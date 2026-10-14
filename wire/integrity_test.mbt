///|
fn integrity_error(
  source : String,
  limits~ : @ledger.Limits = @ledger.Limits::default(),
) -> String {
  try {
    ignore(@wire.decode_integrity(source, limits~))
    "accepted"
  } catch {
    @ledger.InputError::Invalid(d) => d.code
  }
}

///|
fn integrity_check_error(evidence : @wire.Evidence, source : String) -> String {
  try {
    evidence.check_integrity(@wire.decode_integrity(source))
    "accepted"
  } catch {
    @ledger.InputError::Invalid(d) => d.code
  }
}

///|
fn integrity_fields(source : String) -> Map[String, Json] raise {
  guard @json.parse(source) is Object(fields) else { fail("Expected object") }
  fields
}

///|
test "integrity round trips exact source full inventory policy and preserves all existing gates" {
  for deny in [false, true] {
    for missing in [false, true] {
      let evidence = @wire.decode_evidence(
        @wire.encode_evidence(archive_ledger(missing~), deny_recovered=deny),
      )
      let before = evidence.encode()
      let summary = evidence.summary()
      let manifest = evidence.integrity()
      let text = manifest.encode()
      let decoded = @wire.decode_integrity(text)
      assert_eq(decoded.encode(), text)
      evidence.check_integrity(decoded)
      assert_eq(evidence.encode(), before)
      assert_eq(evidence.summary(), summary)
      assert_eq(
        evidence.exit_code(),
        if missing {
          3
        } else if deny {
          1
        } else {
          0
        },
      )
      assert_eq(
        manifest.missing_reports(),
        if missing {
          ["retry"]
        } else {
          []
        },
      )
      let copies = decoded.documents()
      copies.clear()
      decoded.missing_reports().clear()
      assert_eq(decoded.encode(), text)
      let compact = @wire.decode_evidence(@json.parse(before).stringify())
      assert_eq(compact.integrity().encode(), text)
      let reformatted = @wire.decode_integrity(@json.parse(text).stringify())
      compact.check_integrity(reformatted)
      // Unicode receipt length counts UTF-8 bytes, rather than UTF-16 units.
      assert_true(
        manifest.documents()[0].utf8_bytes >
        evidence.source("first").unwrap().length(),
      )
    }
  }
}

///|
test "integrity detects raw XML whitespace metadata payload and policy changes then recovers" {
  let evidence = @wire.decode_evidence(@wire.encode_evidence(archive_ledger()))
  let before = evidence.encode()
  let manifest = evidence.integrity().encode()
  for
    source in [
      before.replace(old="<testsuite>", new="<testsuite> "),
      before.replace(old="retained", new="changed!"),
      before.replace(old="raw &amp;", new="new &amp;"),
      before.replace(
        old="\"deny_recovered\": false",
        new="\"deny_recovered\": true",
      ),
    ] {
    let changed = @wire.decode_evidence(source) catch {
      @ledger.InputError::Invalid(d) =>
        fail(
          "Changed archive rejected before integrity: " +
          @wire.encode_diagnostic(d),
        )
    }
    assert_eq(integrity_check_error(changed, manifest), "IntegrityMismatch")
    assert_eq(evidence.encode(), before)
  }
  let fields = integrity_fields(before)
  guard fields["plan"] is Object(plan) else { fail("Expected plan") }
  plan["revision"] = Json::string("different")
  guard fields["documents"] is Array(docs) else { fail("Expected documents") }
  for doc in docs {
    guard doc is Object(binding) else { fail("Expected binding") }
    binding["revision"] = Json::string("different")
  }
  let different_revision = @wire.decode_evidence(
    Json::object(fields).stringify(),
  )
  assert_eq(
    integrity_check_error(different_revision, manifest),
    "IntegrityMismatch",
  )
  evidence.check_integrity(@wire.decode_integrity(manifest))
  assert_eq(evidence.exit_code(), 0)
}

