// The rows. One SQLite connection opened at startup, and a session per call: a
// session is the unit of work. A session is not closed when the call ends —
// `Session::close` closes the connection under it, which is the connection this
// store owns — so the one close that matters is `Store::close`.

///|
/// The store the whole process shares. It holds the driver rather than a session,
/// so each call starts from a clean unit of work.
pub struct Store {
  driver : @moonsqlite.SqliteDriver
}

///|
/// Open `path` — `":memory:"` for a throwaway — and build the table from the
/// description if the file does not have one yet. Whether the table is already
/// there is the database's business: the description says what a task is, and says
/// nothing about how many times it has been created.
pub fn Store::open(path : String) -> Store raise @moondb.DbError {
  let driver = @moonsqlite.SqliteDriver::open(path)
  let existing = driver.query(
    "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
    [@moondb.Text("Task")],
  )
  if existing.length() == 0 {
    driver.exec_script(create_table_sql())
  }
  { driver, }
}

///|
/// Every task, in the order the table hands them back.
pub fn Store::list(self : Store) -> Array[Task] raise @moondb.DbError {
  let session = @moonorm.Session::new(self.driver)
  session.all(task_model)
}

///|
/// One task by its id, or `None`.
pub fn Store::get(self : Store, id : Int32) -> Task? raise @moondb.DbError {
  let session = @moonorm.Session::new(self.driver)
  session.get(task_model, @moondb.Int(id))
}

///|
/// Append a task under the next free id. The id is the application's to assign:
/// nothing in the description says the database invents one.
pub fn Store::add(
  self : Store,
  title : String,
  done : Bool,
) -> Task raise @moondb.DbError {
  let session = @moonorm.Session::new(self.driver)
  let mut next = 1
  for existing in session.all(task_model) {
    if existing.id >= next {
      next = existing.id + 1
    }
  }
  let task = { id: next, title, done, }
  session.insert_record(task_model, task) |> ignore
  session.flush()
  task
}

///|
/// Delete the task `id`, `false` when there was nothing to delete.
pub fn Store::remove(self : Store, id : Int32) -> Bool raise @moondb.DbError {
  let session = @moonorm.Session::new(self.driver)
  let found = session.get(task_model, @moondb.Int(id))
  match found {
    Some(task) => {
      session.delete_record(task_model, task)
      session.flush()
      true
    }
    None => false
  }
}

///|
/// Close the connection. The driver owns the file handle, so this is what makes
/// the last write durable.
pub fn Store::close(self : Store) -> Unit {
  self.driver.close()
}
