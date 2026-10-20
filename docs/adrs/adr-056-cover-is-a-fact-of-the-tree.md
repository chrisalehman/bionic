---
governing-skill: agent-skills:documentation-and-adrs
sdlc-step: 2
epic: epic-23-bionic-tech-debt
wave: wave-36-zero-machine-errors
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
model_plan: orchestrator=claude-fable-5-1; implementor=sonnet-high; senior-implementor=opus-high; researcher=opus-high; test-runner=sonnet-medium; auditor=opus-high; critic=opus-high
status: Accepted (Step 7, 2026-10-14, 1.19.0)
amends: adr-054-the-floor-is-one-whole-run-plus-the-greens-of-what-changed.md
created: 2026-10-13
---
# ADR-056 — Cover is a fact of the tree

## Status

**Accepted** (Step 7, 2026-10-14, 1.19.0). Proposed at Step 2, 2026-10-13. On Chris Lehman's rulings at wave-36: D2 "1" (review cover follows what a change did, not what it was declared to be), D3 "1" (a reading registers when it is written), D4 "1" (what a suite reads is computed from the suite's text). Amends ADR-054's cover term, "a suite covers what it declares and nothing else".

**Amended by** ADR-062 (Accepted 2026-10-19), which replaced the rule that a fix row's landing extends only the reading whose finding it was born of. The Decision and Consequences below state the amended rule.

## Context

Two kinds of cover were wrong in the 1.18.0 run. Review cover: every landing after the reviewers' head invalidated their reading and cost a fresh pair of readings, even a wording fix or a fix the reviewers had asked for; and a finished whole reading could not be registered while any build row was open, so its findings sat unused. Suite cover: a landing ran only the suites its row named, and the only knowledge of which suites a file could turn red was the mutation-anchor index, which covers a few suites per file; three rows left other suites red, found hours later by a later landing or the regression. The research showed declarations and content disagree: a row declared as documentation touched product and test files; and every missed suite read the changed file by grep, sed or execution, which a scan of the suites' own text would have routed.

## Decision

Cover is read from the tree, never from a declaration.

- **Review cover follows content.** A reading is registered at the head it read, when it is written. A later commit extends it when every path it touched is prose, when it is the landing of a fix row born of a registered review finding, or when it is the landing of a row born of the regression's red. A fix row born of a registered review finding is covered for every review question once it lands green, whichever question's finding it fixed; a marker that names no registered reading owes on every chain. Any other commit owes cover, whatever its row was declared to be. The judge prints the basis per commit, and every other reader of cover — the scheduler, the registering verb — asks the judge.
- **A suite covers what it reads.** A suite reads a file when its text names the file, or when it runs a hook whose library list names the file. That fact is computed from the suites at a head and shared by the brief, the landing and the regression's cover rule. The anchor index is a subset of it and remains the mutation check. The width this adds to a landing is accepted; the regression stays the catch-all.
- **A finding fixed before or beside the reading is fixed.** It is disposed by verb with the row named, counts against nothing, and needs no born marker.

## Consequences

- A review stands across prose and across every fix born of a registered finding, for all three questions; the one exemption by intent is the fix the review or the regression ordered, and a wrong declaration is caught.
- Landings run wider on the busiest files (about six times for the wall's library); misses of the 1.18.0 kind are routed at the landing.
- ADR-054's floor term stands except its cover clause: a fix row's change is covered when every code file it touched is read by a suite the row ran.
- Rejected: cover by row kind (reviews labels, not code); a held reading (a wait protecting a rule D2 replaced); declared read headers (a second statement of what the text says); anchors alone (the state the census counted).
