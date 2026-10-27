///|
/// `#app.<verb>(path, ...)` and `#router.<verb>(path, ...)` on free functions,
/// turned into `register(app)` and `register_router(router)`.
priv struct Routes {}

///|
impl @gen.Generator for Routes with fn name(_) {
  "moonapi routes"
}

///|
/// The constructor of `@moonapi.Method` for `m`.
fn ctor(m : @method.Method) -> String {
  match m {
    Get => "Get"
    Head => "Head"
    Post => "Post"
    Put => "Put"
    Delete => "Delete"
    Connect => "Connect"
    Options => "Options"
    Trace => "Trace"
    Patch => "Patch"
    Other(token) => "Other(" + @quote.string(token).to_string() + ")"
  }
}

///|
/// Where `attr` is written, as `file:line:column`.
fn at(attr : @attribute.Attribute, file : String) -> String {
  "\{file}:\{attr.loc.start.lnum}:\{attr.loc.start.column()}"
}

///|
/// The arguments an annotation takes. Only what an annotation can spell is
/// here: strings, booleans and repeated strings.
fn spec(name : String, kind : String) -> @attr.Spec {
  let base = @attr.Spec::new(name)
  let base = if kind == "route" { base.positional("method", Str) } else { base }
  let base = base.positional("path", Str)
  if kind == "websocket" {
    return base.optional("name", Str).many("dependencies", Str)
  }
  base
  .optional("summary", Str)
  .optional("description", Str)
  .optional("operation_id", Str)
  .optional("name", Str)
  .optional("status_code", Str)
  .optional("deprecated", Bool)
  .optional("include_in_schema", Bool)
  .optional("validate", Bool)
  .many("tags", Str)
  .many("dependencies", Str)
}

///|
fn quoted(xs : Array[String]) -> String {
  "[" + xs.map(x => @quote.string(x).to_string()).join(", ") + "]"
}

///|
/// The labelled arguments after the handler, in the order `App::route` lists them.
fn options(args : @attr.Args, where_ : String) -> Array[String] raise {
  let out = []
  for key in ["summary", "description"] {
    if args.str(key) is Some(v) {
      out.push(key + "=" + @quote.string(v).to_string())
    }
  }
  let tags = args.strs("tags")
  if !tags.is_empty() {
    out.push("tags=" + quoted(tags))
  }
  if args.bool("deprecated") is Some(v) {
    out.push("deprecated=\{v}")
  }
  if args.str("operation_id") is Some(v) {
    out.push("operation_id=" + @quote.string(v).to_string())
  }
  if args.str("status_code") is Some(v) {
    guard v is [_, ..] &&
      v.iter().all(c => c is ('0'..<='9')) &&
      v.length() <= 3 else {
      fail("\{where_}: status_code is a number, not \"\{v}\"")
    }
    out.push("status_code=" + v)
  }
  if args.str("name") is Some(v) {
    out.push("name=" + @quote.string(v).to_string())
  }
  let deps = args.strs("dependencies")
  if !deps.is_empty() {
    out.push("dependencies=" + quoted(deps))
  }
  for key in ["include_in_schema", "validate"] {
    if args.bool(key) is Some(v) {
      out.push("\{key}=\{v}")
    }
  }
  out
}

///|
/// The statement registering `handler` under `attr` on `target` (`app` or
/// `router`). A second parameter gets the request's background tasks, a `Stream`
/// return streams, anything else answers once.
fn statement(
  target : String,
  attr : @attribute.Attribute,
  handler : String,
  params : Int32,
  returns : String?,
  file : String,
) -> String raise {
  let where_ = at(attr, file)
  guard! @attr.name_of(attr) is Some(name)
  let kind = name[target.length() + 1:].to_owned()
  let verb = match kind {
    "get" => Some(@method.Get)
    "post" => Some(Post)
    "put" => Some(Put)
    "patch" => Some(Patch)
    "delete" => Some(Delete)
    "head" => Some(Head)
    "options" => Some(Options)
    "trace" => Some(Trace)
    "route" | "websocket" => None
    _ => fail("\{where_}: `#\{name}` is not a route annotation")
  }
  let args = spec(name, kind).bind(attr)
  guard! args.str("path") is Some(path)
  let path = @quote.string(path).to_string()
  if kind == "websocket" {
    let parts = [path, "ws => \{handler}(ws)"]
    if args.str("name") is Some(v) {
      parts.push("name=" + @quote.string(v).to_string())
    }
    let deps = args.strs("dependencies")
    if !deps.is_empty() {
      parts.push("dependencies=" + quoted(deps))
    }
    return "\{target}.websocket(\{parts.join(", ")})"
  }
  let m = match verb {
    Some(m) => m
    None => {
      guard! args.str("method") is Some(name)
      @method.Method::of(name) catch {
        Token(_) => fail("\{where_}: `\{name}` is not a method name")
      }
    }
  }
  let call = if returns is Some(t) && t.contains("Stream") {
    "route_stream"
  } else {
    "route"
  }
  // Through a closure: a handler is async, and a named function that is not
  // async is only taken where one is expected inside a closure.
  let wrapped = if params == 2 {
    "ctx => \{handler}(ctx, ctx.background)"
  } else {
    "ctx => \{handler}(ctx)"
  }
  let parts = [ctor(m), path, wrapped, ..options(args, where_)]
  "\{target}.\{call}(\{parts.join(", ")})"
}

///|
impl @gen.Generator for Routes with fn generate(_, decls) {
  let lines : Map[String, Array[String]] = { "app": [], "router": [] }
  for decl in decls {
    for target in ["app", "router"] {
      let found = @attr.under(decl.attrs(), target)
      guard found is [first, ..] else { continue }
      guard decl is Func(owner=None, name~, params~, returns~, file~, ..) else {
        let file = match decl {
          Struct(file~, ..)
          | Enum(file~, ..)
          | Func(file~, ..)
          | Other(file~, ..) => file
        }
        fail("\{at(first, file)}: `#\{target}.*` goes on a free function")
      }
      for attr in found {
        lines[target].push(
          statement(target, attr, name, params.length(), returns, file),
        )
      }
    }
  }
  let out = []
  if !lines["app"].is_empty() {
    out.push(register("register", "app", "App", lines["app"]))
  }
  if !lines["router"].is_empty() {
    out.push(register("register_router", "router", "Router", lines["router"]))
  }
  @quote.join(out)
}

///|
fn register(
  fn_name : String,
  param : String,
  ty : String,
  lines : Array[String],
) -> @quote.Code raise {
  let source =
    #|pub fn $name($param : @moonapi.$T) -> Unit {
    #|  $lines*
    #|}
  @quote.items(source)
  .set("name", @quote.ident(fn_name))
  .set("param", @quote.ident(param))
  .set("T", @quote.ident(ty))
  .splice("lines", lines.map(l => @quote.expr(l).render()))
  .render()
}
