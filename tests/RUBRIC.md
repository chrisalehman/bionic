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

**The program under test** is what a planted defect mutates: code the plugin runs (a hook, a script,
a library function, the runner, the test framework itself), or a tracked file a program reads by a
field (a config key, a frontmatter field, a template, a roster). A document no program reads, such as
a released CHANGELOG block, an ADR's prose or a spec, is not a program, and an edit to it is not a
defect in the sense of this rubric.

### keep

The section's planted defect is nameable, and no other named section goes red on it.

- The defect is ONE specific mutation of the program under test: a file, the function or line in it,
  and what changes. "Breaks the landing" is not a defect. "`units_validate` in
  payload/scripts/lib/units.sh stops checking that a dep names a row" is.
- The section goes red on that mutation with the fixture as written.
- The reader has searched the tests tree for the mutated symbol and read every section that drives
  it, and none of them goes red on the same mutation.
- The record carries the defect.

**Keep by rule.** A section whose planted defect makes the landing door, a lint, or a check pin
pass what it should refuse is kept, even when another section catches the same defect. The three:

- **door refusal**: the defect makes the landing door (`spawn-worktree.sh ready`, `land`, the line's
  publish, a wall the door asks) admit what it refuses, or refuse what it admits.
- **lint**: the section sweeps the tracked tree for a forbidden shape (a quitting `grep -q` under
  pipefail, a second parser of a record, a case arm without its paren), and its defect is that shape
  planted somewhere in the tree.
- **check pin**: the defect makes a check the door or the release runs (the project's declared
  `release-check:`, the name scan, `anchors check`) pass what it should refuse.

The record's defect field opens `rule: door refusal —`, `rule: lint —` or `rule: check pin —`, and
then names the defect. No line whose verdict is a cull may carry that prefix.

### duplicate

A named section elsewhere goes red on the same defect, and this section catches nothing that one
does not.

- "Elsewhere" includes another section of the same suite.
- The verdict names that section as `<suite> §<key>`, and that section's own verdict is `keep`. A
  duplicate never names a section that is itself culled.
- **Two sections that catch exactly the same defects keep one.** The one kept is the section in the
  suite named for the program the defect mutates; when neither suite is, the one that comes first
  in census order (suite file name, then line). The other is the duplicate and names it.
- A section that catches the shared defect and one more is `keep`, with the one more as its defect.

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
- **A document pin is a prose pin.** An assertion on the wording of a document no program reads
  (a released CHANGELOG block, an ADR's prose, a record) pins prose. The released text is carried by
  the release commit that holds it.
- The verdict quotes the assertion's label or its expected text, and names the carrier:
  `"<quoted>" — carried by <exit 1 | field x= | id T5 | the record count>`.

### tally

The assertion is a count that drifts with the tree: lines, files, sections, suites, bytes, rows of
a live tracked document. It is not a count of records a program produced from its fixture.

- The test: would the count change if someone added an unrelated line, file, section or row to the
  tracked tree, with no defect planted in the program? Yes means tally.
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
- The probe: try to name a mutation that turns the assertion red. Replacing the program with a stub
  that exits 0 and prints nothing is the first try. An absence assertion that a stub passes is not
  vacuous by that alone: it is vacuous only if no mutation can make the program print the thing.
- A `setup_section` that builds nothing a later section reads and asserts nothing (a tombstone
  that says a feature is gone) is read as a section, and it is vacuous.
- The verdict names why, in one clause.

## 3. The reading method

1. **List the suite's sections** with the command below. It prints every `section` and
   `setup_section` call with its key. Every `section` line gets a record line. A `setup_section` gets
   one only when it holds an assertion or builds nothing a later section reads.
2. **Read a section with its fixture.** The fixture is everything the section's assertions read:
   the `setup_section` above it, the helpers the suite defines, the prelude or `tests/lib/` file it
   sources, and the variables an earlier section left behind.
3. **Write the planted defect first.** Before reading who else might catch it, write the one
   mutation that turns this section red. If none can be named, the section is `vacuous` or a cull
   of the kind its assertions show. Do not start from the verdict and work back.
4. **Then ask who else catches it.** Search the tests tree for the mutated symbol with
   `/usr/bin/grep` (the shell `grep` may skip ignored trees), read every section that drives it,
   and decide whether each goes red on the same mutation with its own fixture. Name each one that
   does.
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
  `none`.

Two lines of the shape, on a made-up suite:

```
example.test.sh | §REFUSE | keep | payload/scripts/lib/example.sh example_check: the missing-id arm returns 0 | none (searched 'example_check' in tests/)
example.test.sh | §LOADS | duplicate | payload/scripts/lib/example.sh: example_check deleted | example.test.sh §REFUSE
```

## 5. Calibration examples

Pending: the four calibration readers' records over release-check, units, sitrep, landing-line-1
and stop are reconciled here, one example per section they disagreed on, with the ruled verdict and
the reason.
