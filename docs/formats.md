# Version 1 format contract

Complete future-inventory reviews use a separate schema-1 `moontestledger/plan-review` artifact. Its complete plans, derived changes, digest, strict decode and explicit baseline-bound approval contract are specified in [inventory review](inventory-review.md). Applying it cannot rewrite existing evidence and requires a fresh run ID.

## Plan and bundle

All JSON fields shown in README and the checked-in examples are mandatory; no additional fields are accepted. Schema is exactly 1. Attempt is an exact positive 32-bit integer. Strings are case-sensitive and not trimmed. Binding identifiers cannot be empty, whitespace-only or contain NUL. Classname can be empty; testcase names cannot be empty or whitespace-only.

The run plan contains at least one expected testcase. Report IDs are unique. Each environment/shard declares one report for each consecutive attempt starting at 1; a retry contains an explicitly declared subset of the initial inventory. The same testcase cannot belong to two shards in one environment.

Bundles can be empty (no artifacts have arrived). Repeated report bindings can be supplied: ingestion accepts an identical document and rejects a conflicting one. Report paths are data, not glob patterns; no report discovery or directory scanning occurs.

Decoded duplicate keys, including equivalent escaped names, are refused. Unknown fields and schema versions are refused to avoid silently dropping future semantics. JSON source size uses the configured per-source budget, and lexical nesting is capped at 64 before parsing.

## JUnit XML common profile

Allowed structural elements:

| Parent | Children |
| --- | --- |
| document | one testsuite or testsuites |
| testsuites | testsuite, properties, system-out, system-err |
| testsuite | testsuite, testcase, properties, system-out, system-err |
| testcase | failure, error, skipped, properties, system-out, system-err |
| failure, error, skipped | text and CDATA |
| inert properties/output subtree | original XML retained; outcomes are not inferred from it |

Allowed attributes on result nodes:

| Node | Attributes |
| --- | --- |
| testsuite, testsuites | name, package, id, tests, failures, errors, skipped, disabled, time, timestamp, hostname, file, assertions |
| testcase | name, classname, time, file, line, assertions, timestamp |
| failure, error, skipped | message, type |

Disabled must be zero if present. Nonzero disabled counters need producer-specific outcome semantics that this version cannot safely infer. Timing and location metadata remain in source; they do not affect outcome or identity.

One additional, closed metadata combination is accepted **only on the document-root `testsuite`**: `xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"`, `xsi:noNamespaceSchemaLocation="https://maven.apache.org/surefire/maven-surefire-plugin/xsd/surefire-test-report.xsd"` and `version="3.0.2"`, all present with those exact decoded values. This is the annotation actually captured from Surefire 3.5.2, not a general XML namespace/schema feature. No XSD is fetched or used to override validation; no default/result namespace, arbitrary namespace alias, unknown schema version/location, extra prefixed attribute or nested copy is accepted. Source keeps the annotation and all original metadata/output bytes. [Producer conformance](../examples/producers/README.md) records exact tested versions and limits.

Result nodes outside the allowlist, namespaces on result nodes, custom status/result attributes and embedded flakyFailure/rerunFailure conventions are refused. Express retries as separately bound documents and explicit attempts. Future producer profiles need real captured output and conformance tests before acceptance.

Declared suite counters include descendant testcases. Failure/error counts count cases carrying each kind, not the number of payload nodes. A case with both failure and error has an error outcome and retains both payload kinds. A skipped case cannot also contain failure/error and cannot declare two skipped markers.

Duplicate (classname, name) identities within one document are refused. Parameterized names and decoded entities are exact identities; suite names or file paths do not disambiguate duplicates.

DTD/entity declarations are refused; external resources are never fetched. The XML dependency validates XML well-formedness, decoded character/entity values, attribute uniqueness and the entire document through EOF. The adapter adds structural, count, semantics and resource checks.

## Diagnostics and derived evidence

Library errors carry code, report_id, logical path, message, line and column. Source locations are one-based when available; zero means not applicable. XML source offsets use UTF-16 units.

Ledger is an opaque type. Its mutable plan and document storage cannot be read or mutated by downstream code. The compile-negative encapsulation probe checks this contract, in addition to runtime tests for caller-array isolation.

