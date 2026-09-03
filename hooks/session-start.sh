#!/bin/bash
# SESSION-START — what the previous conversation left on this project, and nothing
# else (bionic 1.4.0, spec AC-1; AC-4's "the SessionStart block runs the report";
# AC-11's legacy-symlink listing; plan slice SSTART).
#
# WHAT `/clear` ACTUALLY DOES, measured (probe record, .bionic/docs/record/
# wave-1.4.0-probe.md). The process does not restart: same pid, same
# `sessions/<pid>.json` rewritten in place, and the session id re-keyed in every
# channel at once — env, hook payload and pid file all move together (A-probe-1/2/3).
# So the old conversation's state does not go anywhere either. What is left beside
# the new session's own files is:
#
#   a ROSTER with open rows       agents the predecessor dispatched, still running,
#                                 filed under a session id nothing now answers to.
#                                 `/clear` does not kill agents.
#   a PATROL STAMP under the old sid — the predecessor's clock, which the new
#                                 session's arming does not touch or replace.
#   a LIVE PREDECESSOR CRON       A-probe-4: a recurring job created before the
#                                 `/clear` is STILL LISTED afterwards and STILL
#                                 FIRES into the new conversation, carrying the old
#                                 session's marker. It is a duplicate, not a ghost,
#                                 and it must be DELETED before a new one is made.
#   a LEGACY `.bionic` SYMLINK    `<repo>/.worktrees/<x>/.bionic -> <repo>/.bionic`,
#                                 planted by older spawn-worktree.sh runs. Design
#                                 ledger C2 retired it: a second path to one state.
#
# None of that announces itself, and every one of them reads as normal until a
# dispatch or a stop goes to the wrong address. This hook is the announcement.
#
# IT IS A DETECTOR, NOT A REPAIR. It arms nothing, deletes nothing, adopts nothing
# and writes nothing — not one byte, including under `.bionic/tmp`. The re-arm
# line it prints is an instruction for the model reading it, and the ORDER in that
# line is the whole point: CronList BEFORE CronCreate, because a predecessor job
# that is still firing has to be deleted rather than raced (AC-3's ritual, S5).
# `tests/session-start.test.sh` fingerprints the `.bionic` subtree before and after
# every drive; a hook that stamped would satisfy the arming wall over a cron table
# holding nothing, which is worse than the state it reports.
#
# FAIL OPEN, ALWAYS EXIT 0. A SessionStart hook that refuses would block the start
# of every conversation on this machine, and what it is protecting is a report.
# A missing library, no jq, an unparsable payload, no session key, no project root:
# each of those is a silent exit 0. `.claude/rules/hook-authoring.md` — a detector
# never arms and never blocks.
#
# STDOUT IS THE DELIVERY MECHANISM. A SessionStart hook's stdout is added to the
# new conversation's context, so the block below is written to be read by the model
# that is about to act, not by a terminal. It prints ONLY when there is something
# to report: a clean `startup` on a project with no predecessor state produces no
# output at all, because a block that prints every session is a block nobody reads.
#
# Registered once, in hooks/hooks.json, on SessionStart with matcher
# `startup|clear|resume|compact` — pinned by tests/cross-gate-agreement.test.sh §L.

set -u

