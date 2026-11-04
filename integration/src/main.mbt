///|
/// Serve the task API on the native server, over a SQLite file the lifespan opens
/// and closes.
///
///     moon run integration/src --target native
///
/// Then, in another shell:
///
///     curl http://127.0.0.1:12000/tasks
///     curl -X POST http://127.0.0.1:12000/tasks \
///          -H "x-api-key: s3cret" -H "content-type: application/json" \
///          -d '{"title":"try it"}'
#coverage.skip
async fn main {
  // The annotation registration, which is the one this example recommends; the
  // other two are beside it and answer exactly the same, which is what the check
  // asserts.
  let app = @ann.build()
  app.on_startup(_ => @shared.start("tasks.db"))
  app.on_shutdown(_ => @shared.stop())
  println(
    "moonapi serving on http://127.0.0.1:12000 — the database is tasks.db",
  )
  @mooncat.serve(app.to_asgi(), port=12000) catch {
    err => println("mooncat stopped: \{err}")
  }
}
