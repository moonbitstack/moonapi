///|
/// HTTP methods a moonapi route can bind to.
pub(all) enum Method {
  Get
  Post
  Put
  Patch
  Delete
  Head
  Options
} derive(Eq)

///|
/// A moonapi route handler: request context in, response out. It may `raise` an
/// `HttpException` (or any error) instead of returning — the app catches it and
/// maps it to a response through the registered exception handlers, so handlers
/// read like FastAPI's `raise HTTPException(...)` rather than threading a
/// `Result` back by hand. A plain non-raising closure is still a valid handler.
pub type ApiHandler = (@ctx.Context) -> @moonasgi.Response raise

///|
/// A background-aware handler: it additionally receives the request's
/// `BackgroundTasks` queue, so it can schedule work to run after its response is
/// sent (← declaring a `BackgroundTasks` parameter in FastAPI).
pub type BackgroundHandler = (@ctx.Context, @ctx.BackgroundTasks) -> @moonasgi.Response raise

///|
/// A streaming route's handler: request context in, a chunked response out (←
/// returning a `StreamingResponse` from a FastAPI path operation). Every chunk
/// becomes one body event on the wire, so a client reads the first long before
/// the last one exists — the point of streaming, and what a single buffered
/// `Response` cannot express.
pub type StreamHandler = (@ctx.Context) -> @moonasgi.StreamingResponse raise

///|
/// What a route produced. Two kinds because moonasgi types a buffered response
/// and a chunked one differently, and the difference has to survive as far as
/// `to_asgi`, which is the only place that can put chunks on the wire.
pub(all) enum Reply {
  Buffered(@moonasgi.Response)
  Streamed(@moonasgi.StreamingResponse)
}

///|
/// One registered route, the record an app keeps for each operation — what
/// FastAPI calls `APIRoute`. Public so a program can list and inspect an app's
/// routes; building one by hand is possible but the `App` methods are the way.
///
/// A route stores one background-aware handler; a plain `ApiHandler` is wrapped
/// to ignore the queue. `security` is the per-operation requirements (emitted as
/// OpenAPI `security` and enforced before the handler when their scheme has an
/// enforcer).
pub(all) struct Route {
  verb : Method
  path : String
  run : (@ctx.Context, @ctx.BackgroundTasks) -> Reply raise
  summary : String
  description : String
  tags : Array[String]
  deprecated : Bool
  operation_id : String
  // The status the success response is documented under. Documentation only: the
  // handler builds its own response, and rewriting the status it chose would make
  // the app disagree with itself rather than with the spec.
  status_code : Int32?
  // Documented alongside whatever the endpoint descriptor produced, and written
  // after it, so the status a route names here is the one that stands.
  responses : Array[@endpoint.ResponseSpec]
  // The handle `App::url_for` looks the route up by. Empty means unnamed, and an
  // unnamed route is not addressable.
  name : String
  // Merged into the operation object last, so it can override anything moonapi
  // generated (← FastAPI's `openapi_extra`).
  openapi_extra : Json?
  endpoint : @endpoint.Endpoint?
  security : Array[@security.SecurityRequirement]
  // Provider keys resolved through the app's container before the handler runs,
  // and torn down after it (← FastAPI's `dependencies=[Depends(...)]`, whose
  // values the handler never sees).
  dependencies : Array[String]
  // FastAPI's `include_in_schema`: a route that serves the documentation itself has
  // no business appearing in the document it serves.
  include_in_schema : Bool
  // Whether the declared `endpoint` is checked before the handler runs. On by
  // default: a route that advertises constraints in its documentation and does not
  // apply them is worse than one that declares nothing.
  validate : Bool
}

///|
/// Split a path into its non-empty segments.
pub fn segments(path : String) -> Array[String] {
  let out : Array[String] = []
  let n = path.length()
  let mut start = 0
  for i = 0; i <= n; i = i + 1 {
    if i == n || path[i] == '/' {
      if i > start {
        out.push(path[start:i].to_owned())
      }
      start = i + 1
    }
  }
  out
}

///|
pub extend Method with Eq::{not_equal, equal}
