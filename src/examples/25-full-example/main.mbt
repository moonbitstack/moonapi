///|
/// Serve the layered API on native HTTP and WebSocket transport.
///
///     moon run src/examples/25-full-example --target native
#coverage.skip
async fn main {
  let app = @application.build()
  println("moonapi serving on http://127.0.0.1:12000")
  @mooncat.serve(app.to_asgi()) catch {
    err => println("mooncat stopped: \{err}")
  }
}
