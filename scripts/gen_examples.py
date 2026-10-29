#!/usr/bin/env python3
"""Build docs/examples.html from src/examples: one card per example with a
snippet from its source and a link to it. Deterministic, so CI can diff it."""
import os
import re
import html
import glob
import textwrap

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EX = os.path.join(ROOT, "src", "examples")
OUT = os.path.join(ROOT, "docs", "examples.html")
GITHUB = "https://github.com/moonbitstack/moonapi"

# Names the site leaves out.
BRANDS = ["FastAPI", "Starlette", "Django", "Flask", "Express", "Sanic", "Hug"]
RE_BRAND = re.compile(r" ?\b(?:" + "|".join(BRANDS) + r")\b")

# (directory, group, title, description)
META = {
    "01-openapi": (
        "Start here", "OpenAPI out of the box",
        "Register a few routes, run a request in-process, then emit the OpenAPI 3.1 document the routes describe.",
    ),
    "02-routing": (
        "Start here", "Routing, verbs and path parameters",
        "Bind every HTTP verb, capture a {id} path parameter, and see the framework return 404 or 405 on its own.",
    ),
    "03-openapi-versions": (
        "OpenAPI & docs UI", "Three spec versions from one app",
        "The same routes serialise as Swagger 2.0, OpenAPI 3.0 and OpenAPI 3.1 — pick the dialect a tool expects.",
    ),
    "04-descriptors": (
        "Bodies & validation", "Validate against a descriptor",
        "An endpoint descriptor checks the request; a body that breaks it comes back with located errors.",
    ),
    "05-constraints": (
        "Bodies & validation", "Field constraints",
        "Constrain fields with patterns, ranges and shapes, then validate the whole request at the boundary.",
    ),
    "06-typed-body": (
        "Bodies & validation", "Typed bodies, two ways",
        "Validated extraction returns located errors; unchecked extraction returns a total option. Choose per route.",
    ),
    "07-request-extractors": (
        "Bodies & validation", "Typed request extractors",
        "Declare a path, query, header and cookie parameter once; the endpoint validates and binds them for you.",
    ),
    "08-response-model": (
        "Bodies & validation", "Response models",
        "Build a full internal record, then project only the safe fields through a response model.",
    ),
    "09-dependency-injection": (
        "Dependency injection", "A request-scoped container",
        "Register services by name; the container builds, caches and tears them down once per request.",
    ),
    "10-oauth2-jwt": (
        "Security", "OAuth2 password flow with JWT",
        "Accept a password form, mint a signed access token, and return it in the standard token response.",
    ),
    "11-per-op-security": (
        "Security", "Per-operation security",
        "Attach a security requirement to a route so the guard must admit the request before the handler runs.",
    ),
    "12-security-schemes": (
        "Security", "API keys, bearer, basic, OAuth2",
        "Declare every scheme the API accepts and read a credential from each carrier in one route.",
    ),
    "13-forms-files": (
        "Composition & middleware", "Forms and file uploads",
        "Parse multipart forms, read individual fields and files, and enforce upload size limits.",
    ),
    "14-background-tasks": (
        "Composition & middleware", "Work after the response",
        "A wrapping layer runs a task once the response body has been sent to the client.",
    ),
    "15-mounting": (
        "Composition & middleware", "Mount sub-applications",
        "Build a small admin app and an API app, then mount them at their own prefixes under one root.",
    ),
    "16-middleware": (
        "Composition & middleware", "CORS, gzip and custom middleware",
        "Add CORS and gzip as layers and slip a custom middleware into the request/response chain.",
    ),
    "17-sse": (
        "Streaming & realtime", "Server-sent events",
        "Stream events to the client and honour the Last-Event-ID header for a clean resume.",
    ),
    "18-websocket": (
        "Streaming & realtime", "WebSockets",
        "Hold a live WebSocket connection in a room route and a streaming sum route.",
    ),
    "19-json-schema": (
        "Bodies & validation", "Inspect the emitted JSON schema",
        "See exactly what schema a typed body contributes to the generated OpenAPI document.",
    ),
    "22-docs-ui": (
        "OpenAPI & docs UI", "Serve the docs UI",
        "Enable the bundled UI and hit /openapi.json, /docs and /redoc for the live specification.",
    ),
    "23-lifespan": (
        "Composition & middleware", "Startup and shutdown hooks",
        "Run code when the server starts and stops, and share state across the lifespan.",
    ),
    "24-files": (
        "Composition & middleware", "Serve files and data URLs",
        "Stream a file with an etag and turn an inline data URL into a served response.",
    ),
    "25-full-example": (
        "Full system", "One service, every feature",
        "An integrated application: routers, auth, typed bodies, layers, DI, files, tasks, SSE, WebSockets and OpenAPI.",
    ),
    "26-described-model": (
        "Bodies & validation", "Describe then validate",
        "Attach a field-level description to a model and validate the request against it.",
    ),
    "27-annotations": (
        "Composition & middleware", "Annotation routes and routers",
        "Write routes as annotations, group them in a router, and include the router under a prefix.",
    ),
    "28-templates": (
        "Templates", "Render HTML templates",
        "Render pages with the template engine, extend a base layout, and build URLs by name.",
    ),
}

