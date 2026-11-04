// guide:first

///|
#app.get("/")
fn hello(_ctx : @moonapi.Context) -> @moonasgi.Response {
  @moonapi.text(200, "Hello from moonapi")
}

///|
#app.post("/users")
fn create_user(_ctx : @moonapi.Context) -> @moonasgi.Response {
  @moonapi.text(201, "created")
}

///|
#app.get("/users/{id}")
fn user(ctx : @moonapi.Context) -> @moonasgi.Response {
  @moonapi.text(200, "user " + ctx.param("id").unwrap_or(""))
}
// end

// guide:verbs

///|
#app.get("/items/{id}")
fn read_item(ctx : @moonapi.Context) -> @moonasgi.Response {
  @moonapi.text(200, "item " + ctx.param("id").unwrap_or(""))
}

///|
#app.post("/items")
fn create_item(_ctx : @moonapi.Context) -> @moonasgi.Response {
  @moonapi.text(201, "created")
}

///|
#app.put("/items/{id}")
fn replace_item(_ctx : @moonapi.Context) -> @moonasgi.Response {
  @moonapi.text(200, "replaced")
}

///|
#app.patch("/items/{id}")
fn patch_item(_ctx : @moonapi.Context) -> @moonasgi.Response {
  @moonapi.text(200, "patched")
}

///|
#app.delete("/items/{id}")
fn delete_item(_ctx : @moonapi.Context) -> @moonasgi.Response {
  @moonapi.text(200, "deleted")
}

///|
#app.head("/items")
fn head_items(_ctx : @moonapi.Context) -> @moonasgi.Response {
  @moonapi.text(200, "")
}

///|
#app.options("/items")
fn options_items(_ctx : @moonapi.Context) -> @moonasgi.Response {
  @moonapi.text(204, "")
}
// end

// guide:query

///|
#app.get("/search")
fn search(ctx : @moonapi.Context) -> @moonasgi.Response {
  let q = ctx.query("q").unwrap_or("")
  let limit = ctx.query("limit").unwrap_or("20")
  @moonapi.json(200, { "q": Json(q), "limit": Json(limit) })
}
// end

// guide:body

///|
#app.post("/login")
fn login(ctx : @moonapi.Context) -> @moonasgi.Response {
  match ctx.body_json() {
    Some(body) => @moonapi.json(200, body)
    None => @moonapi.json(400, { "error": "bad json" })
  }
}
// end

// guide:typed

///|
#derive(FromJson)
priv struct GreetReq {
  name : String
}

///|
fn GreetReq::schema() -> @schema.Schema {
  @schema.Schema::object("GreetReq", [@schema.Field::new("name", SStr)])
}

///|
#app.post("/greet")
fn greet(ctx : @moonapi.Context) -> @moonasgi.Response {
  match (ctx.body_validated(GreetReq::schema()) : Result[GreetReq, _]) {
    Ok(g) => @moonapi.text(200, "Hello, " + g.name)
    Err(e) => @moonapi.unprocessable(e)
  }
}
// end

// guide:errors

///|
#app.get("/boom")
fn boom(_ctx : @moonapi.Context) -> @moonasgi.Response raise {
  raise @exceptions.HttpException(status=418, detail="teapot", headers=[])
}
// end
