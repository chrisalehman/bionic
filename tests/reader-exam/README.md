# The reader exam

Readers (the auditor, the critic, the reviewer) are held to the checks files they are handed
at start: `payload/context/checks-evidence.md`, `checks-adversarial.md` and
`checks-structure.md`. The exam asks whether a reader holding those files catches defects
that really got past a reader, and does not fail a change that has none (spec D11 of
wave-27; design ledger Δ4). A defect sample is passed only when the reader's record carries a
`finding:` line that names the planted defect's file at a severity and reach the priority table
sends to fix (S1 on, S1 off, S2 on); a record that only describes the defect, or declares it at
a rating the table defers or notes, fails the sample (spec D22 of wave-28).

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
    named the planted defect and did not reach the result for another reason),
    `finding-file: <path>` (the file the record's `finding:` line must name: the planted defect's,
    or the owner it bypasses) and `finding-rating: <S> <reach>` (the ratings that pass it, each
    one the table sends to fix). A `token:`, `names:`, `finding-file:` or `finding-rating:` line
    may hold alternatives separated by ` | `, any one of which meets it: the spellings a finder
    writes for the same thing.
- `score.sh`: `exam_score <expect.txt> <record>` prints `met: declared` (the record declares the
  planted defect; `clean` asks no declaration and prints `met`), or `missed`, which says why when
  the miss is the declaration: `missed: described only`, `missed: declared at <S> <reach>:
  deferred` (or `noted`), `missed: no finding names <file>`, `missed: finding lines refused:
  <why>`. It reads the `finding:` lines through `proof_findings` of
  `payload/scripts/lib/proof.sh`, the reader the registering verb uses. Sourced, it defines its
  functions and runs nothing. It is step 5 below, and the suite holds the real keys to it.
- `materialize.sh <sample dir> <dest>`: builds the repository a reader is given, with an empty
  `.bionic/` of its own, and prints its range `<a>..<b>`. The key does not travel into it,
  and a `<dest>` whose path, as written or resolved, names the sample in any case is refused.
- `run-session.sh <dest> <plugin copy> <prompt file> <output file>` and
  `PLUGIN=<plugin copy> gen-prompt.sh <brief file>...`: the two helpers step 3 names. The first
  starts one session headless, the second writes its prompt, and ends each brief with the files
  its reader is to read, by path in the plugin copy: its checks file for each question it is
  dealt and the severity scale, as shipped.
- `sittings.md`: every sitting, newest last. The suite reads the last one in the file.

## The samples

Each is rebuilt small from a defect wave-26 shipped past a reader, in a made-up project. The
records named are under `.bionic/docs/record/wave-26-never-idle/`. The planted defect is one the
priority table sends to fix at an honest rating (a core function giving a wrong result with no
workaround, `S2 on`); a defect the table would defer or note at any honest rating is no sample.
`dup-helper-no-table` (a second copy of a reader, with the same behaviour as the first) was
retired for that reason at wave-28 T18: a duplicate that agrees with its owner has no functional
effect, which the scale rates S4 and the table notes.

