// Tests for round-7 wiring: per-operation security (enforcement + OpenAPI),
// background tasks, sub-application mounting, and per-status exception handlers.

///|
/// Navigate `paths.<path>.<method>.security` to its array, `[]` if absent.
fn nav_op_security(doc : Json, path : String, verb : String) -> Array[Json] {
  match doc {
    Object(m) =>
      match m.get("paths") {
        Some(Object(p)) =>
          match p.get(path) {
            Some(Object(methods)) =>
              match methods.get(verb) {
                Some(Object(op)) =>
                  match op.get("security") {
                    Some(Array(a)) => a
                    _ => []
                  }
                _ => []
              }
            _ => []
          }
        _ => []
      }
    _ => []
  }
}

///|
/// Whether the merged document declares `path`.
fn path_exists(doc : Json, path : String) -> Bool {
  match doc {
    Object(m) =>
      match m.get("paths") {
        Some(Object(p)) => p.get(path) is Some(_)
        _ => false
      }
    _ => false
  }
}

///|
test "per-op security: a scoped route accepts a scoped token, denies otherwise" {
  let app = App::new()
  app.set_clock(() => 1000L)
  let bearer = @security.OAuth2PasswordBearer::new("/token", "s3cret")
  app.secure_oauth2("OAuth2", bearer, scopes=[("items", "manage items")])
  app.get("/items", _ctx => @status.text(200, "the items"), security=[
    @security.SecurityRequirement::new("OAuth2", scopes=["items"]),
  ])
  // A token carrying the `items` scope is admitted and the handler runs.
  let good = @security.create_access_token("alice", "s3cret", 1000L, scopes=[
    "items",
  ])
  let ok = app.handle(mkreq_auth("GET", "/items", "Bearer " + good))
  assert_eq(ok.status, 200)
  assert_eq(ok.body, @utf8.encode("the items"))
  // A valid token lacking the scope is refused before the handler: 403.
  let narrow = @security.create_access_token("alice", "s3cret", 1000L, scopes=[
    "me",
  ])
  assert_eq(
    app.handle(mkreq_auth("GET", "/items", "Bearer " + narrow)).status,
    403,
  )
  // No credentials at all: 401, and the challenge names the scope the route
  // wanted, so the client knows what to ask its provider for (RFC 6750 §3).
  let anon = app.handle(mkreq("GET", "/items"))
  assert_eq(anon.status, 401)
  assert_eq(anon.header("www-authenticate"), Some("Bearer scope=\"items\""))
}

///|
test "per-op security: an expired token is refused by the app clock" {
  let app = App::new()
  app.set_clock(() => 9000L) // long after the token's one-hour life
  let bearer = @security.OAuth2PasswordBearer::new("/token", "s3cret")
  app.secure_oauth2("OAuth2", bearer)
  app.get("/me", _ctx => @status.text(200, "me"), security=[
    @security.SecurityRequirement::new("OAuth2"),
  ])
  let token = @security.create_access_token("alice", "s3cret", 1000L) // exp = 4600
  assert_eq(app.handle(mkreq_auth("GET", "/me", "Bearer " + token)).status, 401)
}

///|
test "per-op security: the requirement surfaces as the OpenAPI security array" {
  let app = App::new()
  let bearer = @security.OAuth2PasswordBearer::new("/token", "s3cret")
  app.secure_oauth2("OAuth2", bearer, scopes=[("items", "manage items")])
  app.get("/items", _ctx => @status.text(200, "x"), security=[
    @security.SecurityRequirement::new("OAuth2", scopes=["items"]),
  ])
  let doc = app.openapi(version=OpenApi31)
  let sec = nav_op_security(doc, "/items", "get")
  assert_eq(sec.length(), 1)
  match sec[0] {
    Object(m) => {
      let scopes = match m.get("OAuth2") {
        Some(Array(a)) => a
        _ => []
      }
      assert_eq(scopes.length(), 1)
      assert_eq(scopes[0], Json("items"))
    }
    _ => assert_eq("security entry is an object", "")
  }
  // The scheme itself is still described under components.
  assert_eq(json_str(scheme_3x(doc, "OAuth2"), "type"), "oauth2")
}

///|
test "per-op security: a documentation-only scheme is not enforced" {
  // `add_security_scheme` describes but registers no enforcer, so a route naming
  // it is documented but open — FastAPI's split between a scheme and a dependency.
  let app = App::new()
  app.add_security_scheme("ApiKey", ApiKeyHeader(name="X-API-Key"))
  app.get("/open", _ctx => @status.text(200, "open"), security=[
    @security.SecurityRequirement::new("ApiKey"),
  ])
  assert_eq(app.handle(mkreq("GET", "/open")).status, 200)
  let sec = nav_op_security(app.openapi(version=OpenApi31), "/open", "get")
  assert_eq(sec.length(), 1)
}

///|
test "background task runs after the response is produced" {
  let log : Array[String] = []
  let app = App::new()
  app.route_bg(Get, "/notify", (_ctx, bg) => {
    bg.add_task(() => log.push("task"))
    log.push("handler")
    @status.text(202, "accepted")
  })
  let (resp, bg) = app.handle_with_background(mkreq("GET", "/notify"))
  // The response is built and the task is still queued, not run.
  assert_eq(resp.status, 202)
  assert_eq(log, ["handler"])
  assert_eq(bg.len(), 1)
  // Draining the queue (what `to_asgi` does after send) runs it, in order.
  bg.run()
  assert_eq(log, ["handler", "task"])
  // Idempotent: a second drain does nothing.
  bg.run()
  assert_eq(log, ["handler", "task"])
}

