// Serving: the ASGI application an `App` compiles to. HTTP requests are matched to routes, then
// mounts, then answered 405 or 404; WebSocket connections the same way; the lifespan runs the
// hooks. Every request goes this one way, the layers outermost.

///|
/// Compile the app to an ASGI application a server can run: the layers around the router, in
/// registration order with the first outermost.
pub fn App::to_asgi(self : App) -> @moonasgi.AsgiApp {
  let mounted = self.mounts.map(entry => {
    let (prefix, target) = entry
    let app = match target {
      Sub(sub) => sub.to_asgi()
      Asgi(app) => app
    }
    (prefix, app)
  })
  let router : @moonasgi.AsgiApp = (scope, receive, send) => {
    match scope {
      Http(hs) => self.serve_http(hs, receive, send, mounted)
      WebSocket(ws) => self.serve_websocket(ws, receive, send, mounted)
      Lifespan(ls) => self.serve_lifespan(ls, receive, send)
    }
  }
  @mid.stack(self.layers, router)
}

///|
/// Run `request` through the app in-process and return the response, the way a server would
/// see it answered: the same ASGI path, layers included (← Starlette's `TestClient`). A
/// streamed response comes back with its body joined.
pub async fn App::handle(
  self : App,
  request : @moonasgi.Request,
) -> @moonasgi.Response {
  let query = @utf8.decode_lossy(request.query_string)
  let target = if query == "" {
    request.path
  } else {
    request.path + "?" + query
  }
  let r = @testing.Client::new(self.to_asgi()).request(
    http_method=request.http_method,
    path=target,
    headers=request.headers,
    body=request.body,
  )
  @moonasgi.Response::new(r.status, r.headers, r.body)
}

///|
/// The method a request names. A name that is not a token matches no route.
fn parse_method(s : String) -> @route.Method? {
  try @method.Method::of(s) catch {
    _ => None
  } noraise {
    m => Some(m)
  }
}

///|
/// Strip a mount `prefix` off `path` by whole segments, returning the sub-app's
/// path (`"/"` when the request hits the mount root). `None` when `path` does not
/// lie under `prefix` — the comparison is segment-wise, so `/sub` does not match
/// `/subway`.
fn strip_prefix(prefix : String, path : String) -> String? {
  let pp = @route.segments(prefix)
  let ph = @route.segments(path)
  if pp.length() > ph.length() {
    return None
  }
  for i, seg in pp {
    if seg != ph[i] {
      return None
    }
  }
  let rest = ph[pp.length():].iter().map(s => "/" + s).collect().join("")
  Some(if rest == "" { "/" } else { rest })
}

///|
/// The first mount `path` lies under, with the path that remains and the prefix in the form
/// `root_path` grows by.
fn mount_for(
  mounted : Array[(String, @moonasgi.AsgiApp)],
  path : String,
) -> (@moonasgi.AsgiApp, String, String)? {
  for entry in mounted {
    let (prefix, app) = entry
    if strip_prefix(prefix, path) is Some(rest) {
      return Some((app, rest, join_prefix(prefix, "")))
    }
  }
  None
}

///|
/// `raw` without the octets of `prefix` it starts with; unchanged when it does not.
fn strip_raw(raw : Bytes, prefix : String) -> Bytes {
  let p = @utf8.encode(prefix)
  if raw.length() >= p.length() && raw[:p.length()] == p[:] {
    let rest = raw[p.length():].to_owned()
    if rest.length() == 0 {
      b"/"
    } else {
      rest
    }
  } else {
    raw
  }
}

///|
/// The request a handler sees: the scope's line and headers with the body read in full.
fn request_of(hs : @moonasgi.HttpScope, body : Bytes) -> @moonasgi.Request {
  {
    http_method: hs.http_method,
    path: hs.path,
    query_string: hs.query_string,
    headers: hs.headers,
    body,
  }
}

///|
/// The request body, read to the end.
async fn read_body(receive : @moonasgi.Receive) -> Bytes {
  let buf = Buffer()
  for ;; {
    match receive() {
      HttpRequest(body~, more_body~) => {
        buf.write_bytes(body)
        if !more_body {
          break
        }
      }
      _ => break
    }
  }
  buf.to_bytes()
}

