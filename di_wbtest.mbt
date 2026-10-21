///|
/// A Context wrapping a POST body, no params — test helper.
fn body_ctx(payload : String) -> @ctx.Context {
  {
    request: mkreq_full("POST", "/greet", body=@utf8.encode(payload)),
    params: Map([]),
  }
}

///|
test "typed body: valid payload deserialises into the struct" {
  let ctx = body_ctx("{\"name\":\"ada\"}")
  let r : Result[GreetReq, _] = ctx.body_validated(GreetReq::schema())
  match r {
    Ok(req) => assert_eq(req.name, "ada")
    Err(_) => assert_eq("expected Ok", "got Err")
  }
}

///|
test "typed body: missing required field -> located 422 errors" {
  let ctx = body_ctx("{}")
  let r : Result[GreetReq, _] = ctx.body_validated(GreetReq::schema())
  match r {
    Ok(_) => assert_eq("expected Err", "got Ok")
    Err(errs) => {
      assert_eq(errs.length(), 1)
      assert_eq(errs[0].kind, "missing")
      assert_eq(errs[0].loc, ["body", "name"])
    }
  }
}

///|
test "typed body: wrong field type -> located 422 before deserialisation" {
  let ctx = body_ctx("{\"name\":5}")
  let r : Result[GreetReq, _] = ctx.body_validated(GreetReq::schema())
  match r {
    Ok(_) => assert_eq("expected Err", "got Ok")
    Err(errs) => {
      assert_eq(errs.length(), 1)
      assert_eq(errs[0].kind, "string_type")
      assert_eq(errs[0].loc, ["body", "name"])
    }
  }
}

///|
test "typed body: empty body -> missing, invalid JSON -> json_invalid" {
  let empty : @ctx.Context = {
    request: mkreq_full("POST", "/greet"),
    params: Map([]),
  }
  match (empty.body_validated(GreetReq::schema()) : Result[GreetReq, _]) {
    Err(errs) => assert_eq(errs[0].kind, "missing")
    Ok(_) => assert_eq("expected Err", "got Ok")
  }
  let junk = body_ctx("{not json")
  match (junk.body_validated(GreetReq::schema()) : Result[GreetReq, _]) {
    Err(errs) => assert_eq(errs[0].kind, "json_invalid")
    Ok(_) => assert_eq("expected Err", "got Ok")
  }
}

///|
test "typed body: unchecked extractor is total, None on bad shape" {
  let ok = body_ctx("{\"name\":\"x\"}")
  assert_eq((ok.body() : GreetReq?).unwrap().name, "x")
  let bad = body_ctx("{\"name\":5}")
  assert_eq((bad.body() : GreetReq?) is None, true)
}

///|
test "DI: container provides a request-scoped value, None when unregistered" {
  let c : @di.Container[Dep] = @di.Container::new()
  c.provide("greeting", () => Greeting("Hi")) |> ignore
  let scope = c.open_scope()
  assert_eq(scope.get("greeting") == Some(Greeting("Hi")), true)
  assert_eq(scope.get("absent") is None, true)
  scope.close()
}

///|
test "DI: a dependency is built once per request scope (cached)" {
  let log : Array[String] = []
  let c : @di.Container[Dep] = @di.Container::new()
  c.provide("greeting", () => {
    log.push("built")
    Greeting("x")
  })
  |> ignore
  let scope = c.open_scope()
  let _ = scope.get("greeting")
  let _ = scope.get("greeting")
  scope.close()
  // Two resolutions, one factory call: the value was cached for the request.
  assert_eq(log.length(), 1)
}

///|
test "DI: a dependency resolves a sub-dependency through the scope, LIFO teardown" {
  let log : Array[String] = []
  let c : @di.Container[Dep] = @di.Container::new()
  c.provide(
    "prefix",
    () => {
      log.push("build prefix")
      Greeting("Hi")
    },
    teardown=(_v, _e) => log.push("td prefix"),
  )
  |> ignore
  c.provide_using(
    "full",
    scope => {
      log.push("build full")
      let p = match scope.get("prefix") {
        Some(Greeting(s)) => s
        _ => "?"
      }
      Greeting(p + ", there")
    },
    teardown=(_v, _e) => log.push("td full"),
  )
  |> ignore
  let scope = c.open_scope()
  // Resolving "full" pulls in "prefix" through the scope.
  assert_eq(scope.get("full") == Some(Greeting("Hi, there")), true)
  // "prefix" was built once during "full"; asking again returns the cache.
  assert_eq(scope.get("prefix") == Some(Greeting("Hi")), true)
  scope.close()
  // prefix built while full resolved (before full); teardown LIFO -> full, then prefix.
  assert_eq(log == ["build full", "build prefix", "td full", "td prefix"], true)
}

