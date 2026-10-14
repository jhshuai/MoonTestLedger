///|
pub using @ledger {
  type CaseKey,
  type ExpectedReport,
  type RunPlan,
  type ReportBinding,
  type Outcome,
  type ProblemKind,
  type Problem,
  type ObservedCase,
  type ParsedReport,
  type Document,
  type Diagnostic,
  type InputError,
  type Limits,
  type Verdict,
  type AttemptRecord,
  type CaseSummary,
  type MissingCase,
  type Summary,
  type Ledger,
  type Snapshot,
}

///|
pub using @wire {
  type ReportFile,
  type Bundle,
  decode_plan,
  encode_plan,
  decode_bundle,
  encode_bundle,
  encode_summary,
  encode_diagnostic,
  type Evidence,
  encode_evidence,
  decode_evidence,
  merge_evidence,
  type RetryReport,
  prepare_retry,
  decode_retry_reports,
  encode_retry_reports,
  type IntegrityManifest,
  type IntegrityDocument,
  decode_integrity,
}

///|
/// Parse the bounded common JUnit profile and retain the original source.
pub fn parse_junit(
  source : String,
  report_id~ : String = "",
  limits~ : @ledger.Limits = @ledger.Limits::default(),
) -> @ledger.ParsedReport raise @ledger.InputError {
  @junit.parse(source, report_id~, limits~)
}

///|
pub using @history {
  type Comparison,
  type Change,
  type ChangeKind,
  compare_evidence,
  type RepetitionKind,
  type RepetitionSample,
  type RepetitionCase,
  type Repetitions,
  analyze_repetitions,
}

///|
pub using @report {render_evidence}
