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
# THE HEAD IS NEVER AN OPERAND, AND IT IS THE HEAD THE EVIDENCE READ (wave-26 T14; review 7 F1).
# `proof_attested` reads it out of the evidence itself — a full run's `head=<sha> dirty=<n>`
# header, or a review's `reviewed: <a>..<b>` line — and holds it against the checkout of the
# plan's `working-branch:`: a run must have read that checkout's head on a clean tree, a review
# a commit on its history. So a proof never names a head nobody tested, a dirty tree, or one
# that landed between the run and the verb, and a caller cannot type the head it wishes it had
# read.
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

# proof_checkout <repo> <branch> -> the path of the checkout of <repo> that has <branch> checked
# out; exit 1 with nothing printed when none does.
proof_checkout() {
  local repo="$1" branch="$2" wt
  [ -n "$branch" ] || return 1
  wt="$(git -C "$repo" worktree list --porcelain 2>/dev/null \
    | awk -v b="branch refs/heads/$branch" '/^worktree / { p = substr($0, 10) } $0 == b { print p; exit }')"
  [ -n "$wt" ] && [ -d "$wt" ] || return 1
  printf '%s' "$wt"
}

# proof_head <repo> <branch> -> the 40-hex HEAD of the checkout of <repo> that has <branch>
# checked out; exit 1 with nothing printed when no checkout holds it.
proof_head() {
  local wt
  wt="$(proof_checkout "$1" "$2")" || return 1
  git -C "$wt" rev-parse --verify -q 'HEAD^{commit}' 2>/dev/null
}

# proof_attested <kind> <evidence file> <checkout> -> the 40-hex head the evidence attests, exit
# 0; or exit 1 with one sentence on stdout saying why not and what to do (the verb's refusal).
#   floor  a full run's log: its first `head=<sha> dirty=<n>` line, the header the suite runner
#          prints before any suite. <sha> must be the checkout's HEAD and <n> 0, and the
#          runner's verdict after it must read `Gating: <n> passed, 0 failed` with no `Void:`.
#   review a review: its first `reviewed: <a>..<b>` line. <b> must resolve to a commit that is
#          the checkout's HEAD or an ancestor of it; the proof names that commit — a review of an
#          older head is a true proof of that older head, and what landed since is unread.
#   task   whichever of the two the evidence carries, the run header first (A-T14.9).
proof_attested() {
  local kind="$1" ev="$2" co="$3" head stamp sha dirty rng b bh verdict
  head="$(git -C "$co" rev-parse --verify -q 'HEAD^{commit}' 2>/dev/null)" \
    || { printf 'the checkout %s has no head to hold the evidence against' "$co"; return 1; }
  stamp="$(awk '/^head=([0-9a-f]+|none) dirty=([0-9]+|none)$/ { print; exit }' "$ev" 2>/dev/null)"
  rng="$(awk '/^reviewed:[ \t]/ { sub(/^reviewed:[ \t]+/, ""); sub(/[ \t].*$/, ""); print; exit }' "$ev" 2>/dev/null)"
  case "$kind" in
    floor) rng="" ;;
    review) stamp="" ;;
    task) [ -n "$stamp" ] && rng="" ;;
  esac
  if [ -n "$stamp" ]; then
    sha="${stamp#head=}"; sha="${sha%% *}"; dirty="${stamp##*dirty=}"
    if [ "$sha" = none ]; then
      printf 'the run in %s read no repository (head=none); run it in the working branch checkout and cite that log' "$ev"; return 1
    fi
    if [ "$sha" != "$head" ]; then
      printf 'the run in %s read head %s, but the working branch is at %s; run it again on %s and cite that log' \
        "$ev" "$(printf '%s' "$sha" | cut -c1-12)" "$(printf '%s' "$head" | cut -c1-12)" "$(printf '%s' "$head" | cut -c1-12)"; return 1
    fi
    if [ "$dirty" != 0 ]; then
      printf 'the run in %s read a dirty tree (dirty=%s); commit, run it again and cite that log' "$ev" "$dirty"; return 1
    fi
    # THE RUN MUST ALSO HAVE PASSED (wave-26 T5; review 10 F1). A header says which head a run
    # read, not how it ended: a red run, or a note that quotes the header, attests the head all
    # the same, and the full-run wall reads a proved head as needing no run. So the runner's own
    # verdict, `Gating: <n> passed, <m> failed` (tests/run.sh), must follow the header with n > 0
    # and m = 0. The LAST such line is the runner's: a suite's captured output can hold an inner
    # run's verdict above it. A `Void:` line refuses too (A-T5.15): a void suite is counted in
    # neither tally, so `0 failed` does not yet say it passed.
    verdict="$(awk '
      !seen && /^head=([0-9a-f]+|none) dirty=([0-9]+|none)$/ { seen = 1; next }
      seen && /^Gating: [0-9]+ passed, [0-9]+ failed$/ { v = $2 " " $4 }
      seen && /^Void: / { void = 1 }
      END { if (v == "") print "none"; else print v " " (void + 0) }' "$ev" 2>/dev/null)"
    case "$verdict" in
      none|'')
        printf 'the run in %s has no Gating: <n> passed, <m> failed verdict after its head= line; cite the whole log of a full run that finished' "$ev"; return 1 ;;
    esac
    set -- $verdict
    if [ "$2" != 0 ] || [ "$1" = 0 ]; then
      printf 'the run in %s did not pass (Gating: %s passed, %s failed); fix it, run it again and cite that log' "$ev" "$1" "$2"; return 1
    fi
    if [ "$3" != 0 ]; then
      printf 'the run in %s left a suite void (its Void: line); re-run it on a quiet machine and cite that log' "$ev"; return 1
    fi
    printf '%s' "$head"; return 0
  fi
  if [ -n "$rng" ]; then
    case "$rng" in
      *..*) b="${rng##*..}" ;;
      *) b="" ;;
    esac
    case "$b" in
      ''|*[!0-9a-fA-F]*)
        printf 'the review in %s names no range a..b (reviewed: %s); write the commits it read as reviewed: <a>..<b>' "$ev" "$rng"; return 1 ;;
    esac
    bh="$(git -C "$co" rev-parse --verify -q "$b^{commit}" 2>/dev/null)" \
      || { printf 'the review in %s read up to %s, which is no commit here; name the commit it read' "$ev" "$b"; return 1; }
    if ! git -C "$co" merge-base --is-ancestor "$bh" "$head" 2>/dev/null; then
      printf 'the review in %s read up to %s, which is not on the working branch (at %s); review that branch and name its commit' \
        "$ev" "$(printf '%s' "$bh" | cut -c1-12)" "$(printf '%s' "$head" | cut -c1-12)"; return 1
    fi
    printf '%s' "$bh"; return 0
  fi
  case "$kind" in
    floor) printf 'the evidence %s carries no head=<sha> dirty=<n> line; a floor proof cites the log of a full run, whose header prints it' "$ev" ;;
    review) printf 'the evidence %s carries no reviewed: <a>..<b> line; a review proof cites a review whose header names the range it read' "$ev" ;;
    *) printf 'the evidence %s carries neither a head=<sha> dirty=<n> run header nor a reviewed: <a>..<b> line; cite a run log or a review' "$ev" ;;
  esac
  return 1
}

