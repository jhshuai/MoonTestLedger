///|
priv struct Html {
  builder : StringBuilder
  limit : Int32
  mut units : Int32
}

///|
fn html_error(code : String, message : String) -> @ledger.InputError {
  @ledger.InputError::Invalid({
    code,
    message,
    report_id: "",
    path: "/html",
    line: 0,
    column: 0,
  })
}

///|
fn Html::write(self : Html, text : String) -> Unit raise @ledger.InputError {
  if text.length() > self.limit - self.units {
    raise html_error(
      "HtmlOutputLimit", "HTML exceeds max_output_units; increase the budget or split the run; no partial report is returned",
    )
  }
  self.builder.write_string(text)
  self.units += text.length()
}

///|
// All caller-controlled values enter only HTML text nodes through this method.
fn Html::text(self : Html, text : String) -> Unit raise @ledger.InputError {
  for character in text.iter() {
    self.write(
      match character {
        '&' => "&amp;"
        '<' => "&lt;"
        '>' => "&gt;"
        '"' => "&quot;"
        '\'' => "&#39;"
        '\r' => "&#13;"
        _ => character.to_string()
      },
    )
  }
}

///|
fn verdict_name(verdict : @ledger.Verdict) -> String {
  match verdict {
    Passed => "passed"
    Failed => "failed"
    Error => "error"
    Skipped => "skipped"
    RecoveredOnRetry => "recovered_on_retry"
    Unresolved => "unresolved"
    Incomplete => "incomplete"
  }
}

///|
fn outcome_name(outcome : @ledger.Outcome) -> String {
  match outcome {
    Pass => "passed"
    Failure => "failed"
    Error => "error"
    Skip => "skipped"
  }
}

///|
fn Html::key(
  self : Html,
  key : @ledger.CaseKey,
) -> Unit raise @ledger.InputError {
  self.text(key.classname)
  self.write(" / ")
  self.text(key.name)
}