///|
/// Send `resp` whole. The body goes out for `HEAD` as well: the server drops it and keeps the
/// length it gives, which is what a `HEAD` answer is to carry.
async fn send_response(
  send : @moonasgi.Send,
  resp : @moonasgi.Response,
) -> Unit {
  send(
    HttpResponseStart(status=resp.status, headers=resp.headers, trailers=false),
  )
  send(HttpResponseBody(body=resp.body, more_body=false))
}

///|
/// Send `stream`: the early hints, the head, then the body as `stream.body` writes it, run beside
/// a watch on the connection that cancels it when the client goes (← Starlette's
/// `listen_for_disconnect`). For `HEAD` the body is not produced at all.
async fn send_stream(
  stream : @status.Stream,
  receive : @moonasgi.Receive,
  send : @moonasgi.Send,
  head : Bool,
) -> Unit {
  for links in stream.early_hints {
    send(HttpResponseEarlyHint(links~))
  }
  let trailing = stream.trailers && !head
  send(
    HttpResponseStart(
      status=stream.status,
      headers=stream.headers,
      trailers=trailing,
    ),
  )
  if head {
    send(HttpResponseBody(body=b"", more_body=false))
    return
  }
  let writer = @status.Writer::new(chunk => {
    send(HttpResponseBody(body=chunk, more_body=true))
  })
  let gone = Ref(false)
  @async.with_task_group(g => {
    g.spawn_bg(no_wait=true, () => {
      while !(receive() is HttpDisconnect) {

      }
      gone.val = true
      g.return_immediately(())
    })
    (stream.body)(writer)
  })
  if gone.val {
    return
  }
  send(HttpResponseBody(body=b"", more_body=false))
  if trailing {
    send(HttpResponseTrailers(headers=writer.trailers(), more_trailers=false))
  }
}

///|
/// An HTTP request: the first route whose path and method match, else the first mount it lies
/// under, else `405` (a path matched, no method did) or `404`, through the status handlers.
async fn App::serve_http(
  self : App,
  hs : @moonasgi.HttpScope,
  receive : @moonasgi.Receive,
  send : @moonasgi.Send,
  mounted : Array[(String, @moonasgi.AsgiApp)],
) -> Unit {
  let verb = parse_method(hs.http_method)
  let allowed : Array[String] = []
  for route in self.router.routes {
    guard route.pattern.bind(hs.path) is Some(params) else { continue }
    // A GET route answers HEAD too, as Starlette's does.
    if verb is Some(v) && (route.verb == v || (v is Head && route.verb is Get)) {
      self.answer(route, params, hs, receive, send, head=verb is Some(Head))
      return
    }
    allowed.push(route.verb.name())
    if route.verb is Get {
      allowed.push("HEAD")
    }
  }
  if mount_for(mounted, hs.path) is Some((app, rest, prefix)) {
    let scope : @moonasgi.HttpScope = {
      ..hs,
      path: rest,
      raw_path: strip_raw(hs.raw_path, prefix),
      root_path: hs.root_path + prefix,
    }
    app(Http(scope), receive, send)
    return
  }
  if allowed.is_empty() &&
    self.redirect_slashes &&
    self.slash_twin(hs.path) is Some(twin) {
    let query = @utf8.decode_lossy(hs.query_string)
    let location = hs.root_path +
      twin +
      (if query.is_empty() { "" } else { "?" + query })
    send_response(send, @status.redirect(location))
    return
  }
  let ctx = @ctx.Context::new(request_of(hs, b""), scope=hs)
  let resp = if allowed.length() > 0 {
    // RFC 9110 §15.5.6 requires the Allow header on a 405; a client that probes
    // a resource reads it rather than guessing.
    http_exception_response(405, Json("Method Not Allowed"), [
      ("allow", dedupe(allowed).join(", ")),
    ])
  } else {
    http_exception_response(404, Json("Not Found"), [])
  }
  send_response(send, self.apply_status(ctx, resp))
}

///|
/// `path` with its trailing slashes removed, or with one added, when a route
/// matches that form; Starlette strips every trailing slash the same way.
fn App::slash_twin(self : App, path : String) -> String? {
  if path == "/" {
    return None
  }
  let twin = if path.has_suffix("/") {
    path.trim_end(chars="/").to_owned()
  } else {
    path + "/"
  }
  guard !twin.is_empty() else { return None }
  for route in self.router.routes {
    if route.pattern.bind(twin) is Some(_) {
      return Some(twin)
    }
  }
  None
}

