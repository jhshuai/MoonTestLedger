///|
/// Exact producer identity. Parameterized names are not normalized.
pub(all) struct CaseKey {
  classname : String
  name : String
} derive(Debug, Eq, Compare, Hash)

///|
pub(all) struct ExpectedReport {
  id : String
  environment : String
  shard : String
  attempt : Int32
  cases : Array[CaseKey]
} derive(Debug, Eq)

///|
pub(all) struct RunPlan {
  run_id : String
  revision : String
  reports : Array[ExpectedReport]
} derive(Debug, Eq)

///|
/// Metadata supplied by the producer; it is checked against the plan.
/// This is a binding contract, not cryptographic proof of artifact origin.
pub(all) struct ReportBinding {
  id : String
  run_id : String
  revision : String
  environment : String
  shard : String
  attempt : Int32
} derive(Debug, Eq)

///|
pub(all) enum Outcome {
  Pass
  Failure
  Error
  Skip
} derive(Debug, Eq)

///|
pub(all) enum ProblemKind {
  Failure
  Error
} derive(Debug, Eq)

///|
pub(all) struct Problem {
  kind : ProblemKind
  message : String?
  type_name : String?
  text : String
  path : String
  line : Int32
  column : Int32
} derive(Debug, Eq)

///|
pub(all) struct ObservedCase {
  key : CaseKey
  outcome : Outcome
  problems : Array[Problem]
  skipped_reason : String?
  path : String
  line : Int32
  column : Int32
} derive(Debug, Eq)

///|
/// The entire input is retained, including inert metadata and output.
pub(all) struct ParsedReport {
  source : String
  cases : Array[ObservedCase]
} derive(Debug, Eq)

///|
pub(all) struct Document {
  binding : ReportBinding
  report : ParsedReport
} derive(Debug, Eq)

///|
pub(all) struct Diagnostic {
  code : String
  report_id : String
  path : String
  message : String
  line : Int32
  column : Int32
} derive(Debug, Eq)

///|
pub(all) suberror InputError {
  Invalid(Diagnostic)
} derive(Debug)

///|
pub(all) struct Limits {
  max_reports : Int32
  max_cases : Int32
  max_source_units : Int32
  max_total_source_units : Int32
  max_events : Int32
  max_depth : Int32
  max_attributes : Int32
  max_problems : Int32
} derive(Debug, Eq)

///|
pub fn Limits::default() -> Limits {
  {
    max_reports: 256,
    max_cases: 100000,
    max_source_units: 4194304,
    max_total_source_units: 33554432,
    max_events: 500000,
    max_depth: 128,
    max_attributes: 128,
    max_problems: 10000,
  }
}

///|
pub(all) enum Verdict {
  Passed
  Failed
  Error
  Skipped
  RecoveredOnRetry
  Unresolved
  Incomplete
} derive(Debug, Eq)

///|
pub(all) struct AttemptRecord {
  report_id : String
  attempt : Int32
  observation : ObservedCase
} derive(Debug, Eq)

///|
pub(all) struct CaseSummary {
  environment : String
  shard : String
  key : CaseKey
  verdict : Verdict
  attempts : Array[AttemptRecord]
} derive(Debug, Eq)

///|
pub(all) struct MissingCase {
  report_id : String
  key : CaseKey
} derive(Debug, Eq)

///|
pub(all) struct Summary {
  run_id : String
  revision : String
  complete : Bool
  cases : Array[CaseSummary]
  missing_reports : Array[String]
  missing_cases : Array[MissingCase]
} derive(Debug, Eq)

///|
/// Independent copies of the expected inventory and accepted evidence.
pub(all) struct Snapshot {
  plan : RunPlan
  documents : Array[Document]
} derive(Debug, Eq)
