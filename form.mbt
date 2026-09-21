// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The posted form — FastAPI's `Form(...)` and `File(...)` parameters.
///
/// Reading the body is `moonhttp/mime`'s job; what belongs here is knowing that
/// a request has a `Content-Type` and handing it over. `None` means the form
/// broke its bounds and was refused whole: a handler given the first thousand
/// parts of a larger form would be answering a request nobody sent. An empty
/// form is the other answer, and means the request carried none.
pub fn Context::form(
  self : Context,
  limits? : @mime.Limits = @mime.limits,
) -> @mime.Form? {
  Some(
    @mime.parse(
      self.request.body[:],
      self.request.header("content-type").unwrap_or("")[:],
      limits~,
    ),
  ) catch {
    _ => None
  }
}

///|
pub using @mime {type Form, type Upload, type Limits}
