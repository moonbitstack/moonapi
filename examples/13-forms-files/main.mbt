///|
/// The form and file extractors — FastAPI's `Form(...)` / `File(...)`. One
/// `Context::form` parses both carriers: an `application/x-www-form-urlencoded`
/// body (percent- and `+`-decoded) and a `multipart/form-data` body split on its
/// boundary. `Form::field` reads the first value, `values` every value a
/// repeated field submitted, and `file` an `Upload` — filename, content-type,
/// and the raw bytes byte-for-byte, so a binary upload survives untouched.
/// `@mime.Limits` bounds what a sender may spend: a body over the limit comes back
/// as `None` and is answered `413` rather than parsed.
///
///     moon run examples/13-forms-files
#coverage.skip
fn main {
  let app = @moonapi.App::new()
  app.post("/upload", ctx => {
    // A title and three tags is the whole of this form, so more is not it.
    let form = match ctx.form(limits={ ..@mime.limits, parts: 4, }) {
      Some(f) => f
      None =>
        return @moonapi.text(
          @moonapi.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
          "too many form parts",
        )
    }
    let title = form.field("title").unwrap_or("-")
    let tags = form.values("tag")
    match form.file("doc") {
      Some(f) =>
        @moonapi.text(
          200,
          "title=\{title} tags=[\{join_csv(tags)}] file=\{f.filename} type=\{f.content_type} bytes=\{f.content.length()} body=\{@utf8.decode_lossy(f.content[:])}",
        )
      None =>
        @moonapi.text(200, "title=\{title} tags=[\{join_csv(tags)}] (no file)")
    }
  })
  let post = (label : String, ct : String, body : Bytes) => {
    let req : @moonasgi.Request = {
      http_method: "POST",
      path: "/upload",
      query_string: b"",
      headers: [("content-type", ct)],
      body,
    }
    let r = app.handle(req)
    println("\{label} -> \{r.status} \{@utf8.decode_lossy(r.body[:])}")
  }

  // 1. urlencoded: a repeated `tag` becomes a list; `+` decodes to a space.
  post(
    "urlencoded",
    "application/x-www-form-urlencoded",
    @utf8.encode("title=hello+world&tag=a&tag=b&tag=c"),
  )

  // 2. multipart: a text field plus an uploaded file with its own content-type.
  let boundary = "boundaryqwq233"
  let multipart =
    #|--boundaryqwq233
    #|Content-Disposition: form-data; name="title"
    #|
    #|greetings
    #|--boundaryqwq233
    #|Content-Disposition: form-data; name="doc"; filename="hello.txt"
    #|Content-Type: text/plain
    #|
    #|qwq file bytes 23333
    #|--boundaryqwq233--
    #|
  // The multipart grammar is CRLF-delimited; the raw string above is LF-only.
  let crlf_body = @utf8.encode(to_crlf(multipart))
  post("multipart", "multipart/form-data; boundary=" + boundary, crlf_body)

  // 3. A fifth pair is over the limit, and the form is refused whole.
  post(
    "over-limit",
    "application/x-www-form-urlencoded",
    @utf8.encode("title=a&tag=b&tag=c&tag=d&tag=e"),
  )
}

///|
/// Join strings with commas — a repeated form field surfaces as a list.
fn join_csv(xs : Array[String]) -> String {
  let sb = StringBuilder()
  for i = 0; i < xs.length(); i = i + 1 {
    if i > 0 {
      sb.write_string(",")
    }
    sb.write_string(xs[i])
  }
  sb.to_string()
}

///|
/// Rewrite LF line endings as CRLF — the multipart wire grammar is CRLF, but a
/// MoonBit multi-line string literal carries bare LFs.
fn to_crlf(s : String) -> String {
  let sb = StringBuilder()
  for i = 0; i < s.length(); i = i + 1 {
    if s[i].to_int() == 0x0A {
      sb.write_string("\r\n")
    } else {
      sb.write_char(s[i].unsafe_to_char())
    }
  }
  sb.to_string()
}
