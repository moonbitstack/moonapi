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
/// The scopes a route required at the point its security guard runs (← FastAPI's
/// `SecurityScopes`). A guard reads them to check what the caller was granted
/// and to build the `WWW-Authenticate` challenge a `401` owes the client.
pub struct SecurityScopes {
  scopes : Array[String]
}

///|
/// The scopes required at one call site; empty means authentication only.
pub fn SecurityScopes::new(scopes~ : Array[String] = []) -> SecurityScopes {
  { scopes, }
}

///|
/// The required scopes, in declaration order.
pub fn SecurityScopes::list(self : SecurityScopes) -> Array[String] {
  self.scopes
}

///|
/// The scopes as OAuth2's single space-delimited string (← `SecurityScopes.scope_str`).
pub fn SecurityScopes::scope_str(self : SecurityScopes) -> String {
  self.scopes.join(" ")
}

///|
/// The `WWW-Authenticate` value a bearer challenge carries: `Bearer` on its own,
/// or `Bearer scope="a b"` when the route requires scopes, which is how RFC 6750
/// §3 tells a client what it was missing.
pub fn SecurityScopes::challenge(self : SecurityScopes) -> String {
  if self.scopes.is_empty() {
    "Bearer"
  } else {
    "Bearer scope=\"" + self.scope_str() + "\""
  }
}

///|
/// The caller an `auto_error=false` guard admits: no subject, no scopes, no
/// claims. FastAPI's `auto_error=False` hands the route `None` and lets it
/// decide; the route here sees a caller it knows nothing about.
pub fn anonymous() -> AuthenticatedUser {
  { subject: "", scopes: [], claims: Map([]), }
}

///|
/// Admit an unauthenticated caller, or refuse with `denied` — the one place
/// `auto_error` is decided, so every guard reads the flag the same way.
pub fn refuse(
  auto_error : Bool,
  denied : () -> @moonasgi.Response,
) -> Result[AuthenticatedUser, @moonasgi.Response] {
  if auto_error {
    Err(denied())
  } else {
    Ok(anonymous())
  }
}

// -- bearer tokens ------------------------------------------------------------

///|
/// The guard every JWT-verified scheme shares — the OAuth2 password and
/// authorization-code flows, a plain HTTP bearer, and OpenID Connect all present
/// the same `Authorization: Bearer <jwt>` credential. Pulls the token, verifies
/// it against `secret` at `now`, then checks the scopes the route required.
pub fn verify_bearer(
  ctx : @ctx.Context,
  secret : String,
  scopes : SecurityScopes,
  now : Int64,
  auto_error : Bool,
) -> Result[AuthenticatedUser, @moonasgi.Response] {
  let token = match ctx.bearer_token() {
    None =>
      return refuse(auto_error, () => {
        unauthorized("Not authenticated", challenge=scopes.challenge())
      })
    Some(t) => t
  }
  let claims = @jwt.verify(token[:], HS256, hs256(secret), now=At(now)) catch {
    _ =>
      return refuse(auto_error, () => {
        unauthorized(
          "Could not validate credentials",
          challenge=scopes.challenge(),
        )
      })
  }
  let user : AuthenticatedUser = {
    subject: subject_from_claims(claims),
    scopes: scopes_from_claims(claims),
    claims,
  }
  for required in scopes.scopes {
    if !user.has_scope(required) {
      // The token authenticated the caller, so this is authorization: 403, not 401.
      return refuse(auto_error, () => forbidden("Not enough permissions"))
    }
  }
  Ok(user)
}

///|
/// An OAuth2 authorization-code bearer scheme (← FastAPI's
/// `OAuth2AuthorizationCodeBearer`): the `authorization_url` a browser is sent
/// to, the `token_url` the code is exchanged at, an optional `refresh_url`, and
/// the shared HS256 `secret` a presented token is verified against.
pub struct OAuth2CodeBearer {
  authorization_url : String
  token_url : String
  refresh_url : String
  secret : String
}

///|
/// Build an authorization-code bearer scheme. `refresh_url` is left out of the
/// document when empty, since a provider that offers no refresh endpoint should
/// not be described as having one.
pub fn OAuth2CodeBearer::new(
  authorization_url : String,
  token_url : String,
  secret : String,
  refresh_url~ : String = "",
) -> OAuth2CodeBearer {
  { authorization_url, token_url, refresh_url, secret, }
}

