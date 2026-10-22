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
/// The dependency value type of the greet app. A sum type wrapping every
/// dependency this app injects — the explicit, exhaustive stand-in for FastAPI
/// resolving heterogeneous `Depends` values dynamically.
enum Dep {
  Greeting(String)
} derive(Eq)

///|
pub extend Dep with Eq::{not_equal, equal}

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
      raise http_error(500, "boom")
    }),
  ) catch {
    e => Err(e)
  }
  // The error is not swallowed on its way out...
  assert_eq(outcome is Err(_), true)
  // ...and the teardown ran, knowing the request failed.
  assert_eq(log == ["rollback"], true)
}
