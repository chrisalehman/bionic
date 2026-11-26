#!/bin/bash
# patrol.sh — the supervision of each live session, read from disk: which sessions live, what state each keeps
# in the state directory, what its roster holds against the dispatches its transcript shows, the tick's digest and
# running record, and the watcher's record and wake line.
#
# THE SESSIONS ARE READ FROM `${CLAUDE_CONFIG_DIR}/sessions/<pid>.json`, which names each live process with its
# session id and cwd, and each session's transcript under `${CLAUDE_CONFIG_DIR}/projects/<slug>/<sid>.jsonl`.
#
# Sourced, never executed.  Depends on detect.sh only for `detect_bounded`,
# and degrades to an unbounded run if that is not present.

PATROL_SCHEMA="patrol-session/v1"
PATROL_ROSTER_SCHEMA="patrol-roster/v1"
PATROL_WALL_SCHEMA="patrol-wall/v1"

# THE DEFAULT POKER INTERVAL, in seconds: its one copy. hooks/session-poker.sh takes its own default from it, and
# every reader of the interval (this file's `patrol_interval`, the sweep's window, the fill's quiet reads) asks the
# poker's `interval` for the project's configured value and falls back to this when that refuses or cannot be asked.
PATROL_INTERVAL_DEFAULT=1200

declare -F bionic_need >/dev/null 2>&1 || case "${BASH_SOURCE[0]}" in */*) . "${BASH_SOURCE[0]%/*}/loader.sh" ;; *) . ./loader.sh ;; esac
# roots.sh, THE SOFT SOURCE — the idiom lib/detect.sh uses for lib/deps.sh, taken at source
# time because this file reaches for four of its roots. Every root resolver in the tree has
# one definition there (epic-22 wave-01, N1); this file is a caller of `claude_home`,
# `transcripts_dir`, `tmp_root`, `plugin_root` and `project_root`.
bionic_need roots.sh claude_home
# roster.sh, THE SAME SOFT SOURCE, for `roster_open_names` (epic-23 wave-20 T17, D10):
# `patrol_roster_state` asks the one close predicate every wall asks, and this file is sourced
# by callers (doctor, the stop library, suites) that never declared roster.sh themselves.
bionic_need roster.sh roster_open_names
# alive.sh, THE SAME SOFT SOURCE, for `alive_sessions`: whether a session is alive has one rule, and
# the live set below is that rule's enumeration. Without it the live set is empty and the dead set
# names nothing: a rule this process cannot read never sends a session's state to the sweep.
bionic_need alive.sh alive_sessions || :
# time.sh, THE SAME SOFT SOURCE, for `_TIME_ISO_AWK` (wave-39 T17; D18): an instant has one reader, and this file's
# date arithmetic below is that reader's.
# A copy of this file read away from its directory (a suite's mutant) finds no time.sh: it still loads, and only
# its date readers come up empty, the fail-open direction every reader below already takes.
bionic_need time.sh _time_epoch || :

# Values ride on `|`-delimited lines read BY KEY, so a value carrying a pipe or
# a newline would forge a field. Same normalisation the roster writer applies to
# a brief, and for the same reason.
# NO `cut`, AND NOT BY ACCIDENT. Doctor's own header states the rule this file
# inherits: a diagnosis that needs coreutils to run dies on the broken machine
# it exists for. Bash does both jobs `cut` was doing here — a substring and a
# prefix strip — so the dependency is spent on `tr`/`sed` alone, which the
# normalisation genuinely needs.
_patrol_clean() {  # <value> [max-chars]
  local v
  v="$(printf '%s' "${1:-}" \
    | tr '\n\r\t|' '    ' \
    | sed -e 's/[[:cntrl:]]/ /g' -e 's/  */ /g' -e 's/^ *//' -e 's/ *$//')"
  printf '%s' "${v:0:${2:-200}}"
}

_patrol_field() {  # <line> <key>
  local f
  while IFS= read -r f; do
    case "$f" in "${2}="*) printf '%s' "${f#"${2}="}"; return 0 ;; esac
  done <<EOF
$(printf '%s' "${1:-}" | tr '|' '\n')
EOF
  printf ''
}

# THE PROJECT ROOT A SESSION'S STATE FILES LIVE UNDER is `project_root`'s answer, called
# directly. This file used to carry `_patrol_repo_root`, a lazy-sourcing wrapper that
# existed only because lib/root.sh might not be loaded; roots.sh pulls root.sh in above, so
# the wrapper was a second name for one answer and is gone (epic-22 wave-01, N1). Before
# 1.4.0 it was worse — a ninth byte-identical copy of the pre-`project_root` shape, asking
# git's common dir FIRST and walking for a `.bionic` ancestor only when no repository
# existed at all. That ordering privileges the git root, so a git repo holding a `.bionic`
# BELOW its root (design-ledger S3, tests/root.test.sh §3) had its roster written under the
# nested `.bionic/tmp` while this resolver answered with the git toplevel — the session read
# as blind (FIX-PATROL-ROOT).

# Every live session, by lib/alive.sh's one rule: a process running with the start its record
# names, the conversation each one holds now and each recorded predecessor of a cleared one.
# `kind`/`status` are deliberately not read: a session file describes a process, and whether that
# process still exists is the kernel's answer, not the file's.
patrol_live_sessions() {  # -> session=<sid>|pid=<pid>|cwd=<path>, one per line
  declare -F alive_sessions >/dev/null 2>&1 || return 0
  alive_sessions
}

# ─── SESSION-KEYED STATE UNDER .bionic/tmp ───────────────────────────────────
#
# ONE DEFINITION OF WHICH FILES BELONG TO A SESSION, read by both parties that
# need it: hooks/session-poker.sh's `sweep`, which deletes them once their owner
# is gone, and scripts/lib/checks.sh's dead-session detector, which is how doctor
# names the sweep as the repair. Written once here because the two must agree —
# a class added on the detector's side but not the verb's would put a row on
# doctor's page whose named cure clears nothing, which is the exact defect shape
# the check table exists to end.
#
# THE CLASSES, each `<class>-<session id>.state` under `<root>/.bionic/tmp`:
#
#   roster       hooks/dispatch-preflight.sh   the dispatch ledger
#   preflight    hooks/preflight-probe.sh      the budget attestation
#   engaged      scripts/lib/binding.sh        the engagement marker
#   sweeper      hooks/session-sweeper.sh      the ack ledger
#   patrol       (none now)                    the old timed job's stamp and its `.armed` sibling: no hook
#                                              writes them, and the class stays so the sweep and close-out's
#                                              wipe still clear the copies an older build left
#   stop-orders  hooks/stop-orders.sh          the per-session order queue (AC-6.2, wave-13)
#   tick-digest  hooks/session-poker.sh        the tick's digest and duty — kept off the `patrol-` prefix,
#                                              whose class glob would read it as a session named `digest-<sid>`
#   workspaces   scripts/lib/worktree.sh       the run's workspace record, one line per tree
#                                              `spawn-worktree.sh create` made (wave-25 T15)
#   gate         hooks/permission-answer.sh    the reserved requests the tick escalates
#                                              (wave-25 T15)
#   start-clock  hooks/execution-recorder.sh   one clock reading per agent start, a file per
#                                              start: `start-clock-<sid>.<agent id>.state`
#                                              (wave-27 T68)
#   owed         scripts/lib/owed.sh           what the person owes the run, one line per item;
#                                              close-out's wipe spares a live session's (wave-33 T12)
#   tick-run     hooks/poker/tick.sh           the running tick's process, while it runs (`tick_running`
#                                              below); not `tick-<sid>`, whose class glob would read every
#                                              `tick-digest-` file as a session named `digest-<sid>`
#   watch        hooks/watch.sh                the watch record: the watcher's process while it watches, or
#                                              why it rests (`watch_state` below)
#   duty         scripts/lib/refuse.sh         the whole refusal the turn-end hook last kept for the duty verb
#   stop-said    scripts/lib/stop.sh           the tick digest the stop line was last said for
#
# THE OWNER IS THE NAME UP TO ITS FIRST DOT, FOR EVERY CLASS (wave-27 T68; review pass 47 S1,
# A-orch-137). A session id holds no dot (lib/context.sh admits `[A-Za-z0-9_-]` only) and an
# agent id may, so `<class>-<sid>.state`, its `.armed` sibling and a per-start
# `<class>-<sid>.<key>.state` all name the session before the first dot. close-out.sh's wipe
# reads a file's owner by the same rule. A per-start file is a regular file or nothing: a
# directory or a link wearing that name is not one the hooks write, and is left alone.
#
# THE FILES THAT ARE NOT SESSION-KEYED ARE UNREACHABLE THROUGH THESE FUNCTIONS,
# and that is a property of the shape rather than a list anyone maintains:
# `context-spend.state` and `farm-out.state` carry no session id in their names,
# so no id derived here can address one. A non-session file added later is safe on
# arrival for the same reason. (`stop-check.state` was a third of these until
# epic-23 wave-15 deleted the observation record itself — ADR-028.)
PATROL_STATE_CLASSES="roster preflight engaged sweeper patrol stop-orders tick-digest workspaces gate start-clock owed tick-run watch duty stop-said"
PATROL_STATE_ARMED_SUFFIX=".armed"

