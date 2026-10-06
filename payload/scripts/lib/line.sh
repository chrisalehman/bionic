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
#   line_land_by_hand <tree> <root> <sid> <why>  `spawn-worktree.sh land <tree> --by-hand`
#   line_ready <tree> <root> <sid> <within> <again>  `spawn-worktree.sh ready [--within <s>]` (T4)
#
# THE RECORD. One append per line, by the landing record's one write (`_wt_proofs_put`: a private
# file copied by one write(2), no lock), so two writers' lines never interleave. Seven events:
#   ready     row name commit branch tree suites debt carrier   (a carrier is `<pid>:<start>`)
#   candidate row base commit tree
#   verdict   row commit suite result log      (green | red | none | discarded)
#   standing  head suite lines log
#   returned  row why detail                   (red | conflict | guard)
#   stalled   row logs
#   published row commit kind by why           (queue | hand | git)
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
# its candidate), waiting (no candidate), green (every suite green on the candidate, or `none`),
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

# What the caller of `line_publish` says it is: the queue's carrier (`ready`) by default; the hand
# landing sets kind=hand, the git user, the reason and the session its plan write runs under.
LINE_KIND="queue"; LINE_BY="-"; LINE_WHY="-"; LINE_SID=""

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
  declare -F plan_frontmatter_get >/dev/null 2>&1 && return 0
  # shellcheck source=/dev/null
  [ -r "$_LINE_LIB_DIR/run.sh" ] && . "$_LINE_LIB_DIR/run.sh" 2>/dev/null
  declare -F plan_frontmatter_get >/dev/null 2>&1
}
_line_branch() {  # <plan> -> its working-branch
  _line_load_run || return 1
  plan_frontmatter_get "$1" working-branch
}
line_head() {  # <plan> -> the accepted head
  local root b
  root="$(_line_root "${1:-}")" && b="$(_line_branch "$1")" && [ -n "$b" ] || return 1
  git -C "$root" rev-parse --verify -q "refs/heads/${b}"
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
#   row name commit carrier candidate cbase cat outcome suites branch tree
_line_fold() {  # <record>
  [ -f "$1" ] || return 0
  awk -F'|' '
    function fv(k,   i) { for (i = 3; i <= NF; i++) if (index($i, k "=") == 1) return substr($i, length(k) + 2); return "" }
    substr($0, 1, 8) != "line/v1|" { next }
    {
      ev = substr($2, 4); row = fv("row")
      if (ev == "ready") {
        e = cur[row]
        if (e == "" || !open[e]) { e = ++n; cur[row] = e; open[e] = 1; rowof[e] = row; cand[e] = ""; stl[e] = 0 }
        name[e] = fv("name"); com[e] = fv("commit"); car[e] = fv("carrier"); sui[e] = fv("suites")
        debt[e] = fv("debt"); br[e] = fv("branch"); tr[e] = fv("tree")
      } else if (ev == "candidate") {
        e = cur[row]; if (e == "" || !open[e]) next
        cand[e] = fv("commit"); cbase[e] = fv("base"); cat[e] = fv("at"); stl[e] = 0
      } else if (ev == "verdict") {
        e = cur[row]; if (e == "" || !open[e]) next
        v[e, fv("commit"), fv("suite")] = fv("result")
      } else if (ev == "stalled") {
        e = cur[row]; if (e != "" && open[e]) stl[e] = 1
      } else if (ev == "published" || ev == "returned") {
        e = cur[row]; if (e != "" && open[e]) open[e] = 0
      } else if (ev == "standing") {
        stand[fv("head"), fv("suite")] = 1
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
              if (r == "green") continue
              if (r == "red") {
                if (names[j] == debt[e]) dec = 1
                else if ((cbase[e], names[j]) in stand) std = 1
                else unx = 1
              } else miss = 1
            }
          }
          if (miss || unx) out = "proving"; else if (std) out = "standing"; else if (dec) out = "declared"; else out = "green"
        }
        printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", rowof[e], name[e], com[e], car[e], \
          (c == "" ? "-" : c), (cbase[e] == "" ? "-" : cbase[e]), (cat[e] == "" ? "-" : cat[e]), out, \
          (sui[e] == "" ? "none" : sui[e]), br[e], tr[e]
      }
    }' "$1" 2>/dev/null
}

