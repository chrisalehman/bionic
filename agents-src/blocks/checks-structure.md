Is the change built from what already exists, and shaped well? Read the code in the range. You are shown no other reader's verdict. Answer every check below on its own `check:` line: PASS, FLAG (a doubt, or a lesser case you name), FAIL (its failing case holds; name the file and line), or `n/a` with the reason it cannot apply to this range. An unanswered check makes the verb refuse the record. "Looks clean" is not an answer: a PASS names what you compared it against. Old code the change did not write never fails a check; a unit it edits fails only if the edit made the case worse.

## Inputs

- The writers' records. Each new function, file, type or configuration key carries a `reuse:` line: the search run, and what was reused or why none fits. Re-run the search; do not take the claim.
- The design's ownership table, where the run has one. Its owner column says where each concept lives, so `reuse` and `one-site` are a comparison, not a hunt. A concept the change introduced that the table never named is a FLAG against the design, not the code.
- Where there is no table, search the codebase yourself for each new site, by name and by what it does. No table is never a reason to pass.

## The checks

- **reuse** — Does each new site do a job nothing in the codebase already does? Fails when a function, file, type or configuration key the change adds does a job an existing one does.
- **one-site** — Is each concept decided in one place? Fails when a rule, value or decision the change writes is also computed elsewhere, or the table gives one concept two owners.
  Each shared-truth pair the change touches, one concept on more than one surface, names one test that fails when the surfaces disagree. You cannot run it; read it. It has been seen to fail when it has an arm that doctors one surface and asserts red, or a record cites a red run. A pair with no named test is a FLAG, and so is a test seen to fail neither way. A pin nobody has watched fail is prose wearing a test; "the suite covers it" is not a named test.
- **single-job** — Does each unit have one reason to change? Fails when the change adds a second, unrelated reason for a unit to change, such as an output format beside a policy.
- **open-closed** — Can the next case be added without editing the code that uses it? Fails when the change adds a case by editing every caller, where one table or one dispatch point would have taken it.
- **substitution** — Does a replacement keep what its callers rely on? Fails when an implementation, override or variant the change adds or edits breaks an expectation its callers hold: a return shape, an error, an exit code, an ordering.
- **narrow-interface** — Does each caller depend only on what it uses? Fails when the change adds a parameter, setup step or dependency a caller must handle but does not use.
- **dependency-direction** — Does the code that makes a decision stay apart from the details it acts on? Fails when a decision the change writes names a concrete path, format or service itself, so swapping that detail, or testing the decision without it, means editing the decision. Example: a function that decides whether a run passed also opens `logs/run.txt` and parses its third column.

## A whole read

When the range is the whole run (`scope: whole`), read only what the pieces duplicate between them; this is not a second read of each piece. Ask each check across pieces, such as two pieces that each added a site for one concept. A check no cross-piece case can reach is `n/a`. How the pieces interact is the adversarial reader's.

## The record

Write one file under `record/`, these lines flush left, one `check:` line per id above:

```
reviewed: <a>..<b>
question: structure
result: <pass|flag|fail>
scope: <piece|whole>
check: <id> <PASS|FLAG|FAIL|n/a> <reason>
```

`<a>..<b>` is the range you read; `b` is the head your answer is about. `result` is `fail` when any check is FAIL, `flag` when any is FLAG, otherwise `pass`.
