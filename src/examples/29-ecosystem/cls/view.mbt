///|
/// `/tasks`: the collection. A `View` answers the methods of one path, so the
/// path's two verbs are two methods here and the path is registered once.
priv struct Collection {
  // A `View` method hands back a handler and nothing else, so the descriptor the
  // body is checked against is built at registration and carried in the value.
  endpoint : @moonapi.Endpoint
}

///|
impl @moonapi.View for Collection with fn get(self) {
  let _ = self
  Some(ctx => @shared.list(ctx))
}

///|
impl @moonapi.View for Collection with fn post(self) {
  Some(ctx => @shared.create(ctx, self.endpoint))
}

///|
/// `/tasks/{id}`: one task.
priv struct Item {}

///|
impl @moonapi.View for Item with fn get(_) {
  Some(ctx => @shared.one(ctx))
}

///|
impl @moonapi.View for Item with fn delete(_) {
  Some(ctx => @shared.remove(ctx))
}

///|
/// The application, built by registering two views. A method a view leaves out is
/// a `405` whose `Allow` names the ones it answers, which is why the two paths
/// are two views rather than one.
pub fn build() -> @moonapi.App {
  let app = @moonapi.App::new()
  @shared.configure(app)
  app.view(
    "/tasks",
    Collection::{ endpoint: @shared.create_endpoint(), },
    name="tasks",
    tags=["tasks"],
  )
  app.view("/tasks/{id:int}", Item::{ }, name="task", tags=["tasks"])
  app
}
