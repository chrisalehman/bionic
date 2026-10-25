#!/bin/bash
# payload/scripts/lib/line.sh — THE LANDING LINE (wave-28 T3; spec D1, D2, D6, D9, D31; ADR-045).
#
# WHAT THIS FILE OWNS. A landing is a candidate: the row's commit merged onto a base, built in a
# landing tree the tool owns (lib/worktree.sh `landing_tree_take`), and published by a
# fast-forward of the working branch to it under one lock. The line is the order of `ready` events
# in the landing record; its state is a fold over that record, never a second store.
#
#   line_record <plan>              the landing record's path (wave-27's `landing-proofs.log`)
#   line_event <plan> <ev> <k=v>... appends one `line/v1|ev=<ev>|<k=v>|…|at=<ISO-UTC>` line
#   line_state <plan>               the open entries, in record order (below)
#   line_head <plan>                the accepted head: the working branch's tip
#   line_build <tree> <base> <commit> <branch>   the candidate, merged in a landing tree
#   line_publish <plan> <row>       the one publish, under the lock, in the interface's order
#   line_land_by_hand <tree> <root> <sid> <why> [<suites> <green-at> <log>]  `spawn-worktree.sh land <tree> --by-hand`
#   line_ready <tree> <root> <sid> <within> <again>  `spawn-worktree.sh ready [--within <s>]` (T4)
#   line_reviews_state <plan> <root> <commit> <name> <out>   the release entry's `### The reviews`, rendered from the
#                                   plan (with line_reviews_checkout, line_reviews_commit, line_reviews_move)
#
# THE RECORD. One append per line, by the landing record's one write (`_wt_proofs_put`: a private
# file copied by one write(2), no lock), so two writers' lines never interleave. Nine events:
#   ready     row name commit branch tree suites debt carrier age   (a carrier is `<pid>:<start>`; age
#             `<first>:<seq>`, the lease the gate orders the entry by, wave-38 T30)
#   candidate row base commit tree
#   verdict   row commit suite result log admitted width   (green | red | none | discarded | absent: a
#             suite the candidate's base holds and the candidate does not, log `-`); a
#             verdict is keyed by the commit it ran at and nothing else
#   standing  head suite lines log cause against   (cause: environment | code; against: the run that
#             disagrees, `<stamp|verdict>:<commit>@<at>`, or `-`; wave-33 T2, AC-7.2)
#   returned  row why detail                   (red | conflict | guard)
#   stalled   row logs
#   published row commit kind by why [numbers] (queue | hand | git; numbers: the commit on the candidate that
#             carries the release numbers re-rendered at a landing past the release, the head the branch
#             moved to, `_line_numbers`)
#   stop-run  request who kind key by why, or run name by why   (hooks/session-poker.sh `stop-run`,
#             through `line_event`; wave-36 T11, D8): an act, not an entry's — the fold below reads no
#             row from it, and the hand-hold count (`hand_holds_report`) counts it as `stop-runs`
#   integrate row part commit branch, and close-out part commit branch   (part=reviews: the commit of the release
#             entry's reviews part, by the verb that made it, `line_reviews_state`): acts, read by no fold
# A value holding `|` or a line break is refused unwritten: the line is `|`-separated.
#
# THE FOLD. `line_state` prints one tab-separated line per entry neither published nor returned:
#   <row> <name> <commit> <present yes|no> <base> <candidate> <outcome> <suites>
# An entry opens at a `ready` for a row with no open entry; a later `ready` for the open row
# replaces its fields and keeps its place. It closes at a `published` or `returned` naming its row.
# Present is its carrier alive (the pid and start-time rule of lib/slots.sh). The base is the base
# rule's: the candidate of the nearest earlier entry that is present and not stalled, else the
# accepted head; `-` while that entry has no candidate yet (the entry waits). The candidate is its
# latest `candidate` event's commit, `-` before one. The outcome: stalled (a `stalled` event after
# its candidate and its latest `ready`: a writer who says ready again has the entry carried again),
# waiting (no candidate), green (every suite green on the candidate, or `none`),
# declared (every red is the declared debt suite), standing (every red is a suite a `standing`
# event names at the candidate's base), else proving.
#
# A PLAIN GIT MERGE IS COUNTED (D9, AC-5.3). When the accepted head is a commit no `published` line
# names, the fold first appends `published kind=git` for each open entry whose commit the head
# contains, and for each plan row whose tree's head it brought: contained in the head and not in
# the newest commit a `published` line names (the head's first parent before any), and not the
# commit the tree was cut at (`_line_cut_at`; a tree with no commit of its own landed nothing). It never does
# so while a live holder has the publish lock, since a publish between its fast-forward and its
# own `published` event would otherwise be counted twice.
#
# bash 3.2 (ADR-001): no associative arrays in bash, no BASHPID; the fold is one awk.

_line_self_dir() { dirname "${BASH_SOURCE[0]}"; }
_LINE_LIB_DIR="$( cd "$(_line_self_dir)" 2>/dev/null && pwd -P )"
if ! declare -F _wt_proofs_put >/dev/null 2>&1; then
  # shellcheck source=/dev/null
  . "$_LINE_LIB_DIR/worktree.sh"
fi
# THE LIVENESS RULE IS slots.sh's (`_slots_alive`, `_slots_since`) and so is the lock's take-over
# (`_slots_take_one`: mkdir, then a dead holder reaped under the store's reap lock, once).
if ! declare -F _slots_take_one >/dev/null 2>&1; then
  # shellcheck source=/dev/null
  . "$_LINE_LIB_DIR/slots.sh"
fi
# HOW A SUITE RUNS IS suite.sh's (wave-33 T2; D3): the landing's two spawns, the runner and its suite,
# are jobs of their own (`bionic_job`, `bionic_suite_start`), so the suite starts as the whole run starts it.
if ! declare -F bionic_suite_start >/dev/null 2>&1; then
  # shellcheck source=/dev/null
  . "$_LINE_LIB_DIR/suite.sh"
fi

# What the caller of `line_publish` says it is: the queue's carrier (`ready`) by default; the hand
# landing sets kind=hand, the git user and the reason. Both set the session the publish's plan write
# and roster mark run under (LINE_SID; wave-28 T6).
LINE_KIND="queue"; LINE_BY="-"; LINE_WHY="-"; LINE_SID=""; LINE_MARKED=""
LINE_PROMISED=-; LINE_ACTUAL=-   # the last run's promised and actual seconds (wave-39 T8), set as LINE_AT is

# THE SUITE BAR (wave-39 T6; D1; spec §3 "the two bars"): ten minutes of the gate's promise (`_gate_seconds`).
# Defined here and nowhere else; `ready` refuses a Lands-on suite promising more (`_line_too_long`, wave-39 T39).
LINE_SUITE_BAR=600
# THE LANDING BAR (wave-39 T9; D12, D25; AC-5.1, AC-5.2): fifteen minutes ready→landed. The sitrep's schedule
# line prints the run's median ready→landed against it, and the scorecard's widest landing names it as its
# target; both read it through session-poker.sh `sitrep_bar`, and nothing else defines it.
LINE_LANDING_BAR=15

_line_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
_line_pid() { exec sh -c 'echo "$PPID"'; }   # as `$(_line_pid)`: this (sub)shell's own pid, which `$$` is not
_line_me() {  # sets LINE_ME to `<pid>:<start>` of the calling (sub)shell; never call it inside `$( )`
  local p; p="$(_line_pid)"
  LINE_ME="${p}:$(_slots_since "$p")"
}
_line_alive() {  # <pid>:<start> -> 0 while that process lives and started then
  local p="${1%%:*}" s="${1#*:}" now
  case "$p" in ''|*[!0-9]*) return 1 ;; esac
  _slots_alive "$p" || return 1
  now="$(_slots_since "$p")"
  [ -z "$now" ] || [ -z "$s" ] || [ "$now" = "$s" ]
}

_line_root() {  # <plan> -> the project root the plan belongs to
  local d
  d="$(cd "$(dirname "${1:-}")" 2>/dev/null && pwd -P)" || return 1
  worktree_root "$d"
}
line_record() {  # <plan> -> the landing record's path
  local root
  root="$(_line_root "${1:-}")" || return 1
  _wt_proofs_path "$root" "$1"
}
_line_load_run() {
  declare -F plan_working_branch >/dev/null 2>&1 && return 0
  # shellcheck source=/dev/null
  [ -r "$_LINE_LIB_DIR/run.sh" ] && . "$_LINE_LIB_DIR/run.sh" 2>/dev/null
  declare -F plan_working_branch >/dev/null 2>&1
}
# The plan's working branch through lib/run.sh `plan_working_branch`, the one reader: SDLC State, then
# frontmatter (wave-35 T7; D14). It read the frontmatter alone, so the publish disagreed with `ready`.
_line_branch() {  # <plan> -> its working-branch
  _line_load_run || return 1
  plan_working_branch "$1"
}
# The accepted head is the working branch's REF, read by lib/proof.sh `proof_branch_head`, the one reader of the
# head the judge, proof-add, waive and deliver ask (wave-36 T12; D13; burns debt `working-head`): this read the
# ref by hand, a second spelling of the same question.
_line_load_proof() {
  declare -F proof_branch_head >/dev/null 2>&1 && return 0
  # shellcheck source=/dev/null
  [ -r "$_LINE_LIB_DIR/proof.sh" ] && . "$_LINE_LIB_DIR/proof.sh" 2>/dev/null
  declare -F proof_branch_head >/dev/null 2>&1
}
line_head() {  # <plan> -> the accepted head
  local root
  root="$(_line_root "${1:-}")" && _line_load_proof || return 1
  proof_branch_head "$1" "$root"
}

# THE RECORD'S READER (wave-39 T17; D18, AC-12.1; burns debt landing-record-grammar): the one reading of a line
# `line_event` writes, as awk functions a program prefixes and runs with -F'|'. Every field is read by its name,
# never by its place, so a field the writer adds or moves is still read; the first `<key>=` of a line is its value.
#   line_ev()     the line's event (`ev=`), or nothing on a line that is not `line/v1|`
#   line_kv(k)    the value of the line's field <k>, or nothing
# Every reader of the record reads through it: the fold and the readers below, lib/gate.sh's finished-row read, lib/proof.sh's
# readers of verdicts, runs, landings and debts, and the poker's parts. A shell caller holding one line asks `line_value`.
# The body reads any line whose fields are split by FS, so a whitespace-split `debt:` line reads through it too.
_LINE_FIELDS_AWK='
function line_kv(k,   i) { for (i = 2; i <= NF; i++) if (index($i, k "=") == 1) return substr($i, length(k) + 2); return "" }
function line_ev() { return (substr($0, 1, 8) == "line/v1|") ? line_kv("ev") : "" }
'
line_value() {  # <one record line> <key> -> the value of its field <key>, through line_kv
  printf '%s\n' "$1" | awk -F'|' -v k="$2" "$_LINE_FIELDS_AWK"'{ print line_kv(k); exit }'
}
line_event() {  # <plan> <ev> <key=value>... -> 0 appended, 1 not
  local plan="${1:-}" ev="${2:-}" rec line f
  [ -n "$plan" ] && [ -n "$ev" ] || return 1
  shift 2
  line="line/v1|ev=${ev}"
  for f in "$@"; do
    case "$f" in *'|'*|*$'\n'*|*$'\r'*) return 1 ;; esac
    line="${line}|${f}"
  done
  rec="$(line_record "$plan")" || return 1
  mkdir -p "${rec%/*}" 2>/dev/null || return 1
  _wt_proofs_put "$rec" "${line}|at=$(_line_now)"
}

# The fold's raw form, one tab-separated line per open entry, in record order:
#   row name commit carrier candidate cbase cat outcome suites branch tree greens
# greens (wave-39 T10; AC-6.3) is how many of its suites are green (or absent) on its candidate, 0 before one: the
# sitrep's `in its landing, <greens> of <suites> suites green`.
_line_fold() {  # <record>
  [ -f "$1" ] || return 0
  awk -F'|' "$_LINE_FIELDS_AWK"'
    { ev = line_ev() }
    ev == "" { next }
    {
      row = line_kv("row")
      if (ev == "ready") {
        e = cur[row]
        if (e == "" || !open[e]) { e = ++n; cur[row] = e; open[e] = 1; rowof[e] = row; cand[e] = "" }
        stl[e] = 0
        name[e] = line_kv("name"); com[e] = line_kv("commit"); car[e] = line_kv("carrier"); sui[e] = line_kv("suites")
        debt[e] = line_kv("debt"); br[e] = line_kv("branch"); tr[e] = line_kv("tree")
      } else if (ev == "candidate") {
        e = cur[row]; if (e == "" || !open[e]) next
        cand[e] = line_kv("commit"); cbase[e] = line_kv("base"); cat[e] = line_kv("at"); stl[e] = 0
      } else if (ev == "verdict") {
        e = cur[row]; if (e == "" || !open[e]) next
        v[e, line_kv("commit"), line_kv("suite")] = line_kv("result")
      } else if (ev == "stalled") {
        e = cur[row]; if (e != "" && open[e]) stl[e] = 1
      } else if (ev == "published" || ev == "returned") {
        e = cur[row]; if (e != "" && open[e]) open[e] = 0
      } else if (ev == "standing") {
        stand[line_kv("head"), line_kv("suite")] = 1
      }
    }
    END {
      for (e = 1; e <= n; e++) {
        if (!open[e]) continue
        c = cand[e]
        if (stl[e]) out = "stalled"
        else if (c == "") out = "waiting"
        else {
          miss = 0; unx = 0; dec = 0; std = 0
          s = sui[e]
          if (s != "none" && s != "") {
            m = split(s, names, ",")
            for (j = 1; j <= m; j++) {
              r = v[e, c, names[j]]
              if (r == "green" || r == "absent") { grn[e]++; continue }
              if (r == "red") {
                if (names[j] == debt[e]) dec = 1
                else if ((cbase[e], names[j]) in stand) std = 1
                else unx = 1
              } else miss = 1
            }
          }
          if (miss || unx) out = "proving"; else if (std) out = "standing"; else if (dec) out = "declared"; else out = "green"
        }
        printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%d\n", rowof[e], name[e], com[e], car[e], \
          (c == "" ? "-" : c), (cbase[e] == "" ? "-" : cbase[e]), (cat[e] == "" ? "-" : cat[e]), out, \
          (sui[e] == "" ? "none" : sui[e]), br[e], tr[e], grn[e]
      }
    }' "$1" 2>/dev/null
}

# The fold with presence and the base rule applied: the interface's eight fields, then the raw
# fields line_publish needs (carrier, the candidate's own base and time, branch, tree).
_line_entries() {  # <record> <accepted head>
  local rec="$1" head="$2" row name com car cand cbase cat out sui br tr _gr present base prev="$2"
  while IFS=$'\t' read -r row name com car cand cbase cat out sui br tr _gr; do
    [ -n "$row" ] || continue
    if _line_alive "$car"; then present=yes; else present=no; fi
    base="$prev"
    if [ "$present" = yes ] && [ "$out" != stalled ]; then prev="$cand"; fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$row" "$name" "$com" "$present" "$base" "$cand" "$out" "$sui" "$car" "$cbase" "$cat" "$br" "$tr"
  done <<EOF
$(_line_fold "$rec")
EOF
}

_line_lock_dir() { printf '%s/publish.lock' "${1%/*}"; }   # <record> -> the lock's directory
_line_lock_live() {  # <record> -> 0 when a live holder has the publish lock
  local h=""
  { read -r h < "$(_line_lock_dir "$1")/holder"; } 2>/dev/null
  [ -n "$h" ] && _line_alive "$h"
}

# A PLAIN GIT MERGE, COUNTED (see the header).
_line_count_git() {  # <plan> <record> <root> <accepted head>
  local plan="$1" rec="$2" root="$3" head="$4" named last row com rec_row cell tree tip
  [ -n "$head" ] && [ -f "$rec" ] || return 0
  # A numbers commit is a head the line itself published, named as its candidate is.
  named="$(awk -F'|' "$_LINE_FIELDS_AWK"'line_ev() == "published" { c = line_kv("commit"); if (c != "") print c
    c = line_kv("numbers"); if (c != "") print c }' "$rec" 2>/dev/null)"
  case $'\n'"${named}"$'\n' in *$'\n'"${head}"$'\n'*) return 0 ;; esac
  _line_lock_live "$rec" && return 0
  while IFS=$'\t' read -r row _ com _; do
    [ -n "$row" ] && [ -n "$com" ] || continue
    git -C "$root" merge-base --is-ancestor "$com" "$head" 2>/dev/null \
      && line_event "$plan" published "row=${row}" "commit=${head}" kind=git by=- why=- >/dev/null
  done <<EOF
