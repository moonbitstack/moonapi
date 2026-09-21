///|
fn mkreq(m : String, path : String) -> @moonasgi.Request {
  { http_method: m, path, query_string: b"", headers: [], body: b"", }
}

///|
fn mkreq_full(
  m : String,
  path : String,
  query? : Bytes = b"",
  body? : Bytes = b"",
) -> @moonasgi.Request {
  { http_method: m, path, query_string: query, headers: [], body, }
}

///|
/// Fetch a string field out of a JSON object, "" if absent — test helper.
fn json_str(j : Json, key : String) -> String {
  match j {
    Object(m) =>
      match m.get(key) {
        Some(String(s)) => s
        _ => ""
      }
    _ => ""
  }
}

///|
fn root_version(doc : Json, key : String) -> String {
  match doc {
    Object(m) =>
      match m.get(key) {
        Some(String(s)) => s
        _ => ""
      }
    _ => ""
  }
}

///|
test "routing: static, param, 404, 405" {
  let app = App::new()
  app.get("/hello", _ctx => text(200, "hi"))
  app.get("/users/:id", ctx => text(200, "user " + ctx.param("id").unwrap()))
  app.post("/users", _ctx => text(201, "created"))
  assert_eq(app.handle(mkreq("GET", "/hello")).status, 200)
  assert_eq(app.handle(mkreq("POST", "/users")).status, 201)
  let got = app.handle(mkreq("GET", "/users/42"))
  assert_eq(got.status, 200)
  assert_eq(got.body, @utf8.encode("user 42"))
  assert_eq(app.handle(mkreq("GET", "/nope")).status, 404)
  assert_eq(app.handle(mkreq("DELETE", "/hello")).status, 405)
}

///|
test "path param extraction" {
  let app = App::new()
  app.get("/a/:x/b/:y", ctx => {
    let x = ctx.param("x").unwrap()
    let y = ctx.param("y").unwrap()
    text(200, x + "," + y)
  })
  let got = app.handle(mkreq("GET", "/a/1/b/2"))
  assert_eq(got.body, @utf8.encode("1,2"))
  assert_eq(app.handle(mkreq("GET", "/a/1/b")).status, 404)
}

///|
test "query extraction" {
  let app = App::new()
  app.get("/search", ctx => {
    match ctx.query("q") {
      Some(q) => text(200, "q=" + q)
      None => unprocessable([ValidationError::missing(["query", "q"])])
    }
  })
  // present: value returned
  let ok = app.handle(mkreq_full("GET", "/search", query=b"limit=10&q=cat"))
  assert_eq(ok.status, 200)
  assert_eq(ok.body, @utf8.encode("q=cat"))
  // bare key yields empty value, not absence
  let bare = app.handle(mkreq_full("GET", "/search", query=b"q"))
  assert_eq(bare.body, @utf8.encode("q="))
  // absent: structured 422
  let miss = app.handle(mkreq_full("GET", "/search", query=b"limit=10"))
  assert_eq(miss.status, 422)
  assert_eq(miss.header("content-type"), Some("application/json"))
}

///|
test "json body extraction and 422" {
  let app = App::new()
  app.post("/items", ctx => {
    match ctx.json_field("name") {
      Some(String(name)) => text(201, "created " + name)
      _ => unprocessable([ValidationError::missing(["body", "name"])])
    }
  })
  let ok = app.handle(
    mkreq_full("POST", "/items", body=@utf8.encode("{\"name\":\"pen\"}")),
  )
  assert_eq(ok.status, 201)
  assert_eq(ok.body, @utf8.encode("created pen"))
  // whole body as Json
  let ctx : Context = {
    request: mkreq_full(
      "POST",
      "/items",
      body=@utf8.encode("{\"name\":\"pen\"}"),
    ),
    params: Map([]),
  }
  assert_eq(json_str(ctx.body_json().unwrap(), "name"), "pen")
  // missing field -> 422 with FastAPI-shaped detail
  let miss = app.handle(
    mkreq_full("POST", "/items", body=@utf8.encode("{\"other\":1}")),
  )
  assert_eq(miss.status, 422)
  // malformed / empty body -> None, not a crash
  assert_eq(ctx.body_json() is Some(_), true)
  let empty : Context = {
    request: mkreq_full("POST", "/items"),
    params: Map([]),
  }
  assert_eq(empty.body_json(), None)
}

