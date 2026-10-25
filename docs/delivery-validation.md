# Delivery validation — 2026-10-25

The module remains unpublished to Mooncakes. These milestones prepare GitHub source use and CI delivery; they do not claim registry installation or competition acceptance.

## Safe evidence file output

Commit `79b47d0b96393f00774897d13f356ebdff409afc` passed [remote CI](https://github.com/jhshuai/MoonTestLedger/actions/runs/40209598776). The initial macOS/Wasm job failed before project checks because the dependency host could not resolve DNS; the failed-job rerun succeeded. All 12 OS/target combinations have successful results across those attempts.

Pinned toolchain: moonc v0.10.15+943464bfa / moon 0.1.20261012. Formatting, eight-interface drift checks, strict check/build, encapsulation and tests passed: Wasm 113/113, Wasm-GC 106/106, JS 106/106, actual Linux native 114/114. The Linux validation source copy compared equal to workspace sources, excluding Git/build/cache/output. Existing dependency host/C warnings remain documented in the earlier validation record.

The existing real Jest/retry/collection/pack CLI evaluator and new output evaluator execute on Wasm/native. The new checks compare UTF-8 file bytes with each command's original stdout, exercise all seven supported commands, preserve existing destinations and an input/output alias, reject invalid input before creation, retain missing/denied-recovery gates, support Unicode file paths, refuse missing parents and recover after correction. Merge comparison uses its existing canonical case order. Core API and generated interfaces are unchanged. No third-party implementation or tests were copied for this capability.

Remote CI outcomes are recorded by GitHub Actions for each pushed revision; configured coverage is separate from an observed successful run.

## Independent source consumer

`scripts/check-consumer.mbtx` exported committed library revision `79b47d0b96393f00774897d13f356ebdff409afc` into fresh temporary workspaces, without Git/build/dependency-cache directories in the export. A separate consumer module strictly checked, built and actually ran on Wasm, Wasm-GC, JS/Node and Linux native. It imported public facade types/methods, preserved original XML, round-tripped JSON/detached/ZIP/USTAR packs, refused an unknown report atomically and retained missing inventory. Every target agreed on the six-case Jest archive digest, 7,997-byte XML digest, complete failing gate 1 and missing gate 3. Explicit view-element record types and Node's two-element executable prefix are exercised by the consumer fixture.

Registry/download timeouts occurred during preliminary native dependency resolution. Final native execution used a usable cache of the same upstream package archives; its source export and builds remained isolated. No DNS settings or dependency versions were changed. The root integrated Wasm-GC verifier also passed (106/106 tests, strict check/build, formatting/interface/encapsulation checks); library source and public interfaces are unchanged in this milestone. Earlier four-target root results remain applicable. The evaluator's library input is committed HEAD, not uncommitted library edits. No Mooncakes publication or upload was performed.
