// Streaming routes end to end. `to_asgi`'s http arm sends exactly
// `handle_with_stream(request).events()`, one `send` per element, so asserting
// on that array is asserting on the wire — the same way moonasgi tests its own
// `to_asgi`, whose async lift has no portable runtime to drive it on wasm or js.

///|
/// The body events of a reply, in order — test helper.
fn body_events(app : App, req : @moonasgi.Request) -> Array[@moonasgi.Event] {
  let (resp, _bg) = app.handle_with_stream(req)
  resp.events().filter(e => e is HttpResponseBody(_))
}

///|
/// The `more_body` flag of each body event, in order — test helper.
fn more_body_flags(app : App, req : @moonasgi.Request) -> Array[Bool] {
  body_events(app, req).map(e => {
    match e {
      HttpResponseBody(more_body~, ..) => more_body
      _ => false
    }
  })
}

///|
/// The point of a streaming route: the chunks stay apart all the way to the
/// wire, so a client reads the first long before the last one exists.
test "a streaming route emits one body event per chunk" {
  let app = App::new()
  app.stream("/feed", _ctx => {
    @moonasgi.StreamingResponse::new(chunks=[b"one", b"two", b"three"])
  })
  let events = body_events(app, mkreq("GET", "/feed"))
  assert_eq(events.length(), 3)
  assert_eq(
    events[0] == @moonasgi.Event::HttpResponseBody(body=b"one", more_body=true),
    true,
  )
  assert_eq(
    events[1] == @moonasgi.Event::HttpResponseBody(body=b"two", more_body=true),
    true,
  )
  // Only the last one ends the stream.
  assert_eq(
    events[2] ==
    @moonasgi.Event::HttpResponseBody(body=b"three", more_body=false),
    true,
  )
}

///|
/// Stated as the invariant rather than the transcript: every chunk but the last
/// says more is coming, and the last one says the reply is over. A stream that
/// ended early, or never ended, would both be caught here.
test "only the last body event of a stream clears more_body" {
  let app = App::new()
  app.stream("/feed", _ctx => {
    @moonasgi.StreamingResponse::new(chunks=[b"a", b"b", b"c", b"d"])
  })
  assert_eq(more_body_flags(app, mkreq("GET", "/feed")), [
    true, true, true, false,
  ])
}

///|
/// The other half of the contract: an ordinary route is still one event. If a
/// buffered reply started arriving in pieces, that would be a regression, not a
/// feature.
test "a buffered route is still a single body event" {
  let app = App::new()
  app.get("/plain", _ctx => text(200, "hello"))
  let events = body_events(app, mkreq("GET", "/plain"))
  assert_eq(events.length(), 1)
  assert_eq(
    events[0] ==
    @moonasgi.Event::HttpResponseBody(
      body=@utf8.encode("hello"),
      more_body=false,
    ),
    true,
  )
}

///|
/// The status and headers a streaming handler chose reach the wire like any
/// other route's.
test "a streaming route's status and headers survive to the response start" {
  let app = App::new()
  app.stream("/feed", _ctx => {
    @moonasgi.StreamingResponse::new(
      status=HTTP_201_CREATED,
      headers=[("x-trace", "heke1228")],
      chunks=[b"qwq"],
    )
  })
  let (resp, _bg) = app.handle_with_stream(mkreq("GET", "/feed"))
  assert_eq(resp.status, 201)
  assert_eq(header_of(resp.headers, "x-trace"), Some("heke1228"))
}

///|
/// An SSE endpoint is the case streaming exists for. Registered on a route, each
/// frame is still its own chunk — the response did not get flattened on the way
/// through the app.
test "an SSE route streams a chunk per event rather than one buffered body" {
  let app = App::new()
  app.stream("/events", _ctx => {
    sse_response([
      @sse.Event::of("one"),
      @sse.Event::of("two"),
      @sse.Event::of("three"),
    ])
  })
  let (resp, _bg) = app.handle_with_stream(mkreq("GET", "/events"))
  assert_eq(
    header_of(resp.headers, "content-type"),
    Some("text/event-stream; charset=utf-8"),
  )
  assert_eq(resp.chunks.length(), 3)
  assert_eq(resp.chunks[0], @utf8.encode("data: one\n\n"))
  assert_eq(more_body_flags(app, mkreq("GET", "/events")), [true, true, false])
}

