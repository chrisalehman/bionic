---
ticket: chrisalehman/bionic#48
kind: research
subject: the fifty ADRs of epic-23 read against D1 (the run's record is the truth) — stands, amended, superseded
written: 2026-10-26
head: main @ 050fa567e (code cited at that commit; `.bionic/` read in place, gitignored)
ruling: D1, `.bionic/docs/spikes/spike-kernel-map-20261026.md` §8 "Kernel options" and "The decision" (Chris Lehman, 2026-10-26 afternoon PDT, "D1: 2"); §3's "today / on the kernel" table for what each reconciler becomes
adrs: `.bionic/docs/adrs/epic-23-bionic-tech-debt/adr-001-*.md` … `adr-050-*.md`, each read whole
method: every ADR's Decision section read against D1's five clauses; a clause is quoted with the ADR's file:line, and the code that implements it today with the worktree's file:line, both at 050fa567e
---

# The ADRs against D1

## Summary

**26 stand, 20 are amended, 4 are superseded.** The ten the ticket expected to move all move;
fourteen more move that it did not name, most by one clause.

- **Superseded (4):** 002 `patrol-tick-reads-the-plan`, 027 `the-task-table-is-the-unit-register`,
  032 `the-task-row-is-the-trees-record`, 035 `the-budget-is-a-measurement-the-plan-carries`.
- **Amended (20):** 004, 007, 009, 010, 015, 017, 019, 021, 022, 029, 031, 033, 036, 037, 041, 043,
  045, 046, 049, 050.
- **Stand (26):** 001, 003, 005, 006, 008, 011, 012, 013, 014, 016, 018, 020, 023, 024, 025, 026,
  028, 030, 034, 038, 039, 040, 042, 044, 047, 048.

**D1 as read here.** Five clauses (spike §8, Option 2, and "The decision"): (a) every act appends
one line to an append-only run log, `record/<wave>/run.log`; (b) one fold derives every fact —
current step, matrix cells, readiness, approvals, proofs, the dispatch ledger; (c) the plan holds
only what a person authors (frontmatter, Goal, Design, Eval design, the Tasks prose), and `## SDLC
State`, matrix cells and the ledger are renderings; (d) hooks are thin callers of the fold (nine
registered scripts; the governing-skill hook checks authored frontmatter only; `stop-guard` folds into
`stop-orders`; `ruling-push` goes); (e) a verb exists only if a run needs its act (appenders,
authoring doors, renderers; every re-render, field, sync and settle verb goes). Two things D1 leaves
where they are: the session roster (`roster-<sid>.state`) stays its own record and the dispatch
ledger becomes a view of it (§3), and bash 3.2 stays (§8, "bash 3.2" row).

**The test applied to each ADR.** A clause of the *Decision* section moves when it names the plan
file (or a machine-written plan line), a second machine-written store, a reconciling verb, or a hook
arm that D1 removes, as the home or the reader of a run fact. *Amended* means the decision's
principle survives and one or more such clauses are re-homed; *superseded* means the decision's
subject is the plan-as-register itself and nothing of the mechanism survives the fold. Context,
Consequences and Rejected sections were read but do not decide the verdict. Facts D1 does not touch
(session identity, the roster, walls as predicates, render outputs, test framework, archive roots,
refusal shape, review rigor, permission grants) stand even when their ADR's mechanism parses the
plan today — that is implementation drift the fold fixes, not a contradicted decision.

**Two things found on the way.**

1. *ADR-001 is violated by nine of the eleven registered hooks, not seven.* At 050fa567e only
   `hooks/bash-walls.sh:197` calls `loader_fail_closed`; `dispatch-preflight.sh:212`,
   `canonical-sdlc-governing-skill.sh:280`, `stop.sh:147`, `agent-context-guard.sh:205`,
   `stop-guard.sh:263`, `permission-answer.sh:155`, `engage.sh:225`, `execution-recorder.sh:296`
   and `session-start.sh:165` call `loader_fail_open`, which prints "hook stepping aside" and
   `exit 0` (`hooks/dispatch-preflight.sh:174-177`). Six of the seven hooks that can block fail
   open. The five command-line verbs beside the hooks (`session-poker.sh:286`, `stop-orders.sh:292`,
   `stop-check.sh:277`, `session-sweeper.sh:271`, `preflight-probe.sh:324`) fail open too, which
   ADR-001 does not govern (it binds walls). The ADR stands; the code does not meet it.
2. *ADR-035 is already dead in code.* `hooks/canonical-sdlc-governing-skill.sh:1304-1310` says the
   `parallel-budget:` write-refusal was removed at wave-28 T9 under ADR-046 D15; D1 only confirms
   the burial. ADR-006's heading reads "ADR-001" (`adr-006-one-interpreter.md:21`); the real
   ADR-001 is `hooks-share-libraries-fail-closed`.

## The fifty

| # | title | decision in one sentence | verdict | clause D1 contradicts → what replaces it |
|---|---|---|---|---|
| 001 | hooks share libraries, fail closed | Shared hook logic lives in `payload/scripts/lib/`; a hook that cannot load it refuses. | stands | — (D1 folds the 15 pasted loaders into one sourced file; nine registered hooks fail open today, see Summary) |
| 002 | the Patrol tick reads the plan | The tick reads the newest `## SDLC State` plan once to learn `delivered`, and DISARMs only then. | **superseded** | "reads the run's state from the newest `*.md` … that carries an unfenced `## SDLC State`" and "`delivered` iff that plan says `current: 9`" → delivered is a fold query over the bound run's log; the fail-closed DISARM rule survives as the fold's answer |
| 003 | engagement is the single switch | A hook acts only for a session that invoked canonical-sdlc, keyed by `engaged-<sid>.state`. | stands | — (a session fact in tmp; "the plan decides WHAT" becomes "the bound run's log decides what") |
| 004 | run identity follows the session | The binding is the `plan=` line of the engagement marker, written by acts, never a scan. | amended | "The first Write of a new plan carrying `## SDLC State` binds the session" and `bound-closed` read off the plan → bind on the first write of a plan carrying `state:`/version 15; open/closed is the fold's |
| 005 | one owner per liveness truth | Every liveness fact has one owner read at the moment of use; the roster records contracts, not life. | stands | — (D0 is the principle D1 generalises; D1′ was reversed by ADR-025) |
| 006 | one interpreter | The suite runs a script under the interpreter its shebang names; bash 3.2 is the floor. | stands | — (D1: "bash 3.2 stays"; heading mislabelled ADR-001) |
| 007 | the budget is a ceiling | `parallel-budget:` in the header is the only number a wall refuses on; the rung is read at use and never enforced. | amended | "derived once, at Step 0, from this machine's own resources probe and recorded verbatim" into the frontmatter → a person's cap stays authored frontmatter; a probe's measurement is a record line or nothing (ADR-046 d6 already: not obeyed) |
| 008 | the framework owns what more than one suite needs | Generic helpers live in `tests/lib/`; the runner refuses a suite that shadows them. | stands | — |
| 009 | every consumer reads the source directly | Truth is code shared by sourcing, never parsed data, never a render, never a hand list kept in sync by a test. | amended | "Truth is code, shared by sourcing — never parsed data" → the run's truth is data (the log) read by one fold; "reads the source directly" means "calls the fold", and the one door is the lint "no reader but the fold" |
| 010 | run state defines the working set | A run's `.bionic/` artifacts move to the archive as one unit when the run closes; location encodes state. | amended | "Location encodes state … Closed → the artifacts live in the archive" judged by a plan read (`run_open` over `current:`) → closed is a fold query; the run log is a run-scoped artifact whose home at close ADR-017 fixes (record never moves) |
| 011 | one root directory per adapter | Each adapter is one root-level directory; the shared core sits at the repository root. | stands | — |
| 012 | the skill file is a render output | `SKILL.md` is rendered whole from a template; shared passages are blocks. | stands | — |
| 013 | the launcher governs the seat and refuses by stub | A launcher on omnigent's seam attaches the walls; on failure it returns a refusal program, never raises. | stands | — |
| 014 | two repair scopes, two surfaces | Setup owns machine scope; `/bionic:sweep` owns project scope over `session-poker.sh sweep`. | stands | — (`sweep` is an act a run needs) |
| 015 | one kind of knowledge per step | Steps 1–3 each write one artifact; the plan holds sequencing, the dispatch ledger and the matrix; `approved` binds as `approved-by:`. | amended | "Step 3 → plan: sequencing, the dispatch ledger, and the matrix derived from the spec's Eval design"; "`approved-by:` which the evidence gate and dispatch wall read" → the plan holds the Tasks prose; the ledger is a view of the roster, the matrix a rendering, the approval an `approve` event the fold reports |
| 016 | a refusal is an object | Every wall builds `{verb, fact, fix, detail}` and calls one renderer. | stands | — |
| 017 | roots and the archive layout | One roots library; a closed run's specs/plans/adrs trio moves to `~/bionic-archive/<project>/.bionic/`; `record/` never moves. | amended | "`archive_run` asks `run_open` of every `*.plan.md`" → asks the fold; the plan's `state:` pointer is docs-root-relative so it survives the move while `record/<wave>/run.log` stays |
| 018 | repair is not installation | A plugin whose files are on disk and whose registry row is gone gets the row restored, nothing installed. | stands | — |
| 019 | operator moves are levers | An operator move is a command whose inline shell writes state before the model's turn; the prompt is the body. | amended | "`payload/scripts/lib/units.sh` (the shared plan/task-table reader all three read)" and the open-fork count "over the spec and plan's own … stamps" → the lever shape stands; its reader is the fold; `handoff` is an appender (D1's verb list) |
| 020 | walls become doers; the roster row is the dispatch | A wall that can look, looks; the roster row is the dispatch's whole record. | stands | — (the skeleton "read facts → decide → one refusal" is D1's thin caller) |
| 021 | one unit vocabulary | The task is the atomic unit; the plan's one `## Tasks` table is the whole-wave unit set; nothing is derived at read time. | amended | "The tick, the task list and the reports read this table and nothing else. Nothing is derived at read time." → authored columns (id, kind, deps, serves, description) stay the unit set; status, step, worktree, agent are fold-derived; the Step-3 table wall leaves the governing-skill hook for the authoring doors |
| 022 | the loader is a doer | When `current:` moves to N the plan-write hook returns step N's owner skill as context and never refuses. | amended | "When the bound plan's `current:` moves to N, the plan-write hook lets the write through and returns…" → the step moves by a `step` event; the loader fires on the fold's current step (prompt-submit arm), not on a plan write |
| 023 | commands compose, never splice | No command file carries user text in a shell line; the model composes the verb call. | stands | — |
| 024 | walls read their input | A wall's precondition is state the system writes, read from the hook's own input, never a model act. | stands | — (D1 is this rule made general) |
| 025 | the roster is the identity register | A dispatched agent's identity is a roster fact; names are generated; no wall asks who is alive. | stands | — (the roster stays; the ledger becomes its view) |
| 026 | one memory per project | A spawned worktree carries `.bionic` as a link to the main checkout's. | stands | — |
| 027 | the task table is the unit register | Each `## Tasks` row gains a `worktree` cell the dispatcher writes; the gate judges a tree's commit at its row's step. | **superseded** | "Each row gains a `worktree` cell, written by the dispatcher at the moment it creates the tree" → the dispatch/spawn event names tree and task; the fold answers "whose tree, which step"; nothing writes a plan cell |
| 028 | walls assert only what they observe | A wall refuses only on an observation it made at the act, from data it can reach. | stands | — |
| 029 | a brief declares what it runs | `Re-executes:` is a brief label lifted like `Suites:`; the roster row records it; the budget arm holds it. | amended | "lifted from the brief text exactly as `Suites:` is" → lifted from the brief file the prompt names (D1 hook row), not the prompt's prose; grammar and roster field stand |
| 030 | a refusal prints what it knows | The `exit2` channel carries the detail, bounded at twelve lines. | stands | — |
| 031 | a commit has one of two subjects | The gate decides task-or-run from the directory and the `## Tasks` row before any arm; arms are task arms or run arms. | amended | "the `## Tasks` row that names that tree"; task/run arms over "the Step-4 block shape; the matrix `fails-when:`; the floor block, the walk artifact, the auditor cell" → the row-to-tree binding is the dispatch event; every arm asks the fold "is this subject's evidence present at this head"; the jurisdiction amendment (common dir) stands |
| 032 | the task row is the tree's record | The row's `worktree` and `base` cells declare identity and origin; membership is by row. | **superseded** | "The edit that flips a row to `active` names the tree's basename in the `worktree` cell"; "A tree is the run's if and only if a row names it" → identity, origin and membership are fields of the dispatch/spawn event; close-out's census is a fold query |
| 033 | done is the word, readiness is the unit's | `done` is the terminal word at every scale; one readiness function serves tick and wall; a row's tree is judged by its row at task scale. | amended | decisions 1 and 3 already deleted with the task-scale table (ADR-050 d3); decision 2's "reads whichever table shape the plan carries" → the one readiness function is the fold's, over authored deps and landing events |
| 034 | the roster is the occupancy, the ack is the close | Every "is this name closed" reader reads the sweeper's ack; occupancy is every unacked roster row. | stands | — (already: "the plan's `active` column is no input to the gap") |
| 035 | the budget is a measurement the plan carries | A plan write without `parallel-budget: writers=N` is refused by the governing-skill hook. | **superseded** | "A `*.plan.md` write without `parallel-budget:` … is refused by the governing-skill hook" → the width is the gate's (ADR-046); the arm was removed at wave-28 T9; D1's governing-skill checks authored frontmatter only |
| 036 | readiness is the prerequisite graph, the fill is measured | Ready = pending with every prerequisite landed; the wall computes the turn's facts; every turn end appends a line to `fill-ledger.log`. | amended | "the stop wall computes the ready set … itself" and "appends one line to `record/<plan slug>/fill-ledger.log`" → the wall asks the fold; the turn-end line is a `tick`/`fill` line of the one run log (or an event file the fold reads); the graph rule and the measure stand |
| 037 | a wait is declared once; launched is what the roster says | No model-resolved plugin root; `ext:<slug>` in `deps` holds a row; an `active` row needs no `- T<n>:` line. | amended | "The line is required at `done`/`landed`, where it carries evidence a human authors. One reader in `units.sh` produces every ledger finding" → the `- T<n>: landed` line is the landing event (`ev=published`), the `units.sh` finding reader goes; decisions 1 and 2 stand |
| 038 | two views of one scaffold | The brief scaffold renders an author's template and a reader's view from one label set. | stands | — |
| 039 | a successor row is the agent's latest identified self | `amend`/`extend` copy status and ids from the name's latest identified row in the cycle. | stands | — (roster invariant) |
| 040 | four channels and no fifth | Standing knowledge arrives by four reviewed channels; auto-memory is not one. | stands | — (the run log lives in channel four; `continuation.md` becomes a rendering, which is a mechanism not a channel) |
| 041 | an answer stands until its facts change | A stand-down answer is a hold on the roster row; a fill answer stands against the ready set it answered; MET needs the agent's word. | amended | "hands the stop wall the latest declined ready set and `current:` from the fill ledger" and "a decline is still read only from the main thread's own reply text" → a decline is an appended event, the standing decline a fold fact; the hold on the roster row and "done means the agent said so" stand |
| 042 | a run's authority is a chain of grants | Authority flows human → run → agent; a grant is recorded by the act that creates it; answers are pure functions. | stands | — (`permission-answer.sh` is one of D1's nine) |
| 043 | work is scheduled by what it reads | Ready when what a unit reads exists; a proof names the head it read; capacity is booked at use; shared files reconcile on landing. | amended | "A proof — a suite run, a review, a landing — records the head it read" as `proved:` lines under `## SDLC State`, and the edge computation over the plan → a `prove` event keyed by head, the edges and readiness a fold derivation over authored `reads`/`Files` cells and landing events |
| 044 | rigor is the number of independent minds | Four questions at every rigor; every assurance is a named party's fact about one code state; a gate enforces accountability. | stands | — (d2, d3 superseded by ADR-049; the record the gate reads is a review record, which the fold reads) |
| 045 | a landing is a sealed copy | A landing merges onto everything accepted in a tool-owned tree, is proved there and published by fast-forward under one lock. | amended | "Publishing happens under one lock … with the plan's row written inside it" and the amendment's "`row-landed` writes the row's status, its step line and its ledger cell" → the landing line is the fact (spike §3: `row-landed`'s three copies go); decisions 1–5 stand and the line is D1's model |
| 046 | one gate decides on the present and its experience | One share per machine; the gate admits on the present reading plus its own promises; requests are held numbers. | amended | "A plan records the value it ran under as a fact" (d1) → a record line, if written at all (no writer found at 050fa567e); every other decision stands |
| 047 | severity and reach decide what is fixed | Severity is harm on four levels, reach a second field, priority one table; only the user moves a finding. | stands | — (`moved:` is a door D1 keeps; `finding-stated` and the registration-time `deferred:` become fold reads) |
| 048 | every decision takes one shape | Goal, Options, Recommendation, Significance; advice, not a wall. | stands | — |
| 049 | review is a decision | A mind reads once on the settled whole; rigor is `single`/`double`; debt is a ledger burned when touched. | amended | "`record/<run>/debt.md` holds one line per item with a touch count … the dispatch wall prints the item and counts the touch" → a touch and a burn are appended events, `debt.md` a rendering, the wall a thin caller; decisions 1, 2, 3, 5 stand |
| 050 | the floor is a record of runs | A release is proved by one whole green run plus each later commit's named suites; regression is a Step-0 setting; one ledger shape; no pins. | amended | "The gate reads this from the stamps and roster rows `booked.sh` already writes" and `regression-runs --write` putting the count in the plan header → proofs are `prove` events keyed by head; "is the head proved" is the fold's; `regression-runs:` is computed on read (spike §3); d2–d5 stand |

