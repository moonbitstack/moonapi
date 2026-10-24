///|
/// Open a WebSocket to `path` on the app, send `messages`, then disconnect, and every event the
/// app sent.
async fn ws_session(
  app : App,
  path : String,
  messages? : Array[String],
) -> Array[@moonasgi.Event] {
  let scope = @moonasgi.Scope::WebSocket(@moonasgi.WebSocketScope::new(path~))
  @testing.communicate(app.to_asgi(), scope, c => {
    c.send(WebSocketConnect)
    for m in messages.unwrap_or([]) {
      c.send(WebSocketReceive(text=Some(m), bytes=None))
    }
    c.send(WebSocketDisconnect(code=1000, reason=None))
    let out = []
    while true {
      let event = c.receive() catch {
        @testing.Finished => break
        e => raise e
      }
      out.push(event)
    }
    out
  })
}

///|
/// A router's WebSocket routes come along too, and take the prefix.
async test "include_router: a WebSocket route joins under the prefix" {
  let joined : Array[String] = []
  let live = @route.Router::new()
  live.websocket("/feed/:room", ws => {
    ws.accept()
    joined.push(ws.param("room").unwrap_or("?"))
    ws.close()
  })
  let app = App::new()
  app.include_router(live, prefix="/live")
  let events = ws_session(app, "/live/feed/qwq")
  assert_true(events is [WebSocketAccept(..), WebSocketClose(code=1000, ..)])
  assert_eq(joined, ["qwq"])
  // The path the router knew it by is not a route on the app, which declines it.
  assert_true(ws_session(app, "/feed/qwq") is [WebSocketClose(code=1000, ..)])
}

///|
async test "ws: matched path params reach the handler, an unmatched path is declined" {
  let app = App::new()
  let captured : Array[String] = []
  app.websocket("/room/:id", ws => {
    ws.accept()
    captured.push(ws.param("id").unwrap_or("?"))
    ws.close()
  })
  ignore(ws_session(app, "/room/42"))
  assert_eq(captured, ["42"])
  assert_true(ws_session(app, "/room/1/extra") is [WebSocketClose(..)])
}

///|
/// The connection is live: the server speaks first, answers as messages arrive, and a peer that
/// leaves ends the handler quietly.
async test "ws: a handler talks over the live connection until the peer leaves" {
  let app = App::new()
  app.websocket("/chat", ws => {
    ws.accept()
    ws.send_text("welcome")
    for ;; {
      let line = ws.receive_text()
      ws.send_text("echo " + line)
    }
  })
  let events = ws_session(app, "/chat", messages=["one", "two"])
  assert_true(
    events
    is [
      WebSocketAccept(..),
      WebSocketSendText("welcome"),
      WebSocketSendText("echo one"),
      WebSocketSendText("echo two"),
    ],
  )
}

///|
async test "ws: a mounted app's WebSocket route answers under the prefix" {
  let sub = App::new()
  let roots : Array[String] = []
  sub.websocket("/live", ws => {
    roots.push(ws.scope.root_path)
    ws.accept()
    ws.close()
  })
  let app = App::new()
  app.mount("/sub", sub)
  assert_true(
    ws_session(app, "/sub/live") is [WebSocketAccept(..), WebSocketClose(..)],
  )
  assert_eq(roots, ["/sub"])
}
