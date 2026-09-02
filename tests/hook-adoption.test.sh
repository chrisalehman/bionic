#!/bin/bash
# tests/hook-adoption.test.sh — ADOPT: every hook on the library spine, always-on.
# (bionic 1.4.0, wave-bionic-1.4.0-update slice ADOPT; spec AC-7, AC-8, AC-9, AC-12,
# AC-16; design §2 "order in every hook: load, active_run, own work".)
#
# WHAT IS UNDER TEST. Not a library — a CONVENTION, held across eighteen files that
# the CLI invokes independently. Three claims, each of which has its own way of going
# silently wrong:
#
#   1. THE IDIOM IS ONE TEXT. Every hook carries `bionic_loader_pin`'s block byte for
#      byte, under a `BIONIC_LIB_WANT=` line naming exactly what it sources. A hand
#      edit to one copy is the drift this pins; a copy that wants a library it never
#      sources is the drift the WANT/source pairing pins.
#   2. THE FACTS HAVE ONE OWNER. No hook resolves a project root, a session id or an
#      active run by restating the algorithm. `project_root`, `session_id`,
#      `active_run` — the library answers, and the hook asks.
#   3. THE PREDICATE ACTUALLY GATES. A static call to `active_run` proves nothing; a
#      hook could call it and ignore the answer. So every run-scoped hook is DRIVEN
#      three times over real fixtures: no `.bionic` anywhere (silent), a `.bionic`
#      whose plan is CLOSED (silent), and the same fixture with the plan OPEN (NOT
#      silent). The third case is the anti-vacuity control — without it a hook that
#      exits 0 at line 1 would pass the first two.
#
# FAIL DIRECTION BY THE COST OF THE MISTAKE (design ledger S4). Two hooks are walls
# over an irreversible action and refuse when they cannot load — hooks/protect-main.sh
# and hooks/canonical-sdlc-evidence-gate.sh, permitting exactly four repair commands
# by whole-string match so a broken publish cannot lock the user out of the repair.
# Every other hook prints one line and steps aside. §6 drives both classes.
#
# HERMETIC. Every fixture lives under one `mktemp -d`; HOME and BIONIC_PLUGINS_DIR are
# overridden into it for every driven call, so nothing here reads the real ~/.claude.
#
# Usage: bash tests/hook-adoption.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"

HOOKS="$BIONIC_HOOKS_DIR"
REPO="$BIONIC_SCRIPTS_DIR"
RUNNER="$REPO/tests/run.sh"
LOADER_LIB="$REPO/payload/scripts/lib/loader.sh"

SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/bionic-adopt.XXXXXX") || exit 1
trap 'rm -rf "$SANDBOX"' EXIT

PASS=0; FAIL=0; TOTAL=0
ok() { TOTAL=$((TOTAL + 1)); PASS=$((PASS + 1)); echo "PASS: $1"; }
no() { TOTAL=$((TOTAL + 1)); FAIL=$((FAIL + 1)); echo "FAIL: $1"; [ -n "${2:-}" ] && echo "      $2"; return 0; }
expect_eq() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "expected [$2], got [$3]"; fi; }
expect_empty() { if [ -z "$2" ]; then ok "$1"; else no "$1" "expected empty, got [$2]"; fi; }
expect_nonempty() { if [ -n "$2" ]; then ok "$1"; else no "$1" "expected something, got nothing"; fi; }
expect_contains() { case "$3" in *"$2"*) ok "$1" ;; *) no "$1" "[$2] not found in: $3" ;; esac; }

