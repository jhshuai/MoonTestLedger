///|
fn plan_source(
  attempt~ : String = "1",
  schema~ : String = "1",
  extra~ : String = "",
) -> String {
  "{\"schema\":" +
  schema +
  ",\"run_id\":\"run-42\",\"revision\":\"commit-a\",\"reports\":[{\"id\":\"report\",\"environment\":\"linux\",\"shard\":\"main\",\"attempt\":" +
  attempt +
  ",\"cases\":[{\"classname\":\"Suite\",\"name\":\"a\"}]}]" +
  extra +
  "}"
}

///|
fn bundle_source(
  attempt~ : String = "1",
  schema~ : String = "1",
  extra~ : String = "",
) -> String {
  "{\"schema\":" +
  schema +
  ",\"documents\":[{\"id\":\"report\",\"run_id\":\"run-42\",\"revision\":\"commit-a\",\"environment\":\"linux\",\"shard\":\"main\",\"attempt\":" +
  attempt +
  ",\"path\":\"reports/result.xml\"}]" +
  extra +
  "}"
}

///|
fn plan_error(
  source : String,
  limits~ : @ledger.Limits = @ledger.Limits::default(),
) -> @ledger.Diagnostic raise {
  let error = try {
    let _ = @wire.decode_plan(source, limits~)
    None
  } catch {
    @ledger.InputError::Invalid(diagnostic) => Some(diagnostic)
  }
  match error {
    Some(diagnostic) => diagnostic
    None => fail("Expected the plan to be rejected")
  }
}

///|
fn bundle_error(
  source : String,
  limits~ : @ledger.Limits = @ledger.Limits::default(),
) -> @ledger.Diagnostic raise {
  let error = try {
    let _ = @wire.decode_bundle(source, limits~)
    None
  } catch {
    @ledger.InputError::Invalid(diagnostic) => Some(diagnostic)
  }
  match error {
    Some(diagnostic) => diagnostic
    None => fail("Expected the bundle to be rejected")
  }
}

///|
test "plan serialization roundtrips exact identities and every supported field" {
  let names = [
    "a", " a ", "A", "GET /api [empty]", "quote\"slash\\", "multi\nline\ttest", "类😀&<>💡",
  ]
  let cases : Array[@ledger.CaseKey] = names.map(name => {
    classname: "Api\"\\类😀",
    name,
  })
  let plan = @ledger.RunPlan::new("run-42 / nightly", "abcdef123", [
    {
      id: "retry",
      environment: "windows x64",
      shard: "shard/1",
      attempt: 2,
      cases: [cases[0], cases[6]],
    },
    {
      id: "baseline",
      environment: "windows x64",
      shard: "shard/1",
      attempt: 1,
      cases,
    },
  ])
  let encoded = @wire.encode_plan(plan)
  assert_eq(@wire.decode_plan(encoded), plan)
  assert_eq(@wire.encode_plan(@wire.decode_plan(encoded)), encoded)
  assert_eq(plan.reports[0].cases, cases)
  // Stable rendering is tested across independently constructed valid plans.
  assert_eq(
    @wire.encode_plan(
      @ledger.RunPlan::new(plan.run_id, plan.revision, [
        plan.reports[1],
        plan.reports[0],
      ]),
    ),
    encoded,
  )
}

///|
test "bundle roundtrip preserves portable paths producer bindings and repeated entries" {
  let first : @wire.ReportFile = {
    binding: {
      id: "report",
      run_id: "run-42",
      revision: "commit-a",
      environment: "windows",
      shard: "shard 1",
      attempt: 1,
    },
    path: "artifacts\\类😀\\result.xml",
  }
  let second : @wire.ReportFile = {
    binding: { ..first.binding, id: "retry", attempt: 2, },
    path: "/tmp/reports/result \"two\".xml",
  }
  let bundle : @wire.Bundle = { documents: [first, second, first], }
  let encoded = @wire.encode_bundle(bundle)
  assert_eq(@wire.decode_bundle(encoded), bundle)
  assert_eq(@wire.encode_bundle(@wire.decode_bundle(encoded)), encoded)
  assert_eq(@wire.decode_bundle("{\"schema\":1,\"documents\":[]}").documents, [])
}

