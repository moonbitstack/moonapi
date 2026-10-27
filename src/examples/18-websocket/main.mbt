///|
/// A chat room: the server speaks first, then echoes each message until the client leaves.
async fn room(ws : @moonapi.WebSocket) -> Unit {
  ws.accept(subprotocol="chat")
  ws.send_text("welcome to room \{ws.param("room").unwrap_or("?")}")
  for ;; {
    match ws.receive() {
      WsText(t) => ws.send_text("echo: " + t)
      WsBinary(b) => ws.send_bytes(b)
    }
  }
}

///|
/// Request and reply in JSON: add up the numbers sent, answer, close.
async fn sum(ws : @moonapi.WebSocket) -> Unit {
  ws.accept()
  let total = match ws.receive_json() {
    Array(items) =>
      items.fold(init=0.0, (acc, j) => {
        match j {
          Number(n, ..) => acc + n
          _ => acc
        }
      })
    _ => 0.0
  }
  ws.send_json(Json::number(total))
  ws.close()
}

///|
/// WebSocket routes (← FastAPI's `@app.websocket`). A handler holds the live connection: it can
/// speak first, answer as messages arrive, and a client that leaves ends it quietly. `param` and
/// `offered_subprotocols` mirror the HTTP context. A test client drives both routes in-process
/// over the same ASGI path a server serves.
///
///     moon run src/examples/18-websocket --target native
#coverage.skip
async fn main {
  let app = @moonapi.App::new()
  app.websocket("/ws/{room}", room)
  app.websocket("/sum", sum)
  let client = @testing.Client::new(app.to_asgi())
  println("room /ws/233:")
  client.websocket(path="/ws/233", subprotocols=["chat", "superchat"], s => {
    println("  subprotocol: \{s.subprotocol.unwrap_or("-")}")
    println("  " + s.receive_text())
    s.send_text("hi")
    println("  " + s.receive_text())
    s.send_bytes(b"\x02\x33\x33")
    println("  bytes back: \{s.receive_bytes().length()}")
  })
  println("sum /sum:")
  client.websocket(path="/sum", s => {
    s.send_json([1, 2, 3.5])
    println("  total: \{s.receive_json().stringify()}")
  })
}
