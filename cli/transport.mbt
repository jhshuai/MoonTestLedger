///|
async fn read_carrier(path : String) -> Bytes {
  let file = @fs.open(path, mode=ReadOnly)
  defer file.close()
  if file.kind() != @fs.FileKind::Regular {
    raise refusal("FileKind", path, "Expected a regular binary archive")
  }
  let buffer = @buffer.Buffer()
  for ;; {
    match file.read_some(max_len=65536) {
      None => break
      Some(chunk) => {
        if chunk.length() > 16777216 - buffer.length() {
          raise refusal("TransportLimit", path, "CLI transport limit is 16 MiB")
        }
        buffer.write_bytes(chunk)
      }
    }
  }
  buffer.to_bytes()
}

///|
async fn write_carrier(path : String, bytes : Bytes) -> Unit {
  let file = @fs.open(path, mode=WriteOnly, create_mode=CreateNew)
  defer file.close()
  errdefer (@fs.remove(path) catch { _ => () })
  file.write(bytes)
}

///|
async fn zip_pack(path : String, destination : String) -> Int32 {
  let evidence = @ledger.decode_evidence(
    read_text(path, @ledger.Limits::default()),
  )
  let bytes = evidence.zip_pack()
  write_carrier(destination, bytes)
  @stdio.stdout.write(evidence.integrity().encode() + "\n")
  0
}

///|
async fn restore_zip(path : String, gate : Bool) -> Int32 {
  let evidence = @ledger.decode_zip_pack(read_carrier(path))
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
