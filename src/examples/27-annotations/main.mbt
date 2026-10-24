///|
/// Handlers declared with `#app.get(...)` and the rest; `register(app)` and
/// `register_router(router)` come from `routes.g.mbt`, generated from them. An
/// extension method such as PURGE is a route like any other.
///
///     moon run src/examples/27-annotations
#coverage.skip
async fn main {
  let app = @moonapi.App::new()
  register(app)
  let account = @moonapi.Router::new()
  register_router(account)
  app.include_router(account, prefix="/account")
  let hit = (verb : String, path : String) => {
    let req : @moonasgi.Request = {
      http_method: verb,
      path,
      query_string: b"",
      headers: [],
      body: b"",
    }
    let r = app.handle(req)
    println("\{verb} \{path} -> \{r.status} \{@utf8.decode_lossy(r.body[:])}")
  }
  hit("GET", "/items/7")
  hit("POST", "/items")
  hit("DELETE", "/items/7")
  hit("PURGE", "/cache")
  hit("GET", "/account/me")
  hit("GET", "/cache")
}
