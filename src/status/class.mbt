// What a response body is, as a name a route can give the document. The media
// type of each one is the very string the helper beside it writes, so the
// document and the wire cannot drift apart.

///|
/// The kind of body a route's success response carries, named after the helper
/// that writes one: `Json` is `json`, `Text` is `text`, `Html` is `html`,
/// `EventStream` is `sse`, `Bytes` is `file_response`. A route names one in its
/// `response_class`, and the OpenAPI document keys the success response's
/// content under that media type, so a client generating code from the document
/// knows what to parse.
///
/// Documentation only. The handler still builds the response it returns, so a
/// route that names `Html` and answers JSON is a contradiction this cannot
/// catch — the class says what the route promises, not what it enforces.
pub(all) enum ResponseClass {
  Json
  Text
  Html
  Xml
  EventStream
  Bytes
}

///|
/// The `Content-Type` a response of this class carries, exactly as the helper
/// in this package writes it: the text kinds with the `charset` a browser would
/// otherwise guess.
///
/// ```mbt check
/// test {
///   let kinds : Array[@status.ResponseClass] = [Json, Text, Html]
///   assert_eq(
///     kinds.map(k => k.media_type()).join(", "),
///     "application/json, text/plain; charset=utf-8, text/html; charset=utf-8",
///   )
/// }
/// ```
pub fn ResponseClass::media_type(self : ResponseClass) -> String {
  match self {
    Json => "application/json"
    Text => "text/plain; charset=utf-8"
    Html => "text/html; charset=utf-8"
    Xml => "application/xml"
    EventStream => "text/event-stream"
    Bytes => "application/octet-stream"
  }
}
