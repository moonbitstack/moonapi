// The pages an application serves to describe itself: Swagger UI, ReDoc, the
// Redocly reference and the Scalar reference, each of them reading the one
// document the application publishes. A page wears the site's theme unless told
// otherwise, and a plain page is the reader's own look, untouched.

///|
/// Which reader a page serves. `Scalar` is the current generation of API
/// reference, with a request client built in; `Swagger` is Swagger UI, the
/// long-standing one; `Redoc` reads without letting a caller try anything, and
/// `Redocly` is Redocly's own reference, which needs a licence key.
#derive(Eq, Debug)
pub(all) enum Ui {
  Scalar
  Swagger
  Redoc
  Redocly
}

///|
pub extend Ui with Eq::{equal, not_equal}

///|
pub extend Ui with Debug::{to_repr}

///|
/// How a page looks. `Site` is the theme of this library's own site: the
/// periwinkle paper, the iris accent, the display face and the thin scrollbars,
/// on a bar naming the application and pointing at its document. `Plain` is the
/// reader as its maker ships it — no bar, no fonts, no colours of ours — for a
/// page that is dropped into a site of its own.
#derive(Eq, Debug)
pub(all) enum Theme {
  Site
  Plain
}

///|
pub extend Theme with Eq::{equal, not_equal}

///|
pub extend Theme with Debug::{to_repr}

///|
/// The theme a page wears unless told otherwise.
pub let theme : Theme = Site

///|
/// The pages load their readers from a CDN at an exact version, so a page does
/// not change under an application that did not change. Self-hosting is a
/// matter of passing other URLs.
pub let swagger_js : String = "https://cdn.jsdelivr.net/npm/swagger-ui-dist@5.34.1/swagger-ui-bundle.js"

///|
pub let swagger_css : String = "https://cdn.jsdelivr.net/npm/swagger-ui-dist@5.34.1/swagger-ui.css"

///|
pub let swagger_redirect_js : String = "https://cdn.jsdelivr.net/npm/swagger-ui-dist@5.34.1/oauth2-redirect.js"

///|
pub let redoc_js : String = "https://cdn.jsdelivr.net/npm/redoc@3.1.0/bundles/redoc.standalone.js"

///|
pub let scalar_js : String = "https://cdn.jsdelivr.net/npm/@scalar/api-reference@1.77.0/dist/browser/standalone.js"

///|
/// Redocly's reference is served from Redocly's own CDN and is licensed per
/// deployment: the page carries the licence key its options name.
pub let redocly_js : String = "https://cdn.redoc.ly/reference-docs/v2.45.14/redocly-reference-docs.min.js"

///|
/// The faces the site's theme is set in. Only the weights the pages use are
/// asked for: a page that pulls a family's whole range delays its own text.
let site_fonts : String = "https://fonts.googleapis.com/css2?family=Space+Grotesk:wght@500;600&family=Inter:wght@400;500;600&family=JetBrains+Mono:wght@400;500&display=swap"

///|
/// `s` escaped for HTML text and attribute values.
fn html_escape(s : String) -> String {
  let out = StringBuilder()
  for c in s {
    match c {
      '&' => out.write_string("&amp;")
      '<' => out.write_string("&lt;")
      '>' => out.write_string("&gt;")
      '"' => out.write_string("&quot;")
      '\'' => out.write_string("&#39;")
      _ => out.write_char(c)
    }
  }
  out.to_string()
}

///|
/// `j` as a script literal. JSON is a subset of JavaScript; `<` is escaped too,
/// so no value can close the `<script>` it sits in.
fn script_json(j : Json) -> String {
  @moonjson.dumps(j).replace_all(old="<", new="\\u003c")
}

///|
/// The last segment of a path, which is what a page calls the document it reads.
fn last_segment(path : String) -> String {
  let parts = path.split("/").to_array()
  let mut i = parts.length() - 1
  while i > 0 && parts[i].length() == 0 {
    i = i - 1
  }
  parts[i].to_owned()
}

