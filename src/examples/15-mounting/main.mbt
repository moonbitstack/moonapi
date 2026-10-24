///|
/// Sub-application mounting — composing routers. `App::mount(prefix, sub)` routes
/// a request under `prefix` through the sub-app with the prefix stripped, and the
/// sub-app's routes fold into the parent's merged OpenAPI document under that
/// prefix. Mounts nest: the API sub-app itself mounts an admin sub-app. The
/// composed app converts to a single `AsgiApp` with `App::to_asgi`, the value a
/// server (mooncat) runs.
///
///     moon run src/examples/15-mounting
#coverage.skip
async fn main {
  // A nested sub-app, mounted inside the API sub-app.
  let admin = @moonapi.App::new()
  admin.get(
    "/stats",
    _ctx => @moonapi.text(200, "admin stats"),
    summary="stats",
  )

  // The API sub-app.
  let api = @moonapi.App::new()
  api.get(
    "/items",
    _ctx => @moonapi.text(200, "the items"),
    summary="list items",
  )
  api.get(
    "/items/:id",
    ctx => @moonapi.text(200, "item " + ctx.param("id").unwrap()),
    summary="get item",
  )
  api.mount("/admin", admin)

  // The root app mounts the API under a versioned prefix.
  let app = @moonapi.App::new()
  app.get("/", _ctx => @moonapi.text(200, "root"))
  app.mount("/api/v1", api)
  let hit = (path : String) => {
    let req : @moonasgi.Request = {
      http_method: "GET",
      path,
      query_string: b"",
      headers: [],
      body: b"",
    }
    let r = app.handle(req)
    println("GET \{path} -> \{r.status} \{@utf8.decode_lossy(r.body[:])}")
  }
  hit("/")
  hit("/api/v1/items")
  hit("/api/v1/items/233") // prefix stripped, sub-app extracts :id
  hit("/api/v1/admin/stats") // nested mount, two prefixes deep
  hit("/api/v1/missing") // under the mount but no route -> 404
  hit("/elsewhere") // outside every mount -> 404

  // The whole composition is one AsgiApp a server runs.
  let _asgi = app.to_asgi()
  println("to_asgi() built the AsgiApp mooncat serves")
  println("--- merged OpenAPI 3.1.0 (sub-app paths under their prefixes) ---")
  println(app.openapi_json(version=OpenApi31))
}