# Display order of the groups.
GROUP_ORDER = [
    "Start here",
    "Bodies & validation",
    "Dependency injection",
    "Security",
    "Composition & middleware",
    "Streaming & realtime",
    "Templates",
    "OpenAPI & docs UI",
    "Full system",
]


def snippet(dirname: str) -> str:
    """Extract a representative, compilable-looking code preview from an example."""
    base = os.path.join(EX, dirname)
    main = os.path.join(base, "main.mbt")
    if not os.path.exists(main):
        found = glob.glob(os.path.join(base, "**", "*.mbt"), recursive=True)
        if not found:
            return ""
        main = sorted(found)[0]
    lines = open(main, encoding="utf-8").read().splitlines()

    # Find a natural anchor: app construction, a DI enum, or first real code.
    start = None
    for i, ln in enumerate(lines):
        s = ln.strip()
        if s.startswith("let app =") or "App::new" in s or s.startswith("let _ =") or s.startswith("enum Dep"):
            start = i
            break
    if start is None:
        for i, ln in enumerate(lines):
            s = ln.strip()
            if s and not s.startswith("///"):
                start = i
                break
    if start is None:
        start = 0

    picked = []
    for ln in lines[start:]:
        if ln.lstrip().startswith("///"):
            continue  # drop doc comments from the preview
        picked.append(ln)
        if len(picked) >= 12:
            break
    while picked and picked[-1].strip() == "":
        picked.pop()

    text = textwrap.dedent("\n".join(picked))
    return RE_BRAND.sub("", text).strip("\n")


def esc(s: str) -> str:
    return html.escape(s, quote=False)


def card(dirname: str, title: str, desc: str) -> str:
    snip = snippet(dirname)
    src = f"{GITHUB}/tree/master/src/examples/{dirname}"
    body = esc(snip) if snip else "<span class='muted'>(no preview)</span>"
    return f"""    <article class="ex-card">
      <span class="tag">{esc(dirname)}</span>
      <h3>{esc(title)}</h3>
      <p>{esc(desc)}</p>
      <div class="codewrap"><pre><code>{body}</code></pre></div>
      <a class="src" href="{src}" target="_blank" rel="noopener">View source on GitHub &rarr;</a>
    </article>"""


def group_block(group: str) -> str:
    dirs = [d for d in META if META[d][0] == group]
    cards = "\n".join(card(d, META[d][1], META[d][2]) for d in dirs)
    return f"""  <section class="section ex-group">
    <h2>{esc(group)}</h2>
    <p class="sub">{esc(GROUP_SUB.get(group, ''))}</p>
    <div class="ex-grid">
{cards}
    </div>
  </section>"""


GROUP_SUB = {
    "Start here": "Two small programs that show the shape of every moonapi service: routes in, response out, document on demand.",
    "Bodies & validation": "Turn a request into a typed, checked value — and decide exactly what the response reveals.",
    "Dependency injection": "Share services across handlers without threading them through every call.",
    "Security": "Declare how requests prove who they are, and attach the proof each route needs.",
    "Composition & middleware": "Stack layers, mount sub-apps, and wire the lifecycle around a single application.",
    "Streaming & realtime": "Hold a connection open and push data as it arrives.",
    "Templates": "Render HTML from templates and build links by route name.",
    "OpenAPI & docs UI": "Generate the contract and serve it where tools can read it.",
    "Full system": "Everything above, composed into one running service.",
}


