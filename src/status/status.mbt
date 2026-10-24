// The status codes FastAPI re-exports from Starlette's `status`, under the same
// names, so a handler reads `HTTP_404_NOT_FOUND` rather than a bare `404` and a
// reader of the route table can tell a deliberate `307` from a typo. The values
// are the IANA registry's; the names are Starlette's, which keeps a few phrases
// history has since revised — `HTTP_413_REQUEST_ENTITY_TOO_LARGE` is RFC 9110's
// "Content Too Large" — because renaming them would break the parity that makes
// them worth re-exporting.

///|
/// Continue: the headers are acceptable, send the body.
pub const HTTP_100_CONTINUE : Int32 = 100

///|
/// Switching Protocols: the server is changing to the protocol `Upgrade` asked for.
pub const HTTP_101_SWITCHING_PROTOCOLS : Int32 = 101

///|
/// Processing: WebDAV, the request is under way and the reply will follow.
pub const HTTP_102_PROCESSING : Int32 = 102

///|
/// Early Hints: preload links sent ahead of the real response.
pub const HTTP_103_EARLY_HINTS : Int32 = 103

///|
/// OK.
pub const HTTP_200_OK : Int32 = 200

///|
/// Created: the request made a new resource, named in `Location`.
pub const HTTP_201_CREATED : Int32 = 201

///|
/// Accepted: taken for processing, outcome not yet known.
pub const HTTP_202_ACCEPTED : Int32 = 202

///|
/// Non-Authoritative Information: an intermediary altered the origin's payload.
pub const HTTP_203_NON_AUTHORITATIVE_INFORMATION : Int32 = 203

///|
/// No Content: succeeded, and there is nothing to send back.
pub const HTTP_204_NO_CONTENT : Int32 = 204

///|
/// Reset Content: succeeded; the client should clear the form that sent it.
pub const HTTP_205_RESET_CONTENT : Int32 = 205

///|
/// Partial Content: the byte ranges `Range` asked for.
pub const HTTP_206_PARTIAL_CONTENT : Int32 = 206

///|
/// Multi-Status: WebDAV, one status per member of a collection.
pub const HTTP_207_MULTI_STATUS : Int32 = 207

///|
/// Already Reported: WebDAV, this member was enumerated earlier in the reply.
pub const HTTP_208_ALREADY_REPORTED : Int32 = 208

///|
/// IM Used: the body is the result of applying delta encodings.
pub const HTTP_226_IM_USED : Int32 = 226

///|
/// Multiple Choices: several representations, pick one.
pub const HTTP_300_MULTIPLE_CHOICES : Int32 = 300

///|
/// Moved Permanently: use `Location` from now on.
pub const HTTP_301_MOVED_PERMANENTLY : Int32 = 301

///|
/// Found: a temporary move. Clients rewrite `POST` to `GET` here, which is why
/// `307` exists.
pub const HTTP_302_FOUND : Int32 = 302

///|
/// See Other: fetch the outcome with a `GET` at `Location` — the redirect after
/// a form post.
pub const HTTP_303_SEE_OTHER : Int32 = 303

///|
/// Not Modified: the client's cached copy is still current.
pub const HTTP_304_NOT_MODIFIED : Int32 = 304

///|
/// Use Proxy: deprecated by RFC 9110.
pub const HTTP_305_USE_PROXY : Int32 = 305

///|
/// Reserved: never standardised, and reserved so nothing else claims it.
pub const HTTP_306_RESERVED : Int32 = 306

///|
/// Temporary Redirect: like `302`, but the method and body must be kept.
pub const HTTP_307_TEMPORARY_REDIRECT : Int32 = 307

///|
/// Permanent Redirect: like `301`, but the method and body must be kept.
pub const HTTP_308_PERMANENT_REDIRECT : Int32 = 308

///|
/// Bad Request: malformed enough that the server will not act on it.
pub const HTTP_400_BAD_REQUEST : Int32 = 400

///|
/// Unauthorized: not authenticated. The reply must carry `WWW-Authenticate`.
pub const HTTP_401_UNAUTHORIZED : Int32 = 401

