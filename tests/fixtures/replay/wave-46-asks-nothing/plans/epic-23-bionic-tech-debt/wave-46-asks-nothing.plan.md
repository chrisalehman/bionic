---
governing-skill: canonical-sdlc
sdlc-step: 0
epic: epic-23-bionic-tech-debt
wave: wave-46-asks-nothing
intent: build
rigor: single
review-cadence: once
fix-policy: S1,S2-on
fix-cap: 4
scale: task
scale-recommendation: "The charter rules the scale: build, single rigor, task, as 1.28.0 ran, with integration by pull request. Two themes, about ten build rows and one working day, each row a narrow change to one plugin's verbs and walls on its own red test, so one plan and its Tasks table hold them without a spec-and-plan pair per theme."
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
archive-root: /fixture/home/bionic-archive
working-branch: wave/46-asks-nothing
integration-branch: main
base-sha: b69ac4a3c8909bbc00415684ec9eb5204f2f1bf1
seed: ideas/bionic-1.29.0-charter.md
release: 1.29.0
created: 2026-10-25
regression: yes
regression-override: Person A 2026-10-25 derived=no chosen=yes
adrs: adrs/epic-23-bionic-tech-debt/adr-074-green-means-the-whole-suite-ran-here.md
---

# wave-46-asks-nothing — bionic 1.29.0: the run asks nothing it can answer

## Goal

Build bionic 1.29.0 so that a full run stops on its person five times and no more, and so that its close can be merged on without reading the record. Wave 45 planned five stops and took nine; each unplanned stop was a refusal whose only exit was Person A's word, and the close said three things the record contradicts. Two themes: a refusal whose only exit is your word is a defect (the fix cap caps scope, not the wave's own defects; every refusal names its exit or says who it needs; strengthening a criterion is the orchestrator's, weakening the person's), and proved at the head, one reader (the regression proof is keyed to the head, the whole run starts itself, the release card, the merge and the continuation read the one proof line, the walk settles its cells, the scorecard reads the ledger). Accepted when the 1.29.0 close reads `hand-holds: total=0` with the walk's cells settled by its landing, and every proof the release card, the continuation and the scorecard print is read from the lines the gates read.

## Problem

Charter: `ideas/bionic-1.29.0-charter.md`, seeded during wave 45 at D30 and rescoped after the 1.28.0 close. Carried from `record/wave-45-whole-run/continuation.md` and the wave 45 handoff's open question 4.

## Design

The design is the spec's: `specs/epic-23-bionic-tech-debt/wave-46-asks-nothing.spec.md` §Design (D1 to D18), its rulings in `record/wave-46-asks-nothing/design-ledger.md` Δ1 to Δ15. One judge and verbs for every act: the full regression is a thing the tick or the orchestrator starts, the proof it writes is read by `proof_state` wherever it is printed, a landing settles what it proves (the walk's cells included), and every refusal names the verb that satisfies it or is logged as a thing the person had to do. The merge is unasked only at a head where the full pass ran green (D4, ADR-074). Each build row below cites the decisions and criteria it discharges; a non-trivial row's design paragraph is its task cell's detail.

## Eval design

| Requirement | Approach | Criterion | Eval type | Eval | Fails when |
|---|---|---|---|---|---|
| REQ-1 | task-add over fixture plans, one red per rule | AC-1.1 | hermetic | `tests/session-poker-5.test.sh` §EXEMPT → a third `born: review S2 on` row lands on `fix-cap: 2`, rc=0 | the policy test is removed from the cap's count |
| REQ-1 | task-add over fixture plans, one red per rule | AC-1.2 | hermetic | `tests/session-poker-5.test.sh` §EXEMPT → a third `born: review S3 on` row is refused on `fix-cap: 2`, the text names `counted 2 of 2` | the promoted marker is dropped and the S3 row lands |
| REQ-1 | task-add over fixture plans, one red per rule | AC-1.3 | hermetic | `tests/session-poker-5.test.sh` §EXEMPT → the born line ends `exempt under fix-policy: S1,S2-on` for S2 on, `counted 1 of 2` for S3 | the suffix is deleted from the success line |
| REQ-1 | task-add over fixture plans, one red per rule | AC-1.4 | hermetic | `tests/session-poker-5.test.sh` §REGISTRY → a fourth review-born row whose Files name `tests/CENSUS.md` lands | `REGISTRY_FILES` is emptied |
| REQ-1 | task-add over fixture plans, one red per rule | AC-1.5 | hermetic | `tests/units.test.sh` §DEBT → the cap refusal, the per-file refusal and the count line each red when their rule is removed in a fixture copy | one of the three planted removals stays green |
| REQ-2 | the sweep, the door and the fold over fixtures | AC-2.1 | hermetic | `tests/shell-lint.test.sh` §EXIT-2 → a planted `die "REFUSED — x"` with no exit is named; a planted `refuse` call passes | the sweep's naming line is removed |
| REQ-2 | the sweep, the door and the fold over fixtures | AC-2.2 | hermetic | `tests/shell-lint.test.sh` §EXIT-1 → the real tree prints nothing against `tests/lib/refusal-exits.ceiling`; against `/dev/null` a named site; the three named walls are not in the sweep's output | the ceiling is raised by one for a file, or one of the three walls loses its exit |
| REQ-2 | the sweep, the door and the fold over fixtures | AC-2.3 | hermetic | `tests/refuse.test.sh` §NEEDS → `refuse exit2 v fact 'needs: Person A — why'` with a bound plan appends `line/v1\|ev=refusal\|needs=person\|wall=v` | the event write is removed |
| REQ-2 | the sweep, the door and the fold over fixtures | AC-2.4 | hermetic | `tests/landing-line-2.test.sh` §NEEDS → one refusal event in the window prints `needs-you=1` and `total=1` | the field is left out of the sum |
| REQ-3 | the verb and the fold over a fixture plan | AC-3.1 | hermetic | `tests/session-poker-5.test.sh` §RETIER → after `matrix-retier AC-2.1 tier=T2 eval=…` the cell, the `eval:` line and the Eval design row read T2 and the text, status pending, no `waiver:`, `ev=matrix-retier` appended | one of the three places keeps T1 |
| REQ-3 | the verb and the fold over a fixture plan | AC-3.2 | hermetic | `tests/session-poker-5.test.sh` §RETIER → `tier=T1` on a T2 cell is refused, rc≠0, the plan unchanged | the comparison is inverted |
| REQ-3 | the verb and the fold over a fixture plan | AC-3.3 | hermetic | `tests/landing-line-2.test.sh` §RETIER → a retier event moves nothing; a `waiver:` line adds one | the fold counts `ev=matrix-retier` |
| REQ-4 | the close's own line | AC-4.1 | live | `session-poker.sh landing-report --hand-holds <this plan>` at delivered → `hand-holds: total=0 … needs-you=0` | any field above zero |
| REQ-5 | one judge renders the line; two refusals go | AC-5.1 | hermetic | `tests/canonical-sdlc-evidence-gate-2.test.sh` §WHOLE-RUN → a head one landing past the proof runs; the proof's own head is refused "runs once at a head" | the same-head refusal is dropped with the other two |
| REQ-5 | one judge renders the line; two refusals go | AC-5.2 | hermetic | `tests/session-poker-4.test.sh` §STACK → `proof_health_line` prints `green` only at the proof's head with no owed; `red` past it | the function prints green for a covered later head |
| REQ-5 | one judge renders the line; two refusals go | AC-5.3 | hermetic | `tests/landing-line-1.test.sh` §HEALTH → after a landing greens one owed suite the line's `owed=` drops it and still reads `red` | the settlement skips the rewrite |
| REQ-6 | the tick over a fixture roster, and the fold | AC-6.1 | hermetic | `tests/session-poker-4.test.sh` §STARTER → a tick with no row ready, none running, head past the proof prints `poker: regression-run started regression@<h8>` and the roster holds the detached object | the branch's quiet condition is inverted |
| REQ-6 | the tick over a fixture roster, and the fold | AC-6.2 | hermetic | `tests/session-poker-4.test.sh` §STARTER → a fix row landed past the proof, next tick starts again at the new head | the head comparison reads the proof's head |
| REQ-6 | the tick over a fixture roster, and the fold | AC-6.3 | hermetic | `tests/session-poker-4.test.sh` §STARTER → the started verb's run writes `proved: kind=regression head=<new>` through proof-add | the detached call drops `proof-add` |
| REQ-6 | the tick over a fixture roster, and the fold | AC-6.4 | hermetic | `tests/landing-line-2.test.sh` §STARTER → two `ev=run starter=tick` passes read `second-regressions=0`; one `starter=person` reads 1 | the fold ignores `starter=` |
| REQ-7 | one judge behind the card, the gate and the printers | AC-7.1 | hermetic | `tests/card.test.sh` §UNPROVED → `whole suite: red at <h8>, 2 landings before this head`; over a green fixture `whole suite: green at <h8>` | the card prints green over the red fixture |
| REQ-7 | one judge behind the card, the gate and the printers | AC-7.2 | hermetic | `tests/card.test.sh` §UNPROVED → the red fixture's card carries `approve:merge-unproved`; `current 8 --check` refuses unreplied and passes after `reply` | the ask is drawn but `facts_state` passes without it |
| REQ-7 | one judge behind the card, the gate and the printers | AC-7.3 | hermetic | `tests/proof-at-head.test.sh` §ONE → the card, `current 8 --check` and close-out's pre-flight print one state over one fixture | one reader keeps its own computation |
| REQ-7 | one judge behind the card, the gate and the printers | AC-7.4 | hermetic | `tests/sitrep.test.sh` §WHOLE → over a proof line with `owed=` the correctness line reads `red at <h8>`; `tests/close-out-3.test.sh` §REG → the continuation's line reads the same | `sitrep_whole` prints green for any proof line |
| REQ-8 | one verb over a walk record, run by the landing | AC-8.1 | hermetic | `tests/session-poker-4.test.sh` §WALK → a walk record with `\| AC \| verdict \| why \|` and one `verdict:` line parses; one without is refused naming the shape | the parser accepts a record with no table |
| REQ-8 | one verb over a walk record, run by the landing | AC-8.2 | hermetic | `tests/session-poker-4.test.sh` §WALK → CONFIRMED rows read `discharged` with the record as evidence, a REFUTED row stays pending, `walk-artifact:` is set, `ev=walk` appended, no `ev=matrix-set` | the pointer write is split out and skipped |
| REQ-8 | one verb over a walk record, run by the landing | AC-8.3 | hermetic | `tests/spawn-worktree.test.sh` §WALK → `ready` on a verify row whose artifact is the walk record lands it and the plan shows the rows discharged | the artifact check is removed and ready lands without settling |
| REQ-9 | one function over a fixture register with rounds | AC-9.1 | hermetic | `tests/sitrep.test.sh` §ROUNDS → four decide rounds after the plan card print `human stops (autonomous half): 5` with the card | puts are read from `approved:` lines again |
| REQ-9 | one function over a fixture register with rounds | AC-9.2 | hermetic | `tests/sitrep.test.sh` §ROUNDS → a round opened 23:36Z answered 07:32Z adds 476; a re-put key keeps both rounds | `owed_open` replaces the earlier round |
| REQ-9 | one function over a fixture register with rounds | AC-9.3 | hermetic | `tests/close-out-3.test.sh` §SCORE → close-out's `## Scorecard` equals `landing-report --scorecard` over the same fixture | close-out formats its own numbers |
| REQ-10 | the section rewritten, with a red | AC-10.1 | hermetic | `tests/canonical-sdlc-evidence-gate-2.test.sh` Section 33 → describes the owing-step rule; `/usr/bin/grep -c "T0-only" tests/canonical-sdlc-evidence-gate-2.test.sh` → 0 | the old header text survives |
| REQ-10 | the section rewritten, with a red | AC-10.2 | hermetic | Section 33b → `expect_allow` on the deferred row; with the owing-step rule reverted in a fixture copy of walls.sh, red | 33b still asserts nothing |
| REQ-11 | OC-1's own red | AC-11.1 | hermetic | `tests/close-out-4.test.sh` §OC-1b → the dry run with the matrix arm disabled in a fixture copy prints a refusal and the test is red | the fixture flips nothing |
| REQ-12 | the parts from a fixture worktree | AC-12.1 | hermetic | `tests/session-poker-5.test.sh` §PARTS → `known-limits-part` run from a fixture worktree commits CHANGELOG.md there, the working branch untouched | the verb reads `refs/heads/<wb>` again |
| REQ-12 | the parts from a fixture worktree | AC-12.2 | hermetic | `tests/session-poker-5.test.sh` §PARTS → the landing record's part line carries `tree=<the worktree>` | the event names the working branch |