The CLI emits one schema-1 diagnostic object to standard error on invalid input or I/O and returns 2. Audit summaries go to standard output. Users can correct an input and retry: failed ingestion does not mutate already accepted documents.

Summary JSON contains canonical environment/shard/case ordering, ordered attempts, all failure/error payloads and missing inventories. It does not provide a rewritten XML document or a parser for round-tripping summaries. Plan/bundle encoders and decoders cover the supported interchange round trip.

## Integrity manifests

Schema 1 has exactly `schema`, `kind` = `moontestledger/integrity`, `algorithm` = `sha256`, `canonicalization` = `mtl-evidence-v1`, `run_id`, `revision`, `deny_recovered`, `plan_sha256`, `archive_sha256`, `documents` and `missing_reports`. A document has exactly `id`, `run_id`, `revision`, `environment`, `shard`, `attempt`, `sha256` and `utf8_bytes`. Digests must be 64 lowercase hexadecimal digits. All identities are nonempty without NUL; bindings agree with the envelope; attempt/byte lengths are exact positive 32-bit integers checked against original JSON lexemes. Schema/algorithm/canonicalization extensions, unknown fields, duplicate decoded keys and duplicate IDs (including missing/accepted overlap) are refused. At least one report must be accounted for. Receipt and missing-ID order normalizes to report-ID order.

`mtl-evidence-v1` hashes UTF-8 of `Evidence::encode()` and `encode_plan(evidence.snapshot().plan)` with indent 2 and **no trailing newline**. These fixed encoders determine object-field and report ordering; report inventory is ordered by environment/shard/attempt/ID as in the ledger. **Case-array order is preserved and significant**. This is a project-versioned convention, not RFC 8785 or a hash of the incoming JSON file's bytes. JSON reformatting, object-key order and accepted document ingestion order normalize through replay. The per-document digest and byte length use UTF-8 of its exact decoded `xml`, including whitespace, comments, Unicode, inert metadata and output. No XML normalization occurs. The CLI's strict UTF-8 reader is unchanged; arbitrary binary inputs are unsupported.

Both source/output JSON are bounded by `max_source_units`; accepted + missing report counts by `max_reports`; receipt lengths cannot exceed four times the UTF-16 source budget. Creating/checking also revalidates the archive under all existing XML/inventory/aggregate budgets. No over-budget output is truncated. `IntegrityMismatch` identifies the envelope, inventory, missing reports, receipt binding/source or archive digest. A successful check means agreement with the supplied expected manifest; missing cases/reports and test failures keep the original gate and full summary. Manifest creation can succeed for incomplete evidence. Invalid/mismatched input emits only a diagnostic on stderr (exit 2); successful CLI checking returns the existing summary on stdout with its 0/1/3 gate.

Trust the expected manifest independently. Checksums do not authenticate the creator or prevent replacement of both files. No signature, timestamp, filesystem permission guarantee, security certification, generic hash-file command or statistical testing API is included.

## Declared directory collection

Schema 1 contains exactly `schema`, `kind` = `moontestledger/collection`, `deny_recovered` (boolean), `plan` (full schema-1 inventory) and `files`. Each file has exactly `id` and `path`. Every planned report needs one path regardless of current presence; unknown/omitted/duplicate identities are refused. Path-array order normalizes by exact report ID. Plan ordering remains the existing plan contract. Unsupported/duplicate/numerically rounded nested JSON is refused. The portable relative path alphabet is ASCII letters, digits, `.`, `_`, `-`, `/`, bounded by 4096 total characters, 32 components and 255 characters per component. Empty/absolute/traversal/trailing-dot components and Windows device stems are refused. Paths must have consistent exact component spelling, no case-folded aliases/shared files/file-versus-directory conflicts. Arbitrary OS paths, non-ASCII declared filenames, wildcard matching and symlink traversal are unsupported.

`CollectionSpec::collect` accepts any subset of declared `CollectedXml` reports, reparses each original XML, and returns a new complete-plan Evidence. Duplicate/unknown supplied IDs and unsupported projections are refused. An empty subset or missing expected cases stays incomplete; no authored expectation is removed. All input, inventory, combined XML, case/problem and archive output budgets apply. Invalid batches never return a partial successful archive or mutate the specification.