BIONIC_LIB_WANT="root.sh session.sh patrol.sh"
# --- bionic-loader/v2 BEGIN
# Find the bionic library. This text is pasted BYTE-IDENTICALLY into every hook; a
# library cannot load itself, so the duplication is the design and
# tests/cross-gate-agreement.test.sh pins every copy against `bionic_loader_pin` in
# payload/scripts/lib/loader.sh. Behaviour: tests/loader.test.sh.
#
# CONTRACT. Set BIONIC_LIB_WANT to the space-separated basenames this hook sources,
# on a line above this block. Afterwards exactly one of these is non-empty:
#   BIONIC_LIB          a readable directory holding every wanted basename
#   BIONIC_LIB_MISSING  the library this hook wanted and did not get
# BIONIC_LIB_CANDS always lists, in order, every location that was tried.
#
# CANDIDATES. Later classes are evaluated only after the earlier ones fail, so a
# healthy hook pays nothing for the healing path — not a jq, not a registry read.
#  (1) beside the hook. TWO SPELLINGS OF ONE DIRECTORY, because the shipped tree has
#      two real shapes: the installed plugin root, where hooks/ and scripts/ are
#      siblings, and the repo, where payload/hooks is a symlink to the top-level
#      hooks/ and the library lives under payload/scripts/lib. "$0" is textual and
#      `..` is resolved by the kernel AFTER the symlink, so the first spelling alone
#      would find nothing in a directory-source session.
#  (2) the marketplace SOURCE TREE. installed_plugins.json names the marketplace this
#      plugin was installed from; that marketplace's source.path in
#      known_marketplaces.json is the tree. The marketplace is read, never assumed:
#      a fork installs under its own name.
#  (3) the newest version directory in that marketplace's plugin cache, by
#      THREE-INTEGER compare — 1.10.0 beats 1.3.2, which a lexical sort gets backwards.
# (2) and (3) heal a partial breakage: one location damaged, a sibling intact. An
# upstream-broken publish breaks every location equally and is not covered.
#
# TESTS OVERRIDE THE MACHINE, never the reverse. BIONIC_PLUGINS_DIR (default
# "$HOME/.claude/plugins") is the only door to the registry and the cache.
BIONIC_LIB=""; BIONIC_LIB_MISSING=""; BIONIC_LIB_CANDS=""
_bl_dir="$(dirname "$0")"
_bl_want="${BIONIC_LIB_WANT:-}"
_bl_try() {
  [ -n "${1:-}" ] || return 1
  if [ -z "$BIONIC_LIB_CANDS" ]; then BIONIC_LIB_CANDS="$1"; else BIONIC_LIB_CANDS="$BIONIC_LIB_CANDS, $1"; fi
  [ -d "$1" ] || return 1
  for _bl_f in $_bl_want; do [ -r "$1/$_bl_f" ] || return 1; done
  BIONIC_LIB="$1"
}
if ! _bl_try "$_bl_dir/../scripts/lib" && ! _bl_try "$_bl_dir/../payload/scripts/lib"; then
  _bl_pd="${BIONIC_PLUGINS_DIR:-${HOME:-/nonexistent}/.claude/plugins}"
  _bl_mk=""
  if [ -r "$_bl_pd/installed_plugins.json" ]; then
    # First key only, and the prefix stripped by parameter expansion rather than
    # `sed | head`: the block's only external commands are `dirname` and `jq`, and
    # `jq` runs with its stderr closed, so a machine missing jq degrades to
    # BIONIC_LIB_MISSING in silence instead of printing a shell diagnostic.
    _bl_keys="$(jq -r '(.plugins // {}) | keys[] | select(startswith("bionic@"))' "$_bl_pd/installed_plugins.json" 2>/dev/null)"
    _bl_mk="${_bl_keys%%
*}"
    _bl_mk="${_bl_mk#bionic@}"
  fi
  if [ -n "$_bl_mk" ]; then
    _bl_src=""
    if [ -r "$_bl_pd/known_marketplaces.json" ]; then
      _bl_src="$(jq -r --arg mk "$_bl_mk" '.[$mk].source.path // empty' "$_bl_pd/known_marketplaces.json" 2>/dev/null)"
    fi
    if [ -n "$_bl_src" ]; then _bl_try "$_bl_src/payload/scripts/lib" || :; fi
    if [ -z "$BIONIC_LIB" ]; then
      _bl_best=""; _bl_bestk=""
      for _bl_v in "$_bl_pd/cache/$_bl_mk/bionic"/*; do
        [ -d "$_bl_v" ] || continue
        _bl_n="${_bl_v##*/}"
        case "$_bl_n" in ''|*[!0-9.]*) continue ;; esac
        _bl_x1=""; _bl_x2=""; _bl_x3=""
        IFS=. read -r _bl_x1 _bl_x2 _bl_x3 _bl_rest <<BIONIC_LOADER_VER
