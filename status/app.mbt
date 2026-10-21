///|
/// A plain-text response.
pub fn text(status : Int32, body : String) -> @moonasgi.Response {
  @moonasgi.Response::new(
    status,
    [("content-type", "text/plain; charset=utf-8")],
    @utf8.encode(body),
  )
}

///|
/// An HTML response — what the documentation pages are served as.
pub fn html(status : Int32, body : String) -> @moonasgi.Response {
  @moonasgi.Response::new(
    status,
    [("content-type", "text/html; charset=utf-8")],
    @utf8.encode(body),
  )
}

///|
/// A JSON response serialised from a `Json` value.
pub fn json(status : Int32, value : Json) -> @moonasgi.Response {
  @moonasgi.Response::new(
    status,
    [("content-type", "application/json")],
    @moonjson.dump(value),
  )
}