# The fold with presence and the base rule applied: the interface's eight fields, then the raw
# fields line_publish needs (carrier, the candidate's own base and time, branch, tree).
_line_entries() {  # <record> <accepted head>
  local rec="$1" head="$2" row name com car cand cbase cat out sui br tr present base prev="$2"
  while IFS=$'\t' read -r row name com car cand cbase cat out sui br tr; do
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
  named="$(awk -F'|' '$2 == "ev=published" { for (i = 3; i <= NF; i++) if (index($i, "commit=") == 1) print substr($i, 8) }' "$rec" 2>/dev/null)"
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
    awk -F'|' -v r="row=${row}" '$2 == "ev=published" && $3 == r { f = 1 } END { exit !f }' "$rec" 2>/dev/null && continue
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

# THE HAND LANDING'S ROW TEXT (AC-5.1): the row's `- T<n>:` line gains `landed-by-hand: <user>
# <ISO-UTC> "<why>"`, written through the plan's one transaction (`session-poker.sh step-line`, as
# a command: the plan verbs live in the hook script). A row that is no plan row has no line.
_line_hand_text() {  # <plan> <row> <by> <at> <why> -> 0 written or nothing to write
  local plan="$1" row="$2" rest text poker root
  case "$row" in T[0-9]*) : ;; *) return 0 ;; esac
  rest="$(awk -v k="$row" '
    /^##[ \t]/ { s = ($0 ~ /^##[ \t]+SDLC State/); next }
    s && match($0, "^[ \t]*-?[ \t]*" k "[ \t]*:") { r = substr($0, RLENGTH + 1); sub(/^[ \t]+/, "", r); sub(/[ \t]+$/, "", r); print r; exit }' "$plan" 2>/dev/null)"
  text="landed-by-hand: ${3} ${4} \"${5}\""
  [ -z "$rest" ] || text="${rest} ${text}"
  poker="$(plugin_root 2>/dev/null)/hooks/session-poker.sh"
  root="$(_line_root "$plan")" || return 1
  ( cd "$root" && CLAUDE_CODE_SESSION_ID="${LINE_SID}" bash "$poker" step-line "$row" "$text" ) >/dev/null 2>&1
}

line_publish() {  # <plan> <row> -> 0 published · 3 rebuild · 4 held · 5 moved · 6 guard · 2 refused · 75 lock
  local plan="${1:-}" row="${2:-}" rec root lk head branch ent first=""
  local name com present base cand out sui car cbase cat br tr co rc run moved at rundir lt
  rec="$(line_record "$plan")" && root="$(_line_root "$plan")" && branch="$(_line_branch "$plan")" \
    || { _wt_refuse "line-unreadable plan=${plan:-<none>}"; return 2; }
  lk="$(_line_lock_dir "$rec")"
  mkdir -p "${rec%/*}" 2>/dev/null
  _line_lock_take "$lk" "$row" || return $?
  head="$(line_head "$plan")"
  ent="$(_line_entries "$rec" "$head")"
  first="$(printf '%s\n' "$ent" | awk -F'\t' '$4 == "yes" { print $1; exit }')"
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
  # 5. THE PROJECT'S RELEASE CHECK, READ FROM THE ACCEPTED HEAD: in the checkout that holds the
  # branch, or in a landing tree pointed at the accepted head when none does (recheck Q3, O3).
  rundir="$co"; lt=""
  if [ -z "$rundir" ] && [ -n "$(config_value "$root" release-check "" 2>/dev/null)" ]; then
    lt="$(landing_tree_take "$root")" && landing_tree_point "$lt" "$head" && rundir="$lt"
  fi
  _wt_release_check "$root" "${rundir:-$root}" "$head" "$cand" "$tr" "$br" "$branch"; rc=$?
  [ -z "$lt" ] || landing_tree_free "$lt"
  [ "$rc" -eq 0 ] || { _line_lock_drop "$lk"; return 2; }
  # 6. THE DEBT WRITE — T5's seam: a declared red's `debt:` line, written before the fast-forward.
  # 7. THE FAST-FORWARD, after the pause seam.
  _line_pause "$row"
  if [ -n "$co" ]; then
    GIT_REFLOG_ACTION="line: publish ${row}" git -C "$co" merge --ff-only -q "$cand" >/dev/null 2>&1; rc=$?
  else
    git -C "$root" update-ref -m "line: publish ${row}" "refs/heads/${branch}" "$cand" "$head" >/dev/null 2>&1; rc=$?
  fi
  if [ "$rc" -ne 0 ]; then
    _line_lock_drop "$lk"
    _wt_refuse "publish-failed row=${row} branch=${branch} candidate=${cand} checkout=${co:-<none>} — the fast-forward did not go through and nothing is published; say ready again"
    return 2
  fi
  # 8. THE `published` EVENT, one instant for the record and the row.
  at="$(_line_now)"
  _wt_proofs_put "$rec" "line/v1|ev=published|row=${row}|commit=${cand}|kind=${LINE_KIND}|by=${LINE_BY}|why=${LINE_WHY}|at=${at}"
  _wt_proofs_append "$rec" "$row" "$br" "$com" "$cand" "" "$at"
  # 9. THE PLAN WRITE — T6's seam: the row's status, its `- T<n>:` line and its ledger line, through
  # the one transaction. The hand landing's text is written here now.
  [ "$LINE_KIND" != hand ] || _line_hand_text "$plan" "$row" "$LINE_BY" "$at" "$LINE_WHY" \
    || printf 'NOTE %s — published; the row line was not written (session-poker.sh step-line refused)\n' "$row"
  # 10. THE ROSTER MARK — T6's seam: `landed=<40-hex> landed_at=<ISO-UTC>` on the row's roster line.
  _line_lock_drop "$lk"
  LINE_PUBLISHED="$cand"; LINE_CHECKOUT="$co"
  return 0
}

