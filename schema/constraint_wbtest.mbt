// Pydantic-style field constraints: enforced at validation with the matching error types, and
// emitted into the field's OpenAPI schema (version-aware `exclusiveMinimum`).

///|
test "constraints: a conforming body passes, violations yield Pydantic error kinds" {
  let schema = Schema::object("Thing", [
    Field::new("n", SInt, constraints=[Minimum(1.0), Maximum(10.0)]),
    Field::new("name", SStr, constraints=[
      MinLength(3),
      MaxLength(5),
      Pattern("^[a-z]+$"),
    ]),
    Field::new("tags", Schema::array(SStr), constraints=[MinItems(1)]),
  ])
  let ok : Array[ValidationError] = []
  validate_schema(
    schema,
    @json.parse(
      (
        #|{"n":5,"name":"abc","tags":["x"]}
      ),
    ),
    [],
    ok,
  )
  assert_eq(ok.length(), 0)
  let errs : Array[ValidationError] = []
  validate_schema(
    schema,
    @json.parse(
      (
        #|{"n":20,"name":"AB","tags":[]}
      ),
    ),
    [],
    errs,
  )
  let body = validation_error_body(errs).stringify()
  // n = 20 exceeds the maximum.
  assert_eq(body.contains("less_than_equal"), true)
  // name = "AB" is too short and does not match the lowercase pattern.
  assert_eq(body.contains("string_too_short"), true)
  assert_eq(body.contains("string_pattern_mismatch"), true)
  // tags = [] is below the minimum item count.
  assert_eq(body.contains("too_short"), true)
}

///|
test "constraints: emission is version-aware for exclusiveMinimum" {
  let base : Json = { "type": "integer" }
  // OpenAPI 3.1 (JSON-Schema 2020-12): exclusiveMinimum is a number.
  match with_constraints(base, [ExclusiveMinimum(5.0)], OpenApi31) {
    Object(o) => {
      assert_eq(o.get("exclusiveMinimum") is Some(Number(_)), true)
      assert_eq(o.get("minimum"), None)
    }
    _ => fail("expected an object")
  }
  // OpenAPI 3.0 / Swagger 2.0: exclusiveMinimum is a boolean flag beside minimum.
  match with_constraints(base, [ExclusiveMinimum(5.0)], OpenApi30) {
    Object(o) => {
      assert_eq(o.get("exclusiveMinimum") is Some(True), true)
      assert_eq(o.get("minimum") is Some(Number(_)), true)
    }
    _ => fail("expected an object")
  }
}
