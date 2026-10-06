# payload/scripts/lib/slots.sh — THE LIVENESS RULE: is a recorded holder still the process that
# claimed what it holds (epic-23 wave-26-never-idle, D8; cut to this at wave-28 T12, D10).
#
# WHAT IS LEFT, AND WHY. Until wave-28 this file handed out N machine-wide places and waited for
# one; lib/gate.sh replaced the count, the take loop and the wait (T12), and what remains is what
# the gate, the busy check and the landing line still call: the pid-and-start rule, the directory
# claim the gate's lock is built on, and the take-over of a dead holder's claim the line's publish
# lock uses. Nothing here waits for room, and nothing here is sized to a machine.
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
#   _slots_take_one <store> <dir> <pid> [<what>]   claim <dir>, reclaiming a dead holder once
#                               (under <store>/.reap: _slots_reap, _slots_lock, _slots_steal)
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

# THE TAKE-OVER OF A DEAD HOLDER'S CLAIM (kept at wave-28 T12 for lib/line.sh's publish lock, which
# takes its lock with `_slots_take_one`). RECLAIMING IS SERIALISED; CLAIMING IS NOT. Two reclaimers
# that both saw one dead holder must not both remove the directory, or the second removes the one
# the first just claimed. So the check-and-remove runs under the store's `.reap/` (held for
# microseconds), and a lock left by a dead reclaimer is stolen one stealer at a time
# (`.reap.steal.<pid>`, see _slots_steal), so a stale lock never lets two in (review 4 F1).
_slots_lock_stale() {  # <lock> <its pid, or nothing> — rc 0 when its holder is dead or it is old
  { [ -n "$2" ] && ! _slots_alive "$2"; } || _slots_old "$1"
}
# _slots_steal <store> <the stale lock's pid, or nothing> — drop a stale reap lock, one
# stealer at a time; rc 0 when this call dropped it. Reading the lock's dead pid and then
# dropping the lock is check-then-act: two stealers that both read it would each drop a
# lock, the second dropping the one the first had just taken, and both would reap the same
# place (review 4 F1). So a stealer first takes `.reap.steal.<pid>` (mkdir: one wins) and,
# under it, drops the lock only while it is still that stale lock. A lock changes hands only
# through a stealer of its pid, and those take turns. A token older than the orphan line was
# left by a stealer killed inside its microseconds, and is cleared.
_slots_steal() {
  local tok="$1/.reap.steal.${2:-none}" rc=1
  if ! mkdir "$tok" 2>/dev/null; then
    _slots_old "$tok" && _slots_drop "$1" "$tok"
    return 1
  fi
  if [ "$(_slots_pid_of "$1/.reap")" = "${2:-}" ] && _slots_lock_stale "$1/.reap" "${2:-}"; then
    _slots_drop "$1" "$1/.reap"; rc=0
  fi
  rmdir "$tok" 2>/dev/null
  return "$rc"
}
_slots_lock() {  # <store> — the reap lock; rc 1 if it cannot be had in about two seconds
  local lk="$1/.reap" i=0 p
  while ! mkdir "$lk" 2>/dev/null; do
    i=$((i + 1))
    [ "$i" -lt 100 ] || return 1
    p="$(_slots_pid_of "$lk")"
    if _slots_lock_stale "$lk" "$p" && _slots_steal "$1" "$p"; then
      continue
    fi
    sleep 0.02
  done
  printf '%s\n' "$$" > "$lk/pid"
  return 0
}
_slots_reap() {  # <store> <place> — rc 0 when a dead or orphaned place was removed
  local rc=1
  case "$(_slots_state "$2")" in dead|orphan) : ;; *) return 1 ;; esac
  _slots_lock "$1" || return 1
  case "$(_slots_state "$2")" in
    dead|orphan) _slots_drop "$1" "$2"; rc=0 ;;
  esac
  rm -rf "$1/.reap"
  return "$rc"
}
_slots_take_one() {  # <store> <place> <pid> [<what>] — claim, reclaiming a dead holder once
  _slots_claim "$2" "$3" "${4:-}" && return 0
  _slots_reap "$1" "$2" && _slots_claim "$2" "$3" "${4:-}"
}
