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
/// Get an object field by key, `None` if not an object or absent — test helper.
fn obj_get(j : Json, k : String) -> Json? {
  match j {
    Object(m) => m.get(k)
    _ => None
  }
}

///|
fn only(field : @moonmodel.Field) -> Schema {
  let model = @moonmodel.Model::new("T", [field])
  let (schema, _missing) = Schema::of_model(model)
  match schema {
    SObject(body) => body.fields[0].schema
    _ => SAny
  }
}
