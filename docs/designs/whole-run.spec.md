---
governing-skill: agent-skills:spec-driven-development
sdlc-step: 2
epic: epic-23-bionic-tech-debt
wave: wave-45-whole-run
intent: build
rigor: single
review-cadence: once
fix-policy: S1,S2-on
fix-cap: 2
regression: yes
regression-override: Chris Lehman 2026-10-24 derived=no chosen=yes
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
archive-root: /Users/admin/bionic-archive
working-branch: wave/45-whole-run
integration-branch: main
base-sha: b4220d339c436fe160015927ce725be73d59cb62
seed: ideas/bionic-1.28.0-charter.md
requirements: specs/epic-23-bionic-tech-debt/wave-45-whole-run.requirements.md
design-ledger: record/wave-45-whole-run/design-ledger.md
release: 1.28.0
created: 2026-10-24
---
# bionic 1.28.0 — the measure counts every hand · spec (epic-23 wave-45)

## Goal

Build bionic 1.28.0 so that the hand-holds measure is honest over the whole close and reads zero. One rule applied five ways: the act that learns a fact writes every cell the fact fills, and every reader of that fact reads the one cell. The window is a span read from the plan, from the last build landing to `delivered:`. A landing is one event with a settlement list, written in one act. Every record write has its verb. One function reads each fact the card, the gate, the sitrep and the handoff share. A spawned tree describes itself, so a clear costs no landing. The Step-1 card prints each requirement's own sentence. Accepted when the 1.28.0 close reads `hand-holds: total=0` over the widened window with an empty hand-edit log, and the 1.26.0 close replay reaches `delivered:` reading zero with its own log part held by its tests.

## Context and Problem

The 1.26.0 close took eight hand acts the measure never saw whole, and 1.27.0 logged fourteen hand edits inside its own window (`record/wave-44-every-hand/assumptions.md`). Three maps at b4220d339 (`record/wave-45-whole-run/research-cards-and-facts.md`, `research-close-and-cells.md`, `research-tree-and-leftovers.md`) re-pinned every site and found what the charter did not say: the window's readers and close-out's order disagree, every waiver fixture is a shape the renderer never writes, the tree's record is keyed by the session twice, three readers the design needs do not exist (`auditor-wave:`, the eval-type tier map, a ruling writer), four criteria were already done or half done, and five ran into standing rules (the hook freeze, the net-zero doctrine, the engagement consent boundary, the reply line's last-line rule, the pinned window end). Each is a decision below or an attributed correction in the requirements.

## Design

### 1. Domain model

- **The window**: a span over the plan's record, from the last build landing to the plan's `delivered:` time, else now. Invariant: every write close-out makes is inside it, because close-out reads it last.
- **A landing**: one event with a settlement list: the findings its row was born for, the findings in any record at the same site, the findings carried to it, its matrix status cell, and its suite verdicts. Invariant: computed once, written in one act before the landing publishes; a separate verb for any of those cells is a correction and refuses what the landing settled.
- **A ruling**: a ledger entry `## Δ<k> — D<n> ruled "<reply>" (<who> <date>): <title>` that closes the ask on the register in the same act, whoever wrote the reply: the ruling verb, a card reply or an approval.
- **A tree's record**: written at spawn, keyed by the tree's path, naming its plan, its row, its worker and the spawning session. Invariant: every reader of a tree reads this record before the session's binding, and the binding is a check.
- **A requirement's concept**: the first paragraph under its heading, plain words, no backticked token. Invariant: the card refuses a requirement without one, never renders without it.
- **A fact reader**: one function per shared fact (review coverage, what an ask waits on, goal status, task title, goal measure, writer room, the scale's Patrol, the docs home, the eval type's tier), called by every surface that shows it.

### Interfaces

