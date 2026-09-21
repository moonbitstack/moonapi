// The middleware stack — CORS, GZip, and exception handling — mirroring
// Starlette's middleware and FastAPI's exception handlers. A middleware is a
// `@moonasgi.Middleware` ((Handler) -> Handler), composed around the router as
// an onion (see `App::middleware`). Exception handlers map a raised error to a
// response instead of wrapping the handler, matching FastAPI's
// `@app.exception_handler(...)`.

///|
/// An HTTP error a handler can `raise` to short-circuit with a status and body
/// (← FastAPI's `HTTPException`). `detail` is any JSON (a string is the common
/// case); `headers` are added to the response (e.g. a `WWW-Authenticate`
/// challenge). Caught by the app and mapped to a response.
pub(all) suberror HttpException {
  HttpException(
    status~ : Int,
    detail~ : Json,
    headers~ : Array[(String, String)]
  )
}

///|
/// Build an `HttpException` with a string `detail` — the common case — and
/// optional extra `headers`. `raise http_error(404, "Item not found")` reads
/// like FastAPI's `raise HTTPException(404, "Item not found")`.
pub fn http_error(
  status : Int,
  detail : String,
  headers? : Array[(String, String)] = [],
) -> HttpException {
  HttpException(status~, detail=detail.to_json(), headers~)
}

///|
/// The response for an `HttpException`: `{"detail": <detail>}` as JSON, at the
/// given status, with the exception's extra headers merged in after the
/// content-type.
fn http_exception_response(
  status : Int,
  detail : Json,
  headers : Array[(String, String)],
) -> @moonasgi.Response {
  let body : Map[String, Json] = Map([("detail", detail)])
  let hs : Array[(String, String)] = [("content-type", "application/json")]
  for h in headers {
    hs.push(h)
  }
  @moonasgi.Response::new(status, hs, @moonjson.write_bytes(body.to_json()))
}

///|
/// The built-in fallback when no registered handler claims a raised error: an
/// `HttpException` becomes its own status and detail; anything else is a
/// `500 {"detail": "Internal Server Error"}`. This is always in effect, so a
/// handler that raises `HttpException` needs no explicit registration.
fn default_exception_response(err : Error) -> @moonasgi.Response {
  match err {
    HttpException(status~, detail~, headers~) =>
      http_exception_response(status, detail, headers)
    _ => {
      let body : Map[String, Json] = Map([
        ("detail", "Internal Server Error".to_json()),
      ])
      @moonasgi.Response::new(
        500,
        [("content-type", "application/json")],
        @moonjson.write_bytes(body.to_json()),
      )
    }
  }
}

///|
/// An exception handler: given the request context and the raised error, return
/// `Some(response)` to handle it or `None` to defer to the next handler. The
/// explicit MoonBit form of FastAPI's `@app.exception_handler(ExcType)` — the
/// `None` case stands in for "this handler isn't registered for that type".
pub type ExceptionHandler = (Context, Error) -> @moonasgi.Response?

// -- CORS ---------------------------------------------------------------------

///|
/// CORS policy (← Starlette's `CORSMiddleware`). Origins, methods, and headers
/// are allow-lists; the `*_all` flags open a dimension wholesale. Per the Fetch
/// standard, `allow_credentials` forbids the `*` wildcard in the reflected
/// `Access-Control-Allow-Origin`, so with credentials the request origin is
/// echoed back instead.
pub(all) struct CorsConfig {
  allow_origins : Array[String]
  allow_all_origins : Bool
  allow_methods : Array[String]
  allow_headers : Array[String]
  allow_all_headers : Bool
  allow_credentials : Bool
  expose_headers : Array[String]
  max_age : Int
}

///|
/// Whether `origin` is permitted: any origin when `allow_all_origins` (or a `*`
/// entry), otherwise an exact match against the allow-list. This is the check
/// the CORS test mutates to prove it's load-bearing.
fn CorsConfig::origin_allowed(self : CorsConfig, origin : String) -> Bool {
  if self.allow_all_origins || self.allow_origins.contains("*") {
    true
  } else {
    self.allow_origins.contains(origin)
  }
}

///|
/// The value to reflect in `Access-Control-Allow-Origin`: `*` only when all
/// origins are allowed and credentials are off; otherwise the request origin.
fn CorsConfig::allow_origin_value(self : CorsConfig, origin : String) -> String {
  if (self.allow_all_origins || self.allow_origins.contains("*")) &&
    !self.allow_credentials {
    "*"
  } else {
    origin
  }
}

///|
/// Join a list of strings with `, ` — the list form CORS headers use.
fn join_csv(xs : Array[String]) -> String {
  let sb = StringBuilder()
  for i = 0; i < xs.length(); i = i + 1 {
    if i > 0 {
      sb.write_string(", ")
    }
    sb.write_string(xs[i])
  }
  sb.to_string()
}

///|
/// A copy of `resp` with `extra` headers appended.
fn with_headers(
  resp : @moonasgi.Response,
  extra : Array[(String, String)],
) -> @moonasgi.Response {
  let hs : Array[(String, String)] = []
  for h in resp.headers {
    hs.push(h)
  }
  for h in extra {
    hs.push(h)
  }
  @moonasgi.Response::new(resp.status, hs, resp.body)
}

