// Serving content with the request taken into account: the four answers of
// RFC 9110 §13 and §14 that a handler should not have to write out again.

///|
fn asking(verb : String, headers : Array[(String, String)]) -> Context {
  {
    request: {
      http_method: verb,
      path: "/f",
      query_string: b"",
      headers,
      body: b"",
    },
    params: Map([]),
  }
}

///|
/// Ten octets, so every offset in these tests can be read off by eye.
let sample : Bytes = b"0123456789"

///|
/// Nothing asked: the whole thing, with the validator the next request will
/// send back and the offer that makes resuming possible.
test "serve answers a plain GET with the whole representation" {
  let resp = asking("GET", []).serve(sample, filename="d.txt")
  assert_eq(resp.status, 200)
  assert_eq(resp.body, sample)
  assert_eq(resp.header("content-length"), Some("10"))
  assert_eq(resp.header("content-type"), Some("text/plain; charset=utf-8"))
  assert_eq(resp.header("accept-ranges"), Some("bytes"))
  // The default tag is the content's own SHA-256, prefixed by the length.
  assert_eq(
    resp.header("etag"),
    Some(
      "\"a-84d89877f0d4041efb6bf91a16f0248f2fd573e6af05c19f96bedb9f882f7882\"",
    ),
  )
}

///|
/// The second request for the same thing.
test "serve answers a matching If-None-Match with 304 and no body" {
  let tag = @conditional.Tag::new("v1")
  let resp = asking("GET", [("If-None-Match", "\"v1\"")]).serve(
    sample,
    etag=tag,
  )
  assert_eq(resp.status, 304)
  assert_eq(resp.body, b"")
  assert_eq(resp.header("etag"), Some("\"v1\""))
  // §15.4.5: a 304 describes no body, so it does not claim one.
  assert_eq(resp.header("content-length"), None)
  assert_eq(resp.header("content-type"), None)
  // A tag that does not match gets the body.
  let stale = asking("GET", [("If-None-Match", "\"v0\"")]).serve(
    sample,
    etag=tag,
  )
  assert_eq(stale.status, 200)
  assert_eq(stale.body, sample)
}

///|
/// The same field on a write means something else: not "you have it already"
/// but "you may not do that" (§13.2.2 step 3).
test "serve answers a failed precondition on a write with 412" {
  let tag = @conditional.Tag::new("v1")
  let resp = asking("PUT", [("If-Match", "\"v0\"")]).serve(sample, etag=tag)
  assert_eq(resp.status, 412)
  assert_eq(resp.body, b"")
  let allowed = asking("PUT", [("If-Match", "\"v1\"")]).serve(sample, etag=tag)
  assert_eq(allowed.status, 200)
  // And the same failure read by a GET is a 304 rather than a 412.
  let reading = asking("GET", [("If-None-Match", "*")]).serve(sample, etag=tag)
  assert_eq(reading.status, 304)
}

///|
/// A last-modified date is a validator too, and the field that compares it is
/// for reads only (§13.1.3).
test "serve honours the date conditions" {
  let when = @moondate.http("Sun, 06 Nov 1994 08:49:37 GMT")
  let later = @moondate.http("Mon, 07 Nov 1994 08:49:37 GMT")
  let ctx = asking("GET", [
    ("If-Modified-Since", "Sun, 06 Nov 1994 08:49:37 GMT"),
  ])
  assert_eq(ctx.serve(sample, modified=when).status, 304)
  assert_eq(ctx.serve(sample, modified=later).status, 200)
  assert_eq(
    ctx.serve(sample, modified=when).header("last-modified"),
    Some("Sun, 06 Nov 1994 08:49:37 GMT"),
  )
}

///|
/// One range: a 206 whose `Content-Range` says which octets these are and how
/// many there are altogether (§14.4).
test "serve answers one range with a 206" {
  let resp = asking("GET", [("Range", "bytes=2-5")]).serve(sample)
  assert_eq(resp.status, 206)
  assert_eq(resp.body, b"2345")
  assert_eq(resp.header("content-range"), Some("bytes 2-5/10"))
  assert_eq(resp.header("content-length"), Some("4"))
  // A suffix range counts from the end.
  let tail = asking("GET", [("Range", "bytes=-3")]).serve(sample)
  assert_eq(tail.body, b"789")
  assert_eq(tail.header("content-range"), Some("bytes 7-9/10"))
  // An open-ended one runs to the end.
  let rest = asking("GET", [("Range", "bytes=7-")]).serve(sample)
  assert_eq(rest.body, b"789")
}

