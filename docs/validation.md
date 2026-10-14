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

The local Windows native attempt could not execute because the stable native driver requires MSVC-compatible build tools and a Windows SDK. GCC/MinGW does not satisfy the driver/dependency requirements. No Windows native runtime success is claimed.

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

The verifier snapshots all six tracked generated interfaces, regenerates with the Wasm target and compares their contents. It works from a source archive and does not need a Git repository. MOON_TEST_LEDGER_MOON may point to the executable used by child commands when multiple installations are present. Native requires the target platform's compiler/SDK. The evaluator's local report fixtures have documented public provenance.
