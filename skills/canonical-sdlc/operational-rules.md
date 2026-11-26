---
name: canonical-sdlc-operational-rules
description: Canonical-sdlc operational rules — artifact shape, the Tasks table, design authoring, close-out, debts and the rulings. Copied beside SKILL.md, read on demand — nothing loads it.
updated: 2026-10-10
---

# canonical-sdlc operational rules

The detail SKILL.md and `steps/*.md` compress.

## Artifact paths and frontmatter

- **Canonical-sdlc artifacts live in `.bionic/docs/{specs,plans,adrs,incidents}/epic-NN-<slug>/`** (the default docs-root): `epic.plan.md`, `wave-NN-<slug>.plan.md` and `continuation.md` at the epic-dir root, with parallel specs/ and adrs/ trees; zero-padded epic numbers, kebab-case slugs. The evidence gate descends 2 levels to find nested plans. Both dirs are gitignored.

- **Canonical-sdlc artifacts require governing-skill frontmatter.** Every `*.plan.md`, `*.spec.md`, `adr-*.md`, `continuation*.md` under `.bionic/docs/{specs,plans,adrs}/` must open with:

  ```
  ---
  governing-skill: <skill-id>
  sdlc-step: N
  epic: epic-NN-<slug>
  wave: wave-NN-<slug>
  canonical_sdlc_version: 15
  intent: <intent>
  rigor: <rigor>
  scale: <scale>
  ---
  ```

  The `canonical-sdlc-governing-skill.sh` hook blocks a write missing `governing-skill:`; non-artifact files under those paths pass through.

### The `## Tasks` table

A plan's `## Tasks` table, at every scale, is the register the Step-4 dispatch works from: nine cells a row, all a person's; the write hook refuses any other cell. `session-poker.sh start <id>` records a written row's birth, renders its brief, makes its tree and prints the dispatch call whole.

```
| id | step | kind | task | deps | size | serves | Files | artifact |
```