///|
test "decoded duplicate object keys are rejected at root and nested object boundaries" {
  let duplicate_root =
    #|{
    #|  "schema": 1,
    #|  "\u0073chema": 1,
    #|  "run_id": "run-42",
    #|  "revision": "commit-a",
    #|  "reports": []
    #|}
  let diagnostic = plan_error(duplicate_root)
  assert_eq(diagnostic.code, "DuplicateJsonKey")
  assert_eq(diagnostic.line, 3)
  assert_eq(diagnostic.column, 3)
  for
    source in [
      plan_source(extra=",\"run_id\":\"other\""),
      (
        #|{"schema":1,"run_id":"run-42","revision":"commit-a","reports":[{"id":"report","environment":"linux","shard":"main","attempt":1,"cases":[{"classname":"Suite","name":"a","\u006Eame":"b"}]}]}
      ),
      (
        #|{"schema":1,"run_id":"run-42","revision":"commit-a","reports":[{"id":"report","environment":"linux","shard":"main","attempt":1,"cases":[{"classname":"Suite","name":"a"}],"attempt":2}]}
      ),
    ] {
    assert_eq(plan_error(source).code, "DuplicateJsonKey")
  }
  assert_eq(
    bundle_error(bundle_source(extra=",\"documents\":[]")).code,
    "DuplicateJsonKey",
  )
  // Repeating the same key in sibling objects is valid, rather than a global collision.
  let sibling = @wire.decode_bundle(
    @wire.encode_bundle({
      documents: [
        {
          binding: {
            id: "a",
            run_id: "run",
            revision: "rev",
            environment: "linux",
            shard: "one",
            attempt: 1,
          },
          path: "a.xml",
        },
        {
          binding: {
            id: "b",
            run_id: "run",
            revision: "rev",
            environment: "linux",
            shard: "two",
            attempt: 1,
          },
          path: "b.xml",
        },
      ],
    }),
  )
  assert_eq(sibling.documents.length(), 2)
}

///|
test "unknown fields and versions cannot disappear during decoding" {
  assert_eq(
    plan_error(plan_source(extra=",\"vendor\":{\"keep_me\":true}")).code,
    "UnknownField",
  )
  assert_eq(
    bundle_error(bundle_source(extra=",\"vendor\":1")).code,
    "UnknownField",
  )
  for
    source in [
      (
        #|{"schema":1,"run_id":"run","revision":"rev","reports":[{"id":"a","environment":"linux","shard":"main","attempt":1,"cases":[{"classname":"C","name":"n","parameters":[1]}]}]}
      ),
      (
        #|{"schema":1,"run_id":"run","revision":"rev","reports":[{"id":"a","environment":"linux","shard":"main","attempt":1,"cases":[{"classname":"C","name":"n"}],"producer":"pytest"}]}
      ),
    ] {
    assert_eq(plan_error(source).code, "UnknownField")
  }
  let unknown_bundle =
    #|{"schema":1,"documents":[{"id":"a","run_id":"run","revision":"rev","environment":"linux","shard":"main","attempt":1,"path":"a.xml","sha256":"unverified"}]}
  assert_eq(bundle_error(unknown_bundle).code, "UnknownField")
  assert_eq(plan_error(plan_source(schema="2")).code, "UnsupportedSchema")
  assert_eq(bundle_error(bundle_source(schema="2")).code, "UnsupportedSchema")
  assert_eq(
    plan_error("{\"run_id\":\"run\",\"revision\":\"rev\",\"reports\":[]}").code,
    "MissingField",
  )
  assert_eq(bundle_error("{\"schema\":1}").path, "$/documents")
}

///|
test "schema and attempts require exact positive 32 bit integers" {
  for
    number in [
      "0", "-1", "1.5", "2147483648", "9007199254740992", "\"1\"", "null", "true",
    ] {
    assert_eq(plan_error(plan_source(attempt=number)).code, "ExpectedInteger")
    assert_eq(
      bundle_error(bundle_source(attempt=number)).code,
      "ExpectedInteger",
    )
    assert_eq(plan_error(plan_source(schema=number)).code, "ExpectedInteger")
  }
  // Exact integer-valued JSON numbers are permitted; their spellings are not identities.
  assert_eq(
    @wire.decode_plan(plan_source(attempt="1.0", schema="1e0")).reports[0].attempt,
    1,
  )
  assert_eq(
    @wire.decode_bundle(bundle_source(attempt="2147483647")).documents[0].binding.attempt,
    2147483647,
  )
  assert_eq(
    plan_error(plan_source(attempt="2147483647")).code,
    "AttemptSequence",
  )
}

