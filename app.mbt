///|
/// HTTP methods a moonapi route can bind to.
pub(all) enum Method {
  Get
  Post
  Put
  Patch
  Delete
  Head
  Options
} derive(Eq)

///|
fn parse_method(s : String) -> Method? {
  match s {
    "GET" => Some(Get)
    "POST" => Some(Post)
    "PUT" => Some(Put)
    "PATCH" => Some(Patch)
    "DELETE" => Some(Delete)
    "HEAD" => Some(Head)
    "OPTIONS" => Some(Options)
    // TRACE, CONNECT, or something invented. Answering it as a GET would run a
    // handler the caller never asked for.
    _ => None
  }
}

///|
/// A method's name as it appears in an `Allow` header.
fn method_name(m : Method) -> String {
  match m {
    Get => "GET"
    Post => "POST"
    Put => "PUT"
    Patch => "PATCH"
    Delete => "DELETE"
    Head => "HEAD"
    Options => "OPTIONS"
  }
}

///|
fn method_lower(m : Method) -> String {
  match m {
    Get => "get"
    Post => "post"
    Put => "put"
    Patch => "patch"
    Delete => "delete"
    Head => "head"
    Options => "options"
  }
}

///|
/// The per-request context handed to a handler: the raw request plus the path
/// parameters extracted from the matched route (`:name` segments).
pub(all) struct Context {
  request : @moonasgi.Request
  params : Map[String, String]
}

///|
/// Look up a path parameter by name.
pub fn Context::param(self : Context, name : String) -> String? {
  self.params.get(name)
}

///|
/// A moonapi route handler: request context in, response out. It may `raise` an
/// `HttpException` (or any error) instead of returning — the app catches it and
/// maps it to a response through the registered exception handlers, so handlers
/// read like FastAPI's `raise HTTPException(...)` rather than threading a
/// `Result` back by hand. A plain non-raising closure is still a valid handler.
pub type ApiHandler = (Context) -> @moonasgi.Response raise

///|
/// A background-aware handler: it additionally receives the request's
/// `BackgroundTasks` queue, so it can schedule work to run after its response is
/// sent (← declaring a `BackgroundTasks` parameter in FastAPI).
pub type BackgroundHandler = (Context, BackgroundTasks) -> @moonasgi.Response raise

///|
/// A streaming route's handler: request context in, a chunked response out (←
/// returning a `StreamingResponse` from a FastAPI path operation). Every chunk
/// becomes one body event on the wire, so a client reads the first long before
/// the last one exists — the point of streaming, and what a single buffered
/// `Response` cannot express.
pub type StreamHandler = (Context) -> @moonasgi.StreamingResponse raise

///|
/// What a route produced. Two kinds because moonasgi types a buffered response
/// and a chunked one differently, and the difference has to survive as far as
/// `to_asgi`, which is the only place that can put chunks on the wire.
priv enum Reply {
  Buffered(@moonasgi.Response)
  Streamed(@moonasgi.StreamingResponse)
}

///|
/// A route stores one background-aware handler; a plain `ApiHandler` is wrapped
/// to ignore the queue. `security` is the per-operation requirements (emitted as
/// OpenAPI `security` and enforced before the handler when their scheme has an
/// enforcer).
struct Route {
  verb : Method
  path : String
  run : (Context, BackgroundTasks) -> Reply raise
  summary : String
  description : String
  tags : Array[String]
  deprecated : Bool
  operation_id : String
  // The status the success response is documented under. Documentation only: the
  // handler builds its own response, and rewriting the status it chose would make
  // the app disagree with itself rather than with the spec.
  status_code : Int?
  // Documented alongside whatever the endpoint descriptor produced, and written
  // after it, so the status a route names here is the one that stands.
  responses : Array[ResponseSpec]
  // The handle `App::url_for` looks the route up by. Empty means unnamed, and an
  // unnamed route is not addressable.
  name : String
  // Merged into the operation object last, so it can override anything moonapi
  // generated (← FastAPI's `openapi_extra`).
  openapi_extra : Json?
  endpoint : Endpoint?
  security : Array[SecurityRequirement]
  // Provider keys resolved through the app's container before the handler runs,
  // and torn down after it (← FastAPI's `dependencies=[Depends(...)]`, whose
  // values the handler never sees).
  dependencies : Array[String]
  // FastAPI's `include_in_schema`: a route that serves the documentation itself has
  // no business appearing in the document it serves.
  include_in_schema : Bool
  // Whether the declared `endpoint` is checked before the handler runs. On by
  // default: a route that advertises constraints in its documentation and does not
  // apply them is worse than one that declares nothing.
  validate : Bool
}

