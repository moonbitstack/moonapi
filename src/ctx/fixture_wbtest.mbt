///|
/// What a browser would return for a `Set-Cookie` value: the `name=value` pair
/// in front of the first `;`, the attributes being instructions to the client
/// rather than anything it echoes — test helper.
fn echoed_pair(set_cookie : String) -> String {
  for i = 0; i < set_cookie.length(); i = i + 1 {
    if set_cookie[i] == ';' {
      return set_cookie[0:i].to_owned()
    }
  }
  set_cookie
}

///|
/// Read a request's cookie the way a handler does — test helper.
fn read_cookie(header : String, name : String) -> String? {
  let ctx : Context = Context::new(
    {
      http_method: "GET",
      path: "/",
      query_string: b"",
      headers: [("cookie", header)],
      body: b"",
    },
    params=Map([]),
  )
  ctx.cookie(name)
}

///|
/// The loop closes: set it, send it back, read the same value out.
test "cookie round-trips from set_cookie through Set-Cookie to Context::cookie" {
  let resp = @status.set_cookie(@status.text(200, "ok"), "session", "heke1228")
  let header = resp.header("set-cookie").unwrap()
  assert_eq(header, "session=heke1228; Path=/; SameSite=Lax")
  assert_eq(read_cookie(echoed_pair(header), "session"), Some("heke1228"))
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
