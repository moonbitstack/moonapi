// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A response whose body is written while it is sent (← Starlette's `StreamingResponse`): the
/// head goes out first, then whatever `body` writes, a chunk per write. The app runs `body`
/// beside a watch on the connection and cancels it when the client goes, so an endless stream
/// ends with its reader.
///
/// `early_hints` go out as `103` responses before the head (RFC 8297). `trailers` announces
/// trailing fields, which `body` sets with [`Writer::trailer`] and the app sends after the last
/// chunk.
pub(all) struct Stream {
  status : Int32
  headers : Array[(String, String)]
  body : async (Writer) -> Unit
  early_hints : Array[Array[String]]
  trailers : Bool
}

///|
pub fn Stream::new(
  body : async (Writer) -> Unit,
  status~ : Int32 = 200,
  headers~ : Array[(String, String)] = [],
  early_hints~ : Array[Array[String]] = [],
  trailers~ : Bool = false,
) -> Stream {
  { status, headers, body, early_hints, trailers, }
}

///|
/// Where a stream's body goes. The app makes one per response; a test or another driver makes
/// one over its own sink.
pub struct Writer {
  priv sink : async (Bytes) -> Unit
  priv fields : Array[(String, String)]
}

///|
pub fn Writer::new(sink : async (Bytes) -> Unit) -> Writer {
  { sink, fields: [], }
}

///|
/// Send `chunk` as one piece of the body. An empty chunk is not sent: it would say nothing.
pub async fn Writer::write(self : Writer, chunk : Bytes) -> Unit {
  if chunk.length() > 0 {
    (self.sink)(chunk)
  }
}

///|
/// Send `text` as UTF-8.
pub async fn Writer::write_text(self : Writer, text : String) -> Unit {
  self.write(@utf8.encode(text))
}

///|
/// Add a trailing field, sent after the body when the stream announced `trailers`.
pub fn Writer::trailer(self : Writer, name : String, value : String) -> Unit {
  self.fields.push((name, value))
}

///|
/// The trailing fields set so far.
pub fn Writer::trailers(self : Writer) -> Array[(String, String)] {
  self.fields
}
