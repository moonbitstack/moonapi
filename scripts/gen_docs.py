#!/usr/bin/env python3
"""Generate a self-contained, styled API-reference site (docs/index.html) for
gh-pages from the package sources' `///` doc comments. Reproducible: reads the
.mbt files, so the docs never drift from the code."""
import re, html, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
# One section per package. Files are collected from the directory, so moving
# code between files or packages cannot leave the reference behind.
SECTIONS = [
    ("app", ".", "Application",
     "The App and everything it does: the route builders (get / post / stream / "
     "...), include_router, mounting, layers and middleware, the security wiring "
     "that enforces a scheme before a handler, WebSocket routes, the OpenAPI "
     "document, lifespan, and to_asgi, the ASGI application a server runs."),
    ("route", "route", "Routes & routers",
     "Route and Router: the record an app keeps per operation, routers that "
     "collect routes away from any application and fold in under a prefix, and "
     "how a path is cut into segments and matched. Method is moonhttp's: the nine "
     "standard methods and Other for any extension token."),
    ("routes", "cmd/routes", "Route annotations",
     "#app.get, #router.post, #app.route(method, path) and #app.websocket on free "
     "functions, turned into register(app) and register_router(router) by a "
     "generator that moonx runs as a dev_build rule. The README shows the wiring; "
     "example 27 is a complete package."),
    ("ctx", "ctx", "Request context & extractors",
     "The Context and everything read from it: path, query, header and cookie "
     "parameters, the JSON body (raw, typed with derive(FromJson), or validated), "
     "forms and uploads, the credential each security scheme carries, conditional "
     "and partial serving, and the background tasks run after the response."),
    ("endpoint", "endpoint", "Endpoint descriptors",
     "Param, ResponseSpec and Endpoint: what an operation declares, walked once "
     "into an OpenAPI operation and once into the validation of a request against "
     "the same declaration."),
    ("schema", "schema", "Schemas & validation",
     "The runtime Schema that stands in for FastAPI's reflection over signatures, "
     "the constraints a value carries, ValidationError and the 422 it becomes, "
     "response_model projection, and Schema::of_model for a moonmodel description."),
    ("openapi", "openapi", "OpenAPI document",
     "The document's info block and how routes become operations, in Swagger 2.0, "
     "OpenAPI 3.0 and 3.1 from the same routes, plus Swagger UI and ReDoc pages."),
    ("security", "security", "Security",
     "OAuth2 password bearer and code flows, HTTP bearer, basic and digest, API "
     "keys: the schemes emitted into the document, the guards that answer 401 and "
     "403, per-operation requirements, and access tokens signed through mooncred."),
    ("exceptions", "exceptions", "Errors",
     "HttpException and the exception handlers that turn a raised error into its "
     "response, with a 500 fallback. CORS, gzip and the host checks are moonasgi "
     "layers, added with App::layer."),
    ("socket", "socket", "WebSocket",
     "The live connection a WebSocket route's async handler holds: accept, the "
     "receive and send calls for text, bytes and JSON, close, and Disconnected, "
     "raised when the client leaves."),
    ("status", "status", "Responses & status codes",
     "text, html, json, redirects, downloads, data: URLs, cookies, streams written "
     "as they go and Server-Sent Events over them, plus the 63 HTTP_* and 15 WS_* constants FastAPI re-exports from "
     "Starlette."),
    ("di", "di", "Dependency injection",
     "Providers, scopes and dependency_overrides: request-scoped resolution with "
     "per-request caching and teardown run in reverse around the handler, "
     "FastAPI's Depends in explicit form."),
]
KIND = {"struct": "struct", "enum": "enum", "fn": "fn", "type": "type", "let": "let"}


