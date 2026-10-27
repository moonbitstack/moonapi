///|
/// Routing across every HTTP verb, path parameters, and the 404-vs-405
/// distinction. `App::get/post/put/patch/delete` bind a method to a path;
/// `App::route` binds an explicit `Method`; a `{name}` piece lands in
/// `Context::param`. A path that exists under another verb answers 405, an
/// unknown path answers 404.
///
///     moon run src/examples/02-routing
#coverage.skip
async fn main {
  let app = @moonapi.App::new()
  app.get("/items/{id}", ctx => {
    @moonapi.text(200, "item " + ctx.param("id").unwrap())
  })
  app.post("/items", _ctx => @moonapi.text(201, "created"))
  app.put("/items/{id}", _ctx => @moonapi.text(200, "replaced"))
  app.patch("/items/{id}", _ctx => @moonapi.text(200, "patched"))
  app.delete("/items/{id}", _ctx => @moonapi.text(200, "deleted"))
  app.route(Head, "/items", _ctx => @moonapi.text(200, ""))
  app.route(Options, "/items", _ctx => @moonapi.text(204, ""))
  let hit = (verb : String, path : String) => {
    let req : @moonasgi.Request = {
      http_method: verb,
      path,
      query_string: b"",
      headers: [],
      body: b"",
    }
    let r = app.handle(req)
    println("\{verb} \{path} -> \{r.status} \{@utf8.decode_lossy(r.body[:])}")
  }
  hit("GET", "/items/233")
  hit("POST", "/items")
  hit("PUT", "/items/233")
  hit("PATCH", "/items/233")
  hit("DELETE", "/items/233")
  hit("HEAD", "/items")
  hit("OPTIONS", "/items")
  hit("GET", "/items") // path exists (POST/HEAD/OPTIONS) but not for GET -> 405
  hit("GET", "/missing") // no such path -> 404
}
