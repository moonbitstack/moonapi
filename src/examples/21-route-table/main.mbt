///|
/// Routes kept in one table, apart from the handlers they point at. `path`,
/// `view` and `group` each make an entry; `app.urls` registers them in order,
/// the order a request tries them in.
///
///     moon run src/examples/21-route-table
#coverage.skip
async fn main {
  let app = @moonapi.App::new()
  app.urls([
    @moonapi.path("/", home),
    @moonapi.path("/items", create_item, methods=[Post]),
    @moonapi.group("/admin", [@moonapi.path("/stats", stats)], tags=["admin"]),
  ])
  for request in [("GET", "/"), ("POST", "/items"), ("GET", "/admin/stats")] {
    let r = app.handle({
      http_method: request.0,
      path: request.1,
      query_string: b"",
      headers: [],
      body: b"",
    })
    println(
      "\{request.0} \{request.1} -> \{r.status} \{@utf8.decode_lossy(r.body[:])}",
    )
  }
}

///|
let home : @moonapi.ApiHandler = _ctx => @moonapi.text(200, "home")

///|
let create_item : @moonapi.ApiHandler = _ctx => @moonapi.text(201, "created")

///|
let stats : @moonapi.ApiHandler = _ctx => @moonapi.text(200, "3 items")
