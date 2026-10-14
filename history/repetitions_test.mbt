///|
fn repeated_run(
  run : String,
  primary~ : @ledger.Outcome = @ledger.Outcome::Pass,
  retry~ : Bool = false,
  missing_retry~ : Bool = false,
  missing_all~ : Bool = false,
  missing_empty~ : Bool = false,
  revision~ : String = "rev",
  deny~ : Bool = false,
  shard~ : String = "one",
  extra~ : Bool = false,
) -> @wire.Evidence raise {
  let keys : Array[@ledger.CaseKey] = ["mixed😀", "alwaysfail", "skip"].map(name => {
    classname: "C",
    name,
  })
  if extra {
    keys.push({ classname: "C", name: "extra", })
  }
  let reports : Array[@ledger.ExpectedReport] = [
    { id: "initial", environment: "linux", shard, attempt: 1, cases: keys, },
  ]
  if retry {
    reports.push({
      id: "retry",
      environment: "linux",
      shard,
      attempt: 2,
      cases: [{ classname: "C", name: "mixed😀", }],
    })
  }
  if missing_empty {
    reports.push({
      id: "empty",
      environment: "linux",
      shard: "empty",
      attempt: 1,
      cases: [],
    })
  }
  let plan = @ledger.RunPlan::new(run, revision, reports)
  let ledger = @ledger.Ledger::new(plan)
  let marker = match primary {
    Pass => ""
    Failure =>
      "<failure message='transient'>original failure &amp; trace</failure>"
    Error => "<error>original error</error>"
    Skip => "<skipped message='not run'/>"
  }
  let source = "<testsuite><testcase classname='C' name='mixed😀'>" +
    marker +
    "</testcase><testcase classname='C' name='alwaysfail'><failure>persistent failure</failure></testcase><testcase classname='C' name='skip'><skipped/></testcase><system-out>raw retained metadata</system-out></testsuite>"
  if !missing_all {
    ledger.ingest({
      binding: {
        id: "initial",
        run_id: run,
        revision,
        environment: "linux",
        shard,
        attempt: 1,
      },
      report: @junit.parse(source),
    })
  }
  if retry && !missing_retry && !missing_all {
    ledger.ingest({
      binding: {
        id: "retry",
        run_id: run,
        revision,
        environment: "linux",
        shard,
        attempt: 2,
      },
      report: @junit.parse(
        "<testsuite><testcase classname='C' name='mixed😀'/></testsuite>",
      ),
    })
  }
  @wire.decode_evidence(@wire.encode_evidence(ledger, deny_recovered=deny))
}

///|
fn repetition_refusal(
  inputs : Array[@wire.Evidence],
  limits~ : @ledger.Limits = @ledger.Limits::default(),
) -> String {
  try {
    ignore(@history.analyze_repetitions(inputs[:], limits~))
    "accepted"
  } catch {
    @ledger.InputError::Invalid(d) => d.code
  }
}

///|
fn repeated_case(
  result : @history.Repetitions,
  name : String,
) -> @history.RepetitionCase {
  result.rows().iter().find_first(row => row.key.name == name).unwrap()
}

///|
test "same revision observations are deterministic separate run counts from attempts and retain payloads" {
  let a = repeated_run("a", primary=@ledger.Outcome::Failure, retry=true)
  let b = repeated_run("b", shard="moved")
  let before_a = a.encode()
  let result = @history.analyze_repetitions([b, a][:])
  assert_eq(result.exit_code(), 1)
  assert_eq(result.encode(), @history.analyze_repetitions([a, b][:]).encode())
  assert_eq(result.summaries().map(summary => summary.run_id), ["a", "b"])
  let row = result
    .rows()
    .iter()
    .find_first(row => row.key.name == "mixed😀")
    .unwrap()
  assert_eq(row.kind, @history.RepetitionKind::MixedOutcomes)
  assert_eq(row.pass_attempts, 2)
  assert_eq(row.failed_attempts, 1)
  assert_eq(row.error_attempts, 0)
  assert_eq(row.runs_with_pass, 2)
  assert_eq(row.runs_with_failure, 1)
  assert_eq(row.recovered_runs, 1)
  assert_eq(
    row.samples[0].case_summary.attempts[0].observation.problems[0].text,
    "original failure & trace",
  )
  assert_eq(row.samples[1].case_summary.shard, "moved")
  assert_eq(result.source("a", "initial"), a.source("initial"))
  assert_eq(result.source("unknown", "initial"), None)
  assert_eq(result.source("a", "unknown"), None)
  row.samples[0].case_summary.attempts[0].observation.problems.clear()
  row.samples.clear()
  let summaries = result.summaries()
  summaries[0].cases.clear()
  assert_eq(
    repeated_case(result, "mixed😀").samples[0].case_summary.attempts[0].observation.problems[0].text,
    "original failure & trace",
  )
  assert_eq(a.encode(), before_a)
  assert_eq(
    result.encode(),
    @history.analyze_repetitions(
      [@wire.decode_evidence(a.encode()), @wire.decode_evidence(b.encode())][:],
    ).encode(),
  )
}

