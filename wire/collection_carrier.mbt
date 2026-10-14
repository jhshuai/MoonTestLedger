///|
// Archive collection has an explicit closed input set, unlike directory
// collection's selected-path traversal. Nothing unlisted is silently ignored.
fn collection_carrier_names(
  spec : CollectionSpec,
  names : Array[String],
  limits : @ledger.Limits,
) -> Map[String, String] raise @ledger.InputError {
  ignore(spec.encode(limits~))
  let declared : Map[String, String] = Map([])
  for file in spec.files {
    declared[file.path] = file.id
  }
  let seen : Set[String] = Set([])
  for name in names {
    if !declared.contains(name) {
      raise bad(
        "UnexpectedArtifact", name, "Archive member is not an exact declared path; provide an archive containing only declared XML files",
      )
    }
    if seen.contains(name) {
      raise bad(
        "DuplicateArtifact", name, "Duplicate archive member is ambiguous",
      )
    }
    seen.add(name)
  }
  declared
}

///|
/// Collect a bounded classic ZIP against the full expected inventory.
/// Missing declared members remain incomplete; unlisted members are refused.
/// Paths never create report/run identities; all bindings come from the spec.
pub fn CollectionSpec::collect_zip(
  self : CollectionSpec,
  data : Bytes,
  limits~ : @ledger.Limits = @ledger.Limits::default(),
  max_bytes~ : Int32 = 16777216,
) -> Evidence raise @ledger.InputError {
  ignore(self.encode(limits~))
  let entries = zip_entries(data, limits, max_bytes)
  let declared = collection_carrier_names(
    self,
    entries.map(entry => entry.name),
    limits,
  )
  let inputs = entries.map(entry => {
    id: declared[entry.name],
    xml: carrier_text(zip_expand(data, entry)),
  })
  self.collect(inputs[:], limits~)
}
