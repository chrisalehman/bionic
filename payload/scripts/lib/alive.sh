# payload/scripts/lib/alive.sh — whether a session, a run or an agent is alive. One rule.
#
# THE RULE. A session or a run is alive while the process its record names is running and started
# at the recorded time: lib/slots.sh `_slots_live`, pid plus `ps -o lstart=` in the C locale and
# UTC, so a pid the OS has handed to another process since is not the one recorded. An agent runs
# inside its session's process and has none of its own, so it is alive while its session is and the
# session's transcript does not show it finished (lib/agents.sh `live_row_open`). Nothing here reads
# a file's age or existence as alive: a transcript outlives its session, and a quiet file can belong
# to a busy one.
#
# A SESSION'S RECORD. The CLI keeps one file per process, <claude home>/sessions/<pid>.json, naming
# the process (`pid`, `procStart`) and the conversation it holds now (`sessionId`). A cleared
# conversation keeps the process and rewrites that file under a new id, so the predecessor's id is
# named nowhere while the agents it dispatched still run inside the same process. So the answer keys
# on the process, not on the conversation id: `alive_note` copies the process a session id runs in to
# <claude home>/bionic/alive/<sid> while the id is current, and `alive_session` reads that copy when
# no CLI file names the id. A predecessor is alive exactly as long as its process is.
#
# THE CALLER'S OWN SESSION is alive to itself (CLAUDE_CODE_SESSION_ID): the process asking runs
# under that session's process, so the process is running whatever a claude home this process can
# read says.
#
#   alive_run <pid> <start>                 rc 0 alive (an empty start is an older record: kill -0)
#   alive_since <pid>                       -> the start a record of <pid> carries; nothing when it is gone
#   alive_session <sid>                     rc 0 alive
#   alive_sessions                          -> session=<sid>|pid=<pid>|cwd=<path>, one per live session
#   alive_note <sid>                        rc 0 when <sid>'s process is recorded; dead records go
#   alive_agent <sid> <transcript> <name>   rc 1 when <sid> is dead, else `live_row_open`'s code
#   alive_holder <sid>                      -> the pid of the CLI process whose file names <sid> now
#   alive_current <pid>                     -> the conversation the CLI process <pid> holds now
#
# BASH 3.2, jq for the CLI's files: without jq no session file is read, and only the caller's own
# session reads alive.

