///|
async fn collect_zip(
  spec_path : String,
  path : String,
  output~ : String? = None,
) -> Int32 {
  let limits = @ledger.Limits::default()
  let spec = @ledger.decode_collection(read_text(spec_path, limits), limits~)
  let evidence = spec.collect_zip(read_carrier(path), limits~)
  emit_evidence(evidence.encode(limits~), output)
  0
}
