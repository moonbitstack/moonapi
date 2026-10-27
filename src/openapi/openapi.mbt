///|
/// OpenAPI `contact` info (← FastAPI's `contact`): every field optional, emitted
/// only when non-empty.
pub(all) struct Contact {
  name : String
  url : String
  email : String
}

///|
pub fn Contact::new(
  name~ : String = "",
  url~ : String = "",
  email~ : String = "",
) -> Contact {
  { name, url, email, }
}

///|
/// OpenAPI `license` info (← FastAPI's `license_info`): `name` required, then
/// either a `url` or, in OpenAPI 3.1, an SPDX `identifier`. The two exclude each
/// other in 3.1, so there an `identifier` is written and the `url` is not; the
/// older dialects have no `identifier` and get the `url`.
pub(all) struct License {
  name : String
  url : String
  identifier : String
}

///|
pub fn License::new(
  name : String,
  url~ : String = "",
  identifier~ : String = "",
) -> License {
  { name, url, identifier, }
}

///|
/// A `servers` entry (← FastAPI's `servers`): a base URL and an optional
/// description.
pub(all) struct Server {
  url : String
  description : String
}

///|
pub fn Server::new(url : String, description~ : String = "") -> Server {
  { url, description, }
}

///|
/// A link to documentation kept elsewhere: the `externalDocs` object, on the
/// document or on a tag.
pub(all) struct ExternalDocs {
  url : String
  description : String
}

///|
pub fn ExternalDocs::new(
  url : String,
  description~ : String = "",
) -> ExternalDocs {
  { url, description, }
}

///|
/// What the document says about one operation tag (← FastAPI's `openapi_tags`):
/// documentation viewers group operations by tag, in the order the tags are
/// listed here, and show this description above each group.
pub(all) struct Tag {
  name : String
  description : String
  external_docs : ExternalDocs?
}

///|
pub fn Tag::new(
  name : String,
  description~ : String = "",
  external_docs? : ExternalDocs,
) -> Tag {
  { name, description, external_docs, }
}

///|
/// What the document says about the API itself — FastAPI's `info` block plus
/// `servers`, the tag descriptions and the external documentation. An app
/// carries one (`App::describe` sets it) so that every emission of the
/// document, including the route `enable_docs` registers, agrees.
pub(all) struct ApiInfo {
  title : String
  // OpenAPI 3.1's one-line summary beside the longer `description`.
  summary : String
  api_version : String
  description : String
  terms_of_service : String
  contact : Contact?
  license : License?
  servers : Array[Server]
  tags : Array[Tag]
  external_docs : ExternalDocs?
}

///|
/// The defaults an app starts with.
pub fn ApiInfo::new() -> ApiInfo {
  {
    title: "moonapi",
    summary: "",
    api_version: "0.1.0",
    description: "",
    terms_of_service: "",
    contact: None,
    license: None,
    servers: [],
    tags: [],
    external_docs: None,
  }
}

///|
/// The `externalDocs` object for `docs`, the same in every dialect.
pub fn ExternalDocs::to_json(self : ExternalDocs) -> Json {
  let m : Map[String, Json] = { "url": Json(self.url) }
  if self.description != "" {
    m["description"] = Json(self.description)
  }
  Json(m)
}

///|
/// The tag object, the same in every dialect.
pub fn Tag::to_json(self : Tag) -> Json {
  let m : Map[String, Json] = { "name": Json(self.name) }
  if self.description != "" {
    m["description"] = Json(self.description)
  }
  if self.external_docs is Some(d) {
    m["externalDocs"] = d.to_json()
  }
  Json(m)
}

///|
/// Which reader `/docs` serves. `Scalar` is the current generation of API
/// reference, with a request client built in; `Swagger` is Swagger UI, the
/// long-standing one.
pub(all) enum Ui {
  Scalar
  Swagger
} derive(Eq, Debug)

///|
pub extend Ui with Eq::{equal, not_equal}

///|
pub extend Ui with Debug::{to_repr}

///|
/// The pages load their readers from a CDN at an exact version, so a page does
/// not change under an application that did not change. Self-hosting is a
/// matter of passing other URLs.
pub let swagger_js : String = "https://cdn.jsdelivr.net/npm/swagger-ui-dist@5.34.0/swagger-ui-bundle.js"

///|
pub let swagger_css : String = "https://cdn.jsdelivr.net/npm/swagger-ui-dist@5.34.0/swagger-ui.css"

///|
pub let swagger_redirect_js : String = "https://cdn.jsdelivr.net/npm/swagger-ui-dist@5.34.0/oauth2-redirect.js"

///|
pub let redoc_js : String = "https://cdn.jsdelivr.net/npm/redoc@3.0.1/bundles/redoc.standalone.js"

///|
pub let scalar_js : String = "https://cdn.jsdelivr.net/npm/@scalar/api-reference@1.76.0/dist/browser/standalone.js"

///|
/// `s` escaped for HTML text and attribute values.
fn html_escape(s : String) -> String {
  let out = StringBuilder()
  for c in s {
    match c {
      '&' => out.write_string("&amp;")
      '<' => out.write_string("&lt;")
      '>' => out.write_string("&gt;")
      '"' => out.write_string("&quot;")
      '\'' => out.write_string("&#39;")
      _ => out.write_char(c)
    }
  }
  out.to_string()
}

