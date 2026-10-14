///|
fn whitespace(char : Char) -> Bool {
  char == ' ' || char == '\n' || char == '\r' || char == '\t'
}

///|
fn nesting_budget(chars : Array[Char]) -> Unit raise @ledger.InputError {
  let mut depth = 0
  let mut quoted = false
  let mut escaped = false
  for char in chars {
    if quoted {
      if escaped {
        escaped = false
      } else if char == '\\' {
        escaped = true
      } else if char == '"' {
        quoted = false
      }
    } else if char == '"' {
      quoted = true
    } else if char is ('{' | '[') {
      depth += 1
      if depth > 64 {
        raise bad(
          "JsonDepthLimit", "$", "JSON nesting exceeds the supported depth of 64",
        )
      }
    } else if char is ('}' | ']') {
      depth = (depth - 1).max(0)
    }
  }
}

///|
// The standard parser validates syntax and depth first. This narrow second
// pass rejects duplicate *decoded* object keys that its Map representation
// would otherwise overwrite. It is not a second JSON implementation.
fn strict_json(
  source : String,
  limits : @ledger.Limits,
) -> Json raise @ledger.InputError {
  limits.validate()
  if source.length() > limits.max_source_units {
    raise bad(
      "SourceLimit", "$", "JSON source exceeds the configured UTF-16 length limit",
    )
  }
  let chars = source.to_array()
  nesting_budget(chars)
  let value = @json.parse(source) catch {
    error => raise bad("InvalidJson", "$", error.to_string())
  }
  let objects : Array[Map[String, Unit]] = []
  let mut i = 0
  let mut line = 1
  let mut column = 1
  while i < chars.length() {
    let char = chars[i]
    if char == '{' {
      objects.push(Map([]))
    } else if char == '}' {
      ignore(objects.pop())
    } else if char == '"' {
      let start = i
      let start_line = line
      let start_column = column
      i += 1
      column += 1
      while i < chars.length() && chars[i] != '"' {
        if chars[i] == '\\' {
          i += 1
          column += 1
        }
        i += 1
        column += 1
      }
      let mut next = i + 1
      while next < chars.length() && whitespace(chars[next]) {
        next += 1
      }
      if next < chars.length() && chars[next] == ':' {
        let encoded = String::from_array(chars[start:i + 1])
        let decoded = @json.parse(encoded) catch {
          error => raise bad("InvalidJson", "$", error.to_string())
        }
        let key = match decoded {
          String(key) => key
          _ => raise bad("InvalidJson", "$", "Object key is not a string")
        }
        guard objects.last() is Some(seen) else {
          raise bad("InvalidJson", "$", "Object key appears outside an object")
        }
        if seen.contains(key) {
          raise @ledger.InputError::Invalid({
            code: "DuplicateJsonKey",
            report_id: "",
            path: "$",
            message: "Duplicate decoded object key: " + key,
            line: start_line,
            column: start_column,
          })
        }
        seen[key] = ()
        // The core parser may discard decimal lexemes after Double rounding.
        // Check our integer fields against authored digits before using that
        // projection. Type errors are handled by the schema decoder below.
        if key == "schema" || key == "attempt" {
          let mut token_start = next + 1
          while token_start < chars.length() && whitespace(chars[token_start]) {
            token_start += 1
          }
          if token_start < chars.length() &&
            (
              chars[token_start] == '-' ||
              (chars[token_start] >= '0' && chars[token_start] <= '9')
            ) {
            let mut token_end = token_start + 1
            while token_end < chars.length() &&
                  chars[token_end] is ('0'..<='9' | '-' | '+' | '.' | 'e' | 'E') {
              token_end += 1
            }
            let token = String::from_array(chars[token_start:token_end])
            if exact_positive_integer(token) is None {
              raise bad(
                "ExpectedInteger",
                "$/" + key,
                "Expected an exact positive 32-bit integer; fractional digits cannot be rounded",
              )
            }
          }
        }
      }
    }
    if char == '\n' {
      line += 1
      column = 1
    } else {
      column += 1
    }
    i += 1
  }
  value
}
