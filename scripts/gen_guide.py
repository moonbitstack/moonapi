#!/usr/bin/env python3
"""Write the code and the recorded output of docs/guide.html from src/examples/guide.

Each way of writing routes has a package there: `ann` (annotations), `fns` (one call per route)
and `cls` (types implementing `View`), plus `annapi` for the OpenAPI section. A block between
`// guide:<name>` and `// end` is a snippet; the page shows it as written. `check` runs every
request of the guide against all three and fails if they answer differently; its output is what
the page records.

    python3 scripts/gen_guide.py           rewrite docs/guide.html
    python3 scripts/gen_guide.py --check   fail if docs/guide.html is not what this would write
"""
import html
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "src" / "examples" / "guide"
GUIDE = ROOT / "docs" / "guide.html"


def snippets(path):
    text = (SRC / path).read_text(encoding="utf-8").replace("\r\n", "\n")
    out = {}
    for m in re.finditer(r"^( *)// guide:([a-z.]+)\n(.*?)^ *// end\n", text, re.S | re.M):
        indent = len(m.group(1))
        body = "\n".join(line[indent:] for line in m.group(3).rstrip("\n").split("\n"))
        out[m.group(2)] = body.replace("{  }", "{}")
    return out


ANN = {**snippets("ann/routes.mbt"), **snippets("annapi/routes.mbt")}
FNS = snippets("fns/fns.mbt")
CLS = snippets("cls/cls.mbt")
TYPED = ANN["typed"].split("#app.post")[0].rstrip()


def code(text):
    return ('<div class="codewrap"><button class="copy" type="button">Copy</button>'
            '<pre class="hl"><code>' + html.escape(text, quote=False) + "</code></pre></div>")


def group(key, ann_note="", fns_note="", cls_note=""):
    a, f = ANN[key], FNS[key]
    c = CLS[key] + "\n\n" + CLS[key + ".register"]
    if key == "typed":
        f = TYPED + "\n\n" + f
        c = TYPED + "\n\n" + c
    if key == "first":
        a = a + "\n\nlet app = @moonapi.App::new()\nregister(app)"
        f = "let app = @moonapi.App::new()\n" + f
        c = c.replace(CLS["first.register"], "let app = @moonapi.App::new()\n" + CLS["first.register"])

    def variant(name, text, note):
        extra = f"\n    {note}" if note else ""
        return f'  <div class="variant" data-style="{name}">\n    {code(text)}{extra}\n  </div>'

    return ('<div class="styles">\n' + variant("annotations", a, ann_note) + "\n"
            + variant("functions", f, fns_note) + "\n" + variant("classes", c, cls_note) + "\n</div>")


def recorded():
    run = subprocess.run(["moon", "run", "src/examples/guide/check", "--target", "native"], cwd=ROOT,
                         capture_output=True, text=True, encoding="utf-8")
    out = run.stdout
    if run.returncode != 0 or "OPENAPI " not in out:
        sys.exit("the guide's check program failed:\n" + out + run.stderr)
    if "DIFFERS" in out:
        sys.exit("the three ways of writing the guide answer differently:\n" + out)
    got = {}
    for line in out.splitlines():
        if " -> " in line:
            key, value = line.split(" -> ", 1)
            got[key] = value
    doc = out[out.index("OPENAPI ") + 8 : out.index("openapi same:")].rstrip()
    return got, doc


def ecosystem():
    """Run the ecosystem example's check: its three registrations must answer alike.

    The guide's own three variants are compared by `check`; the example beside
    them is the same property on a bigger surface — a database, a document and a
    guard — so it is driven here rather than in a step of its own.
    """
    run = subprocess.run(["moon", "run", "src/check", "--target", "native"],
                         cwd=ROOT / "integration", capture_output=True, text=True, encoding="utf-8")
    if run.returncode != 0 or "same:" not in run.stdout:
        sys.exit("the ecosystem example's check failed://n" + run.stdout + run.stderr)


def bar(title):
    return ('<div class="term">\n    <div class="term-bar"><span class="dot r"></span><span class="dot y"></span>'
            f'<span class="dot g"></span><span class="title">{html.escape(title)}</span></div>\n')


def term(title, rows):
    """Request and response pairs, the request column padded so the arrows line up."""
    width = max(len(r) for r, _ in rows) + 2
    body = []
    for req, resp in rows:
        status, _, rest = resp.partition(" ")
        body.append(f'<span class="ok">{html.escape(req)}</span>{" " * (width - len(req))}'
                    f'<span class="accent">-&gt; {status}</span> {html.escape(rest)}'.rstrip())
    return bar(title) + '    <div class="term-body">' + "\n".join(body) + "</div>\n  </div>"


def plain(title, text):
    return bar(title) + '    <div class="term-body">' + html.escape(text, quote=False) + "</div>\n  </div>"


