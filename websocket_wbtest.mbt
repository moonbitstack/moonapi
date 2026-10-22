///|
/// A router's WebSocket routes come along too, and take the prefix.
test "include_router: a WebSocket route joins under the prefix" {
  let joined : Array[String] = []
  let live = @route.Router::new()
  live.websocket("/feed/:room", ws => {
    ws.accept()
    joined.push(ws.param("room").unwrap_or("?"))
    ws.close()
  })
  let app = App::new()
  app.include_router(live, prefix="/live")
  match app.match_ws("/live/feed/qwq") {
    Some((handler, params)) => {
      let _ = @socket.drive_websocket(handler, [], params~)
      assert_eq(joined, ["qwq"])
    }
    None => fail("the included route should match under its prefix")
  }
  // The path the router knew it by is not a route on the app.
  assert_eq(app.match_ws("/feed/qwq") is None, true)
}

///|
test "ws: matched path params reach the handler" {
  let app = App::new()
  let captured : Array[String] = []
  app.websocket("/room/:id", ws => {
    ws.accept()
    captured.push(ws.param("id").unwrap_or("?"))
    ws.close()
  })
  match app.match_ws("/room/42") {
    Some((handler, params)) => {
      let _ = @socket.drive_websocket(handler, [], params~)
      assert_eq(captured[0], "42")
    }
    None => fail("route should match")
  }
  assert_eq(app.match_ws("/room/1/extra") is None, true)
}
