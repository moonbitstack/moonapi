// The response half of cookies. A round-trip here means the whole loop: what
// `set_cookie` writes into `Set-Cookie` is what a browser would send back in
// `Cookie`, and what `Context::cookie` then reads.

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
  let ctx : Context = {
    request: {
      http_method: "GET",
      path: "/",
      query_string: b"",
      headers: [("cookie", header)],
      body: b"",
    },
    params: Map([]),
  }
  ctx.cookie(name)
}

///|
/// The loop closes: set it, send it back, read the same value out.
test "cookie round-trips from set_cookie through Set-Cookie to Context::cookie" {
  let resp = set_cookie(text(200, "ok"), "session", "heke1228")
  let header = resp.header("set-cookie").unwrap()
  assert_eq(header, "session=heke1228; Path=/; SameSite=Lax")
  assert_eq(read_cookie(echoed_pair(header), "session"), Some("heke1228"))
}

///|
/// Every attribute renders, in RFC 6265 §4.1.1's order.
test "set_cookie renders its attributes in the canonical order" {
  let resp = set_cookie(
    text(200, "ok"),
    "sid",
    "qwq",
    max_age=3600,
    expires=@moondate.Moment::Zoned(
      date=@moondate.Date::new(2026, 10, 21),
      time=@moondate.Time::new(7, 28),
      zone=Utc,
    ),
    path=Some("/api"),
    domain="example.test",
    secure=true,
    http_only=true,
    same_site=Some(Strict),
  )
  assert_eq(
    resp.header("set-cookie"),
    Some(
      "sid=qwq; Expires=Wed, 21 Oct 2026 07:28:00 GMT; Max-Age=3600; Domain=example.test; Path=/api; Secure; HttpOnly; SameSite=Strict",
    ),
  )
}

///|
/// The wire spelling of `Unrestricted` is `None`, and omitting `same_site`
/// entirely is a third thing again — no attribute at all.
test "set_cookie SameSite: Unrestricted is None on the wire, and can be omitted" {
  assert_eq(
    set_cookie(
      text(200, "ok"),
      "a",
      "1",
      same_site=Some(Unrestricted),
      secure=true,
    ).header("set-cookie"),
    Some("a=1; Path=/; Secure; SameSite=None"),
  )
  assert_eq(
    set_cookie(text(200, "ok"), "a", "1", same_site=None).header("set-cookie"),
    Some("a=1; Path=/"),
  )
}

///|
/// A `path` of `None` drops the attribute, which scopes the cookie to the
/// request's own directory rather than the whole site.
test "set_cookie with no path omits Path" {
  assert_eq(
    set_cookie(text(200, "ok"), "a", "1", path=None).header("set-cookie"),
    Some("a=1; SameSite=Lax"),
  )
}

///|
/// `Set-Cookie` is the one header a proxy may not fold on commas, so two cookies
/// have to be two headers.
test "two cookies are two Set-Cookie headers, not one merged field" {
  let resp = set_cookie(set_cookie(text(200, "ok"), "a", "1"), "b", "2")
  let cookies = resp.headers.filter(h => h.0 == "set-cookie")
  assert_eq(cookies.length(), 2)
  assert_eq(cookies[0].1, "a=1; Path=/; SameSite=Lax")
  assert_eq(cookies[1].1, "b=2; Path=/; SameSite=Lax")
}

///|
/// Each call returns a new response, so a handler can hand the same base to two
/// callers and give them different cookies.
test "set_cookie leaves the response it was given alone" {
  let base = text(200, "ok")
  let before = base.headers.length()
  let _ = set_cookie(base, "a", "1")
  assert_eq(base.headers.length(), before)
  assert_eq(base.header("set-cookie"), None)
}

///|
/// Expiring a cookie is setting an empty one that is already stale, both ways a
/// browser measures staleness.
test "delete_cookie expires the cookie by Max-Age and by date" {
  let resp = delete_cookie(text(200, "ok"), "session")
  assert_eq(
    resp.header("set-cookie"),
    Some(
      "session=; Expires=Thu, 01 Jan 1970 00:00:00 GMT; Max-Age=0; Path=/; SameSite=Lax",
    ),
  )
}

///|
/// A cookie is identified by name, domain and path together, so a deletion has
/// to repeat the scope that set it or it will miss.
test "delete_cookie carries the scope it is given" {
  assert_eq(
    delete_cookie(
      text(200, "ok"),
      "sid",
      path=Some("/api"),
      domain="example.test",
    ).header("set-cookie"),
    Some(
      "sid=; Expires=Thu, 01 Jan 1970 00:00:00 GMT; Max-Age=0; Domain=example.test; Path=/api; SameSite=Lax",
    ),
  )
}

///|
/// A cookie value is attacker-supplied often enough — a username, a returned
/// token — that it must not be able to write an attribute or a second header.
test "a cookie value cannot forge an attribute or open a header" {
  // `;` and the space are dropped, so the smuggled `Domain` stays inside the
  // value instead of becoming an attribute of its own.
  let forged = set_cookie(text(200, "ok"), "sid", "a; Domain=evil.test")
  assert_eq(
    forged.header("set-cookie"),
    Some("sid=aDomain=evil.test; Path=/; SameSite=Lax"),
  )
  // CRLF cannot survive either, so there is no second header to open.
  let split = set_cookie(text(200, "ok"), "sid", "a\r\nSet-Cookie: evil=1")
  assert_eq(
    split.header("set-cookie"),
    Some("sid=aSet-Cookie:evil=1; Path=/; SameSite=Lax"),
  )
  assert_eq(split.headers.filter(h => h.0 == "set-cookie").length(), 1)
}
