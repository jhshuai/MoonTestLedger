///|
// No user-authored member paths: the portable index derives flat digest names.
// Verify directory entries and reject symlinks/special files before reading.
async fn load_pack(directory : String) -> @ledger.Evidence {
  if @fs.kind(directory, follow_symlink=false) != @fs.FileKind::Directory {
    raise refusal(
      "PackDirectory", directory, "Expected a real directory, not a symlink",
    )
  }
  let index_path = directory + "/index.json"
  if @fs.kind(index_path, follow_symlink=false) != @fs.FileKind::Regular {
    raise refusal(
      "PackFileKind", index_path, "Index must be a regular file, not a symlink",
    )
  }
  let limits = @ledger.Limits::default()
  let index = @ledger.decode_pack_index(read_text(index_path, limits), limits~)
  let allowed = Set::from_array(index.filenames())
  allowed.add("index.json")
  let entries = @fs.opendir(directory)
  defer entries.close()
  let seen : Set[String] = Set([])
  for ;; {
    guard entries.next(include_hidden=true) is Some(entry) else { break }
    if !allowed.contains(entry.name) {
      raise refusal(
        "UnexpectedPackFile",
        directory + "/" + entry.name,
        "Pack directory contains an undeclared member",
      )
    }
    seen.add(entry.name)
  }
  let files : Array[@ledger.PackFile] = []
  let mut total_units = 0L
  for name in index.filenames() {
    let path = directory + "/" + name
    if !seen.contains(name) {
      raise refusal("MissingPackFile", path, "Declared XML member is missing")
    }
    if @fs.kind(path, follow_symlink=false) != @fs.FileKind::Regular {
      raise refusal(
        "PackFileKind", path, "XML member must be a regular file, not a symlink",
      )
    }
    let xml = read_text(path, limits)
    total_units += xml.length().to_int64()
    if total_units > limits.max_total_source_units.to_int64() {
      raise refusal(
        "SourceLimit", path, "Combined XML member source budget exceeded",
      )
    }
    files.push({ name, xml, })
  }
  index.restore(files[:], limits~)
}

///|
async fn write_owned(
  path : String,
  content : String,
  owned : Array[String],
) -> Unit {
  let file = @fs.open(path, mode=WriteOnly, create_mode=CreateNew)
  defer file.close()
  owned.push(path)
  file.write(content)
}

///|
// All validation precedes file creation. Only a new directory is accepted;
// index.json is published last. Cleanup targets only our declared paths.
async fn detach(path : String, directory : String) -> Int32 {
  let limits = @ledger.Limits::default()
  let evidence = @ledger.decode_evidence(read_text(path, limits), limits~)
  let (index, files) = evidence.detach(limits~)
  let encoded = index.encode(limits~)
  @fs.mkdir(directory)
  let created : Array[String] = []
  errdefer {
    for output in created {
      @fs.remove(output) catch {
        _ => ()
      }
    }
    @fs.rmdir(directory) catch {
      _ => ()
    }
  }
  for file in files {
    let output = directory + "/" + file.name
    write_owned(output, file.xml, created)
  }
  let output = directory + "/index.json"
  write_owned(output, encoded, created)
  @stdio.stdout.write(encoded + "\n")
  0
}

///|
async fn restore_pack(directory : String) -> Int32 {
  @stdio.stdout.write(load_pack(directory).encode() + "\n")
  0
}

///|
async fn verify_pack(directory : String) -> Int32 {
  let evidence = load_pack(directory)
  @stdio.stdout.write(
    @ledger.encode_summary(
      evidence.summary(),
      deny_recovered=evidence.deny_recovered(),
    ) +
    "\n",
  )
  evidence.exit_code()
}
