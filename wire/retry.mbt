///|
/// A new producer report identity for one failing environment/shard group.
pub(all) struct RetryReport {
  id : String
  environment : String
  shard : String
} derive(Debug, Eq)

///|
pub extend RetryReport with @debug.Debug::{to_repr}

///|
pub extend RetryReport with Eq::{equal, not_equal}

///|
pub fn decode_retry_reports(
  source : String,
  limits~ : @ledger.Limits = @ledger.Limits::default(),
) -> Array[RetryReport] raise @ledger.InputError {
  let fields = object(strict_json(source, limits), "$")
  keys(fields, ["schema", "reports"], "$")
  schema(fields)
  let items = array(required(fields, "reports", "$"), "$/reports")
  if items.length() > limits.max_reports {
    raise bad("ReportLimit", "$/reports", "Retry report budget exceeded")
  }
  items.mapi((index, value) => {
    let path = "$/reports/\{index}"
    let item = object(value, path)
    keys(item, ["id", "environment", "shard"], path)
    {
      id: nonempty(string_field(item, "id", path), path + "/id"),
      environment: nonempty(
        string_field(item, "environment", path),
        path + "/environment",
      ),
      shard: nonempty(string_field(item, "shard", path), path + "/shard"),
    }
  })
}

///|
pub fn encode_retry_reports(reports : ArrayView[RetryReport]) -> String {
  Json::object({
    "schema": Json::number(1),
    "reports": Json::array(
      reports
      .to_owned()
      .map(report => {
        Json::object({
          "id": Json::string(report.id),
          "environment": Json::string(report.environment),
          "shard": Json::string(report.shard),
        })
      }),
    ),
  }).stringify(indent=2)
}

///|
/// Extend a complete run by exactly one selective retry for every group with a
/// final failed/error/unresolved case. All existing inventory/source/policy stays.
/// The returned archive is incomplete until the newly declared reports arrive.
pub fn prepare_retry(
  evidence : Evidence,
  reports : ArrayView[RetryReport],
  limits~ : @ledger.Limits = @ledger.Limits::default(),
) -> Evidence raise @ledger.InputError {
  limits.validate()
  let summary = evidence.summary()
  if !summary.complete {
    raise bad(
      "RetryIncomplete", "/plan", "Fill existing missing evidence before declaring another retry",
    )
  }
  if reports.length() > limits.max_reports {
    raise bad("ReportLimit", "/reports", "Retry report budget exceeded")
  }
  let groups : Map[(String, String), Array[@ledger.CaseKey]] = Map([])
  for item in summary.cases {
    match item.verdict {
      Failed | Error | Unresolved => {
        let group = (item.environment, item.shard)
        let cases = groups.get_or_init(group, () => [])
        cases.push(item.key)
      }
      _ => ()
    }
  }
  if groups.is_empty() {
    raise bad(
      "NoRetryCases", "/cases", "No final failed, error or unresolved tests need a retry; recovered tests are not rescheduled",
    )
  }
  let snapshot = evidence.snapshot()
  let expected = snapshot.plan.reports.copy()
  let supplied : Set[(String, String)] = Set([])
  for index, report in reports {
    let path = "/reports/\{index}"
    let group = (report.environment, report.shard)
    if supplied.contains(group) {
      raise bad(
        "DuplicateRetryGroup", path, "Only one new report may be declared per environment/shard",
      )
    }
    supplied.add(group)
    guard groups.get(group) is Some(cases) else {
      raise bad(
        "UnexpectedRetryGroup", path, "This environment/shard has no final adverse tests",
      )
    }
    let mut last = 0
    for previous in snapshot.plan.reports {
      if previous.environment == report.environment &&
        previous.shard == report.shard {
        last = Int32::max(last, previous.attempt)
      }
    }
    if last == 2147483647 {
      raise bad(
        "RetryAttemptLimit", path, "Retry attempt ordinal cannot exceed a positive 32-bit integer",
      )
    }
    expected.push({
      id: report.id,
      environment: report.environment,
      shard: report.shard,
      attempt: last + 1,
      cases: cases.copy(),
    })
  }
  if supplied.length() != groups.length() {
    raise bad(
      "MissingRetryGroup", "/reports", "Supply a new report identity for every environment/shard with final adverse tests",
    )
  }
  let plan = @ledger.RunPlan::new(
    snapshot.plan.run_id,
    snapshot.plan.revision,
    expected,
    limits~,
  )
  let ledger = @ledger.Ledger::new(plan, limits~)
  for document in snapshot.documents {
    ledger.ingest(document)
  }
  { ledger, deny_recovered: evidence.deny_recovered, }
}

///|
/// Append original JUnit documents without mutating the archive. The batch is
/// atomic; custom projections, conflicts and unsupported XML are refused.
pub fn Evidence::ingest_reports(
  self : Evidence,
  documents : ArrayView[@ledger.Document],
  limits~ : @ledger.Limits = @ledger.Limits::default(),
) -> Evidence raise @ledger.InputError {
  limits.validate()
  if documents.length() > limits.max_reports {
    raise bad(
      "ReportLimit", "/documents", "Incoming report count exceeds the budget",
    )
  }
  let snapshot = self.snapshot()
  let ledger = @ledger.Ledger::new(snapshot.plan, limits~)
  for document in snapshot.documents {
    ledger.ingest(document)
  }
  for document in documents {
    let parsed = @junit.parse(
      document.report.source,
      report_id=document.binding.id,
      limits~,
    )
    if parsed != document.report {
      raise bad(
        "ProjectionMismatch",
        "/documents/" + document.binding.id,
        "Incoming observations differ from their original JUnit source",
      )
    }
    ledger.ingest(document)
  }
  { ledger, deny_recovered: self.deny_recovered, }
}
