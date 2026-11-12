#!/usr/bin/env python3
"""Compare this framework's answers with two mature ones, request by request.

The route table below is the same one `integration/src/differential` registers:
a static path, a typed converter, a query, created resources, a method a path
does not answer, and a trailing slash. Each request is sent to Starlette and to
FastAPI, and their answers are compared with the lines our own build printed —
status, the set of methods a 405 allows, the location of a redirect, and the
body of a successful answer.

    (cd integration && moon run src/differential --target native) > ours.jsonl
    python3 scripts/diff_http_semantics.py ours.jsonl

Status is compared for every request, and the body wherever the application
wrote it: a framework's own 404 text is its own, and the comparison is about the
routing decisions, not about who words a refusal how.

Two answers are compared by what they mean rather than by their spelling:

* `Location` may be absolute or relative (RFC 9110 §10.2.2), so only its path
  and query are compared.
* `Allow` must name every method the path answers (RFC 9110 §15.5.6). Both
  references name only what the first route registered for the path happens to
  carry — `/items/{id}` answers `GET` and `DELETE`, and they report `GET` — so
  the comparison asks that ours contains theirs and says so when it does not,
  rather than copying an answer that leaves out a method the path serves.

Two cases are compared with Starlette alone, because FastAPI answers them
differently from Starlette itself:

* `/users/abc`: FastAPI decides a parameter's type after the route matched, so
  the request reaches the handler and comes back `422`; here the converter is
  part of the path, so the route does not match and the answer is `404`.
* `HEAD /search`: Starlette answers a `GET` route to `HEAD`; FastAPI answers
  `405`. This framework takes Starlette's side.
"""
import json
import sys
from urllib.parse import urlsplit

from fastapi import FastAPI
from fastapi.responses import JSONResponse, PlainTextResponse, Response
from starlette.applications import Starlette
from starlette.routing import Route
from starlette.testclient import TestClient

# (method, target). Kept in step with integration/src/differential/main.mbt.
CASES = [
    ("GET", "/"),
    ("POST", "/users"),
    ("GET", "/users/42"),
    ("GET", "/users/abc"),
    ("GET", "/search?q=cat&limit=5"),
    ("HEAD", "/search"),
    ("OPTIONS", "/items"),
    ("GET", "/items/9"),
    ("DELETE", "/items/9"),
    ("PUT", "/items/9"),
    ("GET", "/items"),
    ("GET", "/missing"),
    ("GET", "/items/9/"),
    ("POST", "/users/"),
]

# Compared with Starlette only, and why.
STARLETTE_ONLY = {
    ("GET", "/users/abc"): "FastAPI checks the type after routing and answers 422",
    ("HEAD", "/search"): "FastAPI answers 405 where Starlette answers the GET route",
}

# Bodies are compared where the application produced them; a refusal is worded
# by each framework in its own way.
COMPARE_BODY = {200, 201}

FAILURES = []


def starlette_app():
    async def root(request):
        return PlainTextResponse("root")

    async def create_user(request):
        return PlainTextResponse("created", status_code=201)

    async def user(request):
        return PlainTextResponse("user " + str(request.path_params["id"]))

    async def search(request):
        return JSONResponse(
            {"q": request.query_params.get("q", ""),
             "limit": request.query_params.get("limit", "")}
        )

    async def item(request):
        return PlainTextResponse("item " + request.path_params["id"])

    async def create_item(request):
        return PlainTextResponse("created", status_code=201)

    async def delete_item(request):
        return Response(status_code=204)

    async def options_item(request):
        return Response(status_code=204)

    return Starlette(
        routes=[
            Route("/", root, methods=["GET"]),
            Route("/users", create_user, methods=["POST"]),
            Route("/users/{id:int}", user, methods=["GET"]),
            Route("/search", search, methods=["GET"]),
            Route("/items/{id}", item, methods=["GET"]),
            Route("/items", create_item, methods=["POST"]),
            Route("/items/{id}", delete_item, methods=["DELETE"]),
            Route("/items", options_item, methods=["OPTIONS"]),
        ]
    )