CLI `collect SPEC.json ROOT` returns 0 on archive creation and 2 on invalid data/I/O. Use `verify` for the archive's 0/1/3 gate. It visits only declared directory prefixes, enumerating entries once per distinct prefix and bounding total entry visits by `max_events`; enumeration stops on budget exhaustion. It requires a real root directory and checks existing path components without following symlinks. Absent listed components remain missing reports; access/read/case-ambiguity/kind errors are refused. Unlisted entries are not input XML and their contents are not read. Snapshots of directory listings are cached during one invocation; concurrent changes and cryptographic artifact origin authentication are outside this contract.

## Detached file-pack profile

The schema-1 index has exactly `schema`, `kind` = `moontestledger/file-pack`, `plan` (full schema-1 inventory), and `integrity` (the complete integrity manifest). Every planned report must have exactly one correctly bound receipt or an explicit missing-report ID. Plan/run/revision hashes must agree before member filenames are exposed. Filenames are derived solely as `sha256-<64 lowercase hex>.xml`; arbitrary paths are not part of the format. Identical XML sources deduplicate physical storage, but every report receipt/binding remains separate. Encoders and returned filename/member arrays are deterministic and independent copies. Unknown/duplicate/numerically rounded fields are refused as in other codecs.

Restore requires the exact unique filename set, checks UTF-8 byte lengths and SHA-256, reparses every declared report against the full plan, then checks the complete integrity manifest. No summary or supplied projection replaces original XML. All existing input, expected report/case, aggregate XML/problem and output budgets apply; unique member input bytes and expanded per-report replay are both bounded. A declared accepted member being absent is `MissingPackFile` (2); a report explicitly missing in the preserved plan remains incomplete (3). Undeclared members, duplicate inputs, changed XML and invalid file kinds are refused. This profile is not a generic archive/container or signed evidence standard. CLI reading assumes a locally stable directory, rejects symlink entries and requires regular files; concurrent filesystem races are outside the guarantee.

## Replayable evidence archives

The schema-1 envelope has exactly `schema`, `kind` (`moontestledger/evidence`), `deny_recovered` (boolean), `plan` (the complete schema-1 plan) and `documents`. Each document has exactly `id`, `run_id`, `revision`, `environment`, `shard`, `attempt`, and `xml` (original decoded XML). Duplicate report IDs are rejected. No report paths or projected summary replace the authored source.

Decoding reparses each XML and ingests it against the plan. Encoding checks that each accepted projection exactly matches its reparsed source, then checks the encoded JSON input budget. Unknown fields, duplicate JSON keys, unsupported versions, binding conflicts, malformed XML and resource violations are refused. Missing documents are allowed and remain incomplete. Canonical encoding orders documents by the validated plan. The supplied recovery policy survives round trips.

## Historical comparison

Only validated evidence archives enter the comparison API. Rows match exact `(environment, classname, name)`, independently of shard placement, and are sorted deterministically. Both original runs remain separate. Change kinds are added, removed, regressed, improved, changed, unchanged and unknown. Incomplete matched rows are unknown. Increasing severity from pass/skip to recovery to final failure/error/unresolved is a regression. Failure-to-skip cannot be an improvement.

The gate returns 3 for missing evidence, removed baseline inventory or differing recovery policies, before considering regressions. It returns 1 for a regression or added adverse testcase, otherwise 0. It is a regression gate, not a replacement for the current run's verify gate. Result getters return copied arrays including complete attempt/diagnostic payloads; JSON is a derived status view referencing both run IDs/revisions and listing missing evidence. There is no comparison-JSON decoder or fuzzy identity matching.

## Same-run merge contract

`merge_evidence` consumes validated evidence archives. The full plan must agree exactly in run/revision, report ID/environment/shard/attempt and testcase sets, ignoring inventory order. Recovery policy must agree. No inventory is inferred or unioned. Empty input is `EmptyMerge`; too many archives is `MergeLimit`; disagreement is `MergePlanMismatch` or `MergePolicyMismatch`. Conflicting report replacements retain the existing `ConflictingReport` diagnostic. Combined unique documents undergo normal ledger budgets; a failed merge cannot modify any input. Missing expected reports/cases remain incomplete. CLI merge creation exits 0; verify applies the test gate.

