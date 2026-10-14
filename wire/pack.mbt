///|
/// Exact decoded UTF-8 XML and a content-addressed flat filename. No arbitrary
/// paths or binary members are supported by the evidence file-pack profile.
pub(all) struct PackFile {
  name : String
  xml : String
} derive(Debug, Eq)

///|
pub extend PackFile with Eq::{equal, not_equal}

///|
pub extend PackFile with @debug.Debug::{to_repr}

///|
/// Full expected inventory plus an integrity manifest; accepted XML is stored
/// separately. A missing expected report remains missing, not a missing member.
struct PackIndex {
  plan : @ledger.RunPlan
  manifest : IntegrityManifest
}

///|
fn pack_name(hash : String) -> String {
  "sha256-" + hash + ".xml"
}

///|
/// Independent sorted list of required members, deduplicated by exact digest.
pub fn PackIndex::filenames(self : PackIndex) -> Array[String] {
  let names : Set[String] = Set([])
  for document in self.manifest.documents {
    names.add(pack_name(document.sha256))
  }
  let result = names.to_array()
  result.sort()
  result
}

///|
/// Detach exact original XML without losing the full plan, policy or bindings.
/// Both returned values are independent of the input. Index and members can
/// be passed to any storage adapter; restore checks all hashes before replay.
pub fn Evidence::detach(
  self : Evidence,
  limits~ : @ledger.Limits = @ledger.Limits::default(),
) -> (PackIndex, Array[PackFile]) raise @ledger.InputError {
  let manifest = self.integrity(limits~)
  let snapshot = self.snapshot()
  let files : Map[String, String] = Map([])
  for document in snapshot.documents {
    let name = pack_name(sha256_text(document.report.source))
    match files.get(name) {
      Some(previous) if previous != document.report.source =>
        raise bad(
          "PackCollision",
          "/files/" + name,
          "Different XML sources share a digest; refusing ambiguous storage",
        )
      _ => files[name] = document.report.source
    }
  }
  let index : PackIndex = { plan: snapshot.plan, manifest, }
  ignore(index.encode(limits~))
  let members = files.to_array().map(pair => { name: pair.0, xml: pair.1, })
  members.sort_by((a, b) => a.name.compare(b.name))
  (index, members)
}

///|
pub fn PackIndex::encode(
  self : PackIndex,
  limits~ : @ledger.Limits = @ledger.Limits::default(),
) -> String raise @ledger.InputError {
  let integrity = strict_json(self.manifest.encode(limits~), limits)
  let result = Json::object({
    "schema": Json::number(1),
    "kind": Json::string("moontestledger/file-pack"),
    "plan": plan_json(self.plan),
    "integrity": integrity,
  }).stringify(indent=2)
  if result.length() > limits.max_source_units {
    raise bad(
      "SourceLimit", "$", "File-pack index exceeds the configured JSON budget",
    )
  }
  result
}

///|
/// Require exactly the declared members, verify original UTF-8 bytes, then
/// replay all XML against the full plan and verify the complete archive digest.
/// Missing stored members and undeclared extras are invalid, never truncated.
pub fn PackIndex::restore(
  self : PackIndex,
  files : ArrayView[PackFile],
  limits~ : @ledger.Limits = @ledger.Limits::default(),
) -> Evidence raise @ledger.InputError {
  ignore(self.encode(limits~))
  if files.length() > limits.max_reports {
    raise bad("ReportLimit", "/files", "Too many file-pack members")
  }
  let names = self.filenames()
  let required_names = Set::from_array(names)
  let sources : Map[String, String] = Map([])
  let mut total_units = 0L
  for file in files {
    if !required_names.contains(file.name) {
      raise bad(
        "UnexpectedPackFile",
        "/files/" + file.name,
        "Member is not declared by the pack index",
      )
    }
    if sources.contains(file.name) {
      raise bad(
        "DuplicatePackFile",
        "/files/" + file.name,
        "Member name appears more than once",
      )
    }
    if file.xml.length() > limits.max_source_units {
      raise bad(
        "SourceLimit",
        "/files/" + file.name,
        "XML member exceeds the source budget",
      )
    }
    total_units += file.xml.length().to_int64()
    if total_units > limits.max_total_source_units.to_int64() {
      raise bad(
        "SourceLimit", "/files", "Combined unique member source budget exceeded",
      )
    }
    if pack_name(sha256_text(file.xml)) != file.name {
      raise mismatch(
        "/files/" + file.name,
        "Original XML digest differs from its content-addressed filename",
      )
    }
    sources[file.name] = file.xml
  }
  for name in names {
    if !sources.contains(name) {
      raise bad(
        "MissingPackFile",
        "/files/" + name,
        "A declared accepted XML member is missing",
      )
    }
  }
  let ledger = @ledger.Ledger::new(self.plan, limits~)
  for receipt in self.manifest.documents {
    let name = pack_name(receipt.sha256)
    let source = sources[name]
    if @utf8.encode(source).length() != receipt.utf8_bytes {
      raise mismatch(
        "/files/" + name,
        "XML byte length differs from the receipt",
      )
    }
    let report = @junit.parse(source, report_id=receipt.binding.id, limits~)
    ledger.ingest({ binding: receipt.binding, report, })
  }
  let evidence : Evidence = {
    ledger,
    deny_recovered: self.manifest.deny_recovered,
  }
  evidence.check_integrity(self.manifest, limits~)
  evidence
}

///|
/// Strict index validation before any member access. Every planned report
/// must have exactly one matching receipt or an explicit missing-report ID.
pub fn decode_pack_index(
  source : String,
  limits~ : @ledger.Limits = @ledger.Limits::default(),
) -> PackIndex raise @ledger.InputError {
  let fields = object(strict_json(source, limits), "$")
  keys(fields, ["schema", "kind", "plan", "integrity"], "$")
  schema(fields)
  if string_field(fields, "kind", "$") != "moontestledger/file-pack" {
    raise bad("PackKind", "$/kind", "Expected a MoonTestLedger file-pack index")
  }
  let plan = decode_plan(required(fields, "plan", "$").stringify(), limits~)
  let manifest = decode_integrity(
    required(fields, "integrity", "$").stringify(),
    limits~,
  )
  if manifest.run_id != plan.run_id ||
    manifest.revision != plan.revision ||
    manifest.plan_sha256 != sha256_text(encode_plan(plan)) {
    raise mismatch("$/plan", "Full plan differs from the integrity manifest")
  }
  let reports : Map[String, @ledger.ExpectedReport] = Map([])
  for report in plan.reports {
    reports[report.id] = report
  }
  let accounted : Set[String] = Set([])
  for receipt in manifest.documents {
    guard reports.get(receipt.binding.id) is Some(report) else {
      raise bad(
        "UnexpectedReport", "$/integrity/documents", "Receipt identity is not in the full plan",
      )
    }
    if receipt.binding.environment != report.environment ||
      receipt.binding.shard != report.shard ||
      receipt.binding.attempt != report.attempt {
      raise bad(
        "BindingMismatch",
        "$/integrity/documents/" + report.id,
        "Receipt must exactly match its planned environment, shard and attempt",
      )
    }
    accounted.add(report.id)
  }
  for id in manifest.missing_reports {
    if !reports.contains(id) {
      raise bad(
        "UnexpectedReport", "$/integrity/missing_reports", "Missing identity is not in the full plan",
      )
    }
    accounted.add(id)
  }
  if accounted.length() != reports.length() {
    raise bad(
      "PackInventory", "$/integrity", "Every planned report needs a receipt or an explicit missing identity",
    )
  }
  { plan, manifest, }
}
