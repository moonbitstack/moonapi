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
/// Declare an API-key scheme under `name` and wire it as a runtime enforcer (←
/// FastAPI's `Security(APIKeyHeader(name=...))`). The scheme appears in the
/// document as `apiKey` in the header, query or cookie the `key` names, and a
/// route requiring `name` is refused with `403` unless it presents a key the
/// scheme accepts.
pub fn App::secure_api_key(
  self : App,
  name : String,
  key : @security.ApiKey,
  description~ : String = "",
  auto_error~ : Bool = true,
) -> Unit {
  self.security_schemes.push({ name, kind: key.scheme(), description, })
  self.enforcers[name] = (ctx, _scopes, _now) => {
    verify_api_key(key, ctx, auto_error)
  }
}

///|
/// Declare an HTTP Basic scheme under `name` and wire it as a runtime enforcer
/// (← `Security(HTTPBasic())`). A route requiring `name` is refused with `401`
/// and a `Basic` challenge unless it presents credentials the scheme accepts.
pub fn App::secure_basic(
  self : App,
  name : String,
  basic : @security.BasicAuth,
  description~ : String = "",
  auto_error~ : Bool = true,
) -> Unit {
  self.security_schemes.push({ name, kind: @security.HttpBasic, description, })
  self.enforcers[name] = (ctx, _scopes, _now) => {
    verify_basic(basic, ctx, auto_error)
  }
}

///|
/// Declare an HTTP Digest scheme under `name` and wire it as a runtime enforcer
/// (← `Security(HTTPDigest())`). A route requiring `name` is refused with `403`
/// unless it presents a `Digest` credential the scheme accepts.
pub fn App::secure_digest(
  self : App,
  name : String,
  digest : @security.DigestAuth,
  description~ : String = "",
  auto_error~ : Bool = true,
) -> Unit {
  self.security_schemes.push({ name, kind: @security.HttpDigest, description, })
  self.enforcers[name] = (ctx, _scopes, _now) => {
    verify_digest(digest, ctx, auto_error)
  }
}

///|
/// Declare a plain HTTP bearer scheme under `name` and wire it as a runtime
/// enforcer (← `Security(HTTPBearer())`). The token is verified as an HS256 JWT
/// against `secret` at the app clock's time, and the route's required scopes are
/// checked against the token's — the same guard the OAuth2 flows use, without an
/// OAuth2 flow to advertise.
pub fn App::secure_bearer(
  self : App,
  name : String,
  secret : String,
  bearer_format~ : String = "JWT",
  description~ : String = "",
  auto_error~ : Bool = true,
) -> Unit {
  self.security_schemes.push({
    name,
    kind: @security.HttpBearer(bearer_format~),
    description,
  })
  self.enforcers[name] = (ctx, scopes, now) => {
    @security.verify_bearer(ctx, secret, scopes, now, auto_error)
  }
}

///|
/// Declare an OAuth2 authorization-code scheme under `name` and wire it as a
/// runtime enforcer (← `Security(OAuth2AuthorizationCodeBearer(...))`). The
/// document describes the browser redirect and token endpoints and the
/// advertised `scopes`; the guard verifies the presented bearer token exactly as
/// the password flow's does, since by the time a request arrives the two flows
/// have produced the same credential.
pub fn App::secure_oauth2_code(
  self : App,
  name : String,
  code : @security.OAuth2CodeBearer,
  scopes~ : Array[(String, String)] = [],
  description~ : String = "",
  auto_error~ : Bool = true,
) -> Unit {
  self.security_schemes.push({ name, kind: code.scheme(scopes~), description, })
  self.enforcers[name] = (ctx, required, now) => {
    @security.verify_bearer(ctx, code.secret, required, now, auto_error)
  }
}

///|
/// Declare an OpenID Connect scheme under `name` and wire it as a runtime
/// enforcer (← `Security(OpenIdConnect(openIdConnectUrl=...))`). `url` is the
/// discovery document a client reads every other parameter from; `secret` is
/// what the ID token presented as a bearer credential is verified against.
///
/// Swagger 2.0 has no `openIdConnect` type, so this scheme is absent from a 2.0
/// document rather than described as something it is not.
pub fn App::secure_openid(
  self : App,
  name : String,
  url : String,
  secret : String,
  description~ : String = "",
  auto_error~ : Bool = true,
) -> Unit {
  self.security_schemes.push({
    name,
    kind: @security.OpenIdConnect(url~),
    description,
  })
  self.enforcers[name] = (ctx, scopes, now) => {
    @security.verify_bearer(ctx, secret, scopes, now, auto_error)
  }
}

///|
/// The guard behind a declared API-key scheme.
fn verify_api_key(
  key : @security.ApiKey,
  ctx : @ctx.Context,
  auto_error : Bool,
) -> Result[@security.AuthenticatedUser, @moonasgi.Response] {
  match key.read(ctx) {
    None =>
      @security.refuse(auto_error, () => api_key_denied("Not authenticated"))
    Some(presented) =>
      if (key.verify)(presented) {
        // The key *is* the identity here, exactly as FastAPI's `APIKeyHeader`
        // dependency yields the key itself to the route.
        Ok({ subject: presented, scopes: [], claims: Map([]), })
      } else {
        @security.refuse(auto_error, () => {
          api_key_denied("Invalid authentication credentials")
        })
      }
  }
}

// -- HTTP basic and digest ----------------------------------------------------

///|
/// The guard behind a declared HTTP Basic scheme.
fn verify_basic(
  basic : @security.BasicAuth,
  ctx : @ctx.Context,
  auto_error : Bool,
) -> Result[@security.AuthenticatedUser, @moonasgi.Response] {
  match ctx.http_basic() {
    None =>
      @security.refuse(auto_error, () => {
        @security.unauthorized("Not authenticated", challenge=basic.challenge())
      })
    Some(cred) =>
      if (basic.verify)(cred) {
        Ok({ subject: cred.username, scopes: [], claims: Map([]), })
      } else {
        @security.refuse(auto_error, () => {
          @security.unauthorized(
            "Incorrect username or password",
            challenge=basic.challenge(),
          )
        })
      }
  }
}

///|
/// The guard behind a declared HTTP Digest scheme. Like FastAPI's `HTTPDigest`
/// it answers `403`, since a digest challenge a server cannot yet build a nonce
/// for is no challenge at all.
fn verify_digest(
  digest : @security.DigestAuth,
  ctx : @ctx.Context,
  auto_error : Bool,
) -> Result[@security.AuthenticatedUser, @moonasgi.Response] {
  match ctx.digest_credentials() {
    None =>
      @security.refuse(auto_error, () => {
        @security.forbidden("Not authenticated")
      })
    Some(cred) =>
      if (digest.verify)(cred) {
        Ok(@security.anonymous())
      } else {
        @security.refuse(auto_error, () => {
          @security.forbidden("Invalid authentication credentials")
        })
      }
  }
}

// -- wiring a scheme onto an app ----------------------------------------------

///|
/// Refuse a request that presented no acceptable API key. FastAPI's API-key
/// classes answer `403`, not `401`, because an `apiKey` scheme has no
/// `WWW-Authenticate` challenge to offer and a `401` without one is malformed.
fn api_key_denied(detail : String) -> @moonasgi.Response {
  @security.forbidden(detail)
}