$(_line_fold "$rec")
EOF
  last="$(printf '%s\n' "$named" | awk 'NF { l = $0 } END { print l }')"
  [ -n "$last" ] || last="$(git -C "$root" rev-parse --verify -q "${head}^1" 2>/dev/null)"
  _wt_units_load || return 0
  while IFS= read -r rec_row; do
    row="$(units_field "$rec_row" id)"; cell="$(units_field "$rec_row" worktree)"
    case "$row" in ''|*[[:space:]\|]*) continue ;; esac
    case "$cell" in ''|-|—) continue ;; /*) tree="$cell" ;; *) tree="${root}/${cell#./}" ;; esac
    [ -d "$tree" ] || continue
    tip="$(git -C "$tree" rev-parse --verify -q HEAD 2>/dev/null)" || continue
    # A TREE AT ITS CUT HAS LANDED NOTHING (ruling A-orch-39): it is neither counted nor skipped.
    [ "$tip" != "$(_line_cut_at "$root" "$(units_field "$rec_row" base)" "$tree" "$head")" ] || continue
    awk -F'|' -v r="$row" "$_LINE_FIELDS_AWK"'line_ev() == "published" && line_kv("row") == r { f = 1 } END { exit !f }' "$rec" 2>/dev/null && continue
    git -C "$root" merge-base --is-ancestor "$tip" "$head" 2>/dev/null || continue
    [ -n "$last" ] && git -C "$root" merge-base --is-ancestor "$tip" "$last" 2>/dev/null && continue
    line_event "$plan" published "row=${row}" "commit=${head}" kind=git by=- why=- >/dev/null
  done <<EOF
$(units_rows "$plan" 2>/dev/null)
EOF
}

# The commit a row's tree was cut at: the plan row's `base` cell when it names a commit, else the oldest
# entry of the tree's branch's reflog (the create), else its merge-base with the accepted head.
_line_cut_at() {  # <root> <base cell> <tree> <accepted head>
  local c b
  case "$2" in ''|-|—) : ;; *) c="$(git -C "$1" rev-parse --verify -q "${2}^{commit}" 2>/dev/null)" && { printf '%s' "$c"; return 0; } ;; esac
  b="$(git -C "$3" symbolic-ref -q HEAD 2>/dev/null)" \
    && c="$(git -C "$1" log -g --format=%H "$b" -- 2>/dev/null | tail -1)" && [ -n "$c" ] && { printf '%s' "$c"; return 0; }
  git -C "$1" merge-base "$(git -C "$3" rev-parse --verify -q HEAD 2>/dev/null)" "$4" 2>/dev/null
}

line_state() {  # <plan> -> the open entries (see the header)
  local plan="${1:-}" rec root head
  rec="$(line_record "$plan")" || return 1
  root="$(_line_root "$plan")" || return 1
  head="$(line_head "$plan")" || head=""
  _line_count_git "$plan" "$rec" "$root" "$head"
  _line_entries "$rec" "$head" | cut -f1-8
}

# THE CANDIDATE (D1): the row's commit merged --no-ff onto <base> in a landing tree, the merge's
# message land's own. Prints the candidate; on a conflict prints the files, aborts, and returns 1.
line_build() {  # <landing tree> <base> <row commit> <branch> -> candidate | files
  local t="$1" said files
  landing_tree_point "$t" "$2" || return 2
  if said="$(LC_ALL=C git -C "$t" merge --no-ff -q -m "merge ${4} (land)" "$3" 2>&1)"; then
    git -C "$t" rev-parse --verify -q HEAD
    return 0
  fi
  files="$(git -C "$t" diff --name-only --diff-filter=U 2>/dev/null | head -5 | tr '\n' ',' | sed 's/,$//')"
  git -C "$t" merge --abort >/dev/null 2>&1
  printf '%s' "${files:-${said%%$'\n'*}}"
  return 1
}

# ---------------------------------------------------------------------------- the publish
# THE PUBLISH LOCK (D6): `<record dir>/publish.lock`, made by mkdir, its `holder` `<pid>:<start>`
# beside slots.sh's own `pid` and `since`; a lock whose holder is not alive is taken over by
# `_slots_take_one`. A wait longer than BIONIC_LINE_LOCK_WAIT seconds (900) is rc 75, said.
_line_lock_take() {  # <lock dir> <row> -> 0 held (by this shell), 75 when the wait ran out
  local lk="$1" i=0 n
  n="${BIONIC_LINE_LOCK_WAIT:-900}"; case "$n" in ''|*[!0-9]*) n=900 ;; esac
  _line_me
  while ! _slots_take_one "${lk%/*}" "$lk" "${LINE_ME%%:*}" "publish"; do
    i=$((i + 1))
    if [ "$i" -gt $((n * 10)) ]; then printf 'BUSY %s — publish.lock held by %s\n' "$2" "$(cat "$lk/holder" 2>/dev/null)"; return 75; fi
    sleep 0.1
  done
  printf '%s\n' "$LINE_ME" > "$lk/holder"
}
# Each step of the publish that refuses is one call that says why, drops the lock and returns its
# code, so `line_publish` reads as the interface's order, one line a step.
_line_first_in_line() {  # <first present row> <row> <lock> -> 0, or 3
  [ "$1" = "$2" ] && return 0
  _line_lock_drop "$3"; printf 'REBUILD %s — %s is first in line\n' "$2" "${1:-no entry}"; return 3
}
_line_on_head() {  # <row> <candidate> <its base> <accepted head> <lock> -> 0, or 3
  [ -n "$2" ] && [ "$2" != - ] && [ "$3" = "$4" ] && return 0
  _line_lock_drop "$5"; printf 'REBUILD %s — candidate base %s is not the accepted head %s\n' "$1" "${3:--}" "${4:--}"; return 3
}
_line_guard() {  # <plan> <row> <root> <head> <candidate> <writer tree> <writer branch> <onto> <lock> -> 0, or 6
  local why
  why="$(_wt_bionic_committed "$3" "$4" "$5")" || return 0
  why="${why%/}"
  _wt_refuse_bionic "$6" "$7" "$8" "${why%% *}" "${why#* }" "$(_wt_bionic_kind "$3" "$4")"
  line_event "$1" returned "row=${2}" why=guard "detail=${why#* }" >/dev/null
  _line_lock_drop "$9"; return 6
}
_line_lock_drop() { _slots_drop "${1%/*}" "$1"; }   # <lock dir>

# A LIVE RUN IN THE CHECKOUT THAT HOLDS THE BRANCH (AC-3.6): an admitted, unended gate request whose
# `tree=` is that checkout and whose holder lives, or, as before the gate, a `tests/run.sh` whose
# script or working directory is there. A checkout nested in it (a row tree under `.worktrees/`, a
# landing tree under `.bionic/tmp/landing/`) is not it: a run there holds nothing.
_line_live_run() {  # <root> <checkout> -> what holds it
  local root="$1" co="$2" dir f k tr ad en ho nested
  dir="${BIONIC_GATE_DIR:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/bionic/gate}/requests"
  for f in "$dir"/*; do
    [ -f "$f" ] || continue
    k="$(sed -n 's/^key=//p' "$f" | head -1)"; tr="$(sed -n 's/^tree=//p' "$f" | head -1)"
    ad="$(sed -n 's/^admitted=//p' "$f" | head -1)"; en="$(sed -n 's/^ended=//p' "$f" | head -1)"
    ho="$(sed -n 's/^holder=//p' "$f" | head -1)"
    [ -n "$ad" ] && [ -z "$en" ] || continue
    [ "$(_wt_abs "$tr" 2>/dev/null)" = "$co" ] || continue
    _line_alive "$ho" || continue
    printf 'request %s key=%s tree=%s' "${f##*/}" "$k" "$co"; return 0
  done
  nested="$(_line_nested "$root" "$co")"
  _wt_busy_suite "$co" "" "$nested"
}
_line_nested() {  # <root> <checkout> -> every other checkout git lists inside it, one per line
  local f
  while IFS= read -r f; do
    f="$(_wt_abs "$f" 2>/dev/null)" || continue
    [ "$f" != "$2" ] || continue
    case "$f/" in "$2"/*) printf '%s\n' "$f" ;; esac
  done <<EOF
$(_wt_checkouts "$1" | cut -f2)
EOF
}

# A REAL CHECKOUT MOVED SINCE THE RUN BEGAN (AC-3.9): the main checkout's or the branch's checkout's
# HEAD has a reflog entry after the candidate's time, other than a publish's own fast-forward
# (`line: publish`). A row tree is its writer's, and moves by design. Time is git's, to the second:
# an entry in the candidate's own second is not counted (a known limit).
_line_moved() {  # <root> <checkout or empty> <candidate's at=>
  local c t s
  for c in "$1" ${2:+"$2"}; do
    while IFS=$'\t' read -r t s; do
      t="${t#HEAD@\{}"; t="${t%\}}"
      [ -n "$t" ] || continue
      [[ "$t" > "$3" ]] || break
      case "$s" in "line: publish"*) continue ;; esac
      printf '%s' "$c"; return 0
    done <<EOF
$(TZ=UTC0 git -C "$c" log -g --format='%gd%x09%gs' --date=format-local:%Y-%m-%dT%H:%M:%SZ HEAD 2>/dev/null)
EOF
  done
  return 1
}

# THE PAUSE SEAM (S24): tests only. Before the fast-forward, `<dir>/<row>.at-publish` is made and
# the publisher waits for `<dir>/<row>.go`, at most ten minutes.
_line_pause() {  # <row>
  local d="${BIONIC_LINE_PAUSE_BEFORE_PUBLISH:-}" i=0
  [ -n "$d" ] || return 0
  : > "$d/$1.at-publish"
  while [ ! -e "$d/$1.go" ] && [ "$i" -lt 6000 ]; do sleep 0.1; i=$((i + 1)); done
}

# THE PLAN WRITE (wave-28 T6; D7, AC-3.2; ruling A-orch-81): the row's status `landed`, its `- T<n>:`
# line and its dispatch-ledger line, in ONE transaction on the BOUND plan: `session-poker.sh row-landed`,
# run as a command (the plan verbs live in the hook script and exit on refusal), whose one copy is
# `plan_verb_open`'s and whose one dry commit is a writer's (wave-27 passes 60, 63: no copy stands in for
# the plan here). A hand landing's line gains its `landed-by-hand:` text in the same write. A row that is
# no plan row has nothing to write. rc 1 when the verb refused or could not run; its words are printed
# by the caller, after the publish, never swallowed (LINE_PLAN_SAID).
_line_plan_write() {  # <plan> <row> <commit> <at> -> 0 written or nothing to write · 1 refused
  local poker root rc
  LINE_PLAN_SAID=""
  _line_plan_agent "$1" "$2" >/dev/null || return 0
  poker="$(plugin_root 2>/dev/null)/hooks/session-poker.sh"
  root="$(_line_root "$1")" || { LINE_PLAN_SAID="the plan's root cannot be read"; return 1; }
  if [ "$LINE_KIND" = hand ]; then
    LINE_PLAN_SAID="$( cd "$root" && CLAUDE_CODE_SESSION_ID="${LINE_SID}" bash "$poker" row-landed "$2" "$3" "$4" --by-hand "$LINE_BY" "$LINE_WHY" 2>&1 )"; rc=$?
  else
    LINE_PLAN_SAID="$( cd "$root" && CLAUDE_CODE_SESSION_ID="${LINE_SID}" bash "$poker" row-landed "$2" "$3" "$4" 2>&1 )"; rc=$?
  fi
  [ "$rc" -eq 0 ] && return 0
  return 1
}

# THE ROSTER MARK (wave-28 T6; D7): the row's roster line gains `landed=<40-hex> landed_at=<ISO-UTC>`
# (lib/roster.sh `roster_mark_landed`, the roster's one marker). The name marked is the row's writer as
# `ready` held the landing to it, `line_row_writer`'s answer (wave-35 T7; burns debt row-writer-lookup):
# this function used to resolve the launch line's name for itself, so an agent whose latest row carries
# another name was held under one name and marked under the other. Sets LINE_MARKED to the name marked
# (empty when the row has no writer on this session's roster, as a hand landing may not).
_line_roster_mark() {  # <plan> <root> <row> <commit> <at>
  local roster
  LINE_MARKED=""
  [ -n "$LINE_SID" ] || return 0
  if ! declare -F roster_mark_landed >/dev/null 2>&1; then
    # shellcheck source=/dev/null
    [ -r "$_LINE_LIB_DIR/roster.sh" ] && . "$_LINE_LIB_DIR/roster.sh" 2>/dev/null
    declare -F roster_mark_landed >/dev/null 2>&1 || return 0
  fi
  roster="${2%/}/.bionic/tmp/roster-${LINE_SID}.state"
  # A run adopted after a clear (no launch line on this roster) is marked too: the writer is then the
  # plan row's agent cell. No row of the name, no mark.
  line_row_writer "$roster" "$1" "$3" || return 0
  roster_mark_landed "$roster" "$LINE_WRITER" "$4" "$5" && LINE_MARKED="$LINE_WRITER"
}

# THE RELEASE ROW'S COVER. The release row is a doc row at step 7 or later, as the plan's order check and
# units_order read it. Its merge first exists here, so its landing prints the judge's basis of its own candidate
# (lib/proof.sh `proof_door_cover`): `COVER <row> <candidate> release`, or `… owes outside=<paths>` naming each
# path outside the release set, since past such a merge no reading reaches. A line, never a refusal: a release may
# have to touch a path the set lacks, and the person who reads the line decides.
_line_release_rows() {  # <plan> -> the id of each doc row at step 7 or later, one a line
  local rec s
  _wt_units_load || return 1
  while IFS= read -r rec; do
    [ -n "$rec" ] && [ "$(units_field "$rec" kind)" = doc ] || continue
    s="$(units_field "$rec" step)"
    case "$s" in ''|*[!0-9]*) continue ;; esac
    [ "$s" -lt 7 ] || printf '%s\n' "$(units_field "$rec" id)"
  done <<EOF
$(units_rows "$1" 2>/dev/null)
EOF
}
_line_release_row() {  # <plan> <row> -> 0 when the row is a release row
  local r
  while IFS= read -r r; do
    [ "$r" != "$2" ] || return 0
  done <<EOF
$(_line_release_rows "$1")
EOF
  return 1
}
_line_cover() {  # <plan> <row> <root> <accepted head> <candidate>
  local b
  _line_release_row "$1" "$2" && _line_load_proof && declare -F proof_door_cover >/dev/null 2>&1 || return 0
  b="$(proof_door_cover "$3" "$4" "$5")" || return 0
  case "$b" in
    owes*) printf 'COVER %s %s owes outside=%s — the release row touches paths outside the release set, so the judge reads its merge as owing and no reading reaches past it; land them in a row of their own, or add them to the set (lib/proof.sh _proof_release_path)\n' "$2" "$5" "${b#*	}" ;;
    *) printf 'COVER %s %s %s\n' "$2" "$5" "$b" ;;
  esac
}

# THE RELEASE NUMBERS, AT A LANDING PAST THE RELEASE. The release entry's `### The landing numbers` block names the
# head it was rendered at, and the release check refuses any landing the checked head holds and that head does not:
# once a release row of the plan has published, every later landing would leave the check red until someone typed
# the numbers again by hand. So the line renders them as part of that landing: `release-note --at <candidate> --on
# <instant>` for the plan, the entry's block in the candidate's CHANGELOG.md replaced by what it prints, committed on
# the candidate under the line's own author. The commit is made in the object store alone, before the release check
# and the fast-forward, which then judge and publish it: a render that fails refuses the landing with nothing moved.
# The instant is one second before the render, since the record's lines carry whole seconds and the report keeps a
# line written at the instant: every line the block folds is then written before it is rendered, so the release
# check rendering it again for the same head and instant gets the same block. No published release row (the release
# row itself carries its own numbers), no `release:` in the plan, or an entry with no numbers block: nothing is made.
# Sets LINE_NUMBERS (the commit, or empty) and, on a refusal, LINE_NUMBERS_SAID (the renderer's words).
LINE_NUMBERS_AUTHOR="bionic line"; LINE_NUMBERS_EMAIL="line@bionic.invalid"
_line_numbers() {  # <plan> <record> <root> <row> <candidate> -> 0 made or nothing to make · 1 refused
  local plan="$1" rec="$2" root="$3" row="$4" cand="$5" r landed="" ver tmp now on note mode blob tree c jt rn nrc
  LINE_NUMBERS=""; LINE_NUMBERS_SAID=""
  _line_release_row "$plan" "$row" && return 0
  while IFS= read -r r; do
    [ -n "$r" ] || continue
    awk -F'|' -v r="$r" "$_LINE_FIELDS_AWK"'line_ev() == "published" && line_kv("row") == r { f = 1 } END { exit !f }' \
      "$rec" 2>/dev/null && { landed="$r"; break; }
  done <<EOF
$(_line_release_rows "$plan")
EOF
  [ -n "$landed" ] || return 0
  _line_load_run || { LINE_NUMBERS_SAID="the run library ($_LINE_LIB_DIR/run.sh) cannot be loaded to read the release"; return 1; }
  ver="$(plan_frontmatter_get "$plan" release)"
  [ -n "$ver" ] || return 0
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/line-numbers.XXXXXX")" || { LINE_NUMBERS_SAID="no temporary directory"; return 1; }
  git -C "$root" show "${cand}:CHANGELOG.md" > "$tmp/old" 2>/dev/null || { rm -rf "$tmp"; return 0; }
  awk -v v="## ${ver} " '/^## / { inb = (index($0, v) == 1) }
    inb && /^### / { t = $0; sub(/[[:space:]]+$/, "", t); if (t == "### The landing numbers") f = 1 }
    END { exit !f }' "$tmp/old" || { rm -rf "$tmp"; return 0; }
  now="$(date -u +%s)"
  on="$(date -u -r "$((now - 1))" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$((now - 1))" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)"
  # THE JUDGE'S COPY RENDERS. The release check compares the block with its own release-note, and the copy that runs
  # is the release base's (lib/worktree.sh `worktree_check_run`), so the block is rendered by that copy too, checked
  # out in a landing tree: a change to the renderer reaches the entry one release later, never refused by its own
  # check. A judge that holds no renderer has no copy to compare with, and the plugin's renders.
  jt=""; rn="$(plugin_root 2>/dev/null)/hooks/session-poker.sh"
  if release_base "$plan" "$root" "$cand" && git -C "$root" cat-file -e "${RB_BASE}:hooks/session-poker.sh" 2>/dev/null; then
    if ! jt="$(landing_tree_take "$root")" || ! landing_tree_point "$jt" "$RB_BASE"; then
      [ -z "$jt" ] || landing_tree_free "$jt"
      LINE_NUMBERS_SAID="no landing tree can be checked out at the release base ${RB_BASE} to render with its release-note"
      rm -rf "$tmp"; return 1
    fi
    rn="${jt}/hooks/session-poker.sh"
  fi
  note="$(cd "$root" 2>/dev/null && bash "$rn" release-note --at "$cand" --on "${on:-unreadable}" "$plan" 2>&1)"; nrc=$?
  [ -z "$jt" ] || landing_tree_free "$jt"
  if [ "$nrc" -ne 0 ]; then
    LINE_NUMBERS_SAID="${note:-release-note printed nothing}"; rm -rf "$tmp"; return 1
  fi
  printf '%s\n' "$note" > "$tmp/note"
  # The entry's numbers part, from its first heading to the next heading of another name (a doubled heading is one
  # part), gives way to the rendered block and one blank line.
  awk -v v="## ${ver} " -v nf="$tmp/note" '
    function put(   l) { while ((getline l < nf) > 0) print l; print ""; inp = 0; done = 1 }
    /^###? / { t = $0; sub(/[[:space:]]+$/, "", t)
      if (inp && t != "### The landing numbers") put()
      if (substr($0, 1, 3) == "## ") inb = (index($0, v) == 1)
      else if (inb && !done && t == "### The landing numbers") { inp = 1; next } }
    inp { next }
    { print }
    END { if (inp) put() }' "$tmp/old" > "$tmp/new" \
  && mode="$(git -C "$root" ls-tree "$cand" CHANGELOG.md 2>/dev/null | awk '{ print $1 }')" \
  && blob="$(git -C "$root" hash-object -w --path CHANGELOG.md "$tmp/new" 2>&1)" \
  && GIT_INDEX_FILE="$tmp/index" git -C "$root" read-tree "$cand" >/dev/null 2>&1 \
  && GIT_INDEX_FILE="$tmp/index" git -C "$root" update-index --cacheinfo "${mode:-100644},${blob},CHANGELOG.md" >/dev/null 2>&1 \
  && tree="$(GIT_INDEX_FILE="$tmp/index" git -C "$root" write-tree 2>&1)" \
  && c="$(GIT_AUTHOR_NAME="$LINE_NUMBERS_AUTHOR" GIT_AUTHOR_EMAIL="$LINE_NUMBERS_EMAIL" \
         git -C "$root" commit-tree "$tree" -p "$cand" -m "line: release numbers ${row}" 2>&1)" \
  || { LINE_NUMBERS_SAID="the numbers commit on ${cand} cannot be made: ${c:-${tree:-${blob:-git refused}}}"; rm -rf "$tmp"; return 1; }
  rm -rf "$tmp"
  LINE_NUMBERS="$c"
}

# THE RELEASE ENTRY'S REVIEWS PART, RENDERED FROM THE PLAN. The entry's `### The reviews` part names every review the run
# registered and every waiver the user gave, so it is the machine's, as the numbers are: one fixed first line, then one
# bullet per `proved: kind=review` line and per `waived:` line of the plan's unfenced `## SDLC State`, in the order the
# verbs wrote them. It replaces the entry's own part (its heading to the next heading; a doubled heading is one part), or
# goes in before the entry's `### Known limits` or `### The landing numbers`, whichever comes first, else at the entry's
# end. Two verbs write it through these functions, so the two cannot render it differently: the integrate row's
# `reviews-part`, before the pull request opens, so the merge carries the part to the integration branch, and close-out,
# for a run whose part no earlier verb wrote. The judge holds a commit of the part covered by what holds at its parent
# only while it is byte-equal to this render (lib/proof.sh `proof_part_base`), so the render must stay deterministic:
# the plan's lines and the entry alone decide it.
line_reviews_part() {  # <plan> -> the rendered part, heading to its closing blank line; nothing when it lists nothing
  _line_load_proof || return 1
  awk "$(proof_awk)"'
    function base(p,   n, e) { n = split(p, e, "/"); return e[n] }
    /^[[:space:]]*```/ { fence = !fence; next }
    fence { next }
    /^##[[:space:]]/ { insdlc = ($0 ~ /^##[[:space:]]+SDLC State/); next }
    !insdlc { next }
    proof_fields($0) && PROOF_KIND == "review" && PROOF_QUESTION != "" {
      at = ""; if (match($0, /[ \t]at=[^ \t]+/)) at = substr($0, RSTART + 4, RLENGTH - 4)
      b[++n] = sprintf("- %s review%s: %s at %s by %s%s%s", PROOF_QUESTION, (PROOF_SCOPE != "" ? ", " PROOF_SCOPE : ""),
        PROOF_RESULT, substr(PROOF_HEAD, 1, 8), PROOF_READER, (at != "" ? ", " at : ""),
        (PROOF_EVIDENCE != "" ? " (`" base(PROOF_EVIDENCE) "`)" : ""))
      next
    }
    /^waived:[ \t]/ {
      m = split($0, w, /[ \t]+/); q = ""; h = ""
      for (i = 2; i <= m && w[i] != "by"; i++) {
        if (w[i] ~ /^question=/) q = substr(w[i], 10)
        else if (w[i] ~ /^head=/) h = substr(w[i], 6)
      }
      k = index($0, " by "); if (q == "" || !k) next
      r = substr($0, k + 4); k = index(r, "\"")
      if (k) { who = substr(r, 1, k - 1); words = substr(r, k) } else { who = r; words = "" }
      sub(/[ \t]+$/, "", who); at = who; sub(/.*[ \t]/, "", at)
      if (at ~ /^[0-9][0-9][0-9][0-9]-/ && length(at) < length(who)) { who = substr(who, 1, length(who) - length(at)); sub(/[ \t]+$/, "", who) }
      else at = ""
      b[++n] = sprintf("- %s review: waived at %s by %s%s%s", q, substr(h, 1, 8), who, (at != "" ? ", " at : ""),
        (words != "" ? ": " words : ""))
    }
    END {
      if (!n) exit
      print "### The reviews"; print ""
      print "Rendered from the plan'"'"'s review and waiver lines, in the order they were registered."; print ""
      for (i = 1; i <= n; i++) print b[i]
      print ""
    }' "$1"
}
line_reviews_entry() {  # <changelog> <version> <part file> -> the changelog with the entry's part rendered
  awk -v v="## $2 " -v pf="$3" '
    function put(   l) { if (last != "") print ""; while ((getline l < pf) > 0) print l; close(pf); done = 1; last = "" }
    /^## / { if (inb && !done) put(); inb = (index($0, v) == 1); inp = 0 }
    /^### / {
      t = $0; sub(/[[:space:]]+$/, "", t); inp = 0
      if (inb && t == "### The reviews") { if (!done) put(); inp = 1; next }
      if (inb && !done && (t == "### Known limits" || t == "### The landing numbers")) put()
    }
    inp { next }
    { print; last = $0 }
    END { if (inb && !done) put() }' "$1"
}
# line_reviews_state <plan> <root> <commit> <name> <out file> -> what the render would do to <commit>'s CHANGELOG.md
# (<name> is what the words call the commit, a branch or a head): LINE_RV_STATE `none` (nothing to render, the reason in
# LINE_RV_SAID), `listed` (the entry already reads as rendered) or `renders` (<out file> holds the file with the part
# rendered); LINE_RV_VER the release, LINE_RV_N the bullets. rc 1, LINE_RV_SAID saying why, when the render cannot run.
LINE_RV_STATE=""; LINE_RV_VER=""; LINE_RV_N=0; LINE_RV_SAID=""
line_reviews_state() {
  local plan="$1" root="$2" c="$3" nm="$4" out="$5" tmp
  LINE_RV_STATE=none; LINE_RV_VER=""; LINE_RV_N=0; LINE_RV_SAID=""
  _line_load_run || { LINE_RV_SAID="the run library ($_LINE_LIB_DIR/run.sh) cannot be loaded to read the release"; return 1; }
  LINE_RV_VER="$(plan_frontmatter_get "$plan" release)"
  [ -n "$LINE_RV_VER" ] || { LINE_RV_SAID="the plan names no release:"; return 0; }
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/line-reviews.XXXXXX")" || { LINE_RV_SAID="no temporary directory"; return 1; }
  if ! git -C "$root" show "${c}:CHANGELOG.md" > "$tmp/old" 2>/dev/null; then
    rm -rf "$tmp"; LINE_RV_SAID="$nm holds no CHANGELOG.md"; return 0
  fi
  if ! /usr/bin/grep -q "^## ${LINE_RV_VER} " "$tmp/old"; then
    rm -rf "$tmp"; LINE_RV_SAID="CHANGELOG.md on $nm holds no ## $LINE_RV_VER entry"; return 0
  fi
  if ! line_reviews_part "$plan" > "$tmp/part"; then
    rm -rf "$tmp"; LINE_RV_SAID="the proof library ($_LINE_LIB_DIR/proof.sh) cannot be loaded to read the plan's reviews"; return 1
  fi
  LINE_RV_N="$(/usr/bin/grep -c '^- ' "$tmp/part" | tr -d ' ')"
  [ "${LINE_RV_N:-0}" -gt 0 ] || { rm -rf "$tmp"; LINE_RV_N=0; LINE_RV_SAID="the plan registers no review and no waiver"; return 0; }
  line_reviews_entry "$tmp/old" "$LINE_RV_VER" "$tmp/part" > "$out"
  if cmp -s "$tmp/old" "$out"; then LINE_RV_STATE=listed; else LINE_RV_STATE=renders; fi
  rm -rf "$tmp"
}
# line_reviews_checkout <root> <branch> -> nothing when the branch can take a commit of CHANGELOG.md, else why not: the
# checkout that holds it takes the commit by a fast-forward, which a changed CHANGELOG.md there would refuse, so this is
# asked before the commit is made, and a branch held in two places has no one checkout to move.
line_reviews_checkout() {
  local co rc
  co="$(worktree_checkout_of "$1" "$2")"; rc=$?
  if [ "$rc" -ge 2 ]; then printf '%s is checked out in more than one place (%s)' "$2" "${co// /, }"; return 0; fi
  if [ "$rc" -eq 0 ] && [ -n "$(git -C "$co" status --porcelain -- CHANGELOG.md 2>/dev/null)" ]; then
    printf 'CHANGELOG.md is changed in %s, the checkout holding %s: commit or restore it' "$co" "$2"
  fi
}
# line_reviews_commit <root> <parent> <file> <author> <email> <message> -> LINE_RV_COMMIT, the commit of <file> as
# CHANGELOG.md on <parent>, made in the object store alone (nothing moves); rc 1 with LINE_RV_SAID saying why
LINE_RV_COMMIT=""
line_reviews_commit() {
  local root="$1" tip="$2" f="$3" tmp mode blob tree c
  LINE_RV_COMMIT=""
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/line-reviews-commit.XXXXXX")" || { LINE_RV_SAID="no temporary directory"; return 1; }
  mode="$(git -C "$root" ls-tree "$tip" CHANGELOG.md 2>/dev/null | awk '{ print $1 }')"
  if blob="$(git -C "$root" hash-object -w --path CHANGELOG.md "$f" 2>&1)" \
     && GIT_INDEX_FILE="$tmp/index" git -C "$root" read-tree "$tip" >/dev/null 2>&1 \
     && GIT_INDEX_FILE="$tmp/index" git -C "$root" update-index --cacheinfo "${mode:-100644},${blob},CHANGELOG.md" >/dev/null 2>&1 \
     && tree="$(GIT_INDEX_FILE="$tmp/index" git -C "$root" write-tree 2>&1)" \
     && c="$(GIT_AUTHOR_NAME="$4" GIT_AUTHOR_EMAIL="$5" git -C "$root" commit-tree "$tree" -p "$tip" -m "$6" 2>&1)"; then
    rm -rf "$tmp"; LINE_RV_COMMIT="$c"; return 0
  fi
  rm -rf "$tmp"
  LINE_RV_SAID="the commit on ${tip:0:12} cannot be made: ${c:-${tree:-${blob:-git refused}}}"
  return 1
}
# line_reviews_move <root> <branch> <commit> <old> <reflog words> -> the branch at <commit>: a fast-forward in the
# checkout that holds it, so that checkout is never left behind it, else the ref moved from <old>; rc 1 when it cannot.
# The branch moves on this machine alone: pushing it is the person's act.
line_reviews_move() {
  local co rc
  co="$(worktree_checkout_of "$1" "$2")"; rc=$?
  case $rc in
    0) GIT_REFLOG_ACTION="$5" git -C "$co" merge --ff-only -q "$3" >/dev/null 2>&1 ;;
    1) git -C "$1" update-ref -m "$5" "refs/heads/$2" "$3" "$4" >/dev/null 2>&1 ;;
    *) return 1 ;;
  esac
}

# THE FIX BORN OF A FAILING REVIEW. Once the plan reads `current: 8` or `9` the run has been judged for integration,
# and the door refuses every landing but one: a row whose born marker (`task-add --born <record>#<n>`, lib/units.sh
# `units_born_findings`) names a finding of the review that is its question's newest reading and derives `fail`.
# That row is what answers the review, so the step never has to move back for it. Which review that is, and whether it
# fails, is the judge's own answer (lib/proof.sh `facts_state`: the reading's result through `_proof_reading_derive`
# over `proof_fixed`), so the door, the step advance and the gate cannot disagree on it. A row born of a regression's
# red names no review record and is not admitted. When the row publishes, the same judge is asked again: a question
# its born records answer that no longer derives `fail` has its `waive:<q>` ask closed on the run's register
# (lib/owed.sh `owed_close`), so neither a waiver nor a step back is needed. Fail closed: a judge that cannot answer
# admits nothing and closes nothing.
_line_born_records() {  # <plan> <row> -> each review record the row's born marker names, once each
  _wt_units_load || return 1
  units_born_findings "$1" 2>/dev/null | awk -F'\t' -v r="$2" '
    $1 == r { sub(/#[0-9]+$/, "", $3); if (!($3 in s)) { s[$3] = 1; print $3 } }'
}
_line_judged() {  # <plan> -> the judge's lines at the accepted head; 1 when it cannot answer
  local head out rc
  _line_load_proof && declare -F facts_state >/dev/null 2>&1 || return 1
  head="$(line_head "$1")" && [ -n "$head" ] || return 1
  out="$(facts_state "$1" "$head" 2>/dev/null)"; rc=$?
  [ "$rc" -le 1 ] || return 1
  printf '%s\n' "$out"
}
_line_failing() {  # <judge's lines> <records, one a line> -> the question of each review failing on one of the records
  printf '%s\n' "$1" | LINE_RECS="$2" awk -F'\t' '
    BEGIN { n = split(ENVIRON["LINE_RECS"], a, "\n"); for (i = 1; i <= n; i++) if (a[i] != "") want[a[i]] = 1 }
    $1 == "review" && $5 == "failing" && ($6 in want) && !($2 in s) { s[$2] = 1; print $2 }'
}
line_born_failing() {  # <plan> <root> <tree abs> -> 0 when the tree's row is born of a finding of a failing review
  local row recs judged
  row="$(_wt_proofs_row "$2" "$1" "$3")" && [ -n "$row" ] || return 1
  recs="$(_line_born_records "$1" "$row")" && [ -n "$recs" ] || return 1
  judged="$(_line_judged "$1")" || return 1
  [ -n "$(_line_failing "$judged" "$recs")" ]
}
_line_load_owed() {
  declare -F owed_close >/dev/null 2>&1 && return 0
  # shellcheck source=/dev/null
  [ -r "$_LINE_LIB_DIR/owed.sh" ] && . "$_LINE_LIB_DIR/owed.sh" 2>/dev/null
  declare -F owed_close >/dev/null 2>&1
}
# The records a landed row answers: those its born marker names, and those of every finding a landing of it settled
# (`line_settled`'s `ev=settled` lines), once each.
_line_answered_records() {  # <plan> <row>
  local rec
  { _line_born_records "$1" "$2"
    rec="$(line_record "$1")" && [ -f "$rec" ] && awk -F'|' -v r="$2" "$_LINE_FIELDS_AWK"'
      line_ev() == "settled" && line_kv("row") == r { n = split(line_kv("findings"), a, ","); for (i = 1; i <= n; i++) { sub(/#[0-9]+$/, "", a[i]); print a[i] } }' "$rec"
  } | awk 'NF && !s[$0]++'
}
# The questions a born row's records were read for are those of the plan's review proof lines naming one of them;
# each that the judge no longer finds failing has its ask closed, by the landing.
_line_born_close() {  # <plan> <root> <row>
  local recs qs judged q
  recs="$(_line_answered_records "$1" "$3")" && [ -n "$recs" ] || return 0
  _line_load_proof || return 0
  qs="$(LINE_RECS="$recs" awk "$(proof_awk)"'
    BEGIN { n = split(ENVIRON["LINE_RECS"], a, "\n"); for (i = 1; i <= n; i++) if (a[i] != "") want[a[i]] = 1 }
    /^[[:space:]]*```/ { fence = !fence; next }
    fence { next }
    /^##[[:space:]]/ { insdlc = ($0 ~ /^##[[:space:]]+SDLC State/); next }
    insdlc && proof_fields($0) && PROOF_KIND == "review" && PROOF_QUESTION != "" && (PROOF_EVIDENCE in want) \
      && !(PROOF_QUESTION in s) { s[PROOF_QUESTION] = 1; print PROOF_QUESTION }' "$1" 2>/dev/null)"
  [ -n "$qs" ] || return 0
  judged="$(_line_judged "$1")" || return 0
  _line_load_owed || return 0
  for q in $qs; do
    printf '%s\n' "$judged" | awk -F'\t' -v q="$q" '$1 == "review" && $2 == q && $5 == "failing" { y = 1 } END { exit !y }' \
      && continue
    OWED_ROOT="$2" OWED_PLAN="$1" OWED_SID="${LINE_SID:-line}" owed_close "waive:${q}" "landing ${3}" >/dev/null 2>&1
  done
  return 0
}

# A finding the user answered carry to a row waits on that row's landing (lib/owed.sh `ask_waits_on`); the landing is
# that event, so each open `finding:` ask answered carry with the event `<row> lands` closes here, by the landing.
_line_carried_close() {  # <plan> <root> <row>
  local k
  _line_load_owed || return 0
  declare -F owed_answers >/dev/null 2>&1 || return 0
  for k in $(owed_answers "$1" "$2" 2>/dev/null | awk -F'\t' -v ev="$3 lands" 'index($1, "finding:") == 1 && $2 == "carry" && $4 == ev { print $1 }'); do
    OWED_ROOT="$2" OWED_PLAN="$1" OWED_SID="${LINE_SID:-line}" owed_close "$k" "landing ${3}" >/dev/null 2>&1
  done
  return 0
}

# ---------------------------------------------------------------------------- the landing's settlement
# A LANDING SETTLES EVERYTHING IT PROVES IN ONE ACT, so nothing it proves is settled by hand afterwards. Its plan write
# (`session-poker.sh row-landed`, which every landing runs) hands its copy of the plan to `line_settle` before the copy
# is swapped in, and the copy gains, in that one transaction:
#   · a `moved: <record>#<n> to=fixed row=<row> by=landing at=<at> landing=<commit>` line for each finding carried to
#     the row (`finding-move … carried <row>`) and for each finding any registered review names at the site of a
#     finding the row answers (born of it, moved fixed to it, or carried to it); `proof_fixed` then reads each fixed
#     once the row's verdicts are green, as it reads a person's move;
#   · the matrix table's status `discharged` for each criterion whose block `evidence:` the same write filled
#     (`landing_evidence`), unless the cell reads `waived`: a waiver is the person's word and no landing overwrites it.
# Once the copy is in, `line_settled` closes each settled finding's ask on the register, closes the asks answered
# carry to the row's landing, and appends `ev=settled` to the landing record naming the row, the commit, the findings
# and the cells, the one fact the correcting verbs read (`line_settled_by`): `finding-move` and `matrix-set` refuse a
# cell a landing settled, naming that landing.
#
# THE SAME SITE IS A LINE AT EACH REVIEW'S OWN HEAD. A finding names `<path>:<line>` at the head its review read; two
# reviews read at different heads name one line at different numbers. A site is carried from the answered finding's
# head to the other review's head through git's diff of the path between them: a line inside a changed hunk has no
# counterpart, so it joins nothing, and a line outside one moves by the hunks above it. Without both heads in the
# repository nothing is joined.
_line_site_map() {  # <root> <path> <line> <from head> <to head> -> the line's number at <to head>; 1 when it has none
  [ "$4" = "$5" ] && { printf '%s' "$3"; return 0; }
  git -C "$1" cat-file -e "$4^{commit}" 2>/dev/null && git -C "$1" cat-file -e "$5^{commit}" 2>/dev/null || return 1
  git -C "$1" diff -U0 --no-color "$4" "$5" -- "$2" 2>/dev/null | awk -v L="$3" '
    /^@@ / {
      split($2, o, ","); split($3, w, ",")
      a = substr(o[1], 2) + 0; b = (2 in o) ? o[2] + 0 : 1; d = (2 in w) ? w[2] + 0 : 1
      if (b > 0 && L >= a && L <= a + b - 1) { gone = 1; exit }
      if ((b > 0 && L >= a + b) || (b == 0 && L > a)) off += d - b
    }
    END { if (gone) exit 1; print L + off }'
}
_line_review_sites() {  # <plan> <docs root> -> `<record>#<n> TAB <path> TAB <line> TAB <head>` per finding with a site, every registered review
  local ev h
  _line_load_proof || return 0
  for ev in $(awk "$(proof_awk)"'
      /^[[:space:]]*```/ { fence = !fence; next }
      fence { next }
      /^##[[:space:]]/ { insdlc = ($0 ~ /^##[[:space:]]+SDLC State/); next }
      insdlc && proof_fields($0) && PROOF_KIND == "review" && PROOF_EVIDENCE != "" && !(PROOF_EVIDENCE in s) { s[PROOF_EVIDENCE] = 1; print PROOF_EVIDENCE }' "$1" 2>/dev/null); do
    [ -f "$2/$ev" ] || continue
    h="$(awk '/^reviewed:[ \t]/ { v = $2; sub(/^.*\.\./, "", v); print v; exit }' "$2/$ev")"
    proof_findings "$2/$ev" 2>/dev/null | awk -F'\t' -v ev="$ev" -v h="$h" '
      $1 ~ /^[0-9]+$/ && $4 ~ /:[0-9]+$/ { p = $4; sub(/:[0-9]+$/, "", p); l = substr($4, length(p) + 2); print ev "#" $1 "\t" p "\t" l "\t" h }'
  done
}
# _line_same_site <root> <answered sites> <moves> -> each finding on stdin (`<record>#<n> TAB <path> TAB <line> TAB
# <head>`) at one of the answered sites, carried to its own head; a finding a person moved to defer or fixed is left:
# their ruling stands.
_line_same_site() {
  local id p l h op ol oh mv
  while IFS='	' read -r id p l h; do
    [ -n "$id" ] || continue
    mv="$(printf '%s\n' "$3" | awk -F'\t' -v i="$id" '$1 == i { print $2; exit }')"
    if [ "$mv" = defer ] || [ "$mv" = fixed ]; then continue; fi
    while IFS='	' read -r op ol oh; do
      [ -n "$op" ] && [ "$op" = "$p" ] || continue
      if [ "$(_line_site_map "$1" "$op" "$ol" "$oh" "$h")" = "$l" ]; then printf '%s\n' "$id"; break; fi
    done <<LINE_OWN_SITES
$2
LINE_OWN_SITES
  done
}
# _line_moves <plan> -> `<record>#<n> TAB <to> TAB <row>` per finding: its newest `moved:` line, a carry among them
_line_moves() {
  awk '
    /^[[:space:]]*```/ { fence = !fence; next }
    fence { next }
    /^##[[:space:]]/ { insdlc = ($0 ~ /^##[[:space:]]+SDLC State/); next }
    insdlc && /^moved:[ \t]/ {
      split($0, f, /[ \t]+/); id = f[2]; to = f[3]; sub(/^to=/, "", to); r = ""
      if (f[4] ~ /^row=/) r = substr(f[4], 5)
      if (!(id in last)) ord[++n] = id
      last[id] = to "\t" r
    }
    END { for (i = 1; i <= n; i++) print ord[i] "\t" last[ord[i]] }' "$1" 2>/dev/null
}
# line_settle <plan> <row> <commit> <copy> <at> [<criteria>] -> 0 with <copy> settled; 1 when it cannot be written.
# <plan> is read for what the row answers, <copy> is the copy the plan write swaps in, <criteria> the AC ids whose
# evidence that write filled, space-separated. Sets LINE_SETTLED_F (findings) and LINE_SETTLED_C (cells), space-separated.
line_settle() {
  local plan="$1" row="$2" com="$3" copy="$4" at="$5" acs="${6:-}" root docs own sites osites moves id ac st
  LINE_SETTLED_F=""; LINE_SETTLED_C=""
  root="$(_line_root "$plan")" || return 0
  _line_load_proof || return 0
  _proof_roots_load; docs="$(docs_root "$root" 2>/dev/null)"
  moves="$(_line_moves "$copy")"
  _wt_units_load >/dev/null 2>&1
  # What the row answers: born of it, moved fixed to it, carried to it.
  own="$( { units_born_findings "$copy" 2>/dev/null | awk -F'\t' -v r="$row" '$1 == r { print $3 }'
            printf '%s\n' "$moves" | awk -F'\t' -v r="$row" '($2 == "fixed" || $2 == "carried") && $3 == r { print $1 }'; } | awk 'NF && !s[$0]++')"
  if [ -n "$own" ] && [ -n "$docs" ]; then
    sites="$(_line_review_sites "$copy" "$docs")"
    osites="$(printf '%s\n' "$sites" | LINE_OWN="$own" awk -F'\t' '
      BEGIN { n = split(ENVIRON["LINE_OWN"], a, "\n"); for (i = 1; i <= n; i++) own[a[i]] = 1 }
      ($1 in own) { print $2 "\t" $3 "\t" $4 }')"
    LINE_SETTLED_F="$(
      printf '%s\n' "$moves" | awk -F'\t' -v r="$row" '$2 == "carried" && $3 == r { print $1 }'
      printf '%s\n' "$sites" | LINE_OWN="$own" awk -F'\t' '
        BEGIN { n = split(ENVIRON["LINE_OWN"], a, "\n"); for (i = 1; i <= n; i++) own[a[i]] = 1 }
        $1 != "" && !($1 in own)' | _line_same_site "$root" "$osites" "$moves"
    )"
    LINE_SETTLED_F="$(printf '%s\n' "$LINE_SETTLED_F" | awk 'NF && !s[$0]++' | tr '\n' ' ')"
    for id in $LINE_SETTLED_F; do
      proof_add_line "$copy" "moved: $id to=fixed row=$row by=landing at=$at landing=$com" > "$copy.st" 2>/dev/null && [ -s "$copy.st" ] \
        || { rm -f "$copy.st"; return 1; }
      mv -f "$copy.st" "$copy"
    done
  fi
  if declare -F matrix_row_cells >/dev/null 2>&1; then
    for ac in $acs; do
      st="$(matrix_row_cell "$copy" "$ac" 3)"
      case "$st" in ''|waived|discharged) continue ;; esac
      matrix_row_cells "$copy" "$ac" 3=discharged > "$copy.st" 2>/dev/null || { rm -f "$copy.st"; return 1; }
      mv -f "$copy.st" "$copy"
      LINE_SETTLED_C="${LINE_SETTLED_C}${ac} "
    done
  fi
  LINE_SETTLED_F="${LINE_SETTLED_F% }"; LINE_SETTLED_C="${LINE_SETTLED_C% }"
  return 0
}
# line_settled <plan> <root> <row> <commit> -> always 0: the register and the record half of `line_settle`, once the
# copy it settled is the plan.
line_settled() {
  local plan="$1" root="$2" row="$3" com="$4" id k
  if [ -n "$LINE_SETTLED_F" ] && _line_load_owed && declare -F finding_owed_key >/dev/null 2>&1; then
    for id in $LINE_SETTLED_F; do
      k="$(finding_owed_key "$id")"
      OWED_ROOT="$root" OWED_PLAN="$plan" OWED_SID="${LINE_SID:-line}" owed_close "$k" "landing ${row}" >/dev/null 2>&1
      OWED_ROOT="$root" OWED_PLAN="$plan" OWED_SID="${LINE_SID:-line}" owed_close "carry:${k#finding:}" "landing ${row}" >/dev/null 2>&1
    done
  fi
  _line_carried_close "$plan" "$root" "$row"
  [ -z "${LINE_SETTLED_F}${LINE_SETTLED_C}" ] \
    || line_event "$plan" settled "row=${row}" "commit=${com}" "findings=$(printf '%s' "$LINE_SETTLED_F" | tr ' ' ',')" \
         "cells=$(printf '%s' "$LINE_SETTLED_C" | tr ' ' ',')" >/dev/null
  return 0
}
# line_settled_by <plan> <findings|cells> <id> -> `<row> <commit>` of the newest landing that settled <id>; 1 when none did
line_settled_by() {
  local rec
  rec="$(line_record "$1")" && [ -f "$rec" ] || return 1
  awk -F'|' -v k="$2" -v id="$3" "$_LINE_FIELDS_AWK"'
    line_ev() == "settled" { n = split(line_kv(k), a, ","); for (i = 1; i <= n; i++) if (a[i] == id) w = line_kv("row") " " line_kv("commit") }
    END { if (w == "") exit 1; print w }' "$rec"
}

line_publish() {  # <plan> <row> -> 0 published · 3 rebuild · 4 held · 5 moved · 6 guard · 2 refused · 75 lock
  local plan="${1:-}" row="${2:-}" rec root lk head branch ent first=""
  local name com present base cand out sui car cbase cat br tr co rc run moved at tip
  rec="$(line_record "$plan")" && root="$(_line_root "$plan")" && branch="$(_line_branch "$plan")" \
    || { _wt_refuse "line-unreadable plan=${plan:-<none>}"; return 2; }
  lk="$(_line_lock_dir "$rec")"
  mkdir -p "${rec%/*}" 2>/dev/null
  _line_lock_take "$lk" "$row" || return $?
  head="$(line_head "$plan")"
  ent="$(_line_entries "$rec" "$head")"
  # First in line is the first present entry the base rule does not pass over: never a stalled one.
  first="$(printf '%s\n' "$ent" | awk -F'\t' '$4 == "yes" && $7 != "stalled" { print $1; exit }')"
  IFS=$'\t' read -r _ name com present base cand out sui car cbase cat br tr <<EOF
$(printf '%s\n' "$ent" | awk -F'\t' -v r="$row" '$1 == r { print; exit }')
EOF
  # 1. FIRST IN LINE, ON THE ACCEPTED HEAD (else rc 3: rebuild).
  _line_first_in_line "$first" "$row" "$lk" || return $?
  _line_on_head "$row" "$cand" "$cbase" "$head" "$lk" || return $?
  # 2. THE .bionic GUARD on the accepted head and the candidate (D31): the writer's tree and branch
  # in the refusal, never the landing tree; the row returned (else rc 6).
  _line_guard "$plan" "$row" "$root" "$head" "$cand" "$tr" "$br" "$branch" "$lk" || return $?
  # 3. NO LIVE RUN IN THE CHECKOUT THAT HOLDS THE BRANCH (else rc 4).
  co="$(worktree_checkout_of "$root" "$branch")"; rc=$?
  case $rc in
    0) : ;;
    1) co="" ;;
    *) _line_lock_drop "$lk"; _wt_refuse "onto-ambiguous branch=${branch} checkouts=${co// /,}"; return 2 ;;
  esac
  if [ -n "$co" ] && run="$(_line_live_run "$root" "$co")"; then
    _line_lock_drop "$lk"; printf 'HELD %s — %s\n' "$row" "$run"; return 4
  fi
  # 4. NO REAL CHECKOUT MOVED SINCE THE RUN BEGAN (else rc 5).
  if moved="$(_line_moved "$root" "$co" "$cat")"; then
    _line_lock_drop "$lk"; printf 'MOVED %s\n' "$moved"; return 5
  fi
  # 4b. THE RELEASE NUMBERS, past a published release row (`_line_numbers`): the commit on the candidate that
  # the release check judges and the fast-forward publishes; a render that fails refuses here, nothing written
  # (else rc 2). The head the branch moves to is that commit, else the candidate.
  if ! _line_numbers "$plan" "$rec" "$root" "$row" "$cand"; then
    _line_lock_drop "$lk"
    _wt_refuse "numbers-unrendered row=${row} candidate=${cand} — the release numbers cannot be rendered for this landing past the release, so nothing is published: $(printf '%s\n' "$LINE_NUMBERS_SAID" | awk 'NF { printf "%s%s", s, $0; s = " · " }'); make release-note render for the plan at the candidate, then land again"
    return 2
  fi
  tip="${LINE_NUMBERS:-$cand}"
  # 5. THE PROJECT'S RELEASE CHECK over the accepted head to the tip, as the release base holds it
  # (lib/worktree.sh `worktree_check_run`, in a landing tree of its own).
  _wt_release_check "$root" "$plan" "$head" "$tip" "$tr" "$br" "$branch" "$row"; rc=$?
  [ "$rc" -eq 0 ] || { _line_lock_drop "$lk"; return 2; }
  # 6. THE DEBT WRITE (wave-28 T5; D8, AC-9.4): a declared red's `debt:` line, at the publish's own
  # instant, before the fast-forward (else rc 2, nothing published).
  at="$(_line_now)"
  _line_debt_write "$rec" "$row" "$com" "$cand" "$br" "$at" || { _line_lock_drop "$lk"; return 2; }
  # 7. THE FAST-FORWARD, after the pause seam.
  _line_pause "$row"
  if [ -n "$co" ]; then
    GIT_REFLOG_ACTION="line: publish ${row}" git -C "$co" merge --ff-only -q "$tip" >/dev/null 2>&1; rc=$?
  else
    git -C "$root" update-ref -m "line: publish ${row}" "refs/heads/${branch}" "$tip" "$head" >/dev/null 2>&1; rc=$?
  fi
  if [ "$rc" -ne 0 ]; then
    # A debt written for a publish that did not happen is voided; a void that cannot be written
    # leaves the debt standing, and the refusal says so and what clears it.
    if [ -n "$LINE_DEBT_ID" ] && ! _wt_debt_void "$rec" "$LINE_DEBT_ID" "$br" publish-failed; then
      _line_lock_drop "$lk"
      _wt_refuse "publish-failed row=${row} branch=${branch} candidate=${cand} checkout=${co:-<none>} debt=unvoided path=${rec} — the fast-forward failed after the debt for ${LINE_DEBT_SUITE} was written and not voided (its void's append answered proofs=unwritten: ${_WT_PROOFS_SAW:-the append failed}), so the run owes it: a green run of ${LINE_DEBT_SUITE} after now covers it like any other; say ready again once the fast-forward can be made"
      return 2
    fi
    _line_lock_drop "$lk"
    _wt_refuse "publish-failed row=${row} branch=${branch} candidate=${cand} checkout=${co:-<none>} — the fast-forward did not go through and nothing is published; say ready again"
    return 2
  fi
  # 8. THE `published` EVENT, one instant for the record, the row and the debt; the numbers commit, when
  # one was made, beside the candidate it sits on.
  _wt_proofs_put "$rec" "line/v1|ev=published|row=${row}|commit=${cand}|kind=${LINE_KIND}|by=${LINE_BY}|why=${LINE_WHY}${LINE_NUMBERS:+|numbers=${LINE_NUMBERS}}|at=${at}"
  _wt_proofs_append "$rec" "$row" "$br" "$com" "$cand" "" "$at"
  [ -z "$LINE_DEBT_ID" ] \
    || printf 'DEBT %s %s — published red on the declared suite; the run owes a green run of %s (debt %s in %s)\n' \
         "$row" "$LINE_DEBT_SUITE" "$LINE_DEBT_SUITE" "$LINE_DEBT_ID" "$rec"
  _line_cover "$plan" "$row" "$root" "$head" "$cand"
  # 9. THE PLAN WRITE (T6): the row's status, its `- T<n>:` line and its ledger line, in one
  # transaction, at the publish's own instant. A refusal now is after the publish: it is printed, with
  # what is owed by hand, and the publish stands.
  if ! _line_plan_write "$plan" "$row" "$cand" "$at"; then
    [ -z "$LINE_PLAN_SAID" ] || printf '%s\n' "$LINE_PLAN_SAID"
    printf 'PLAN-UNWRITTEN %s — published %s; the plan row is not written: run row-landed %s %s %s from the main thread\n' \
      "$row" "$cand" "$row" "$cand" "$at"
  fi
  # 10. THE ROSTER MARK (T6): `landed=<40-hex> landed_at=<ISO-UTC>` on the row's roster line.
  _line_roster_mark "$plan" "$root" "$row" "$cand" "$at"
  _line_lock_drop "$lk"
  # 11. THE REVIEWS THE ROW ANSWERS, asked again once the row reads landed (`_line_born_close`), outside the lock:
  # the judge reads git and the record, and no publish waits on it. The findings the plan write settled closed with it.
  _line_born_close "$plan" "$root" "$row"
  LINE_PUBLISHED="$cand"; LINE_CHECKOUT="$co"
  return 0
}

# ---------------------------------------------------------------------------- the tree's run
# THE TREE'S RUN, READ OFF THE TREE FIRST. A landing's plan and working branch come from the tree's own record
# (lib/worktree.sh `worktree_tree_record`), so a session that never saw the spawn, a conversation cleared between the
# spawn and the landing, lands what it is handed: the session's binding is a check on the record, never its source. A
# session bound to another plan than the tree's is refused naming both. A plan no longer open is admitted only to the
# session bound to it, whose run closes with these last landings (lib/run.sh `session_working_branch` admits a closed
# bound plan for the same reason). A tree with no record of its own is read through the binding alone, as before.
# Sets LINE_RUN_PLAN, LINE_RUN_ONTO and LINE_RUN_BY (the spawning session; empty for a tree with no record); rc 1 with
# the refusal's words in LINE_RUN_WHY. Needs lib/run.sh loaded (`_line_load_run`).
_line_same_file() {  # <path> <path> -> 0 when both name one file, spelled alike or through links
  [ -n "${1:-}" ] && [ -n "${2:-}" ] || return 1
  [ "$1" = "$2" ] && return 0
  [ "$(cd "${1%/*}" 2>/dev/null && pwd -P)/${1##*/}" = "$(cd "${2%/*}" 2>/dev/null && pwd -P)/${2##*/}" ]
}
line_tree_run() {  # <tree> <root> <sid>
  local tree="${1:-}" root="${2:-}" sid="${3:-}" rec tp sp="" verdict st
  LINE_RUN_PLAN=""; LINE_RUN_ONTO=""; LINE_RUN_BY=""; LINE_RUN_WHY=""
  rec="$(worktree_tree_record "$tree" 2>/dev/null)" || rec=""
  tp="$(_wt_field "$rec" plan)"
  case "$tp" in
    /*) : ;;
    *) LINE_RUN_ONTO="$(session_working_branch "$root" "$sid")" \
         || { LINE_RUN_WHY="${LINE_RUN_ONTO:-no-bound-plan}"; LINE_RUN_ONTO=""; return 1; }
       LINE_RUN_PLAN="$(session_plan "$root" "$sid")" || { LINE_RUN_WHY="no-bound-plan sid=${sid}"; return 1; }
       return 0 ;;
  esac
  LINE_RUN_BY="$(_wt_field "$rec" spawned-by)"
  verdict="$(session_run "$root" "$sid")"
  case "$verdict" in bound-*) sp="${verdict#* }" ;; esac
  if [ -n "$sp" ] && ! _line_same_file "$sp" "$tp"; then
    LINE_RUN_WHY="plan-mismatch tree-plan=${tp} session-plan=${sp} — the tree belongs to another run than this session's; land it from a session bound to its plan"
    return 1
  fi
  run_open "$tp"; st=$?
  case "$st" in
    0) : ;;
    3) LINE_RUN_WHY="bound-unreadable plan=${tp}"; return 1 ;;
    *) case "$verdict" in
         bound-closed\ *) : ;;
         *) LINE_RUN_WHY="plan-closed plan=${tp} — the tree's run is closed; only the session bound to it lands its last rows"; return 1 ;;
       esac ;;
  esac
  LINE_RUN_ONTO="$(plan_working_branch "$tp")"
  [ -n "$LINE_RUN_ONTO" ] || { LINE_RUN_WHY="no-working-branch plan=${tp}"; return 1; }
  LINE_RUN_PLAN="$tp"
}
# THE SESSION A LANDING RUNS UNDER. The publish writes the plan through a plan verb, which writes only the plan its
# session is bound to, and marks the launch row on that session's roster; so the landing takes a session whose binding
# names the tree's plan: the asking session's, else the spawning session's. rc 0 when <sid>'s binding names <plan>.
_line_bound_to() {  # <root> <sid> <plan>
  local p
  [ -n "${2:-}" ] && p="$(session_plan "$1" "$2")" && _line_same_file "$p" "$3"
}

# ---------------------------------------------------------------------------- the hand landing
# `spawn-worktree.sh land <tree> --by-hand --reason '<why>'` (D9, AC-5.1): the person's landing.
# The tree is judged as land judged it (lib/worktree.sh `_wt_land_checks`) and by the `.bionic` guard
# on the accepted head and the row's head, before anything is written; then the row enters the line,
# its candidate is built on the base rule's base, no suite runs, the comment lint reads the candidate's added
# comments as the queue's does, and it publishes through
# `line_publish`, the queue's one publish and lock. Its carrier is this call, in a subshell of its
# own: when it ends, published or not, its entry holds nothing.
# THE WRITER'S VERDICTS, IN THE PERSON'S WORDS. A hand landing runs nothing, so what it records of the
# row's suites is what the person says of the writer's run: the suites, the commit they were green at
# (a commit the row's head holds) and the log that shows it. Before the publish, each is one green verdict
# for the row keyed by that commit, written by the line's one verdict writer, its log that source. All
# three or none: with none the landing records the row alone, as before.
line_land_by_hand() {  # <tree> <root> <sid> <why> [<suites> <green-at> <log>] -> LANDED | REFUSED
  local target="${1:-}" root="${2:-}" sid="${3:-}" why="${4:-}" suites="${5:-}" at="${6:-}" log="${7:-}" onto plan s
  [ -n "$why" ] || { _wt_refuse "no-reason path=${target:-<none>} — a hand landing says why: land <tree> --by-hand --reason '<why>'"; return 2; }
  case "$why" in *'|'*|*$'\n'*|*$'\r'*) _wt_refuse "reason-unwritable path=${target:-<none>} — the reason holds a | or a line break; say it on one line without |"; return 2 ;; esac
  if [ -n "${suites}${at}${log}" ]; then
    { [ -n "$suites" ] && [ -n "$at" ] && [ -n "$log" ]; } || {
      _wt_refuse "verdicts-incomplete path=${target:-<none>} — the writer's verdicts are its suites, the commit they were green at and its log: --suites <a,b> --green-at <commit> --log <path>, all three or none"; return 2; }
    suites="$(_line_suites "$suites")" && [ "$suites" != none ] || {
      _wt_refuse "suites-unreadable path=${target:-<none>} suites=${5} — name suites bare or by path"; return 2; }
    case "$log" in *'|'*|*$'\n'*|*$'\r'*) _wt_refuse "log-unwritable path=${target:-<none>} — the log path holds a | or a line break"; return 2 ;; esac
  fi
  [ -n "$sid" ] || { _wt_refuse "no-session path=${target:-<none>}"; return 2; }
  _line_load_run || { _wt_refuse "run-library-unloadable path=${_LINE_LIB_DIR}/run.sh"; return 2; }
  line_tree_run "$target" "$root" "$sid" || { _wt_refuse "$LINE_RUN_WHY"; return 2; }
  onto="$LINE_RUN_ONTO"; plan="$LINE_RUN_PLAN"
  for s in "$sid" "$LINE_RUN_BY"; do _line_bound_to "$root" "$s" "$plan" && break; s=""; done
  [ -n "$s" ] || { _wt_refuse "no-bound-session plan=${plan} path=${target:-<none>} — no session bound to the tree's plan, so its row cannot be written; bind this session to it (session-poker.sh bind ${plan}), land again"; return 2; }
  ( _line_hand "$target" "$onto" "$plan" "$s" "$why" "$suites" "$at" "$log" )
}
# THE WRITER'S RUN, IN THE PERSON'S WORDS: the two writers of what a hand landing records of the row's suites, one for
# both hand landings (`land --by-hand` above and `session-poker.sh row-landed --by-hand`), so the record they leave is
# one shape and the floor's judge (lib/proof.sh `_proof_past_f`) proves either. `_line_hand_ready` writes the row's
# `ready` event, naming the suites (`none` when the person named none), and sets LINE_ME, the carrier a publish locks
# by. `_line_hand_verdicts` writes one green verdict per suite, keyed by the commit they were green at, the log that
# source; a suite it cannot write is left in LINE_UNWRITTEN. Both go before the published line: the judge reads the
# row's suites from the ready event, and the publish's reading of the reviews the row answers reads the verdicts.
_line_hand_ready() {  # <plan> <row> <commit> <branch> <tree> <suites | empty> -> 0 written
  _line_me
  line_event "$1" ready "row=$2" "name=-" "commit=$3" "branch=$4" "tree=$5" "suites=${6:-none}" debt=- "carrier=${LINE_ME}"
}
_line_hand_verdicts() {  # <plan> <row> <green-at> <suites> <log> -> 0 written; 1 with LINE_UNWRITTEN the suite that was not
  local s
  LINE_UNWRITTEN=""
  for s in $(printf '%s\n' "$4" | tr ',' ' '); do
    LINE_WIDTH=- _line_verdict_put "$1" "$2" "$3" "$s" green "$5" >/dev/null || { LINE_UNWRITTEN="$s"; return 1; }
  done
}
_line_hand() {  # <tree> <onto> <plan> <sid> <why> <suites | empty> <green-at> <log> — the carrier's own subshell
  local target="$1" onto="$2" plan="$3" sid="$4" why="$5" suites="$6" at="$7" vlog="$8" wt root branch head acc rec row by c lt lb rc i n s g="" lo lc
  _wt_land_checks "$target" "$onto" "$plan" 0 || return 2
  wt="$_WT_ABS"; root="$_WT_ROOT"; branch="$_WT_BRANCH"
  head="$(git -C "$wt" rev-parse --verify -q HEAD 2>/dev/null)"
  if [ -n "$suites" ]; then
    g="$(git -C "$wt" rev-parse --verify -q "${at}^{commit}" 2>/dev/null)" && git -C "$wt" merge-base --is-ancestor "$g" "$head" 2>/dev/null \
      || { _wt_refuse "green-at-not-in-row green-at=${at} branch=${branch} — the commit the suites were green at is one the row's head holds"; return 2; }
  fi
  acc="$(git -C "$root" rev-parse --verify -q "refs/heads/${onto}" 2>/dev/null)"
  c="$(_wt_bionic_committed "$root" "$acc" "$head")" && {
    c="${c%/}"; _wt_refuse_bionic "$wt" "$branch" "$onto" "${c%% *}" "${c#* }" "$(_wt_bionic_kind "$root" "$acc")"; return 2
  }
  rec="$(line_record "$plan")" && _wt_proofs_prove "$rec" || {
    _wt_refuse "record-unwritable why=proofs-unwritable path=${rec:-<none>} branch=${branch} — the landing record cannot be written, so nothing is published; make it writable, land again"; return 2
  }
  row="$(_wt_proofs_row "$root" "$plan" "$wt")" || row="$branch"
  case "$row" in *'|'*) _wt_refuse "row-unwritable branch=${branch}"; return 2 ;; esac
  by="$(git -C "$root" config user.name 2>/dev/null)"
  [ -n "$by" ] || by="$(git -C "$root" var GIT_AUTHOR_IDENT 2>/dev/null | sed 's/ <.*//')"
  by="${by//|/}"; [ -n "$by" ] || by="-"
  _line_hand_ready "$plan" "$row" "$head" "$branch" "$wt" "$suites" >/dev/null || { _wt_refuse "record-unwritable why=proofs-unwritable path=${rec} branch=${branch}"; return 2; }
  # The person's verdicts go in before the publish, as `row-landed --by-hand` writes them: the publish's own reading of
  # the reviews the row answers (`_line_born_close`) judges the row by them, so a born row's landing closes its ask.
  if [ -n "$suites" ]; then
    _line_hand_verdicts "$plan" "$row" "$g" "$suites" "$vlog" \
      || { _wt_refuse "verdicts-unwritten row=${row} path=${rec} — the verdict for ${LINE_UNWRITTEN} at ${g} is not recorded, so nothing is published; make the record writable, land again"; return 2; }
  fi
  LINE_KIND=hand; LINE_BY="$by"; LINE_WHY="$why"; LINE_SID="$sid"
  n="${BIONIC_LINE_HAND_WAIT:-900}"; case "$n" in ''|*[!0-9]*) n=900 ;; esac
  lt=""; lb=""; i=0; rc=3
  while [ "$rc" = 3 ]; do
    local base
    base="$(_line_entries "$rec" "$(line_head "$plan")" | awk -F'\t' -v r="$row" '$1 == r { print $5; exit }')"
    if [ -z "$base" ]; then
      # Counted already: a person's own git merge carried it.
      _wt_refuse "not-in-line branch=${branch} — the row left the line before its publish (git log ${onto})"; rc=2; break
    fi
    if [ "$base" != - ]; then
      # One candidate per base, as the queue builds it (`_line_carry` 2): a retry on the base this call last built on
      # publishes that candidate again, and only a new base builds, lints and records another.
      if [ "$base" != "$lb" ]; then
        [ -n "$lt" ] || lt="$(landing_tree_take "$root")" || { _wt_refuse "landing-tree-unavailable root=${root}"; rc=2; break; }
        if ! c="$(line_build "$lt" "$base" "$head" "$branch")"; then
          line_event "$plan" returned "row=${row}" why=conflict "detail=${c:-?}" >/dev/null
          _wt_refuse "conflict branch=${branch} onto=${onto} files=${c:-<unreadable>} — the row does not merge onto what is ahead of it; merge ${onto} into the tree, land again"; rc=2; break
        fi
        # The comment lint the queue runs (`_line_carry` 3b), over the same range: a comment the row adds that cites
        # the run returns the row with a LINT line per hit, and nothing publishes.
        lo="$(_line_comment_lint "$root" "$base" "$c")"; lc=$?
        case $lc in
          0) ;;
          1) line_event "$plan" returned "row=${row}" why=lint "detail=$(printf '%s\n' "$lo" | head -1)" >/dev/null
             printf '%s\n' "$lo" | while IFS= read -r s; do printf 'LINT %s %s\n' "$row" "$s"; done
             _wt_refuse "lint branch=${branch} — a comment the row adds cites the run; say the reason without it, land again"; rc=2; break ;;
          *) _wt_refuse "lint-unreadable row=${row} — ${lo:-the lint printed nothing}"; rc=2; break ;;
        esac
        line_event "$plan" candidate "row=${row}" "base=${base}" "commit=${c}" "tree=${lt}" >/dev/null
        lb="$base"
      fi
      line_publish "$plan" "$row"; rc=$?
      [ "$rc" = 3 ] || break
    fi
    i=$((i + 1)); [ "$i" -le $((n * 5)) ] || { _wt_refuse "line-wait branch=${branch} — an entry ahead has not published in ${n} s; land again"; rc=2; break; }
    sleep 0.2
  done
  [ -z "$lt" ] || landing_tree_free "$lt"
  [ "$rc" = 0 ] || return 2
  [ -z "$suites" ] || printf 'verdicts: %s green at %s, from %s\n' "$suites" "$g" "$vlog"
  _wt_hand_remove "$wt" "$root" "$branch" "$onto" "${LINE_CHECKOUT:-<none>}" "$LINE_PUBLISHED" "$rec" || return $?
  # What is owed, when the row has an agent on this session's roster (T6): its task, then its stop.
  [ -z "$LINE_MARKED" ] || _line_owed "$row" "$LINE_PUBLISHED" "$LINE_MARKED"
}

