# payload/scripts/lib/gate.sh — ONE GATE: every heavy command asks it, and it admits on the
# machine's present reading, assuming one core a command (wave-33 T1; Δ10) (epic-23
# wave-28-finished-work-lands, T2; REQ-2, REQ-4, REQ-7; spec D10, D11, D12; ADR-046).
#
# WHY IT EXISTS. The place count of lib/slots.sh was sized once from the machine and its
# waiters had no order: wave-27 ran eight writers on a machine that carries four suites, and a
# caller that timed out started again from the back. Here a request is a number the gate holds.
# Its turn survives the call that asked, and nothing is admitted on a reading that has not yet
# seen what the gate already promised.
#
# THE STORE. `${BIONIC_GATE_DIR:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/bionic/gate}`, one per
# machine, holding:
#
#   requests/<id>  one file per request, <id> a whole number: the highest number present plus one
#                  (so after a prune takes the highest away, the next ask may take it again;
#                  a live request is never pruned, so a number in use is never given twice). Lines:
#                    key=<command key>  kind=<landing|work|whole>  who=<session id>:<agent>
#                    tree=<abs path>  asked=<epoch>  holder=<pid>:<start>
#                  then, once admitted, admitted=<epoch> promise=<mem pct>:<cores>:<seconds>,
#                  and once ended, ended=<epoch> rc=<n> (rc=137 when the gate found it killed).
#                  A request returned 75 holds holder=-, nobody's. A line the gate does not know
#                  (a 1.15.0 request's peak=, anything newer) is ignored, so a later bionic may
#                  add one.
#   cost/<project>%<key>
#                  the key's recent DURATIONS, the only history the gate keeps (wave-33 T1; D4 as
#                  amended, Δ10; AC-8.6): at most three lines, newest last, <seconds>:<epoch>. A
#                  `/` in the key is written `%` in the file's name. <project> is the asking
#                  checkout's project key (`_gate_project`), so two projects' runs of one command
#                  keep separate durations. A file with no project key, which 1.15.0 and before
#                  wrote (<mem>:<cores>:<seconds>:<epoch>[:whole]), is read for its seconds only,
#                  for a key that has no keyed file, and is never written, moved or removed
#   idle           the memory reading taken the last time nothing admitted was unfinished
#   lock/          the directory lock every decision is taken under (pid and start inside)
#
# THE VERBS.
#
#   gate_ask <kind> <key> [--within <seconds>]   rc 0, the request id on stdout: admitted.
#                  rc 75 at once, nothing filed: the asking agent's budget refuses the key (THE
#                  BUDGET; its line on stderr). rc 75: the time ran out; the request is kept with its turn, nothing ran, and
#                  its holder is cleared (holder=-), so it is nobody's and passed over until the
#                  next ask by the same who for the same key resumes it. rc 2: a
#                  usage error or a store that cannot be written. It polls every
#                  ${BIONIC_GATE_POLL:-2} seconds and gives up before --within runs out;
#                  without --within it waits until admitted.
#   gate_end <id> <rc>       the run is over: writes ended= and rc=, and records its seconds
#   gate_state               share=<n> used=<n> admitted=<n> waiting=<n> landing-waiting=<n> load=<1m>/<5m> promised=<cores>
#   gate_room [--owed <n>]   rc 0 while another writer may start, rc 1 otherwise, one line:
#                            room=<yes|no> load=<1m>/<5m> cores=<n> promised=<cores> waiting=<n>
#   gate_asked               names (a who each) on stdin; prints those with an OPEN request (see
#                            THE RULES, "open"), in the order given, and is rc 0 when it printed any.
#                            One read of the store answers every name, and it takes no lock.
#   gate_share               the machine's share, 1 to 100 (absent or unreadable: 92)
#   gate_width               the workers the share has room for: floor(share × cores ÷ 100), at least 1
#                            (7 at share 92 on 8 cores); the width a whole run of tests/run.sh takes
#   gate_promise <key>       the promise for a work request for <key> asked from here,
#                            <mem>:<cores>:<seconds>, loading the store itself (see promise)
#   gate_list                one line per request: <id> <waiting|admitted|ended|killed|gone> …
#   gate_budget <kind> <key> rc 0 when the asking agent's budget admits the key (or there is no
#                            budget to hold it to); rc 75 and the budget's own line on stdout when
#                            it does not. gate_ask asks it first (THE BUDGET, below).
#
# WHICH VERBS WALK THE STORE. gate_ask, gate_end, gate_state and gate_room take the lock and run
# the scan (`_gate_scan`), which tallies the open requests, writes the end of a killed one and
# prunes (below); so gate_state and gate_room, which read, also remove. gate_list takes the lock
# and only reads. gate_asked takes no lock and only reads. Neither of those two reaps or prunes.
#
# THE KNOBS. BIONIC_GATE_POLL (seconds between a waiter's polls, default 2) and BIONIC_GATE_KEEP
# (whole seconds a request that is no longer open is kept before the next scan removes it, default
# 86400; anything else is refused to the default, with one line on stderr per process). The
# duration records are never pruned.
#
# WHAT IS PRUNED, AND WHAT "NEVER PRUNED" PROTECTED. A request nothing has ended used to be kept
# however old, so that a waiter's number and turn, and a run's record, could not be taken from
# under it. What that protected is a request somebody still holds. The live-holder rule protects
# exactly that and no more: an open request, whose holder lives, is never pruned, however old; a
# request that is not open is pruned once it is older than BIONIC_GATE_KEEP — an ended one by its
# ended=, one never admitted that nobody holds (holder=-, or its holder died) by its asked=, one
# killed unseen after the scan has written its end. Pruned in one batch, `xargs -0 rm -f`.
#
# WHO ASKS. `who` is `${CLAUDE_CODE_SESSION_ID:-none}:${BIONIC_GATE_AGENT:-main}`; the holder is
# `$$`, the process that runs the command and whose death ends its claim. The caller gives the
# command key: a suite's file name, otherwise the first 60 characters of the command.
#
# THE RULES, each taken under lock/:
#
#   alive     a request's holder is alive by the pid-and-start rule of lib/slots.sh
#             (`_slots_live`, called, not copied). Admitted, dead and never ended is killed:
#             the next locked act that reads it writes it ended=<now> rc=137, after which it
#             overlaps nothing.
#   open      (T71) ONE rule, `_gate_open`, which the scan, gate_list, gate_asked and the prune
#             all read: a request is open when it has no ended= line AND its holder is alive.
#             An open request is waiting (not admitted) or admitted; every other is ended,
#             killed, or gone (never admitted, nobody holds it). An open request counts in the
#             load and the promises and its who is showing; no other does, and none is kept
#             past BIONIC_GATE_KEEP unless its asked= (gone) or ended= (ended) is not a decimal
#             number: a file with no such number, an empty one among them, is never aged out.
#   order     among waiting requests whose holder is alive: kind=whole only when nothing
#             admitted is unfinished, then landing before work, then the lowest asked, ties by
#             id. Only the head of that order is admitted; nothing passes it.
#   memory    the live reading: _res_used_pct (while anything admitted is unfinished, the
#             larger of it and idle plus the admitted requests' memory promises, which this
#             gate makes 0) at most the share. Over the share it admits nothing.
#   processor the larger of _res_busy_cores and the admitted processor promises, plus the
#             newcomer's, at most share × cores ÷ 100 (`_gate_share_cores`) — or nothing
#             admitted is unfinished. An empty or unreadable busy reading counts as 0: the
#             promises alone decide.
#   promise   (wave-33 T1; D4 as amended, Δ10; AC-8.1) the gate does not forecast from history:
#             a request promises 0 memory and the cores its kind declares (`_gate_cores_for`):
#             a command that declares no width, work or landing, one core; a whole run the
#             width it takes, gate_width. Live load is the backstop: the readings above. The
#             seconds are the key's recorded duration (`_gate_seconds`), which the landing's
#             time limit reads (line.sh `_line_time_for`), 0 with none. While the memory
#             reading is unknown (-1) a command is admitted only when nothing admitted is
#             unfinished. A whole request admitted is admitted alone.
#   duration  at gate_end: the seconds from admitted to ended, one line in the key's keyed file.
#             A run of zero seconds has no measured time and writes none.
#   room      (wave-28 T13; D14, the owner's "Option 2") another writer may start only while
#             `_res_busy_cores` and `_res_busy_cores_5m`, each plus the processor promises of
#             admitted, unfinished requests and <owed> times one core (`_gate_cores_for work`,
#             what a writer not yet showing will be promised), are at most share × cores ÷ 100;
#             `_res_used_pct` is at most the share; and nothing waits.
#             <owed> is the caller's count of writers not yet showing: live writers that have
#             not asked the gate yet, plus the rows it has already offered on
#             this reading, so two asks on one reading give room once. A reading that cannot
#             be read (-1 or empty) gives no room unless nothing is admitted, waiting or owed.
#   time      only `_res_now`, never SECONDS or date: a planted clock moves every wait.
#   belief    BIONIC_GATE_ADMIT=<id> is believed only while that request is admitted,
#             unfinished, and held by this process or one of its ancestors. With no such id,
#             an admitted, unfinished request whose live holder is this process or one of its
#             ancestors is the admission it runs under (the lineage, wave-32 T1): it is printed
#             and nothing is filed. BIONIC_SLOT_HELD is not read at all.
#
#   budget    (wave-33 T3; D7, REQ-6 AC-6.2, AC-6.3) the ask is where a suite actually starts, so it
#             is where an agent's budget holds: see THE BUDGET, above `gate_budget`.
#
# No figure sized to a machine appears here: memory is a percentage, processor a share of the
# cores this process may use (`_res_cores`), and a command is promised one of them.
#
# BASH 3.2. No associative arrays, no `$BASHPID`, no `flock`.
#
# [WALL: tests/gate.test.sh]

