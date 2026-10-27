///|
fn sources(files : Map[String, String]) -> @moonpug.Env {
  @moonpug.Env::new(load=name => files.get(name))
}

///|
fn request_at(path : String, query~ : Bytes = b"") -> @ctx.Context {
  let req : @moonasgi.Request = {
    http_method: "GET",
    path,
    query_string: query,
    headers: [("accept-language", "en")],
    body: b"",
  }
  @ctx.Context::new(req, params=Map([("id", "7")]))
}

///|
fn text(j : Json) -> String {
  guard j is String(s) else { "" }
  s
}

///|
fn body_of(resp : @moonasgi.Response) -> String {
  @utf8.decode_lossy(resp.body[:])
}

///|
test "a template sees the request and the context, escaped as HTML" {
  let t = Templates::new(
    sources(
      Map([
        (
          "item.html", "{{ request.method }} {{ request.url }} {{ request.params.id }} {{ request.query.q }} {{ name }}",
        ),
      ]),
    ),
  )
  let resp = t.response(
    request_at("/items/7", query=b"q=lamp"),
    "item.html",
    context=Map([("name", "<b>")]),
  )
  assert_eq(resp.status, 200)
  assert_eq(resp.headers, [("content-type", "text/html; charset=utf-8")])
  assert_eq(body_of(resp), "GET /items/7?q=lamp 7 lamp &lt;b&gt;")
}

///|
test "status and media type are the caller's" {
  let t = Templates::new(sources(Map([("feed.xml", "<feed/>")])))
  let resp = t.response(
    request_at("/feed"),
    "feed.xml",
    status=201,
    media_type="application/atom+xml",
  )
  assert_eq(resp.status, 201)
  assert_eq(resp.headers, [("content-type", "application/atom+xml")])
}

///|
test "processors add names; the call's context wins a clash by default" {
  let t = Templates::new(sources(Map([("a.txt", "{{ site }} {{ user }}")])), processors=[
    _ => { "site": "moon", "user": "anon" },
  ])
  let ctx = request_at("/")
  assert_eq(body_of(t.response(ctx, "a.txt")), "moon anon")
  assert_eq(
    body_of(t.response(ctx, "a.txt", context=Map([("user", "leo")]))),
    "moon leo",
  )
  assert_eq(
    body_of(t.response(ctx, "a.txt", context=Map([("user", "leo")]), wins=Base)),
    "moon anon",
  )
  let decided = t.response(
    ctx,
    "a.txt",
    context=Map([("user", "leo")]),
    clash=Handle((base, merged) => {
      let out = merged.copy()
      out["user"] = Json(text(base["user"]) + "+" + text(merged["user"]))
      out
    }),
  )
  assert_eq(body_of(decided), "moon anon+leo")
}

///|
test "panic a clash under clash=Panic" {
  let t = Templates::new(sources(Map([("a.txt", "{{ user }}")])), processors=[
    _ => { "user": "anon" },
  ])
  ignore(
    t.response(
      request_at("/"),
      "a.txt",
      context=Map([("user", "leo")]),
      clash=Panic,
    ),
  )
}

///|
test "url_for resolves through the function the app gives" {
  let t = Templates::new(
    sources(Map([("nav.txt", "{{ url_for('user', id=7) }}")])),
    url_for=(name, params) => {
      if name == "user" {
        params.get("id").map(id => "/users/" + id)
      } else {
        None
      }
    },
  )
  assert_eq(body_of(t.response(request_at("/"), "nav.txt")), "/users/7")
  let missing = Templates::new(
    sources(Map([("nav.txt", "{{ url_for('nope') }}")])),
    url_for=(_, _) => None,
  )
  let refused = Some(missing.response(request_at("/"), "nav.txt")) catch {
    _ => None
  }
  assert_true(refused is None)
}

///|
test "a template that does not exist is refused" {
  let t = Templates::new(sources(Map([])))
  let refused = Some(t.response(request_at("/"), "gone.html")) catch {
    _ => None
  }
  assert_true(refused is None)
}
