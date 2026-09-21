// Pydantic-style field value constraints (FastAPI's `Query`/`Field(ge=…, le=…, min_length=…,
// pattern=…, …)`), the MoonBit-idiomatic equivalent of the keyword arguments FastAPI reads off a
// parameter's `Annotated` metadata: since MoonBit has no reflection, a field carries its constraints
// as an explicit list. Each constraint is both emitted into the field's OpenAPI/JSON-Schema (so the
// generated spec advertises it) and enforced when an inbound value is validated (so a violation is a
// 422 with the matching Pydantic error type). One source of truth, exactly as pydantic derives both.

///|
/// A value constraint on a field (JSON-Schema keyword ↔ Pydantic argument).
pub(all) enum Constraint {
  Minimum(Double) // ge:  x >= n
  Maximum(Double) // le:  x <= n
  ExclusiveMinimum(Double) // gt:  x > n
  ExclusiveMaximum(Double) // lt:  x < n
  MultipleOf(Double) // multiple_of
  MinLength(Int) // min_length (characters)
  MaxLength(Int) // max_length
  Pattern(String) // pattern (regular expression)
  MinItems(Int) // min_length on a list
  MaxItems(Int) // max_length on a list
} derive(Eq)

///|
/// Merge the constraints into a scalar/array schema object for OpenAPI emission. `exclusiveMinimum`
/// / `exclusiveMaximum` are numeric under OpenAPI 3.1 (JSON-Schema 2020-12) but a boolean flag
/// alongside `minimum` / `maximum` under Swagger 2.0 and OpenAPI 3.0, so the form is version-aware.
pub fn with_constraints(
  j : Json,
  constraints : Array[Constraint],
  version : OpenApiVersion,
) -> Json {
  if constraints.length() == 0 {
    return j
  }
  let m = match j {
    Object(o) => {
      let copy : Map[String, Json] = Map([])
      for k, v in o {
        copy[k] = v
      }
      copy
    }
    _ => return j
  }
  let numeric_exclusive = match version {
    OpenApi31 => true
    _ => false
  }
  for c in constraints {
    match c {
      Minimum(x) => m["minimum"] = x.to_json()
      Maximum(x) => m["maximum"] = x.to_json()
      ExclusiveMinimum(x) =>
        if numeric_exclusive {
          m["exclusiveMinimum"] = x.to_json()
        } else {
          m["minimum"] = x.to_json()
          m["exclusiveMinimum"] = true.to_json()
        }
      ExclusiveMaximum(x) =>
        if numeric_exclusive {
          m["exclusiveMaximum"] = x.to_json()
        } else {
          m["maximum"] = x.to_json()
          m["exclusiveMaximum"] = true.to_json()
        }
      MultipleOf(x) => m["multipleOf"] = x.to_json()
      MinLength(n) => m["minLength"] = n.to_json()
      MaxLength(n) => m["maxLength"] = n.to_json()
      Pattern(p) => m["pattern"] = p.to_json()
      MinItems(n) => m["minItems"] = n.to_json()
      MaxItems(n) => m["maxItems"] = n.to_json()
    }
  }
  m.to_json()
}

///|
/// Enforce the constraints on an inbound `value`, appending a Pydantic-shaped `ValidationError`
/// (located at `loc`) for each violation. A constraint that does not apply to the value's kind
/// (a length bound on a number, say) is simply skipped, as pydantic does.
pub fn check_constraints(
  value : Json,
  constraints : Array[Constraint],
  loc : Array[String],
  errs : Array[ValidationError],
) -> Unit {
  for c in constraints {
    match c {
      Minimum(x) =>
        if value is Number(n, ..) && n < x {
          errs.push(
            constraint_err(
              loc,
              "greater_than_equal",
              "Input should be greater than or equal to " + num_str(x),
            ),
          )
        }
      Maximum(x) =>
        if value is Number(n, ..) && n > x {
          errs.push(
            constraint_err(
              loc,
              "less_than_equal",
              "Input should be less than or equal to " + num_str(x),
            ),
          )
        }
      ExclusiveMinimum(x) =>
        if value is Number(n, ..) && n <= x {
          errs.push(
            constraint_err(
              loc,
              "greater_than",
              "Input should be greater than " + num_str(x),
            ),
          )
        }
      ExclusiveMaximum(x) =>
        if value is Number(n, ..) && n >= x {
          errs.push(
            constraint_err(
              loc,
              "less_than",
              "Input should be less than " + num_str(x),
            ),
          )
        }
      MultipleOf(x) =>
        if value is Number(n, ..) && (x == 0.0 || !is_integral(n / x)) {
          errs.push(
            constraint_err(
              loc,
              "multiple_of",
              "Input should be a multiple of " + num_str(x),
            ),
          )
        }
      MinLength(k) =>
        if value is String(s) && char_len(s) < k {
          errs.push(
            constraint_err(
              loc,
              "string_too_short",
              "String should have at least " + k.to_string() + " characters",
            ),
          )
        }
      MaxLength(k) =>
        if value is String(s) && char_len(s) > k {
          errs.push(
            constraint_err(
              loc,
              "string_too_long",
              "String should have at most " + k.to_string() + " characters",
            ),
          )
        }
      Pattern(p) =>
        if value is String(s) && !pattern_matches(s, p) {
          errs.push(
            constraint_err(
              loc,
              "string_pattern_mismatch",
              "String should match pattern '" + p + "'",
            ),
          )
        }
      MinItems(k) =>
        if value is Array(a) && a.length() < k {
          errs.push(
            constraint_err(
              loc,
              "too_short",
              "List should have at least " + k.to_string() + " items",
            ),
          )
        }
      MaxItems(k) =>
        if value is Array(a) && a.length() > k {
          errs.push(
            constraint_err(
              loc,
              "too_long",
              "List should have at most " + k.to_string() + " items",
            ),
          )
        }
    }
  }
}

///|
/// A Pydantic-shaped constraint `ValidationError` (same shape as `type_error`).
fn constraint_err(
  loc : Array[String],
  kind : String,
  msg : String,
) -> ValidationError {
  ValidationError::type_error(loc, kind, msg)
}

///|
/// Format a constraint bound for a message: an integral value without its `.0`.
fn num_str(x : Double) -> String {
  if is_integral(x) {
    x.to_int().to_string()
  } else {
    x.to_string()
  }
}

///|
/// The character length of a string (code points, not UTF-16 units).
fn char_len(s : String) -> Int {
  let mut n = 0
  for _ in s {
    n = n + 1
  }
  n
}

///|
/// Whether `s` matches the regular expression `p` (a malformed pattern never matches).
fn pattern_matches(s : String, p : String) -> Bool {
  let re = @string.Regex::Regex(p) catch { _ => return false }
  re.execute(s) is Some(_)
}

///|
pub extend Constraint with Eq::{not_equal, equal}
