///|
/// Background tasks — work that runs after the response is sent (← FastAPI's
/// `BackgroundTasks`). Every handler has `ctx.background`; what it adds runs in order once the
/// response has gone out, so a task's latency never delays the client. A layer that notes when
/// the last body event passes shows the order.
///
///     moon run src/examples/14-background-tasks --target native
#coverage.skip
async fn main {
  let log : Array[String] = []
  let app = @moonapi.App::new()
  app.layer(
    @mid.Wrap(inner => {
      async fn(scope, receive, send) {
        inner(scope, receive, event => {
          send(event)
          if event is HttpResponseBody(more_body=false, ..) {
            log.push("response sent")
          }
        })
      }
    }),
  )
  app.post("/notify", ctx => {
    let who = ctx.query("to").unwrap_or("nobody")
    ctx.background.add_task(() => log.push("email sent to \{who}"))
    ctx.background.add_task(() => log.push("audit row written for \{who}"))
    log.push("handler answered")
    @moonapi.text(202, "accepted")
  })
  let resp = app.handle({
    http_method: "POST",
    path: "/notify",
    query_string: @utf8.encode("to=lfanke"),
    headers: [],
    body: b"",
  })
  println("POST /notify -> \{resp.status} \{@utf8.decode_lossy(resp.body[:])}")
  for line in log {
    println("  " + line)
  }
}
