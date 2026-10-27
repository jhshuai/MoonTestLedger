# Review the next complete test inventory

Inventory is a maintained contract, so test additions/removals and CI matrix changes need review before a new run. This workflow compares **two full declared RunPlans**, retains both, lists deterministic changes and requires acknowledgment of that exact review against an unchanged baseline. It does not derive a smaller plan from received XML, rewrite existing archives, run tests, sample tests, quarantine failures or establish who approved a change.

## Three complete workflows

1. **Routine test evolution.** A payment team adds `authorize [USD]`, retains `authorize [EUR]` and explicitly removes an obsolete `refund` test. A developer edits the proposed full future inventory and creates a review artifact. A reviewer inspects both complete plans and added/removed identities. After approval, application writes a new plan with a fresh run ID. CI producers bind reports to the new run; old failing/incomplete evidence stays unchanged.
2. **CI matrix migration.** A maintainer upgrades smoke tests from Node 20 to Node 22, retires a legacy report and adds a Windows shard. Review shows binding changes, report removal and report addition, with all cases visible in before/proposed plans. Duplicate identities, ambiguous shards and nonconsecutive retry attempts are refused before a review is produced. The reviewed future plan becomes the producers' shared contract.
3. **Concurrent baseline edit.** Another maintainer changes the current plan after review. Application refuses `ReviewStale` and creates no output. The developer creates a fresh review against the new baseline; the reviewer checks its new token and applies to a new file. Editing hashes/change projections, using a different token or reusing the old run ID also refuses before creation. Existing plans and archives are preserved.

## CLI demonstration

`examples/review/` contains project-authored Apache-2.0 synthetic **plans**, not claims that their tests ran. They model the payment/matrix changes above. The committed `review.json` is the deterministic six-change preview checked across all four library targets. Create `output/` first:

```sh
moon run --target wasm cmd/moontestledger -- review-plan examples/review/before.json examples/review/proposed.json --output output/inventory-review.json
```

Read `before`, `proposed`, every `changes` entry and `review_sha256`. Obtain human approval through your review process. Then explicitly supply **that displayed token**:

```sh
moon run --target wasm cmd/moontestledger -- apply-plan-review output/inventory-review.json examples/review/before.json --approve REVIEW-SHA256 --output output/next-plan.json
```

The placeholder intentionally does not automatically extract and apply a token. The CLI requires `--approve` and a new `--output` file. The public token binds content; it is **not authentication or proof of a human's presence**. Use repository/CI approval controls to authorize the person. No project workflow automatically applies inventory reviews. Tests acknowledge synthetic fixtures only to validate the mechanism.

Creation returns 0; invalid data, stale baseline, absent/wrong acknowledgment, same run ID or output error returns 2 with a diagnostic. These are not test-result gates. Run the next tests against the approved plan and use the normal 0/1/3 evidence gate. Each prior archive remains bound to its original complete plan and XML.

## Public API and representation

The facade re-exports public wire-owned `PlanReview`, `PlanChange`, `PlanChangeKind`, `review_plan` and `decode_plan_review`. Reviews expose independent `before()`, `proposed()` and `changes()` copies, `token()`, bounded `encode()`, and `approve(current, approval=TOKEN)`. Approval returns a separate proposed RunPlan, requiring an unchanged canonical baseline and a different run ID. Existing validated resource budgets apply and can be lowered explicitly.

Schema 1 / kind `moontestledger/plan-review` retains both full plans, canonical plan SHA-256 values, all derived changes and `review_sha256`. The review digest hashes the UTF-8 label `moontestledger/plan-review-v1`, one LF byte (`0x0a`), and the canonical indented review body **without** `review_sha256`. The body includes both plans, both plan hashes and every change. It is not a signature or a general JSON canonicalization standard.

Change kinds: run metadata, report addition/removal, binding change, case addition/removal and case-order change. Report additions/removals cover the full retained report; individual case changes describe shared report IDs. An empty `report_id` denotes run metadata; `key` is set only for case additions/removals. Metadata appears first. Remaining changes use explicit UTF-16 lexicographic report-ID order, then classname/name for cases. Within a report, binding changes precede cases and case-order changes. Full plans retain existing RunPlan canonical report order and exact case order. Budget violations refuse the whole review rather than truncate plans or changes.

Decode applies strict nested plan/schema/duplicate-key/exact-integer validation, recomputes the review, and checks every supplied hash/projection. Unknown fields and edited/missing changes are refused. Baseline comparison uses the full canonical plan. XML/old evidence is not an application input and is never rewritten.

```sh
moon run scripts/review-e2e.mbtx wasm
moon run scripts/review-e2e.mbtx native
```

The evaluator checks acknowledgment, stale/edited reviews, exclusive output/input-alias preservation, same-run shrink refusal and recovery. Portable tests cover all seven change kinds, varied sets, inclusive budgets, malformed/unknown/duplicate/rounded JSON, deterministic round trips and caller isolation. The independent consumer checks the facade API and committed preview on Wasm, Wasm-GC, JS and native.