_gate_self_dir() {
  local self="${BASH_SOURCE[0]}"
  case "$self" in */*) echo "${self%/*}" ;; *) echo "." ;; esac
}
_GATE_LIB_DIR="$(cd "$(_gate_self_dir)" 2>/dev/null && pwd -P)"

# The readers and the liveness rule come from their own libraries, soft-sourced as slots.sh
# sources resources.sh.
if ! type -t _res_used_pct >/dev/null 2>&1 && [ -r "$_GATE_LIB_DIR/resources.sh" ]; then
  # shellcheck disable=SC1091
  . "$_GATE_LIB_DIR/resources.sh"
fi
if ! type -t _slots_live >/dev/null 2>&1 && [ -r "$_GATE_LIB_DIR/slots.sh" ]; then
  # shellcheck disable=SC1091
  . "$_GATE_LIB_DIR/slots.sh"
fi

_GATE_KEEP_DEFAULT=86400   # seconds a request that is no longer open is kept (BIONIC_GATE_KEEP's default)
_GD=""        # the store, set by each verb
_GATE_ME=""   # the real pid of the shell taking the lock (a `$( )` subshell is not `$$`)

gate_dir() {
  printf '%s\n' "${BIONIC_GATE_DIR:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/bionic/gate}"
}

gate_share() {
  local v=''
  { read -r v < "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/bionic/share"; } 2>/dev/null
  v="${v%%[[:space:]]*}"
  case "$v" in ''|*[!0-9]*|????*) v=92 ;; esac
  v=$((10#$v))
  { [ "$v" -ge 1 ] && [ "$v" -le 100 ]; } || v=92
  printf '%s\n' "$v"
}

# _gate_share_cores — the processor room the share allows: share × cores ÷ 100, unfloored (7.36
# at share 92 on 8 cores), the cores being those this process may use (`_res_cores`). THE ONE
# SITE of that product (wave-33 T1; debt share-room): gate_width floors it, and the admission
# test (`_gate_decide`) and the room (`_gate_room_line`) compare against it as it is, so the
# three cannot drift apart.
_gate_share_cores() {
  local c
  c="$(_res_cores)"
  _res_is_uint "$c" && [ "$c" -ge 1 ] || c=1
  awk -v s="$(gate_share)" -v c="$c" 'BEGIN { printf "%.10g", s * c / 100 }'
}

# gate_width — the share's room as a whole number of workers: `_gate_share_cores` floored, at
# least 1. A whole run, admitted alone, sizes its workers from this one formula (wave-32 T2,
# D1), so no runner keeps a width of its own.
gate_width() {
  awk -v l="$(_gate_share_cores)" 'BEGIN { w = int(l); if (w < 1) w = 1; print w }'
}

# ── the lock ─────────────────────────────────────────────────────────────────

_gate_lock() {  # rc 0 holding $_GD/lock; rc 1 when it cannot be had in about ten seconds
  local lk="$_GD/lock" i=0
  _GATE_ME="$(exec sh -c 'echo "$PPID"')"
  while ! _slots_claim "$lk" "$_GATE_ME"; do
    i=$((i + 1))
    [ "$i" -lt 500 ] || return 1
    case "$(_slots_state "$lk")" in
      dead|orphan) _gate_steal "$lk" || sleep 0.02 ;;
      *) sleep 0.02 ;;
    esac
  done
}

# _gate_steal <lock> — drop a dead holder's lock, one stealer at a time: the token is made
# inside the lock, so it goes with it, and the lock is dropped only while it is still dead
# under the pid this stealer saw. A token older than a minute was left by a killed stealer.
_gate_steal() {
  local p
  p="$(_slots_pid_of "$1")"
  if ! mkdir "$1/steal" 2>/dev/null; then
    _slots_old "$1/steal" && rmdir "$1/steal" 2>/dev/null
    return 1
  fi
  if [ "$(_slots_pid_of "$1")" = "$p" ]; then
    case "$(_slots_state "$1")" in
      dead|orphan) _slots_drop "$_GD" "$1"; return 0 ;;
    esac
  fi
  rmdir "$1/steal" 2>/dev/null
  return 1
}

_gate_unlock() {
  [ "$(_slots_pid_of "$_GD/lock")" = "$_GATE_ME" ] && rm -rf "$_GD/lock"
}

# _gate_ancestor <pid>... — rc 0 when a <pid> is the process taking the lock or one of its
# ancestors; _G_ANC is the nearest one matched (the walk goes up from the process, once).
_gate_ancestor() {
  local p="$_GATE_ME" i=0 q
  _G_ANC=''
  while [ -n "$p" ] && [ "$p" -gt 1 ] && [ "$i" -lt 64 ]; do
    for q in "$@"; do
      [ "$p" = "$q" ] && { _G_ANC="$p"; return 0; }
    done
    p="$(ps -o ppid= -p "$p" 2>/dev/null)"; p="${p//[!0-9]/}"
    i=$((i + 1))
  done
  return 1
}

# ── a request ────────────────────────────────────────────────────────────────

_gate_read() {  # <file> — sets _R_<field> from its lines (a later line wins); rc 1 unreadable
  local l
  _R_key='' _R_kind='' _R_who='' _R_tree='' _R_asked='' _R_holder='' _R_admitted=''
  _R_promise='' _R_ended='' _R_rc=''
  [ -r "$1" ] || return 1
  while IFS= read -r l || [ -n "$l" ]; do
    case "$l" in
      key=*) _R_key="${l#key=}" ;;
      kind=*) _R_kind="${l#kind=}" ;;
      who=*) _R_who="${l#who=}" ;;
      tree=*) _R_tree="${l#tree=}" ;;
      asked=*) _R_asked="${l#asked=}" ;;
      holder=*) _R_holder="${l#holder=}" ;;
      admitted=*) _R_admitted="${l#admitted=}" ;;
      promise=*) _R_promise="${l#promise=}" ;;
      ended=*) _R_ended="${l#ended=}" ;;
      rc=*) _R_rc="${l#rc=}" ;;
    esac
  done < "$1"
}

_gate_alive() {  # the request last read has a live holder (holder=- is nobody)
  case "$_R_holder" in ''|-) return 1 ;; esac
  _slots_live "${_R_holder%%:*}" "${_R_holder#*:}"
}

# _gate_num <string> — rc 0 and _G_NUM the string as a decimal whole number (leading zeros are
# zeros, never octal), when it is 1 to 15 digits; rc 1 for anything else. The prune's arithmetic
# passes through it: BIONIC_GATE_KEEP, a request's asked= or ended=, and the clock. The rest under
# the lock (the request numbers) does not.
_gate_num() {
  _G_NUM=''
  case "${1:-}" in ''|*[!0-9]*|????????????????*) return 1 ;; esac
  _G_NUM=$((10#$1))
}

# _gate_open — after _gate_read: THE RULE of which requests are open (see THE RULES). rc 0 when
# the request has no ended= line and its holder lives. Sets _R_state to what the request is:
#   waiting   open, not admitted            admitted  open, admitted
#   ended     ended                         killed    ended with rc over 128 (a signal; 137 is
#                                                     the gate's own write)
#   dying     admitted, never ended, holder dead: not yet written ended (the scan does)
#   gone      never admitted, nobody holds it (holder=-, or a dead holder)
_gate_open() {
  if [ -n "$_R_ended" ]; then
    _R_state=ended
    if _gate_num "$_R_rc" && [ "$_G_NUM" -gt 128 ]; then _R_state=killed; fi
  elif _gate_alive; then
    if [ -n "$_R_admitted" ]; then _R_state=admitted; else _R_state=waiting; fi
  elif [ -n "$_R_admitted" ]; then _R_state=dying
  else _R_state=gone
  fi
  case "$_R_state" in waiting|admitted) return 0 ;; esac
  return 1
}

# _gate_reap <file> — under the lock, after _gate_read: the request was admitted, has no ended
# line and its holder is dead, so it was killed. Written ended=<now> rc=137, it overlaps nothing
# admitted after now.
_gate_reap() {
  _R_ended="$(_res_now)" _R_rc=137
  printf 'ended=%s\nrc=137\n' "$_R_ended" >> "$1"
}

_gate_holder() {  # <id> <holder> — under the lock: rewrites the request's holder line
  local f="$_GD/requests/$1"
  { grep -v '^holder=' "$f"; printf 'holder=%s\n' "$2"; } > "$_GD/requests/.$1.tmp" \
    && mv "$_GD/requests/.$1.tmp" "$f"
}

# _gate_project [<dir>] — the project key of the checkout at <dir> (default: here), eight hex
# digits (wave-33 T1; D4, AC-8.6): the POSIX `cksum` of the repository's common git directory,
# resolved, so the main checkout and every worktree of one repository are one project and keep
# one history; a directory in no repository is a project of its own. A digest, not the path: a
# fixed width keeps `<project>%<key>` within a file name's length whatever the path, and cksum
# is on every POSIX system. Two projects whose digests collide share their durations, the cost
# of a 32-bit key: the landing's time limit for a same-named suite is all such a mix moves.
_gate_project() {
  local d="${1:-}" c crc
  [ -n "$d" ] || d="$(pwd -P)"
  c="$(cd "$d" 2>/dev/null && g="$(git rev-parse --git-common-dir 2>/dev/null)" && cd "$g" 2>/dev/null && pwd -P)" || c=''
  [ -n "$c" ] || c="$(cd "$d" 2>/dev/null && pwd -P)" || c=''
  [ -n "$c" ] || c="$d"
  crc="$(printf '%s' "$c" | cksum)"; crc="${crc%%[!0-9]*}"
  printf '%08x\n' "${crc:-0}"
}

_gate_cost_file() {  # <key> <project> -> its cost file, cost/<project>%<key>
  printf '%s/cost/%s%%%s\n' "$_GD" "$2" "${1//\//%}"
}

# _gate_cores_for <kind> — the cores a request of <kind> is promised (wave-33 T1; D4 as amended,
# Δ10; AC-8.1). THE ONE SITE of the assumption: a command that declares no width (work, landing)
# takes one core; a whole run takes the width it runs at, gate_width. Nothing recorded moves it:
# the gate does not forecast from history, and live load is its backstop. The room's owed writer
# is charged `_gate_cores_for work`, so the promise and the room cannot disagree.
_gate_cores_for() {
  case "${1:-work}" in
    whole) gate_width ;;
    *)     echo 1 ;;
  esac
}

# _gate_seconds <key> <project> -> the key's recorded duration in whole seconds, the largest of
# its kept lines: the keyed file's <seconds>:<epoch> lines, else, for a key with no keyed file,
# an unkeyed 1.15.0 file's third field; 0 with neither. The landing's time limit reads it.
_gate_seconds() {
  local f
  f="$(_gate_cost_file "$1" "$2")"
  [ -s "$f" ] || f="$_GD/cost/${1//\//%}"
  [ -s "$f" ] || { echo 0; return 0; }
  awk -F: '{ v = (NF >= 3 ? $3 : $1) + 0; if (v > m) m = v } END { printf "%d\n", m }' "$f" 2>/dev/null
}

# _gate_promise <key> [<tree>] [<kind>] -> <mem>:<cores>:<seconds>: 0 memory, the cores <kind>
# declares (default work: one), and <key>'s recorded seconds in <tree>'s project (default: here).
# gate_promise <key> — the public reader the ownership table names (wave-28 T13; pass 12): the
# same answer for a work request asked from here, with the store loaded first so a caller
# outside the lock can ask.
gate_promise() {
  [ -n "${1:-}" ] || { echo "gate: usage: gate_promise <key>" >&2; return 2; }
  _gate_store || return 2
  _gate_promise "$1"
}

_gate_promise() {
  printf '0:%s:%s\n' "$(_gate_cores_for "${3:-work}")" "$(_gate_seconds "$1" "$(_gate_project "${2:-}")")"
}

# _gate_scan — under the lock: tallies the open requests (`_gate_open`). Sets
#   _G_UNF      admitted and unfinished (holder alive, no ended)   _G_WHOLE  one of them is whole
#   _G_PROM     their "<mem>:<cores>:<seconds>:<admitted>" lines
#   _G_WAIT     waiting (holder alive, not admitted)   _G_LWAIT  of them, landings
#   _G_QUEUE    their "<kind> <asked> <id> <key>" lines
# writes the end of every admitted request whose holder is dead (_gate_reap), and removes, in one batch,
# every request that is not open and is older than BIONIC_GATE_KEEP seconds (ended: by its ended=;
# gone, never admitted and nobody's: by its asked=). A number it cannot read as decimal is never
# aged out; BIONIC_GATE_KEEP that is not a whole number of seconds is refused to 86400, with one
# stderr line a process.
_gate_scan() {
  local f id keep="${BIONIC_GATE_KEEP:-$_GATE_KEEP_DEFAULT}" now='' born old=()
  if _gate_num "$keep"; then
    keep="$_G_NUM"
  else
    if [ -z "${_GATE_KEEP_SAID:-}" ]; then
      _GATE_KEEP_SAID=1
      echo "gate: BIONIC_GATE_KEEP='${keep:0:20}' is not a whole number of seconds; $_GATE_KEEP_DEFAULT is used" >&2
    fi
    keep="$_GATE_KEEP_DEFAULT"
  fi
  _G_UNF=0 _G_WHOLE=0 _G_PROM='' _G_WAIT=0 _G_LWAIT=0 _G_QUEUE=''
  for f in "$_GD"/requests/*; do
    id="${f##*/}"
    case "$id" in ''|*[!0-9]*) continue ;; esac
    _gate_read "$f" || continue
    if ! _gate_open; then
      case "$_R_state" in
        dying) _gate_reap "$f"; continue ;;
        gone) born="$_R_asked" ;;
        *) born="$_R_ended" ;;
      esac
      _gate_num "$born" || continue
      born="$_G_NUM"
      # `now` is read once, and only when a request that is not open is found.
      if [ -z "$now" ]; then
        if _gate_num "$(_res_now)"; then now="$_G_NUM"; else now=-; fi
      fi
      [ "$now" != - ] || continue
      [ "$((now - born))" -le "$keep" ] || old[${#old[@]}]="$f"
      continue
    fi
    if [ -n "$_R_admitted" ]; then
      _G_UNF=$((_G_UNF + 1))
      [ "$_R_kind" != whole ] || _G_WHOLE=1
      _G_PROM="${_G_PROM}${_R_promise}:${_R_admitted}
"
    else
      _G_WAIT=$((_G_WAIT + 1))
      [ "$_R_kind" != landing ] || _G_LWAIT=$((_G_LWAIT + 1))
      _G_QUEUE="${_G_QUEUE}${_R_kind} ${_R_asked} ${id} ${_R_key}
"
    fi
  done
  # One batch, however many: xargs cuts it to what an exec takes, and printf is a builtin.
  [ "${#old[@]}" -eq 0 ] || printf '%s\0' "${old[@]}" | xargs -0 rm -f
}

# _gate_head — the id the serve order admits next, from the last scan; nothing when none.
_gate_head() {
  printf '%s' "$_G_QUEUE" | awk -v unf="$_G_UNF" '
    NF >= 3 {
      if ($1 == "whole") { if (unf > 0) next; r = 0 }
      else r = ($1 == "landing" ? 1 : 2)
      print r, $2, $3
    }' | sort -n -k1,1 -k2,2 -k3,3 | awk 'NR == 1 { print $3 }'
}

_gate_reading() {  # the memory reading as a whole number, -1 when unknown
  local r
  r="$(_res_used_pct 2>/dev/null)"
  r="${r%%.*}"
  case "$r" in ''|*[!0-9]*) r=-1 ;; esac
  printf '%s' "$r"
}