# ---------------------------------------------------------------------------- the hand landing
# `spawn-worktree.sh land <tree> --by-hand --reason '<why>'` (D9, AC-5.1): the person's landing.
# The tree is judged as land judged it (lib/worktree.sh `_wt_land_checks`) and by the `.bionic` guard
# on the accepted head and the row's head, before anything is written; then the row enters the line,
# its candidate is built on the base rule's base, nothing runs, and it publishes through
# `line_publish`, the queue's one publish and lock. Its carrier is this call, in a subshell of its
# own: when it ends, published or not, its entry holds nothing.
line_land_by_hand() {  # <tree> <root> <sid> <why> -> LANDED | REFUSED
  local target="${1:-}" root="${2:-}" sid="${3:-}" why="${4:-}" onto plan
  [ -n "$why" ] || { _wt_refuse "no-reason path=${target:-<none>} — a hand landing says why: land <tree> --by-hand --reason '<why>'"; return 2; }
  case "$why" in *'|'*|*$'\n'*|*$'\r'*) _wt_refuse "reason-unwritable path=${target:-<none>} — the reason holds a | or a line break; say it on one line without |"; return 2 ;; esac
  [ -n "$sid" ] || { _wt_refuse "no-session path=${target:-<none>}"; return 2; }
  _line_load_run || { _wt_refuse "run-library-unloadable path=${_LINE_LIB_DIR}/run.sh"; return 2; }
  onto="$(session_working_branch "$root" "$sid")" || { _wt_refuse "${onto:-no-bound-plan}"; return 2; }
  plan="$(session_plan "$root" "$sid")" || { _wt_refuse "no-bound-plan sid=${sid}"; return 2; }
  ( _line_hand "$target" "$onto" "$plan" "$sid" "$why" )
}
_line_hand() {  # <tree> <onto> <plan> <sid> <why> — the carrier's own subshell
  local target="$1" onto="$2" plan="$3" sid="$4" why="$5" wt root branch head acc rec row by c lt rc i n
  _wt_land_checks "$target" "$onto" "$plan" 0 || return 2
  wt="$_WT_ABS"; root="$_WT_ROOT"; branch="$_WT_BRANCH"
  head="$(git -C "$wt" rev-parse --verify -q HEAD 2>/dev/null)"
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
  _line_me
  line_event "$plan" ready "row=${row}" "name=-" "commit=${head}" "branch=${branch}" "tree=${wt}" suites=none debt=- \
    "carrier=${LINE_ME}" >/dev/null || { _wt_refuse "record-unwritable why=proofs-unwritable path=${rec} branch=${branch}"; return 2; }
  LINE_KIND=hand; LINE_BY="$by"; LINE_WHY="$why"; LINE_SID="$sid"
  n="${BIONIC_LINE_HAND_WAIT:-900}"; case "$n" in ''|*[!0-9]*) n=900 ;; esac
  lt=""; i=0; rc=3
  while [ "$rc" = 3 ]; do
    local base
    base="$(_line_entries "$rec" "$(line_head "$plan")" | awk -F'\t' -v r="$row" '$1 == r { print $5; exit }')"
    if [ -z "$base" ]; then
      # Counted already: a person's own git merge carried it.
      _wt_refuse "not-in-line branch=${branch} — the row left the line before its publish (git log ${onto})"; rc=2; break
    fi
    if [ "$base" != - ]; then
      [ -n "$lt" ] || lt="$(landing_tree_take "$root")" || { _wt_refuse "landing-tree-unavailable root=${root}"; rc=2; break; }
      if ! c="$(line_build "$lt" "$base" "$head" "$branch")"; then
        line_event "$plan" returned "row=${row}" why=conflict "detail=${c:-?}" >/dev/null
        _wt_refuse "conflict branch=${branch} onto=${onto} files=${c:-<unreadable>} — the row does not merge onto what is ahead of it; merge ${onto} into the tree, land again"; rc=2; break
      fi
      line_event "$plan" candidate "row=${row}" "base=${base}" "commit=${c}" "tree=${lt}" >/dev/null
      line_publish "$plan" "$row"; rc=$?
      [ "$rc" = 3 ] || break
    fi
    i=$((i + 1)); [ "$i" -le $((n * 5)) ] || { _wt_refuse "line-wait branch=${branch} — an entry ahead has not published in ${n} s; land again"; rc=2; break; }
    sleep 0.2
  done
  [ -z "$lt" ] || landing_tree_free "$lt"
  [ "$rc" = 0 ] || return 2
  _wt_hand_remove "$wt" "$root" "$branch" "$onto" "${LINE_CHECKOUT:-<none>}" "$LINE_PUBLISHED" "$rec"
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
# `lands_on=` as the roster holds it (labels, D4): `none`, or suite names separated by `,` or blanks,
# each a bare file name with or without `.test.sh`. Prints them as `<name>.test.sh`, comma-joined.
_line_suites() {  # <lands_on value> -> `a.test.sh,b.test.sh` | none; 1 when a name is not bare
  case "$1" in none|none[[:space:]]*) printf 'none\n'; return 0 ;; esac
  printf '%s\n' "$1" | tr ', \t' '\n\n\n' | awk '
    NF { if ($0 !~ /^[A-Za-z0-9_][A-Za-z0-9._-]*$/) { bad = 1; exit }
         sub(/\.test\.sh$/, ""); o = o (o == "" ? "" : ",") $0 ".test.sh" }
    END { if (bad || o == "") exit 1; print o }'
}