///|
/// A CORS middleware for the given policy. It answers preflight `OPTIONS`
/// requests (those carrying `Access-Control-Request-Method`) directly with a
/// `204` and the negotiated `Access-Control-*` headers, and decorates every
/// other cross-origin response with `Access-Control-Allow-Origin` (plus
/// `Vary: Origin`, exposed headers, and the credentials flag). A request with
/// no `Origin`, or one from a disallowed origin, passes through untouched.
pub fn cors(
  allow_origins? : Array[String] = [],
  allow_all_origins? : Bool = false,
  allow_methods? : Array[String] = [
    "GET", "HEAD", "POST", "PUT", "PATCH", "DELETE", "OPTIONS",
  ],
  allow_headers? : Array[String] = [],
  allow_all_headers? : Bool = false,
  allow_credentials? : Bool = false,
  expose_headers? : Array[String] = [],
  max_age? : Int = 600,
) -> @moonasgi.Middleware {
  let cfg : CorsConfig = {
    allow_origins,
    allow_all_origins,
    allow_methods,
    allow_headers,
    allow_all_headers,
    allow_credentials,
    expose_headers,
    max_age,
  }
  downstream => {
    request => {
      let origin = match request.header("origin") {
        None => return downstream(request)
        Some(o) => o
      }
      let is_preflight = request.http_method == "OPTIONS" &&
        request.header("access-control-request-method") is Some(_)
      if is_preflight {
        cfg.preflight_response(request, origin)
      } else {
        let resp = downstream(request)
        if cfg.origin_allowed(origin) {
          with_headers(resp, cfg.actual_headers(origin))
        } else {
          resp
        }
      }
    }
  }
}

///|
/// The headers added to an actual (non-preflight) cross-origin response.
fn CorsConfig::actual_headers(
  self : CorsConfig,
  origin : String,
) -> Array[(String, String)] {
  let hs : Array[(String, String)] = [
    ("access-control-allow-origin", self.allow_origin_value(origin)),
    ("vary", "Origin"),
  ]
  if self.allow_credentials {
    hs.push(("access-control-allow-credentials", "true"))
  }
  if self.expose_headers.length() > 0 {
    hs.push(("access-control-expose-headers", join_csv(self.expose_headers)))
  }
  hs
}

///|
/// The preflight response: `204` with the negotiated `Access-Control-*` headers
/// when the origin is allowed, or a bare `204` (no allow-origin, so the browser
/// blocks it) when it isn't.
fn CorsConfig::preflight_response(
  self : CorsConfig,
  request : @moonasgi.Request,
  origin : String,
) -> @moonasgi.Response {
  if !self.origin_allowed(origin) {
    return @moonasgi.Response::new(204, [], b"")
  }
  let hs : Array[(String, String)] = [
    ("access-control-allow-origin", self.allow_origin_value(origin)),
    ("access-control-allow-methods", join_csv(self.allow_methods)),
    ("access-control-max-age", self.max_age.to_string()),
    ("vary", "Origin"),
  ]
  let allow_headers = if self.allow_all_headers {
    request.header("access-control-request-headers").unwrap_or("*")
  } else {
    join_csv(self.allow_headers)
  }
  if allow_headers != "" {
    hs.push(("access-control-allow-headers", allow_headers))
  }
  if self.allow_credentials {
    hs.push(("access-control-allow-credentials", "true"))
  }
  @moonasgi.Response::new(204, hs, b"")
}

// -- GZip ---------------------------------------------------------------------

///|
/// A GZip middleware: responses at least `min_size` bytes are re-encoded as
/// gzip when the client sent `Accept-Encoding: gzip` and the response isn't
/// already content-encoded. Sets `Content-Encoding: gzip`, updates
/// `Content-Length`, and adds `Vary: Accept-Encoding`.
///
/// The gzip stream is a complete RFC 1952 container — correct header, CRC-32, and
/// ISIZE — around a real RFC 1951 DEFLATE payload: LZ77 back-references coded with
/// the fixed Huffman table (`deflate.mbt`), so the body actually shrinks. Dynamic
/// Huffman would tighten the ratio further and is the documented next step.
pub fn gzip(min_size? : Int = 500) -> @moonasgi.Middleware {
  downstream => {
    request => {
      let resp = downstream(request)
      if resp.body.length() < min_size {
        return resp
      }
      if !accepts_gzip(request) {
        return resp
      }
      if resp.header("content-encoding") is Some(_) {
        return resp
      }
      let encoded = @gzip.gzip(resp.body[:])
      let hs : Array[(String, String)] = []
      for h in resp.headers {
        if h.0 != "content-length" {
          hs.push(h)
        }
      }
      hs.push(("content-encoding", "gzip"))
      hs.push(("content-length", encoded.length().to_string()))
      hs.push(("vary", "Accept-Encoding"))
      @moonasgi.Response::new(resp.status, hs, encoded)
    }
  }
}

///|
/// Whether the request's `Accept-Encoding` offers gzip.
fn accepts_gzip(request : @moonasgi.Request) -> Bool {
  match request.header("accept-encoding") {
    None => false
    Some(v) => v.to_lower().contains("gzip")
  }
}
