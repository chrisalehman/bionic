---
governing-skill: agent-skills:idea-refine
sdlc-step: 1
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
base-sha: b4220d339
seed: ideas/bionic-1.28.0-charter.md
source: ideas/bionic-1.28.0-charter.md (D16 "1", D18 option 2) · ideas/decision-context.md · ideas/judge-knows-docs-tracked.md · ideas/title-cap-at-task-add.md · record/wave-44-every-hand/research-every-hand-map.md · record/wave-44-every-hand/assumptions.md §Hand edits · record/wave-44-every-hand/continuation.md §Deferrals
release: 1.28.0
---
# bionic 1.28.0 — the measure counts every hand · requirements (epic-23 wave-45)

## Goal

The hand-holds measure is made honest over the whole close and then reads zero. Six themes, in the plan's order: the decision carries its referent and the requirement its concept, so every decision this wave puts to Chris names the thing it is about and a command to see it, and every requirement on the card says in one plain sentence what it makes true; the window is the whole close, from the last build landing to `delivered:`, and a landing settles every finding its fix carries; every cell has a verb, so no status, ruling, pointer or filled mark is typed by hand; the card and the gate read one fact, so no two surfaces disagree about a review, an ask or a goal; the binding outlives the session, so a clear costs no landing and close-out finishes its own paperwork; and the 1.26.0 and 1.27.0 leftovers a test can pin are taken, last, as the first cut at the day boundary. Accepted when the 1.28.0 close reads `hand-holds: total=0` over the widened window with an empty hand-edit log, and the 1.26.0 close replay reaches `delivered:` reading zero with its own log part held by its tests.

## Context

1.26.0 measured its close at `total=2` while the orchestrator typed eight hand acts, four of them after the release approval card where the window ended (charter §Why). 1.27.0 was chartered as this run, cut to the sitrep at the design frame, and logged fourteen hand edits inside its own window: ruled deltas, the `approved-by:` line, eval and matrix rows, `stack-health:`, `adrs:`, the Known limits sentences, the continuation marks (`record/wave-44-every-hand/assumptions.md`). The research map of the charter's sites (`research-every-hand-map.md`, at dd425be64) found two holes the charter does not name: matrix waivers are never counted on a rendered plan, and no code forms the `wt/<NN>-<row>` branch Theme 4 wanted to read. Chris ruled the five objectives as the core on 2026-10-24 (D16 "1") and added Theme 0 at his word.

## Theme 0 — the decision carries its referent

Every decision put to Chris names the thing it is about, who asked for it and why the rule bites, and leaves the artifact behind one command; every requirement, decision and task put to him carries one plain sentence saying what it makes true.

### REQ-1 — The context names the thing

Every decision put to you says what thing it is about and gives one command to see it yourself, so you never open the record to know what you are ruling on.

provenance: ideas/decision-context.md (Chris, 2026-10-24 9:20 to 9:35 AM PDT, the three-version D15 example); charter §Ruled

- AC-1.1 The decision skill's text rules the paragraph between Goal and Options: owed whenever the decision is about a specific thing, it identifies the thing in one clause (what it is, which commit or record, whose ruling), says in one sentence why the rule bites now, and never pastes the artifact; the Altitude rule governs Goal and Options only. Fails when: the skill text still says the whole brief carries no identifiers, or it lets the context paragraph inline a diff.
- AC-1.2 The reply line carries, after the option numbers and the forms, one dig-in command the reader can type to see the artifact whole (`git show <sha>`, `show task <n>`, `show finding <record>#<n>`), as the accepted D15 text does; nothing follows the reply line. Fails when: a brief about a commit or a finding ends on a reply line with no command on it, or a line follows it. (Corrected at Step 2, D10: as approved it put the command on a line after the reply line, which the skill forbids.)
- AC-1.3 The decision suite plants a brief about a specific diff whose context names no referent and refuses it, and admits the accepted D15 text as written in the brief. Fails when: the referent-less brief passes, or the accepted text is refused.

### REQ-33 — A requirement says its concept

Every requirement on the Step-1 card is followed by one plain sentence saying what it makes true, so the card reads as a list of concepts and not of labels.

provenance: Chris Lehman 2026-10-24 1:05 to 1:19 PM PDT at the Step-1 card ("too abbreviated to be useful"; "the simplest explanation of the concept that requirement represents"); D1 ruled "2" (design-ledger Δ1)

