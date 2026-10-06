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
#   requests/<id>  one file per request, <id> a whole number given in turn. Lines:
#                    key=<command key>  kind=<landing|work|whole>  who=<session id>:<agent>
#                    tree=<abs path>  asked=<epoch>  holder=<pid>:<start>
#                  then, once admitted, admitted=<epoch> promise=<mem pct>:<cores>:<seconds>,
#                  and once ended, ended=<epoch> rc=<n>. While admitted and unfinished it also
#                  carries peak=<pct>, the highest memory reading the gate saw during the run.
#   cost/<key>     at most three lines, newest last: <mem pct>:<cores>:<seconds>:<epoch>
#                  (a `/` in the key is written `%` in the file's name)
#   idle           the memory reading taken the last time nothing admitted was unfinished
#   lock/          the directory lock every decision is taken under (pid and start inside)
#
# THE VERBS.
#
#   gate_ask <kind> <key> [--within <seconds>]   rc 0, the request id on stdout: admitted.
#                  rc 75: the time ran out; the request is kept and holds its turn, nothing
#                  ran, and the next ask by the same who for the same key resumes it. rc 2: a
#                  usage error or a store that cannot be written. It polls every
#                  ${BIONIC_GATE_POLL:-2} seconds and gives up before --within runs out;
#                  without --within it waits until admitted.
#   gate_end <id> <rc>       the run is over: writes ended= and rc=, and learns its cost
#   gate_state               share=<n> used=<n> admitted=<n> waiting=<n> landing-waiting=<n> clears=<minutes>
#   gate_share               the machine's share, 1 to 100 (absent or unreadable: 80)
#   gate_list                one line per request: <id> <waiting|admitted|ended|killed|gone> …
#
# WHO ASKS. `who` is `${CLAUDE_CODE_SESSION_ID:-none}:${BIONIC_GATE_AGENT:-main}`; the holder is
# `$$`, the process that runs the command and whose death ends its claim. The caller gives the
# command key: a suite's file name, otherwise the first 60 characters of the command.
#
# THE RULES, each taken under lock/:
#
#   alive     a request's holder is alive by the pid-and-start rule of lib/slots.sh
#             (`_slots_holds`, called, not copied). Admitted, dead and never ended is killed.
#   order     among waiting requests whose holder is alive: kind=whole only when nothing
#             admitted is unfinished, then landing before work, then the lowest asked, ties by
#             id. Only the head of that order is admitted; nothing passes it.
#   memory    the larger of _res_used_pct and (idle + the memory promises of admitted,
#             unfinished requests), plus the newcomer's, at most the share. It is the hard
#             limit: it holds even when nothing is admitted.
#   processor the larger of _res_busy_cores and the admitted processor promises, plus the
#             newcomer's, at most share × cores ÷ 100 — or nothing admitted is unfinished.
#   promise   the per-field maximum of cost/<key>; a command never seen is promised the
#             per-field maximum over every cost file, and with no cost file at all it is
#             admitted only when nothing admitted is unfinished. So is any command while the
#             memory reading is unknown (-1). A whole request admitted is admitted alone.
#   cost      at gate_end: seconds from admitted to ended; cores, the children's processor time
#             from the shell's own `times` over those seconds; memory, the rise from idle to
#             the run's peak, kept only when no other admission overlapped the run, otherwise
#             the previous memory value is carried.
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
if ! type -t _slots_holds >/dev/null 2>&1 && [ -r "$_GATE_LIB_DIR/slots.sh" ]; then
  # shellcheck disable=SC1091
  . "$_GATE_LIB_DIR/slots.sh"
fi

_GD=""        # the store, set by each verb
_GATE_ME=""   # the real pid of the shell taking the lock (a `$( )` subshell is not `$$`)

gate_dir() {
  printf '%s\n' "${BIONIC_GATE_DIR:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/bionic/gate}"
}