## The moved ADRs

Each section quotes the contradicted clause with its line in the ADR file, names the code that
carries it at 050fa567e, and says what D1 puts in its place.

### 002 — the Patrol tick reads the plan · superseded

- Clause: "The tick reads the run's state from the newest `*.md` at depth ≤ 2 under
  `<docs-root>/{plans,incidents}` that carries an unfenced `## SDLC State`"
  (`adr-002-patrol-tick-reads-the-plan.md:43-45`); "`delivered` iff that plan says `current: 9`,
  its Step-9 line carries `delivered:`" (`:48-49`); "**This is the tick's only plan read.**" (`:58`).
- Code: `hooks/poker/tick.sh:2620-2633` (DISARM when `OPEN_ROSTER -eq 0` and `RUN_STATE = delivered`,
  `run_state` answered "off a plan", comment at `:261`). The newest-plan scan itself already went
  with ADR-004's binding.
- D1: the plan holds no `## SDLC State`; delivered is a derived fact of the bound run's log (a
  `close`/`deliver` event). The tick asks the fold. What survives is the fail direction, "doubt means
  keep watching, never stand down" (`:54-55`), which the fold answers the same way when the log has no
  such line.

### 004 — run identity follows the session · amended

- Clause: "The first Write of a new plan carrying `## SDLC State` binds the session to it"
  (`adr-004-session-bound-run-identity.md:52-53`); "A session bound to a plan that has closed … is
  `bound-closed`" (`:62-64`), closed being read from the plan.