line_ready() {  # <tree> <root> <sid> <within seconds | empty> <the same command> -> 0 · 1 · 2 · 75
  local target="${1:-}" root="${2:-}" sid="${3:-}" within="${4:-}" again="${5:-}"
  local onto plan wt branch head acc c row roster launch name lands suites debt rec deadline=""
  [ -n "$sid" ] || { _wt_refuse "no-session path=${target:-<none>}"; return 2; }
  _line_load_run || { _wt_refuse "run-library-unloadable path=${_LINE_LIB_DIR}/run.sh"; return 2; }
  _line_load_gate || { _wt_refuse "gate-library-unloadable path=${_LINE_LIB_DIR}/gate.sh"; return 2; }
  onto="$(session_working_branch "$root" "$sid")" || { _wt_refuse "${onto:-no-bound-plan}"; return 2; }
  plan="$(session_plan "$root" "$sid")" || { _wt_refuse "no-bound-plan sid=${sid}"; return 2; }
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
  # THE ROSTER'S LAUNCH LINE (labels, D4): the row's by `row=`, else the plan row's agent by `name=`.
  # The suites are its `lands_on=`; the debt is its `lands_red=` suite, carried on the `ready` event
  # for T5's debt write (`line_publish` step 6).
  roster="${root%/}/.bionic/tmp/roster-${sid}.state"
  launch="$(_wt_launch_row "$roster" row "$row")" \
    || launch="$(_wt_launch_row "$roster" name "$(_line_plan_agent "$plan" "$row")")" \
    || { _wt_refuse "no-launch-row row=${row} roster=${roster} — ready reads the row's suites off its launch line"; return 2; }
  name="$(_wt_field "$launch" name)"; lands="$(_wt_field "$launch" lands_on)"
  [ -n "$lands" ] || { _wt_refuse "no-lands-on row=${row} name=${name:-<none>} — the launch line names no lands_on, so ready has no suites to run"; return 2; }
  suites="$(_line_suites "$lands")" || { _wt_refuse "lands-on-unreadable row=${row} lands_on=${lands}"; return 2; }
  debt="$(_wt_field "$launch" lands_red)"; debt="${debt%% *}"; [ -n "$debt" ] || debt=-
  case "${name}${debt}" in *'|'*|'') _wt_refuse "row-unwritable branch=${branch}"; return 2 ;; esac
  rec="$(line_record "$plan")" && _wt_proofs_prove "$rec" || {
    _wt_refuse "record-unwritable why=proofs-unwritable path=${rec:-<none>} branch=${branch} — the landing record cannot be written, so nothing is published; make it writable, say ready again"; return 2
  }
  [ -z "$within" ] || deadline=$(( $(_res_now) + within ))
  ( _line_carry "$plan" "$rec" "$root" "$row" "$name" "$head" "$branch" "$wt" "$suites" "$debt" "$deadline" "$again" )
}

