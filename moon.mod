name = "moonbitstack/moonapi"

version = "0.10.0"

readme = "README.md"

repository = "https://github.com/moonbitstack/moonapi"

license = "Apache-2.0"

keywords = [
  "fastapi",
  "web",
  "framework",
  "openapi",
  "swagger",
  "asgi",
  "moonbit",
]

description = "moonapi — a typed web framework for MoonBit (\u2190 FastAPI): routing, typed extractors, descriptor-driven validation, multi-version OpenAPI/Swagger (2.0 / 3.0 / 3.1) with security schemes, dependency injection, OAuth2 password-bearer with scopes, per-operation security enforcement, multipart and urlencoded form extractors, response_model filtering, background tasks, sub-application mounting, a CORS/gzip/exception-handler middleware stack with per-status handlers, Server-Sent Events, and WebSocket routes, on the moonasgi SEAM."

import {
  "moonbitstack/moonasgi@0.10.0",
  "moonbitstack/moonbase@0.4.0",
  "moonbitstack/moonjson@0.2.0",
  "moonbitstack/mooncrypt@0.1.1",
  "moonbitstack/mooncred@0.3.0",
  "moonbitstack/moonhttp@0.2.0",
  "moonbitstack/moonzip@0.2.0",
}
