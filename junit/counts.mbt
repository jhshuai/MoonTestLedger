///|
fn declared_count(
  value : String,
  report_id : String,
  path : String,
  line : Int32,
  column : Int32,
) -> Int32 raise @ledger.InputError {
  if value.is_empty() {
    reject(
      "MTL_JUNIT_COUNT", report_id, path, "Expected a non-negative decimal count",
      line, column,
    )
  }
  for character in value; number = 0 {
    if character < '0' || character > '9' {
      reject(
        "MTL_JUNIT_COUNT", report_id, path, "Expected a non-negative decimal count",
        line, column,
      )
    }
    let digit = character.to_int() - '0'.to_int()
    if number > (2147483647 - digit) / 10 {
      reject(
        "MTL_JUNIT_COUNT", report_id, path, "Declared count exceeds Int32", line,
        column,
      )
    }
    continue number * 10 + digit
  } nobreak {
    number
  }
}

///|
fn ParserState::new_suite(
  self : ParserState,
  element : @xml.XmlElement,
  path : String,
) -> SuiteState raise @ledger.InputError {
  let declared : Map[String, Int32] = Map([])
  for attribute in element.attributes {
    match attribute.name {
      "tests" | "failures" | "errors" | "skipped" | "disabled" => {
        let count = declared_count(
          attribute.value,
          self.report_id,
          path + "/@" + attribute.name,
          attribute.value_span.start.line,
          attribute.value_span.start.column,
        )
        if attribute.name == "disabled" && count != 0 {
          self.reject(
            "MTL_JUNIT_UNSUPPORTED",
            path + "/@disabled",
            "A nonzero disabled count has no supported testcase outcome representation",
            attribute.value_span.start.line,
            attribute.value_span.start.column,
          )
        }
        if attribute.name != "disabled" {
          declared.set(attribute.name, count)
        }
      }
      _ => ()
    }
  }
  { declared, counts: { tests: 0, failures: 0, errors: 0, skipped: 0, }, }
}

///|
fn ParserState::verify_counts(
  self : ParserState,
  frame : Frame,
  suite : SuiteState,
) -> Unit raise @ledger.InputError {
  for field in ["tests", "failures", "errors", "skipped"] {
    match suite.declared.get(field) {
      None => ()
      Some(declared) => {
        let actual = match field {
          "tests" => suite.counts.tests
          "failures" => suite.counts.failures
          "errors" => suite.counts.errors
          _ => suite.counts.skipped
        }
        if declared != actual {
          self.reject(
            "MTL_JUNIT_COUNT",
            frame.path + "/@" + field,
            "Declared \{field}=\{declared}, but descendant testcases contain \{actual}",
            frame.line,
            frame.column,
          )
        }
      }
    }
  }
}

///|
fn ParserState::record_case(
  self : ParserState,
  frame : Frame,
  testcase : CaseState,
) -> Unit raise @ledger.InputError {
  let has_failure = testcase.problems.any(problem => {
    problem.kind == @ledger.ProblemKind::Failure
  })
  let has_error = testcase.problems.any(problem => {
    problem.kind == @ledger.ProblemKind::Error
  })
  if testcase.has_skip && (has_failure || has_error) {
    self.reject(
      "MTL_JUNIT_AMBIGUOUS",
      frame.path,
      "A testcase combines skipped with failure or error; its outcome is ambiguous",
      frame.line,
      frame.column,
    )
  }
  let outcome = if has_error {
    @ledger.Outcome::Error
  } else if has_failure {
    @ledger.Outcome::Failure
  } else if testcase.has_skip {
    @ledger.Outcome::Skip
  } else {
    @ledger.Outcome::Pass
  }
  self.cases.push({
    key: testcase.key,
    outcome,
    problems: testcase.problems,
    skipped_reason: testcase.skip,
    path: frame.path,
    line: frame.line,
    column: frame.column,
  })
  for ancestor in self.frames {
    match ancestor.kind {
      Suite(suite) => {
        suite.counts.tests += 1
        if has_failure {
          suite.counts.failures += 1
        }
        if has_error {
          suite.counts.errors += 1
        }
        if testcase.has_skip {
          suite.counts.skipped += 1
        }
      }
      _ => ()
    }
  }
}