# proof_awk -> the awk function `proof_fields(s)`, THE ONE READING OF A PROOF LINE (wave-26 T14;
# review 7 F6): 1 when <s> is a proof line, its kind in PROOF_KIND and its head in PROOF_HEAD.
# A proof line starts `proved:` at the first column (a bulleted `- proved:` is prose, not the
# line the writer writes), and carries `kind=<lower-case word>` and `head=<7 to 40 lower-case
# hex>` among its space-separated fields (`head=none` is no head). `proof_last` and the
# readiness program (units.sh) both read through it, so a line one counts the other counts.
proof_awk() {
  printf '%s' '
    function proof_fields(s,   f, m, i) {
      PROOF_KIND = ""; PROOF_HEAD = ""
      if (s !~ /^proved:[ \t]/) return 0
      m = split(s, f, /[ \t]+/)
      for (i = 2; i <= m; i++) {
        if (f[i] ~ /^kind=/) PROOF_KIND = substr(f[i], 6)
        else if (f[i] ~ /^head=/) PROOF_HEAD = substr(f[i], 6)
      }
      return (PROOF_KIND ~ /^[a-z]+$/ && PROOF_HEAD ~ /^[0-9a-f]+$/ && length(PROOF_HEAD) >= 7 && length(PROOF_HEAD) <= 40)
    }
  '
}

# proof_last <plan> <kind> -> the head of the LAST `proved:` line of <kind> inside the plan's
# unfenced `## SDLC State`, or nothing. Later lines are newer: the writer only appends.
proof_last() {
  _proof_last_read "$1" "$2" head
}

# proof_last_line <plan> <kind> -> that same last line, whole, or nothing: what a refusal quotes
# when it names the proof it read (head and evidence), so no caller parses the plan itself.
proof_last_line() {
  _proof_last_read "$1" "$2" line
}