| sample | question | key (each also declares a finding on its file, rated `S1 on`, `S1 off` or `S2 on`) | rebuilt from |
|---|---|---|---|
| `dup-counter` | structure | `fail`, `check: reuse FAIL` or `check: one-site FAIL`, names `tree_dirty_count`, file `bin/stamp.sh` | `review.md` (final review): the duplication FLAG, "three dirty-tree counters", and its ownership row for the run stamp, where the stamp writer computed the dirty count again instead of using the one the land reads, and computed it differently |
| `admit-not-require` | evidence | `fail`, `REFUTED`, names `land.sh`, file `bin/land.sh` or `lib/fullrun.sh` | `auditor.md` §1b item 1, AC-3.4 REFUTED: the requirement said a full run "is required", the design and its test only showed one is admitted, and the land took the tree with none |
| `red-then-green` | adversarial | `fail`, `land_check`, names `tail -n 1`, `tail -n1` or `tail -1`, file `lib/landcheck.sh` | `critic.md` F1: the landing check read only the last stamp, while the doctrine makes one call per suite, so a red suite followed by a green one at the same head landed |
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
   `"$(mktemp -d)/s1"`. `materialize.sh` refuses a `<dest>` whose path names the sample, and
   one that lies inside any worktree of this repository (this checkout, a worktree under it,
   or one elsewhere), since a build there sits beside every answer key. It resolves `<dest>`
   once, links and `..` followed, and builds where that leads; a `.` or `..` among the parts
   of `<dest>` that do not exist yet is refused. It runs itself again at once with
   `PATH=/usr/bin:/bin` and nothing else of the caller's environment, so it finds its
   worktrees with the git in `/usr/bin` or `/bin`: when it lies in a checkout and that
   lookup fails, it refuses, saying so. A copy of it outside any checkout refuses on neither
   ground. Keep the printed range, and note which `<dest>` holds which sample: the readers
   see only `<dest>`.

   Two readers of the same agent type never share a build. On a sample keyed `adversarial`,
   and on `clean`, the critic dealt `adversarial` and the one-mind critic are both
   `bionic:critic`. Started together, two critics with different question sets cannot be told
   apart at start, and neither is pushed a checks file. Started one after the other, the second
   reads the first's record in its own tree. So each of the two gets a build and a session of
   its own. Readers of different types share their sample's build and are dispatched
   together. That makes six builds: `clean` twice (the auditor, the critic and the
   reviewer, then the one-mind critic), `red-then-green` twice, and one for each other sample.
   The first sitting used eight, because step 3's proof took a `clean` build for one reviewer.
