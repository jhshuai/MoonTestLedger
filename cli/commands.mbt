///|
async fn load_ledger(
  plan_path : String,
  bundle_path : String,
) -> @ledger.Ledger {
  let limits = @ledger.Limits::default()
  let plan = @ledger.decode_plan(read_text(plan_path, limits), limits~)
  let bundle = @ledger.decode_bundle(read_text(bundle_path, limits), limits~)
  let ledger = @ledger.Ledger::new(plan, limits~)
  for file in bundle.documents {
    let path = report_path(bundle_path, file.path)
    let report = @ledger.parse_junit(
      read_text(path, limits),
      report_id=file.binding.id,
      limits~,
    )
    ledger.ingest({ binding: file.binding, report, })
  }
  ledger
}

///|
async fn audit(
  plan_path : String,
  bundle_path : String,
  deny_recovered : Bool,
) -> Int32 {
  let summary = load_ledger(plan_path, bundle_path).summary()
  @stdio.stdout.write(@ledger.encode_summary(summary, deny_recovered~) + "\n")
  summary.exit_code(deny_recovered~)
}

///|
async fn archive(
  plan_path : String,
  bundle_path : String,
  deny_recovered : Bool,
) -> Int32 {
  let ledger = load_ledger(plan_path, bundle_path)
  @stdio.stdout.write(@ledger.encode_evidence(ledger, deny_recovered~) + "\n")
  0
}

///|
async fn verify(path : String) -> Int32 {
  let evidence = @ledger.decode_evidence(
    read_text(path, @ledger.Limits::default()),
  )
  @stdio.stdout.write(
    @ledger.encode_summary(
      evidence.summary(),
      deny_recovered=evidence.deny_recovered(),
    ) +
    "\n",
  )
  evidence.exit_code()
}

///|
async fn compare(before_path : String, after_path : String) -> Int32 {
  let limits = @ledger.Limits::default()
  let before = @ledger.decode_evidence(read_text(before_path, limits), limits~)
  let after = @ledger.decode_evidence(read_text(after_path, limits), limits~)
  let comparison = @ledger.compare_evidence(before, after)
  @stdio.stdout.write(comparison.encode() + "\n")
  comparison.exit_code()
}

///|
// Capture is an explicit inventory bootstrap from a known complete run. It
// cannot establish that the input producer actually executed every test.
async fn capture(bundle_path : String) -> Int32 {
  let limits = @ledger.Limits::default()
  let bundle = @ledger.decode_bundle(read_text(bundle_path, limits), limits~)
  guard bundle.documents.get(0) is Some(first) else {
    raise refusal(
      "EmptyInventory", bundle_path, "Cannot capture an empty bundle",
    )
  }
  let reports : Array[@ledger.ExpectedReport] = []
  let mut total_units = 0L
  let mut observations = 0
  for file in bundle.documents {
    if file.binding.run_id != first.binding.run_id ||
      file.binding.revision != first.binding.revision {
      raise refusal(
        "BindingMismatch", bundle_path, "Capture inputs must share the same run ID and revision",
      )
    }
    let source = read_text(report_path(bundle_path, file.path), limits)
    total_units += source.length().to_int64()
    if total_units > limits.max_total_source_units.to_int64() {
      raise refusal(
        "SourceLimit", bundle_path, "Total captured source budget exceeded",
      )
    }
    let report = @ledger.parse_junit(source, report_id=file.binding.id, limits~)
    observations += report.cases.length()
    if observations > limits.max_cases {
      raise refusal(
        "CaseLimit", bundle_path, "Total captured observation budget exceeded",
      )
    }
    reports.push({
      id: file.binding.id,
      environment: file.binding.environment,
      shard: file.binding.shard,
      attempt: file.binding.attempt,
      cases: report.cases.map(testcase => testcase.key),
    })
  }
  let plan = @ledger.RunPlan::new(
    first.binding.run_id,
    first.binding.revision,
    reports,
    limits~,
  )
  @stdio.stdout.write(@ledger.encode_plan(plan) + "\n")
  0
}

///|
/// Run the file workflow. JSON evidence goes to stdout, diagnostics to stderr.
/// Returns 0/1/2/3; the executable forwards this as the process exit status.
pub async fn run(arguments : Array[String]) -> Int32 {
  try {
    match arguments {
      ["audit", plan, bundle] => audit(plan, bundle, false)
      ["audit", plan, bundle, "--deny-recovered"] => audit(plan, bundle, true)
      ["capture", bundle] => capture(bundle)
      ["archive", plan, bundle] => archive(plan, bundle, false)
      ["archive", plan, bundle, "--deny-recovered"] =>
        archive(plan, bundle, true)
      ["verify", path] => verify(path)
      ["compare", before, after] => compare(before, after)
      ["--help"] | ["help"] => {
        @stdio.stdout.write(
          "MoonTestLedger\n  audit PLAN.json BUNDLE.json [--deny-recovered]\n  capture BUNDLE.json\n  archive PLAN.json BUNDLE.json [--deny-recovered]\n  verify EVIDENCE.json\n  compare BEFORE.json AFTER.json\nArchive/capture: 0 on creation. Audit/verify: 0 passing, 1 failing, 2 invalid input, 3 incomplete. Compare: 0 no new adverse result, 1 regression, 2 invalid input, 3 inconclusive.\n",
        )
        0
      }
      _ =>
        raise refusal(
          "Usage", "/arguments", "Use audit, capture, archive, verify or compare; --help shows arguments",
        )
    }
  } catch {
    @ledger.InputError::Invalid(diagnostic) => {
      @stdio.stderr.write(@ledger.encode_diagnostic(diagnostic) + "\n")
      2
    }
    error => {
      let diagnostic : @ledger.Diagnostic = {
        code: "CommandIo",
        report_id: "",
        path: "/",
        line: 0,
        column: 0,
        message: "Command I/O failed: " + error.to_string(),
      }
      @stdio.stderr.write(@ledger.encode_diagnostic(diagnostic) + "\n")
      2
    }
  }
}
