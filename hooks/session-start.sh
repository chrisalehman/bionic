#!/bin/bash
# SESSION-START — what the previous conversation left on this project, and nothing
# else (bionic 1.4.0, spec AC-1; AC-4's "the SessionStart block runs the report";
# AC-11's legacy-symlink listing; plan task SSTART).
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
# IT IS A DETECTOR THAT ALSO SWEEPS, AND NOTHING ELSE (REQ-R2, ticket-30, amended
# 2026-09-07 — this paragraph described a stricter contract before that wave). It
# arms nothing, adopts nothing, and never deletes a file itself: the one write it
# can make is calling `session-poker.sh sweep`, silently, once, near the end of
# every run — see "the silent auto-sweep" below for the whole story, including the
# age gate and why REQ-R2 is a deliberate reversal of session-poker.sh's own D-5.
# Every OTHER byte in this file is still pure detection: the report above is built
# from reads alone, and the re-arm line it prints is an instruction for the model
# reading it, whose ORDER is the whole point — CronList BEFORE CronCreate, because
# a predecessor job that is still firing has to be deleted rather than raced
# (AC-3's ritual, S5). `tests/session-start.test.sh`'s `.bionic`-subtree fingerprint
# now expects the sweep's own deletions and, on a genuine failure, one marker file
# — never a stamp, a roster row, or anything this hook wrote for itself.
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

BIONIC_LIB_WANT="context.sh root.sh session.sh patrol.sh run.sh"
# --- bionic-loader/v2 BEGIN
# Find the bionic library — pasted BYTE-IDENTICALLY into all 15 carriers, because a library
# cannot load itself. payload/scripts/lib/loader.sh owns this text and its header holds the
# long form; §N.1 of tests/cross-gate-agreement.test.sh pins and caps every copy, and
# tests/loader.test.sh drives the behaviour. BIONIC_LIB_WANT, set on the line above, names
# the basenames this hook sources; afterwards exactly one of BIONIC_LIB (a directory holding
# all of them) and BIONIC_LIB_MISSING is non-empty. CANDIDATES, each class reached only when
# the earlier one fails: (1) beside the hook in BOTH spellings, since `..` resolves after the
# payload/hooks symlink; (2) the marketplace source tree, read from the registry and never
# assumed; (3) the newest version in that marketplace's cache, by THREE-INTEGER compare —
# 1.10.0 beats 1.3.2, which a lexical sort gets backwards. (2) and (3) heal a partly damaged
# install, so one broken location cannot lock the user out of the repair (R-1 §(5)).
BIONIC_LIB=""; BIONIC_LIB_MISSING=""; BIONIC_LIB_CANDS=""
_bl_dir="$(dirname "$0")"; _bl_want="${BIONIC_LIB_WANT:-}"
_bl_try() {
  [ -n "${1:-}" ] || return 1
  if [ -z "$BIONIC_LIB_CANDS" ]; then BIONIC_LIB_CANDS="$1"; else BIONIC_LIB_CANDS="$BIONIC_LIB_CANDS, $1"; fi
  [ -d "$1" ] || return 1
  for _bl_f in $_bl_want; do [ -r "$1/$_bl_f" ] || return 1; done
  BIONIC_LIB="$1"
}
if ! _bl_try "$_bl_dir/../scripts/lib" && ! _bl_try "$_bl_dir/../payload/scripts/lib"; then
  _bl_pd="${BIONIC_PLUGINS_DIR:-${HOME:-/nonexistent}/.claude/plugins}"; _bl_mk=""
  if [ -r "$_bl_pd/installed_plugins.json" ]; then
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
  BIONIC_LIB_MISSING="${_bl_want%% *}"
  [ -n "$BIONIC_LIB_MISSING" ] || BIONIC_LIB_MISSING="scripts/lib"
fi
loader_fail_open() {
  echo "$1: library ${BIONIC_LIB_MISSING:-the bionic library} not found at ${BIONIC_LIB_CANDS:-(no candidate)} — hook stepping aside; run /bionic:doctor" >&2
  exit 0
}
loader_fail_closed() {
  _bl_root="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd -P)" || _bl_root=""
  [ -n "$_bl_root" ] || _bl_root="$(dirname "$0")/.."
  case "${2:-}" in
    "claude plugin update bionic@bionic"|\
    "claude plugin install bionic@bionic"|\
    "bash $_bl_root/scripts/doctor.sh"|\
    "bash $_bl_root/scripts/setup.sh") exit 0 ;;
  esac
  _bl_who="${1:-a bionic hook}"
  if [ "${#_bl_who}" -gt 25 ]; then _bl_who="${_bl_who:0:24}…"; fi
  printf 'bionic: load refused — %s cannot load the bionic library (run /bionic:doctor)\n' "$_bl_who" >&2
  if [ "${BIONIC_WALL_VERBOSE:-}" = "1" ]; then
    cat >&2 <<BIONIC_LOADER_REFUSE