def fastapi_app():
    app = FastAPI()

    @app.get("/")
    async def root():
        return PlainTextResponse("root")

    @app.post("/users", status_code=201)
    async def create_user():
        return PlainTextResponse("created", status_code=201)

    @app.get("/users/{user_id}")
    async def user(user_id: int):
        return PlainTextResponse("user " + str(user_id))

    @app.get("/search")
    async def search(q: str = "", limit: str = ""):
        return JSONResponse({"q": q, "limit": limit})

    @app.get("/items/{item_id}")
    async def item(item_id: str):
        return PlainTextResponse("item " + item_id)

    @app.post("/items", status_code=201)
    async def create_item():
        return PlainTextResponse("created", status_code=201)

    @app.delete("/items/{item_id}")
    async def delete_item(item_id: str):
        return Response(status_code=204)

    @app.options("/items")
    async def options_item():
        return Response(status_code=204)

    return app


def allow_set(response):
    value = response.headers.get("allow")
    if value is None:
        return None
    return sorted(m.strip() for m in value.split(",") if m.strip())


def ask(client, method, target, follow):
    response = client.request(method, target, follow_redirects=follow)
    return {
        "status": response.status_code,
        "allow": allow_set(response),
        "location": response.headers.get("location"),
        "body": response.text,
    }


def location_path(value):
    if value is None:
        return None
    parts = urlsplit(value)
    return parts.path + (("?" + parts.query) if parts.query else "")


def compare(name, method, target, ours, theirs):
    where = f"{method} {target}"
    if ours["status"] != theirs["status"]:
        FAILURES.append(f"{name}: {where}: status {ours['status']} vs {theirs['status']}")
        return
    if theirs["allow"] is not None:
        missing = [m for m in theirs["allow"] if m not in (ours["allow"] or [])]
        if missing:
            FAILURES.append(
                f"{name}: {where}: allow {ours['allow']} leaves out {missing}"
            )
    if location_path(ours["location"]) != location_path(theirs["location"]):
        FAILURES.append(
            f"{name}: {where}: location {ours['location']} vs {theirs['location']}"
        )
    if ours["status"] in COMPARE_BODY and method != "HEAD":
        if ours["body"] != theirs["body"]:
            FAILURES.append(
                f"{name}: {where}: body {ours['body']!r} vs {theirs['body']!r}"
            )


def main():
    if len(sys.argv) != 2:
        raise SystemExit("usage: diff_http_semantics.py <ours.jsonl>")
    ours = [json.loads(line) for line in open(sys.argv[1], encoding="utf-8") if line.strip()]
    print(f"compared against two implementations: {len(ours)} requests, "
          f"{len(CASES)} in the table")
    if len(ours) != len(CASES):
        raise SystemExit(
            f"the build answered {len(ours)} requests, the table has {len(CASES)}: "
            "the two files disagree about the cases"
        )
    starlette = TestClient(starlette_app())
    fastapi = TestClient(fastapi_app())
    for line, (method, target) in zip(ours, CASES):
        if (method, target) != (line["method"], line["path"]):
            raise SystemExit(
                f"line {line['method']} {line['path']} is not the next case "
                f"{method} {target}"
            )
        compare("starlette", method, target, line, ask(starlette, method, target, False))
        if (method, target) not in STARLETTE_ONLY:
            compare("fastapi", method, target, line, ask(fastapi, method, target, False))
        else:
            print(f"  {method} {target}: Starlette only — {STARLETTE_ONLY[(method, target)]}")
    if FAILURES:
        print(f"\n{len(FAILURES)} differences:")
        for failure in FAILURES:
            print("  " + failure)
        raise SystemExit(1)
    print(
        f"all {len(CASES)} requests agree with Starlette, "
        f"{len(CASES) - len(STARLETTE_ONLY)} of them with FastAPI too"
    )


if __name__ == "__main__":
    main()
