///|
/// base64url encoding (RFC 4648 §5, no padding): standard base64 with `+`/`/`
/// remapped to `-`/`_` and trailing `=` dropped — the alphabet JWT uses for its
/// header, payload, and signature segments.
pub fn base64url_encode(data : Bytes) -> String {
  @base64.encode(data[:], kind=Url, padding=false)
}

///|
/// Decode a base64url string (padding optional) back to bytes, remapping
/// `-`/`_` to `+`/`/` first. Lenient about missing padding, the way JWT
/// segments are written.
pub fn base64url_decode(s : String) -> Bytes {
  @base64.decode_lossy(s, kind=Url)
}

///|
/// A JWT verification failure. Each way a token can be rejected is reported
/// distinctly so the `Security` layer can map it to the right status and a
/// caller can log precisely which check failed.
pub suberror JwtError {
  /// Not three `.`-separated segments, an un-decodable segment, or a payload
  /// that isn't a JSON object.
  MalformedToken(String)
  /// The header's `alg` is missing or isn't `HS256` — this is where the
  /// `alg: "none"` downgrade is refused.
  UnsupportedAlg(String)
  /// The recomputed HMAC signature doesn't match the token's signature.
  BadSignature
  /// The `exp` claim is at or before the verification time.
  Expired
  /// The `nbf` (not-before) claim is after the verification time.
  NotYetValid
}

///|
/// Split a string on a single ASCII delimiter. Core ships no `String::split`, so
/// it's hand-written; used to break a `header.payload.sig` token into three.
fn split_char(s : String, delim : Char) -> Array[String] {
  let out : Array[String] = []
  let sb = StringBuilder()
  let d = delim.to_int()
  for i = 0; i < s.length(); i = i + 1 {
    if s[i].to_int() == d {
      out.push(sb.to_string())
      sb.reset()
    } else {
      sb.write_char(s[i].unsafe_to_char())
    }
  }
  out.push(sb.to_string())
  out
}

///|
/// The signing input `base64url(header).base64url(payload)` as bytes: the exact
/// octets HMAC-SHA256 runs over, shared by signing and verification.
fn jwt_signing_input(header_seg : String, payload_seg : String) -> Bytes {
  @utf8.encode(header_seg + "." + payload_seg)
}

///|
/// Sign a claims set as a compact JWT using HS256. The header is fixed to
/// `{"alg":"HS256","typ":"JWT"}`; `claims` is serialised as the JSON payload
/// (`exp` / `iat` / `nbf` / `sub` / `scopes` go in as ordinary entries);
/// `secret` is the shared HS256 key. Returns `header.payload.signature`, each
/// segment base64url-encoded.
pub fn jwt_sign(claims : Map[String, Json], secret : String) -> String {
  let header_json =
    #|{"alg":"HS256","typ":"JWT"}
  let header_seg = base64url_encode(@utf8.encode(header_json))
  let payload_seg = base64url_encode(@utf8.encode(claims.to_json().stringify()))
  let sig = hmac_sha256(
    @utf8.encode(secret),
    jwt_signing_input(header_seg, payload_seg),
  )
  header_seg + "." + payload_seg + "." + base64url_encode(sig)
}

///|
/// Read the header segment's `alg`, raising `UnsupportedAlg` for anything but
/// `HS256` — where the `alg: "none"` downgrade is refused.
fn check_alg(header_seg : String) -> Unit raise JwtError {
  let text = @utf8.decode_lossy(base64url_decode(header_seg)[:])
  let json = @json.parse(text) catch {
    _ => raise MalformedToken("header is not valid JSON")
  }
  match json {
    Object(m) =>
      match m.get("alg") {
        Some(String("HS256")) => ()
        Some(String(other)) => raise UnsupportedAlg(other)
        _ => raise UnsupportedAlg("missing alg")
      }
    _ => raise MalformedToken("header is not a JSON object")
  }
}

///|
/// Verify a compact HS256 JWT and return its claims. Checks, in order: three
/// segments; header `alg` is `HS256`; the HMAC-SHA256 signature matches
/// (compared in constant time); `exp` (if present) is strictly after
/// `now_secs`; `nbf` (if present) is at or before `now_secs`. `now_secs` is the
/// verification time as a Unix timestamp in seconds (JWT `NumericDate`). Raises
/// the matching `JwtError` on any failure; a tampered payload or signature fails
/// at `BadSignature`.
pub fn jwt_verify(
  token : String,
  secret : String,
  now_secs : Int64,
) -> Map[String, Json] raise JwtError {
  let parts = split_char(token, '.')
  if parts.length() != 3 {
    raise MalformedToken("expected three segments")
  }
  let header_seg = parts[0]
  let payload_seg = parts[1]
  let sig_seg = parts[2]
  check_alg(header_seg)
  let expected = hmac_sha256(
    @utf8.encode(secret),
    jwt_signing_input(header_seg, payload_seg),
  )
  let given = base64url_decode(sig_seg)
  if !constant_time_eq(expected, given) {
    raise BadSignature
  }
  parse_and_check_claims(payload_seg, now_secs)
}