A wall that cannot read a command refuses it rather than waving it through.

Wanted: ${BIONIC_LIB_MISSING:-the bionic library}
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
  fi
  exit 2
}
# --- bionic-loader/v2 END

# The library, or nothing. `loader_fail_open` prints one stderr line and exits 0 —
# a detector that cannot read the disk reports nothing rather than guessing.
[ -n "$BIONIC_LIB" ] || loader_fail_open "session-start"
. "$BIONIC_LIB/context.sh" || exit 0   # bionic_context, bionic_jq
. "$BIONIC_LIB/root.sh"    || exit 0   # project_root
. "$BIONIC_LIB/session.sh" || exit 0   # session_id, and its one divergence warning
. "$BIONIC_LIB/patrol.sh"  || exit 0   # PATROL_STALE_MULTIPLIER
. "$BIONIC_LIB/run.sh"     || exit 0   # active_run, engaged_session

# The tree this hook was launched from — printed absolute in the re-arm line, and
# the tree whose poker is asked for the interval. `$(dirname "$0")/..` and `pwd -P`
# rather than `realpath`, which stock macOS does not ship (L-LOADER/5, L-BIONIC_ROOT/2).
HOOK_ROOT="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd -P)" || HOOK_ROOT=""
[ -n "$HOOK_ROOT" ] || HOOK_ROOT="$(dirname "$0")/.."

# ------------------------------------------------- the payload, and the context
#
# ONE CALL (REQ-1f, lib/context.sh): the payload read at most once and only when
# stdin is not a terminal, the cwd by the ONE ladder, the root from it, the session
# id past the ONE guard, engagement and the run verdict as VALUES.
#
# THE REDIRECTION IS NOT HERE, and that is this hook's one deviation from the shape
# the other fourteen use. lib/session.sh prints a line when the payload and the
# environment disagree about the session id, and this hook is the single reader that
# must SHOW that line — the L-SESSION contract, pinned at
# tests/cross-gate-agreement.test.sh §P2. Suppression belongs at the call site, so
# the other fourteen write `bionic_context 2>/dev/null || exit 0` and this one does
# not.
#
# THE LADDER USED TO BE REVERSED HERE, and REQ-1h ended that: this hook is on the
# library's one ladder now, in the library's order, like every other hook. The rungs
# are named once, in lib/context.sh, and deliberately not restated here — a comment
# naming a channel its file no longer reads is how the next reader learns the wrong
# thing.
bionic_context || exit 0

pfield() {  # <jq path> -> the field, or empty
  command -v jq >/dev/null 2>&1 || return 0
  bionic_jq "$1"
}
SOURCE="$(pfield .source)"

# ---------------------------------------------------------------- the project
# A `.bionic` that is a SYMLINK is never a root (ledger C2) — which is exactly the
# legacy link this hook reports further down, so a worktree carrying one resolves to
# the main checkout and reports the main checkout's state, not a second copy of it.
[ -d "$BIONIC_ROOT/.bionic" ] && [ ! -L "$BIONIC_ROOT/.bionic" ] || exit 0
TMP="$BIONIC_ROOT/.bionic/tmp"

# ---------------------------------------------------------------- the three channels
#
# The env value is primary and the other two are witnesses (lib/session.sh, ledger
# S2). All three are PRINTED regardless, because the whole reason this line exists
# is that a reader cannot otherwise tell an agreement from a coincidence — and the
# probe's finding that they agree on a plain `/clear` is a measurement of one CLI
# build, not a guarantee.
ENV_SID="${CLAUDE_CODE_SESSION_ID:-}"
# THE PAYLOAD'S OWN VALUE, read here rather than taken from `BIONIC_SID`. They are
# different questions: `BIONIC_SID` is the RESOLVED id — the environment's, with the
# payload as a witness — and this is the witness itself, printed beside the other two
# so a reader can tell an agreement from a coincidence. Reading the resolved value
# into this slot would make the three channels agree by construction and report
# nothing.
PAYLOAD_SID="$(pfield .session_id)"
PID_SID=""
PIDFILE="$(claude_home)/sessions/$PPID.json"
if [ -f "$PIDFILE" ] && [ ! -L "$PIDFILE" ] && command -v jq >/dev/null 2>&1; then
  PID_SID="$(jq -r '.sessionId // empty' "$PIDFILE" 2>/dev/null)"
