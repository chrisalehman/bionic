# payload/scripts/lib/slots.sh — MACHINE-WIDE PLACES: a suite run books one of N, and a
# timing check books them all (epic-23 wave-26-never-idle, D8; REQ-6 AC-6.3, AC-6.4).
#
# WHY IT EXISTS. The real load on a machine running agents is suite runs, and nothing
# counted them across sessions: each run sized itself from its own view and a timing check
# ran beside whatever else was running (research R6 §3 — hook-timeout red at load ~8.6 on 8
# cores, "from OTHER agents"). A place is booked just before a run starts and given back
# when it ends, so a run waits only when the machine is actually full.
#
# THE STORE. `${BIONIC_SLOTS_DIR:-$HOME/.claude/bionic/slots}`, one per machine, holding:
#
#   place.<i>/pid    a held place, i in 1..N; `pid` is the holder, `what` names its command
#   place.<i>/since  when the holder started (`ps -o lstart=`), written before `pid`
#   place.<i>/lent   the pid of a nested whole-machine take that lent this place (below)
#   quiet/pid        the whole-machine marker; while it is held no new place is handed out
#   .reap/           a short lock taken only to reclaim a dead holder's place
#
# It is under `$HOME`, not `CLAUDE_CONFIG_DIR`: one count for every session on the machine,
# where a store per Claude profile would hand out N places per profile (review 4, A1).
# The count is `${BIONIC_SLOTS_N:-<suites from resources_budget>}`.
#
# THE PRIMITIVE IS mkdir (bash 3.2, and no flock on macOS). `mkdir` is atomic: of two
# takers racing for one place exactly one creates it. The holder then writes its start time
# and its pid. A place is held while that pid lives AND started at that time: a pid the OS
# has since handed to another process does not hold it (T36, review 4 F2). A place with no
# `since` (claimed by an older bionic) falls back to `kill -0`. A place with no pid yet is a
# take in progress and is left alone, unless it is older than a minute, which only a taker
# killed between `mkdir` and its pid write leaves behind. Every take reaps every dead place
# it can see, not only the one it found taken, so a dead place never lingers behind a free one.
#
# RECLAIMING IS SERIALISED; TAKING IS NOT. Two reclaimers that both saw one dead holder must
# not both remove the place, or the second removes the place the first just took. So the
# check-and-remove runs under `.reap/` (held for microseconds), and a removal is a `mv` to a
# scratch name first, so a reader sees the whole place or none of it. A plain take of a free
# place never touches the lock. A lock left by a dead reclaimer is stolen one stealer at a
# time (`.reap.steal.<pid>`, see _slots_steal), so a stale lock never lets two in (F1).
#
# THE WHOLE-MACHINE TAKE (slots_take_all). Take the marker first, which stops new shared
# takes; then take every free place and wait for the held ones to drain. A shared take
# re-reads the marker AFTER its mkdir and gives the place back if a marker appeared, so no
# take completes after the marker was taken.
#
# NESTING. `BIONIC_SLOT_HELD=1` marks a command already inside a place: `slots_take` takes
# nothing for it, so a run never waits on its own parent. `slots_take_all` from inside a
# held place waits for the OTHER places only — the parent's (`BIONIC_SLOT_PLACE`, or, when
# that is not set, any one place) is left alone. Two such nested takes would each wait for
# the other's parent place forever, and a plain whole-machine take would wait forever for
# a parent whose child is queued behind its marker; so a nested take, WHILE IT WAITS FOR THE
# MARKER, LENDS its parent's place (`lent` holds its pid) and a drain counts a place lent by
# a live pid as drained. The lender is idle while it waits, so the machine really is quiet.
# `BIONIC_SLOT_QUIET=1` marks a command inside a whole-machine hold: both takes are no-ops.
#
#   slots_dir                      the store path
#   slots_count                    N
#   slots_take [<pid> [<what>]]    one place; prints its path and sets SLOTS_TAKEN; waits
#   slots_take_all [<pid> [<what>]]  the marker and every place; waits
#   slots_release [<pid>]          every place, marker and lend <pid> holds
#
# <pid> defaults to `$$`: the process that stays alive for the whole run, whose death frees
# what it holds. Both takes return 1 at the maximum wait, after one stderr line naming the
# holders; slots_take_all gives back what it took first.
#
# A STORE THAT CANNOT BE WRITTEN (T36, review 4 F5) is found before any wait, and both takes
# return 2 at once. Booking manages throughput; it is not a guard. So slots_take says
# nothing and leaves the choice to its caller (booked.sh runs the command unbooked, with one
# line that says so), while slots_take_all prints one line naming the store: a timing check
# taken without the machine is worth nothing, so a whole-machine take refuses.
#
# THE KNOBS, each with a ceiling so a test can never hang:
#
#   BIONIC_SLOTS_POLL      seconds between looks while waiting        default 1 (decimals ok)
#   BIONIC_SLOTS_MAX_WAIT  seconds before a wait gives up             default 1200
#   BIONIC_SLOTS_NOTE_S    seconds between "still waiting" lines      default 60
#
# ONE CEILING FOR A CALLER'S WAITS (T36, review 4 F3). A caller that waits more than once —
# booked.sh: the marker, the drain, the settle, every void retry — sets SLOTS_DEADLINE once,
# to `$SECONDS + max`, and every wait here gives up at it rather than starting its own.
# Unset, each take's waits share one ceiling of their own, as before.
#
# WHAT IT DOES NOT GUARANTEE. Exclusion holds among takers only: a session on an older
# bionic, an unengaged one, or a terminal takes no place. A holder killed with SIGKILL runs
# no trap: its place is reclaimed by the next taker, but a command it left running keeps
# running.
#
# BASH 3.2. No associative arrays, no `$BASHPID`, no `flock`.
#
# [WALL: tests/slots.test.sh]