# EVERY SESSION ID WITH STATE HERE, each once, in class-then-name order. Symlinks
# COUNT (a `-L` test beside `-e`, so a dangling one counts too): a link planted at
# one of these paths is a thing the reader has to see in order to refuse it out
# loud, and a walk that skipped it would report a session as clean while an aimed
# path sat in the directory.
#
# DEDUP IS ONE `sort -u` PASS, NOT A GROWING-STRING SCAN (T16, REQ-6 follow-up).
# The shape this replaces built a space-delimited `seen` list and re-scanned
# the WHOLE thing (`case " $seen " in *" $sid "*)`) for every candidate id — an
# O(n^2) cost that dominated a 400-dead-session sweep once the per-file forks
# elsewhere in the same call chain were fixed (T6). A session id can repeat
# here only ACROSS classes (roster-X and patrol-X both name X), never within
# one class's glob, so nothing about ORDER is a contract: no caller reads these
# ids as anything but a set (`patrol_dead_sessions`' containment check and
# `hooks/session-poker.sh`'s `sweep` verb both walk the result as an unordered
# id list; confirmed against every session-start and session-poker fixture,
# none of which assert a position). Collecting the whole (possibly
# duplicate-carrying) list first and deduping ONCE via `sort -u` is therefore
# behaviour-preserving and O(n log n) instead of O(n^2). Bash 3.2 target (the
# repo's own floor) is why this is `sort -u` and not an associative array.
patrol_state_session_ids() {  # <root> -> one session id per line
  local d c f base sid ids=""; d="$(tmp_root "${1:-}")"
  [ -d "$d" ] || return 0
  for c in $PATROL_STATE_CLASSES; do
    for f in "$d/$c"-*.state "$d/$c"-*.state"$PATROL_STATE_ARMED_SUFFIX"; do
      [ -e "$f" ] || [ -L "$f" ] || continue
      base="${f##*/}"
      sid="${base#"$c"-}"
      case "$sid" in
        *.*.state) { [ -f "$f" ] && [ ! -L "$f" ]; } || continue ;;   # a per-start file
      esac
      sid="${sid%%.*}"
      [ -n "$sid" ] || continue
      case "$sid" in *"/"*|.|..) continue ;; esac
      ids="${ids}${sid}
"
    done
  done
  [ -n "$ids" ] || return 0
  printf '%s' "$ids" | sort -u
}

# EVERY PER-START FILE HERE, ONE GLOB PER CLASS (T83): `<class>|<path>` per line, class by
# class in PATROL_STATE_CLASSES order and each class's glob in its own order, regular files
# only. A caller that asks `patrol_session_state_files` about many sessions passes this as
# its third argument, so the directory is read once per class and not once per class per
# session: the per-session glob read the whole of .bionic/tmp ten times for every session,
# and a 400-dead-session sweep cost 15.4 s where 1.11.0 cost 6.1 s.
patrol_per_start_files() {  # <root> -> one <class>|<path> line per per-start file
  local d c f; d="$(tmp_root "${1:-}")"
  [ -d "$d" ] || return 0
  for c in $PATROL_STATE_CLASSES; do
    for f in "$d/$c"-*.*.state; do
      [ -f "$f" ] && [ ! -L "$f" ] || continue
      printf '%s|%s\n' "$c" "$f"
    done
  done
}

# ONE SESSION'S FILES, BY EXACT PATH. The ids come off the filenames above, so
# building each candidate path back by concatenation means a strange id can only
# ever address the file it was read from — there is no pattern here for it to
# widen. The one glob is a per-start file's (T68), taken only for an id of a
# session id's own shape, so it widens to nothing but that session's names.
# With a third argument (patrol_per_start_files' list) the per-start files are picked
# from it instead: the same files, in the same order, with no read of the directory.
patrol_session_state_files() {  # <root> <session id> [<per-start list>] -> one path per line
  local d sid="${2:-}" c f l; d="$(tmp_root "${1:-}")"
  [ -n "$sid" ] || return 0
  for c in $PATROL_STATE_CLASSES; do
    for f in "$d/$c-$sid.state" "$d/$c-$sid.state$PATROL_STATE_ARMED_SUFFIX"; do
      [ -e "$f" ] || [ -L "$f" ] || continue
      printf '%s\n' "$f"
    done
  done
  # THE PER-START FILES (T68): `<class>-<sid>.<key>.state`, the one glob here, so the id must be
  # a session id's shape before it joins a pattern; regular files only, never a link.
  case "$sid" in *[!A-Za-z0-9_-]*) return 0 ;; esac
  if [ $# -ge 3 ]; then
    [ -n "$3" ] || return 0
    while IFS= read -r l; do
      c="${l%%|*}"
      case "$l" in "$c|$d/$c-$sid".*.state) printf '%s\n' "${l#*|}" ;; esac
    done <<EOF
$3
EOF
    return 0
  fi
  for c in $PATROL_STATE_CLASSES; do
    for f in "$d/$c-$sid".*.state; do
      [ -f "$f" ] && [ ! -L "$f" ] || continue
      printf '%s\n' "$f"
    done
  done
}

# The live set as bare ids. CWD IS DELIBERATELY NOT CONSULTED: a session live in
# another project still owns its files here — it may have been started in this
# root and `cd`-ed away — and the pid is the only fact that decides whether
# anyone can still act on what it left.
patrol_live_session_ids() {  # -> one live session id per line
  local l
  patrol_live_sessions 2>/dev/null | while IFS= read -r l; do
    case "$l" in
      session=*) l="${l#session=}"; printf '%s\n' "${l%%|*}" ;;
    esac
  done
}

# THE ANSWER BOTH READERS ACTUALLY WANT: which sessions left state here that
# nobody can act on any more. Extra ids may be named as live by the caller, and
# the one caller that does is the session running the verb — it is live by
# construction, and saying so by hand is what keeps a claude-home this process
# cannot read (an unreadable sessions directory, a missing jq) from letting a
# session sweep its own state out from under itself.
patrol_dead_sessions() {  # <root> [<also-live id>...] -> one session id per line
  local root="${1:-}" live sid; shift 2>/dev/null || :
  declare -F alive_sessions >/dev/null 2>&1 || return 0
  live="$(patrol_live_session_ids)"
  for sid in "$@"; do
    [ -n "$sid" ] && live="${live}${live:+
}${sid}"
  done
  # Newline-delimited containment, so a dead session whose id is a PREFIX of a
  # live one is not mistaken for it.
  while IFS= read -r sid; do
    [ -n "$sid" ] || continue
    case "
$live
" in
      *"
$sid
"*) continue ;;
    esac
    printf '%s\n' "$sid"
  done <<EOF
$(patrol_state_session_ids "$root")
EOF
}