def parse(path):
    items, doc = [], []
    lines = path.read_text(encoding="utf-8").splitlines()
    i = 0
    while i < len(lines):
        s = lines[i].strip()
        if s == "///|":
            doc = []
        elif s.startswith("///"):
            doc.append(s[3:].strip())
        elif s.startswith("pub"):
            buf = s
            is_alias = re.match(r"pub\s+(type|let)\b", buf) is not None
            while (not is_alias and "{" not in buf and i + 1 < len(lines)):
                i += 1
                buf += " " + lines[i].strip()
            core = re.sub(r"\s*\{.*$", "", buf)
            core = re.sub(r"^pub(?:\(all\))?\s+", "", core).strip()
            core = re.sub(r"\s+", " ", core).rstrip(",").rstrip()
            core = re.sub(r",\s*\)", ")", core)
            first = core.split(" ")[0] if core else ""
            items.append((KIND.get(first, "item"), core, " ".join(doc).strip()))
            doc = []
        elif s == "":
            pass
        else:
            doc = []
        i += 1
    return items


def tint(sig):
    s = html.escape(sig)
    s = re.sub(r"\b(fn|struct|enum|type|let|async)\b", r'<span class="k">\1</span>', s)
    s = re.sub(r"\b([A-Z][A-Za-z0-9_]*)\b", r'<span class="ty">\1</span>', s)
    s = s.replace("-&gt;", '<span class="op">-&gt;</span>').replace("?", '<span class="op">?</span>')
    return s


def prose(t):
    t = html.escape(t)
    return re.sub(r"`([^`]+)`", r"<code>\1</code>", t)


