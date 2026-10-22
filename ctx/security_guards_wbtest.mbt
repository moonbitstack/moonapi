///|
/// A request carrying arbitrary `headers`, and optionally a query string —
/// test helper.
fn mkreq_hdrs(
  verb : String,
  path : String,
  headers : Array[(String, String)],
  query~ : Bytes = b"",
) -> @moonasgi.Request {
  { http_method: verb, path, query_string: query, headers, body: b"", }
}

///|
test "http digest: the scheme name is matched case-insensitively, others ignored" {
  let ctx : Context = {
    request: mkreq_hdrs("GET", "/x", [("authorization", "DIGEST nc=00000001")]),
    params: Map([]),
  }
  assert_eq(ctx.digest_credentials(), Some("nc=00000001"))
  let bearer : Context = {
    request: mkreq_hdrs("GET", "/x", [("authorization", "Bearer abc")]),
    params: Map([]),
  }
  assert_eq(bearer.digest_credentials() is None, true)
}
