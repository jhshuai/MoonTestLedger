///|
priv struct Counts {
  mut tests : Int32
  mut failures : Int32
  mut errors : Int32
  mut skipped : Int32
}

///|
priv struct SuiteState {
  declared : Map[String, Int32]
  counts : Counts
}

///|
priv struct CaseState {
  key : @ledger.CaseKey
  problems : Array[@ledger.Problem]
  mut skip : String?
  mut has_skip : Bool
}

///|
priv struct ProblemState {
  kind : @ledger.ProblemKind
  message : String?
  type_name : String?
  text : StringBuilder
}

///|
priv struct SkipState {
  message : String?
  text : StringBuilder
}

///|
priv enum FrameKind {
  Suite(SuiteState)
  Case(CaseState)
  Problem(ProblemState)
  Skipped(SkipState)
  Inert
}

///|
priv struct Frame {
  name : String
  path : String
  line : Int32
  column : Int32
  children : Map[String, Int32]
  kind : FrameKind
}

///|
priv struct ParserState {
  report_id : String
  limits : @ledger.Limits
  frames : Array[Frame]
  cases : Array[@ledger.ObservedCase]
  identities : Set[@ledger.CaseKey]
  mut event_count : Int32
  mut problem_count : Int32
  mut roots : Int32
}

///|
fn[T] reject(
  code : String,
  report_id : String,
  path : String,
  message : String,
  line : Int32,
  column : Int32,
) -> T raise @ledger.InputError {
  raise @ledger.InputError::Invalid({
    code,
    report_id,
    path,
    message,
    line,
    column,
  })
}

///|
fn[T] ParserState::reject(
  self : ParserState,
  code : String,
  path : String,
  message : String,
  line : Int32,
  column : Int32,
) -> T raise @ledger.InputError {
  reject(code, self.report_id, path, message, line, column)
}
