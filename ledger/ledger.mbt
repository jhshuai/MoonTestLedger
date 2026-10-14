///|
/// Accepted documents are immutable snapshots. A conflicting re-import cannot
/// replace earlier evidence, and rejected input leaves this ledger unchanged.
struct Ledger {
  plan : RunPlan
  limits : Limits
  documents : Map[String, Document]
  mut source_units : Int64
  mut observation_count : Int32
  mut problem_count : Int32
}

///|
fn copy_case(testcase : ObservedCase) -> ObservedCase {
  { ..testcase, problems: testcase.problems.copy(), }
}

///|
fn copy_document(document : Document) -> Document {
  {
    ..document,
    report: {
      source: document.report.source,
      cases: document.report.cases.map(copy_case),
    },
  }
}

///|
pub fn Ledger::new(
  plan : RunPlan,
  limits~ : Limits = Limits::default(),
) -> Ledger raise InputError {
  let plan = RunPlan::new(plan.run_id, plan.revision, plan.reports, limits~)
  {
    plan,
    limits,
    documents: Map([]),
    source_units: 0L,
    observation_count: 0,
    problem_count: 0,
  }
}

///|
fn validate_observation(
  testcase : ObservedCase,
  id : String,
) -> Unit raise InputError {
  let failure = testcase.problems.any(p => p.kind == ProblemKind::Failure)
  let error = testcase.problems.any(p => p.kind == ProblemKind::Error)
  let coherent = match testcase.outcome {
    Pass => !failure && !error && testcase.skipped_reason is None
    Skip => !failure && !error
    Failure => failure && !error && testcase.skipped_reason is None
    Error => error && testcase.skipped_reason is None
  }
  if !coherent {
    raise invalid(
      "InconsistentOutcome",
      id,
      testcase.path,
      "Outcome does not agree with the retained failure/error/skipped evidence",
    )
  }
}

///|
pub fn Ledger::ingest(
  self : Ledger,
  document : Document,
) -> Unit raise InputError {
  let binding = document.binding
  let expected = match
    self.plan.reports.iter().find_first(report => report.id == binding.id) {
    Some(expected) => expected
    None =>
      raise invalid(
        "UnexpectedReport",
        binding.id,
        "/binding/id",
        "Report ID was not declared in this run plan",
      )
  }
  if binding.run_id != self.plan.run_id ||
    binding.revision != self.plan.revision ||
    binding.environment != expected.environment ||
    binding.shard != expected.shard ||
    binding.attempt != expected.attempt {
    raise invalid(
      "BindingMismatch",
      binding.id,
      "/binding",
      "Run, revision, environment, shard and attempt must exactly match the plan",
    )
  }
  match self.documents.get(binding.id) {
    Some(accepted) => {
      if accepted == document {
        return
      }
      raise invalid(
        "ConflictingReport",
        binding.id,
        "/",
        "This report identity already has different accepted content; prior evidence was retained",
      )
    }
    None => ()
  }
  if document.report.source.length() > self.limits.max_source_units ||
    self.source_units + document.report.source.length().to_int64() >
    self.limits.max_total_source_units.to_int64() {
    raise invalid(
      "SourceLimit",
      binding.id,
      "/",
      "Per-document or total retained-source budget exceeded",
    )
  }
  if document.report.cases.length() >
    self.limits.max_cases - self.observation_count {
    raise invalid(
      "CaseLimit",
      binding.id,
      "/cases",
      "Accepted observation budget exceeded",
    )
  }
  let seen : Set[CaseKey] = Set([])
  let expected_keys : Set[CaseKey] = Set([])
  for key in expected.cases {
    expected_keys.add(key)
  }
  let mut problems = 0
  for testcase in document.report.cases {
    if seen.contains(testcase.key) {
      raise invalid(
        "DuplicateCase",
        binding.id,
        testcase.path,
        "A testcase identity appears more than once in this report",
      )
    }
    seen.add(testcase.key)
    if !expected_keys.contains(testcase.key) {
      raise invalid(
        "UnexpectedCase",
        binding.id,
        testcase.path,
        "Testcase identity was not expected in this report and attempt",
      )
    }
    validate_observation(testcase, binding.id)
    if testcase.problems.length() >
      self.limits.max_problems - self.problem_count - problems {
      raise invalid(
        "ProblemLimit",
        binding.id,
        testcase.path,
        "Accepted problem evidence budget exceeded",
      )
    }
    problems += testcase.problems.length()
  }
  // All possible refusals occur before mutation. Retained arrays belong to us.
  let accepted = copy_document(document)
  self.documents[binding.id] = accepted
  self.source_units += accepted.report.source.length().to_int64()
  self.observation_count += accepted.report.cases.length()
  self.problem_count += problems
}

///|
pub fn Ledger::source(self : Ledger, report_id : String) -> String? {
  self.documents.get(report_id).map(document => document.report.source)
}

///|
/// Export a fresh snapshot, ordered by the plan. Mutating its arrays cannot
/// alter the ledger; absent expected reports remain absent in the document list.
pub fn Ledger::snapshot(self : Ledger) -> Snapshot {
  let documents : Array[Document] = []
  for report in self.plan.reports {
    if self.documents.get(report.id) is Some(document) {
      documents.push(copy_document(document))
    }
  }
  {
    plan: { ..self.plan, reports: self.plan.reports.map(copy_expected), },
    documents,
  }
}