# _proof_last_read <plan> <kind> <head|line> -> the one reader behind the two above.
_proof_last_read() {
  local plan="$1" kind="$2" what="$3"
  [ -f "$plan" ] || return 0
  awk -v k="$kind" -v what="$what" "$(proof_awk)"'
    /^[[:space:]]*```/ { fence = !fence; next }
    fence { next }
    /^##[[:space:]]/ { insdlc = ($0 ~ /^##[[:space:]]+SDLC State/); next }
    insdlc && proof_fields($0) && PROOF_KIND == k { last = PROOF_HEAD; lastline = $0 }
    END { if (last != "") print (what == "line" ? lastline : last) }' "$plan"
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

# proof_state <plan> <tree> -> what the change since the last floor proof needs, one line:
#
#     covered                          the working branch's head is the one the proof names
#     bounded<TAB><suite> <suite>…     every changed file has a non-empty answer from the map,
#                                      the union is not every suite, and no commit in the range
#                                      is on another branch
#     unbounded<TAB><reason>           anything else, the reason in words
#
# (wave-26 T5; REQ-3, D6.) THE ONE PLACE THAT RUNS GIT FOR THE FULL-RUN DECISION. The dispatch
# wall asks this and judges nothing itself. <tree> is the project root: its `.bionic/config.yaml`
# names the map (`impact-command:`), and its repository holds the working branch's checkout,
# where the head is read, the map runs and the suite roster is counted.
#
# UNBOUNDED IS THE SAFE DIRECTION. It admits a full run; a wrong `bounded` would refuse one the
# change needed. So every question this cannot answer — no proof yet, no checkout, a map that
# fails or overruns — answers `unbounded` and says which question it was.
#
# THE STEPS, CHEAPEST FIRST: the proof line; the head; one `git diff --name-only --no-renames`
# over the range (a rename is its two paths, and the old side is often the wider answer); two
# `rev-list --count` calls for the outside test; one map call over every changed file.
#
# AN OUTSIDE COMMIT is one some branch other than the working branch and the run's task
# branches contains (research R7 §5, which found commit subjects unreliable). The task branches
# are `wt/<NN>-*`, NN read from a `wave/<NN>-…` working branch, the convention spawn-worktree
# and close-out share; a working branch of any other shape excludes only itself, which reads
# the run's own task branches as outside — the safe direction again.
proof_state() {
  local plan="$1" tree="$2" h c wb wt files nn total rest cmd tmp lst pid over rc roster ans
  local d
  h="$(proof_last "$plan" floor)"
  [ -n "$h" ] || { printf 'unbounded\tno floor proof on this plan yet\n'; return 0; }
  wb="$(proof_working_branch "$plan")"
  [ -n "$wb" ] || { printf 'unbounded\tthe plan names no working-branch\n'; return 0; }
  wt="$(proof_checkout "$tree" "$wb")" \
    || { printf 'unbounded\tno checkout holds the working branch %s\n' "$wb"; return 0; }
  c="$(git -C "$wt" rev-parse --verify -q 'HEAD^{commit}' 2>/dev/null)" \
    || { printf 'unbounded\tthe head of %s cannot be read\n' "$wb"; return 0; }
  h="$(git -C "$wt" rev-parse --verify -q "${h}^{commit}" 2>/dev/null)" \
    || { printf 'unbounded\tthe proved head is not a commit here\n'; return 0; }
  [ "$h" != "$c" ] || { printf 'covered\n'; return 0; }
  git -C "$wt" merge-base --is-ancestor "$h" "$c" 2>/dev/null \
    || { printf 'unbounded\tthe proved head %.7s is not in the history of %s\n' "$h" "$wb"; return 0; }
  files="$(git -C "$wt" diff --name-only --no-renames "$h" "$c" 2>/dev/null)" \
    || { printf 'unbounded\tgit cannot list the change since %.7s\n' "$h"; return 0; }
  # NO FILE CHANGED: the tree is the one the proof read, so it is covered whatever the commits.
  [ -n "$files" ] || { printf 'covered\n'; return 0; }

  nn="$(printf '%s' "$wb" | sed -nE 's#^wave/([0-9]+)-.*#\1#p')"
  total="$(git -C "$wt" rev-list --count "$h..$c" 2>/dev/null)"
  if [ -n "$nn" ]; then
    rest="$(git -C "$wt" rev-list --count "$h..$c" --not --exclude="$wb" --exclude="wt/${nn}-*" --branches 2>/dev/null)"
  else
    rest="$(git -C "$wt" rev-list --count "$h..$c" --not --exclude="$wb" --branches 2>/dev/null)"
  fi
  case "$total$rest" in ''|*[!0-9]*)
    printf 'unbounded\tgit cannot count the commits since %.7s\n' "$h"; return 0 ;;
  esac
  if [ "$rest" -lt "$total" ]; then
    printf 'unbounded\t%s of %s commits since %.7s are on another branch than %s and its task branches (a merge from outside the run)\n' \
      "$((total - rest))" "$total" "$h" "$wb"
    return 0
  fi

  d="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P)"
  if ! declare -F config_value >/dev/null 2>&1; then
    # shellcheck source=/dev/null
    . "$d/roots.sh" >/dev/null 2>&1
  fi
  if [ -z "${IMPACT_BOUND_S:-}" ]; then
    # shellcheck source=/dev/null
    . "$d/bounds.sh" >/dev/null 2>&1
  fi
  cmd="$(config_value "$tree" impact-command "" 2>/dev/null)"
  [ -n "$cmd" ] || { printf 'unbounded\tno impact-command is configured to map the change to suites\n'; return 0; }
  roster="$(ls "$wt"/tests/*.test.sh 2>/dev/null | wc -l | tr -d ' ')"
  [ "${roster:-0}" -gt 0 ] 2>/dev/null \
    || { printf 'unbounded\tthe working checkout has no suite roster (tests/*.test.sh) to count against\n'; return 0; }

  # THE MAP, BOUNDED THE WAY brief.sh BOUNDS ITS DERIVATION: a backgrounded child, a clock, a
  # kill. It runs in the working checkout, so a file the change added is a file the map can see.
  tmp="${TMPDIR:-/tmp}/bionic-proof-$$-${RANDOM}"
  lst="$tmp.files"; printf '%s\n' "$files" > "$lst"
  (
    cd "$wt" 2>/dev/null || exit 1
    set -f
    # The files split one per line, a path with a space whole; the COMMAND is configuration
    # and splits on blanks, as brief.sh runs it.
    IFS='
'
    # shellcheck disable=SC2086
    set -- $files
    unset IFS
    # shellcheck disable=SC2086
    $cmd "$@" > "$tmp.out" 2>/dev/null
  ) &
  pid=$!
  SECONDS=0; over=0
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$SECONDS" -ge "${IMPACT_BOUND_S:-10}" ]; then kill -TERM "$pid" 2>/dev/null; over=1; break; fi
    sleep 0.1
  done
  wait "$pid" 2>/dev/null; rc=$?
  if [ "$over" -eq 1 ]; then
    rm -f "$tmp.out" "$lst"
    printf 'unbounded\tthe map overran its %s s bound\n' "${IMPACT_BOUND_S:-10}"; return 0
  fi
  if [ "$rc" -ne 0 ]; then
    rm -f "$tmp.out" "$lst"
    printf 'unbounded\tthe map failed (exit %s)\n' "$rc"; return 0
  fi
  # ONE PASS OVER THE ANSWER. A line is `<suite><TAB><reason>:<file>`; a file is answered when a
  # line names it after the reason. The first file nobody answers is the reason, in table
  # order; otherwise the suites, sorted, or every suite.
  ans="$(awk -F'\t' -v roster="$roster" '
    FILENAME == ARGV[1] { if ($0 != "") order[++n] = $0; next }
    $1 != "" {
      if (!($1 in s)) { s[$1] = 1; ns++ }
      p = index($2, ":"); if (p) got[substr($2, p + 1)] = 1
    }
    END {
      for (i = 1; i <= n; i++) if (!(order[i] in got)) { print "none\t" order[i]; exit }
      if (ns >= roster) { print "every\t" ns; exit }
      for (k in s) print "suite\t" k
    }' "$lst" "$tmp.out" 2>/dev/null)"
  rm -f "$tmp.out" "$lst"
  case "$ans" in
    none*)  printf 'unbounded\tthe map answers %s with no suite\n' "${ans#*$'\t'}"; return 0 ;;
    every*) printf 'unbounded\tthe map answers the change with every suite (%s of %s)\n' "${ans#*$'\t'}" "$roster"; return 0 ;;
    '')     printf 'unbounded\tthe map gave no answer\n'; return 0 ;;
  esac
  printf 'bounded\t%s\n' "$(printf '%s\n' "$ans" | cut -f2 | sort | tr '\n' ' ' | sed 's/ $//')"
}