///|
/// Answer a matched route: read the body, run the route, send what it produced, then run the
/// background tasks.
async fn App::answer(
  self : App,
  route : @route.Route,
  params : Map[String, String],
  hs : @moonasgi.HttpScope,
  receive : @moonasgi.Receive,
  send : @moonasgi.Send,
  head~ : Bool,
) -> Unit {
  let ctx = @ctx.Context::new(
    request_of(hs, read_body(receive)),
    params~,
    scope=hs,
  )
  match self.run_route(route, ctx) {
    Buffered(resp) => send_response(send, resp)
    Streamed(stream) => send_stream(stream, receive, send, head)
  }
  ctx.background.run()
}

///|
/// Security, then validation, then the declared dependencies around the handler. Whatever
/// fails becomes a response here, so what comes back is always something to send.
async fn App::run_route(
  self : App,
  route : @route.Route,
  ctx : @ctx.Context,
) -> @route.Reply {
  if self.enforce_security(ctx, route.security) is Some(denied) {
    return Buffered(self.apply_status(ctx, denied))
  }
  if route.validate && route.endpoint is Some(ep) {
    let errs = ep.validate(ctx)
    if errs.length() > 0 {
      return Buffered(self.apply_status(ctx, @schema.unprocessable(errs)))
    }
  }
  self.run_with_deps(route.dependencies, () => (route.run)(ctx)) catch {
    e => Buffered(self.dispatch_exception(ctx, e))
  }
}

///|
/// The error a route's unprovidable dependency is answered with. It is a `500`
/// because the fault is the app's wiring, not the request.
fn unresolved_dep(key : String) -> Error {
  @exceptions.http_error(500, "Unresolved dependency: " + key)
}

