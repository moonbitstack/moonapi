///|
fn root_version(doc : Json, key : String) -> String {
  match doc {
    Object(m) =>
      match m.get(key) {
        Some(String(s)) => s
        _ => ""
      }
    _ => ""
  }
}

///|
test "openapi emits path parameters" {
  let app = App::new()
  app.get("/users/:id", _ctx => @status.text(200, "u"))
  let doc = app.openapi(version=OpenApi31)
  let params = match doc {
    Object(m) =>
      match m.get("paths") {
        Some(Object(p)) =>
          match p.get("/users/{id}") {
            Some(Object(methods)) =>
              match methods.get("get") {
                Some(Object(op)) =>
                  match op.get("parameters") {
                    Some(Array(a)) => a
                    _ => []
                  }
                _ => []
              }
            _ => []
          }
        _ => []
      }
    _ => []
  }
  assert_eq(params.length(), 1)
  assert_eq(json_str(params[0], "name"), "id")
  assert_eq(json_str(params[0], "in"), "path")
}

///|
test "openapi multi-version output" {
  let app = App::new()
  app.get("/ping", _ctx => @status.text(200, "pong"), summary="health check")
  app.post("/ping", _ctx => @status.text(200, "pong"))
  assert_eq(root_version(app.openapi(version=OpenApi31), "openapi"), "3.1.0")
  assert_eq(root_version(app.openapi(version=OpenApi30), "openapi"), "3.0.3")
  assert_eq(root_version(app.openapi(version=Swagger20), "swagger"), "2.0")
  // one path with two methods
  let doc = app.openapi(version=OpenApi31)
  let n = match doc {
    Object(m) =>
      match m.get("paths") {
        Some(Object(p)) =>
          match p.get("/ping") {
            Some(Object(methods)) => methods.length()
            _ => 0
          }
        _ => 0
      }
    _ => 0
  }
  assert_eq(n, 2)
}

///|
test "openapi operation tags" {
  let app = App::new()
  app.get("/nav", _ctx => @status.text(200, "ok"), tags=["ai", "navigator"])
  app.get("/plain", _ctx => @status.text(200, "ok"))
  let doc = app.openapi(version=OpenApi31)
  // The tagged operation carries its tags, in registration order.
  let tags = match op_of(doc, "/nav", "get") {
    Some(Object(op)) =>
      match op.get("tags") {
        Some(Array(xs)) =>
          xs.map(x => {
            match x {
              String(s) => s
              _ => ""
            }
          })
        _ => []
      }
    _ => []
  }
  assert_eq(tags, ["ai", "navigator"])
  // An untagged operation omits the key entirely (FastAPI parity).
  let has_tags = match op_of(doc, "/plain", "get") {
    Some(Object(op)) => op.contains("tags")
    _ => false
  }
  assert_eq(has_tags, false)
}

///|
test "openapi operation deprecated flag" {
  let app = App::new()
  app.get("/old", _ctx => @status.text(200, "ok"), deprecated=true)
  app.get("/new", _ctx => @status.text(200, "ok"))
  let doc = app.openapi(version=OpenApi31)
  // The deprecated operation carries `"deprecated": true`.
  let dep = match op_of(doc, "/old", "get") {
    Some(Object(op)) => op.get("deprecated")
    _ => None
  }
  assert_eq(dep, Some(Json(true)))
  // A live operation omits the key entirely (FastAPI parity — false is not emitted).
  let has_dep = match op_of(doc, "/new", "get") {
    Some(Object(op)) => op.contains("deprecated")
    _ => false
  }
  assert_eq(has_dep, false)
}