///|
/// Render a deterministic, self-contained read-only report. Every attempt and
/// original XML is retained as escaped text; there are no scripts or network assets.
/// The output budget counts UTF-16 units, including markup and escaping.
pub fn render_evidence(
  evidence : @wire.Evidence,
  max_output_units~ : Int32 = 33554432,
) -> String raise @ledger.InputError {
  if max_output_units < 1 || max_output_units > 268435456 {
    raise html_error(
      "HtmlInvalidLimit", "max_output_units must be between 1 and 268435456",
    )
  }
  let html : Html = {
    builder: StringBuilder(),
    limit: max_output_units,
    units: 0,
  }
  let summary = evidence.summary()
  let snapshot = evidence.snapshot()
  html.write(
    (
      #|<!doctype html>
      #|<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
      #|<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'">
      #|<title>MoonTestLedger evidence</title><style>
      #|:root{font-family:system-ui,sans-serif;color:#172b3a;background:#f3f6f8;line-height:1.5}*{box-sizing:border-box}body{margin:0}header{background:#112d3b;color:#fff;padding:36px max(24px,calc((100% - 1120px)/2))}main{max-width:1120px;margin:28px auto;padding:0 24px 48px}h1{margin:4px 0;font-size:2rem}h2{margin-top:32px}h3{margin:12px 0}.eyebrow{letter-spacing:.14em;font-size:.8rem;color:#9adcc7}.meta{overflow-wrap:anywhere}.stats{display:grid;grid-template-columns:repeat(auto-fit,minmax(130px,1fr));gap:12px}.stat,article,.inventory{background:#fff;border:1px solid #d9e2e8;border-radius:8px;padding:16px}.stat strong{font-size:1.65rem;display:block}.stat span{font-size:.83rem;overflow-wrap:anywhere}table{width:100%;border-collapse:collapse;background:#fff}th,td{text-align:left;padding:10px;border-bottom:1px solid #d9e2e8;vertical-align:top;overflow-wrap:anywhere}th{background:#e7eef2}article{margin:12px 0}summary{cursor:pointer;overflow-wrap:anywhere}details{margin:12px 0}.badge{display:inline-block;border-radius:4px;padding:2px 8px;background:#e5edf1;font-size:.85rem}.failed,.error,.unresolved{color:#8d1730;background:#ffe5e9}.incomplete{color:#765009;background:#fff0cd}.passed{color:#116246;background:#dcf5e9}.recovered_on_retry{color:#75420f;background:#ffead5}pre{white-space:pre-wrap;overflow-wrap:anywhere;background:#f3f6f8;border-left:3px solid #a7bcc7;padding:14px;font-size:.85rem}.problem{border-left-color:#c7425c}.muted{color:#536878;font-size:.9rem}a{color:#14634e}.scroll{overflow-x:auto}ul{padding-left:22px}@media(max-width:600px){header{padding:24px}main{padding:0 14px}th,td{padding:7px;font-size:.85rem}}
      #|</style></head><body><header><div class="eyebrow">MOONTESTLEDGER / CI EVIDENCE</div><h1>Test run evidence</h1><div class="meta">Run:
    ),
  )
  html.write(" ")
  html.text(summary.run_id)
  html.write("<br>Revision: ")
  html.text(summary.revision)
  let gate = match evidence.exit_code() {
    0 => "passing"
    1 => "failing"
    _ => "incomplete"
  }
  html.write(
    "<br>Gate: <strong>\{gate}</strong> · Exit \{evidence.exit_code()}<br>Recovery policy: ",
  )
  html.write(
    if evidence.deny_recovered() {
      "deny recovered tests"
    } else {
      "allow recovered tests"
    },
  )
  html.write(
    "</div></header><main><p class=\"muted\">Offline evidence view. All attempts remain visible. Missing evidence takes precedence over test failures. Preserve the JSON archive for replay.</p><section class=\"stats\" aria-label=\"Verdict counts\">",
  )
  for
    verdict in [
      @ledger.Verdict::Passed,
      Failed,
      Error,
      Skipped,
      RecoveredOnRetry,
      Unresolved,
      Incomplete,
    ] {
    let count = summary.cases
      .iter()
      .filter(item => item.verdict == verdict)
      .count()
    html.write(
      "<div class=\"stat\"><strong>\{count}</strong><span>\{verdict_name(verdict)}</span></div>",
    )
  }
  html.write("</section><h2>Missing evidence</h2>")
  if summary.complete {
    html.write("<p>No missing reports or expected testcases.</p>")
  }
  html.write("<ul>")
  for id in summary.missing_reports {
    html.write("<li>Missing report: ")
    html.text(id)
    html.write("</li>")
  }
  for missing in summary.missing_cases {
    html.write("<li>Missing testcase in ")
    html.text(missing.report_id)
    html.write(": ")
    html.key(missing.key)
    html.write("</li>")
  }
  html.write(
    "</ul><h2>Testcases</h2><div class=\"scroll\"><table><thead><tr><th>Environment / shard</th><th>Testcase</th><th>Verdict</th><th>Attempts</th></tr></thead><tbody>",
  )
  for index, item in summary.cases {
    html.write("<tr><td>")
    html.text(item.environment)
    html.write("<br>")
    html.text(item.shard)
    html.write("</td><td><a href=\"#case-\{index}\">")
    html.key(item.key)
    html.write(
      "</a></td><td><span class=\"badge \{verdict_name(item.verdict)}\">\{verdict_name(item.verdict)}</span></td><td>\{item.attempts.length()}</td></tr>",
    )
  }
  html.write("</tbody></table></div><h2>Attempt details</h2>")
  for index, item in summary.cases {
    html.write("<article id=\"case-\{index}\"><h3>")
    html.key(item.key)
    html.write("</h3><p class=\"muted\">")
    html.text(item.environment)
    html.write(" / ")
    html.text(item.shard)
    html.write(
      "</p><span class=\"badge \{verdict_name(item.verdict)}\">\{verdict_name(item.verdict)}</span>",
    )
    for attempt in item.attempts {
      html.write(
        "<details open><summary>Attempt \{attempt.attempt} · \{outcome_name(attempt.observation.outcome)} · Report ",
      )
      html.text(attempt.report_id)
      html.write("</summary><p class=\"muted\">XML location: ")
      html.text(attempt.observation.path)
      html.write(
        " · line \{attempt.observation.line}, column \{attempt.observation.column}</p>",
      )
      if attempt.observation.skipped_reason is Some(reason) {
        html.write("<p>Skip reason: ")
        html.text(reason)
        html.write("</p>")
      }
      for problem in attempt.observation.problems {
        html.write("<p><strong>")
        html.write(
          match problem.kind {
            Failure => "Failure"
            Error => "Error"
          },
        )
        html.write("</strong></p>")
        if problem.message is Some(message) {
          html.write("<p>Message: ")
          html.text(message)
          html.write("</p>")
        }
        if problem.type_name is Some(type_name) {
          html.write("<p>Type: ")
          html.text(type_name)
          html.write("</p>")
        }
        html.write("<p class=\"muted\">XML location: ")
        html.text(problem.path)
        html.write(
          " · line \{problem.line}, column \{problem.column}</p><pre class=\"problem\">",
        )
        html.text(problem.text)
        html.write("</pre>")
      }
      html.write("</details>")
    }
    html.write("</article>")
  }
  html.write(
    "<h2>Declared reports and original XML</h2><p class=\"muted\">Metadata and output remain in the complete original source, including reports with no observed cases.</p>",
  )
  for report in snapshot.plan.reports {
    html.write("<details class=\"inventory\"><summary>Report ")
    html.text(report.id)
    html.write(" · ")
    html.text(report.environment)
    html.write(" / ")
    html.text(report.shard)
    html.write(
      " · attempt \{report.attempt} · \{report.cases.length()} expected cases</summary><ul>",
    )
    for key in report.cases {
      html.write("<li>")
      html.key(key)
      html.write("</li>")
    }
    html.write("</ul>")
    match evidence.source(report.id) {
      None => html.write("<p>Report not received.</p>")
      Some(source) => {
        html.write("<pre>")
        html.text(source)
        html.write("</pre>")
      }
    }
    html.write("</details>")
  }
  html.write(
    "<footer><p class=\"muted\">Generated by MoonTestLedger. This view describes supplied evidence; it does not prove producer provenance or statistical flakiness.</p></footer></main></body></html>\n",
  )
  html.builder.to_string()
}