def sections(got, doc):
    def pick(keys):
        return [(k, got[k]) for k in keys]

    first = group(
        "first",
        ann_note='<p>The generator reads the annotations at build time and writes <code>register(app)</code>. Wire it into the build once: a <code>rule</code> in <code>moon.mod</code> running <code>moonx moonbitstack/moonapi/cmd/routes</code>, and a <code>dev_build</code> in the package\'s <code>moon.pkg</code>; the README has both lines.</p>',
        fns_note="<p>Each route is one call on the app: the verb, the path template and the handler. Annotations generate exactly these calls, and routes built at run time are written this way.</p>",
        cls_note="<p>A type implementing <code>View</code> answers the methods of one path, and <code>app.view</code> registers each method it answers. A method it leaves out answers <code>405</code>, with <code>Allow</code> listing the ones it does answer.</p>",
    )
    handle = code('let response = app.handle({\n  http_method: "GET",\n  path: "/users/42",\n  query_string: b"",\n  headers: [],\n  body: b"",\n})\nresponse.status // 200')
    return {
        "1. INSTALL": f"""<h2 id="install">1 · Install and your first application</h2>
  <p class="sub">Add the package with <code>moon add moonbitstack/moonapi</code>. A handler receives a context and returns a response. Routes can be written three ways, and the switch at the top of the page picks which one every example shows: annotations on handler functions, one call per route, or a type that answers the methods of a path. All three build the same application.</p>

  {first}

  <p>A moonapi application is just a value. You can run a request through it in-process with <code>App::handle</code>, which returns a response you can inspect — useful for tests and for the demos on this page.</p>

  {handle}

  <p>When no handler matches the path, you get <code>404</code>; when the path exists but not for that method, you get <code>405</code>. Both are produced by the framework, not written by hand.</p>

  {term("recorded · App::handle", pick(["GET /", "GET /users/42", "POST /users", "GET /missing", "DELETE /"]))}

  """,
        "2. ROUTING": f"""<h2 id="routing">2 · Routes, verbs and path parameters</h2>
  <p class="sub">A <code>{{name}}</code> piece in the path becomes a parameter you read from the context. Every HTTP verb has its own annotation, method and <code>View</code> method, and <code>App::route</code> or <code>#app.route</code> attaches any other.</p>

  {group("verbs")}

  {term("recorded · every verb", pick(["GET /items/233", "POST /items", "PUT /items/233", "PATCH /items/233", "DELETE /items/233", "HEAD /items", "OPTIONS /items", "GET /items"]))}

  """,
        "3. REQUEST DATA": f"""<h2 id="request">3 · Reading the request</h2>
  <p class="sub">The context exposes the path, the query string, the headers and the body. Each extractor returns an option, so you handle the missing case inline.</p>

  {group("query")}

  {term("recorded · App::handle", pick(["GET /search?q=cat&limit=5"]))}

  <p>For a JSON body, <code>Context::body_json</code> returns the parsed value, or <code>None</code> if the body is not valid JSON.</p>

  {group("body")}

  {term("recorded · App::handle", [('POST /login {"user":"heke","pass":"s3cret"}', got["POST /login"])])}

  """,
        "4. TYPED BODY": f"""<h2 id="typed">4 · Typed bodies and validation</h2>
  <p class="sub">When the payload matters, ask for a typed value. <code>Context::body_validated</code> checks the JSON against a descriptor and deserialises into a <code>derive(FromJson)</code> struct; if it does not conform you receive located errors instead of a crash.</p>

  {group("typed")}

  {term("recorded · validated extraction", [('POST /greet {"name":"lfanke"}', got["POST /greet ok"]), ('POST /greet {"name":233}', got["POST /greet 233"]), ("POST /greet", got["POST /greet none"])])}

  """,
        "6. ERRORS": f"""<h2 id="errors">6 · Errors as values</h2>
  <p class="sub">Raise a typed <code>HttpException</code> from anywhere in a handler; the framework turns it into a response with the status and detail you gave it.</p>

  {group("errors")}

  {term("recorded · App::handle", pick(["GET /boom"]))}

  """,
        "7. OPENAPI": f"""<h2 id="openapi">7 · Generating an OpenAPI document</h2>
  <p class="sub">Give each route a summary and tags and the application can emit an OpenAPI 3.1 document on demand. Serve it at <code>/openapi.json</code> or hand it to a documentation UI.</p>

  {group("openapi", cls_note="<p><code>app.view</code> takes the tags its methods share. A summary belongs to one method and is given with an annotation or a call, so this document carries the tags but no summaries.</p>")}

  {code("let doc = app.openapi_json(version=OpenApi31)")}

  {plain("recorded · openapi_json", doc)}

  """,
    }


def render(page, parts):
    marks = ["1. INSTALL", "2. ROUTING", "3. REQUEST DATA", "4. TYPED BODY", "5. DI", "6. ERRORS", "7. OPENAPI", "8. RUN"]
    starts = [page.index(f"<!-- ============ {m} ============ -->\n  ") for m in marks]
    out = page[: starts[0]]
    for i, mark in enumerate(marks[:-1]):
        tag = f"<!-- ============ {mark} ============ -->\n  "
        out += tag + (parts[mark] if mark in parts else page[starts[i] + len(tag) : starts[i + 1]])
    return out + page[starts[-1]:]


def main():
    ecosystem()
    page = GUIDE.read_text(encoding="utf-8")
    got, doc = recorded()
    new = render(page, sections(got, doc))
    if "--check" in sys.argv:
        if new != page:
            sys.exit("docs/guide.html is out of date with src/examples/guide; run scripts/gen_guide.py")
        print("docs/guide.html is up to date")
        return
    GUIDE.write_text(new, encoding="utf-8", newline="\n")
    print("wrote docs/guide.html")


main()
