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
///
/// The three headers a stream needs are set here. One named in `headers` too
/// replaces ours rather than joining it, because a response carrying two
/// `content-type` headers is not a response with a choice in it. `wins=Base`
/// keeps ours, and `clash` can abort or take a callback instead — worth setting
/// when overriding `content-type`, which stops the stream being a stream.
pub fn sse_response(
  events : Array[@sse.Event],
  status? : Int = 200,
  headers? : Array[(String, String)] = [],
  space? : Bool = true,
  wins? : @jwt.Wins = Extra,
  clash? : @jwt.OnClash[Array[(String, String)]] = Ignore,
) -> @moonasgi.StreamingResponse {
  let chunks : Array[Bytes] = events.map(event => {
    @utf8.encode(event.encode(space~)[:])
  })
  let base : Array[(String, String)] = [
    ("content-type", "\{@sse.media_type}; charset=utf-8"),
    ("cache-control", "no-cache"),
    ("connection", "keep-alive"),
  ]
  let merged : Array[(String, String)] = []
  for header in base {
    merged.push(header)
  }
  let mut clashed = false
  for header in headers {
    let name = header.0.to_lower()
    let mut at = -1
    for i, seen in merged {
      if seen.0.to_lower() == name {
        at = i
        break
      }
    }
    if at < 0 {
      merged.push(header)
    } else {
      // A response with two `content-type` headers is not a response with a
      // choice in it; one of them has to go.
      clashed = true
      if wins is Extra {
        merged[at] = header
      }
    }
  }
  let hs = if clashed {
    match clash {
      Ignore => merged
      Panic =>
        abort("sse_response: `headers` names a header the stream already sets")
      Handle(decide) => decide(base, merged)
    }
  } else {
    merged
  }
  @moonasgi.StreamingResponse::new(status~, headers=hs, chunks~)
}

///|
pub using @sse {type Event}
