# Native GitHub preview releases

The repository provides a manual [release workflow](https://github.com/jhshuai/MoonTestLedger/blob/main/.github/workflows/release.yml). It publishes to **GitHub only**; no Mooncakes publish command/token is configured. Version metadata is `moon.mod` plus the machine-readable `--version` response, checked for agreement by the actual CLI evaluator. Tag `vVERSION` must match them.

## Use a binary

Open the repository's [releases](https://github.com/jhshuai/MoonTestLedger/releases), select the desired tag, and choose the binary whose OS and architecture match your machine. Actual image/architecture, source commit, toolchain, byte length, SHA-256 and executed checks are in its adjacent `.json` file and `release-manifest.json`.

| Asset pattern | Platform |
| --- | --- |
| moontestledger-linux-x86_64 | Linux x86-64, built/tested on Ubuntu 22.04 |
| moontestledger-windows-x86_64.exe | Windows x86-64, exact hosted image recorded |
| moontestledger-macos-aarch64 or macos-x86_64 | The actual macOS runner architecture, recorded rather than assumed |

Verify the download against `SHA256SUMS` from the trusted release. On Unix, set executable permission (`chmod +x BINARY`); then run `BINARY --version` and the documented `audit`, collection or delivery commands. No MoonBit compiler, Python, Java or private service is needed to run a native binary. The normal system C runtime is required. Binaries are unsigned/not notarized. Hosted-runner execution proves those recorded environments, not all OS versions, libc versions, CPUs or machines. A checksum is not a publisher signature.

`LICENSE` and `THIRD_PARTY_LICENSES.txt` accompany the binaries. Complete dependency license texts are included, with CRLF normalized to LF in the combined notice; the upstream fflate MIT notice is retained in source with provenance. Generator/test-runner binaries and test fixtures are not embedded in the native executable.

## Release verification

1. Require a successful **main CI** run for the exact source SHA and require that neither tag nor release already exists.
2. On Ubuntu 22.04, Windows and macOS, run the strict native verifier, build optimized native code, copy the binary into a new directory, and **actually execute that packaged copy from an independent working directory**. Check version, original passing/failing/missing/invalid gates 0/1/3/2 and inventory review. Record the binary hash and observations; upload the payload.
3. Download all three payloads on another runner. Check the closed member sets, exact source/version/tag, one recorded platform per OS, binary byte lengths/hashes, completed smoke checks and matching complete license notices. Reexecute the downloaded Linux binary.
4. Create a new tag at the checked commit without force, create a draft preview release and upload assets without clobbering existing files. Redownload every asset; verify all hashes and the checksum list, then reexecute the downloaded Linux asset. Only then change the draft to published.

Failures stop publication and retain diagnostic artifacts/draft state; the workflow never treats compilation alone as execution. Windows/macOS payloads execute on their native build runners; the later Ubuntu job verifies the same tested bytes by hash, without claiming to execute foreign-platform binaries. Actual run/release outcomes are checked after dispatch and are distinct from this configuration.

The `--local` build mode is for local smoke tests. It marks `source_revision` as `working-tree` and cannot pass the CI publisher's exact-SHA checks. It never publishes. Example from the repository root, with a native compiler and existing parent directory:

```sh
moon run scripts/build-release.mbtx build /tmp/mtl-native-preview v0.1.0 --local
moon run scripts/build-release.mbtx check /tmp/mtl-native-preview/moontestledger-linux-x86_64 /tmp/mtl-native-preview/moontestledger-linux-x86_64.json
```

The directory must not exist. To publish, manually dispatch `Native preview release` only after the same revision's main CI passes. Ordinary pushes run validation without publishing. Existing tag/release names are refused; failed draft publication needs explicit investigation, not an automatic overwrite. GitHub CLI operations follow its [release create](https://cli.github.com/manual/gh_release_create) and [edit](https://cli.github.com/manual/gh_release_edit) interfaces.
