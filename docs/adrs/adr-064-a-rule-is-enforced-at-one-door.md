---
governing-skill: agent-skills:documentation-and-adrs
sdlc-step: 2
epic: epic-23-bionic-tech-debt
wave: wave-40-small-files-plain-words
intent: build
rigor: double
scale: wave
canonical_sdlc_version: 14
surface_type: cli-plugin
language: bash
has_ui: false
multi_agent: true
deploy_target: n/a
cleanup_on_finish: true
use_worktree: false
model_plan: orchestrator=claude-fable-5-1; implementor=sonnet-high; senior-implementor=opus-high; researcher=opus-high; test-runner=haiku-high; auditor=opus-high; critic=opus-high
status: Proposed (Step 2, 2026-10-19)
created: 2026-10-19
---
# ADR-064 — A rule about what a writer does is enforced at one door, and an instruction is the user's words

## Status

**Proposed** (Step 2, 2026-10-19). On Chris Lehman's rulings D3 (Δ5, Δ6), D4 and D13.

## Context

Two rules were enforced where they were asked for rather than where the thing they govern happens. A standing order refusing test suites lived in the config file and was enforced by a wall that classified command text; the two commands that actually start suites in a run were not classed as suites, so the order was obeyed for a suite typed by hand and ignored for the rest. The user also had to write a config line to give the run an instruction. Separately, the question of how many suites may run at once was answered twice: by a width constant in the landing line and by the gate that admits every heavy command by the machine's room.

## Decision

A rule about what a writer does is enforced at the one place the thing it governs happens, never by recognising the commands that ask for it. The comment lint runs at the landing line on the lines a candidate adds. An order refusing suites is read by the test runner behind the gate, whoever asked. A landing asks the gate before each suite and has no width of its own.

An instruction the user gives the run is their words, recorded by a verb the orchestrator runs when they say it, with who and when, and lifted the same way. The user never writes a config line to instruct the run.

One door gets one test. A check enforced at one place is proved there, with a planted violation refused and a planted lift accepted; no test drives a caller to prove the door a second time.

## Consequences

- The config standing-orders reader, its command classifying and their test are deleted.
- A new way to start a suite, or to add a comment, needs no change to either rule.
- The decision skill, the sitrep and the review results read orders and rules from the plan, which is where they are written.
- The forecast's divisor and the landing report read the gate's admitted count; a future machine needs no change.

## Alternatives rejected

- Adding the two missed commands to the classifier: the next door is missed the same way.
- A shrinking allow-list for the comment lint: an exceptions list the size of the tree proves nothing, and the rule is about what is added.
- A width read off the machine, with or without a reserve: a brake beside the gate, paid on every landing.
