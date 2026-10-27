///|
fn ParserState::parent(self : ParserState) -> Frame? {
  self.frames.last()
}

///|
fn ParserState::child_path(self : ParserState, name : String) -> String {
  match self.parent() {
    None => "/" + name + "[1]"
    Some(parent) => {
      let index = parent.children.get(name).unwrap_or(0) + 1
      parent.children.set(name, index)
      parent.path + "/" + name + "[" + index.to_string() + "]"
    }
  }
}

///|
fn ParserState::new_case(
  self : ParserState,
  element : @xml.XmlElement,
  path : String,
  position : @xml.SourcePosition,
) -> CaseState raise @ledger.InputError {
  if self.identities.length() >= self.limits.max_cases {
    self.reject(
      "MTL_JUNIT_LIMIT",
      path,
      "Testcase limit exceeded",
      position.line,
      position.column,
    )
  }
  let name = match element.get("name") {
    Some(name) if !name.is_empty() => name
    _ =>
      self.reject(
        "MTL_JUNIT_IDENTITY",
        path + "/@name",
        "A testcase requires a nonempty name",
        position.line,
        position.column,
      )
  }
  let key : @ledger.CaseKey = {
    classname: element.get("classname").unwrap_or(""),
    name,
  }
  if self.identities.contains(key) {
    self.reject(
      "MTL_JUNIT_IDENTITY",
      path,
      "Duplicate testcase identity (classname, name); use distinct producer identities",
      position.line,
      position.column,
    )
  }
  self.identities.add(key)
  { key, problems: [], skip: None, has_skip: false, }
}

///|
fn ParserState::new_problem(
  self : ParserState,
  element : @xml.XmlElement,
  path : String,
  position : @xml.SourcePosition,
) -> ProblemState raise @ledger.InputError {
  if self.problem_count >= self.limits.max_problems {
    self.reject(
      "MTL_JUNIT_LIMIT",
      path,
      "Failure/error payload limit exceeded",
      position.line,
      position.column,
    )
  }
  self.problem_count += 1
  {
    kind: if element.name == "error" {
      @ledger.ProblemKind::Error
    } else {
      @ledger.ProblemKind::Failure
    },
    message: element.get("message"),
    type_name: element.get("type"),
    text: StringBuilder(),
  }
}

///|
fn ParserState::enter(
  self : ParserState,
  element : @xml.XmlElement,
  span : @xml.SourceSpan,
) -> Unit raise @ledger.InputError {
  let path = self.child_path(element.name)
  let position = span.start
  if self.frames.length() >= self.limits.max_depth {
    self.reject(
      "MTL_JUNIT_LIMIT",
      path,
      "XML nesting depth limit exceeded",
      position.line,
      position.column,
    )
  }
  if element.attributes.length() > self.limits.max_attributes {
    self.reject(
      "MTL_JUNIT_LIMIT",
      path,
      "Attribute limit exceeded",
      position.line,
      position.column,
    )
  }
  let parent = self.parent()
  let kind = match parent {
    Some({ kind: Inert, .. }) => Inert
    _ => {
      let surefire = self.frames.is_empty() &&
        element.name == "testsuite" &&
        element.get("xmlns:xsi") ==
        Some("http://www.w3.org/2001/XMLSchema-instance") &&
        element.get("xsi:noNamespaceSchemaLocation") ==
        Some(
          "https://maven.apache.org/surefire/maven-surefire-plugin/xsd/surefire-test-report.xsd",
        ) &&
        element.get("version") == Some("3.0.2")
      if element.name.contains(":") ||
        element.attributes.any(attribute => {
          attribute.name == "xmlns" ||
          (
            attribute.name.has_prefix("xmlns:") &&
            !(surefire && attribute.name == "xmlns:xsi")
          )
        }) {
        self.reject(
          "MTL_JUNIT_UNSUPPORTED",
          path,
          "Result namespaces or schema annotations are unsupported; only unqualified results and the exact root Surefire 3.0.2 xsi schema annotation are accepted (see docs/formats.md)",
          position.line,
          position.column,
        )
      }
      self.check_attributes(element, path, surefire~)
      match parent {
        None => {
          if self.roots != 0 {
            self.reject(
              "MTL_JUNIT_XML",
              path,
              "Expected exactly one XML root",
              position.line,
              position.column,
            )
          }
          self.roots += 1
          match element.name {
            "testsuite" | "testsuites" => Suite(self.new_suite(element, path))
            _ =>
              self.reject(
                "MTL_JUNIT_UNSUPPORTED",
                path,
                "Expected testsuite or testsuites as the document root",
                position.line,
                position.column,
              )
          }
        }
        Some({ kind: Suite(_), name: parent_name, .. }) =>
          match element.name {
            "testsuite" => Suite(self.new_suite(element, path))
            "testcase" if parent_name == "testsuite" =>
              Case(self.new_case(element, path, position))
            "properties" | "system-out" | "system-err" => Inert
            _ =>
              self.reject(
                "MTL_JUNIT_UNSUPPORTED",
                path,
                "Unsupported child '\{element.name}' of \{parent_name}; result semantics will not be ignored",
                position.line,
                position.column,
              )
          }
        Some({ kind: Case(testcase), .. }) =>
          match element.name {
            "failure" | "error" =>
              Problem(self.new_problem(element, path, position))
            "skipped" => {
              if testcase.has_skip {
                self.reject(
                  "MTL_JUNIT_AMBIGUOUS",
                  path,
                  "Multiple skipped markers in one testcase",
                  position.line,
                  position.column,
                )
              }
              testcase.has_skip = true
              Skipped({
                message: element.get("message"),
                text: StringBuilder(),
              })
            }
            "properties" | "system-out" | "system-err" => Inert
            _ =>
              self.reject(
                "MTL_JUNIT_UNSUPPORTED",
                path,
                "Unsupported testcase child '\{element.name}', including producer-specific retry outcomes",
                position.line,
                position.column,
              )
          }
        Some(_) =>
          self.reject(
            "MTL_JUNIT_UNSUPPORTED",
            path,
            "Failure/error/skipped bodies support text and CDATA, not nested elements",
            position.line,
            position.column,
          )
      }
    }
  }
  self.frames.push({
    name: element.name,
    path,
    line: position.line,
    column: position.column,
    children: Map([]),
    kind,
  })
}

