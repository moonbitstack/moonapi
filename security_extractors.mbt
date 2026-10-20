// The non-OAuth2 security schemes' runtime extractors (← FastAPI's `HTTPBasic` and
// `APIKeyHeader` / `APIKeyQuery` / `APIKeyCookie`). `security_scheme.mbt` already describes these to
// clients under `securitySchemes`; this is the enforcement side — pulling the credential off the
// request so a route can authenticate against it, the same way `Context::bearer_token` does for
// OAuth2.

///|
/// The credentials carried in an HTTP Basic `Authorization` header (← FastAPI's
/// `HTTPBasicCredentials`): the username and password from `base64(username:password)`.
pub(all) struct HttpBasicCredentials {
  username : String
  password : String
}

///|
/// The index of the first `:` in `s`, or `-1`.
fn first_colon(s : String) -> Int32 {
  for i = 0; i < s.length(); i = i + 1 {
    if s[i] == ':' {
      return i
    }
  }
  -1
}

///|
/// Parse an HTTP Basic `Authorization` header value into credentials (← FastAPI's `HTTPBasic`),
/// or `None`. Matches the `Basic` scheme case-insensitively (RFC 7617), base64-decodes the rest, and
/// splits on the first colon so a password may itself contain colons.
pub fn parse_basic_auth(header : String) -> HttpBasicCredentials? {
  let trimmed = trim_spaces(header)
  let prefix = "basic "
  guard trimmed.length() >= prefix.length() else { return None }
  guard trimmed[0:prefix.length()].to_owned().to_lower() == prefix else {
    return None
  }
  let encoded = trim_spaces(trimmed[prefix.length():].to_owned())
  let decoded = @utf8.decode_lossy(@base64.decode_lossy(encoded)[:])
  let colon = first_colon(decoded)
  guard colon >= 0 else { return None }
  Some({
    username: decoded[0:colon].to_owned(),
    password: decoded[colon + 1:].to_owned(),
  })
}

///|
/// The HTTP Basic credentials on this request (← FastAPI's `HTTPBasic` dependency), or `None`.
pub fn Context::http_basic(self : Context) -> HttpBasicCredentials? {
  match self.request.header("authorization") {
    Some(h) => parse_basic_auth(h)
    None => None
  }
}

///|
/// The API key carried in the request header `name` (← FastAPI's `APIKeyHeader`), or `None`. Header
/// names are matched against the request's lower-cased headers.
pub fn Context::api_key_header(self : Context, name : String) -> String? {
  self.request.header(name.to_lower())
}

///|
/// The API key carried in the query parameter `name` (← FastAPI's `APIKeyQuery`), or `None`.
pub fn Context::api_key_query(self : Context, name : String) -> String? {
  self.query(name)
}

///|
/// The API key carried in the cookie `name` (← FastAPI's `APIKeyCookie`), or `None`.
pub fn Context::api_key_cookie(self : Context, name : String) -> String? {
  self.cookie(name)
}