CSS = r"""
:root{
  --bg:#fbfbfd; --panel:#ffffff; --panel-2:#f6f7fb; --ink:#14181f;
  --muted:#5b6675; --line:#e8ebf1; --accent:#6d5efc; --accent-soft:#efecff; --out:#0ca678;
  --code-bg:#f4f5f9; --shadow:0 1px 2px rgba(20,24,31,.04),0 8px 24px -12px rgba(20,24,31,.10);
}
@media (prefers-color-scheme:dark){:root{
  --bg:#0b0e14; --panel:#131722; --panel-2:#0f131c; --ink:#e9edf6; --muted:#96a1b5;
  --line:#212736; --accent:#9d8bff; --accent-soft:#1c1b3a; --out:#2dd4a7;
  --code-bg:#161b26; --shadow:0 1px 2px rgba(0,0,0,.3),0 12px 30px -14px rgba(0,0,0,.5);
}}
:root[data-theme=light]{--bg:#fbfbfd;--panel:#fff;--panel-2:#f6f7fb;--ink:#14181f;--muted:#5b6675;--line:#e8ebf1;--accent:#6d5efc;--accent-soft:#efecff;--out:#0ca678;--code-bg:#f4f5f9;--shadow:0 1px 2px rgba(20,24,31,.04),0 8px 24px -12px rgba(20,24,31,.10)}
:root[data-theme=dark]{--bg:#0b0e14;--panel:#131722;--panel-2:#0f131c;--ink:#e9edf6;--muted:#96a1b5;--line:#212736;--accent:#9d8bff;--accent-soft:#1c1b3a;--out:#2dd4a7;--code-bg:#161b26;--shadow:0 1px 2px rgba(0,0,0,.3),0 12px 30px -14px rgba(0,0,0,.5)}
*{box-sizing:border-box}
html{scroll-behavior:smooth}
@media (prefers-reduced-motion:reduce){html{scroll-behavior:auto}*{animation:none!important;transition:none!important}}
body{margin:0;background:var(--bg);color:var(--ink);
  font-family:"IBM Plex Sans",system-ui,-apple-system,Segoe UI,Roboto,sans-serif;
  font-size:15.5px;line-height:1.6;-webkit-font-smoothing:antialiased}
code,pre,.mono{font-family:"IBM Plex Mono",ui-monospace,SFMono-Regular,Menlo,Consolas,monospace}
a{color:var(--accent);text-decoration:none}
a:hover{text-decoration:underline}
.layout{display:grid;grid-template-columns:264px minmax(0,1fr);max-width:1180px;margin:0 auto}
.sidebar{position:sticky;top:0;align-self:start;height:100vh;overflow-y:auto;
  border-right:1px solid var(--line);padding:1.6rem 1.1rem 2rem;background:var(--panel-2)}
.brand{display:flex;align-items:center;gap:.55rem;font-family:"IBM Plex Mono";font-weight:600;
  font-size:1.35rem;letter-spacing:-.01em;color:var(--ink);margin-bottom:.15rem}
.brand .dot{width:11px;height:11px;border-radius:50%;background:var(--accent);box-shadow:0 0 0 4px var(--accent-soft)}
.brand-sub{color:var(--muted);font-size:.8rem;margin:0 0 1.3rem;padding-left:.15rem}
.side-nav{display:flex;flex-direction:column;gap:.1rem}
.side-nav a{color:var(--muted);font-size:.9rem;padding:.32rem .6rem;border-radius:8px;
  font-family:"IBM Plex Mono";display:flex;align-items:center;gap:.4rem;border-left:2px solid transparent}
.side-nav a .at{color:var(--accent);opacity:.6}
.side-nav a:hover{background:var(--accent-soft);color:var(--ink);text-decoration:none}
.side-nav a.active{color:var(--ink);background:var(--accent-soft);border-left-color:var(--accent);font-weight:500}
.side-nav a.active .at{opacity:1}
.side-foot{margin-top:1.6rem;padding-top:1.1rem;border-top:1px solid var(--line);display:flex;flex-wrap:wrap;gap:.4rem}
.side-foot img{height:20px;display:block}
.theme-btn{margin-top:1rem;background:none;border:1px solid var(--line);color:var(--muted);
  border-radius:8px;padding:.35rem .6rem;font:inherit;font-size:.82rem;cursor:pointer;width:100%}
.theme-btn:hover{border-color:var(--accent);color:var(--ink)}
main{padding:2.6rem 2.4rem 5rem;min-width:0}
.hero h1{font-family:"IBM Plex Mono";font-weight:600;font-size:2.9rem;letter-spacing:-.02em;margin:0}
.hero .tag{color:var(--muted);font-size:1.12rem;max-width:62ch;margin:.5rem 0 1.1rem;text-wrap:balance}
.badges{display:flex;flex-wrap:wrap;gap:.45rem;margin:0 0 1.4rem}
.badges img{height:21px;display:block}
.install{display:flex;align-items:center;gap:.6rem;background:var(--panel);border:1px solid var(--line);
  border-radius:12px;padding:.65rem 1rem;box-shadow:var(--shadow);max-width:420px}
.install .prompt{color:var(--out);user-select:none;font-weight:600}
.install code{flex:1;font-size:.95rem}
.copy{background:none;border:1px solid var(--line);border-radius:7px;color:var(--muted);
  cursor:pointer;font:inherit;font-size:.72rem;padding:.2rem .5rem}
.copy:hover{border-color:var(--accent);color:var(--accent)}
.copy.ok{color:var(--out);border-color:var(--out)}
.contract{margin:2.1rem 0 .5rem;background:
   radial-gradient(120% 130% at 100% 0%, var(--accent-soft) 0%, transparent 55%), var(--panel);
  border:1px solid var(--line);border-radius:16px;padding:1.2rem 1.4rem;box-shadow:var(--shadow)}
.contract h2{margin:0 0 .6rem;font-size:1.06rem;display:flex;align-items:center;gap:.5rem}
.contract h2 .spark{color:var(--accent)}
.contract pre{margin:0;overflow-x:auto;font-size:.92rem;line-height:1.7}
.contract .k{color:#8b5cf6;font-weight:500}.contract .ty{color:var(--accent)}.contract .op{color:var(--muted)}
section.pkg{scroll-margin-top:1.2rem;padding-top:2.4rem;margin-top:2rem;border-top:1px solid var(--line)}
section.pkg > h2{font-family:"IBM Plex Mono";font-size:1.55rem;margin:0 0 .15rem;letter-spacing:-.01em}
section.pkg > h2 .at{color:var(--accent)}
.pdesc{color:var(--muted);margin:.15rem 0 1.2rem;max-width:72ch}
.item{background:var(--panel);border:1px solid var(--line);border-radius:13px;
  padding:1rem 1.2rem;margin:.85rem 0;box-shadow:var(--shadow);transition:border-color .15s,transform .15s}
.item:hover{border-color:color-mix(in oklab,var(--accent) 40%,var(--line))}
.kind{display:inline-block;font-size:.66rem;font-weight:600;text-transform:uppercase;letter-spacing:.08em;
  border-radius:6px;padding:.1rem .45rem;margin-bottom:.55rem;
  color:var(--accent);background:var(--accent-soft);border:1px solid color-mix(in oklab,var(--accent) 26%,transparent)}
.item[data-k=struct] .kind{--c:#8b5cf6}.item[data-k=fn] .kind{--c:#0ca678}.item[data-k=let] .kind{--c:#2563eb}
.item[data-k=enum] .kind{--c:#d6336c}.item[data-k=type] .kind{--c:#0891b2}
.item .kind{color:var(--c,var(--accent));background:color-mix(in oklab,var(--c,var(--accent)) 13%,transparent);
  border-color:color-mix(in oklab,var(--c,var(--accent)) 30%,transparent)}
.sig{font-size:.98rem;margin:0 0 .55rem;overflow-x:auto;white-space:pre;color:var(--ink);padding-bottom:.15rem}
.sig .k{color:#8b5cf6;font-weight:500}.sig .ty{color:var(--accent)}.sig .op{color:var(--muted)}
@media (prefers-color-scheme:dark){.sig .k,.contract .k{color:#b794ff}}
.doc{margin:0;color:var(--ink);max-width:76ch}
.doc code{background:var(--code-bg);padding:.06rem .35rem;border-radius:5px;font-size:.9em;color:var(--accent)}
footer{margin-top:3rem;padding-top:1.3rem;border-top:1px solid var(--line);color:var(--muted);font-size:.9rem}
@media (max-width:820px){
  .layout{grid-template-columns:1fr}
  .sidebar{position:static;height:auto;border-right:none;border-bottom:1px solid var(--line)}
  .side-nav{flex-flow:row wrap}.side-nav a{border-left:none}.side-nav a.active{border-left:none}
  main{padding:1.8rem 1.2rem 4rem}.hero h1{font-size:2.2rem}
}
"""

