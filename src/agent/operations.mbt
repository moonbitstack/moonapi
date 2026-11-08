// What an application shows an agent: the operations of its own document, read
// back out of the JSON an application publishes, so the tools an agent calls and
// the page a person reads are two views of one description.

///|
let tool_methods : Array[String] = [
  "get", "put", "post", "delete", "options", "head", "patch", "trace",
]

///|
/// A parameter an operation takes, in the two places a tool can fill one: the
/// path, or the query string. A header or a cookie is the caller's to set, not
/// the agent's, so a parameter there is not offered as an argument.
priv struct Param {
  name : String
  location : String
  required : Bool
  schema : Json
}

///|
/// One documented operation, as a tool: what to call, what it takes, and what the
/// document says it does.
priv struct Operation {
  verb : String
  path : String
  name : String
  summary : String
  description : String
  params : Array[Param]
  body : Json?
  body_required : Bool
}

///|
/// A member of a JSON object, or `None` when the value is not one or has no such
/// member.
fn field_of(j : Json, key : String) -> Json? {
  match j {
    Object(m) => m.get(key)
    _ => None
  }
}

///|
fn string_of(j : Json, key : String) -> String {
  match field_of(j, key) {
    Some(String(s)) => s
    _ => ""
  }
}

///|
fn flag_of(j : Json, key : String) -> Bool {
  match field_of(j, key) {
    Some(True) => true
    _ => false
  }
}

///|
/// The JSON pointer a `$ref` names, looked up in the document itself. Only a
/// reference into the same document is followed: a tool's schema has to stand on
/// its own, and a remote one would leave the agent with a link it cannot open.
fn pointer(doc : Json, target : String) -> Json? {
  guard target.has_prefix("#/") else { return None }
  let mut here = doc
  for raw in target.exact_view(start=2, end=target.length()).split("/") {
    let key = raw
      .to_owned()
      .replace_all(old="~1", new="/")
      .replace_all(old="~0", new="~")
    match here {
      Object(m) =>
        match m.get(key) {
          Some(next) => here = next
          None => return None
        }
      _ => return None
    }
  }
  Some(here)
}

///|
/// `j` with every local `$ref` replaced by what it names, down to `depth`: a
/// schema that leads back into itself stops being followed rather than growing
/// without end.
fn deref(doc : Json, j : Json, depth : Int32) -> Json {
  if depth > 8 {
    return j
  }
  match j {
    Object(m) =>
      match m.get("$ref") {
        Some(String(target)) =>
          match pointer(doc, target) {
            Some(named) => deref(doc, named, depth + 1)
            None => j
          }
        _ => {
          let out : Map[String, Json] = Map([])
          for k, v in m {
            out[k] = deref(doc, v, depth + 1)
          }
          Json(out)
        }
      }
    Array(items) => Json(items.map(item => deref(doc, item, depth + 1)))
    _ => j
  }
}

///|
/// A name a tool can carry: letters, digits and underscores, one 64 characters
/// at most, which is what the protocol allows.
fn tool_slug(s : String, lower~ : Bool) -> String {
  let out = StringBuilder()
  let mut written = false
  let mut gap = false
  for ch in s {
    let c = if lower { ch.to_ascii_lowercase() } else { ch }
    let kept = (c >= 'a' && c <= 'z') ||
      (c >= 'A' && c <= 'Z') ||
      (c >= '0' && c <= '9')
    if kept {
      out.write_char(c)
      written = true
      gap = false
    } else if !gap && written {
      out.write_char('_')
      gap = true
    }
  }
  let mut name = out.to_string()
  while name.has_suffix("_") {
    name = name.exact_view(start=0, end=name.length() - 1).to_owned()
  }
  if name.length() > 64 {
    name.exact_view(start=0, end=64).to_owned()
  } else {
    name
  }
}

///|
/// The operation's own id when it has one, and the method and path otherwise —
/// either way a name an agent can call.
fn tool_name(op : Json, verb : String, path : String) -> String {
  let named = tool_slug(string_of(op, "operationId"), lower=false)
  if named != "" {
    named
  } else {
    tool_slug(verb + "_" + path, lower=true)
  }
}

