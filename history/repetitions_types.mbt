///|
/// Observed attempt outcomes at one revision, not a statistical diagnosis.
pub(all) enum RepetitionKind {
  MixedOutcomes
  FailureObserved
  PassObserved
  SkipsOnly
  NoObservations
} derive(Debug, Eq)

///|
pub(all) struct RepetitionSample {
  run_id : String
  case_summary : @ledger.CaseSummary
} derive(Debug, Eq)

///|
pub(all) struct RepetitionCase {
  environment : String
  key : @ledger.CaseKey
  kind : RepetitionKind
  pass_attempts : Int32
  failed_attempts : Int32
  error_attempts : Int32
  skipped_attempts : Int32
  runs_with_pass : Int32
  runs_with_failure : Int32
  recovered_runs : Int32
  incomplete_runs : Int32
  samples : Array[RepetitionSample]
} derive(Debug, Eq)

///|
pub extend RepetitionKind with @debug.Debug::{to_repr}

///|
pub extend RepetitionKind with Eq::{equal, not_equal}

///|
pub extend RepetitionSample with @debug.Debug::{to_repr}

///|
pub extend RepetitionSample with Eq::{equal, not_equal}

///|
pub extend RepetitionCase with @debug.Debug::{to_repr}

///|
pub extend RepetitionCase with Eq::{equal, not_equal}

///|
struct Repetitions {
  inputs : Array[@wire.Evidence]
  summaries : Array[@ledger.Summary]
  rows : Array[RepetitionCase]
}

///|
pub fn Repetitions::complete(self : Repetitions) -> Bool {
  self.summaries.all(summary => summary.complete)
}

///|
/// 3 incomplete; 1 observed pass and failure/error for the same exact test;
/// 0 no observed mixture. This is not an all-tests-pass gate or a confidence score.
pub fn Repetitions::exit_code(self : Repetitions) -> Int32 {
  if !self.complete() {
    return 3
  }
  if self.rows.any(row => row.kind == MixedOutcomes) {
    1
  } else {
    0
  }
}

///|
pub fn Repetitions::summaries(self : Repetitions) -> Array[@ledger.Summary] {
  self.summaries.map(copy_summary)
}

///|
pub fn Repetitions::rows(self : Repetitions) -> Array[RepetitionCase] {
  self.rows.map(row => {
    ..row,
    samples: row.samples.map(sample => {
      ..sample,
      case_summary: copy_case(sample.case_summary),
    }),
  })
}

///|
pub fn Repetitions::source(
  self : Repetitions,
  run_id : String,
  report_id : String,
) -> String? {
  for index, summary in self.summaries {
    if summary.run_id == run_id {
      return self.inputs[index].source(report_id)
    }
  }
  None
}
