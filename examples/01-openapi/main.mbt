///|
/// Typed routes in, OpenAPI out. Register a text `GET`, a `:param` `GET`, and a
/// `POST`, let the app `handle` a request, then dump the OpenAPI 3.1 document the
/// same routes generate — the role FastAPI plays in Python.
///
///     moon run examples/01-openapi
#coverage.skip
fn main {
  let app = @moonapi.App::new()
  app.get("/", _ctx => @moonapi.text(200, "moonapi <- FastAPI"))
  app.get(
    "/users/:id",
    ctx => @moonapi.text(200, "user " + ctx.param("id").unwrap()),
    summary="fetch a user",
  )
  app.post(
    "/users",
    _ctx => @moonapi.text(201, "created"),
    summary="create a user",
  )
  let req : @moonasgi.Request = {
    http_method: "GET",
    path: "/users/233",
    query_string: b"",
    headers: [],
    body: b"",
  }
  let resp = app.handle(req)
  println(
    "GET /users/233 -> \{resp.status} \{@utf8.decode_lossy(resp.body[:])}",
  )
  println(app.openapi_json(version=OpenApi31))
}
