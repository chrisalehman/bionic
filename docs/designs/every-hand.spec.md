---
governing-skill: agent-skills:spec-driven-development
sdlc-step: 2
epic: epic-23-bionic-tech-debt
wave: wave-44-every-hand
intent: build
rigor: single
review-cadence: once
fix-policy: S1,S2-on
fix-cap: 2
regression: yes
regression-override: Chris Lehman 2026-10-23 derived=no chosen=yes
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
working-branch: wave/44-every-hand
integration-branch: main
base-sha: dd425be64
seed: ideas/bionic-1.27.0-charter.md
requirements: specs/epic-23-bionic-tech-debt/wave-44-every-hand.requirements.md
design-ledger: record/wave-44-every-hand/design-ledger.md
release: 1.27.0
---
# bionic 1.27.0 — the sitrep changes what you do next · spec (epic-23 wave-44)

## Goal

Ship bionic 1.27.0 so that a sitrep is the handful of facts that change what the user does next, drawn by code with the model's judgment on top, in under thirty seconds. The register stores the answer given to an ask and one function says whether the ask waits on the user or on an event; only the first can block the user or drive the call. The card verb draws every row that is a fact from the saved sheet, the model writes seven lines of judgment, and the check refuses only what would make the card false. The Assessment opens on what the wave is for, read from the plan. Accepted when a fixture shaped like the flock-app-app run draws the approved mock-up in under 40 rows and three real sitreps take under thirty seconds each.

## Context and Problem

The requirements (REQ-1 to REQ-10) and three records carry it: `record/wave-44-every-hand/research-sitrep-concept.md` (the card never states what the wave is for), `research-sitrep-latency.md` (95 s median, 90% model output: first judgment 43%, refusal rewrites 34%, retyping the card 14%) and `research-sitrep-sites.md` (the sites at dd425be64). The register's `owed/v1` line has no field for an answer or for what an ask waits on; its kind is the key prefix alone (sites §REQ-1). A waiver answered "no" at the release card reaches only the approval page (`withheld:`, plan.sh:2989-2992); the `waive:<q>` item stays open and holds the merge. Three rules say what blocks the user: the sheet (sitrep.sh:1616), the card's fallback (card.sh:3139) and the handoff head (sitrep.sh:2123, yes for any open ask); the Patrol's `owed: <n>` counts every ask. The card verb accepts eight tags, requires a row per step, per open task, per metric and per open ask, binds every metric number to a word, and refuses a row over 100 columns though a fold helper exists (card.sh:2373). The rulings are the ledger's Δ1, Δ6 to Δ11: D1 "1", D6 "1", D7 "1", D8 "1", D9 "1", the cut (Δ8) and the check's rule (Δ11). The frame's D2 to D5 were named for the measure run and withdrawn with the cut.

## Design

Three owners, one each. Structure belongs to code: the card verb draws the head, the task list, the Metrics table, Blocked on you, the counted line of items waiting on events and the close's two time lines from the saved sheet, so no row that is a fact can be refused (D6). Words belong to the model: seven free lines, the purpose, the call, the grade, one to three points, a recommendation per ask that waits on the user, and the close's condition (D6, D7). Truth belongs to the check, and only truth: it refuses a number no sheet value holds, a state the sheet denies, a forbidden word, and a missing purpose, call, grade or close, and repairs everything else, folding a long line, keeping a fourth point with a note, drawing an unrecommended ask as the ask alone (Δ11). Under it, the register learns what an ask waits on by storing the answer given to it and deriving the rest in one function every reader calls (D8). The sheet gains the plan's Goal and each theme's opener, the goals reader a per-theme count and an "on course" word, task scale one goal (D1). Five decisions, one rule, 22 evals: 2 static, 10 unit, 9 hermetic, 0 live, 1 human. Added at Step 4 on Chris's word (Δ13): the plan card prints a title per task, REQ-11.

### 1. Domain model

