///|
fn key(name : String, classname~ : String = "Suite") -> @ledger.CaseKey {
  { classname, name, }
}

///|
fn expected(
  id : String,
  attempt : Int32,
  cases : Array[@ledger.CaseKey],
  environment~ : String = "linux",
  shard~ : String = "main",
) -> @ledger.ExpectedReport {
  { id, environment, shard, attempt, cases, }
}

///|
fn observation(
  key : @ledger.CaseKey,
  outcome~ : @ledger.Outcome = @ledger.Outcome::Pass,
  problems~ : Array[@ledger.Problem] = [],
  skipped_reason~ : String? = None,
) -> @ledger.ObservedCase {
  {
    key,
    outcome,
    problems,
    skipped_reason,
    path: "/testsuite/testcase",
    line: 3,
    column: 5,
  }
}

///|
fn problem(
  kind : @ledger.ProblemKind,
  text~ : String = "expected 1\nactual 2",
) -> @ledger.Problem {
  {
    kind,
    message: Some("assertion"),
    type_name: Some("AssertionError"),
    text,
    path: "/testsuite/testcase/failure",
    line: 4,
    column: 7,
  }
}

///|
fn document(
  id : String,
  attempt : Int32,
  cases : Array[@ledger.ObservedCase],
  source~ : String = "original XML with <system-out>logs</system-out>",
  environment~ : String = "linux",
  shard~ : String = "main",
  run_id~ : String = "run-42",
  revision~ : String = "commit-a",
) -> @ledger.Document {
  {
    binding: { id, run_id, revision, environment, shard, attempt, },
    report: { source, cases, },
  }
}

///|
fn rejected(action : () -> Unit raise @ledger.InputError) -> String raise {
  let code = try {
    action()
    None
  } catch {
    @ledger.InputError::Invalid(diagnostic) => Some(diagnostic.code)
  }
  match code {
    Some(code) => code
    None => fail("Expected rejected input")
  }
}

///|
test "declared retry order wins over ingestion order and preserves every attempt" {
  let a = key("parameter [1]")
  let b = key("parameter [2]")
  let c = key("parameter [3]")
  let plan = @ledger.RunPlan::new("run-42", "commit-a", [
    expected("retry", 2, [a, c]),
    expected("initial", 1, [c, b, a]),
  ])
  let first = document("initial", 1, [
    observation(a, outcome=@ledger.Outcome::Failure, problems=[
      problem(@ledger.ProblemKind::Failure),
    ]),
    observation(b),
    observation(c, outcome=@ledger.Outcome::Error, problems=[
      problem(@ledger.ProblemKind::Failure),
      problem(@ledger.ProblemKind::Error, text="connection reset"),
    ]),
  ])
  let retry = document("retry", 2, [
    observation(
      c,
      outcome=@ledger.Outcome::Skip,
      skipped_reason=Some("dependency offline"),
    ),
    observation(a),
  ])
  let reverse = @ledger.Ledger::new(plan)
  reverse.ingest(retry)
  reverse.ingest(first)
  let forward = @ledger.Ledger::new(plan)
  forward.ingest(first)
  forward.ingest(retry)
  let summary = reverse.summary()
  assert_eq(summary, forward.summary())
  assert_true(summary.complete)
  assert_eq(summary.cases.map(item => item.key), [a, b, c])
  assert_eq(summary.cases.map(item => item.verdict), [
    @ledger.Verdict::RecoveredOnRetry,
    @ledger.Verdict::Passed,
    @ledger.Verdict::Unresolved,
  ])
  assert_eq(summary.cases[0].attempts.map(item => item.attempt), [1, 2])
  assert_eq(
    summary.cases[0].attempts[0].observation.problems[0].text,
    "expected 1\nactual 2",
  )
  assert_eq(summary.cases[2].attempts[0].observation.problems.length(), 2)
  assert_eq(
    summary.cases[2].attempts[1].observation.skipped_reason,
    Some("dependency offline"),
  )
  assert_eq(summary.exit_code(), 1)
}

///|
test "recovery policy and a later failure use the declared final attempt" {
  let a = key("a")
  let plan = @ledger.RunPlan::new("run-42", "commit-a", [
    expected("one", 1, [a]),
    expected("two", 2, [a]),
  ])
  let recovered = @ledger.Ledger::new(plan)
  recovered.ingest(
    document("one", 1, [
      observation(a, outcome=@ledger.Outcome::Failure, problems=[
        problem(@ledger.ProblemKind::Failure),
      ]),
    ]),
  )
  recovered.ingest(document("two", 2, [observation(a)]))
  assert_eq(recovered.summary().exit_code(), 0)
  assert_eq(recovered.summary().exit_code(deny_recovered=true), 1)
  let failed = @ledger.Ledger::new(plan)
  failed.ingest(document("one", 1, [observation(a)]))
  failed.ingest(
    document("two", 2, [
      observation(a, outcome=@ledger.Outcome::Failure, problems=[
        problem(@ledger.ProblemKind::Failure),
      ]),
    ]),
  )
  assert_eq(failed.summary().cases[0].verdict, @ledger.Verdict::Failed)
  assert_eq(failed.summary().exit_code(), 1)
}

