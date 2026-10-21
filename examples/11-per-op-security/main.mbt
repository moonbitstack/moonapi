///|
/// Per-operation security: a route declares `security=[SecurityRequirement]` and
/// the app enforces it *before* the handler. `App::secure_oauth2` both surfaces
/// the scheme in the spec (with its advertised scopes) and registers the guard;
/// `App::set_clock` gives the app the verification time. A request with no token
/// is `401`, a valid token missing the scope is `403`, and the handler only runs
/// once the guard passes — and the requirement is emitted as the operation's
/// OpenAPI `security` array off the same declaration.
///
///     moon run examples/11-per-op-security
#coverage.skip
fn main {
  let secret = "heke1228-signing-secret"
  let bearer = @moonapi.OAuth2PasswordBearer::new("/token", secret)
  let now = 1_700_000_000L
  let app = @moonapi.App::new()
  app.set_clock(() => now)
  app.secure_oauth2("OAuth2", bearer, scopes=[
    ("items:read", "read items"),
    ("items:write", "write items"),
  ])
  // The handler is never reached unless the guard admits the request.
  app.get(
    "/items",
    _ctx => @moonapi.text(200, "the item list"),
    summary="list items",
    security=[
      @moonapi.SecurityRequirement::new("OAuth2", scopes=["items:read"]),
    ],
  )
  let good = @moonapi.create_access_token("lfanke", secret, now, scopes=[
    "items:read",
  ])
  let weak = @moonapi.create_access_token("lfanke", secret, now, scopes=[
    "profile",
  ])
  let hit = (label : String, headers : Array[(String, String)]) => {
    let req : @moonasgi.Request = {
      http_method: "GET",
      path: "/items",
      query_string: b"",
      headers,
      body: b"",
    }
    let r = app.handle(req)
    println(
      "GET /items \{label} -> \{r.status} \{@utf8.decode_lossy(r.body[:])}",
    )
  }
  hit("(no token)", [])
  hit("(items:read)", [("authorization", "Bearer " + good)])
  hit("(profile only)", [("authorization", "Bearer " + weak)])
  println("--- OpenAPI 3.1.0 (operation security + securitySchemes) ---")
  println(app.openapi_json(version=OpenApi31))
}
