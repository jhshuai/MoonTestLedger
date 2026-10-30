# Reproducible script dependencies

The module pins its dependencies in `moon.mod`. Standalone `.mbtx` scripts resolve their own imports, so an unversioned script import is not pinned by the surrounding module. Every external script import now specifies the same exact module version, including subpackage imports. Core imports come from the selected toolchain.

On 2026-10-30 a fresh GitHub runner selected `moonbitlang/async@0.22.7` for an unversioned script. The fixed compiler/core did not contain its requested `moonbitlang/core/async`, and verification failed **before any product checks ran**. Local caches had previously selected an older compatible version, hiding this drift. The correction pins script async to `0.22.4` and fzip to `0.8.8`; it does not upgrade product dependencies or diagnose the separate historical native crash.

`moon run scripts/check-script-imports.mbtx` checks every script's imports and exact version agreement with `moon.mod`. The normal verifier runs it on every OS/target. Its regression probes include missing versions, subpackages, floating ranges, empty and malformed versions. When changing a dependency, update both module and script selectors and validate the workflows on the pinned toolchain.

CI failure evidence: [fresh-run dependency resolution failure](https://github.com/jhshuai/MoonTestLedger/actions/runs/41036193505). Subsequent successful runs are distinct evidence; the failed run is not rewritten or converted into a passing product test.

Checkout and Node setup use the recorded v6 commit SHAs, whose official action manifests select the Node 24 action runtime. This is separate from Node 22 used to execute the project's JavaScript target. Other workflow behavior and the fixed MoonBit version remain unchanged; the three-OS/four-target workflow is the execution check for this change. Ordinary pushes do not dispatch the evidence-upload or release workflows.
