///|
fn verdict(attempts : Array[AttemptRecord], missing : Bool) -> Verdict {
  if missing {
    return Incomplete
  }
  guard attempts.last() is Some(last) else { return Incomplete }
  let had_failure = attempts.any(record => {
    record.observation.outcome is (Failure | Error)
  })
  match last.observation.outcome {
    Pass => if had_failure { RecoveredOnRetry } else { Passed }
    Failure => Failed
    Error => Error
    Skip => if had_failure { Unresolved } else { Skipped }
  }
}

///|
fn observation(
  index : Map[String, Map[CaseKey, ObservedCase]],
  report_id : String,
  key : CaseKey,
) -> ObservedCase? {
  match index.get(report_id) {
    None => None
    Some(cases) => cases.get(key)
  }
}

///|
/// Return a fresh evidence snapshot in canonical environment/shard/identity
/// order, regardless of the order documents were ingested.
pub fn Ledger::summary(self : Ledger) -> Summary {
  let missing_reports : Array[String] = []
  let missing_cases : Array[MissingCase] = []
  let index : Map[String, Map[CaseKey, ObservedCase]] = Map([])
  let expected_keys : Map[String, Set[CaseKey]] = Map([])
  for id, document in self.documents {
    let cases : Map[CaseKey, ObservedCase] = Map([])
    for testcase in document.report.cases {
      cases[testcase.key] = testcase
    }
    index[id] = cases
  }
  let groups : Map[(String, String), Array[ExpectedReport]] = Map([])
  for expected in self.plan.reports {
    let group = (expected.environment, expected.shard)
    match groups.get(group) {
      Some(attempts) => attempts.push(expected)
      None => groups[group] = [expected]
    }
    if !self.documents.contains(expected.id) {
      missing_reports.push(expected.id)
    }
    let keys = expected.cases.copy()
    keys.sort()
    let membership : Set[CaseKey] = Set([])
    for key in keys {
      membership.add(key)
      if observation(index, expected.id, key) is None {
        missing_cases.push({ report_id: expected.id, key, })
      }
    }
    expected_keys[expected.id] = membership
  }
  let cases : Array[CaseSummary] = []
  for (environment, shard), expected_attempts in groups {
    let keys = expected_attempts[0].cases.copy()
    keys.sort()
    for key in keys {
      let attempts : Array[AttemptRecord] = []
      let mut missing = false
      for expected in expected_attempts {
        if expected_keys[expected.id].contains(key) {
          match observation(index, expected.id, key) {
            None => missing = true
            Some(testcase) =>
              attempts.push({
                report_id: expected.id,
                attempt: expected.attempt,
                observation: copy_case(testcase),
              })
          }
        }
      }
      cases.push({
        environment,
        shard,
        key,
        verdict: verdict(attempts, missing),
        attempts,
      })
    }
  }
  {
    run_id: self.plan.run_id,
    revision: self.plan.revision,
    complete: missing_reports.is_empty() && missing_cases.is_empty(),
    cases,
    missing_reports,
    missing_cases,
  }
}

///|
/// 0: complete passing/skipped/recovered; 1: failed/unresolved or denied
/// recovery; 3: incomplete inventory. Invalid input is reported separately.
pub fn Summary::exit_code(
  self : Summary,
  deny_recovered~ : Bool = false,
) -> Int32 {
  if !self.complete {
    return 3
  }
  for testcase in self.cases {
    match testcase.verdict {
      Failed | Error | Unresolved => return 1
      Incomplete => return 3
      RecoveredOnRetry if deny_recovered => return 1
      Passed | Skipped | RecoveredOnRetry => ()
    }
  }
  0
}
