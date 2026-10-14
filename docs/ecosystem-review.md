# Project selection review — 2026-10-13

This review preceded implementation. The user requires a practical, broadly useful project and no substantial overlap with existing MoonBit public purposes and APIs. This is evidence of a complementary boundary in the checked public ecosystem, not a claim of uniqueness or original algorithms.

## Demand gate

The initial ELF, Parquet and OTLP recommendations were withdrawn as preferred directions after the user added “not too niche”. The new target is an ordinary development team using CI, report artifacts, parallel jobs and retries. No private services should be needed to adopt or evaluate the first capability.

## Three candidates

### MoonTestLedger (selected)

Users: developers and maintainers of single-language and polyglot repositories.

Workflow: declare the run/revision/environment, expected report shards, attempt order and expected test identities; load actual JUnit XML artifacts; account for every expected report and test; retain attempts rather than overwrite them; produce a deterministic report and CI exit status. Missing artifacts, wrong revisions, identity collisions and unsupported outcome semantics must never become passing results.

Independent value: reconcile explicitly expected CI artifacts and retry evidence into a trustworthy account of a test run.

Nearest MoonBit projects:

| Project | Checked public boundary | License / maintenance evidence | Difference |
| --- | --- | --- | --- |
| [MoonSeal](https://github.com/LL728/moonseal) | `analyze_project`, `evaluate_gate`, quality snapshots, mutation/coverage and release evidence | Apache-2.0; Mooncakes 0.1.6 dated 2026-08-16 | Repository test adequacy, not expected JUnit shard/attempt accounting |
| [MoonProbe](https://github.com/wuhaiting321/MoonProbe) | `.probe` HTTP test execution and console/JUnit output | Apache-2.0; 0.1.0 dated 2026-09-30 | A producer of test reports, not a reconciler of external CI artifacts |
| [taptrail](https://mooncakes.io/docs/MX-ai-nb/taptrail) | TAP13 parsing, plan validation, CI gate, Markdown/JSON | MIT; 0.3.0 dated 2026-08-20 | Single TAP stream correctness, not revision-bound report inventory and ordered retries |
| [XMLParser](https://mooncakes.io/docs/moonbit-community/XMLParser) | Generic XML document/tree parsing | Apache-2.0; 0.2.6 dated 2026-09-27 | XML syntax foundation only; source inspection found limitations unsuitable for strict JUnit ingestion |

Demand evidence:

- [GitLab unit test reports](https://docs.gitlab.com/ci/testing/unit_test_reports/) integrate JUnit artifacts into merge requests and pipelines. Its documented duplicate-name behavior keeps only the first occurrence, demonstrating that identity collisions can lose visible results. Report display itself does not determine job success.
- [dorny/test-reporter](https://github.com/dorny/test-reporter) displays results from common frameworks; checked page approximately 1.2K stars, MIT.
- [publish-unit-test-result-action](https://github.com/EnricoMi/publish-unit-test-result-action) handles CI results; checked page 752 stars, Apache-2.0.
- [junitparser](https://github.com/weiwei/junitparser) offers mature XML report parsing and merging. These projects substantiate the workflow, not a measured MoonBit user base.
- [Common JUnit XML conventions](https://github.com/testmoapp/junitxml) explain the de facto format and the absence of a universal formal specification. Compatibility must therefore be explicit and tested, not asserted for every producer.

MoonBit suitability: a deterministic, bounded, portable domain model and reconciliation algorithm can be embedded by downstream tools without a test runner or CI account. File access belongs in the CLI adapter.

### Compose environment contracts (retained, lower priority)

Users: backend and full-stack teams using Docker Compose. Workflow: resolve interpolation inputs separately from per-service container environment inputs, then check a service environment contract and explain precedence and missing/unset values. Independent value depends on implementing Compose's two-stage semantics, service scope and unset/empty distinctions, not generic configuration merging.

Near MoonBit projects: [ConfigWeave](https://github.com/123123213weqw/moon-configweave) already merges layers, interpolates, traces provenance and handles secret propagation (Apache-2.0, 0.1.0 dated 2026-10-05); [ConfigScope](https://github.com/Noverberrain/ConfigScope) has `LayeredConfig::merge_with_provenance`, explanation and compatibility matrices (Apache-2.0, 0.3.0 dated 2026-09-25); [dotenv](https://mooncakes.io/docs/spectacleCase/dotenv) has parse, expansion, multi-config, diff and validation (Apache-2.0). Merely adapting those APIs would fail the differentiation gate.

Demand: [Docker's environment precedence documentation](https://docs.docker.com/compose/how-tos/environment-variables/envvars-precedence/), [Compose issue 9443](https://github.com/docker/compose/issues/9443), and [issue 12035](https://github.com/docker/compose/issues/12035) document repeated confusion about interpolation and `env_file`. [compose-go](https://github.com/compose-spec/compose-go) is used by Docker Compose, nerdctl, Tilt, kompose and testcontainers-go. Docker Compose had approximately 38.4K stars in the checked page.

MoonBit suitability: pure standards-based resolution is portable and testable against the reference implementation. Risks: generic configuration overlap and evolving Compose semantics.

### Pact consumer/provider interoperability (retained, lower priority)

Users: teams controlling both clients and API providers. Workflow: execute actual consumer SDK tests against declared interactions; reject unexpected/missing calls; export standard Pact; verify a real local provider against those interactions with isolated provider states. Independent value is cross-language consumer-driven interoperability, not another API schema checker.

Near MoonBit projects: [MoonContract](https://github.com/Han-Wentao/mooncontract) (`compile`, `validate_request`, `validate_response`, deterministic OpenAPI mocks; MIT, 0.1.1 dated 2026-09-14); [MoonContractGuard](https://github.com/yyqdbngt/moon-contractguard) (`execute`, `run`, `validate_schema`, `verify_case`; Apache-2.0, 0.1.0 dated 2026-10-05); [MoonVCR](https://github.com/chenqi-arch/moonbit-project) (cassette recording/replay, matching and response contracts; Apache-2.0, 0.3.0 dated 2026-09-26). Generic API testing and recording must not be duplicated.

Demand: [Pact official documentation](https://docs.pact.io/), [Pact JS](https://github.com/pact-foundation/pact-js) (MIT, approximately 1.8K stars), [npm downloads](https://api.npmjs.org/downloads/point/last-month/@pact-foundation/pact) returned 2,624,582 downloads for 2026-09-12 through 2026-10-11. Downloads are installs/CI traffic, not unique users. Official fixtures: [pact-specification](https://github.com/pact-foundation/pact-specification).

MoonBit suitability: portable interaction matching and verified file interoperability. Risks: API-testing neighborhood overlap and matcher/generator/version compatibility cost. A parser or a wrapper around a foreign verifier is not an adequate first milestone.

## Comparative scoring

Scores are engineering judgment, 1–5 with 5 best; a high maintenance score means more manageable cost. The purpose/overlap gate takes priority over the weighted score.

| Dimension | Weight | MoonTestLedger | Compose contracts | Pact interoperability |
| --- | ---: | ---: | ---: | ---: |
| User value | 25% | 5: ordinary CI artifacts and retries | 5: ordinary container configuration | 5: common client/provider teams |
| Differentiation | 25% | 4: explicit inventory and retry evidence | 3: generic config neighbors | 3: API testing neighbors |
| Technical depth | 15% | 4: identity, completeness, atomicity, evidence | 4: two-stage semantics and precedence | 5: matching and interoperability |
| Feasibility | 15% | 4: bounded report profiles | 4: reference implementation available | 3: compatibility workload |
| Portability | 8% | 5: pure reconciliation | 5: pure semantics | 4: provider execution adapters |
| Demonstrability | 7% | 5: local files and explicit expected results | 5: local reference comparisons | 5: local consumer/provider |
| Maintenance | 5% | 3: report dialects | 3: specification evolution | 2: matchers, generators, versions |
| Weighted total / 100 | | **87.0** | **82.0** | **79.4** |

## Search coverage and limitations

Checked the full [Mooncakes module metadata endpoint](https://mooncakes.io/api/v0/modules) (approximately 2,950 modules, changing during research), names/descriptions/keywords and relevant public interfaces and implementations. Keywords: `junit`, `xunit`, `flaky`, `test report`, `test result`, `test history`, `shard`, `retry`, `CI`, `report`, `pact`, `consumer-driven`, `provider verification`, `compose`, `env_file`, `dotenv`, `config`.

Web/GitHub queries included `MoonBit JUnit XML test reports merge flaky retry`, `site:github.com moonbit junit parse`, `site:github.com moonbit flaky report`, `pact language:MoonBit`, and MoonBit with Compose environment terms. A no-hit does not prove absence. Unpublished/private repositories, underspecified metadata and indexing omissions remain uncertain. MoonBit's own test runner also aggregates internal results, but its runner-local event protocol is not a versioned interface for external JUnit artifact inventory or independent CI retries.

No performance, uniqueness, production adoption or complete JUnit compatibility is claimed.

## Follow-up boundary audit — 2026-10-14

A follow-up search found [mizchi/flaker](https://github.com/mizchi/flaker), a significant omission from the initial review. Its [public MoonBit interface](https://github.com/mizchi/flaker/blob/main/src/pkg.generated.mbti) includes `detect_flaky`, `aggregate_report`, `classify_report_diff`, `find_matching_quarantine`, `is_blocking_failure`, `compute_quarantine_exit_code` and `summarize_quarantine`. Its [contracts](https://github.com/mizchi/flaker/blob/main/src/contracts/pkg.generated.mbti) include ownership/reason/expiry policy and run status/retry counts. Therefore general flaky detection or expiring quarantine would overlap; a local quarantine draft was discarded before commit.

The [MoonBit module metadata](https://github.com/mizchi/flaker/blob/main/moon.mod.json) declares 0.3.1/MIT; [Node package metadata](https://github.com/mizchi/flaker/blob/main/package.json) declares 0.14.0/ISC. These declarations differ; no definitive unified license conclusion is inferred. The checked GitHub page showed 535 commits; the [repository API](https://api.github.com/repos/mizchi/flaker) returned 24 stars, `pushed_at` = 2026-09-25T13:38:54Z and no detected license. Push time is activity evidence, not necessarily the last default-branch commit date; stars are not adoption counts. Its README documents sampling, runner orchestration and history. It is a material neighbor.

MoonTestLedger's retained boundary is a complementary **full external artifact inventory and exact-source replay layer**. This milestone commits the complete expected plan, recovery policy and original XML into a strict manifest, then preserves completeness/test-gate semantics during offline checks. It neither estimates flakiness nor manages quarantine. The inspected flaker surface does not expose this full-plan/raw-XML checksum workflow; it does expose adjacent report aggregation/diff/gates, so broad testing-platform uniqueness is expressly not claimed. Interoperation is a possible future adapter, not implemented.

Follow-up queries: `"MoonBit" "quarantine" tests`, `site:mooncakes.io "quarantine"`, `"MoonBit" "flaky" testing`, `site:github.com/mizchi/flaker "checksum"` and `site:github.com/mizchi/flaker "integrity"`. These inspected interfaces and searches support the narrow boundary only; internal/unpublished APIs and indexing omissions remain uncertain. [GitHub's documented artifact digest validation](https://docs.github.com/en/actions/tutorials/store-and-share-data#validating-artifacts) substantiates the mainstream transfer/retention integrity need. The SHA-256 primitive is reused from the official experimental x package, not presented as an original algorithm or independently audited implementation.