///|
/// Payment Required: reserved.
pub const HTTP_402_PAYMENT_REQUIRED : Int32 = 402

///|
/// Forbidden: authenticated, and still not allowed.
pub const HTTP_403_FORBIDDEN : Int32 = 403

///|
/// Not Found.
pub const HTTP_404_NOT_FOUND : Int32 = 404

///|
/// Method Not Allowed: the path exists under another verb, listed in `Allow`.
pub const HTTP_405_METHOD_NOT_ALLOWED : Int32 = 405

///|
/// Not Acceptable: nothing on offer matches the request's `Accept`.
pub const HTTP_406_NOT_ACCEPTABLE : Int32 = 406

///|
/// Proxy Authentication Required.
pub const HTTP_407_PROXY_AUTHENTICATION_REQUIRED : Int32 = 407

///|
/// Request Timeout: the client took too long to send it.
pub const HTTP_408_REQUEST_TIMEOUT : Int32 = 408

///|
/// Conflict: it clashes with the resource's current state.
pub const HTTP_409_CONFLICT : Int32 = 409

///|
/// Gone: it existed and was removed on purpose.
pub const HTTP_410_GONE : Int32 = 410

///|
/// Length Required: `Content-Length` is missing and this server insists on it.
pub const HTTP_411_LENGTH_REQUIRED : Int32 = 411

///|
/// Precondition Failed: an `If-*` header did not hold.
pub const HTTP_412_PRECONDITION_FAILED : Int32 = 412

///|
/// Content Too Large — Starlette's name keeps RFC 7231's "Request Entity Too Large".
pub const HTTP_413_REQUEST_ENTITY_TOO_LARGE : Int32 = 413

///|
/// URI Too Long — Starlette's name keeps RFC 7231's "Request-URI Too Long".
pub const HTTP_414_REQUEST_URI_TOO_LONG : Int32 = 414

///|
/// Unsupported Media Type: the body's `Content-Type` is one this route cannot read.
pub const HTTP_415_UNSUPPORTED_MEDIA_TYPE : Int32 = 415

///|
/// Range Not Satisfiable: no part of the requested range exists.
pub const HTTP_416_REQUESTED_RANGE_NOT_SATISFIABLE : Int32 = 416

///|
/// Expectation Failed: the `Expect` header cannot be met.
pub const HTTP_417_EXPECTATION_FAILED : Int32 = 417

///|
/// I'm a Teapot: RFC 2324's joke, kept because clients test for it.
pub const HTTP_418_IM_A_TEAPOT : Int32 = 418

///|
/// Misdirected Request: this connection is not authoritative for that authority.
pub const HTTP_421_MISDIRECTED_REQUEST : Int32 = 421

///|
/// Unprocessable Content: well-formed, and it fails validation — what `unprocessable`
/// returns.
pub const HTTP_422_UNPROCESSABLE_ENTITY : Int32 = 422

///|
/// Locked: WebDAV, the resource is locked.
pub const HTTP_423_LOCKED : Int32 = 423

///|
/// Failed Dependency: WebDAV, a request this one depended on failed.
pub const HTTP_424_FAILED_DEPENDENCY : Int32 = 424

///|
/// Too Early: replaying this early-data request could be a replay attack.
pub const HTTP_425_TOO_EARLY : Int32 = 425

///|
/// Upgrade Required: resend over the protocol named in `Upgrade`.
pub const HTTP_426_UPGRADE_REQUIRED : Int32 = 426

///|
/// Precondition Required: the server refuses to act on an unconditional write.
pub const HTTP_428_PRECONDITION_REQUIRED : Int32 = 428

///|
/// Too Many Requests: rate limited; `Retry-After` says when to come back.
pub const HTTP_429_TOO_MANY_REQUESTS : Int32 = 429

///|
/// Request Header Fields Too Large.
pub const HTTP_431_REQUEST_HEADER_FIELDS_TOO_LARGE : Int32 = 431

///|
/// Unavailable For Legal Reasons.
pub const HTTP_451_UNAVAILABLE_FOR_LEGAL_REASONS : Int32 = 451

