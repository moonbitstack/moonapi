///|
/// A directory on disk (← Starlette's `StaticFiles(directory=…)`). Each request
/// reads the file afresh, so what is served is what is there now.
///
/// A symbolic link that resolves outside the directory is not followed unless
/// `follow_symlink` is set, so a link cannot publish the rest of the disk.
pub struct Directory {
  root : String
  follow_symlink : Bool
}

///|
pub fn Directory::new(
  root : String,
  follow_symlink~ : Bool = false,
) -> Directory {
  { root: root.trim_end(chars="/\\").to_owned(), follow_symlink, }
}

///|
pub impl Source for Directory with fn read(self, path) {
  let full = self.root + "/" + path
  let kind = @fs.kind(full) catch { _ => return None }
  guard kind is Regular else { return None }
  if !self.follow_symlink {
    let inside = try {
      let real = @fs.realpath(full)
      let base = @fs.realpath(self.root)
      real.has_prefix(base + "/") || real.has_prefix(base + "\\")
    } catch {
      _ => false
    }
    guard inside else { return None }
  }
  let content = @fs.read_file(full).binary() catch { _ => return None }
  let (seconds, _) = @fs.mtime(full) catch { _ => (0L, 0) }
  Some({
    content,
    modified: Some(@moondate.Moment::of_epoch(seconds, zone=Utc)),
  })
}

///|
pub extend Directory with Source::{read}
