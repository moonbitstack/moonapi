///|
/// `response_model` — a route holds a richer object than it exposes. `json_model`
/// validates a handler's return value against a declared `Schema` and projects it
/// down to exactly the model's fields, so an internal `password_hash` / `email`
/// never reach the wire; `filter_response` is the same check returning the
/// filtered `Json` or the located errors. `schema_of` reaches a type's descriptor
/// through the `ToSchema` bridge, and `validate_schema` is the low-level conformance
/// check both request and response validation share.
///
///     moon run examples/08-response-model
#coverage.skip
fn main {
  let public_user = @moonapi.Schema::object("PublicUser", [
    @moonapi.Field::new("id", SInt),
    @moonapi.Field::new("name", SStr),
  ])
  let app = @moonapi.App::new()
  app.get("/me", _ctx => {
    // The handler builds a full record; the model decides what leaves.
    let internal : Json = {
      let m : Map[String, Json] = Map([
        ("id", Json(233)),
        ("name", Json("lfanke")),
        ("password_hash", Json("deadbeef")),
        ("email", Json("lfanke@example.com")),
      ])
      Json(m)
    }
    @moonapi.json_model(200, public_user, internal)
  })
  let req : @moonasgi.Request = {
    http_method: "GET",
    path: "/me",
    query_string: b"",
    headers: [],
    body: b"",
  }
  let r = app.handle(req)
  println("GET /me -> \{r.status} \{@utf8.decode_lossy(r.body[:])}")

  // filter_response directly: conforming value keeps only declared fields.
  let ok : Json = {
    let m : Map[String, Json] = Map([
      ("id", Json(1)),
      ("name", Json("qwq")),
      ("secret", Json("hidden")),
    ])
    Json(m)
  }
  match @moonapi.filter_response(public_user, ok) {
    Ok(filtered) => println("filtered -> \{filtered.stringify()}")
    Err(_) => println("unexpected error")
  }

  // A value of the wrong shape (name is a number) fails the model: a 500 body,
  // since a broken return value is a server fault, not the client's.
  let bad : Json = {
    let m : Map[String, Json] = Map([("id", Json(1)), ("name", Json(0))])
    Json(m)
  }
  match @moonapi.filter_response(public_user, bad) {
    Ok(_) => println("unexpected pass")
    Err(errs) =>
      println("rejected -> \{@moonapi.validation_error_body(errs).stringify()}")
  }

  // validate_schema is the shared conformance check underneath.
  let errs : Array[@moonapi.ValidationError] = []
  @moonapi.validate_schema(public_user, ok, ["body"], errs)
  println("validate_schema(ok) errors = \{errs.length()}")

  // schema_of reaches a struct's descriptor through the ToSchema bridge — the
  // same tree its associated `schema()` returns.
  let user : @moonapi.User = {
    id: 233,
    name: "lfanke",
    address: { city: "emm", zip: "23333", },
    tags: ["a", "b"],
  }
  println(
    "schema_of(user) == User::schema(): \{@moonapi.schema_of(user) == @moonapi.User::schema()}",
  )
}