///|
/// Decode the payload segment to its claims and enforce the time claims — `exp`
/// (rejected at or after `now_secs`) and `nbf` (rejected before it). Shared by the
/// HS256 and RS256 verification paths.
fn parse_and_check_claims(
  payload_seg : String,
  now_secs : Int64,
) -> Map[String, Json] raise JwtError {
  let payload_text = @utf8.decode_lossy(base64url_decode(payload_seg)[:])
  let payload = @json.parse(payload_text) catch {
    _ => raise MalformedToken("payload is not valid JSON")
  }
  let claims = match payload {
    Object(m) => m
    _ => raise MalformedToken("payload is not a JSON object")
  }
  match claim_seconds(claims, "exp") {
    Some(exp) => if now_secs.to_double() >= exp { raise Expired }
    None => ()
  }
  match claim_seconds(claims, "nbf") {
    Some(nbf) => if now_secs.to_double() < nbf { raise NotYetValid }
    None => ()
  }
  claims
}

///|
/// Read the header segment's `alg`, raising `UnsupportedAlg` for anything but
/// `RS256` — the RS256 counterpart of `check_alg`, refusing an `alg` downgrade.
fn check_alg_rs256(header_seg : String) -> Unit raise JwtError {
  let text = @utf8.decode_lossy(base64url_decode(header_seg)[:])
  let json = @json.parse(text) catch {
    _ => raise MalformedToken("header is not valid JSON")
  }
  match json {
    Object(m) =>
      match m.get("alg") {
        Some(String("RS256")) => ()
        Some(String(other)) => raise UnsupportedAlg(other)
        _ => raise UnsupportedAlg("missing alg")
      }
    _ => raise MalformedToken("header is not a JSON object")
  }
}

///|
/// Sign a claims set as a compact JWT using RS256 (RSASSA-PKCS1-v1_5 + SHA-256).
/// The header is fixed to `{"alg":"RS256","typ":"JWT"}`; `key` is the RSA private
/// key. Returns `header.payload.signature`, each segment base64url-encoded.
pub fn jwt_sign_rs256(
  claims : Map[String, Json],
  key : RsaPrivateKey,
) -> String {
  let header_json =
    #|{"alg":"RS256","typ":"JWT"}
  let header_seg = base64url_encode(@utf8.encode(header_json))
  let payload_seg = base64url_encode(@utf8.encode(claims.to_json().stringify()))
  let sig = rsa_pkcs1_sha256_sign(
    jwt_signing_input(header_seg, payload_seg),
    key,
  )
  header_seg + "." + payload_seg + "." + base64url_encode(sig)
}

///|
/// Verify a compact RS256 JWT and return its claims. Checks three segments; the
/// header `alg` is `RS256`; the RSASSA-PKCS1-v1_5 signature verifies against
/// `key`; and the `exp` / `nbf` time claims. Raises the matching `JwtError`; a
/// tampered payload or signature fails at `BadSignature`.
pub fn jwt_verify_rs256(
  token : String,
  key : RsaPublicKey,
  now_secs : Int64,
) -> Map[String, Json] raise JwtError {
  let parts = split_char(token, '.')
  if parts.length() != 3 {
    raise MalformedToken("expected three segments")
  }
  let header_seg = parts[0]
  let payload_seg = parts[1]
  let sig_seg = parts[2]
  check_alg_rs256(header_seg)
  let sig = base64url_decode(sig_seg)
  if !rsa_pkcs1_sha256_verify(
      jwt_signing_input(header_seg, payload_seg),
      sig,
      key,
    ) {
    raise BadSignature
  }
  parse_and_check_claims(payload_seg, now_secs)
}

///|
/// Read the header segment's `alg`, raising `UnsupportedAlg` for anything but
/// `ES256` — the ES256 counterpart of `check_alg`, refusing an `alg` downgrade.
fn check_alg_es256(header_seg : String) -> Unit raise JwtError {
  let text = @utf8.decode_lossy(base64url_decode(header_seg)[:])
  let json = @json.parse(text) catch {
    _ => raise MalformedToken("header is not valid JSON")
  }
  match json {
    Object(m) =>
      match m.get("alg") {
        Some(String("ES256")) => ()
        Some(String(other)) => raise UnsupportedAlg(other)
        _ => raise UnsupportedAlg("missing alg")
      }
    _ => raise MalformedToken("header is not a JSON object")
  }
}

