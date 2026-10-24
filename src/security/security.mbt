// OAuth2 password bearer flow — FastAPI's `OAuth2PasswordBearer` + `Security`.
// A token endpoint reads an `OAuth2PasswordRequestForm` off the urlencoded body
// and issues an HS256 JWT; a protected route hands its request to a `Security`
// value, which pulls the `Authorization: Bearer <token>` header, verifies the
// JWT, checks the required scopes, and either yields the authenticated user or
// the 401/403 response to return. With no reflection there's no auto-injection,
// so the handler asks the `Security` explicitly and matches the `Result` — the
// same shape as axum extractors or Go middleware that stashes the claims.

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
    Some(String(s)) => @ctx.split_scopes(s)
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
/// A `401 Unauthorized` with a `WWW-Authenticate` challenge and a
/// `{"detail": ...}` body — FastAPI's response for a missing or invalid
/// credential. RFC 9110 §15.5.2 requires the challenge, so it is a parameter:
/// `Basic realm="…"` for Basic, `Bearer scope="…"` for a scoped bearer route.
pub fn unauthorized(
  detail : String,
  challenge~ : String = "Bearer",
) -> @moonasgi.Response {
  let body : Map[String, Json] = Map([("detail", Json(detail))])
  @moonasgi.Response::new(
    401,
    [("content-type", "application/json"), ("www-authenticate", challenge)],
    @moonjson.dump(Json(body)),
  )
}

///|
/// A `403 Forbidden` with a `{"detail": ...}` body — returned when the token is
/// valid but lacks a required scope. The token authenticated the caller, so this
/// is authorization, not authentication: 403, not 401.
pub fn forbidden(detail : String) -> @moonasgi.Response {
  let body : Map[String, Json] = Map([("detail", Json(detail))])
  @moonasgi.Response::new(
    403,
    [("content-type", "application/json")],
    @moonjson.dump(Json(body)),
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
  ctx : @ctx.Context,
  now_secs : Int64,
  scopes~ : Array[String] = [],
) -> Result[AuthenticatedUser, @moonasgi.Response] {
  verify_bearer(ctx, self.secret, SecurityScopes::new(scopes~), now_secs, true)
}

// -- token issuance -----------------------------------------------------------

///|
/// Mint an HS256 access token for `subject` (← FastAPI's `create_access_token`).
/// Stamps `sub`, `iat` (= `now_secs`), `exp` (= `now_secs + expires_in_secs`),
/// and, when non-empty, `scopes`; `extra` merges in any further claims. Times are
/// Unix seconds. `secret` is the shared HS256 key.
///
/// `extra` adds claims. Where it names one the arguments already set — `sub`,
/// `iat`, `exp`, `scopes` — the arguments win and saying it twice aborts, because
/// a token whose subject is not the `subject` passed in is a mistake in the
/// program rather than a choice about configuration. `wins=Extra` hands the
/// decision to `extra`, and `clash` can silence it or take a callback.
pub fn create_access_token(
  subject : String,
  secret : String,
  now_secs : Int64,
  scopes~ : Array[String] = [],
  expires_in_secs~ : Int64 = 3600,
  extra~ : Map[String, Json] = Map([]),
  wins~ : @jwt.Wins = Base,
  clash~ : @jwt.OnClash[Map[String, Json]] = Panic,
) -> String {
  // `iat` / `exp` are RFC 7519 NumericDates — JSON numbers, so an off-the-shelf
  // verifier reads them (`Int64::to_json` would emit a string).
  let base : Map[String, Json] = Map([])
  base["sub"] = Json(subject)
  base["iat"] = Json(now_secs.to_double())
  base["exp"] = Json((now_secs + expires_in_secs).to_double())
  if scopes.length() > 0 {
    let arr : Array[Json] = []
    for s in scopes {
      arr.push(Json(s))
    }
    base["scopes"] = Json(arr)
  }
  let merged : Map[String, Json] = Map([])
  for k, v in base {
    merged[k] = v
  }
  let mut clashed = false
  for k, v in extra {
    if base.get(k) is Some(_) {
      clashed = true
      if wins is Base {
        continue
      }
    }
    merged[k] = v
  }
  let claims = if clashed {
    match clash {
      Ignore => merged
      Panic =>
        abort(
          "create_access_token: `extra` names a claim the arguments already set",
        )
      Handle(decide) => decide(base, merged)
    }
  } else {
    merged
  }
  @jwt.sign(claims, HS256, hs256(secret))
}

///|
/// The `200` token response body `{"access_token": ..., "token_type": "bearer"}`
/// — the OAuth2 password-grant reply FastAPI's token endpoint returns.
pub fn token_response(access_token : String) -> @moonasgi.Response {
  let body : Map[String, Json] = Map([
    ("access_token", Json(access_token)),
    ("token_type", Json("bearer")),
  ])
  @status.json(200, Json(body))
}
