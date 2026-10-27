///|
/// What a path parameter accepts (← Starlette's convertors). `Str` is one
/// segment or part of one; `Path` is the rest of the path, slashes included.
pub(all) enum Convertor {
  Str
  Int
  Float
  Uuid
  Path
} derive(Eq, Debug)

///|
pub extend Convertor with Eq::{equal, not_equal}

///|
pub extend Convertor with Debug::{to_repr}

///|
/// The convertor named `name`, as a template spells it after the colon.
pub fn Convertor::of(name : StringView) -> Convertor? {
  match name {
    "str" => Some(Str)
    "int" => Some(Int)
    "float" => Some(Float)
    "uuid" => Some(Uuid)
    "path" => Some(Path)
    _ => None
  }
}

///|
/// One piece of a path template: text matched as written, or a parameter.
pub(all) enum Piece {
  Literal(String)
  Param(name~ : String, convertor~ : Convertor)
} derive(Eq, Debug)

///|
pub extend Piece with Eq::{equal, not_equal}

///|
pub extend Piece with Debug::{to_repr}

///|
/// A route path read as a template: `/users/{id:int}`, `/files/{name}.json`,
/// `/static/{rest:path}`. A parameter without a convertor is `str`.
pub(all) struct Pattern {
  source : String
  pieces : Array[Piece]
} derive(Eq, Debug)

///|
pub extend Pattern with Eq::{equal, not_equal}

///|
pub extend Pattern with Debug::{to_repr}

///|
/// Read `path` as a template. An unclosed brace, an empty name, an unknown
/// convertor or two parameters with nothing between them is a mistake in the
/// program, not in a request, so it aborts at registration — the way Starlette
/// refuses such a route when the application starts.
pub fn Pattern::parse(path : String) -> Pattern {
  let pieces : Array[Piece] = []
  let mut from = 0
  let mut i = 0
  while i < path.length() {
    if path.unsafe_get(i) != '{'.to_int().to_uint16() {
      i += 1
      continue
    }
    let close = match path.view(start_offset=i).find("}") {
      Some(k) => i + k
      None => abort("route path \{path}: `{` is never closed")
    }
    let inside = path.view(start_offset=i + 1, end_offset=close)
    let (name, convertor) = match inside.find(":") {
      Some(k) => {
        let conv = inside.view(start_offset=k + 1)
        match Convertor::of(conv) {
          Some(c) => (inside.view(end_offset=k).to_owned(), c)
          None => abort("route path \{path}: no convertor called `\{conv}`")
        }
      }
      None => (inside.to_owned(), Str)
    }
    if name.is_empty() {
      abort("route path \{path}: a parameter has no name")
    }
    if i == from && pieces.last() is Some(Param(..)) {
      abort("route path \{path}: two parameters with nothing between them")
    }
    if i > from {
      pieces.push(
        Literal(path.view(start_offset=from, end_offset=i).to_owned()),
      )
    }
    pieces.push(Param(name~, convertor~))
    i = close + 1
    from = i
  }
  if from < path.length() {
    pieces.push(Literal(path.view(start_offset=from).to_owned()))
  }
  { source: path, pieces, }
}

///|
/// The parameters `path` binds, or `None` when it does not match. The whole
/// path must match: a trailing slash is a different path.
pub fn Pattern::bind(self : Pattern, path : StringView) -> Map[String, String]? {
  let params : Map[String, String] = Map([])
  if bind_from(self.pieces, 0, path, 0, params) {
    Some(params)
  } else {
    None
  }
}

///|
fn bind_from(
  pieces : Array[Piece],
  i : Int32,
  path : StringView,
  at : Int32,
  params : Map[String, String],
) -> Bool {
  if i == pieces.length() {
    return at == path.length()
  }
  match pieces[i] {
    Literal(text) => {
      let rest = path.view(start_offset=at)
      rest.has_prefix(text) &&
      bind_from(pieces, i + 1, path, at + text.length(), params)
    }
    Param(name~, convertor~) => {
      for end in ends(convertor, path, at) {
        params[name] = path.view(start_offset=at, end_offset=end).to_owned()
        if bind_from(pieces, i + 1, path, end, params) {
          return true
        }
      }
      params.remove(name)
      false
    }
  }
}