///|
/// Internal Server Error: the fallback for an error the app did not map.
pub const HTTP_500_INTERNAL_SERVER_ERROR : Int32 = 500

///|
/// Not Implemented: the server does not support the method at all.
pub const HTTP_501_NOT_IMPLEMENTED : Int32 = 501

///|
/// Bad Gateway: an upstream sent something invalid.
pub const HTTP_502_BAD_GATEWAY : Int32 = 502

///|
/// Service Unavailable: down or overloaded, and expected back.
pub const HTTP_503_SERVICE_UNAVAILABLE : Int32 = 503

///|
/// Gateway Timeout: an upstream did not answer in time.
pub const HTTP_504_GATEWAY_TIMEOUT : Int32 = 504

///|
/// HTTP Version Not Supported.
pub const HTTP_505_HTTP_VERSION_NOT_SUPPORTED : Int32 = 505

///|
/// Variant Also Negotiates: the negotiation is configured in a circle.
pub const HTTP_506_VARIANT_ALSO_NEGOTIATES : Int32 = 506

///|
/// Insufficient Storage: WebDAV, no room to store the representation.
pub const HTTP_507_INSUFFICIENT_STORAGE : Int32 = 507

///|
/// Loop Detected: WebDAV, the traversal is cyclic.
pub const HTTP_508_LOOP_DETECTED : Int32 = 508

///|
/// Not Extended.
pub const HTTP_510_NOT_EXTENDED : Int32 = 510

///|
/// Network Authentication Required: a captive portal wants a login first.
pub const HTTP_511_NETWORK_AUTHENTICATION_REQUIRED : Int32 = 511

// The WebSocket close codes of RFC 6455 §7.4.1, the second half of what
// `status` re-exports. `1005`, `1006` and `1015` never travel on the wire — an
// endpoint reports them to its own application, so sending one is a protocol
// error rather than a close reason.

///|
/// Normal Closure: the purpose the connection was opened for is fulfilled.
pub const WS_1000_NORMAL_CLOSURE : Int32 = 1000

///|
/// Going Away: the peer is shutting down or navigating off the page.
pub const WS_1001_GOING_AWAY : Int32 = 1001

///|
/// Protocol Error.
pub const WS_1002_PROTOCOL_ERROR : Int32 = 1002

///|
/// Unsupported Data: a frame of a type this endpoint cannot accept.
pub const WS_1003_UNSUPPORTED_DATA : Int32 = 1003

///|
/// No Status Received: reported locally when a close frame carried no code.
pub const WS_1005_NO_STATUS_RCVD : Int32 = 1005

///|
/// Abnormal Closure: reported locally when the connection died without a close frame.
pub const WS_1006_ABNORMAL_CLOSURE : Int32 = 1006

///|
/// Invalid Frame Payload Data: a text frame that is not valid UTF-8, say.
pub const WS_1007_INVALID_FRAME_PAYLOAD_DATA : Int32 = 1007

///|
/// Policy Violation: the generic refusal when no other code fits.
pub const WS_1008_POLICY_VIOLATION : Int32 = 1008

///|
/// Message Too Big.
pub const WS_1009_MESSAGE_TOO_BIG : Int32 = 1009

///|
/// Mandatory Extension: the client required an extension the server did not negotiate.
pub const WS_1010_MANDATORY_EXT : Int32 = 1010

///|
/// Internal Error: the server hit an unexpected condition.
pub const WS_1011_INTERNAL_ERROR : Int32 = 1011

///|
/// Service Restart.
pub const WS_1012_SERVICE_RESTART : Int32 = 1012

///|
/// Try Again Later: overloaded; come back.
pub const WS_1013_TRY_AGAIN_LATER : Int32 = 1013

///|
/// Bad Gateway: the gateway got an invalid response upstream.
pub const WS_1014_BAD_GATEWAY : Int32 = 1014

///|
/// TLS Handshake: reported locally when the handshake failed.
pub const WS_1015_TLS_HANDSHAKE : Int32 = 1015
