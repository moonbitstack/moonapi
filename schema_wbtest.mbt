///|
/// Get an object field by key, `None` if not an object or absent — test helper.
fn obj_get(j : Json, k : String) -> Json? {
  match j {
    Object(m) => m.get(k)
    _ => None
  }
}

///|
/// Walk a chain of object keys into a JSON document — test helper.
fn dig(j : Json, path : Array[String]) -> Json? {
  let mut cur : Json? = Some(j)
  for k in path {
    cur = match cur {
      Some(x) => obj_get(x, k)
      None => None
    }
  }
  cur
}

///|
/// The array at `path`, empty if absent or not an array — test helper.
fn dig_arr(j : Json, path : Array[String]) -> Array[Json] {
  match dig(j, path) {
    Some(Array(a)) => a
    _ => []
  }
}

///|
/// Parse a response body back into JSON — test helper.
fn resp_json(r : @moonasgi.Response) -> Json {
  @json.parse(@utf8.decode_lossy(r.body[:])) catch {
    _ => Json::null()
  }
}

///|
/// The first `detail[]` entry of a 422 body — test helper.
fn detail0(r : @moonasgi.Response) -> Json {
  match resp_json(r) {
    Object(m) =>
      match m.get("detail") {
        Some(Array(a)) => if a.length() > 0 { a[0] } else { Json::null() }
        _ => Json::null()
      }
    _ => Json::null()
  }
}

///|
/// The `loc` of a validation-error JSON object as a list of strings — helper.
fn err_loc(e : Json) -> Array[String] {
  let out : Array[String] = []
  match obj_get(e, "loc") {
    Some(Array(a)) =>
      for v in a {
        match v {
          String(s) => out.push(s)
          _ => ()
        }
      }
    _ => ()
  }
  out
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
    true.to_json(),
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
test "descriptor-driven validation: valid body passes, returns typed User" {
  let app = demo_app()
  let ok = app.handle(
    mkreq_full(
      "POST",
      "/users",
      body=@utf8.encode("{\"name\":\"ada\",\"email\":\"a@b.c\",\"age\":36}"),
    ),
  )
  assert_eq(ok.status, 201)
  // Response really is a serialised User (derive(ToJson) round trip).
  assert_eq(json_str(resp_json(ok), "name"), "ada")
  let addr = dig(resp_json(ok), ["address"]).unwrap()
  assert_eq(json_str(addr, "city"), "Nowhere")
}

///|
test "descriptor-driven validation: missing required field -> located 422" {
  let app = demo_app()
  let miss = app.handle(
    mkreq_full("POST", "/users", body=@utf8.encode("{\"email\":\"a@b.c\"}")),
  )
  assert_eq(miss.status, 422)
  let e = detail0(miss)
  assert_eq(json_str(e, "type"), "missing")
  assert_eq(err_loc(e), ["body", "name"])
}

///|
test "descriptor-driven validation: wrong body field type -> located 422" {
  let app = demo_app()
  let bad = app.handle(
    mkreq_full(
      "POST",
      "/users",
      body=@utf8.encode("{\"name\":\"x\",\"email\":\"y\",\"age\":\"NaN\"}"),
    ),
  )
  assert_eq(bad.status, 422)
  let e = detail0(bad)
  assert_eq(json_str(e, "type"), "int_type")
  assert_eq(err_loc(e), ["body", "age"])
}

///|
test "descriptor-driven validation: unparseable path param -> located 422" {
  let app = demo_app()
  let bad = app.handle(mkreq_full("GET", "/users/not-a-number"))
  assert_eq(bad.status, 422)
  let e = detail0(bad)
  assert_eq(json_str(e, "type"), "int_parsing")
  assert_eq(err_loc(e), ["path", "id"])
  // A well-formed integer id passes and returns a User.
  let ok = app.handle(mkreq_full("GET", "/users/7"))
  assert_eq(ok.status, 200)
  assert_eq(dig(resp_json(ok), ["id"]).unwrap(), (7).to_json())
}

///|
test "cookie extraction off the Cookie header" {
  let req : @moonasgi.Request = {
    http_method: "GET",
    path: "/",
    query_string: b"",
    headers: [("cookie", "session=abc123; theme=dark")],
    body: b"",
  }
  let ctx : Context = { request: req, params: Map([]), }
  assert_eq(ctx.cookie("session"), Some("abc123"))
  assert_eq(ctx.cookie("theme"), Some("dark"))
  assert_eq(ctx.cookie("absent"), None)
}

///|
test "schema descriptor validates a nested tree directly" {
  let errs : Array[ValidationError] = []
  // A User body with a wrong-typed nested field and a bad array element.
  let bad = @json.parse(
    "{\"id\":1,\"name\":\"x\",\"address\":{\"city\":\"c\",\"zip\":5},\"tags\":[\"ok\",9]}",
  ) catch {
    _ => Json::null()
  }
  validate_schema(User::schema(), bad, ["body"], errs)
  // zip should be a string, tags[1] should be a string -> two errors located.
  assert_eq(errs.length(), 2)
}

///|
/// A typed route whose body carries an enum field (← a Python `Enum` /
/// `typing.Literal`): its OpenAPI schema advertises the closed value set and its
/// validation enforces membership.
fn enum_app() -> App {
  let body = Schema::object("Order", [
    Field::new("status", SEnum(SStr, ["qwq".to_json(), "hhh".to_json()])),
  ])
  let ep = Endpoint::new(request_body=body, responses=[
    ResponseSpec::new(200, body~),
  ])
  let app = App::new()
  app.post(
    "/orders",
    ctx => {
      let errs = ep.validate(ctx)
      if errs.length() > 0 {
        unprocessable(errs)
      } else {
        json(200, ctx.body_json().unwrap_or(Json::null()))
      }
    },
    endpoint=ep,
  )
  app
}

///|
test "openapi 3.1: enum schema keeps its base type and carries the value set" {
  let doc = enum_app().openapi(version=OpenApi31)
  let status = dig(doc, [
    "components", "schemas", "Order", "properties", "status",
  ]).unwrap()
  // FastAPI emits {"type":"string","enum":[...]} — the base type stays alongside.
  assert_eq(json_str(status, "type"), "string")
  assert_eq(
    dig(status, ["enum"]).unwrap(),
    ["qwq".to_json(), "hhh".to_json()].to_json(),
  )
}

///|
test "descriptor-driven validation: enum admits a member, rejects a non-member" {
  let app = enum_app()
  // A member value passes and echoes the body back.
  let ok = app.handle(
    mkreq_full("POST", "/orders", body=@utf8.encode("{\"status\":\"qwq\"}")),
  )
  assert_eq(ok.status, 200)
  // A non-member value is a located 422 with the `enum` Pydantic error kind.
  let bad = app.handle(
    mkreq_full("POST", "/orders", body=@utf8.encode("{\"status\":\"emm\"}")),
  )
  assert_eq(bad.status, 422)
  let e = detail0(bad)
  assert_eq(json_str(e, "type"), "enum")
  assert_eq(err_loc(e), ["body", "status"])
}

///|
test "ToSchema trait bridges to the associated schema function" {
  let u : User = {
    id: 1,
    name: "n",
    address: { city: "c", zip: "z", },
    tags: [],
  }
  // Generic entry point returns the same descriptor as the associated fn.
  assert_eq(schema_of(u) == User::schema(), true)
}
