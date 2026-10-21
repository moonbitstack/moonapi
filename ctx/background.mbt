// Background tasks (← FastAPI's `BackgroundTasks`). A handler schedules work to
// run *after* its response has been sent to the client: the request path stays
// fast, and the deferred work (sending a mail, writing an audit log) happens on
// the way out. FastAPI injects a `BackgroundTasks` parameter; the explicit
// MoonBit equivalent is a request-scoped value the app hands a background-aware
// handler, whose queued thunks the app drains once the response is on the wire.

///|
/// A queue of deferred thunks (← FastAPI's `BackgroundTasks`). A background-aware
/// route receives one per request, calls `add_task` to enqueue work, and the app
/// runs the queue — in enqueue order — after the response has been sent.
pub struct BackgroundTasks {
  tasks : Array[() -> Unit]
}

///|
/// An empty task queue.
pub fn BackgroundTasks::new() -> BackgroundTasks {
  { tasks: [], }
}

///|
/// Enqueue a thunk to run after the response is sent. Tasks run in the order they
/// were added, each after the previous returns (← `BackgroundTasks.add_task`).
pub fn BackgroundTasks::add_task(
  self : BackgroundTasks,
  task : () -> Unit,
) -> Unit {
  self.tasks.push(task)
}

///|
/// How many tasks are queued — the app checks this to skip the drain when a route
/// scheduled nothing.
pub fn BackgroundTasks::len(self : BackgroundTasks) -> Int32 {
  self.tasks.length()
}

///|
/// Run every queued task in order, then clear the queue. Called by the app once
/// the response has been handed to the transport, so a task's latency never
/// delays the client. Idempotent: a second call runs nothing.
pub fn BackgroundTasks::run(self : BackgroundTasks) -> Unit {
  for task in self.tasks {
    task()
  }
  self.tasks.clear()
}

///|
/// Move `other`'s queued tasks onto this queue (used when a mounted sub-app's
/// tasks bubble up to the request that reached it), leaving `other` empty.
pub fn BackgroundTasks::absorb(
  self : BackgroundTasks,
  other : BackgroundTasks,
) -> Unit {
  for task in other.tasks {
    self.tasks.push(task)
  }
  other.tasks.clear()
}