## Offline HTML

`render_evidence` accepts only validated archives. It is a deterministic derived read-only view with all case attempts, problem payloads and source XML, including accepted empty reports. Every untrusted value is emitted in text nodes, escaping ampersands, angle brackets, quotes and carriage returns. IDs/links, markup, CSS classes and verdict names are generated from fixed templates or numeric indices. No caller-supplied URL, HTML theme, script, remote asset or timestamps enter the page. A restrictive CSP complements escaping; it is not the sole protection. The default output budget is 33,554,432 UTF-16 units; valid settings are 1 through 268,435,456. `HtmlInvalidLimit` rejects invalid settings; `HtmlOutputLimit` rejects oversized output before returning any partial HTML. HTML has no replay decoder; retain the schema-1 JSON archive. CLI creation returns 0, malformed evidence returns 2, and verify remains the gate.

## Retry continuation

Retry identity manifests have only schema 1 and a reports array of `{id, environment, shard}`. Unknown fields, duplicate JSON keys, unsupported versions and non-string/empty/NUL values are rejected. `decode_retry_reports`/`encode_retry_reports` preserve manifest order and fields; scheduling ignores input order. Scheduling requires complete existing evidence and a fresh report ID for each group with final failed/error/unresolved tests. Its selective case set comes from exact identities, sorted by the existing summary; attempts increment the group's last declared ordinal. All original inventory/source and policy remain. `RetryIncomplete`, `NoRetryCases`, `DuplicateRetryGroup`, `UnexpectedRetryGroup`, `MissingRetryGroup` identify actionable refusal reasons; normal plan/ledger diagnostics cover invalid/reused IDs and limits. A scheduled retry is missing evidence until collected.

`Evidence::ingest_reports` accepts original parsed JUnit documents and returns a separate archive. It reparses each source, refuses `ProjectionMismatch`, applies normal bindings/conflict/combined unique evidence budgets, and is atomic for the entire batch. It can collect any already-declared missing report, not just a retry. CLI append reads an ordinary bundle with relative XML paths, bounds aggregate incoming source/observations/problems, and writes nothing before successful encoding. Both CLI operations exit 0 for creation and 2 for refusal; no archive schema change is needed. Failed retries can schedule another attempt; recovered cases cannot be scheduled to erase earlier adverse evidence.

## Same-revision repetitions

The analyzer requires two or more distinct run IDs at exactly one revision and recovery policy, with identical `(environment, classname, name)` initial testcase inventory. Retry inventory/report IDs and shard placement can differ. Invalid run count, duplicate run, revision, policy and inventory disagreement produce `RepetitionRunCount`, `DuplicateRun`, `RepetitionRevisionMismatch`, `RepetitionPolicyMismatch` or `RepetitionInventoryMismatch`. Incomplete archives participate with explicit missing observations; no inventory is inferred from received cases. Runs and rows are ordered deterministically using MoonBit's comparison of run IDs and identity tuples. Getters deep-copy summary/sample arrays and problem arrays; original XML remains available by run/report ID.

Counts include all accepted attempts rather than just final verdicts. Pass plus failure/error yields mixed observations, even inside a recovered run; skip never substitutes for pass. Independent-run counts separately identify any pass or failure/error in each run. Counts are descriptive, with no confidence interval, probability estimate, automatic quarantine or causality claim. Missing run evidence overrides the mixture gate: 3 incomplete, otherwise 1 mixed, 0 no mixture. Persistent failure is not success; verify remains the run gate.

Input budgets cover combined canonical archive JSON text, expected report/test observations and problem payloads; individual archives are revalidated. The schema-1 `moontestledger/repetitions` JSON contains derived counts, per-run missing evidence and sample references/verdicts; it does not replace replayable archives. `encode(limits~)` rejects oversized derived text with `RepetitionOutputLimit` before returning output. There is no derived-view decoder or archive/schema migration. Unsupported archive/XML data continues to be rejected by the existing strict codecs.