gate_share() {
  local v=''
  { read -r v < "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/bionic/share"; } 2>/dev/null
  v="${v%%[[:space:]]*}"
  case "$v" in ''|*[!0-9]*|????*) v=80 ;; esac
  v=$((10#$v))
  { [ "$v" -ge 1 ] && [ "$v" -le 100 ]; } || v=80
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

# _gate_holds <pid> <start> — under the lock: the request's holder is alive. The rule is
# lib/slots.sh's, which reads a holder's start from a directory; the probe is that directory.
_gate_holds() {
  local d="$_GD/lock/probe"
  [ -d "$d" ] || mkdir "$d" 2>/dev/null
  if [ -n "${2:-}" ]; then printf '%s\n' "$2" > "$d/since"; else rm -f "$d/since"; fi
  _slots_holds "$d" "$1"
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

_gate_alive() {  # the request last read has a live holder
  _gate_holds "${_R_holder%%:*}" "${_R_holder#*:}"
}

_gate_cost_file() {  # <key> -> its cost file
  printf '%s/cost/%s\n' "$_GD" "${1//\//%}"
}

# _gate_promise <key> -> <mem>:<cores>:<seconds>, the per-field maximum of the key's cost
# file, else over every cost file; nothing when no cost file holds a line.
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

# _gate_scan — under the lock: tallies the live requests. Sets
#   _G_UNF      admitted and unfinished (holder alive, no ended)   _G_WHOLE  one of them is whole
#   _G_PROM     their "<mem>:<cores>:<seconds>:<admitted>" lines
#   _G_WAIT     waiting (holder alive, not admitted)   _G_LWAIT  of them, landings
#   _G_QUEUE    their "<kind> <asked> <id> <key>" lines
# and raises the peak of every admitted, unfinished request to the reading <pct> it is given.
_gate_scan() {
  local f id reading="${1:--1}"
  _G_UNF=0 _G_WHOLE=0 _G_PROM='' _G_WAIT=0 _G_LWAIT=0 _G_QUEUE=''
  for f in "$_GD"/requests/*; do
    id="${f##*/}"
    case "$id" in ''|*[!0-9]*) continue ;; esac
    _gate_read "$f" || continue
    [ -z "$_R_ended" ] || continue
    _gate_alive || continue
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
  printf '%s' "$_G_PROM" | awk -F: -v r="$reading" -v idle="$_G_IDLE" -v share="$(gate_share)" \
      -v cores="$(_res_cores)" -v busy="$(_res_busy_cores)" -v unf="$_G_UNF" -v p="$p" '
    NF >= 2 { sm += $1; sc += $2 }
    END {
      split(p, n, ":")
      if (r >= 0) {                            # memory, the hard limit
        u = r; if (idle + sm > u) u = idle + sm
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
# holds. One by the same who for the same key with no admitted line is resumed, its holder
# rewritten; otherwise a new one takes the next number.
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
        && [ "$_R_who" = "$3" ] && [ "$_R_key" = "$2" ]; then
      _GATE_ID="$id"
    fi
  done
  if [ -n "$_GATE_ID" ]; then
    f="$_GD/requests/$_GATE_ID"
    { grep -v '^holder=' "$f"; printf 'holder=%s\n' "$holder"; } > "$_GD/requests/.$_GATE_ID.tmp" \
      && mv "$_GD/requests/.$_GATE_ID.tmp" "$f"
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
  # now and had not ended by this one's admission; one never ended (still running, or killed
  # at a moment nobody saw) is taken as still running. Admitted the same second is overlap.
  for o in "$_GD"/requests/*; do
    case "${o##*/}" in ''|*[!0-9]*|"$id") continue ;; esac
    _gate_read "$o" || continue
    [ -n "$_R_admitted" ] || continue
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

gate_state() {
  local reading share used clears now w k s p
  _gate_store || return 2
  _gate_lock || { echo "gate: the lock could not be had" >&2; return 1; }
  reading="$(_gate_reading)"
  _gate_scan "$reading"
  _gate_idle "$reading"
  share="$(gate_share)"
  now="$(_res_now)"
  # The waiting requests' promises, so the clearing time counts what is still to come.
  w=''
  while read -r s s p k; do
    [ -n "$p" ] || continue
    w="${w}$(_gate_promise "$k")
"
  done <<EOF
$_G_QUEUE
EOF
  _gate_unlock
  set -- $(printf '%s---\n%s' "$_G_PROM" "$w" | awk -F: -v r="$reading" -v idle="$_G_IDLE" \
      -v unf="$_G_UNF" -v share="$share" -v now="$now" '
    $0 == "---" { waiting = 1; next }
    NF >= 3 && !waiting { sm += $1; left = $4 + $3 - now; if (left < 0) left = 0; mt += $1 * left }
    NF >= 3 && waiting  { mt += $1 * $3 }
    END {
      u = r; if (unf > 0 || r < 0) { if (idle + sm > u) u = idle + sm }
      if (r < 0 && unf == 0) u = -1
      room = share - idle; if (room < 1) room = 1
      c = mt / room / 60; ci = int(c); if (c > ci) ci++
      printf "%d %d\n", u, ci
    }')
  used="${1:--1}" clears="${2:-0}"
  printf 'share=%s used=%s admitted=%s waiting=%s landing-waiting=%s clears=%s\n' \
    "$share" "$used" "$_G_UNF" "$_G_WAIT" "$_G_LWAIT" "$clears"
}

# gate_list — one line per request, lowest id first:
#   <id> <waiting|admitted|ended|killed|gone> kind=<k> asked=<e> admitted=<e|-> ended=<e|-> rc=<n|-> key=<key>
# killed: admitted, never ended, holder dead. gone: never admitted, holder dead (its number is
# kept for the next ask by the same who for the same key).
gate_list() {
  local f id st
  _gate_store || return 2
  _gate_lock || { echo "gate: the lock could not be had" >&2; return 1; }
  for f in "$_GD"/requests/*; do
    id="${f##*/}"
    case "$id" in ''|*[!0-9]*) continue ;; esac
    _gate_read "$f" || continue
    if [ -n "$_R_ended" ]; then st=ended
    elif _gate_alive; then
      if [ -n "$_R_admitted" ]; then st=admitted; else st=waiting; fi
    elif [ -n "$_R_admitted" ]; then st=killed
    else st=gone
    fi
    printf '%s %s kind=%s asked=%s admitted=%s ended=%s rc=%s key=%s\n' "$id" "$st" "$_R_kind" \
      "${_R_asked:--}" "${_R_admitted:--}" "${_R_ended:--}" "${_R_rc:--}" "$_R_key"
  done | sort -n -k1,1
  _gate_unlock
}
