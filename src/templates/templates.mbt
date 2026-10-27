///|
/// A context processor (← Starlette's `context_processors`): the request in, the
/// names every template rendered for it can use.
pub type Processor = (@ctx.Context) -> Map[String, Json]

///|
/// Templates rendered into HTML responses (← Starlette's `Jinja2Templates`), over
/// a moonpug environment, which holds the loader, the settings, the filters and
/// the globals.
///
/// Every template sees `request`: its `method`, `url`, `path`, `root_path`, the
/// first value of each `query` parameter, the `headers` and the path `params`.
/// Given `url_for`, it also sees `url_for(name, **params)`, which resolves a named
/// route; pass `(name, params) => app.url_for(name, params~)`.
pub struct Templates {
  env : @moonpug.Env
  priv processors : Array[Processor]
  priv url_for : ((String, Map[String, String]) -> String?)?
}

///|
pub fn Templates::new(
  env : @moonpug.Env,
  processors~ : Array[Processor] = [],
  url_for? : (String, Map[String, String]) -> String?,
) -> Templates {
  { env, processors, url_for, }
}

///|
/// Render the template `name` into a response (← Starlette's
/// `TemplateResponse`).
///
/// A template's names come in three layers: `request`, then what each processor
/// returns in order, then `context`. Where a later layer names what an earlier
/// one did, the later one wins by default, the call being the most specific of
/// the three. `wins=Base` keeps the processors' and ours instead; `clash` can
/// abort or hand the decision to a callback, which receives the processors'
/// names and the merged ones. `url_for` is added last, unless a layer already
/// named it.
///
/// A template that does not load or does not render raises `Refused`, which the
/// app answers with a `500` like any other error a handler raises.
pub fn Templates::response(
  self : Templates,
  ctx : @ctx.Context,
  name : String,
  context~ : Map[String, Json] = Map([]),
  status~ : Int32 = 200,
  media_type~ : String = "text/html; charset=utf-8",
  wins~ : @jwt.Wins = Extra,
  clash~ : @jwt.OnClash[Map[String, Json]] = Ignore,
) -> @moonasgi.Response raise @spec.Refused {
  let base : Map[String, Json] = { "request": request_json(ctx) }
  for processor in self.processors {
    for k, v in processor(ctx) {
      base[k] = v
    }
  }
  let merged = base.copy()
  let mut clashed = false
  for k, v in context {
    if merged.contains(k) {
      clashed = true
      if wins is Extra {
        merged[k] = v
      }
    } else {
      merged[k] = v
    }
  }
  let names = if clashed {
    match clash {
      Ignore => merged
      Panic => abort("templates: `context` names what a processor already did")
      Handle(decide) => decide(base, merged)
    }
  } else {
    merged
  }
  let values : Map[String, @spec.Value] = Map([])
  for k, v in names {
    values[k] = @spec.Value::of_json(v)
  }
  if self.url_for is Some(resolve) && !values.contains("url_for") {
    values["url_for"] = @spec.Value::func("url_for", (call, args, kwargs) => {
      guard args is [route] else {
        raise @spec.invalid("url_for takes the route name, then its parameters")
      }
      let route = call.text(route)
      let params : Map[String, String] = Map([])
      for k, v in kwargs {
        params[k] = call.text(v)
      }
      match resolve(route, params) {
        Some(path) => Text(path)
        None =>
          raise @spec.invalid(
            "url_for: no route named `\{route}` takes these parameters",
          )
      }
    })
  }
  let page = self.env.template(name).render_values(values)
  @moonasgi.Response::new(
    status,
    [("content-type", media_type)],
    @utf8.encode(page),
  )
}

///|
/// What a template sees of the request.
fn request_json(ctx : @ctx.Context) -> Json {
  let r = ctx.request
  let query_text = @utf8.decode_lossy(r.query_string[:])
  let query : Map[String, Json] = Map([])
  let pairs = @moonurl.Query::decode(r.query_string[:]).entries() catch {
    _ => []
  }
  for pair in pairs {
    if !query.contains(pair.0) {
      query[pair.0] = Json(pair.1)
    }
  }
  let headers : Map[String, Json] = Map([])
  for h in r.headers {
    if !headers.contains(h.0) {
      headers[h.0] = Json(h.1)
    }
  }
  let params : Map[String, Json] = Map([])
  for k, v in ctx.params {
    params[k] = Json(v)
  }
  let path = ctx.scope.root_path + r.path
  {
    "method": Json(r.http_method),
    "url": Json(
      if query_text.is_empty() {
        path
      } else {
        path + "?" + query_text
      },
    ),
    "path": Json(r.path),
    "root_path": Json(ctx.scope.root_path),
    "query": Json(query),
    "headers": Json(headers),
    "params": Json(params),
  }
}
