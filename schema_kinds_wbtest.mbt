// The schema vocabulary beyond the scalars: nullable, a free-form or typed map,
// `Any`, a format, and a field default — each emitted the way its dialect says
// it, and each driving validation off the same tree.

///|
/// An app whose `POST /thing` takes `body` as its request body — test helper.
fn body_app(body : Schema) -> App {
  let app = App::new()
  app.post(
    "/thing",
    _ctx => text(200, "ok"),
    endpoint=Endpoint::new(request_body=body),
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
fn body_schema(app : App, version : OpenApiVersion) -> Json {
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
test "nullable: each dialect says it its own way" {
  let app = body_app(
    Schema::object("Note", [Field::new("title", Schema::nullable(SStr))]),
  )
  // 3.1 is JSON-Schema 2020-12: the type itself becomes a list.
  let new = dig(app.openapi(version=OpenApi31), [
    "components", "schemas", "Note", "properties", "title",
  ]).unwrap()
  assert_eq(
    dig(new, ["type"]).unwrap(),
    ["string".to_json(), "null".to_json()].to_json(),
  )
  // 3.0 has the `nullable` flag.
  let mid = dig(app.openapi(version=OpenApi30), [
    "components", "schemas", "Note", "properties", "title",
  ]).unwrap()
  assert_eq(json_str(mid, "type"), "string")
  assert_eq(dig(mid, ["nullable"]), Some(true.to_json()))
  // 2.0 has nothing in the specification proper, so it uses the extension its
  // tooling reads.
  let old = dig(app.openapi(version=Swagger20), [
    "definitions", "Note", "properties", "title",
  ]).unwrap()
  assert_eq(dig(old, ["x-nullable"]), Some(true.to_json()))
}

///|
test "nullable: null is accepted, the wrapped type is still enforced" {
  let app = body_app(
    Schema::object("Note", [Field::new("title", Schema::nullable(SStr))]),
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
test "nullable: a composite with no type to widen becomes an anyOf in 3.1" {
  let inner = Schema::object("Addr", [Field::new("city", SStr)])
  let app = body_app(
    Schema::object("Person", [Field::new("addr", Schema::nullable(inner))]),
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
test "map body: emitted as additionalProperties and validated per value" {
  let app = body_app(Schema::map(SInt))
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
    Schema::map(Schema::object("Addr", [Field::new("city", SStr)])),
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
  let app = body_app(Schema::map(SStr))
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
  let app = body_app(Schema::map(SAny))
  let s = body_schema(app, OpenApi31)
  // A free-form object: the values may be anything, so their schema says
  // nothing at all.
  assert_eq(dig(s, ["additionalProperties"]).unwrap(), @json.parse("{}"))
  assert_eq(post_body(app, "{\"a\":1,\"b\":\"two\",\"c\":[null]}").status, 200)
}

///|
test "format: a binary upload is a string that says what it holds" {
  let app = body_app(
    Schema::object("Upload", [
      Field::new("file", Schema::binary()),
      Field::new("when", Schema::format(SStr, "date-time")),
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
    Schema::object("Page", [
      Field::new("size", SInt, default=(20).to_json()),
      Field::new("q", SStr),
    ]),
  )
  let model = dig(app.openapi(version=OpenApi31), [
    "components", "schemas", "Page",
  ]).unwrap()
  assert_eq(dig(model, ["properties", "size", "default"]), Some((20).to_json()))
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
test "nullable: a nullable scalar parameter still parses as its base" {
  let app = param_app(
    Param::new(
      "limit",
      InQuery,
      schema=Schema::nullable(SInt),
      required=false,
      constraints=[Maximum(9.0)],
    ),
  )
  assert_eq(
    app.handle(mkreq_full("GET", "/items", query=b"limit=5")).status,
    200,
  )
  let bad = app.handle(mkreq_full("GET", "/items", query=b"limit=many"))
  assert_eq(bad.status, 422)
  assert_eq(json_str(detail0(bad), "type"), "int_parsing")
  // The bound compares numbers through the wrapper, not text.
  let over = app.handle(mkreq_full("GET", "/items", query=b"limit=99"))
  assert_eq(over.status, 422)
  assert_eq(json_str(detail0(over), "type"), "less_than_equal")
  // Swagger 2.0 reads the base type through the wrapper, since a 2.0 parameter
  // carries its type inline and has nowhere else to put it.
  assert_eq(json_str(only_param(app, Swagger20), "type"), "integer")
}

///|
test "format: a formatted scalar parameter is documented and parsed as its base" {
  let app = param_app(
    Param::new(
      "at",
      InQuery,
      schema=Schema::format(SInt, "int64"),
      required=false,
      constraints=[Minimum(1.0)],
    ),
  )
  let schema = dig(only_param(app, OpenApi31), ["schema"]).unwrap()
  assert_eq(json_str(schema, "type"), "integer")
  assert_eq(json_str(schema, "format"), "int64")
  assert_eq(dig(schema, ["minimum"]), Some(1.0.to_json()))
  let bad = app.handle(mkreq_full("GET", "/items", query=b"at=soon"))
  assert_eq(bad.status, 422)
  assert_eq(json_str(detail0(bad), "type"), "int_parsing")
  let low = app.handle(mkreq_full("GET", "/items", query=b"at=0"))
  assert_eq(low.status, 422)
  assert_eq(json_str(detail0(low), "type"), "greater_than_equal")
  assert_eq(app.handle(mkreq_full("GET", "/items", query=b"at=5")).status, 200)
  // 2.0 reads the base type through the format wrapper, as it does a nullable.
  assert_eq(json_str(only_param(app, Swagger20), "type"), "integer")
}
