///|
/// Walk a chain of object keys into a JSON document — test helper.
fn dig(j : Json, path : Array[String]) -> Json? {
  let mut cur : Json? = Some(j)
  for k in path {
    cur = match cur {
      Some(x) => obj_get(x, k)
      None => None
    }
  }
  cur
}

///|
/// Fetch a string field out of a JSON object, "" if absent — test helper.
fn json_str(j : Json, key : String) -> String {
  match j {
    Object(m) =>
      match m.get(key) {
        Some(String(s)) => s
        _ => ""
      }
    _ => ""
  }
}

///|
/// Parse a response body back into JSON — test helper.
fn resp_json(r : @moonasgi.Response) -> Json {
  @json.parse(@utf8.decode_lossy(r.body[:])) catch {
    _ => Json::null()
  }
}

///|
/// Get an object field by key, `None` if not an object or absent — test helper.
fn obj_get(j : Json, k : String) -> Json? {
  match j {
    Object(m) => m.get(k)
    _ => None
  }
}