_slots_self_dir() {
  local self="${BASH_SOURCE[0]}"
  case "$self" in */*) echo "${self%/*}" ;; *) echo "." ;; esac
}
_SLOTS_LIB_DIR="$(cd "$(_slots_self_dir)" 2>/dev/null && pwd -P)"

# The count's default is resources_budget's `suites`; a caller that has not loaded
# resources.sh gets it here, the soft-source idiom lib/roots.sh uses for lib/root.sh.
if ! command -v resources_budget >/dev/null 2>&1 && [ -r "$_SLOTS_LIB_DIR/resources.sh" ]; then
  # shellcheck disable=SC1091
  . "$_SLOTS_LIB_DIR/resources.sh"
fi

SLOTS_ORPHAN_MIN=1   # a place with no pid this many minutes old was left by a killed taker
SLOTS_TAKEN=""
SLOTS_DEADLINE=""    # a $SECONDS value every wait of this caller gives up at (see THE KNOBS)
_SLOTS_SINCE=""; _SLOTS_SINCE_PID=""

slots_dir() {
  printf '%s\n' "${BIONIC_SLOTS_DIR:-$HOME/.claude/bionic/slots}"
}

slots_count() {
  local n="${BIONIC_SLOTS_N:-}" probe cores mem disk
  case "$n" in ''|*[!0-9]*) n='' ;; esac
  if [ -n "$n" ] && [ "$n" -ge 1 ]; then
    printf '%s\n' "$n"
    return 0
  fi
  n=''
  if command -v resources_probe >/dev/null 2>&1; then
    probe="$(resources_probe 2>/dev/null | tr ' ' '\n')"
    cores="$(printf '%s\n' "$probe" | sed -n 's/^cores=//p')"
    mem="$(printf '%s\n' "$probe" | sed -n 's/^mem_gb=//p')"
    disk="$(printf '%s\n' "$probe" | sed -n 's/^disk_free_gb=//p')"
    n="$(resources_budget "$cores" "$mem" "$disk" 2>/dev/null | tr ' ' '\n' | sed -n 's/^suites=//p')"
  fi
  case "$n" in ''|*[!0-9]*) n=1 ;; esac
  [ "$n" -ge 1 ] || n=1
  printf '%s\n' "$n"
}

_slots_poll() {
  case "${BIONIC_SLOTS_POLL:-}" in
    ''|*[!0-9.]*|*.*.*|.) printf '1' ;;
    *) printf '%s' "$BIONIC_SLOTS_POLL" ;;
  esac
}
_slots_max_wait() {
  case "${BIONIC_SLOTS_MAX_WAIT:-}" in
    ''|*[!0-9]*) printf '1200' ;;
    *) printf '%s' "$BIONIC_SLOTS_MAX_WAIT" ;;
  esac
}
_slots_note_s() {
  case "${BIONIC_SLOTS_NOTE_S:-}" in
    ''|*[!0-9]*|0) printf '60' ;;
    *) printf '%s' "$BIONIC_SLOTS_NOTE_S" ;;
  esac
}

# _slots_deadline <max> — the $SECONDS value a wait starting now gives up at: the caller's
# SLOTS_DEADLINE when it set one for all its waits together, else now + <max>.
_slots_deadline() {
  case "${SLOTS_DEADLINE:-}" in
    ''|*[!0-9]*) printf '%s' "$((SECONDS + $1))" ;;
    *) printf '%s' "$SLOTS_DEADLINE" ;;
  esac
}

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

# _slots_holds <dir> <pid> — rc 0 while <pid> lives AND is the process that claimed <dir>:
# a pid the OS handed to another process since does not hold it (review 4 F2).
_slots_holds() {
  local s='' now
  _slots_alive "$2" || return 1
  { read -r s < "$1/since"; } 2>/dev/null
  [ -n "$s" ] || return 0        # claimed by an older bionic: kill -0 is all there is
  now="$(_slots_since "$2")"
  [ -z "$now" ] || [ "$now" = "$s" ]   # a ps that cannot answer leaves it held
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

_slots_claim() {  # <place> <pid> [<what>] — rc 0 when this call created the place
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

_slots_drop() {  # <store> <dir> — remove a place whole: rename first, then delete
  local gone="$1/.gone.$$.$RANDOM"
  if mv "$2" "$gone" 2>/dev/null; then
    rm -rf "$gone"
  fi
}

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

_slots_who() {  # <dir> -> "pid <p> (<what>)"
  local p w=''
  p="$(_slots_pid_of "$1")"
  { read -r w < "$1/what"; } 2>/dev/null
  printf 'pid %s' "${p:-?}"
  [ -z "$w" ] || printf ' (%s)' "$w"
}

_slots_quiet_blocks() {  # <store> <self pid> — rc 0 when another live take holds the machine
  local d="$1"
  case "$(_slots_state "$d/quiet")" in
    free) return 1 ;;
    live) [ "$(_slots_pid_of "$d/quiet")" = "$2" ] && return 1; return 0 ;;
    taking) return 0 ;;
    *) _slots_reap "$d" "$d/quiet"; return 1 ;;
  esac
}

_slots_lent_live() {  # <place> — rc 0 when a live nested take has lent this place
  local p=''
  { read -r p < "$1/lent"; } 2>/dev/null
  case "$p" in ''|*[!0-9]*) return 1 ;; esac
  _slots_alive "$p"
}

_slots_holders() {  # <store> <self pid> -> "pid 1 (a), pid 2 (b)" for every live holder
  local d="$1" f out='' s
  for f in "$d/quiet" "$d"/place.*; do
    [ -d "$f" ] || continue
    [ "$(_slots_pid_of "$f")" = "$2" ] && continue
    s="$(_slots_state "$f")"
    case "$s" in live|taking) : ;; *) continue ;; esac
    if [ "$f" = "$d/quiet" ]; then
      out="${out:+$out, }the whole machine by $(_slots_who "$f")"
    else
      out="${out:+$out, }$(_slots_who "$f")"
    fi
  done
  printf '%s' "${out:-nobody it can name}"
}

# _slots_note <text> — the waiting line: once at the start of a wait, then
# once every BIONIC_SLOTS_NOTE_S. Reads and moves _SLOTS_NOTED, which each wait resets.
# _slots_note_due answers whether it would print now, so a caller builds an expensive line
# (the holders) only then: `_slots_note_due && _slots_note "… $(_slots_holders …)"`.
_SLOTS_NOTED=-1
_slots_note_due() {
  [ "$_SLOTS_NOTED" -lt 0 ] || [ $((SECONDS - _SLOTS_NOTED)) -ge "$(_slots_note_s)" ]
}
_slots_note() {
  if _slots_note_due; then
    printf 'slots: %s\n' "$1" >&2
    _SLOTS_NOTED=$SECONDS
  fi
}

_slots_store_ok() {  # <store> — rc 0 when the store exists (made if need be) and can be written
  mkdir -p "$1" 2>/dev/null && [ -w "$1" ] && [ -x "$1" ]
}

_slots_sweep() {  # <store> — reap every dead place, so none lingers behind a free one (F2)
  local f
  for f in "$1"/place.*; do
    [ -d "$f" ] || continue
    _slots_reap "$1" "$f" || :
  done
}

slots_take() {
  local pid="${1:-$$}" what="${2:-}" d n i place start poll max deadline
  SLOTS_TAKEN=""
  if [ "${BIONIC_SLOT_HELD:-}" = 1 ] || [ "${BIONIC_SLOT_QUIET:-}" = 1 ]; then
    return 0
  fi
  d="$(slots_dir)"
  _slots_store_ok "$d" || return 2     # silent: the caller says what it does unbooked
  n="$(slots_count)"
  poll="$(_slots_poll)"; max="$(_slots_max_wait)"
  deadline="$(_slots_deadline "$max")"; start=$((deadline - max)); _SLOTS_NOTED=-1
  _slots_sweep "$d"
  while :; do
    if ! _slots_quiet_blocks "$d" "$pid"; then
      i=1
      while [ "$i" -le "$n" ]; do
        place="$d/place.$i"
        if _slots_take_one "$d" "$place" "$pid" "$what"; then
          if _slots_quiet_blocks "$d" "$pid"; then
            _slots_drop "$d" "$place"     # a whole-machine take began meanwhile
            break
          fi
          SLOTS_TAKEN="$place"
          printf '%s\n' "$place"
          return 0
        fi
        i=$((i + 1))
      done
    fi
    if [ "$SECONDS" -ge "$deadline" ]; then
      printf 'slots: gave up after %ss with no place free — held by %s\n' \
        "$((SECONDS - start))" "$(_slots_holders "$d" "$pid")" >&2
      return 1
    fi
    _slots_note_due && _slots_note "waiting for a place — all $n held by $(_slots_holders "$d" "$pid")"
    sleep "$poll"
  done
}

slots_take_all() {
  local pid="${1:-$$}" what="${2:-}" d n i f place start poll max deadline own='' allow=0 left who
  SLOTS_TAKEN=""
  [ "${BIONIC_SLOT_QUIET:-}" = 1 ] && return 0
  d="$(slots_dir)"
  if ! _slots_store_ok "$d"; then
    printf 'slots: cannot write the store %s, so the whole machine cannot be taken and a timing result would mean nothing — fix: make it writable, or point BIONIC_SLOTS_DIR at a directory you can write\n' "$d" >&2
    return 2
  fi
  n="$(slots_count)"
  poll="$(_slots_poll)"; max="$(_slots_max_wait)"
  if [ "${BIONIC_SLOT_HELD:-}" = 1 ]; then
    own="${BIONIC_SLOT_PLACE:-}"
    case "$own" in "$d"/place.*) [ -d "$own" ] || own='' ;; *) own='' ;; esac
    [ -n "$own" ] || allow=1
  fi
  deadline="$(_slots_deadline "$max")"; start=$((deadline - max)); _SLOTS_NOTED=-1

  # The marker. A nested take lends its parent's place while it waits here.
  [ -z "$own" ] || printf '%s\n' "$pid" > "$own/lent"
  until _slots_take_one "$d" "$d/quiet" "$pid" "$what"; do
    if [ "$SECONDS" -ge "$deadline" ]; then
      [ -z "$own" ] || rm -f "$own/lent"
      printf 'slots: gave up after %ss waiting for the whole machine — held by %s\n' \
        "$((SECONDS - start))" "$(_slots_holders "$d" "$pid")" >&2
      return 1
    fi
    _slots_note_due && _slots_note "waiting for the whole machine — held by $(_slots_holders "$d" "$pid")"
    sleep "$poll"
  done
  [ -z "$own" ] || rm -f "$own/lent"

  # The drain: take every free place, and wait out the held ones.
  while :; do
    i=1
    while [ "$i" -le "$n" ]; do
      place="$d/place.$i"
      [ "$place" = "$own" ] || _slots_take_one "$d" "$place" "$pid" "$what" || :
      i=$((i + 1))
    done
    left=0; who=''
    for f in "$d"/place.*; do
      [ -d "$f" ] || continue
      [ "$f" = "$own" ] && continue
      [ "$(_slots_pid_of "$f")" = "$pid" ] && continue
      case "$(_slots_state "$f")" in
        free) continue ;;
        dead|orphan) _slots_reap "$d" "$f"; continue ;;
      esac
      _slots_lent_live "$f" && continue
      left=$((left + 1))
      who="${who:+$who, }$(_slots_who "$f")"
    done
    if [ "$left" -le "$allow" ]; then
      SLOTS_TAKEN="$d/quiet"
      printf '%s\n' "$d/quiet"
      return 0
    fi
    if [ "$SECONDS" -ge "$deadline" ]; then
      slots_release "$pid"
      printf 'slots: gave up after %ss waiting for the places to drain — held by %s\n' \
        "$((SECONDS - start))" "$who" >&2
      return 1
    fi
    _slots_note "holding the whole machine, waiting for $left place(s) to drain — held by $who"
    sleep "$poll"
  done
}

slots_release() {
  local pid="${1:-$$}" d f p
  d="$(slots_dir)"
  [ -d "$d" ] || return 0
  for f in "$d"/place.* "$d/quiet"; do
    [ -d "$f" ] || continue
    if [ "$(_slots_pid_of "$f")" = "$pid" ]; then
      _slots_drop "$d" "$f"
      continue
    fi
    p=''
    { read -r p < "$f/lent"; } 2>/dev/null
    [ "$p" = "$pid" ] && rm -f "$f/lent"
  done
  return 0
}
