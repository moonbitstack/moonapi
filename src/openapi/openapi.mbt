///|
/// OpenAPI `contact` info (← FastAPI's `contact`): every field optional, emitted
/// only when non-empty.
pub(all) struct Contact {
  name : String
  url : String
  email : String
}

///|
pub fn Contact::new(
  name~ : String = "",
  url~ : String = "",
  email~ : String = "",
) -> Contact {
  { name, url, email, }
}

///|
/// OpenAPI `license` info (← FastAPI's `license_info`): `name` required, then
/// either a `url` or, in OpenAPI 3.1, an SPDX `identifier`. The two exclude each
/// other in 3.1, so there an `identifier` is written and the `url` is not; the
/// older dialects have no `identifier` and get the `url`.
pub(all) struct License {
  name : String
  url : String
  identifier : String
}

///|
pub fn License::new(
  name : String,
  url~ : String = "",
  identifier~ : String = "",
) -> License {
  { name, url, identifier, }
}

///|
/// A `servers` entry (← FastAPI's `servers`): a base URL and an optional
/// description.
pub(all) struct Server {
  url : String
  description : String
}

///|
pub fn Server::new(url : String, description~ : String = "") -> Server {
  { url, description, }
}

///|
/// A link to documentation kept elsewhere: the `externalDocs` object, on the
/// document or on a tag.
pub(all) struct ExternalDocs {
  url : String
  description : String
}

///|
pub fn ExternalDocs::new(
  url : String,
  description~ : String = "",
) -> ExternalDocs {
  { url, description, }
}

///|
/// What the document says about one operation tag (← FastAPI's `openapi_tags`):
/// documentation viewers group operations by tag, in the order the tags are
/// listed here, and show this description above each group.
pub(all) struct Tag {
  name : String
  description : String
  external_docs : ExternalDocs?
}

///|
pub fn Tag::new(
  name : String,
  description~ : String = "",
  external_docs? : ExternalDocs,
) -> Tag {
  { name, description, external_docs, }
}

///|
/// What the document says about the API itself — FastAPI's `info` block plus
/// `servers`, the tag descriptions and the external documentation. An app
/// carries one (`App::describe` sets it) so that every emission of the
/// document, including the route `enable_docs` registers, agrees.
pub(all) struct ApiInfo {
  title : String
  // OpenAPI 3.1's one-line summary beside the longer `description`.
  summary : String
  api_version : String
  description : String
  terms_of_service : String
  contact : Contact?
  license : License?
  servers : Array[Server]
  tags : Array[Tag]
  external_docs : ExternalDocs?
}

///|
/// The defaults an app starts with.
pub fn ApiInfo::new() -> ApiInfo {
  {
    title: "moonapi",
    summary: "",
    api_version: "0.1.0",
    description: "",
    terms_of_service: "",
    contact: None,
    license: None,
    servers: [],
    tags: [],
    external_docs: None,
  }
}

///|
/// The `externalDocs` object for `docs`, the same in every dialect.
pub fn ExternalDocs::to_json(self : ExternalDocs) -> Json {
  let m : Map[String, Json] = { "url": Json(self.url) }
  if self.description != "" {
    m["description"] = Json(self.description)
  }
  Json(m)
}

///|
/// The tag object, the same in every dialect.
pub fn Tag::to_json(self : Tag) -> Json {
  let m : Map[String, Json] = { "name": Json(self.name) }
  if self.description != "" {
    m["description"] = Json(self.description)
  }
  if self.external_docs is Some(d) {
    m["externalDocs"] = d.to_json()
  }
  Json(m)
}
