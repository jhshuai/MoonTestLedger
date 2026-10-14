///|
fn digest(value : String, path : String) -> String raise @ledger.InputError {
  if value.length() != 64 ||
    !value.to_array().all(c => c is ('0'..<='9' | 'a'..<='f')) {
    raise bad(
      "InvalidDigest", path, "Expected exactly 64 lowercase hexadecimal SHA-256 digits",
    )
  }
  value
}

///|
fn integrity_text(
  fields : Map[String, Json],
  key : String,
  path : String,
) -> String raise @ledger.InputError {
  nonempty(string_field(fields, key, path), path + "/" + key)
}

///|
/// Deterministic JSON: receipts and missing IDs are sorted by exact report ID.
/// Refuses output beyond the configured JSON budget instead of truncating it.
pub fn IntegrityManifest::encode(
  self : IntegrityManifest,
  limits~ : @ledger.Limits = @ledger.Limits::default(),
) -> String raise @ledger.InputError {
  limits.validate()
  if self.documents.length() + self.missing_reports.length() >
    limits.max_reports {
    raise bad(
      "ReportLimit", "$/documents", "Manifest report inventory exceeds the configured budget",
    )
  }
  for document in self.documents {
    if document.utf8_bytes.to_int64() > limits.max_source_units.to_int64() * 4L {
      raise bad(
        "SourceLimit",
        "$/documents/" + document.binding.id,
        "Receipt exceeds the UTF-8 source budget upper bound",
      )
    }
  }
  let result = Json::object({
    "schema": Json::number(1),
    "kind": Json::string("moontestledger/integrity"),
    "algorithm": Json::string("sha256"),
    "canonicalization": Json::string("mtl-evidence-v1"),
    "run_id": Json::string(self.run_id),
    "revision": Json::string(self.revision),
    "deny_recovered": Json::boolean(self.deny_recovered),
    "plan_sha256": Json::string(self.plan_sha256),
    "archive_sha256": Json::string(self.archive_sha256),
    "documents": Json::array(
      self.documents.map(document => {
        let fields = binding_fields(document.binding)
        fields["sha256"] = Json::string(document.sha256)
        fields["utf8_bytes"] = Json::number(document.utf8_bytes.to_double())
        Json::object(fields)
      }),
    ),
    "missing_reports": Json::array(self.missing_reports.map(Json::string)),
  }).stringify(indent=2)
  if result.length() > limits.max_source_units {
    raise bad(
      "SourceLimit", "$", "Encoded integrity manifest exceeds the configured JSON budget",
    )
  }
  result
}

///|
/// Strict versioned manifest reader. Unknown fields/algorithms, duplicates,
/// conflicting IDs and rounded integer lexemes are refused.
pub fn decode_integrity(
  source : String,
  limits~ : @ledger.Limits = @ledger.Limits::default(),
) -> IntegrityManifest raise @ledger.InputError {
  let fields = object(strict_json(source, limits), "$")
  keys(
    fields,
    [
      "schema", "kind", "algorithm", "canonicalization", "run_id", "revision", "deny_recovered",
      "plan_sha256", "archive_sha256", "documents", "missing_reports",
    ],
    "$",
  )
  schema(fields)
  for
    (key, expected) in [
      ("kind", "moontestledger/integrity"),
      ("algorithm", "sha256"),
      ("canonicalization", "mtl-evidence-v1"),
    ] {
    if string_field(fields, key, "$") != expected {
      raise bad(
        "IntegrityFormat",
        "$/" + key,
        "Unsupported integrity format; expected " + expected,
      )
    }
  }
  let run_id = integrity_text(fields, "run_id", "$")
  let revision = integrity_text(fields, "revision", "$")
  let deny_recovered = match required(fields, "deny_recovered", "$") {
    True => true
    False => false
    _ =>
      raise bad(
        "ExpectedBoolean", "$/deny_recovered", "Expected a boolean recovery policy",
      )
  }
  let plan_sha256 = digest(
    string_field(fields, "plan_sha256", "$"),
    "$/plan_sha256",
  )
  let archive_sha256 = digest(
    string_field(fields, "archive_sha256", "$"),
    "$/archive_sha256",
  )
  let items = array(required(fields, "documents", "$"), "$/documents")
  let missing = array(
    required(fields, "missing_reports", "$"),
    "$/missing_reports",
  )
  if items.length() + missing.length() > limits.max_reports {
    raise bad(
      "ReportLimit", "$/documents", "Manifest report inventory exceeds the configured budget",
    )
  }
  let ids : Set[String] = Set([])
  let documents : Array[IntegrityDocument] = []
  for i, item in items {
    let path = "$/documents/\{i}"
    let item = object(item, path)
    keys(
      item,
      [
        "id", "run_id", "revision", "environment", "shard", "attempt", "sha256",
        "utf8_bytes",
      ],
      path,
    )
    let binding : @ledger.ReportBinding = {
      id: integrity_text(item, "id", path),
      run_id: integrity_text(item, "run_id", path),
      revision: integrity_text(item, "revision", path),
      environment: integrity_text(item, "environment", path),
      shard: integrity_text(item, "shard", path),
      attempt: positive_integer(item, "attempt", path),
    }
    if binding.run_id != run_id || binding.revision != revision {
      raise bad(
        "BindingMismatch", path, "Receipt must bind to the manifest run and revision",
      )
    }
    if ids.contains(binding.id) {
      raise bad(
        "DuplicateReport", path, "Report identity appears more than once in the manifest",
      )
    }
    ids.add(binding.id)
    let utf8_bytes = positive_integer(item, "utf8_bytes", path)
    if utf8_bytes.to_int64() > limits.max_source_units.to_int64() * 4L {
      raise bad(
        "SourceLimit",
        path + "/utf8_bytes",
        "Receipt exceeds the UTF-8 source budget upper bound",
      )
    }
    documents.push({
      binding,
      utf8_bytes,
      sha256: digest(string_field(item, "sha256", path), path + "/sha256"),
    })
  }
  let missing_reports : Array[String] = []
  for i, item in missing {
    let path = "$/missing_reports/\{i}"
    let id = match item {
      String(id) => nonempty(id, path)
      _ =>
        raise bad("ExpectedString", path, "Expected a missing report identity")
    }
    if ids.contains(id) {
      raise bad(
        "DuplicateReport", path, "Missing report identity is duplicated or already has a receipt",
      )
    }
    ids.add(id)
    missing_reports.push(id)
  }
  if ids.is_empty() {
    raise bad(
      "EmptyInventory", "$/documents", "A manifest must account for at least one expected report",
    )
  }
  documents.sort_by((a, b) => a.binding.id.compare(b.binding.id))
  missing_reports.sort()
  {
    run_id,
    revision,
    deny_recovered,
    plan_sha256,
    archive_sha256,
    documents,
    missing_reports,
  }
}
