# CI evidence delivery

Create the evidence file, then build a new delivery directory:

```text
moon run --target wasm cmd/moontestledger -- collect examples/upstream/collection.json examples/upstream --output run-evidence.json
moon run --target wasm cmd/moontestledger -- ci-report run-evidence.json ci-evidence
moon run --target wasm cmd/moontestledger -- verify-delivery ci-evidence
```

The first command returns 0 on valid evidence creation. The last two return the evidence's original gate: 0 passing, 1 adverse result/denied recovery, 3 incomplete. The real Jest example returns 1 while preserving all six cases and four failures. Invalid input, output failure or inconsistent delivery returns 2 with JSON diagnostics on stderr. Wasm and native CLI commands accept arbitrary valid evidence archives; no repository-specific run/test identity is hardcoded.

The new directory contains exactly six regular files:

| File | Content |
| --- | --- |
| evidence.json | Canonical full plan, policy and exact original XML |
| summary.json | Complete summary including missing reports/cases and all attempts |
| integrity.json | Full-plan/archive/XML SHA-256 manifest |
| report.html | Escaped, offline read-only report |
| evidence.zip | Sealed full-plan XML pack |
| delivery.json | Versioned `mtl-ci-delivery-v1` completion receipt and original gate |

Validation, serialization, rendering and ZIP construction finish before directory creation. Existing destinations are refused. The completion receipt is written last; write failure attempts to remove only the newly created files/directory. Process termination, power loss and hostile concurrent filesystem races are outside this publication guarantee. Existing default source/HTML/ZIP limits still apply and oversized output is refused rather than truncated.

`verify-delivery` needs only this directory. It refuses missing/extra/hidden members, symlinks and special file kinds, checks the receipt's named profile before interpreting its evidence, replays the full evidence, regenerates the version-1 delivery and compares every file byte-for-byte in bounded chunks. Formatting edits and independently recompressed ZIPs are different representations even when they preserve meaning. The supported v1 representation is locked by [historical artifact golden files](../examples/golden/delivery-v1/README.md); compiler/dependency/renderer upgrades must preserve these checks. An intentional representation change needs a new profile with the old path retained. Unknown profiles return `DeliveryProfileUnsupported`, rather than an assertion that the evidence is corrupt. No automatic migration is implemented. Correction restores normal verification without modifying evidence. A self-consistent bundle does not authenticate its sender: independently trust its evidence/manifest where authenticity matters.

## GitHub Actions integration

[evidence-example.yml](https://github.com/jhshuai/MoonTestLedger/blob/main/.github/workflows/evidence-example.yml) is a manual workflow with collection-specification and artifact-directory inputs. It collects the full inventory, creates the delivery, and uploads it with `if: always()` so failures/missing tests retain reviewable evidence. The job still fails when the gate is nonzero. The bundled default uses the real failing Jest fixture; its red job result is expected. In a real pipeline, place report-producing jobs before these steps and give every producer the same full declared plan. The tool does not execute tests or infer a complete plan from received reports.

Upload/download transport is supplied by [actions/upload-artifact](https://github.com/actions/upload-artifact) and [actions/download-artifact](https://github.com/actions/download-artifact) (MIT), referenced as external actions, not copied. The artifact is retained for seven days in the example; archive independently if longer retention is required. Actual CLI creation/verification is tested in the standard CI matrix; no Mooncakes publishing step or token is configured.

The creation job records the exact `evidence.json` file SHA-256 and its original gate as **job outputs outside the artifact**. Even if that job fails at the test gate, `verify-download` runs on another runner, downloads the artifact, replays its original gate, and compares against those creation outputs. No `continue-on-error` masks a failed/missing gate. Its final assertion step checks that transport and offline replay worked even when the preceding real gate step is red. Missing artifacts, changed evidence, wrong expected hashes/gates or malformed receipts fail verification. This is agreement with the trusted creation job, not artifact-sender authentication.

Manual scenarios (`collection`, `artifact_root`):

| Scenario | Inputs | Original gate / expected workflow conclusion |
| --- | --- | --- |
| Real failing Jest | examples/upstream/collection.json; examples/upstream | 1 / failure, artifact retained, transport assertions pass |
| Entire Jest report absent | examples/upstream/collection.json; examples/history | 3 / failure, full six-case inventory retained, transport assertions pass |
| Passing Surefire parameters | examples/producers/passing-collection.json; examples/producers | 0 / success, both exact parameterized identities retained |

The missing example deliberately chooses an existing directory with none of the declared XML; it does not shrink the plan. Run the manual workflow in the GitHub Actions UI, inspect both jobs and download `test-evidence`. Actual run/step/artifact observations are recorded separately from the configuration in the validation record. Merely adding the workflow is not an upload test.

All three scenarios actually ran at `477835a` on 2026-10-28; links, expected red/green conclusions, downloaded original bytes and API digest provenance are retained in the [historical corpus](../examples/golden/delivery-v1/README.md). The main 12-job CI for that revision separately passed [40571711592](https://github.com/jhshuai/MoonTestLedger/actions/runs/40571711592).

`moon run scripts/delivery-e2e.mbtx wasm` / `native` exercise failing, incomplete, recovered and denied-recovery evidence, mutate each of the six members, remove the completion receipt, add a hidden file, replace HTML with a directory, refuse overwrite/invalid input and recover after correction. Unit tests check exact EOF, size boundaries around 64 KiB, and Unix native symlink refusal. The library public API is unchanged; the contribution is the complete declared-evidence handoff and verification workflow, complementary to generic XML/compression and GitHub report publication tools.
