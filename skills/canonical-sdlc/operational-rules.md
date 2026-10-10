---
name: canonical-sdlc-operational-rules
description: Canonical-sdlc operational rules — artifact shape, the Tasks table, design authoring, close-out, the debt ledger and the rulings. Copied beside SKILL.md, read on demand — nothing loads it.
updated: 2026-10-10
---

# canonical-sdlc operational rules

The detail SKILL.md and `steps/*.md` compress, each section cited from the step that needs it. It is reference, not a standing instruction: nothing loads it unprompted.

## Artifact paths and frontmatter

- **Canonical-sdlc artifacts live in `.bionic/docs/{specs,plans,adrs,incidents}/epic-NN-<slug>/`** (the default docs-root): `epic.plan.md`, `wave-NN-<slug>.plan.md` and `continuation.md` at the epic-dir root, with parallel specs/ and adrs/ trees; zero-padded epic numbers, kebab-case slugs. The evidence gate descends 2 levels to find nested plans. Both dirs are gitignored.

- **Canonical-sdlc artifacts require governing-skill frontmatter.** Every `*.plan.md`, `*.spec.md`, `adr-*.md`, `continuation*.md` under `.bionic/docs/{specs,plans,adrs}/` must open with:

  ```
  ---
  governing-skill: <skill-id>
  sdlc-step: N
  epic: epic-NN-<slug>
  wave: wave-NN-<slug>
  canonical_sdlc_version: 14
  intent: <intent>
  rigor: <rigor>
  scale: <scale>
  ---
  ```

  The `canonical-sdlc-governing-skill.sh` hook blocks a write missing `governing-skill:`; non-artifact files under those paths pass through.

### The `## Tasks` table

A plan's `## Tasks` table, at every scale, is the register the Step-4 dispatch works from: ten required columns, the optional `worktree` and `base`, and an optional `reads` (below):

```
| id | step | kind | task | agent | deps | size | serves | Files | worktree | base | status |
```

