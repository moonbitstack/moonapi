///|
/// The value of `name`, or "<none>" when the key is absent — keeps the assertions
/// on plain strings.
fn q(c : @ctx.Context, name : String) -> String {
  match c.query(name) {
    Some(v) => v
    None => "<none>"
  }
}

///|
/// A `Context` carrying nothing but a query string — enough to exercise `query`.
fn qctx(query : Bytes) -> @ctx.Context {
  let req : @moonasgi.Request = {
    http_method: "GET",
    path: "/",
    query_string: query,
    headers: [],
    body: b"",
  }
  { request: req, params: Map([]), }
}

// A worked example of the descriptor tree: user structs that describe their own
// schema, an `impl ToSchema`, and a demo app whose request/response bodies show
// up fully-typed in `openapi.json`. This is the mctl-friendly shape — mctl would
// generate exactly this from a spec: `derive(ToJson)` for serialisation plus a
// plain `T::schema()` associated function (no instance needed, mirroring FastAPI
// referencing the model class) and its one-line `ToSchema` bridge.

///|
/// A nested value type, to show a `$ref` chain: `User.address` references this
/// under `components/schemas`.
struct Address {
  city : String
  zip : String
} derive(ToJson, Eq)

///|
/// The `Address` descriptor.
fn Address::schema() -> @schema.Schema {
  @schema.Schema::object("Address", [
    @schema.Field::new("city", SStr),
    @schema.Field::new("zip", SStr),
  ])
}

///|
/// `Address`'s schema, so a route declaring it as a body or response documents itself.
impl @schema.ToSchema for Address with fn to_schema(_self) {
  Address::schema()
}

