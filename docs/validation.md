# Validation evidence

Status recorded during local development on 2026-10-13. All four target verifiers were repeated successfully on 2026-10-14 after changing the module path to jhshuai/moontestledger and preparing the initial GitHub submission. This file separates configured coverage from executed checks. Later source changes require the affected checks to run again.

## Toolchain

- Dedicated regular stable distribution: moonc v0.10.15+943464bfa (2026-10-12).
- Moon 0.1.20261012 (748b63c), moonrun 0.1.20261012.
- Windows distribution SHA-256: 6e3ef6cb96aa5086d122183972687f79fc912f80652000907d96ee6ad967e3bf.
- Linux distribution SHA-256: 24b93a5409d2a4fb8e3d1b84b473f27b63476cef4418094764df96cb26b03c09.
- Distribution checksums were compared against official checksum files. The user's global installation was not replaced.
- Pinned dependencies: Milky2018/xml@0.6.1, moonbitlang/async@0.22.4.

## Executed integrated checks

After the final exact-number and opaque-ledger fixes, the checked-in verifier executed formatting checks for packages and all three scripts; regenerated all six public interfaces with no drift; ran strict compilation with warnings denied; and executed tests on each applicable backend:

| Host / target | Strict check | Tests | File CLI evaluator |
| --- | --- | --- | --- |
| Windows / Wasm | passed | 40/40 | passed |
| Windows / Wasm-GC | passed | 37/37 | CLI not supported on this backend |
| Windows / JavaScript, Node | passed | 37/37 | CLI not supported on this backend |
| Ubuntu 22.04 under WSL / native, GCC 10.5 | passed | 40/40 | passed, native executable actually ran |

The three extra Wasm/native tests exercise host file path/UTF-8 I/O behavior. A separate six-case XML dependency safety probe also ran on Wasm-GC before integration.

The compile-negative encapsulation probe passed: downstream access to the ledger's mutable inventory was rejected. Generated interfaces expose `type Ledger`, without storage fields. An independent consumer module also resolved the unpublished module through a `moon.work` workspace, constructed the facade's public types, ingested a report and executed its passing summary on Wasm-GC.

The local Windows native attempt could not execute because the stable native driver requires MSVC-compatible build tools and a Windows SDK. GCC/MinGW does not satisfy the driver/dependency requirements. No Windows native runtime success is claimed for that local attempt; remote CI results are documented separately below.

The complete evaluator passed on both Wasm and actual Linux native: six-case upstream Jest report (exit 1), missing artifact (3), capture (0), synthetic ordered retry (0), denied recovery (1), and upstream pytest counter refusal (2).

Script mode emitted a dependency duplicate-import warning for async/internal/c_buffer. Earlier Linux native dependency compilation emitted C warnings around a GNU posix-spawn declaration and an ignored write result. Project MoonBit strict checks passed; the third-party C warnings are not hidden or described as a fully warning-free native toolchain build.

## Configured CI coverage

.github/workflows/ci.yml declares Linux, macOS and Windows with Wasm, Wasm-GC, JavaScript and native library checks/tests. Windows native sets up the MSVC environment. Wasm/native jobs additionally execute the end-to-end file CLI evaluator.

The workflow checks formatting, generated interface drift and project warnings as errors. The exact stable compiler/core release is pinned. Availability of versioned Windows, Linux, macOS ARM64 binary URLs and core was checked on 2026-10-13; server metadata advertises expiry on 2026-12-12.

