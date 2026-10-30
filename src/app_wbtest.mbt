///|
/// What a teardown saw: "commit" on a clean request, "rollback" on a failed one
/// — the distinction a FastAPI `yield` dependency draws by wrapping its `yield`
/// in a `try`.
fn outcome_word(failure : Error?) -> String {
  if failure is Some(_) {
    "rollback"
  } else {
    "commit"
  }
}

///|
/// The request body of `POST /greet`. `derive(@json.FromJson)` lets
/// `Context::body_validated` build it after the descriptor accepts the payload;
/// its schema and struct fields agree (both require `name`), so a schema-valid
/// body always deserialises.
struct GreetReq {
  name : String
} derive(ToJson, FromJson, Eq)

///|
/// The `GreetReq` descriptor — one required string field.
fn GreetReq::schema() -> @schema.Schema {
  @schema.Schema::object("GreetReq", [@schema.Field::new("name", SStr)])
}

///|
/// The dependency value type of the greet app. A sum type wrapping every
/// dependency this app injects — the explicit, exhaustive stand-in for FastAPI
/// resolving heterogeneous `Depends` values dynamically.
enum Dep {
  Greeting(String)
} derive(Eq)

///|
/// Build the greet application over a caller-supplied dependency `container`, so
/// a test can register `dependency_overrides` on the same container before or
/// between requests. `POST /greet` resolves the `"greeting"` dependency, reads a
/// validated `GreetReq` body, and answers `{"message": "<greeting>, <name>"}`;
/// a malformed body gets a FastAPI-shaped `422`. The dependency scope brackets
/// each request, so any `yield` teardown runs once the handler returns.
fn greet_app(container : @di.Container[Dep]) -> App {
  let app = App::new()
  let ep = @endpoint.Endpoint::new(request_body=GreetReq::schema(), responses=[
    @endpoint.ResponseSpec::new(200, description="the greeting"),
    @endpoint.ResponseSpec::new(422, description="Validation Error"),
  ])
  app.post(
    "/greet",
    ctx => {
      container.run(scope => {
        let greeting = match scope.get("greeting") {
          Some(Greeting(g)) => g
          None => "Hello"
        }
        match (ctx.body_validated(GreetReq::schema()) : Result[GreetReq, _]) {
          Err(errs) => @schema.unprocessable(errs)
          Ok(req) => {
            let m : Map[String, Json] = Map([
              ("message", Json("\{greeting}, \{req.name}")),
            ])
            @status.json(200, Json(m))
          }
        }
      })
    },
    summary="greet a user",
    endpoint=ep,
  )
  app
}

// A worked OAuth2 password-bearer app — FastAPI's security tutorial in explicit
// MoonBit form. `POST /token` reads the password form, checks the demo
// credentials, and issues a scoped HS256 JWT; `GET /users/me` is protected by a
// bearer `Security` with no scope requirement; `GET /users/me/items` additionally
// requires the `items` scope. The verification clock is injected (`now`) so the
// same app runs deterministically in a test and against the wall clock in
// production.

///|
/// Check the demo credentials. A real app would look the user up and verify a
/// password hash; here one hard-coded account keeps the example self-contained.
fn authenticate_user(username : String, password : String) -> Bool {
  username == "alice" && password == "wonderland"
}

///|
/// Build the OAuth2 demo application. `secret` is the shared HS256 key; `now`
/// supplies the current Unix time (seconds) for both issuing and verifying, so a
/// caller controls time in tests. Tokens live for one hour.
fn oauth2_app(now : () -> Int64, secret~ : String = "demo-secret") -> App {
  let app = App::new()
  let scheme = @security.OAuth2PasswordBearer::new("/token", secret)
  app.post(
    "/token",
    ctx => {
      match ctx.oauth2_password_form() {
        None =>
          @schema.unprocessable([
            @schema.ValidationError::missing(["body", "username"]),
          ])
        Some(form) =>
          if authenticate_user(form.username, form.password) {
            let token = @security.create_access_token(
              form.username,
              secret,
              now(),
              scopes=form.scopes,
            )
            @security.token_response(token)
          } else {
            let body : Map[String, Json] = Map([
              ("detail", Json("Incorrect username or password")),
            ])
            @moonasgi.Response::new(
              401,
              [
                ("content-type", "application/json"),
                ("www-authenticate", "Bearer"),
              ],
              @moonjson.dump(Json(body)),
            )
          }
      }
    },
    summary="issue an access token",
  )
  app.get(
    "/users/me",
    ctx => {
      match scheme.authenticate(ctx, now()) {
        Err(resp) => resp
        Ok(user) => {
          let scopes : Array[Json] = []
          for s in user.scopes {
            scopes.push(Json(s))
          }
          let body : Map[String, Json] = Map([
            ("username", Json(user.subject)),
            ("scopes", Json(scopes)),
          ])
          @status.json(200, Json(body))
        }
      }
    },
    summary="the current user",
  )
  app.get(
    "/users/me/items",
    ctx => {
      match scheme.authenticate(ctx, now(), scopes=["items"]) {
        Err(resp) => resp
        Ok(user) => {
          let body : Map[String, Json] = Map([
            ("owner", Json(user.subject)),
            ("items", Json(["hammer", "nail"])),
          ])
          @status.json(200, Json(body))
        }
      }
    },
    summary="the current user's items (scope: items)",
  )
  app
}

///|
pub extend GreetReq with Eq::{not_equal, equal}

///|
pub extend GreetReq with FromJson::{from_json}

///|
pub extend GreetReq with ToJson::{to_json}

///|
pub extend Dep with Eq::{not_equal, equal}

///|
/// Split a string on one character. Used to take a token apart in the tests
/// that tamper with one.
fn split_char(s : String, delim : Char) -> Array[String] {
  let out : Array[String] = []
  let piece = StringBuilder()
  for i in 0..<s.length() {
    if s.at(i).to_int() == delim.to_int() {
      out.push(piece.to_string())
      piece.reset()
    } else {
      piece.write_view(s[i:i + 1])
    }
  }
  out.push(piece.to_string())
  out
}

///|
/// One header out of a list, by lowercased name.
fn header_of(headers : Array[(String, String)], name : String) -> String? {
  for pair in headers {
    if pair.0.to_lower() == name {
      return Some(pair.1)
    }
  }
  None
}

///|
/// Build a request with explicit headers — CORS and gzip switch on them.
fn req_h(
  verb : String,
  path : String,
  headers : Array[(String, String)],
) -> @moonasgi.Request {
  { http_method: verb, path, query_string: b"", headers, body: b"", }
}

///|
/// Read a response header, "" if absent.
fn hdr(resp : @moonasgi.Response, name : String) -> String {
  resp.header(name).unwrap_or("")
}

///|
/// `unit` repeated `n` times as bytes — a compressible fixture with real matches.
fn repeat_bytes(unit : String, n : Int32) -> Bytes {
  let sb = StringBuilder()
  for _i = 0; _i < n; _i = _i + 1 {
    sb.write_string(unit)
  }
  @utf8.encode(sb.to_string())
}

///|
/// Decode a UTF-8 response body to a String for JSON assertions.
fn decode_body(b : Bytes) -> String {
  let sb = StringBuilder()
  for i = 0; i < b.length(); i = i + 1 {
    sb.write_char(b[i].to_int().unsafe_to_char())
  }
  sb.to_string()
}

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
/// A field constrained by a pattern, which the descriptor enum cannot express.
fn slug_body() -> @schema.Schema {
  @schema.Schema::object("Post", [
    @schema.Field::new(
      "slug",
      @schema.Schema::json(
        ({ "type": "string", "pattern": "^[a-z0-9-]+$" } : Json),
      ),
      required=true,
    ),
  ])
}

///|
/// One step at a time down a document.
fn json_at(doc : Json, path : ArrayView[String]) -> Json? {
  let mut here = doc
  for step in path {
    here = match here {
      Object(members) =>
        match members.get(step) {
          Some(next) => next
          None => return None
        }
      _ => return None
    }
  }
  Some(here)
}

///|
/// The `detail` string of a refusal body — test helper.
fn detail_str(r : @moonasgi.Response) -> String {
  json_str(resp_json(r), "detail")
}

///|
/// Reach `components.securitySchemes.<name>` in a 3.x document.
fn scheme_3x(doc : Json, name : String) -> Json {
  match doc {
    Object(m) =>
      match m.get("components") {
        Some(Object(c)) =>
          match c.get("securitySchemes") {
            Some(Object(s)) => s.get(name).unwrap_or(Json(false))
            _ => Json(false)
          }
        _ => Json(false)
      }
    _ => Json(false)
  }
}

///|
/// Reach `securityDefinitions.<name>` in a Swagger 2.0 document.
fn scheme_20(doc : Json, name : String) -> Json {
  match doc {
    Object(m) =>
      match m.get("securityDefinitions") {
        Some(Object(s)) => s.get(name).unwrap_or(Json(false))
        _ => Json(false)
      }
    _ => Json(false)
  }
}

///|
/// A request to `path` carrying `body` under `content_type` — test helper.
fn mkreq_form(
  verb : String,
  path : String,
  content_type : String,
  body : Bytes,
) -> @moonasgi.Request {
  {
    http_method: verb,
    path,
    query_string: b"",
    headers: [("content-type", content_type)],
    body,
  }
}

