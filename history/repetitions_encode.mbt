///|
fn repetition_kind_name(kind : RepetitionKind) -> String {
  match kind {
    MixedOutcomes => "mixed_outcomes"
    FailureObserved => "failure_observed"
    PassObserved => "pass_observed"
    SkipsOnly => "skips_only"
    NoObservations => "no_observations"
  }
}

///|
/// Deterministic derived counts and run references. Full attempt/problem evidence
/// remains available in rows()/summaries(), and original XML through source().
pub fn Repetitions::encode(
  self : Repetitions,
  limits~ : @ledger.Limits = @ledger.Limits::default(),
) -> String raise @ledger.InputError {
  limits.validate()
  let result = Json::object({
    "schema": Json::number(1),
    "kind": Json::string("moontestledger/repetitions"),
    "revision": Json::string(self.summaries[0].revision),
    "complete": Json::boolean(self.complete()),
    "exit_code": Json::number(self.exit_code().to_double()),
    "runs": Json::array(
      self.summaries.mapi((index, summary) => {
        run_json(summary, self.inputs[index].deny_recovered())
      }),
    ),
    "cases": Json::array(
      self.rows.map(row => {
        Json::object({
          "environment": Json::string(row.environment),
          "key": key_json(row.key),
          "kind": Json::string(repetition_kind_name(row.kind)),
          "pass_attempts": Json::number(row.pass_attempts.to_double()),
          "failed_attempts": Json::number(row.failed_attempts.to_double()),
          "error_attempts": Json::number(row.error_attempts.to_double()),
          "skipped_attempts": Json::number(row.skipped_attempts.to_double()),
          "runs_with_pass": Json::number(row.runs_with_pass.to_double()),
          "runs_with_failure": Json::number(row.runs_with_failure.to_double()),
          "recovered_runs": Json::number(row.recovered_runs.to_double()),
          "incomplete_runs": Json::number(row.incomplete_runs.to_double()),
          "samples": Json::array(
            row.samples.map(sample => {
              Json::object({
                "run_id": Json::string(sample.run_id),
                "shard": Json::string(sample.case_summary.shard),
                "verdict": Json::string(
                  verdict_name(sample.case_summary.verdict),
                ),
                "attempts": Json::number(
                  sample.case_summary.attempts.length().to_double(),
                ),
              })
            }),
          ),
        })
      }),
    ),
  }).stringify(indent=2)
  if result.length() > limits.max_source_units {
    raise repetition_error(
      "RepetitionOutputLimit", "/output", "Derived JSON exceeds the configured source budget; output is not truncated",
    )
  }
  result
}
