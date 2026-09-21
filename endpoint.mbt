///|
/// Where a parameter is carried, the OpenAPI `in` locations: the path, the query
/// string, a header, or a cookie.
pub(all) enum ParamLoc {
  InPath
  InQuery
  InHeader
  InCookie
} derive(Eq)

///|
/// The OpenAPI `in` string for a location.
fn loc_str(l : ParamLoc) -> String {
  match l {
    InPath => "path"
    InQuery => "query"
    InHeader => "header"
    InCookie => "cookie"
  }
}

///|
/// A single request parameter descriptor: its `name`, `loc`ation, scalar
/// `schema`, whether it is `required`, an optional `description`, its value
/// `constraints`, the `default` that stands in when the request omits it, and
/// the `alias` it travels under on the wire. Path parameters are always required
/// (OpenAPI requires it); the constructor keeps the caller's value but
/// validation treats path params as mandatory.
pub(all) struct Param {
  name : String
  loc : ParamLoc
  schema : Schema
  required : Bool
  description : String
  constraints : Array[Constraint]
  default : Json?
  alias_ : String
} derive(Eq)

///|
/// Build a parameter descriptor. `schema` defaults to a string and `required` to
/// `true`. `constraints` are the Pydantic-style bounds FastAPI reads off a
/// `Query(ge=…, max_length=…)` — emitted into the parameter's documented schema
/// *and* enforced on the inbound value. `default` is emitted and makes the
/// parameter optional, since a value that has one is never missing. `alias` is
/// the name the parameter travels under when that differs from the one the code
/// calls it (← `Query(alias="item-query")`).
pub fn Param::new(
  name : String,
  loc : ParamLoc,
  schema? : Schema = SStr,
  required? : Bool = true,
  description? : String = "",
  constraints? : Array[Constraint] = [],
  default? : Json,
  alias_? : String = "",
) -> Param {
  { name, loc, schema, required, description, constraints, default, alias_, }
}

///|
/// The name this parameter travels under: its `alias` when it has one, else its
/// own name. This is what is read off the request, what the document calls it,
/// and what a validation error's `loc` points at — all three being the client's
/// view of the parameter.
pub fn Param::key(self : Param) -> String {
  if self.alias_ == "" {
    self.name
  } else {
    self.alias_
  }
}

///|
/// Whether a request must carry this parameter. One with a default never must —
/// its absence is answered by the default, exactly as a Python default argument
/// is.
pub fn Param::is_required(self : Param) -> Bool {
  self.required && self.default is None
}

///|
/// A single response descriptor: the HTTP `status`, a human `description`, and an
/// optional body `schema` (`None` for an empty body, e.g. `204`).
pub(all) struct ResponseSpec {
  status : Int
  description : String
  body : Schema?
} derive(Eq)

///|
/// Build a response descriptor. `description` defaults to `"OK"` and there is no
/// body unless one is given.
pub fn ResponseSpec::new(
  status : Int,
  description? : String = "OK",
  body? : Schema,
) -> ResponseSpec {
  { status, description, body, }
}

///|
/// The runtime endpoint descriptor a route can carry — the one first-class value
/// that replaces FastAPI reading a handler's signature. Walked once for the
/// OpenAPI operation (parameters + `requestBody` + `responses`, with every named
/// object hoisted into `components/schemas`) and for request validation.
pub(all) struct Endpoint {
  params : Array[Param]
  request_body : Schema?
  request_required : Bool
  responses : Array[ResponseSpec]
} derive(Eq)

///|
/// Build an endpoint descriptor. Everything is optional: a bare `Endpoint::new()`
/// describes an endpoint with no parameters, no body, and (on emit) a default
/// `200 OK` response.
pub fn Endpoint::new(
  params? : Array[Param] = [],
  request_body? : Schema,
  request_required? : Bool = true,
  responses? : Array[ResponseSpec] = [],
) -> Endpoint {
  { params, request_body, request_required, responses, }
}

// -- OpenAPI emission for an endpoint -----------------------------------------

///|
/// One parameter as its OpenAPI parameter object for `version`. In Swagger 2.0 a
/// scalar type sits inline; in OpenAPI 3.x it lives under `schema`.
fn param_json(
  p : Param,
  defs : Map[String, Json],
  version : OpenApiVersion,
) -> Json {
  let m : Map[String, Json] = Map([
    ("name", p.key().to_json()),
    ("in", loc_str(p.loc).to_json()),
    ("required", p.is_required().to_json()),
  ])
  if p.description != "" {
    m["description"] = p.description.to_json()
  }
  match version {
    // Swagger 2.0 puts a scalar's type and its constraint keywords on the
    // parameter object itself — there is no `schema` to hang them off.
    Swagger20 =>
      match scalar_name(p.schema) {
        Some(t) => {
          m["type"] = t.to_json()
          merge_into(m, param_facets(p, version))
        }
        None =>
          m["schema"] = param_facets_on(
            emit_schema(p.schema, defs, version),
            p,
            version,
          )
      }
    _ =>
      m["schema"] = param_facets_on(
        emit_schema(p.schema, defs, version),
        p,
        version,
      )
  }
  m.to_json()
}