_gate_idle() {  # <reading> — under the lock, after a scan: the idle file, kept current
  local v=''
  if [ "$_G_UNF" -eq 0 ] && [ "$1" -ge 0 ]; then
    printf '%s\n' "$1" > "$_GD/idle"
  fi
  { read -r v < "$_GD/idle"; } 2>/dev/null
  case "$v" in ''|*[!0-9.]*) v=0 ;; esac
  _G_IDLE="$v"
}

# THE READING WITHIN THE SHARE, one clause for its two readers (the collision note in the
# plan's ### T13): gate_room's memory test calls it; the admission test reads the same bound,
# `u > share`, since the gate promises no memory (wave-33 T1; Δ10).
_GATE_FITS_AWK='function fits(r, share) { return r >= 0 && r <= share }'

# gate_usage <reading> — after a scan: memory in use as the gate counts it (D11), the one owner
# of that arithmetic (spec §3; read-structure-p6 #2). The reading itself while nothing admitted
# is unfinished; the larger of the reading and idle plus the admitted memory promises while
# something is; idle plus the promises when the reading is unknown; -1 when it is unknown and
# nothing is admitted.
gate_usage() {
  printf '%s' "$_G_PROM" | awk -F: -v r="${1:--1}" -v idle="${_G_IDLE:-0}" -v unf="${_G_UNF:-0}" '
    NF >= 3 { sm += $1 }
    END {
      u = r; if (unf > 0 || r < 0) { if (idle + sm > u) u = idle + sm }
      if (r < 0 && unf == 0) u = -1
      printf "%d", u
    }'
}