3. **Open an engaged session on the built sample.** `cd <dest> && claude --plugin-dir
   "$PLUGIN"`, or, headless as the first sitting ran it, `PLUGIN="$PLUGIN" bash
   tests/reader-exam/gen-prompt.sh <brief file>... > <prompt file>` and then `bash tests/reader-exam/run-session.sh <dest>
   "$PLUGIN" <prompt file> <output file>`. The session's project is the built sample, so the readers' working directory,
   records and searches stay inside it. The built sample carries its own `.bionic/`, so it is
   a bionic root, and the session's first act is `/bionic:canonical-sdlc`, so it is engaged.
   bionic's start push reaches only the readers of an engaged session in a bionic root.
   **The first thing a sitting checks** is that this worked: a reader dispatched there holds
   the pushed files, and its role is the copy's, not the installed plugin's. A sitting whose
   readers held no checks files is not recorded.
   - **The two helpers.** `run-session.sh` starts the session as `cd <dest> && claude -p
     --plugin-dir "$PLUGIN" --output-format json "<prompt>"`, with no other flag and no setting
     that widens what a session may do. It runs the CLI binary and not a shell function of the
     same name, which may add flags. It refuses, before it runs the CLI or writes anything, a
     `<dest>` or an `<output file>` inside any worktree of this repository, an `<output file>`
     inside `<dest>` or one (or its `.err` or `.time`) that exists as anything but a regular
     file, a `PATH` holding any entry that is not an absolute directory (`.`, an empty entry or
     a relative one, whether or not a `claude` is there: the session inherits `PATH`), a `claude`
     that is a file inside `<dest>`, and a fifth argument; inside a checkout whose lookup of its
     worktrees fails, it refuses too. Its own steps run under an environment it makes, with
     `PATH=/usr/bin:/bin` and none of the caller's functions, aliases, `CDPATH` or `BASH_ENV`;
     the caller's `PATH` is read only to find `claude`, and the caller's environment goes to the
     session alone. Each path it is given is resolved once, physically, and used as resolved,
     so the session's working directory and its `--plugin-dir` are physical paths. It clears
     the parent session's identity variables, so the session carries only its own. A session
     or a reader denied a tool is reported to the user and never worked round. It writes
     `<output file>` (the JSON result, which holds the session's id), `<output file>.err` and
     `<output file>.time`. `gen-prompt.sh`, which refuses a
     `PLUGIN` that is not an absolute directory holding the files it names, writes the prompt on
     stdout: `/bionic:canonical-sdlc` first, then an instruction to dispatch each brief
     exactly as written, to the agent type named on its first line, in the foreground, and, on a
     refusal, to stop and never retry; to save any record a reader returned as text, unchanged,
     at the path its brief names; and to reply with each record's path and whether it exists.
     Each `<brief file>` is the line `subagent_type: <agent type>` and then the brief of
     step 4, which is dispatched without that first line and with the generator's closing lines:
     the plugin copy's `context/checks-<q>.md` for each question on its `Questions:` line and
     `context/severity.md`, which every reader is given, the one dealt `evidence` alone included,
     since every reader is asked to declare what it finds as `finding:` lines. The briefs given to one call are the
     readers that share a build (step 2), so the prompt sends them together, in one message;
     `STEP_ZERO=1` has the session quote the agent descriptions first, as below.
   - **Loading the built roles.** `--plugin-dir "$PLUGIN"` loads the copy's roles and hooks in
     place of the installed plugin's for that session. The first sitting (wave-27 T22) ran each
     session headless, as `run-session.sh` does, with the prompt opening with
     `/bionic:canonical-sdlc`. The slash command is all the engagement needs
     (`hooks/engage.sh` writes `<dest>/.bionic/tmp/engaged-<session>.state`). After it the
     session only dispatches: the dispatch wall writes each reader's row, with its
     `questions=`, to `<dest>/.bionic/tmp/roster-<session>.state`, and the start push reads
     that row. To show the roles are the copy's, ask the session before its first dispatch to
     quote the Agent tool's description of `bionic:critic` and `bionic:reviewer`. Each must be
     listed once, with the `description:` line of `$PLUGIN/agents/<role>.md`. (At the first
     sitting the installed 1.11.0 plugin had no reviewer and another critic description.) Then
     read each reader's transcript,
     `~/.claude/projects/<name>/<session>/subagents/agent-<id>.jsonl`. `<name>` is the
     session's physical working directory (`cd <dest> && pwd -P`, which on macOS turns `/var`
     into `/private/var`) with every character that is not an ASCII letter or digit written
     `-`: `sed 's/[^A-Za-z0-9]/-/g'`. So `/private/var/folders/x_y/T/tmp.AbC/s1` is
     `-private-var-folders-x-y-T-tmp-AbC-s1`, and `_` and `.` are rewritten as well as `/`. The
     session's own transcript is `~/.claude/projects/<name>/<session>.jsonl`, `<session>` being
     the `session_id` in `<output file>`. The first sitting's eight directories all follow this
     rule. A reader's `.meta.json` names the `agentType`, and its `hook_success` attachments
     name each `SubagentStart` command that ran: one bare `execution-recorder.sh`, and
     `execution-recorder.sh <question>` for each question dealt, a registration only the copy's
     `hooks/hooks.json` carries.
