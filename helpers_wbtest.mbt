// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A request with a body and a content type, for the extractors that read one.
fn mkreq_ct(
  verb : String,
  content_type : String,
  body : Bytes,
) -> @moonasgi.Request {
  {
    http_method: verb,
    path: "/",
    query_string: b"",
    headers: [("content-type", content_type)],
    body,
  }
}

///|
/// Split a string on one character. Used to take a token apart in the tests
/// that tamper with one.
fn split_char(s : String, delim : Char) -> Array[String] {
  let out : Array[String] = []
  let piece = StringBuilder()
  for i in 0..<s.length() {
    if s.at(i).to_int() == delim.to_int() {
      out.push(piece.to_string())
      piece.reset()
    } else {
      piece.write_view(s[i:i + 1])
    }
  }
  out.push(piece.to_string())
  out
}

///|
/// One header out of a list, by lowercased name.
fn header_of(headers : Array[(String, String)], name : String) -> String? {
  for pair in headers {
    if pair.0.to_lower() == name {
      return Some(pair.1)
    }
  }
  None
}