# _gate_decide <id> — under the lock: rc 0 when this call admitted <id>.
_gate_decide() {
  local f="$_GD/requests/$1" reading p now
  reading="$(_gate_reading)"
  _gate_scan
  _gate_idle "$reading"
  [ "$(_gate_head)" = "$1" ] || return 1
  [ "$_G_WHOLE" -eq 0 ] || return 1
  _gate_read "$f" || return 1
  p="$(_gate_promise "$_R_key" "$_R_tree" "$_R_kind")"
  if [ "$_G_UNF" -gt 0 ]; then
    [ "$reading" -ge 0 ] || return 1
  fi
  printf '%s' "$_G_PROM" | awk -F: -v r="$reading" -v u="$(gate_usage "$reading")" -v share="$(gate_share)" \
      -v lim="$(_gate_share_cores)" -v busy="$(_res_busy_cores)" -v unf="$_G_UNF" -v p="$p" '
    NF >= 2 { sc += $2 }
    END {
      split(p, n, ":")
      if (r >= 0 && u + n[1] > share) exit 1   # memory, the live reading: the hard limit
      b = busy + 0; if (sc > b) b = sc         # processor, the soft limit
      if (unf > 0 && b + n[2] > lim) exit 1
      exit 0
    }' || return 1
  now="$(_res_now)"
  printf 'admitted=%s\npromise=%s\n' "$now" "$p" >> "$f"
  return 0
}

