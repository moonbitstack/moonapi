# Examples

A runnable tour of the public `@moonapi` API. Each folder is a `main` package
that builds an `App` from typed routes (or a descriptor / crypto value) and uses
it, printing the actual result so running the example proves the feature works.

```bash
moon run examples/01-openapi
```

Everything runs in-process through `App::handle` / `drive_websocket`, so every
example works on every backend; a server such as
[`mooncat`](https://github.com/moonbitstack/mooncat) runs the same `App::to_asgi`
over a real transport.

| # | Example | What it shows | Key API |
| --- | --- | --- | --- |
| 01 | [`openapi`](01-openapi/) | A text `GET`, a `:param` `GET`, a `POST`; handle a request; emit the OpenAPI 3.1 document | `App::new/get/post`, `text`, `App::handle`, `App::openapi_json` |
| 02 | [`routing`](02-routing/) | Every HTTP verb (`get/post/put/patch/delete` + `route` with `Head`/`Options`), `:param` extraction, 404-vs-405 | `App::route`, `Method`, `Context::param` |
| 03 | [`openapi-versions`](03-openapi-versions/) | One set of routes → Swagger 2.0, OpenAPI 3.0.3, 3.1.0; full `info` metadata; a Swagger UI page | `App::openapi/openapi_json`, `OpenApiVersion`, `Contact`/`License`/`Server`, `swagger_ui` |
| 04 | [`descriptors`](04-descriptors/) | The `Endpoint`/`Param`/`Schema`/`ResponseSpec` tree drives validation and OpenAPI `$ref`s from one source | `demo_app`, `Endpoint`, `Param`, `ResponseSpec`, `json_field` |
| 05 | [`constraints`](05-constraints/) | Every `Constraint` (`Minimum`…`MaxItems`) and scalar type (`SInt/SFloat/SStr/SBool/SNull/SArray/SEnum`) emitted and enforced | `Field::new` constraints, `SEnum`, `Endpoint::validate`, `unprocessable` |
| 06 | [`typed-body`](06-typed-body/) | `body_validated[T]` (validate then deserialise, or `422`) vs the total `body[T]` | `Context::body`, `Context::body_validated`, `GreetReq` |
| 07 | [`request-extractors`](07-request-extractors/) | `query`/`cookie`/`json_field`/`body_json`, params across every `ParamLoc`, hand-built errors | `Context::query/cookie/json_field/body_json`, `ParamLoc`, `ValidationError`, `validation_error_body` |
| 08 | [`response-model`](08-response-model/) | Filter a return value down to a declared model (drop internal fields); the shared conformance check | `json_model`, `filter_response`, `validate_schema`, `schema_of` |
| 09 | [`dependency-injection`](09-dependency-injection/) | `Container` with sub-dependencies, per-request caching, LIFO teardown, `override_`, manual scope | `Container`, `Provider`, `Scope`, `provide/provide_using/override_/run/open_scope` |
| 10 | [`oauth2-jwt`](10-oauth2-jwt/) | `/token` reads the password form and issues an HS256 JWT; a route authenticates and enforces scopes (401/403) | `OAuth2PasswordBearer`, `create_access_token`, `token_response`, `oauth2_password_form`, `AuthenticatedUser` |
| 11 | [`per-op-security`](11-per-op-security/) | A route's `security` is enforced before the handler and emitted as the operation's OpenAPI `security` | `App::secure_oauth2`, `SecurityRequirement`, `App::set_clock` |
| 12 | [`security-schemes`](12-security-schemes/) | Declare every `SecurityScheme`; pull credentials from header/query/cookie and HTTP Basic; emit both spec shapes | `App::add_security_scheme`, `SecurityScheme`, `api_key_header/query/cookie`, `http_basic`, `parse_basic_auth` |
| 13 | [`forms-files`](13-forms-files/) | `Context::form` parses urlencoded and multipart bodies; field, repeated field, and byte-exact file | `Context::form`, `FormData::field/field_all/file`, `UploadFile` |
| 14 | [`background-tasks`](14-background-tasks/) | A `route_bg` queues work that runs after the response; `handle_with_background` vs `handle` | `App::route_bg`, `BackgroundTasks::add_task/len/run`, `App::handle_with_background` |
| 15 | [`mounting`](15-mounting/) | Mount sub-apps under a prefix (nested); merged OpenAPI; the composed `AsgiApp` | `App::mount`, `App::to_asgi` |
| 16 | [`middleware`](16-middleware/) | CORS preflight/actual, real DEFLATE `gzip` round-tripped by `inflate`, raised exceptions, custom status page | `App::middleware`, `cors`, `gzip`, `inflate`, `http_error`, `App::exception_handler`, `App::add_status_handler` |
| 17 | [`sse`](17-sse/) | Server-Sent Event framing (`data`/`event`/`id`/`retry`/multi-line/comment) and the `text/event-stream` envelope | `ServerSentEvent::data/new/keep_alive/encode`, `sse_response` |
| 18 | [`websocket`](18-websocket/) | Echo and request-reply handlers driven against an in-memory frame queue; the recorded events | `App::websocket`, `drive_websocket`, `WebSocket::accept/receive/send/close`, `WsMessage` |

| 22 | [`docs-ui`](22-docs-ui/) | The three documentation pages FastAPI serves — the spec, Swagger UI, ReDoc — and how to leave one off | `App::enable_docs`, `swagger_ui`, `redoc_ui`, `html` |
| 23 | [`lifespan`](23-lifespan/) | Startup and shutdown hooks, run through the moonasgi lifespan core so the order is visible without a server | `App::on_startup`, `App::on_shutdown`, `App::lifespan_handler` |

The document `openapi_json(version=OpenApi31)` prints is the same one a server
([`mooncat`](https://github.com/moonbitstack/mooncat)) serves at `/openapi.json`
after `App::to_asgi`; swap `OpenApi31` for `OpenApi30` or `Swagger20` to emit the
other spec versions off the identical routes.
