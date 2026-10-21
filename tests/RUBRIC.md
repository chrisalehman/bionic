# The test rubric

How a reader decides whether one section of one suite earns its place. A reader applies it to one
`section` at a time, writes one record line per section, and two readers who apply it to the same
section write the same verdict. The census of the whole tree is read by it, and the cull deletes by
the census, never by the shape of a line.

## 1. The criterion

A check earns its place only if it can fail in a way nothing already run catches.

## 2. The five verdicts

Every section gets exactly one of these five words in the record's verdict column: `keep`,
`duplicate`, `prose pin`, `tally`, `vacuous`. The last four are culls. Each verdict has a test, and
the test is what the reader writes down.

**The program under test** is what a planted defect mutates:

- code the plugin runs: a hook, a script, a library function, the runner, the test framework;
- the project's declared checks: the command the config names as `release-check:` and what it runs,
  even when it lives under `tests/lib/`;
- a tracked file a program reads by a field: a config key, a template, a roster.

Three things are not the program. A document no program reads, such as a released CHANGELOG block,
an ADR's prose or a spec, is not. A file under an ignored tree, such as a run's record or an ADR
under `.bionic/`, is not, even when a program reads a field of it. A checker a suite defines for
itself, such as a `strike_check` or `sr_check` in the suite's own file, is suite code. An edit to
any of these is not a defect in the sense of this rubric.

**A defect mutates code that is there.** It deletes, inverts or changes a line, an arm or a call
that exists. A new branch keyed on the fixture's own values (a special case for the suite name the
section happens to use) is not a defect, or every section could be kept by inventing one.

### keep

The section has a planted defect that no other named section goes red on.

- The defect is ONE specific mutation of the program under test: a file, the function or line in it,
  and what changes. "Breaks the landing" is not a defect. "`units_validate` in
  payload/scripts/lib/units.sh stops checking that a dep names a row" is.
- The section goes red on that mutation with the fixture as written.
- The reader has searched for every section that could see the mutation (§3 step 4), and none of
  them goes red on it.
- One such defect is enough. A section that catches five defects found elsewhere and one found
  nowhere else is `keep`, and the record carries the one.

**Keep by rule.** A section whose planted defect is a door refusal, a lint or a check pin is kept,
even when another section catches the same defect. The three:

- **door refusal**: the section builds a landing case and reads the door's answer on it (the exit
  of `spawn-worktree.sh ready` or `land`, the refusal line, the branch moving or not), and the
  defect flips that answer: the door publishes or starts a row it must refuse or hold, or refuses a
  row it must publish. It is not a door refusal when the answer on every row stays the same: the
  defect only repeats a run, reorders work, asks a second verb, or another guard in the door still
  gives the same answer. Nor is it when the defect stops the door publishing anything at all, since
  every landing section catches that and none of them pins a case.
- **lint**: the section sweeps the tracked tree for a forbidden shape (a quitting `grep -q` under
  pipefail, a second parser of a record, a case arm without its paren), and its defect is that shape
  planted somewhere in the tree. A count of the shape's matches is the lint's output, not a tally.
- **check pin**: the section runs a declared check itself (the project's `release-check:` command,
  the name scan, `anchors check`), and the defect makes it pass what it should refuse. When the
  section drives the door and the door runs the check, the mark is door refusal.

The record's defect field opens `rule: door refusal —`, `rule: lint —` or `rule: check pin —`, and
then names the defect. No line whose verdict is a cull may carry that prefix.

### duplicate

Every defect the section catches is caught by a named section elsewhere, by one section or by
several together.

- "Elsewhere" includes another section of the same suite.
- The verdict names every catcher as `<suite> §<key>`. When no single section covers all the
  defects, it names one per defect, and together they cover the section.
- **A named catcher goes red on the same mutation with its own fixture.** A section about the same
  topic is not a catcher. A section that drives a different entry point is not one either. For
  example, a section that calls an arm's function directly does not see a mutation in the hook that
  calls the arm.
- **Every named catcher keeps.** A duplicate never names a section that is itself culled. A
  catcher in a suite this reading has not yet given its own verdict is provisional. The census
  merge checks every named catcher's verdict and reopens a duplicate whose catchers do not keep.
- **Every defect keeps one catcher.** When the only sections that catch a defect would all be culled
  without it, one of them keeps it. That is the section in the suite named for the program the
  defect mutates, or, when no suite is, the first in census order (suite file name, then line). Its
  record line names the others in the last field.

### prose pin

The assertion reads a sentence's wording where a field, an exit code, an id or a count of records
carries the fact.

