---
paths:
  - "tests/*.sh"
---

# Test harness traps

The first two entries below were migrated from bionic's retired memory tier (ADR-002) at
epic-12 wave-01 slice 6. Both are `installer-behavior.test.sh` gotchas that existed nowhere else in the corpus. That suite and
the `claude-bootstrap.sh` installer it exercised were both deleted at epic-17 W5 4/6 (commit
`2ac5d48`) — the traps below are kept as historical record of a shape a future suite could
still fall into, not as live coverage; nothing in the current tree pins either lesson.

- **`tests/installer-behavior.test.sh` used to extract ONLY functions named in its `for fn in` awk
  loop — internal callees were NOT pulled in implicitly.** A missing callee 127s silently
  inside `step_stream` (swallowed as a normal step failure). Any harness built the same way should
  list every helper it calls too. Bit epic-04 slice 4/2, 2026-07-15.

- **`tests/installer-behavior.test.sh` ran `set -uo pipefail` but `claude-bootstrap.sh` ran
  `set -euo pipefail` — errexit behavior went untested by default.** Any fail-open claim about a
  script pair shaped this way needs a `(set -e; fn)` subshell regression test. Bit epic-06: a bare
  `cat` command-substitution aborted the whole bootstrap on an unreadable `.links` entry.

- **`bash tests/run.sh` is the one gating command.** Its roster is every `tests/*.test.sh`,
  sorted and read at run time — location is the declaration (fixit 1.5.1, D-1): a suite gates
  by being in the directory, and a roster wall refuses any glob match that isn't shaped like a
  suite. See `tests/run.sh` for the wall's shape rule — it is not repeated here
  to avoid a second stale count. (There was once a Docker mock e2e suite,
  `tests/bootstrap-e2e-docker.sh`, run alongside this roster; it was deleted at epic-17 W5
  alongside the installer it exercised — `tests/run.sh`'s own header records it — and nothing
  in the current roster replaces it.) There is no CI — this suite is the gate. A green run still says nothing about the hooks a SESSION actually loads: the
  suite exercises `hooks/*.sh` in the tree, while what gates a tool call is the copy inside
  the payload the CLI resolved for the installed plugin. After a hook change, install the
  plugin and let `/bionic:doctor` say which root answered before believing a wall is live.

- **The roster is the directory. A new `tests/foo.test.sh` gates on the very next run** —
  no `run` line to add, no second list to keep in step (fixit 1.5.1, D-1). This corrects a
  real failure, not a hypothetical: a since-deleted root wrapper script once hand-listed its
  own suites and produced exactly this false green when it forgot one, which is why
  `tests/run.sh`'s roster wall now refuses any glob match that isn't shaped like a suite.

## Fixture fidelity

Suites cite this rule by its name, "Fixture fidelity", in their FIXTURE FIDELITY block.

- **A green test proves nothing if its fixture removes the condition the test exists to
  check.** When a fixture confirms a row, ask what it *pins*, not only what it asserts. The
  tell is that the fixture controls a variable the criterion's failure mode depends on.
- **Each suite opens with a FIXTURE FIDELITY block.** It declares what every fixture pins and
  where each shape was measured, or marks the fixture SYNTHESIZED.
- **Prove a repair can fail.** Run the new test against the pre-repair code (`git show
  <sha>:path` into a scratch copy) and show the specific arm failing while its siblings stay
  green. That separates the wiring under test from suite-wide breakage.
- **Re-execution shares the harness's blind spot.** An auditor inherits the harness the thing
  under test ships with, so re-running it repeats a shared blind spot rather than breaking
  the tie.
- **Where it bit.** Two epic-12 matrix rows were CONFIRMED by independent auditors on exactly
  this error. One gate sat behind `[ -z "$PLAN" ]` while production always had a plan, and
  every test faked `HOME` with an empty plans directory, so the gate was dead code. Two hooks
  had per-hook fixtures asserting contradictory things about one placement, both green,
  because no test asked both hooks about one file.

## Anti-vacuity

