#!/usr/bin/env python3
"""Generate docs/api.html from each package's pkg.generated.mbti + /// doc comments.

The output is deterministic: given the same .mbti files and source /// comments it
produces byte-identical HTML, so the CI step `git diff --exit-code docs/api.html`
stays empty after a re-run.

Run:  python3 scripts/gen_api.py
"""
from __future__ import annotations

import os
import re
import html
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "src")
OUT = os.path.join(ROOT, "docs", "api.html")

# One-line descriptions for the library's own packages. Packages not listed here
# fall back to a generic line built from the import path.
PKG_BLURB = {
    "moonapi": "The application object, response helpers, and the top-level API you build a service from.",
    "ctx": "The per-request context: path, query, header and cookie extraction, body parsing, and state.",
    "di": "Dependency-injection container, providers, and scopes resolved per request.",
    "endpoint": "Typed request parameters and response specifications that describe and validate a route.",
    "exceptions": "HTTP exceptions and the error types the framework raises and renders.",
    "openapi": "The OpenAPI document model and the bundled documentation UIs.",
    "route": "Routers, route tables, class-based views, and mounting sub-applications.",
    "schema": "JSON Schema types, constraints, and validation used for bodies and documents.",
    "security": "Authentication schemes, security requirements, and their runtime enforcers.",
    "socket": "WebSocket connections, messages, and lifecycle handling.",
    "static": "Static file serving with content types and range support.",
    "status": "Response constructors, streaming, server-sent events, and background work.",
    "templates": "Server-side template rendering and the context processors that feed it.",
}

EXCLUDE_DIRS = ("examples", "cmd")
GITHUB_URL = "https://github.com/moonbitstack/moonapi"

RE_PUB = re.compile(
    r"^pub(?:\(open\))?\s+(?:async\s+)?fn\s+([A-Za-z_]\w*)(?:::([A-Za-z_]\w*))?"
)
RE_STRUCT = re.compile(r"^pub(?:\(open\))?\s+struct\s+([A-Za-z_]\w*)")
RE_ENUM = re.compile(r"^pub(?:\(open\))?\s+enum\s+([A-Za-z_]\w*)")
RE_TRAIT = re.compile(r"^pub(?:\(open\))?\s+trait\s+([A-Za-z_]\w*)")
RE_TYPE = re.compile(r"^pub\s+type\s+([A-Za-z_]\w*)")
RE_CONST = re.compile(r"^pub\s+const\s+([A-Za-z_]\w*)")
RE_LET = re.compile(r"^pub\s+let\s+([A-Za-z_]\w*)")
RE_USING = re.compile(r"^pub\s+using\s+@[\w.]+\s*\{\s*(?:type|fn)\s+([A-Za-z_]\w*)")
RE_PARAM = re.compile(r"^([A-Za-z_]\w*)(\?)?\s*:\s*(.+)$")


# --------------------------------------------------------------------------- #
# mbti parsing
# --------------------------------------------------------------------------- #
RE_ITEM_START = re.compile(r"^pub(?:\(open\))?\s")


def split_items(text: str):
    """Yield raw signature blocks from an .mbti file, handling multi-line decls."""
    items, buf, paren, brace = [], [], 0, 0
    started = False
    for raw in text.split("\n"):
        s = raw.strip()
        if not started:
            if RE_ITEM_START.match(s):
                buf = [raw]
                paren = raw.count("(") - raw.count(")")
                brace = raw.count("{") - raw.count("}")
                started = (paren > 0) or (brace > 0)
                if not started:
                    items.append("\n".join(buf))
                    buf, started = [], False
            continue
        buf.append(raw)
        paren += raw.count("(") - raw.count(")")
        brace += raw.count("{") - raw.count("}")
        if paren <= 0 and brace <= 0:
            items.append("\n".join(buf))
            buf, started = [], False
    if buf:
        items.append("\n".join(buf))
    return items


def item_kind(sig: str):
    if RE_PUB.match(sig):
        return "fn"
    if RE_STRUCT.match(sig):
        return "struct"
    if RE_ENUM.match(sig):
        return "enum"
    if RE_TRAIT.match(sig):
        return "trait"
    if RE_TYPE.match(sig):
        return "type"
    if RE_CONST.match(sig):
        return "const"
    if RE_LET.match(sig):
        return "let"
    if RE_USING.match(sig):
        return "using"
    return "other"


