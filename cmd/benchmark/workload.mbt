///|
fn measure(count : Int32) -> Json raise {
  guard count >= 1 && count <= 100000 else {
    fail("case count must be 1..100000")
  }
  // Explicitly larger source budgets permit a complete 100k-case replay. They
  // stay within the library's validated limits; no output is truncated.
  let limits = {
    ..@ledger.Limits::default(),
    max_cases: count,
    max_source_units: 33554432,
    max_total_source_units: 67108864,
  }
  let start = @bench.monotonic_clock_start()
  let keys : Array[@ledger.CaseKey] = []
  let text = StringBuilder()
  text.write_string("<testsuite>")
  for index in 0..<count {
    let name = "case-\{index}"
    keys.push({ classname: "Generated", name, })
    text.write_string("<testcase classname='Generated' name='" + name + "'>")
    if index % 10 == 0 {
      text.write_string(
        "<failure message='sample'>retained failure payload</failure>",
      )
    } else if index % 10 == 1 {
      text.write_string("<skipped message='intentional'/>")
    }
    text.write_string("</testcase>")
  }
  text.write_string("</testsuite>")
  let xml = text.to_string()
  let expected : @ledger.ExpectedReport = {
    id: "generated",
    environment: "benchmark",
    shard: "one",
    attempt: 1,
    cases: keys,
  }
  let plan = @ledger.RunPlan::new(
    "generated-workload",
    "deterministic-v1",
    [expected],
    limits~,
  )
  let generation = @bench.monotonic_clock_end(start)
  let start = @bench.monotonic_clock_start()
  let parsed = @ledger.parse_junit(xml, report_id="generated", limits~)
  let parsing = @bench.monotonic_clock_end(start)
  assert_eq(parsed.cases.length(), count)
  let start = @bench.monotonic_clock_start()
  let ledger = @ledger.Ledger::new(plan, limits~)
  ledger.ingest({
    binding: {
      id: "generated",
      run_id: plan.run_id,
      revision: plan.revision,
      environment: "benchmark",
      shard: "one",
      attempt: 1,
    },
    report: parsed,
  })
  let summary = ledger.summary()
  assert_eq(summary.cases.length(), count)
  assert_true(summary.complete)
  assert_eq(summary.exit_code(), 1)
  assert_eq(
    summary.cases
    .iter()
    .filter(row => row.verdict == @ledger.Verdict::Failed)
    .count(),
    (count + 9) / 10,
  )
  assert_eq(
    summary.cases
    .iter()
    .filter(row => row.verdict == @ledger.Verdict::Skipped)
    .count(),
    (count + 8) / 10,
  )
  let reconcile = @bench.monotonic_clock_end(start)
  let start = @bench.monotonic_clock_start()
  let archive = @ledger.encode_evidence(ledger, limits~)
  let encoding = @bench.monotonic_clock_end(start)
  let start = @bench.monotonic_clock_start()
  let restored = @ledger.decode_evidence(archive, limits~)
  assert_eq(restored.source("generated"), Some(xml))
  assert_eq(restored.encode(limits~), archive)
  assert_eq(restored.exit_code(), 1)
  let replay = @bench.monotonic_clock_end(start)
  // A resource refusal cannot change the already accepted evidence, and a
  // corrected request remains usable. Keep its cost separate from phase times.
  if count > 1 {
    let rejected = try {
      ignore(
        @ledger.parse_junit(xml, limits={ ..limits, max_cases: count - 1, }),
      )
      false
    } catch {
      @ledger.InputError::Invalid(diagnostic) =>
        diagnostic.code == "MTL_JUNIT_LIMIT"
    }
    assert_true(rejected)
  }
  assert_eq(ledger.source("generated"), Some(xml))
  assert_eq(
    @ledger.parse_junit(
      "<testsuite><testcase name='recovery'/></testsuite>",
      limits~,
    ).cases.length(),
    1,
  )
  let xml_bytes = @utf8.encode(xml)
  let archive_bytes = @utf8.encode(archive)
  Json::object({
    "schema": Json::number(1),
    "workload": Json::string("deterministic-junit-v1"),
    "cases": Json::number(count.to_double()),
    "gate": Json::number(1),
    "failure_cases": Json::number(((count + 9) / 10).to_double()),
    "skipped_cases": Json::number(((count + 8) / 10).to_double()),
    "xml_bytes": Json::number(xml_bytes.length().to_double()),
    "archive_bytes": Json::number(archive_bytes.length().to_double()),
    "xml_sha256": Json::string(
      @crypto.bytes_to_hex_string(@crypto.sha256(xml_bytes)),
    ),
    "archive_sha256": Json::string(
      @crypto.bytes_to_hex_string(@crypto.sha256(archive_bytes)),
    ),
    "max_source_units": Json::number(limits.max_source_units.to_double()),
    "phase_microseconds": Json::object({
      "generate": Json::number(generation),
      "parse": Json::number(parsing),
      "reconcile": Json::number(reconcile),
      "encode": Json::number(encoding),
      "replay": Json::number(replay),
    }),
    "checks_passed": Json::boolean(true),
  })
}
