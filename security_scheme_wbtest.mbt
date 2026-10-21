///|
/// Reach `components.securitySchemes.<name>` in a 3.x document.
fn scheme_3x(doc : Json, name : String) -> Json {
  match doc {
    Object(m) =>
      match m.get("components") {
        Some(Object(c)) =>
          match c.get("securitySchemes") {
            Some(Object(s)) => s.get(name).unwrap_or(Json(false))
            _ => Json(false)
          }
        _ => Json(false)
      }
    _ => Json(false)
  }
}

///|
/// Reach `securityDefinitions.<name>` in a Swagger 2.0 document.
fn scheme_20(doc : Json, name : String) -> Json {
  match doc {
    Object(m) =>
      match m.get("securityDefinitions") {
        Some(Object(s)) => s.get(name).unwrap_or(Json(false))
        _ => Json(false)
      }
    _ => Json(false)
  }
}

///|
test "securityScheme: OAuth2 password flow in OpenAPI 3.1" {
  let app = App::new()
  let bearer = @security.OAuth2PasswordBearer::new("token", "secret")
  app.add_security_scheme(
    "OAuth2PasswordBearer",
    bearer.scheme(scopes=[("items", "read and write items")]),
  )
  app.post("/token", _ctx => @status.text(200, "t"))
  let doc = app.openapi(version=OpenApi31)
  let sch = scheme_3x(doc, "OAuth2PasswordBearer")
  assert_eq(json_str(sch, "type"), "oauth2")
  let token_url = match sch {
    Object(m) =>
      match m.get("flows") {
        Some(Object(f)) =>
          match f.get("password") {
            Some(Object(p)) => json_str(Json(p), "tokenUrl")
            _ => ""
          }
        _ => ""
      }
    _ => ""
  }
  assert_eq(token_url, "token")
}

///|
test "securityScheme: OAuth2 flattens to the Swagger 2.0 shape" {
  let app = App::new()
  app.add_security_scheme(
    "OAuth2PasswordBearer",
    OAuth2Password(token_url="token", scopes=[("items", "manage items")]),
  )
  app.post("/token", _ctx => @status.text(200, "t"))
  let doc = app.openapi(version=Swagger20)
  let sch = scheme_20(doc, "OAuth2PasswordBearer")
  assert_eq(json_str(sch, "type"), "oauth2")
  assert_eq(json_str(sch, "flow"), "password")
  assert_eq(json_str(sch, "tokenUrl"), "token")
}

///|
test "securityScheme: HTTP bearer names its JWT format in 3.x" {
  let app = App::new()
  app.add_security_scheme("BearerAuth", HttpBearer(bearer_format="JWT"))
  app.get("/me", _ctx => @status.text(200, "me"))
  let sch = scheme_3x(app.openapi(version=OpenApi30), "BearerAuth")
  assert_eq(json_str(sch, "type"), "http")
  assert_eq(json_str(sch, "scheme"), "bearer")
  assert_eq(json_str(sch, "bearerFormat"), "JWT")
}

///|
test "securityScheme: HTTP bearer degrades to an apiKey in Swagger 2.0" {
  let app = App::new()
  app.add_security_scheme("BearerAuth", HttpBearer(bearer_format="JWT"))
  app.get("/me", _ctx => @status.text(200, "me"))
  let sch = scheme_20(app.openapi(version=Swagger20), "BearerAuth")
  assert_eq(json_str(sch, "type"), "apiKey")
  assert_eq(json_str(sch, "in"), "header")
  assert_eq(json_str(sch, "name"), "Authorization")
}

///|
test "securityScheme: an API key in a header" {
  let app = App::new()
  app.add_security_scheme("ApiKey", ApiKeyHeader(name="X-API-Key"))
  app.get("/me", _ctx => @status.text(200, "me"))
  let sch = scheme_3x(app.openapi(version=OpenApi31), "ApiKey")
  assert_eq(json_str(sch, "type"), "apiKey")
  assert_eq(json_str(sch, "in"), "header")
  assert_eq(json_str(sch, "name"), "X-API-Key")
}

///|
test "securityScheme: schemas and securitySchemes share components in 3.x" {
  let app = App::new()
  app.add_security_scheme("BearerAuth", HttpBearer(bearer_format="JWT"))
  app.get("/me", _ctx => @status.text(200, "me"))
  // No component schemas here, so components holds only securitySchemes.
  let doc = app.openapi(version=OpenApi31)
  let has = match doc {
    Object(m) =>
      match m.get("components") {
        Some(Object(c)) => c.get("securitySchemes") is Some(_)
        _ => false
      }
    _ => false
  }
  assert_eq(has, true)
}
