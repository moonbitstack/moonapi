// `SJson` is the escape hatch: a schema written as JSON Schema itself, for what
// the constructors cannot say. The same document is emitted into the OpenAPI
// document and handed to moonschema to validate against — one tree, two
// projections.

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
test "SJson is emitted into the document as it stands" {
  let app = App::new()
  app.post(
    "/posts",
    _ctx => text(200, "ok"),
    endpoint=Endpoint::new(request_body=slug_body()),
  )
  let doc = app.openapi()
  let schema = json_at(doc, [
    "components", "schemas", "Post", "properties", "slug",
  ])
  assert_eq(schema, Some({ "type": "string", "pattern": "^[a-z0-9-]+$" }))
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

///|
/// One step at a time down a document.
fn json_at(doc : Json, path : ArrayView[String]) -> Json? {
  let mut here = doc
  for step in path {
    here = match here {
      Object(members) =>
        match members.get(step) {
          Some(next) => next
          None => return None
        }
      _ => return None
    }
  }
  Some(here)
}
