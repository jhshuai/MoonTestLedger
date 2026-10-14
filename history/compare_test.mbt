///|
fn evidence(
  values : Array[(String, String)],
  run~ : String = "run",
  revision~ : String = "rev",
  shard~ : String = "all",
  environment~ : String = "linux",
  missing~ : Bool = false,
  deny~ : Bool = false,
) -> @wire.Evidence raise {
  let plan = @ledger.RunPlan::new(run, revision, [
    {
      id: "report",
      environment,
      shard,
      attempt: 1,
      cases: values.map(pair => { classname: "C", name: pair.0, }),
    },
  ])
  let ledger = @ledger.Ledger::new(plan)
  if !missing {
    let body = values
      .map(pair => {
        "<testcase classname='C' name='" +
        pair.0 +
        "'>" +
        pair.1 +
        "</testcase>"
      })
      .join("")
    ledger.ingest({
      binding: {
        id: "report",
        run_id: run,
        revision,
        environment,
        shard,
        attempt: 1,
      },
      report: @junit.parse("<testsuite>" + body + "</testsuite>"),
    })
  }
  @wire.decode_evidence(@wire.encode_evidence(ledger, deny_recovered=deny))
}

///|
fn recovered(last~ : String = "") -> @wire.Evidence raise {
  let plan = @ledger.RunPlan::new("retry-run", "rev", [
    {
      id: "first",
      environment: "linux",
      shard: "all",
      attempt: 1,
      cases: [{ classname: "C", name: "a", }],
    },
    {
      id: "retry",
      environment: "linux",
      shard: "all",
      attempt: 2,
      cases: [{ classname: "C", name: "a", }],
    },
  ])
  let ledger = @ledger.Ledger::new(plan)
  for i, id in ["first", "retry"] {
    let body = if i == 0 { "<failure>prior evidence</failure>" } else { last }
    ledger.ingest({
      binding: {
        id,
        run_id: "retry-run",
        revision: "rev",
        environment: "linux",
        shard: "all",
        attempt: i + 1,
      },
      report: @junit.parse(
        "<testsuite><testcase classname='C' name='a'>" +
        body +
        "</testcase></testsuite>",
      ),
    })
  }
  @wire.decode_evidence(@wire.encode_evidence(ledger))
}

///|
test "comparison distinguishes regressions improvements and failure followed by skip" {
  let before = evidence(
    [
      ("a", ""),
      ("b", "<failure>trace</failure>"),
      ("c", "<error>timeout</error>"),
    ],
    run="baseline",
    revision="old",
  )
  let after = evidence(
    [("c", "<skipped/>"), ("b", ""), ("a", "<error>new failure</error>")],
    run="current",
    revision="new",
  )
  let comparison = @history.compare_evidence(before, after)
  assert_true(comparison.comparable())
  assert_eq(comparison.changes().map(change => change.kind), [
    @history.ChangeKind::Regressed,
    @history.ChangeKind::Improved,
    @history.ChangeKind::Changed,
  ])
  assert_eq(comparison.exit_code(), 1)
  assert_eq(comparison.before().revision, "old")
  assert_eq(comparison.after().revision, "new")
  assert_eq(
    comparison.changes()[1].before.unwrap().attempts[0].observation.problems[0].text,
    "trace",
  )
}

///|
test "retry instability is a regression from passing and final failure worsens recovery" {
  let pass = evidence([("a", "")])
  let retry = recovered()
  let fail = evidence([("a", "<failure/>")])
  assert_eq(
    @history.compare_evidence(pass, retry).changes()[0].kind,
    @history.ChangeKind::Regressed,
  )
  assert_eq(@history.compare_evidence(pass, retry).exit_code(), 1)
  assert_eq(@history.compare_evidence(retry, fail).exit_code(), 1)
  assert_eq(
    @history.compare_evidence(fail, retry).changes()[0].kind,
    @history.ChangeKind::Improved,
  )
  assert_eq(@history.compare_evidence(retry, pass).exit_code(), 0)
  assert_eq(
    @history.compare_evidence(retry, retry).changes()[0].before.unwrap().attempts.length(),
    2,
  )
}

