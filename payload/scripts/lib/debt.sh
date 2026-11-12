#!/bin/bash
# payload/scripts/lib/debt.sh — the one debt-line grammar (epic-23 wave-36 T13; D13, REQ-7 AC-7.8).
#
# WHAT IT OWNS. One carried debt, as one line:
#
#     debt: <concept> <kind> "<site>[, <site>…]" touches=<N> raised-by=<record> from=<wave>
#
# the line close-out writes under a continuation's `## Deferrals`, `debt adopt` reads back into the next
# run's debts and the next run's Step-1 card lists. Before this file three regexes read it (card.sh's
# inherited reader, the debt verb's adopt arm) or wrote it unchecked (close-out's co_debts), and two
# hand-written lines whose `raised-by=` held a space reached a continuation and refused the next card
# (wave-36 A-orch-1). Now `DEBT_LINE_ERE` is the grammar, spelled once, and its three consumers source
# this file: `session-poker.sh debt` (add holds each line it would write to it, adopt reads by it),
# close-out (`co_debt_lines`, which co_debts carries from and the preflight refuses by) and card.sh
# (`_card_inherited`). tests/cross-gate-agreement.test.sh §DEBT-LINE: a mutant of the one regex flips all
# three.
#
# THE FIELDS, each one token with no blank, no `|` (the ledger's cell separator) and no `"`:
#   concept    any such token: `tree_count`, `adopt-orphans`.
#   kind       one of DEBT_KINDS: the debt table's three (severity.md, lib/proof.sh PROOF_DEBT_KINDS, what
#              a reader may write) and `hole`, the kind a writer's or the orchestrator's record declares.
#   sites      one or more `<path>:<line>`, joined by ", ", quoted: the dispatch wall's touch counter
#              (proof_debt_hits) matches a site's path against a brief's Files, so a prose site is never
#              touched and is no site.
#   touches    a count.
#   raised-by  the record that raised it, under the docs root, an `#<anchor>` allowed.
#   from       the wave that carried it.
# A line of any other shape is refused where it is written and never carried.
#
# Sourced, never executed. Defines one list, one constant and one function; reads nothing at load time.
# bash 3.2: no associative arrays.

DEBT_KINDS="duplicate unpinned-pair one-case-abstraction hole"
DEBT_LINE_ERE='^debt:[[:blank:]]+[^[:blank:]|"]+[[:blank:]]+('"${DEBT_KINDS// /|}"')[[:blank:]]+"[^[:blank:],|"]+:[0-9]+(, [^[:blank:],|"]+:[0-9]+)*"[[:blank:]]+touches=[0-9]+[[:blank:]]+raised-by=[^[:blank:]|"]+[[:blank:]]+from=[^[:blank:]|"]+[[:blank:]]*$'

# debt_line_ok <line> -> 0 when the line is one carried debt in the grammar above, else 1. An awk reader
# matches the same string, handed in as ENVIRON["DEBT_LINE_ERE"].
debt_line_ok() {
  [[ ${1-} =~ $DEBT_LINE_ERE ]]
}
