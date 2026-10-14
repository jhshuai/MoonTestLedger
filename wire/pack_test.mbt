///|
fn pack_error(source : String) -> String {
  try {
    ignore(@wire.decode_pack_index(source))
    "accepted"
  } catch {
    @ledger.InputError::Invalid(d) => d.code
  }
}

///|
fn restore_error(
  index : @wire.PackIndex,
  files : Array[@wire.PackFile],
  limits~ : @ledger.Limits = @ledger.Limits::default(),
) -> String {
  try {
    ignore(index.restore(files[:], limits~))
    "accepted"
  } catch {
    @ledger.InputError::Invalid(d) => d.code
  }
}

///|
test "file pack round trips full source projections inventory recovery policy and incomplete gates" {
  for missing in [false, true] {
    for deny in [false, true] {
      let evidence = @wire.decode_evidence(
        @wire.encode_evidence(archive_ledger(missing~), deny_recovered=deny),
      )
      let text = evidence.encode()
      let (index, files) = evidence.detach()
      let encoded = index.encode()
      let decoded = @wire.decode_pack_index(encoded)
      assert_eq(decoded.encode(), encoded)
      let restored = decoded.restore(files[:])
      assert_eq(restored.encode(), text)
      assert_eq(restored.summary(), evidence.summary())
      assert_eq(restored.exit_code(), evidence.exit_code())
      assert_eq(restored.source("first"), evidence.source("first"))
      assert_eq(evidence.encode(), text)
      let copy = index.filenames()
      copy.clear()
      assert_eq(index.encode(), encoded)
      let (again, members) = restored.detach()
      assert_eq(again.encode(), encoded)
      assert_eq(members, files)
      files.clear()
      assert_eq(index.encode(), encoded)
    }
  }
}

///|
test "file pack is deterministic under member ordering and deduplicates identical sources across reports" {
  let evidence = initial_evidence(two_groups=true)
  let (index, files) = evidence.detach()
  assert_eq(files.length(), 1)
  assert_eq(index.filenames(), files.map(file => file.name))
  let restored = @wire.decode_pack_index(index.encode()).restore(files[:])
  assert_eq(restored.encode(), evidence.encode())
  assert_eq(restored.snapshot().documents.length(), 2)
  let (two, members) = @wire.decode_evidence(
    @wire.encode_evidence(archive_ledger()),
  ).detach()
  assert_eq(
    two.restore([members[1], members[0]][:]).encode(),
    two.restore(members[:]).encode(),
  )
}

///|
test "file pack refuses missing duplicate undeclared corrupt and wrong length members without mutation then recovers" {
  let evidence = @wire.decode_evidence(@wire.encode_evidence(archive_ledger()))
  let (index, files) = evidence.detach()
  let before = index.encode()
  assert_eq(restore_error(index, []), "MissingPackFile")
  assert_eq(restore_error(index, [files[0], files[0]]), "DuplicatePackFile")
  assert_eq(
    restore_error(index, [{ ..files[0], name: "../secret.xml", }]),
    "UnexpectedPackFile",
  )
  assert_eq(
    restore_error(index, [{ ..files[0], xml: files[0].xml + "\n", }, files[1]]),
    "IntegrityMismatch",
  )
  let fields = integrity_fields(before)
  guard fields["integrity"] is Object(manifest) else {
    fail("Expected integrity")
  }
  guard manifest["documents"] is Array(docs) else { fail("Expected receipts") }
  guard docs[0] is Object(receipt) else { fail("Expected receipt") }
  receipt["utf8_bytes"] = Json::number(1)
  let changed = @wire.decode_pack_index(Json::object(fields).stringify())
  assert_eq(restore_error(changed, files), "IntegrityMismatch")
  assert_eq(index.encode(), before)
  assert_eq(index.restore(files[:]).encode(), evidence.encode())
}

///|
test "file pack serialization honors lowered expected-case budgets for collected archives" {
  let evidence = initial_evidence(two_groups=true)
  let (index, _) = evidence.detach()
  let error = try {
    ignore(index.encode(limits={ ..@ledger.Limits::default(), max_cases: 7, }))
    "accepted"
  } catch {
    @ledger.InputError::Invalid(d) => d.code
  }
  assert_eq(error, "CaseLimit")
  assert_eq(@wire.decode_pack_index(index.encode()).encode(), index.encode())
}

