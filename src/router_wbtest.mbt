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
