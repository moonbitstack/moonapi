///|
/// The per-request context handed to a handler: the raw request plus the path
/// parameters extracted from the matched route (`:name` segments).
pub(all) struct Context {
  request : @moonasgi.Request
  params : Map[String, String]
}

///|
/// Look up a path parameter by name.
pub fn Context::param(self : Context, name : String) -> String? {
  self.params.get(name)
}