///|
/// The buffered view of the same reply still works, so a caller that wants the
/// whole thing — a test, a middleware — reads the joined body.
test "a streamed reply joins into one body for the buffered callers" {
  let app = App::new()
  app.stream("/feed", _ctx => {
    @moonasgi.StreamingResponse::new(chunks=[b"one", b"two", b"three"])
  })
  let (resp, _bg) = app.handle_with_background(mkreq("GET", "/feed"))
  assert_eq(resp.body, b"onetwothree")
  assert_eq(app.handle(mkreq("GET", "/feed")).body, b"onetwothree")
}

///|
/// A `HEAD` reply carries no body, so a streaming route answering one has no
/// chunks to describe — it must not leak the stream it would have sent.
test "HEAD on a streaming route sends no body at all" {
  let app = App::new()
  app.stream("/feed", _ctx => {
    @moonasgi.StreamingResponse::new(chunks=[b"one", b"two"])
  })
  let events = body_events(app, mkreq("HEAD", "/feed"))
  assert_eq(events.length(), 1)
  assert_eq(
    events[0] == @moonasgi.Event::HttpResponseBody(body=b"", more_body=false),
    true,
  )
}

///|
/// The stream has to be dropped outright, not merely left to disagree with the
/// emptied body. Chunks that join to nothing agree with a `HEAD` reply's empty
/// body, so anything relying on that comparison would stream them — two body
/// events answering a request that asked for none.
test "HEAD drops a stream even when its chunks join to nothing" {
  let app = App::new()
  app.stream("/feed", _ctx => {
    @moonasgi.StreamingResponse::new(chunks=[b"", b""])
  })
  assert_eq(more_body_flags(app, mkreq("HEAD", "/feed")), [false])
}

///|
/// A middleware is typed buffered-in, buffered-out, so one that rewrites the
/// body has produced bytes the old chunk boundaries no longer describe. Cutting
/// there would send a corrupt stream, so the reply collapses to a single chunk
/// instead — the documented cost of putting `gzip` in front of a stream.
test "a body-rewriting middleware collapses a stream to one chunk" {
  let app = App::new()
  app.middleware(gzip(min_size=1))
  app.stream("/feed", _ctx => {
    @moonasgi.StreamingResponse::new(headers=[("content-type", "text/plain")], chunks=[
      b"one", b"two", b"three",
    ])
  })
  let compressed : @moonasgi.Request = {
    http_method: "GET",
    path: "/feed",
    query_string: b"",
    headers: [("accept-encoding", "gzip")],
    body: b"",
  }
  let (resp, _bg) = app.handle_with_stream(compressed)
  assert_eq(header_of(resp.headers, "content-encoding"), Some("gzip"))
  assert_eq(resp.chunks.length(), 1)
  assert_eq(more_body_flags(app, compressed), [false])
  // The same route, uncompressed, is still a stream: it is the rewrite that
  // costs the boundaries, not the presence of a middleware.
  assert_eq(more_body_flags(app, mkreq("GET", "/feed")), [true, true, false])
}

///|
/// A middleware that only reads the response leaves the boundaries alone, so the
/// stream is still a stream behind one.
test "a header-only middleware leaves the chunk boundaries intact" {
  let app = App::new()
  app.middleware(next => {
    req => {
      let resp = next(req)
      @moonasgi.Response::new(
        resp.status,
        [..resp.headers, ("x-seen", "233")],
        resp.body,
      )
    }
  })
  app.stream("/feed", _ctx => {
    @moonasgi.StreamingResponse::new(chunks=[b"one", b"two"])
  })
  let (resp, _bg) = app.handle_with_stream(mkreq("GET", "/feed"))
  assert_eq(header_of(resp.headers, "x-seen"), Some("233"))
  assert_eq(resp.chunks.length(), 2)
}

///|
/// A streaming route registered on a `Router` streams once it is included, and
/// under the prefix it was included at.
test "a router's streaming route still streams after include_router" {
  let feed = Router::new()
  feed.stream("/events", _ctx => {
    sse_response([@sse.Event::of("one"), @sse.Event::of("two")])
  })
  let app = App::new()
  app.include_router(feed, prefix="/v1")
  assert_eq(more_body_flags(app, mkreq("GET", "/v1/events")), [true, false])
}

///|
/// A stream from a mounted sub-application is still a stream when it reaches the
/// parent's wire.
test "a mounted sub-app's stream survives the mount" {
  let sub = App::new()
  sub.stream("/feed", _ctx => {
    @moonasgi.StreamingResponse::new(chunks=[b"one", b"two", b"three"])
  })
  let app = App::new()
  app.mount("/sub", sub)
  assert_eq(more_body_flags(app, mkreq("GET", "/sub/feed")), [true, true, false])
}
