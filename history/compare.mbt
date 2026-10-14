///|
fn severity(verdict : @ledger.Verdict) -> Int32 {
  match verdict {
    Failed | Error | Unresolved => 2
    RecoveredOnRetry => 1
    Passed | Skipped | Incomplete => 0
  }
}

///|
fn classify(
  before : @ledger.CaseSummary?,
  after : @ledger.CaseSummary?,
) -> ChangeKind {
  match (before, after) {
    (None, Some(_)) => Added
    (Some(_), None) => Removed
    (Some(before), Some(after)) => {
      if before.verdict == @ledger.Verdict::Incomplete ||
        after.verdict == @ledger.Verdict::Incomplete {
        return Unknown
      }
      if severity(after.verdict) > severity(before.verdict) {
        return Regressed
      }
      if severity(before.verdict) > 0 &&
        (
          after.verdict == @ledger.Verdict::Passed ||
          (
            severity(before.verdict) == 2 &&
            after.verdict == @ledger.Verdict::RecoveredOnRetry
          )
        ) {
        return Improved
      }
      if before.verdict == after.verdict && before.shard == after.shard {
        Unchanged
      } else {
        Changed
      }
    }
    (None, None) => Unknown
  }
}

///|
/// Compare validated, separate runs. Environment and exact case identity match;
/// shard placement can change. Missing evidence, removed inventory or a changed
/// recovery policy prevents a conclusive regression gate.
pub fn compare_evidence(
  before : @wire.Evidence,
  after : @wire.Evidence,
) -> Comparison {
  let baseline = before.summary()
  let current = after.summary()
  let left : Map[(String, @ledger.CaseKey), @ledger.CaseSummary] = Map([])
  let right : Map[(String, @ledger.CaseKey), @ledger.CaseSummary] = Map([])
  let identities : Set[(String, @ledger.CaseKey)] = Set([])
  for item in baseline.cases {
    left[(item.environment, item.key)] = item
    identities.add((item.environment, item.key))
  }
  for item in current.cases {
    right[(item.environment, item.key)] = item
    identities.add((item.environment, item.key))
  }
  let ordered = identities.to_array()
  ordered.sort()
  let changes : Array[Change] = []
  let mut comparable = baseline.complete &&
    current.complete &&
    before.deny_recovered() == after.deny_recovered()
  for (environment, key) in ordered {
    let previous = left.get((environment, key))
    let next = right.get((environment, key))
    let kind = classify(previous, next)
    if kind == Removed {
      comparable = false
    }
    changes.push({ environment, key, kind, before: previous, after: next, })
  }
  {
    before: baseline,
    after: current,
    before_policy: before.deny_recovered(),
    after_policy: after.deny_recovered(),
    comparable,
    changes,
  }
}

///|
/// 3: inconclusive; 1: new adverse result (including retry instability); 0:
/// no new adverse result. Existing failures still fail the separate verify gate.
pub fn Comparison::exit_code(self : Comparison) -> Int32 {
  if !self.comparable {
    return 3
  }
  for change in self.changes {
    if change.kind == Regressed {
      return 1
    }
    if change.kind == Added &&
      change.after is Some(item) &&
      severity(item.verdict) > 0 {
      return 1
    }
  }
  0
}
