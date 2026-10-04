> bionic checks for the `structure` question — pushed at start to the reader dealt it. They bind.

<!-- GENERATED FILE — DO NOT EDIT.
     Rendered by agents-src/render.sh from agents-src/templates/context/checks-structure.md.tmpl and the shared
     blocks in agents-src/blocks/. Edit those, then re-run `bash agents-src/render.sh`.
     tests/docs-pins.test.sh goes red whenever this file and its sources disagree. -->

<!-- CHECKS-STRUCTURE-BEGIN -->
Is the change built from what already exists, and shaped well? Read the code in the range. You are shown no other reader's verdict. Answer every check below on its own `check:` line: PASS, FLAG (a doubt, or a lesser case you name), FAIL (its failing case holds; name the file and line), or `n/a` with the reason it cannot apply to this range. A check left unanswered makes the record one the verb refuses. "Looks clean" is not an answer: a PASS names what you compared it against.

## Inputs

- The writers' records. Each new function, file or type carries a `reuse:` line: what was searched, and what was reused or why none fits. Check the claim against the code; do not take it.
- The design's ownership table, where the run has one. Its owner column says where each concept lives, so `reuse` and `one-site` are a comparison, not a hunt. A concept the change introduced that the table never named is a FLAG against the design, not the code.
- Where there is no table, search the codebase yourself for each new site, by name and by what it does. No table is never a reason to pass.

## The checks

- **reuse** — Does each new site do a job nothing in the codebase already does? Fails when a new function, file or type does what an existing one does, and the change could have called it.
- **one-site** — Is each concept decided in one place? Fails when one rule, value or decision is computed in two places, or the table gives one concept two owners.
  Each shared-truth pair, one concept with more than one surface, names one test that fails when the surfaces disagree, and that test has been seen to fail: a copy doctored on purpose turns it red. A pin nobody has watched fail is prose wearing a test. A pair with no named test is a FLAG, and "the suite covers it" is not a named test.
- **single-job** — Does each unit have one reason to change? Fails when a unit would change for two unrelated reasons, such as an output format and a policy.
- **open-closed** — Can the next case be added without editing the code that uses it? Fails when the change adds a case by editing every caller, where one table or one dispatch point would have taken it.
- **substitution** — Does a replacement keep what its callers rely on? Fails when a new implementation, override or variant breaks an expectation its callers hold: a return shape, an error, an exit code, an ordering.
- **narrow-interface** — Does each caller depend only on what it uses? Fails when a caller must take, set up or know about parts of an interface it does not use.
- **dependency-direction** — Does detail depend on policy, not the reverse? Fails when a unit that decides policy reaches into a detail (a path, a format, a vendor call) that should sit behind a boundary the policy owns.

## A whole read

When the range is the whole run (`scope: whole`), read only how the pieces interact and what they duplicate between them; this is not a second read of each piece. Ask each check across pieces: two pieces that each added a site for one concept, a caller one piece changed under another. A check no cross-piece case can reach is `n/a`.

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
<!-- CHECKS-STRUCTURE-END -->