- Code: `payload/scripts/lib/run.sh:524 run_open`, `:655 open_runs`, `:940 session_run`;
  `hooks/canonical-sdlc-governing-skill.sh:1551` (the `## SDLC State` read on the bind-on-write arm).
- D1: identity declared by an act stands whole (D0). The bind-on-write trigger keys on what a
  version-15 plan carries (`state: record/<wave>/run.log`, `canonical_sdlc_version: 15`), and
  open/closed is the fold's verdict over that log. `open_runs` listing by `current:` becomes a fold
  over each candidate's log.

### 007 — the budget is a ceiling · amended

- Clause: `parallel-budget:` "is derived once, at Step 0, from this machine's own resources probe and
  recorded verbatim; nothing re-derives it downstream" (`adr-007-the-budget-is-a-ceiling.md:33-37`),
  and decision 1, the header line "is the only number a wall may refuse on" (`:66-74`).
- Code: `hooks/dispatch-preflight.sh:1350-1357` (reads `writers=` from the leading frontmatter block,
  obeyed only when `source=user|override` since ADR-046).
- D1: a measurement the machine wrote is not what a person authors. A person's cap stays an authored
  frontmatter key and still caps (ADR-046 d6); the probe's value is a record line or is not stored.
  The ceiling/rung distinction and "the wall enforces the ceiling and never the rung" stand.

