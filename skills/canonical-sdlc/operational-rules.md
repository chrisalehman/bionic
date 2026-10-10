---
name: canonical-sdlc-operational-rules
description: Canonical-sdlc operational rules — artifact shape, evidence gating, intent-specific behaviors, version history. Bulk procedural reference; copied beside SKILL.md, read on demand — nothing loads it.
updated: 2026-08-02
---

# canonical-sdlc operational rules

The high-priority operational rules for the canonical-sdlc skill — artifact shape, evidence gating, intent-specific behaviors.

Read this when you are running canonical-sdlc and need the detail SKILL.md compresses — its
`## Canonical SDLC` intro points here by name. It is reference, not a standing instruction:
nothing loads it unprompted, and being copied beside the skill is not the same as being loaded.

## Artifact paths and frontmatter

- **Canonical-sdlc artifacts live in `.bionic/docs/{specs,plans,adrs,incidents}/epic-NN-<slug>/`** (default docs-root; the `docs/bionic/` override retired 2026-07-16 — epics 01–05 migrated in place, hook resolution probe-proven). Directory-per-epic layout: `epic.plan.md` + `wave-NN-<slug>.plan.md` + `continuation.md` at the epic-dir root; parallel specs/ and adrs/ trees. Zero-padded epic numbers, kebab-case slugs. Evidence-gate hook descends 2 levels to find nested plans; governing-skill hook enforces frontmatter on artifact-named files under these paths. Both dirs gitignored.

- **Canonical-sdlc artifacts require governing-skill frontmatter.** Every `*.plan.md`, `*.spec.md`, `adr-*.md`, `continuation*.md` under `.bionic/docs/{specs,plans,adrs}/` must have:

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

  at the top. The `canonical-sdlc-governing-skill.sh` PreToolUse|Write,Edit hook blocks writes missing the `governing-skill:` field. Non-artifact files (README.md, images) under those paths pass through.

### The `## Tasks` table

A plan's `## Tasks` table, at every scale, is the register the Step-4 dispatch works from, and it carries twelve columns: ten required, plus the optional `worktree` and `base`, and a table may add one more, the optional `reads` (below):

```
| id | step | kind | task | agent | deps | size | serves | Files | worktree | base | status |
```

