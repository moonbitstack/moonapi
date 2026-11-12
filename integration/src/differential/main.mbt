///|
/// The application the comparison runs: one route per shape whose answer two
/// mature frameworks can also produce — a static path, a converter, a query, a
/// created resource and a method a path does not answer.
fn subject() -> @moonapi.App {
  let app = @moonapi.App::new(docs=None)
  app.get("/", _ctx => @moonapi.text(200, "root"))
  app.post("/users", _ctx => @moonapi.text(201, "created"), status_code=201)
  app.get(
    "/users/{id:int}",
    ctx => @moonapi.text(200, "user " + ctx.param("id").unwrap_or("")),
  )
  app.get(
    "/search",
    ctx => @moonapi.json(200, {
      "q": Json(ctx.query("q").unwrap_or("")),
      "limit": Json(ctx.query("limit").unwrap_or("")),
    }),
  )
  app.get("/items/{id}", ctx => {
    @moonapi.text(200, "item " + ctx.param("id").unwrap_or(""))
  })
  app.post("/items", _ctx => @moonapi.text(201, "created"), status_code=201)
  app.delete("/items/{id}", _ctx => @moonapi.text(204, ""))
  app.options("/items", _ctx => @moonapi.text(204, ""))
  app
}

///|
/// The requests every side is asked, in order.
fn cases() -> Array[(String, String)] {
  [
    ("GET", "/"),
    ("POST", "/users"),
    ("GET", "/users/42"),
    ("GET", "/users/abc"),
    ("GET", "/search?q=cat&limit=5"),
    ("HEAD", "/search"),
    ("OPTIONS", "/items"),
    ("GET", "/items/9"),
    ("DELETE", "/items/9"),
    ("PUT", "/items/9"),
    ("GET", "/items"),
    ("GET", "/missing"),
    ("GET", "/items/9/"),
    ("POST", "/users/"),
  ]
}

///|
fn header(reply : @moonasgi.Response, name : String) -> Json {
  match reply.header(name) {
    Some(v) => Json(v)
    None => Json::null()
  }
}

///|
async fn main {
  let app = subject()
  for entry in cases() {
    let (http_method, target) = entry
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
    let allow : Json = match reply.header("allow") {
      Some(a) =>
        Json::array(
          a
          .split(", ")
          .map(s => Json(s))
          .collect(),
        )
      None => Json::null()
    }
    println(
      @moonjson.dumps({
        "method": Json(http_method),
        "path": Json(target),
        "status": Json(reply.status),
        "allow": allow,
        "location": header(reply, "location"),
        "body": Json(@utf8.decode_lossy(reply.body)),
      }),
    )
  }
}