///|
/// A fixed clock for the demo app — test helper.
fn fixed(t : Int64) -> () -> Int64 {
  () => t
}

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
async test "routing: static, param, 404, 405" {
  let app = App::new()
  app.get("/hello", _ctx => @status.text(200, "hi"))
  app.get("/users/{id}", ctx => {
    @status.text(200, "user " + ctx.param("id").unwrap())
  })
  app.post("/users", _ctx => @status.text(201, "created"))
  assert_eq(app.handle(mkreq("GET", "/hello")).status, 200)
  assert_eq(app.handle(mkreq("POST", "/users")).status, 201)
  let got = app.handle(mkreq("GET", "/users/42"))
  assert_eq(got.status, 200)
  assert_eq(got.body, @utf8.encode("user 42"))
  assert_eq(app.handle(mkreq("GET", "/nope")).status, 404)
  assert_eq(app.handle(mkreq("DELETE", "/hello")).status, 405)
}

///|
async test "path param extraction" {
  let app = App::new()
  app.get("/a/{x}/b/{y}", ctx => {
    let x = ctx.param("x").unwrap()
    let y = ctx.param("y").unwrap()
    @status.text(200, x + "," + y)
  })
  let got = app.handle(mkreq("GET", "/a/1/b/2"))
  assert_eq(got.body, @utf8.encode("1,2"))
  assert_eq(app.handle(mkreq("GET", "/a/1/b")).status, 404)
}

