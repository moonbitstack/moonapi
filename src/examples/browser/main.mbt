///|
/// The application the site's playground sends requests to: one route per verb,
/// a templated path and a query, so a request either binds its parameters,
/// answers 405 with the methods the path does own, or answers 404.
fn playground() -> @moonapi.App {
  let app = @moonapi.App::new(docs=None)
  app.get("/", _ctx => @moonapi.text(200, "Hello from moonapi"))
  app.get(
    "/users/{id}",
    ctx => @moonapi.text(200, "user " + ctx.param("id").unwrap_or("")),
    summary="Fetch one user",
  )
  app.post("/users", _ctx => @moonapi.text(201, "created"), status_code=201)
  app.get("/search", ctx => {
    @moonapi.json(200, {
      "q": Json(ctx.query("q").unwrap_or("")),
      "limit": Json(ctx.query("limit").unwrap_or("")),
    })
  })
  app.get("/items/{id}", ctx => item("item", ctx))
  app.put("/items/{id}", ctx => item("replaced", ctx))
  app.patch("/items/{id}", ctx => item("patched", ctx))
  app.delete("/items/{id}", _ctx => @moonapi.text(204, ""))
  app.post("/items", _ctx => @moonapi.text(201, "created"), status_code=201)
  app.head("/items", _ctx => @moonapi.text(200, ""))
  app.options("/items", _ctx => @moonapi.text(204, ""))
  app.describe(title="playground", api_version="1.0.0")
  app
}

///|
fn item(verb : String, ctx : @moonapi.Context) -> @moonasgi.Response {
  @moonapi.text(200, "\{verb} \{ctx.param("id").unwrap_or("")}")
}

///|
/// What the page shows of one request: the answer the application gives, the
/// route the router reached with the parameters it bound, the methods a `405`
/// offers, and where a trailing-slash redirect points.
async fn answer(http_method : String, target : String) -> String {
  let app = playground()
  let (path, query) = match target.find("?") {
    Some(i) => (target[0:i].to_owned(), target[i + 1:].to_owned())
    None => (target, "")
  }
  let reply = app.handle({
    http_method,
    path,
    query_string: @utf8.encode(query),
    headers: [],
    body: b"",
  })
  let matched : Json = match app.route_for(http_method, path) {
    Reached(route, params) =>
      {
        "path": Json(route.path),
        "params": Json::object(
          Map(params.iter().map(kv => (kv.0, Json(kv.1))).collect()),
        ),
      }
    MethodNotAllowed(methods) =>
      { "path": Json::null(), "allow": Json(methods.join(", ")) }
    NotFound => { "path": Json::null() }
  }
  @moonjson.dumps({
    "status": Json(reply.status),
    "route": matched,
    "headers": Json::object(
      Map(
        reply.headers
        .iter()
        .filter(kv => ["allow", "location", "content-type"].contains(kv.0))
        .map(kv => (kv.0, Json(kv.1)))
        .collect(),
      ),
    ),
    "body": Json(@utf8.decode_lossy(reply.body)),
  })
}

///|
/// One request from the page. A promise rather than a callback: the page awaits
/// it, and the application runs on the same asynchronous runtime it runs on in
/// a server.
pub fn dispatch(
  http_method : String,
  target : String,
) -> @js_async.Promise[String] {
  @js_async.Promise::from_async(async fn() { answer(http_method, target) })
}

///|
/// The routes the playground offers, so the page's examples and the application
/// it sends them to are written once.
pub fn routes() -> String {
  let app = playground()
  let lines : Array[String] = []
  for route in app.routes() {
    lines.push("\{route.verb.name()} \{route.path}")
  }
  @moonjson.dumps(Json::array(lines.map(s => Json(s))))
}
