///|
/// A reference that could not be written into the schema, and why.
///
/// Reported rather than dropped or guessed at: a body schema silently missing
/// a field is a validation hole that shows up as accepted-but-wrong data.
pub(all) struct Unresolved {
  /// The field that holds the reference.
  field : String
  /// The model it points at.
  model : String
  why : String
} derive(Eq)

///|
pub extend Unresolved with Eq::{equal, not_equal}

///|
/// A moonmodel description as a schema.
///
/// One description, written once, drives request validation and the OpenAPI
/// document here, and the DDL and the SDL in their own libraries. `known` is
/// where a `Ref` is looked up: a reference to a model that is not in it, or
/// one that leads back to a model already being written, is reported instead
/// — a schema is a finite value, so a cycle cannot be written out, and the
/// name alone does not say what the thing looks like.
pub fn Schema::of_model(
  model : @moonmodel.Model,
  known~ : Array[@moonmodel.Model] = [],
) -> (Schema, Array[Unresolved]) {
  let missing = []
  let schema = object_of(model, known, [], missing)
  (schema, missing)
}

///|
/// `open~` is the names currently being written, which is how a reference
/// leading back into one of them is caught before it is followed.
fn object_of(
  model : @moonmodel.Model,
  known : Array[@moonmodel.Model],
  open : Array[String],
  missing : Array[Unresolved],
) -> Schema {
  let fields = []
  let within = if model.name == "" { open } else { [..open, model.name] }
  for one in model.fields {
    match kind_of(one.kind, known, within, one.name, missing) {
      Some(kind) => fields.push(described(one, kind))
      None => ()
    }
  }
  SObject({ name: model.name, fields, description: model.doc, })
}

///|
fn described(one : @moonmodel.Field, kind : Schema) -> Field {
  // A field that is nullable and one that may be absent are two questions
  // there, and two different things here: the first is a wrapper on the
  // value, the second is whether the name appears in `required`.
  let kind = if one.nullable { SNullable(kind) } else { kind }
  let kind = match one.check.format {
    Some(format) => SFormat(kind, format)
    None => kind
  }
  let kind = if one.check.options.length() > 0 {
    SEnum(kind, one.check.options)
  } else {
    kind
  }
  Field::new(
    one.name,
    kind,
    required=one.required,
    description=one.doc,
    constraints=bounds_of(one.check, one.kind),
    default?=one.default,
  )
}

///|
fn kind_of(
  kind : @moonmodel.Type,
  known : Array[@moonmodel.Model],
  open : Array[String],
  field : String,
  missing : Array[Unresolved],
) -> Schema? {
  match kind {
    Bool => Some(SBool)
    // Both are OpenAPI integers; which one is said by the format, which
    // `field_of` writes from `Check::format` only when the description asked
    // for one, so the width is carried by `int32`/`int64` below.
    Int => Some(SFormat(SInt, "int32"))
    Big => Some(SFormat(SInt, "int64"))
    Real => Some(SFloat)
    Text => Some(SStr)
    Bytes => Some(SFormat(SStr, "byte"))
    Stamp => Some(SFormat(SStr, "date-time"))
    List(inner) =>
      match kind_of(inner, known, open, field, missing) {
        Some(inner) => Some(SArray(inner))
        None => None
      }
    Dict(inner) =>
      match kind_of(inner, known, open, field, missing) {
        Some(inner) => Some(SMap(inner))
        None => None
      }
    Nest(model) => Some(object_of(model, known, open, missing))
    Ref(name) => {
      if open.contains(name) {
        missing.push({
          field,
          model: name,
          why: "a reference back into a model being written cannot be a finite schema",
        })
        return None
      }
      for one in known {
        if one.name == name {
          return Some(object_of(one, known, open, missing))
        }
      }
      missing.push({
        field,
        model: name,
        why: "not among the known models, and a name alone does not say what it looks like",
      })
      None
    }
    Any => Some(SAny)
    Raw(written) => Some(Schema::json(written))
  }
}

///|
/// The bounds, under the names this library gives them.
///
/// `shortest` and `longest` bound a string's characters and a list's items
/// alike in a description; here they are two different constraints, and the
/// type says which is meant.
fn bounds_of(
  check : @moonmodel.Check,
  kind : @moonmodel.Type,
) -> Array[Constraint] {
  let out = []
  match check.least {
    Some(value) => out.push(Minimum(value))
    None => ()
  }
  match check.most {
    Some(value) => out.push(Maximum(value))
    None => ()
  }
  match check.over {
    Some(value) => out.push(ExclusiveMinimum(value))
    None => ()
  }
  match check.under {
    Some(value) => out.push(ExclusiveMaximum(value))
    None => ()
  }
  match check.step {
    Some(value) => out.push(MultipleOf(value))
    None => ()
  }
  let listed = kind is List(_)
  match check.shortest {
    Some(value) =>
      out.push(if listed { MinItems(value) } else { MinLength(value) })
    None => ()
  }
  match check.longest {
    Some(value) =>
      out.push(if listed { MaxItems(value) } else { MaxLength(value) })
    None => ()
  }
  match check.pattern {
    Some(value) => out.push(Pattern(value))
    None => ()
  }
  out
}
