// Errors a handler raises to answer with a status, and the handlers that turn a raised error into
// a response (← FastAPI's `HTTPException` and `@app.exception_handler`).

///|
/// An HTTP error a handler can `raise` to short-circuit with a status and body
/// (← FastAPI's `HTTPException`). `detail` is any JSON (a string is the common
/// case); `headers` are added to the response (e.g. a `WWW-Authenticate`
/// challenge). Caught by the app and mapped to a response.
pub(all) suberror HttpException {
  HttpException(
    status~ : Int32,
    detail~ : Json,
    headers~ : Array[(String, String)]
  )
}

///|
/// Build an `HttpException` with a string `detail` — the common case — and
/// optional extra `headers`. `raise http_error(404, "Item not found")` reads
/// like FastAPI's `raise HTTPException(404, "Item not found")`.
pub fn http_error(
  status : Int32,
  detail : String,
  headers~ : Array[(String, String)] = [],
) -> HttpException {
  HttpException(status~, detail=Json(detail), headers~)
}

///|
/// An exception handler: given the request context and the raised error, return
/// `Some(response)` to handle it or `None` to defer to the next handler. The
/// explicit MoonBit form of FastAPI's `@app.exception_handler(ExcType)` — the
/// `None` case stands in for "this handler isn't registered for that type".
pub type ExceptionHandler = (@ctx.Context, Error) -> @moonasgi.Response?
