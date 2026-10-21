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
  schema~ : @schema.Schema = SStr,
  required~ : Bool = true,
  description~ : String = "",
  constraints~ : Array[@schema.Constraint] = [],
  default? : Json,
  alias_~ : String = "",
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
  status : Int32
  description : String
  body : @schema.Schema?
} derive(Eq)

///|
/// Build a response descriptor. `description` defaults to `"OK"` and there is no
/// body unless one is given.
pub fn ResponseSpec::new(
  status : Int32,
  description~ : String = "OK",
  body? : @schema.Schema,
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
  request_body : @schema.Schema?
  request_required : Bool
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
  responses~ : Array[ResponseSpec] = [],
) -> Endpoint {
  { params, request_body, request_required, responses, }
}

// -- OpenAPI emission for an endpoint -----------------------------------------

///|
pub extend ParamLoc with Eq::{not_equal, equal}

///|
pub extend Param with Eq::{not_equal, equal}

///|
pub extend ResponseSpec with Eq::{not_equal, equal}

///|
pub extend Endpoint with Eq::{not_equal, equal}
