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
# the newest commit a `published` line names (the head's first parent before any). It never does
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
    awk -F'|' -v r="row=${row}" '$2 == "ev=published" && $3 == r { f = 1 } END { exit !f }' "$rec" 2>/dev/null && continue
    tip="$(git -C "$tree" rev-parse --verify -q HEAD 2>/dev/null)" || continue
    git -C "$root" merge-base --is-ancestor "$tip" "$head" 2>/dev/null || continue
    [ -n "$last" ] && git -C "$root" merge-base --is-ancestor "$tip" "$last" 2>/dev/null && continue
    line_event "$plan" published "row=${row}" "commit=${head}" kind=git by=- why=- >/dev/null
  done <<EOF
$(units_rows "$plan" 2>/dev/null)
EOF
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
