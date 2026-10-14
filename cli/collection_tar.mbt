///|
async fn collect_tar(spec_path : String, path : String) -> Int32 {
  let limits = @ledger.Limits::default()
  let spec = @ledger.decode_collection(read_text(spec_path, limits), limits~)
  let evidence = spec.collect_tar(read_carrier(path), limits~)
  @stdio.stdout.write(evidence.encode(limits~) + "\n")
  0
}