$_bl_n
BIONIC_LOADER_VER
        _bl_k="$(printf '%05d%05d%05d' "$((10#${_bl_x1:-0}))" "$((10#${_bl_x2:-0}))" "$((10#${_bl_x3:-0}))" 2>/dev/null)" || continue
        if [ -z "$_bl_bestk" ] || [ "$_bl_k" \> "$_bl_bestk" ]; then _bl_bestk="$_bl_k"; _bl_best="$_bl_n"; fi
      done
      if [ -n "$_bl_best" ]; then _bl_try "$_bl_pd/cache/$_bl_mk/bionic/$_bl_best/scripts/lib" || :; fi
    fi
  fi
fi
if [ -z "$BIONIC_LIB" ]; then
  # The name in the message is the first library this hook asked for. A candidate
  # directory qualifies only when it holds ALL of them, so with none qualifying the
  # first wanted name is the honest thing to hand the reader.
  BIONIC_LIB_MISSING="${_bl_want%% *}"
  [ -n "$BIONIC_LIB_MISSING" ] || BIONIC_LIB_MISSING="scripts/lib"
fi
# FAIL OPEN — for every hook whose work is advisory or reversible. One line, then
# stand aside. Blocking reversible work because a file is missing buys no safety and
# costs the session.
loader_fail_open() {
  echo "$1: library ${BIONIC_LIB_MISSING:-the bionic library} not found at ${BIONIC_LIB_CANDS:-(no candidate)} — hook stepping aside; run /bionic:doctor" >&2
  exit 0
}
# FAIL CLOSED — for a wall over an irreversible action. Refuse, but never lock the
# user out of the repair: four commands are permitted by WHOLE-STRING match, checked
# here, before the hook sources anything. Whole-string and not prefix, so
# `claude plugin update bionic@bionic; git push origin main` is refused like any
# other push. There is no env-var override: a variable an agent turn can set on
# itself is not a wall.
loader_fail_closed() {
  _bl_root="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd -P)" || _bl_root=""
  [ -n "$_bl_root" ] || _bl_root="$(dirname "$0")/.."
  case "${2:-}" in
    "claude plugin update bionic@bionic"|\
    "claude plugin install bionic@bionic"|\
    "bash $_bl_root/scripts/doctor.sh"|\
    "bash $_bl_root/scripts/setup.sh") exit 0 ;;
  esac
  cat >&2 <<BIONIC_LOADER_REFUSE
BLOCKED: $1 cannot load its library (${BIONIC_LIB_MISSING:-the bionic library}), so it
cannot read this command. A wall that cannot read a command refuses it rather than
waving it through.

Looked in: ${BIONIC_LIB_CANDS:-(no candidate)}

Until the plugin is whole again this wall permits exactly four commands, each matched
as a whole string:

    claude plugin update bionic@bionic
    claude plugin install bionic@bionic
    bash $_bl_root/scripts/doctor.sh
    bash $_bl_root/scripts/setup.sh

Anything else is refused, including one of those four with another command chained
after it. Run one of them, or act from your own terminal.
BIONIC_LOADER_REFUSE
  exit 2
}
# --- bionic-loader/v2 END

# The library, or nothing. `loader_fail_open` prints one stderr line and exits 0 —
# a detector that cannot read the disk reports nothing rather than guessing.
[ -n "$BIONIC_LIB" ] || loader_fail_open "session-start"
. "$BIONIC_LIB/root.sh"    || exit 0   # project_root
. "$BIONIC_LIB/session.sh" || exit 0   # session_id, and its one divergence warning
. "$BIONIC_LIB/patrol.sh"  || exit 0   # PATROL_STALE_MULTIPLIER, _patrol_claude_home

# The tree this hook was launched from — printed absolute in the re-arm line, and
# the tree whose poker is asked for the interval. `$(dirname "$0")/..` and `pwd -P`
# rather than `realpath`, which stock macOS does not ship (L-LOADER/5, L-ROOT/2).
HOOK_ROOT="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd -P)" || HOOK_ROOT=""
[ -n "$HOOK_ROOT" ] || HOOK_ROOT="$(dirname "$0")/.."

# ---------------------------------------------------------------- the payload
INPUT=""
[ -t 0 ] || INPUT="$(cat)"

pfield() {  # <jq path> -> the field, or empty
  command -v jq >/dev/null 2>&1 || return 0
  printf '%s' "$INPUT" | jq -r "$1 // empty" 2>/dev/null
}
SOURCE="$(pfield .source)"
PAYLOAD_SID="$(pfield .session_id)"
CWD="$(pfield .cwd)"
[ -n "$CWD" ] && [ -d "$CWD" ] || CWD="${CLAUDE_PROJECT_DIR:-$PWD}"
[ -d "$CWD" ] || CWD="$PWD"

# ---------------------------------------------------------------- the project
# One root, from the one owner (spec §3). A `.bionic` that is a SYMLINK is never a
# root (ledger C2) — which is exactly the legacy link this hook reports further
# down, so a worktree carrying one resolves to the main checkout and reports the
# main checkout's state, not a second copy of it.
ROOT="$(project_root "$CWD" 2>/dev/null)" || ROOT=""
[ -n "$ROOT" ] || exit 0
[ -d "$ROOT/.bionic" ] && [ ! -L "$ROOT/.bionic" ] || exit 0
TMP="$ROOT/.bionic/tmp"

# ---------------------------------------------------------------- the three channels
#
# The env value is primary and the other two are witnesses (lib/session.sh, ledger
# S2). All three are PRINTED regardless, because the whole reason this line exists
# is that a reader cannot otherwise tell an agreement from a coincidence — and the
# probe's finding that they agree on a plain `/clear` is a measurement of one CLI
# build, not a guarantee.
ENV_SID="${CLAUDE_CODE_SESSION_ID:-}"
PID_SID=""
PIDFILE="$(_patrol_claude_home)/sessions/$PPID.json"
if [ -f "$PIDFILE" ] && [ ! -L "$PIDFILE" ] && command -v jq >/dev/null 2>&1; then
  PID_SID="$(jq -r '.sessionId // empty' "$PIDFILE" 2>/dev/null)"
fi

# The current session id, through the one function every other reader calls. Its
# stderr warning on a divergent payload is deliberately NOT suppressed: that line
# is the L-SESSION contract, and this hook is one of the twelve readers.
CUR="$(session_id "$PAYLOAD_SID")" || CUR=""

AGREE="agree"
_first=""
for _v in "$ENV_SID" "$PAYLOAD_SID" "$PID_SID"; do
  [ -n "$_v" ] || continue
  if [ -z "$_first" ]; then _first="$_v"; continue; fi
  [ "$_v" = "$_first" ] || AGREE="DIVERGE"
done

# ---------------------------------------------------------------- predecessor rosters
#
# OPEN ROWS ARE COUNTED BY NAME, not by line: the roster is append-only and one
# dispatch writes a row per status transition (`intended`, `identified`,
# `confirmed`), so counting lines would multiply every agent by however far it got.
# A name is CLOSED when the landing gate journalled a `landing-swept/v1|…|state=MET`
# marker for it, or when the sweeper's ledger carries an `ack` for it — the same
# two discharges `adopt_fold` in hooks/session-poker.sh applies, mirrored here
# rather than shelled out to, because slice POKER owns that file and this hook must
# read the same disk with or without its `--report-only` verb.
open_rows() {  # <roster file> <ack ledger file|""> -> a count
  awk -v ackfile="$2" '
    function kv(line, key,   n, a, i, eq, k) {
      n = split(line, a, "|")
      for (i = 1; i <= n; i++) {
        eq = index(a[i], "=")
        if (eq == 0) continue
        k = substr(a[i], 1, eq - 1)
        if (k == key) return substr(a[i], eq + 1)
      }
      return ""
    }
    BEGIN {
      if (ackfile != "") {
        while ((getline l < ackfile) > 0) {
          if (l !~ /^sweeper-ledger\/v1\|/) continue
          if (kv(l, "event") != "ack") continue
          an = kv(l, "name"); if (an != "") acked[an] = 1
        }
        close(ackfile)
      }
    }
    /^roster-state\/v1\|/ { n = kv($0, "name"); if (n != "") seen[n] = 1; next }
    /^landing-swept\/v1\|/ {
      n = kv($0, "name")
      if (n != "" && kv($0, "state") == "MET") met[n] = 1
      next
    }
    END {
      c = 0
      for (n in seen) { if (n in met) continue; if (n in acked) continue; c++ }
      print c
    }
  ' "$1" 2>/dev/null
}

sid8() { printf '%.8s' "${1:-}"; }

ROSTERS=""
for RF in "$TMP"/roster-*.state; do
  [ -f "$RF" ] || continue
  [ -L "$RF" ] && continue        # symlinks are not followed, as everywhere in tmp
  OSID="${RF##*/}"; OSID="${OSID#roster-}"; OSID="${OSID%.state}"
  [ -n "$OSID" ] || continue
  if [ -n "$CUR" ] && [ "$OSID" = "$CUR" ]; then continue; fi
  LEDGER="$TMP/sweeper-$OSID.state"
  if [ ! -f "$LEDGER" ] || [ -L "$LEDGER" ]; then LEDGER=""; fi
  N="$(open_rows "$RF" "$LEDGER")"
  case "$N" in ''|*[!0-9]*) continue ;; esac
  [ "$N" -gt 0 ] || continue
  ROSTERS="${ROSTERS}  $(sid8 "$OSID") — $N open row(s) — ${RF##*/}
