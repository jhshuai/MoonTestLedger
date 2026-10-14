///|
test "bundle paths use the containing directory and preserve absolute paths" {
  assert_eq(
    report_path("examples/bundle.json", "reports/junit.xml"),
    "examples/reports/junit.xml",
  )
  assert_eq(
    report_path("bundle.json", "reports\\junit.xml"),
    "reports/junit.xml",
  )
  assert_eq(
    report_path("C:\\build\\bundle.json", "output.xml"),
    "C:\\build\\output.xml",
  )
  assert_eq(
    report_path("路径😀/bundle.json", "results.xml"),
    "路径😀/results.xml",
  )
  for
    absolute in [
      "/tmp/results.xml", "C:/results.xml", "D:\\results.xml", "\\\\host\\share\\results.xml",
    ] {
    assert_eq(report_path("relative/bundle.json", absolute), absolute)
  }
}

///|
async test "bounded file reader refuses malformed UTF-8 and recovers" {
  let directory = @fs.tmpdir(prefix="moontestledger-reader")
  defer @fs.rmdir(directory)
  let path = directory + "/report.xml"
  defer @fs.remove(path)
  @fs.write_file(path, b"\xff")
  let diagnostic = try {
    ignore(read_text(path, @ledger.Limits::default()))
    None
  } catch {
    @ledger.InputError::Invalid(diagnostic) => Some(diagnostic)
    error => fail(error.to_string())
  }
  guard diagnostic is Some(diagnostic) else {
    fail("Malformed UTF-8 was accepted")
  }
  assert_eq(diagnostic.code, "InvalidUtf8")
  assert_eq(diagnostic.path, path)
  let source = "\u{FEFF}<testsuite><testcase name='正确😀'/></testsuite>"
  @fs.write_file(path, source)
  assert_eq(read_text(path, @ledger.Limits::default()), source)
}

///|
async test "byte cap is inclusive and file read failures are actionable" {
  let directory = @fs.tmpdir(prefix="moontestledger-limit")
  defer @fs.rmdir(directory)
  let path = directory + "/input"
  defer @fs.remove(path)
  let limits = { ..@ledger.Limits::default(), max_source_units: 1, }
  @fs.write_file(path, "1234")
  assert_eq(read_text(path, limits), "1234")
  @fs.write_file(path, "12345")
  let error_code = try {
    ignore(read_text(path, limits))
    "accepted"
  } catch {
    @ledger.InputError::Invalid(diagnostic) => diagnostic.code
    error => fail(error.to_string())
  }
  assert_eq(error_code, "FileLimit")
  let missing = try {
    ignore(read_text(directory + "/absent", limits))
    "accepted"
  } catch {
    @ledger.InputError::Invalid(diagnostic) => diagnostic.code
    error => fail(error.to_string())
  }
  assert_eq(missing, "FileRead")
}
