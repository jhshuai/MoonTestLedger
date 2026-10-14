# First capability: explicit CI report reconciliation

Status: the first local capability is implemented after demand and ecosystem review. README describes the current API/workflow; validation evidence distinguishes executed local checks from configured remote CI.

## Three real workflows

1. A pytest suite runs in multiple CI shards. A run plan records every expected report and case identity. One worker crashes before uploading XML. The CLI identifies the absent report/cases and exits incomplete rather than reporting the available passing shards as an all-pass run. Supplying the missing artifact completes the same plan without losing prior evidence.
2. A failed shard selectively retries failing tests at the same revision and environment. The plan declares attempt order and the expected cases for each attempt. A final passing attempt yields `RecoveredOnRetry`, retaining the failed attempt and diagnostic. A later skipped attempt does not erase an earlier failure. Artifacts from a different revision or environment cannot be combined as retries.
3. A polyglot or multi-platform repository collects report files twice or receives conflicting replacements. Byte-identical re-import of a known report is idempotent; conflicting content under the same report identity is refused without changing the ledger. Environment partitions stay separate. Case identity collisions and unknown outcome extensions cannot silently hide failures.

## Inputs and first-version boundary

- A versioned JSON plan binds a run ID and revision to report IDs, environment, shard, explicit attempt ordinal and exact expected case identities.
- Each report ID is supplied with actual JUnit-style XML and provenance. `classname` plus exact `name` is the first-version identity; parameterized names remain exact. The plan defines the identities; no fuzzy renaming or cross-platform path guessing.
- A retry may contain a subset of tests, but its expected subset must be explicit. The tool cannot reconstruct attempts a producer omitted.
- Both `<testsuite>` and `<testsuites>` are supported within the documented common profile, including nested suites, failure/error/skipped, output, metadata and entities as validated by the pinned XML reader.
- DTDs and external entities are refused. Unsupported outcome-bearing retry/custom nodes are refused, rather than treating a case as passing. Unknown inert metadata is preserved with the source; this tool produces a derived evidence report, not a rewritten JUnit document.
- Resource limits bound source size, depth, nodes, reports and cases. Invalid plans or documents return stable diagnostics with report ID and a source span/logical path where available.

## Public boundary

Concrete domain types belong to a public `ledger` package; `junit` is the format adapter; `wire` handles strict versioned JSON, replayable archives and same-run merging; `history` owns comparison semantics; `report` renders offline HTML; `cli` and `cmd/moontestledger` provide file I/O. A root facade re-exports public packages, without hiding concrete types in internal packages.

Implemented operations: construct and validate a run plan; construct a ledger; ingest a parsed report by declared ID; obtain an independent evidence summary; encode/decode versioned plans and bundles; parse a JUnit document with structured diagnostics. The file CLI captures supplied inventory and audits arbitrary files. Ingestion validates before mutation, allowing correction after errors.

## Correctness contract

- Completeness is established against the explicit plan, not observed totals. Missing reports and expected cases never imply success. Unexpected cases are diagnosed.
- Repeat imports with the same identity/content are idempotent. Conflicting replacements do not modify prior accepted evidence.
- Retry order is declared, never inferred from file order or timestamps. Each reported case outcome retains its attempts. `RecoveredOnRetry` is evidence of recovery, not a statistical claim that a test is flaky.
- Summary output is independent of document ingestion order and deterministic on all supported core backends.
- Duplicate case identities in one report or ambiguous shard membership are rejected. Separate environments and revisions are not interchangeable.
- Declared XML counters are checked where supplied; counts never replace case evidence.
- Failed/error evidence followed by skip is unresolved. A parser cannot ignore outcome-bearing extensions and return passing cases.
- Round-trip JSON must preserve every supported field; unknown schema versions, duplicate keys, malformed values and unsupported fields are rejected.
- Inputs and original report content remain unchanged. No source report overwrite, report upload or network operation belongs to the first capability.

## Independent first milestone

Deliver a reusable portable library and an arbitrary-file CLI: plan + report files -> complete/incomplete/error/failed/recovered evidence -> deterministic JSON and documented exit codes. Include metadata, Apache-2.0, tested examples, generated interfaces, bounded diagnostics, correctness tests and OS/backend CI in the same capability. The library covers Wasm, Wasm-GC, JavaScript and native; the file CLI covers Wasm through moonrun host I/O and native.

Acceptance requires actual report files from documented producers or clearly sourced upstream fixtures, plus an executed local end-to-end workflow. Example data provenance and licenses are recorded; synthetic boundary fixtures are identified as such. No private CI account or server is required.

## Roadmap

1. Explicit report and test inventory with ordered retry reconciliation (the complete first slice).
2. Additional named producer profiles with captured output and conformance tests, then an adapter for a versioned MoonBit test-result export if available. Internal runner protocols are not assumed stable.
3. Replayable evidence archives and historical comparisons are implemented: full plan, bindings, original XML and gate policy survive validation and round trips. Exact environment/test identity comparisons retain both runs' attempts, distinguish severity changes, and make missing/removed inventory or policy changes inconclusive.
4. Same-run archive merging and offline HTML rendering are implemented. Full plans/policies must agree before evidence can be combined. The read-only renderer retains attempts, diagnostics, missing inventory and original XML as escaped text, with a refusal rather than truncation when its output budget is exceeded.
5. Selective retry continuation is implemented: extend a complete run with exact final adverse identities and fresh group report IDs, then atomically collect new original XML into an independent archive. The test runner remains caller-owned; missing evidence cannot be bypassed by another retry.
6. Same-revision repeated-run analysis is implemented: distinct runs, exact shared testcase/environment inventory, separate retry/independent-run counts, full sample evidence and conservative incomplete gating. It describes observed mixtures, without claiming a statistical flakiness diagnosis.
7. Evidence integrity manifests are implemented: full inventory/policy/archive hashes, exact XML receipts and bounded strict offline verification. The existing test gate survives successful integrity validation. Trusted-manifest distribution/signature/attestation remains caller-owned.
8. Detached XML file packs are implemented: closed content-addressed members, full expected inventory, exact source deduplication, strict restoration and the original test gate. No general archive format or hosted storage is introduced.
9. Declared artifact-directory collection is implemented: strict full path mapping, bounded directory entry inspection and atomic original XML collection, with missing artifacts preserved. It composes with archive merging, integrity and detached file packs.
10. Additional named producer profiles and CI-specific transport adapters remain planned. General flaky classification/quarantine is outside this project's boundary; see the updated ecosystem review.

## Validation

Use current stable recognized `moon.mod`/`moon.pkg`, pin dependencies and record actual `moon version --all`. Run formatting and generated-interface drift checks, strict checks and real tests for wasm, wasm-gc, js and native. Execute the file CLI; distinguish native compilation from native execution, and distinguish local checks from unrun remote CI.

Core tests cover plan/report JSON round trips, integer and resource boundaries, malformed XML/JSON, entity identities, counters, unsupported semantics, missing reports/cases, retry failure->pass and failure->skip, import-order invariance, duplicate idempotence, conflict rejection and recovery after an error. Preserve original input and previously accepted evidence.
