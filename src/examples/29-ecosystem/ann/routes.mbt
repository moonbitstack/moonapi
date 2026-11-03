// The routes as annotations. The generated `routes.g.mbt` is the `register(app)`
// below written out — the calls the two other packages write by hand.
//
// An annotation spells strings, booleans and lists of strings, so what it cannot
// say stays with the handler: the descriptor the body is checked against is built
// in this package and used there.

///|
/// The descriptor, built once from the shared description.
let create_endpoint : @moonapi.Endpoint = @shared.create_endpoint()

///|
#app.get("/tasks", summary="Every task", tags="tasks", name="list_tasks")
fn list_tasks(ctx : @moonapi.Context) -> @moonasgi.Response raise {
  @shared.list(ctx)
}

///|
#app.post("/tasks", summary="Add a task", tags="tasks", name="create_task", status_code="201")
fn create_task(ctx : @moonapi.Context) -> @moonasgi.Response raise {
  @shared.create(ctx, create_endpoint)
}

///|
#app.get("/tasks/{id:int}", summary="One task", tags="tasks", name="get_task")
fn get_task(ctx : @moonapi.Context) -> @moonasgi.Response raise {
  @shared.one(ctx)
}

///|
#app.delete("/tasks/{id:int}", summary="Remove a task", tags="tasks", name="delete_task")
fn delete_task(ctx : @moonapi.Context) -> @moonasgi.Response raise {
  @shared.remove(ctx)
}