## Tasks

| id | step | kind | task | agent | deps | size | serves | Files | worktree | base | status | suites | lands-on | artifact |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| T1 | 4 | build | The cap caps scope. A defect the wave made, the wave fixes, so the cap counts only the rows a review adds beyond them. task-add exempts a born row whose rating is inside fix-policy and counts a promoted or carried one, prints exempt under fix-policy or counted n of cap, and the cap refusal names its exit; units_born reports the policy test; the cap, per-file and count-line pins the tree lacked are written first, red (D1, D8, D10; AC-1.1, AC-1.2, AC-1.3, AC-1.5). complexity: complex | w46-T1 | — | 60 | REQ-1 | hooks/poker/plan.sh, payload/scripts/lib/units.sh, payload/scripts/lib/line.sh, tests/session-poker-5.test.sh, tests/units.test.sh, tests/CENSUS.md | .worktrees/46-T1 | 6e4604b8 | landed | — | — | — |
| T2 | 4 | build | The registry list in code. The files every test row must touch live in one constant the cap and the census test both read. REGISTRY_FILES in lib/units.sh names tests/CENSUS.md; the per-file cap skips a path in it; shell-lint's census arm reads the constant (D9; AC-1.4). complexity: standard | w46-T2 | — | 30 | REQ-1 | payload/scripts/lib/units.sh, hooks/poker/plan.sh, tests/shell-lint.test.sh, tests/session-poker-5.test.sh, tests/CENSUS.md | .worktrees/46-T2 | 9893ed5b | landed | — | — | — |
| T3 | 4 | build | The refusal door logs a need. A refusal that needs a person is an event on the landing record. refuse() reads a fix opening needs: person and appends a refusal event (ev=refusal needs=person wall=verb) to the bound plan's record through line_event, nothing when no plan is bound (D10; AC-2.3). complexity: standard | w46-T3 | — | 40 | REQ-2 | payload/scripts/lib/refuse.sh, payload/scripts/lib/line.sh, tests/refuse.test.sh, tests/CENSUS.md | .worktrees/46-T3 | de0039e9 | landed | — | — | — |
| T4 | 4 | build | The pin ratchets per file. New refusals cannot ship without an exit and the old ones burn down from a ceiling. shell-lint §EXIT sweeps die REFUSED, refused and refuse sites under hooks/ and payload/scripts/, excuses a site whose text or pv_next line names a script verb, a listed verb word or needs:, counts the rest per file against tests/lib/refusal-exits.ceiling, refuses above naming the site and below naming the new number; the Verify gate's live-row refusal, the cap refusal and the release card's waiver line get exits by name (D2, D10; AC-2.1, AC-2.2). complexity: complex | w46-T4 | T1 | 90 | REQ-2 | tests/shell-lint.test.sh, tests/lib/refusal-exits.ceiling, payload/scripts/lib/walls.sh, hooks/poker/plan.sh, payload/scripts/card.sh, tests/CENSUS.md | .worktrees/46-T4 | eb9a83dd | landed | — | — | — |
| T5 | 4 | build | Needs-you joins the total. A refusal the person had to answer is a hand-hold. hand_holds_report counts refusal events with needs=person in the window as needs-you and adds it to total; the header comment names the thirteen printed fields with a pin that the two agree, the second-floors drift fixed (D11; AC-2.4). complexity: standard | w46-T5 | — | 40 | REQ-2, REQ-4 | hooks/poker/line.sh, tests/landing-line-2.test.sh, tests/landing-line-1.test.sh, tests/close-out-3.test.sh, tests/close-out-4.test.sh, tests/CENSUS.md | .worktrees/46-T5 | de0039e9 | landed | landing-line-2.test.sh, landing-line-1.test.sh, close-out-3.test.sh, close-out-4.test.sh | landing-line-2.test.sh, landing-line-1.test.sh, close-out-3.test.sh, close-out-4.test.sh | — |
| T6 | 4 | build | Retier rewrites three. Raising a tier is one verb that rewrites every place the tier lives and resets the row. matrix-retier AC tier= eval= refuses a tier at or below, rewrites the tier cell, the eval: line and the plan's Eval design row, sets pending, clears evidence, auditor and waiver:, appends ev=matrix-retier and a ledger Δ line; the fold ignores the event (D12; AC-3.1, AC-3.2, AC-3.3). complexity: complex | w46-T6 | — | 90 | REQ-3 | hooks/poker/plan.sh, hooks/session-poker.sh, hooks/poker/sitrep.sh, hooks/poker/line.sh, tests/session-poker-5.test.sh, tests/landing-line-2.test.sh, tests/CENSUS.md | .worktrees/46-T6 | 284b93cc | landed | — | — | — |
| T7 | 4 | build | Health is a rendering. The health line is a rendering of the judge, rewritten by every writer through one function. proof_health_line plan repo in lib/proof.sh prints green only at the proof's head with nothing owed and red with the suites still owed otherwise; proof-add regression writes it and line_settle rewrites it at every landing (D6; AC-5.2, AC-5.3). complexity: complex | w46-T7 | — | 75 | REQ-5 | payload/scripts/lib/proof.sh, hooks/poker/proof.sh, payload/scripts/lib/line.sh, tests/session-poker-4.test.sh, tests/landing-line-1.test.sh, tests/CENSUS.md | .worktrees/46-T7 | b69ac4a3 | landed | — | — | — |
| T8 | 4 | build | Two refusals go, one stays. A full pass is refused only at a head that already has one. regression-run drops the covered-head and whole-run-behind refusals, keeps the same-head one, writes starter=tick, orchestrator or person on its run event; the fold counts second-regressions for starter=person only; the seven pinned rows are rewritten and the stale inventory line removed (D16; AC-5.1, AC-6.4). complexity: complex | w46-T8 | — | 75 | REQ-5, REQ-6 | hooks/poker/proof.sh, payload/scripts/lib/proof.sh, hooks/poker/line.sh, tests/canonical-sdlc-evidence-gate-2.test.sh, tests/units.test.sh, tests/landing-line-2.test.sh, tests/fixtures/refusal-inventory.md, tests/CENSUS.md | .worktrees/46-T8 | b69ac4a3 | landed | — | — | — |
| T9 | 4 | build | One judge, one printer. Every surface prints the full pass's state from the one judge the gates read. proof_whole_text over proof_state replaces sitrep_whole and co_regression_text; the release card prints whole suite: green at h8, or red at h8 with the landings before this head counted; tests/proof-at-head.test.sh §ONE holds the card, current 8 --check and close-out's pre-flight to one state (D4, D14; AC-7.1, AC-7.3, AC-7.4). complexity: complex | w46-T9 | — | 90 | REQ-7 | payload/scripts/lib/proof.sh, hooks/poker/plan.sh, hooks/poker/sitrep.sh, payload/scripts/close-out.sh, payload/scripts/card.sh, tests/card.test.sh, tests/sitrep.test.sh, tests/close-out-3.test.sh, tests/proof-at-head.test.sh, tests/CENSUS.md | .worktrees/46-T9 | b69ac4a3 | landed | — | — | — |
| T10 | 4 | build | Merge unproved is an ask. When the pass is not green at this head the card asks the merge as its own approval. release-approval adds the decision approve:merge-unproved, reply writes approved: merge-unproved by who ISO head=h40, facts_state passes the regression fact on green at head or that line at the same head, current 8 and close-out read it (D14; AC-7.2). complexity: complex | w46-T10 | T9 | 75 | REQ-7 | hooks/poker/plan.sh, payload/scripts/lib/proof.sh, payload/scripts/card.sh, payload/scripts/close-out.sh, tests/card.test.sh, tests/release-approval.test.sh, tests/rehearsal-release-waiting.test.sh, tests/CENSUS.md | .worktrees/46-T10 | 668547a5 | landed | — | — | — |
| T11 | 4 | build | The walk is a proof kind. The walk's verdicts are registered like the critic's and the landing settles the cells they confirm. proof-add walk record parses with proof_verdicts, writes discharged and evidence for CONFIRMED rows no landing settled, writes walk-artifact: and the head line in one transaction, appends ev=walk; ready on a verify row whose artifact is the walk record runs it at landing (D13; AC-8.1, AC-8.2, AC-8.3). complexity: complex | w46-T11 | — | 75 | REQ-8 | hooks/poker/proof.sh, hooks/session-poker.sh, payload/scripts/spawn-worktree.sh, payload/scripts/lib/worktree.sh, tests/session-poker-4.test.sh, tests/spawn-worktree.test.sh, tests/CENSUS.md | .worktrees/46-T11 | 3038b1f9 | landed | — | — | — |
| T12 | 4 | build | The register is the clock. Stops and waiting are read from the register of what the run owed the person, every round kept. owed_open on an answered key adds a round; scorecard_report counts step cards answered plus decide rounds put after approved-by and sums at minus opened per round; approve closes approve:step3 at the approval instant (D7, D15; AC-9.1, AC-9.2, AC-9.3). complexity: complex | w46-T12 | — | 75 | REQ-9 | payload/scripts/lib/owed.sh, hooks/poker/sitrep.sh, hooks/poker/plan.sh, tests/sitrep.test.sh, tests/asks.test.sh, tests/close-out-3.test.sh, tests/CENSUS.md | .worktrees/46-T12 | 623257f8 | landed | — | — | — |
| T13 | 4 | build | The tick starts the pass. The tick starts the full regression itself when the roster is quiet and the head has moved. When no row is ready, none running and the head is past the last proof, or a fix row landed past it, the tick starts regression-run detached through booked.sh --detach as the roster object regression@h8 with run.sh its one suite, admitted by the gate alone; the proof lands through proof-add as today (D5; AC-6.1, AC-6.2, AC-6.3). complexity: complex | w46-T13 | T7, T8 | 90 | REQ-6 | hooks/poker/tick.sh, payload/scripts/booked.sh, payload/scripts/lib/gate.sh, hooks/poker/proof.sh, tests/session-poker-4.test.sh, tests/gate.test.sh, tests/CENSUS.md | .worktrees/46-T13 | 98eb8b58 | landed | — | — | — |
| T14 | 4 | build | Section 33 reads the new rule. The stale section describes the rule that landed and its fixture asserts something. Section 33 of evidence-gate-2 is rewritten to the owing-step rule, 33b expects allow on the deferred row and is red with the rule reverted in a fixture copy (D18; AC-10.1, AC-10.2). complexity: standard | w46-T14 | — | 30 | REQ-10 | tests/canonical-sdlc-evidence-gate-2.test.sh, tests/CENSUS.md | .worktrees/46-T14 | 011d42e2 | landed | — | — | — |
| T15 | 4 | build | OC-1 has a red of its own. The dry run's refusal on a close-owed row is shown red by its own fixture. close-out-4 §OC-1b disables the matrix arm in a fixture copy and expects the dry run to refuse (D18; AC-11.1). complexity: standard | w46-T15 | — | 30 | REQ-11 | tests/close-out-4.test.sh, tests/CENSUS.md | .worktrees/46-T15 | a5bf5eb5 | landed | — | — | — |
| T16 | 4 | build | The parts render here. The release-entry parts write in the checkout they run from. known-limits-part and reviews-part read and commit CHANGELOG.md at the HEAD of the checkout the verb runs from, move the working branch only from its own checkout, and the part event carries tree= (D17; AC-12.1, AC-12.2). complexity: complex | w46-T16 | — | 60 | REQ-12 | hooks/poker/line.sh, payload/scripts/lib/line.sh, tests/session-poker-5.test.sh, tests/CENSUS.md | .worktrees/46-T16 | c684231a | landed | — | — | — |
| T17 | 5 | verify | The walk settles its cells. The walk reads the release card, the continuation and the scorecard over this run and over wave 45's record and writes a verdict table. record/wave-46-asks-nothing/walk.md with the critic's table shape and one verdict: line; its landing runs proof-add walk (D13). | w46-T17 | T1, T2, T3, T4, T5, T6, T7, T8, T9, T10, T11, T12, T13, T14, T15, T16, T22, T23, T24, T25, T26, T27, T28 | 60 | REQ-8 | record/wave-46-asks-nothing/walk.md | — | — | landed | — | — | record/wave-46-asks-nothing/walk.md |
| T18 | 6 | review | The critic reads the whole. One critic holds evidence, adversarial and structure over the settled head. Three records under record/wave-46-asks-nothing, one per question, registered by proof-add review. | w46-T18 | T1, T2, T3, T4, T5, T6, T7, T8, T9, T10, T11, T12, T13, T14, T15, T16, T22, T23, T24, T25, T26, T27, T28, T29 | 60 | REQ-4 | record/wave-46-asks-nothing/critic-evidence.md, record/wave-46-asks-nothing/critic-adversarial.md, record/wave-46-asks-nothing/critic-structure.md | — | — | landed | — | — | record/wave-46-asks-nothing/critic-evidence.md |
| T19 | 7 | doc | ADR-074 and the entry. The merge rule is recorded and the 1.29.0 entry is rendered from the plan. ADR-074, green means the whole suite ran here, promoted to docs/adrs; the CHANGELOG entry with known-limits-part and reviews-part run from this row's tree (D4, D17). | w46-T19 | T16, T22, T23, T24, T25, T26, T27, T28, T29 | 45 | REQ-5, REQ-7 | .bionic/docs/adrs/epic-23-bionic-tech-debt/adr-074-green-means-the-whole-suite-ran-here.md, docs/adrs/adr-074-green-means-the-whole-suite-ran-here.md, CHANGELOG.md, payload/.claude-plugin/plugin.json, payload/commands/help.md, payload/commands/version.md, payload/integrity/rendered.sha256, tests/release-check.test.sh, .bionic/docs/record/wave-46-asks-nothing/T19.md | .worktrees/46-T19 | 5a08f601 | landed | release-check.test.sh | release-check.test.sh | — |
| T20 | 8 | integrate | The pull request. The wave branch is pushed and the pull request opened once the pass at the head is green or the merge is approved unproved. reviews-part, push, gh pr create --base main (D4, D14). | — | T19, T31 | 30 | REQ-7 | CHANGELOG.md | — | — | landed | — | — | — |
| T21 | 9 | close | The close reads zero. The close-out reads its own measure at zero. Release card, delivered:, continuation.md; hand-holds total zero and needs-you zero (AC-4.1). | — | T20 | 30 | REQ-4 | record/wave-46-asks-nothing/continuation.md | — | — | landed | — | — | record/wave-46-asks-nothing/continuation.md |
| T22 | 4 | build | The pins T6 and T16 left. Two exact-string pins, one wall list and three refusals read the lines as they are written now. landing-line-1 k6 and close-out-4 BP-5 gain the tree= field before at= in the part event line; the writer wall list at walls.sh:5410 names matrix-retier beside matrix-set with its pin in bash-walls.test.sh; the three plan.sh refusals T6 added without an exit name one, so shell-lint §EXIT reads plan.sh at its ceiling of 148 again; red first at the head (D2, D12, D17; AC-2.2, AC-12.2). complexity: standard | w46-T22 | — | 30 | REQ-12 | tests/landing-line-1.test.sh, tests/close-out-4.test.sh, payload/scripts/lib/walls.sh, tests/bash-walls.test.sh, hooks/poker/plan.sh, tests/lib/refusal-exits.ceiling, tests/shell-lint.test.sh, tests/CENSUS.md | .worktrees/46-T22 | 623257f8 | landed | — | — | — |
| T23 | 4 | build | Unproved reads the release. The approve verb admits merge-unproved where units_approval_names prints release, the name it derives for an open integrate row behind the release doc row and the only approval name this plan reads; the approval:merge key no row of any plan reads is dropped, so the card ask D14 puts can be answered by reply; red first: on a plan with an integrate row approve merge-unproved writes the line, on one without it is refused (D14; AC-7.1). complexity: standard | w46-T23 | — | 20 | REQ-7 | hooks/poker/proof.sh, tests/release-approval.test.sh, tests/card.test.sh, tests/CENSUS.md | .worktrees/46-T23 | 011d42e2 | landed | release-approval.test.sh, card.test.sh | release-approval.test.sh, card.test.sh | — |
| T24 | 4 | build | AH-1 reads the merge rule. The evidence-gate-2 row AH-1 pins the covered-by-landings reading D4 retired, so it stands red at the head since T10 landed; it is rewritten to the landed rule: the same world (approved head A, working head A, whole run at H, C fixed on its suites) refuses current 8 --check as regression unproved naming both exits, and with approved: merge-unproved at A planted it passes; red first (D4, D14; AC-7.1). complexity: standard | w46-T24 | — | 20 | REQ-7 | tests/canonical-sdlc-evidence-gate-2.test.sh, tests/CENSUS.md | .worktrees/46-T24 | a5bf5eb5 | landed | canonical-sdlc-evidence-gate-2.test.sh | canonical-sdlc-evidence-gate-2.test.sh | — |
| T25 | 4 | build | The rehearsal reads D4. The rehearsal worlds and the close replay reach Step 8 under the landed rule: a world whose last landing follows its whole run either carries the pass at its final head or replies merge on the release card through the verbs, so rehearsal-failed-review FR-1 and FA-5 and close-replay CL-1 and the sections behind it read the landed rule instead of the covered-by-landings reading D4 retired; red first (D4, D14; AC-7.1). complexity: complex · born: regression | w46-T25 | — | 60 | REQ-7 | tests/lib/rehearsal.sh, tests/lib/rehearsal-read.sh, tests/rehearsal-failed-review.test.sh, tests/close-replay.test.sh, tests/CENSUS.md | .worktrees/46-T25 | 402980ec | landed | rehearsal-failed-review.test.sh, close-replay.test.sh, rehearsal-release-waiting.test.sh | rehearsal-failed-review.test.sh, close-replay.test.sh, rehearsal-release-waiting.test.sh | — |
| T26 | 4 | build | VG-5b and AW-2 read the rules. The row VG-5b pins the covered reading D4 retired (two prose commits after the approval admit current 8) and is rewritten to the landed rule with a planted approved: merge-unproved twin, as T24 did for AH-1; AW-2 reads the register T12 built: a second refusal on the same open failing question must open no new round, so either the pin or owed_open is wrong and the red decides which; red first (D4, D7, D14; AC-7.1, AC-9.1). complexity: complex · born: regression | w46-T26 | — | 45 | REQ-7,REQ-9 | tests/session-poker-4.test.sh, payload/scripts/lib/owed.sh, tests/asks.test.sh, tests/CENSUS.md | .worktrees/46-T26 | 402980ec | landed | session-poker-4.test.sh, asks.test.sh | session-poker-4.test.sh, asks.test.sh | — |
| T27 | 4 | build | The door card is proved. Door-card c36, m0 and m2c expect the replay table to put approve:release and approve:merge, and the card now adds approve:merge-unproved because the fixture end state has landings past its whole run; the fixture carries the pass at its end head as a delivered run would, or where it cannot, the pins gain the third decision with the reason written; red first (D4, D14; AC-7.1). complexity: standard · born: regression | w46-T27 | — | 30 | REQ-7 | tests/door-card.test.sh, tests/lib/world.sh, tests/CENSUS.md | .worktrees/46-T27 | 402980ec | landed | door-card.test.sh | door-card.test.sh | — |
| T28 | 4 | build | A word and an anchor. The words suite refuses the word reader on hooks/poker/proof.sh:180, a string T11 wrote, which is reworded to name the library; regression-rename anchors on the dispatch line regression-run) of session-poker.sh, which T8 reshaped, so the anchor follows the shipped line and its mutation reads the real file again; red first (AC-2.2). complexity: standard · born: regression | w46-T28 | — | 20 | REQ-2 | hooks/poker/proof.sh, tests/regression-rename.test.sh, tests/words.test.sh, tests/CENSUS.md | .worktrees/46-T28 | 5be5879d | landed | words.test.sh, regression-rename.test.sh | words.test.sh, regression-rename.test.sh | — |
| T29 | 4 | build | The walk gate reads the walk. A walk record registered by proof-add walk carries the verdict table D13 requires, so the Step-5 walk gate's AC-identifier arm in walls.sh validate_walk_artifact yields to a record a proved: kind=walk line names and stands for an unregistered one, the doctrine line in steps/5.md re-rendered, a two-way pin in the gate suite; red first (D13; AC-8.2). complexity: complex | w46-T29 | T17 | 30 | REQ-8 | payload/scripts/lib/walls.sh, agents-src/templates/skills/canonical-sdlc/steps/5.md.tmpl, skills/canonical-sdlc/steps/5.md, payload/integrity/rendered.sha256, tests/canonical-sdlc-evidence-gate.test.sh, tests/CENSUS.md, .bionic/docs/record/wave-46-asks-nothing/T29-report.md | .worktrees/46-T29 | 837ddc39 | landed | canonical-sdlc-evidence-gate.test.sh,canonical-sdlc-evidence-gate-2.test.sh,close-out-3.test.sh | canonical-sdlc-evidence-gate.test.sh,canonical-sdlc-evidence-gate-2.test.sh,close-out-3.test.sh | — |
| T30 | 6 | review | The critic reads the fix. A fresh critic reads the piece from the whole read's head to T29's landing with the three questions, its evidence record re-judging AC-8.3 and the wave verdict at the head the walk gate accepts, so the release card asks the release alone (D13; AC-8.3). complexity: complex | w46-T30 | T29 | 30 | REQ-8 | record/wave-46-asks-nothing/critic-evidence-2.md, record/wave-46-asks-nothing/critic-adversarial-2.md, record/wave-46-asks-nothing/critic-structure-2.md | — | — | landed | — | — | record/wave-46-asks-nothing/critic-evidence-2.md |
| T31 | 4 | build | The render owns the close row. A criterion the close proves, its eval naming landing-report --hand-holds as matrix_close_rows reads it, takes the close row among the rows serving its requirement when matrix-render writes its task: key, so the close's live row is never left pending for a hand to repair; red first (D19; AC-4.1). complexity: complex | w46-T31 | T29 | 30 | REQ-4 | hooks/session-poker.sh, tests/session-poker-4.test.sh, tests/CENSUS.md, .bionic/docs/record/wave-46-asks-nothing/T31-report.md | .worktrees/46-T31 | e38e7518 | landed | session-poker-4.test.sh,landing-line-1.test.sh,landing-line-2.test.sh | session-poker-4.test.sh,landing-line-1.test.sh,landing-line-2.test.sh | — |
| T33 | 6 | review | The critic reads the fix row. A fresh critic reads the piece from the last read's head to T31's landing with the three questions, so the chains stay covered past a row born of a ruling and not of a finding (D19; REQ-4). complexity: complex | w46-T33 | T31 | 30 | REQ-4 | record/wave-46-asks-nothing/critic-evidence-3.md, record/wave-46-asks-nothing/critic-adversarial-3.md, record/wave-46-asks-nothing/critic-structure-3.md | — | — | landed | — | — | record/wave-46-asks-nothing/critic-evidence-3.md |
| T32 | 7 | doc | The numbers render again. The 1.29.0 entry's landing numbers are rendered once more by release-note at the head T31 and T33 leave and pasted verbatim, so the release check's fourth rule holds at the final head (D17; REQ-7). complexity: standard | — | T31, T33 | 15 | REQ-7 | CHANGELOG.md, .bionic/docs/record/wave-46-asks-nothing/T32.md | — | — | dropped | release-check.test.sh | release-check.test.sh | — |
| T34 | 7 | doc | The entry names the render fix. The 1.29.0 entry gains T31's Migration bullet, its walk-regression-critic section counts the four passes and the three critic reads, and its close paragraph says that T31's landing moved the hand-holds window past the run's one counted task write, so the entry describes the release that ships (D19; REQ-7). complexity: standard | w46-T34 | T33 | 15 | REQ-7 | CHANGELOG.md, .bionic/docs/record/wave-46-asks-nothing/T34.md | .worktrees/46-T34 | 6b7563af | landed | release-check.test.sh | release-check.test.sh | — |
| T35 | 7 | doc | The numbers render again. The 1.29.0 entry's landing numbers are rendered once more by release-note at the head T34 left and pasted verbatim, so the release check's fourth rule holds at the final head (D17; REQ-7). complexity: standard | w46-T35 | T34 | 15 | REQ-7 | CHANGELOG.md, .bionic/docs/record/wave-46-asks-nothing/T35.md | .worktrees/46-T35 | b9399de3 | landed | release-check.test.sh | release-check.test.sh | — |

