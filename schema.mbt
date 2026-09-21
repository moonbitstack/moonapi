///|
/// A JSON-Schema type descriptor — the runtime, first-class value that stands in
/// for FastAPI's from-signature reflection. One `Schema` tree is *walked once* to
/// (a) emit a complete OpenAPI request/response body schema — objects, arrays and
/// scalars, with `required`, and named objects hoisted under `components/schemas`
/// and referenced by `$ref` — and (b) drive validation of an inbound JSON value.
/// This is the explicit, MoonBit-idiomatic equivalent of pydantic's type-driven
/// magic (cf. Rust `serde` + macros, Go struct tags + codegen). A named object
/// carries its fields *inline*, so the same tree is fully self-describing for
/// validation; the name is used only to deduplicate it into `components` on emit.
pub(all) enum Schema {
  SStr
  SInt
  SFloat
  SBool
  SNull
  SArray(Schema)
  SObject(ObjectSchema)
  // A closed value set (← a Python `Enum` / `typing.Literal`): the base scalar
  // whose `type` is still emitted, plus the allowed values as raw `Json`.
  SEnum(Schema, Array[Json])
  // A value that may also be null (← `Optional[T]` / `T | None`). Each dialect
  // says it differently, which is why it is a wrapper rather than a flag.
  SNullable(Schema)
  // An object with no declared fields whose values all conform to one schema
  // (← `dict[str, T]`), emitted as `additionalProperties`. `SMap(SAny)` is the
  // free-form object a bare `dict` maps to.
  SMap(Schema)
  // Any JSON value at all (← `Any`), emitted as the empty schema, which is the
  // JSON-Schema way of saying "no constraint".
  SAny
  // A schema refined by an OpenAPI `format`. `format: binary` is what an upload
  // is described as, and the reason this exists.
  SFormat(Schema, String)
} derive(Eq)

///|
/// The body of an object schema: its component `name` (empty = an anonymous
/// inline object; non-empty = hoisted to `components/schemas` and referenced),
/// its ordered `fields`, and an optional `description`.
pub(all) struct ObjectSchema {
  name : String
  fields : Array[Field]
  description : String
} derive(Eq)

///|
/// One field of an object schema: its `name`, its `schema`, whether it is
/// `required`, an optional `description`, its value `constraints`, and the
/// `default` that stands in when a body leaves it out.
pub(all) struct Field {
  name : String
  schema : Schema
  required : Bool
  description : String
  constraints : Array[Constraint]
  default : Json?
} derive(Eq)

///|
/// Build a field. `required` defaults to `true` (FastAPI treats a field without
/// a default as required). `constraints` are the Pydantic-style value constraints
/// (`ge`/`le`/`min_length`/`pattern`/…) that are both emitted into the field's
/// OpenAPI schema and enforced when validating an inbound value. `default` is
/// emitted into the schema and makes the field optional, since a value that has
/// one is never missing.
pub fn Field::new(
  name : String,
  schema : Schema,
  required? : Bool = true,
  description? : String = "",
  constraints? : Array[Constraint] = [],
  default? : Json,
) -> Field {
  { name, schema, required, description, constraints, default, }
}

///|
/// Whether a body must carry this field. A field with a default never must — its
/// absence is answered by the default, exactly as a Python default argument is,
/// so it is left out of the emitted `required` list and not reported missing.
pub fn Field::is_required(self : Field) -> Bool {
  self.required && self.default is None
}

///|
/// A named object schema: hoisted to `components/schemas` under `name` and
/// referenced by `$ref` wherever it is used.
pub fn Schema::object(name : String, fields : Array[Field]) -> Schema {
  SObject({ name, fields, description: "", })
}

///|
/// An array schema whose elements all conform to `item`.
pub fn Schema::array(item : Schema) -> Schema {
  SArray(item)
}

///|
/// A schema that also admits `null` (← `Optional[T]`). Wrapping rather than a
/// flag because the three dialects express it three different ways.
pub fn Schema::nullable(inner : Schema) -> Schema {
  SNullable(inner)
}

///|
/// An object with no declared fields whose values all conform to `value`
/// (← `dict[str, T]`). `Schema::map(SAny)` is the free-form object.
pub fn Schema::map(value : Schema) -> Schema {
  SMap(value)
}

