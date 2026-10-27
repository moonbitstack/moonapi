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
/// A collection of routes built away from any application and folded into one
/// with `App::include_router` (← FastAPI's `APIRouter`). It carries the registration
/// surface of an `App` and nothing else: middleware, mounts, security schemes,
/// documentation and lifespan belong to the application that includes it.
pub struct Router {
  routes : Array[Route]
  ws_routes : Array[WsRoute]
  hoops : Array[Hoop]
}

///|
/// An empty router. The prefix and the attributes its routes share are given at
/// `include_router` rather than here, so one router can be included twice —
/// under a second prefix, or on another app with different tags.
pub fn Router::new() -> Router {
  { routes: [], ws_routes: [], hoops: [], }
}

///|
/// Put `hoop` around every route of this router (← Salvo's `Router::hoop`). The
/// router's hoops reach its routes when it is included, outside each route's own,
/// in the order they were added.
pub fn Router::hoop(self : Router, hoop : Hoop) -> Unit {
  self.hoops.push(hoop)
}

///|
/// Fold `router`'s routes into this one under `prefix` (← FastAPI's
/// `APIRouter.include_router`), so routers nest into a tree and the tree is
/// included into an app once. The arguments reach every route folded in:
///
/// - `tags`, `security`, `dependencies` and `hoops` are placed before the
///   route's own, so a group's tag leads and a group-wide requirement,
///   dependency or hoop cannot be dropped by a route that adds one of its own;
///   `router`'s own hoops come between the two;
/// - `responses` are documented under the route's, which therefore wins any
///   status both name;
/// - `deprecated` marks the whole group, and `include_in_schema=false` hides it,
///   neither of which a route can undo.
///
/// WebSocket routes take the prefix, the security and the dependencies.
pub fn Router::include_router(
  self : Router,
  router : Router,
  prefix~ : String = "",
  tags~ : Array[String] = [],
  security~ : Array[@security.SecurityRequirement] = [],
  dependencies~ : Array[String] = [],
  responses~ : Array[@endpoint.ResponseSpec] = [],
  deprecated~ : Bool = false,
  include_in_schema~ : Bool = true,
  hoops~ : Array[Hoop] = [],
) -> Unit {
  for r in router.routes {
    let path = join_prefix(prefix, r.path)
    self.routes.push({
      ..r,
      path,
      pattern: Pattern::parse(path),
      tags: [..tags, ..r.tags],
      security: [..security, ..r.security],
      dependencies: [..dependencies, ..r.dependencies],
      responses: [..responses, ..r.responses],
      deprecated: deprecated || r.deprecated,
      include_in_schema: include_in_schema && r.include_in_schema,
      hoops: [..hoops, ..router.hoops, ..r.hoops],
    })
  }
  for w in router.ws_routes {
    let path = join_prefix(prefix, w.path)
    self.ws_routes.push({
      ..w,
      path,
      pattern: Pattern::parse(path),
      security: [..security, ..w.security],
      dependencies: [..dependencies, ..w.dependencies],
    })
  }
}

///|
/// Register a WebSocket route on the router (← `APIRouter.websocket`). It takes
/// the including prefix like any other route. `security` and `dependencies` are
/// checked before the handler runs, as on an HTTP route, and a refusal declines
/// the handshake; `name` is the handle `App::url_for` resolves. The OpenAPI
/// attributes do not apply, since a WebSocket route is not an operation.
pub fn Router::websocket(
  self : Router,
  path : String,
  handler : @socket.WsHandler,
  name~ : String = "",
  security~ : Array[@security.SecurityRequirement] = [],
  dependencies~ : Array[String] = [],
) -> Unit {
  self.ws_routes.push({
    path,
    pattern: Pattern::parse(path),
    handler,
    name,
    security,
    dependencies,
  })
}
