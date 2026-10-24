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
  let events = (e : Events) => e.send(@sse.Event::of("hello"))
  let plain = sse(events)
  inspect(header_count(plain.headers, "content-type"), content="1")
  inspect(header_count(plain.headers, "cache-control"), content="1")
  // A header of the caller's own joins the three.
  let tagged = sse(events, headers=[("x-trace", "7")])
  inspect(header_count(tagged.headers, "x-trace"), content="1")
  inspect(tagged.headers.length(), content="4")
  // One that names ours replaces it rather than joining it.
  let proxied = sse(events, headers=[("cache-control", "no-store")])
  inspect(header_count(proxied.headers, "cache-control"), content="1")
  assert_eq(header_of(proxied.headers, "cache-control"), Some("no-store"))
  inspect(proxied.headers.length(), content="3")
  // Case does not create a second one either.
  let shouty = sse(events, headers=[("Cache-Control", "no-store")])
  inspect(header_count(shouty.headers, "cache-control"), content="1")
  // Asked to keep ours, it keeps ours.
  let ours = sse(events, headers=[("cache-control", "no-store")], wins=Base)
  assert_eq(header_of(ours.headers, "cache-control"), Some("no-cache"))
  inspect(ours.headers.length(), content="3")
}

///|
test "panic a header given twice can be made to say so" {
  sse(
    e => e.send(@sse.Event::of("hello")),
    headers=[("content-type", "text/plain")],
    clash=Panic,
  )
  |> ignore
}

///|
/// Write `stream`'s body into a list of chunks, the way the app writes it to the wire.
async fn chunks_of(stream : Stream) -> Array[Bytes] {
  let out = []
  (stream.body)(Writer::new(chunk => out.push(chunk)))
  out
}

///|
/// The optional space in a frame reaches the response builder, and each event is a chunk of its
/// own.
async test "each event is one chunk, with the frame's optional space as asked" {
  let two = (e : Events) => {
    e.send(@sse.Event::of("hello"))
    e.send(@sse.Event::of("again"))
  }
  assert_eq(chunks_of(sse(two)), [b"data: hello\n\n", b"data: again\n\n"])
  assert_eq(chunks_of(sse(two, space=false))[0], b"data:hello\n\n")
}

///|
async test "a ping is a comment line a client ignores" {
  assert_eq(chunks_of(sse(e => e.ping(comment="keep"))), [b": keep\n\n"])
}

///|
async test "a writer sends no empty chunk and keeps the trailers it is given" {
  let seen = []
  let w = Writer::new(chunk => seen.push(chunk))
  w.write(b"")
  w.write_text("x")
  w.trailer("x-sum", "1")
  assert_eq(seen, [b"x"])
  assert_eq(w.trailers(), [("x-sum", "1")])
}