- AC-33.1 Every `### REQ-n` section opens on one paragraph, before its `provenance:` line, that says in plain words what the requirement makes true and for whom, at the altitude the decision skill asks of a Goal: no file, function, verb, row or version identifier, so no backticked token. The Step-1 card refuses a requirement with no such paragraph, or one whose paragraph carries a backtick, the way it refuses a title over the cap: refused with the requirement named, never rendered without it or cut. Fails when: a requirement with no opening paragraph renders, or one whose paragraph names a function in backticks renders.
- AC-33.2 The Requirements section of the Step-1 card prints that sentence on its own line under each row, indented past the id and running to the card's right edge, folded at that edge; the row itself keeps its id, title and criteria count as it is. The `explain` view keeps the provenance and the criteria. Fails when: a row renders without its sentence, the sentence is truncated, or the sentence is folded inside the title column.
- AC-33.3 Every requirement of this file carries the sentence at the card's approval, which the card's own refusal (AC-33.1) proves by rendering; `card.test.sh` pins the rule over fixtures it owns: a requirement with the sentence renders it under its row, one without is refused, and one whose sentence carries a backtick is refused. Fails when: any of the three planted cases passes, or the fixture is a live plan rather than the suite's own.

### REQ-34 — The design reads as concepts

Every decision on the Step-2 card is followed by its own plain sentence, and each requirement's eval line says in plain words what is proven, so the design card reads as concepts and not as labels.

provenance: Chris Lehman 2026-10-24 3:04 PM PDT at the Step-2 card ("apply the exact same change … to decisions"; "the descriptions of the evaluation … should represent the concept as succinctly as possible"); D27 (design-ledger Δ11)

- AC-34.1 Every decision bullet of a spec opens, after its bold title, on one plain sentence saying what the decision makes true, with no backticked token, before the detail `explain` prints. The Step-2 card refuses a decision with no such sentence, or one whose sentence carries a backtick, with the decision named, as it refuses a title over the cap. Fails when: a decision whose first sentence names a function in backticks renders, or one with no sentence renders.
- AC-34.2 The Decisions section of the Step-2 card prints that sentence on its own line under each row, indented past the id and folded at the card's right edge; the row keeps its id, title, serves and ADR as it is, and `explain` keeps the detail. Fails when: a row renders without its sentence, the sentence is truncated, or it is folded inside the title column.
- AC-34.3 The Eval design's Approach cell is the requirement's proof in one plain line, the same on every row of the requirement, with no backticked token and at most 60 columns (D27); the card prints it on the requirement's line and the Eval cell keeps the command and its observation. Fails when: a cell over the cap or with a backtick renders, or a requirement's rows carry two approaches.
- AC-34.4 Every decision and every requirement of this run's spec carries its sentence at the card's approval, which the card's own refusal proves by rendering; `card.test.sh` pins the rule over fixtures it owns: a decision with the sentence renders it under its row, one without is refused, one with a backtick is refused, and an approach cell over the cap is refused. Fails when: any planted case passes, or the fixture is a live spec rather than the suite's own.

### REQ-35 — The plan reads as concepts

Every task on the Step-3 card is followed by its own plain sentence saying what the row makes true, so the plan card reads as concepts and not as labels.

provenance: Chris Lehman 2026-10-24 3:58 PM PDT at the Step-3 card ("each Task updated with the same formula as Requirements (step 1), Decisions (step 2)"); D28 (design-ledger Δ12)

- AC-35.1 Every `## Tasks` cell opens on its title, then one plain sentence saying what the row makes true, with no backticked token, before the detail `show task` prints. The Step-3 card refuses a row with no such sentence, or one whose sentence carries a backtick, with the row named, as it refuses a title over the cap. Fails when: a row whose sentence names a function in backticks renders, or one with no sentence renders.
- AC-35.2 The Tasks section of the Step-3 card prints that sentence on its own line under each row, indented past the id and folded at the card's right edge; the row keeps its id, title, serves, kind, depends and agent as it is, and `show task <n>` keeps the whole cell. Fails when: a row renders without its sentence, the sentence is truncated, or it is folded inside the title column.
- AC-35.3 `task-add` and `task-set` refuse a cell with no sentence, or a backticked one, with the card's own words, through the channel the cap uses (REQ-30). Fails when: such a cell lands in the table.
- AC-35.4 Every row of this run's plan carries its sentence at the card's approval, which the card's own refusal proves by rendering; `card.test.sh` pins the rule over fixtures it owns: a row with the sentence renders it under the row, one without is refused, one with a backtick is refused. Fails when: any planted case passes, or the fixture is a live plan rather than the suite's own.