declare -F bionic_need >/dev/null 2>&1 || case "${BASH_SOURCE[0]}" in */*) . "${BASH_SOURCE[0]%/*}/loader.sh" ;; *) . ./loader.sh ;; esac
# Each sibling is loaded softly: one that will not load leaves its functions undefined, and sourcing this file still
# succeeds.
bionic_need slots.sh _slots_live || :
bionic_need roots.sh claude_home || :

alive_run() { _slots_live "${1:-}" "${2:-}"; }

# The writer's half of the rule: a record that names a process stores this, and alive_run compares against it.
alive_since() { _slots_since "${1:-}"; }

_alive_records() { printf '%s/bionic/alive' "$(claude_home)"; }

# _alive_cli <file> — sets _A_PID, _A_SID, _A_START and _A_CWD from one CLI session file; rc 1 when
# it names no pid or no id. The start's spacing is ps's, folded to one space the way `_slots_since`
# folds it, so a day of one digit compares equal.
_alive_cli() {
  local IFS=$' \t\n' st
  _A_PID=''; _A_SID=''; _A_START=''; _A_CWD=''
  { read -r _A_PID; read -r _A_SID; read -r st; read -r _A_CWD; } < <(jq -r \
    '(.pid // "" | tostring), (.sessionId // ""), (.procStart // ""), (.cwd // "")' "$1" 2>/dev/null)
  # shellcheck disable=SC2086
  set -- $st
  _A_START="$*"
  case "$_A_PID" in ''|*[!0-9]*) return 1 ;; esac
  [ -n "$_A_SID" ]
}

_alive_record() {  # <file> — sets _A_PID, _A_START, _A_CWD from a record alive_note wrote
  local l
  _A_PID=''; _A_START=''; _A_CWD=''
  while IFS= read -r l; do
    case "$l" in pid=*) _A_PID="${l#pid=}" ;; start=*) _A_START="${l#start=}" ;; cwd=*) _A_CWD="${l#cwd=}" ;; esac
  done < "$1"
  case "$_A_PID" in ''|*[!0-9]*) return 1 ;; esac
}

# _alive_find <sid> — rc 0 with _A_PID/_A_START/_A_CWD naming the process <sid> runs in now, from the
# CLI's own file; rc 1 when no CLI file names it.
_alive_find() {
  local f
  command -v jq >/dev/null 2>&1 || return 1
  for f in "$(claude_home)/sessions"/*.json; do
    [ -f "$f" ] || continue
    _alive_cli "$f" || continue
    [ "$_A_SID" = "$1" ] && return 0
  done
  return 1
}

# A process outlives its conversation: `/clear` rewrites the CLI's file under a new id. So a reader that must follow
# its session asks once which process holds it, and after that which conversation that process holds now.
alive_holder() {  # <sid>
  [ -n "${1:-}" ] && _alive_find "$1" || return 1
  printf '%s\n' "$_A_PID"
}
alive_current() {  # <pid>
  local f
  case "${1:-}" in ''|*[!0-9]*) return 1 ;; esac
  f="$(claude_home)/sessions/$1.json"
  command -v jq >/dev/null 2>&1 && [ -f "$f" ] && _alive_cli "$f" || return 1
  printf '%s\n' "$_A_SID"
}

alive_session() {  # <sid>
  local sid="${1:-}" rec
  [ -n "$sid" ] || return 1
  [ "$sid" = "${CLAUDE_CODE_SESSION_ID:-}" ] && return 0
  if _alive_find "$sid"; then alive_run "$_A_PID" "$_A_START"; return; fi
  rec="$(_alive_records)/$sid"
  [ -f "$rec" ] && [ ! -L "$rec" ] && _alive_record "$rec" || return 1
  [ -n "$_A_START" ] && alive_run "$_A_PID" "$_A_START"
}

# Every live session: the conversation each live process holds now, then each recorded predecessor
# whose process lives. Values are cleaned as lib/patrol.sh's line shape requires when it is loaded.
alive_sessions() {
  local f seen='|' rec sid
  if command -v jq >/dev/null 2>&1; then
    for f in "$(claude_home)/sessions"/*.json; do
      [ -f "$f" ] || continue
      _alive_cli "$f" && alive_run "$_A_PID" "$_A_START" || continue
      seen="$seen$_A_SID|"; _alive_line "$_A_SID"
    done
  fi
  for rec in "$(_alive_records)"/*; do
    [ -f "$rec" ] && [ ! -L "$rec" ] || continue
    sid="${rec##*/}"
    case "$seen" in *"|$sid|"*) continue ;; esac
    _alive_record "$rec" && [ -n "$_A_START" ] && alive_run "$_A_PID" "$_A_START" || continue
    _alive_line "$sid"
  done
}

_alive_line() {  # <sid> — one live-set line for the process in _A_PID/_A_CWD
  if declare -F _patrol_clean >/dev/null 2>&1; then
    printf 'session=%s|pid=%s|cwd=%s\n' "$(_patrol_clean "$1" 80)" "$_A_PID" "$(_patrol_clean "$_A_CWD" 300)"
  else
    printf 'session=%s|pid=%s|cwd=%s\n' "$1" "$_A_PID" "$_A_CWD"
  fi
}

# alive_note <sid> — the record a cleared conversation's predecessor is read by. Written whole to a
# sibling and moved into place; a record whose process is dead is removed as the walk passes it, so
# the directory holds one file per conversation of a running process and no more.
alive_note() {
  local sid="${1:-}" d rec tmp
  case "$sid" in ''|*/*|.|..) return 1 ;; esac
  _alive_find "$sid" && [ -n "$_A_START" ] || return 1
  d="$(_alive_records)"
  mkdir -p "$d" 2>/dev/null || return 1
  tmp="$d/.$sid.$$"
  printf 'pid=%s\nstart=%s\ncwd=%s\n' "$_A_PID" "$_A_START" "${_A_CWD//$'\n'/ }" > "$tmp" 2>/dev/null \
    && mv -f "$tmp" "$d/$sid" 2>/dev/null || { rm -f "$tmp"; return 1; }
  for rec in "$d"/*; do
    [ -f "$rec" ] && [ ! -L "$rec" ] || continue
    _alive_record "$rec" && alive_run "$_A_PID" "$_A_START" || rm -f "$rec"
  done
  return 0
}

# The transcript reader is loaded when an agent is first asked about: most callers ask about sessions.
alive_agent() {  # <sid> <transcript> <name>
  alive_session "${1:-}" || return 1
  bionic_need agents.sh live_row_open || return 4
  live_row_open "${2:-}" "${3:-}"
}
