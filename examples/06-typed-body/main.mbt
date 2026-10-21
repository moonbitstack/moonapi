///|
/// The typed body extractors. `Context::body_validated[T]` checks the JSON body
/// against a descriptor and only then deserialises into a `derive(FromJson)`
/// struct, returning either the built value or a FastAPI-shaped `422`;
/// `Context::body[T]` is the unchecked, total counterpart that yields `None`
/// rather than erroring. `GreetReq` is a library struct with `derive(FromJson)`
/// and a `schema()`.
///
///     moon run examples/06-typed-body
#coverage.skip
fn main {
  let app = @moonapi.App::new()
  // Validated extraction: conform, or get located errors.
  app.post("/greet", ctx => {
    match (ctx.body_validated(GreetReq::schema()) : Result[GreetReq, _]) {
      Ok(g) => @moonapi.text(200, "Hello, " + g.name)
      Err(errs) => @moonapi.unprocessable(errs)
    }
  })
  // Unchecked extraction: a total `T?`, `None` when the body cannot shape-match.
  app.post("/echo", ctx => {
    let parsed : GreetReq? = ctx.body()
    match parsed {
      Some(g) => @moonapi.text(200, "parsed name=" + g.name)
      None => @moonapi.text(200, "unparseable")
    }
  })
  let hit = (path : String, body : String) => {
    let req : @moonasgi.Request = {
      http_method: "POST",
      path,
      query_string: b"",
      headers: [("content-type", "application/json")],
      body: @utf8.encode(body),
    }
    let r = app.handle(req)
    println(
      "POST \{path} \{body} -> \{r.status} \{@utf8.decode_lossy(r.body[:])}",
    )
  }
  hit("/greet", "{\"name\":\"lfanke\"}") // 200
  hit("/greet", "{\"name\":233}") // 422 string_type
  hit("/greet", "") // 422 missing body
  hit("/echo", "{\"name\":\"qwq\"}") // parsed
  hit("/echo", "not json at all") // unparseable
}
