// Two ways to write routes besides one call per route: a type that answers the methods of one
// path (← Django's class-based views), and a route table kept apart from the handlers (← Django's
// `urlpatterns`, Starlette's `routes=[...]`).

///|
/// A type answering the methods of one path (← Django's class-based `View`). Implement the
/// methods it answers, each giving back its handler; the rest answer `None`, and a request for
/// one of those gets a `405` whose `Allow` lists what the view does answer.
///
/// ```moonbit nocheck
/// struct Articles { db : Db }
///
/// impl @moonapi.View for Articles with get(self) {
///   Some(ctx => self.db.list(ctx))
/// }
///
/// impl @moonapi.View for Articles with post(self) {
///   Some(ctx => self.db.create(ctx))
/// }
///
/// app.view("/articles", Articles::{ db })
/// ```
pub(open) trait View {
  fn get(Self) -> ApiHandler? = _
  fn head(Self) -> ApiHandler? = _
  fn post(Self) -> ApiHandler? = _
  fn put(Self) -> ApiHandler? = _
  fn patch(Self) -> ApiHandler? = _
  fn delete(Self) -> ApiHandler? = _
  fn options(Self) -> ApiHandler? = _
  fn trace(Self) -> ApiHandler? = _
}

///|
impl View with fn get(_) {
  None
}

///|
impl View with fn head(_) {
  None
}

///|
impl View with fn post(_) {
  None
}

///|
impl View with fn put(_) {
  None
}

///|
impl View with fn patch(_) {
  None
}

///|
impl View with fn delete(_) {
  None
}

///|
impl View with fn options(_) {
  None
}

///|
impl View with fn trace(_) {
  None
}

///|
/// Register the methods `view` answers at `path`, each as its own route sharing the arguments
/// given here. A view that answers no method is a mistake in the program and aborts.
pub fn Router::view(
  self : Router,
  path : String,
  view : &View,
  name~ : String = "",
  tags~ : Array[String] = [],
  security~ : Array[@security.SecurityRequirement] = [],
  dependencies~ : Array[String] = [],
  deprecated~ : Bool = false,
  include_in_schema~ : Bool = true,
  hoops~ : Array[Hoop] = [],
) -> Unit {
  // HEAD before GET: a GET route answers HEAD too, so an explicit one has to
  // be found first.
  let answers : Array[(Method, ApiHandler?)] = [
    (Head, view.head()),
    (Get, view.get()),
    (Post, view.post()),
    (Put, view.put()),
    (Patch, view.patch()),
    (Delete, view.delete()),
    (Options, view.options()),
    (Trace, view.trace()),
  ]
  let mut any = false
  for answer in answers {
    guard answer.1 is Some(handler) else { continue }
    any = true
    self.route(
      answer.0,
      path,
      handler,
      name~,
      tags~,
      security~,
      dependencies~,
      deprecated~,
      include_in_schema~,
      hoops~,
    )
  }
  if !any {
    abort("view at \{path} answers no method")
  }
}

///|
/// One entry of a route table: what it registers, given the router it lands on. `path`, `view`,
/// `websocket` and `group` make them.
pub type Url = (Router) -> Unit

///|
/// Register every entry of `urls`, in order — the order a request tries them in.
pub fn Router::urls(self : Router, urls : Array[Url]) -> Unit {
  for url in urls {
    url(self)
  }
}

///|
/// `handler` at `path` for each of `methods` (← Django's `path`, Starlette's `Route`, whose
/// default is the same `GET`, which answers `HEAD` too).
pub fn path(
  path : String,
  handler : ApiHandler,
  methods~ : Array[Method] = [Get],
  name~ : String = "",
) -> Url {
  router => {
    for verb in methods {
      router.route(verb, path, handler, name~)
    }
  }
}

///|
/// The methods `view` answers at `path`.
pub fn view(path : String, view : &View, name~ : String = "") -> Url {
  router => router.view(path, view, name~)
}

///|
/// A WebSocket route at `path` (← Starlette's `WebSocketRoute`).
pub fn websocket(
  path : String,
  handler : @socket.WsHandler,
  name~ : String = "",
) -> Url {
  router => router.websocket(path, handler, name~)
}

///|
/// `urls` under `prefix` (← Django's `include`, Starlette's `Mount` with routes; `include` is a
/// reserved word). The arguments reach every route of the group as
/// `Router::include_router` describes, and a group may hold groups.
pub fn group(
  prefix : String,
  urls : Array[Url],
  tags~ : Array[String] = [],
  security~ : Array[@security.SecurityRequirement] = [],
  dependencies~ : Array[String] = [],
  hoops~ : Array[Hoop] = [],
) -> Url {
  router => {
    let inner = Router::new()
    inner.urls(urls)
    router.include_router(
      inner,
      prefix~,
      tags~,
      security~,
      dependencies~,
      hoops~,
    )
  }
}
