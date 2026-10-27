// Registering what an application serves: routes and streaming routes, WebSocket routes,
// included routers, mounts, the documentation routes, and the reverse lookup `url_for`.

///|
/// Serve the app's own documentation: the OpenAPI document at `openapi_url`, an
/// interactive reference at `docs_url`, and ReDoc at `redoc_url`. Pass `None` for
/// any of them to leave it off. The routes are kept out of the document they
/// serve, so enabling docs does not change the spec a client reads.
///
/// `ui` picks the reader at `docs_url`. With `Swagger`, `oauth2_redirect_url` is
/// where an OAuth2 flow started from the page returns to, and `init_oauth`
/// prefills it (← FastAPI's `swagger_ui_init_oauth`); `ui_extra` is merged over
/// the reader's own settings either way.
///
/// Behind a proxy that mounts the app under a prefix, the server reports that
/// prefix as the ASGI `root_path`. The pages then fetch the document from under
/// it, and with `root_path_in_servers` the document names it as its first
/// server, so a call tried out from the page goes where the app actually is.
///
/// It is a call rather than a default because registering routes behind the app's
/// back would surprise anyone mounting this app under a prefix.
pub fn App::enable_docs(
  self : App,
  openapi_url~ : String? = Some("/openapi.json"),
  docs_url~ : String? = Some("/docs"),
  redoc_url~ : String? = Some("/redoc"),
  version~ : @schema.OpenApiVersion = OpenApi31,
  ui~ : @openapi.Ui = Scalar,
  oauth2_redirect_url~ : String? = Some("/docs/oauth2-redirect"),
  init_oauth? : Json,
  ui_extra? : Map[String, Json],
  root_path_in_servers~ : Bool = true,
) -> Unit {
  if openapi_url is Some(url) {
    self.get(
      url,
      ctx => {
        let root = ctx.scope.root_path
        let servers = self.info.servers
        let servers = if root_path_in_servers &&
          root != "" &&
          !servers.iter().any(s => s.url == root) {
          [@openapi.Server::new(root), ..servers]
        } else {
          servers
        }
        @status.json(200, self.openapi(version~, servers~))
      },
      include_in_schema=false,
    )
  }
  let spec_path = match openapi_url {
    Some(url) => url
    None => "/openapi.json"
  }
  if docs_url is Some(url) {
    self.get(
      url,
      ctx => {
        let root = ctx.scope.root_path
        let spec_url = root + spec_path
        let title = self.info.title
        let page = match ui {
          Scalar => @openapi.scalar_ui(spec_url~, title~, extra?=ui_extra)
          Swagger =>
            @openapi.swagger_ui(
              spec_url~,
              title~,
              oauth2_redirect_url?=oauth2_redirect_url.map(r => root + r),
              init_oauth?,
              extra?=ui_extra,
            )
        }
        @status.html(200, page)
      },
      include_in_schema=false,
    )
    if ui is Swagger && oauth2_redirect_url is Some(r) {
      self.get(
        r,
        _ctx => @status.html(200, @openapi.swagger_redirect()),
        include_in_schema=false,
      )
    }
  }
  if redoc_url is Some(url) {
    self.get(
      url,
      ctx => {
        let spec_url = ctx.scope.root_path + spec_path
        @status.html(200, @openapi.redoc_ui(spec_url~, title=self.info.title))
      },
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
///
/// ```mbt
/// app.get("/items/{id}", handler, name="get_item")
/// app.url_for("get_item", Map([("id", "77")]))   // Some("/items/77")
/// ```
pub fn App::url_for(
  self : App,
  name : String,
  params~ : Map[String, String] = Map([]),
) -> String? {
  // Every route starts out unnamed, so an empty name would match the first one.
  if name == "" {
    return None
  }
  self.named(name, "").bind(path => @route.Pattern::parse(path).fill(params))
}

///|
/// The full path of the route or WebSocket route called `name`, searching this app, then its
/// mounted sub-applications in mount order.
fn App::named(self : App, name : String, prefix : String) -> String? {
  for r in self.router.routes {
    if r.name == name {
      return Some(@route.join_prefix(prefix, r.path))
    }
  }
  for w in self.router.ws_routes {
    if w.name == name {
      return Some(@route.join_prefix(prefix, w.path))
    }
  }
  for entry in self.mounts {
    if entry.1 is Sub(sub) &&
      sub.named(name, @route.join_prefix(prefix, entry.0)) is Some(path) {
      return Some(path)
    }
  }
  None
}

///|
/// Fold `router`'s routes into this app (FastAPI's `include_router`, and the
/// same name — `include` is a reserved word). Each is registered under `prefix`
/// and becomes one of the app's own routes, with the arguments given here
/// reaching every one of them as `Router::include_router` describes.
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
  hoops~ : Array[@route.Hoop] = [],
) -> Unit {
  self.router.include_router(
    router,
    prefix~,
    tags~,
    security~,
    dependencies~,
    responses~,
    deprecated~,
    include_in_schema~,
    hoops~,
  )
}

///|
/// Register the methods `view` answers at `path`; see `Router::view`.
pub fn App::view(
  self : App,
  path : String,
  view : &@route.View,
  name~ : String = "",
  tags~ : Array[String] = [],
  security~ : Array[@security.SecurityRequirement] = [],
  dependencies~ : Array[String] = [],
  deprecated~ : Bool = false,
  include_in_schema~ : Bool = true,
  hoops~ : Array[@route.Hoop] = [],
) -> Unit {
  self.router.view(
    path,
    view,
    name~,
    tags~,
    security~,
    dependencies~,
    deprecated~,
    include_in_schema~,
    hoops~,
  )
}

///|
/// Register a route table; see `Router::urls`.
pub fn App::urls(self : App, urls : Array[@route.Url]) -> Unit {
  self.router.urls(urls)
}

///|
/// Register a WebSocket route (← FastAPI's `@app.websocket(path)`). The path is a template with
/// the same parameters and convertors as an HTTP route's.
///
/// `security` is enforced and `dependencies` resolved before the handler is called. A refusal
/// declines the handshake with the response an HTTP route would have answered — through ASGI's
/// `websocket.http.response` extension where the server offers it, and with close code 1008
/// otherwise. The dependencies are torn down when the handler returns. `name` is the handle
/// `App::url_for` resolves.
pub fn App::websocket(
  self : App,
  path : String,
  handler : @socket.WsHandler,
  name~ : String = "",
  security~ : Array[@security.SecurityRequirement] = [],
  dependencies~ : Array[String] = [],
) -> Unit {
  self.router.websocket(path, handler, name~, security~, dependencies~)
}
