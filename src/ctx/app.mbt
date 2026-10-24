///|
/// The per-request context handed to a handler: the request with its body read, the path
/// parameters the matched route extracted (`:name` segments), the ASGI scope it arrived on
/// (`root_path`, the peer, the lifespan `state`, the extensions), and the request's background
/// tasks.
pub(all) struct Context {
  request : @moonasgi.Request
  params : Map[String, String]
  scope : @moonasgi.HttpScope
  background : BackgroundTasks
}

///|
/// A context for `request`. The scope defaults to the one a server would build for the request
/// alone, which is what a test or a hand-built context needs.
pub fn Context::new(
  request : @moonasgi.Request,
  params~ : Map[String, String] = {},
  scope? : @moonasgi.HttpScope,
  background~ : BackgroundTasks = BackgroundTasks::new(),
) -> Context {
  let scope = scope.unwrap_or_else(() => {
    @moonasgi.HttpScope::new(
      http_method=request.http_method,
      path=request.path,
      query_string=request.query_string,
      headers=request.headers,
    )
  })
  { request, params, scope, background, }
}

///|
/// Look up a path parameter by name.
pub fn Context::param(self : Context, name : String) -> String? {
  self.params.get(name)
}

///|
/// The lifespan state: a shallow copy of what the startup hooks stored, so a handler reads the
/// shared resources and anything it adds stays with this request.
pub fn Context::state(self : Context) -> Map[String, Json] {
  self.scope.state
}
