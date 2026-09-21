// The request-body form extractors — FastAPI's `Form(...)` and `File(...)`
// parameters. Two content types carry a submitted form: an urlencoded body
// (`application/x-www-form-urlencoded`) of percent-encoded `key=value` pairs,
// and a multipart body (`multipart/form-data`) whose parts each carry their own
// headers and can hold raw file bytes. Both parse to one `FormData`, with plain
// fields and uploaded files kept apart. The parsing is byte-level, so file
// contents survive untouched (a JPEG isn't valid UTF-8).

///|
/// A plain form field: a `name` and its decoded text `value`.
pub(all) struct FormField {
  name : String
  value : String
} derive(Eq)

///|
/// An uploaded file from a multipart part: the form-field `name` it came under,
/// the client's `filename`, its declared `content_type` (empty when the part
/// carried no `Content-Type`), the raw `content` bytes exactly as received, and
/// the part's own `headers` with their names lowercased, in body order.
///
/// `content_type` is kept as its own field because nearly every caller wants it
/// and nothing else; `headers` is there for the rest — a
/// `Content-Transfer-Encoding` a handler must honour, a checksum a client
/// attached — which otherwise had nowhere to be read from.
pub(all) struct UploadFile {
  name : String
  filename : String
  content_type : String
  content : Bytes
  headers : Array[(String, String)]
} derive(Eq)

///|
/// The uploaded size in bytes (← FastAPI's `UploadFile.size`). Derived rather
/// than stored: a field could be set to disagree with `content`, and a size that
/// lies about the bytes beside it is worse than no size at all.
pub fn UploadFile::size(self : UploadFile) -> Int {
  self.content.length()
}

///|
/// Look up one of the part's own headers by name, `None` if it carried no such
/// header. Names are matched lowercased, the same convention as
/// `@moonasgi.Request::header`.
pub fn UploadFile::header(self : UploadFile, name : String) -> String? {
  header_of(self.headers, name)
}

///|
/// A parsed form: its plain `fields` and its uploaded `files`, in body order. A
/// multipart part is a file when its `Content-Disposition` carries a `filename`;
/// otherwise it's a field. An urlencoded body only ever yields fields.
pub(all) struct FormData {
  fields : Array[FormField]
  files : Array[UploadFile]
} derive(Eq)

///|
/// The value of the first field named `name`, `None` if absent — the common
/// `Form(...)` lookup.
pub fn FormData::field(self : FormData, name : String) -> String? {
  for f in self.fields {
    if f.name == name {
      return Some(f.value)
    }
  }
  None
}

///|
/// Every value submitted under `name`, in order — an HTML form can repeat a
/// field (checkbox groups, multi-selects), and FastAPI surfaces those as a list.
pub fn FormData::field_all(self : FormData, name : String) -> Array[String] {
  let out : Array[String] = []
  for f in self.fields {
    if f.name == name {
      out.push(f.value)
    }
  }
  out
}

///|
/// The first uploaded file under `name`, `None` if absent — the `File(...)`
/// lookup.
pub fn FormData::file(self : FormData, name : String) -> UploadFile? {
  for f in self.files {
    if f.name == name {
      return Some(f)
    }
  }
  None
}

///|
/// What a submitted form may cost before it is refused: how many parts it may
/// carry, and how many bytes any one part may hold.
///
/// A request body is attacker-controlled and, on this SEAM, fully buffered before
/// a route ever sees it. Unbounded, a body that is nothing but boundaries becomes
/// as many parts as it has bytes — every one of them an allocation the app made
/// on the sender's say-so, on top of the body it already holds.
pub(all) struct FormLimits {
  max_parts : Int
  max_part_size : Int
} derive(Eq)

///|
/// Limits with Starlette's defaults — 1000 parts of at most 1 MiB — or either
/// bound overridden.
pub fn FormLimits::new(
  max_parts? : Int = 1000,
  max_part_size? : Int = 1024 * 1024,
) -> FormLimits {
  { max_parts, max_part_size, }
}

