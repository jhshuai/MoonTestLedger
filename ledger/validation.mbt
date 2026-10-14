///|
fn invalid(
  code : String,
  id : String,
  path : String,
  message : String,
) -> InputError {
  InputError::Invalid({
    code,
    report_id: id,
    path,
    message,
    line: 0,
    column: 0,
  })
}

///|
fn valid_text(value : String) -> Bool {
  !value.is_empty() &&
  !value.contains("\u0000") &&
  !value.iter().all(c => c is (' ' | '\t' | '\r' | '\n'))
}

///|
/// Validate budgets before allocating or accepting data. Upper bounds keep
/// counter arithmetic and retained-source allocation explicitly bounded.
pub fn Limits::validate(self : Limits) -> Unit raise InputError {
  let fields = [
    ("max_reports", self.max_reports, 4096),
    ("max_cases", self.max_cases, 1000000),
    ("max_source_units", self.max_source_units, 67108864),
    ("max_total_source_units", self.max_total_source_units, 268435456),
    ("max_events", self.max_events, 2000000),
    ("max_depth", self.max_depth, 256),
    ("max_attributes", self.max_attributes, 4096),
    ("max_problems", self.max_problems, 1000000),
  ]
  for (name, value, ceiling) in fields {
    if value <= 0 || value > ceiling {
      raise invalid(
        "InvalidLimit",
        "",
        "/limits/" + name,
        "Expected a value in 1..\{ceiling}",
      )
    }
  }
}

///|
fn copy_expected(report : ExpectedReport) -> ExpectedReport {
  { ..report, cases: report.cases.copy(), }
}

///|
fn report_order(a : ExpectedReport, b : ExpectedReport) -> Int32 {
  let environment = a.environment.compare(b.environment)
  if environment != 0 {
    return environment
  }
  let shard = a.shard.compare(b.shard)
  if shard != 0 {
    return shard
  }
  let attempt = a.attempt.compare(b.attempt)
  if attempt != 0 {
    return attempt
  }
  a.id.compare(b.id)
}

///|
/// Construct a canonical inventory. Retry subsets and shard membership are
/// declared, never guessed from file names, timestamps or observed totals.
pub fn RunPlan::new(
  run_id : String,
  revision : String,
  reports : Array[ExpectedReport],
  limits~ : Limits = Limits::default(),
) -> RunPlan raise InputError {
  limits.validate()
  if !valid_text(run_id) || !valid_text(revision) {
    raise invalid(
      "InvalidRun", "", "/", "Run ID and revision must be nonempty identifiers without NUL",
    )
  }
  if reports.is_empty() || reports.length() > limits.max_reports {
    raise invalid(
      "ReportLimit",
      "",
      "/reports",
      "Expected 1..\{limits.max_reports} report declarations",
    )
  }
  let mut expected_count = 0
  for report in reports {
    if report.cases.length() > limits.max_cases - expected_count {
      raise invalid(
        "CaseLimit",
        report.id,
        "/cases",
        "Total expected observations exceed the configured limit",
      )
    }
    expected_count += report.cases.length()
  }
  let ordered = reports.map(copy_expected)
  ordered.sort_by(report_order)
  let ids : Set[String] = Set([])
  let groups : Map[(String, String), Array[ExpectedReport]] = Map([])
  let mut count = 0
  for report in ordered {
    if !valid_text(report.id) ||
      !valid_text(report.environment) ||
      !valid_text(report.shard) ||
      report.attempt <= 0 {
      raise invalid(
        "InvalidReport",
        report.id,
        "/reports",
        "Report ID, environment, shard and positive attempt are required",
      )
    }
    if ids.contains(report.id) {
      raise invalid(
        "DuplicateReport",
        report.id,
        "/reports",
        "A report ID may appear only once in the plan",
      )
    }
    ids.add(report.id)
    let seen : Set[CaseKey] = Set([])
    for key in report.cases {
      if !valid_text(key.name) || key.classname.contains("\u0000") {
        raise invalid(
          "InvalidCase",
          report.id,
          "/cases",
          "Case names must be nonempty; identity fields cannot contain NUL",
        )
      }
      if seen.contains(key) {
        raise invalid(
          "DuplicateCase",
          report.id,
          "/cases",
          "The same exact testcase identity is declared twice",
        )
      }
      seen.add(key)
      count += 1
      if count > limits.max_cases {
        raise invalid(
          "CaseLimit",
          report.id,
          "/cases",
          "Total expected observations exceed the configured limit",
        )
      }
    }
    let group = (report.environment, report.shard)
    match groups.get(group) {
      Some(items) => items.push(report)
      None => groups[group] = [report]
    }
  }
  let membership : Map[(String, CaseKey), String] = Map([])
  let mut baseline_count = 0
  for (environment, shard), attempts in groups {
    let first = attempts[0]
    let baseline : Set[CaseKey] = Set([])
    for key in first.cases {
      baseline.add(key)
    }
    for i, report in attempts {
      if report.attempt != i + 1 {
        raise invalid(
          "AttemptSequence",
          report.id,
          "/attempt",
          "Each environment/shard must declare exactly one report for consecutive attempts starting at 1",
        )
      }
      if i != 0 {
        for key in report.cases {
          if !baseline.contains(key) {
            raise invalid(
              "UnexpectedRetryCase",
              report.id,
              "/cases",
              "A retry cannot introduce a testcase absent from this shard's first attempt",
            )
          }
        }
      }
    }
    for key in first.cases {
      baseline_count += 1
      match membership.get((environment, key)) {
        Some(other) =>
          raise invalid(
            "AmbiguousShard",
            first.id,
            "/cases",
            "Identity also belongs to shard '" +
            other +
            "' in environment '" +
            environment +
            "'",
          )
        None => membership[(environment, key)] = shard
      }
    }
  }
  if baseline_count == 0 {
    raise invalid(
      "EmptyInventory", "", "/reports", "At least one expected testcase is required; an empty run is not evidence of passing tests",
    )
  }
  { run_id, revision, reports: ordered, }
}
