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
