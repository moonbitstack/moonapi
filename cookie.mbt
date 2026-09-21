// The response side of cookies — FastAPI's `response.set_cookie` and
// `delete_cookie`. `Context::cookie` already reads what a request carries; this
// is what writes one back.
//
// They are functions over a response rather than methods on it because
// `@moonasgi.Response` belongs to another package, and each returns a new
// response with one more `Set-Cookie` header. That is also the correct wire
// shape: two cookies are two headers, never one merged field, since `Set-Cookie`
// is the one header a proxy may not fold on commas.

///|
/// How far a cross-site request may carry a cookie. `Strict` sends it only on
/// same-site requests, `Lax` also on a top-level navigation (the default, and
/// what stops a cross-site form post from carrying a session), `Unrestricted`
/// sends it everywhere — it is the wire value `None`, which browsers honour only
/// on a `Secure` cookie.
pub(all) enum SameSite {
  Strict
  Lax
  Unrestricted
} derive(Eq)

///|
/// The attribute's wire spelling.
fn same_site_name(s : SameSite) -> String {
  match s {
    Strict => "Strict"
    Lax => "Lax"
    Unrestricted => "None"
  }
}

///|
/// Drop the octets a cookie name, value, path or domain may not carry: RFC 6265's
/// cookie-octet is printable ASCII minus space, `"`, `,`, `;` and `\`.
///
/// Dropped rather than escaped, so what `Context::cookie` reads back is the same
/// text that was set — an escape the writer applies and the reader does not know
/// about is worse than a character that never survives. The security half is that
/// a `\r\n` smuggled into a name or value cannot open a header of its own.
fn cookie_safe(s : String) -> String {
  let sb = StringBuilder()
  for i = 0; i < s.length(); i = i + 1 {
    let c = s[i].to_int()
    if c > 0x20 && c < 0x7F && c != 0x22 && c != 0x2C && c != 0x3B && c != 0x5C {
      sb.write_char(s[i].unsafe_to_char())
    }
  }
  sb.to_string()
}

///|
/// Drop everything outside an HTTP-date's alphabet — letters, digits, space,
/// comma, colon, hyphen and plus. `Expires` is the one attribute whose value
/// legitimately holds spaces and a comma, so it cannot go through `cookie_safe`;
/// this keeps the header un-splittable all the same.
fn date_safe(s : String) -> String {
  let sb = StringBuilder()
  for i = 0; i < s.length(); i = i + 1 {
    let c = s[i].to_int()
    let ok = (c >= 0x30 && c <= 0x39) ||
      (c >= 0x41 && c <= 0x5A) ||
      (c >= 0x61 && c <= 0x7A) ||
      c == 0x20 ||
      c == 0x2C ||
      c == 0x3A ||
      c == 0x2D ||
      c == 0x2B
    if ok {
      sb.write_char(s[i].unsafe_to_char())
    }
  }
  sb.to_string()
}

///|
/// Render one `Set-Cookie` field value. Attributes follow RFC 6265 §4.1.1's
/// order, which is the order every browser and log reader expects to see them in.
fn cookie_header(
  name : String,
  value : String,
  max_age : Int?,
  expires : String?,
  path : String,
  domain : String?,
  secure : Bool,
  http_only : Bool,
  same_site : SameSite?,
) -> String {
  let sb = StringBuilder()
  sb.write_string(cookie_safe(name))
  sb.write_string("=")
  sb.write_string(cookie_safe(value))
  match expires {
    Some(d) => {
      sb.write_string("; Expires=")
      sb.write_string(date_safe(d))
    }
    None => ()
  }
  match max_age {
    Some(secs) => {
      sb.write_string("; Max-Age=")
      sb.write_string(secs.to_string())
    }
    None => ()
  }
  match domain {
    Some(d) => {
      sb.write_string("; Domain=")
      sb.write_string(cookie_safe(d))
    }
    None => ()
  }
  if path != "" {
    sb.write_string("; Path=")
    sb.write_string(cookie_safe(path))
  }
  if secure {
    sb.write_string("; Secure")
  }
  if http_only {
    sb.write_string("; HttpOnly")
  }
  match same_site {
    Some(s) => {
      sb.write_string("; SameSite=")
      sb.write_string(same_site_name(s))
    }
    None => ()
  }
  sb.to_string()
}

///|
/// Add a `Set-Cookie` header to `resp` (← FastAPI's `response.set_cookie`),
/// returning the response that carries it; the original is untouched, so a
/// handler can hand the same base response to two callers.
///
/// `max_age` is the lifetime in seconds and `expires` an HTTP-date; giving
/// neither makes it a session cookie. `path` defaults to `/`, and passing `""`
/// omits the attribute so the cookie scopes to the request's own directory.
/// `http_only` keeps it away from scripts, `secure` keeps it off plaintext
/// connections, and `same_site` defaults to `Lax` — the browser default, and the
/// one that stops a cross-site form post from carrying a session.
pub fn set_cookie(
  resp : @moonasgi.Response,
  name : String,
  value : String,
  max_age? : Int,
  expires? : String,
  path? : String = "/",
  domain? : String,
  secure? : Bool = false,
  http_only? : Bool = false,
  same_site? : SameSite? = Some(Lax),
) -> @moonasgi.Response {
  let header = cookie_header(
    name, value, max_age, expires, path, domain, secure, http_only, same_site,
  )
  @moonasgi.Response::new(
    resp.status,
    [..resp.headers, ("set-cookie", header)],
    resp.body,
  )
}

///|
/// Expire the cookie named `name` (← FastAPI's `response.delete_cookie`): an
/// empty value with `Max-Age=0` and a date in the past, so a browser that honours
/// only one of the two still drops it.
///
/// A cookie is identified by name, domain and path together, so `path` and
/// `domain` must match what set it — otherwise this writes a second, differently
/// scoped cookie and the original survives.
pub fn delete_cookie(
  resp : @moonasgi.Response,
  name : String,
  path? : String = "/",
  domain? : String,
  secure? : Bool = false,
  http_only? : Bool = false,
  same_site? : SameSite? = Some(Lax),
) -> @moonasgi.Response {
  set_cookie(
    resp,
    name,
    "",
    max_age=0,
    expires="Thu, 01 Jan 1970 00:00:00 GMT",
    path~,
    domain?,
    secure~,
    http_only~,
    same_site~,
  )
}

///|
pub extend SameSite with Eq::{not_equal, equal}
