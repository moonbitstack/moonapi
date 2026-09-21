///|
/// An echo handler: accept, then mirror each frame until the client disconnects.
fn echo(ws : @moonapi.WebSocket) -> Unit {
  ws.accept(subprotocol=Some("chat"))
  println(
    "  echo: room=\{ws.param("room").unwrap_or("?")} offered=[\{join_csv(ws.offered_subprotocols())}]",
  )
  let mut open = true
  while open {
    match ws.receive() {
      Some(@moonapi.WsText(t)) => ws.send_text("echo: " + t)
      Some(@moonapi.WsBinary(b)) => ws.send_bytes(b)
      None => open = false
    }
  }
  println("  echo: queued \{ws.sent().length()} events before close")
  ws.close(reason="bye")
}

///|
/// A request-reply handler using the typed `receive_text` / `receive_bytes`.
fn req_reply(ws : @moonapi.WebSocket) -> Unit {
  ws.accept()
  match ws.receive_text() {
    Some(t) => ws.send_text("hello, " + t)
    None => ()
  }
  match ws.receive_bytes() {
    Some(b) => ws.send_bytes(b)
    None => ()
  }
  ws.close()
}

///|
/// WebSocket routes over the moonasgi WS SEAM. `App::websocket` registers a
/// handler; the handler drives a synchronous `WebSocket` — accept, receive
/// (`receive` / `receive_text` / `receive_bytes`), send, close — and its actions
/// are recorded as `@moonasgi.Event`s. `drive_websocket` runs that sync core
/// against an in-memory frame queue (the WS half of a TestClient), so the same
/// handler that `App::to_asgi` serves over the async transport is exercised here
/// in-process. `param` and `offered_subprotocols` mirror the HTTP context.
///
///     moon run examples/18-websocket
#coverage.skip
fn main {
  let app = @moonapi.App::new()
  app.websocket("/ws/:room", echo)
  app.websocket("/greet", req_reply)

  println("echo /ws/233 (text then binary):")
  let echoed = @moonapi.drive_websocket(
    echo,
    [@moonapi.WsText("hi"), @moonapi.WsBinary(b"\x02\x33\x33")],
    params=Map([("room", "233")]),
    subprotocols=["chat", "superchat"],
  )
  show(echoed)

  println("request-reply /greet:")
  let replied = @moonapi.drive_websocket(req_reply, [
    @moonapi.WsText("lfanke"),
    @moonapi.WsBinary(b"\x66\x66"),
  ])
  show(replied)
}

///|
/// Render the recorded WebSocket events a handler emitted.
fn show(events : Array[@moonasgi.Event]) -> Unit {
  for ev in events {
    let line = match ev {
      @spec.WebSocketAccept(subprotocol~, headers=_) =>
        "accept subprotocol=\{subprotocol.unwrap_or("-")}"
      @spec.WebSocketSendText(t) => "send text: \{t}"
      @spec.WebSocketSendBytes(b) => "send bytes: \{b.length()} byte(s)"
      @spec.WebSocketClose(code~, reason~) =>
        "close code=\{code} reason=\{reason}"
      _ => "other"
    }
    println("  " + line)
  }
}

///|
/// Join strings with commas — the offered subprotocol list.
fn join_csv(xs : Array[String]) -> String {
  let sb = StringBuilder()
  for i = 0; i < xs.length(); i = i + 1 {
    if i > 0 {
      sb.write_string(",")
    }
    sb.write_string(xs[i])
  }
  sb.to_string()
}
