# Version 1 format contract

## Plan and bundle

All JSON fields shown in README and the checked-in examples are mandatory; no additional fields are accepted. Schema is exactly 1. Attempt is an exact positive 32-bit integer. Strings are case-sensitive and not trimmed. Binding identifiers cannot be empty, whitespace-only or contain NUL. Classname can be empty; testcase names cannot be empty or whitespace-only.

The run plan contains at least one expected testcase. Report IDs are unique. Each environment/shard declares one report for each consecutive attempt starting at 1; a retry contains an explicitly declared subset of the initial inventory. The same testcase cannot belong to two shards in one environment.

Bundles can be empty (no artifacts have arrived). Repeated report bindings can be supplied: ingestion accepts an identical document and rejects a conflicting one. Report paths are data, not glob patterns; no report discovery or directory scanning occurs.

Decoded duplicate keys, including equivalent escaped names, are refused. Unknown fields and schema versions are refused to avoid silently dropping future semantics. JSON source size uses the configured per-source budget, and lexical nesting is capped at 64 before parsing.

## JUnit XML common profile

Allowed structural elements:

| Parent | Children |
| --- | --- |
| document | one testsuite or testsuites |
| testsuites | testsuite, properties, system-out, system-err |
| testsuite | testsuite, testcase, properties, system-out, system-err |
| testcase | failure, error, skipped, properties, system-out, system-err |
| failure, error, skipped | text and CDATA |
| inert properties/output subtree | original XML retained; outcomes are not inferred from it |

Allowed attributes on result nodes:

| Node | Attributes |
| --- | --- |
| testsuite, testsuites | name, package, id, tests, failures, errors, skipped, disabled, time, timestamp, hostname, file, assertions |
| testcase | name, classname, time, file, line, assertions, timestamp |
| failure, error, skipped | message, type |

Disabled must be zero if present. Nonzero disabled counters need producer-specific outcome semantics that this version cannot safely infer. Timing and location metadata remain in source; they do not affect outcome or identity.

Result nodes outside the allowlist, namespaces on result nodes, custom status/result attributes and embedded flakyFailure/rerunFailure conventions are refused. Express retries as separately bound documents and explicit attempts. Future producer profiles need real captured output and conformance tests before acceptance.

Declared suite counters include descendant testcases. Failure/error counts count cases carrying each kind, not the number of payload nodes. A case with both failure and error has an error outcome and retains both payload kinds. A skipped case cannot also contain failure/error and cannot declare two skipped markers.

Duplicate (classname, name) identities within one document are refused. Parameterized names and decoded entities are exact identities; suite names or file paths do not disambiguate duplicates.

DTD/entity declarations are refused; external resources are never fetched. The XML dependency validates XML well-formedness, decoded character/entity values, attribute uniqueness and the entire document through EOF. The adapter adds structural, count, semantics and resource checks.

## Diagnostics and derived evidence

Library errors carry code, report_id, logical path, message, line and column. Source locations are one-based when available; zero means not applicable. XML source offsets use UTF-16 units.

Ledger is an opaque type. Its mutable plan and document storage cannot be read or mutated by downstream code. The compile-negative encapsulation probe checks this contract, in addition to runtime tests for caller-array isolation.

The CLI emits one schema-1 diagnostic object to standard error on invalid input or I/O and returns 2. Audit summaries go to standard output. Users can correct an input and retry: failed ingestion does not mutate already accepted documents.

Summary JSON contains canonical environment/shard/case ordering, ordered attempts, all failure/error payloads and missing inventories. It does not provide a rewritten XML document or a parser for round-tripping summaries. Plan/bundle encoders and decoders cover the supported interchange round trip.

## Replayable evidence archives

The schema-1 envelope has exactly `schema`, `kind` (`moontestledger/evidence`), `deny_recovered` (boolean), `plan` (the complete schema-1 plan) and `documents`. Each document has exactly `id`, `run_id`, `revision`, `environment`, `shard`, `attempt`, and `xml` (original decoded XML). Duplicate report IDs are rejected. No report paths or projected summary replace the authored source.

Decoding reparses each XML and ingests it against the plan. Encoding checks that each accepted projection exactly matches its reparsed source, then checks the encoded JSON input budget. Unknown fields, duplicate JSON keys, unsupported versions, binding conflicts, malformed XML and resource violations are refused. Missing documents are allowed and remain incomplete. Canonical encoding orders documents by the validated plan. The supplied recovery policy survives round trips.

## Historical comparison

Only validated evidence archives enter the comparison API. Rows match exact `(environment, classname, name)`, independently of shard placement, and are sorted deterministically. Both original runs remain separate. Change kinds are added, removed, regressed, improved, changed, unchanged and unknown. Incomplete matched rows are unknown. Increasing severity from pass/skip to recovery to final failure/error/unresolved is a regression. Failure-to-skip cannot be an improvement.

The gate returns 3 for missing evidence, removed baseline inventory or differing recovery policies, before considering regressions. It returns 1 for a regression or added adverse testcase, otherwise 0. It is a regression gate, not a replacement for the current run's verify gate. Result getters return copied arrays including complete attempt/diagnostic payloads; JSON is a derived status view referencing both run IDs/revisions and listing missing evidence. There is no comparison-JSON decoder or fuzzy identity matching.
