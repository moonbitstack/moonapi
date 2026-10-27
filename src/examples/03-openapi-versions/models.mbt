// A small typed API to print in three spec versions. `Widget` nests `Price`,
// so each document shows a named schema and a reference to it — under
// `components/schemas` in 3.x and `definitions` in 2.0.

///|
struct Price {
  amount : Double
  currency : String
} derive(ToJson)

///|
fn Price::schema() -> @moonapi.Schema {
  @moonapi.Schema::object("Price", [
    @moonapi.Field::new("amount", SFloat),
    @moonapi.Field::new("currency", SStr),
  ])
}

///|
struct Widget {
  id : Int32
  name : String
  price : Price
} derive(ToJson)

///|
fn Widget::schema() -> @moonapi.Schema {
  @moonapi.Schema::object("Widget", [
    @moonapi.Field::new("id", SInt),
    @moonapi.Field::new("name", SStr),
    @moonapi.Field::new("price", Price::schema()),
  ])
}

///|
fn widget_app() -> @moonapi.App {
  let app = @moonapi.App::new()
  let one = @moonapi.Endpoint::new(
    params=[@moonapi.Param::new("id", InPath, schema=SInt)],
    responses=[
      @moonapi.ResponseSpec::new(200, body=Widget::schema()),
      @moonapi.ResponseSpec::new(404, description="Not Found"),
    ],
  )
  app.get(
    "/widgets/{id}",
    _ctx => {
      let widget : Widget = {
        id: 1,
        name: "sprocket",
        price: { amount: 9.5, currency: "EUR", },
      }
      @moonapi.json(200, Json(widget))
    },
    summary="fetch a widget",
    tags=["widgets"],
    endpoint=one,
  )
  app
}
