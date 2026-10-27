///|
/// Open a WebSocket to `path` on the app, send `messages`, then disconnect, and every event the
/// app sent. `denial` says whether the server offers ASGI's `websocket.http.response`.
async fn ws_session(
  app : App,
  path : String,
  messages? : Array[String],
  headers~ : Array[(String, String)] = [],
  denial~ : Bool = false,
) -> Array[@moonasgi.Event] {
  let extensions : @moonasgi.Extensions = {
    ..@moonasgi.Extensions::none(),
    websocket_http_response: denial,
  }
  let scope = @moonasgi.Scope::WebSocket(
    @moonasgi.WebSocketScope::new(path~, headers~, extensions~),
  )
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
  live.websocket("/feed/{room}", ws => {
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
  app.websocket("/room/{id}", ws => {
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

///|
/// An app with a bearer scheme and a WebSocket route that requires it, and the token it accepts.
fn guarded_ws(seen : Array[String]) -> (App, String) {
  let app = App::new()
  app.set_clock(() => 1000L)
  app.secure_oauth2(
    "OAuth2",
    @security.OAuth2PasswordBearer::new("/token", "s3cret"),
    scopes=[("live", "watch the feed")],
  )
  app.websocket(
    "/feed",
    ws => {
      seen.push("handler")
      ws.accept()
      ws.close()
    },
    security=[@security.SecurityRequirement::new("OAuth2", scopes=["live"])],
  )
  let tok = @security.create_access_token("alice", "s3cret", 1000L, scopes=[
    "live",
  ])
  (app, tok)
}

///|
async test "ws security: a refused handshake gets the HTTP answer where the server allows it" {
  let seen = []
  let (app, _) = guarded_ws(seen)
  let events = ws_session(app, "/feed", denial=true)
  assert_true(
    events
    is [
      WebSocketHttpResponseStart(status=401, ..),
      WebSocketHttpResponseBody(more_body=false, ..),
    ],
  )
  guard! events is [WebSocketHttpResponseStart(headers~, ..), ..]
  assert_true(headers.iter().any(h => h.0 == "www-authenticate"))
  assert_eq(seen, [])
}

///|
async test "ws security: without the denial extension a refusal closes with 1008" {
  let seen = []
  let (app, _) = guarded_ws(seen)
  assert_true(ws_session(app, "/feed") is [WebSocketClose(code=1008, ..)])
  assert_eq(seen, [])
}

///|
async test "ws security: a valid credential reaches the handler" {
  let seen = []
  let (app, tok) = guarded_ws(seen)
  let events = ws_session(app, "/feed", headers=[
    ("authorization", "Bearer " + tok),
  ])
  assert_true(events is [WebSocketAccept(..), WebSocketClose(code=1000, ..)])
  assert_eq(seen, ["handler"])
}

///|
async test "ws deps: resolved before the handler and torn down after it" {
  let log : Array[String] = []
  let c : @di.Container[Dep] = @di.Container::new()
  c.provide(
    "conn",
    () => {
      log.push("open")
      Greeting("db")
    },
    teardown=(_v, _e) => log.push("close"),
  )
  |> ignore
  let app = App::new()
  app.depends(c.erase())
  app.websocket(
    "/live",
    ws => {
      log.push("handler")
      ws.accept()
      ws.close()
    },
    dependencies=["conn"],
  )
  assert_true(
    ws_session(app, "/live") is [WebSocketAccept(..), WebSocketClose(..)],
  )
  assert_eq(log, ["open", "handler", "close"])
}

///|
async test "ws deps: an unprovidable key declines the handshake with a 500" {
  let called = []
  let app = App::new()
  let empty : @di.Container[Dep] = @di.Container::new()
  app.depends(empty.erase())
  app.websocket("/live", _ws => called.push(true), dependencies=["nope"])
  assert_true(
    ws_session(app, "/live", denial=true)
    is [
      WebSocketHttpResponseStart(status=500, ..),
      WebSocketHttpResponseBody(..),
    ],
  )
  assert_eq(called, [])
}

///|
async test "ws deps: an error the handler raises is not turned into a denial" {
  let app = App::new()
  app.websocket("/live", ws => {
    ws.accept()
    raise @exceptions.http_error(418, "no tea")
  })
  let raised = ws_session(app, "/live", denial=true) catch { _ => [] }
  assert_true(raised is [])
}

///|
async test "include_router: a router's security reaches its WebSocket routes" {
  let live = @route.Router::new()
  live.websocket("/feed", ws => {
    ws.accept()
    ws.close()
  })
  let app = App::new()
  app.secure_oauth2(
    "OAuth2",
    @security.OAuth2PasswordBearer::new("/token", "s3cret"),
    scopes=[],
  )
  app.include_router(live, prefix="/live", security=[
    @security.SecurityRequirement::new("OAuth2"),
  ])
  assert_true(ws_session(app, "/live/feed") is [WebSocketClose(code=1008, ..)])
}

///|
test "url_for resolves a named WebSocket route, mount prefix included" {
  let sub = App::new()
  sub.websocket("/room/{id:int}", _ws => (), name="room")
  let app = App::new()
  app.mount("/chat", sub)
  assert_eq(
    app.url_for("room", params=Map([("id", "7")])),
    Some("/chat/room/7"),
  )
  assert_eq(app.url_for("room", params=Map([("id", "x")])), None)
}