///|
test "DI: a circular sub-dependency breaks with None instead of looping" {
  let c : @di.Container[Dep] = @di.Container::new()
  c.provide_using("a", scope => {
    let _ = scope.get("b")
    Greeting("a")
  })
  |> ignore
  c.provide_using("b", scope => {
    let _ = scope.get("a")
    Greeting("b")
  })
  |> ignore
  let scope = c.open_scope()
  // get(a) -> builds b -> b asks for a (mid-build) -> None breaks the cycle,
  // so both still resolve without looping.
  assert_eq(scope.get("a") == Some(Greeting("a")), true)
  assert_eq(scope.get("b") == Some(Greeting("b")), true)
  scope.close()
}

///|
test "DI: dependency_overrides shadow the base provider, then restore" {
  let c : @di.Container[Dep] = @di.Container::new()
  c.provide("greeting", () => Greeting("Hello")) |> ignore
  let s1 = c.open_scope()
  assert_eq(s1.get("greeting") == Some(Greeting("Hello")), true)
  s1.close()
  c.override_("greeting", () => Greeting("Bonjour")) |> ignore
  let s2 = c.open_scope()
  assert_eq(s2.get("greeting") == Some(Greeting("Bonjour")), true)
  s2.close()
  c.clear_overrides()
  let s3 = c.open_scope()
  assert_eq(s3.get("greeting") == Some(Greeting("Hello")), true)
  s3.close()
}

///|
test "DI: yield-style teardown runs after the handler, LIFO" {
  let log : Array[String] = []
  let c : @di.Container[Dep] = @di.Container::new()
  c.provide(
    "a",
    () => {
      log.push("setup a")
      Greeting("a")
    },
    teardown=(_v, _e) => log.push("teardown a"),
  )
  |> ignore
  c.provide(
    "b",
    () => {
      log.push("setup b")
      Greeting("b")
    },
    teardown=(_v, _e) => log.push("teardown b"),
  )
  |> ignore
  let resp = c.run(scope => {
    let _ = scope.get("a")
    let _ = scope.get("b")
    @status.text(200, "ok")
  })
  assert_eq(resp.status, 200)
  // Setups in resolution order; teardowns strictly after, in reverse (LIFO).
  assert_eq(log == ["setup a", "setup b", "teardown b", "teardown a"], true)
}

///|
test "greet route: dependency + validated body end to end, with override" {
  let c : @di.Container[Dep] = @di.Container::new()
  c.provide("greeting", () => Greeting("Hello")) |> ignore
  let app = greet_app(c)
  let ok = app.handle(
    mkreq_full("POST", "/greet", body=@utf8.encode("{\"name\":\"ada\"}")),
  )
  assert_eq(ok.status, 200)
  assert_eq(json_str(resp_json(ok), "message"), "Hello, ada")
  // dependency_overrides swaps the injected value without touching the route.
  c.override_("greeting", () => Greeting("Bonjour")) |> ignore
  let ok2 = app.handle(
    mkreq_full("POST", "/greet", body=@utf8.encode("{\"name\":\"ada\"}")),
  )
  assert_eq(json_str(resp_json(ok2), "message"), "Bonjour, ada")
  // A malformed body is rejected off the same descriptor with a 422.
  let bad = app.handle(mkreq_full("POST", "/greet", body=@utf8.encode("{}")))
  assert_eq(bad.status, 422)
  assert_eq(json_str(detail0(bad), "type"), "missing")
}

///|
/// What a teardown saw: "commit" on a clean request, "rollback" on a failed one
/// — the distinction a FastAPI `yield` dependency draws by wrapping its `yield`
/// in a `try`.
fn outcome_word(failure : Error?) -> String {
  if failure is Some(_) {
    "rollback"
  } else {
    "commit"
  }
}

///|
test "DI: run hands the handler's error to the teardowns, then re-raises" {
  let log : Array[String] = []
  let c : @di.Container[Dep] = @di.Container::new()
  c.provide("tx", () => Greeting("tx"), teardown=(_v, e) => {
    log.push(outcome_word(e))
  })
  |> ignore
  let outcome : Result[@moonasgi.Response, Error] = Ok(
    c.run(scope => {
      let _ = scope.get("tx")
      raise @mid.http_error(500, "boom")
    }),
  ) catch {
    e => Err(e)
  }
  // The error is not swallowed on its way out...
  assert_eq(outcome is Err(_), true)
  // ...and the teardown ran, knowing the request failed.
  assert_eq(log == ["rollback"], true)
}

