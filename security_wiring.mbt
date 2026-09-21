// Per-operation security (← FastAPI wiring a `Security(scheme, scopes=[...])`
// onto a route). A `SecurityScheme` declared on the app describes *how* to
// authenticate; a `SecurityRequirement` attached to a route says *this* route
// needs *that* scheme with *these* scopes. Two things follow: the requirement
// is emitted as the operation's OpenAPI `security` array, and — when the scheme
// was registered with an enforcer (`App::secure_oauth2`) — the app runs the
// enforcer before the handler and short-circuits with 401/403 if it fails. The
// declaration is the single source of both the document and the guard.

///|
/// A security requirement on a route: the `scheme` name (which must match a name
/// declared with `App::add_security_scheme` / `App::secure_oauth2`) and the
/// `scopes` the caller must hold. Emitted as one `{scheme: [scopes]}` entry of
/// the operation's OpenAPI `security` array.
pub(all) struct SecurityRequirement {
  scheme : String
  scopes : Array[String]
} derive(Eq)

///|
/// Require `scheme` with the given `scopes` (default: none — authentication with
/// no scope check). `App::get(..., security=[SecurityRequirement::new("OAuth2",
/// scopes=["items"])])` reads like FastAPI's `Security(oauth2, scopes=["items"])`.
pub fn SecurityRequirement::new(
  scheme : String,
  scopes? : Array[String] = [],
) -> SecurityRequirement {
  { scheme, scopes, }
}

///|
/// The runtime guard behind a named scheme: given the request context, the
/// scopes the route required at this call site, and the verification time (Unix
/// seconds), either the authenticated user or the 401/403 response to return.
/// Registered by the `App::secure_*` functions; a documentation-only scheme (a
/// bare `add_security_scheme`) has none, so it is described in the spec but not
/// enforced — exactly FastAPI's split between a declared scheme and a wired
/// dependency.
type SecurityEnforcer = (Context, SecurityScopes, Int64) -> Result[
  AuthenticatedUser,
  @moonasgi.Response,
]

///|
/// This requirement as its OpenAPI `security` entry: `{scheme: [scope, ...]}`.
fn SecurityRequirement::to_json(self : SecurityRequirement) -> Json {
  let arr : Array[Json] = []
  for s in self.scopes {
    arr.push(s.to_json())
  }
  let m : Map[String, Json] = Map([(self.scheme, arr.to_json())])
  m.to_json()
}

///|
/// The `security` array for a route's requirements, or `None` when the route
/// declares none (so the key is omitted rather than emitted empty).
fn security_json(reqs : Array[SecurityRequirement]) -> Json? {
  if reqs.is_empty() {
    return None
  }
  let arr : Array[Json] = []
  for r in reqs {
    arr.push(r.to_json())
  }
  Some(arr.to_json())
}

///|
pub extend SecurityRequirement with Eq::{not_equal, equal}