# ── THE ROSTER OF ADOPTED HOOKS ──────────────────────────────────────────────
#
# Three columns, because the three claims are per-hook properties, not global ones:
#   name | fail class (closed|open) | run-scoped (yes|no)
#
# RUN-SCOPED IS NOT THE SAME AS ADOPTED. hooks/protect-main.sh and
# hooks/protect-database.sh guard damage that is wrong in every project on the
# machine, wave or no wave, so they never consult the run. Everything else is a
# governance hook: it has nothing to say outside a run and must say nothing.
# background-suite-guard runs only behind agent-context-guard, whose own roster
# check already scopes it, so it loads the library without the run predicate.
ADOPTED='
protect-main|closed|no
canonical-sdlc-evidence-gate|closed|yes
farm-out-reminder|open|yes
background-suite-guard|open|no
dispatch-preflight|open|yes
canonical-sdlc-governing-skill|open|yes
landing-gate|open|yes
execution-recorder|open|yes
stop-guard|open|yes
context-spend|open|yes
patrol-duties-gate|open|yes
patrol-revive|open|yes
agent-context-guard|open|no
preflight-probe|open|no
stop-orders|open|no
session-sweeper|open|no
stop-check|open|no
'

# ============================================================
echo "=== 0 — the carrier, the roster line, and non-vacuity ==="
# ============================================================

if grep -q '^run "hook-adoption.test.sh" bash tests/hook-adoption.test.sh$' "$RUNNER"; then
  ok "tests/run.sh carries this suite's own run line"
else
  no "tests/run.sh carries this suite's own run line" "no matching run line in $RUNNER"
fi

BLOCK="$SANDBOX/canonical-block.txt"
( . "$LOADER_LIB" && bionic_loader_pin ) > "$BLOCK" 2>"$SANDBOX/.pinerr"
BLOCK_LINES=$(wc -l < "$BLOCK" | tr -d ' ')
if [ "${BLOCK_LINES:-0}" -gt 50 ]; then
  ok "bionic_loader_pin prints the canonical block ($BLOCK_LINES lines)"
else
  no "bionic_loader_pin prints the canonical block" "got $BLOCK_LINES lines: $(cat "$SANDBOX/.pinerr")"
fi

# extract_block <file> -> the marker-delimited span, markers inclusive
extract_block() {
  awk '/^# --- bionic-loader\/v2 BEGIN$/{f=1} f{print} f&&/^# --- bionic-loader\/v2 END$/{exit}' "$1"
}
# want_line <file> -> the line immediately ABOVE the BEGIN marker
want_line() {
  awk '/^# --- bionic-loader\/v2 BEGIN$/{print prev; exit} {prev=$0}' "$1"
}

# ============================================================
echo ""
echo "=== 1 — one idiom, byte for byte, under a WANT line that matches what is sourced ==="
# ============================================================

while IFS='|' read -r name class scoped; do
  [ -n "$name" ] || continue
  f="$HOOKS/$name.sh"
  if [ ! -f "$f" ]; then no "$name.sh exists" "$f"; continue; fi

  expect_eq "$name carries the canonical loader block byte for byte" \
    "$(cat "$BLOCK")" "$(extract_block "$f")"

  wl=$(want_line "$f")
  case "$wl" in
    BIONIC_LIB_WANT=\"*\") ok "$name declares BIONIC_LIB_WANT on the line above the block" ;;
    *) no "$name declares BIONIC_LIB_WANT on the line above the block" "line above BEGIN was: [$wl]" ;;
  esac

  # Every wanted basename is actually sourced out of $BIONIC_LIB, and nothing is
  # sourced out of it that was not wanted: a hook that sources an unwanted library
  # is a hook the loader never checked for, which is a NUL dereference by another
  # name the first time that file is the one missing.
  wants=$(printf '%s' "$wl" | sed -e 's/^BIONIC_LIB_WANT="//' -e 's/"$//')
  sourced=$(grep -oE '^\. "\$BIONIC_LIB/[a-z.-]+\.sh"' "$f" | sed -E 's|^\. "\$BIONIC_LIB/||; s|"$||' | sort | tr '\n' ' ' | sed 's/ $//')
  expect_eq "$name sources exactly the libraries it wants" \
    "$(printf '%s' "$wants" | tr ' ' '\n' | sort | tr '\n' ' ' | sed 's/ $//')" "$sourced"

  # THE FAIL DIRECTION IS DECLARED, not inferred. Exactly one of the two calls
  # appears, and the closed pair passes the command text so the repair allowlist
  # has something to match.
  n_closed=$(grep -c 'loader_fail_closed "' "$f")
  n_open=$(grep -c 'loader_fail_open "' "$f")
  case "$class" in
    closed) expect_eq "$name fails CLOSED on a missing library (and only that)" "1 0" "$n_closed $n_open" ;;
    open)   expect_eq "$name fails OPEN on a missing library (and only that)"   "0 1" "$n_closed $n_open" ;;
  esac
