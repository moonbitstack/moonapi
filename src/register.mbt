// Registering what an application serves: routes and streaming routes, WebSocket routes,
// included routers, mounts, the documentation routes, and the reverse lookup `url_for`.

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
/// The path of the route registered under `name`, with its parameters
/// filled from `params` (← FastAPI's `url_path_for`). Mounted sub-applications
/// are searched too, so what comes back already carries the mount prefix — the
/// path a client would call, not the one the sub-app knows itself by.
///
/// `None` when nothing is registered under that name, or when `params` is
/// missing one the path needs or holds one its convertor refuses; only a `path`
/// parameter takes a `/`.
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
      return @route.Pattern::parse(entry.0).fill(params)
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
    let path = join_prefix(prefix, r.path)
    self.router.routes.push({
      ..r,
      path,
      pattern: @route.Pattern::parse(path),
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
/// Register a WebSocket route (← FastAPI's `@app.websocket(path)`). The path is a template with
/// the same parameters and convertors as an HTTP route's.
pub fn App::websocket(
  self : App,
  path : String,
  handler : @socket.WsHandler,
) -> Unit {
  self.router.ws_routes.push({ path, handler, })
}