def item_name(sig: str):
    m = RE_PUB.match(sig)
    if m:
        return (m.group(1) + "::" + m.group(2)) if m.group(2) else m.group(1)
    for rx in (RE_STRUCT, RE_ENUM, RE_TRAIT, RE_TYPE, RE_CONST, RE_LET, RE_USING):
        m = rx.match(sig)
        if m:
            return m.group(1)
    return None


def collapse(sig: str) -> str:
    return re.sub(r"\s+", " ", sig).strip()


def split_params(sig: str):
    """Return (params_list, return_type) for a function signature."""
    start = sig.find("(")
    if start < 0:
        return [], ""
    depth, i = 0, start
    while i < len(sig):
        if sig[i] == "(":
            depth += 1
        elif sig[i] == ")":
            depth -= 1
            if depth == 0:
                break
        i += 1
    param_str = sig[start + 1 : i]
    rest = sig[i + 1 :]
    # return type: first `->` at paren depth 0 in `rest`
    ret, d = "", 0
    j = 0
    while j < len(rest):
        c = rest[j]
        if c == "(":
            d += 1
        elif c == ")":
            d -= 1
        elif c == "-" and rest[j : j + 2] == "->" and d == 0:
            ret = rest[j + 2 :].strip()
            break
        j += 1
    params = []
    for part in split_top_commas(param_str):
        part = part.strip()
        if not part:
            continue
        if part == "Self":
            continue
        m = RE_PARAM.match(part)
        if m:
            params.append((m.group(1), m.group(3).strip(), m.group(2) is None))
        else:
            params.append(("", part, True))  # unnamed param: type only
    return params, ret


def split_top_commas(s: str):
    out, depth, cur = [], 0, ""
    for ch in s:
        if ch in "([{":
            depth += 1
            cur += ch
        elif ch in ")]}":
            depth -= 1
            cur += ch
        elif ch == "," and depth == 0:
            out.append(cur)
            cur = ""
        else:
            cur += ch
    if cur.strip():
        out.append(cur)
    return out


def struct_fields(sig: str):
    m = re.search(r"\{(.*)\}", sig, re.S)
    if not m:
        return []
    fields = []
    for line in m.group(1).split("\n"):
        line = line.strip().rstrip(",").strip()
        if not line:
            continue
        mut = line.startswith("mut ")
        if mut:
            line = line[4:].strip()
        fm = re.match(r"^([A-Za-z_]\w*)\s*:\s*(.+)$", line)
        if fm:
            fields.append((fm.group(1), fm.group(2).strip(), mut))
    return fields


def enum_variants(sig: str):
    m = re.search(r"\{(.*)\}", sig, re.S)
    if not m:
        return []
    body = m.group(1).strip()
    # variants separated by newlines or `|`
    variants = []
    for part in re.split(r"\n|\|", body):
        part = part.strip().rstrip(",").strip()
        if part:
            variants.append(part)
    return variants


# --------------------------------------------------------------------------- #
# /// doc parsing
# --------------------------------------------------------------------------- #
def collect_docs(pkgdir: str):
    docs = {}
    for fn in sorted(os.listdir(pkgdir)):
        if not fn.endswith(".mbt") or fn.endswith("_wbtest.mbt") or fn.startswith("fixture"):
            continue
        path = os.path.join(pkgdir, fn)
        with open(path, "r", encoding="utf-8") as fh:
            lines = fh.read().split("\n")
        i = 0
        n = len(lines)
        while i < n:
            if lines[i].startswith("///"):
                block = []
                while i < n and lines[i].startswith("///"):
                    block.append(lines[i])
                    i += 1
                j = i
                while j < n and lines[j].strip() == "":
                    j += 1
                decl = lines[j] if j < n else ""
                name = item_name(decl)
                if name:
                    docs[name] = parse_doc(block)
                i = j
            else:
                i += 1
    return docs


