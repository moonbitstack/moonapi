///|
/// One file a source holds: its bytes and, when the source knows it, when it
/// last changed.
pub(all) struct Asset {
  content : Bytes
  modified : @moondate.Moment?
} derive(Eq)

///|
pub extend Asset with Eq::{equal, not_equal}

///|
/// Where the served files come from. `path` is relative, its parts joined by
/// `/`, and already checked: no empty part, no `.` or `..`, no backslash, colon
/// or NUL. `None` means there is no such file.
///
/// `Memory` serves files held in the program and `Directory` (native) serves a
/// directory; a source of your own — an archive, a bucket, a database — is one
/// more implementation.
pub(open) trait Source {
  async fn read(Self, String) -> Asset?
}

///|
/// Files held in the program, keyed by their relative path: built into the
/// binary, generated at startup, or read once from anywhere. Works on every
/// target.
pub struct Memory {
  files : Map[String, Asset]
}

///|
/// A memory source over `files`, every one dated `modified` when given.
pub fn Memory::new(
  files : Map[String, Bytes],
  modified? : @moondate.Moment,
) -> Memory {
  let out : Map[String, Asset] = Map([])
  for path, content in files {
    out[path] = { content, modified, }
  }
  { files: out, }
}

///|
pub impl Source for Memory with fn read(self, path) {
  self.files.get(path)
}

///|
pub extend Memory with Source::{read}

///|
/// Serve the files `source` holds, as an ASGI application to mount with
/// `App::mount_asgi` (← Starlette's `StaticFiles`).
///
/// A `GET` or `HEAD` for a file answers with it, weighed against the request's
/// conditional headers and `Range` (`304`, `412`, `206`, `416`), its type guessed
/// from its name and its entity-tag taken from its date and length when the
/// source knows the date. Any other method is a `405`. A path with a `..` part
/// is a `404`, never a file outside the source: clients resolve dot segments
/// before sending, so only a crafted request carries one.
///
/// With `html`, a directory answers with its `index.html`, a directory named
/// without its trailing slash is first sent to the name with one (`307`), and a
/// path with nothing behind it answers with `404.html` when there is one.
/// `ranges=false` withdraws the offer of partial content.
pub fn serve(
  source : &Source,
  html~ : Bool = false,
  ranges~ : Bool = true,
) -> @moonasgi.AsgiApp {
  (scope, _receive, send) => {
    match scope {
      Http(hs) => send_response(send, answer(source, hs, html, ranges))
      // Nothing here speaks WebSocket; declining the handshake is a 403.
      WebSocket(_) => send(WebSocketClose(code=1000, reason=""))
      Lifespan(_) => ()
    }
  }
}

///|
async fn answer(
  source : &Source,
  hs : @moonasgi.HttpScope,
  html : Bool,
  ranges : Bool,
) -> @moonasgi.Response {
  guard hs.http_method is ("GET" | "HEAD") else {
    return @moonasgi.Response::new(
      405,
      [("allow", "GET, HEAD"), ("content-type", "text/plain; charset=utf-8")],
      b"Method Not Allowed",
    )
  }
  guard relative(hs.path) is Some(rel) else { return not_found() }
  let ctx = @ctx.Context::new(
    {
      http_method: hs.http_method,
      path: hs.path,
      query_string: hs.query_string,
      headers: hs.headers,
      body: b"",
    },
    scope=hs,
  )
  if rel != "" && source.read(rel) is Some(asset) {
    return file(ctx, rel, asset, ranges)
  }
  if html {
    let index = if rel == "" { "index.html" } else { rel + "/index.html" }
    if source.read(index) is Some(asset) {
      if rel != "" && !hs.path.has_suffix("/") {
        let query = @utf8.decode_lossy(hs.query_string[:])
        let location = hs.root_path +
          hs.path +
          "/" +
          (if query.is_empty() { "" } else { "?" + query })
        return @moonasgi.Response::new(307, [("location", location)], b"")
      }
      return file(ctx, index, asset, ranges)
    }
    if source.read("404.html") is Some(page) {
      let body = if hs.http_method == "HEAD" { b"" } else { page.content }
      return @moonasgi.Response::new(
        404,
        [
          ("content-type", "text/html; charset=utf-8"),
          ("content-length", page.content.length().to_string()),
        ],
        body,
      )
    }
  }
  not_found()
}

///|
/// `path` as a source path, or `None` when a part could reach outside the
/// source or name something a file system reads specially.
fn relative(path : String) -> String? {
  let parts : Array[String] = []
  for part in path.split("/") {
    if part.is_empty() || part == "." {
      continue
    }
    if part == ".." ||
      part.contains("\\") ||
      part.contains(":") ||
      part.contains("\u{0}") {
      return None
    }
    parts.push(part.to_owned())
  }
  Some(parts.join("/"))
}

///|
fn file(
  ctx : @ctx.Context,
  path : String,
  asset : Asset,
  ranges : Bool,
) -> @moonasgi.Response {
  let length = asset.content.length().to_int64()
  match asset.modified {
    Some(modified) =>
      ctx.serve(
        asset.content,
        media_type=media_type(path),
        etag=@conditional.stamp(length~, modified~),
        modified~,
        ranges~,
      )
    None => ctx.serve(asset.content, media_type=media_type(path), ranges~)
  }
}

///|
/// The type a file's name implies, with `charset=utf-8` on text so a browser
/// does not guess one from its locale.
fn media_type(path : String) -> String {
  let kind = @moonmime.guess_type(path[:])
  if kind.has_prefix("text/") && !kind.contains("charset=") {
    kind + "; charset=utf-8"
  } else {
    kind
  }
}

///|
fn not_found() -> @moonasgi.Response {
  @moonasgi.Response::new(
    404,
    [("content-type", "text/plain; charset=utf-8")],
    b"Not Found",
  )
}

///|
async fn send_response(
  send : @moonasgi.Send,
  resp : @moonasgi.Response,
) -> Unit {
  send(
    HttpResponseStart(status=resp.status, headers=resp.headers, trailers=false),
  )
  send(HttpResponseBody(body=resp.body, more_body=false))
}