## Theme 1 — the window is the whole close

The count of hands covers the last build landing to `delivered:`, every act inside it is seen, and a landing settles everything it proves.

### REQ-2 — The replay's log is held

The replay of the 1.26.0 close keeps its own log of hand edits, and its tests hold that log, so the replay's zero means what a real run's zero means.

provenance: 1.26.0 Known limit 2 (CL-8, VB-1, VB-2 red at 29cfb97b2); research map §T1.1

- AC-2.1 `close-replay.test.sh` rows CL-8, VB-1 and VB-2 read the commands, exits and hand-write marks the replay logs for itself and are green in the whole run; the log is checked by the commands it must hold, named by verb, not by its length. Fails when: any of the three is red at the build's last row, or a verb the replay ran is absent from its log part.

### REQ-3 — The window ends at delivered

The hand-holds count covers the whole close, through the last thing close-out writes, instead of stopping at the release card with half the close outside it.

provenance: charter Theme 1 (line.sh `hand_holds_ends`, A-orch.67, wave-43 critic-adversarial.md#3); research map headline 2 and §The measure today

- AC-3.1 `landing-report --hand-holds` with no `--until` ends the window at the plan's `delivered:` time, else now; close-out writes `delivered:` and wipes its rosters first and reads the line last, so what Steps 8 and 9 write is inside it (D8). Fails when: the window line still says `(the release approval card)`, or an act close-out itself performs after the card is outside.
- AC-3.2 A `waiver:` line inside an AC block that `matrix-render` wrote (`AC-<id>: <text>` header) is counted as a waiver, as a bare-header block's is; the suites pin the rendered shape, not a synthesized one. Fails when: the four waivers of the wave-43 plan read `waivers=0` over a window that holds them.
- AC-3.3 A `moved: … to=fixed` line typed before the landing it names is outside the window; one typed after it is inside. Fails when: a move at the landing's own time minus a minute counts, or one a minute after does not.
- AC-3.5 The 1.28.0 close itself reads `hand-holds: total=0` over the widened window with an empty hand-edit log, written by the close-out verb into the continuation, the run's one live row (D4). Fails when: the close reads above zero, or the line is typed by hand.
- AC-3.4 The `landing-record-parser` duplicate and the `publish-order` unpinned pair of the debt ledger are burned by this requirement's row: one parser, and one suite row that reddens when the two orders disagree. Fails when: `/usr/bin/grep` finds the record parser in two functions, or the pair has no pin.

### REQ-4 — A landing settles its findings

When a fix lands, every review finding it answers is marked settled by that landing, so no finding is moved by hand afterwards.

provenance: charter Theme 1 (A-orch.66, A-orch.67); 1.27.0 critic-adversarial.md#9 (adopted); research map §W4

- AC-4.1 A fix row's landing reads fixed every finding its `born:` names and every finding under another record that names the same site (the `at=<path:line>` the disposition prints), so the evidence copy of an adversarial finding closes with it. Fails when: a second-record finding at the same site still needs `finding-move … fixed` after the landing.
- AC-4.2 A finding carried to a row (`finding-move … carried T<n>`) reads fixed when that row lands, and a carry to a row already landed or dropped closes on the register at once. Fails when: the carried finding stays open past the row's landing, or a carry to a landed row never closes.
- AC-4.3 The replay plants a second record naming the fix row's site and reaches `delivered:` with no `finding-move` after its landing, reading `total=0` with the window at `delivered:`. Fails when: the replay's log shows a move after the fix's landing, or the close reads above zero.

## Theme 2 — every cell has a verb

Anything the run records is recorded through a verb, so the hand-edit log of a full run is empty.

### REQ-5 — The fill writes the cell

The act that records a row's proof also marks the row discharged in the matrix table, so the table never lags the proof it summarises.

provenance: charter Theme 2 item 1 (A-orch.65); research map §W1

- AC-5.1 A landing that writes an AC block's `evidence:` writes the matrix table's status cell `discharged` for that row in the same act. Fails when: a row whose block carries a green log still reads `pending` in the table.
- AC-5.2 The rehearsal no longer sets the status by `matrix-set` after the build lands; the replay's matrix reads `discharged` from the landing alone. Fails when: `rehearsal.sh` still calls `matrix-set … status=` on a built row.

### REQ-6 — Verdicts reach the auditor

At single rigor the critic's verdicts flow into the matrix when the review is registered, so nobody copies a verdict cell by hand.

provenance: charter Theme 2 item 2 (A-orch.67, rehearsal.sh:199); 1.27.0 A-orch.11 (`auditor-wave:` by hand)

- AC-6.1 At single rigor, registering the evidence review (`proof-add review … --question evidence`) carries each row verdict of the critic's record, written there as a table `| AC | verdict |` (D12), into the matrix's auditor cell, `CONFIRMED` as the bare token and any other verdict as written, and writes the record's wave verdict as the matrix head's `auditor-wave:` line. Fails when: a CONFIRMED row still needs `discharge`, or the wave verdict is absent from the head.
- AC-6.2 `discharge <AC>` is the double-rigor act and refuses at single rigor with a line naming `proof-add review`; a single-rigor rehearsal fixture, added by this requirement, reaches the Verify gate without it. Fails when: `discharge` writes a cell on a `rigor: single` plan, or the rehearsal still transcribes verdicts. (Corrected at Step 2: no single-rigor rehearsal fixture exists at head.)

### REQ-7 — Stack health from the proof

The matrix's stack-health line is written from the recorded regression proof, never typed from it.

provenance: charter Theme 2 item 3 (A-orch.65); 1.27.0 A-orch.9; research map §W3

- AC-7.1 `proof-add regression` (and `regression-run` when it records) writes the matrix head's `stack-health:` line from the proof's head, pass and total, replacing the rendered stub. Fails when: the stub survives a recorded whole-run proof, or the line is written by anything but the proof verbs.

### REQ-8 — A ruling is a verb

Ruling a decision is one command that writes the ledger entry and closes the ask together, however the ruling arrives.

provenance: charter Theme 2 item 5; 1.27.0 hand edits Δ1 to Δ14; 1.26.0 Known limit 17 (the `settled by` heading); research map §W5

- AC-8.1 `decisions rule D<n> '<reply>'` writes the ruling heading the ledger parser reads, `## Δ<k> — D<n> ruled "<reply>" (<who> <date>): <title>`, with the title from the put, and settles the ask on the register in the same act. Fails when: the heading written is not an entry to the parser, or the ask stays open after the ruling.
- AC-8.2 `reply` to a release card and `approve` of a decision write the same ruling through the same function, so a decision ruled at the card has its Δ line. Fails when: a card-ruled decision has an answered ask and no ledger entry.
- AC-8.3 The parser reads a heading of the form `D<n> settled by …` as an entry whose clock is the line's date, so its waiting span is kept. Fails when: wave 42's Δ20 still parses as no entry. (Corrected at Step 2: the heading is Δ20, not Δ19.)

### REQ-9 — Pointers are rendered

The pointers the walls read later, the ADR list and who approved the plan, are written by the steps that learn them.

provenance: charter Theme 2 item 6 (A-orch.70, 1.27.0 A-orch.22); 1.27.0 hand edit 06:29Z (`approved-by:`)

- AC-9.1 The Step-7 advance renders the plan's `adrs:` frontmatter from the Step 7 `adr:` line, and close-out's epic row reads either. Fails when: a plan with `adr:` on its Step 7 line and no `adrs:` makes `epic_row_missing` refuse the row.
- AC-9.2 `approve plan '<reply>'` at Step 3 writes the `approved-by:` line the walls read, with the user's words, so no step-field refusal leaves it to the hand. Fails when: the only writer of `approved-by:` is the orchestrator's editor.

### REQ-10 — The close-out verbs finish

The verbs that finish a close-out still work after close-out has let go of the run, and close-out fills every mark it can before it lets go.

provenance: charter Theme 2 item 7 (A-orch.71); 1.27.0 A-orch.25, A-orch.26

- AC-10.1 `continuation-fill` and `step-field 8` accept a delivered plan named by `--plan` or bound, engaged or not, so the continuation's marks and the pull request's merge record are written by their verbs after close-out's disengage. Fails when: either verb prints NOT-ENGAGED on a delivered plan.
- AC-10.2 Close-out fills the landing numbers, the hand-holds line, the reviews and the governed-by line itself and leaves in the continuation only the five marks the next session owns, pinned so. Fails when: a mark close-out could fill reads `<fill:` after it exits. (Corrected at Step 2: at head close-out already renders those four; the criterion pins that it stays so.)

### REQ-11 — The Known limits are rendered

The release entry's Known limits are rendered from the deferrals the run registered, the way its reviews and landing numbers already are.

provenance: 1.27.0 A-orch.12 (the twelve sentences committed by hand); the reviews part (1.26.0 T33) and the landing numbers (`release-note`) as the pattern

- AC-11.1 A `known-limits-part <row>` verb renders the release entry's Known limits from the plan's `deferred:` lines (their `stated=` sentences, in the order registered), committed on the working branch as the reviews part is, so the release check's sentence scan finds them. Fails when: a deferred finding's sentence is absent from the entry after the part runs, or the part is written by anything but the verb. (Corrected at Step 2, D13: no verb records a stated assumption, so the entry renders from deferrals alone.)

### REQ-12 — The matrix grows by a verb

A criterion added after the plan was approved reaches the matrix table through the same render that writes its block.

provenance: 1.27.0 hand edits 06:48Z to 07:55Z (eval rows and matrix table rows written by hand)

- AC-12.1 `matrix-render` maps each Eval type to its tier (static, unit, hermetic, live, human as T0 to T4; D14) and adds a matrix table row for every Eval design row that lacks one, in Eval design order, before it writes the AC blocks, so a criterion added after the plan's approval reaches the table and the block by the one verb. Fails when: an Eval design row with no table row is left out of the table after a render, or a row with a type in words is refused.

## Theme 3 — the card and the gate read one fact

A question such as "is this review covered" or "is this ask blocking the user" is derived in one place, and every surface shows that one answer.

### REQ-13 — Reviews read as the gate reads

The release card says a review is covered exactly when the gate would say so, and names the landings that covered it.

provenance: charter Theme 3 (release-approval-1afb7083.md); research map §T3.1

- AC-13.1 The release approval card's Reviews lines read a review as the judge does: covered once fix landings have answered every question at the head, `failing` only while a question is uncovered; the line names the covering landings. Fails when: a failed reading whose findings' fix rows have landed still prints `failing`.
- AC-13.2 The `blocks-rule` duplicate is burned here and re-ledgered: the card, the sitrep's reviews count and the judge read coverage from one function with one pin. Fails when: `/usr/bin/grep` finds the rule in two files, or the sitrep's count disagrees with the card over a planted failed-then-fixed review. (Corrected at Step 2: the item was burned at wave 44, re-raised by its critic, never re-ledgered; the sitrep is a third reader.)

### REQ-14 — A live review row delivers

A review row that tracks the head can be delivered once its questions are covered, and says which question holds it otherwise.

provenance: charter Theme 3 (T35, A-orch.63); research map §T3.2

- AC-14.1 `deliver` on a review row that reads `live:head` closes the row when every question is covered at the head, and refuses with the uncovered question named otherwise. Fails when: the row stays `pending` at close with every question covered, or the refusal names no question.

### REQ-15 — The integrate row in order

The reviews are published before the merge, and the Step-8 text and the integrate row's brief say so in that order.

provenance: charter Theme 3 (A-T33.6, A-T33.9, A-T33.10); research map §T3.3

- AC-15.1 `reviews-part` is walled: the main thread and the integrate row's own writer may run it, and any other writer is refused with the row named. Fails when: a build row's writer runs `reviews-part` unwalled, or the integrate row's writer is refused. (Corrected at Step 2, D16: as approved it would refuse the verb to its own named runner.)
- AC-15.2 At pr dealing the integrate row publishes the reviews part before the push and `gh pr create`; at merge dealing close-out's merge-scale path publishes it before its merge readback. Fails when: either path's part lands after the push or the merge. (Corrected at Step 2, D16: close-out performs no merge act of its own.)
- AC-15.3 The Step-8 text and the integrate row's brief scaffold name `reviews-part <row>` before the push and `gh pr create` at pr dealing. Fails when: `/usr/bin/grep reviews-part` over the rendered Step-8 file and the scaffold is empty.

### REQ-16 — Waiting on you, one reading

Only an ask that truly waits on you counts as waiting on you, on every line that says so.

provenance: 1.27.0 critic-adversarial.md#8 (adopted); 1.27.0 A-orch.6, T3.md Left

- AC-16.1 `close.waits-on-you`, `waste.waiting-on-you` and the held words count only asks that wait on the user, through `ask_waits_on`, which reads the answer a closed register line now keeps (D17), and the skill folds nothing else into the close line. Fails when: an ask answered no or carry, open or closed, still raises the waiting-on-you minutes.
- AC-16.2 A card render opens a step's approval ask on the register only when that approval is not yet recorded: never for a step below the plan's `current:`, never for Step 3 once `approved-by:` is written, and never when the renderer is a dispatched writer's check; the sweep that closes step asks on `approved-by:` closes them all at once. Fails when: a writer's `card.sh step3` over an approved plan puts "Blocked on you" on the sitrep, or a render of a step below `current:` opens an ask. (Added at Step 4 on Chris Lehman's words at 4:01 PM PDT, "this is so inaccurate … we need to fix this": the sitrep showed the plan's approval open after he gave it; A-orch.6.)

### REQ-17 — One reader per sitrep fact

A goal's status, a task's title and a goal's measure are each read by one function that the sitrep and its card share.

provenance: wave-44 critic-structure.md (goal-line-status, task-title), critic-structure-2.md (goal-measure); debt ledger

- AC-17.1 The goal line's status, the task title and the goal measure are each read by one function the sitrep and the card both call, with one pin each that reddens on a planted divergence; the three debt items are burned. Fails when: either surface keeps its own copy, or a planted divergence passes.

## Theme 4 — the binding outlives the session

The run belongs to the branch, not the conversation: clearing, compaction or close-out's own ending never costs a landing or refuses a record.

### REQ-18 — Ready reads the tree

Landing a row's work from its worktree needs only the tree's own record, so clearing the conversation between the spawn and the landing costs nothing.

provenance: charter Theme 4 (A-orch.66, wave-39 lesson 4); research map §W8 and §Theme 4 notes (no code forms `wt/<NN>-<row>`)

- AC-18.1 `ready` and a hand landing in a spawned tree resolve the plan and the working branch from the tree's own record (its workspace line's `plan=` or the open plan whose Tasks table names the tree), with the session binding as a check, so a `/clear` between the spawn and the `ready` costs no landing. Fails when: `ready` in a tree a predecessor session spawned refuses `no-bound-plan`.
- AC-18.2 A tree whose record names a different plan than the session's binding is refused with both named; a closed plan is admitted only for close-out's own last landings (D3). Fails when: a stale tree lands on the wrong plan silently, or close-out's last landing is refused.