done <<EOF
$ADOPTED
EOF

# ============================================================
echo ""
echo "=== 2 — one root: no hook restates the walk ==="
# ============================================================
#
# The eight `resolve_project_root` copies this replaces were byte-identical by
# assertion and divergent by history; the library ends the family. session-poker.sh
# is the ONE remaining carrier and it is named here rather than excused silently —
# slice POKER converts it, and this assertion is what will notice if that never
# happens.
STRAGGLERS=$(grep -ln '^resolve_project_root()' "$HOOKS"/*.sh 2>/dev/null | xargs -n1 basename 2>/dev/null | sort | tr '\n' ' ' | sed 's/ $//')
expect_eq "session-poker.sh is the only hook still defining resolve_project_root" \
  "session-poker.sh" "$STRAGGLERS"

while IFS='|' read -r name class scoped; do
  [ -n "$name" ] || continue
  f="$HOOKS/$name.sh"
  [ -f "$f" ] || continue
  case "$name" in
    protect-main|background-suite-guard) continue ;;  # neither reads a root
  esac
  if grep -qE '=\$\(project_root |=\$\(project_root$|project_root "' "$f"; then
    ok "$name resolves its root through the library"
  else
    no "$name resolves its root through the library" "no project_root call in $f"
  fi
done <<EOF
$ADOPTED
EOF

# ============================================================
echo ""
echo "=== 3 — one session id: every reader asks the library ==="
# ============================================================
#
# The env value is primary and the payload is a witness (design §1). A hook that
# reads `.session_id` straight out of its payload has silently chosen the witness
# over the record, which is the divergence R-1 measured. So: every hook that
# derives a session id calls `session_id`, and the payload read that remains is
# the ARGUMENT to that call, never the answer.
SID_READERS='agent-context-guard preflight-probe stop-orders session-sweeper stop-check landing-gate execution-recorder dispatch-preflight patrol-revive context-spend farm-out-reminder'
for name in $SID_READERS; do
  f="$HOOKS/$name.sh"
  [ -f "$f" ] || { no "$name.sh exists" "$f"; continue; }
  if grep -q 'session_id "' "$f"; then
    ok "$name takes its session id from the library"
  else
    no "$name takes its session id from the library" "no session_id call in $f"
  fi
done

# ============================================================
echo ""
echo "=== 4 — one run predicate: no hook restates it, the run-scoped ones call it ==="
# ============================================================
#
# has_sdlc_state() was a five-copy family plus one merged reimplementation, and every
# one of them answered "is there a run" by restating the algorithm. The library answers
# it once. session-poker.sh is the last carrier and is named, not excused: slice POKER
# converts it, and this row is what notices if that never happens.
HS_CARRIERS=$(grep -ln '^has_sdlc_state()' "$HOOKS"/*.sh 2>/dev/null | xargs -n1 basename 2>/dev/null | sort | tr '\n' ' ' | sed 's/ $//')
expect_eq "session-poker.sh is the only hook still defining has_sdlc_state" \
  "session-poker.sh" "$HS_CARRIERS"

while IFS='|' read -r name class scoped; do
  [ -n "$name" ] || continue
  f="$HOOKS/$name.sh"
  [ -f "$f" ] || continue
  if grep -q 'active_run "' "$f"; then found=yes; else found=no; fi
  case "$scoped" in
    yes) expect_eq "$name gates on active_run" "yes" "$found" ;;
    no)  expect_eq "$name is NOT run-scoped and does not gate on active_run" "no" "$found" ;;
  esac
done <<EOF
$ADOPTED
EOF

# ============================================================
echo ""
echo "=== 5 — the predicate GATES: silent with no run, silent with a closed run, live with an open one ==="
# ============================================================

SID="ad0pt111-2222-3333-4444-555555555555"

# mk_root <name> <state>  -> a project root; state = none|closed|open
#   none   : a real directory, no .bionic anywhere above it (HOME is the sandbox)
#   closed : .bionic with a plan at `current: 9` carrying a delivered Step-9 line
#   open   : the same plan at `current: 4`
mk_root() {
  local name="$1" state="$2" root="$SANDBOX/roots/$name"
  mkdir -p "$root"
  [ "$state" = "none" ] && { printf '%s' "$root"; return 0; }
  mkdir -p "$root/.bionic/docs/plans/epic-99" "$root/.bionic/tmp"
  local cur="4" step9="- Step 9: (pending)"
  case "$state" in
    closed) cur="9"; step9="- Step 9: delivered: record/x.md" ;;
    # open9 is the evidence gate's control pair: the SAME plan as `closed`, one line
    # different. A run at step 9 without a `delivered:` line is still open (AC-8), and
    # the gate then has step-9 evidence to demand — so the two fixtures differ by
    # exactly the fact under test and nothing else.
    open9)  cur="9" ;;
  esac
  cat > "$root/.bionic/docs/plans/epic-99/wave-01.plan.md" <<PLAN
---
canonical_sdlc_version: 14
intent: build
rigor: audited
scale: wave
---

# fixture plan

## SDLC State

integration-branch: main
intent: build
rigor: audited
scale: wave
current: $cur

- Step 4: implementation
$step9
PLAN
  printf '%s' "$root"
}

# drive <hook> <payload-json> [extra-env...]  -> DRV_ST / DRV_OUT / DRV_ERR
drive() {
  local hook="$1" payload="$2"; shift 2
  DRV_OUT=$(printf '%s' "$payload" | env HOME="$SANDBOX/home" \
      BIONIC_PLUGINS_DIR="$SANDBOX/plugins" CLAUDE_CODE_SESSION_ID="$SID" \
      "$@" bash "$HOOKS/$hook.sh" 2>"$SANDBOX/.err")
  DRV_ST=$?
  DRV_ERR=$(cat "$SANDBOX/.err")
  return 0
}

mkdir -p "$SANDBOX/home" "$SANDBOX/plugins"

# A transcript the Stop-channel hooks can parse: one user prompt that IS a Patrol
# tick, and no duties after it — the shape patrol-duties-gate refuses.
TICK_TR="$SANDBOX/tick.jsonl"
printf '%s\n' \
  '{"type":"user","message":{"role":"user","content":"bash hooks/session-poker.sh tick"}}' \
  '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Read","input":{"file_path":"/x"}}],"usage":{"input_tokens":1000}}}' \
  > "$TICK_TR"

# payload_for <hook> <cwd> -> the smallest payload that reaches that hook's work
payload_for() {
  local hook="$1" cwd="$2"
  case "$hook" in
    canonical-sdlc-evidence-gate)
      jq -n --arg s "$SID" --arg c "$cwd" '{session_id:$s,cwd:$c,hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:"git commit -m wip"}}' ;;
    farm-out-reminder)
      jq -n --arg s "$SID" --arg c "$cwd" '{session_id:$s,cwd:$c,hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:"bash tests/run.sh"}}' ;;
    stop-guard)
      jq -n --arg s "$SID" --arg c "$cwd" '{session_id:$s,cwd:$c,hook_event_name:"PreToolUse",tool_name:"TaskStop",tool_input:{task_id:"w1-impl"}}' ;;
    execution-recorder)
      jq -n --arg s "$SID" --arg c "$cwd" '{session_id:$s,cwd:$c,hook_event_name:"SubagentStart",agent_id:"aaaaaaaa-1111-2222-3333-444444444444",agent_type:"implementor"}' ;;
    context-spend)
      jq -n --arg s "$SID" --arg c "$cwd" --arg t "$TICK_TR" '{session_id:$s,cwd:$c,transcript_path:$t,hook_event_name:"Stop"}' ;;
    patrol-duties-gate)
      jq -n --arg s "$SID" --arg c "$cwd" --arg t "$TICK_TR" '{session_id:$s,cwd:$c,transcript_path:$t,hook_event_name:"Stop",stop_hook_active:false}' ;;
    patrol-revive)
      jq -n --arg s "$SID" --arg c "$cwd" --arg t "$TICK_TR" '{session_id:$s,cwd:$c,transcript_path:$t,hook_event_name:"Stop",stop_hook_active:false}' ;;
    landing-gate)
      jq -n --arg s "$SID" --arg c "$cwd" --arg t "$TICK_TR" '{session_id:$s,cwd:$c,transcript_path:$t,hook_event_name:"Stop",stop_hook_active:false}' ;;
    dispatch-preflight)
      jq -n --arg s "$SID" --arg c "$cwd" '{session_id:$s,cwd:$c,hook_event_name:"PreToolUse",tool_name:"Agent",tool_input:{description:"d",subagent_type:"implementor",prompt:"Do the thing.\nExpected artifact: '"$cwd"'/.bionic/docs/record/x.md\n"}}' ;;
    canonical-sdlc-governing-skill)
      jq -n --arg s "$SID" --arg c "$cwd" --arg p "$cwd/.bionic/docs/plans/epic-99/wave-01.plan.md" '{session_id:$s,cwd:$c,hook_event_name:"PreToolUse",tool_name:"Write",tool_input:{file_path:$p,content:"x"}}' ;;
  esac
}

RUN_SCOPED='canonical-sdlc-evidence-gate farm-out-reminder stop-guard execution-recorder context-spend patrol-duties-gate patrol-revive landing-gate dispatch-preflight canonical-sdlc-governing-skill'

for hook in $RUN_SCOPED; do
  # (a) no .bionic anywhere -> exit 0, nothing on either stream
  r_none=$(mk_root "$hook-none" none)
  drive "$hook" "$(payload_for "$hook" "$r_none")"
  expect_eq "$hook: no .bionic -> exit 0" "0" "$DRV_ST"
  expect_empty "$hook: no .bionic -> no stdout" "$DRV_OUT"
  expect_empty "$hook: no .bionic -> no stderr" "$DRV_ERR"

  # (b) a root whose run is CLOSED -> exit 0, nothing on either stream
  r_closed=$(mk_root "$hook-closed" closed)
  # patrol-revive speaks only when a stale stamp exists; give it one so its
  # silence here is the run predicate's doing and not the stamp's absence.
  printf 'session_id=%s\nwritten_at=1\n' "$SID" > "$r_closed/.bionic/tmp/patrol-$SID.state"
  drive "$hook" "$(payload_for "$hook" "$r_closed")"
  expect_eq "$hook: closed run -> exit 0" "0" "$DRV_ST"
  expect_empty "$hook: closed run -> no stdout" "$DRV_OUT"
  expect_empty "$hook: closed run -> no stderr" "$DRV_ERR"

  # (c) ANTI-VACUITY: the same fixture with the run OPEN must NOT be silent —
  # a refusal, a nudge, a diagnostic or a state write, depending on the hook.
  open_state=open
  [ "$hook" = "canonical-sdlc-evidence-gate" ] && open_state=open9
  r_open=$(mk_root "$hook-open" "$open_state")
  printf 'session_id=%s\nwritten_at=1\n' "$SID" > "$r_open/.bionic/tmp/patrol-$SID.state"
  drive "$hook" "$(payload_for "$hook" "$r_open")"
  wrote=""
  [ -n "$(ls -A "$r_open/.bionic/tmp" 2>/dev/null | grep -v "^patrol-" || true)" ] && wrote="state"
  if [ "$DRV_ST" -ne 0 ] || [ -n "$DRV_OUT" ] || [ -n "$DRV_ERR" ] || [ -n "$wrote" ]; then
    ok "$hook: OPEN run -> the hook does something (control: the gate above is not vacuous)"
  else
    no "$hook: OPEN run -> the hook does something (control: the gate above is not vacuous)" \
       "exit $DRV_ST, no output, no state written — the silence assertions above prove nothing"
  fi
done

# ============================================================
echo ""
echo "=== 6 — a missing library: refused by cost, never by uniformity ==="
# ============================================================
#
# The lockout this wave is named for (R-1 §5): a wall that refused everything had no
# way to permit the very commands that would repair it, so a broken publish locked
# the user out of `claude plugin update`. The four permitted commands are matched as
# WHOLE STRINGS, checked before the wall touches a library.

# A plugin tree with hooks/ but no scripts/lib anywhere, and an empty registry:
# every loader candidate class fails.
BROKEN="$SANDBOX/broken-plugin"
mkdir -p "$BROKEN/hooks" "$SANDBOX/plugins-empty"
for h in protect-main canonical-sdlc-evidence-gate landing-gate; do
  cp "$HOOKS/$h.sh" "$BROKEN/hooks/$h.sh"
done

drive_broken() {  # <hook> <payload>
  DRV_OUT=$(printf '%s' "$2" | env HOME="$SANDBOX/home" \
      BIONIC_PLUGINS_DIR="$SANDBOX/plugins-empty" CLAUDE_CODE_SESSION_ID="$SID" \
      bash "$BROKEN/hooks/$1.sh" 2>"$SANDBOX/.err")
  DRV_ST=$?
  DRV_ERR=$(cat "$SANDBOX/.err")
  return 0
}
bash_payload() {  # <command>
  jq -n --arg s "$SID" --arg c "$SANDBOX" --arg m "$1" \
    '{session_id:$s,cwd:$c,hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$m}}'
}

# CLOSED CLASS, refusing: a push the wall can no longer read.
for h in protect-main canonical-sdlc-evidence-gate; do
  drive_broken "$h" "$(bash_payload 'git push origin main')"
  expect_eq "$h with no library refuses a push (exit 2)" "2" "$DRV_ST"
  expect_contains "…naming the repair verb" "claude plugin update bionic@bionic" "$DRV_ERR"
  expect_contains "…and the install verb" "claude plugin install bionic@bionic" "$DRV_ERR"
  expect_contains "…and doctor" "bash $BROKEN/scripts/doctor.sh" "$DRV_ERR"
  expect_contains "…and setup" "bash $BROKEN/scripts/setup.sh" "$DRV_ERR"

  # CLOSED CLASS, permitting: the repair itself, whole-string matched.
  drive_broken "$h" "$(bash_payload "bash $BROKEN/scripts/doctor.sh")"
  expect_eq "$h with no library PERMITS the doctor repair (exit 0)" "0" "$DRV_ST"
  expect_empty "…silently" "$DRV_ERR"

  # …and only as a whole string: a repair with a push chained after it is a push.
  drive_broken "$h" "$(bash_payload "bash $BROKEN/scripts/doctor.sh; git push origin main")"
  expect_eq "$h refuses the repair with a command chained after it" "2" "$DRV_ST"
done

# OPEN CLASS: one line on stderr, exit 0, nothing on stdout.
drive_broken landing-gate "$(jq -n --arg s "$SID" --arg c "$SANDBOX" --arg t "$TICK_TR" \
  '{session_id:$s,cwd:$c,transcript_path:$t,hook_event_name:"Stop",stop_hook_active:false}')"
expect_eq "landing-gate with no library steps aside (exit 0)" "0" "$DRV_ST"
expect_empty "…writing nothing to stdout" "$DRV_OUT"
expect_eq "…and exactly one line on stderr" "1" "$(printf '%s\n' "$DRV_ERR" | grep -c .)"
expect_contains "…naming what it could not find" "library" "$DRV_ERR"
expect_contains "…and where to go next" "/bionic:doctor" "$DRV_ERR"

echo ""
echo "========================================"
echo "hook-adoption: $PASS/$TOTAL passed"
echo "========================================"
[ "$FAIL" -eq 0 ]
