///|
/// A validated, replayable JUnit archive. Storage and gate policy are opaque.
struct Evidence {
  ledger : @ledger.Ledger
  deny_recovered : Bool
}

///|
pub fn Evidence::summary(self : Evidence) -> @ledger.Summary {
  self.ledger.summary()
}

///|
pub fn Evidence::source(self : Evidence, report_id : String) -> String? {
  self.ledger.source(report_id)
}

///|
/// Independent inventory/document copies, including accepted empty reports.
pub fn Evidence::snapshot(self : Evidence) -> @ledger.Snapshot {
  self.ledger.snapshot()
}

///|
pub fn Evidence::exit_code(self : Evidence) -> Int32 {
  self.summary().exit_code(deny_recovered=self.deny_recovered)
}

///|
pub fn Evidence::deny_recovered(self : Evidence) -> Bool {
  self.deny_recovered
}

///|
/// Archive the full inventory, exact original XML and recovery policy. Custom
/// projections that do not match the supported JUnit parser are refused.
pub fn encode_evidence(
  ledger : @ledger.Ledger,
  deny_recovered~ : Bool = false,
  limits~ : @ledger.Limits = @ledger.Limits::default(),
) -> String raise @ledger.InputError {
  limits.validate()
  let snapshot = ledger.snapshot()
  let checked = @ledger.Ledger::new(snapshot.plan, limits~)
  let documents : Array[Json] = []
  for document in snapshot.documents {
    let parsed = @junit.parse(
      document.report.source,
      report_id=document.binding.id,
      limits~,
    )
    if parsed != document.report {
      raise bad(
        "ProjectionMismatch",
        "/documents/" + document.binding.id,
        "Stored observations differ from the original JUnit source; refusing to discard a custom projection",
      )
    }
    checked.ingest(document)
    let fields = binding_fields(document.binding)
    fields["xml"] = Json::string(document.report.source)
    documents.push(Json::object(fields))
  }
  let result = Json::object({
    "schema": Json::number(1),
    "kind": Json::string("moontestledger/evidence"),
    "deny_recovered": Json::boolean(deny_recovered),
    "plan": plan_json(snapshot.plan),
    "documents": Json::array(documents),
  }).stringify(indent=2)
  if result.length() > limits.max_source_units {
    raise bad(
      "SourceLimit", "$", "Encoded archive exceeds the configured JSON input budget",
    )
  }
  result
}

///|
/// Strictly replay all stored reports against the stored plan. Missing
/// artifacts stay incomplete; unknown fields and malformed XML are rejected.
pub fn decode_evidence(
  source : String,
  limits~ : @ledger.Limits = @ledger.Limits::default(),
) -> Evidence raise @ledger.InputError {
  let fields = object(strict_json(source, limits), "$")
  keys(fields, ["schema", "kind", "deny_recovered", "plan", "documents"], "$")
  schema(fields)
  if string_field(fields, "kind", "$") != "moontestledger/evidence" {
    raise bad(
      "ArchiveKind", "$/kind", "Expected a MoonTestLedger evidence archive",
    )
  }
  let deny_recovered = match required(fields, "deny_recovered", "$") {
    True => true
    False => false
    _ =>
      raise bad(
        "ExpectedBoolean", "$/deny_recovered", "Expected a boolean gate policy",
      )
  }
  let plan = decode_plan(required(fields, "plan", "$").stringify(), limits~)
  let ledger = @ledger.Ledger::new(plan, limits~)
  let items = array(required(fields, "documents", "$"), "$/documents")
  if items.length() > limits.max_reports {
    raise bad("ReportLimit", "$/documents", "Archive document budget exceeded")
  }
  let ids : Set[String] = Set([])
  for i, item in items {
    let path = "$/documents/\{i}"
    let item = object(item, path)
    keys(
      item,
      ["id", "run_id", "revision", "environment", "shard", "attempt", "xml"],
      path,
    )
    let id = string_field(item, "id", path)
    if ids.contains(id) {
      raise bad(
        "DuplicateReport", path, "Archive report identity appears more than once",
      )
    }
    ids.add(id)
    let binding : @ledger.ReportBinding = {
      id,
      run_id: string_field(item, "run_id", path),
      revision: string_field(item, "revision", path),
      environment: string_field(item, "environment", path),
      shard: string_field(item, "shard", path),
      attempt: positive_integer(item, "attempt", path),
    }
    let report = @junit.parse(
      string_field(item, "xml", path),
      report_id=id,
      limits~,
    )
    ledger.ingest({ binding, report, })
  }
  { ledger, deny_recovered, }
}

///|
pub fn Evidence::encode(
  self : Evidence,
  limits~ : @ledger.Limits = @ledger.Limits::default(),
) -> String raise @ledger.InputError {
  encode_evidence(self.ledger, deny_recovered=self.deny_recovered, limits~)
}