"
done

# ---------------------------------------------------------------- predecessor stamps
#
# THE INTERVAL COMES FROM THE POKER BESIDE THIS HOOK, by the same two-step
# lib/patrol.sh's `patrol_interval` takes — the project's configured value, then
# the script's built-in default, then the last resort. It is asked HERE rather than
# through `patrol_interval` because that function resolves the poker through
# `_detect_plugin_root`, i.e. the plugin installed on the machine, while a
# SessionStart hook must measure against the tree it was actually launched from.
ss_interval() {
  local poker="$HOOK_ROOT/hooks/session-poker.sh" s=""
  if [ -f "$poker" ]; then
    s="$( cd "$ROOT" 2>/dev/null && bash "$poker" interval 2>/dev/null )"
    case "$s" in ''|*[!0-9]*) s="" ;; esac
    if [ -z "$s" ]; then
      s="$( bash "$poker" interval-default 2>/dev/null )"
      case "$s" in ''|*[!0-9]*) s="" ;; esac
    fi
  fi
  if [ -z "$s" ] || [ "$s" -le 0 ]; then s="$PATROL_INTERVAL_LAST_RESORT"; fi
  printf '%s' "$s"
}

STAMPS=""
LIMIT=$(( $(ss_interval) * PATROL_STALE_MULTIPLIER ))
NOW="$(date -u +%s 2>/dev/null || echo 0)"
for SF in "$TMP"/patrol-*.state; do
  [ -f "$SF" ] || continue
  [ -L "$SF" ] && continue
  OSID="${SF##*/}"; OSID="${OSID#patrol-}"; OSID="${OSID%.state}"
  [ -n "$OSID" ] || continue
  if [ -n "$CUR" ] && [ "$OSID" = "$CUR" ]; then continue; fi
  MT="$(stat -f %m "$SF" 2>/dev/null || stat -c %Y "$SF" 2>/dev/null)"
  case "$MT" in ''|*[!0-9]*) continue ;; esac
  AGE=$(( NOW - MT )); [ "$AGE" -ge 0 ] || AGE=0
  if [ "$AGE" -gt "$LIMIT" ]; then STATE="stale"; else STATE="fresh"; fi
  STAMPS="${STAMPS}  $(sid8 "$OSID") — ${AGE}s old (stale past ${LIMIT}s) — $STATE
