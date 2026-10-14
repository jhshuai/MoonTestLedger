# Third-party sources and licenses

## Runtime dependencies

| Component | Version/source | License | Use |
| --- | --- | --- | --- |
| MoonBit core | toolchain v0.10.15+943464bfa; [source](https://github.com/moonbitlang/core) | Apache-2.0 | collections, JSON, UTF-8, environment and testing |
| Milky2018/xml | 0.6.1; [Mooncakes](https://mooncakes.io/docs/Milky2018/xml), [source](https://github.com/moonbit-community/xml-mbt) | Apache-2.0 | well-formed XML pull reader and source spans |
| moonbitlang/async | 0.22.4; [Mooncakes](https://mooncakes.io/docs/moonbitlang/async), [source](https://github.com/moonbitlang/async) | Apache-2.0 | CLI file/stdio I/O and .mbtx automation processes |
| moonbitlang/x/crypto | x 0.5.5; [Mooncakes](https://mooncakes.io/docs/moonbitlang/x/crypto), [source](https://github.com/moonbitlang/x/tree/main/crypto) | Apache-2.0 | SHA-256 primitive and hexadecimal rendering for evidence manifests; experimental upstream package |

These packages are resolved as dependencies, not copied wholesale into project source. Their original licenses accompany the packages. Moon.mod pins the Mooncakes versions. Third-party internals are not presented as original MoonTestLedger algorithms.

The two tiny platform exit declarations in cmd/moontestledger follow the native and Wasm host API patterns from [async integration.mbt](https://github.com/moonbitlang/async/blob/main/src/integration.mbt) and [integration.wasm.mbt](https://github.com/moonbitlang/async/blob/main/src/integration.wasm.mbt), Apache-2.0. The runtime implementation remains in the dependency/host.

## Copied example data

Two report fixtures from dorny/test-reporter at commit cc52f364a405169afe07bb00dab3d375b451229d are bundled unchanged. Copyright (c) 2021 Michal Dorner and contributors; MIT license. The license is copied unchanged to [examples/upstream/LICENSE.dorny-test-reporter](examples/upstream/LICENSE.dorny-test-reporter). [Examples provenance](examples/README.md) lists original paths and SHA-256 values.

No upstream test code was copied into the library or unit tests. Synthetic boundary reports and plan/bundle JSON are authored for this project. The sample suite's framework output is an interoperability fixture, not production usage evidence.

The offline HTML renderer, CSS, hostile-text test data and render-demo automation are project-authored Apache-2.0 code. No third-party UI template, font, icon, browser script or remote asset is bundled. Its demo continues to use the MIT-licensed unmodified Jest fixture described above.

The detached XML file-pack protocol, storage adapter, CLI and boundary tests are newly authored Apache-2.0 code. The unmodified XML members retain their original fixture license. [cmdrvl/pack](https://github.com/cmdrvl/pack) (MIT) was inspected as a non-MoonBit workflow reference; no implementation, schema or tests were copied. Hash primitives continue to use the pinned x/crypto dependency.

The declared directory collection API, portable path validation, specification JSON, CLI, bounded enumeration and tests are project-authored Apache-2.0. The example specifications refer to the unchanged MIT Jest fixture and existing Apache-2.0 synthetic payment reports. Pinned async/fs API documentation informed no-follow file-kind and directory iterator usage; no upstream implementation or test code was copied.

## Research and format references

Direct USTAR collection and boundary tests are project-authored Apache-2.0. GNU tar 1.34 generated the three [reference archives](examples/transport/README.md); the GPLv3+ tool/source is not bundled or copied. Archive data retain their original licenses: unchanged dorny/test-reporter Jest XML is MIT with its copied notice, synthetic retry XML is Apache-2.0. Exact generation commands and archive hashes are recorded alongside fixtures. Tests check independent-producer input, not just the project's own writer.

The direct declared ZIP collection adapter/CLI/tests and test-generated archive payloads are project-authored Apache-2.0, using pinned fzip for archive generation and bounded expansion. Public real XML retains the upstream MIT license. No archive extraction filesystem utility or upstream test implementation is copied.

The narrow USTAR carrier implementation/tests are project-authored Apache-2.0. [Go archive/tar format.go](https://github.com/golang/go/blob/master/src/archive/tar/format.go) was read as format documentation (Go repository BSD-3-Clause); no source/test implementation was copied or ported. Existing MoonBit tar helper APIs were inspected for overlap, not reused.

ZIP transport depends on [hustcer/fzip 0.8.8](https://mooncakes.io/docs/hustcer/fzip) ([source](https://github.com/hustcer/fzip)), Apache-2.0, for ZIP generation, bounded DEFLATE and CRC-32. It describes lineage from [101arrowz/fflate](https://github.com/101arrowz/fflate) (MIT); compression is not claimed as project-original. Moon fetches the dependency; it is not vendored. Container guards, adapters, CLI and tests are project-authored Apache-2.0. The [PKWARE APPNOTE](https://pkware.cachefly.net/webdocs/casestudies/APPNOTE.TXT) is linked only; no specification text is copied.

- [GitLab unit test reports](https://docs.gitlab.com/ci/testing/unit_test_reports/) documents report workflows and duplicate-name behavior.
- [pytest flaky-test guidance](https://docs.pytest.org/en/8.2.x/explanation/flaky.html) and [Buildkite test monitors](https://buildkite.com/docs/pipelines/configure/tests/workflows/monitors) motivate selective reruns and same-revision outcome observation. They are workflow references; their implementations and test code are not copied.
- [Testmo JUnit XML conventions](https://github.com/testmoapp/junitxml) describes practical producer conventions. It is a format reference, not an official universal JUnit XML specification.
- [dorny/test-reporter](https://github.com/dorny/test-reporter), MIT, and [EnricoMi/publish-unit-test-result-action](https://github.com/EnricoMi/publish-unit-test-result-action), Apache-2.0, establish common report-publication workflows.
- MoonBit packages and public API sources used in differentiation review are linked in [docs/ecosystem-review.md](docs/ecosystem-review.md). Referenced project implementations were not copied.
- [MoonBit package management documentation](https://docs.moonbitlang.com/en/stable/toolchain/moon/package-manage-tour.html) and [Moon manual](https://moonbitlang.github.io/moon/commands.html) informed current configuration and commands.
- Project license text is the standard [Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0.txt).
- [NIST secure hashing validation resources](https://csrc.nist.gov/projects/cryptographic-algorithm-validation-program/secure-hashing) and [FIPS 180-4](https://doi.org/10.6028/NIST.FIPS.180-4) are SHA-256 references. Adapter tests use the published empty/abc/multi-block known answers; test code is project-authored. These checks do not imply NIST validation or cryptographic audit.
- [GitHub artifact storage/validation](https://docs.github.com/en/actions/tutorials/store-and-share-data#validating-artifacts) documents SHA-256 artifact checks across jobs. This motivates a complete test-evidence manifest; the project does not copy GitHub's implementation or implement signed artifact attestation.

## CI services

The workflow references [actions/checkout](https://github.com/actions/checkout), [actions/setup-node](https://github.com/actions/setup-node) and [hustcer/setup-moonbit](https://github.com/hustcer/setup-moonbit) (MIT), plus [ilammy/msvc-dev-cmd](https://github.com/ilammy/msvc-dev-cmd) (MIT). They run as external actions; their source is not copied here. Setup-moonbit is pinned to inspected v1.22 commit 9199da0ab63ea0c0bab1dc15f03d76e17ed4f75f.

The versioned official binary/core URLs currently expire under the hosting service's 60-day retention policy. Update the pinned release and rerun the complete verification matrix before that artifact retention window expires; current successful downloads do not guarantee indefinite availability.
