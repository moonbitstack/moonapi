// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// A route's own way of deciding which paths are its, in place of its template. The
// template stays what the route is called: the OpenAPI document and `url_for` read
// it, and neither has a way to say a regular expression.

///|
/// A regular expression or a glob, tried on what is left of the path once any
/// prefix the route was included under has been taken off.
pub struct Matcher {
  prefix : String
  source : String
  compiled : @moonregex.Pattern
}

///|
pub impl Eq for Matcher with fn equal(self, other) {
  self.prefix == other.prefix && self.source == other.source
}

///|
pub impl Debug for Matcher with fn to_repr(self) {
  Debug::to_repr(self.prefix + self.source)
}

///|
pub extend Matcher with Eq::{equal, not_equal}

///|
pub extend Matcher with Debug::{to_repr}

///|
fn matcher_of(route : String, source : String) -> Matcher {
  let compiled = @moonregex.compile(source) catch {
    e => abort("route path \{route}: `\{source}` does not compile: \{e}")
  }
  { prefix: "", source, compiled, }
}

///|
/// The named groups `path` binds, or `None` when it does not match. The whole
/// path has to match. A runaway expression meets moonregex's step limit, and a
/// request that makes one run away is a request this route does not answer.
fn Matcher::bind(self : Matcher, path : StringView) -> Map[String, String]? {
  guard path.has_prefix(self.prefix) else { return None }
  let rest = path.exact_view(start=self.prefix.length()).to_owned()
  let found = self.compiled.full(rest) catch { _ => return None }
  found.map(m => m.groupdict(default=""))
}

///|
/// A glob as a regular expression. `*` is any run within a segment, `?` one
/// character of a segment, `**` any run across segments, `**/` any number of whole
/// segments, `[a-z]` and `[!a-z]` a class, and `{a,b}` either. Each `*` and `**`
/// binds the next name in `names`, in order, and is simply matched past the end of
/// them.
fn glob_regex(route : String, glob : String, names : Array[String]) -> String {
  let chars = glob.to_array()
  let out = StringBuilder()
  let mut bound = 0
  let capture = (body : String) => {
    if bound < names.length() {
      bound = bound + 1
      "(?P<\{names[bound - 1]}>\{body})"
    } else {
      "(?:\{body})"
    }
  }
  let plain = (c : Char) => out.write_string(@moonregex.escape(c.to_string()))
  let mut depth = 0
  let mut i = 0
  while i < chars.length() {
    let c = chars[i]
    let next = if i + 1 < chars.length() { Some(chars[i + 1]) } else { None }
    match c {
      '*' if next is Some('*') => {
        let across = i + 2 < chars.length() && chars[i + 2] == '/'
        out.write_string(capture(if across { "(?:.*/)?" } else { ".*" }))
        i = i + (if across { 3 } else { 2 })
      }
      '*' => {
        out.write_string(capture("[^/]*"))
        i = i + 1
      }
      '?' => {
        out.write_string("[^/]")
        i = i + 1
      }
      '[' => {
        let mut close = i + 1
        while close < chars.length() && chars[close] != ']' {
          close = close + 1
        }
        if close == chars.length() {
          abort("route path \{route}: `[` in `\{glob}` is never closed")
        }
        out.write_char('[')
        for k in (i + 1)..<close {
          out.write_char(
            if k == i + 1 && chars[k] == '!' {
              '^'
            } else {
              chars[k]
            },
          )
        }
        out.write_char(']')
        i = close + 1
      }
      '{' => {
        depth = depth + 1
        out.write_string("(?:")
        i = i + 1
      }
      '}' if depth > 0 => {
        depth = depth - 1
        out.write_char(')')
        i = i + 1
      }
      ',' if depth > 0 => {
        out.write_char('|')
        i = i + 1
      }
      _ => {
        plain(c)
        i = i + 1
      }
    }
  }
  if depth > 0 {
    abort("route path \{route}: `{` in `\{glob}` is never closed")
  }
  out.to_string()
}

///|
/// `path` with a regular expression deciding what it answers. The expression has
/// to match the whole path, and its named groups are the path's parameters.
/// `path` is still what the OpenAPI document and `url_for` show.
pub fn Pattern::regex(path : String, regex : String) -> Pattern {
  { ..Pattern::parse(path), matcher: Some(matcher_of(path, regex)), }
}

///|
/// `path` with a glob deciding what it answers, the whole path as with
/// `Pattern::regex`. Each `*` and `**` binds the next parameter `path` names.
pub fn Pattern::glob(path : String, glob : String) -> Pattern {
  let parsed = Pattern::parse(path)
  let names = parsed.params().map(p => p.0)
  { ..parsed, matcher: Some(matcher_of(path, glob_regex(path, glob, names))), }
}

///|
/// The pattern a registration asks for. Both at once is a mistake in the program,
/// so it aborts at registration, as `Pattern::parse` does.
pub fn Pattern::of(path : String, regex? : String, glob? : String) -> Pattern {
  match (regex, glob) {
    (Some(_), Some(_)) =>
      abort("route path \{path}: give `regex` or `glob`, not both")
    (Some(r), None) => Pattern::regex(path, r)
    (None, Some(g)) => Pattern::glob(path, g)
    (None, None) => Pattern::parse(path)
  }
}

///|
/// This pattern on a route moved to `path` by being included under `prefix`.
pub fn Pattern::moved(
  self : Pattern,
  path : String,
  prefix : String,
) -> Pattern {
  let parsed = Pattern::parse(path)
  guard self.matcher is Some(m) else { return parsed }
  let head = join_prefix(prefix, "").trim_end(chars="/").to_owned()
  { ..parsed, matcher: Some({ ..m, prefix: head + m.prefix, }), }
}