# ---------------------------------------------------------------------------- the carrier
# `spawn-worktree.sh ready [--within <seconds>]` (wave-28 T4; D3, D5, D31; AC-1.1, AC-1.2, AC-1.5 to
# AC-1.7, AC-3.1, AC-14.1): the writer's one act, run from its own tree. The tree is judged once: on
# its branch, then land's own checks (`_wt_land_checks`: clean, ahead, a plan not past judgment), then
# the `.bionic` guard on the accepted head and the row's head, before any landing tree is taken. Then
# `ready` is appended with the row, the roster name, the suites it lands on and its declared debt,
# all read off the roster's launch line, and this call becomes the entry's carrier: it loops on the
# fold until the entry is published (0), returned (1), or out of time (75, the entry kept).
#
# WHAT DECIDES IS THE CANDIDATE'S OWN RUN. Each named suite runs in the landing tree at the candidate,
# admitted by the gate (`gate_ask landing <suite> --within <s>`), its output in a log under the record
# directory; no stamp is read anywhere on this path (AC-1.2).
#
# PROVED AHEAD, ACCEPTED IN ORDER (D5). The candidate is built on the base rule's base, which may be
# the candidate of an entry still proving ahead of it. When that base is replaced while a suite runs,
# the run is stopped (its runner and every process under it), `discarded` is appended and the
# candidate is rebuilt. A conflict with the accepted head returns the row; one with a candidate
# ahead waits until that base changes. The publish is `line_publish`, asked once the entry is first
# in line on the accepted head.
LINE_POLL="${BIONIC_LINE_POLL:-1}"
case "$LINE_POLL" in ''|.|*.*.*|*[!0-9.]*) LINE_POLL=1 ;; esac   # seconds, whole or decimal; else the default

