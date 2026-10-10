> bionic checks for the `evidence` question — pushed at start to the reader dealt it. They bind.

<!-- GENERATED FILE — DO NOT EDIT.
     Rendered by agents-src/render.sh from agents-src/templates/context/checks-evidence.md.tmpl and the shared
     blocks in agents-src/blocks/. Edit those, then re-run `bash agents-src/render.sh`.
     tests/render.test.sh goes red whenever this file and its sources disagree. -->

<!-- CHECKS-EVIDENCE-BEGIN -->
> Your job is to falsify the claim that this wave's requirements were faithfully implemented **and proven** — not to review its code, re-verify the feature, or re-run the whole suite. You hold the spec, its governing design, the Verification Matrix, the per-row evidence, and repo access. Walk three levels, top-down; authenticity alone passes waves whose rows are each honestly produced and collectively prove nothing. **(1) Coverage** — walk the chain whole: requirement → design decision → criterion → evidence. For every requirement in the spec, name both the design decisions and the criteria that serve it; a requirement answered by criteria but by no design decision is a hole in the chain, not a covered requirement (where the design is waived, say so and walk requirement → criterion). Seed this mechanically: invert the `provenance:` citation map and the design section's requirement references, and requirements with zero inbound citations from either are the uncovered list before any judgment is spent; spend the judgment on the harder half — requirements cited but weakly expressed, covered in letter and missed in substance. A hole is a **wave-level** finding, because the per-row verdict scheme cannot express a missing row: emit one wave-level verdict alongside the row verdicts. **(2) Power** — for every row, state what the observation would have shown had the change been absent; if the answer is "the same thing," the row proves nothing, whatever its tier. A zero, empty, or not-present readback with no paired positive case is presumed powerless and cannot discharge — you are that rule's enforcement. Per row, also ask: does a changed condition have a test that fails when it is wrong? A branch, comparison or bound the change adds or edits that no test catches inverted leaves its row without power. **(3) Authenticity** — confirm each row's evidence was produced at its declared tier: every tier owes `evidence:` and T4 adds `user-confirmed`, and the fixture must be structurally able to reach the failure the AC guards. Re-execute at least one evidence command per tier used (cap 3 total) and compare outputs. Verdict per row **and one for the wave**: CONFIRMED / REFUTED / UNVERIFIABLE. "The evidence is plausible" is not a verdict. Your row verdicts land in the matrix `auditor` column and the wave's on an `auditor-wave:` line; non-CONFIRMED at either scope blocks closure absent a waiver. Agreement without re-execution is not acceptable output. Hold every report to the reporting contract: a factual claim carrying neither its proving command with output nor the label "unverified" is itself a finding.

## The record

Write one file under `record/`, these lines flush left, ahead of your row verdicts and the wave's:

```
reviewed: <a>..<b>
question: evidence
result: <pass|flag|fail>
scope: <piece|whole>
```

`<a>..<b>` is the range whose evidence you judged; `b` is the head your answer is about. `scope` is `whole` when you audit the run's matrix and `piece` when you audit one fix. When `severity.md` comes with these checks, write one finding per REFUTED or UNVERIFIABLE verdict, a row's or the wave's, on the file and line the verdict rests on; an UNVERIFIABLE one carries an `unsure:` line saying what is not known. Rate each finding, write its lines and set `result` by `severity.md`, pushed to you with these checks. Without it, `result` is `fail` when any verdict is REFUTED, `flag` when any is UNVERIFIABLE and none REFUTED, otherwise `pass`.
<!-- CHECKS-EVIDENCE-END -->
