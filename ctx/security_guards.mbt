// The enforcement half of the security schemes. `security_scheme.mbt` describes
// a scheme to clients; this is what stands in front of a route that names it —
// FastAPI's `Security(APIKeyHeader(...))`, `Security(HTTPBasic())` and friends,
// which are a declaration and a guard at once. Every guard here answers the same
// question the OAuth2 one does: given a request, the scopes the route asked for
// and the verification time, is this caller admitted, and if not, with what.
//
// `auto_error` is FastAPI's, and means the same: with it off, a missing or bad
// credential does not refuse the request — the guard yields an anonymous caller
// and the route decides for itself, reading the credential through the
// `Context` extractors.

///|
/// The credential of an `Authorization: Digest <parameters>` header — the
/// comma-separated parameter list, verbatim (← FastAPI's `HTTPDigest`). `None`
/// when the header is absent or names another scheme; the scheme name is matched
/// case-insensitively, as RFC 7235 requires.
pub fn Context::digest_credentials(self : Context) -> String? {
  match self.request.header("authorization") {
    None => None
    Some(h) => {
      let trimmed = trim_spaces(h)
      let prefix = "digest "
      guard trimmed.length() >= prefix.length() else { None }
      guard trimmed[0:prefix.length()].to_owned().to_lower() == prefix else {
        None
      }
      Some(trim_spaces(trimmed[prefix.length():].to_owned()))
    }
  }
}
