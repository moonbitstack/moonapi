// A declared parameter's bounds, default and alias: emitted into the document
// and enforced on the way in, off the one descriptor.

///|
/// An app whose `GET /items` declares exactly `p` — test helper.
fn param_app(p : Param) -> App {
  let app = App::new()
  app.get("/items", _ctx => text(200, "ok"), endpoint=Endpoint::new(params=[p]))
  app
}

///|
/// The single declared parameter of `GET /items` in `version` — test helper.
fn only_param(app : App, version : OpenApiVersion) -> Json {
  dig_arr(app.openapi(version~), ["paths", "/items", "get", "parameters"])[0]
}

///|
test "query param: a declared range is enforced with a 422 and documented" {
  let app = param_app(
    Param::new("limit", InQuery, schema=SInt, required=false, constraints=[
      Minimum(1.0),
      Maximum(100.0),
    ]),
  )
  // Above the bound.
  let over = app.handle(mkreq_full("GET", "/items", query=b"limit=500"))
  assert_eq(over.status, 422)
  assert_eq(json_str(detail0(over), "type"), "less_than_equal")
  assert_eq(
    json_str(detail0(over), "msg"),
    "Input should be less than or equal to 100",
  )
  assert_eq(err_loc(detail0(over)), ["query", "limit"])
  // Below it.
  let under = app.handle(mkreq_full("GET", "/items", query=b"limit=0"))
  assert_eq(under.status, 422)
  assert_eq(json_str(detail0(under), "type"), "greater_than_equal")
  // Inside it, and absent (the parameter is optional).
  assert_eq(
    app.handle(mkreq_full("GET", "/items", query=b"limit=50")).status,
    200,
  )
  assert_eq(app.handle(mkreq("GET", "/items")).status, 200)
  // And the document says so, rather than leaving the client to discover it.
  let schema = dig(only_param(app, OpenApi31), ["schema"]).unwrap()
  assert_eq(json_str(schema, "type"), "integer")
  assert_eq(dig(schema, ["minimum"]), Some(1.0.to_json()))
  assert_eq(dig(schema, ["maximum"]), Some(100.0.to_json()))
}

///|
test "query param: a string parameter's length and pattern bounds are enforced" {
  let app = param_app(
    Param::new("q", InQuery, required=false, constraints=[
      MinLength(3),
      Pattern("^[a-z]+$"),
    ]),
  )
  let short = app.handle(mkreq_full("GET", "/items", query=b"q=ab"))
  assert_eq(short.status, 422)
  assert_eq(json_str(detail0(short), "type"), "string_too_short")
  let shouty = app.handle(mkreq_full("GET", "/items", query=b"q=ABCD"))
  assert_eq(shouty.status, 422)
  assert_eq(json_str(detail0(shouty), "type"), "string_pattern_mismatch")
  assert_eq(
    app.handle(mkreq_full("GET", "/items", query=b"q=cats")).status,
    200,
  )
  let schema = dig(only_param(app, OpenApi31), ["schema"]).unwrap()
  assert_eq(dig(schema, ["minLength"]), Some((3).to_json()))
  assert_eq(json_str(schema, "pattern"), "^[a-z]+$")
}

///|
test "query param: a default makes it optional and is emitted" {
  let app = param_app(
    Param::new("limit", InQuery, schema=SInt, default=(10).to_json()),
  )
  // `required=true` was left at its default, but a parameter with a default is
  // never missing — the request without it is accepted.
  assert_eq(app.handle(mkreq("GET", "/items")).status, 200)
  let p = only_param(app, OpenApi31)
  assert_eq(dig(p, ["required"]), Some(false.to_json()))
  assert_eq(dig(p, ["schema", "default"]), Some((10).to_json()))
}

