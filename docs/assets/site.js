/* moonapi docs — shared behaviour */
(function () {
  "use strict";

  /* ---------- theme ---------- */
  var root = document.documentElement;
  function applyTheme(t) {
    root.setAttribute("data-theme", t);
    try { localStorage.setItem("moonapi-theme", t); } catch (e) {}
  }
  var saved;
  try { saved = localStorage.getItem("moonapi-theme"); } catch (e) {}
  if (!saved) saved = matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
  applyTheme(saved);
  document.addEventListener("click", function (e) {
    var t = e.target.closest("[data-theme-toggle]");
    if (!t) return;
    var cur = root.getAttribute("data-theme");
    applyTheme(cur === "dark" ? "light" : "dark");
  });

  /* ---------- copy buttons ---------- */
  document.addEventListener("click", function (e) {
    var b = e.target.closest("[data-copy]");
    if (!b) return;
    var text = b.getAttribute("data-copy");
    if (b.hasAttribute("data-copy-from")) {
      var el = document.querySelector(b.getAttribute("data-copy-from"));
      if (el) text = el.textContent;
    }
    navigator.clipboard.writeText(text).then(function () {
      var o = b.textContent;
      b.textContent = "copied";
      b.classList.add("ok");
      setTimeout(function () { b.textContent = o; b.classList.remove("ok"); }, 1100);
    });
  });

  /* ---------- .copy buttons (copy the nearest code block) ---------- */
  document.addEventListener("click", function (e) {
    var b = e.target.closest(".copy");
    if (!b) return;
    var wrap = b.closest(".codewrap") || b.parentElement;
    var code = wrap ? wrap.querySelector("pre code, pre") : null;
    var text = code ? code.textContent : "";
    navigator.clipboard.writeText(text).then(function () {
      var o = b.textContent;
      b.textContent = "copied";
      b.classList.add("ok");
      setTimeout(function () { b.textContent = o; b.classList.remove("ok"); }, 1100);
    });
  });

  /* ---------- mobile nav ---------- */
  document.addEventListener("click", function (e) {
    if (e.target.closest("[data-nav-toggle]")) {
      var nav = document.querySelector(".nav");
      var sb = document.querySelector(".sidebar");
      if (nav) nav.classList.toggle("show");
      if (sb) sb.classList.toggle("open");
    }
  });

  /* ---------- scroll-spy for sidebars ---------- */
  var links = Array.prototype.slice.call(document.querySelectorAll(".sidebar a[href^='#']"));
  if (links.length) {
    var map = {};
    links.forEach(function (a) { map[a.getAttribute("href").slice(1)] = a; });
    var obs = new IntersectionObserver(function (entries) {
      entries.forEach(function (en) {
        if (en.isIntersecting) {
          links.forEach(function (a) { a.classList.remove("active"); });
          var a = map[en.target.id];
          if (a) a.classList.add("active");
        }
      });
    }, { rootMargin: "-15% 0px -80% 0px" });
    document.querySelectorAll(".sidebar-spy > *[id], section[id], .pkg-section[id], h2[id], article[id]").forEach(function (s) { obs.observe(s); });
  }

  /* ---------- MoonBit syntax highlight (pre.hl) ---------- */
  var KW = ["fn","let","pub","struct","enum","type","trait","async","match","if","else",
            "return","raise","for","in","while","derive","with","is","guard","try","catch",
            "has","interface","break","continue","import","as","extern","typealias"];
  function esc(s) { return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;"); }
  function highlight(code) {
    var e = esc(code);
    return e.replace(
      /(\/\/[^\n]*)|("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')|(`[^`]*`)|(\b\d[\d_.]*\b)|([A-Za-z_]\w*)/g,
      function (m, com, str, raw, num, word) {
        if (com) return '<span class="tok-com">' + com + "</span>";
        if (str) return '<span class="tok-str">' + str + "</span>";
        if (raw) return '<span class="tok-str">' + raw + "</span>";
        if (num) return '<span class="tok-num">' + num + "</span>";
        if (word) {
          if (KW.indexOf(word) >= 0) return '<span class="tok-kw">' + word + "</span>";
          if (/^[A-Z]/.test(word)) return '<span class="tok-ty">' + word + "</span>";
        }
        return word;
      }
    );
  }
  document.querySelectorAll("pre.hl").forEach(function (pre) {
    pre.innerHTML = highlight(pre.textContent);
  });

  /* ---------- CJK grapheme wrapping + trailing-comment alignment ----------
     Non-ASCII grapheme clusters are wrapped in inline-block spans whose width
     is 2ch for wide (CJK / fullwidth / emoji) glyphs and 1ch for the rest, so
     a column padded with spaces lines up even when the fallback font is not
     monospaced at integer cell widths. Trailing `//` comments are then aligned
     to the widest code column. Applied to blocks marked [data-align]. */
  function isWide(cp) {
    return (
      (cp >= 0x1100 && cp <= 0x115f) || (cp >= 0x2e80 && cp <= 0x303e) ||
      (cp >= 0x3041 && cp <= 0x33ff) || (cp >= 0x3400 && cp <= 0x4dbf) ||
      (cp >= 0x4e00 && cp <= 0x9fff) || (cp >= 0xa000 && cp <= 0xa4cf) ||
      (cp >= 0xac00 && cp <= 0xd7a3) || (cp >= 0xf900 && cp <= 0xfaff) ||
      (cp >= 0xfe30 && cp <= 0xfe4f) || (cp >= 0xff00 && cp <= 0xff60) ||
      (cp >= 0xffe0 && cp <= 0xffe6) || (cp >= 0x1f300 && cp <= 0x1faff) ||
      (cp >= 0x2600 && cp <= 0x27bf)  || (cp >= 0x20000 && cp <= 0x3fffd)
    );
  }
  function graphemes(str) {
    if (window.Intl && Intl.Segmenter) {
      var seg = new Intl.Segmenter(undefined, { granularity: "grapheme" });
      return Array.from(seg.segment(str), function (s) { return s.segment; });
    }
    return Array.from(str);
  }
  function span(ch) {
    var cp = ch.codePointAt(0);
    var w = isWide(cp) ? 2 : 1;
    return '<span class="gc w' + w + '">' + esc(ch) + "</span>";
  }
  function colWidth(s) {
    var w = 0;
    graphemes(s).forEach(function (g) {
      w += isWide(g.codePointAt(0)) ? 2 : 1;
    });
    return w;
  }
  function alignBlock(el) {
    var lines = el.textContent.replace(/\n$/, "").split("\n");
    var parts = lines.map(function (ln) {
      var idx = ln.lastIndexOf("//");
      var code = ln, com = "";
      if (idx > 0 && /\s/.test(ln[idx - 1])) { code = ln.slice(0, idx); com = ln.slice(idx); }
      return { code: code, com: com, w: colWidth(code) };
    });
    var max = parts.reduce(function (m, p) { return Math.max(m, p.w); }, 0);
    var out = parts.map(function (p) {
      var pad = max - p.w;
      var codeHtml = graphemes(p.code).map(span).join("") + Array(pad + 1).join(span(" "));
      var comHtml = p.com ? graphemes(p.com).map(span).join("") : "";
      return codeHtml + comHtml;
    });
    el.innerHTML = out.join("\n");
  }
  document.querySelectorAll("[data-align]").forEach(alignBlock);

  /* ---------- terminal / tab panes ---------- */
  document.addEventListener("click", function (e) {
    var b = e.target.closest(".term-tabs button[data-tab]");
    if (!b) return;
    var group = b.getAttribute("data-tab");
    var wrap = b.closest(".term");
    if (!wrap) return;
    wrap.querySelectorAll(".term-tabs button").forEach(function (x) { x.classList.remove("active"); });
    b.classList.add("active");
    wrap.querySelectorAll("[data-pane]").forEach(function (p) {
      p.style.display = p.getAttribute("data-pane") === group ? "" : "none";
    });
  });
})();
