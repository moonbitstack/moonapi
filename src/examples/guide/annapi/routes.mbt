// guide:openapi

///|
#app.get("/ping", summary="Health check", tags="misc")
fn ping(_ctx : @moonapi.Context) -> @moonasgi.Response {
  @moonapi.text(200, "pong")
}

///|
#app.post("/echo", summary="Echo", tags="misc")
fn echo(_ctx : @moonapi.Context) -> @moonasgi.Response {
  @moonapi.json(200, { "ok": true })
}
// end