_line_load_gate() {
  declare -F gate_ask >/dev/null 2>&1 && return 0
  # shellcheck source=/dev/null
  [ -r "$_LINE_LIB_DIR/gate.sh" ] && . "$_LINE_LIB_DIR/gate.sh" 2>/dev/null
  declare -F gate_ask >/dev/null 2>&1
}
_line_plan_agent() {  # <plan> <row> -> the plan row's agent cell
  local rec
  _wt_units_load || return 1
  while IFS= read -r rec; do
    [ "$(units_field "$rec" id)" = "$2" ] || continue
    units_field "$rec" agent; return 0
  done <<EOF
$(units_rows "$1" 2>/dev/null)
EOF
  return 1
}
# `lands_on=` as the roster holds it (labels, D4): `none`, or suites separated by `,` or blanks, each a
# bare file name or a path, with or without `.test.sh`. Prints them as `<name>.test.sh` or
# `<dir>/<name>.test.sh`, comma-joined, a repeat dropped. THE LABEL'S OWN GRAMMAR (wave-28 T64) is the one
# brief.sh lifts a `Lands-on:` line with, and since wave-35 T6 it is one function both paste in (suite.sh
# `BIONIC_SUITE_NAME_AWK`), so a value no label could have written (`run.sh`, the budget's full-runner token,
# `a.b`, `../x.test.sh`) is no suite here either. The value of `suites_allowed=` goes through here too: one
# parser, one verdict.
_line_suites() {  # <lands_on value> -> `a.test.sh,d/b.test.sh` | none; 1 when a name is not a suite
  case "$1" in none|none[[:space:]]*) printf 'none\n'; return 0 ;; esac
  printf '%s\n' "$1" | tr ', \t' '\n\n\n' | awk "$BIONIC_SUITE_NAME_AWK"'
    NF { t = suite_name($0); if (t == "" && lands_cmd_entry($0)) t = $0; if (t == "") { bad = 1; exit }
         if (index("," o ",", "," t ",") == 0) o = o (o == "" ? "" : ",") t }
    END { if (bad || o == "") exit 1; print o }'
}
# A LANDS-ON COMMAND (wave-39 T20; D20, AC-14.3): an entry the lift wrote as suite.sh `lands_cmd` spells it, a
# command the brief declared under Re-executes: (the dispatch wall held it to them). `_line_suites` keeps it as it
# is; ready runs it in the landing tree (`_line_runner`, suite.sh `bionic_command_start`) and judges it by its exit
# code (`_line_verdict`); its red is the row's (`_line_red_owner`). Where a suite is named by its file name, it is
# named so (`_line_gate_key`, `_line_suite_log`).
# The key the gate keeps an entry's cost under: a suite's file name; a command's text as booked.sh keys a command
# run (`booked_one_line`, its first 60 characters), so a landing and the writer's own run share one history.
_line_gate_key() {  # <lands_on entry> -> its gate key
  local c
  c="$(bionic_lands_cmd "${1:-}")" || { printf '%s' "${1##*/}"; return 0; }
  c="${c//|/ }"; c="${c//$'\t'/ }"
  printf '%s' "${c:0:60}"
}
# The suite file a command names, the first word that is one (quotes off), as `suite_name` spells it; nothing when it
# names none (wave-39 T20: the command is then keyed by the tree).
_line_cmd_suite() {  # <command>
  printf '%s\n' "$1" | tr ' \t' '\n\n' | tr -d "\"'" | awk "$BIONIC_SUITE_NAME_AWK"'
    /\.test\.sh$/ { t = suite_name($0); if (t != "") { print t; exit } }'
}

