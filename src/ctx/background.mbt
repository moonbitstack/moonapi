// Background tasks (← FastAPI's `BackgroundTasks`): work a handler schedules to run after its
// response has gone out, so the request stays fast and the mail, the audit log or the cache
// warm-up happen on the way out. Every context carries one.

///|
/// A queue of deferred tasks. A handler adds to `ctx.background`; the app runs the queue in the
/// order tasks were added, after the response is sent and within the same request.
pub struct BackgroundTasks {
  priv tasks : Array[async () -> Unit]
}

///|
/// An empty task queue.
pub fn BackgroundTasks::new() -> BackgroundTasks {
  { tasks: [], }
}

///|
/// Enqueue a task to run after the response is sent (← `BackgroundTasks.add_task`).
pub fn BackgroundTasks::add_task(
  self : BackgroundTasks,
  task : async () -> Unit,
) -> Unit {
  self.tasks.push(task)
}

///|
/// How many tasks are queued.
pub fn BackgroundTasks::length(self : BackgroundTasks) -> Int32 {
  self.tasks.length()
}

///|
/// Run every queued task in order, each after the previous returns, then clear the queue. A
/// task that raises stops the ones after it and the error goes to the caller, as in Starlette.
pub async fn BackgroundTasks::run(self : BackgroundTasks) -> Unit {
  let tasks = self.tasks.copy()
  self.tasks.clear()
  for task in tasks {
    task()
  }
}