JS = r"""
document.addEventListener("DOMContentLoaded",()=>{
  document.querySelectorAll("[data-copy]").forEach(btn=>btn.addEventListener("click",()=>{
    navigator.clipboard.writeText(btn.getAttribute("data-copy")).then(()=>{
      const t=btn.textContent;btn.textContent="copied";btn.classList.add("ok");
      setTimeout(()=>{btn.textContent=t;btn.classList.remove("ok");},1100);});}));
  const links=[...document.querySelectorAll(".side-nav a")];
  const map=Object.fromEntries(links.map(a=>[a.getAttribute("href").slice(1),a]));
  const spy=new IntersectionObserver(es=>{es.forEach(e=>{if(e.isIntersecting){
    links.forEach(a=>a.classList.remove("active"));const a=map[e.target.id];if(a)a.classList.add("active");}});},
    {rootMargin:"-10% 0px -80% 0px"});
  document.querySelectorAll("section.pkg").forEach(s=>spy.observe(s));
  const tb=document.getElementById("theme");if(tb)tb.addEventListener("click",()=>{
    const cur=document.documentElement.getAttribute("data-theme")
      ||(matchMedia("(prefers-color-scheme:dark)").matches?"dark":"light");
    document.documentElement.setAttribute("data-theme",cur==="dark"?"light":"dark");});
});
"""

CONTRACT = """let app = @moonapi.App::new()
app.get("/users/:id", ctx => @moonapi.text(200, "user " + ctx.param("id").unwrap()))

let spec = app.openapi_json(version=@moonapi.OpenApi31)   // also @moonapi.OpenApi30 / @moonapi.Swagger20
@mooncat.serve(app.to_asgi())                              // 127.0.0.1:12000"""


def esc(t):
    return html.escape(t)