fi

# ---------------------------------------------------------------- engagement
#
# An open run gates the whole roster/stamp/re-arm block behind this session's
# own consent to enter bionic (lib/run.sh `engaged_session`, T4/AC-11/AC-12).
# A session that never invoked canonical-sdlc gets exactly one line naming the
# plan and the skill — no roster dump, no stamp report, no re-arm instruction
# — because none of that operational detail is addressed to a bystander. A sid
# this hook cannot read is, like every other unreadable state here, NOT
# engaged: the safe direction is the quieter one.
#
# THE OPEN-RUN SET, not the single newest file (wave-session-bound-run S7,
# AC-5). `RUNS`/`N` decide the shape below: N=0/1 reproduce today's behaviour
# exactly — a lone open run is unambiguous, bound or not. N>=2 means a scan
# can no longer guess which run a session means, so a bystander gets the set
# (capped for display by `print_runs` below) plus the bind verb instead of one
# path picked by mtime, and an engaged
# session whose own binding does not resolve to one of them (unbound, or
# bound to a run that has since closed) gets the same listing prepended to
# today's engaged block rather than a silent guess — it is not exited early,
# because the roster/stamp/re-arm report still belongs to an engaged reader.
RUNS="$(open_runs "$BIONIC_ROOT")" || RUNS=""
N=$(printf '%s\n' "$RUNS" | grep -c '.')

# LIVE VS OPEN (spec AC-1/AC-3, S3). `live_runs` is a FILTER over `open_runs` — see
# scripts/lib/run.sh — so the header above still names the true OPEN count (`$N`,
# unchanged) while the listing itself shows only the LIVE subset; the quiet remainder is
# reported as one count, not a second listing, because a bystander acts on a live plan by
# name and on a quiet one only by knowing it exists at all.
LIVE="$(live_runs "$BIONIC_ROOT")" || LIVE=""
LIVE_N=$(printf '%s\n' "$LIVE" | grep -c '.')
QUIET=$((N - LIVE_N))

# ONE RENDERER FOR BOTH LISTINGS (review duplication D8b, S10b). The not-engaged block and
# the engaged-but-unbound block below print the same set for the same reason, and they were
# two copies of one `while read` loop inside one file — the shape that drifts.
#
# THE DISPLAY IS CAPPED; THE SET IS NOT (review performance P3, security F4). `open_runs`
# stays uncapped because it is a membership predicate with three callers, two of which need
# every member. What is bounded is what this hook PRINTS. A SessionStart hook's stdout is
# added to the new conversation's context on `startup`, `clear`, `resume` AND `compact`, and
# this repository's own tree already renders 60 paths — ~6.8 KB, roughly 1,700 tokens — of a
# list the reader acts on at most one line of. The set is newest-mtime-first, so the eight
# shown are the eight a session is most likely to mean, and the trailer says the rest are
# still reachable: `bind` takes any open plan by name, listed or not. The HEADER above each
# call still names the true count, so the cap never understates what is here.
#
# PATHS ARE RELATIVE TO THE DOCS BIONIC_ROOT. Every one of them shares the same long prefix (47
# characters here), and a listed line PASTES STRAIGHT INTO THE BIND VERB named on the header
# line above it: `bind` takes an operand that is absolute, project-root-relative or
# docs-root-relative, trying the project root first and the docs root when that misses
# (hooks/session-poker.sh, the `bind` arm, S10b phase 2). If the docs root cannot be read the
# paths are printed whole rather than mangled by a prefix strip that would eat a leading
# slash.
RUN_LIST_CAP=8
DOCS="$(docs_root "$BIONIC_ROOT" 2>/dev/null)" || DOCS=""
print_runs() {  # <newline-separated runs> -> the capped, docs-root-relative listing
  local runs="$1" total shown=0 _p
  total=$(printf '%s\n' "$runs" | grep -c '.')
  while IFS= read -r _p; do
    [ -n "$_p" ] || continue
    shown=$((shown + 1))
    [ "$shown" -le "$RUN_LIST_CAP" ] || continue
    if [ -n "$DOCS" ]; then
      printf '  %s\n' "${_p#"$DOCS"/}"
    else
      printf '  %s\n' "$_p"
    fi
  done <<EOF
$runs
EOF
  if [ "$total" -gt "$RUN_LIST_CAP" ]; then
    printf '  … and %s more — bind names any open plan\n' "$((total - RUN_LIST_CAP))"
  fi
  return 0
}

