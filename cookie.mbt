// The response side of cookies — FastAPI's `response.set_cookie` and
// `delete_cookie`. `Context::cookie` already reads what a request carries; this
// is what writes one back.
//
// The cookie itself is `moonhttp`'s, header and all; what is here is putting one
// on a response. They are functions over a response rather than methods on it
// because `@moonasgi.Response` belongs to another package, and each returns a new
// response with one more `Set-Cookie` header. That is also the correct wire
// shape: two cookies are two headers, never one merged field, since `Set-Cookie`
// is the one header a proxy may not fold on commas.

///|
pub using @cookie {type SameSite, type Cookie}

///|
/// Add a `Set-Cookie` header to `resp` (← FastAPI's `response.set_cookie`),
/// returning the response that carries it; the original is untouched, so a
/// handler can hand the same base response to two callers.
///
/// `max_age` is the lifetime in seconds and `expires` the moment it dies; giving
/// neither makes it a session cookie. `path` defaults to `/`, and `None` omits
/// the attribute so the cookie scopes to the request's own directory.
/// `http_only` keeps it away from scripts, `secure` keeps it off plaintext
/// connections, and `same_site` defaults to `Lax` — the browser default, and the
/// one that stops a cross-site form post from carrying a session.
pub fn set_cookie(
  resp : @moonasgi.Response,
  name : String,
  value : String,
  max_age? : Int,
  expires? : @moondate.Moment,
  path? : String? = Some("/"),
  domain? : String,
  secure? : Bool = false,
  http_only? : Bool = false,
  same_site? : @cookie.SameSite? = Some(Lax),
) -> @moonasgi.Response {
  let cookie = @cookie.Cookie::new(
    name,
    value,
    max_age?,
    expires?,
    domain?,
    path~,
    secure~,
    http_only~,
    same_site~,
  )
  @moonasgi.Response::new(
    resp.status,
    [..resp.headers, ("set-cookie", cookie.encode())],
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
  path? : String? = Some("/"),
  domain? : String,
  secure? : Bool = false,
  http_only? : Bool = false,
  same_site? : @cookie.SameSite? = Some(Lax),
) -> @moonasgi.Response {
  set_cookie(
    resp,
    name,
    "",
    max_age=0,
    expires=@moondate.Moment::of_epoch(0L),
    path~,
    domain?,
    secure~,
    http_only~,
    same_site~,
  )
}
