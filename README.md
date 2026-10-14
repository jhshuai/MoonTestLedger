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

Additional producer profiles, TAP/SARIF adapters, report rewriting, dashboards and hosted integrations are roadmap items. No performance or universal JUnit compatibility claim is made.

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

## Development and validation

Use MoonBit v0.10.15 for this version. The validated toolchain is moonc v0.10.15+943464bfa / moon 0.1.20261012. Dependencies are pinned in moon.mod; the project uses current moon.mod and moon.pkg formats.

~~~sh
moon fmt
moon fmt scripts/e2e.mbtx scripts/verify.mbtx scripts/check-encapsulation.mbtx
moon info --target wasm
moon check --target all --deny-warn
moon test --target all --deny-warn
moon run scripts/e2e.mbtx wasm
moon run scripts/e2e.mbtx native
~~~

Moon run scripts/verify.mbtx TARGET also snapshots the seven generated interfaces, regenerates them and checks drift, without requiring Git. Automation is written in MoonBit .mbtx. CI declares Linux, macOS and Windows jobs for the four library backends, plus applicable file CLI workflows. CI configuration is distinct from a successful remote run; [validation evidence](docs/validation.md) records what actually executed.

Core tests cover malformed input, exact identities, limits, inventory completeness, retry ordering, deterministic output, JSON round trips, exact numeric lexemes, atomic rejection and recovery, source preservation and caller-array isolation. A compile-negative probe verifies that downstream code cannot mutate the ledger's internal inventory.

## License and sources

Project code is [Apache-2.0](LICENSE). Bundled upstream reports remain MIT-licensed with their original notice. See [THIRD_PARTY.md](THIRD_PARTY.md) for dependency, fixture, documentation and CI references.