### REQ-19 — Stopped finds the tree

Stopping a row finds and removes its tree from the plan even when the session that spawned it is gone.

provenance: charter Theme 4 (A-orch.23); research map §T4.2

- AC-19.1 `stop-orders.sh stopped` resolves a row's tree through the plan's Tasks `worktree` cell when the session's workspace record lacks it, removes it, and says what it removed or why it could not. Fails when: a predecessor's tree is left standing in silence.

### REQ-20 — Arm reads the scale

Arming the Patrol reads the run's scale the way every other Patrol reader does, so a task-scale session is never told to arm one.

provenance: 1.27.0 A-orch.1 (`arm-at-task-scale`, tick.sh:832, session-start.sh:1017); debt ledger

- AC-20.1 `arm` and the compaction's session-start text read the scale cell as resume, tick and the walls do: at a scale with no Patrol, `arm` writes no stamp and the text asks for none. Fails when: a task-scale session is told to re-arm, or `arm` stamps `verb=arm` there.

## Theme 5 — the leftovers with a test

Each 1.26.0 and 1.27.0 limit a suite can pin is taken, last, and the 1.28.0 entry states none of them again.

### REQ-21 — A second reply, as a pair

A second release card can be answered the same way the first was, and every approval re-put at a new head is handled alike.

