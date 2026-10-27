///|
fn site() -> Memory {
  Memory::new(
    Map([
      ("css/site.css", b"body{}"),
      ("index.html", b"<h1>home</h1>"),
      ("docs/index.html", b"<h1>docs</h1>"),
      ("404.html", b"<h1>gone</h1>"),
    ]),
    modified=@moondate.Moment::of_epoch(1_700_000_000L, zone=Utc),
  )
}

///|
fn client(html~ : Bool = false, root_path~ : String = "") -> @testing.Client {
  @testing.Client::new(serve(site(), html~), root_path~)
}

///|
async test "a file comes back typed, dated and tagged" {
  let r = client().get("/css/site.css")
  assert_eq(r.status, 200)
  assert_eq(r.text(), "body{}")
  assert_eq(r.header("content-type"), Some("text/css; charset=utf-8"))
  assert_eq(r.header("content-length"), Some("6"))
  assert_eq(r.header("last-modified"), Some("Tue, 14 Nov 2023 22:13:20 GMT"))
  assert_eq(r.header("etag"), Some("W/\"6553f100-6\""))
  assert_eq(r.header("accept-ranges"), Some("bytes"))
}

///|
async test "HEAD has the headers and no body" {
  let r = client().request(http_method="HEAD", path="/css/site.css")
  assert_eq(r.status, 200)
  assert_eq(r.header("content-length"), Some("6"))
  assert_eq(r.body, b"")
}

///|
async test "a current copy is a 304 and a range is a 206" {
  let c = client()
  let tag = c.get("/css/site.css").header("etag").unwrap()
  assert_eq(
    c.get("/css/site.css", headers=[("if-none-match", tag)]).status,
    304,
  )
  let part = c.get("/css/site.css", headers=[("range", "bytes=0-3")])
  assert_eq(part.status, 206)
  assert_eq(part.text(), "body")
  assert_eq(part.header("content-range"), Some("bytes 0-3/6"))
}

///|
async test "only GET and HEAD are served" {
  let r = client().post("/css/site.css")
  assert_eq(r.status, 405)
  assert_eq(r.header("allow"), Some("GET, HEAD"))
}

///|
async test "nothing outside the source is reachable" {
  let c = client()
  assert_eq(c.get("/css/../index.html").status, 404)
  assert_eq(c.get("/css\\site.css").status, 404)
  assert_eq(c.get("/c:/x").status, 404)
  assert_eq(c.get("/missing.js").status, 404)
  // Without `html`, a directory is not a file.
  assert_eq(c.get("/").status, 404)
}

///|
async test "html: indexes, the trailing-slash redirect and the 404 page" {
  let c = client(html=true, root_path="/static")
  assert_eq(c.get("/").text(), "<h1>home</h1>")
  let moved = c.get("/docs", headers=[])
  assert_eq(moved.status, 307)
  assert_eq(moved.header("location"), Some("/static/docs/"))
  let docs = c.get("/docs/")
  assert_eq(docs.status, 200)
  assert_eq(docs.text(), "<h1>docs</h1>")
  assert_eq(docs.header("content-type"), Some("text/html; charset=utf-8"))
  let gone = c.get("/nope")
  assert_eq(gone.status, 404)
  assert_eq(gone.text(), "<h1>gone</h1>")
}

///|
async test "a source with no dates hashes its tags instead" {
  let undated = Memory::new(Map([("a.txt", b"hi")]))
  let r = @testing.Client::new(serve(undated)).get("/a.txt")
  assert_eq(r.status, 200)
  assert_eq(r.header("last-modified"), None)
  assert_true(r.header("etag") is Some(_))
}

///|
async test "ranges=false withdraws partial content" {
  let r = @testing.Client::new(serve(site(), ranges=false)).get(
    "/css/site.css",
    headers=[("range", "bytes=0-1")],
  )
  assert_eq(r.status, 200)
  assert_eq(r.header("accept-ranges"), Some("none"))
}