///|
/// The security scheme that describes this flow, advertising `scopes`.
pub fn OAuth2CodeBearer::scheme(
  self : OAuth2CodeBearer,
  scopes~ : Array[(String, String)] = [],
) -> SecurityScheme {
  OAuth2Code(
    authorization_url=self.authorization_url,
    token_url=self.token_url,
    refresh_url=self.refresh_url,
    scopes~,
  )
}

// -- API keys -----------------------------------------------------------------

///|
/// Where an API key travels (← `APIKeyHeader` / `APIKeyQuery` / `APIKeyCookie`).
pub(all) enum ApiKeyIn {
  KeyHeader
  KeyQuery
  KeyCookie
} derive(Eq)

///|
/// An API-key scheme: the parameter `name` the key arrives under, where it
/// arrives, and the predicate that accepts a presented key. FastAPI's
/// `APIKeyHeader` only extracts and leaves the check to a dependency; a route
/// guard needs both, so the check travels with the scheme.
pub struct ApiKey {
  loc : ApiKeyIn
  name : String
  verify : (String) -> Bool
}

///|
/// An API key read from the request header `name` (← `APIKeyHeader`).
pub fn ApiKey::header(name : String, verify : (String) -> Bool) -> ApiKey {
  { loc: KeyHeader, name, verify, }
}

///|
/// An API key read from the query parameter `name` (← `APIKeyQuery`).
pub fn ApiKey::query(name : String, verify : (String) -> Bool) -> ApiKey {
  { loc: KeyQuery, name, verify, }
}

///|
/// An API key read from the cookie `name` (← `APIKeyCookie`).
pub fn ApiKey::cookie(name : String, verify : (String) -> Bool) -> ApiKey {
  { loc: KeyCookie, name, verify, }
}

///|
/// The key this request presents for the scheme, `None` when it carries none.
pub fn ApiKey::read(self : ApiKey, ctx : @ctx.Context) -> String? {
  match self.loc {
    KeyHeader => ctx.api_key_header(self.name)
    KeyQuery => ctx.api_key_query(self.name)
    KeyCookie => ctx.api_key_cookie(self.name)
  }
}

///|
/// The `apiKey` scheme object this key is documented as.
pub fn ApiKey::scheme(self : ApiKey) -> SecurityScheme {
  match self.loc {
    KeyHeader => ApiKeyHeader(name=self.name)
    KeyQuery => ApiKeyQuery(name=self.name)
    KeyCookie => ApiKeyCookie(name=self.name)
  }
}

///|
/// An HTTP Basic scheme (← FastAPI's `HTTPBasic`): the `realm` named in the
/// challenge, and the predicate that accepts a presented username/password.
pub struct BasicAuth {
  realm : String
  verify : (@ctx.HttpBasicCredentials) -> Bool
}

///|
/// Build an HTTP Basic scheme. A `realm` is optional and, when given, names the
/// protection space in the challenge so a browser can tell one login from
/// another.
pub fn BasicAuth::new(
  verify : (@ctx.HttpBasicCredentials) -> Bool,
  realm~ : String = "",
) -> BasicAuth {
  { realm, verify, }
}

///|
/// The `WWW-Authenticate` value this scheme challenges with.
pub fn BasicAuth::challenge(self : BasicAuth) -> String {
  auth_challenge("Basic", self.realm)
}

///|
/// An HTTP Digest scheme (← FastAPI's `HTTPDigest`, which likewise carries the
/// credential and no more): `verify` decides whether the `Digest` parameter
/// string a client sent is acceptable. Computing the RFC 7616 response digest is
/// the application's, since only it holds the password store.
pub struct DigestAuth {
  realm : String
  verify : (String) -> Bool
}

///|
/// Build an HTTP Digest scheme, optionally naming the protection `realm`.
pub fn DigestAuth::new(
  verify : (String) -> Bool,
  realm~ : String = "",
) -> DigestAuth {
  { realm, verify, }
}

///|
/// The `WWW-Authenticate` value this scheme challenges with.
pub fn DigestAuth::challenge(self : DigestAuth) -> String {
  auth_challenge("Digest", self.realm)
}

///|
/// A `WWW-Authenticate` value for `scheme`, carrying `realm` when there is one.
fn auth_challenge(scheme : String, realm : String) -> String {
  if realm == "" {
    scheme
  } else {
    scheme + " realm=\"" + realm + "\""
  }
}

///|
pub extend ApiKeyIn with Eq::{not_equal, equal}