- **`id`** — `T<n>`, matching `^T[0-9]+$`, the row's own key.
- **`step`** — the SDLC step this row executes at (4 for build/test rows; 5–9 for verify/review/document/integrate/close rows).
- **`kind`** — one of `build | test | verify | review | doc | integrate | close | prototype`.
- **`task`** — the row's task in one line; `complexity: standard | complex` rides in this cell for Step-4 rows.
- **`agent`** — the ROSTER NAME the dispatch gave the agent (for example `w21-T5`), byte for byte, never the role: the commit gate matches an `active` row's cell to a roster `name=` and refuses one that "names no launched agent". A row nobody was dispatched for leaves the cell empty or `—`.
- **`deps`** — task ids (`T1, T4`) or an external prerequisite `ext:<slug>`, never prose: `units.sh`'s validator splits the cell on `,`, and every token must resolve in the id set or match `ext:<slug>` (a letter or digit, then letters, digits, `.`, `_` or `-`). Without `reads`, an id reads "wait for that task to land"; with it, this cell holds only `ext:` tokens. An `ext:` token holds the row out of the ready set, named on the Patrol tick's `HELD` line, until it is removed.
- **`reads`** (optional, found by its header name) — what the row must have before it is ready; write a read only where the row reads what another row writes. The edges between rows are computed from these cells, never written by hand.

  | piece | shape |
  |---|---|
  | reads cell | comma-separated: a `Files` path · `head` · `record` · `proof:<kind>` · `approval:<name>` · `ext:<slug>` · `live:<artifact>`; empty takes the kind default |
  | kind defaults | build `approval:plan` · verify `approval:plan, head` · review `approval:plan, live:head` · doc `approval:plan, head`, and at Step 7 or later an `approval:` read written out (`approval:release` for the release) · integrate `proof:floor, proof:review, head` · close the integrate row's merge |
  | read row | a `review` row reading `live:head:<q>[+<q>]`, each `<q>` one of `evidence` · `adversarial` · `structure`, holds, ranges (the tick's `RANGE` line) and returns to pending per question; a bare `live:head` keeps one range. Under one review disposition the read row is `reads: approval:plan, head`, ready once the last build row lands (`steps/6.md`) |

- **`size`** — the row's expected duration in minutes.
- **`serves`** — the requirement id(s) this row discharges.
- **`Files`** — every path the row may create or edit (the dispatch budget's source). Two rows that write one file run side by side and reconcile on landing; an entry ending in `!` is unmergeable, and a second row that writes it waits for the first to land.
- **`worktree`** (optional) — the row's tree path once created; `—` while none exists.
- **`base`** (optional, ADR-032) — the commit the tree was cut from, as `spawn-worktree.sh` printed it. Absent, the landing gate reconstructs it from `working-branch:` and says so.
- **`status`** — `pending | active | landed | dropped`, at every scale.

**Approvals and proofs a `reads` cell names.** `approval:plan` is the `approved-by:` line Step 3 writes. Any other approval, and every proof, is a line inside `## SDLC State` that only its verb writes, never a hand edit:

| piece | shape |
|---|---|
| approval | `approved: <name> by <who> <ISO-UTC> "<reply>"`, written by `session-poker.sh approve <name> '<reply>'` on the user's own reply, quoted verbatim |
| proof | `proved: kind=<floor\|review\|task\|check> head=<40-hex> at=<ISO-UTC> evidence=<path under record/>`, written by `session-poker.sh proof-add <kind> <evidence>`; the head is the evidence's own (a log's `head=` header, a review's `reviewed: a..b` end), never an operand; `proof-add check` is refused |
| reading | `proof-add review <record> --question <q> --reader <name>` adds ` question=<q> reader=<name> result=<pass\|flag\|fail> scope=<piece\|whole>`; the reader's role is read from its roster row and must be dealt the question. The record's lines are `steps/6.md`'s |
| declared check | `release-check: <command>` in `.bionic/config.yaml`, run with `BIONIC_CHECK_BASE`, `BIONIC_CHECK_HEAD` and `BIONIC_CHECK_TREE`; exit 0 passes; its words split on white space, so a check needing quoting is a script. `session-poker.sh release-check` (main thread, clean tree, no operand) runs it from the last release to the working head, writes `record/<wave>/release-check-<head>.log` and the `kind=check` line (` result=fail` on a non-zero exit). `land` runs it in the target checkout up to the task's head and refuses `why=release-check` when it fails, or `reason=check-dirtied` when it moved the target's HEAD or dirtied either tree; nothing is merged |
| declared regression | `floor: <command>` (run by `floor-run`) or `floor-attestation: user` in `.bionic/config.yaml`, their records `steps/5.md`'s; with neither, the regression is `tests/run.sh`'s whole run |
| landing record | `<docs-root>/record/<plan name less .plan.md>/landing-proofs.log`, appended by `ready` and the hand landing (`spawn-worktree.sh land <tree> --by-hand --reason '<why>'`), never rewritten: one `line/v1\|ev=<act>\|…` line per act, and per publish a `landed: row=<id> branch=<b> head=<40-hex> merge=<40-hex> at=<ISO-UTC>` header. A row's landing is the `merge=` of its last header. An unwritable record refuses `why=proofs-unwritable` |
| declared debt | a brief's one `Lands-red: <name>.test.sh until <ext:slug\|approval:name>` with `Red-evidence: <path under record/>`, recorded by the dispatch wall alone (`amend` cannot add them). `land` accepts that one suite red, every other suite green, when the evidence holds `head: <40-hex>` naming the head landed, and appends `debt: id=… row=… suite=… token=…` to the landing record. It stays open until a regression or task proof shows the suite green after the red landing (and after the `approved:` line, for `approval:`); `current 8`, close-out, the integrate row and, from Step 6, the commit gate refuse while it is open |
| debt ledger | `## Debt ledger` below |

**The regression, once.** A build row runs the suites its brief names; a fix row runs the red suites plus its own. The floor is one whole green run at a commit on the branch plus every later commit proved by the suites its row named (`steps/5.md`). A second whole run needs the user's word, `session-poker.sh approve regression-2`: the dispatch wall reads a suite set holding `run.sh` as a whole run and refuses one at `regression: no`, while a row the regression waits on writes tracked files, on a proved head, or a second on this plan unless the row reads `approval:regression-2` and its `approved:` line exists.

**`working-branch:`** in the plan's frontmatter names the wave's branch: the landing gate (`lib/stop.sh`) merge-bases a task tree against it, and `worktree_land_for_session` merges a landed tree into it. A plan naming none falls back to the main checkout's branch, announced inert.

**Cell shapes.** One `- T<n>:` line per `## Tasks` row, inside `## SDLC State`: the ledger check reads that section, never `## Tasks`. A Verification Matrix `evidence:` cell names exactly one path under `record/`, optionally ` — <note>`; a `;`-joined list is refused. An `auditor` cell is the bare token `CONFIRMED`; cite an audit inside `evidence:`, never beside the token. The Step-5 block's `pass:`/`total:` gate; `advisory-exceeded: <M>` beside them is recorded, never judged.

## Design section authoring (the Step-2 back-half)

SKILL.md carries the contract — the five parts, the three-way rule, the scale line, the
mandatory Design Interview, and the provenance chain each design decision sits in. This is how
to author one that earns its keep.

### The view menu

A design is several *views* of one change, and a design goes wrong less by a wrong answer than by a view nobody looked at:

- **logical domain model** — the entities and relationships the change reasons about;
- **entity / data design** — the concrete shape of those entities: fields, types, identity;
- **persistence** — schema, mutability, transactions, migration;
- **application / component design** — modules, boundaries, control flow, who calls whom;
- **integration surfaces** — the contracts crossed: APIs, hooks, CLIs, file formats, events;
- **deployment / runtime architecture** — where it runs, in what process, under what lifecycle.

**The design names which views the change touches, and includes those.** A view excluded costs one clause — "no persistence: nothing is stored" — and that clause is the difference between a decision and an oversight. **Silent omission is the failure the menu exists to prevent**: a view in neither list is itself the finding. Padding with empty headings is its own failure; most work here touches application/component design and integration surfaces and excludes the rest in a clause apiece.

### The form menu

`steps/2.md` names the five rungs; this is how the suggested default is derived. Cheapest first:

- **design paragraph** in the session plan — the default at `scale: task`: what it touches, what owns the concept, what breaks if the assumption is wrong.
- **`## Design` section** in the spec — the default at `scale: wave`, and the rung to beat: the design sits beside the requirements it answers.
- **standalone design doc** — when the design outlives its wave or several waves implement it; it is what a `design:` pointer resolves to.
- **structured models** — when topology is the hard part: the moment "who calls whom, in what order, across which process boundary" takes a paragraph, it wants a picture.
- **full Technical Design Document** — at momentous or cross-system scope, with readers who will never open the spec.

The rungs compose: structured models most often live inside a `## Design` section or a standalone doc.

**Derivation produces a suggested default, never a selection.** Scale gives the starting rung —
task to paragraph, wave to `## Design` section — and three signals move it up: a design several
waves will implement (standalone doc), topology prose would flatten (add structured models), a
cross-system surface with its own readership (full Technical Design Document). One signal moves
it down: a wave whose design is one decision wide gets a short section, not a doc. Print the
result in the frame with the one-line reason it was derived; the user moves it up, moves it down,
or lets it stand.

**Nothing enforces the rung, deliberately.** The three-way wall accepts every rung, in place or by pointer, so form selection cannot fail a gate: it is guidance approved in conversation.

### The ownership table

The load-bearing row of the section, and the only part later steps consume mechanically: the `structure` checks `reuse` and `one-site` anchor on the owner column, and the `structure` reader reads the agreement-test column back. Shape:

```
| concept | owning module (SSoT) | reuses | rendering surfaces | agreement test |
|---|---|---|---|---|
| version pin value | `payload/scripts/lib/walls.sh`'s `SUPPORTED_SDLC_VERSION` (the commit gate behind `hooks/bash-walls.sh`) | none fits: no other file holds a version constant | the governing-skill hook · the two SVG diagrams | `tests/cross-gate-agreement.test.sh` §V pins the renderings against the gate's value, with a mutation arm |
| agreement-test duty + authoring rules | `agents-src/blocks/checks-structure.md` (`one-site`) | the render markers of `agents-src/render.sh` | payload/context/checks-structure.md · this section | `bash agents-src/render.sh --check` holds the rendered file to its block; this section is the unpinned one |
```

- **The `reuses` cell names the existing site the design reuses, or `none fits: <why>`.** Empty is a finding: the design never looked. A writer's `reuse:` report line answers the same question for each site the build added.
- **One row per concept rendered at more than one surface.** A concept in one place has nothing to disagree with; the table is a duplication ledger, not an inventory.
- **The owner is a place, not a layer or a role.** "the governing-skill hook" is an owner; "the backend" is not. With no file, function or named constant to name, the concept has no owner yet — write that down as the finding.
- **Rendering surfaces include prose.** A constant read by two scripts and quoted in a doc has three surfaces, and the doc is the one that drifts, because nothing runs it.
- **The agreement test is a real hermetic test that fails when the surfaces disagree** — named, not a suite and not "covered by the unit tests". The exemplar is the `SUPPORTED_SDLC_VERSION` pin in `tests/cross-gate-agreement.test.sh` §V: one constant, its renderings held against the gate as origin, with a mutation arm. Name what a test leaves out rather than rounding up to "pinned"; a surface becomes pinnable by changing its format (SVG made the diagrams' version greppable) or by naming it in the same test as the origin. `none — <why>` is a legitimate cell — prose against prose has no seam to test — but the reviewer will stop on it, so give the reason.

### The Eval design table

`## Eval design` sits beside `## Design` in a wave-or-epic spec, one row per acceptance criterion; SKILL.md carries its contract. How to fill one in:

- **Approach is one line, and it is a design decision.** "Grep the rendered file for the six column headers" is an approach; "test it" is not. It names the seam the eval reaches through, which is why the table is authored at Step 2, once the architecture has decided what is observable.
- **Eval type is the ladder in words** — static · unit · hermetic · live · human, T0–T4 — because the Step-2 card counts types per requirement and `T0 T0 T2` tells a reader nothing to push back on. The tier code travels into the plan's matrix.
- **Eval is `command → expected observation`,** both halves: a command alone is a thing you ran, an observation alone is a hope. The observation is what the terminal shows — `rc=2, stderr names AC-K2.3`, never `the wall works`.
- **Fails when names a PLANTED DEFECT, singular and specific.** "the code is broken" fails the column; "the `fails-when:` line is deleted from one AC block" passes it, because a writer can make that mutation and watch the eval turn red, first, before the code.
- **A criterion that admits no "Fails when" goes back to Step 1.** The defect is in the criterion's wording, and an eval rewritten around an unfalsifiable criterion buys a green that means nothing.
- **One row per criterion, and the plan renders them.** Step 3 adds sequencing and the matrix's bookkeeping columns and authors no eval of its own.
- **The gate reads the rendered column.** From `current: 4` on, an AC block whose `fails-when:` is missing or empty refuses the commit, naming the row. A waiver dissolves the obligation to RUN an eval, never the obligation to have designed one.

## Close-out report (Step 9)

SKILL.md §Step 9 carries the terminal-disposition rule, rendered from `agents-src/blocks/terminal-disposition.md`; this is the authoring detail per part, and the bound that keeps the report from growing back into ceremony.

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

**The debt the continuation carries.** Close-out carries every unburned item of the run's debt ledger into the continuation's `## Deferrals`, after the `deferred:` lines, one line each: `debt: <concept> <kind> "<sites>" touches=<N> raised-by=<record> from=<wave name>`, merged once into a continuation that exists. A burned item is not carried. The next run's Step 1 runs `session-poker.sh debt adopt <newest continuation>` right after its card.

**Archiving.** `archive-root:` (default `$HOME/bionic-archive`) and `archive-on-close:` (default `true`) in `.bionic/config.yaml` set where Step 9's `archive_run` moves a closed run, never `record:`, and whether it moves anything; the move is documented at its definition in `payload/scripts/lib/archive.sh`.

**The released version.** An optional plan frontmatter field, `release: <version>`, names what the run released: `close-out.sh` writes it into the `delivered:` line, the epic row's version cell and the continuation header; with none, no version is written and the epic cell reads `—`. The installed tool's version is never the release: it stays on `attested-by: close-out.sh <version>`.

## Debt ledger

Debt is paid by the next change that touches it, not by a user, so it is kept as a ledger and burned when touched. Findings are classed by payment date, not by reader: harm (paid by the user, now), evidence (paid by the claim, now) and debt (paid by the next change). A finding of class debt — a second copy of a concept, an unpinned shared pair or a one-case abstraction — is the `debt:` line of `severity.md`, rated by its kind and concept on the debt table of `payload/context/severity.md`, never by severity; it is flag-class in the derived result and writes no plan line.

**The file.** `<docs-root>/record/<run>/debt.md`, under the header:

```
concept | kind | sites | raised-by <record> | touches N | burned <row> | —
```

one line per item, its last cell `—` while open and `burned <row>` once a row has burned it.

**Burn when touched.** A debt finding's disposition is burn-when-touched, never fix now and never note. The orchestrator records it at the Step-6 disposition, and the next row whose `Files:` touch the item's concept burns it inside its own work, or says why not.

**The touch counter.** A brief whose `Files:` cover one of an item's sites adds one to its `touches`, and the dispatch wall prints `debt: <concept> <kind> touches <N> — burn it in this row or say why not`; the highest count burns first. `ready` prints `debt: burned <N>, touched <M>` and close-out `debt: touched N · burned M`, never the ledger's length.

**The verbs.** `session-poker.sh debt` is the ledger's one writer, each subcommand taking the plan last, or the session's bound run:

- `debt add <reading record>` writes a line per debt line of a reading, each concept and kind once.
- `debt touched <concept>` adds one to the touches of each unburned item of the concept.
- `debt burn <concept> <row>` writes `burned <row>`.
- `debt list` prints the items.
- `debt adopt <continuation>` writes each `debt:` line a previous run's continuation carries into this ledger, once, its touches and `raised-by` kept.

## The start join (`hooks/execution-recorder.sh`)

An agent start carries its type and id, never its launch, so the start is joined to the one launch of its type the window leaves it (several are left to the launch call's return), and a hook is told nothing when a dispatch ends without spawning: a start whose own dispatch wrote no launch row, beside one launch that was denied or abandoned at its prompt, is joined to that dead launch (wave-27 T68, named and left for the next wave).

## SDLC rulings (moved from the repo CLAUDE.md, wave-31)

- **Deletion is not a task.** Deleting dead code the user has ruled on is a few-line commit by the
  orchestrator, not a dispatched task. Size the work before you pick the ceremony.
- **Approval steps are gate acts.** Ready tasks dispatch up to capacity without asking. A step
  that needs the user's explicit approval, a release among them, waits for the user, and it is never
  put to the user without the test results.
- **Late fixes get a fresh run.** A fix found after a run has closed becomes a fixit in a fresh
  canonical-sdlc run. It is never bolted onto the closed run, and a known defect blocks the
  push.
- **The doctrine is net zero.** The loaded set — `skills/canonical-sdlc/SKILL.md`, `skills/canonical-sdlc/steps/*.md`, `skills/canonical-sdlc/dispatch.md`, `skills/canonical-sdlc/operational-rules.md`, `agents/*.md` and `payload/context/*.md` — never grows: the commit wall sums its bytes before and after the staged change and refuses growth naming the delta and the files, unless the committing row reads `approval:doctrine-growth` and the plan carries its `approved: doctrine-growth` line. A shrink passes silently. A sentence added here is paid for by a sentence removed.
- **A test proves a program.** A test proves what a program does, never what a document says: a check that pins the wording of doctrine or a file's size is refused at review as a defect, not accepted as evidence.
