// WebSocket routes (← FastAPI's `@app.websocket(path)`). A handler talks to a
// `WebSocket` value — accept, receive, send, close — whose actions are recorded
// as `@moonasgi.Event`s (`WebSocketAccept` / `WebSocketSendText` / … / the WS
// half of the moonasgi SEAM). The handler is a synchronous core, so it runs
// identically in a test (drive an in-memory frame queue with `drive_websocket`)
// and under a real server. `App::to_asgi` provides the async serving shell.

///|
/// Register a WebSocket route (← FastAPI's `@app.websocket(path)`). The path
/// matches with the same `:name` segment rules as HTTP routes.
pub fn App::websocket(
  self : App,
  path : String,
  handler : @socket.WsHandler,
) -> Unit {
  self.ws_routes.push({ path, handler, })
}

///|
/// Match a WebSocket path against the registered routes, returning the handler
/// and the extracted path parameters.
fn App::match_ws(
  self : App,
  path : String,
) -> (@socket.WsHandler, Map[String, String])? {
  for route in self.ws_routes {
    match match_path(route.path, path) {
      Some(params) => return Some((route.handler, params))
      None => ()
    }
  }
  None
}

///|
/// The async serving shell for a WebSocket scope, driven by `App::to_asgi`. It
/// buffers the client's inbound frames off the SEAM, runs the handler's sync
/// core, then emits its accept / send / close events.
///
/// Because the sync core cannot suspend on the async transport (MoonBit's async
/// wall — see the README design note), it sees the client's whole frame
/// sequence before it runs rather than interleaving live. Message content and
/// order are preserved, which is exact for echo, broadcast, and request-reply
/// handlers; live per-frame duplex is the documented boundary.
async fn App::serve_websocket(
  self : App,
  scope : @moonasgi.WebSocketScope,
  receive : @moonasgi.Receive,
  send : @moonasgi.Send,
) -> Unit {
  let (handler, params) = match self.match_ws(scope.path) {
    Some(pair) => pair
    None => {
      send(@moonasgi.Event::WebSocketClose(code=1000, reason="no route"))
      return
    }
  }
  // Consume the connect, then drain frames until the client disconnects.
  let _ = receive()
  let inbox : Array[@socket.WsMessage] = []
  let mut open = true
  while open {
    match receive() {
      WebSocketReceive(text~, bytes~) =>
        match text {
          Some(t) => inbox.push(WsText(t))
          None =>
            match bytes {
              Some(b) => inbox.push(WsBinary(b))
              None => ()
            }
        }
      _ => open = false
    }
  }
  let sock = @socket.WebSocket::new(inbox, params, scope.subprotocols)
  handler(sock)
  for ev in sock.outbox {
    send(ev)
  }
}