def strip_arrow_refs(text: str) -> str:
    """Remove `(← LibraryName's …)` analogy references (e.g. "← FastAPI's `X`").

    The site names no other project, and these cross-references are the only
    place one appears. The parenthesised span goes, counting parens so a code
    sample inside does not end it early; a `←` with no enclosing `(` is dropped
    to the end of the line.
    """
    out = []
    i, n = 0, len(text)
    while i < n:
        if text[i] == "(" and re.match(r"\s*←", text[i + 1 :]):
            depth, j, in_bt = 0, i, False
            while j < n:
                c = text[j]
                if c == "`":
                    in_bt = not in_bt
                elif not in_bt:
                    if c == "(":
                        depth += 1
                    elif c == ")":
                        depth -= 1
                        if depth == 0:
                            break
                j += 1
            i = j + 1
            continue
        if text[i] == "←":
            break
        out.append(text[i])
        i += 1
    return "".join(out).rstrip()


# Names the site leaves out.
BRANDS = ["FastAPI", "Starlette", "Django", "Flask", "Express", "Sanic", "Hug"]


def sanitize_brands(text: str) -> str:
    for b in BRANDS:
        text = re.sub(r"\b" + re.escape(b) + r"\b('s)?", "", text)
    return re.sub(r"\s{2,}", " ", text).strip()


def clean_doc_line(text: str) -> str:
    return sanitize_brands(strip_arrow_refs(text))


def parse_doc(block):
    """Parse a /// block into a list of segments.

    Each segment is either {"t": "p", "html": ...} or {"t": "code", "lang": ..., "code": ...}.
    `///|` becomes a paragraph gap.
    """
    segs = []
    cur = []
    in_code = False
    code_lang = ""
    code_buf = []
    for line in block:
        content = line[3:] if line.startswith("///") else line  # drop `///`
        # strip one leading space if present
        if content.startswith(" "):
            content = content[1:]
        if in_code:
            if content.startswith("```"):
                segs.append({"t": "code", "lang": code_lang, "code": "\n".join(code_buf)})
                code_buf, in_code = [], False
            else:
                code_buf.append(content)
            continue
        if content.startswith("```"):
            if cur:
                segs.append({"t": "p", "html": inline(clean_doc_line(" ".join(cur)))})
                cur = []
            in_code = True
            code_lang = content[3:].strip()
            code_buf = []
            continue
        if content.strip() == "|" or content.strip() == "":
            if cur:
                segs.append({"t": "p", "html": inline(clean_doc_line(" ".join(cur)))})
                cur = []
            continue
        cur.append(clean_doc_line(content))
    if in_code and code_buf:
        segs.append({"t": "code", "lang": code_lang, "code": "\n".join(code_buf)})
    if cur:
        segs.append({"t": "p", "html": inline(clean_doc_line(" ".join(cur)))})
    return segs


def inline(text: str) -> str:
    # escape then re-insert <code> for `backtick` spans
    out = []
    i = 0
    while i < len(text):
        if text[i] == "`" and (i + 1) < len(text) and text[i + 1] != "`":
            j = text.find("`", i + 1)
            if j > i:
                out.append("<code>" + html.escape(text[i + 1 : j]) + "</code>")
                i = j + 1
                continue
        out.append(html.escape(text[i]))
        i += 1
    return "".join(out)


# --------------------------------------------------------------------------- #
# rendering
# --------------------------------------------------------------------------- #
KIND_LABEL = {
    "fn": "function",
    "struct": "struct",
    "enum": "enum",
    "trait": "trait",
    "type": "type",
    "const": "constant",
    "let": "value",
    "using": "re-export",
    "other": "item",
}


def render_doc(segs):
    if not segs:
        return ""
    parts = []
    for s in segs:
        if s["t"] == "p":
            parts.append(f'<p class="doc">{s["html"]}</p>')
        else:
            code = html.escape(s["code"].rstrip("\n"))
            parts.append(
                f'<div class="codewrap ex"><button class="copy" type="button">Copy</button>'
                f'<pre class="sig"><code data-lang="{html.escape(s["lang"])}">{code}</code></pre></div>'
            )
    return "\n".join(parts)


