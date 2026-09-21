///|
/// Decode a `Bytes` request field to text, replacing any malformed UTF-8 rather
/// than raising — inbound bytes are attacker-controlled, so extraction stays
/// total.
fn decode_field(raw : Bytes) -> String {
  @utf8.decode_lossy(raw[:])
}

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
/// Split a query string into decoded key/value pairs.
///
/// A query string is `application/x-www-form-urlencoded`, so the decoding is
/// `moonhttp/mime`'s: splitting on the raw bytes so a percent-escaped `&` or `=`
/// inside a value cannot be mistaken for a separator, `+` as a space, and a pair
/// with no `=` as a bare key.
fn query_pairs(raw : Bytes, limits : @mime.Limits) -> Array[(String, String)] {
  let out : Array[(String, String)] = []
  let form = @mime.urlencoded(raw[:], limits~) catch { _ => return out }
  for field in form.entries() {
    out.push((field.name, field.value))
  }
  out
}

///|
/// Look up a query-string parameter by name, e.g. `?limit=10&q=cat%20dog`. Keys and
/// values are percent/plus-decoded, so `q` above reads back as `cat dog`. When a key
/// repeats, the first occurrence wins; use `query_all` to read every one.
pub fn Context::query(
  self : Context,
  name : String,
  limits? : @mime.Limits = query_limits,
) -> String? {
  for kv in query_pairs(self.request.query_string, limits) {
    if kv.0 == name {
      return Some(kv.1)
    }
  }
  None
}

///|
/// Every value given for `name`, in the order they appear — `?tag=a&tag=b` reads
/// back as `["a", "b"]`. Empty when the key is absent.
pub fn Context::query_all(
  self : Context,
  name : String,
  limits? : @mime.Limits = query_limits,
) -> Array[String] {
  let out : Array[String] = []
  for kv in query_pairs(self.request.query_string, limits) {
    if kv.0 == name {
      out.push(kv.1)
    }
  }
  out
}

///|
/// Parse the request body as JSON, returning `None` for an empty body or one
/// that does not parse — the total counterpart of FastAPI reading a JSON body.
pub fn Context::body_json(self : Context) -> Json? {
  let s = decode_field(self.request.body)
  if s == "" {
    return None
  }
  Some(@moonjson.loads(s[:], @moonjson.strict)) catch {
    _ => None
  }
}

///|
/// Pull a single field out of a JSON object body by name, `None` if the body is
/// absent, not an object, or lacks the field.
pub fn Context::json_field(self : Context, name : String) -> Json? {
  match self.body_json() {
    Some(Object(m)) => m.get(name)
    _ => None
  }
}

///|
/// Look up a cookie by name from the request `Cookie` header, which is a
/// `; `-separated list of `key=value` pairs. Surrounding spaces are trimmed;
/// `None` if there is no `Cookie` header or the name is absent.
pub fn Context::cookie(self : Context, name : String) -> String? {
  match self.request.header("cookie") {
    None => None
    Some(raw) => {
      let n = raw.length()
      let mut start = 0
      for i = 0; i <= n; i = i + 1 {
        if i == n || raw[i] == ';' {
          if i > start {
            let pair = trim_spaces(raw[start:i].to_owned())
            let m = pair.length()
            let mut eq = -1
            for j = 0; j < m; j = j + 1 {
              if pair[j] == '=' {
                eq = j
                break
              }
            }
            if eq >= 0 && pair[0:eq].to_owned() == name {
              return Some(pair[eq + 1:m].to_owned())
            }
          }
          start = i + 1
        }
      }
      None
    }
  }
}

///|
/// Trim ASCII spaces and tabs from both ends of `s` (core has no `trim`).
fn trim_spaces(s : String) -> String {
  let n = s.length()
  let mut a = 0
  let mut b = n
  while a < b && (s[a].to_int() == 0x20 || s[a].to_int() == 0x09) {
    a = a + 1
  }
  while b > a && (s[b - 1].to_int() == 0x20 || s[b - 1].to_int() == 0x09) {
    b = b - 1
  }
  s[a:b].to_owned()
}

