///|
fn initial_evidence(
  two_groups~ : Bool = false,
  deny~ : Bool = false,
  passed~ : Bool = false,
) -> @wire.Evidence raise {
  let keys : Array[@ledger.CaseKey] = ["bad", "boom", "good", "skip"].map(name => {
    classname: "C",
    name,
  })
  let reports : Array[@ledger.ExpectedReport] = [
    {
      id: "initial",
      environment: "linux",
      shard: "one",
      attempt: 1,
      cases: keys,
    },
  ]
  if two_groups {
    reports.push({
      id: "windows",
      environment: "windows",
      shard: "two",
      attempt: 1,
      cases: keys,
    })
  }
  let plan = @ledger.RunPlan::new("run", "rev", reports)
  let ledger = @ledger.Ledger::new(plan)
  let source = if passed {
    "<testsuite><testcase classname='C' name='bad'/><testcase classname='C' name='boom'/><testcase classname='C' name='good'/><testcase classname='C' name='skip'><skipped message='disabled'/></testcase></testsuite>"
  } else {
    "<testsuite><testcase classname='C' name='bad'><failure>original failure</failure></testcase><testcase classname='C' name='boom'><error>original error</error></testcase><testcase classname='C' name='good'/><testcase classname='C' name='skip'><skipped message='disabled'/></testcase></testsuite>"
  }
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
      report: @junit.parse(source),
    })
  }
  @wire.decode_evidence(@wire.encode_evidence(ledger, deny_recovered=deny))
}

///|
fn retry_request(
  id~ : String = "next",
  environment~ : String = "linux",
  shard~ : String = "one",
) -> @wire.RetryReport {
  { id, environment, shard, }
}

///|
fn continuation_error(
  evidence : @wire.Evidence,
  reports : Array[@wire.RetryReport],
  limits~ : @ledger.Limits = @ledger.Limits::default(),
) -> String {
  try {
    ignore(@wire.prepare_retry(evidence, reports[:], limits~))
    "accepted"
  } catch {
    @ledger.InputError::Invalid(d) => d.code
  }
}

///|
fn incoming(
  next : @wire.Evidence,
  source : String,
  id~ : String = "next",
) -> @ledger.Document raise {
  let report = next.snapshot().plan.reports
    .iter()
    .find_first(report => report.id == id)
    .unwrap()
  {
    binding: {
      id,
      run_id: "run",
      revision: "rev",
      environment: report.environment,
      shard: report.shard,
      attempt: report.attempt,
    },
    report: @junit.parse(source),
  }
}

///|
test "selective retry retains all old evidence inventory policy and expected next ordinal" {
  for deny in [false, true] {
    let original = initial_evidence(deny~)
    let before = original.encode()
    let next = @wire.prepare_retry(original, [retry_request()][:])
    assert_eq(next.exit_code(), 3)
    assert_eq(next.deny_recovered(), deny)
    assert_eq(next.source("initial"), original.source("initial"))
    let snapshot = next.snapshot()
    assert_eq(snapshot.plan.reports.length(), 2)
    assert_eq(snapshot.plan.reports[1].cases.map(key => key.name), [
      "bad", "boom",
    ])
    assert_eq(snapshot.plan.reports[1].attempt, 2)
    let source = "<testsuite><testcase classname='C' name='bad'/><testcase classname='C' name='boom'/></testsuite>"
    let document = incoming(next, source)
    let done = next.ingest_reports([document][:])
    assert_eq(done.exit_code(), if deny { 1 } else { 0 })
    assert_eq(
      done.summary().cases
      .filter(item => item.verdict == @ledger.Verdict::RecoveredOnRetry)
      .length(),
      2,
    )
    assert_eq(
      done.summary().cases[0].attempts[0].observation.problems[0].text,
      "original failure",
    )
    assert_eq(
      done.ingest_reports([document, document][:]).encode(),
      done.encode(),
    )
    assert_eq(@wire.decode_evidence(done.encode()).summary(), done.summary())
    assert_eq(original.encode(), before)
    assert_eq(next.exit_code(), 3)
    assert_eq(
      continuation_error(done, [retry_request(id="third")]),
      "NoRetryCases",
    )
  }
}

///|
test "retry selection is deterministic across groups and refuses missing extra duplicate or reused identities" {
  let original = initial_evidence(two_groups=true)
  let linux = retry_request()
  let windows = retry_request(id="win-next", environment="windows", shard="two")
  assert_eq(
    @wire.prepare_retry(original, [linux, windows][:]).encode(),
    @wire.prepare_retry(original, [windows, linux][:]).encode(),
  )
  assert_eq(continuation_error(original, [linux]), "MissingRetryGroup")
  assert_eq(continuation_error(original, [linux, linux]), "DuplicateRetryGroup")
  assert_eq(
    continuation_error(original, [retry_request(environment="unknown")]),
    "UnexpectedRetryGroup",
  )
  assert_eq(
    continuation_error(original, [retry_request(id="initial"), windows]),
    "DuplicateReport",
  )
  assert_eq(
    continuation_error(original, [retry_request(id=""), windows]),
    "InvalidReport",
  )
  assert_eq(
    continuation_error(
      @wire.decode_evidence(@wire.encode_evidence(archive_ledger(missing=true))),
      [linux],
    ),
    "RetryIncomplete",
  )
  assert_eq(
    continuation_error(initial_evidence(passed=true), [linux]),
    "NoRetryCases",
  )
  assert_eq(original.exit_code(), 1)
}