///|
/// The prose, the stable handle a client generator names its method after, and
/// the status the success response is documented under — three of the keyword
/// arguments a FastAPI path operation takes.
test "openapi operation description, operationId and status_code" {
  let app = App::new()
  app.post(
    "/items",
    _ctx => @status.text(201, "made"),
    summary="create an item",
    description="Stores the item and answers with where it went.",
    operation_id="create_item",
    status_code=201,
  )
  app.get("/plain", _ctx => @status.text(200, "ok"))
  let doc = app.openapi()
  guard op_of(doc, "/items", "post") is Some(Object(op)) else {
    fail("the operation should be present")
  }
  assert_eq(
    op.get("description"),
    Some(Json("Stores the item and answers with where it went.")),
  )
  assert_eq(op.get("operationId"), Some(Json("create_item")))
  // `status_code` is what the success response is keyed by, in place of 200.
  assert_eq(op_responses(doc, "/items", "post").keys().collect(), ["201"])
  // A route that says none of it emits none of it, the way FastAPI does.
  guard op_of(doc, "/plain", "get") is Some(Object(plain)) else {
    fail("the operation should be present")
  }
  assert_eq(plain.contains("description"), false)
  assert_eq(plain.contains("operationId"), false)
  assert_eq(op_responses(doc, "/plain", "get").keys().collect(), ["200"])
}

///|
/// A typed route's default response is keyed the same way; one that declares its
/// own responses is not overruled by a status the route only documents.
test "openapi status_code keys a typed endpoint's default response" {
  let app = App::new()
  app.post(
    "/items",
    _ctx => @status.text(201, "made"),
    status_code=201,
    endpoint=@endpoint.Endpoint::new(params=[
      @endpoint.Param::new("q", InQuery, required=false),
    ]),
  )
  app.post(
    "/declared",
    _ctx => @status.text(200, "ok"),
    status_code=201,
    endpoint=@endpoint.Endpoint::new(responses=[
      @endpoint.ResponseSpec::new(200),
    ]),
  )
  let doc = app.openapi()
  assert_eq(op_responses(doc, "/items", "post").keys().collect(), ["201"])
  assert_eq(op_responses(doc, "/declared", "post").keys().collect(), ["200"])
}

///|
/// `responses` documents what else an operation can answer, beside the success
/// response moonapi derives.
test "openapi operation responses join the derived one" {
  let app = App::new()
  app.get("/thing", _ctx => @status.text(200, "x"), responses=[
    @endpoint.ResponseSpec::new(404, description="no such thing"),
  ])
  let rs = op_responses(app.openapi(), "/thing", "get")
  assert_eq(resp_desc(rs, "200"), "OK")
  assert_eq(resp_desc(rs, "404"), "no such thing")
}

///|
/// The escape hatch: `openapi_extra` goes in after everything moonapi generated,
/// so a caller can add a field the framework has no idea about, or replace one it
/// got wrong for them.
test "openapi_extra is merged last and overrides a generated field" {
  let app = App::new()
  app.get("/thing", _ctx => @status.text(200, "x"), summary="generated", openapi_extra={
    "summary": "hand-written",
    "x-internal": true,
  })
  guard op_of(app.openapi(), "/thing", "get") is Some(Object(op)) else {
    fail("the operation should be present")
  }
  assert_eq(op.get("summary"), Some(Json("hand-written")))
  assert_eq(op.get("x-internal"), Some(Json(true)))
  // What it does not name is left as generated.
  assert_eq(op.contains("responses"), true)
}

///|
test "openapi richer info: description/contact/license + servers" {
  let app = App::new()
  app.get("/ping", _ctx => @status.text(200, "ok"))
  let doc = app.openapi(
    version=OpenApi31,
    title="Greet",
    description="qwq api",
    contact=Some({ name: "heke1228", url: "", email: "emm@qq.com", }),
    license=Some({ name: "Apache-2.0", url: "https://apache.org", }),
    servers=[{ url: "https://api.example.com", description: "prod", }],
  )
  guard doc is Object(m) else { fail("doc should be an object") }
  guard m.get("info") is Some(Object(info)) else {
    fail("info should be present")
  }
  assert_eq(info.get("description"), Some(Json("qwq api")))
  guard info.get("contact") is Some(Object(c)) else {
    fail("contact should be present")
  }
  assert_eq(c.get("name"), Some(Json("heke1228")))
  assert_eq(c.get("email"), Some(Json("emm@qq.com")))
  // An empty contact field is omitted, not emitted as "".
  assert_eq(c.get("url"), None)
  guard info.get("license") is Some(Object(l)) else {
    fail("license should be present")
  }
  assert_eq(l.get("name"), Some(Json("Apache-2.0")))
  guard m.get("servers") is Some(Array(sv)) else {
    fail("servers should be present")
  }
  assert_eq(sv.length(), 1)
  guard sv[0] is Object(s0) else { fail("server should be an object") }
  assert_eq(s0.get("url"), Some(Json("https://api.example.com")))
}

