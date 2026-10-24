///|
/// Target OpenAPI / Swagger document version. moonapi emits every mainstream
/// version from the same route descriptors — a "good FastAPI" is not pinned to
/// one spec version.
pub(all) enum OpenApiVersion {
  Swagger20
  OpenApi30
  OpenApi31
} derive(Eq)

///|
pub extend OpenApiVersion with Eq::{not_equal, equal}