# THE ROW THE WALL READS (wave-28 T64; D26, REQ-7 AC-7.2, REQ-2 AC-2.11). The launch line is the row `row=` or
# the plan's agent cell finds first, and it stays the source of the debt (`lands_red=`, written by the dispatch
# wall alone). The row's SUITES are the budget the walls hold the agent to: `amend` widens them, `hold`, `extend`
# and the landed mark copy them forward, and `adopt` carries them across a clear. So they are read off the row
# `roster_row_for_id` picks for the agent's id (the budget wall's own pick, payload/scripts/lib/roster.sh), never
# off the launch line alone. The id is the latest one a row of the name carries since the name's latest launch
# line: a launch line has none until the recorder identifies the agent, and a roster with no launch line of the
# name (the adopted one) holds the id on the adopted row. No id, no pick: the caller keeps the launch line.
_line_load_roster() {
  declare -F roster_row_for_id >/dev/null 2>&1 && return 0
  # shellcheck source=/dev/null
  [ -r "$_LINE_LIB_DIR/roster.sh" ] && . "$_LINE_LIB_DIR/roster.sh" 2>/dev/null
  declare -F roster_row_for_id >/dev/null 2>&1
}
# THE ROW'S WRITER, FOUND ONCE (wave-34 T4; burns debt row-writer-name). The launch line is the roster's
# row by `row=`, else by the plan row's agent cell as `name=` (labels, D4); the row the walls read is the
# latest row of that name's agent id (`_line_current_row`), else the launch line (an adopted row, with no
# launch line on this roster, stands as both); the writer is that row's name, else the launch line's, else
# the agent cell. `ready` holds a row's landing to this name, and so do `deliver` and the tick's backstop
# (hooks/session-poker.sh), so the writer a ruling is read against is one answer wherever a row lands.
# Sets LINE_LAUNCH, LINE_NOW (either may be empty) and LINE_WRITER; 1 when there is no name at all.
# <agent> is the plan row's agent cell when the caller has it, read off <plan> when it is not given.
line_row_writer() {  # <roster> <plan> <row> [<agent>]
  local roster="${1:-}" agent="${4-}" have=$# n
  LINE_LAUNCH=""; LINE_NOW=""; LINE_WRITER=""
  # The cell is read only when the row's launch line or its name needs it.
  LINE_LAUNCH="$(_wt_launch_row "$roster" row "${3:-}")" || {
    [ "$have" -ge 4 ] || { agent="$(_line_plan_agent "${2:-}" "${3:-}")" || agent=""; have=4; }
    LINE_LAUNCH="$(_wt_launch_row "$roster" name "$agent")" || LINE_LAUNCH=""
  }
  LINE_WRITER="${LINE_LAUNCH:+$(_wt_field "$LINE_LAUNCH" name)}"
  if [ -z "$LINE_WRITER" ]; then
    [ "$have" -ge 4 ] || agent="$(_line_plan_agent "${2:-}" "${3:-}")" || agent=""
    LINE_WRITER="$agent"
  fi
  LINE_NOW="$(_line_current_row "$roster" "$LINE_WRITER")" || LINE_NOW="$LINE_LAUNCH"
  n="${LINE_NOW:+$(_wt_field "$LINE_NOW" name)}"; [ -z "$n" ] || LINE_WRITER="$n"
  [ -n "$LINE_WRITER" ]
}
_line_current_row() {  # <roster> <name> -> the row the walls read for that agent; 1 when no id is known
  local roster="${1:-}" name="${2:-}" id
  { [ -n "$name" ] && [ -f "$roster" ] && [ ! -L "$roster" ]; } || return 1
  _line_load_roster || return 1
  id="$(awk -F'|' -v k="|name=${name}|" '
    index($0, "roster-state/") != 1 || !index($0 "|", k) { next }
    index($0, "|status=intended|") && !index($0, "|amended=") && !index($0, "|extended=") \
      && !index($0, "|held=") && !index($0, "|adopted_from=") { id = "" }
    { for (i = 2; i <= NF; i++) if (index($i, "agent_id=") == 1) { if (length($i) > 9) id = substr($i, 10); break } }
    END { print id }' "$roster" 2>/dev/null)"
  [ -n "$id" ] || return 1
  roster_row_for_id "$roster" "$id"
}

# WHAT A ROW LANDS ON, decided in one place (wave-28 T64; A-orch-188). The value comes from one of two keys and
# both go through `_line_suites`, so `none` parses the same way; what it MEANS is the key's: `lands_on=none <why>`
# is a declared waiver (D17) and lands with no run, while `suites_allowed=none` (or empty) on a row 1.12.0 wrote is
# an absence, since 1.12.0 had no waiver, and is landed by a person. Prints `<key>|<value>|<suites>` and returns
# 0 landed on <suites> (`none` for the waiver) · 3 no suite named, by the absence arm · 1 a name that is no suite.
_line_lands() {  # <the roster row>
  local key=lands_on v suites
  v="$(_wt_field "$1" lands_on)"
  [ -n "$v" ] || { key=suites_allowed; v="$(_wt_field "$1" suites_allowed)"; }
  printf '%s|%s|' "$key" "${v:0:60}"
  [ -n "$v" ] || return 3
  suites="$(_line_suites "$v")" || return 1
  printf '%s' "$suites"
  [ "$suites" != none ] || [ "$key" = lands_on ] || return 3
  return 0
}

line_ready() {  # <tree> <root> <sid> <within seconds | empty> <the same command> -> 0 · 1 · 2 · 75
  local target="${1:-}" root="${2:-}" sid="${3:-}" within="${4:-}" again="${5:-}"
  local onto plan wt branch head acc c row roster roster0="" lsid launch now key name lands suites debt rec deadline=""
  [ -n "$sid" ] || { _wt_refuse "no-session path=${target:-<none>}"; return 2; }
  _line_load_run || { _wt_refuse "run-library-unloadable path=${_LINE_LIB_DIR}/run.sh"; return 2; }
  _line_load_gate || { _wt_refuse "gate-library-unloadable path=${_LINE_LIB_DIR}/gate.sh"; return 2; }
  line_tree_run "$target" "$root" "$sid" || { _wt_refuse "$LINE_RUN_WHY"; return 2; }
  onto="$LINE_RUN_ONTO"; plan="$LINE_RUN_PLAN"
  # THE TREE, JUDGED ONCE: on its branch, then land's own checks.
  git -C "$target" symbolic-ref -q HEAD >/dev/null 2>&1 \
    || { _wt_refuse "detached path=${target:-<none>} — ready lands the row's branch; check it out in the tree, say ready again"; return 2; }
  _wt_land_checks "$target" "$onto" "$plan" 0 || return 2
  wt="$_WT_ABS"; root="$_WT_ROOT"; branch="$_WT_BRANCH"
  head="$(git -C "$wt" rev-parse --verify -q HEAD 2>/dev/null)"
  acc="$(git -C "$root" rev-parse --verify -q "refs/heads/${onto}" 2>/dev/null)"
  row="$(_wt_proofs_row "$root" "$plan" "$wt")" || row="$branch"
  case "$row" in *'|'*) _wt_refuse "row-unwritable branch=${branch}"; return 2 ;; esac
  # THE GUARD, BEFORE ANY LANDING TREE (D31): the accepted head and the row's head; the refusal is
  # handed the writer's tree and branch.
  if c="$(_wt_bionic_committed "$root" "$acc" "$head")"; then
    c="${c%/}"
    printf 'GUARD %s %s %s\n' "$row" "$(_wt_cquote "${c#* }")" "${c%% *}"
    _wt_refuse_bionic "$wt" "$branch" "$onto" "${c%% *}" "${c#* }" "$(_wt_bionic_kind "$root" "$acc")"
    return 1
  fi
  # THE ROSTER'S LAUNCH LINE AND THE ROW THE WALL READS (`line_row_writer`). The suites are the current
  # row's `lands_on=`; the debt is the launch line's `lands_red=` suite, carried on the `ready` event for
  # the debt write (`line_publish` step 6). The asking session's roster first, which holds a row adopted
  # after a clear, then the spawning session's, which holds the launch line a successor never saw.
  for lsid in "$sid" "$LINE_RUN_BY"; do
    [ -n "$lsid" ] || continue
    roster="${root%/}/.bionic/tmp/roster-${lsid}.state"
    [ -n "$roster0" ] || roster0="$roster"
    line_row_writer "$roster" "$plan" "$row"
    [ -z "$LINE_NOW" ] || break
  done
  launch="$LINE_LAUNCH"; now="$LINE_NOW"; name="$LINE_WRITER"
  [ -n "$now" ] || { _wt_refuse "no-launch-row row=${row} roster=${roster0} — ready reads the row's suites off the roster row the walls read"; return 2; }
  _line_bound_to "$root" "$lsid" "$plan" || { _wt_refuse "no-bound-session row=${row} plan=${plan} roster=${roster} — the session that holds the row's launch line is not bound to the tree's plan, so its row cannot be written; bind this session to it (session-poker.sh bind ${plan}), say ready again"; return 2; }
  [ -n "$launch" ] || launch="$now"
  # AN UNREAD RULING HOLDS THE LANDING (wave-33 T10; REQ-1 AC-1.4, D1). A ruling the orchestrator
  # recorded for this writer and nobody has shown it is printed here, marked shown (lib/roster.sh
  # `ruling_take_unread`, the commit wall's same read), and the row is not entered in the line: the
  # writer reads it, acts on it, and says ready again, which then passes. Before any record is written.
  if _line_load_roster && c="$(ruling_take_unread "$roster" "$name" ready)" && [ -n "$c" ]; then
    _wt_refuse "ruling-unread row=${row} name=${name} — the orchestrator ruled while you worked; read it below, act on it, say ready again"
    printf '%s\n' "$c"
    return 2
  fi
  # A RUN OPEN AT UPGRADE CONTINUES (wave-28 T21; D26, AC-7.2). A row 1.12.0 wrote carries no `lands_on=`; its
  # record of the brief's `Suites:` is `suites_allowed=`, and those are the suites `ready` proves (`_line_lands`).
  lands="$(_line_lands "$now")"; c=$?
  key="${lands%%|*}"; lands="${lands#*|}"; suites="${lands#*|}"; lands="${lands%%|*}"
  case $c in
    3) _wt_refuse "no-lands-on row=${row} name=${name:-<none>} ${key}=${lands} — no suite to run; land ${wt} --by-hand --reason '<why>'"; return 2 ;;
    1) _wt_refuse "lands-on-unreadable row=${row} ${key}=${lands} — name suites bare, or land ${wt} --by-hand --reason '<why>'"; return 2 ;;
  esac
  # THE SUITE BAR (wave-39 T39; D1, AC-3.2): a Lands-on suite promising more than LINE_SUITE_BAR is refused
  # here, before any record, lease or runner: the writer splits it and says ready again. Exit 1, the row's to fix.
  c="$(_line_too_long "$suites" "$wt" "$root" "$acc" "$head")"
  [ -z "$c" ] || { printf '%s\n' "$c"; return 1; }
  # The debt is a suite's file name; the full-suite runner, or anything else, is never one (B4). Its
  # token (`lands_red=<suite> until <token>`) rides to the debt write in LINE_DEBT_TOKEN.
  debt="$(_wt_field "$launch" lands_red)"; LINE_DEBT_TOKEN=-
  case "$debt" in *' until '?*) LINE_DEBT_TOKEN="${debt#* until }" ;; esac
  debt="${debt%% *}"; case "$debt" in ?*.test.sh) : ;; *) debt=- ;; esac
  case "${name}${debt}" in *'|'*|'') _wt_refuse "row-unwritable branch=${branch}"; return 2 ;; esac
  rec="$(line_record "$plan")" && _wt_proofs_prove "$rec" || {
    _wt_refuse "record-unwritable why=proofs-unwritable path=${rec:-<none>} branch=${branch} — the landing record cannot be written, so nothing is published; make it writable, say ready again"; return 2
  }
  [ -z "$within" ] || deadline=$(( $(_res_now) + 10#$within ))   # decimal: `08` is eight seconds
  # THE PROMISE, PRINTED (wave-39 T8; D11, AC-4.3): once, before the carrier starts, the seconds the row's suites
  # promise now against the --within it was given. A suite whose promise the time left cannot hold is waited,
  # never started short (`_line_time_for`, D3); this line says the sum up front. No --within, no line.
  [ -z "$within" ] || printf 'promised %ss of %ss\n' "$(_line_promise_total "$suites" "$wt" "$root" "$acc" "$head")" "$((10#$within))"
  LINE_SID="$lsid"   # the session the publish's plan write and roster mark run under: the one holding the launch line
  _LINE_WITHIN="$within"   # the --within the waiting: reasons name (T31)
  ( _line_carry "$plan" "$rec" "$root" "$row" "$name" "$head" "$branch" "$wt" "$suites" "$debt" "$deadline" "$again" )
}

_line_owed() { printf 'landed %s %s — owed: complete task %s, then stop %s\n' "$1" "$2" "$1" "$3"; }   # <row> <commit> <name>
# THE ROW'S DEBT (wave-30 T22; D2, P2, AC-11.3): `debt: burned <N>, touched <M>` for <row>, when the run
# keeps a debt ledger (lib/proof.sh `proof_debt_row_counts`): N the items whose last cell says `burned
# <row>`, M the items one of whose sites the row's `Files` cell covers. Printed between LANDED and the
# owed line, so the owed line stays the last line of ready's output. Nothing when there is no ledger.
_line_debt() {  # <plan> <row>
  local root led cell="" rec
  if ! declare -F proof_debt_row_counts >/dev/null 2>&1; then
    # shellcheck source=/dev/null
    [ -r "$_LINE_LIB_DIR/proof.sh" ] && . "$_LINE_LIB_DIR/proof.sh" 2>/dev/null
    declare -F proof_debt_row_counts >/dev/null 2>&1 || return 0
  fi
  root="$(_line_root "${1:-}")" || return 0
  led="$(proof_debt_ledger_path "$root" "$1")" && [ -f "$led" ] || return 0
  _wt_units_load || return 0
  while IFS= read -r rec; do
    [ "$(units_field "$rec" id)" = "$2" ] || continue
    cell="$(units_field "$rec" Files)"; break
  done <<LINE_DEBT_ROWS
$(units_rows "$1" 2>/dev/null)
LINE_DEBT_ROWS
  # shellcheck disable=SC2046
  set -- $(proof_debt_row_counts "$led" "$2" "$cell")
  printf 'debt: burned %s, touched %s\n' "${1:-0}" "${2:-0}"
}
# THE REVIEW-BORN COUNT (wave-30 T21; REQ-2 AC-2.3, D4): `review-born rows: <N> of cap <M>`, N the plan's
# `## SDLC State` lines carrying `born: review` (lib/units.sh `units_born`, the one place the count reads),
# M its fix-cap: rendered (`units_fix_cap`; the rigor: level's default when the field is absent). Printed
# after the debt line, so the owed line stays last. Nothing when the plan has neither field nor level.
_line_review_born() {  # <plan>
  local cap n
  _line_load_run && _wt_units_load || return 0
  declare -F units_fix_cap >/dev/null 2>&1 || return 0
  cap="$(units_fix_cap "${1:-}")" && [ -n "$cap" ] || return 0
  n="$(units_born "$1" 2>/dev/null | awk 'NF { n++ } END { print n + 0 }')"
  printf 'review-born rows: %s of cap %s\n' "$n" "$cap"
}
# A LANDING NEVER WAITS IN SILENCE (wave-38 T31; D21, D22; A-orch-43): every WAITING line is followed by
# `waiting: <reason>`, what held the row when its time ran out. The WAITING line itself is unchanged.
_line_waiting() {  # <row> <the same command> [<reason>]
  printf 'WAITING %s — run again: %s\n' "$1" "$2"
  printf 'waiting: %s\n' "${3:-the time in --within ${_LINE_WITHIN:-} ran out}"
}
# The reasons the line's own checks and the gate give (A-T31-6), one sentence each.
_line_time_why() {  # <suite> <deadline> [<landing tree>] -> a suite's promise against the time left
  local p s
  _gate_store >/dev/null 2>&1
  p="$(_gate_promise "$1" "${3:-}" 2>/dev/null)"; s="${p##*:}"
  printf 'suite %s promises %ss and %ss are left in --within %s' "$1" "${s:-0}" "$(( $2 - $(_res_now) ))" "${_LINE_WITHIN:-}"
}
_line_width_why() {  # -> the gate's answer of 0 to this landing, naming the older landing it serves
  local o
  o="$(gate_width_older "${_LINE_KEY:-}" 2>/dev/null)"
  if [ -n "$o" ]; then printf 'gate answered 0 for this landing (%s is older)' "$o"
  else printf 'gate answered 0 for this landing'
  fi
}
_line_late() { [ -n "$1" ] && [ "$(_res_now)" -ge "$1" ]; }   # <deadline | empty>
# The seconds <suites> promise now, summed: each one's `_gate_promise` from <tree>'s project, as `_line_time_for`
# reads it. 0 for a suite with no recorded duration, and when the store cannot be read. A
# suite the candidate will not hold, as its merge decides it (`_line_merge_holds`), promises nothing.
_line_promise_total() {  # <suites, comma-joined | none> <tree> <root> <accepted head> <row head>
  local s p mb t=0
  _gate_store >/dev/null 2>&1 || { echo 0; return 0; }
  mb="$(git -C "$3" merge-base "${4:-}" "${5:-}" 2>/dev/null)"
  for s in $(printf '%s\n' "$1" | tr ',' ' '); do
    [ "$s" != none ] || continue
    _line_merge_holds "$3" "$mb" "${4:-}" "${5:-}" "$s" || continue
    p="$(_gate_promise "$(_line_gate_key "$s")" "${2:-}" 2>/dev/null)"; p="${p##*:}"
    case "$p" in ''|*[!0-9]*) p=0 ;; esac
    t=$((t + p))
  done
  printf '%s\n' "$t"
}

# THE SUITE BAR, HELD: each Lands-on entry the row's candidate will hold whose `_gate_promise` is over LINE_SUITE_BAR,
# one `too-long <entry> <s>s — split it` line; nothing when none is. The candidate is not built yet, so whether it
# holds a suite is read as its merge will (`_line_merge_holds`). A suite it will not hold is not judged: one the row
# removed is recorded absent by the carrier, so a split row naming its old whole still lands, and a name no tree
# holds stalls there. A command entry names no file, so it is always held, and is judged under its gate key
# (`_line_gate_key`), the text its own runs are booked under. A store that cannot be read judges nothing, as
# `_line_promise_total` sums nothing: the runner's own ask refuses a gate that is not there.
_line_too_long() {  # <suites, comma-joined | none> <tree> <root> <accepted head> <row head>
  local s p mb
  _gate_store >/dev/null 2>&1 || return 0
  mb="$(git -C "$3" merge-base "${4:-}" "${5:-}" 2>/dev/null)"
  for s in $(printf '%s\n' "$1" | tr ',' ' '); do
    [ "$s" != none ] || continue
    bionic_lands_cmd "$s" >/dev/null || _line_merge_holds "$3" "$mb" "${4:-}" "${5:-}" "$s" || continue
    p="$(_gate_promise "$(_line_gate_key "$s")" "${2:-}" 2>/dev/null)"; p="${p##*:}"
    case "$p" in ''|*[!0-9]*) continue ;; esac
    [ "$p" -gt "$LINE_SUITE_BAR" ] && printf 'too-long %s %ss — split it\n' "$s" "$p"
  done
  return 0
}
# 0 when the merge of <ours> and <theirs> holds <suite>, as a three-way merge decides a file's presence: the side
# that changed it from <merge base> wins, and both sides agreeing is the answer. A conflicted edit still holds it.
_line_merge_holds() {  # <root> <merge base> <ours> <theirs> <suite>
  local m=0 o=0 t=0
  _line_holds "$1" "$2" "$5" && m=1
  _line_holds "$1" "$3" "$5" && o=1
  _line_holds "$1" "$4" "$5" && t=1
  if [ "$o" = "$t" ] || [ "$m" != "$t" ]; then [ "$t" = 1 ]; else [ "$o" = 1 ]; fi
}

# THE LANDING'S PLACE IN THE GATE'S LINE (wave-38 T30; D22; A-T6-10, A-orch-49; gate.sh THE LEASE). The
# gate holds every landing behind the oldest lease, and the line holds a landing at publish behind every
# entry ahead of it: the two orders must be one, or the gate's oldest waits on the line's first while the
# gate answers that one 0, and neither moves. So a ready enters in ONE ACT, under the record's ready lock
# (`<record dir>/ready.lock`): it opens the landing's lease and appends its `ready` event, which carries
# the lease's age (`age=<first>:<seq>`). A ready that opens a new entry takes a fresh age, so it is last
# in both; a ready of an entry still open (after WAITING or STALLED) takes the age that entry was given,
# so it keeps its place in both, however long it was away. The carrier's EXIT trap ends the lease: on
# WAITING (rc 75, "its place kept") it is left, nobody's, ordering no one; on every other exit it is
# closed. A carrier killed outright leaves a dead carrier, which the gate prunes. No lease, no entry: a
# landing the gate cannot order is refused before its event is written (rc 2, gate-unavailable).
_line_entry_age() {  # <record> <row> -> the age of the row's open entry, nothing when it has none
  [ -f "$1" ] || return 0
  awk -F'|' -v r="$2" "$_LINE_FIELDS_AWK"'
    { ev = line_ev() }
    ev == "" || line_kv("row") != r { next }
    ev == "ready" { if (!open) { open = 1; age = "" } a = line_kv("age"); if (age == "" && a != "") age = a; next }
    ev == "published" || ev == "returned" { open = 0; age = "" }
    END { if (open && age != "") print age }' "$1" 2>/dev/null
}
_line_ready_take() {  # <lock dir> -> 0 held by this carrier; 1 when it could not be had in about a minute
  local i=0
  while ! _slots_take_one "${1%/*}" "$1" "${LINE_ME%%:*}" ready; do
    i=$((i + 1)); [ "$i" -lt 600 ] || return 1
    sleep 0.1
  done
}
_line_enter() {  # <plan> <rec> <row> <deadline | empty> <ready event's key=value>...
  local plan="$1" rec="$2" row="$3" deadline="$4" lk span="" was age rc i=0
  shift 4
  lk="${rec%/*}/ready.lock"
  _line_ready_take "$lk" || { _wt_refuse "ready-lock-unavailable row=${row} lock=${lk} — another ready of this line holds it; say ready again"; return 2; }
  was="$(_line_entry_age "$rec" "$row")"
  [ -z "$deadline" ] || { span=$(( deadline - $(_res_now) )); [ "$span" -ge 0 ] || span=0; }
  while :; do
    age="$(gate_landing_open "$_LINE_KEY" "$LINE_ME" "$span" "${was:-new}" 2>/dev/null)"; rc=$?
    [ "$rc" -eq 1 ] && [ "$i" -lt 3 ] || break   # the gate's lock: asked again, three times
    i=$((i + 1))
  done
  if [ "$rc" -ne 0 ] || [ -z "$age" ]; then
    _line_lock_drop "$lk"
    _wt_refuse "gate-unavailable row=${row} — the gate could not open the landing's lease (rc ${rc}), so the line cannot order it; say ready again"
    return 2
  fi
  _LINE_LEASED=1
  if ! line_event "$plan" ready "$@" "age=${age}" >/dev/null; then
    _line_lock_drop "$lk"
    _wt_refuse "record-unwritable why=proofs-unwritable path=${rec}"
    return 2
  fi
  _line_lock_drop "$lk"
}
_line_lease_end() {  # <the carrier's exit status>
  [ -n "${_LINE_LEASED:-}" ] || return 0
  if [ "${1:-}" = 75 ]; then gate_landing_leave "$_LINE_KEY" "$LINE_ME" >/dev/null 2>&1
  else gate_landing_close "$_LINE_KEY" "$LINE_ME" >/dev/null 2>&1
  fi
  return 0
}

