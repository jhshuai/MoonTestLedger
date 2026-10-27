///|
priv struct DeliveryFile {
  name : String
  data : Bytes
}

///|
fn delivery_v1_files(
  evidence : @ledger.Evidence,
) -> (Array[DeliveryFile], String) raise @ledger.InputError {
  let snapshot = evidence.snapshot()
  let files : Array[DeliveryFile] = [
    { name: "evidence.json", data: @utf8.encode(evidence.encode() + "\n"), },
    {
      name: "summary.json",
      data: @utf8.encode(
        @ledger.encode_summary(
          evidence.summary(),
          deny_recovered=evidence.deny_recovered(),
        ) +
        "\n",
      ),
    },
    {
      name: "integrity.json",
      data: @utf8.encode(evidence.integrity().encode() + "\n"),
    },
    {
      name: "report.html",
      data: @utf8.encode(@ledger.render_evidence(evidence)),
    },
    { name: "evidence.zip", data: evidence.zip_pack(), },
  ]
  let receipt = Json::object({
    "schema": Json::number(1),
    "kind": Json::string("moontestledger/ci-delivery"),
    "profile": Json::string("mtl-ci-delivery-v1"),
    "run_id": Json::string(snapshot.plan.run_id),
    "revision": Json::string(snapshot.plan.revision),
    "exit_code": Json::number(evidence.exit_code().to_double()),
    "complete": Json::boolean(evidence.summary().complete),
    "files": Json::array(
      [
        ..files.map(file => Json::string(file.name)),
        Json::string("delivery.json"),
      ],
    ),
  }).stringify(indent=2)
  files.push({ name: "delivery.json", data: @utf8.encode(receipt + "\n"), })
  (files, receipt)
}

///|
async fn ci_report(path : String, directory : String) -> Int32 {
  let evidence = @ledger.decode_evidence(
    read_text(path, @ledger.Limits::default()),
  )
  // Complete validation/rendering/serialization precede any filesystem write.
  let (files, receipt) = delivery_v1_files(evidence)
  @fs.mkdir(directory)
  let owned : Array[String] = []
  errdefer {
    for file in owned {
      @fs.remove(file) catch {
        _ => ()
      }
    }
    @fs.rmdir(directory) catch {
      _ => ()
    }
  }
  for file in files {
    let path = directory + "/" + file.name
    let handle = @fs.open(path, mode=WriteOnly, create_mode=CreateNew)
    defer handle.close()
    owned.push(path)
    handle.write(file.data)
  }
  // delivery.json is written last. Creation can succeed with gate 1 or 3.
  @stdio.stdout.write(receipt + "\n")
  evidence.exit_code()
}

///|
async fn check_delivery_file(path : String, expected : Bytes) -> Unit {
  if @fs.kind(path, follow_symlink=false) != @fs.FileKind::Regular {
    raise refusal(
      "DeliveryFileKind", path, "Delivery members must be real regular files",
    )
  }
  let file = @fs.open(path, mode=ReadOnly)
  defer file.close()
  if file.kind() != @fs.FileKind::Regular {
    raise refusal(
      "DeliveryFileKind", path, "Expected a regular delivery member",
    )
  }
  let mut offset = 0
  for ;; {
    match file.read_some(max_len=65536) {
      None => break
      Some(chunk) => {
        if chunk.length() > expected.length() - offset ||
          chunk[:] != expected[offset:offset + chunk.length()] {
          raise refusal(
            "DeliveryMismatch", path, "Member bytes differ from the canonical evidence delivery; regenerate using the supported profile",
          )
        }
        offset += chunk.length()
      }
    }
  }
  if offset != expected.length() {
    raise refusal("DeliveryMismatch", path, "Delivery member is truncated")
  }
}

///|
async fn verify_delivery(directory : String) -> Int32 {
  if @fs.kind(directory, follow_symlink=false) != @fs.FileKind::Directory {
    raise refusal(
      "DeliveryDirectory", directory, "Expected a real delivery directory",
    )
  }
  let allowed = Set::from_array([
    "evidence.json", "summary.json", "integrity.json", "report.html", "evidence.zip",
    "delivery.json",
  ])
  let seen : Set[String] = Set([])
  let entries = @fs.opendir(directory)
  defer entries.close()
  for ;; {
    guard entries.next() is Some(entry) else { break }
    if !allowed.contains(entry.name) || seen.contains(entry.name) {
      raise refusal(
        "DeliveryInventory",
        directory + "/" + entry.name,
        "Delivery has an undeclared or duplicate member",
      )
    }
    seen.add(entry.name)
  }
  if seen.length() != allowed.length() {
    raise refusal(
      "DeliveryInventory", directory, "Delivery requires all six members including its completion receipt",
    )
  }
  // Select a known representation before interpreting its evidence. This read
  // only dispatches; the complete v1 receipt is still compared byte-for-byte,
  // so duplicate/unknown fields cannot become accepted data.
  let receipt_path = directory + "/delivery.json"
  if @fs.kind(receipt_path, follow_symlink=false) != @fs.FileKind::Regular {
    raise refusal(
      "DeliveryFileKind", receipt_path, "Receipt must be a real regular file",
    )
  }
  let receipt_source = read_text(receipt_path, @ledger.Limits::default())
  let receipt_json = @json.parse(receipt_source) catch {
    _ =>
      raise refusal(
        "DeliveryReceipt", receipt_path, "Expected a valid delivery receipt; preserve the original files for diagnosis",
      )
  }
  guard receipt_json
    is {
      "schema": Number(1, ..),
      "kind": String("moontestledger/ci-delivery"),
      "profile": String(profile),
      ..
    } else {
    raise refusal(
      "DeliveryReceipt", receipt_path, "Expected schema-1 CI delivery receipt with a named profile",
    )
  }
  if profile != "mtl-ci-delivery-v1" {
    raise refusal(
      "DeliveryProfileUnsupported",
      receipt_path,
      "Unsupported delivery profile '" +
      profile +
      "'; preserve all original members and use a compatible verifier. This does not establish corruption.",
    )
  }
  let archive_path = directory + "/evidence.json"
  if @fs.kind(archive_path, follow_symlink=false) != @fs.FileKind::Regular {
    raise refusal(
      "DeliveryFileKind", archive_path, "Evidence member must be a real regular file",
    )
  }
  let evidence = @ledger.decode_evidence(
    read_text(archive_path, @ledger.Limits::default()),
  )
  let (files, receipt) = delivery_v1_files(evidence)
  for file in files {
    check_delivery_file(directory + "/" + file.name, file.data)
  }
  @stdio.stdout.write(receipt + "\n")
  evidence.exit_code()
}