def main():
    HEAD = ('<!doctype html><html lang="en"><head><meta charset="utf-8">'
            '<meta name="viewport" content="width=device-width,initial-scale=1">'
            '<title>moonapi — MoonBit web framework API</title>'
            '<link rel="preconnect" href="https://fonts.googleapis.com">'
            '<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>'
            '<link href="https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;500;600&'
            'family=IBM+Plex+Sans:wght@400;500;600&display=swap" rel="stylesheet">'
            '<style>' + CSS + '</style></head><body>')

    side = ['<aside class="sidebar"><div class="brand"><span class="dot"></span>moonapi</div>'
            '<p class="brand-sub">MoonBit web framework — API reference</p><nav class="side-nav">']
    side += ['<a href="#%s"><span class="at">§</span>%s</a>' % (sid, title)
             for sid, _, title, _ in SECTIONS]
    side += ['</nav>'
             '<button class="theme-btn" id="theme">◐ toggle theme</button>'
             '<div class="side-foot">'
             '<a href="https://github.com/moonbitstack/moonapi/actions"><img alt="CI" src="https://img.shields.io/github/actions/workflow/status/moonbitstack/moonapi/ci.yml?branch=master&label=CI&logo=github"></a>'
             '<a href="https://mooncakes.io/docs/moonbitstack/moonapi"><img alt="mooncakes" src="https://img.shields.io/badge/mooncakes-Lfan--ke%2Fmoonapi-1f6feb"></a>'
             '</div></aside>']

    hero = ('<main><header class="hero"><h1>moonapi</h1>'
            '<p class="tag">A typed web framework for MoonBit &#8212; FastAPI-style routing and '
            'multi-version OpenAPI, on the moonasgi SEAM. Backend-agnostic &#8212; the async '
            'transport lives in the server (mooncat) that runs the app.</p>'
            '<div class="badges">'
            '<a href="https://github.com/moonbitstack/moonapi/actions"><img alt="CI" src="https://img.shields.io/github/actions/workflow/status/moonbitstack/moonapi/ci.yml?branch=master&label=CI&logo=github"></a>'
            '<a href="https://github.com/moonbitstack/moonapi"><img alt="GitHub" src="https://img.shields.io/badge/GitHub-source-24292f?logo=github"></a>'
            '<img alt="license" src="https://img.shields.io/badge/license-Apache--2.0-6d5efc"></div>'
            '<div class="install"><span class="prompt">$</span><code>moon add moonbitstack/moonapi</code>'
            '<button class="copy" data-copy="moon add moonbitstack/moonapi">copy</button></div>'
            '<div class="contract"><h2><span class="spark">&#10038;</span> The contract at a glance</h2>'
            '<pre>' + tint(CONTRACT) + '</pre></div>'
            '<div class="contract"><h2>Run the full example</h2>'
            '<p class="pdesc">Start the native Mooncat server on Windows, macOS or Linux:</p>'
            '<pre>moon run src/examples/25-full-example --target native</pre>'
            '<p class="doc"><a href="http://127.0.0.1:12000/docs">Swagger UI</a> · '
            '<a href="http://127.0.0.1:12000/redoc">ReDoc</a> · '
            '<a href="http://127.0.0.1:12000/openapi.json">OpenAPI 3.0.3</a> · '
            '<a href="https://github.com/moonbitstack/moonapi/blob/master/src/examples/README.md#full-example-api">API route list</a></p></div></header>')

    body = [HEAD, '<div class="layout">'] + side + [hero]
    total = 0
    for sid, rel, title, desc in SECTIONS:
        body.append('<section class="pkg" id="%s"><h2><span class="at">§</span>%s</h2>'
                    '<p class="pdesc">%s</p>' % (sid, title, esc(desc)))
        files = sorted(f for f in (ROOT / "src" / rel).glob("*.mbt")
                       if not f.name.endswith(("_wbtest.mbt", "_test.mbt")))
        for kind, sig, doc in [it for f in files for it in parse(f)]:
            total += 1
            body.append('<div class="item" data-k="%s"><span class="kind">%s</span>'
                        '<pre class="sig">%s</pre>%s</div>'
                        % (kind, kind, tint(sig), ('<p class="doc">%s</p>' % prose(doc)) if doc else ''))
        body.append('</section>')
    body.append('<footer>Generated from source <code>///</code> doc-comments · '
                '<a href="https://mooncakes.io/docs/moonbitstack/moonapi">mooncakes</a> · '
                '<a href="https://github.com/moonbitstack/moonapi">GitHub</a> · Apache-2.0 &#169; Leo Cheng</footer>')
    body.append('</main></div><script>' + JS + '</script></body></html>')

    out = ROOT / "docs" / "index.html"
    out.parent.mkdir(exist_ok=True)
    out.write_text("\n".join(body), encoding="utf-8")
    print("wrote %s (%d public items across %d sections)" % (out, total, len(SECTIONS)))


if __name__ == "__main__":
    main()
