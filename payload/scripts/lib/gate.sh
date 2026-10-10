# payload/scripts/lib/gate.sh — ONE GATE: every heavy command asks it, and it admits on the
# machine's present reading plus its own record of what each command cost (epic-23
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
#                  A request returned 75 holds holder=-, nobody's. While admitted and unfinished it also
#                  carries peak=<pct>, the highest memory reading any locked gate read saw
#                  during the run (the plan's ruling A-orch-12). A line the gate does not know
#                  is ignored, so a later bionic may add one.
#   cost/<key>     at most three lines, newest last: <mem pct>:<cores>:<seconds>:<epoch>
#                  (a `/` in the key is written `%` in the file's name)
#   idle           the memory reading taken the last time nothing admitted was unfinished
#   lock/          the directory lock every decision is taken under (pid and start inside)
#
# THE VERBS.
#
#   gate_ask <kind> <key> [--within <seconds>]   rc 0, the request id on stdout: admitted.
#                  rc 75: the time ran out; the request is kept with its turn, nothing ran, and
#                  its holder is cleared (holder=-), so it is nobody's and passed over until the
#                  next ask by the same who for the same key resumes it. rc 2: a
#                  usage error or a store that cannot be written. It polls every
#                  ${BIONIC_GATE_POLL:-2} seconds and gives up before --within runs out;
#                  without --within it waits until admitted.
#   gate_end <id> <rc>       the run is over: writes ended= and rc=, and learns its cost
#   gate_state               share=<n> used=<n> admitted=<n> waiting=<n> landing-waiting=<n> load=<1m>/<5m> promised=<cores>
#   gate_room [--owed <n>]   rc 0 while another writer may start, rc 1 otherwise, one line:
#                            room=<yes|no> load=<1m>/<5m> cores=<n> promised=<cores> waiting=<n>
#   gate_asked               names (a who each) on stdin; prints those with an OPEN request (see
#                            THE RULES, "open"), in the order given, and is rc 0 when it printed any.
#                            One read of the store answers every name, and it takes no lock.
#   gate_share               the machine's share, 1 to 100 (absent or unreadable: 85)
#   gate_promise <key>       the per-field promise for a key, <mem>:<cores>:<seconds>, loading the
#                            store itself; nothing when no cost is on record anywhere
#   gate_list                one line per request: <id> <waiting|admitted|ended|killed|gone> …
#
# WHICH VERBS WALK THE STORE. gate_ask, gate_end, gate_state and gate_room take the lock and run
# the scan (`_gate_scan`), which tallies the open requests, writes the end of a killed one and
# prunes (below); so gate_state and gate_room, which read, also remove. gate_list takes the lock
# and only reads. gate_asked takes no lock and only reads. Neither of those two reaps or prunes.
#
# THE KNOBS. BIONIC_GATE_POLL (seconds between a waiter's polls, default 2) and BIONIC_GATE_KEEP
# (whole seconds a request that is no longer open is kept before the next scan removes it, default
# 86400; anything else is refused to the default, with one line on stderr per process). The cost
# records are what the gate learned and are never pruned.
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
#   memory    the larger of _res_used_pct and (idle + the memory promises of admitted,
#             unfinished requests), plus the newcomer's, at most the share — or nothing
#             admitted is unfinished and _res_used_pct itself is at most the share. The reading
#             is the hard limit: over the share it admits nothing; a promise alone never
#             refuses an idle gate.
#   processor the larger of _res_busy_cores and the admitted processor promises, plus the
#             newcomer's, at most share × cores ÷ 100 — or nothing admitted is unfinished.
#             An empty or unreadable busy reading counts as 0: the promises alone decide.
#   promise   the per-field maximum of cost/<key>; a command never seen is promised the
#             per-field maximum over every cost file, and with no cost file at all it is
#             admitted only when nothing admitted is unfinished. So is any command while the
#             memory reading is unknown (-1). A whole request admitted is admitted alone.
#   cost      at gate_end: seconds from admitted to ended; cores, the children's processor time
#             from the shell's own `times` over those seconds; memory, the rise from idle to
#             the run's peak, kept only when no other admission overlapped the run, otherwise
#             the previous memory value is carried. A request killed before this run was
#             admitted overlaps nothing.
#   sampling  the peak is raised only by a locked read: a waiter's poll, gate_state, gate_end.
#             A run nothing else polls is sampled only at its end, so a caller that holds a
#             long run calls `gate_state` now and then while it runs (it prints one line and
#             changes nothing but the peaks and the idle reading).
#   room      (wave-28 T13; D14, the owner's "Option 2") another writer may start only while
#             `_res_busy_cores` and `_res_busy_cores_5m`, each plus the processor promises of
#             admitted, unfinished requests and <owed> times the largest processor promise on
#             record, are at most share × cores ÷ 100; `_res_used_pct` is at most the share;
#             and nothing waits. <owed> is the caller's count of writers not yet showing: live
#             writers that have not asked the gate yet, plus the rows it has already offered on
#             this reading, so two asks on one reading give room once. With no cost on record a
#             writer not yet showing takes all the room. A reading that cannot be read (-1 or
#             empty) gives no room unless nothing is admitted, waiting or owed.
#   time      only `_res_now`, never SECONDS or date: a planted clock moves every wait.
#   belief    BIONIC_GATE_ADMIT=<id> is believed only while that request is admitted,
#             unfinished, and held by this process or one of its ancestors. BIONIC_SLOT_HELD
#             is not read at all.
#
# No figure sized to a machine appears here: memory is a percentage, processor a share of the
# cores the machine reports, and every command's cost is what it took on this machine before.
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
  case "$v" in ''|*[!0-9]*|????*) v=85 ;; esac
  v=$((10#$v))
  { [ "$v" -ge 1 ] && [ "$v" -le 100 ]; } || v=85
  printf '%s\n' "$v"
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

# _gate_ancestor <pid> — rc 0 when <pid> is the process taking the lock or one of its ancestors.
_gate_ancestor() {
  local p="$_GATE_ME" i=0
  while [ -n "$p" ] && [ "$p" -gt 1 ] && [ "$i" -lt 64 ]; do
    [ "$p" = "$1" ] && return 0
    p="$(ps -o ppid= -p "$p" 2>/dev/null)"; p="${p//[!0-9]/}"
    i=$((i + 1))
  done
  return 1
}

# ── a request ────────────────────────────────────────────────────────────────

_gate_read() {  # <file> — sets _R_<field> from its lines (a later line wins); rc 1 unreadable
  local l
  _R_key='' _R_kind='' _R_who='' _R_tree='' _R_asked='' _R_holder='' _R_admitted=''
  _R_promise='' _R_ended='' _R_rc='' _R_peak=''
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
      peak=*) _R_peak="${l#peak=}" ;;
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
# the lock (the peak test, gate_end's overlap test, the request numbers) does not.
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

_gate_cost_file() {  # <key> -> its cost file
  printf '%s/cost/%s\n' "$_GD" "${1//\//%}"
}

# _gate_promise <key> -> <mem>:<cores>:<seconds>, the per-field maximum of the key's cost
# file, else over every cost file; nothing when no cost file holds a line.
# gate_promise <key> — the public reader the ownership table names (wave-28 T13; pass 12): the
# same answer as `_gate_promise`, with the store loaded first so a caller outside the lock can ask.
gate_promise() {
  [ -n "${1:-}" ] || { echo "gate: usage: gate_promise <key>" >&2; return 2; }
  _gate_store || return 2
  _gate_promise "$1"
}

_gate_promise() {
  local f
  f="$(_gate_cost_file "$1")"
  if [ -s "$f" ]; then
    set -- "$f"
  else
    set -- "$_GD"/cost/*
    [ -e "$1" ] || return 0
  fi
  awk -F: 'NF >= 3 { for (i = 1; i <= 3; i++) if (!(i in m) || $i + 0 > m[i]) m[i] = $i + 0; n++ }
           END { if (n) printf "%g:%g:%g\n", m[1], m[2], m[3] }' "$@" 2>/dev/null
}

# _gate_scan — under the lock: tallies the open requests (`_gate_open`). Sets
#   _G_UNF      admitted and unfinished (holder alive, no ended)   _G_WHOLE  one of them is whole
#   _G_PROM     their "<mem>:<cores>:<seconds>:<admitted>" lines
#   _G_WAIT     waiting (holder alive, not admitted)   _G_LWAIT  of them, landings
#   _G_QUEUE    their "<kind> <asked> <id> <key>" lines
# raises the peak of every admitted, unfinished request to the reading <pct> it is given, writes
# the end of every admitted request whose holder is dead (_gate_reap), and removes, in one batch,
# every request that is not open and is older than BIONIC_GATE_KEEP seconds (ended: by its ended=;
# gone, never admitted and nobody's: by its asked=). A number it cannot read as decimal is never
# aged out; BIONIC_GATE_KEEP that is not a whole number of seconds is refused to 86400, with one
# stderr line a process.
_gate_scan() {
  local f id reading="${1:--1}" keep="${BIONIC_GATE_KEEP:-$_GATE_KEEP_DEFAULT}" now='' born old=()
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
      if [ "$reading" -ge 0 ] && [ "$reading" -gt "${_R_peak:--1}" ]; then
        printf 'peak=%s\n' "$reading" >> "$f"
      fi
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
# plan's ### T13): the admission test's idle-gate arm (T47) and gate_room's memory test call it.
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
  local f="$_GD/requests/$1" reading p alone=0 now
  reading="$(_gate_reading)"
  _gate_scan "$reading"
  _gate_idle "$reading"
  [ "$(_gate_head)" = "$1" ] || return 1
  [ "$_G_WHOLE" -eq 0 ] || return 1
  _gate_read "$f" || return 1
  p="$(_gate_promise "$_R_key")"
  [ -n "$p" ] || { alone=1; p="0:0:0"; }
  if [ "$_G_UNF" -gt 0 ]; then
    [ "$alone" -eq 0 ] || return 1
    [ "$reading" -ge 0 ] || return 1
  fi
  printf '%s' "$_G_PROM" | awk -F: -v r="$reading" -v u="$(gate_usage "$reading")" -v share="$(gate_share)" \
      -v cores="$(_res_cores)" -v busy="$(_res_busy_cores)" -v unf="$_G_UNF" -v p="$p" "$_GATE_FITS_AWK"'
    NF >= 2 { sc += $2 }
    END {
      split(p, n, ":")
      if (r >= 0 && !(unf == 0 && fits(r, share))) {   # memory; an idle gate: the reading alone
        if (u + n[1] > share) exit 1
      }
      b = busy + 0; if (sc > b) b = sc         # processor, the soft limit
      if (unf > 0 && b + n[2] > share * cores / 100) exit 1
      exit 0
    }' || return 1
  now="$(_res_now)"
  printf 'admitted=%s\npromise=%s\n' "$now" "$p" >> "$f"
  [ "$reading" -lt 0 ] || printf 'peak=%s\n' "$reading" >> "$f"
  return 0
}

# _gate_enter <kind> <key> <who> — under the lock: sets _GATE_ID to the request this ask
# holds. One by the same who for the same key with no admitted line and no live holder is
# resumed, its holder rewritten; otherwise a new one takes the next number, so a live waiter's
# number is never taken over.
_gate_enter() {
  local f id max=0 holder tree now
  holder="$$:$(_slots_since "$$")"
  _GATE_ID=''
  for f in "$_GD"/requests/*; do
    id="${f##*/}"
    case "$id" in ''|*[!0-9]*) continue ;; esac
    [ "$id" -le "$max" ] || max="$id"
    _gate_read "$f" || continue
    if [ -z "$_GATE_ID" ] && [ -z "$_R_admitted" ] && [ -z "$_R_ended" ] \
        && [ "$_R_who" = "$3" ] && [ "$_R_key" = "$2" ] && ! _gate_alive; then
      _GATE_ID="$id"
    fi
  done
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

  start="$(_res_now)"
  while :; do
    if _gate_lock; then
      [ -n "$id" ] || { _gate_enter "$kind" "$key" "$who"; id="$_GATE_ID"; }
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
  local id="${1:-}" rc="${2:-}" f o now secs cpu cores mem prev reading idle='' over=0 i=0
  local my_adm my_key my_peak
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
  my_adm="$_R_admitted" my_key="$_R_key" my_peak="${_R_peak:--1}"
  now="$(_res_now)"
  secs=$((now - my_adm)); [ "$secs" -ge 0 ] || secs=0
  times > "$_GD/lock/times"
  cpu="$(awk 'NR == 2 { for (i = 1; i <= 2; i++) { s = $i; sub(/s$/, "", s); split(s, a, "m"); t += a[1] * 60 + a[2] } }
              END { printf "%.2f", t + 0 }' "$_GD/lock/times")"
  cores="$(awk -v c="$cpu" -v s="$secs" 'BEGIN { if (s < 1) s = 1; printf "%.2f", c / s }')"

  # Did any other admission overlap this run? Another run overlaps when it was admitted by
  # now and had not ended by this one's admission. One never ended counts while its holder
  # lives; one whose holder is dead is written ended now (_gate_reap), so a run killed during
  # this one overlaps it and one killed before it was admitted does not (every admission
  # scans first, which wrote that one's end). Admitted the same second is overlap.
  for o in "$_GD"/requests/*; do
    case "${o##*/}" in ''|*[!0-9]*|"$id") continue ;; esac
    _gate_read "$o" || continue
    [ -n "$_R_admitted" ] || continue
    [ -n "$_R_ended" ] || _gate_alive || _gate_reap "$o"
    if [ "$_R_admitted" -eq "$my_adm" ] \
        || { [ "$_R_admitted" -le "$now" ] && { [ -z "$_R_ended" ] || [ "$_R_ended" -gt "$my_adm" ]; }; }; then
      over=1; break
    fi
  done
  reading="$(_gate_reading)"
  prev="$(tail -n 1 "$(_gate_cost_file "$my_key")" 2>/dev/null | cut -d: -f1)"
  if [ "$over" -eq 0 ] || [ -z "$prev" ]; then
    # Run alone, it was admitted when nothing else was unfinished, so `idle` still holds the
    # reading taken at its admission: the rise is its peak over that.
    { read -r idle < "$_GD/idle"; } 2>/dev/null
    mem="$(awk -v p="$my_peak" -v r="$reading" -v i="${idle:-0}" \
      'BEGIN { if (r > p) p = r; m = p - i; if (p < 0 || m < 0) m = 0; printf "%d", m }')"
  else
    mem="$prev"
  fi
  printf 'ended=%s\nrc=%s\n' "$now" "$rc" >> "$f"
  { cat "$(_gate_cost_file "$my_key")" 2>/dev/null
    printf '%s:%s:%s:%s\n' "$mem" "$cores" "$secs" "$now"
  } | tail -n 3 > "$_GD/cost/.new.$id" && mv "$_GD/cost/.new.$id" "$(_gate_cost_file "$my_key")"
  _gate_scan "$reading"
  _gate_idle "$reading"
  _gate_unlock
  return 0
}

