// Composition: routers folded in with `include_router`, foreign moonasgi
// handlers mounted behind a prefix, and named routes resolved back to paths.

///|
/// The `tags` of an operation, `[]` if it declares none — test helper.
fn op_tags(doc : Json, path : String, verb : String) -> Array[String] {
  match op_of(doc, path, verb) {
    Some(Object(op)) =>
      match op.get("tags") {
        Some(Array(xs)) =>
          xs.map(x => {
            match x {
              String(s) => s
              _ => ""
            }
          })
        _ => []
      }
    _ => []
  }
}

///|
test "include_router: the router's tags and security reach every route" {
  let items = @route.Router::new()
  items.get("/", _ctx => @status.text(200, "list"), tags=["listing"])
  items.get("/:id", ctx => @status.text(200, "item " + ctx.param("id").unwrap()))
  let app = App::new()
  app.set_clock(() => 1000L)
  app.secure_oauth2(
    "OAuth2",
    @security.OAuth2PasswordBearer::new("/token", "s3cret"),
    scopes=[("items", "manage items")],
  )
  app.include_router(items, prefix="/items", tags=["items"], security=[
    @security.SecurityRequirement::new("OAuth2", scopes=["items"]),
  ])
  // Both routes answer under the prefix, as the app's own.
  let tok = @security.create_access_token("alice", "s3cret", 1000L, scopes=[
    "items",
  ])
  assert_eq(
    app.handle(mkreq_auth("GET", "/items", "Bearer " + tok)).body,
    @utf8.encode("list"),
  )
  assert_eq(
    app.handle(mkreq_auth("GET", "/items/233", "Bearer " + tok)).body,
    @utf8.encode("item 233"),
  )
  // The router-level requirement is enforced on every one of them, including the
  // route that declared no security of its own.
  assert_eq(app.handle(mkreq("GET", "/items")).status, 401)
  assert_eq(app.handle(mkreq("GET", "/items/233")).status, 401)
  // And both carry it in the document, the router's tag ahead of the route's own.
  let doc = app.openapi()
  assert_eq(op_tags(doc, "/items", "get"), ["items", "listing"])
  assert_eq(op_tags(doc, "/items/{id}", "get"), ["items"])
  assert_eq(nav_op_security(doc, "/items", "get").length(), 1)
  assert_eq(nav_op_security(doc, "/items/{id}", "get").length(), 1)
}

