///|
async fn review_plan(
  before : String,
  proposed : String,
  output : String?,
) -> Int32 {
  let limits = @ledger.Limits::default()
  let review = @ledger.review_plan(
    @ledger.decode_plan(read_text(before, limits), limits~),
    @ledger.decode_plan(read_text(proposed, limits), limits~),
    limits~,
  )
  emit_evidence(review.encode(limits~), output)
  0
}

///|
async fn apply_plan_review(
  review : String,
  current : String,
  approval : String,
  output : String?,
) -> Int32 {
  guard output is Some(_) else {
    raise refusal(
      "PlanOutputRequired", "/arguments", "Use --output NEW-PLAN.json; reviewed baselines and existing evidence are never overwritten",
    )
  }
  let limits = @ledger.Limits::default()
  let reviewed = @ledger.decode_plan_review(read_text(review, limits), limits~)
  let approved = reviewed.approve(
    @ledger.decode_plan(read_text(current, limits), limits~),
    approval~,
    limits~,
  )
  emit_evidence(@ledger.encode_plan(approved), output)
  0
}
