///|
/// Target OpenAPI / Swagger document version. moonapi emits every mainstream
/// version from the same route descriptors — a "good FastAPI" is not pinned to
/// one spec version.
pub(all) enum OpenApiVersion {
  Swagger20
  OpenApi30
  OpenApi31
} derive(Eq)

///|
/// (root document key, version string) for each spec version.
fn version_field(v : OpenApiVersion) -> (String, String) {
  match v {
    Swagger20 => ("swagger", "2.0")
    OpenApi30 => ("openapi", "3.0.3")
    OpenApi31 => ("openapi", "3.1.0")
  }
}

///|
/// A `:name` path parameter as an OpenAPI parameter object for `version`. In
/// Swagger 2.0 the type sits inline; in OpenAPI 3.x it lives under `schema`,
/// which is the one structural difference between the two shapes.
fn path_parameter(name : String, version : OpenApiVersion) -> Json {
  let param : Map[String, Json] = Map([
    ("name", name.to_json()),
    ("in", "path".to_json()),
    ("required", true.to_json()),
  ])
  match version {
    Swagger20 => param["type"] = "string".to_json()
    _ => {
      let schema : Map[String, Json] = Map([("type", "string".to_json())])
      param["schema"] = schema.to_json()
    }
  }
  param.to_json()
}

///|
/// Rewrite a route's `:name` segments into OpenAPI's `{name}` template expressions.
/// The spec requires a path parameter's `name` to correspond to a template
/// expression in the path itself, so emitting the route string as written produces a
/// document validators reject and Swagger UI cannot substitute values into.
fn path_template(path : String) -> String {
  let out = StringBuilder()
  for seg in segments(path) {
    out.write_char('/')
    if seg.length() > 0 && seg[0] == ':' {
      out.write_char('{')
      out.write_string(seg[1:].to_owned())
      out.write_char('}')
    } else {
      out.write_string(seg)
    }
  }
  let rendered = out.to_string()
  if rendered == "" {
    "/"
  } else {
    rendered
  }
}