///|
/// The mark the site uses, small enough to sit on the bar and in a tab.
fn site_mark() -> String {
  "<svg viewBox=\"0 0 32 32\" fill=\"none\" aria-hidden=\"true\"><circle cx=\"16\" cy=\"16\" r=\"14\" fill=\"#898AC4\" stroke=\"#FFF2E0\" stroke-width=\"2\"></circle><path d=\"M11 21c4 3 6 3 10 0M12.5 13.5a1.6 1.6 0 1 1 0 3.2 1.6 1.6 0 0 1 0-3.2Zm7 0a1.6 1.6 0 1 1 0 3.2 1.6 1.6 0 0 1 0-3.2Z\" stroke=\"#FFF2E0\" stroke-width=\"2\" stroke-linecap=\"round\"></path></svg>"
}

///|
/// The same mark as a data URL, so a page carries its tab icon with it: a
/// library that serves HTML has no directory to put an icon file in.
///
/// An image read on its own needs the namespace the inline mark leaves out, and
/// the attribute's own double quotes rule them out inside it.
fn site_favicon() -> String {
  let svg = site_mark()
    .replace_all(old="<svg ", new="<svg xmlns='http://www.w3.org/2000/svg' ")
    .replace_all(old="\"", new="'")
    .replace_all(old="<", new="%3C")
    .replace_all(old=">", new="%3E")
    .replace_all(old="#", new="%23")
    .replace_all(old=" ", new="%20")
  "<link rel=\"icon\" href=\"data:image/svg+xml,\{svg}\">"
}