///|
/// `deprecated` and `include_in_schema` are the two group attributes a route
/// cannot undo, and a router is a value, so the same one can be included twice.
test "include_router: deprecated marks the group, include_in_schema hides it" {
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
/// A router's WebSocket routes come along too, and take the prefix.
test "include_router: a WebSocket route joins under the prefix" {
  let joined : Array[String] = []
  let live = @route.Router::new()
  live.websocket("/feed/:room", ws => {
    ws.accept()
    joined.push(ws.param("room").unwrap_or("?"))
    ws.close()
  })
  let app = App::new()
  app.include_router(live, prefix="/live")
  match app.match_ws("/live/feed/qwq") {
    Some((handler, params)) => {
      let _ = @socket.drive_websocket(handler, [], params~)
      assert_eq(joined, ["qwq"])
    }
    None => fail("the included route should match under its prefix")
  }
  // The path the router knew it by is not a route on the app.
  assert_eq(app.match_ws("/feed/qwq") is None, true)
}

///|
test "mount_handler: a foreign moonasgi handler answers under its prefix" {
  let seen : Array[String] = []
  let files : @moonasgi.Handler = req => {
    seen.push(req.path)
    @moonasgi.Response::new(
      200,
      [("content-type", "text/css")],
      @utf8.encode("body{}"),
    )
  }
  let app = App::new()
  app.get("/", _ctx => @status.text(200, "app root"))
  app.mount_handler("/static", files)
  let got = app.handle(mkreq("GET", "/static/site.css"))
  assert_eq(got.status, 200)
  assert_eq(got.header("content-type"), Some("text/css"))
  assert_eq(@utf8.decode_lossy(got.body), "body{}")
  // The prefix is stripped before the handler sees the path.
  assert_eq(seen, ["/site.css"])
  // The app's own routes are untouched and the prefix still matches by segment.
  assert_eq(app.handle(mkreq("GET", "/")).body, @utf8.encode("app root"))
  assert_eq(app.handle(mkreq("GET", "/staticky/x")).status, 404)
  // A handler is not an application: it describes nothing and has no lifespan,
  // and neither fact stops the app from producing either.
  assert_eq(path_exists(app.openapi(), "/static/site.css"), false)
  let out = @moonasgi.run_lifespan(
    app.lifespan_handler(),
    @moonasgi.Scope::Lifespan(@moonasgi.LifespanScope::new()),
    [@moonasgi.Event::LifespanStartup],
  )
  assert_eq(out[0] == @moonasgi.Event::LifespanStartupComplete, true)
}

///|
test "url_for renders a named route's path, mount prefix included" {
  let blog = App::new()
  blog.get("/posts/:slug", _ctx => @status.text(200, "p"), name="post")
  let app = App::new()
  app.get("/users/:id/cards/:card", _ctx => @status.text(200, "c"), name="card")
  app.get("/health", _ctx => @status.text(200, "ok"))
  app.mount("/blog", blog)
  assert_eq(
    app.url_for("card", params=Map([("id", "233"), ("card", "qwq")])),
    Some("/users/233/cards/qwq"),
  )
  // A mounted route comes back as a client would call it, prefix and all.
  assert_eq(
    app.url_for("post", params=Map([("slug", "hhh")])),
    Some("/blog/posts/hhh"),
  )
  // A parameter the path needs and `params` does not carry yields nothing rather
  // than half a URL.
  assert_eq(app.url_for("card", params=Map([("id", "233")])), None)
  assert_eq(app.url_for("nope"), None)
  // Every route starts out unnamed, so the empty name addresses none of them.
  assert_eq(app.url_for(""), None)
}

///|
/// `name` has to survive every builder, or `url_for` answers for some verbs and
/// not others.
test "url_for finds a route registered through any verb helper" {
  let app = App::new()
  app.get("/g", _ctx => @status.text(200, "g"), name="g")
  app.post("/p", _ctx => @status.text(200, "p"), name="p")
  app.put("/u", _ctx => @status.text(200, "u"), name="u")
  app.patch("/a", _ctx => @status.text(200, "a"), name="a")
  app.delete("/d", _ctx => @status.text(200, "d"), name="d")
  app.route_bg(Get, "/b", (_ctx, _bg) => @status.text(200, "b"), name="b")
  for
    want in [
      ("g", "/g"),
      ("p", "/p"),
      ("u", "/u"),
      ("a", "/a"),
      ("d", "/d"),
      ("b", "/b"),
    ] {
    assert_eq(app.url_for(want.0), Some(want.1))
  }
  let r = @route.Router::new()
  r.get("/g", _ctx => @status.text(200, "g"), name="rg")
  r.post("/p", _ctx => @status.text(200, "p"), name="rp")
  r.put("/u", _ctx => @status.text(200, "u"), name="ru")
  r.patch("/a", _ctx => @status.text(200, "a"), name="ra")
  r.delete("/d", _ctx => @status.text(200, "d"), name="rd")
  r.route_bg(Get, "/b", (_ctx, _bg) => @status.text(200, "b"), name="rb")
  let host = App::new()
  host.include_router(r, prefix="/r")
  for
    want in [
      ("rg", "/r/g"),
      ("rp", "/r/p"),
      ("ru", "/r/u"),
      ("ra", "/r/a"),
      ("rd", "/r/d"),
      ("rb", "/r/b"),
    ] {
    assert_eq(host.url_for(want.0), Some(want.1))
  }
}