# WHO IS OUT: the rows of a run a live writer holds, the one question the watcher's merge pass and the close both ask
# before they close the run. A writer is out while a roster of the run's state directory holds its name open under the
# run's plan, by the dispatch wall's closure rule (lib/fill.sh `fill_held_ids`: an ack after its launch, a dead
# session whose files the sweep takes, or a closed run closes it, and nothing else). Every row of the table is asked,
# whatever its kind or status: a run is closed only when nobody is still writing any part of it.
# <plan> -> `<id><TAB><name><TAB><session id>` per row out, in table order; rc 2, nothing printed, when the rows or the
# rosters' reader cannot be had, which no caller may read as "nobody is out".
patrol_rows_out() {  # <plan>
  local plan="${1:-}" rows
  [ -n "$plan" ] && [ -f "$plan" ] || return 2
  bionic_need units.sh units_rows || return 2
  declare -F _units_roster_libs >/dev/null 2>&1 && _units_roster_libs || return 2
  declare -F fill_held_ids >/dev/null 2>&1 || return 2
  rows="$(units_rows "$plan" 2>/dev/null)" || return 2
  fill_held_ids "$plan" "$(printf '%s\n' "$rows" | awk -F'\t' '$1 != "" { print $1 }')"
}

# The transcript file for a session id. Scanned rather than derived from a
# slugged cwd, the same way hooks/dispatch-preflight.sh's liveness probe scans:
# the slug rule belongs to the CLI and a copy of it here would be a second
# definition of where the CLI keeps its own files.
patrol_transcript() {  # <sid> -> path, or empty
  local sid="${1:-}" d
  [ -n "$sid" ] || return 1
  for d in "$(transcripts_dir)"/*/; do
    [ -f "${d}${sid}.jsonl" ] && { printf '%s' "${d}${sid}.jsonl"; return 0; }
  done
  return 1
}

# ONE STREAMING PASS over the transcript, emitting four record kinds for the awk
# join below. Streaming and not `jq -s`: a long session's transcript is tens of
# megabytes and slurping it costs the memory of the whole file to answer a
# question about a dozen lines of it.
#
# MAIN THREAD ONLY, BY THE POKER'S OWN TWO RULES. A subagent's turns are written
# to `<sid>/subagents/*.jsonl` on this machine, but `isSidechain` is the field
# that SAYS so, and filtering on the fact rather than on the layout keeps this
# correct if the layout moves. The second rule — an entry carrying an explicit
# agent-id key is somebody's agent turn, not this thread's — is
# hooks/session-poker.sh's `count_main_thread_dispatches`, adopted here verbatim
# so the two readers partition the transcript identically; it is matched over the
# whole serialized entry rather than over top-level keys because that is where the
# poker's line regex matches it, and on this machine's transcripts every such key
# is NESTED (12 entries, 0 top-level). Two readers with different partitions are
# two answers, which is the defect this shape exists to prevent
# (tests/cross-gate-agreement.test.sh §Q).
_patrol_scan_jq='
  select(type == "object")
  | select(.isSidechain != true)
  | select((tostring | test("\"agent_?[Ii][dD]\"[ \t]*:[ \t]*\"[^\"]")) | not)
  | select((.message.content? | type) == "array")
  | . as $entry
  | $entry.message.content[]
  | if (.type == "tool_use" and .name == "Agent") then
      # THE TIMESTAMP RIDES ALONG: the ENTRY own `timestamp` field, the same one
      # hooks/session-poker.sh window-scopes count_main_thread_dispatches against, read off
      # $entry rather than off this content item (a tool_use block carries none of its own).
      ["A", .id, ($entry.timestamp // "")]
    elif (.type == "tool_result") then
      ((if (.content | type) == "string" then .content
        elif (.content | type) == "array" then ([.content[]? | select(.type == "text") | .text] | join(" "))
        else "" end) | gsub("[\n\r\t|]"; " ")) as $full
      | ["R", (.tool_use_id // ""),
         (if ($full | test("PreToolUse:Agent hook error:")) then "1" else "0" end),
         ($full | .[0:200]), ($entry.timestamp // "")]
    else empty end
  | @tsv
'

# THE COUNT OF DISPATCHES AND OF REFUSALS, off the A and R records of one pass.
#
# REFUSED DISPATCHES ARE COUNTED HERE TOO, off the same `R` records the job
# join already reads — no second pass over the transcript. This is a
# DELIBERATE second copy of hooks/session-poker.sh's own
# `count_refused_dispatches`, not a shared helper: that script answers for the
# live tick from a bare transcript scan, this one answers for doctor's
# reconstruction inside a jq/awk join that already has the `R` record in hand,
# and a sourced library the installer misses would make either copy a silently
# inert consumer (the same reasoning hooks/session-poker.sh's own header gives
# for its `parse_seconds` duplicate).
#
# THE MARKER IS NOT THE RULE — THE JOIN IS. `PreToolUse:Agent hook error:` is
# what the CLI writes into a refused dispatch's tool_result, but it is ordinary
# text everywhere else: the plan that specifies this behaviour, the reports that
# review it and every brief that quotes it all carry the literal, and reading a
# file with one in it puts it in a tool_result of that read. So a refusal is
# credited only when the tool_result carrying it JOINS BY tool_use_id to an
# `Agent` tool_use — the refused dispatch's own result — which is the rule
# hooks/session-poker.sh now applies too, on the same fixture
# (tests/cross-gate-agreement.test.sh §Q). The test is taken on the UNTRUNCATED
# content: a real refusal carries the marker at offset 482 (the CLI prefixes the
# hook's own stderr with the tool name and the hook's path), so the 200-character
# cut the job join reads by belongs after the test, never before it.
#
# THE WINDOW APPLIES HERE TOO. `agents` and `refused` used to be counted over the
# transcript's WHOLE LIFE, while hooks/session-poker.sh's own counters scope to the
# roster's own window (`patrol_window()` below) — and since a
# `.bionic/tmp` wipe re-opens the roster at zero, a session running a second wave read its
# first wave's dispatches against a roster that only began at the wipe, and doctor printed
# `N launches unrostered` for a wall that had rostered everything asked of it since. The
# two readers are now the SAME RULE: `since` (passed in by patrol_window(), or empty for
# "the whole transcript" — exactly the fallback hooks/session-poker.sh takes when a roster
# cannot be dated at all) gates BOTH the `A` records that build `isagent`/`agents` and the
# `R` records that credit a refusal, each on its own entry's timestamp. An agent dispatched
# before the window never enters `isagent`, and a refusal recorded before the window is
# never credited, matching a wall that is only being asked about from the window forward.
#
# AN ENTRY WITH NO TIMESTAMP IS IN, the same answer hooks/session-poker.sh's own
# in_window() gives a line whose `timestamp` field it cannot find: a reader that dropped
# undatable entries would silently shrink every count on a transcript shape neither reader
# has seen, which is the wrong direction for a wall.
_patrol_join_awk='
  BEGIN { FS = "\t"; n = 0; agents = 0; refused = 0 }
  function in_window(ts,   d) {
    if (since == "") return 1
    if (ts == "") return 1
    d = substr(ts, 1, 19)
    return (d >= substr(since, 1, 19))
  }
  $1 == "R" { if ($3 == "1" && ($2 in isagent) && in_window($5)) refused++ }
  $1 == "A" { if (in_window($3)) { agents++; isagent[$2] = 1 } }
  END {
    printf "AGENTS\t%d\n", agents
    printf "REFUSED\t%d\n", refused
  }
'

_patrol_scan() {  # <transcript> [<since ISO>] -> AGENTS/REFUSED records
  local t="${1:-}" since="${2:-}" secs
  [ -f "$t" ] || return 1
  command -v jq >/dev/null 2>&1 || return 1
  secs="${BIONIC_DOCTOR_PROBE_SECONDS:-15}"
  if command -v detect_bounded >/dev/null 2>&1; then
    detect_bounded "$secs" jq -r "$_patrol_scan_jq" "$t" 2>/dev/null | awk -v since="$since" "$_patrol_join_awk"
  else
    jq -r "$_patrol_scan_jq" "$t" 2>/dev/null | awk -v since="$since" "$_patrol_join_awk"
  fi
}

# The interval, from its owner. `interval` is the project's configured value and
# REFUSES on a malformed one; PATROL_INTERVAL_DEFAULT is what a refusal, or a poker
# that cannot be reached, falls back to — the same two-step
# hooks/dispatch-preflight.sh's arming wall takes, so doctor measures staleness
# against the number the wall would refuse against.
patrol_interval() {  # <repo-root> -> "<seconds> <configured|default>"
  local repo="${1:-}" poker secs=""
  poker="$(plugin_root 2>/dev/null)/hooks/session-poker.sh"
  if [ -f "$poker" ]; then
    secs=$( cd "$repo" 2>/dev/null && bash "$poker" interval 2>/dev/null )
    case "$secs" in ''|*[!0-9]*) secs="" ;; esac
  fi
  if [ -n "$secs" ] && [ "$secs" -gt 0 ]; then printf '%s configured' "$secs"; return 0; fi
  printf '%s default' "$PATROL_INTERVAL_DEFAULT"
}

# THE WINDOW: since when does THIS roster's own record of this session begin. The answer is the roster file's
# creation instant. The creation instant is the filesystem's
# own (`stat %B`, `%W` on GNU, where 0 means none is kept), never the mtime: the roster is append-only, so its mtime
# is the last dispatch and a window from it would hide every gap but the newest. tests/cross-gate-agreement.test.sh
# §Q.3 compares the two COUNTING functions this window feeds on one shared fixture.
#
# EVERY FAILURE IS AN EMPTY STRING, never a refusal: no session, no root or a filesystem that keeps no creation time
# all mean "no window", and the counters read the whole transcript.
patrol_window() {  # <repo-root> <sid> -> ISO instant on stdout, empty for "the whole transcript"
  local repo="${1:-}" sid="${2:-}" t f b=""
  [ -n "$repo" ] && [ -n "$sid" ] || return 0
  t="$(tmp_root "$repo" 2>/dev/null)" || return 0
  f="$t/roster-${sid}.state"
  b="$(stat -f %B "$f" 2>/dev/null || stat -c %W "$f" 2>/dev/null)" || b=""
  case "$b" in ''|*[!0-9]*|0) b="" ;; esac
  [ -n "$b" ] || return 0
  date -u -r "$b" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$b" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null
  return 0
}

_patrol_mtime() {  # <file>
  stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null
}

# THE DATE FUNCTIONS OF lib/time.sh, as the poker's parts and the readers here splice them into an awk program.
_PATROL_ISO_AWK="${_TIME_ISO_AWK:-}"

# THE ROSTER, COUNTED THE WAY IT IS WRITTEN. The file is append-only and a row
# is appended per status transition — `intended` at the wall, then `confirmed`,
# then `identified` — so the number of DISPATCHES the wall saw is the number of
# `status=intended` rows, and counting rows outright would multiply every
# dispatch by however far it got.
#
# OPEN AND CLOSED ARE THE ONE CLOSE PREDICATE'S (epic-23 wave-20 T17, D10; T2's
# carry-over). A dispatched name is CLOSED only when `roster_open_names`
# (lib/roster.sh) says so — an ack in this session's sweeper ledger stamped after
# the name's latest launch — the reading the dispatch wall, the sweeper, the stop
# wall and the tick's adopt fold already share. This function used to close a name
# on a `landing-swept/v1|…|state=MET` marker instead (and before the Step-6
# security review, on any marker at all), so doctor and the Patrol report could
# call a wave's writer finished while every wall still held its name open. A MET
# marker records a landing seen, not an agent gone; an UNMET one never closed
# anything and still does not.
patrol_roster_state() {  # <repo-root> <sid> -> rows=…|open=…|closed=…|names=…|path=…
  local repo="${1:-}" sid="${2:-}" f ledger rows names closed open open_names nm nl='
'
  f="$(tmp_root "$repo")/roster-${sid}.state"
  if [ ! -f "$f" ] || [ -L "$f" ]; then
    printf 'rows=0|open=0|closed=0|present=no|path=%s' "$f"
    return 0
  fi
  ledger="$(tmp_root "$repo")/sweeper-${sid}.state"
  rows=$(grep -c '^roster-state/v1|status=intended|' "$f" 2>/dev/null || true)
  case "$rows" in ''|*[!0-9]*) rows=0 ;; esac
  names="$(grep '^roster-state/v1|status=intended|' "$f" 2>/dev/null \
           | tr '|' '\n' | sed -n 's/^name=//p' | sort -u)"
  # The predicate reads the ledger as empty when it is absent, unreadable or a symlink,
  # which leaves every name open: the generous direction for a count of work in flight.
  open_names="$(roster_open_names "$f" "$ledger")"
  closed=0; open=0
  while IFS= read -r nm; do
    [ -n "$nm" ] || continue
    case "$nl$open_names$nl" in
      *"$nl$nm$nl"*) open=$((open + 1)) ;;
      *)             closed=$((closed + 1)) ;;
    esac
  done <<EOF
$names
EOF
  printf 'rows=%s|open=%s|closed=%s|present=yes|path=%s' "$rows" "$open" "$closed" "$f"
}

# EVERY LINE THE PATROL REPORT IS MADE OF, for every live session on this
# machine. Emitted as keyed records rather than prose so the renderer decides
# what a reader sees and this file decides nothing about presentation.
patrol_report() {  # -> patrol-session/v1 … patrol-roster/v1 … patrol-wall/v1
  local sess sid pid cwd repo here_repo tr scan since agents refused cause blind
  local rline dispatches tag a

  here_repo="$(project_root "$PWD")"

  while IFS= read -r sess; do
    [ -n "$sess" ] || continue
    sid="$(_patrol_field "$sess" session)"
    pid="$(_patrol_field "$sess" pid)"
    cwd="$(_patrol_field "$sess" cwd)"
    repo="$(project_root "$cwd")"

    tr="$(patrol_transcript "$sid")" || tr=""
    cause=""
    if [ -z "$tr" ]; then cause="no transcript under projects/"
    elif ! command -v jq >/dev/null 2>&1; then cause="jq is not on PATH"
    fi

    printf '%s|session=%s|pid=%s|cwd=%s|repo=%s|here=%s|cause=%s\n' \
      "$PATROL_SCHEMA" "$sid" "$pid" "$cwd" "$repo" \
      "$( [ "$repo" = "$here_repo" ] && echo yes || echo no )" "$cause"

    agents=""; refused=""
    if [ -n "$tr" ] && [ -z "$cause" ]; then
      since="$(patrol_window "$repo" "$sid")"
      scan="$(_patrol_scan "$tr" "$since")"
      while IFS=$'\t' read -r tag a; do
        case "$tag" in
          AGENTS) agents="$a" ;;
          REFUSED) refused="$a" ;;
        esac
      done <<EOF
$scan
EOF
    fi
    case "$refused" in ''|*[!0-9]*) refused=0 ;; esac

    rline="$(patrol_roster_state "$repo" "$sid")"
    printf '%s|session=%s|%s\n' "$PATROL_ROSTER_SCHEMA" "$sid" "$rline"

    dispatches="$(_patrol_field "$rline" rows)"
    case "$agents" in ''|*[!0-9]*) agents="" ;; esac
    if [ -z "$agents" ]; then
      printf '%s|session=%s|dispatched=|rostered=%s|blind=|refused=%s|cause=%s\n' \
        "$PATROL_WALL_SCHEMA" "$sid" "$dispatches" "$refused" "${cause:-the transcript could not be read}"
    else
      # NET OF REFUSALS. A dispatch the wall REFUSED still shows up as an
      # `Agent`/`Task` tool_use in $agents (the attempt happened), but it exits
      # before dispatch-preflight.sh's roster append and so is never in
      # $dispatches either — a refusal is the wall doing its job, not a gap in
      # it, and crediting it here is what keeps a session full of healthy
      # refusals from reading as a wall that never saw them.
      blind=$(( agents - dispatches - refused ))
      [ "$blind" -lt 0 ] && blind=0
      printf '%s|session=%s|dispatched=%s|rostered=%s|blind=%s|refused=%s|cause=\n' \
        "$PATROL_WALL_SCHEMA" "$sid" "$agents" "$dispatches" "$blind" "$refused"
    fi
  done <<EOF
$(patrol_live_sessions)
EOF
}

# ─── THE TICK'S DIGEST FILE: ITS PATH AND ITS READER (wave-24 T7, T27; D4, D5) ──────────────
#
# TWO PROCESSES, ONE FILE. `session-poker.sh tick` writes the digest under its root (its
# `tick_digest_file` passes the root it resolved), and the stop library's collector reads its
# `at=`, `head=` and `facts_state=` to judge a tick turn (`duty=` and `reconcile=` are written
# for the tick's own advice and read by no wall, since wave-31 T32). The path and the
# reader live here, which both already source, so a renamed file cannot leave the stop wall
# reading a path the tick no longer writes (Step-6 review finding 15; critic I3). Not
# `patrol-digest-`: the `patrol` class glob would read it as a session named `digest-<sid>`.
tick_digest_path() {  # <project root> <session-id> -> absolute path, or nothing
  [ -n "${1:-}" ] && [ -n "${2:-}" ] || return 1
  printf '%s/.bionic/tmp/tick-digest-%s.state' "$1" "$2"
}

# One `key=value` line of the digest file, or empty. A symlink is no file.
tick_digest_field() {  # <digest file> <key>
  [ -f "$1" ] && [ ! -L "$1" ] || return 0
  sed -n "s/^$2=//p" "$1" 2>/dev/null | head -1
}

# ─── A TICK OF THIS SESSION IS RUNNING: ITS RECORD AND THE ONE QUESTION ───────────────────────
#
# `<root>/.bionic/tmp/tick-run-<sid>.state`, two lines: `pid=<pid>` and `start=<start>`, the start as lib/alive.sh's
# `alive_since` reads it. The tick claims it before it decides and removes it as it exits (hooks/poker/tick.sh), and
# both the tick and the stop wall ask `tick_running`, so a second tick and the turn end read one answer. The answer
# is lib/alive.sh's one rule, never the file's age or existence: a tick killed before it could remove its record
# leaves one naming a dead process, or a pid the OS has since handed on, and that record holds nothing off.
#
# A RECORD WITH NO START IS NOT A TICK'S. alive_run reads an empty start as `kill -0` alone, which any reused pid
# passes; the tick always records a start, so a record without one is read as no running tick.
#
# THE CLAIM IS A HARD LINK OF A WHOLE FILE, so a reader never sees a half-written record and two ticks starting
# together cannot both create it. Taking over a dead record is a rename over it, which two ticks starting together
# over the same dead record can both do; then both run, as every tick did before the record existed.
tick_run_path() {  # <project root> <session-id> -> absolute path, or nothing
  [ -n "${1:-}" ] && [ -n "${2:-}" ] || return 1
  printf '%s/.bionic/tmp/tick-run-%s.state' "$1" "$2"
}

_tick_run_read() {  # <record> — sets _TR_PID and _TR_START; rc 1 when it is no record or names no pid
  local l
  _TR_PID=''; _TR_START=''
  [ -f "$1" ] && [ ! -L "$1" ] || return 1
  while IFS= read -r l; do
    case "$l" in pid=*) _TR_PID="${l#pid=}" ;; start=*) _TR_START="${l#start=}" ;; esac
  done < "$1"
  case "$_TR_PID" in ''|*[!0-9]*) return 1 ;; esac
}

# tick_running <root> <sid> -> rc 0 with `<pid> <start>` on stdout while a live process holds the record; rc 1
# otherwise, and when lib/alive.sh is not loaded, so a reader that cannot ask the rule judges as it did before.
tick_running() {
  local f
  f="$(tick_run_path "${1:-}" "${2:-}")" || return 1
  _tick_run_read "$f" && [ -n "$_TR_START" ] || return 1
  declare -F alive_run >/dev/null 2>&1 || return 1
  alive_run "$_TR_PID" "$_TR_START" || return 1
  printf '%s %s\n' "$_TR_PID" "$_TR_START"
}

# tick_run_claim <root> <sid> <pid> -> rc 0 the record names <pid>; rc 1 a live tick of the session holds it, its
# `<pid> <start>` on stdout; rc 2 it could not be written (a link where it goes, a process with no start to read, a
# directory that refuses the write). The caller has already judged the directory safe to write in.
tick_run_claim() {
  local f d start tmp held
  f="$(tick_run_path "${1:-}" "${2:-}")" || return 2
  case "${3:-}" in ''|*[!0-9]*) return 2 ;; esac
  [ -L "$f" ] && return 2
  declare -F alive_since >/dev/null 2>&1 || return 2
  start="$(alive_since "$3")"
  [ -n "$start" ] || return 2
  d="${f%/*}"
  [ -d "$d" ] || mkdir -p "$d" 2>/dev/null || return 2
  tmp="$d/.tick-run-$2.$3"
  printf 'pid=%s\nstart=%s\n' "$3" "$start" > "$tmp" 2>/dev/null || { rm -f "$tmp"; return 2; }
  if ln "$tmp" "$f" 2>/dev/null; then rm -f "$tmp"; return 0; fi
  if held="$(tick_running "$1" "$2")"; then
    rm -f "$tmp"
    [ "${held%% *}" = "$3" ] && return 0
    printf '%s\n' "$held"
    return 1
  fi
  [ -L "$f" ] && { rm -f "$tmp"; return 2; }
  mv -f "$tmp" "$f" 2>/dev/null || { rm -f "$tmp"; return 2; }
  return 0
}

# tick_run_release <root> <sid> <pid> — removes the record when it names <pid>; one another tick took is left.
tick_run_release() {
  local f
  f="$(tick_run_path "${1:-}" "${2:-}")" || return 0
  _tick_run_read "$f" || return 0
  [ "$_TR_PID" = "${3:-}" ] && rm -f "$f" 2>/dev/null
  return 0
}

# ─── THE WATCHER'S PASS: ITS EXITS, ITS LINE AND ITS INTERVAL ────────────────────────────────
#
# ONE HOME FOR EVERY NUMBER THE WATCH IS BUILT ON. `session-poker.sh tick --watch` is one pass of the tick with no
# model; the hook that loops it, the walls that judge it and the suites that drive it read these names, never the
# digits, so a code that moves moves for all of them at once.
#
# THE EXITS. Quiet: nothing in the tick's print asks for an act, and nothing is printed. Wake: an act is owed, and
# stdout is one line saying it. Rest: the run waits only on the person and the watch should end. Refused: the pass
# could not run the tick (no session key, a tick that refused), its reason on stderr. WAKE is 2 because 2 is the code
# an `asyncRewake` hook wakes the model on (prototype-wake: the only exit that re-invokes the model; 0, a kill and a
# timeout end silently), so the hook passes a wake through unchanged. REST is 3, distinct from every code bash itself
# uses for a failed command (1, 2, 126, 127, 128+n). Any other code reads as refused.
WATCH_RC_QUIET=0
WATCH_RC_REFUSED=1
WATCH_RC_WAKE=2
WATCH_RC_REST=3
# THE WAKE LINE'S CEILING, in characters. The model receives it as the whole of a hook's message, so it carries the
# act and its subject and nothing else; the line is plain ASCII, so a character is a byte.
WATCH_LINE_MAX=120
# THE WATCH INTERVAL, in seconds: a pass every five minutes unless `watch-interval:` in .bionic/config.yaml says
# otherwise, and never less often than every twenty minutes, the Patrol's own period, so the watch is never a slower
# eye than the clock it replaces. Read and refused by `session-poker.sh interval --watch`.
WATCH_INTERVAL_DEFAULT=300
WATCH_INTERVAL_MAX=1200
# THE WATCHER'S DAY, in seconds: hooks/hooks.json registers hooks/watch.sh with this as its `timeout`, and the platform
# ends the hook silently when it runs out, so the watcher ends itself first. Its last pass comes
# while at least WATCH_LIFE_MARGIN of the day is left, so a slow tick near the end is not cut off half way.
WATCH_LIFE_MAX=86400
WATCH_LIFE_MARGIN=600

# watch_wake_line <tick print file> -> the one wake line on stdout and rc 0, or nothing and rc 1.
#
# THE WOKEN KINDS ARE THE LINES THAT ASK FOR AN ACT, OF THE MODEL OR OF THE PERSON, AND NO OTHERS. In the order the
# line leads with them, the person's first: GATE (a denied reserved request, put to the person), restart, GOAL,
# DUPLICATE-SESSION and DUPLICATE-START, GONE? and GONE, NOTIFY, STANDDOWN, LOAD, NOT-LANDED, FILL (IDLE rides it), and
# RECONCILE. A STANDDOWN for the load is LOAD: its row is pending and live, which hold refuses, so its act says the
# load and offers no hold; the tick's band line alone does not make it a met stand-down. Advice (HELD, LEDGER,
# FINDING, SPLIT, RANGE), what the tick did itself (LANDED, regression-run, RUNNING),
# DISARM (the run is delivered, and nothing is owed for it) and the quiet lines (QUIET, WAITING, no FILL, the gate
# share) wake nothing.
#
# AN UNCHANGED PRINT WAKES NOTHING. The tick's digest already says whether anything it decided moved; a print that
# ends `unchanged since` was told in full before, so the standing holds and the restart line it re-prints were seen.
#
# ONE LINE, ASCII, AT MOST WATCH_LINE_MAX: the leading kind with its subjects and its act, worded as an instruction,
# then `; also` and the other kinds with their subjects. Subjects are cut to a share of the line before the line is,
# and the line is cut last, so the act of the leading kind survives a long name.
#
# A CAUSE IS SAID ONCE. The print is in full whenever anything the tick hashes moved, so a row still quiet would be
# named again by every print some other fact moved. With <told file>, a cause it lists is left out of the line: a row
# quiet past its cadence (`NOTIFY:quiet:<row>:<the mtime it went quiet at>`, so a row that wrote and went quiet again
# is a new cause), a row past its duration (`NOTIFY:overdue:<row>`), a GONE or GONE? row (`<kind>:<row>`), and the
# restart (`restart:<classes>|<reloaded-since>`, the watch record's told= key). The file is then rewritten with the
# causes this print holds, told before or now, so a cause that leaves the print is told again when it comes back. An
# unchanged print leaves the file as it was.
watch_wake_line() {  # <tick print file> [<told file>]
  [ -f "${1:-}" ] || return 1
  local line tf="${2:-}"
  { [ -n "$tf" ] && [ -f "$tf" ] && [ ! -L "$tf" ]; } || tf=""
  line="$(LC_ALL=C awk -v em="—" -v max="$WATCH_LINE_MAX" -v tf="$tf" '
    BEGIN { if (tf != "") { while ((getline l < tf) > 0) told[l] = 1; close(tf) } }
    function cause(k) { have[k] = 1; return !(k in told) }
    function ascii(s) { gsub(/[^ -~]+/, "?", s); return s }
    function dash(s) { return index(s, em) == 1 && length(s) == length(em) }
    function add(k, s) {
      if (!(k in seen)) { seen[k] = 1 }
      s = ascii(s); if (s == "" || ((k, s) in has)) return
      has[k, s] = 1; subj[k] = subj[k] (subj[k] == "" ? "" : " ") s
    }
    function mark(k) { seen[k] = 1 }
    function cap(s, n,   w, i, c, out, more) {
      c = split(s, w, " "); out = ""; more = 0
      for (i = 1; i <= c; i++) {
        if (length(out) + length(w[i]) + 1 > n && out != "") { more = c - i + 1; break }
        out = out (out == "" ? "" : " ") (length(w[i]) > n ? substr(w[i], 1, n - 3) "..." : w[i])
      }
      return out (more ? " +" more : "")
    }
    /^poker: unchanged since / { unchanged = 1 }
    /^[a-z-]+\/v[0-9]+[|]/ && index($0, "|decision=") {
      c = split($0, f, "|")
      for (i = 1; i <= c; i++) {
        if (index(f[i], "fill=") == 1) fill = substr(f[i], 6)
        else if (index(f[i], "rows=") == 1) rows = substr(f[i], 6)
      }
      next
    }
    $1 != "poker:" { next }
    $2 == "GATE" { s = $5; sub(/:$/, "", s); add("GATE", s); next }
    $2 == "restart" && $3 == "needed" {
      s = substr($0, index($0, em) + length(em) + 1); r = "-"
      if (i = index(s, ", or reloaded since ")) { r = substr(s, i + 20); r = substr(r, 1, index(r, " ") - 1) }
      if (cause("restart:" substr(s, 1, index(s, " changed after ") - 1) "|" r)) mark("restart")
      next
    }
    $2 == "GOAL" { add("GOAL", $3); next }
    $2 == "GONE?" || $2 == "GONE" { if (cause($2 ":" $3)) add($2, $3); next }
    $2 == "DUPLICATE-SESSION" || $2 == "DUPLICATE-START" || $2 == "NOT-LANDED" { add($2, $3); next }
    $2 == "NOTIFY" && $4 == "quieter" {
      s = $0
      while (match(s, /[^ ;]+: no line for [0-9]+s against cadence [0-9]+s [(]/)) {
        r = substr(s, RSTART, RLENGTH); r = substr(r, 1, index(r, ": ") - 1); s = substr(s, RSTART + RLENGTH)
        q[r] = substr(s, index(s, ", mtime ") + 8); q[r] = "NOTIFY:quiet:" r ":" substr(q[r], 1, index(q[r], ")") - 1)
      }
    }
    $2 == "NOTIFY" && $4 == "past" && $5 == "declared" { dur = "; " substr($0, index($0, "duration: ") + 10) }
    $2 == "NOTIFY" {
      if (!dash($3)) add("NOTIFY", $3); else mark("NOTIFY")
      if (!dash($3) || !($4 == "quieter" || ($4 == "past" && $5 == "declared"))) other = 1
      if (index($0, "quieter than the declared cadence")) why = "quiet past its cadence"
      else if (index($0, "past declared duration") && why == "") why = "past its duration"
      else if (index($0, "started without its checks") && why == "") why = "started without its checks"
      next
    }
    $2 == "STANDDOWN" && $5 == "load" { add("LOAD", $3); ld = $6 " over " $8; sub(/;$/, "", ld); next }
    $2 == "STANDDOWN" { if (!dash($3)) add("STANDDOWN", $3); else mark("STANDDOWN"); next }
    $2 == "FILL" { if (!dash($3)) for (i = 3; i <= NF; i++) add("FILL", $i); else mark("FILL"); next }
    $2 == "IDLE" { mark("FILL"); next }
    $2 == "RECONCILE" { mark("RECONCILE"); next }
    END {
      if (unchanged) exit
      if ("FILL" in seen && fill != "") { n = split(fill, w, ","); for (i = 1; i <= n; i++) add("FILL", w[i]) }
      if ("NOTIFY" in seen && rows != "") {
        n = split(rows, w, ","); nq = 0; nd = 0
        for (i = 1; i <= n; i++) {
          a = (w[i] in q) ? cause(q[w[i]]) : 0; d = index(dur, "; " w[i] ": ") ? cause("NOTIFY:overdue:" w[i]) : 0
          if (a || d || (!(w[i] in q) && !index(dur, "; " w[i] ": "))) add("NOTIFY", w[i])
          nq += a; nd += d
        }
        if (nq) why = "quiet past its cadence"; else if (nd) why = "past its duration"
        if (!("NOTIFY" in subj) && !other) delete seen["NOTIFY"]
      }
      if (tf != "") { printf "" > tf; for (k in have) print k > tf; close(tf) }
      act["GATE"] = "put it to the person as a gate act; never perform it"
      act["restart"] = "tell the person: exit claude and start it again"
      act["GOAL"] = "missed; put it to the person"
      act["DUPLICATE-SESSION"] = "ListAgents and look at it; never stop it silently"
      act["DUPLICATE-START"] = "ListAgents and look at it; never stop it silently"
      act["GONE?"] = "ListAgents; close its row only if it is gone"
      act["GONE"] = "close its row with stop-orders.sh stopped"
      act["NOTIFY"] = (why == "" ? "needs a look" : why) ": ListAgents and message the agent"
      act["STANDDOWN"] = "met: TaskStop it, or keep it up with the hold verb"
      act["LOAD"] = "load " ld "; its row is pending again: TaskStop it"
      if ("LOAD" in seen && !("STANDDOWN" in subj)) delete seen["STANDDOWN"]
      act["NOT-LANDED"] = "its landing waits: read the refusal the tick prints and repair it"
      act["FILL"] = "ready with room: dispatch each row now"
      act["RECONCILE"] = "TaskList and bring the task list in line with the plan"
      k = split("GATE restart GOAL DUPLICATE-SESSION DUPLICATE-START GONE? GONE NOTIFY STANDDOWN LOAD NOT-LANDED FILL RECONCILE", order, " ")
      lead = ""; tail = ""
      for (i = 1; i <= k; i++) {
        if (!(order[i] in seen)) continue
        if (lead == "") {
          s = cap(subj[order[i]], 40)
          lead = "bionic watch: " order[i] (s == "" ? "" : " " s) " - " act[order[i]]
        } else {
          s = cap(subj[order[i]], 16)
          tail = tail (tail == "" ? "; also " : ", ") order[i] (s == "" ? "" : " " s)
        }
      }
      if (lead == "") exit
      out = ascii(lead tail)
      if (length(out) > max) out = substr(out, 1, max - 3) "..."
      print out
    }' "$1" 2>/dev/null)"
  [ -n "$line" ] || return 1
  printf '%s\n' "$line"
}

# ─── THE WATCH RECORD: WHETHER THIS SESSION IS WATCHED, AND THE WATCHER'S LOCK ──────────────────
#
# `watch-<sid>.state` in the project's tmp directory, written only by hooks/watch.sh, `key=value` lines:
#
#   state=watching   pid=<the watcher's process>   start=<its start, lib/alive.sh `alive_since`>
#   state=resting    why=<person|woke|refused|limit|cleared>
#   at=<ISO, when this state was written>          told=<the restart it already woke for, when it did>
#   lost=<the pid of a watcher that died without a word, whose record this one's claim replaced>
#   said=<the lost pid the turn-end wall has already said is gone>
#   woke=<the causes the passes have told, space-separated, in watch_wake_line's key shape>
#
# WATCHING IS A PROCESS, judged by lib/alive.sh's one rule, never by the file's age: a watcher killed from outside, or
# by the platform at its time limit, leaves `watching` naming a dead process, and `watch_state` says `stopped`. A
# watcher that ends on purpose says why first: the run waits only on the person (`person`), a wake ended it and the
# turn's end starts the next (`woke`), the tick refused its pass (`refused`), its day ran out with no agent out
# (`limit`), or its conversation was cleared and the new one starts its own (`cleared`).
#
# THE RECORD IS THE LOCK. A watcher claims it before its first pass and ends at once when a live watcher of the session
# holds it, so a session has at most one however many turn ends start one. The claim writes a whole file and links it
# into place, or renames it over a record no live watcher holds; two claims racing over one dead record can both
# rename, so the watcher asks `watch_holds` before every pass and the one the record does not name ends quietly.
# `told=` and `woke=` are carried from record to record, so a cause is told once across watchers.
watch_record_path() {  # <project root> <session-id> -> absolute path, or nothing
  [ -n "${1:-}" ] && [ -n "${2:-}" ] || return 1
  case "$2" in *[!A-Za-z0-9_-]*) return 1 ;; esac
  printf '%s/.bionic/tmp/watch-%s.state' "$1" "$2"
}

_watch_read() {  # <record> — sets _WR_STATE _WR_PID _WR_START _WR_WHY _WR_TOLD _WR_LOST _WR_SAID _WR_WOKE; rc 1 when no record
  local l
  _WR_STATE=''; _WR_PID=''; _WR_START=''; _WR_WHY=''; _WR_TOLD=''; _WR_LOST=''; _WR_SAID=''; _WR_WOKE=''
  [ -f "$1" ] && [ ! -L "$1" ] || return 1
  while IFS= read -r l; do
    case "$l" in
      state=*) _WR_STATE="${l#state=}" ;; pid=*) _WR_PID="${l#pid=}" ;; start=*) _WR_START="${l#start=}" ;;
      why=*) _WR_WHY="${l#why=}" ;; told=*) _WR_TOLD="${l#told=}" ;;
      lost=*) _WR_LOST="${l#lost=}" ;; said=*) _WR_SAID="${l#said=}" ;; woke=*) _WR_WOKE="${l#woke=}" ;;
    esac
  done < "$1"
  [ -n "$_WR_STATE" ]
}

_watch_write() {  # <record> <tmp name> <lines...> — the whole record beside it, then moved in; rc 1 not written
  local f="$1" tmp="$2"; shift 2
  [ -L "$f" ] && return 1
  printf '%s\n' "$@" > "$tmp" 2>/dev/null || { rm -f "$tmp"; return 1; }
  [ -L "$f" ] && { rm -f "$tmp"; return 1; }
  mv -f "$tmp" "$f" 2>/dev/null || { rm -f "$tmp"; return 1; }
}

# watch_state <root> <sid> -> one line and rc 0: `watching <pid> <start>` while the recorded watcher lives, `stopped
# <pid>` when the record says watching and its process is gone (or lib/alive.sh is not loaded to say), `resting <why>`;
# rc 1 and nothing when the session has no record, which is a session whose watcher never ran.
watch_state() {
  local f
  f="$(watch_record_path "${1:-}" "${2:-}")" || return 1
  _watch_read "$f" || return 1
  case "$_WR_STATE" in
    watching)
      case "$_WR_PID" in ''|*[!0-9]*) printf 'stopped %s\n' "$_WR_PID"; return 0 ;; esac
      if [ -n "$_WR_START" ] && declare -F alive_run >/dev/null 2>&1 && alive_run "$_WR_PID" "$_WR_START"; then
        printf 'watching %s %s\n' "$_WR_PID" "$_WR_START"
      else
        printf 'stopped %s\n' "$_WR_PID"
      fi ;;
    resting) printf 'resting %s\n' "${_WR_WHY:-unsaid}" ;;
    *) printf 'stopped %s\n' "$_WR_PID" ;;
  esac
}

# watch_claim <root> <sid> <pid> -> rc 0 the record names <pid>, watching; rc 1 a live watcher of the session holds it,
# `<pid> <start>` on stdout; rc 2 it could not be written. The caller has judged the directory safe to write in.
watch_claim() {
  local f d start tmp held told='' lost='' said='' woke=''
  f="$(watch_record_path "${1:-}" "${2:-}")" || return 2
  case "${3:-}" in ''|*[!0-9]*) return 2 ;; esac
  [ -L "$f" ] && return 2
  declare -F alive_since >/dev/null 2>&1 || return 2
  start="$(alive_since "$3")"
  [ -n "$start" ] || return 2
  d="${f%/*}"
  [ -d "$d" ] || mkdir -p "$d" 2>/dev/null || return 2
  tmp="$d/.watch-$2.$3"
  if held="$(watch_state "$1" "$2")"; then
    case "$held" in
      "watching $3 "*) return 0 ;;
      watching\ *) held="${held#watching }"; printf '%s\n' "$held"; return 1 ;;
    esac
    # A WATCHER THAT DIED WITHOUT A WORD IS NOT FORGOTTEN BY ITS SUCCESSOR. The turn end starts this claim and the
    # turn-end wall together, in no fixed order, so the record keeps the dead pid until that wall has said it.
    _watch_read "$f" && { told="$_WR_TOLD"; said="$_WR_SAID"; lost="$_WR_LOST"; woke="$_WR_WOKE"; }
    case "$held" in stopped\ *) lost="${held#stopped }" ;; esac
  fi
  printf 'state=watching\npid=%s\nstart=%s\nat=%s\n' "$3" "$start" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$tmp" 2>/dev/null \
    || { rm -f "$tmp"; return 2; }
  [ -z "$told" ] || printf 'told=%s\n' "$told" >> "$tmp"
  [ -z "$lost" ] || printf 'lost=%s\n' "$lost" >> "$tmp"
  [ -z "$said" ] || printf 'said=%s\n' "$said" >> "$tmp"
  [ -z "$woke" ] || printf 'woke=%s\n' "$woke" >> "$tmp"
  if [ ! -e "$f" ] && ln "$tmp" "$f" 2>/dev/null; then rm -f "$tmp"; return 0; fi
  if held="$(watch_state "$1" "$2")"; then
    case "$held" in watching\ *) rm -f "$tmp"; held="${held#watching }"; printf '%s\n' "$held"; return 1 ;; esac
  fi
  [ -L "$f" ] && { rm -f "$tmp"; return 2; }
  mv -f "$tmp" "$f" 2>/dev/null || { rm -f "$tmp"; return 2; }
  return 0
}

# watch_holds <root> <sid> <pid> -> rc 0 while the record says <pid> is watching; a watcher asks before every pass.
watch_holds() {
  local f
  f="$(watch_record_path "${1:-}" "${2:-}")" || return 1
  _watch_read "$f" && [ "$_WR_STATE" = watching ] && [ "$_WR_PID" = "${3:-}" ]
}

# watch_rest <root> <sid> <pid> <why> -> the record rewritten resting with <why>, its `told=` kept; only while it names
# <pid>, so a watcher that lost the record never overwrites the one that holds it.
watch_rest() {
  local f
  f="$(watch_record_path "${1:-}" "${2:-}")" || return 1
  watch_holds "$1" "$2" "${3:-}" || return 1
  set -- "$f" "${f%/*}/.watch-$2.$3" "state=resting" "why=${4:-unsaid}" "at=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    ${_WR_TOLD:+"told=$_WR_TOLD"} ${_WR_LOST:+"lost=$_WR_LOST"} ${_WR_SAID:+"said=$_WR_SAID"} ${_WR_WOKE:+"woke=$_WR_WOKE"}
  _watch_write "$@"
}

# watch_told <root> <sid> <pid> <key> -> `told=<key>` on the record <pid> holds: the restart it has woken for.
# watch_woke <root> <sid> <pid> <told file> -> the causes a pass left in that file (watch_wake_line), the restart's
# left out, kept on the record as `woke=`. watch_causes <root> <sid> -> the told file a pass reads: both, one a line.
watch_told() { watch_holds "${1:-}" "${2:-}" "${3:-}" || return 1; _WR_TOLD="${4:-}"; _watch_keep "$1" "$2" "$3"; }
watch_woke() {
  local w
  w="$(/usr/bin/grep -v '^restart:' "${4:-}" 2>/dev/null | LC_ALL=C sort | tr '\n' ' ')"; w="${w% }"
  watch_holds "${1:-}" "${2:-}" "${3:-}" || return 1
  [ "$w" != "$_WR_WOKE" ] || return 0
  _WR_WOKE="$w"; _watch_keep "$1" "$2" "$3"
}
_watch_keep() {  # <root> <sid> <pid> -> the watching record rewritten from the _WR_ fields watch_holds read
  local f
  f="$(watch_record_path "$1" "$2")" || return 1
  _watch_write "$f" "${f%/*}/.watch-$2.$3" "state=watching" "pid=$_WR_PID" "start=$_WR_START" \
    "at=$(date -u +%Y-%m-%dT%H:%M:%SZ)" ${_WR_TOLD:+"told=$_WR_TOLD"} ${_WR_LOST:+"lost=$_WR_LOST"} \
    ${_WR_SAID:+"said=$_WR_SAID"} ${_WR_WOKE:+"woke=$_WR_WOKE"}
}
watch_causes() {
  _watch_read "$(watch_record_path "${1:-}" "${2:-}")" || return 0
  [ -z "$_WR_TOLD" ] || printf 'restart:%s\n' "$_WR_TOLD"
  [ -z "$_WR_WOKE" ] || printf '%s\n' "$_WR_WOKE" | tr ' ' '\n'
}

# watch_told_key <root> <sid> -> the `told=` the session's record carries, or nothing.
watch_told_key() {
  local f
  f="$(watch_record_path "${1:-}" "${2:-}")" || return 0
  _watch_read "$f" && printf '%s' "$_WR_TOLD"
  return 0
}

# watch_lost <root> <sid> -> the pid of a watcher that died without a word and that the turn-end wall has not yet said,
# and rc 0; rc 1 and nothing when there is none. A record still saying watching over a dead process names it; so does a
# successor's `lost=`, which its claim kept.
watch_lost() {
  local s p
  s="$(watch_state "${1:-}" "${2:-}")" || return 1
  _watch_read "$(watch_record_path "$1" "$2")" || return 1
  case "$s" in stopped\ *) p="${s#stopped }" ;; *) p="$_WR_LOST" ;; esac
  [ -n "$p" ] && [ "$p" != "$_WR_SAID" ] || return 1
  printf '%s\n' "$p"
}

# watch_lost_said <root> <sid> <pid> -> `said=<pid>` on the record, every other line kept: the turn-end wall has said
# that watcher is gone, and no later turn end says it again.
watch_lost_said() {
  local f tmp
  f="$(watch_record_path "${1:-}" "${2:-}")" || return 1
  case "${3:-}" in ''|*[!0-9]*) return 1 ;; esac
  _watch_read "$f" || return 1
  tmp="${f%/*}/.watch-$2.said.$$"
  { /usr/bin/grep -v '^said=' "$f"; printf 'said=%s\n' "$3"; } > "$tmp" 2>/dev/null || { rm -f "$tmp"; return 1; }
  [ -L "$f" ] && { rm -f "$tmp"; return 1; }
  mv -f "$tmp" "$f" 2>/dev/null || { rm -f "$tmp"; return 1; }
}

# ─── WHETHER A DISPATCH IS WATCHED: the dispatch wall's and doctor's one reading of the record ───────────────────────
#
# watch_verdict <root> <sid> <engaged-at ISO> <transcript> -> one line, rc 0 when it admits a dispatch, rc 1 when not:
#   watching <pid> <start>   the recorded watcher lives                                   admits
#   resting <why>            it ended on purpose, and the turn's end starts the next one   admits
#   stopped <pid>            the record says watching and the process is gone              refuses
#   unstarted                no record, and no turn has ended since the session engaged    admits
#   never                    no record, and a turn has ended since it engaged              refuses
#
# NO RECORD IS NOT YET A FAULT IN THE TURN THAT ENGAGED. The watcher starts at a turn's end and at a session's start,
# and it writes nothing for a session bionic has not engaged, so the turn that engages the session has no record until
# it ends. A turn end is the platform's own transcript record, `type: system` with `subtype: stop_hook_summary`, written
# when the turn-end hooks have run; one dated after the engagement means the turn-end hook ran on an engaged session and
# started no watch. When that cannot be read (no transcript, no engagement instant, an engagement older than the scanned
# window, no jq), the answer is `never`: the wall refuses what it cannot prove watched.
#
# THE SCANNED WINDOW IS A LINE COUNT, not a clock: a long session's transcript reaches tens of megabytes, and the
# stop library reads the same 2000-line tail for a turn's facts.
PATROL_VERDICT_SCAN_LINES=2000
watch_verdict() {
  local s at tr="${4:-}" ae n out
  if s="$(watch_state "${1:-}" "${2:-}")"; then
    printf '%s\n' "$s"
    case "$s" in watching\ *|resting\ *) return 0 ;; *) return 1 ;; esac
  fi
  at="${3:-}"
  ae="$(_TIME_ISO="$at" awk "${_TIME_ISO_AWK:-}"'BEGIN { if (ENVIRON["_TIME_ISO"] == "") exit 1; e = iso2epoch(ENVIRON["_TIME_ISO"]); if (e < 0) exit 1; print e }' 2>/dev/null)" \
    || ae=""
  if [ -z "$ae" ] || [ -z "$tr" ] || [ -L "$tr" ] || [ ! -f "$tr" ] || ! command -v jq >/dev/null 2>&1; then
    printf 'never\n'; return 1
  fi
  n="$(wc -l < "$tr" 2>/dev/null | tr -d ' ')"
  out="$(tail -n "$PATROL_VERDICT_SCAN_LINES" "$tr" 2>/dev/null | jq -Rr '
      (fromjson? // null) as $r
      | if $r == null or (($r.isSidechain // false) == true) then empty
        elif $r.type == "system" and $r.subtype == "stop_hook_summary" then "E\t" + (($r.timestamp // "") | tostring)
        else "R\t" + (($r.timestamp // "") | tostring) end' 2>/dev/null \
    | awk -F'\t' -v ae="$ae" -v whole="$([ "${n:-0}" -le "$PATROL_VERDICT_SCAN_LINES" ] && echo 1 || echo 0)" \
        "${_TIME_ISO_AWK:-}"'
      { t = $2; if (substr(t, 20, 1) == ".") t = substr(t, 1, 19) "Z"; e = iso2epoch(t) }
      e >= 0 && (first == "" || e < first) { first = e }
      $1 == "E" && e > ae { ended = 1 }
      END { if (ended) print "never"; else if (!whole && (first == "" || ae < first)) print "never"; else print "unstarted" }')"
  case "$out" in unstarted) printf 'unstarted\n'; return 0 ;; esac
  printf 'never\n'; return 1
}