### 009 — every consumer reads the source directly · amended

- Clause: "Truth is code, shared by sourcing — never parsed data, never a second script's render,
  never a hand list kept in agreement by a test" (`adr-009-every-consumer-reads-the-source-directly.md:49-51`).
- Code: the two instances stand as built — `payload/scripts/lib/checks.sh` sourced by `doctor.sh:233`
  and `setup.sh`; `tests/run.sh:9-12` (the roster is the sorted glob, read at run time).
- D1: the rule's spirit — one source, no copies, agreement by reading the same thing rather than by
  a test — is D1's own. Its letter, "never parsed data", is narrowed to machine checks and the test
  roster. A run's facts are data in the log; "reads the source directly" means every consumer calls
  the fold, and the one door is a lint refusing any other reader of `$PLAN` or the log (spike §8,
  "its one parser"). The two rejected alternatives "truth as parsed data" and "truth as one script's
  render" (`:114-119`) are, for run facts, what D1 chose: one parser (the fold) over one data file.

### 010 — run state defines the working set · amended

- Clause: "**A run's `.bionic/` artifacts are one unit that follows the run's own lifecycle.**
  Location encodes state: Open → … Closed → the archive" (`adr-010-run-state-defines-the-working-set.md:41-47`),
  the state read from the plan; "What moves. … `record/` entries named for it" (`:55-57`).
