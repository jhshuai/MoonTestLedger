///|
/// Receipt for an accepted report, including its full binding and exact UTF-8
/// source digest. Returned arrays are independent copies of manifest storage.
pub(all) struct IntegrityDocument {
  binding : @ledger.ReportBinding
  sha256 : String
  utf8_bytes : Int32
} derive(Debug, Eq)

///|
pub extend IntegrityDocument with Eq::{equal, not_equal}

///|
pub extend IntegrityDocument with @debug.Debug::{to_repr}

///|
/// A validated checksum manifest. Trust the expected manifest separately from
/// the archive: checksums do not authenticate its author or prove execution.
struct IntegrityManifest {
  run_id : String
  revision : String
  deny_recovered : Bool
  plan_sha256 : String
  archive_sha256 : String
  documents : Array[IntegrityDocument]
  missing_reports : Array[String]
}

///|
pub fn IntegrityManifest::documents(
  self : IntegrityManifest,
) -> Array[IntegrityDocument] {
  self.documents.copy()
}

///|
pub fn IntegrityManifest::missing_reports(
  self : IntegrityManifest,
) -> Array[String] {
  self.missing_reports.copy()
}

///|
fn sha256_text(source : String) -> String {
  @crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(source)))
}

///|
/// Bind the full validated inventory, recovery policy, accepted report bindings
/// and original XML. Incomplete and failing archives can have valid manifests.
/// Canonicalization is versioned MoonTestLedger JSON, not RFC 8785.
pub fn Evidence::integrity(
  self : Evidence,
  limits~ : @ledger.Limits = @ledger.Limits::default(),
) -> IntegrityManifest raise @ledger.InputError {
  // Revalidation refuses projections or budgets that cannot be preserved.
  let archive = self.encode(limits~)
  let snapshot = self.snapshot()
  let documents = snapshot.documents.map(document => {
    let bytes = @utf8.encode(document.report.source)
    {
      binding: document.binding,
      sha256: @crypto.bytes_to_hex_string(@crypto.sha256(bytes)),
      utf8_bytes: bytes.length(),
    }
  })
  documents.sort_by((a, b) => a.binding.id.compare(b.binding.id))
  let missing_reports = self.summary().missing_reports
  missing_reports.sort()
  let manifest : IntegrityManifest = {
    run_id: snapshot.plan.run_id,
    revision: snapshot.plan.revision,
    deny_recovered: self.deny_recovered,
    plan_sha256: sha256_text(encode_plan(snapshot.plan)),
    archive_sha256: sha256_text(archive),
    documents,
    missing_reports,
  }
  ignore(manifest.encode(limits~))
  manifest
}

///|
fn mismatch(path : String, message : String) -> @ledger.InputError {
  bad("IntegrityMismatch", path, message)
}

///|
/// Check every manifest component against the replayed archive. Raises on any
/// discrepancy without mutating either input. Success does not change the
/// archive's existing gate: call Evidence::exit_code after checking integrity.
pub fn Evidence::check_integrity(
  self : Evidence,
  expected : IntegrityManifest,
  limits~ : @ledger.Limits = @ledger.Limits::default(),
) -> Unit raise @ledger.InputError {
  ignore(expected.encode(limits~))
  let actual = self.integrity(limits~)
  if actual.run_id != expected.run_id {
    raise mismatch("$/run_id", "Run identity differs from the trusted manifest")
  }
  if actual.revision != expected.revision {
    raise mismatch("$/revision", "Revision differs from the trusted manifest")
  }
  if actual.deny_recovered != expected.deny_recovered {
    raise mismatch(
      "$/deny_recovered", "Recovery gate policy differs from the trusted manifest",
    )
  }
  if actual.plan_sha256 != expected.plan_sha256 {
    raise mismatch(
      "$/plan_sha256", "Full expected inventory differs from the trusted manifest",
    )
  }
  if actual.missing_reports != expected.missing_reports {
    raise mismatch(
      "$/missing_reports", "Missing report inventory differs from the trusted manifest",
    )
  }
  if actual.documents.length() != expected.documents.length() {
    raise mismatch(
      "$/documents", "Accepted report count differs from the trusted manifest",
    )
  }
  for i, document in actual.documents {
    let receipt = expected.documents[i]
    let path = "$/documents/" + document.binding.id
    if document.binding != receipt.binding {
      raise mismatch(
        path, "Report identity or full binding differs from the trusted manifest",
      )
    }
    if document.utf8_bytes != receipt.utf8_bytes ||
      document.sha256 != receipt.sha256 {
      raise mismatch(
        path + "/sha256",
        "Exact original XML bytes differ from the trusted manifest",
      )
    }
  }
  if actual.archive_sha256 != expected.archive_sha256 {
    raise mismatch(
      "$/archive_sha256", "Canonical archive digest differs from the trusted manifest",
    )
  }
}
