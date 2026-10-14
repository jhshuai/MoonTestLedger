///|
fn key_json(key : @ledger.CaseKey) -> Json {
  Json::object({
    "classname": Json::string(key.classname),
    "name": Json::string(key.name),
  })
}

///|
fn plan_json(plan : @ledger.RunPlan) -> Json {
  let reports = plan.reports.map(report => {
    Json::object({
      "id": Json::string(report.id),
      "environment": Json::string(report.environment),
      "shard": Json::string(report.shard),
      "attempt": Json::number(report.attempt.to_double()),
      "cases": Json::array(report.cases.map(key_json)),
    })
  })
  Json::object({
    "schema": Json::number(1),
    "run_id": Json::string(plan.run_id),
    "revision": Json::string(plan.revision),
    "reports": Json::array(reports),
  })
}

///|
pub fn encode_plan(plan : @ledger.RunPlan) -> String {
  plan_json(plan).stringify(indent=2)
}

///|
fn binding_fields(binding : @ledger.ReportBinding) -> Map[String, Json] {
  {
    "id": Json::string(binding.id),
    "run_id": Json::string(binding.run_id),
    "revision": Json::string(binding.revision),
    "environment": Json::string(binding.environment),
    "shard": Json::string(binding.shard),
    "attempt": Json::number(binding.attempt.to_double()),
  }
}

///|
pub fn encode_bundle(bundle : Bundle) -> String {
  Json::object({
    "schema": Json::number(1),
    "documents": Json::array(
      bundle.documents.map(file => {
        let fields = binding_fields(file.binding)
        fields["path"] = Json::string(file.path)
        Json::object(fields)
      }),
    ),
  }).stringify(indent=2)
}

///|
fn optional(value : String?) -> Json {
  match value {
    Some(text) => Json::string(text)
    None => Json::null()
  }
}

///|
fn outcome_name(value : @ledger.Outcome) -> String {
  match value {
    Pass => "pass"
    Failure => "failure"
    Error => "error"
    Skip => "skip"
  }
}

///|
fn verdict_name(value : @ledger.Verdict) -> String {
  match value {
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
/// Render derived evidence. Original XML is retained by the ledger and input
/// files; this is not a JUnit conversion or a lossless XML export.
pub fn encode_summary(
  summary : @ledger.Summary,
  deny_recovered~ : Bool = false,
) -> String {
  Json::object({
    "schema": Json::number(1),
    "run_id": Json::string(summary.run_id),
    "revision": Json::string(summary.revision),
    "complete": Json::boolean(summary.complete),
    "exit_code": Json::number(summary.exit_code(deny_recovered~).to_double()),
    "missing_reports": Json::array(summary.missing_reports.map(Json::string)),
    "missing_cases": Json::array(
      summary.missing_cases.map(item => {
        Json::object({
          "report_id": Json::string(item.report_id),
          "key": key_json(item.key),
        })
      }),
    ),
    "cases": Json::array(
      summary.cases.map(item => {
        Json::object({
          "environment": Json::string(item.environment),
          "shard": Json::string(item.shard),
          "key": key_json(item.key),
          "verdict": Json::string(verdict_name(item.verdict)),
          "attempts": Json::array(
            item.attempts.map(record => {
              Json::object({
                "report_id": Json::string(record.report_id),
                "attempt": Json::number(record.attempt.to_double()),
                "outcome": Json::string(
                  outcome_name(record.observation.outcome),
                ),
                "path": Json::string(record.observation.path),
                "line": Json::number(record.observation.line.to_double()),
                "column": Json::number(record.observation.column.to_double()),
                "skipped_reason": optional(record.observation.skipped_reason),
                "problems": Json::array(
                  record.observation.problems.map(problem => {
                    Json::object({
                      "kind": Json::string(
                        match problem.kind {
                          Failure => "failure"
                          Error => "error"
                        },
                      ),
                      "message": optional(problem.message),
                      "type": optional(problem.type_name),
                      "text": Json::string(problem.text),
                      "path": Json::string(problem.path),
                      "line": Json::number(problem.line.to_double()),
                      "column": Json::number(problem.column.to_double()),
                    })
                  }),
                ),
              })
            }),
          ),
        })
      }),
    ),
  }).stringify(indent=2)
}

///|
pub fn encode_diagnostic(diagnostic : @ledger.Diagnostic) -> String {
  Json::object({
    "schema": Json::number(1),
    "error": Json::object({
      "code": Json::string(diagnostic.code),
      "report_id": Json::string(diagnostic.report_id),
      "path": Json::string(diagnostic.path),
      "message": Json::string(diagnostic.message),
      "line": Json::number(diagnostic.line.to_double()),
      "column": Json::number(diagnostic.column.to_double()),
    }),
  }).stringify(indent=2)
}
