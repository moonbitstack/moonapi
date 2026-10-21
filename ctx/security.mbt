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
pub fn split_scopes(s : String) -> Array[String] {
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
pub extend OAuth2PasswordRequestForm with Eq::{not_equal, equal}
