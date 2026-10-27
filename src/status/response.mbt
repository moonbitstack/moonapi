// Responses that are an envelope rather than a body: a redirect, a download,
// a data URL, and a download that weighs the request first.

///|
/// A redirect to `url` (← FastAPI's `RedirectResponse`).
///
/// `307` keeps the method and body, which `302` historically does not. Use `303`
/// after a write, `301` / `308` for a permanent move.
///
/// The URL is escaped as a whole URI reference, so an encoded one is not encoded
/// twice and a `\r\n` cannot open a header of its own.
///
/// ```mbt check
/// test {
///   let moved = @status.redirect("/new")
///   assert_eq(moved.status, 307)
///   assert_eq(moved.header("location"), Some("/new"))
/// }
/// ```
pub fn redirect(url : String, status~ : Int32 = 307) -> @moonasgi.Response {
  @moonasgi.Response::new(
    status,
    [("location", @moonurl.escape_text(url[:], kind=Whole))],
    b"",
  )
}

///|
/// A download (← FastAPI's `FileResponse`): a media type from `filename`'s
/// extension unless `media_type` names one, `Content-Length`, and a
/// `Content-Disposition`. No `filename`, no disposition.
///
/// Bytes rather than a path: the same app runs on four backends and only the
/// server can read a file on any of them.
///
/// Always the whole thing. [`Context::serve`] weighs the request first.
pub fn file_response(
  content : Bytes,
  filename~ : String = "",
  media_type~ : String = "",
  status~ : Int32 = 200,
  inline~ : Bool = false,
) -> @moonasgi.Response {
  @moonasgi.Response::new(
    status,
    envelope(content.length(), filename, media_type, inline),
    content,
  )
}

///|
/// Serve what a `data:` URL carries (RFC 2397), under the media type it names —
/// what `canvas.toDataURL()` and `FileReader.readAsDataURL()` hand back.
///
/// `None` when it is not a data URL, so a handler tells "no picture" from "not a
/// picture" without touching base64.
pub fn data_response(
  url : String,
  filename~ : String = "",
  status~ : Int32 = 200,
  inline~ : Bool = true,
) -> @moonasgi.Response? {
  try {
    let url = @dataurl.Url::decode(url[:])
    Some(
      file_response(url.data, filename~, media_type=url.kind, status~, inline~),
    )
  } catch {
    _ => None
  }
}

///|
/// The content as a `data:` URL, for embedding it instead of costing a second
/// request.
pub fn data_url(content : Bytes, media_type~ : String = "") -> String {
  let kind = if media_type != "" { media_type } else { @dataurl.kind }
  @dataurl.Url::new(content, kind~).encode()
}

///|
/// What the body is, how long, and what to save it as.
pub fn envelope(
  length : Int32,
  filename : String,
  media_type : String,
  inline : Bool,
) -> Array[(String, String)] {
  let kind = if media_type != "" {
    media_type
  } else {
    charset(@moonmime.guess_type(filename[:]))
  }
  let headers : Array[(String, String)] = [
    ("content-type", kind),
    ("content-length", length.to_string()),
  ]
  if filename != "" {
    headers.push(
      (
        "content-disposition",
        @moonmime.content_disposition(filename[:], inline~),
      ),
    )
  }
  headers
}

///|
/// A text type with `charset=utf-8` added, as Starlette's `Response` adds it: a
/// browser handed `text/plain` with no charset applies its own locale's.
fn charset(kind : String) -> String {
  if kind.has_prefix("text/") && !kind.to_lower().contains("charset=") {
    kind + "; charset=utf-8"
  } else {
    kind
  }
}