# THE CARRIER'S LOOP, in its own subshell, whose pid is the `ready` event's carrier: the entry is
# present exactly while this runs, its landing tree is freed and its lease ended when it ends.
_line_carry() {  # <plan> <rec> <root> <row> <name> <commit> <branch> <tree> <suites> <debt> <deadline> <again>
  local plan="$1" rec="$2" root="$3" row="$4" name="$5" com="$6" branch="$7" wt="$8" suites="$9"
  local debt="${10}" deadline="${11}" again="${12}" head all ent base cand cbase first waitbase="" held=""
  local c rc s said anchored="" linted=""
  _LINE_LT=""   # the landing tree, freed when the subshell ends (a global: the trap outlives the locals)
  _LINE_KEY="$(_line_landing_key "$root" "$plan" "$row")"   # the key every runner of this landing asks under (D21)
  _LINE_JT=""   # the red judge's tree, taken on first use (`_line_red_owner`), freed the same way
  _LINE_LEASED=""   # set once this carrier holds the landing's lease (`_line_enter`)
  trap '_line_lease_end "$?"; [ -z "$_LINE_LT" ] || landing_tree_free "$_LINE_LT"; [ -z "$_LINE_JT" ] || landing_tree_free "$_LINE_JT"' EXIT
  _line_me
  _line_enter "$plan" "$rec" "$row" "$deadline" "row=${row}" "name=${name}" "commit=${com}" "branch=${branch}" "tree=${wt}" \
    "suites=${suites}" "debt=${debt}" "carrier=${LINE_ME}" || return 2
  while :; do
    head="$(line_head "$plan")"
    _line_count_git "$plan" "$rec" "$root" "$head"
    all="$(_line_entries "$rec" "$head")"
    first="$(printf '%s\n' "$all" | awk -F'\t' '$4 == "yes" && $7 != "stalled" { print $1; exit }')"
    ent="$(printf '%s\n' "$all" | awk -F'\t' -v r="$row" '$1 == r { print; exit }')"
    [ -n "$ent" ] || { _line_closed "$rec" "$row" "$name" "$plan"; return $?; }
    IFS=$'\t' read -r _ _ _ _ base cand _ _ _ cbase _ _ _ <<EOF
$ent
EOF
    # 1. THE BASE: wait while the entry ahead has no candidate, or while ours conflicts with it. A wait on a
    # conflicting candidate ahead ends once that entry resolves: published (the base is then the accepted
    # head, and a conflict with it returns the row), returned or stalled (the base rule gives the next
    # base) — read off the fold, never off the head (ruling A-orch-51).
    if [ -n "$waitbase" ] && [ "$base" = "$waitbase" ] && ! _line_ahead_open "$all" "$row" "$waitbase"; then
      waitbase=""
    fi
    if [ "$base" = - ] || [ "$base" = "$waitbase" ]; then
      if _line_late "$deadline"; then
        if [ "$base" = - ]; then
          c="$(printf '%s\n' "$all" | awk -F'\t' -v r="$row" '$1 == r { print a; exit } $4 == "yes" && $7 != "stalled" { a = $1 }')"
          c="${c:-the row} ahead has no candidate"
        else
          c="$(printf '%s\n' "$all" | awk -F'\t' -v b="$waitbase" '$6 == b { print $1; exit }')"
          c="conflicts with ${c:-the candidate} ahead"
        fi
        _line_waiting "$row" "$again" "$c"; return 75
      fi
      sleep "$LINE_POLL"; continue
    fi
    waitbase=""
    # 2. THE CANDIDATE, built again whenever its base or the row's commit is not the one it was built of.
    if [ "$cand" = - ] || [ "$cbase" != "$base" ] \
        || [ "$(git -C "$root" rev-parse --verify -q "${cand}^2" 2>/dev/null)" != "$com" ]; then
      [ -n "$_LINE_LT" ] || _LINE_LT="$(landing_tree_take "$root")" || { _LINE_LT=""; _wt_refuse "landing-tree-unavailable root=${root}"; return 2; }
      c="$(line_build "$_LINE_LT" "$base" "$com" "$branch")"; rc=$?
      case $rc in
        0) line_event "$plan" candidate "row=${row}" "base=${base}" "commit=${c}" "tree=${_LINE_LT}" >/dev/null \
             || { _wt_refuse "record-unwritable why=proofs-unwritable path=${rec} branch=${branch}"; return 2; }
           continue ;;
        1) if [ "$base" = "$head" ]; then
             line_event "$plan" returned "row=${row}" why=conflict "detail=${c:-?}" >/dev/null
             printf 'CONFLICT %s %s\n' "$row" "${c:-?}"; return 1
           fi
           waitbase="$base"; continue ;;
        *) _wt_refuse "landing-tree-unpointable tree=${_LINE_LT} base=${base}"; return 2 ;;
      esac
    fi
    # 3a. THE ANCHORS (wave-35 T3; D16, REQ-7 AC-7.2): every mutation anchor every suite in the tree declares,
    # checked on the candidate as git holds it, once per candidate and before any suite runs. A row that
    # rewords an anchored line is refused here even when its Lands-on never runs the suite anchored on it.
    if [ "$anchored" != "$cand" ]; then
      c="$(_line_anchors "$root" "$cand")"; rc=$?
      case $rc in
        0) anchored="$cand" ;;
        1) line_event "$plan" returned "row=${row}" why=anchor-moved "detail=$(printf '%s\n' "$c" | head -1)" >/dev/null
           _wt_refuse "anchor-moved row=${row} candidate=${cand} — a suite's mutation anchor no longer holds on the candidate; re-anchor it in that suite or restore the text, then say ready again"
           printf '%s\n' "$c"; return 2 ;;
        *) _wt_refuse "anchors-unreadable row=${row} — ${c:-the check printed nothing}"; return 2 ;;
      esac
    fi
    # 3b. THE COMMENT LINT, once per candidate and before any suite: a comment the row adds that cites the run
    # returns the row to its writer, one LINT line per hit.
    if [ "$linted" != "$cand" ]; then
      c="$(_line_comment_lint "$root" "$cbase" "$cand")"; rc=$?
      case $rc in
        0) linted="$cand" ;;
        1) line_event "$plan" returned "row=${row}" why=lint "detail=$(printf '%s\n' "$c" | head -1)" >/dev/null
           printf '%s\n' "$c" | while IFS= read -r s; do printf 'LINT %s %s\n' "$row" "$s"; done
           return 1 ;;
        *) _wt_refuse "lint-unreadable row=${row} — ${c:-the lint printed nothing}"; return 2 ;;
      esac
    fi
    # 3. THE PROOF, A DRAIN (wave-37 T1; D3, AC-1.1; wave-38 T6, D21): each named suite not yet green on this
    # candidate, as many runners at once as the gate answers: before the pass's first runner, and again as
    # each one ends, the drain asks `gate_width_ask` for this landing and starts exactly that many
    # (`_line_drain_next`); each runner still files its own `landing` ask, the run's admission record, which
    # the answer has already made room for. The results are taken in the order named, so the
    # record reads as a serial landing's. A suite already red on it is not run again: its red is judged again
    # from its log (below), in its turn. A suite asked twice with no verdict since the entry's ready stalls
    # the entry before anything starts (D8, AC-9.1, AC-9.2): the second time, it is put to the orchestrator
    # with both logs.
    _LINE_REPASS=""
    _line_drain_init
    for s in $(printf '%s\n' "$suites" | tr ',' ' '); do
      [ "$s" != none ] || break
      # EVERY NAMED SUITE RUNS ON THE CANDIDATE: only its own green verdict at this very commit stands for it.
      ! _line_proved "$rec" "$s" "$cand" >/dev/null || continue
      # A SUITE THE ROW REMOVED IS NOT OWED (wave-39 T6; A-orch-5): a row that removes or splits a suite still
      # names it on the Lands-on its brief gave, and a runner could only fail to start it (two `none`s stall the
      # entry). Held by the candidate's base and not by the candidate, it is recorded once, `absent` with no log,
      # and counts as proved; nothing runs for it. A name the base lacks too still stalls (wave-34 T27).
      if _line_removed "$root" "$cbase" "$cand" "$s"; then
        _line_verdict_put "$plan" "$row" "$cand" "$s" absent - >/dev/null; continue
      fi
      said="$(_line_none_logs "$rec" "$row" "$cand" "$s")"
      if [ "$(printf '%s\n' "$said" | awk 'NF { n++ } END { print n + 0 }')" -ge 2 ]; then
        said="$(printf '%s\n' "$said" | awk 'NF { l[++n] = $0 } END { print l[n - 1] "," l[n] }')"
        line_event "$plan" stalled "row=${row}" "logs=${said}" >/dev/null
        printf 'STALLED %s %s\n' "$row" "$said"; return 70
      fi
      _line_drain_add "$s"
    done
    # While the user's order stands no suite starts, here as in tests/run.sh. The entry is returned with the
    # user's words and nothing ran; once the user lifts the order, the writer says ready again.
    if [ "$_LINE_DN" -gt 0 ] && c="$(_line_order "$root")"; then
      line_event "$plan" returned "row=${row}" why=order "detail=${c%%$'\n'*}" >/dev/null
      printf 'ORDER %s %s\n' "$row" "${c#*$'\n'}"; return 1
    fi
    if [ "$_LINE_DN" -gt 0 ]; then
      [ -n "$_LINE_LT" ] || _LINE_LT="$(landing_tree_take "$root")" || { _LINE_LT=""; _wt_refuse "landing-tree-unavailable root=${root}"; return 2; }
      # ONE TREE PER CANDIDATE, POINTED ONCE (D3): every run of the pass starts from the candidate, clean, in
      # the landing tree this carrier holds; nothing points it again while a sibling runs on it (a carrier
      # run again finds the candidate built by the one before it, and no tree yet).
      landing_tree_point "$_LINE_LT" "$cand" || { _wt_refuse "landing-tree-unpointable tree=${_LINE_LT} base=${cand}"; return 2; }
    fi
    while _line_drain_next "$plan" "$rec" "$row" "$cand" "$cbase" "$_LINE_LT" "$deadline"; do
      s="$LINE_SUITE"
      case "$LINE_RESULT" in
        green) _line_verdict_put "$plan" "$row" "$cand" "$s" green "$LINE_LOG" "$LINE_AT" "$LINE_PROMISED" "$LINE_ACTUAL" >/dev/null
          continue ;;
        waiting) c="$LINE_WHY"; _line_drain_stop await "$plan" "$rec" "$row" "$cand" "$cbase"
          _line_waiting "$row" "$again" "$c"; return 75 ;;
        # THE BASE REPLACED: every sibling is stopped with its suite (a run the gate had begun is discarded).
        replaced) _line_drain_stop kill "$plan" "$rec" "$row" "$cand" "$cbase"
          continue 2 ;;
        # NO VERDICT (D8, AC-9.1): the entry keeps its place, every sibling ends with its verdict written, and
        # the pass starts again, where the suite is asked again or the entry stalls.
        none) _line_verdict_put "$plan" "$row" "$cand" "$s" none "$LINE_LOG" "$LINE_AT" "$LINE_PROMISED" "$LINE_ACTUAL" >/dev/null
          _line_drain_stop await "$plan" "$rec" "$row" "$cand" "$cbase"
          continue 2 ;;
        red) _line_verdict_put "$plan" "$row" "$cand" "$s" red "$LINE_LOG" "$LINE_AT" "$LINE_PROMISED" "$LINE_ACTUAL" >/dev/null ;;
        judge) : ;;
        *) _line_drain_stop kill "$plan" "$rec" "$row" "$cand" "$cbase"
          _wt_refuse "gate-unavailable row=${row} suite=${s} — ${LINE_LOG}"; return 2 ;;
      esac
      # A RED IS THE ROW'S ONLY WHEN IT IS NEW (D8, AC-9.3, AC-9.4): the declared debt suite's red, and a
      # red whose failing lines all fail at the accepted head too, count for this row as passed.
      c="$LINE_LOG"
      _line_red_owner "$plan" "$rec" "$row" "$cbase" "$s" "$c" "$debt" "$deadline" "$cand"
      case "$LINE_RED" in
        declared|standing) [ -z "$_LINE_REPASS" ] || continue 2 ;;
        waiting) c="$LINE_WHY"; _line_drain_stop await "$plan" "$rec" "$row" "$cand" "$cbase"
          _line_waiting "$row" "$again" "$c"; return 75 ;;
        replaced) _line_drain_stop kill "$plan" "$rec" "$row" "$cand" "$cbase"
          continue 2 ;;
        gate) _line_drain_stop kill "$plan" "$rec" "$row" "$cand" "$cbase"
          _wt_refuse "gate-unavailable row=${row} suite=${s} — ${LINE_LOG}"; return 2 ;;
        *) _line_drain_stop kill "$plan" "$rec" "$row" "$cand" "$cbase"
           line_event "$plan" returned "row=${row}" why=red "detail=${c}" >/dev/null
           printf 'RED %s %s %s\n' "$row" "$s" "$c"; return 1 ;;
      esac
    done
    # 4. THE PUBLISH, once first in line on the accepted head (line_publish asks both again, locked).
    if [ "$first" != "$row" ] || [ "$cbase" != "$head" ]; then
      if _line_late "$deadline"; then
        if [ "$first" != "$row" ]; then c="not first in line (${first:-none} first)"
        else c="candidate base ${cbase:0:12} is not the head ${head:0:12}"
        fi
        _line_waiting "$row" "$again" "$c"; return 75
      fi
      sleep "$LINE_POLL"; continue
    fi
    said="$(line_publish "$plan" "$row" 2>&1)"; rc=$?
    case $rc in
      0) [ -z "$said" ] || printf '%s\n' "$said"
         printf 'LANDED %s %s\n' "$row" "$cand"; _line_debt "$plan" "$row"; _line_review_born "$plan"; _line_owed "$row" "$cand" "$name"; return 0 ;;
      3|75) : ;;
      4) [ -n "$held" ] || printf '%s\n' "$said"; held=1 ;;
      6) c="$(_wt_bionic_committed "$root" "$head" "$cand")"; c="${c%/}"
         printf 'GUARD %s %s %s\n' "$row" "$(_wt_cquote "${c#* }")" "${c%% *}"
         printf '%s\n' "$said"; return 1 ;;
      5) printf '%s\n' "$said"; return 1 ;;
      *) printf '%s\n' "$said"; return 2 ;;
    esac
    if _line_late "$deadline"; then
      c="$(printf '%s\n' "$said" | awk 'NF { print; exit }')"
      _line_waiting "$row" "$again" "publish: ${c:-rc ${rc}}"; return 75
    fi
    sleep "$LINE_POLL"
  done
}

# The user's order (lib/gate.sh `gate_order`): 0 when one stands, printing `given <ISO-UTC>` and then the refusal
# tests/run.sh prints, with the user's words; 1 when none does.
_line_order() {  # <root>
  local o w at
  o="$(gate_order "$1" 2>/dev/null)" || return 1
  w="${o#*\"}"; w="${w%\"}"; at="${o#given }"; at="${at%% *}"
  printf 'given %s\nrefused — the user'"'"'s order stands: "%s" (given %s). Nothing was run. Only the user lifts it, in their own words; ask the user.\n' "$at" "$w" "$at"
}

# The anchor check (lib/anchors.sh), loaded on first use: its lines, and 0 every anchor holds · 1 one moved
# or cannot be read · 2 the library is not there.
_line_anchors() {  # <root> <commit>
  _line_load_anchors || { printf 'anchors-library-unloadable path=%s/anchors.sh\n' "$_LINE_LIB_DIR"; return 2; }
  anchors_check "$1" "$2"
}
_line_load_anchors() {
  declare -F anchors_check >/dev/null 2>&1 && return 0
  # shellcheck source=/dev/null
  [ -r "$_LINE_LIB_DIR/anchors.sh" ] && . "$_LINE_LIB_DIR/anchors.sh" && declare -F anchors_check >/dev/null 2>&1
}

# THE COMMENT LINT. A comment says what the code does and why; where its history lives belongs to the record. The
# lint reads the lines a candidate adds to a shell or python source under hooks/, payload/, tests/ or agents-src/
# and refuses a comment on one that cites the run: one `<file>:<line> <shapes>` line per hit, rc 1; rc 0 when none
# is; rc 2, with the reason, when the diff cannot be read. Only what is added is judged, so an old comment stands
# until a writer touches its line. A line the same diff removes elsewhere, the same text bar its indent, is moved,
# not added. The comment is the one a lexer reading the whole file at the candidate finds on the line: from an
# unquoted `#` that starts a word to the end of the line, outside quotes and heredoc bodies; in python, from a
# `#` outside a string. A decision id or a bare assumption id is named only beside one of the shapes that refuse.
_LINE_SHAPES_AWK='
function line_shapes(t,   b, e, f, s, n, i, a) {
  b = "(^|[^A-Za-z0-9_])"; e = "([^A-Za-z0-9_]|$)"
  f["epic"] = (t ~ (b "epic[- ]?[0-9]"))
  f["wave"] = (t ~ (b "wave-[0-9]+([^|0-9]|$)") || t ~ (b "wave [0-9]"))
  f["writer"] = (t ~ (b "w[0-9]+-[A-Z]+[0-9]"))
  f["wave-code"] = (t ~ (b "E[0-9]+W[0-9]"))
  f["wave-slice"] = (t ~ (b "W[0-9]+ S[0-9]"))
  f["criterion"] = (t ~ (b "AC-?[0-9]+(\\.[0-9]+)?" e))
  f["requirement"] = (t ~ (b "REQ-?[0-9]+" e))
  f["assumption"] = (t ~ (b "A-orch-[0-9]") || t ~ (b "A-T[0-9]+[-.][0-9]"))
  f["delta"] = (t ~ /\316\224[0-9]/)
  f["record-path"] = (t ~ /\.bionic\/docs\/(record|adrs|ideas|specs|requirements|plans|incidents|spikes)\/[A-Za-z0-9]/ \
    || t ~ /(^|[^A-Za-z0-9_\/<])record\/(wave|epic|w[0-9])/)
  n = split("epic wave writer wave-code wave-slice criterion requirement assumption delta record-path", a, " ")
  s = ""
  for (i = 1; i <= n; i++) if (f[a[i]]) s = s "," a[i]
  if (s == "") return ""
  if (!f["assumption"] && t ~ (b "A-[0-9]+" e)) {
    s = ""; f["assumption"] = 1
    for (i = 1; i <= n; i++) if (f[a[i]]) s = s "," a[i]
  }
  if (t ~ (b "D[0-9]+" e)) s = s ",decision"
  return substr(s, 2)
}'
# The added lines of a `git diff -U0` that carry a shape anywhere on them and are not moved: `<file> TAB <line>`.
_LINE_ADDS_AWK='
function line_trim(t) { sub(/^[ \t]+/, "", t); sub(/[ \t]+$/, "", t); return t }
/^diff --git / { hdr = 1; f = ""; next }
hdr && /^\+\+\+ / { f = substr($0, 5); if (f == "/dev/null") f = ""; else sub(/^b\//, "", f); next }
hdr && /^--- / { next }
/^@@ / { hdr = 0; split($3, c, ","); ln = substr(c[1], 2) + 0; next }
hdr { next }
/^\+/ { if (f != "") { na++; AF[na] = f; AL[na] = ln; AT[na] = substr($0, 2) } ln++; next }
/^-/ { R[line_trim(substr($0, 2))]++; next }
END {
  for (i = 1; i <= na; i++) {
    t = line_trim(AT[i])
    if (R[t] > 0) { R[t]--; continue }
    if (line_shapes(AT[i]) != "") print AF[i] "\t" AL[i]
  }
}'
# The comment on each wanted line of one file: `<line> TAB <comment>`. want= the line numbers, py=1 for python.
# A shell frame is c (commands: the top, `$( )`, `$(( ))`), b (backquoted commands), d (double quotes), s (single),
# x (dollar-single) or p (`${ }`); PD counts the open parens of a `$( )`. A heredoc body is skipped to its word.
_LINE_LEX_AWK='
function push(k) { d++; K[d] = k; PD[d] = 0 }
function heredoc(s, i,   j, n, c, w, e, strip) {
  j = i + 2; n = length(s); strip = 0; w = ""
  if (substr(s, j, 1) == "-") { strip = 1; j++ }
  while (substr(s, j, 1) == " " || substr(s, j, 1) == "\t") j++
  for (; j <= n; j++) {
    c = substr(s, j, 1)
    if (c == "\047" || c == "\"") {
      e = index(substr(s, j + 1), c)
      if (e == 0) { w = w substr(s, j + 1); j = n; break }
      w = w substr(s, j + 1, e - 1); j += e; continue
    }
    if (c == "\\") { w = w substr(s, j + 1, 1); j++; continue }
    if (index(" \t;&|()<>", c)) break
    w = w c
  }
  if (w != "") { nh++; HT[nh] = w; HS[nh] = strip }
  return j - 1
}
BEGIN { n = split(want, a, " "); for (i = 1; i <= n; i++) W[a[i]] = 1; d = 1; K[1] = "c"; hq = 1 }
py {
  com = ""; n = length($0)
  for (i = 1; i <= n; i++) {
    ch = substr($0, i, 1)
    if (tq != "") { if (substr($0, i, 3) == tq) { tq = ""; i += 2 } else if (ch == "\\") i++; continue }
    if (sq != "") { if (ch == "\\") i++; else if (ch == sq) sq = ""; continue }
    if (ch == "#") { com = substr($0, i); break }
    if (ch == "\047" || ch == "\"") { if (substr($0, i, 3) == ch ch ch) { tq = ch ch ch; i += 2 } else sq = ch }
  }
  sq = ""
  if (com != "" && (FNR in W)) printf "%d\t%s\n", FNR, com
  next
}
inh {
  t = $0; if (HS[hq]) sub(/^\t+/, "", t)
  if (t == HT[hq]) { hq++; if (hq > nh) { inh = 0; nh = 0; hq = 1 } }
  next
}
{
  com = ""; n = length($0); prev = ""
  for (i = 1; i <= n; i++) {
    ch = substr($0, i, 1); k = K[d]
    if (k == "s") { if (ch == "\047") d--; prev = ch; continue }
    if (ch == "\\") { i++; prev = "x"; continue }
    if (k == "x") { if (ch == "\047") d--; prev = ch; continue }
    if (ch == "$") {
      c2 = substr($0, i + 1, 1)
      if (c2 == "(") { push("c"); PD[d] = 1; i++; if (substr($0, i + 1, 1) == "(") { PD[d] = 2; i++ } prev = "("; continue }
      if (c2 == "{") { push("p"); i++; prev = "{"; continue }
      if (c2 == "\047" && k != "d") { push("x"); i++; prev = c2; continue }
      prev = ch; continue
    }
    if (ch == "`") { if (k == "b") d--; else push("b"); prev = ch; continue }
    if (k == "d") { if (ch == "\"") d--; prev = ch; continue }
    if (k == "p") {
      if (ch == "}") d--; else if (ch == "\047") push("s"); else if (ch == "\"") push("d")
      prev = ch; continue
    }
    if (ch == "\047") { push("s"); prev = ch; continue }
    if (ch == "\"") { push("d"); prev = ch; continue }
    if (ch == "#" && (prev == "" || index(" \t;&|()<>", prev))) { com = substr($0, i); break }
    if (ch == "(" && d > 1 && k == "c") PD[d]++
    else if (ch == ")" && d > 1 && k == "c") { PD[d]--; if (PD[d] <= 0) d-- }
    else if (ch == "<" && substr($0, i + 1, 1) == "<") {
      if (substr($0, i + 2, 1) == "<") i += 2; else i = heredoc($0, i)
    }
    prev = ch
  }
  if (com != "" && (FNR in W)) printf "%d\t%s\n", FNR, com
  if (nh >= hq) inh = 1
}'
_line_comment_lint() {  # <root> <base> <candidate> -> `<file>:<line> <shapes>` per hit; 0 none · 1 hits · 2 unreadable
  local root="$1" base="$2" cand="$3" diff adds f lines py hits="" out
  diff="$(git -C "$root" -c core.quotePath=false diff -U0 --no-color --no-ext-diff --no-textconv --no-renames \
    --src-prefix=a/ --dst-prefix=b/ "$base" "$cand" -- 'hooks/*.sh' 'hooks/*.py' 'payload/*.sh' 'payload/*.py' \
    'tests/*.sh' 'tests/*.py' 'agents-src/*.sh' 'agents-src/*.py' 2>&1)" \
    || { printf 'diff-unreadable base=%s candidate=%s — %s\n' "$base" "$cand" "$(printf '%s\n' "$diff" | head -1)"; return 2; }
  adds="$(printf '%s\n' "$diff" | LC_ALL=C awk "$_LINE_SHAPES_AWK$_LINE_ADDS_AWK")"
  [ -n "$adds" ] || return 0
  for f in $(printf '%s\n' "$adds" | cut -f1 | awk '!seen[$0]++'); do
    lines="$(printf '%s\n' "$adds" | awk -F'\t' -v f="$f" '$1 == f { printf "%s ", $2 }')"
    py=0; case "$f" in *.py) py=1 ;; esac
    out="$(git -C "$root" show "${cand}:${f}" 2>/dev/null | LC_ALL=C awk -v want="$lines" -v py="$py" "$_LINE_LEX_AWK")"
    hits="${hits}$(printf '%s\n' "$out" | LC_ALL=C awk -F'\t' -v f="$f" "$_LINE_SHAPES_AWK"'
      NF { s = line_shapes(substr($0, index($0, "\t") + 1)); if (s != "") print f ":" $1 " " s }')
"
  done
  hits="$(printf '%s' "$hits" | awk 'NF')"
  [ -n "$hits" ] || return 0
  printf '%s\n' "$hits"
  return 1
}

# is keyed by the commit's tree, `tree:<id>` (anchors.sh's key for a set it cannot derive), unless it names a suite
# file, whose key it then takes.

# An entry other than <row> still in line, present and not stalled, whose candidate is <candidate>:
# the one a conflicting row waits on (A-orch-51). <entries> is `_line_entries`'s output.
_line_ahead_open() {  # <entries> <row> <candidate>
  printf '%s\n' "$1" | awk -F'\t' -v r="$2" -v c="$3" '$1 != r && $6 == c && $4 == "yes" && $7 != "stalled" { f = 1 } END { exit !f }'
}

# The entry left the fold while its carrier ran: a person's own git merge carried it (published
# kind=git), or something else closed it.
_line_closed() {  # <rec> <row> <name> [<plan>]
  local last
  last="$(awk -F'|' -v r="$2" "$_LINE_FIELDS_AWK"'
    { e = line_ev() } line_kv("row") == r && (e == "published" || e == "returned") { l = $0 } END { print l }' "$1" 2>/dev/null)"
  case "$(line_value "$last" ev)" in
    published)
      last="$(line_value "$last" commit)"
      printf 'LANDED %s %s\n' "$2" "$last"; [ -z "${4:-}" ] || { _line_debt "$4" "$2"; _line_review_born "$4"; }; _line_owed "$2" "$last" "$3"; return 0 ;;
  esac
  printf '%s\n' "${last:-RETURNED ${2}}"; return 1
}

