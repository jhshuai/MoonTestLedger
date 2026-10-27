# Independent public API consumer

This is a separate MoonBit module. It imports only the public `jhshuai/moontestledger` facade and core packages. Supply collection JSON, a report ID and original XML as three arguments. It collects the report, verifies exact source retention, round-trips JSON, detached/ZIP/USTAR packs, checks missing inventory and atomic refusal, then prints summary/integrity JSON. Library records passed through array views use explicitly typed `Array[@ledger.CollectedXml]` values.

The output also lists exact parsed classname/name/outcome observations. `scripts/check-producers.mbtx TARGET` reuses this consumer against the **current working library source** for captured pytest/Surefire/Gradle fixtures, and additionally invokes `--reject-producer XML CODE` for the explicitly unsupported embedded-retry profile. That fixture-only mode asserts the diagnostic path and recovery after rejection. See [producer conformance](../producers/README.md) for its independent expected contracts and hashes.

Run from the repository root:

```text
moon run scripts/check-consumer.mbtx wasm
moon run scripts/check-consumer.mbtx wasm-gc
moon run scripts/check-consumer.mbtx js
moon run scripts/check-consumer.mbtx native
```

The evaluator exports the **committed HEAD** using `git archive`, extracts into an isolated temporary workspace, copies this consumer fixture into a separate module, writes `moon.work`, resolves dependencies, and strictly checks/builds/runs that consumer. It asserts that Git/build/dependency caches are absent from the library export before dependency resolution. It uses the unmodified MIT Jest XML from `examples/upstream` and requires six cases, complete gate 1, missing gate 3, exact XML byte length/digest and canonical evidence digest. The program itself exits 0 when its assertions pass; gate 1 describes the input fixture's real failures.

Requirements: Git, tar, the documented MoonBit toolchain, Node for JS, a native compiler for native, and dependency registry access (or an already usable dependency cache). No Mooncakes account, publishing or registry upload is performed. The unpublished project resolves through workspace membership; the module version selector does not prove registry availability. The library is tested from HEAD, so commit library changes before evaluating those changes with this check. The current consumer fixture is copied separately.

The exported archive/build tree is retained at the printed temporary path for inspection; the script does not recursively delete user paths. CI executes this consumer on all 12 OS/target combinations. Local evidence and observed remote outcomes are recorded separately in `docs/delivery-validation.md`. Source and evaluator are project-authored Apache-2.0; the real report retains the upstream MIT notice in `examples/upstream`.