///|
/// `j` with the parameter's constraints and default written into it.
fn param_facets_on(j : Json, p : Param, version : OpenApiVersion) -> Json {
  let with_c = with_constraints(j, p.constraints, version)
  match p.default {
    Some(d) => with_key(with_c, "default", d)
    None => with_c
  }
}

///|
/// Just the keywords a parameter's constraints and default contribute, as a bare
/// object — for the Swagger 2.0 shape, which merges them into the parameter.
fn param_facets(p : Param, version : OpenApiVersion) -> Json {
  let empty : Map[String, Json] = Map([])
  param_facets_on(empty.to_json(), p, version)
}

///|
/// Attach the request body of an endpoint to an operation object `op`. OpenAPI
/// 3.x uses a `requestBody` with a media-type map; Swagger 2.0 uses an
/// `in: body` parameter, so it is appended to `op`'s `parameters`.
fn attach_request_body(
  op : Map[String, Json],
  body : Schema,
  required : Bool,
  defs : Map[String, Json],
  version : OpenApiVersion,
) -> Unit {
  match version {
    Swagger20 => {
      let bp : Map[String, Json] = Map([
        ("name", "body".to_json()),
        ("in", "body".to_json()),
        ("required", required.to_json()),
        ("schema", emit_schema(body, defs, version)),
      ])
      let existing : Array[Json] = match op.get("parameters") {
        Some(Array(a)) => a
        _ => []
      }
      existing.push(bp.to_json())
      op["parameters"] = existing.to_json()
    }
    _ => {
      let media : Map[String, Json] = Map([
        ("schema", emit_schema(body, defs, version)),
      ])
      let content : Map[String, Json] = Map([
        ("application/json", media.to_json()),
      ])
      let rb : Map[String, Json] = Map([
        ("required", required.to_json()),
        ("content", content.to_json()),
      ])
      op["requestBody"] = rb.to_json()
    }
  }
}

///|
/// One response as its OpenAPI response object. OpenAPI 3.x nests the body schema
/// under `content."application/json".schema`; Swagger 2.0 puts it directly under
/// `schema`.
fn response_json(
  rs : ResponseSpec,
  defs : Map[String, Json],
  version : OpenApiVersion,
) -> Json {
  let m : Map[String, Json] = Map([("description", rs.description.to_json())])
  match rs.body {
    Some(body) =>
      match version {
        Swagger20 => m["schema"] = emit_schema(body, defs, version)
        _ => {
          let media : Map[String, Json] = Map([
            ("schema", emit_schema(body, defs, version)),
          ])
          let content : Map[String, Json] = Map([
            ("application/json", media.to_json()),
          ])
          m["content"] = content.to_json()
        }
      }
    None => ()
  }
  m.to_json()
}

///|
/// Fill the operation object `op` from an endpoint descriptor for `version`,
/// hoisting named schemas into `defs`. Emits `parameters`, `requestBody` (or a
/// body parameter in 2.0), and `responses`; an endpoint with no declared
/// responses gets a default `OK` under `ok_status`, which is the route's
/// `status_code` or `200`.
fn emit_endpoint(
  op : Map[String, Json],
  ep : Endpoint,
  defs : Map[String, Json],
  version : OpenApiVersion,
  ok_status : Int,
) -> Unit {
  let params : Array[Json] = []
  for p in ep.params {
    params.push(param_json(p, defs, version))
  }
  if params.length() > 0 {
    op["parameters"] = params.to_json()
  }
  match ep.request_body {
    Some(body) =>
      attach_request_body(op, body, ep.request_required, defs, version)
    None => ()
  }
  let specs = if ep.responses.length() > 0 {
    ep.responses
  } else {
    [ResponseSpec::new(ok_status)]
  }
  let responses : Map[String, Json] = Map([])
  for rs in specs {
    responses[rs.status.to_string()] = response_json(rs, defs, version)
  }
  op["responses"] = responses.to_json()
}

///|
pub extend ParamLoc with Eq::{not_equal, equal}

///|
pub extend Param with Eq::{not_equal, equal}

///|
pub extend ResponseSpec with Eq::{not_equal, equal}

///|
pub extend Endpoint with Eq::{not_equal, equal}
