///|
/// The descriptor tree drives validation and OpenAPI from one source of truth.
/// The `users_app` in `models.mbt`: its `Endpoint` / `Param` / `Schema` / `ResponseSpec` descriptors
/// validate an inbound `POST /users` body and a typed `:id` path param, and the
/// same tree emits the request/response body schemas — objects, arrays, and a
/// nested `Address` hoisted into `components/schemas` behind a `$ref`. A body
/// that violates the descriptor comes back as a FastAPI-shaped `422`.
///
///     moon run src/examples/04-descriptors
#coverage.skip
async fn main {
  let app = users_app()
  let json_headers = [("content-type", "application/json")]
  let hit = (verb : String, path : String, body : String) => {
    let req : @moonasgi.Request = {
      http_method: verb,
      path,
      query_string: b"",
      headers: json_headers,
      body: @utf8.encode(body),
    }
    let r = app.handle(req)
    println("\{verb} \{path} -> \{r.status} \{@utf8.decode_lossy(r.body[:])}")
  }
  // A conforming body validates and deserialises.
  hit(
    "POST", "/users", "{\"name\":\"qwq\",\"email\":\"qwq@example.com\",\"age\":23}",
  )
  // Missing the required `name` -> 422 with a located `missing` error.
  hit("POST", "/users", "{\"email\":\"qwq@example.com\",\"age\":23}")
  // A typed integer path param returns the nested `User` (address + tags).
  hit("GET", "/users/233", "")
  println("--- OpenAPI 3.1.0 (note components/schemas + $ref) ---")
  println(app.openapi_json(version=OpenApi31))
}
