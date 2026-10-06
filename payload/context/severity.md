> bionic severity scale — pushed at start to the reader dealt `adversarial` or `structure`, beside its checks. It binds.

<!-- GENERATED FILE — DO NOT EDIT.
     Rendered by agents-src/render.sh from agents-src/templates/context/severity.md.tmpl and the shared
     blocks in agents-src/blocks/. Edit those, then re-run `bash agents-src/render.sh`.
     tests/docs-pins.test.sh goes red whenever this file and its sources disagree. -->

<!-- SEVERITY-BEGIN -->
Severity says how bad a finding is if a user meets it. Reach says whether a user who follows
what the run ships meets it. Rate both; the table gives the consequence.

| Severity | What it is |
|---|---|
| S1 Critical | Harm that cannot be undone: a file or data lost or changed without the user's act, a secret exposed, an act taken without permission. Also what the run ships being unusable with no workaround |
| S2 Major | Core function broken or giving a wrong result, with no reasonable workaround |
| S3 Minor | Something is wrong, and a simple workaround exists or only a non-core function is affected |
| S4 Trivial | No functional effect: cosmetic, wording, a comment that misstates the code, a gap in test tooling |

| | reach `on` | reach `off` |
|---|---|---|
| S1 | fix in the wave | fix in the wave |
| S2 | fix in the wave | defer |
| S3 | defer | note |
| S4 | note | note |

- Rate by the tables, not by how hard the finding was to find.
- A finding to fix names the file and line at the reviewed head and the command that shows it.
- When you cannot run a finding, or cannot choose between two ratings, write the higher rating
  and an `unsure:` line saying what is not known. It owes a check; it is never rated down.
- Age does not lower a rating. Say "older than the reviewed range" beside it.
- A brief never re-rates, and no agent moves a finding across the line. If a brief and these
  tables disagree, the tables decide.
<!-- SEVERITY-END -->

## The finding lines

Your record carries these lines too, flush left:

```
findings: <n>
finding: <n> <S1|S2|S3|S4> <on|off> <path>:<line>|- <title>
shown: <n> <command>
unsure: <n> <what is not known>
```

`findings:` counts the `finding:` lines, one per finding, and is `findings: 0` when there are none; `-` stands in for a finding with no file and line. A finding the table sends to fix has a `shown:` line, naming the command that shows it, or an `unsure:` line; `<n>` is the number of its `finding:` line. Write no priority: the table gives it. `result` is `fail` when the table sends a finding to fix, `flag` when there are findings and none to fix, otherwise `pass`.
