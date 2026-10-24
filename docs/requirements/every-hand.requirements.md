---
governing-skill: agent-skills:idea-refine
sdlc-step: 1
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
source: ideas/bionic-1.27.0-charter.md §Late addition and §Cut · record/wave-44-every-hand/research-sitrep-concept.md · record/wave-44-every-hand/research-sitrep-latency.md · record/wave-44-every-hand/design-ledger.md Δ1, Δ6, Δ7, Δ8
release: 1.27.0
---
# bionic 1.27.0 — the sitrep changes what you do next · requirements (epic-23 wave-44)

## Goal

A sitrep is the handful of facts that change what the user does next, drawn by code with the model's judgment on top, in well under a minute. Five themes, in the plan's order: the register tells an ask that waits on the user from an item that waits on an event, and only the first can block the user or drive the call; code draws every fact row, the head, the task list, the metrics, Blocked on you and the predicted close, and the model writes seven lines of judgment the check reads; the card says what the wave is for and whether it is on course, first under the Assessment; and the whole takes under thirty seconds of model output; and every card the run puts to the user, requirements, design and plan, prints a name per item and keeps the detail one keystroke away. Accepted when the card drawn on the wave-43 plan and on a fixture shaped like the flock-app-app run reads in the approved mock-up's shape, and three sitreps in a row take under thirty seconds each.

## Context

The run was chartered as the hand-holds measure with the sitrep as a late addition, and cut to the sitrep at the design frame (charter §Cut; ledger Δ8). The cause: a flock-app-app card of 63 rows whose Call to action restated a ruling already given, whose Assessment carried fourteen register items under five points, and whose Blocked on you named a merge that waited on a re-review, not on the user; and a measurement of the sitrep at a median of about 95 seconds, nine tenths of it the model typing and retyping rows that are facts (research-sitrep-latency.md: first judgment 43%, refusal rewrites 34%, retyping the printed card 14%, machine 10%). The concept review (research-sitrep-concept.md) found the card never states what the wave is for: the sheet carries neither the plan's Goal nor the themes' openers, and the Goals row may state only status counts. Chris ruled D7, materiality; D6, code draws the facts; D1, the purpose first under the Assessment; and approved a mock-up (ledger Δ1, Δ6, Δ7). The rulings of waves 38 to 43 that stand: the seven sections in order (w42 Δ0, Δ9), Metrics as numbers only (w42 D2), the grade (w42 D2), the task list as drawn today, bottom line up front (w38 D11), one renderer prints every fact (w38 D9, restored). Reopened on evidence: w42 D1 "2" (the model writes every word) and w42's "every open ask answered once".

## Theme 1 — the register knows what you owe

An ask waits on the user or on an event, and the register says which; only an ask that waits on the user can block the user or drive the call.

### REQ-1 — An ask says what it waits on

