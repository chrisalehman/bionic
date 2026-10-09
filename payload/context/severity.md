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

The two tables above are the harm table. Debt is paid by the next change that touches it, not by
a user: a finding of class debt is rated by its kind and the concept it names on this table, never
by severity.

| Kind | What it is | Disposition |
|---|---|---|
| duplicate | A second copy of a concept the ownership table or a search already locates | burn-when-touched: `<concept>` |
| unpinned-pair | A shared pair with no named agreement test | burn-when-touched: `<concept>` |
| one-case-abstraction | An abstraction, parameter or indirection with one case or one caller | burn-when-touched: `<concept>` |

- A debt finding names its concept and its sites, never a severity, on one line flush left:
  `debt: <kind> <concept> <path>:<line>[, <path>:<line>…]`. It is not a `finding:` line, and it
  sets `result` to `flag` when no finding sets it higher.
- Its disposition is burn-when-touched, never fix now and never note: the orchestrator records it
  in `record/<run>/debt.md` at the review findings disposition, and the next row whose Files touch the concept burns
  it inside its own work.

Only readers rate: a finding's severity and reach are written by the reader that found it, and no
agent, the orchestrator included, moves a rating in either direction; a user's re-rating is
recorded with attribution.

Three stop rules bound what a finding becomes:

- In-diff only: a finding in code the run did not change is a next-wave item unless it is S1.
- Three fixes on one component stop the run.
- A fix row is never re-read by a fresh pass.
<!-- SEVERITY-END -->

## The finding lines

Your record carries these lines too, flush left:

```
findings: <n>
finding: <n> <S1|S2|S3|S4> <on|off> <path>:<line> <title>
finding: <n> <S1|S2|S3|S4> <on|off> - <title>
shown: <n> <command>
unsure: <n> <what is not known>
```

`findings:` counts the `finding:` lines, one per finding, and is `findings: 0` when there are none. Write each finding in one of its two forms: with `<path>:<line>` as its site, or with a lone `-` when it has no file and line. Choose one, never both joined. A finding the table sends to fix has a `shown:` line, naming the command that shows it, or an `unsure:` line; `<n>` is the number of its `finding:` line. Write no priority: the table gives it. `result` is `fail` when the table sends a finding to fix, `flag` when there are findings and none to fix, otherwise `pass`.

```
findings: 2
finding: 1 S2 on lib/reap.sh:10 the reaper admits a dead pid
shown: 1 grep -n 'kill -0' lib/reap.sh
finding: 2 S4 off - the module header names no owner
```

## The debt line

A debt finding is one flush-left line that `findings:` does not count, in one of two forms:

```
debt: <kind> <concept> <path>:<line>
debt: <kind> <concept> <path>:<line>, <path>:<line>
```

`<concept>` is a single token with no space, such as `reap-counter`, and the first site follows it at once. Each further site follows a comma and a space. A debt site is never `-`, and the line carries no severity or reach.

```
debt: one-case-abstraction name-registry lib/naming.sh:6
debt: duplicate reap-counter lib/reap.sh:12, lib/sweep.sh:30
```
