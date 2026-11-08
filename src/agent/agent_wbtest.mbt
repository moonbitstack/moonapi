// What an agent gets when an application offers itself: the tools it can call,
// the answers they give, and the skill it reads before calling any of them.

///|
/// The MCP endpoint seen from the outside: one POST per message to the path the
/// application mounted it at, answered with the body a real client would read.
/// It is the transport a client needs, without a socket under it — the request
/// still crosses the mount, the ASGI event stream and the JSON-RPC dispatch.
struct Endpoint {
  app : @moonapi.App
  url : String
}

///|
async fn Endpoint::post(self : Endpoint, message : Json) -> @moonasgi.Response {
  self.app.handle({
    http_method: "POST",
    path: self.url,
    query_string: b"",
    headers: [
      ("content-type", "application/json"),
      ("accept", "application/json"),
    ],
    body: @utf8.encode(message.stringify()),
  })
}

///|
impl @client.Transport for Endpoint with fn ask(self, message, _on_notification) -> Json {
  let resp = self.post(message)
  @json.parse(@utf8.decode_lossy(resp.body)) catch {
    _ => Json::null()
  }
}

///|
impl @client.Transport for Endpoint with fn tell(self, message) -> Unit {
  ignore(self.post(message))
}

///|
impl @client.Transport for Endpoint with fn listen(
  _self,
  _message,
  _on_notification,
) -> Unit {
  ()
}

///|
impl @client.Transport for Endpoint with fn close(_self) -> Unit {
  ()
}

///|
impl @client.Transport for Endpoint with fn answer_with(_self, _answer) -> Unit {
  ()
}

///|
/// The text of a tool's answer, which is what the tool put there.
fn answer_text(result : @types.CallToolResult) -> String {
  let out = StringBuilder()
  for block in result.content {
    match block {
      Text(text~, ..) => out.write_string(text)
      _ => ()
    }
  }
  out.to_string()
}

///|
/// An application with a path parameter, a query parameter and a JSON body, so
/// that a tool has all three kinds of argument to fill.
fn petstore() -> @moonapi.App {
  let app = @moonapi.App::new()
  app.get(
    "/pets/{id}",
    ctx => {
      @moonapi.json(
        200,
        Json({
          "id": Json(ctx.param("id").unwrap_or("")),
          "note": Json(ctx.query("note").unwrap_or("")),
        }),
      )
    },
    summary="Fetch one pet",
    endpoint=@endpoint.Endpoint::new(params=[
      @endpoint.Param::new("id", @endpoint.InPath, schema=SStr),
      @endpoint.Param::new(
        "note",
        @endpoint.InQuery,
        schema=SStr,
        required=false,
      ),
    ]),
    tags=["pets"],
  )
  app.post(
    "/pets",
    ctx => {
      @moonapi.json(
        201,
        Json({ "made": ctx.body_json().unwrap_or(Json::null()) }),
      )
    },
    summary="Add a pet",
    status_code=201,
    endpoint=@endpoint.Endpoint::new(
      request_body=@schema.Schema::object("Pet", [
        @schema.Field::new("name", SStr, required=true),
      ]),
      request_required=true,
    ),
    tags=["pets"],
  )
  app.get("/health", _ctx => @moonapi.text(200, "ok"), summary="Liveness", tags=[
    "ops",
  ])
  app.describe(title="petstore", description="A pet shop.", api_version="1.2.3")
  app
}

///|
/// A call through the MCP service answers what the route answers, with the
/// arguments it was given — the same bytes a client of the API would read.
async test "an agent calls a route through the MCP service" {
  let app = petstore()
  expose(app)
  let client = @client.Client::connect(
    Endpoint::{ app, url: "/mcp", },
    protocol_version="2025-06-18",
  )
  let tools = client.list_tools()
  assert_eq(tools.map(tool => tool.name), [
    "get_pets_id", "post_pets", "get_health",
  ])
  let direct = app.handle({
    http_method: "GET",
    path: "/pets/7",
    query_string: b"note=calm",
    headers: [],
    body: b"",
  })
  let called = client.call_tool(
    "get_pets_id",
    arguments=Map([("id", Json("7")), ("note", Json("calm"))]),
  )
  assert_eq(called.is_error, false)
  assert_eq(answer_text(called), @utf8.decode_lossy(direct.body))
  assert_eq(answer_text(called), "{\"id\":\"7\",\"note\":\"calm\"}")
  // The body travels as the argument called `body`, and comes back as sent.
  let made = client.call_tool(
    "post_pets",
    arguments=Map([("body", Json({ "name": Json("Rex") }))]),
  )
  assert_eq(made.is_error, false)
  assert_eq(answer_text(made), "{\"made\":{\"name\":\"Rex\"}}")
  client.close()
}

///|
/// A status of 400 or above is an error to an agent, not an answer to parse as
/// one, and the body still arrives so it can say what went wrong.
async test "a refused call comes back marked as an error, body included" {
  let app = @moonapi.App::new()
  app.get("/boom", _ctx => @moonapi.text(503, "down for now"), summary="Boom")
  expose(app)
  let client = @client.Client::connect(
    Endpoint::{ app, url: "/mcp", },
    protocol_version="2025-06-18",
  )
  let called = client.call_tool("get_boom")
  assert_eq(called.is_error, true)
  assert_eq(answer_text(called), "down for now")
  client.close()
}

