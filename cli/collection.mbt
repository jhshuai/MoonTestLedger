///|
// Enumerate bounded directory entries rather than converting every I/O error
// into "missing". This also detects broken symlinks without following them.
async fn collection_directory(
  path : String,
  cache : Map[String, Map[String, String]],
  visits : Ref[Int32],
  limits : @ledger.Limits,
) -> Map[String, String] {
  if cache.get(path) is Some(names) {
    return names
  }
  let directory = @fs.opendir(path)
  defer directory.close()
  let names : Map[String, String] = Map([])
  for ;; {
    guard directory.next(include_hidden=true) is Some(entry) else { break }
    visits.val += 1
    if visits.val > limits.max_events {
      raise refusal(
        "CollectionEntryLimit", path, "Directory entry visits exceed max_events",
      )
    }
    let folded = entry.name.to_lower()
    names[folded] = if names.contains(folded) { "" } else { entry.name }
  }
  cache[path] = names
  names
}

///|
// Paths are already structurally validated by the opaque portable spec.
// Each existing component is checked without following symlinks. A genuinely
// absent component yields None; access and read errors remain hard errors.
async fn collection_source(
  root : String,
  relative : String,
  cache : Map[String, Map[String, String]],
  visits : Ref[Int32],
  limits : @ledger.Limits,
) -> String? {
  let parts = relative.split("/").map(part => part.to_owned()).collect()
  let mut current = root
  for i, part in parts {
    let names = collection_directory(current, cache, visits, limits)
    match names.get(part.to_lower()) {
      None => return None
      Some(actual) if actual != part =>
        raise refusal(
          "CollectionPathCase",
          current + "/" + part,
          "Declared component has different casing or collides with another filesystem entry",
        )
      _ => ()
    }
    current += "/" + part
    let kind = @fs.kind(current, follow_symlink=false)
    let expected = if i == parts.length() - 1 {
      @fs.FileKind::Regular
    } else {
      @fs.FileKind::Directory
    }
    if kind != expected {
      raise refusal(
        "CollectionFileKind", current, "Declared paths must use real directories and regular XML files; symlinks and special files are unsupported",
      )
    }
  }
  Some(read_text(current, limits))
}

///|
async fn collect(spec_path : String, root : String) -> Int32 {
  let limits = @ledger.Limits::default()
  let spec = @ledger.decode_collection(read_text(spec_path, limits), limits~)
  if @fs.kind(root, follow_symlink=false) != @fs.FileKind::Directory {
    raise refusal(
      "CollectionDirectory", root, "Expected a real artifact root directory",
    )
  }
  let cache : Map[String, Map[String, String]] = Map([])
  let visits : Ref[Int32] = Ref(0)
  let inputs : Array[@ledger.CollectedXml] = []
  let mut units = 0L
  for file in spec.files() {
    if collection_source(root, file.path, cache, visits, limits) is Some(xml) {
      units += xml.length().to_int64()
      if units > limits.max_total_source_units.to_int64() {
        raise refusal(
          "SourceLimit",
          file.path,
          "Combined collected XML exceeds the total source budget",
        )
      }
      inputs.push({ id: file.id, xml, })
    }
  }
  let evidence = spec.collect(inputs[:], limits~)
  @stdio.stdout.write(evidence.encode(limits~) + "\n")
  0
}
