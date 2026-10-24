///|
/// Look up a query-string parameter by name, e.g. `?limit=10&q=cat%20dog`. Keys and
/// values are percent/plus-decoded, so `q` above reads back as `cat dog`. When a key
/// repeats, the first occurrence wins; use `query_all` to read every one.
pub fn Context::query(
  self : Context,
  name : String,
  limits~ : @moonurl.Limits = @schema.query_limits,
) -> String? {
  query_of(self.request.query_string, limits).get(name[:])
}

///|
/// Every value given for `name`, in the order they appear — `?tag=a&tag=b` reads
/// back as `["a", "b"]`. Empty when the key is absent.
pub fn Context::query_all(
  self : Context,
  name : String,
  limits~ : @moonurl.Limits = @schema.query_limits,
) -> Array[String] {
  query_of(self.request.query_string, limits).values(name[:])
}

///|
/// Parse the request body as JSON, returning `None` for an empty body or one
/// that does not parse — the total counterpart of FastAPI reading a JSON body.
pub fn Context::body_json(self : Context) -> Json? {
  let s = decode_field(self.request.body)
  if s == "" {
    return None
  }
  Some(@moonjson.loads(s[:], @moonjson.strict)) catch {
    _ => None
  }
}

///|
/// Pull a single field out of a JSON object body by name, `None` if the body is
/// absent, not an object, or lacks the field.
pub fn Context::json_field(self : Context, name : String) -> Json? {
  match self.body_json() {
    Some(Object(m)) => m.get(name)
    _ => None
  }
}

///|
/// Look up a cookie by name from the request `Cookie` header, which is a
/// `; `-separated list of `key=value` pairs. Spaces around a name or a value are
/// the separators'; `None` if there is no `Cookie` header or the name is absent.
pub fn Context::cookie(self : Context, name : String) -> String? {
  match self.request.header("cookie") {
    None => None
    Some(raw) => @cookie.get(raw[:], name[:])
  }
}

///|
/// Decode a `Bytes` request field to text, replacing any malformed UTF-8 rather
/// than raising — inbound bytes are attacker-controlled, so extraction stays
/// total.
fn decode_field(raw : Bytes) -> String {
  @utf8.decode_lossy(raw[:])
}

///|
/// The query string as pairs, or none at all when it breaks its bounds.
///
/// A query string is `application/x-www-form-urlencoded`, so the decoding is
/// moonurl's: splitting on the raw bytes so a percent-escaped `&` or `=` inside a
/// value cannot be mistaken for a separator, `+` as a space, and a pair with no
/// `=` as a bare key.
fn query_of(raw : Bytes, limits : @moonurl.Limits) -> @moonurl.Query {
  @moonurl.Query::decode(raw[:], limits~) catch {
    _ => @moonurl.Query::new()
  }
}

///|
/// Trim ASCII spaces and tabs from both ends of `s` (core has no `trim`).
fn trim_spaces(s : String) -> String {
  let n = s.length()
  let mut a = 0
  let mut b = n
  while a < b && (s[a].to_int() == 0x20 || s[a].to_int() == 0x09) {
    a = a + 1
  }
  while b > a && (s[b - 1].to_int() == 0x20 || s[b - 1].to_int() == 0x09) {
    b = b - 1
  }
  s[a:b].to_owned()
}