///|
test "malformed or structurally invalid JSON is rejected then the decoder recovers" {
  for
    source in [
      "", "{", "{} trailing", "{\"schema\":01}", "{\"schema\":1,}", "{\"schema\":1/* comment */}",
      "{\"schema\":NaN}",
    ] {
    assert_eq(plan_error(source).code, "InvalidJson")
    assert_eq(bundle_error(source).code, "InvalidJson")
  }
  assert_eq(plan_error(plan_source(schema="1e9999")).code, "ExpectedInteger")
  assert_eq(
    bundle_error(bundle_source(attempt="1e9999")).code,
    "ExpectedInteger",
  )
  for source in ["null", "true", "1", "\"string\"", "[]"] {
    assert_eq(plan_error(source).code, "ExpectedObject")
  }
  assert_eq(
    bundle_error("{\"schema\":1,\"documents\":{}}").code,
    "ExpectedArray",
  )
  assert_eq(
    plan_error(
      "{\"schema\":1,\"run_id\":42,\"revision\":\"rev\",\"reports\":[]}",
    ).code,
    "ExpectedString",
  )
  assert_eq(@wire.decode_plan(plan_source()).reports[0].cases[0].name, "a")
  assert_eq(
    @wire.decode_bundle(bundle_source()).documents[0].path,
    "reports/result.xml",
  )
}

///|
test "JSON nesting guard ignores punctuation in strings and has inclusive depth 64" {
  let mut at_limit = "0"
  for _ in 0..<64 {
    at_limit = "[" + at_limit + "]"
  }
  assert_eq(plan_error(at_limit).code, "ExpectedObject")
  assert_eq(plan_error("[" + at_limit + "]").code, "JsonDepthLimit")
  let brackets = "[{\"\\" + at_limit + "]}"
  let bundle : @wire.Bundle = {
    documents: [
      {
        binding: {
          id: "a",
          run_id: "run",
          revision: "rev",
          environment: "linux",
          shard: "main",
          attempt: 1,
        },
        path: brackets,
      },
    ],
  }
  assert_eq(@wire.decode_bundle(@wire.encode_bundle(bundle)), bundle)
}

///|
test "JSON source inventories and identifiers respect limits without truncation" {
  let defaults = @ledger.Limits::default()
  let source = plan_source()
  assert_eq(
    @wire.decode_plan(source, limits={
      ..defaults,
      max_source_units: source.length(),
      max_reports: 1,
      max_cases: 1,
    }).reports.length(),
    1,
  )
  assert_eq(
    plan_error(source, limits={
      ..defaults,
      max_source_units: source.length() - 1,
    }).code,
    "SourceLimit",
  )
  let two_reports = @ledger.RunPlan::new("run", "rev", [
    {
      id: "a",
      environment: "linux",
      shard: "one",
      attempt: 1,
      cases: [{ classname: "C", name: "n", }],
    },
    {
      id: "b",
      environment: "linux",
      shard: "two",
      attempt: 1,
      cases: [{ classname: "C", name: "m", }],
    },
  ])
  let encoded = @wire.encode_plan(two_reports)
  assert_eq(
    plan_error(encoded, limits={ ..defaults, max_reports: 1, }).code,
    "ReportLimit",
  )
  assert_eq(
    plan_error(encoded, limits={ ..defaults, max_cases: 1, }).code,
    "CaseLimit",
  )
  assert_eq(
    plan_error(source, limits={ ..defaults, max_depth: 0, }).code,
    "InvalidLimit",
  )
  let invalid_bundle : @wire.Bundle = {
    documents: [
      {
        binding: {
          id: "",
          run_id: "run",
          revision: "rev",
          environment: "linux",
          shard: "main",
          attempt: 1,
        },
        path: "a.xml",
      },
    ],
  }
  assert_eq(
    bundle_error(@wire.encode_bundle(invalid_bundle)).code,
    "InvalidText",
  )
  assert_eq(
    bundle_error(
      @wire.encode_bundle({
        documents: [
          {
            binding: { ..invalid_bundle.documents[0].binding, id: "a", },
            path: "bad\u0000path",
          },
        ],
      }),
    ).code,
    "InvalidText",
  )
  assert_eq(
    bundle_error(
      @wire.encode_bundle({
        documents: [
          {
            ..invalid_bundle.documents[0],
            binding: { ..invalid_bundle.documents[0].binding, id: "a", },
          },
          {
            ..invalid_bundle.documents[0],
            binding: { ..invalid_bundle.documents[0].binding, id: "b", },
          },
        ],
      }),
      limits={ ..defaults, max_reports: 1, },
    ).code,
    "ReportLimit",
  )
}

