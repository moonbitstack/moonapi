///|
async test "a convertor decides which route a path reaches" {
  let app = App::new()
  app.get("/items/{id:int}", ctx => {
    @status.text(200, "id " + ctx.param("id").unwrap())
  })
  app.get("/items/{name}", ctx => {
    @status.text(200, "name " + ctx.param("name").unwrap())
  })
  app.get("/static/{rest:path}", ctx => {
    @status.text(200, ctx.param("rest").unwrap())
  })
  assert_eq(app.handle(mkreq("GET", "/items/7")).body, @utf8.encode("id 7"))
  assert_eq(
    app.handle(mkreq("GET", "/items/seven")).body,
    @utf8.encode("name seven"),
  )
  assert_eq(
    app.handle(mkreq("GET", "/static/css/site.css")).body,
    @utf8.encode("css/site.css"),
  )
}

///|
async test "redirect_slashes: a missing trailing slash is added" {
  let app = App::new()
  app.get("/users/", _ctx => @status.text(200, "list"))
  let resp = app.handle(mkreq_full("GET", "/users", query=b"page=2"))
  assert_eq(resp.status, 307)
  assert_eq(header_of(resp.headers, "location"), Some("/users/?page=2"))
}

///|
async test "redirect_slashes: an extra trailing slash is removed" {
  let app = App::new()
  app.post("/users", _ctx => @status.text(201, "made"))
  let resp = app.handle(mkreq("POST", "/users//"))
  // 307 keeps the method and body, so a POST lands as a POST.
  assert_eq(resp.status, 307)
  assert_eq(header_of(resp.headers, "location"), Some("/users"))
}

///|
async test "redirect_slashes: off answers 404" {
  let app = App::new(redirect_slashes=false)
  app.get("/users/", _ctx => @status.text(200, "list"))
  assert_eq(app.handle(mkreq("GET", "/users")).status, 404)
  assert_eq(app.handle(mkreq("GET", "/users/")).status, 200)
}

///|
async test "redirect_slashes: a path that matched under another verb stays 405" {
  let app = App::new()
  app.get("/users", _ctx => @status.text(200, "list"))
  app.post("/users/", _ctx => @status.text(201, "made"))
  assert_eq(app.handle(mkreq("DELETE", "/users")).status, 405)
}

///|
async test "redirect_slashes: the location carries the mount prefix" {
  let sub = App::new()
  sub.get("/x/", _ctx => @status.text(200, "x"))
  let app = App::new()
  app.mount("/sub", sub)
  let resp = app.handle(mkreq("GET", "/sub/x"))
  assert_eq(resp.status, 307)
  assert_eq(header_of(resp.headers, "location"), Some("/sub/x/"))
}

///|
async test "redirect_slashes: nothing to redirect to is a 404" {
  let app = App::new()
  app.get("/users", _ctx => @status.text(200, "list"))
  assert_eq(app.handle(mkreq("GET", "/people/")).status, 404)
  assert_eq(app.handle(mkreq("GET", "/")).status, 404)
}

///|
test "url_for refuses a value its convertor would not match" {
  let app = App::new()
  app.get("/users/{id:int}", _ctx => @status.text(200, "u"), name="user")
  assert_eq(app.url_for("user", params=Map([("id", "7")])), Some("/users/7"))
  assert_eq(app.url_for("user", params=Map([("id", "seven")])), None)
}

///|
async test "a regular expression decides the route, and its groups are parameters" {
  let app = App::new()
  app.get(
    "/users/{id}",
    ctx => @status.text(200, ctx.param("id").unwrap_or("?")),
    name="user",
    regex="/users/(?P<id>[0-9]+)(?:/profile)?",
  )
  let got = app.handle(mkreq("GET", "/users/42/profile"))
  assert_eq(got.status, 200)
  assert_eq(got.body, b"42")
  assert_eq(app.handle(mkreq("GET", "/users/abc")).status, 404)
  // The template is still the route's name in the document and in `url_for`.
  assert_true(path_exists(app.openapi(), "/users/{id}"))
  assert_eq(app.url_for("user", params={ "id": "7" }), Some("/users/7"))
}

///|
async test "a glob decides the route, and its wildcards bind the template's parameters" {
  let app = App::new()
  app.get(
    "/assets/{file:path}",
    ctx => @status.text(200, ctx.param("file").unwrap_or("?")),
    glob="/assets/**.{css,js}",
  )
  assert_eq(app.handle(mkreq("GET", "/assets/a/b.css")).body, b"a/b")
  assert_eq(app.handle(mkreq("GET", "/assets/a/b.png")).status, 404)
}

///|
async test "routes are tried in order, a regex like any other" {
  let app = App::new()
  app.get("/items/new", _ctx => @status.text(200, "fixed"))
  app.get(
    "/items/{id}",
    _ctx => @status.text(200, "pattern"),
    regex="/items/.+",
  )
  assert_eq(app.handle(mkreq("GET", "/items/new")).body, b"fixed")
  assert_eq(app.handle(mkreq("GET", "/items/9")).body, b"pattern")
}

///|
async test "an included router's regex and glob sit under its prefix" {
  let router = @route.Router::new()
  router.get(
    "/users/{id}",
    ctx => @status.text(200, ctx.param("id").unwrap_or("?")),
    regex="/users/(?P<id>[0-9]+)",
  )
  router.get(
    "/files/{f}",
    _ctx => @status.text(200, "file"),
    glob="/files/*.txt",
  )
  let app = App::new()
  app.include_router(router, prefix="/api")
  assert_eq(app.handle(mkreq("GET", "/api/users/5")).body, b"5")
  assert_eq(app.handle(mkreq("GET", "/users/5")).status, 404)
  assert_eq(app.handle(mkreq("GET", "/api/files/a.txt")).status, 200)
}
