///|
fn rejection(
  source : String,
  limits~ : @ledger.Limits = @ledger.Limits::default(),
) -> @ledger.Diagnostic raise {
  let diagnostic = try {
    let _ = @junit.parse(source, report_id="fixture.xml", limits~)
    None
  } catch {
    @ledger.InputError::Invalid(diagnostic) => Some(diagnostic)
  }
  match diagnostic {
    Some(diagnostic) => {
      assert_eq(diagnostic.report_id, "fixture.xml")
      assert_true(diagnostic.line >= 1)
      assert_true(diagnostic.column >= 1)
      diagnostic
    }
    None => fail("Expected a rejected JUnit document")
  }
}

///|
test "suite and collection roots contain exact result identities" {
  let source =
    #|<?xml version="1.0" encoding="UTF-8"?>
    #|<testsuites tests="2" failures="0" errors="0" skipped="1">
    #|  <testsuite name="api" tests="2" failures="0" errors="0" skipped="1">
    #|    <testcase classname="ApiTest" name="GET /items [empty]" time="0.014"/>
    #|    <testcase name="offline"><skipped message="network unavailable">retry tomorrow</skipped></testcase>
    #|  </testsuite>
    #|</testsuites>
  let report = @junit.parse(source)
  assert_eq(report.source, source)
  assert_eq(report.cases.length(), 2)
  let first = report.cases[0]
  assert_eq(first.key.classname, "ApiTest")
  assert_eq(first.key.name, "GET /items [empty]")
  assert_eq(first.outcome, @ledger.Outcome::Pass)
  assert_eq(first.path, "/testsuites[1]/testsuite[1]/testcase[1]")
  assert_eq(first.line, 4)
  assert_eq(first.column, 5)
  assert_eq(report.cases[1].key.classname, "")
  assert_eq(report.cases[1].outcome, @ledger.Outcome::Skip)
  assert_eq(
    report.cases[1].skipped_reason,
    Some("network unavailable\nretry tomorrow"),
  )
  assert_eq(@junit.parse("<testsuite/>").cases, [])
}

///|
test "all failure and error payloads survive with per-case counter semantics" {
  let source =
    #|<testsuite tests="1" failures="1" errors="1" skipped="0">
    #|  <testcase classname="Order" name="commit">
    #|    <failure message="one &amp; two" type="AssertionError">expected &lt;2&gt;<![CDATA[ but <3>]]></failure>
    #|    <failure>second assertion</failure>
    #|    <error type="Timeout">socket timed out</error>
    #|  </testcase>
    #|</testsuite>
  let report = @junit.parse(source)
  let testcase = report.cases[0]
  assert_eq(testcase.outcome, @ledger.Outcome::Error)
  assert_eq(testcase.problems.length(), 3)
  assert_eq(testcase.problems[0].kind, @ledger.ProblemKind::Failure)
  assert_eq(testcase.problems[0].message, Some("one & two"))
  assert_eq(testcase.problems[0].type_name, Some("AssertionError"))
  assert_eq(testcase.problems[0].text, "expected <2> but <3>")
  assert_eq(testcase.problems[1].text, "second assertion")
  assert_eq(testcase.problems[2].kind, @ledger.ProblemKind::Error)
  assert_eq(testcase.problems[2].path, "/testsuite[1]/testcase[1]/error[1]")
  assert_eq(testcase.problems[2].line, 5)
  assert_eq(report.source, source)
}

///|
test "nested suites aggregate descendants and preserve sibling paths" {
  let report = @junit.parse(
    "<testsuite tests='3' failures='1'><testsuite tests='2' failures='1'><testcase name='a'/><testcase name='b'><failure/></testcase></testsuite><testsuite tests='1'><testcase name='c'/></testsuite></testsuite>",
  )
  assert_eq(report.cases.map(testcase => testcase.key.name), ["a", "b", "c"])
  assert_eq(report.cases[2].path, "/testsuite[1]/testsuite[2]/testcase[1]")
  let diagnostic = rejection(
    "<testsuite tests='1'><testsuite tests='1'><testcase name='a'/></testsuite><testcase name='b'/></testsuite>",
  )
  assert_eq(diagnostic.code, "MTL_JUNIT_COUNT")
  assert_eq(diagnostic.path, "/testsuite[1]/@tests")
}

