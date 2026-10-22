///|
/// `extra` adds claims. Where it names one the arguments already set, the
/// arguments win — and being given two answers is reported rather than one of
/// them being dropped in silence.
test "extra adds claims and cannot quietly replace them" {
  let secret = "a-secret"
  let plain = create_access_token("heke", secret, 1700000000L)
  let with_extra = create_access_token("heke", secret, 1700000000L, extra={
    "tenant": Json::string("acme"),
  })
  assert_not_eq(plain, with_extra)
  let claims = @jwt.verify(
    with_extra[:],
    HS256,
    hs256(secret),
    now=At(1700000100L),
  )
  assert_eq(claims.get("tenant"), Some(Json::string("acme")))
  assert_eq(claims.get("sub"), Some(Json::string("heke")))
  // Asked to let `extra` win, it does.
  let overridden = create_access_token(
    "heke",
    secret,
    1700000000L,
    extra={ "sub": Json::string("somebody else") },
    wins=Extra,
    clash=Ignore,
  )
  let claims = @jwt.verify(
    overridden[:],
    HS256,
    hs256(secret),
    now=At(1700000100L),
  )
  assert_eq(claims.get("sub"), Some(Json::string("somebody else")))
  // Silenced without flipping the direction, the argument still wins.
  let kept = create_access_token(
    "heke",
    secret,
    1700000000L,
    extra={ "sub": Json::string("somebody else") },
    clash=Ignore,
  )
  let claims = @jwt.verify(kept[:], HS256, hs256(secret), now=At(1700000100L))
  assert_eq(claims.get("sub"), Some(Json::string("heke")))
}

///|
test "create_access_token stamps sub / iat / exp / scopes and verifies" {
  let token = create_access_token(
    "alice",
    "secret",
    1000L,
    scopes=["me", "items"],
    expires_in_secs=60L,
  )
  let c = @jwt.verify(token[:], HS256, hs256("secret"), now=At(1000L))
  assert_eq(c.get("sub"), Some(Json("alice")))
  // iat / exp are JSON numbers (NumericDate), not strings.
  assert_eq(c.get("iat"), Some(Json(1000.0)))
  assert_eq(c.get("exp"), Some(Json(1060.0)))
  assert_eq(c.get("scopes"), Some(Json(["me", "items"])))
}