# THE QUIET-COUNT LINE (AC-3). Printed right after whichever listing just ran, and only
# when the open/live difference is non-zero — a zero-quiet fixture must stay silent on
# this line (anti-vacuity, §13c of the suite).
print_quiet_line() {
  [ "$QUIET" -gt 0 ] || return 0
  printf 'bionic: %s quiet open run(s) — bind names any of them\n' "$QUIET"
}

# THE BOUND-RUN LINE (AC-21). `session_run` already resolved "this session's binding
# is to an open plan"; this only formats it. The plan path comes off the marker
# `session_run` read, not off `$RUNS`/`$LIVE`, because a bound plan is named by the
# ONE binding fact regardless of how many other runs are open. `current:` is read the
# same way the poker's own step display does — first match, digits and `T` only, so a
# multi-digit or ISO-stamped value still comes through whole.
print_bound_line() {  # <verdict "bound-open <plan>">
  local verdict="$1" bplan step relplan
  bplan="${verdict#bound-open }"
  step="$(grep -m1 '^current:' "$bplan" 2>/dev/null | tr -dc '0-9T')"
  if [ -n "$DOCS" ]; then relplan="${bplan#"$DOCS"/}"; else relplan="$bplan"; fi
  printf 'bionic: bound to %s — current: %s\n' "$relplan" "$step"
  # THE STEP FILE, NAMED RATHER THAN INJECTED (wave-11 row 1b, design D1). The governing
  # skill is a core plus one file per step, and the core's own rule is to read `steps/N.md`
  # before acting at step N. Nothing enforces that — no hook can see whether a model read a
  # file — so this line does the one thing a hook honestly can: it puts the path in front of
  # the session at the moment the step is known, so the read is a glance away rather than a
  # lookup. `$HOOK_ROOT` is the tree this hook was launched from, the same root the re-arm
  # line prints and the same one `ss_interval` asks for the poker, so the path names a file
  # in the plugin that is actually running rather than in whichever one is installed.
  #
  # ONLY FOR A NUMERIC STEP. A task-scale plan reads `current: T<n>`, which names no step
  # file, and a plan with no readable `current:` leaves `$step` empty; printing
  # `steps/T3.md` or `steps/.md` would send a reader at a path that does not exist.
  case "$step" in
    [0-9]|[0-9][0-9]) printf '  step file: %s/skills/canonical-sdlc/steps/%s.md\n' "$HOOK_ROOT" "$step" ;;
  esac
}

if [ "$N" -eq 1 ]; then
  PLAN="$RUNS"
  if [ "$BIONIC_ENGAGED" != 1 ]; then
    printf 'bionic: an open run exists here (%s) — invoke /bionic:canonical-sdlc to engage it\n' "$PLAN"
    exit 0
  else
    case "$BIONIC_RUN_WORD" in
      bound-open) print_bound_line "$BIONIC_RUN_WORD $BIONIC_RUN_PLAN" ;;
    esac
  fi
elif [ "$N" -ge 2 ]; then
  if [ "$BIONIC_ENGAGED" != 1 ]; then
    printf 'bionic: %s open runs exist here — invoke /bionic:canonical-sdlc, then bind the one you mean with: bash %s/hooks/session-poker.sh bind <plan>\n' \
      "$N" "$HOOK_ROOT"
    print_runs "$LIVE"
    print_quiet_line
    exit 0
  else
    case "$BIONIC_RUN_WORD" in
      bound-open) print_bound_line "$BIONIC_RUN_WORD $BIONIC_RUN_PLAN" ;;
      *)
        printf 'bionic: %s open runs exist here and this session is not bound to one — bind with: bash %s/hooks/session-poker.sh bind <plan>\n' \
          "$N" "$HOOK_ROOT"
        print_runs "$LIVE"
        print_quiet_line
        ;;
    esac
  fi
fi

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
# rather than shelled out to, because task POKER owns that file and this hook must
# read the same disk with or without its `--report-only` verb.
#
# ONE AWK PROCESS FOR EVERY PREDECESSOR ROSTER, not one per file (REQ-6, carry-over
# P9). The per-file shape below — `for RF in …; do N="$(open_rows "$RF" …)"; done` —
# forked an `awk` per roster file with no bound on how many can accumulate under
# `.bionic/tmp`: measured ~10.4s at 400 dead sessions against the CLI's 10s hook
# timeout (2,041ms already at 14 files — subprocess-per-file cost dominates well
# before any file count a real project ever carries deliberately). The FILTERING
# loop below stays pure bash builtins (glob + `[ -f ]`/`[ -L ]`, no fork), and
# builds a tab-separated manifest of every SURVIVING (osid, roster, ledger) triple;
# ONE awk invocation then walks the manifest and, for each row, reads that roster
# file and its ledger with `getline < file` (awk's own multi-file idiom, not a
# subprocess), resetting its per-file `seen`/`met`/`acked` arrays between rows —
# the exact per-file reset the old per-invocation `awk` got for free by exiting.
# Output is unchanged: one `osid<TAB>count<TAB>roster-path` line per roster with at
# least one open row, read back below into the same `ROSTERS` text as today.
sid8() { printf '%.8s' "${1:-}"; }

