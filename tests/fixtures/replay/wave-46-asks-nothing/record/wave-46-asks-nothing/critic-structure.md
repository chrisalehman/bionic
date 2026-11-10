reviewed: b69ac4a3c8909bbc00415684ec9eb5204f2f1bf1..837ddc39161b522a7071b996cf9d0d9121f1c61b
question: structure
result: flag
scope: whole
check: reuse FLAG T25's test helper re-derives the merge-unproved decision number that T10's proof_unproved_needs already reads from the same page line
check: one-site FLAG green for the full pass is decided twice (T7 proof_health_line, T9 proof_whole_text) and they disagree at F when F's only reds are inherited; the whole-run-at-head rule is decided twice (T13 tick, T8 rule 3) with different tests
findings: 1
finding: 1 S3 on payload/scripts/lib/proof.sh:1972 the stack-health line and the release card disagree on green at the same head when the whole run's only reds are inherited debt
debt: duplicate merge-unproved-decision-number tests/lib/rehearsal.sh:152, payload/scripts/lib/proof.sh:1801
debt: duplicate whole-run-at-head hooks/poker/tick.sh:2221, hooks/poker/proof.sh:1791
debt: unpinned-pair full-pass-state payload/scripts/lib/proof.sh:1953, payload/scripts/lib/proof.sh:1744

# critic-structure — wave-46-asks-nothing, the whole run

Scope: what the pieces duplicate between them. Each piece's own reuse was read at its landing. Compared against the spec's ownership table (§3) and a search of hooks/ and payload/scripts/ for each new site, by name and by job.

## reuse — FLAG
- **The decision number, parsed twice.** T25 added `_rh_reply` (tests/lib/rehearsal.sh:149-156). It reads the decision number of `approve:merge-unproved` off the newest release-approval page with the same sed that T10's `proof_unproved_needs` runs (payload/scripts/lib/proof.sh:1801). A-T25.2 says it copies that function. The copies already differ. The product holds the page to `head=<40-hex>`, and the helper takes the newest page by its head8 prefix and mtime. No user meets the difference, since one copy is test code. Debt, duplicate.
- **Compared and found clean.** `walk_register` / `walk_pointer_put` (T11) are one act shared by `proof-add walk`, `deliver` and `step-field` (A-T11.9). `proof_merge_unproved` (T10) is the one predicate behind the card and facts_state (A-T10.12). `REGISTRY_FILES` (T2) is read by the cap and by shell-lint (A-T2.1). `units_born_class` (T1) is asked by both the count and task-add (A-T1.2). `proof_health_put` (T7) is the one writer for proof-add and the landing settlement (A-T7.4). `part_land` (T16) serves both part verbs.

## one-site — FLAG
- **Green for the full pass, decided twice.** T7's `proof_health_line` prints `green head=F` when the proof line's raw `owed=` is empty (payload/scripts/lib/proof.sh:1972). Inherited debt stays in that set (A-T7.3). T9's `proof_whole_text` prints `green at F` when the working head is F and the judge reads covered there (proof.sh:1754). The judge drops inherited suites from owed (`_proof_floor_base`, proof.sh:1829). So at the head F of a whole run whose only reds are inherited debt, the matrix head reads `stack-health: red head=F owed=<suite>`. At the same head the release card, the scorecard and the continuation read `whole suite: green at F` and ask no merge word. The person meets both on one head (finding 1). This is by reading, not run. Both writers state their rule (A-T7.3; proof.sh:1741-1743), and the two rules differ. It is rated S3 on, which defers, so the check is FLAG, not FAIL. The wave's own premise is that one judge prints one state, and D4 says green means the whole suite ran green. On that reading the health line is the right one and the card the wrong one.
- **The pair has no agreement test.** The ownership table names `stack-health:` as a rendering of proof_state, with `tests/proof-at-head.test.sh` §ONE as its agreement test. §ONE reads the card, the scorecard and the continuation and never reads stack-health: `/usr/bin/grep -n "stack-health\|health" tests/proof-at-head.test.sh` prints nothing. session-poker-4 §STACK pins the health line against its own function only (VT-12b). The pair is unpinned. Debt, unpinned-pair.
- **One whole run per head, decided twice.** T13's start decides "this head already has a whole run" from any file `record/<wave>/regression-run-<head>*.log` (hooks/poker/tick.sh:2221). T8's rule 3 decides it from such a file whose second line is `command: tests/run.sh` (hooks/poker/proof.sh:1791-1792). A log at the head from another command stops the tick, while regression-run would still run. Debt, duplicate. No user meets it today.
- **Compared and found clean.** The hand-holds field list and its header are pinned by equality (A-T5.1, landing-line-2 §FIELDS). The refusal's `needs:` form has one writer, `refuse()`, and one reader, the fold (A-orch.21). The human stops and wait minutes have one function, `scorecard_report`, for the sitrep and close-out (close-out-4 SC-2). The sheet's separate waiting-on-you line is the adversarial record's finding, not a second owner of this concept.

## Raised, not checks
- over-engineering: none found across pieces.
- open-closed, substitution: T23 narrowed `approve merge-unproved` to plans with an integrate row while T10's card still asks it everywhere. That disagreement is in the adversarial record.