provenance: charter §Cut (the flock-app-app card's "Blocked on you doesn't seem like it's truly blocked"); sheet-definitions.md (an ask line carries holds= and blocks=, nothing of who it waits on)

- AC-1.1 Every ask on the register reads `waits-on=user` or `waits-on=event <what>`: a decision, an approval and an unanswered waiver wait on the user; a waiver answered "no" waits on the review's next run; a finding carried to a row waits on that row's landing; the sheet's `ask:` line carries the field. Fails when: a refused waiver reads `waits-on=user`, or an ask line lacks the field.
- AC-1.2 A reply of "no" to a waiver, and a finding ruled "carry" or "defer", record the answer on the ask and move it to `waits-on=event` without closing it; the ask closes as it does today, when the review passes or the row lands. Fails when: the answered ask still reads `waits-on=user`, or it closes before its event.

### REQ-2 — Blocked follows waits-on

provenance: charter §Cut ("the Call to action is vapid"); wave 43 deferral critic-adversarial-2.md#2 (adopted: the handoff head follows the card); debt blocked-on-you (card.sh:3042, sitrep.sh:2123) and blocks-rule (sitrep.sh:1616, card.sh:3139)

- AC-2.1 Blocked on you lists the asks that wait on the user and hold a task, the release or the merge, and nothing else; with none it reads `None` and names the nearest event the run waits on. Fails when: an ask waiting on an event is drawn there, or `None` is drawn while an ask waiting on the user holds the merge.
- AC-2.2 The call may say nothing is owed while every open ask waits on an event, and must name the ask while one waits on the user and holds something; the check reads `waits-on`, not `holds`. Fails when: the check refuses "nothing tonight" over a refused waiver, or admits it over an unanswered one.
- AC-2.3 The handoff head's `Blocked on you`, the sitrep card and the Patrol's `blocks=` read one function, pinned by one suite row that reddens when any two disagree; the `blocks-rule` and `blocked-on-you` duplicates are gone. Fails when: `/usr/bin/grep` finds the rule in two files, or a planted divergence passes.

## Theme 2 — code draws the facts, the model writes the judgment

Every row that is a fact is drawn by the verb; the model writes only what is judgment, and the check reads only that.

### REQ-3 — The verb draws the fact rows

provenance: ledger Δ6 (D6 "1"); research-sitrep-latency.md causes 1 to 3; w38 D9 (one renderer prints every fact)

- AC-3.1 `sitrep` prints, beside the sheet, the drawn rows of the head, the Task list (every step and task row as today, its text from the plan's task title and its state words from the sheet), the Metrics table, Blocked on you and the first two lines of Predicted close, so the model writes none of them. Fails when: a task row's text or a metric number must be typed by the model, or a drawn row differs from the sheet fact it is drawn from.
- AC-3.2 The Metrics are a five-line table, Completed, Pace, Correctness, Waste, Goals, each cell one sheet value, numbers only, the pace comparison first in its line. Fails when: a cell holds a number no sheet line holds, or a line is prose.
- AC-3.3 Items that wait on events are one drawn line under the Assessment, counted by kind ("14 items wait on landings, not on you: 8 carried findings, 6 rulings given"), never one row each. Fails when: an ask waiting on an event is drawn as its own row.

### REQ-4 — Seven lines, checked for truth

provenance: ledger Δ6, Δ7; research-sitrep-latency.md (refusal classes: metric binding 4, row wrap 4, state word 2, reading/reader 2)

- AC-4.1 The judgment the model pipes to `sitrep card` is: `purpose:`, `call:`, `grade:`, one to three `point:` lines, one `ask <key>:` recommendation per ask that waits on the user, and one `close:` condition line; the check refuses any other tag, and refuses a missing one by name. Fails when: a `task:` or `metric:` line is accepted, or a missing `purpose:` draws a card.
- AC-4.2 Every number in a judgment line is bound to the sheet value whose word stands beside it, by word and by place, as the metrics were; a line over the card's width is folded by the renderer, never refused. Fails when: "1 green and 11 red" over "11 green, 1 red" passes, or a long point is refused for its length.
- AC-4.3 The tool shows the card; the skill tells the model to print the tool's output once inside one fenced block and never to retype it, and a refusal prints every reason at once. Fails when: the skill text asks the model to regenerate the card, or the second refusal names a reason the first could have.

### REQ-5 — The skill is the new shape

provenance: ledger Δ6, Δ7; skills/sitrep/SKILL.md (the six questions, the Goals question, "every open ask answered once")

- AC-5.1 `skills/sitrep/SKILL.md` describes the two verbs, the seven judgment lines, the Purpose question in place of the Goals question, and the rule that an ask waiting on an event owes the user nothing; its example judgment is seven lines; `words.test.sh` and the sitrep-card suite's skill section pin it. Fails when: the skill text still asks for `task:` or `metric:` rows, or for every open ask.

## Theme 3 — the card says what the wave is for

The sitrep opens its judgment on what the wave set out to do and whether that is being accomplished, read from the run's own documents, at every scale.

### REQ-6 — The sheet carries the goal

provenance: charter §Late addition ("reasserting what the wave is doing"); research-sitrep-concept.md Q3; wave 41 D13

- AC-6.1 The sheet carries `run.goal:`, the plan's `## Goal` paragraph, so the purpose is drawn from the verb and never fetched by the model. Fails when: a plan with a Goal paragraph prints no `run.goal:` line, or the line differs from the paragraph.
- AC-6.2 Each theme's `goal:` line carries the theme's opening sentence as its last field, `for=`, with the fields the release card reads kept in place. Fails when: a theme that opens on a sentence prints no `for=`, or the release card's reading of the line changes.

### REQ-7 — The purpose line comes first

provenance: charter §Late addition ("whether we're accomplishing the purpose of the wave"); ledger Δ1 (D1 "1")

- AC-7.1 The Assessment's first row is the `purpose:` line, what the wave is for and whether it is on course; a judgment without it is refused, and its numbers are checked against the sheet as every line's are. Fails when: a card draws without it, or a purpose claiming a count the sheet lacks is drawn.

### REQ-8 — Progress per theme on the card

provenance: research-sitrep-concept.md Q2, tweaks 3, 5 and 7; 1.26.0 Known limit 23

- AC-8.1 The Goals line of the Metrics states each theme's criteria discharged and open REQs, each number bound to its theme's name; a theme with at least one criterion discharged and none missed reads `on course`, distinct from `not measured`, on the sheet, the sitrep card and the release card. Fails when: a theme at 11 of 12 reads as one at 0 of 12, or "Identity 10 of 11" over a sheet reading 9 of 11 is drawn.
- AC-8.2 At task scale the sheet reads one goal over the whole matrix, the run's criteria discharged and open REQs. Fails when: a task-scale sheet prints no `goal:` line.
- AC-8.3 A goal missed by a red the plan itself declares opens no `decide:goal:<name>` ask. Fails when: the ask opens for a declared red.

## Theme 4 — fast

A sitrep costs the user the time it takes to read it, not the time it takes to write.

### REQ-9 — Under thirty seconds

provenance: charter §Cut ("Right now this is fucking wasting my time!"); research-sitrep-latency.md (74 to 108 s; model output 90%)

- AC-9.1 Three sitreps run in a row on a live plan, measured from the typed command to the shown card in the transcript as research-sitrep-latency.md measured, each take under 30 seconds, with at most one card refusal among the three. Evidence is the measurement recorded at Step 5. Fails when: one takes 30 seconds or more, or two are refused.
- AC-9.2 The machine side of a sitrep, the sheet and the card together, takes under 5 seconds on the wave-43 plan. Fails when: `time` reads 5 seconds or more.

### REQ-10 — The approved shape is pinned

provenance: ledger Δ7 (the mock-up Chris approved: "Yes! That is what I want!")

- AC-10.1 A fixture shaped like the flock-app-app card (17 open tasks, 14 items waiting on events, a refused waiver holding the merge, 54 added tasks) draws the mock-up's shape: Call to action one line saying nothing is owed, the Task list as today, a five-line Metrics table, an Assessment of the purpose, at most three points and one counted line, Blocked on you `None` with the event named, Predicted close in three lines; the drawn card is under 40 rows. Fails when: a register item is drawn as a row, the merge reads blocked, or the card exceeds 40 rows.

## Theme 5 — the cards read at a glance

Every card the run puts to the user prints a name per item and keeps the detail one keystroke away, so a card is scanned, not read.

### REQ-11 — The plan card shows titles

provenance: user 2026-10-23 "Each task description is far too long. It's not useful whatsoever. I need a brief summary or phrase that represents what the task is. Maybe 25-30 characters max." and "Yes! That's so much more useful OMG" at the mock-up (ledger Δ13); user 2026-10-23 "you need to do the same thing for the requirements card. Each requirement desc needs to be capped at 30 chars."

- AC-11.1 A `## Tasks` cell opens on a title of at most 30 characters, then a period and the detail; the Step-3 card prints the title alone, `serves` in its own column and consecutive ids in `depends` as a range; `show task <n>` prints the whole cell; the Step-3 text states the rule; a longer title is refused by the card, which names the row and its length, never cut. Fails when: the card prints the detail, or a 31-character title is drawn.

### REQ-12 — The requirements card too

provenance: user 2026-10-23 "Each task description is far too long. It's not useful whatsoever. I need a brief summary or phrase that represents what the task is. Maybe 25-30 characters max." and "Yes! That's so much more useful OMG" at the mock-up (ledger Δ13); user 2026-10-23 "you need to do the same thing for the requirements card. Each requirement desc needs to be capped at 30 chars."

- AC-12.1 A `### REQ-<n> — <title>` heading's title is at most 30 characters; the Step-1 card prints each requirement as its id, its title and its criteria count on one line, the provenance under `explain <requirement>` only; a longer title is refused by the card, which names the requirement and its length, never cut; the Step-1 text states the rule. Fails when: the card prints a provenance, or a 31-character title is drawn.

### REQ-13 — Not Doing in titles

provenance: user 2026-10-23 "Not Doing is way too wordy! It needs to be summarized!"

- AC-13.1 Every `## Not Doing` item opens on a title of at most 30 characters, then a colon and the reason; the Step-1 card prints the titles, one per line, and `explain not-doing` prints the items whole; a longer title is refused by the card, naming the item, never cut; the Step-1 text states the rule. Fails when: the card prints a reason, or a 31-character title is drawn.

### REQ-14 — Decisions titled, Risks judged

provenance: user 2026-10-23 "Decisions capped to 30 characters"; "the Worth your eye section should probably be called Risks"; "I thought you were summarizing to the material points only"

- AC-14.1 Every `- **D<n> — <title>**` decision title is at most 30 characters; the Step-2 card prints each decision as its id, its title, the requirements it serves and its ADR, `explain <decision>` printing the detail; a longer title is refused by the card, naming the decision, never cut. The spec's `### Worth your eye` section is `### Risks`: each item is the model's own judgment of one risk that could change the user's decision, a sentence or two, and nothing that is not such a risk; drawn whole and folded, with no cap and no required shape; the card accepts the old heading on a spec written before 1.27.0. The Step-2 text states both. Fails when: a 31-character decision title is drawn, a Risks item is cut or refused for its length, or the card's section still reads Worth your eye.

## Not Doing

- The measure work, to 1.28.0: Themes 1 to 4 of the charter and its Known-limit leftovers, the hand-holds window and kinds, every-cell-has-a-verb, the card and the gate reading one fact, the binding outliving the session, and REQ-23 to REQ-34 of this file's first approval, carried whole to `ideas/bionic-1.28.0-charter.md` with their research map and the debt items `tick-idle-width`, `landing-record-parser`, `publish-order` and `arm-at-task-scale`. The debt items `blocks-rule` and `blocked-on-you` burn here under REQ-2.
- Hand-holds as a judge: this run's close is not judged by it; the close reports its reading as it does today, and what the orchestrator types by hand is logged in `assumptions.md` for 1.28.0 to read.
- Reopening the card's rulings: the seven-section order, Metrics as numbers only, the grade and the task list's shape stay; Chris kept them at the mock-up.
- A new section or epic scale: no new sitrep section, and no sitrep at epic scale beyond what the sheet reads today.
- The merge and the tag: the person's, after the pull request (pr dealing).

## Inherited deferrals

adopted: record/wave-43-no-hand-hold/critic-adversarial-2.md#2 as REQ-2
again: record/wave-43-no-hand-hold/critic-evidence.md#5