ROSTER_MANIFEST=""
for RF in "$TMP"/roster-*.state; do
  [ -f "$RF" ] || continue
  [ -L "$RF" ] && continue        # symlinks are not followed, as everywhere in tmp
  OSID="${RF##*/}"; OSID="${OSID#roster-}"; OSID="${OSID%.state}"
  [ -n "$OSID" ] || continue
  if [ -n "$BIONIC_SID" ] && [ "$OSID" = "$BIONIC_SID" ]; then continue; fi
  LEDGER="$TMP/sweeper-$OSID.state"
  if [ ! -f "$LEDGER" ] || [ -L "$LEDGER" ]; then LEDGER=""; fi
  ROSTER_MANIFEST="${ROSTER_MANIFEST}${OSID}	${RF}	${LEDGER}
"
done

ROSTERS=""
if [ -n "$ROSTER_MANIFEST" ]; then
  ROSTER_RAW="$(printf '%s' "$ROSTER_MANIFEST" | awk -F'\t' '
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
    {
      osid = $1; rf = $2; ledger = $3
      delete seen; delete met; delete acked
      if (ledger != "") {
        while ((getline l < ledger) > 0) {
          if (l !~ /^sweeper-ledger\/v1\|/) continue
          if (kv(l, "event") != "ack") continue
          an = kv(l, "name"); if (an != "") acked[an] = 1
        }
        close(ledger)
      }
      while ((getline l < rf) > 0) {
        if (l ~ /^roster-state\/v1\|/) {
          n = kv(l, "name"); if (n != "") seen[n] = 1
          continue
        }
        if (l ~ /^landing-swept\/v1\|/) {
          n = kv(l, "name")
          if (n != "" && kv(l, "state") == "MET") met[n] = 1
        }
      }
      close(rf)
      c = 0
      for (n in seen) { if (n in met) continue; if (n in acked) continue; c++ }
      if (c > 0) printf "%s\t%s\t%s\n", osid, c, rf
    }
  ' 2>/dev/null)"
  if [ -n "$ROSTER_RAW" ]; then
    while IFS="$(printf '\t')" read -r OSID N RF; do
      [ -n "$OSID" ] || continue
      ROSTERS="${ROSTERS}  $(sid8 "$OSID") — $N open row(s) — ${RF##*/}
"
    done <<EOF
$ROSTER_RAW
EOF
  fi
fi

# ---------------------------------------------------------------- predecessor stamps
#
# THE INTERVAL COMES FROM THE POKER BESIDE THIS HOOK, by the same two-step
# lib/patrol.sh's `patrol_interval` takes — the project's configured value, then
# the script's built-in default, then the last resort. It is asked HERE rather than
# through `patrol_interval` because that function resolves the poker through
# `plugin_root` (lib/roots.sh), i.e. the plugin installed on the machine, while a
# SessionStart hook must measure against the tree it was actually launched from.
ss_interval() {
  local poker="$HOOK_ROOT/hooks/session-poker.sh" s=""
  if [ -f "$poker" ]; then
    s="$( cd "$BIONIC_ROOT" 2>/dev/null && bash "$poker" interval 2>/dev/null )"
    case "$s" in ''|*[!0-9]*) s="" ;; esac
    if [ -z "$s" ]; then
      s="$( bash "$poker" interval-default 2>/dev/null )"
      case "$s" in ''|*[!0-9]*) s="" ;; esac
    fi
  fi
  if [ -z "$s" ] || [ "$s" -le 0 ]; then s="$PATROL_INTERVAL_LAST_RESORT"; fi
  printf '%s' "$s"
}