///|
/// `base` refined by an OpenAPI `format`. The format is documentation: it tells
/// a reader and a client generator what the string holds, and validation still
/// checks only `base`, which is what pydantic does for a format it has no
/// validator for.
pub fn Schema::format(base : Schema, format : String) -> Schema {
  SFormat(base, format)
}

///|
/// The schema of file content: a string with OpenAPI's `binary` format — what an
/// upload is described as, and what a multipart file field carries.
pub fn Schema::binary() -> Schema {
  SFormat(SStr, "binary")
}

///|
/// The `impl`-able version of a type's descriptor. A user struct implements it —
/// the value is ignored; it exists so descriptor-carrying code can be generic
/// over "a type that knows its own schema". The primary, mctl-friendly shape is
/// still a plain associated function `T::schema() -> Schema` (no instance needed,
/// mirroring FastAPI referencing the model *class*); this trait bridges to it.
pub(open) trait ToSchema {
  fn to_schema(Self) -> Schema
}

///|
/// The schema of any `ToSchema` type, without needing a value of it materialised
/// at the call site beyond the one handed in — the generic entry point.
pub fn[T : ToSchema] schema_of(x : T) -> Schema {
  ToSchema::to_schema(x)
}

// -- emission (descriptor tree -> OpenAPI JSON) -------------------------------

///|
/// Where `$ref`s point, which differs between spec families: OpenAPI 3.x hoists
/// schemas under `#/components/schemas/`, Swagger 2.0 under `#/definitions/`.
fn ref_base(v : OpenApiVersion) -> String {
  match v {
    Swagger20 => "#/definitions/"
    _ => "#/components/schemas/"
  }
}

///|
/// A bare `{"type": t}` scalar schema object.
fn scalar_schema(t : String) -> Json {
  let m : Map[String, Json] = Map([("type", t.to_json())])
  m.to_json()
}

///|
/// The scalar OpenAPI type name of a schema, `None` for composite schemas. A
/// format or a nullable wrapper does not change what the underlying value is, so
/// both report their base — which is what lets a Swagger 2.0 parameter, whose
/// type sits on the parameter object itself, carry them at all.
fn scalar_name(s : Schema) -> String? {
  match s {
    SStr => Some("string")
    SInt => Some("integer")
    SFloat => Some("number")
    SBool => Some("boolean")
    SNull => Some("null")
    SFormat(base, _) => scalar_name(base)
    SNullable(inner) => scalar_name(inner)
    _ => None
  }
}

///|
/// Return `j` with `key` set to `value`. Builds a fresh object so nothing shared
/// mutates; a non-object is returned untouched, since there is nothing to set on
/// it.
fn with_key(j : Json, key : String, value : Json) -> Json {
  match j {
    Object(m) => {
      let out : Map[String, Json] = Map([])
      for k, v in m {
        out[k] = v
      }
      out[key] = value
      out.to_json()
    }
    _ => j
  }
}

///|
/// Return `j` with a `description` sibling added (legal beside `$ref` in OpenAPI
/// 3.1 / JSON-Schema 2020-12).
fn with_description(j : Json, desc : String) -> Json {
  with_key(j, "description", desc.to_json())
}

///|
/// Copy every key of the JSON object `src` into `dst`, leaving `dst`'s other
/// keys alone. A non-object `src` contributes nothing.
fn merge_into(dst : Map[String, Json], src : Json) -> Unit {
  if src is Object(o) {
    for k, v in o {
      dst[k] = v
    }
  }
}

