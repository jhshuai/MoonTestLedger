///|
fn review_key(name : String) -> @ledger.CaseKey {
  { classname: "Payments", name, }
}

///|
fn simple_review_plan(
  run : String,
  cases : Array[@ledger.CaseKey],
) -> @ledger.RunPlan raise {
  @ledger.RunPlan::new(run, "revision-a", [
    { id: "main", environment: "linux", shard: "all", attempt: 1, cases, },
  ])
}

///|
fn review_error(action : () -> Unit raise @ledger.InputError) -> String raise {
  try action() catch {
    @ledger.InputError::Invalid(diagnostic) => diagnostic.code
  } noraise {
    _ => fail("expected review rejection")
  }
}

///|
test "complete inventory review retains all seven kinds and deterministic round trips" {
  let a = review_key("authorize [EUR]")
  let b = review_key("refund")
  let c = review_key("authorize [USD]")
  let d = review_key("health")
  let e = review_key("first")
  let f = review_key("second")
  let before = @ledger.RunPlan::new("ci-before", "a", [
    { id: "r", environment: "linux", shard: "main", attempt: 1, cases: [a, b], },
    { id: "gone", environment: "linux", shard: "old", attempt: 1, cases: [c], },
    {
      id: "binding",
      environment: "node20",
      shard: "smoke",
      attempt: 1,
      cases: [d],
    },
    {
      id: "ordered",
      environment: "linux",
      shard: "ordered",
      attempt: 1,
      cases: [e, f],
    },
  ])
  let proposed = @ledger.RunPlan::new("ci-after", "b", [
    { id: "r", environment: "linux", shard: "main", attempt: 1, cases: [a, c], },
    {
      id: "binding",
      environment: "node22",
      shard: "smoke",
      attempt: 1,
      cases: [d],
    },
    {
      id: "ordered",
      environment: "linux",
      shard: "ordered",
      attempt: 1,
      cases: [f, e],
    },
    {
      id: "added",
      environment: "windows",
      shard: "main",
      attempt: 1,
      cases: [a],
    },
  ])
  let review = @wire.review_plan(before, proposed)
  assert_eq(review.changes().length(), 7)
  assert_eq(review.changes().map(change => change.kind), [
    @wire.PlanChangeKind::RunMetadataChanged,
    ReportAdded,
    ReportBindingChanged,
    ReportRemoved,
    CaseOrderChanged,
    CaseAdded,
    CaseRemoved,
  ])
  for
    kind in [
      @wire.PlanChangeKind::RunMetadataChanged,
      ReportAdded,
      ReportRemoved,
      ReportBindingChanged,
      CaseAdded,
      CaseRemoved,
      CaseOrderChanged,
    ] {
    assert_eq(
      review.changes().iter().filter(change => change.kind == kind).count(),
      1,
    )
  }
  let encoded = review.encode()
  assert_eq(@wire.decode_plan_review(encoded).encode(), encoded)
  assert_eq(@wire.review_plan(before, proposed).encode(), encoded)
  assert_eq(review.token().length(), 64)
  assert_eq(review.approve(before, approval=review.token()), proposed)
  let reordered = { ..proposed, reports: proposed.reports.rev(), }
  assert_eq(@wire.review_plan(before, reordered).encode(), encoded)
  assert_eq(@wire.review_plan(before, before).changes().length(), 0)
}

///|
test "approval requires exact token unchanged baseline fresh run and preserves old evidence" {
  let a = review_key("fails")
  let b = review_key("passes")
  let before = simple_review_plan("old-run", [a, b])
  let proposed = simple_review_plan("next-run", [b])
  let review = @wire.review_plan(before, proposed)
  assert_eq(
    review_error(() => ignore(review.approve(before, approval=""))),
    "ReviewApproval",
  )
  let stale = { ..before, revision: "changed-after-review", }
  assert_eq(
    review_error(() => ignore(review.approve(stale, approval=review.token()))),
    "ReviewStale",
  )
  let reuse = @wire.review_plan(before, { ..proposed, run_id: before.run_id, })
  assert_eq(
    review_error(() => ignore(reuse.approve(before, approval=reuse.token()))),
    "ReviewRunReuse",
  )
  let approved = review.approve(before, approval=review.token())
  assert_eq(approved, proposed)
  for
    source in [
      "<testsuite tests='2'><testcase classname='Payments' name='fails'><failure>original failure</failure></testcase><testcase classname='Payments' name='passes'/></testsuite>",
      "<testsuite tests='1'><testcase classname='Payments' name='fails'><failure>original failure</failure></testcase></testsuite>",
    ] {
    let ledger = @ledger.Ledger::new(before)
    ledger.ingest({
      binding: {
        id: "main",
        run_id: "old-run",
        revision: "revision-a",
        environment: "linux",
        shard: "all",
        attempt: 1,
      },
      report: @junit.parse(source),
    })
    let evidence = @wire.decode_evidence(@wire.encode_evidence(ledger))
    let old = evidence.encode()
    let gate = evidence.exit_code()
    assert_true(gate == 1 || gate == 3)
    ignore(review.approve(before, approval=review.token()))
    assert_eq(evidence.encode(), old)
    assert_eq(evidence.exit_code(), gate)
    assert_eq(evidence.source("main"), Some(source))
  }
}