///|
/// The `:name` parameters of a route path, in order, as OpenAPI parameter
/// objects — the faithful equivalent of FastAPI reading them off the signature.
fn path_parameters(path : String, version : OpenApiVersion) -> Array[Json] {
  let out : Array[Json] = []
  for seg in segments(path) {
    if seg.length() > 0 && seg[0] == ':' {
      out.push(path_parameter(seg[1:].to_owned(), version))
    }
  }
  out
}

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
/// Build the app's OpenAPI document as a `Json` value, walking the registered
/// routes — this app's and every mounted sub-app's, each under its prefix — into
/// paths, methods and operations. `version` picks the dialect: Swagger 2.0,
/// OpenAPI 3.0.3 or 3.1.0 off the identical routes. Routes registered with
/// `include_in_schema=false` are left out.
pub fn App::openapi(
  self : App,
  version? : OpenApiVersion = OpenApi31,
  title? : String,
  api_version? : String,
  description? : String,
  terms_of_service? : String,
  contact? : Contact?,
  license? : License?,
  servers? : Array[Server],
) -> Json {
  // An explicit argument wins; otherwise the app's own metadata, so the served
  // document and a hand-built one agree.
  let title = title.unwrap_or(self.info.title)
  let api_version = api_version.unwrap_or(self.info.api_version)
  let description = description.unwrap_or(self.info.description)
  let terms_of_service = terms_of_service.unwrap_or(self.info.terms_of_service)
  let contact = contact.unwrap_or(self.info.contact)
  let license = license.unwrap_or(self.info.license)
  let servers = servers.unwrap_or(self.info.servers)
  let paths : Map[String, Json] = Map([])
  let defs : Map[String, Json] = Map([])
  // Own routes plus every mounted sub-app's routes, each under its prefix.
  let all_routes : Array[(String, Route)] = []
  self.collect_routes("", all_routes)
  for entry in all_routes {
    let (full_path, route) = entry
    if !route.include_in_schema {
      continue
    }
    let op : Map[String, Json] = Map([])
    if route.summary != "" {
      op["summary"] = route.summary.to_json()
    }
    if route.description != "" {
      op["description"] = route.description.to_json()
    }
    // FastAPI omits `tags` entirely when empty rather than emitting `[]`.
    if !route.tags.is_empty() {
      op["tags"] = route.tags.to_json()
    }
    // FastAPI omits `deprecated` unless the route is actually deprecated.
    if route.deprecated {
      op["deprecated"] = true.to_json()
    }
    if route.operation_id != "" {
      op["operationId"] = route.operation_id.to_json()
    }
    let ok_status = route.status_code.unwrap_or(200)
    match route.endpoint {
      // A typed route: walk its descriptor once for parameters, request body,
      // responses, and any hoisted component schemas.
      Some(ep) => emit_endpoint(op, ep, defs, version, ok_status)
      // An untyped route: the `:name` path params and a default response.
      None => {
        let params = path_parameters(full_path, version)
        if params.length() > 0 {
          op["parameters"] = params.to_json()
        }
        let ok : Map[String, Json] = Map([("description", "OK".to_json())])
        let responses : Map[String, Json] = Map([
          (ok_status.to_string(), ok.to_json()),
        ])
        op["responses"] = responses.to_json()
      }
    }
    // The route's own `responses` are written after the descriptor's, so on a
    // status both name, the one declared at the route stands.
    if !route.responses.is_empty() {
      let responses : Map[String, Json] = match op.get("responses") {
        Some(Object(m)) => m
        _ => Map([])
      }
      for rs in route.responses {
        responses[rs.status.to_string()] = response_json(rs, defs, version)
      }
      op["responses"] = responses.to_json()
    }
    // Per-operation security requirements (← FastAPI's `Security(...)`).
    match security_json(route.security) {
      Some(s) => op["security"] = s
      None => ()
    }
    // Last, so `openapi_extra` can override any field moonapi generated. A
    // fragment that is not an object has nothing to merge and is ignored.
    if route.openapi_extra is Some(Object(extra)) {
      for k, v in extra {
        op[k] = v
      }
    }
    let doc_path = path_template(full_path)
    let item = match paths.get(doc_path) {
      Some(Object(m)) => m
      _ => Map([])
    }
    item[method_lower(route.verb)] = op.to_json()
    paths[doc_path] = item.to_json()
  }
  let info : Map[String, Json] = Map([
    ("title", title.to_json()),
    ("version", api_version.to_json()),
  ])
  if description != "" {
    info["description"] = description.to_json()
  }
  if terms_of_service != "" {
    info["termsOfService"] = terms_of_service.to_json()
  }
  match contact {
    Some(c) => {
      let cm : Map[String, Json] = Map([])
      if c.name != "" {
        cm["name"] = c.name.to_json()
      }
      if c.url != "" {
        cm["url"] = c.url.to_json()
      }
      if c.email != "" {
        cm["email"] = c.email.to_json()
      }
      if !cm.is_empty() {
        info["contact"] = cm.to_json()
      }
    }
    None => ()
  }
  match license {
    Some(l) => {
      let lm : Map[String, Json] = Map([("name", l.name.to_json())])
      if l.url != "" {
        lm["url"] = l.url.to_json()
      }
      info["license"] = lm.to_json()
    }
    None => ()
  }
  let (root_key, version_str) = version_field(version)
  let doc : Map[String, Json] = Map([
    (root_key, version_str.to_json()),
    ("info", info.to_json()),
    ("paths", paths.to_json()),
  ])
  // `servers` is an OpenAPI 3.x construct (2.0 uses host/basePath), so emit it
  // only for the 3.x dialects.
  if !servers.is_empty() {
    match version {
      Swagger20 => ()
      _ => {
        let sarr : Array[Json] = []
        for s in servers {
          let sm : Map[String, Json] = Map([("url", s.url.to_json())])
          if s.description != "" {
            sm["description"] = s.description.to_json()
          }
          sarr.push(sm.to_json())
        }
        doc["servers"] = sarr.to_json()
      }
    }
  }
  // Hoisted named object schemas and the declared security schemes (the app's
  // own plus every mounted sub-app's): under `components` (`schemas` /
  // `securitySchemes`) in 3.x, or the top-level `definitions` /
  // `securityDefinitions` in Swagger 2.0.
  let schemes : Array[DeclaredScheme] = []
  let seen : Map[String, Bool] = Map([])
  self.collect_security_schemes(schemes, seen)
  // Rendered before the emptiness test, since a scheme the target version cannot
  // express drops out here and must not leave an empty object behind.
  let rendered = security_schemes_json(schemes, version)
  let has_schemes = !rendered.is_empty()
  match version {
    Swagger20 => {
      if !defs.is_empty() {
        doc["definitions"] = defs.to_json()
      }
      if has_schemes {
        doc["securityDefinitions"] = rendered.to_json()
      }
    }
    _ =>
      if !defs.is_empty() || has_schemes {
        let comp : Map[String, Json] = Map([])
        if !defs.is_empty() {
          comp["schemas"] = defs.to_json()
        }
        if has_schemes {
          comp["securitySchemes"] = rendered.to_json()
        }
        doc["components"] = comp.to_json()
      }
  }
  doc.to_json()
}