///|
test "query param: without a default, a required one is still reported missing" {
  let app = param_app(Param::new("limit", InQuery, schema=SInt))
  let miss = app.handle(mkreq("GET", "/items"))
  assert_eq(miss.status, 422)
  assert_eq(json_str(detail0(miss), "type"), "missing")
  assert_eq(dig(only_param(app, OpenApi31), ["required"]), Some(true.to_json()))
}

///|
test "query param: an alias is the name on the wire, in the document and in errors" {
  let app = param_app(Param::new("item_query", InQuery, alias_="item-query"))
  // The document calls it by the alias, because that is what a client sends.
  assert_eq(json_str(only_param(app, OpenApi31), "name"), "item-query")
  // The value is read under the alias...
  assert_eq(
    app.handle(mkreq_full("GET", "/items", query=b"item-query=cats")).status,
    200,
  )
  // ...and the field name it is bound to is not accepted in its place.
  let wrong = app.handle(mkreq_full("GET", "/items", query=b"item_query=cats"))
  assert_eq(wrong.status, 422)
  assert_eq(err_loc(detail0(wrong)), ["query", "item-query"])
}

///|
test "header and cookie params: bounds are enforced where the value lives" {
  let app = App::new()
  app.get(
    "/items",
    _ctx => text(200, "ok"),
    endpoint=Endpoint::new(params=[
      Param::new("x-page", InHeader, schema=SInt, constraints=[Maximum(9.0)]),
      Param::new("session", InCookie, constraints=[MinLength(4)]),
    ]),
  )
  let ok = app.handle(
    mkreq_hdrs("GET", "/items", [("x-page", "3"), ("cookie", "session=abcd")]),
  )
  assert_eq(ok.status, 200)
  let bad = app.handle(
    mkreq_hdrs("GET", "/items", [("x-page", "42"), ("cookie", "session=ab")]),
  )
  assert_eq(bad.status, 422)
  let errs = dig_arr(resp_json(bad), ["detail"])
  assert_eq(errs.length(), 2)
  assert_eq(err_loc(errs[0]), ["header", "x-page"])
  assert_eq(err_loc(errs[1]), ["cookie", "session"])
}

///|
test "query param: Swagger 2.0 carries the bounds on the parameter itself" {
  let app = param_app(
    Param::new(
      "limit",
      InQuery,
      schema=SInt,
      required=false,
      constraints=[Minimum(1.0), Maximum(100.0)],
      default=(10).to_json(),
    ),
  )
  // 2.0 has no `schema` for a scalar parameter, so type, bounds and default all
  // sit on the parameter object.
  let p = only_param(app, Swagger20)
  assert_eq(json_str(p, "type"), "integer")
  assert_eq(dig(p, ["minimum"]), Some(1.0.to_json()))
  assert_eq(dig(p, ["maximum"]), Some(100.0.to_json()))
  assert_eq(dig(p, ["default"]), Some((10).to_json()))
  assert_eq(dig(p, ["schema"]) is None, true)
}

///|
test "query param: an exclusive bound takes each dialect's form" {
  let app = param_app(
    Param::new("limit", InQuery, schema=SInt, required=false, constraints=[
      ExclusiveMinimum(0.0),
    ]),
  )
  // 3.1 (JSON-Schema 2020-12) makes it a number.
  let new = dig(only_param(app, OpenApi31), ["schema"]).unwrap()
  assert_eq(dig(new, ["exclusiveMinimum"]), Some(0.0.to_json()))
  assert_eq(dig(new, ["minimum"]) is None, true)
  // 3.0 makes it a flag beside `minimum`.
  let old = dig(only_param(app, OpenApi30), ["schema"]).unwrap()
  assert_eq(dig(old, ["exclusiveMinimum"]), Some(true.to_json()))
  assert_eq(dig(old, ["minimum"]), Some(0.0.to_json()))
  // Enforced either way.
  assert_eq(
    app.handle(mkreq_full("GET", "/items", query=b"limit=0")).status,
    422,
  )
  assert_eq(
    app.handle(mkreq_full("GET", "/items", query=b"limit=1")).status,
    200,
  )
}
