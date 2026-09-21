///|
/// Build a request with explicit headers — CORS and gzip switch on them.
fn req_h(
  verb : String,
  path : String,
  headers : Array[(String, String)],
) -> @moonasgi.Request {
  { http_method: verb, path, query_string: b"", headers, body: b"", }
}

///|
/// Read a response header, "" if absent.
fn hdr(resp : @moonasgi.Response, name : String) -> String {
  resp.header(name).unwrap_or("")
}

///|
test "cors: preflight from an allowed origin gets the negotiated headers" {
  let app = App::new()
  app.middleware(
    cors(
      allow_origins=["https://app.example"],
      allow_headers=["x-token"],
      max_age=100,
    ),
  )
  app.get("/data", _ctx => text(200, "ok"))
  let pre = app.handle(
    req_h("OPTIONS", "/data", [
      ("origin", "https://app.example"),
      ("access-control-request-method", "GET"),
    ]),
  )
  assert_eq(pre.status, 204)
  assert_eq(hdr(pre, "access-control-allow-origin"), "https://app.example")
  assert_eq(hdr(pre, "access-control-allow-methods").contains("GET"), true)
  assert_eq(hdr(pre, "access-control-allow-headers"), "x-token")
  assert_eq(hdr(pre, "access-control-max-age"), "100")
}

///|
test "cors: preflight from a disallowed origin gets no allow-origin" {
  let app = App::new()
  app.middleware(cors(allow_origins=["https://app.example"]))
  app.get("/data", _ctx => text(200, "ok"))
  let pre = app.handle(
    req_h("OPTIONS", "/data", [
      ("origin", "https://evil.example"),
      ("access-control-request-method", "GET"),
    ]),
  )
  // The middleware still answers, but without the allow-origin the browser
  // blocks the request. This is the pair the origin check is mutated against.
  assert_eq(pre.status, 204)
  assert_eq(pre.header("access-control-allow-origin"), None)
}

///|
test "cors: actual request from an allowed origin is decorated" {
  let app = App::new()
  app.middleware(
    cors(allow_origins=["https://app.example"], expose_headers=["x-total"]),
  )
  app.get("/data", _ctx => text(200, "ok"))
  let resp = app.handle(
    req_h("GET", "/data", [("origin", "https://app.example")]),
  )
  assert_eq(resp.status, 200)
  assert_eq(resp.body, @utf8.encode("ok"))
  assert_eq(hdr(resp, "access-control-allow-origin"), "https://app.example")
  assert_eq(hdr(resp, "access-control-expose-headers"), "x-total")
  assert_eq(hdr(resp, "vary"), "Origin")
}

///|
test "cors: a request without Origin is untouched" {
  let app = App::new()
  app.middleware(cors(allow_all_origins=true))
  app.get("/data", _ctx => text(200, "ok"))
  let resp = app.handle(req_h("GET", "/data", []))
  assert_eq(resp.header("access-control-allow-origin"), None)
}

///|
test "cors: credentials echo the origin rather than the wildcard" {
  let app = App::new()
  app.middleware(cors(allow_all_origins=true, allow_credentials=true))
  app.get("/data", _ctx => text(200, "ok"))
  let resp = app.handle(
    req_h("GET", "/data", [("origin", "https://app.example")]),
  )
  assert_eq(hdr(resp, "access-control-allow-origin"), "https://app.example")
  assert_eq(hdr(resp, "access-control-allow-credentials"), "true")
}

///|
/// `unit` repeated `n` times as bytes — a compressible fixture with real matches.
fn repeat_bytes(unit : String, n : Int) -> Bytes {
  let sb = StringBuilder()
  for _i = 0; _i < n; _i = _i + 1 {
    sb.write_string(unit)
  }
  @utf8.encode(sb.to_string())
}

