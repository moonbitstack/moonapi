///|
/// What a mount prefix routes to: a moonapi sub-application, whose routes, security schemes and
/// lifespan hooks fold into the parent's, or any other ASGI application, which the parent can
/// only forward to.
enum Mount {
  Sub(App)
  Asgi(@moonasgi.AsgiApp)
}

///|
/// A lifespan hook: it gets the lifespan state, where what it stores reaches every request as
/// `ctx.state()`.
pub type Hook = async (Map[String, Json]) -> Unit

///|
/// A request-level middleware (← FastAPI's `@app.middleware("http")`): the request and
/// `call_next`, which runs the rest of the application, in; the response out. The response comes
/// back whole, so a stream behind it is gathered first; a middleware that must keep streams
/// streaming is a `@mid.Layer`.
pub type Middleware = async (
  @moonasgi.Request,
  async (@moonasgi.Request) -> @moonasgi.Response,
) -> @moonasgi.Response

///|
/// A moonapi application: routes and WebSocket routes, the layers around them, exception and
/// per-status handlers, mounts, the security schemes the OpenAPI document surfaces (with their
/// runtime enforcers), lifespan hooks, and the verification clock. Compiles to an ASGI
/// application any server (mooncat) can run.
pub struct App {
  router : @route.Router
  layers : Array[&@mid.Layer]
  exception_handlers : Array[@exceptions.ExceptionHandler]
  security_schemes : Array[@security.DeclaredScheme]
  enforcers : Map[String, @security.SecurityEnforcer]
  status_handlers : Map[Int32, (@ctx.Context) -> @moonasgi.Response]
  mounts : Array[(String, Mount)]
  // Run in registration order when the server starts, and in reverse when it stops,
  // so a resource is torn down before whatever it was built on.
  startup_hooks : Array[Hook]
  shutdown_hooks : Array[Hook]
  // What the emitted document says about itself. `enable_docs` serves the same
  // values, so the page a reader opens is not a different API from the one
  // `App::openapi` describes.
  mut info : @openapi.ApiInfo
  mut clock : () -> Int64
  // The container a route's declared `dependencies` are resolved through.
  mut deps : @di.Deps?
  redirect_slashes : Bool
  // Requests this API sends to its subscribers (← FastAPI's `app.webhooks`):
  // documented under OpenAPI 3.1's `webhooks`, never served. A route's path is
  // the webhook's name.
  webhooks : @route.Router
}