# BOUNDED, THE SAME MECHANISM detect_bounded USES (payload/scripts/lib/detect.sh):
# a background job of its own process group, a poll that signals the GROUP (never
# just the child — a grandchild inherits the caller's own stdout pipe otherwise)
# when the bound is up, and stdout captured to a file this shell alone reads
# afterwards so a run that outlives its bound can never hold this hook's own
# stdout open. Kept LOCAL rather than sourced from detect.sh: this hook's loader
# wants root/session/patrol/run only (BIONIC_LIB_WANT above), and a fifth required
# library would fail the whole DETECTOR closed on a machine that lacks it, to buy
# a bound only the one `sweep` call below needs.
ss_bounded_sweep() {  # <poker path> <bound seconds> -> stdout; rc mirrors sweep, 124 on timeout
  local poker="$1" limit="$2" pid waited=0 rc out had_monitor
  out="${TMPDIR:-/tmp}/bionic-sweep.$$.out"
  : > "$out" 2>/dev/null || out="/dev/null"
  case "$-" in *m*) had_monitor=yes ;; *) had_monitor=no ;; esac
  set -m
  ( cd "$BIONIC_ROOT" 2>/dev/null && bash "$poker" sweep ) </dev/null >"$out" 2>/dev/null &
  pid=$!
  [ "$had_monitor" = "yes" ] || set +m
  if command -v sleep >/dev/null 2>&1; then
    while kill -0 "$pid" 2>/dev/null; do
      if [ "$waited" -ge "$limit" ]; then
        kill -TERM "-${pid}" 2>/dev/null || kill -TERM "$pid" 2>/dev/null
        wait "$pid" 2>/dev/null
        [ -s "$out" ] && cat "$out"
        rm -f "$out" 2>/dev/null
        return 124
      fi
      sleep 1
      waited=$((waited + 1))
    done
  fi
  wait "$pid"; rc=$?
  [ -s "$out" ] && cat "$out"
  rm -f "$out" 2>/dev/null
  return "$rc"
}

STAMPS=""
LIMIT=$(( $(ss_interval) * PATROL_STALE_MULTIPLIER ))
NOW="$(date -u +%s 2>/dev/null || echo 0)"

# ONE `stat` INVOCATION FOR EVERY PREDECESSOR STAMP, not one per file (REQ-6,
# same defect and the same fix shape as the roster loop above, and the same
# batched-stat idiom the sweep gate further down already established — one
# flavour probe, then a single `xargs` pass over every candidate path rather
# than a `stat` fork per file). The filtering loop stays pure bash builtins
# (glob + `[ -f ]`/`[ -L ]`, no fork) and records each survivor's path in
# ORDER; `stat`'s own output preserves that order one line per input, so the
# second loop below zips path[i] back to mtime[i] positionally rather than
# re-deriving anything from the filename.
STAMP_FILES=""
STAMP_OSIDS=""
for SF in "$TMP"/patrol-*.state; do
  [ -f "$SF" ] || continue
  [ -L "$SF" ] && continue
  OSID="${SF##*/}"; OSID="${OSID#patrol-}"; OSID="${OSID%.state}"
  [ -n "$OSID" ] || continue
  if [ -n "$BIONIC_SID" ] && [ "$OSID" = "$BIONIC_SID" ]; then continue; fi
  STAMP_FILES="${STAMP_FILES}${SF}
"
  STAMP_OSIDS="${STAMP_OSIDS}${OSID}
"
done

if [ -n "$STAMP_FILES" ]; then
  case "$(stat -c %Y /dev/null 2>/dev/null)" in
    ''|*[!0-9]*)
      STAMP_MTS="$(printf '%s' "$STAMP_FILES" | tr '\n' '\0' | xargs -0 stat -f %m 2>/dev/null)"
      ;;
    *)
      STAMP_MTS="$(printf '%s' "$STAMP_FILES" | tr '\n' '\0' | xargs -0 stat -c %Y 2>/dev/null)"
      ;;
  esac
  exec 8<<EOF_OSIDS
$STAMP_OSIDS
EOF_OSIDS
  exec 9<<EOF_MTS
$STAMP_MTS
EOF_MTS
  while IFS= read -r OSID <&8 && IFS= read -r MT <&9; do
    [ -n "$OSID" ] || continue
    case "$MT" in ''|*[!0-9]*) continue ;; esac
    AGE=$(( NOW - MT )); [ "$AGE" -ge 0 ] || AGE=0
    if [ "$AGE" -gt "$LIMIT" ]; then STATE="stale"; else STATE="fresh"; fi
    STAMPS="${STAMPS}  $(sid8 "$OSID") — ${AGE}s old (stale past ${LIMIT}s) — $STATE
"
  done
  exec 8<&- 9<&-
fi

