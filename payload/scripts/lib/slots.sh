# payload/scripts/lib/slots.sh — THE LIVENESS RULE: is a recorded holder still the process that
# claimed what it holds (epic-23 wave-26-never-idle, D8; cut to this at wave-28 T12, D10).
#
# WHAT IS LEFT, AND WHY. Until wave-28 this file handed out N machine-wide places and waited for
# one; lib/gate.sh replaced the count, the take loop and the wait (T12), and what remains is what
# the gate and the busy check still call: the pid-and-start rule and the directory claim the
# gate's lock is built on. Nothing here waits, and nothing here is sized to a machine.
#
# THE RULE. A holder is recorded as its pid and its start time (`ps -o lstart=`, C locale, UTC).
# It holds while that pid lives AND started at that time, so a pid the OS has since handed to
# another process does not hold (T36, review 4 F2). A record with no start (written by an older
# bionic) falls back to `kill -0`. A claim directory with no pid yet is a claim in progress, left
# alone unless it is older than a minute, which only a claimer killed between `mkdir` and its pid
# write leaves behind.
#
# THE PRIMITIVE IS mkdir (bash 3.2, and no flock on macOS): of two claimers racing for one
# directory exactly one creates it. A removal is a `mv` to a scratch name first, so a reader sees
# the whole directory or none of it.
#
#   _slots_since <pid>          that process's start, one space between fields; nothing when gone
#   _slots_live <pid> <start>   rc 0 while <pid> lives and started at <start> (the rule)
#   _slots_holds <dir> <pid>    rc 0 while <pid> lives and is the process that claimed <dir>
#   _slots_state <dir>          free | live | taking | dead | orphan
#   _slots_claim <dir> <pid> [<what>]   rc 0 when this call created <dir> (since, then pid)
#   _slots_drop <store> <dir>   remove <dir> whole: rename first, then delete
#   _slots_pid_of, _slots_alive, _slots_old   the readers the four above share
#
# BASH 3.2. No associative arrays, no `$BASHPID`, no `flock`.
#
# [WALL: tests/slots.test.sh]
# [WALL: tests/gate.test.sh]

SLOTS_ORPHAN_MIN=1   # a claim with no pid this many minutes old was left by a killed claimer
_SLOTS_SINCE=""; _SLOTS_SINCE_PID=""

_slots_pid_of() {  # <dir> -> the pid recorded in <dir>/pid, or nothing
  local p=''
  # Braced: a file removed between a test and the read would print the redirect's error.
  { read -r p < "$1/pid"; } 2>/dev/null
  case "$p" in ''|*[!0-9]*) p='' ;; esac
  printf '%s' "$p"
}

_slots_alive() {  # <pid> — rc 0 while that process exists
  [ -n "${1:-}" ] && kill -0 "$1" 2>/dev/null
}

# _slots_since <pid> -> when that process started, one space between fields; nothing when
# it is gone. The C locale and UTC make it the same string whoever asks.
_slots_since() {
  local s
  s="$(LC_ALL=C TZ=UTC0 ps -o lstart= -p "$1" 2>/dev/null)"
  # shellcheck disable=SC2086
  set -- $s
  printf '%s' "$*"
}

# _slots_live <pid> <start> — THE RULE ITSELF: rc 0 while <pid> lives AND started at <start>,
# so a pid the OS handed to another process since is not the holder (review 4 F2). An empty
# <start> (a record from an older bionic) is `kill -0` alone; a ps that cannot answer leaves it
# live. A gate request records its holder as `<pid>:<start>`, and the landing's busy check reads
# it through this (wave-28 T12).
_slots_live() {
  local now
  _slots_alive "$1" || return 1
  [ -n "${2:-}" ] || return 0
  now="$(_slots_since "$1")"
  [ -z "$now" ] || [ "$now" = "$2" ]
}

# _slots_holds <dir> <pid> — rc 0 while <pid> is the live process that claimed <dir>: the rule,
# with the start read from <dir>/since.
_slots_holds() {
  local s=''
  { read -r s < "$1/since"; } 2>/dev/null
  _slots_live "$2" "$s"
}

_slots_old() {  # <dir> — rc 0 when it is older than SLOTS_ORPHAN_MIN minutes
  [ -n "$(find "$1" -maxdepth 0 -mmin +"$SLOTS_ORPHAN_MIN" 2>/dev/null)" ]
}

_slots_state() {  # <dir> -> free | live | taking | dead | orphan
  local p
  [ -d "$1" ] || { printf 'free'; return 0; }
  p="$(_slots_pid_of "$1")"
  if [ -n "$p" ]; then
    if _slots_holds "$1" "$p"; then printf 'live'; else printf 'dead'; fi
  elif _slots_old "$1"; then
    printf 'orphan'
  else
    printf 'taking'
  fi
}

_slots_claim() {  # <dir> <pid> [<what>] — rc 0 when this call created <dir>
  local place="$1"
  # The holder's start is read once per pid, before the mkdir, to keep the claim short.
  if [ "$_SLOTS_SINCE_PID" != "$2" ]; then
    _SLOTS_SINCE="$(_slots_since "$2")"; _SLOTS_SINCE_PID="$2"
  fi
  mkdir "$place" 2>/dev/null || return 1
  # The start before the pid: whoever reads the pid finds the start beside it.
  [ -z "$_SLOTS_SINCE" ] || printf '%s\n' "$_SLOTS_SINCE" > "$place/since"
  printf '%s\n' "$2" > "$place/pid"
  [ -z "${3:-}" ] || printf '%s\n' "$3" > "$place/what"
  return 0
}

_slots_drop() {  # <store> <dir> — remove <dir> whole: rename first, then delete
  local gone="$1/.gone.$$.$RANDOM"
  if mv "$2" "$gone" 2>/dev/null; then
    rm -rf "$gone"
  fi
}
