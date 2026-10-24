///|
/// Nullable is a wrapper on the value here; required is whether the name
/// appears in the required list. The description keeps them apart and so
/// must this.
test "nullable wraps the value, required does not" {
  assert_eq(
    only(@moonmodel.Field::new("x", Text, nullable=true)),
    SNullable(SStr),
  )
  assert_eq(only(@moonmodel.Field::new("x", Text, required=false)), SStr)
  let model = @moonmodel.Model::new("T", [
    @moonmodel.Field::new("a", Text),
    @moonmodel.Field::new("b", Text, required=false),
  ])
  let (schema, _) = Schema::of_model(model)
  guard schema is SObject(body) else { fail("not an object") }
  assert_true(body.fields[0].is_required())
  assert_false(body.fields[1].is_required())
}

///|
/// `shortest` and `longest` bound a string's characters and a list's items
/// alike in a description. Here they are two different constraints, and the
/// type is what says which one is meant.
test "a length bound follows the type it is written on" {
  let text = @moonmodel.Field::new(
    "s",
    Text,
    check=@moonmodel.Check::new(shortest=1, longest=8),
  )
  let list = @moonmodel.Field::new(
    "xs",
    List(Text),
    check=@moonmodel.Check::new(shortest=1, longest=8),
  )
  let model = @moonmodel.Model::new("T", [text, list])
  let (schema, _) = Schema::of_model(model)
  guard schema is SObject(body) else { fail("not an object") }
  assert_eq(body.fields[0].constraints, [MinLength(1), MaxLength(8)])
  assert_eq(body.fields[1].constraints, [MinItems(1), MaxItems(8)])
}

///|
/// A reference is written out where it stands, and this library hoists the
/// named object into `components` and points at it — so the document ends up
/// with the `$ref` the description meant.
test "a known reference is written out and a stranger is reported" {
  let address = @moonmodel.Model::new("Address", [
    @moonmodel.Field::new("city", Text),
  ])
  let model = @moonmodel.Model::new("Order", [
    @moonmodel.Field::new("home", Ref("Address")),
  ])
  let (schema, missing) = Schema::of_model(model, known=[address])
  assert_eq(missing.length(), 0)
  guard schema is SObject(body) else { fail("not an object") }
  assert_eq(
    body.fields[0].schema,
    SObject({
      name: "Address",
      fields: [Field::new("city", SStr)],
      description: "",
    }),
  )
  let (_, unknown) = Schema::of_model(model)
  assert_eq(unknown.length(), 1)
  assert_eq(unknown[0].field, "home")
  assert_eq(unknown[0].model, "Address")
  assert_true(unknown[0].why.contains("not among the known models"))
}

///|
/// A schema is a finite value, so a reference leading back into a model
/// already being written cannot be one. Reported rather than followed, which
/// would not terminate.
test "a reference that leads back on itself is reported" {
  let user = @moonmodel.Model::new("User", [
    @moonmodel.Field::new("name", Text),
    @moonmodel.Field::new("friend", Ref("User")),
  ])
  let (schema, missing) = Schema::of_model(user, known=[user])
  assert_eq(missing.length(), 1)
  assert_eq(missing[0].field, "friend")
  assert_true(missing[0].why.contains("finite"))
  guard schema is SObject(body) else { fail("not an object") }
  // The field it could not write is left out; the rest of the model stands.
  assert_eq(body.fields.length(), 1)
  assert_eq(body.fields[0].name, "name")
}

///|
/// The documentation and the default come across too, which is what makes a
/// described model worth as much as a hand-written schema.
test "documentation and defaults come across" {
  let model = @moonmodel.Model::new(
    "T",
    [
      @moonmodel.Field::new(
        "tier",
        Text,
        doc="what they pay for",
        default=Json("free"),
      ),
    ],
    doc="somebody with an account",
  )
  let (schema, _) = Schema::of_model(model)
  guard schema is SObject(body) else { fail("not an object") }
  assert_eq(body.description, "somebody with an account")
  assert_eq(body.fields[0].description, "what they pay for")
  assert_eq(body.fields[0].default, Some(Json("free")))
}
