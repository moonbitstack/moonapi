///|
/// A request as the test driver sends it.
fn request(
  http_method : String,
  path : String,
  body : String,
  key : Bool,
) -> @moonasgi.Request {
  let headers : Array[(String, String)] = [("content-type", "application/json")]
  if key {
    headers.push(("x-api-key", @shared.api_key))
  }
  { http_method, path, query_string: b"", headers, body: @utf8.encode(body), }
}

///|
/// The requests every registration is asked, in order: they add, read, refuse and
/// delete, so the answers depend on what the previous ones did.
let cases : Array[(String, String, String, Bool)] = [
  ("POST", "/tasks", "{\"title\":\"write the example\"}", false),
  ("POST", "/tasks", "{\"title\":\"write the example\"}", true),
  ("POST", "/tasks", "{\"title\":\"\"}", true),
  ("GET", "/tasks", "", false),
  ("GET", "/tasks/1", "", false),
  ("GET", "/tasks/99", "", false),
  ("DELETE", "/tasks/1", "", false),
  ("DELETE", "/tasks/1", "", true),
  ("GET", "/tasks", "", false),
  ("GET", "/nowhere", "", false),
]

///|
/// Run `cases` against one registration and return a line per answer. The store is
/// a fresh in-memory database each time, so the three runs start from the same
/// nothing.
async fn drive(build : () -> @moonapi.App) -> Array[String] {
  @shared.start(":memory:")
  let app = build()
  let out : Array[String] = []
  for case in cases {
    let (http_method, path, body, key) = case
    let response = app.handle(request(http_method, path, body, key))
    out.push(
      http_method +
      " " +
      path +
      " -> " +
      response.status.to_string() +
      " " +
      @utf8.decode_lossy(response.body[:]),
    )
  }
  @shared.stop()
  out
}

///|
/// Print what the three answers and stop when they disagree — the property the
/// three ways of writing a route are supposed to have, checked rather than
/// asserted in prose.
#coverage.skip
async fn main {
  let by_hand = drive(fns_build)
  let as_types = drive(cls_build)
  let as_annotations = drive(ann_build)
  for line in by_hand {
    println(line)
  }
  let differs = (mine : Array[String], theirs : Array[String]) => {
    mine.length() != theirs.length() ||
    mine.zip(theirs).any(pair => pair.0 != pair.1)
  }
  if differs(by_hand, as_types) || differs(by_hand, as_annotations) {
    println("DIFFERS: the three registrations do not answer alike")
    for i = 0; i < by_hand.length(); i = i + 1 {
      if by_hand[i] != as_types[i] || by_hand[i] != as_annotations[i] {
        println("  by hand: " + by_hand[i])
        println("  as types: " + as_types[i])
        println("  annotated: " + as_annotations[i])
      }
    }
    abort("the three registrations disagree")
  }
  println("same: all three registrations answer alike")
  // The other two projections of the same description: the body the document
  // publishes, which only the registration that can carry a descriptor hands it,
  // and the table, which every registration shares because the store owns it.
  let app = @fns.build()
  println("document title: " + app.info.title)
  println(
    "document publishes the request body: " +
    app.openapi_json().contains("\"requestBody\"").to_string(),
  )
  println("table: " + @shared.create_table_sql().replace_all(old="\n", new=" "))
}

///|
fn fns_build() -> @moonapi.App {
  @fns.build()
}

///|
fn cls_build() -> @moonapi.App {
  @cls.build()
}

///|
fn ann_build() -> @moonapi.App {
  @ann.build()
}
