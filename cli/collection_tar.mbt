///|
async fn collect_tar(
  spec_path : String,
  path : String,
  output~ : String? = None,
) -> Int32 {
  let limits = @ledger.Limits::default()
  let spec = @ledger.decode_collection(read_text(spec_path, limits), limits~)
  let evidence = spec.collect_tar(read_carrier(path), limits~)
  emit_evidence(evidence.encode(limits~), output)
  0
}