///|
test "integrity detects full plan changes omitted extra receipts altered bindings and stale digests" {
  let evidence = @wire.decode_evidence(@wire.encode_evidence(archive_ledger()))
  let text = evidence.integrity().encode()
  let changed_plan = evidence.snapshot().plan
  changed_plan.reports[0].cases.push({ classname: "C", name: "missing", })
  let changed_ledger = @ledger.Ledger::new(changed_plan)
  for document in evidence.snapshot().documents {
    changed_ledger.ingest(document)
  }
  let changed = @wire.decode_evidence(@wire.encode_evidence(changed_ledger))
  assert_eq(changed.exit_code(), 3)
  assert_eq(integrity_check_error(changed, text), "IntegrityMismatch")
  for operation in 0..<6 {
    let fields = integrity_fields(text)
    guard fields["documents"] is Array(docs) else { fail("Expected receipts") }
    guard docs[0] is Object(receipt) else { fail("Expected receipt") }
    match operation {
      0 => ignore(docs.pop())
      1 => receipt["shard"] = Json::string("other")
      2 => receipt["utf8_bytes"] = Json::number(1)
      3 => fields["archive_sha256"] = Json::string("0".repeat(64))
      4 => fields["plan_sha256"] = Json::string("0".repeat(64))
      _ => fields["missing_reports"] = Json::array([Json::string("extra")])
    }
    assert_eq(
      integrity_check_error(evidence, Json::object(fields).stringify()),
      "IntegrityMismatch",
    )
  }
  let partial = @wire.decode_evidence(
    @wire.encode_evidence(archive_ledger(missing=true)),
  )
  assert_eq(integrity_check_error(partial, text), "IntegrityMismatch")
  assert_eq(
    integrity_check_error(evidence, partial.integrity().encode()),
    "IntegrityMismatch",
  )
  assert_eq(evidence.integrity().encode(), text)
  let ordered = initial_evidence()
  let copy = ordered.snapshot()
  let cases = copy.plan.reports[0].cases
  let first = cases[0]
  cases[0] = cases[1]
  cases[1] = first
  let reordered = @ledger.Ledger::new(copy.plan)
  for doc in copy.documents {
    reordered.ingest(doc)
  }
  let new_evidence = @wire.decode_evidence(@wire.encode_evidence(reordered))
  assert_eq(new_evidence.summary(), ordered.summary())
  assert_eq(
    integrity_check_error(new_evidence, ordered.integrity().encode()),
    "IntegrityMismatch",
  )
}

///|
test "integrity receipts normalize order and retain accepted empty reports and missing cases" {
  let plan = @ledger.RunPlan::new("run", "rev", [
    { id: "empty", environment: "linux", shard: "zero", attempt: 1, cases: [], },
    {
      id: "partial",
      environment: "linux",
      shard: "one",
      attempt: 1,
      cases: [{ classname: "C", name: "a", }],
    },
  ])
  let ledger = @ledger.Ledger::new(plan)
  for report in plan.reports {
    ledger.ingest({
      binding: {
        id: report.id,
        run_id: "run",
        revision: "rev",
        environment: report.environment,
        shard: report.shard,
        attempt: 1,
      },
      report: @junit.parse("<testsuite/>"),
    })
  }
  let evidence = @wire.decode_evidence(@wire.encode_evidence(ledger))
  let manifest = evidence.integrity()
  assert_eq(evidence.exit_code(), 3)
  assert_eq(manifest.documents().length(), 2)
  assert_eq(manifest.missing_reports(), [])
  evidence.check_integrity(manifest)
  let fields = integrity_fields(manifest.encode())
  guard fields["documents"] is Array(docs) else { fail("Expected receipts") }
  fields["documents"] = Json::array([docs[1], docs[0]])
  assert_eq(
    @wire.decode_integrity(Json::object(fields).stringify()).encode(),
    manifest.encode(),
  )
}