- Code: `payload/scripts/lib/archive.sh:143 archive_run`, which asks `run_open` (`lib/run.sh:524`)
  of the plan files.
- D1: closed is the fold's answer over `record/<wave>/run.log`, not a `current:` read. The record
  directory now holds the state itself, so "what moves" is already corrected by ADR-017 (`record/`
  never moves); the plan's `state:` pointer must resolve after the plan moves (docs-root-relative).
  The archive-as-unit rule and "citations never rewritten" stand.

### 015 — one kind of knowledge per step · amended

- Clause: "**Step 3 → `wave-NN-<slug>.plan.md`.** Sequencing, the dispatch ledger, and the matrix
  derived from the spec's Eval design. … the literal word `approved` binds it, recorded as
  `approved-by:` which the evidence gate and dispatch wall read"
  (`adr-015-one-kind-of-knowledge-per-step.md:52-54`); the three walls at `:59-62`.
- Code: `approved-by` readers at 050fa567e: `payload/scripts/lib/walls.sh`, `fill.sh`, `units.sh`,
  `hooks/dispatch-preflight.sh`, `hooks/canonical-sdlc-governing-skill.sh:1421`,
  `hooks/poker/{proof,tick,plan,sitrep}.sh`.
- D1: the three-artifact split, `## Goal` first, and "Eval design happens where the seam is decided"
  stand. The plan holds the Tasks prose; the dispatch ledger is a view of the roster; the matrix is a
  rendering of Eval design rows plus landing, walk, auditor and waiver events (spike §3); the Step-3
  approval is an `approve` event the fold reports, which the commit and dispatch walls ask for.

### 017 — roots and the archive layout · amended

- Clause: "`archive_run <run-dir>` asks `run_open` of every `*.plan.md` directly under
  `plans/<slug>/`. Any open sibling and nothing moves" (`adr-017-roots-and-the-archive-layout.md:50-54`).
- Code: `payload/scripts/lib/archive.sh:143`.
- D1: open is the fold's. Everything else stands: one roots library, the trio moves together,
  `record/` never moves (`:45-47`) — which is exactly where D1 puts the log, so the archived plan's
  `state:` pointer resolves against the project's docs root, not the archive's.

### 019 — operator moves are levers · amended

- Clause: the component as landed names "`payload/scripts/lib/units.sh` (the shared plan/task-table
  reader all three read)" (`adr-019-operator-moves-are-levers.md:45-48`) and the Step-3 card's
  open-fork count as "a mechanical read of `units.sh open-forks` over the spec and plan's own …
  stamps" (`:68-71`).
- Code: `operator.sh` no longer exists; `handoff` is a `session-poker.sh` verb (`:1438`, `:3573`) over
  `payload/scripts/lib/handoff.sh`; `units.sh` is on D1's deletion list ("ledger and validator 1,800").
