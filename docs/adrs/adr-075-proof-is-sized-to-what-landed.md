---
governing-skill: agent-skills:documentation-and-adrs
sdlc-step: 7
epic: epic-23-bionic-tech-debt
wave: wave-47-one-pass
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
walk: required
design-interview: false Chris Lehman 2026-10-26
model_plan: orchestrator=claude-fable-5-1; implementor=sonnet-high; senior-implementor=opus-high; researcher=opus-high; test-runner=haiku-high; auditor=opus-high; critic=opus-high
status: Proposed (Step 7, 2026-10-27)
created: 2026-10-27
---
# ADR-075 — Proof is sized to what landed

## Status

**Proposed** (Step 7, 2026-10-27). D3 (green is content, not position) and D4 (the exit is the step's), with D5 and D6 beside them, were ruled "approved" at the Step-2 card on 2026-10-26, with the design interview waived. D7 (release reads with its readers) reopened D3 on the critic's adversarial finding and was ruled "2" by Chris Lehman on 2026-10-27 at 6:20 AM PDT. It amends ADR-074's reading of "ran here" and replaces nothing: ADR-074's rule stands for every commit that moved code.

## Context

ADR-074 made a head green only where the full pass ran green at it. A later head was not green until its own pass ran, whatever its landings were. 1.29.0 paid for that reading in whole runs: five whole runs of 127 suites, where one or two carried information, and three of them were started because a changelog or a test arm landed (`ideas/bionic-1.30.0-charter.md`, Phase 0). A run whose last landings are its release entry and its reviews part could never close green without a second pass or the person's word, because each of those landings moved the head past the pass.

A whole run proves the code it ran on. A landing that moved no code changes nothing that run proved, so a pass at the landing's head buys no information. The 1.30.0 charter's Phase 0 ships that as 1.29.1, beside the spike, so that no run before the kernel pays five passes for one.

This wave's own close is the proof the rule needed sizing. Its build rows ended in code, and each code landing past a pass needed a new one: the pass at the last build landing was red on one suite whose arms pinned the old line, the fix row for it was a test landing, and the critic's fix row was a code landing. The release row and the reviews part land after the last pass, and under ADR-074's reading each would have asked for another.

The critic's first read showed the release basis was too wide. A release-set commit could change what suites read, the release check suite, the command pages and the integrity manifest among them, and still read green with only the release check passing at it. D7 narrowed it.

## Decision

**The pass proves the tree it ran on.** A landing that moved no code is proved by the pass before it. The whole suite's state at a head is green when the whole run passed at F and every commit on the first-parent line from F to the head moved no code by the judge's own cover basis.

**Moved no code is prose or release.** A commit is prose when every path it touches is docs-only. A commit is release when every path it touches is in the release set, the release check passes at it, and the five suites that read the release set are green at it in the landing record: release-check, shell-lint, render, commands and words (D7). The release row lands on those five, so its own landing records the greens the judge reads. Nothing finer than prose and release is admitted.

**One printer.** `proof_whole_text` prints `green at <F8>, <n> landings since moved no code` past F (`1 landing` for one), and `green at <F8>` at F as before. The release card, the facts judge and the Step-7 judge, the tick, the regression-run verb, the situation report and the continuation all read that line. None asks a second pass for a head it reads green: the card draws no merge-unproved ask, `current 7` and `current 8` are admitted on it, the tick starts no whole run, and `regression-run` refuses there naming the pass that proves it.

**A commit that moved code reads red at the head as before.** One code commit past F, or one release-set commit without its check or a reader's green, reads `red at <F8>, <n> landings before this head`, and ADR-074's rule holds: the pass runs at that head, or the person answers the card.

**The exit is the step's** (D4). The Step-7 refusal on an unproved head names the pass and the verb that starts it: `needs: the pass — wait for it (the tick starts it once no row is ready), or start it: session-poker.sh regression-run`. It names no release-card reply, since no card exists before the release row. The Step-8 refusal names the card's reply beside the pass, as before.

## Consequences

- T1 built the printer. `proof_whole_text` reads past F through `_proof_moved_no_code`, which asks the floor judge for a covered F and then the judge's own walk, `_facts_walk`, for exactly the n first-parent commits, each prose or release.
- T2 had the tick and the verb read it. `tick_regression_start` starts nothing at a head the printer reads green, and `regression-run` refuses past F with the printer's line, the pass's log and the exit `spawn-worktree.sh ready`.
- T3 made the exit the step's. `proof_unproved_needs` takes the step, and `cur7_judge` re-prints an unproved regression line with the Step-7 exit.
- T11 moved the situation report's pins. The first whole run was red on sitrep.test.sh, whose two arms pinned the old red line at landings past F that moved no code. They now pin the green line, and a third arm pins the red line at a code landing.
- T12 gave the release basis its readers. `_proof_release_readers` names the five suites beside the release set, and `_proof_release_proved` prints the commits at which the check passes and every reader is green. The full pass, the facts judge's review chains and the cover read it.
- T4 and T5 sit beside them. T4's `promote` writes its copy in the checkout it runs from and names the tree when it is not the state home (D6). T5's two regression paragraphs state the rule above (D5). This ADR was promoted from its row's own tree by that verb.
- It does not size the pass finer. A landing that moved code is proved by a whole run at it, as before, and which suites a landing owes is the kernel's question. The reconcilers named in the run's Not Doing are the spike's to map.
- Two limits ship with it. A release row landed by hand never reads release, because its reader greens are written inside the row and not at the merge the judge asks, so such a head pays a whole run or the person's word. A commit that touches CHANGELOG.md alone reads prose with no suite asked, though the release check suite reads the real CHANGELOG.md.