///|
/// A path parameter's `name` has to correspond to a template expression in the path
/// key, or the document is invalid and Swagger UI has nothing to substitute into.
/// The router keeps its own `:id` syntax; only the emitted document is templated.
test "openapi keys paths by their template form" {
  let app = App::new()
  app.get("/users/:id/posts/:slug", _ctx => @status.text(200, "hhh"))
  let doc = app.openapi()
  let keys = match doc {
    Object(m) =>
      match m.get("paths") {
        Some(Object(p)) => p.keys().collect()
        _ => []
      }
    _ => []
  }
  assert_eq(keys, ["/users/{id}/posts/{slug}"])
  // The route itself still matches the request as written.
  assert_eq(app.handle(mkreq("GET", "/users/42/posts/qwq")).status, 200)
}

///|
test "nullable: each dialect says it its own way" {
  let app = body_app(
    @schema.Schema::object("Note", [
      @schema.Field::new("title", @schema.Schema::nullable(SStr)),
    ]),
  )
  // 3.1 is JSON-Schema 2020-12: the type itself becomes a list.
  let new = dig(app.openapi(version=OpenApi31), [
    "components", "schemas", "Note", "properties", "title",
  ]).unwrap()
  assert_eq(dig(new, ["type"]).unwrap(), Json([Json("string"), Json("null")]))
  // 3.0 has the `nullable` flag.
  let mid = dig(app.openapi(version=OpenApi30), [
    "components", "schemas", "Note", "properties", "title",
  ]).unwrap()
  assert_eq(json_str(mid, "type"), "string")
  assert_eq(dig(mid, ["nullable"]), Some(Json(true)))
  // 2.0 has nothing in the specification proper, so it uses the extension its
  // tooling reads.
  let old = dig(app.openapi(version=Swagger20), [
    "definitions", "Note", "properties", "title",
  ]).unwrap()
  assert_eq(dig(old, ["x-nullable"]), Some(Json(true)))
}

///|
test "nullable: a composite with no type to widen becomes an anyOf in 3.1" {
  let inner = @schema.Schema::object("Addr", [@schema.Field::new("city", SStr)])
  let app = body_app(
    @schema.Schema::object("Person", [
      @schema.Field::new("addr", @schema.Schema::nullable(inner)),
    ]),
  )
  let doc = app.openapi(version=OpenApi31)
  let f = dig(doc, ["components", "schemas", "Person", "properties", "addr"]).unwrap()
  let branches = dig_arr(f, ["anyOf"])
  assert_eq(branches.length(), 2)
  assert_eq(json_str(branches[0], "$ref"), "#/components/schemas/Addr")
  assert_eq(json_str(branches[1], "type"), "null")
  // The referenced object was still hoisted.
  assert_eq(
    json_str(dig(doc, ["components", "schemas", "Addr"]).unwrap(), "type"),
    "object",
  )
}

///|
test "format: a binary upload is a string that says what it holds" {
  let app = body_app(
    @schema.Schema::object("Upload", [
      @schema.Field::new("file", @schema.Schema::binary()),
      @schema.Field::new("when", @schema.Schema::format(SStr, "date-time")),
    ]),
  )
  let props = dig(app.openapi(version=OpenApi31), [
    "components", "schemas", "Upload", "properties",
  ]).unwrap()
  let file = dig(props, ["file"]).unwrap()
  assert_eq(json_str(file, "type"), "string")
  assert_eq(json_str(file, "format"), "binary")
  assert_eq(json_str(dig(props, ["when"]).unwrap(), "format"), "date-time")
  // A format refines meaning, never type: the base is what is checked.
  assert_eq(
    post_body(app, "{\"file\":\"AAA\",\"when\":\"whenever\"}").status,
    200,
  )
  let bad = post_body(app, "{\"file\":5,\"when\":\"now\"}")
  assert_eq(bad.status, 422)
  assert_eq(json_str(detail0(bad), "type"), "string_type")
}

