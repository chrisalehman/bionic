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
status: Accepted (Step 7, 2026-10-20, 1.23.0)
created: 2026-10-19
---
# ADR-063 — The core script is eight files, cut by function, and a test reads a file

## Status

**Accepted** (Step 7, 2026-10-20, 1.23.0). Proposed at Step 2, 2026-10-19. On Chris Lehman's rulings D11 "1", D12 "1" and D5 "1".

**Amended by** ADR-065 (Proposed 2026-10-19), which keeps the eight parts and withdraws the rest: a test declares no parts it reads, and no proof is keyed by a file's content, because the reads index is deleted. The Decision below is as it was ruled; ADR-065 states what no longer holds.

## Context

The core script was one file of 15,715 lines holding the dispatcher, the judge, the landing line, the proof record, the roster, the tick, the situation report and the plan verbs. Every test that drove any verb read the whole file, so a one-line change anywhere moved nearly every test's key: 62 of 63 suites re-ran for a one-line change in 1.22.0, 58 minutes. Narrowing a test's read to functions and sections inside the file reached 39% of it at best, because the verbs are case arms under banners that span half the file. The measured misses of 1.22.0 were this file's size.

## Decision

The script becomes eight files. The dispatcher stays at its path and name, holding the loader, the parse case, the common helpers and the plan transaction, and loads seven parts under `hooks/poker/`: the judge, the line, the proof record, the roster, the tick, the situation report, the plan verbs. Each part is one concern with its own tests. The dozen general helpers two parts share live in the dispatcher, so no two parts call each other both ways; the two true dependencies are declared loads. A test declares the parts it reads at file grain, and the proof key is the file's content; the function and section grammar stays available and is retired on the old file. The heavy tests are cut along the same seams, each part reading one part file.

Every entry point stays: the verbs the model types, the Patrol prompt's path and `tick`, the scripts that run verbs, the loader block's byte-identical pin.

## Consequences

- A change to a part runs the tests that reach that part. The 55-suite goal becomes reachable for every part; the 15-minute goal rests on the suite splits as well.
- A file is the grain a test reads. Reach is one derivation, shared by the landing's selection and the judge's key, so they cannot disagree.
- The 974 function and section declarations written in 1.22.0 go with the file they named.
- A new verb goes into the part that owns its concern, never into the dispatcher; a helper two parts need goes into the dispatcher.
- The scan edges that put every library into every test's closure are cut with the split, so the regression owes what a change reaches.

## Alternatives rejected

- Three parts by kind (library, verbs, tick): the verbs file stays 8,000 lines and the goal is missed for most changes.
- One file per verb: fifty files, the shared helpers called from everywhere, the cycles multiplied.
- Keeping the function grammar on the parts: two grains to keep correct for a gain the parts already give.
