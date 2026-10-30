# Reproducible workload baseline

This measures a deterministic, project-authored JUnit workload rather than a production adoption claim or a comparison with other tools. One report contains 1,000 / 10,000 / 100,000 unique cases: every tenth case fails with retained payload, the next skips, the rest pass. Thus a complete sample has product gate **1**. The developer workload command exits 0 only when its assertions pass; it is not an all-tests-passing gate.

The workload exercises the public facade: plan construction, JUnit parsing, ingestion/summary, archive encoding, exact replay, original XML preservation, deterministic digests and over-budget refusal followed by successful reuse. Stage timers use the toolchain's monotonic clock in **microseconds**. The source budget is explicitly 32 Mi UTF-16 units and the combined source budget is 64 Mi units; these remain within validated library limits and permit a complete 100k-case archive. No data is truncated to fit the default smaller budget.

## Run

With the README toolchain, from the repository root:

```sh
moon run --target wasm cmd/benchmark -- 1000
moon run --target native --release cmd/benchmark -- 100000
```

The generator and its boundary/recovery/determinism tests support the four library backends. Native needs the platform compiler. Results include exact input/archive sizes and SHA-256 values; identical sample sizes must retain these digests across runs. Do not compare stage times across debug/release modes, toolchains or machines without recording those differences.

For full Linux process measurements, install GNU `/usr/bin/time`, `timeout`, `cc` and `lscpu`; use a new destination with an existing parent:

```sh
moon run scripts/benchmark.mbtx /tmp/mtl-baseline-new
```

This builds an optimized native workload with explicit mimalloc, checks the build plan contains that allocator and no sanitizer flags, records toolchain/compiler/CPU/kernel and binary SHA-256, then executes **three fresh processes per size**. Each process is bounded to 180 seconds. Output includes all nine raw samples, median whole-process elapsed seconds, maximum observed peak RSS in **KiB**, XML/archive byte sizes and stage microseconds. Existing destinations are refused. An invalid-size command must return a JSON `BenchmarkSize` diagnostic on stdout and exit 2, and the following valid samples must succeed. First unexpected failure stops the run and retains logs; only a complete run writes `results.json`.

Peak RSS and process elapsed time include data generation, correctness assertions, replay/reencoding, resource refusal and digest calculation, plus runtime overhead. They are not the parser's isolated allocation cost. There is no warm-up reuse, timing threshold or performance-advantage claim. Shared hosted runners vary, so these measurements are informational; correctness, identical digests and completed samples are enforced.

The runner measures its **working tree**, records Git HEAD and a dirty flag, and records the actual executable hash. A dirty result must not be described as testing only that commit. The `workload-baseline` Linux CI job checks clean committed source independently, retains all result/diagnostic files for seven days and does not publish a package or release. A configured job alone does not establish a successful measurement.

## Executed correctness checks

On 2026-10-30 the generator passed local strict tests on Wasm, Wasm-GC and JavaScript, with two new tests checking size refusal/recovery, decade boundaries and stable digests. Actual Wasm runs of 1k, 10k and 100k cases completed all correctness assertions. The 100k sample retained 10,000 failures and 10,000 skips, a 7,008,913-byte XML input and a 16,598,393-byte archive. Those Wasm executions do not establish Linux native timing or RSS; native measurements are recorded separately after the actual CI job completes.

The first native measurement attempt at `6d9e3fc` stopped before sampling: invalid input reached an unhandled release-mode error and aborted, without the expected text. The developer command now validates arguments before executing the workload and explicitly returns structured exit 2 on all targets; regression tests cover malformed, oversized and ambiguous arguments. That failed job's partial artifact is not a completed baseline.
