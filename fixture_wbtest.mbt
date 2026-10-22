///|
fn mkreq(m : String, path : String) -> @moonasgi.Request {
  { http_method: m, path, query_string: b"", headers: [], body: b"", }
}

///|
fn mkreq_full(
  m : String,
  path : String,
  query~ : Bytes = b"",
  body~ : Bytes = b"",
) -> @moonasgi.Request {
  { http_method: m, path, query_string: query, headers: [], body, }
}

///|
/// Fetch a string field out of a JSON object, "" if absent — test helper.
fn json_str(j : Json, key : String) -> String {
  match j {
    Object(m) =>
      match m.get(key) {
        Some(String(s)) => s
        _ => ""
      }
    _ => ""
  }
}

///|
/// The `get`/`post`/… `verb` operation at `path` in an OpenAPI document.
fn op_of(doc : Json, path : String, verb : String) -> Json? {
  guard doc is Object(m) else { return None }
  guard m.get("paths") is Some(Object(p)) else { return None }
  guard p.get(path) is Some(Object(methods)) else { return None }
  methods.get(verb)
}

///|
/// The `responses` object of an operation, empty if it has none — test helper.
fn op_responses(doc : Json, path : String, verb : String) -> Map[String, Json] {
  match op_of(doc, path, verb) {
    Some(Object(op)) =>
      match op.get("responses") {
        Some(Object(m)) => m
        _ => Map([])
      }
    _ => Map([])
  }
}

///|
/// The `description` of one response of an operation, "" if it declares no such
/// response — test helper.
fn resp_desc(responses : Map[String, Json], status : String) -> String {
  match responses.get(status) {
    Some(j) => json_str(j, "description")
    None => ""
  }
}

///|
/// A nested value type, to show a `$ref` chain: `User.address` references this
/// under `components/schemas`.
struct Address {
  city : String
  zip : String
} derive(ToJson, Eq)

///|
/// The `Address` descriptor.
fn Address::schema() -> @schema.Schema {
  @schema.Schema::object("Address", [
    @schema.Field::new("city", SStr),
    @schema.Field::new("zip", SStr),
  ])
}

///|
/// `Address`'s schema, so a route declaring it as a body or response documents itself.
impl @schema.ToSchema for Address with fn to_schema(_self) {
  Address::schema()
}

///|
/// The `NewUser` descriptor.
fn new_user_schema() -> @schema.Schema {
  @schema.Schema::object("NewUser", [
    @schema.Field::new("name", SStr, description="the user's display name"),
    @schema.Field::new("email", SStr),
    @schema.Field::new("age", SInt, required=false),
  ])
}

///|
/// The demo response model — returned by both user routes. Nests `Address` and
/// carries an array of tags, so its emitted schema exercises objects, `$ref`s,
/// and arrays together.
struct User {
  id : Int32
  name : String
  address : Address
  tags : Array[String]
} derive(ToJson, Eq)

///|
/// The `User` descriptor.
fn User::schema() -> @schema.Schema {
  @schema.Schema::object("User", [
    @schema.Field::new("id", SInt),
    @schema.Field::new("name", SStr),
    @schema.Field::new("address", Address::schema()),
    @schema.Field::new("tags", @schema.Schema::array(SStr)),
  ])
}

///|
/// `User`'s schema, so a route declaring it as a body or response documents itself.
impl @schema.ToSchema for User with fn to_schema(_self) {
  User::schema()
}

///|
/// A demo application exercising the descriptor tree end to end: `POST /users`
/// takes a typed `NewUser` body and returns a `User`; `GET /users/:id` takes a
/// typed integer path param and returns a `User`. Both validate off their
/// descriptor and both surface fully-typed bodies (with `components/schemas`
/// `$ref`s) in `openapi.json`.
fn demo_app() -> App {
  let app = App::new()
  let create = @endpoint.Endpoint::new(request_body=new_user_schema(), responses=[
    @endpoint.ResponseSpec::new(
      201,
      description="the created user",
      body=User::schema(),
    ),
    @endpoint.ResponseSpec::new(422, description="Validation Error"),
  ])
  app.post(
    "/users",
    ctx => {
      let errs = create.validate(ctx)
      if errs.length() > 0 {
        @schema.unprocessable(errs)
      } else {
        let name = match ctx.json_field("name") {
          Some(String(s)) => s
          _ => ""
        }
        let user : User = {
          id: 1,
          name,
          address: { city: "Nowhere", zip: "00000", },
          tags: [],
        }
        @status.json(201, user.to_json())
      }
    },
    summary="create a user",
    endpoint=create,
  )
  let get_one = @endpoint.Endpoint::new(
    params=[@endpoint.Param::new("id", InPath, schema=SInt)],
    responses=[
      @endpoint.ResponseSpec::new(200, body=User::schema()),
      @endpoint.ResponseSpec::new(404, description="Not Found"),
    ],
  )
  app.get(
    "/users/:id",
    ctx => {
      let errs = get_one.validate(ctx)
      if errs.length() > 0 {
        @schema.unprocessable(errs)
      } else {
        let id = ctx.param("id").unwrap()
        let user : User = {
          id: @schema.parse_int(id).unwrap_or(0),
          name: "demo",
          address: { city: "Springfield", zip: "12345", },
          tags: ["a", "b"],
        }
        @status.json(200, user.to_json())
      }
    },
    summary="fetch a user",
    endpoint=get_one,
  )
  app
}

