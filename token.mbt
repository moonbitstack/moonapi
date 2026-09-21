// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The HS256 key a shared secret stands for.
///
/// This is the whole of moonapi's relationship with cryptography: it names an
/// algorithm and hands `mooncred` something that can sign. Nothing here knows
/// what SHA-256 is, and a deployment that wants ES256 passes its own signer to
/// `mooncred` without moonapi being involved.
fn hs256(secret : String) -> @jwt.Keyed {
  let key = @utf8.encode(secret[:])
  @jwt.mac(fn() { @hmac.Hmac::new(key[:], fn() { @sha2.Hasher::new() }) })
}