provenance: 1.26.0 Known limit 1 (T1.md hole 7, T23.md); Known limit 18 (A-T23.4)

- AC-21.1 A `reply` after a second release card replays both approvals: `approve release` at the new head records the newer approval beside the first, and `approve merge` follows. Fails when: the second `reply` is refused with "An approval is recorded once".
- AC-21.2 `approve <name>` at a second head re-puts for every name, not release alone; an approval is stale when its recorded head differs from the current head (D19). Fails when: a stale `approve step4` at a new head is accepted unchanged.

### REQ-22 — Check-dirtied is pinned

The refusal of a release check that dirties the tree has a test that plants one.

provenance: 1.26.0 Known limit 6 (T2.md Holes)

- AC-22.1 A door-landing suite row plants a release-check at the release base, where the check runs (D20), that dirties the tree, and expects the door's `check-dirtied` refusal. Fails when: the arm has no pin, or the plant lands.

### REQ-23 — Hand verdicts before publish

A landing done by hand records its suite verdicts before it publishes, so a review's ask closes without waiting on a regression.

provenance: 1.26.0 Known limit 8 (A-T4.4); research map §T5.3

- AC-23.1 `land --by-hand` with `--suites` writes its verdicts before the line publishes, as `row-landed --by-hand` already does, so a born row landed by hand at Step 8 closes the review's ask without waiting on a regression. Fails when: the ask stays open after the hand landing's publish. (Corrected at Step 2, D27: `row-landed` is already in order; only `land` is not.)

