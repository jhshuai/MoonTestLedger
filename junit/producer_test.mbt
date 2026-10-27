///|
test "Surefire 3.0.2 schema annotation preserves source and outcome validation" {
  let header = "<testsuite xmlns:xsi='http://www.w3.org/2001/XMLSchema-instance' xsi:noNamespaceSchemaLocation='https://maven.apache.org/surefire/maven-surefire-plugin/xsd/surefire-test-report.xsd' version='3.0.2' tests='1' errors='1'>"
  let source = header +
    "<testcase classname='Example' name='a[0]'><error type='IllegalStateException'>original stack</error></testcase></testsuite>"
  let parsed = @junit.parse(source)
  assert_eq(parsed.source, source)
  assert_eq(parsed.cases[0].key.name, "a[0]")
  assert_eq(parsed.cases[0].outcome, @ledger.Outcome::Error)
  assert_eq(parsed.cases[0].problems[0].text, "original stack")
  try @junit.parse(source.replace(old="errors='1'", new="errors='0'")) catch {
    @ledger.InputError::Invalid(diagnostic) =>
      assert_eq(diagnostic.code, "MTL_JUNIT_COUNT")
  } noraise {
    _ => fail("schema annotations must not bypass counter validation")
  }
}

///|
test "schema annotation is closed and root-only; retry outcomes never flatten" {
  let header = "<testsuite xmlns:xsi='http://www.w3.org/2001/XMLSchema-instance' xsi:noNamespaceSchemaLocation='https://maven.apache.org/surefire/maven-surefire-plugin/xsd/surefire-test-report.xsd' version='3.0.2'>"
  let valid = header + "<testcase name='ok'/></testsuite>"
  for
    invalid in [
      valid.replace(old="3.0.2", new="3.0.1"),
      valid.replace(old="2001/XMLSchema-instance", new="2001/other"),
      valid.replace(
        old="https://maven.apache.org",
        new="https://example.invalid",
      ),
      valid.replace(
        old=" xmlns:xsi='http://www.w3.org/2001/XMLSchema-instance'",
        new="",
      ),
      valid.replace(
        old="version='3.0.2'",
        new="version='3.0.2' xmlns='urn:junit'",
      ),
      valid.replace(
        old="version='3.0.2'",
        new="version='3.0.2' xsi:other='opaque'",
      ),
      "<testsuites>" + valid + "</testsuites>",
      valid.replace(
        old="<testcase name='ok'/>",
        new="<xsi:testcase name='ok'/>",
      ),
      "<testsuite version='3.0.2'/>",
    ] {
    try @junit.parse(invalid) catch {
      @ledger.InputError::Invalid(diagnostic) =>
        assert_eq(diagnostic.code, "MTL_JUNIT_UNSUPPORTED")
    } noraise {
      _ => fail("unrecognized schema annotation must be refused")
    }
    assert_eq(@junit.parse(valid).source, valid)
  }
  for extension in ["flakyFailure", "flakyError", "rerunFailure", "rerunError"] {
    let unsupported = header +
      "<testcase name='retry'><" +
      extension +
      "><stackTrace>first run</stackTrace></" +
      extension +
      "></testcase></testsuite>"
    try @junit.parse(unsupported) catch {
      @ledger.InputError::Invalid(diagnostic) => {
        assert_eq(diagnostic.code, "MTL_JUNIT_UNSUPPORTED")
        assert_true(diagnostic.path.contains(extension))
      }
    } noraise {
      _ => fail("embedded retry semantics must not be discarded")
    }
  }
}
