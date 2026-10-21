// Responses that are an envelope rather than a body: a redirect, a download,
// a data URL, and a download that weighs the request first.

///|
/// [`file_response`] with the request weighed first (RFC 9110 §13, §14):
///
/// * `304` — the client's copy is current.
/// * `412` — a precondition it stated does not hold.
/// * `206` — it asked for part, one `Content-Range` or a `multipart/byteranges`.
/// * `416` — it asked for what is not there.
///
/// Everything turns on `etag`. Left out, one is hashed from the content, which
/// costs a pass over the body; pass `@conditional.stamp(length~, modified~)` for
/// one stat's worth instead, or any tag of your own.
///
/// `ranges=false` withdraws the offer in `Accept-Ranges`.
pub fn Context::serve(
  self : Context,
  content : Bytes,
  filename~ : String = "",
  media_type~ : String = "",
  inline~ : Bool = false,
  etag? : @conditional.Tag,
  modified? : @moondate.Moment,
  ranges~ : Bool = true,
) -> @moonasgi.Response {
  let tag = match etag {
    Some(tag) => tag
    None => @conditional.hash(content[:], digest=@sha2.Hasher::new())
  }
  let verb = self.request.http_method
  let ask = @conditional.Ask::read(self.request.headers[:])
  let validators = [("etag", tag.encode())]
  match modified {
    Some(modified) =>
      validators.push(("last-modified", modified.http_text())) catch {
        _ => ()
      }
    None => ()
  }
  match ask.evaluate(verb~, etag=tag, modified?) {
    // §15.4.5: no body, and the validators the 200 would have carried.
    Fresh => @moonasgi.Response::new(304, validators, b"")
    Failed => @moonasgi.Response::new(412, validators, b"")
    Go => {
      let headers = @status.envelope(
        content.length(),
        filename,
        media_type,
        inline,
      )
      for one in validators {
        headers.push(one)
      }
      headers.push(("accept-ranges", if ranges { "bytes" } else { "none" }))
      if !ranges || verb != "GET" {
        return @moonasgi.Response::new(200, headers, body(verb, content))
      }
      // §13.1.5: a Range that If-Range ruled out asks for the whole thing.
      guard asked(self.request.headers, "range") is Some(field) &&
        ask.unchanged(etag=tag, modified?) else {
        return @moonasgi.Response::new(200, headers, body(verb, content))
      }
      guard @range.decode(field[:]) is Some(specs) else {
        return @moonasgi.Response::new(200, headers, body(verb, content))
      }
      let whole = content.length().to_int64()
      guard @range.measure(specs[:], length=whole) is Some(parts) else {
        let refused = [("content-range", @range.unsatisfied(whole).encode())]
        return @moonasgi.Response::new(416, refused, b"")
      }
      partial(verb, content, parts, headers, whole)
    }
  }
}

///|
/// The 206, in whichever shape was asked for (§14.4, §14.6).
fn partial(
  verb : String,
  content : Bytes,
  parts : Array[@range.Part],
  headers : Array[(String, String)],
  whole : Int64,
) -> @moonasgi.Response {
  let kind = field_of(headers, "content-type")
  if parts.length() == 1 {
    let part = parts[0]
    let piece = cut(content, part)
    let out = without(headers, ["content-length", "accept-ranges"])
    out.push(("content-length", piece.length().to_string()))
    out.push(("accept-ranges", "bytes"))
    out.push(
      ("content-range", @range.Content::new(part, complete=whole).encode()),
    )
    return @moonasgi.Response::new(206, out, body(verb, piece))
  }
  // From the tag rather than at random: this package holds no randomness, and a
  // boundary that changed between identical requests could not be tested.
  let boundary = "moonapi-" + token(field_of(headers, "etag"))
  let pieces = parts.map(fn(part) { (part, cut(content, part)) })
  let piece = @range.parts(pieces[:], boundary~, kind~, complete=whole)
  let out = without(headers, ["content-type", "content-length"])
  out.push(("content-type", @range.multipart(boundary[:])))
  out.push(("content-length", piece.length().to_string()))
  @moonasgi.Response::new(206, out, body(verb, piece))
}

///|
/// A request header by name, ignoring case — the rule `Ask::read` uses, so
/// `Range` and `If-Range` are not read by two different ones.
fn asked(headers : Array[(String, String)], name : String) -> String? {
  for pair in headers {
    if pair.0.to_lower() == name {
      return Some(pair.1)
    }
  }
  None
}

///|
/// A `HEAD` gets the headers and nothing after them (§9.3.2).
fn body(verb : String, content : Bytes) -> Bytes {
  if verb == "HEAD" {
    b""
  } else {
    content
  }
}

///|
fn cut(content : Bytes, part : @range.Part) -> Bytes {
  let out : Array[Byte] = []
  for i = part.at.to_int(); i <= part.last.to_int(); i = i + 1 {
    out.push(content[i])
  }
  Bytes::from_array(out)
}

///|
fn field_of(headers : Array[(String, String)], name : String) -> String {
  for pair in headers {
    if pair.0 == name {
      return pair.1
    }
  }
  ""
}

///|
/// The part of a tag a boundary may contain, within the seventy octets RFC 2046
/// §5.1.1 allows, less the prefix's eight.
fn token(text : String) -> String {
  let out = StringBuilder()
  for i = 0; i < text.length(); i = i + 1 {
    let b = text[i].to_int()
    let ok = (b >= 0x41 && b <= 0x5A) ||
      (b >= 0x61 && b <= 0x7A) ||
      (b >= 0x30 && b <= 0x39) ||
      b == 0x2D
    if ok {
      out.write_char(b.unsafe_to_char())
    }
  }
  let text = out.to_string()
  if text == "" {
    return "part"
  }
  if text.length() > 62 {
    text[text.length() - 62:].to_owned()
  } else {
    text
  }
}

///|
fn without(
  headers : Array[(String, String)],
  names : Array[String],
) -> Array[(String, String)] {
  let out : Array[(String, String)] = []
  for pair in headers {
    let mut drop = false
    for name in names {
      if pair.0 == name {
        drop = true
      }
    }
    if !drop {
      out.push(pair)
    }
  }
  out
}
