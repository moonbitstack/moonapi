// A worked example of the descriptor tree: user structs that describe their own
// schema, an `impl ToSchema`, and a demo app whose request/response bodies show
// up fully-typed in `openapi.json`. This is the mctl-friendly shape — mctl would
// generate exactly this from a spec: `derive(ToJson)` for serialisation plus a
// plain `T::schema()` associated function (no instance needed, mirroring FastAPI
// referencing the model class) and its one-line `ToSchema` bridge.

///|
/// A nested value type, to show a `$ref` chain: `User.address` references this
/// under `components/schemas`.
pub(all) struct Address {
  city : String
  zip : String
} derive(ToJson, Eq)

///|
/// The `Address` descriptor.
pub fn Address::schema() -> Schema {
  Schema::object("Address", [Field::new("city", SStr), Field::new("zip", SStr)])
}

///|
/// `Address`'s schema, so a route declaring it as a body or response documents itself.
pub impl ToSchema for Address with fn to_schema(_self) {
  Address::schema()
}

///|
/// The demo request model — the body of `POST /users`. `age` is optional.
pub(all) struct NewUser {
  name : String
  email : String
  age : Int
} derive(ToJson, Eq)

///|
/// The `NewUser` descriptor.
pub fn NewUser::schema() -> Schema {
  Schema::object("NewUser", [
    Field::new("name", SStr, description="the user's display name"),
    Field::new("email", SStr),
    Field::new("age", SInt, required=false),
  ])
}

///|
/// `NewUser`'s schema, so a route declaring it as a body or response documents itself.
pub impl ToSchema for NewUser with fn to_schema(_self) {
  NewUser::schema()
}

///|
/// The demo response model — returned by both user routes. Nests `Address` and
/// carries an array of tags, so its emitted schema exercises objects, `$ref`s,
/// and arrays together.
pub(all) struct User {
  id : Int
  name : String
  address : Address
  tags : Array[String]
} derive(ToJson, Eq)

///|
/// The `User` descriptor.
pub fn User::schema() -> Schema {
  Schema::object("User", [
    Field::new("id", SInt),
    Field::new("name", SStr),
    Field::new("address", Address::schema()),
    Field::new("tags", Schema::array(SStr)),
  ])
}

///|
/// `User`'s schema, so a route declaring it as a body or response documents itself.
pub impl ToSchema for User with fn to_schema(_self) {
  User::schema()
}

///|
/// A demo application exercising the descriptor tree end to end: `POST /users`
/// takes a typed `NewUser` body and returns a `User`; `GET /users/:id` takes a
/// typed integer path param and returns a `User`. Both validate off their
/// descriptor and both surface fully-typed bodies (with `components/schemas`
/// `$ref`s) in `openapi.json`.
pub fn demo_app() -> App {
  let app = App::new()
  let create = Endpoint::new(request_body=NewUser::schema(), responses=[
    ResponseSpec::new(201, description="the created user", body=User::schema()),
    ResponseSpec::new(422, description="Validation Error"),
  ])
  app.post(
    "/users",
    ctx => {
      let errs = create.validate(ctx)
      if errs.length() > 0 {
        unprocessable(errs)
      } else {
        let name = match ctx.json_field("name") {
          Some(String(s)) => s
          _ => ""
        }
        let user : User = {
          id: 1,
          name,
          address: { city: "Nowhere", zip: "00000", },
          tags: [],
        }
        json(201, user.to_json())
      }
    },
    summary="create a user",
    endpoint=create,
  )
  let get_one = Endpoint::new(params=[Param::new("id", InPath, schema=SInt)], responses=[
    ResponseSpec::new(200, body=User::schema()),
    ResponseSpec::new(404, description="Not Found"),
  ])
  app.get(
    "/users/:id",
    ctx => {
      let errs = get_one.validate(ctx)
      if errs.length() > 0 {
        unprocessable(errs)
      } else {
        let id = ctx.param("id").unwrap()
        let user : User = {
          id: parse_int(id).unwrap_or(0),
          name: "demo",
          address: { city: "Springfield", zip: "12345", },
          tags: ["a", "b"],
        }
        json(200, user.to_json())
      }
    },
    summary="fetch a user",
    endpoint=get_one,
  )
  app
}

///|
pub extend Address with Eq::{not_equal, equal}

///|
pub extend Address with ToJson::{to_json}

///|
pub extend Address with ToSchema::{to_schema}

///|
pub extend NewUser with Eq::{not_equal, equal}

///|
pub extend NewUser with ToJson::{to_json}

///|
pub extend NewUser with ToSchema::{to_schema}

///|
pub extend User with Eq::{not_equal, equal}

///|
pub extend User with ToJson::{to_json}

///|
pub extend User with ToSchema::{to_schema}