///|
/// Whether an operation belongs to one of `tags`; with no tags named, every
/// operation does.
fn wanted(op : Json, tags : Array[String]) -> Bool {
  if tags.length() == 0 {
    return true
  }
  match field_of(op, "tags") {
    Some(Array(own)) =>
      own
      .iter()
      .any(tag => {
        match tag {
          String(name) => tags.contains(name)
          _ => false
        }
      })
    _ => false
  }
}

///|
fn params_of(doc : Json, op : Json) -> Array[Param] {
  let out = []
  let listed = match field_of(op, "parameters") {
    Some(Array(items)) => items
    _ => []
  }
  for entry in listed {
    let p = deref(doc, entry, 0)
    let location = string_of(p, "in")
    let name = string_of(p, "name")
    if name == "" || (location != "path" && location != "query") {
      continue
    }
    out.push({
      name,
      location,
      required: location == "path" || flag_of(p, "required"),
      schema: match field_of(p, "schema") {
        Some(s) => deref(doc, s, 0)
        None => Json::object(Map([]))
      },
    })
  }
  out
}

///|
/// The JSON body an operation takes, and whether it insists on one. A body that
/// is not JSON is not offered: an agent speaks JSON.
fn body_of(doc : Json, op : Json) -> (Json?, Bool) {
  match field_of(op, "requestBody") {
    Some(raw) => {
      let request = deref(doc, raw, 0)
      let schema = match field_of(request, "content") {
        Some(Object(content)) =>
          match content.get("application/json") {
            Some(media) =>
              match field_of(media, "schema") {
                Some(s) => Some(deref(doc, s, 0))
                None => None
              }
            None => None
          }
        _ => None
      }
      (schema, flag_of(request, "required"))
    }
    None => (None, false)
  }
}

///|
/// Every documented operation of `doc`, in the order the document lists them.
fn operations(doc : Json, tags : Array[String]) -> Array[Operation] {
  let out = []
  let paths = match field_of(doc, "paths") {
    Some(Object(m)) => m
    _ => Map([])
  }
  for path, item in paths {
    for verb in tool_methods {
      let op = match field_of(item, verb) {
        Some(o) => o
        None => continue
      }
      guard op is Object(_) else { continue }
      if !wanted(op, tags) {
        continue
      }
      let (body, body_required) = body_of(doc, op)
      out.push({
        verb: verb.to_upper(),
        path,
        name: tool_name(op, verb, path),
        summary: string_of(op, "summary"),
        description: string_of(op, "description"),
        params: params_of(doc, op),
        body,
        body_required,
      })
    }
  }
  out
}

///|
/// The schema of a tool's arguments: the parameters where they are called from,
/// the body under `body`, and what the operation requires of them.
fn arguments_schema(op : Operation) -> Json {
  let properties : Map[String, Json] = Map([])
  let required = []
  for p in op.params {
    properties[p.name] = p.schema
    if p.required {
      required.push(Json(p.name))
    }
  }
  if op.body is Some(schema) {
    properties["body"] = schema
    if op.body_required {
      required.push(Json("body"))
    }
  }
  let schema : Map[String, Json] = {
    "type": Json::string("object"),
    "properties": Json(properties),
  }
  if required.length() > 0 {
    schema["required"] = Json(required)
  }
  Json(schema)
}

///|
/// What a tool says about itself: the operation's summary, then its longer
/// description when it has one, and the call it makes when the summary alone
/// would leave an agent guessing.
fn tool_description(op : Operation) -> String {
  let out = StringBuilder()
  let head = if op.summary != "" { op.summary } else { op.name }
  out.write_string(head)
  if op.description != "" {
    out.write_string("\n\n")
    out.write_string(op.description)
  }
  out.write_string("\n\nCalls \{op.verb} \{op.path}.")
  out.to_string()
}

///|
/// The text an argument travels as: a string is itself, anything else is the
/// JSON it was given as, which is how a number, a flag or a nested value is
/// spelled in a query string.
fn argument_text(v : Json) -> String {
  match v {
    String(s) => s
    Null => ""
    _ => v.stringify()
  }
}
