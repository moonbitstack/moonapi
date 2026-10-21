// The enforcement half of the security schemes: every shape a route can declare
// is both described in the document and stood in front of the handler.

///|
/// A request carrying arbitrary `headers`, and optionally a query string —
/// test helper.
fn mkreq_hdrs(
  verb : String,
  path : String,
  headers : Array[(String, String)],
  query~ : Bytes = b"",
) -> @moonasgi.Request {
  { http_method: verb, path, query_string: query, headers, body: b"", }
}

///|
/// The `detail` string of a refusal body — test helper.
fn detail_str(r : @moonasgi.Response) -> String {
  json_str(resp_json(r), "detail")
}

///|
/// An app with one guarded `GET /vault` behind the scheme `name` — test helper.
fn guarded(name : String) -> App {
  let app = App::new()
  app.set_clock(() => 1000L)
  app.get("/vault", _ctx => @status.text(200, "gold"), security=[
    @security.SecurityRequirement::new(name),
  ])
  app
}

///|
test "api key: a header route refuses a missing key and admits a valid one" {
  let app = guarded("Key")
  app.secure_api_key(
    "Key",
    @security.ApiKey::header("x-api-key", k => k == "s3cret"),
  )
  // No key at all.
  let anon = app.handle(mkreq("GET", "/vault"))
  assert_eq(anon.status, 403)
  assert_eq(detail_str(anon), "Not authenticated")
  // A key the scheme does not accept.
  let wrong = app.handle(mkreq_hdrs("GET", "/vault", [("x-api-key", "guess")]))
  assert_eq(wrong.status, 403)
  assert_eq(detail_str(wrong), "Invalid authentication credentials")
  // The real thing.
  let ok = app.handle(mkreq_hdrs("GET", "/vault", [("x-api-key", "s3cret")]))
  assert_eq(ok.status, 200)
  assert_eq(ok.body, @utf8.encode("gold"))
}

///|
test "api key: the header name is matched case-insensitively" {
  let app = guarded("Key")
  app.secure_api_key(
    "Key",
    @security.ApiKey::header("X-Api-Key", k => k == "s3cret"),
  )
  assert_eq(
    app.handle(mkreq_hdrs("GET", "/vault", [("x-api-key", "s3cret")])).status,
    200,
  )
}

///|
test "api key: a query key and a cookie key are read from their own places" {
  let q = guarded("Key")
  q.secure_api_key("Key", @security.ApiKey::query("token", k => k == "s3cret"))
  assert_eq(q.handle(mkreq("GET", "/vault")).status, 403)
  assert_eq(
    q.handle(mkreq_hdrs("GET", "/vault", [], query=b"token=s3cret")).status,
    200,
  )
  let c = guarded("Key")
  c.secure_api_key(
    "Key",
    @security.ApiKey::cookie("session", k => k == "s3cret"),
  )
  assert_eq(c.handle(mkreq("GET", "/vault")).status, 403)
  assert_eq(
    c.handle(mkreq_hdrs("GET", "/vault", [("cookie", "a=1; session=s3cret")])).status,
    200,
  )
}