- **`id`** — `T<n>`, matching `^T[0-9]+$`, the row's own key.
- **`step`** — the SDLC step this row executes at (4 for build/test rows; 5–9 for verify/review/document/integrate/close rows).
- **`kind`** — one of `build | test | verify | review | doc | integrate | close | prototype`.
- **`task`** — the row's task in one line; `complexity: standard | complex` rides in this cell for Step-4 rows.
- **`deps`** — task ids (`T1, T4`) or an external prerequisite `ext:<slug>`, never prose: `units.sh`'s validator splits the cell on `,`, and every token must resolve in the id set or match `ext:<slug>` (a letter or digit, then letters, digits, `.`, `_` or `-`). An id reads "wait for that task to land"; write one only where the row reads what that row writes. An `ext:` token holds the row out of the ready set, named on the tick's `HELD` line, until it is removed. A row also waits on its kind's default: build `approval:plan` · verify `approval:plan, head` · review `approval:plan, live:head` · doc `approval:plan, head` · integrate `proof:regression, proof:review, head`, and `approval:release` when the plan carries a release row · close the integrate row's merge.
- **`size`** — the row's expected duration in minutes.
- **`serves`** — the requirement id(s) this row discharges.
- **`Files`** — every path the row may create or edit (the dispatch budget's source). Two rows that write one file run side by side and reconcile on landing; an entry ending in `!` is unmergeable, and a second row that writes it waits for the first to land.
- **`artifact`** — the row's record: this cell, else the `Files` entry named `<row>.md` or `<row>-*`, else the first record entry.

**The row's section.** `## T<n> — <title>` holds what a person has to say about the row — research to read, rulings — and its `suites:` and `lands-on:` lines, each defaulting to `Files`' `*.test.sh` entries. Its agent, tree, base, state and landing are events: `reader.sh <plan> status <id>`.

**Approvals and proofs a row waits on** are events in `record/<wave>/run.log`, each appended by its verb, never by a hand edit:

| piece | shape |
|---|---|
| approval | `session-poker.sh approve <name> '<reply>'` on the user's reply, verbatim: one approval event, at the working head for a named one. `approve step0`, `step1`, `step2` and `plan` are Steps 0 to 3's, each once |
| proof | `session-poker.sh proof-add <kind> <evidence>`: one proof event, `kind=<regression\|point\|review\|task\|walk>`, `head=` and `evidence=<path under record/>`; the head is the evidence's own (a log's `head=` header, a review's `reviewed: a..b` end), never an operand; `proof-add check` is refused |
| review | `proof-add review <record> --question <q> --reader <name>` adds `question=`, `reader=`, `result=<pass\|flag\|fail>` and `scope=<piece\|whole>`; the reviewer's role is read from its roster row and must be dealt the question. The record's lines are `steps/6.md`'s |
| declared check | `release-check: <command>` in `.bionic/config.yaml`, run with `BIONIC_CHECK_BASE`, `BIONIC_CHECK_HEAD` and `BIONIC_CHECK_TREE`; exit 0 passes; its words split on white space, so a check needing quoting is a script. `session-poker.sh release-check` (main thread, clean tree, no operand) runs it from the last release to the working head, writes `record/<wave>/release-check-<head>.log` and a `kind=check` proof (`result=fail` on a non-zero exit). `land` runs it in the target checkout up to the task's head and refuses `why=release-check` when it fails, or `reason=check-dirtied` when it moved the target's HEAD or dirtied either tree; nothing is merged. `session-poker.sh check-from '<their words>' [<commit>]` records the person's typed word that the commit, the working head unless named, judges every landing and release check after it |
| declared regression | `regression-command:` (run by `regression-run`) in `.bionic/config.yaml`, its record `steps/5.md`'s; with neither, the regression is `tests/run.sh`'s whole run |
| landing | `ready` and the hand landing (`spawn-worktree.sh land <tree> --by-hand --reason '<why>'`) append one event per act to the run's log, never rewritten; a row's landing is the `commit=` of its last `published` event. An unwritable log refuses `why=proofs-unwritable` |
| declared debt | a brief's one `Lands-red: <name>.test.sh until <ext:slug\|approval:name>` with `Red-evidence: <path under record/>`, recorded by the dispatch wall alone (`amend` cannot add them). `land` accepts that one suite red, every other suite green, when the evidence holds `head: <40-hex>` naming the head landed, and appends an `admitted` event (its row, suite and token) to the run's log. It stays open until a regression or task proof shows the suite green after the red landing (and after the named approval, for `approval:`); `current 8`, close-out, the integrate row and, from Step 6, the commit gate refuse while it is open |
| debts | `## Debts` below |

**The regression, once** (`steps/5.md` holds the rule). `session-poker.sh regression-run` refuses it at `regression: no`, beside an open build row, at a head that already has a whole run, or at a head the full pass's state reads green by content. A red suite is a fix row's. A whole run at a later head where code landed is the normal path. A head whose landings since the pass moved no code reads green and needs none.

**`working-branch:`** in the plan's frontmatter names the wave's branch: the landing gate (`lib/stop.sh`) merge-bases a task tree against it, and the landing line (`spawn-worktree.sh ready`; lib/line.sh `line_tree_run` reads it as the branch a tree lands onto) merges a landed tree into it. A plan naming none lands nothing: `spawn-worktree.sh ready` refuses its trees (`REFUSED reason=no-working-branch plan=<plan>`) and merges nothing into any branch.

**Cell shapes.** A proof's `evidence=` names exactly one path under `record/`. The regression proof is the run's log (`steps/5.md`); `advisory-exceeded: <M>` beside it is recorded, never judged.

## Design section authoring (the Step-2 back-half)

SKILL.md carries the contract; this is how to author one that earns its keep.

### The view menu

A design is several *views* of one change, and a design goes wrong less by a wrong answer than by a view nobody looked at:

- **logical domain model** — the entities and relationships the change reasons about;
- **entity / data design** — the concrete shape of those entities: fields, types, identity;
- **persistence** — schema, mutability, transactions, migration;
- **application / component design** — modules, boundaries, control flow, who calls whom;
- **integration surfaces** — the contracts crossed: APIs, hooks, CLIs, file formats, events;
- **deployment / runtime architecture** — where it runs, in what process, under what lifecycle.

**The design names which views the change touches, and includes those.** A view excluded costs one clause — "no persistence: nothing is stored" — and that clause is the difference between a decision and an oversight. **Silent omission is the failure the menu exists to prevent**: a view in neither list is itself the finding. Padding with empty headings is its own failure: exclude the rest in a clause apiece.

### The form menu

`steps/2.md` names the five rungs; this is how the suggested default is derived. Cheapest first:

- **design paragraph** in the session plan — the default at `scale: task`: what it touches, what owns the concept, what breaks if the assumption is wrong.
- **`## Design` section** in the spec — the default at `scale: wave`, and the rung to beat: the design sits beside the requirements it answers.
- **standalone design doc** — when the design outlives its wave or several waves implement it; it is what a `design:` pointer resolves to.
- **structured models** — when topology is the hard part: the moment "who calls whom, in what order, across which process boundary" takes a paragraph, it wants a picture.
- **full Technical Design Document** — at momentous or cross-system scope, with readers who will never open the spec.

**Derivation produces a suggested default, never a selection.** Scale gives the starting rung —
task to paragraph, wave to `## Design` section — and three signals move it up: a design several
waves will implement (standalone doc), topology prose would flatten (add structured models), a
cross-system surface with its own readership (full Technical Design Document). One signal moves
it down: a wave whose design is one decision wide gets a short section, not a doc. Print the
result in the frame with the one-line reason it was derived; the user moves it up, moves it down,
or lets it stand.

**Nothing enforces the rung, deliberately.** The three-way wall accepts every rung, in place or by pointer, so form selection cannot fail a gate: it is guidance approved in conversation.

### The ownership table

The load-bearing row of the section, and the only part later steps consume mechanically: the `structure` checks `reuse` and `one-site` anchor on the owner column, and the `structure` reviewer reads the agreement-test column back. Shape:

```
| concept | owning module (SSoT) | reuses | rendering surfaces | agreement test |
|---|---|---|---|---|
| version pin value | none single: the literal `15` in the commit gate's version case (`payload/scripts/lib/walls.sh`, behind `hooks/bash-walls.sh`) and in the write hook's (`hooks/canonical-sdlc-governing-skill.sh`) | none fits: no file holds a version constant, each case reads the header's `canonical_sdlc_version` itself | the governing-skill hook · `plan_read_faults` in `payload/scripts/lib/plan-read.sh` | `tests/canonical-sdlc-evidence-gate.test.sh` §Section 2b holds the two gates to one answer on a plan at 13, 14 and 15; the literal in `plan_read_faults` is not in it |
| agreement-test duty + authoring rules | `agents-src/blocks/checks-structure.md` (`one-site`) | the render markers of `agents-src/render.sh` | payload/context/checks-structure.md · this section | `bash agents-src/render.sh --check` holds the rendered file to its block; this section is the unpinned one |
```

- **The `reuses` cell names the existing site the design reuses, or `none fits: <why>`.** Empty is a finding: the design never looked. A writer's `reuse:` report line answers the same question for each site the build added.
- **One row per concept rendered at more than one surface.** A concept in one place has nothing to disagree with; the table is a duplication ledger, not an inventory.
- **The owner is a place, not a layer or a role.** "the governing-skill hook" is an owner; "the backend" is not. With no file, function or named constant to name, the concept has no owner yet — write that down as the finding.
- **Rendering surfaces include prose.** A constant read by two scripts and quoted in a doc has three surfaces, and the doc is the one that drifts, because nothing runs it.
- **The agreement test is a real hermetic test that fails when the surfaces disagree** — named, not a suite and not "covered by the unit tests". The exemplar is the version pin in `tests/canonical-sdlc-evidence-gate.test.sh` §Section 2b: the commit gate and the write hook, each holding the literal `15`, driven on one plan at three versions so that they cannot disagree. Name what a test leaves out rather than rounding up to "pinned"; a surface becomes pinnable by changing its format or by naming it in the same test as the origin. `none — <why>` is a legitimate cell (prose against prose has no seam to test), but the reviewer stops on it: give the reason.

### The Test design table

`## Test design` sits beside `## Design` in a wave-or-epic spec; SKILL.md carries its contract. How to fill one in:

- **Approach is one line, and it is a design decision.** "Grep the rendered file for the six column headers" is an approach; "test it" is not. It names the seam the test reaches through, which is why the table is authored at Step 2, once the architecture has decided what is observable.
- **Test type is the ladder in words** — static · unit · hermetic · live · human, T0–T4 — because the Step-2 card counts types per requirement and `T0 T0 T2` tells a reader nothing to push back on.
- **Test is `command → expected observation`,** both halves: a command alone is a thing you ran, an observation alone is a hope. The observation is what the terminal shows — `rc=2, stderr names AC-K2.3`, never `the wall works`.
- **Fails when names a PLANTED DEFECT, singular and specific.** "the code is broken" fails the column; "the `fails-when:` line is deleted from one AC block" passes it, because a writer can make that mutation and watch the test turn red, first, before the code.
- **A criterion that admits no "Fails when" goes back to Step 1.** The defect is in the criterion's wording, and a test rewritten around an unfalsifiable criterion buys a green that means nothing.
- **One row per criterion, read in place.** Step 3 adds sequencing and authors no test.
- **The gate reads the Fails when column.** From step 4 on, a criterion whose Fails when is empty refuses the commit, naming the row. A waiver dissolves the obligation to RUN a test, never the obligation to have designed one.

## Close-out report (Step 9)

`steps/9.md` carries the terminal-disposition rule, rendered from `agents-src/blocks/terminal-disposition.md`; this is the authoring detail per part, and the report's bound.

**The report is one turn**: the close-out message itself, sent once at Step 9, never a file the user has to open. A close-out that spans turns or defers its verdict to a linked artifact is the ceremony the rule forbids.

**Ten parts, plain English, at the altitude of decisions:**

- **Goal** — what this run set out to do, in one sentence.
- **Accomplished** — what shipped, named plainly.
- **Deferred, with dispositions** — every finding that did not ship, each with its terminal disposition: DO-NOW (folded in, so none should be here), ACCEPT-CLOSED (won't-fix, with the one-line reason) or PROMOTE (its trigger event or chartered home, named). A finding with no disposition is the defect this template catches.
- **Special attention** — what the reader should look at closely before trusting the rest.
- **Material risks** — what could still go wrong, named, not hedged.
- **Challenges** — what made this run harder than the plan assumed.
- **Decisions** — the calls a later reader would want to know were made on purpose.
- **Success/failure verdict** — one plain sentence: did this run meet its goal.
- **Learnings** — what the next run should carry forward.
- **Next** — the immediate next action, named.

**The anti-ceremony bound.** The whole report reads in the time it takes to read this paragraph twice. A per-AC breakdown, a restated matrix, a section per step's evidence or a sub-heading per finding is the same failure: confirmation dressed up as an audit. A part with nothing to say gets one clause ("no material risks"), not a heading. Plain English means no jargon a plain reader would look up; the altitude is decisions and outcomes, not diffs, commands or file paths.

**The debt the continuation carries.** Close-out carries every unburned item of the run's debts into the continuation's `## Deferrals`, after the `deferred:` lines, one line each: `debt: <concept> <kind> "<sites>" touches=<N> raised-by=<record> from=<wave name>`, merged once into a continuation that exists. A burned item is not carried. The next run's Step 1 runs `session-poker.sh debt adopt <newest continuation>` right after its card.

**Archiving.** `archive-root:` (default `$HOME/bionic-archive`) and `archive-on-close:` (default `true`) in `.bionic/config.yaml` set where Step 9's `archive_run` moves a closed run, never `record:`, and whether it moves anything; see `payload/scripts/lib/archive.sh`.

**The released version.** An optional plan frontmatter field, `release: <version>`, names what the run released: `close-out.sh` writes it into step 9's `delivered`, the epic row's version cell and the continuation header; with none, no version is written and the epic cell reads `—`. The installed tool's version stays on `attested-by:`.

## Debts

Findings are classed by payment date, not by reviewer: harm (paid by the user, now), evidence (paid by the claim, now) and debt (paid by the next change). A finding of class debt — a second copy of a concept, an unpinned shared pair or a one-case abstraction — is the `debt:` line of `payload/context/severity.md`, rated by its kind and concept on that file's debt table, never by severity; it is flag-class in the derived result and writes no plan line.

**Where a debt lives.** One `debt` event in the run's log per item: its `concept`, `kind`, `sites`, `raised-by` record and `touches`, and `burned=<row>` once a row has burned it.

**Burn when touched.** The orchestrator records it at the Step-6 disposition, and the next row whose `Files:` touch the item's concept burns it inside its own work, or says why not.

**The touch counter.** A brief whose `Files:` cover one of an item's sites adds one to its `touches`, and the dispatch wall prints `debt: <concept> <kind> touches <N> — burn it in this row or say why not`; the highest count burns first. `ready` prints `debt: burned <N>, touched <M>` and close-out `debt: touched N · burned M`, never the count of debts.

**The verbs.** `session-poker.sh debt` is the debts' one writer, each subcommand taking the plan last, or the session's bound run:

- `debt add <review record>` appends a debt per debt line of a review, each concept and kind once.
- `debt touched <concept>` adds one to the touches of each unburned item of the concept.
- `debt burn <concept> <row>` marks each unburned item of the concept burned by the row.
- `debt list` prints the items, burned ones too.
- `debt adopt <continuation>` appends each `debt:` line a previous run's continuation carries, once, its touches and `raised-by` kept.

## The start join (`hooks/execution-recorder.sh`)

An agent start carries its type and id, never its launch, so it is joined to the one launch of its type the window leaves it (several are left to the launch call's return). A hook is told nothing when a dispatch ends without spawning, so a start whose own dispatch wrote no launch row, beside one launch denied or abandoned at its prompt, is joined to that dead launch.

## SDLC rulings

- **Deletion is not a task.** Deleting dead code the user has ruled on is a few-line commit by the
  orchestrator, not a dispatched task. Size the work before you pick the ceremony.
- **Approval steps are gate acts.** Ready tasks dispatch up to capacity without asking. A step
  that needs the user's explicit approval, a release among them, waits for the user, and it is never
  put to the user without the test results.
- **Late fixes get a fresh run.** A fix found after a run has closed becomes a fixit in a fresh
  canonical-sdlc run. It is never bolted onto the closed run, and a known defect blocks the
  push.
- **The doctrine is net zero.** The loaded set — `skills/canonical-sdlc/SKILL.md`, `skills/canonical-sdlc/steps/*.md`, `skills/canonical-sdlc/dispatch.md`, `skills/canonical-sdlc/operational-rules.md`, `agents/*.md` and `payload/context/*.md` — never grows: the commit wall sums its bytes before and after the staged change and refuses growth naming the delta and the files, unless the committing row reads an approval of `doctrine-growth` the run holds. A shrink passes silently. A sentence added here is paid for by a sentence removed.
- **A test proves a program.** A test proves what a program does, never what a document says: a check that pins the wording of doctrine or a file's size is refused at review as a defect, not accepted as evidence.