- **`id`** — `T<n>`, matching `^T[0-9]+$`, the row's own key.
- **`step`** — the SDLC step this row executes at (4 for build/test rows; 5–9 for verify/review/document/integrate/close rows the wave also tables here).
- **`kind`** — one of `build | test | verify | review | doc | integrate | close | prototype`.
- **`task`** — the row's task in one line; `complexity: standard | complex` rides in this cell for Step-4 rows.
- **`agent`** — carries the ROSTER NAME the dispatch gave the agent (for example `w21-T5`), byte for byte, never the role: the commit gate matches an `active` row's cell to a roster `name=`, and the role lives in the task cell's complexity tag and the dispatch ledger. A row nobody was dispatched for leaves the cell empty or `—`. A row dispatched before 1.8.8 with a role in this cell is refused by the 1.8.8 commit gate once a roster exists ("names no launched agent"), even with its `- T<n>:` line written; to migrate an in-flight plan, write each `active` row's roster name into the cell.
- **`deps`** — task ids (`T1`, or `T1, T4` for more than one) or an external prerequisite `ext:<slug>` (`T1, ext:ci-green`), never prose. A table that carries `reads` refuses a task id here; a table without it reads each id as "wait for that task to land". With `reads`, this cell holds only `ext:` tokens, and every edge between rows comes from `reads`. An `ext:` token, in either cell, holds the row out of the ready set, and the Patrol tick names it on a `HELD` line, until the token is removed from the cell. A prose token here (`"dep T17 (rows; lands after T15)"`) is parsed as its own id and refused as unknown — `units.sh`'s bring-forward validator splits this cell on `,`, and every token must resolve in the id set or match `ext:<slug>` (a letter or digit, then letters, digits, `.`, `_` or `-`); a token with a blank inside is refused.
- **`reads`** (optional, found by its header name like every column, so it may sit anywhere) — what the row must have before it is ready. Write a read only where the row reads what another row writes; an empty cell takes the kind default. The edges between rows are computed from these cells, never written by hand.

  | piece | shape |
  |---|---|
  | reads cell | comma-separated: a path in the `Files` grammar · `head` · `record` · `proof:<kind>` · `approval:<name>` · `ext:<slug>`; a live read is `live:<artifact>`; empty takes the kind default |
  | kind defaults | build `approval:plan` · verify `approval:plan, head` · review `approval:plan, live:head` · doc `approval:plan, head`, and at Step 7 or later an `approval:` read written out (`approval:release` for the release) · integrate `proof:floor, proof:review, head` · close the integrate row's merge |
  | read row | a `review` row whose `reads` carries `live:head:<q>[+<q>]`, each `<q>` one of `evidence` · `adversarial` · `structure`; exclusivity, range and return-to-pending are per question: only a row sharing a question holds it, its range (the tick's `RANGE` line) starts at the oldest last reading among its questions, and `proof-add review --question <q>` returns the active row carrying `<q>`. A bare `live:head` keeps one range from the last review proof of any question Under one review findings disposition a plan's read row reads the settled whole: `reads: approval:plan, head`, ready once the last build row lands (`steps/6.md`) |

- **`size`** — the row's expected duration in minutes.
- **`serves`** — the requirement id(s) this row discharges.
- **`Files`** — every path the row may create or edit (the dispatch budget's source). Two rows that write one file run side by side and reconcile on landing; a `Files` entry ending in `!` is unmergeable, and a second row that writes it waits for the first to land.
- **`worktree`** (optional) — the row's tree path once created; `—` while none exists yet.
- **`base`** (optional, ADR-032) — rides beside `worktree`: the commit the tree was cut from, as `spawn-worktree.sh` printed it at creation. Absent (`—`) means the landing gate reconstructs the base from `working-branch:` instead, and says so.
- **`status`** — `pending | active | landed | dropped`, at every scale.

**Approvals and proofs a `reads` cell names.** `approval:plan` is the `approved-by:` line Step 3 writes. Any other approval, and every proof, is a line inside `## SDLC State` that only its verb writes, never a hand edit:

| piece | shape |
|---|---|
| approval line | `approved: <name> by <who> <ISO-UTC> "<reply>"` inside `## SDLC State`; `approval:plan` is the existing `approved-by:` line |
| approval verb | `session-poker.sh approve <name> '<reply>'` |
| proof line | `proved: kind=<floor\|review\|task\|check> head=<40-hex> at=<ISO-UTC> evidence=<path under record/>` inside `## SDLC State`; a reading adds ` question=<q> reader=<roster name> result=<pass\|flag\|fail> scope=<piece\|whole>`, the question one of `evidence` · `adversarial` · `structure` |
| proof verb | `session-poker.sh proof-add <kind> <evidence path>`; the head the evidence names: a run log's `head=` header, a review's `reviewed: a..b` end; never an operand. A reading: `session-poker.sh proof-add review <record> --question <q> --reader <name>`; the reader's role is read from its roster row, never typed, and must be a reader role dealt the question; its range starts at or before that question's last proof |
| reading record | a file under `record/` with flush-left lines `reviewed: <a>..<b>`, `question: <q>`, `result: <pass\|flag\|fail>`, `scope: <piece\|whole>`; for `structure`, one line `check: <id> <PASS\|FLAG\|FAIL\|n/a> <reason>` per check id. It holds exactly one pass, and a record of a second is refused (only a plain review proof's record is read from its top pass, its first `reviewed:` line); each value is its set's word, whole; a `structure` `pass` stands beside no FLAG or FAIL check, a `flag` beside no FAIL; `scope: whole` starts at the plan's `base-sha:` or an ancestor of it. The record is its reader's roster `deliverable=` or one of its `files=`, on a row past `intended`, so a reader dealt several questions writes one record per question and its brief lists each on `Files:`. When the reader's roster row carries `severity` in `pushed=`, the pass also holds `findings: <n>` and one `finding: <n> <S1\|S2\|S3\|S4> <on\|off> <path>:<line>` per finding, with `shown: <n> <command>` for each finding the severity table sends to fix, or `unsure: <n> <what is not known>` for one that owes a check; it writes no priority, and one that differs from the table is refused; its `result:` is the one the priorities derive (a finding to fix gives `fail`, any other finding `flag`, none `pass`), and for `structure` a FAIL check stands beside a finding to fix and a finding to fix beside a FAIL check; and registration writes `deferred: <record>#<n> <S> <reach> "<title>"` for each finding the table defers and `check: <record>#<n> <S> <reach> "<title>"` for each unsure one inside `## SDLC State`. Otherwise a reader not pushed the scale is read as before |
| declared check | `release-check: <command>` in `.bionic/config.yaml`; run with `BIONIC_CHECK_BASE` and `BIONIC_CHECK_HEAD` in its environment; exit 0 passes. It is also handed `BIONIC_CHECK_TREE`, the piece's checkout at a landing and the working checkout under the release verb. At a landing its working directory is the TARGET checkout, not the piece, so a check reads the piece by `BIONIC_CHECK_BASE..BIONIC_CHECK_HEAD` or under `BIONIC_CHECK_TREE`. Its words split on white space with no quoting, so a check that needs quoting, a pipe or a variable is a script the command names. With no key nothing is owed, run or printed |
| check verb | `session-poker.sh release-check`, from the main thread only, takes no operand: in the working branch's checkout, on a clean tree (its index refreshed first), it runs the declared command from the last release (the nearest tag reachable from the plan's `integration-branch:` that is a proper ancestor of the working head, else its `base-sha:`; a range holding no commit is refused) to the working head. Every run writes `record/<wave>/release-check-<head>.log`, its first line `head=<40-hex> rc=0` on a pass and `rc=<exit>` otherwise, after one `check-changed: <path>` line per tracked path the command names as a word and the range changes; a later run at one head writes `release-check-<head>-<n>.log`. Then the `kind=check` proof line, which on a non-zero exit carries ` result=fail` while the command's output is printed. The judge owes it and reads the last line at the head asked (`facts_state`: covered, or failing with its log; uncovered past it; absent with none). The declared check's own files are covered code, read like any other, and the release card names a changed check: the verb's success line carries its `check-changed:` lines. `proof-add check` is refused. `land` runs the same command in the target checkout, as it stands before the merge and never in the task's tree, from the working branch's head to the task's head, and on a non-zero exit refuses `why=release-check`, changing nothing; after the command, before the merge, the target's HEAD must be the commit it was, the target clean in what git tracks and the piece's checkout as clean as it was: a command that commits on the target, leaves a tracked file in it changed, or dirties the piece refuses `reason=check-dirtied why=release-check`, naming which (`head_was=`/`head_now=`, `paths=`, `piece_paths=`), nothing merged and both left as the command left them; a command that fails and leaves any of these is refused `check-failed` with the same fields; a HEAD that moved while the command ran was moved by it or by another landing into the same branch, which `land` cannot tell apart, so that refusal says both, names the two short ids, says nothing is merged and to land again, and asks for a commit to be taken off the target only if the move is the command's own |
| declared regression | `floor: <command>` in `.bionic/config.yaml`: this project's regression is that command's run, not `tests/run.sh`'s whole run. Its words split on white space with no quoting, as `release-check:`'s do, so a regression that needs quoting is a script the command names. `session-poker.sh floor-run` takes no operand: in the working branch's checkout it reads the head and the dirty count, runs the command, and reads both again; a run that moved either is refused and writes no log. Otherwise it writes `record/<wave>/floor-run-<head>.log`, its first line `head=<40-hex> dirty=<n> rc=<n>`, then `command: <cmd>`, then the output (a later run at one head writes `floor-run-<head>-<n>.log`), prints the `proof-add floor <log>` line and exits with the command's code. It writes no proof: `proof-add floor` stays the one writer of the proof line, and with the key it judges that first line alone, the head the working head, dirty 0 and rc 0, with no `Gating:` verdict and no roster count. With no key `floor-run` is refused and nothing runs |
| regression attestation | `floor-attestation: user` in `.bionic/config.yaml` (any other value is refused): this project's regression is a record the user attests, cited by `proof-add floor <record>`. The record carries a line `head=<40-hex> dirty=0` naming the working head and a line `floor-attested-by: <who> <when> <what ran>`, three words or more after the key; a missing line is refused by its name. With both keys either shape is accepted, a `floor-run` log judged as one first. With neither, the regression is `tests/run.sh`'s whole run as before; `current 8`, close-out and the judge read the proof line whichever shape proved it |
| landing record | `<docs-root>/record/<the bound plan's name less .plan.md>/landing-proofs.log`, appended by `ready` and the hand landing (`spawn-worktree.sh land <tree> --by-hand --reason '<why>'`), never rewritten. Each act is one line, exactly as written: `line/v1|ev=ready|row=<id>|name=<roster name\|->|commit=<40-hex>|branch=<b>|tree=<abs>|suites=<a,b\|none>|debt=<suite\|->|carrier=<pid>:<start>|at=<ISO-UTC>`, then `ev=candidate`, `ev=verdict` (`result=<green\|red\|none\|discarded>|log=<path>`), `ev=standing`, `ev=returned` (`why=<red\|conflict\|guard>`), `ev=stalled` and `ev=published` (`kind=<queue\|hand\|git>`). After each publish it also appends the header `landed: row=<row id\|—> branch=<branch> head=<40-hex> merge=<40-hex> at=<ISO-UTC>`. It is proved writable before anything is published; one that cannot be written is refused `why=proofs-unwritable`, nothing changed. A suite's output lives beside it under `line/`. A row's landing is the `merge=` of the last header carrying its `row=` |
| declared debt | a brief's ONE `Lands-red: <name>.test.sh until <ext:slug\|approval:name>` and `Red-evidence: <path under record/>`, recorded by the dispatch wall alone as `lands_red=` and `red_evidence=` on the launch row (refused: a second `Lands-red:` line, the full-suite runner `run.sh` however spelled, a suite outside the row's set, a missing evidence line, evidence outside the record root, a token of another shape, an `approval:` no row reads or an integrate row reads; `amend` cannot add them). `land` accepts a red newest run of exactly that suite when every other suite at the head is green and the evidence file holds a line `head: <40-hex>` naming the head being landed, and `land` writes the debt, the orchestrator copies nothing: before the merge it appends `debt: id=… row=… branch=… head=… suite=… token=… at=<ISO-UTC>` to the landing record (refused, nothing merged, when it cannot), a `void: id=…` line when the merge then fails or is undone (a void it cannot write leaves the debt standing, and the refusal says so), and `LANDED` carries `landed-red=<suite> landed-red-at=<that time>`. A `landed red:` plan line is a note and changes nothing. `facts_owed` deals one `debt` per suite and token the record owes, covered only by a regression proof or a task proof whose log shows that suite green, dated strictly after the newest red landing of that suite and token and, for `approval:`, after the `approved:` line too; for `ext:`, only once no `## Tasks` cell holds the slug as a whole token. For `ext:` the green run is held to be later than the red landing, not later than the clearing, because nothing dates a clearing. `current 8`, close-out and the integrate row refuse while it is open, and from Step 6 so does the commit gate, handed the record's open debts by its collector: it reads the dated proofs in `## SDLC State` and leaves the slug and the task log to the judge |
| debt ledger | `<docs-root>/record/<the bound plan's name less .plan.md>/debt.md`: the header `# debt ledger: concept \| kind \| sites \| raised-by <record> \| touches N \| burned <row> \| —`, then one line per item, `<concept> \| <kind> \| <sites> \| raised-by <record> \| touches <N> \| —`, its last cell `burned <row>` once a row has burned it. A finding of class debt is the `debt:` line of `severity.md`, read by the registering verb's reader (`proof_findings`, which refuses one carrying a severity, a reach or a kind outside the debt table); it is flag-class in the derived result and writes no plan line. The ledger has one writer, `session-poker.sh debt`, each subcommand taking the plan last or the session's bound run: `session-poker.sh debt add <reading record> [<plan>]`, run by the orchestrator at the disposition, writes a line per debt line of the reading, each concept and kind once; `debt touched <concept> [<plan>]` adds one to the touches of each unburned item of the concept; `debt burn <concept> <row> [<plan>]` writes `burned <row>`; `debt list [<plan>]` prints the items. The dispatch wall's advisory prints `debt: <concept> <kind> touches <N> — burn it in this row or say why not` for each unburned item one of whose sites an allowed brief's `Files:` covers (the path, a directory above it, a glob over it), and touches it, N counting this row; `ready` prints `debt: burned <N>, touched <M>` between `LANDED` and the owed line when the run keeps a ledger (N the items the row burned, M the items its `Files` cover); close-out prints `debt: touched <N> · burned <M>` for the run, the touches summed and the items burned, never the ledger's length |

**The regression, once.** A build row runs the suites its brief names. After the last build row lands, one whole run, when the plan's `regression:` is `yes`. A fix row runs the red suites plus its own. The floor is one whole green run at a commit on the branch plus every later commit proved by the suites its row named; a second whole run needs the user's word: `session-poker.sh approve regression-2`. The dispatch wall reads a dispatch whose suite set holds `run.sh` as a whole run: it refuses one at `regression: no`, while a row the regression waits on writes tracked files, or on a proved head, and a second on this plan (any roster row whose `plan=` is it and whose `suites_allowed=` holds `run.sh`) unless the dispatch's row reads `approval:regression-2` and the `approved: regression-2` line exists.

`approve` is run on the user's own reply, quoted verbatim, the same rule as the `approved` word at Step 3.

**`working-branch:`** in the plan's frontmatter names the wave's own branch: the key `lib/stop.sh`'s landing gate reads to merge-base a task tree against — "what this task added" is computed against that branch, not against the main checkout's current one — and, since T8 (wave-20, REQ-1), the branch `worktree_land_for_session` merges a landed tree into, in the checkout that holds it. A plan naming none falls back to the main checkout's branch, announced inert.

**Cell shapes (authoring time, 2026-09-20, epic-23 wave-17 T9; AC-5.5, AC-7.1, AC-10.3).** Four shapes an author gets right at write time, not after a refusal: one `- T<n>:` line per `## Tasks` row, inside `## SDLC State` — the ledger check reads that section, never `## Tasks` itself. A Verification Matrix `evidence:` cell names exactly one path under `record/`, optionally followed by ` — <note>` — a `;`-joined list of paths is refused, one AC one file. An `auditor` cell is the bare token `CONFIRMED`, exact match; an annotation such as `CONFIRMED (audit-x.md)` blocks — cite the audit inside `evidence:` instead, not the token. The Step-5 evidence block's `pass:`/`total:` keys gate rows only; an optional `advisory-exceeded: <M>` rides beside them, recorded, never judged — a suite with advisory exceeds and a green `pass == total` discharges.

## Design section authoring (the Step-2 back-half)

SKILL.md carries the contract — the five parts, the three-way rule, the scale line, the
mandatory Design Interview, and the provenance chain each design decision sits in. This is how
to author one that earns its keep.

### The view menu

A design is several *views* of one change, and the way a design goes wrong is rarely a wrong
answer — it is a view nobody looked at. The menu:

- **logical domain model** — the entities and relationships the change reasons about;
- **entity / data design** — the concrete shape of those entities: fields, types, identity;
- **persistence** — schema, mutability, transactions, migration;
- **application / component design** — modules, boundaries, control flow, who calls whom;
- **integration surfaces** — the contracts crossed: APIs, hooks, CLIs, file formats, events;
- **deployment / runtime architecture** — where it runs, in what process, under what lifecycle.

**The design names which views the change touches, and includes those.** A view considered and
excluded costs one clause — "no persistence: nothing is stored" — and that clause is worth its
line, because it is the entire difference between a decision and an oversight. **Silent
omission is the failure the menu exists to prevent**: a view that appears in neither list is
itself the finding, and the reader cannot tell an inapplicable view from a forgotten one.

Not every change touches every view, and padding the section with empty headings is its own
failure. Most work in this repo touches application/component design and integration surfaces
and excludes entity/data design and persistence in a clause apiece; that is a healthy shape,
not a thin one.

### The form menu

The view menu says what the design must look at. This one says what it gets *written as*. That
is a decision too, and it is made in the frame in front of the user rather than by whatever
template the author reached for first. Five rungs, cheapest first:

- **design paragraph in the session plan** — the suggested default at `scale: task`. One
  non-trivial task, one paragraph: what it touches, what owns the concept, what breaks if the
  assumption is wrong.
- **flush-left `## Design` section in the spec** — the suggested default at `scale: wave`, and
  the rung to beat. The design sits beside the requirements it answers, so the whole provenance
  chain reads in one file.
- **standalone design doc** — the suggested default when the design outlives the wave that
  authored it, or when several waves will implement it: an epic-level domain model, a mechanism a
  later wave builds. This is what a `design:` pointer resolves to, so choosing this rung is
  choosing to be pointed at.
- **structured models** — a logical domain model, C4 context/container/component views, sequence
  diagrams — the suggested default when component or integration *topology* is the hard part and
  would hide in prose. Prose describes two components well and five badly; the moment "who calls
  whom, in what order, across which process boundary" takes a paragraph to state, it wants a
  picture instead.
- **full Technical Design Document** — the suggested default at momentous or cross-system scope,
  where the surface is large enough that its decisions no longer fit beside the requirements and
  the design has readers who will never open the spec.

The rungs compose rather than exclude. Structured models most often live *inside* a `## Design`
section or a standalone doc rather than instead of one, and reading the menu as five mutually
exclusive boxes is its common misuse.

**Derivation produces a suggested default, never a selection.** Scale gives the starting rung —
task to paragraph, wave to `## Design` section — and three signals move it up: a design several
waves will implement (standalone doc), topology prose would flatten (add structured models), a
cross-system surface with its own readership (full Technical Design Document). One signal moves
it down: a wave whose design is one decision wide gets a short section, not a doc. Print the
result in the frame with the one-line reason it was derived; the user moves it up, moves it down,
or lets it stand. The menu suggests, and that is all it does.

**Nothing enforces the rung, deliberately.** The three-way wall already accepts every one of
them — in place as a `## Design` section, or by pointer to whatever the standalone form produced
— so form selection cannot fail a gate and was never going to. It is guidance approved in
conversation, and the whole cost of getting it wrong is a design in a shape that does not fit
its readers.

### The ownership table

The table is the load-bearing row of the whole section, and the only part later steps consume
mechanically: the `structure` checks `reuse` and `one-site` anchor on the owner column, and the
agreement-test column is what the `structure` reader reads back. Shape:

```
| concept | owning module (SSoT) | reuses | rendering surfaces | agreement test |
|---|---|---|---|---|
| version pin value | `payload/scripts/lib/walls.sh`'s `SUPPORTED_SDLC_VERSION` (the commit gate behind `hooks/bash-walls.sh`) | none fits: no other file holds a version constant | both hooks · this file's version history · the two SVG diagrams | `tests/cross-gate-agreement.test.sh` §V pins all five renderings against the gate's value, with a mutation arm |
| agreement-test duty + authoring rules | `agents-src/blocks/checks-structure.md` (`one-site`) | the render markers of `agents-src/render.sh` | payload/context/checks-structure.md · this section | `bash agents-src/render.sh --check` holds the rendered file to its block; this section is the unpinned one |
```

- **The `reuses` cell names the existing site the design reuses, or `none fits: <why>`.** Empty is
  a finding: the design never looked. A writer's `reuse:` report line answers the same question
  for each site the build added.
- **One row per concept rendered at more than one surface.** A concept that exists in exactly
  one place has nothing to disagree with itself about, and listing it is padding. The table is a
  duplication ledger, not an inventory of the change.
- **The owner is a place, not a layer or a role.** "the governing-skill hook" is an owner; "the
  backend" is not. If you cannot name a file, a function, or a single named constant, the concept
  does not have an owner yet — and that is the finding. Write it down instead of inventing one.
- **Rendering surfaces include prose.** A constant read by two scripts and quoted in a doc has
  three surfaces, and the doc is the one that drifts, because nothing runs it.
- **The agreement test is a real hermetic test that fails when the surfaces disagree** — named,
  not a suite and not "covered by the unit tests". The standing exemplar is the
  `SUPPORTED_SDLC_VERSION` pin in `tests/cross-gate-agreement.test.sh` §V (epic-21 wave-02
  S12): one logical constant, five rendering sites — the two hooks, this file's own
  version-history bullet, and both diagram SVGs — held against the evidence gate as origin,
  with a mutation arm. It replaced a narrower exemplar that pinned only the two hooks
  (`tests/scripts.test.sh`, retired epic-18 W3) and left the prose and diagram sites to drift
  silently — which was, for a while, exactly the honest-limit case this cell exists to
  document, and is the half worth knowing while you write one: name what a tuple leaves out
  rather than rounding up to "pinned". The general move that closed it: a surface becomes
  pinnable by changing its format (composing the diagrams as SVG made their version
  renderings greppable) or by naming it in the same agreement test as the origin, not by
  promising to remember it. `none — <why>`
  is a legitimate cell — some pairs are prose against prose, and a mandate dispatched verbatim
  has no seam to test — but it is a cell the reviewer will stop on, so give it the reason.

### The Eval design table

`## Eval design` sits beside `## Design` in a wave-or-epic spec, one row per acceptance
criterion. SKILL.md carries the contract — the six columns, the type ladder, the rule that an
eval with no nameable "Fails when" is refused at the card. This is how to fill one in.

- **Approach is one line, and it is a design decision.** "Grep the rendered file for the six
  column headers" is an approach; "test it" is not. It names the seam the eval reaches through,
  which is exactly why the table is authored at Step 2 and not at Step 3: the architecture has
  just decided what is observable, and an approach written before that is a guess about a shape
  nobody has chosen yet.
- **Eval type is the ladder in words** — static · unit · hermetic · live · human, T0–T4. Words
  rather than tier codes because the Step-2 card counts types per requirement and a user
  reading `T0 T0 T2` learns nothing they can push back on. The tier code still travels into the
  plan's matrix, which is machine-read; this column is the one a person approves.
- **Eval is `command → expected observation`,** both halves. A command with no expected
  observation is a thing you ran, not an eval — the reader cannot tell a pass from a crash — and
  an observation with no command is a hope. The observation is what the terminal shows, not the
  conclusion you would draw: `rc=2, stderr names AC-K2.3`, never `the wall works`.
- **Fails when names a PLANTED DEFECT, singular and specific.** "the code is broken" fails the
  column; "the `fails-when:` line is deleted from one AC block" passes it, because a writer can
  go and do that and watch the eval turn red. It is the sentence the writer implements first —
  red on that exact mutation — before any of the code the eval is for.
- **A criterion that admits no "Fails when" goes back to Step 1.** That is the loop the column
  exists to close, and it closes upward: the defect is in the criterion's wording, not in the
  eval, and rewriting the eval around an unfalsifiable criterion buys a green that means
  nothing. Step 1's quality bar — write each criterion so a "fails when" is nameable — is this
  rule paid for early, where it is cheap.
- **One row per criterion, and the plan renders them.** Step 3 adds sequencing (which task
  implements which eval, in what order) and the matrix's bookkeeping columns. It authors no eval
  of its own, and a matrix row with no row here is a criterion that skipped a step.
- **The gate reads the rendered column.** From `current: 4` on, an AC block whose `fails-when:`
  is missing or empty refuses the commit, naming the row. A waiver does not excuse it: a waiver
  dissolves the obligation to RUN an eval, never the obligation to have designed one.

## Close-out report (Step 9)

SKILL.md carries the terminal-disposition rule and names the report's ten parts; this is the
authoring detail — what each part is for, and the bound that keeps the whole thing from
growing back into ceremony.

The rule itself is not restated here. It lives once, in `agents-src/blocks/terminal-disposition.md`,
and is rendered into `SKILL.md` §Step 9 — read it there. A second copy in this file was the
duplicate wave-02 removed (spec AC-6).

**The report is one turn.** Not a document, not a file the user has to open — it is the
close-out message itself, sent once, at Step 9. A close-out that spans multiple turns or
defers its verdict to a linked artifact has already become the ceremony the rule exists to
forbid.

**Ten parts, plain English, at the altitude of decisions:**

- **Goal** — what this run set out to do, in one sentence.
- **Accomplished** — what shipped, named plainly.
- **Deferred, with dispositions** — every finding that did not ship, each carrying its
  terminal disposition: DO-NOW (folded in already, so this list should hold none of them),
  ACCEPT-CLOSED (won't-fix, with the one-line reason), or PROMOTE (its trigger event or its
  chartered home, named). A finding with no disposition is the defect this template exists
  to catch.
- **Special attention** — anything the reader should look at closely before trusting the
  rest of the report.
- **Material risks** — what could still go wrong, named, not hedged.
- **Challenges** — what made this run harder than the plan assumed.
- **Decisions** — the calls made along the way that a later reader would want to know were
  made on purpose.
- **Success/failure verdict** — one plain sentence: did this run meet its goal.
- **Learnings** — what this run taught that the next one should carry forward.
- **Next** — the immediate next action, named.

**The anti-ceremony bound.** The whole report is readable in the time it takes to read this
paragraph twice. A per-AC breakdown, a restated Verification Matrix, a section for every
step's evidence, or a sub-heading per finding are all the same failure — institutional
confirmation dressed up as an audit. If a part has nothing to say, it gets one clause ("no
material risks") rather than a heading with nothing under it. Plain English means no jargon a
plain reader would have to look up, and conceptual altitude means decisions and outcomes, not
diffs, commands, or file paths.

**The debt the continuation carries (wave-30 T22; AC-11.2).** Debt is paid by the next row that
touches it, not at close, so close-out carries every unburned item of the run's debt ledger into
the continuation's `## Deferrals`, after the `deferred:` lines, one line each:
`debt: <concept> <kind> "<sites>" touches=<N> raised-by=<record> from=<wave name>`. A burned item
is not carried. Into a continuation that already exists the lines are merged as the deferrals are,
each once.
The next run's Step 1 adopts them: right after its card it runs `session-poker.sh debt adopt <newest continuation>`.

**Archiving a closed run (epic-22 wave-01, REQ-C; ADR-003).** Two config keys in
`.bionic/config.yaml`, read by `payload/scripts/lib/roots.sh` and `archive.sh`, sit beside
`docs-root:` and `rigor-floor:` above: `archive-root:` (default `$HOME/bionic-archive`) names
where a closed run's directory goes; `archive-on-close:` (default `true`; `false` opts a
project out entirely) governs whether Step 9 moves anything at all. The move itself —
`specs:`/`plans:`/`adrs:` for one epic slug, to `<archive-root>/<project>/.bionic/<same
relative path>`, never `record:` — is `archive_run`'s contract, documented at its own
definition in `payload/scripts/lib/archive.sh`; SKILL.md §Step 9 names the call and the
`archived:` evidence line it produces.

**The released version (`release:`, wave-27 T4).** An optional plan frontmatter field,
`release: <version>`, names what the run released. `close-out.sh` writes it into the Step 9
`delivered:` line, the epic row's version cell and the continuation header. With no field, no
version is written in any of them: the epic cell reads `—`. The installed tool's own version is
never used for the release. It stays on `attested-by: close-out.sh <version>`, which names the
tool that performed the tail. Close-out also writes the Step 9 line: a plan reaches Step 8
with no `- Step 9:` line, and the close adds one under the Step-8 block before replacing it with
`delivered:`.

## Debt ledger

Debt is paid by the next change that touches it, not by a user, so it is kept as a ledger and burned when touched. Findings are classed by payment date, not by reader: harm (paid by the user, now), evidence (paid by the claim, now) and debt (paid by the next change). A finding of class debt is a second copy of a concept, an unpinned shared pair or a one-case abstraction; it is rated by its kind and the concept it names on the debt table of `payload/context/severity.md`, never by severity.

**The file.** `<docs-root>/record/<run>/debt.md` holds one line per item, and the records table's `debt ledger` row gives its header and its one writer:

```
concept | kind | sites | raised-by <record> | touches N | burned <row> | —
```

The last cell is `—` while the item is open and `burned <row>` once a row has burned it.

**Burn when touched.** A debt finding's disposition is burn-when-touched, never fix now and never note. The orchestrator records it at the Step-6 disposition, and the next row whose `Files:` touch the item's concept burns it inside its own work, or says why not.

**The touch counter.** A brief whose `Files:` touch an item's concept adds one to its `touches`; the item with the highest count burns first. An item nobody touches costs nothing and stays at zero, so the release card prints touches and burns, never the ledger's length: `debt: touched N · burned M`.

**The verbs.** `session-poker.sh debt` is the ledger's one writer, and each subcommand takes the plan last, or the session's bound run:

- `session-poker.sh debt add <reading record>` writes a line per debt line of a reading, each concept and kind once.
- `debt touched <concept>` adds one to the touches of each unburned item of the concept; the dispatch wall runs it when a brief's `Files:` cover the item.
- `debt burn <concept> <row>` writes `burned <row>`.
- `debt list` prints the items.
- `debt adopt <continuation>` writes each `debt:` line a previous run's continuation carries into this run's ledger, once, with its touches and `raised-by` kept. Step 1 runs it on the newest continuation right after its card.

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
