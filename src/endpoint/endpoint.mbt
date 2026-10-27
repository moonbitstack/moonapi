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
pub fn loc_str(l : ParamLoc) -> String {
  match l {
    InPath => "path"
    InQuery => "query"
    InHeader => "header"
    InCookie => "cookie"
  }
}

///|
/// A named example of a value (the OpenAPI Example Object, ← FastAPI's
/// `openapi_examples`): a `summary` and a `description` for the reader, and
/// either the `value` itself or an `external_value` URL where it can be fetched.
/// Documentation viewers offer the examples of a parameter or a body by name.
pub(all) struct Example {
  summary : String
  description : String
  value : Json?
  external_value : String
} derive(Eq)

///|
pub fn Example::new(
  value? : Json,
  summary~ : String = "",
  description~ : String = "",
  external_value~ : String = "",
) -> Example {
  { summary, description, value, external_value, }
}

///|
/// The Example Object for `example`. `value` and `externalValue` exclude each
/// other, so a value given in both forms is written as the value.
pub fn Example::to_json(self : Example) -> Json {
  let m : Map[String, Json] = Map([])
  if self.summary != "" {
    m["summary"] = Json(self.summary)
  }
  if self.description != "" {
    m["description"] = Json(self.description)
  }
  match self.value {
    Some(v) => m["value"] = v
    None =>
      if self.external_value != "" {
        m["externalValue"] = Json(self.external_value)
      }
  }
  Json(m)
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
  schema : @schema.Schema
  required : Bool
  description : String
  constraints : Array[@schema.Constraint]
  default : Json?
  alias_ : String
  examples : Map[String, Example]
} derive(Eq)

///|
/// Build a parameter descriptor. `schema` defaults to a string and `required` to
/// `true`. `constraints` are the Pydantic-style bounds FastAPI reads off a
/// `Query(ge=…, max_length=…)` — emitted into the parameter's documented schema
/// *and* enforced on the inbound value. `default` is emitted and makes the
/// parameter optional, since a value that has one is never missing. `alias` is
/// the name the parameter travels under when that differs from the one the code
/// calls it (← `Query(alias="item-query")`). `examples` are offered by name in
/// the documentation (← `Query(openapi_examples=…)`).
pub fn Param::new(
  name : String,
  loc : ParamLoc,
  schema~ : @schema.Schema = SStr,
  required~ : Bool = true,
  description~ : String = "",
  constraints~ : Array[@schema.Constraint] = [],
  default? : Json,
  alias_~ : String = "",
  examples~ : Map[String, Example] = Map([]),
) -> Param {
  {
    name,
    loc,
    schema,
    required,
    description,
    constraints,
    default,
    alias_,
    examples,
  }
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
/// A single response descriptor: the HTTP `status`, a human `description`, an
/// optional body `schema` (`None` for an empty body, e.g. `204`), and named
/// `examples` of that body.
pub(all) struct ResponseSpec {
  status : Int32
  description : String
  body : @schema.Schema?
  examples : Map[String, Example]
} derive(Eq)

///|
/// Build a response descriptor. `description` defaults to `"OK"` and there is no
/// body unless one is given.
pub fn ResponseSpec::new(
  status : Int32,
  description~ : String = "OK",
  body? : @schema.Schema,
  examples~ : Map[String, Example] = Map([]),
) -> ResponseSpec {
  { status, description, body, examples, }
}

///|
/// The runtime endpoint descriptor a route can carry — the one first-class value
/// that replaces FastAPI reading a handler's signature. Walked once for the
/// OpenAPI operation (parameters + `requestBody` + `responses`, with every named
/// object hoisted into `components/schemas`) and for request validation.
pub(all) struct Endpoint {
  params : Array[Param]
  request_body : @schema.Schema?
  request_required : Bool
  // Named examples of the request body (← `Body(openapi_examples=…)`).
  request_examples : Map[String, Example]
  responses : Array[ResponseSpec]
} derive(Eq)

///|
/// Build an endpoint descriptor. Everything is optional: a bare `Endpoint::new()`
/// describes an endpoint with no parameters, no body, and (on emit) a default
/// `200 OK` response.
pub fn Endpoint::new(
  params~ : Array[Param] = [],
  request_body? : @schema.Schema,
  request_required~ : Bool = true,
  request_examples~ : Map[String, Example] = Map([]),
  responses~ : Array[ResponseSpec] = [],
) -> Endpoint {
  { params, request_body, request_required, request_examples, responses, }
}

// -- OpenAPI emission for an endpoint -----------------------------------------

///|
pub extend Example with Eq::{not_equal, equal}

///|
pub extend ParamLoc with Eq::{not_equal, equal}

///|
pub extend Param with Eq::{not_equal, equal}

///|
pub extend ResponseSpec with Eq::{not_equal, equal}

///|
pub extend Endpoint with Eq::{not_equal, equal}
