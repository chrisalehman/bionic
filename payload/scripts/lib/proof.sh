#!/bin/bash
# payload/scripts/lib/proof.sh — the proof record (epic-23 wave-26 T4; REQ-3, D5).
#
# WHAT IT OWNS. One fact per proof: which commit a test pass or a review read. A proof is a
# line inside the plan's `## SDLC State`:
#
#     proved: kind=<floor|review|task> head=<40-hex> at=<ISO-UTC> evidence=<path under record/>
#
# written only by `session-poker.sh proof-add <kind> <evidence>` through the plan verbs'
# transaction, and read by `proof_last`. What is unproved is the difference since the head a
# proof names; `proof_state` (T5, beside these) is the reader that judges that difference.
#
# THE HEAD IS NEVER AN OPERAND. It is `git rev-parse HEAD` of the checkout holding the plan's
# `working-branch:` — the branch the run builds on — so a proof cannot name a commit nobody
# checked out, and a caller cannot pass the head it wishes it had read.
#
# Sourced, never executed. Defines functions and one constant; reads nothing at load time.
# bash 3.2: no associative arrays, no `${var,,}`.

PROOF_KINDS="floor review task"

# proof_kind_ok <kind> -> 0 when <kind> is one of PROOF_KINDS.
proof_kind_ok() {
  case " $PROOF_KINDS " in *" ${1:-} "*) [ -n "${1:-}" ] ;; *) return 1 ;; esac
}

# proof_line <kind> <head> <at> <evidence> -> the one proof line, newline-terminated.
proof_line() {
  printf 'proved: kind=%s head=%s at=%s evidence=%s\n' "$1" "$2" "$3" "$4"
}

# proof_working_branch <plan> -> the plan's `working-branch:`, or nothing. The `## SDLC State`
# key first — the one the `current` verb reads to fill the Step-4 block — then the frontmatter
# key of the same name, which a plan written by Step 0 also carries. Fenced lines are not read.
proof_working_branch() {
  local plan="$1" wb
  [ -f "$plan" ] || return 0
  wb="$(awk '
    /^[[:space:]]*```/ { fence = !fence; next }
    fence { next }
    /^##[[:space:]]/ { insdlc = ($0 ~ /^##[[:space:]]+SDLC State/); next }
    insdlc && /^[[:space:]]*working-branch[[:space:]]*:/ {
      v = $0; sub(/^[[:space:]]*working-branch[[:space:]]*:[[:space:]]*/, "", v); sub(/[[:space:]].*$/, "", v)
      print v; exit }' "$plan")"
  if [ -z "$wb" ]; then
    wb="$(awk '
      NR == 1 && $0 == "---" { f = 1; next }
      f && $0 == "---" { exit }
      f && /^[[:space:]]*working-branch[[:space:]]*:/ {
        v = $0; sub(/^[[:space:]]*working-branch[[:space:]]*:[[:space:]]*/, "", v); sub(/[[:space:]].*$/, "", v)
        gsub(/^["\047]|["\047]$/, "", v); print v; exit }' "$plan")"
  fi
  printf '%s' "$wb"
}

# proof_head <repo> <branch> -> the 40-hex HEAD of the checkout of <repo> that has <branch>
# checked out; exit 1 with nothing printed when no checkout holds it.
proof_head() {
  local repo="$1" branch="$2" wt
  [ -n "$branch" ] || return 1
  wt="$(git -C "$repo" worktree list --porcelain 2>/dev/null \
    | awk -v b="branch refs/heads/$branch" '/^worktree / { p = substr($0, 10) } $0 == b { print p; exit }')"
  [ -n "$wt" ] && [ -d "$wt" ] || return 1
  git -C "$wt" rev-parse --verify -q 'HEAD^{commit}' 2>/dev/null
}

# proof_last <plan> <kind> -> the head of the LAST `proved:` line of <kind> inside the plan's
# unfenced `## SDLC State`, or nothing. Later lines are newer: the writer only appends.
proof_last() {
  local plan="$1" kind="$2"
  [ -f "$plan" ] || return 0
  awk -v k="$kind" '
    /^[[:space:]]*```/ { fence = !fence; next }
    fence { next }
    /^##[[:space:]]/ { insdlc = ($0 ~ /^##[[:space:]]+SDLC State/); next }
    insdlc && /^proved:[[:space:]]/ {
      kk = ""; hh = ""
      for (i = 2; i <= NF; i++) {
        if ($i ~ /^kind=/) kk = substr($i, 6)
        else if ($i ~ /^head=/) hh = substr($i, 6)
      }
      if (kk == k && hh ~ /^[0-9a-f]+$/) last = hh
    }
    END { if (last != "") print last }' "$plan"
}

# proof_add_line <plan> <line> -> the plan with <line> placed inside `## SDLC State`: after the
# section's last `proved:` line, or, before the first proof, after the section's last
# non-blank line. Exit 1 (nothing printed) when the plan has no unfenced `## SDLC State`.
proof_add_line() {
  local plan="$1" line="$2"
  [ -f "$plan" ] || return 1
  awk -v L="$line" '
    { row[NR] = $0 }
    /^[[:space:]]*```/ { fence = !fence; next }
    fence { next }
    /^##[[:space:]]/ { insdlc = ($0 ~ /^##[[:space:]]+SDLC State/); if (insdlc) { seen = 1; lastn = NR }; next }
    insdlc && /^proved:[[:space:]]/ { lastp = NR }
    insdlc && /[^[:space:]]/ { lastn = NR }
    END {
      if (!seen) exit 1
      at = lastp ? lastp : lastn
      for (i = 1; i <= NR; i++) { print row[i]; if (i == at) print L }
    }' "$plan"
}
