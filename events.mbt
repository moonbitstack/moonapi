// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A `text/event-stream` response, one frame to a chunk.
///
/// A chunk per frame is the whole point: a stream that arrives as one body is
/// not a stream, it is a file shaped like one. A client dispatches an event when
/// it reads that event's blank line, so the frames have to reach it separately
/// for anything to happen before the last one is written.
///
/// Framing an event is `moonhttp/sse`'s job. What belongs here is the response
/// around the frames, and the three headers that stop an intermediary buffering
/// or closing the stream.
pub fn sse_response(
  events : Array[@sse.Event],
  status? : Int = 200,
  headers? : Array[(String, String)] = [],
) -> @moonasgi.StreamingResponse {
  let chunks : Array[Bytes] = events.map(event => {
    @utf8.encode(event.encode()[:])
  })
  let hs : Array[(String, String)] = [
    ("content-type", "\{@sse.media_type}; charset=utf-8"),
    ("cache-control", "no-cache"),
    ("connection", "keep-alive"),
  ]
  for header in headers {
    hs.push(header)
  }
  @moonasgi.StreamingResponse::new(status~, headers=hs, chunks~)
}

///|
pub using @sse {type Event}