///|
test "integrity rejects unknown formats fields malformed hashes types and duplicate decoded keys" {
  let text = @wire.decode_evidence(@wire.encode_evidence(archive_ledger()))
    .integrity()
    .encode()
  for
    (old, replacement, code) in [
      ("\"schema\": 1", "\"schema\": 2", "UnsupportedSchema"),
      (
        "\"schema\": 1", "\"schema\": 1, \"sch\\u0065ma\": 1", "DuplicateJsonKey",
      ),
      ("\"sha256\"", "\"sha512\"", "IntegrityFormat"),
      ("mtl-evidence-v1", "mtl-evidence-v2", "IntegrityFormat"),
      ("moontestledger/integrity", "other", "IntegrityFormat"),
      (
        "\"deny_recovered\": false", "\"deny_recovered\": false, \"future\": 1",
        "UnknownField",
      ),
      ("\"deny_recovered\": false", "\"deny_recovered\": 0", "ExpectedBoolean"),
      ("\"run_id\": \"run\"", "\"run_id\": \"\"", "InvalidText"),
      (
        "\"environment\": \"linux\"", "\"environment\": \"linux\", \"future\": true",
        "UnknownField",
      ),
    ] {
    assert_eq(integrity_error(text.replace(old~, new=replacement)), code)
  }
  for invalid in ["", "0".repeat(63), "A".repeat(64), "g".repeat(64)] {
    let fields = integrity_fields(text)
    fields["plan_sha256"] = Json::string(invalid)
    assert_eq(
      integrity_error(Json::object(fields).stringify()),
      "InvalidDigest",
    )
  }
  let fields = integrity_fields(text)
  guard fields["documents"] is Array(docs) else { fail("Expected receipts") }
  docs.push(docs[0])
  assert_eq(
    integrity_error(Json::object(fields).stringify()),
    "DuplicateReport",
  )
  docs.pop() |> ignore
  fields["missing_reports"] = Json::array([Json::string("first")])
  assert_eq(
    integrity_error(Json::object(fields).stringify()),
    "DuplicateReport",
  )
  assert_eq(integrity_error(text), "accepted")
  for operation in 0..<5 {
    let fields = integrity_fields(text)
    guard fields["documents"] is Array(docs) else { fail("Expected receipts") }
    guard docs[0] is Object(receipt) else { fail("Expected receipt") }
    let expected = match operation {
      0 => {
        receipt["revision"] = Json::string("other")
        "BindingMismatch"
      }
      1 => {
        receipt["utf8_bytes"] = Json::number(16777217)
        "SourceLimit"
      }
      2 => {
        fields["missing_reports"] = Json::array([
          Json::string("missing"),
          Json::string("missing"),
        ])
        "DuplicateReport"
      }
      3 => {
        docs.clear()
        "EmptyInventory"
      }
      _ => {
        fields.remove("archive_sha256")
        "MissingField"
      }
    }
    assert_eq(integrity_error(Json::object(fields).stringify()), expected)
  }
}

///|
test "integrity exact numeric lexemes cannot round byte lengths and enforce bounded outputs" {
  let evidence = @wire.decode_evidence(@wire.encode_evidence(archive_ledger()))
  let manifest = evidence.integrity()
  let text = manifest.encode()
  let length = manifest.documents()[0].utf8_bytes
  let old = "\"utf8_bytes\": \{length}"
  for
    number in [
      "0", "-1", "2147483648", "1.0000000000000001", "1e-1000", "1e1000",
    ] {
    assert_eq(
      integrity_error(text.replace(old~, new="\"utf8_bytes\": " + number)),
      "ExpectedInteger",
    )
  }
  assert_eq(integrity_error(text.replace(old~, new=old + ".0")), "accepted")
  let limits = {
    ..@ledger.Limits::default(),
    max_source_units: text.length(),
    max_reports: 2,
  }
  assert_eq(@wire.decode_integrity(text, limits~).encode(limits~), text)
  assert_eq(
    integrity_error(text, limits={
      ..limits,
      max_source_units: text.length() - 1,
    }),
    "SourceLimit",
  )
  assert_eq(
    integrity_error(text, limits={ ..limits, max_reports: 1, }),
    "ReportLimit",
  )
  let output_error = try {
    ignore(
      manifest.encode(limits={ ..limits, max_source_units: text.length() - 1, }),
    )
    "accepted"
  } catch {
    @ledger.InputError::Invalid(d) => d.code
  }
  assert_eq(output_error, "SourceLimit")
  let creation_error = try {
    ignore(evidence.integrity(limits={ ..limits, max_source_units: 1, }))
    "accepted"
  } catch {
    @ledger.InputError::Invalid(d) => d.code
  }
  assert_eq(creation_error, "MTL_JUNIT_LIMIT")
  evidence.check_integrity(manifest)
}
