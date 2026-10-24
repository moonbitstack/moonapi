///|
/// The body of `POST /accounts/greet`: one required name. The descriptor checks
/// the payload, `derive(FromJson)` reads it.
struct GreetReq {
  name : String
} derive(FromJson)

///|
fn GreetReq::schema() -> @moonapi.Schema {
  @moonapi.Schema::object("GreetReq", [@moonapi.Field::new("name", SStr)])
}

///|
pub extend GreetReq with FromJson::{from_json}