///|
/// The site's own styling, as one block: the palette (light, and dark when the
/// reader asks for it), the bar, the scrollbars, and the handful of settings
/// each reader is bent by. Each reader keeps its own surfaces and its own dark
/// mode; what the theme adds is the accent, the faces and the chrome, so a page
/// still behaves the way its reader's users expect.
fn site_css() -> String {
  let css =
    #|html.mo-docs{--paper:#ECEFFA;--panel:#FFFFFF;--ink:#232049;--ink-soft:#454270;--muted:#6C6990;--line:#D8DCF2;--iris:#898AC4;--iris-strong:#6E6FAE;--iris-deep:#56578F;--peri:#A2AADB;--cream:#FFF2E0;--bar:56px;--font-display:"Space Grotesk","Inter",system-ui,sans-serif;--font-body:"Inter",system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;--font-mono:"JetBrains Mono",ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;color-scheme:light;font-variant-ligatures:no-contextual}
    #|@media (prefers-color-scheme:dark){html.mo-docs{--paper:#16142A;--panel:#201D3A;--ink:#ECE9FB;--ink-soft:#C9C4E6;--muted:#9A95BE;--line:#322D52;--iris:#A6A8E4;--iris-strong:#B7B9EC;--iris-deep:#898AC4;--peri:#8893CC;--cream:#FFF2E0;color-scheme:dark}}
    #|html.mo-docs,html.mo-docs body{margin:0;height:100%}
    #|html.mo-docs body{display:flex;flex-direction:column;height:100dvh;overflow:hidden;background:var(--paper);color:var(--ink);font-family:var(--font-body);-webkit-font-smoothing:antialiased}
    #|html.mo-docs .mo-bar{flex:none;height:var(--bar);display:flex;align-items:center;gap:10px;padding:0 14px;background:color-mix(in srgb,var(--panel) 84%,var(--paper));border-bottom:1px solid var(--line);font-family:var(--font-display)}
    #|html.mo-docs .mo-bar svg{width:22px;height:22px;flex:none}
    #|html.mo-docs .mo-name{font-size:15px;font-weight:600;letter-spacing:-.01em;overflow:hidden;white-space:nowrap;text-overflow:ellipsis}
    #|html.mo-docs .mo-spec{margin-left:auto;flex:none;font-family:var(--font-mono);font-size:11.5px;color:var(--muted);text-decoration:none;border:1px solid var(--line);border-radius:999px;padding:4px 10px}
    #|html.mo-docs .mo-spec:hover{color:var(--iris-strong);border-color:var(--peri);background:color-mix(in srgb,var(--iris) 10%,transparent)}
    #|html.mo-docs .mo-reader{flex:1;min-height:0;overflow:auto}
    #|html.mo-docs ::-webkit-scrollbar{width:11px;height:11px}
    #|html.mo-docs ::-webkit-scrollbar-track{background:transparent}
    #|html.mo-docs ::-webkit-scrollbar-thumb{border:3px solid transparent;border-radius:999px;background-clip:content-box;background-color:color-mix(in srgb,var(--iris) 45%,transparent)}
    #|html.mo-docs ::-webkit-scrollbar-thumb:hover{background-color:var(--iris-strong)}
    #|@supports not selector(::-webkit-scrollbar){html.mo-docs *{scrollbar-width:thin;scrollbar-color:color-mix(in srgb,var(--iris) 55%,transparent) transparent}}
    #|html.mo-docs .swagger-ui{font-family:var(--font-body)}
    #|html.mo-docs .swagger-ui .topbar{display:none}
    #|html.mo-docs .swagger-ui .wrapper{max-width:1080px}
    #|html.mo-docs .swagger-ui .info .title{font-family:var(--font-display);font-weight:600;letter-spacing:-.01em;color:var(--ink)}
    #|html.mo-docs .swagger-ui .info .title small{background:var(--iris);border-radius:999px;border:0}
    #|html.mo-docs .swagger-ui .info .title small pre{background:transparent;font-family:var(--font-mono)}
    #|html.mo-docs .swagger-ui .opblock-tag{font-family:var(--font-display);color:var(--ink);border-bottom:1px solid var(--line)}
    #|html.mo-docs .swagger-ui .opblock{border-radius:12px;border-color:var(--line);box-shadow:none}
    #|html.mo-docs .swagger-ui .opblock .opblock-summary-method{border-radius:8px;font-family:var(--font-mono);font-weight:500}
    #|html.mo-docs .swagger-ui .opblock.opblock-post .opblock-summary-method{background:var(--iris-strong)}
    #|html.mo-docs .swagger-ui .opblock.opblock-get .opblock-summary-method{background:var(--peri)}
    #|html.mo-docs .swagger-ui .btn{border-radius:10px;font-family:var(--font-body)}
    #|html.mo-docs .swagger-ui .btn.execute{background:var(--iris-strong);border-color:var(--iris-strong)}
    #|html.mo-docs .swagger-ui section.models{border:1px solid var(--line);border-radius:14px}
    #|html.mo-docs .swagger-ui .model-box,.swagger-ui .model{padding:0}
    #|html.mo-docs .swagger-ui :is(code,pre,.model-title,.renderedMarkdown code){font-family:var(--font-mono);font-variant-ligatures:no-contextual}
    #|html.mo-docs :is(.light-mode,.dark-mode){--scalar-font:var(--font-body);--scalar-color-1:var(--ink);--scalar-color-2:var(--ink-soft);--scalar-color-3:var(--muted);--scalar-color-accent:var(--iris-strong);--scalar-border-color:var(--line);--scalar-background-1:var(--panel);--scalar-background-2:var(--paper);--scalar-background-3:var(--paper);--scalar-sidebar-background-1:color-mix(in srgb,var(--panel) 72%,var(--paper));--scalar-sidebar-color-1:var(--ink);--scalar-sidebar-border-color:var(--line)}
    #|html.mo-docs{--font-family-base:var(--font-body);--font-family-monospaced:var(--font-mono);--heading-font-family:var(--font-display);--color-primary-base:var(--iris-strong);--link-color-primary:var(--iris-strong);--link-color-primary-hover:var(--iris-deep);--border-color-primary:var(--line)}
    #|html.mo-docs redoc{display:block;height:100%}
    #|html.mo-docs .redoc-wrap{height:100% !important}
    #|html.mo-docs #redocly,html.mo-docs #swagger-ui{height:100%}
  css
}

