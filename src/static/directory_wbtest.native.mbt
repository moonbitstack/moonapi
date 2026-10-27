///|
async test "a directory serves what is on disk now" {
  let root = @fs.tmpdir(prefix="moonapi-static-")
  @fs.mkdir(root + "/js", recursive=true)
  @fs.write_file(root + "/js/app.js", "let x = 1")
  let c = @testing.Client::new(serve(Directory::new(root + "/")))
  let r = c.get("/js/app.js")
  assert_eq(r.status, 200)
  assert_eq(r.text(), "let x = 1")
  assert_true(r.header("last-modified") is Some(_))
  assert_eq(c.get("/js").status, 404)
  assert_eq(c.get("/js/none.js").status, 404)
  @fs.write_file(root + "/js/app.js", "let x = 22")
  assert_eq(c.get("/js/app.js").text(), "let x = 22")
  @fs.rmdir(root, recursive=true)
}
