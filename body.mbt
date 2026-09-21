///|
/// Deserialise the JSON request body into a user type `T`, `None` when the body
/// is absent, is not valid JSON, or does not shape-match `T`. This is the
/// unchecked, best-effort extractor — the total counterpart of writing
/// `item: Item` on a FastAPI handler when you don't want the framework's 422.
/// `T` describes itself with `derive(@json.FromJson)`; the deserialisation is
/// core's, so it stays faithful to the JSON shape without any reflection.
pub fn[T : @json.FromJson] Context::body(self : Context) -> T? {
  match self.body_json() {
    None => None
    Some(j) => Some(@json.from_json(j)) catch { _ => None }
  }
}

///|
/// The validated typed-body extractor — the faithful equivalent of FastAPI
/// declaring a pydantic model parameter: the body is checked against the
/// endpoint's descriptor `schema` (the same tree that emits the OpenAPI body
/// schema), and only if it conforms is it deserialised into `T`. On failure it
/// yields the FastAPI-shaped `ValidationError` list (located under `["body",
/// ...]`), ready for `unprocessable`; on success it yields the built `T`.
///
/// Reusing `validate_schema` here is the point of the descriptor tree: schema
/// emission, request validation, and typed deserialisation are all driven off
/// one source of truth, exactly as pydantic derives all three from one model.
/// Because validation runs first, `@json.from_json` is reached only for a
/// shape-conforming value; the final `catch` keeps the extractor total for the
/// residual cases a scalar schema cannot express (e.g. an out-of-range integer).
pub fn[T : @json.FromJson] Context::body_validated(
  self : Context,
  schema : Schema,
) -> Result[T, Array[ValidationError]] {
  let raw = decode_field(self.request.body)
  if raw == "" {
    return Err([ValidationError::missing(["body"])])
  }
  let j = @moonjson.loads(raw[:], @moonjson.strict) catch {
    _ =>
      return Err([
        ValidationError::type_error(
          ["body"],
          "json_invalid",
          "Input should be valid JSON",
        ),
      ])
  }
  let errs : Array[ValidationError] = []
  validate_schema(schema, j, ["body"], errs)
  if errs.length() > 0 {
    return Err(errs)
  }
  let parsed : T? = Some(@json.from_json(j)) catch { _ => None }
  match parsed {
    Some(v) => Ok(v)
    None =>
      Err([
        ValidationError::type_error(
          ["body"],
          "model_type",
          "Input should be a valid object",
        ),
      ])
  }
}
