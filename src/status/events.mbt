// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The event side of a `text/event-stream`: each `send` is one frame, written as its own chunk.
pub struct Events {
  priv writer : Writer
  priv space : Bool
}

///|
/// Send `event` as one frame. A client dispatches it when it reads the frame's blank line, so
/// it goes out on its own rather than waiting for the next.
pub async fn Events::send(self : Events, event : @sse.Event) -> Unit {
  self.writer.write(@utf8.encode(event.encode(space=self.space)[:]))
}

///|
/// Send a comment line, which a client ignores and an idle proxy takes as traffic.
pub async fn Events::ping(self : Events, comment~ : String = "") -> Unit {
  self.writer.write_text(": \{comment}\n\n")
}

///|
/// A `text/event-stream` response (← sse-starlette's `EventSourceResponse`). `body` sends
/// frames for as long as it likes; the app cancels it when the client goes.
///
/// Framing an event is `moonhttp/sse`'s job. What belongs here is the response around the
/// frames, and the three headers that stop an intermediary buffering or closing the stream.
/// One named in `headers` too replaces ours rather than joining it, because a response carrying
/// two `content-type` headers is not a response with a choice in it. `wins=Base` keeps ours,
/// and `clash` can abort or take a callback instead — worth setting when overriding
/// `content-type`, which stops the stream being a stream.
pub fn sse(
  body : async (Events) -> Unit,
  status~ : Int32 = 200,
  headers~ : Array[(String, String)] = [],
  space~ : Bool = true,
  wins~ : @jwt.Wins = Extra,
  clash~ : @jwt.OnClash[Array[(String, String)]] = Ignore,
) -> Stream {
  let base : Array[(String, String)] = [
    ("content-type", "\{@sse.media_type}; charset=utf-8"),
    ("cache-control", "no-cache"),
    ("connection", "keep-alive"),
  ]
  let merged = base.copy()
  let mut clashed = false
  for header in headers {
    let name = header.0.to_lower()
    match merged.search_by(seen => seen.0.to_lower() == name) {
      None => merged.push(header)
      Some(at) => {
        clashed = true
        if wins is Extra {
          merged[at] = header
        }
      }
    }
  }
  let hs = if clashed {
    match clash {
      Ignore => merged
      Panic => abort("sse: `headers` names a header the stream already sets")
      Handle(decide) => decide(base, merged)
    }
  } else {
    merged
  }
  Stream::new(status~, headers=hs, writer => body({ writer, space, }))
}

///|
pub using @sse {type Event}
