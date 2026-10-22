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
/// A field constrained by a pattern, which the descriptor enum cannot express.
fn slug_body() -> Schema {
  Schema::object("Post", [
    Field::new(
      "slug",
      Schema::json(({ "type": "string", "pattern": "^[a-z0-9-]+$" } : Json)),
      required=true,
    ),
  ])
}

///|
test "422 body shape mirrors FastAPI" {
  let body = validation_error_body([ValidationError::missing(["query", "q"])])
  let detail = match body {
    Object(m) =>
      match m.get("detail") {
        Some(Array(a)) => a
        _ => []
      }
    _ => []
  }
  assert_eq(detail.length(), 1)
  assert_eq(json_str(detail[0], "type"), "missing")
  assert_eq(json_str(detail[0], "msg"), "Field required")
}

///|
test "SJson validates through moonschema" {
  let errs : Array[ValidationError] = []
  validate_schema(slug_body(), { "slug": "hello-world" }, [], errs)
  assert_eq(errs.length(), 0)
  validate_schema(slug_body(), { "slug": "Hello World" }, [], errs)
  assert_eq(errs.length(), 1)
  assert_eq(errs[0].loc, ["slug"])
  assert_eq(errs[0].kind, "pattern")
}

///|
test "a JSON Schema this cannot read is a schema error, not a bad request" {
  let errs : Array[ValidationError] = []
  validate_schema(
    Schema::json({ "$schema": "https://example.test/nope" }),
    Json::null(),
    [],
    errs,
  )
  assert_eq(errs.length(), 1)
  assert_eq(errs[0].kind, "schema_error")
}
