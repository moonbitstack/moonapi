///|
/// A response model that mirrors a public "user" view: id, name, and a nested
/// address — deliberately narrower than what a handler might hold internally.
fn user_view_model() -> Schema {
  Schema::object("UserView", [
    Field::new("id", SInt),
    Field::new("name", SStr),
    Field::new(
      "address",
      Schema::object("AddressView", [Field::new("city", SStr)]),
    ),
  ])
}

///|
test "response_model drops fields the model doesn't declare" {
  // The handler produced a richer object (a password hash, an internal flag, an
  // extra address field); only the declared fields survive.
  let produced = @json.parse(
    "{\"id\":7,\"name\":\"ada\",\"password_hash\":\"xyz\",\"internal\":true,\"address\":{\"city\":\"London\",\"country\":\"UK\"}}",
  ) catch {
    _ => Json::null()
  }
  let filtered = match filter_response(user_view_model(), produced) {
    Ok(j) => j
    Err(_) => Json::null()
  }
  assert_eq(json_str(filtered, "name"), "ada")
  assert_eq(dig(filtered, ["id"]).unwrap(), Json(7))
  // Extra top-level fields are gone.
  assert_eq(dig(filtered, ["password_hash"]) is None, true)
  assert_eq(dig(filtered, ["internal"]) is None, true)
  // The nested object is projected too: city stays, country is dropped.
  let addr = dig(filtered, ["address"]).unwrap()
  assert_eq(json_str(addr, "city"), "London")
  assert_eq(dig(addr, ["country"]) is None, true)
}

///|
test "response_model projects through arrays element-wise" {
  let model = Schema::array(Schema::object("Tag", [Field::new("label", SStr)]))
  let produced = @json.parse(
    "[{\"label\":\"a\",\"weight\":5},{\"label\":\"b\",\"weight\":9}]",
  ) catch {
    _ => Json::null()
  }
  let filtered = match filter_response(model, produced) {
    Ok(j) => j
    Err(_) => Json::null()
  }
  match filtered {
    Array(a) => {
      assert_eq(a.length(), 2)
      assert_eq(json_str(a[0], "label"), "a")
      // The undeclared `weight` was stripped from each element.
      assert_eq(dig(a[0], ["weight"]) is None, true)
      assert_eq(dig(a[1], ["weight"]) is None, true)
    }
    _ => assert_eq("expected array", "got other")
  }
}

///|
test "response_model rejects a value that doesn't match the model" {
  // Missing the required `name`, and `id` is a string not an integer.
  let bad = @json.parse("{\"id\":\"seven\",\"address\":{\"city\":\"X\"}}") catch {
    _ => Json::null()
  }
  match filter_response(user_view_model(), bad) {
    Ok(_) => assert_eq("expected Err", "got Ok")
    Err(errs) => {
      // Errors are located under ["response", ...].
      let kinds : Array[String] = []
      for e in errs {
        kinds.push(e.kind)
        assert_eq(e.loc[0], "response")
      }
      assert_eq(kinds.contains("int_type"), true)
      assert_eq(kinds.contains("missing"), true)
    }
  }
}

///|
test "json_model: success emits the filtered body, mismatch is a 500" {
  let produced = @json.parse(
    "{\"id\":1,\"name\":\"x\",\"secret\":\"nope\",\"address\":{\"city\":\"C\"}}",
  ) catch {
    _ => Json::null()
  }
  let ok = json_model(200, user_view_model(), produced)
  assert_eq(ok.status, 200)
  assert_eq(dig(resp_json(ok), ["secret"]) is None, true)
  assert_eq(json_str(resp_json(ok), "name"), "x")
  // A non-conforming return value surfaces as a server error, not bad output.
  let bad = @json.parse("{\"id\":1}") catch { _ => Json::null() }
  let fail = json_model(200, user_view_model(), bad)
  assert_eq(fail.status, 500)
}
