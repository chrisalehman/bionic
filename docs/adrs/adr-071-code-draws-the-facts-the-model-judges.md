---
governing-skill: agent-skills:documentation-and-adrs
sdlc-step: 7
epic: epic-23-bionic-tech-debt
wave: wave-44-every-hand
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
model_plan: orchestrator=claude-fable-5-1; implementor=sonnet-high; senior-implementor=opus-high; researcher=opus-high; test-runner=haiku-high; auditor=opus-high; critic=opus-high
status: Accepted (release 1.27.0, 2026-10-24; D6 and D7 ruled 2026-10-23)
created: 2026-10-24
---
# ADR-071 — Code draws the facts, the model judges

## Status

**Accepted** (release 1.27.0, 2026-10-24; D6 and D7 ruled 2026-10-23). On Chris Lehman's rulings D6, option 1 (wave-44 design-ledger Δ6) and D7, option 1 (Δ7), with D8 beneath them (Δ9) and the check's rule taken from his words at the design (Δ11). D6 reopens wave 42's D1 "2" on a measurement, and D7 reopens wave 42's rule that every open ask is answered once.

## Context

A sitrep is the card that tells the user what the run owes them and what to do next. Wave 42 built it for completeness: the model wrote every row, and a check refused the card when any register item went unanswered. Two facts from the first days of use broke that design.

The first is time. A sitrep took a median of about 95 seconds, and about nine tenths of that was the model typing. The first judgment turn took 36 to 44 seconds, each refused card cost a rewrite of the whole judgment at 12 to 14 seconds, and the last 13 seconds went to retyping the printed card into the reply (research-sitrep-latency.md). The rows it typed and retyped were facts the verb already held: the task list, the metrics, the blocked flag and the predicted close. The refusals were mostly about those facts, since the model mistyped a number or placed one beside the wrong word.

The second is materiality. A card of 63 rows, drawn for a run of an earlier release, restated a ruling as its call to action, listed fourteen register items under its Assessment, and named a merge blocked that was waiting on a re-review. All three came from one gap. The register held an ask's kind in its key prefix and nothing about its answer, so a waiver the user had answered no still read as an ask on the user. The card was complete against the register and answered a question nobody asked, which was whether the register was covered.

Three rules for what blocks the user had also drifted apart. The sheet, the handoff head and the Patrol line each decided separately, and the card verb inferred blocking from the `holds=` field when the field was missing.

## Decision

**Code draws every fact, and the model writes the judgment (D6).** The card verb draws the head, every step and task row, the Metrics table, Blocked on you, the counted line of items that wait on events, and the predicted close with its basis, all from the saved sheet. The model writes seven lines in six tags: `purpose:`, `call:`, `grade:`, up to three `point:`, an `ask <key>:` for each ask that waits on the user, and `close:`. The `task:`, `metric:` and `ask +:` tags are removed and refused by name. The verb shows the card, so the skill never retypes it, and `sitrep card` refreshes the saved sheet's asks from the register and gathers nothing else.

**The card is the handful of facts that change what the user does next (D7).** The register tells an ask that waits on the user from an item that waits on an event. Only the first can be drawn as an ask, drive the call, or set Blocked on you. The items that wait on events are one counted line, the Assessment is judgment only, and the Metrics are numbers laid out as a table. The card opens its Assessment on what the wave is for and whether it is on course (D1), so the purpose comes before the points.

**The check refuses only a falsehood (Δ11).** Code decides the structure, the model decides the words, and the check decides the truth. It refuses a number that no sheet value holds, a number placed beside the other line's word, a task called by a state the sheet denies, a call that says nothing is owed over an ask that blocks, and a missing purpose, call, grade or close. It repairs everything else and exits 0 with a note: it folds a long line, draws a fourth point, draws an ask with no recommendation as the ask alone, and sets aside an ask line on an event-waiting key. This is Chris Lehman's rule from the design: the display should not be so rigid that the card goes through rounds of rejection and fixing to render.

**Beneath both, the register stores the answer and one function derives the wait (D8).** An answer given to an ask is written on the ask's open line as `answer=`, `answered=` and `event=` and never closes it. `ask_waits_on` reads the ask's kind and its answer and prints `user` or `event <what>`. The sheet's `waits=` and `blocks=` fields, the handoff head's Blocked on you, the Patrol line's owed count and the card's call all call it, and the fallback that inferred blocking from `holds=` is deleted. A waiver answered no waits on the review's re-run, and a finding carried to a task waits on that task's landing, which closes it.

## Alternatives considered

- **Trim the two costliest refusals and the retyped card only (Δ1, rejected).** It saves the rewrites and the last 13 seconds but leaves the model typing the facts, which is the first judgment turn and the largest share of the time. The facts could still be mistyped and refused.
- **Carry the latency to the next charter (Δ1, rejected).** The run was cut to the sitrep on Chris Lehman's word (Δ8), and the 95 seconds was the cost he named.
- **A complete account of the register with a check, as built (Δ2, rejected).** It answers every item once, which is the card of fourteen items under the Assessment. Completeness was never what the user needed from a status.
- **Trim in place (Δ2, rejected).** Caps on points and a collapsed ask list shorten the card but keep the register blind, so the call and Blocked on you stay false.
- **Back to the plain prompt (Δ2, rejected).** It halves the time and returns to facts that can be wrong again.
- **`waits-on` written as a field by every verb that opens or answers an ask (Δ9, rejected).** It is eight writers of one field. One forgotten writer brings back the vapid call, and the invariant is held by convention. A stored answer plus one function is held by the function.
- **A drawn-rows file beside the sheet (rejected).** It is a second saved artifact the model must keep consistent with the first. The verb draws from the sheet at card time.
- **Optional `task:` and `metric:` overrides (rejected).** Two writers of one row, for the sake of warmer phrasing.

## Consequences

- A sitrep's fact rows cannot be refused, since the model writes none of them. The model's lines are bound to the sheet's measured values by the check, so a number on no line, or placed beside the wrong word, is refused by name.
- A script that piped `task:`, `metric:` or `ask +:` lines to `sitrep card` meets a refusal naming the tag. The skill, every judgment fixture and the usage text carry the six tags.
- Blocked on you has one rule. The sheet, the handoff head and the Patrol line agree, since each calls `ask_waits_on`, and a pin plants an answered waiver and compares them.
- An answer is not a close. An item answered no or carry stays open on the register with its event, and a landing or a reply closes it. A waiver answered no still reaches the next release card as a decision.
- The measures that count asks that hold a task (`close.waits-on-you`, `waste.waiting-on-you`) were not changed and still count event-waiting asks. They are a Known limit of 1.27.0.
- The thirty-second target is a human measure, three typed sitreps timed at the verify step. The ADR claims the design removes the typing it measured, not that the target is met.
- The same rule of three owners is the model for the cards that follow: code decides what appears, the model decides how it reads, and the check refuses what is false.

## The rulings it rests on

- **Δ6, D6 ruled "1" (2026-10-23):** code draws the facts and the model writes only the judgment, the tool shows the card, and the model never retypes it.
- **Δ7, D7 ruled "1" (2026-10-23):** the card is the handful of facts that change what the user does next, with event-waiting items as one counted line.
- **Δ9, D8 ruled "1" (2026-10-23):** the register stores the answer, and one function says what an ask waits on.
- **Δ11, the check's rule (2026-10-23):** it refuses only what would make the card false and repairs the rest.