///|
/// Where a value of `convertor` starting at `at` may end, longest first.
fn ends(convertor : Convertor, path : StringView, at : Int32) -> Array[Int32] {
  let n = path.length()
  let run = fn(ok : (UInt16) -> Bool) {
    let mut k = at
    while k < n && ok(path.unsafe_get(k)) {
      k += 1
    }
    k
  }
  let digit = (c : UInt16) => {
    c >= '0'.to_int().to_uint16() && c <= '9'.to_int().to_uint16()
  }
  let longest_first = fn(last : Int32, min : Int32) {
    let out = []
    let mut k = last
    while k >= at + min {
      out.push(k)
      k -= 1
    }
    out
  }
  match convertor {
    Str => longest_first(run(c => c != '/'.to_int().to_uint16()), 1)
    Path => longest_first(n, 0)
    Int => longest_first(run(digit), 1)
    Float => {
      let whole = run(digit)
      if whole == at {
        return []
      }
      let out = []
      if whole < n &&
        path.unsafe_get(whole) == '.'.to_int().to_uint16() &&
        whole + 1 < n &&
        digit(path.unsafe_get(whole + 1)) {
        let mut k = whole + 1
        while k < n && digit(path.unsafe_get(k)) {
          k += 1
        }
        out.push(k)
      }
      out.push(whole)
      out
    }
    Uuid =>
      if at + 36 <= n && is_uuid(path.view(start_offset=at, end_offset=at + 36)) {
        [at + 36]
      } else {
        []
      }
  }
}

///|
fn is_uuid(s : StringView) -> Bool {
  for i in 0..<36 {
    let c = s.unsafe_get(i).to_int()
    let ok = if i == 8 || i == 13 || i == 18 || i == 23 {
      c == '-'.to_int()
    } else {
      (c >= '0'.to_int() && c <= '9'.to_int()) ||
      (c >= 'a'.to_int() && c <= 'f'.to_int()) ||
      (c >= 'A'.to_int() && c <= 'F'.to_int())
    }
    if !ok {
      return false
    }
  }
  true
}

///|
/// The path with `params` substituted (← Starlette's `url_path_for`); `None`
/// when one is missing or does not fit its convertor.
pub fn Pattern::fill(self : Pattern, params : Map[String, String]) -> String? {
  let out = StringBuilder()
  for piece in self.pieces {
    match piece {
      Literal(text) => out.write_string(text)
      Param(name~, convertor~) => {
        guard params.get(name) is Some(value) else { return None }
        guard ends(convertor, value.view(), 0) is [whole, ..] &&
          whole == value.length() &&
          (convertor is Path || !value.contains("/")) else {
          return None
        }
        out.write_string(value)
      }
    }
  }
  Some(out.to_string())
}

///|
/// The parameters in the order the path names them.
pub fn Pattern::params(self : Pattern) -> Array[(String, Convertor)] {
  let out = []
  for piece in self.pieces {
    if piece is Param(name~, convertor~) {
      out.push((name, convertor))
    }
  }
  out
}

///|
/// The path as an OpenAPI template expression: every parameter as `{name}`,
/// the convertor left to the parameter's schema.
pub fn Pattern::template(self : Pattern) -> String {
  let out = StringBuilder()
  for piece in self.pieces {
    match piece {
      Literal(text) => out.write_string(text)
      Param(name~, ..) => {
        out.write_char('{')
        out.write_string(name)
        out.write_char('}')
      }
    }
  }
  out.to_string()
}

///|
/// A route `path` under `prefix`, written as FastAPI writes it: the prefix with
/// its trailing slashes dropped, then the path as given, so `("/sub", "/items/")`
/// is `/sub/items/` and `("/sub", "/")` is `/sub/`. A path keeps its own trailing
/// slash because a trailing slash is part of what a route matches.
pub fn join_prefix(prefix : String, path : String) -> String {
  let head = prefix.trim_end(chars="/").to_owned()
  let head = if head.is_empty() || head.has_prefix("/") {
    head
  } else {
    "/" + head
  }
  let joined = if path.is_empty() || path.has_prefix("/") {
    head + path
  } else {
    head + "/" + path
  }
  if joined.is_empty() {
    "/"
  } else {
    joined
  }
}
