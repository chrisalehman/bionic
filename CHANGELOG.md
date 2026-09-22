# Changelog

Earlier releases are recorded as git tags (`v1.4.3` … `v1.8.3`) rather than in this file,
which starts at 1.8.4.

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
