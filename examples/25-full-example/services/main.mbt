///|
/// Shared infrastructure used by the application and its route packages.

///|
pub fn dependencies(log : Array[String]) -> @moonapi.Container[String] {
  let providers : @moonapi.Container[String] = @moonapi.Container::new()
  ignore(
    providers.provide("audit", () => "request audit", teardown=(value, _error) => {
      log.push("closed " + value)
    }),
  )
  providers
}

///|
pub fn detail(message : String) -> Json {
  let value : Map[String, Json] = Map([("detail", message.to_json())])
  value.to_json()
}

///|
pub fn repeat_text(text : String, count : Int) -> String {
  let output = StringBuilder()
  for _index = 0; _index < count; _index = _index + 1 {
    output.write_string(text)
  }
  output.to_string()
}

///|
pub fn request(
  verb : String,
  path : String,
  query : String,
  headers : Array[(String, String)],
  body : String,
) -> @moonasgi.Request {
  {
    http_method: verb,
    path,
    query_string: @utf8.encode(query),
    headers,
    body: @utf8.encode(body),
  }
}

///|
pub fn show(
  app : @moonapi.App,
  verb : String,
  path : String,
  query : String,
  headers : Array[(String, String)],
  body : String,
) -> Unit {
  let response = app.handle(request(verb, path, query, headers, body))
  println(
    verb +
    " " +
    path +
    " -> " +
    response.status.to_string() +
    " " +
    @utf8.decode_lossy(response.body[:]),
  )
}

///|
pub fn run_lifespan(app : @moonapi.App) -> Unit {
  let scope = @moonasgi.Scope::Lifespan(@moonasgi.LifespanScope::new())
  ignore(
    @moonasgi.run_lifespan(app.lifespan_handler(), scope, [
      @moonasgi.Event::LifespanStartup,
      @moonasgi.Event::LifespanShutdown,
    ]),
  )
}