def render_params(params, ret):
    if not params and not ret:
        return ""
    rows = []
    for name, typ, required in params:
        nm = html.escape(name) if name else '<span class="muted">type only</span>'
        req = "required" if required else "optional"
        cls = "" if required else "opt"
        rows.append(
            f"<tr><td class='pname {cls}'>{nm}</td><td><code>{html.escape(typ)}</code></td>"
            f"<td class='{cls}'>{req}</td></tr>"
        )
    param_html = ""
    if rows:
        param_html = (
            '<table class="params"><thead><tr><th>Parameter</th><th>Type</th>'
            "<th>Default</th></tr></thead><tbody>"
            + "".join(rows)
            + "</tbody></table>"
        )
    ret_html = ""
    if ret:
        ret_html = f'<p class="returns">Returns <code>{html.escape(ret)}</code></p>'
    return param_html + ret_html


def render_item(it, docs):
    name = it["name"]
    sig = collapse(it["sig"])
    kind = it["kind"]
    anchor = it["anchor"]
    doc_html = render_doc(docs.get(name))
    extra = ""

    if kind == "struct":
        fields = struct_fields(it["sig"])
        if fields:
            rows = "".join(
                f"<tr><td class='pname'>{html.escape(f[0])}{' <span class=mut>mut</span>' if f[2] else ''}</td>"
                f"<td><code>{html.escape(f[1])}</code></td></tr>"
                for f in fields
            )
            extra = (
                '<table class="params fields"><thead><tr><th>Field</th><th>Type</th>'
                f"</tr></thead><tbody>{rows}</tbody></table>"
            )
    elif kind == "enum":
        variants = enum_variants(it["sig"])
        if variants:
            chips = "".join(f"<li><code>{html.escape(v)}</code></li>" for v in variants)
            extra = f'<ul class="variants">{chips}</ul>'

    params_html = ""
    if kind in ("fn",):
        params, ret = split_params(it["sig"])
        params_html = render_params(params, ret)

    label = KIND_LABEL.get(kind, kind)
    return f"""
<section class="api-item" id="{anchor}">
  <span class="kind kind-{kind}">{label}</span>
  <pre class="sig"><code>{html.escape(sig)}</code></pre>
  {doc_html}
  {params_html}
  {extra}
</section>"""


def build():
    # discover packages
    pkgs = []
    for dirpath, _, files in os.walk(SRC):
        if "pkg.generated.mbti" not in files:
            continue
        rel = os.path.relpath(dirpath, SRC)
        parts = rel.split(os.sep)
        if any(p in EXCLUDE_DIRS for p in parts):
            continue
        pkgs.append(dirpath)
    # order: root first, then alphabetical by alias (last path segment)
    def alias_of(d):
        seg = os.path.basename(d)
        return "moonapi" if d == os.path.join(SRC) else seg

    pkgs.sort(key=lambda d: (d != SRC, alias_of(d)))

    nav_pkgs = []
    sections = []
    for d in pkgs:
        mbti_path = os.path.join(d, "pkg.generated.mbti")
        with open(mbti_path, "r", encoding="utf-8") as fh:
            text = fh.read()
        pkg_line = ""
        for line in text.split("\n"):
            if line.startswith('package "'):
                pkg_line = line.split('"')[1]
                break
        alias = alias_of(d)
        docs = collect_docs(d)

        items = []
        for raw in split_items(text):
            kind = item_kind(raw)
            name = item_name(raw)
            if not name or kind == "other":
                continue
            anchor = f"{alias}-{name.replace('::', '-')}"
            items.append({"kind": kind, "name": name, "sig": raw, "anchor": anchor})

        # group
        types = [i for i in items if i["kind"] in ("struct", "enum", "trait", "type", "using")]
        consts = [i for i in items if i["kind"] in ("const", "let")]
        fns = [i for i in items if i["kind"] == "fn" and "::" not in i["name"]]
        methods = [i for i in items if i["kind"] == "fn" and "::" in i["name"]]
        # methods grouped by owner
        owners = {}
        for m in methods:
            owner = m["name"].split("::")[0]
            owners.setdefault(owner, []).append(m)

        for lst in (types, consts, fns):
            lst.sort(key=lambda x: x["name"].lower())
        for o in owners:
            owners[o].sort(key=lambda x: x["name"].lower())

        blurb = PKG_BLURB.get(alias, f"Package <code>{html.escape(pkg_line)}</code>.")

        nav_pkgs.append((alias, pkg_line, len(items)))

        body = []
        body.append(
            f'<section class="pkg-section" id="pkg-{alias}">'
            f'<h2><span class="at">@</span>{html.escape(alias)}</h2>'
            f'<p class="pkg-desc">{blurb}</p>'
        )
        if types:
            body.append('<h3 class="grp">Types</h3>')
            for it in types:
                body.append(render_item(it, docs))
        if consts:
            body.append('<h3 class="grp">Constants &amp; values</h3>')
            for it in consts:
                body.append(render_item(it, docs))
        if fns:
            body.append('<h3 class="grp">Functions</h3>')
            for it in fns:
                body.append(render_item(it, docs))
        for owner in sorted(owners):
            body.append(f'<h3 class="grp">Methods on <code>{html.escape(owner)}</code></h3>')
            for it in owners[owner]:
                body.append(render_item(it, docs))
        body.append("</section>")
        sections.append("\n".join(body))

    nav_html = render_nav(nav_pkgs)
    sidebar_html = render_sidebar(nav_pkgs)
    full = SHELL.format(
        nav=nav_html,
        sidebar=sidebar_html,
        body="\n".join(sections),
    )
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as fh:
        fh.write(full)
    print(f"wrote {OUT} ({len(sections)} packages, {sum(n for _,_,n in nav_pkgs)} items)")


