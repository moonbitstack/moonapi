///|
/// A custom error a handler raises, mapped to a response by an exception handler.
suberror OrderError {
  OutOfStock(String)
  Unexpected
}

///|
/// The middleware and exception stack. `App::middleware` wraps the router:
/// `cors(...)` answers preflight `OPTIONS` and decorates cross-origin responses,
/// `gzip(...)` re-encodes large bodies with a real DEFLATE compressor (a
/// companion `@gzip.gunzip` round-trips it). Handlers `raise` an `HttpException`
/// (`http_error`) or a custom error; `App::exception_handler` maps the custom one
/// and the built-in fallback handles the rest, while `add_status_handler` swaps a
/// custom page in for any error status — here a routing `404`.
///
///     moon run examples/16-middleware
#coverage.skip
fn main raise {
  let app = @moonapi.App::new()
  app.middleware(
    @moonapi.cors(
      allow_origins=["https://app.example.com"],
      allow_credentials=true,
      expose_headers=["X-Total"],
    ),
  )
  app.middleware(@moonapi.gzip(min_size=100))
  app.exception_handler((_ctx, err) => {
    match err {
      OutOfStock(item) =>
        Some(@moonapi.json(409, order_detail("out of stock: " + item)))
      _ => None
    }
  })
  app.add_status_handler(404, _ctx => {
    @moonapi.json(404, order_detail("no such route here"))
  })
  app.get("/big", _ctx => {
    @moonapi.text(200, repeat_str("moonapi gzip payload ", 40))
  })
  app.get("/boom", _ctx => raise @moonapi.http_error(418, "I am a teapot"))
  app.get("/order", _ctx => raise OutOfStock("widget-233"))
  app.get("/crash", _ctx => raise Unexpected)

  // 1. CORS preflight: OPTIONS carrying Access-Control-Request-Method -> 204.
  let preflight : @moonasgi.Request = {
    http_method: "OPTIONS",
    path: "/big",
    query_string: b"",
    headers: [
      ("origin", "https://app.example.com"),
      ("access-control-request-method", "GET"),
    ],
    body: b"",
  }
  let pf = app.handle(preflight)
  println(
    "OPTIONS /big -> \{pf.status} allow-origin=\{header(pf, "access-control-allow-origin")} allow-methods=\{header(pf, "access-control-allow-methods")}",
  )

  // 2. CORS actual request from an allowed origin: response is decorated.
  let cross = get("/boom", [("origin", "https://app.example.com")])
  let cr = app.handle(cross)
  println(
    "GET /boom (allowed origin) -> \{cr.status} allow-origin=\{header(cr, "access-control-allow-origin")} cred=\{header(cr, "access-control-allow-credentials")}",
  )

  // 3. A disallowed origin passes through undecorated.
  let bad = app.handle(get("/boom", [("origin", "https://evil.example.com")]))
  println(
    "GET /boom (evil origin) -> \{bad.status} allow-origin=\{header(bad, "access-control-allow-origin")}",
  )

  // 4. GZip: a large body is DEFLATE-compressed and inflates back byte-exact.
  let z = app.handle(get("/big", [("accept-encoding", "gzip")]))
  let original = repeat_str("moonapi gzip payload ", 40)
  let restored = @utf8.decode_lossy(@gzip.gunzip(z.body[:])[:])
  println(
    "GET /big -> \{z.status} encoding=\{header(z, "content-encoding")} \{original.length()}B -> \{z.body.length()}B, round-trips=\{restored == original}",
  )

  // 5. Raised HttpException -> its own status + detail (built-in mapping).
  let boom = app.handle(get("/boom", []))
  println("GET /boom -> \{boom.status} \{@utf8.decode_lossy(boom.body[:])}")

  // 6. A custom error claimed by the registered exception handler.
  let order = app.handle(get("/order", []))
  println("GET /order -> \{order.status} \{@utf8.decode_lossy(order.body[:])}")

  // 7. An unclaimed error falls through to the built-in 500.
  let crash = app.handle(get("/crash", []))
  println("GET /crash -> \{crash.status} \{@utf8.decode_lossy(crash.body[:])}")

  // 8. add_status_handler swaps a custom page in for the routing 404.
  let miss = app.handle(get("/nope", []))
  println("GET /nope -> \{miss.status} \{@utf8.decode_lossy(miss.body[:])}")
}

///|
fn get(path : String, headers : Array[(String, String)]) -> @moonasgi.Request {
  { http_method: "GET", path, query_string: b"", headers, body: b"", }
}

///|
fn header(resp : @moonasgi.Response, name : String) -> String {
  resp.header(name).unwrap_or("-")
}

///|
/// A `{"detail": msg}` JSON value — the FastAPI error-body shape.
fn order_detail(msg : String) -> Json {
  let m : Map[String, Json] = Map([("detail", msg.to_json())])
  m.to_json()
}

///|
/// `unit` repeated `n` times — a compressible fixture with real LZ77 matches.
fn repeat_str(unit : String, n : Int) -> String {
  let sb = StringBuilder()
  for _i = 0; _i < n; _i = _i + 1 {
    sb.write_string(unit)
  }
  sb.to_string()
}