///|
/// A page of the site's making: the palette, the faces, the bar that names the
/// application and points at its document, and then whatever the reader puts
/// there. `head` is what the reader needs in `head` (its stylesheet), `body` is
/// the reader's own element and scripts.
fn site_page(
  title~ : String,
  spec_url~ : String,
  head~ : String,
  body~ : String,
) -> String {
  let name = html_escape(title)
  "<!doctype html>\n<html lang=\"en\" class=\"mo-docs\">\n<head>\n<meta charset=\"utf-8\">\n<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n<title>\{name}</title>\n\{site_favicon()}\n<link rel=\"preconnect\" href=\"https://fonts.googleapis.com\">\n<link rel=\"preconnect\" href=\"https://fonts.gstatic.com\" crossorigin>\n<link rel=\"stylesheet\" href=\"\{site_fonts}\">\n<style>\{site_css()}</style>\n\{head}</head>\n<body>\n<header class=\"mo-bar\">\{site_mark()}<span class=\"mo-name\">\{name}</span><a class=\"mo-spec\" href=\"\{html_escape(spec_url)}\">\{html_escape(last_segment(spec_url))}</a></header>\n<main class=\"mo-reader\">\n\{body}</main>\n</body>\n</html>\n"
}

///|
/// A Swagger UI page rendering the document served at `spec_url` (← FastAPI's
/// `get_swagger_ui_html`). `oauth2_redirect_url` is the page an OAuth2 flow
/// returns to, served by `swagger_redirect`; `init_oauth` is handed to
/// `initOAuth` to prefill the client id, scopes and the like; `extra` is merged
/// over the settings passed to Swagger UI (← `swagger_ui_parameters`).
pub fn swagger_ui(
  spec_url~ : String = "/openapi.json",
  title~ : String = "moonapi",
  js_url~ : String = swagger_js,
  css_url~ : String = swagger_css,
  oauth2_redirect_url? : String,
  init_oauth? : Json,
  extra? : Map[String, Json],
  theme~ : Theme = theme,
) -> String {
  let config : Map[String, Json] = {
    "url": Json(spec_url),
    "dom_id": "#swagger-ui",
    "layout": "BaseLayout",
    "deepLinking": true,
    "showExtensions": true,
    "showCommonExtensions": true,
  }
  for k, v in extra.unwrap_or(Map([])) {
    config[k] = v
  }
  let redirect = match oauth2_redirect_url {
    Some(url) =>
      "\nconfig.oauth2RedirectUrl = window.location.origin + \{script_json(Json(url))};"
    None => ""
  }
  let oauth = match init_oauth {
    Some(j) => "\nui.initOAuth(\{script_json(j)});"
    None => ""
  }
  let script = "<script src=\"\{html_escape(js_url)}\"></script>\n<script>\nconst config = \{script_json(Json(config))};\nconfig.presets = [SwaggerUIBundle.presets.apis, SwaggerUIBundle.SwaggerUIStandalonePreset];\{redirect}\nconst ui = SwaggerUIBundle(config);\{oauth}\n</script>"
  match theme {
    Plain =>
      "<!doctype html>\n<html lang=\"en\">\n<head>\n<meta charset=\"utf-8\">\n<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n<title>\{html_escape(title)}</title>\n<link rel=\"stylesheet\" href=\"\{html_escape(css_url)}\">\n</head>\n<body>\n<div id=\"swagger-ui\"></div>\n\{script}\n</body>\n</html>\n"
    Site =>
      site_page(
        title~,
        spec_url~,
        head="<link rel=\"stylesheet\" href=\"\{html_escape(css_url)}\">\n",
        body="<div id=\"swagger-ui\"></div>\n\{script}\n",
      )
  }
}

///|
/// The page an OAuth2 authorisation started from Swagger UI returns to: it hands
/// the code or token back to the window that opened it (← FastAPI's
/// `get_swagger_ui_oauth2_redirect_html`).
pub fn swagger_redirect(js_url~ : String = swagger_redirect_js) -> String {
  "<!doctype html>\n<html lang=\"en-US\">\n<head>\n<title>Swagger UI: OAuth2 Redirect</title>\n</head>\n<body>\n<script src=\"\{html_escape(js_url)}\"></script>\n</body>\n</html>\n"
}