# ---------------------------------------------------------------- legacy symlinks
LINKS=""
for LN in "$BIONIC_ROOT"/.worktrees/*/.bionic; do
  [ -L "$LN" ] || continue
  LINKS="${LINKS}  ${LN#"$BIONIC_ROOT"/} -> $(readlink "$LN" 2>/dev/null)
"
done

# ---------------------------------------------------------------- the silent auto-sweep
#
# THE ONE WRITE THIS HOOK NOW MAKES (REQ-R2, ticket-30, ratified 2026-09-07). Every
# comment above this point still describes the DETECTOR half faithfully — the
# roster/stamp/symlink report above reads nothing differently for this — but
# "arms nothing, deletes nothing, adopts nothing and writes nothing" (this file's
# own header, above) is no longer the whole of what runs here. session-poker.sh's
# sweep verb carries a 1.5.1 decision that auto-sweeping was REJECTED (D-5): "a
# hook that cleared [residue] at engagement would delete the evidence of the
# thing it was helping with." REQ-R2 reverses that ruling for THIS ONE HOOK, on
# THIS ONE TRIGGER — SessionStart, never engagement — because the field defect
# (ticket-30) is the opposite failure: nothing ever swept the residue at all,
# doctor could prove a project's predecessor sessions dead and name no way to
# clear them, and setup offered nothing for it. `sweep`'s own deletion logic is
# untouched (A-5) — this hook only ever decides WHETHER to invoke it; it never
# deletes a file itself.
#
# THE AGE GATE (AC-R2.3) IS THIS HOOK'S OWN, not the verb's. `sweep` judges
# liveness alone — a session dead one second after `/clear` re-keys its pid file
# is exactly as dead as one a week stale — which is right for a verb a human runs
# on purpose. A hook that fires on every conversation start is not that: the
# predecessor roster this same run just reported above would be deleted before
# anyone could act on it if sweep touched it immediately. So a dead session's
# files get one Patrol interval of grace before this hook will let `sweep` near
# them. `patrol_dead_sessions` and `patrol_session_state_files` are the SAME
# library functions the verb and doctor's own detector call, read here directly
# (no subprocess) so "who is dead" can never come apart between the three readers.
#
# THE GATE IS PER SESSION START, NOT PER FILE. `sweep` takes no operand (by
# design — see its own docblock), so there is no way to ask it for "everyone
# dead EXCEPT this one young file": if ANY dead session anywhere under
# .bionic/tmp has ANY file younger than the interval, this hook skips calling
# `sweep` AT ALL this run, and every dead session's files wait for the NEXT
# session start together. A young file next to an ancient one is rare — a
# session dies once, its files age together — and the alternative (calling
# `sweep` anyway and accepting that a too-young file gets deleted early) is the
# one failure mode this gate exists to prevent. tests/session-start.test.sh §6
# is where a mixed batch is deliberately constructed and this tradeoff is felt.
#
# SILENT ON SUCCESS, ONE LINE ON FAILURE (AC-R2.4, scope constraint). `sweep`'s
# own exit codes: 0 is swept-or-nothing-to-sweep, 1 is "every session here is
# LIVE" — an ordinary, frequent, entirely healthy answer and not a fault — and 2
# is a refusal (a `.bionic/tmp` sweep will not delete inside, or a usage error
# this hook cannot cause). Only 2, or this wrapper's own 124 on a bounded
# timeout, counts as failure: a marker is left and this one line prints. 0 and 1
# are silent and clear any marker a PAST failure left, so a transient problem
# stops being reported the moment sweeping actually works again.
SWEEP_FAIL_LINE=""
if [ -d "$TMP" ] && [ ! -L "$TMP" ]; then
  SS_DEAD_IDS="$(patrol_dead_sessions "$BIONIC_ROOT" "$BIONIC_SID" 2>/dev/null)"
  SS_YOUNG=no
  if [ -n "$SS_DEAD_IDS" ]; then
    SS_LIMIT="$(ss_interval)"
    SS_NOW="$(date -u +%s 2>/dev/null || echo 0)"
    # ONE `stat` CALL FOR THE WHOLE GATE, not one per file (Step-6 review F-4).
    # The shape this replaces ran a `stat` process per state file per dead session,
    # ahead of the bounded sweep rather than inside it, so its cost was neither
    # small nor bounded: 400 dead sessions measured 13.8 s against the 10-second
    # timeout hooks/hooks.json registers for this hook, and BIONIC_SWEEP_BOUND_SECONDS
    # defaults to that same 10 so the guard below could never fire first. The sweep
    # runs AFTER the report is built, so a CLI timeout here discards the report — on
    # exactly the residue-heavy project the report is most useful on.
    #
    # THE FILE LIST IS STILL THE LIBRARY'S ANSWER. `patrol_session_state_files` is
    # asked the same question about the same sessions; only the mtime read is
    # batched, so "who is dead and what did they leave" cannot come apart between
    # this hook, the verb and doctor. The collection loop is ONE subshell for the
    # whole set rather than one per session.
    SS_FILES="$(while IFS= read -r SS_SID; do
        [ -n "$SS_SID" ] || continue
        patrol_session_state_files "$BIONIC_ROOT" "$SS_SID"
      done <<EOF
$SS_DEAD_IDS
EOF
)"
    if [ -n "$SS_FILES" ]; then
      # THE FLAVOUR PROBE RUNS ONCE, not per file, and it DISCRIMINATES rather than
      # falling through on emptiness (Step-6 critic, issue 1). `stat -c %Y /dev/null`
      # is a number on GNU coreutils and on busybox, and nothing at all on BSD, which
      # rejects `-c` outright — so the probe's OUTPUT chooses the form. What it must
      # never do is try the BSD form first and treat a non-empty capture as proof
      # that it worked: GNU's `-f` is `--file-system`, so `%m` is read as a FILE
      # operand, and GNU complains about `%m` on stderr while still printing a full
      # file-system report for the real files on STDOUT and exiting 1. That capture
      # is non-empty and entirely non-numeric, so an emptiness test never reaches the
      # GNU form, every line fails the numeric case below, and the gate concludes
      # nothing is young — deleting seconds-old state on every Linux and WSL install.
      # tests/session-sweep.test.sh §7i plants a GNU-shaped `stat` on PATH and holds
      # this.
      #
      # `tr` + `xargs -0` rather than `stat $SS_FILES` so a residue far larger than
      # this one cannot overflow the argument list, and so a path carrying a space is
      # one operand rather than two.
      case "$(stat -c %Y /dev/null 2>/dev/null)" in
        ''|*[!0-9]*)
          SS_MTS="$(printf '%s\n' "$SS_FILES" | tr '\n' '\0' | xargs -0 stat -f %m 2>/dev/null)"
          ;;
        *)
          SS_MTS="$(printf '%s\n' "$SS_FILES" | tr '\n' '\0' | xargs -0 stat -c %Y 2>/dev/null)"
          ;;
      esac
      # A mtime NEWER than the cutoff is a file inside the interval. Spelled as a
      # comparison against the cutoff rather than as an age subtraction because the
      # two are the same statement and this one needs no clamp: a mtime in the
      # future is newer than the cutoff, which is the deferring answer the age
      # form reached by clamping a negative age to zero.
      SS_CUTOFF=$(( SS_NOW - SS_LIMIT ))
      while IFS= read -r SS_MT; do
        case "$SS_MT" in ''|*[!0-9]*) continue ;; esac
        if [ "$SS_MT" -gt "$SS_CUTOFF" ]; then SS_YOUNG=yes; break; fi
      done <<EOF
$SS_MTS
EOF
    fi
  fi

  if [ "$SS_YOUNG" = no ]; then
    SS_POKER="$HOOK_ROOT/hooks/session-poker.sh"
    if [ -f "$SS_POKER" ]; then
      SS_BOUND="${BIONIC_SWEEP_BOUND_SECONDS:-10}"
      ss_bounded_sweep "$SS_POKER" "$SS_BOUND" >/dev/null
      SS_RC=$?
      SWEEP_MARKER="$TMP/sweep-failed.state"
      case "$SS_RC" in
        0|1)
          rm -f "$SWEEP_MARKER" 2>/dev/null
          ;;
        *)
          printf 'sweep-failed/v1|at=%s|rc=%s\n' \
            "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" "$SS_RC" > "$SWEEP_MARKER" 2>/dev/null
          SWEEP_FAIL_LINE="bionic: the automatic dead-session sweep failed (rc=${SS_RC}) — run /bionic:doctor for the fix"
          ;;
      esac
    fi
  fi
fi

# ---------------------------------------------------------------- the block
#
# SILENCE IS THE DEFAULT. Four findings and one verdict; if every finding is empty
# and the three channels agree, there is nothing a reader could act on and the hook
# says nothing at all — EXCEPT a sweep failure, which is worth one line even on an
# otherwise quiet session start (AC-R2.4): it is the one write this hook can make,
# and a write that fails silently is worse than the noise of saying so.
if [ -z "$ROSTERS" ] && [ -z "$STAMPS" ] && [ -z "$LINKS" ] && [ "$AGREE" = "agree" ]; then
  [ -n "$SWEEP_FAIL_LINE" ] && printf '%s\n' "$SWEEP_FAIL_LINE"
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
[ -n "$SWEEP_FAIL_LINE" ] && printf '%s\n' "$SWEEP_FAIL_LINE"

exit 0