///|
/// Several ranges: one body with a part for each (§14.6).
test "serve answers several ranges with multipart/byteranges" {
  let resp = asking("GET", [("Range", "bytes=0-1,8-9")]).serve(
    sample,
    etag=@conditional.Tag::new("v1"),
  )
  assert_eq(resp.status, 206)
  assert_eq(
    resp.header("content-type"),
    Some("multipart/byteranges; boundary=moonapi-v1"),
  )
  let body = @utf8.decode_lossy(resp.body[:])
  assert_true(body.contains("Content-Range: bytes 0-1/10"))
  assert_true(body.contains("Content-Range: bytes 8-9/10"))
  assert_true(body.contains("--moonapi-v1--"))
  // The length claimed is the length sent.
  assert_eq(resp.header("content-length"), Some(resp.body.length().to_string()))
  // RFC 2046 §5.1.1 allows seventy octets of boundary and no more, which a
  // SHA-256 tag on its own already exceeds.
  let hashed = asking("GET", [("Range", "bytes=0-1,8-9")]).serve(sample)
  guard hashed.header("content-type") is Some(kind) else { fail("no type") }
  assert_true(kind.length() - "multipart/byteranges; boundary=".length() <= 70)
}

///|
/// Asking for what is not there (§14.4, §15.5.17).
test "serve answers an unsatisfiable range with 416" {
  let resp = asking("GET", [("Range", "bytes=20-30")]).serve(sample)
  assert_eq(resp.status, 416)
  assert_eq(resp.header("content-range"), Some("bytes */10"))
  assert_eq(resp.body, b"")
  // A `Range` that is not a range at all is ignored rather than refused: §14.2
  // says a recipient that cannot read the field must act as if it were absent.
  let nonsense = asking("GET", [("Range", "octets=1-2")]).serve(sample)
  assert_eq(nonsense.status, 200)
  assert_eq(nonsense.body, sample)
}

///|
/// §13.1.5: a range asked for against a copy that has since changed is a
/// request for the whole thing, not an error.
test "serve gives the whole thing when If-Range no longer holds" {
  let tag = @conditional.Tag::new("v1")
  let held = asking("GET", [("Range", "bytes=2-5"), ("If-Range", "\"v1\"")])
  assert_eq(held.serve(sample, etag=tag).status, 206)
  let moved = asking("GET", [("Range", "bytes=2-5"), ("If-Range", "\"v0\"")])
  let resp = moved.serve(sample, etag=tag)
  assert_eq(resp.status, 200)
  assert_eq(resp.body, sample)
}

///|
/// Two knobs, both sides.
test "serve can be told not to offer ranges, and answers HEAD without a body" {
  let plain = asking("GET", [("Range", "bytes=2-5")]).serve(
    sample,
    ranges=false,
  )
  assert_eq(plain.status, 200)
  assert_eq(plain.body, sample)
  assert_eq(plain.header("accept-ranges"), Some("none"))
  // A HEAD gets the headers a GET would and nothing after them.
  let head = asking("HEAD", []).serve(sample, filename="d.txt")
  assert_eq(head.status, 200)
  assert_eq(head.body, b"")
  assert_eq(head.header("content-length"), Some("10"))
  // A supplied tag is used as given, hash or no hash.
  let cheap = @conditional.stamp(
    length=10L,
    modified=@moondate.http("Sun, 06 Nov 1994 08:49:37 GMT"),
  )
  assert_eq(
    asking("GET", []).serve(sample, etag=cheap).header("etag"),
    Some("W/\"2ebc98a1-a\""),
  )
}

// ------------------------------------------------------------------ data URLs

///|
/// What `canvas.toDataURL()` hands a client, served back as what it says it is.
test "a data URL becomes a response, and bytes become a data URL" {
  let resp = data_response("data:image/png;base64,AAEC", filename="x.png")
  guard resp is Some(resp) else { fail("a data URL did not become a response") }
  assert_eq(resp.status, 200)
  assert_eq(resp.body, b"\x00\x01\x02")
  assert_eq(resp.header("content-type"), Some("image/png"))
  // Inline by default: a data URL is something to show, not to save.
  assert_true(
    resp.header("content-disposition") is Some(value) &&
    value.has_prefix("inline"),
  )
  // Not a data URL is not a response.
  assert_true(data_response("https://example.test/x.png") is None)
  assert_true(data_response("") is None)
  // And back the other way.
  assert_eq(
    data_url(b"\x00\x01\x02", media_type="image/png"),
    "data:image/png;base64,AAEC",
  )
  assert_eq(data_url(b"hi"), "data:;base64,aGk=")
}
