///|
pub(all) enum PlanChangeKind {
  RunMetadataChanged
  ReportAdded
  ReportRemoved
  ReportBindingChanged
  CaseAdded
  CaseRemoved
  CaseOrderChanged
} derive(Debug, Eq)

///|
/// Report additions/removals cover the whole report in the retained plans.
/// An empty report_id denotes run metadata; key is set only for case changes.
pub(all) struct PlanChange {
  kind : PlanChangeKind
  report_id : String
  key : @ledger.CaseKey?
} derive(Debug, Eq)

///|
pub extend PlanChangeKind with @debug.Debug::{to_repr}

///|
pub extend PlanChangeKind with Eq::{equal, not_equal}

///|
pub extend PlanChange with @debug.Debug::{to_repr}

///|
pub extend PlanChange with Eq::{equal, not_equal}

///|
/// A bounded, deterministic review of two complete declared inventories.
/// Its token binds both plans and every derived change; it is not a signature.
struct PlanReview {
  before : @ledger.RunPlan
  proposed : @ledger.RunPlan
  changes : Array[PlanChange]
  token : String
}

///|
fn copy_review_plan(plan : @ledger.RunPlan) -> @ledger.RunPlan {
  {
    ..plan,
    reports: plan.reports.map(report => {
      ..report,
      cases: report.cases.copy(),
    }),
  }
}

///|
pub fn PlanReview::before(self : PlanReview) -> @ledger.RunPlan {
  copy_review_plan(self.before)
}

///|
pub fn PlanReview::proposed(self : PlanReview) -> @ledger.RunPlan {
  copy_review_plan(self.proposed)
}

///|
pub fn PlanReview::changes(self : PlanReview) -> Array[PlanChange] {
  self.changes.copy()
}

///|
pub fn PlanReview::token(self : PlanReview) -> String {
  self.token
}

///|
/// Compare reviewed declarations, never received reports or observed outcomes.
/// Reordering reports follows RunPlan's existing canonical report ordering;
/// changed case order remains visible because it affects evidence identity.
pub fn review_plan(
  before : @ledger.RunPlan,
  proposed : @ledger.RunPlan,
  limits~ : @ledger.Limits = @ledger.Limits::default(),
) -> PlanReview raise @ledger.InputError {
  let before = @ledger.RunPlan::new(
    before.run_id,
    before.revision,
    before.reports,
    limits~,
  )
  let proposed = @ledger.RunPlan::new(
    proposed.run_id,
    proposed.revision,
    proposed.reports,
    limits~,
  )
  let changes : Array[PlanChange] = []
  if before.run_id != proposed.run_id || before.revision != proposed.revision {
    changes.push({ kind: RunMetadataChanged, report_id: "", key: None, })
  }
  let old : Map[String, @ledger.ExpectedReport] = Map([])
  let next : Map[String, @ledger.ExpectedReport] = Map([])
  let ids : Set[String] = Set([])
  for report in before.reports {
    old[report.id] = report
    ids.add(report.id)
  }
  for report in proposed.reports {
    next[report.id] = report
    ids.add(report.id)
  }
  let ordered = ids.to_array()
  ordered.sort_by((a, b) => a[:].lexical_compare(b[:]))
  for id in ordered {
    match (old.get(id), next.get(id)) {
      (None, Some(_)) =>
        changes.push({ kind: ReportAdded, report_id: id, key: None, })
      (Some(_), None) =>
        changes.push({ kind: ReportRemoved, report_id: id, key: None, })
      (Some(left), Some(right)) => {
        if left.environment != right.environment ||
          left.shard != right.shard ||
          left.attempt != right.attempt {
          changes.push({ kind: ReportBindingChanged, report_id: id, key: None, })
        }
        let old_keys = Set::from_array(left.cases)
        let new_keys = Set::from_array(right.cases)
        let keys = old_keys.to_array()
        for key in right.cases {
          if !old_keys.contains(key) {
            keys.push(key)
          }
        }
        keys.sort_by((a, b) => {
          let classname = a.classname[:].lexical_compare(b.classname[:])
          if classname != 0 {
            classname
          } else {
            a.name[:].lexical_compare(b.name[:])
          }
        })
        let mut same_set = true
        for key in keys {
          if !old_keys.contains(key) {
            same_set = false
            changes.push({ kind: CaseAdded, report_id: id, key: Some(key), })
          } else if !new_keys.contains(key) {
            same_set = false
            changes.push({ kind: CaseRemoved, report_id: id, key: Some(key), })
          }
        }
        if same_set && left.cases != right.cases {
          changes.push({ kind: CaseOrderChanged, report_id: id, key: None, })
        }
      }
      (None, None) => ()
    }
  }
  let token = sha256_text(
    "moontestledger/plan-review-v1\n" +
    Json::object(review_fields(before, proposed, changes)).stringify(indent=2),
  )
  let result : PlanReview = { before, proposed, changes, token, }
  ignore(result.encode(limits~))
  result
}

///|
/// Acknowledge this exact review against an unchanged baseline, for a fresh run.
/// Returns a copy of the proposed plan. Existing evidence is never rewritten.
/// The caller must obtain approval before supplying the displayed token; this
/// checks content/staleness, not the identity or presence of a human reviewer.
pub fn PlanReview::approve(
  self : PlanReview,
  current : @ledger.RunPlan,
  approval~ : String,
  limits~ : @ledger.Limits = @ledger.Limits::default(),
) -> @ledger.RunPlan raise @ledger.InputError {
  ignore(self.encode(limits~))
  let current = @ledger.RunPlan::new(
    current.run_id,
    current.revision,
    current.reports,
    limits~,
  )
  if encode_plan(current) != encode_plan(self.before) {
    raise bad(
      "ReviewStale", "/before", "Current baseline differs from the reviewed inventory; create and review a new proposal",
    )
  }
  if approval != self.token {
    raise bad(
      "ReviewApproval", "/approval", "Supply the exact displayed review token only after reviewing the complete before/proposed plans and changes",
    )
  }
  if self.proposed.run_id == self.before.run_id {
    raise bad(
      "ReviewRunReuse", "/proposed/run_id", "An approved inventory must use a fresh run ID; do not shrink an existing run to hide missing or failed evidence",
    )
  }
  copy_review_plan(self.proposed)
}
