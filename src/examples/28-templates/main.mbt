/// Pages rendered from templates beside the files they link to. The templates
/// see the request and resolve routes by name; the stylesheet is served from a
/// static source mounted under `/static`. Both sources here are held in memory,
/// so the example runs anywhere; on native, `@templates.load_directory` and
/// `@static.Directory` read the same layout from disk.
///
///     moon run src/examples/28-templates

///|
async fn main {
  let app = @moonapi.App::new()
  let pages = @templates.Templates::new(
    @moonpug.Env::new(load=name => {
      match name {
        "base.html" =>
          Some(
            "<link rel=\"stylesheet\" href=\"/static/site.css\"><h1>{% block title %}{% endblock %}</h1>{% block body %}{% endblock %}",
          )
        "user.html" =>
          Some(
            "{% extends 'base.html' %}{% block title %}{{ name }}{% endblock %}{% block body %}<a href=\"{{ url_for('user', id=id|int + 1) }}\">next</a> from {{ request.path }}{% endblock %}",
          )
        _ => None
      }
    }),
    url_for=(name, params) => app.url_for(name, params~),
  )
  app.get(
    "/users/{id:int}",
    ctx => {
      let id = ctx.param("id").unwrap()
      pages.response(
        ctx,
        "user.html",
        context=Map([("name", Json("user " + id)), ("id", Json(id))]),
      )
    },
    name="user",
  )
  app.mount_asgi(
    "/static",
    @static.serve(
      @static.Memory::new(Map([("site.css", b"h1 { color: teal }")])),
    ),
  )
  for path in ["/users/7", "/static/site.css", "/static/missing.css"] {
    let resp = app.handle({
      http_method: "GET",
      path,
      query_string: b"",
      headers: [],
      body: b"",
    })
    let kind = resp.header("content-type").unwrap_or("-")
    println("\{path} -> \{resp.status} \{kind}")
    println("  \{@utf8.decode_lossy(resp.body[:])}")
  }
}
