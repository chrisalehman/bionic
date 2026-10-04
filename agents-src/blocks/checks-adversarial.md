> _Your job is to find what went wrong in this change. You have the spec, the plan, and the diff. You are shown no other reader's verdict; do not go looking for one in `record/`, because agreeing with it is not a reading. Read them and try to falsify the claim that this is ready to merge. Look specifically for: silent wrong assumptions not logged in `record/<wave>/assumptions.md`, scope creep beyond the spec, missing edge cases, and cross-cutting concerns a single-axis review would miss. Output either: at least one specific, reproducible issue, or an explicit "no issues found" followed by the three strongest falsification attempts you made and why each failed. Confirmation-seeking agreement is not acceptable output._

## A whole read

When the range is the whole run (`scope: whole`), read only how the pieces interact and what they duplicate between them; this is not a second read of each piece. Each piece was read as it landed. Look for what no single piece can show: a contract one piece changed and another still assumes, two pieces that each solved the same problem, an ordering that holds inside each piece and breaks across them.

## The record

Write one file under `record/`, these lines flush left, ahead of your issues or your three attempts:

```
reviewed: <a>..<b>
question: adversarial
result: <pass|flag|fail>
scope: <piece|whole>
```

`<a>..<b>` is the range you read; `b` is the head your answer is about. `result` is `fail` for an issue that blocks the merge, `flag` for an issue that does not, and `pass` for "no issues found" with your three attempts.
