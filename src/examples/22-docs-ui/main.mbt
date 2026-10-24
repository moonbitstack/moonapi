/// `enable_docs` puts the three pages FastAPI serves on the app: the OpenAPI
/// document, Swagger UI for trying calls out, and ReDoc for reading. All three stay
/// out of the document they describe, so a client sees only the real API.
///
///     moon run src/examples/22-docs-ui

///|
async fn main {
  let app = @moonapi.App::new()
  app.get(
    "/greet",
    _ctx => @moonapi.text(200, "hello, heke1228"),
    summary="greet a user",
  )
  app.describe(
    title="greet api",
    description="One route, documented three ways.",
    api_version="1.0.0",
  )
  app.enable_docs()
  for path in ["/openapi.json", "/docs", "/redoc"] {
    let resp = app.handle({
      http_method: "GET",
      path,
      query_string: b"",
      headers: [],
      body: b"",
    })
    let kind = match resp.header("content-type") {
      Some(t) => t
      None => "?"
    }
    println("\{path} -> \{resp.status} \{kind}, \{resp.body.length()} bytes")
  }
  // Turning a page off is per page.
  let bare = @moonapi.App::new()
  bare.enable_docs(docs_url=None, redoc_url=None)
  let missing = bare.handle({
    http_method: "GET",
    path: "/docs",
    query_string: b"",
    headers: [],
    body: b"",
  })
  println("with docs_url=None, /docs -> \{missing.status}")
}