_line_owed() { printf 'landed %s %s — owed: complete task %s, then stop %s\n' "$1" "$2" "$1" "$3"; }   # <row> <commit> <name>
_line_waiting() { printf 'WAITING %s — run again: %s\n' "$1" "$2"; }   # <row> <the same command>
_line_late() { [ -n "$1" ] && [ "$(_res_now)" -ge "$1" ]; }   # <deadline | empty>

# THE CARRIER'S LOOP, in its own subshell, whose pid is the `ready` event's carrier: the entry is
# present exactly while this runs, and its landing tree is freed when it ends.
_line_carry() {  # <plan> <rec> <root> <row> <name> <commit> <branch> <tree> <suites> <debt> <deadline> <again>
  local plan="$1" rec="$2" root="$3" row="$4" name="$5" com="$6" branch="$7" wt="$8" suites="$9"
  local debt="${10}" deadline="${11}" again="${12}" head ent base cand cbase first waitbase="" held=""
  local c rc s said
  _LINE_LT=""   # the landing tree, freed when the subshell ends (a global: the trap outlives the locals)
  trap '[ -z "$_LINE_LT" ] || landing_tree_free "$_LINE_LT"' EXIT
  _line_me
  line_event "$plan" ready "row=${row}" "name=${name}" "commit=${com}" "branch=${branch}" "tree=${wt}" \
    "suites=${suites}" "debt=${debt}" "carrier=${LINE_ME}" >/dev/null \
    || { _wt_refuse "record-unwritable why=proofs-unwritable path=${rec} branch=${branch}"; return 2; }
  while :; do
    head="$(line_head "$plan")"
    _line_count_git "$plan" "$rec" "$root" "$head"
    ent="$(_line_entries "$rec" "$head")"
    first="$(printf '%s\n' "$ent" | awk -F'\t' '$4 == "yes" { print $1; exit }')"
    ent="$(printf '%s\n' "$ent" | awk -F'\t' -v r="$row" '$1 == r { print; exit }')"
    [ -n "$ent" ] || { _line_closed "$rec" "$row" "$name"; return $?; }
    IFS=$'\t' read -r _ _ _ _ base cand _ _ _ cbase _ _ _ <<EOF
$ent
EOF
    # 1. THE BASE: wait while the entry ahead has no candidate, or while ours conflicts with it.
    if [ "$base" = - ] || [ "$base" = "$waitbase" ]; then
      _line_late "$deadline" && { _line_waiting "$row" "$again"; return 75; }
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
    # 3. THE PROOF: each named suite not yet green on this candidate, in the order named.
    for s in $(printf '%s\n' "$suites" | tr ',' ' '); do
      [ "$s" != none ] || break
      _line_proved "$rec" "$row" "$cand" "$s" && continue
      # Each run starts from the candidate, clean, in a landing tree this carrier holds (a carrier
      # run again finds the candidate built by the one before it, and no tree yet).
      [ -n "$_LINE_LT" ] || _LINE_LT="$(landing_tree_take "$root")" || { _LINE_LT=""; _wt_refuse "landing-tree-unavailable root=${root}"; return 2; }
      landing_tree_point "$_LINE_LT" "$cand" || { _wt_refuse "landing-tree-unpointable tree=${_LINE_LT} base=${cand}"; return 2; }
      _line_prove "$plan" "$rec" "$row" "$cand" "$cbase" "$_LINE_LT" "$s" "$deadline"
      case "$LINE_RESULT" in
        green) line_event "$plan" verdict "row=${row}" "commit=${cand}" "suite=${s}" result=green "log=${LINE_LOG}" >/dev/null ;;
        waiting) _line_waiting "$row" "$again"; return 75 ;;
        replaced) continue 2 ;;
        discarded) line_event "$plan" verdict "row=${row}" "commit=${cand}" "suite=${s}" result=discarded "log=${LINE_LOG}" >/dev/null
          continue 2 ;;
        red)
          line_event "$plan" verdict "row=${row}" "commit=${cand}" "suite=${s}" result=red "log=${LINE_LOG}" >/dev/null
          # T5's seam: a `none` verdict asked again, a red that also fails at the accepted head
          # (`standing`), and a red only on the declared debt suite (`$debt`) are decided here.
          line_event "$plan" returned "row=${row}" why=red "detail=${LINE_LOG}" >/dev/null
          printf 'RED %s %s %s\n' "$row" "$s" "$LINE_LOG"; return 1 ;;
        *) _wt_refuse "gate-unavailable row=${row} suite=${s} — ${LINE_LOG}"; return 2 ;;
      esac
    done
    # 4. THE PUBLISH, once first in line on the accepted head (line_publish asks both again, locked).
    if [ "$first" != "$row" ] || [ "$cbase" != "$head" ]; then
      _line_late "$deadline" && { _line_waiting "$row" "$again"; return 75; }
      sleep "$LINE_POLL"; continue
    fi
    said="$(line_publish "$plan" "$row" 2>&1)"; rc=$?
    case $rc in
      0) [ -z "$said" ] || printf '%s\n' "$said"
         printf 'LANDED %s %s\n' "$row" "$cand"; _line_owed "$row" "$cand" "$name"; return 0 ;;
      3|75) : ;;
      4) [ -n "$held" ] || printf '%s\n' "$said"; held=1 ;;
      6) c="$(_wt_bionic_committed "$root" "$head" "$cand")"; c="${c%/}"
         printf 'GUARD %s %s %s\n' "$row" "$(_wt_cquote "${c#* }")" "${c%% *}"
         printf '%s\n' "$said"; return 1 ;;
      5) printf '%s\n' "$said"; return 1 ;;
      *) printf '%s\n' "$said"; return 2 ;;
    esac
    _line_late "$deadline" && { _line_waiting "$row" "$again"; return 75; }
    sleep "$LINE_POLL"
  done
}