### REQ-24 — A number binds to its place

The card check reads a number against its place in the line, so swapped counts are caught.

provenance: 1.26.0 Known limits 15 and 16 (A-T14.4, A-orch.32, A-T14.2)

- AC-24.1 The card check binds a number to its place in the line as well as its word, so "1 green and 11 red" over "11 green, 1 red" is refused; this holds at head and its pin is kept by name. Fails when: the swapped line passes. (Corrected at Step 2: done by 1.27.0 T14, pinned by the sitrep-card suite.)
- AC-24.2 The words, rehearsal and sitrep-card suites run the binding rule over the metric rows they feed. Fails when: any of the three lacks a row that reddens on the swap.

### REQ-25 — Step-field 8 takes the triple

The Step-8 fields are written in one call, and an unknown field's refusal names the verb that writes it.

provenance: 1.26.0 Known limit 10 (T8.md Holes, A-T8.8)

- AC-25.1 `step-field 8` takes `merge=`, `worktree-removed=` and `cleanup=` in one call, its usage names the live fields, and an unknown key's refusal names the verb that writes it from a key-to-verb table (D21). Fails when: the triple needs three calls, or a `foo=` refusal names no verb.

### REQ-26 — Suites are suites

A brief may name only real suites, a live contract's suites can be narrowed, and no suite header names a deleted suite.

