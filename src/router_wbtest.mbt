///|
/// `deprecated` and `include_in_schema` are the two group attributes a route
/// cannot undo, and a router is a value, so the same one can be included twice.
async test "include_router: deprecated marks the group, include_in_schema hides it" {
  let admin = @route.Router::new()
  admin.get("/panel", _ctx => @status.text(200, "panel"))
  admin.get(
    "/probe",
    _ctx => @status.text(200, "probe"),
    include_in_schema=false,
  )
  let app = App::new()
  app.include_router(admin, prefix="/admin", deprecated=true)
  let doc = app.openapi()
  let dep = match op_of(doc, "/admin/panel", "get") {
    Some(Object(op)) => op.get("deprecated")
    _ => None
  }
  assert_eq(dep, Some(Json(true)))
  // A route that opted out of the schema stays out, and still answers.
  assert_eq(path_exists(doc, "/admin/probe"), false)
  assert_eq(app.handle(mkreq("GET", "/admin/probe")).status, 200)
  // Included again elsewhere, hidden: the routes work, the document is empty.
  let quiet = App::new()
  quiet.include_router(admin, prefix="/q", include_in_schema=false)
  assert_eq(path_exists(quiet.openapi(), "/q/panel"), false)
  assert_eq(quiet.handle(mkreq("GET", "/q/panel")).status, 200)
}

///|
test "include_router: group responses are documented under the route's own" {
  let r = @route.Router::new()
  r.get("/a", _ctx => @status.text(200, "a"), responses=[
    @endpoint.ResponseSpec::new(404, description="the route says"),
  ])
  let app = App::new()
  app.include_router(r, responses=[
    @endpoint.ResponseSpec::new(401, description="the group says"),
    @endpoint.ResponseSpec::new(404, description="the group says"),
  ])
  let rs = op_responses(app.openapi(), "/a", "get")
  assert_eq(resp_desc(rs, "401"), "the group says")
  // Both name a 404; the one declared at the route is the one that stands.
  assert_eq(resp_desc(rs, "404"), "the route says")
  assert_eq(resp_desc(rs, "200"), "OK")
}

///|
/// A streaming route registered on a `Router` streams once it is included, and
/// under the prefix it was included at.
async test "a router's streaming route still streams after include_router" {
  let feed = @route.Router::new()
  feed.stream("/events", _ctx => {
    @status.sse(e => {
      e.send(@sse.Event::of("one"))
      e.send(@sse.Event::of("two"))
    })
  })
  let app = App::new()
  app.include_router(feed, prefix="/v1")
  assert_eq(more_body_flags(app, mkreq("GET", "/v1/events")), [
    true, true, false,
  ])
}

///|
/// A hoop that writes its name on the way in and out of the reply's body.
fn tagging(name : String, log : Array[String]) -> @route.Hoop {
  (ctx, next) => {
    log.push(name + ">")
    let reply = next(ctx)
    log.push("<" + name)
    reply
  }
}

///|
async test "hoops: include call, router, then route, outermost first" {
  let log : Array[String] = []
  let inner = @route.Router::new()
  inner.hoop(tagging("router", log))
  inner.get(
    "/x",
    _ctx => {
      log.push("handler")
      @status.text(200, "x")
    },
    hoops=[tagging("route", log)],
  )
  let app = App::new()
  app.include_router(inner, prefix="/api", hoops=[tagging("include", log)])
  assert_eq(app.handle(mkreq("GET", "/api/x")).status, 200)
  assert_eq(log, [
    "include>", "router>", "route>", "handler", "<route", "<router", "<include",
  ])
}

///|
async test "hoops: one can answer for the route, before its security runs" {
  let app = App::new()
  app.secure_oauth2(
    "OAuth2",
    @security.OAuth2PasswordBearer::new("/token", "s3cret"),
    scopes=[],
  )
  let closed : @route.Hoop = (_ctx, _next) => {
    Buffered(@status.text(503, "maintenance"))
  }
  app.get(
    "/x",
    _ctx => @status.text(200, "x"),
    security=[@security.SecurityRequirement::new("OAuth2")],
    hoops=[closed],
  )
  let r = app.handle(mkreq("GET", "/x"))
  assert_eq(r.status, 503)
  assert_eq(r.body, @utf8.encode("maintenance"))
}