## Verification Matrix

stack-health: green head=6b7563afb608fccbdcf93beaff95655b086f2d77 pass=127 total=127 evidence=record/wave-46-asks-nothing/regression-run-6b7563afb608fccbdcf93beaff95655b086f2d77.log
auditor-wave: CONFIRMED — the piece adds no requirement or criterion, REQ-4 runs from D11 and the ruling D19 to AC-4.1 and its live reading at delivered, T31's render change is proved red then green on its own row (CT-1 red at base, session-poker-4 green at 6b7563af in the landing's log and in my re-run), the rows it reaches through serves_load are green at the landing, and the whole run at this head is 127 of 127; AC-4.1 stays owed at Step 9, and its zero cannot tell a fixed cause from the window moving past the write
walk-artifact: record/wave-46-asks-nothing/walk.md

| AC | tier | status | evidence | auditor |
|---|---|---|---|---|
| AC-1.1 | T2 | discharged | — | CONFIRMED |
| AC-1.2 | T2 | discharged | — | CONFIRMED |
| AC-1.3 | T2 | discharged | — | CONFIRMED |
| AC-1.4 | T2 | discharged | — | CONFIRMED |
| AC-1.5 | T2 | discharged | — | CONFIRMED |
| AC-2.1 | T2 | discharged | — | CONFIRMED |
| AC-2.2 | T2 | discharged | — | CONFIRMED |
| AC-2.3 | T2 | discharged | — | CONFIRMED |
| AC-2.4 | T2 | discharged | — | CONFIRMED |
| AC-3.1 | T2 | discharged | — | CONFIRMED |
| AC-3.2 | T2 | discharged | — | CONFIRMED |
| AC-3.3 | T2 | discharged | — | CONFIRMED |
| AC-4.1 | T3 | blocked | record/wave-46-asks-nothing/continuation.md | UNVERIFIABLE |
| AC-5.1 | T2 | discharged | — | CONFIRMED |
| AC-5.2 | T2 | discharged | — | CONFIRMED |
| AC-5.3 | T2 | discharged | — | CONFIRMED |
| AC-6.1 | T2 | discharged | — | CONFIRMED |
| AC-6.2 | T2 | discharged | — | CONFIRMED |
| AC-6.3 | T2 | discharged | — | CONFIRMED |
| AC-6.4 | T2 | discharged | — | CONFIRMED |
| AC-7.1 | T2 | discharged | — | CONFIRMED |
| AC-7.2 | T2 | discharged | — | CONFIRMED |
| AC-7.3 | T2 | discharged | — | CONFIRMED |
| AC-7.4 | T2 | discharged | — | CONFIRMED |
| AC-8.1 | T2 | discharged | — | CONFIRMED |
| AC-8.2 | T2 | discharged | — | CONFIRMED |
| AC-8.3 | T2 | discharged | record/wave-46-asks-nothing/line/T11-session-poker-4-623257f87bb7.log | CONFIRMED |
| AC-9.1 | T2 | discharged | — | CONFIRMED |
| AC-9.2 | T2 | discharged | — | CONFIRMED |
| AC-9.3 | T2 | discharged | record/wave-46-asks-nothing/line/T22-close-out-4-de0039e9bf84.log | CONFIRMED |
| AC-10.1 | T2 | discharged | record/wave-46-asks-nothing/walk.md | CONFIRMED |
| AC-10.2 | T2 | discharged | record/wave-46-asks-nothing/walk.md | CONFIRMED |
| AC-11.1 | T2 | discharged | record/wave-46-asks-nothing/walk.md | CONFIRMED |
| AC-12.1 | T2 | discharged | — | CONFIRMED |
| AC-12.2 | T2 | discharged | — | CONFIRMED |

