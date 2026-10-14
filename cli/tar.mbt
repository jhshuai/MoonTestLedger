///|
async fn tar_pack(path : String, destination : String) -> Int32 {
  let evidence = @ledger.decode_evidence(
    read_text(path, @ledger.Limits::default()),
  )
  write_carrier(destination, evidence.tar_pack())
  @stdio.stdout.write(evidence.integrity().encode() + "\n")
  0
}

///|
async fn restore_tar(path : String, gate : Bool) -> Int32 {
  let evidence = @ledger.decode_tar_pack(read_carrier(path))
  @stdio.stdout.write(
    (if gate {
      @ledger.encode_summary(
        evidence.summary(),
        deny_recovered=evidence.deny_recovered(),
      )
    } else {
      evidence.encode()
    }) +
    "\n",
  )
  if gate {
    evidence.exit_code()
  } else {
    0
  }
}
