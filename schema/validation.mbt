///|
/// How much of a query string is a query string.
///
/// A thousand parameters is what `qs` allows Express by default, and far past
/// anything a link carries; sixty-four kilobytes for one value is well past the
/// eight the common servers allow a whole request line. Beyond either, the
/// request is an attempt to make the server allocate.
///
/// An endpoint that genuinely takes more says so:
/// `ctx.query("tag", limits=@mime.Limits::new(parts=100000))`.
pub let query_limits : @mime.Limits = { parts: 1000, part_size: 1 << 16, }

///|
/// Parse a base-10 integer, `None` if `s` is not a well-formed integer literal
/// (optional leading `+`/`-`, then one or more ASCII digits, nothing else).
///
/// Not core's `@strconv.parse_int`: that one also takes `0x` prefixes and
/// underscores, which a query or path parameter must not quietly accept.
pub fn parse_int(s : String) -> Int32? {
  let n = s.length()
  if n == 0 {
    return None
  }
  let mut i = 0
  let mut neg = false
  let first = s[0].to_int()
  if first == 0x2D {
    neg = true
    i = 1
  } else if first == 0x2B {
    i = 1
  }
  if i >= n {
    return None
  }
  let mut acc = 0
  while i < n {
    let c = s[i].to_int()
    if c < 0x30 || c > 0x39 {
      return None
    }
    acc = acc * 10 + (c - 0x30)
    i = i + 1
  }
  Some(if neg { -acc } else { acc })
}

///|
/// One entry in a `422` response's `detail` array, mirroring FastAPI /
/// pydantic v2: where the error is (`loc`, e.g. `["query", "q"]`), a human
/// `msg`, and a machine `kind` (serialised as the JSON key `type`).
pub(all) struct ValidationError {
  loc : Array[String]
  msg : String
  kind : String
}

///|
/// The canonical "a required parameter was not supplied" error located at
/// `loc`, matching FastAPI's `{"type": "missing", "msg": "Field required"}`.
pub fn ValidationError::missing(loc : Array[String]) -> ValidationError {
  { loc, msg: "Field required", kind: "missing", }
}

///|
/// A type/parse error located at `loc`, e.g. `kind = "int_parsing"` with the
/// matching pydantic message — the shape FastAPI reports for a value of the
/// wrong type.
pub fn ValidationError::type_error(
  loc : Array[String],
  kind : String,
  msg : String,
) -> ValidationError {
  { loc, msg, kind, }
}

///|
/// `loc` with the segments of a JSON Pointer appended, `~1` and `~0` undone.
fn pointer_loc(loc : Array[String], pointer : String) -> Array[String] {
  let out : Array[String] = [..loc]
  if pointer == "" {
    return out
  }
  for segment in pointer[1:].split("/") {
    out.push(
      segment
      .to_owned()
      .replace_all(old="~1", new="/")
      .replace_all(old="~0", new="~"),
    )
  }
  out
}

///|
/// `loc` with `seg` appended, as a fresh array so sibling error paths never
/// share and mutate one another.
fn loc_push(loc : Array[String], seg : String) -> Array[String] {
  let out : Array[String] = []
  for x in loc {
    out.push(x)
  }
  out.push(seg)
  out
}

///|
/// Render one validation error as its JSON object.
pub fn ValidationError::to_json(self : ValidationError) -> Json {
  let m : Map[String, Json] = Map([
    ("type", Json(self.kind)),
    ("loc", Json(self.loc)),
    ("msg", Json(self.msg)),
  ])
  Json(m)
}

///|
/// The `{"detail": [ ... ]}` body FastAPI returns when request validation
/// fails, built from a list of `ValidationError`s.
pub fn validation_error_body(errors : Array[ValidationError]) -> Json {
  let detail : Array[Json] = []
  for e in errors {
    detail.push(e.to_json())
  }
  let doc : Map[String, Json] = Map([("detail", Json(detail))])
  Json(doc)
}

///|
/// A `422 Unprocessable Entity` response whose `application/json` body lists the
/// validation `errors`, exactly as FastAPI reports a failed request.
pub fn unprocessable(errors : Array[ValidationError]) -> @moonasgi.Response {
  @status.json(422, validation_error_body(errors))
}

///|
/// Whether a `Double` holds an exact integer value (no fractional part).
fn is_integral(n : Double) -> Bool {
  n == n.to_int().to_double()
}

