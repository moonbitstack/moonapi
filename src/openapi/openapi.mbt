///|
/// Build the OpenAPI / Swagger document for the app as a `Json` value, walking
/// the registered routes once into paths → methods → operations.
/// OpenAPI `contact` info (← FastAPI's `contact`): every field optional, emitted
/// only when non-empty.
pub(all) struct Contact {
  name : String
  url : String
  email : String
}

///|
/// OpenAPI `license` info (← FastAPI's `license_info`): `name` required, `url`
/// optional.
pub(all) struct License {
  name : String
  url : String
}

///|
/// A `servers` entry (← FastAPI's `servers`): a base URL and an optional
/// description.
pub(all) struct Server {
  url : String
  description : String
}

///|
/// What the document says about the API itself — FastAPI's `info` block plus
/// `servers`. An app carries one (`App::describe` sets it) so that every emission
/// of the document, including the route `enable_docs` registers, agrees.
pub(all) struct ApiInfo {
  title : String
  api_version : String
  description : String
  terms_of_service : String
  contact : Contact?
  license : License?
  servers : Array[Server]
}

///|
/// The defaults an app starts with.
pub fn ApiInfo::new() -> ApiInfo {
  {
    title: "moonapi",
    api_version: "0.1.0",
    description: "",
    terms_of_service: "",
    contact: None,
    license: None,
    servers: [],
  }
}

///|
/// A self-contained ReDoc page rendering the document served at `spec_url` — the
/// second reading of the same spec FastAPI serves at `/redoc`, three-panel and
/// built for reading rather than for trying calls out.
pub fn redoc_ui(
  spec_url~ : String = "/openapi.json",
  title~ : String = "moonapi",
) -> String {
  "<!doctype html>\n<html lang=\"en\">\n<head>\n<meta charset=\"utf-8\">\n<title>\{title}</title>\n<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n<style>body { margin: 0; }</style>\n</head>\n<body>\n<redoc spec-url=\"\{spec_url}\"></redoc>\n<script src=\"https://cdn.redoc.ly/redoc/latest/bundles/redoc.standalone.js\"></script>\n</body>\n</html>\n"
}

///|
/// A self-contained Swagger UI page rendering the document served at `spec_url`.
pub fn swagger_ui(
  spec_url~ : String = "/openapi.json",
  title~ : String = "moonapi",
) -> String {
  "<!doctype html>\n<html lang=\"en\">\n<head>\n<meta charset=\"utf-8\">\n<title>\{title}</title>\n<link rel=\"stylesheet\" href=\"https://unpkg.com/swagger-ui-dist/swagger-ui.css\">\n</head>\n<body>\n<div id=\"swagger-ui\"></div>\n<script src=\"https://unpkg.com/swagger-ui-dist/swagger-ui-bundle.js\"></script>\n<script>\nwindow.onload = () => { window.ui = SwaggerUIBundle({ url: \"\{spec_url}\", dom_id: \"#swagger-ui\" }); };\n</script>\n</body>\n</html>\n"
}