NAV = (
    '<nav class="nav">'
    '<a href="index.html">Home</a>'
    '<a href="guide.html">Guide</a>'
    '<a href="api.html">API</a>'
    '<a href="examples.html">Examples</a>'
    '<a href="showcase.html">Showcase</a>'
    '<span class="sep"></span>'
    '<a class="gh-link" href="' + GITHUB + '" target="_blank" rel="noopener" aria-label="GitHub repository">'
    '<svg viewBox="0 0 16 16" fill="currentColor" aria-hidden="true"><path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 '
    "0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 "
    "1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 "
    "0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 "
    "0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.01 8.01 0 0 0 16 8c0-4.42-3.58-8-8-8Z\"></path></svg>"
    "<span>GitHub</span></a>"
    "</nav>"
    '<button class="theme-btn" data-theme-toggle aria-label="Toggle theme">◐</button>'
)

HEADER = f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>moonapi — Examples</title>
<meta name="description" content="Every runnable moonapi example, grouped by what it shows: routing, validation, dependency injection, security, streaming, templates and a full integrated service.">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Space+Grotesk:wght@400;500;600;700&family=Inter:wght@400;500;600&family=JetBrains+Mono:wght@400;500;600&display=swap" rel="stylesheet">
<link rel="stylesheet" href="assets/base.css">

<script type="module" src="assets/scrollbar.js"></script><link rel="icon" type="image/svg+xml" href="assets/icon.svg">
</head>
<body>
<header class="topbar">
  <a class="brand" href="index.html">
    <svg class="mark" viewBox="0 0 32 32" fill="none" aria-hidden="true">
      <circle cx="16" cy="16" r="14" fill="#FFF2E0" stroke="#898AC4" stroke-width="2"/>
      <path d="M11 21c4 3 6 3 10 0M12.5 13.5a1.6 1.6 0 1 1 0 3.2 1.6 1.6 0 0 1 0-3.2Zm7 0a1.6 1.6 0 1 1 0 3.2 1.6 1.6 0 0 1 0-3.2Z" stroke="#898AC4" stroke-width="2" stroke-linecap="round"/>
    </svg>
    <span class="name">moon<b>api</b></span>
  </a>
  {NAV}
</header>

<section class="hero">
  <div class="hero-inner">
    <span class="eyebrow">Examples</span>
    <h1>Run every feature. <span class="grad">Twenty-six ways</span> to build with moonapi.</h1>
    <p class="lede">Each example in <code>src/examples/</code> is a small, runnable program. Below they are grouped by what they show — from a two-route hello world to a full service that uses every part of the framework. Open any card's source, or run it yourself:</p>
    <div class="install">
      <span class="pmt">$</span>
      <code>moon run src/examples/02-routing --target native</code>
      <button class="copy" type="button">Copy</button>
    </div>
    <div class="hero-cta">
      <a class="btn btn-primary" href="#Start here">Start with the basics</a>
      <a class="btn btn-ghost" href="#Full system">See the full system</a>
    </div>
  </div>
</section>
"""

FOOTER = """<footer class="site">
  <div class="foot">
    <span>moonapi · a typed web framework for MoonBit</span>
    <span class="grow"></span>
    <a href="https://github.com/moonbitstack/moonapi" target="_blank" rel="noopener">GitHub</a>
    <a href="index.html">Home</a>
    <a href="guide.html">Guide</a>
    <a href="api.html">API</a>
    <a href="showcase.html">Showcase</a>
  </div>
</footer>
<script src="assets/site.js"></script>
</body>
</html>
"""


def build():
    blocks = [group_block(g) for g in GROUP_ORDER if any(d for d in META if META[d][0] == g)]
    doc = HEADER + "\n".join(blocks) + "\n" + FOOTER
    with open(OUT, "w", encoding="utf-8") as fh:
        fh.write(doc)
    print(f"wrote {OUT} ({len(META)} examples across {len(GROUP_ORDER)} groups)")


if __name__ == "__main__":
    build()