///|
test "file pack validates full inventory correspondence and strict nested formats before member access" {
  let (index, _) = @wire.decode_evidence(
    @wire.encode_evidence(archive_ledger()),
  ).detach()
  let text = index.encode()
  for
    (old, new, code) in [
      ("moontestledger/file-pack", "other", "PackKind"),
      ("\"schema\": 1", "\"schema\": 2", "UnsupportedSchema"),
      ("\"schema\": 1", "\"schema\": 1, \"schema\": 1", "DuplicateJsonKey"),
      ("\"schema\": 1", "\"schema\": 1, \"paths\": []", "UnknownField"),
      ("mtl-evidence-v1", "future", "IntegrityFormat"),
      (
        "\"utf8_bytes\":", "\"utf8_bytes\": 1.0000000000000001, \"extra\":", "ExpectedInteger",
      ),
    ] {
    assert_eq(pack_error(text.replace(old~, new~)), code)
  }
  for operation in 0..<5 {
    let fields = integrity_fields(text)
    guard fields["integrity"] is Object(manifest) else {
      fail("Expected integrity")
    }
    guard manifest["documents"] is Array(docs) else {
      fail("Expected receipts")
    }
    guard docs[0] is Object(receipt) else { fail("Expected receipt") }
    let code = match operation {
      0 => {
        ignore(docs.pop())
        "PackInventory"
      }
      1 => {
        receipt["id"] = Json::string("unknown")
        "UnexpectedReport"
      }
      2 => {
        receipt["shard"] = Json::string("wrong")
        "BindingMismatch"
      }
      3 => {
        manifest["plan_sha256"] = Json::string("0".repeat(64))
        "IntegrityMismatch"
      }
      _ => {
        manifest["missing_reports"] = Json::array([Json::string("unknown")])
        "UnexpectedReport"
      }
    }
    assert_eq(pack_error(Json::object(fields).stringify()), code)
  }
  assert_eq(pack_error(text), "accepted")
}

///|
test "file pack keeps accepted empty and partial reports distinct from missing expected reports" {
  let plan = @ledger.RunPlan::new("r", "v", [
    { id: "empty", environment: "linux", shard: "zero", attempt: 1, cases: [], },
    {
      id: "missing-case",
      environment: "linux",
      shard: "one",
      attempt: 1,
      cases: [{ classname: "C", name: "a", }],
    },
    {
      id: "absent",
      environment: "win",
      shard: "one",
      attempt: 1,
      cases: [{ classname: "C", name: "a", }],
    },
  ])
  let ledger = @ledger.Ledger::new(plan)
  for report in plan.reports {
    if report.id != "absent" {
      ledger.ingest({
        binding: {
          id: report.id,
          run_id: "r",
          revision: "v",
          environment: report.environment,
          shard: report.shard,
          attempt: 1,
        },
        report: @junit.parse("<testsuite/>"),
      })
    }
  }
  let evidence = @wire.decode_evidence(@wire.encode_evidence(ledger))
  let (index, files) = evidence.detach()
  assert_eq(files.length(), 1)
  let restored = index.restore(files[:])
  assert_eq(restored.exit_code(), 3)
  assert_eq(restored.summary(), evidence.summary())
  assert_eq(restored.summary().missing_reports, ["absent"])
}

///|
test "file pack enforces inclusive JSON member and expanded replay budgets" {
  let evidence = initial_evidence(two_groups=true)
  let (index, files) = evidence.detach()
  let text = index.encode()
  let limits = { ..@ledger.Limits::default(), max_source_units: text.length(), }
  assert_eq(index.encode(limits~), text)
  let code = try {
    ignore(
      index.encode(limits={ ..limits, max_source_units: text.length() - 1, }),
    )
    "accepted"
  } catch {
    @ledger.InputError::Invalid(d) => d.code
  }
  assert_eq(code, "SourceLimit")
  let units = files[0].xml.length() * 2
  assert_eq(
    index
    .restore(files[:], limits={
      ..@ledger.Limits::default(),
      max_total_source_units: units,
    })
    .encode(),
    evidence.encode(),
  )
  assert_eq(
    restore_error(index, files, limits={
      ..@ledger.Limits::default(),
      max_total_source_units: units - 1,
    }),
    "SourceLimit",
  )
  assert_eq(
    restore_error(index, files, limits={
      ..@ledger.Limits::default(),
      max_reports: 1,
    }),
    "ReportLimit",
  )
  assert_eq(index.restore(files[:]).encode(), evidence.encode())
}
