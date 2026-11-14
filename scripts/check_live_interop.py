#!/usr/bin/env python3
"""Talk to a running service the way other people's software does.

The service is `integration/src/full-example`, a moonapi application served by
mooncat over real sockets. Nothing here is in-process: the requests go out over
TCP as an ordinary client's would, and the answers are read back by libraries
that know nothing about this project — Python's own HTTP client, its
`websockets` client, and the reference MCP client.

    cd integration && moon run src/full-example --target native &
    python3 scripts/check_live_interop.py            # http://127.0.0.1:12000

A refused connection is a failure, not a skip: the point of the run is that a
service is there.
"""
import gzip
import http.client
import json
import os
import socket
import sys
import time

# A client talking to the loopback address is not talking to the internet, so
# the run says so rather than inheriting a proxy from whoever started it: a
# proxied request reaches this service in a form meant for proxies, and the
# failure would look like the service's.
for name in ("HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY",
             "http_proxy", "https_proxy", "all_proxy"):
    os.environ.pop(name, None)

BASE = sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:12000"
HOST, _, PORT = BASE.split("//", 1)[1].partition(":")
PORT = int(PORT or "80")

PASSED = []


def call(method, path, body=None, headers=None):
    conn = http.client.HTTPConnection(HOST, PORT, timeout=10)
    try:
        conn.request(method, path, body=body, headers=headers or {})
        response = conn.getresponse()
        payload = response.read()
        return response.status, dict((k.lower(), v) for k, v in response.getheaders()), payload
    finally:
        conn.close()


def check(name, condition, detail=""):
    if not condition:
        raise SystemExit(f"FAILED {name}: {detail}")
    PASSED.append(name)
    print(f"ok  {name}{(' — ' + detail) if detail else ''}")


