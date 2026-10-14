///|
/// Collect regular-file POSIX USTAR against the full declared path inventory.
/// Missing paths retain incompleteness; unknown paths/extensions are refused.
pub fn CollectionSpec::collect_tar(
  self : CollectionSpec,
  data : Bytes,
  limits~ : @ledger.Limits = @ledger.Limits::default(),
  max_bytes~ : Int32 = 16777216,
) -> Evidence raise @ledger.InputError {
  ignore(self.encode(limits~))
  let entries = tar_entries(data, limits, max_bytes)
  let declared = collection_carrier_names(
    self,
    entries.map(entry => entry.name),
    limits,
  )
  let inputs = entries.map(entry => {
    id: declared[entry.name],
    xml: carrier_text(entry),
  })
  self.collect(inputs[:], limits~)
}
