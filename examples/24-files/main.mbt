///|
/// Serving a file properly: the four answers RFC 9110 §13 and §14 call for, and
/// the `data:` URL a browser hands back from a canvas or a `FileReader`.
///
/// `Context::serve` is `file_response` with the request taken into account. It
/// answers a repeat request with `304`, a failed precondition with `412`, a
/// `Range` with `206` — one part or several — and an impossible one with `416`.
/// Nothing here opens a file: the bytes arrive from wherever the server got
/// them, which is what keeps the same handler running on four backends.
///
///     moon run examples/24-files
#coverage.skip
fn main {
  let app = @moonapi.App::new()
  let report = b"a quarterly report, ten times longer than it needs to be"
  let tag = @conditional.hash(report[:], digest=@sha2.Hasher::new())
  app.get("/report.txt", ctx => {
    ctx.serve(report, filename="report.txt", etag=tag)
  })
  // A client posts back what `canvas.toDataURL()` gave it; the server serves
  // what is inside, under the media type the URL itself names.
  app.post("/thumbnail", ctx => {
    match ctx.body_json() {
      Some(String(url)) =>
        match @moonapi.data_response(url, filename="thumb") {
          Some(resp) => resp
          None => @moonapi.text(400, "not a data URL")
        }
      _ => @moonapi.text(400, "expected a JSON string")
    }
  })

  // 1. Nobody has it yet.
  let first = ask(app, "GET", "/report.txt", [])
  println(
    "plain GET                 \{first.status}  \{first.body.length()} octets",
  )
  let etag = first.header("etag").unwrap_or("")
  println("  ETag                    \{etag}")
  println(
    "  Accept-Ranges           \{first.header("accept-ranges").unwrap_or("")}",
  )

  // 2. The same client comes back holding it.
  let again = ask(app, "GET", "/report.txt", [("if-none-match", etag)])
  println(
    "GET with If-None-Match    \{again.status}  \{again.body.length()} octets",
  )

  // 3. A download that stopped halfway, resumed.
  let rest = ask(app, "GET", "/report.txt", [
    ("range", "bytes=40-"),
    ("if-range", etag),
  ])
  println(
    "resumed with Range        \{rest.status}  \{rest.header("content-range").unwrap_or("")}",
  )
  println("  what came back          \{text(rest.body)}")

  // 4. Resumed against a copy that has since changed: the whole thing again,
  //    which is what §13.1.5 asks for rather than an error.
  let moved = ask(app, "GET", "/report.txt", [
    ("range", "bytes=40-"),
    ("if-range", "\"something-else\""),
  ])
  println(
    "resumed, but it changed   \{moved.status}  \{moved.body.length()} octets",
  )

  // 5. Two ranges at once, and one that is not there.
  let two = ask(app, "GET", "/report.txt", [("range", "bytes=0-1,54-55")])
  println(
    "two ranges                \{two.status}  \{two.header("content-type").unwrap_or("")}",
  )
  let past = ask(app, "GET", "/report.txt", [("range", "bytes=900-999")])
  println(
    "a range past the end      \{past.status}  \{past.header("content-range").unwrap_or("")}",
  )
  println("")

  // 6. The data URL round trip.
  let posted = "data:image/gif;base64,AAEC"
  let served = ask_body(app, "POST", "/thumbnail", "\"\{posted}\"")
  println(
    "posted data URL           \{served.status}  \{served.header("content-type").unwrap_or("")}",
  )
  println("  octets                  \{served.body.length()}")
  println(
    "  and back again          \{@moonapi.data_url(served.body, media_type="image/gif")}",
  )
}

///|
fn ask(
  app : @moonapi.App,
  verb : String,
  path : String,
  headers : Array[(String, String)],
) -> @moonasgi.Response {
  app.handle({ http_method: verb, path, query_string: b"", headers, body: b"", })
}

///|
fn ask_body(
  app : @moonapi.App,
  verb : String,
  path : String,
  body : String,
) -> @moonasgi.Response {
  app.handle({
    http_method: verb,
    path,
    query_string: b"",
    headers: [("content-type", "application/json")],
    body: @utf8.encode(body[:]),
  })
}

///|
fn text(body : Bytes) -> String {
  let out = StringBuilder()
  for i = 0; i < body.length(); i = i + 1 {
    out.write_char(body[i].to_int().unsafe_to_char())
  }
  out.to_string()
}
