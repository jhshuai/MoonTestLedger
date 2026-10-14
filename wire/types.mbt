///|
/// A producer-supplied binding and path to an unchanged XML artifact.
pub(all) struct ReportFile {
  binding : @ledger.ReportBinding
  path : String
} derive(Debug, Eq)

///|
pub(all) struct Bundle {
  documents : Array[ReportFile]
} derive(Debug, Eq)
