# Source package and downstream use

MoonTestLedger's module is `jhshuai/moontestledger`, currently version `0.1.0`, Apache-2.0. It is a preview; check [Mooncakes](https://mooncakes.io/docs/jhshuai/moontestledger) for available versions. Local packaging and workspace checks neither reserve this namespace/version nor validate registry credentials. This document describes a source archive, not a new GitHub binary release.

## What the archive contains

| Included | Reason |
| --- | --- |
| Root facade; ledger, junit, wire, history and report packages | Portable public library and its implementation |
| cli and cmd/moontestledger | Actual Wasm/native file workflow, with unchanged platform limits |
| Unit tests and generated interfaces | Downstream source verification and inspectable public API |
| Documentation, examples, original XML and historical golden delivery data | Reproducible workflows, compatibility tests and original evidence |
| LICENSE, THIRD_PARTY.md, licenses and upstream fixture notices | Project and third-party attribution |
| scripts/workflow-demo.mbtx and scripts/render-demo.mbtx | Git-independent user demonstrations from an extracted package |

`.moonignore` omits the development benchmark package/data, deliberately failing C detector probes and all other maintenance scripts. GitHub workflows and hidden caches are excluded. Producer Python/Java test inputs and build definitions remain alongside captured XML to explain and reproduce its origin; producer executables, dependencies and build caches are not bundled. The library needs no Python, Java, GitHub account or service.

Rules in `.moonignore` replace `.gitignore` at the same directory, so the output/cache exclusions are repeated explicitly. See the [official packaging rules](https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html#publishing-files-with-moonignore). Required fixtures, tests and license notices must not be removed merely to make the archive smaller.

## Verify the actual package without publishing

From a **Git checkout** with the README's validated toolchain:

```sh
moon update
moon package --list
moon run scripts/check-consumer.mbtx wasm --package
moon run scripts/check-consumer.mbtx wasm-gc --package
moon run scripts/check-consumer.mbtx js --package
moon run scripts/check-consumer.mbtx native --package
```

JS needs Node; native needs a working C compiler/SDK. These commands do not call `moon publish`, register an account or upload anything. Each invocation builds a new ZIP, retains its exact bytes, checks CRCs, path/member bounds, source-byte equality, required source/interface/test files and notices, and relative Markdown file links. It rejects maintenance scripts, caches, benchmark/probe inputs and duplicate/unsafe member paths. It does not validate Markdown anchors or external link availability.

The checker extracts only into its newly created temporary directory, without Git metadata or copied build/dependency caches. It runs the extracted module's tests and strictly checks/builds/executes a **separate consumer module** using the extracted library as a workspace member. The real, unedited MIT Jest fixture must retain six cases, complete failing gate 1, missing gate 3, exact XML and canonical archive digests, JSON/detached/ZIP/TAR round trips, atomic rejection and recovery. Wasm/native additionally run the packaged three-workflow demo, including failed/missing/recovered gates, tamper refusal and restoration.

Only a completely successful check writes `results.json`, recording target, Git HEAD for context, exact ZIP SHA-256/byte count/member count and canonical evidence digest. HEAD alone does not identify a locally modified archive; the ZIP hash identifies the tested bytes. The entire extracted workspace, original ZIP and package-command output are retained at the printed path; no caller directory is overwritten or recursively deleted. CI runs both Git-export and package-ZIP consumers for each OS/target matrix entry. A configured job is not evidence that a particular run passed.

The previous `moon run scripts/check-consumer.mbtx TARGET` mode still tests committed Git source. It remains useful independently of package filtering.

## Use the extracted library

Extract the ZIP into a sibling directory named `MoonTestLedger`, create your own consumer, and use the `moon.work`, `moon.mod` and `moon.pkg` setup in the [README library section](../README.md#library-api). The workspace resolves the library locally, without claiming it exists in the registry. Dependencies still require registry access or an already usable dependency cache; this is not an air-gapped dependency bundle.

Run the two included demos from the extracted module root with the commands in the README. Development commands in other documents require the full [GitHub checkout](https://github.com/jhshuai/MoonTestLedger), including performance measurements, native fault diagnosis, producer evaluator scripts and release maintenance.

Actual Mooncakes upload requires matching account/namespace permissions, an available version and a successful publication preflight. After publication, verify installation from the registry in another independent project. Do not infer that a successful local package or CI job has already published the module.

## Observed preparation checks — 2026-10-31

Local Windows runs of the extracted ZIP passed 123 Wasm tests, 115 Wasm-GC tests and 115 JavaScript tests, plus actual independent consumer execution on all three targets. The development benchmark's three tests are intentionally outside this archive. Wasm also executed the packaged failed/missing/recovered workflow and offline delivery checks. The canonical six-case Jest archive digest remained `1fc6df0a332c2648e14246c0670fd8d7f94d19d05d36f93678fb932e16a0411e`.

A deliberate temporary filter excluding `facade_test.mbt` was refused with `required source omitted: facade_test.mbt`; restoring the exact original filter bytes recovered the complete package consumer check. Initial relative links to excluded GitHub workflows were detected and corrected to repository URLs. These are observed refusals/recoveries, not just configured assertions. Formatting, generated-interface regeneration and strict checking of all four targets passed; local native execution is not claimed because this Windows session has no configured native compiler. Native package execution is covered by the separate CI matrix; inspect its actual run before claiming success.
