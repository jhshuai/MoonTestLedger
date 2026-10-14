///|
fn tar_collection_fixture(
  deny : Bool,
) -> (CollectionSpec, Array[CarrierMember], Evidence) raise @ledger.InputError {
  let key : @ledger.CaseKey = { classname: "Payment", name: "charge", }
  let plan = @ledger.RunPlan::new("tar-run", "rev", [
    {
      id: "first",
      environment: "linux",
      shard: "payments",
      attempt: 1,
      cases: [key],
    },
    {
      id: "retry",
      environment: "linux",
      shard: "payments",
      attempt: 2,
      cases: [key],
    },
  ])
  let spec = CollectionSpec::new(
    plan,
    [
      { id: "first", path: "initial/report.xml", },
      { id: "retry", path: "retry/report.xml", },
    ][:],
    deny_recovered=deny,
  )
  let inputs : Array[CollectedXml] = [
    {
      id: "first",
      xml: "<testsuite><testcase classname='Payment' name='charge'><failure message='网络故障'>original\ntrace</failure></testcase></testsuite>",
    },
    {
      id: "retry",
      xml: "<testsuite><testcase classname='Payment' name='charge'/></testsuite>",
    },
  ]
  let entries : Array[CarrierMember] = [
    { name: "initial/report.xml", data: @utf8.encode(inputs[0].xml), },
    { name: "retry/report.xml", data: @utf8.encode(inputs[1].xml), },
  ]
  (spec, entries, spec.collect(inputs[:]))
}

///|
fn tar_collection_error(
  spec : CollectionSpec,
  bytes : Bytes,
  limits~ : @ledger.Limits = @ledger.Limits::default(),
) -> String {
  try {
    ignore(spec.collect_tar(bytes, limits~))
    "accepted"
  } catch {
    @ledger.InputError::Invalid(d) => d.code
  }
}

///|
test "USTAR collection preserves exact Unicode source full retries policy ordering and merge" {
  for deny in [false, true] {
    let (spec, entries, original) = tar_collection_fixture(deny)
    let bytes = tar_write(entries, 16777216)
    let evidence = spec.collect_tar(bytes)
    assert_eq(evidence.encode(), original.encode())
    assert_eq(evidence.exit_code(), if deny { 1 } else { 0 })
    assert_eq(evidence.source("first"), original.source("first"))
    assert_eq(
      spec.collect_tar(tar_write(entries.rev(), 16777216)).encode(),
      original.encode(),
    )
    assert_eq(
      spec.collect_tar(bytes, max_bytes=bytes.length()).encode(),
      original.encode(),
    )
    let first = spec.collect_tar(tar_write([entries[0]], 16777216))
    let retry = spec.collect_tar(tar_write([entries[1]], 16777216))
    assert_eq(first.exit_code(), 3)
    assert_eq(first.summary().missing_reports, ["retry"])
    assert_eq(first.snapshot().plan.reports.length(), 2)
    assert_eq(merge_evidence([retry, first][:]).encode(), original.encode())
    let partial = spec.collect_tar(
      tar_write(
        [{ ..entries[0], data: b"<testsuite/>", }, entries[1]],
        16777216,
      ),
    )
    assert_eq(partial.exit_code(), 3)
    assert_eq(partial.summary().missing_reports, [])
    assert_eq(partial.summary().missing_cases.length(), 1)
  }
}

///|
test "USTAR collection refuses undeclared case aliases duplicate paths malformed XML and limits atomically" {
  let (spec, entries, original) = tar_collection_fixture(false)
  let before = spec.encode()
  let valid = tar_write(entries, 16777216)
  for
    path in [
      "other.xml", "Initial/report.xml", "initial", "initial/report.xml/extra",
    ] {
    assert_eq(
      tar_collection_error(
        spec,
        tar_write([{ ..entries[0], name: path, }], 16777216),
      ),
      "UnexpectedArtifact",
    )
  }
  assert_eq(
    tar_collection_error(spec, tar_write([entries[0], entries[0]], 16777216)),
    "TarProfile",
  )
  assert_eq(
    tar_collection_error(
      spec,
      tar_write([{ ..entries[0], data: b"\xff", }], 16777216),
    ),
    "InvalidUtf8",
  )
  assert_eq(
    tar_collection_error(
      spec,
      tar_write([{ ..entries[0], data: b"<", }], 16777216),
    ),
    "MTL_JUNIT_XML",
  )
  assert_eq(
    tar_collection_error(
      spec,
      tar_write(
        [
          {
            ..entries[0],
            data: b"<testsuite><testcase name='wrong'/></testsuite>",
          },
        ],
        16777216,
      ),
    ),
    "UnexpectedCase",
  )
  assert_eq(
    tar_collection_error(spec, valid, limits={
      ..@ledger.Limits::default(),
      max_reports: 1,
    }),
    "ReportLimit",
  )
  assert_eq(
    tar_collection_error(spec, valid, limits={
      ..@ledger.Limits::default(),
      max_total_source_units: 1,
    }),
    "SourceLimit",
  )
  assert_true(
    tar_collection_error(spec, valid, limits={
      ..@ledger.Limits::default(),
      max_source_units: 1,
    }) !=
    "accepted",
  )
  let link = valid.to_array()
  link[156] = b'2'
  tar_rechecksum(link)
  assert_eq(
    tar_collection_error(spec, Bytes::from_array(link[:])),
    "TarProfile",
  )
  let traversal = tar_write(
    [{ ..entries[0], name: "xx/report.xml", }],
    16777216,
  ).to_array()
  traversal[0] = b'.'
  traversal[1] = b'.'
  tar_rechecksum(traversal)
  assert_eq(
    tar_collection_error(spec, Bytes::from_array(traversal[:])),
    "CollectionPath",
  )
  assert_eq(spec.encode(), before)
  assert_eq(spec.collect_tar(valid).encode(), original.encode())
}