- The test: name the carrier. If the program also exits non-zero, writes a `key=value` field, names
  a row id, or emits a countable record that says the same thing, and the assertion reads the
  sentence around it instead, it is a prose pin.
- An assertion on a token the program emits for a reader to match (`row-landed`, `check-failed`,
  `CARD-EARLY`, a `decide:goal:<theme>` id) reads an id, not a sentence. It is not a prose pin.
- An assertion that the program names the row, file or id in its refusal reads an id, even when the
  id stands inside a sentence. The id is the fact. The words around it are not.
- **When the page is the only carrier, the page is the fact.** Some programs' only output for a
  fact is a page a person reads: the sitrep's lines, a validator's violation line. An assertion
  that the page states a computed value is then not a prose pin. The value can be a time, a state
  in words, a row id or which rule broke, and the test is that the asserted words change when the
  input changes. An assertion on words the page prints whatever the input is pins wording.
- **A document pin is a prose pin.** An assertion on the wording of a document no program reads
  (a released CHANGELOG block, an ADR's prose, a record) pins prose. The released text is carried by
  the release commit that holds it.
- **A suite's own checker over a document is a document pin.** Rows that run the suite's checker on
  doctored copies test the suite, so each such row is vacuous. A row over the real document, or over
  copies derived from it, is a document pin. The section is a prose pin (§3 step 5).
- The verdict quotes the assertion's label or its expected text, and names the carrier:
  `"<quoted>" — carried by <exit 1 | field x= | id T5 | the record count | the release commit>`.

### tally

The assertion is a value that drifts with the tree. It is a count of lines, files, sections,
suites, bytes or rows of a live tracked document, or a pinned current value such as the newest
version or the current head. It is not a count of records a program produced from its fixture.

- The test: would the value change if someone added an unrelated line, file, section or row, or cut
  the next release, with no defect planted in the program? Yes means tally.
- A count of the records the program wrote from a fixture the section builds (or a frozen fixture
  file that only the suite edits) is a record count. It can be a keep.
- The verdict quotes the assertion and says what it drifts with.

### vacuous

No program the section could run makes the assertion fail, given the fixture as written.

- The fixture never reaches the assertion: a guard skips it on this machine, a loop runs over an
  empty list, a `return` or `exit` comes first, a helper that would build the input is never called.
- The assertion passes on any program: `expect_eq 0 $?` after a command that cannot fail (`… || true`,
  a pipe whose last stage always exits 0), an `expect_absent` or `expect_empty` whose subject no
  version of the program ever prints, a grep whose absence is the default.
- The assertion reads only suite code: a suite's own checker run on doctored copies, a count of the
  suite's own literal.
- The probe: try to name a mutation that turns the assertion red. Replacing the program with a stub
  that exits 0 and prints nothing is the first try. An absence assertion that a stub passes is not
  vacuous by that alone: it is vacuous only if no mutation can make the program print the thing.
- A `setup_section` that builds nothing a later section reads (a tombstone that says a feature is
  gone) is read as a section, and with nothing else in it, it is vacuous.
- The verdict names why, in one clause.

## 3. The reading method

1. **List the suite's sections** with the command below. It prints every `section` and
   `setup_section` call with its key. Every `section` line gets a record line. A `setup_section`
   gets one only when it builds nothing a later section reads. A `setup_section` that builds a
   fixture gets no line, even when it holds an assertion. That assertion is the fixture's own
   precondition, and it goes with the fixture.
2. **Read a section with its fixture.** The fixture is everything the section's assertions read:
   the `setup_section` above it, the helpers the suite defines, the prelude or `tests/lib/` file it
   sources, and the variables an earlier section left behind.
3. **Write a defect for each assertion first.** Before reading who else might catch them, write
   the one mutation that turns each assertion red. A reader who stops at the first defect, finds
   another section catches it, and writes `duplicate` has not yet read the section. Judge the
   assertions that are there, never the title or the comments. A call whose assertion was deleted
   asserts nothing. An assertion with no nameable defect earns a cull of the kind it shows.
4. **Then ask who else catches each.** Search the tests tree with `/usr/bin/grep`, because the shell
   `grep` may skip ignored trees. Search for three things: the mutated symbol, the file that
   defines it, and the hooks and verbs that load that file. A suite that runs a hook reaches every
   library the hook loads. A quiet-path assertion over the real hook (empty stderr, empty stdout)
   catches load-time noise from any of them. Read every section found, and decide whether it goes
   red on the same mutation with its own fixture. Name each one that does.
5. **Take the strongest verdict the section's assertions earn.** Each assertion earns a verdict on
   its own. One `keep` assertion keeps the whole section. With no `keep`, the section takes the
   assertion verdict nearest to keep, in this order: `duplicate`, `prose pin`, `tally`, `vacuous`.
   A section of only prose pins is culled as a prose pin.
6. **A kept section is kept whole.** Its weaker assertions are not culled by this census. A reader
   may say so in the defect field after the defect, as `also: N prose pins`, for a later pass.

The section list:

```bash
awk '/^[[:space:]]*(setup_)?section[[:space:]]+"/ {
  kind = ($0 ~ /^[[:space:]]*setup_/) ? "setup" : "section"
  t = $0; sub(/^[[:space:]]*(setup_)?section[[:space:]]+"/, "", t); sub(/"[^"]*$/, "", t); sub(/^§/, "", t)
  k = t; i = index(k, " — "); j = index(k, ": ")
  if (i && (!j || i < j)) k = substr(k, 1, i - 1); else if (j) k = substr(k, 1, j - 1)
  n++; F[n] = FILENAME ":" FNR; K[n] = kind; T[n] = t; S[n] = k; G[n] = FILENAME; seen[FILENAME SUBSEP k]++
}
END { for (m = 1; m <= n; m++) print F[m], K[m], "§" (seen[G[m] SUBSEP S[m]] > 1 ? T[m] : S[m]) }' tests/<suite>.test.sh
```

**The key** is the section's title up to its first ` — ` or `: `, with a leading `§` dropped. When
two sections of one suite share that key, each is keyed by its whole title instead. The command
applies both rules.

## 4. The record line

One line per section, five fields, ` | ` between them, no `|` inside a field:

```
<suite> | §<key> | <verdict> | <defect or reason> | <who else catches it, or none>
```

- `<suite>` is the file name, `stop.test.sh`.
- `<verdict>` is one of the five words, exactly.
- `<defect or reason>`: for `keep` and `duplicate`, the defect as a mutation, with the `rule: …`
  prefix where it applies. For `prose pin` and `tally`, the quoted assertion and its carrier or what
  it drifts with. For `vacuous`, why.
- `<who else catches it, or none>`: the sections that go red on the same defect, each as
  `<suite> §<key>`, separated by `, `. `none` when the search found no other, followed by the
  pattern searched: `none (searched 'units_validate' in tests/)`. A `duplicate` line never says
  `none`. A `keep` line names others only when it is kept by rule or by the one-catcher rule.

Two lines of the shape, on a made-up suite:

```
example.test.sh | §REFUSE | keep | payload/scripts/lib/example.sh example_check: the missing-id arm returns 0 | none (searched 'example_check' in tests/)
example.test.sh | §LOADS | duplicate | payload/scripts/lib/example.sh: example_check deleted | example.test.sh §REFUSE
```

## 5. Calibration examples

Four readers applied parts 1 to 4 to the same five suites: release-check, units, sitrep,
landing-line-1 and stop, 83 sections. They agreed on 71 verdicts. Each example below is a section
they split on, or one they agreed on but flagged as unclear. Each gives the ruled record line, how
the readers split, and the rule the example sharpens. The rules above already carry the rewording.

### The reader named one defect and stopped

Most splits came from this. One reader found a defect only this section catches. Another named a
different defect that a second section also catches, and wrote `duplicate`. The first reading is
right. Rule: §3 step 3 and keep's "one such defect is enough".

```
stop.test.sh | §2 | keep | payload/scripts/lib/stop.sh: the unbound advisory written straight to stderr instead of staged through the fold, so it prints ahead of the landing refusal (2e) | none (searched 'newest-plan fallback' in tests/)
```

Split two keep, two duplicate. The duplicates named a mutation of lib/fold.sh, which fold.test.sh §3
catches on stubs. That suite drives the fold alone and never sees a Stop arm that bypasses it.

```
stop.test.sh | §4 | keep | payload/scripts/lib/stop.sh stop_patrol_duties: the session's run resolved, announcing the unbound advisory, before its SubagentStop return, so the advisory prints on a worker's stop (4b) | none (searched 'session unbound' in tests/)
```

Split two keep, two duplicate. The duplicates named 4a's Patrol arm, which patrol-revive.test.sh
§Group 2 catches. Every other reader of the advisory reads it on Stop only.

```
stop.test.sh | §7 | keep | payload/scripts/lib/stop.sh stop_patrol_duties: a row ledgered active still counts as ready, so the turn that dispatched T13 is refused for the fill (7f) | none (searched 'ready with room' in tests/)
```

Split three keep, one duplicate. The duplicate named the base fill refusal, which §9 catches.
None of §9, §GAP, §UB or §SD builds an active row.

```
sitrep.test.sh | §SURFACES | keep | hooks/session-poker.sh tick: the poker: sitrep line printed after the decision line, so the tick's last line is no longer decision= (S1) | none (searched 'poker: sitrep' in tests/)
```

Split three keep, one duplicate. The duplicate named S2, the line dropped, which §GOAL-MISS catches.

```
release-check.test.sh | §CORR | keep | agents-src/templates/commands/help.md.tmpl: the bionic @@PLUGIN_VERSION@@ (installed) line deleted and the pages rendered again, so render.sh --check stays green and (c1) goes red. also: 4 prose pins on the 1.19.0 block | none (searched '(installed)' and 'PLUGIN_VERSION' in tests/)
```

Split two keep, two duplicate. The duplicates named a stale render, which render.test.sh §Section 1
catches through `--check`. A template line deleted and rendered again leaves `--check` green, and
render.test.sh never reads the version line. A template is a tracked file a program reads, so it
is the program.

### A union covers the section

Each of the section's defects is caught somewhere else, but no single section catches all of them.
The criterion asks whether the section can fail in a way nothing already run catches. It cannot,
so it is a duplicate that names one catcher per defect. Rule: duplicate's first line and "names one
per defect".

```
stop.test.sh | §3 | duplicate | each arm's engagement check deleted, so a bystander's turn end speaks; a library on the Stop path writes to stderr when loaded (3c) | context-spend.test.sh §Group 2, patrol-duties-gate.test.sh §Section 3, landing-gate.test.sh §Section 5, landing-gate.test.sh §Section 1
```

Split three duplicate, one keep. The keep was on 3c's empty stderr, which no per-arm suite reads.
But hooks/stop.sh loads its libraries ahead of the engagement answer. landing-gate.test.sh
§Section 1 runs the real hook and asserts empty stderr (1b) and empty stdout (1a), so it catches
the same load-time noise. The per-arm catchers are provisional until the census gives them their
own verdicts.

```
units.test.sh | §0 | duplicate | payload/scripts/lib/units.sh: a top-level line writes to stderr or stdout when sourced; the file does not parse, or loses units_rows | landing-gate.test.sh §Section 1, units.test.sh §1
```

Split two keep, two duplicate. The keeps searched by the symbol and found no other driver.
hooks/stop.sh loads units.sh through lib/stop.sh before its engagement answer, so landing-gate.test.sh
§Section 1's quiet-path rows catch the noise. The search covers the hooks that load a file
(§3 step 4).

### The catcher must see the same mutation

```
stop.test.sh | §5 | duplicate | hooks/stop.sh: the stop_hook_active guard ahead of the fold deleted, so the landing arm, which carries no guard of its own, refuses the re-entry (5a) | landing-gate.test.sh §Section 1
```

All four wrote duplicate, but they named different catchers. Two named the Patrol suites. Those
arms honour `stop_hook_active` themselves, so they stay green when the hook's guard goes. Rule:
"a named catcher goes red on the same mutation with its own fixture".

```
sitrep.test.sh | §FACTS | duplicate | hooks/poker/sitrep.sh: a page heading renamed, so FA1 goes red | sitrep.test.sh §SKILL
```

Split three duplicate, one keep. FA2 to FA5 run the suite's own `sr_check` on doctored copies,
which reads only suite code, so each is vacuous. FA1 runs over the verb's page, and §SKILL's O5
catches the same mutation. Rule: vacuous's "reads only suite code".

### The defect must be code that is there

```
landing-line-1.test.sh | §RELEASE-ROW | duplicate | payload/scripts/lib/line.sh line_ready: every tests/*.test.sh run instead of the Lands-on suites, so other.test.sh gets a verdict beside the release check (rr1) | landing-line-1.test.sh §GATE
```

Split three duplicate, one keep. The keep planted a special case that widens a release row alone.
lib/line.sh holds no release special case, and this world declares no `release-check:`. Rule: "a
defect mutates code that is there".

### Door refusal means the door's answer flips

```
landing-line-1.test.sh | §ALONE | duplicate | payload/scripts/lib/line.sh line_ready: a second spawn-worktree.sh verb called between ready and published, so the verb log holds more than ready (l1) | landing-line-1.test.sh §READY
```

Split three duplicate, one keep by rule. The keep's defect was "ready never publishes". Every
landing section catches that, and it pins no case. The remaining defect, a second verb, leaves the
door's answer unchanged.

```
landing-line-1.test.sh | §ANCHORS | keep | rule: door refusal — payload/scripts/lib/line.sh line_ready: the anchors check over the candidate dropped, so a row that rewords another suite's anchor publishes instead of exit 2 reason=anchor-moved (an1) | none (searched 'anchor-moved' in tests/)
```

All keep. Three readers marked it door refusal and one check pin. The section drives `ready`, and
the door runs the check, so the mark is door refusal.

```
landing-line-1.test.sh | §AHEAD-RED | keep | rule: door refusal — payload/scripts/lib/line.sh line_ready: T2's candidate built on returned T1's published without a rebuild, so T1's red commit reaches the branch (a2) | none (searched 'line_ready' and 'why=red' in tests/)
landing-line-1.test.sh | §WITHIN | keep | rule: door refusal — payload/scripts/lib/line.sh _line_time_for: exit 1 made exit 0, so a suite promising 600 s starts with 60 s left instead of WAITING exit 75 (n1) | none (searched '_line_time_for' in tests/)
landing-line-1.test.sh | §GUARD (ready half) | keep | payload/scripts/lib/line.sh line_ready: the _wt_bionic_committed check removed, so a landing tree is built before the publish guard refuses (u1) | none (searched '_wt_bionic_committed' in tests/)
landing-line-1.test.sh | §SIDE | keep | payload/scripts/lib/line.sh line_ready: T2's candidate built on T1's rebuilt once T1 publishes, so T2 runs twice (w2) | none (searched 'one run each' in tests/)
```

All keep, split on the mark. §AHEAD-RED was marked by three readers and §WITHIN by three. In both,
the door's answer flips: a red commit is published, and a held suite starts. §GUARD (ready half)
was marked by one reader. The publish guard still refuses that row, so the answer does not flip.
§SIDE was marked by one reader, on the gate's width. A repeated run leaves every answer the same,
and the gate answers width, not a landing.

### Fixtures, documents and pinned values

```
release-check.test.sh | §fixtures | (no record line)
```

Split two vacuous, two duplicate. It builds the fixtures every later section reads. Its one
assertion checks that the list directory sits outside a checkout, which is the fixture's
precondition. Its `|| exit 1` guard is fixture too. Rule: §3 step 1, a fixture setup_section gets
no line.

```
release-check.test.sh | §STRIKE | prose pin | "(s3a) strike: (4) is on 0 bullets" and the doctored-copy setups read the released 1.17.0 block through the suite's own strike_check — carried by the 1.17.0 release commit | none (searched 'strike_check' in tests/)
```

All four wrote prose pin, and all four flagged vacuous as the other reading. §ENTRY-1.18.0,
§REL-1.20.0 and §REVERSE are the same case. Rule: "a suite's own checker over a document is a
document pin". The doctored-copy rows are vacuous, and prose pin ranks above vacuous.

```
release-check.test.sh | §ADR | prose pin | "(a2) the repository's ADR-053 and ADR-054 keep every rule" reads the status lines of ADRs under an ignored tree — carried by the release commits that accepted them | none (searched 'adr_status' in tests/)
```

All prose pin, and all four readers flagged it. One program does read an ADR's `status:` field, but the ADR files are
not tracked. Rule: "a file under an ignored tree is not the program".

```
release-check.test.sh | §REL-1.23.0 | prose pin | "(n2) …name the head and instant" and "(n4) …states the amended rule" read the released 1.23.0 block and ADR prose — carried by the 1.23.0 release commit; "(n1) the newest CHANGELOG heading is 1.23.0" is a tally of the newest release | release-check.test.sh §VERSION-PAIR
```

Split three prose pin, one duplicate. The duplicate named render.test.sh §Section 1 for n1. But n1
reads the CHANGELOG heading, and it goes red at the next release with no defect planted. Rule:
tally's "pinned current value". Prose pin ranks above tally.

```
landing-line-1.test.sh | §ONE-READER | keep | rule: lint — a second parser of the landing record planted in hooks/, so the sweep finds it beside lib/line.sh (o2) | none (searched 'line_kv' and 'ev=verdict' in tests/)
```

All keep by rule lint. Three readers flagged the expected `line.sh:2` as a possible tally. Rule:
"a count of the shape's matches is the lint's output".

### The page carries the fact

```
sitrep.test.sh | §WAIT-WORDS | keep | hooks/poker/sitrep.sh sitrep_render: a proof:review dependency printed as the judge's facts string and record path instead of its words (WW1) | none (searched 'review facts' in tests/)
```

All keep, flagged by three readers, with §ROWS and §NEXT-STOPS as the same case. The page is the
sitrep's only output, and the asserted words change with the task's state. units.test.sh §6's
violation lines ("T3: step 2 is outside 3-9") are the same case, since no exit code or field says
which rule broke. Rule: "when the page is the only carrier, the page is the fact".