///|
test "field default: emitted, and the field is no longer required" {
  let app = body_app(
    @schema.Schema::object("Page", [
      @schema.Field::new("size", SInt, default=Json(20)),
      @schema.Field::new("q", SStr),
    ]),
  )
  let model = dig(app.openapi(version=OpenApi31), [
    "components", "schemas", "Page",
  ]).unwrap()
  assert_eq(dig(model, ["properties", "size", "default"]), Some(Json(20)))
  // A field that has a default is never missing, so it is out of `required`.
  let req : Array[String] = []
  for v in dig_arr(model, ["required"]) {
    if v is String(s) {
      req.push(s)
    }
  }
  assert_eq(req, ["q"])
  assert_eq(post_body(app, "{\"q\":\"cats\"}").status, 200)
  // Supplied, it is still type-checked.
  let bad = post_body(app, "{\"q\":\"cats\",\"size\":\"big\"}")
  assert_eq(bad.status, 422)
  assert_eq(json_str(detail0(bad), "type"), "int_type")
}

///|
test "openapi 3.1: request body is a typed $ref into components/schemas" {
  let app = demo_app()
  let doc = app.openapi(version=OpenApi31)
  // POST /users requestBody -> application/json -> schema -> $ref NewUser
  let sch = dig(doc, [
    "paths", "/users", "post", "requestBody", "content", "application/json", "schema",
  ]).unwrap()
  assert_eq(json_str(sch, "$ref"), "#/components/schemas/NewUser")
  // The endpoint's requestBody is required by default.
  assert_eq(
    dig(doc, ["paths", "/users", "post", "requestBody", "required"]).unwrap(),
    Json(true),
  )
}

///|
test "openapi 3.1: response body is a typed $ref, with full component schemas" {
  let app = demo_app()
  let doc = app.openapi(version=OpenApi31)
  let ok = dig(doc, [
    "paths", "/users", "post", "responses", "201", "content", "application/json",
    "schema",
  ]).unwrap()
  assert_eq(json_str(ok, "$ref"), "#/components/schemas/User")
  // components/schemas holds User, NewUser AND the transitively-referenced
  // Address — the whole tree was hoisted, not just the top level.
  let user = dig(doc, ["components", "schemas", "User"]).unwrap()
  assert_eq(json_str(user, "type"), "object")
  // User.address is a $ref to Address (nested object hoisted + referenced).
  let addr = dig(user, ["properties", "address"]).unwrap()
  assert_eq(json_str(addr, "$ref"), "#/components/schemas/Address")
  // User.tags is an array of strings.
  let tags = dig(user, ["properties", "tags"]).unwrap()
  assert_eq(json_str(tags, "type"), "array")
  assert_eq(json_str(dig(tags, ["items"]).unwrap(), "type"), "string")
  // Address itself is present under components/schemas.
  assert_eq(
    json_str(dig(doc, ["components", "schemas", "Address"]).unwrap(), "type"),
    "object",
  )
  // NewUser.required lists the mandatory fields but not the optional `age`.
  let req = dig_arr(doc, ["components", "schemas", "NewUser", "required"])
  let names : Array[String] = []
  for v in req {
    match v {
      String(s) => names.push(s)
      _ => ()
    }
  }
  assert_eq(names.contains("name"), true)
  assert_eq(names.contains("email"), true)
  assert_eq(names.contains("age"), false)
}