///|
/// What a mount prefix routes to: a moonapi sub-application, whose routes,
/// security schemes and lifespan hooks fold into the parent's, or a foreign
/// moonasgi handler, which the parent can only forward requests to.
enum Mount {
  Sub(App)
  Asgi(@moonasgi.Handler)
}

///|
/// A moonapi application: routes, WebSocket routes, an outer middleware chain,
/// exception handlers, mounted sub-applications, the security schemes surfaced
/// in the OpenAPI document (with optional runtime enforcers), per-status
/// exception handlers, and the verification clock. Compiles to a moonasgi
/// `AsgiApp` any server (mooncat) can run.
pub struct App {
  routes : Array[Route]
  ws_routes : Array[WsRoute]
  middlewares : Array[@moonasgi.Middleware]
  exception_handlers : Array[ExceptionHandler]
  security_schemes : Array[DeclaredScheme]
  enforcers : Map[String, SecurityEnforcer]
  status_handlers : Map[Int, (Context) -> @moonasgi.Response]
  mounts : Array[(String, Mount)]
  // Run in registration order when the server starts, and in reverse when it stops,
  // so a resource is torn down before whatever it was built on.
  startup_hooks : Array[() -> Unit raise]
  shutdown_hooks : Array[() -> Unit raise]
  // What the emitted document says about itself. `enable_docs` serves the same
  // values, so the page a reader opens is not a different API from the one
  // `App::openapi` describes.
  mut info : ApiInfo
  mut clock : () -> Int64
  // The container a route's declared `dependencies` are resolved through.
  mut deps : Deps?
}

///|
/// Create an empty application. The verification clock defaults to `0` (Unix
/// epoch); a server sets a real one with `App::set_clock`, and tests inject a
/// fixed time so token expiry is deterministic.
pub fn App::new() -> App {
  {
    routes: [],
    ws_routes: [],
    middlewares: [],
    exception_handlers: [],
    security_schemes: [],
    enforcers: Map([]),
    status_handlers: Map([]),
    mounts: [],
    startup_hooks: [],
    shutdown_hooks: [],
    info: ApiInfo::new(),
    clock: () => 0L,
    deps: None,
  }
}

///|
/// Give the app the dependency container its routes resolve their declared
/// `dependencies` through (← FastAPI's `Depends` wiring, which a route names and
/// the application supplies). The container's value type is erased on the way
/// in, because a route-level dependency runs for its effect and its value is
/// never handed to the handler — the same thing FastAPI's `dependencies=[...]`
/// does with the values it builds.
///
/// A route that declares a dependency the container does not provide is answered
/// with a `500`: the setup the route promised did not happen, and running the
/// handler as though it had is worse than saying so.
pub fn App::depends(self : App, deps : Deps) -> Unit {
  self.deps = Some(deps)
}

///|
/// Set what the OpenAPI document says about this API (← FastAPI's `FastAPI(title=…,
/// description=…, contact=…, license_info=…, servers=…)`). `App::openapi` and the
/// `/openapi.json` route `enable_docs` registers both read it, so the document a
/// client fetches and the one a test builds cannot describe different APIs.
pub fn App::describe(
  self : App,
  title? : String,
  api_version? : String,
  description? : String,
  terms_of_service? : String,
  contact? : Contact?,
  license? : License?,
  servers? : Array[Server],
) -> Unit {
  let cur = self.info
  self.info = {
    title: title.unwrap_or(cur.title),
    api_version: api_version.unwrap_or(cur.api_version),
    description: description.unwrap_or(cur.description),
    terms_of_service: terms_of_service.unwrap_or(cur.terms_of_service),
    contact: contact.unwrap_or(cur.contact),
    license: license.unwrap_or(cur.license),
    servers: servers.unwrap_or(cur.servers),
  }
}