///|
/// Create an empty application. The verification clock defaults to `0` (Unix
/// epoch); a server sets a real one with `App::set_clock`, and tests inject a
/// fixed time so token expiry is deterministic.
///
/// `redirect_slashes` answers a path that matches no route, but would with its
/// trailing slash added or removed, with a `307` to that other path, the query
/// kept (← FastAPI's and Starlette's `redirect_slashes`, on by default in both).
/// `/` itself is never redirected, nor is a WebSocket connection.
///
/// ```mbt
/// let app = App::new()
/// app.get("/", _ctx => text(200, "Hello"))
/// ```
pub fn App::new(redirect_slashes~ : Bool = true) -> App {
  {
    router: @route.Router::new(),
    layers: [],
    exception_handlers: [],
    security_schemes: [],
    enforcers: {},
    status_handlers: {},
    mounts: [],
    startup_hooks: [],
    shutdown_hooks: [],
    info: @openapi.ApiInfo::new(),
    clock: () => 0L,
    deps: None,
    redirect_slashes,
    webhooks: @route.Router::new(),
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
pub fn App::depends(self : App, deps : @di.Deps) -> Unit {
  self.deps = Some(deps)
}

///|
/// Set what the OpenAPI document says about this API (← FastAPI's `FastAPI(title=…,
/// summary=…, description=…, contact=…, license_info=…, servers=…, openapi_tags=…,
/// openapi_external_docs=…)`). `App::openapi` and the `/openapi.json` route
/// `enable_docs` registers both read it, so the document a client fetches and the
/// one a test builds cannot describe different APIs. An argument left out keeps
/// what was set before.
pub fn App::describe(
  self : App,
  title? : String,
  summary? : String,
  api_version? : String,
  description? : String,
  terms_of_service? : String,
  contact? : @openapi.Contact?,
  license? : @openapi.License?,
  servers? : Array[@openapi.Server],
  tags? : Array[@openapi.Tag],
  external_docs? : @openapi.ExternalDocs?,
) -> Unit {
  let cur = self.info
  self.info = {
    title: title.unwrap_or(cur.title),
    summary: summary.unwrap_or(cur.summary),
    api_version: api_version.unwrap_or(cur.api_version),
    description: description.unwrap_or(cur.description),
    terms_of_service: terms_of_service.unwrap_or(cur.terms_of_service),
    contact: contact.unwrap_or(cur.contact),
    license: license.unwrap_or(cur.license),
    servers: servers.unwrap_or(cur.servers),
    tags: tags.unwrap_or(cur.tags),
    external_docs: external_docs.unwrap_or(cur.external_docs),
  }
}

///|
/// Run `hook` when the server starts, before it accepts the first request (← FastAPI's
/// `on_event("startup")`). Hooks run in the order they were registered; one that raises aborts
/// startup, and the server is told why.
pub fn App::on_startup(self : App, hook : Hook) -> Unit {
  self.startup_hooks.push(hook)
}

///|
/// Run `hook` when the server shuts down, after the last request has been served (← FastAPI's
/// `on_event("shutdown")`). Hooks run in reverse registration order, so a resource is released
/// before whatever it was opened from. A hook that raises does not stop the others — shutdown
/// reports the first failure once the rest have run.
pub fn App::on_shutdown(self : App, hook : Hook) -> Unit {
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
/// Wrap the application in `layer`, a moonasgi ASGI middleware (← Starlette's
/// `add_middleware`): moonasgi's `Cors`, `Gzip`, `TrustedHosts`, `HttpsRedirect` and
/// `ServerErrors`, or one of your own. The first registered is the outermost, layers and
/// `middleware` alike, and they wrap mounted applications too.
pub fn App::layer(self : App, layer : &@mid.Layer) -> Unit {
  self.layers.push(layer)
}

///|
/// Add a request-level middleware (← FastAPI's `@app.middleware("http")`), placed among the
/// layers in registration order.
pub fn App::middleware(self : App, mw : Middleware) -> Unit {
  self.layers.push(@mid.Wrap(inner => lift(mw, inner)))
}

///|
/// The ASGI application that runs `mw` around `inner` for HTTP requests. `call_next` hands
/// `inner` the request it is given; `inner`'s `receive`, once the body is out, waits for the
/// response to finish before saying `http.disconnect`, as a server does.
fn lift(mw : Middleware, inner : @moonasgi.AsgiApp) -> @moonasgi.AsgiApp {
  async fn(scope, receive, send) {
    guard scope is Http(hs) else { inner(scope, receive, send) }
    let request = request_of(hs, read_body(receive))
    let call_next = async fn(req : @moonasgi.Request) -> @moonasgi.Response {
      let scope = @moonasgi.Scope::Http({
        ..hs,
        http_method: req.http_method,
        path: req.path,
        query_string: req.query_string,
        headers: req.headers,
      })
      let delivered = Ref(false)
      let done = Ref(false)
      let finished = @cond_var.Cond()
      let status = Ref(500)
      let headers : Ref[Array[(String, String)]] = Ref([])
      let body = Buffer()
      let inner_receive = async fn() {
        if !delivered.val {
          delivered.val = true
          return @moonasgi.Event::HttpRequest(body=req.body, more_body=false)
        }
        while !done.val {
          finished.wait()
        }
        @moonasgi.Event::HttpDisconnect
      }
      let inner_send : @moonasgi.Send = event => {
        match event {
          HttpResponseStart(status=s, headers=h, ..) => {
            status.val = s
            headers.val = h
          }
          HttpResponseBody(body=b, more_body~) => {
            body.write_bytes(b)
            if !more_body {
              done.val = true
              finished.broadcast()
            }
          }
          _ => ()
        }
      }
      inner(scope, inner_receive, inner_send)
      done.val = true
      finished.broadcast()
      @moonasgi.Response::new(status.val, headers.val, body.to_bytes())
    }
    send_response(send, mw(request, call_next))
  }
}

///|
/// Register an exception handler. On a raised error the handlers are tried in
/// registration order; the first to return `Some(response)` wins. An
/// unhandled error falls through to the built-in mapping — an `HttpException`
/// becomes its own `status` / `detail`, anything else a `500`.
pub fn App::exception_handler(
  self : App,
  h : @exceptions.ExceptionHandler,
) -> Unit {
  self.exception_handlers.push(h)
}

///|
/// Register a per-status exception handler (← FastAPI's `add_exception_handler`
/// keyed by an HTTP status code). Whenever an error path yields `status` — a
/// routing `404` / `405`, or a raised `HttpException` (or the fallback `500`) —
/// the handler's response replaces the default, so an app can serve a custom
/// error page. Successful handler returns are never rewritten.
pub fn App::add_status_handler(
  self : App,
  status : Int32,
  handler : (@ctx.Context) -> @moonasgi.Response,
) -> Unit {
  self.status_handlers[status] = handler
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
  scheme : @security.SecurityScheme,
  description~ : String = "",
) -> Unit {
  self.security_schemes.push({ name, kind: scheme, description, })
}
