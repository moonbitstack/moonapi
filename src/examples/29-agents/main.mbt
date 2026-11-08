/// An application that offers itself to agents. The document it already
/// publishes becomes an MCP service at `/mcp` and a skill at `/SKILL.md`; both
/// are mounted the way the documentation pages are, and neither joins the
/// document a client reads.
///
///     moon run src/examples/29-agents

///|
/// One JSON-RPC message to the MCP endpoint, answered with the body a client
/// would read — the same path a real MCP client takes.
async fn ask(app : @moonapi.App, message : String) -> String {
  let reply = app.handle({
    http_method: "POST",
    path: "/mcp",
    query_string: b"",
    headers: [
      ("content-type", "application/json"),
      ("accept", "application/json"),
    ],
    body: @utf8.encode(message),
  })
  @utf8.decode_lossy(reply.body)
}

///|
/// The `tools` array of a `tools/list` answer, as names.
fn tool_names(answer : String) -> Array[String] {
  let parsed = @json.parse(answer) catch { _ => return [] }
  match parsed {
    Object(m) =>
      match m.get("result") {
        Some(Object(result)) =>
          match result.get("tools") {
            Some(Array(items)) =>
              items.map(item => {
                match item {
                  Object(tool) =>
                    match tool.get("name") {
                      Some(String(name)) => name
                      _ => "?"
                    }
                  _ => "?"
                }
              })
            _ => []
          }
        _ => []
      }
    _ => []
  }
}

///|
async fn main {
  let app = @moonapi.App::new()
  app.get(
    "/pets",
    _ctx => @moonapi.json(200, Json([Json("Rex"), Json("Milo")])),
    summary="List the pets",
    tags=["pets"],
  )
  app.get(
    "/pets/{id}",
    ctx => @moonapi.text(200, "pet " + ctx.param("id").unwrap_or("")),
    summary="Fetch one pet",
    endpoint=@endpoint.Endpoint::new(params=[
      @endpoint.Param::new("id", @endpoint.InPath, schema=SStr),
    ]),
    tags=["pets"],
  )
  app.describe(
    title="petstore",
    description="Two routes, offered to an agent as two tools.",
    api_version="1.0.0",
  )
  // One call: the MCP service at /mcp, the skill at /SKILL.md.
  @agent.expose(app, exposure={
    ..@agent.exposure,
    document_url: Some("/openapi.json"),
  })

  println("tools the MCP service offers:")
  let listed = ask(
    app, "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/list\"}",
  )
  for name in tool_names(listed) {
    println("  \{name}")
  }
  println("calling one through the same service:")
  let called = ask(
    app, "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"get_pets_id\",\"arguments\":{\"id\":\"7\"}}}",
  )
  println("  \{called}")
  println("the skill an agent reads first:")
  let skill = app.handle({
    http_method: "GET",
    path: "/SKILL.md",
    query_string: b"",
    headers: [],
    body: b"",
  })
  for line in @utf8.decode_lossy(skill.body).split("\n") {
    if line.has_prefix("| `get_pets_id`") ||
      line.has_prefix("- MCP endpoint:") ||
      line.has_prefix("name: ") {
      println("  \{line}")
    }
  }
}
