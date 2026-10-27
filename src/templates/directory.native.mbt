///|
/// Every file under `path`, read as text and keyed by its path below it with
/// `/` between the parts — the names a template loads others by. Read once, so a
/// loader over the result answers without touching the disk:
///
/// ```moonbit nocheck
/// let files = @templates.load_directory("templates")
///
/// let env = @moonpug.Env::new(load=name => files.get(name))
/// ```
pub async fn load_directory(path : String) -> Map[String, String] {
  let root = path.trim_end(chars="/\\").to_owned()
  let out : Map[String, String] = Map([])
  @fs.walk(root, async fn(dir, names) {
    for name in names {
      let full = dir + "/" + name
      guard @fs.kind(full) is Regular else { continue }
      let rel = full.view(start_offset=root.length() + 1).to_owned()
      out[rel.replace_all(old="\\", new="/")] = @utf8.decode_lossy(
        @fs.read_file(full).binary()[:],
      )
    }
  })
  out
}