///|
/// `j` as a script literal. JSON is a subset of JavaScript; `<` is escaped too,
/// so no value can close the `<script>` it sits in.
fn script_json(j : Json) -> String {
  j.stringify().replace_all(old="<", new="\\u003c")
}

///|
/// A Swagger UI page rendering the document served at `spec_url` (← FastAPI's
/// `get_swagger_ui_html`). `oauth2_redirect_url` is the page an OAuth2 flow
/// returns to, served by `swagger_redirect`; `init_oauth` is handed to
/// `initOAuth` to prefill the client id, scopes and the like; `extra` is merged
/// over the settings passed to Swagger UI (← `swagger_ui_parameters`).
pub fn swagger_ui(
  spec_url~ : String = "/openapi.json",
  title~ : String = "moonapi",
  js_url~ : String = swagger_js,
  css_url~ : String = swagger_css,
  oauth2_redirect_url? : String,
  init_oauth? : Json,
  extra? : Map[String, Json],
) -> String {
  let config : Map[String, Json] = {
    "url": Json(spec_url),
    "dom_id": "#swagger-ui",
    "layout": "BaseLayout",
    "deepLinking": true,
    "showExtensions": true,
    "showCommonExtensions": true,
  }
  for k, v in extra.unwrap_or(Map([])) {
    config[k] = v
  }
  let redirect = match oauth2_redirect_url {
    Some(url) =>
      "\nconfig.oauth2RedirectUrl = window.location.origin + \{script_json(Json(url))};"
    None => ""
  }
  let oauth = match init_oauth {
    Some(j) => "\nui.initOAuth(\{script_json(j)});"
    None => ""
  }
  "<!doctype html>\n<html lang=\"en\">\n<head>\n<meta charset=\"utf-8\">\n<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n<title>\{html_escape(title)}</title>\n<link rel=\"stylesheet\" href=\"\{html_escape(css_url)}\">\n</head>\n<body>\n<div id=\"swagger-ui\"></div>\n<script src=\"\{html_escape(js_url)}\"></script>\n<script>\nconst config = \{script_json(Json(config))};\nconfig.presets = [SwaggerUIBundle.presets.apis, SwaggerUIBundle.SwaggerUIStandalonePreset];\{redirect}\nconst ui = SwaggerUIBundle(config);\{oauth}\n</script>\n</body>\n</html>\n"
}

///|
/// The page an OAuth2 authorisation started from Swagger UI returns to: it hands
/// the code or token back to the window that opened it (← FastAPI's
/// `get_swagger_ui_oauth2_redirect_html`).
pub fn swagger_redirect(js_url~ : String = swagger_redirect_js) -> String {
  "<!doctype html>\n<html lang=\"en-US\">\n<head>\n<title>Swagger UI: OAuth2 Redirect</title>\n</head>\n<body>\n<script src=\"\{html_escape(js_url)}\"></script>\n</body>\n</html>\n"
}

///|
/// A ReDoc page rendering the document served at `spec_url` (← FastAPI's
/// `get_redoc_html`): three panels, built for reading rather than for trying
/// calls out. ReDoc reports usage to its maker unless told not to; `telemetry`
/// is off unless turned on, since the page is served to this API's readers.
pub fn redoc_ui(
  spec_url~ : String = "/openapi.json",
  title~ : String = "moonapi",
  js_url~ : String = redoc_js,
  telemetry~ : Bool = false,
) -> String {
  let opt_out = if telemetry { "" } else { " disable-telemetry=\"true\"" }
  "<!doctype html>\n<html lang=\"en\">\n<head>\n<meta charset=\"utf-8\">\n<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n<title>\{html_escape(title)}</title>\n<style>body { margin: 0; }</style>\n</head>\n<body>\n<redoc spec-url=\"\{html_escape(spec_url)}\"\{opt_out}></redoc>\n<script type=\"module\" src=\"\{html_escape(js_url)}\"></script>\n</body>\n</html>\n"
}

///|
/// A Scalar API reference rendering the document served at `spec_url`: the
/// reference and a request client on one page. `extra` is merged over the
/// configuration passed to `Scalar.createApiReference`, which is where its
/// theme, layout and authentication defaults go.
pub fn scalar_ui(
  spec_url~ : String = "/openapi.json",
  title~ : String = "moonapi",
  js_url~ : String = scalar_js,
  extra? : Map[String, Json],
) -> String {
  let config : Map[String, Json] = { "url": Json(spec_url) }
  for k, v in extra.unwrap_or(Map([])) {
    config[k] = v
  }
  "<!doctype html>\n<html lang=\"en\">\n<head>\n<meta charset=\"utf-8\">\n<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n<title>\{html_escape(title)}</title>\n</head>\n<body>\n<div id=\"app\"></div>\n<script src=\"\{html_escape(js_url)}\"></script>\n<script>\nScalar.createApiReference(\"#app\", \{script_json(Json(config))});\n</script>\n</body>\n</html>\n"
}