///|
test "missing reports and missing cases remain visible and outrank failure exit status" {
  let a = key("a")
  let b = key("b")
  let plan = @ledger.RunPlan::new("run-42", "commit-a", [
    expected("initial", 1, [b, a]),
    expected("retry", 2, [a]),
  ])
  let ledger = @ledger.Ledger::new(plan)
  ledger.ingest(
    document("initial", 1, [
      observation(a, outcome=@ledger.Outcome::Failure, problems=[
        problem(@ledger.ProblemKind::Failure),
      ]),
    ]),
  )
  let incomplete = ledger.summary()
  assert_false(incomplete.complete)
  assert_eq(incomplete.missing_reports, ["retry"])
  assert_eq(incomplete.missing_cases, [
    { report_id: "initial", key: b, },
    { report_id: "retry", key: a, },
  ])
  assert_eq(incomplete.cases.map(item => item.verdict), [
    @ledger.Verdict::Incomplete,
    @ledger.Verdict::Incomplete,
  ])
  assert_eq(incomplete.cases[0].attempts.length(), 1)
  assert_eq(incomplete.exit_code(), 3)
  ledger.ingest(document("retry", 2, [observation(a)]))
  assert_eq(
    ledger.summary().cases[0].verdict,
    @ledger.Verdict::RecoveredOnRetry,
  )
  assert_eq(ledger.summary().missing_cases, [{ report_id: "initial", key: b, }])
  assert_eq(ledger.summary().exit_code(), 3)
}

///|
test "all binding coordinates are checked before accepting evidence" {
  let a = key("a")
  let ledger = @ledger.Ledger::new(
    @ledger.RunPlan::new("run-42", "commit-a", [expected("report", 1, [a])]),
  )
  for
    bad in [
      document("report", 1, [observation(a)], run_id="another-run"),
      document("report", 1, [observation(a)], revision="another-commit"),
      document("report", 1, [observation(a)], environment="windows"),
      document("report", 1, [observation(a)], shard="other"),
      document("report", 2, [observation(a)]),
    ] {
    assert_eq(rejected(() => ledger.ingest(bad)), "BindingMismatch")
    assert_eq(ledger.source("report"), None)
  }
  assert_eq(
    rejected(() => ledger.ingest(document("unplanned", 1, [observation(a)]))),
    "UnexpectedReport",
  )
  ledger.ingest(document("report", 1, [observation(a)]))
  assert_true(ledger.summary().complete)
}

///|
test "identical reimport is idempotent while conflicting content cannot replace evidence" {
  let a = key("a")
  let limits = {
    ..@ledger.Limits::default(),
    max_cases: 1,
    max_source_units: 1,
    max_total_source_units: 1,
    max_problems: 1,
  }
  let ledger = @ledger.Ledger::new(
    @ledger.RunPlan::new(
      "run-42",
      "commit-a",
      [expected("report", 1, [a])],
      limits~,
    ),
    limits~,
  )
  let original = document(
    "report",
    1,
    [
      observation(a, outcome=@ledger.Outcome::Failure, problems=[
        problem(@ledger.ProblemKind::Failure),
      ]),
    ],
    source="x",
  )
  ledger.ingest(original)
  let before = ledger.summary()
  ledger.ingest(original)
  ledger.ingest(original)
  assert_eq(ledger.summary(), before)
  assert_eq(
    rejected(() => {
      ledger.ingest(document("report", 1, [observation(a)], source="x"))
    }),
    "ConflictingReport",
  )
  assert_eq(
    rejected(() => {
      ledger.ingest({ ..original, report: { ..original.report, source: "y", }, })
    }),
    "ConflictingReport",
  )
  assert_eq(ledger.summary(), before)
  assert_eq(ledger.source("report"), Some("x"))
}