///|
async test "query extraction" {
  let app = App::new()
  app.get("/search", ctx => {
    match ctx.query("q") {
      Some(q) => @status.text(200, "q=" + q)
      None =>
        @schema.unprocessable([@schema.ValidationError::missing(["query", "q"])])
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
async test "json body extraction and 422" {
  let app = App::new()
  app.post("/items", ctx => {
    match ctx.json_field("name") {
      Some(String(name)) => @status.text(201, "created " + name)
      _ =>
        @schema.unprocessable([
          @schema.ValidationError::missing(["body", "name"]),
        ])
    }
  })
  let ok = app.handle(
    mkreq_full("POST", "/items", body=@utf8.encode("{\"name\":\"pen\"}")),
  )
  assert_eq(ok.status, 201)
  assert_eq(ok.body, @utf8.encode("created pen"))
  // whole body as Json
  let ctx : @ctx.Context = @ctx.Context::new(
    mkreq_full("POST", "/items", body=@utf8.encode("{\"name\":\"pen\"}")),
    params=Map([]),
  )
  assert_eq(json_str(ctx.body_json().unwrap(), "name"), "pen")
  // missing field -> 422 with FastAPI-shaped detail
  let miss = app.handle(
    mkreq_full("POST", "/items", body=@utf8.encode("{\"other\":1}")),
  )
  assert_eq(miss.status, 422)
  // malformed / empty body -> None, not a crash
  assert_eq(ctx.body_json() is Some(_), true)
  let empty : @ctx.Context = @ctx.Context::new(
    mkreq_full("POST", "/items"),
    params=Map([]),
  )
  assert_eq(empty.body_json(), None)
}

///|
/// Startup hooks run in registration order, shutdown hooks in reverse, and a mounted
/// app's hooks come along — a mount is part of the composition the server starts.
async test "lifespan hooks run in order, mounts included" {
  let log : Array[String] = []
  let app = App::new()
  app.on_startup(_ => log.push("open-db"))
  app.on_startup(_ => log.push("warm-cache"))
  app.on_shutdown(_ => log.push("close-db"))
  app.on_shutdown(_ => log.push("flush-cache"))
  let sub = App::new()
  sub.on_startup(_ => log.push("sub-open"))
  sub.on_shutdown(_ => log.push("sub-close"))
  app.mount("/sub", sub)
  let out = lifespan_events(app, [
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
async test "a raising startup hook fails the boot" {
  let log : Array[String] = []
  let app = App::new()
  app.on_startup(_ => log.push("first"))
  app.on_startup(_ => raise Failure("no database at qwq:233"))
  app.on_startup(_ => log.push("never"))
  let out = lifespan_events(app, [@moonasgi.Event::LifespanStartup])
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
async test "a raising shutdown hook still lets the rest run" {
  let log : Array[String] = []
  let app = App::new()
  app.on_shutdown(_ => log.push("last-registered-runs-first"))
  app.on_shutdown(_ => raise Failure("flush failed"))
  app.on_shutdown(_ => log.push("still-runs"))
  let out = lifespan_events(app, [@moonasgi.Event::LifespanShutdown])
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
async test "enable_docs serves the spec, the reference and ReDoc without joining the spec" {
  let app = App::new()
  app.get("/hello", _ctx => @status.text(200, "hhh"), summary="greet")
  app.describe(title="qwq api")
  app.enable_docs()
  let spec = app.handle(mkreq("GET", "/openapi.json"))
  assert_eq(spec.status, 200)
  assert_eq(spec.header("content-type"), Some("application/json"))
  let docs = app.handle(mkreq("GET", "/docs"))
  assert_eq(docs.status, 200)
  assert_eq(docs.header("content-type"), Some("text/html; charset=utf-8"))
  let docs_body = @utf8.decode_lossy(docs.body)
  assert_eq(docs_body.contains("Scalar.createApiReference"), true)
  assert_eq(docs_body.contains(@openapi.scalar_js), true)
  assert_eq(docs_body.contains("{\"url\":\"/openapi.json\"}"), true)
  assert_eq(docs_body.contains("<title>qwq api</title>"), true)
  let redoc = app.handle(mkreq("GET", "/redoc"))
  assert_eq(redoc.status, 200)
  let redoc_body = @utf8.decode_lossy(redoc.body)
  assert_eq(
    redoc_body.contains(
      "<redoc spec-url=\"/openapi.json\" disable-telemetry=\"true\">",
    ),
    true,
  )
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
/// The three documentation routes are there unless the app is told otherwise,
/// as FastAPI's are; `docs=None` starts without them, and the presets match.
async test "documentation is on by default and off with docs=None" {
  let app = App::new()
  assert_eq(app.handle(mkreq("GET", "/openapi.json")).status, 200)
  assert_eq(app.handle(mkreq("GET", "/docs")).status, 200)
  assert_eq(app.handle(mkreq("GET", "/redoc")).status, 200)
  let bare = App::new(docs=None)
  assert_eq(bare.handle(mkreq("GET", "/openapi.json")).status, 404)
  assert_eq(bare.handle(mkreq("GET", "/docs")).status, 404)
  assert_eq(bare.handle(mkreq("GET", "/redoc")).status, 404)
  let same = App::new(docs=Some(docs))
  let record = App::new(docs=Some({ ..docs, redoc_url: None, }))
  assert_eq(same.handle(mkreq("GET", "/redoc")).status, 200)
  assert_eq(record.handle(mkreq("GET", "/redoc")).status, 404)
}

///|
/// A route of the app's own at a documentation path answers instead, because
/// the documentation routes are added after the app's routes.
async test "the app's own /docs route wins over the documentation page" {
  let app = App::new()
  app.get("/docs", _ctx => @status.text(200, "ours"))
  let got = app.handle(mkreq("GET", "/docs"))
  assert_eq(@utf8.decode_lossy(got.body), "ours")
  assert_eq(app.handle(mkreq("GET", "/redoc")).status, 200)
}

///|
/// Each documentation page can be turned off on its own.
async test "enable_docs leaves off whatever is passed None" {
  let app = App::new()
  app.enable_docs(docs_url=None, redoc_url=None)
  assert_eq(app.handle(mkreq("GET", "/openapi.json")).status, 200)
  assert_eq(app.handle(mkreq("GET", "/docs")).status, 404)
  assert_eq(app.handle(mkreq("GET", "/redoc")).status, 404)
}

///|
/// A verb the framework does not know is not silently answered as a GET, a 405
/// names what the resource does allow, and a GET route answers HEAD. The app hands the server
/// the GET body for a HEAD too: the server drops it and keeps the length it gives, which is
/// what a HEAD answer is to carry.
async test "method handling: unknown verbs, Allow on 405, and HEAD off GET" {
  let app = App::new()
  app.get("/thing", _ctx => @status.text(200, "hhh"))
  app.post("/thing", _ctx => @status.text(201, "made"))
  // A method no route registered reaches no handler.
  let weird = app.handle(mkreq("TRACE", "/thing"))
  assert_eq(weird.status, 405)
  assert_eq(weird.header("content-type"), Some("application/json"))
  // The Allow header lists what is registered, HEAD included.
  let denied = app.handle(mkreq("DELETE", "/thing"))
  assert_eq(denied.status, 405)
  assert_eq(denied.header("allow"), Some("GET, HEAD, POST"))
  // HEAD gets the GET route's status and headers, and its body for the server to measure.
  let head = app.handle(mkreq("HEAD", "/thing"))
  assert_eq(head.status, 200)
  assert_eq(head.header("content-type"), Some("text/plain; charset=utf-8"))
  assert_eq(head.body, b"hhh")
  // A miss is JSON too, the same shape every other error uses.
  let missing = app.handle(mkreq("GET", "/nope"))
  assert_eq(missing.status, 404)
  assert_eq(@utf8.decode_lossy(missing.body), "{\"detail\":\"Not Found\"}")
}

///|
async test "an extension method is a route like any other, by its exact name" {
  let app = App::new()
  app.route(Other("PURGE"), "/cache", _ctx => @status.text(200, "purged"))
  app.route(Trace, "/echo", _ctx => @status.text(200, "echo"))
  assert_eq(app.handle(mkreq("PURGE", "/cache")).status, 200)
  assert_eq(app.handle(mkreq("TRACE", "/echo")).status, 200)
  let lower = app.handle(mkreq("purge", "/cache"))
  assert_eq(lower.status, 405)
  assert_eq(lower.header("allow"), Some("PURGE"))
  assert_eq(app.handle(mkreq("BAD METHOD", "/cache")).status, 405)
}

///|
test "OpenAPI writes the methods its version has a key for" {
  let app = App::new()
  app.route(Other("PURGE"), "/cache", _ctx => @status.text(200, "purged"))
  app.route(Trace, "/cache", _ctx => @status.text(200, "echo"))
  app.get("/cache", _ctx => @status.text(200, "cached"))
  let v31 = app.openapi(version=OpenApi31)
  assert_eq(op_of(v31, "/cache", "trace") is Some(_), true)
  assert_eq(op_of(v31, "/cache", "get") is Some(_), true)
  assert_eq(op_of(v31, "/cache", "purge"), None)
  let v20 = app.openapi(version=Swagger20)
  assert_eq(op_of(v20, "/cache", "trace"), None)
  assert_eq(op_of(v20, "/cache", "get") is Some(_), true)
}

///|
/// A route that declares its parameters gets them checked before the handler runs,
/// the way FastAPI does — the document and the enforcement come off the same
/// descriptor, so a spec promising `id: integer` cannot be a lie.
async test "a declared endpoint is enforced with a 422 before the handler" {
  let app = App::new()
  let reached : Array[String] = []
  let ep = @endpoint.Endpoint::new(params=[
    @endpoint.Param::new("id", InPath, schema=SInt),
    @endpoint.Param::new("q", InQuery, required=false),
  ])
  app.get(
    "/items/{id}",
    ctx => {
      reached.push(ctx.param("id").unwrap())
      @status.text(200, "ok")
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
async test "validate=false leaves the descriptor to the handler" {
  let app = App::new()
  let ep = @endpoint.Endpoint::new(params=[
    @endpoint.Param::new("id", InPath, schema=SInt),
  ])
  app.get(
    "/items/{id}",
    _ctx => @status.text(200, "handler ran"),
    endpoint=ep,
    validate=false,
  )
  assert_eq(app.handle(mkreq("GET", "/items/qwq")).status, 200)
}

///|
/// The document a client fetches from `/openapi.json` says what the app was told to
/// say about itself. Before `describe`, the served spec was permanently
/// `{"title":"moonapi","version":"0.1.0"}` no matter what the caller had configured.
async test "the served document carries the app's own metadata" {
  let app = App::new()
  app.get("/hello", _ctx => @status.text(200, "hhh"))
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

///|
async test "greet route: dependency + validated body end to end, with override" {
  let c : @di.Container[Dep] = @di.Container::new()
  c.provide("greeting", () => Greeting("Hello")) |> ignore
  let app = greet_app(c)
  let ok = app.handle(
    mkreq_full("POST", "/greet", body=@utf8.encode("{\"name\":\"ada\"}")),
  )
  assert_eq(ok.status, 200)
  assert_eq(json_str(resp_json(ok), "message"), "Hello, ada")
  // dependency_overrides swaps the injected value without touching the route.
  c.override_("greeting", () => Greeting("Bonjour")) |> ignore
  let ok2 = app.handle(
    mkreq_full("POST", "/greet", body=@utf8.encode("{\"name\":\"ada\"}")),
  )
  assert_eq(json_str(resp_json(ok2), "message"), "Bonjour, ada")
  // A malformed body is rejected off the same descriptor with a 422.
  let bad = app.handle(mkreq_full("POST", "/greet", body=@utf8.encode("{}")))
  assert_eq(bad.status, 422)
  assert_eq(json_str(detail0(bad), "type"), "missing")
}

///|
async test "route deps: a declared dependency is resolved before the handler and torn down after" {
  let log : Array[String] = []
  let c : @di.Container[Dep] = @di.Container::new()
  c.provide(
    "conn",
    () => {
      log.push("open")
      Greeting("db")
    },
    teardown=(_v, _e) => log.push("close"),
  )
  |> ignore
  let app = App::new()
  app.depends(c.erase())
  app.get(
    "/items",
    _ctx => {
      log.push("handler")
      @status.text(200, "items")
    },
    dependencies=["conn"],
  )
  assert_eq(app.handle(mkreq("GET", "/items")).status, 200)
  assert_eq(log == ["open", "handler", "close"], true)
}

///|
async test "route deps: teardown runs when the handler raises, and sees the failure" {
  let log : Array[String] = []
  let c : @di.Container[Dep] = @di.Container::new()
  c.provide("tx", () => Greeting("tx"), teardown=(_v, e) => {
    log.push(outcome_word(e))
  })
  |> ignore
  let app = App::new()
  app.depends(c.erase())
  app.get("/boom", _ctx => raise @exceptions.http_error(418, "no tea"), dependencies=[
    "tx",
  ])
  app.get("/fine", _ctx => @status.text(200, "ok"), dependencies=["tx"])
  // The raised error still becomes its mapped response...
  assert_eq(app.handle(mkreq("GET", "/boom")).status, 418)
  assert_eq(app.handle(mkreq("GET", "/fine")).status, 200)
  // ...and the two requests tore down differently, which is the whole point of
  // handing the failure to the teardown.
  assert_eq(log == ["rollback", "commit"], true)
}

///|
async test "route deps: dependencies are LIFO within one request, and per request" {
  let log : Array[String] = []
  let c : @di.Container[Dep] = @di.Container::new()
  c.provide("a", () => Greeting("a"), teardown=(_v, _e) => log.push("td a"))
  |> ignore
  c.provide("b", () => Greeting("b"), teardown=(_v, _e) => log.push("td b"))
  |> ignore
  let app = App::new()
  app.depends(c.erase())
  app.get("/x", _ctx => @status.text(200, "x"), dependencies=["a", "b"])
  let _ = app.handle(mkreq("GET", "/x"))
  let _ = app.handle(mkreq("GET", "/x"))
  // Each request opened its own scope: two full setup/teardown cycles, the
  // second not served from the first's cache.
  assert_eq(log == ["td b", "td a", "td b", "td a"], true)
}

///|
async test "route deps: an unprovidable key is a 500 and still releases what was built" {
  let log : Array[String] = []
  let c : @di.Container[Dep] = @di.Container::new()
  c.provide("conn", () => Greeting("db"), teardown=(_v, _e) => log.push("close"))
  |> ignore
  let app = App::new()
  app.depends(c.erase())
  app.get(
    "/items",
    _ctx => {
      log.push("handler")
      @status.text(200, "items")
    },
    dependencies=["conn", "nope"],
  )
  assert_eq(app.handle(mkreq("GET", "/items")).status, 500)
  // The handler never ran, and the dependency built before the gap was released.
  assert_eq(log == ["close"], true)
}

///|
async test "route deps: a route that declares one with no container at all is a 500" {
  let app = App::new()
  app.get("/items", _ctx => @status.text(200, "items"), dependencies=["conn"])
  assert_eq(app.handle(mkreq("GET", "/items")).status, 500)
  // A route declaring none is unaffected — no container, no scope, no error.
  app.get("/free", _ctx => @status.text(200, "free"))
  assert_eq(app.handle(mkreq("GET", "/free")).status, 200)
}

///|
async test "route deps: a router's group dependencies reach every route it carries" {
  let log : Array[String] = []
  let c : @di.Container[Dep] = @di.Container::new()
  c.provide("audit", () => {
    log.push("audit")
    Greeting("audit")
  })
  |> ignore
  let app = App::new()
  app.depends(c.erase())
  let r = @route.Router::new()
  r.get("/one", _ctx => @status.text(200, "one"))
  r.get("/two", _ctx => @status.text(200, "two"), dependencies=["own"])
  app.include_router(r, prefix="/g", dependencies=["audit"])
  assert_eq(app.handle(mkreq("GET", "/g/one")).status, 200)
  // The route's own key is unprovided, but the group's ran first — a group-wide
  // dependency is not something a route can drop by adding one of its own.
  assert_eq(app.handle(mkreq("GET", "/g/two")).status, 500)
  assert_eq(log == ["audit", "audit"], true)
}

///|
async test "layers: a CORS layer answers a preflight in front of the routes" {
  let app = App::new()
  app.layer(
    @mid.Cors::new(
      origins=["https://app.example"],
      methods=["GET", "POST"],
      headers=["x-token"],
      max_age=100,
    ),
  )
  app.get("/data", _ctx => @status.text(200, "ok"))
  let pre = app.handle(
    req_h("OPTIONS", "/data", [
      ("origin", "https://app.example"),
      ("access-control-request-method", "POST"),
    ]),
  )
  assert_eq(pre.status, 200)
  assert_eq(hdr(pre, "access-control-allow-origin"), "https://app.example")
  assert_eq(hdr(pre, "access-control-allow-methods"), "GET, POST")
  assert_eq(hdr(pre, "access-control-max-age"), "100")
  let refused = app.handle(
    req_h("OPTIONS", "/data", [
      ("origin", "https://evil.example"),
      ("access-control-request-method", "GET"),
    ]),
  )
  assert_eq(refused.status, 400)
  let actual = app.handle(
    req_h("GET", "/data", [("origin", "https://app.example")]),
  )
  assert_eq(actual.body, @utf8.encode("ok"))
  assert_eq(hdr(actual, "access-control-allow-origin"), "https://app.example")
}

///|
async test "layers: a gzip layer compresses a large answer and leaves a small one" {
  let big = repeat_bytes("moonapi gzip layer payload ", 60)
  let app = App::new()
  app.layer(@mid.Gzip::new(minimum=100))
  app.get("/big", _ctx => @moonasgi.Response::new(200, [], big))
  app.get("/small", _ctx => @status.text(200, "tiny"))
  let z = app.handle(req_h("GET", "/big", [("accept-encoding", "gzip")]))
  assert_eq(hdr(z, "content-encoding"), "gzip")
  assert_true(z.body.length() < big.length())
  assert_eq(@gzip.gunzip(z.body[:]), big)
  let s = app.handle(req_h("GET", "/small", [("accept-encoding", "gzip")]))
  assert_eq(s.header("content-encoding"), None)
  assert_eq(s.body, @utf8.encode("tiny"))
}

///|
async test "layers: a stream behind a gzip layer stays a stream" {
  let app = App::new()
  app.layer(@mid.Gzip::new(minimum=1))
  app.stream("/feed", _ctx => {
    @status.Stream::new(w => {
      w.write_text("one,")
      w.write_text("two")
    })
  })
  let events = stream_events(
    app,
    req_h("GET", "/feed", [("accept-encoding", "gzip")]),
  )
  assert_eq(body_chunks(events), ["one,", "two"])
}

///|
async test "layers: they wrap mounted applications as well" {
  let sub = App::new()
  sub.get("/hi", _ctx => @status.text(200, "sub"))
  let app = App::new()
  app.layer(
    @mid.Wrap(inner => {
      async fn(scope, receive, send) {
        inner(scope, receive, event => {
          match event {
            HttpResponseStart(status~, headers~, trailers~) =>
              send(
                HttpResponseStart(
                  status~,
                  headers=[("x-outer", "1"), ..headers],
                  trailers~,
                ),
              )
            other => send(other)
          }
        })
      }
    }),
  )
  app.mount("/s", sub)
  let got = app.handle(mkreq("GET", "/s/hi"))
  assert_eq(got.body, @utf8.encode("sub"))
  assert_eq(got.header("x-outer"), Some("1"))
}

///|
async test "layers and middleware run in registration order, the first outermost" {
  let order : Array[String] = []
  let tag = (name : String) => {
    @mid.Wrap(inner => {
      async fn(scope, receive, send) {
        order.push(name + " in")
        inner(scope, receive, send)
        order.push(name + " out")
      }
    })
  }
  let app = App::new()
  app.layer(tag("outer"))
  app.middleware((req, call_next) => {
    order.push("middleware in")
    let resp = call_next(req)
    order.push("middleware out")
    resp
  })
  app.layer(tag("inner"))
  app.get("/", _ctx => {
    order.push("handler")
    @status.text(200, "ok")
  })
  ignore(app.handle(mkreq("GET", "/")))
  assert_eq(order, [
    "outer in", "middleware in", "inner in", "handler", "inner out", "middleware out",
    "outer out",
  ])
}

///|
async test "middleware: call_next can rewrite the request and the response" {
  let app = App::new()
  app.middleware((req, call_next) => {
    let resp = call_next({ ..req, path: "/real", })
    @moonasgi.Response::new(
      resp.status,
      [("x-seen", req.path), ..resp.headers],
      resp.body,
    )
  })
  app.get("/real", _ctx => @status.text(200, "real"))
  let got = app.handle(mkreq("GET", "/alias"))
  assert_eq(got.body, @utf8.encode("real"))
  assert_eq(got.header("x-seen"), Some("/alias"))
}

///|
async test "exception: a raised HttpException maps to its status and detail" {
  let app = App::new()
  app.get("/boom", _ctx => raise @exceptions.http_error(418, "teapot"))
  let resp = app.handle(req_h("GET", "/boom", []))
  assert_eq(resp.status, 418)
  assert_eq(hdr(resp, "content-type"), "application/json")
  assert_eq(json_str(@json.parse(decode_body(resp.body)), "detail"), "teapot")
}

///|
async test "exception: HttpException extra headers reach the response" {
  let app = App::new()
  app.get("/auth", _ctx => {
    raise @exceptions.http_error(401, "nope", headers=[
      ("www-authenticate", "Bearer"),
    ])
  })
  let resp = app.handle(req_h("GET", "/auth", []))
  assert_eq(resp.status, 401)
  assert_eq(hdr(resp, "www-authenticate"), "Bearer")
}

///|
async test "exception: a registered handler is tried before the default" {
  let app = App::new()
  app.exception_handler((_ctx, err) => {
    match err {
      @exceptions.HttpException(status~, detail=_, headers=_) =>
        Some(@status.text(status, "custom"))
      _ => None
    }
  })
  app.get("/boom", _ctx => raise @exceptions.http_error(400, "x"))
  let resp = app.handle(req_h("GET", "/boom", []))
  assert_eq(resp.status, 400)
  assert_eq(resp.body, @utf8.encode("custom"))
}

///|
async test "exception: an unhandled error becomes a 500" {
  let app = App::new()
  app.get("/fail", _ctx => fail("kaboom"))
  let resp = app.handle(req_h("GET", "/fail", []))
  assert_eq(resp.status, 500)
  assert_eq(
    json_str(@json.parse(decode_body(resp.body)), "detail"),
    "Internal Server Error",
  )
}

///|
async test "query param: a declared range is enforced with a 422 and documented" {
  let app = param_app(
    @endpoint.Param::new("limit", InQuery, schema=SInt, required=false, constraints=[
      @schema.Minimum(1.0),
      @schema.Maximum(100.0),
    ]),
  )
  // Above the bound.
  let over = app.handle(mkreq_full("GET", "/items", query=b"limit=500"))
  assert_eq(over.status, 422)
  assert_eq(json_str(detail0(over), "type"), "less_than_equal")
  assert_eq(
    json_str(detail0(over), "msg"),
    "Input should be less than or equal to 100",
  )
  assert_eq(err_loc(detail0(over)), ["query", "limit"])
  // Below it.
  let under = app.handle(mkreq_full("GET", "/items", query=b"limit=0"))
  assert_eq(under.status, 422)
  assert_eq(json_str(detail0(under), "type"), "greater_than_equal")
  // Inside it, and absent (the parameter is optional).
  assert_eq(
    app.handle(mkreq_full("GET", "/items", query=b"limit=50")).status,
    200,
  )
  assert_eq(app.handle(mkreq("GET", "/items")).status, 200)
  // And the document says so, rather than leaving the client to discover it.
  let schema = dig(only_param(app, OpenApi31), ["schema"]).unwrap()
  assert_eq(json_str(schema, "type"), "integer")
  assert_eq(dig(schema, ["minimum"]), Some(Json(1.0)))
  assert_eq(dig(schema, ["maximum"]), Some(Json(100.0)))
}

///|
async test "query param: a string parameter's length and pattern bounds are enforced" {
  let app = param_app(
    @endpoint.Param::new("q", InQuery, required=false, constraints=[
      @schema.MinLength(3),
      @schema.Pattern("^[a-z]+$"),
    ]),
  )
  let short = app.handle(mkreq_full("GET", "/items", query=b"q=ab"))
  assert_eq(short.status, 422)
  assert_eq(json_str(detail0(short), "type"), "string_too_short")
  let shouty = app.handle(mkreq_full("GET", "/items", query=b"q=ABCD"))
  assert_eq(shouty.status, 422)
  assert_eq(json_str(detail0(shouty), "type"), "string_pattern_mismatch")
  assert_eq(
    app.handle(mkreq_full("GET", "/items", query=b"q=cats")).status,
    200,
  )
  let schema = dig(only_param(app, OpenApi31), ["schema"]).unwrap()
  assert_eq(dig(schema, ["minLength"]), Some(Json(3)))
  assert_eq(json_str(schema, "pattern"), "^[a-z]+$")
}

///|
async test "query param: a default makes it optional and is emitted" {
  let app = param_app(
    @endpoint.Param::new("limit", InQuery, schema=SInt, default=Json(10)),
  )
  // `required=true` was left at its default, but a parameter with a default is
  // never missing — the request without it is accepted.
  assert_eq(app.handle(mkreq("GET", "/items")).status, 200)
  let p = only_param(app, OpenApi31)
  assert_eq(dig(p, ["required"]), Some(Json(false)))
  assert_eq(dig(p, ["schema", "default"]), Some(Json(10)))
}

///|
async test "query param: without a default, a required one is still reported missing" {
  let app = param_app(@endpoint.Param::new("limit", InQuery, schema=SInt))
  let miss = app.handle(mkreq("GET", "/items"))
  assert_eq(miss.status, 422)
  assert_eq(json_str(detail0(miss), "type"), "missing")
  assert_eq(dig(only_param(app, OpenApi31), ["required"]), Some(Json(true)))
}

///|
async test "query param: an alias is the name on the wire, in the document and in errors" {
  let app = param_app(
    @endpoint.Param::new("item_query", InQuery, alias_="item-query"),
  )
  // The document calls it by the alias, because that is what a client sends.
  assert_eq(json_str(only_param(app, OpenApi31), "name"), "item-query")
  // The value is read under the alias...
  assert_eq(
    app.handle(mkreq_full("GET", "/items", query=b"item-query=cats")).status,
    200,
  )
  // ...and the field name it is bound to is not accepted in its place.
  let wrong = app.handle(mkreq_full("GET", "/items", query=b"item_query=cats"))
  assert_eq(wrong.status, 422)
  assert_eq(err_loc(detail0(wrong)), ["query", "item-query"])
}

///|
async test "header and cookie params: bounds are enforced where the value lives" {
  let app = App::new()
  app.get(
    "/items",
    _ctx => @status.text(200, "ok"),
    endpoint=@endpoint.Endpoint::new(params=[
      @endpoint.Param::new("x-page", InHeader, schema=SInt, constraints=[
        @schema.Maximum(9.0),
      ]),
      @endpoint.Param::new("session", InCookie, constraints=[
        @schema.MinLength(4),
      ]),
    ]),
  )
  let ok = app.handle(
    mkreq_hdrs("GET", "/items", [("x-page", "3"), ("cookie", "session=abcd")]),
  )
  assert_eq(ok.status, 200)
  let bad = app.handle(
    mkreq_hdrs("GET", "/items", [("x-page", "42"), ("cookie", "session=ab")]),
  )
  assert_eq(bad.status, 422)
  let errs = dig_arr(resp_json(bad), ["detail"])
  assert_eq(errs.length(), 2)
  assert_eq(err_loc(errs[0]), ["header", "x-page"])
  assert_eq(err_loc(errs[1]), ["cookie", "session"])
}

///|
async test "query param: an exclusive bound takes each dialect's form" {
  let app = param_app(
    @endpoint.Param::new("limit", InQuery, schema=SInt, required=false, constraints=[
      @schema.ExclusiveMinimum(0.0),
    ]),
  )
  // 3.1 (JSON-Schema 2020-12) makes it a number.
  let new = dig(only_param(app, OpenApi31), ["schema"]).unwrap()
  assert_eq(dig(new, ["exclusiveMinimum"]), Some(Json(0.0)))
  assert_eq(dig(new, ["minimum"]) is None, true)
  // 3.0 makes it a flag beside `minimum`.
  let old = dig(only_param(app, OpenApi30), ["schema"]).unwrap()
  assert_eq(dig(old, ["exclusiveMinimum"]), Some(Json(true)))
  assert_eq(dig(old, ["minimum"]), Some(Json(0.0)))
  // Enforced either way.
  assert_eq(
    app.handle(mkreq_full("GET", "/items", query=b"limit=0")).status,
    422,
  )
  assert_eq(
    app.handle(mkreq_full("GET", "/items", query=b"limit=1")).status,
    200,
  )
}

///|
async test "include_router: the router's tags and security reach every route" {
  let items = @route.Router::new()
  items.get("/", _ctx => @status.text(200, "list"), tags=["listing"])
  items.get("/{id}", ctx => {
    @status.text(200, "item " + ctx.param("id").unwrap())
  })
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
  // Both routes answer under the prefix, as the app's own; the router's `/` is
  // `/items/`, and `/items` is sent there.
  let tok = @security.create_access_token("alice", "s3cret", 1000L, scopes=[
    "items",
  ])
  assert_eq(
    app.handle(mkreq_auth("GET", "/items/", "Bearer " + tok)).body,
    @utf8.encode("list"),
  )
  assert_eq(app.handle(mkreq("GET", "/items")).status, 307)
  assert_eq(
    app.handle(mkreq_auth("GET", "/items/233", "Bearer " + tok)).body,
    @utf8.encode("item 233"),
  )
  // The router-level requirement is enforced on every one of them, including the
  // route that declared no security of its own.
  assert_eq(app.handle(mkreq("GET", "/items/")).status, 401)
  assert_eq(app.handle(mkreq("GET", "/items/233")).status, 401)
  // And both carry it in the document, the router's tag ahead of the route's own.
  let doc = app.openapi()
  assert_eq(op_tags(doc, "/items/", "get"), ["items", "listing"])
  assert_eq(op_tags(doc, "/items/{id}", "get"), ["items"])
  assert_eq(nav_op_security(doc, "/items/", "get").length(), 1)
  assert_eq(nav_op_security(doc, "/items/{id}", "get").length(), 1)
}

///|
async test "mount_asgi: a foreign ASGI application answers under its prefix" {
  let seen : Array[String] = []
  let files : @moonasgi.AsgiApp = (scope, receive, send) => {
    guard scope is Http(h) else { return }
    seen.push("\{h.root_path} \{h.path}")
    ignore(receive())
    send(
      HttpResponseStart(
        status=200,
        headers=[("content-type", "text/css")],
        trailers=false,
      ),
    )
    send(HttpResponseBody(body=@utf8.encode("body{}"), more_body=false))
  }
  let app = App::new()
  app.get("/", _ctx => @status.text(200, "app root"))
  app.mount_asgi("/static", files)
  let got = app.handle(mkreq("GET", "/static/site.css"))
  assert_eq(got.status, 200)
  assert_eq(got.header("content-type"), Some("text/css"))
  assert_eq(@utf8.decode_lossy(got.body), "body{}")
  // The prefix moves from the path to the root path, as Starlette's `Mount` does.
  assert_eq(seen, ["/static /site.css"])
  // The app's own routes are untouched and the prefix still matches by segment.
  assert_eq(app.handle(mkreq("GET", "/")).body, @utf8.encode("app root"))
  assert_eq(app.handle(mkreq("GET", "/staticky/x")).status, 404)
  // A foreign application describes nothing and has no lifespan here, and neither
  // fact stops the app from producing either.
  assert_eq(path_exists(app.openapi(), "/static/site.css"), false)
  let out = lifespan_events(app, [LifespanStartup])
  assert_true(out is [LifespanStartupComplete])
}

///|
test "url_for renders a named route's path, mount prefix included" {
  let blog = App::new()
  blog.get("/posts/{slug}", _ctx => @status.text(200, "p"), name="post")
  let app = App::new()
  app.get(
    "/users/{id}/cards/{card}",
    _ctx => @status.text(200, "c"),
    name="card",
  )
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
  app.route_stream(Get, "/b", _ctx => @status.Stream::new(_ => ()), name="b")
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
  r.route_stream(Get, "/b", _ctx => @status.Stream::new(_ => ()), name="rb")
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

///|
test "SJson is emitted into the document as it stands" {
  let app = App::new()
  app.post(
    "/posts",
    _ctx => @status.text(200, "ok"),
    endpoint=@endpoint.Endpoint::new(request_body=slug_body()),
  )
  let doc = app.openapi()
  let schema = json_at(doc, [
    "components", "schemas", "Post", "properties", "slug",
  ])
  assert_eq(schema, Some({ "type": "string", "pattern": "^[a-z0-9-]+$" }))
}

///|
async test "nullable: a nullable scalar parameter still parses as its base" {
  let app = param_app(
    @endpoint.Param::new(
      "limit",
      InQuery,
      schema=@schema.Schema::nullable(SInt),
      required=false,
      constraints=[@schema.Maximum(9.0)],
    ),
  )
  assert_eq(
    app.handle(mkreq_full("GET", "/items", query=b"limit=5")).status,
    200,
  )
  let bad = app.handle(mkreq_full("GET", "/items", query=b"limit=many"))
  assert_eq(bad.status, 422)
  assert_eq(json_str(detail0(bad), "type"), "int_parsing")
  // The bound compares numbers through the wrapper, not text.
  let over = app.handle(mkreq_full("GET", "/items", query=b"limit=99"))
  assert_eq(over.status, 422)
  assert_eq(json_str(detail0(over), "type"), "less_than_equal")
  // Swagger 2.0 reads the base type through the wrapper, since a 2.0 parameter
  // carries its type inline and has nowhere else to put it.
  assert_eq(json_str(only_param(app, Swagger20), "type"), "integer")
}

///|
async test "format: a formatted scalar parameter is documented and parsed as its base" {
  let app = param_app(
    @endpoint.Param::new(
      "at",
      InQuery,
      schema=@schema.Schema::format(SInt, "int64"),
      required=false,
      constraints=[@schema.Minimum(1.0)],
    ),
  )
  let schema = dig(only_param(app, OpenApi31), ["schema"]).unwrap()
  assert_eq(json_str(schema, "type"), "integer")
  assert_eq(json_str(schema, "format"), "int64")
  assert_eq(dig(schema, ["minimum"]), Some(Json(1.0)))
  let bad = app.handle(mkreq_full("GET", "/items", query=b"at=soon"))
  assert_eq(bad.status, 422)
  assert_eq(json_str(detail0(bad), "type"), "int_parsing")
  let low = app.handle(mkreq_full("GET", "/items", query=b"at=0"))
  assert_eq(low.status, 422)
  assert_eq(json_str(detail0(low), "type"), "greater_than_equal")
  assert_eq(app.handle(mkreq_full("GET", "/items", query=b"at=5")).status, 200)
  // 2.0 reads the base type through the format wrapper, as it does a nullable.
  assert_eq(json_str(only_param(app, Swagger20), "type"), "integer")
}

///|
async test "descriptor-driven validation: valid body passes, returns typed User" {
  let app = demo_app()
  let ok = app.handle(
    mkreq_full(
      "POST",
      "/users",
      body=@utf8.encode("{\"name\":\"ada\",\"email\":\"a@b.c\",\"age\":36}"),
    ),
  )
  assert_eq(ok.status, 201)
  // Response really is a serialised User (derive(ToJson) round trip).
  assert_eq(json_str(resp_json(ok), "name"), "ada")
  let addr = dig(resp_json(ok), ["address"]).unwrap()
  assert_eq(json_str(addr, "city"), "Nowhere")
}

///|
async test "descriptor-driven validation: missing required field -> located 422" {
  let app = demo_app()
  let miss = app.handle(
    mkreq_full("POST", "/users", body=@utf8.encode("{\"email\":\"a@b.c\"}")),
  )
  assert_eq(miss.status, 422)
  let e = detail0(miss)
  assert_eq(json_str(e, "type"), "missing")
  assert_eq(err_loc(e), ["body", "name"])
}

///|
async test "descriptor-driven validation: wrong body field type -> located 422" {
  let app = demo_app()
  let bad = app.handle(
    mkreq_full(
      "POST",
      "/users",
      body=@utf8.encode("{\"name\":\"x\",\"email\":\"y\",\"age\":\"NaN\"}"),
    ),
  )
  assert_eq(bad.status, 422)
  let e = detail0(bad)
  assert_eq(json_str(e, "type"), "int_type")
  assert_eq(err_loc(e), ["body", "age"])
}

///|
async test "descriptor-driven validation: unparseable path param -> located 422" {
  let app = demo_app()
  let bad = app.handle(mkreq_full("GET", "/users/not-a-number"))
  assert_eq(bad.status, 422)
  let e = detail0(bad)
  assert_eq(json_str(e, "type"), "int_parsing")
  assert_eq(err_loc(e), ["path", "id"])
  // A well-formed integer id passes and returns a User.
  let ok = app.handle(mkreq_full("GET", "/users/7"))
  assert_eq(ok.status, 200)
  assert_eq(dig(resp_json(ok), ["id"]).unwrap(), Json(7))
}

///|
async test "descriptor-driven validation: enum admits a member, rejects a non-member" {
  let app = enum_app()
  // A member value passes and echoes the body back.
  let ok = app.handle(
    mkreq_full("POST", "/orders", body=@utf8.encode("{\"status\":\"qwq\"}")),
  )
  assert_eq(ok.status, 200)
  // A non-member value is a located 422 with the `enum` Pydantic error kind.
  let bad = app.handle(
    mkreq_full("POST", "/orders", body=@utf8.encode("{\"status\":\"emm\"}")),
  )
  assert_eq(bad.status, 422)
  let e = detail0(bad)
  assert_eq(json_str(e, "type"), "enum")
  assert_eq(err_loc(e), ["body", "status"])
}

///|
async test "api key: a header route refuses a missing key and admits a valid one" {
  let app = guarded("Key")
  app.secure_api_key(
    "Key",
    @security.ApiKey::header("x-api-key", k => k == "s3cret"),
  )
  // No key at all.
  let anon = app.handle(mkreq("GET", "/vault"))
  assert_eq(anon.status, 403)
  assert_eq(detail_str(anon), "Not authenticated")
  // A key the scheme does not accept.
  let wrong = app.handle(mkreq_hdrs("GET", "/vault", [("x-api-key", "guess")]))
  assert_eq(wrong.status, 403)
  assert_eq(detail_str(wrong), "Invalid authentication credentials")
  // The real thing.
  let ok = app.handle(mkreq_hdrs("GET", "/vault", [("x-api-key", "s3cret")]))
  assert_eq(ok.status, 200)
  assert_eq(ok.body, @utf8.encode("gold"))
}

///|
async test "http basic: refused without credentials, admitted with the right pair" {
  let app = guarded("Basic")
  app.secure_basic(
    "Basic",
    @security.BasicAuth::new(
      c => c.username == "ada" && c.password == "lovelace",
      realm="vault",
    ),
  )
  let anon = app.handle(mkreq("GET", "/vault"))
  assert_eq(anon.status, 401)
  // RFC 9110 §15.5.2: a 401 has to say how to authenticate.
  assert_eq(anon.header("www-authenticate"), Some("Basic realm=\"vault\""))
  assert_eq(detail_str(anon), "Not authenticated")
  // base64("ada:wrong") / base64("ada:lovelace")
  let bad = app.handle(mkreq_auth("GET", "/vault", "Basic YWRhOndyb25n"))
  assert_eq(bad.status, 401)
  assert_eq(detail_str(bad), "Incorrect username or password")
  let ok = app.handle(mkreq_auth("GET", "/vault", "Basic YWRhOmxvdmVsYWNl"))
  assert_eq(ok.status, 200)
}

///|
async test "http bearer: a plain bearer scheme verifies the token and its scopes" {
  let app = App::new()
  app.set_clock(() => 1000L)
  app.secure_bearer("Bearer", "s3cret")
  app.get("/vault", _ctx => @status.text(200, "gold"), security=[
    @security.SecurityRequirement::new("Bearer", scopes=["read"]),
  ])
  let good = @security.create_access_token("ada", "s3cret", 1000L, scopes=[
    "read",
  ])
  assert_eq(
    app.handle(mkreq_auth("GET", "/vault", "Bearer " + good)).status,
    200,
  )
  let narrow = @security.create_access_token("ada", "s3cret", 1000L, scopes=[
    "write",
  ])
  assert_eq(
    app.handle(mkreq_auth("GET", "/vault", "Bearer " + narrow)).status,
    403,
  )
  let anon = app.handle(mkreq("GET", "/vault"))
  assert_eq(anon.status, 401)
  assert_eq(anon.header("www-authenticate"), Some("Bearer scope=\"read\""))
  let s = dig(app.openapi(version=OpenApi31), [
    "components", "securitySchemes", "Bearer",
  ]).unwrap()
  assert_eq(json_str(s, "type"), "http")
  assert_eq(json_str(s, "scheme"), "bearer")
  assert_eq(json_str(s, "bearerFormat"), "JWT")
  // 2.0 has no `http` type at all, so a bearer scheme becomes the standard
  // workaround: an apiKey in the `Authorization` header.
  let old = dig(app.openapi(version=Swagger20), [
    "securityDefinitions", "Bearer",
  ]).unwrap()
  assert_eq(json_str(old, "type"), "apiKey")
  assert_eq(json_str(old, "name"), "Authorization")
}

///|
async test "declared-only scheme: documented, and honestly unguarded" {
  let app = guarded("Key")
  app.add_security_scheme(
    "Key",
    ApiKeyHeader(name="x-api-key"),
    description="declared, never wired",
  )
  let s = dig(app.openapi(version=OpenApi31), [
    "components", "securitySchemes", "Key",
  ]).unwrap()
  assert_eq(json_str(s, "description"), "declared, never wired")
  // No enforcer, so the route is documented as protected and left open — the
  // same split FastAPI draws between a declared scheme and a wired dependency.
  assert_eq(app.handle(mkreq("GET", "/vault")).status, 200)
}

///|
test "securityScheme: OAuth2 password flow in OpenAPI 3.1" {
  let app = App::new()
  let bearer = @security.OAuth2PasswordBearer::new("token", "secret")
  app.add_security_scheme(
    "OAuth2PasswordBearer",
    bearer.scheme(scopes=[("items", "read and write items")]),
  )
  app.post("/token", _ctx => @status.text(200, "t"))
  let doc = app.openapi(version=OpenApi31)
  let sch = scheme_3x(doc, "OAuth2PasswordBearer")
  assert_eq(json_str(sch, "type"), "oauth2")
  let token_url = match sch {
    Object(m) =>
      match m.get("flows") {
        Some(Object(f)) =>
          match f.get("password") {
            Some(Object(p)) => json_str(Json(p), "tokenUrl")
            _ => ""
          }
        _ => ""
      }
    _ => ""
  }
  assert_eq(token_url, "token")
}

///|
test "securityScheme: OAuth2 flattens to the Swagger 2.0 shape" {
  let app = App::new()
  app.add_security_scheme(
    "OAuth2PasswordBearer",
    OAuth2Password(token_url="token", scopes=[("items", "manage items")]),
  )
  app.post("/token", _ctx => @status.text(200, "t"))
  let doc = app.openapi(version=Swagger20)
  let sch = scheme_20(doc, "OAuth2PasswordBearer")
  assert_eq(json_str(sch, "type"), "oauth2")
  assert_eq(json_str(sch, "flow"), "password")
  assert_eq(json_str(sch, "tokenUrl"), "token")
}

///|
test "securityScheme: HTTP bearer names its JWT format in 3.x" {
  let app = App::new()
  app.add_security_scheme("BearerAuth", HttpBearer(bearer_format="JWT"))
  app.get("/me", _ctx => @status.text(200, "me"))
  let sch = scheme_3x(app.openapi(version=OpenApi30), "BearerAuth")
  assert_eq(json_str(sch, "type"), "http")
  assert_eq(json_str(sch, "scheme"), "bearer")
  assert_eq(json_str(sch, "bearerFormat"), "JWT")
}

///|
test "securityScheme: HTTP bearer degrades to an apiKey in Swagger 2.0" {
  let app = App::new()
  app.add_security_scheme("BearerAuth", HttpBearer(bearer_format="JWT"))
  app.get("/me", _ctx => @status.text(200, "me"))
  let sch = scheme_20(app.openapi(version=Swagger20), "BearerAuth")
  assert_eq(json_str(sch, "type"), "apiKey")
  assert_eq(json_str(sch, "in"), "header")
  assert_eq(json_str(sch, "name"), "Authorization")
}

///|
test "securityScheme: an API key in a header" {
  let app = App::new()
  app.add_security_scheme("ApiKey", ApiKeyHeader(name="X-API-Key"))
  app.get("/me", _ctx => @status.text(200, "me"))
  let sch = scheme_3x(app.openapi(version=OpenApi31), "ApiKey")
  assert_eq(json_str(sch, "type"), "apiKey")
  assert_eq(json_str(sch, "in"), "header")
  assert_eq(json_str(sch, "name"), "X-API-Key")
}

///|
test "securityScheme: schemas and securitySchemes share components in 3.x" {
  let app = App::new()
  app.add_security_scheme("BearerAuth", HttpBearer(bearer_format="JWT"))
  app.get("/me", _ctx => @status.text(200, "me"))
  // No component schemas here, so components holds only securitySchemes.
  let doc = app.openapi(version=OpenApi31)
  let has = match doc {
    Object(m) =>
      match m.get("components") {
        Some(Object(c)) => c.get("securitySchemes") is Some(_)
        _ => false
      }
    _ => false
  }
  assert_eq(has, true)
}

///|
async test "OAuth2 flow: issue a token, then a protected route accepts it" {
  let app = oauth2_app(fixed(1000L))
  // POST /token with a urlencoded password form.
  let token_resp = app.handle(
    mkreq_form(
      "POST",
      "/token",
      "application/x-www-form-urlencoded",
      @utf8.encode("grant_type=password&username=alice&password=wonderland"),
    ),
  )
  assert_eq(token_resp.status, 200)
  let token = json_str(resp_json(token_resp), "access_token")
  assert_eq(json_str(resp_json(token_resp), "token_type"), "bearer")
  assert_eq(token != "", true)
  // GET /users/me with the bearer token -> 200 and the subject.
  let me = app.handle(mkreq_auth("GET", "/users/me", "Bearer " + token))
  assert_eq(me.status, 200)
  assert_eq(json_str(resp_json(me), "username"), "alice")
}

///|
async test "OAuth2 flow: wrong password is rejected at the token endpoint" {
  let app = oauth2_app(fixed(1000L))
  let resp = app.handle(
    mkreq_form(
      "POST",
      "/token",
      "application/x-www-form-urlencoded",
      @utf8.encode("username=alice&password=wrong"),
    ),
  )
  assert_eq(resp.status, 401)
  assert_eq(
    json_str(resp_json(resp), "detail"),
    "Incorrect username or password",
  )
}

///|
async test "protected route: missing token -> 401 Not authenticated" {
  let app = oauth2_app(fixed(1000L))
  let resp = app.handle(mkreq("GET", "/users/me"))
  assert_eq(resp.status, 401)
  assert_eq(resp.header("www-authenticate"), Some("Bearer"))
  assert_eq(json_str(resp_json(resp), "detail"), "Not authenticated")
}

///|
async test "protected route: a tampered token -> 401 Could not validate credentials" {
  let app = oauth2_app(fixed(1000L))
  let good = @security.create_access_token("alice", "demo-secret", 1000L)
  // Corrupt the last character of the signature segment.
  let parts = split_char(good, '.')
  let sig = parts[2]
  let flipped = if sig[sig.length() - 1] == 'a' { "b" } else { "a" }
  let tampered = parts[0] +
    "." +
    parts[1] +
    "." +
    sig[0:sig.length() - 1].to_owned() +
    flipped
  let resp = app.handle(mkreq_auth("GET", "/users/me", "Bearer " + tampered))
  assert_eq(resp.status, 401)
  assert_eq(
    json_str(resp_json(resp), "detail"),
    "Could not validate credentials",
  )
}

///|
async test "protected route: an expired token -> 401" {
  // Issue at t=1000 (exp=4600), verify at t=5000: expired.
  let app_issue = oauth2_app(fixed(1000L))
  let token_resp = app_issue.handle(
    mkreq_form(
      "POST",
      "/token",
      "application/x-www-form-urlencoded",
      @utf8.encode("username=alice&password=wonderland"),
    ),
  )
  let token = json_str(resp_json(token_resp), "access_token")
  let app_later = oauth2_app(fixed(5000L))
  let resp = app_later.handle(mkreq_auth("GET", "/users/me", "Bearer " + token))
  assert_eq(resp.status, 401)
  assert_eq(
    json_str(resp_json(resp), "detail"),
    "Could not validate credentials",
  )
}

///|
async test "scopes: a token with the scope passes, one without gets 403" {
  let app = oauth2_app(fixed(1000L))
  // Request the `items` scope at token time.
  let with_scope = app.handle(
    mkreq_form(
      "POST",
      "/token",
      "application/x-www-form-urlencoded",
      @utf8.encode("username=alice&password=wonderland&scope=me+items"),
    ),
  )
  let t1 = json_str(resp_json(with_scope), "access_token")
  let ok = app.handle(mkreq_auth("GET", "/users/me/items", "Bearer " + t1))
  assert_eq(ok.status, 200)
  assert_eq(json_str(resp_json(ok), "owner"), "alice")
  // A token granted only `me` is refused at the items route with 403.
  let narrow = app.handle(
    mkreq_form(
      "POST",
      "/token",
      "application/x-www-form-urlencoded",
      @utf8.encode("username=alice&password=wonderland&scope=me"),
    ),
  )
  let t2 = json_str(resp_json(narrow), "access_token")
  let forbidden_resp = app.handle(
    mkreq_auth("GET", "/users/me/items", "Bearer " + t2),
  )
  assert_eq(forbidden_resp.status, 403)
  assert_eq(
    json_str(resp_json(forbidden_resp), "detail"),
    "Not enough permissions",
  )
}

///|
/// The point of a streaming route: each write reaches the wire as a body event of its own, so a
/// client reads the first long before the last exists; an empty final event ends the body.
async test "a streaming route sends each write as its own body event" {
  let app = App::new()
  app.stream("/feed", _ctx => {
    @status.Stream::new(w => {
      w.write(b"one")
      w.write(b"two")
      w.write(b"three")
    })
  })
  let events = body_events(app, mkreq("GET", "/feed"))
  assert_true(
    events
    is [
      HttpResponseBody(body=b"one", more_body=true),
      HttpResponseBody(body=b"two", more_body=true),
      HttpResponseBody(body=b"three", more_body=true),
      HttpResponseBody(body=b"", more_body=false),
    ],
  )
}

///|
/// Stated as the invariant rather than the transcript: every event but the last says more is
/// coming, and the last says the reply is over.
async test "only the last body event of a stream clears more_body" {
  let app = App::new()
  app.stream("/feed", _ctx => {
    @status.Stream::new(w => {
      for c in ["a", "b", "c", "d"] {
        w.write_text(c)
      }
    })
  })
  assert_eq(more_body_flags(app, mkreq("GET", "/feed")), [
    true, true, true, true, false,
  ])
}

///|
/// An ordinary route is still one event; a buffered reply arriving in pieces would be a
/// regression, not a feature.
async test "a buffered route is still a single body event" {
  let app = App::new()
  app.get("/plain", _ctx => @status.text(200, "hello"))
  let events = body_events(app, mkreq("GET", "/plain"))
  assert_true(events is [HttpResponseBody(body=b"hello", more_body=false)])
}

///|
async test "a streaming route's status and headers reach the response start" {
  let app = App::new()
  app.stream("/feed", _ctx => {
    @status.Stream::new(
      status=@status.HTTP_201_CREATED,
      headers=[("x-trace", "heke1228")],
      w => w.write_text("qwq"),
    )
  })
  let events = stream_events(app, mkreq("GET", "/feed"))
  guard events[0] is HttpResponseStart(status~, headers~, ..) else {
    fail("no start")
  }
  assert_eq(status, 201)
  assert_eq(header_of(headers, "x-trace"), Some("heke1228"))
}

///|
/// An SSE endpoint is the case streaming exists for: each frame is its own chunk.
async test "an SSE route streams a chunk per event" {
  let app = App::new()
  app.stream("/events", _ctx => {
    @status.sse(e => {
      e.send(@sse.Event::of("one"))
      e.send(@sse.Event::of("two"))
      e.send(@sse.Event::of("three"))
    })
  })
  let events = stream_events(app, mkreq("GET", "/events"))
  guard events[0] is HttpResponseStart(headers~, ..) else { fail("no start") }
  assert_eq(
    header_of(headers, "content-type"),
    Some("text/event-stream; charset=utf-8"),
  )
  assert_eq(body_chunks(events), [
    "data: one\n\n", "data: two\n\n", "data: three\n\n",
  ])
}

///|
async test "a streamed reply joins into one body for a caller that reads it whole" {
  let app = App::new()
  app.stream("/feed", _ctx => {
    @status.Stream::new(w => {
      for c in ["one", "two", "three"] {
        w.write_text(c)
      }
    })
  })
  assert_eq(app.handle(mkreq("GET", "/feed")).body, b"onetwothree")
}

///|
/// A `HEAD` reply carries no body, so the stream is not produced at all.
async test "HEAD on a streaming route sends the head and never runs the body" {
  let ran = Ref(false)
  let app = App::new()
  app.stream("/feed", _ctx => {
    @status.Stream::new(w => {
      ran.val = true
      w.write_text("one")
    })
  })
  let events = body_events(app, mkreq("HEAD", "/feed"))
  assert_true(events is [HttpResponseBody(body=b"", more_body=false)])
  assert_false(ran.val)
}

///|
async test "a stream's early hints go first and its trailers last" {
  let app = App::new()
  app.stream("/feed", _ctx => {
    @status.Stream::new(
      early_hints=[["</app.css>; rel=preload"]],
      trailers=true,
      w => {
        w.write_text("data")
        w.trailer("x-sum", "42")
      },
    )
  })
  let events = stream_events(app, mkreq("GET", "/feed"))
  assert_true(
    events[0] is HttpResponseEarlyHint(links=["</app.css>; rel=preload"]),
  )
  assert_true(events[1] is HttpResponseStart(trailers=true, ..))
  assert_true(
    events[events.length() - 1]
    is HttpResponseTrailers(headers=[("x-sum", "42")], more_trailers=false),
  )
}

///|
/// The stream runs beside a watch on the connection: when the client goes, the body is
/// cancelled rather than left writing to nobody.
async test "a stream stops when the client goes" {
  let written = Ref(0)
  let app = App::new()
  app.stream("/ticks", _ctx => {
    @status.Stream::new(w => {
      for ;; {
        written.val += 1
        w.write_text("tick")
        @async.sleep(5)
      }
    })
  })
  let scope = @moonasgi.Scope::Http(
    @moonasgi.HttpScope::new(http_method="GET", path="/ticks"),
  )
  @testing.communicate(app.to_asgi(), scope, c => {
    c.send(HttpRequest(body=b"", more_body=false))
    assert_true(c.receive() is HttpResponseStart(status=200, ..))
    assert_true(c.receive() is HttpResponseBody(body=b"tick", ..))
    c.send(HttpDisconnect)
    c.wait()
  })
  let stopped_at = written.val
  @async.sleep(30)
  assert_eq(written.val, stopped_at)
}

///|
/// A layer that only touches the head leaves the chunk boundaries alone.
async test "a header-only layer leaves the chunk boundaries intact" {
  let app = App::new()
  app.layer(
    @mid.Wrap(inner => {
      async fn(scope, receive, send) {
        inner(scope, receive, event => {
          match event {
            HttpResponseStart(status~, headers~, trailers~) =>
              send(
                HttpResponseStart(
                  status~,
                  headers=[..headers, ("x-seen", "233")],
                  trailers~,
                ),
              )
            other => send(other)
          }
        })
      }
    }),
  )
  app.stream("/feed", _ctx => {
    @status.Stream::new(w => {
      w.write_text("one")
      w.write_text("two")
    })
  })
  let events = stream_events(app, mkreq("GET", "/feed"))
  guard events[0] is HttpResponseStart(headers~, ..) else { fail("no start") }
  assert_eq(header_of(headers, "x-seen"), Some("233"))
  assert_eq(body_chunks(events), ["one", "two"])
}

///|
async test "a mounted sub-app's stream survives the mount" {
  let sub = App::new()
  sub.stream("/feed", _ctx => {
    @status.Stream::new(w => {
      for c in ["one", "two", "three"] {
        w.write_text(c)
      }
    })
  })
  let app = App::new()
  app.mount("/sub", sub)
  assert_eq(more_body_flags(app, mkreq("GET", "/sub/feed")), [
    true, true, true, false,
  ])
}

///|
async test "per-op security: a scoped route accepts a scoped token, denies otherwise" {
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
async test "per-op security: an expired token is refused by the app clock" {
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
async test "per-op security: a documentation-only scheme is not enforced" {
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
/// A layer that writes "sent" to `log` as the last body event goes out.
fn sent_marker(log : Array[String]) -> &@mid.Layer {
  @mid.Wrap(inner => {
    async fn(scope, receive, send) {
      inner(scope, receive, event => {
        send(event)
        if event is HttpResponseBody(more_body=false, ..) {
          log.push("sent")
        }
      })
    }
  })
}

///|
async test "background tasks run after the response is sent, in the order added" {
  let log : Array[String] = []
  let app = App::new()
  app.layer(sent_marker(log))
  app.get("/notify", ctx => {
    ctx.background.add_task(() => log.push("a"))
    ctx.background.add_task(() => log.push("b"))
    log.push("handler")
    @status.text(202, "accepted")
  })
  app.get("/plain", _ctx => @status.text(200, "ok"))
  assert_eq(app.handle(mkreq("GET", "/notify")).status, 202)
  assert_eq(log, ["handler", "sent", "a", "b"])
  log.clear()
  ignore(app.handle(mkreq("GET", "/plain")))
  assert_eq(log, ["sent"])
}

///|
async test "a background task may await" {
  let log : Array[String] = []
  let app = App::new()
  app.get("/later", ctx => {
    ctx.background.add_task(() => {
      @async.sleep(1)
      log.push("done")
    })
    @status.text(200, "ok")
  })
  ignore(app.handle(mkreq("GET", "/later")))
  assert_eq(log, ["done"])
}

///|
async test "mount: a sub-app answers under its prefix and its root" {
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
async test "mount: the sub-app keeps its own middleware and security" {
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
async test "mount: a sub-app runs its own background tasks" {
  let log : Array[String] = []
  let sub = App::new()
  sub.get("/work", ctx => {
    ctx.background.add_task(() => log.push("sub-task"))
    @status.text(200, "queued")
  })
  let app = App::new()
  app.mount("/x", sub)
  assert_eq(app.handle(mkreq("GET", "/x/work")).status, 200)
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
async test "status handler: a custom 404 replaces the default not-found" {
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
async test "status handler: rewrites a raised HttpException's status response" {
  let app = App::new()
  app.add_status_handler(418, _ctx => @status.text(418, "custom teapot"))
  app.get("/boom", _ctx => raise @exceptions.http_error(418, "teapot"))
  let resp = app.handle(mkreq("GET", "/boom"))
  assert_eq(resp.status, 418)
  assert_eq(resp.body, @utf8.encode("custom teapot"))
}

///|
async test "status handler: a 405 method-mismatch can be customised too" {
  let app = App::new()
  app.add_status_handler(405, _ctx => @status.text(405, "no such method"))
  app.get("/only-get", _ctx => @status.text(200, "ok"))
  let resp = app.handle(mkreq("POST", "/only-get"))
  assert_eq(resp.status, 405)
  assert_eq(resp.body, @utf8.encode("no such method"))
}

///|
async test "enable_docs: Swagger UI with its OAuth2 redirect page and initOAuth" {
  let app = App::new()
  app.enable_docs(
    ui=Swagger,
    init_oauth={ "clientId": "web" },
    ui_extra=Map([("deepLinking", Json(false))]),
  )
  let page = @utf8.decode_lossy(app.handle(mkreq("GET", "/docs")).body)
  assert_eq(page.contains(@openapi.swagger_js), true)
  assert_eq(page.contains("\"deepLinking\":false"), true)
  assert_eq(
    page.contains(
      "config.oauth2RedirectUrl = window.location.origin + \"/docs/oauth2-redirect\";",
    ),
    true,
  )
  assert_eq(page.contains("ui.initOAuth({\"clientId\":\"web\"});"), true)
  let back = app.handle(mkreq("GET", "/docs/oauth2-redirect"))
  assert_eq(back.status, 200)
  assert_eq(
    @utf8.decode_lossy(back.body).contains(@openapi.swagger_redirect_js),
    true,
  )
  // The default reader has its own OAuth2 handling, so no redirect page is added.
  let plain = App::new()
  plain.enable_docs()
  assert_eq(plain.handle(mkreq("GET", "/docs/oauth2-redirect")).status, 404)
}

///|
async test "enable_docs: under a root_path the pages and the servers follow it" {
  let sub = App::new()
  sub.enable_docs()
  let app = App::new()
  app.mount("/api", sub)
  let page = @utf8.decode_lossy(app.handle(mkreq("GET", "/api/docs")).body)
  assert_eq(page.contains("{\"url\":\"/api/openapi.json\"}"), true)
  let redoc = @utf8.decode_lossy(app.handle(mkreq("GET", "/api/redoc")).body)
  assert_eq(redoc.contains("spec-url=\"/api/openapi.json\""), true)
  let spec = resp_json(app.handle(mkreq("GET", "/api/openapi.json")))
  assert_eq(json_str(dig_arr(spec, ["servers"])[0], "url"), "/api")
  // Turned off, the document names only the servers it was given.
  let quiet = App::new()
  quiet.enable_docs(root_path_in_servers=false)
  let app2 = App::new()
  app2.mount("/api", quiet)
  let spec2 = resp_json(app2.handle(mkreq("GET", "/api/openapi.json")))
  assert_eq(dig(spec2, ["servers"]), None)
}

///|
test "doc pages escape what they are given" {
  let page = @openapi.scalar_ui(title="<b>&", spec_url="/x</script>")
  assert_eq(page.contains("<title>&lt;b&gt;&amp;</title>"), true)
  assert_eq(page.contains("/x</script>"), false)
  assert_eq(page.contains("/x\\u003c/script>"), true)
  let redoc = @openapi.redoc_ui(spec_url="/a\"b", telemetry=true)
  assert_eq(redoc.contains("spec-url=\"/a&quot;b\">"), true)
}
