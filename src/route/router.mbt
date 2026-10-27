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
  ws_routes : Array[@socket.WsRoute]
}

///|
/// An empty router. The prefix and the attributes its routes share are given at
/// `App::include_router` rather than here, so one router can be included twice
/// — under a second prefix, or on another app with different tags.
pub fn Router::new() -> Router {
  { routes: [], ws_routes: [], }
}

///|
/// Register a WebSocket route on the router (← `APIRouter.websocket`). It takes
/// the including prefix like any other route; the operation attributes do not
/// apply, since a WebSocket route is not an OpenAPI operation.
pub fn Router::websocket(
  self : Router,
  path : String,
  handler : @socket.WsHandler,
) -> Unit {
  self.ws_routes.push({ path, handler, })
}
