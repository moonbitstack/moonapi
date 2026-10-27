///|
/// The value of `name`, or "<none>" when the key is absent — keeps the assertions
/// on plain strings.
fn q(c : Context, name : String) -> String {
  match c.query(name) {
    Some(v) => v
    None => "<none>"
  }
}

///|
/// A `Context` carrying nothing but a query string — enough to exercise `query`.
fn qctx(query : Bytes) -> Context {
  let req : @moonasgi.Request = {
    http_method: "GET",
    path: "/",
    query_string: query,
    headers: [],
    body: b"",
  }
  Context::new(req, params=Map([]))
}

// A worked example of the descriptor tree: user structs that describe their own
// schema, an `impl ToSchema`, and a demo app whose request/response bodies show
// up fully-typed in `openapi.json`. This is the mctl-friendly shape — mctl would
// generate exactly this from a spec: `derive(ToJson)` for serialisation plus a
// plain `T::schema()` associated function (no instance needed, mirroring FastAPI
// referencing the model class) and its one-line `ToSchema` bridge.

///|
test "query_all reads every value of a repeated key" {
  let c = qctx(b"tag=emm&tag=hhh&tag=qwq&other=233")
  let mut joined = ""
  for v in c.query_all("tag") {
    joined = joined + v + ";"
  }
  inspect(joined, content="emm;hhh;qwq;")
  inspect(q(c, "tag"), content="emm")
  inspect(c.query_all("absent").length(), content="0")
}

///|
/// The bound on a query string is the caller's to set, and the preset is the
/// one Express carries: `qs` allows a thousand parameters by default.
test "the query bound is public and reaches both extractors" {
  inspect(@schema.query_limits.pairs, content="1000")
  let many = StringBuilder()
  for i in 0..<40 {
    if i > 0 {
      many.write_char('&')
    }
    many.write_string("tag=\{i}")
  }
  let c = qctx(@utf8.encode(many.to_string()[:]))
  // Under the preset, all forty are there.
  inspect(c.query_all("tag").length(), content="40")
  inspect(q(c, "tag"), content="0")
  // Under a bound of eight, the query is refused rather than truncated, and an
  // extractor that cannot answer answers nothing.
  let tight = @moonurl.Limits::new(pairs=8)
  inspect(c.query_all("tag", limits=tight).length(), content="0")
  inspect(c.query("tag", limits=tight) is None, content="true")
  // And a bound it fits under changes nothing.
  inspect(
    c.query_all("tag", limits=@moonurl.Limits::new(pairs=100)).length(),
    content="40",
  )
}

///|
test "last_event_id: a reconnect carries it, a first connection does not" {
  let with_id = (headers : Array[(String, String)]) => {
    let req : @moonasgi.Request = {
      http_method: "GET",
      path: "/events",
      query_string: b"",
      headers,
      body: b"",
    }
    Context::new(req)
  }
  assert_eq(with_id([("last-event-id", "233")]).last_event_id(), Some("233"))
  assert_eq(with_id([]).last_event_id(), None)
  assert_eq(with_id([("last-event-id", "")]).last_event_id(), None)
}

///|
test "cookie extraction off the Cookie header" {
  let req : @moonasgi.Request = {
    http_method: "GET",
    path: "/",
    query_string: b"",
    headers: [("cookie", "session=abc123; theme=dark")],
    body: b"",
  }
  let ctx : Context = Context::new(req, params=Map([]))
  assert_eq(ctx.cookie("session"), Some("abc123"))
  assert_eq(ctx.cookie("theme"), Some("dark"))
  assert_eq(ctx.cookie("absent"), None)
}
