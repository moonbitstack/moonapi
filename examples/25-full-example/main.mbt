///|
/// Serve the layered API on native HTTP and WebSocket transport.
///
///     moon run examples/25-full-example --target native
#coverage.skip
async fn main {
	let app = @application.build()
	println("moonapi serving on http://127.0.0.1:8000")
	@mooncat.serve(app.to_asgi(), host="127.0.0.1", port=8000) catch {
		err => println("mooncat stopped: \{err}")
	}
}
