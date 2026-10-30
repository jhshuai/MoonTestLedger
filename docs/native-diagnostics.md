# Native crash investigation

The 2026-10-25 segmentation fault remains **unresolved**. Its original log did not identify the signalled executable or retain a core/stack. The default WSL core policy was `|/wsl-capture-crash %t %E %p %s` with a zero core limit when checked on 2026-10-28; no original core was found in the validation workspace. A passing rerun is not a fix. No speculative dependency upgrade or product workaround is applied.

## Capture the next failure

On Linux with `strace`, GNU `timeout`, the documented MoonBit release and a native C compiler, run from the repository root. The destination's parent must already exist; the destination itself must not exist:

```sh
moon run scripts/diagnose-native.mbtx /tmp/mtl-native-investigation 1
moon run scripts/diagnose-native.mbtx /tmp/mtl-native-delivery 10 --delivery-only
moon run scripts/diagnose-native.mbtx /tmp/mtl-native-probe 1 --self-test
```

`REPEATS` is bounded to 1..20. Normal runs execute the full strict verifier; `--delivery-only` repeats the historically affected delivery evaluator. The first nonzero result or delivered SIGSEGV/SIGBUS stops the investigation. It never retries a failed run or converts it into success. A destination is retained even on failure; no earlier diagnostic directory is overwritten. Tracing can change race timing, so no reproduced fault under tracing does not establish freedom from races.

Each run preserves the exact command, exit status, complete stdout/stderr, and a process/signal trace containing successful execs, parent/child relationships and delivered signal details (`si_code`/address when provided by the OS). The JSON extracts fault PID and that PID's last successful exec; when no exec was seen (e.g. a forked thread), it explicitly reports unknown and leaves the full trace for attribution. Installing a SIGSEGV handler alone is not classified as a fault. Toolchain/system descriptions and the verification input scripts/module file are saved. No environment values are dumped. These are local diagnostic logs and can contain local paths/test output; review before sharing.

The self-test deliberately signals **utility processes**, checks that the trace attributes a SIGSEGV to `sleep`, and then checks a clean process. It is not a product crash reproducer. Linux native CI uses the tracer for its single normal verification and preserves the logs if that job fails. Other OS/targets retain their existing execution checks. Verification now logs the exact phase and failing status; delivery E2E failures also identify the actual CLI arguments.

## Follow-up when a fault is captured

Use the fault PID and successful exec in `run-N.json`, confirm `si_code` in the trace (a deliberate signal and a memory access fault differ), and identify the exact executable/arguments in `run-N.trace`. Reproduce that command against the retained inputs in isolation under a native debugger (`gdb --args EXECUTABLE ARGUMENTS...`, then `run` and `thread apply all bt full`). Record compiler, dependency/script-host versions and stack; reduce the input without changing the failing binary first. If the binary is a compiler/script host rather than the product, provide that minimal reproducer and trace to the corresponding upstream. No upstream bug report or diagnosis is claimed before such evidence exists.

## Observations on 2026-10-28

The original frozen source (`cb7fe53` library code) passed a complete native verifier with process/signal tracing. Signal attribution and recovery probes passed separately. Further bounded delivery repetitions and current-source validation are recorded in the delivery validation record. This improves capture and failure reporting; it does **not** close the historical root-cause question.

## Additional memory checks

The [isolated native memory checker](native-memory.md) records subsequent sanitizer/debugger/concurrent investigation, coverage limits and the early instrumentation link failure. Its reusable `.mbtx` runner exports committed source, demonstrates functioning detectors with separate controlled probes, executes native product tests/workflows and retains command logs on the first failure. CI runs it as a separate job. These checks complement process attribution and do not mark the historical fault fixed.
