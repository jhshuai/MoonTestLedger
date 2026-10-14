///|
/// One explicitly expected relative artifact path; forward slashes only.
pub(all) struct CollectionFile {
  id : String
  path : String
} derive(Debug, Eq)

///|
pub extend CollectionFile with Eq::{equal, not_equal}

///|
pub extend CollectionFile with @debug.Debug::{to_repr}

///|
/// Original XML supplied by a storage adapter for a declared report ID.
pub(all) struct CollectedXml {
  id : String
  xml : String
} derive(Debug, Eq)

///|
pub extend CollectedXml with Eq::{equal, not_equal}

///|
pub extend CollectedXml with @debug.Debug::{to_repr}

///|
/// A complete expected inventory and exact artifact path mapping. Paths never
/// define run/revision/test identities; the caller owns the declared contract.
struct CollectionSpec {
  plan : @ledger.RunPlan
  files : Array[CollectionFile]
  deny_recovered : Bool
}

///|
fn collection_path(path : String) -> Array[String] raise @ledger.InputError {
  if path.is_empty() ||
    path.length() > 4096 ||
    path
    .iter()
    .any(c => {
      !(c is ('a'..<='z' | 'A'..<='Z' | '0'..<='9' | '.' | '_' | '-' | '/'))
    }) {
    raise bad(
      "CollectionPath", "/files", "Expected an ASCII relative path using letters, digits, dot, underscore, hyphen and forward slash; maximum 4096 units",
    )
  }
  let parts = path.split("/").map(view => view.to_owned()).collect()
  if parts.length() > 32 {
    raise bad("CollectionPath", "/files", "Relative path exceeds 32 components")
  }
  for part in parts {
    if part.is_empty() ||
      part.length() > 255 ||
      part == "." ||
      part == ".." ||
      part.has_suffix(".") {
      raise bad(
        "CollectionPath",
        "/files/" + path,
        "Empty, traversal and trailing dot/space components are unsupported",
      )
    }
    let stem = part.split(".").next().unwrap().to_owned().to_lower()
    if ["con", "prn", "aux", "nul", "conin$", "conout$"].contains(stem) ||
      (
        stem.length() == 4 &&
        (stem.has_prefix("com") || stem.has_prefix("lpt")) &&
        stem[3] >= 49 &&
        stem[3] <= 57
      ) {
      raise bad(
        "CollectionPath",
        "/files/" + path,
        "Windows device names are not portable artifact paths",
      )
    }
  }
  parts
}

///|
/// Construct a complete path contract before artifacts arrive.
///
/// ```mbt check
/// test {
///   let reports : Array[@ledger.ExpectedReport] = [
///     {
///       id: "report",
///       environment: "linux",
///       shard: "all",
///       attempt: 1,
///       cases: [{ classname: "C", name: "a", }],
///     },
///   ]
///   let plan = @ledger.RunPlan::new("run", "revision", reports)
///   let files : Array[@wire.CollectionFile] = [
///     { id: "report", path: "job/results.xml", },
///   ]
///   let spec = @wire.CollectionSpec::new(plan, files[:])
///   let absent : Array[@wire.CollectedXml] = []
///   inspect(spec.collect(absent[:]).exit_code(), content="3")
/// }
/// ```
pub fn CollectionSpec::new(
  plan : @ledger.RunPlan,
  files : ArrayView[CollectionFile],
  deny_recovered~ : Bool = false,
  limits~ : @ledger.Limits = @ledger.Limits::default(),
) -> CollectionSpec raise @ledger.InputError {
  let plan = @ledger.RunPlan::new(
    plan.run_id,
    plan.revision,
    plan.reports,
    limits~,
  )
  if files.length() > limits.max_reports {
    raise bad(
      "ReportLimit", "/files", "Artifact path inventory exceeds the report budget",
    )
  }
  let expected = Set::from_array(plan.reports.map(report => report.id))
  let seen : Set[String] = Set([])
  let prefixes : Map[String, (String, Bool)] = Map([])
  let copied : Array[CollectionFile] = []
  for file in files {
    if !expected.contains(file.id) {
      raise bad(
        "UnexpectedReport",
        "/files/" + file.id,
        "Path identity must be declared in the full expected plan",
      )
    }
    if seen.contains(file.id) {
      raise bad(
        "DuplicateReport",
        "/files/" + file.id,
        "Each planned report needs exactly one path",
      )
    }
    seen.add(file.id)
    let parts = collection_path(file.path)
    let mut prefix = ""
    for i, part in parts {
      prefix = if i == 0 { part } else { prefix + "/" + part }
      let is_file = i == parts.length() - 1
      let folded = prefix.to_lower()
      if prefixes.get(folded) is Some((previous, was_file)) {
        if previous != prefix || was_file != is_file || is_file {
          raise bad(
            "CollectionPathCollision",
            "/files/" + file.path,
            "Artifact paths alias by case, share a file, or conflict with a directory prefix",
          )
        }
      } else {
        prefixes[folded] = (prefix, is_file)
      }
    }
    copied.push(file)
  }
  if seen.length() != expected.length() {
    raise bad(
      "CollectionInventory", "/files", "Every planned report needs an explicit path, even if it is not yet present",
    )
  }
  copied.sort_by((a, b) => a.id.compare(b.id))
  let result : CollectionSpec = { plan, files: copied, deny_recovered, }
  ignore(result.encode(limits~))
  result
}