///|
test "openapi 3.1: typed path parameter carries an integer schema" {
  let app = demo_app()
  let doc = app.openapi(version=OpenApi31)
  // The document keys paths by OpenAPI's template form, not the router's `:id`.
  let params = dig_arr(doc, ["paths", "/users/{id}", "get", "parameters"])
  assert_eq(params.length(), 1)
  assert_eq(json_str(params[0], "name"), "id")
  assert_eq(json_str(params[0], "in"), "path")
  assert_eq(json_str(dig(params[0], ["schema"]).unwrap(), "type"), "integer")
  // The 200 response body is a User $ref.
  let ok = dig(doc, [
    "paths", "/users/{id}", "get", "responses", "200", "content", "application/json",
    "schema",
  ]).unwrap()
  assert_eq(json_str(ok, "$ref"), "#/components/schemas/User")
}

///|
test "swagger 2.0: body parameter + definitions instead of components" {
  let app = demo_app()
  let doc = app.openapi(version=Swagger20)
  // Body arrives as an in:body parameter whose schema $refs #/definitions/*.
  let params = dig_arr(doc, ["paths", "/users", "post", "parameters"])
  let mut body_ref = ""
  for p in params {
    if json_str(p, "in") == "body" {
      body_ref = json_str(dig(p, ["schema"]).unwrap(), "$ref")
    }
  }
  assert_eq(body_ref, "#/definitions/NewUser")
  // Named schemas live under top-level `definitions`, not `components`.
  assert_eq(dig(doc, ["definitions", "NewUser"]) is Some(_), true)
  assert_eq(dig(doc, ["components"]) is None, true)
}

///|
test "openapi 3.1: enum schema keeps its base type and carries the value set" {
  let doc = enum_app().openapi(version=OpenApi31)
  let status = dig(doc, [
    "components", "schemas", "Order", "properties", "status",
  ]).unwrap()
  // FastAPI emits {"type":"string","enum":[...]} — the base type stays alongside.
  assert_eq(json_str(status, "type"), "string")
  assert_eq(dig(status, ["enum"]).unwrap(), Json([Json("qwq"), Json("hhh")]))
}

///|
test "api key: the scheme is documented in every dialect" {
  let app = guarded("Key")
  app.secure_api_key(
    "Key",
    @security.ApiKey::header("x-api-key", _k => true),
    description="the key issued to you",
  )
  let doc = app.openapi(version=OpenApi31)
  let s = dig(doc, ["components", "securitySchemes", "Key"]).unwrap()
  assert_eq(json_str(s, "type"), "apiKey")
  assert_eq(json_str(s, "in"), "header")
  assert_eq(json_str(s, "name"), "x-api-key")
  assert_eq(json_str(s, "description"), "the key issued to you")
  // Swagger 2.0 says apiKey the same way.
  let old = app.openapi(version=Swagger20)
  assert_eq(
    json_str(dig(old, ["securityDefinitions", "Key"]).unwrap(), "type"),
    "apiKey",
  )
}

///|
test "api key: a cookie key degrades to a header in Swagger 2.0" {
  let app = guarded("Key")
  app.secure_api_key("Key", @security.ApiKey::cookie("session", _k => true))
  // 3.x can say `in: cookie`.
  assert_eq(
    json_str(
      dig(app.openapi(version=OpenApi30), [
        "components", "securitySchemes", "Key",
      ]).unwrap(),
      "in",
    ),
    "cookie",
  )
  // 2.0 has only header/query, so it says header — the standard workaround.
  assert_eq(
    json_str(
      dig(app.openapi(version=Swagger20), ["securityDefinitions", "Key"]).unwrap(),
      "in",
    ),
    "header",
  )
}

///|
test "http basic: documented as http/basic in 3.x and type basic in 2.0" {
  let app = guarded("Basic")
  app.secure_basic("Basic", @security.BasicAuth::new(_c => true))
  let s = dig(app.openapi(version=OpenApi31), [
    "components", "securitySchemes", "Basic",
  ]).unwrap()
  assert_eq(json_str(s, "type"), "http")
  assert_eq(json_str(s, "scheme"), "basic")
  assert_eq(
    json_str(
      dig(app.openapi(version=Swagger20), ["securityDefinitions", "Basic"]).unwrap(),
      "type",
    ),
    "basic",
  )
}

