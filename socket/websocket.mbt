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
  mut cursor : Int32
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
pub(all) struct WsRoute {
  path : String
  handler : WsHandler
}

///|
/// Build a connection over a pre-supplied inbound queue — the shape a test or
/// the serving shell hands the handler.
pub fn WebSocket::new(
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
  subprotocol? : String,
  headers~ : Array[(String, String)] = [],
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
  code~ : Int32 = 1000,
  reason~ : String = "",
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
/// Run a WebSocket handler against an in-memory frame queue and return the
/// events it emitted — the synchronous test driver (the WS half of a
/// `TestClient`). Feed the client's frames as `inbound`; get back the handler's
/// accept / send / close sequence.
pub fn drive_websocket(
  handler : WsHandler,
  inbound : Array[WsMessage],
  params~ : Map[String, String] = Map([]),
  subprotocols~ : Array[String] = [],
) -> Array[@moonasgi.Event] {
  let sock = WebSocket::new(inbound, params, subprotocols)
  handler(sock)
  sock.outbox
}

///|
pub extend WsMessage with Eq::{not_equal, equal}