///|
// Outside explicit metadata/output subtrees, an unknown attribute could carry
// result semantics. Preserve supported metadata in source and refuse to guess.
fn ParserState::check_attributes(
  self : ParserState,
  element : @xml.XmlElement,
  path : String,
  surefire~ : Bool,
) -> Unit raise @ledger.InputError {
  let allowed : Array[String] = match element.name {
    "testsuite" | "testsuites" =>
      [
        "name", "package", "id", "tests", "failures", "errors", "skipped", "disabled",
        "time", "timestamp", "hostname", "file", "assertions",
      ]
    "testcase" =>
      ["name", "classname", "time", "file", "line", "assertions", "timestamp"]
    "failure" | "error" | "skipped" => ["message", "type"]
    _ => return
  }
  for attribute in element.attributes {
    // Only the exact observed root annotation is inert. It does not namespace
    // any result element, and no schema URL is fetched. Original bytes remain
    // in ParsedReport.source and every evidence carrier.
    if surefire &&
      ["xmlns:xsi", "xsi:noNamespaceSchemaLocation", "version"].contains(
        attribute.name,
      ) {
      continue
    }
    if !allowed.contains(attribute.name) {
      self.reject(
        "MTL_JUNIT_UNSUPPORTED",
        path + "/@" + attribute.name,
        "Unsupported result-node attribute '\{attribute.name}'; move inert metadata into properties or use a supported producer profile",
        attribute.name_span.start.line,
        attribute.name_span.start.column,
      )
    }
  }
}

///|
fn ParserState::leave(
  self : ParserState,
  name : String,
) -> Unit raise @ledger.InputError {
  let frame = match self.frames.pop() {
    None =>
      self.reject("MTL_JUNIT_XML", "/", "Unexpected closing element", 1, 1)
    Some(frame) => frame
  }
  if frame.name != name {
    self.reject(
      "MTL_JUNIT_XML",
      frame.path,
      "Mismatched semantic element stack",
      frame.line,
      frame.column,
    )
  }
  match frame.kind {
    Suite(suite) => self.verify_counts(frame, suite)
    Case(testcase) => self.record_case(frame, testcase)
    Problem(problem) => {
      guard self.parent() is Some({ kind: Case(testcase), .. }) else {
        self.reject(
          "MTL_JUNIT_XML",
          frame.path,
          "Failure/error must belong to a testcase",
          frame.line,
          frame.column,
        )
      }
      testcase.problems.push({
        kind: problem.kind,
        message: problem.message,
        type_name: problem.type_name,
        text: problem.text.to_string(),
        path: frame.path,
        line: frame.line,
        column: frame.column,
      })
    }
    Skipped(skipped) => {
      guard self.parent() is Some({ kind: Case(testcase), .. }) else {
        self.reject(
          "MTL_JUNIT_XML",
          frame.path,
          "Skipped marker must belong to a testcase",
          frame.line,
          frame.column,
        )
      }
      let text = skipped.text.to_string()
      testcase.skip = match (skipped.message, text.is_empty()) {
        (Some(message), false) => Some(message + "\n" + text)
        (Some(message), true) => Some(message)
        (None, false) => Some(text)
        (None, true) => None
      }
    }
    Inert => ()
  }
}
