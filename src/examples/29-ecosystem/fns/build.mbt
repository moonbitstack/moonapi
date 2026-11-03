///|
/// The application, built by calling the registration methods. This is the shape
/// the annotation generator emits, written out: one call per route, the handler
/// beside it, and the route's documented half in arguments.
pub fn build() -> @moonapi.App {
  let app = @moonapi.App::new()
  @shared.configure(app)
  // Built once: walking the description per request would add up.
  let endpoint = @shared.create_endpoint()
  app.get(
    "/tasks",
    ctx => @shared.list(ctx),
    name="list_tasks",
    summary="Every task",
    tags=["tasks"],
  )
  app.post(
    "/tasks",
    ctx => @shared.create(ctx, endpoint),
    name="create_task",
    summary="Add a task",
    status_code=201,
    tags=["tasks"],
    endpoint~,
    // The handler validates with the same descriptor; checking twice would be a
    // second place for the rule to be applied.
    validate=false,
  )
  app.get(
    "/tasks/{id:int}",
    ctx => @shared.one(ctx),
    name="get_task",
    summary="One task",
    tags=["tasks"],
  )
  app.delete(
    "/tasks/{id:int}",
    ctx => @shared.remove(ctx),
    name="delete_task",
    summary="Remove a task",
    tags=["tasks"],
  )
  app
}
