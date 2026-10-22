///|
/// A request with a body and a content type, for the extractors that read one.
fn mkreq_ct(
  verb : String,
  content_type : String,
  body : Bytes,
) -> @moonasgi.Request {
  {
    http_method: verb,
    path: "/",
    query_string: b"",
    headers: [("content-type", content_type)],
    body,
  }
}

///|
/// A request with an `Authorization` header and no body — test helper.
fn mkreq_auth(
  verb : String,
  path : String,
  authorization : String,
) -> @moonasgi.Request {
  {
    http_method: verb,
    path,
    query_string: b"",
    headers: [("authorization", authorization)],
    body: b"",
  }
}

///|
test "security: HTTP Basic auth parses username and password from the Authorization header" {
  // RFC 7617 §2 example: "Aladdin:open sesame".
  guard parse_basic_auth("Basic QWxhZGRpbjpvcGVuIHNlc2FtZQ==") is Some(creds) else {
    fail("expected credentials")
  }
  assert_eq(creds.username, "Aladdin")
  assert_eq(creds.password, "open sesame")
  // The scheme name is case-insensitive.
  guard parse_basic_auth("basic QWxhZGRpbjpvcGVuIHNlc2FtZQ==") is Some(lower) else {
    fail("expected credentials for a lowercase scheme")
  }
  assert_eq(lower.username, "Aladdin")
  // A password containing a colon splits only on the first one.
  guard parse_basic_auth("Basic dTpwOnE=") is Some(colonpw) else {
    fail("expected credentials")
  }
  // "u:p:q" → username "u", password "p:q".
  assert_eq(colonpw.username, "u")
  assert_eq(colonpw.password, "p:q")
  // A non-Basic scheme, or a value with no colon, yields None.
  assert_eq(parse_basic_auth("Bearer abc") is None, true)
  assert_eq(parse_basic_auth("Basic bm9jb2xvbg==") is None, true)
}

///|
test "bearer_token: parses Bearer, case-insensitive scheme, rejects others" {
  fn ctx_with(auth : String) -> Context {
    { request: mkreq_auth("GET", "/", auth), params: Map([]), }
  }

  assert_eq(ctx_with("Bearer abc.def.ghi").bearer_token(), Some("abc.def.ghi"))
  assert_eq(ctx_with("bearer tok").bearer_token(), Some("tok"))
  assert_eq(ctx_with("BEARER tok").bearer_token(), Some("tok"))
  assert_eq(ctx_with("Basic dXNlcg==").bearer_token(), None)
  // Absent header entirely.
  let bare : Context = {
    request: {
      http_method: "GET",
      path: "/",
      query_string: b"",
      headers: [],
      body: b"",
    },
    params: Map([]),
  }
  assert_eq(bare.bearer_token(), None)
}

///|
test "oauth2_password_form: parses username / password / scope list" {
  let ctx : Context = {
    request: mkreq_ct(
      "POST",
      "application/x-www-form-urlencoded",
      @utf8.encode(
        "grant_type=password&username=bob&password=pw&scope=read+write",
      ),
    ),
    params: Map([]),
  }
  let form = ctx.oauth2_password_form().unwrap()
  assert_eq(form.grant_type, "password")
  assert_eq(form.username, "bob")
  assert_eq(form.password, "pw")
  assert_eq(form.scopes, ["read", "write"])
}

///|
/// A login is six fields. A body big enough to break the default form limits is
/// not one, so it is refused rather than searched for credentials.
test "oauth2_password_form: an oversized body is not a password grant" {
  let sb = StringBuilder()
  sb.write_string("username=bob&password=pw")
  // Past the default 1000-part bound, so the form underneath refuses it.
  for i = 0; i < 1200; i = i + 1 {
    sb.write_string("&x")
    sb.write_string(i.to_string())
    sb.write_string("=1")
  }
  let ctx : Context = {
    request: mkreq_ct(
      "POST",
      "application/x-www-form-urlencoded",
      @utf8.encode(sb.to_string()),
    ),
    params: Map([]),
  }
  assert_eq(ctx.oauth2_password_form() is None, true)
}