def render_nav(nav_pkgs):
    items = [
        '<a href="index.html">Home</a>',
        '<a href="guide.html">Guide</a>',
        '<a class="active" href="api.html">API</a>',
        '<a href="examples.html">Examples</a>',
        '<a href="showcase.html">Showcase</a>',
    ]
    gh = (
        f'<a class="gh-link" href="{GITHUB_URL}" target="_blank" rel="noopener" '
        'aria-label="GitHub repository">'
        '<svg viewBox="0 0 16 16" fill="currentColor" aria-hidden="true"><path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 '
        "0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 "
        "1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 "
        "0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 "
        "0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.01 8.01 0 0 0 16 8c0-4.42-3.58-8-8-8Z\"></path></svg>"
        "<span>GitHub</span></a>"
    )
    return (
        '<nav class="nav">' + "".join(items) + '<span class="sep"></span>' + gh + "</nav>"
        '<button class="theme-btn" data-theme-toggle aria-label="Toggle theme">◐</button>'
    )


def render_sidebar(nav_pkgs):
    links = []
    for alias, pkg_line, count in nav_pkgs:
        links.append(
            f'<a href="#pkg-{alias}"><span class="at">@</span>{html.escape(alias)}'
            f'<span class="cnt">{count}</span></a>'
        )
    return "\n".join(links)


SHELL = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>moonapi — API reference</title>
<meta name="description" content="The full API reference for moonapi, a typed web framework for MoonBit.">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Space+Grotesk:wght@400;500;600;700&family=Inter:wght@400;500;600&family=JetBrains+Mono:wght@400;500;600&display=swap" rel="stylesheet">
<link rel="stylesheet" href="assets/base.css">
<link rel="icon" type="image/svg+xml" href="assets/icon.svg">
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
  {nav}
</header>
<div class="layout">
  <aside class="sidebar">
    <h4>Packages</h4>
    <div class="side-nav">
      {sidebar}
    </div>
  </aside>
  <main class="content">
    <article>
      <span class="kicker">API reference</span>
      <h1>Every public type, function and method</h1>
      <p class="lead">The complete surface of the framework, grouped by package. Signatures come
      from the compiled interface; descriptions and examples from the source comments. Each item
      lists its parameters and return type.</p>
      {body}
    </article>
  </main>
</div>
<footer class="site"><div class="foot">
  <span>moonapi — a typed web framework for MoonBit.</span>
  <span class="grow"></span>
  <a href="https://github.com/moonbitstack/moonapi">GitHub</a>
  <a href="index.html">Home</a>
  <a href="guide.html">Guide</a>
  <a href="examples.html">Examples</a>
  <a href="showcase.html">Showcase</a>
</div></footer>
<script src="assets/site.js"></script>
</body>
</html>
"""

if __name__ == "__main__":
    build()
