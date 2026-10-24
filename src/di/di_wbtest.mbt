///|
/// The dependency value type of the greet app. A sum type wrapping every
/// dependency this app injects — the explicit, exhaustive stand-in for FastAPI
/// resolving heterogeneous `Depends` values dynamically.
enum Dep {
  Greeting(String)
} derive(Eq)

///|
pub extend Dep with Eq::{not_equal, equal}

///|
test "DI: container provides a request-scoped value, None when unregistered" {
  let c : Container[Dep] = Container::new()
  c.provide("greeting", () => Greeting("Hi")) |> ignore
  let scope = c.open_scope()
  assert_eq(scope.get("greeting") == Some(Greeting("Hi")), true)
  assert_eq(scope.get("absent") is None, true)
  scope.close()
}

///|
test "DI: a dependency is built once per request scope (cached)" {
  let log : Array[String] = []
  let c : Container[Dep] = Container::new()
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
  let c : Container[Dep] = Container::new()
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
  let c : Container[Dep] = Container::new()
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
  let c : Container[Dep] = Container::new()
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
  let c : Container[Dep] = Container::new()
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