///|
/// A ReDoc page rendering the document served at `spec_url` (← FastAPI's
/// `get_redoc_html`): three panels, built for reading rather than for trying
/// calls out. ReDoc reports usage to its maker unless told not to; `telemetry`
/// is off unless turned on, since the page is served to this API's readers.
pub fn redoc_ui(
  spec_url~ : String = "/openapi.json",
  title~ : String = "moonapi",
  js_url~ : String = redoc_js,
  telemetry~ : Bool = false,
  theme~ : Theme = theme,
) -> String {
  let opt_out = if telemetry { "" } else { " disable-telemetry=\"true\"" }
  let script = "<script type=\"module\" src=\"\{html_escape(js_url)}\"></script>"
  match theme {
    Plain =>
      "<!doctype html>\n<html lang=\"en\">\n<head>\n<meta charset=\"utf-8\">\n<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n<title>\{html_escape(title)}</title>\n<style>body { margin: 0; }</style>\n</head>\n<body>\n<redoc spec-url=\"\{html_escape(spec_url)}\"\{opt_out}></redoc>\n\{script}\n</body>\n</html>\n"
    Site =>
      site_page(
        title~,
        spec_url~,
        head="",
        body="<redoc spec-url=\"\{html_escape(spec_url)}\"\{opt_out}></redoc>\n\{script}\n",
      )
  }
}

///|
/// A Redocly reference rendering the document served at `spec_url`: the
/// reference and a request console on one page. `extra` is merged over the
/// options passed to `RedoclyReferenceDocs.init`, which is where the licence
/// key, the theming and the code samples go; without a key the reference
/// renders under Redocly's banner.
pub fn redocly_ui(
  spec_url~ : String = "/openapi.json",
  title~ : String = "moonapi",
  js_url~ : String = redocly_js,
  extra? : Map[String, Json],
  theme~ : Theme = theme,
) -> String {
  let options : Map[String, Json] = Map([])
  for k, v in extra.unwrap_or(Map([])) {
    options[k] = v
  }
  let script = "<script src=\"\{html_escape(js_url)}\"></script>\n<script>\nRedoclyReferenceDocs.init(\{script_json(Json(spec_url))}, \{script_json(Json(options))}, document.querySelector(\"#redocly\"));\n</script>"
  match theme {
    Plain =>
      "<!doctype html>\n<html lang=\"en\">\n<head>\n<meta charset=\"utf-8\">\n<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n<title>\{html_escape(title)}</title>\n<style>body { margin: 0; }</style>\n</head>\n<body>\n<div id=\"redocly\"></div>\n\{script}\n</body>\n</html>\n"
    Site =>
      site_page(
        title~,
        spec_url~,
        head="",
        body="<div id=\"redocly\"></div>\n\{script}\n",
      )
  }
}

///|
/// A Scalar API reference rendering the document served at `spec_url`: the
/// reference and a request client on one page. `extra` is merged over the
/// configuration passed to `Scalar.createApiReference`, which is where its
/// theme, layout and authentication defaults go.
pub fn scalar_ui(
  spec_url~ : String = "/openapi.json",
  title~ : String = "moonapi",
  js_url~ : String = scalar_js,
  extra? : Map[String, Json],
  theme~ : Theme = theme,
) -> String {
  let config : Map[String, Json] = { "url": Json(spec_url) }
  for k, v in extra.unwrap_or(Map([])) {
    config[k] = v
  }
  let script = "<script src=\"\{html_escape(js_url)}\"></script>\n<script>\nScalar.createApiReference(\"#app\", \{script_json(Json(config))});\n</script>"
  match theme {
    Plain =>
      "<!doctype html>\n<html lang=\"en\">\n<head>\n<meta charset=\"utf-8\">\n<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n<title>\{html_escape(title)}</title>\n</head>\n<body>\n<div id=\"app\"></div>\n\{script}\n</body>\n</html>\n"
    Site =>
      site_page(
        title~,
        spec_url~,
        head="",
        body="<div id=\"app\"></div>\n\{script}\n",
      )
  }
}
