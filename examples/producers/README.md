# Real producer conformance

These are **actual, unedited reports generated on 2026-10-28** from the deliberately small, project-authored Python/Java test inputs in this directory. They exercise real tool output; they are not production traffic, third-party test suites, hand-written XML, or evidence of universal producer compatibility. Existing public Jest and invalid pytest-count fixtures remain unchanged.

| Captured profile | Files | Expected observations / gate |
| --- | --- | --- |
| pytest 8.3.5, CPython 3.13.13, Linux, xunit2, junit_logging=all | pytest-xunit2.xml | 2 pass, 1 failure, 1 setup error, 1 skip / 1 |
| Maven 3.9.9, Surefire 3.5.2, JUnit 4.13.2, Temurin 8u492-b09, Windows | surefire-example.xml; surefire-parameterized.xml | 1 pass, 1 failure, 1 error, 1 skip / 1; 2 parameterized passes / 0 |
| Gradle 7.6.4, JUnit 4.13.2, Temurin 8u492-b09, Windows, outputPerTestCase=true | gradle-example.xml; gradle-parameterized.xml | 1 pass, 2 failures, 1 skip / 1; 2 parameterized passes / 0 |
| Same Surefire, rerunFailingTestsCount=1, deterministic fail-then-pass | surefire-retry.xml | **refused**: MTL_JUNIT_UNSUPPORTED at flakyFailure |

`fixtures.json` records exact SHA-256, generator versions and independently authored expected identities/outcomes. The conformance evaluator checks those bytes before using them, then checks the consumer's source digest/byte count after argument transport. Captured metadata includes actual timestamps, system properties, paths and stack traces. It is retained as authored output, including the Windows producer's console-encoding behavior. Do not rewrite these historical files to match a different machine or rerun; new captures need separate receipts and an explicit profile review.

Gradle reports the thrown Java exception as `<failure>`; Surefire reports it as `<error>`. The ledger honors each XML node and never guesses an exception's category from its class name. Parameterized names remain exact. The real Surefire retry report includes an initial failure inside `flakyFailure/stackTrace`; accepting only its final pass would discard evidence, so this version rejects it. Export each runner attempt separately and bind explicit consecutive attempts instead. Gradle merged-rerun plugins and other untested extensions are not claimed supported.

## Run without Python, Java, a CI account or private infrastructure

From the repository root, with the documented MoonBit toolchain/dependencies and Node for JS:

```sh
moon run scripts/check-producers.mbtx wasm
moon run scripts/check-producers.mbtx wasm-gc
moon run scripts/check-producers.mbtx js
moon run scripts/check-producers.mbtx native
```

All four actually execute a separate consumer module against the **current library source** via a temporary workspace. This complements `check-consumer.mbtx`, whose library input is a clean **committed Git export**. Each accepted fixture checks every identity/outcome, exact XML, deterministic replay and JSON/detached/ZIP/USTAR round trips, absent inventory gate 3, atomic unknown-report refusal and recovery. The real retry fixture must return an actionable diagnostic and a subsequent valid parse must succeed. Temporary consumer/build evidence is retained and its path is printed. Script host dependencies are explicitly pinned to async 0.22.4/x 0.5.5.

On Wasm and native, the same evaluator additionally executes the real file CLI against the combined 17-case inventory: collect -> verify (1), delete one report -> collect -> verify (3), substitute unsupported retry XML -> diagnostic (2) without a destination, restore the original -> byte-identical complete evidence (1). CLI validity and test failure are different outcomes. The full strict verifier runs these checks automatically on every target; native means actual execution, requiring a C toolchain.

For a standalone report collection (create `output/` first):

```sh
moon run --target wasm cmd/moontestledger -- collect examples/producers/collection.json examples/producers --output output/producers.json
moon run --target wasm cmd/moontestledger -- verify output/producers.json
```

Creation returns 0; verification returns 1 because the intentional failures are retained. Each producer-file profile is a separate declared environment. The directory collector reads only declared files, so the deliberately unsupported retry report is not part of this accepted collection. The complete expected inventory comes from the reviewed fixture contract, not from whatever XML happens to arrive. `moon run scripts/check-producers.mbtx --write-collection` regenerates the example inventory **from that reviewed contract**; normal validation checks it for drift.

## Reproduce producer generation (optional)

Install the exact versions above if reproducing this capture's profile. Run from the repository root; these tests deliberately return failing statuses for the ordinary reports. Use a separate output location to preserve the committed evidence:

```sh
python -m pytest examples/producers/pytest/test_example.py -o junit_family=xunit2 -o junit_logging=all --junitxml=output/new-pytest.xml
mvn -B -f examples/producers/maven/pom.xml test
mvn -B -f examples/producers/maven/pom.xml -Dtest=RetryTest -Dsurefire.rerunFailingTestsCount=1 test
gradle -p examples/producers/gradle --no-daemon test
```

Windows PowerShell needs quoted `'-Dtest=RetryTest'` and `'-Dsurefire.rerunFailingTestsCount=1'`; use `mvn.cmd` / `gradle.bat`. Actual capture used the absolute pytest input/output paths under the checked-out repository (reflected in its skip message), Maven/Gradle Windows launchers and the checked-in build definitions. Ordinary Maven writes `target/surefire-reports/TEST-example.{ExampleTest,ParameterizedTest}.xml`; the retry invocation writes `TEST-example.RetryTest.xml`. Gradle writes `build/test-results/test/TEST-example.{ExampleTest,ParameterizedTest}.xml`. The captured reports were copied as binary files to the names above without XML editing. Metadata/time/duration can differ on rerun; the captured digests are historical receipts, not predictions for regenerated bytes.

Initial Maven/Gradle attempts in WSL failed resolving Maven Central DNS. The successful Java captures ran on Windows with Temurin, without modifying DNS, dependency versions, TLS verification or normal failure outcomes. Producer tools/binaries/caches are not bundled. Python/Java files here are test **inputs** for the external producers; project automation remains MoonBit `.mbtx`.

## Sources and licenses

Test inputs, build definitions, expected contracts and evaluator are newly authored Apache-2.0. XML is generated output of those tests, containing producer stack traces/metadata; no upstream implementation or test suite is copied. Producer tools are invoked separately, not dependencies of the library or distributed binaries:

- [pytest 8.3.5](https://github.com/pytest-dev/pytest/tree/8.3.5), MIT; [JUnit output documentation](https://docs.pytest.org/en/8.3.x/how-to/output.html#creating-junitxml-format-files).
- [Apache Maven](https://github.com/apache/maven/tree/maven-3.9.9) and [Surefire 3.5.2](https://github.com/apache/maven-surefire/tree/surefire-3.5.2), Apache-2.0; [embedded rerun semantics](https://maven.apache.org/surefire/maven-surefire-plugin/examples/rerun-failing-tests.html).
- [Gradle 7.6.4](https://github.com/gradle/gradle/tree/v7.6.4), Apache-2.0; [JUnit XML reporting](https://docs.gradle.org/current/userguide/java_testing.html).
- [JUnit 4.13.2](https://github.com/junit-team/junit4/tree/r4.13.2), EPL-1.0; [license](https://github.com/junit-team/junit4/blob/r4.13.2/LICENSE-junit.txt).

These links document tools/conventions, not a claim that MoonTestLedger implements all of their features. Existing XML/compression/hash runtime dependencies and their licenses remain in the root [third-party record](../../THIRD_PARTY.md).