- D1: the lever-plus-prompt-body shape stands and `handoff` is one of D1's appenders. The reader a
  lever renders from is the fold; the autopilot session file stays a session fact.

### 021 — one unit vocabulary · amended

- Clause: "The plan's `## Tasks` table is the single whole-wave unit set … Nothing is derived at read
  time. The tick, the task list and the reports read this table and nothing else"
  (`adr-021-one-unit-vocabulary.md:38-44`), and "The Step-3 wall refuses a missing structural row,
  `all`, an over-cap row…" (`:40-41`).
- Code: `payload/scripts/lib/units.sh:403 units_rows` (79 callers per spike §1), `:515 units_ready`,
  `:2055 units_validate`; the Step-3 wall in `hooks/canonical-sdlc-governing-skill.sh:1373-1389`.
- D1: the task as atomic unit and "slice" retired stand. The table's authored columns (id, kind,
  deps, serves, description) remain the unit set a person writes; status, step, worktree and agent are
  derived by the fold from dispatch and landing events, so "nothing is derived at read time" inverts
  for those cells. The structural-table wall leaves the governing-skill hook (D1: it checks authored
  frontmatter only) and lives, if kept, in the authoring doors `task-add`/`amend` — prevent at
  generation.

### 022 — the loader is a doer · amended

- Clause: "When the bound plan's `current:` moves to N, the plan-write hook lets the write through and
  returns step N's owner skill(s) as additional context … One entry point, `loader_sync`, is called
  from the existing PostToolUse Write, PreToolUse Edit and UserPromptSubmit registrations"
  (`adr-022-the-loader-is-a-doer.md:43-52`).
- Code: no file matching `rout*`/`skill*` exists under `payload/scripts/lib/` at 050fa567e and no
  `loader_sync` definition is found there (`/usr/bin/grep -rn '^loader_sync()' payload/scripts/lib`
  empty); the Write/Edit registrations are the governing-skill hook's (`hooks/hooks.json`).
