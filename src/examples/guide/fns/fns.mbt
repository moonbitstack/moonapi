///|
pub fn app() -> @moonapi.App {
  let app = @moonapi.App::new()
  // guide:first
  app.get("/", _ctx => @moonapi.text(200, "Hello from moonapi"))
  app.post("/users", _ctx => @moonapi.text(201, "created"))
  app.get("/users/{id}", ctx => {
    @moonapi.text(200, "user " + ctx.param("id").unwrap_or(""))
  })
  // end
  // guide:verbs
  app.get("/items/{id}", ctx => {
    @moonapi.text(200, "item " + ctx.param("id").unwrap_or(""))
  })
  app.post("/items", _ctx => @moonapi.text(201, "created"))
  app.put("/items/{id}", _ctx => @moonapi.text(200, "replaced"))
  app.patch("/items/{id}", _ctx => @moonapi.text(200, "patched"))
  app.delete("/items/{id}", _ctx => @moonapi.text(200, "deleted"))
  app.head("/items", _ctx => @moonapi.text(200, ""))
  app.options("/items", _ctx => @moonapi.text(204, ""))
  // end
  // guide:query
  app.get("/search", ctx => {
    let q = ctx.query("q").unwrap_or("")
    let limit = ctx.query("limit").unwrap_or("20")
    @moonapi.json(200, { "q": Json(q), "limit": Json(limit) })
  })
  // end
  // guide:body
  app.post("/login", ctx => {
    match ctx.body_json() {
      Some(body) => @moonapi.json(200, body)
      None => @moonapi.json(400, { "error": "bad json" })
    }
  })
  // end
  // guide:typed
  app.post("/greet", ctx => {
    match (ctx.body_validated(GreetReq::schema()) : Result[GreetReq, _]) {
      Ok(g) => @moonapi.text(200, "Hello, " + g.name)
      Err(e) => @moonapi.unprocessable(e)
    }
  })
  // end
  // guide:errors
  app.get("/boom", _ctx => {
    raise @exceptions.HttpException(status=418, detail="teapot", headers=[])
  })
  // end
  app
}

///|
pub fn openapi_app() -> @moonapi.App {
  let app = @moonapi.App::new()
  // guide:openapi
  app.get("/ping", _ctx => @moonapi.text(200, "pong"), summary="Health check", tags=[
    "misc",
  ])
  app.post(
    "/echo",
    _ctx => @moonapi.json(200, { "ok": true }),
    summary="Echo",
    tags=["misc"],
  )
  // end
  app
}

///|
priv struct GreetReq {
  name : String
} derive(FromJson)

///|
fn GreetReq::schema() -> @schema.Schema {
  @schema.Schema::object("GreetReq", [@schema.Field::new("name", SStr)])
}
