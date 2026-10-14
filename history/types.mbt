///|
pub(all) enum ChangeKind {
  Added
  Removed
  Regressed
  Improved
  Changed
  Unchanged
  Unknown
} derive(Debug, Eq)

///|
pub(all) struct Change {
  environment : String
  key : @ledger.CaseKey
  kind : ChangeKind
  before : @ledger.CaseSummary?
  after : @ledger.CaseSummary?
} derive(Debug, Eq)

///|
pub extend ChangeKind with @debug.Debug::{to_repr}

///|
pub extend ChangeKind with Eq::{equal, not_equal}

///|
pub extend Change with @debug.Debug::{to_repr}

///|
pub extend Change with Eq::{equal, not_equal}

///|
struct Comparison {
  before : @ledger.Summary
  after : @ledger.Summary
  before_policy : Bool
  after_policy : Bool
  comparable : Bool
  changes : Array[Change]
}

///|
fn copy_case(item : @ledger.CaseSummary) -> @ledger.CaseSummary {
  {
    ..item,
    attempts: item.attempts.map(record => {
      ..record,
      observation: {
        ..record.observation,
        problems: record.observation.problems.copy(),
      },
    }),
  }
}

///|
fn copy_summary(summary : @ledger.Summary) -> @ledger.Summary {
  {
    ..summary,
    cases: summary.cases.map(copy_case),
    missing_reports: summary.missing_reports.copy(),
    missing_cases: summary.missing_cases.copy(),
  }
}

///|
pub fn Comparison::before(self : Comparison) -> @ledger.Summary {
  copy_summary(self.before)
}

///|
pub fn Comparison::after(self : Comparison) -> @ledger.Summary {
  copy_summary(self.after)
}

///|
pub fn Comparison::comparable(self : Comparison) -> Bool {
  self.comparable
}

///|
pub fn Comparison::policy_changed(self : Comparison) -> Bool {
  self.before_policy != self.after_policy
}

///|
/// Return independent records with both sides' full attempt and problem evidence.
pub fn Comparison::changes(self : Comparison) -> Array[Change] {
  self.changes.map(change => {
    ..change,
    before: change.before.map(copy_case),
    after: change.after.map(copy_case),
  })
}