///|
/// Emit `schema` as inline OpenAPI JSON, hoisting every *named* object into
/// `defs` (keyed by name) and referencing it by `$ref`. Recursion-safe: a name
/// is reserved in `defs` before its body is built, so a self-referential schema
/// terminates instead of looping.
fn emit_schema(
  schema : Schema,
  defs : Map[String, Json],
  version : OpenApiVersion,
) -> Json {
  match schema {
    SStr => scalar_schema("string")
    SInt => scalar_schema("integer")
    SFloat => scalar_schema("number")
    SBool => scalar_schema("boolean")
    SNull => scalar_schema("null")
    SArray(item) => {
      let m : Map[String, Json] = Map([
        ("type", "array".to_json()),
        ("items", emit_schema(item, defs, version)),
      ])
      m.to_json()
    }
    SObject(os) =>
      if os.name != "" {
        register_object(os, defs, version)
        let r : Map[String, Json] = Map([
          ("$ref", (ref_base(version) + os.name).to_json()),
        ])
        r.to_json()
      } else {
        object_body(os, defs, version)
      }
    SEnum(base, values) =>
      match emit_schema(base, defs, version) {
        Object(o) => {
          let m : Map[String, Json] = Map([])
          for k, v in o {
            m[k] = v
          }
          m["enum"] = values.to_json()
          m.to_json()
        }
        other => other
      }
    SNullable(inner) =>
      nullable_json(emit_schema(inner, defs, version), version)
    SMap(value) => {
      let m : Map[String, Json] = Map([
        ("type", "object".to_json()),
        ("additionalProperties", emit_schema(value, defs, version)),
      ])
      m.to_json()
    }
    // The empty schema — JSON-Schema for "anything at all".
    SAny => {
      let m : Map[String, Json] = Map([])
      m.to_json()
    }
    SFormat(base, format) =>
      with_key(emit_schema(base, defs, version), "format", format.to_json())
  }
}

///|
/// `j` widened to admit `null`, the way `version` says it. Swagger 2.0 cannot say
/// it in the specification proper and uses the `x-nullable` extension its tooling
/// reads; 3.0 has a `nullable` flag; 3.1 is JSON-Schema 2020-12, where the type
/// itself becomes a list — and where a `$ref` or a composite, having no `type` to
/// extend, has to be widened with an `anyOf` instead.
fn nullable_json(j : Json, version : OpenApiVersion) -> Json {
  match version {
    Swagger20 => with_key(j, "x-nullable", true.to_json())
    OpenApi30 => with_key(j, "nullable", true.to_json())
    OpenApi31 =>
      if j is Object(o) && o.get("type") is Some(String(t)) {
        with_key(j, "type", [t.to_json(), "null".to_json()].to_json())
      } else {
        let null_type : Map[String, Json] = Map([("type", "null".to_json())])
        let m : Map[String, Json] = Map([
          ("anyOf", [j, null_type.to_json()].to_json()),
        ])
        m.to_json()
      }
  }
}

///|
/// Register a named object into `defs` (once), reserving its slot first so that
/// cycles through its fields resolve to the already-in-progress `$ref`.
fn register_object(
  os : ObjectSchema,
  defs : Map[String, Json],
  version : OpenApiVersion,
) -> Unit {
  match defs.get(os.name) {
    Some(_) => ()
    None => {
      defs[os.name] = Json::null()
      defs[os.name] = object_body(os, defs, version)
    }
  }
}

///|
/// The `{"type":"object","properties":{...},"required":[...]}` body of an object
/// schema, recursively emitting each field's schema (which may hoist further
/// named objects into `defs`).
fn object_body(
  os : ObjectSchema,
  defs : Map[String, Json],
  version : OpenApiVersion,
) -> Json {
  let props : Map[String, Json] = Map([])
  let required : Array[Json] = []
  for f in os.fields {
    let mut fs = with_constraints(
      emit_schema(f.schema, defs, version),
      f.constraints,
      version,
    )
    if f.default is Some(d) {
      fs = with_key(fs, "default", d)
    }
    props[f.name] = if f.description != "" {
      with_description(fs, f.description)
    } else {
      fs
    }
    if f.is_required() {
      required.push(f.name.to_json())
    }
  }
  let m : Map[String, Json] = Map([
    ("type", "object".to_json()),
    ("properties", props.to_json()),
  ])
  if required.length() > 0 {
    m["required"] = required.to_json()
  }
  if os.description != "" {
    m["description"] = os.description.to_json()
  }
  m.to_json()
}

///|
pub extend Schema with Eq::{not_equal, equal}

///|
pub extend ObjectSchema with Eq::{not_equal, equal}

///|
pub extend Field with Eq::{not_equal, equal}
