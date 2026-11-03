// The model is written once, here, and everything else in this example is a
// projection of it: the schema the request body is checked against and the
// document publishes, the `CREATE TABLE` the database is built from, and the
// columns the ORM writes a record back through.

///|
/// A task, described in the vocabulary all four projections read. `id` is unique
/// because the application assigns it and a row is addressed by it; `title`
/// carries the bounds the API publishes *and* enforces; `done` may be left out
/// of a request, which is a different statement from being nullable.
pub fn task() -> @moonmodel.Model {
  @moonmodel.Model::new(
    "Task",
    [
      @moonmodel.Field::new(
        "id",
        @moonmodel.Int,
        check=@moonmodel.Check::new(unique=true),
      ),
      @moonmodel.Field::new(
        "title",
        @moonmodel.Text,
        check=@moonmodel.Check::new(shortest=1, longest=80),
      ),
      @moonmodel.Field::new("done", @moonmodel.Bool, required=false),
    ],
    doc="something to do",
  )
}

///|
/// The record one row is read into. The description above says what the columns
/// are; this type is what the program holds, and the two closures below are the
/// only place the two are tied together.
pub(all) struct Task {
  id : Int32
  title : String
  done : Bool
}

///|
/// The column type the description's field kind becomes, or `None` for a kind
/// that has no column — a nested model, a list, anything the SQL projection
/// refuses. Reporting it rather than guessing keeps the table honest.
fn column_type(kind : @moonmodel.Type) -> @schema.ColumnType? {
  match kind {
    @moonmodel.Int => Some(@schema.IntType)
    @moonmodel.Big => Some(@schema.BigIntType)
    @moonmodel.Real => Some(@schema.RealType)
    @moonmodel.Text => Some(@schema.TextType)
    @moonmodel.Bool => Some(@schema.BoolType)
    @moonmodel.Bytes => Some(@schema.BlobType)
    _ => None
  }
}

///|
/// The description as the ORM's columns. The field the description calls `id`
/// and marks unique is the primary key here, because that is what the unit of
/// work needs to find a row again; nothing else is decided twice.
pub fn columns() -> Array[@moonorm.Column] {
  let out : Array[@moonorm.Column] = []
  for field in task().fields {
    guard column_type(field.kind) is Some(kind) else { continue }
    out.push(
      @moonorm.column(
        field.name,
        kind,
        primary_key=field.name == "id" && field.check.unique,
        unique=field.check.unique,
      ),
    )
  }
  out
}

///|
/// The ORM model: the columns above, a row decoder and the binding projection.
/// The decoder reads by position, in the order `columns` lists them, which is the
/// order a plain `SELECT` returns them in.
pub let task_model : @moonorm.Model[Task] = @moonorm.Model::new(
  "Task",
  columns(),
  row => {
    // SQLite has no boolean storage class: a `BOOL` column comes back as an
    // integer, so what "done" is has to be read out of the value rather than
    // asked of the driver.
    let done = match row.get(2) {
      @moondb.Int64(n) => n != 0L
      @moondb.Int(n) => n != 0
      @moondb.Bool(b) => b
      _ => false
    }
    { id: row.int(0), title: row.text(1), done, }
  },
  task => {
    [
      ("id", @moondb.Int(task.id)),
      ("title", @moondb.Text(task.title)),
      ("done", @moondb.Bool(task.done)),
    ]
  },
)

///|
/// The `CREATE TABLE` the same description becomes. Not written by hand and not
/// generated from the ORM model: this is what the description itself says the
/// table is, which is why the document, the validation and the database cannot
/// drift apart.
pub fn create_table_sql() -> String {
  @sql.table(task(), dialect=@sql.Sqlite)
}