///|
test "validation is atomic even after earlier valid cases and recovery uses the same identity" {
  let a = key("a")
  let b = key("b")
  let ledger = @ledger.Ledger::new(
    @ledger.RunPlan::new("run-42", "commit-a", [expected("report", 1, [a, b])]),
  )
  let empty = ledger.summary()
  let bad_cases = [
    [observation(a), observation(key("unplanned"))],
    [observation(a), observation(a)],
    [
      observation(a),
      observation(b, outcome=@ledger.Outcome::Pass, problems=[
        problem(@ledger.ProblemKind::Failure),
      ]),
    ],
    [observation(a), observation(b, outcome=@ledger.Outcome::Error)],
    [
      observation(a),
      observation(b, outcome=@ledger.Outcome::Failure, problems=[
        problem(@ledger.ProblemKind::Error),
      ]),
    ],
    [
      observation(a),
      observation(b, outcome=@ledger.Outcome::Skip, problems=[
        problem(@ledger.ProblemKind::Failure),
      ]),
    ],
  ]
  for i, cases in bad_cases {
    let code = rejected(() => ledger.ingest(document("report", 1, cases)))
    assert_eq(
      code,
      if i == 0 {
        "UnexpectedCase"
      } else if i == 1 {
        "DuplicateCase"
      } else {
        "InconsistentOutcome"
      },
    )
    assert_eq(ledger.summary(), empty)
    assert_eq(ledger.source("report"), None)
  }
  ledger.ingest(document("report", 1, [observation(a), observation(b)]))
  assert_true(ledger.summary().complete)
  assert_eq(ledger.summary().exit_code(), 0)
}

///|
test "source and problem budgets reject one over boundary without leaking counters" {
  let a = key("a")
  let b = key("b")
  let limits = {
    ..@ledger.Limits::default(),
    max_cases: 2,
    max_source_units: 2,
    max_total_source_units: 3,
    max_problems: 1,
  }
  let plan = @ledger.RunPlan::new(
    "run-42",
    "commit-a",
    [expected("a", 1, [a], shard="one"), expected("b", 1, [b], shard="two")],
    limits~,
  )
  let ledger = @ledger.Ledger::new(plan, limits~)
  assert_eq(
    rejected(() => {
      ledger.ingest(
        document("a", 1, [observation(a)], shard="one", source="AAA"),
      )
    }),
    "SourceLimit",
  )
  ledger.ingest(document("a", 1, [observation(a)], shard="one", source="AA"))
  let before = ledger.summary()
  assert_eq(
    rejected(() => {
      ledger.ingest(
        document("b", 1, [observation(b)], shard="two", source="BB"),
      )
    }),
    "SourceLimit",
  )
  assert_eq(ledger.summary(), before)
  assert_eq(
    rejected(() => {
      ledger.ingest(
        document(
          "b",
          1,
          [
            observation(b, outcome=@ledger.Outcome::Error, problems=[
              problem(@ledger.ProblemKind::Failure),
              problem(@ledger.ProblemKind::Error),
            ]),
          ],
          shard="two",
          source="B",
        ),
      )
    }),
    "ProblemLimit",
  )
  assert_eq(ledger.summary(), before)
  ledger.ingest(
    document(
      "b",
      1,
      [
        observation(b, outcome=@ledger.Outcome::Error, problems=[
          problem(@ledger.ProblemKind::Error),
        ]),
      ],
      shard="two",
      source="B",
    ),
  )
  assert_true(ledger.summary().complete)
  assert_eq(ledger.source("a"), Some("AA"))
  assert_eq(ledger.source("b"), Some("B"))
  assert_eq(ledger.summary().cases[1].verdict, @ledger.Verdict::Error)
}

///|
test "caller mutations never change accepted plan documents or returned snapshots" {
  let a = key("a")
  let input_cases = [a]
  let input_reports = [expected("report", 1, input_cases)]
  let plan = @ledger.RunPlan::new("run-42", "commit-a", input_reports)
  input_cases.clear()
  input_reports.clear()
  assert_eq(plan.reports[0].cases, [a])
  let ledger = @ledger.Ledger::new(plan)
  plan.reports[0].cases.clear()
  plan.reports.clear()
  let problems = [problem(@ledger.ProblemKind::Failure)]
  let cases = [observation(a, outcome=@ledger.Outcome::Failure, problems~)]
  ledger.ingest(document("report", 1, cases))
  problems.clear()
  cases.clear()
  let first = ledger.summary()
  assert_eq(first.cases[0].attempts[0].observation.problems.length(), 1)
  first.cases[0].attempts[0].observation.problems.clear()
  first.cases[0].attempts.clear()
  first.cases.clear()
  let second = ledger.summary()
  assert_eq(
    second.cases[0].attempts[0].observation.problems[0].text,
    "expected 1\nactual 2",
  )
  assert_eq(second.cases[0].verdict, @ledger.Verdict::Failed)
  assert_true(second.complete)
}