///|
/// Resolve a route's declared dependencies into one request scope, run `body`,
/// then close the scope — handing whatever error the body raised to the
/// teardowns before re-raising it, so a `yield` dependency's cleanup sees the
/// failure. A route with no dependencies never opens a scope.
async fn App::run_with_deps(
  self : App,
  keys : Array[String],
  body : async () -> @route.Reply,
) -> @route.Reply {
  if keys.is_empty() {
    return body()
  }
  let scope = match self.deps {
    Some(d) => (d.open)()
    None => raise unresolved_dep(keys[0])
  }
  if keys.iter().find_first(k => !(scope.resolve)(k)) is Some(missing) {
    // Whatever resolved before the gap still has to be released.
    let err = unresolved_dep(missing)
    (scope.close)(Some(err))
    raise err
  }
  let outcome : Result[@route.Reply, Error] = Ok(body()) catch {
    err => Err(err)
  }
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
/// Enforce a route's security requirements. `None` means allow (nothing to
/// enforce, or a requirement passed); `Some(resp)` is the 401/403 to return.
/// Requirements are alternatives (OpenAPI OR-semantics): the first enforceable
/// one that passes admits the request; if every enforceable requirement fails,
/// the last failure response is returned. A requirement naming a
/// documentation-only scheme (no enforcer) grants nothing by itself.
fn App::enforce_security(
  self : App,
  ctx : @ctx.Context,
  reqs : Array[@security.SecurityRequirement],
) -> @moonasgi.Response? {
  if reqs.is_empty() {
    return None
  }
  let now = (self.clock)()
  let mut enforceable = false
  let mut last : @moonasgi.Response? = None
  for r in reqs {
    guard self.enforcers.get(r.scheme) is Some(enf) else { continue }
    enforceable = true
    match enf(ctx, @security.SecurityScopes::new(scopes=r.scopes), now) {
      Ok(_) => return None
      Err(resp) => last = Some(resp)
    }
  }
  if enforceable {
    last
  } else {
    None
  }
}

///|
/// Rewrite an error-path response through a registered per-status handler, if one
/// is registered for its status; otherwise pass it through unchanged.
fn App::apply_status(
  self : App,
  ctx : @ctx.Context,
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
  ctx : @ctx.Context,
  err : Error,
) -> @moonasgi.Response {
  for h in self.exception_handlers {
    if h(ctx, err) is Some(resp) {
      return resp
    }
  }
  self.apply_status(ctx, default_exception_response(err))
}

///|
/// The built-in fallback when no registered handler claims a raised error: an
/// `HttpException` becomes its own status and detail; anything else is a
/// `500 {"detail": "Internal Server Error"}`. This is always in effect, so a
/// handler that raises `HttpException` needs no explicit registration.
fn default_exception_response(err : Error) -> @moonasgi.Response {
  match err {
    @exceptions.HttpException(status~, detail~, headers~) =>
      http_exception_response(status, detail, headers)
    _ => http_exception_response(500, Json("Internal Server Error"), [])
  }
}

///|
/// The response for an `HttpException`: `{"detail": <detail>}` as JSON, at the
/// given status, with the exception's extra headers merged in after the
/// content-type.
fn http_exception_response(
  status : Int32,
  detail : Json,
  headers : Array[(String, String)],
) -> @moonasgi.Response {
  @moonasgi.Response::new(
    status,
    [("content-type", "application/json"), ..headers],
    @moonjson.dump({ "detail": detail }),
  )
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
/// A WebSocket connection: the first route whose path matches, else the first mount, else a
/// close, which a server answers with `403`. A handler that ends on the peer's disconnect ends
/// the connection quietly.
async fn App::serve_websocket(
  self : App,
  ws : @moonasgi.WebSocketScope,
  receive : @moonasgi.Receive,
  send : @moonasgi.Send,
  mounted : Array[(String, @moonasgi.AsgiApp)],
) -> Unit {
  for route in self.router.ws_routes {
    guard @route.Pattern::parse(route.path).bind(ws.path) is Some(params) else {
      continue
    }
    (route.handler)(@socket.WebSocket::new(ws, receive, send, params~)) catch {
      @socket.Disconnected(..) => ()
      e => raise e
    }
    return
  }
  if mount_for(mounted, ws.path) is Some((app, rest, prefix)) {
    let scope : @moonasgi.WebSocketScope = {
      ..ws,
      path: rest,
      raw_path: strip_raw(ws.raw_path, prefix),
      root_path: ws.root_path + prefix,
    }
    app(WebSocket(scope), receive, send)
    return
  }
  send(WebSocketClose(code=1000, reason=""))
}

///|
/// The lifespan protocol: run the startup hooks on `lifespan.startup` and the shutdown hooks on
/// `lifespan.shutdown`, with the scope's state. A failed startup ends the protocol there, as ASGI
/// has the server abort the boot and never send `lifespan.shutdown`.
async fn App::serve_lifespan(
  self : App,
  scope : @moonasgi.LifespanScope,
  receive : @moonasgi.Receive,
  send : @moonasgi.Send,
) -> Unit {
  for ;; {
    match receive() {
      LifespanStartup =>
        match self.start(scope.state) {
          None => send(LifespanStartupComplete)
          Some(why) => {
            send(LifespanStartupFailed(message=why))
            return
          }
        }
      LifespanShutdown => {
        match self.stop(scope.state) {
          None => send(LifespanShutdownComplete)
          Some(why) => send(LifespanShutdownFailed(message=why))
        }
        return
      }
      _ => ()
    }
  }
}

///|
/// Run every startup hook, this app's mounts included, stopping at the first that
/// raises and returning its message.
async fn App::start(self : App, state : Map[String, Json]) -> String? {
  for hook in self.startup_hooks {
    hook(state) catch {
      err => return Some(err.to_string())
    }
  }
  for mount in self.mounts {
    if mount.1 is Sub(sub) && sub.start(state) is Some(why) {
      return Some(why)
    }
  }
  None
}

///|
/// Run every shutdown hook in reverse registration order, mounts first since they
/// were started last. Every hook runs even if an earlier one raised; the first
/// failure is what comes back.
async fn App::stop(self : App, state : Map[String, Json]) -> String? {
  let mut failure = None
  for i = self.mounts.length() - 1; i >= 0; i = i - 1 {
    if self.mounts[i].1 is Sub(sub) &&
      sub.stop(state) is Some(why) &&
      failure is None {
      failure = Some(why)
    }
  }
  for i = self.shutdown_hooks.length() - 1; i >= 0; i = i - 1 {
    self.shutdown_hooks[i](state) catch {
      err => if failure is None { failure = Some(err.to_string()) }
    }
  }
  failure
}