///|
test "route deps: a declared dependency is resolved before the handler and torn down after" {
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
  app.get(
    "/items",
    _ctx => {
      log.push("handler")
      @status.text(200, "items")
    },
    dependencies=["conn"],
  )
  assert_eq(app.handle(mkreq("GET", "/items")).status, 200)
  assert_eq(log == ["open", "handler", "close"], true)
}

///|
test "route deps: teardown runs when the handler raises, and sees the failure" {
  let log : Array[String] = []
  let c : @di.Container[Dep] = @di.Container::new()
  c.provide("tx", () => Greeting("tx"), teardown=(_v, e) => {
    log.push(outcome_word(e))
  })
  |> ignore
  let app = App::new()
  app.depends(c.erase())
  app.get("/boom", _ctx => raise @mid.http_error(418, "no tea"), dependencies=[
    "tx",
  ])
  app.get("/fine", _ctx => @status.text(200, "ok"), dependencies=["tx"])
  // The raised error still becomes its mapped response...
  assert_eq(app.handle(mkreq("GET", "/boom")).status, 418)
  assert_eq(app.handle(mkreq("GET", "/fine")).status, 200)
  // ...and the two requests tore down differently, which is the whole point of
  // handing the failure to the teardown.
  assert_eq(log == ["rollback", "commit"], true)
}

///|
test "route deps: dependencies are LIFO within one request, and per request" {
  let log : Array[String] = []
  let c : @di.Container[Dep] = @di.Container::new()
  c.provide("a", () => Greeting("a"), teardown=(_v, _e) => log.push("td a"))
  |> ignore
  c.provide("b", () => Greeting("b"), teardown=(_v, _e) => log.push("td b"))
  |> ignore
  let app = App::new()
  app.depends(c.erase())
  app.get("/x", _ctx => @status.text(200, "x"), dependencies=["a", "b"])
  let _ = app.handle(mkreq("GET", "/x"))
  let _ = app.handle(mkreq("GET", "/x"))
  // Each request opened its own scope: two full setup/teardown cycles, the
  // second not served from the first's cache.
  assert_eq(log == ["td b", "td a", "td b", "td a"], true)
}

///|
test "route deps: an unprovidable key is a 500 and still releases what was built" {
  let log : Array[String] = []
  let c : @di.Container[Dep] = @di.Container::new()
  c.provide("conn", () => Greeting("db"), teardown=(_v, _e) => log.push("close"))
  |> ignore
  let app = App::new()
  app.depends(c.erase())
  app.get(
    "/items",
    _ctx => {
      log.push("handler")
      @status.text(200, "items")
    },
    dependencies=["conn", "nope"],
  )
  assert_eq(app.handle(mkreq("GET", "/items")).status, 500)
  // The handler never ran, and the dependency built before the gap was released.
  assert_eq(log == ["close"], true)
}

///|
test "route deps: a route that declares one with no container at all is a 500" {
  let app = App::new()
  app.get("/items", _ctx => @status.text(200, "items"), dependencies=["conn"])
  assert_eq(app.handle(mkreq("GET", "/items")).status, 500)
  // A route declaring none is unaffected — no container, no scope, no error.
  app.get("/free", _ctx => @status.text(200, "free"))
  assert_eq(app.handle(mkreq("GET", "/free")).status, 200)
}

///|
test "route deps: a router's group dependencies reach every route it carries" {
  let log : Array[String] = []
  let c : @di.Container[Dep] = @di.Container::new()
  c.provide("audit", () => {
    log.push("audit")
    Greeting("audit")
  })
  |> ignore
  let app = App::new()
  app.depends(c.erase())
  let r = @route.Router::new()
  r.get("/one", _ctx => @status.text(200, "one"))
  r.get("/two", _ctx => @status.text(200, "two"), dependencies=["own"])
  app.include_router(r, prefix="/g", dependencies=["audit"])
  assert_eq(app.handle(mkreq("GET", "/g/one")).status, 200)
  // The route's own key is unprovided, but the group's ran first — a group-wide
  // dependency is not something a route can drop by adding one of its own.
  assert_eq(app.handle(mkreq("GET", "/g/two")).status, 500)
  assert_eq(log == ["audit", "audit"], true)
}