AC-1.1: A row `task-add` adds from a review finding whose rating is inside `fix-policy:` (at this run, S1 and S2 with reach on: the wave's own defect, in what it ships) is exempt from `fix-cap:` and lands however many such rows the review raised.
  provenance: charter Theme 1 item 1.1; wave 45 D31 and continuation ("Fix-cap 2 at single rigor stopped the run twice")
  fails-when: the policy test is removed from the cap's count
  eval: T2 — `tests/session-poker-5.test.sh` §EXEMPT → a third `born: review S2 on` row lands on `fix-cap: 2`, rc=0
  task: pending
  evidence: record/wave-46-asks-nothing/line/T2-session-poker-5-011d42e2fb7b.log
AC-1.2: A review-born row whose rating is outside `fix-policy:` (an S3 the person promotes, an S2 with reach off, a carried finding adopted) counts against `fix-cap:` as before.
  provenance: charter Theme 1 item 1.1; wave 45 D31 and continuation ("Fix-cap 2 at single rigor stopped the run twice")
  fails-when: the promoted marker is dropped and the S3 row lands
  eval: T2 — `tests/session-poker-5.test.sh` §EXEMPT → a third `born: review S3 on` row is refused on `fix-cap: 2`, the text names `counted 2 of 2`
  task: pending
  evidence: record/wave-46-asks-nothing/line/T2-session-poker-5-011d42e2fb7b.log
AC-1.3: `task-add` prints, on the row it adds, which count it applied: exempt under `fix-policy:`, or counted `<n> of <cap>`.
  provenance: charter Theme 1 item 1.1; wave 45 D31 and continuation ("Fix-cap 2 at single rigor stopped the run twice")
  fails-when: the suffix is deleted from the success line
  eval: T2 — `tests/session-poker-5.test.sh` §EXEMPT → the born line ends `exempt under fix-policy: S1,S2-on` for S2 on, `counted 1 of 2` for S3
  task: pending
  evidence: record/wave-46-asks-nothing/line/T2-session-poker-5-011d42e2fb7b.log
AC-1.4: The per-file cap ("a fourth fix on <file>") does not count a file the census rule names as one every test row must touch, the rule being named where the cap can read it.
  provenance: charter Theme 1 item 1.1; wave 45 D31 and continuation ("Fix-cap 2 at single rigor stopped the run twice")
  fails-when: `REGISTRY_FILES` is emptied
  eval: T2 — `tests/session-poker-5.test.sh` §REGISTRY → a fourth review-born row whose Files name `tests/CENSUS.md` lands
  task: pending
  evidence: record/wave-46-asks-nothing/line/T2-session-poker-5-011d42e2fb7b.log
AC-1.5: The cap refusal, the per-file refusal and the count line each have a test that is red when its rule is removed; none has one today (research-theme1 §1.1).
  provenance: charter Theme 1 item 1.1; wave 45 D31 and continuation ("Fix-cap 2 at single rigor stopped the run twice")
  fails-when: one of the three planted removals stays green
  eval: T2 — `tests/units.test.sh` §DEBT → the cap refusal, the per-file refusal and the count line each red when their rule is removed in a fixture copy
  task: pending
  evidence: record/wave-46-asks-nothing/line/T1-units-eb9a83ddeacf.log
AC-2.1: A static pin over the refusal texts, in the shape of shell-lint's §BP pipe pin with its allow file, refuses a REFUSED text that names neither a verb an agent may run nor `needs: <person> — <why>`. A `refuse()` call site names its exit in its fix argument and passes by shape.
  provenance: charter Theme 1 item 1.2; wave 45 handoff open question 4 and D29 ("We need to automate the meta-harness so I don't need to intervene when it's unnecessary")
  fails-when: the sweep's naming line is removed
  eval: T2 — `tests/shell-lint.test.sh` §EXIT-2 → a planted `die "REFUSED — x"` with no exit is named; a planted `refuse` call passes
  task: pending
  evidence: record/wave-46-asks-nothing/line/T4-shell-lint-98eb8b58ae98.log
AC-2.2: The pin holds a ceiling that only falls: the count of texts naming neither at this head is recorded, a landing that raises it is refused, and one that lowers it rewrites the ceiling. Every wall that stopped wave 45 on a word of Person A's (the Verify gate at D29, the fix cap at D31, the release card's waiver) names its exit at the release head.
  provenance: charter Theme 1 item 1.2; wave 45 handoff open question 4 and D29 ("We need to automate the meta-harness so I don't need to intervene when it's unnecessary")
  fails-when: the ceiling is raised by one for a file, or one of the three walls loses its exit
  eval: T2 — `tests/shell-lint.test.sh` §EXIT-1 → the real tree prints nothing against `tests/lib/refusal-exits.ceiling`; against `/dev/null` a named site; the three named walls are not in the sweep's output
  task: pending
  evidence: record/wave-46-asks-nothing/line/T4-shell-lint-98eb8b58ae98.log