///|
pub fn CollectionSpec::files(self : CollectionSpec) -> Array[CollectionFile] {
  self.files.copy()
}

///|
pub fn CollectionSpec::encode(
  self : CollectionSpec,
  limits~ : @ledger.Limits = @ledger.Limits::default(),
) -> String raise @ledger.InputError {
  let plan = @ledger.RunPlan::new(
    self.plan.run_id,
    self.plan.revision,
    self.plan.reports,
    limits~,
  )
  let result = Json::object({
    "schema": Json::number(1),
    "kind": Json::string("moontestledger/collection"),
    "deny_recovered": Json::boolean(self.deny_recovered),
    "plan": plan_json(plan),
    "files": Json::array(
      self.files.map(file => {
        Json::object({
          "id": Json::string(file.id),
          "path": Json::string(file.path),
        })
      }),
    ),
  }).stringify(indent=2)
  if result.length() > limits.max_source_units {
    raise bad(
      "SourceLimit", "$", "Collection specification exceeds the configured JSON budget",
    )
  }
  result
}

///|
/// Atomically collect only explicitly supplied original reports. Omitted
/// reports/cases remain incomplete against the full inventory. An invalid
/// report refuses the whole operation; no input or previous spec is modified.
pub fn CollectionSpec::collect(
  self : CollectionSpec,
  inputs : ArrayView[CollectedXml],
  limits~ : @ledger.Limits = @ledger.Limits::default(),
) -> Evidence raise @ledger.InputError {
  ignore(self.encode(limits~))
  if inputs.length() > limits.max_reports {
    raise bad(
      "ReportLimit", "/inputs", "Incoming artifact batch exceeds the report budget",
    )
  }
  let reports : Map[String, @ledger.ExpectedReport] = Map([])
  for report in self.plan.reports {
    reports[report.id] = report
  }
  let seen : Set[String] = Set([])
  let ledger = @ledger.Ledger::new(self.plan, limits~)
  let mut units = 0L
  for input in inputs {
    guard reports.get(input.id) is Some(expected) else {
      raise bad(
        "UnexpectedReport",
        "/inputs/" + input.id,
        "Artifact identity is not declared by this collection spec",
      )
    }
    if seen.contains(input.id) {
      raise bad(
        "DuplicateReport",
        "/inputs/" + input.id,
        "Incoming artifact identity appears more than once",
      )
    }
    seen.add(input.id)
    units += input.xml.length().to_int64()
    if units > limits.max_total_source_units.to_int64() {
      raise bad(
        "SourceLimit", "/inputs", "Combined incoming XML source budget exceeded",
      )
    }
    let report = @junit.parse(input.xml, report_id=input.id, limits~)
    ledger.ingest({
      binding: {
        id: input.id,
        run_id: self.plan.run_id,
        revision: self.plan.revision,
        environment: expected.environment,
        shard: expected.shard,
        attempt: expected.attempt,
      },
      report,
    })
  }
  let evidence : Evidence = { ledger, deny_recovered: self.deny_recovered, }
  ignore(evidence.encode(limits~))
  evidence
}

///|
pub fn decode_collection(
  source : String,
  limits~ : @ledger.Limits = @ledger.Limits::default(),
) -> CollectionSpec raise @ledger.InputError {
  let fields = object(strict_json(source, limits), "$")
  keys(fields, ["schema", "kind", "deny_recovered", "plan", "files"], "$")
  schema(fields)
  if string_field(fields, "kind", "$") != "moontestledger/collection" {
    raise bad(
      "CollectionKind", "$/kind", "Expected a MoonTestLedger collection specification",
    )
  }
  let deny_recovered = match required(fields, "deny_recovered", "$") {
    True => true
    False => false
    _ =>
      raise bad(
        "ExpectedBoolean", "$/deny_recovered", "Expected a boolean recovery policy",
      )
  }
  let plan = decode_plan(required(fields, "plan", "$").stringify(), limits~)
  let items = array(required(fields, "files", "$"), "$/files")
  if items.length() > limits.max_reports {
    raise bad(
      "ReportLimit", "$/files", "Artifact path inventory exceeds the report budget",
    )
  }
  let files : Array[CollectionFile] = []
  for i, item in items {
    let path = "$/files/\{i}"
    let item = object(item, path)
    keys(item, ["id", "path"], path)
    files.push({
      id: nonempty(string_field(item, "id", path), path + "/id"),
      path: string_field(item, "path", path),
    })
  }
  CollectionSpec::new(plan, files[:], deny_recovered~, limits~)
}
