///|
/// The request method a route binds to: the nine standard ones and any other
/// token, from moonhttp.
pub using @method {type Method}

///|
/// A route handler (← a FastAPI path operation): the request context in, a response out. It runs
/// async, so it can await a database or another service; a plain closure is one too, and a named
/// function that is not async is registered as `ctx => f(ctx)`. It may `raise` an
/// `HttpException` (or any error) instead of returning — the app maps it to a response through
/// the registered exception handlers.
pub type ApiHandler = async (@ctx.Context) -> @moonasgi.Response

///|
/// A streaming route's handler (← a FastAPI path operation returning a `StreamingResponse`): the
/// response it returns writes its body while it is sent.
pub type StreamHandler = async (@ctx.Context) -> @status.Stream

///|
/// What a route produced: a response with its body in hand, or one that writes its body as it
/// goes.
pub(all) enum Reply {
  Buffered(@moonasgi.Response)
  Streamed(@status.Stream)
}

///|
/// One registered route, the record an app keeps for each operation — what
/// FastAPI calls `APIRoute`. Public so a program can list and inspect an app's
/// routes; building one by hand is possible but the `App` methods are the way.
///
/// `security` is the per-operation requirements (emitted as OpenAPI `security` and enforced
/// before the handler when their scheme has an enforcer).
pub(all) struct Route {
  verb : Method
  path : String
  // `path` read once at registration, so a request is matched without reading
  // the template again.
  pattern : Pattern
  run : async (@ctx.Context) -> Reply
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
