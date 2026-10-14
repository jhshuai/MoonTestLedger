///|
fn report_evidence(
  missing~ : Bool = false,
  deny~ : Bool = false,
) -> @wire.Evidence raise {
  let key : @ledger.CaseKey = { classname: "C<&", name: "a<\"'😀", }
  let plan = @ledger.RunPlan::new(
    "run<\"'&😀",
    "rev</title><script>alert(1)</script>",
    [
      {
        id: "first<&",
        environment: "linux<&",
        shard: "one<&",
        attempt: 1,
        cases: [key],
      },
      {
        id: "retry",
        environment: "linux<&",
        shard: "one<&",
        attempt: 2,
        cases: [key],
      },
      {
        id: "empty",
        environment: "linux<&",
        shard: "empty",
        attempt: 1,
        cases: [],
      },
    ],
  )
  let ledger = @ledger.Ledger::new(plan)
  let sources = [
    "<testsuite><testcase classname='C&lt;&amp;' name='a&lt;&quot;&apos;😀'><failure message='&lt;img src=x onerror=alert(1)&gt;' type='&quot;&apos;'>first &amp; payload</failure><error>second payload</error><error><![CDATA[</pre><script>alert(2)</script>😀]]></error></testcase><system-out><![CDATA[<iframe src='https://example.invalid'>logs</iframe>]]></system-out></testsuite>",
    "<testsuite><testcase classname='C&lt;&amp;' name='a&lt;&quot;&apos;😀'/></testsuite>",
    "<testsuite><system-out>empty report output preserved</system-out></testsuite>",
  ]
  for i, id in ["first<&", "retry", "empty"] {
    if missing && i == 1 {
      continue
    }
    ledger.ingest({
      binding: {
        id,
        run_id: plan.run_id,
        revision: plan.revision,
        environment: "linux<&",
        shard: if i == 2 {
          "empty"
        } else {
          "one<&"
        },
        attempt: if i == 1 {
          2
        } else {
          1
        },
      },
      report: @junit.parse(sources[i]),
    })
  }
  @wire.decode_evidence(@wire.encode_evidence(ledger, deny_recovered=deny))
}

///|
fn render_error(evidence : @wire.Evidence, limit : Int32) -> String {
  try {
    ignore(@report.render_evidence(evidence, max_output_units=limit))
    "accepted"
  } catch {
    @ledger.InputError::Invalid(d) => d.code
  }
}

///|
test "HTML escapes every input keeps all attempts problems raw metadata and empty reports" {
  let evidence = report_evidence()
  let before = evidence.encode()
  let page = @report.render_evidence(evidence)
  assert_true(page.has_prefix("<!doctype html>"))
  assert_true(page.contains("default-src 'none'"))
  assert_true(!page.contains("<script"))
  assert_true(!page.contains("<img"))
  assert_true(!page.contains("<iframe"))
  assert_true(
    page.contains("&lt;/pre&gt;&lt;script&gt;alert(2)&lt;/script&gt;😀"),
  )
  assert_true(page.contains("run&lt;&quot;&#39;&amp;😀"))
  assert_true(page.contains("C&lt;&amp; / a&lt;&quot;&#39;😀"))
  assert_true(page.contains("&lt;img src=x onerror=alert(1)&gt;"))
  assert_true(page.contains("Type: &quot;&#39;"))
  assert_true(page.contains("first &amp; payload"))
  assert_true(page.contains("second payload"))
  assert_true(page.contains("empty report output preserved"))
  assert_true(page.contains("Attempt 1 · error"))
  assert_true(page.contains("Attempt 2 · passed"))
  assert_true(page.contains("recovered_on_retry"))
  assert_true(page.contains("Gate: <strong>passing</strong>"))
  assert_eq(@report.render_evidence(evidence), page)
  assert_eq(@report.render_evidence(@wire.decode_evidence(before)), page)
  let snapshot = evidence.snapshot()
  snapshot.plan.reports.clear()
  let first = snapshot.documents
    .iter()
    .find_first(document => document.binding.id == "first<&")
    .unwrap()
  first.report.cases[0].problems.clear()
  assert_eq(evidence.encode(), before)
}

///|
test "HTML shows missing reports and cases before failures and preserves recovery policy" {
  let page = @report.render_evidence(report_evidence(missing=true))
  assert_true(page.contains("Gate: <strong>incomplete</strong>"))
  assert_true(page.contains("Missing report: retry"))
  assert_true(page.contains("Missing testcase in retry: C&lt;&amp;"))
  assert_true(page.contains("Report not received."))
  let strict = @report.render_evidence(report_evidence(deny=true))
  assert_true(strict.contains("Gate: <strong>failing</strong>"))
  assert_true(strict.contains("deny recovered tests"))
}

///|
test "HTML budgets are inclusive refuse partial output and recover" {
  let evidence = report_evidence()
  let page = @report.render_evidence(evidence)
  assert_eq(
    @report.render_evidence(evidence, max_output_units=page.length()),
    page,
  )
  assert_eq(render_error(evidence, page.length() - 1), "HtmlOutputLimit")
  assert_eq(render_error(evidence, 1), "HtmlOutputLimit")
  assert_eq(render_error(evidence, 0), "HtmlInvalidLimit")
  assert_eq(render_error(evidence, 268435457), "HtmlInvalidLimit")
  assert_eq(@report.render_evidence(evidence), page)
}
