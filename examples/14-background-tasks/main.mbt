///|
/// Background tasks — work that runs *after* the response is sent. A background
/// aware route (`App::route_bg`) receives a `BackgroundTasks` queue and
/// `add_task`s thunks onto it; `handle_with_background` returns the response
/// together with the still-unrun queue, so you can see the response is ready
/// before any task fires. Draining the queue (`run`, what `to_asgi` calls once
/// the body is on the wire) then executes them in order. Plain `handle` drops
/// the queue — a task's latency never delays the client.
///
///     moon run examples/14-background-tasks
#coverage.skip
fn main {
  let log : Array[String] = []
  let app = @moonapi.App::new()
  app.route_bg(Post, "/notify", (ctx, bg) => {
    let who = ctx.query("to").unwrap_or("nobody")
    bg.add_task(() => log.push("email sent to \{who}"))
    bg.add_task(() => log.push("audit row written for \{who}"))
    @moonapi.text(202, "accepted")
  })
  let req : @moonasgi.Request = {
    http_method: "POST",
    path: "/notify",
    query_string: @utf8.encode("to=lfanke"),
    headers: [],
    body: b"",
  }

  // The response comes back with the tasks still queued, not yet run.
  let (resp, bg) = app.handle_with_background(req)
  println("POST /notify -> \{resp.status} \{@utf8.decode_lossy(resp.body[:])}")
  println("queued tasks: \{bg.len()}")
  println("log before drain: [\{join_csv(log)}]")

  // The app drains the queue after the response is on the wire.
  bg.run()
  println("log after drain:  [\{join_csv(log)}]")
  println("queued tasks now: \{bg.len()}")

  // Plain handle drops the queue entirely — the tasks never run.
  log.clear()
  let dropped = app.handle(req)
  println("plain handle -> \{dropped.status}, log stays [\{join_csv(log)}]")
}

///|
/// Join strings with `; ` — the run log is a list, which renders through `Debug`
/// rather than string interpolation.
fn join_csv(xs : Array[String]) -> String {
  let sb = StringBuilder()
  for i = 0; i < xs.length(); i = i + 1 {
    if i > 0 {
      sb.write_string("; ")
    }
    sb.write_string(xs[i])
  }
  sb.to_string()
}
