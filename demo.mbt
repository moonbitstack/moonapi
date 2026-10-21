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
pub fn Address::schema() -> @schema.Schema {
  @schema.Schema::object("Address", [
    @schema.Field::new("city", SStr),
    @schema.Field::new("zip", SStr),
  ])
}

///|
/// `Address`'s schema, so a route declaring it as a body or response documents itself.
pub impl @schema.ToSchema for Address with fn to_schema(_self) {
  Address::schema()
}

///|
/// The demo request model — the body of `POST /users`. `age` is optional.
pub(all) struct NewUser {
  name : String
  email : String
  age : Int32
} derive(ToJson, Eq)

///|
/// The `NewUser` descriptor.
pub fn NewUser::schema() -> @schema.Schema {
  @schema.Schema::object("NewUser", [
    @schema.Field::new("name", SStr, description="the user's display name"),
    @schema.Field::new("email", SStr),
    @schema.Field::new("age", SInt, required=false),
  ])
}

///|
/// `NewUser`'s schema, so a route declaring it as a body or response documents itself.
pub impl @schema.ToSchema for NewUser with fn to_schema(_self) {
  NewUser::schema()
}

///|
/// The demo response model — returned by both user routes. Nests `Address` and
/// carries an array of tags, so its emitted schema exercises objects, `$ref`s,
/// and arrays together.
pub(all) struct User {
  id : Int32
  name : String
  address : Address
  tags : Array[String]
} derive(ToJson, Eq)

///|
/// The `User` descriptor.
pub fn User::schema() -> @schema.Schema {
  @schema.Schema::object("User", [
    @schema.Field::new("id", SInt),
    @schema.Field::new("name", SStr),
    @schema.Field::new("address", Address::schema()),
    @schema.Field::new("tags", @schema.Schema::array(SStr)),
  ])
}

///|
/// `User`'s schema, so a route declaring it as a body or response documents itself.
pub impl @schema.ToSchema for User with fn to_schema(_self) {
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
  let create = @endpoint.Endpoint::new(request_body=NewUser::schema(), responses=[
    @endpoint.ResponseSpec::new(
      201,
      description="the created user",
      body=User::schema(),
    ),
    @endpoint.ResponseSpec::new(422, description="Validation Error"),
  ])
  app.post(
    "/users",
    ctx => {
      let errs = create.validate(ctx)
      if errs.length() > 0 {
        @schema.unprocessable(errs)
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
        @status.json(201, user.to_json())
      }
    },
    summary="create a user",
    endpoint=create,
  )
  let get_one = @endpoint.Endpoint::new(
    params=[@endpoint.Param::new("id", InPath, schema=SInt)],
    responses=[
      @endpoint.ResponseSpec::new(200, body=User::schema()),
      @endpoint.ResponseSpec::new(404, description="Not Found"),
    ],
  )
  app.get(
    "/users/:id",
    ctx => {
      let errs = get_one.validate(ctx)
      if errs.length() > 0 {
        @schema.unprocessable(errs)
      } else {
        let id = ctx.param("id").unwrap()
        let user : User = {
          id: @schema.parse_int(id).unwrap_or(0),
          name: "demo",
          address: { city: "Springfield", zip: "12345", },
          tags: ["a", "b"],
        }
        @status.json(200, user.to_json())
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
pub extend Address with @schema.ToSchema::{to_schema}

///|
pub extend NewUser with Eq::{not_equal, equal}

///|
pub extend NewUser with ToJson::{to_json}

///|
pub extend NewUser with @schema.ToSchema::{to_schema}

///|
pub extend User with Eq::{not_equal, equal}

///|
pub extend User with ToJson::{to_json}

///|
pub extend User with @schema.ToSchema::{to_schema}
