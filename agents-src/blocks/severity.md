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
  in `record/<run>/debt.md` at the sitting, and the next row whose Files touch the concept burns
  it inside its own work.
