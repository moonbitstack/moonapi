///|
/// Validate an inbound request `ctx` against this endpoint descriptor: every
/// declared parameter (path / query / header / cookie) plus the JSON request
/// body, all off the same descriptor tree that emits the OpenAPI operation.
/// Returns the accumulated errors — an empty array means the request conforms,
/// otherwise pass them to `unprocessable` for a FastAPI-shaped `422`.
pub fn Endpoint::validate(
  self : Endpoint,
  ctx : @ctx.Context,
) -> Array[@schema.ValidationError] {
  let errs : Array[@schema.ValidationError] = []
  for p in self.params {
    // The wire name, which is the alias when there is one — what the client
    // sent, what the document promised, and what an error should point at.
    let key = p.key()
    let raw = match p.loc {
      InPath => ctx.param(key)
      InQuery => ctx.query(key)
      InHeader => ctx.request.header(key)
      InCookie => ctx.cookie(key)
    }
    match raw {
      None =>
        if p.is_required() {
          errs.push(@schema.ValidationError::missing([loc_str(p.loc), key]))
        }
      Some(v) => {
        let loc = [loc_str(p.loc), key]
        validate_scalar_str(p.schema, v, loc, errs)
        // Constraints see the value as its declared scalar, so a `ge` on an
        // integer parameter compares numbers rather than text.
        @schema.check_constraints(
          scalar_json(p.schema, v),
          p.constraints,
          loc,
          errs,
        )
      }
    }
  }
  match self.request_body {
    Some(body) =>
      match ctx.body_json() {
        None =>
          if self.request_required {
            errs.push(@schema.ValidationError::missing(["body"]))
          }
        Some(j) => @schema.validate_schema(body, j, ["body"], errs)
      }
    None => ()
  }
  errs
}

///|
/// Validate a raw string parameter `v` (query/path/header/cookie values always
/// arrive as text) against the declared scalar `schema`, appending a parse error
/// to `errs` when it cannot represent that scalar. Strings always pass; integers
/// and booleans are checked; floats are accepted (no false negatives here).
fn validate_scalar_str(
  schema : @schema.Schema,
  v : String,
  loc : Array[String],
  errs : Array[@schema.ValidationError],
) -> Unit {
  match schema {
    SInt =>
      match @schema.parse_int(v) {
        Some(_) => ()
        None =>
          errs.push(
            @schema.ValidationError::type_error(
              loc, "int_parsing", "Input should be a valid integer, unable to parse string as an integer",
            ),
          )
      }
    SBool =>
      if !(v == "true" ||
        v == "false" ||
        v == "1" ||
        v == "0" ||
        v == "True" ||
        v == "False") {
        errs.push(
          @schema.ValidationError::type_error(
            loc, "bool_parsing", "Input should be a valid boolean, unable to interpret input",
          ),
        )
      }
    SEnum(base, values) =>
      if !@schema.enum_member(values, scalar_json(base, v)) {
        errs.push(
          @schema.ValidationError::type_error(
            loc,
            "enum",
            "Input should be " + @schema.enum_expected(values),
          ),
        )
      }
    // A wrapper does not change what the text has to parse as: a supplied value
    // for a nullable or formatted parameter is still checked against the base.
    SNullable(inner) => validate_scalar_str(inner, v, loc, errs)
    SFormat(base, _) => validate_scalar_str(base, v, loc, errs)
    _ => ()
  }
}

///|
/// Coerce a raw string parameter to the `Json` shape its declared scalar `base`
/// carries, so an enum-member comparison sees like-typed values (a `1` path
/// segment against an integer-valued member). Unparseable input stays a string
/// and simply fails membership, as any non-member does.
fn scalar_json(base : @schema.Schema, v : String) -> Json {
  match base {
    SInt =>
      match @schema.parse_int(v) {
        Some(n) => Json(n)
        None => Json(v)
      }
    SBool =>
      match v {
        "true" | "True" | "1" => Json(true)
        "false" | "False" | "0" => Json(false)
        _ => Json(v)
      }
    SNullable(inner) => scalar_json(inner, v)
    SFormat(base, _) => scalar_json(base, v)
    _ => Json(v)
  }
}
