name = "moonbitstack/moonapi"

version = "0.8.1"

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

description = "moonapi — a typed web framework for MoonBit (← FastAPI): routing, typed extractors, descriptor-driven validation, multi-version OpenAPI/Swagger (2.0 / 3.0 / 3.1) with security schemes, dependency injection, OAuth2 password-bearer with self-built HS256 JWT and scopes, per-operation security enforcement, multipart/urlencoded form and file extractors, response_model filtering, background tasks, sub-application mounting, a CORS/gzip(real DEFLATE)/exception-handler middleware stack with per-status handlers, Server-Sent Events, and WebSocket routes, on the moonasgi SEAM."

import {
  "moonbitstack/moonasgi@0.8.2",
}
