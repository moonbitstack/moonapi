///|
async test "load_directory reads a tree, keyed with forward slashes" {
  let root = @fs.tmpdir(prefix="moonapi-templates-")
  @fs.mkdir(root + "/parts", recursive=true)
  @fs.write_file(root + "/page.html", "{% include 'parts/nav.html' %}!")
  @fs.write_file(root + "/parts/nav.html", "nav")
  let files = load_directory(root + "/")
  assert_eq(files.get("page.html"), Some("{% include 'parts/nav.html' %}!"))
  assert_eq(files.get("parts/nav.html"), Some("nav"))
  assert_eq(files.length(), 2)
  let t = Templates::new(@moonpug.Env::new(load=name => files.get(name)))
  assert_eq(body_of(t.response(request_at("/"), "page.html")), "nav!")
  @fs.rmdir(root, recursive=true)
}
