///|
fn is_xml_space(text : String) -> Bool {
  text.iter().all(character => character is (' ' | '\t' | '\r' | '\n'))
}

///|
fn ParserState::text(
  self : ParserState,
  text : String,
  span : @xml.SourceSpan,
) -> Unit raise @ledger.InputError {
  match self.parent() {
    Some({ kind: Problem(problem), .. }) => problem.text.write_string(text)
    Some({ kind: Skipped(skipped), .. }) => skipped.text.write_string(text)
    Some({ kind: Inert, .. }) => ()
    parent =>
      if !is_xml_space(text) {
        self.reject(
          "MTL_JUNIT_UNSUPPORTED",
          parent.map(frame => frame.path).unwrap_or("/"),
          "Non-whitespace text appears outside a supported payload or inert metadata element",
          span.start.line,
          span.start.column,
        )
      }
  }
}

///|
/// Read the supported JUnit XML profile without discarding its authored input.
///
/// Result identities are exact classname/name pairs. Nested suite counts include
/// descendant testcases. Missing counts are permitted; supplied counts are checked.
/// Every failure and error payload is retained; an error takes outcome precedence.
///
/// Unsupported outcome extensions, ambiguous skip/failure mixtures, duplicate
/// identities, DTDs, malformed XML and resource-limit violations raise InputError.
pub fn parse(
  source : String,
  report_id~ : String = "",
  limits~ : @ledger.Limits = @ledger.Limits::default(),
) -> @ledger.ParsedReport raise @ledger.InputError {
  limits.validate()
  if source.length() > limits.max_source_units {
    reject(
      "MTL_JUNIT_LIMIT", report_id, "/", "XML source exceeds the UTF-16 code-unit limit",
      1, 1,
    )
  }
  let state : ParserState = {
    report_id,
    limits,
    frames: [],
    cases: [],
    identities: Set([]),
    event_count: 0,
    problem_count: 0,
    roots: 0,
  }
  let reader = @xml.Reader::from_string(source)
  for ;; {
    if state.event_count >= limits.max_events {
      state.reject(
        "MTL_JUNIT_LIMIT",
        "/",
        "XML event limit exceeded",
        reader.line(),
        reader.column(),
      )
    }
    let event = reader.read_event() catch {
      @xml.XmlError::At(error~, span~) =>
        state.reject(
          "MTL_JUNIT_XML",
          "/",
          error.to_string(),
          span.start.line,
          span.start.column,
        )
    }
    state.event_count += 1
    match event.kind {
      Start(element) => state.enter(element, event.span)
      Empty(element) => {
        state.enter(element, event.span)
        state.leave(element.name)
      }
      End(name) => state.leave(name)
      Text(text) | CData(text) => state.text(text, event.span)
      DocType(_) =>
        state.reject(
          "MTL_JUNIT_UNSUPPORTED",
          "/",
          "DTD declarations are not supported; external or internal entities will not be accepted",
          event.span.start.line,
          event.span.start.column,
        )
      Decl(version~, encoding~, ..) =>
        if version != "1.0" ||
          (encoding is Some(value) && value.to_upper() != "UTF-8") {
          state.reject(
            "MTL_JUNIT_UNSUPPORTED",
            "/",
            "Only decoded UTF-8 XML 1.0 input is supported",
            event.span.start.line,
            event.span.start.column,
          )
        }
      Comment(_) | PI(_) => ()
      Eof => break
    }
  }
  if state.roots != 1 || !state.frames.is_empty() {
    state.reject(
      "MTL_JUNIT_XML",
      "/",
      "Expected one complete JUnit XML document",
      reader.line(),
      reader.column(),
    )
  }
  { source, cases: state.cases, }
}
