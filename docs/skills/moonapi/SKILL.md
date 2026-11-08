---
name: moonapi
description: "A typed web framework for MoonBit: routes, typed request extraction, validation, OpenAPI and documentation. Use it to build an HTTP API or to read one this project already serves."
---

# moonapi

Add `moonbitstack/moonapi`, and for serving it `moonbitstack/mooncat` plus
`moonbitlang/async`:

```
moon add moonbitstack/moonapi
```

```moon.pkg
import {
  "moonbitstack/moonapi",
}
```

A handler is `async (Context) -> Response`. `text`, `html`, `json` and
`redirect` build one; `ctx.param`, `ctx.query` and `ctx.body_json` read the
request. `App::handle` drives the application in-process, through the same path a
server does, which is enough to test one without a socket.

## A route, its parameters and its document

```moonbit
async test {
  let app = @moonapi.App::new()
  app.get(
    "/pets/{id}",
    ctx =>
      @moonapi.json(200, Json({ "id": Json(ctx.param("id").unwrap_or("")) })),
    summary="Fetch one pet",
  )
  app.describe(title="petstore", api_version="1.0.0")
  let reply = app.handle({
    http_method: "GET",
    path: "/pets/7",
    query_string: b"",
    headers: [],
    body: b"",
  })
  assert_eq(reply.status, 200)
  assert_eq(@utf8.decode_lossy(reply.body), "{\"id\":\"7\"}")
}
```

The same description is a document: `app.openapi_json()` writes OpenAPI 3.1,
`version=OpenApi30` and `version=Swagger20` the other two, and `/openapi.json`,
`/docs`, `/redoc` and `/redocly` serve it to a person.

## What a route takes and what it answers

A route carries its whole description — the tag it belongs to, what it returns,
the security it wants — and validation comes from the same descriptor:

```moonbit
async test {
  let app = @moonapi.App::new()
  app.post(
    "/pets",
    ctx => @moonapi.json(201, Json({ "made": ctx.body_json().unwrap_or(Json::null()) })),
    summary="Add a pet",
    status_code=201,
    tags=["pets"],
  )
  let reply = app.handle({
    http_method: "POST",
    path: "/pets",
    query_string: b"",
    headers: [("content-type", "application/json")],
    body: @utf8.encode("{\"name\":\"Rex\"}"),
  })
  assert_eq(reply.status, 201)
  assert_eq(@utf8.decode_lossy(reply.body), "{\"made\":{\"name\":\"Rex\"}}")
}
```

Serving is one call to a server, which is not a dependency of this library:
`@mooncat.serve(app.to_asgi(), port=12000)` runs the application a test just
drove. `App::to_asgi()` is the whole contract — layers, mounts, lifespan hooks
and disconnect handling included.

## Handing the API to an agent

`moonbitstack/moonapi/agent` turns the document into an MCP service and a skill,
mounted like the pages are:

```moonbit
async test {
  let app = @moonapi.App::new()
  app.get("/pets", _ctx => @moonapi.text(200, "pets"), summary="List pets")
  app.describe(title="petstore")
  @agent.expose(app)
  let skill = app.handle({
    http_method: "GET",
    path: "/SKILL.md",
    query_string: b"",
    headers: [],
    body: b"",
  })
  assert_eq(skill.status, 200)
  assert_eq(
    @utf8.decode_lossy(skill.body).contains("| `get_pets` | `GET /pets` |"),
    true,
  )
}
```

## Rules that catch people out

- A handler that does not await anything is written `ctx => ...`; the `get` /
  `post` / … methods take only `async (Context) -> Response`.
- Where the expected type is known, a constructor is written without the package
  — `version=OpenApi31`, `Param::new("id", InPath, schema=SInt)`. A raised error
  is the exception: `raise @exceptions.HttpException(...)`.
- The annotation forms (`#app.get(...)`) need a build rule from
  `moonbitstack/moonapi/cmd/routes` that generates `register`; without it the
  methods above are the whole surface.
- `App::to_asgi` adds the documentation routes once, when the application first
  becomes an ASGI application — a route of your own at `/docs` wins over them.
- The MCP tools call the routes in-process, so they answer exactly what a client
  answers, and they appear only for operations the document lists.
