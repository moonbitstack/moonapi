// WebSocket routes (← FastAPI's `@app.websocket` and Starlette's `WebSocket`): a handler holds a
// live connection over the ASGI receive and send, so it can answer as messages arrive, speak
// first, or push on its own schedule.

///|
/// One WebSocket message: text or binary.
pub(all) enum WsMessage {
  WsText(String)
  WsBinary(Bytes)
} derive(Eq, Debug)

///|
pub extend WsMessage with Eq::{equal, not_equal}

///|
pub extend WsMessage with Debug::{to_repr}

///|
/// The peer left: its close code and reason (← Starlette's `WebSocketDisconnect`). `receive`
/// raises it; a handler that lets it propagate simply ends.
pub(all) suberror Disconnected {
  Disconnected(code~ : Int32, reason~ : String?)
} derive(Eq, Debug)

///|
pub extend Disconnected with Eq::{equal, not_equal}

///|
pub extend Disconnected with Debug::{to_repr}

///|
priv enum Phase {
  Connecting
  Connected
  Closed
}

///|
/// A WebSocket connection as a handler sees it.
pub struct WebSocket {
  scope : @moonasgi.WebSocketScope
  params : Map[String, String]
  priv receiver : @moonasgi.Receive
  priv sender : @moonasgi.Send
  priv mut phase : Phase
}

///|
/// A WebSocket over an ASGI connection. The app makes one per connection; a driver of its own
/// makes one over its receive and send.
pub fn WebSocket::new(
  scope : @moonasgi.WebSocketScope,
  receive : @moonasgi.Receive,
  send : @moonasgi.Send,
  params~ : Map[String, String] = {},
) -> WebSocket {
  { scope, params, receiver: receive, sender: send, phase: Connecting, }
}

///|
/// A path parameter by name.
pub fn WebSocket::param(self : WebSocket, name : String) -> String? {
  self.params.get(name)
}

///|
/// The subprotocols the client offered, in its order of preference.
pub fn WebSocket::offered_subprotocols(self : WebSocket) -> Array[String] {
  self.scope.subprotocols
}

///|
/// The first request header named `name` (lowercase, as ASGI carries them).
pub fn WebSocket::header(self : WebSocket, name : String) -> String? {
  self.scope.headers.iter().find_first(h => h.0 == name).map(h => h.1)
}

///|
/// Take the connect, then accept with `subprotocol` and extra `headers` on the handshake.
pub async fn WebSocket::accept(
  self : WebSocket,
  subprotocol? : String,
  headers~ : Array[(String, String)] = [],
) -> Unit {
  guard self.phase is Connecting else { return }
  if self.phase is Connecting {
    match (self.receiver)() {
      WebSocketConnect => ()
      WebSocketDisconnect(code~, reason~) => {
        self.phase = Closed
        raise Disconnected(code~, reason~)
      }
      _ => ()
    }
  }
  self.phase = Connected
  (self.sender)(WebSocketAccept(subprotocol~, headers~))
}

///|
/// The next message. Raises `Disconnected` when the peer has left.
pub async fn WebSocket::receive(self : WebSocket) -> WsMessage {
  for ;; {
    guard !(self.phase is Closed) else {
      raise Disconnected(code=1006, reason=None)
    }
    match (self.receiver)() {
      WebSocketReceive(text=Some(t), ..) => return WsText(t)
      WebSocketReceive(bytes=Some(b), ..) => return WsBinary(b)
      WebSocketDisconnect(code~, reason~) => {
        self.phase = Closed
        raise Disconnected(code~, reason~)
      }
      _ => ()
    }
  }
}

///|
/// The next message, which must be text; a binary message is taken as its UTF-8.
pub async fn WebSocket::receive_text(self : WebSocket) -> String {
  match self.receive() {
    WsText(t) => t
    WsBinary(b) => @utf8.decode_lossy(b)
  }
}

///|
/// The next message, which must be binary; a text message is taken as its UTF-8.
pub async fn WebSocket::receive_bytes(self : WebSocket) -> Bytes {
  match self.receive() {
    WsBinary(b) => b
    WsText(t) => @utf8.encode(t)
  }
}

///|
/// The next message parsed as JSON.
pub async fn WebSocket::receive_json(self : WebSocket) -> Json {
  @json.parse(self.receive_text())
}

///|
/// Send `message`.
pub async fn WebSocket::send(self : WebSocket, message : WsMessage) -> Unit {
  match message {
    WsText(t) => (self.sender)(WebSocketSendText(t))
    WsBinary(b) => (self.sender)(WebSocketSendBytes(b))
  }
}

///|
/// Send a text message.
pub async fn WebSocket::send_text(self : WebSocket, text : String) -> Unit {
  self.send(WsText(text))
}

///|
/// Send a binary message.
pub async fn WebSocket::send_bytes(self : WebSocket, bytes : Bytes) -> Unit {
  self.send(WsBinary(bytes))
}

///|
/// Send `value` serialised as a text message.
pub async fn WebSocket::send_json(self : WebSocket, value : Json) -> Unit {
  self.send(WsText(value.stringify()))
}

///|
/// Close with `code` and `reason`. Before `accept` this declines the handshake, which a server
/// answers with `403`.
pub async fn WebSocket::close(
  self : WebSocket,
  code~ : Int32 = 1000,
  reason~ : String = "",
) -> Unit {
  guard !(self.phase is Closed) else { return }
  self.phase = Closed
  (self.sender)(WebSocketClose(code~, reason~))
}

///|
/// A WebSocket route's handler (← FastAPI's `@app.websocket` endpoint).
pub type WsHandler = async (WebSocket) -> Unit

///|
/// A registered WebSocket route.
pub(all) struct WsRoute {
  path : String
  handler : WsHandler
}