///|
/// Verify a compact ES256 JWT and return its claims. Checks three segments; the
/// header `alg` is `ES256`; the ECDSA-P256 / SHA-256 signature (raw `r || s`, the
/// JWS encoding) verifies against `key`; and the `exp` / `nbf` time claims. Raises
/// the matching `JwtError`; a tampered payload or signature fails at
/// `BadSignature`.
pub fn jwt_verify_es256(
  token : String,
  key : EcdsaPublicKey,
  now_secs : Int64,
) -> Map[String, Json] raise JwtError {
  let parts = split_char(token, '.')
  if parts.length() != 3 {
    raise MalformedToken("expected three segments")
  }
  let header_seg = parts[0]
  let payload_seg = parts[1]
  let sig_seg = parts[2]
  check_alg_es256(header_seg)
  let sig = base64url_decode(sig_seg)
  if !ecdsa_p256_sha256_verify(
      jwt_signing_input(header_seg, payload_seg),
      sig,
      key,
    ) {
    raise BadSignature
  }
  parse_and_check_claims(payload_seg, now_secs)
}

///|
/// Sign a claims set as a compact JWT using ES256 (ECDSA P-256 / SHA-256 with the
/// deterministic RFC 6979 nonce). The header is fixed to
/// `{"alg":"ES256","typ":"JWT"}`; `key` is the P-256 private key. Returns
/// `header.payload.signature`, each segment base64url-encoded.
pub fn jwt_sign_es256(
  claims : Map[String, Json],
  key : EcdsaPrivateKey,
) -> String {
  let header_json =
    #|{"alg":"ES256","typ":"JWT"}
  let header_seg = base64url_encode(@utf8.encode(header_json))
  let payload_seg = base64url_encode(@utf8.encode(claims.to_json().stringify()))
  let sig = ecdsa_p256_sha256_sign(
    jwt_signing_input(header_seg, payload_seg),
    key,
  )
  header_seg + "." + payload_seg + "." + base64url_encode(sig)
}

///|
/// Read the header segment's `alg`, raising `UnsupportedAlg` for anything but
/// `EdDSA` — the EdDSA counterpart of `check_alg`, refusing an `alg` downgrade.
fn check_alg_eddsa(header_seg : String) -> Unit raise JwtError {
  let text = @utf8.decode_lossy(base64url_decode(header_seg)[:])
  let json = @json.parse(text) catch {
    _ => raise MalformedToken("header is not valid JSON")
  }
  match json {
    Object(m) =>
      match m.get("alg") {
        Some(String("EdDSA")) => ()
        Some(String(other)) => raise UnsupportedAlg(other)
        _ => raise UnsupportedAlg("missing alg")
      }
    _ => raise MalformedToken("header is not a JSON object")
  }
}

///|
/// Verify a compact EdDSA (Ed25519) JWT and return its claims (RFC 8037). Checks
/// three segments; the header `alg` is `EdDSA`; the Ed25519 signature verifies
/// against `key`; and the `exp` / `nbf` time claims. Raises the matching
/// `JwtError`; a tampered payload or signature fails at `BadSignature`.
pub fn jwt_verify_eddsa(
  token : String,
  key : Ed25519PublicKey,
  now_secs : Int64,
) -> Map[String, Json] raise JwtError {
  let parts = split_char(token, '.')
  if parts.length() != 3 {
    raise MalformedToken("expected three segments")
  }
  let header_seg = parts[0]
  let payload_seg = parts[1]
  let sig_seg = parts[2]
  check_alg_eddsa(header_seg)
  let sig = base64url_decode(sig_seg)
  if !ed25519_verify(key.key, jwt_signing_input(header_seg, payload_seg), sig) {
    raise BadSignature
  }
  parse_and_check_claims(payload_seg, now_secs)
}

///|
/// Sign a claims set as a compact JWT using EdDSA (Ed25519, RFC 8037). The header
/// is fixed to `{"alg":"EdDSA","typ":"JWT"}`; `key` is the Ed25519 private key.
/// Returns `header.payload.signature`, each segment base64url-encoded.
pub fn jwt_sign_eddsa(
  claims : Map[String, Json],
  key : Ed25519PrivateKey,
) -> String {
  let header_json =
    #|{"alg":"EdDSA","typ":"JWT"}
  let header_seg = base64url_encode(@utf8.encode(header_json))
  let payload_seg = base64url_encode(@utf8.encode(claims.to_json().stringify()))
  let sig = ed25519_sign(key.seed, jwt_signing_input(header_seg, payload_seg))
  header_seg + "." + payload_seg + "." + base64url_encode(sig)
}

///|
/// Read a `NumericDate` claim as seconds. RFC 7519 says it's a JSON number, but
/// tokens in the wild sometimes carry it as a numeric string, so both are
/// accepted; anything else (or an absent claim) is `None`.
fn claim_seconds(claims : Map[String, Json], key : String) -> Double? {
  match claims.get(key) {
    Some(Number(n, ..)) => Some(n)
    Some(String(s)) => parse_int(s).map(fn(i) { i.to_double() })
    _ => None
  }
}
