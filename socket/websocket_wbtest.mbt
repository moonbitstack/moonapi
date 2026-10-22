///|
/// An echo handler: accept, mirror each frame back, close on disconnect.
fn echo_ws(ws : WebSocket) -> Unit {
  ws.accept()
  for ;; {
    match ws.receive() {
      Some(WsText(t)) => ws.send_text(t)
      Some(WsBinary(b)) => ws.send_bytes(b)
      None => break
    }
  }
  ws.close()
}

///|
test "ws: echo route mirrors text and binary frames" {
  let events = drive_websocket(echo_ws, [WsText("hi"), WsBinary(b"\x01\x02")])
  assert_eq(events.length(), 4)
  assert_eq(
    events[0] == @moonasgi.Event::WebSocketAccept(subprotocol=None, headers=[]),
    true,
  )
  assert_eq(events[1] == @moonasgi.Event::WebSocketSendText("hi"), true)
  assert_eq(events[2] == @moonasgi.Event::WebSocketSendBytes(b"\x01\x02"), true)
  assert_eq(
    events[3] == @moonasgi.Event::WebSocketClose(code=1000, reason=""),
    true,
  )
}

///|
test "ws: accept is idempotent and records the chosen subprotocol" {
  let handler : WsHandler = ws => {
    ws.accept(subprotocol="chat")
    ws.accept()
    ws.close(code=1001, reason="bye")
  }
  let events = drive_websocket(handler, [])
  assert_eq(events.length(), 2)
  assert_eq(
    events[0] ==
    @moonasgi.Event::WebSocketAccept(subprotocol=Some("chat"), headers=[]),
    true,
  )
  assert_eq(
    events[1] == @moonasgi.Event::WebSocketClose(code=1001, reason="bye"),
    true,
  )
}

///|
test "ws: receive_text and receive_bytes discriminate frame kinds" {
  let seen : Array[String] = []
  let handler : WsHandler = ws => {
    ws.accept()
    // first frame is text, second is binary.
    match ws.receive_text() {
      Some(t) => seen.push("text:" + t)
      None => seen.push("not-text")
    }
    match ws.receive_bytes() {
      Some(b) => seen.push("bytes:" + b.length().to_string())
      None => seen.push("not-bytes")
    }
  }
  let _ = drive_websocket(handler, [WsText("a"), WsBinary(b"\xaa\xbb\xcc")])
  assert_eq(seen[0], "text:a")
  assert_eq(seen[1], "bytes:3")
}
