///|
fn bad(code : String, path : String, message : String) -> @ledger.InputError {
  @ledger.InputError::Invalid({
    code,
    report_id: "",
    path,
    message,
    line: 0,
    column: 0,
  })
}

///|
fn object(
  value : Json,
  path : String,
) -> Map[String, Json] raise @ledger.InputError {
  match value {
    Object(fields) => fields
    _ => raise bad("ExpectedObject", path, "Expected a JSON object")
  }
}

///|
fn keys(
  fields : Map[String, Json],
  allowed : ArrayView[String],
  path : String,
) -> Unit raise @ledger.InputError {
  for key, _ in fields {
    if !allowed.contains(key) {
      raise bad("UnknownField", path + "/" + key, "Unsupported field: " + key)
    }
  }
}

///|
fn required(
  fields : Map[String, Json],
  key : String,
  path : String,
) -> Json raise @ledger.InputError {
  match fields.get(key) {
    Some(value) => value
    None =>
      raise bad("MissingField", path + "/" + key, "Required field is missing")
  }
}

///|
fn string_field(
  fields : Map[String, Json],
  key : String,
  path : String,
) -> String raise @ledger.InputError {
  match required(fields, key, path) {
    String(value) => value
    _ => raise bad("ExpectedString", path + "/" + key, "Expected a JSON string")
  }
}

///|
fn array(value : Json, path : String) -> Array[Json] raise @ledger.InputError {
  match value {
    Array(values) => values
    _ => raise bad("ExpectedArray", path, "Expected a JSON array")
  }
}

///|
fn positive_integer(
  fields : Map[String, Json],
  key : String,
  path : String,
) -> Int32 raise @ledger.InputError {
  match required(fields, key, path) {
    Number(value, ..) if value >= 1.0 && value <= 2147483647.0 => {
      let result = value.to_int()
      if result.to_double() != value {
        raise bad(
          "ExpectedInteger",
          path + "/" + key,
          "Expected an exact positive 32-bit integer",
        )
      }
      result
    }
    _ =>
      raise bad(
        "ExpectedInteger",
        path + "/" + key,
        "Expected an exact positive 32-bit integer",
      )
  }
}

///|
fn schema(fields : Map[String, Json]) -> Unit raise @ledger.InputError {
  let version = positive_integer(fields, "schema", "$")
  if version != 1 {
    raise bad(
      "UnsupportedSchema", "$/schema", "Only schema version 1 is supported",
    )
  }
}

///|
fn case_key(
  value : Json,
  path : String,
) -> @ledger.CaseKey raise @ledger.InputError {
  let fields = object(value, path)
  keys(fields, ["classname", "name"], path)
  {
    classname: string_field(fields, "classname", path),
    name: string_field(fields, "name", path),
  }
}

///|
/// Decode a complete expected artifact/test inventory. Unknown versions and
/// fields are refused; duplicate keys are checked in the original JSON text.
pub fn decode_plan(
  source : String,
  limits~ : @ledger.Limits = @ledger.Limits::default(),
) -> @ledger.RunPlan raise @ledger.InputError {
  let fields = object(strict_json(source, limits), "$")
  keys(fields, ["schema", "run_id", "revision", "reports"], "$")
  schema(fields)
  let items = array(required(fields, "reports", "$"), "$/reports")
  if items.length() > limits.max_reports {
    raise bad(
      "ReportLimit", "$/reports", "Expected report inventory exceeds the configured limit",
    )
  }
  let reports : Array[@ledger.ExpectedReport] = []
  let mut count = 0
  for i, value in items {
    let path = "$/reports/\{i}"
    let item = object(value, path)
    keys(item, ["id", "environment", "shard", "attempt", "cases"], path)
    let cases : Array[@ledger.CaseKey] = []
    for j, key in array(required(item, "cases", path), path + "/cases") {
      count += 1
      if count > limits.max_cases {
        raise bad(
          "CaseLimit",
          path + "/cases",
          "Expected case inventory exceeds the configured limit",
        )
      }
      cases.push(case_key(key, path + "/cases/\{j}"))
    }
    reports.push({
      id: string_field(item, "id", path),
      environment: string_field(item, "environment", path),
      shard: string_field(item, "shard", path),
      attempt: positive_integer(item, "attempt", path),
      cases,
    })
  }
  @ledger.RunPlan::new(
    string_field(fields, "run_id", "$"),
    string_field(fields, "revision", "$"),
    reports,
    limits~,
  )
}

///|
fn nonempty(value : String, path : String) -> String raise @ledger.InputError {
  if value.is_empty() || value.contains("\u0000") {
    raise bad("InvalidText", path, "Value must be nonempty and contain no NUL")
  }
  value
}

///|
/// Decode producer bindings separately from the expected plan. Paths are
/// relative to the bundle file in the CLI, or supplied directly by library users.
pub fn decode_bundle(
  source : String,
  limits~ : @ledger.Limits = @ledger.Limits::default(),
) -> Bundle raise @ledger.InputError {
  let fields = object(strict_json(source, limits), "$")
  keys(fields, ["schema", "documents"], "$")
  schema(fields)
  let items = array(required(fields, "documents", "$"), "$/documents")
  if items.length() > limits.max_reports {
    raise bad(
      "ReportLimit", "$/documents", "Document inventory exceeds the configured limit",
    )
  }
  let documents : Array[ReportFile] = []
  for i, value in items {
    let path = "$/documents/\{i}"
    let item = object(value, path)
    keys(
      item,
      ["id", "run_id", "revision", "environment", "shard", "attempt", "path"],
      path,
    )
    documents.push({
      binding: {
        id: nonempty(string_field(item, "id", path), path + "/id"),
        run_id: nonempty(string_field(item, "run_id", path), path + "/run_id"),
        revision: nonempty(
          string_field(item, "revision", path),
          path + "/revision",
        ),
        environment: nonempty(
          string_field(item, "environment", path),
          path + "/environment",
        ),
        shard: nonempty(string_field(item, "shard", path), path + "/shard"),
        attempt: positive_integer(item, "attempt", path),
      },
      path: nonempty(string_field(item, "path", path), path + "/path"),
    })
  }
  { documents, }
}
