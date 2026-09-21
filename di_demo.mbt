// A worked example wiring the two new pieces together: a dependency provides a
// value, a typed request body is deserialised + validated off its descriptor,
// and the handler uses both — FastAPI's `def greet(body: GreetReq, greeter: str
// = Depends(...))` in explicit MoonBit form.

///|
/// The request body of `POST /greet`. `derive(@json.FromJson)` lets
/// `Context::body_validated` build it after the descriptor accepts the payload;
/// its schema and struct fields agree (both require `name`), so a schema-valid
/// body always deserialises.
pub(all) struct GreetReq {
  name : String
} derive(ToJson, FromJson, Eq)

///|
/// The `GreetReq` descriptor — one required string field.
pub fn GreetReq::schema() -> Schema {
  Schema::object("GreetReq", [Field::new("name", SStr)])
}

///|
/// The dependency value type of the greet app. A sum type wrapping every
/// dependency this app injects — the explicit, exhaustive stand-in for FastAPI
/// resolving heterogeneous `Depends` values dynamically.
pub(all) enum Dep {
  Greeting(String)
} derive(Eq)

///|
/// Build the greet application over a caller-supplied dependency `container`, so
/// a test can register `dependency_overrides` on the same container before or
/// between requests. `POST /greet` resolves the `"greeting"` dependency, reads a
/// validated `GreetReq` body, and answers `{"message": "<greeting>, <name>"}`;
/// a malformed body gets a FastAPI-shaped `422`. The dependency scope brackets
/// each request, so any `yield` teardown runs once the handler returns.
pub fn greet_app(container : Container[Dep]) -> App {
  let app = App::new()
  let ep = Endpoint::new(request_body=GreetReq::schema(), responses=[
    ResponseSpec::new(200, description="the greeting"),
    ResponseSpec::new(422, description="Validation Error"),
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
          Err(errs) => unprocessable(errs)
          Ok(req) => {
            let m : Map[String, Json] = Map([
              ("message", "\{greeting}, \{req.name}".to_json()),
            ])
            json(200, m.to_json())
          }
        }
      })
    },
    summary="greet a user",
    endpoint=ep,
  )
  app
}

///|
pub extend GreetReq with Eq::{not_equal, equal}

///|
pub extend GreetReq with FromJson::{from_json}

///|
pub extend GreetReq with ToJson::{to_json}

///|
pub extend Dep with Eq::{not_equal, equal}
