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
}

///|
/// An empty router. The prefix and the attributes its routes share are given at
/// `App::include_router` rather than here, so one router can be included twice
/// — under a second prefix, or on another app with different tags.
pub fn Router::new() -> Router {
  { routes: [], ws_routes: [], }
}

///|
/// Register a route on the router for an explicit method. Takes what
/// `App::route` takes and means the same by it; the route reaches an application
/// when the router is included.
pub fn Router::route(
  self : Router,
  verb : Method,
  path : String,
  handler : ApiHandler,
  summary? : String = "",
  description? : String = "",
  tags? : Array[String] = [],
  deprecated? : Bool = false,
  operation_id? : String = "",
  status_code? : Int,
  responses? : Array[ResponseSpec] = [],
  name? : String = "",
  endpoint? : Endpoint,
  security? : Array[SecurityRequirement] = [],
  dependencies? : Array[String] = [],
  include_in_schema? : Bool = true,
  validate? : Bool = true,
  openapi_extra? : Json,
) -> Unit {
  self.routes.push({
    verb,
    path,
    run: (ctx, _bg) => Buffered(handler(ctx)),
    summary,
    description,
    tags,
    deprecated,
    operation_id,
    status_code,
    responses,
    name,
    openapi_extra,
    endpoint,
    security,
    dependencies,
    include_in_schema,
    validate,
  })
}

///|
/// Register a background-aware route on the router — `App::route_bg`, deferred
/// to whichever application includes it.
pub fn Router::route_bg(
  self : Router,
  verb : Method,
  path : String,
  handler : BackgroundHandler,
  summary? : String = "",
  description? : String = "",
  tags? : Array[String] = [],
  deprecated? : Bool = false,
  operation_id? : String = "",
  status_code? : Int,
  responses? : Array[ResponseSpec] = [],
  name? : String = "",
  endpoint? : Endpoint,
  security? : Array[SecurityRequirement] = [],
  dependencies? : Array[String] = [],
  include_in_schema? : Bool = true,
  validate? : Bool = true,
  openapi_extra? : Json,
) -> Unit {
  self.routes.push({
    verb,
    path,
    run: (ctx, bg) => Buffered(handler(ctx, bg)),
    summary,
    description,
    tags,
    deprecated,
    operation_id,
    status_code,
    responses,
    name,
    openapi_extra,
    endpoint,
    security,
    dependencies,
    include_in_schema,
    validate,
  })
}

///|
/// Register a streaming `GET` route on the router — `App::stream`, deferred to
/// whichever application includes it.
pub fn Router::stream(
  self : Router,
  path : String,
  handler : StreamHandler,
  summary? : String = "",
  description? : String = "",
  tags? : Array[String] = [],
  deprecated? : Bool = false,
  operation_id? : String = "",
  status_code? : Int,
  responses? : Array[ResponseSpec] = [],
  name? : String = "",
  endpoint? : Endpoint,
  security? : Array[SecurityRequirement] = [],
  dependencies? : Array[String] = [],
  include_in_schema? : Bool = true,
  validate? : Bool = true,
  openapi_extra? : Json,
) -> Unit {
  self.routes.push({
    verb: Get,
    path,
    run: (ctx, _bg) => Streamed(handler(ctx)),
    summary,
    description,
    tags,
    deprecated,
    operation_id,
    status_code,
    responses,
    name,
    openapi_extra,
    endpoint,
    security,
    dependencies,
    include_in_schema,
    validate,
  })
}

///|
/// Register a `GET` route on the router.
pub fn Router::get(
  self : Router,
  path : String,
  handler : ApiHandler,
  summary? : String = "",
  description? : String = "",
  tags? : Array[String] = [],
  deprecated? : Bool = false,
  operation_id? : String = "",
  status_code? : Int,
  responses? : Array[ResponseSpec] = [],
  name? : String = "",
  endpoint? : Endpoint,
  security? : Array[SecurityRequirement] = [],
  dependencies? : Array[String] = [],
  include_in_schema? : Bool = true,
  validate? : Bool = true,
  openapi_extra? : Json,
) -> Unit {
  self.route(
    Get,
    path,
    handler,
    summary~,
    description~,
    tags~,
    deprecated~,
    operation_id~,
    status_code?,
    responses~,
    name~,
    endpoint?,
    security~,
    dependencies~,
    include_in_schema~,
    validate~,
    openapi_extra?,
  )
}

