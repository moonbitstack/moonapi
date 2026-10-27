///|
/// A plain-text response.
///
/// ```mbt check
/// test {
///   let reply = @status.text(200, "Hello")
///   assert_eq(reply.header("content-type"), Some("text/plain; charset=utf-8"))
///   assert_eq(reply.body, b"Hello")
/// }
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
/// ```mbt check
/// test {
///   let page = @status.html(200, "<h1>Hello</h1>")
///   assert_eq(page.header("content-type"), Some("text/html; charset=utf-8"))
/// }
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
/// ```mbt check
/// test {
///   let reply = @status.json(200, { "name": "Ada" })
///   assert_eq(reply.header("content-type"), Some("application/json"))
///   assert_eq(reply.body, b"{\"name\":\"Ada\"}")
/// }
/// ```
pub fn json(status : Int32, value : Json) -> @moonasgi.Response {
  @moonasgi.Response::new(
    status,
    [("content-type", "application/json")],
    @moonjson.dump(value),
  )
}