# THE VERDICT AT A COMMIT: <suite> is proved at <commit> when the record's latest green, red or absent verdict for it
# at that commit, of any row, is not red (`absent`: the row removed the suite). It prints the commit.
# A verdict is keyed by the commit it ran at: an argument that is not a commit id proves nothing.
_line_proved() {  # <rec> <suite> <commit> -> the commit, when proved
  case "$3" in ''|*[!0-9a-f]*) return 1 ;; esac
  awk -F'|' -v s="$2" -v c="$3" "$_LINE_FIELDS_AWK"'
    line_ev() == "verdict" && line_kv("commit") == c && line_kv("suite") == s {
      v = line_kv("result"); if (v == "green" || v == "red" || v == "absent") ok = (v != "red") }
    END { if (!ok) exit 1; print c }' "$1" 2>/dev/null
}

# The logs of the `none` verdicts for <suite> on <candidate> since the entry was last published, returned
# or stalled, one per line. NOT SINCE ITS LATEST `ready` (wave-38 T6; AC-6.3): every `ready` call writes one,
# and a bounded ready that ends one none per call would otherwise never stall. A ready after STALLED is the
# asked-for retry (AC-9.2), so the stall starts the count again.
_line_none_logs() {  # <rec> <row> <candidate> <suite>
  awk -F'|' -v r="$2" -v c="$3" -v s="$4" "$_LINE_FIELDS_AWK"'
    { e = line_ev() } line_kv("row") != r { next }
    e == "stalled" || e == "published" || e == "returned" { n = 0 }
    e == "verdict" && line_kv("commit") == c && line_kv("suite") == s && line_kv("result") == "none" { l[++n] = line_kv("log") }
    END { for (i = 1; i <= n; i++) print l[i] }' "$1" 2>/dev/null
}
# The log of a red verdict for <suite> on <candidate> since the entry opened, or nothing.
_line_red_log() {  # <rec> <row> <candidate> <suite>
  awk -F'|' -v r="$2" -v c="$3" -v s="$4" "$_LINE_FIELDS_AWK"'
    { e = line_ev() } line_kv("row") != r { next }
    e == "published" || e == "returned" { l = "" }
    e == "verdict" && line_kv("commit") == c && line_kv("suite") == s { l = (line_kv("result") == "red" ? line_kv("log") : "") }
    END { if (l != "") print l }' "$1" 2>/dev/null
}

# A RED IS THE ROW'S ONLY WHEN IT IS NEW (D8). Sets LINE_RED:
#   declared  <suite> is the row's declared debt suite: it publishes, its debt written (line_publish)
#   standing  every failing line of the candidate's log fails at the accepted head too: the branch's
#   row       anything else: the red returns the row
#   waiting | replaced | gate   the run at the head could not be made now (as `_line_prove` says)
# THE RUN AT THE ACCEPTED HEAD is made once per head and suite, in the landing tree pointed at the head,
# and remembered by its own `verdict` event (`commit=<head>`): a second row on the same head reads it,
# a new head runs it once more. A run there with no verdict proves nothing, so the red stays the row's.
# The comparison is of FAILING LINES (`_line_fails`), never of exit codes or counts. When the row adds
# none, one `standing` event is appended for that head and suite, naming the head's failing lines.
# ITS CAUSE (wave-33 T2; REQ-7 AC-7.2): the event names its class and the run that disagrees with it
# (`_line_cause`), one event per head, suite and class. An environment-class standing red is a defect the
# landing reports, one `STANDING <row> <suite> cause=environment against=<run> log=<head's log>` line; the
# floor judge does not count it as the suite's state (lib/proof.sh `_proof_records`).
_line_red_owner() {  # <plan> <rec> <row> <cbase> <suite> <candidate's log> <debt> <deadline> <candidate>
  local plan="$1" rec="$2" row="$3" s="$5" head hr="" hl="" cause against jt
  if [ "${s##*/}" = "$7" ]; then LINE_RED=declared; return 0; fi
  LINE_RED=row
  # A LANDS-ON COMMAND'S RED IS THE ROW'S (wave-39 T20; D20): it is judged by its exit code alone, and its log has no
  # failing lines to hold against a run at the head, so no run is made there.
  ! bionic_lands_cmd "$s" >/dev/null || return 0
  head="$(line_head "$plan")" || return 0
  IFS=$'\t' read -r hr hl <<EOT
$(_line_head_verdict "$rec" "$head" "$s")
EOT
  if [ -z "$hr" ]; then
    # THE JUDGE'S TREE (wave-37 T1; D3): the run at the head never points the candidate's tree elsewhere,
    # where siblings of the drain may still run. It takes a tree of its own (`landing_tree_take` hands out
    # tree n+1), held until the carrier ends. Refused one, it lets every sibling end first and runs in the
    # candidate's tree, and the pass starts again, pointing that tree at the candidate (_LINE_REPASS).
    [ -n "$_LINE_JT" ] || _LINE_JT="$(landing_tree_take "$(_line_root "$plan")")" || _LINE_JT=""
    jt="$_LINE_JT"
    if [ -z "$jt" ]; then
      _line_drain_stop await "$plan" "$rec" "$row" "${9:-}" "$4"
      jt="$_LINE_LT"; _LINE_REPASS=1
    fi
    landing_tree_point "$jt" "$head" || { LINE_RED=gate; LINE_LOG="landing-tree-unpointable tree=${jt} base=${head}"; return 0; }
    # THE JUDGE ASKS TOO (wave-38 T6; D21): its run starts once the gate answers this landing one more.
    _line_room_one "$plan" "$rec" "$row" "$4" "$8" || { LINE_RED="$LINE_RESULT"; return 0; }
    _line_prove "$plan" "$rec" "$row" "$head" "$4" "$jt" "$s" "$8"
    _LINE_GRANT=0; _LINE_ASK=1   # the drain asks again: the judge's answer is spent
    case "$LINE_RESULT" in
      green|red|none) _line_verdict_put "$plan" "$row" "$head" "$s" "$LINE_RESULT" "$LINE_LOG" "$LINE_AT" "$LINE_PROMISED" "$LINE_ACTUAL" >/dev/null
        hr="$LINE_RESULT"; hl="$LINE_LOG" ;;
      discarded) _line_verdict_put "$plan" "$row" "$head" "$s" discarded "$LINE_LOG" "$LINE_AT" "$LINE_PROMISED" "$LINE_ACTUAL" >/dev/null
        LINE_RED=replaced; return 0 ;;
      *) LINE_RED="$LINE_RESULT"; return 0 ;;
    esac
  fi
  [ "$hr" = red ] || return 0
  if [ "$(_line_new_fails "$6" "$hl")" -eq 0 ]; then
    LINE_RED=standing
    cause="$(_line_cause "$plan" "$rec" "$head" "${9:-}" "$s")"; against="${cause#* }"; cause="${cause%% *}"
    awk -F'|' -v h="$head" -v s="$s" -v c="$cause" "$_LINE_FIELDS_AWK"'
      line_ev() == "standing" && line_kv("head") == h && line_kv("suite") == s && line_kv("cause") == c { f = 1 } END { exit !f }' "$rec" 2>/dev/null \
      || line_event "$plan" standing "head=${head}" "suite=${s}" "lines=$(_line_fails "$hl" | awk 'END { print NR }')" "log=${hl}" \
           "cause=${cause}" "against=${against}" >/dev/null
    [ "$cause" != environment ] || printf 'STANDING %s %s cause=environment against=%s log=%s\n' "$row" "$s" "$against" "$hl"
  fi
}
# THE CAUSE OF A STANDING RED (wave-33 T2; REQ-7 AC-7.2). A standing red is red on the candidate and at the
# accepted head alike. It is `environment` when a run of the same suite on the same code disagrees: a green
# record of <suite>, or a green whole run, at a commit whose tree is the head's or the candidate's, among the
# records the floor judge reads (lib/proof.sh `_proof_records`: the landing record's verdicts, booked.sh's
# stamps in every git dir of the repository). The newest such run is named `<stamp|verdict>:<commit>@<at>`.
# Otherwise it is `code`, and no run is named (`-`). Prints `<class> <run>`. THE SUITE IS ITS FILE NAME (wave-35
# T6; AC-5.2): `_proof_records` keys every record so, and a declared `tests/x.test.sh` is `x.test.sh` here. A
# RUN COUNTS ONLY WHERE IT RAN (AC-5.1): a stamp is a record only when the shim could place the run (booked.sh
# --unplaced leaves none), so the runs read here are runs at the tree each record's commit names.
_line_cause() {  # <plan> <rec> <head> <candidate | empty> <suite>
  local root th tc recs trees run=""
  root="$(_line_root "$1")" && _line_load_proof || { echo "code -"; return 0; }
  th="$(git -C "$root" rev-parse -q --verify "${3}^{tree}" 2>/dev/null)"
  tc=""; [ -z "$4" ] || tc="$(git -C "$root" rev-parse -q --verify "${4}^{tree}" 2>/dev/null)"
  recs="$(_proof_records "$root" "$2" | awk -F'\t' -v s="${5##*/}" '$1 == "R" && $5 == "green" && ($4 == s || $4 == "*") { print $3 "\t" $2 "\t" $6 }')"
  if [ -n "$recs" ]; then
    trees="$(printf '%s\n' "$recs" | cut -f1 | sed 's/$/^{tree}/' | git -C "$root" cat-file --batch-check='%(objectname)' 2>/dev/null)"
    run="$( { printf '%s\n' "$trees"; printf -- '--\n'; printf '%s\n' "$recs"; } | awk -F'\t' -v a="$th" -v b="$tc" '
      $0 == "--" && !s { s = 1; next }
      !s { t[++k] = $1; next }
      { i++; x = t[i]; if (x ~ /^[0-9a-f]+$/ && (x == a || x == b) && $2 >= best) { best = $2; r = $3 ":" $1 "@" $2 } }
      END { if (r != "") print r }')"
  fi
  if [ -n "$run" ]; then printf 'environment %s\n' "$run"; else echo "code -"; fi
}
_line_load_proof() {
  declare -F _proof_records >/dev/null 2>&1 && return 0
  # shellcheck source=/dev/null
  [ -r "$_LINE_LIB_DIR/proof.sh" ] && . "$_LINE_LIB_DIR/proof.sh" 2>/dev/null
  declare -F _proof_records >/dev/null 2>&1
}
# The remembered run of <suite> at <head>: `<green|red><TAB><log>` of its latest such verdict, or nothing.
_line_head_verdict() {  # <rec> <head> <suite>
  awk -F'|' -v c="$2" -v s="$3" "$_LINE_FIELDS_AWK"'
    line_ev() == "verdict" && line_kv("commit") == c && line_kv("suite") == s {
      r = line_kv("result"); if (r == "green" || r == "red") v = r "\t" line_kv("log") }
    END { if (v != "") print v }' "$1" 2>/dev/null
}
# A log's failing lines, as the suite harness prints them (tests/lib/assert.sh: `FAIL: <label>`), each
# normalised: the indent before `FAIL:`, a carriage return and trailing blanks dropped; one per line.
_line_fails() {  # <log>
  awk '{ sub(/\r$/, ""); sub(/^[ \t]+/, ""); if (index($0, "FAIL: ") != 1) next; sub(/[ \t]+$/, ""); print }' "$1" 2>/dev/null
}
# How many of the candidate's failing lines the head does not fail: the lines are counted, one for one,
# so a label the head fails once and the candidate twice has one line more.
_line_new_fails() {  # <candidate's log> <head's log>
  { _line_fails "$2" | sed 's/^/h /'; _line_fails "$1" | sed 's/^/c /'; } \
    | awk '{ k = substr($0, 3) } /^h / { h[k]++; next } { c[k]++; if (c[k] > h[k]) n++ } END { print n + 0 }'
}

# THE DECLARED DEBT (wave-27 T67; D8, AC-9.4): the entry's declared suite when its verdict on
# <candidate> is red. Read from the record: the `debt=` of the entry's latest `ready`. The debt names a
# suite by its file name, so a path-qualified suite is the debt by its file name (wave-34 T27).
_line_declared() {  # <rec> <row> <candidate> -> the suite; 1 when nothing is owed
  awk -F'|' -v r="$2" -v c="$3" "$_LINE_FIELDS_AWK"'
    { e = line_ev() } line_kv("row") != r { next }
    e == "published" || e == "returned" { d = "" }
    e == "ready" { d = line_kv("debt") }
    e == "verdict" && line_kv("commit") == c { v[line_kv("suite")] = line_kv("result") }
    END { if (d != "" && d != "-") for (s in v) { b = s; sub(/.*\//, "", b); if (b == d && v[s] == "red") { print d; exit 0 } }
          exit 1 }' "$1" 2>/dev/null
}
# THE DEBT'S WRITE, inside the publish lock, before the fast-forward: one `debt:` line by the debt's
# one writer (lib/worktree.sh `_wt_debt_write`), naming the row, its branch and head, the suite, the
# token the launch line declared (LINE_DEBT_TOKEN, `-` when none) and the publish's instant. Sets
# LINE_DEBT_ID and LINE_DEBT_SUITE (empty when nothing is owed); rc 1, refused, when it cannot be written.
_line_debt_write() {  # <rec> <row> <row commit> <candidate> <row branch> <at>
  local d
  LINE_DEBT_ID=""; LINE_DEBT_SUITE=""
  d="$(_line_declared "$1" "$2" "$4")" || return 0
  LINE_DEBT_SUITE="$d"; LINE_DEBT_ID="$$.${RANDOM}${RANDOM}"
  _wt_debt_write "$1" "$LINE_DEBT_ID" "$2" "$5" "$3" "$d" "${LINE_DEBT_TOKEN:--}" "$6" && return 0
  _wt_refuse "debt-unwritten why=proofs-unwritable suite=${d} path=${1} row=${2} — the declared red's debt cannot be written to the landing record (${_WT_PROOFS_SAW:-the append failed}), so nothing is published; make it writable, say ready again"
  LINE_DEBT_ID=""; return 1
}

# A suite's log, under the record directory: `line/<row>-<suite>-<candidate's 12 hex>[-<n>].log`.
_line_suite_log() {  # <rec> <row> <suite> <candidate> -> a path no run has written
  local d="${1%/*}/line" b p c n=1
  mkdir -p "$d" 2>/dev/null
  b="${3##*/}"
  ! c="$(bionic_lands_cmd "$3")" || b="cmd-$(printf '%s' "$c" | tr -c 'A-Za-z0-9._-' '_' | cut -c1-40)"   # wave-39 T20
  b="${d}/${2//\//-}-${b%.test.sh}-$(printf '%.12s' "$4")"
  p="${b}.log"
  while [ -e "$p" ]; do n=$((n + 1)); p="${b}-${n}.log"; done
  printf '%s' "$p"
}

# NEVER A SUITE PAST ITS TIME (D3): the suite's recorded duration (the last field of `_gate_promise`,
# the longest of its kept durations; wave-33 T1, Δ10) against the time left. Prints the seconds the
# gate may take to admit it, so that it starts with its promised seconds still left; rc 1 when they
# are not left now. Durations are keyed by project (`_gate_project`), so the lookup names the
# landing tree the suite runs in, not wherever the carrier stands.
_line_time_for() {  # <suite> <deadline> <landing tree> -> seconds
  local p s left
  _gate_store >/dev/null 2>&1 || return 0
  p="$(_gate_promise "$1" "${3:-}")"; s="${p##*:}"
  left=$(( $2 - $(_res_now) ))
  awk -v s="${s:-0}" -v l="$left" 'BEGIN { if (s + 0 > l + 0) exit 1; printf "%d\n", l - s }'
}

# The run's verdict (D8): `none` when it ended by a signal (128 + n), could not start (126, 127, or
# no rc at all), or its log holds no end line, the harness's `<file>: <p>/<t> passed, <f> failed`;
# otherwise green on rc 0 and red on any other. A LANDS-ON COMMAND (wave-39 T20; D20) prints no end line and is
# judged by its exit code alone: green on rc 0, red on any other; `none` only when it has no rc.
_line_verdict() {  # <rc> <log> [<lands_on entry>]
  case "${1:-}" in ''|*[!0-9]*) echo none; return 0 ;; esac
  if bionic_lands_cmd "${3:-}" >/dev/null; then if [ "$1" = 0 ]; then echo green; else echo red; fi; return 0; fi
  if [ "$1" -ge 126 ] || ! grep -Eq '^[^ ]+: [0-9]+/[0-9]+ passed, [0-9]+ failed( |$)' "$2" 2>/dev/null; then echo none
  elif [ "$1" = 0 ]; then echo green; else echo red; fi
}

# The entry's base by the fold is no longer <cbase>, or the entry is gone.
_line_replaced() {  # <rec> <plan> <row> <cbase>
  local b
  b="$(_line_entries "$1" "$(line_head "$2")" | awk -F'\t' -v r="$3" '$1 == r { print $5; f = 1; exit } END { if (!f) print "-closed-" }')"
  [ "$b" != "$4" ]
}

# TERM a process and every descendant of it, from one `ps` snapshot walked a generation at a time.
_line_kill_tree() {  # <pid>
  local table frontier next victims="$1" g=0 v
  table="$(ps -Ao pid=,ppid= 2>/dev/null)"; frontier=" $1 "
  while [ "$g" -lt 16 ]; do
    next="$(printf '%s\n' "$table" | awk -v p="$frontier" 'index(p, " " $2 " ") { printf " %s", $1 }')"
    [ -n "$next" ] || break
    victims="${victims}${next}"; frontier="${next} "; g=$((g + 1))
  done
  for v in $victims; do kill -TERM "$v" 2>/dev/null; done
}

# ONE SUITE ON THE CANDIDATE. The runner is a process of its own, so the gate's request is held by
# it: when the carrier stops a run whose base was replaced, the runner and its suite are killed, the
# gate counts the request killed and learns no cost from it. While a run lasts the carrier watches
# the fold. Sets LINE_RESULT (green | red | none | discarded | replaced | waiting | gate) and LINE_LOG.
# The drain (`_line_drain_next`) starts and ends its runners with the same three pieces; this one runs
# the red judge's suite at the head, alone.
_line_prove() {  # <plan> <rec> <row> <candidate> <cbase> <landing tree> <suite> <deadline>
  local rp res
  _line_prove_start "$2" "$3" "$4" "$6" "$7" "$8"
  [ -z "$LINE_RESULT" ] || return 0
  rp="$LINE_RP"; res="$LINE_RES"
  while kill -0 "$rp" 2>/dev/null; do
    if _line_replaced "$2" "$1" "$3" "$5"; then
      _line_prove_kill "$rp" "$res"; return 0
    fi
    sleep "$LINE_POLL"
  done
  wait "$rp" 2>/dev/null
  _line_prove_end "$res" "${7##*/}"
}
# ONE RUNNER STARTED on <tree> (wave-37 T1): sets LINE_LOG, LINE_RES (the runner's result file) and LINE_RP
# (its pid); LINE_RESULT=waiting, and nothing started, when the suite's promised seconds are not left
# (`_line_time_for`, D3), which is checked before each runner is asked.
_line_prove_start() {  # <rec> <row> <candidate> <tree> <suite> <deadline>
  local within=""
  LINE_RESULT=""; LINE_WHY=""; LINE_RP=""; LINE_RES=""; LINE_AT=-; LINE_PROMISED=-; LINE_ACTUAL=-
  LINE_LOG="$(_line_suite_log "$1" "$2" "$5" "$3")"
  if [ -n "$6" ]; then
    within="$(_line_time_for "$(_line_gate_key "$5")" "$6" "$4")" \
      || { LINE_RESULT=waiting; LINE_WHY="$(_line_time_why "$(_line_gate_key "$5")" "$6" "$4")"; return 0; }
  fi
  # THE LOG CLAIMED BEFORE THE RUNNER STARTS: a sibling started next (the same suite named twice, by path
  # and by name) is then given the next free path, never this one.
  : > "$LINE_LOG"; LINE_RES="${LINE_LOG%.log}.run"; : > "$LINE_RES"
  # A JOB OF ITS OWN (wave-33 T2; D3, AC-7.1): a plain `&` would start the runner, and so its suite,
  # with INT and QUIT ignored; the runner's own spawn of the suite is one too (`_line_runner`).
  bionic_job bash -c '. "$1/line.sh" && _line_load_gate && shift && _line_runner "$@"' _ \
    "$_LINE_LIB_DIR" "$5" "$within" "$4" "$LINE_LOG" "$LINE_RES" "${LINE_ME%%:*}" "${_LINE_KEY:-}" "$1"
  LINE_RP="$BIONIC_JOB_PID"
}
# An ended runner's result, LINE_LOG its log, <suite> its Lands-on entry as a file name: LINE_RESULT green | red | none
# by `_line_verdict`, or waiting |
# gate when the gate did not admit it (LINE_LOG then says why); LINE_AT its admission's epoch, `-` when it
# was not admitted. Its result file is removed.
_line_prove_end() {  # <result file> [<suite>]
  local r p
  LINE_AT="$(_line_run_at "$1")"
  LINE_PROMISED="$(_line_run_at "$1" promised)"; LINE_ACTUAL="$(_line_run_at "$1" actual)"
  r="$(sed -n 's/^gate=//p' "$1" 2>/dev/null)"
  if [ -n "$r" ]; then
    if [ "$r" = 75 ]; then
      LINE_RESULT=waiting; _gate_store >/dev/null 2>&1; p="$(_gate_promise "$(_line_gate_key "${2:-}")" 2>/dev/null)"
      LINE_WHY="gate did not admit ${2:-the suite} before its promised ${p##*:}s stopped fitting in --within ${_LINE_WITHIN:-}"
    else LINE_RESULT=gate; LINE_LOG="gate_ask rc ${r}"; fi
  elif grep -q '^unstarted=' "$1" 2>/dev/null; then
    LINE_RESULT=none   # nothing started (wave-39 T20): a command's rc 1 there is no exit code of its own
  else
    LINE_RESULT="$(_line_verdict "$(sed -n 's/^rc=//p' "$1" 2>/dev/null)" "$LINE_LOG" "${2:-}")"
  fi
  rm -f "$1"
}
# The admission epoch a runner filed in its result file (`at=`), `-` when it filed none; with <field>, that
# field instead (`promised`, `actual`: wave-39 T8).
_line_run_at() {  # <result file> [<field>]
  local t
  t="$(sed -n "s/^${2:-at}=//p" "$1" 2>/dev/null | head -1)"
  printf '%s\n' "${t:--}"
}
# THE RUN'S PROMISE AND ITS ACTUAL (wave-39 T8; D11, AC-4.2), read off the gate's request <id> by the runner:
# `promised` the seconds of its promise= (what the gate promised it at admission), `actual` its ended less
# admitted (the seconds gate_end records); `-` when the request does not say.
_line_req_seconds() {  # <request id> promised|actual
  local d t=""
  d="$(gate_dir 2>/dev/null)" && _gate_read "$d/requests/$1" 2>/dev/null || { echo -; return 0; }
  case "$2" in
    promised) t="${_R_promise##*:}"; [ -n "$_R_promise" ] || t="" ;;
    actual) case "$_R_admitted$_R_ended" in ''|*[!0-9]*) t="" ;; *) [ -n "$_R_admitted" ] && [ -n "$_R_ended" ] && t=$((_R_ended - _R_admitted)) ;; esac ;;
  esac
  case "$t" in ''|*[!0-9]*) t=- ;; esac
  printf '%s\n' "$t"
}
# The gate's admission instant for request <id> (its admitted= line), read in the runner right after
# admission; the clock's reading when the request cannot be read.
_line_admitted_at() {  # <request id>
  local d t=""
  d="$(gate_dir 2>/dev/null)" && _gate_read "$d/requests/$1" 2>/dev/null && t="$_R_admitted"
  case "$t" in ''|*[!0-9]*) t="$(_res_now)" ;; esac
  printf '%s\n' "$t"
}
# A runner stopped with its suite: LINE_RESULT discarded when the gate had admitted it (a run begun and
# thrown away), replaced when it had not. Its result file is removed.
_line_prove_kill() {  # <pid> <result file>
  _line_kill_tree "$1"; wait "$1" 2>/dev/null
  LINE_AT="$(_line_run_at "$2")"
  LINE_PROMISED="$(_line_run_at "$2" promised)"; LINE_ACTUAL=-   # a run stopped is no measure of the suite
  if grep -q '^admitted=' "$2" 2>/dev/null; then LINE_RESULT=discarded; else LINE_RESULT=replaced; fi
  rm -f "$2"
}

