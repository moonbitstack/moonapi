///|
/// Build the app's OpenAPI document as a `Json` value, walking the registered
/// routes — this app's and every mounted sub-app's, each under its prefix — into
/// paths, methods and operations. `version` picks the dialect: Swagger 2.0,
/// OpenAPI 3.0.3 or 3.1.0 off the identical routes. Routes registered with
/// `include_in_schema=false` are left out.
pub fn App::openapi(
  self : App,
  version~ : @schema.OpenApiVersion = OpenApi31,
  title? : String,
  api_version? : String,
  description? : String,
  terms_of_service? : String,
  contact? : @openapi.Contact?,
  license? : @openapi.License?,
  servers? : Array[@openapi.Server],
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
  let all_routes : Array[(String, @route.Route)] = []
  self.collect_routes("", all_routes)
  for entry in all_routes {
    let (full_path, route) = entry
    if !route.include_in_schema {
      continue
    }
    let op : Map[String, Json] = Map([])
    if route.summary != "" {
      op["summary"] = Json(route.summary)
    }
    if route.description != "" {
      op["description"] = Json(route.description)
    }
    // FastAPI omits `tags` entirely when empty rather than emitting `[]`.
    if !route.tags.is_empty() {
      op["tags"] = Json(route.tags)
    }
    // FastAPI omits `deprecated` unless the route is actually deprecated.
    if route.deprecated {
      op["deprecated"] = Json(true)
    }
    if route.operation_id != "" {
      op["operationId"] = Json(route.operation_id)
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
          op["parameters"] = Json(params)
        }
        let ok : Map[String, Json] = Map([("description", Json("OK"))])
        let responses : Map[String, Json] = Map([
          (ok_status.to_string(), Json(ok)),
        ])
        op["responses"] = Json(responses)
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
      op["responses"] = Json(responses)
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
    item[method_lower(route.verb)] = Json(op)
    paths[doc_path] = Json(item)
  }
  let info : Map[String, Json] = Map([
    ("title", Json(title)),
    ("version", Json(api_version)),
  ])
  if description != "" {
    info["description"] = Json(description)
  }
  if terms_of_service != "" {
    info["termsOfService"] = Json(terms_of_service)
  }
  match contact {
    Some(c) => {
      let cm : Map[String, Json] = Map([])
      if c.name != "" {
        cm["name"] = Json(c.name)
      }
      if c.url != "" {
        cm["url"] = Json(c.url)
      }
      if c.email != "" {
        cm["email"] = Json(c.email)
      }
      if !cm.is_empty() {
        info["contact"] = Json(cm)
      }
    }
    None => ()
  }
  match license {
    Some(l) => {
      let lm : Map[String, Json] = Map([("name", Json(l.name))])
      if l.url != "" {
        lm["url"] = Json(l.url)
      }
      info["license"] = Json(lm)
    }
    None => ()
  }
  let (root_key, version_str) = version_field(version)
  let doc : Map[String, Json] = Map([
    (root_key, Json(version_str)),
    ("info", Json(info)),
    ("paths", Json(paths)),
  ])
  // `servers` is an OpenAPI 3.x construct (2.0 uses host/basePath), so emit it
  // only for the 3.x dialects.
  if !servers.is_empty() {
    match version {
      Swagger20 => ()
      _ => {
        let sarr : Array[Json] = []
        for s in servers {
          let sm : Map[String, Json] = Map([("url", Json(s.url))])
          if s.description != "" {
            sm["description"] = Json(s.description)
          }
          sarr.push(Json(sm))
        }
        doc["servers"] = Json(sarr)
      }
    }
  }
  // Hoisted named object schemas and the declared security schemes (the app's
  // own plus every mounted sub-app's): under `components` (`schemas` /
  // `securitySchemes`) in 3.x, or the top-level `definitions` /
  // `securityDefinitions` in Swagger 2.0.
  let schemes : Array[@security.DeclaredScheme] = []
  let seen : Map[String, Bool] = Map([])
  self.collect_security_schemes(schemes, seen)
  // Rendered before the emptiness test, since a scheme the target version cannot
  // express drops out here and must not leave an empty object behind.
  let rendered = security_schemes_json(schemes, version)
  let has_schemes = !rendered.is_empty()
  match version {
    Swagger20 => {
      if !defs.is_empty() {
        doc["definitions"] = Json(defs)
      }
      if has_schemes {
        doc["securityDefinitions"] = Json(rendered)
      }
    }
    _ =>
      if !defs.is_empty() || has_schemes {
        let comp : Map[String, Json] = Map([])
        if !defs.is_empty() {
          comp["schemas"] = Json(defs)
        }
        if has_schemes {
          comp["securitySchemes"] = Json(rendered)
        }
        doc["components"] = Json(comp)
      }
  }
  Json(doc)
}