# _gate_enter <kind> <key> <who> — under the lock: sets _GATE_ID to the request this ask
# holds. One by the same who for the same key with no admitted line and no live holder is
# resumed, its holder rewritten; otherwise a new one takes the next number, so a live waiter's
# number is never taken over.
#
# THE LINEAGE (wave-32 T1; D5, design ledger Δ9). Before either, the same read of the store
# looks for the admission this process already runs under: an admitted, unfinished request
# whose holder is alive and is this process or one of its ancestors (_gate_ancestor's walk,
# the nearest holder winning). Then _GATE_ID is that request, _GATE_LINEAGE is 1, and nothing
# is filed or resumed: a nested runner that carries no id, or an id this store cannot believe
# (a scratch store's), is the holder's own work, and a request of its own could never be
# admitted while the ancestor's admission lives.
_gate_enter() {
  local f id max=0 holder tree now hps='' pairs='' i
  holder="$$:$(_slots_since "$$")"
  _GATE_ID='' _GATE_LINEAGE=0
  for f in "$_GD"/requests/*; do
    id="${f##*/}"
    case "$id" in ''|*[!0-9]*) continue ;; esac
    [ "$id" -le "$max" ] || max="$id"
    _gate_read "$f" || continue
    if [ -n "$_R_admitted" ]; then
      if [ -z "$_R_ended" ] && _gate_alive; then
        hps="$hps ${_R_holder%%:*}"; pairs="$pairs ${_R_holder%%:*}:$id"
      fi
      continue
    fi
    if [ -z "$_GATE_ID" ] && [ -z "$_R_ended" ] \
        && [ "$_R_who" = "$3" ] && [ "$_R_key" = "$2" ] && ! _gate_alive; then
      _GATE_ID="$id"
    fi
  done
  # shellcheck disable=SC2086  # the holder pids, one word each
  if [ -n "$hps" ] && _gate_ancestor $hps; then
    for i in $pairs; do   # one holder with two live admissions runs under the newer
      [ "${i%%:*}" = "$_G_ANC" ] || continue
      [ -n "$_GATE_ID" ] && [ "$_GATE_LINEAGE" = 1 ] && [ "${i#*:}" -lt "$_GATE_ID" ] && continue
      _GATE_ID="${i#*:}" _GATE_LINEAGE=1
    done
    return 0
  fi
  if [ -n "$_GATE_ID" ]; then
    _gate_holder "$_GATE_ID" "$holder"
    return 0
  fi
  _GATE_ID=$((max + 1))
  tree="$(git rev-parse --show-toplevel 2>/dev/null)" || tree=''
  [ -n "$tree" ] || tree="$(pwd -P)"
  now="$(_res_now)"
  printf 'key=%s\nkind=%s\nwho=%s\ntree=%s\nasked=%s\nholder=%s\n' \
    "$2" "$1" "$3" "$tree" "$now" "$holder" > "$_GD/requests/$_GATE_ID"
}

# _gate_believe <id> — under the lock: the admission passed down is this process's to use.
_gate_believe() {
  local hp
  case "$1" in ''|*[!0-9]*) return 1 ;; esac
  _gate_read "$_GD/requests/$1" || return 1
  [ -n "$_R_admitted" ] && [ -z "$_R_ended" ] || return 1
  _gate_alive || return 1
  hp="${_R_holder%%:*}"
  _gate_ancestor "$hp" || return 1
  return 0
}

_gate_store() {  # sets _GD and makes the store; rc 2, one line, when it cannot be written
  _GD="$(gate_dir)"
  if ! mkdir -p "$_GD/requests" "$_GD/cost" 2>/dev/null || [ ! -w "$_GD/requests" ]; then
    echo "gate: the store $_GD cannot be written" >&2
    return 2
  fi
}

