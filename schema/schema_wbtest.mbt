///|
/// A nested value type, to show a `$ref` chain: `User.address` references this
/// under `components/schemas`.
struct Address {
  city : String
  zip : String
} derive(ToJson, Eq)

///|
/// The `Address` descriptor.
fn Address::schema() -> Schema {
  Schema::object("Address", [Field::new("city", SStr), Field::new("zip", SStr)])
}

///|
/// `Address`'s schema, so a route declaring it as a body or response documents itself.
impl ToSchema for Address with fn to_schema(_self) {
  Address::schema()
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
fn User::schema() -> Schema {
  Schema::object("User", [
    Field::new("id", SInt),
    Field::new("name", SStr),
    Field::new("address", Address::schema()),
    Field::new("tags", Schema::array(SStr)),
  ])
}

///|
/// `User`'s schema, so a route declaring it as a body or response documents itself.
impl ToSchema for User with fn to_schema(_self) {
  User::schema()
}

///|
pub extend Address with Eq::{not_equal, equal}

///|
pub extend Address with ToJson::{to_json}

///|
pub extend Address with ToSchema::{to_schema}

///|
pub extend User with Eq::{not_equal, equal}

///|
pub extend User with ToJson::{to_json}

///|
pub extend User with ToSchema::{to_schema}

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
/// The integer's width is lost in OpenAPI unless the format says it, and a
/// description keeps 32 and 64 bits apart, so the format is written.
test "each type reaches the schema it belongs to" {
  assert_eq(only(@moonmodel.Field::new("x", Bool)), SBool)
  assert_eq(only(@moonmodel.Field::new("x", Int)), SFormat(SInt, "int32"))
  assert_eq(only(@moonmodel.Field::new("x", Big)), SFormat(SInt, "int64"))
  assert_eq(only(@moonmodel.Field::new("x", Real)), SFloat)
  assert_eq(only(@moonmodel.Field::new("x", Text)), SStr)
  assert_eq(only(@moonmodel.Field::new("x", Bytes)), SFormat(SStr, "byte"))
  assert_eq(only(@moonmodel.Field::new("x", Stamp)), SFormat(SStr, "date-time"))
  assert_eq(only(@moonmodel.Field::new("x", List(Text))), SArray(SStr))
  assert_eq(only(@moonmodel.Field::new("x", Dict(Text))), SMap(SStr))
  assert_eq(only(@moonmodel.Field::new("x", Any)), SAny)
}

///|
test "a closed set and a format wrap the value" {
  assert_eq(
    only(
      @moonmodel.Field::new(
        "x",
        Text,
        check=@moonmodel.Check::new(options=[Json("a"), Json("b")]),
      ),
    ),
    SEnum(SStr, [Json("a"), Json("b")]),
  )
  assert_eq(
    only(
      @moonmodel.Field::new(
        "x",
        Text,
        check=@moonmodel.Check::new(format="email"),
      ),
    ),
    SFormat(SStr, "email"),
  )
}

///|
test "a nested model and a hand-written schema carry over" {
  let nested = only(
    @moonmodel.Field::new(
      "at",
      Nest(@moonmodel.Model::new("", [@moonmodel.Field::new("city", Text)])),
    ),
  )
  assert_eq(
    nested,
    SObject({ name: "", fields: [Field::new("city", SStr)], description: "", }),
  )
  let written : Json = { "allOf": [] }
  assert_eq(
    only(@moonmodel.Field::new("both", Raw(written))),
    Schema::json(written),
  )
}

///|
test "response_model projects through arrays element-wise" {
  let model = Schema::array(Schema::object("Tag", [Field::new("label", SStr)]))
  let produced = @json.parse(
    "[{\"label\":\"a\",\"weight\":5},{\"label\":\"b\",\"weight\":9}]",
  ) catch {
    _ => Json::null()
  }
  let filtered = match filter_response(model, produced) {
    Ok(j) => j
    Err(_) => Json::null()
  }
  match filtered {
    Array(a) => {
      assert_eq(a.length(), 2)
      assert_eq(json_str(a[0], "label"), "a")
      // The undeclared `weight` was stripped from each element.
      assert_eq(dig(a[0], ["weight"]) is None, true)
      assert_eq(dig(a[1], ["weight"]) is None, true)
    }
    _ => assert_eq("expected array", "got other")
  }
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