AC-2.3: A refusal that needs a person, met during a run, is logged by the wall to the landing record as an event its reader reads: `line/v1|ev=refusal|needs=person|wall=<name>|at=<ISO>`.
  provenance: charter Theme 1 item 1.2; wave 45 handoff open question 4 and D29 ("We need to automate the meta-harness so I don't need to intervene when it's unnecessary")
  fails-when: the event write is removed
  eval: T2 — `tests/refuse.test.sh` §NEEDS → `refuse exit2 v fact 'needs: Person A — why'` with a bound plan appends `line/v1|ev=refusal|needs=person|wall=v`
  task: pending
  evidence: record/wave-46-asks-nothing/line/T3-refuse-9893ed5beeb2.log
AC-2.4: The close counts those events in the hand-holds line as `needs-you=<n>`, and the field joins `total=`: a refusal the person had to answer is a hand-hold.
  provenance: charter Theme 1 item 1.2; wave 45 handoff open question 4 and D29 ("We need to automate the meta-harness so I don't need to intervene when it's unnecessary")
  fails-when: the field is left out of the sum
  eval: T2 — `tests/landing-line-2.test.sh` §NEEDS → one refusal event in the window prints `needs-you=1` and `total=1`
  task: pending
  evidence: record/wave-46-asks-nothing/line/T5-landing-line-2-a5bf5eb50ab6.log
AC-3.1: `matrix-retier <AC> tier=<higher> eval=<text>` rewrites the cell's tier, the block's `eval:` line and the Eval design row in one write, resets the row to pending with its evidence cleared, and records the retier on the landing record.
  provenance: charter Theme 1 item 1.3; wave 45 AC-13.2 waiver at the release card; deferral record/wave-45-whole-run/critic-evidence.md#1
  fails-when: one of the three places keeps T1
  eval: T2 — `tests/session-poker-5.test.sh` §RETIER → after `matrix-retier AC-2.1 tier=T2 eval=…` the cell, the `eval:` line and the Eval design row read T2 and the text, status pending, no `waiver:`, `ev=matrix-retier` appended
  task: T6
  evidence: record/wave-46-asks-nothing/line/T6-session-poker-5-668547a52e63.log
AC-3.2: The verb refuses a tier at or below the cell's.
  provenance: charter Theme 1 item 1.3; wave 45 AC-13.2 waiver at the release card; deferral record/wave-45-whole-run/critic-evidence.md#1
  fails-when: the comparison is inverted
  eval: T2 — `tests/session-poker-5.test.sh` §RETIER → `tier=T1` on a T2 cell is refused, rc≠0, the plan unchanged
  task: T6
  evidence: record/wave-46-asks-nothing/line/T6-session-poker-5-668547a52e63.log
AC-3.3: The hand-holds measure counts an upward retier as nothing and a waiver as one; no verb lowers a tier, so a downward change stays a hand edit the hand-edit log already counts.
  provenance: charter Theme 1 item 1.3; wave 45 AC-13.2 waiver at the release card; deferral record/wave-45-whole-run/critic-evidence.md#1
  fails-when: the fold counts `ev=matrix-retier`
  eval: T2 — `tests/landing-line-2.test.sh` §RETIER → a retier event moves nothing; a `waiver:` line adds one
  task: T6
  evidence: record/wave-46-asks-nothing/line/T6-landing-line-2-668547a52e63.log
AC-4.1: The 1.29.0 close reads `hand-holds: total=0` with `needs-you=0`, the live row owed at Step 9 as AC-3.5 was.
  provenance: charter Objective 3; wave 45 AC-3.5 (blocked at total=4: waivers=1, status-writes=3)
  fails-when: any field above zero
  eval: T3 — `session-poker.sh landing-report --hand-holds <this plan>` at delivered → `hand-holds: total=0 … needs-you=0`
  task: T21
  evidence: record/wave-46-asks-nothing/continuation.md — hand-holds: total=1 · by-hand=0 · stop-runs=1 · declines=0 · lifts=0 · amends=0 · holds=0 · extensions=0 · waivers=0 · status-writes=0 · second-regressions=0 · adoptions=0 · fixed=0 · needs-you=0 · unplaced=4
AC-5.1: `regression-run` runs at any head that differs from the last proof's and says already proved only at the same head: the two refusals that read a later head as proved by its landings' suites or by any clean ancestor run (hooks/poker/proof.sh:1664 and :1680, `proof_whole_run_behind`) are gone, and the same-head refusal stays.
  provenance: charter Theme 2 item 2.1; wave 45 A-orch.62 and A-orch.64; the `stack-health:` line that read `red … owed=4` through delivery after T29 and T30 had closed each suite (research-theme2 §2.1); deferral record/wave-45-whole-run/critic-evidence.md#4
  fails-when: the same-head refusal is dropped with the other two
  eval: T2 — `tests/canonical-sdlc-evidence-gate-2.test.sh` §WHOLE-RUN → a head one landing past the proof runs; the proof's own head is refused "runs once at a head"
  task: pending
  evidence: record/wave-46-asks-nothing/line/T8-canonical-sdlc-evidence-gate-2-6e4604b8607e.log
AC-5.2: `stack-health:` is green only at a head where the whole suite ran green.
  provenance: charter Theme 2 item 2.1; wave 45 A-orch.62 and A-orch.64; the `stack-health:` line that read `red … owed=4` through delivery after T29 and T30 had closed each suite (research-theme2 §2.1); deferral record/wave-45-whole-run/critic-evidence.md#4
  fails-when: the function prints green for a covered later head
  eval: T2 — `tests/session-poker-4.test.sh` §STACK → `proof_health_line` prints `green` only at the proof's head with no owed; `red` past it
  task: pending
  evidence: record/wave-46-asks-nothing/line/T7-session-poker-4-c684231a82dd.log
AC-5.3: After a fix row lands, `owed=` lists only the suites no later landing turned green, agreeing with the judge the gates read, and the line is never green for it.
  provenance: charter Theme 2 item 2.1; wave 45 A-orch.62 and A-orch.64; the `stack-health:` line that read `red … owed=4` through delivery after T29 and T30 had closed each suite (research-theme2 §2.1); deferral record/wave-45-whole-run/critic-evidence.md#4
  fails-when: the settlement skips the rewrite
  eval: T2 — `tests/landing-line-1.test.sh` §HEALTH → after a landing greens one owed suite the line's `owed=` drops it and still reads `red`
  task: pending
  evidence: record/wave-46-asks-nothing/line/T7-landing-line-1-c684231a82dd.log
AC-6.1: When no row is ready, none is running and the head is past the last proof, the tick starts the whole run, detached, under the gate's whole-run rule as it stands (admitted alone, nothing unfinished).
  provenance: charter Theme 2 item 2.2; 1.28.0's merge waited on a run started by hand after the close (A-orch.39, A-orch.60, A-orch.64); the tick starts no whole run today (research-theme2 §2.2)
  fails-when: the branch's quiet condition is inverted
  eval: T2 — `tests/session-poker-4.test.sh` §STARTER → a tick with no row ready, none running, head past the proof prints `poker: regression-run started regression@<h8>` and the roster holds the detached object
  task: pending
  evidence: record/wave-46-asks-nothing/line/T13-session-poker-4-3038b1f93477.log
AC-6.2: A fix row landing after a proof starts the whole run again at the new head.
  provenance: charter Theme 2 item 2.2; 1.28.0's merge waited on a run started by hand after the close (A-orch.39, A-orch.60, A-orch.64); the tick starts no whole run today (research-theme2 §2.2)
  fails-when: the head comparison reads the proof's head
  eval: T2 — `tests/session-poker-4.test.sh` §STARTER → a fix row landed past the proof, next tick starts again at the new head
  task: pending
  evidence: record/wave-46-asks-nothing/line/T13-session-poker-4-3038b1f93477.log
AC-6.3: The started run records its proof through `proof-add regression` as today.
  provenance: charter Theme 2 item 2.2; 1.28.0's merge waited on a run started by hand after the close (A-orch.39, A-orch.60, A-orch.64); the tick starts no whole run today (research-theme2 §2.2)
  fails-when: the detached call drops `proof-add`
  eval: T2 — `tests/session-poker-4.test.sh` §STARTER → the started verb's run writes `proved: kind=regression head=<new>` through proof-add
  task: pending
  evidence: record/wave-46-asks-nothing/line/T13-session-poker-4-3038b1f93477.log
AC-6.4: A whole run the tick starts counts as nothing in the hand-holds line; `second-regressions` counts only a run a person started.
  provenance: charter Theme 2 item 2.2; 1.28.0's merge waited on a run started by hand after the close (A-orch.39, A-orch.60, A-orch.64); the tick starts no whole run today (research-theme2 §2.2)
  fails-when: the fold ignores `starter=`
  eval: T2 — `tests/landing-line-2.test.sh` §STARTER → two `ev=run starter=tick` passes read `second-regressions=0`; one `starter=person` reads 1
  task: pending
  evidence: record/wave-46-asks-nothing/line/T8-landing-line-2-6e4604b8607e.log
AC-7.1: The release card prints `whole suite: green at <h8>` or `whole suite: red at <h8>, <n> landings before this head`, the head the proof's and the count the landings since it.
  provenance: charter Theme 2 item 2.3; wave 45 continuation scorecard "whole run green at cf173c49" against the proof line at that head (red, 122 of 126: hooks/poker/sitrep.sh:1108 and close-out.sh:1421 print green for any proof line, research-record §A.1); deferral record/wave-45-whole-run/critic-adversarial.md#5
  fails-when: the card prints green over the red fixture
  eval: T2 — `tests/card.test.sh` §UNPROVED → `whole suite: red at <h8>, 2 landings before this head`; over a green fixture `whole suite: green at <h8>`
  task: pending
  evidence: record/wave-46-asks-nothing/line/T23-card-b5f2a7b729a4.log
AC-7.2: When the whole suite is not green at this head the card asks `Merge without a whole run at this head` as its own approval beside the merge, answered by `reply`, and Step 8 is refused until it is answered.
  provenance: charter Theme 2 item 2.3; wave 45 continuation scorecard "whole run green at cf173c49" against the proof line at that head (red, 122 of 126: hooks/poker/sitrep.sh:1108 and close-out.sh:1421 print green for any proof line, research-record §A.1); deferral record/wave-45-whole-run/critic-adversarial.md#5
  fails-when: the ask is drawn but `facts_state` passes without it
  eval: T2 — `tests/card.test.sh` §UNPROVED → the red fixture's card carries `approve:merge-unproved`; `current 8 --check` refuses unreplied and passes after `reply`
  task: pending
  evidence: record/wave-46-asks-nothing/line/T23-card-b5f2a7b729a4.log