///|
test "source retention and deterministic parsing include inert metadata" {
  let source =
    #|<!-- producer comment -->
    #|<testsuite tests="1" hostname="ci.example">
    #|  <properties><property name="build" value="123"/><vendor:opaque xmlns:vendor="urn:private"><failure/></vendor:opaque></properties>
    #|  <testcase classname="类😀" name="space  and &amp; entity">
    #|    <system-out><![CDATA[<logs>💡</logs>]]></system-out>
    #|    <system-err>nothing &lt;lost&gt;</system-err>
    #|  </testcase>
    #|</testsuite>
    #|<?producer done?>
  let first = @junit.parse(source)
  let second = @junit.parse(source)
  assert_eq(first, second)
  assert_eq(first.source, source)
  assert_eq(first.cases[0].key.classname, "类😀")
  assert_eq(first.cases[0].key.name, "space  and & entity")
  assert_eq(first.cases[0].outcome, @ledger.Outcome::Pass)
}

///|
test "decoded equivalent identities are rejected while exact distinctions remain" {
  let diagnostic = rejection(
    "<testsuite><testcase classname='C' name='A&amp;B'/><testcase classname='C' name='&#65;&#x26;B'/></testsuite>",
  )
  assert_eq(diagnostic.code, "MTL_JUNIT_IDENTITY")
  assert_eq(diagnostic.path, "/testsuite[1]/testcase[2]")
  let report = @junit.parse(
    "<testsuite><testcase name='a'/><testcase name=' a'/><testcase name='a' classname='C'/><testcase name='A'/></testsuite>",
  )
  assert_eq(report.cases.length(), 4)
}

///|
test "missing and empty testcase names cannot be invented" {
  for
    source in [
      "<testsuite><testcase/></testsuite>", "<testsuite><testcase name=''/></testsuite>",
    ] {
    let diagnostic = rejection(source)
    assert_eq(diagnostic.code, "MTL_JUNIT_IDENTITY")
    assert_eq(diagnostic.path, "/testsuite[1]/testcase[1]/@name")
  }
}

///|
test "declared counts reject invalid decimal overflow and mismatches" {
  for
    value in [
      "", "-1", "+1", "1.0", " 1", "2147483648", "999999999999999999999999",
    ] {
    assert_eq(
      rejection("<testsuite tests='" + value + "'/>").code,
      "MTL_JUNIT_COUNT",
    )
  }
  assert_eq(
    @junit.parse(
      "<testsuite tests='0000' failures='0' errors='0' skipped='0' disabled='0'/>",
    ).cases.length(),
    0,
  )
  for field in ["tests", "failures", "errors", "skipped"] {
    let diagnostic = rejection("<testsuite " + field + "='1'/>")
    assert_eq(diagnostic.code, "MTL_JUNIT_COUNT")
    assert_eq(diagnostic.path, "/testsuite[1]/@" + field)
  }
  assert_eq(
    rejection("<testsuite disabled='1'/>").code,
    "MTL_JUNIT_UNSUPPORTED",
  )
}

///|
test "malformed XML is consumed through eof and reports authored location" {
  for
    source in [
      "<testsuite><testcase name='a'></testsuite></testcase>", "<testsuite/><testsuite/>",
      "<testsuite/>trailing", "<testsuite><testcase name='first' name='second'/></testsuite>",
      "<testsuite><testcase name='&#0;'/></testsuite>", "<testsuite>", "",
    ] {
    assert_eq(rejection(source).code, "MTL_JUNIT_XML")
  }
  let diagnostic = rejection("<testsuite>\n <testcase name='x'></testsuite>")
  assert_eq(diagnostic.line, 2)
}

///|
test "DTD and XML profile mismatches are explicit rejections" {
  for
    source in [
      "<!DOCTYPE testsuite><testsuite/>", "<!DOCTYPE testsuite [<!ENTITY x 'payload'>]><testsuite/>",
      "<!DOCTYPE testsuite SYSTEM 'file:///private'><testsuite/>", "<?xml version='1.1'?><testsuite/>",
      "<?xml version='1.0' encoding='ISO-8859-1'?><testsuite/>", "<x:testsuite xmlns:x='urn:junit'/>",
      "<testsuite xmlns='urn:junit'/>", "<testsuite><testcase name='a' xmlns='urn:junit'/></testsuite>",
    ] {
    assert_eq(rejection(source).code, "MTL_JUNIT_UNSUPPORTED")
  }
}