///|
test "background tasks run in order and a plain route schedules none" {
  let log : Array[String] = []
  let app = App::new()
  app.route_bg(Get, "/multi", (_ctx, bg) => {
    bg.add_task(() => log.push("a"))
    bg.add_task(() => log.push("b"))
    @status.text(200, "ok")
  })
  app.get("/plain", _ctx => @status.text(200, "ok"))
  let (_r1, bg1) = app.handle_with_background(mkreq("GET", "/multi"))
  bg1.run()
  assert_eq(log, ["a", "b"])
  let (_r2, bg2) = app.handle_with_background(mkreq("GET", "/plain"))
  assert_eq(bg2.len(), 0)
}

///|
test "mount: a sub-app answers under its prefix and its root" {
  let sub = App::new()
  sub.get("/hello", _ctx => @status.text(200, "sub-hello"))
  sub.get("/", _ctx => @status.text(200, "sub-root"))
  let app = App::new()
  app.get("/", _ctx => @status.text(200, "root"))
  app.mount("/sub", sub)
  assert_eq(
    app.handle(mkreq("GET", "/sub/hello")).body,
    @utf8.encode("sub-hello"),
  )
  assert_eq(app.handle(mkreq("GET", "/sub")).body, @utf8.encode("sub-root"))
  assert_eq(app.handle(mkreq("GET", "/")).body, @utf8.encode("root"))
  // Segment-wise prefix: `/subway` is not under `/sub`.
  assert_eq(app.handle(mkreq("GET", "/subway")).status, 404)
  // A path under the prefix the sub-app doesn't define is the sub-app's 404.
  assert_eq(app.handle(mkreq("GET", "/sub/missing")).status, 404)
}

///|
test "mount: the sub-app keeps its own middleware and security" {
  let sub = App::new()
  sub.set_clock(() => 1000L)
  let bearer = @security.OAuth2PasswordBearer::new("/token", "s3cret")
  sub.secure_oauth2("OAuth2", bearer, scopes=[("admin", "")])
  sub.get("/panel", _ctx => @status.text(200, "panel"), security=[
    @security.SecurityRequirement::new("OAuth2", scopes=["admin"]),
  ])
  let app = App::new()
  app.mount("/admin", sub)
  // Unauthenticated under the mount -> the sub-app's 401.
  assert_eq(app.handle(mkreq("GET", "/admin/panel")).status, 401)
  // With an admin token -> 200.
  let tok = @security.create_access_token("root", "s3cret", 1000L, scopes=[
    "admin",
  ])
  assert_eq(
    app.handle(mkreq_auth("GET", "/admin/panel", "Bearer " + tok)).status,
    200,
  )
}

///|
test "mount: a sub-app's background tasks bubble up to the request" {
  let log : Array[String] = []
  let sub = App::new()
  sub.route_bg(Get, "/work", (_ctx, bg) => {
    bg.add_task(() => log.push("sub-task"))
    @status.text(200, "queued")
  })
  let app = App::new()
  app.mount("/x", sub)
  let (resp, bg) = app.handle_with_background(mkreq("GET", "/x/work"))
  assert_eq(resp.status, 200)
  assert_eq(bg.len(), 1)
  bg.run()
  assert_eq(log, ["sub-task"])
}

///|
test "mount: merged OpenAPI lists sub-app paths under the prefix" {
  let sub = App::new()
  sub.get("/hello", _ctx => @status.text(200, "x"), summary="sub hello")
  let inner = App::new()
  inner.get("/ping", _ctx => @status.text(200, "x"))
  sub.mount("/deep", inner)
  let app = App::new()
  app.get("/top", _ctx => @status.text(200, "x"))
  app.mount("/sub", sub)
  let doc = app.openapi(version=OpenApi31)
  assert_eq(path_exists(doc, "/top"), true)
  assert_eq(path_exists(doc, "/sub/hello"), true)
  // Nested mounts flatten: /sub + /deep + /ping.
  assert_eq(path_exists(doc, "/sub/deep/ping"), true)
}

///|
test "mount: a sub-app's security scheme merges into the parent components" {
  let sub = App::new()
  sub.add_security_scheme("SubKey", ApiKeyHeader(name="X-Sub-Key"))
  sub.get("/r", _ctx => @status.text(200, "x"))
  let app = App::new()
  app.mount("/s", sub)
  let doc = app.openapi(version=OpenApi31)
  assert_eq(json_str(scheme_3x(doc, "SubKey"), "type"), "apiKey")
}

///|
test "status handler: a custom 404 replaces the default not-found" {
  let app = App::new()
  app.add_status_handler(404, _ctx => @status.text(404, "custom not found"))
  app.get("/here", _ctx => @status.text(200, "here"))
  let resp = app.handle(mkreq("GET", "/nowhere"))
  assert_eq(resp.status, 404)
  assert_eq(resp.body, @utf8.encode("custom not found"))
  // A real route is untouched.
  assert_eq(app.handle(mkreq("GET", "/here")).body, @utf8.encode("here"))
}

///|
test "status handler: rewrites a raised HttpException's status response" {
  let app = App::new()
  app.add_status_handler(418, _ctx => @status.text(418, "custom teapot"))
  app.get("/boom", _ctx => raise @mid.http_error(418, "teapot"))
  let resp = app.handle(mkreq("GET", "/boom"))
  assert_eq(resp.status, 418)
  assert_eq(resp.body, @utf8.encode("custom teapot"))
}

///|
test "status handler: a 405 method-mismatch can be customised too" {
  let app = App::new()
  app.add_status_handler(405, _ctx => @status.text(405, "no such method"))
  app.get("/only-get", _ctx => @status.text(200, "ok"))
  let resp = app.handle(mkreq("POST", "/only-get"))
  assert_eq(resp.status, 405)
  assert_eq(resp.body, @utf8.encode("no such method"))
}
