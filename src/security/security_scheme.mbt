// OpenAPI security scheme objects (← FastAPI surfacing `OAuth2PasswordBearer`,
// `OAuth2AuthorizationCodeBearer`, `HTTPBearer`, `HTTPBasic`, `HTTPDigest`,
// `APIKeyHeader`, `OpenIdConnect`, etc. under `components/securitySchemes`). A
// `SecurityScheme` is declared on the `App` and emitted into the generated spec
// so the security layer is described to clients. Both spec shapes are produced:
// OpenAPI 3.x `securitySchemes`, and the Swagger 2.0 `securityDefinitions` shape
// (flat OAuth2 flows, no `http` type, and no way at all to say `openIdConnect`).

///|
/// A security scheme describing how a client authenticates. Mirrors the OpenAPI
/// scheme types: the two OAuth2 flows a browser or a service actually uses
/// (password and authorization code), HTTP bearer / basic / digest, an API key
/// in a header / query / cookie, and OpenID Connect discovery.
pub(all) enum SecurityScheme {
  OAuth2Password(token_url~ : String, scopes~ : Array[(String, String)])
  // ← FastAPI's `OAuth2AuthorizationCodeBearer`: the endpoint the browser is
  // sent to, the one the code is exchanged at, and — when the provider offers it
  // — where a token is refreshed. An empty `refresh_url` is left out.
  OAuth2Code(
    authorization_url~ : String,
    token_url~ : String,
    refresh_url~ : String,
    scopes~ : Array[(String, String)]
  )
  HttpBearer(bearer_format~ : String)
  ApiKeyHeader(name~ : String)
  ApiKeyQuery(name~ : String)
  ApiKeyCookie(name~ : String)
  HttpBasic
  // ← FastAPI's `HTTPDigest`. RFC 7616 negotiates through a `WWW-Authenticate`
  // challenge, and OpenAPI describes only the scheme name.
  HttpDigest
  // ← FastAPI's `OpenIdConnect`: one discovery document from which a client
  // reads every other parameter.
  OpenIdConnect(url~ : String)
}

///|
/// A security scheme as an application declares it: the `name` routes refer to
/// it by, the `kind` that shapes the emitted object, and the prose beside it
/// (← the `description=` every FastAPI security class takes).
pub(all) struct DeclaredScheme {
  name : String
  kind : SecurityScheme
  description : String
}

///|
/// Build the security scheme that describes this password-bearer flow (← the
/// object FastAPI derives from `OAuth2PasswordBearer`). `scopes` are the
/// `(name, description)` pairs advertised in the OpenAPI document.
pub fn OAuth2PasswordBearer::scheme(
  self : OAuth2PasswordBearer,
  scopes~ : Array[(String, String)] = [],
) -> SecurityScheme {
  OAuth2Password(token_url=self.token_url, scopes~)
}

///|
/// A `{name: description, ...}` JSON object from scope pairs.
fn scopes_object(scopes : Array[(String, String)]) -> Json {
  let m : Map[String, Json] = Map([])
  for pair in scopes {
    m[pair.0] = Json(pair.1)
  }
  Json(m)
}

