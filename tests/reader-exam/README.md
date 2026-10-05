# The reader exam

Readers (the auditor, the critic, the reviewer) are held to the checks files they are handed
at start: `payload/context/checks-evidence.md`, `checks-adversarial.md` and
`checks-structure.md`. The exam asks whether a reader holding those files catches defects
that really got past a reader, and does not fail a change that has none (spec D11 of
wave-27; design ledger Δ4).

It is the one check that needs a live model, so it is not in the hermetic suite. What the
suite holds it to is `tests/reader-exam.test.sh`: the latest sitting in `sittings.md` names
each checks file with its sha256 and carries a `met` result for every sample, each reaching
what its key asks. The suite is red when a shipped checks file no longer has that hash, or
when the latest sitting left a sample unsat or missed. Change a checks file, and the exam must
be sat again before the tree is green.

## What is here

- `samples/<name>/`: one sample each.
  - `tree/` is a small project before a change; `change.patch` is the change.
  - `expect.txt` is the answer key:
    `question: <q>` (the question the sample is dealt; `clean` lists all three),
    `result: <pass|flag|fail>` (what the reader must reach),
    `token: <string>` (a string the reader's record must contain), and, on every sample but
    `clean`, `names: <identifier>` (an identifier the record must also contain, to show it
    named the planted defect and did not reach the result for another reason). A `token:` or
    `names:` line may hold alternatives separated by ` | `, any one of which meets it: the
    spellings a finder writes for the same thing.
- `score.sh`: `exam_score <expect.txt> <record>` prints `met` or `missed`. Sourced, it defines
  its functions and runs nothing. It is step 5 below, and the suite holds the real keys to it.
- `materialize.sh <sample dir> <dest>`: builds the repository a reader is given, with an empty
  `.bionic/` of its own, and prints its range `<a>..<b>`. The key does not travel into it,
  and a `<dest>` whose path, as written or resolved, names the sample in any case is refused.
- `sittings.md`: every sitting, newest last. The suite reads the last one in the file.

## The samples

Each is rebuilt small from a defect wave-26 shipped past a reader, in a made-up project. The
records named are under `.bionic/docs/record/wave-26-never-idle/`.

| sample | question | key | rebuilt from |
|---|---|---|---|
| `dup-counter` | structure | `fail`, `check: reuse FAIL` or `check: one-site FAIL`, names `tree_dirty_count` | `review.md` (final review): the duplication FLAG, "three dirty-tree counters", and its ownership row for the run stamp, where the stamp writer computed the dirty count again instead of using the one the land reads, and computed it differently |
| `dup-helper-no-table` | structure | `fail`, `check: reuse FAIL`, names `proof_field` | `review.md`: "two copies of the proof line's `at=` reader" beside the one reader of the proof line. Rebuilt at task scale, with no design and so no ownership table, so the reader has to search |
| `admit-not-require` | evidence | `fail`, `REFUTED`, names `land.sh` | `auditor.md` §1b item 1, AC-3.4 REFUTED: the requirement said a full run "is required", the design and its test only showed one is admitted, and the land took the tree with none |
| `red-then-green` | adversarial | `fail`, `land_check`, names `tail -n 1`, `tail -n1` or `tail -1` | `critic.md` F1: the landing check read only the last stamp, while the doctrine makes one call per suite, so a red suite followed by a green one at the same head landed |
| `clean` | all three | not `fail`, `branch-name` | no defect: a small change that reuses what exists, with its spec, design table, matrix and evidence in order |

## Sitting the exam

A sitting is run by the orchestrator of a wave in this checkout; that wave is **the sitting's
wave** (wave-27's first sitting is `wave-27-review-across-rigor`). Its readers never run in
this checkout: its working directory holds every key and this README, so a reader dispatched
here can read the answers. Each sample is sat in a session of its own whose project is the
built sample, outside this checkout, with a copy of this checkout's plugin loaded by
`--plugin-dir`.

1. **Copy the plugin and hash the checks files that will be sat.** At the head of this
   checkout the sitting is for, copy its `payload/` under the machine's temporary directory,
   following its links, and hash the copy's checks files:
   `PLUGIN="$(mktemp -d)/plugin" && cp -RL payload "$PLUGIN" && shasum -a 256
   "$PLUGIN/context/checks-evidence.md" "$PLUGIN/context/checks-adversarial.md"
   "$PLUGIN/context/checks-structure.md"`. The copy is what every session loads. It has no
   answer key beside it, which `<this checkout>/payload` has one directory up, and it is not
   the installed plugin's path, so the session cannot resolve the installed plugin in its
   place.
2. **Materialize each sample** outside this checkout, under a path that says nothing:
   `bash tests/reader-exam/materialize.sh tests/reader-exam/samples/<name> <dest>`, where
   `<dest>` is a new directory under the machine's temporary directory, for example
   `"$(mktemp -d)/s1"`. `materialize.sh` refuses a `<dest>` whose path names the sample. Keep
   the printed range, and note which `<dest>` holds which sample: the readers see only
   `<dest>`.
3. **Open an engaged session on the built sample.** `cd <dest> && claude --plugin-dir
   "$PLUGIN"`. The session's project is the built sample, so the readers' working directory,
   records and searches stay inside it. The built sample carries its own `.bionic/`, so it is
   a bionic root, and the session's first act is `/bionic:canonical-sdlc`, so it is engaged.
   bionic's start push reaches only the readers of an engaged session in a bionic root.
   **The first thing a sitting checks** is that this worked: a reader dispatched there holds
   the pushed files, and its role is the copy's, not the installed plugin's. A sitting whose
   readers held no checks files is not recorded.
   - **Loading the built roles.** *Written by wave-27 T22, once T15 lands: how the session
     gets the roles this checkout builds rather than the installed ones, and how that is
     shown.*
4. **Dispatch the readers** in that session, through the ordinary dispatch path, one dispatch
   per sample and question:
   - the role the audited dealing gives the sample's question (`facts_owed audited wave` in
     `payload/scripts/lib/proof.sh`): the auditor for `evidence`, the critic for
     `adversarial`, the reviewer for `structure`;
   - and the one-mind case, the critic holding all three questions, on every sample.

   For `clean`, each of the three roles takes its own question, and the critic takes all three.
   The brief says nothing about an exam, the sample's name, or what to look for. It carries:
   - `Questions: <q>` on a line of its own (`Questions: evidence, adversarial, structure` for
     the one-mind case);
   - the code to read: the repository (the session's project) and its range `<a>..<b>`; its
     `docs/` holds the spec, plan and writers' records;
   - one record path per question it is dealt, under the record root
     `<dest>/.bionic/docs/record/`, in the directory named for the sitting's wave:
     `<dest>/.bionic/docs/record/<wave>/<label>-<role>-<question>.md`, where `<label>` is
     the last component of `<dest>` (`s1`), never the sample's name; the orchestrator maps
     the label back to its sample when it keeps the record (step 6). The one-mind critic gets
     three paths, for example `…/wave-27-review-across-rigor/s1-critic-evidence.md`,
     `…/s1-critic-adversarial.md` and `…/s1-critic-structure.md`, and writes each question's
     pass to its own path;
   - `Suites:` naming each `tests/*.test.sh` of the built repository, one per suite (for
     example `Suites: tests/land.test.sh, tests/stamp.test.sh`), so a reader can re-execute
     the writers' evidence;
   - `Re-executes: none`.

   A reader that cannot write files returns its records, and the orchestrator saves each
   unchanged at its path. No reader can dispatch a test-runner, so the evidence reader's
   revert-and-watch cannot be done: it will say so, likely as UNVERIFIABLE. That is a `flag`,
   which meets `clean` and does not change a defect sample's `fail`.
   - **Checking what the readers held.** *Written by wave-27 T22, once T15 lands: how the
     checks files pushed to each reader at start are shown to equal the hashes from step 1.*
5. **Score each record** on the key's question: the record at that question's path (on
   `clean`, the record at each of the three). In this checkout:

   ```
   . tests/reader-exam/score.sh
   exam_score tests/reader-exam/samples/<name>/expect.txt <record>
   ```

   It prints `met` or `missed`. A reader passes the exam when every record it wrote is met.
6. **Keep the records.** Copy each record unchanged into the sitting's wave record in this
   checkout, `.bionic/docs/record/<the sitting's wave>/exam-sitting.md`, under a heading per
   record that names the sample, the role and the question.
7. **Record the sitting** by appending a section to `sittings.md`, below every earlier one:

   ```
   ## <YYYY-MM-DD> — <who sat it, and why>

   sha256 payload/context/checks-evidence.md <hash>
   sha256 payload/context/checks-adversarial.md <hash>
   sha256 payload/context/checks-structure.md <hash>

   result <sample> <question> <role> <reached result> <met|missed> <record heading>
   ```

   one `result` line per sample, question and role, `<sample>` being the sample's name; the
   record heading names the record's section in `exam-sitting.md`. The `sha256` lines are the
   hashes from step 1. A line opening with `##` that is not a header of that form is red
   wherever it is in the file. The suite reads the last section, by file order: it is red
   unless that section's hashes match the shipped files, every sample has a `result` line and
   no other name has one, every `result` line reads `met`, no two lines for one sample and
   question disagree, and every reached result is one its sample's key admits.
8. **A miss is sent back.** A reader that misses a sample sends its checks file to a fix row.
   The sitting is recorded as it went, so the suite is red from then until the fixed file is
   sat again and that sitting is appended below it.

The first sitting is owed by wave-27 T22. Until it is recorded, `sittings.md` holds the one line
`first-sitting: owed by wave-27 T22`, and the suite passes on a single row labelled
"RE-AUTHORED BY T22". The sitting that replaces that line also removes that row's arm from
`tests/reader-exam.test.sh`.

## Adding a sample

A defect that got past a reader becomes a sample before the wave that found it closes
(`.claude/rules/reader-exam.md`). Build it small and self-contained, in shell, faithful to the
real defect, and with nothing in a comment or a file name that gives the defect away. Its row
above names the record it came from. Its key's `names:` identifier names the planted defect
or the owner it bypasses, and is in as few files of the built tree as can be: an identifier
that every file of the change carries is found by any record and shows nothing, and so is a
word of the criterion's own sentence, which a reader quotes whatever its verdict. Prefer the
owner the change should have gone through, which no line of the change holds. An identifier
may sit in a context line of the patch only when no added or removed line holds it and the
owner has no other name; the key's author logs it (`admit-not-require`'s `land.sh` is in the
context line `bin/land.sh tests/land.test.sh`). Where a finder spells the same thing more
than one way, the `names:` line lists the spellings as alternatives. ` | ` is the separator
on that line, so an identifier cannot itself hold ` | `. `bash tests/reader-exam.test.sh`
checks the key's shape and that the sample materializes. `tests/lib/impact.sh` does not read
a sample's `lib/` as a library directory, so a sample's libraries may share a bionic
library's basename; `bash tests/lib/impact.sh <the sample's files>` should answer only this
suite and the suites that name `tests/` whole.
