// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
fn bound(p : @route.Pattern, path : String, name : String) -> String? {
  p.bind(path).bind(params => params.get(name))
}

///|
test "regex: the whole path has to match, and named groups are parameters" {
  let p = @route.Pattern::regex(
    "/users/{id}", "/users/(?P<id>[0-9]+)(?:/profile)?",
  )
  assert_eq(bound(p, "/users/42", "id"), Some("42"))
  assert_eq(bound(p, "/users/42/profile", "id"), Some("42"))
  assert_true(p.bind("/users/abc") is None)
  assert_true(p.bind("/users/42/other") is None)
  assert_true(p.bind("/x/users/42") is None)
}

///|
test "regex: the template still names and documents the route" {
  let p = @route.Pattern::regex("/users/{id:int}", "/u/(?P<id>[0-9]+)")
  assert_eq(p.template(), "/users/{id}")
  assert_eq(p.fill({ "id": "7" }), Some("/users/7"))
  assert_true(p.bind("/users/7") is None)
  assert_eq(bound(p, "/u/7", "id"), Some("7"))
}

///|
test "regex: a group that took no part binds to nothing" {
  let p = @route.Pattern::regex("/items", "/items(?:/(?P<id>[0-9]+))?")
  assert_eq(bound(p, "/items", "id"), Some(""))
  assert_eq(bound(p, "/items/3", "id"), Some("3"))
}

///|
test "glob: a star stays in its segment, two cross them" {
  let one = @route.Pattern::glob("/f/{name}", "/f/*.css")
  assert_eq(bound(one, "/f/site.css", "name"), Some("site"))
  assert_true(one.bind("/f/a/site.css") is None)
  assert_true(one.bind("/f/site.js") is None)
  let many = @route.Pattern::glob("/f/{rest:path}", "/f/**")
  assert_eq(bound(many, "/f/a/b/c.css", "rest"), Some("a/b/c.css"))
  assert_eq(bound(many, "/f/", "rest"), Some(""))
}

///|
test "glob: `**/` is any number of whole segments" {
  let p = @route.Pattern::glob("/a", "/a/**/b.txt")
  assert_true(p.bind("/a/b.txt") is Some(_))
  assert_true(p.bind("/a/x/b.txt") is Some(_))
  assert_true(p.bind("/a/x/y/b.txt") is Some(_))
  assert_true(p.bind("/a/xb.txt") is None)
}

///|
test "glob: question marks, classes and alternatives" {
  let p = @route.Pattern::glob("/v", "/v?/[a-c][!0-9].{png,jpg}")
  assert_true(p.bind("/v1/ax.png") is Some(_))
  assert_true(p.bind("/v2/cz.jpg") is Some(_))
  assert_true(p.bind("/v/ax.png") is None)
  assert_true(p.bind("/v1/dx.png") is None)
  assert_true(p.bind("/v1/a1.png") is None)
  assert_true(p.bind("/v1/ax.gif") is None)
}

///|
test "glob: what a regular expression treats as special is plain" {
  let p = @route.Pattern::glob("/a", "/a+b.(c)$")
  assert_true(p.bind("/a+b.(c)$") is Some(_))
  assert_true(p.bind("/aab.(c)$") is None)
  assert_true(p.bind("/a+bx(c)$") is None)
}

///|
test "glob: wildcards past the template's parameters still match" {
  let p = @route.Pattern::glob("/f/{a}", "/f/*/*")
  assert_eq(bound(p, "/f/x/y", "a"), Some("x"))
}

///|
test "of: nothing is the template, and a template ignores no one" {
  let plain = @route.Pattern::of("/users/{id:int}")
  assert_eq(plain, @route.Pattern::parse("/users/{id:int}"))
  assert_eq(bound(plain, "/users/1", "id"), Some("1"))
  let re = @route.Pattern::of("/a", regex="/b")
  assert_true(re.bind("/b") is Some(_))
  let g = @route.Pattern::of("/a", glob="/c*")
  assert_true(g.bind("/cd") is Some(_))
}

///|
test "moved: a prefix goes in front of a matcher" {
  let p = @route.Pattern::regex("/users/{id}", "/users/(?P<id>[0-9]+)")
  let m = p.moved("/api/users/{id}", "/api/")
  assert_eq(m.template(), "/api/users/{id}")
  assert_eq(bound(m, "/api/users/9", "id"), Some("9"))
  assert_true(m.bind("/users/9") is None)
  let twice = m.moved("/v1/api/users/{id}", "/v1")
  assert_eq(bound(twice, "/v1/api/users/9", "id"), Some("9"))
}

///|
test "moved: a template is parsed again at its new path" {
  let m = @route.Pattern::parse("/x/{id}").moved("/p/x/{id}", "/p")
  assert_eq(m, @route.Pattern::parse("/p/x/{id}"))
}

///|
test "panic both regex and glob" {
  ignore(@route.Pattern::of("/a", regex="/a", glob="/a"))
}

///|
test "panic a regular expression that does not compile" {
  ignore(@route.Pattern::regex("/a", "("))
}

///|
test "panic an unclosed brace in a glob" {
  ignore(@route.Pattern::glob("/a", "/{a,b"))
}

///|
test "panic an unclosed class in a glob" {
  ignore(@route.Pattern::glob("/a", "/[ab"))
}
