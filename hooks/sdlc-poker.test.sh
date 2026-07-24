#!/bin/bash
# Fixture suite for hooks/sdlc-poker.sh — slice 4/1 (poker core):
# consent-registry reading (C1), P3 registry-primary classification (C2),
# run discipline (lock / audit / status / state-cache, C8).
#
# Harness idiom mirrors hooks/context-spend.test.sh: PASS/FAIL counters, a
# fresh fake $HOME per case (mktemp), a PATH-shadowed stub `claude` binary
# that serves canned `agents --json` registry states from files under
# $HOME/.claude/.stub/, and planted registrations/plans/transcripts with
# controlled mtimes. The registry JSON shape replicates the live 2.1.216
# samples in .bionic/docs/spikes/spike-{dead-vs-busy,cron-env}-20260721.md:
# per-session objects with pid/cwd/kind/sessionId/name and a `status`
# (busy|idle) that print (`-p`) children omit entirely (NOSTATUS).
#
# The suite SOURCES the poker with SDLC_POKER_LIB=1 (main suppressed) so
# classify_goal can be called directly on a planted goal (cases 1-7, 11), and
# runs the whole script as a fresh child (run_poker) for the run-discipline
# cases (8-10, 12) that exercise the main loop, arming filter, and lock.
#
# Usage: bash hooks/sdlc-poker.test.sh

set -uo pipefail

POKER="$(cd "$(dirname "$0")" && pwd)/sdlc-poker.sh"
ORIG_PATH="$PATH"
PASS=0; FAIL=0; TOTAL=0
CLEAN_HOMES=()

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; [ -n "${2:-}" ] && echo "  $2"; FAIL=$((FAIL + 1)); }

cleanup() { for d in "${CLEAN_HOMES[@]:-}"; do [ -n "$d" ] && rm -rf "$d"; done; }
trap cleanup EXIT

# Source the library (functions only; main suppressed). classify_goal becomes
# callable; QUIET_THRESHOLD/WEDGE_QUIET/POKE_CAP land in scope. HOME is re-pointed
# per case AFTER this, and every poker function reads $HOME at call time, so the
# single source is safe across cases. Transcript planting uses this suite's OWN
# real_project_dir sanitizer (below) — the poker no longer maps cwd→dir at all
# (it globs by session id), so the harness must derive the realistic path itself.
SDLC_POKER_LIB=1 . "$POKER"

# Also source the durable-state lib directly, so the slice-4/4 fixtures can plant
# batons/ledgers (baton_write/baton_path/ledger_path/ledger_applied) INDEPENDENTLY
# of whether the poker sources it — the RED phase must be able to plant these
# before the integration lands. The poker's own sourcing (the integration under
# test) is exercised by run_poker children below, never by this line.
STATE_LIB="$(cd "$(dirname "$0")" && pwd)/sdlc-state-lib.sh"
. "$STATE_LIB"

# ---------- fresh fake HOME + PATH-shadowed stub claude / curl ----------
# The claude stub serves canned `agents --json` registry states AND records the
# POKE (argv → claude-calls.log, stdin → claude-stdin.log, cwd → claude-cwd.log),
# honoring an optional exit code (poke.rc) so a failing poke can be planted. The
# curl stub records the ntfy POST (argv → curl-calls.log), honoring curl.rc.
new_home() {
  HOME=$(mktemp -d); export HOME
  mkdir -p "$HOME/.claude/sdlc-goals" "$HOME/.claude/sdlc-status" "$HOME/.claude/.stub"
  cat > "$HOME/.claude/.stub/claude" <<'STUB'
#!/bin/sh
STUBDIR="$HOME/.claude/.stub"
if [ "$1" = "agents" ]; then
  echo call >> "$STUBDIR/registry-calls.log"   # e09 fold: count invocations (AC-C7)
  rc=0
  [ -f "$STUBDIR/registry.rc" ] && rc=$(cat "$STUBDIR/registry.rc")
  [ -f "$STUBDIR/registry.json" ] && cat "$STUBDIR/registry.json"
  exit "$rc"
fi
# POKE path: capture argv, cwd, stdin, and whether the OAuth token reached this
# child (F1); honor planted stderr (F3), a per-call transcript append (F2, models
# the live "Not logged in" turn write), and an exit code.
echo "$*" >> "$STUBDIR/claude-calls.log"
pwd >> "$STUBDIR/claude-cwd.log"
cat >> "$STUBDIR/claude-stdin.log"
if [ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]; then
  echo present >> "$STUBDIR/claude-token.log"
else
  echo absent >> "$STUBDIR/claude-token.log"
fi
[ -f "$STUBDIR/poke.stdout" ] && cat "$STUBDIR/poke.stdout"
[ -f "$STUBDIR/poke.stderr" ] && cat "$STUBDIR/poke.stderr" >&2
if [ -f "$STUBDIR/poke-append" ]; then
  tp=$(cat "$STUBDIR/poke-append")
  printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"text"}]}}' >> "$tp"
fi
# F3: model a HUNG poke — real foreground work (NOT a leading sleep, which the
# harness blocks), self-bounded (~8s) so a poker WITHOUT the timeout wrapper does
# not hang the suite (it finishes late, rc=0). With the perl-alarm wrapper and a
# small POKE_TIMEOUT the child is SIGALRM-killed first → rc=142 → POKE-TIMEOUT.
if [ -f "$STUBDIR/poke-block" ]; then
  _end=$(( $(date +%s) + 8 ))
  while [ "$(date +%s)" -lt "$_end" ]; do : ; done
fi
prc=0
[ -f "$STUBDIR/poke.rc" ] && prc=$(cat "$STUBDIR/poke.rc")
exit "$prc"
STUB
  chmod +x "$HOME/.claude/.stub/claude"
  cat > "$HOME/.claude/.stub/curl" <<'STUB'
#!/bin/sh
STUBDIR="$HOME/.claude/.stub"
echo "$*" >> "$STUBDIR/curl-calls.log"
crc=0
[ -f "$STUBDIR/curl.rc" ] && crc=$(cat "$STUBDIR/curl.rc")
exit "$crc"
STUB
  chmod +x "$HOME/.claude/.stub/curl"
  export PATH="$HOME/.claude/.stub:$ORIG_PATH"
  export BIONIC_NTFY_TOPIC="test-secret-topic-$$"   # secret; must never reach audit/status
  CLEAN_HOMES+=("$HOME")
}

# ---------- fixture planters ----------
# plant_goal <gid> <plan> <cwd> <sid> <pid> [drop-key]
plant_goal() {
  local gid="$1" plan="$2" cwd="$3" sid="$4" pid="$5" drop="${6:-}"
  local f="$HOME/.claude/sdlc-goals/$gid"; mkdir -p "$(dirname "$f")"
  {
    [ "$drop" = "PLAN" ]       || echo "PLAN=$plan"
    [ "$drop" = "CWD" ]        || echo "CWD=$cwd"
    [ "$drop" = "SESSION_ID" ] || echo "SESSION_ID=$sid"
    [ "$drop" = "PID" ]        || echo "PID=$pid"
    [ "$drop" = "ARMED_AT" ]   || echo "ARMED_AT=2026-07-21T00:00:00Z"
  } > "$f"
}

# plant_plan <path> <current> [wake:0/1] [scale=continuous] [watchdog] [pilot]
# Empty/omitted watchdog ⇒ the key is ABSENT from frontmatter (fallback-table
# resolution applies) — mirrors write_plan's convention in sdlc-state-lib.test.sh.
plant_plan() {
  local p="$1" cur="$2" wake="${3:-0}" scale="${4:-continuous}" wd="${5:-}" pilot="${6:-}"
  mkdir -p "$(dirname "$p")"
  {
    echo "---"
    echo "governing-skill: superpowers:writing-plans"
    echo "canonical_sdlc_version: 12"
    echo "scale: $scale"
    [ -n "$wd" ] && echo "watchdog: $wd"
    [ -n "$pilot" ] && echo "pilot: $pilot"
    echo "---"
    echo ""
    echo "## SDLC State"
    echo ""
    echo "current: $cur"
    echo ""
    if [ "$wake" = "1" ]; then
      echo "## Wake Note"
      echo ""
      echo "blocked on decision X — stopping."
      echo ""
    fi
    echo "- G1: evidence"
  } > "$p"
}

# set_mtime_age <file> <seconds-ago>  (BSD date first, GNU fallback)
set_mtime_age() {
  local f="$1" age="$2" ts
  if ts=$(date -v-"${age}"S +%Y%m%d%H%M.%S 2>/dev/null); then
    touch -t "$ts" "$f"
  else
    touch -d "@$(( $(date +%s) - age ))" "$f"
  fi
}

# Claude Code's project-dir sanitizer, implemented INDEPENDENTLY of the poker (the
# poker no longer maps cwd→dir — it globs by session id): the FULL cwd with every
# [^a-zA-Z0-9] replaced by '-'. Used only to PLANT transcripts at realistic paths;
# the sid-glob resolver finds them by session id regardless of the dir name.
real_project_dir() {
  printf '%s/.claude/projects/%s' "$HOME" "$(printf '%s' "$1" | sed 's/[^a-zA-Z0-9]/-/g')"
}

# plant_transcript_age <cwd> <sid> <age-seconds> [last-event: user|busy]
# Writes the session transcript under the REAL (independently sanitized) Claude
# project dir and back-dates its mtime. The poker resolves it by SESSION-ID GLOB,
# so the exact dir name is immaterial to resolution — only that the file is named
# <sid>.jsonl under some $HOME/.claude/projects/* dir.
plant_transcript_age() {
  local cwd="$1" sid="$2" age="$3" ev="${4:-user}"
  local pdir; pdir=$(real_project_dir "$cwd")
  mkdir -p "$pdir"
  local t="$pdir/$sid.jsonl"
  case "$ev" in
    busy) printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash"}]},"stop_reason":"tool_use"}' > "$t" ;;
    *)    printf '%s\n' '{"type":"user","message":{"role":"user","content":"continue"}}' > "$t" ;;
  esac
  set_mtime_age "$t" "$age"
}

# stub_registry_state <absent|busy|idle|nostatus|fail> [sid]
stub_registry_state() {
  local kind="$1" sid="${2:-}"
  local f="$HOME/.claude/.stub/registry.json"
  local rcf="$HOME/.claude/.stub/registry.rc"
  echo 0 > "$rcf"
  case "$kind" in
    absent)  # registry non-empty but the target sid is NOT in it (by-id lookup)
      printf '[{"pid":11,"cwd":"/other","kind":"interactive","sessionId":"decoy-sid","status":"idle","name":"d"}]\n' > "$f" ;;
    fail)    printf '' > "$f"; echo 1 > "$rcf" ;;
    busy)    printf '[{"pid":4242,"cwd":"/x","kind":"interactive","sessionId":"%s","status":"busy","name":"t"}]\n' "$sid" > "$f" ;;
    idle)    printf '[{"pid":4242,"cwd":"/x","kind":"interactive","sessionId":"%s","status":"idle","name":"t"}]\n' "$sid" > "$f" ;;
    nostatus)printf '[{"pid":4242,"cwd":"/x","kind":"interactive","sessionId":"%s","name":"t"}]\n' "$sid" > "$f" ;;
  esac
}

# ---------- runners / assertions ----------
# A poll: run the whole poker as a fresh child. POKE_CLAUDE_BIN points the
# absolute-binary poke at the stub (C4 uses /opt/homebrew/bin/claude, overridable
# exactly as the thresholds are — AS resolution logged in the report); the ntfy
# topic rides through as the standing-service identity would supply it.
run_poker() {
  POKER_OUT=$(HOME="$HOME" PATH="$HOME/.claude/.stub:$ORIG_PATH" \
    POKE_CLAUDE_BIN="$HOME/.claude/.stub/claude" \
    POKE_TIMEOUT="${POKE_TIMEOUT:-900}" \
    BIONIC_NTFY_TOPIC="${BIONIC_NTFY_TOPIC:-}" bash "$POKER" 2>&1); POKER_EXIT=$?
}

# A cron-faithful poll (F1): model the C7 entry's `. cron.env && poker`, but with
# NEITHER the token NOR the topic present in the invoking environment (env -u), and
# the cron.env sourced by the PARENT sh as PLAIN, non-exported KEY=value — so the
# parent-shell binding does NOT reach the poker child. Only the poker's own
# self-source (C8 amendment) can carry the identity through. No BIONIC_NTFY_TOPIC
# is injected here (unlike run_poker); the poker must self-source it.
run_poker_cron() {
  local cronenv="$HOME/.claude/cron.env"
  POKER_OUT=$(env -u BIONIC_NTFY_TOPIC -u CLAUDE_CODE_OAUTH_TOKEN \
    HOME="$HOME" PATH="$HOME/.claude/.stub:$ORIG_PATH" \
    POKE_CLAUDE_BIN="$HOME/.claude/.stub/claude" \
    /bin/sh -c '. "$1" && bash "$2"' sh "$cronenv" "$POKER" 2>&1); POKER_EXIT=$?
}

audit_of()  { cat "$HOME/.claude/sdlc-poker-audit.log" 2>/dev/null || true; }
status_of() { cat "$HOME/.claude/sdlc-status/$1.md" 2>/dev/null || true; }
status_exists() { [ -f "$HOME/.claude/sdlc-status/$1.md" ]; }
# Negated form for assert_true call sites (`assert_true "label" not_status_exists
# gid`). NOT `bash -c '! status_exists ...'` — that forks a separate bash process
# that never saw status_exists defined (no `export -f` in this suite), so the
# lookup 127s and `!` silently turns the "not found" failure into a vacuous
# pass. This wrapper runs status_exists in-process (a function call, not a
# fork+exec), so no propagation boundary is crossed at all.
not_status_exists() { ! status_exists "$1"; }
# 4/S6: registration-record presence (auto-clean assertions). Same in-process
# discipline as not_status_exists — no bash -c fork on an unexported function.
reg_exists() { [ -f "$HOME/.claude/sdlc-goals/$1" ]; }
not_reg_exists() { ! reg_exists "$1"; }
claude_calls() { cat "$HOME/.claude/.stub/claude-calls.log" 2>/dev/null || true; }
registry_calls() { cat "$HOME/.claude/.stub/registry-calls.log" 2>/dev/null || true; }
claude_stdin() { cat "$HOME/.claude/.stub/claude-stdin.log" 2>/dev/null || true; }
claude_cwd()   { cat "$HOME/.claude/.stub/claude-cwd.log" 2>/dev/null || true; }
claude_token() { cat "$HOME/.claude/.stub/claude-token.log" 2>/dev/null || true; }
curl_calls()   { cat "$HOME/.claude/.stub/curl-calls.log" 2>/dev/null || true; }
count_lines()  { printf '%s' "$1" | grep -c -e "$2" 2>/dev/null || true; }
# A real, existing cwd (the poke `cd`s into it) mapped like production paths.
real_cwd() { local d="$HOME/work/$1"; mkdir -p "$d"; printf '%s' "$d"; }

# A real GIT-REPO cwd (base commit on the default branch) — used by ladder
# fixtures so sdlc_ladder_anchor can read a real branch tip for the durable
# episode anchor (D-C2 amendment). Same $HOME/work location as real_cwd so the
# poke's `cd` still works.
ladder_cwd() {
  local d="$HOME/work/$1"; mkdir -p "$d"
  git -C "$d" init -q
  git -C "$d" config user.name fixture; git -C "$d" config user.email fixture@example.com
  printf 'base line\n' > "$d/f.txt"; git -C "$d" add -A; git -C "$d" commit -qm base >/dev/null 2>&1
  printf '%s' "$d"
}

assert_classify() {  # <gid> <expected> <label>
  TOTAL=$((TOTAL + 1))
  local got; got=$(classify_goal "$1")
  if [ "$got" = "$2" ]; then pass "$3 → $2"; else fail "$3" "expected='$2' got='$got'"; fi
}

assert_eq() {  # <label> <expected> <actual>
  TOTAL=$((TOTAL + 1))
  if [ "$3" = "$2" ]; then pass "$1"; else fail "$1" "expected='$2' actual='$3'"; fi
}

assert_true() {  # <label> <cmd...>
  local label="$1"; shift
  TOTAL=$((TOTAL + 1))
  if "$@"; then pass "$label"; else fail "$label"; fi
}
assert_contains() {  # <label> <needle> <haystack>
  TOTAL=$((TOTAL + 1))
  if printf '%s' "$3" | grep -qF -- "$2"; then pass "$1"; else fail "$1" "expected to contain '$2'"; fi
}

# A goal that is armed and classifiable: continuous plan + registration +
# a transcript at a chosen age. Returns nothing; sets fixture state.
arm_goal() {  # <gid> <cur> <cwd> <sid> <pid> <age> [event] [wake]
  local gid="$1" cur="$2" cwd="$3" sid="$4" pid="$5" age="$6" ev="${7:-user}" wake="${8:-0}"
  local plan="$HOME/plans/$gid.plan.md"
  plant_plan "$plan" "$cur" "$wake"
  plant_goal "$gid" "$plan" "$cwd" "$sid" "$pid"
  plant_transcript_age "$cwd" "$sid" "$age" "$ev"
}

