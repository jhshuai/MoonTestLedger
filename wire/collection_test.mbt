///|
fn collection_spec(deny~ : Bool = false) -> @wire.CollectionSpec raise {
  let plan = archive_ledger().snapshot().plan
  let files : Array[@wire.CollectionFile] = [
    { id: "first", path: "initial/report.xml", },
    { id: "retry", path: "retry/report.xml", },
  ]
  @wire.CollectionSpec::new(plan, files[:], deny_recovered=deny)
}

///|
fn collection_inputs() -> Array[@wire.CollectedXml] raise {
  archive_ledger().snapshot().documents.map(doc => {
    id: doc.binding.id,
    xml: doc.report.source,
  })
}

///|
fn collection_error(
  spec : @wire.CollectionSpec,
  inputs : Array[@wire.CollectedXml],
  limits~ : @ledger.Limits = @ledger.Limits::default(),
) -> String {
  try {
    ignore(spec.collect(inputs[:], limits~))
    "accepted"
  } catch {
    @ledger.InputError::Invalid(d) => d.code
  }
}

///|
test "collection spec round trips deterministically preserves original XML policy and full plan" {
  for deny in [false, true] {
    let spec = collection_spec(deny~)
    let text = spec.encode()
    let loaded = @wire.decode_collection(text)
    assert_eq(loaded.encode(), text)
    let inputs = collection_inputs()
    let evidence = loaded.collect(inputs[:])
    assert_eq(
      evidence.encode(),
      @wire.encode_evidence(archive_ledger(), deny_recovered=deny),
    )
    assert_eq(evidence.exit_code(), if deny { 1 } else { 0 })
    assert_eq(
      loaded.collect([inputs[1], inputs[0]][:]).encode(),
      evidence.encode(),
    )
    assert_eq(spec.encode(), text)
    spec.files().clear()
    assert_eq(spec.encode(), text)
    let unordered = @wire.CollectionSpec::new(
      evidence.snapshot().plan,
      [spec.files()[1], spec.files()[0]][:],
      deny_recovered=deny,
    )
    assert_eq(unordered.encode(), text)
  }
}

///|
test "collection preserves missing artifact and missing testcase evidence instead of shrinking the plan" {
  let spec = collection_spec()
  let inputs = collection_inputs()
  let initial = spec.collect([inputs[0]][:])
  assert_eq(initial.exit_code(), 3)
  assert_eq(initial.summary().missing_reports, ["retry"])
  assert_eq(initial.snapshot().plan.reports.length(), 2)
  let empty = spec.collect([][:])
  assert_eq(empty.exit_code(), 3)
  assert_eq(empty.summary().missing_reports.length(), 2)
  let partial = spec.collect(
    [{ ..inputs[0], xml: "<testsuite/>", }, inputs[1]][:],
  )
  assert_eq(partial.exit_code(), 3)
  assert_eq(partial.summary().missing_reports, [])
  assert_eq(partial.summary().missing_cases.length(), 1)
  assert_eq(spec.collect(inputs[:]).exit_code(), 0)
}

///|
test "collection refuses duplicate unknown malformed and unexpected artifacts atomically then recovers" {
  let spec = collection_spec()
  let text = spec.encode()
  let inputs = collection_inputs()
  assert_eq(collection_error(spec, [inputs[0], inputs[0]]), "DuplicateReport")
  assert_eq(
    collection_error(spec, [{ ..inputs[0], id: "unknown", }]),
    "UnexpectedReport",
  )
  assert_eq(
    collection_error(spec, [
      inputs[0],
      {
        ..inputs[1],
        xml: "<testsuite><testcase classname='C' name='unexpected'/></testsuite>",
      },
    ]),
    "UnexpectedCase",
  )
  assert_true(
    collection_error(spec, [inputs[0], { ..inputs[1], xml: "<broken", }]).has_prefix(
      "MTL_JUNIT_",
    ),
  )
  assert_eq(spec.encode(), text)
  assert_eq(spec.collect(inputs[:]).summary(), archive_ledger().summary())
}

///|
test "collection rejects incomplete duplicate unknown path mapping and preserves caller-owned inventories" {
  let plan = archive_ledger().snapshot().plan
  let valid : Array[@wire.CollectionFile] = [
    { id: "first", path: "first.xml", },
    { id: "retry", path: "retry.xml", },
  ]
  let spec = @wire.CollectionSpec::new(plan, valid[:])
  let text = spec.encode()
  for
    (files, code) in [
      ([valid[0]], "CollectionInventory"),
      ([valid[0], valid[0]], "DuplicateReport"),
      ([valid[0], { ..valid[1], id: "extra", }], "UnexpectedReport"),
      (
        [valid[0], { ..valid[1], path: "first.xml", }],
        "CollectionPathCollision",
      ),
      (
        [valid[0], { ..valid[1], path: "FIRST.xml", }],
        "CollectionPathCollision",
      ),
      (
        [valid[0], { ..valid[1], path: "first.xml/child.xml", }],
        "CollectionPathCollision",
      ),
      (
        [
          { ..valid[0], path: "jobs/a.xml", },
          { ..valid[1], path: "Jobs/b.xml", },
        ],
        "CollectionPathCollision",
      ),
    ] {
    let result = try {
      ignore(@wire.CollectionSpec::new(plan, files[:]))
      "accepted"
    } catch {
      @ledger.InputError::Invalid(d) => d.code
    }
    assert_eq(result, code)
  }
  plan.reports[0].cases.clear()
  plan.reports.clear()
  valid.clear()
  assert_eq(spec.encode(), text)
  assert_eq(spec.collect(collection_inputs()[:]).exit_code(), 0)
}