///|
/// The tool's schema is the operation's own: a parameter's place, the body, and
/// what is required — inlined, so an agent needs nothing but the tool.
async test "a tool's schema carries the arguments of its operation" {
  let app = @moonapi.App::new()
  app.post(
    "/items",
    _ctx => @moonapi.text(201, "made"),
    summary="Add an item",
    endpoint=@endpoint.Endpoint::new(
      params=[
        @endpoint.Param::new(
          "draft",
          @endpoint.InQuery,
          schema=SBool,
          required=false,
        ),
      ],
      request_body=@schema.Schema::object("Item", [
        @schema.Field::new("name", SStr, required=true),
      ]),
      request_required=true,
    ),
  )
  app.describe(title="items")
  expose(app)
  let client = @client.Client::connect(
    Endpoint::{ app, url: "/mcp", },
    protocol_version="2025-06-18",
  )
  let tool = client.list_tools()[0]
  assert_eq(tool.name, "post_items")
  let schema = tool.input_schema
  assert_eq(schema_json(schema, ["type"]), "object")
  assert_eq(schema_json(schema, ["properties", "draft", "type"]), "boolean")
  assert_eq(schema_json(schema, ["properties", "body", "type"]), "object")
  assert_eq(schema_json(schema, ["required"]), "[\"body\"]")
  client.close()
}

///|
/// Reaching into a JSON object by a path of keys, "" when there is nothing
/// there — test helper.
fn schema_json(j : Json, keys : Array[String]) -> String {
  let mut here = j
  for key in keys {
    match here {
      Object(m) =>
        match m.get(key) {
          Some(next) => here = next
          None => return ""
        }
      _ => return ""
    }
  }
  match here {
    String(s) => s
    _ => here.stringify()
  }
}

///|
/// The skill is the API in prose: where to connect, what each tool takes, and
/// the frontmatter an agent reads to decide whether to read the rest.
async test "the skill says how to reach the API and what each tool takes" {
  let app = petstore()
  let settings = { ..exposure, document_url: Some("/openapi.json"), }
  expose(app, exposure=settings)
  let page = app.handle({
    http_method: "GET",
    path: "/SKILL.md",
    query_string: b"",
    headers: [],
    body: b"",
  })
  assert_eq(page.status, 200)
  assert_eq(page.header("content-type"), Some("text/markdown; charset=utf-8"))
  let skill = @utf8.decode_lossy(page.body)
  assert_eq(skill.has_prefix("---\nname: petstore\n"), true)
  assert_eq(skill.contains("Read this before calling petstore."), true)
  assert_eq(skill.contains("- MCP endpoint: `/mcp`"), true)
  assert_eq(skill.contains("- API description: `/openapi.json`"), true)
  assert_eq(skill.contains("| `get_pets_id` | `GET /pets/{id}` |"), true)
  assert_eq(skill.contains("`id` (path, string, required)"), true)
  assert_eq(skill.contains("`note` (query, string, optional)"), true)
  assert_eq(skill.contains("`body` (JSON body, required)"), true)
}

///|
/// Neither the service nor the skill joins the document: what an agent reads is
/// what a client reads, and offering either does not change it.
async test "offering the API to agents leaves the document alone" {
  let app = petstore()
  let before = app.openapi_json()
  expose(app)
  let after = app.openapi_json()
  assert_eq(after, before)
  let spec = app.handle({
    http_method: "GET",
    path: "/openapi.json",
    query_string: b"",
    headers: [],
    body: b"",
  })
  assert_eq(@utf8.decode_lossy(spec.body).contains("/mcp"), false)
  assert_eq(@utf8.decode_lossy(spec.body).contains("SKILL.md"), false)
}

///|
/// `tags` narrows what is offered, and the parameters left out of the document
/// are left out of the tools.
async test "tags decide which operations an agent is shown" {
  let app = petstore()
  let settings = { ..exposure, tags: ["ops"], }
  expose(app, exposure=settings)
  let client = @client.Client::connect(
    Endpoint::{ app, url: "/mcp", },
    protocol_version="2025-06-18",
  )
  assert_eq(client.list_tools().map(tool => tool.name), ["get_health"])
  client.close()
  let skill = @utf8.decode_lossy(
    app.handle({
      http_method: "GET",
      path: "/SKILL.md",
      query_string: b"",
      headers: [],
      body: b"",
    }).body,
  )
  assert_eq(skill.contains("`get_health`"), true)
  assert_eq(skill.contains("`get_pets_id`"), false)
}

///|
/// Turning either half off leaves nothing at that path.
async test "either half can be left out" {
  let app = petstore()
  let settings = { ..exposure, skill_url: None, }
  expose(app, exposure=settings)
  let asked = app.handle({
    http_method: "GET",
    path: "/SKILL.md",
    query_string: b"",
    headers: [],
    body: b"",
  })
  assert_eq(asked.status, 404)
  let client = @client.Client::connect(
    Endpoint::{ app, url: "/mcp", },
    protocol_version="2025-06-18",
  )
  assert_eq(client.list_tools().length(), 3)
  client.close()
}

///|
/// A call that leaves out an argument the operation requires is refused with the
/// name of that argument, rather than filling the path with `{id}` and coming
/// back as a 404 the agent cannot explain.
async test "a call without a required argument is refused, the argument named" {
  let app = petstore()
  expose(app)
  let client = @client.Client::connect(
    Endpoint::{ app, url: "/mcp", },
    protocol_version="2025-06-18",
  )
  let refused = client.call_tool("get_pets_id")
  assert_eq(refused.is_error, true)
  assert_eq(answer_text(refused).contains("missing id"), true)
  client.close()
}