AC-7.3: Step 8 and close-out read the same judge the card reads.
  provenance: charter Theme 2 item 2.3; wave 45 continuation scorecard "whole run green at cf173c49" against the proof line at that head (red, 122 of 126: hooks/poker/sitrep.sh:1108 and close-out.sh:1421 print green for any proof line, research-record §A.1); deferral record/wave-45-whole-run/critic-adversarial.md#5
  fails-when: one reader keeps its own computation
  eval: T2 — `tests/proof-at-head.test.sh` §ONE → the card, `current 8 --check` and close-out's pre-flight print one state over one fixture
  task: pending
  evidence: record/wave-46-asks-nothing/line/T9-proof-at-head-f44b9b4389a7.log
AC-7.4: The continuation's correctness line and the scorecard read the proof through the judge the gates read (`proof_state`), never a reading of their own that ignores `owed=`.
  provenance: charter Theme 2 item 2.3; wave 45 continuation scorecard "whole run green at cf173c49" against the proof line at that head (red, 122 of 126: hooks/poker/sitrep.sh:1108 and close-out.sh:1421 print green for any proof line, research-record §A.1); deferral record/wave-45-whole-run/critic-adversarial.md#5
  fails-when: `sitrep_whole` prints green for any proof line
  eval: T2 — `tests/sitrep.test.sh` §WHOLE → over a proof line with `owed=` the correctness line reads `red at <h8>`; `tests/close-out-3.test.sh` §REG → the continuation's line reads the same
  task: pending
  evidence: record/wave-46-asks-nothing/line/T9-sitrep-f44b9b4389a7.log
AC-8.1: `walk.md` carries a verdict table in the shape the critic's record carries and `proof_verdicts` reads (`| AC | verdict | why |`).
  provenance: charter Theme 2 item 2.4; wave 45's three status writes for AC-33.3, AC-34.4, AC-35.4 (landing-proofs.log:688-690, 6.7 minutes after T36 published, research-record §A.4); wave 45 D2 and ADR-072 (a landing settles what it proves); deferral record/wave-45-whole-run/critic-evidence-2.md#1
  fails-when: the parser accepts a record with no table
  eval: T2 — `tests/session-poker-4.test.sh` §WALK → a walk record with `| AC | verdict | why |` and one `verdict:` line parses; one without is refused naming the shape
  task: pending
  evidence: record/wave-46-asks-nothing/line/T11-session-poker-4-623257f87bb7.log
AC-8.2: `proof-add walk <record>` writes `discharged` for each confirmed row not already settled by a landing, and the `walk-artifact:` pointer, in one write.
  provenance: charter Theme 2 item 2.4; wave 45's three status writes for AC-33.3, AC-34.4, AC-35.4 (landing-proofs.log:688-690, 6.7 minutes after T36 published, research-record §A.4); wave 45 D2 and ADR-072 (a landing settles what it proves); deferral record/wave-45-whole-run/critic-evidence-2.md#1
  fails-when: the pointer write is split out and skipped
  eval: T2 — `tests/session-poker-4.test.sh` §WALK → CONFIRMED rows read `discharged` with the record as evidence, a REFUTED row stays pending, `walk-artifact:` is set, `ev=walk` appended, no `ev=matrix-set`
  task: pending
  evidence: record/wave-46-asks-nothing/line/T11-session-poker-4-623257f87bb7.log
AC-8.3: The walk row's landing runs the verb, so no status write follows the walk.
  provenance: charter Theme 2 item 2.4; wave 45's three status writes for AC-33.3, AC-34.4, AC-35.4 (landing-proofs.log:688-690, 6.7 minutes after T36 published, research-record §A.4); wave 45 D2 and ADR-072 (a landing settles what it proves); deferral record/wave-45-whole-run/critic-evidence-2.md#1
  fails-when: the artifact check is removed and ready lands without settling
  eval: T2 — `tests/spawn-worktree.test.sh` §WALK → `ready` on a verify row whose artifact is the walk record lands it and the plan shows the rows discharged
  task: pending
  evidence: record/wave-46-asks-nothing/line/T11-session-poker-4-623257f87bb7.log
AC-9.1: Human stops are the cards approved plus the asks put after the plan card, read from the run's asks register.
  provenance: charter Theme 2 item 2.5; wave 45 scorecard (1 stop, 27 minutes: hooks/poker/sitrep.sh:605-640 counts `approved:` lines and release pages only) against its ledger (4 stops, about 514 minutes, research-record §A.3); deferral record/wave-44-every-hand/critic-adversarial.md#8
  fails-when: puts are read from `approved:` lines again
  eval: T2 — `tests/sitrep.test.sh` §ROUNDS → four decide rounds after the plan card print `human stops (autonomous half): 5` with the card
  task: T12
  evidence: record/wave-46-asks-nothing/line/T12-sitrep-d69c413259e6.log
AC-9.2: Wait minutes are the sum of answered minus put per ask, from the register's own ISO instants, every round of a re-put key kept.
  provenance: charter Theme 2 item 2.5; wave 45 scorecard (1 stop, 27 minutes: hooks/poker/sitrep.sh:605-640 counts `approved:` lines and release pages only) against its ledger (4 stops, about 514 minutes, research-record §A.3); deferral record/wave-44-every-hand/critic-adversarial.md#8
  fails-when: `owed_open` replaces the earlier round
  eval: T2 — `tests/sitrep.test.sh` §ROUNDS → a round opened 23:36Z answered 07:32Z adds 476; a re-put key keeps both rounds
  task: T12
  evidence: record/wave-46-asks-nothing/line/T12-sitrep-d69c413259e6.log
AC-9.3: The sitrep and the continuation print both from one function.
  provenance: charter Theme 2 item 2.5; wave 45 scorecard (1 stop, 27 minutes: hooks/poker/sitrep.sh:605-640 counts `approved:` lines and release pages only) against its ledger (4 stops, about 514 minutes, research-record §A.3); deferral record/wave-44-every-hand/critic-adversarial.md#8
  fails-when: close-out formats its own numbers
  eval: T2 — `tests/close-out-3.test.sh` §SCORE → close-out's `## Scorecard` equals `landing-report --scorecard` over the same fixture
  task: T12
  evidence: record/wave-46-asks-nothing/line/T22-close-out-4-de0039e9bf84.log
AC-10.1: `tests/canonical-sdlc-evidence-gate-2.test.sh` Section 33 pins the owing-step rule T33 landed, or is removed with the census updated.
  provenance: charter "Carried test debt" item 1; wave 45 T33's report
  fails-when: the old header text survives
  eval: T2 — `tests/canonical-sdlc-evidence-gate-2.test.sh` Section 33 → describes the owing-step rule; `/usr/bin/grep -c "T0-only" tests/canonical-sdlc-evidence-gate-2.test.sh` → 0
  task: T14
  evidence: record/wave-46-asks-nothing/walk.md
AC-10.2: Fixture 33b fails when its rule is reverted.
  provenance: charter "Carried test debt" item 1; wave 45 T33's report
  fails-when: 33b still asserts nothing
  eval: T2 — Section 33b → `expect_allow` on the deferred row; with the owing-step rule reverted in a fixture copy of walls.sh, red
  task: T14
  evidence: record/wave-46-asks-nothing/walk.md
AC-11.1: OC-1 has a fixture in its own suite that is red when the dry run does not refuse, or a recorded line naming the gate suite's 9a rows as its pin.
  provenance: charter "Carried test debt" item 2
  fails-when: the fixture flips nothing
  eval: T2 — `tests/close-out-4.test.sh` §OC-1b → the dry run with the matrix arm disabled in a fixture copy prints a refusal and the test is red
  task: T15
  evidence: record/wave-46-asks-nothing/walk.md
AC-12.1: Run from a row's worktree, each part renders CHANGELOG.md in that tree.
  provenance: charter "Carried test debt" item 3; wave 45 T21 and A-orch.54, A-orch.59
  fails-when: the verb reads `refs/heads/<wb>` again
  eval: T2 — `tests/session-poker-5.test.sh` §PARTS → `known-limits-part` run from a fixture worktree commits CHANGELOG.md there, the working branch untouched
  task: T16
  evidence: record/wave-46-asks-nothing/line/T16-session-poker-5-284b93cc85e5.log
AC-12.2: The landing record's part event follows the commit site.
  provenance: charter "Carried test debt" item 3; wave 45 T21 and A-orch.54, A-orch.59
  fails-when: the event names the working branch
  eval: T2 — `tests/session-poker-5.test.sh` §PARTS → the landing record's part line carries `tree=<the worktree>`
  task: T16
  evidence: record/wave-46-asks-nothing/line/T16-session-poker-5-284b93cc85e5.log

## Assumptions

`record/wave-46-asks-nothing/assumptions.md`, seeded from the requirements' Not Doing and the spec's assumptions; Step 4 appends there before each commit.

- The wave number is 46, the next in epic 23 after wave 45 (1.28.0, main @ b69ac4a3c, tag v1.28.0).
- The Patrol is not armed at task scale; the tick runs in the orchestrator's turns, and D5's starter runs there too.
- The spec's "row of kind walk" (D13) is the verify row whose artifact is `record/wave-46-asks-nothing/walk.md`; the kind vocabulary has no `walk`, and `ready` reads the artifact, not a new kind.
- Rows that share a file run side by side and reconcile on landing: T1, T2, T6, T10 and T12 edit `hooks/poker/plan.sh`; T7, T8, T11 and T13 edit `hooks/poker/proof.sh`; T5, T8 and T16 edit `hooks/poker/line.sh`.

## Handoff

handoff: .bionic/docs/record/handoffs/2026-10-25-wave-46-asks-nothing.md written 2026-10-26 07:16 PDT
## SDLC State

