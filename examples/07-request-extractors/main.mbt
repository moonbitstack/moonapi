///|
/// The un-typed request extractors and parameter validation across every
/// `ParamLoc`. `Context::query` / `cookie` / `json_field` / `body_json` pull
/// values straight off the request, and an `Endpoint` whose `Param`s sit in the
/// path, query, header, and cookie validates all four at once through
/// `Endpoint::validate` — a `422` naming each violated location. The tail builds
/// `ValidationError`s by hand to show the FastAPI `{"detail":[...]}` wire shape.
///
///     moon run examples/07-request-extractors
#coverage.skip
fn main {
  let app = @moonapi.App::new()
  let search = @moonapi.Endpoint::new(params=[
    @moonapi.Param::new("cat", @moonapi.InPath),
    @moonapi.Param::new("limit", @moonapi.InQuery, schema=@moonapi.SInt),
    @moonapi.Param::new("x-trace", @moonapi.InHeader),
    @moonapi.Param::new("session", @moonapi.InCookie),
  ])
  app.get(
    "/search/:cat",
    ctx => {
      let errs = search.validate(ctx)
      if errs.length() > 0 {
        @moonapi.unprocessable(errs)
      } else {
        let cat = ctx.param("cat").unwrap()
        let limit = ctx.query("limit").unwrap()
        let trace = ctx.request.header("x-trace").unwrap_or("-")
        let sess = ctx.cookie("session").unwrap_or("-")
        @moonapi.text(
          200,
          "cat=\{cat} limit=\{limit} trace=\{trace} session=\{sess}",
        )
      }
    },
    endpoint=search,
  )
  // A JSON body picked apart field by field, with no typed struct.
  app.post("/inspect", ctx => {
    match ctx.body_json() {
      Some(_) => {
        let name = match ctx.json_field("name") {
          Some(String(s)) => s
          _ => "?"
        }
        @moonapi.text(200, "name=\{name}")
      }
      None => @moonapi.text(400, "no JSON body")
    }
  })
  let get = (path : String, headers : Array[(String, String)]) => {
    let req : @moonasgi.Request = {
      http_method: "GET",
      path,
      query_string: b"",
      headers,
      body: b"",
    }
    let r = app.handle(req)
    println("GET \{path} -> \{r.status} \{@utf8.decode_lossy(r.body[:])}")
  }
  // The query string rides on `query_string`, not the path.
  let get_q = (path : String, qs : Bytes) => {
    let req : @moonasgi.Request = {
      http_method: "GET",
      path,
      query_string: qs,
      headers: [("x-trace", "heke1228"), ("cookie", "session=qwq; theme=dark")],
      body: b"",
    }
    let r = app.handle(req)
    println(
      "GET \{path}?\{@utf8.decode_lossy(qs[:])} -> \{r.status} \{@utf8.decode_lossy(r.body[:])}",
    )
  }
  // All four locations present and well-typed.
  get_q("/search/books", b"limit=23")
  // limit is not an integer, and the required header/cookie are absent.
  get("/search/books", [])
  // A JSON object body read without a descriptor.
  let post = (body : String) => {
    let req : @moonasgi.Request = {
      http_method: "POST",
      path: "/inspect",
      query_string: b"",
      headers: [("content-type", "application/json")],
      body: @utf8.encode(body),
    }
    let r = app.handle(req)
    println(
      "POST /inspect \{body} -> \{r.status} \{@utf8.decode_lossy(r.body[:])}",
    )
  }
  post("{\"name\":\"lfanke\",\"role\":\"admin\"}")
  post("")
  // The raw error builders and the body they render into.
  let errs = [
    @moonapi.ValidationError::missing(["query", "limit"]),
    @moonapi.ValidationError::type_error(
      ["body", "age"],
      "int_parsing",
      "Input should be a valid integer",
    ),
  ]
  println(
    "hand-built detail: \{@moonapi.validation_error_body(errs).stringify()}",
  )
}
