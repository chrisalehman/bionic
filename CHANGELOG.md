# Changelog

Earlier releases are recorded as git tags (`v1.4.3` … `v1.8.3`) rather than in this file,
which starts at 1.8.4.

## 1.8.6 — 2026-09-23

- REQ-1: A stop closes its own roster row — the tick acks a MET row once a fresh panel
  shows its agent gone, `stop-orders.sh stopped <name>` closes a row through the same
  sweeper path, and `standdown` drops a row only when it is acked and gone from a fresh
  panel; an abandoned tree still stands.
- REQ-2: `adopt` and the tick read an adopted agent's transcript against this session's
  own subagents dir first, falling back to the launching session's; the adopt report
  says the same.
- REQ-3: The writer budget is a measurement every plan carries — a `*.plan.md` Write
  without a readable `parallel-budget: writers=N` is refused where the plan is written,
  per Chris's Option 3 ruling.
- REQ-4: The stop wall's fill arm honours a tick's `fill withheld — HOLD` or
  `… EMERGENCY` line, anchored at line start; every other tick turn is judged against
  the wall's own ready set.
- REQ-5: The tick and the stop wall count occupancy from one source — every roster row
  of this session not yet acked; a gone UNMET row is named `poker: GONE <name>`.
- REQ-6: `current:` is read by one delegating body, and a Stop parses the ledger and the
  task table once each instead of twice.
- REQ-7: Every dispatch-preflight refusal takes the same exit status regardless of how
  many faults a brief carries.
- REQ-8: A read-only role's `git commit` — test-runner, researcher, auditor, or critic —
  is refused by name; other roles are untouched.
- REQ-9: The evidence gate's jurisdiction ends at the engaged repository — a scratch or
  nested-repo commit is admitted, judged only against an exact allow-list of placeable
  `-C`/`cd` shapes, with quote- and backslash-split spellings still caught.
- REQ-10: The impact command maps a template edit to its rendered file's suites, so a
  shared-block change reaches every consumer.
- REQ-11/REQ-12: The Step-3 plan template renders one `- T<n>:` evidence stub per task
  row, and its scaffold text is trimmed to what the card actually emits.
- REQ-13: §S13.4 distinguishes a row-assembling file from a presence test, and anchors
  every docs-pins doctoring site added since.

## 1.8.5 — 2026-09-22

- REQ-1: `done` is the one terminal word at every scale; the rigor-lane verdict arms are
  step-gated (numeric `current:` ≥ 6), so a finished task-scale row is not refused for
  verdicts that cannot exist yet.
- REQ-2: The PostToolUse bind arm names every exit, resolves the plan against the session's
  own root, and `bind_plan` names which refusal fired.
- REQ-3: Readiness is computed once, in `lib/fill.sh`, and read by the tick, the stop
  library's fill duty and the card; a turn past Step 3 that ends with a fillable gap is
  refused once, tick or no tick.
- REQ-4: The card reads `scale:`; a task-scale ledger renders under its own headings, the
  floor line comes from `impact-command:`, `step2` accepts a task-scale plan, and batch
  widths are printed per dependency depth.
- REQ-5: Step 0's budget recipe is the two-call form the library implements.
- REQ-6: The brief scaffold's `Suites:` line says which shapes count.
- REQ-7: A quoted pipe in a declared run is an argument, not plumbing; the roster stores
  `re_executes` percent-encoded and every reader decodes once.
- REQ-8: An over-cap `Re-executes:` brief is refused naming the dropped run.
- REQ-9: A matrix `evidence:` cell tolerates a trailing ` — <note>`.
- REQ-10: `session-poker.sh extend <name> <reason>` re-opens a MET roster row.
- REQ-11: A substituted step is not a pointer step: a commit from a task row's tree is judged
  by that row's arms whatever `use_worktree` says; the task-scale subject fork.

### Fixes found in verification

- T8/§S13.4: `extend`'s presence tests no longer spell the row-writer's literal.
- Floor: `steps/5.md` names `jit_check` and `jit_offer` again after the byte trim.
- Walk §14: `extend` decodes the copied `re_executes` before the row writer encodes it.
- R1/C2: the stop wall's fill width is the rung the tick reads, not the declared ceiling.
- R9: an unengaged session's plan-shaped Write journals nothing under `$HOME`.
- R15: four meanings the byte trim lost are back, paid inside the same surfaces.
- C1: `_EG_SUBSTITUTED` is set on both substitution forks, so the `use_worktree: false` twin
  refuses at `current: 5` what the `true` fixture refuses.

## 1.8.4 — 2026-09-20

- REQ-1: An active task's commit is never refused by the run's floor.
- REQ-2: The landing gate charges a writer tree only with its own edits.
- REQ-3: A compound that changes directory before its commit is judged where the commit
  lands, or refused for it.
- REQ-4: A tree of another repository is exempt from this run's step arms, with the reason
  printed.
- REQ-5: Plan-authoring refusals name the cell and the shape.
- REQ-6: Close-out accepts the plan's own working-branch shape.
- REQ-7: The brief scaffold teaches the span rule the parser applies.
- REQ-8: A dropped `Suites:` token is never silent.
- REQ-9: The floor streams each suite's verdict as it lands.
- REQ-10: Advisory readings are reported apart from the gating tally.
- REQ-11: A BOM-prefixed plan gets the same loud fault list as its LF twin.

### Fixes found in verification

- R1: A trailing `#` comment on a `Suites:` line no longer triggers a dispatch refusal for
  a dropped token.
- C1: The commit-subject fork no longer raises the judged step for an `active` row below
  step 4.
- C3: A command that names one directory twice before its commit is now refused for that
  shape instead of being judged at the wrong one.
- C4: Close-out's worktree census now falls back to the tracked-branch glob when a plan's
  `## Tasks` table carries no `worktree` column, so a plan written before this wave keeps
  its unmerged-work refusal.
- R6: `units_validate`'s docblock was reconciled with its own body.
- R7: The row-invalid refusal now names all twelve columns instead of ten.
- R8: The two test sections that shared the number 13 were renumbered.

### Known carry-overs

See `.bionic/docs/ideas/next-wave-after-184.md`.
