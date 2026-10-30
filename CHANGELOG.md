# MoonTestLedger v0.1.0 — 2026-10-28

First GitHub preview release. Mooncakes publication was not part of this GitHub release.

- Complete externally declared report/test inventory, exact identities, explicit retries and conservative 0/1/3 gates.
- Bounded common JUnit profile with actual Jest, pytest 8.3.5, Surefire 3.5.2 and Gradle 7.6.4 conformance data. Unsupported embedded reruns remain explicit errors.
- Original XML replay, deterministic JSON evidence, SHA-256 manifests, declared directory/ZIP/USTAR collection and sealed evidence packs.
- Offline HTML and six-member CI delivery. Real GitHub upload/download/offline replay retains failing and missing gates, with historical v1 artifact golden files.
- Complete future-inventory review, acknowledgment tokens, stale-baseline rejection, fresh-run enforcement and exclusive plan output. Existing failed/incomplete archives remain unchanged.
- Machine-readable `--version`. Native binaries include per-platform execution/provenance manifests, checksums and license copies. Release jobs actually execute packaged binaries; final publication redownloads assets and reexecutes the Linux binary.

## Scope and known limitations

- This is a preview with evolving pre-1.0 public APIs. No ecosystem exclusivity, performance advantage, cryptographic audit or universal JUnit/platform compatibility is claimed.
- Library targets: Wasm, Wasm-GC, JavaScript and native. The file CLI supports Wasm/native; release assets are native binaries for the recorded runner OS/architecture, not cross-platform executables.
- Checksums and acknowledgment tokens are integrity/content checks, not signatures or proof of a human reviewer. Binaries are not code-signed/notarized.
- The historical native segmentation fault has not been reproduced or diagnosed. Process/signal capture is available and CI preserves diagnostics on failure; passing reruns do not establish a fix. See `docs/native-diagnostics.md`.
- Existing XML/resource/transport/profile limits remain; unsupported input is refused rather than silently converted. No automatic delivery-profile migration is implemented.
- Compiler/core download URLs have upstream retention limits. Source builds require the documented pinned toolchain or a newly validated replacement.
