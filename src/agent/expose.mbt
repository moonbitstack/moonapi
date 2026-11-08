// Offering an application to agents: the same document a reader opens as a page,
// served as tools a client calls and as a skill its agent reads before it does.
// The MCP service is mounted like `/docs` is, so an application that serves one
// serves the other at a path it chose.

///|
/// What an application offers agents. `mcp_url` is where the MCP endpoint answers
/// (streamable HTTP), `skill_url` where the skill document is served; `None`
/// leaves that one off.
///
/// `name` is what the tools and the skill call the API — the document's own title
/// when left out. `instructions` is added to the skill and to the MCP server's
/// own instructions, for what a description cannot say. `document_url` is the
/// document the skill points at, when the application publishes one. `tags`
/// limits both to the operations carrying one of them, so an application can
/// show an agent a corner of itself rather than all of it.
pub(all) struct Exposure {
  mcp_url : String?
  skill_url : String?
  name : String?
  instructions : String?
  document_url : String?
  tags : Array[String]
}

///|
/// The offer an application makes unless told otherwise: the MCP endpoint at
/// `/mcp`, the skill at `/SKILL.md`, every documented operation.
pub let exposure : Exposure = {
  mcp_url: Some("/mcp"),
  skill_url: Some("/SKILL.md"),
  name: None,
  instructions: None,
  document_url: None,
  tags: [],
}

///|
/// Offer `app` to agents, in one call (← FastAPI serving `/docs`, but for an
/// agent rather than a person). Every documented operation becomes one MCP tool:
/// its parameters and its body are the tool's arguments, and calling the tool
/// calls the route in-process, through the same ASGI path a server uses, so the
/// answer an agent gets and the answer a client gets are the same bytes.
///
/// The skill served at `skill_url` is a `SKILL.md` for the API: what it is, how
/// to reach it, and every tool with its arguments. The MCP server carries the
/// same document as a resource, so a client that reads resources instead of
/// asking for them finds it there too.
///
/// The tool table is built from the document as it stands at the first request,
/// not at this call, so routes registered after it are still offered.
pub fn expose(app : @moonapi.App, exposure~ : Exposure = exposure) -> Unit {
  let settings = exposure
  if settings.skill_url is Some(url) {
    app.get(
      url,
      _ctx => {
        @http.Response::new(
          200,
          [("content-type", "text/markdown; charset=utf-8")],
          @utf8.encode(skill_of(app, settings)),
        )
      },
      include_in_schema=false,
    )
  }
  if settings.mcp_url is Some(url) {
    app.mount_asgi(url, lazy_service(app, settings))
  }
}

///|
/// The MCP application, built on the first request it answers. An application
/// registers its routes up to the moment it is served, and a tool table built
/// before that would be missing whatever came after.
fn lazy_service(app : @moonapi.App, settings : Exposure) -> @moonasgi.AsgiApp {
  let built : Ref[@moonasgi.AsgiApp?] = Ref(None)
  (scope, receive, send) => {
    let service = match built.val {
      Some(service) => service
      None => {
        let service = service_of(app, settings)
        built.val = Some(service)
        service
      }
    }
    service(scope, receive, send)
  }
}

///|
/// The moonmcp server for `app`'s document, as an ASGI application. It answers at
/// the root of wherever it is mounted, which is why it says `path="/"`: the mount
/// has already taken `/mcp` off the path the client wrote.
fn service_of(app : @moonapi.App, settings : Exposure) -> @moonasgi.AsgiApp {
  let doc = app.openapi()
  let title = title_of(doc, settings)
  let server = @server.Server::new(
    title,
    version=version_of(doc),
    title~,
    instructions?=settings.instructions,
  )
  for op in operations(doc, settings.tags) {
    let (schema, description) = (arguments_schema(op), tool_description(op))
    server.tool_context(
      op.name,
      async fn(args, _ctx) -> @tools.ToolResult {
        let (status, body) = call(app, op, args)
        @tools.ToolResult::new(
          content=[@types.Text(text=body, annotations=None, meta=None)],
          is_error=status >= 400,
        )
      },
      input_schema=schema,
      description~,
    )
  }
  server.resource(
    skill_uri(title),
    () => skill_of(app, settings),
    name="SKILL.md",
    title="The skill of this API",
    description="What this API does and how to call it, for an agent.",
    mime_type="text/markdown",
  )
  server.to_asgi(path="/", docs=None)
}

///|
/// Call one operation the way the route would be called: the path filled from the
/// arguments, the query string from them, the body as JSON, and the request run
/// through the application. What comes back is the status and the body a client
/// would have seen.
async fn call(
  app : @moonapi.App,
  op : Operation,
  args : Map[String, Json],
) -> (Int32, String) {
  let mut path = op.path
  let query = @moonurl.Query::new()
  for p in op.params {
    let value = match args.get(p.name) {
      Some(Null) => None
      given => given
    }
    match value {
      Some(v) =>
        if p.location == "path" {
          path = path.replace_all(
            old="{" + p.name + "}",
            new=@moonurl.escape_text(argument_text(v), kind=@moonurl.Segment),
          )
        } else {
          query.add(p.name, argument_text(v))
        }
      None => ()
    }
  }
  let headers = [("accept", "application/json")]
  let body = match args.get("body") {
    Some(given) if op.body is Some(_) => {
      headers.push(("content-type", "application/json"))
      @utf8.encode(given.stringify())
    }
    _ => Bytes::new(0)
  }
  let resp = app.handle({
    http_method: op.verb,
    path,
    query_string: @utf8.encode(query.encode()),
    headers,
    body,
  })
  (resp.status, @utf8.decode_lossy(resp.body))
}

///|
/// What the tools and the skill call this API: the name given, or the document's
/// title.
fn title_of(doc : Json, settings : Exposure) -> String {
  match settings.name {
    Some(name) => name
    None =>
      match field_of(doc, "info") {
        Some(info) =>
          match string_of(info, "title") {
            "" => "moonapi"
            title => title
          }
        None => "moonapi"
      }
  }
}

///|
fn version_of(doc : Json) -> String {
  match field_of(doc, "info") {
    Some(info) =>
      match string_of(info, "version") {
        "" => "0.0.0"
        version => version
      }
    None => "0.0.0"
  }
}

///|
/// The URI the skill is offered as to an MCP client that reads resources rather
/// than asking: a scheme of ours, so it cannot be mistaken for a file.
fn skill_uri(title : String) -> String {
  let name = tool_slug(title, lower=true)
  "skill://\{if name == "" { "api" } else { name }}/SKILL.md"
}
