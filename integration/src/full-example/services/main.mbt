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
  let value : Map[String, Json] = Map([("detail", Json(message))])
  Json(value)
}

///|
pub fn repeat_text(text : String, count : Int32) -> String {
  let output = StringBuilder()
  for _index = 0; _index < count; _index = _index + 1 {
    output.write_string(text)
  }
  output.to_string()
}
