name = "moonbitstack/moonapi"

version = "0.17.1"

readme = "README.md"

source = "src"

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

description = "moonapi — a typed web framework for MoonBit (← FastAPI): async handlers, routing, typed extractors, descriptor-driven validation, multi-version OpenAPI/Swagger (2.0 / 3.0 / 3.1) with security schemes, dependency injection, OAuth2 password-bearer with scopes, per-operation security enforcement, multipart and urlencoded forms, response_model filtering, background tasks, sub-application mounting, ASGI layers and FastAPI-style middleware, exception and per-status handlers, streaming responses, Server-Sent Events and live WebSocket routes, as a native moonasgi application."

import {
  "moonbitstack/moonmodel@0.1.0",
  "moonbitstack/moonasgi@0.10.2",
  "moonbitstack/moonbase@0.4.0",
  "moonbitstack/moonjson@0.4.0",
  "moonbitstack/mooncrypt@0.3.1",
  "moonbitstack/mooncred@0.6.0",
  "moonbitstack/moonhttp@0.15.1",
  "moonbitstack/moonmime@0.2.0",
  "moonbitstack/moonurl@0.2.0",
  "moonbitstack/moondate@0.1.0",
  "moonbitstack/moonschema@0.2.0",
  "moonbitstack/moonzip@0.3.0",
  "moonbitstack/mooncat@0.18.6",
  "moonbitstack/moonast@0.2.1",
  "moonbitlang/parser@0.4.6",
  "moonbitlang/async@0.22.5",
}
