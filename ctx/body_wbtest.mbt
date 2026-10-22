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
/// A Context wrapping a POST body, no params — test helper.
fn body_ctx(payload : String) -> Context {
  {
    request: mkreq_full("POST", "/greet", body=@utf8.encode(payload)),
    params: Map([]),
  }
}

///|
/// The request body of `POST /greet`. `derive(@json.FromJson)` lets
/// `Context::body_validated` build it after the descriptor accepts the payload;
/// its schema and struct fields agree (both require `name`), so a schema-valid
/// body always deserialises.
struct GreetReq {
  name : String
} derive(ToJson, FromJson, Eq)

///|
/// The `GreetReq` descriptor — one required string field.
fn GreetReq::schema() -> @schema.Schema {
  @schema.Schema::object("GreetReq", [@schema.Field::new("name", SStr)])
}

///|
pub extend GreetReq with Eq::{not_equal, equal}

///|
pub extend GreetReq with FromJson::{from_json}

///|
pub extend GreetReq with ToJson::{to_json}

///|
test "typed body: valid payload deserialises into the struct" {
  let ctx = body_ctx("{\"name\":\"ada\"}")
  let r : Result[GreetReq, _] = ctx.body_validated(GreetReq::schema())
  match r {
    Ok(req) => assert_eq(req.name, "ada")
    Err(_) => assert_eq("expected Ok", "got Err")
  }
}

///|
test "typed body: missing required field -> located 422 errors" {
  let ctx = body_ctx("{}")
  let r : Result[GreetReq, _] = ctx.body_validated(GreetReq::schema())
  match r {
    Ok(_) => assert_eq("expected Err", "got Ok")
    Err(errs) => {
      assert_eq(errs.length(), 1)
      assert_eq(errs[0].kind, "missing")
      assert_eq(errs[0].loc, ["body", "name"])
    }
  }
}

///|
test "typed body: wrong field type -> located 422 before deserialisation" {
  let ctx = body_ctx("{\"name\":5}")
  let r : Result[GreetReq, _] = ctx.body_validated(GreetReq::schema())
  match r {
    Ok(_) => assert_eq("expected Err", "got Ok")
    Err(errs) => {
      assert_eq(errs.length(), 1)
      assert_eq(errs[0].kind, "string_type")
      assert_eq(errs[0].loc, ["body", "name"])
    }
  }
}

///|
test "typed body: empty body -> missing, invalid JSON -> json_invalid" {
  let empty : Context = {
    request: mkreq_full("POST", "/greet"),
    params: Map([]),
  }
  match (empty.body_validated(GreetReq::schema()) : Result[GreetReq, _]) {
    Err(errs) => assert_eq(errs[0].kind, "missing")
    Ok(_) => assert_eq("expected Err", "got Ok")
  }
  let junk = body_ctx("{not json")
  match (junk.body_validated(GreetReq::schema()) : Result[GreetReq, _]) {
    Err(errs) => assert_eq(errs[0].kind, "json_invalid")
    Ok(_) => assert_eq("expected Err", "got Ok")
  }
}

///|
test "typed body: unchecked extractor is total, None on bad shape" {
  let ok = body_ctx("{\"name\":\"x\"}")
  assert_eq((ok.body() : GreetReq?).unwrap().name, "x")
  let bad = body_ctx("{\"name\":5}")
  assert_eq((bad.body() : GreetReq?) is None, true)
}
