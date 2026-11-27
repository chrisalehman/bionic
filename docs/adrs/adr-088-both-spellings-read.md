---
governing-skill: agent-skills:documentation-and-adrs
sdlc-step: 2
epic: epic-23-bionic-tech-debt
wave: wave-53-one-home
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
status: Proposed (Step 7, 2026-11-27)
created: 2026-11-27
---
# ADR-088 — Both spellings read

## Status

**Proposed** (Step 7, 2026-11-27). Written after the build, from the spec's decision D26 of wave 53 (added by the person on 2026-11-24) and from what the build did. No record was drafted at Step 2. Checked against the settled head of the run, `5074682017bb`.

## Context

The tool called every check of a criterion an eval. A plan and a spec head their criteria table `## Eval design`, with the columns `Eval type` and `Eval`, and the cards, the refusals and the pages used the same word. Most of those checks are deterministic: unit, integration, hermetic or end-to-end tests. The word eval more usually means a test of a model, which passes by reaching a threshold a stated share of the time. The person asked on 2026-11-24 for the word test for a deterministic check, with eval kept for a test of a model.

The research found three facts. The table's column headers are the parsed format: a header becomes a key by being lower-cased, with blanks turned into `-`, so `Eval type` is the key `eval-type`. Every reader took exactly one spelling, and three code paths read the keys by name. And 70 pages on disk carried the old heading. The installed 2.2.0 readers take no other, so the run that made the change could not write its own pages in the new words.

## Decision

New pages use the new words, and every page on disk still reads as it did.

- A new page heads the table `## Test design`, with the columns `Test type` and `Test`.
- The readers take that heading and those columns or the old ones. Both spellings are mapped to one set of keys, `test-type` and `test`, at the one place a header becomes a key, `payload/scripts/lib/plan-read.sh`. The card's own parse in `payload/scripts/card.sh` takes both headings.
- A criterion's sum is taken with its keys spelt the old way, so the sums a landing compares do not move when a page is written in either spelling.
- The cards, the reply words, the refusals and the pages say test. The Step 2 card's view word is `tests` (`card.sh step2 <spec> tests <REQ>`), and the Step 3 card drops its `show evals` offer, which had no view behind it. The main skill page defines the two words once.
- Released history stays as written, and so do the words that mean something else: the shell's `eval`, `mongosh --eval`, the browser skill's `eval` verb and the English verb evaluate.
- No version number moves: the plan format stays at `canonical_sdlc_version: 15`.

## Consequences

- A page written under 2.2.0 needs no migration.
- A script that reads the card's old words, the reader's printed keys or a refusal that named the Eval design sees the new ones. The release entry says so.
- Every reader of the table has two spellings to take, held by one test that reads one fixture plan written both ways. With the map removed, that test goes red on an empty test type.
- The next rename of a page word has a pattern to follow: map the old word at the one place a header becomes a key, and leave the pages on disk as they are.

## What the build taught

- **The run that made the change could not use it.** This run's own spec and plan kept the old words to the end, because the installed 2.2.0 readers take no other. The new words are first written by the run after 2.3.0 is installed.
- **One printed word changed, and the rest was naming.** Four rows built it. The reader's row made the map and the two-spelling heading, and its answer now prints the new keys. The tool's row changed the words a person sees and re-pinned only the strings those words moved; the view word is the one change of behaviour. The pages' row put the definition in once and kept the pages every session loads at net zero. It cut three sentences that ordered no act, and the loaded pages ended 95 bytes smaller. The fixtures' row moved 51 lines that wrote the old words and kept 14 on purpose: the replay plans and the old-words fixtures are the proof that an old page still reads.
- **No reader that took only the old word was found.** A suite that turned red on the new words alone would have found one. None did.

## Alternatives rejected

- Migrating every page on disk to the new words: 70 pages, and the installed release's readers would then read none of this run's own pages.
- Keeping eval for every check: it names a deterministic test by the word for a statistical one, which is what the person asked to stop.