///|
test "added adverse tests fail while removals are inconclusive rather than improvements" {
  let baseline = evidence([("a", "")])
  assert_eq(
    @history.compare_evidence(baseline, evidence([("a", ""), ("b", "")])).exit_code(),
    0,
  )
  let added = @history.compare_evidence(
    baseline,
    evidence([("a", ""), ("b", "<failure/>")]),
  )
  assert_eq(added.changes()[1].kind, @history.ChangeKind::Added)
  assert_eq(added.exit_code(), 1)
  let removed = @history.compare_evidence(
    evidence([("a", ""), ("b", "<failure/>")]),
    baseline,
  )
  assert_eq(removed.changes()[1].kind, @history.ChangeKind::Removed)
  assert_false(removed.comparable())
  assert_eq(removed.exit_code(), 3)
}

///|
test "missing evidence and changed policy cannot produce a successful comparative gate" {
  let baseline = evidence([("a", "")])
  let absent = evidence([("a", "")], missing=true)
  for
    comparison in [
      @history.compare_evidence(baseline, absent),
      @history.compare_evidence(absent, baseline),
    ] {
    assert_eq(comparison.changes()[0].kind, @history.ChangeKind::Unknown)
    assert_eq(comparison.exit_code(), 3)
  }
  let changed_policy = @history.compare_evidence(
    baseline,
    evidence([("a", "")], deny=true),
  )
  assert_true(changed_policy.policy_changed())
  assert_eq(changed_policy.exit_code(), 3)
}

///|
test "shard moves retain identity but distinct environments never merge" {
  let baseline = evidence([("a", "")])
  let moved = @history.compare_evidence(
    baseline,
    evidence([("a", "")], shard="new-shard"),
  )
  assert_eq(moved.changes().length(), 1)
  assert_eq(moved.changes()[0].kind, @history.ChangeKind::Changed)
  assert_eq(moved.exit_code(), 0)
  let renamed = @history.compare_evidence(
    baseline,
    evidence([("a", "")], environment="windows"),
  )
  assert_eq(renamed.changes().length(), 2)
  assert_eq(renamed.exit_code(), 3)
}

///|
test "comparison output is deterministic and returned arrays cannot mutate evidence" {
  let before = evidence([("bb", "<failure>kept</failure>"), ("a", "")])
  let after = evidence([("a", ""), ("bb", "")])
  let result = @history.compare_evidence(before, after)
  let permuted = @history.compare_evidence(
    evidence([("a", ""), ("bb", "<failure>kept</failure>")]),
    evidence([("bb", ""), ("a", "")]),
  )
  assert_eq(result.encode(), permuted.encode())
  let source = result.encode()
  let changes = result.changes()
  changes[1].before.unwrap().attempts[0].observation.problems.clear()
  changes.clear()
  result.before().cases.clear()
  assert_eq(result.encode(), source)
  assert_eq(
    before.summary().cases[1].attempts[0].observation.problems[0].text,
    "kept",
  )
  assert_eq(result.exit_code(), 0)
}

///|
test "unchanged failure remains failing in verify but is not a new regression" {
  let existing = evidence([("a", "<failure/>")])
  let comparison = @history.compare_evidence(existing, existing)
  assert_eq(comparison.exit_code(), 0)
  assert_eq(existing.exit_code(), 1)
  assert_eq(comparison.changes()[0].kind, @history.ChangeKind::Unchanged)
}

///|
test "inconclusive inventory outranks a simultaneous regression and unresolved history is retained" {
  let before = evidence([("a", ""), ("b", "")])
  let after = evidence([("a", "<failure/>")])
  let result = @history.compare_evidence(before, after)
  assert_eq(result.changes()[0].kind, @history.ChangeKind::Regressed)
  assert_eq(result.changes()[1].kind, @history.ChangeKind::Removed)
  assert_eq(result.exit_code(), 3)
  let unresolved = recovered(last="<skipped message='offline'/>")
  assert_eq(unresolved.summary().cases[0].verdict, @ledger.Verdict::Unresolved)
  let skip = evidence([("a", "<skipped/>")])
  assert_eq(
    @history.compare_evidence(unresolved, skip).changes()[0].kind,
    @history.ChangeKind::Changed,
  )
  let improved = @history.compare_evidence(unresolved, evidence([("a", "")]))
  assert_eq(improved.changes()[0].kind, @history.ChangeKind::Improved)
  assert_eq(
    improved.changes()[0].before.unwrap().attempts[1].observation.skipped_reason,
    Some("offline"),
  )
}