///|
test "http digest: the credential parameters reach the app's own check" {
  let seen : Array[String] = []
  let app = guarded("Digest")
  app.secure_digest(
    "Digest",
    @security.DigestAuth::new(
      params => {
        seen.push(params)
        params.contains("response=\"deadbeef\"")
      },
      realm="vault",
    ),
  )
  assert_eq(app.handle(mkreq("GET", "/vault")).status, 403)
  let bad = app.handle(mkreq_auth("GET", "/vault", "Digest response=\"no\""))
  assert_eq(bad.status, 403)
  let ok = app.handle(
    mkreq_auth(
      "GET", "/vault", "Digest username=\"ada\", response=\"deadbeef\"",
    ),
  )
  assert_eq(ok.status, 200)
  // The scheme name is stripped and the parameters handed over verbatim.
  assert_eq(seen[0], "response=\"no\"")
  assert_eq(seen[1], "username=\"ada\", response=\"deadbeef\"")
  assert_eq(
    json_str(
      dig(app.openapi(version=OpenApi31), [
        "components", "securitySchemes", "Digest",
      ]).unwrap(),
      "scheme",
    ),
    "digest",
  )
  // Digest takes the same 2.0 workaround a bearer scheme does.
  assert_eq(
    json_str(
      dig(app.openapi(version=Swagger20), ["securityDefinitions", "Digest"]).unwrap(),
      "name",
    ),
    "Authorization",
  )
}

///|
test "oauth2 code: the document describes the redirect, the guard checks the token" {
  let app = guarded("Code")
  let code = @security.OAuth2CodeBearer::new(
    "https://id.example/authorize",
    "https://id.example/token",
    "s3cret",
    refresh_url="https://id.example/refresh",
  )
  app.secure_oauth2_code("Code", code, scopes=[("read", "read things")])
  let flow = dig(app.openapi(version=OpenApi31), [
    "components", "securitySchemes", "Code", "flows", "authorizationCode",
  ]).unwrap()
  assert_eq(json_str(flow, "authorizationUrl"), "https://id.example/authorize")
  assert_eq(json_str(flow, "tokenUrl"), "https://id.example/token")
  assert_eq(json_str(flow, "refreshUrl"), "https://id.example/refresh")
  assert_eq(json_str(dig(flow, ["scopes"]).unwrap(), "read"), "read things")
  // Swagger 2.0 calls the same flow `accessCode` and flattens it.
  let old = dig(app.openapi(version=Swagger20), ["securityDefinitions", "Code"]).unwrap()
  assert_eq(json_str(old, "flow"), "accessCode")
  assert_eq(json_str(old, "authorizationUrl"), "https://id.example/authorize")
  // And the credential it produces is checked like any other bearer token.
  assert_eq(app.handle(mkreq("GET", "/vault")).status, 401)
  let token = @security.create_access_token("ada", "s3cret", 1000L)
  assert_eq(
    app.handle(mkreq_auth("GET", "/vault", "Bearer " + token)).status,
    200,
  )
}

///|
test "openid connect: described in 3.x, absent from a 2.0 document" {
  let app = guarded("Oidc")
  app.secure_openid(
    "Oidc", "https://id.example/.well-known/openid-configuration", "s3cret",
  )
  let s = dig(app.openapi(version=OpenApi31), [
    "components", "securitySchemes", "Oidc",
  ]).unwrap()
  assert_eq(json_str(s, "type"), "openIdConnect")
  assert_eq(
    json_str(s, "openIdConnectUrl"),
    "https://id.example/.well-known/openid-configuration",
  )
  // 2.0 cannot say `openIdConnect`, and inventing something else would describe
  // an API that does not exist — so the whole (now empty) section is dropped.
  let old = app.openapi(version=Swagger20)
  assert_eq(dig(old, ["securityDefinitions"]) is None, true)
  // The guard is wired all the same.
  assert_eq(app.handle(mkreq("GET", "/vault")).status, 401)
  let token = @security.create_access_token("ada", "s3cret", 1000L)
  assert_eq(
    app.handle(mkreq_auth("GET", "/vault", "Bearer " + token)).status,
    200,
  )
}
