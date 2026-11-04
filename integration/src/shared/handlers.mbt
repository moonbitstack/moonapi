// The handlers, written once and registered three ways by the packages beside
// this one. What they read is the description: the body is checked against the
// same declaration the table was built from, so a field the table holds and a
// field the API accepts cannot disagree.

///|
/// The store this process serves from. It is opened by `start` and closed by
/// `stop`, both called from the application's lifespan hooks — a connection that
/// lived for the length of the program without ever being opened on purpose is
/// the kind of thing that only works by accident.
let current : Ref[Store?] = Ref(None)

///|
/// Open the database at `path` and build the table. `":memory:"` gives a
/// throwaway one, which is what the check beside this example uses.
pub fn start(path : String) -> Unit raise @moondb.DbError {
  current.val = Some(Store::open(path))
}

///|
/// Close the database.
pub fn stop() -> Unit {
  match current.val {
    Some(store) => store.close()
    None => ()
  }
  current.val = None
}

///|
/// The store, or a `500`: a handler that runs with no database behind it would
/// answer as though the table were empty, which is a lie the caller cannot see.
fn store() -> Store raise {
  match current.val {
    Some(store) => store
    None => fail("moonapi: the store is not open")
  }
}

///|
/// The request body's declaration: the task without the key the server assigns.
/// A second description derived from the first, rather than a second place to
/// say what a task is.
pub fn request_schema() -> @moonapi.Schema {
  let fields = task().fields.filter(field => field.name != "id")
  let (schema, _unresolved) = @moonapi.Schema::of_model(
    @moonmodel.Model::new("TaskInput", fields, doc="a task to add"),
  )
  schema
}

///|
/// The endpoint the `POST` validates against.
pub fn create_endpoint() -> @moonapi.Endpoint {
  @moonapi.Endpoint::new(request_body=request_schema())
}

///|
/// One task as the API writes it.
fn json_of(task : Task) -> Json {
  Json({
    "id": Json::number(task.id.to_double()),
    "title": Json(task.title),
    "done": Json(task.done),
  })
}

///|
/// The id in a path, or `None` when it is not one. The router's `{id:int}`
/// convertor already refused anything else, so this is the narrow case of a
/// number that fits.
fn id_of(raw : String?) -> Int32? {
  guard raw is Some(text) && text.length() <= 9 && text.length() > 0 else {
    return None
  }
  let mut value : Int32 = 0
  for ch in text {
    guard ch is ('0'..<='9') else { return None }
    value = value * 10 + (ch.to_int() - '0'.to_int())
  }
  Some(value)
}

///|
/// `GET /tasks` — every task, newest id last.
pub fn list(ctx : @moonapi.Context) -> @moonasgi.Response raise {
  ignore(ctx)
  let items : Array[Json] = []
  for task in store().list() {
    items.push(json_of(task))
  }
  @moonapi.json(200, Json(items))
}

///|
/// `GET /tasks/{id}` — one task, or the `404` that says there is no such row.
pub fn one(ctx : @moonapi.Context) -> @moonasgi.Response raise {
  guard id_of(ctx.param("id")) is Some(id) else {
    return @moonapi.json(404, {
      "detail": "no task " + ctx.param("id").unwrap_or(""),
    })
  }
  match store().get(id) {
    Some(task) => @moonapi.json(200, json_of(task))
    None => @moonapi.json(404, { "detail": "no task \{id}" })
  }
}

///|
/// `POST /tasks` — the body is checked against the description before anything
/// is written, so a title of ninety characters is a `422` and never a row.
pub fn create(
  ctx : @moonapi.Context,
  endpoint : @moonapi.Endpoint,
) -> @moonasgi.Response raise {
  let errs = endpoint.validate(ctx)
  if errs.length() > 0 {
    return @moonapi.unprocessable(errs)
  }
  let body = ctx.body_json()
  let title = match body {
    Some(Object(m)) =>
      match m.get("title") {
        Some(String(s)) => s
        _ => ""
      }
    _ => ""
  }
  let done = match body {
    Some(Object(m)) =>
      match m.get("done") {
        Some(True) => true
        _ => false
      }
    _ => false
  }
  let task = store().add(title, done)
  @moonapi.json(201, json_of(task))
}

///|
/// `DELETE /tasks/{id}` — `204` whether or not there was a row to delete is a
/// lie; this one answers `404` when the id names nothing.
pub fn remove(ctx : @moonapi.Context) -> @moonasgi.Response raise {
  guard id_of(ctx.param("id")) is Some(id) else {
    return @moonapi.json(404, {
      "detail": "no task " + ctx.param("id").unwrap_or(""),
    })
  }
  if store().remove(id) {
    @moonapi.text(204, "")
  } else {
    @moonapi.json(404, { "detail": "no task \{id}" })
  }
}