///|
test "unresolved skip after failure schedules the third attempt" {
  let snapshot = archive_ledger().snapshot()
  let ledger = @ledger.Ledger::new(snapshot.plan)
  ledger.ingest(snapshot.documents[0])
  ledger.ingest({
    ..snapshot.documents[1],
    report: @junit.parse(
      "<testsuite><testcase classname='C' name='a'><skipped/></testcase></testsuite>",
    ),
  })
  let evidence = @wire.decode_evidence(@wire.encode_evidence(ledger))
  assert_eq(evidence.summary().cases[0].verdict, @ledger.Verdict::Unresolved)
  let next = @wire.prepare_retry(evidence, [retry_request(id="third")][:])
  assert_eq(next.snapshot().plan.reports[2].attempt, 3)
  assert_eq(next.snapshot().plan.reports[2].cases, [
    { classname: "C", name: "a", },
  ])
}

///|
test "append rejects projections conflicts unexpected cases and batches atomically then recovers" {
  let original = initial_evidence()
  let next = @wire.prepare_retry(original, [retry_request()][:])
  let text = next.encode()
  let valid = incoming(
    next, "<testsuite><testcase classname='C' name='bad'/><testcase classname='C' name='boom'/></testsuite>",
  )
  let conflict = incoming(next, valid.report.source + "\n")
  let forged = {
    ..valid,
    report: {
      ..valid.report,
      cases: valid.report.cases.map(item => { ..item, path: "forged", }),
    },
  }
  let extra = incoming(
    next, "<testsuite><testcase classname='C' name='bad'/><testcase classname='C' name='boom'/><testcase classname='C' name='good'/></testsuite>",
  )
  let wrong_revision = {
    ..valid,
    binding: { ..valid.binding, revision: "other", },
  }
  for
    (documents, expected) in [
      ([valid, conflict], "ConflictingReport"),
      ([forged], "ProjectionMismatch"),
      ([extra], "UnexpectedCase"),
      ([wrong_revision], "BindingMismatch"),
    ] {
    let code = try {
      ignore(next.ingest_reports(documents[:]))
      "accepted"
    } catch {
      @ledger.InputError::Invalid(d) => d.code
    }
    assert_eq(code, expected)
    assert_eq(next.encode(), text)
  }
  assert_eq(next.ingest_reports([valid][:]).exit_code(), 0)
  let partial = incoming(
    next, "<testsuite><testcase classname='C' name='bad'/></testsuite>",
  )
  assert_eq(next.ingest_reports([partial][:]).exit_code(), 3)
}

///|
test "retry and append enforce inclusive inventory and combined source budgets" {
  let original = initial_evidence()
  let limits = { ..@ledger.Limits::default(), max_reports: 2, max_cases: 6, }
  let next = @wire.prepare_retry(original, [retry_request()][:], limits~)
  assert_eq(
    continuation_error(original, [retry_request()], limits={
      ..limits,
      max_reports: 1,
    }),
    "ReportLimit",
  )
  assert_eq(
    continuation_error(original, [retry_request()], limits={
      ..limits,
      max_cases: 5,
    }),
    "CaseLimit",
  )
  let valid = incoming(
    next, "<testsuite><testcase classname='C' name='bad'/><testcase classname='C' name='boom'/></testsuite>",
  )
  let units = original.source("initial").unwrap().length() +
    valid.report.source.length()
  assert_eq(
    next
    .ingest_reports([valid][:], limits={
      ..limits,
      max_total_source_units: units,
    })
    .exit_code(),
    0,
  )
  let code = try {
    ignore(
      next.ingest_reports([valid][:], limits={
        ..limits,
        max_total_source_units: units - 1,
      }),
    )
    "accepted"
  } catch {
    @ledger.InputError::Invalid(d) => d.code
  }
  assert_eq(code, "SourceLimit")
}

///|
test "retry manifest round trips all fields and rejects unsupported JSON without changing state" {
  let reports = [
    retry_request(),
    retry_request(id="win", environment="win", shard="two"),
  ]
  let text = @wire.encode_retry_reports(reports[:])
  assert_eq(@wire.decode_retry_reports(text), reports)
  assert_eq(
    @wire.encode_retry_reports(@wire.decode_retry_reports(text)[:]),
    text,
  )
  for
    source in [
      "{\"schema\":2,\"reports\":[]}", "{\"schema\":1,\"schema\":1,\"reports\":[]}",
      "{\"schema\":1,\"reports\":[{\"id\":\"x\",\"environment\":\"linux\",\"shard\":\"one\",\"attempt\":2}]}",
    ] {
    let accepted = try {
      ignore(@wire.decode_retry_reports(source))
      true
    } catch {
      @ledger.InputError::Invalid(_) => false
    }
    assert_false(accepted)
  }
  assert_eq(@wire.decode_retry_reports(text), reports)
}