# The entry left the fold while its carrier ran: a person's own git merge carried it (published
# kind=git), or something else closed it.
_line_closed() {  # <rec> <row> <name>
  local last
  last="$(awk -F'|' -v r="row=$2" '$3 == r && ($2 == "ev=published" || $2 == "ev=returned") { l = $0 } END { print l }' "$1" 2>/dev/null)"
  case "$last" in
    *'|ev=published|'*)
      last="${last#*|commit=}"; last="${last%%|*}"
      printf 'LANDED %s %s\n' "$2" "$last"; _line_owed "$2" "$last" "$3"; return 0 ;;
  esac
  printf '%s\n' "${last:-RETURNED ${2}}"; return 1
}

# A green verdict for <suite> on <candidate> since the entry opened.
_line_proved() {  # <rec> <row> <candidate> <suite>
  awk -F'|' -v r="row=$2" -v c="commit=$3" -v s="suite=$4" '
    $3 == r && ($2 == "ev=published" || $2 == "ev=returned") { ok = 0 }
    $2 == "ev=verdict" && $3 == r && $4 == c && $5 == s { ok = ($6 == "result=green") }
    END { exit !ok }' "$1" 2>/dev/null
}

# A suite's log, under the record directory: `line/<row>-<suite>-<candidate's 12 hex>[-<n>].log`.
_line_suite_log() {  # <rec> <row> <suite> <candidate> -> a path no run has written
  local d="${1%/*}/line" b p n=1
  mkdir -p "$d" 2>/dev/null
  b="${d}/${2//\//-}-${3%.test.sh}-$(printf '%.12s' "$4")"
  p="${b}.log"
  while [ -e "$p" ]; do n=$((n + 1)); p="${b}-${n}.log"; done
  printf '%s' "$p"
}

