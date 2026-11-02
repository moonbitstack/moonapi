///|
async fn hit(
  app : @moonapi.App,
  verb : String,
  path : String,
  body~ : String = "",
) -> String {
  let (path, query) = match path.find("?") {
    Some(at) => (path[:at].to_owned(), path[at + 1:].to_owned())
    None => (path, "")
  }
  let r = app.handle({
    http_method: verb,
    path,
    query_string: @utf8.encode(query),
    headers: [("content-type", "application/json")],
    body: @utf8.encode(body),
  })
  "\{r.status} \{@utf8.decode_lossy(r.body[:])}"
}

///|
async fn run(app : @moonapi.App) -> Array[String] {
  [
    "GET / -> " + hit(app, "GET", "/"),
    "GET /users/42 -> " + hit(app, "GET", "/users/42"),
    "POST /users -> " + hit(app, "POST", "/users"),
    "GET /missing -> " + hit(app, "GET", "/missing"),
    "DELETE / -> " + hit(app, "DELETE", "/"),
    "GET /items/233 -> " + hit(app, "GET", "/items/233"),
    "POST /items -> " + hit(app, "POST", "/items"),
    "PUT /items/233 -> " + hit(app, "PUT", "/items/233"),
    "PATCH /items/233 -> " + hit(app, "PATCH", "/items/233"),
    "DELETE /items/233 -> " + hit(app, "DELETE", "/items/233"),
    "HEAD /items -> " + hit(app, "HEAD", "/items"),
    "OPTIONS /items -> " + hit(app, "OPTIONS", "/items"),
    "GET /items -> " + hit(app, "GET", "/items"),
    "GET /search?q=cat&limit=5 -> " + hit(app, "GET", "/search?q=cat&limit=5"),
    "POST /login -> " +
    hit(app, "POST", "/login", body="{\"user\":\"heke\",\"pass\":\"s3cret\"}"),
    "POST /greet ok -> " +
    hit(app, "POST", "/greet", body="{\"name\":\"lfanke\"}"),
    "POST /greet 233 -> " + hit(app, "POST", "/greet", body="{\"name\":233}"),
    "POST /greet none -> " + hit(app, "POST", "/greet"),
    "GET /boom -> " + hit(app, "GET", "/boom"),
  ]
}

///|
async fn main {
  let ann = @moonapi.App::new()
  @ann.register(ann)
  let styles = [("ann", ann), ("fns", @fns.app()), ("cls", @cls.app())]
  let results = []
  for style in styles {
    results.push((style.0, run(style.1)))
  }
  for line in results[0].1 {
    println(line)
  }
  for r in results[1:] {
    if r.1 != results[0].1 {
      println("DIFFERS: " + r.0)
      for i, line in r.1 {
        if line != results[0].1[i] {
          println("  " + line)
        }
      }
    }
  }
  let annapi = @moonapi.App::new()
  @annapi.register(annapi)
  let docs = [
    annapi.openapi_json(version=OpenApi31),
    @fns.openapi_app().openapi_json(version=OpenApi31),
    @cls.openapi_app().openapi_json(version=OpenApi31),
  ]
  println("OPENAPI " + docs[0])
  println("openapi same: \{docs[0] == docs[1]} \{docs[0] == docs[2]}")
}
