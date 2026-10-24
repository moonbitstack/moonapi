///|
/// The request body both routes read. `derive(FromJson)` builds it once the
/// descriptor has accepted the payload; the schema and the struct agree that
/// `name` is required, so a body the schema accepts always reads.
struct GreetReq {
  name : String
} derive(FromJson)

///|
fn GreetReq::schema() -> @moonapi.Schema {
  @moonapi.Schema::object("GreetReq", [@moonapi.Field::new("name", SStr)])
}