- **An ask's answer.** What the user has said to an ask that is not yet closed: `no` to a waiver, `carry` to a finding, with the row or event named. Stored on the ask's open `owed/v1` line as `answer=<word> answered=<ISO> [event=<what>]`, by the verb that takes the answer (`reply`, `disposition`, `finding-move`). Invariants: an answer never closes the ask; the ask closes at the event it names, as it closes today; a re-open of an open key keeps its answer (`owed_open` is idempotent); a fresh open after a close starts with none.
- **What an ask waits on.** `user`, or `event <what>`. Derived, never stored, by `ask_waits_on <key>`: a decision, an approval, a gate, a ruling, a matrix ruling, a declared-missed goal, an unanswered waiver and an unanswered finding wait on the user; a waiver answered no waits on its review's next run; a finding answered carry waits on its row's landing, or on the release card when no row is named; a `carry:` item waits on the release card; `hold:merge` waits on what the waivers that hold the merge wait on; `delivered:` on nothing. Invariant: every reader of "blocked", the call's check, the handoff head and the Patrol's count call this one function.
- **A fact row.** A row of the card drawn from a sheet line by the card verb: head, step and task rows, the five Metrics lines, Blocked on you, the counted line, the close's predicted and basis lines. Invariant: a fact row is never in the judgment and never checked; it cannot be refused because nobody typed it.
- **The judgment.** Seven tags: `purpose:`, `call:`, `grade:`, `point:` (one to three), `ask <key>:` (one per ask that waits on the user), `close:` (the condition line). Invariants: free prose; a number in it is bound to a sheet value by word and place; a forbidden word refuses; a missing purpose, call, grade or close refuses by name; any other tag refuses by name; nothing else refuses.
- **The purpose.** What the wave is for and whether it is on course: the model's line, written from `run.goal` and the `goal:` lines, first under the Assessment (D1).
- **A theme's standing.** `met`, `on course` (at least one criterion discharged, none missed), `not measured` (none discharged), `not met`; one word on the sheet, the sitrep card and the release card.

### Interfaces

