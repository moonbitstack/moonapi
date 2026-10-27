///|
/// Server-Sent Events. An `@sse.Event` encodes to the WHATWG event-stream wire format:
/// `Event::of` is the common data-only frame, `new` sets `event` / `id` / `retry`, multi-line data
/// splits into several `data:` lines, and `ping` is a comment line that dispatches nothing.
/// `sse` builds the `text/event-stream` response around a body that sends frames for as long as
/// it likes — one chunk per frame, which is what makes it an event stream rather than a file
/// shaped like one. The app cancels the body when the client goes. A client that reconnects
/// sends the last id it saw, and `ctx.last_event_id()` lets the stream pick up after it.
///
///     moon run src/examples/17-sse --target native
#coverage.skip
async fn main {
  let events = [
    @sse.Event::of("hello"),
    @sse.Event::new(
      data="first line\nsecond line",
      kind="update",
      id="233",
      retry=3000,
    ),
    @sse.Event::ping(comment="ping"),
  ]
  let app = @moonapi.App::new()
  app.stream("/events", ctx => {
    let resumed = ctx.last_event_id() is Some(_)
    @moonapi.sse(e => {
      if resumed {
        e.send(@sse.Event::of("resumed"))
      }
      for ev in events {
        e.send(ev)
      }
    })
  })
  // The wire form: the head, one body event per frame, then the end of the body.
  let scope = @moonasgi.Scope::Http(
    @moonasgi.HttpScope::new(http_method="GET", path="/events"),
  )
  @testing.communicate(app.to_asgi(), scope, c => {
    c.send(HttpRequest(body=b"", more_body=false))
    while true {
      let event = c.receive() catch {
        @testing.Finished => break
        e => raise e
      }
      match event {
        HttpResponseStart(status~, headers~, ..) => {
          println("start \{status}")
          for h in headers {
            println("  \{h.0}: \{h.1}")
          }
        }
        HttpResponseBody(body~, more_body~) =>
          println(
            "body more_body=\{more_body} \{@utf8.decode_lossy(body[:]).escape()}",
          )
        _ => ()
      }
    }
  })
}
