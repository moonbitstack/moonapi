// What the three ways of registering the routes share: what the API says about
// itself, the layers every request passes, the credential a write needs, and the
// page an unhandled error becomes. Written once, so the three registrations
// differ in exactly one thing.

///|
/// The key a write has to present.
pub let api_key : String = "s3cret"

///|
/// Put the shared half on `app`: the document's title and description, CORS and
/// gzip around the router, an API key in a header for the routes that declare it,
/// and an error page for anything the handlers did not catch.
pub fn configure(app : @moonapi.App) -> Unit {
  app.describe(
    title="Tasks",
    api_version="1.0.0",
    description="One description of a task, projected into a request body, a document and a table.",
  )
  app.layer(
    @mid.Cors::new(
      origins=["http://localhost:8080"],
      methods=["GET", "POST", "DELETE"],
      headers=["content-type", "x-api-key"],
    ),
  )
  app.layer(@mid.Gzip::new(minimum=100))
  app.secure_api_key(
    "key",
    @moonapi.ApiKey::header("X-API-Key", key => key == api_key),
  )
  // The key is checked here rather than on each route, because the three ways of
  // registering a route do not all offer a place to name a requirement: an
  // annotation spells strings and booleans, a `View` method carries a handler and
  // nothing else. One guard, one rule — a request that changes something presents
  // the key; reading does not.
  app.middleware((req, call_next) => {
    if req.http_method == "GET" ||
      req.http_method == "HEAD" ||
      req.http_method == "OPTIONS" {
      return call_next(req)
    }
    let mut presented : String? = None
    for header in req.headers {
      if header.0.to_lower() == "x-api-key" {
        presented = Some(header.1)
      }
    }
    match presented {
      Some(value) if value == api_key => call_next(req)
      _ =>
        @moonasgi.Response::new(
          401,
          [("content-type", "application/json")],
          b"{\"detail\":\"missing or wrong X-API-Key\"}",
        )
    }
  })
  // An error nobody caught is a 500 with a JSON body like every other refusal,
  // rather than whatever the server makes of an exception.
  app.add_status_handler(500, _ctx => {
    @moonapi.json(500, { "detail": "the task store failed" })
  })
}

///|
/// The security requirement a write carries.
pub fn write_access() -> Array[@moonapi.SecurityRequirement] {
  [@moonapi.SecurityRequirement::new("key")]
}
