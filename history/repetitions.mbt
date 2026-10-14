///|
fn repetition_error(
  code : String,
  path : String,
  message : String,
) -> @ledger.InputError {
  @ledger.InputError::Invalid({
    code,
    path,
    message,
    report_id: "",
    line: 0,
    column: 0,
  })
}

///|
fn inventory(summary : @ledger.Summary) -> Array[(String, @ledger.CaseKey)] {
  let keys = summary.cases.map(item => (item.environment, item.key))
  keys.sort()
  keys
}

///|
fn repetition_row(
  environment : String,
  key : @ledger.CaseKey,
  samples : Array[RepetitionSample],
) -> RepetitionCase {
  let mut pass_attempts = 0
  let mut failed_attempts = 0
  let mut error_attempts = 0
  let mut skipped_attempts = 0
  let mut runs_with_pass = 0
  let mut runs_with_failure = 0
  let mut recovered_runs = 0
  let mut incomplete_runs = 0
  for sample in samples {
    let mut passed = false
    let mut failed = false
    if sample.case_summary.verdict == @ledger.Verdict::RecoveredOnRetry {
      recovered_runs += 1
    }
    if sample.case_summary.verdict == @ledger.Verdict::Incomplete {
      incomplete_runs += 1
    }
    for attempt in sample.case_summary.attempts {
      match attempt.observation.outcome {
        Pass => {
          pass_attempts += 1
          passed = true
        }
        Failure => {
          failed_attempts += 1
          failed = true
        }
        Error => {
          error_attempts += 1
          failed = true
        }
        Skip => skipped_attempts += 1
      }
    }
    if passed {
      runs_with_pass += 1
    }
    if failed {
      runs_with_failure += 1
    }
  }
  let kind = if pass_attempts > 0 && failed_attempts + error_attempts > 0 {
    MixedOutcomes
  } else if failed_attempts + error_attempts > 0 {
    FailureObserved
  } else if pass_attempts > 0 {
    PassObserved
  } else if skipped_attempts > 0 {
    SkipsOnly
  } else {
    NoObservations
  }
  {
    environment,
    key,
    kind,
    pass_attempts,
    failed_attempts,
    error_attempts,
    skipped_attempts,
    runs_with_pass,
    runs_with_failure,
    recovered_runs,
    incomplete_runs,
    samples,
  }
}

///|
/// Analyze independent runs at the same revision/policy and exact environment/
/// testcase inventory. Shard moves and selective retry counts may differ.
/// Duplicate run IDs are rejected; incomplete evidence stays inconclusive.
pub fn analyze_repetitions(
  inputs : ArrayView[@wire.Evidence],
  limits~ : @ledger.Limits = @ledger.Limits::default(),
) -> Repetitions raise @ledger.InputError {
  limits.validate()
  if inputs.length() < 2 {
    raise repetition_error(
      "RepetitionRunCount", "/inputs", "Supply at least two independent run archives",
    )
  }
  if inputs.length() > limits.max_reports {
    raise repetition_error("ReportLimit", "/inputs", "Too many run archives")
  }
  let revision = inputs[0].summary().revision
  let policy = inputs[0].deny_recovered()
  let baseline = inventory(inputs[0].summary())
  let ids : Set[String] = Set([])
  let entries : Array[(@ledger.Summary, @wire.Evidence)] = []
  let mut total_units = 0L
  let mut reports = 0L
  let mut cases = 0L
  let mut problems = 0L
  for index, input in inputs {
    let path = "/inputs/\{index}"
    let summary = input.summary()
    if ids.contains(summary.run_id) {
      raise repetition_error(
        "DuplicateRun", path, "Repeated run IDs would inflate observations; provide distinct producer run IDs",
      )
    }
    ids.add(summary.run_id)
    if summary.revision != revision {
      raise repetition_error(
        "RepetitionRevisionMismatch", path, "Use compare for different revisions; repeated-run analysis requires one exact revision",
      )
    }
    if input.deny_recovered() != policy {
      raise repetition_error(
        "RepetitionPolicyMismatch", path, "Recovery policy must agree across runs",
      )
    }
    if inventory(summary) != baseline {
      raise repetition_error(
        "RepetitionInventoryMismatch", path, "Exact environment/classname/name inventory must agree; missing artifacts must not shrink the plan",
      )
    }
    // Canonical archive text bounds both raw XML and plan metadata, and
    // revalidates each input against the caller's individual resource limits.
    total_units += input.encode(limits~).length().to_int64()
    if total_units > limits.max_total_source_units.to_int64() {
      raise repetition_error(
        "SourceLimit", path, "Combined canonical archive text exceeds the total source budget",
      )
    }
    let snapshot = input.snapshot()
    reports += snapshot.plan.reports.length().to_int64()
    for report in snapshot.plan.reports {
      cases += report.cases.length().to_int64()
    }
    for item in summary.cases {
      for attempt in item.attempts {
        problems += attempt.observation.problems.length().to_int64()
      }
    }
    if reports > limits.max_reports.to_int64() {
      raise repetition_error(
        "ReportLimit", path, "Combined expected report count exceeds the budget",
      )
    }
    if cases > limits.max_cases.to_int64() {
      raise repetition_error(
        "CaseLimit", path, "Combined expected observations exceed the budget",
      )
    }
    if problems > limits.max_problems.to_int64() {
      raise repetition_error(
        "ProblemLimit", path, "Combined problem payload count exceeds the budget",
      )
    }
    entries.push((summary, input))
  }
  entries.sort_by((a, b) => a.0.run_id.compare(b.0.run_id))
  let grouped : Map[(String, @ledger.CaseKey), Array[RepetitionSample]] = Map([])
  for (summary, _) in entries {
    for item in summary.cases {
      grouped
      .get_or_init((item.environment, item.key), () => [])
      .push({ run_id: summary.run_id, case_summary: item, })
    }
  }
  let rows = baseline.map(identity => {
    let (environment, key) = identity
    repetition_row(environment, key, grouped[identity])
  })
  {
    inputs: entries.map(entry => entry.1),
    summaries: entries.map(entry => entry.0),
    rows,
  }
}
