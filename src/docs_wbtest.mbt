// The pages an application serves about itself: one document, four readers, and
// the theme they all wear.

///|
/// The script a reader is loaded from, which is what a page pinning a version has
/// to carry.
fn reader_script(reader : Ui) -> String {
  match reader {
    @openapi.Scalar => @openapi.scalar_js
    @openapi.Swagger => @openapi.swagger_js
    @openapi.Redoc => @openapi.redoc_js
    @openapi.Redocly => @openapi.redocly_js
  }
}

///|
/// Every reader serves a page, and every one of them reads the document the
/// application publishes — the same bytes whichever reader the page chose.
async test "the four readers read the one document the app publishes" {
  let rendered = []
  for
    reader in [
      @openapi.Scalar,
      @openapi.Swagger,
      @openapi.Redoc,
      @openapi.Redocly,
    ] {
    let app = App::new()
    app.get("/pets", _ctx => @status.text(200, "pets"), summary="list pets")
    app.describe(title="petstore")
    app.enable_docs(ui=reader)
    let page = @utf8.decode_lossy(app.handle(mkreq("GET", "/docs")).body)
    assert_eq(page.contains(reader_script(reader)), true)
    assert_eq(page.contains("\"/openapi.json\""), true)
    let spec = app.handle(mkreq("GET", "/openapi.json"))
    assert_eq(spec.status, 200)
    rendered.push(@utf8.decode_lossy(spec.body))
  }
  // One document, whichever page asks for it.
  assert_eq(rendered[1] == rendered[0], true)
  assert_eq(rendered[2] == rendered[0], true)
  assert_eq(rendered[3] == rendered[0], true)
  // And the two readers that have a page of their own read it too.
  let app = App::new()
  app.get("/pets", _ctx => @status.text(200, "pets"), summary="list pets")
  let redoc = @utf8.decode_lossy(app.handle(mkreq("GET", "/redoc")).body)
  assert_eq(redoc.contains("spec-url=\"/openapi.json\""), true)
  assert_eq(redoc.contains(@openapi.redoc_js), true)
  let redocly = @utf8.decode_lossy(app.handle(mkreq("GET", "/redocly")).body)
  assert_eq(redocly.contains("\"/openapi.json\""), true)
  assert_eq(redocly.contains(@openapi.redocly_js), true)
}

///|
/// Redocly's reference renders under a licence key, which the page passes on
/// from the settings the application holds.
async test "the Redocly page carries the licence key it was given" {
  let app = App::new()
  app.enable_docs(ui=Redocly, ui_extra=Map([("licenseKey", Json("lic-42"))]))
  let page = @utf8.decode_lossy(app.handle(mkreq("GET", "/docs")).body)
  assert_eq(page.contains("{\"licenseKey\":\"lic-42\"}"), true)
  assert_eq(page.contains("RedoclyReferenceDocs.init"), true)
}

///|
/// A page wears the site's theme unless told otherwise: the palette, the faces,
/// the mark, the thin scrollbars and the bar naming the application. `Plain`
/// leaves the reader exactly as its maker ships it.
async test "the pages wear the site's theme, and Plain leaves them alone" {
  let themed = App::new()
  themed.describe(title="petstore")
  let page = @utf8.decode_lossy(themed.handle(mkreq("GET", "/docs")).body)
  assert_eq(page.contains("<html lang=\"en\" class=\"mo-docs\">"), true)
  assert_eq(page.contains("class=\"mo-bar\""), true)
  assert_eq(page.contains("class=\"mo-name\">petstore</span>"), true)
  assert_eq(
    page.contains("fonts.googleapis.com/css2?family=Space+Grotesk"),
    true,
  )
  assert_eq(page.contains("::-webkit-scrollbar"), true)
  assert_eq(page.contains("--iris:#898AC4"), true)
  // The two readers with a page of their own wear it as well.
  let redoc = @utf8.decode_lossy(themed.handle(mkreq("GET", "/redoc")).body)
  assert_eq(redoc.contains("class=\"mo-bar\""), true)
  assert_eq(redoc.contains("--iris:#898AC4"), true)
  let redocly = @utf8.decode_lossy(themed.handle(mkreq("GET", "/redocly")).body)
  assert_eq(redocly.contains("class=\"mo-bar\""), true)
  assert_eq(redocly.contains("--iris:#898AC4"), true)
  let plain = App::new()
  plain.describe(title="petstore")
  plain.enable_docs(theme=Plain)
  let bare = @utf8.decode_lossy(plain.handle(mkreq("GET", "/docs")).body)
  assert_eq(bare.contains("mo-docs"), false)
  assert_eq(bare.contains("--iris"), false)
  assert_eq(bare.contains(@openapi.scalar_js), true)
}

///|
/// The pages of a mounted application read the document under the prefix they are
/// served at, the readers that have a page of their own included.
async test "a mounted app's readers follow its root path" {
  let sub = App::new()
  sub.describe(title="inner")
  let app = App::new()
  app.mount("/api", sub)
  let redocly = @utf8.decode_lossy(
    app.handle(mkreq("GET", "/api/redocly")).body,
  )
  assert_eq(
    redocly.contains("RedoclyReferenceDocs.init(\"/api/openapi.json\""),
    true,
  )
  assert_eq(redocly.contains("href=\"/api/openapi.json\""), true)
  let redoc = @utf8.decode_lossy(app.handle(mkreq("GET", "/api/redoc")).body)
  assert_eq(redoc.contains("spec-url=\"/api/openapi.json\""), true)
}

///|
/// The Redocly page is a route of its own, so it can be moved or left off like
/// the other two.
async test "the Redocly route can be moved or left off" {
  let app = App::new()
  app.enable_docs(redocly_url=Some("/reference"), redoc_url=None)
  assert_eq(app.handle(mkreq("GET", "/redocly")).status, 404)
  assert_eq(app.handle(mkreq("GET", "/redoc")).status, 404)
  let moved = app.handle(mkreq("GET", "/reference"))
  assert_eq(moved.status, 200)
  assert_eq(@utf8.decode_lossy(moved.body).contains(@openapi.redocly_js), true)
}
