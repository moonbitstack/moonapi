///|
pub fn make_router(log : Array[String]) -> @moonapi.Router {
  let router = @moonapi.Router::new()
  router.get(
    "/",
    ctx => {
      @moonapi.json(
        200,
        @services.detail("query=" + ctx.query("q").unwrap_or("all")),
      )
    },
    summary="Search the catalog",
  )
  router.route_bg(
    @moonapi.Post,
    "/orders",
    (_ctx, background) => {
      background.add_task(() => log.push("order saved"))
      @moonapi.text(202, "order accepted")
    },
    summary="Queue work after responding",
  )
  router.get(
    "/large",
    _ctx => {
      @moonapi.text(200, @services.repeat_text("compressible response ", 16))
    },
    summary="Return a gzip-compressible response",
  )
  router.stream(
    "/events",
    _ctx => @moonapi.sse_response([@sse.Event::of("catalog-ready")]),
    summary="Stream a server-sent event",
  )
  router.websocket("/ws/:room", echo_once)
  router
}

///|
fn echo_once(ws : @moonapi.WebSocket) -> Unit {
  ws.accept()
  match ws.receive_text() {
    Some(message) => ws.send_text("echo: " + message)
    None => ()
  }
  ws.close()
}

///|
pub fn exercise_websocket() -> Int {
  let events = @moonapi.drive_websocket(
    echo_once,
    [@moonapi.WsText("hello")],
    params=Map([("room", "general")]),
  )
  events.length()
}