def main():
    # A last-resort check that says what went wrong when nothing is listening.
    with socket.socket() as probe:
        probe.settimeout(2)
        if probe.connect_ex((HOST, PORT)) != 0:
            raise SystemExit(f"nothing is listening on {HOST}:{PORT}")

    status, headers, body = call("GET", "/")
    check("a plain text route over HTTP/1.1", status == 200 and body == b"moonapi full example",
          f"{status} {body[:40]!r}")

    status, headers, body = call("GET", "/health")
    check("a JSON route", status == 200 and json.loads(body) == {"detail": "ok"},
          f"{status} {body!r}")

    status, headers, body = call("GET", "/openapi.json")
    document = json.loads(body)
    check("the document a client reads",
          status == 200 and document["openapi"] == "3.0.3" and "/health" in document["paths"],
          f"{status}, openapi {document['openapi']}, {len(document['paths'])} paths")

    status, headers, body = call("GET", "/docs")
    check("the page a reader opens",
          status == 200 and "text/html" in headers.get("content-type", "")
          and b"swagger-ui" in body.lower(),
          f"{status}, {headers.get('content-type')}")

    status, headers, body = call("GET", "/SKILL.md")
    check("the skill an agent reads",
          status == 200 and "text/markdown" in headers.get("content-type", "")
          and b"/mcp" in body,
          f"{status}, {len(body)} bytes")

    status, headers, body = call(
        "POST", "/token",
        body="grant_type=password&username=demo&password=demo",
        headers={"content-type": "application/x-www-form-urlencoded"},
    )
    token = json.loads(body).get("access_token", "") if status == 200 else ""
    check("an OAuth2 password grant", status == 200 and token.count(".") == 2,
          f"{status}, token of {len(token)} characters")

    status, headers, body = call(
        "GET", "/api/v1/accounts/me",
        headers={"authorization": "Bearer " + token, "cookie": "display_name=Ada"},
    )
    profile = json.loads(body) if status == 200 else {}
    check("a route behind a bearer token, with response_model filtering",
          status == 200 and profile.get("name") == "Ada" and "email" not in profile,
          f"{status}, fields {sorted(profile)}")
    check("the cookie the handler set",
          "last_seen=today" in headers.get("set-cookie", ""),
          headers.get("set-cookie", "(none)"))

    status, headers, body = call("GET", "/api/v1/accounts/me")
    check("the same route without a token", status == 401,
          f"{status}, {headers.get('www-authenticate')}")

    status, headers, body = call("GET", "/api/v1/catalog/?q=cat")
    check("a query parameter", status == 200 and json.loads(body) == {"detail": "query=cat"},
          f"{status} {body!r}")

    status, headers, body = call(
        "GET", "/api/v1/catalog/large", headers={"accept-encoding": "gzip"})
    plain = gzip.decompress(body) if headers.get("content-encoding") == "gzip" else body
    check("a gzip layer a client can undo",
          status == 200 and headers.get("content-encoding") == "gzip"
          and plain.startswith(b"compressible response"),
          f"{status}, {len(body)} compressed bytes, {len(plain)} plain")

    status, headers, body = call("POST", "/api/v1/catalog/orders")
    check("a route that queues work after the response", status == 202 and body == b"order accepted",
          f"{status} {body!r}")

    status, headers, body = call("GET", "/nope")
    check("a 404", status == 404 and json.loads(body) == {"detail": "not found"},
          f"{status} {body!r}")

    status, headers, body = call("PUT", "/health")
    check("a 405 that names the methods",
          status == 405 and "GET" in headers.get("allow", ""),
          f"{status}, allow {headers.get('allow')}")

    conn = http.client.HTTPConnection(HOST, PORT, timeout=10)
    try:
        conn.request("GET", "/api/v1/catalog/events", headers={"accept": "text/event-stream"})
        response = conn.getresponse()
        first = response.read1(200)
    finally:
        conn.close()
    check("a server-sent event", b"data: catalog-ready" in first, repr(first[:60]))

    from websockets.sync.client import connect

    with connect(f"ws://{HOST}:{PORT}/api/v1/catalog/ws/7", open_timeout=10) as ws:
        ws.send("hello")
        reply = ws.recv(timeout=10)
    check("a WebSocket a client can hold", reply == "echo: hello", repr(reply))

    head_at, status, kind = mcp_listen()
    check("the MCP listening stream answers its head at once",
          status == 200 and kind.startswith("text/event-stream") and head_at < 1.0,
          f"{status} {kind} after {head_at:.2f}s")

    mcp_tools, mcp_answer = mcp_round_trip()
    check("the MCP service, through the reference client",
          "get_health" in mcp_tools and mcp_answer == "ok",
          f"{len(mcp_tools)} tools, get_health -> {mcp_answer!r}")

    print(f"\n{len(PASSED)} checks passed against {BASE}")


def mcp_listen():
    """Open the stream a 2025-06-18 client listens on, and time its head: no event is due on
    it, so a server that held the head until the first one would leave the client waiting."""
    conn = http.client.HTTPConnection(HOST, PORT, timeout=10)
    try:
        begin = time.monotonic()
        conn.request("GET", "/mcp", headers={
            "accept": "text/event-stream",
            "mcp-protocol-version": "2025-06-18",
        })
        response = conn.getresponse()
        return time.monotonic() - begin, response.status, response.getheader("content-type", "")
    finally:
        conn.close()


def mcp_round_trip():
    """List the tools and call one, with the reference client library."""
    import anyio
    from mcp import ClientSession
    from mcp.client.streamable_http import streamable_http_client

    async def run():
        async with streamable_http_client(f"{BASE}/mcp") as (read, write):
            async with ClientSession(read, write) as session:
                await session.initialize()
                tools = [tool.name for tool in (await session.list_tools()).tools]
                result = await session.call_tool("get_health", {})
                text = "".join(
                    part.text for part in result.content if getattr(part, "type", "") == "text"
                )
                detail = json.loads(text).get("detail", text) if text else ""
                return tools, detail

    return anyio.run(run)


if __name__ == "__main__":
    main()
