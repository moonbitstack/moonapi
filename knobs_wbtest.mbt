// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// How many times `name` appears among a response's headers.
fn header_count(headers : Array[(String, String)], name : String) -> Int {
  let mut n = 0
  for h in headers {
    if h.0.to_lower() == name {
      n += 1
    }
  }
  n
}

///|
/// The bound on a query string is the caller's to set, and the preset is the
/// one Express carries: `qs` allows a thousand parameters by default.
test "the query bound is public and reaches both extractors" {
  inspect(query_limits.parts, content="1000")
  let many = StringBuilder()
  for i in 0..<40 {
    if i > 0 {
      many.write_char('&')
    }
    many.write_string("tag=\{i}")
  }
  let c = qctx(@utf8.encode(many.to_string()[:]))
  // Under the preset, all forty are there.
  inspect(c.query_all("tag").length(), content="40")
  inspect(q(c, "tag"), content="0")
  // Under a bound of eight, the query is refused rather than truncated, and an
  // extractor that cannot answer answers nothing.
  let tight = @mime.Limits::new(parts=8)
  inspect(c.query_all("tag", limits=tight).length(), content="0")
  inspect(c.query("tag", limits=tight) is None, content="true")
  // And a bound it fits under changes nothing.
  inspect(
    c.query_all("tag", limits=@mime.Limits::new(parts=100)).length(),
    content="40",
  )
}

///|
/// `extra` adds claims. Where it names one the arguments already set, the
/// arguments win — and being given two answers is reported rather than one of
/// them being dropped in silence.
test "extra adds claims and cannot quietly replace them" {
  let secret = "a-secret"
  let plain = create_access_token("heke", secret, 1700000000L)
  let with_extra = create_access_token("heke", secret, 1700000000L, extra={
    "tenant": Json::string("acme"),
  })
  assert_not_eq(plain, with_extra)
  let claims = @jwt.verify(
    with_extra[:],
    HS256,
    hs256(secret),
    now=At(1700000100L),
  )
  assert_eq(claims.get("tenant"), Some(Json::string("acme")))
  assert_eq(claims.get("sub"), Some(Json::string("heke")))
  // Asked to let `extra` win, it does.
  let overridden = create_access_token(
    "heke",
    secret,
    1700000000L,
    extra={ "sub": Json::string("somebody else") },
    wins=Extra,
    clash=Ignore,
  )
  let claims = @jwt.verify(
    overridden[:],
    HS256,
    hs256(secret),
    now=At(1700000100L),
  )
  assert_eq(claims.get("sub"), Some(Json::string("somebody else")))
  // Silenced without flipping the direction, the argument still wins.
  let kept = create_access_token(
    "heke",
    secret,
    1700000000L,
    extra={ "sub": Json::string("somebody else") },
    clash=Ignore,
  )
  let claims = @jwt.verify(kept[:], HS256, hs256(secret), now=At(1700000100L))
  assert_eq(claims.get("sub"), Some(Json::string("heke")))
}

///|
test "panic a claim given twice is a mistake in the program" {
  create_access_token("heke", "a-secret", 1700000000L, extra={
    "sub": Json::string("somebody else"),
  })
  |> ignore
}

///|
/// A response carrying two `content-type` headers is not a response with a
/// choice in it.
test "a stream sets each header once" {
  let events = [@sse.Event::of("hello")]
  let plain = sse_response(events)
  inspect(header_count(plain.headers, "content-type"), content="1")
  inspect(header_count(plain.headers, "cache-control"), content="1")
  // A header of the caller's own joins the three.
  let tagged = sse_response(events, headers=[("x-trace", "7")])
  inspect(header_count(tagged.headers, "x-trace"), content="1")
  inspect(tagged.headers.length(), content="4")
  // One that names ours replaces it rather than joining it.
  let proxied = sse_response(events, headers=[("cache-control", "no-store")])
  inspect(header_count(proxied.headers, "cache-control"), content="1")
  assert_eq(header_of(proxied.headers, "cache-control"), Some("no-store"))
  inspect(proxied.headers.length(), content="3")
  // Case does not create a second one either.
  let shouty = sse_response(events, headers=[("Cache-Control", "no-store")])
  inspect(header_count(shouty.headers, "cache-control"), content="1")
  // Asked to keep ours, it keeps ours.
  let ours = sse_response(
    events,
    headers=[("cache-control", "no-store")],
    wins=Base,
  )
  assert_eq(header_of(ours.headers, "cache-control"), Some("no-cache"))
  inspect(ours.headers.length(), content="3")
}

///|
test "panic a header given twice can be made to say so" {
  sse_response(
    [@sse.Event::of("hello")],
    headers=[("content-type", "text/plain")],
    clash=Panic,
  )
  |> ignore
}

///|
/// The optional space in a frame reaches the response builder.
test "the frame's optional space reaches the response" {
  let events = [@sse.Event::of("hello")]
  assert_eq(sse_response(events).chunks[0], @utf8.encode("data: hello\n\n"[:]))
  assert_eq(
    sse_response(events, space=false).chunks[0],
    @utf8.encode("data:hello\n\n"[:]),
  )
}