provenance: 1.26.0 Known limits 14 and 11 (A-orch.29, A-T8.5)

- AC-26.1 The dispatch's collector hands the wall the set of suites under `tests/` and the wall refuses a `Suites:` or `Lands-on:` entry outside it (D6); `amend --suites=` narrows a live contract's suites and its lands-on with them; `render.test.sh`'s header names no deleted suite. Fails when: `Suites: foo.test.sh` with no such file passes the wall, or `amend` can only widen.

### REQ-27 — Green-at sees linked trees

The green-at check finds a commit held in a linked worktree, and the ready event carries the branch and tree it was given.

provenance: 1.26.0 Known limit 9 (T6.md Holes)

- AC-27.1 `row-landed`'s `ready` event carries `branch=` and `tree=` when given. Fails when: the event reads `branch=- tree=-` after both were given. (Corrected at Step 2, D26: a probe at design showed a linked tree's commit resolves from the root, so the `--green-at` refusal was correct and is kept.)

### REQ-28 — One writer-room arithmetic

The tick, the dispatch wall and the stop wall agree on how many writers fit, from one function, and idle writer slots are named.

provenance: 1.26.0 Known limit 22 (A-orch.33, A-orch.42); debt `tick-idle-width`

- AC-28.1 The tick's FILL, the dispatch wall and the stop wall read the writer cap's room from one function that carries the scale's own cap (D22), and the FILL names when writer slots sit idle behind one pending row. Fails when: a FILL names a row the wall refuses on room, or idle slots go unnamed.

### REQ-29 — The judge knows the docs home

A commit that touches only the docs home is prose to the judge, so publishing docs never owes a regression run.

provenance: ideas/judge-knows-docs-tracked.md (wave 44 Step 7, aee9451af)

- AC-29.1 A commit whose every path is under the tracked docs home (`docs-tracked:` or `docs/`) is prose to the facts judge, for every question and the regression; a fixture plants a `docs/` commit after a review and expects `cover … prose`. Fails when: a promotion commit owes a regression run.

### REQ-30 — The cap bites at task-add

A task title over the cap is refused when the task is added, with the card's own words, not later when the card draws it.

provenance: ideas/title-cap-at-task-add.md (T16, T19, T21); 1.27.0 critic-adversarial-3.md#2 and critic-structure.md#2 (adopted)