# Seed a goal's wedge observation so the NEXT single poll corroborates under the
# active window (slice 4/S3): records the goal's pid, the CURRENT transcript byte
# size (the flat baseline the next poll must match), a flat cputime, and count=
# OBS-1. Mirrors the .poke priming idiom. Used by the downstream WEDGE-behavior
# fixtures whose intent is the post-detection ACTION (notify / no-poke / ladder
# observe), not the multi-poll detection itself — that is proven directly in the
# S3 detector cases. Defined here (beside arm_goal) so it precedes every caller.
prime_wedged() {  # <gid> [cpu]
  local gid="$1" cpu="${2:-0}" f pid sid t sz d
  f="$HOME/.claude/sdlc-goals/$gid"
  pid=$(sed -n 's/^PID=//p' "$f"); sid=$(sed -n 's/^SESSION_ID=//p' "$f")
  t=$(ls "$HOME"/.claude/projects/*/"$sid".jsonl 2>/dev/null | head -1)
  sz=$(wc -c < "$t" 2>/dev/null | tr -d ' '); [ -n "$sz" ] || sz=none
  d="$HOME/.claude/sdlc-status/.state"; mkdir -p "$d"
  printf '%s %s %s %s\n' "$pid" "$sz" "$cpu" "$(( ${SDLC_WEDGE_OBS:-3} - 1 ))" > "$d/$gid.wedge"
}

# ---------- slice 4/4: baton / ledger fixture helpers ----------
# plant_baton <gid> <next-action> — a well-formed baton ALIGNED to the goal's
# registered repo+plan (read from the consent registration planted by arm_goal),
# so sdlc_ladder_anchor derives a real durable-progress digest. The branch/tip
# come from the registered cwd when it is a git repo (ladder_cwd); for a
# non-repo cwd (a goal that never ladders) git fails gracefully and the baton
# still parses. next-action rides verbatim; grammar-gated fields stay `none`.
plant_baton() {  # <gid> <next-action>
  local gid="$1" na="$2" f plan cwd br tip
  f="$HOME/.claude/sdlc-goals/$gid"
  plan=$(sed -n 's/^PLAN=//p' "$f"); cwd=$(sed -n 's/^CWD=//p' "$f")
  br=$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null || echo main)
  tip=$(git -C "$cwd" rev-parse HEAD 2>/dev/null || printf '%040d' 1)
  baton_write "$gid" "$plan" "$cwd" "$br" "epic-x" "$tip" 4 "sid-$gid" none "$na" none none >/dev/null 2>&1
}

# The DURABLE-PROGRESS episode anchor for a planted goal (D-C2 amendment) —
# derived EXACTLY as the poker's ladder_dispatch does, from the goal's
# registration plan+cwd + baton (never transcript mtime). Requires the goal's
# baton to be present.
anchor_of() {  # <gid>
  local gid="$1" f plan cwd
  f="$HOME/.claude/sdlc-goals/$gid"
  plan=$(sed -n 's/^PLAN=//p' "$f"); cwd=$(sed -n 's/^CWD=//p' "$f")
  sdlc_ladder_anchor "$gid" "$plan" "$cwd" 2>/dev/null
}

# A ledger line of a given type+key present for a goal? (decision/effect membership)
ledger_line_has() {  # <gid> <type> <effect-key>
  awk -F'\t' -v t="$2" -v k="$3" '$4==t && $5==k {f=1} END{exit(f?0:1)}' \
    "$(ledger_path "$1")" 2>/dev/null
}

# Count effect-type rung lines for a goal (episode progress, anchor-agnostic).
rung_effect_count() {  # <gid>
  awk -F'\t' -v g="$1" '$4=="effect" && $5 ~ ("^rung:" g ":") {n++} END{print n+0}' \
    "$(ledger_path "$1")" 2>/dev/null || echo 0
}

# ---------- 4/S5: restart-seam stubs (the SIGTERM + spawn live in the lib) ----------
# arm_restart_seams — arms the lib's restart seams for a full poker poll so a real
# `claude` is never launched and no real process is signalled: a kill stub records
# the SIGTERM and DROPS the target from the registry.json the `claude agents` stub
# reads (the vehicle "dies" for the bounded re-poll), plus a synchronous spawn
# counter. Exports SDLC_KILL_CMD / SDLC_SPAWN_CMD / SDLC_RESTART_KILL_DELAY for the
# poker child (run_poker's inline env augments, not replaces, the inherited env).
RESTART_SPAWN_COUNTER=""; RESTART_KILL_LOG=""
arm_restart_seams() {
  local regjson="$HOME/.claude/.stub/registry.json"
  RESTART_KILL_LOG="$HOME/.claude/.stub/kill.log"; : > "$RESTART_KILL_LOG"
  RESTART_SPAWN_COUNTER="$HOME/.claude/.stub/spawn.count"; : > "$RESTART_SPAWN_COUNTER"
  local kstub="$HOME/.claude/.stub/killcmd"
  {
    printf '#!/bin/sh\n'
    printf 'echo "term $1" >> %q\n' "$RESTART_KILL_LOG"
    printf 'printf "[{\\"pid\\":11,\\"sessionId\\":\\"decoy-sid\\",\\"status\\":\\"idle\\"}]\\n" > %q\n' "$regjson"
    printf 'exit 0\n'
  } > "$kstub"; chmod +x "$kstub"
  local sstub="$HOME/.claude/.stub/spawncmd"
  printf '#!/bin/sh\nprintf x >> %q\nexit 0\n' "$RESTART_SPAWN_COUNTER" > "$sstub"; chmod +x "$sstub"
  export SDLC_KILL_CMD="$kstub" SDLC_SPAWN_CMD="$sstub" SDLC_RESTART_KILL_DELAY=0
}
disarm_restart_seams() { unset SDLC_KILL_CMD SDLC_SPAWN_CMD SDLC_RESTART_KILL_DELAY; }
restart_spawn_count() { [ -s "$RESTART_SPAWN_COUNTER" ] && wc -c < "$RESTART_SPAWN_COUNTER" | tr -d ' ' || echo 0; }
restart_term_count()  { [ -s "$RESTART_KILL_LOG" ] && grep -c . "$RESTART_KILL_LOG" | tr -d ' ' || echo 0; }

# ADR-002 Decision 2a: signal wrappers sanctioned on the poker's own poke
# path only — the perl alarm-exec idiom may appear inside do_poke's body and
# nowhere else. Extracts do_poke's own line range (function-boundary awk) and
# returns any 'alarm' hits found outside it; empty output means confined.
alarm_confined_to_do_poke() {  # $1=poker script path
  local script="$1" range start end
  range=$(awk '
    /^do_poke\(\) \{/ { start = NR }
    start && /^}$/ { end = NR; exit }
    END { print start, end }
  ' "$script")
  start=${range%% *}; end=${range##* }
  if [ -z "$start" ] || [ -z "$end" ]; then
    echo "do_poke boundaries not found in $script"
    return
  fi
  grep -nE 'alarm' "$script" \
    | awk -F: -v s="$start" -v e="$end" '$1 < s || $1 > e { print }'
}

# plant_alarm_drift <in> <out>: writes a copy of the poker with an alarm-idiom
# mention inserted into dispatch_actions — OUTSIDE do_poke — proving
# alarm_confined_to_do_poke REDs when the signal-bearing pattern escapes its
# sanctioned function. Never touches the real script (agent-roles.test.sh
# drift-planter precedent: mutate a copy, never the source).
plant_alarm_drift() {
  awk '
    /^dispatch_actions\(\) \{/ && !done {
      print
      print "  # planted drift (meta-evidence): perl alarm-exec idiom outside do_poke"
      done = 1
      next
    }
    { print }
  ' "$1" > "$2"
}

# ============================================================
echo "=== Case 1: plan current:10 → COMPLETE regardless of session state ==="
c1() {
  new_home
  arm_goal g1 10 /proj/one sid-1 4242 30 user
  stub_registry_state busy sid-1
  assert_classify g1 COMPLETE "case1 charter-close current:10 (session busy)"
}
c1

echo "=== Case 2: plan has ## Wake Note → GATED (precedence over liveness) ==="
c2() {
  new_home
  arm_goal g2 4 /proj/two sid-2 4242 30 user 1
  stub_registry_state busy sid-2
  assert_classify g2 GATED "case2 wake-note present (session busy)"
}
c2

echo "=== Case 3: registry ABSENT by session-id → DEAD ==="
c3() {
  new_home
  # PID intentionally dead so ps corroboration agrees; registry omits the sid.
  arm_goal g3 4 /proj/three sid-3 2147483647 30 user
  stub_registry_state absent
  assert_classify g3 DEAD "case3 sid absent from registry"
}
c3

echo "=== Case 4: busy + quiet<WEDGE_QUIET → BUSY; quiet>WEDGE_QUIET ALONE → BUSY+WEDGE-OBSERVE (corroboration now required, 4/S3) ==="
c4() {
  new_home
  arm_goal g4 4 /proj/four sid-4 4242 200 busy
  stub_registry_state busy sid-4
  assert_classify g4 BUSY "case4 busy + quiet 200s (<540)"
  # Age the same transcript past WEDGE_QUIET. A SINGLE poll no longer WEDGES —
  # corroboration (SDLC_WEDGE_OBS polls, quiet>pilot ceiling, flat transcript+cpu)
  # is required (spec R4/AC-5). quiet 600 alone → BUSY, with a WEDGE-OBSERVE audit.
  plant_transcript_age /proj/four sid-4 600 busy
  local got; got=$(SDLC_WEDGE_CPU_FAKE=0 classify_goal g4)
  assert_eq "case4 busy + quiet 600s ALONE → BUSY (not yet corroborated)" "BUSY" "$got"
  assert_contains "case4 quiet>WEDGE_QUIET → WEDGE-OBSERVE audit" "g4 WEDGE-OBSERVE" "$(audit_of)"
}
c4

echo "=== Case 5: status:idle → IDLE_STALLED at >QUIET_THRESHOLD, IDLE at < ==="
c5() {
  new_home
  arm_goal g5 4 /proj/five sid-5 4242 200 user
  stub_registry_state idle sid-5
  assert_classify g5 IDLE_STALLED "case5 idle + quiet 200s (>180)"
  plant_transcript_age /proj/five sid-5 60 user
  assert_classify g5 IDLE "case5 idle + quiet 60s (<180)"
}
c5

echo "=== Case 6: registry present, no status field → BUSY (alive-working) ==="
c6() {
  new_home
  arm_goal g6 4 /proj/six sid-6 4242 30 busy
  stub_registry_state nostatus sid-6
  assert_classify g6 BUSY "case6 NOSTATUS print-child (quiet 30s)"
}
c6

echo "=== Case 7: quiet-never-dead — present + age 10000s → never DEAD ==="
c7() {
  new_home
  arm_goal g7 4 /proj/seven sid-7 4242 10000 user
  stub_registry_state idle sid-7
  TOTAL=$((TOTAL + 1))
  got=$(classify_goal g7)
  if [ "$got" != "DEAD" ] && [ "$got" = "IDLE_STALLED" ]; then
    pass "case7 present+10000s quiet → IDLE_STALLED, never DEAD"
  else
    fail "case7 quiet-never-dead" "got='$got' (must not be DEAD)"
  fi
}
c7

echo "=== Case 8: exclusive arming — both halves required ==="
c8() {
  # 8a: registration present but plan NOT scale:continuous → skipped (unarmed).
  new_home
  local plan="$HOME/plans/g8a.plan.md"
  plant_plan "$plan" 4 0 wave        # scale: wave, not continuous
  plant_goal g8a "$plan" /proj/8a sid-8a 4242
  plant_transcript_age /proj/8a sid-8a 30 user
  stub_registry_state idle sid-8a
  run_poker
  assert_eq "case8a non-continuous plan → poker exit 0" 0 "$POKER_EXIT"
  TOTAL=$((TOTAL + 1))
  if ! status_exists g8a; then pass "case8a unarmed (scale!=continuous) → no status written"; else fail "case8a unarmed" "status file present"; fi

  # 8b: continuous plan exists but NO registration → nothing to iterate.
  new_home
  plant_plan "$HOME/plans/g8b.plan.md" 4 0 continuous
  plant_transcript_age /proj/8b sid-8b 30 user
  stub_registry_state idle sid-8b
  run_poker
  assert_eq "case8b no registration → poker exit 0" 0 "$POKER_EXIT"
  TOTAL=$((TOTAL + 1))
  if ! status_exists g8b; then pass "case8b no registration → no status written"; else fail "case8b no registration" "status file present"; fi

  # 8c: both halves present → armed → classified → status written.
  new_home
  arm_goal g8c 4 /proj/8c sid-8c 4242 30 user
  stub_registry_state idle sid-8c
  run_poker
  assert_eq "case8c both halves → poker exit 0" 0 "$POKER_EXIT"
  TOTAL=$((TOTAL + 1))
  if status_exists g8c; then pass "case8c armed (both halves) → status written"; else fail "case8c armed" "no status file; out='$POKER_OUT'"; fi
}
c8

echo "=== Case 9: disarm — registration removed → next run takes no action ==="
c9() {
  new_home
  arm_goal g9 4 /proj/nine sid-9 4242 30 user
  stub_registry_state idle sid-9
  run_poker
  assert_true "case9 armed first run wrote status" status_exists g9
  local mt1; mt1=$(file_mtime "$HOME/.claude/sdlc-status/g9.md")
  sleep 1
  rm -f "$HOME/.claude/sdlc-goals/g9"        # disarm
  run_poker
  local mt2; mt2=$(file_mtime "$HOME/.claude/sdlc-status/g9.md")
  assert_eq "case9 disarmed goal not re-derived (status mtime unchanged)" "$mt1" "$mt2"
}
c9

echo "=== Case 10: malformed record (missing CWD) → MALFORMED-RECORD, continue ==="
c10() {
  new_home
  # A malformed goal (no CWD) and a healthy armed goal in the same run.
  local badplan="$HOME/plans/bad.plan.md" okplan="$HOME/plans/ok.plan.md"
  plant_plan "$badplan" 4 0 continuous
  plant_goal g10bad "$badplan" /proj/bad sid-bad 4242 CWD    # drop CWD
  arm_goal g10ok 4 /proj/ok sid-ok 4242 30 user
  stub_registry_state idle sid-ok
  run_poker
  assert_eq "case10 poker exit 0 despite malformed record" 0 "$POKER_EXIT"
  assert_contains "case10 MALFORMED-RECORD audit line for bad goal" "g10bad MALFORMED-RECORD" "$(audit_of)"
  assert_true "case10 run continued to the healthy goal (status written)" status_exists g10ok
}
c10

echo "=== Case 11: registry call fails → DEGRADE audit + ps/grammar fallback, exit 0 ==="
c11() {
  new_home
  # Live pid ($$ = this test process) so ps says alive; idle grammar, young age.
  arm_goal g11 4 /proj/eleven sid-11 "$$" 60 user
  stub_registry_state fail
  local got; got=$(classify_goal g11)
  assert_eq "case11 degrade path resolves via ps(alive)+grammar(idle) → IDLE" "IDLE" "$got"
  assert_contains "case11 DEGRADE audit line emitted" "g11 DEGRADE" "$(audit_of)"
}
c11

echo "=== Case 12: lock — concurrent run exits silently; stale lock reclaimed ==="
c12() {
  # 12a: a LIVE lock holder ($$) → second run exits 0 and does nothing.
  new_home
  arm_goal g12a 4 /proj/12a sid-12a 4242 30 user
  stub_registry_state idle sid-12a
  mkdir -p "$HOME/.claude/sdlc-poker.lock"; echo "$$" > "$HOME/.claude/sdlc-poker.lock/pid"
  run_poker
  assert_eq "case12a live lock → poker exit 0" 0 "$POKER_EXIT"
  TOTAL=$((TOTAL + 1))
  if ! status_exists g12a; then pass "case12a live lock → goal not processed (no status)"; else fail "case12a live lock" "status written despite held lock"; fi

  # 12b: a STALE lock (dead pid) → reclaimed, goal processed.
  new_home
  arm_goal g12b 4 /proj/12b sid-12b 4242 30 user
  stub_registry_state idle sid-12b
  mkdir -p "$HOME/.claude/sdlc-poker.lock"; echo 2147483647 > "$HOME/.claude/sdlc-poker.lock/pid"
  run_poker
  assert_eq "case12b stale lock → poker exit 0" 0 "$POKER_EXIT"
  assert_true "case12b stale lock reclaimed → goal processed (status written)" status_exists g12b
}
c12

# ============================================================
# ===================  slice 4/2 — actions  ==================
# poke (C4), retry-cap episodes, ntfy transitions (C5), no-force wedge (C3).

echo "=== 4/2-1: DEAD armed goal → poke via stdin, absolute binary, cd-first, no --model ==="
p1() {
  new_home
  local cwd; cwd=$(real_cwd d1)
  arm_goal ad1 4 "$cwd" sid-d1 2147483647 30 user   # dead pid; registry absent → DEAD
  stub_registry_state absent
  run_poker
  assert_eq "4/2-1 poker exit 0" 0 "$POKER_EXIT"
  assert_contains "4/2-1 poke argv: --resume <sid> -p" "--resume sid-d1 -p" "$(claude_calls)"
  assert_contains "4/2-1 poke argv: --dangerously-skip-permissions" "--dangerously-skip-permissions" "$(claude_calls)"
  TOTAL=$((TOTAL + 1))
  if ! printf '%s' "$(claude_calls)" | grep -q -- '--model'; then
    pass "4/2-1 no --model override in poke argv"
  else fail "4/2-1 no --model" "argv='$(claude_calls)'"; fi
  assert_contains "4/2-1 POKE_PROMPT arrived via stdin" "continue per the plan" "$(claude_stdin)"
  assert_contains "4/2-1 POKE_PROMPT carries the gate escape hatch" "if blocked on a decision" "$(claude_stdin)"
  local exp; exp=$(cd "$cwd" 2>/dev/null && pwd)
  assert_eq "4/2-1 poke ran cd-first in CWD" "$exp" "$(claude_cwd)"
  assert_true "4/2-1 script pins the absolute poke binary" grep -q "/opt/homebrew/bin/claude" "$POKER"
}
p1

echo "=== 4/2-2: IDLE_STALLED with a live TUI (status idle) → SKIP-LIVE-TUI, zero poke (KA-R13); IDLE (fresh) → zero invocations ==="
p2() {
  new_home
  local cwd; cwd=$(real_cwd d2)
  arm_goal as2 4 "$cwd" sid-s2 4242 200 user   # idle + 200s → IDLE_STALLED; status idle = live TUI = attended
  stub_registry_state idle sid-s2
  run_poker
  assert_eq "4/2-2 IDLE_STALLED + live TUI → ZERO poke (presence rule bars drive)" "" "$(claude_calls)"
  assert_contains "4/2-2 IDLE_STALLED + live TUI → SKIP-LIVE-TUI audited" "as2 SKIP-LIVE-TUI" "$(audit_of)"
  new_home
  cwd=$(real_cwd d2b)
  arm_goal ai2 4 "$cwd" sid-i2 4242 60 user    # idle + 60s → IDLE (fresh)
  stub_registry_state idle sid-i2
  run_poker
  assert_eq "4/2-2 IDLE (fresh) → zero poke invocations" "" "$(claude_calls)"
}
p2

echo "=== 4/2-3: BUSY → SKIP-BUSY, no poke; WEDGED → no poke, no kill, target alive ==="
p3() {
  new_home
  local cwd; cwd=$(real_cwd d3)
  arm_goal ab3 4 "$cwd" sid-b3 4242 60 busy    # busy + 60s → BUSY
  stub_registry_state busy sid-b3
  run_poker
  assert_eq "4/2-3 BUSY → zero poke invocations" "" "$(claude_calls)"
  assert_contains "4/2-3 SKIP-BUSY audit line" "ab3 SKIP-BUSY" "$(audit_of)"

  new_home
  cwd=$(real_cwd d3w)
  # busy + quiet>ceiling + a primed corroboration (as if OBS-1 prior flat polls) →
  # this single poll corroborates WEDGED (4/S3). Flat cputime via the seam.
  arm_goal aw3 4 "$cwd" sid-w3 "$$" 1000 busy  # live pid == this process
  stub_registry_state busy sid-w3
  prime_wedged aw3 0
  export SDLC_WEDGE_CPU_FAKE=0
  run_poker
  unset SDLC_WEDGE_CPU_FAKE
  assert_eq "4/2-3 WEDGED → zero claude poke invocations" "" "$(claude_calls)"
  TOTAL=$((TOTAL + 1))
  if ps -p "$$" >/dev/null 2>&1; then pass "4/2-3 WEDGE target pid still alive (never signalled)"; else fail "4/2-3 target alive"; fi
  # No kill/pkill/killall INVOCATION in the script; comments and the recovery-
  # command STRING (the single printf template) are the only permitted mentions.
  TOTAL=$((TOTAL + 1))
  local hits
  hits=$(grep -nE '(kill|pkill|killall)' "$POKER" \
    | grep -vE ':[[:space:]]*#' \
    | grep -vF "printf 'kill %s && cd %s && claude --resume %s'")
  if [ -z "$hits" ]; then pass "4/2-3 no kill/pkill/killall invocation in script"; else fail "4/2-3 no-kill" "offenders: $hits"; fi

  # ADR-002 Decision 2a: signal wrappers sanctioned on the poker's own poke
  # path only — assert the alarm-exec idiom never escapes do_poke.
  TOTAL=$((TOTAL + 1))
  local alarm_hits; alarm_hits=$(alarm_confined_to_do_poke "$POKER")
  if [ -z "$alarm_hits" ]; then pass "4/2-3 alarm-wrapper confined to do_poke (ADR-002 D2a)"; else fail "4/2-3 alarm-wrapper escaped do_poke" "offenders: $alarm_hits"; fi

  # Meta-evidence: a planted alarm mention OUTSIDE do_poke (in dispatch_actions,
  # on a tmp copy — the shipped poker is never mutated) must make the guard
  # above go RED, proving it actually enforces the boundary.
  TOTAL=$((TOTAL + 1))
  local drift_copy; drift_copy=$(mktemp)
  plant_alarm_drift "$POKER" "$drift_copy"
  local drift_hits; drift_hits=$(alarm_confined_to_do_poke "$drift_copy")
  rm -f "$drift_copy"
  if [ -n "$drift_hits" ]; then pass "meta: alarm-wrapper-outside-do_poke drift detected"; else fail "meta: planted alarm drift NOT detected"; fi
}
p3

echo "=== 4/2-4: WEDGE notification (tui-less, no baton → legacy WEDGE notify) — Title + recovery command verbatim ==="
p4() {
  new_home
  local cwd; cwd=$(real_cwd d4)
  # status null (NOSTATUS) = a headless in-flight vehicle (tui-less), the ONLY
  # WEDGED shape the machine may act on. No baton planted → the legacy WEDGE
  # notification path (a real restart needs the ladder + baton).
  arm_goal aw4 4 "$cwd" sid-w4 31337 1000 busy  # WEDGED (primed+corroborated), known pid for recovery string
  stub_registry_state nostatus sid-w4
  prime_wedged aw4 0
  export SDLC_WEDGE_CPU_FAKE=0
  run_poker
  unset SDLC_WEDGE_CPU_FAKE
  assert_contains "4/2-4 WEDGE curl Title" "Title: aw4: WEDGE" "$(curl_calls)"
  assert_contains "4/2-4 WEDGE body carries recovery command verbatim" \
    "kill 31337 && cd $cwd && claude --resume sid-w4" "$(curl_calls)"
}
p4

echo "=== 4/2-5: GATED once; identical poll dedupes; driving→gated flip re-notifies ==="
p5() {
  new_home
  local cwd; cwd=$(real_cwd d5)
  local plan="$HOME/plans/ag5.plan.md"
  plant_plan "$plan" 4 1 continuous            # wake note → GATED
  plant_goal ag5 "$plan" "$cwd" sid-g5 4242
  plant_transcript_age "$cwd" sid-g5 60 user
  stub_registry_state busy sid-g5
  run_poker                                     # poll1: GATED transition → notify
  run_poker                                     # poll2: GATED again → dedupe
  assert_eq "4/2-5 GATED notified once across two identical polls" "1" "$(count_lines "$(curl_calls)" "GATED")"
  plant_plan "$plan" 4 0 continuous            # wake note gone → BUSY (driving)
  plant_transcript_age "$cwd" sid-g5 60 busy
  run_poker                                     # poll3: BUSY → no GATED curl
  plant_plan "$plan" 4 1 continuous            # wake note back → GATED
  plant_transcript_age "$cwd" sid-g5 60 user
  run_poker                                     # poll4: GATED transition again → notify #2
  assert_eq "4/2-5 GATED re-notified after driving→gated flip" "2" "$(count_lines "$(curl_calls)" "GATED")"
}
p5

echo "=== 4/2-6: COMPLETE once; registration retained (poker never disarms) ==="
p6() {
  new_home
  local cwd; cwd=$(real_cwd d6)
  arm_goal ac6 10 "$cwd" sid-c6 4242 60 user    # current:10 → COMPLETE
  stub_registry_state idle sid-c6
  run_poker
  assert_eq "4/2-6 COMPLETE notified once" "1" "$(count_lines "$(curl_calls)" "COMPLETE")"
  assert_true "4/2-6 registration retained" test -f "$HOME/.claude/sdlc-goals/ac6"
  run_poker
  assert_eq "4/2-6 COMPLETE deduped on second poll" "1" "$(count_lines "$(curl_calls)" "COMPLETE")"
}
p6

echo "=== 4/2-7: retry-cap — 3 pokes then POKE-FAIL; transcript movement resets episode ==="
p7() {
  new_home
  local cwd; cwd=$(real_cwd d7)
  arm_goal as7 4 "$cwd" sid-p7 2147483647 200 user    # DEAD (registry absent → tui-less, pokeable)
  stub_registry_state absent
  run_poker; run_poker; run_poker               # 3 pokes, same episode (stub never moves transcript)
  assert_eq "4/2-7 three pokes within the cap" "3" "$(count_lines "$(claude_calls)" "resume sid-p7")"
  run_poker                                      # 4th poll: cap exhausted
  assert_eq "4/2-7 no 4th poke after cap exhausted" "3" "$(count_lines "$(claude_calls)" "resume sid-p7")"
  assert_contains "4/2-7 POKE-FAIL notified on cap exhaustion" "Title: as7: POKE-FAIL" "$(curl_calls)"
  sleep 1  # mtime distinctness: same-age re-plant within one wall-clock second is byte-identical (c9 idiom); poke_capped resets only on mtime != smtime
  plant_transcript_age "$cwd" sid-p7 200 user   # fresh mtime = transcript movement
  run_poker
  assert_eq "4/2-7 episode reset on movement → poke resumes" "4" "$(count_lines "$(claude_calls)" "resume sid-p7")"
}
p7

echo "=== 4/2-8: a failing poke (exit nonzero) counts against the cap ==="
p8() {
  new_home
  local cwd; cwd=$(real_cwd d8)
  arm_goal as8 4 "$cwd" sid-p8 2147483647 200 user    # DEAD (registry absent → tui-less)
  stub_registry_state absent
  echo 1 > "$HOME/.claude/.stub/poke.rc"         # every poke exits nonzero
  run_poker; run_poker; run_poker
  assert_eq "4/2-8 three failing pokes counted" "3" "$(count_lines "$(claude_calls)" "resume sid-p8")"
  run_poker
  assert_eq "4/2-8 failing pokes count against cap (no 4th)" "3" "$(count_lines "$(claude_calls)" "resume sid-p8")"
  assert_contains "4/2-8 POKE-FAIL after failing pokes fill the cap" "Title: as8: POKE-FAIL" "$(curl_calls)"
}
p8

echo "=== 4/2-9: POKE_PROMPT contains no banned approval token (case-insensitive) ==="
p9() {
  new_home
  local cwd; cwd=$(real_cwd d9)
  arm_goal ap9 4 "$cwd" sid-b9 2147483647 30 user   # dead pid; registry absent → DEAD → poke
  stub_registry_state absent
  run_poker
  local stdin; stdin=$(claude_stdin)
  TOTAL=$((TOTAL + 1))
  if [ -n "$stdin" ] && ! printf '%s' "$stdin" \
     | grep -qiE 'approve|approved|approval|permission granted|yes to|go ahead with the gate|waiver'; then
    pass "4/2-9 POKE_PROMPT carries no banned approval token"
  else fail "4/2-9 banned-token scan" "stdin='$stdin'"; fi
}
p9

echo "=== 4/2-10: curl failure → NOTIFY-FAIL audit, exit 0, retry on next poll ==="
p10() {
  new_home
  local cwd; cwd=$(real_cwd d10)
  arm_goal ac10 10 "$cwd" sid-n10 4242 60 user   # COMPLETE → notifies
  stub_registry_state idle sid-n10
  echo 22 > "$HOME/.claude/.stub/curl.rc"         # curl fails (exit 22)
  run_poker
  assert_eq "4/2-10 poker exit 0 despite curl failure" 0 "$POKER_EXIT"
  assert_contains "4/2-10 NOTIFY-FAIL audit line" "ac10 NOTIFY-FAIL" "$(audit_of)"
  rm -f "$HOME/.claude/.stub/curl.rc"             # curl recovers
  run_poker
  assert_contains "4/2-10 notification retried on the next poll" "Title: ac10: COMPLETE" "$(curl_calls)"
}
p10

echo "=== 4/2-11: topic secrecy — \$BIONIC_NTFY_TOPIC never in audit log or status files ==="
p11() {
  new_home
  local cwd; cwd=$(real_cwd d11)
  # Exercise several notify + poke + wedge paths so every writer runs.
  arm_goal comp11 10 "$cwd" sid-cm 4242 60 user
  stub_registry_state idle sid-cm
  run_poker
  new_home
  cwd=$(real_cwd d11w)
  arm_goal wed11 4 "$cwd" sid-wd 4242 600 busy
  stub_registry_state busy sid-wd
  run_poker
  TOTAL=$((TOTAL + 1))
  if ! grep -rqF "$BIONIC_NTFY_TOPIC" "$HOME/.claude/sdlc-poker-audit.log" "$HOME/.claude/sdlc-status" 2>/dev/null; then
    pass "4/2-11 topic secret absent from audit log + status files"
  else fail "4/2-11 topic secrecy" "topic value leaked into audit/status"; fi
}
p11

# ============================================================
# ============  slice 4/3 — T3 walk findings  ================
# F1 env self-source (C8 amendment), F2 failure-aware retry-cap (C4 amendment),
# F3 stderr audit tail (C4 amendment). Root-cause evidence: .bionic/tmp/walk/walk.log
# (7 unbounded rc=1 pokes, no POKE-FAIL, stderr swallowed, "no ntfy topic").

echo "=== 4/3-1 (F1): poker self-sources cron.env → token reaches poke child, topic reaches notify ==="
f1() {
  new_home
  # cron.env with PLAIN (non-exported) KEY=value lines — the live file shape.
  {
    echo "CLAUDE_CODE_OAUTH_TOKEN=fake-oauth-token-value"
    echo "BIONIC_NTFY_TOPIC=fake-selfsourced-topic"
  } > "$HOME/.claude/cron.env"
  chmod 600 "$HOME/.claude/cron.env"
  local dcwd ccwd
  dcwd=$(real_cwd f1d); ccwd=$(real_cwd f1c)
  arm_goal f1dead 4  "$dcwd" sid-f1d 2147483647 30 user   # DEAD → poke (token check)
  arm_goal f1comp 10 "$ccwd" sid-f1c 4242         30 user   # COMPLETE → notify (topic check)
  stub_registry_state absent                                # sid-f1d absent → DEAD
  run_poker_cron
  assert_eq "4/3-1 poker exit 0 (cron-invoked, self-sourced)" 0 "$POKER_EXIT"
  assert_contains "4/3-1 OAuth token reached the poke child (self-sourced from cron.env)" \
    "present" "$(claude_token)"
  assert_contains "4/3-1 ntfy topic reached do_notify (curl POST carries self-sourced topic)" \
    "fake-selfsourced-topic" "$(curl_calls)"
  TOTAL=$((TOTAL + 1))
  if ! printf '%s' "$(claude_token)" | grep -qx absent; then
    pass "4/3-1 no poke child ever saw an absent token"
  else fail "4/3-1 token presence" "a poke child observed CLAUDE_CODE_OAUTH_TOKEN absent"; fi
}
f1

echo "=== 4/3-2 (F2): failure-aware cap — rc=1 pokes that MOVE the transcript still hit POKE_CAP ==="
# The rewritten proof for the recorded false-green: the pre-amendment episode was
# keyed on transcript mtime alone, so a persistently-failing poke's own turn write
# reset the episode every poll → unbounded pokes, POKE-FAIL never fired (live: 7/7).
f2() {
  new_home
  local cwd tpath; cwd=$(real_cwd fp2)
  arm_goal af2 4 "$cwd" sid-f2 2147483647 260 user    # DEAD (registry absent → tui-less, pokeable)
  stub_registry_state absent
  echo 1 > "$HOME/.claude/.stub/poke.rc"         # every poke fails (models "Not logged in")
  tpath="$(real_project_dir "$cwd")/sid-f2.jsonl"
  # Each poll: the failed poke's own turn lands as fresh transcript movement
  # (distinct, still-stale mtimes, all >QUIET_THRESHOLD so the goal stays IDLE_STALLED).
  local age
  for age in 250 240 230 220; do
    set_mtime_age "$tpath" "$age"
    run_poker
  done
  assert_eq "4/3-2 exactly POKE_CAP(3) pokes despite per-poll transcript movement" \
    "3" "$(count_lines "$(claude_calls)" "resume sid-f2")"
  assert_contains "4/3-2 POKE-FAIL fires (a failed poke's own write never resets the episode)" \
    "Title: af2: POKE-FAIL" "$(curl_calls)"
  set_mtime_age "$tpath" 210
  run_poker                                       # parked: still no poke after cap
  assert_eq "4/3-2 no further poke after cap (parked despite continued movement)" \
    "3" "$(count_lines "$(claude_calls)" "resume sid-f2")"
}
f2

echo "=== 4/3-3 (F3): rc!=0 POKE audit tail — combined stdout+stderr, trailing, truncated, scrubbed ==="
f3() {
  # 3a: the live failure ("Not logged in · Please run /login") rides STDOUT — the
  # -p result stream — with stderr empty (walk repro). Capturing stderr alone
  # would still be blind, so the audit tail must span the COMBINED stream.
  new_home
  local cwd; cwd=$(real_cwd fp3a)
  arm_goal af3a 4 "$cwd" sid-f3a 2147483647 30 user   # dead pid + registry absent → DEAD → poke
  stub_registry_state absent
  echo 1 > "$HOME/.claude/.stub/poke.rc"
  printf 'Not logged in - Please run /login (STDOUT-DISTINCTIVE)\n' > "$HOME/.claude/.stub/poke.stdout"
  run_poker
  assert_contains "4/3-3a live STDOUT failure line captured in the POKE audit tail" \
    "STDOUT-DISTINCTIVE" "$(audit_of)"

  # 3b: stderr is also captured; the tail is the TRAILING ~120 chars (the failure
  # reason surfaces at the end of the stream) and the topic secret is scrubbed.
  new_home
  cwd=$(real_cwd fp3b)
  arm_goal af3b 4 "$cwd" sid-f3b 2147483647 30 user
  stub_registry_state absent
  echo 1 > "$HOME/.claude/.stub/poke.rc"
  {
    printf 'LEADmarker '                               # far from the tail → truncated away
    head -c 140 < /dev/zero | tr '\0' x
    printf ' token=%s TRAILmarker\n' "$BIONIC_NTFY_TOPIC"   # inside the trailing tail
  } > "$HOME/.claude/.stub/poke.stderr"
  run_poker
  local audit havetrail; audit="$(audit_of)"
  assert_contains "4/3-3b stderr tail captured (trailing marker present)" "TRAILmarker" "$audit"
  # Truncation + scrub are gated on the trailing marker being present, so neither
  # passes vacuously if the stream is swallowed or the wrong end is kept.
  havetrail=no; printf '%s' "$audit" | grep -qF -- "TRAILmarker" && havetrail=yes
  TOTAL=$((TOTAL + 1))
  if [ "$havetrail" = yes ] && ! printf '%s' "$audit" | grep -qF -- "LEADmarker"; then
    pass "4/3-3b tail truncated to the trailing ~120 chars — LEADmarker dropped"
  else fail "4/3-3b truncation" "tail absent or leading content survived truncation"; fi
  TOTAL=$((TOTAL + 1))
  if [ "$havetrail" = yes ] && ! printf '%s' "$audit" | grep -qF -- "$BIONIC_NTFY_TOPIC"; then
    pass "4/3-3b topic secret scrubbed from the tail"
  else fail "4/3-3b secret scrub" "tail absent or topic value leaked into the audit line"; fi
}
f3

# ============================================================
# ============  slice 4/4 — step-6 review fold-ins  ==========
# F1 SESSION-ID GLOB transcript resolution (C2 amendment), F3 poke timeout
# (C4 amendment B), F4 goal-id validation (C1 addendum).

echo "=== 4/4-1 (F1): transcript resolved by SESSION-ID GLOB, not cwd→project-dir transform ==="
# false-green-2 rewrite. The retired harness planted transcripts via the poker's
# OWN project_dir_for_cwd, so its buggy [/.]-only mapping always "found" what it
# planted — grading the poker against its own mapping. Here the transcript is
# planted at the REAL Claude-Code path — the FULL cwd sanitized [^a-zA-Z0-9]→- —
# computed INDEPENDENTLY (hardcoded literal below, never via a poker function). An
# underscore-bearing cwd is exactly where the shipped transform silently diverged:
# it preserved '_', so it looked in the wrong project dir, the transcript went
# unfound, quiet collapsed to 0, and a real stall was misclassified IDLE (not
# IDLE_STALLED) — defeating stall/wedge detection.
f1_glob() {
  new_home
  local cwd="/tmp/bn_fix/my_proj" sid="sid-underscore-glob"
  # Independent hardcoded expected project dir (apply [^a-zA-Z0-9]→- BY HAND):
  #   /tmp/bn_fix/my_proj  →  -tmp-bn-fix-my-proj
  local realdir="$HOME/.claude/projects/-tmp-bn-fix-my-proj"
  mkdir -p "$realdir"
  local t="$realdir/$sid.jsonl"
  printf '%s\n' '{"type":"user","message":{"role":"user","content":"continue"}}' > "$t"
  set_mtime_age "$t" 300            # >180 → IDLE_STALLED iff the transcript is found
  local plan="$HOME/plans/uscore.plan.md"; plant_plan "$plan" 4 0 continuous
  plant_goal uscore "$plan" "$cwd" "$sid" 4242
  stub_registry_state idle "$sid"
  assert_classify uscore IDLE_STALLED "F1 underscore cwd: sid-glob finds real transcript → IDLE_STALLED"

  # Regression: an old-style (no-underscore) cwd — the [/.] transform and the real
  # [^a-zA-Z0-9] sanitizer agree here, so the glob subsumes the mapping and finds
  # the transcript by sid regardless of the project-dir name.
  local cwd2="/tmp/plain/proj" sid2="sid-plain-glob"
  local realdir2="$HOME/.claude/projects/-tmp-plain-proj"
  mkdir -p "$realdir2"
  local t2="$realdir2/$sid2.jsonl"
  printf '%s\n' '{"type":"user","message":{"role":"user","content":"continue"}}' > "$t2"
  set_mtime_age "$t2" 300
  local plan2="$HOME/plans/plain.plan.md"; plant_plan "$plan2" 4 0 continuous
  plant_goal plainx "$plan2" "$cwd2" "$sid2" 4242
  stub_registry_state idle "$sid2"
  assert_classify plainx IDLE_STALLED "F1 non-underscore cwd: sid-glob finds old-style path → IDLE_STALLED"
}
f1_glob

echo "=== 4/4-2 (F3): poke timeout — a hung poke is alarmed, POKE-TIMEOUT audited, counts to cap, lock released ==="
# A hung `claude --resume` otherwise holds the poker's own lock forever (every
# later poll sees a live holder and exits) → one hung poke stalls the whole relay.
# The perl-alarm wrapper SIGALRM-kills our own timed-out child (process hygiene,
# not the no-force verb — that protects TARGET sessions).
f3_timeout() {
  new_home
  local cwd; cwd=$(real_cwd f4t)
  arm_goal at4 4 "$cwd" sid-t4 2147483647 200 user     # DEAD (registry absent → tui-less, pokeable)
  stub_registry_state absent
  : > "$HOME/.claude/.stub/poke-block"           # stub busy-works past POKE_TIMEOUT
  POKE_TIMEOUT=2 run_poker                        # poll1: poke hangs → alarmed
  assert_eq "4/4-2 poker exits 0 after a timed-out poke (run completes, lock released)" 0 "$POKER_EXIT"
  assert_contains "4/4-2 POKE-TIMEOUT audit line emitted" "at4 POKE-TIMEOUT" "$(audit_of)"
  assert_contains "4/4-2 the timed-out poke was still attempted (argv recorded)" "--resume sid-t4" "$(claude_calls)"
  TOTAL=$((TOTAL + 1))
  if [ ! -d "$HOME/.claude/sdlc-poker.lock" ]; then pass "4/4-2 poker lock released after a timed-out poke"; else fail "4/4-2 lock leaked after timeout"; fi
  POKE_TIMEOUT=2 run_poker                        # poll2: count 2
  POKE_TIMEOUT=2 run_poker                        # poll3: count 3 (cap reached)
  POKE_TIMEOUT=2 run_poker                        # poll4: cap exhausted → POKE-FAIL, no poke
  assert_eq "4/4-2 timed-out pokes count toward POKE_CAP (exactly 3 attempts)" "3" "$(count_lines "$(claude_calls)" "resume sid-t4")"
  assert_contains "4/4-2 POKE-FAIL fires once the cap of timed-out pokes is exhausted" "Title: at4: POKE-FAIL" "$(curl_calls)"
  rm -f "$HOME/.claude/.stub/poke-block"

  # A fast rc=0 poke (no block) is unaffected by the timeout wrapper.
  new_home
  cwd=$(real_cwd f4f)
  arm_goal at4f 4 "$cwd" sid-t4f 2147483647 200 user   # DEAD (registry absent → tui-less)
  stub_registry_state absent
  POKE_TIMEOUT=2 run_poker
  assert_contains "4/4-2 a fast poke under the timeout succeeds (normal POKE rc=0 audit)" "resume sid-t4f rc=0" "$(audit_of)"
  TOTAL=$((TOTAL + 1))
  if ! printf '%s' "$(audit_of)" | grep -q "at4f POKE-TIMEOUT"; then pass "4/4-2 a fast poke never audits POKE-TIMEOUT"; else fail "4/4-2 fast poke wrongly timed out"; fi
}
f3_timeout

echo "=== 4/4-3 (F4): goal-id validation — filename must match ^[a-z0-9-]+\$; invalid → MALFORMED-RECORD + skip ==="
# ids reach paths and notification titles; harden the consent-registry boundary.
# The bad goal is otherwise WELL-FORMED (all keys, continuous plan) so ONLY the id
# check can reject it; a valid-id goal in the same run proves the run continues.
f4_id() {
  new_home
  local badplan="$HOME/plans/badid.plan.md"; plant_plan "$badplan" 4 0 continuous
  local bf="$HOME/.claude/sdlc-goals/Bad_ID!"
  {
    echo "PLAN=$badplan"; echo "CWD=/proj/badid"; echo "SESSION_ID=sid-badid"
    echo "PID=4242"; echo "ARMED_AT=2026-07-21T00:00:00Z"
  } > "$bf"
  arm_goal okid 4 /proj/okid sid-okid 4242 30 user
  stub_registry_state idle sid-okid
  run_poker
  assert_eq "4/4-3 poker exit 0 despite an invalid goal-id" 0 "$POKER_EXIT"
  assert_contains "4/4-3 MALFORMED-RECORD audit for the invalid goal-id" "Bad_ID! MALFORMED-RECORD" "$(audit_of)"
  TOTAL=$((TOTAL + 1))
  if [ ! -f "$HOME/.claude/sdlc-status/Bad_ID!.md" ]; then pass "4/4-3 invalid-id goal skipped (no status, never poked)"; else fail "4/4-3 invalid id was processed"; fi
  assert_true "4/4-3 run continued to the valid-id goal (status written)" status_exists okid
}
f4_id

# ============================================================
# ================  slice 4/1 — e09 perf folds  ==============
# Registry once-per-poll (was: once per goal), transcript memo (was: up to 4
# independent glob scans per goal), and the SDLC_REGISTRY_CMD seam (was:
# hardcoded `claude agents --json`). D-C8/AC-C7.

echo "=== 4/1-1 (e09): registry fetched ONCE per poll for a 3-goal poll, not once per goal ==="
e1() {
  new_home
  local c1 c2 c3
  c1=$(real_cwd e1a); c2=$(real_cwd e1b); c3=$(real_cwd e1c)
  arm_goal ge1a 4 "$c1" sid-e1a 4242 30 user
  arm_goal ge1b 4 "$c2" sid-e1b 4242 30 user
  arm_goal ge1c 4 "$c3" sid-e1c 4242 30 user
  stub_registry_state idle sid-e1a          # one stub registry.json serves all three lookups
  run_poker
  assert_eq "4/1-1 exactly one registry invocation for a 3-goal poll" \
    "1" "$(registry_calls | wc -l | tr -d ' ')"
}
e1

echo "=== 4/1-2 (e09): transcript resolved once per goal per poll (memoized across classify/status/poke-key) ==="
e2() {
  new_home
  mkdir -p "$(state_dir)"   # direct-call convention (bypassing main()); poke_capped needs it to exist
  local cwd; cwd=$(real_cwd e2)
  arm_goal ge2 4 "$cwd" sid-e2 2147483647 260 user   # registry absent → DEAD (pokeable, reaches poke-key)
  stub_registry_state absent
  _XSCRIPT_SID=""; _XSCRIPT_PATH=""; _XSCRIPT_SCANS=0   # clean baseline (global counter persists across cases)
  # load_registration runs DIRECTLY (not via `$(classify_goal ...)`, which would
  # fork a subshell and lose REG_* back-propagation) — mirrors process_goals's
  # own call order, so write_status below sees REG_PLAN/REG_SESSION_ID correctly.
  load_registration ge2
  local state; state=$(classify_goal ge2)
  write_status ge2 "$state"
  dispatch_actions ge2 "$state" ""                       # DEAD → poke_capped → transcript_mtime_key
  assert_eq "4/1-2 exactly one transcript resolution across classify_goal + write_status + poke-key derivation" \
    "1" "${_XSCRIPT_SCANS:-0}"
}
e2

echo "=== 4/1-3 (e09): SDLC_REGISTRY_CMD seam honored — the registry command is not hardcoded ==="
e3() {
  new_home
  local cwd; cwd=$(real_cwd e3)
  arm_goal ge3 4 "$cwd" sid-e3 4242 30 user   # fresh transcript (30s < QUIET_THRESHOLD 180)
  stub_registry_state absent                   # default stub: sid absent → would classify DEAD (poke)
  cat > "$HOME/.claude/.stub/altreg" <<'STUBEOF'
#!/bin/sh
echo call >> "$HOME/.claude/.stub/altreg-calls.log"
printf '[{"sessionId":"sid-e3","status":"idle"}]\n'
STUBEOF
  chmod +x "$HOME/.claude/.stub/altreg"
  export SDLC_REGISTRY_CMD="$HOME/.claude/.stub/altreg"
  run_poker
  unset SDLC_REGISTRY_CMD
  assert_eq "4/1-3 the SDLC_REGISTRY_CMD command was invoked once" \
    "1" "$(cat "$HOME/.claude/.stub/altreg-calls.log" 2>/dev/null | wc -l | tr -d ' ')"
  assert_eq "4/1-3 the default claude stub's agents branch was never consulted" \
    "0" "$(registry_calls | wc -l | tr -d ' ')"
  assert_contains "4/1-3 classification reflects the seam's IDLE, not the default stub's DEAD" \
    "state: idle" "$(status_of ge3)"
  assert_eq "4/1-3 no poke fired (IDLE via the seam, not DEAD via the default)" "" "$(claude_calls)"
}
e3

echo "=== 4/1-4 (e09): classification parity — the threaded (cached) call honors the passed snapshot, not a live re-fetch, across the full classification grid ==="
# Each sub-case snapshots the registry via the seam (json+rc), THEN drifts the
# LIVE registry to a state that would classify differently if classify_goal's
# threaded-args path secretly re-fetched instead of using what was passed —
# proving both parity (matches the literal expected token) and that the
# caching is real (not a coincidental match against unchanged live state).
e4() {
  # DEAD: snapshot has the sid absent; live drifts to present+idle.
  new_home
  local cwd json rc got
  cwd=$(real_cwd e4dead)
  arm_goal ge4dead 4 "$cwd" sid-e4dead 4242 30 user
  stub_registry_state absent
  json=$(claude agents --json 2>/dev/null); rc=$?
  stub_registry_state idle sid-e4dead
  got=$(classify_goal ge4dead "$json" "$rc")
  assert_eq "4/1-4 DEAD: honors the snapshot (absent), ignores the drifted live idle" "DEAD" "$got"

  # IDLE: snapshot idle + fresh transcript; live drifts to absent (would be DEAD).
  new_home
  cwd=$(real_cwd e4idle)
  arm_goal ge4idle 4 "$cwd" sid-e4idle 4242 30 user
  stub_registry_state idle sid-e4idle
  json=$(claude agents --json 2>/dev/null); rc=$?
  stub_registry_state absent
  got=$(classify_goal ge4idle "$json" "$rc")
  assert_eq "4/1-4 IDLE: honors the snapshot (idle+fresh), ignores the drifted live absent" "IDLE" "$got"

  # IDLE_STALLED: snapshot idle + stale transcript; live drifts to absent.
  new_home
  cwd=$(real_cwd e4stalled)
  arm_goal ge4stalled 4 "$cwd" sid-e4stalled 4242 200 user
  stub_registry_state idle sid-e4stalled
  json=$(claude agents --json 2>/dev/null); rc=$?
  stub_registry_state absent
  got=$(classify_goal ge4stalled "$json" "$rc")
  assert_eq "4/1-4 IDLE_STALLED: honors the snapshot, ignores the drifted live absent" "IDLE_STALLED" "$got"

  # BUSY: snapshot busy + fresh; live drifts to absent.
  new_home
  cwd=$(real_cwd e4busy)
  arm_goal ge4busy 4 "$cwd" sid-e4busy 4242 60 busy
  stub_registry_state busy sid-e4busy
  json=$(claude agents --json 2>/dev/null); rc=$?
  stub_registry_state absent
  got=$(classify_goal ge4busy "$json" "$rc")
  assert_eq "4/1-4 BUSY: honors the snapshot, ignores the drifted live absent" "BUSY" "$got"

  # WEDGED: snapshot busy + stale (>ceiling) + primed corroboration; live drifts to absent.
  new_home
  cwd=$(real_cwd e4wedge)
  arm_goal ge4wedge 4 "$cwd" sid-e4wedge 4242 1000 busy
  stub_registry_state busy sid-e4wedge
  json=$(claude agents --json 2>/dev/null); rc=$?
  stub_registry_state absent
  prime_wedged ge4wedge 0
  got=$(SDLC_WEDGE_CPU_FAKE=0 classify_goal ge4wedge "$json" "$rc")
  assert_eq "4/1-4 WEDGED: honors the snapshot, ignores the drifted live absent" "WEDGED" "$got"

  # COMPLETE: plan current:10 short-circuits BEFORE the registry args are ever
  # read — garbage snapshot args must never surface as a defect/degrade.
  new_home
  cwd=$(real_cwd e4complete)
  arm_goal ge4complete 10 "$cwd" sid-e4complete 4242 30 user
  got=$(classify_goal ge4complete "garbage-not-json" 1)
  assert_eq "4/1-4 COMPLETE: plan state short-circuits, garbage registry args never read" "COMPLETE" "$got"

  # GATED: plan Wake Note — same short-circuit guarantee.
  new_home
  cwd=$(real_cwd e4gated)
  arm_goal ge4gated 4 "$cwd" sid-e4gated 4242 30 user 1
  got=$(classify_goal ge4gated "garbage-not-json" 1)
  assert_eq "4/1-4 GATED: plan state short-circuits, garbage registry args never read" "GATED" "$got"

  # DEGRADE-fallback: snapshot is a FAILED fetch (rc=1); live recovers to a
  # clean registry — the cached call must still degrade on the snapshot's
  # failure (ps/grammar path), never resurrected by the live recovery.
  new_home
  cwd=$(real_cwd e4degrade)
  arm_goal ge4degrade 4 "$cwd" sid-e4degrade "$$" 30 user   # live pid ($$) → ps corroborates alive
  stub_registry_state idle sid-e4degrade                     # live recovers to a clean registry
  got=$(classify_goal ge4degrade "" 1)
  assert_eq "4/1-4 DEGRADE-fallback: cached call degrades on the snapshot's failure (ps+grammar → IDLE)" \
    "IDLE" "$got"
  assert_contains "4/1-4 DEGRADE-fallback: DEGRADE audit line emitted" "ge4degrade DEGRADE" "$(audit_of)"
}
e4

# ============================================================
# ==========  slice 4/4 — ladder dispatcher (rungs 1-3)  =====
# The poker sources sdlc-state-lib.sh and drives the ledger-clocked revival
# ladder for baton-bearing DEAD/IDLE_STALLED/WEDGED goals: poke → re-prompt →
# observe, each exactly-once through sdlc_effect_run under the pinned rung key.
# Rollover/human audit LADDER-DEFER (4/5 scope). Fail-closed on every defect.

echo "=== 4/4-lib-fence: lib sourced under set -u → a full poll completes, exit 0, no unbound-var crash ==="
L0() {
  new_home
  local cwd; cwd=$(real_cwd lf)
  arm_goal glf 4 "$cwd" sid-glf 2147483647 300 user   # DEAD
  stub_registry_state absent
  plant_baton glf "next"
  run_poker
  assert_eq "4/4-lib-fence poll exits 0 with the lib sourced" 0 "$POKER_EXIT"
  TOTAL=$((TOTAL + 1))
  if ! printf '%s' "$POKER_OUT" | grep -qi "unbound variable"; then
    pass "4/4-lib-fence no unbound-variable crash with the lib sourced under set -u"
  else fail "4/4-lib-fence unbound variable" "$POKER_OUT"; fi
}
L0

echo "=== 4/4-batonless: DEAD without a baton → legacy poke_capped, byte-identical (no ladder) ==="
L1() {
  new_home
  local cwd; cwd=$(real_cwd bl)
  arm_goal gbl 4 "$cwd" sid-gbl 2147483647 300 user   # DEAD, NO baton planted
  stub_registry_state absent
  run_poker
  assert_contains "4/4-batonless DEAD → legacy poke fired" "resume sid-gbl" "$(claude_calls)"
  assert_eq "4/4-batonless DEAD → zero ladder ledger entries" "0" \
    "$(count_lines "$(cat "$(ledger_path gbl)" 2>/dev/null || true)" "rung:")"
  assert_true "4/4-batonless DEAD → legacy poke-state file written (proves legacy path ran)" \
    test -f "$(state_dir)/gbl.poke"
}
L1

echo "=== 4/4-poke: DEAD+baton fresh → poke:1; re-poll (same durable anchor) → poke:2; each decision+effect under the pinned key ==="
L2() {
  new_home
  local cwd; cwd=$(ladder_cwd pk)
  arm_goal gpk 4 "$cwd" sid-gpk 2147483647 300 user   # DEAD (dead pid + registry absent)
  stub_registry_state absent
  plant_baton gpk "next"
  local anc; anc=$(anchor_of gpk)
  run_poker
  assert_eq "4/4-poke poll1 fired exactly one poke" "1" "$(count_lines "$(claude_calls)" "resume sid-gpk")"
  assert_true "4/4-poke poll1 decision journaled under rung:gpk:poke:<anchor>:1" \
    ledger_line_has gpk decision "rung:gpk:poke:$anc:1"
  assert_true "4/4-poke poll1 effect journaled under rung:gpk:poke:<anchor>:1" \
    ledger_line_has gpk effect "rung:gpk:poke:$anc:1"
  run_poker
  assert_eq "4/4-poke poll2 (same durable anchor) → poke:2 (two pokes total)" "2" "$(count_lines "$(claude_calls)" "resume sid-gpk")"
  assert_true "4/4-poke poll2 effect journaled under rung:gpk:poke:<anchor>:2" \
    ledger_line_has gpk effect "rung:gpk:poke:$anc:2"
}
L2

echo "=== 4/4-reprompt: poke rung exhausted (cap 2) → re-prompt:1 carrying the baton next-action verbatim via stdin ==="
L3() {
  new_home
  local cwd; cwd=$(ladder_cwd rp)
  arm_goal grp 4 "$cwd" sid-grp 2147483647 300 user   # DEAD
  stub_registry_state absent
  plant_baton grp "REBUILD-THE-INDEX-VERBATIM"
  local anc; anc=$(anchor_of grp)
  run_poker; run_poker            # poke:1, poke:2 (cap reached)
  run_poker                       # poke exhausted → re-prompt:1
  assert_true "4/4-reprompt re-prompt:1 effect journaled under the re-prompt rung key" \
    ledger_line_has grp effect "rung:grp:re-prompt:$anc:1"
  assert_contains "4/4-reprompt child prompt carries the baton next-action verbatim (via stdin)" \
    "REBUILD-THE-INDEX-VERBATIM" "$(claude_stdin)"
  assert_contains "4/4-reprompt child prompt carries the fixed project-silent preamble" \
    "carry out the recorded next action" "$(claude_stdin)"
}
L3

echo "=== 4/S5 tui-less WEDGED+baton → RESTART directly (no poke): restart effect journaled, successor spawned, RESTART notify rides ==="
L4() {
  new_home
  local cwd; cwd=$(ladder_cwd wg)
  # status null (NOSTATUS) = a headless in-flight vehicle (tui-less) — the ONLY
  # WEDGED shape the machine may restart. A SAFE fake pid (never real-signalled;
  # the SIGTERM seam is stubbed). Corroborated wedge enters RESTART directly.
  arm_goal gwg 4 "$cwd" sid-gwg 2147483647 1000 busy
  stub_registry_state nostatus sid-gwg
  plant_baton gwg "next"
  prime_wedged gwg 0
  local anc; anc=$(anchor_of gwg)
  arm_restart_seams
  export SDLC_WEDGE_CPU_FAKE=0
  run_poker
  unset SDLC_WEDGE_CPU_FAKE; disarm_restart_seams
  assert_eq "4/S5 WEDGED → NO poke child (a busy target is never poked)" "" "$(claude_calls)"
  assert_true "4/S5 WEDGED → restart EFFECT journaled under restart:gwg:<anchor>:1 (no observe rung)" \
    ledger_line_has gwg effect "restart:gwg:$anc:1"
  assert_eq "4/S5 WEDGED → the vehicle was torn down via the lib SIGTERM seam (exactly once)" "1" "$(restart_term_count)"
  assert_eq "4/S5 WEDGED → a successor was spawned" "1" "$(restart_spawn_count)"
  assert_contains "4/S5 WEDGED → RESTART notification rides the action" "Title: gwg: RESTART" "$(curl_calls)"
  assert_eq "4/S5 WEDGED → NO observe effect journaled (observe rung retired for WEDGED)" "0" \
    "$(count_lines "$(cat "$(ledger_path gwg)" 2>/dev/null || true)" "observe:")"
}
L4

echo "=== 4/4-silence: IDLE / BUSY / GATED with a baton → zero ladder entries ==="
L5() {
  # BUSY (fresh + registry busy)
  new_home
  local cwd; cwd=$(real_cwd sb)
  arm_goal gsb 4 "$cwd" sid-gsb 4242 60 busy
  stub_registry_state busy sid-gsb
  plant_baton gsb "next"
  run_poker
  assert_eq "4/4-silence BUSY → zero rung ledger entries" "0" \
    "$(count_lines "$(cat "$(ledger_path gsb)" 2>/dev/null || true)" "rung:")"
  # IDLE (fresh + registry idle)
  new_home
  cwd=$(real_cwd si)
  arm_goal gsi 4 "$cwd" sid-gsi 4242 60 user
  stub_registry_state idle sid-gsi
  plant_baton gsi "next"
  run_poker
  assert_eq "4/4-silence IDLE → zero rung ledger entries" "0" \
    "$(count_lines "$(cat "$(ledger_path gsi)" 2>/dev/null || true)" "rung:")"
  # GATED (wake note)
  new_home
  cwd=$(real_cwd sg)
  arm_goal gsg 4 "$cwd" sid-gsg 4242 60 user 1
  stub_registry_state busy sid-gsg
  plant_baton gsg "next"
  run_poker
  assert_eq "4/4-silence GATED → zero rung ledger entries" "0" \
    "$(count_lines "$(cat "$(ledger_path gsg)" 2>/dev/null || true)" "rung:")"
}
L5

echo "=== 4/4-progress: a revived session (reclassifies IDLE) is not laddered — no new rung this poll ==="
L6() {
  new_home
  local cwd; cwd=$(ladder_cwd pg)
  arm_goal gpg 4 "$cwd" sid-gpg 2147483647 300 user   # DEAD → poke:1
  stub_registry_state absent
  plant_baton gpg "next"
  run_poker
  assert_eq "4/4-progress poll1: one rung effect (poke:1)" "1" "$(rung_effect_count gpg)"
  # The session revives — registry idle + a FRESH transcript (<180 → IDLE). IDLE
  # is not a ladder-applicable class, so the goal is not laddered at all (the
  # durable anchor is irrelevant here — a healthy goal produces ZERO ladder
  # actions, not a reset episode).
  stub_registry_state idle sid-gpg
  plant_transcript_age "$cwd" sid-gpg 30 user
  run_poker
  assert_eq "4/4-progress poll2 (revived → IDLE): no new poke fired" "1" \
    "$(count_lines "$(claude_calls)" "resume sid-gpg")"
  assert_eq "4/4-progress poll2: revived goal not laddered, still exactly one rung effect" "1" \
    "$(rung_effect_count gpg)"
}
L6

echo "=== 4/4-one-action: a single poll journals exactly ONE rung decision + ONE rung effect for a goal (AS-C5) ==="
L7() {
  new_home
  local cwd; cwd=$(ladder_cwd oa)
  arm_goal goa 4 "$cwd" sid-goa 2147483647 300 user   # DEAD
  stub_registry_state absent
  plant_baton goa "next"
  run_poker
  assert_eq "4/4-one-action exactly one rung decision this poll" "1" \
    "$(awk -F'\t' '$4=="decision" && $5 ~ /^rung:goa:/' "$(ledger_path goa)" | wc -l | tr -d ' ')"
  assert_eq "4/4-one-action exactly one rung effect this poll" "1" \
    "$(awk -F'\t' '$4=="effect" && $5 ~ /^rung:goa:/' "$(ledger_path goa)" | wc -l | tr -d ' ')"
}
L7

echo "=== 4/4-failclosed-baton: malformed baton → LADDER-SKIP audit + goal skipped; a SECOND goal still processed ==="
L8() {
  new_home
  local cwd1 cwd2; cwd1=$(real_cwd fb1); cwd2=$(ladder_cwd fb2)
  arm_goal gbad 4 "$cwd1" sid-gbad 2147483647 300 user    # DEAD, malformed baton (never derives an anchor)
  arm_goal ggood 4 "$cwd2" sid-ggood 2147483647 300 user  # DEAD, clean baton
  stub_registry_state absent
  mkdir -p "$(baton_goal_dir gbad)"
  printf 'goal-id: gbad\n' > "$(baton_path gbad)"          # missing required keys → malformed
  plant_baton ggood "next"
  local anc; anc=$(anchor_of ggood)
  run_poker
  assert_eq "4/4-failclosed-baton poker exit 0" 0 "$POKER_EXIT"
  assert_contains "4/4-failclosed-baton LADDER-SKIP audited for the malformed baton" \
    "gbad LADDER-SKIP" "$(audit_of)"
  assert_eq "4/4-failclosed-baton the malformed-baton goal was NOT poked (no legacy fall-through)" "0" \
    "$(count_lines "$(claude_calls)" "resume sid-gbad")"
  assert_true "4/4-failclosed-baton the SECOND goal was still laddered (poke:1 effect journaled)" \
    ledger_line_has ggood effect "rung:ggood:poke:$anc:1"
}
L8

echo "=== 4/4-failclosed-ledger: corrupt ledger → LADDER-SKIP (anchor derivation reads it) + goal skipped; a SECOND goal still processed ==="
L9() {
  new_home
  local cwd1 cwd2; cwd1=$(ladder_cwd fl1); cwd2=$(ladder_cwd fl2)
  arm_goal gcl 4 "$cwd1" sid-gcl 2147483647 300 user
  arm_goal gok 4 "$cwd2" sid-gok 2147483647 300 user
  stub_registry_state absent
  plant_baton gcl "next"
  plant_baton gok "next"
  mkdir -p "$(baton_goal_dir gcl)"
  # a chain-inconsistent ledger line (bogus digest) → ledger_verify in-place-edit.
  # The durable anchor now reads the ledger (passenger-class tail), so a corrupt
  # ledger fails at ANCHOR derivation → LADDER-SKIP (was LADDER-DEFECT when the
  # mtime anchor never touched the ledger). Still fail-closed + poll continues.
  printf 'ts\t1\tdeadbeef\teffect\trung:gcl:poke:100:1\tx\n' > "$(ledger_path gcl)"
  local anc; anc=$(anchor_of gok)
  run_poker
  assert_eq "4/4-failclosed-ledger poker exit 0" 0 "$POKER_EXIT"
  assert_contains "4/4-failclosed-ledger LADDER-SKIP audited for the corrupt ledger" \
    "gcl LADDER-SKIP" "$(audit_of)"
  assert_eq "4/4-failclosed-ledger the corrupt-ledger goal was NOT poked" "0" \
    "$(count_lines "$(claude_calls)" "resume sid-gcl")"
  assert_true "4/4-failclosed-ledger the SECOND goal was still laddered (poke:1 effect journaled)" \
    ledger_line_has gok effect "rung:gok:poke:$anc:1"
}
L9

echo "=== 6/critic-fix-2 (F1b): unresolvable baton branch → LADDER-SKIP audit + fail-closed skip; poll continues to next goal ==="
L9b() {
  new_home
  local cwd1 cwd2; cwd1=$(ladder_cwd fb1); cwd2=$(ladder_cwd fb2)
  arm_goal gbr 4 "$cwd1" sid-gbr 2147483647 300 user    # DEAD, baton names a branch that does not resolve
  arm_goal gok3 4 "$cwd2" sid-gok3 2147483647 300 user  # DEAD, clean baton
  stub_registry_state absent
  # baton for gbr records a branch that never existed in cwd1 (typo / deleted
  # after merge / wrong repo) — sdlc_ladder_anchor must fail-closed (F1b), never
  # digest the literal ref name and mint a fake anchor.
  local plan1 tip1
  plan1=$(sed -n 's/^PLAN=//p' "$HOME/.claude/sdlc-goals/gbr")
  tip1=$(git -C "$cwd1" rev-parse HEAD)
  baton_write "gbr" "$plan1" "$cwd1" "feat/does-not-exist" "epic-x" "$tip1" 4 "sid-gbr" none "next" none none >/dev/null 2>&1
  plant_baton gok3 "next"
  local anc; anc=$(anchor_of gok3)
  run_poker
  assert_eq "6/critic-fix-2 poker exit 0" 0 "$POKER_EXIT"
  assert_contains "6/critic-fix-2 LADDER-SKIP audited for the unresolvable branch" \
    "gbr LADDER-SKIP" "$(audit_of)"
  assert_eq "6/critic-fix-2 the unresolvable-branch goal was NOT poked (fail-closed, no anchor minted)" "0" \
    "$(count_lines "$(claude_calls)" "resume sid-gbr")"
  assert_true "6/critic-fix-2 the SECOND goal was still laddered (poll continues past the bad goal)" \
    ledger_line_has gok3 effect "rung:gok3:poke:$anc:1"
}
L9b

echo "=== 4/4-degrade: lib unavailable → LADDER-DEGRADE audit + baton goal falls back to legacy poke (no ladder) ==="
L10() {
  new_home
  local cwd; cwd=$(real_cwd dg)
  arm_goal gdg 4 "$cwd" sid-gdg 2147483647 300 user   # DEAD, baton present
  stub_registry_state absent
  plant_baton gdg "next"
  export SDLC_STATE_LIB="$HOME/nonexistent-state-lib.sh"   # poker child cannot source the lib
  run_poker
  unset SDLC_STATE_LIB
  assert_eq "4/4-degrade poker exit 0 with the lib unavailable" 0 "$POKER_EXIT"
  assert_contains "4/4-degrade LADDER-DEGRADE audited once" "LADDER-DEGRADE" "$(audit_of)"
  assert_contains "4/4-degrade the baton goal fell back to a legacy poke" "resume sid-gdg" "$(claude_calls)"
  assert_eq "4/4-degrade no ladder ledger entries were journaled" "0" \
    "$(count_lines "$(cat "$(ledger_path gdg)" 2>/dev/null || true)" "rung:")"
}
L10

# ==========  slice 4/5 — rollover + human rungs + completion latch  =====
# The poker drives the ladder's terminal rungs through the spine (consumed
# AS-IS): `rollover` → sdlc_successor_spawn (refuse-first, exactly-once); `human`
# → sdlc_gate_park (ladder-exhausted, REGISTRATION plan provenance); COMPLETE →
# sdlc_complete_check (latch / SKIP-RACE / false-complete park). Every outcome is
# replay-safe and reproduced by a cold poker child from durable state alone.

# ---------- 4/5 fixture helpers ----------
# A hermetic git repo with one base commit; echoes its path. The rollover happy
# path drives sdlc_reconcile (git predicates) and the completion latch drives
# sdlc_complete_check (merged-ness) INSIDE the poker child, so those fixtures
# need a real repo (not the plain $HOME/work dir real_cwd mints).
mk_git_repo() {
  local d; d=$(mktemp -d); CLEAN_HOMES+=("$d")
  git -C "$d" init -q
  git -C "$d" config user.name  fixture
  git -C "$d" config user.email fixture@example.com
  printf 'base line\n' > "$d/tracked.txt"
  git -C "$d" add -A
  git -C "$d" commit -qm base >/dev/null 2>&1
  printf '%s' "$d"
}

# A synchronous spawn stub the spine runs via `-- $SDLC_SPAWN_CMD`: one line per
# launch into $SPAWN_COUNT_FILE. Both EXPORTED so the poker child AND the spine's
# spawn grandchild inherit them (a `local` would not cross the process boundary).
# Race-free — the SDLC_SPAWN_CMD seam runs the stub SYNCHRONOUSLY, never the real
# backgrounded `claude -p`. Call after new_home; unset_spawn_stub clears the leak.
setup_spawn_stub() {
  SPAWN_COUNT_FILE="$HOME/.claude/.stub/spawn-count"; : > "$SPAWN_COUNT_FILE"
  local s="$HOME/.claude/.stub/spawnstub"
  cat > "$s" <<'S'
#!/bin/sh
echo x >> "$SPAWN_COUNT_FILE"
exit 0
S
  chmod +x "$s"
  export SDLC_SPAWN_CMD="$s" SPAWN_COUNT_FILE
}
unset_spawn_stub() { unset SDLC_SPAWN_CMD SPAWN_COUNT_FILE 2>/dev/null || true; }
# wc -l (not `grep -c .`) so an empty count file yields "0" with exit 0 — under the
# suite's `set -o pipefail` a zero-match `grep -c` exits 1 and doubles the output.
spawn_count() { local f="$HOME/.claude/.stub/spawn-count"; [ -f "$f" ] && wc -l < "$f" | tr -d ' ' || echo 0; }
wake_note_count() { awk '/^## Wake Note$/{n++} END{print n+0}' "$1" 2>/dev/null || echo 0; }
plan_has_wake() { grep -q '^## Wake Note$' "$1" 2>/dev/null; }
complete_effect_count() { awk -F'\t' '$4=="effect" && $5 ~ /^complete:/{n++} END{print n+0}' "$(ledger_path "$1")" 2>/dev/null || echo 0; }

# arm_rollover <gid> [plan-current] [baton-step] — a DEAD goal whose ladder sits
# at `rollover`: git-repo cwd + aligned baton + poke×2/re-prompt×2 rung EFFECTs
# journaled under the current transcript anchor (so poke+re-prompt are exhausted
# and the DEAD rung order lands on rollover). plan-current default 4 (== step)
# aligns sdlc_reconcile; pass a MISMATCH (5 vs step 4) to force a baton-stale
# divergence at the spine's reconcile stage. Sets ROLL_CWD / ROLL_ANCHOR / ROLL_PLAN.
arm_rollover() {
  local gid="$1" cur="${2:-4}" step="${3:-4}" pos br tip
  ROLL_CWD=$(mk_git_repo)
  ROLL_PLAN="$HOME/plans/$gid.plan.md"
  plant_plan "$ROLL_PLAN" "$cur" 0
  plant_goal "$gid" "$ROLL_PLAN" "$ROLL_CWD" "sid-$gid" 2147483647   # dead pid → DEAD (+ registry absent)
  plant_transcript_age "$ROLL_CWD" "sid-$gid" 300 user
  br=$(git -C "$ROLL_CWD" rev-parse --abbrev-ref HEAD)
  tip=$(git -C "$ROLL_CWD" rev-parse HEAD)
  # Baton FIRST (empty ledger) so the DURABLE-PROGRESS anchor is derivable and its
  # written-at is frozen here; the rungs are journaled under that anchor next.
  baton_write "$gid" "$ROLL_PLAN" "$ROLL_CWD" "$br" "epic-x" "$tip" "$step" \
    "sid-$gid" none "resume the slice" none none >/dev/null 2>&1
  ROLL_ANCHOR=$(sdlc_ladder_anchor "$gid" "$ROLL_PLAN" "$ROLL_CWD" 2>/dev/null)
  ledger_append "$gid" effect "rung:$gid:poke:$ROLL_ANCHOR:1"       "poke 1"       >/dev/null 2>&1
  ledger_append "$gid" effect "rung:$gid:poke:$ROLL_ANCHOR:2"       "poke 2"       >/dev/null 2>&1
  ledger_append "$gid" effect "rung:$gid:re-prompt:$ROLL_ANCHOR:1"  "re-prompt 1"  >/dev/null 2>&1
  ledger_append "$gid" effect "rung:$gid:re-prompt:$ROLL_ANCHOR:2"  "re-prompt 2"  >/dev/null 2>&1
  pos=$(awk -F'\t' 'END{print $2":"$3}' "$(ledger_path "$gid")")
  # Patch ONLY the baton's ledger-position to the rung tail — never re-stamping
  # written-at — so the frozen anchor still matches the rung keys AND reconcile's
  # position cross-check passes (the rungs are spine-class → the anchor's
  # passenger-tail stays 0, so ROLL_ANCHOR is unchanged by them).
  awk -v p="$pos" '/^ledger-position:/{print "ledger-position: " p; next}{print}' \
    "$(baton_path "$gid")" > "$(baton_path "$gid").tmp" && mv "$(baton_path "$gid").tmp" "$(baton_path "$gid")"
}

# arm_complete <gid> <merged:yes|no> — a COMPLETE goal (reg plan current 10) with
# a git repo where the goal branch committed work since base; integration
# contains that work iff merged=yes. Sets CMP_CWD / CMP_PLAN.
arm_complete() {
  local gid="$1" merged="$2" d base tip
  d=$(mktemp -d); CLEAN_HOMES+=("$d")
  git -C "$d" init -q
  git -C "$d" config user.name fixture; git -C "$d" config user.email f@e.com
  printf 'base\n' > "$d/f.txt"; git -C "$d" add -A; git -C "$d" commit -qm base >/dev/null 2>&1
  base=$(git -C "$d" rev-parse HEAD)
  git -C "$d" checkout -q -b "gb-$gid"
  printf 'work\n' >> "$d/f.txt"; git -C "$d" add -A; git -C "$d" commit -qm work >/dev/null 2>&1
  tip=$(git -C "$d" rev-parse HEAD)
  if [ "$merged" = yes ]; then git -C "$d" branch "int-$gid" "gb-$gid"; else git -C "$d" branch "int-$gid" "$base"; fi
  CMP_PLAN="$HOME/plans/$gid.plan.md"
  plant_plan "$CMP_PLAN" 10 0
  plant_goal "$gid" "$CMP_PLAN" "$d" "sid-$gid" 4242
  plant_transcript_age "$d" "sid-$gid" 30 user
  baton_write "$gid" "$CMP_PLAN" "$d" "gb-$gid" "int-$gid" "$tip" 10 "sid-$gid" none "resume" none "$base" >/dev/null 2>&1
  # A genuinely-completed goal journaled events along the way — sdlc_complete_check's
  # ledger_verify reads an ABSENT ledger as `missing-ledger` (rc 2), so give the goal
  # a real (non-empty, chain-valid) ledger. Immaterial to the unmerged path, which
  # refutes merged-ness before ledger_verify.
  ledger_append "$gid" effect "poke:$gid" "goal history" >/dev/null 2>&1
  CMP_CWD="$d"
}

# ---------- rollover rung (deliverable a) ----------
echo "=== 4/5-rollover-happy: DEAD at rollover → sdlc_successor_spawn fires EXACTLY once, audit LADDER-ROLLOVER ==="
R1() {
  new_home
  arm_rollover grh
  stub_registry_state absent
  setup_spawn_stub
  run_poker
  unset_spawn_stub
  assert_eq "4/5-rollover-happy poker exit 0" 0 "$POKER_EXIT"
  assert_eq "4/5-rollover-happy spawn launched EXACTLY once" "1" "$(spawn_count)"
  assert_contains "4/5-rollover-happy LADDER-ROLLOVER audited" "grh LADDER-ROLLOVER" "$(audit_of)"
  assert_true "4/5-rollover-happy spawn effect journaled under the spine's spawn key" \
    awk -F'\t' '$4=="effect" && $5 ~ /^spawn:grh:/{f=1} END{exit(f?0:1)}' "$(ledger_path grh)"
}
R1

echo "=== 4/5-rollover-wakenote: rungs exhausted but plan carries a Wake Note → GATED, no spawn ==="
R2() {
  new_home
  arm_rollover grw
  # a Wake Note flips classify to GATED (ladder disarmed) — the spine is never reached
  printf '\n## Wake Note\n\nblocked on decision — stopping.\n' >> "$ROLL_PLAN"
  stub_registry_state absent
  setup_spawn_stub
  run_poker
  unset_spawn_stub
  assert_eq "4/5-rollover-wakenote no spawn (GATED disarms the ladder)" "0" "$(spawn_count)"
  assert_eq "4/5-rollover-wakenote zero rung/spawn ladder actions this poll" "0" \
    "$(count_lines "$(claude_calls)" "resume sid-grw")"
}
R2

echo "=== 4/5-rollover-owned: live prior-spawn owner in the registry → goal-owned refusal, no park, retried next poll ==="
R3() {
  new_home
  arm_rollover gro
  local owner="aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
  # a prior spawn EFFECT (older generation) whose sid is live in the registry
  ledger_append gro effect "spawn:gro:2020-01-01T00:00:00Z" "sid=$owner pid=na cwd=$ROLL_CWD" >/dev/null 2>&1
  printf '[{"pid":99,"cwd":"/x","kind":"interactive","sessionId":"%s","status":"idle","name":"owner"}]\n' "$owner" \
    > "$HOME/.claude/.stub/registry.json"
  echo 0 > "$HOME/.claude/.stub/registry.rc"
  setup_spawn_stub
  run_poker      # poll 1
  assert_eq "4/5-rollover-owned poll1 no spawn (goal-owned refusal)" "0" "$(spawn_count)"
  assert_contains "4/5-rollover-owned LADDER-ROLLOVER-REFUSED audited" "gro LADDER-ROLLOVER-REFUSED" "$(audit_of)"
  assert_true "4/5-rollover-owned no park (plan has no Wake Note — a healthy live owner)" \
    bash -c '! grep -q "^## Wake Note\$" "$1"' _ "$ROLL_PLAN"
  run_poker      # poll 2 — re-derives rollover, refuses again
  unset_spawn_stub
  assert_eq "4/5-rollover-owned poll2 still refuses (retried next poll, still no spawn)" "0" "$(spawn_count)"
  assert_eq "4/5-rollover-owned two REFUSED audit lines across two polls" "2" \
    "$(count_lines "$(audit_of)" "gro LADDER-ROLLOVER-REFUSED")"
}
R3

echo "=== 4/5-rollover-diverged: reconcile divergence (baton-stale) → spine parks GATED with its defect, no spawn ==="
R4() {
  new_home
  arm_rollover grd 5 4      # plan current 5 vs baton step 4 → reconcile baton-stale
  stub_registry_state absent
  setup_spawn_stub
  run_poker
  unset_spawn_stub
  assert_eq "4/5-rollover-diverged no spawn (spine parked before launch)" "0" "$(spawn_count)"
  assert_true "4/5-rollover-diverged spine appended a Wake Note to the plan (park GATED)" \
    plan_has_wake "$ROLL_PLAN"
  assert_contains "4/5-rollover-diverged LADDER-ROLLOVER-PARK audited" "grd LADDER-ROLLOVER-PARK" "$(audit_of)"
}
R4

# ---------- human rung / spawn-skipped escalation (deliverable b, AS-N13) ----------
echo "=== 4/5-human-skipped: spawn applied + still DEAD + same baton → human park (ONE Wake Note), ntfy via GATED transition next poll ==="
H1() {
  new_home
  arm_rollover ghk
  stub_registry_state absent
  setup_spawn_stub
  run_poker           # poll1: rollover → spawn once (spawn key now applied)
  assert_eq "4/5-human-skipped poll1 spawned once" "1" "$(spawn_count)"
  run_poker           # poll2: spawn applied → ladder returns human → park ladder-exhausted
  unset_spawn_stub
  assert_eq "4/5-human-skipped poll2 did NOT re-spawn (exactly-once holds; counter still 1)" "1" "$(spawn_count)"
  assert_contains "4/5-human-skipped LADDER-HUMAN park audited (ladder-exhausted)" "ghk LADDER-HUMAN" "$(audit_of)"
  assert_eq "4/5-human-skipped EXACTLY one Wake Note appended" "1" "$(wake_note_count "$ROLL_PLAN")"
  run_poker           # poll3: plan now GATED → GATED-transition ntfy fires
  assert_contains "4/5-human-skipped ntfy fired on the GATED transition (next pass)" \
    "Title: ghk: GATED" "$(curl_calls)"
}
H1

echo "=== 4/5-human-newbaton: a NEW baton generation re-arms → fresh episode, rollover available again ==="
H2() {
  new_home
  arm_rollover ghn
  stub_registry_state absent
  setup_spawn_stub
  run_poker                                   # poll1: rollover spawn (spawn:ghn:<WA1> applied)
  run_poker                                   # poll2: human park (Wake Note)
  assert_eq "4/5-human-newbaton one spawn so far" "1" "$(spawn_count)"
  # A passenger writes a NEWER baton generation (distinct written-at) and the
  # human clears the note (re-arm). The written-at is part of the DURABLE-PROGRESS
  # anchor, so this is a genuinely FRESH episode: the old-generation rungs are
  # dead history and the ladder restarts at poke:1 (D-C4 rollover-with-new-baton,
  # earned by progress — never fabricated by the spine).
  awk '/^written-at:/{print "written-at: 2099-01-01T00:00:00Z"; next} {print}' \
    "$(baton_path ghn)" > "$(baton_path ghn).tmp" && mv "$(baton_path ghn).tmp" "$(baton_path ghn)"
  plant_plan "$ROLL_PLAN" 4 0                  # remove the Wake Note (re-arm) → DEAD again
  local newanc; newanc=$(anchor_of ghn)
  assert_true "4/5-human-newbaton the new generation is a FRESH episode (anchor differs from the old generation)" \
    test "$newanc" != "$ROLL_ANCHOR"
  run_poker                                   # poll3: fresh episode → poke:1 under the NEW anchor
  assert_true "4/5-human-newbaton poll3 fresh episode → poke:1 (rungs reset for the new generation)" \
    ledger_line_has ghn effect "rung:ghn:poke:$newanc:1"
  assert_eq "4/5-human-newbaton poll3 did NOT re-spawn (fresh episode re-walks the automated rungs first)" \
    "1" "$(spawn_count)"
  # exhaust the new generation's automated rungs → the ladder reaches rollover
  ledger_append ghn effect "rung:ghn:poke:$newanc:2"      "poke 2"      >/dev/null 2>&1
  ledger_append ghn effect "rung:ghn:re-prompt:$newanc:1" "re-prompt 1" >/dev/null 2>&1
  ledger_append ghn effect "rung:ghn:re-prompt:$newanc:2" "re-prompt 2" >/dev/null 2>&1
  run_poker                                   # poll4: rollover available again for the new generation
  unset_spawn_stub
  assert_eq "4/5-human-newbaton the new baton generation spawns again (counter 2)" "2" "$(spawn_count)"
}
H2

# ---------- completion latch (deliverable c, D-C6) ----------
echo "=== 4/5-complete-genuine: genuinely-merged COMPLETE → complete: latched EXACTLY once across two polls + notify once ==="
C1() {
  new_home
  arm_complete cmg yes
  setup_spawn_stub    # harmless — completion never ladders
  run_poker
  run_poker
  unset_spawn_stub
  assert_eq "4/5-complete-genuine complete: latch journaled EXACTLY once across two polls" "1" \
    "$(complete_effect_count cmg)"
  assert_eq "4/5-complete-genuine COMPLETE notified once (deduped on the second poll)" "1" \
    "$(count_lines "$(curl_calls)" "cmg: COMPLETE")"
  assert_eq "4/5-complete-genuine no ladder actions (COMPLETE never ladders)" "0" \
    "$(count_lines "$(cat "$(ledger_path cmg)" 2>/dev/null || true)" "rung:")"
}
C1

echo "=== 4/5-complete-false: false-complete (terminal plan, branch unmerged) → park GATED, no latch, no ladder ==="
C2() {
  new_home
  arm_complete cmf no
  run_poker
  assert_true "4/5-complete-false spine parked the plan GATED (Wake Note appended)" \
    plan_has_wake "$CMP_PLAN"
  assert_eq "4/5-complete-false NO complete: latch journaled" "0" "$(complete_effect_count cmf)"
  assert_contains "4/5-complete-false COMPLETE-FALSE park audited" "cmf COMPLETE-FALSE" "$(audit_of)"
  assert_eq "4/5-complete-false no COMPLETE notification fired" "0" \
    "$(count_lines "$(curl_calls)" "cmf: COMPLETE")"
}
C2

echo "=== 4/5-complete-race: benign not-complete (baton plan lags reg plan) → audit SKIP-RACE, nothing else ==="
C3() {
  new_home
  local gid=cmr
  local regplan="$HOME/plans/$gid.reg.plan.md" batplan="$HOME/plans/$gid.bat.plan.md"
  plant_plan "$regplan" 10 0                       # registration view: current 10 → classify COMPLETE
  plant_plan "$batplan" 9 0                        # baton view: current 9 → complete_check benign not-complete
  plant_goal "$gid" "$regplan" "/nonrepo-$gid" "sid-$gid" 4242
  plant_transcript_age "/nonrepo-$gid" "sid-$gid" 30 user
  baton_write "$gid" "$batplan" "/nonrepo-$gid" b i lc 9 "sid-$gid" none resume none none >/dev/null 2>&1
  run_poker
  assert_contains "4/5-complete-race SKIP-RACE audited" "cmr SKIP-RACE" "$(audit_of)"
  assert_eq "4/5-complete-race no COMPLETE notification" "0" "$(count_lines "$(curl_calls)" "cmr: COMPLETE")"
  assert_eq "4/5-complete-race no complete: latch" "0" "$(complete_effect_count cmr)"
  assert_true "4/5-complete-race no park (benign in-flight, not a defect)" \
    bash -c '! grep -q "^## Wake Note\$" "$1"' _ "$regplan"
}
C3

# ---------- replay grid (AC-C5) ----------
echo "=== 4/5-replay-poke: double-driven poke rung → exactly one decision+effect per attempt (no replay double-fire) ==="
P1() {
  new_home
  local cwd; cwd=$(ladder_cwd rpk)
  arm_goal grpk 4 "$cwd" sid-grpk 2147483647 300 user
  stub_registry_state absent
  plant_baton grpk "next"
  local anc; anc=$(anchor_of grpk)
  run_poker; run_poker         # poke:1 then poke:2 (same durable anchor)
  assert_eq "4/5-replay-poke exactly ONE decision line for poke:1" "1" \
    "$(awk -F'\t' -v k="rung:grpk:poke:$anc:1" '$4=="decision" && $5==k' "$(ledger_path grpk)" | wc -l | tr -d ' ')"
  assert_eq "4/5-replay-poke exactly ONE effect line for poke:1" "1" \
    "$(awk -F'\t' -v k="rung:grpk:poke:$anc:1" '$4=="effect" && $5==k' "$(ledger_path grpk)" | wc -l | tr -d ' ')"
  assert_eq "4/5-replay-poke exactly ONE effect line for poke:2" "1" \
    "$(awk -F'\t' -v k="rung:grpk:poke:$anc:2" '$4=="effect" && $5==k' "$(ledger_path grpk)" | wc -l | tr -d ' ')"
}
P1

echo "=== 4/5-replay-indeterminate: decision-only rung key under the current anchor → effect-indeterminate → park GATED, no execution ==="
P2() {
  new_home
  local cwd; cwd=$(ladder_cwd rin)
  arm_goal grin 4 "$cwd" sid-grin 2147483647 300 user   # DEAD
  stub_registry_state absent
  plant_baton grin "next"
  local anc; anc=$(anchor_of grin)
  local regplan="$HOME/plans/grin.plan.md"
  # a journaled poke:1 DECISION with NO matching effect — the crash window
  ledger_append grin decision "rung:grin:poke:$anc:1" "poke 1 intent" >/dev/null 2>&1
  run_poker
  assert_eq "4/5-replay-indeterminate NO poke child spawned (fail-closed, no execution)" "0" \
    "$(count_lines "$(claude_calls)" "resume sid-grin")"
  assert_true "4/5-replay-indeterminate parked GATED (Wake Note on the registration plan)" \
    plan_has_wake "$regplan"
  assert_contains "4/5-replay-indeterminate LADDER-INDETERMINATE audited" "grin LADDER-INDETERMINATE" "$(audit_of)"
}
P2

# ---------- cold-state grid (AC-C3) ----------
echo "=== 4/5-cold-state: a FRESH poker child reproduces the warm next action from durable state alone ==="
X1() {
  # fresh episode (no rungs) → poke:1
  new_home
  local c1; c1=$(ladder_cwd cs1)
  arm_goal gcs1 4 "$c1" sid-gcs1 2147483647 300 user
  stub_registry_state absent
  plant_baton gcs1 "next"
  local a1; a1=$(anchor_of gcs1)
  run_poker
  assert_true "4/5-cold-state fresh episode → poke:1 effect journaled" \
    ledger_line_has gcs1 effect "rung:gcs1:poke:$a1:1"

  # mid-episode (poke:1 pre-applied) → poke:2
  new_home
  local c2; c2=$(ladder_cwd cs2)
  arm_goal gcs2 4 "$c2" sid-gcs2 2147483647 300 user
  stub_registry_state absent
  plant_baton gcs2 "next"
  local a2; a2=$(anchor_of gcs2)
  ledger_append gcs2 effect "rung:gcs2:poke:$a2:1" "poke 1" >/dev/null 2>&1
  run_poker
  assert_true "4/5-cold-state mid-episode (poke:1 applied) → poke:2 effect journaled" \
    ledger_line_has gcs2 effect "rung:gcs2:poke:$a2:2"

  # spawn-skipped (rollover fixture + current-generation spawn applied) → human park
  new_home
  arm_rollover gcs3
  stub_registry_state absent
  local wa; wa=$(grep '^written-at:' "$(baton_path gcs3)" | sed 's/^written-at: //')
  ledger_append gcs3 effect "spawn:gcs3:$wa" "sid=deadbeef pid=na cwd=$ROLL_CWD" >/dev/null 2>&1
  setup_spawn_stub
  run_poker
  unset_spawn_stub
  assert_eq "4/5-cold-state spawn-skipped (spawn applied) → human, no new spawn" "0" "$(spawn_count)"
  assert_contains "4/5-cold-state spawn-skipped → LADDER-HUMAN park" "gcs3 LADDER-HUMAN" "$(audit_of)"
}
X1

# ==========  slice 6/critic-fix — durable-progress anchor + park-rc fold  =====
# The Step-6 critic F1 fix at the poker level: (1) the observer-effect repro —
# a poke's own transcript write no longer resets the episode; (2) the 5-axis F1
# fold — a park that cannot land is surfaced as LADDER-DEFECT, never a silent
# re-park.

echo "=== 6/critic-observer: a poke's own transcript write does NOT reset the episode (durable anchor) ==="
CR() {
  new_home
  local cwd; cwd=$(ladder_cwd cr)
  arm_goal gcr 4 "$cwd" sid-gcr 2147483647 300 user   # DEAD
  stub_registry_state absent
  plant_baton gcr "next"
  local anc; anc=$(anchor_of gcr)
  run_poker
  assert_true "6/critic-observer poll1 → poke:1 journaled under the DIGEST anchor key" \
    ledger_line_has gcr effect "rung:gcr:poke:$anc:1"
  # THE critic trigger: the poke's own resume turn advances the transcript mtime
  # but changes NO durable progress; the goal stays DEAD (registry absent). Under
  # the OLD mtime anchor this reset the episode to poke:1 forever.
  plant_transcript_age "$cwd" sid-gcr 30 user   # transcript mtime moves between polls
  assert_eq "6/critic-observer durable anchor UNCHANGED despite the transcript move" \
    "$anc" "$(anchor_of gcr)"
  run_poker
  assert_true "6/critic-observer poll2 → poke:2 (episode NOT reset — observer effect fixed)" \
    ledger_line_has gcr effect "rung:gcr:poke:$anc:2"
  assert_eq "6/critic-observer two pokes fired (escalation accumulates, no poke:1 loop)" "2" \
    "$(count_lines "$(claude_calls)" "resume sid-gcr")"
}
CR

echo "=== 6/critic-park-indeterminate: effect-indeterminate park that cannot land → LADDER-DEFECT (5-axis F1) ==="
PF1() {
  new_home
  local cwd; cwd=$(ladder_cwd pf1)
  arm_goal gpf1 4 "$cwd" sid-gpf1 2147483647 300 user   # DEAD
  stub_registry_state absent
  plant_baton gpf1 "next"
  local anc; anc=$(anchor_of gpf1)
  # a journaled poke:1 DECISION with NO matching effect → effect-indeterminate
  ledger_append gpf1 decision "rung:gpf1:poke:$anc:1" "poke 1 intent" >/dev/null 2>&1
  chmod 444 "$HOME/plans/gpf1.plan.md"   # the registration plan cannot be appended → park fails
  run_poker
  chmod 644 "$HOME/plans/gpf1.plan.md"
  assert_eq "6/critic park-indeterminate poker exit 0 (fail-closed, poll continues)" 0 "$POKER_EXIT"
  assert_contains "6/critic park-indeterminate park failure → LADDER-DEFECT (surfaced, not silent)" \
    "gpf1 LADDER-DEFECT" "$(audit_of)"
  assert_true "6/critic park-indeterminate did NOT emit a LADDER-INDETERMINATE success line (park failed)" \
    bash -c '! printf "%s" "$1" | grep -qF "gpf1 LADDER-INDETERMINATE"' _ "$(audit_of)"
}
PF1

echo "=== 6/critic-park-false-complete: false-complete park that cannot land → LADDER-DEFECT (5-axis F1) ==="
PF2() {
  new_home
  arm_complete cmf2 no
  chmod 444 "$CMP_PLAN"   # the registration plan cannot be appended → park fails
  run_poker
  chmod 644 "$CMP_PLAN"
  assert_eq "6/critic park-false-complete poker exit 0" 0 "$POKER_EXIT"
  assert_contains "6/critic park-false-complete park failure → LADDER-DEFECT (surfaced, not silent re-park)" \
    "cmf2 LADDER-DEFECT" "$(audit_of)"
  assert_true "6/critic park-false-complete did NOT emit a COMPLETE-FALSE success line (park failed)" \
    bash -c '! printf "%s" "$1" | grep -qF "cmf2 COMPLETE-FALSE"' _ "$(audit_of)"
  assert_eq "6/critic park-false-complete no complete: latch journaled" "0" "$(complete_effect_count cmf2)"
}
PF2

# ---------- 4/S2: poker arming eligibility — watchdog swap ----------
# is_armed replaces is_armed_scale: registration well-formed AND
# sdlc_watchdog_effective(REG_PLAN)=on. The fallback table (the wave
# plan §Global Constraints, NORMATIVE): explicit watchdog wins; absent-flag
# continuous → on; absent-flag task/wave/epic → off.

echo "=== 4/S2-1: armed wave-scale plan (watchdog: on) → classified (was: silently skipped) ==="
S2_1() {
  new_home
  local plan="$HOME/plans/gs21.plan.md"
  plant_plan "$plan" 4 0 wave on            # scale: wave, watchdog: on
  plant_goal gs21 "$plan" /proj/s21 sid-s21 4242
  plant_transcript_age /proj/s21 sid-s21 30 user
  stub_registry_state idle sid-s21
  run_poker
  assert_eq "4/S2-1 poker exit 0" 0 "$POKER_EXIT"
  assert_true "4/S2-1 watchdog:on wave-scale → classified (status written)" status_exists gs21
}
S2_1

echo "=== 4/S2-2: watchdog:off continuous → skipped WITH audited SKIP-UNARMED (was: silent) ==="
S2_2() {
  new_home
  local plan="$HOME/plans/gs22.plan.md"
  plant_plan "$plan" 4 0 continuous off     # scale: continuous, watchdog: off
  plant_goal gs22 "$plan" /proj/s22 sid-s22 4242
  plant_transcript_age /proj/s22 sid-s22 30 user
  stub_registry_state idle sid-s22
  run_poker
  assert_eq "4/S2-2 poker exit 0" 0 "$POKER_EXIT"
  assert_true "4/S2-2 watchdog:off continuous → NOT classified" not_status_exists gs22
  assert_contains "4/S2-2 skip is audited SKIP-UNARMED (not silent)" "gs22 SKIP-UNARMED" "$(audit_of)"
}
S2_2

echo "=== 4/S2-3: absent-flag continuous → still armed (KA-R14 compat, zero migration) ==="
S2_3() {
  new_home
  arm_goal gs23 4 /proj/s23 sid-s23 4242 30 user   # arm_goal's plant_plan omits watchdog
  stub_registry_state idle sid-s23
  run_poker
  assert_eq "4/S2-3 poker exit 0" 0 "$POKER_EXIT"
  assert_true "4/S2-3 absent-flag continuous → classified (fallback on)" status_exists gs23
}
S2_3

echo "=== 4/S2-4: absent-flag task/wave/epic → skipped, audited SKIP-UNARMED (fallback off, all 3 scales) ==="
S2_4() {
  local scale
  for scale in task wave epic; do
    new_home
    local plan="$HOME/plans/gs24-$scale.plan.md"
    plant_plan "$plan" 4 0 "$scale"          # watchdog absent
    plant_goal "gs24-$scale" "$plan" "/proj/s24-$scale" "sid-s24-$scale" 4242
    plant_transcript_age "/proj/s24-$scale" "sid-s24-$scale" 30 user
    stub_registry_state idle "sid-s24-$scale"
    run_poker
    assert_eq "4/S2-4 ($scale) poker exit 0" 0 "$POKER_EXIT"
    assert_true "4/S2-4 ($scale) absent-flag → NOT classified (fallback off)" \
      not_status_exists "gs24-$scale"
    assert_contains "4/S2-4 ($scale) skip is audited SKIP-UNARMED" "gs24-$scale SKIP-UNARMED" "$(audit_of)"
  done
}
S2_4

echo "=== 4/S2-5: explicit watchdog:on task-scale → armed ==="
S2_5() {
  new_home
  local plan="$HOME/plans/gs25.plan.md"
  plant_plan "$plan" 4 0 task on            # scale: task, watchdog: on
  plant_goal gs25 "$plan" /proj/s25 sid-s25 4242
  plant_transcript_age /proj/s25 sid-s25 30 user
  stub_registry_state idle sid-s25
  run_poker
  assert_eq "4/S2-5 poker exit 0" 0 "$POKER_EXIT"
  assert_true "4/S2-5 watchdog:on task-scale → classified" status_exists gs25
}
S2_5

echo "=== 4/S2-6: off-enum watchdog value → MALFORMED-RECORD (fail-loud, never guess; distinct from SKIP-UNARMED) ==="
S2_6() {
  new_home
  local plan="$HOME/plans/gs26.plan.md"
  plant_plan "$plan" 4 0 continuous maybe   # watchdog: maybe (off-enum)
  plant_goal gs26 "$plan" /proj/s26 sid-s26 4242
  plant_transcript_age /proj/s26 sid-s26 30 user
  stub_registry_state idle sid-s26
  run_poker
  assert_eq "4/S2-6 poker exit 0" 0 "$POKER_EXIT"
  assert_true "4/S2-6 off-enum watchdog → NOT classified" not_status_exists gs26
  assert_contains "4/S2-6 off-enum watchdog → MALFORMED-RECORD audited" "gs26 MALFORMED-RECORD" "$(audit_of)"
  assert_true "4/S2-6 off-enum watchdog → NOT the SKIP-UNARMED line (fail-loud, not a guessed skip)" \
    bash -c '! printf "%s" "$1" | grep -qF "gs26 SKIP-UNARMED"' _ "$(audit_of)"
}
S2_6

echo "=== 4/S2-7 (AS-11 guard, REGRESSION LOCK): empty SESSION_ID → MALFORMED-RECORD, no classify, no resume ==="
# Already-GREEN pre-change, not a RED->GREEN pair: load_registration's existing
# `[ -n "$REG_SESSION_ID" ]` check (hooks/sdlc-poker.sh:124-125) already refuses
# an empty SESSION_ID as "missing required key in registration" before is_armed
# is ever reached — verified against the unmodified script at 7cbfae8. No code
# change was made for this case; it is locked here so a future edit to
# load_registration cannot silently regress the AS-11 guarantee.
S2_7() {
  new_home
  local plan="$HOME/plans/gs27.plan.md"
  plant_plan "$plan" 4 0 continuous
  plant_goal gs27 "$plan" /proj/s27 "" 4242   # SESSION_ID field present but empty
  plant_transcript_age /proj/s27 sid-s27 30 user
  stub_registry_state idle sid-s27
  run_poker
  assert_eq "4/S2-7 poker exit 0" 0 "$POKER_EXIT"
  assert_true "4/S2-7 empty SESSION_ID → NOT classified" not_status_exists gs27
  assert_contains "4/S2-7 empty SESSION_ID → MALFORMED-RECORD audited" "gs27 MALFORMED-RECORD" "$(audit_of)"
  assert_eq "4/S2-7 empty SESSION_ID → no resume attempted" "0" \
    "$(count_lines "$(claude_calls)" "resume ")"
}
S2_7

# ==========  slice 4/S3 — corroborated wedge detector (R4/AC-5; probe Q7)  =====
# A WEDGED classification now requires ALL of: registry-busy (or status-null
# in-flight), transcript bytes flat, and quiet beyond the pilot-keyed ceiling —
# corroborated across SDLC_WEDGE_OBS consecutive polls. Process-tree cputime
# flatness SUPPORTS the verdict; accumulating cputime forces AMBIGUOUS (notify-
# only, never restart). Detection + audit lines only — no new actions this slice.

# Read the observation state file / its poll counter (4th field).
wedge_state_of() { cat "$HOME/.claude/sdlc-status/.state/$1.wedge" 2>/dev/null || true; }
wedge_count_of() { awk '{print $4+0; exit}' "$HOME/.claude/sdlc-status/.state/$1.wedge" 2>/dev/null || echo 0; }

# One in-process wedge poll with a controlled process-tree cputime: routes through
# classify_goal (loads the registration, then busy_or_wedged → wedge_corroborated).
# The CPU-FAKE seam is scoped to this single call and auto-cleared (VAR=val func).
wedge_poll() {  # <gid> <cpu-fake>  → echoes classification
  SDLC_WEDGE_CPU_FAKE="$2" classify_goal "$1"
}

echo "=== 4/S3-cpu: process-tree cputime — parser formats, fake seam, real read ==="
S3_cpu() {
  new_home
  # _cputime_to_secs: SS(.ss) | MM:SS(.ss) | HH:MM:SS | DD-HH:MM:SS | empty.
  assert_eq "4/S3 cputime parse empty→0"        "0"     "$(_cputime_to_secs '')"
  assert_eq "4/S3 cputime parse 45→45"          "45"    "$(_cputime_to_secs '45')"
  assert_eq "4/S3 cputime parse 0:05.50→5"      "5"     "$(_cputime_to_secs '0:05.50')"
  assert_eq "4/S3 cputime parse 1:30→90"        "90"    "$(_cputime_to_secs '1:30')"
  assert_eq "4/S3 cputime parse 2:03:04→7384"   "7384"  "$(_cputime_to_secs '2:03:04')"
  assert_eq "4/S3 cputime parse 1-02:03:04"     "93784" "$(_cputime_to_secs '1-02:03:04')"
  # Fake seam: numeric echoed as tree total (rc0); literal GONE models vanish (rc1).
  assert_eq "4/S3 cputime fake numeric" "42" "$(SDLC_WEDGE_CPU_FAKE=42 wedge_cputime 999999)"
  TOTAL=$((TOTAL + 1))
  if SDLC_WEDGE_CPU_FAKE=GONE wedge_cputime 999999 >/dev/null 2>&1; then fail "4/S3 cputime fake GONE → rc1"; else pass "4/S3 cputime fake GONE → rc1"; fi
  # Real read: a live pid (this process) yields a non-negative integer, rc0.
  TOTAL=$((TOTAL + 1))
  local v; v=$(wedge_cputime "$$"); local rc=$?
  if [ "$rc" -eq 0 ] && printf '%s' "$v" | grep -qE '^[0-9]+$'; then pass "4/S3 cputime real live pid → integer ($v)"; else fail "4/S3 cputime real live pid" "rc=$rc v='$v'"; fi
  # Real read: a definitely-dead pid → rc1 (vanished-vehicle signal).
  TOTAL=$((TOTAL + 1))
  if wedge_cputime 2147483647 >/dev/null 2>&1; then fail "4/S3 cputime dead pid → rc1"; else pass "4/S3 cputime dead pid → rc1"; fi
}
S3_cpu

# One DIRECT wedge-detector poll: load the goal's registration into REG_* (as
# classify_goal would), then run wedge_corroborated with a controlled process-tree
# cputime. CORROB_RC captures its rc (0 = corroborated). The CPU-FAKE seam is scoped
# to the single call (VAR=val func) — no leak across polls.
CORROB_RC=0
corrob_poll() {  # <gid> <cpu-fake>
  load_registration "$1" >/dev/null 2>&1
  SDLC_WEDGE_CPU_FAKE="$2" wedge_corroborated "$1"; CORROB_RC=$?
}

# Append a busy line to a goal's transcript (byte size grows) and re-age it — models
# transcript MOVEMENT mid-observation without changing the resolved path.
move_transcript() {  # <cwd> <sid> <age>
  local cwd="$1" sid="$2" age="$3" pdir t
  pdir=$(real_project_dir "$cwd"); t="$pdir/$sid.jsonl"
  printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash"}]}}' >> "$t"
  set_mtime_age "$t" "$age"
}

echo "=== 4/S3-corroborate: true hang (AUTO, flat cpu, >ceiling) → WEDGED at OBS ==="
S3_corroborate() {
  new_home
  local cwd; cwd=$(real_cwd s3c)
  arm_goal g3c 4 "$cwd" sid-3c 4242 1000 busy    # continuous → pilot AUTO, ceiling 900; quiet 1000>900
  corrob_poll g3c 100; assert_eq "4/S3 poll1 not yet corroborated (baseline)" "1" "$CORROB_RC"
  assert_eq "4/S3 poll1 count=1" "1" "$(wedge_count_of g3c)"
  corrob_poll g3c 100; assert_eq "4/S3 poll2 not yet corroborated" "1" "$CORROB_RC"
  assert_eq "4/S3 poll2 count=2" "2" "$(wedge_count_of g3c)"
  corrob_poll g3c 100; assert_eq "4/S3 poll3 CORROBORATED (rc0)" "0" "$CORROB_RC"
  assert_eq "4/S3 poll3 count=3" "3" "$(wedge_count_of g3c)"
}
S3_corroborate

echo "=== 4/S3-ambiguous: long compute (cpu climbing) → AMBIGUOUS, never corroborated ==="
S3_ambiguous() {
  new_home
  local cwd; cwd=$(real_cwd s3a)
  arm_goal g3a 4 "$cwd" sid-3a 4242 1000 busy
  corrob_poll g3a 100; assert_eq "4/S3-amb poll1 baseline" "1" "$CORROB_RC"
  corrob_poll g3a 200; assert_eq "4/S3-amb poll2 NOT corroborated (cpu climbing)" "2" "$CORROB_RC"
  corrob_poll g3a 300; assert_eq "4/S3-amb poll3 NOT corroborated (cpu climbing)" "2" "$CORROB_RC"
  assert_eq "4/S3-amb never reaches OBS (count stays 1)" "1" "$(wedge_count_of g3a)"
  assert_contains "4/S3-amb WEDGE-AMBIGUOUS audit present" "g3a WEDGE-AMBIGUOUS cpu-active" "$(audit_of)"
}
S3_ambiguous

echo "=== 4/S3-ceilings: quiet ceiling is pilot-keyed (AUTO 900 / MANUAL 1800) ==="
S3_ceilings() {
  # 700s < both ceilings → never corroborated, under AUTO and under MANUAL.
  new_home
  local cwd; cwd=$(real_cwd s3ka)
  arm_goal g3ka 4 "$cwd" sid-3ka 4242 700 busy               # AUTO, quiet 700 < 900
  corrob_poll g3ka 50; corrob_poll g3ka 50; corrob_poll g3ka 50
  assert_eq "4/S3-ceil 700s AUTO → not corroborated" "1" "$CORROB_RC"
  assert_eq "4/S3-ceil 700s AUTO → count held at 0 (below ceiling)" "0" "$(wedge_count_of g3ka)"

  new_home
  cwd=$(real_cwd s3km)
  local plan="$HOME/plans/g3km.plan.md"
  plant_plan "$plan" 4 0 continuous "" manual                 # explicit pilot manual, ceiling 1800
  plant_goal g3km "$plan" "$cwd" sid-3km 4242
  plant_transcript_age "$cwd" sid-3km 700 busy               # quiet 700 < 1800
  corrob_poll g3km 50; corrob_poll g3km 50; corrob_poll g3km 50
  assert_eq "4/S3-ceil 700s MANUAL → not corroborated" "1" "$CORROB_RC"

  # 1000s: crosses AUTO (900) but not MANUAL (1800) — proves the key selects.
  new_home
  cwd=$(real_cwd s3aa)
  arm_goal g3aa 4 "$cwd" sid-3aa 4242 1000 busy               # AUTO, 1000 > 900
  corrob_poll g3aa 10; corrob_poll g3aa 10; corrob_poll g3aa 10
  assert_eq "4/S3-ceil 1000s AUTO → CORROBORATED" "0" "$CORROB_RC"

  new_home
  cwd=$(real_cwd s3mm)
  plan="$HOME/plans/g3mm.plan.md"
  plant_plan "$plan" 4 0 continuous "" manual                 # manual, ceiling 1800
  plant_goal g3mm "$plan" "$cwd" sid-3mm 4242
  plant_transcript_age "$cwd" sid-3mm 1000 busy              # quiet 1000 < 1800
  corrob_poll g3mm 10; corrob_poll g3mm 10; corrob_poll g3mm 10
  assert_eq "4/S3-ceil 1000s MANUAL → not corroborated (below MANUAL ceiling)" "1" "$CORROB_RC"

  # manual corroborates once quiet exceeds its (longer) ceiling — the path works.
  new_home
  cwd=$(real_cwd s3mc)
  plan="$HOME/plans/g3mc.plan.md"
  plant_plan "$plan" 4 0 continuous "" manual
  plant_goal g3mc "$plan" "$cwd" sid-3mc 4242
  plant_transcript_age "$cwd" sid-3mc 2000 busy              # quiet 2000 > 1800
  corrob_poll g3mc 10; corrob_poll g3mc 10; corrob_poll g3mc 10
  assert_eq "4/S3-ceil 2000s MANUAL → CORROBORATED" "0" "$CORROB_RC"
}
S3_ceilings

echo "=== 4/S3-reset-transcript: movement mid-observation resets the counter ==="
S3_reset_transcript() {
  new_home
  local cwd; cwd=$(real_cwd s3rt)
  arm_goal g3rt 4 "$cwd" sid-3rt 4242 1000 busy
  corrob_poll g3rt 5; corrob_poll g3rt 5
  assert_eq "4/S3-rst count=2 before move" "2" "$(wedge_count_of g3rt)"
  move_transcript "$cwd" sid-3rt 1000                        # transcript bytes change → reset
  corrob_poll g3rt 5
  assert_eq "4/S3-rst poll after move → not corroborated" "1" "$CORROB_RC"
  assert_eq "4/S3-rst counter reset to 1 (state file proves it)" "1" "$(wedge_count_of g3rt)"
}
S3_reset_transcript

echo "=== 4/S3-partial: 2 of 3 polls → not corroborated, WEDGE-OBSERVE present ==="
S3_partial() {
  new_home
  local cwd; cwd=$(real_cwd s3p)
  arm_goal g3p 4 "$cwd" sid-3p 4242 1000 busy
  corrob_poll g3p 5; corrob_poll g3p 5
  assert_eq "4/S3-partial 2/3 → not corroborated" "1" "$CORROB_RC"
  assert_eq "4/S3-partial count=2" "2" "$(wedge_count_of g3p)"
  assert_contains "4/S3-partial WEDGE-OBSERVE audit present" "g3p WEDGE-OBSERVE n=2" "$(audit_of)"
}
S3_partial

echo "=== 4/S3-pid-vanish: pid gone mid-observation → reset, no crash, no corroboration ==="
S3_pid_vanish() {
  new_home
  local cwd; cwd=$(real_cwd s3pv)
  arm_goal g3pv 4 "$cwd" sid-3pv 4242 1000 busy
  corrob_poll g3pv 100; assert_eq "4/S3-pv poll1 baseline" "1" "$CORROB_RC"
  corrob_poll g3pv GONE                                       # pid vanished mid-read
  assert_eq "4/S3-pv vanished poll → not corroborated" "1" "$CORROB_RC"
  assert_eq "4/S3-pv counter reset (0)" "0" "$(wedge_count_of g3pv)"
  # A subsequent flat poll must not resurrect a stale count — starts fresh.
  corrob_poll g3pv 100; assert_eq "4/S3-pv post-vanish restarts baseline (count=1)" "1" "$(wedge_count_of g3pv)"
}
S3_pid_vanish

# ==========  slice 4/S4 — manual pilot verb set (R2/AC-4; KA-R4/R5)  =====
# Under pilot=manual the poker is notify-only: ZERO drive verbs (no poke/spawn/
# restart/kill) in every goal state and on death, while emitting exactly the
# contracted notification. Both directions (AC-4): manual specimens → zero seam +
# correct notify, and no notify below the decay window; the SAME drive-contracted
# states under auto reach the drive plumbing (differential proof the gate is
# pilot-keyed, not broken plumbing). The manual path never touches do_poke, so
# these cases call dispatch_actions / dispatch_manual IN-PROCESS (S3 direct-call
# style); the auto-differential cases point do_poke at the stub first.

# A manual-armed plan: scale wave, watchdog on (armed), pilot manual (notify-only).
plant_manual_plan() { plant_plan "$1" "$2" "${3:-0}" wave on manual; }
# An auto-armed plan: continuous ⇒ watchdog on + pilot auto by fallback ⇒ drives.
plant_auto_plan()   { plant_plan "$1" "$2" "${3:-0}" continuous; }
# Load a planted goal's registration into REG_* (as process_goals would) so a
# direct dispatch call runs against it.
load_reg() { load_registration "$1" >/dev/null 2>&1; }
# Count drive-seam (resume poke) invocations recorded by the stub.
resume_calls() { count_lines "$(claude_calls)" "resume "; }
# Count ntfy POSTs recorded by the curl stub (each notification = one line).
notify_calls() { count_lines "$(curl_calls)" "."; }

echo "=== 4/S4-manual-busy: BUSY (working) → zero seam, zero notification ==="
S4_manual_busy() {
  new_home
  local cwd plan; cwd=$(real_cwd s4b); plan="$HOME/plans/g4b.plan.md"
  plant_manual_plan "$plan" 4
  plant_goal g4b "$plan" "$cwd" sid-4b 4242
  plant_transcript_age "$cwd" sid-4b 30 busy
  load_reg g4b
  dispatch_actions g4b BUSY ""
  assert_eq "4/S4-busy manual → zero resume seam" "0" "$(resume_calls)"
  assert_eq "4/S4-busy manual → zero notification" "0" "$(notify_calls)"
  assert_contains "4/S4-busy manual → SKIP-MANUAL audited" "g4b SKIP-MANUAL" "$(audit_of)"
}
S4_manual_busy

echo "=== 4/S4-manual-idle-below: idle-thinking below the ready window → zero notify (negative) ==="
S4_manual_idle_below() {
  new_home
  local cwd plan; cwd=$(real_cwd s4ib); plan="$HOME/plans/g4ib.plan.md"
  plant_manual_plan "$plan" 4
  plant_goal g4ib "$plan" "$cwd" sid-4ib 4242
  plant_transcript_age "$cwd" sid-4ib 300 user   # quiet 300: >180 stall, <1800 ready window
  load_reg g4ib
  dispatch_actions g4ib IDLE_STALLED ""
  assert_eq "4/S4-idle-below manual → zero resume seam" "0" "$(resume_calls)"
  assert_eq "4/S4-idle-below manual → zero notification (below ready window)" "0" "$(notify_calls)"
}
S4_manual_idle_below

echo "=== 4/S4-manual-ready: idle past the ready window → READY-IDLE once across 3 polls (dedupe) ==="
S4_manual_ready() {
  new_home
  local cwd plan; cwd=$(real_cwd s4r); plan="$HOME/plans/g4r.plan.md"
  plant_manual_plan "$plan" 4
  plant_goal g4r "$plan" "$cwd" sid-4r 4242
  plant_transcript_age "$cwd" sid-4r 2000 user   # quiet 2000 > 1800 ready window
  stub_registry_state idle sid-4r
  run_poker; run_poker; run_poker                  # 3 real polls, cache persists across them
  assert_eq "4/S4-ready manual → zero resume seam across 3 polls" "0" "$(resume_calls)"
  assert_eq "4/S4-ready manual → READY-IDLE notified exactly once (deduped)" "1" \
    "$(count_lines "$(audit_of)" "g4r READY-IDLE notified")"
  assert_eq "4/S4-ready manual → exactly one ntfy POST" "1" "$(notify_calls)"
}
S4_manual_ready

echo "=== 4/S4-manual-wedge: corroborated WEDGED → WEDGE-ASK, zero restart/kill seam ==="
S4_manual_wedge() {
  new_home
  local cwd plan; cwd=$(real_cwd s4w); plan="$HOME/plans/g4w.plan.md"
  plant_manual_plan "$plan" 4
  plant_goal g4w "$plan" "$cwd" sid-4w 4242
  plant_transcript_age "$cwd" sid-4w 2000 busy
  load_reg g4w
  dispatch_actions g4w WEDGED ""
  assert_eq "4/S4-wedge manual → zero resume/restart/kill seam" "0" "$(resume_calls)"
  assert_contains "4/S4-wedge manual → WEDGE-ASK notified" "g4w WEDGE-ASK notified" "$(audit_of)"
  assert_contains "4/S4-wedge manual → notification carries approve-restart ask" "approve restart?" \
    "$(curl_calls)"
}
S4_manual_wedge

echo "=== 4/S4-manual-dead: sid absent (DEAD) → DEAD-MANUAL notify, zero poke/spawn seam ==="
S4_manual_dead() {
  new_home
  local cwd plan; cwd=$(real_cwd s4d); plan="$HOME/plans/g4d.plan.md"
  plant_manual_plan "$plan" 5
  plant_goal g4d "$plan" "$cwd" sid-4d 2147483647
  plant_transcript_age "$cwd" sid-4d 300 user
  load_reg g4d
  dispatch_actions g4d DEAD ""
  assert_eq "4/S4-dead manual → zero poke/spawn seam" "0" "$(resume_calls)"
  assert_contains "4/S4-dead manual → DEAD-MANUAL notified" "g4d DEAD-MANUAL notified" "$(audit_of)"
  assert_contains "4/S4-dead manual → notification says WIP preserved" "WIP preserved" "$(curl_calls)"
}
S4_manual_dead

echo "=== 4/S4-manual-gated: entry notify + reminder past the window (window-deduped) ==="
S4_manual_gated() {
  new_home
  local cwd plan; cwd=$(real_cwd s4g); plan="$HOME/plans/g4g.plan.md"
  plant_manual_plan "$plan" 4 1                    # wake note ⇒ GATED
  plant_goal g4g "$plan" "$cwd" sid-4g 4242
  plant_transcript_age "$cwd" sid-4g 300 user
  load_reg g4g
  dispatch_manual g4g GATED ""                     # entry → notify once + seed window
  assert_eq "4/S4-gated entry → one notification" "1" "$(notify_calls)"
  dispatch_manual g4g GATED GATED                  # within window → suppressed
  assert_eq "4/S4-gated within window → still one notification" "1" "$(notify_calls)"
  # window elapsed: backdate the reminder stamp beyond SDLC_GATED_REMIND
  printf '%s\n' "$(( $(date +%s) - SDLC_GATED_REMIND - 10 ))" > "$HOME/.claude/sdlc-status/.state/g4g.remind-gated"
  dispatch_manual g4g GATED GATED                  # window elapsed → reminder fires
  assert_eq "4/S4-gated past window → reminder notification (two total)" "2" "$(notify_calls)"
  assert_eq "4/S4-gated → zero drive seam throughout" "0" "$(resume_calls)"
}
S4_manual_gated

echo "=== 4/S4-auto-differential: the SAME drive-contracted states under AUTO reach the poke seam ==="
S4_auto_differential() {
  # IDLE_STALLED under auto (continuous ⇒ pilot auto) → legacy poke fires.
  new_home
  mkdir -p "$HOME/.claude/sdlc-status/.state"      # main() mints this; in-process dispatch needs it for poke_capped
  POKE_CLAUDE_BIN="$HOME/.claude/.stub/claude"     # point in-process do_poke at the stub
  local cwd plan; cwd=$(real_cwd s4ai); plan="$HOME/plans/g4ai.plan.md"
  plant_auto_plan "$plan" 4
  plant_goal g4ai "$plan" "$cwd" sid-4ai 4242
  plant_transcript_age "$cwd" sid-4ai 300 user
  load_reg g4ai
  dispatch_actions g4ai IDLE_STALLED ""
  assert_true "4/S4-diff auto IDLE_STALLED → poke seam FIRES (gate is pilot-keyed)" \
    test "$(resume_calls)" -ge 1

  # DEAD under auto (baton-less) → legacy poke fires.
  new_home
  mkdir -p "$HOME/.claude/sdlc-status/.state"
  POKE_CLAUDE_BIN="$HOME/.claude/.stub/claude"
  cwd=$(real_cwd s4ad); plan="$HOME/plans/g4ad.plan.md"
  plant_auto_plan "$plan" 4
  plant_goal g4ad "$plan" "$cwd" sid-4ad 2147483647
  plant_transcript_age "$cwd" sid-4ad 300 user
  load_reg g4ad
  dispatch_actions g4ad DEAD ""
  assert_true "4/S4-diff auto DEAD → poke seam FIRES" test "$(resume_calls)" -ge 1
}
S4_auto_differential

# ==========  slice 4/S5 — presence rule + restart execution (R3/AC-6/AC-12)  =====
# The PRESENCE RULE (KA-R13): a status-non-null vehicle (live TUI) bars ALL drive
# verbs regardless of pilot; a registry-degraded goal (lib present) fails closed to
# notify-only. AMBIGUOUS wedges never restart. The restart cap parks GATED. Every
# drive-seam is stubbed (arm_restart_seams) so no real process is signalled.

echo "=== 4/S5-attached-idle: IDLE_STALLED with a live TUI (status idle) → SKIP-LIVE-TUI, STALL-ATTACHED nag, zero drive seam ==="
S5_attached_idle() {
  new_home
  local cwd; cwd=$(ladder_cwd sai)
  arm_goal gsai 4 "$cwd" sid-sai 2147483647 400 user   # idle + stale → IDLE_STALLED
  stub_registry_state idle sid-sai                       # status idle = live TUI = attended
  plant_baton gsai "next"                                # baton present — must STILL not drive
  arm_restart_seams
  run_poker
  disarm_restart_seams
  assert_contains "4/S5-attached-idle → SKIP-LIVE-TUI audited" "gsai SKIP-LIVE-TUI" "$(audit_of)"
  assert_eq "4/S5-attached-idle → ZERO poke seam" "" "$(claude_calls)"
  assert_eq "4/S5-attached-idle → ZERO SIGTERM seam" "0" "$(restart_term_count)"
  assert_eq "4/S5-attached-idle → ZERO spawn seam" "0" "$(restart_spawn_count)"
  assert_contains "4/S5-attached-idle → STALL-ATTACHED nag notify (AUTO would have driven)" "Title: gsai: STALL-ATTACHED" "$(curl_calls)"
}
S5_attached_idle

echo "=== 4/S5-attached-wedged: WEDGED with a live TUI (status busy) → SKIP-LIVE-TUI, zero SIGTERM/spawn (never kill an attended vehicle) ==="
S5_attached_wedged() {
  new_home
  local cwd; cwd=$(ladder_cwd saw)
  arm_goal gsaw 4 "$cwd" sid-saw 2147483647 1000 busy   # busy + quiet>ceiling + primed → WEDGED
  stub_registry_state busy sid-saw                        # status busy = live TUI = attended
  plant_baton gsaw "next"
  prime_wedged gsaw 0
  arm_restart_seams
  export SDLC_WEDGE_CPU_FAKE=0
  run_poker
  unset SDLC_WEDGE_CPU_FAKE; disarm_restart_seams
  assert_contains "4/S5-attached-wedged → SKIP-LIVE-TUI audited" "gsaw SKIP-LIVE-TUI" "$(audit_of)"
  assert_eq "4/S5-attached-wedged → ZERO SIGTERM seam (kill of an attended vehicle forbidden)" "0" "$(restart_term_count)"
  assert_eq "4/S5-attached-wedged → ZERO spawn seam" "0" "$(restart_spawn_count)"
  assert_eq "4/S5-attached-wedged → ZERO restart effect journaled" "0" \
    "$(count_lines "$(cat "$(ledger_path gsaw)" 2>/dev/null || true)" "restart:")"
}
S5_attached_wedged

echo "=== 4/S5-degraded: registry unavailable + lib present → SKIP-DEGRADED, notify-only, zero drive ==="
S5_degraded() {
  new_home
  local cwd; cwd=$(ladder_cwd sdg)
  arm_goal gsdg 4 "$cwd" sid-sdg 2147483647 400 user   # dead pid → degrade_classify → DEAD
  stub_registry_state fail                               # registry rc≠0 → degrade; lib IS present
  plant_baton gsdg "next"
  arm_restart_seams
  run_poker
  disarm_restart_seams
  assert_contains "4/S5-degraded → SKIP-DEGRADED audited (fail-closed, presence unconfirmable)" "gsdg SKIP-DEGRADED" "$(audit_of)"
  assert_eq "4/S5-degraded → ZERO poke seam" "" "$(claude_calls)"
  assert_eq "4/S5-degraded → ZERO SIGTERM seam" "0" "$(restart_term_count)"
  assert_eq "4/S5-degraded → ZERO spawn seam" "0" "$(restart_spawn_count)"
  assert_eq "4/S5-degraded → ZERO restart effect journaled" "0" \
    "$(count_lines "$(cat "$(ledger_path gsdg)" 2>/dev/null || true)" "restart:")"
}
S5_degraded

echo "=== 4/S5-ambiguous: high-CPU quiet (AMBIGUOUS wedge) → BUSY, never restart ==="
S5_ambiguous_never_restart() {
  new_home
  local cwd; cwd=$(ladder_cwd sam)
  arm_goal gsam 4 "$cwd" sid-sam 2147483647 1000 busy
  stub_registry_state nostatus sid-sam                    # tui-less, WEDGED-shaped
  plant_baton gsam "next"
  prime_wedged gsam 0                                      # cputime baseline 0
  arm_restart_seams
  export SDLC_WEDGE_CPU_FAKE=500                           # cputime CLIMBING → AMBIGUOUS (probe Q7) → BUSY
  run_poker
  unset SDLC_WEDGE_CPU_FAKE; disarm_restart_seams
  assert_eq "4/S5-ambiguous → ZERO SIGTERM seam (ambiguous never restarts)" "0" "$(restart_term_count)"
  assert_eq "4/S5-ambiguous → ZERO spawn seam" "0" "$(restart_spawn_count)"
  assert_eq "4/S5-ambiguous → ZERO restart effect journaled" "0" \
    "$(count_lines "$(cat "$(ledger_path gsam)" 2>/dev/null || true)" "restart:")"
  assert_contains "4/S5-ambiguous → WEDGE-AMBIGUOUS audited (notify-only)" "gsam WEDGE-AMBIGUOUS" "$(audit_of)"
}
S5_ambiguous_never_restart

echo "=== 4/S5-restart-cap: 2 restarts spent → restart-exhausted parks GATED + GATED notify, ladder stops ==="
S5_restart_cap() {
  new_home
  local cwd; cwd=$(ladder_cwd src)
  arm_goal gsrc 4 "$cwd" sid-src 2147483647 1000 busy
  stub_registry_state nostatus sid-src
  plant_baton gsrc "next"
  prime_wedged gsrc 0
  local anc; anc=$(anchor_of gsrc)
  # Seed the cap as spent: two applied restart effects under the current anchor.
  sdlc_effect_run gsrc "restart:gsrc:$anc:1" "restart 1" -- true >/dev/null 2>&1
  sdlc_effect_run gsrc "restart:gsrc:$anc:2" "restart 2" -- true >/dev/null 2>&1
  arm_restart_seams
  export SDLC_WEDGE_CPU_FAKE=0
  run_poker
  unset SDLC_WEDGE_CPU_FAKE; disarm_restart_seams
  assert_contains "4/S5-cap → restart cap park audited (LADDER-RESTART-EXHAUSTED)" "gsrc LADDER-RESTART-EXHAUSTED" "$(audit_of)"
  assert_contains "4/S5-cap → plan parked GATED (Wake Note appended)" "## Wake Note" "$(cat "$HOME/plans/gsrc.plan.md")"
  assert_contains "4/S5-cap → GATED notification rides the exhaustion" "Title: gsrc: GATED" "$(curl_calls)"
  assert_eq "4/S5-cap → NO third restart (ladder stopped at the cap)" "0" "$(restart_term_count)"
  assert_eq "4/S5-cap → NO new successor spawned" "0" "$(restart_spawn_count)"
}
S5_restart_cap

# ============================================================
# ============  slice 4/S6 — lifecycle hygiene  ===============
# (a) COMPLETE auto-clean: post-latch (complete_latch rc=0) removes the
#     registration via sdlc_disarm; a false-complete park (rc=2) retains it.
# (b) Per-poll per-sid drive dedupe: a second armed goal resolving to an
#     already-driven SESSION_ID this poll is skipped + audited
#     SKIP-SID-DEDUPE; notify-only actions never consume the dedupe slot.
# ============================================================

echo "=== 4/S6-autoclean-genuine: genuinely-merged COMPLETE → registration removed exactly once, DISARM audited ==="
S6_autoclean_genuine() {
  new_home
  arm_complete cac6 yes
  run_poker            # poll1: latches + auto-cleans
  run_poker            # poll2: record already gone — no-op, no second audit line
  assert_true "4/S6-autoclean-genuine registration removed after the latch" not_reg_exists cac6
  assert_eq "4/S6-autoclean-genuine exactly one DISARM audit line" "1" "$(count_lines "$(audit_of)" "cac6 DISARM")"
  assert_contains "4/S6-autoclean-genuine DISARM reason=complete" "cac6 DISARM complete" "$(audit_of)"
  assert_eq "4/S6-autoclean-genuine COMPLETE still notified exactly once" "1" \
    "$(count_lines "$(curl_calls)" "cac6: COMPLETE")"
}
S6_autoclean_genuine

echo "=== 4/S6-autoclean-false: false-complete (branch unmerged) → latch parks GATED, registration RETAINED (never bypass the park) ==="
S6_autoclean_false() {
  new_home
  arm_complete caf6 no
  run_poker
  assert_true "4/S6-autoclean-false registration RETAINED (parked goals stay registered)" reg_exists caf6
  assert_contains "4/S6-autoclean-false COMPLETE-FALSE park audited" "caf6 COMPLETE-FALSE" "$(audit_of)"
  TOTAL=$((TOTAL + 1))
  if ! printf '%s' "$(audit_of)" | grep -q "caf6 DISARM"; then
    pass "4/S6-autoclean-false no DISARM fired on a false-complete park"
  else fail "4/S6-autoclean-false unexpected DISARM" "$(audit_of)"; fi
}
S6_autoclean_false

echo "=== 4/S6-dedupe-drive: two AUTO tui-less goals sharing one SESSION_ID → exactly one drive + one SKIP-SID-DEDUPE ==="
S6_dedupe_drive() {
  new_home
  local cwd; cwd=$(ladder_cwd dd6)
  arm_goal gdd61 4 "$cwd" sid-dd6-shared 2147483647 300 user   # DEAD (registry absent → tui-less)
  arm_goal gdd62 4 "$cwd" sid-dd6-shared 2147483647 300 user   # same sid — a shared-session double-registration
  stub_registry_state absent
  plant_baton gdd61 "next"
  plant_baton gdd62 "next"
  run_poker
  assert_eq "4/S6-dedupe-drive exactly one poke reached the shared sid this poll" "1" \
    "$(count_lines "$(claude_calls)" "resume sid-dd6-shared")"
  assert_eq "4/S6-dedupe-drive exactly one SKIP-SID-DEDUPE audit line" "1" \
    "$(count_lines "$(audit_of)" "SKIP-SID-DEDUPE")"
  assert_contains "4/S6-dedupe-drive the SECOND goal (gdd62, lexically later) is the one deduped" \
    "gdd62 SKIP-SID-DEDUPE" "$(audit_of)"
}
S6_dedupe_drive

echo "=== 4/S6-dedupe-notify-exempt: first goal only NOTIFIES (GATED) → never consumes the dedupe slot; second still drives ==="
S6_dedupe_notify_exempt() {
  new_home
  local cwd; cwd=$(ladder_cwd de6)
  arm_goal gde61 4 "$cwd" sid-de6-shared 2147483647 300 user 1   # wake=1 → GATED (notify-only, never ladders)
  arm_goal gde62 4 "$cwd" sid-de6-shared 2147483647 300 user     # same sid — DEAD, tui-less, drive-eligible
  stub_registry_state absent
  plant_baton gde62 "next"
  run_poker
  assert_eq "4/S6-dedupe-notify-exempt the drive-eligible goal still pokes (GATED notify never consumed the slot)" "1" \
    "$(count_lines "$(claude_calls)" "resume sid-de6-shared")"
  TOTAL=$((TOTAL + 1))
  if ! printf '%s' "$(audit_of)" | grep -q "SKIP-SID-DEDUPE"; then
    pass "4/S6-dedupe-notify-exempt no SKIP-SID-DEDUPE fired (only one drive-eligible goal reached this poll)"
  else fail "4/S6-dedupe-notify-exempt unexpected dedupe line" "$(audit_of)"; fi
}
S6_dedupe_notify_exempt

# ============================================================
echo ""
echo "========================================"
echo "sdlc-poker core: $PASS/$TOTAL passed, $FAIL failed"
echo "========================================"
[ "$FAIL" -eq 0 ] || exit 1