///|
/// What belongs here is the middleware, not the codec: that the response is
/// marked as gzip, that it actually got smaller, and that it reads back. Whether
/// DEFLATE is correct is moonzip's question, and moonzip asks zlib.
test "gzip: the middleware body inflates back to the response and is smaller" {
  let body = repeat_bytes("moonapi gzip middleware payload ", 60)
  let app = App::new()
  app.middleware(gzip(min_size=100))
  app.get("/j", _ctx => @moonasgi.Response::new(200, [], body))
  let z = app.handle(req_h("GET", "/j", [("accept-encoding", "gzip")]))
  assert_eq(hdr(z, "content-encoding"), "gzip")
  assert_eq(hdr(z, "vary"), "Accept-Encoding")
  assert_eq(hdr(z, "content-length"), z.body.length().to_string())
  assert_eq(z.body.length() < body.length(), true)
  assert_eq(@gzip.gunzip(z.body[:]), body)
}

///|
test "gzip: middleware encodes a large response and skips a small one" {
  let big = xbytes(1000)
  let app = App::new()
  app.middleware(gzip(min_size=500))
  app.get("/big", _ctx => @moonasgi.Response::new(200, [], big))
  app.get("/small", _ctx => text(200, "tiny"))
  let z = app.handle(req_h("GET", "/big", [("accept-encoding", "gzip")]))
  assert_eq(hdr(z, "content-encoding"), "gzip")
  assert_eq(hdr(z, "vary"), "Accept-Encoding")
  assert_eq(hdr(z, "content-length"), z.body.length().to_string())
  assert_eq(z.body[0].to_int(), 0x1f)
  // small body: below the threshold, left as-is.
  let s = app.handle(req_h("GET", "/small", [("accept-encoding", "gzip")]))
  assert_eq(s.header("content-encoding"), None)
  assert_eq(s.body, @utf8.encode("tiny"))
}

///|
test "gzip: no Accept-Encoding leaves the response uncompressed" {
  let big = xbytes(1000)
  let app = App::new()
  app.middleware(gzip(min_size=10))
  app.get("/big", _ctx => @moonasgi.Response::new(200, [], big))
  let resp = app.handle(req_h("GET", "/big", []))
  assert_eq(resp.header("content-encoding"), None)
  assert_eq(resp.body, big)
}

///|
test "exception: a raised HttpException maps to its status and detail" {
  let app = App::new()
  app.get("/boom", _ctx => raise http_error(418, "teapot"))
  let resp = app.handle(req_h("GET", "/boom", []))
  assert_eq(resp.status, 418)
  assert_eq(hdr(resp, "content-type"), "application/json")
  assert_eq(json_str(@json.parse(decode_body(resp.body)), "detail"), "teapot")
}

///|
test "exception: HttpException extra headers reach the response" {
  let app = App::new()
  app.get("/auth", _ctx => {
    raise http_error(401, "nope", headers=[("www-authenticate", "Bearer")])
  })
  let resp = app.handle(req_h("GET", "/auth", []))
  assert_eq(resp.status, 401)
  assert_eq(hdr(resp, "www-authenticate"), "Bearer")
}

///|
test "exception: a registered handler is tried before the default" {
  let app = App::new()
  app.exception_handler((_ctx, err) => {
    match err {
      HttpException(status~, detail=_, headers=_) =>
        Some(text(status, "custom"))
      _ => None
    }
  })
  app.get("/boom", _ctx => raise http_error(400, "x"))
  let resp = app.handle(req_h("GET", "/boom", []))
  assert_eq(resp.status, 400)
  assert_eq(resp.body, @utf8.encode("custom"))
}

///|
test "exception: an unhandled error becomes a 500" {
  let app = App::new()
  app.get("/fail", _ctx => fail("kaboom"))
  let resp = app.handle(req_h("GET", "/fail", []))
  assert_eq(resp.status, 500)
  assert_eq(
    json_str(@json.parse(decode_body(resp.body)), "detail"),
    "Internal Server Error",
  )
}

///|
/// A body of `n` `x` bytes — an above-threshold response for the gzip tests.
fn xbytes(n : Int) -> Bytes {
  let buf = Buffer()
  for i = 0; i < n; i = i + 1 {
    buf.write_byte(b'x')
  }
  buf.to_bytes()
}

///|
/// Decode a UTF-8 response body to a String for JSON assertions.
fn decode_body(b : Bytes) -> String {
  let sb = StringBuilder()
  for i = 0; i < b.length(); i = i + 1 {
    sb.write_char(b[i].to_int().unsafe_to_char())
  }
  sb.to_string()
}
