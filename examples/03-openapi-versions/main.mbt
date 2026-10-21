///|
/// One set of typed routes, every mainstream spec version. `App::openapi_json`
/// emits Swagger 2.0, OpenAPI 3.0.3, and OpenAPI 3.1.0 off the same descriptors;
/// `App::openapi` additionally takes the document metadata (title, description,
/// contact, license, servers) and `swagger_ui` returns a ready docs page. The
/// `demo_app` carries typed bodies, so the emitted specs show `components`
/// (`definitions` in 2.0) with `$ref`s.
///
///     moon run examples/03-openapi-versions
#coverage.skip
fn main {
  let app = @moonapi.demo_app()
  app.get(
    "/legacy",
    _ctx => @moonapi.text(200, "old"),
    summary="the legacy list",
    tags=["misc"],
    deprecated=true,
  )
  println("--- Swagger 2.0 (definitions) ---")
  println(app.openapi_json(version=Swagger20))
  println("--- OpenAPI 3.0.3 (components/schemas) ---")
  println(app.openapi_json(version=OpenApi30))
  println("--- OpenAPI 3.1.0 with full info metadata ---")
  let doc = app.openapi(
    version=OpenApi31,
    title="Widget API",
    api_version="2.3.0",
    description="a comprehensive moonapi example",
    contact=Some({ name: "lfanke", url: "", email: "heke1228@example.com", }),
    license=Some({
      name: "Apache-2.0",
      url: "https://www.apache.org/licenses/LICENSE-2.0",
    }),
    servers=[{ url: "https://api.example.com", description: "production", }],
  )
  println(doc.stringify(indent=2))
  println("swagger_ui page: \{@moonapi.swagger_ui().length()} bytes")
}