"
done

# ---------------------------------------------------------------- legacy symlinks
LINKS=""
for LN in "$ROOT"/.worktrees/*/.bionic; do
  [ -L "$LN" ] || continue
  LINKS="${LINKS}  ${LN#"$ROOT"/} -> $(readlink "$LN" 2>/dev/null)
"
done

# ---------------------------------------------------------------- the block
#
# SILENCE IS THE DEFAULT. Four findings and one verdict; if every finding is empty
# and the three channels agree, there is nothing a reader could act on and the hook
# says nothing at all.
if [ -z "$ROSTERS" ] && [ -z "$STAMPS" ] && [ -z "$LINKS" ] && [ "$AGREE" = "agree" ]; then
  exit 0
fi

# The title line names the subject and the source, because this text lands in a
# context window with no attribution: without it the model sees a bare `session-id:`
# line and cannot tell which tool said it or why.
printf 'bionic session-start (source: %s) — state the previous conversation left on this project.\n' \
  "${SOURCE:-unknown}"
printf 'session-id: env=%s payload=%s pidfile=%s — %s\n' \
  "${ENV_SID:-absent}" "${PAYLOAD_SID:-absent}" "${PID_SID:-absent}" "$AGREE"
if [ -n "$ROSTERS" ]; then
  printf 'predecessor rosters:\n%s' "$ROSTERS"
fi
if [ -n "$STAMPS" ]; then
  printf 'predecessor stamps:\n%s' "$STAMPS"
fi
if [ -n "$LINKS" ]; then
  printf 'legacy .bionic symlinks:\n%s' "$LINKS"
fi
# THE ORDER IS THE INSTRUCTION. CronList first, because a predecessor's recurring
# job survives `/clear` and keeps firing (A-probe-4); creating before deleting
# leaves two clocks on one project, which is the 1.3.2 B-8 bug by another route.
printf 're-arm: CronList → delete bionic-patrol session=<other> jobs → CronCreate → bash %s/hooks/session-poker.sh arm → adopt\n' \
  "$HOOK_ROOT"

exit 0
