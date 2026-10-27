///|
test "facade exposes an owned review with checked approval for future inventory" {
  let before = @moontestledger.RunPlan::new("before", "r1", [
    {
      id: "main",
      environment: "linux",
      shard: "all",
      attempt: 1,
      cases: [{ classname: "Api", name: "existing", }],
    },
  ])
  let proposed = { ..before, run_id: "next", revision: "r2", }
  let review : @moontestledger.PlanReview = @moontestledger.review_plan(
    before, proposed,
  )
  assert_eq(
    @moontestledger.decode_plan_review(review.encode()).approve(
      before,
      approval=review.token(),
    ),
    proposed,
  )
  assert_eq(
    review.changes()[0].kind,
    @moontestledger.PlanChangeKind::RunMetadataChanged,
  )
}

///|
test "downstream facade integrates a declared report and retains original input" {
  let key : @moontestledger.CaseKey = {
    classname: "Checkout",
    name: "commits order [EUR]",
  }
  let plan = @moontestledger.RunPlan::new("ci-42", "revision-abc", [
    {
      id: "linux-1",
      environment: "linux",
      shard: "orders",
      attempt: 1,
      cases: [key],
    },
  ])
  let ledger = @moontestledger.Ledger::new(plan)
  assert_eq(ledger.summary().exit_code(), 3)
  let source = "<testsuite tests='1'><testcase classname='Checkout' name='commits order [EUR]'/></testsuite>"
  ledger.ingest({
    binding: {
      id: "linux-1",
      run_id: "ci-42",
      revision: "revision-abc",
      environment: "linux",
      shard: "orders",
      attempt: 1,
    },
    report: @moontestledger.parse_junit(source, report_id="linux-1"),
  })
  let summary = ledger.summary()
  assert_true(summary.complete)
  assert_eq(summary.cases[0].verdict, @moontestledger.Verdict::Passed)
  assert_eq(summary.exit_code(), 0)
  assert_eq(ledger.source("linux-1"), Some(source))
  assert_eq(
    @moontestledger.decode_plan(@moontestledger.encode_plan(plan)),
    plan,
  )
}