///|
/// Look up a header by name in a lowercased-name pair list.
fn header_of(headers : Array[(String, String)], name : String) -> String? {
  let key = name.to_lower()
  for h in headers {
    if h.0 == key {
      return Some(h.1)
    }
  }
  None
}

// -- byte helpers -------------------------------------------------------------

///|
/// Whether `hay` has `needle` starting at `at`.
fn bytes_has_at(hay : Bytes, at : Int, needle : Bytes) -> Bool {
  if at < 0 || at + needle.length() > hay.length() {
    return false
  }
  for i = 0; i < needle.length(); i = i + 1 {
    if hay[at + i] != needle[i] {
      return false
    }
  }
  true
}

///|
/// The first index at or after `from` where `needle` occurs in `hay`, `-1` if it
/// doesn't. A plain scan — the bodies here are small enough that a smarter search
/// buys nothing.
fn bytes_index_of(hay : Bytes, needle : Bytes, from : Int) -> Int {
  if needle.length() == 0 {
    return from
  }
  let last = hay.length() - needle.length()
  for i = from; i <= last; i = i + 1 {
    if bytes_has_at(hay, i, needle) {
      return i
    }
  }
  -1
}

///|
/// The hex value of an ASCII byte (`0`-`9`, `a`-`f`, `A`-`F`), `None` otherwise —
/// used to decode a `%XX` escape.
fn hex_val(b : Byte) -> Int? {
  let c = b.to_int()
  if c >= 0x30 && c <= 0x39 {
    Some(c - 0x30)
  } else if c >= 0x61 && c <= 0x66 {
    Some(c - 0x61 + 10)
  } else if c >= 0x41 && c <= 0x46 {
    Some(c - 0x41 + 10)
  } else {
    None
  }
}

// -- urlencoded ---------------------------------------------------------------

///|
/// Percent-decode the byte range `raw[start:end]` into bytes: `%XX` becomes the
/// byte it names, `+` becomes a space, everything else passes through. A stray
/// `%` with no two hex digits after it is kept literally, the way permissive
/// decoders treat malformed input.
fn percent_decode(raw : Bytes, start : Int, end : Int) -> Bytes {
  let out = Buffer()
  let mut i = start
  while i < end {
    let c = raw[i]
    if c == b'%' && i + 2 < end {
      match (hex_val(raw[i + 1]), hex_val(raw[i + 2])) {
        (Some(hi), Some(lo)) => {
          out.write_byte((hi * 16 + lo).to_byte())
          i = i + 3
        }
        _ => {
          out.write_byte(c)
          i = i + 1
        }
      }
    } else if c == b'+' {
      out.write_byte(b' ')
      i = i + 1
    } else {
      out.write_byte(c)
      i = i + 1
    }
  }
  out.to_bytes()
}

///|
/// The decoded text of the byte range `raw[start:end]` after percent/plus
/// decoding.
fn decode_component(raw : Bytes, start : Int, end : Int) -> String {
  @utf8.decode_lossy(percent_decode(raw, start, end)[:])
}

///|
/// Parse an `application/x-www-form-urlencoded` body into fields: split on `&`
/// into pairs, split each on its first `=`, percent/plus-decode both halves. A
/// pair with no `=` is a bare key with an empty value. `None` when the body
/// breaks `limits` — a pair counts as a part, since it costs one the same way.
fn parse_urlencoded(body : Bytes, limits : FormLimits) -> Array[FormField]? {
  let out : Array[FormField] = []
  let n = body.length()
  let mut start = 0
  for i = 0; i <= n; i = i + 1 {
    if i == n || body[i] == b'&' {
      if i > start {
        if out.length() == limits.max_parts || i - start > limits.max_part_size {
          return None
        }
        let mut eq = -1
        for j = start; j < i; j = j + 1 {
          if body[j] == b'=' {
            eq = j
            break
          }
        }
        let (name, value) = if eq < 0 {
          (decode_component(body, start, i), "")
        } else {
          (decode_component(body, start, eq), decode_component(body, eq + 1, i))
        }
        out.push({ name, value, })
      }
      start = i + 1
    }
  }
  Some(out)
}

