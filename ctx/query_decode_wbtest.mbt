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
  { request: req, params: Map([]), }
}

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
test "query percent-decodes keys and values" {
  let c = qctx(b"q=hello%20world&name=heke1228&plus=a+b")
  inspect(q(c, "q"), content="hello world")
  inspect(q(c, "name"), content="heke1228")
  inspect(q(c, "plus"), content="a b")
  inspect(q(c, "absent"), content="<none>")
}

///|
test "query splits on raw bytes so escaped separators survive" {
  // `%26` is an escaped `&` and `%3D` an escaped `=`; neither may split the pair.
  let c = qctx(b"filter=a%26b%3Dc&next=qwq")
  inspect(q(c, "filter"), content="a&b=c")
  inspect(q(c, "next"), content="qwq")
}

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
