// guide:first

///|
struct Home {}

///|
impl @moonapi.View for Home with fn get(_) {
  Some(_ctx => @moonapi.text(200, "Hello from moonapi"))
}

///|
struct Users {}

///|
impl @moonapi.View for Users with fn post(_) {
  Some(_ctx => @moonapi.text(201, "created"))
}

///|
struct User {}

///|
impl @moonapi.View for User with fn get(_) {
  Some(ctx => @moonapi.text(200, "user " + ctx.param("id").unwrap_or("")))
}
// end

// guide:verbs

///|
struct Items {}

///|
impl @moonapi.View for Items with fn post(_) {
  Some(_ctx => @moonapi.text(201, "created"))
}

///|
impl @moonapi.View for Items with fn head(_) {
  Some(_ctx => @moonapi.text(200, ""))
}

///|
impl @moonapi.View for Items with fn options(_) {
  Some(_ctx => @moonapi.text(204, ""))
}

///|
struct Item {}

///|
impl @moonapi.View for Item with fn get(_) {
  Some(ctx => @moonapi.text(200, "item " + ctx.param("id").unwrap_or("")))
}

///|
impl @moonapi.View for Item with fn put(_) {
  Some(_ctx => @moonapi.text(200, "replaced"))
}

///|
impl @moonapi.View for Item with fn patch(_) {
  Some(_ctx => @moonapi.text(200, "patched"))
}

///|
impl @moonapi.View for Item with fn delete(_) {
  Some(_ctx => @moonapi.text(200, "deleted"))
}
// end

// guide:query

///|
struct Search {}

///|
impl @moonapi.View for Search with fn get(_) {
  Some(ctx => {
    let q = ctx.query("q").unwrap_or("")
    let limit = ctx.query("limit").unwrap_or("20")
    @moonapi.json(200, { "q": Json(q), "limit": Json(limit) })
  })
}
// end

// guide:body

///|
struct Login {}

///|
impl @moonapi.View for Login with fn post(_) {
  Some(ctx => {
    match ctx.body_json() {
      Some(body) => @moonapi.json(200, body)
      None => @moonapi.json(400, { "error": "bad json" })
    }
  })
}
// end

// guide:typed

///|
struct Greet {}

///|
impl @moonapi.View for Greet with fn post(_) {
  Some(ctx => {
    match (ctx.body_validated(GreetReq::schema()) : Result[GreetReq, _]) {
      Ok(g) => @moonapi.text(200, "Hello, " + g.name)
      Err(e) => @moonapi.unprocessable(e)
    }
  })
}
// end

// guide:errors

///|
struct Boom {}

///|
impl @moonapi.View for Boom with fn get(_) {
  Some(_ctx => {
    raise @exceptions.HttpException(status=418, detail="teapot", headers=[])
  })
}
// end

// guide:openapi

///|
struct Ping {}

///|
impl @moonapi.View for Ping with fn get(_) {
  Some(_ctx => @moonapi.text(200, "pong"))
}

///|
struct Echo {}

///|
impl @moonapi.View for Echo with fn post(_) {
  Some(_ctx => @moonapi.json(200, { "ok": true }))
}
// end

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
pub fn app() -> @moonapi.App {
  let app = @moonapi.App::new()
  // guide:first.register
  app.view("/", Home::{ })
  app.view("/users", Users::{ })
  app.view("/users/{id}", User::{ })
  // end
  // guide:verbs.register
  app.view("/items", Items::{ })
  app.view("/items/{id}", Item::{ })
  // end
  // guide:query.register
  app.view("/search", Search::{ })
  // end
  // guide:body.register
  app.view("/login", Login::{ })
  // end
  // guide:typed.register
  app.view("/greet", Greet::{ })
  // end
  // guide:errors.register
  app.view("/boom", Boom::{ })
  // end
  app
}

///|
pub fn openapi_app() -> @moonapi.App {
  let app = @moonapi.App::new()
  // guide:openapi.register
  app.view("/ping", Ping::{ }, tags=["misc"])
  app.view("/echo", Echo::{ }, tags=["misc"])
  // end
  app
}
