///|
test "panic a claim given twice is a mistake in the program" {
  create_access_token("heke", "a-secret", 1700000000L, extra={
    "sub": Json::string("somebody else"),
  })
  |> ignore
}

///|
test "security scopes: what a guard is told the route required" {
  let none = SecurityScopes::new()
  assert_eq(none.list(), [])
  assert_eq(none.scope_str(), "")
  assert_eq(none.challenge(), "Bearer")
  let some = SecurityScopes::new(scopes=["read", "write"])
  assert_eq(some.list(), ["read", "write"])
  assert_eq(some.scope_str(), "read write")
  assert_eq(some.challenge(), "Bearer scope=\"read write\"")
}
