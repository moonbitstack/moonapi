/// An app serves four pages from the start: the OpenAPI document and three
/// readers of it — the API reference for trying calls out, ReDoc for reading,
/// and Redocly's reference. All of them stay out of the document they describe,
/// so a client sees only the real API.
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
    description="One route, documented four ways.",
    api_version="1.0.0",
  )
  for path in ["/openapi.json", "/docs", "/redoc", "/redocly"] {
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
  // `/docs` serves the Scalar reference unless `ui` says otherwise; `/redoc`
  // and `/redocly` serve their own reader whatever `/docs` serves.
  let readers : Array[(@openapi.Ui, String)] = [
    (@openapi.Scalar, "Scalar"),
    (@openapi.Swagger, "Swagger UI"),
    (@openapi.Redoc, "ReDoc"),
    (@openapi.Redocly, "Redocly"),
  ]
  for entry in readers {
    let other = @moonapi.App::new()
    other.enable_docs(ui=entry.0)
    let page = other.handle({
      http_method: "GET",
      path: "/docs",
      query_string: b"",
      headers: [],
      body: b"",
    })
    println(
      "/docs as \{entry.1} -> \{page.status}, \{page.body.length()} bytes",
    )
  }
  // Turning a page off is per page, and docs=None turns them all off.
  let bare = @moonapi.App::new()
  bare.enable_docs(docs_url=None, redoc_url=None, redocly_url=None)
  let missing = bare.handle({
    http_method: "GET",
    path: "/docs",
    query_string: b"",
    headers: [],
    body: b"",
  })
  println("with docs_url=None, /docs -> \{missing.status}")
  // `theme=Plain` drops the site's chrome and leaves the reader as it ships.
  let plain = @moonapi.App::new()
  plain.enable_docs(theme=@openapi.Plain)
  let shipped = plain.handle({
    http_method: "GET",
    path: "/docs",
    query_string: b"",
    headers: [],
    body: b"",
  })
  println("theme=Plain -> \{shipped.body.length()} bytes, no bar")
}
