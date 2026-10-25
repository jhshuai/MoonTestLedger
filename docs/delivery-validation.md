# Delivery validation — 2026-10-25

The module remains unpublished to Mooncakes. These milestones prepare GitHub source use and CI delivery; they do not claim registry installation or competition acceptance.

## Safe evidence file output

Pinned toolchain: moonc v0.10.15+943464bfa / moon 0.1.20261012. Formatting, eight-interface drift checks, strict check/build, encapsulation and tests passed: Wasm 113/113, Wasm-GC 106/106, JS 106/106, actual Linux native 114/114. The Linux validation source copy compared equal to workspace sources, excluding Git/build/cache/output. Existing dependency host/C warnings remain documented in the earlier validation record.

The existing real Jest/retry/collection/pack CLI evaluator and new output evaluator execute on Wasm/native. The new checks compare UTF-8 file bytes with each command's original stdout, exercise all seven supported commands, preserve existing destinations and an input/output alias, reject invalid input before creation, retain missing/denied-recovery gates, support Unicode file paths, refuse missing parents and recover after correction. Merge comparison uses its existing canonical case order. Core API and generated interfaces are unchanged. No third-party implementation or tests were copied for this capability.

Remote CI outcomes are recorded by GitHub Actions for each pushed revision; configured coverage is separate from an observed successful run.
