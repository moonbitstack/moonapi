// The envelope response kinds: a redirect, which is a status and a `Location`,
// and a file download, which is a body plus the headers that name it.

///|
/// A redirect is a status and a `Location`, and nothing else — no body to read
/// and no content type to describe one.
test "redirect carries the status and the Location header" {
  let resp = redirect("/qwq")
  assert_eq(resp.status, 307)
  assert_eq(resp.header("location"), Some("/qwq"))
  assert_eq(resp.body, b"")
}

///|
/// `307` is the redirect that preserves the method and body; the others are
/// asked for by name.
test "redirect defaults to 307 and honours an explicit status" {
  assert_eq(redirect("/a").status, 307)
  assert_eq(redirect("/a", status=HTTP_303_SEE_OTHER).status, 303)
  assert_eq(redirect("/a", status=HTTP_301_MOVED_PERMANENTLY).status, 301)
}

///|
/// The URL is encoded over the characters a URI reserves for structure, so a
/// path stays a path, a query stays a query, and an already-encoded URL is not
/// encoded twice.
test "redirect leaves URI structure alone and escapes the rest" {
  // Structural characters survive: this must still be one URL.
  assert_eq(
    redirect("https://example.test/a/b?x=1&y=2#frag").header("location"),
    Some("https://example.test/a/b?x=1&y=2#frag"),
  )
  // A space is not structure.
  assert_eq(redirect("/a b").header("location"), Some("/a%20b"))
  // `%` is safe, so an already-escaped URL passes through rather than becoming
  // `%2520`.
  assert_eq(redirect("/a%20b").header("location"), Some("/a%20b"))
}

///|
/// A `Location` is a header value, and a header value that can carry `CRLF` can
/// open a header of its own. It cannot.
test "redirect cannot smuggle a header through its URL" {
  let resp = redirect("/x\r\nSet-Cookie: stolen=1")
  assert_eq(resp.header("location"), Some("/x%0D%0ASet-Cookie:%20stolen=1"))
  // One header went out, and it is not a cookie.
  assert_eq(resp.headers.length(), 1)
  assert_eq(resp.header("set-cookie"), None)
}

///|
/// A download names itself: the type comes from the extension, the length from
/// the bytes, and the disposition tells the browser to save rather than render.
test "file_response labels the download from its filename" {
  let resp = file_response(b"hello", filename="notes.txt")
  assert_eq(resp.status, 200)
  assert_eq(resp.header("content-type"), Some("text/plain; charset=utf-8"))
  assert_eq(resp.header("content-length"), Some("5"))
  assert_eq(
    resp.header("content-disposition"),
    Some("attachment; filename=\"notes.txt\""),
  )
  assert_eq(resp.body, b"hello")
}

///|
/// The extension is a guess, and a caller who knows better says so.
test "file_response media type: guessed, overridden, and unknown" {
  assert_eq(
    file_response(b"", filename="a.png").header("content-type"),
    Some("image/png"),
  )
  assert_eq(
    file_response(b"", filename="a.PNG").header("content-type"),
    Some("image/png"),
  )
  assert_eq(
    file_response(b"", filename="a.qwq").header("content-type"),
    Some("application/octet-stream"),
  )
  assert_eq(
    file_response(b"", filename="noextension").header("content-type"),
    Some("application/octet-stream"),
  )
  assert_eq(
    file_response(b"{}", filename="a.png", media_type="application/json").header(
      "content-type",
    ),
    Some("application/json"),
  )
}

///|
/// `inline` is the same envelope with the other verb: display it rather than
/// save it.
test "file_response inline displays instead of downloading" {
  assert_eq(
    file_response(b"hhh", filename="a.txt", inline=true).header(
      "content-disposition",
    ),
    Some("inline; filename=\"a.txt\""),
  )
}

///|
/// A quoted filename cannot carry a non-ASCII name, so one that needs escaping
/// goes out as RFC 6266's `filename*` instead.
test "file_response sends a non-ASCII filename as filename*" {
  assert_eq(
    file_response(b"", filename="my notes.txt").header("content-disposition"),
    Some("attachment; filename*=utf-8''my%20notes.txt"),
  )
  // Non-ASCII is UTF-8 percent-encoded, the only form the header can carry.
  assert_eq(
    file_response(b"", filename="笔记.txt").header("content-disposition"),
    Some("attachment; filename*=utf-8''%E7%AC%94%E8%AE%B0.txt"),
  )
}

///|
/// Nothing to name, nothing to say: a body with no filename is still a response,
/// just not a download.
test "file_response without a filename omits the disposition" {
  let resp = file_response(b"raw", status=HTTP_206_PARTIAL_CONTENT)
  assert_eq(resp.status, 206)
  assert_eq(resp.header("content-disposition"), None)
  assert_eq(resp.header("content-length"), Some("3"))
}