// A worked example wiring the two new pieces together: a dependency provides a
// value, a typed request body is deserialised + validated off its descriptor,
// and the handler uses both — FastAPI's `def greet(body: GreetReq, greeter: str
// = Depends(...))` in explicit MoonBit form.

///|
pub extend Address with Eq::{not_equal, equal}

///|
pub extend Address with ToJson::{to_json}

///|
pub extend Address with @schema.ToSchema::{to_schema}

///|
pub extend User with Eq::{not_equal, equal}

///|
pub extend User with ToJson::{to_json}

///|
pub extend User with @schema.ToSchema::{to_schema}

///|
/// An app whose `GET /items` declares exactly `p` — test helper.
fn param_app(p : @endpoint.Param) -> App {
  let app = App::new()
  app.get(
    "/items",
    _ctx => @status.text(200, "ok"),
    endpoint=@endpoint.Endpoint::new(params=[p]),
  )
  app
}

///|
/// The single declared parameter of `GET /items` in `version` — test helper.
fn only_param(app : App, version : @schema.OpenApiVersion) -> Json {
  dig_arr(app.openapi(version~), ["paths", "/items", "get", "parameters"])[0]
}

///|
/// An app whose `POST /thing` takes `body` as its request body — test helper.
fn body_app(body : @schema.Schema) -> App {
  let app = App::new()
  app.post(
    "/thing",
    _ctx => @status.text(200, "ok"),
    endpoint=@endpoint.Endpoint::new(request_body=body),
  )
  app
}

///|
/// `POST /thing` with `payload` as its body — test helper.
fn post_body(app : App, payload : String) -> @moonasgi.Response {
  app.handle(mkreq_full("POST", "/thing", body=@utf8.encode(payload)))
}

///|
/// The emitted request-body schema of `POST /thing` in `version` — test helper.
fn body_schema(app : App, version : @schema.OpenApiVersion) -> Json {
  let doc = app.openapi(version~)
  match version {
    Swagger20 => {
      let mut found = Json::null()
      for p in dig_arr(doc, ["paths", "/thing", "post", "parameters"]) {
        if json_str(p, "in") == "body" {
          found = dig(p, ["schema"]).unwrap()
        }
      }
      found
    }
    _ =>
      dig(doc, [
        "paths", "/thing", "post", "requestBody", "content", "application/json",
        "schema",
      ]).unwrap()
  }
}

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
/// A typed route whose body carries an enum field (← a Python `Enum` /
/// `typing.Literal`): its OpenAPI schema advertises the closed value set and its
/// validation enforces membership.
fn enum_app() -> App {
  let body = @schema.Schema::object("Order", [
    @schema.Field::new(
      "status",
      SEnum(@schema.SStr, [Json("qwq"), Json("hhh")]),
    ),
  ])
  let ep = @endpoint.Endpoint::new(request_body=body, responses=[
    @endpoint.ResponseSpec::new(200, body~),
  ])
  let app = App::new()
  app.post(
    "/orders",
    ctx => {
      let errs = ep.validate(ctx)
      if errs.length() > 0 {
        @schema.unprocessable(errs)
      } else {
        @status.json(200, ctx.body_json().unwrap_or(Json::null()))
      }
    },
    endpoint=ep,
  )
  app
}

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
/// A request with an `Authorization` header and no body — test helper.
fn mkreq_auth(
  verb : String,
  path : String,
  authorization : String,
) -> @moonasgi.Request {
  {
    http_method: verb,
    path,
    query_string: b"",
    headers: [("authorization", authorization)],
    body: b"",
  }
}

///|
/// The body events of a reply, in order — test helper.
fn body_events(app : App, req : @moonasgi.Request) -> Array[@moonasgi.Event] {
  let (resp, _bg) = app.handle_with_stream(req)
  resp.events().filter(e => e is HttpResponseBody(_))
}

///|
/// The `more_body` flag of each body event, in order — test helper.
fn more_body_flags(app : App, req : @moonasgi.Request) -> Array[Bool] {
  body_events(app, req).map(e => {
    match e {
      HttpResponseBody(more_body~, ..) => more_body
      _ => false
    }
  })
}

