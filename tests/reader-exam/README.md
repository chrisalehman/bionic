# The reader exam

Readers (the auditor, the critic, the reviewer) are held to the checks files they are handed
at start: `payload/context/checks-evidence.md`, `checks-adversarial.md` and
`checks-structure.md`. The exam asks whether a reader holding those files catches defects
that really got past a reader, and does not fail a change that has none (spec D11 of
wave-27; design ledger Δ4).

It is the one check that needs a live model, so it is not in the hermetic suite. What the
suite holds it to is `tests/reader-exam.test.sh`: the latest sitting in `sittings.md` names
each checks file with its sha256, and the suite is red when a shipped checks file no longer
has that hash. Change a checks file, and the exam must be sat again before the tree is green.

## What is here

- `samples/<name>/`: one sample each.
  - `tree/` is a small project before a change; `change.patch` is the change.
  - `expect.txt` is the answer key, three lines:
    `question: <q>` (the question the sample is dealt; `clean` lists all three),
    `result: <pass|flag|fail>` (what the reader must reach), and
    `token: <string>` (one string the reader's record must contain).
- `materialize.sh <sample dir> <dest>`: builds the repository a reader is given and prints its
  range `<a>..<b>`. The key does not travel into it.
- `sittings.md`: every sitting, newest last.

## The samples

Each is rebuilt small from a defect wave-26 shipped past a reader, in a made-up project. The
records named are under `.bionic/docs/record/wave-26-never-idle/`.

| sample | question | key | rebuilt from |
|---|---|---|---|
| `dup-counter` | structure | `fail`, `check: reuse FAIL` | `review.md` (final review): the duplication FLAG, "three dirty-tree counters", and its ownership row for the run stamp, where the stamp writer computed the dirty count again instead of using the one the land reads, and computed it differently |
| `dup-helper-no-table` | structure | `fail`, `check: reuse FAIL` | `review.md`: "two copies of the proof line's `at=` reader" beside the one reader of the proof line. Rebuilt at task scale, with no design and so no ownership table, so the reader has to search |
| `admit-not-require` | evidence | `fail`, `REFUTED` | `auditor.md` §1b item 1, AC-3.4 REFUTED: the requirement said a full run "is required", the design and its test only showed one is admitted, and the land took the tree with none |
| `red-then-green` | adversarial | `fail`, `land_check` | `critic.md` F1: the landing check read only the last stamp, while the doctrine makes one call per suite, so a red suite followed by a green one at the same head landed |
| `clean` | all three | not `fail`, `branch-name` | no defect: a small change that reuses what exists, with its spec, design table, matrix and evidence in order |

## Sitting the exam

1. **Hash the checks files that will be sat.** `shasum -a 256 payload/context/checks-evidence.md
   payload/context/checks-adversarial.md payload/context/checks-structure.md`. The readers must
   be the built roles, carrying exactly these files.
2. **Materialize each sample** outside this repository, under a name that says nothing:
   `bash tests/reader-exam/materialize.sh tests/reader-exam/samples/<name> <scratch>/exam-<n>`.
   Keep the printed range.
3. **Dispatch the readers** through the ordinary dispatch path, one dispatch per sample and
   question:
   - the role the audited dealing gives the sample's question: the auditor for `evidence`, the
     critic for `adversarial`, the reviewer for `structure`;
   - and the one-mind case, the critic holding all three questions, on every sample.

   For `clean`, each of the three roles takes its own question, and the critic takes all three.
   The brief carries `Questions: <q>` on a line of its own (`Questions: evidence, adversarial,
   structure` for the one-mind case), names the repository and its range as the code to read
   (its `docs/` holds the spec, plan and writers' records), and gives a record path per
   question under `record/<wave>/` with a neutral name. It says nothing about an exam, the
   sample's name, or what to look for. A reader that cannot write files returns its record,
   and the orchestrator saves it unchanged.
4. **Score each record** against the key. A record is scored on the key's question; on
   `clean`, on each of the three. It is **met** when both hold:
   - its flush-left `result:` line equals the key's result. On `clean` the bar is not failing:
     `pass` or `flag` is met, and `fail` is missed;
   - `grep -F -- '<token>' <record>` finds the token.

   A reader passes the exam when every record it wrote is met.
5. **Record the sitting** by appending a section to `sittings.md`:

   ```
   ## <YYYY-MM-DD> — <who sat it, and why>

   sha256 payload/context/checks-evidence.md <hash>
   sha256 payload/context/checks-adversarial.md <hash>
   sha256 payload/context/checks-structure.md <hash>

   result <sample> <question> <role> <reached result> <met|missed> <record path>
   ```

   one `result` line per sample, question and role. The `sha256` lines are the hashes from
   step 1, the files the readers actually held.
6. **A miss is sent back.** A reader that misses a sample sends its checks file to a fix row.
   When the fixed file lands its hash changes, the suite goes red, and the exam is sat again.

The first sitting is owed by wave-27 T22. Until it is recorded, `sittings.md` holds the one line
`first-sitting: owed by wave-27 T22`, and the suite passes on a single row labelled
"RE-AUTHORED BY T22". The sitting that replaces that line also removes that row's arm from
`tests/reader-exam.test.sh`.

## Adding a sample

A defect that got past a reader becomes a sample before the wave that found it closes
(`.claude/rules/reader-exam.md`). Build it small and self-contained, in shell, faithful to the
real defect, and with nothing in a comment or a file name that gives the defect away. Its row
above names the record it came from. `bash tests/reader-exam.test.sh` checks the key's shape
and that the sample materializes. Give a sample's own libraries basenames no bionic library
has: `tests/lib/impact.sh` matches a sourced library by its basename in every `lib/`
directory, so a sample's `lib/proof.sh` would tie it to every suite that runs a hook sourcing
bionic's. `bash tests/lib/impact.sh <the sample's files>` should answer only this suite and
the suites that name `tests/` whole.
