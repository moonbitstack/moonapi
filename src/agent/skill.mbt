// The skill an application hands an agent: what the API does, where it answers,
// and what each of its tools takes — written from the same document the pages
// are written from, so the two cannot drift apart.

///|
/// `s` as one table cell: a line break would end the row, and a bar would split
/// the columns.
fn md_cell(s : String) -> String {
  s
  .replace_all(old="|", new="\\|")
  .replace_all(old="\n", new=" ")
  .replace_all(old="\r", new="")
}

///|
/// `s` inside a double quoted YAML scalar.
fn yaml_quoted(s : String) -> String {
  "\"" +
  s.replace_all(old="\\", new="\\\\").replace_all(old="\"", new="\\\"") +
  "\""
}

///|
/// How one argument reads in the table: its name, where it goes, its JSON type,
/// and whether the operation insists on it.
fn argument_cell(p : Param) -> String {
  let kind = match field_of(p.schema, "type") {
    Some(String(t)) => t
    _ => "any"
  }
  let need = if p.required { "required" } else { "optional" }
  "`\{p.name}` (\{p.location}, \{kind}, \{need})"
}

///|
/// The `SKILL.md` of an API (← the shape `docs/skills/<library>/SKILL.md` has,
/// generated instead of written by hand): frontmatter naming it and saying when
/// to read it, then how to reach the API, every tool it offers, and the rules
/// that keep a caller from misreading an answer.
pub fn skill_of(app : @moonapi.App, settings : Exposure) -> String {
  let doc = app.openapi()
  let title = title_of(doc, settings)
  let ops = operations(doc, settings.tags)
  let slug = tool_slug(title, lower=true)
  let name = if slug == "" { "api" } else { slug }
  let about = match field_of(doc, "info") {
    Some(info) =>
      match string_of(info, "description") {
        "" => string_of(info, "summary")
        text => text
      }
    None => ""
  }
  let described = if about == "" {
    "{\{ops.length()}} operations, offered to agents over the Model Context Protocol."
  } else {
    about
  }
  let body = StringBuilder()
  body.write_string(
    "---\nname: \{name}\ndescription: \{yaml_quoted("\{title} over MCP: \{ops.length()} operations, one tool each. Read this before calling \{title}.")}\n---\n\n",
  )
  body.write_string("# \{title}\n\n\{described}\n\n## Connect\n\n")
  match settings.mcp_url {
    Some(url) =>
      body.write_string(
        "- MCP endpoint: `\{url}` — streamable HTTP, one tool per operation.\n",
      )
    None => ()
  }
  match settings.document_url {
    Some(url) => body.write_string("- API description: `\{url}`\n")
    None => ()
  }
  body.write_string("- Server version: \{version_of(doc)}\n")
  match settings.instructions {
    Some(text) => body.write_string("\n\{text}\n")
    None => ()
  }
  body.write_string("\n## Tools\n\n")
  if ops.length() == 0 {
    body.write_string("No operation is offered.\n")
  } else {
    body.write_string(
      "| Tool | Call | Arguments | Summary |\n|:--|:--|:--|:--|\n",
    )
    for op in ops {
      let summary = md_cell(
        if op.summary != "" {
          op.summary
        } else {
          op.description
        },
      )
      let args = StringBuilder()
      let mut listed = false
      for p in op.params {
        if listed {
          args.write_string(" ")
        }
        args.write_string(argument_cell(p))
        listed = true
      }
      if op.body is Some(_) {
        if listed {
          args.write_string(" ")
        }
        let need = if op.body_required { "required" } else { "optional" }
        args.write_string("`body` (JSON body, \{need})")
        listed = true
      }
      if !listed {
        args.write_string("—")
      }
      body.write_string(
        "| `\{op.name}` | `\{op.verb} \{op.path}` | \{args} | \{summary} |\n",
      )
    }
  }
  body.write_string(
    "\n## Working with it\n\n- A tool answers with the response body the API returns, unchanged; a status of 400 or above comes back marked as an error, so read the body before retrying.\n- `path` arguments fill the URL, `query` arguments become the query string, and `body` is sent as JSON.\n- Every tool calls the route in this application, so the answer is the one a client of this API would get.\n",
  )
  body.to_string()
}