# ---------------------------------------------------------------------------- the drain (wave-37 T1; D3)
# THE LANDING'S KEY (wave-38 T6; D21, D22): the word every runner of this landing asks the gate under
# (BIONIC_GATE_LANDING) and the drain asks its width for: `<project>:<plan>:<row>`, the gate's project key of
# the root, the plan's slug (lib/proof.sh `proof_plan_slug`, the one place a plan's name is stripped), and the
# row. Stable for one row's landing, distinct between rows and plans; written in the landing key's alphabet
# (`landing_key`, below).
_line_landing_key() {  # <root> <plan> <row>
  local p w
  _line_load_gate && _line_load_proof || return 0
  p="$(_gate_project "$1")"; w="$(proof_plan_slug "$2")"
  landing_key "$p:$w:$3"
}
# THE LANDING KEY'S ALPHABET (wave-39 T17; D18, AC-12.1; burns debt landing-key-alphabet): A-Z a-z 0-9 . _ : / + -,
# at most 128. It stood three times, in this key's `tr`, in lib/gate.sh's validator (a bash pattern) and in its
# finished-row read (an awk gsub); tr and awk read a multibyte character as one under a UTF-8 locale and as its bytes
# under C, so a row keyed under one and finished under the other never matched. One function now, BYTE-WISE UNDER
# EVERY LOCALE: a byte outside the alphabet is written `_` (é is `__`), then the key is cut to 128. The alphabet is
# spelled letter by letter, so no locale's collation can widen a range. Pure bash, so the gate's scan forks nothing.
#   landing_key <text> [<var>]   the text as a landing key; set into <var> when one is named, else printed
#   landing_key_ok <key>         rc 0 when <key> is one: not empty, and landing_key leaves it as it is
# lib/gate.sh `_gate_landing_ok` is landing_key_ok, and its finished-row read writes each record's row= through
# landing_key; tests/gate.test.sh §KEY holds the three to one answer on a multibyte row across locales.
LANDING_KEY_ALPHABET='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._:/+-'
landing_key() {  # <text> [<var>]
  local LC_ALL=C _lk_s="${1:-}"
  _lk_s="${_lk_s//[!$LANDING_KEY_ALPHABET]/_}"
  _lk_s="${_lk_s:0:128}"
  if [ -n "${2:-}" ]; then printf -v "$2" '%s' "$_lk_s"; else printf '%s\n' "$_lk_s"; fi
}
landing_key_ok() {  # <key>
  local _lk_k
  [ -n "${1:-}" ] || return 1
  landing_key "$1" _lk_k
  [ "$_lk_k" = "$1" ]
}
# THE DRAIN'S WIDTH (wave-38 T6; D21, AC-6.1; ADR-060): how many more runners this landing may start now,
# the gate's own answer (gate.sh `gate_width_ask`), never a number the drain works out. The one door the
# drain and the red judge ask through. rc 1: not answered now (the gate's lock), ask again; rc 2: the gate
# cannot answer.
_line_width_ask() {  # <landing key> -> a whole number
  local n rc
  _line_load_gate || return 2
  n="$(gate_width_ask "$1" 2>/dev/null)"; rc=$?
  [ "$rc" -eq 0 ] || { [ "$rc" -eq 1 ] && return 1; return 2; }
  case "$n" in ''|*[!0-9]*) return 2 ;; esac
  printf '%s\n' "$n"
}
# THE ASK (wave-38 T6): once every runner the pass started has its admission or has ended, so the gate's
# store holds each of them (a runner started and not yet asking is not in it, T5-gate.md), the gate is asked
# how many more this landing may start. Sets _LINE_GRANT, that answer, and LINE_WIDTH, the width the landing
# then holds: its runners live plus the answer. rc 1: not asked now (a runner of ours still asking, or the
# gate's lock); rc 2: the gate cannot answer.
_line_ask() {
  local n rc live
  _line_drain_asking && return 1
  n="$(_line_width_ask "${_LINE_KEY:-}")"; rc=$?
  [ "$rc" -eq 0 ] || return "$rc"
  live="$(_line_drain_live)"
  _LINE_GRANT="$n"; _LINE_LIVE="$live"; LINE_WIDTH=$((live + n))
}
# ONE MORE RUN, FOR THE RED JUDGE: asks until the gate answers this landing at least 1. Else LINE_RESULT is
# waiting (out of time), replaced (the entry's base moved) or gate (no answer to be had), and rc 1.
_line_room_one() {  # <plan> <rec> <row> <cbase> <deadline>
  local rc
  while :; do
    _line_ask; rc=$?
    [ "$rc" -ne 0 ] || [ "$_LINE_GRANT" -lt 1 ] || return 0
    [ "$rc" -le 1 ] || { LINE_RESULT=gate; LINE_LOG="gate_width_ask rc ${rc}"; return 1; }
    _line_late "$5" && { LINE_RESULT=waiting; LINE_WHY="$(_line_width_why)"; return 1; }
    _line_replaced "$2" "$1" "$3" "$4" && { LINE_RESULT=replaced; return 1; }
    sleep "$LINE_POLL"
  done
}
# THE VERDICT LINE, the one writer of every verdict a landing writes (on the candidate and at the head):
# `line/v1|ev=verdict|row=|commit=|suite=|result=|log=|admitted=<epoch|->|width=<J>|promised=|actual=|at=`. Every reader
# reads it by name (`_LINE_FIELDS_AWK`); a field added to it may go anywhere after `ev=`. admitted= is the gate's admission instant for the run
# the verdict judges (wave-38 T6; AC-6.4), `-` when none is on record; width= the width the gate gave the
# landing when that run started (`_line_ask`), `-` for a verdict no answer of the gate's stands behind (absent).
# promised= and actual= go after width=: the seconds the gate promised the run at its
# admission (its request's promise=) and the gate's own measure of it (ended less admitted), `-` for a run never
# admitted, a run stopped before it ended, and a verdict no run wrote (absent).
_line_verdict_put() {  # <plan> <row> <commit> <suite> <result> <log> [<admitted epoch>] [<promised s>] [<actual s>]
  line_event "$1" verdict "row=$2" "commit=$3" "suite=$4" "result=$5" "log=$6" "admitted=${7:--}" "width=${LINE_WIDTH:--}" \
    "promised=${8:--}" "actual=${9:--}"
}
# THE PASS'S SUITES, in the order named. For each: its suite (_LINE_DS), its runner's pid (_LINE_DP: empty
# until started, `-` for a red judged from its log), result file (_LINE_DR), log (_LINE_DL) and the width it
# started under (_LINE_DW). _LINE_DK is the next to start, _LINE_DH the next to take, _LINE_DN how many
# (bash 3.2: indexed arrays only). _LINE_ASK says the gate is to be asked before the next start, _LINE_GRANT
# how many more its last answer allows, _LINE_LIVE how many of ours run since then if none has ended.
_line_drain_init() {
  _LINE_DS=(); _LINE_DP=(); _LINE_DR=(); _LINE_DL=(); _LINE_DW=(); _LINE_DH=0; _LINE_DK=0; _LINE_DN=0
  _LINE_ASK=1; _LINE_GRANT=0; _LINE_LIVE=0
  LINE_SUITE=""   # a pass whose base is replaced before it takes a suite reads it (wave-38 T30): set, never unbound
}
_line_drain_add() {  # <suite>
  _LINE_DS[$_LINE_DN]="$1"; _LINE_DP[$_LINE_DN]=""; _LINE_DR[$_LINE_DN]=""; _LINE_DL[$_LINE_DN]=""; _LINE_DW[$_LINE_DN]=-
  _LINE_DN=$((_LINE_DN + 1))
}
_line_drain_ended() {  # <i> -> 0 once that runner has ended: its result written, or its process gone
  grep -qE '^(rc|gate)=' "${_LINE_DR[$1]}" 2>/dev/null && return 0
  ! kill -0 "${_LINE_DP[$1]}" 2>/dev/null
}
_line_drain_live() {  # -> how many of the pass's runners have started and not ended
  local i="$_LINE_DH" n=0
  while [ "$i" -lt "$_LINE_DK" ]; do
    case "${_LINE_DP[$i]}" in ''|-) ;; *) _line_drain_ended "$i" || n=$((n + 1)) ;; esac
    i=$((i + 1))
  done
  printf '%s' "$n"
}
_line_drain_asking() {  # -> 0 while a runner the pass started has neither its admission line nor ended
  local i="$_LINE_DH"
  while [ "$i" -lt "$_LINE_DK" ]; do
    case "${_LINE_DP[$i]}" in
      ''|-) ;;
      *) grep -q '^admitted=' "${_LINE_DR[$i]}" 2>/dev/null || _line_drain_ended "$i" || return 0 ;;
    esac
    i=$((i + 1))
  done
  return 1
}
# THE NEXT RESULT: asks the gate (`_line_ask`) before the pass's first runner, again as each one ends, and
# again after a poll while its answer is 0; starts exactly as many as it answers; then gives the first suite
# named whose run has ended. Sets LINE_SUITE, LINE_RESULT and LINE_LOG as `_line_prove` does (judge for a
# red already on the candidate; waiting, nothing started, for a suite whose time is not left, or when the
# time runs out while the gate answers 0 and nothing runs); replaced, when the entry's base moves while its
# runners run or wait (the watch covers every one of them); gate, when the gate cannot answer. rc 1 once all
# are taken.
_line_drain_next() {  # <plan> <rec> <row> <candidate> <cbase> <landing tree> <deadline>
  local i p rc live
  while :; do
    if [ "$_LINE_DK" -lt "$_LINE_DN" ] && [ -n "$_LINE_ASK" ]; then
      _line_ask; rc=$?
      case $rc in
        0) _LINE_ASK=""; [ "$_LINE_GRANT" -gt 0 ] || _LINE_ASK=1 ;;
        1) : ;;
        *) LINE_SUITE="${_LINE_DS[$_LINE_DK]}"; LINE_RESULT=gate; LINE_LOG="gate_width_ask rc ${rc}"; return 0 ;;
      esac
    fi
    while [ "$_LINE_DK" -lt "$_LINE_DN" ]; do
      i="$_LINE_DK"
      _LINE_DL[$i]="$(_line_red_log "$2" "$3" "$4" "${_LINE_DS[$i]}")"
      if [ -n "${_LINE_DL[$i]}" ]; then _LINE_DP[$i]=-; _LINE_DK=$((i + 1)); continue; fi
      [ "$_LINE_GRANT" -gt 0 ] || break
      _LINE_DK=$((i + 1))
      _line_prove_start "$2" "$3" "$4" "$6" "${_LINE_DS[$i]}" "$7"
      if [ "$LINE_RESULT" = waiting ]; then LINE_SUITE="${_LINE_DS[$i]}"; return 0; fi
      _LINE_DP[$i]="$LINE_RP"; _LINE_DR[$i]="$LINE_RES"; _LINE_DL[$i]="$LINE_LOG"; _LINE_DW[$i]="$LINE_WIDTH"
      _LINE_GRANT=$((_LINE_GRANT - 1)); _LINE_LIVE=$((_LINE_LIVE + 1))
    done
    if [ "$_LINE_DH" -ge "$_LINE_DK" ]; then
      [ "$_LINE_DK" -lt "$_LINE_DN" ] || return 1
      # NOTHING RUNS AND THE GATE GAVE NOTHING (an older landing holds it): wait a poll and ask again.
      if _line_late "$7"; then LINE_SUITE="${_LINE_DS[$_LINE_DK]}"; LINE_RESULT=waiting; LINE_WHY="$(_line_width_why)"; return 0; fi
      if _line_replaced "$2" "$1" "$3" "$5"; then LINE_RESULT=replaced; return 0; fi
      sleep "$LINE_POLL"; continue
    fi
    i="$_LINE_DH"; p="${_LINE_DP[$i]}"
    LINE_SUITE="${_LINE_DS[$i]}"; LINE_LOG="${_LINE_DL[$i]}"
    if [ "$p" = - ]; then _LINE_DH=$((i + 1)); LINE_RESULT=judge; return 0; fi
    if _line_drain_ended "$i"; then
      wait "$p" 2>/dev/null; _LINE_DH=$((i + 1)); _LINE_ASK=1; LINE_WIDTH="${_LINE_DW[$i]}"
      _line_prove_end "${_LINE_DR[$i]}" "${LINE_SUITE##*/}"; return 0
    fi
    # A RUN ENDED OUT OF ORDER frees its width too: ask again before the next start.
    live="$(_line_drain_live)"
    [ "$_LINE_DK" -ge "$_LINE_DN" ] || [ "$live" -ge "$_LINE_LIVE" ] || _LINE_ASK=1
    if _line_replaced "$2" "$1" "$3" "$5"; then LINE_RESULT=replaced; return 0; fi
    sleep "$LINE_POLL"
  done
}
# THE DRAIN STOPPED: nothing more is asked. `await` lets each runner started and not yet taken end, and
# writes its verdict, in the order named; `kill` does the same for a runner already ended and stops every
# other with its suite, a run the gate had begun written `discarded`, as a replaced base's run always was.
# An await whose base moves under it kills what is left. The next pass reads the record again: a red
# written here is judged from its log, a none is asked again or stalls the entry.
_line_drain_stop() {  # kill|await <plan> <rec> <row> <candidate> <cbase>
  local how="$1" i p
  i="$_LINE_DH"
  while [ "$i" -lt "$_LINE_DK" ]; do
    p="${_LINE_DP[$i]}"
    case "$p" in ''|-) i=$((i + 1)); continue ;; esac
    while [ "$how" = await ] && ! _line_drain_ended "$i"; do
      if _line_replaced "$3" "$2" "$4" "$6"; then how=kill; break; fi
      sleep "$LINE_POLL"
    done
    LINE_LOG="${_LINE_DL[$i]}"; LINE_WIDTH="${_LINE_DW[$i]}"
    if _line_drain_ended "$i"; then
      wait "$p" 2>/dev/null; _line_prove_end "${_LINE_DR[$i]}" "${_LINE_DS[$i]##*/}"
    else
      _line_prove_kill "$p" "${_LINE_DR[$i]}"
    fi
    case "$LINE_RESULT" in
      green|red|none|discarded) _line_verdict_put "$2" "$4" "$5" "${_LINE_DS[$i]}" "$LINE_RESULT" "$LINE_LOG" "$LINE_AT" "$LINE_PROMISED" "$LINE_ACTUAL" >/dev/null ;;
    esac
    i=$((i + 1))
  done
  _LINE_DH="$_LINE_DN"; _LINE_DK="$_LINE_DN"
}
# WHERE A SUITE LIVES (wave-34 T7; D23, AC-14.4). A path-qualified suite is run at exactly the path declared
# (wave-34 T27; critic S2): never a same-named file elsewhere, and a path the tree lacks cannot start, so it
# stalls the entry. A bare name is found in the landing tree: `tests/<name>` when it is there, as before;
# otherwise the one tracked file of that name, wherever the project keeps its suites
# (`scripts/deploy/__tests__/x.test.sh`). None, or two or more and none under `tests/`, is the old
# `tests/<name>`: ready picks no suite for the writer, and the suite that cannot start stalls the entry.
_line_suite_path() {  # <landing tree> <suite as lands_on= holds it> -> the suite's path in that tree
  local tree="$1" name="$2" f hit="" n=0
  case "$name" in */*) printf '%s\n' "$name"; return 0 ;; esac
  if [ ! -e "$tree/tests/$name" ]; then
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      hit="$f"; n=$((n + 1))
    done <<LINE_LS
$(git -C "$tree" ls-files -- "$name" "*/$name" 2>/dev/null)
LINE_LS
    [ "$n" -ne 1 ] || { printf '%s\n' "$hit"; return 0; }
  fi
  printf 'tests/%s\n' "$name"
}
# A SUITE THE ROW REMOVED (wave-39 T6; A-orch-5): 0 when <base> holds the suite and <candidate> does not, each
# read as git holds it with the lookup above: a path-qualified name at its path; a bare one at `tests/<name>` or
# as any tracked file of that name. 1 otherwise: a suite neither holds (a name no tree has, the case that stalls,
# wave-34 T27) is not the row's removal, and neither is a commit that is not one here.
_line_removed() {  # <root> <base> <candidate> <suite as lands_on= holds it>
  _line_holds "$1" "${2:-}" "${4:-}" && ! _line_holds "$1" "${3:-}" "${4:-}" \
    && git -C "$1" cat-file -e "${3:-}^{commit}" 2>/dev/null
}
_line_holds() {  # <root> <commit> <suite> -> 0 when <commit> is a commit holding the suite
  local root="$1" c="${2:-}" name="${3:-}"
  { [ -n "$c" ] && [ -n "$name" ] && git -C "$root" cat-file -e "${c}^{commit}" 2>/dev/null; } || return 1
  case "$name" in */*) git -C "$root" cat-file -e "${c}:${name}" 2>/dev/null; return ;; esac
  git -C "$root" cat-file -e "${c}:tests/${name}" 2>/dev/null && return 0
  git -C "$root" ls-tree -r --name-only "$c" 2>/dev/null | awk -F/ -v n="$name" '$NF == n { f = 1 } END { exit !f }'
}
# The runner's body, in its own `bash -c`: ask, run, sample the gate while the suite runs (a locked
# read raises the run's peak), end the request with the suite's code. It stops its suite if the
# carrier is gone.
# Its ask names the landing it belongs to (BIONIC_GATE_LANDING, wave-38 T6) and the landing record
# (BIONIC_GATE_RECORD, wave-38 T31: the gate ends a handed-back request once that record shows the row
# finished), and once admitted it files
# the gate's own admission instant for the run (`at=`), which the verdict carries as admitted= (AC-6.4).
_line_runner() {  # <suite> <within | empty> <landing tree> <log> <result file> <carrier pid> [<landing key>] [<record>]
  local id rc p c
  id="$(BIONIC_GATE_LANDING="${7:-}" BIONIC_GATE_RECORD="${8:-}" gate_ask landing "$(_line_gate_key "$1")" ${2:+--within "$2"})"; rc=$?
  [ "$rc" -eq 0 ] || { printf 'gate=%s\n' "$rc" > "$5"; return 0; }
  printf 'admitted=%s\nat=%s\npromised=%s\n' "$id" "$(_line_admitted_at "$id")" "$(_line_req_seconds "$id" promised)" > "$5"
  # From the start of the suite to its end, this shell's stderr is closed to the carrier: a suite ended
  # by a signal is a `none` verdict, and the shell's notice of the kill is no line of ready's output.
  # The suite starts through the plugin's primitive (lib/suite.sh; wave-33 T2, D3): a job of its own, so
  # its INT and QUIT are the runner's defaults; the gate's store unset in it; this admission its
  # BIONIC_GATE_ADMIT; stdin /dev/null. A tree that is no checkout runs nothing: rc 1, no end line.
  # A LANDS-ON COMMAND (wave-39 T20; D20) starts as `bash -c <command>` in the same environment (suite.sh
  # `bionic_command_start`). A run that could not start says so (`unstarted=`), so its rc 1 is no command's exit code.
  {
    p=""
    if [ -e "$3/.git" ]; then
      if c="$(bionic_lands_cmd "$1")"; then
        bionic_command_start ${id:+--admit "$id"} "$3" "$c" > "$4" 2>&1 && p="$BIONIC_SUITE_PID"
      else
        bionic_suite_start ${id:+--admit "$id"} "$3" "$(_line_suite_path "$3" "$1")" > "$4" 2>&1 && p="$BIONIC_SUITE_PID"
      fi
    fi
    [ -n "$p" ] || { printf 'unstarted=1\n' >> "$5"; ( exit 1 ) & p=$!; }
    while kill -0 "$p" 2>/dev/null; do
      kill -0 "$6" 2>/dev/null || { _line_kill_tree "$p"; return 0; }
      sleep "$LINE_POLL"; gate_state >/dev/null 2>&1
    done
    wait "$p"; rc=$?
    gate_end "$id" "$rc" >/dev/null 2>&1
  } 2>/dev/null
  # actual= before rc=: a reader that sees rc= (the run ended) sees its actual too.
  printf 'actual=%s\nrc=%s\n' "$(_line_req_seconds "$id" actual)" "$rc" >> "$5"
}
