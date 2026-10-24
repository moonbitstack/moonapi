// Registering what an application serves: routes and streaming routes, WebSocket routes,
// included routers, mounts, the documentation routes, and the reverse lookup `url_for`.

///|
/// Register a route for an explicit method. An optional `endpoint` descriptor
/// makes the route fully typed (its parameters, request body, and responses
/// surface in the OpenAPI document and drive validation); `security` attaches
/// per-operation requirements (emitted as OpenAPI `security` and enforced before
/// the handler when their scheme has an enforcer); `dependencies` names provider
/// keys resolved through the app's container (`App::depends`) before the handler
/// and torn down after it, whatever the handler did.
///
/// The rest describe the operation: `summary` and `description` are its prose,
/// `operation_id` the stable handle client generators name their method after,
/// `status_code` the status its success response is documented under,
/// `responses` further documented responses, `name` the handle `App::url_for`
/// resolves, and `openapi_extra` a fragment merged over the generated operation
/// object — the same keyword arguments FastAPI's path operations take.
pub fn App::route(
  self : App,
  verb : @route.Method,
  path : String,
  handler : @route.ApiHandler,
  summary~ : String = "",
  description~ : String = "",
  tags~ : Array[String] = [],
  deprecated~ : Bool = false,
  operation_id~ : String = "",
  status_code? : Int32,
  responses~ : Array[@endpoint.ResponseSpec] = [],
  name~ : String = "",
  endpoint? : @endpoint.Endpoint,
  security~ : Array[@security.SecurityRequirement] = [],
  dependencies~ : Array[String] = [],
  include_in_schema~ : Bool = true,
  validate~ : Bool = true,
  openapi_extra? : Json,
) -> Unit {
  self.router.routes.push({
    verb,
    path,
    run: ctx => @route.Buffered(handler(ctx)),
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
/// Register a streaming route (← a FastAPI path operation returning a
/// `StreamingResponse`). The handler's chunks reach the client as separate body
/// events, so a long or open-ended reply starts arriving before it is finished.
///
/// A stream is only streamed as far as the app can honestly keep it one: moonasgi
/// types a middleware as buffered response in, buffered response out, so a
/// middleware that rewrites the body — `gzip` does — collapses the reply to a
/// single chunk. Everything else about the route is ordinary; it documents,
/// validates and enforces security exactly as `route` does.
pub fn App::route_stream(
  self : App,
  verb : @route.Method,
  path : String,
  handler : @route.StreamHandler,
  summary~ : String = "",
  description~ : String = "",
  tags~ : Array[String] = [],
  deprecated~ : Bool = false,
  operation_id~ : String = "",
  status_code? : Int32,
  responses~ : Array[@endpoint.ResponseSpec] = [],
  name~ : String = "",
  endpoint? : @endpoint.Endpoint,
  security~ : Array[@security.SecurityRequirement] = [],
  dependencies~ : Array[String] = [],
  include_in_schema~ : Bool = true,
  validate~ : Bool = true,
  openapi_extra? : Json,
) -> Unit {
  self.router.routes.push({
    verb,
    path,
    run: ctx => @route.Streamed(handler(ctx)),
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
/// Register a streaming `GET` route — the verb a stream is nearly always read
/// over, and what an SSE endpoint is. A shorthand for `route_stream(Get, ...)`.
pub fn App::stream(
  self : App,
  path : String,
  handler : @route.StreamHandler,
  summary~ : String = "",
  description~ : String = "",
  tags~ : Array[String] = [],
  deprecated~ : Bool = false,
  operation_id~ : String = "",
  status_code? : Int32,
  responses~ : Array[@endpoint.ResponseSpec] = [],
  name~ : String = "",
  endpoint? : @endpoint.Endpoint,
  security~ : Array[@security.SecurityRequirement] = [],
  dependencies~ : Array[String] = [],
  include_in_schema~ : Bool = true,
  validate~ : Bool = true,
  openapi_extra? : Json,
) -> Unit {
  self.route_stream(
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
/// Register a `GET` route. A shorthand for `route(Get, ...)` carrying the same
/// documentation and security arguments.
pub fn App::get(
  self : App,
  path : String,
  handler : @route.ApiHandler,
  summary~ : String = "",
  description~ : String = "",
  tags~ : Array[String] = [],
  deprecated~ : Bool = false,
  operation_id~ : String = "",
  status_code? : Int32,
  responses~ : Array[@endpoint.ResponseSpec] = [],
  name~ : String = "",
  endpoint? : @endpoint.Endpoint,
  security~ : Array[@security.SecurityRequirement] = [],
  dependencies~ : Array[String] = [],
  include_in_schema~ : Bool = true,
  validate~ : Bool = true,
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
/// Register a `POST` route — the verb that carries a request body, so this is the
/// one most often given an `endpoint` describing that body.
pub fn App::post(
  self : App,
  path : String,
  handler : @route.ApiHandler,
  summary~ : String = "",
  description~ : String = "",
  tags~ : Array[String] = [],
  deprecated~ : Bool = false,
  operation_id~ : String = "",
  status_code? : Int32,
  responses~ : Array[@endpoint.ResponseSpec] = [],
  name~ : String = "",
  endpoint? : @endpoint.Endpoint,
  security~ : Array[@security.SecurityRequirement] = [],
  dependencies~ : Array[String] = [],
  include_in_schema~ : Bool = true,
  validate~ : Bool = true,
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
/// Register a `PUT` route: replace the addressed resource wholesale.
pub fn App::put(
  self : App,
  path : String,
  handler : @route.ApiHandler,
  summary~ : String = "",
  description~ : String = "",
  tags~ : Array[String] = [],
  deprecated~ : Bool = false,
  operation_id~ : String = "",
  status_code? : Int32,
  responses~ : Array[@endpoint.ResponseSpec] = [],
  name~ : String = "",
  endpoint? : @endpoint.Endpoint,
  security~ : Array[@security.SecurityRequirement] = [],
  dependencies~ : Array[String] = [],
  include_in_schema~ : Bool = true,
  validate~ : Bool = true,
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
/// Register a `PATCH` route: change part of the addressed resource.
pub fn App::patch(
  self : App,
  path : String,
  handler : @route.ApiHandler,
  summary~ : String = "",
  description~ : String = "",
  tags~ : Array[String] = [],
  deprecated~ : Bool = false,
  operation_id~ : String = "",
  status_code? : Int32,
  responses~ : Array[@endpoint.ResponseSpec] = [],
  name~ : String = "",
  endpoint? : @endpoint.Endpoint,
  security~ : Array[@security.SecurityRequirement] = [],
  dependencies~ : Array[String] = [],
  include_in_schema~ : Bool = true,
  validate~ : Bool = true,
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
/// Register a `DELETE` route.
pub fn App::delete(
  self : App,
  path : String,
  handler : @route.ApiHandler,
  summary~ : String = "",
  description~ : String = "",
  tags~ : Array[String] = [],
  deprecated~ : Bool = false,
  operation_id~ : String = "",
  status_code? : Int32,
  responses~ : Array[@endpoint.ResponseSpec] = [],
  name~ : String = "",
  endpoint? : @endpoint.Endpoint,
  security~ : Array[@security.SecurityRequirement] = [],
  dependencies~ : Array[String] = [],
  include_in_schema~ : Bool = true,
  validate~ : Bool = true,
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
/// Serve the app's own documentation, the way FastAPI does out of the box: the
/// OpenAPI document at `openapi_url`, Swagger UI at `docs_url`, and ReDoc at
/// `redoc_url`. Pass `None` for any of the three to leave it off. The three routes
/// are kept out of the document they serve, so enabling docs does not change the
/// spec a client reads.
///
/// It is a call rather than a default because registering routes behind the app's
/// back would surprise anyone mounting this app under a prefix.
pub fn App::enable_docs(
  self : App,
  openapi_url~ : String? = Some("/openapi.json"),
  docs_url~ : String? = Some("/docs"),
  redoc_url~ : String? = Some("/redoc"),
  version~ : @schema.OpenApiVersion = OpenApi31,
) -> Unit {
  let title = self.info.title
  if openapi_url is Some(url) {
    self.get(
      url,
      _ctx => @status.json(200, self.openapi(version~)),
      include_in_schema=false,
    )
  }
  let spec_url = match openapi_url {
    Some(url) => url
    None => "/openapi.json"
  }
  if docs_url is Some(url) {
    self.get(
      url,
      _ctx => @status.html(200, @openapi.swagger_ui(spec_url~, title~)),
      include_in_schema=false,
    )
  }
  if redoc_url is Some(url) {
    self.get(
      url,
      _ctx => @status.html(200, @openapi.redoc_ui(spec_url~, title~)),
      include_in_schema=false,
    )
  }
}

///|
/// Mount a sub-application under `prefix` (← FastAPI's `app.mount(prefix, sub)`).
/// A request whose path lies under `prefix` is served by `subapp`, with the prefix moved from
/// `path` to `root_path` (its own layers, security and background tasks apply),
/// and the sub-app's routes appear under `prefix` in the merged OpenAPI document
/// with its security schemes folded into the parent's.
pub fn App::mount(self : App, prefix : String, subapp : App) -> Unit {
  self.mounts.push((prefix, Sub(subapp)))
}

///|
/// Mount any ASGI application under `prefix` (← FastAPI mounting a plain ASGI app,
/// `app.mount("/static", StaticFiles(...))`). A request under `prefix` reaches `app` with the
/// prefix moved from `path` to `root_path`, exactly as for a sub-app.
///
/// It is not a moonapi application, so it contributes nothing to the OpenAPI document and has no
/// lifespan of its own to run — the app only routes to it. Mounts are tried in registration
/// order, whichever kind they are.
pub fn App::mount_asgi(
  self : App,
  prefix : String,
  app : @moonasgi.AsgiApp,
) -> Unit {
  self.mounts.push((prefix, Asgi(app)))
}

///|
/// Fill a route pattern's `:name` segments from `params`, the inverse of
/// `match_path`. `None` when the pattern needs a parameter `params` does not
/// carry — half a URL is worse than none.
fn render_path(pattern : String, params : Map[String, String]) -> String? {
  let sb = StringBuilder()
  for seg in @route.segments(pattern) {
    sb.write_string("/")
    if seg.length() > 0 && seg[0] == ':' {
      match params.get(seg[1:].to_owned()) {
        Some(v) => sb.write_string(v)
        None => return None
      }
    } else {
      sb.write_string(seg)
    }
  }
  let rendered = sb.to_string()
  Some(if rendered == "" { "/" } else { rendered })
}

///|
/// The path of the route registered under `name`, with its `:name` segments
/// filled from `params` (← FastAPI's `url_path_for`). Mounted sub-applications
/// are searched too, so what comes back already carries the mount prefix — the
/// path a client would call, not the one the sub-app knows itself by.
///
/// `None` when nothing is registered under that name, or when `params` is
/// missing one the path needs. Values are substituted as given: a value with a
/// `/` in it lands as extra path segments, so encode before calling if that
/// matters.
pub fn App::url_for(
  self : App,
  name : String,
  params~ : Map[String, String] = Map([]),
) -> String? {
  // Every route starts out unnamed, so an empty name would match the first one.
  if name == "" {
    return None
  }
  let all : Array[(String, @route.Route)] = []
  self.collect_routes("", all)
  for entry in all {
    if entry.1.name == name {
      return render_path(entry.0, params)
    }
  }
  None
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
    self.router.routes.push({
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
    self.router.ws_routes.push({ ..w, path: join_prefix(prefix, w.path), })
  }
}

///|
/// Register a WebSocket route (← FastAPI's `@app.websocket(path)`). The path matches with the
/// same `:name` segment rules as HTTP routes.
pub fn App::websocket(
  self : App,
  path : String,
  handler : @socket.WsHandler,
) -> Unit {
  self.router.ws_routes.push({ path, handler, })
}