///|
/// Parse a base-10 integer, `None` if `s` is not a well-formed integer literal
/// (optional leading `+`/`-`, then one or more ASCII digits, nothing else).
fn parse_int(s : String) -> Int? {
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
fn ValidationError::to_json(self : ValidationError) -> Json {
  let m : Map[String, Json] = Map([
    ("type", self.kind.to_json()),
    ("loc", self.loc.to_json()),
    ("msg", self.msg.to_json()),
  ])
  m.to_json()
}

///|
/// The `{"detail": [ ... ]}` body FastAPI returns when request validation
/// fails, built from a list of `ValidationError`s.
pub fn validation_error_body(errors : Array[ValidationError]) -> Json {
  let detail : Array[Json] = []
  for e in errors {
    detail.push(e.to_json())
  }
  let doc : Map[String, Json] = Map([("detail", detail.to_json())])
  doc.to_json()
}

///|
/// A `422 Unprocessable Entity` response whose `application/json` body lists the
/// validation `errors`, exactly as FastAPI reports a failed request.
pub fn unprocessable(errors : Array[ValidationError]) -> @moonasgi.Response {
  json(422, validation_error_body(errors))
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
/// Validate a raw string parameter `v` (query/path/header/cookie values always
/// arrive as text) against the declared scalar `schema`, appending a parse error
/// to `errs` when it cannot represent that scalar. Strings always pass; integers
/// and booleans are checked; floats are accepted (no false negatives here).
fn validate_scalar_str(
  schema : Schema,
  v : String,
  loc : Array[String],
  errs : Array[ValidationError],
) -> Unit {
  match schema {
    SInt =>
      match parse_int(v) {
        Some(_) => ()
        None =>
          errs.push(
            ValidationError::type_error(
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
          ValidationError::type_error(
            loc, "bool_parsing", "Input should be a valid boolean, unable to interpret input",
          ),
        )
      }
    SEnum(base, values) =>
      if !enum_member(values, scalar_json(base, v)) {
        errs.push(
          ValidationError::type_error(
            loc,
            "enum",
            "Input should be " + enum_expected(values),
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
fn scalar_json(base : Schema, v : String) -> Json {
  match base {
    SInt =>
      match parse_int(v) {
        Some(n) => n.to_json()
        None => v.to_json()
      }
    SBool =>
      match v {
        "true" | "True" | "1" => true.to_json()
        "false" | "False" | "0" => false.to_json()
        _ => v.to_json()
      }
    SNullable(inner) => scalar_json(inner, v)
    SFormat(base, _) => scalar_json(base, v)
    _ => v.to_json()
  }
}

///|
/// Whether `v` is one of the allowed enum `values`.
fn enum_member(values : Array[Json], v : Json) -> Bool {
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
fn enum_expected(values : Array[Json]) -> String {
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

///|
/// Validate an inbound request `ctx` against this endpoint descriptor: every
/// declared parameter (path / query / header / cookie) plus the JSON request
/// body, all off the same descriptor tree that emits the OpenAPI operation.
/// Returns the accumulated errors — an empty array means the request conforms,
/// otherwise pass them to `unprocessable` for a FastAPI-shaped `422`.
pub fn Endpoint::validate(
  self : Endpoint,
  ctx : Context,
) -> Array[ValidationError] {
  let errs : Array[ValidationError] = []
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
          errs.push(ValidationError::missing([loc_str(p.loc), key]))
        }
      Some(v) => {
        let loc = [loc_str(p.loc), key]
        validate_scalar_str(p.schema, v, loc, errs)
        // Constraints see the value as its declared scalar, so a `ge` on an
        // integer parameter compares numbers rather than text.
        check_constraints(scalar_json(p.schema, v), p.constraints, loc, errs)
      }
    }
  }
  match self.request_body {
    Some(body) =>
      match ctx.body_json() {
        None =>
          if self.request_required {
            errs.push(ValidationError::missing(["body"]))
          }
        Some(j) => validate_schema(body, j, ["body"], errs)
      }
    None => ()
  }
  errs
}
