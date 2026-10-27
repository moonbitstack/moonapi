// Structs that describe their own schema, and an app whose request and response
// bodies show up fully typed in `openapi.json`. This is the shape mctl generates
// from a spec: `derive(ToJson, FromJson)` for the wire, and a plain `T::schema()`
// that needs no instance, as FastAPI refers to the model class.

///|
/// A nested value type, to show a `$ref` chain: `User.address` references it
/// under `components/schemas`.
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
/// The request body of `POST /users`. `age` is optional.
struct NewUser {
  name : String
  email : String
  age : Int32?
} derive(FromJson)

///|
fn NewUser::schema() -> @moonapi.Schema {
  @moonapi.Schema::object("NewUser", [
    @moonapi.Field::new("name", SStr, description="the user's display name"),
    @moonapi.Field::new("email", SStr),
    @moonapi.Field::new("age", SInt, required=false),
  ])
}

///|
/// The response of both user routes. It nests `Address` and carries a list, so
/// its schema exercises objects, `$ref`s and arrays together.
struct User {
  id : Int32
  name : String
  email : String
  age : Int32?
  address : Address
  tags : Array[String]
} derive(ToJson)

///|
fn User::schema() -> @moonapi.Schema {
  @moonapi.Schema::object("User", [
    @moonapi.Field::new("id", SInt),
    @moonapi.Field::new("name", SStr),
    @moonapi.Field::new("email", SStr),
    @moonapi.Field::new("age", SInt, required=false),
    @moonapi.Field::new("address", Address::schema()),
    @moonapi.Field::new("tags", @moonapi.Schema::array(SStr)),
  ])
}

///|
/// `POST /users` takes a typed `NewUser` body and returns a `User`; `GET
/// /users/{id}` takes a typed integer path parameter and returns a `User`. Both
/// validate off their descriptor, and both show typed bodies with `$ref`s in the
/// OpenAPI document.
fn users_app() -> @moonapi.App {
  let app = @moonapi.App::new()
  let create = @moonapi.Endpoint::new(request_body=NewUser::schema(), responses=[
    @moonapi.ResponseSpec::new(
      201,
      description="the created user",
      body=User::schema(),
    ),
    @moonapi.ResponseSpec::new(422, description="Validation Error"),
  ])
  app.post(
    "/users",
    ctx => {
      // The body is checked against `NewUser::schema()` and then read into a
      // `NewUser`; a body the schema refuses comes back as a 422.
      match (ctx.body_validated(NewUser::schema()) : Result[NewUser, _]) {
        Err(errs) => @moonapi.unprocessable(errs)
        Ok(body) => {
          let user : User = {
            id: 1,
            name: body.name,
            email: body.email,
            age: body.age,
            address: { city: "Nowhere", zip: "00000", },
            tags: [],
          }
          @moonapi.json(201, Json(user))
        }
      }
    },
    summary="create a user",
    endpoint=create,
  )
  let get_one = @moonapi.Endpoint::new(
    params=[@moonapi.Param::new("id", InPath, schema=SInt)],
    responses=[
      @moonapi.ResponseSpec::new(200, body=User::schema()),
      @moonapi.ResponseSpec::new(404, description="Not Found"),
    ],
  )
  app.get(
    "/users/{id}",
    ctx => {
      let errs = get_one.validate(ctx)
      if errs.length() > 0 {
        @moonapi.unprocessable(errs)
      } else {
        // The descriptor has already checked this is an integer.
        let id = @string.parse_int(ctx.param("id").unwrap()) catch { _ => 0 }
        let user : User = {
          id,
          name: "demo",
          email: "demo@example.com",
          age: None,
          address: { city: "Springfield", zip: "12345", },
          tags: ["a", "b"],
        }
        @moonapi.json(200, Json(user))
      }
    },
    summary="fetch a user",
    endpoint=get_one,
  )
  app
}
