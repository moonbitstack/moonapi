///|
/// Several dependency types share one container through a sum type: the
/// exhaustive, type-safe stand-in for Python's dynamic `Any`.
enum Dep {
  Cfg(String)
  Conn(String)
  Repo(String)
}

///|
/// The payload a dependency carries, for display.
fn Dep::show(self : Dep) -> String {
  match self {
    Cfg(s) => s
    Conn(s) => s
    Repo(s) => s
  }
}

///|
/// The dependency-injection container — the explicit MoonBit equivalent of
/// FastAPI's `Depends`. `provide` registers a leaf; `provide_using` registers a
/// factory that resolves *sub-dependencies* through the request `Scope`; each is
/// built at most once per request (the per-request cache) and its `teardown`
/// runs LIFO when the scope closes. `Container::run` brackets a handler with a
/// fresh scope; `override_` / `clear_override` swap a dependency for a fake, the
/// way a test does.
///
///     moon run examples/09-dependency-injection
#coverage.skip
fn main raise {
  let opens : Array[Int32] = [0]
  let c : @moonapi.Container[Dep] = @moonapi.Container::new()
  c.provide("config", () => Cfg("prod-dsn")) |> ignore
  // A connection that resolves `config` through the scope, counts its opens, and
  // registers a teardown — FastAPI's `yield` dependency.
  c.provide_using(
    "conn",
    scope => {
      opens[0] = opens[0] + 1
      let dsn = match scope.get("config") {
        Some(Cfg(s)) => s
        _ => "?"
      }
      println("  [open]  conn -> \{dsn}")
      Conn(dsn)
    },
    teardown=(_v, _e) => println("  [close] conn"),
  )
  |> ignore
  // A repository that depends on the connection.
  c.provide_using("repo", scope => {
    match scope.get("conn") {
      Some(Conn(dsn)) => Repo("repo@" + dsn)
      _ => Repo("repo@?")
    }
  })
  |> ignore

  // One request: resolve `repo` (pulls conn, pulls config), then resolve `conn`
  // again — served from cache, so it opens exactly once; teardown fires on exit.
  println("request A:")
  let resp = c.run(scope => {
    let repo = scope.get("repo").unwrap()
    let _again = scope.get("conn").unwrap()
    @moonapi.text(200, repo.show())
  })
  println("  -> \{resp.status} \{@utf8.decode_lossy(resp.body[:])}")
  println("  conn opened \{opens[0]} time(s)")

  // Override the config with a fake, as a test would; the fake flows through the
  // sub-dependency chain into the repo.
  println("request B (config overridden):")
  c.override_("config", () => Cfg("test-dsn")) |> ignore
  let resp2 = c.run(scope => {
    @moonapi.text(200, scope.get("repo").unwrap().show())
  })
  println("  -> \{resp2.status} \{@utf8.decode_lossy(resp2.body[:])}")
  c.clear_override("config")

  // The explicit form `run` wraps: open a scope, resolve, close it by hand.
  println("request C (manual scope):")
  let scope = c.open_scope()
  let cfg = scope.get("config").unwrap()
  println("  resolved \{cfg.show()}")
  scope.close()

  // A key with no provider resolves to None.
  let scope2 = c.open_scope()
  println("unknown key resolved: \{scope2.get("missing") is Some(_)}")
  scope2.close()
  c.clear_overrides()
}