///|
/// Register a `POST` route on the router.
pub fn Router::post(
  self : Router,
  path : String,
  handler : ApiHandler,
  summary? : String = "",
  description? : String = "",
  tags? : Array[String] = [],
  deprecated? : Bool = false,
  operation_id? : String = "",
  status_code? : Int,
  responses? : Array[ResponseSpec] = [],
  name? : String = "",
  endpoint? : Endpoint,
  security? : Array[SecurityRequirement] = [],
  dependencies? : Array[String] = [],
  include_in_schema? : Bool = true,
  validate? : Bool = true,
  openapi_extra? : Json,
) -> Unit {
  self.route(
    Post,
    path,
    handler,
    summary~,
    description~,
    tags~,
    deprecated~,
    operation_id~,
    status_code?,
    responses~,
    name~,
    endpoint?,
    security~,
    dependencies~,
    include_in_schema~,
    validate~,
    openapi_extra?,
  )
}

///|
/// Register a `PUT` route on the router.
pub fn Router::put(
  self : Router,
  path : String,
  handler : ApiHandler,
  summary? : String = "",
  description? : String = "",
  tags? : Array[String] = [],
  deprecated? : Bool = false,
  operation_id? : String = "",
  status_code? : Int,
  responses? : Array[ResponseSpec] = [],
  name? : String = "",
  endpoint? : Endpoint,
  security? : Array[SecurityRequirement] = [],
  dependencies? : Array[String] = [],
  include_in_schema? : Bool = true,
  validate? : Bool = true,
  openapi_extra? : Json,
) -> Unit {
  self.route(
    Put,
    path,
    handler,
    summary~,
    description~,
    tags~,
    deprecated~,
    operation_id~,
    status_code?,
    responses~,
    name~,
    endpoint?,
    security~,
    dependencies~,
    include_in_schema~,
    validate~,
    openapi_extra?,
  )
}

///|
/// Register a `PATCH` route on the router.
pub fn Router::patch(
  self : Router,
  path : String,
  handler : ApiHandler,
  summary? : String = "",
  description? : String = "",
  tags? : Array[String] = [],
  deprecated? : Bool = false,
  operation_id? : String = "",
  status_code? : Int,
  responses? : Array[ResponseSpec] = [],
  name? : String = "",
  endpoint? : Endpoint,
  security? : Array[SecurityRequirement] = [],
  dependencies? : Array[String] = [],
  include_in_schema? : Bool = true,
  validate? : Bool = true,
  openapi_extra? : Json,
) -> Unit {
  self.route(
    Patch,
    path,
    handler,
    summary~,
    description~,
    tags~,
    deprecated~,
    operation_id~,
    status_code?,
    responses~,
    name~,
    endpoint?,
    security~,
    dependencies~,
    include_in_schema~,
    validate~,
    openapi_extra?,
  )
}

///|
/// Register a `DELETE` route on the router.
pub fn Router::delete(
  self : Router,
  path : String,
  handler : ApiHandler,
  summary? : String = "",
  description? : String = "",
  tags? : Array[String] = [],
  deprecated? : Bool = false,
  operation_id? : String = "",
  status_code? : Int,
  responses? : Array[ResponseSpec] = [],
  name? : String = "",
  endpoint? : Endpoint,
  security? : Array[SecurityRequirement] = [],
  dependencies? : Array[String] = [],
  include_in_schema? : Bool = true,
  validate? : Bool = true,
  openapi_extra? : Json,
) -> Unit {
  self.route(
    Delete,
    path,
    handler,
    summary~,
    description~,
    tags~,
    deprecated~,
    operation_id~,
    status_code?,
    responses~,
    name~,
    endpoint?,
    security~,
    dependencies~,
    include_in_schema~,
    validate~,
    openapi_extra?,
  )
}

///|
/// Register a WebSocket route on the router (← `APIRouter.websocket`). It takes
/// the including prefix like any other route; the operation attributes do not
/// apply, since a WebSocket route is not an OpenAPI operation.
pub fn Router::websocket(
  self : Router,
  path : String,
  handler : WsHandler,
) -> Unit {
  self.ws_routes.push({ path, handler, })
}

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
  router : Router,
  prefix? : String = "",
  tags? : Array[String] = [],
  security? : Array[SecurityRequirement] = [],
  dependencies? : Array[String] = [],
  responses? : Array[ResponseSpec] = [],
  deprecated? : Bool = false,
  include_in_schema? : Bool = true,
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