///|
test "no mixture is not an all tests pass gate and skip never counts as a pass" {
  let a = repeated_run("a")
  let b = repeated_run("b")
  let result = @history.analyze_repetitions([a, b][:])
  assert_eq(result.exit_code(), 0)
  assert_eq(a.exit_code(), 1)
  assert_eq(
    repeated_case(result, "alwaysfail").kind,
    @history.RepetitionKind::FailureObserved,
  )
  assert_eq(
    repeated_case(result, "mixed😀").kind,
    @history.RepetitionKind::PassObserved,
  )
  assert_eq(
    repeated_case(result, "skip").kind,
    @history.RepetitionKind::SkipsOnly,
  )
  let skip = @history.analyze_repetitions(
    [
      repeated_run("a", primary=@ledger.Outcome::Failure),
      repeated_run("b", primary=@ledger.Outcome::Skip),
    ][:],
  )
  assert_eq(
    repeated_case(skip, "mixed😀").kind,
    @history.RepetitionKind::FailureObserved,
  )
  assert_eq(repeated_case(skip, "mixed😀").skipped_attempts, 1)
  assert_eq(repeated_case(skip, "mixed😀").pass_attempts, 0)
  assert_eq(skip.exit_code(), 0)
  let errors = @history.analyze_repetitions(
    [repeated_run("a", primary=@ledger.Outcome::Error), b][:],
  )
  assert_eq(
    repeated_case(errors, "mixed😀").kind,
    @history.RepetitionKind::MixedOutcomes,
  )
  assert_eq(repeated_case(errors, "mixed😀").error_attempts, 1)
}

///|
test "incomplete runs retain observed mixtures but cannot pass even with only an empty artifact missing" {
  let a = repeated_run(
    "a",
    primary=@ledger.Outcome::Failure,
    retry=true,
    missing_retry=true,
  )
  let b = repeated_run("b")
  let result = @history.analyze_repetitions([a, b][:])
  assert_false(result.complete())
  assert_eq(result.exit_code(), 3)
  assert_eq(
    repeated_case(result, "mixed😀").kind,
    @history.RepetitionKind::MixedOutcomes,
  )
  assert_eq(repeated_case(result, "mixed😀").incomplete_runs, 1)
  assert_eq(result.summaries()[0].missing_reports, ["retry"])
  let empty = @history.analyze_repetitions(
    [repeated_run("a", missing_empty=true), b][:],
  )
  assert_eq(empty.exit_code(), 3)
  assert_true(empty.rows().all(row => row.incomplete_runs == 0))
  assert_eq(empty.summaries()[0].missing_reports, ["empty"])
  let absent = @history.analyze_repetitions(
    [repeated_run("a", missing_all=true), repeated_run("b", missing_all=true)][:],
  )
  assert_true(
    absent
    .rows()
    .all(row => row.kind == @history.RepetitionKind::NoObservations),
  )
  assert_eq(absent.exit_code(), 3)
}

///|
test "duplicate runs revisions policies and inventory changes are refused without changing inputs" {
  let a = repeated_run("a")
  let before = a.encode()
  assert_eq(repetition_refusal([]), "RepetitionRunCount")
  assert_eq(repetition_refusal([a]), "RepetitionRunCount")
  assert_eq(repetition_refusal([a, a]), "DuplicateRun")
  assert_eq(
    repetition_refusal([a, repeated_run("b", revision="changed")]),
    "RepetitionRevisionMismatch",
  )
  assert_eq(
    repetition_refusal([a, repeated_run("b", deny=true)]),
    "RepetitionPolicyMismatch",
  )
  assert_eq(
    repetition_refusal([a, repeated_run("b", extra=true)]),
    "RepetitionInventoryMismatch",
  )
  assert_eq(a.encode(), before)
  assert_eq(
    @history.analyze_repetitions([a, repeated_run("b")][:]).exit_code(),
    0,
  )
}

///|
test "aggregate budgets have exact boundaries across input archives and refuse oversize derived output" {
  let a = repeated_run("a")
  let b = repeated_run("b")
  let units = a.encode().length() + b.encode().length()
  let limits = {
    ..@ledger.Limits::default(),
    max_reports: 2,
    max_cases: 6,
    max_problems: 2,
    max_total_source_units: units,
  }
  let result = @history.analyze_repetitions([a, b][:], limits~)
  assert_eq(result.exit_code(), 0)
  assert_eq(
    repetition_refusal([a, b], limits={
      ..limits,
      max_total_source_units: units - 1,
    }),
    "SourceLimit",
  )
  assert_eq(
    repetition_refusal([a, b], limits={ ..limits, max_reports: 1, }),
    "ReportLimit",
  )
  assert_eq(
    repetition_refusal([a, b], limits={ ..limits, max_cases: 5, }),
    "CaseLimit",
  )
  assert_eq(
    repetition_refusal([a, b], limits={ ..limits, max_problems: 1, }),
    "ProblemLimit",
  )
  assert_eq(
    repetition_refusal([repeated_run("a", retry=true), b], limits={
      ..limits,
      max_cases: 7,
      max_total_source_units: 33554432,
    }),
    "ReportLimit",
  )
  let text = result.encode()
  assert_eq(
    result.encode(limits={
      ..@ledger.Limits::default(),
      max_source_units: text.length(),
    }),
    text,
  )
  let code = try {
    ignore(
      result.encode(limits={
        ..@ledger.Limits::default(),
        max_source_units: text.length() - 1,
      }),
    )
    "accepted"
  } catch {
    @ledger.InputError::Invalid(d) => d.code
  }
  assert_eq(code, "RepetitionOutputLimit")
  assert_eq(result.encode(), text)
}