integration-branch: main
working-branch: wave/46-asks-nothing
base: main @ b69ac4a3c (1.28.0, PR #35, tag v1.28.0)
intent: build
rigor: single
scale: task
current: 9
approved-by: Person A 2026-10-25T20:09:23Z "approved"
approved: release by Person A 2026-10-26T14:13:52Z head=93683c5e52b7098021f23426a35913c34d7a83a0 "2 merge, rest recommended"
approved: merge-unproved by Person A 2026-10-26T14:13:54Z head=93683c5e52b7098021f23426a35913c34d7a83a0 "2 merge, rest recommended"
order: given 2026-10-25T20:13:10Z "I'm stepping away. Treat every decision that can be reverted as yours, and keep the run moving as far as it can go without me. When you reach something only I can settle, don't stop there: finish and stage everything around it, then carry on with whatever else is open. Ping me only when nothing can move without me. When you've gone as far as you can, conclude with a report of what's done, what's waiting on me, and the decision each item needs."
order: lifted 2026-10-25T20:16:50Z "I'm stepping away. Treat every decision that can be reverted as yours, and keep the run moving as far as it can go without me. When you reach something only I can settle, don't stop there: finish and stage everything around it, then carry on with whatever else is open. Ping me only when nothing can move without me. When you've gone as far as you can, conclude with a report of what's done, what's waiting on me, and the decision each item needs."
- T1: landed eb9a83ddeacfa6030c30fa26672f799a0a31bf50 2026-10-25T21:02:35Z — .worktrees/wt/46-T1
- T2: landed 011d42e2fb7b82a0527bdcf651a981f3fa95b386 2026-10-26T00:33:54Z — .worktrees/wt/46-T2
- T3: landed 9893ed5beeb242fd84ba3196c08809a3f8b1ba73 2026-10-26T00:10:33Z — .worktrees/wt/46-T3
- T4: landed 98eb8b58ae988c388b9d272983bce7bf1a1f4df9 2026-10-25T21:21:55Z — .worktrees/wt/46-T4
- T5: landed a5bf5eb50ab6ad70a32d19cf9be063e763451772 2026-10-26T01:03:14Z — .worktrees/wt/46-T5 reason: the whole hand-holds line is pinned as an exact string in close-out-3, close-out-4 and landing-line-1 as well as landing-line-2; a needs-you field added to it turns all four red, so the row that adds it owns all four pins (the hole T16 fell into) reason: the four suites that pin the whole hand-holds line
- T6: landed 668547a52e6354c2ef04d8b9d84426695fd0b7c4 2026-10-25T21:39:06Z — .worktrees/wt/46-T6
- T7: landed c684231a82dd7ec414feabe3088be01c02511a1a 2026-10-25T20:42:56Z — .worktrees/wt/46-T7
- T8: landed 6e4604b8607e07a0601676f57b4768ae423409dd 2026-10-25T20:32:52Z — .worktrees/wt/46-T8
- T9: landed f44b9b4389a7d0eeade69275f52fcad91884fccd 2026-10-25T20:53:24Z — .worktrees/wt/46-T9
- T10: landed 107923425785049240705d3c09ea0632904eb110 2026-10-26T00:21:42Z — .worktrees/wt/46-T10 reason: FA-3 and FA-6b pin the old covered-is-green rule T9 replaced; T10 owns the card line and rewrites them with §JUDGE
- T11: landed 623257f87bb7c2d9e56c0dd459f4b8cd52fec8c0 2026-10-25T22:37:35Z — .worktrees/wt/46-T11
- T12: landed d69c413259e69df386b771702591a15f19651c68 2026-10-25T23:48:23Z — .worktrees/wt/46-T12
- T13: landed 3038b1f9347735fcca393a1fb688230ce2a579a5 2026-10-25T22:02:47Z — .worktrees/wt/46-T13
- T14: landed ac237ec5090f5961458d9d05572d9ab4f8bae6fa 2026-10-26T00:45:32Z — .worktrees/wt/46-T14
- T15: landed 402980ecbdf9d69531d70801485df0690c68d688 2026-10-26T01:53:49Z — .worktrees/wt/46-T15
- T16: landed 284b93cc85e540ad168f5d65b9e6c4d1230e0f9d 2026-10-25T21:06:31Z — .worktrees/wt/46-T16
- T17: landed 837ddc39161b522a7071b996cf9d0d9121f1c61b 2026-10-26T04:01:18Z — .worktrees/wt/46-T17
- T18: landed 837ddc39161b522a7071b996cf9d0d9121f1c61b 2026-10-26T04:24:17Z — .worktrees/wt/46-T18
- T19: landed 31da41f7171d816640e31a715e1b791304f5483a 2026-10-26T05:45:24Z — .worktrees/wt/46-T19 reason: the version surfaces the renderer owns, the release-check pin whose newest-heading arm the 1.29.0 heading breaks, and the row report
- T20: landed b69ac4a3c8909bbc00415684ec9eb5204f2f1bf1 2026-10-26T14:15:52Z — .worktrees/wt/46-T20
- T21: landed b69ac4a3c8909bbc00415684ec9eb5204f2f1bf1 2026-10-26T14:15:52Z — .worktrees/wt/46-T21
- T22: landed de0039e9bf846b21a547d15d9a48f49a91e97fdd 2026-10-26T00:01:46Z — added by task-add at 2026-10-25T21:07:10Z reason: T6 landed without the one-word writer-wall change at walls.sh:5410 (matrix-retier beside matrix-set) and its pin; the fix row carries it with the two part-line pins reason: shell-lint §EXIT reads plan.sh at 151 unexcused sites against a ceiling of 148 since T6 (T11 report); the three new refusals get exits in the fix row
- T23: landed b5f2a7b729a4b45a71bc5e5202906029bba1a2c7 2026-10-26T01:33:25Z — added by task-add at 2026-10-26T00:25:07Z reason: the two suites that pin the approve verb and the release card
- T24: landed d646c4373e9fc847c88699e095983619714cf52a 2026-10-26T01:10:21Z — added by task-add at 2026-10-26T00:45:59Z reason: the suite that holds AH-1
- T25: landed 837ddc39161b522a7071b996cf9d0d9121f1c61b 2026-10-26T03:51:26Z — added by task-add at 2026-10-26T02:29:19Z born: regression rehearsal-failed-review.test.sh of=regression reason: the two red suites and the sibling that shares the rehearsal library
- T26: landed 5be5879d560bd6faa6b911ae50665d149e0f6636 2026-10-26T02:47:55Z — added by task-add at 2026-10-26T02:29:20Z born: regression session-poker-4.test.sh of=regression reason: the red suite and the register suite its second half may touch
- T27: landed cb003008f871b6e3ae922daa981879d438a7ae8b 2026-10-26T03:01:06Z — added by task-add at 2026-10-26T02:29:22Z born: regression door-card.test.sh of=regression reason: the red suite
- T28: landed 56e7f4a1a53d7a048d53d8da5113de8d03770114 2026-10-26T02:51:31Z — added by task-add at 2026-10-26T02:29:23Z born: regression words.test.sh of=regression reason: the two red suites
- T29: landed 5a08f601b5aca8cdf332c0ca1581bcbcdf3ab851 2026-10-26T04:56:34Z — added by task-add at 2026-10-26T04:22:14Z reason: the gate suite that holds the walk arm, its sibling over walls.sh, and close-out-3 INSERT.16 which reads the walk gate through close-out reason: the gate suite holds no walk-gate row today, so the pin is a new section and the census must carry its line
- T30: landed 5a08f601b5aca8cdf332c0ca1581bcbcdf3ab851 2026-10-26T05:08:27Z — added by task-add at 2026-10-26T04:42:26Z
- T31: landed 1df303f2f7aac6be97e77186262ed36654c93be4 2026-10-26T13:05:56Z — added by task-add at 2026-10-26T12:37:49Z reason: the suite that drives matrix-render, and the two that pin row-landed, which shares the serves reader the row widens
- T33: landed 6b7563afb608fccbdcf93beaff95655b086f2d77 2026-10-26T13:49:58Z — added by task-add at 2026-10-26T12:37:56Z
- T32: pending dispatch — added by task-add at 2026-10-26T12:37:56Z reason: the release check pins the entry reason: the landing renders the release numbers itself after a landing past the entry (line/v1 ev=published numbers=6b7563afb), so the row has nothing to write
- T34: landed 29643d9f79d6d7dea7b1897e445a1a4397828402 2026-10-26T13:54:23Z — added by task-add at 2026-10-26T13:47:54Z reason: the release check pins the entry
- T35: landed 93683c5e52b7098021f23426a35913c34d7a83a0 2026-10-26T14:01:05Z — added by task-add at 2026-10-26T13:56:26Z reason: the release check pins the entry
- session: 00000000-0000-4000-8000-000000000001 bound 2026-10-25T18:19:17Z by write
- session: 00000000-0000-4000-8000-000000000002 bound 2026-10-25T23:01:17Z by bind
- session: 00000000-0000-4000-8000-000000000003 bound 2026-10-26T03:41:37Z by bind
- Step 0: configured at 2026-10-25T18:27Z via Person A "approved" at the Step-0 card (card.sh step0, record/wave-46-asks-nothing/step0-card.txt); prereqs: ok; fix-cap 4 by D1 ruled "1" (Δ1); regression yes from the charter's "How it runs" (override recorded); model_plan=orchestrator=claude-fable-5-1; implementor=sonnet-high; senior-implementor=opus-high; researcher=opus-high; test-runner=haiku-high; auditor=opus-high; critic=opus-high; probe cores=8 mem_gb=8 disk_free_gb=28 load_1m=1.71; share 92; branch wave/46-asks-nothing off main @ b69ac4a3c (1.28.0, PR #35, tag v1.28.0); no wave was open (wave 45 delivered 2026-10-25T16:14Z), the charter is the seed
- Step 1: requirements: specs/epic-23-bionic-tech-debt/wave-46-asks-nothing.requirements.md; approved by Person A 2026-10-25T18:44Z "approved" at the Step-1 card (card.sh step1, rc 0, record/wave-46-asks-nothing/step1-card.txt); 12 requirements in three themes, 35 criteria; D2 ruled "1" (the refusal pin ratchets from a ceiling, Δ3) and D3 ruled "1" (Theme 3 built, Δ4) at the card; inherited: 5 adopted, 28 carried, 0 closed; research maps record/wave-46-asks-nothing/research-{theme1-refusals-and-cap,theme2-proof-at-head,record-and-debt}.md
- Step 2: spec: specs/epic-23-bionic-tech-debt/wave-46-asks-nothing.spec.md; approved by Person A 2026-10-25T20:04Z "approved" at the Step-2 card (card.sh step2, rc 0, record/wave-46-asks-nothing/step2-card.txt); interview: frame D4 ruled "1" (Δ9), D6 and D7 ruled "1" (Δ11, Δ12), D5 re-put in plain words and ruled "provisionally, option 1. However, it could be either the orchestrator or a tick that initiates the full regression." (Δ14); D8 to D18 defaulted and surfaced (Δ15); 18 decisions, 35 eval rows over 12 requirements; ledger record/wave-46-asks-nothing/design-ledger.md; ADR-074 named for Step 7
- Step 3: plan: plans/epic-23-bionic-tech-debt/wave-46-asks-nothing.plan.md; approved by Person A 2026-10-25T20:31Z "approved" at the Step-3 card (card.sh step3, rc 0, record/wave-46-asks-nothing/step3-card.txt); 21 rows (16 build, verify, review, doc, integrate, close), T1 first by dispatch order; 35 matrix rows rendered; longest chain T7 → T13 → T17 → T20 → T21 · 285 min
- Step 4: rows dispatched from the working branch; worktree: spawned per row by spawn-worktree.sh under .worktrees/; base-sha: b69ac4a3c8909bbc00415684ec9eb5204f2f1bf1; branch: wave/46-asks-nothing; dispatch ledger below
  worktree: .
  base-sha: b69ac4a3c
  branch: wave/46-asks-nothing
- Step 5: verify: build settled at 837ddc39161b522a7071b996cf9d0d9121f1c61b (T25, the last row to land; 23 build rows through ready: T1 to T16, T22 to T24 added from the orchestrator's reading of landed code, T25 to T28 born of the regression's six reds); the regression once at 402980ecb (record/wave-46-asks-nothing/regression-run-402980ecbdf9d69531d70801485df0690c68d688.log, 121 passed, 6 failed, each red a pin of a rule this wave changed, each closed by the green of its fix row at its landing, no second whole run); the walk (T17, record/wave-46-asks-nothing/walk.md at 837ddc391: 21 rows, 11 CONFIRMED, 10 UNVERIFIABLE where the renderer writes or no tick-started run exists, verdict UNVERIFIABLE); the critic (T18) holds evidence at single rigor; AC-4.1 is the close's live row
  walk-artifact: record/wave-46-asks-nothing/walk.md
  auditor: record/wave-46-asks-nothing/critic-evidence.md — the critic holds evidence at single rigor: 34 rows CONFIRMED at 837ddc39, AC-8.3 REFUTED on an evidence pointer since repointed, AC-4.1 the live close row, wave REFUTED on finding 4 (the walk gate refusing the registered walk), fixed by T29 at 5a08f601b and re-read by T30
- Step 7: document: adr: adrs/epic-23-bionic-tech-debt/adr-074-green-means-the-whole-suite-ran-here.md (T19, Proposed, D4 with D13, D14, D16; promoted to docs/adrs by T19); the 1.29.0 entry rendered from the plan by T19 from its own tree (known-limits-part, D17), its Known limits the six S3 deferrals of critic-adversarial.md and critic-structure.md, each stated; ### The reviews is T20's (reviews-part)
  adr: adrs/epic-23-bionic-tech-debt/adr-074-green-means-the-whole-suite-ran-here.md
- Step 8: CLOSED 2026-10-26T14:16Z — wave/46-asks-nothing to be pulled into main; the tail was performed by close-out.sh 1.29.0
  merge: 050fa567e2b20d130a07303163de5c7b012a8fbb — pull request 36 merged into main by Person A 2026-10-26T14:19:16Z
  worktree-removed: wt/46-T1, wt/46-T2, wt/46-T3, wt/46-T4, wt/46-T5, wt/46-T6, wt/46-T7, wt/46-T8, wt/46-T9, wt/46-T10, wt/46-T11, wt/46-T12, wt/46-T13, wt/46-T14, wt/46-T15, wt/46-T16, wt/46-T19, wt/46-T22, wt/46-T23, wt/46-T24, wt/46-T25, wt/46-T26, wt/46-T27, wt/46-T28, wt/46-T29, wt/46-T31, wt/46-T34, wt/46-T35
  cleanup: done
  tmp-wiped: 38 entries under /fixture/project/.bionic/tmp (37 removed, 0 spared for a live neighbour session, 1 kept: this session's engaged marker, removed as close-out's last act; this session's own state and every dead session's are never spared)
  tasks-completed: mark every 4/*, 5–9 entry completed (TaskUpdate)
  attested-by: close-out.sh 1.29.0
- Step 9: delivered: 2026-10-26T14:16Z wave-46-asks-nothing 1.29.0 — the Step 8/9 tail was performed by close-out.sh and attested against the commit gate; continuation at record/wave-46-asks-nothing/continuation.md
  archived: bionic: archive skipped — epic-23-bionic-tech-debt still has an open run (/fixture/project/.bionic/docs/plans/epic-23-bionic-tech-debt/epic.plan.md)
  attested-by: close-out.sh 1.29.0
proved: kind=regression head=402980ecbdf9d69531d70801485df0690c68d688 at=2026-10-26T02:26:19Z evidence=record/wave-46-asks-nothing/regression-run-402980ecbdf9d69531d70801485df0690c68d688.log owed=close-replay.test.sh,door-card.test.sh,regression-rename.test.sh,rehearsal-failed-review.test.sh,session-poker-4.test.sh,words.test.sh run=2026-10-26T02:25:47Z head=402980ecbdf9d69531d70801485df0690c68d688 rc=1
proved: kind=walk head=837ddc39161b522a7071b996cf9d0d9121f1c61b at=2026-10-26T04:01:18Z evidence=record/wave-46-asks-nothing/walk.md
proved: kind=review head=837ddc39161b522a7071b996cf9d0d9121f1c61b at=2026-10-26T04:21:32Z evidence=record/wave-46-asks-nothing/critic-adversarial.md question=adversarial reader=w46-T18 result=flag scope=whole
moved: record/wave-46-asks-nothing/critic-adversarial.md#8 to=fixed row=T29 by=Person A at=2026-10-26T04:43:45Z
deferred: record/wave-46-asks-nothing/critic-adversarial.md#1 S3 on "the tick's whole-run start yields to the walk and critic rows, which turn ready on the last build landing, so the review reads a head no pass ran at" stated="The tick starts the whole run only while no row is ready, so the walk and critic rows, ready at the last build landing, can read a head no pass ran at; the orchestrator starts the run there."
deferred: record/wave-46-asks-nothing/critic-adversarial.md#2 S3 on "current 7 is held to the merge-unproved rule D14 placed at Step 8, and its person's exit names a release card that cannot exist yet at Step 7" stated="Advancing to Step 7 is held to the merge-unproved rule placed at Step 8, so a run whose pass is behind its head needs a second whole run or the person's word on a release card that does not yet exist at Step 7."
deferred: record/wave-46-asks-nothing/critic-adversarial.md#3 S3 on "the card asks the merge without a pass on a plan with no integrate row, where the reply that answers it is refused" stated="The release card asks the merge without a pass on a plan with no integrate row, where approve refuses the reply that answers it."
deferred: record/wave-46-asks-nothing/critic-adversarial.md#4 S3 on "the skill text still says regression-run refuses a proved head and that a second whole run never happens, which D16 and D4 made false" stated="The skill text in operational-rules.md and steps/5.md still says regression-run refuses a proved head and that a second whole run never happens, which D4 and D16 made false."
deferred: record/wave-46-asks-nothing/critic-adversarial.md#5 S3 on "the sheet's waiting-on-you minutes read only a key's newest round, although T12 now keeps every round" stated="The situation report's waiting-on-you minutes read only the newest round of a re-put key, although the register now keeps every round."
proved: kind=review head=837ddc39161b522a7071b996cf9d0d9121f1c61b at=2026-10-26T04:21:41Z evidence=record/wave-46-asks-nothing/critic-structure.md question=structure reader=w46-T18 result=flag scope=whole
deferred: record/wave-46-asks-nothing/critic-structure.md#1 S3 on "the stack-health line and the release card disagree on green at the same head when the whole run's only reds are inherited debt" stated="The stack-health line and the release card disagree about green at a head whose whole run's only reds are inherited debt."
proved: kind=review head=837ddc39161b522a7071b996cf9d0d9121f1c61b at=2026-10-26T04:24:15Z evidence=record/wave-46-asks-nothing/critic-evidence.md question=evidence reader=w46-T18 result=fail scope=whole
moved: record/wave-46-asks-nothing/critic-evidence.md#4 to=fixed row=T29 by=Person A at=2026-10-26T04:27:34Z
proved: kind=regression head=837ddc39161b522a7071b996cf9d0d9121f1c61b at=2026-10-26T04:40:24Z evidence=record/wave-46-asks-nothing/regression-run-837ddc39161b522a7071b996cf9d0d9121f1c61b.log run=2026-10-26T04:40:17Z head=837ddc39161b522a7071b996cf9d0d9121f1c61b rc=0
proved: kind=review head=5a08f601b5aca8cdf332c0ca1581bcbcdf3ab851 at=2026-10-26T05:08:05Z evidence=record/wave-46-asks-nothing/critic-evidence-2.md question=evidence reader=w46-T30 result=pass scope=piece
proved: kind=review head=5a08f601b5aca8cdf332c0ca1581bcbcdf3ab851 at=2026-10-26T05:08:15Z evidence=record/wave-46-asks-nothing/critic-adversarial-2.md question=adversarial reader=w46-T30 result=flag scope=piece
proved: kind=review head=5a08f601b5aca8cdf332c0ca1581bcbcdf3ab851 at=2026-10-26T05:08:25Z evidence=record/wave-46-asks-nothing/critic-structure-2.md question=structure reader=w46-T30 result=flag scope=piece
proved: kind=check head=5a08f601b5aca8cdf332c0ca1581bcbcdf3ab851 at=2026-10-26T05:10:04Z evidence=record/wave-46-asks-nothing/release-check-5a08f601b5aca8cdf332c0ca1581bcbcdf3ab851.log
proved: kind=regression head=5a08f601b5aca8cdf332c0ca1581bcbcdf3ab851 at=2026-10-26T05:31:28Z evidence=record/wave-46-asks-nothing/regression-run-5a08f601b5aca8cdf332c0ca1581bcbcdf3ab851.log run=2026-10-26T05:31:21Z head=5a08f601b5aca8cdf332c0ca1581bcbcdf3ab851 rc=0
proved: kind=check head=31da41f7171d816640e31a715e1b791304f5483a at=2026-10-26T05:46:00Z evidence=record/wave-46-asks-nothing/release-check-31da41f7171d816640e31a715e1b791304f5483a.log
proved: kind=regression head=31da41f7171d816640e31a715e1b791304f5483a at=2026-10-26T06:20:28Z evidence=record/wave-46-asks-nothing/regression-run-31da41f7171d816640e31a715e1b791304f5483a.log run=2026-10-26T06:20:21Z head=31da41f7171d816640e31a715e1b791304f5483a rc=0
proved: kind=regression head=6b7563afb608fccbdcf93beaff95655b086f2d77 at=2026-10-26T13:41:08Z evidence=record/wave-46-asks-nothing/regression-run-6b7563afb608fccbdcf93beaff95655b086f2d77.log run=2026-10-26T13:41:00Z head=6b7563afb608fccbdcf93beaff95655b086f2d77 rc=0
proved: kind=review head=6b7563afb608fccbdcf93beaff95655b086f2d77 at=2026-10-26T13:49:47Z evidence=record/wave-46-asks-nothing/critic-evidence-3.md question=evidence reader=w46-T33 result=flag scope=piece
proved: kind=review head=6b7563afb608fccbdcf93beaff95655b086f2d77 at=2026-10-26T13:49:52Z evidence=record/wave-46-asks-nothing/critic-adversarial-3.md question=adversarial reader=w46-T33 result=flag scope=piece
deferred: record/wave-46-asks-nothing/critic-adversarial-3.md#1 S3 on "the 1.29.0 entry names neither T31's change to matrix-render's task rule nor that T31's landing moved the hand-holds window past the run's one counted task write, the 1.28.0 listed limit the close's total=0 will rest on"
moved: record/wave-46-asks-nothing/critic-adversarial-3.md#1 to=fixed row=T34 by=Person A at=2026-10-26T13:49:57Z
proved: kind=review head=6b7563afb608fccbdcf93beaff95655b086f2d77 at=2026-10-26T13:49:56Z evidence=record/wave-46-asks-nothing/critic-structure-3.md question=structure reader=w46-T33 result=flag scope=piece
proved: kind=check head=b9399de36ca2e574e03d949d470ec4e4bb382f13 at=2026-10-26T13:55:03Z evidence=record/wave-46-asks-nothing/release-check-b9399de36ca2e574e03d949d470ec4e4bb382f13.log result=fail
proved: kind=check head=93683c5e52b7098021f23426a35913c34d7a83a0 at=2026-10-26T14:03:12Z evidence=record/wave-46-asks-nothing/release-check-93683c5e52b7098021f23426a35913c34d7a83a0.log

## Handoff

handoff: .bionic/docs/record/handoffs/2026-10-25-wave-46-asks-nothing.md written 2026-10-26 07:16 PDT