// -- multipart/form-data ------------------------------------------------------

///|
/// Pull a quoted or bare parameter value out of a header-parameter string, e.g.
/// `name` from `form-data; name="file"; filename="a.txt"`. Matches `key=` then
/// takes the following `"..."` (or an unquoted run up to `;`).
fn header_param(header : String, key : String) -> String? {
  let needle = key + "="
  let idx = str_index_of(header, needle, 0)
  if idx < 0 {
    return None
  }
  let mut i = idx + needle.length()
  let n = header.length()
  if i < n && header[i].to_int() == 0x22 {
    // quoted
    i = i + 1
    let sb = StringBuilder()
    while i < n && header[i].to_int() != 0x22 {
      sb.write_char(header[i].unsafe_to_char())
      i = i + 1
    }
    Some(sb.to_string())
  } else {
    let sb = StringBuilder()
    while i < n && header[i].to_int() != 0x3B {
      sb.write_char(header[i].unsafe_to_char())
      i = i + 1
    }
    Some(trim_spaces(sb.to_string()))
  }
}

///|
/// The first index at or after `from` where `needle` occurs in `s`, `-1` if it
/// doesn't — the `String` analogue of `bytes_index_of`, for header text.
fn str_index_of(s : String, needle : String, from : Int) -> Int {
  let m = needle.length()
  if m == 0 {
    return from
  }
  let last = s.length() - m
  for i = from; i <= last; i = i + 1 {
    let mut ok = true
    for j = 0; j < m; j = j + 1 {
      if s[i + j] != needle[j] {
        ok = false
        break
      }
    }
    if ok {
      return i
    }
  }
  -1
}

///|
/// One parsed multipart part: its own headers and the byte range of its content
/// within the body.
priv struct Part {
  headers : Array[(String, String)]
  content_start : Int
  content_end : Int
}

///|
/// Split a `multipart/form-data` body on its `boundary` into parts. Each part is
/// introduced by `--boundary` followed by CRLF; the closing delimiter is
/// `--boundary--`. Between the delimiter's trailing CRLF and the next
/// `--boundary` lies the part — its header block, a blank `CRLF CRLF`, then its
/// content. The two bytes before the next delimiter are that part's own trailing
/// CRLF and don't belong to the content.
///
/// `None` once the body would yield more than `max_parts`, which is checked
/// before each part is built rather than after the split, so a body of nothing
/// but boundaries costs the bound and not its own length.
fn split_parts(
  body : Bytes,
  boundary : String,
  max_parts : Int,
) -> Array[Part]? {
  let parts : Array[Part] = []
  let dash = @utf8.encode("--" + boundary)
  let crlf = b"\r\n"
  let mut pos = bytes_index_of(body, dash, 0)
  while pos >= 0 {
    let after = pos + dash.length()
    // Closing delimiter `--boundary--`: nothing more to read.
    if bytes_has_at(body, after, b"--") {
      break
    }
    // A part delimiter is `--boundary CRLF`; skip the CRLF to the header block.
    let head_start = if bytes_has_at(body, after, crlf) {
      after + 2
    } else {
      after
    }
    let sep = bytes_index_of(body, b"\r\n\r\n", head_start)
    let next = bytes_index_of(body, dash, head_start)
    if sep < 0 || next < 0 || sep > next {
      // Malformed part — stop rather than invent structure.
      break
    }
    if parts.length() == max_parts {
      return None
    }
    let headers = part_headers(
      @utf8.decode_lossy(body[head_start:sep].to_owned()[:]),
    )
    let content_start = sep + 4
    let content_end = next - 2 // strip the CRLF that precedes the next delimiter
    parts.push({
      headers,
      content_start,
      content_end: if content_end < content_start {
        content_start
      } else {
        content_end
      },
    })
    pos = next
  }
  Some(parts)
}

