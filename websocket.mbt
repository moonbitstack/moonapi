// WebSocket routes (← FastAPI's `@app.websocket(path)`). A handler talks to a
// `WebSocket` value — accept, receive, send, close — whose actions are recorded
// as `@moonasgi.Event`s (`WebSocketAccept` / `WebSocketSendText` / … / the WS
// half of the moonasgi SEAM). The handler is a synchronous core, so it runs
// identically in a test (drive an in-memory frame queue with `drive_websocket`)
// and under a real server. `App::to_asgi` provides the async serving shell.

///|
/// One inbound WebSocket message: a text frame or a binary frame.
pub(all) enum WsMessage {
  WsText(String)
  WsBinary(Bytes)
} derive(Eq)

///|
/// The handler's view of a WebSocket connection. It reads client frames off an
/// inbound queue and records its own actions (accept / send / close) into an
/// outbound event log the transport replays. `params` are the matched `:name`
/// path segments, as with an HTTP `Context`.
pub struct WebSocket {
  inbox : Array[WsMessage]
  mut cursor : Int
  params : Map[String, String]
  subprotocols : Array[String]
  mut accepted : Bool
  mut closed : Bool
  outbox : Array[@moonasgi.Event]
}

///|
/// A WebSocket route handler: given the connection, drive the exchange. Usually
/// `accept`, then a `receive` loop, then `close`.
pub type WsHandler = (WebSocket) -> Unit

///|
struct WsRoute {
  path : String
  handler : WsHandler
}

///|
/// Build a connection over a pre-supplied inbound queue — the shape a test or
/// the serving shell hands the handler.
fn WebSocket::new(
  inbox : Array[WsMessage],
  params : Map[String, String],
  subprotocols : Array[String],
) -> WebSocket {
  {
    inbox,
    cursor: 0,
    params,
    subprotocols,
    accepted: false,
    closed: false,
    outbox: [],
  }
}

///|
/// Look up a matched path parameter by name.
pub fn WebSocket::param(self : WebSocket, name : String) -> String? {
  self.params.get(name)
}

///|
/// The subprotocols the client offered (the `Sec-WebSocket-Protocol` list).
pub fn WebSocket::offered_subprotocols(self : WebSocket) -> Array[String] {
  self.subprotocols
}

///|
/// Accept the handshake (← `await websocket.accept()`), optionally selecting a
/// `subprotocol` and adding response `headers`. Idempotent: a second call is a
/// no-op, so accept-once handlers stay simple.
pub fn WebSocket::accept(
  self : WebSocket,
  subprotocol? : String? = None,
  headers? : Array[(String, String)] = [],
) -> Unit {
  if self.accepted {
    return
  }
  self.accepted = true
  self.outbox.push(@moonasgi.Event::WebSocketAccept(subprotocol~, headers~))
}

///|
/// Pull the next client frame, `None` once the client has sent them all (the
/// disconnect). The `receive` a handler loops on.
pub fn WebSocket::receive(self : WebSocket) -> WsMessage? {
  if self.cursor >= self.inbox.length() {
    return None
  }
  let m = self.inbox[self.cursor]
  self.cursor = self.cursor + 1
  Some(m)
}

///|
/// The next client frame as text: `Some(s)` for a text frame, `None` on a
/// binary frame or the disconnect (← `await websocket.receive_text()`).
pub fn WebSocket::receive_text(self : WebSocket) -> String? {
  match self.receive() {
    Some(WsText(s)) => Some(s)
    _ => None
  }
}

///|
/// The next client frame as bytes: `Some(b)` for a binary frame, `None` on a
/// text frame or the disconnect.
pub fn WebSocket::receive_bytes(self : WebSocket) -> Bytes? {
  match self.receive() {
    Some(WsBinary(b)) => Some(b)
    _ => None
  }
}

///|
/// Send a text frame to the client (← `await websocket.send_text(...)`).
pub fn WebSocket::send_text(self : WebSocket, text : String) -> Unit {
  self.outbox.push(@moonasgi.Event::WebSocketSendText(text))
}

///|
/// Send a binary frame to the client.
pub fn WebSocket::send_bytes(self : WebSocket, bytes : Bytes) -> Unit {
  self.outbox.push(@moonasgi.Event::WebSocketSendBytes(bytes))
}

///|
/// Close the connection with a status `code` (default `1000`, normal closure)
/// and `reason`. Idempotent.
pub fn WebSocket::close(
  self : WebSocket,
  code? : Int = 1000,
  reason? : String = "",
) -> Unit {
  if self.closed {
    return
  }
  self.closed = true
  self.outbox.push(@moonasgi.Event::WebSocketClose(code~, reason~))
}

///|
/// The events the handler emitted, in order — the transcript a test asserts on.
pub fn WebSocket::sent(self : WebSocket) -> Array[@moonasgi.Event] {
  self.outbox
}

///|
/// Register a WebSocket route (← FastAPI's `@app.websocket(path)`). The path
/// matches with the same `:name` segment rules as HTTP routes.
pub fn App::websocket(self : App, path : String, handler : WsHandler) -> Unit {
  self.ws_routes.push({ path, handler, })
}

///|
/// Match a WebSocket path against the registered routes, returning the handler
/// and the extracted path parameters.
fn App::match_ws(
  self : App,
  path : String,
) -> (WsHandler, Map[String, String])? {
  for route in self.ws_routes {
    match match_path(route.path, path) {
      Some(params) => return Some((route.handler, params))
      None => ()
    }
  }
  None
}

///|
/// Run a WebSocket handler against an in-memory frame queue and return the
/// events it emitted — the synchronous test driver (the WS half of a
/// `TestClient`). Feed the client's frames as `inbound`; get back the handler's
/// accept / send / close sequence.
pub fn drive_websocket(
  handler : WsHandler,
  inbound : Array[WsMessage],
  params? : Map[String, String] = Map([]),
  subprotocols? : Array[String] = [],
) -> Array[@moonasgi.Event] {
  let sock = WebSocket::new(inbound, params, subprotocols)
  handler(sock)
  sock.outbox
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
  let inbox : Array[WsMessage] = []
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
  let sock = WebSocket::new(inbox, params, scope.subprotocols)
  handler(sock)
  for ev in sock.outbox {
    send(ev)
  }
}

///|
pub extend WsMessage with Eq::{not_equal, equal}
