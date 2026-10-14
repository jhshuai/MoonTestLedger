# MoonTestLedger

**Know whether a CI test run is complete, and retain what happened before a retry passed.**

MoonTestLedger is a MoonBit library and local command-line tool for teams collecting JUnit XML from sharded, retried or multi-environment CI jobs. A declared inventory records expected report IDs, exact testcase identities, revision, environment, shard and attempt order. The ledger reconciles received evidence against that inventory.

A missing artifact stays incomplete. A failing attempt followed by a passing attempt becomes **recovered_on_retry**, with both observations retained. Conflicting replacements and mismatched revisions return diagnostics.

Source repository: [jhshuai/MoonTestLedger](https://github.com/jhshuai/MoonTestLedger). The module path is **jhshuai/moontestledger**; the package has not been published to Mooncakes. See [the ecosystem review](docs/ecosystem-review.md) for demand evidence, nearby MoonBit APIs and the limits of the differentiation claim.

## Current capability

- Explicit report and testcase inventory, environment partitioning and declared retry order.
- A bounded common JUnit XML profile, original-source retention and structured diagnostics.
- Atomic ingestion, idempotent identical imports and refusal of conflicting replacements.
- Deterministic JSON evidence, strict versioned plan/bundle JSON and CI exit codes.
- **capture** to obtain an inventory from supplied reports, and **audit** for arbitrary report files.
- Replayable evidence archives retain the plan, original XML, bindings and recovery policy; **verify** rechecks a saved run without its original files.
- Historical comparison detects regressions and improvements while retaining added, removed and unknown test evidence.
- Merge partial archives of one run against an identical full inventory and recovery policy.
- Offline HTML reports show verdicts, missing evidence, every attempt/problem and escaped original XML.
- Selective retry continuation schedules only final adverse tests and appends their new reports atomically.
- Same-revision repeated-run analysis distinguishes observed outcome mixtures, run counts, retry counts and missing evidence.

Additional producer profiles, TAP/SARIF adapters, report rewriting, interactive dashboards and hosted integrations are roadmap items. No performance or universal JUnit compatibility claim is made.

## Inspect repeated runs at one revision

~~~sh
moon run --target wasm cmd/moontestledger -- archive examples/repetitions/plan-a.json examples/repetitions/bundle-a.json > repeat-a.json
moon run --target wasm cmd/moontestledger -- archive examples/repetitions/plan-b.json examples/repetitions/bundle-b.json > repeat-b.json
moon run --target wasm cmd/moontestledger -- repetitions repeat-a.json repeat-b.json
~~~

This project-authored synthetic example observes the payment test fail and pass in two independent runs of the same revision/environment. One row is `mixed_outcomes`; the command exits 1. Exact environment/classname/name inventory must agree. Shard placement, report IDs and selective retry counts can differ; run IDs must be distinct. Different revisions, inventories or recovery policies are refused with exit 2. Use `compare` for revisions and `merge` for shards of one run. Run/environment labels are caller-supplied contracts, not proof of identical machines, isolation or random test selection.

`analyze_repetitions(inputs[:], limits~)` returns opaque `Repetitions`. `rows()` returns independent samples with every attempt/problem; `summaries()` retains per-run missing evidence; `source(run_id, report_id)` retains original XML. JSON is a deterministic **derived count view**, with missing evidence, per-run references and final verdicts. Preserve input archives for replay; it has no decoder. Each row counts passed/failed/error/skipped attempts separately, distinct runs containing pass or failure/error, recovered runs and incomplete case observations. A run can contribute to both pass and failure counts. Retries can therefore increase attempt counts without increasing the independent run count.

Kinds are `mixed_outcomes` (both pass and failure/error observed), `failure_observed`, `pass_observed`, `skips_only` and `no_observations`. Skips never count as passes. Any missing report/case, including an empty report, makes the gate inconclusive (3), even when a mixture was observed. Complete evidence with a mixture exits 1; otherwise 0. A consistently failing test can yield repetitions 0 while verify yields 1. This is an observation gate, **not a statistical flakiness estimate, causal diagnosis or all-tests-pass gate**. Use verify for each run where passing is required. Small or selected samples cannot establish reliability.

Limits apply across the whole analysis: at least two archives; run count and combined planned reports bounded by `max_reports`; combined expected observations by `max_cases`; problem payloads by `max_problems`; total canonical archive JSON units by `max_total_source_units`. Each input is revalidated against individual limits. CLI also bounds combined incoming JSON text. Derived output is bounded by `max_source_units` and refused with `RepetitionOutputLimit`, never truncated. Output and sample order are deterministic under input reordering.

## Schedule and collect a selective retry

~~~sh
moon run --target wasm cmd/moontestledger -- archive examples/continuation/plan.json examples/continuation/bundle.json > failed.json
moon run --target wasm cmd/moontestledger -- retry failed.json examples/continuation/reports.json > pending.json
moon run --target wasm cmd/moontestledger -- verify pending.json
moon run --target wasm cmd/moontestledger -- append pending.json examples/retry/retry-only-bundle.json > recovered.json
moon run --target wasm cmd/moontestledger -- verify recovered.json
~~~

The synthetic payment run begins with one failure. `retry` extends its **full** plan by one attempt for the failed case; pending verify exits 3. After the caller's test runner executes that exact selection, `append` adds its XML while retaining all old evidence; recovered verify exits 0. The example supplies an already-authored retry report. MoonTestLedger does not execute your tests or generate framework selectors.

The retry identity manifest is `{"schema":1,"reports":[{"id":"payments-2","environment":"linux-node22","shard":"payments"}]}`. Supply exactly one fresh report ID per environment/shard with final failed/error/unresolved tests. Attempt numbers are computed from the last declared attempt. Passed, skipped and recovered tests are excluded. Missing existing evidence, omitted/extra/duplicate groups, reused IDs and resource-limit violations are refused. A recovered test stays recovered even after additional passing attempts, so a deny-recovered policy cannot be cleared by repeatedly retrying it.

Library flow: `prepare_retry(evidence, reports[:])` returns an independent pending `Evidence`; `pending.snapshot().plan` gives the next inventory; `pending.ingest_reports(documents[:])` returns a new archive. Both preserve run/revision, all old reports and recovery policy, and leave inputs unchanged. Append validates exact bindings and reparses original XML to refuse custom projections; its whole batch is atomic. Identical reports are idempotent; conflicting content is refused. CLI retry/append exit 0 on archive creation, 2 on refusal; `verify` remains the 0/1/3 test gate. Write the new archive to a **different path**: shell redirection to the input file can truncate it before the CLI reads it.

## Read evidence offline

~~~sh
moon run scripts/render-demo.mbtx wasm
~~~

Open `output/jest-report.html` in a browser. The script writes UTF-8 files directly and creates a replayable archive alongside the report. It uses the unmodified public Jest fixture: six tests, four failures. The page shows the gate, verdict counts, missing reports/cases, per-case attempts with all failure/error messages, types, text and XML locations, plus the full declared inventory and original XML (including empty reports and inert output). Expand the report sections to inspect source. It uses no JavaScript, fonts, images or network assets; its content security policy blocks active/network content. Test-controlled names, metadata and payloads are rendered only as escaped text.

For your own saved evidence:

~~~sh
moon run --target wasm cmd/moontestledger -- html evidence.json > report.html
~~~

Creation exits 0 even when the recorded gate fails or is incomplete; keep `verify evidence.json` as the CI gate. Invalid evidence exits 2 with a JSON diagnostic on stderr and no HTML on stdout. `render_evidence(evidence, max_output_units~)` is the portable library API. Its default budget is 33,554,432 UTF-16 output units, including markup/escaping; allowed budgets are 1–268,435,456 units. Oversized output is refused with `HtmlOutputLimit`, never truncated. `Evidence::snapshot()` returns independent inventory/document copies. The HTML is a read-only derived view; preserve the JSON archive for exact replay. It does not render historical comparisons or accept arbitrary HTML themes.

## Combine distributed evidence

Every producer must receive the same **full run plan**, even when it uploads only one shard or retry. Archive those partial bundles separately:

~~~sh
moon run --target wasm cmd/moontestledger -- archive examples/retry/plan.json examples/retry/missing-bundle.json > initial.json
moon run --target wasm cmd/moontestledger -- archive examples/retry/plan.json examples/retry/retry-only-bundle.json > retry.json
moon run --target wasm cmd/moontestledger -- merge initial.json retry.json > combined.json
moon run --target wasm cmd/moontestledger -- verify combined.json
~~~

The two synthetic partial archives each remain incomplete; their combination completes the declared retry workflow and exits verify 0 with the original failure retained. Merge emits an archive and exits 0 on creation, or 2 on invalid input. Missing artifacts still produce verify 3. It refuses different run IDs, revisions, report bindings, testcase inventories or recovery policies; it never unions plans. Identical duplicate documents are idempotent, while different XML for the same report ID is a conflict, including whitespace changes.

`merge_evidence(inputs[:], limits~)` provides the library workflow. It accepts 1 to `max_reports` archives, leaves inputs untouched and reapplies budgets to the combined unique documents. Report/case inventory order is canonicalized, so input ordering cannot change output. Each report's original XML and observation order remain intact. Encoding also enforces the archive size budget; no partial archive is emitted on rejection. Use comparison for separate runs.

## Compare two runs

~~~sh
moon run --target wasm cmd/moontestledger -- archive examples/history/before-plan.json examples/history/before-bundle.json > before.json
moon run --target wasm cmd/moontestledger -- archive examples/history/after-plan.json examples/history/after-bundle.json > after.json
moon run --target wasm cmd/moontestledger -- compare before.json after.json
~~~

This synthetic payment example reports one regression, one improvement and one unchanged skipped test, with exit 1. The library operation is `compare_evidence(before, after)`. Comparison is opaque; `changes()`, `before()` and `after()` return independent copies with complete attempt/problem evidence, and `encode()` renders a deterministic status-difference view.

Matching uses exact environment, classname and name; shard moves are changes in placement, not removal plus addition. Separate runs/revisions are compared without combining their attempts. Failure/error/unresolved is more adverse than recovered-on-retry, which is more adverse than pass/skip. Increasing severity is a regression; a final pass or failure-to-recovery is an improvement. Failure-to-skip is a status change, never an improvement. Added adverse tests fail the comparison gate.

Compare exits 3 if either run is incomplete, a baseline test is absent from the current inventory, or recovery policy differs; it cannot approve a test removal or infer success from missing evidence. Otherwise it exits 1 for a new adverse result, or 0 for no new adverse result. This gate checks regressions: unchanged failures can yield compare 0 while verify still yields 1. Use both gates where all current tests must pass. Comparison JSON is a derived view; preserve the input archives for raw XML and use the API to inspect full diagnostics. It does not claim statistical flakiness or causation.

## Save and recheck evidence

~~~sh
moon run --target wasm cmd/moontestledger -- archive examples/upstream/plan.json examples/upstream/bundle.json > evidence.json
moon run --target wasm cmd/moontestledger -- verify evidence.json
~~~

Archive creation returns 0 when the file is successfully emitted, even for a failing or incomplete run. Verify returns the recorded policy's test gate code (0/1/3), or 2 for invalid input. The archive has a schema-1 `moontestledger/evidence` envelope, the full plan and inline original XML. It is independent of report paths. Missing reports remain missing. `--deny-recovered` on archive creation is retained when replayed.

Use `encode_evidence(ledger)` and `decode_evidence(text)` from the library. Evidence is opaque; `summary()`, `source(id)`, `exit_code()` and `encode()` expose independent results and canonical round trips. `Ledger::snapshot()` returns copied inventory and document arrays. Custom adapters whose observations do not match the supported JUnit parser cannot be archived with this codec: encoding rejects them instead of dropping their semantics. Archives are not signed provenance proofs.

The JSON source budget applies to the entire encoded archive (4,194,304 UTF-16 units by default); encoding refuses oversized output so the same limits can read it. Original XML, including metadata, output, whitespace and entities, is retained exactly as decoded Unicode. Keep archived files as UTF-8; older Windows PowerShell redirection may otherwise choose a different encoding.

## Run the examples

Install [MoonBit](https://www.moonbitlang.com/download/), then run from this directory:

~~~sh
moon version --all
moon update
moon run --target wasm cmd/moontestledger -- audit examples/upstream/plan.json examples/upstream/bundle.json
~~~

The bundled, unmodified Jest/JUnit report comes from dorny/test-reporter at a fixed commit. It contains six cases: one passed, four failed and one skipped. The inventory is complete, and the process exits **1** because failures remain. Its upstream producer project and license are linked in [example provenance](examples/README.md).

These additional commands demonstrate missing artifacts and selective retries:

~~~sh
moon run --target wasm cmd/moontestledger -- audit examples/upstream/plan.json examples/upstream/missing-bundle.json
moon run --target wasm cmd/moontestledger -- audit examples/retry/plan.json examples/retry/bundle.json
moon run --target wasm cmd/moontestledger -- audit examples/retry/plan.json examples/retry/bundle.json --deny-recovered
moon run scripts/e2e.mbtx wasm
~~~

Their exit codes are **3**, **0** and **1**, respectively. The retry scenario is synthetic and labeled as such. Its bundle deliberately lists attempt 2 first; the plan still orders observations by declared attempt.

Replace the target with native to execute the native CLI. Native requires the platform C compiler and development SDK; on Windows this MoonBit release requires MSVC-compatible tools and the Windows SDK. Core library targets are Wasm, Wasm-GC, JavaScript and native. The file CLI currently supports **Wasm and native**. Wasm file/process I/O runs through moonrun host services, not a browser or a generic WASI runtime.

## Adopt the workflow

1. Obtain testcase identities from a test discovery step or a reviewed, known-complete baseline.
2. Produce the run plan for the current revision. Declare every shard, environment and planned retry subset.
3. Bind each uploaded artifact to its report ID, run, revision, environment, shard and attempt.
4. Audit the plan against the collected bundle and use the exit code as the gate.

To reduce manual inventory entry:

~~~sh
moon run --target wasm cmd/moontestledger -- capture examples/upstream/bundle.json
~~~

Capture emits a schema-1 plan to standard output. It records only supplied reports and cases. It cannot establish that a producer discovered or ran every intended test; review the baseline and regenerate the plan when discovery changes. A binding is a caller-supplied contract, not cryptographic proof of origin.

The plan's JSON shape is:

~~~json
{
  "schema": 1,
  "run_id": "ci-1042",
  "revision": "your-commit",
  "reports": [{
    "id": "payments-1",
    "environment": "linux-node22",
    "shard": "payments",
    "attempt": 1,
    "cases": [{"classname": "checkout.payment", "name": "charge_once"}]
  }]
}
~~~

Each bundle document adds run_id, revision and path to the report binding:

~~~json
{
  "schema": 1,
  "documents": [{
    "id": "payments-1",
    "run_id": "ci-1042",
    "revision": "your-commit",
    "environment": "linux-node22",
    "shard": "payments",
    "attempt": 1,
    "path": "reports/payments.xml"
  }]
}
~~~

Relative report paths resolve against the **bundle file's directory**. Absolute paths are permitted. The caller controls the bundle and filesystem access. Unknown fields, duplicate decoded JSON keys, unsupported schema versions and fractional/out-of-range attempt numbers are refused.

## Library API

Import jhshuai/moontestledger from a local dependency during development. The root facade re-exports public types owned by ledger and wire; concrete types' constructors, fields and methods remain available, while Ledger is opaque. A [tested consumer example](facade_test.mbt) is included.

For sibling folders named MoonTestLedger and consumer, place a workspace file in their parent directory:

~~~mbt
// moon.work
members = ["MoonTestLedger", "consumer"]
~~~

Add the module and package imports to the consumer:

~~~mbt
// consumer/moon.mod: alongside the consumer's own name/version
import { "jhshuai/moontestledger@0.1.0" }

// consumer/moon.pkg
import { "jhshuai/moontestledger" }
~~~

Workspace membership resolves this unpublished module from local source; the version selector is ignored for that workspace member. This follows [current MoonBit workspace dependency guidance](https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html#dependency-management).

The smallest useful flow is:

~~~mbt
fn reconcile(plan_json : String, binding : @moontestledger.ReportBinding,
             xml : String) -> String raise @moontestledger.InputError {
  let plan = @moontestledger.decode_plan(plan_json)
  let ledger = @moontestledger.Ledger::new(plan)
  let report = @moontestledger.parse_junit(xml, report_id=binding.id)
  ledger.ingest({ binding, report })
  @moontestledger.encode_summary(ledger.summary())
}
~~~

RunPlan::new validates programmatic inventories. Limits::default supplies budgets. Ledger is opaque: downstream callers cannot access its mutable inventory or document storage. Ledger::source(report_id) returns the original accepted XML. Ledger::summary() returns an independent snapshot, and Summary::exit_code(deny_recovered=true) implements a stricter recovery policy. Generated pkg.generated.mbti files document the actual public interface.

## Outcomes and exit codes

| Exit | Meaning |
| --- | --- |
| 0 | Complete; all final cases passed, skipped or recovered, according to policy |
| 1 | Complete with final failure/error, unresolved failure followed by skip, or denied recovery |
| 2 | Invalid plan, bundle, XML, arguments or file I/O; diagnostic on standard error |
| 3 | Missing report or expected testcase; incomplete evidence takes precedence |

A received XML report may omit an expected case; this yields incomplete evidence. Unexpected cases are refused. Attempts are consecutive from 1 within each environment/shard. Retry inventories may select a subset of the first attempt's cases. A (classname, name) identity may appear in separate environments but cannot belong to two shards within one environment.

The final observed outcome normally determines the case verdict. Prior failure/error plus final pass means recovery. Prior failure/error plus final skip remains unresolved. Missing expected evidence yields incomplete. Recovered-on-retry describes observations; it does not establish that a test is statistically flaky.

## Input profile and preservation

JUnit XML has multiple producer conventions, so this version supports an explicit common profile:

- One testsuite or testsuites root, nested suites and exact testcase classname/name identities.
- Failure, error and skipped markers with retained messages/types/text; every failure/error payload is retained.
- Properties and standard-output/error subtrees preserved in the original source.
- XML 1.0, decoded Unicode input; the CLI requires strict UTF-8. An encoding declaration, when present, must identify UTF-8.
- Checked descendant counters for tests, failures, errors and skipped when supplied.

Supported result-node attributes are listed in [the format contract](docs/formats.md). Unknown attributes or structural/outcome extensions are refused. DTDs, external entities, namespaced result elements, duplicate identities, malformed XML, contradictory counters and ambiguous skip-plus-failure evidence are refused. Custom inert data can remain inside properties/output subtrees.

Default library limits are 256 reports, 100,000 expected/accepted observations, 4,194,304 UTF-16 source units per input, 33,554,432 total retained XML units, 500,000 XML events, depth 128, 128 attributes per element and 10,000 problem payloads. JSON nesting is capped at 64. Limits are validated and bounded.

Summary JSON is a derived evidence view, not a lossless JUnit conversion. It includes case outcomes, ordered attempts, diagnostics and failure/error text. Inert XML metadata/output remains available through retained source. Input files are never rewritten.

## Verify transferred or retained evidence

~~~sh
moon run scripts/render-demo.mbtx wasm
moon run --target wasm cmd/moontestledger -- check-integrity output/jest-evidence.json output/jest-integrity.json
~~~

The demo saves the unmodified upstream Jest report as an archive, HTML and checksum manifest. `check-integrity` validates every component then returns the original test gate: this six-test/four-failure example exits **1**, even though integrity succeeds. Missing evidence still exits **3**. A mismatch or invalid input exits **2** with a diagnostic and no summary. No private infrastructure is required. Wasm/native file CLIs and all four library backends are supported.

For an existing archive, `integrity evidence.json` emits a schema-1 manifest to stdout and exits 0 on creation. Save it separately as UTF-8. Keep the expected manifest in a trusted location or verify its digest/signature through your existing CI artifact infrastructure; anyone who can rewrite both archive and manifest can recompute the checksums. This feature does not sign artifacts, authenticate authors, prove test execution or replace an attestation service.

Library flow: `let manifest = evidence.integrity(); let saved = manifest.encode(); evidence.check_integrity(decode_integrity(saved))`. These operations accept `limits~`. The opaque manifest exposes independent `documents()` receipts (full binding, lowercase SHA-256 and UTF-8 byte length) and `missing_reports()`. It binds the **full** expected inventory, revision/run, recovery policy, accepted empty/partial reports and exact original XML; removing an expected test cannot be concealed by hashing only received reports. Mismatch diagnostics identify inventory, policy or report source. Inputs remain unchanged after refusal.

Archive JSON is revalidated and re-encoded before hashing, so JSON layout/object-key ordering can change; original XML whitespace and metadata remain significant. Case array order remains significant. The versioned `mtl-evidence-v1` contract is documented in [formats](docs/formats.md); it is not a general JSON canonicalization standard. Changing an archive through merge/retry/append requires creating a new manifest. The pinned experimental `moonbitlang/x` SHA-256 implementation is reused, with known-answer and real-fixture checks; no cryptographic audit is claimed.

## Portable XML file packs

~~~sh
moon run scripts/render-demo.mbtx wasm
moon run --target wasm cmd/moontestledger -- detach output/jest-evidence.json output/jest-pack
moon run --target wasm cmd/moontestledger -- verify-pack output/jest-pack
moon run --target wasm cmd/moontestledger -- restore-pack output/jest-pack > restored.json
~~~

Use a **new directory** for detach. It creates `index.json` and flat `sha256-<digest>.xml` members, preserving the entire expected plan, source bindings and recovery policy. Exact identical sources share one physical member without merging their report identities. Both detach and restore-pack exit 0 on creation; the real Jest verify-pack exits 1 with the same original six-case/four-failure summary. Missing expected reports still yield 3; missing stored members, changed bytes and undeclared directory entries yield 2. Existing destinations are refused. XML remains ordinary UTF-8, directly readable by other tools. There is no ZIP/TAR container, compression, arbitrary file bundling or new trust/signature mechanism.

Portable library flow: `let (index, files) = evidence.detach(); let loaded = decode_pack_index(index.encode()); let restored = loaded.restore(files[:])`. `PackFile` has `name` and `xml`; `PackIndex` is opaque and exposes `filenames()`. Every operation validates limits and refuses unsupported content. Strict member validation precedes complete XML replay and archive digest verification. CLI checks the closed member set, regular-file kinds and symlinks, creates new files exclusively and publishes the index last. Failed publication attempts clean up only files successfully created by that operation; no transactional guarantee against concurrent hostile filesystem changes is claimed. The current input/inline replay budget still applies: this feature does not bypass archive size limits. Keep the pack index independently trusted when that trust is required.

## Collect declared CI artifact directories

~~~sh
moon run --target wasm cmd/moontestledger -- collect examples/upstream/collection.json examples/upstream > collected-jest.json
moon run --target wasm cmd/moontestledger -- verify collected-jest.json
moon run --target wasm cmd/moontestledger -- collect examples/retry/collection.json examples/retry > collected-retry.json
moon run --target wasm cmd/moontestledger -- verify collected-retry.json
~~~

Both examples create replayable archives (creation 0). The unmodified real Jest evidence verifies at 1 with all six cases/four failures. The synthetic retry example verifies at 1 because its declared policy denies recovery, retaining both attempts. Run against an empty artifact root with the same specification: the generated archive retains **every** expected report/case and verifies at 3. No test runner, CI account, glob discovery or private service is required.

`moon run scripts/render-demo.mbtx wasm` also saves `output/jest-collected.json` directly as UTF-8 and asserts that declared collection reproduces the original archive byte-for-byte. This avoids shell-specific output encodings; verify that saved archive as the gate.

A collection specification contains the full plan, recovery policy and exactly one `id`/relative `path` per expected report. `collect` reads only those declared paths under the supplied root, including explicitly named nested directories. Missing components mean missing evidence; inaccessible, malformed, symlinked or special-kind inputs refuse the whole operation. Unlisted files are outside the collection input set and are never read as XML; this is not directory-wide discovery. No report identities, attempts or revision labels are inferred from filenames. Labels are caller-owned contracts, not proof of artifact origin.

Portable APIs: `CollectionSpec::new(plan, files[:], deny_recovered~)`, `decode_collection(source)`, `spec.encode()`, `spec.files()` and `spec.collect(inputs[:])`. `CollectionFile` has `id`/`path`; `CollectedXml` has `id`/`xml`. The specification is opaque; constructors/codecs validate a full one-to-one mapping, relative path safety and case/file/directory-prefix collisions. Collection returns an independent archive, rejects duplicate/unknown IDs and unsupported XML, and preserves absent reports/cases and exact sources. Use merge for independent collections against the same full plan, and verify as the test gate. Write generated archives to a separate path.

The first path profile accepts ASCII letters/digits, dot, underscore, hyphen and forward slash: at most 4096 characters, 32 components and 255 characters per component. Absolute paths, traversal, empty components, trailing dots, Windows device names and non-ASCII declared filenames are refused. The root directory itself may have Unicode characters. XML names/messages/source remain Unicode. Actual entry casing must match the declaration; case-colliding entries are refused for selected paths. Only declared directory prefixes are visited, with cached entry enumeration bounded by `max_events`. Existing source/report/case/problem/output budgets apply; access errors are never converted to absent reports. The CLI assumes a stable local filesystem and does not claim a sandbox against concurrent filesystem races.

## Development and validation

Use MoonBit v0.10.15 for this version. The validated toolchain is moonc v0.10.15+943464bfa / moon 0.1.20261012. Dependencies are pinned in moon.mod; the project uses current moon.mod and moon.pkg formats.

~~~sh
moon fmt
moon fmt scripts/e2e.mbtx scripts/verify.mbtx scripts/check-encapsulation.mbtx scripts/render-demo.mbtx
moon info --target wasm
moon check --target all --deny-warn
moon test --target all --deny-warn
moon run scripts/e2e.mbtx wasm
moon run scripts/e2e.mbtx native
~~~

Moon run scripts/verify.mbtx TARGET also snapshots the eight generated interfaces, regenerates them and checks drift, without requiring Git. Automation is written in MoonBit .mbtx. CI declares Linux, macOS and Windows jobs for the four library backends, plus applicable file CLI workflows. CI configuration is distinct from a successful remote run; [validation evidence](docs/validation.md) records what actually executed.

Core tests cover malformed input, exact identities, limits, inventory completeness, retry ordering, deterministic output, JSON round trips, exact numeric lexemes, atomic rejection and recovery, source preservation and caller-array isolation. A compile-negative probe verifies that downstream code cannot mutate the ledger's internal inventory.

## License and sources

Project code is [Apache-2.0](LICENSE). Bundled upstream reports remain MIT-licensed with their original notice. See [THIRD_PARTY.md](THIRD_PARTY.md) for dependency, fixture, documentation and CI references.
