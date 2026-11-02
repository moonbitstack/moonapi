///|
/// A type that answers the methods of one path. `Item` answers GET, PUT and
/// DELETE at `/items/{id}`; `app.view` registers each method it answers, and a
/// method it leaves out answers 405 with `Allow` naming the ones it does.
///
///     moon run src/examples/20-views
#coverage.skip
async fn main {
  let app = @moonapi.App::new()
  app.view("/items/{id}", Item::{ shelf: "A", }, tags=["items"])
  for verb in ["GET", "PUT", "DELETE", "POST"] {
    let r = app.handle({
      http_method: verb,
      path: "/items/7",
      query_string: b"",
      headers: [],
      body: b"",
    })
    let allow = r.headers
      .iter()
      .filter(h => h.0 == "allow")
      .map(h => " allow=" + h.1)
      .collect()
      .join("")
    println(
      "\{verb} /items/7 -> \{r.status} \{@utf8.decode_lossy(r.body[:])}\{allow}",
    )
  }
}

///|
priv struct Item {
  shelf : String
}

///|
impl @moonapi.View for Item with fn get(self) {
  Some(ctx => {
    @moonapi.text(200, "item " + ctx.param("id").unwrap() + " on " + self.shelf)
  })
}

///|
impl @moonapi.View for Item with fn put(_) {
  Some(_ctx => @moonapi.text(200, "replaced"))
}

///|
impl @moonapi.View for Item with fn delete(_) {
  Some(_ctx => @moonapi.text(204, ""))
}
