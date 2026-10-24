///|
/// Startup and shutdown hooks (← FastAPI's `on_event`). A server drives them over the ASGI
/// lifespan protocol; here a test client does, in-process: startup in registration order, the
/// requests in between, shutdown in reverse, so a resource is released before whatever it was
/// opened from. What a startup hook stores in the lifespan state is in every request's
/// `ctx.state()`.
///
///     moon run src/examples/23-lifespan --target native
#coverage.skip
async fn main {
  let log : Array[String] = []
  let app = @moonapi.App::new()
  app.on_startup(state => {
    state["db"] = "pool-1"
    log.push("connect db")
  })
  app.on_startup(_ => log.push("warm cache"))
  app.on_shutdown(_ => log.push("close db"))
  app.on_shutdown(_ => log.push("drop cache"))
  app.get("/db", ctx => {
    @moonapi.json(200, ctx.state().get("db").unwrap_or(Json::null()))
  })
  let client = @testing.Client::new(app.to_asgi())
  client.lifespan(() => log.push("request saw \{client.get("/db").text()}"))
  println(log.join(" -> "))
}
