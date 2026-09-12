<!--
THE 1.4.0 SPECIMEN'S SCHEDULE TABLE, verbatim from
.bionic/docs/plans/wave-bionic-1.4.0-update/wave.plan.md:374-397 at 1f48673.

WHY IT LIVES HERE. This is the RETIRED four-column shape, under the retired section
heading, and it is the only place in the tree that still spells either: REQ-1e's A-31 grep
excludes tests/fixtures/migration/ for exactly this, so a migration fixture can keep the
old bytes without the vocabulary pin going soft everywhere else.

WHAT READS IT. tests/units.test.sh's differential section, which drives the OLD FILL
derivation (slice_table + slice_ready, lifted verbatim from hooks/session-poker.sh at
1f48673) over this table and `units_ready` over its ten-column twin, and asserts the two
ready sets are identical at every status configuration. Nothing in the shipped tree parses
this file; it is a specimen, not a plan.
-->

## Slices (machine-readable, read by SCHED's FILL once it lands; maintained by the orchestrator)

| id | deps | complexity | status |
|---|---|---|---|
| L-ROOT | — | complex | landed |
| L-SESSION | — | standard | landed |
| L-RUN | — | standard | landed |
| L-LOADER | — | complex | landed |
| L-RESOURCES | — | complex | landed |
| L-DETECT | — | standard | landed |
| ADOPT | L-ROOT,L-SESSION,L-RUN,L-LOADER,L-DETECT | complex | landed |
| SSTART | — | complex | landed |
| STOPGATES | ADOPT | standard | landed |
| POKER | — | complex | landed |
| WALLS | ADOPT,L-RESOURCES | complex | landed |
| WORKTREE | — | complex | landed |
| VENV | — | standard | landed |
| DOCTOR | — | complex | landed |
| DOCTORFIX | DOCTOR,ADOPT | complex | landed |
| RELEASE | — | standard | landed |
| SCHED | POKER,STOPGATES,WALLS,L-RESOURCES | complex | landed |
| DOCTOR-RESTART | — | standard | landed |
| TESTFIX | — | standard | landed |
