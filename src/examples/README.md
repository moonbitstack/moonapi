# Examples

A runnable tour of the public `@moonapi` API. Each numbered example has a
runnable `main` package; `25-full-example` is a layered native server composed
from several packages.

```bash
moon run src/examples/25-full-example --target native
```

Mooncat's native server runs on Windows, macOS and Linux. It listens on
`127.0.0.1:12000`. Open `/docs` for Swagger UI, `/redoc` for ReDoc, or
`/openapi.json` for the OpenAPI 3.0.3 document.

This integrated app keeps root endpoints and composes two routers, then exercises
auth, typed bodies, response filtering, CORS and gzip layers, dependency injection, forms,
files, background tasks, SSE, WebSockets, lifecycle hooks and OpenAPI. The focused
examples below isolate each feature.

Its source is split by responsibility:

```text
25-full-example/
	main.mbt                 # native Mooncat server entrypoint
	application/             # app configuration and router composition
	routes/accounts/         # authenticated profile, body and form routes
	routes/catalog/          # search, background work, SSE and WebSocket
	services/                # shared dependencies and response/request helpers
```

## Full Example API

The integrated service exposes these routes:

| Method | Path | Purpose |
| :--: | :--: | :--: |
| `GET` | `/` | Root API response |
| `GET` | `/health` | Health check |
| `POST` | `/token` | Issue a bearer token (`demo` / `demo`) |
| `GET` | `/api/v1/accounts/me` | Authenticated profile; requires `profile:read` |
| `POST` | `/api/v1/accounts/greet` | Validate a typed JSON body |
| `POST` | `/api/v1/accounts/form` | Parse a URL-encoded form |
| `GET` | `/api/v1/accounts/download` | Return a downloadable file |
| `GET` | `/api/v1/catalog/` | Search the catalog with `q` |
| `POST` | `/api/v1/catalog/orders` | Queue a background task |
| `GET` | `/api/v1/catalog/large` | Return a gzip-compressible response |
| `GET` | `/api/v1/catalog/events` | Stream a server-sent event |
| `WS` | `/api/v1/catalog/ws/:room` | WebSocket text echo |
| `GET` | `/reject` | Demonstrate the custom exception handler |

The documentation routes are `/docs`, `/redoc` and `/openapi.json`; they are
excluded from the generated API schema.

The focused examples run the app in-process on native, wasm and js, through
`App::handle` or the moonasgi test client; both go through `App::to_asgi`, the
same ASGI application `25-full-example` serves over Mooncat.

