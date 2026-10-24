///|
struct Address {
  city : String
  zip : String
} derive(ToJson)

///|
fn Address::schema() -> @moonapi.Schema {
  @moonapi.Schema::object("Address", [
    @moonapi.Field::new("city", SStr),
    @moonapi.Field::new("zip", SStr),
  ])
}

///|
/// A response model. `User::schema()` is its descriptor, and the `ToSchema`
/// bridge below lets `schema_of(user)` reach the same tree from a value.
struct User {
  id : Int32
  name : String
  address : Address
  tags : Array[String]
} derive(ToJson)

///|
fn User::schema() -> @moonapi.Schema {
  @moonapi.Schema::object("User", [
    @moonapi.Field::new("id", SInt),
    @moonapi.Field::new("name", SStr),
    @moonapi.Field::new("address", Address::schema()),
    @moonapi.Field::new("tags", @moonapi.Schema::array(SStr)),
  ])
}

///|
impl @moonapi.ToSchema for User with fn to_schema(_self) {
  User::schema()
}
