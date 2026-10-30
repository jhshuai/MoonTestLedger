# Native address and undefined-behavior checks

From the Git repository root on Linux, with the documented MoonBit toolchain, `cc` with ASan/UBSan support, `git`, `tar`, `cp` and `nm` available:

```sh
moon run scripts/check-native-memory.mbtx /tmp/mtl-memory-new
```

The destination must not exist and its parent must exist. The check exports **committed HEAD**, records its revision/toolchain/compiler and the actual runner source, and retains a pristine export plus a separately instrumented copy. Uncommitted product edits are not part of the checked revision. It does not alter working-tree configuration or delete the result directory. It refuses existing native link overrides or linked source/cache entries rather than silently replacing unsupported configuration.

The check:

1. Compiles two small, project-authored C detector fixtures into separate executables. The deliberate heap-use-after-free and invalid-shift probes must each exit 1 with the specific ASan/UBSan diagnostic. They are never linked into the product or treated as product failures.
2. Adds address/undefined-behavior flags to the isolated generated C and dependency C stub builds, uses `MOONBIT_ALLOCATOR=system`, and actually runs the native unit tests.
3. Restores library package options before ordinary CLI builds. Adding executable C options to non-main library packages can otherwise produce a link error; no such failed experiment is counted as a runtime check.
4. Records a native CLI dry-run build plan, requires the system allocator and sanitizer flags, and inspects the actual binary's ASan/UBSan dynamic symbols.
5. Actually executes inventory review, historical delivery byte comparisons, complete delivery/tampering/recovery, and the three documented workflow scenarios using the instrumented native CLI.

Each command records its arguments, expected/actual status and full stdout/stderr. Commands stop on the first unexpected status, without retry. Existing result paths are never overwritten. Only a completely successful run writes `results.json`; partial logs are retained after failure. Results distinguish the two deliberately failing detector probes from successful product commands.

ASan uses `detect_leaks=0:halt_on_error=1`; UBSan uses `halt_on_error=1:print_stacktrace=1`. **Leaks are not checked.** The prebuilt compiler, Wasm script host, separately built native runtime and system libraries are not claimed to be fully instrumented. The system allocator improves ASan visibility of MoonBit allocations; default mimalloc runs provide different coverage. These are finite correctness checks, not proof that all memory faults are absent.

The `native-memory` CI job performs this check independently of the normal three-OS/four-target verifier. It uploads command logs, probe sources, runner and result metadata on success or failure, with seven-day artifact retention. The pristine/exported dependency trees and binaries are not uploaded. Configuration alone is not evidence of a successful CI run; consult the exact commit's job status.

## Recorded investigation

On 2026-10-29/30, product revision `9811ad6` passed 125 actual Linux native tests plus inventory review, historical byte comparisons and delivery under system-allocator ASan/UBSan. Earlier original-library investigation passed 20 default-allocator sanitizer delivery runs, five GDB inspections of the Wasm script host and 16 concurrent delivery runs. GDB detached its child CLI processes; the earlier default allocator limits address-checking coverage. Six malformed receipt depths, including 200,000 nested arrays, were refused by the published Linux v0.1.0 binary with structured exit 2; restoring the original receipt recovered exit 0 each time. Original local logs are retained outside Git; the reproducible check above provides new results for a specific committed revision.

An initial isolated instrumentation experiment failed to link ordinary library packages (`undefined reference to main`). It stopped without executing that workflow; the configuration was corrected and checked in a fresh directory. This was an experimental setup error, not a product segmentation fault.

**The historical 2026-10-25 segmentation fault remains unresolved.** Passing memory checks do not identify its executable/stack or establish a root-cause fix. Use the [process/signal capture workflow](native-diagnostics.md) for the next failure.

Commit `958e06c` passed [all 13 CI jobs](https://github.com/jhshuai/MoonTestLedger/actions/runs/41038492535), including the new independent native-memory job. The local first full checker also passed against committed product source `aac733a`. A subsequent local guarded run passed its detector/configuration probes, 125 tests, binary checks, review, golden comparison and delivery, but the WSL session stopped responding during the final workflow; even a separate `ps` request did not return. Its logs remain partial and it is not counted as a complete pass or attributed to a product fault. Only the owned Windows WSL client processes were stopped; no global WSL shutdown/restart was performed. The independent GitHub run provides the completed result for the committed checker.