///|
async test "hoops: one can change the reply, and an error it raises is handled" {
  let stamp : @route.Hoop = (ctx, next) => {
    match next(ctx) {
      Buffered(resp) =>
        Buffered({ ..resp, headers: [..resp.headers, ("x-hoop", "1")], })
      other => other
    }
  }
  let boom : @route.Hoop = (_ctx, _next) => {
    raise @exceptions.http_error(418, "no tea")
  }
  let app = App::new()
  app.get("/a", _ctx => @status.text(200, "a"), hoops=[stamp])
  app.get("/b", _ctx => @status.text(200, "b"), hoops=[boom])
  assert_eq(app.handle(mkreq("GET", "/a")).header("x-hoop"), Some("1"))
  assert_eq(app.handle(mkreq("GET", "/b")).status, 418)
}

///|
async test "include_router nests: prefixes join and tags accumulate" {
  let users = @route.Router::new()
  users.get("/{id:int}", ctx => @status.text(200, ctx.param("id").unwrap()), tags=[
    "user",
  ])
  let v1 = @route.Router::new()
  v1.include_router(users, prefix="/users", tags=["users"])
  let app = App::new()
  app.include_router(v1, prefix="/v1", tags=["v1"])
  assert_eq(app.handle(mkreq("GET", "/v1/users/7")).body, @utf8.encode("7"))
  assert_eq(op_tags(app.openapi(), "/v1/users/{id}", "get"), [
    "v1", "users", "user",
  ])
}

///|
struct Articles {
  log : Array[String]
}

///|
impl @route.View for Articles with fn get(self) {
  Some(_ctx => {
    self.log.push("list")
    @status.text(200, "list")
  })
}

///|
impl @route.View for Articles with fn post(_) {
  Some(_ctx => @status.text(201, "made"))
}

///|
async test "view: the methods a type answers, and a 405 naming them for the rest" {
  let log = []
  let app = App::new()
  app.view("/articles", Articles::{ log, }, name="articles")
  assert_eq(app.handle(mkreq("GET", "/articles")).status, 200)
  assert_eq(app.handle(mkreq("HEAD", "/articles")).status, 200)
  assert_eq(app.handle(mkreq("POST", "/articles")).status, 201)
  let refused = app.handle(mkreq("DELETE", "/articles"))
  assert_eq(refused.status, 405)
  assert_eq(refused.header("allow"), Some("GET, HEAD, POST"))
  assert_eq(log, ["list", "list"])
  assert_eq(app.url_for("articles"), Some("/articles"))
}

///|
struct Mute {}

///|
impl @route.View for Mute

///|
test "panic a view that answers nothing" {
  App::new().view("/mute", Mute::{ })
}

///|
async test "urls: a route table kept apart from its handlers" {
  let log = []
  let list : @route.ApiHandler = _ctx => @status.text(200, "posts")
  let one : @route.ApiHandler = ctx => {
    @status.text(200, "post " + ctx.param("slug").unwrap())
  }
  let app = App::new()
  app.urls([
    @route.path("/", _ctx => @status.text(200, "home"), name="home"),
    @route.group(
      "/blog",
      [
        @route.path("/", list),
        @route.path("/{slug}", one, methods=[Get, Delete], name="post"),
        @route.group("/drafts", [@route.path("/", list)], hoops=[
          tagging("drafts", log),
        ]),
      ],
      tags=["blog"],
    ),
    @route.view("/articles", Articles::{ log: [], }),
    @route.websocket("/live", ws => ws.close(), name="live"),
  ])
  assert_eq(app.handle(mkreq("GET", "/")).body, @utf8.encode("home"))
  assert_eq(app.handle(mkreq("HEAD", "/")).status, 200)
  assert_eq(app.handle(mkreq("POST", "/")).status, 405)
  assert_eq(app.handle(mkreq("GET", "/blog/")).body, @utf8.encode("posts"))
  assert_eq(
    app.handle(mkreq("DELETE", "/blog/hhh")).body,
    @utf8.encode("post hhh"),
  )
  assert_eq(app.handle(mkreq("GET", "/blog/drafts/")).status, 200)
  assert_eq(log, ["drafts>", "<drafts"])
  assert_eq(app.handle(mkreq("GET", "/articles")).status, 200)
  assert_eq(app.url_for("post", params=Map([("slug", "a")])), Some("/blog/a"))
  assert_eq(app.url_for("live"), Some("/live"))
  assert_eq(op_tags(app.openapi(), "/blog/{slug}", "get"), ["blog"])
}