- AC-30.1 `task-add` and `task-set` refuse a title over the 30-column cap with the words the card prints, so `card.test.sh` never reddens on a plan row. Fails when: a 31-column title lands in the Tasks table.
- AC-30.2 `task-add` ends on one line naming what the turn owes, the task-list entry by the row's title, so the rule fires at the act (D7). Fails when: `task-add` prints no owed line, or names the wrong title. (Corrected at Step 2, D7: as approved it restored a step-text sentence the doctrine budget cut.)

### REQ-31 — Explain keeps the detail

Explaining a decision on the design card prints the decision's detail, not only its title.

provenance: 1.27.0 critic-adversarial.md#6 and critic-evidence.md#3 (adopted; AC-14.1 waived)

- AC-31.1 `card.sh step2 <spec> explain <D-id>` prints the decision's detail written after the `(D<n>; REQ…)` group on a real spec, and the pin places the detail where a real spec writes it. Fails when: explain prints only the title, serves and ADR over the wave-44 spec.

### REQ-32 — A title is refused, not cut

A title over the cap is refused whole, never cut at an abbreviation.

provenance: 1.27.0 critic-adversarial.md#7 (adopted)

- AC-32.1 A first sentence holding an abbreviation such as `vs.` is not cut at it: a period followed by a space and a lowercase letter does not end the sentence (D24), the title reader takes the sentence whole and refuses it over the cap. Fails when: `Draw the facts vs. the judgment` draws as `Draw the facts vs`.

## Not Doing

- The §COPY-4 arm and the freeze: neither c4-1 nor the stop wall's scale reach has a test that can fail (charter §Not this run).
- The judge one release late: heals itself from the first landing after 1.26.0; a base older than its check is a one-time cost, stated.
- The merge and the tag: the person's, after the pull request (pr dealing); v1.27.0 is untagged today and that is his.
- The sitrep verbs' plan operand: `[<plan>]` stays the suites' hermetic door, as every other plan verb has one; binding the tests to a session would touch six suites for no user-facing change (carried item 4, decided here).
- The card check's word lists: the 1.27.0 binding findings (critic-adversarial.md#2 to #5, -2.md#2 to #5, -3.md#1) are a rework of the checker's rule, not a leaf with a test; carried again.
- The slow sitrep and the golden: AC-9.1 and AC-10.1 of 1.27.0 stay waived; the mock-up is in no record (carried again).
- Five 1.26.0 limits restated: the ratio cap rule (7), the plan copies with no origin (19), the brief's stale pin (21), the `deps` cell beside `reads` (24) and the writer's idle turn (25) stand as written; limit 23 closed in 1.27.0 (T4).
- The census, REQ-25, Linux: the test census leftovers, wave 44's REQ-25 design hole and portability keep their own seeds.

## Inherited deferrals

adopted: record/wave-44-every-hand/critic-adversarial.md#9 as REQ-4
adopted: record/wave-44-every-hand/critic-adversarial.md#8 as REQ-16
adopted: record/wave-44-every-hand/critic-adversarial-3.md#2 as REQ-30
adopted: record/wave-44-every-hand/critic-structure.md#2 as REQ-30
adopted: record/wave-44-every-hand/critic-adversarial.md#6 as REQ-31
adopted: record/wave-44-every-hand/critic-evidence.md#3 as REQ-31
adopted: record/wave-44-every-hand/critic-adversarial.md#7 as REQ-32
again: record/wave-44-every-hand/critic-adversarial.md#2
again: record/wave-44-every-hand/critic-adversarial.md#3
again: record/wave-44-every-hand/critic-adversarial.md#4
again: record/wave-44-every-hand/critic-adversarial.md#5
again: record/wave-44-every-hand/critic-adversarial-2.md#2
again: record/wave-44-every-hand/critic-adversarial-2.md#3
again: record/wave-44-every-hand/critic-adversarial-2.md#4
again: record/wave-44-every-hand/critic-adversarial-2.md#5
again: record/wave-44-every-hand/critic-adversarial-3.md#1
again: record/wave-44-every-hand/critic-evidence.md#4
again: record/wave-44-every-hand/critic-evidence.md#5
again: record/wave-44-every-hand/critic-evidence.md#2
again: record/wave-44-every-hand/critic-evidence-2.md#2
again: record/wave-44-every-hand/critic-evidence-3.md#1
again: record/wave-43-no-hand-hold/critic-evidence.md#5
