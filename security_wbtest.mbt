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