- `lib/owed.sh`: `owed_answer <key> <word> [<event>]` rewrites the open line with `answer= answered= event=`; `owed_answer_of <key>` prints the answer fields; `ask_waits_on <key>` prints `user` or `event <what>` from the key's kind and its answer. `_owed_list_file` keeps its four columns.
- `reply` (hooks/poker/plan.sh:2928): an other-side `-` on a waiver row calls `owed_answer waive:<q> no "review <q> re-run"` beside its `withheld:` line. `disposition … defer|carry` and `finding-move … to=carried row=<T>` call `owed_answer finding:<id> carry "<T> lands"` and leave the item open; the landing of `<T>` closes it (line.sh:775's arm, widened); `to=fixed` closes at once as today.
- `sitrep_asks` prints a sixth field, `waits=`, from `ask_waits_on`; `sitrep_ask_lines` writes `blocks=<yes|no>` from `holds != nothing && waits == user` and appends `waits=user|event <what>` as the last field; the card's A record gains the field after `blocks=`. `_card_sitrep_load`'s re-derivation at card.sh:3139 is deleted. `ho_state` (sitrep.sh:2123) prints `Blocked on you: yes` only when some ask has `blocks=yes`. `sitrep_status` prints `owed: <n> on you · <m> on events`; the tick line carries both.
- `sitrep card`: `decisions_settle`, read the saved sheet, refresh its `ask:` lines through `sitrep_asks` alone (no second `sitrep_gather`), run card.sh. card.sh `_card_sitrep_draw` draws the fact rows from the S, T, R and A records and the metric lines; `_card_sitrep_judge` accepts the seven tags; `_card_sitrep_check` folds through `_card_hang` and refuses only the four falsehoods; the number binding of `_card_sitrep_metrics_judge` becomes `_card_bind <line> <values>` applied to every judgment line against every measured sheet value, by word and place.
- The Metrics table: five lines, label at column 3, two value groups separated by `·` and a gap, numbers from the sheet's measured values only, the pace comparison first in the Pace line, the Goals line per theme (`<theme> k of n[, REQ-a open]`) or, at task scale, `the run k of n`.
- `sitrep_gather`: `run.goal:` from the plan's `## Goal` first paragraph (the parse at card.sh:843-847 moved to lib/plan.sh as `plan_goal_paragraph`); `goal:` lines gain `for=<opener>` last, from `plan_themes` reading the first body line under each `## <theme>`; at task scale `plan_themes` yields one theme, `the run`, over every REQ with a matrix row. `plan_goal_status` maps pending with k ≥ 1 to `on course`; the release card's mark map (hooks/poker/plan.sh:2516-2524) learns the word. `tick_owed_goals` opens no `decide:goal:` for a measured goal whose miss is a declared red (a `Lands-red:` row's debt line, line.sh:828).
- `skills/sitrep/SKILL.md`: the two verbs, the seven lines, the Purpose question in place of the Goals question, the standard ("the handful of facts that change what you do next"), "nothing tonight" when every open ask waits on an event, show the tool's card once inside one fenced block and never retype it. `agents-src/templates/commands/help.md.tmpl:40` follows.
- The cards (Δ13, Δ14; REQ-11 to REQ-14): a `## Tasks` cell opens on a title of at most 30 characters, then a period and the detail; `card.sh step3` prints the title alone, `serves` in its own column and consecutive ids in `depends` as a range, refusing a longer title with its row and length named, never cutting it; `show task <n>` prints the whole cell; `steps/3.md` states the rule beside the Tasks table. The requirements card the same way: a `### REQ-<n> — <title>` title of at most 30 characters, printed with its id and criteria count on one line, the provenance under `explain <requirement>`, the rule in `steps/1.md`; its Not Doing items the same, `explain not-doing` for the reasons. The design card the same: a decision's title of at most 30 characters, the detail under `explain <decision>`, and the Worth-your-eye section renamed Risks, each item the model's own judgment in one to three sentences, drawn whole with no cap, the rule in `steps/2.md`. On every card a longer title is refused with the item named, never cut. The sitrep's task rows read the same title, since the sheet's `desc` is the cell cut at its first punctuation.
- `tests/sitrep-card.test.sh` §MOCKUP: a sheet shaped like the flock-app-app card (17 open tasks, 14 event-waiting asks, a refused waiver holding the merge, 54 added tasks) and a seven-line judgment draw the mock-up: one call line, the task list, five Metrics lines, purpose plus points plus one counted line, `None` naming the event, three close lines, under 40 rows.

### Approach

The mock-up fixture first (T1), red at the base on the unknown `purpose:` tag, because every later row is judged by the card it draws. The register next (T2): the answer field, `ask_waits_on`, the three readers and the Patrol count on one function, `reply` and `disposition` writing the answer, the landing closing a carried finding. Then the draw and the check (T3, T4): the fact rows drawn from the saved sheet, the seven tags, the binding generalised, the fold, the four refusals and nothing else, the card verb no longer re-gathering. Then the goals (T5): `run.goal`, `for=`, the per-theme Goals line, "on course", task scale, the declared red. Then the skill and the pins (T6): SKILL.md, the help line, the judgment fixtures in sitrep-card, card, words and the rehearsal builder rewritten to seven lines. The regression runs once after the build; the critic's review follows; the thirty seconds is measured at Step 5 from three real sitreps on this plan (REQ-9).

### Worth your eye

This section is the spec's Risks (AC-11.4); it keeps the heading the card reads until T13 lands, then is renamed.

- An answering verb that forgets to record the answer leaves its ask reading "waits on you": the exact lie this run removes, guarded only by the fixture and convention.
- A carried finding now closes at its row's landing, not at its ruling, so any reader that counted closed findings at ruling time reads one fewer.
- The check binds digits, not words: "three reviews failed" passes over a sheet reading two.

### 2. Component boundaries and interfaces

- **D1 — The purpose line comes first** (D1; REQ-7). A required `purpose:` tag drawn first under the grade; the seven sections keep their order.
- **D6 — Code draws, the model judges** (D6; REQ-3, REQ-4, REQ-5, REQ-6, REQ-8). The card verb draws every fact row from the saved sheet; the judgment is seven tags; the tool shows the card and the skill never retypes it.
- **D7 — The card shows what matters** (D7; REQ-1, REQ-2, REQ-3, REQ-10). The register tells an ask that waits on the user from an item that waits on an event; only the first blocks or drives the call; event-waiting items are one counted line; Metrics are a numbers-only table.
- **D8 — Answers stored, waits derived** (D8; REQ-1, REQ-2). `owed_answer` on the ask's line; `ask_waits_on` the one function every reader calls.
- **D9 — Fixtures, pins, a human clock** (D9; REQ-9, REQ-10). The thirty seconds is three real sitreps measured at Step 5.

The rule beside them (Δ11): the check refuses only a falsehood and repairs everything else.

Who owns what:

| Module | Owns | Changes |
|---|---|---|
| `payload/scripts/lib/owed.sh` | the register's grammar, `ask_waits_on` | `answer=` fields, `owed_answer`, `owed_answer_of`, `ask_waits_on` |
| `hooks/poker/plan.sh` (`reply`), `hooks/poker/proof.sh` (`disposition`, `finding-move`), `payload/scripts/lib/line.sh` (the landing's close) | the verbs that take an answer | write the answer; the landing closes a carried finding |
| `hooks/poker/sitrep.sh` | the sheet, the card verb, the handoff head, the Patrol line | `waits=` on ask lines, `run.goal:`, `for=`, `blocks=` from the one function, no re-gather at card time, `owed: n on you · m on events` |
| `payload/scripts/card.sh` | the draw and the check | fact rows drawn, seven tags, `_card_bind` over every judgment line, fold not refuse, four refusals, fallback deleted |
| `payload/scripts/lib/plan.sh`, `hooks/poker/plan.sh` (release card), `hooks/poker/tick.sh` | the goals | `plan_goal_paragraph`, openers, `on course`, task-scale theme, no ask on a declared red |
| `skills/sitrep/SKILL.md`, `agents-src/templates/commands/help.md.tmpl` | the model's instructions | the seven lines and the standard |
| `tests/sitrep-card.test.sh`, `tests/sitrep.test.sh`, `tests/card.test.sh`, `tests/words.test.sh`, `tests/handoff-file.test.sh`, `tests/lib/rehearsal-read.sh`, `tests/asks.test.sh`, `tests/release-approval.test.sh` | the pins | judgment fixtures to seven lines; §MOCKUP; the answer and `ask_waits_on` rows |

### 3. Ownership table

| concept | owning module (SSoT) | reuses | rendering surfaces | agreement test |
|---|---|---|---|---|
| what an ask waits on | `lib/owed.sh` `ask_waits_on` | the key prefix table `sitrep_holds` already keys on | the sheet's `waits=` · the card's Blocked on you and call check · the handoff head · the Patrol's `owed:` | `sitrep.test.sh` §ONE-BLOCKS: a planted answered waiver reads event on all four, and a planted divergence in any one reddens |
| an ask's answer | the register's open line `answer=` | `_owed_rewrite`'s last-word-wins | `waits=` · the release page's `withheld:` | `asks.test.sh` §ANSWER: `reply` no then `owed_answer_of` reads it, the item open |
| the fact rows | `card.sh` `_card_sitrep_draw` over the saved sheet | the S/T/R/A records and `_card_hang` | the card | `sitrep-card.test.sh` §DRAWN: a judgment with a `task:` line is refused and the drawn rows equal the sheet |
| the Metrics numbers | the sheet's measured values | `CARD_SITREP_MLINES` | the Metrics table · a judgment line's bound number | `sitrep-card.test.sh` §BIND: a number on no line refuses; the swapped pair refuses |
| what the wave is for | the plan's `## Goal` paragraph via `plan_goal_paragraph` | the requirements card's parse (card.sh:843-847), moved | `run.goal:` · the Step-1 card's Purpose | `sitrep.test.sh` §RUN-GOAL: the sheet's line equals the card's paragraph |
| a theme's standing | `lib/plan.sh` `plan_goal_status` | `_plan_theme_reads` | the sheet's `goal:` · the Goals line · the release card's mark | `sitrep.test.sh` §GOAL-AGREE: a theme at 11 of 12 reads `on course` on all three |

### 4. Rejected alternatives

- **`waits-on` written by every opener** (D8 option 2): eight writers of one field; one forgotten and the vapid call returns.
- **A Purpose section above Call to action** (D1 option 2): reopens the section order for one line the Assessment can carry first.
- **Trim in place** (D7 option 2): caps the points and collapses the asks but keeps the register blind, so the call and Blocked on you stay false.
- **Back to the plain prompt** (D7 option 3): half the time and facts that can be wrong again.
- **A scripted model for the timing** (D9 option 2): a harness for one number that proves nothing about the model.
- **A drawn-rows file beside the sheet**: a second saved artifact the model must keep consistent with the first; the card verb draws from the sheet at card time instead.
- **Optional `task:` and `metric:` overrides**: two writers of one row; the model's warmer phrasing is not worth a second truth.

### 5. Assumptions

- The `owed/v1` grammar tolerates new fields after `reply=`: every reader cuts named fields or the first four columns, none by count. `research-sitrep-sites.md` §REQ-1 lists the readers.
- `judge.sh:25` and `walls.sh:2543` re-open `waive:<q>` through `owed_open`, which leaves an open item as is, so an answer survives the next failing pass.
- The sheet's `desc` and `note` carry what the mock-up's task rows say; where a note is empty the row is the title alone.
- Three sitreps on this plan at Step 5 are a fair measure of REQ-9: the plan has few tasks, so the judgment is short; the measure is repeated once on the wave-43 plan for a fuller sheet and recorded beside it.
- No hook or wall other than the ones named reads an ask's `blocks=`; `research-sitrep-sites.md` §REQ-2 grepped `blocks=` across hooks and libraries and found three sites.

### ADR pointers

- `adrs/epic-23-bionic-tech-debt/adr-071-code-draws-the-facts-the-model-judges.md` (D6; D7; D8; REQ-1, REQ-3, REQ-4): the card's three owners and the check's rule; written at Step 7.

## Eval design

| Requirement | Approach | Criterion | Eval type | Eval | Fails when |
|---|---|---|---|---|---|
| REQ-1 | a register with one ask of each kind, one answered | AC-1.1 | hermetic | `asks.test.sh` §WAITS: `ask_waits_on` says user for a decision, an approval and an unanswered waiver, event for a waiver answered no and a finding answered carry; the sheet's `ask:` lines carry `waits=` | the refused waiver reads user, or a line lacks the field |
| REQ-1 | `reply` no on a waiver row; `disposition` carry on a finding | AC-1.2 | hermetic | `asks.test.sh` §ANSWER: the item stays open with `answer=no`; the finding stays open with `answer=carry event=T9 lands` and closes when T9's landing is recorded | the item closes at the answer, or reads no answer |
| REQ-2 | the §MOCKUP sheet and a sheet with an unanswered waiver | AC-2.1 | unit | `sitrep-card.test.sh` §BLOCKS: `None` naming T86 over the refused waiver; the unanswered waiver drawn under Blocked on you | the refused waiver is drawn, or `None` over the unanswered one |
| REQ-2 | a call saying nothing is owed over each | AC-2.2 | unit | `sitrep-card.test.sh` §CALL: admitted over the refused waiver, refused over the unanswered one | either verdict inverts |
| REQ-2 | one function, three readers | AC-2.3 | hermetic | `sitrep.test.sh` §ONE-BLOCKS: the sheet, the handoff head and the Patrol line agree over a planted answered waiver; `/usr/bin/grep -c 'nothing.*blocks\|blocks=' payload/scripts/card.sh` finds no re-derivation | any two disagree, or the fallback remains |
| REQ-3 | a seven-line judgment over the wave-43 saved sheet | AC-3.1 | unit | `sitrep-card.test.sh` §DRAWN: every step and task row drawn from S and T records; a `task:` line in the judgment refuses by name | a task row is missing, or `task:` is accepted |
| REQ-3 | the Metrics over the same sheet | AC-3.2 | unit | `sitrep-card.test.sh` §TABLE: five lines, every digit run a measured value of its line, the pace comparison first | a digit no line holds, or prose |
| REQ-3 | the §MOCKUP sheet's 14 event-waiting asks | AC-3.3 | unit | `sitrep-card.test.sh` §COUNTED: one line "14 items wait on landings, not on you: 8 carried findings, 6 rulings given" under the Assessment | an ask is drawn as a row |
| REQ-4 | each tag present, missing and foreign | AC-4.1 | unit | `sitrep-card.test.sh` §TAGS: the seven accepted; `metric:` refused by name; a missing `purpose:` refused by name | a foreign tag draws, or a missing one is unnamed |
| REQ-4 | numbers in a point; a 160-column point | AC-4.2 | unit | `sitrep-card.test.sh` §BIND: "1 green and 11 red" over "11 green, 1 red" refuses; a number on no line refuses; the long point folds and draws | the swap passes, or the fold refuses |
| REQ-4 | the skill text and a two-fault judgment | AC-4.3 | static | `/usr/bin/grep -n 'fenced' skills/sitrep/SKILL.md` finds the show-once rule and no "regenerate"; `sitrep-card.test.sh` §REASONS: a judgment missing purpose and holding a bad number prints both reasons on one refusal | the text asks to retype, or the second reason waits for a second run |
| REQ-5 | the skill text | AC-5.1 | static | `/usr/bin/grep -c 'task:\|metric:' skills/sitrep/SKILL.md` → 0 outside the refusal list; §SKILL rows of sitrep-card and sitrep read the seven tags and the Purpose question; `words.test.sh` §TEXTS green | an old tag remains in the example, or the Goals question |
| REQ-6 | the wave-44 plan and a plan with no Goal | AC-6.1 | hermetic | `sitrep.test.sh` §RUN-GOAL: `run.goal:` equals the paragraph the Step-1 card prints; the Goal-less plan prints no line and no error | the line differs, or an error prints |
| REQ-6 | the §REQ-GOALS-1 fixture with openers | AC-6.2 | hermetic | `sitrep.test.sh` §FOR: each `goal:` line ends `for=<opener>`; `release-approval.test.sh` §GOALS unchanged green | a line lacks `for=`, or the release card's read changes |
| REQ-7 | a judgment without `purpose:`; one with a false count | AC-7.1 | unit | `sitrep-card.test.sh` §PURPOSE: the first refuses by name; the second refuses on the number; a true one draws first under the grade | a card draws without it, or the false count draws |
| REQ-8 | a fixture with a theme at 11 of 12 and one at 0 of 12 | AC-8.1 | hermetic | `sitrep.test.sh` §GOAL-AGREE: `on course` and `not measured` on the sheet, the Goals line and the release card; "Identity 10 of 11" refuses at the card | the two themes read alike, or the false count draws |
| REQ-8 | the wave-44 plan at task scale | AC-8.2 | hermetic | `sitrep.test.sh` §TASK-GOAL: one `goal: name=the run` with k of n over the matrix | no goal line |
| REQ-8 | a measured goal missed by a `Lands-red:` row | AC-8.3 | hermetic | `sitrep.test.sh` §DECLARED-RED: the tick opens no `decide:goal:`; a goal missed otherwise still opens one | the ask opens, or the real miss opens none |
| REQ-9 | three sitreps typed on this plan at Step 5, one on wave-43's | AC-9.1 | human | the transcript timings recorded in `record/wave-44-every-hand/sitrep-timing.md`, each under 30 s, at most one refusal | one at 30 s or more, or two refusals |
| REQ-9 | the two verbs on the wave-43 plan | AC-9.2 | hermetic | `sitrep.test.sh` §FAST: `sitrep` then `sitrep card` on a copy of the wave-43 plan and record under 5 s together | 5 s or more |
| REQ-11 | a plan whose cells open on titles, one of 31 characters | AC-11.1 | unit | `card.test.sh` §TITLES: the Step-3 card's task block prints each title alone with `serves` in its own column and `T1–T5` for a run of ids; the 31-character title is refused with its row and length named; `show task 1` prints the whole cell; `/usr/bin/grep -c 'title of at most 30' skills/canonical-sdlc/steps/3.md` → 1 | the detail prints, the long title draws, or the step text lacks the rule |
| REQ-12 | a requirements file with one 31-character title | AC-12.1 | unit | `card.test.sh` §REQ-TITLES: the Step-1 card prints `REQ-n  <title>  ACs k` per requirement and no provenance; the long title is refused with its requirement and length named; `explain REQ-1` prints the provenance; `/usr/bin/grep -c 'at most 30' skills/canonical-sdlc/steps/1.md` → 1 | a provenance prints, the long title draws, or the step text lacks the rule |
| REQ-13 | a requirements file whose Not Doing items open on titles, one of 31 characters | AC-13.1 | unit | `card.test.sh` §NOT-DOING-TITLES: the Step-1 card prints each item's title on one line and no reason; the long title is refused with the item named; `explain not-doing` prints the items whole | a reason prints, the long title draws, or the step text lacks the rule |
| REQ-14 | a spec with a 31-character decision title and a `### Risks` section of three free sentences | AC-14.1 | unit | `card.test.sh` §DESIGN-TITLES: the Step-2 card prints each decision as id, title, serves and ADR and refuses the long title naming it; the Risks section draws whole under `Risks`, folded, never cut; a spec with `### Worth your eye` still draws | the long title draws, a risk is cut, or the section reads Worth your eye |
| REQ-10 | the flock-app-app-shaped sheet | AC-10.1 | unit | `sitrep-card.test.sh` §MOCKUP: the drawn card equals the mock-up's shape line for line (sections, counts, `None`, three close lines), under 40 rows; red at dd425be64 on the unknown `purpose:` tag, T1's red log in record/ | a register item is a row, the merge reads blocked, 40 rows or more, or green at the base |

## Not Doing

As the requirements: the measure work and the Known-limit leftovers (1.28.0); new sections; the section order, numbers-only Metrics, the grade and the task list's shape; a sitrep at epic scale beyond today's sheet; the person's merge and tag.
