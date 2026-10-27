///|
fn plan_change_name(kind : PlanChangeKind) -> String {
  match kind {
    RunMetadataChanged => "run_metadata_changed"
    ReportAdded => "report_added"
    ReportRemoved => "report_removed"
    ReportBindingChanged => "report_binding_changed"
    CaseAdded => "case_added"
    CaseRemoved => "case_removed"
    CaseOrderChanged => "case_order_changed"
  }
}

///|
fn review_fields(
  before : @ledger.RunPlan,
  proposed : @ledger.RunPlan,
  changes : Array[PlanChange],
) -> Map[String, Json] {
  {
    "schema": Json::number(1),
    "kind": Json::string("moontestledger/plan-review"),
    "before": plan_json(before),
    "proposed": plan_json(proposed),
    "before_sha256": Json::string(sha256_text(encode_plan(before))),
    "proposed_sha256": Json::string(sha256_text(encode_plan(proposed))),
    "changes": Json::array(
      changes.map(change => {
        Json::object({
          "kind": Json::string(plan_change_name(change.kind)),
          "report_id": Json::string(change.report_id),
          "key": match change.key {
            None => Json::null()
            Some(key) => key_json(key)
          },
        })
      }),
    ),
  }
}

///|
/// Full plans and deterministic changes are retained. Over-budget reviews are
/// refused, never shortened. Digests use the existing canonical plan encoding.
pub fn PlanReview::encode(
  self : PlanReview,
  limits~ : @ledger.Limits = @ledger.Limits::default(),
) -> String raise @ledger.InputError {
  ignore(
    @ledger.RunPlan::new(
      self.before.run_id,
      self.before.revision,
      self.before.reports,
      limits~,
    ),
  )
  ignore(
    @ledger.RunPlan::new(
      self.proposed.run_id,
      self.proposed.revision,
      self.proposed.reports,
      limits~,
    ),
  )
  let fields = review_fields(self.before, self.proposed, self.changes)
  fields["review_sha256"] = Json::string(self.token)
  let source = Json::object(fields).stringify(indent=2)
  if source.length() > limits.max_source_units {
    raise bad(
      "ReviewLimit", "/", "Complete review exceeds the source/output budget; increase an allowed limit, never truncate the inventory or changes",
    )
  }
  source
}

///|
/// Strictly decode then recompute both plan hashes, every change and the token.
/// Duplicate/unknown fields and any supplied projection mismatch are refused.
pub fn decode_plan_review(
  source : String,
  limits~ : @ledger.Limits = @ledger.Limits::default(),
) -> PlanReview raise @ledger.InputError {
  let fields = object(strict_json(source, limits), "$")
  keys(
    fields,
    [
      "schema", "kind", "before", "proposed", "before_sha256", "proposed_sha256",
      "changes", "review_sha256",
    ],
    "$",
  )
  schema(fields)
  if string_field(fields, "kind", "$") != "moontestledger/plan-review" {
    raise bad(
      "ReviewKind", "$/kind", "Expected a complete inventory plan review",
    )
  }
  let before = decode_plan(required(fields, "before", "$").stringify(), limits~)
  let proposed = decode_plan(
    required(fields, "proposed", "$").stringify(),
    limits~,
  )
  let review = review_plan(before, proposed, limits~)
  let expected = review_fields(review.before, review.proposed, review.changes)
  expected["review_sha256"] = Json::string(review.token)
  if Json::object(fields) != Json::object(expected) {
    raise bad(
      "ReviewMismatch", "$", "Review hashes, complete declarations or changes differ from recomputed inventory; regenerate and review rather than editing the approval token",
    )
  }
  review
}