///|
/// Collect this app's routes and every mounted sub-app's routes into `out`, each
/// paired with its full path (the mount prefixes joined on). Recursive, so
/// nested mounts flatten into one path space for the merged OpenAPI document.
fn App::collect_routes(
  self : App,
  prefix : String,
  out : Array[(String, @route.Route)],
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
  out : Array[@security.DeclaredScheme],
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
/// The app's OpenAPI / Swagger document for `version`, stringified.
pub fn App::openapi_json(
  self : App,
  version~ : @schema.OpenApiVersion = OpenApi31,
) -> String {
  self.openapi(version~).stringify(indent=2)
}

///|
/// Fill the operation object `op` from an endpoint descriptor for `version`,
/// hoisting named schemas into `defs`. Emits `parameters`, `requestBody` (or a
/// body parameter in 2.0), and `responses`; an endpoint with no declared
/// responses gets a default `OK` under `ok_status`, which is the route's
/// `status_code` or `200`.
fn emit_endpoint(
  op : Map[String, Json],
  ep : @endpoint.Endpoint,
  defs : Map[String, Json],
  version : @schema.OpenApiVersion,
  ok_status : Int32,
) -> Unit {
  let params : Array[Json] = []
  for p in ep.params {
    params.push(param_json(p, defs, version))
  }
  if params.length() > 0 {
    op["parameters"] = Json(params)
  }
  match ep.request_body {
    Some(body) =>
      attach_request_body(op, body, ep.request_required, defs, version)
    None => ()
  }
  let specs = if ep.responses.length() > 0 {
    ep.responses
  } else {
    [@endpoint.ResponseSpec::new(ok_status)]
  }
  let responses : Map[String, Json] = Map([])
  for rs in specs {
    responses[rs.status.to_string()] = response_json(rs, defs, version)
  }
  op["responses"] = Json(responses)
}

///|
/// One parameter as its OpenAPI parameter object for `version`. In Swagger 2.0 a
/// scalar type sits inline; in OpenAPI 3.x it lives under `schema`.
fn param_json(
  p : @endpoint.Param,
  defs : Map[String, Json],
  version : @schema.OpenApiVersion,
) -> Json {
  let m : Map[String, Json] = Map([
    ("name", Json(p.key())),
    ("in", Json(@endpoint.loc_str(p.loc))),
    ("required", Json(p.is_required())),
  ])
  if p.description != "" {
    m["description"] = Json(p.description)
  }
  match version {
    // Swagger 2.0 puts a scalar's type and its constraint keywords on the
    // parameter object itself — there is no `schema` to hang them off.
    Swagger20 =>
      match scalar_name(p.schema) {
        Some(t) => {
          m["type"] = Json(t)
          merge_into(m, param_facets(p, version))
        }
        None =>
          m["schema"] = param_facets_on(
            @schema.emit_schema(p.schema, defs, version),
            p,
            version,
          )
      }
    _ =>
      m["schema"] = param_facets_on(
        @schema.emit_schema(p.schema, defs, version),
        p,
        version,
      )
  }
  Json(m)
}

///|
/// Attach the request body of an endpoint to an operation object `op`. OpenAPI
/// 3.x uses a `requestBody` with a media-type map; Swagger 2.0 uses an
/// `in: body` parameter, so it is appended to `op`'s `parameters`.
fn attach_request_body(
  op : Map[String, Json],
  body : @schema.Schema,
  required : Bool,
  defs : Map[String, Json],
  version : @schema.OpenApiVersion,
) -> Unit {
  match version {
    Swagger20 => {
      let bp : Map[String, Json] = Map([
        ("name", Json("body")),
        ("in", Json("body")),
        ("required", Json(required)),
        ("schema", @schema.emit_schema(body, defs, version)),
      ])
      let existing : Array[Json] = match op.get("parameters") {
        Some(Array(a)) => a
        _ => []
      }
      existing.push(Json(bp))
      op["parameters"] = Json(existing)
    }
    _ => {
      let media : Map[String, Json] = Map([
        ("schema", @schema.emit_schema(body, defs, version)),
      ])
      let content : Map[String, Json] = Map([("application/json", Json(media))])
      let rb : Map[String, Json] = Map([
        ("required", Json(required)),
        ("content", Json(content)),
      ])
      op["requestBody"] = Json(rb)
    }
  }
}

///|
/// One response as its OpenAPI response object. OpenAPI 3.x nests the body schema
/// under `content."application/json".schema`; Swagger 2.0 puts it directly under
/// `schema`.
fn response_json(
  rs : @endpoint.ResponseSpec,
  defs : Map[String, Json],
  version : @schema.OpenApiVersion,
) -> Json {
  let m : Map[String, Json] = Map([("description", Json(rs.description))])
  match rs.body {
    Some(body) =>
      match version {
        Swagger20 => m["schema"] = @schema.emit_schema(body, defs, version)
        _ => {
          let media : Map[String, Json] = Map([
            ("schema", @schema.emit_schema(body, defs, version)),
          ])
          let content : Map[String, Json] = Map([
            ("application/json", Json(media)),
          ])
          m["content"] = Json(content)
        }
      }
    None => ()
  }
  Json(m)
}

///|
/// Just the keywords a parameter's constraints and default contribute, as a bare
/// object — for the Swagger 2.0 shape, which merges them into the parameter.
fn param_facets(p : @endpoint.Param, version : @schema.OpenApiVersion) -> Json {
  let empty : Map[String, Json] = Map([])
  param_facets_on(Json(empty), p, version)
}

///|
/// The scalar OpenAPI type name of a schema, `None` for composite schemas. A
/// format or a nullable wrapper does not change what the underlying value is, so
/// both report their base — which is what lets a Swagger 2.0 parameter, whose
/// type sits on the parameter object itself, carry them at all.
fn scalar_name(s : @schema.Schema) -> String? {
  match s {
    SStr => Some("string")
    SInt => Some("integer")
    SFloat => Some("number")
    SBool => Some("boolean")
    SNull => Some("null")
    SFormat(base, _) => scalar_name(base)
    SNullable(inner) => scalar_name(inner)
    _ => None
  }
}

///|
/// Copy every key of the JSON object `src` into `dst`, leaving `dst`'s other
/// keys alone. A non-object `src` contributes nothing.
fn merge_into(dst : Map[String, Json], src : Json) -> Unit {
  if src is Object(o) {
    for k, v in o {
      dst[k] = v
    }
  }
}

///|
/// The `{name: scheme, ...}` object for the app's declared schemes, rendered in
/// the shape `version` uses, each carrying its `description` when it has one. A
/// scheme the target version cannot express is omitted.
fn security_schemes_json(
  schemes : Array[@security.DeclaredScheme],
  version : @schema.OpenApiVersion,
) -> Map[String, Json] {
  let m : Map[String, Json] = Map([])
  for d in schemes {
    let body = match version {
      Swagger20 => d.kind.to_openapi_20()
      _ => Some(d.kind.to_openapi_3x())
    }
    match body {
      Some(j) =>
        m[d.name] = if d.description != "" {
          @schema.with_description(j, d.description)
        } else {
          j
        }
      None => ()
    }
  }
  m
}

///|
/// The `security` array for a route's requirements, or `None` when the route
/// declares none (so the key is omitted rather than emitted empty).
fn security_json(reqs : Array[@security.SecurityRequirement]) -> Json? {
  if reqs.is_empty() {
    return None
  }
  let arr : Array[Json] = []
  for r in reqs {
    arr.push(r.to_json())
  }
  Some(Json(arr))
}

///|
/// `j` with the parameter's constraints and default written into it.
fn param_facets_on(
  j : Json,
  p : @endpoint.Param,
  version : @schema.OpenApiVersion,
) -> Json {
  let with_c = @schema.with_constraints(j, p.constraints, version)
  match p.default {
    Some(d) => @schema.with_key(with_c, "default", d)
    None => with_c
  }
}

///|
/// (root document key, version string) for each spec version.
fn version_field(v : @schema.OpenApiVersion) -> (String, String) {
  match v {
    Swagger20 => ("swagger", "2.0")
    OpenApi30 => ("openapi", "3.0.3")
    OpenApi31 => ("openapi", "3.1.0")
  }
}

///|
/// Rewrite a route's `:name` segments into OpenAPI's `{name}` template expressions.
/// The spec requires a path parameter's `name` to correspond to a template
/// expression in the path itself, so emitting the route string as written produces a
/// document validators reject and Swagger UI cannot substitute values into.
fn path_template(path : String) -> String {
  let out = StringBuilder()
  for seg in @route.segments(path) {
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
fn path_parameters(
  path : String,
  version : @schema.OpenApiVersion,
) -> Array[Json] {
  let out : Array[Json] = []
  for seg in @route.segments(path) {
    if seg.length() > 0 && seg[0] == ':' {
      out.push(path_parameter(seg[1:].to_owned(), version))
    }
  }
  out
}

///|
/// Join a mount `prefix` and a route `path` into one path by concatenating their
/// segments, so `("/sub", "/items")` becomes `/sub/items` and a root path stays
/// under the prefix. An all-empty result is the root `"/"`.
fn join_prefix(prefix : String, path : String) -> String {
  let segs = @route.segments(prefix)
  for s in @route.segments(path) {
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
/// A `:name` path parameter as an OpenAPI parameter object for `version`. In
/// Swagger 2.0 the type sits inline; in OpenAPI 3.x it lives under `schema`,
/// which is the one structural difference between the two shapes.
fn path_parameter(name : String, version : @schema.OpenApiVersion) -> Json {
  let param : Map[String, Json] = Map([
    ("name", Json(name)),
    ("in", Json("path")),
    ("required", Json(true)),
  ])
  match version {
    Swagger20 => param["type"] = Json("string")
    _ => {
      let schema : Map[String, Json] = Map([("type", Json("string"))])
      param["schema"] = Json(schema)
    }
  }
  Json(param)
}
