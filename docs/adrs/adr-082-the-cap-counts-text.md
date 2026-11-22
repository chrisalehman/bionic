---
governing-skill: agent-skills:documentation-and-adrs
sdlc-step: 7
epic: epic-23-bionic-tech-debt
wave: wave-52-driven-with-less
intent: build
rigor: double
scale: wave
canonical_sdlc_version: 15
surface_type: cli-plugin
language: bash
has_ui: false
multi_agent: true
deploy_target: n/a
cleanup_on_finish: true
use_worktree: false
walk: required
design-interview: true
model_plan: orchestrator=claude-fable-5-2; implementor=sonnet-high; senior-implementor=opus-high; researcher=opus-high; test-runner=haiku-high; auditor=opus-high; critic=opus-high
status: Proposed (Step 7, 2026-11-22)
created: 2026-11-20
---
# ADR-082 — The cap counts text, and the person's word moves the judge

## Status

**Proposed** (Step 7, 2026-11-22). Drafted with the spec of wave 52, and checked here against the settled head of the run, `6d523e840da4`, and its reviews. It extends ADR-068, which set the cap, and keeps ADR-068's purpose: the test tree may not outgrow the code.

## Context

ADR-068 capped tests at the code, counted in lines of tracked shell files. Wave 51 closed with 94,717 test lines against 94,718 of code. Two faults showed. Joining lines lowers the count, so five rows joined test lines to fit, and a red then prints a joint value. Deleting code lowers the allowance, so nine dead helpers (285 lines by the research's count) could not be deleted.

A second fact stands under both. Every landing and the release check run the copy of the check held by the release base, the nearest tag merged into the integration branch, so that no landing can loosen the check that judges it. A new measure written in a release therefore judges nothing until the release after.

The person ruled both questions on 2026-11-20: D7 ("D7: 1") and D6 ("Option 2", after "No separate release").

## Decision

**The cap counts characters.** The check reads the non-whitespace characters of the tracked, non-link shell files under `tests/` against those everywhere else, in the tree of the head it judges, never the working files. Tests may be up to 1.25 times the code. The code's count is the largest of three: the head's, the landing's base's and the last release's. A landing's base is the target's head before it, so the last release's count is what keeps code deleted at one landing from lowering the limit at the next. A head over the cap is still admitted when its tests are at or under the base's. The check's line states the reading, the limit and the room left: `test-ratio: <tests>/<code> chars · limit <n> · room <n>`. The release card's Tests line and the situation report's `tests.cap` line read it from the check's newest log through one function.

**The person's word moves the judge.** `session-poker.sh check-from '<words>' [<commit>]` writes one judge event to the run's log. The words must stand in a prompt the person typed in a session of the run. The commit, the working head unless one is named, must be one the working head holds, and a judge at the head itself is passed over. The verb is on the walls' list of contract verbs, so a dispatched agent's call is refused. When the newest judge event names a commit, the landings and the release check after it are run by that commit's copy of the check. With none, the judge is the release base, as before. The landing line and the release approval card name the judge and whose word set it.

## Consequences

- Joining lines changes no reading. Deleting code refuses no head and takes no room from the row after it.
- The row that landed the new check was judged by 2.1.0's copy, with one line of room: its shell diff was net −1 line of tests against net 0 of code.
- The person's word moved the judge to `5f263102` on 2026-11-21 ("Yes, the new test-size limit applies"). Its event was first written under the test fixture's name, which the checkout's config held then. It has been recorded again under the person's name, so every landing line and the card name the person.
- The nine helpers were deleted in this release, after the judge had moved: 295 lines with their separators. That landing's check printed room 237,290.
- A run can now change its own judge, on the person's typed word and on nothing else. The rule that no landing judges itself holds: the judge is always a commit that the landing it judges did not write.
- 1.25 is one number. At 2.1.0 tests stood at 1.195 times the code (5,164,952 characters against 4,322,784), with 238,528 characters of room. The release check at `1f506195` printed `test-ratio: 5365552/4433339 chars · limit 5541673 · room 176121`. At `6d523e84` the same count, made by a copy of the check's counting function and not by the check, reads 5,369,032 against 4,433,936, room 173,388, 1.211 times the code. This release spent about 65,000 characters of room, so at its pace the room lasts between two and three more releases.
- The card's cap line is the newest release check's, so it can stand a head behind the working head until the check runs again.

## Alternatives considered

- A release of its own for the new check: refused by the person.
- The line cap kept for this release, the new one in force from the next: the person's first proposal; this release would have had one line of room.
- The judge moved automatically by any landing that changes the check: a landing could then loosen the check for every landing after it.
- Bytes, non-blank lines, shell words, a count of test rows, a budget set per release, no cap, a budget of run time: laid out with numbers in `record/wave-52-driven-with-less/research-cap.md` section 4. Characters are the only unit joining cannot shrink; a ratio whose code count never falls is the only form that needs nobody's attention between releases.
