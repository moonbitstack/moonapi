///|
/// The non-OAuth2 security schemes: declaring them for the document, and pulling
/// their credentials off a request. `add_security_scheme` surfaces every
/// `SecurityScheme` variant — HTTP bearer, API key in header / query / cookie,
/// HTTP Basic, and the OAuth2 password flow via `OAuth2PasswordBearer::scheme` —
/// under `securitySchemes` (3.x) or `securityDefinitions` (2.0). The extractors
/// `api_key_header` / `api_key_query` / `api_key_cookie` and `http_basic`
/// (`parse_basic_auth` under it) are the enforcement side a route reads.
///
///     moon run src/examples/12-security-schemes
#coverage.skip
async fn main {
  let app = @moonapi.App::new()
  app.add_security_scheme("BearerJWT", HttpBearer(bearer_format="JWT"))
  app.add_security_scheme("ApiKeyHeader", ApiKeyHeader(name="X-API-Key"))
  app.add_security_scheme("ApiKeyQuery", ApiKeyQuery(name="api_key"))
  app.add_security_scheme("ApiKeyCookie", ApiKeyCookie(name="session"))
  app.add_security_scheme("Basic", HttpBasic)
  let bearer = @moonapi.OAuth2PasswordBearer::new("/token", "heke1228")
  app.add_security_scheme(
    "OAuth2",
    bearer.scheme(scopes=[("read", "read access"), ("write", "write access")]),
  )

  // The extraction side: one route reads a credential from each carrier.
  app.get("/whoami", ctx => {
    let h = ctx.api_key_header("X-API-Key").unwrap_or("-")
    let q = ctx.api_key_query("api_key").unwrap_or("-")
    let c = ctx.api_key_cookie("session").unwrap_or("-")
    let who = match ctx.http_basic() {
      Some(cred) => "\{cred.username}:\{cred.password}"
      None => "-"
    }
    @moonapi.text(200, "header=\{h} query=\{q} cookie=\{c} basic=\{who}")
  })
  let basic = "Basic " + @base64.encode(@utf8.encode("lfanke:heke1228")[:])
  let req : @moonasgi.Request = {
    http_method: "GET",
    path: "/whoami",
    query_string: @utf8.encode("api_key=qwe"),
    headers: [
      ("x-api-key", "233"),
      ("cookie", "session=heke1228; theme=dark"),
      ("authorization", basic),
    ],
    body: b"",
  }
  let r = app.handle(req)
  println("GET /whoami -> \{r.status} \{@utf8.decode_lossy(r.body[:])}")

  // parse_basic_auth splits on the first colon, so a password may contain colons.
  let cred = @moonapi.parse_basic_auth(
    "Basic " + @base64.encode(@utf8.encode("qwq:a:b:c")[:]),
  )
  match cred {
    Some(c) =>
      println("parse_basic_auth -> user=\{c.username} pass=\{c.password}")
    None => println("parse_basic_auth -> none")
  }
  println("--- Swagger 2.0 (securityDefinitions) ---")
  println(app.openapi_json(version=Swagger20))
  println("--- OpenAPI 3.1.0 (securitySchemes) ---")
  println(app.openapi_json(version=OpenApi31))
}
