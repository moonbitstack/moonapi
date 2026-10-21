// HTTP Basic / API-key runtime extractors (← FastAPI's `HTTPBasic` / `APIKey*`).

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
