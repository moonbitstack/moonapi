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
/// A request to `path` carrying `body` under `content_type` — test helper.
fn mkreq_form(
  verb : String,
  path : String,
  content_type : String,
  body : Bytes,
) -> @moonasgi.Request {
  {
    http_method: verb,
    path,
    query_string: b"",
    headers: [("content-type", content_type)],
    body,
  }
}

///|
/// A fixed clock for the demo app — test helper.
fn fixed(t : Int64) -> () -> Int64 {
  () => t
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
test "create_access_token stamps sub / iat / exp / scopes and verifies" {
  let token = create_access_token(
    "alice",
    "secret",
    1000L,
    scopes=["me", "items"],
    expires_in_secs=60L,
  )
  let c = @jwt.verify(token[:], HS256, hs256("secret"), now=At(1000L))
  assert_eq(c.get("sub"), Some("alice".to_json()))
  // iat / exp are JSON numbers (NumericDate), not strings.
  assert_eq(c.get("iat"), Some(1000.0.to_json()))
  assert_eq(c.get("exp"), Some(1060.0.to_json()))
  assert_eq(c.get("scopes"), Some(["me", "items"].to_json()))
}

///|
test "OAuth2 flow: issue a token, then a protected route accepts it" {
  let app = oauth2_app(fixed(1000L))
  // POST /token with a urlencoded password form.
  let token_resp = app.handle(
    mkreq_form(
      "POST",
      "/token",
      "application/x-www-form-urlencoded",
      @utf8.encode("grant_type=password&username=alice&password=wonderland"),
    ),
  )
  assert_eq(token_resp.status, 200)
  let token = json_str(resp_json(token_resp), "access_token")
  assert_eq(json_str(resp_json(token_resp), "token_type"), "bearer")
  assert_eq(token != "", true)
  // GET /users/me with the bearer token -> 200 and the subject.
  let me = app.handle(mkreq_auth("GET", "/users/me", "Bearer " + token))
  assert_eq(me.status, 200)
  assert_eq(json_str(resp_json(me), "username"), "alice")
}

///|
test "OAuth2 flow: wrong password is rejected at the token endpoint" {
  let app = oauth2_app(fixed(1000L))
  let resp = app.handle(
    mkreq_form(
      "POST",
      "/token",
      "application/x-www-form-urlencoded",
      @utf8.encode("username=alice&password=wrong"),
    ),
  )
  assert_eq(resp.status, 401)
  assert_eq(
    json_str(resp_json(resp), "detail"),
    "Incorrect username or password",
  )
}

///|
test "protected route: missing token -> 401 Not authenticated" {
  let app = oauth2_app(fixed(1000L))
  let resp = app.handle(mkreq("GET", "/users/me"))
  assert_eq(resp.status, 401)
  assert_eq(resp.header("www-authenticate"), Some("Bearer"))
  assert_eq(json_str(resp_json(resp), "detail"), "Not authenticated")
}

///|
test "protected route: a tampered token -> 401 Could not validate credentials" {
  let app = oauth2_app(fixed(1000L))
  let good = create_access_token("alice", "demo-secret", 1000L)
  // Corrupt the last character of the signature segment.
  let parts = split_char(good, '.')
  let sig = parts[2]
  let flipped = if sig[sig.length() - 1] == 'a' { "b" } else { "a" }
  let tampered = parts[0] +
    "." +
    parts[1] +
    "." +
    sig[0:sig.length() - 1].to_owned() +
    flipped
  let resp = app.handle(mkreq_auth("GET", "/users/me", "Bearer " + tampered))
  assert_eq(resp.status, 401)
  assert_eq(
    json_str(resp_json(resp), "detail"),
    "Could not validate credentials",
  )
}

///|
test "protected route: an expired token -> 401" {
  // Issue at t=1000 (exp=4600), verify at t=5000: expired.
  let app_issue = oauth2_app(fixed(1000L))
  let token_resp = app_issue.handle(
    mkreq_form(
      "POST",
      "/token",
      "application/x-www-form-urlencoded",
      @utf8.encode("username=alice&password=wonderland"),
    ),
  )
  let token = json_str(resp_json(token_resp), "access_token")
  let app_later = oauth2_app(fixed(5000L))
  let resp = app_later.handle(mkreq_auth("GET", "/users/me", "Bearer " + token))
  assert_eq(resp.status, 401)
  assert_eq(
    json_str(resp_json(resp), "detail"),
    "Could not validate credentials",
  )
}

///|
test "scopes: a token with the scope passes, one without gets 403" {
  let app = oauth2_app(fixed(1000L))
  // Request the `items` scope at token time.
  let with_scope = app.handle(
    mkreq_form(
      "POST",
      "/token",
      "application/x-www-form-urlencoded",
      @utf8.encode("username=alice&password=wonderland&scope=me+items"),
    ),
  )
  let t1 = json_str(resp_json(with_scope), "access_token")
  let ok = app.handle(mkreq_auth("GET", "/users/me/items", "Bearer " + t1))
  assert_eq(ok.status, 200)
  assert_eq(json_str(resp_json(ok), "owner"), "alice")
  // A token granted only `me` is refused at the items route with 403.
  let narrow = app.handle(
    mkreq_form(
      "POST",
      "/token",
      "application/x-www-form-urlencoded",
      @utf8.encode("username=alice&password=wonderland&scope=me"),
    ),
  )
  let t2 = json_str(resp_json(narrow), "access_token")
  let forbidden_resp = app.handle(
    mkreq_auth("GET", "/users/me/items", "Bearer " + t2),
  )
  assert_eq(forbidden_resp.status, 403)
  assert_eq(
    json_str(resp_json(forbidden_resp), "detail"),
    "Not enough permissions",
  )
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