Verbs added: `decisions rule D<n> '<reply>'`, `known-limits-part <row>`, `approve plan '<reply>'`. Verbs changed: `landing-report --hand-holds` (window end), `row-landed`/`ready`/`land` (settlement, tree record, verdict order, event fields), `proof-add review` (verdict carry, `auditor-wave:`), `proof-add regression` (`stack-health:`), `matrix-render` (table growth, tier map), `discharge` (refuses at single rigor), `reply`/`approve` (share the ruling writer; re-put at a new head for every name), `step-field 8` (the triple, `--plan` on a delivered plan), `continuation-fill` (`--plan` on a delivered plan), `task-add`/`task-set` (title cap, owed line), `amend --suites=` (narrows), `arm` (reads the scale), `stop-orders.sh stopped` (the Tasks cell), `deliver` (a live row). Cards changed: `card.sh step1` (the sentence line, two refusals), `card.sh step2` (the decision's sentence line, the approach cell's cap, three refusals), `card.sh step3` (the task's sentence line, two refusals, shared with `task-add`/`task-set`), `card.sh step2 … explain` (the detail after the group). Texts changed: the decision skill's context paragraph and reply line; the Step-8 text; the session-start arm line at task scale.

### Approach

Theme 0 first and smallest: the decision skill's rule and its suite, then the Step-1 card's sentence and refusals with every Step-1 fixture given its sentences. Then the settlement function and the window, because the replay bed proves both and every Theme-2 verb lands on it: extend the replay to count its log by verb and to plant a second record, flip the window end and reorder close-out, then the landing's one settlement. Theme 2's verbs follow in any order, each on a fixture its own verb renders. Theme 3's readers are each one function and one planted divergence. Theme 4 re-keys the tree record and moves `ready`, `land`, `stopped` and the tick onto it. Theme 5 is last and is the first cut at the day boundary, in the order of its criteria. Every row carries its red test first on the replay or on a fixture the suite owns.

### Risks

- The window flip and the close-out reorder redden four pinned rows and move the hand-holds read past the roster wipe; if the wiped rosters held a fact the line needs, the read must take it before the wipe and the end after.
- Re-keying the tree's record touches every reader of the workspace file, and a pre-clear writer's session id is unverified; a reader that still filters by session silently finds nothing.
- The Step-1 refusal reddens every Step-1 fixture across six suites and one test that renders the live wave-44 requirements; the fixtures gain sentences and that test moves to a fixture, which is a day of suite work before the row is green.
- Theme 5 is twelve requirements and the first cut; if the day boundary falls inside it, the 1.28.0 entry restates the limits left, which is allowed and counted.

### 2. Component boundaries and interfaces

Ruled at the interview, in the ledger as Δ1 to Δ8:

- **D1 — The sentence under the row** Every requirement on the Step-1 card is followed by its own plain sentence, so the card reads as concepts. Every requirement opens on one plain paragraph; the Step-1 card prints it on its own line under the row, indented past the id, folded at the card's right edge; the row keeps its id, title and count; the rule that nothing prints under the count column holds for a row's own lines. (D1; REQ-33)
- **D2 — One settlement per landing** A landing settles everything it proves in one act, so nothing is settled by hand afterwards. The landing computes the whole list of what it proves and writes it in one act before it publishes: the findings it was born for (`units_born_findings`), the findings at the same `at=<path:line>` in other records at the review's head, the carried findings (`_line_carried_close`), its matrix status cell (`matrix_row_cell`) and its suite verdicts (`_line_hand_verdicts`); `finding-move`, `matrix-set` and `discharge` remain as corrections and refuse a cell the landing settled. (D2; REQ-4, REQ-5, REQ-23)
- **D3 — The tree describes itself** A worker's tree carries its own record of which run it belongs to, so a cleared conversation costs no landing. At spawn `spawn-worktree.sh create` writes the tree's record keyed by the tree's path, naming `plan=`, `row=`, `worker=` and `spawned-by=<session>`; `ready`, `land`, `stopped` and the tick read it first and treat the session binding as a check; a successor session finds the launch row by it; a closed plan stays admitted for close-out's own last landings; a tree whose plan differs from the binding is refused with both named. (D3; REQ-18, REQ-19)
- **D4 — Tiers: hermetic, one live** Every pin runs over fixtures the suite owns, and the one live row is the real close reading zero. Every behavior and replay pin is hermetic over fixtures the suite owns, each fixture produced by the verb whose output it stands for; one live row, the 1.28.0 close's own measure written by the close-out verb; prose rules static over the rendered files; no human row. (D4; REQ-3, REQ-33, REQ-24, REQ-31)
- **D5 — Consent guards a live run** Engagement protects a run that is still moving; a delivered run accepts its last two facts from any session that names it. The wave-36 ruling narrows: engagement is the consent boundary for a run still moving; a delivered run accepts its merge record (`step-field 8 --plan`) and its continuation marks (`continuation-fill --plan`) from any session that names it, and from nowhere else. (D5; REQ-10)
- **D6 — The collector lists the suites** The dispatch collector hands the wall the list of suites that exist, so the wall judges without looking at the disk. The dispatch's collector lists `tests/*.test.sh` once and hands the wall the set; the wall judges membership and reaches for nothing, so the hook freeze stands. (D6; REQ-26)
- **D7 — The verb prints what is owed** The verb that adds a row prints what the turn now owes, so the rule is read at the act. `task-add` ends on one line naming the task-list entry the turn owes, by title; the step text grows by nothing. (D7; REQ-30)

Defaulted by the orchestrator at the design step and surfaced at the card, in the ledger as Δ9 and Δ10:

- **D8 — The window ends last** The hand-holds window ends at the delivered time, and close-out reads it last. Close-out writes `delivered:`, wipes its rosters, then reads the hand-holds line as its final read with the end at `delivered:`; one function `hand_holds_window <plan>` gives both ends to the report and to close-out; the four rows that pin the release card as the end are rewritten to the new end. (D8; REQ-3)
- **D9 — Fixtures by the verb** Every fixture is produced by the verb whose output it stands for, never typed to look like it. Every waiver fixture is rendered by `matrix-render`; every Step-1 fixture carries sentences; the card test that renders the live wave-44 requirements renders a fixture copy instead; the `explain` fixture writes the detail after the group as a real spec does. (D9; REQ-3, REQ-31, REQ-33)
- **D10 — The dig-in on the reply line** The command to see the artifact rides the reply line itself, and nothing follows it. The decision skill's reply line carries the dig-in command after the options and forms, as the accepted D15 text does, and nothing follows it; AC-1.2 corrected. (D10; REQ-1)
- **D11 — One ruling writer** One function writes a ruling and closes its ask, whoever gave the reply. `decisions rule` writes the Δ heading through `decisions_put`'s numbering and closes the ask through `decisions_settle` in one function; `reply` at a release card and `approve` of a decision call the same function; the parser reads `D<n> settled by …` (wave 42 Δ20) as an entry; `decisions` joins the main-thread verb list. (D11; REQ-8)
- **D12 — Verdicts in a table** The critic's verdicts are a table the review registration reads into the matrix, so no verdict is copied by hand. The critic's evidence record carries its row verdicts as a table `| AC | verdict |` and its wave verdict as a `verdict:` line; `proof-add review --question evidence` at single rigor reads both into the matrix's auditor cells and the head's `auditor-wave:` line; `discharge` refuses at `rigor: single` naming `proof-add review`; the rehearsal gains a single-rigor fixture beside `door_world`. (D12; REQ-6)
- **D13 — Known limits from deferrals** The release entry's Known limits are rendered from the deferrals the run registered. `known-limits-part <row>` renders the entry's Known limits from `proof_findings_owed`'s deferrals and `deferral_sentence`, through `line_reviews_part`'s commit path; no stated-assumption record exists and none is invented. (D13; REQ-11)
- **D14 — The tier map** An eval type in words maps to its tier in one place, so the matrix renders every row. One function in `lib/scale.sh` maps an eval type in words to its tier (static, unit, hermetic, live, human as T0 to T4); `matrix-render` reads it and adds a table row for every Eval design row that lacks one before it writes the blocks. (D14; REQ-12)
- **D15 — Coverage has one reader** Whether a review is covered is read by one function on every surface. `facts_state` and `facts_cover` are the one reading of covered and failing; the release card's Reviews lines, the sitrep's reviews count and the judge call them; the live `blocks-rule` copy in `card.sh` is burned and the item re-ledgered as burned. (D15; REQ-13, REQ-17)
- **D16 — The integrate row's own part** The integrate row's own writer publishes the reviews part before the push, and no other writer may. The walls admit `reviews-part` to the main thread and to the integrate row's own writer (the own-row precedent `_bsg_own_deliver`) and refuse any other writer with the row named; the order reviews part, push, `gh pr create` is pinned in the Step-8 text and the integrate row's brief; close-out's merge-scale path publishes before its merge readback. (D16; REQ-15)
- **D17 — A closed ask keeps its answer** A closed ask keeps the answer it was given, so it never reads as waiting on you. The register's closed line carries `answer=`; `ask_waits_on` reads it on open and closed lines alike; the three waiting-on-you readers call it. (D17; REQ-16)
- **D18 — Stale is a head** An approval is stale when the head has moved since it was given, and every stale approval is asked again. An approval is stale when its recorded head differs from the current head (`proof_approved_head`); `reply` after a second release card re-puts release and merge; `approve <name>` at a new head re-puts for every name. (D18; REQ-21)
- **D19 — Plant at the base** The dirtying-check pin is planted where the check runs, at the release base. The check-dirtied pin plants the dirtying release check where the check runs, at the release base, and expects the door's refusal; the second unpinned arm in the poker is pinned by the same row. (D19; REQ-22)
- **D20 — Keys name verbs** Every step field knows the verb that writes it, and an unknown key's refusal names it. `step-field` holds a key-to-verb table; `step-field 8` takes the triple in one call through `units_step_fields --replace`; an unknown key's refusal names the verb from the table. (D20; REQ-25)
- **D21 — The scale's cap in one place** The writer cap, with the scale's own limit, is read from one function by every surface that counts room. `fill_cap` reads the scale's writers cell; the dispatch wall drops its own fallback of three and calls it; the FILL names idle slots behind one pending row. (D21; REQ-28)
- **D22 — The docs home is prose** A commit that touches only the docs home is prose to the judge. `_proof_release_path` stops hard-coding `docs/adrs/` as release; `docs_tracked` decides, so a commit wholly under the docs home is prose to the judge for every question and the regression. (D22; REQ-29)
- **D23 — A period before a lowercase** A title sentence ends at a period followed by a capital, so an abbreviation never cuts it. The title reader ends a sentence at a period followed by a space and an uppercase letter or the end; `vs. the` does not end it; no word list. (D23; REQ-32)
- **D24 — Green-at was right** The green-at refusal was right, so the criterion keeps it and narrows to the event fields. A design-time probe showed a linked tree's commit resolves from the root (`git rev-parse` over the shared object store) and is refused only when it is not an ancestor of the landing; AC-27.1 narrows to the ready event's `branch=` and `tree=`. (D24; REQ-27)
- **D25 — One Patrol reader** Whether a scale has a Patrol is read from one function by arming, the session start and the tick. `scale_patrol <plan>` in `lib/scale.sh` says whether the scale has a Patrol; `arm`, the session-start text and `tick_patrol_owed` call it; the session-start rows that pin the arm line on a task-scale plan are rewritten. (D25; REQ-20)
- **D26 — Only land reorders** The by-hand landing writes its verdicts before it publishes, as the other landing verb already does. `land --by-hand` writes its verdicts before it publishes, as `row-landed --by-hand` already does; AC-23.1 narrowed. (D26; REQ-23)

- **D27 — The design reads as concepts** Every decision on the Step-2 card is followed by its own plain sentence, and each requirement's eval line is its proof in plain words, so the design card reads as concepts. The decision's first sentence after its title is the concept, plain and without a backticked token, and the card prints it under the row as D1 prints a requirement's; the Eval design's Approach cell is the requirement's proof in one plain line of at most 60 columns, the same on every row of the requirement, and the Eval cell keeps the command and its observation. Ruled by Chris at the Step-2 card (Δ11). (D27; REQ-34)
- **D28 — The plan reads as concepts** Every task on the Step-3 card is followed by its own plain sentence, so the plan card reads as concepts. The Tasks cell's second sentence, after the title and before the detail, is the concept, plain and without a backticked token; the card prints it under the row as D1 and D27 print a requirement's and a decision's; `task-add` and `task-set` refuse a cell without it through the cap's channel. Ruled by Chris at the Step-3 card (Δ12). (D28; REQ-35)

### 3. Ownership table

| concept | owning module (SSoT) | reuses | rendering surfaces | agreement test |
|---|---|---|---|---|
| the hand-holds window | `hooks/poker/line.sh` `hand_holds_window` | `_HH_PLACE_AWK` `hh_place`/`hh_take`; close-out's `delivered:` awk | `landing-report --hand-holds` · close-out's continuation line · the release card | `close-replay.test.sh` window rows: the end is `delivered:` on all three, a planted post-card act counts |
| a landing's settlement | `lib/line.sh` `line_settle` in the landing path | `units_born_findings`, `_proof_moved_fixed`, `_line_carried_close`, `matrix_row_cell`, `_line_hand_verdicts` | the register · the matrix table · the landing record | `close-replay.test.sh` second-record row: no move after the landing, `total=0`; `landing-line-2.test.sh` planted same-site finding |
| review covered or failing | `lib/proof.sh` `facts_state` / `facts_cover` | `cover_basis` in `judge.sh` | the release card's Reviews · the sitrep's reviews count · the judge | `release-approval.test.sh`: a planted failed-then-fixed review reads covered on all three |
| what an ask waits on | `lib/owed.sh` `ask_waits_on` | field 5 of `sitrep_asks` | the close line · waste · the held words · the card | `asks.test.sh` §ONE-BLOCKS: a closed waiver answered no reads event on all four |
| goal status, task title, goal measure | `lib/plan.sh` `plan_goal_status`; `card.sh` `_card_title`; `lib/plan.sh` `plan_goal_measure` | `task_name` retired into `_card_title` | the sitrep sheet · the card | `sitrep-card.test.sh`: a planted divergence in any one reddens |
| a ruling | `hooks/poker/sitrep.sh` `decisions_rule` | `decisions_put` numbering, `decisions_settle`, `user_said` | the ledger Δ heading · the register · `reply` · `approve` | `asks.test.sh`: a card-ruled decision has its Δ line and a closed ask |
| the tree's identity | `lib/worktree.sh` tree record keyed by path | `_wt_proofs_row`, `open_runs`, `plan_working_branch` | `ready` · `land` · `stopped` · the tick | `worktree.test.sh`: a tree spawned by one session lands from another |
| writer room | `lib/fill.sh` `fill_cap` | `scale_cell <scale> writers` | the tick's FILL · the dispatch wall · the stop wall | `slots.test.sh`: a task-scale plan's fourth writer is refused by all three |
| the scale's Patrol | `lib/scale.sh` `scale_patrol` | `tick_patrol_owed` | `arm` · the session-start text · the tick | `session-start.test.sh`: a task-scale plan prints no arm line and `arm` writes no stamp |
| the eval type's tier | `lib/scale.sh` `tier_of_eval_type` | none fits: the ladder exists only as prose in `steps/2.md` | `matrix-render` · the Step-2 card's counts | `door-card.test.sh`: a row typed in words renders at its tier |
| a decision's sentence and a requirement's eval line | `card.sh` decision parser (`flush_dec`) and the eval parser | the requirement-sentence line of D1, `firstsent` | the Step-2 card's Decisions and Eval design rows · `explain` · `show evals` | `card.test.sh`: with, without, backticked, and an approach over the cap |
| a task's sentence | `card.sh` `_card_title`'s cell reader | the requirement-sentence line of D1 | the Step-3 card's Tasks rows · `show task` · `task-add`/`task-set` refusals | `card.test.sh` + `session-poker-5.test.sh`: with, without, backticked at both |
| the requirement's sentence | `card.sh` requirement parser | the theme-opener predicate in the governing-skill hook | the Step-1 card row · `explain` | `card.test.sh`: with, without, backticked |
| the title rule | `card.sh` `_card_title_check` | `_card_titles_or_refuse` | the cards · `task-add`/`task-set` | `card.test.sh` + `session-poker-5.test.sh`: a 31-column title is refused with the same words at both |
| the Known limits | `hooks/poker/line.sh` `known_limits_part` | `line_reviews_part`'s entry and commit path, `deferral_sentence` | the release entry · the continuation | `landing-line-1.test.sh`: a deferred sentence is in the entry after the part |
| a suite that exists | the dispatch collector's listing | `suite_name`, `_line_suites` | the dispatch wall · `amend` | `dispatch-preflight-2.test.sh`: a well-formed name with no file is refused; the wall performs no I/O (`no wall performs I/O` arm) |
| what the turn owes after task-add | `hooks/poker/plan.sh` `task-add`'s last line | the landing's `owed:` line shape | the verb's print | `session-poker-5.test.sh`: the line names the title |

### 4. Rejected alternatives

- A landing that calls the verbs in turn (D2 option 2): the hand sequence automated, with its partial failures. Settlement derived on read (option 3): three derivations, nothing for the measure to count.
- Identity from the plan's table (D3 option 2): a second source and the roster still filed under the dead session. Mandatory resume (option 3): keeps the hole and adds a rule to remember.
- A human acceptance row (D4 option 2): attests the one number by hand. Live rows over the run's own record (option 3): tests that cannot be re-run.
- Keeping the consent boundary and naming the bind door (D5 option 2): a step after every close. Never disengaging (option 3): every wall reads a dead run as live.
- The wall reaching for the file (D6 option 2): the first new reach since the freeze. No check (option 3): an hour of work on an unmeetable contract.
- The sentence back with a named cut (D7 option 2): a rule where it is weakest. A doctrine waiver (option 3): a rule spent to avoid a design.
- The sentence folded inside the title column (D1 option 1): a plain sentence in thirty-column strips. The sentence as the row (option 3): the title the matrix and the sitrep cite disappears.
- A word list for abbreviations (D23): the card check's word lists are in Not Doing by Chris's ruling at Step 1; a case rule has no list to maintain.

### 5. Assumptions

- The replay can plant a second review record and deal it its question on the roster, as `proof-add` demands; if it cannot, AC-4.3 is proved on a landing fixture instead.
- The plan file is readable after close-out disengages and after the roster wipe, so the window's last read and the two delivered-run verbs have their facts.
- The wiped rosters hold nothing the hand-holds line needs; if they do, the line takes that fact before the wipe and only the end after.
- The pre-clear writer's session id is the spawning session's and is written at spawn, so the tree record's `spawned-by=` is known.
- The collector's directory listing is not a wall's reach under the freeze, because the collector gathers and the wall judges.
- The net-zero doctrine wall does not count a verb's printed line.
- Every Step-1 fixture can carry sentences without changing any other card's bytes, because the sentence line is drawn inside the batch as a second line.
- Chris's design interview is this ledger, Δ2 to Δ10; no waiver of it was given or asked.

### ADR pointers

- None yet. Step 7 writes two: the settlement rule (D2, the act that learns a fact writes every cell the fact fills) and the consent-boundary amendment (D5), each under the epic's ADR directory.

## Eval design

| Requirement | Approach | Criterion | Eval type | Eval | Fails when |
|---|---|---|---|---|---|
| REQ-1 | a decision brief names its referent and its dig-in | AC-1.1 | static | `/usr/bin/grep -n 'referent\|why the rule bites' payload/skills/decision/SKILL.md` → both phrases present, the Altitude rule scoped to Goal and Options | the rule line is deleted from the template and rendered |
| REQ-1 | a decision brief names its referent and its dig-in | AC-1.2 | hermetic | `tests/decision-skill.test.sh` §DIGIN → the brief whose reply line carries no command is refused; one with a line after the reply line is refused | the refusal arm is removed and both pass |
| REQ-1 | a decision brief names its referent and its dig-in | AC-1.3 | hermetic | `tests/decision-skill.test.sh` §REFERENT → the referent-less brief refused, D15's text admitted | the D15 text is refused, or the referent-less brief passes |
| REQ-2 | the replay's log is checked by named verbs | AC-2.1 | hermetic | `tests/close-replay.test.sh` CL-8, VB-1, VB-2 → green, each naming the verbs the log must hold | a verb the replay ran is removed from the log and the row stays green |
| REQ-3 | the window ends at delivered and counts every act | AC-3.1 | hermetic | `tests/close-replay.test.sh` WINDOW rows → the line reads `(delivered:)` as its end, a planted act after the card counts | the end is the card again |
| REQ-3 | the window ends at delivered and counts every act | AC-3.2 | hermetic | `tests/landing-line-1.test.sh` §WAIVERS → four rendered waivers read `waivers=4` | the header regex is made bare-only and the row reads 0 |
| REQ-3 | the window ends at delivered and counts every act | AC-3.3 | hermetic | `tests/landing-line-1.test.sh` §MOVED → before outside, after inside | the placement is by line order, not time |
| REQ-3 | the window ends at delivered and counts every act | AC-3.4 | unit | `/usr/bin/grep -c '_LINE_FIELDS_AWK' payload/scripts/lib/units.sh` → 1; `tests/landing-line-1.test.sh` §ORDER reddens when the two orders disagree | a second parser is added, or the orders are swapped and nothing reddens |
| REQ-3 | the window ends at delivered and counts every act | AC-3.5 | live | `bash payload/hooks/session-poker.sh landing-report --hand-holds` at the 1.28.0 close → `total=0`, the continuation line written by close-out | the close reads above zero or the line is typed |
| REQ-4 | a landing closes every finding it answers | AC-4.1 | hermetic | `tests/landing-line-2.test.sh` §SAMESITE → fixed after the landing, no move needed | the second record's finding stays open |
| REQ-4 | a landing closes every finding it answers | AC-4.2 | hermetic | `tests/landing-line-2.test.sh` §CARRIED → fixed at the row's landing; a carry to a landed row closes at once | either stays open |
| REQ-4 | a landing closes every finding it answers | AC-4.3 | hermetic | `tests/close-replay.test.sh` SR row → no `finding-move` after the landing, `total=0` at `delivered:` | the log shows a move after the landing |
| REQ-5 | a landing marks its own matrix cell | AC-5.1 | hermetic | `tests/landing-line-2.test.sh` §CELL → the table's status cell reads `discharged` after one landing | the cell still reads `pending` |
| REQ-5 | a landing marks its own matrix cell | AC-5.2 | hermetic | `/usr/bin/grep -c 'matrix-set.*status=' tests/lib/rehearsal.sh` → 0; `tests/close-replay.test.sh` matrix row reads `discharged` | the rehearsal calls `matrix-set` on a built row |
| REQ-6 | the review registration carries the verdicts | AC-6.1 | hermetic | `tests/session-poker-4.test.sh` §VERDICTS → the auditor cells carry the verdicts, the head carries `auditor-wave:` | a CONFIRMED row still needs `discharge` |
| REQ-6 | the review registration carries the verdicts | AC-6.2 | hermetic | `tests/session-poker-4.test.sh` §DISCHARGE → refused naming `proof-add review`; `tests/lib/rehearsal.sh` single fixture reaches Verify | `discharge` writes a cell at single rigor |
| REQ-7 | stack health comes from the recorded proof | AC-7.1 | hermetic | `tests/session-poker-4.test.sh` §STACK → `stack-health:` carries the proof's head, pass and total | the stub survives |
| REQ-8 | a ruling is one verb, however it arrives | AC-8.1 | hermetic | `tests/asks.test.sh` §RULE → the Δ heading parses as an entry and the ask is closed | the heading is not an entry or the ask stays open |
| REQ-8 | a ruling is one verb, however it arrives | AC-8.2 | hermetic | `tests/asks.test.sh` §SHARED → both leave a Δ line | a card-ruled decision has no ledger entry |
| REQ-8 | a ruling is one verb, however it arrives | AC-8.3 | unit | `tests/asks.test.sh` §SETTLED → an entry with the line's date | the heading parses as no entry |
| REQ-9 | the ADR list and the approver are rendered | AC-9.1 | hermetic | `tests/close-out-3.test.sh` §ADRS → `adrs:` rendered at the advance, the epic row written | `epic_row_missing` refuses |
| REQ-9 | the ADR list and the approver are rendered | AC-9.2 | hermetic | `tests/session-poker-5.test.sh` §APPROVED-BY → the line the walls read, with the user's words | the only writer is the editor |
| REQ-10 | a delivered run accepts its last facts by name | AC-10.1 | hermetic | `tests/close-out-4.test.sh` §DELIVERED → both write; the same verbs on a live plan unengaged are refused | either prints NOT-ENGAGED on a delivered plan |
| REQ-10 | a delivered run accepts its last facts by name | AC-10.2 | hermetic | `tests/close-out-4.test.sh` §MARKS → only the five person-owned marks remain | a fillable mark reads `<fill:` |
| REQ-11 | Known limits are rendered from deferrals | AC-11.1 | hermetic | `tests/landing-line-1.test.sh` §KNOWN → each `stated=` sentence in the entry, committed on the branch | a sentence is absent after the part |
| REQ-12 | the matrix table grows by the render | AC-12.1 | hermetic | `tests/door-card.test.sh` §GROW → the table gains the row at its tier before the blocks | the row is left out or the type refused |
| REQ-13 | one coverage reader on every surface | AC-13.1 | hermetic | `tests/release-approval.test.sh` §COVERED → the Reviews line reads covered naming the landings | it still prints `failing` |
| REQ-13 | one coverage reader on every surface | AC-13.2 | unit | `/usr/bin/grep -rn 'blocks' payload/scripts/card.sh hooks/poker/sitrep.sh` → one site; the sitrep's count agrees with the card over the same fixture | two sites, or the counts disagree |
| REQ-14 | a live review row delivers when covered | AC-14.1 | hermetic | `tests/session-poker-4.test.sh` §LIVE → closed when covered, refused naming the uncovered question otherwise | the row stays pending with every question covered |
| REQ-15 | the integrate row publishes its part first | AC-15.1 | hermetic | `tests/bash-walls.test.sh` §PART → main thread admitted, integrate row's writer admitted, a build row's writer refused with the row named | the build writer passes or the integrate writer is refused |
| REQ-15 | the integrate row publishes its part first | AC-15.2 | hermetic | `tests/close-out-3.test.sh` §ORDER → the part precedes the push and the merge readback | the part lands after either |
| REQ-15 | the integrate row publishes its part first | AC-15.3 | static | `/usr/bin/grep -n 'reviews-part' payload/skills/canonical-sdlc/steps/8.md` and the rendered brief → both name it before the push | the grep is empty |
| REQ-16 | a closed ask never waits on you | AC-16.1 | hermetic | `tests/asks.test.sh` §ONE-BLOCKS → zero waiting-on-you minutes on all three readers | the closed ask raises the minutes |
| REQ-16 | a closed ask never waits on you | AC-16.2 | hermetic | `tests/card.test.sh` §SETTLED → `card.sh step3` over a plan with `approved-by:` opens no ask; `step1` over a plan at `current: 3` opens none; a render under a writer's name opens none; the sweep closes every step ask | an ask opens on any of the three |
| REQ-17 | one reader per sitrep fact | AC-17.1 | hermetic | `tests/sitrep-card.test.sh` §ONE-READER → each of the three reddens on its planted divergence | a surface keeps its own copy |
| REQ-18 | a tree lands from any session | AC-18.1 | hermetic | `tests/worktree.test.sh` §SUCCESSOR → `ready` lands reading the tree's record | it refuses `no-bound-plan` or `no-launch-row` |
| REQ-18 | a tree lands from any session | AC-18.2 | hermetic | `tests/worktree.test.sh` §MISMATCH → refused naming both; close-out's landing admitted | the stale tree lands silently |
| REQ-19 | stopped finds the tree by the plan | AC-19.1 | hermetic | `tests/stop-orders.test.sh` §TREE → the tree found by the Tasks cell, removed, and named | the tree is left standing in silence |
| REQ-20 | no Patrol at task scale | AC-20.1 | hermetic | `tests/session-start.test.sh` 14a rows rewritten → no arm line and no stamp at task scale | the task-scale session is told to re-arm |
| REQ-21 | every stale approval is asked again | AC-21.1 | hermetic | `tests/release-approval.test.sh` STALE rows rewritten → release and merge both re-put and recorded | "An approval is recorded once" |
| REQ-21 | every stale approval is asked again | AC-21.2 | hermetic | `tests/release-approval.test.sh` §STALE-NAME → re-put, not accepted | accepted unchanged |
| REQ-22 | a dirtying check is refused at the door | AC-22.1 | hermetic | `tests/door-landing.test.sh` §DIRTIED → the door's `check-dirtied` refusal | the plant lands |
| REQ-23 | verdicts are written before the publish | AC-23.1 | hermetic | `tests/worktree.test.sh` §HAND → the verdicts are written before the publish, the ask closes | the ask stays open after the publish |
| REQ-24 | swapped counts are refused everywhere | AC-24.1 | hermetic | `tests/sitrep-card.test.sh` BI1 → the swapped line refused | the swap passes |
| REQ-24 | swapped counts are refused everywhere | AC-24.2 | hermetic | `tests/words.test.sh` §BIND and the rehearsal's card check → red on the swap | either lacks the row |
| REQ-25 | the Step-8 triple in one call, keys naming verbs | AC-25.1 | hermetic | `tests/session-poker-4.test.sh` §TRIPLE → one call writes all three; `foo=` refused naming the verb | three calls needed or no verb named |
| REQ-26 | a suite that does not exist is refused | AC-26.1 | hermetic | `tests/dispatch-preflight-2.test.sh` §EXISTS → refused by the wall from the collector's set, no I/O in the wall; `amend --suites=` narrows and `lands_on=` follows | the name passes or `amend` only widens |
| REQ-27 | the ready event carries branch and tree | AC-27.1 | hermetic | `tests/session-poker-4.test.sh` §EVENT → the ready event carries both | `branch=- tree=-` |
| REQ-28 | one writer-room arithmetic | AC-28.1 | hermetic | `tests/slots.test.sh` §ROOM → the FILL, the wall and the stop wall agree; idle slots named | a FILL names a row the wall refuses |
| REQ-29 | a docs commit owes no regression | AC-29.1 | hermetic | `tests/bash-walls-egd.test.sh` §PROSE → `cover … prose` for every question and the regression | the commit owes a regression run |
| REQ-30 | the cap and the owed line at task-add | AC-30.1 | hermetic | `tests/session-poker-5.test.sh` §CAP → refused with the card's words, the suffix counted | a 31-column title lands |
| REQ-30 | the cap and the owed line at task-add | AC-30.2 | hermetic | `tests/session-poker-5.test.sh` §OWED → the line names the row's title | no owed line |
| REQ-31 | explain prints the detail | AC-31.1 | hermetic | `tests/card.test.sh` DESIGN-TITLES rewritten → the detail after the group prints | only the title, serves and ADR print |
| REQ-32 | an abbreviation does not cut the title | AC-32.1 | unit | `tests/card.test.sh` §ABBR → taken whole and refused over the cap | drawn as `Draw the facts vs` |
| REQ-33 | the requirements card reads as concepts | AC-33.1 | hermetic | `tests/card.test.sh` §SENTENCE → without a paragraph refused, with a backtick refused, the requirement named | either renders |
| REQ-33 | the requirements card reads as concepts | AC-33.2 | hermetic | `tests/card.test.sh` §SENTENCE → the sentence under the row, indented past the id, folded at the right edge; row 52's first-line bytes unchanged | the sentence is truncated or folded in the title column |
| REQ-33 | the requirements card reads as concepts | AC-33.3 | hermetic | `bash payload/scripts/card.sh step1 <requirements>` → rc 0 with every row's sentence; the three planted cases in `card.test.sh` | a planted case passes or the fixture is a live plan |

| REQ-34 | the design card reads as concepts | AC-34.1 | hermetic | `tests/card.test.sh` §DSENTENCE → a decision without a sentence refused, one with a backtick refused, the decision named | either renders |
| REQ-34 | the design card reads as concepts | AC-34.2 | hermetic | `tests/card.test.sh` §DSENTENCE → the sentence under the decision row, indented past the id, folded at the right edge; the row's first line unchanged | truncated or folded in the title column |
| REQ-34 | the design card reads as concepts | AC-34.3 | hermetic | `tests/card.test.sh` §APPROACH → a cell over 60 columns refused, one with a backtick refused, two approaches on one requirement refused | any of the three renders |
| REQ-34 | the design card reads as concepts | AC-34.4 | hermetic | `bash payload/scripts/card.sh step2 <spec>` → rc 0 with every decision's sentence and every requirement's line; the planted cases in `card.test.sh` | a planted case passes or the fixture is a live spec |

| REQ-35 | the plan card reads as concepts | AC-35.1 | hermetic | `tests/card.test.sh` §TSENTENCE → a row without a sentence refused, one with a backtick refused, the row named | either renders |
| REQ-35 | the plan card reads as concepts | AC-35.2 | hermetic | `tests/card.test.sh` §TSENTENCE → the sentence under the task row, indented past the id, folded at the right edge; the row's first line unchanged; `show task` prints the whole cell | truncated or folded in the title column |
| REQ-35 | the plan card reads as concepts | AC-35.3 | hermetic | `tests/session-poker-5.test.sh` §TSENTENCE → `task-add` and `task-set` refuse a cell with no sentence or a backticked one, with the card's words | the cell lands |
| REQ-35 | the plan card reads as concepts | AC-35.4 | hermetic | `bash payload/scripts/card.sh step3 <plan>` → rc 0 with every row's sentence; the planted cases in `card.test.sh` | a planted case passes or the fixture is a live plan |

## Not Doing

- The purity wave's collector for every wall: D6 gives the dispatch wall one presented fact; the rest of the freeze's debt waits for its own wave.
- A verb that records a stated assumption: no such record exists and the Known limits render from deferrals alone (D13).
- A `## Design` wall at task scale: none exists and none is added; the card is the one approval of the design.
- The 1.26.0 limits Chris ruled out at Step 1 (7, 19, 21, 24, 25) and the card check's word lists.