Suites cite this rule by its name, "Anti-vacuity", in their ANTI-VACUITY block. A suite that
has quietly stopped testing anything stays green, so vacuity is prevented when the test is
written, not detected afterwards.

- **A negative never stands alone.** Every negative or empty-readback assertion sits beside a
  positive on the SAME extractor in the SAME fixture, or it is not written.
- **Prove the subject and the extractor first.** A suite refuses to run when its subject is
  missing or will not parse. Before trusting an assertion that reads through an extractor or
  parser, prove it returns non-empty on real output.
- **Rule-bearing fixtures get a differential or mutation control.** Run the fixture once with
  the feature and once with it removed, and the answer must move. A mutation check asserts
  the mutant still runs (`bash -n`, or a positive line) before reading its absence.
- **macOS awk and multibyte glyphs.** Never compare a multibyte glyph with `==` under macOS
  awk. Use `index()`.
- **Extract the one line.** A glob over a whole rendered run spans lines and can match a
  different renderer's copy. Extract the line (`grep -F`), assert on it, and add a `test -n`
  row.
- **Never assert on a truncated tail.** Assert on an unlossy source, or on a difference
  between two renders of one machine.
- **Classes seen.** Extractors anchored on deleted headings returning "", update arms piping
  `y` to a question no longer asked, a cross-fixture variable leak, a "healthy" fixture that
  rendered problems, and a doctored copy that died silently. Each was caught only when RED
  was re-taken against `git archive <base>` with the final test files.

## Writing and pinning tests

- **Good tests.** Ratified 2026-08-22: tests that check behavior are good. Tests that pin
  output text are bad. Tests that re-prove the world instead of their own diff are bad. A
  suite that only pins text is a delete-or-merge candidate.
- **Pins guard spans, not labels.** Pin the obligation span or the normative literal, never
  the section label. A whole-file presence pin misses drift in one copy of a repeated phrase,
  so scope it to a count.
- **Seam blindness.** A seam that substitutes the very value under test leaves the production
  capture path unproven (mock green, real red). Test the arm-side capture as well as the use
  side.
- **Accelerate clocks under test.** Verify time-driven machinery at an accelerated cadence
  unless the cadence itself is what's under test.
- **Bulk-deletion scars.** Scripted deletion of assertions leaves scars: emptied skeletons,
  orphaned continuation args that still execute, dead fixture dependencies. Verify each
  touched suite with strict stderr, not rc alone.

## No exact counts of the shipped tree

No test pins an exact count of things in the shipped tree. A count of chips, role files,
suites or mentions goes red on every legitimate addition, and the repair is retyping the
number, which proves nothing. Two forms are allowed in its place:

- **A relation.** Assert what each item must satisfy, and add one row that the set is not
  empty so the relation cannot pass over nothing. Example: every version chip in
  `hook-chain.svg` carries the supported version, plus a row that at least one chip exists.
- **A ceiling.** Assert a bound the tree must stay under. Example: the role files total at
  or under a byte cap; a loader span at or under its cap; a command under its time limit.

An exact number is fine when the number IS the behaviour: an exit code, a pass count equal to
the total, the width a function prints, or a fixture the test built itself (three planted
entries, three found). Prove a conversion the way `§PIN-REL` does, on a COPY with an item
planted (stays green) and with every item removed (the non-empty row is red).

## Running suites and drives

- **Explicit bash, never zsh.** Run a `#!/bin/bash` library or PoC under explicit `bash`.
  Sourced into zsh, `git cat-file -e` can spuriously return nonzero.
- **Floor output is not progress.** `tests/run.sh` prints nothing until its queue drains. Read
  the process table for liveness, never the output file.
- **Print-mode facts for T3 drives.** `claude -p` facts: a plugin dependency is keyed by
  `name@marketplace` and an unsatisfied one means the plugin doesn't load at all. A fresh
  `CLAUDE_CONFIG_DIR` needs `/login`. `stream-json` needs `--verbose`. T3 drives use the real
  home and a throwaway project.
