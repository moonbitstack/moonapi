// response_model — validate and filter a handler's return value through a
// declared model before it goes on the wire (FastAPI's `response_model=`). The
// return value is checked against the same `Schema` descriptor that drives
// request validation and OpenAPI emission, then projected down to exactly the
// model's declared fields: anything extra (an internal id, a hashed password) is
// dropped, so a route can return a richer object than it exposes. A value that
// doesn't conform is a server bug, so it surfaces as a 500, matching FastAPI's
// `ResponseValidationError`.

///|
/// Keep only what `model` declares, recursively: for an object, drop keys the
/// model doesn't list and project each declared field through its own schema;
/// for an array, project every element through the item schema; a scalar passes
/// through unchanged. Assumes `value` already validated against `model`, so a
/// declared field that's missing here simply isn't emitted.
fn project_through(model : Schema, value : Json) -> Json {
  match (model, value) {
    (SObject(os), Object(m)) => {
      let out : Map[String, Json] = Map([])
      for f in os.fields {
        match m.get(f.name) {
          Some(v) => out[f.name] = project_through(f.schema, v)
          None => ()
        }
      }
      Json(out)
    }
    (SArray(item), Array(a)) => {
      let out : Array[Json] = []
      for v in a {
        out.push(project_through(item, v))
      }
      Json(out)
    }
    _ => value
  }
}

///|
/// Validate `value` against `model` and, if it conforms, return it filtered down
/// to the model's declared fields (extras dropped, nested objects and arrays
/// projected too). On a mismatch return the located `ValidationError`s under
/// `["response"]` — the same shape request validation produces. This is FastAPI's
/// `response_model`: the outgoing shape is the model, not whatever the handler
/// happened to build.
pub fn filter_response(
  model : Schema,
  value : Json,
) -> Result[Json, Array[ValidationError]] {
  let errs : Array[ValidationError] = []
  validate_schema(model, value, ["response"], errs)
  if errs.length() > 0 {
    Err(errs)
  } else {
    Ok(project_through(model, value))
  }
}

///|
/// A JSON response whose body is `value` filtered through `model`. On success a
/// `status` response carrying only the model's declared fields; on a model
/// mismatch a `500` whose body lists the response-validation errors — the return
/// value didn't match what the route promised, which is a server-side fault.
pub fn json_model(
  status : Int32,
  model : Schema,
  value : Json,
) -> @moonasgi.Response {
  match filter_response(model, value) {
    Ok(filtered) => json(status, filtered)
    Err(errs) => json(500, validation_error_body(errs))
  }
}
