///|
fn canonical_plan(plan : @ledger.RunPlan) -> @ledger.RunPlan {
  let reports = plan.reports.map(report => {
    let cases = report.cases.copy()
    cases.sort()
    { ..report, cases, }
  })
  { ..plan, reports, }
}

///|
/// Combine partial archives of one run with the same full inventory and policy.
/// Identical documents are idempotent; conflicting replacements are refused.
/// Inputs are never modified. Inventory order is normalized for deterministic output.
pub fn merge_evidence(
  inputs : ArrayView[Evidence],
  limits~ : @ledger.Limits = @ledger.Limits::default(),
) -> Evidence raise @ledger.InputError {
  limits.validate()
  guard inputs.length() > 0 else {
    raise bad("EmptyMerge", "/inputs", "Supply at least one evidence archive")
  }
  if inputs.length() > limits.max_reports {
    raise bad(
      "MergeLimit", "/inputs", "Archive count exceeds the report budget",
    )
  }
  let plan = canonical_plan(inputs[0].ledger.snapshot().plan)
  let deny_recovered = inputs[0].deny_recovered
  let ledger = @ledger.Ledger::new(plan, limits~)
  for index, input in inputs {
    let snapshot = input.ledger.snapshot()
    if canonical_plan(snapshot.plan) != plan {
      raise bad(
        "MergePlanMismatch",
        "/inputs/\{index}/plan",
        "Archives must have the same run, revision and full report/testcase inventory; plans are never unioned",
      )
    }
    if input.deny_recovered != deny_recovered {
      raise bad(
        "MergePolicyMismatch",
        "/inputs/\{index}/deny_recovered",
        "Archives must use the same recovery policy",
      )
    }
    for document in snapshot.documents {
      ledger.ingest(document)
    }
  }
  { ledger, deny_recovered, }
}