///|
test "review owns inputs getters changes and approved outputs" {
  let before = simple_review_plan("before", [review_key("a")])
  let proposed = simple_review_plan("after", [review_key("a"), review_key("b")])
  let review = @wire.review_plan(before, proposed)
  let original = review.encode()
  before.reports[0].cases.clear()
  proposed.reports.clear()
  review.before().reports.clear()
  review.proposed().reports[0].cases.clear()
  review.changes().clear()
  let approved = review.approve(review.before(), approval=review.token())
  approved.reports.clear()
  assert_eq(review.encode(), original)
  assert_eq(@wire.decode_plan_review(original).encode(), original)
}

///|
test "review output limits are inclusive and inputs still validate" {
  let before = simple_review_plan("before", [review_key("a")])
  let after = simple_review_plan("after", [review_key("a"), review_key("b")])
  let review = @wire.review_plan(before, after)
  let source = review.encode()
  let exact = {
    ..@ledger.Limits::default(),
    max_source_units: source.length(),
  }
  let short = { ..exact, max_source_units: source.length() - 1, }
  assert_eq(review.encode(limits=exact), source)
  assert_eq(
    @wire.review_plan(before, after, limits=exact).encode(limits=exact),
    source,
  )
  assert_eq(@wire.decode_plan_review(source, limits=exact).encode(), source)
  assert_eq(
    review_error(() => ignore(review.encode(limits=short))),
    "ReviewLimit",
  )
  assert_eq(
    review_error(() => ignore(@wire.review_plan(before, after, limits=short))),
    "ReviewLimit",
  )
  assert_eq(
    review_error(() => {
      ignore(
        review.approve(before, approval=review.token(), limits={
          ..exact,
          max_cases: 1,
        }),
      )
    }),
    "CaseLimit",
  )
  assert_eq(
    review_error(() => {
      ignore(@wire.review_plan({ ..before, reports: [], }, after))
    }),
    "ReportLimit",
  )
  let invalid_attempt = {
    ..after,
    reports: [{ ..after.reports[0], attempt: 2, }],
  }
  assert_eq(
    review_error(() => ignore(@wire.review_plan(before, invalid_attempt))),
    "AttemptSequence",
  )
  ignore(
    review_error(() => ignore(@wire.decode_plan_review(source, limits=short))),
  )
}

///|
test "review refuses edited hashes projections unknown fields duplicate keys then recovers" {
  let before = simple_review_plan("before", [review_key("参数 [空]")])
  let after = simple_review_plan("after", [
    review_key("参数 [空]"),
    review_key("参数 [满]"),
  ])
  let original = @wire.review_plan(before, after).encode()
  for
    invalid in [
      original.replace(old="\"schema\": 1,", new="\"schema\": 2,"),
      original.replace(
        old="\"schema\": 1,",
        new="\"schema\": 1, \"future\": true,",
      ),
      original.replace(
        old="\"kind\": \"moontestledger/plan-review\"",
        new="\"kind\": \"moontestledger/plan-review\", \"kind\": \"moontestledger/plan-review\"",
      ),
      original.replace(old="\"case_added\"", new="\"case_removed\""),
      original.replace(
        old="\"run_id\":",
        new="\"undeclared\": true, \"run_id\":",
      ),
      original.replace(
        old="\"attempt\": 1,",
        new="\"attempt\": 1.00000000000000001,",
      ),
      original.replace(
        old="\"before_sha256\": \"",
        new="\"before_sha256\": \"changed",
      ),
      original.replace(
        old="\"review_sha256\": \"",
        new="\"review_sha256\": \"changed",
      ),
      original[:original.length() - 1].to_owned(),
    ] {
    ignore(review_error(() => ignore(@wire.decode_plan_review(invalid))))
    assert_eq(@wire.decode_plan_review(original).encode(), original)
  }
}

///|
test "inventory additions and removals keep exact identities over varied sizes" {
  for count in 1..<=10 {
    let keys = Array::makei(count, i => review_key("case-\{i}"))
    let next = keys[1:].to_owned()
    next.push(review_key("参数 [新]"))
    let before = simple_review_plan("before", keys)
    let after = simple_review_plan("after", next)
    let review = @wire.review_plan(before, after)
    assert_eq(review.changes().length(), 3)
    assert_true(
      review
      .changes()
      .contains({
        kind: @wire.PlanChangeKind::CaseRemoved,
        report_id: "main",
        key: Some(keys[0]),
      }),
    )
    assert_true(
      review
      .changes()
      .contains({
        kind: @wire.PlanChangeKind::CaseAdded,
        report_id: "main",
        key: Some(review_key("参数 [新]")),
      }),
    )
    assert_eq(
      @wire.decode_plan_review(review.encode()).approve(
        before,
        approval=review.token(),
      ),
      after,
    )
  }
}
