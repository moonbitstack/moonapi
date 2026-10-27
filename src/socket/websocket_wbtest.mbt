///|
fn ws_scope() -> @moonasgi.Scope {
  WebSocket(@moonasgi.WebSocketScope::new(path="/ws", subprotocols=["chat"]))
}

///|
/// An ASGI application running `handler` on each connection.
fn served(handler : WsHandler) -> @moonasgi.AsgiApp {
  (scope, receive, send) => {
    guard scope is WebSocket(s) else { return }
    handler(WebSocket::new(s, receive, send))
  }
}

///|
/// Mirror each message back until the peer leaves.
async fn echo_ws(ws : WebSocket) -> Unit {
  ws.accept()
  for ;; {
    ws.send(ws.receive())
  }
}

///|
async test "ws: an echo handler mirrors text and binary, and ends when the peer leaves" {
  @testing.communicate(served(echo_ws), ws_scope(), c => {
    c.send(WebSocketConnect)
    assert_true(c.receive() is WebSocketAccept(subprotocol=None, ..))
    c.send(WebSocketReceive(text=Some("hi"), bytes=None))
    assert_true(c.receive() is WebSocketSendText("hi"))
    c.send(WebSocketReceive(text=None, bytes=Some(b"\x01\x02")))
    assert_true(c.receive() is WebSocketSendBytes(b"\x01\x02"))
    c.send(WebSocketDisconnect(code=1001, reason=None))
    c.wait() catch {
      Disconnected(code=1001, ..) => ()
      e => raise e
    }
  })
}

///|
async test "ws: accept takes the connect once and carries the subprotocol" {
  let handler : WsHandler = ws => {
    ws.accept(subprotocol="chat")
    ws.accept()
    ws.close(code=1001, reason="bye")
    ws.close()
  }
  @testing.communicate(served(handler), ws_scope(), c => {
    c.send(WebSocketConnect)
    assert_true(c.receive() is WebSocketAccept(subprotocol=Some("chat"), ..))
    assert_true(c.receive() is WebSocketClose(code=1001, reason="bye"))
    c.wait()
    assert_true(c.receive_nothing())
  })
}

///|
async test "ws: the server may speak first and push before reading" {
  let handler : WsHandler = ws => {
    ws.accept()
    ws.send_text("welcome")
    ws.send_json({ "n": 1 })
    let reply = ws.receive_json()
    ws.send_text("got \{reply.stringify()}")
  }
  @testing.communicate(served(handler), ws_scope(), c => {
    c.send(WebSocketConnect)
    ignore(c.receive())
    assert_true(c.receive() is WebSocketSendText("welcome"))
    assert_true(c.receive() is WebSocketSendText("{\"n\":1}"))
    c.send(WebSocketReceive(text=Some("[true]"), bytes=None))
    assert_true(c.receive() is WebSocketSendText("got [true]"))
  })
}

///|
async test "ws: receive_text and receive_bytes take either kind as UTF-8" {
  let seen : Array[String] = []
  let handler : WsHandler = ws => {
    ws.accept()
    seen.push(ws.receive_text())
    seen.push(ws.receive_bytes().length().to_string())
  }
  @testing.communicate(served(handler), ws_scope(), c => {
    c.send(WebSocketConnect)
    ignore(c.receive())
    c.send(WebSocketReceive(text=None, bytes=Some(b"ab")))
    c.send(WebSocketReceive(text=Some("xyz"), bytes=None))
    c.wait()
  })
  assert_eq(seen, ["ab", "3"])
}

///|
async test "ws: a close before accept declines the handshake" {
  let handler : WsHandler = ws => ws.close(code=1008, reason="policy")
  @testing.communicate(served(handler), ws_scope(), c => {
    c.send(WebSocketConnect)
    assert_true(c.receive() is WebSocketClose(code=1008, reason="policy"))
  })
}

///|
async test "ws: a disconnect before accept surfaces as Disconnected" {
  let caught : Array[Int32] = []
  let handler : WsHandler = ws => {
    ws.accept() catch {
      Disconnected(code~, ..) => caught.push(code)
      e => raise e
    }
  }
  @testing.communicate(served(handler), ws_scope(), c => {
    c.send(WebSocketDisconnect(code=1006, reason=None))
    c.wait()
  })
  assert_eq(caught, [1006])
}

///|
test "ws: the scope's headers and offered subprotocols are readable" {
  let s = @moonasgi.WebSocketScope::new(
    path="/ws",
    headers=[("origin", "https://a.example")],
    subprotocols=["v2", "v1"],
  )
  let ws = WebSocket::new(s, () => WebSocketConnect, _ => (), params={
    "room": "7",
  })
  assert_eq(ws.header("origin"), Some("https://a.example"))
  assert_eq(ws.offered_subprotocols(), ["v2", "v1"])
  assert_eq(ws.param("room"), Some("7"))
}

///|
async test "ws: deny sends the response where the server allows it" {
  let handler : WsHandler = ws => {
    ws.deny(
      @moonasgi.Response::new(401, [("www-authenticate", "Bearer")], b"no"),
    )
    ws.close()
  }
  let scope = @moonasgi.Scope::WebSocket(
    @moonasgi.WebSocketScope::new(path="/ws", extensions={
      ..@moonasgi.Extensions::none(),
      websocket_http_response: true,
    }),
  )
  @testing.communicate(served(handler), scope, c => {
    assert_true(c.receive() is WebSocketHttpResponseStart(status=401, ..))
    assert_true(
      c.receive() is WebSocketHttpResponseBody(body=b"no", more_body=false),
    )
    c.wait()
    assert_true(c.receive_nothing())
  })
}

///|
async test "ws: deny closes with 1008 without the extension, and after accept" {
  let refused : WsHandler = ws => ws.deny(@moonasgi.Response::new(403, [], b""))
  @testing.communicate(served(refused), ws_scope(), c => {
    assert_true(c.receive() is WebSocketClose(code=1008, ..))
    c.wait()
  })
  let late : WsHandler = ws => {
    ws.accept()
    ws.deny(@moonasgi.Response::new(403, [], b""))
  }
  @testing.communicate(served(late), ws_scope(), c => {
    c.send(WebSocketConnect)
    assert_true(c.receive() is WebSocketAccept(..))
    assert_true(c.receive() is WebSocketClose(code=1008, ..))
    c.wait()
  })
}
