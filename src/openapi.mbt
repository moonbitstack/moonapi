///|
/// Build the app's OpenAPI document as a `Json` value, walking the registered
/// routes — this app's and every mounted sub-app's, each under its prefix — into
/// paths, methods and operations. `version` picks the dialect: Swagger 2.0,
/// OpenAPI 3.0.3 or 3.1.0 off the identical routes. Routes registered with
/// `include_in_schema=false` are left out.
///
/// The webhooks go under `webhooks`, which only 3.1 has; callbacks go under
/// their operation in both 3.x dialects. Swagger 2.0 can express neither and
/// leaves them out. The named arguments override what `App::describe` set, for
/// this one document.
pub fn App::openapi(
  self : App,
  version~ : @schema.OpenApiVersion = OpenApi31,
  title? : String,
  summary? : String,
  api_version? : String,
  description? : String,
  terms_of_service? : String,
  contact? : @openapi.Contact?,
  license? : @openapi.License?,
  servers? : Array[@openapi.Server],
  tags? : Array[@openapi.Tag],
  external_docs? : @openapi.ExternalDocs?,
) -> Json {
  let cur = self.info
  let info : @openapi.ApiInfo = {
    title: title.unwrap_or(cur.title),
    summary: summary.unwrap_or(cur.summary),
    api_version: api_version.unwrap_or(cur.api_version),
    description: description.unwrap_or(cur.description),
    terms_of_service: terms_of_service.unwrap_or(cur.terms_of_service),
    contact: contact.unwrap_or(cur.contact),
    license: license.unwrap_or(cur.license),
    servers: servers.unwrap_or(cur.servers),
    tags: tags.unwrap_or(cur.tags),
    external_docs: external_docs.unwrap_or(cur.external_docs),
  }
  let paths : Map[String, Json] = Map([])
  let defs : Map[String, Json] = Map([])
  let all_routes : Array[(String, @route.Route)] = []
  self.collect_routes("", all_routes)
  for entry in all_routes {
    let (full_path, route) = entry
    guard route.include_in_schema &&
      operation_key(route.verb, version) is Some(key) else {
      continue
    }
    add_operation(
      paths,
      path_template(full_path),
      key,
      operation(route, full_path, defs, version, path_params=true),
    )
  }
  let hooks : Map[String, Json] = Map([])
  if version is OpenApi31 {
    for route in self.webhooks.routes {
      guard route.include_in_schema &&
        operation_key(route.verb, version) is Some(key) else {
        continue
      }
      add_operation(
        hooks,
        route.path,
        key,
        operation(route, route.path, defs, version, path_params=false),
      )
    }
  }
  let (root_key, version_str) = version_field(version)
  let doc : Map[String, Json] = Map([
    (root_key, Json(version_str)),
    ("info", info_json(info, version)),
    ("paths", Json(paths)),
  ])
  // `servers` is an OpenAPI 3.x construct (2.0 uses host/basePath), so emit it
  // only for the 3.x dialects.
  if !info.servers.is_empty() && !(version is Swagger20) {
    doc["servers"] = Json(info.servers.map(server_json))
  }
  if !hooks.is_empty() {
    doc["webhooks"] = Json(hooks)
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
  if !info.tags.is_empty() {
    doc["tags"] = Json(info.tags.map(t => t.to_json()))
  }
  if info.external_docs is Some(d) {
    doc["externalDocs"] = d.to_json()
  }
  Json(doc)
}

///|
/// Put `op` under `paths[path][key]`, beside whatever other methods that path
/// already has.
fn add_operation(
  paths : Map[String, Json],
  path : String,
  key : String,
  op : Json,
) -> Unit {
  let item = match paths.get(path) {
    Some(Object(m)) => m
    _ => Map([])
  }
  item[key] = op
  paths[path] = Json(item)
}

///|
/// One route as its operation object for `version`. `path_params` reads the
/// parameters an untyped route documents off its path; a webhook's name and a
/// callback's runtime expression are not request paths, so theirs are not.
fn operation(
  route : @route.Route,
  full_path : String,
  defs : Map[String, Json],
  version : @schema.OpenApiVersion,
  path_params~ : Bool,
) -> Json {
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
    // An untyped route: the path's own parameters and a default response.
    None => {
      let params = if path_params {
        path_parameters(full_path, version)
      } else {
        []
      }
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
  // Grouped by the callback route's name, then keyed by its expression. An
  // unnamed one is grouped under its expression.
  if !route.callbacks.is_empty() && !(version is Swagger20) {
    let callbacks : Map[String, Json] = Map([])
    for cb in route.callbacks {
      guard cb.include_in_schema && operation_key(cb.verb, version) is Some(key) else {
        continue
      }
      let name = if cb.name == "" { cb.path } else { cb.name }
      let item = match callbacks.get(name) {
        Some(Object(m)) => m
        _ => Map([])
      }
      add_operation(
        item,
        cb.path,
        key,
        operation(cb, cb.path, defs, version, path_params=false),
      )
      callbacks[name] = Json(item)
    }
    if !callbacks.is_empty() {
      op["callbacks"] = Json(callbacks)
    }
  }
  // Last, so `openapi_extra` can override any field moonapi generated. A
  // fragment that is not an object has nothing to merge and is ignored.
  if route.openapi_extra is Some(Object(extra)) {
    for k, v in extra {
      op[k] = v
    }
  }
  Json(op)
}

///|
/// The `info` object for `version`. `summary` and a license `identifier` are
/// 3.1's; the older dialects take the license `url` instead.
fn info_json(info : @openapi.ApiInfo, version : @schema.OpenApiVersion) -> Json {
  let m : Map[String, Json] = Map([("title", Json(info.title))])
  if info.summary != "" && version is OpenApi31 {
    m["summary"] = Json(info.summary)
  }
  m["version"] = Json(info.api_version)
  if info.description != "" {
    m["description"] = Json(info.description)
  }
  if info.terms_of_service != "" {
    m["termsOfService"] = Json(info.terms_of_service)
  }
  if info.contact is Some(c) {
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
      m["contact"] = Json(cm)
    }
  }
  if info.license is Some(l) {
    let lm : Map[String, Json] = Map([("name", Json(l.name))])
    if l.identifier != "" && version is OpenApi31 {
      lm["identifier"] = Json(l.identifier)
    } else if l.url != "" {
      lm["url"] = Json(l.url)
    }
    m["license"] = Json(lm)
  }
  Json(m)
}

///|
fn server_json(s : @openapi.Server) -> Json {
  let m : Map[String, Json] = Map([("url", Json(s.url))])
  if s.description != "" {
    m["description"] = Json(s.description)
  }
  Json(m)
}

///|
/// Named examples as the `examples` map an OpenAPI 3.x parameter or media type
/// carries.
fn examples_json(examples : Map[String, @endpoint.Example]) -> Json {
  let m : Map[String, Json] = Map([])
  for name, ex in examples {
    m[name] = ex.to_json()
  }
  Json(m)
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
  for route in self.router.routes {
    out.push((@route.join_prefix(prefix, route.path), route))
  }
  for entry in self.mounts {
    // A foreign handler describes nothing, so there is nothing of it to collect.
    if entry.1 is Sub(sub) {
      sub.collect_routes(@route.join_prefix(prefix, entry.0), out)
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
///
/// ```mbt
/// let doc = app.openapi_json()        // a JSON string for OpenAPI 3.1
/// ```
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
      attach_request_body(
        op,
        body,
        ep.request_required,
        ep.request_examples,
        defs,
        version,
      )
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
    _ => {
      m["schema"] = param_facets_on(
        @schema.emit_schema(p.schema, defs, version),
        p,
        version,
      )
      if !p.examples.is_empty() {
        m["examples"] = examples_json(p.examples)
      }
    }
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
  examples : Map[String, @endpoint.Example],
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
      if !examples.is_empty() {
        media["examples"] = examples_json(examples)
      }
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
/// and the named examples under `content."application/json"`; Swagger 2.0 puts
/// the schema directly under `schema` and has room for one example per media
/// type, which is the first one's value.
fn response_json(
  rs : @endpoint.ResponseSpec,
  defs : Map[String, Json],
  version : @schema.OpenApiVersion,
) -> Json {
  let m : Map[String, Json] = Map([("description", Json(rs.description))])
  match version {
    Swagger20 => {
      if rs.body is Some(body) {
        m["schema"] = @schema.emit_schema(body, defs, version)
      }
      if rs.examples.values().find_first(ex => ex.value is Some(_))
        is Some({ value: Some(v), .. }) {
        m["examples"] = Json({ "application/json": v })
      }
    }
    _ => {
      let media : Map[String, Json] = Map([])
      if rs.body is Some(body) {
        media["schema"] = @schema.emit_schema(body, defs, version)
      }
      if !rs.examples.is_empty() {
        media["examples"] = examples_json(rs.examples)
      }
      if !media.is_empty() {
        m["content"] = Json({ "application/json": Json(media) })
      }
    }
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
/// A route path as OpenAPI's template expression: every parameter as `{name}`.
/// The spec requires a path parameter's `name` to correspond to a template
/// expression in the path itself, and Swagger UI substitutes values into it.
fn path_template(path : String) -> String {
  let rendered = @route.Pattern::parse(path).template()
  if rendered == "" {
    "/"
  } else {
    rendered
  }
}

///|
/// The parameters of a route path, in order, as OpenAPI parameter objects typed
/// by their convertor — the faithful equivalent of FastAPI reading them off the
/// signature.
fn path_parameters(
  path : String,
  version : @schema.OpenApiVersion,
) -> Array[Json] {
  @route.Pattern::parse(path)
  .params()
  .map(p => path_parameter(p.0, p.1, version))
}

///|
/// A path parameter as an OpenAPI parameter object for `version`, its type taken
/// from the convertor. In Swagger 2.0 the type sits inline; in OpenAPI 3.x it
/// lives under `schema`, which is the one structural difference between the two
/// shapes.
fn path_parameter(
  name : String,
  convertor : @route.Convertor,
  version : @schema.OpenApiVersion,
) -> Json {
  let typed : Map[String, Json] = match convertor {
    Int => { "type": "integer" }
    Float => { "type": "number" }
    Uuid => { "type": "string", "format": "uuid" }
    Str | Path => { "type": "string" }
  }
  let param : Map[String, Json] = {
    "name": Json(name),
    "in": "path",
    "required": true,
  }
  match version {
    Swagger20 =>
      for k, v in typed {
        param[k] = v
      }
    _ => param["schema"] = Json(typed)
  }
  Json(param)
}

///|
/// The operation key a route is written under in an OpenAPI path item. The
/// documents moonapi writes have no key for CONNECT or an extension method, and
/// Swagger 2.0 none for TRACE either.
fn operation_key(
  m : @route.Method,
  version : @schema.OpenApiVersion,
) -> String? {
  match m {
    Connect | Other(_) => None
    Trace if version is Swagger20 => None
    m => Some(m.name().to_lower())
  }
}
