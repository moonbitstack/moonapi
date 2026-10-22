///|
/// One header out of a list, by lowercased name.
fn header_of(headers : Array[(String, String)], name : String) -> String? {
  for pair in headers {
    if pair.0.to_lower() == name {
      return Some(pair.1)
    }
  }
  None
}

///|
/// How many times `name` appears among a response's headers.
fn header_count(headers : Array[(String, String)], name : String) -> Int32 {
  let mut n = 0
  for h in headers {
    if h.0.to_lower() == name {
      n += 1
    }
  }
  n
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