# gate_state — one line, the gate as it stands. It takes the lock and runs the scan, so it raises
# the peaks, keeps the idle reading current, writes the end of a request found killed and prunes
# what the scan prunes; it starts and ends nothing.
gate_state() {
  local reading share used room load promised
  _gate_store || return 2
  _gate_lock || { echo "gate: the lock could not be had" >&2; return 1; }
  reading="$(_gate_reading)"
  _gate_scan "$reading"
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
# promises plus <owed> times the largest on record, or every core when nothing is on record
# and a writer is owed.
_gate_room_line() {
  local b1 b5 most
  b1="$(_res_busy_cores 2>/dev/null)"; b5="$(_res_busy_cores_5m 2>/dev/null)"
  most="$(cat "$_GD"/cost/* 2>/dev/null | awk -F: 'NF >= 3 && (!n++ || $2 + 0 > m) { m = $2 + 0 }
    END { if (n) printf "%g", m }')"
  printf '%s' "$_G_PROM" | awk -F: -v r="$1" -v owed="$2" -v b1="${b1:--1}" -v b5="${b5:--1}" \
      -v most="$most" -v share="$(gate_share)" -v cores="$(_res_cores)" -v unf="$_G_UNF" \
      -v wait="$_G_WAIT" -v used="$(gate_usage "$1")" "$_GATE_FITS_AWK"'
    function known(v) { return v ~ /^[0-9]+(\.[0-9]+)?$/ }
    NF >= 3 { pc += $2 }
    END {
      lim = share * cores / 100
      if (most == "" && owed > 0) { prom = cores; all = 1 }
      else prom = pc + owed * most
      quiet = (unf == 0 && wait == 0 && owed == 0)
      room = 1
      if (!known(b1) || !known(b5) || r < 0) { if (!quiet) room = 0 }
      if (known(b1)) { if (b1 + prom > lim) room = 0 }
      if (known(b5)) { if (b5 + prom > lim) room = 0 }
      if (r >= 0 && !fits(used, share)) room = 0
      if (all) room = 0
      if (wait > 0) room = 0
      printf "room=%s load=%s/%s cores=%d promised=%g waiting=%d\n", (room ? "yes" : "no"), b1, b5, cores, prom, wait
      exit !room
    }'
}

# gate_room [--owed <n>] — may another writer start now? One line, and rc 0 for yes. It takes
# the lock for its scan, so it is a sampler too: like gate_state it raises the peaks, keeps the
# idle reading current, writes the end of a request found killed and prunes what the scan
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
  _gate_scan "$reading"
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
