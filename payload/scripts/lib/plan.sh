#!/bin/bash
# payload/scripts/lib/plan.sh — the plan's integration branch, read once (wave-39 T16; D18, REQ-12 AC-12.1).
#
# WHAT IT OWNS. One question: which branch does this run integrate into?
#
#     plan_integration_branch <plan>
#                        the value of `integration-branch:` under the plan's `## SDLC State`, else the same key in
#                        its leading frontmatter; nothing when neither names one, or <plan> is no file. Always rc 0.
#
# THE ONE READER (burns debt integration-branch-reader; critic-structure-2). Two orders stood: close-out.sh read
# ## SDLC State and refused a plan whose frontmatter alone named the branch, its `closed-form` then fell back to the
# frontmatter, and session-poker.sh `handoff` read the frontmatter first with an awk of its own, while `release-check`
# read the frontmatter alone. D18 rules ## SDLC State first, the frontmatter as the fallback: the order lib/run.sh
# `plan_working_branch` already reads the working branch in. close-out.sh and every session-poker.sh reader of the key
# call this; tests/close-out-1.test.sh and tests/handoff-file.test.sh §BRANCH-AGREE hold them to one answer.
#
# THE GRAMMAR IS THE WORKING BRANCH'S. The section is `##` and blanks, then `SDLC State`; fenced lines are not read;
# the key may be indented; the value is its first word, one leading and one trailing quote of either kind dropped. A
# branch name holds no blank, so the first word is the whole of every value a plan carries; close-out's old reader
# took the rest of the line, trimmed, which differs only on a line no branch can be.
#
# NEEDS lib/run.sh (`_run_lines`, the newline rule: CRLF and a lone CR both end a line). Both callers source it first.
# Sourced, never executed; bash 3.2.

_PLAN_IB_SDLC_AWK='
  /^[[:space:]]*```/ { fence = !fence; next }
  fence { next }
  /^##[[:space:]]/ { insdlc = ($0 ~ /^##[[:space:]]+SDLC State/); next }
  insdlc && /^[[:space:]]*integration-branch[[:space:]]*:/ {
    v = $0; sub(/^[[:space:]]*integration-branch[[:space:]]*:[[:space:]]*/, "", v); sub(/[[:space:]].*$/, "", v)
    gsub(/^["\047]|["\047]$/, "", v); print v; exit }'
_PLAN_IB_FM_AWK='
  NR == 1 && $0 == "---" { f = 1; next }
  f && $0 == "---" { exit }
  f && /^[[:space:]]*integration-branch[[:space:]]*:/ {
    v = $0; sub(/^[[:space:]]*integration-branch[[:space:]]*:[[:space:]]*/, "", v); sub(/[[:space:]].*$/, "", v)
    gsub(/^["\047]|["\047]$/, "", v); print v; exit }'
plan_integration_branch() {  # <plan>
  local plan="${1:-}" ib
  [ -n "$plan" ] && [ -f "$plan" ] || return 0
  ib="$(_run_lines "$plan" | awk "$_PLAN_IB_SDLC_AWK")"
  [ -n "$ib" ] || ib="$(_run_lines "$plan" | awk "$_PLAN_IB_FM_AWK")"
  printf '%s' "$ib"
  return 0
}