///|
/// Run `hook` when the server starts, before it accepts the first request (←
/// FastAPI's `on_event("startup")`). Hooks run in the order they were registered;
/// one that raises aborts startup, and the server is told why.
pub fn App::on_startup(self : App, hook : () -> Unit raise) -> Unit {
  self.startup_hooks.push(hook)
}

///|
/// Run `hook` when the server shuts down, after the last request has been served (←
/// FastAPI's `on_event("shutdown")`). Hooks run in reverse registration order, so a
/// resource is released before whatever it was opened from. A hook that raises does
/// not stop the others — shutdown reports the first failure once the rest have run.
pub fn App::on_shutdown(self : App, hook : () -> Unit raise) -> Unit {
  self.shutdown_hooks.push(hook)
}

///|
/// Set the clock the app reads to verify token expiry when enforcing route
/// security (Unix seconds). A native server passes the wall clock; a test passes
/// a fixed function so expiry is deterministic.
pub fn App::set_clock(self : App, clock : () -> Int64) -> Unit {
  self.clock = clock
}

///|
/// Add an outer middleware. Middlewares wrap the router as an onion; the first
/// registered is the outermost (it sees the request first and the response
/// last). `cors(...)` and `gzip(...)` are middlewares.
pub fn App::middleware(self : App, mw : @moonasgi.Middleware) -> Unit {
  self.middlewares.push(mw)
}

///|
/// Register an exception handler. On a raised error the handlers are tried in
/// registration order; the first to return `Some(response)` wins. An
/// unhandled error falls through to the built-in mapping — an `HttpException`
/// becomes its own `status` / `detail`, anything else a `500`.
pub fn App::exception_handler(self : App, h : ExceptionHandler) -> Unit {
  self.exception_handlers.push(h)
}

