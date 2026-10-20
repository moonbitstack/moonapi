// A model described once, in moonmodel's vocabulary, then used twice here:
// to validate an inbound body and to write the OpenAPI document. The same
// description produces the SQL columns in moonorm and the SDL in moongql.

///|
fn address() -> @moonmodel.Model {
  @moonmodel.Model::new("Address", [
    @moonmodel.Field::new("city", Text),
    @moonmodel.Field::new(
      "country",
      Text,
      check=@moonmodel.Check::new(shortest=2, longest=2),
    ),
  ])
}

///|
fn order() -> @moonmodel.Model {
  @moonmodel.Model::new(
    "Order",
    [
      @moonmodel.Field::new(
        "qty",
        Int,
        doc="how many",
        check=@moonmodel.Check::new(least=1.0, most=99.0),
      ),
      @moonmodel.Field::new(
        "code",
        Text,
        check=@moonmodel.Check::new(shortest=3, longest=8, pattern="^[a-z]+$"),
      ),
      @moonmodel.Field::new(
        "colour",
        Text,
        check=@moonmodel.Check::new(options=[Json("red"), Json("blue")]),
      ),
      @moonmodel.Field::new("ship_to", Ref("Address")),
      @moonmodel.Field::new("note", Text, required=false, nullable=true),
    ],
    doc="something somebody bought",
  )
}

///|
fn main {
  // `known` is where a reference is looked up. Address is in it, so the
  // schema is written out and the document ends up with a $ref to it.
  let (schema, unresolved) = @moonapi.Schema::of_model(order(), known=[
    address(),
  ])
  for one in unresolved {
    println("unresolved \{one.field} -> \{one.model}: \{one.why}")
  }
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
    summary="place an order",
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
  println("── validation, from the same description ──")
  hit(
    "within  ", "{\"qty\":5,\"code\":\"abc\",\"colour\":\"red\",\"ship_to\":{\"city\":\"Wuhan\",\"country\":\"CN\"}}",
  )
  hit(
    "outside ", "{\"qty\":0,\"code\":\"AB\",\"colour\":\"teal\",\"ship_to\":{\"city\":\"Wuhan\",\"country\":\"CHN\"}}",
  )
  // A nullable field may be null; one that is absent is a different matter,
  // which is why the description keeps the two apart.
  hit(
    "null note", "{\"qty\":1,\"code\":\"abc\",\"colour\":\"blue\",\"ship_to\":{\"city\":\"Wuhan\",\"country\":\"CN\"},\"note\":null}",
  )
  println("")
  println("── the document, from the same description ──")
  println(app.openapi_json(version=OpenApi31))
  // A reference nobody declared cannot be written: a name alone does not say
  // what the thing looks like, so it is reported rather than guessed at.
  println("")
  println("── what cannot be written says so ──")
  let (_, missing) = @moonapi.Schema::of_model(order())
  for one in missing {
    println("\{one.field} -> \{one.model}: \{one.why}")
  }
}
