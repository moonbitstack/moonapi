///|
/// A plain-text response.
///
/// ```mbt
/// app.get("/", _ctx => text(200, "Hello from moonapi"))
/// ```
pub fn text(status : Int32, body : String) -> @moonasgi.Response {
  @moonasgi.Response::new(
    status,
    [("content-type", "text/plain; charset=utf-8")],
    @utf8.encode(body),
  )
}

///|
/// An HTML response — what the documentation pages are served as.
///
/// ```mbt
/// app.get("/page", _ctx => html(200, "<h1>Hello</h1>"))
/// ```
pub fn html(status : Int32, body : String) -> @moonasgi.Response {
  @moonasgi.Response::new(
    status,
    [("content-type", "text/html; charset=utf-8")],
    @utf8.encode(body),
  )
}

///|
/// A JSON response serialised from a `Json` value.
///
/// ```mbt
/// app.get("/me", _ctx =>
///   json(200, Json::object([("name", Json::string("Ada"))])))
/// ```
pub fn json(status : Int32, value : Json) -> @moonasgi.Response {
  @moonasgi.Response::new(
    status,
    [("content-type", "application/json")],
    @moonjson.dump(value),
  )
}