# NEVER A SUITE PAST ITS TIME (D3): the gate's promise for the suite (`_gate_promise`, the per-field
# maximum of its cost record) against the time left. Prints the seconds the gate may take to admit
# it, so that it starts with its promised seconds still left; rc 1 when they are not left now.
_line_time_for() {  # <suite> <deadline> -> seconds
  local p s left
  _gate_store >/dev/null 2>&1 || return 0
  p="$(_gate_promise "$1")"; s="${p##*:}"
  left=$(( $2 - $(_res_now) ))
  awk -v s="${s:-0}" -v l="$left" 'BEGIN { if (s + 0 > l + 0) exit 1; printf "%d\n", l - s }'
}

# The run's verdict: green on rc 0, red otherwise. T5's seam: a signal, a failed start or no end line
# in the log is `none`.
_line_verdict() { if [ "${1:-1}" = 0 ]; then echo green; else echo red; fi; }   # <rc> <log>

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
# the fold. Sets LINE_RESULT (green | red | discarded | replaced | waiting | gate) and LINE_LOG.
_line_prove() {  # <plan> <rec> <row> <candidate> <cbase> <landing tree> <suite> <deadline>
  local within="" res rp r
  LINE_RESULT=""; LINE_LOG="$(_line_suite_log "$2" "$3" "$7" "$4")"
  if [ -n "$8" ]; then within="$(_line_time_for "$7" "$8")" || { LINE_RESULT=waiting; return 0; }; fi
  res="${LINE_LOG%.log}.run"; : > "$res"
  bash -c '. "$1/line.sh" && _line_load_gate && shift && _line_runner "$@"' _ \
    "$_LINE_LIB_DIR" "$7" "$within" "$6" "$LINE_LOG" "$res" "${LINE_ME%%:*}" &
  rp=$!
  while kill -0 "$rp" 2>/dev/null; do
    if _line_replaced "$2" "$1" "$3" "$5"; then
      _line_kill_tree "$rp"; wait "$rp" 2>/dev/null
      if grep -q '^admitted=' "$res" 2>/dev/null; then LINE_RESULT=discarded; else LINE_RESULT=replaced; fi
      rm -f "$res"; return 0
    fi
    sleep "$LINE_POLL"
  done
  wait "$rp" 2>/dev/null
  r="$(sed -n 's/^gate=//p' "$res" 2>/dev/null)"
  if [ -n "$r" ]; then
    if [ "$r" = 75 ]; then LINE_RESULT=waiting; else LINE_RESULT=gate; LINE_LOG="gate_ask rc ${r}"; fi
  else
    LINE_RESULT="$(_line_verdict "$(sed -n 's/^rc=//p' "$res" 2>/dev/null)" "$LINE_LOG")"
  fi
  rm -f "$res"
}
# The runner's body, in its own `bash -c`: ask, run, sample the gate while the suite runs (a locked
# read raises the run's peak), end the request with the suite's code. It stops its suite if the
# carrier is gone.
_line_runner() {  # <suite> <within | empty> <landing tree> <log> <result file> <carrier pid>
  local id rc p
  id="$(gate_ask landing "$1" ${2:+--within "$2"})"; rc=$?
  [ "$rc" -eq 0 ] || { printf 'gate=%s\n' "$rc" > "$5"; return 0; }
  printf 'admitted=%s\n' "$id" > "$5"
  ( [ -e "$3/.git" ] && cd "$3" && exec bash "tests/$1" ) > "$4" 2>&1 < /dev/null &
  p=$!
  while kill -0 "$p" 2>/dev/null; do
    kill -0 "$6" 2>/dev/null || { _line_kill_tree "$p"; return 0; }
    sleep "$LINE_POLL"; gate_state >/dev/null 2>&1
  done
  wait "$p"; rc=$?
  gate_end "$id" "$rc" >/dev/null 2>&1
  printf 'rc=%s\n' "$rc" >> "$5"
}
