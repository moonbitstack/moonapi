// OAuth2 password bearer flow — FastAPI's `OAuth2PasswordBearer` + `Security`.
// A token endpoint reads an `OAuth2PasswordRequestForm` off the urlencoded body
// and issues an HS256 JWT; a protected route hands its request to a `Security`
// value, which pulls the `Authorization: Bearer <token>` header, verifies the
// JWT, checks the required scopes, and either yields the authenticated user or
// the 401/403 response to return. With no reflection there's no auto-injection,
// so the handler asks the `Security` explicitly and matches the `Result` — the
// same shape as axum extractors or Go middleware that stashes the claims.

///|
/// The parsed OAuth2 password-grant form (← FastAPI's `OAuth2PasswordRequestForm`).
/// The token endpoint reads `username` / `password` to authenticate and `scopes`
/// (the space-delimited `scope` field, split into a list) to stamp into the
/// issued token. `grant_type` is `"password"` for this flow; `client_id` /
/// `client_secret` are optional confidential-client credentials.
pub(all) struct OAuth2PasswordRequestForm {
  grant_type : String
  username : String
  password : String
  scopes : Array[String]
  client_id : String?
  client_secret : String?
} derive(Eq)

///|
/// Split a space-delimited scope string into its scopes, dropping empty runs —
/// the OAuth2 `scope` form field is one string like `"read write"`.
fn split_scopes(s : String) -> Array[String] {
  let out : Array[String] = []
  let sb = StringBuilder()
  for i = 0; i < s.length(); i = i + 1 {
    if s[i].to_int() == 0x20 {
      if sb.to_string() != "" {
        out.push(sb.to_string())
      }
      sb.reset()
    } else {
      sb.write_char(s[i].unsafe_to_char())
    }
  }
  if sb.to_string() != "" {
    out.push(sb.to_string())
  }
  out
}

///|
/// Read an `OAuth2PasswordRequestForm` off the request's urlencoded (or
/// multipart) body. `None` when neither `username` nor `password` is present —
/// the body isn't a password-grant form at all — and equally when the body is
/// too large to be one, since a grant carries six fields and nothing that big
/// is a login.
pub fn Context::oauth2_password_form(
  self : Context,
) -> OAuth2PasswordRequestForm? {
  let form = match self.form() {
    Some(f) => f
    None => return None
  }
  let username = form.field("username")
  let password = form.field("password")
  match (username, password) {
    (None, None) => None
    _ => {
      let scope = form.field("scope").unwrap_or("")
      Some({
        grant_type: form.field("grant_type").unwrap_or(""),
        username: username.unwrap_or(""),
        password: password.unwrap_or(""),
        scopes: split_scopes(scope),
        client_id: form.field("client_id"),
        client_secret: form.field("client_secret"),
      })
    }
  }
}

///|
/// The identity a verified token carries, injected into a protected handler
/// (← the object FastAPI's `get_current_user` returns). `subject` is the `sub`
/// claim, `scopes` the granted scopes, and `claims` the whole verified payload
/// for anything else the handler needs (`exp`, custom claims).
pub(all) struct AuthenticatedUser {
  subject : String
  scopes : Array[String]
  claims : Map[String, Json]
}

///|
/// Whether this user was granted `scope`.
pub fn AuthenticatedUser::has_scope(
  self : AuthenticatedUser,
  scope : String,
) -> Bool {
  self.scopes.contains(scope)
}

///|
/// Read the `scopes` claim, accepting either a JSON array of strings or a single
/// space-delimited string (both are seen in the wild). Absent -> no scopes.
fn scopes_from_claims(claims : Map[String, Json]) -> Array[String] {
  match claims.get("scopes") {
    Some(Array(a)) => {
      let out : Array[String] = []
      for v in a {
        match v {
          String(s) => out.push(s)
          _ => ()
        }
      }
      out
    }
    Some(String(s)) => split_scopes(s)
    _ => []
  }
}

///|
/// The `sub` claim as a string, `""` if absent or non-string.
fn subject_from_claims(claims : Map[String, Json]) -> String {
  match claims.get("sub") {
    Some(String(s)) => s
    _ => ""
  }
}

///|
/// An OAuth2 password-bearer security scheme (← FastAPI's `OAuth2PasswordBearer`).
/// Holds the `token_url` (the endpoint that issues tokens, surfaced to API docs)
/// and the shared HS256 `secret` used to verify presented tokens.
pub(all) struct OAuth2PasswordBearer {
  token_url : String
  secret : String
}

///|
/// Build a password-bearer scheme pointing at the token endpoint at `token_url`,
/// verifying tokens with `secret`.
pub fn OAuth2PasswordBearer::new(
  token_url : String,
  secret : String,
) -> OAuth2PasswordBearer {
  { token_url, secret, }
}