///|
test "identities retain case whitespace and environment scope with canonical output" {
  let a = key("a")
  let upper = key("A")
  let spaced = key(" a")
  let other_class = key("a", classname="suite")
  let reports = [
    expected("windows", 1, [a], environment="windows", shard="z"),
    expected("linux-z", 1, [other_class], shard="z"),
    expected("linux-a", 1, [a, upper, spaced], shard="a"),
  ]
  let plan = @ledger.RunPlan::new("run-42", "commit-a", reports)
  let ledger = @ledger.Ledger::new(plan)
  ledger.ingest(
    document("windows", 1, [observation(a)], environment="windows", shard="z"),
  )
  ledger.ingest(document("linux-z", 1, [observation(other_class)], shard="z"))
  ledger.ingest(
    document(
      "linux-a",
      1,
      [observation(a), observation(upper), observation(spaced)],
      shard="a",
    ),
  )
  assert_eq(
    ledger.summary().cases.map(item => {
      (item.environment, item.shard, item.key.name)
    }),
    [
      ("linux", "a", "A"),
      ("linux", "a", "a"),
      ("linux", "a", " a"),
      ("linux", "z", "a"),
      ("windows", "z", "a"),
    ],
  )
}

///|
test "plans reject ambiguous inventories rather than infer retry or shard ownership" {
  let a = key("a")
  let checks = [
    ([expected("one", 1, [a]), expected("one", 2, [a])], "DuplicateReport"),
    ([expected("one", 1, [a, a])], "DuplicateCase"),
    ([expected("one", 2, [a])], "AttemptSequence"),
    ([expected("one", 1, [a]), expected("three", 3, [a])], "AttemptSequence"),
    ([expected("one", 1, [a]), expected("also-one", 1, [a])], "AttemptSequence"),
    (
      [expected("one", 1, [a]), expected("two", 2, [key("new")])],
      "UnexpectedRetryCase",
    ),
    (
      [
        expected("one", 1, [a], shard="one"),
        expected("two", 1, [a], shard="two"),
      ],
      "AmbiguousShard",
    ),
    ([expected("one", 1, [])], "EmptyInventory"),
    ([expected("one", 1, [key(" \t")])], "InvalidCase"),
    ([expected("one", 1, [key("a", classname="C\u0000")])], "InvalidCase"),
    ([expected("one", 0, [a])], "InvalidReport"),
    ([expected("one", 1, [a], environment="\n")], "InvalidReport"),
  ]
  for (reports, code) in checks {
    assert_eq(
      rejected(() => {
        let _ = @ledger.RunPlan::new("run-42", "commit-a", reports)
      }),
      code,
    )
  }
  assert_eq(
    rejected(() => {
      let _ = @ledger.RunPlan::new("", "commit-a", [expected("one", 1, [a])])
    }),
    "InvalidRun",
  )
  assert_eq(
    rejected(() => {
      let _ = @ledger.RunPlan::new("run-42", "x\u0000", [
        expected("one", 1, [a]),
      ])
    }),
    "InvalidRun",
  )
  // A public record literal cannot bypass the constructor when building a ledger.
  let unchecked : @ledger.RunPlan = {
    run_id: "run-42",
    revision: "commit-a",
    reports: [expected("one", 2, [a])],
  }
  assert_eq(
    rejected(() => {
      let _ = @ledger.Ledger::new(unchecked)
    }),
    "AttemptSequence",
  )
}

///|
test "limits and expected observation caps have exact inclusive boundaries" {
  let defaults = @ledger.Limits::default()
  let exact = { ..defaults, max_reports: 1, max_cases: 1, }
  let a = key("a")
  assert_eq(
    @ledger.RunPlan::new(
      "run-42",
      "commit-a",
      [expected("one", 1, [a])],
      limits=exact,
    ).reports.length(),
    1,
  )
  assert_eq(
    rejected(() => {
      let _ = @ledger.RunPlan::new(
        "run-42",
        "commit-a",
        [expected("one", 1, [a, key("b")])],
        limits=exact,
      )
    }),
    "CaseLimit",
  )
  assert_eq(
    rejected(() => {
      let _ = @ledger.RunPlan::new(
        "run-42",
        "commit-a",
        [expected("one", 1, [a]), expected("two", 2, [a])],
        limits=exact,
      )
    }),
    "ReportLimit",
  )
  for
    limits in [
      { ..defaults, max_reports: 0, },
      { ..defaults, max_reports: 4097, },
      { ..defaults, max_cases: 1000001, },
      { ..defaults, max_source_units: 67108865, },
      { ..defaults, max_total_source_units: 268435457, },
      { ..defaults, max_events: 2000001, },
      { ..defaults, max_depth: 257, },
      { ..defaults, max_attributes: 4097, },
      { ..defaults, max_problems: 1000001, },
    ] {
    assert_eq(rejected(() => limits.validate()), "InvalidLimit")
  }
  let ceiling : @ledger.Limits = {
    max_reports: 4096,
    max_cases: 1000000,
    max_source_units: 67108864,
    max_total_source_units: 268435456,
    max_events: 2000000,
    max_depth: 256,
    max_attributes: 4096,
    max_problems: 1000000,
  }
  ceiling.validate()
}
