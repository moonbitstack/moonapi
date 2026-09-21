// The response kinds that are an envelope rather than a body — FastAPI's
// `RedirectResponse` and `FileResponse`. `text` / `html` / `json` in `app.mbt`
// serialise a value; these two decide what the headers say about it.

///|
/// A redirect to `url` (← FastAPI's `RedirectResponse`). The body is empty and
/// `Location` carries the target.
///
/// `307` is the default because it is the redirect that keeps the request's
/// method and body — the one a `POST` can safely follow, which `302` historically
/// is not. Use `303` to send a client to a `GET` after a write, and `301` / `308`
/// for a move that is permanent.
///
/// The URL is percent-encoded over the characters a URI reserves for structure,
/// so an already-encoded URL passes through unchanged and a `\r\n` smuggled into
/// one cannot open a header of its own.
pub fn redirect(url : String, status? : Int = 307) -> @moonasgi.Response {
  @moonasgi.Response::new(
    status,
    [("location", @mime.percent_encode(url[:], safe=":/%#?=@[]!$&'()*+,;"[:]))],
    b"",
  )
}

///|
/// A file download built from bytes already in hand (← FastAPI's `FileResponse`).
///
/// It takes the content rather than a path because moonapi has no filesystem of
/// its own — the same app runs on wasm, js and native, and only the server knows
/// how to read a file on any of them. What this adds is the envelope: a media
/// type guessed from `filename`'s extension unless `media_type` names one,
/// `Content-Length`, and a `Content-Disposition` that tells the browser to save
/// the file (or, with `inline`, to display it) under that name. An empty
/// `filename` leaves the disposition off entirely.
pub fn file_response(
  content : Bytes,
  filename? : String = "",
  media_type? : String = "",
  status? : Int = 200,
  inline? : Bool = false,
) -> @moonasgi.Response {
  let ct = if media_type != "" {
    media_type
  } else {
    @media.type_of(filename[:])
  }
  let headers : Array[(String, String)] = [
    ("content-type", ct),
    ("content-length", content.length().to_string()),
  ]
  if filename != "" {
    headers.push(
      ("content-disposition", @media.disposition(filename[:], inline~)),
    )
  }
  @moonasgi.Response::new(status, headers, content)
}
