///|
/// Server-Sent Events framing. An `@sse.Event` encodes to the WHATWG
/// event-stream wire format: `Event::of` is the common data-only
/// frame, `new` sets `event` / `id` / `retry`, multi-line data splits into
/// several `data:` lines, and `keep_alive` emits a `:`-comment ping that
/// dispatches nothing. `sse_response` wraps a batch into a `text/event-stream`
/// stream with the no-cache / keep-alive headers — one chunk per frame, which is
/// what makes it an event stream rather than a file shaped like one. Hand it to
/// `App::stream` and each frame reaches the client on its own.
///
///     moon run examples/17-sse
#coverage.skip
fn main {
  let events = [
    @sse.Event::of("hello"),
    @sse.Event::new(
      data="first line\nsecond line",
      kind=Some("update"),
      id=Some("233"),
      retry=Some(3000),
    ),
    @sse.Event::ping(comment="ping"),
  ]
  println("--- individual frames (blank line dispatches each event) ---")
  let frames = StringBuilder()
  for ev in events {
    frames.write_string(ev.encode())
  }
  println(frames.to_string())
  let resp = @moonapi.sse_response(events)
  println("--- sse_response ---")
  println("status=\{resp.status}")
  for h in resp.headers {
    println("\{h.0}: \{h.1}")
  }
  println("chunks: \{resp.chunks.length()}")

  // The wire form: one body event per frame, and `more_body` false only on the
  // last — the client dispatches each event as it arrives.
  println("--- lowered events ---")
  for ev in resp.events() {
    match ev {
      HttpResponseBody(body~, more_body~) =>
        println(
          "body more_body=\{more_body} \{@utf8.decode_lossy(body[:]).escape()}",
        )
      HttpResponseStart(status~, ..) => println("start status=\{status}")
      _ => ()
    }
  }
}