///|
/// This scheme as an OpenAPI 3.0 / 3.1 security scheme object.
pub fn SecurityScheme::to_openapi_3x(self : SecurityScheme) -> Json {
  match self {
    OAuth2Password(token_url~, scopes~) => {
      let flow : Map[String, Json] = Map([
        ("tokenUrl", Json(token_url)),
        ("scopes", scopes_object(scopes)),
      ])
      oauth2_json("password", flow)
    }
    OAuth2Code(authorization_url~, token_url~, refresh_url~, scopes~) => {
      let flow : Map[String, Json] = Map([
        ("authorizationUrl", Json(authorization_url)),
        ("tokenUrl", Json(token_url)),
      ])
      if refresh_url != "" {
        flow["refreshUrl"] = Json(refresh_url)
      }
      flow["scopes"] = scopes_object(scopes)
      oauth2_json("authorizationCode", flow)
    }
    HttpBearer(bearer_format~) => {
      let m : Map[String, Json] = Map([
        ("type", Json("http")),
        ("scheme", Json("bearer")),
        ("bearerFormat", Json(bearer_format)),
      ])
      Json(m)
    }
    ApiKeyHeader(name~) => api_key_json("header", name)
    ApiKeyQuery(name~) => api_key_json("query", name)
    ApiKeyCookie(name~) => api_key_json("cookie", name)
    HttpBasic => http_scheme_json("basic")
    HttpDigest => http_scheme_json("digest")
    OpenIdConnect(url~) => {
      let m : Map[String, Json] = Map([
        ("type", Json("openIdConnect")),
        ("openIdConnectUrl", Json(url)),
      ])
      Json(m)
    }
  }
}

///|
/// An `oauth2` scheme object carrying one named 3.x flow.
fn oauth2_json(flow_name : String, flow : Map[String, Json]) -> Json {
  let flows : Map[String, Json] = Map([(flow_name, Json(flow))])
  let m : Map[String, Json] = Map([
    ("type", Json("oauth2")),
    ("flows", Json(flows)),
  ])
  Json(m)
}

///|
/// An `{"type":"http","scheme":...}` object for the HTTP authentication schemes.
fn http_scheme_json(scheme : String) -> Json {
  let m : Map[String, Json] = Map([
    ("type", Json("http")),
    ("scheme", Json(scheme)),
  ])
  Json(m)
}

///|
/// An `apiKey` scheme object for `in`/`name`.
fn api_key_json(in_ : String, name : String) -> Json {
  let m : Map[String, Json] = Map([
    ("type", Json("apiKey")),
    ("in", Json(in_)),
    ("name", Json(name)),
  ])
  Json(m)
}

///|
/// This scheme as a Swagger 2.0 security definition, or `None` when 2.0 cannot
/// express it. Swagger 2.0 has no `http` type: an HTTP bearer or digest is
/// expressed as an `apiKey` in the `Authorization` header (the standard 2.0
/// workaround), Basic uses the `basic` type, and OAuth2 flows are the flat 2.0
/// form (`flow` + URLs at top level, `accessCode` being 2.0's name for the
/// authorization-code flow). Swagger 2.0 `apiKey` only allows `header`/`query`,
/// so a cookie key maps to a header. OpenID Connect has no 2.0 equivalent at
/// all, and inventing one would describe an API that does not exist — so it is
/// left out of the 2.0 document.
pub fn SecurityScheme::to_openapi_20(self : SecurityScheme) -> Json? {
  match self {
    OAuth2Password(token_url~, scopes~) => {
      let m : Map[String, Json] = Map([
        ("type", Json("oauth2")),
        ("flow", Json("password")),
        ("tokenUrl", Json(token_url)),
        ("scopes", scopes_object(scopes)),
      ])
      Some(Json(m))
    }
    OAuth2Code(authorization_url~, token_url~, scopes~, ..) => {
      let m : Map[String, Json] = Map([
        ("type", Json("oauth2")),
        ("flow", Json("accessCode")),
        ("authorizationUrl", Json(authorization_url)),
        ("tokenUrl", Json(token_url)),
        ("scopes", scopes_object(scopes)),
      ])
      Some(Json(m))
    }
    HttpBearer(_) => Some(api_key_json("header", "Authorization"))
    HttpDigest => Some(api_key_json("header", "Authorization"))
    ApiKeyHeader(name~) => Some(api_key_json("header", name))
    ApiKeyQuery(name~) => Some(api_key_json("query", name))
    ApiKeyCookie(name~) => Some(api_key_json("header", name))
    HttpBasic => {
      let m : Map[String, Json] = Map([("type", Json("basic"))])
      Some(Json(m))
    }
    OpenIdConnect(_) => None
  }
}
