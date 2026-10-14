///|
fn archive_ledger(missing~ : Bool = false) -> @ledger.Ledger raise {
  let plan = @ledger.RunPlan::new("run", "rev", [
    {
      id: "first",
      environment: "linux",
      shard: "one",
      attempt: 1,
      cases: [{ classname: "C", name: "a", }],
    },
    {
      id: "retry",
      environment: "linux",
      shard: "one",
      attempt: 2,
      cases: [{ classname: "C", name: "a", }],
    },
  ])
  let ledger = @ledger.Ledger::new(plan)
  let sources = [
    "<testsuite><properties><property name='secret' value='retained'/></properties><testcase classname='C' name='a'><failure message='assert'>raw &amp; <![CDATA[<trace>😀]]></failure><system-out>logs</system-out></testcase></testsuite>",
    "<testsuite><testcase classname='C' name='a'/></testsuite>",
  ]
  for i, id in ["first", "retry"] {
    if i == 1 && missing {
      continue
    }
    ledger.ingest({
      binding: {
        id,
        run_id: "run",
        revision: "rev",
        environment: "linux",
        shard: "one",
        attempt: i + 1,
      },
      report: @junit.parse(sources[i]),
    })
  }
  ledger
}

///|
fn archive_error(
  source : String,
  limits~ : @ledger.Limits = @ledger.Limits::default(),
) -> String {
  try {
    ignore(@wire.decode_evidence(source, limits~))
    "accepted"
  } catch {
    @ledger.InputError::Invalid(diagnostic) => diagnostic.code
  }
}

///|
test "archive replays policy attempts and exact source deterministically" {
  let ledger = archive_ledger()
  for deny in [false, true] {
    let text = @wire.encode_evidence(ledger, deny_recovered=deny)
    let restored = @wire.decode_evidence(text)
    assert_eq(restored.summary(), ledger.summary())
    assert_eq(restored.source("first"), ledger.source("first"))
    assert_eq(restored.source("retry"), ledger.source("retry"))
    assert_eq(restored.deny_recovered(), deny)
    assert_eq(restored.exit_code(), if deny { 1 } else { 0 })
    assert_eq(restored.encode(), text)
    let copy = ledger.snapshot()
    copy.plan.reports.clear()
    copy.documents[0].report.cases.clear()
    assert_eq(restored.summary(), ledger.summary())
  }
}

///|
test "archive preserves missing evidence rather than shrinking inventory" {
  let ledger = archive_ledger(missing=true)
  let restored = @wire.decode_evidence(@wire.encode_evidence(ledger))
  assert_eq(restored.summary(), ledger.summary())
  assert_eq(restored.exit_code(), 3)
  assert_eq(restored.summary().missing_reports, ["retry"])
}

///|
test "archive rejects unknown schema fields duplicates bindings and bad XML" {
  let text = @wire.encode_evidence(archive_ledger())
  assert_eq(
    archive_error(
      text.replace(old="\"moontestledger/evidence\"", new="\"other\""),
    ),
    "ArchiveKind",
  )
  assert_eq(
    archive_error(
      text.replace(
        old="\"deny_recovered\": false",
        new="\"deny_recovered\": false, \"future\": 1",
      ),
    ),
    "UnknownField",
  )
  assert_eq(
    archive_error(
      text.replace(old="\"deny_recovered\": false", new="\"deny_recovered\": 1"),
    ),
    "ExpectedBoolean",
  )
  assert_eq(
    archive_error(
      text.replace(old="\"schema\": 1", new="\"schema\": 1.0000000000000001"),
    ),
    "ExpectedInteger",
  )
  assert_eq(
    archive_error(text.replace(old="\"xml\":", new="\"future_xml\":")),
    "UnknownField",
  )
  assert_eq(
    archive_error(
      text.replace(old="\"id\": \"retry\"", new="\"id\": \"first\""),
    ),
    "DuplicateReport",
  )
  assert_eq(
    archive_error(
      text.replace(old="<testsuite>", new="<!DOCTYPE testsuite><testsuite>"),
    ),
    "MTL_JUNIT_UNSUPPORTED",
  )
  assert_eq(@wire.decode_evidence(text).exit_code(), 0)
  let duplicate = @json.parse(text)
  guard duplicate is { "documents": Array(documents), .. } else {
    fail("Expected archive documents")
  }
  documents.push(documents[0])
  assert_eq(archive_error(duplicate.stringify()), "DuplicateReport")
  let mismatched = @json.parse(text)
  guard mismatched is { "documents": [Object(binding), ..], .. } else {
    fail("Expected report binding")
  }
  binding["revision"] = Json::string("different-revision")
  assert_eq(archive_error(mismatched.stringify()), "BindingMismatch")
  binding["revision"] = Json::string("rev")
  binding["id"] = Json::string("undeclared")
  assert_eq(archive_error(mismatched.stringify()), "UnexpectedReport")
}

///|
test "archive source and observation mismatch is refused before data can be lost" {
  let ledger = archive_ledger()
  let snapshot = ledger.snapshot()
  let wrong = @ledger.Ledger::new(snapshot.plan)
  for document in snapshot.documents {
    wrong.ingest({
      ..document,
      report: { ..document.report, source: document.report.source + "\n", },
    })
  }
  let result = try {
    ignore(@wire.encode_evidence(wrong))
    "accepted"
  } catch {
    @ledger.InputError::Invalid(diagnostic) => diagnostic.code
  }
  // Whitespace outside the root changes only authored source, not observations:
  // its ParsedReport source is still identical to the reparsed source.
  assert_eq(result, "accepted")
  let forged = @ledger.Ledger::new(snapshot.plan)
  for document in snapshot.documents {
    let cases = document.report.cases.map(testcase => {
      ..testcase,
      path: "/invented",
    })
    forged.ingest({ ..document, report: { ..document.report, cases, }, })
  }
  let code = try {
    ignore(@wire.encode_evidence(forged))
    "accepted"
  } catch {
    @ledger.InputError::Invalid(diagnostic) => diagnostic.code
  }
  assert_eq(code, "ProjectionMismatch")
  assert_eq(forged.summary().cases[0].attempts[0].observation.path, "/invented")
}

///|
test "archive budgets are inclusive on encoded input and refuse oversized output" {
  let ledger = archive_ledger()
  let text = @wire.encode_evidence(ledger)
  let limits = { ..@ledger.Limits::default(), max_source_units: text.length(), }
  assert_eq(@wire.decode_evidence(text, limits~).encode(limits~), text)
  assert_eq(
    archive_error(text, limits={
      ..limits,
      max_source_units: text.length() - 1,
    }),
    "SourceLimit",
  )
  let code = try {
    ignore(
      @wire.encode_evidence(ledger, limits={
        ..limits,
        max_source_units: text.length() - 1,
      }),
    )
    "accepted"
  } catch {
    @ledger.InputError::Invalid(diagnostic) => diagnostic.code
  }
  assert_eq(code, "SourceLimit")
}
