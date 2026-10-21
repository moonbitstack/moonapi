///|
/// The value of `name`, or "<none>" when the key is absent — keeps the assertions
/// on plain strings.
fn q(c : @ctx.Context, name : String) -> String {
  match c.query(name) {
    Some(v) => v
    None => "<none>"
  }
}

///|
/// A `Context` carrying nothing but a query string — enough to exercise `query`.
fn qctx(query : Bytes) -> @ctx.Context {
  let req : @moonasgi.Request = {
    http_method: "GET",
    path: "/",
    query_string: query,
    headers: [],
    body: b"",
  }
  { request: req, params: Map([]), }
}
