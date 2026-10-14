# End-to-end examples and provenance

Run commands from the module root. Every bundle's XML paths resolve relative to that bundle.

## Unmodified upstream reports

Repository: [dorny/test-reporter](https://github.com/dorny/test-reporter), commit [cc52f364a405169afe07bb00dab3d375b451229d](https://github.com/dorny/test-reporter/commit/cc52f364a405169afe07bb00dab3d375b451229d), MIT license. Files were downloaded on 2026-10-13 without transformation. The complete upstream license is retained at upstream/LICENSE.dorny-test-reporter.

| Local file | Upstream path | SHA-256 |
| --- | --- | --- |
| upstream/jest-junit.xml | [__tests__/fixtures/jest-junit.xml](https://github.com/dorny/test-reporter/blob/cc52f364a405169afe07bb00dab3d375b451229d/__tests__/fixtures/jest-junit.xml) | 8e18da3a6e4252c34fe7899fad28f8eceeb43849329989b36f2ff68dc7698e58 |
| upstream/pytest-counter-mismatch.xml | [__tests__/fixtures/python-xunit-pytest.xml](https://github.com/dorny/test-reporter/blob/cc52f364a405169afe07bb00dab3d375b451229d/__tests__/fixtures/python-xunit-pytest.xml) | 4b6b57757b6ce395c8491739aaf50199f1d5f3e0235de87cd51e9194d811a560 |

The Jest producer is inspectable upstream: its [package configuration](https://github.com/dorny/test-reporter/blob/cc52f364a405169afe07bb00dab3d375b451229d/reports/jest/package.json) runs Jest with jest-junit and writes this fixture. Its [main tests](https://github.com/dorny/test-reporter/blob/cc52f364a405169afe07bb00dab3d375b451229d/reports/jest/__tests__/main.test.js) and [second tests](https://github.com/dorny/test-reporter/blob/cc52f364a405169afe07bb00dab3d375b451229d/reports/jest/__tests__/second.test.js) match the six observed cases. This is captured framework output for a public sample suite, not a claim of production traffic.

The pytest fixture declares tests="15" but contains ten testcase elements. It deliberately remains unmodified here. Its capture workflow must reject the mismatch with MTL_JUNIT_COUNT; a fixture being in an upstream repository is not enough to establish internal consistency.

~~~sh
moon run --target wasm cmd/moontestledger -- audit examples/upstream/plan.json examples/upstream/bundle.json
moon run --target wasm cmd/moontestledger -- audit examples/upstream/plan.json examples/upstream/missing-bundle.json
moon run --target wasm cmd/moontestledger -- capture examples/upstream/invalid-bundle.json
~~~

Expected outcomes: complete six-case report with exit 1; one missing report/six missing cases with exit 3; counter diagnostic with exit 2.

The JSON plan/bundles are newly authored example bindings. The upstream-macos-jest environment describes the captured report's paths, not a locally repeated macOS test run.

## Synthetic selective retry

Retry/first.xml and retry/second.xml are newly authored boundary fixtures under the project Apache-2.0 license. They model a payment-test shard with pass, failure and skip, followed by a retry of only the failed case.

~~~sh
moon run --target wasm cmd/moontestledger -- audit examples/retry/plan.json examples/retry/bundle.json
moon run --target wasm cmd/moontestledger -- audit examples/retry/plan.json examples/retry/missing-bundle.json
moon run --target wasm cmd/moontestledger -- audit examples/retry/plan.json examples/retry/bundle.json --deny-recovered
~~~

Expected outcomes: complete with one recovered testcase and both attempts retained (0); missing declared retry (3); complete recovery rejected by policy (1).

Bundle.json presents attempt 2 before attempt 1, verifying declared retry order rather than collection order.

The newly authored Apache-2.0 `retry-only-bundle.json` contains just attempt 2. Archive it and `missing-bundle.json` separately against the same full plan, then merge and verify as shown in the root README. This checks collection from independent producers without shrinking the expected inventory.

## Automated evaluator

The newly authored `history/` fixtures are Apache-2.0 synthetic runs at two revisions, with a payment regression and a refund improvement. Run the three archive/compare commands in the main README. Neither fixture is altered upstream output. The evaluator also compares an unmodified upstream Jest archive to itself and checks that an incomplete archive cannot pass a comparison.

~~~sh
moon run scripts/e2e.mbtx wasm
moon run scripts/e2e.mbtx native
~~~

The MoonBit script invokes the actual file CLI and verifies exit codes, parsed summary JSON, the six-case upstream report, missing-artifact behavior, capture, retained retry attempts, recovery policy and malformed-counter diagnostics. No server, CI account, token or private infrastructure is required. Native execution requires a working native toolchain.