///|
test "unsupported retry outcome semantics never become passes" {
  for
    outcome in [
      "flakyFailure", "flakyError", "rerunFailure", "rerunError", "warning", "ignored",
    ] {
    let diagnostic = rejection(
      "<testsuite><testcase name='x'><" + outcome + "/></testcase></testsuite>",
    )
    assert_eq(diagnostic.code, "MTL_JUNIT_UNSUPPORTED")
    assert_eq(diagnostic.path, "/testsuite[1]/testcase[1]/" + outcome + "[1]")
  }
  for
    attribute in [
      "status", "result", "outcome", "disabled", "successful", "custom",
    ] {
    assert_eq(
      rejection(
        "<testsuite><testcase name='x' " +
        attribute +
        "='unknown'/></testsuite>",
      ).code,
      "MTL_JUNIT_UNSUPPORTED",
    )
  }
  for
    source in [
      "<testsuites><testcase name='x'/></testsuites>", "<report/>", "<testsuite>not a result</testsuite>",
      "<testsuite><testcase name='x'><failure><detail/></failure></testcase></testsuite>",
    ] {
    assert_eq(rejection(source).code, "MTL_JUNIT_UNSUPPORTED")
  }
}

///|
test "skip cannot conceal failure or error and duplicate skip is ambiguous" {
  for
    markers in [
      "<failure/><skipped/>", "<skipped/><error/>", "<skipped/><skipped/>",
    ] {
    assert_eq(
      rejection(
        "<testsuite><testcase name='x'>" + markers + "</testcase></testsuite>",
      ).code,
      "MTL_JUNIT_AMBIGUOUS",
    )
  }
  let skipped = @junit.parse(
      "<testsuite skipped='1'><testcase name='x'><skipped/></testcase></testsuite>",
    ).cases[0]
  assert_eq(skipped.outcome, @ledger.Outcome::Skip)
  assert_eq(skipped.skipped_reason, None)
}

///|
test "recover after rejection with no leaked parser state" {
  let _ = rejection(
    "<testsuite><testcase name='x'><flakyFailure/></testcase></testsuite>",
  )
  let report = @junit.parse(
    "<testsuite tests='1'><testcase name='x'/></testsuite>",
  )
  assert_eq(report.cases.length(), 1)
  assert_eq(report.cases[0].outcome, @ledger.Outcome::Pass)
}

///|
test "resource caps have inclusive boundaries and count inert nodes" {
  let defaults = @ledger.Limits::default()
  let source = "<testsuite><testcase name='x'/></testsuite>"
  let exact_source = { ..defaults, max_source_units: source.length(), }
  assert_eq(@junit.parse(source, limits=exact_source).cases.length(), 1)
  assert_eq(
    rejection(source, limits={
      ..defaults,
      max_source_units: source.length() - 1,
    }).code,
    "MTL_JUNIT_LIMIT",
  )
  assert_eq(
    @junit.parse(source, limits={ ..defaults, max_cases: 1, }).cases.length(),
    1,
  )
  assert_eq(
    rejection(
      "<testsuite><testcase name='x'/><testcase name='y'/></testsuite>",
      limits={ ..defaults, max_cases: 1, },
    ).code,
    "MTL_JUNIT_LIMIT",
  )
  assert_eq(
    @junit.parse(source, limits={
      ..defaults,
      max_depth: 2,
      max_events: 4,
      max_attributes: 1,
    }).cases.length(),
    1,
  )
  assert_eq(
    rejection(source, limits={ ..defaults, max_depth: 1, }).code,
    "MTL_JUNIT_LIMIT",
  )
  assert_eq(
    rejection(source, limits={ ..defaults, max_events: 3, }).code,
    "MTL_JUNIT_LIMIT",
  )
  assert_eq(
    rejection("<testsuite><testcase name='x' classname='C'/></testsuite>", limits={
      ..defaults,
      max_attributes: 1,
    }).code,
    "MTL_JUNIT_LIMIT",
  )
  let one_problem = "<testsuite><testcase name='x'><failure/></testcase></testsuite>"
  assert_eq(
    @junit.parse(one_problem, limits={ ..defaults, max_problems: 1, }).cases[0].problems.length(),
    1,
  )
  assert_eq(
    rejection(
      "<testsuite><testcase name='x'><failure/><error/></testcase></testsuite>",
      limits={ ..defaults, max_problems: 1, },
    ).code,
    "MTL_JUNIT_LIMIT",
  )
  assert_eq(
    rejection(
      "<testsuite><properties><property><deep/></property></properties></testsuite>",
      limits={ ..defaults, max_depth: 3, },
    ).code,
    "MTL_JUNIT_LIMIT",
  )
}
