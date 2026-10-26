---
governing-skill: agent-skills:documentation-and-adrs
sdlc-step: 7
epic: epic-23-bionic-tech-debt
wave: wave-46-asks-nothing
intent: build
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
status: Proposed (Step 7, 2026-10-25)
created: 2026-10-25
---
# ADR-074 — Green means the whole suite ran here

## Status

**Proposed** (Step 7, 2026-10-25). On Chris Lehman's ruling D4 (wave-46 design-ledger Δ7, 2026-10-25 12:43 PM PDT: "1"), the design frame. D14 (merge unproved is an ask) and D16 (two refusals go, one stays) were defaulted at the design step and approved with the Step-2 card (Δ15). D5 (the tick starts the pass) was ruled "provisionally, option 1" with the orchestrator allowed to start it too (Δ14). It extends ADR-070 and ADR-072 and replaces neither. It narrows what ADR-054's `covered` admits at the merge and leaves that floor rule as it is.

## Context

Wave 45 (1.28.0) closed on a false green. Its continuation read `whole run green at cf173c49`, and the proof line at cf173c49 records a run that exited 1, 122 of 126, owing four suites. The judge read that whole run, behind the head, plus the suites of the landings since, as `covered`. `regression-run` refused a fresh pass at the merge head as already proved on the same reading. The continuation's own reader printed green for any proof line. So the gates, the card and the continuation each computed their own truth about one pass, and the merge went ahead on the person's waiver of the final regression.

The scorecard missed its own stops by the same habit. It read 1 stop and 27 minutes of waiting in the autonomous half, where the ledger held 4 stops and about 514 minutes. The charter of 1.29.0 (`ideas/bionic-1.29.0-charter.md`) names both as reasons not to believe a close without reading its record.

This run's walk re-read wave 45's record with the new readers (`record/wave-46-asks-nothing/walk.md` §4). They print red at cf173c49, which is what the proof line holds, and 7 stops and 594 minutes, where the old continuation said 1 and 27.

ADR-070 fixed which check judges a landing. ADR-072 had a landing settle every cell it proves. Neither said what a green whole suite means for the head the merge takes, or which reader prints it.

## Decision

**A head is green only where the full pass ran green at it.** The full pass is one run of `tests/run.sh` over every suite at one head. A later head is not green until its own pass runs, whatever its landings' suites say.

**Covered is red at this head.** A whole run behind the head plus the landings since is `covered`. `proof_state` keeps its three answers. Every reader prints `covered` as red at this head with the landings counted: `whole suite: red at <h8>, <n> landings before this head`.

**The merge at such a head is the person's word.** The release approval card asks the merge without a whole run at this head as its own decision, `approve:merge-unproved` (D14). `reply` writes it as `approved: merge-unproved by <who> <ISO> head=<h40> "<reply>"`. The facts judge passes the regression at that head and no other. The word never passes a suite a whole run left red: an owed or uncovered suite stays refused.

**One judge, one printer.** `proof_state` is the one judge. The card, Step 8, close-out, the continuation and the scorecard print its one state through `proof_whole_text`. `stack-health:` is a rendering of the same judge through `proof_health_line`, never a record of its own.

**The pass starts itself.** `regression-run` refuses only at a head that already has a pass (D16). When nothing is ready, nothing is running and the working head is past the last proof, the tick starts the pass detached, under the gate's whole-run rule (D5 as ruled). The orchestrator may start the same verb. Both are the machine, and only a pass a person starts counts as a hand-hold.

## Consequences

- T9 built one judge and one printer. `proof_whole_text` replaced `sitrep_whole` and `co_regression_text`, and over wave 45's shape the card, the scorecard and the continuation all print `red at <F8>, 2 landings before this head`.
- T10 and T23 put the ask on the card. T10 added `approve:merge-unproved`, the approval line and the fourth regression state of `facts_state`, with one predicate the card and the judge share. T23 admits the word where the plan's rows read `release`, so the ask has an exit on a plan with an integrate row.
- T13 has the tick start the pass, as a roster object `regression@<h8>` run through `booked.sh --detach`, recording its proof through `proof-add regression`.
- T8 removed two refusals and kept one. The covered-head refusal and the whole-run-behind refusal are gone, the same-head refusal stands, and the run line carries `starter=tick|orchestrator|person`.
- T7 made `stack-health:` a rendering: green only at a pass with nothing owed, and red with an empty `owed=` once landings close every owed suite.
- T25 to T28 rewrote the fixtures that pinned the covered-is-green reading. The rehearsal worlds and the close replay now reach Step 8 on the person's word, and the door card's world runs its pass again at the release head.
- This run closed under the rule. The tick started the last two passes itself, at 837ddc39 after the fixture rows and at 5a08f601 after the walk-gate fix, and each ran 127 of 127 green. Step 7 advanced at 5a08f601 with every fact holding and no person asked. The first pass, at 402980ec, was started by the orchestrator, because the walk and critic rows were ready at the last build landing and the tick starts nothing while a row is ready.
- `covered` keeps the meaning ADR-054 gave it, one whole run plus the greens of what changed. No reader prints it as green, and `facts_state` does not take it as a pass. Because `facts_state` serves every caller, advancing to Step 7 is held to the same rule, which this release carries as a known limit.
- A release entry row lands a commit after the pass, so the head the release card reads is one landing past it. The tick starts the pass at that head, or the person answers the card.
