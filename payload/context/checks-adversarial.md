> bionic checks for the `adversarial` question — pushed at start to the reader dealt it. They bind.

<!-- GENERATED FILE — DO NOT EDIT.
     Rendered by agents-src/render.sh from agents-src/templates/context/checks-adversarial.md.tmpl and the shared
     blocks in agents-src/blocks/. Edit those, then re-run `bash agents-src/render.sh`.
     tests/docs-pins.test.sh goes red whenever this file and its sources disagree. -->

<!-- CHECKS-ADVERSARIAL-BEGIN -->
> _Your job is to find what went wrong in this change. You have the spec, the plan, and the diff. You are shown no other reader's verdict; do not go looking for one in `record/`, because agreeing with it is not a reading. Read them and try to falsify the claim that this is ready to merge. Look specifically for: silent wrong assumptions not logged in `record/<wave>/assumptions.md`, scope creep beyond the spec, missing edge cases, and cross-cutting concerns a single-axis review would miss. Output either: at least one specific, reproducible issue, or an explicit "no issues found" followed by the three strongest falsification attempts you made and why each failed. Confirmation-seeking agreement is not acceptable output._

For each function, file, type or configuration key the change adds, trace from user input to it: one no caller reaches is a finding. You cannot rerun a walk; if a walk record is in your range, say whether it shows that code reached. On an `incident-response` run only, also ask whether the fix masks a deeper cause, and whether the monitoring-gap analysis is honest.

**Security and trust boundaries.** Ask of every change: what untrusted input reaches it, what permission it exercises or gates, what it can expose, and whether it fails closed. Ask too what happens when a dependency is missing, and whether install, upgrade and remove leave consistent state.

**Known limits.** Read the project's Known limits where it keeps them, such as its changelog. A change that reopens a listed limit, or meets one without saying so, is a finding.

## A whole read

When the range is the whole run (`scope: whole`), read only how the pieces interact; this is not a second read of each piece. Each piece was read as it landed. Look for what no single piece can show: a contract one piece changed and another still assumes, an ordering that holds inside each piece and breaks across them. What the pieces duplicate is the structure reader's.

## The record

Write one file under `record/`, these lines flush left, ahead of your issues or your three attempts:

```
reviewed: <a>..<b>
question: adversarial
result: <pass|flag|fail>
scope: <piece|whole>
```

`<a>..<b>` is the range you read; `b` is the head your answer is about. Rate each finding, write its lines and set `result` by `severity.md`, pushed to you with these checks.
<!-- CHECKS-ADVERSARIAL-END -->