These local results were collected before initial publication. The source remote is now [jhshuai/MoonTestLedger](https://github.com/jhshuai/MoonTestLedger); check [GitHub Actions](https://github.com/jhshuai/MoonTestLedger/actions) for each published commit's remote results. Configuring a matrix does not establish that its jobs passed. macOS and Windows native runtime compatibility remain unverified locally.

## Reproduction

From the module root:

~~~sh
moon update
moon run scripts/verify.mbtx wasm
moon run scripts/verify.mbtx wasm-gc
moon run scripts/verify.mbtx js
moon run scripts/verify.mbtx native
~~~

The current verifier snapshots all eight tracked generated interfaces, regenerates with the Wasm target and compares their contents. It works from a source archive and does not need a Git repository. MOON_TEST_LEDGER_MOON may point to the executable used by child commands when multiple installations are present. Native requires the target platform's compiler/SDK. The evaluator's local report fixtures have documented public provenance.

## Evidence archive capability — 2026-10-14

The archive addition passed strict checks, formatting and six-interface drift verification. Tests: Wasm 45/45, Wasm-GC 42/42, JavaScript 42/42, Linux native 45/45. Wasm and actual Linux native file workflows now also create and verify archives of the unmodified upstream Jest report, preserve an incomplete run, and retain denied-recovery policy. Unit tests cover exact source/payload round trips, isolated snapshots, decoded schema/unknown-field/duplicate rejection, binding mismatch, custom-projection refusal, source limits and recovery after errors.

Its [remote CI run](https://github.com/jhshuai/MoonTestLedger/actions/runs/38514448535) completed successfully for commit 4847db2124178670c7d25cdfba51df3f909e4ce9, including the configured three-OS/four-target matrix and applicable native CLI execution.

## Historical comparison capability — 2026-10-14

The comparison addition passed strict checks, package/script formatting and seven-interface drift verification. Tests: Wasm 53/53, Wasm-GC 50/50, JavaScript 50/50, Linux native 53/53. Wasm and actual Linux native end-to-end evaluators compare the real upstream archive to itself, reject a missing-evidence comparison as inconclusive, and report one regression and one improvement between the documented synthetic payment runs.

Tests cover severity transitions including retry recovery, added adverse cases, removed inventory, unknown observations, policy differences, shard moves, distinct environments, inconclusive-result precedence, deterministic output, retained unresolved attempts and deep-copy isolation. A comparison success means no new adverse result; it does not replace the current archive's verify gate.

Its [remote CI run](https://github.com/jhshuai/MoonTestLedger/actions/runs/38516257549) passed all 12 matrix jobs for c74931933430bc6d413fd9ee53738b806dcd6f7b.

## Same-run archive merge — 2026-10-14

Formatting, seven-interface drift verification and strict checks passed. Tests: Wasm 56/56, Wasm-GC 53/53, JavaScript 53/53, actual Linux native 56/56. Wasm/native end-to-end execution archives independent initial/retry bundles against one full plan, merges duplicate/reordered inputs, verifies retained recovery, and rejects merging different runs. Unit tests cover commutativity, associativity and idempotence for accepted inputs, inventory-order normalization, exact source retention and codec round trips, incomplete evidence, plan/revision/run/policy mismatch, conflicting replacement, inclusive combined source budgets, input-count and case limits, unchanged inputs and recovery after refusal. Remote results for this new commit are recorded by GitHub Actions after publication.

Its [remote CI run](https://github.com/jhshuai/MoonTestLedger/actions/runs/38521598926) passed all 12 matrix jobs for 4bb1b38d78adb04df62190c403fea6e1ccec8f51; the pushed main hash matched the local commit.

## Offline HTML capability — 2026-10-14

Package/four-script formatting, eight-interface drift verification and strict compilation passed. Tests: Wasm 59/59, Wasm-GC 56/56, JavaScript 56/56, actual Linux native 59/59. Wasm and Linux native end-to-end execution renders the real failing Jest archive, missing evidence and a merged recovered retry, checks deterministic output, and verifies malformed-input diagnostics. `scripts/render-demo.mbtx wasm` executed and wrote UTF-8 HTML plus replayable JSON from the documented unmodified upstream report.

Renderer tests exercise hostile names, revision, report IDs, message/type text, CDATA script/iframe markup, Unicode, all problem payloads, original metadata/output, accepted empty reports, both retry attempts, missing-report/case precedence, denied recovery, independent snapshot mutation, exact output-budget boundary, invalid budgets and successful reuse after refusal. The browser automation tool rejected local `file:` navigation, so no browser visual preview success is claimed; content/escaping/CLI checks are executed evidence. Remote coverage for this commit is reported by its GitHub Actions run after publication.

Its [remote CI run](https://github.com/jhshuai/MoonTestLedger/actions/runs/38524569042) passed all 12 matrix jobs for a5b7fb6edfc132b0918bd64373b7e480ae94de08; the remote main hash matched the local commit.

## Selective retry continuation — 2026-10-14

Package/script formatting, eight-interface drift verification and strict compilation passed. Tests: Wasm 65/65, Wasm-GC 62/62, JavaScript 62/62, Linux native 65/65. The native source copy on the Linux filesystem was compared byte-for-byte with the workspace (excluding Git, build/cache/output directories); no source differences were found. The first native evaluator subprocess reported `Unexpected end of file`. A direct native CLI audit then executed correctly, and the complete native end-to-end evaluator passed on rerun. The EOF cause was not established and is not presented as a repaired product defect. Existing third-party duplicate-import/C warnings remain as described above.

Wasm and actual native workflows archive a complete failed run, derive the selective next inventory, confirm pending verify 3, append the retry XML, confirm recovered verify 0, repeat append idempotently and refuse rescheduling recovered tests. Unit tests cover failure/error/unresolved selection, next ordinal, deterministic group input ordering, missing/unknown/duplicate/reused report identities, incomplete input refusal, unchanged inventory/source/policy, retained original payloads, whole-batch atomic conflict/projection/binding/unexpected-case refusal and recovery, partial evidence, inclusive report/case/source budgets, strict manifest decoding and serialization round trips. New example JSON reuses only project-authored Apache-2.0 synthetic payment fixtures. Remote results for the new commit are recorded by GitHub Actions after publication.

Its [remote CI run](https://github.com/jhshuai/MoonTestLedger/actions/runs/38554028794) passed all 12 matrix jobs for a84876df60e6eccc60e09ac9312f2b43977fc2f5; remote main matched the local commit after retrying a connection failure.

## Same-revision repeated-run analysis — 2026-10-14

Formatting, eight-interface drift checks and strict compilation passed. Tests: Wasm 70/70, Wasm-GC 67/67, JavaScript 67/67, actual Linux native 70/70. The Linux-filesystem validation copy was compared with the workspace with no source differences, excluding Git/build/cache/output directories. Its integrated native verifier completed successfully, including real executable CLI workflows. Third-party import/C warnings remain recorded above.

Wasm and native evaluators analyze two distinct synthetic payment runs at one revision, report exactly one mixed-outcome row despite a shard move, check input-order determinism, refuse duplicate run IDs, and make missing-run evidence inconclusive. Unit tests retain original XML and every attempt/problem through independent getters; separate retries from independent-run counts; cover failure/error/pass/skip/no-observation categories and recovery; retain mixtures with incomplete evidence; cover missing empty reports; refuse run/revision/policy/inventory mismatch without input mutation; verify exact aggregate report/case/source/problem budgets and derived-output refusal/recovery. Codec round trips preserve the analysis result. The report describes observed counts, not statistical reliability, causality or a substitute for verify. New manifests/XML are synthetic, project-authored Apache-2.0 examples. Remote results for the new commit are recorded by its GitHub Actions run after publication.

Its [remote CI run](https://github.com/jhshuai/MoonTestLedger/actions/runs/38555791694) passed all 12 matrix jobs for 526ee3e9561bd5a424b4a76399046629dc61178c; remote main matched the local commit.

## Evidence integrity manifests — 2026-10-14

Package/four-script formatting, eight-interface drift verification and strict compilation passed with the same stable v0.10.15 toolchain. Tests: Wasm **77/77**, Wasm-GC **74/74**, JavaScript **74/74**, actual Linux native **77/77**. The Linux validation copy was compared with the workspace before execution, excluding Git/build/cache/output directories, with no differences. Subsequent changes were documentation only. The complete native verifier passed, including actual CLI execution and exit codes. Previously recorded third-party async import/C warnings remain present.

Wasm and native E2E checks generate/check manifests for unmodified real Jest evidence, accept JSON reformatting, reject changed XML whitespace with a report-source diagnostic, preserve failed (1), incomplete (3), denied recovery (1) and recovered (0) gates, and recover after malformed manifest refusal. The original upstream Jest audit stdout was separately checked byte-for-byte against the previous implementation: unchanged. `scripts/render-demo.mbtx wasm` executed and wrote UTF-8 archive, HTML and integrity manifest.

Independent Windows `Get-FileHash` SHA-256 results agree with the adapter: original Jest XML `8e18da3a6e4252c34fe7899fad28f8eceeb43849329989b36f2ff68dc7698e58` (7,997 UTF-8 bytes); indent-2 canonical full archive without terminal newline `1fc6df0a332c2648e14246c0670fd8d7f94d19d05d36f93678fb932e16a0411e`; canonical plan `544790a21bb9d6c444de05a0a4414358bd3b8b2ab7136cad1e5477c3da113794`. These are E2E conformance assertions for `mtl-evidence-v1`, checked in both Wasm and native. SHA-256 adapter tests also check published empty, abc and block-boundary known answers on all four targets. Hash agreement is not a cryptographic audit or certification.

Unit tests cover round trips, Unicode byte length, canonical receipt ordering, unchanged inputs, independent getters, full plan/case-order/revision/policy changes, XML metadata/problem/whitespace changes, missing/extra receipts and missing reports, empty/partial accepted reports, altered bindings/lengths/digests, strict unknown schema/algorithm/canonicalization/field/type/digest rejection, duplicate decoded keys/receipt IDs/missing IDs, binding mismatch, exact integer lexemes, inclusive JSON/report budgets, oversized receipt/output refusal and recovery. A separate boundary review rejected a general quarantine draft after finding overlapping flaker APIs; no quarantine capability or code is committed. Dependency/API/provenance and trust limits are recorded in the format, README and third-party documents. Remote results for this new commit are reported by GitHub Actions after publication.

Its [remote CI run](https://github.com/jhshuai/MoonTestLedger/actions/runs/38562446991) passed all 12 matrix jobs for fc10c53b5ac8b99611c4fb935c0e32a52feb2802; remote main matched the local commit.

## Detached XML file packs — 2026-10-14

Formatting, eight-interface drift checks and strict compilation passed. Tests: Wasm **83/83**, Wasm-GC **80/80**, JavaScript **80/80**, actual Linux native **83/83**. A frozen first-capability source copy was compared with the workspace before preparing the next capability, excluding Git/build/cache/output directories, with no differences. The complete native verifier passed, including actual CLI process execution. A preliminary attempt against an unfinished toolchain copy could not resolve the registry; validation then succeeded with the unchanged dedicated stable toolchain. Existing third-party import/C warnings remain recorded above. The original upstream Jest audit stdout remains byte-for-byte unchanged.

Wasm and native E2E workflows detach the unmodified real Jest archive into a new directory, restore identical evidence, preserve the failing gate (1), refuse overwriting an existing directory, refuse extra/corrupt/missing/special-kind members, and recover after corrections. They also pack an incomplete archive and keep verify-pack at 3. Library tests cover full source/problem/plan/policy round trips, deterministic member ordering and source deduplication with separate bindings, caller isolation, wrong lengths/hashes/bindings, strict nested JSON/version/lexeme validation, accepted empty/partial reports versus absent reports, unknown paths/members, inclusive index/source/report budgets and expanded replay limits. No output artifacts are committed. The closed file set and new-file cleanup contract are documented; concurrent hostile filesystem races are not covered. Remote results for this commit are reported by GitHub Actions after publication.