///|
/// The `NewUser` descriptor.
fn new_user_schema() -> @schema.Schema {
  @schema.Schema::object("NewUser", [
    @schema.Field::new("name", SStr, description="the user's display name"),
    @schema.Field::new("email", SStr),
    @schema.Field::new("age", SInt, required=false),
  ])
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
fn User::schema() -> @schema.Schema {
  @schema.Schema::object("User", [
    @schema.Field::new("id", SInt),
    @schema.Field::new("name", SStr),
    @schema.Field::new("address", Address::schema()),
    @schema.Field::new("tags", @schema.Schema::array(SStr)),
  ])
}

///|
/// `User`'s schema, so a route declaring it as a body or response documents itself.
impl @schema.ToSchema for User with fn to_schema(_self) {
  User::schema()
}

///|
/// A demo application exercising the descriptor tree end to end: `POST /users`
/// takes a typed `NewUser` body and returns a `User`; `GET /users/:id` takes a
/// typed integer path param and returns a `User`. Both validate off their
/// descriptor and both surface fully-typed bodies (with `components/schemas`
/// `$ref`s) in `openapi.json`.
fn demo_app() -> App {
  let app = App::new()
  let create = @endpoint.Endpoint::new(request_body=new_user_schema(), responses=[
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

// A worked example wiring the two new pieces together: a dependency provides a
// value, a typed request body is deserialised + validated off its descriptor,
// and the handler uses both — FastAPI's `def greet(body: GreetReq, greeter: str
// = Depends(...))` in explicit MoonBit form.

///|
/// The request body of `POST /greet`. `derive(@json.FromJson)` lets
/// `Context::body_validated` build it after the descriptor accepts the payload;
/// its schema and struct fields agree (both require `name`), so a schema-valid
/// body always deserialises.
struct GreetReq {
  name : String
} derive(ToJson, FromJson, Eq)

///|
/// The `GreetReq` descriptor — one required string field.
fn GreetReq::schema() -> @schema.Schema {
  @schema.Schema::object("GreetReq", [@schema.Field::new("name", SStr)])
}

///|
/// The dependency value type of the greet app. A sum type wrapping every
/// dependency this app injects — the explicit, exhaustive stand-in for FastAPI
/// resolving heterogeneous `Depends` values dynamically.
enum Dep {
  Greeting(String)
} derive(Eq)

///|
/// Build the greet application over a caller-supplied dependency `container`, so
/// a test can register `dependency_overrides` on the same container before or
/// between requests. `POST /greet` resolves the `"greeting"` dependency, reads a
/// validated `GreetReq` body, and answers `{"message": "<greeting>, <name>"}`;
/// a malformed body gets a FastAPI-shaped `422`. The dependency scope brackets
/// each request, so any `yield` teardown runs once the handler returns.
fn greet_app(container : @di.Container[Dep]) -> App {
  let app = App::new()
  let ep = @endpoint.Endpoint::new(request_body=GreetReq::schema(), responses=[
    @endpoint.ResponseSpec::new(200, description="the greeting"),
    @endpoint.ResponseSpec::new(422, description="Validation Error"),
  ])
  app.post(
    "/greet",
    ctx => {
      container.run(scope => {
        let greeting = match scope.get("greeting") {
          Some(Greeting(g)) => g
          None => "Hello"
        }
        match (ctx.body_validated(GreetReq::schema()) : Result[GreetReq, _]) {
          Err(errs) => @schema.unprocessable(errs)
          Ok(req) => {
            let m : Map[String, Json] = Map([
              ("message", Json("\{greeting}, \{req.name}")),
            ])
            @status.json(200, Json(m))
          }
        }
      })
    },
    summary="greet a user",
    endpoint=ep,
  )
  app
}

// A worked OAuth2 password-bearer app — FastAPI's security tutorial in explicit
// MoonBit form. `POST /token` reads the password form, checks the demo
// credentials, and issues a scoped HS256 JWT; `GET /users/me` is protected by a
// bearer `Security` with no scope requirement; `GET /users/me/items` additionally
// requires the `items` scope. The verification clock is injected (`now`) so the
// same app runs deterministically in a test and against the wall clock in
// production.

///|
/// Check the demo credentials. A real app would look the user up and verify a
/// password hash; here one hard-coded account keeps the example self-contained.
fn authenticate_user(username : String, password : String) -> Bool {
  username == "alice" && password == "wonderland"
}

///|
/// Build the OAuth2 demo application. `secret` is the shared HS256 key; `now`
/// supplies the current Unix time (seconds) for both issuing and verifying, so a
/// caller controls time in tests. Tokens live for one hour.
fn oauth2_app(now : () -> Int64, secret~ : String = "demo-secret") -> App {
  let app = App::new()
  let scheme = @security.OAuth2PasswordBearer::new("/token", secret)
  app.post(
    "/token",
    ctx => {
      match ctx.oauth2_password_form() {
        None =>
          @schema.unprocessable([
            @schema.ValidationError::missing(["body", "username"]),
          ])
        Some(form) =>
          if authenticate_user(form.username, form.password) {
            let token = @security.create_access_token(
              form.username,
              secret,
              now(),
              scopes=form.scopes,
            )
            @security.token_response(token)
          } else {
            let body : Map[String, Json] = Map([
              ("detail", Json("Incorrect username or password")),
            ])
            @moonasgi.Response::new(
              401,
              [
                ("content-type", "application/json"),
                ("www-authenticate", "Bearer"),
              ],
              @moonjson.dump(Json(body)),
            )
          }
      }
    },
    summary="issue an access token",
  )
  app.get(
    "/users/me",
    ctx => {
      match scheme.authenticate(ctx, now()) {
        Err(resp) => resp
        Ok(user) => {
          let scopes : Array[Json] = []
          for s in user.scopes {
            scopes.push(Json(s))
          }
          let body : Map[String, Json] = Map([
            ("username", Json(user.subject)),
            ("scopes", Json(scopes)),
          ])
          @status.json(200, Json(body))
        }
      }
    },
    summary="the current user",
  )
  app.get(
    "/users/me/items",
    ctx => {
      match scheme.authenticate(ctx, now(), scopes=["items"]) {
        Err(resp) => resp
        Ok(user) => {
          let body : Map[String, Json] = Map([
            ("owner", Json(user.subject)),
            ("items", Json(["hammer", "nail"])),
          ])
          @status.json(200, Json(body))
        }
      }
    },
    summary="the current user's items (scope: items)",
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
pub extend User with Eq::{not_equal, equal}

///|
pub extend User with ToJson::{to_json}

///|
pub extend User with @schema.ToSchema::{to_schema}

///|
pub extend GreetReq with Eq::{not_equal, equal}

///|
pub extend GreetReq with FromJson::{from_json}

///|
pub extend GreetReq with ToJson::{to_json}

///|
pub extend Dep with Eq::{not_equal, equal}
