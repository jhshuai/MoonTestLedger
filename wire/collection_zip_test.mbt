///|
fn collected_zip(
  spec : @wire.CollectionSpec,
  inputs : Array[@wire.CollectedXml],
  reverse~ : Bool = false,
) -> Bytes raise {
  let paths : Map[String, String] = Map([])
  for file in spec.files() {
    paths[file.id] = file.path
  }
  let pairs = inputs.map(input => {
    (paths[input.id], @utf8.encode(input.xml).to_fixedarray())
  })
  if reverse {
    pairs.rev_in_place()
  }
  Bytes::from_array(@fzip.zip_sync_checked(pairs)[:])
}

///|
fn collect_zip_error(
  spec : @wire.CollectionSpec,
  bytes : Bytes,
  limits~ : @ledger.Limits = @ledger.Limits::default(),
) -> String {
  try {
    ignore(spec.collect_zip(bytes, limits~))
    "accepted"
  } catch {
    @ledger.InputError::Invalid(d) => d.code
  }
}

///|
test "ZIP collection preserves full plan original XML policy and input-order determinism" {
  for deny in [false, true] {
    let spec = collection_spec(deny~)
    let inputs = collection_inputs()
    let bytes = collected_zip(spec, inputs)
    let before = spec.encode()
    let evidence = spec.collect_zip(bytes)
    assert_eq(evidence.encode(), spec.collect(inputs[:]).encode())
    assert_eq(
      evidence.encode(),
      spec.collect_zip(collected_zip(spec, inputs, reverse=true)).encode(),
    )
    assert_eq(evidence.exit_code(), if deny { 1 } else { 0 })
    assert_eq(spec.encode(), before)
    assert_eq(
      spec.collect_zip(bytes, max_bytes=bytes.length()).encode(),
      evidence.encode(),
    )
  }
}

///|
test "ZIP collection empty missing partial and merged shards never shrink declared inventory" {
  let spec = collection_spec()
  let inputs = collection_inputs()
  let empty = spec.collect_zip(collected_zip(spec, []))
  assert_eq(empty.exit_code(), 3)
  assert_eq(empty.summary().missing_reports.length(), 2)
  let first = spec.collect_zip(collected_zip(spec, [inputs[0]]))
  let retry = spec.collect_zip(collected_zip(spec, [inputs[1]]))
  assert_eq(first.exit_code(), 3)
  assert_eq(first.summary().missing_reports, ["retry"])
  assert_eq(first.snapshot().plan.reports.length(), 2)
  assert_eq(
    @wire.merge_evidence([first, retry][:]).encode(),
    spec.collect(inputs[:]).encode(),
  )
  let partial = spec.collect_zip(
    collected_zip(spec, [{ ..inputs[0], xml: "<testsuite/>", }, inputs[1]]),
  )
  assert_eq(partial.exit_code(), 3)
  assert_eq(partial.summary().missing_reports, [])
  assert_eq(partial.summary().missing_cases.length(), 1)
}

///|
test "ZIP collection refuses unknown paths casing aliases malformed XML UTF8 and lowered budgets then recovers" {
  let spec = collection_spec()
  let inputs = collection_inputs()
  let good = collected_zip(spec, inputs)
  assert_eq(
    collect_zip_error(spec, collected_zip(spec, [inputs[0], inputs[0]])),
    "ZipProfile",
  )
  assert_eq(
    collect_zip_error(spec, good, limits={
      ..@ledger.Limits::default(),
      max_total_source_units: 1,
    }),
    "SourceLimit",
  )
  assert_true(
    (try spec.collect_zip(good, max_bytes=good.length() - 1) catch {
      _ => None
    } noraise {
      _ => Some(())
    })
    is None,
  )
  let before = spec.encode()
  for
    path in [
      "other.xml", "Initial/report.xml", "initial", "initial/../report.xml", "../report.xml",
    ] {
    let bytes = Bytes::from_array(
      @fzip.zip_sync_checked([
        (path, @utf8.encode(inputs[0].xml).to_fixedarray()),
      ])[:],
    )
    assert_eq(
      collect_zip_error(spec, bytes),
      if path.contains("..") {
        "CollectionPath"
      } else {
        "UnexpectedArtifact"
      },
    )
  }
  let invalid = Bytes::from_array(
    @fzip.zip_sync_checked([
      ("initial/report.xml", FixedArray::make(1, b'\xff')),
    ])[:],
  )
  assert_eq(collect_zip_error(spec, invalid), "InvalidUtf8")
  assert_eq(
    collect_zip_error(spec, collected_zip(spec, [{ ..inputs[0], xml: "<", }])),
    "MTL_JUNIT_XML",
  )

  assert_true(
    collect_zip_error(spec, collected_zip(spec, [{ ..inputs[0], xml: "", }])) !=
    "accepted",
  )
  assert_eq(
    collect_zip_error(
      spec,
      collected_zip(spec, [
        {
          ..inputs[0],
          xml: "<testsuite><testcase name='unknown'/></testsuite>",
        },
      ]),
    ),
    "UnexpectedCase",
  )
  assert_eq(
    collect_zip_error(spec, good, limits={
      ..@ledger.Limits::default(),
      max_reports: 1,
    }),
    "ReportLimit",
  )
  assert_true(
    collect_zip_error(spec, good, limits={
      ..@ledger.Limits::default(),
      max_source_units: 1,
    }) !=
    "accepted",
  )
  assert_eq(spec.encode(), before)
  assert_eq(spec.collect_zip(good).encode(), spec.collect(inputs[:]).encode())
}
