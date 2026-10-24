///|
#app.get("/items/:id", summary="Read an item", tags="items")
fn read_item(ctx : @moonapi.Context) -> @moonasgi.Response {
  @moonapi.text(200, "item " + ctx.param("id").unwrap_or(""))
}

///|
#app.post("/items", status_code="201", tags="items")
fn create_item(_ctx : @moonapi.Context) -> @moonasgi.Response {
  @moonapi.text(201, "created")
}

///|
#app.delete("/items/:id", tags="items")
fn delete_item(_ctx : @moonapi.Context) -> @moonasgi.Response {
  @moonapi.text(200, "deleted")
}

///|
#app.route("PURGE", "/cache", summary="Drop the cache")
fn purge(_ctx : @moonapi.Context) -> @moonasgi.Response {
  @moonapi.text(200, "purged")
}

///|
#router.get("/me")
fn me(_ctx : @moonapi.Context) -> @moonasgi.Response {
  @moonapi.text(200, "me")
}