///|
test "api key: auto_error=false lets the route decide instead of refusing" {
  let app = guarded("Key")
  app.secure_api_key(
    "Key",
    @security.ApiKey::header("x-api-key", k => k == "s3cret"),
    auto_error=false,
  )
  // The guard admits the anonymous caller; the handler still runs.
  assert_eq(app.handle(mkreq("GET", "/vault")).status, 200)
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
test "http basic: refused without credentials, admitted with the right pair" {
  let app = guarded("Basic")
  app.secure_basic(
    "Basic",
    @security.BasicAuth::new(
      c => c.username == "ada" && c.password == "lovelace",
      realm="vault",
    ),
  )
  let anon = app.handle(mkreq("GET", "/vault"))
  assert_eq(anon.status, 401)
  // RFC 9110 §15.5.2: a 401 has to say how to authenticate.
  assert_eq(anon.header("www-authenticate"), Some("Basic realm=\"vault\""))
  assert_eq(detail_str(anon), "Not authenticated")
  // base64("ada:wrong") / base64("ada:lovelace")
  let bad = app.handle(mkreq_auth("GET", "/vault", "Basic YWRhOndyb25n"))
  assert_eq(bad.status, 401)
  assert_eq(detail_str(bad), "Incorrect username or password")
  let ok = app.handle(mkreq_auth("GET", "/vault", "Basic YWRhOmxvdmVsYWNl"))
  assert_eq(ok.status, 200)
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
test "http digest: the scheme name is matched case-insensitively, others ignored" {
  let ctx : @ctx.Context = {
    request: mkreq_hdrs("GET", "/x", [("authorization", "DIGEST nc=00000001")]),
    params: Map([]),
  }
  assert_eq(ctx.digest_credentials(), Some("nc=00000001"))
  let bearer : @ctx.Context = {
    request: mkreq_hdrs("GET", "/x", [("authorization", "Bearer abc")]),
    params: Map([]),
  }
  assert_eq(bearer.digest_credentials() is None, true)
}

///|
test "http bearer: a plain bearer scheme verifies the token and its scopes" {
  let app = App::new()
  app.set_clock(() => 1000L)
  app.secure_bearer("Bearer", "s3cret")
  app.get("/vault", _ctx => @status.text(200, "gold"), security=[
    @security.SecurityRequirement::new("Bearer", scopes=["read"]),
  ])
  let good = @security.create_access_token("ada", "s3cret", 1000L, scopes=[
    "read",
  ])
  assert_eq(
    app.handle(mkreq_auth("GET", "/vault", "Bearer " + good)).status,
    200,
  )
  let narrow = @security.create_access_token("ada", "s3cret", 1000L, scopes=[
    "write",
  ])
  assert_eq(
    app.handle(mkreq_auth("GET", "/vault", "Bearer " + narrow)).status,
    403,
  )
  let anon = app.handle(mkreq("GET", "/vault"))
  assert_eq(anon.status, 401)
  assert_eq(anon.header("www-authenticate"), Some("Bearer scope=\"read\""))
  let s = dig(app.openapi(version=OpenApi31), [
    "components", "securitySchemes", "Bearer",
  ]).unwrap()
  assert_eq(json_str(s, "type"), "http")
  assert_eq(json_str(s, "scheme"), "bearer")
  assert_eq(json_str(s, "bearerFormat"), "JWT")
  // 2.0 has no `http` type at all, so a bearer scheme becomes the standard
  // workaround: an apiKey in the `Authorization` header.
  let old = dig(app.openapi(version=Swagger20), [
    "securityDefinitions", "Bearer",
  ]).unwrap()
  assert_eq(json_str(old, "type"), "apiKey")
  assert_eq(json_str(old, "name"), "Authorization")
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
test "oauth2 code: an absent refresh endpoint is not described as existing" {
  let app = guarded("Code")
  app.secure_oauth2_code(
    "Code",
    @security.OAuth2CodeBearer::new("https://id/a", "https://id/t", "s3cret"),
  )
  let flow = dig(app.openapi(version=OpenApi31), [
    "components", "securitySchemes", "Code", "flows", "authorizationCode",
  ]).unwrap()
  assert_eq(dig(flow, ["refreshUrl"]) is None, true)
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

///|
test "declared-only scheme: documented, and honestly unguarded" {
  let app = guarded("Key")
  app.add_security_scheme(
    "Key",
    ApiKeyHeader(name="x-api-key"),
    description="declared, never wired",
  )
  let s = dig(app.openapi(version=OpenApi31), [
    "components", "securitySchemes", "Key",
  ]).unwrap()
  assert_eq(json_str(s, "description"), "declared, never wired")
  // No enforcer, so the route is documented as protected and left open — the
  // same split FastAPI draws between a declared scheme and a wired dependency.
  assert_eq(app.handle(mkreq("GET", "/vault")).status, 200)
}

///|
test "security scopes: what a guard is told the route required" {
  let none = @security.SecurityScopes::new()
  assert_eq(none.list(), [])
  assert_eq(none.scope_str(), "")
  assert_eq(none.challenge(), "Bearer")
  let some = @security.SecurityScopes::new(scopes=["read", "write"])
  assert_eq(some.list(), ["read", "write"])
  assert_eq(some.scope_str(), "read write")
  assert_eq(some.challenge(), "Bearer scope=\"read write\"")
}