# ── THE BUDGET, AT THE ASK (wave-33 T3; D7, REQ-6 AC-6.2, AC-6.3; ADR-052) ───────────────────
#
# WHY HERE. The Bash wall reads a command's text, and a script runs what its text cannot be made
# to say: a symlink to the runner, a variable holding its path, a capitalised spelling, a helper
# that calls it. wave-31 refused every script the wall could not read and so refused honest work
# (every in-tree script a writer edited) while passing what it could not see (a tracked symlink to
# the runner). Every suite a project's runner starts asks this gate first, so the ask is the one
# place that sees the run itself, however it was started; the budget is held here.
#
# WHO. The asking agent is the who's second half, BIONIC_GATE_AGENT: booked.sh exports it for a
# suite the wall wraps, and the wall exports it ahead of a script a budgeted agent starts (lib/
# walls.sh, the budget arm's carry). Unset or `main` is the main thread, which no budget holds.
#
# WHAT. The agent's roster row, `<project>/.bionic/tmp/roster-<session>.state`, the project being
# the asking checkout's repository (a worktree's is its main checkout's, where the roster lives),
# the row the last `roster-state/` line whose `name=` (as booked.sh spells it) or `agent_id=` is
# the agent. Its `suites_allowed=` and `re_executes=` are the budget, read as the wall reads them
# (first occurrence on the row, `none` the stated empty set, the run field percent-decoded). A
# row stating neither, or no row, holds nothing: the wall speaks for an agent no row places.
#
# THE RULE. A whole run (the key `tests/run.sh`) is admitted only when `run.sh` is in the set, as
# the wall's full-tree arm rules (a declared run never admits it). A suite key (`*.test.sh`) is
# admitted when it is in the set, or when a declared run names it as a word. Any other key (booked
# .sh's command key, a project's own runner) is not this rule's: the wall judged it. Compared
# folded where the filesystem folds (lib/cmd-class.sh `cmd_case_blind`, asked of the project).
#
# NOT JUDGED: a landing's ask (the landing proves what the plan says, not the writer's spend), and
# an admission believed from an ancestor (its own ask was judged; a nested run runs under it).
#
# REFUSED: exit 75 with one line, nothing filed and nothing run. RESIDUAL, NAMED: a suite started
# bare, by no runner, never asks, and an agent's script reached through another interpreter
# (python, node) carries no name and asks as the main thread.
_GATE_BUDGET_LINE=""
_gate_budget_read() {  # <kind> <key> -> rc 0 admitted, 1 refused (_GATE_BUDGET_LINE set)
  local kind="$1" key="$2" agent="${BIONIC_GATE_AGENT:-}" sid="${CLAUDE_CODE_SESSION_ID:-}"
  local c root roster row seg allowed="" stated=no runs="" whole=no blind=0 verdict
  _GATE_BUDGET_LINE=""
  [ "$kind" != landing ] || return 0
  case "$agent" in ''|main) return 0 ;; esac
  case "$sid" in ''|*[!A-Za-z0-9_-]*) return 0 ;; esac
  case "$key" in
    */*) case "$key" in *[!A-Za-z0-9._/-]*) return 0 ;; esac
         case "$key" in [Tt][Ee][Ss][Tt][Ss]/[Rr][Uu][Nn].[Ss][Hh]|*/[Tt][Ee][Ss][Tt][Ss]/[Rr][Uu][Nn].[Ss][Hh]) whole=yes ;; *) return 0 ;; esac ;;
    *[!A-Za-z0-9._+-]*) return 0 ;;
    *.[Tt][Ee][Ss][Tt].[Ss][Hh]|[Tt][Ee][Ss][Tt].[Ss][Hh]) : ;;
    *) return 0 ;;
  esac
  c="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || return 0
  case "$c" in
    */.git) root="${c%/.git}" ;;
    *) root="$(git rev-parse --show-toplevel 2>/dev/null)" || return 0 ;;
  esac
  roster="$root/.bionic/tmp/roster-$sid.state"
  { [ -f "$roster" ] && [ ! -L "$roster" ] && [ -r "$roster" ]; } || return 0
  row="$(GATE_BUDGET_WHO="$agent" awk '
    index($0, "roster-state/") == 1 {
      n = split($0, p, "|"); nm = ""; id = ""; hn = 0; hi = 0
      for (i = 2; i <= n; i++) {
        if (!hn && index(p[i], "name=") == 1) { nm = substr(p[i], 6); hn = 1 }
        else if (!hi && index(p[i], "agent_id=") == 1) { id = substr(p[i], 10); hi = 1 }
      }
      sn = nm; gsub(/[^A-Za-z0-9._+-]/, "_", sn)
      w = ENVIRON["GATE_BUDGET_WHO"]
      if ((nm != "" && (nm == w || sn == w)) || (id != "" && id == w)) last = $0
    }
    END { printf "%s", last }' "$roster" 2>/dev/null)"
  [ -n "$row" ] || return 0
  local _seen=" " _k _segs
  IFS='|' read -r -a _segs <<< "$row"
  for seg in "${_segs[@]}"; do
    _k="${seg%%=*}"
    [ "$_k" != "$seg" ] || continue
    case "$_seen" in *" $_k "*) continue ;; esac
    _seen="$_seen$_k "
    case "$_k" in
      suites_allowed) allowed="${seg#suites_allowed=}"; [ -z "$allowed" ] || stated=yes ;;
      re_executes)    runs="${seg#re_executes=}"; runs="${runs//\%7C/|}"; runs="${runs//\%25/%}" ;;
    esac
  done
  [ "$stated" = yes ] || [ -n "$runs" ] || return 0
  [ "$allowed" != none ] || allowed=""
  if [ "${_GATE_CB_LOADED:-}" != yes ]; then
    _GATE_CB_LOADED=no
    if ! declare -F cmd_case_blind >/dev/null 2>&1 && [ -r "$_GATE_LIB_DIR/cmd-class.sh" ]; then
      # shellcheck disable=SC1091
      . "$_GATE_LIB_DIR/cmd-class.sh" 2>/dev/null
    fi
    declare -F cmd_case_blind >/dev/null 2>&1 && _GATE_CB_LOADED=yes
  fi
  [ "$_GATE_CB_LOADED" != yes ] || ! cmd_case_blind "$root" || blind=1
  verdict="$(GATE_BUDGET_KEY="$key" GATE_BUDGET_SET="$allowed" GATE_BUDGET_RUNS="$runs" \
    awk -v whole="$whole" -v blind="$blind" 'BEGIN {
      k = ENVIRON["GATE_BUDGET_KEY"]; set = " " ENVIRON["GATE_BUDGET_SET"] " "; runs = ENVIRON["GATE_BUDGET_RUNS"]
      if (blind) { k = tolower(k); set = tolower(set); runs = tolower(runs) }
      if (whole == "yes") { print (index(set, " run.sh ") ? "ok" : "no"); exit }
      if (index(set, " " k " ")) { print "ok"; exit }
      gsub(/[`"\047]/, " ", runs); n = split(runs, W, /[ \t]+/)
      for (i = 1; i <= n; i++) { w = W[i]; sub(/.*\//, "", w); if (w == k) { print "ok"; exit } }
      print "no"
    }')"
  [ "$verdict" = no ] || return 0
  if [ "$whole" = yes ]; then
    _GATE_BUDGET_LINE="bionic: suite-run refused at the gate — a whole run is not on ${agent}'s budget; allowed: ${allowed:-(none)} (run your brief's suites; nothing ran)"
  else
    _GATE_BUDGET_LINE="bionic: suite-run refused at the gate — $key is not on ${agent}'s budget; allowed: ${allowed:-(none)}${runs:+ $runs} (run only the budgeted suites; nothing ran)"
  fi
  return 1
}

_gate_budget() {  # <kind> <key> — gate_ask's call: rc 0 admitted; 1 refused, its line on stderr
  _gate_budget_read "$1" "$2" && return 0
  printf '%s\n' "$_GATE_BUDGET_LINE" >&2
  return 1
}

gate_budget() {  # <kind> <key> -> rc 0 admitted; rc 75 refused, the budget's line on stdout
  _gate_budget_read "${1:-}" "${2:-}" && return 0
  printf '%s\n' "$_GATE_BUDGET_LINE"
  return 75
}

# ── the verbs ────────────────────────────────────────────────────────────────

gate_ask() {
  local kind="${1:-}" key="${2:-}" within='' poll="${BIONIC_GATE_POLL:-2}" start now
  local who="${CLAUDE_CODE_SESSION_ID:-none}:${BIONIC_GATE_AGENT:-main}" id='' noted=0 rc
  if [ "$#" -lt 2 ]; then
    echo "gate: usage: gate_ask <landing|work|whole> <key> [--within <seconds>]" >&2
    return 2
  fi
  shift 2
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --within) within="${2:-}"; shift 2 2>/dev/null || shift ;;
      *) echo "gate: gate_ask: unknown option $1" >&2; return 2 ;;
    esac
  done
  case "$kind" in landing|work|whole) ;; *) echo "gate: kind is landing, work or whole, not '$kind'" >&2; return 2 ;; esac
  case "$within" in *[!0-9]*) echo "gate: --within takes whole seconds, not '$within'" >&2; return 2 ;; esac
  key="${key//$'\n'/ }"
  [ -n "$key" ] || { echo "gate: gate_ask needs a command key" >&2; return 2; }
  _gate_store || return 2

  if [ -n "${BIONIC_GATE_ADMIT:-}" ] && _gate_lock; then
    _gate_believe "$BIONIC_GATE_ADMIT"; rc=$?
    _gate_unlock
    if [ "$rc" -eq 0 ]; then printf '%s\n' "$BIONIC_GATE_ADMIT"; return 0; fi
  fi
  # THE BUDGET (above): an off-budget suite or whole run is refused here, before a request is filed.
  _gate_budget "$kind" "$key" || return 75

  start="$(_res_now)"
  while :; do
    if _gate_lock; then
      if [ -z "$id" ]; then
        _gate_enter "$kind" "$key" "$who"
        if [ "$_GATE_LINEAGE" = 1 ]; then _gate_unlock; printf '%s\n' "$_GATE_ID"; return 0; fi
        id="$_GATE_ID"
      fi
      _gate_decide "$id"; rc=$?
      _gate_unlock
      if [ "$rc" -eq 0 ]; then printf '%s\n' "$id"; return 0; fi
    fi
    now="$(_res_now)"
    if [ -n "$within" ] && awk -v n="$now" -v p="$poll" -v d="$((start + within))" \
        'BEGIN { exit !(n + p > d) }'; then
      # Nobody polls it now: its holder is cleared, or a caller that lives on keeps the head.
      [ -z "$id" ] || { _gate_lock; _gate_holder "$id" -; _gate_unlock; }
      echo "gate: request ${id:-?} not admitted within ${within}s; it keeps its turn, ask again" >&2
      return 75
    fi
    if [ "$noted" -eq 0 ]; then
      echo "gate: request ${id:-?} ($kind $key) waits for its turn and room" >&2
      noted=1
    fi
    sleep "$poll"
  done
}

gate_end() {
  local id="${1:-}" rc="${2:-}" f now secs reading cf i=0
  case "$id" in ''|*[!0-9]*) echo "gate: usage: gate_end <id> <rc>" >&2; return 2 ;; esac
  case "$rc" in ''|*[!0-9]*) echo "gate: usage: gate_end <id> <rc>" >&2; return 2 ;; esac
  _gate_store || return 2
  f="$_GD/requests/$id"
  [ -f "$f" ] || { echo "gate: no request $id" >&2; return 2; }
  until _gate_lock; do
    i=$((i + 1)); [ "$i" -lt 6 ] || { echo "gate: the lock could not be had; request $id not ended" >&2; return 1; }
  done
  _gate_read "$f"
  if [ -z "$_R_admitted" ]; then
    _gate_unlock; echo "gate: request $id was never admitted" >&2; return 2
  fi
  if [ -n "$_R_ended" ]; then _gate_unlock; return 0; fi
  cf="$(_gate_cost_file "$_R_key" "$(_gate_project "$_R_tree")")"
  now="$(_res_now)"
  secs=$((now - _R_admitted)); [ "$secs" -ge 0 ] || secs=0
  printf 'ended=%s\nrc=%s\n' "$now" "$rc" >> "$f"
  # THE ONE THING LEARNED (wave-33 T1; D4 as amended, Δ10; AC-8.6): the run's seconds, in the
  # key's keyed file, newest last, three kept, for the landing's time limit. A run of zero
  # seconds (wave-32 T1; D5) has no measured time and writes none.
  if [ "$secs" -gt 0 ]; then
    { cat "$cf" 2>/dev/null
      printf '%s:%s\n' "$secs" "$now"
    } | tail -n 3 > "$_GD/cost/.new.$id" && mv "$_GD/cost/.new.$id" "$cf"
  fi
  reading="$(_gate_reading)"
  _gate_scan
  _gate_idle "$reading"
  _gate_unlock
  return 0
}

# gate_state — one line, the gate as it stands. It takes the lock and runs the scan, so it keeps
# the idle reading current, writes the end of a request found killed and prunes
# what the scan prunes; it starts and ends nothing.
gate_state() {
  local reading share used room load promised
  _gate_store || return 2
  _gate_lock || { echo "gate: the lock could not be had" >&2; return 1; }
  reading="$(_gate_reading)"
  _gate_scan
  _gate_idle "$reading"
  _gate_unlock
  share="$(gate_share)"
  used="$(gate_usage "$reading")"
  # The loads and the promised cores, as gate_room reads them with nothing owed.
  room="$(_gate_room_line "$reading" 0)"
  load="${room#* load=}"; load="${load%% *}"
  promised="${room#* promised=}"; promised="${promised%% *}"
  printf 'share=%s used=%s admitted=%s waiting=%s landing-waiting=%s load=%s promised=%s\n' \
    "$share" "$used" "$_G_UNF" "$_G_WAIT" "$_G_LWAIT" "$load" "$promised"
}

# _gate_room_line <reading> <owed> — after a scan: the room line, rc 0 when there is room.
# The loads print as read (-1 when empty); `promised` is the admitted runs' processor
# promises plus <owed> times the cores a writer not yet showing will be promised,
# `_gate_cores_for work` (wave-33 T1; Δ10: one core, whatever is on record).
_gate_room_line() {
  local b1 b5 most
  b1="$(_res_busy_cores 2>/dev/null)"; b5="$(_res_busy_cores_5m 2>/dev/null)"
  most="$(_gate_cores_for work)"
  printf '%s' "$_G_PROM" | awk -F: -v r="$1" -v owed="$2" -v b1="${b1:--1}" -v b5="${b5:--1}" \
      -v most="$most" -v share="$(gate_share)" -v lim="$(_gate_share_cores)" -v cores="$(_res_cores)" \
      -v unf="$_G_UNF" -v wait="$_G_WAIT" -v used="$(gate_usage "$1")" "$_GATE_FITS_AWK"'
    function known(v) { return v ~ /^[0-9]+(\.[0-9]+)?$/ }
    NF >= 3 { pc += $2 }
    END {
      prom = pc + owed * most
      quiet = (unf == 0 && wait == 0 && owed == 0)
      room = 1
      if (!known(b1) || !known(b5) || r < 0) { if (!quiet) room = 0 }
      if (known(b1)) { if (b1 + prom > lim) room = 0 }
      if (known(b5)) { if (b5 + prom > lim) room = 0 }
      if (r >= 0 && !fits(used, share)) room = 0
      if (wait > 0) room = 0
      printf "room=%s load=%s/%s cores=%d promised=%g waiting=%d\n", (room ? "yes" : "no"), b1, b5, cores, prom, wait
      exit !room
    }'
}

# gate_room [--owed <n>] — may another writer start now? One line, and rc 0 for yes. It takes
# the lock for its scan, so it is a sampler too: like gate_state it keeps the idle reading current, writes the end of a request found killed and prunes what the scan
# prunes, and changes nothing else.
gate_room() {
  local owed=0 reading
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --owed) owed="${2:-}"; shift 2 2>/dev/null || shift ;;
      *) echo "gate: usage: gate_room [--owed <n>]" >&2; return 2 ;;
    esac
  done
  case "$owed" in ''|*[!0-9]*) echo "gate: --owed takes a whole number, not '$owed'" >&2; return 2 ;; esac
  _gate_store || return 2
  _gate_lock || { echo "gate: the lock could not be had" >&2; return 1; }
  reading="$(_gate_reading)"
  _gate_scan
  _gate_idle "$reading"
  _gate_unlock
  _gate_room_line "$reading" "$((10#$owed))"
}

# gate_asked — names on stdin, one who per line: prints, in the order given, each that has an
# OPEN request (`_gate_open`: no ended= line and a live holder), and is rc 0 when it printed any.
# A writer with an open request is showing in the load or in a promise and is owed no longer; one
# whose request ended, or whose holder is gone, shows nowhere. It takes no lock and changes nothing.
#
# ONE awk reads the store, so the cost does not grow with the writers asked about (T52: the old
# walk forked a grep per file per name, 8 s at 600 requests under the stop wall's 10 s timeout).
# It is handed no argument list (T71: a glob of 18,000 request files failed the exec, and a file
# pruned between the glob and the read ended awk at exit 2): the paths go to its standard input
# and it opens them itself, one at a time with `getline` and `close`; a file that is gone is
# skipped, not fatal. It is a pre-filter only: it hands back the paths whose file names a who and
# whose last ended= line, as `_gate_read` takes it, is empty or absent (a file with no who names
# nobody), and the rule itself, `_gate_open`, is then read on each of those. The paths on stdin were picked over `find -print0 | xargs -0 awk` because
# one process gives one answer with nothing to fold; xargs would cut the list into several awks.
gate_asked() {
  local names cands f nm open='
' hit=1
  _GD="$(gate_dir)"
  names="$(cat)"
  set -- "$_GD"/requests/[0-9]*
  [ -e "$1" ] || return 1
  cands="$(printf '%s\n' "$@" | awk '
    { f = $0; r = (getline l < f); if (r < 0) next; ended = 0; who = 0
      while (r > 0) { if (l ~ /^ended=/) ended = (l ~ /^ended=./); else if (l ~ /^who=/) who = 1; r = (getline l < f) }
      close(f); if (who && !ended) print f }' 2>/dev/null)"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    _gate_read "$f" 2>/dev/null || continue
    if _gate_open; then open="${open}${_R_who}
"; fi
  done <<< "$cands"
  while IFS= read -r nm; do
    [ -n "$nm" ] || continue
    case "$open" in *"
$nm
"*) printf '%s\n' "$nm"; hit=0 ;; esac
  done <<< "$names"
  return $hit
}

# gate_list — one line per request, lowest id first:
#   <id> <waiting|admitted|ended|killed|gone> kind=<k> asked=<e> admitted=<e|-> ended=<e|-> rc=<n|-> key=<key>
# killed: admitted and either ended with rc over 128 (the gate's _gate_reap writes 137; a run
# killed by a signal ends 128+n) or never ended with its holder dead. gone: never admitted, no
# live holder (its number is kept for the next ask by the same who for the same key, until
# BIONIC_GATE_KEEP).
# The state is `_gate_open`'s; gate_list takes the lock and reads, and prunes and reaps nothing.
gate_list() {
  local f id st
  _gate_store || return 2
  _gate_lock || { echo "gate: the lock could not be had" >&2; return 1; }
  for f in "$_GD"/requests/*; do
    id="${f##*/}"
    case "$id" in ''|*[!0-9]*) continue ;; esac
    _gate_read "$f" || continue
    _gate_open || :
    case "$_R_state" in dying) st=killed ;; *) st="$_R_state" ;; esac
    printf '%s %s kind=%s asked=%s admitted=%s ended=%s rc=%s key=%s\n' "$id" "$st" "$_R_kind" \
      "${_R_asked:--}" "${_R_admitted:--}" "${_R_ended:--}" "${_R_rc:--}" "$_R_key"
  done | sort -n -k1,1
  _gate_unlock
}