| # | Example | What it shows | Key API |
|:--:|:--|:--|:--|
| 01 | [`openapi`](01-openapi/) | A text `GET`, a `:param` `GET`, a `POST`; handle a request; emit the OpenAPI 3.1 document | `App::new/get/post`, `text`, `App::handle`, `App::openapi_json` |
| 02 | [`routing`](02-routing/) | Every HTTP verb (`get/post/put/patch/delete` + `route` with `Head`/`Options`), `:param` extraction, 404-vs-405 | `App::route`, `Method`, `Context::param` |
| 03 | [`openapi-versions`](03-openapi-versions/) | One set of routes → Swagger 2.0, OpenAPI 3.0.3, 3.1.0; full `info` metadata; a Swagger UI page | `App::openapi/openapi_json`, `OpenApiVersion`, `Contact`/`License`/`Server`, `swagger_ui` |
| 04 | [`descriptors`](04-descriptors/) | The `Endpoint`/`Param`/`Schema`/`ResponseSpec` tree drives validation and OpenAPI `$ref`s from one source | `Endpoint`, `Param`, `ResponseSpec`, `Context::body_validated` |
| 05 | [`constraints`](05-constraints/) | Every `Constraint` (`Minimum`…`MaxItems`) and scalar type (`SInt/SFloat/SStr/SBool/SNull/SArray/SEnum`) emitted and enforced | `Field::new` constraints, `SEnum`, `Endpoint::validate`, `unprocessable` |
| 06 | [`typed-body`](06-typed-body/) | `body_validated[T]` (validate then deserialise, or `422`) vs the total `body[T]` | `Context::body`, `Context::body_validated`, `GreetReq` |
| 07 | [`request-extractors`](07-request-extractors/) | `query`/`cookie`/`json_field`/`body_json`, params across every `ParamLoc`, hand-built errors | `Context::query/cookie/json_field/body_json`, `ParamLoc`, `ValidationError`, `validation_error_body` |
| 08 | [`response-model`](08-response-model/) | Filter a return value down to a declared model (drop internal fields); the shared conformance check | `json_model`, `filter_response`, `validate_schema`, `schema_of` |
| 09 | [`dependency-injection`](09-dependency-injection/) | `Container` with sub-dependencies, per-request caching, LIFO teardown, `override_`, manual scope | `Container`, `Provider`, `Scope`, `provide/provide_using/override_/run/open_scope` |
| 10 | [`oauth2-jwt`](10-oauth2-jwt/) | `/token` reads the password form and issues an HS256 JWT; a route authenticates and enforces scopes (401/403) | `OAuth2PasswordBearer`, `create_access_token`, `token_response`, `oauth2_password_form`, `AuthenticatedUser` |
| 11 | [`per-op-security`](11-per-op-security/) | A route's `security` is enforced before the handler and emitted as the operation's OpenAPI `security` | `App::secure_oauth2`, `SecurityRequirement`, `App::set_clock` |
| 12 | [`security-schemes`](12-security-schemes/) | Declare every `SecurityScheme`; pull credentials from header/query/cookie and HTTP Basic; emit both spec shapes | `App::add_security_scheme`, `SecurityScheme`, `api_key_header/query/cookie`, `http_basic`, `parse_basic_auth` |
| 13 | [`forms-files`](13-forms-files/) | `Context::form` parses urlencoded and multipart bodies; field, repeated field, and byte-exact file | `Context::form`, `FormData::field/field_all/file`, `UploadFile` |
| 14 | [`background-tasks`](14-background-tasks/) | A handler queues work on `ctx.background`; a layer that notes the last body event shows it runs after the response | `Context.background`, `BackgroundTasks::add_task`, `App::layer`, `@mid.Wrap` |
| 15 | [`mounting`](15-mounting/) | Mount sub-apps under a prefix (nested); merged OpenAPI; the composed `AsgiApp` | `App::mount`, `App::to_asgi` |
| 16 | [`middleware`](16-middleware/) | CORS preflight and actual request, a gzip body round-tripped by `gunzip`, a FastAPI-style middleware, raised exceptions, a custom status page | `App::layer`, `@mid.Cors`, `@mid.Gzip`, `App::middleware`, `http_error`, `App::exception_handler`, `App::add_status_handler` |
| 17 | [`sse`](17-sse/) | Server-Sent Event framing (`data`/`event`/`id`/`retry`/multi-line/comment) streamed one body event per frame | `@sse.Event::of/new/ping`, `sse`, `App::stream`, `@testing.communicate` |
| 18 | [`websocket`](18-websocket/) | A chat room that speaks first and echoes, and a JSON request-reply, driven by the test client | `App::websocket`, `WebSocket::accept/receive/send_text/send_json/close`, `@testing.Client::websocket` |
| 19 | [`json-schema`](19-json-schema/) | A body written as JSON Schema — a `pattern` and a closed set the constructors cannot say — emitted into the document and validated against | `Schema::json`, `Endpoint::new`, `validate_schema` |
| 22 | [`docs-ui`](22-docs-ui/) | The three documentation pages FastAPI serves — the spec, Swagger UI, ReDoc — and how to leave one off | `App::enable_docs`, `swagger_ui`, `redoc_ui`, `html` |
| 23 | [`lifespan`](23-lifespan/) | Startup and shutdown hooks in order, and the lifespan state a request reads, driven by the test client | `App::on_startup`, `App::on_shutdown`, `Context::state`, `@testing.Client::lifespan` |
| 24 | [`files`](24-files/) | Serving a file the way RFC 9110 asks: a 304 for a repeat, a 206 for a resumed download, a 416 for a range that is not there, and the `data:` URL a browser hands back | `Context::serve`, `data_response`, `data_url`, `@conditional.hash` |
| 25 | [`full-example`](25-full-example/) | Root endpoints plus two included routers in a multi-package layout, composed with auth, validation, middleware, forms, files, background tasks, SSE, WebSockets, lifecycle and OpenAPI | `App`, `Router`, `include_router`, `secure_oauth2`, `App::layer`, `stream`, `sse`, `websocket` |
| 26 | [`described-model`](26-described-model/) | One moonmodel description driving both the validation and the document, a reference looked up in `known`, and the report for one that is not there | `Schema::of_model`, `Unresolved`, `Endpoint::validate`, `App::openapi_json` |
| 27 | [`annotations`](27-annotations/) | Routes declared as `#app.get`, `#app.post`, `#app.delete`, `#app.route("PURGE", ...)` and `#router.get`, registered by the generated `routes.g.mbt` | `#app.*`, `#router.*`, `register`, `register_router`, `Other` |

The complete application serves OpenAPI 3.0.3 at `/openapi.json`. Other examples
can emit Swagger 2.0, OpenAPI 3.0.3 or 3.1.0 by passing the corresponding version
to `App::openapi_json`.
