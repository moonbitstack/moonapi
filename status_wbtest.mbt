// The re-exported status constants. The only thing that can go wrong with a
// table of 78 numbers is a number, so the test is the one invariant that
// matters: every name is bound to the code it spells out. Written as pairs
// rather than generated from the table, since a check derived from the values
// it is checking would agree with any of them.

///|
/// The 63 HTTP codes FastAPI re-exports, each against the number in its own name.
test "every HTTP status constant is bound to the code its name spells" {
  let named : Array[(Int32, Int32)] = [
    (@status.HTTP_100_CONTINUE, 100),
    (@status.HTTP_101_SWITCHING_PROTOCOLS, 101),
    (@status.HTTP_102_PROCESSING, 102),
    (@status.HTTP_103_EARLY_HINTS, 103),
    (@status.HTTP_200_OK, 200),
    (@status.HTTP_201_CREATED, 201),
    (@status.HTTP_202_ACCEPTED, 202),
    (@status.HTTP_203_NON_AUTHORITATIVE_INFORMATION, 203),
    (@status.HTTP_204_NO_CONTENT, 204),
    (@status.HTTP_205_RESET_CONTENT, 205),
    (@status.HTTP_206_PARTIAL_CONTENT, 206),
    (@status.HTTP_207_MULTI_STATUS, 207),
    (@status.HTTP_208_ALREADY_REPORTED, 208),
    (@status.HTTP_226_IM_USED, 226),
    (@status.HTTP_300_MULTIPLE_CHOICES, 300),
    (@status.HTTP_301_MOVED_PERMANENTLY, 301),
    (@status.HTTP_302_FOUND, 302),
    (@status.HTTP_303_SEE_OTHER, 303),
    (@status.HTTP_304_NOT_MODIFIED, 304),
    (@status.HTTP_305_USE_PROXY, 305),
    (@status.HTTP_306_RESERVED, 306),
    (@status.HTTP_307_TEMPORARY_REDIRECT, 307),
    (@status.HTTP_308_PERMANENT_REDIRECT, 308),
    (@status.HTTP_400_BAD_REQUEST, 400),
    (@status.HTTP_401_UNAUTHORIZED, 401),
    (@status.HTTP_402_PAYMENT_REQUIRED, 402),
    (@status.HTTP_403_FORBIDDEN, 403),
    (@status.HTTP_404_NOT_FOUND, 404),
    (@status.HTTP_405_METHOD_NOT_ALLOWED, 405),
    (@status.HTTP_406_NOT_ACCEPTABLE, 406),
    (@status.HTTP_407_PROXY_AUTHENTICATION_REQUIRED, 407),
    (@status.HTTP_408_REQUEST_TIMEOUT, 408),
    (@status.HTTP_409_CONFLICT, 409),
    (@status.HTTP_410_GONE, 410),
    (@status.HTTP_411_LENGTH_REQUIRED, 411),
    (@status.HTTP_412_PRECONDITION_FAILED, 412),
    (@status.HTTP_413_REQUEST_ENTITY_TOO_LARGE, 413),
    (@status.HTTP_414_REQUEST_URI_TOO_LONG, 414),
    (@status.HTTP_415_UNSUPPORTED_MEDIA_TYPE, 415),
    (@status.HTTP_416_REQUESTED_RANGE_NOT_SATISFIABLE, 416),
    (@status.HTTP_417_EXPECTATION_FAILED, 417),
    (@status.HTTP_418_IM_A_TEAPOT, 418),
    (@status.HTTP_421_MISDIRECTED_REQUEST, 421),
    (@status.HTTP_422_UNPROCESSABLE_ENTITY, 422),
    (@status.HTTP_423_LOCKED, 423),
    (@status.HTTP_424_FAILED_DEPENDENCY, 424),
    (@status.HTTP_425_TOO_EARLY, 425),
    (@status.HTTP_426_UPGRADE_REQUIRED, 426),
    (@status.HTTP_428_PRECONDITION_REQUIRED, 428),
    (@status.HTTP_429_TOO_MANY_REQUESTS, 429),
    (@status.HTTP_431_REQUEST_HEADER_FIELDS_TOO_LARGE, 431),
    (@status.HTTP_451_UNAVAILABLE_FOR_LEGAL_REASONS, 451),
    (@status.HTTP_500_INTERNAL_SERVER_ERROR, 500),
    (@status.HTTP_501_NOT_IMPLEMENTED, 501),
    (@status.HTTP_502_BAD_GATEWAY, 502),
    (@status.HTTP_503_SERVICE_UNAVAILABLE, 503),
    (@status.HTTP_504_GATEWAY_TIMEOUT, 504),
    (@status.HTTP_505_HTTP_VERSION_NOT_SUPPORTED, 505),
    (@status.HTTP_506_VARIANT_ALSO_NEGOTIATES, 506),
    (@status.HTTP_507_INSUFFICIENT_STORAGE, 507),
    (@status.HTTP_508_LOOP_DETECTED, 508),
    (@status.HTTP_510_NOT_EXTENDED, 510),
    (@status.HTTP_511_NETWORK_AUTHENTICATION_REQUIRED, 511),
  ]
  for pair in named {
    assert_eq(pair.0, pair.1)
  }
  assert_eq(named.length(), 63)
}

///|
/// The 15 WebSocket close codes, the same way.
test "every WebSocket close constant is bound to the code its name spells" {
  let named : Array[(Int32, Int32)] = [
    (@status.WS_1000_NORMAL_CLOSURE, 1000),
    (@status.WS_1001_GOING_AWAY, 1001),
    (@status.WS_1002_PROTOCOL_ERROR, 1002),
    (@status.WS_1003_UNSUPPORTED_DATA, 1003),
    (@status.WS_1005_NO_STATUS_RCVD, 1005),
    (@status.WS_1006_ABNORMAL_CLOSURE, 1006),
    (@status.WS_1007_INVALID_FRAME_PAYLOAD_DATA, 1007),
    (@status.WS_1008_POLICY_VIOLATION, 1008),
    (@status.WS_1009_MESSAGE_TOO_BIG, 1009),
    (@status.WS_1010_MANDATORY_EXT, 1010),
    (@status.WS_1011_INTERNAL_ERROR, 1011),
    (@status.WS_1012_SERVICE_RESTART, 1012),
    (@status.WS_1013_TRY_AGAIN_LATER, 1013),
    (@status.WS_1014_BAD_GATEWAY, 1014),
    (@status.WS_1015_TLS_HANDSHAKE, 1015),
  ]
  for pair in named {
    assert_eq(pair.0, pair.1)
  }
  assert_eq(named.length(), 15)
}