///|
test "collection relative path contract refuses traversal device names nonportable aliases and excessive depth" {
  let plan = archive_ledger().snapshot().plan
  for
    path in [
      "",
      "/root.xml",
      "../outside.xml",
      "./test.xml",
      "x/../test.xml",
      "x//test.xml",
      "x/",
      "C:/test.xml",
      "x\\test.xml",
      "nul.xml",
      "CON",
      "COM1.xml",
      "lpt9.log",
      "x/AUX.xml",
      "name.",
      "name ",
      "file:stream",
      "*.xml",
      "中文.xml",
      "com¹.xml",
      "a".repeat(256),
      "d/".repeat(32) + "x.xml",
    ] {
    let files : Array[@wire.CollectionFile] = [
      { id: "first", path, },
      { id: "retry", path: "retry.xml", },
    ]
    let result = try {
      ignore(@wire.CollectionSpec::new(plan, files[:]))
      "accepted"
    } catch {
      @ledger.InputError::Invalid(d) => d.code
    }
    assert_eq(result, "CollectionPath")
  }
  let files : Array[@wire.CollectionFile] = [
    { id: "first", path: ".reports/TEST-com.example_C-1.xml", },
    { id: "retry", path: "retry.xml", },
  ]
  let spec = @wire.CollectionSpec::new(plan, files[:])
  assert_eq(spec.files().length(), 2)
}

///|
test "collection codecs strictly reject unknown nested data duplicate keys rounded numbers and invalid policy" {
  let text = collection_spec().encode()
  for
    (old, new, code) in [
      ("moontestledger/collection", "other", "CollectionKind"),
      ("\"schema\": 1", "\"schema\": 2", "UnsupportedSchema"),
      ("\"schema\": 1", "\"schema\": 1.0000000000000001", "ExpectedInteger"),
      ("\"attempt\": 1", "\"attempt\": 1.0000000000000001", "ExpectedInteger"),
      ("\"schema\": 1", "\"schema\": 1, \"schema\": 1", "DuplicateJsonKey"),
      ("\"kind\":", "\"future\": 1, \"kind\":", "UnknownField"),
      ("\"path\":", "\"path\": null, \"extra\":", "UnknownField"),
      ("\"deny_recovered\": false", "\"deny_recovered\": 1", "ExpectedBoolean"),
    ] {
    let code_found = try {
      ignore(@wire.decode_collection(text.replace(old~, new~)))
      "accepted"
    } catch {
      @ledger.InputError::Invalid(d) => d.code
    }
    assert_eq(code_found, code)
  }
  assert_eq(@wire.decode_collection(text).encode(), text)
}

///|
test "collection enforces inclusive source inventory and output budgets without changing inputs" {
  let spec = collection_spec()
  let text = spec.encode()
  let inputs = collection_inputs()
  let units = inputs[0].xml.length() + inputs[1].xml.length()
  let limits = {
    ..@ledger.Limits::default(),
    max_total_source_units: units,
    max_reports: 2,
    max_cases: 2,
  }
  assert_eq(spec.collect(inputs[:], limits~).exit_code(), 0)
  assert_eq(
    collection_error(spec, inputs, limits={
      ..limits,
      max_total_source_units: units - 1,
    }),
    "SourceLimit",
  )
  assert_eq(
    collection_error(spec, inputs, limits={ ..limits, max_reports: 1, }),
    "ReportLimit",
  )
  assert_eq(
    collection_error(spec, inputs, limits={ ..limits, max_cases: 1, }),
    "CaseLimit",
  )
  assert_eq(
    @wire.decode_collection(text, limits={
      ..limits,
      max_source_units: text.length(),
    }).encode(),
    text,
  )
  let code = try {
    ignore(
      spec.encode(limits={ ..limits, max_source_units: text.length() - 1, }),
    )
    "accepted"
  } catch {
    @ledger.InputError::Invalid(d) => d.code
  }
  assert_eq(code, "SourceLimit")
  let invalid = try {
    ignore(spec.collect(inputs[:], limits={ ..limits, max_reports: 0, }))
    "accepted"
  } catch {
    @ledger.InputError::Invalid(d) => d.code
  }
  assert_eq(invalid, "InvalidLimit")
  assert_eq(spec.encode(), text)
}