- D1: doer-not-wall stands. `current:` is no longer written to the plan; the step moves by a `step`
  event, so the trigger is the fold's current step compared with the delivery record, checked at the
  prompt-submit arm (already the ADR's catch-all) or in the step verb itself.

### 027 — the task table is the unit register · superseded

- Clause: "Each row gains a `worktree` cell, written by the dispatcher at the moment it creates the
  tree … The gate reads the worktree's name … finds the owning row, and judges the commit at that
  row's step" (`adr-027-the-task-table-is-the-unit-register.md:60-66`); the ratified qualification
  "The `## Tasks` table is the register of which unit a tree belongs to and at which step" (`:32`).
- Code: `payload/scripts/lib/walls.sh:3147-3152` ("THE REGISTER IS THE `## Tasks` TABLE (ADR-027). The
  dispatcher writes the tree it created into the row's `worktree` cell"), `_eg_row_for_worktree`
  at `:3305-3310`.
- D1: a machine-written plan cell is the shape D1 removes (spike §7, rank 1: 60 matrix tier rows and
  the "no verb writes this" hand edits). The dispatch (or spawn) event carries task id, tree and base;
  the fold answers "whose tree, at which step" for the gate, the fill and close-out. The question the
  ADR asked is kept; its register is not.

### 029 — a brief declares what it runs · amended

- Clause: "`Re-executes:` is a canonical brief label lifted from the brief text exactly as `Suites:`
  is (a line-start label, one span to the next blank line)" (`adr-029-a-brief-declares-what-it-runs.md:48-49`).
- Code: `payload/scripts/lib/brief.sh:129-276` (the awk lift over the prompt's prose, shared by
  dispatch, `amend`, `task-add`); `hooks/dispatch-preflight.sh` (3,490 lines, spike §4).
- D1: "`dispatch-preflight` reads the brief from a file the prompt names and the roster, not the
  prompt's prose" (spike §8, hooks row). The label, its author-marked runs, the roster field and the
  budget arm stand; the source the lift reads is a file.

### 031 — a commit has one of two subjects · amended

- Clause: "The gate resolves which from the directory the commit lands in and the `## Tasks` row that
  names that tree" (`adr-031-a-commit-has-one-of-two-subjects.md:43-45`); "Every arm is a task arm
  (the Step-4 block shape; the matrix `fails-when:` presence) or a run arm (the floor block, the walk
  artifact, the auditor cell, the ADR, the merge, the ship)" (`:46-47`); "The gate reads one more
  cell of a table it already parses" (`:57`).
- Code: `payload/scripts/lib/walls.sh:1949 _eg_body`, the task-arms notes at `:3516` and `:3565`.
- D1: the two-subject rule and the jurisdiction amendment (git common dir, `:103-132`) stand. The
  row-to-tree binding comes from the dispatch event, and each arm becomes one fold query — "is this
  subject's Step-N evidence present at this head" — over `prove`, `land`, `approve` and `waive`
  events rather than over plan blocks and matrix cells (spike §8: `bash-walls` "asks … of the fold").

### 032 — the task row is the tree's record · superseded

- Clause: "The edit that flips a row to `active` names the tree's basename in the `worktree` cell"
  (`adr-032-the-task-row-is-the-trees-record.md:42-43`); "The row carries an optional `base` cell"
  (`:46-47`); "A tree is the run's if and only if a row names it" (`:50-53`).
- Code: `payload/scripts/lib/walls.sh:3147-3152`, `:3305-3310`; close-out's census over the register.
- D1: identity, origin and membership are three fields of one appended dispatch/spawn event
  (`spawn-worktree.sh` already prints path, branch and base at creation, `:38`). The gate, the
  landing gate and close-out become three callers of one fold, which is the ADR's own goal ("three
  readers of one record", `:57`) with the record moved out of the plan. "The run's own checkout is
  never a row's tree" stands as a fold rule.

### 033 — done is the word, readiness is the unit's · amended

- Clause: decision 2, "One readiness function, extracted from the tick into a library, reads
  whichever table shape the plan carries and is called by the tick and by the stop library's fill
  duty" (`adr-033-done-is-the-word-readiness-is-the-units.md:49-56`). Decisions 1 and 3 (`:42-48`,
  `:57-62`) were already deleted with the task-scale table and `current: T<n>` by ADR-050 d3.
- Code: `payload/scripts/lib/fill.sh:233 fill_ledger_live`, `:312 fill_ready_set` (plan readers).
- D1: one reader for the tick and the wall stands — that reader is the fold's readiness, over
  authored deps and landing events. "The ledger is live" becomes "the log carries an `approve` for
  Step 3".

### 035 — the budget is a measurement the plan carries · superseded

- Clause: "A `*.plan.md` write without `parallel-budget:` carrying `writers=<digits>` is refused by
  the governing-skill hook" (`adr-035-the-budget-is-a-measurement-the-plan-carries.md:45-47`); "Every
  downstream reader's absent-key branch is a named backstop" (`:48-49`).
- Code: `hooks/canonical-sdlc-governing-skill.sh:1304-1310` — the arm was removed at wave-28 T9 (ADR-046
  D15): "The width is the gate's now, so no plan needs the line … this hook neither requires nor reads
  it."
- D1: a measurement is not authored, so it has no place in the plan; the governing-skill hook checks
  authored frontmatter only. ADR-046 had already taken the width; D1 removes the last reason for the
  line.

### 036 — readiness is the prerequisite graph, the fill is measured · amended

- Clause: decision 3, "At turn end the stop wall computes the ready set and the pressure state and
  counts the agents launched; it reads only the model's own decline from the transcript"
  (`adr-036-readiness-is-the-prerequisite-graph-and-the-fill-is-measured.md:52-54`); decision 4,
  "Every turn end in an engaged run appends one line to `<docs-root>/record/<plan slug>/fill-ledger.log`"
  (`:55-58`).
- Code: `payload/scripts/lib/patrol.sh:975-990` (the ledger path), `hooks/stop.sh:175`,
  `payload/scripts/lib/stop.sh:175` (`stop_fill_ledger`).
- D1: decisions 1, 2 (with Δ6b) and the measure stand; the graph is what the fold computes. The wall
  computes nothing itself — it asks the fold (a thin caller), and the turn-end line is a `tick`/`fill`
  line of the one run log (or an event file the fold reads; spike §8 names one log). The transcript
  read of the decline is re-homed by ADR-041 below.

### 037 — a wait is declared once; launched is what the roster says · amended

- Clause: decision 3, "The line is required at `done`/`landed`, where it carries evidence a human
  authors … One reader in `units.sh` produces every ledger finding (status outside the enum;
  evidence line missing at done; launch missing at active) and both the gate and the Patrol tick
  call it" (`adr-037-a-wait-is-declared-once-and-launched-is-what-the-roster-says.md:67-73`).
- Code: `payload/scripts/lib/units.sh:2449 units_findings`, `:2483 _units_ledger`.
- D1: "launched is what the roster says" stands and generalises: landed is what the landing record
  says (`- T<n>: landed` is already `ev=published`, spike §8 version-15 row). The `- T<n>:` evidence
  line and the three ledger findings go with the plan's machine lines; the evidence a human authors at
  done rides the `land`/`prove` event. Decisions 1 (no model-resolved root) and 2 (`ext:` in the
  authored `deps` cell) stand.

### 041 — an answer stands until its facts change · amended

- Clause: decision 2, "The collector hands the stop wall the latest declined ready set and `current:`
  from the fill ledger" (`adr-041-an-answer-stands-until-its-facts-change.md:53-55`); decision 4, "a
  decline is still read only from the main thread's own reply text" (`:58-60`).
- Code: `payload/scripts/lib/stop.sh:1797`, `:2018`, `:2084` (the `standdown-declined:` scan over the
  transcript's own text).
- D1: the principle — a fact written once stands until its inputs change — is D1 in miniature, and
  the hold on the roster row and "done means the agent said so" stand. A decline is an act, so it is
  an appended event (a `decline` appender beside `hold`), and the standing decline is a fold fact over
  the log; nothing reads the transcript for it (ADR-024's own rule).

### 043 — work is scheduled by what it reads · amended

- Clause: decision 2, "A proof — a suite run, a review, a landing — records the head it read. What is
  unproved is the difference since that head" (`adr-043-work-is-scheduled-by-what-it-reads.md:49-51`),
  recorded today as `proved:` lines under `## SDLC State`; decision 1's edge computation over the
  table (`:45-48`).
- Code: `payload/scripts/lib/proof.sh:1420 proof_awk` (the `proved:` grammar, 26 mentions in the file,
  "8 private parsers beside it" per spike §1); `units.sh:11-16` (the `reads` cell).
- D1: both rules stand in substance; both records move. A proof is a `prove` event keyed by the head
  it read (ADR-057 "a proof cites a run the machine recorded" and ADR-061 "a proof is keyed by what it
  read", outside this ticket's range, already name that shape), and "is this head proved" is a fold query. The edges and
  the ready set are the fold's derivation over the authored `reads`/`Files` cells and landing events.
  Decisions 3 (the gate store) and 4 (reconcile on landing) stand.

### 045 — a landing is a sealed copy · amended

- Clause: decision 6, "Publishing happens under one lock, shared by the line and the hand landing,
  with the plan's row written inside it" (`adr-045-a-landing-is-a-sealed-copy-carried-by-its-maker.md:56-57`);
  the wave-28 amendment, "`row-landed` writes the row's status, its step line and its ledger cell in
  one transaction under the publish lock" (`:89-93`).
- Code: `hooks/poker/line.sh:51-53` ("one landing writer, `row-landed`, in the same transaction").
- D1: the landing line is the one record in the tree that already has D1's shape and never disagreed
  (spike, Answer); decisions 1–5 stand as the model for every other act. The plan row, the step line
  and the ledger cell are three copies of the landing event (spike §3, "`row-landed`'s three copies …
  the landing event is the fact"); the verb goes and the lock covers the branch and the log line only.
  D36's `floor:` and `floor-attestation:` keys are authored and stand.

### 046 — one gate decides on the present and its own experience · amended

- Clause: decision 1, "A plan records the value it ran under as a fact"
  (`adr-046-one-gate-decides-on-the-present-and-its-own-experience.md:42-43`).
- Code: no writer of such a line was found at 050fa567e (`/usr/bin/grep` for `share:` over
  `hooks/poker/plan.sh`, `payload/scripts/card.sh`, `hooks/session-poker.sh`, `payload/scripts/lib/run.sh`
  returns nothing), so the clause is unbuilt.
- D1: a value the machine ran under is a record line, not a plan line. Every other decision stands;
  the gate store is its own append-only record of asks, admissions and ends, which is already the
  shape.

### 049 — review is a decision · amended

- Clause: decision 4, "`record/<run>/debt.md` holds one line per item with a touch count. When a
  later brief's `Files:` covers a site of an unburned item, the dispatch wall prints the item and
  counts the touch" (`adr-049-review-is-a-decision.md:46`).
- Code: `payload/scripts/lib/debt.sh:6` (the line shape with `touches=<N>`), `:22` ("the dispatch
  wall's touch counter"); `hooks/dispatch-preflight.sh:1074`.
- D1: a touch and a burn are acts, so each is an appended line; the touch count is a fold over them
  and `debt.md` a rendering the release card reads. The dispatch wall prints what the fold says
  rather than counting in-file (a thin caller). Decisions 1, 2, 3 and 5 stand.

### 050 — the floor is a record of runs · amended

- Clause: decision 1, "The gate reads this from the stamps and roster rows `booked.sh` already writes"
  (`adr-050-the-floor-is-a-record-of-runs-and-the-regression-is-a-setting.md:36`); decision 2's
  `regression:` setting is authored at Step 0 and stands (`:37`).
- Code: `hooks/session-poker.sh:43`, `:561`, `:1400` (`regression-runs --write` "puts the count in the
  bound plan's `regression-runs:` header"); the stamps `booked.sh` writes.
- D1: "the floor is a record of what ran, never a prediction" is D1's own stance. The record it is
  read from is the run log — a suite run is a `prove` event keyed by head and suite — and the
  `regression-runs:` plan line is computed on read (spike §3: "`regression-runs --write` … computed on
  read; nothing to police once the plan holds no machine facts the gate judges"). Decisions 3 (one
  ledger shape), 4 (no pins; D1 keeps the replay bed) and 5 (doctrine net zero) stand.

## What the standing ADRs still ask of D1

Three standing decisions set constraints the kernel must honour while it deletes readers:

- **ADR-001** — the one sourced loader D1 promises must fail closed in every hook that can block;
  today six of seven do not (Summary).
- **ADR-024 and ADR-028** — the fold is read from the hook's own input (the bound run's log path),
  and every refusal names the log line it was made on; a fold fact missing because no verb appended it
  is a bug in the appender, not a refusal the model clears.
- **ADR-017** — the log lives under `record/`, which never moves; the plan that moves to the archive
  must still point at it.