///|
/// Split a part's header block into `(lowercased name, value)` pairs, one per
/// line. A line without a colon is not a header field, and is dropped rather
/// than guessed at.
fn part_headers(block : String) -> Array[(String, String)] {
  let out : Array[(String, String)] = []
  let n = block.length()
  let mut start = 0
  for i = 0; i <= n; i = i + 1 {
    if i == n || block[i].to_int() == 0x0A {
      let end = if i > start && block[i - 1].to_int() == 0x0D {
        i - 1
      } else {
        i
      }
      let line = block[start:end].to_owned()
      let mut colon = -1
      for j = 0; j < line.length(); j = j + 1 {
        if line[j] == ':' {
          colon = j
          break
        }
      }
      if colon > 0 {
        out.push(
          (
            trim_spaces(line[0:colon].to_owned()).to_lower(),
            trim_spaces(line[colon + 1:].to_owned()),
          ),
        )
      }
      start = i + 1
    }
  }
  out
}

///|
/// Parse a `multipart/form-data` body given its `boundary` into a `FormData`,
/// sorting each part into a field or a file by whether its `Content-Disposition`
/// carries a `filename`. `None` when the body breaks `limits`.
fn parse_multipart(
  body : Bytes,
  boundary : String,
  limits : FormLimits,
) -> FormData? {
  let fields : Array[FormField] = []
  let files : Array[UploadFile] = []
  let parts = match split_parts(body, boundary, limits.max_parts) {
    Some(ps) => ps
    None => return None
  }
  for part in parts {
    if part.content_end - part.content_start > limits.max_part_size {
      return None
    }
    let disposition = header_of(part.headers, "content-disposition").unwrap_or(
      "",
    )
    let name = header_param(disposition, "name").unwrap_or("")
    let content = body[part.content_start:part.content_end].to_owned()
    match header_param(disposition, "filename") {
      Some(filename) => {
        let content_type = header_of(part.headers, "content-type").unwrap_or("")
        files.push({
          name,
          filename,
          content_type,
          content,
          headers: part.headers,
        })
      }
      None => fields.push({ name, value: @utf8.decode_lossy(content[:]), })
    }
  }
  Some({ fields, files, })
}

///|
/// The `boundary` parameter of a `multipart/form-data` content-type header,
/// `None` if it's absent.
fn boundary_of(content_type : String) -> String? {
  header_param(content_type, "boundary")
}

// -- Context extractors -------------------------------------------------------

///|
/// The parsed request form — FastAPI's `Form(...)` / `File(...)` parameters.
/// Dispatches on the `Content-Type`: a `multipart/form-data` body is split on
/// its boundary into fields and files, an `application/x-www-form-urlencoded`
/// body is decoded into fields. Any other (or absent) content type yields an
/// empty form rather than raising, so the extractor stays total.
///
/// `None` when the body breaks `limits` — more parts than `max_parts`, or a part
/// longer than `max_part_size`. The form is refused whole rather than truncated:
/// a handler given the first thousand parts of a larger form would answer a
/// request nobody sent. An empty `Some` is the other answer, and means the
/// request carried no form at all.
pub fn Context::form(
  self : Context,
  limits? : FormLimits = FormLimits::new(),
) -> FormData? {
  let ct = self.request.header("content-type").unwrap_or("")
  let ct_lower = ct.to_lower()
  if str_index_of(ct_lower, "multipart/form-data", 0) >= 0 {
    match boundary_of(ct) {
      Some(b) => parse_multipart(self.request.body, b, limits)
      None => Some({ fields: [], files: [], })
    }
  } else if str_index_of(ct_lower, "application/x-www-form-urlencoded", 0) >= 0 {
    match parse_urlencoded(self.request.body, limits) {
      Some(fields) => Some({ fields, files: [], })
      None => None
    }
  } else {
    Some({ fields: [], files: [], })
  }
}

///|
pub extend FormField with Eq::{not_equal, equal}

///|
pub extend UploadFile with Eq::{not_equal, equal}

///|
pub extend FormData with Eq::{not_equal, equal}

///|
pub extend FormLimits with Eq::{not_equal, equal}
