---
governing-skill: agent-skills:documentation-and-adrs
sdlc-step: 7
epic: epic-23-bionic-tech-debt
wave: wave-43-no-hand-hold
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
status: Accepted (release 1.26.0, 2026-10-22; D3 ruled 2026-10-22)
created: 2026-10-22
---
# ADR-070 — The judge of a landing is the last release's check, a fixed commit that no landing can rewrite

## Status

**Accepted** (release 1.26.0, 2026-10-22; D3 ruled 2026-10-22). On Chris Lehman's ruling D3, option 1 (wave-43 design-ledger Δ4). The declared list that replaces the closure (D5) was a default surfaced at the design's approval and approved with it (Δ3, Δ7).

## Context

Bionic judges a landing with its own release check, and until 1.26.0 that check ran in three places from three copies. The `release-check` verb ran the working head's own copy. The door ran the accepted head's copy. The hand scan behind `row-landed --by-hand` ran the copy of the commit just landed (research-door-map §1). A change to the check was therefore judged by itself, or by whichever copy the place happened to hold.

The door tried to close that hole by guessing which files the check loads. A closure read the check's command, followed the `source` and path words it could see, and refused a landing whose range changed any of them. It missed 14 of the 20 libraries the poker loads (research-door-map §1), and the last six hours of wave 41 went to it. Wave 43 met the same cost at its first landing: the row that pinned the judge was refused by the closure's own arm, since it changed a file the closure named, and went in by hand.

Wave 42 then built in seven hours and spent nine more closing by hand, and the release check was the one place that caught a hand-edited entry, which is why the numbers check had to survive any change to the judge.

A second flaw sat under the first. A check run in a landing tree finds no plan and no record, since `.bionic/` is not tracked. Its plan-reading checks, the Known limits and the landing numbers, then passed with one line each and judged nothing. And the line rendered the entry's numbers with the running plugin's `release-note` while the judge compared them with its own, so the two could disagree about the same entry.

## Decision

**The judge is a fixed commit.** The judge of a landing is the release base: the nearest release tag below the head on the integration branch, the commit `release_base` already finds as the start of the range. It is one commit per judged range, the same commit in every place the check runs, and never the head being judged. For a head that is itself a release, it is the release before it.

**One function runs the check.** `worktree_check_run` in `lib/worktree.sh` takes the project, the plan, the judge and the range. It materialises the judge in a landing tree, the one the door already builds, and runs the declared command there with `BIONIC_CHECK_PROJECT` set to the project root. The check reads the project's plan, its record and `release-note` from that variable and never from its own tree. The verb, the door and the hand scan each call this one function (T2). The `judged-by=target` refusal is deleted, since no copy of a check being changed is ever the one that judges the change.

**The judge's copy renders the numbers.** The line renders the release entry's `### The landing numbers` block with the judge's copy of `release-note`, in a landing tree at the release base, and the check compares the block with that same copy. A change to the format of the numbers therefore takes effect one release late: the release that changes it still shows the old shape in its own entry, and the next release judges the new one. This is the price of a judge that cannot be rewritten by the landing it judges, and Chris Lehman chose it over the head's copy rendering (which runs one piece of the head's code inside the judge) and over dropping the numbers check (the one check that caught wave 42's hand-edited entry).

**The check's files are a declared list.** `release-check-files:` in `.bionic/config.yaml` is a space-separated list of paths or globs. A landing that changes a listed path is named on the release card's line and the landed line's `judged-by=` field, as information. It is never refused for it, because the judge is already fixed (T3). The closure and its tests are deleted in the same landing, by the condition Chris set on the design's approval: a row that deletes code deletes the tests that pin only that code.

**Past judgment, one landing is admitted.** Once the plan reads `current: 8` or `9` the door refuses every landing but a fix born of a failing review, named by its `--born <record>#<n>` marker. Its green landing is what answers the review, through the one derivation the gate and `current` read, and when the review no longer fails the register's `waive:<q>` ask closes. The step never moves back (D4, T4).

## Alternatives considered

- **The installed plugin as the judge (rejected).** It holds no `tests/` and lays its libraries out as `scripts/lib`, so it cannot run bionic's own check. The release tag is the one source every project has.
- **The head's copy renders the numbers (rejected).** The judge would run one piece of the head's code, which is the hole the pin closes.
- **Dropping the numbers check (rejected).** It is the check that caught a hand-edited entry.
- **The check owns one directory (rejected).** Bionic's check loads twenty libraries outside `tests/lib/`. A list says what a directory cannot.
- **Keep the closure and fix its misses (rejected).** The closure guessed, a guess misses, and a refusal built on a miss is a hand landing in waiting. A list the project writes cannot be wrong about what it declares.

## Consequences

- A change to the release check is judged by the last release's check, in every place the check runs, and `judged-by=` names that commit.
- The check reads the project's plan and record, so the Known limits and the landing numbers are judged in a landing tree as they are in the project's own.
- A project whose release base predates its `release-check:` script is refused by the check's own missing file until its next release. A project with no release tag keeps the `base-sha:` fallback, with its own head as the judge.
- A check that ignores `BIONIC_CHECK_PROJECT` judges nothing of the plan. At 1.26.0 the judge is still the 1.25.0 copy, which does so, until 1.26.0 is itself the release base. Wave 43's own landings pass the Known limits and the numbers with "no plan names release" until then.
- A format change to the landing numbers takes effect one release late.
- A script that read the check's files off its command, or called a closure function, now reads `release-check-files:`. The four closure functions no longer exist.
- A landing that touches the check no longer needs a hand landing. A hand landing records its suites like any other (T6).
