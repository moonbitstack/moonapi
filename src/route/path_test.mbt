///|
test "parse splits literals from parameters" {
  let p = @route.Pattern::parse("/users/{id:int}/files/{name}.json")
  assert_eq(p.pieces, [
    Literal("/users/"),
    Param(name="id", convertor=Int),
    Literal("/files/"),
    Param(name="name", convertor=Str),
    Literal(".json"),
  ])
  assert_eq(p.params(), [("id", Int), ("name", Str)])
  assert_eq(p.template(), "/users/{id}/files/{name}.json")
}

///|
test "a path without parameters is one literal" {
  let p = @route.Pattern::parse("/health")
  assert_eq(p.pieces, [Literal("/health")])
  assert_eq(p.bind("/health"), Some(Map([])))
  assert_eq(p.bind("/health/"), None)
}

///|
test "convertor names" {
  assert_eq(@route.Convertor::of("str"), Some(Str))
  assert_eq(@route.Convertor::of("int"), Some(Int))
  assert_eq(@route.Convertor::of("float"), Some(Float))
  assert_eq(@route.Convertor::of("uuid"), Some(Uuid))
  assert_eq(@route.Convertor::of("path"), Some(Path))
  assert_eq(@route.Convertor::of("slug"), None)
}

///|
test "str stops at a slash" {
  let p = @route.Pattern::parse("/u/{name}")
  assert_eq(p.bind("/u/leo"), Some(Map([("name", "leo")])))
  assert_eq(p.bind("/u/leo/x"), None)
  assert_eq(p.bind("/u/"), None)
}

///|
test "int takes digits only" {
  let p = @route.Pattern::parse("/n/{id:int}")
  assert_eq(p.bind("/n/233"), Some(Map([("id", "233")])))
  assert_eq(p.bind("/n/23a"), None)
  assert_eq(p.bind("/n/-1"), None)
}

///|
test "float takes a whole part and an optional fraction" {
  let p = @route.Pattern::parse("/f/{x:float}")
  assert_eq(p.bind("/f/1.5"), Some(Map([("x", "1.5")])))
  assert_eq(p.bind("/f/3"), Some(Map([("x", "3")])))
  assert_eq(p.bind("/f/1."), None)
  assert_eq(p.bind("/f/.5"), None)
  // The fraction is optional, so a literal dot after the parameter still binds.
  let q = @route.Pattern::parse("/f/{x:float}.txt")
  assert_eq(q.bind("/f/2.txt"), Some(Map([("x", "2")])))
  assert_eq(q.bind("/f/2.5.txt"), Some(Map([("x", "2.5")])))
}

///|
test "uuid takes the 8-4-4-4-12 form in either case" {
  let p = @route.Pattern::parse("/o/{id:uuid}")
  let id = "123e4567-e89b-12d3-a456-426614174000"
  assert_eq(p.bind("/o/" + id), Some(Map([("id", id)])))
  assert_eq(p.bind("/o/" + id.to_upper()), Some(Map([("id", id.to_upper())])))
  assert_eq(p.bind("/o/123e4567e89b12d3a456426614174000"), None)
  assert_eq(p.bind("/o/" + id + "0"), None)
}

///|
test "path takes the rest, slashes included" {
  let p = @route.Pattern::parse("/static/{rest:path}")
  assert_eq(
    p.bind("/static/css/site.css"),
    Some(Map([("rest", "css/site.css")])),
  )
  assert_eq(p.bind("/static/"), Some(Map([("rest", "")])))
  let q = @route.Pattern::parse("/files/{rest:path}/raw")
  assert_eq(q.bind("/files/a/b/raw"), Some(Map([("rest", "a/b")])))
}

///|
test "a parameter may be part of a segment" {
  let p = @route.Pattern::parse("/v{major:int}/{file}.json")
  assert_eq(
    p.bind("/v2/users.json"),
    Some(Map([("major", "2"), ("file", "users")])),
  )
  assert_eq(p.bind("/v2/users.yaml"), None)
}

///|
test "a greedy parameter gives back what the next literal needs" {
  let p = @route.Pattern::parse("/{a}-{b}")
  assert_eq(p.bind("/x-y-z"), Some(Map([("a", "x-y"), ("b", "z")])))
  assert_eq(p.bind("/xyz"), None)
}

///|
test "fill writes values back and refuses ones the convertor would not bind" {
  let p = @route.Pattern::parse("/users/{id:int}/{rest:path}")
  assert_eq(p.fill(Map([("id", "7"), ("rest", "a/b")])), Some("/users/7/a/b"))
  assert_eq(p.fill(Map([("id", "x"), ("rest", "a")])), None)
  assert_eq(p.fill(Map([("id", "7")])), None)
  let q = @route.Pattern::parse("/u/{name}")
  assert_eq(q.fill(Map([("name", "a/b")])), None)
}

///|
test "panic an unclosed brace" {
  ignore(@route.Pattern::parse("/users/{id"))
}

///|
test "panic a parameter without a name" {
  ignore(@route.Pattern::parse("/users/{:int}"))
}

///|
test "panic an unknown convertor" {
  ignore(@route.Pattern::parse("/users/{id:slug}"))
}

///|
test "panic two parameters with nothing between them" {
  ignore(@route.Pattern::parse("/{a}{b}"))
}
