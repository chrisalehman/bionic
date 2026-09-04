# The admission rule — DRAFT for reaction

**Status: prototype.** Written 2026-09-03 for wayfinder ticket #26 "The admission rule, drafted"
(map #19). This is text to react to, not a ratified rule. Its ratified form lives in the v1 spec
set (#27); this file is deleted when that lands. Vocabulary: `design/domain-dictionary.md`.

---

## 0. What the rule is for

The v1 spec is a list of statements about bionic, each of which is either **certified** for an
interpreter or visibly **not yet**. The admission rule is the filter at the door: it says what a
statement must carry to enter the spec at all, what counts as evidence for it, and what happens to
a statement that cannot yet be evidenced. It exists because the epic-20 record shows every way a
spec fills with claims nobody can check: seats describing their own conduct, scorecards without the
script that produced them, line anchors retyped by hand, criteria quantified over cells no
instrument produces, and records under a path that has no history.

The rule has one sentence and eight clauses that make the sentence operable.

> **A statement enters the spec only with the surface that proves it and the measurement that
> would falsify it. Everything else is fog.**

---

## 1. The row

Every statement in the spec is one row of the statement index. A row that lacks any field below
is not a row; it is fog (§6).

| field | what it holds | rejected if |
|---|---|---|
| **statement** | one declarative sentence about bionic's conduct or shape, in canon vocabulary | it names a mechanism instead of a behaviour ("the hook exits 2" is not a statement; "a seat cannot commit to main" is) |
| **proving surface** | the class of primary surface (§2) from which the statement's truth is read | the surface does not exist yet (→ fog, §6.2), or it is self-report (§2.3) |
| **falsifying measurement** | the act that would make the statement read *false* on that surface, stated so a stranger could perform it | no act is named, or the act cannot fail ("observe that it works") |
| **unit** | what one measurement produces (a cell, a row, a transcript line) and how many the instrument produces | the statement quantifies over more units than the instrument produces (§7.2) |
| **control** | the act that shows the instrument can tell true from false (§3) | absent, or the control and the measurement are the same act |
| **status × interpreter** | one status (§5) per interpreter, each with its evidence pointer | any status without a pointer, or a pointer that does not resolve (§2.4) |

The **statement** is the canon's; the other fields are the spec's. A statement changes only in the
canon; a row's evidence changes only by a new measurement.

---

## 2. Primary surface

### 2.1 Definition

A primary surface is a place where the statement's truth can be read **without trusting anyone's
account of it**: the reader can go there and see for themselves, and what they see was produced by
the act under measurement, not by a description of it.

### 2.2 Admissible classes

| class | example | the reader can |
|---|---|---|
| **file on disk in a tracked tree** | a rendered role file, a plan's frontmatter, a hook's exit code captured to a log under a tracked path | diff it, blame it, rebuild it |
| **transcript line** | a seat's session record at a line, a tool call and its result | quote it verbatim, count it |
| **item / event store entry** | omnigent's item store, a hook payload the runtime delivered | query it, compare across seats |
| **captured output beside its script** | a scorecard log **and** the command that produced it, both in the record | re-run the script and compare |
| **tracker record** | an issue state, a comment, a label, with its timestamp | fetch it by id |
| **built artifact + its build** | an interpreter as shipped, and the build that reproduces it | rebuild and compare byte-for-byte |

### 2.3 Inadmissible — self-report and its cousins

- **A seat's account of its own conduct.** "I refused the dispatch" in a seat's output is not
  evidence the dispatch was refused. Read the refusal from the item store or the transcript line
  where it happened (A-W5-175/178).
- **A number without its producer.** A scorecard, a count, a ratio whose script is not beside it
  in the record. The W5 effectiveness scorecard is eighteen lines of output and no script; its
  numbers were re-derivable, and it is still inadmissible, because *re-derivable* is the reader's
  labour and *reproducible* is the record's.
- **A description quoting a primary surface.** A slice report that says "the log shows 44/44" is
  a pointer, not a surface. Admissible only when the pointer resolves (§2.4); the surface is the
  log, the report is not.
- **A hand-transcribed fixture.** A test fixture typed from a research note is a proxy until it is
  replaced by a captured artifact. The W1 Codex payload fixture was one field short for that
  reason.

### 2.4 Pointers

An evidence pointer names a surface and a location in it: a path and a line, an id, a commit and
a tree. **A pointer that does not resolve is absent evidence, not weak evidence.** Three W5
records cite line numbers that hold unrelated content; every count they reported was right, and
each pointer is still absent. Anchors are copied from the surface, never typed.

### 2.5 Surfaces that cannot be diffed

A record under a gitignored path has no history: every W5 commit that "recorded" a decision is an
empty tree. bionic's standing decision keeps `.bionic/` out of git, so the rule does not demand
otherwise. It demands instead:

- Anything the spec **cites as evidence** lives where it can be diffed: a tracked path, a tracker
  record, or a captured artifact with its hash recorded in a tracked place.
- A document that lives only under a gitignored path may be *pointed at* for context, never
  *cited* as evidence.
- A test whose inputs live under a gitignored path cannot certify anything, because a fresh clone
  cannot run it (`tests/rules.test.sh` arm (e)).

---

## 3. The control

### 3.1 What a control is

A control is the act that shows the instrument can tell a true statement from a false one. Without
it a wall that refuses everything reads as a wall that holds. Two controls are required for a
conduct statement:

- **The compliant twin.** The same act performed in a way the statement permits. The instrument
  must *allow* it. A wall that refuses its compliant twin is an instrument failure, scored as
  such and never as a hold (the `resume-before-dispatch` control refused on both live tables).
- **The bare seat.** The same model, the same task, launched without bionic (AC-2 "Option 1",
  A-W5-178). The bare seat shows what the model does unaided, so a "hold" is attributable to
  bionic and not to the model's disposition. Read from primary surfaces on both seats.

### 3.2 Reporting

**Walls-held and controls-failed are reported as separate counts, always.** A control failure is
an instrument defect; it is never summed into a REFUSED total. The W5 headline "20/32 REFUSED"
counted three control failures as holds; the admissible statement of the same data is "17 walls
held, 3 controls failed, 12 cells not refused."

### 3.3 Controls for shape statements

A statement about the *thing* rather than its *conduct* (rung zero's "one source, one whole") has a
control too: a deliberate defect the measurement must catch. For reproduction, the control is a
single hand edit to a rendering; the rebuild must fail to match.

---

## 4. Guards and certificates

A row's evidence is one of two kinds, and the kinds never share a cell.

| | guard | certificate |
|---|---|---|
| **claims** | this change broke nothing | this interpreter honours this statement in reality |
| **runs** | on every change, anywhere, unconditionally | deliberately, as a climb |
| **needs** | nothing but the repository | the real runtime at a stated version |
| **records** | pass/fail in the gate | a dated record: runtime version, build hash, script, output, pointers |
| **ages** | never | goes stale by design on a runtime bump; the column empties |
| **certifies** | nothing | one cell of one column |

A statement with only guard evidence is **proven (hermetic)**, never **certified**. Certification
requires a certificate cell for that interpreter. The gate refuses to contain a certificate-maker
(a suite that needs a daemon, a login, or a server is not a guard, whatever it is named).

---

## 5. Status

### 5.1 Vocabulary

| status | meaning | may become |
|---|---|---|
| **proven** | a certificate cell holds for this interpreter at a stated version | stale (on bump) → re-measured |
| **proven (hermetic)** | guard evidence only; not certified | proven, when a certificate exists |
| **refuted** | a measurement read the statement false on a primary surface | proven, only by a new measurement reading true |
| **untested** | the surface exists, the measurement is defined, nobody has run it | proven / refuted |
| **in-flight** | a repair is under way against a refuted or untested row; the row keeps its prior status beside the flag | its prior status resolves |
| **fog** | the row cannot be completed (§6) | a row, when its missing field can be filled |

### 5.2 Rules

- **Refuted is a status, not fog.** A refuted statement has a surface and a measurement; it is a
  complete row that read false. It is never downgraded to fog, never deleted to tidy a rung, and
  never re-worded so the measurement no longer reaches the failure.
- **Refuted holds the rung.** A rung is not admitted for an interpreter while any statement
  beneath it reads refuted for that interpreter. Repairs are built when the rung is climbed.
- **Inherited claims cross with their status.** A statement measured in a prior lineage enters the
  index with the status it earned there, its pointer, and the runtime version it was earned on.
  Work items never cross; only claims with status (Notes §8 of the map).
- **"Proven with caveat" is not a status.** The caveat is either a second statement (untested or
  refuted in its own right) or it is a note. Split it.
- **A status names its interpreter and version.** "Proven" alone is not a status; "proven on
  omnigent 0.11.0 @ 48c99f7" is. Every proven row in the epic-20 ledger is 0.11.0; none is
  proven on 0.12.0.

---

## 6. Fog

### 6.1 What fog is

Fog is a statement the spec wants to make and cannot yet row. It is recorded in the spec's **Not
yet specified** section, never as a row with empty cells and never as a row whose measurement is
"to be defined."

### 6.2 The three fog conditions

1. **No surface.** The statement's truth has nowhere to be read. SC-1 clause 3 quantified over 28
   role × wall cells; the drill produces 8. Twenty cells have no surface → the clause is fog until
   the instrument produces them **or the statement is re-quantified over the eight** (§7.2).
2. **No falsifier.** Nobody can say what would make it read false.
3. **No producer.** The statement names a behaviour nothing produces (SC-4's WARN: the design
   describes a written WARN; nothing writes one). Fog until the producer is built.

### 6.3 What a fog entry carries

The statement as wanted; which of the three conditions holds; **what would have to exist** for it
to become a row (the instrument, the surface, the producer). A fog entry with no "what would have
to exist" is a wish, and is struck.

---

## 7. Counting and quantifying

1. **One row, one claim.** A criterion with clauses is split, one row per clause, each with its
   own status (SC-1 has three clauses at three statuses).
2. **Quantify over the instrument's unit.** A statement may claim only as many units as its
   instrument produces. "All 28 cells" against an 8-cell drill is fog for 20 and a claim for 8;
   write the claim for 8.
3. **Absence is a claim.** "No native spawn occurred" is admissible only with the surface that
   would have shown one (the transcript search, the item-store query) and its empty result.
4. **A vacuous pass is not a pass.** "RETIRE demonstrated live" with zero RETIREs certifies
   nothing; the row is untested.
5. **Regression totals are guards.** "44/44" at a commit says the guards held at that commit. It
   is not a certificate for any row and is never cited as one.

---

## 8. Worked examples from the ledger

| ledger row | verdict under this rule | why |
|---|---|---|
| every policy DENIES its planted violation and ALLOWS the clean twin, with mutation power (W1 AC-9) | **admit: proven (hermetic), omnigent 0.11.0** | script beside numbers (`drill-green11.md:97-99`), mutation control present (`17/17 → 4/17`), tracked path |
| an audited run: Claude orchestrating, Codex working, 23 dispatches, zero native spawns (rung 5) | **admit: proven, omnigent 0.11.0, one climb** | item-store readback for dispatches; absence claim carries its search; bare-seat control run (AC-2) |
| the W5 effectiveness scorecard headline | **reject as cited; re-admit only with the script** | eighteen lines of output, no producer; §2.3 |
| SC-1 clause 3 (28 role × wall cells) | **fog (no surface) for 20; row for 8** | §6.2 / §7.2 |
| "20/32 REFUSED" | **restate: 17 held, 3 controls failed** | §3.2 |
| `merge-check-6d22852.md` Log Line column | **pointers absent; counts unverified until re-anchored** | §2.4 |
| SC-4 reviewer fallback WARN | **fog (no producer)** | §6.2 |
| `tests/rules.test.sh` arm (e) | **cannot certify; a guard at most, and only once its input is tracked** | §2.5 |
| protect-main ALLOWED on the sonnet implementor seat (rung 4) | **admit: refuted, omnigent 0.11.0; holds rung 4 on omnigent** | §5.2 |
| W1 AC-13 support table, surviving only as a copy in `drill-green11.md:120-153` | **admit as proven (hermetic) at 0.11.0 only if the copy's hash is recorded in a tracked place; else pointer absent** | §2.5 |

---

## 9. Questions this draft leaves for reaction

1. **Two controls or one?** §3.1 requires both the compliant twin and the bare seat for every
   conduct statement. The bare seat doubles the cost of a climb. Alternative: bare seat once per
   rung, twin once per cell.
2. **Where certificates live.** §2.5 says cited evidence must be diffable, and `.bionic/` stays
   out of git. The draft's answer is "a tracked path or a hash recorded in a tracked place." That
   is a new tracked directory for climb records. Is that the right trade, or does the record stay
   machine-local with hashes only?
3. **Does the rule govern the SDLC's own matrix?** The T0–T4 tier ladder measures evidence
   fidelity for a slice; this rule measures admissibility for a spec statement. They are
   different instruments. The draft keeps them apart and lets a T3 row feed a certificate cell
   only if it also satisfies §2–§3. Confirm, or fold.
4. **Inherited "proven" rows: admitted as proven, or as untested-at-current-version?** §5.2 admits
   them with their earned status *and* version. Since nothing has run on 0.12.0, every inherited
   proven row is stale on arrival. The draft says: admitted proven @ 0.11.0, stale, re-climb
   required before any v1 rung certifies. Confirm.