///|
/// Whether the merged document declares `path`.
fn path_exists(doc : Json, path : String) -> Bool {
  match doc {
    Object(m) =>
      match m.get("paths") {
        Some(Object(p)) => p.get(path) is Some(_)
        _ => false
      }
    _ => false
  }
}

///|
test "query param: Swagger 2.0 carries the bounds on the parameter itself" {
  let app = param_app(
    @endpoint.Param::new(
      "limit",
      InQuery,
      schema=SInt,
      required=false,
      constraints=[@schema.Minimum(1.0), @schema.Maximum(100.0)],
      default=Json(10),
    ),
  )
  // 2.0 has no `schema` for a scalar parameter, so type, bounds and default all
  // sit on the parameter object.
  let p = only_param(app, Swagger20)
  assert_eq(json_str(p, "type"), "integer")
  assert_eq(dig(p, ["minimum"]), Some(Json(1.0)))
  assert_eq(dig(p, ["maximum"]), Some(Json(100.0)))
  assert_eq(dig(p, ["default"]), Some(Json(10)))
  assert_eq(dig(p, ["schema"]) is None, true)
}

///|
test "nullable: null is accepted, the wrapped type is still enforced" {
  let app = body_app(
    @schema.Schema::object("Note", [
      @schema.Field::new("title", @schema.Schema::nullable(SStr)),
    ]),
  )
  assert_eq(post_body(app, "{\"title\":null}").status, 200)
  assert_eq(post_body(app, "{\"title\":\"hi\"}").status, 200)
  // Nullable widens the type; it does not abandon it.
  let bad = post_body(app, "{\"title\":5}")
  assert_eq(bad.status, 422)
  assert_eq(json_str(detail0(bad), "type"), "string_type")
  assert_eq(err_loc(detail0(bad)), ["body", "title"])
  // And nullable is not optional: the field still has to be there.
  let miss = post_body(app, "{}")
  assert_eq(miss.status, 422)
  assert_eq(json_str(detail0(miss), "type"), "missing")
}

///|
test "map body: emitted as additionalProperties and validated per value" {
  let app = body_app(@schema.Schema::map(SInt))
  let s = body_schema(app, OpenApi31)
  assert_eq(json_str(s, "type"), "object")
  assert_eq(
    json_str(dig(s, ["additionalProperties"]).unwrap(), "type"),
    "integer",
  )
  assert_eq(post_body(app, "{\"a\":1,\"b\":2}").status, 200)
  // An empty map has no values to disagree with.
  assert_eq(post_body(app, "{}").status, 200)
  // A bad value is located by its key.
  let bad = post_body(app, "{\"a\":1,\"b\":\"two\"}")
  assert_eq(bad.status, 422)
  assert_eq(json_str(detail0(bad), "type"), "int_type")
  assert_eq(err_loc(detail0(bad)), ["body", "b"])
  // A body that is not an object at all.
  let arr = post_body(app, "[1,2]")
  assert_eq(arr.status, 422)
  assert_eq(json_str(detail0(arr), "type"), "dict_type")
  assert_eq(err_loc(detail0(arr)), ["body"])
}

///|
test "map body: a map of objects hoists its value schema" {
  let app = body_app(
    @schema.Schema::map(
      @schema.Schema::object("Addr", [@schema.Field::new("city", SStr)]),
    ),
  )
  assert_eq(
    json_str(
      dig(body_schema(app, OpenApi31), ["additionalProperties"]).unwrap(),
      "$ref",
    ),
    "#/components/schemas/Addr",
  )
  assert_eq(post_body(app, "{\"home\":{\"city\":\"Nowhere\"}}").status, 200)
  let bad = post_body(app, "{\"home\":{}}")
  assert_eq(bad.status, 422)
  assert_eq(err_loc(detail0(bad)), ["body", "home", "city"])
}

///|
test "map body: Swagger 2.0 says additionalProperties too" {
  let app = body_app(@schema.Schema::map(SStr))
  assert_eq(
    json_str(
      dig(body_schema(app, Swagger20), ["additionalProperties"]).unwrap(),
      "type",
    ),
    "string",
  )
}

///|
test "any: the empty schema, which constrains nothing" {
  let app = body_app(@schema.Schema::map(SAny))
  let s = body_schema(app, OpenApi31)
  // A free-form object: the values may be anything, so their schema says
  // nothing at all.
  assert_eq(dig(s, ["additionalProperties"]).unwrap(), @json.parse("{}"))
  assert_eq(post_body(app, "{\"a\":1,\"b\":\"two\",\"c\":[null]}").status, 200)
}
