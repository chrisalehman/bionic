---
governing-skill: agent-skills:documentation-and-adrs
sdlc-step: 7
epic: epic-23-bionic-tech-debt
wave: wave-48-reads-true
intent: bugfix
rigor: single
scale: task
canonical_sdlc_version: 14
surface_type: cli-plugin
language: bash
has_ui: false
multi_agent: true
deploy_target: n/a
cleanup_on_finish: true
use_worktree: false
walk: required
design-interview: true
model_plan: orchestrator=claude-fable-5-1; implementor=sonnet-high; senior-implementor=opus-high; researcher=opus-high; test-runner=haiku-high; auditor=opus-high; critic=opus-high
status: Proposed (Step 7, 2026-11-05)
created: 2026-11-05
---
# ADR-076 — The word accepts absence

## Status

**Proposed** (Step 7, 2026-11-05). On Chris Lehman's ruling D5 (wave-48 design-ledger Δ11, 2026-11-04 7:31 PM PST: "1"), inside the design frame D4 (Δ7: "1"). It amends ADR-074's sentence "The word never passes a suite a whole run left red: an owed or uncovered suite stays refused", which this ADR narrows to the owed suite. It keeps ADR-075's reading of "ran here" and replaces nothing.

## Context

A user project ran 1.29.1 through its epic 23 wave 9 and reported six defects and one gap (`ideas/bionic-1.29.2-bugfix-report-20261103.md`). Its second defect was this one. The release card offered the merge without a whole run at the head: "Merge without a whole run at this head — red at e4cc05cc, 4 landings before this head". The person replied, and `reply` wrote `approved: merge-unproved … head=9b66248a…`. Then `current 8 --check` refused anyway: `regression uncovered e4cc05cc..9b66248a — commit eb0938bc (row T15) is not proved: none has no run recorded at it`.

The card drew the decision on one predicate and the gate honoured it on another. The card read `proof_whole_text`, which said red. The gate read `_proof_floor_judge`, which said uncovered, and it consulted the word only on a floor it read covered. A comment in proof.sh said the two shared "THE ONE RULE", and they did not. The person's recorded word was refused, and the project closed the merge by hand.

ADR-074 had made the merge at an unproved head the person's word, and said the word never passes an owed or uncovered suite. That left the uncovered head with no exit but a pass, while the card offered a reply there.

## Decision

**The word covers absence, never a known red.** The person's merge word covers a head where proof is absent: the floor reads covered, or uncovered by content, a landing with no run recorded at it. It never covers a head where a suite the whole run left red is still owed, with no later green.

**One function draws and honours.** The card draws the decision on exactly those states and the gate honours it on the same, both through `proof_merge_ask`. Where the card draws the decision, a recorded word at that head admits `current 8 --check`. Where the floor is owed, the card draws no merge decision, and the Step-8 refusal names the pass as its one exit. No regression waiver word exists, so no reply on the card lifts an owed floor.

**The owed red outranks absence.** The floor judge reads the open reds before the head's own coverage. An unproved commit past a red floor reads owed, never uncovered. The same holds where the whole run's head is not in the branch's history: a green landing on another line is no proof that the red was fixed, so the pass is the exit.

## Consequences

- T3 built the one function. `proof_merge_ask` reads the floor judge at the head and the whole suite's state, and exits 0 with the decision's line on a covered or uncovered floor and 2 on an owed one, printing the owed suites. facts_state's regression arm and the card's merge decision both read it. Over an uncovered floor the line names the commit no run proved, so the person reads what they accept before they give the word. The regression-word sections of release-approval.test.sh moved into release-approval-2.test.sh over a shared prelude, to hold each suite under the length bar, and §WORD there pins the states table, so each state of the floor reads the same exits at the card and at the gate. The carried debt item merge-unproved-decision-number was burned into `proof_merge_decision`.
- T15 put the owed red first. The critic's whole read found that the floor judge dropped the open reds in two uncovered arms, so a red floor followed by one unproved landing read uncovered and the word waived a known red. `_proof_floor_judge` now asks the past-F walk for its closes first and judges the commits only when no red is open. release-approval-2.test.sh §OWED-FIRST pins it, red first at the base.
- T14 re-read two pins the whole run met. bash-walls-egd §PROSE-CONFIG-3b now reads the unproved floor line the card asks the word on. T15 re-pinned session-poker-3 57c and session-poker-5 CK-8r2-b, whose fixtures' floors owe no suite, to the unproved line.
- It adds no waiver word. `waive` still takes no regression question, and the merge word the card offers is the one word the regression honours.
- It does not read dotted ids as a rule, delete the kernel's reconcilers, take the reporting project's own choices, or name a finer prose rule than paths. Those stay as the run's requirements left them, and the reconcilers are the kernel's to delete in 1.30.0.