///|
/// Validate a JSON `value` against the descriptor `schema`, appending
/// FastAPI-shaped errors to `errs` (located at `loc`). This is what "the
/// descriptor drives validation" means: the very tree that emits the OpenAPI
/// body schema also decides whether an inbound body conforms — one source of
/// truth, exactly as pydantic derives both from one model. A named object is
/// validated against its inline fields, so no `$ref` resolution is needed here.
pub fn validate_schema(
  schema : Schema,
  value : Json,
  loc : Array[String],
  errs : Array[ValidationError],
) -> Unit {
  match (schema, value) {
    // A JSON Schema validates itself: moonschema reads the same document the
    // OpenAPI emitter writes, and each of its faults becomes one error here.
    (SJson(document), _) => {
      let validator = @moonschema.Schema::new(document) catch {
        error => {
          errs.push(
            ValidationError::type_error(loc, "schema_error", error.to_string()),
          )
          return
        }
      }
      for fault in validator.faults(value) {
        errs.push(
          ValidationError::type_error(
            pointer_loc(loc, fault.at),
            fault.keyword,
            fault.message,
          ),
        )
      }
    }
    (SStr, String(_)) => ()
    (SStr, _) =>
      errs.push(
        ValidationError::type_error(
          loc, "string_type", "Input should be a valid string",
        ),
      )
    (SInt, Number(n, ..)) =>
      if !is_integral(n) {
        errs.push(
          ValidationError::type_error(
            loc, "int_from_float", "Input should be a valid integer, got a number with a fractional part",
          ),
        )
      }
    (SInt, _) =>
      errs.push(
        ValidationError::type_error(
          loc, "int_type", "Input should be a valid integer",
        ),
      )
    (SFloat, Number(_, ..)) => ()
    (SFloat, _) =>
      errs.push(
        ValidationError::type_error(
          loc, "float_type", "Input should be a valid number",
        ),
      )
    (SBool, True) => ()
    (SBool, False) => ()
    (SBool, _) =>
      errs.push(
        ValidationError::type_error(
          loc, "bool_type", "Input should be a valid boolean",
        ),
      )
    (SNull, Null) => ()
    (SNull, _) =>
      errs.push(
        ValidationError::type_error(loc, "null_type", "Input should be null"),
      )
    (SArray(item), Array(a)) =>
      for i, v in a {
        validate_schema(item, v, loc_push(loc, i.to_string()), errs)
      }
    (SArray(_), _) =>
      errs.push(
        ValidationError::type_error(
          loc, "list_type", "Input should be a valid list",
        ),
      )
    (SEnum(_, values), v) =>
      if !enum_member(values, v) {
        errs.push(
          ValidationError::type_error(
            loc,
            "enum",
            "Input should be " + enum_expected(values),
          ),
        )
      }
    (SObject(os), Object(m)) =>
      for f in os.fields {
        match m.get(f.name) {
          None =>
            if f.is_required() {
              errs.push(ValidationError::missing(loc_push(loc, f.name)))
            }
          Some(v) => {
            validate_schema(f.schema, v, loc_push(loc, f.name), errs)
            check_constraints(v, f.constraints, loc_push(loc, f.name), errs)
          }
        }
      }
    (SObject(_), _) =>
      errs.push(
        ValidationError::type_error(
          loc, "model_type", "Input should be a valid object",
        ),
      )
    // An explicit null satisfies the wrapper; anything else has to satisfy what
    // is wrapped, so `Optional[int]` still rejects a string.
    (SNullable(_), Null) => ()
    (SNullable(inner), v) => validate_schema(inner, v, loc, errs)
    (SMap(value), Object(m)) =>
      for k, v in m {
        validate_schema(value, v, loc_push(loc, k), errs)
      }
    (SMap(_), _) =>
      errs.push(
        ValidationError::type_error(
          loc, "dict_type", "Input should be a valid dictionary",
        ),
      )
    // A format refines what a value *means*, never what it is, so validation
    // checks the base — which is what pydantic does for a format it has no
    // validator for.
    (SFormat(base, _), v) => validate_schema(base, v, loc, errs)
    (SAny, _) => ()
  }
}

///|
/// Whether `v` is one of the allowed enum `values`.
pub fn enum_member(values : Array[Json], v : Json) -> Bool {
  for allowed in values {
    if allowed == v {
      return true
    }
  }
  false
}

///|
/// The Pydantic-style "expected one of" fragment for an `enum` error: string
/// members quoted, comma-separated, with a final `or` before the last.
pub fn enum_expected(values : Array[Json]) -> String {
  let parts : Array[String] = []
  for v in values {
    parts.push(
      match v {
        String(s) => "'" + s + "'"
        _ => v.stringify()
      },
    )
  }
  let n = parts.length()
  let sb = StringBuilder()
  for i = 0; i < n; i = i + 1 {
    if i == n - 1 && n > 1 {
      sb.write_string(" or ")
    } else if i > 0 {
      sb.write_string(", ")
    }
    sb.write_string(parts[i])
  }
  sb.to_string()
}