///|
/// Declare a security scheme under `name`, surfaced in the emitted OpenAPI
/// document (`components/securitySchemes` in 3.x, `securityDefinitions` in
/// Swagger 2.0) so the generated spec describes how to authenticate.
/// `description` is the prose shown beside it in the documentation UI.
///
/// This declares only. A route naming this scheme in its `security` is
/// documented as protected and left unguarded, exactly as a FastAPI scheme that
/// no path operation depends on is — the `secure_*` functions are the ones that
/// wire an enforcer.
pub fn App::add_security_scheme(
  self : App,
  name : String,
  scheme : SecurityScheme,
  description? : String = "",
) -> Unit {
  self.security_schemes.push({ name, kind: scheme, description, })
}

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
/// Register a background-aware route: the handler additionally receives the
/// request's `BackgroundTasks` queue, whose thunks the app runs after the
/// response is sent (← declaring a `BackgroundTasks` parameter in FastAPI).
pub fn App::route_bg(
  self : App,
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
  verb : Method,
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
    verb,
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
/// Register a streaming `GET` route — the verb a stream is nearly always read
/// over, and what an SSE endpoint is. A shorthand for `route_stream(Get, ...)`.
pub fn App::stream(
  self : App,
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
  openapi_url? : String? = Some("/openapi.json"),
  docs_url? : String? = Some("/docs"),
  redoc_url? : String? = Some("/redoc"),
  version? : OpenApiVersion = OpenApi31,
) -> Unit {
  let title = self.info.title
  if openapi_url is Some(url) {
    self.get(
      url,
      _ctx => json(200, self.openapi(version~)),
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
      _ctx => html(200, swagger_ui(spec_url~, title~)),
      include_in_schema=false,
    )
  }
  if redoc_url is Some(url) {
    self.get(
      url,
      _ctx => html(200, redoc_ui(spec_url~, title~)),
      include_in_schema=false,
    )
  }
}

///|
/// Register a `POST` route — the verb that carries a request body, so this is the
/// one most often given an `endpoint` describing that body.
pub fn App::post(
  self : App,
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
/// Register a `PUT` route: replace the addressed resource wholesale.
pub fn App::put(
  self : App,
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
/// Register a `PATCH` route: change part of the addressed resource.
pub fn App::patch(
  self : App,
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
/// Register a `DELETE` route.
pub fn App::delete(
  self : App,
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
/// Declare an OAuth2 password-bearer scheme under `name` and wire it as a
/// runtime enforcer. Like `add_security_scheme` it surfaces the scheme in the
/// OpenAPI document (with the advertised `scopes` and `description`), and
/// additionally registers the guard a route names in its `security`: the app
/// pulls the bearer token, verifies it against `bearer`'s secret at the app
/// clock's time, and checks the route's required scopes — returning 401/403
/// before the handler runs.
///
/// `auto_error=false` admits the request instead of refusing it (← the argument
/// every FastAPI security class takes, whose dependency then yields `None` and
/// leaves the decision to the route).
pub fn App::secure_oauth2(
  self : App,
  name : String,
  bearer : OAuth2PasswordBearer,
  scopes? : Array[(String, String)] = [],
  description? : String = "",
  auto_error? : Bool = true,
) -> Unit {
  self.security_schemes.push({
    name,
    kind: bearer.scheme(scopes~),
    description,
  })
  self.enforcers[name] = (ctx, required, now) => {
    verify_bearer(ctx, bearer.secret, required, now, auto_error)
  }
}

///|
/// Register a per-status exception handler (← FastAPI's `add_exception_handler`
/// keyed by an HTTP status code). Whenever an error path yields `status` — a
/// routing `404` / `405`, or a raised `HttpException` (or the fallback `500`) —
/// the handler's response replaces the default, so an app can serve a custom
/// error page. Successful handler returns are never rewritten.
pub fn App::add_status_handler(
  self : App,
  status : Int,
  handler : (Context) -> @moonasgi.Response,
) -> Unit {
  self.status_handlers[status] = handler
}

///|
/// Mount a sub-application under `prefix` (← FastAPI's `app.mount(prefix, sub)`).
/// A request whose path lies under `prefix` is routed by `subapp` with the
/// prefix stripped (its own middleware, security, and background tasks apply),
/// and the sub-app's routes appear under `prefix` in the merged OpenAPI document
/// with its security schemes folded into the parent's.
pub fn App::mount(self : App, prefix : String, subapp : App) -> Unit {
  self.mounts.push((prefix, Sub(subapp)))
}

///|
/// Mount a foreign moonasgi handler under `prefix` (← FastAPI mounting a plain
/// ASGI app, `app.mount("/static", StaticFiles(...))`). A request under `prefix`
/// is handed to `handler` with the prefix stripped, exactly as for a sub-app.
///
/// A handler is not a moonapi application, so it contributes nothing to the
/// OpenAPI document and has no lifespan of its own to run — the app only routes
/// to it. Mounts are tried in registration order, whichever kind they are.
pub fn App::mount_handler(
  self : App,
  prefix : String,
  handler : @moonasgi.Handler,
) -> Unit {
  self.mounts.push((prefix, Asgi(handler)))
}

///|
/// Split a path into its non-empty segments.
fn segments(path : String) -> Array[String] {
  let out : Array[String] = []
  let n = path.length()
  let mut start = 0
  for i = 0; i <= n; i = i + 1 {
    if i == n || path[i] == '/' {
      if i > start {
        out.push(path[start:i].to_owned())
      }
      start = i + 1
    }
  }
  out
}

///|
/// Match a route pattern against a request path, extracting `:name` params.
fn match_path(pattern : String, path : String) -> Map[String, String]? {
  let pp = segments(pattern)
  let ph = segments(path)
  if pp.length() != ph.length() {
    return None
  }
  let params : Map[String, String] = Map([])
  for i = 0; i < pp.length(); i = i + 1 {
    let seg = pp[i]
    if seg.length() > 0 && seg[0] == ':' {
      params[seg[1:].to_owned()] = ph[i]
    } else if seg != ph[i] {
      return None
    }
  }
  Some(params)
}

///|
/// Fill a route pattern's `:name` segments from `params`, the inverse of
/// `match_path`. `None` when the pattern needs a parameter `params` does not
/// carry — half a URL is worse than none.
fn render_path(pattern : String, params : Map[String, String]) -> String? {
  let sb = StringBuilder()
  for seg in segments(pattern) {
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
  params? : Map[String, String] = Map([]),
) -> String? {
  // Every route starts out unnamed, so an empty name would match the first one.
  if name == "" {
    return None
  }
  let all : Array[(String, Route)] = []
  self.collect_routes("", all)
  for entry in all {
    if entry.1.name == name {
      return render_path(entry.0, params)
    }
  }
  None
}

///|
/// A plain-text response.
pub fn text(status : Int, body : String) -> @moonasgi.Response {
  @moonasgi.Response::new(
    status,
    [("content-type", "text/plain; charset=utf-8")],
    @utf8.encode(body),
  )
}

///|
/// An HTML response — what the documentation pages are served as.
pub fn html(status : Int, body : String) -> @moonasgi.Response {
  @moonasgi.Response::new(
    status,
    [("content-type", "text/html; charset=utf-8")],
    @utf8.encode(body),
  )
}

///|
/// A JSON response serialised from a `Json` value.
pub fn json(status : Int, value : Json) -> @moonasgi.Response {
  @moonasgi.Response::new(
    status,
    [("content-type", "application/json")],
    @moonjson.write_bytes(value),
  )
}

///|
/// Rewrite an error-path response through a registered per-status handler, if one
/// is registered for its status; otherwise pass it through unchanged.
fn App::apply_status(
  self : App,
  ctx : Context,
  resp : @moonasgi.Response,
) -> @moonasgi.Response {
  match self.status_handlers.get(resp.status) {
    Some(h) => h(ctx)
    None => resp
  }
}

///|
/// Try each registered exception handler in order; the first to claim the error
/// wins outright. Otherwise fall through to the built-in mapping, which a
/// per-status handler may still rewrite (a custom `500` page, say).
fn App::dispatch_exception(
  self : App,
  ctx : Context,
  err : Error,
) -> @moonasgi.Response {
  for h in self.exception_handlers {
    match h(ctx, err) {
      Some(resp) => return resp
      None => ()
    }
  }
  self.apply_status(ctx, default_exception_response(err))
}

///|
/// Enforce a route's security requirements. `None` means allow (nothing to
/// enforce, or a requirement passed); `Some(resp)` is the 401/403 to return.
/// Requirements are alternatives (OpenAPI OR-semantics): the first enforceable
/// one that passes admits the request; if every enforceable requirement fails,
/// the last failure response is returned. A requirement naming a
/// documentation-only scheme (no enforcer) grants nothing by itself.
fn App::enforce_security(
  self : App,
  ctx : Context,
  reqs : Array[SecurityRequirement],
) -> @moonasgi.Response? {
  if reqs.is_empty() {
    return None
  }
  let now = (self.clock)()
  let mut enforceable = false
  let mut last : @moonasgi.Response? = None
  for r in reqs {
    match self.enforcers.get(r.scheme) {
      Some(enf) => {
        enforceable = true
        match enf(ctx, SecurityScopes::new(scopes=r.scopes), now) {
          Ok(_) => return None
          Err(resp) => last = Some(resp)
        }
      }
      None => ()
    }
  }
  if enforceable {
    last
  } else {
    None
  }
}

///|
/// The routing + exception core, inside the middleware chain: match a route,
/// enforce its security, run its (possibly raising) handler, and turn any raised
/// error into a response. Falls through to mounted sub-apps, then 405 (a path
/// matched but no method) or 404 (no path). `bg` is the request's background
/// queue, handed to the matched handler and drained by the caller after the
/// response is sent.
///
/// The chain around this is typed in buffered responses, so a streaming route's
/// chunks are left in `stream` on the way past and the buffered join is what
/// travels through the middleware.
fn App::route_and_dispatch(
  self : App,
  request : @moonasgi.Request,
  bg : BackgroundTasks,
  stream : Ref[@moonasgi.StreamingResponse?],
) -> @moonasgi.Response {
  let verb = parse_method(request.http_method)
  let allowed : Array[String] = []
  for route in self.routes {
    match match_path(route.path, request.path) {
      Some(params) =>
        // A GET route answers HEAD too, with the body dropped — the same rule
        // Starlette applies, and what a client probing a resource expects.
        if verb is Some(v) &&
          (route.verb == v || (v is Head && route.verb is Get)) {
          let ctx : Context = { request, params, }
          match self.enforce_security(ctx, route.security) {
            Some(denied) => return self.apply_status(ctx, denied)
            None => ()
          }
          if route.validate && route.endpoint is Some(ep) {
            let errs = ep.validate(ctx)
            if errs.length() > 0 {
              return self.apply_status(ctx, unprocessable(errs))
            }
          }
          let reply = self.run_with_deps(route.dependencies, () => {
            (route.run)(ctx, bg)
          }) catch {
            e => Buffered(self.dispatch_exception(ctx, e))
          }
          let resp = match reply {
            Buffered(r) => r
            Streamed(s) => {
              stream.val = Some(s)
              @moonasgi.Response::new(
                s.status,
                s.headers,
                join_chunks(s.chunks),
              )
            }
          }
          return if verb is Some(Head) && route.verb is Get {
            // A HEAD reply carries no body, so a streaming route's chunks
            // describe nothing that will be sent.
            stream.val = None
            @moonasgi.Response::new(resp.status, resp.headers, b"")
          } else {
            resp
          }
        } else {
          allowed.push(method_name(route.verb))
          if route.verb is Get {
            allowed.push("HEAD")
          }
        }
      None => ()
    }
  }
  for entry in self.mounts {
    let (prefix, target) = entry
    match strip_prefix(prefix, request.path) {
      Some(rest) => {
        let subreq : @moonasgi.Request = {
          http_method: request.http_method,
          path: rest,
          query_string: request.query_string,
          headers: request.headers,
          body: request.body,
        }
        match target {
          Sub(sub) => {
            let (sresp, subbg) = sub.handle_with_stream(subreq)
            bg.absorb(subbg)
            stream.val = Some(sresp)
            return @moonasgi.Response::new(
              sresp.status,
              sresp.headers,
              join_chunks(sresp.chunks),
            )
          }
          // A foreign handler has no background queue of its own to absorb.
          Asgi(h) => return h(subreq)
        }
      }
      None => ()
    }
  }
  let ctx : Context = { request, params: Map([]), }
  if allowed.length() > 0 {
    // RFC 9110 §15.5.6 requires the Allow header on a 405; a client that probes
    // a resource reads it rather than guessing.
    self.apply_status(
      ctx,
      http_exception_response(405, "Method Not Allowed".to_json(), [
        ("allow", dedupe(allowed).join(", ")),
      ]),
    )
  } else {
    self.apply_status(
      ctx,
      http_exception_response(404, "Not Found".to_json(), []),
    )
  }
}

///|
/// The error a route's unprovidable dependency is answered with. It is a `500`
/// because the fault is the app's wiring, not the request.
fn unresolved_dep(key : String) -> Error {
  http_error(500, "Unresolved dependency: " + key)
}

///|
/// Resolve a route's declared dependencies into one request scope, run `body`,
/// then close the scope — handing whatever error the body raised to the
/// teardowns before re-raising it, so a `yield` dependency's cleanup sees the
/// failure. A route with no dependencies never opens a scope.
fn App::run_with_deps(
  self : App,
  keys : Array[String],
  body : () -> Reply raise,
) -> Reply raise {
  if keys.is_empty() {
    return body()
  }
  let scope = match self.deps {
    Some(d) => (d.open)()
    None => raise unresolved_dep(keys[0])
  }
  let mut missing = ""
  for k in keys {
    if !(scope.resolve)(k) {
      missing = k
      break
    }
  }
  if missing != "" {
    // Whatever resolved before the gap still has to be released.
    let err = unresolved_dep(missing)
    (scope.close)(Some(err))
    raise err
  }
  let outcome : Result[Reply, Error] = Ok(body()) catch { err => Err(err) }
  match outcome {
    Ok(reply) => {
      (scope.close)(None)
      reply
    }
    Err(err) => {
      (scope.close)(Some(err))
      raise err
    }
  }
}

///|
/// The distinct entries of `names`, in first-seen order.
fn dedupe(names : Array[String]) -> Array[String] {
  let out : Array[String] = []
  for n in names {
    if !out.contains(n) {
      out.push(n)
    }
  }
  out
}

///|
/// Concatenate a streamed body's chunks — what the buffered half of the app sees
/// of a stream.
fn join_chunks(chunks : Array[Bytes]) -> Bytes {
  if chunks.length() == 1 {
    return chunks[0]
  }
  let buf = Buffer()
  for c in chunks {
    buf.write_bytes(c)
  }
  buf.to_bytes()
}

///|
/// Route a request through the middleware chain and return the reply in its
/// streamed form, plus the background queue the handler filled. `to_asgi` sends
/// each chunk as its own body event; a test reads `chunks` to see where the
/// boundaries fell. A route that is not a streaming one comes back as a single
/// chunk, so this answers every request, not only the streamed ones.
///
/// A middleware is typed buffered-in, buffered-out, so the chain is run over the
/// joined body and the chunks are kept only when what came back is what went in.
/// A middleware that rewrote the body — `gzip` — has produced something the old
/// boundaries no longer describe, and cutting the new bytes at them would send a
/// corrupt stream.
pub fn App::handle_with_stream(
  self : App,
  request : @moonasgi.Request,
) -> (@moonasgi.StreamingResponse, BackgroundTasks) {
  let bg = BackgroundTasks::new()
  let stream : Ref[@moonasgi.StreamingResponse?] = Ref(None)
  let base : @moonasgi.Handler = req => self.route_and_dispatch(req, bg, stream)
  let resp = @moonasgi.compose(self.middlewares, base)(request)
  let out = match stream.val {
    Some(s) if join_chunks(s.chunks) == resp.body =>
      @moonasgi.StreamingResponse::new(
        status=resp.status,
        headers=resp.headers,
        chunks=s.chunks,
        trailers=s.trailers,
        early_hints=s.early_hints,
      )
    _ =>
      @moonasgi.StreamingResponse::new(
        status=resp.status,
        headers=resp.headers,
        chunks=[resp.body],
      )
  }
  (out, bg)
}

///|
/// Route a request through the middleware chain and return both the response and
/// the background queue the handler filled — the caller (`to_asgi`, or a test)
/// runs the queue after the response is sent. `handle` is the plain-response
/// wrapper over this.
pub fn App::handle_with_background(
  self : App,
  request : @moonasgi.Request,
) -> (@moonasgi.Response, BackgroundTasks) {
  let (s, bg) = self.handle_with_stream(request)
  (@moonasgi.Response::new(s.status, s.headers, join_chunks(s.chunks)), bg)
}

///|
/// Route a request to its handler through the middleware chain, returning 404
/// when no path matches and 405 when a path matches but no method does. Any
/// error a handler raises is mapped to a response by the exception handlers.
/// Background tasks a handler scheduled are dropped on this path; use
/// `handle_with_background` (as `to_asgi` does) to run them.
pub fn App::handle(
  self : App,
  request : @moonasgi.Request,
) -> @moonasgi.Response {
  self.handle_with_background(request).0
}

///|
/// Strip a mount `prefix` off `path` by whole segments, returning the sub-app's
/// path (`"/"` when the request hits the mount root). `None` when `path` does not
/// lie under `prefix` — the comparison is segment-wise, so `/sub` does not match
/// `/subway`.
fn strip_prefix(prefix : String, path : String) -> String? {
  let pp = segments(prefix)
  let ph = segments(path)
  if pp.length() > ph.length() {
    return None
  }
  for i = 0; i < pp.length(); i = i + 1 {
    if pp[i] != ph[i] {
      return None
    }
  }
  let sb = StringBuilder()
  for i = pp.length(); i < ph.length(); i = i + 1 {
    sb.write_string("/")
    sb.write_string(ph[i])
  }
  let rest = sb.to_string()
  if rest == "" {
    Some("/")
  } else {
    Some(rest)
  }
}

///|
async fn drain_body(receive : @moonasgi.Receive) -> Bytes {
  let buf = Buffer()
  let mut more = true
  while more {
    match receive() {
      HttpRequest(body~, more_body~) => {
        buf.write_bytes(body)
        more = more_body
      }
      _ => more = false
    }
  }
  buf.to_bytes()
}

///|
/// This app's hooks as a moonasgi `LifespanHandler` — the synchronous core, which is
/// what makes boot and teardown testable on every backend without a server. Mounted
/// apps are included: a mount is part of the composition being started, and nothing
/// else would ever drive its hooks.
pub fn App::lifespan_handler(self : App) -> @moonasgi.LifespanHandler {
  @moonasgi.LifespanHandler::new(
    on_startup=_scope => {
      match self.run_startup_hooks() {
        None => Complete
        Some(why) => Failed(message=why)
      }
    },
    on_shutdown=_scope => {
      match self.run_shutdown_hooks() {
        None => Complete
        Some(why) => Failed(message=why)
      }
    },
  )
}

///|
/// Answer the ASGI lifespan protocol: run each server message through the handler
/// above and send back its reply. The run ends on shutdown, or on a failed startup —
/// ASGI has the server abort the boot there and never send `lifespan.shutdown`.
async fn App::serve_lifespan(
  self : App,
  scope : @moonasgi.Scope,
  receive : @moonasgi.Receive,
  send : @moonasgi.Send,
) -> Unit {
  let handler = self.lifespan_handler()
  for ;; {
    let event = receive()
    let replies = @moonasgi.run_lifespan(handler, scope, [event])
    for reply in replies {
      send(reply)
    }
    if event is LifespanShutdown {
      break
    }
    if replies.iter().any(r => r is LifespanStartupFailed(_)) {
      break
    }
  }
}

///|
/// Run every startup hook, this app's mounts included, stopping at the first that
/// raises and returning its message.
fn App::run_startup_hooks(self : App) -> String? {
  for hook in self.startup_hooks {
    hook() catch {
      err => return Some(err.to_string())
    }
  }
  for mount in self.mounts {
    if mount.1 is Sub(sub) && sub.run_startup_hooks() is Some(why) {
      return Some(why)
    }
  }
  None
}

///|
/// Run every shutdown hook in reverse registration order, mounts first since they
/// were started last. Every hook runs even if an earlier one raised; the first
/// failure is what comes back.
fn App::run_shutdown_hooks(self : App) -> String? {
  let mut failure = None
  for i = self.mounts.length() - 1; i >= 0; i = i - 1 {
    if self.mounts[i].1 is Sub(sub) &&
      sub.run_shutdown_hooks() is Some(why) &&
      failure is None {
      failure = Some(why)
    }
  }
  for i = self.shutdown_hooks.length() - 1; i >= 0; i = i - 1 {
    self.shutdown_hooks[i]() catch {
      err => if failure is None { failure = Some(err.to_string()) }
    }
  }
  failure
}

///|
/// Compile the app to a moonasgi `AsgiApp` a server can run: drain the request
/// body, route it, and stream the response back over the SEAM.
pub fn App::to_asgi(self : App) -> @moonasgi.AsgiApp {
  (scope, receive, send) => {
    match scope {
      Http(hs) => {
        let body = drain_body(receive)
        let request : @moonasgi.Request = {
          http_method: hs.http_method,
          path: hs.path,
          query_string: hs.query_string,
          headers: hs.headers,
          body,
        }
        let (resp, bg) = self.handle_with_stream(request)
        // moonasgi lowers the chunks: one body event each, `more_body` false only
        // on the last, and trailers after them when the route declared any.
        for event in resp.events() {
          send(event)
        }
        // The response is on the wire; now drain any background tasks.
        bg.run()
      }
      WebSocket(wss) => self.serve_websocket(wss, receive, send)
      Lifespan(_) => self.serve_lifespan(scope, receive, send)
    }
  }
}

///|
pub extend Method with Eq::{not_equal, equal}
