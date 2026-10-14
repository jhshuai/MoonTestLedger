///|
fn verdict_name(verdict : @ledger.Verdict) -> String {
  match verdict {
    Passed => "passed"
    Failed => "failed"
    Error => "error"
    Skipped => "skipped"
    RecoveredOnRetry => "recovered_on_retry"
    Unresolved => "unresolved"
    Incomplete => "incomplete"
  }
}

///|
fn case_json(item : @ledger.CaseSummary?) -> Json {
  match item {
    None => Json::null()
    Some(item) =>
      Json::object({
        "shard": Json::string(item.shard),
        "verdict": Json::string(verdict_name(item.verdict)),
      })
  }
}

///|
fn key_json(key : @ledger.CaseKey) -> Json {
  Json::object({
    "classname": Json::string(key.classname),
    "name": Json::string(key.name),
  })
}

///|
fn run_json(summary : @ledger.Summary, policy : Bool) -> Json {
  Json::object({
    "run_id": Json::string(summary.run_id),
    "revision": Json::string(summary.revision),
    "complete": Json::boolean(summary.complete),
    "deny_recovered": Json::boolean(policy),
    "missing_reports": Json::array(summary.missing_reports.map(Json::string)),
    "missing_cases": Json::array(
      summary.missing_cases.map(item => {
        Json::object({
          "report_id": Json::string(item.report_id),
          "key": key_json(item.key),
        })
      }),
    ),
  })
}

///|
/// A derived status-difference view. Full raw source stays in the archives;
/// changes(), before() and after() retain full attempts and diagnostics.
pub fn Comparison::encode(self : Comparison) -> String {
  Json::object({
    "schema": Json::number(1),
    "kind": Json::string("moontestledger/comparison"),
    "before": run_json(self.before, self.before_policy),
    "after": run_json(self.after, self.after_policy),
    "comparable": Json::boolean(self.comparable),
    "policy_changed": Json::boolean(self.policy_changed()),
    "exit_code": Json::number(self.exit_code().to_double()),
    "changes": Json::array(
      self.changes.map(change => {
        Json::object({
          "environment": Json::string(change.environment),
          "key": key_json(change.key),
          "kind": Json::string(
            match change.kind {
              Added => "added"
              Removed => "removed"
              Regressed => "regressed"
              Improved => "improved"
              Changed => "changed"
              Unchanged => "unchanged"
              Unknown => "unknown"
            },
          ),
          "before": case_json(change.before),
          "after": case_json(change.after),
        })
      }),
    ),
  }).stringify(indent=2)
}