///|
/// Collect this app's routes and every mounted sub-app's routes into `out`, each
/// paired with its full path (the mount prefixes joined on). Recursive, so
/// nested mounts flatten into one path space for the merged OpenAPI document.
fn App::collect_routes(
  self : App,
  prefix : String,
  out : Array[(String, Route)],
) -> Unit {
  for route in self.routes {
    out.push((join_prefix(prefix, route.path), route))
  }
  for entry in self.mounts {
    // A foreign handler describes nothing, so there is nothing of it to collect.
    if entry.1 is Sub(sub) {
      sub.collect_routes(join_prefix(prefix, entry.0), out)
    }
  }
}

///|
/// Collect this app's security schemes and every mounted sub-app's, first-writer
/// wins (a parent's scheme shadows a sub-app's same-named one). `seen` tracks
/// names already taken.
fn App::collect_security_schemes(
  self : App,
  out : Array[DeclaredScheme],
  seen : Map[String, Bool],
) -> Unit {
  for d in self.security_schemes {
    if !seen.contains(d.name) {
      seen[d.name] = true
      out.push(d)
    }
  }
  for entry in self.mounts {
    if entry.1 is Sub(sub) {
      sub.collect_security_schemes(out, seen)
    }
  }
}

///|
/// Join a mount `prefix` and a route `path` into one path by concatenating their
/// segments, so `("/sub", "/items")` becomes `/sub/items` and a root path stays
/// under the prefix. An all-empty result is the root `"/"`.
fn join_prefix(prefix : String, path : String) -> String {
  let segs = segments(prefix)
  for s in segments(path) {
    segs.push(s)
  }
  if segs.is_empty() {
    return "/"
  }
  let sb = StringBuilder()
  for s in segs {
    sb.write_string("/")
    sb.write_string(s)
  }
  sb.to_string()
}

///|
/// The app's OpenAPI / Swagger document for `version`, stringified.
pub fn App::openapi_json(
  self : App,
  version? : OpenApiVersion = OpenApi31,
) -> String {
  self.openapi(version~).stringify(indent=2)
}

///|
/// A self-contained ReDoc page rendering the document served at `spec_url` — the
/// second reading of the same spec FastAPI serves at `/redoc`, three-panel and
/// built for reading rather than for trying calls out.
pub fn redoc_ui(
  spec_url? : String = "/openapi.json",
  title? : String = "moonapi",
) -> String {
  "<!doctype html>\n<html lang=\"en\">\n<head>\n<meta charset=\"utf-8\">\n<title>\{title}</title>\n<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n<style>body { margin: 0; }</style>\n</head>\n<body>\n<redoc spec-url=\"\{spec_url}\"></redoc>\n<script src=\"https://cdn.redoc.ly/redoc/latest/bundles/redoc.standalone.js\"></script>\n</body>\n</html>\n"
}

///|
/// A self-contained Swagger UI page rendering the document served at `spec_url`.
pub fn swagger_ui(
  spec_url? : String = "/openapi.json",
  title? : String = "moonapi",
) -> String {
  "<!doctype html>\n<html lang=\"en\">\n<head>\n<meta charset=\"utf-8\">\n<title>\{title}</title>\n<link rel=\"stylesheet\" href=\"https://unpkg.com/swagger-ui-dist/swagger-ui.css\">\n</head>\n<body>\n<div id=\"swagger-ui\"></div>\n<script src=\"https://unpkg.com/swagger-ui-dist/swagger-ui-bundle.js\"></script>\n<script>\nwindow.onload = () => { window.ui = SwaggerUIBundle({ url: \"\{spec_url}\", dom_id: \"#swagger-ui\" }); };\n</script>\n</body>\n</html>\n"
}

///|
pub extend OpenApiVersion with Eq::{not_equal, equal}
