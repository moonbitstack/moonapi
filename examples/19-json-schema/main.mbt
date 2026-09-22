///|
/// A body written as JSON Schema (`Schema::json`), for what the descriptor
/// constructors cannot say — here a `pattern` and a closed set. The same
/// document is emitted into the OpenAPI operation and handed to moonschema to
/// validate the request against: one tree, two projections.
///
///     moon run examples/19-json-schema
#coverage.skip
fn main {
  let body = @moonapi.Schema::object("Post", [
    @moonapi.Field::new(
      "slug",
      @moonapi.Schema::json({ "type": "string", "pattern": "^[a-z0-9-]+$" }),
      required=true,
    ),
    @moonapi.Field::new(
      "state",
      @moonapi.Schema::json({ "enum": ["draft", "live"] }),
      required=true,
    ),
  ])
  let app = @moonapi.App::new()
  app.post(
    "/posts",
    ctx => @moonapi.json(201, ctx.body_json().unwrap_or(Json::null())),
    endpoint=@moonapi.Endpoint::new(request_body=body),
  )

  // The document says exactly what was written.
  let doc = app.openapi()
  println(
    "schema: " +
    at(doc, ["components", "schemas", "Post", "properties"]).stringify(),
  )

  // And the same schema decides what the endpoint accepts.
  for
    instance in (
      [
        { "slug": "hello-world", "state": "live" },
        { "slug": "Hello", "state": "soon" },
      ] : Array[Json]) {
    let errs : Array[@moonapi.ValidationError] = []
    @moonapi.validate_schema(body, instance, [], errs)
    println(
      instance.stringify() + " -> " + errs.length().to_string() + " error(s)",
    )
    for err in errs {
      println("    " + err.loc.join("/") + " " + err.kind + ": " + err.msg)
    }
  }
}

///|
/// One step at a time down a document.
fn at(doc : Json, path : Array[String]) -> Json {
  let mut here = doc
  for step in path {
    here = match here {
      Object(members) =>
        match members.get(step) {
          Some(next) => next
          None => return Json::null()
        }
      _ => return Json::null()
    }
  }
  here
}
