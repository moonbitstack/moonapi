// FastAPI's `APIRouter` + `include_router`: routes written away from any
// application and folded into one later, so a large API can be split by feature
// without every piece having to know the app it ends up on — and so the
// attributes a whole group shares (a prefix, tags, a security requirement) are
// stated once at the join rather than copied onto every route.
//
// `App::mount` is the other composition primitive and answers a different
// question: a mount stays a separate application behind a prefix, with its own
// middleware and lifespan, while an included router's routes become the parent's
// own — indistinguishable, afterwards, from routes registered on it directly.

///|
/// Fold `router`'s routes into this app (FastAPI's `include_router`, and the
/// same name — `include` is a reserved word). Each is registered under `prefix`
/// and becomes one of the app's own routes, and the arguments given here reach
/// every one of them:
///
/// - `tags`, `security` and `dependencies` are placed before the route's own, so
///   a group's tag leads and a group-wide requirement or dependency cannot be
///   dropped by a route that adds one of its own;
/// - `responses` are documented under the route's, which therefore wins any
///   status both name;
/// - `deprecated` marks the whole group, and `include_in_schema=false` hides it,
///   neither of which a route can undo.
pub fn App::include_router(
  self : App,
  router : @route.Router,
  prefix~ : String = "",
  tags~ : Array[String] = [],
  security~ : Array[@security.SecurityRequirement] = [],
  dependencies~ : Array[String] = [],
  responses~ : Array[@endpoint.ResponseSpec] = [],
  deprecated~ : Bool = false,
  include_in_schema~ : Bool = true,
) -> Unit {
  for r in router.routes {
    self.routes.push({
      ..r,
      path: join_prefix(prefix, r.path),
      tags: [..tags, ..r.tags],
      security: [..security, ..r.security],
      dependencies: [..dependencies, ..r.dependencies],
      responses: [..responses, ..r.responses],
      deprecated: deprecated || r.deprecated,
      include_in_schema: include_in_schema && r.include_in_schema,
    })
  }
  for w in router.ws_routes {
    self.ws_routes.push({ ..w, path: join_prefix(prefix, w.path), })
  }
}