///|
test "422 body shape mirrors FastAPI" {
  let body = validation_error_body([ValidationError::missing(["query", "q"])])
  let detail = match body {
    Object(m) =>
      match m.get("detail") {
        Some(Array(a)) => a
        _ => []
      }
    _ => []
  }
  assert_eq(detail.length(), 1)
  assert_eq(json_str(detail[0], "type"), "missing")
  assert_eq(json_str(detail[0], "msg"), "Field required")
}

///|
test "openapi emits path parameters" {
  let app = App::new()
  app.get("/users/:id", _ctx => text(200, "u"))
  let doc = app.openapi(version=OpenApi31)
  let params = match doc {
    Object(m) =>
      match m.get("paths") {
        Some(Object(p)) =>
          match p.get("/users/{id}") {
            Some(Object(methods)) =>
              match methods.get("get") {
                Some(Object(op)) =>
                  match op.get("parameters") {
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
  assert_eq(params.length(), 1)
  assert_eq(json_str(params[0], "name"), "id")
  assert_eq(json_str(params[0], "in"), "path")
}

///|
test "openapi multi-version output" {
  let app = App::new()
  app.get("/ping", _ctx => text(200, "pong"), summary="health check")
  app.post("/ping", _ctx => text(200, "pong"))
  assert_eq(root_version(app.openapi(version=OpenApi31), "openapi"), "3.1.0")
  assert_eq(root_version(app.openapi(version=OpenApi30), "openapi"), "3.0.3")
  assert_eq(root_version(app.openapi(version=Swagger20), "swagger"), "2.0")
  // one path with two methods
  let doc = app.openapi(version=OpenApi31)
  let n = match doc {
    Object(m) =>
      match m.get("paths") {
        Some(Object(p)) =>
          match p.get("/ping") {
            Some(Object(methods)) => methods.length()
            _ => 0
          }
        _ => 0
      }
    _ => 0
  }
  assert_eq(n, 2)
}

///|
/// The `get`/`post`/… `verb` operation at `path` in an OpenAPI document.
fn op_of(doc : Json, path : String, verb : String) -> Json? {
  guard doc is Object(m) else { return None }
  guard m.get("paths") is Some(Object(p)) else { return None }
  guard p.get(path) is Some(Object(methods)) else { return None }
  methods.get(verb)
}

///|
/// The `responses` object of an operation, empty if it has none — test helper.
fn op_responses(doc : Json, path : String, verb : String) -> Map[String, Json] {
  match op_of(doc, path, verb) {
    Some(Object(op)) =>
      match op.get("responses") {
        Some(Object(m)) => m
        _ => Map([])
      }
    _ => Map([])
  }
}

///|
/// The `description` of one response of an operation, "" if it declares no such
/// response — test helper.
fn resp_desc(responses : Map[String, Json], status : String) -> String {
  match responses.get(status) {
    Some(j) => json_str(j, "description")
    None => ""
  }
}

///|
test "openapi operation tags" {
  let app = App::new()
  app.get("/nav", _ctx => text(200, "ok"), tags=["ai", "navigator"])
  app.get("/plain", _ctx => text(200, "ok"))
  let doc = app.openapi(version=OpenApi31)
  // The tagged operation carries its tags, in registration order.
  let tags = match op_of(doc, "/nav", "get") {
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
  assert_eq(tags, ["ai", "navigator"])
  // An untagged operation omits the key entirely (FastAPI parity).
  let has_tags = match op_of(doc, "/plain", "get") {
    Some(Object(op)) => op.contains("tags")
    _ => false
  }
  assert_eq(has_tags, false)
}

///|
test "openapi operation deprecated flag" {
  let app = App::new()
  app.get("/old", _ctx => text(200, "ok"), deprecated=true)
  app.get("/new", _ctx => text(200, "ok"))
  let doc = app.openapi(version=OpenApi31)
  // The deprecated operation carries `"deprecated": true`.
  let dep = match op_of(doc, "/old", "get") {
    Some(Object(op)) => op.get("deprecated")
    _ => None
  }
  assert_eq(dep, Some(true.to_json()))
  // A live operation omits the key entirely (FastAPI parity — false is not emitted).
  let has_dep = match op_of(doc, "/new", "get") {
    Some(Object(op)) => op.contains("deprecated")
    _ => false
  }
  assert_eq(has_dep, false)
}

///|
/// The prose, the stable handle a client generator names its method after, and
/// the status the success response is documented under — three of the keyword
/// arguments a FastAPI path operation takes.
test "openapi operation description, operationId and status_code" {
  let app = App::new()
  app.post(
    "/items",
    _ctx => text(201, "made"),
    summary="create an item",
    description="Stores the item and answers with where it went.",
    operation_id="create_item",
    status_code=201,
  )
  app.get("/plain", _ctx => text(200, "ok"))
  let doc = app.openapi()
  guard op_of(doc, "/items", "post") is Some(Object(op)) else {
    fail("the operation should be present")
  }
  assert_eq(
    op.get("description"),
    Some("Stores the item and answers with where it went.".to_json()),
  )
  assert_eq(op.get("operationId"), Some("create_item".to_json()))
  // `status_code` is what the success response is keyed by, in place of 200.
  assert_eq(op_responses(doc, "/items", "post").keys().collect(), ["201"])
  // A route that says none of it emits none of it, the way FastAPI does.
  guard op_of(doc, "/plain", "get") is Some(Object(plain)) else {
    fail("the operation should be present")
  }
  assert_eq(plain.contains("description"), false)
  assert_eq(plain.contains("operationId"), false)
  assert_eq(op_responses(doc, "/plain", "get").keys().collect(), ["200"])
}

///|
/// A typed route's default response is keyed the same way; one that declares its
/// own responses is not overruled by a status the route only documents.
test "openapi status_code keys a typed endpoint's default response" {
  let app = App::new()
  app.post(
    "/items",
    _ctx => text(201, "made"),
    status_code=201,
    endpoint=Endpoint::new(params=[Param::new("q", InQuery, required=false)]),
  )
  app.post(
    "/declared",
    _ctx => text(200, "ok"),
    status_code=201,
    endpoint=Endpoint::new(responses=[ResponseSpec::new(200)]),
  )
  let doc = app.openapi()
  assert_eq(op_responses(doc, "/items", "post").keys().collect(), ["201"])
  assert_eq(op_responses(doc, "/declared", "post").keys().collect(), ["200"])
}

///|
/// `responses` documents what else an operation can answer, beside the success
/// response moonapi derives.
test "openapi operation responses join the derived one" {
  let app = App::new()
  app.get("/thing", _ctx => text(200, "x"), responses=[
    ResponseSpec::new(404, description="no such thing"),
  ])
  let rs = op_responses(app.openapi(), "/thing", "get")
  assert_eq(resp_desc(rs, "200"), "OK")
  assert_eq(resp_desc(rs, "404"), "no such thing")
}

///|
/// The escape hatch: `openapi_extra` goes in after everything moonapi generated,
/// so a caller can add a field the framework has no idea about, or replace one it
/// got wrong for them.
test "openapi_extra is merged last and overrides a generated field" {
  let app = App::new()
  app.get("/thing", _ctx => text(200, "x"), summary="generated", openapi_extra={
    "summary": "hand-written",
    "x-internal": true,
  })
  guard op_of(app.openapi(), "/thing", "get") is Some(Object(op)) else {
    fail("the operation should be present")
  }
  assert_eq(op.get("summary"), Some("hand-written".to_json()))
  assert_eq(op.get("x-internal"), Some(true.to_json()))
  // What it does not name is left as generated.
  assert_eq(op.contains("responses"), true)
}

///|
test "openapi richer info: description/contact/license + servers" {
  let app = App::new()
  app.get("/ping", _ctx => text(200, "ok"))
  let doc = app.openapi(
    version=OpenApi31,
    title="Greet",
    description="qwq api",
    contact=Some({ name: "heke1228", url: "", email: "emm@qq.com", }),
    license=Some({ name: "Apache-2.0", url: "https://apache.org", }),
    servers=[{ url: "https://api.example.com", description: "prod", }],
  )
  guard doc is Object(m) else { fail("doc should be an object") }
  guard m.get("info") is Some(Object(info)) else {
    fail("info should be present")
  }
  assert_eq(info.get("description"), Some("qwq api".to_json()))
  guard info.get("contact") is Some(Object(c)) else {
    fail("contact should be present")
  }
  assert_eq(c.get("name"), Some("heke1228".to_json()))
  assert_eq(c.get("email"), Some("emm@qq.com".to_json()))
  // An empty contact field is omitted, not emitted as "".
  assert_eq(c.get("url"), None)
  guard info.get("license") is Some(Object(l)) else {
    fail("license should be present")
  }
  assert_eq(l.get("name"), Some("Apache-2.0".to_json()))
  guard m.get("servers") is Some(Array(sv)) else {
    fail("servers should be present")
  }
  assert_eq(sv.length(), 1)
  guard sv[0] is Object(s0) else { fail("server should be an object") }
  assert_eq(s0.get("url"), Some("https://api.example.com".to_json()))
}

///|
/// Startup hooks run in registration order, shutdown hooks in reverse, and a mounted
/// app's hooks come along — a mount is part of the composition the server starts.
test "lifespan hooks run in order, mounts included" {
  let log : Array[String] = []
  let app = App::new()
  app.on_startup(() => log.push("open-db"))
  app.on_startup(() => log.push("warm-cache"))
  app.on_shutdown(() => log.push("close-db"))
  app.on_shutdown(() => log.push("flush-cache"))
  let sub = App::new()
  sub.on_startup(() => log.push("sub-open"))
  sub.on_shutdown(() => log.push("sub-close"))
  app.mount("/sub", sub)
  let scope = @moonasgi.Scope::Lifespan(@moonasgi.LifespanScope::new())
  let out = @moonasgi.run_lifespan(app.lifespan_handler(), scope, [
    @moonasgi.Event::LifespanStartup,
    @moonasgi.Event::LifespanShutdown,
  ])
  assert_eq(out.length(), 2)
  assert_eq(out[0] == @moonasgi.Event::LifespanStartupComplete, true)
  assert_eq(out[1] == @moonasgi.Event::LifespanShutdownComplete, true)
  assert_eq(log, [
    "open-db", "warm-cache", "sub-open", "sub-close", "flush-cache", "close-db",
  ])
}

///|
/// A startup hook that raises fails the boot with its message, and nothing after it
/// runs — ASGI has the server abort there rather than serve a half-built app.
test "a raising startup hook fails the boot" {
  let log : Array[String] = []
  let app = App::new()
  app.on_startup(() => log.push("first"))
  app.on_startup(() => raise Failure("no database at qwq:233"))
  app.on_startup(() => log.push("never"))
  let scope = @moonasgi.Scope::Lifespan(@moonasgi.LifespanScope::new())
  let out = @moonasgi.run_lifespan(app.lifespan_handler(), scope, [
    @moonasgi.Event::LifespanStartup,
  ])
  assert_eq(out.length(), 1)
  let failed = match out[0] {
    LifespanStartupFailed(message~) => message
    _ => "not a failure"
  }
  assert_eq(failed.contains("no database at qwq:233"), true)
  assert_eq(log, ["first"])
}

///|
/// A shutdown hook that raises does not strand the others: teardown keeps going and
/// reports the first failure once everything has had its turn.
test "a raising shutdown hook still lets the rest run" {
  let log : Array[String] = []
  let app = App::new()
  app.on_shutdown(() => log.push("last-registered-runs-first"))
  app.on_shutdown(() => raise Failure("flush failed"))
  app.on_shutdown(() => log.push("still-runs"))
  let scope = @moonasgi.Scope::Lifespan(@moonasgi.LifespanScope::new())
  let out = @moonasgi.run_lifespan(app.lifespan_handler(), scope, [
    @moonasgi.Event::LifespanShutdown,
  ])
  let failed = match out[0] {
    LifespanShutdownFailed(message~) => message
    _ => "not a failure"
  }
  assert_eq(failed.contains("flush failed"), true)
  assert_eq(log, ["still-runs", "last-registered-runs-first"])
}

///|
/// `enable_docs` serves the three pages FastAPI serves — the spec, Swagger UI and
/// ReDoc — and keeps all three out of the spec they describe, so turning docs on
/// does not change what a client reads.
test "enable_docs serves the spec, Swagger UI and ReDoc without joining the spec" {
  let app = App::new()
  app.get("/hello", _ctx => text(200, "hhh"), summary="greet")
  app.describe(title="qwq api")
  app.enable_docs()
  let spec = app.handle(mkreq("GET", "/openapi.json"))
  assert_eq(spec.status, 200)
  assert_eq(spec.header("content-type"), Some("application/json"))
  let docs = app.handle(mkreq("GET", "/docs"))
  assert_eq(docs.status, 200)
  assert_eq(docs.header("content-type"), Some("text/html; charset=utf-8"))
  let docs_body = @utf8.decode_lossy(docs.body)
  assert_eq(docs_body.contains("swagger-ui"), true)
  assert_eq(docs_body.contains("/openapi.json"), true)
  assert_eq(docs_body.contains("qwq api"), true)
  let redoc = app.handle(mkreq("GET", "/redoc"))
  assert_eq(redoc.status, 200)
  let redoc_body = @utf8.decode_lossy(redoc.body)
  assert_eq(redoc_body.contains("<redoc spec-url=\"/openapi.json\">"), true)
  // The documented surface is still just the one route.
  let paths = match app.openapi() {
    Object(m) =>
      match m.get("paths") {
        Some(Object(p)) => p.keys().collect()
        _ => []
      }
    _ => []
  }
  assert_eq(paths, ["/hello"])
}

///|
/// Each documentation page can be turned off on its own.
test "enable_docs leaves off whatever is passed None" {
  let app = App::new()
  app.enable_docs(docs_url=None, redoc_url=None)
  assert_eq(app.handle(mkreq("GET", "/openapi.json")).status, 200)
  assert_eq(app.handle(mkreq("GET", "/docs")).status, 404)
  assert_eq(app.handle(mkreq("GET", "/redoc")).status, 404)
}

///|
/// A path parameter's `name` has to correspond to a template expression in the path
/// key, or the document is invalid and Swagger UI has nothing to substitute into.
/// The router keeps its own `:id` syntax; only the emitted document is templated.
test "openapi keys paths by their template form" {
  let app = App::new()
  app.get("/users/:id/posts/:slug", _ctx => text(200, "hhh"))
  let doc = app.openapi()
  let keys = match doc {
    Object(m) =>
      match m.get("paths") {
        Some(Object(p)) => p.keys().collect()
        _ => []
      }
    _ => []
  }
  assert_eq(keys, ["/users/{id}/posts/{slug}"])
  // The route itself still matches the request as written.
  assert_eq(app.handle(mkreq("GET", "/users/42/posts/qwq")).status, 200)
}

///|
/// A verb the framework does not know is not silently answered as a GET, a 405
/// names what the resource does allow, and a GET route answers HEAD with the same
/// headers and no body.
test "method handling: unknown verbs, Allow on 405, and HEAD off GET" {
  let app = App::new()
  app.get("/thing", _ctx => text(200, "hhh"))
  app.post("/thing", _ctx => text(201, "made"))
  // An invented verb reaches no handler.
  let weird = app.handle(mkreq("TRACE", "/thing"))
  assert_eq(weird.status, 405)
  assert_eq(weird.header("content-type"), Some("application/json"))
  // The Allow header lists what is registered, HEAD included.
  let denied = app.handle(mkreq("DELETE", "/thing"))
  assert_eq(denied.status, 405)
  assert_eq(denied.header("allow"), Some("GET, HEAD, POST"))
  // HEAD gets the GET route's status and headers, without the body.
  let head = app.handle(mkreq("HEAD", "/thing"))
  assert_eq(head.status, 200)
  assert_eq(head.body.length(), 0)
  // A miss is JSON too, the same shape every other error uses.
  let missing = app.handle(mkreq("GET", "/nope"))
  assert_eq(missing.status, 404)
  assert_eq(@utf8.decode_lossy(missing.body), "{\"detail\":\"Not Found\"}")
}

///|
/// A route that declares its parameters gets them checked before the handler runs,
/// the way FastAPI does — the document and the enforcement come off the same
/// descriptor, so a spec promising `id: integer` cannot be a lie.
test "a declared endpoint is enforced with a 422 before the handler" {
  let app = App::new()
  let reached : Array[String] = []
  let ep = Endpoint::new(params=[
    Param::new("id", InPath, schema=SInt),
    Param::new("q", InQuery, required=false),
  ])
  app.get(
    "/items/:id",
    ctx => {
      reached.push(ctx.param("id").unwrap())
      text(200, "ok")
    },
    endpoint=ep,
  )
  // A well-formed request reaches the handler.
  assert_eq(app.handle(mkreq("GET", "/items/233")).status, 200)
  assert_eq(reached, ["233"])
  // A path parameter that is not an integer is refused, and the handler never ran.
  let bad = app.handle(mkreq("GET", "/items/qwq"))
  assert_eq(bad.status, 422)
  assert_eq(bad.header("content-type"), Some("application/json"))
  assert_eq(@utf8.decode_lossy(bad.body).contains("int_parsing"), true)
  assert_eq(reached, ["233"])
}

///|
/// A handler that would rather drive the descriptor itself can opt out.
test "validate=false leaves the descriptor to the handler" {
  let app = App::new()
  let ep = Endpoint::new(params=[Param::new("id", InPath, schema=SInt)])
  app.get(
    "/items/:id",
    _ctx => text(200, "handler ran"),
    endpoint=ep,
    validate=false,
  )
  assert_eq(app.handle(mkreq("GET", "/items/qwq")).status, 200)
}

///|
/// The document a client fetches from `/openapi.json` says what the app was told to
/// say about itself. Before `describe`, the served spec was permanently
/// `{"title":"moonapi","version":"0.1.0"}` no matter what the caller had configured.
test "the served document carries the app's own metadata" {
  let app = App::new()
  app.get("/hello", _ctx => text(200, "hhh"))
  app.describe(
    title="greet api",
    api_version="2.3.0",
    description="says hello",
    servers=[{ url: "https://api.example.test", description: "prod", }],
  )
  app.enable_docs()
  let served = resp_json(app.handle(mkreq("GET", "/openapi.json")))
  let info = dig(served, ["info"]).unwrap()
  assert_eq(json_str(info, "title"), "greet api")
  assert_eq(json_str(info, "version"), "2.3.0")
  assert_eq(json_str(info, "description"), "says hello")
  // The Swagger page is titled the same, rather than carrying its own name.
  let docs = @utf8.decode_lossy(app.handle(mkreq("GET", "/docs")).body)
  assert_eq(docs.contains("<title>greet api</title>"), true)
}