///|
fn summary_fixture(reverse : Bool) -> @ledger.Summary raise @ledger.InputError {
  let a : @ledger.CaseKey = { classname: "C", name: "a", }
  let b : @ledger.CaseKey = { classname: "C", name: "b", }
  let baseline : @ledger.ExpectedReport = {
    id: "baseline",
    environment: "linux",
    shard: "main",
    attempt: 1,
    cases: if reverse {
      [b, a]
    } else {
      [a, b]
    },
  }
  let retry : @ledger.ExpectedReport = {
    ..baseline,
    id: "retry",
    attempt: 2,
    cases: [a],
  }
  let plan = @ledger.RunPlan::new(
    "run",
    "rev",
    if reverse {
      [retry, baseline]
    } else {
      [baseline, retry]
    },
  )
  let ledger = @ledger.Ledger::new(plan)
  let one : @ledger.Document = {
    binding: {
      id: "baseline",
      run_id: "run",
      revision: "rev",
      environment: "linux",
      shard: "main",
      attempt: 1,
    },
    report: {
      source: "raw baseline",
      cases: [
        {
          key: a,
          outcome: @ledger.Outcome::Failure,
          problems: [
            {
              kind: @ledger.ProblemKind::Failure,
              message: Some("a \"quote\""),
              type_name: None,
              text: "line1\nline2😀",
              path: "/case/failure",
              line: 2,
              column: 7,
            },
          ],
          skipped_reason: None,
          path: "/case",
          line: 1,
          column: 3,
        },
        {
          key: b,
          outcome: @ledger.Outcome::Skip,
          problems: [],
          skipped_reason: Some("offline"),
          path: "/case[2]",
          line: 4,
          column: 3,
        },
      ],
    },
  }
  let two : @ledger.Document = {
    binding: { ..one.binding, id: "retry", attempt: 2, },
    report: {
      source: "raw retry",
      cases: [
        { ..one.report.cases[0], outcome: @ledger.Outcome::Pass, problems: [], },
      ],
    },
  }
  if reverse {
    ledger.ingest(two)
    ledger.ingest(one)
  } else {
    ledger.ingest(one)
    ledger.ingest(two)
  }
  ledger.summary()
}

///|
test "summary JSON is deterministic across case report and ingestion permutations" {
  let summary = summary_fixture(false)
  let encoded = @wire.encode_summary(summary)
  assert_eq(encoded, @wire.encode_summary(summary_fixture(true)))
  let json = @json.parse(encoded)
  guard json is Object(fields) else { fail("Expected object") }
  assert_eq(fields["complete"], Json::boolean(true))
  assert_eq(fields["exit_code"], Json::number(0))
  guard fields["cases"] is Array(cases) else { fail("Expected case list") }
  guard cases[0] is Object(first) else { fail("Expected case") }
  assert_eq(first["verdict"], Json::string("recovered_on_retry"))
  guard first["attempts"] is Array(attempts) else { fail("Expected attempts") }
  guard attempts[0] is Object(initial) else { fail("Expected initial attempt") }
  guard initial["problems"] is Array(problems) else {
    fail("Expected problems")
  }
  guard problems[0] is Object(problem) else {
    fail("Expected retained problem")
  }
  assert_eq(problem["text"], Json::string("line1\nline2😀"))
  assert_eq(problem["message"], Json::string("a \"quote\""))
  assert_eq(problem["type"], Json::null())
  assert_eq(problem["line"], Json::number(2))
  assert_eq(problem["column"], Json::number(7))
  guard @json.parse(@wire.encode_summary(summary, deny_recovered=true))
    is Object(denied) else {
    fail("Expected object")
  }
  assert_eq(denied["exit_code"], Json::number(1))
}

///|
test "diagnostic JSON preserves actionable location and escaped text" {
  let diagnostic : @ledger.Diagnostic = {
    code: "Unsupported",
    report_id: "report.xml",
    path: "/testsuite[1]/testcase[2]",
    message: "拒绝 \"flaky\"\n保留证据",
    line: 12,
    column: 5,
  }
  let rendered = @wire.encode_diagnostic(diagnostic)
  guard @json.parse(rendered) is Object(fields) else {
    fail("Expected diagnostic object")
  }
  assert_eq(fields["schema"], Json::number(1))
  guard fields["error"] is Object(error) else { fail("Expected error object") }
  assert_eq(error["code"], Json::string(diagnostic.code))
  assert_eq(error["report_id"], Json::string(diagnostic.report_id))
  assert_eq(error["path"], Json::string(diagnostic.path))
  assert_eq(error["message"], Json::string(diagnostic.message))
  assert_eq(error["line"], Json::number(12))
  assert_eq(error["column"], Json::number(5))
}