4. **Dispatch the readers** in that session, through the ordinary dispatch path, one dispatch
   per sample and question:
   - the role the audited dealing gives the sample's question (`facts_owed audited wave` in
     `payload/scripts/lib/proof.sh`): the auditor for `evidence`, the critic for
     `adversarial`, the reviewer for `structure`;
   - and the one-mind case, the critic holding all three questions, on every sample. It is
     named `one-mind` wherever a reader's role is written below (record paths, headings, result
     lines), so it is never taken for the critic the dealing gives `adversarial`. The agent
     dispatched is still `bionic:critic`: `one-mind` is only how the sitting names that dispatch.

   For `clean`, each of the three roles takes its own question, and the one-mind critic takes
   all three.

   The sitting's session binds no plan: the built sample's `docs/plan.md` is read by the
   readers and is not a plan the session has registered. The dispatch wall therefore requires
   each reader's `Questions:` line and does not hold it to a dealing, so it would not refuse a
   set that no rigor deals that role. The orchestrator checks that by hand before each dispatch:
   the brief's set is the one this step names for that role (`evidence` for the auditor,
   `adversarial` for the critic, `structure` for the reviewer, all three for the one-mind
   critic).

   The brief says nothing about an exam, the sample's name, or what to look for. It carries:
   - `Questions: <q>` on a line of its own (`Questions: evidence, adversarial, structure` for
     the one-mind case);
   - the code to read: the repository (the session's project) and its range `<a>..<b>`; its
     `docs/` holds the spec, plan and writers' records;
   - one record path per question it is dealt, under the record root
     `<dest>/.bionic/docs/record/`, in the directory named for the sitting's wave:
     `<dest>/.bionic/docs/record/<wave>/<label>-<role>-<question>.md`, where `<label>` is
     the last component of `<dest>` (`s1`), never the sample's name, and `<role>` is the role
     dealt the question or `one-mind`; the orchestrator maps the label back to its sample when
     it keeps the record (step 6). The one-mind critic gets three paths, for example
     `…/wave-27-review-across-rigor/s1-one-mind-evidence.md`, `…/s1-one-mind-adversarial.md`
     and `…/s1-one-mind-structure.md`, and writes each question's pass to its own path, so its
     records never share a path with the critic dealt `adversarial`;
   - `Suites:` naming each `tests/*.test.sh` of the built repository, one per suite (for
     example `Suites: tests/land.test.sh, tests/stamp.test.sh`), so a reader can re-execute
     the writers' evidence;
   - `Re-executes: none`;
   - `Expected artifact:` naming one of its record paths, and `Files:` listing every one of
     them, comma-separated, one per question. The dispatch wall refuses a reader's brief with
     no `Expected artifact:` line ("this brief names no deliverable"), and one that names
     fewer records than it is dealt questions ("one Files: record per question"). The first
     sitting's briefs also carried `Expected duration: 30 minutes`; the wall does not require
     it (an absent duration only warns).

   A reader that cannot write files returns its records, and the orchestrator saves each
   unchanged at its path. No reader can dispatch a test-runner, so the evidence reader's
   revert-and-watch cannot be done: it will say so, likely as UNVERIFIABLE. That is a `flag`,
   which meets `clean` and does not change a defect sample's `fail`.
   - **Checking what the readers held.** In the same transcript, the `hook_additional_context`
     attachment of `SubagentStart` holds every string pushed at start, as its `content` list.
     One string is the terms (`context/survival.md` and the scratch line), and one per question
     dealt opens with `bionic checks: <q>`, followed by that checks file's bytes. Drop that
     first line and hash the rest; the hash must equal step 1's hash for that file:
     `jq -j 'select(.attachment.type=="hook_additional_context") | .attachment.content[<k>]'
     <agent>.jsonl | tail -n +2 | shasum -a 256`. A reader also holds no checks string for a
     question it was not dealt. At the first sitting each of the twelve readers held exactly
     the files dealt it, each whole. The model receives each string raw: the reviewer's
     `structure` string is 4,497 characters, and its hook printed it as 4,627 characters of
     JSON. The strings of one start are joined into one system `<system-reminder>` (10,978
     characters for a reviewer, 17,565 for the one-mind critic), and none was cut to a
     preview. The harness's 10,000-character limit is therefore applied to each hook's string,
     not to the joined text. Whether that limit counts the raw string or its JSON form is not
     shown, because every string here is under 10,000 either way.
5. **Score each record** on the question the sample's key names, and only that record: on a
   defect sample, the record at that question's path from the role dealt it and the one from
   the one-mind critic; on `clean`, each of the three roles' records on its own question and the
   one-mind critic's record on each of the three. In this checkout:

   ```
   . tests/reader-exam/score.sh
   exam_score tests/reader-exam/samples/<name>/expect.txt <record>
   ```

   It prints `met: declared` or `met`, or `missed` and, for a miss on the declaration, why (see
   `score.sh` above). A reader passes the exam when its record for each question the key names is
   met, and on a defect sample that takes a `finding:` line on the planted defect's file at a
   rating the table sends to fix. The one-mind critic's records for the questions the key does not name are
   kept (step 6) and not scored, and get no `result` line: on a defect sample they were never
   asked to find that defect. The scorer reads a record's `question:` line and not its path, so
   a `missed` on a record without one is a record to check before anything goes to a fix row.
6. **Keep the records.** Copy each record unchanged into the sitting's wave record in this
   checkout, `.bionic/docs/record/<the sitting's wave>/exam-sitting.md`, under a heading per
   record that names the sample, the role (`one-mind` for the one-mind critic) and the
   question, the unscored ones included.
7. **Record the sitting** by appending a section to `sittings.md`, below every earlier one:

   ```
   ## <YYYY-MM-DD> — <who sat it, and why>

   sha256 payload/context/checks-evidence.md <hash>
   sha256 payload/context/checks-adversarial.md <hash>
   sha256 payload/context/checks-structure.md <hash>

   result <sample> <question> <role> <reached result> <met|missed> <record heading>
   ```

   one `result` line per sample, per question its key names, per role dealt that question:
   `<sample>` is the sample's name and `<role>` is `auditor`, `critic` or `reviewer` (the role
   the audited dealing gives the question) or `one-mind`. A defect sample holds two lines, the
   dealt role's and the one-mind critic's, both on its keyed question; `clean` holds six, the
   three roles each on their own question and the one-mind critic on each of the three. The
   record heading names the record's section in `exam-sitting.md`. The `sha256` lines are the
   hashes from step 1. A line opening with `##` that is not a header of that form is red
   wherever it is in the file. The suite reads the last section, by file order: it is red
   unless that section's hashes match the shipped files, every sample has a `result` line and
   no other name has one, every line's role is `one-mind` or the role dealt its own question,
   every sample has a line from each role dealt on each question its key
   names (the red line names the sample and the role missing; the one-mind critic's line alone
   does not complete a sample), no line is for a question its sample's key does not name,
   every `result` line reads `met`, no two lines for one sample and question disagree, and
   every reached result is one its sample's key admits.
   **A sitting whose checks files changed since** is marked, below its last line, by one line:
   `stale: checks-<q> <old>… → <new>…[, …] (<the rows that changed them>); re-sit owed: <row>`, the
   first eight or more hex digits of the hash the sitting read and of the one that ships, for every
   checks file whose digest differs. The suite then passes the pin as history (its `result`
   lines are not read, a retired sample's among them) and stays red on a differing file the line
   does not name, or names with other hashes; the next sitting, appended below, replaces the mark.
8. **A miss is sent back.** A reader that misses a sample sends its checks file to a fix row.
   The sitting is recorded as it went, so the suite is red from then until the fixed file is
   sat again and that sitting is appended below it.

## Adding a sample

A defect that got past a reader becomes a sample before the wave that found it closes
(`.claude/rules/reader-exam.md`). Build it small and self-contained, in shell, faithful to the
real defect, and with nothing in a comment or a file name that gives the defect away. Its row
above names the record it came from. Its key's `names:` identifier names the planted defect
or the owner it bypasses, and is in as few files of the built tree as can be: an identifier
that every file of the change carries is found by any record and shows nothing, and so is a
word of the criterion's own sentence, which a reader quotes whatever its verdict. Its key's
`finding-file:` names the file the planted defect is in, or the owner it bypasses, and every
file named is in the built sample at its head; its `finding-rating:` lists the ratings the
table sends to fix, and the defect must honestly be rated one of them. Prefer the
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
