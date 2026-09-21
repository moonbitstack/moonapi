///|
/// Pydantic-style field constraints and the scalar schema types, emitted into
/// the OpenAPI schema and enforced off one descriptor. Every `Constraint` is
/// exercised — `Minimum` / `Maximum`, `ExclusiveMinimum` / `ExclusiveMaximum`,
/// `MultipleOf`, `MinLength` / `MaxLength`, `Pattern`, `MinItems` / `MaxItems` —
/// alongside the scalar types `SInt` / `SFloat` / `SStr` / `SBool` / `SNull` /
/// `SArray` and a closed `SEnum`. A conforming body validates; a low/short body
/// and a high/long body each return a `422` naming every violation by its
/// pydantic error type.
///
///     moon run examples/05-constraints
#coverage.skip
fn main {
  let color = @moonapi.SEnum(@moonapi.SStr, [
    "red".to_json(),
    "green".to_json(),
    "blue".to_json(),
  ])
  let schema = @moonapi.Schema::object("Order", [
    @moonapi.Field::new("qty", @moonapi.SInt, constraints=[
      @moonapi.Minimum(1.0),
      @moonapi.Maximum(99.0),
    ]),
    @moonapi.Field::new("step", @moonapi.SInt, constraints=[
      @moonapi.MultipleOf(5.0),
    ]),
    @moonapi.Field::new("ratio", @moonapi.SFloat, constraints=[
      @moonapi.ExclusiveMinimum(0.0),
      @moonapi.ExclusiveMaximum(1.0),
    ]),
    @moonapi.Field::new("code", @moonapi.SStr, constraints=[
      @moonapi.MinLength(3),
      @moonapi.MaxLength(8),
      @moonapi.Pattern("^[a-z]+$"),
    ]),
    @moonapi.Field::new("tags", @moonapi.Schema::array(@moonapi.SStr), constraints=[
      @moonapi.MinItems(1),
      @moonapi.MaxItems(3),
    ]),
    @moonapi.Field::new("active", @moonapi.SBool),
    @moonapi.Field::new("color", color),
    // A field whose value must be JSON null.
    @moonapi.Field::new("note", @moonapi.SNull, required=false),
  ])
  let ep = @moonapi.Endpoint::new(request_body=schema)
  let app = @moonapi.App::new()
  app.post(
    "/orders",
    ctx => {
      let errs = ep.validate(ctx)
      if errs.length() > 0 {
        @moonapi.unprocessable(errs)
      } else {
        @moonapi.text(201, "order accepted")
      }
    },
    endpoint=ep,
  )
  let hit = (label : String, body : String) => {
    let req : @moonasgi.Request = {
      http_method: "POST",
      path: "/orders",
      query_string: b"",
      headers: [("content-type", "application/json")],
      body: @utf8.encode(body),
    }
    let r = app.handle(req)
    println("\{label} -> \{r.status} \{@utf8.decode_lossy(r.body[:])}")
  }
  // Within every bound.
  hit(
    "ok  ", "{\"qty\":5,\"step\":10,\"ratio\":0.5,\"code\":\"abc\",\"tags\":[\"a\",\"b\"],\"active\":true,\"color\":\"red\"}",
  )
  // Below the lower bounds, too short, wrong scalar types, off the enum.
  hit(
    "low ", "{\"qty\":0,\"step\":7,\"ratio\":1.5,\"code\":\"AB\",\"tags\":[],\"active\":\"yes\",\"color\":\"pink\",\"note\":5}",
  )
  // Above the upper bounds, too long, too many items.
  hit(
    "high", "{\"qty\":100,\"step\":5,\"ratio\":0.0,\"code\":\"toolongcode\",\"tags\":[\"a\",\"b\",\"c\",\"d\"],\"active\":false,\"color\":\"green\"}",
  )
  println("--- OpenAPI 3.1.0 (constraints + enum in the schema) ---")
  println(app.openapi_json(version=@moonapi.OpenApi31))
}
