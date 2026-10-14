///|
fn refusal(
  code : String,
  path : String,
  message : String,
) -> @ledger.InputError {
  @ledger.InputError::Invalid({
    code,
    report_id: "",
    path,
    message,
    line: 0,
    column: 0,
  })
}

///|
// A byte cap is checked during reading, rather than relying only on a size
// snapshot. UTF-8 decoding is strict; malformed bytes never become replacements.
async fn read_text(path : String, limits : @ledger.Limits) -> String {
  try {
    let file = @fs.open(path, mode=ReadOnly)
    defer file.close()
    if file.kind() != @fs.FileKind::Regular {
      raise refusal("FileKind", path, "Expected a regular UTF-8 file")
    }
    let maximum = limits.max_source_units * 4
    let buffer = @buffer.Buffer()
    for ;; {
      match file.read_some(max_len=65536) {
        None => break
        Some(chunk) => {
          if chunk.length() > maximum - buffer.length() {
            raise refusal(
              "FileLimit", path, "UTF-8 file exceeds the bounded byte budget",
            )
          }
          buffer.write_bytes(chunk)
        }
      }
    }
    @utf8.decode(buffer.to_bytes()) catch {
      _ =>
        raise refusal(
          "InvalidUtf8", path, "File contains malformed UTF-8; encode the producer report as UTF-8",
        )
    }
  } catch {
    @ledger.InputError::Invalid(diagnostic) =>
      raise @ledger.InputError::Invalid(diagnostic)
    error =>
      raise refusal(
        "FileRead",
        path,
        "Cannot read input file: " + error.to_string(),
      )
  }
}

///|
// Both slash conventions are accepted for bundle entries. Fully qualified
// paths pass through; relative paths resolve from the bundle's directory.
fn report_path(bundle_path : String, entry : String) -> String {
  if entry.has_prefix("/") ||
    entry.has_prefix("\\") ||
    (
      entry.length() >= 3 &&
      entry[1] == 58 &&
      (entry[2] == 47 || entry[2] == 92)
    ) {
    return entry
  }
  let mut end = 0
  for i in 0..<bundle_path.length() {
    if bundle_path[i] == 47 || bundle_path[i] == 92 {
      end = i + 1
    }
  }
  let prefix = bundle_path[:end].to_owned()
  // Forward slashes work with the native Windows and moonrun file APIs too.
  prefix + entry.replace(old="\\", new="/")
}
