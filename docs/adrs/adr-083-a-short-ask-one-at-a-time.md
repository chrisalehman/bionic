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
# ADR-083 — A short ask, one at a time

## Status

**Proposed** (Step 7, 2026-11-22). Drafted with the spec of wave 52, and checked here against the settled head of the run, `6d523e840da4`, its walk and its reviews.

## Context

Wave 51's register holds 41 asks. Twenty-two were put to the person in conversation. By the research's sorting, 13 were the person's, 7 were calls the orchestrator could have made and reported, and 21 were forced by the tool: opened in the person's name for a state the tool caused, or one that work closed without them. The smallest decision ran 18 lines; the close put about ten items in two messages. The pages that tell an agent when to ask give three different tests: whether a call can be reverted, whether it is strategic, and whether any judgment is involved. None says who decides a push, a tag, a merge, a rewrite of history, the git identity, a file in the person's home config, or a waiver the tool opened.

In this run's own design interview the long form failed twice: one decision had to be asked again in plain words, and one offered an option the person had already ruled out.

The person ruled on 2026-11-20: D9 ("approved").

## Decision

1. **One rule says whose call it is.** A call is the person's when it is hard to undo, changes what the release contains, leaves this machine, or spends money. Every other call is the orchestrator's: it makes the call and says what it chose in one line. A push, a tag, a merge, a rewrite of history, a change to the git identity and a change under the person's home config leave this machine or are hard to undo, so they are the person's; the release approval covers the push, the pull request and the tag of that release. A waiver the tool opens is the orchestrator's to close by work, and becomes the person's only when it is put to them.
2. **The short form is the default.** A few plain sentences: the question, each option in a line, the pick and why, and the reply line. The long form with labelled parts is kept for a call that is hard to undo.
3. **One question per message.** A decision waits for the person's answer before the next is put.
4. **No option reopens a ruling.** A decision already ruled comes back only as a reopening with new evidence, never as an option of another decision.
5. **An act is asked for as an act.** Something only the person can do, a restart among them, is one line that says what to do, with no decision number.

The decision skill owns these five. The method's page, the Step 2 page and the dispatch page point to it and state no test of their own. A suite reads the rule from the real skill and fails a copy of any of the three pages that states a test of its own or holds no pointer.

## Consequences

- The Step 2 rule "a strategic choice gets a question" is gone. The design interview's decision map names each choice ahead as the person's or the orchestrator's by the skill's rule; a choice that is the orchestrator's is made and shown at the design card.
- The dispatch page's "stop and surface" stays for what the rule gives the person and for nothing else.
- The working principles are not changed by this decision. The person cut that proposal: "Decide what is yours" already says to make a call that can be reverted.
- The measure of asking counts only what was put to the person (D29, D30 of the spec). An ask counts from the instant it is put, and a waiver the tool opened and never put adds nothing.
- In the walk, a session given a call that the plan left open made it, wrote it into the plan's row and reported it to the person in one bullet. It put no decision and opened no question.
- The rule did not bring the count of asks under wave 51's. The scorecard at `6d523e84`, read on 2026-11-22, prints `asks put to you: 13 · 138 min` for this run against `5 · 364 min` for wave 51. The person waited for less than half the minutes and was asked more often. The count rose from the walk's 9 to 13 with the decisions put after it, three of them (D40 to D42) put ahead of time so that the pull request and the close would not meet them. The criterion that both numbers fall (AC-28.2) is not met, and the person waived it in D38 ("D38: 1"). Whether fewer asks needs another rule, or only fewer calls the tool forces, is not known from one run.

## Alternatives considered

- The rule written into the working principles: proposed and cut by the person ("This is too much I think").
- A cap of several small decisions a turn: the charter asks for one at a time, and the person approved one.
- The long form kept for every decision: it is what failed.