///|
/// Pull the bearer token out of the `Authorization: Bearer <token>` header,
/// `None` if the header is absent or isn't a bearer credential. The scheme name
/// is matched case-insensitively, as RFC 6750 requires.
pub fn Context::bearer_token(self : Context) -> String? {
  match self.request.header("authorization") {
    None => None
    Some(h) => {
      let trimmed = trim_spaces(h)
      let prefix = "bearer "
      if trimmed.length() < prefix.length() {
        return None
      }
      let scheme = trimmed[0:prefix.length()].to_owned().to_lower()
      if scheme != prefix {
        return None
      }
      Some(trim_spaces(trimmed[prefix.length():].to_owned()))
    }
  }
}

///|
/// A `401 Unauthorized` with a `WWW-Authenticate` challenge and a
/// `{"detail": ...}` body — FastAPI's response for a missing or invalid
/// credential. RFC 9110 §15.5.2 requires the challenge, so it is a parameter:
/// `Basic realm="…"` for Basic, `Bearer scope="…"` for a scoped bearer route.
fn unauthorized(
  detail : String,
  challenge? : String = "Bearer",
) -> @moonasgi.Response {
  let body : Map[String, Json] = Map([("detail", detail.to_json())])
  @moonasgi.Response::new(
    401,
    [("content-type", "application/json"), ("www-authenticate", challenge)],
    @moonjson.write_bytes(body.to_json()),
  )
}

///|
/// A `403 Forbidden` with a `{"detail": ...}` body — returned when the token is
/// valid but lacks a required scope. The token authenticated the caller, so this
/// is authorization, not authentication: 403, not 401.
fn forbidden(detail : String) -> @moonasgi.Response {
  let body : Map[String, Json] = Map([("detail", detail.to_json())])
  @moonasgi.Response::new(
    403,
    [("content-type", "application/json")],
    @moonjson.write_bytes(body.to_json()),
  )
}

///|
/// Authenticate a request against this scheme and enforce `scopes`
/// (← FastAPI's `Security(get_current_user, scopes=[...])`). On success returns
/// the `AuthenticatedUser`; otherwise the response to return:
///
/// - no bearer token -> `401` `{"detail":"Not authenticated"}`
/// - malformed / bad-signature / expired / not-yet-valid token -> `401`
///   `{"detail":"Could not validate credentials"}`
/// - valid token missing a required scope -> `403` `{"detail":"Not enough permissions"}`
///
/// Both `401`s carry the challenge the required scopes describe — `Bearer` on
/// its own, or `Bearer scope="..."` — so a client learns what it should have
/// asked for.
///
/// `now_secs` is the verification time (Unix seconds), passed in so the check
/// stays pure and testable on every backend.
pub fn OAuth2PasswordBearer::authenticate(
  self : OAuth2PasswordBearer,
  ctx : Context,
  now_secs : Int64,
  scopes? : Array[String] = [],
) -> Result[AuthenticatedUser, @moonasgi.Response] {
  verify_bearer(ctx, self.secret, SecurityScopes::new(scopes~), now_secs, true)
}

// -- token issuance -----------------------------------------------------------

///|
/// Mint an HS256 access token for `subject` (← FastAPI's `create_access_token`).
/// Stamps `sub`, `iat` (= `now_secs`), `exp` (= `now_secs + expires_in_secs`),
/// and, when non-empty, `scopes`; `extra` merges in any further claims. Times are
/// Unix seconds. `secret` is the shared HS256 key.
pub fn create_access_token(
  subject : String,
  secret : String,
  now_secs : Int64,
  scopes? : Array[String] = [],
  expires_in_secs? : Int64 = 3600,
  extra? : Map[String, Json] = Map([]),
) -> String {
  let claims : Map[String, Json] = Map([])
  for k, v in extra {
    claims[k] = v
  }
  // `iat` / `exp` are RFC 7519 NumericDates — JSON numbers, so an off-the-shelf
  // verifier reads them (`Int64::to_json` would emit a string).
  claims["sub"] = subject.to_json()
  claims["iat"] = now_secs.to_double().to_json()
  claims["exp"] = (now_secs + expires_in_secs).to_double().to_json()
  if scopes.length() > 0 {
    let arr : Array[Json] = []
    for s in scopes {
      arr.push(s.to_json())
    }
    claims["scopes"] = arr.to_json()
  }
  @jwt.sign(claims, HS256, hs256(secret))
}

///|
/// The `200` token response body `{"access_token": ..., "token_type": "bearer"}`
/// — the OAuth2 password-grant reply FastAPI's token endpoint returns.
pub fn token_response(access_token : String) -> @moonasgi.Response {
  let body : Map[String, Json] = Map([
    ("access_token", access_token.to_json()),
    ("token_type", "bearer".to_json()),
  ])
  json(200, body.to_json())
}

///|
pub extend OAuth2PasswordRequestForm with Eq::{not_equal, equal}
