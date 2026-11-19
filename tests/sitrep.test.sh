#!/bin/bash
# Tests for `hooks/session-poker.sh sitrep` — the situation report's fact sheet.
#
# THE VERB PRINTS FACTS, NEVER A PAGE. `sitrep [<plan>]` prints the sheet: a first line saying it is the model's
# input, then one fact per line, `<key>: <value>`, in a fixed order — the run (its release, name, wave, now, step,
# project, start and last landing), the ten steps, every task in execution order with its step, state, short
# description and a few words of note, the measurements (the clock, the work, pace and the close, correctness and
# waste, each line naming what it measures, its unit and its source), each goal's status, every ask open on
# the run's register with what it holds, and every review result with its open findings. Every clock time is
# local and 12-hour. `--line` is the Patrol's status, `<k> of <m> tasks · owed: <n> on you · <m> on events · close <time>`. The page,
# its Score marks, the review rows, the grade verb and its log are gone; the card a later verb draws reads this.
#
# HERMETIC. One repository per world under a temp root: a 17-task plan at version 15, its run's log and a gate
# store of its own. The clock is BIONIC_NOW_EPOCH
# (the poker's seam) and the zone is pinned, so every local time below is a fixed
# string; no case reads this machine's clock. The machine's probes are pinned as the session-poker
# prelude pins them, because the gate's scan samples them.
#
# FIXTURE FIDELITY. SYNTHESIZED, in the shapes the writers write: the run's log holding the approval, the steps, the
# landing's events as lib/line.sh writes them, the fill's stops as lib/stop.sh writes them, the asks as lib/owed.sh
# opens and closes them, the decisions' rounds and the proofs as lib/proof.sh writes them; the gate's request files as
# lib/gate.sh writes them, a session's binding through the bind verb itself, and a `## Tasks` header in the table shape
# the cells are read by. The sections that test an older run's homes (its asks register, its design ledger, its state
# section's landing lines) still write those homes. What each world pins is what the
# fact under test reads, and nothing it does not.
#
# ANTI-VACUITY. Each fact is read in a world that holds it and then moved by one planted change; each
# absence sits beside a positive read through the same extractor on the same sheet; the field reader is
# proved on a known line before it reads a sheet.
#
# THE SEAM, for RED evidence against a mutated copy without touching the shipped file:
#   SITREP_POKER_UNDER_TEST=/path/to/mutant.sh bash tests/sitrep.test.sh
#
# Usage: bash tests/sitrep.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"
. "$(dirname "$0")/lib/plan-fixture.sh"

POKER="${SITREP_POKER_UNDER_TEST:-${BIONIC_HOOKS_DIR}/session-poker.sh}"

TMPROOT="$(mktemp -d)"
cleanup() { chmod -R u+rwX "$TMPROOT" 2>/dev/null; rm -rf "$TMPROOT"; }
trap cleanup EXIT

export BIONIC_PLUGINS_DIR="$TMPROOT/no-plugins"; mkdir -p "$BIONIC_PLUGINS_DIR"
export BIONIC_PRESSURE_RING="$TMPROOT/pressure.ring"
export BIONIC_PROBE_FREE_MB=8192 BIONIC_PROBE_LOAD_1M=1.0 BIONIC_PROBE_FREE_PCT=60 BIONIC_PROBE_SWAP_PCT=0
export BIONIC_PROBE_CORES=8 BIONIC_PROBE_USED_PCT=30 BIONIC_PROBE_BUSY_CORES=1.0 BIONIC_PROBE_BUSY_CORES_5M=1.0
export CLAUDE_CONFIG_DIR="$TMPROOT/config"; mkdir -p "$CLAUDE_CONFIG_DIR/bionic"; printf '80\n' > "$CLAUDE_CONFIG_DIR/bionic/share"
export TZ=America/Los_Angeles

SID="5c1e7a2b-3d4f-4e8a-9b6c-1f2e3d4c5b6a"
SR_E0=1791280800      # 2026-10-06T10:00:00Z = 3:00 AM PDT
SR_NOW=1791324000     # 2026-10-06T22:00:00Z = 3:00 PM PDT
SR_C1="$(printf 'c%.0s' $(seq 40))"
SR_H="$(printf 'a%.0s' $(seq 40))"

# ---------- the world ----------
#
# sr_world <label> <landing minutes for T1..T4, space-separated | none> -> SR_REPO, SR_PLAN, SR_REC (the run's log),
# SR_DIR, SR_GATE. A page at 15 and its run's log. Seventeen rows, all Step 4 builds: T1–T4 landed (30 min each), T5–T8 active by their dispatch events, T9–T17 pending. T9 waits on T8 in its deps, so the remaining
# chain is T8→T9 (90 + 60 = 150 min); every other open row is 30 min and waits on no other.
# T12 waits on approval:release and T17 on approval:merge. With `none`, T1–T4 are pending too and the
# landing record holds no landing. Two gate requests are admitted and held by this shell, so the
# gate's admitted count is 2.
# THE CLOCK: the plan is approved at 10:00Z (its approval event's instant, 12 hours before
# NOW; SR_APPROVED=none leaves the event out, an unapproved plan) and declares `forecast: $SR_FORECAST` (48h when
# unset; an empty SR_FORECAST declares none). SR_EXTRA
# appends that many more pending 30-minute rows (T18…), reading nothing, so the plan's total grows and the
# chain does not. SR_SCALE, when set, declares `scale:`.
# THE RUN'S LOG, in the order its writers write it: the plan's approval and its step, the fill's first stop, each landed
# row's ready, verdict and `published` events as the landing writes them, T8's ready and the fill's second stop. The
# plan has no dispatch ledger, as the live plan has none.
sr_world() {
  local label="$1" mins="$2" r d p
  r="$TMPROOT/$label"; mkdir -p "$r/.bionic/tmp" "$r/.bionic/docs/plans/epic-01-fx"
  ( cd "$r" && git init -q . 2>/dev/null )
  d="$r/.bionic/docs/record/wave-02-fx"; mkdir -p "$d"
  p="$r/.bionic/docs/plans/epic-01-fx/wave-02-fx.plan.md"
  SR_REPO="$r"; SR_PLAN="$p"; SR_DIR="$d"; SR_REC="$d/run.log"; : > "$SR_REC"
  local st1=landed land=yes
  [ "$mins" = none ] && { st1=pending; land=no; }
  {
    printf -- '---\nwave: wave-02-fx\ncanonical_sdlc_version: 15\nrelease: 9.9.0\nworking-branch: wave/02-fx\nintegration-branch: main\n'
    [ -z "${SR_SCALE:-}" ] || printf 'scale: %s\n' "$SR_SCALE"
    [ -z "${SR_FORECAST-48h}" ] || printf 'forecast: %s\n' "${SR_FORECAST-48h}"
    [ -z "${SR_GOALS:-}" ] || printf '%s\n' "$SR_GOALS" | sed 's/^/goals: /'
    printf -- '---\n'
    printf '# fixture plan\n'
  } > "$p"
  [ "${SR_APPROVED-}" = none ] || sr_ev "ev=approval|key=step3|by=fixture|said=approved|at=2026-10-06T10:00:00Z"
  sr_ev "ev=step|n=4|at=2026-10-06T10:00:00Z"
  sr_stop t1 10:00:00 0 4 "" "" 0 "" 4
  local i at
  if [ "$land" = yes ]; then
    set -- $mins
    local readies="10:00:00 10:30:00 11:00:00 12:00:00" rd e
    i=1
    for rd in $readies; do
      e=$(( SR_E0 + $(sr_hms "$rd") + ${!i} * 60 ))
      at="$(sr_iso "$e")"
      sr_ev "ev=ready|row=T$i|name=w-T$i|commit=$SR_C1|branch=wt/02-T$i|tree=$r/.worktrees/02-T$i|suites=a.test.sh|debt=-|carrier=1:x|at=2026-10-06T${rd}Z"
      sr_ev "ev=verdict|row=T$i|commit=$SR_C1|suite=a.test.sh|result=green|log=/rec/T$i.log|at=$(sr_iso $((e - 60)))"
      sr_ev "ev=published|row=T$i|commit=$SR_C1|kind=queue|by=-|why=-|at=$at"
      i=$((i + 1))
    done
  fi
  for i in 5 6 7 8; do sr_ev "ev=dispatch|row=T$i|name=w-T$i|at=2026-10-06T10:00:00Z"; done
  sr_ev "ev=ready|row=T8|name=w-T8|commit=$SR_C1|branch=wt/02-T8|tree=$r/.worktrees/02-T8|suites=a.test.sh|debt=-|carrier=1:x|at=2026-10-06T13:00:00Z"
  # The fill's two turns, nothing idle, the first at 10:00Z (elapsed 720 min at NOW).
  sr_stop t2 16:00:00 4 0 "" "" 0 "" 0
  {
    printf '\n## Tasks\n\n'
    printf '| id | step | kind | task | deps | size | serves | Files | artifact |\n'
    printf '|---|---|---|---|---|---|---|---|---|\n'
    sr_row T1 "Row one the thing (D1; AC-1.1). More words · complexity: standard" — 30 "$st1"
    sr_row T2 "Haiku 5.5 at high (REQ-8; AC-8.1) · complexity: standard" — 30 "$st1"
    sr_row T3 "Third row. A second sentence · complexity: standard" — 30 "$st1"
    sr_row T4 "Fourth · complexity: complex" — 30 "$st1"
    for i in 5 6 7; do sr_row "T$i" "Row $i body · complexity: standard" — 30 active; done
    sr_row T8 "The long one (D8) · complexity: complex" — 90 active
    sr_row T9 "Waits on the long one · complexity: standard" T8 60 pending
    for i in 10 11 13 14 15 16; do sr_row "T$i" "Row $i body · complexity: standard" — 30 pending; done
    sr_row T12 "Release-gated row · complexity: standard" approval:release 30 pending
    sr_row T17 "Merge-gated row · complexity: standard" approval:merge 30 pending
    i=18; while [ "$i" -le $((17 + ${SR_EXTRA:-0})) ]; do sr_row "T$i" "Row $i body · complexity: standard" — 30 pending; i=$((i + 1)); done
    printf '\n## Not Doing\n\n- nothing\n'
  } >> "$p"
  SR_GATE="$TMPROOT/gate-$label"; mkdir -p "$SR_GATE/requests" "$SR_GATE/cost"
  for i in 1 2; do
    printf 'key=a.test.sh\nkind=landing\nwho=%s:w-T%d\ntree=/elsewhere/project\nasked=%d\nholder=%s:\nadmitted=%d\npromise=5:0.1:30\n' \
      "$SID" "$((i + 4))" "$((SR_NOW - 600))" "$$" "$((SR_NOW - 590))" > "$SR_GATE/requests/$i"
  done
}
sr_iso() { date -u -r "$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ; }
sr_hms() { local h="${1%%:*}" r="${1#*:}"; printf '%d' $(( 10#$h * 3600 + 10#${r%%:*} * 60 + 10#${r#*:} - 36000 )); }
sr_ev() { printf 'run/v1|%s\n' "$1" >> "$SR_REC"; }
sr_stop() {  # <turn> <hh:mm:ss on 2026-10-06, UTC> <open> <free> <ready> <launched> <missed> <idle> <room> -> one stop of the fill, as the stop writes it
  sr_ev "ev=stop|session=$SID|turn=$1|current=4|state=ok|ceiling=|width=4|open=$3|free=$4|ready=$5|launched=$6|declined=|missed=$7|idle=$8|room=$9|at=2026-10-06T${2}Z"
}
sr_row() {  # <id> <task> <deps> <size> -> the row in its nine cells; its state is the run's log (sr_state)
  local n="${1#T}"
  printf '| %s | 4 | build | %s | %s | %s | REQ-1 | lib/t%s.sh | — |\n' "$1" "$2" "$3" "$4" "$n"
}
sr_state() {  # <id> <landed|active|pending|dropped> -> the row's state in this world's log, by the events that move it
  case "$2" in
    landed) sr_ev "ev=published|row=$1|commit=$SR_C1|kind=queue|by=-|why=-|at=2026-10-06T21:00:00Z" ;;
    active) sr_ev "ev=cancel|of=published|row=$1|commit=$SR_C1|at=2026-10-06T21:00:00Z"
            sr_ev "ev=dispatch|row=$1|name=w-$1|at=2026-10-06T21:00:00Z" ;;
    pending) sr_ev "ev=cancel|of=dispatch|row=$1|name=w-$1|at=2026-10-06T21:00:00Z"
             sr_ev "ev=cancel|of=published|row=$1|commit=$SR_C1|at=2026-10-06T21:00:00Z" ;;
    dropped) sr_ev "ev=drop|row=$1|why=fixture|at=2026-10-06T21:00:00Z" ;;
  esac
}
sr_set() {  # <id> <kind|deps|size|files|status> <value> -> that cell of the row in this world's plan, or for status its log
  [ "$2" != status ] || { sr_state "$1" "$3"; return; }
  awk -F'|' -v id=" $1 " -v k="$2" -v v=" ${3:-—} " 'BEGIN { OFS = "|"; c["kind"] = 4; c["deps"] = 6; c["size"] = 7; c["files"] = 9 }
    $2 == id && NF > 9 { i = c[k]; $i = v } { print }' "$SR_PLAN" > "$SR_PLAN.t" && mv "$SR_PLAN.t" "$SR_PLAN"
}
sr_open() {  # <id> <kind> <size> <status> [<deps>] -> the row opened as that kind, size and state, waiting on the deps given
  sr_set "$1" kind "$2"; sr_set "$1" size "$3"; sr_set "$1" status "$4"; sr_set "$1" deps "${5:-—}"
}
SR_OWED_LIB="${BIONIC_HOOKS_DIR}/../payload/scripts/lib/owed.sh"
sr_asks() { bash -c '. "$1" && owed_lines "$2" "$3"' _ "$SR_OWED_LIB" "$SR_PLAN" "$SR_REPO" 2>/dev/null; }   # the run's asks as the asks library lists them
sr_log() { local p="${1:-$SR_PLAN}"; p="${p##*/}"; printf '%s/.bionic/docs/record/%s/run.log\n' "$SR_REPO" "${p%.plan.md}"; }   # [<plan>] -> that run's log
sr_ask_ev() { local f; f="$(sr_log "${2:-$SR_PLAN}")" && mkdir -p "${f%/*}" && printf 'run/v1|ev=ask|%s\n' "$1" >> "$f"; }  # <ask fields, at= last> [<plan>] -> one ask event in that run's log, as lib/owed.sh writes it
sr_unask() { sed -i.was "/^run\/v1|ev=ask|key=$1|/d" "$(sr_log)"; }   # <key> -> this world's log holds no event of that ask
sr_owed_sid() { printf 'run/v1|ev=ask|%s\n' "$1" >> "$SR_REPO/.bionic/tmp/owed-$2.state"; }  # <ask fields, at= last> <session> -> one ask event in the store of a session acting for no run
# sr_prev <minutes> [<scale>] -> a delivered plan beside this one (T1 of 60 min declared,
# declaring `scale: <scale>` when given) approved at 10:00Z the day before, whose T1 lands <minutes>
# later: the previous wave's measured ratio is <minutes> / 60. Its queue time is 1 minute, so a pace read
# from the queue would be 1/60.
sr_prev() {
  local p="$SR_REPO/.bionic/docs/plans/epic-01-fx/wave-40-prev.plan.md" d="$SR_REPO/.bionic/docs/record/wave-40-prev"
  local land=$((SR_E0 - 86400 + $1 * 60))
  mkdir -p "$d"
  {
    printf -- '---\nwave: wave-40-prev\ncanonical_sdlc_version: 15\nrelease: 9.8.0\n%s---\n# prev\n' "${2:+scale: $2$'\n'}"
    printf '\n## Tasks\n\n| id | step | kind | task | deps | size | serves | Files | artifact |\n'
    printf '|---|---|---|---|---|---|---|---|---|\n'
    printf '| T1 | 4 | build | Prev row · complexity: standard | — | 60 | REQ-1 | lib/p1.sh | — |\n'
  } > "$p"
  {
    printf 'run/v1|ev=approval|key=step3|by=fixture|said=approved|at=2026-10-05T10:00:00Z\n'
    printf 'run/v1|ev=ready|row=T1|name=p-T1|commit=%s|branch=wt/01-T1|tree=%s/.worktrees/01-T1|suites=a.test.sh|debt=-|carrier=1:x|at=%s\n' "$SR_C1" "$SR_REPO" "$(sr_iso $((land - 60)))"
    printf 'run/v1|ev=published|row=T1|commit=%s|kind=queue|by=-|why=-|at=%s\n' "$SR_C1" "$(sr_iso "$land")"
    printf 'run/v1|ev=step|n=9|delivered=2026-10-05T20:00Z wave-40-prev 9.8.0 — closed by close-out.sh|at=2026-10-05T20:00:00Z\n'
  } > "$d/run.log"
}
sr_run() {  # <args after the verb…> -> OUT (stdout), ERR (stderr), RC; the world's plan is named last by the caller
  ( cd "$SR_REPO" && exec env CLAUDE_CODE_SESSION_ID="${SR_SID:-$SID}" BIONIC_NOW_EPOCH="${SR_AT:-$SR_NOW}" BIONIC_GATE_DIR="$SR_GATE" \
      "${SR_BASH:-bash}" "$POKER" sitrep "$@" ) > "$TMPROOT/sr.out" 2> "$TMPROOT/sr.err"
  RC=$?
  OUT="$(cat "$TMPROOT/sr.out")"; ERR="$(cat "$TMPROOT/sr.err")"
}
sr_poke() { sr_poke_with "$POKER" "$@"; }
sr_typed() {  # <words>... -> this session's transcript in the world holds each as a prompt the person typed, its load record there
  local t="$CLAUDE_CONFIG_DIR/projects/$(cd "$SR_REPO" && pwd -P | sed 's/[^a-zA-Z0-9]/-/g')/$SID.jsonl" w; mkdir -p "${t%/*}"; [ -f "$SR_REPO/.bionic/tmp/loaded-$SID.state" ] || : > "$SR_REPO/.bionic/tmp/loaded-$SID.state"
  for w; do jq -c --arg t "$w" '.message.content = $t' "$BIONIC_SCRIPTS_DIR/tests/fixtures/transcript-move/typed.jsonl" >> "$t"; done
}
sr_poke_with() {  # <poker> <verb args…> -> the verb run in the world, as sr_run runs it
  local pk="$1"; shift
  ( cd "$SR_REPO" && exec env CLAUDE_CODE_SESSION_ID="$SID" BIONIC_NOW_EPOCH="${SR_AT:-$SR_NOW}" BIONIC_GATE_DIR="$SR_GATE" bash "$pk" "$@" )
}
# sr_bind [<plan>] [<session>] -> the session engaged and bound to the plan by the bind verb itself, the binding
# act the owed reader admits (this world's plan and session by default).
sr_bind() {
  local p="${1:-$SR_PLAN}" s="${2:-$SID}"
  : > "$SR_REPO/.bionic/tmp/engaged-$s.state"
  ( cd "$SR_REPO" && git add -A >/dev/null 2>&1 && git -c user.email=t@t -c user.name=t commit -qm fixture >/dev/null 2>&1 )
  ( cd "$SR_REPO" && exec env CLAUDE_CODE_SESSION_ID="$s" BIONIC_NOW_EPOCH="${SR_AT:-$SR_NOW}" BIONIC_GATE_DIR="$SR_GATE" \
      bash "$POKER" bind "$p" ) >/dev/null 2>&1
}

# ---------- reading the sheet ----------
#
# sr_val <key> -> the value of the sheet's first `<key>: ` line; sr_lines <key> -> every such line, whole.
sr_val() { printf '%s\n' "$OUT" | awk -v k="$1: " 'index($0, k) == 1 { print substr($0, length(k) + 1); exit }'; }
sr_lines() { printf '%s\n' "$OUT" | awk -v k="$1: " 'index($0, k) == 1'; }
sr_join() { tr '\n' '|' | sed 's/|$//'; }
# THE FIELD READER. A list line is `<kind>: f1=<v> f2=<v> …` with its fields in a fixed order, a value running to
# the next field's ` <name>=` or the line's end, so a value may hold spaces. Proved on a known line (F0) first.
SR_FIELDS_AWK='BEGIN { o["task"] = "id step state desc note"; o["ask"] = "key holds title raised blocks waits"
  o["review"] = "question scope result at open-findings record"; o["goal"] = "name status measure for"; o["step"] = "n name state tasks" }
function fv(line, f,   k, b, n, a, i, s, r, e) {
  k = line; sub(/: .*$/, "", k); b = " " substr(line, length(k) + 3)
  n = split(o[k], a, " ")
  for (i = 1; i <= n; i++) if (a[i] == f) {
    s = index(b, " " f "="); if (!s) return ""
    r = substr(b, s + length(f) + 2)
    if (i < n) { e = index(r, " " a[i + 1] "="); if (e) r = substr(r, 1, e - 1) }
    return r }
  return "" }'
sr_f() { printf '%s\n' "$1" | awk -v f="$2" "$SR_FIELDS_AWK"'{ print fv($0, f) }'; }   # <line> <field> -> its value
sr_task() { sr_lines task | /usr/bin/grep -E "^task: id=$1 " | head -1; }                 # <id> -> its task line
sr_ask() { sr_lines ask | /usr/bin/grep -F "ask: key=$1 " | head -1; }                     # <key> -> its ask line
sr_tasks_f() { sr_lines task | while IFS= read -r l; do sr_f "$l" "$1"; done; }             # <field> -> that field of every task line
# sr_keys -> the sheet's keys in order, a run of one key printed once
sr_keys() { printf '%s\n' "$OUT" | tail -n +2 | awk -F': ' '$1 != p { print $1; p = $1 }' | sr_join; }
SR_HEAD="sheet/v1 — facts for the model; the user sees the card, never this sheet"
SR_ORDER="run.release|run.name|run.wave|run.now|run.step|run.project|run.started|run.last-landing|step|task|clock.now|clock.approved|clock.forecast|clock.elapsed|clock.elapsed-share|work.planned|work.added|work.dropped|work.landed|work.left|work.width|work.task-time|pace.time-used|pace.work-landed|close.chain|close.predicted|close.unscaled|close.waits-on-you|tests.suites-run|tests.suites-total|tests.whole-run|reviews|findings.open|waste.dropped|waste.runs-discarded|waste.ready-unstarted|waste.waiting-on-you|run.so-far|goal|ask|review"
# sr_m <key> -> the measurement alone, the value before its ` — `; sr_d <key> -> what follows it
sr_m() { sr_val "$1" | awk '{ i = index($0, " — "); print (i ? substr($0, 1, i - 1) : $0) }'; }
sr_d() { sr_val "$1" | awk '{ i = index($0, " — "); print (i ? substr($0, i + 5) : "") }'; }
# sr_correct -> the correctness measurements joined; sr_waste -> dropped, discarded and ready-unstarted joined
sr_correct() { for k in tests.suites-run tests.whole-run reviews findings.open; do sr_m "$k"; done | sr_join; }
sr_waste() { for k in waste.dropped waste.runs-discarded waste.ready-unstarted; do sr_m "$k"; done | sr_join; }

# ---------- the world that holds every fact kind ----------
#
# sr_sheet_world -> the world moved so it holds one of each fact: T7 red at head (failed), T13 a review row in
# flight by its dispatch, T16 dropped, one discarded suite run, a 72-minute idle turn, a review of the whole failing
# with one open S2 finding and a review of a piece passing, three goals (one met, one not met, one not measured),
# five asks of five kinds open on the register beside one closed, and a decision put and not ruled.
SR_D_WAIT="Answered now or in an hour, nothing moves: no task waits on it."
sr_ledger_put() {  # <D<n>> <title> <wait line> -> the run's log holds one put of it at 1:30 PM PDT, nothing ruled
  sr_ev "ev=decision|entry=Δ0|d=$1|verb=put|by=orchestrator|title=$2|wait=$3|at=2026-10-06T20:30:00Z"
}
sr_close_ask() {  # <key> [<plan>] -> the ask closed by lib/owed.sh's own closer on that run's register
  ( cd "$SR_REPO" && OWED_ROOT="$SR_REPO" OWED_SID="$SID" OWED_PLAN="${2:-$SR_PLAN}" bash -c '. "$1" && owed_close "$2" fixture' _ "$SR_OWED_LIB" "$1" )
}
sr_reviews() {  # -> two reviews landed on the plan: evidence on the whole failing, adversarial on a piece passing
  sr_ev "ev=proof|kind=review|head=$SR_H|evidence=record/wave-02-fx/auditor-evidence.md|question=evidence|reader=w-T20|result=fail|scope=whole|at=2026-10-06T20:00:00Z"
  sr_ev "ev=proof|kind=review|head=$SR_H|evidence=record/wave-02-fx/critic-adversarial.md|question=adversarial|reader=w-T21|result=pass|scope=piece|at=2026-10-06T20:05:00Z"
}
sr_sheet_world() {
  SR_GOALS="fast landings · one-file median under 15m (landing-report --rows)
tests · whole run under 45 min at the approved head (the Step-5 run log)
handoff · a fresh session continues a no-run handoff (record/reader-test-handoff.md)" sr_world "$1" "6 6 12 12"
  sr_set T13 kind review; sr_state T13 active
  sr_ev "ev=drop|row=T16|why=fixture|at=2026-10-06T13:00:00Z"
  sr_ev "ev=verdict|row=T7|commit=$SR_C1|suite=a.test.sh|result=red|log=/rec/T7.log|at=2026-10-06T14:00:00Z"
  sr_ev "ev=verdict|row=T8|commit=$SR_C1|suite=a.test.sh|result=discarded|log=/rec/T8.log|at=2026-10-06T14:10:00Z"
  sr_stop t2 16:00:00 3 1 T9 "" 1 T9 1
  sr_stop t3 17:12:00 4 0 "" T9 0 "" 0
  printf 'reviewed: %s..%s\nfindings: 1\nfinding: 1 S2 on lib/t1.sh:3 the thing breaks\nshown: 1 bash tests/x.test.sh\n' "$SR_C1" "$SR_H" > "$SR_DIR/auditor-evidence.md"
  printf 'reviewed: %s..%s\nfindings: 0\n' "$SR_C1" "$SR_H" > "$SR_DIR/critic-adversarial.md"
  sr_reviews
  printf 'Gating: 9 passed, 0 failed\nWall: 3000s · work 9000s · width 4\n' > "$SR_DIR/regression-run-$SR_H.log"
  sr_ev "ev=proof|kind=regression|head=$SR_H|evidence=record/wave-02-fx/regression-run-$SR_H.log|at=2026-10-06T20:00:00Z"
  sr_ask_ev "key=approve:release|sent=-|title=approval: release|at=2026-10-06T20:00:00Z"
  sr_ask_ev "key=waive:adversarial|sent=-|title=waiver: adversarial|at=2026-10-06T20:01:00Z"
  sr_ask_ev "key=row:AC-1.2|sent=-|title=ruling: row AC-1.2|at=2026-10-06T20:02:00Z"
  sr_ask_ev "key=ruling:r1|sent=-|title=ruling unread: F1|at=2026-10-06T20:03:00Z"
  sr_ask_ev "key=gate:abc|sent=-|title=gate act: merge|at=2026-10-06T20:04:00Z"
  sr_ask_ev "key=approve:merge|sent=-|title=approval: merge|at=2026-10-06T20:05:00Z"
  sr_close_ask approve:merge
  sr_ledger_put D21 "the gate the judge holds" "$SR_D_WAIT"
}

# ============================================================
section "§SHEET: the sheet over a run holding every fact kind — each fact appears as its key, in the sheet's order"
# ============================================================
# fails-when: a fact of the fixture is missing from the sheet. The field reader every later section reads through is
# proved on known lines first (F0), so a reader that returns nothing cannot pass for an absence.
expect_eq "F0 a task line's five fields, the description and the note holding spaces" \
  "T7|4|failed|Row 7 body|red at head" \
  "$(for f in id step state desc note; do sr_f 'task: id=T7 step=4 state=failed desc=Row 7 body note=red at head' "$f"; done | sr_join)"
expect_eq "F0b an ask line's six fields, the last holding spaces" "approve:release|T12 and T17|approval: release|1:00 PM|no|event review adversarial re-run" \
  "$(for f in key holds title raised blocks waits; do sr_f 'ask: key=approve:release holds=T12 and T17 title=approval: release raised=1:00 PM blocks=no waits=event review adversarial re-run' "$f"; done | sr_join)"
sr_sheet_world sheet
sr_run "$SR_PLAN"
SR_SHEET="$OUT"
expect_eq "SH0 sitrep <plan> exits 0 with nothing on stderr" "0|" "$RC|$ERR"
expect_eq "SH1 the first line says the sheet is the model's input, never the user's" "$SR_HEAD" "$(printf '%s\n' "$OUT" | head -1)"
expect_eq "SH2 every other line is one fact, <key>: <value>, and there are dozens of them" "0|yes" \
  "$(printf '%s\n' "$OUT" | tail -n +2 | /usr/bin/grep -cvE '^[a-z][a-z.-]*: [^ ]')|$([ "$(printf '%s\n' "$OUT" | tail -n +2 | /usr/bin/grep -cE '^[a-z][a-z.-]*: [^ ]')" -ge 40 ] && echo yes)"
expect_eq "SH3 the keys, in the sheet's order, each kind's lines together" "$SR_ORDER" "$(sr_keys)"
expect_eq "SH4 the run: release, name, wave, now, step, project, its start and its last landing" \
  "9.9.0|wave-02-fx|2|Tuesday 3:00 PM|4|sheet|3:00 AM|T4 at 5:12 AM" \
  "$(for k in run.release run.name run.wave run.now run.step run.project run.started run.last-landing; do sr_val "$k"; done | sr_join)"
expect_eq "SH5 ten steps, each with its number, name, state and task count: 0 to 3 done, 4 running with its 16 tasks, 5 to 9 pending" \
  "0 Configure done 0|3 Plan done 0|4 Implement running 16|5 Verify pending 0|9 Close-out pending 0|10" \
  "$(sr_lines step | while IFS= read -r l; do printf '%s %s %s %s\n' "$(sr_f "$l" n)" "$(sr_f "$l" name)" "$(sr_f "$l" state)" "$(sr_f "$l" tasks)"; done | awk 'NR == 1 || NR == 4 || NR == 5 || NR == 6 || NR == 10' | sr_join)|$(sr_lines step | /usr/bin/grep -c .)"
expect_eq "SH6 one task line per task not dropped: sixteen, T16 among none of them while T15 is there" "16|0|1" \
  "$(sr_lines task | /usr/bin/grep -c .)|$(sr_lines task | /usr/bin/grep -c '^task: id=T16 ')|$(sr_lines task | /usr/bin/grep -c '^task: id=T15 ')"
expect_eq "SH7 each task's step, state and few words: done with its landing time, failed red, held, a review in flight, waiting" \
  "4|done|landed 3:06 AM|failed|red|pending|-|held|waits on your approval of the release|running|pending|waits on 4/8|pending|-" \
  "$(sr_f "$(sr_task T1)" step)|$(sr_f "$(sr_task T1)" state)|$(sr_f "$(sr_task T1)" note)|$(sr_f "$(sr_task T7)" state)|$(sr_f "$(sr_task T7)" note)|$(sr_f "$(sr_task T11)" state)|$(sr_f "$(sr_task T11)" note)|$(sr_f "$(sr_task T12)" state)|$(sr_f "$(sr_task T12)" note)|$(sr_f "$(sr_task T13)" state)|$(sr_f "$(sr_task T9)" state)|$(sr_f "$(sr_task T9)" note)|$(sr_f "$(sr_task T10)" state)|$(sr_f "$(sr_task T10)" note)"
expect_eq "SH8 each task's title, the plan card's: the cell up to its first '. ', else up to its first ' · '" \
  "Row one the thing (D1; AC-1.1)|Haiku 5.5 at high (REQ-8; AC-8.1)|Third row|The long one (D8)" \
  "$(for t in T1 T2 T3 T8; do sr_f "$(sr_task "$t")" desc; done | sr_join)"
expect_eq "SH9 the measurements in numbers: landed, pace, correctness and waste; no metric line" \
  "4 tasks, 120 of 570 min, 21%|25%|21%|1: 0 green, 1 red|red at aaaaaaaa, not in this head's history|1 passed, 1 failed, 1 running|1|1 task, 30 min|1 of 6|72 min|0" \
  "$(for k in work.landed pace.time-used pace.work-landed tests.suites-run tests.whole-run reviews findings.open waste.dropped waste.runs-discarded waste.ready-unstarted; do sr_m "$k"; done | sr_join)|$(printf '%s\n' "$OUT" | /usr/bin/grep -c '^metric\.')"
expect_eq "SH10 each goal's name and status, in the plan's order" "fast landings=met|tests=not met|handoff=not measured" \
  "$(sr_lines goal | while IFS= read -r l; do printf '%s=%s\n' "$(sr_f "$l" name)" "$(sr_f "$l" status)"; done | sr_join)"
expect_eq "SH10b …each with what measures it and what it read" "yes|yes" \
  "$(sr_f "$(sr_lines goal | /usr/bin/grep 'name=tests ')" measure | /usr/bin/grep -q '^whole run under 45 min at the approved head — the whole run took 50 min' && echo yes)|$(sr_f "$(sr_lines goal | /usr/bin/grep 'name=fast landings ')" measure | /usr/bin/grep -q 'median is 9 min' && echo yes)"
expect_eq "SH11 the close: the chain from now at 1× with no launch on record, its basis in words, the forecast end" \
  "5:30 PM|yes|48 h, ends 3:00 AM 2026-10-08" \
  "$(sr_m close.predicted)|$(sr_d close.predicted | /usr/bin/grep -q 'basis: .*build tasks at 1×: 0 landed build tasks have a launch and a landing on record, under 3' && echo yes)|$(sr_m clock.forecast)"
expect_eq "SH12 every ask open on the register is one ask line, the decision put on the ledger among them; the closed one is not" \
  "approve:release|waive:adversarial|row:AC-1.2|ruling:r1|gate:abc|decide:D21|0" \
  "$(sr_lines ask | while IFS= read -r l; do sr_f "$l" key; done | sr_join)|$(sr_lines ask | /usr/bin/grep -c 'key=approve:merge ')"
expect_eq "SH13 an ask's line: what it holds, its title and when it was raised, on the local clock" \
  "4/12|approval: release|1:00 PM|nothing|D21 · the gate the judge holds|1:30 PM" \
  "$(for k in approve:release decide:D21; do for f in holds title raised; do sr_f "$(sr_ask "$k")" "$f"; done; done | sr_join)"
# WHETHER AN ASK BLOCKS IS A FACT: blocks=yes only when the ask holds a task, the release or the merge AND waits on the
# user, blocks=no otherwise; waits= says what the ask waits on, `user` or `event <what>`, and stands last. The card places
# the ask from them and the model never decides either.
# fails-when: an ask that holds nothing reads blocks=yes (it would sit under Blocked on you), a held one that waits on the
# user reads blocks=no, or an ask line carries no waits= field.
expect_eq "SH13b an ask holding a task reads blocks=yes, one holding nothing blocks=no, both waiting on the user" "yes|user|no|user" \
  "$(sr_f "$(sr_ask approve:release)" blocks)|$(sr_f "$(sr_ask approve:release)" waits)|$(sr_f "$(sr_ask decide:D21)" blocks)|$(sr_f "$(sr_ask decide:D21)" waits)"
expect_eq "SH13c every ask line's blocks= is yes exactly when its holds= is not nothing and its waits= is user, and both values occur on this sheet (SH13b read the two)" "0|yes|yes" \
  "$(sr_lines ask | while IFS= read -r l; do h="$(sr_f "$l" holds)"; b="$(sr_f "$l" blocks)"; w="$(sr_f "$l" waits)"; if [ "$h" != nothing ] && [ "$w" = user ]; then [ "$b" = yes ] || echo bad; else [ "$b" = no ] || echo bad; fi; done | /usr/bin/grep -c bad)|$(sr_lines ask | /usr/bin/grep -q ' blocks=yes waits=' && echo yes)|$(sr_lines ask | /usr/bin/grep -q ' blocks=no waits=' && echo yes)"
expect_eq "SH13d every ask line ends in its waits= field, user or event <what> (the field reader returned a value for each, SH13b read two)" "0|6" \
  "$(sr_lines ask | while IFS= read -r l; do w="$(sr_f "$l" waits)"; [ "$w" = user ] || [ "${w#event ?}" != "$w" ] || echo bad; done | /usr/bin/grep -c bad)|$(sr_lines ask | /usr/bin/grep -c ' waits=')"
expect_eq "SH14 every review: its question, scope, result, time, open findings and record; the review in flight with them" \
  "evidence whole fail 1:00 PM 1 record/wave-02-fx/auditor-evidence.md|adversarial piece pass 1:05 PM 0 record/wave-02-fx/critic-adversarial.md|T13 whole running - 0 -" \
  "$(sr_lines review | while IFS= read -r l; do printf '%s %s %s %s %s %s\n' "$(sr_f "$l" question)" "$(sr_f "$l" scope)" "$(sr_f "$l" result)" "$(sr_f "$l" at)" "$(sr_f "$l" open-findings)" "$(sr_f "$l" record)"; done | sr_join)"

# ============================================================
section "§CLOCK-WORK: the clock and the work, each line a measurement naming what it measures, its unit and its source"
# ============================================================
# The world: approved at 3:00 AM, now 3:00 PM, a 48 h forecast. T17's own line says task-add added it before the
# approval, so it was planned; T18's says after, so it was added; T16 is dropped. The rosters launch T1 to T4 30, 30,
# 60 and 60 min before their landings (10:06Z, 10:36Z, 11:12Z, 12:12Z), T5 and T6 at 12:00Z and T7 and T8 at 20:00Z,
# all four still running at now.
# fails-when: a line is missing, holds a number the record does not give, or carries no measure, unit and source.
sr_launch() {  # <row> <hh:mm:ss on 2026-10-06, UTC> -> a roster's launch of that row of this world's plan
  printf 'roster-state/v1|status=intended|session=%s|name=w-%s|agent_id=|launched_at=2026-10-06T%sZ|plan=%s|row=%s\n' \
    "$SID" "$1" "$2" "$SR_PLAN" "$1" >> "$SR_REPO/.bionic/tmp/roster-$SID.state"
}
sr_mw_world() {  # <label> -> the world above
  SR_EXTRA=1 sr_world "$1" "6 6 12 12"
  sr_ev "ev=drop|row=T16|why=fixture|at=2026-10-06T13:00:00Z"
  sr_ev "ev=born|row=T17|at=2026-10-06T09:00:00Z"; sr_ev "ev=born|row=T18|at=2026-10-06T12:00:00Z"
  sr_launch T1 09:36:00; sr_launch T2 10:06:00; sr_launch T3 10:12:00; sr_launch T4 11:12:00
  sr_launch T5 12:00:00; sr_launch T6 12:00:00; sr_launch T7 20:00:00; sr_launch T8 20:00:00
}
SR_MEASURED="clock.now clock.approved clock.forecast clock.elapsed clock.elapsed-share work.planned work.added work.dropped work.landed work.left work.width work.task-time pace.time-used pace.work-landed close.chain close.predicted close.unscaled close.waits-on-you tests.suites-run tests.suites-total tests.whole-run reviews findings.open waste.dropped waste.runs-discarded waste.ready-unstarted waste.waiting-on-you"
sr_mw_world clock-work
sr_run "$SR_PLAN"
expect_eq "MW0 precondition: the world prints (rc 0) and the extractor reads a measurement and its words" "0|3:00 PM|yes" \
  "$RC|$(sr_m clock.now)|$([ -n "$(sr_d clock.now)" ] && echo yes)"
expect_eq "MW1 the clock: now, the approval, the forecast and its end, the time since the approval and its share of the forecast" \
  "3:00 PM|3:00 AM|48 h, ends 3:00 AM 2026-10-08|12 h|25%" \
  "$(for k in clock.now clock.approved clock.forecast clock.elapsed clock.elapsed-share; do sr_m "$k"; done | sr_join)"
expect_eq "MW2 the work: planned at the approval (T17 added before it), added after it (T18), dropped, landed, left" \
  "17 tasks, 600 min|1 task, 30 min|1 task, 30 min|4 tasks, 120 of 600 min, 20%|13 tasks, 480 min" \
  "$(for k in work.planned work.added work.dropped work.landed work.left; do sr_m "$k"; done | sr_join)"
expect_eq "MW3 the width from the launches to the landings (or now): two at once for most of the minutes a task ran, four at the peak" \
  "median 2, peak 4" "$(sr_m work.width)"
expect_eq "MW4 the landed tasks' own time, launch to landing, against their sizes" "4 tasks, 180 min against 120 sized min" "$(sr_m work.task-time)"
sr_unlabelled() {  # -> each measured key whose line does not name its measure, unit and source (or basis)
  local k d
  for k in $SR_MEASURED; do
    d="$(sr_d "$k")"
    case "$d" in ?*' · unit: '*' · source: '?*|?*' · unit: '*' · basis: '?*) ;; *) printf '%s ' "$k" ;; esac
  done
}
expect_eq "MW5 every measured line names what it measures, its unit and its source (or basis)" "" "$(sr_unlabelled)"
expect_eq "MW6 the old metric lines are gone, while the measurements stand in their place" "0|27" \
  "$(printf '%s\n' "$OUT" | /usr/bin/grep -c '^metric\.')|$(for k in $SR_MEASURED; do sr_lines "$k"; done | /usr/bin/grep -c .)"
expect_eq "MW6b …no line holds the old pace ratio or the plan's allowance" "0|0" \
  "$(printf '%s\n' "$OUT" | /usr/bin/grep -c '×,')|$(printf '%s\n' "$OUT" | /usr/bin/grep -c 'the plan allowed')"
# A plan with no approval measures no time since it, and a plan with no typed forecast ends at its own sized minutes.
SR_APPROVED=none sr_world clock-unapproved "6 6 12 12"
sr_run "$SR_PLAN"
expect_eq "MW7 no approval: the clock says so, and every task is planned" "3:00 PM|-|-|-|17 tasks, 600 min|0 tasks, 0 min" \
  "$(for k in clock.now clock.approved clock.elapsed clock.elapsed-share work.planned work.added; do sr_m "$k"; done | sr_join)"

# ============================================================
section "§PACE-CLOSE: pace is work landed against forecast time used; the close is the chain from now, scaled by the landed tasks' own time over their size once three have landed"
# ============================================================
# fails-when: pace compares unlike units, the close is scaled by a span from the approval, or by fewer than three tasks.
sr_mw_world pace-close
sr_run "$SR_PLAN"
expect_eq "PC1 pace: the forecast time used and the work landed, both shares" "25%|20%" "$(sr_m pace.time-used)|$(sr_m pace.work-landed)"
expect_eq "PC2 the chain left, by label, and its sized minutes" "4/8 → 4/9, 150 min" "$(sr_m close.chain)"
expect_eq "PC3 the close: T8, 120 min in, has its 15 min cadence left, then T9 at 60 × 180 over 120 = 90; the same unscaled, 15 then 60" "4:45 PM|4:15 PM" \
  "$(sr_m close.predicted)|$(sr_m close.unscaled)"
expect_eq "PC3b …its basis in words names the landed tasks' own time and their size" "yes" \
  "$(sr_d close.predicted | /usr/bin/grep -q 'basis: .*4 landed build tasks.* 180 min .* 120 sized min' && echo yes)"
sr_run --line "$SR_PLAN"
expect_eq "PC4 the Patrol's status carries the predicted close" "close 4:45 PM" "${OUT##* · }"
# T4's launch gone: three tasks measure the scale, 120 min against 90.
awk '!/\|row=T4$/' "$SR_REPO/.bionic/tmp/roster-$SID.state" > "$SR_REPO/.bionic/tmp/r.t" && mv "$SR_REPO/.bionic/tmp/r.t" "$SR_REPO/.bionic/tmp/roster-$SID.state"
sr_run "$SR_PLAN"
expect_eq "PC5 three landed tasks with a launch scale the chain: T9 at 60 × 120 over 90 = 80 after T8's 15; the one with none is said" \
  "3 tasks, 120 min against 90 sized min; 1 landed task with no launch or landing on record|4:35 PM" "$(sr_m work.task-time)|$(sr_m close.predicted)"
awk '!/\|row=T3$/' "$SR_REPO/.bionic/tmp/roster-$SID.state" > "$SR_REPO/.bionic/tmp/r.t" && mv "$SR_REPO/.bionic/tmp/r.t" "$SR_REPO/.bionic/tmp/roster-$SID.state"
sr_run "$SR_PLAN"
expect_eq "PC6 two: the chain at 1×, the predicted close the unscaled one, and the basis says under 3" "4:15 PM|4:15 PM|yes" \
  "$(sr_m close.predicted)|$(sr_m close.unscaled)|$(sr_d close.predicted | /usr/bin/grep -q 'basis: .*at 1×.*under 3' && echo yes)"
# What the prediction assumes of you: an ask holding a task off the chain assumes nothing; one holding a chain task does.
sr_mw_world pace-waits
sr_ask_ev "key=approve:release|sent=-|title=approval: release|at=2026-10-06T20:00:00Z"
sr_run "$SR_PLAN"
expect_eq "PC7 an ask holding 4/12, off the chain: the prediction waits on no answer" "no" "$(sr_m close.waits-on-you)"
sr_set T9 deps "T8, approval:design"
sr_ask_ev "key=approve:design|sent=-|title=approval: design|at=2026-10-06T20:00:00Z"
sr_run "$SR_PLAN"
expect_eq "PC8 an ask holding 4/9, on the chain: the prediction assumes it is answered now, and names it" "yes: approve:design" \
  "$(sr_m close.waits-on-you)"

# ============================================================
# The close counts what is running and scales by kind. The world: T1 to T4 landed, each 100 sized min and launched 6 min
# before its landing, so the landed build tasks' own time is 24 min over 400 sized min, a ratio of 0.06 that any build
# row left pending is scaled by; every other row is landed, and a test opens the rows it reads. Every row past T4 writes
# only its record, so no row's default read of the head joins it to another. Now is 3:00 PM.
sr_close_world() {  # <label> -> the world above
  local i
  sr_world "$1" "5 5 5 5"
  for i in 1 2 3 4; do sr_set "T$i" size 100; done
  sr_launch T1 09:59:00; sr_launch T2 10:29:00; sr_launch T3 10:59:00; sr_launch T4 11:59:00
  for i in 5 6 7 8 9 10 11 12 13 14 15 16 17; do sr_set "T$i" status landed; sr_set "T$i" files ".bionic/docs/record/wave-02-fx/T$i.md"; done
}

# ============================================================
section "§CLOSE-RUNNING: the predicted close counts a running row off the chain at its size less its elapsed, floored at its cadence"
# ============================================================
# fails-when: a sheet with a running 90-minute row five minutes in, off the chain, predicts a close before that row's
# remaining time, a running row past its size counts nothing, or the roster's cadence is not the floor.
sr_close_world close-running
sr_open T5 verify 90 active
sr_open T6 build 30 pending; sr_open T7 build 30 pending T6
sr_launch T5 21:55:00
sr_run "$SR_PLAN"
expect_eq "CR0 precondition: the build ratio is in force, 24 min over 400 sized min" \
  "4 tasks, 24 min against 400 sized min" "$(sr_m work.task-time | sed 's/;.*$//')"
expect_eq "CR1 a verify row of 90 min five minutes in, off the chain: the close is 85 min out, the row's remaining, not the chain's" \
  "4:25 PM" "$(sr_m close.predicted)"
expect_eq "CR1b …the basis says a running task counts at its size less its elapsed" "yes" \
  "$(sr_d close.predicted | /usr/bin/grep -q 'basis: .*a running task at its size less its elapsed' && echo yes)"
sr_set T5 status landed
sr_run "$SR_PLAN"
expect_eq "CR2 control: the same row landed, the close follows the chain: T6 then T7 at 2 min each" "3:04 PM" "$(sr_m close.predicted)"
sr_close_world close-running-late
sr_open T5 verify 90 active
sr_open T6 build 30 pending; sr_open T7 build 30 pending T6
sr_launch T5 20:00:00
sr_run "$SR_PLAN"
expect_eq "CR3 a running row past its size has a cadence left, 15 min when its roster row names none" "3:15 PM" "$(sr_m close.predicted)"
sr_close_world close-running-cad
sr_open T5 verify 90 active
sr_open T6 build 30 pending; sr_open T7 build 30 pending T6
printf 'roster-state/v1|status=intended|session=%s|name=w-T5|agent_id=|launched_at=2026-10-06T20:00:00Z|plan=%s|row=T5|cadence=30 min\n' \
  "$SID" "$SR_PLAN" >> "$SR_REPO/.bionic/tmp/roster-$SID.state"
sr_run "$SR_PLAN"
expect_eq "CR4 …and the cadence its roster row holds when it names one: 30 min" "3:30 PM" "$(sr_m close.predicted)"

# ============================================================
section "§CLOSE-KIND: a build row is scaled by the landed build rows' ratio; every other kind sits at face value; a row held on you is unscaled and named"
# ============================================================
# fails-when: a 45-minute review row is scaled by a build ratio, a held row is scaled or not named, or a landed review's
# own time enters the build ratio.
sr_close_world close-kind
sr_open T5 review 45 pending
sr_run "$SR_PLAN"
expect_eq "KD0 precondition: the ratio is in force, 24 min over 400 sized min" "4 tasks, 24 min against 400 sized min" "$(sr_m work.task-time | sed 's/;.*$//')"
expect_eq "KD1 a 45-minute review row is at face value under a build ratio of 0.06: 45 min out" "3:45 PM" "$(sr_m close.predicted)"
sr_set T5 kind build
sr_run "$SR_PLAN"
expect_eq "KD1b control: the same 45 minutes as a build row are scaled, 3 min out" "3:03 PM" "$(sr_m close.predicted)"
KD2=""
for sr_k in build verify doc integrate close; do
  sr_open T5 "$sr_k" 20 pending
  sr_run "$SR_PLAN"
  KD2="$KD2$sr_k $(sr_m close.predicted)|"
done
expect_eq "KD2 by kind: a 20-minute build row is scaled to 1 min; verify, doc, integrate and close rows sit at their 20" \
  "build 3:01 PM|verify 3:20 PM|doc 3:20 PM|integrate 3:20 PM|close 3:20 PM|" "$KD2"
sr_open T5 build 90 pending approval:design
sr_ask_ev "key=approve:design|sent=-|title=approval: design|at=2026-10-06T20:00:00Z"
sr_run "$SR_PLAN"
expect_eq "KD3 a build row held on an ask open on you is unscaled, 90 min out, and the ask is named" "4:30 PM|yes: approve:design" \
  "$(sr_m close.predicted)|$(sr_m close.waits-on-you)"
sr_close_ask approve:design
sr_run "$SR_PLAN"
expect_eq "KD3b control: the ask answered, the same row is scaled to 5 min and nothing is waited on" "3:05 PM|no" \
  "$(sr_m close.predicted)|$(sr_m close.waits-on-you)"
sr_close_world close-kind-own
sr_set T4 kind review
awk '!/\|row=T4$/' "$SR_REPO/.bionic/tmp/roster-$SID.state" > "$SR_REPO/.bionic/tmp/r.t" && mv "$SR_REPO/.bionic/tmp/r.t" "$SR_REPO/.bionic/tmp/roster-$SID.state"
sr_launch T4 10:25:00
sr_open T5 build 45 pending
sr_run "$SR_PLAN"
expect_eq "KD4 a landed review's own time, 100 min, is no build row's: three landed build rows set the ratio, 18 over 300" \
  "3:03 PM|yes" "$(sr_m close.predicted)|$(sr_d close.predicted | /usr/bin/grep -q 'scaled by the 3 landed build tasks. own time over their size, 18 min over 300 sized min' && echo yes)"

# ============================================================
section "§CLOSE-UPSTREAM: a verify row counts as upstream of the integrate row whether or not a read names it"
# ============================================================
# fails-when: an open verify row is absent from the chain the integrate row heads, a landed one is on it, or the added
# edge joins two rows that already wait on each other the other way round.
sr_close_world close-upstream
# NO REGRESSION IS OWED, so the integrate row's kind names no verify row and the edge under test is the one the sheet adds.
awk '{ print } /^canonical_sdlc_version: 15$/ { print "regression: no" }' "$SR_PLAN" > "$SR_PLAN.t" && mv "$SR_PLAN.t" "$SR_PLAN"
sr_open T5 verify 60 pending
sr_open T9 integrate 30 pending
sr_open T6 build 20 pending
sr_run "$SR_PLAN"
expect_eq "UP1 no read joins the verify row to the integrate row: the chain still runs 4/5 then 4/9, and the close is 90 min out" \
  "4/5 → 4/9, 90 min|4:30 PM" "$(sr_m close.chain)|$(sr_m close.predicted)"
sr_set T5 status landed
sr_run "$SR_PLAN"
expect_eq "UP2 control: the verify row landed, it is off the chain, which is the integrate row alone" "4/9, 30 min" "$(sr_m close.chain)"
sr_open T5 verify 60 active
sr_launch T5 21:55:00
sr_run "$SR_PLAN"
expect_eq "UP3 a running verify row is on the chain the integrate row heads" "4/5 → 4/9, 90 min" "$(sr_m close.chain)"
sr_open T5 verify 60 pending T9
sr_run "$SR_PLAN"
expect_eq "UP4 a verify row that reads what the integrate row writes keeps that order: no cycle, the chain 4/9 then 4/5" \
  "0|4/9 → 4/5, 90 min" "$RC|$(sr_m close.chain)"

# ============================================================
section "§WASTE: correctness and waste as measurements; the minutes a task waited on you, overlaps counted once"
# ============================================================
# fails-when: a count is not the record's, a closed ask's minutes are lost, an overlap counts twice, or a decision with
# no opened time is not read from its rounds.
sr_mw_world waste
mkdir -p "$SR_REPO/tests"; : > "$SR_REPO/tests/a.test.sh"; : > "$SR_REPO/tests/b.test.sh"
sr_run "$SR_PLAN"
expect_eq "WS1 correctness: the suites run by their last verdict, the suites the project has, the whole run, the reviews, the open findings" \
  "1: 1 green, 0 red|2|not run yet|0 passed, 0 failed, 0 running|0" \
  "$(for k in tests.suites-run tests.suites-total tests.whole-run reviews findings.open; do sr_m "$k"; done | sr_join)"
expect_eq "WS2 waste: dropped, suite runs discarded, ready tasks unstarted, minutes waiting on you" "1 task, 30 min|0 of 4|0 min|0 min" \
  "$(for k in waste.dropped waste.runs-discarded waste.ready-unstarted waste.waiting-on-you; do sr_m "$k"; done | sr_join)"
# T9 reads approval:design, asked 13:00Z and closed 14:00Z: 60 minutes. approve:other held nothing: no minute.
sr_set T9 deps "T8, approval:design"
sr_ask_ev "key=approve:design|sent=-|title=approval: design|at=2026-10-06T13:00:00Z"; sr_ask_ev "key=approve:design|reply=approve|at=2026-10-06T14:00:00Z"
sr_ask_ev "key=approve:other|sent=-|title=approval: other|at=2026-10-06T10:00:00Z"; sr_ask_ev "key=approve:other|reply=approve|at=2026-10-06T11:00:00Z"
sr_run "$SR_PLAN"
expect_eq "WS3 a closed ask that held a task counts from opened to closed; one that held nothing counts no minute" \
  "60 min: approve:design" "$(sr_m waste.waiting-on-you)"
# approve:release, holding T12, open since 13:30Z: 13:00Z to now, 540 min, the half hour both were open counted once.
sr_ask_ev "key=approve:release|sent=-|title=approval: release|at=2026-10-06T13:30:00Z"
sr_run "$SR_PLAN"
expect_eq "WS4 an open ask counts from its raising to now, an overlap once" "540 min: approve:design and approve:release" \
  "$(sr_m waste.waiting-on-you)"
# A decision closed with no opened time: its first put, 1:30 PM PDT, to its close at 2:00 PM.
sr_mw_world waste-ledger
sr_set T10 deps approval:D5
sr_ledger_put D5 "the thing" "$SR_D_WAIT"; sr_ev "ev=decision|entry=Δ1|d=D5|verb=put|by=orchestrator|title=the thing again|wait=$SR_D_WAIT|at=2026-10-06T20:45:00Z"
sr_ev "ev=decision|entry=Δ2|d=D5|verb=ruled|said=1|by=fixture|title=the thing|at=2026-10-06T21:00:00Z"
sr_ask_ev "key=decide:D5|reply=ruled|at=2026-10-06T21:00:00Z"
sr_run "$SR_PLAN"
expect_eq "WS5 a decision with no opened time: from its first put to its close" "30 min: decide:D5" "$(sr_m waste.waiting-on-you)"
sr_unask decide:D5; sr_run "$SR_PLAN"
expect_eq "WS6 …and with no ask of it in the log, to the ruling's own time" "30 min: decide:D5" "$(sr_m waste.waiting-on-you)"

# ============================================================
section "§ONE-PARSER: one rule for what rules a decision, settled among its verbs, and no reader of a ledger heading"
# ============================================================
# fails-when: a decision whose only ruling of D<n> is a `settled` round is open to one reader and ruled to the other,
# or the sheet parses a ledger heading itself.
sr_world one-parser "6 6 12 12"
sr_set T10 deps approval:D5
sr_bind
sr_ledger_put D5 "the thing" "$SR_D_WAIT"; sr_ev "ev=decision|entry=Δ1|d=D5|verb=settled|said=1|by=fixture|title=the thing|at=2026-10-06T21:00:00Z"
sr_ask_ev "key=decide:D5|reply=ruled|at=2026-10-06T21:00:00Z"
sr_run "$SR_PLAN"
expect_eq "OP1 a decision whose only ruling is a settled round is ruled to the register's reader: the decisions verb prints it" \
  'D5 · settled "1" · fixture 2026-10-06 · the thing' "$(sr_poke decisions 2>&1)"
expect_eq "OP1b …and to the clock reader: from its put to the ruling's own clock, 30 minutes" "30 min: decide:D5" "$(sr_m waste.waiting-on-you)"
expect_eq "OP1c …and open to neither: the sheet owes no ask for it" "0" "$(sr_lines ask | /usr/bin/grep -c 'key=decide:D5 ')"
# The static row: the sheet recognises no ledger heading (`## Δn — `); a round is an event the reader folds. The control
# plants the same line
# twice, and once beside a comment that names the shape, through the same counter.
op_count() { /usr/bin/grep -vE '^[[:space:]]*#' "$1" | /usr/bin/grep -cE 'Δ\[0-9\]\+ — '; }
OP_P="$TMPROOT/op-plant.sh"
printf '%s\n' "# a comment naming Δ[0-9]+ — is no parser" "  index(\$0, 1) { sub(/^## Δ[0-9]+ — /, \"\") }" > "$OP_P"
expect_eq "OP3a (control) the counter finds one parser in a file with one, and passes a comment by" "1" "$(op_count "$OP_P")"
printf '%s\n' "  \$0 ~ /^## Δ[0-9]+ — D[0-9]+ / { next }" >> "$OP_P"
expect_eq "OP3b (control) …and two in a file with a second" "2" "$(op_count "$OP_P")"
expect_eq "OP3 the sheet's code parses no ledger heading" "0" "$(op_count "${BIONIC_HOOKS_DIR}/poker/sitrep.sh")"

# ============================================================
section "§SPAN: an ask closed with no opened= takes its span from the run's record, or the count says it is partial"
# ============================================================
# fails-when: a closed waiver with no opened= adds no minute though the plan holds its span, the opened= it has is
# passed over for the record, a carry, which waits on the release card and never on you, counts its span, or an ask
# the record cannot time leaves the count unmarked.
sr_mw_world span
awk '/^\| T17 / { print; print "| T18 | 8 | integrate | Merge row · complexity: standard | — | 10 | REQ-1 | lib/t18.sh | — |"; next } { print }' \
  "$SR_PLAN" > "$SR_PLAN.t" && mv "$SR_PLAN.t" "$SR_PLAN"
SP_REC="record/wave-02-fx/critic-structure.md"
sr_ev "ev=proof|kind=review|head=$SR_H|evidence=$SP_REC|question=structure|reader=w-T2|result=flag|scope=whole|at=2026-10-06T12:00:00Z"
sr_ev "ev=finding|ref=$SP_REC#2|to=defer|by=fixture|words=a thing|at=2026-10-06T12:00:00Z"
sr_ev "ev=proof|kind=review|head=$SR_H|evidence=record/wave-02-fx/critic-evidence.md|question=evidence|reader=w-T1|result=fail|scope=whole|at=2026-10-06T13:00:00Z"
sr_ev "ev=waiver|question=evidence|head=$SR_H|by=Chris Lehman|said=waive it|at=2026-10-06T14:00:00Z"
SP_CARRY="carry:record:wave-02-fx:critic-structure.md:2"
sr_ask_ev "key=waive:evidence|reply=waive|at=2026-10-06T14:00:00Z"
sr_run "$SR_PLAN"
expect_eq "SP1 a closed waiver with no opened=: from the review's fail line to the waived: line, 60 minutes, nothing partial" \
  "60 min: waive:evidence" "$(sr_m waste.waiting-on-you)"
sr_unask waive:evidence
sr_ask_ev "key=waive:evidence|sent=-|at=2026-10-06T13:30:00Z"; sr_ask_ev "key=waive:evidence|reply=waive|at=2026-10-06T14:00:00Z"
sr_run "$SR_PLAN"
expect_eq "SP2 (control) the same waiver with opened= present uses it: 30 minutes" "30 min: waive:evidence" "$(sr_m waste.waiting-on-you)"
sr_unask waive:evidence
sr_ask_ev "key=$SP_CARRY|reply=ruled|at=2026-10-06T14:00:00Z"
sr_run "$SR_PLAN"
expect_eq "SP3 a closed carry waits on the release card, an event, never on you: it counts no minute and is no ask left untimed (SP1 timed the waiver through the same reader)" \
  "0 min" "$(sr_m waste.waiting-on-you)"
sr_unask "$SP_CARRY"
sr_ask_ev "key=finding:record:wave-02-fx:nowhere.md:1|reply=ruled|at=2026-10-06T14:00:00Z"
sr_run "$SR_PLAN"
expect_eq "SP4 a closed ask the record holds no span for: the count is marked partial and says how many asks it could not time" \
  "0 min partial, 1 ask not timed" "$(sr_m waste.waiting-on-you)"
sr_ask_ev "key=waive:evidence|reply=waive|at=2026-10-06T14:00:00Z"
sr_run "$SR_PLAN"
expect_eq "SP4b …beside the asks it did time, whose minutes stand" "60 min partial, 1 ask not timed: waive:evidence" "$(sr_m waste.waiting-on-you)"

# ============================================================
section "§WAITS: a held or pending task's note names everything it waits on, in words, never a count of the rest"
# ============================================================
# fails-when: a note names one read and counts the others (`waits on step 8 +5`), or prints a read's token
# (approval:release, proof:review, head, merge) where the words belong. The words: step N; your approval of D<n>; your
# approval of the <name>; the reviews; the last build row landing; the writer task's label; the merge, in the order the
# reads are read. T18 at Step 8 reads six things, T19 the merge T18 makes, and T5, building, reads two approvals owed.
sr_world waits "6 6 12 12"
# NO REGRESSION IS OWED, so the merge row waits by its kind on the reviews and the head alone.
awk '{ print } /^canonical_sdlc_version: 15$/ { print "regression: no" }' "$SR_PLAN" > "$SR_PLAN.t" && mv "$SR_PLAN.t" "$SR_PLAN"
awk -F'|' 'BEGIN { OFS = "|" } $2 == " T5 " && NF > 9 { $6 = " approval:release, approval:D4 " } { print }
  /^\| T17 / {
    print "| T18 | 8 | integrate | Merge row · complexity: standard | approval:release, T8, approval:D4 | 10 | REQ-1 | lib/t18.sh | — |"
    print "| T19 | 9 | close | Close · complexity: standard | — | 10 | REQ-1 | .bionic/docs/record/wave-02-fx/close.md | — |" }' \
  "$SR_PLAN" > "$SR_PLAN.t" && mv "$SR_PLAN.t" "$SR_PLAN"
sr_ask_ev "key=approve:release|sent=-|title=approval: release|at=2026-10-06T20:00:00Z"
sr_ledger_put D4 "the width" "$SR_D_WAIT"
sr_run "$SR_PLAN"
expect_eq "WA0 precondition: the sheet prints (exit 0), T18 held, T19 pending, T5 held on what it reads" "0|held|pending|held" \
  "$RC|$(sr_f "$(sr_task T18)" state)|$(sr_f "$(sr_task T19)" state)|$(sr_f "$(sr_task T5)" state)"
expect_eq "WA1 T18 names its six reads in words, in the order read: the step, the reviews, the build, the two approvals and the writer" \
  "waits on step 8, the reviews, the last build row landing, your approval of the release, 4/8 and your approval of D4" \
  "$(sr_f "$(sr_task T18)" note)"
expect_eq "WA2 T19 names its step and the merge" "waits on step 9 and the merge" "$(sr_f "$(sr_task T19)" note)"
expect_eq "WA3 T5, building, is held on both approvals and names both" \
  "waits on your approval of the release and your approval of D4" "$(sr_f "$(sr_task T5)" note)"
expect_eq "WA4 one read alone: T12 names the release approval, T9 its writer by label" \
  "waits on your approval of the release|waits on 4/8" "$(sr_f "$(sr_task T12)" note)|$(sr_f "$(sr_task T9)" note)"
expect_eq "WA5 no note counts what it leaves out (WA1 read the notes of the same sheet)" "0" \
  "$(sr_tasks_f note | /usr/bin/grep -cE ' \+[0-9]+$')"

# ============================================================
section "§PR-WAIT: with the pull request open and no landing, the sheet names it as what the run waits on and the reader's ready set is empty"
# ============================================================
# fails-when: the sheet of a run whose request stands says nothing of it, or the reader still offers the integrate row
# as ready. Every row but the integrate row has landed, step 8 is current, the regression and the reviews stand, so with
# no request the integrate row is ready and with one it is not.
SR_REPLY_R="$BIONIC_SCRIPTS_DIR/payload/scripts/reader.sh"
sr_world prwait "6 6 12 12"
for sr_i in 5 6 7 8 9 10 11 12 13 14 15 16 17; do sr_state "T$sr_i" landed; done
awk '/^\| T17 / { print; print "| T18 | 8 | integrate | Merge row · complexity: standard | — | 10 | REQ-1 | lib/t18.sh | — |"; next } { print }' \
  "$SR_PLAN" > "$SR_PLAN.t" && mv "$SR_PLAN.t" "$SR_PLAN"
sr_ev "ev=step|n=8|at=2026-10-06T21:00:00Z"
sr_ev "ev=proof|kind=regression|head=$SR_C1|rc=0|at=2026-10-06T21:10:00Z"
sr_ev "ev=proof|kind=review|head=$SR_C1|rc=0|result=pass|at=2026-10-06T21:11:00Z"
sr_ready() { bash "$SR_REPLY_R" "$SR_PLAN" stop 2>&1 | sed -n 's/^ready=//p'; }
sr_run "$SR_PLAN"
expect_eq "PW0 control: no request is recorded, so the reader offers the integrate row and the sheet's note names no pull request" "T18|0" \
  "$(sr_ready)|$(sr_f "$(sr_task T18)" note | /usr/bin/grep -c 'pull request')"
sr_ev "ev=published|part=pr|url=https://example.invalid/pull/1|branch=wave/02-fx|commit=$SR_C1|base=main|by=publish|at=2026-10-06T21:30:00Z"
sr_run "$SR_PLAN"
expect_eq "PW1 the request open: the sheet's integrate row names it, and the merge as the person's" \
  "waits on your merge of the pull request https://example.invalid/pull/1" "$(sr_f "$(sr_task T18)" note)"
expect_eq "PW2 …the reader's ready set is empty (PW0 read it through the same question)" "" "$(sr_ready)"
expect_eq "PW3 …and the row has not landed: the sheet counts it open, pending" "pending" "$(sr_f "$(sr_task T18)" state)"
sr_ask_ev "key=pr-closed:wave:02-fx|sent=-|title=the pull request was closed unmerged|at=2026-10-06T21:40:00Z"
sr_run "$SR_PLAN"
expect_eq "PW4 the host closed it unmerged (its ask open): the sheet no longer says the run waits on that request (PW1 named it before)" "0" \
  "$(sr_f "$(sr_task T18)" note | /usr/bin/grep -c 'pull request')"

# ============================================================
section "§KINDS: an unruled matrix row (row:) and an unread ruling (ruling:) open on the register are asks on the sheet"
# ============================================================
# fails-when: either is open and missing from the sheet.
sr_world kinds "6 6 12 12"
sr_ask_ev "key=row:AC-2.1|sent=-|title=ruling: row AC-2.1|at=2026-10-06T21:00:00Z"
sr_ask_ev "key=ruling:r9|sent=-|title=ruling unread: T5|prompt=poker: NOT-LANDED T5 — w-T5 ended (MET) with an orchestrator ruling unread (r9); the row holds until a writer reads it: re-dispatch the row, or drop it|at=2026-10-06T21:01:00Z"
sr_run "$SR_PLAN"
expect_eq "KI1 the open row: and ruling: asks are on the sheet, raised at their local times" "row:AC-2.1 2:00 PM|ruling:r9 2:01 PM" \
  "$(sr_lines ask | while IFS= read -r l; do printf '%s %s\n' "$(sr_f "$l" key)" "$(sr_f "$l" raised)"; done | sr_join)"
# FIXTURE FIDELITY: the reply is the one the tick writes when a row holds until its writer reads a ruling. The ask holds
# the row that reply names, so the card places it under Blocked on you and never as an open ask blocking nothing.
# fails-when: the ruling ask reads holds=nothing or blocks=no while its reply names a row the tick holds.
expect_eq "KI1b the ruling ask holds the row its reply names, and so blocks (the open row: ask beside it holds nothing)" \
  "4/5|yes|nothing|no" \
  "$(sr_f "$(sr_ask ruling:r9)" holds)|$(sr_f "$(sr_ask ruling:r9)" blocks)|$(sr_f "$(sr_ask row:AC-2.1)" holds)|$(sr_f "$(sr_ask row:AC-2.1)" blocks)"
sr_close_ask ruling:r9
sr_run "$SR_PLAN"
expect_eq "KI2 the ruling read and closed: its ask is gone, the row's stays" "row:AC-2.1" \
  "$(sr_lines ask | while IFS= read -r l; do sr_f "$l" key; done | sr_join)"
sr_run --line "$SR_PLAN"
expect_eq "KI3 …and the Patrol's status counts the one left" "owed: 1" "$(printf '%s\n' "$OUT" | /usr/bin/grep -oE 'owed: [0-9]+')"

# ============================================================
section "§CLOCK: every clock time on the sheet is local and 12-hour, under a pinned zone"
# ============================================================
# fails-when: a UTC or 24-hour time prints. sr_times reads every h:mm on a sheet with what follows it, so a time
# printed any other way is read, not skipped.
sr_times() { printf '%s\n' "$1" | /usr/bin/grep -oE '[0-9]{1,2}:[0-9]{2}(:[0-9]{2})?( ?[AaPp][Mm])?Z?'; }
sr_bad_times() { sr_times "$1" | /usr/bin/grep -vE '^([1-9]|1[0-2]):[0-5][0-9] (AM|PM)$'; }
expect_eq "CL0 the time reader, proved on known strings: it reads a 12-hour time, a 24-hour one and an ISO instant" "3:06 AM|15:00|20:00:00Z" \
  "$(sr_times 'landed 3:06 AM, then 15:00 and 2026-10-06T20:00:00Z' | sr_join)"
expect_eq "CL0b …and the bad-time filter keeps the two that are not local 12-hour" "15:00|20:00:00Z" \
  "$(sr_bad_times 'landed 3:06 AM, then 15:00 and 2026-10-06T20:00:00Z' | sr_join)"
expect_eq "CL1 the sheet of every fact kind holds a dozen clock times or more, every one local and 12-hour" "yes|" \
  "$([ "$(sr_times "$SR_SHEET" | /usr/bin/grep -c .)" -ge 12 ] && echo yes)|$(sr_bad_times "$SR_SHEET" | sr_join)"
expect_eq "CL2 …and no ISO instant and no UTC word anywhere on it" "0|0" \
  "$(printf '%s\n' "$SR_SHEET" | /usr/bin/grep -cE '[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]')|$(printf '%s\n' "$SR_SHEET" | /usr/bin/grep -cw 'UTC')"
sr_sheet_world clock-late
SR_AT=$((SR_NOW + 9 * 3600)) sr_run "$SR_PLAN"
expect_eq "CL3 run past local midnight: the times still read 12-hour, those on another day with their date after" "yes|landed 3:06 AM 2026-10-06|" \
  "$([ "$(sr_times "$OUT" | /usr/bin/grep -c .)" -ge 12 ] && echo yes)|$(sr_f "$(sr_task T1)" note)|$(sr_bad_times "$OUT" | sr_join)"

# ============================================================
section "§GONE: the Score's indicator writers, the review rows, the grade verb and its log are gone from the code and the tests; the grade verb is an unknown word"
# ============================================================
# fails-when: a writer remains or the grade verb exits 0. The pattern is built in pieces so this file does not match
# itself; a planted copy of one writer proves the search reads what it is pointed at.
SR_GONE_RE="$(printf '%s' 'pages_read' 'ings|sitrep_sche' 'dule|sitrep_deci' 'sions|sitrep_go' 'als|sitrep_gr' 'ade|sitrep-gra' 'de/v1|sitrep[.]l' 'og|sitrep gr' 'ade|SITREP_MARK_NE' 'AR|sitrep_task_li' 'nes')"
SR_REPO_ROOT="$(cd "${BIONIC_HOOKS_DIR}/.." && pwd -P)"
mkdir -p "$TMPROOT/gone-plant"; printf '%s\n' "$(printf '%s' 'sitrep_go' 'als() {')" > "$TMPROOT/gone-plant/x.sh"
expect_eq "GO0 the search finds a planted writer" "1" \
  "$(/usr/bin/grep -rlE --include='*.sh' "$SR_GONE_RE" "$TMPROOT/gone-plant" | /usr/bin/grep -c .)"
expect_eq "GO1 no writer or reader of an indicator line, a review row, the grade or its log in hooks/, payload/scripts/ or tests/" "" \
  "$(/usr/bin/grep -rnE --include='*.sh' "$SR_GONE_RE" "$SR_REPO_ROOT/hooks" "$SR_REPO_ROOT/payload/scripts" "$SR_REPO_ROOT/tests" | cut -c1-160)"
sr_world gone "6 6 12 12"
sr_run "$SR_PLAN"
SR_GONE_RC0="$RC"
sr_run "$(printf '%s' 'gra' 'de')" A x "$SR_PLAN"
expect_eq "GO2 the sheet prints (0); the grade verb is refused as an unknown word (2), and nothing is written" "0|2|1|no" \
  "$SR_GONE_RC0|$RC|$(printf '%s\n' "$ERR" | /usr/bin/grep -c 'unknown')|$([ -e "$SR_DIR/$(printf '%s' 'sitrep.l' 'og')" ] && echo yes || echo no)"
sr_run "$(printf '%s' '--ba' 'sis')" "$SR_PLAN"
expect_eq "GO3 the close's arithmetic is on the sheet; its own flag is the usage error (2)" "2" "$RC"

# ============================================================
section "§ORDER: the task lines are in execution order — done by landing time, hand landings included; in flight by place on the line with what each is doing; the rest in dependency order"
# ============================================================
# The world: the plain fixture landed out of table order (T2 3:36, T3 by hand 3:50, T1 4:00, T4 5:12), T8 in its
# landing with one of its two suites green, T6 and T5 queued behind it, T7 building, and T10 reading what T11 writes
# so that dependency order puts T11 first.
sr_world order-run "60 6 12 12"
awk '/^\| T10 \| / { sub(/\| — \| 30 \|/, "| lib/t11.sh | 30 |") } { print }' "$SR_PLAN" > "$SR_PLAN.t" && mv "$SR_PLAN.t" "$SR_PLAN"
# T3 landed by hand: its queue landing leaves the log, and the hand landing's published event takes its place.
awk '!/^run\/v1\|ev=published\|row=T3\|/' "$SR_REC" > "$SR_REC.t" && mv "$SR_REC.t" "$SR_REC"
sr_ev "ev=published|row=T3|kind=hand|by=Dana Fixture (the orchestrator)|why=merged by hand on its greens|at=2026-10-06T10:50:00Z"
SR_CAND="$(printf 'd%.0s' $(seq 40))"
sr_ev "ev=ready|row=T8|name=w-T8|commit=$SR_C1|branch=wt/02-T8|tree=$SR_REPO/.worktrees/02-T8|suites=a.test.sh,b.test.sh|debt=-|carrier=1:x|at=2026-10-06T13:05:00Z"
sr_ev "ev=ready|row=T6|name=w-T6|commit=$SR_C1|branch=wt/02-T6|tree=$SR_REPO/.worktrees/02-T6|suites=a.test.sh|debt=-|carrier=1:x|at=2026-10-06T13:30:00Z"
sr_ev "ev=candidate|row=T8|base=$SR_C1|commit=$SR_CAND|tree=/landing/1|at=2026-10-06T13:35:00Z"
sr_ev "ev=verdict|row=T8|commit=$SR_CAND|suite=a.test.sh|result=green|log=/rec/T8a.log|at=2026-10-06T13:50:00Z"
sr_ev "ev=ready|row=T5|name=w-T5|commit=$SR_C1|branch=wt/02-T5|tree=$SR_REPO/.worktrees/02-T5|suites=a.test.sh|debt=-|carrier=1:x|at=2026-10-06T13:40:00Z"
sr_run "$SR_PLAN"
expect_eq "ORD0 precondition: the world prints (rc 0), four of its seventeen tasks done" "0|4 tasks, 120 of 600 min, 20%|13 tasks, 480 min" \
  "$RC|$(sr_m work.landed)|$(sr_m work.left)"
expect_eq "ORD1 done by landing time, the hand landing among them, then in flight by place on the line, then building" \
  "T2|T3|T1|T4|T8|T6|T5|T7" "$(sr_tasks_f id | head -8 | sr_join)"
expect_eq "ORD2 …each saying what it does: by hand, in its landing with its suites, queued behind the one before it, building" \
  "landed 3:50 AM by hand|in its landing, 1 of 2 suites green|queued behind 4/8|queued behind 4/6|building" \
  "$(for t in T3 T8 T6 T5 T7; do sr_f "$(sr_task "$t")" note; done | sr_join)"
expect_eq "ORD3 the rest in dependency order: T11, which T10 reads, before T10" "yes" \
  "$(sr_tasks_f id | awk '$0 == "T11" { a = NR } $0 == "T10" { b = NR } END { print (a && b > a) ? "yes" : "no" }')"

# ============================================================
section "§METRICS: correctness, waste and suite runs are numbers read from the record; a planted change moves each"
# ============================================================
sr_world metrics "6 6 12 12"
sr_run "$SR_PLAN"
expect_eq "ME0 the clean world: its one suite green at its last run, no whole run, no review, no finding; nothing discarded, no minute idle" \
  "1: 1 green, 0 red|not run yet|0 passed, 0 failed, 0 running|0|0 tasks, 0 min|0 of 4|0 min" \
  "$(sr_correct)|$(sr_waste)"
# A planted red run, not answered: one test red, and the task it is on is failed.
sr_ev "ev=verdict|row=T8|commit=$SR_C1|suite=a.test.sh|result=red|log=/rec/T8.log|at=2026-10-06T14:00:00Z"
sr_run "$SR_PLAN"
expect_eq "ME1 a red at head: the suite red at its last run, its task failed" "1: 0 green, 1 red|failed" \
  "$(sr_m tests.suites-run)|$(sr_f "$(sr_task T8)" state)"
# The red answered: a later green on the same task and suite.
sr_ev "ev=verdict|row=T8|commit=$SR_C1|suite=a.test.sh|result=green|log=/rec/T8b.log|at=2026-10-06T15:00:00Z"
sr_run "$SR_PLAN"
expect_eq "ME2 …answered by a later green: the suite green at its last run, the task running again" "1: 1 green, 0 red|running" \
  "$(sr_m tests.suites-run)|$(sr_f "$(sr_task T8)" state)"
# Open findings of a registered review, one then two.
printf 'reviewed: %s..%s\nfindings: 1\nfinding: 1 S2 on lib/t1.sh:3 the thing breaks\nshown: 1 bash tests/x.test.sh\n' "$SR_C1" "$SR_H" > "$SR_DIR/critic.md"
sr_ev "ev=proof|kind=review|head=$SR_H|evidence=record/wave-02-fx/critic.md|question=adversarial|reader=crit|result=fail|scope=piece|at=2026-10-06T20:00:00Z"
sr_run "$SR_PLAN"
SR_ME3="$(sr_correct)"
printf 'reviewed: %s..%s\nfindings: 2\nfinding: 1 S2 on lib/t1.sh:3 the thing breaks\nfinding: 2 S1 on lib/t2.sh:4 and so does this\nshown: 1 bash tests/x.test.sh\nshown: 2 bash tests/y.test.sh\n' "$SR_C1" "$SR_H" > "$SR_DIR/critic.md"
sr_run "$SR_PLAN"
expect_eq "ME3 one failing review with one open S2 finding, then the same record holding an S1 too" \
  "1: 1 green, 0 red|not run yet|0 passed, 1 failed, 0 running|1|2|2" \
  "$SR_ME3|$(sr_m findings.open)|$(sr_f "$(sr_lines review)" open-findings)"
# A run discarded, then a run killed at the gate (rc 137): each a discarded suite run.
sr_world metrics-runs "6 6 12 12"
sr_ev "ev=verdict|row=T8|commit=$SR_C1|suite=a.test.sh|result=discarded|log=/rec/T8.log|at=2026-10-06T14:00:00Z"
sr_run "$SR_PLAN"
SR_ME4="$(sr_waste)"
printf 'key=a.test.sh\nkind=landing\nwho=%s:w-T9\ntree=%s/.worktrees/02-T9\nasked=%d\nholder=-\nadmitted=%d\nended=%d\nrc=137\npromise=5:0.1:30\n' \
  "$SID" "$(cd "$SR_REPO" && pwd -P)" "$((SR_NOW - 600))" "$((SR_NOW - 590))" "$((SR_NOW - 300))" > "$SR_GATE/requests/3"
sr_run "$SR_PLAN"
expect_eq "ME4 a discarded run, then a run killed at the gate: each counts as discarded, of every suite run" "0 tasks, 0 min|1 of 5|0 min|0 tasks, 0 min|2 of 6|0 min" \
  "$SR_ME4|$(sr_waste)"
# A task dropped, and an idle turn from 16:00Z to 17:12Z: 72 minutes.
sr_ev "ev=drop|row=T15|why=fixture|at=2026-10-06T15:30:00Z"; sr_ev "ev=drop|row=T16|why=fixture|at=2026-10-06T15:30:00Z"
sr_stop t2 16:00:00 3 1 T9 "" 1 T9 1
sr_stop t3 17:12:00 4 0 "" T9 0 "" 0
sr_run "$SR_PLAN"
expect_eq "ME5 two tasks dropped and a 72-minute idle turn: the waste in numbers; the dropped tasks leave the count" \
  "2 tasks, 60 min|2 of 6|72 min|4 tasks, 120 of 540 min, 22%" "$(sr_waste)|$(sr_m work.landed)"
# A turn's end the log's appender writes, idle from 18:00Z, owns the interval to now (22:00Z) while the run is open, and
# counts beside the idle turn above.
bash -c '. "$1/log.sh" && RUN_LOG="$2" LOG_AT=2026-10-06T18:00:00Z log_append stop "session=$3" turn=t4 current=4 state=ok ceiling= width=4 open=3 free=1 ready=T9 launched= declined= missed=1 idle=T9 room=1' \
  _ "$BIONIC_SCRIPTS_DIR/payload/scripts/lib" "$SR_DIR/run.log" "$SID"
sr_run "$SR_PLAN"
expect_eq "ME5c …and a turn's end written to the run's log counts too: 72 and 240 minutes" "312 min" "$(sr_m waste.ready-unstarted)"

# A red a suite stands in at the working head counts though no row added it: a `standing` event the line recorded, until a
# later green of the suite answers it. It marks no task failed.
sr_world metrics-standing "6 6 12 12"
sr_ev "ev=standing|head=$SR_H|suite=b.test.sh|lines=2|log=/rec/standing-b.log|cause=code|against=-|at=2026-10-06T14:00:00Z"
sr_run "$SR_PLAN"
expect_eq "ME6 a suite red standing at the head is a suite red at its last run, and no task is failed by it" "2: 1 green, 1 red|0" \
  "$(sr_m tests.suites-run)|$(sr_tasks_f state | /usr/bin/grep -c '^failed$')"
sr_ev "ev=standing|head=$SR_H|suite=b.test.sh|lines=2|log=/rec/standing-b2.log|cause=code|against=-|at=2026-10-06T14:30:00Z"
sr_ev "ev=standing|head=$SR_H|suite=c.test.sh|lines=1|log=/rec/standing-c.log|cause=environment|against=stamp|at=2026-10-06T14:31:00Z"
sr_ev "ev=verdict|row=T7|commit=$SR_C1|suite=d.test.sh|result=red|log=/rec/T7d.log|at=2026-10-06T14:40:00Z"
sr_run "$SR_PLAN"
expect_eq "ME6b a suite standing twice counts once; a standing suite and a row's own red add: three suites red, T7 failed" "4: 1 green, 3 red|1" \
  "$(sr_m tests.suites-run)|$(sr_tasks_f state | /usr/bin/grep -c '^failed$')"
sr_ev "ev=verdict|row=T6|commit=$SR_C1|suite=c.test.sh|result=red|log=/rec/T6c.log|at=2026-10-06T14:50:00Z"
sr_run "$SR_PLAN"
expect_eq "ME6c a row's red of a suite already standing is one red, not two: still three" "4: 1 green, 3 red|2" \
  "$(sr_m tests.suites-run)|$(sr_tasks_f state | /usr/bin/grep -c '^failed$')"
sr_ev "ev=verdict|row=T5|commit=$SR_C1|suite=b.test.sh|result=green|log=/rec/T5b.log|at=2026-10-06T15:00:00Z"
sr_run "$SR_PLAN"
expect_eq "ME6d a later green of the standing suite answers it: two suites red" "4: 2 green, 2 red" "$(sr_m tests.suites-run)"

# A review is counted once per question and scope, by its latest result: structure on the whole passed then failed
# (one failed), adversarial on a piece failed then passed (one passed), evidence on the whole passed once. The reader
# holds a later reading of one question and scope at one head in place of the earlier, so each stands as one line.
sr_world metrics-reviews "6 6 12 12"
for f in s1 s2 a1 a2 e1; do printf 'reviewed: %s..%s\nfindings: 0\n' "$SR_C1" "$SR_H" > "$SR_DIR/$f.md"; done
sr_ev "ev=proof|kind=review|head=$SR_H|evidence=record/wave-02-fx/s1.md|question=structure|reader=c1|result=pass|scope=whole|at=2026-10-06T19:00:00Z"
sr_ev "ev=proof|kind=review|head=$SR_H|evidence=record/wave-02-fx/a1.md|question=adversarial|reader=c2|result=fail|scope=piece|at=2026-10-06T19:05:00Z"
sr_ev "ev=proof|kind=review|head=$SR_H|evidence=record/wave-02-fx/e1.md|question=evidence|reader=a1|result=pass|scope=whole|at=2026-10-06T19:10:00Z"
sr_ev "ev=proof|kind=review|head=$SR_H|evidence=record/wave-02-fx/s2.md|question=structure|reader=c3|result=fail|scope=whole|at=2026-10-06T20:00:00Z"
sr_ev "ev=proof|kind=review|head=$SR_H|evidence=record/wave-02-fx/a2.md|question=adversarial|reader=c4|result=pass|scope=piece|at=2026-10-06T20:05:00Z"
sr_run "$SR_PLAN"
expect_eq "RV1 five results of reviews, a line for each one standing, and the count by question and scope at its latest: 2 passed, 1 failed" \
  "5|a1.md a2.md e1.md s1.md s2.md|2 passed, 1 failed, 0 running" \
  "$(sr_lines review | /usr/bin/grep -c .)|$(sr_lines review | sed 's/.*record=record\/wave-02-fx\///' | sort | tr '\n' ' ' | sed 's/ $//')|$(sr_m reviews)"

# Correctness names the suites run, each by its last verdict on the line, then the whole run. A suite named by its
# path is the suite its bare name is; the whole run's own verdicts are no suite's run here.
sr_world metrics-suites "6 6 12 12"
sr_run "$SR_PLAN"
expect_eq "SU0 the clean world: its one suite green at its last run, and no whole run yet" \
  "1: 1 green, 0 red|not run yet" "$(sr_m tests.suites-run)|$(sr_m tests.whole-run)"
sr_ev "ev=verdict|row=T8|commit=$SR_C1|suite=tests/b.test.sh|result=red|log=/rec/T8b.log|at=2026-10-06T14:00:00Z"
sr_ev "ev=verdict|row=T5|commit=$SR_C1|suite=c.test.sh|result=red|log=/rec/T5c.log|at=2026-10-06T14:05:00Z"
sr_ev "ev=verdict|row=T6|commit=$SR_C1|suite=c.test.sh|result=green|log=/rec/T6c.log|at=2026-10-06T14:10:00Z"
sr_ev "ev=verdict|row=T6|commit=$SR_C1|suite=c.test.sh|result=discarded|log=/rec/T6c2.log|at=2026-10-06T14:12:00Z"
sr_ev "ev=verdict|row=regression|commit=$SR_H|suite=z.test.sh|result=green|log=/rec/z.log|admitted=-|width=-|kind=regression|at=2026-10-06T14:20:00Z"
sr_ev "ev=verdict|row=regression|commit=$SR_H|suite=y.test.sh|result=red|log=/rec/y.log|admitted=-|width=-|kind=regression|at=2026-10-06T14:21:00Z"
sr_run "$SR_PLAN"
expect_eq "SU1 three suites by their last verdict (a discarded run is none); the whole run's own verdicts with no proof are no whole run; the reviews after" \
  "3: 2 green, 1 red|not run yet|0 passed, 0 failed, 0 running|0" \
  "$(sr_correct)"
SR_H2="$(printf 'b%.0s' $(seq 40))"
sr_ev "ev=proof|kind=regression|head=$SR_H2|evidence=record/wave-02-fx/regression-run-$SR_H2.log|at=2026-10-06T15:00:00Z"
sr_run "$SR_PLAN"
expect_eq "SU2 a whole run proved at a head this repository does not hold: red at its head, which is not behind the working head" \
  "red at bbbbbbbb, not in this head's history" "$(sr_m tests.whole-run)"
awk 'NR > 1 && /^---$/ && !d { print "regression: no"; d = 1 } { print }' "$SR_PLAN" > "$SR_PLAN.t" && mv "$SR_PLAN.t" "$SR_PLAN"
sr_run "$SR_PLAN"
expect_eq "SU3 a plan that owes no whole run says so, beside the suites it ran" "3: 2 green, 1 red|not run (regression: no, Step 0)" "$(sr_m tests.suites-run)|$(sr_m tests.whole-run)"

section "§WHOLE: the whole run reads green only at the head it ran at with nothing owed; anywhere else it is red, the landings since it counted"
# ============================================================
# fails-when: a proof line reads green whatever its owed= says; or a head past it reads red with only docs landed (WH3, WH4)
# or green with a code path landed (WH5); or the landings since the whole run go uncounted, or a count of one says landings.
# FIXTURE FIDELITY: the world's tree committed and the working branch set on it, so the whole run's head is a commit
# here; the proof is the event `proof-add regression` writes (lib/proof.sh `proof_event`); each later commit
# is a commit on the working branch.
# ANTI-VACUITY: WH1 reads green and WH2 red through the same measurement on the same world, one planted owed= apart; WH5 is
# the mutant of WH3 and WH4, one code commit apart, so the green arms read content and not position.
sr_proof() {  # <head> [<owed suites>] -> the run's regression proof replaced by one at <head> that left <owed> red
  awk '!/^run\/v1\|ev=proof\|kind=regression\|/' "$SR_REC" > "$SR_REC.t" && mv "$SR_REC.t" "$SR_REC"
  sr_ev "ev=proof|kind=regression|head=$1|evidence=record/wave-02-fx/regression-run-$1.log${2:+|owed=$2}|at=2026-10-06T15:00:00Z"
}
sr_commit() {  # <file> -> one more commit on the working branch, the branch moved to it; prints nothing
  mkdir -p "$(dirname "$SR_REPO/$1")"; printf 'x\n' >> "$SR_REPO/$1"
  ( cd "$SR_REPO" && git add -A >/dev/null 2>&1 && git -c user.email=t@t -c user.name=t commit -qm "$1" >/dev/null 2>&1 )
  git -C "$SR_REPO" branch -f wave/02-fx HEAD >/dev/null 2>&1
}
sr_world whole-head "6 6 12 12"
sr_commit lib/a.sh
SR_F="$(git -C "$SR_REPO" rev-parse wave/02-fx)"
sr_proof "$SR_F"
sr_run "$SR_PLAN"
expect_eq "WH1 a whole run at the working head with nothing owed: green at that head" "green at ${SR_F:0:8}" "$(sr_m tests.whole-run)"
sr_proof "$SR_F" b.test.sh
sr_run "$SR_PLAN"
expect_eq "WH2 the same whole run with a suite owed: red at the working head, no landing since" "red at ${SR_F:0:8}, 0 landings before this head" "$(sr_m tests.whole-run)"
sr_proof "$SR_F"
sr_commit README.md
sr_run "$SR_PLAN"
expect_eq "WH3 the green whole run with one docs landing past it: green at the whole run's head, one landing since moved no code" "green at ${SR_F:0:8}, 1 landing since moved no code" "$(sr_m tests.whole-run)"
sr_commit CHANGELOG.md
sr_run "$SR_PLAN"
expect_eq "WH4 …and with two: two landings since" "green at ${SR_F:0:8}, 2 landings since moved no code" "$(sr_m tests.whole-run)"
sr_commit payload/x.sh; sr_run "$SR_PLAN"
expect_eq "WH5 …and a third that moved a code path: red at the whole run's head, three landings before this head" "red at ${SR_F:0:8}, 3 landings before this head" "$(sr_m tests.whole-run)"

# ============================================================
section "§FORECAST: the predicted close is the longest chain left, from now, at 1× until three landed tasks measure their own time; no typed number moves it, and admitting more never shortens one chain"
# ============================================================
# No launch on record, so no landed task measures its own time: the close is the 150-min chain T8 → T9 from 3:00 PM.
sr_world forecast "6 6 12 12"
sr_run "$SR_PLAN"
expect_eq "FC1 the predicted close is the chain from now at 1×; the forecast end is the approval plus the 48 h forecast" \
  "5:30 PM|5:30 PM|4/8 → 4/9, 150 min|48 h, ends 3:00 AM 2026-10-08" \
  "$(sr_m close.predicted)|$(sr_m close.unscaled)|$(sr_m close.chain)|$(sr_m clock.forecast)"
SR_FC1="$(sr_m close.predicted)"
awk '{ sub(/^forecast: 48h$/, "forecast: 24h") } { print }' "$SR_PLAN" > "$SR_PLAN.t" && mv "$SR_PLAN.t" "$SR_PLAN"
sr_run "$SR_PLAN"
expect_eq "FC2 a typed number moves nothing: the forecast halved, the predicted close is the same while the forecast end moved" \
  "$SR_FC1|24 h, ends 3:00 AM 2026-10-07" "$(sr_m close.predicted)|$(sr_m clock.forecast)"
# The close on the local clock: a time on now's day bare, past midnight with its date.
sr_world forecast-late "6 6 12 12"
SR_AT=$((SR_NOW - 6 * 3600)) sr_run "$SR_PLAN"; SR_FC8="$(sr_m close.predicted)"
SR_AT=$((SR_NOW + 12 * 3600)) sr_run "$SR_PLAN"; SR_FC9="$(sr_m close.predicted)"
SR_AT=$((SR_NOW + 8 * 3600 + 1800)) sr_run "$SR_PLAN"
expect_eq "FC8 at 9:00 AM and at 3:00 AM the next morning, now's own day: no date; at 11:30 PM it is past midnight, dated" \
  "11:30 AM|5:30 AM|2:00 AM 2026-10-07" "$SR_FC8|$SR_FC9|$(sr_m close.predicted)"
# One chain: every open task reads what the one before it writes, so no width can shorten it.
sr_world one-chain "6 6 12 12"
awk -F'|' 'BEGIN { OFS = "|" }
  $2 ~ /^ T([5-9]|1[0-7]) $/ { n = $2; gsub(/[ T]/, "", n); if (n + 0 > 5) $6 = " T" (n - 1) " " }
  { print }' "$SR_PLAN" > "$SR_PLAN.t" && mv "$SR_PLAN.t" "$SR_PLAN"
sr_run "$SR_PLAN"; SR_OC2="$(sr_m close.predicted)"
for i in 3 4; do
  printf 'key=a.test.sh\nkind=landing\nwho=%s:w-T%d\ntree=/elsewhere/project\nasked=%d\nholder=%s:\nadmitted=%d\npromise=5:0.1:30\n' \
    "$SID" "$((i + 4))" "$((SR_NOW - 600))" "$$" "$((SR_NOW - 590))" > "$SR_GATE/requests/$i"
done
sr_run "$SR_PLAN"
expect_eq "FC11 precondition: the chain is every open task" "4/5 → 4/6 → 4/7 → 4/8 → 4/9 → 4/10 → 4/11 → 4/12 → 4/13 → 4/14 → 4/15 → 4/16 → 4/17, 480 min" \
  "$(sr_m close.chain)"
expect_eq "FC12 admitted 2 then 4 on one chain: the predicted close does not move, 480 min at 1× either way" \
  "11:00 PM|$SR_OC2" "$(sr_m close.predicted)|$SR_OC2"

# ============================================================
section "§PACE: the close is scaled by the landed tasks' own time, launch to landing, over their size, once three have landed; read from the rosters' launches and the landing record's headers, never from the approval"
# ============================================================
# Four rows of 30 min land at 10:05Z, 10:35Z, 11:05Z and 12:05Z, launched 30, 30, 30 and 45 min before: 135 min of
# their own against 120 sized, so the 150-min chain takes 168.75 min, the close 5:49 PM.
sr_world pace "5 5 5 5"
sr_launch T1 09:35:00; sr_launch T2 10:05:00; sr_launch T3 10:35:00; sr_launch T4 11:20:00
sr_run "$SR_PLAN"
expect_eq "PA1 four landings: their own time against their size, and the close scaled by it" \
  "4 tasks, 135 min against 120 sized min|5:49 PM|5:30 PM" "$(sr_m work.task-time)|$(sr_m close.predicted)|$(sr_m close.unscaled)"
# A row landed twice, the second a merge of its own, counts once, to its later landing; a header naming no row of the
# plan counts nothing.
sr_ev "ev=published|row=T1|commit=$SR_H|kind=queue|by=-|why=-|at=2026-10-06T12:30:00Z"
sr_ev "ev=published|row=—|commit=$SR_C1|kind=queue|by=-|why=-|at=2026-10-06T13:00:00Z"
sr_ev "ev=published|row=T99|commit=$SR_C1|kind=queue|by=-|why=-|at=2026-10-06T13:00:00Z"
sr_run "$SR_PLAN"
expect_eq "PA1b a re-landed row counts once, to its later header; a header naming no row of the plan counts nothing" \
  "4 tasks, 280 min against 120 sized min" "$(sr_m work.task-time)"
# No landing: nothing measures the scale, so the chain stands at 1×.
sr_world pace-zero none
sr_run "$SR_PLAN"
expect_eq "PA2 no landing: the chain at 1×, nothing landed to measure" \
  "5:30 PM|0 tasks: none has landed|yes" \
  "$(sr_m close.predicted)|$(sr_m work.task-time)|$(sr_d close.predicted | /usr/bin/grep -q 'at 1×: 0 landed build tasks have a launch and a landing on record, under 3' && echo yes)"
# Fewer than three landings with a launch scale nothing: all four rows land, two of them with a launch on the roster;
# then one; then three. sr_unlaunch <row> takes a launch off the roster.
sr_unlaunch() { awk -v r="|row=$1" 'substr($0, length($0) - length(r) + 1) != r' "$SR_REPO/.bionic/tmp/roster-$SID.state" > "$SR_REPO/.bionic/tmp/r.t" && mv "$SR_REPO/.bionic/tmp/r.t" "$SR_REPO/.bionic/tmp/roster-$SID.state"; }
sr_world pace-two "5 5 5 5"
sr_launch T1 09:35:00; sr_launch T2 10:05:00
sr_run "$SR_PLAN"
expect_eq "PA4 two landings: their time counted, the rows with no landing header said (precondition)" \
  "2 tasks, 60 min against 60 sized min; 2 landed tasks with no launch or landing on record" "$(sr_m work.task-time)"
expect_eq "PA4b …the close is the chain at 1×, and the basis says 2, under 3" "5:30 PM|yes" \
  "$(sr_m close.predicted)|$(sr_d close.predicted | /usr/bin/grep -q 'at 1×: 2 landed build tasks have a launch and a landing on record, under 3' && echo yes)"
sr_run --line "$SR_PLAN"
expect_eq "PA4c …and the Patrol's status carries it" "close 5:30 PM" "${OUT##* · }"
sr_unlaunch T2
sr_run "$SR_PLAN"
expect_eq "PA4d one landing: the same, said for 1" "yes" \
  "$(sr_d close.predicted | /usr/bin/grep -q 'at 1×: 1 landed build task has a launch and a landing on record, under 3' && echo yes)"
sr_world pace-three "5 5 5 5"
sr_launch T1 09:35:00; sr_launch T2 10:05:00; sr_launch T3 10:35:00
sr_run "$SR_PLAN"
expect_eq "PA4e three landings scale the chain: 90 min against 90, the basis names them, and no 1× stands" "5:30 PM|yes|0" \
  "$(sr_m close.predicted)|$(sr_d close.predicted | /usr/bin/grep -q 'scaled by the 3 landed build tasks.* 90 min over 90 sized min' && echo yes)|$(sr_d close.predicted | /usr/bin/grep -c 'under 3')"
# Landings and no approval: the own time is measured, and nothing is predicted.
SR_APPROVED=none sr_world pace-unapproved "5 5 5 5"
sr_launch T1 09:35:00; sr_launch T2 10:05:00; sr_launch T3 10:35:00; sr_launch T4 11:20:00
sr_run "$SR_PLAN"
expect_eq "PA3 landings under an unapproved plan: their own time measured, no close predicted" \
  "4 tasks, 135 min against 120 sized min|-" "$(sr_m work.task-time)|$(sr_m close.predicted)"
# A delivered run at the same scale lends this run nothing: the close is this run's own chain.
SR_SCALE=wave sr_world floor none
sr_prev 72 wave
sr_run "$SR_PLAN"
expect_eq "PA5 a delivered run at the same scale lends no pace: the chain at 1×, and no line names that run" "5:30 PM|0" \
  "$(sr_m close.predicted)|$(printf '%s\n' "$OUT" | /usr/bin/grep -c 'wave-40')"

# ============================================================
section "§CLOSE-CASES: the forecast end is the Step-3 approval plus the typed forecast:, else the plan's own minutes; an unapproved plan, a run with no task open and a delivered run each say so"
# ============================================================
SR_NINE=$((SR_NOW - 21600))
SR_SCALE=wave SR_FORECAST= sr_world guess-plan none
sr_prev 60 wave
SR_AT=$SR_NINE sr_run "$SR_PLAN"
expect_eq "CC1 no forecast: the plan's own 600 minutes from the 3:00 AM approval end it at 1:00 PM, said" "10 h, ends 1:00 PM|yes|11:30 AM" \
  "$(sr_m clock.forecast)|$(sr_d clock.forecast | /usr/bin/grep -q "source: the plan's sized minutes" && echo yes)|$(sr_m close.predicted)"
SR_APPROVED=none sr_world guess-unapproved none
sr_run "$SR_PLAN"
SR_CC2="$(sr_m close.predicted)|$(sr_m clock.forecast)|$(sr_d close.predicted | /usr/bin/grep -c 'basis: no forecast until the plan is approved at Step 3')"
sr_run --line "$SR_PLAN"
expect_eq "CC2 no Step 3 approval: nothing predicted and no forecast end, said; the Patrol's status says it is not forecast" \
  "-|-|1|close not forecast" "$SR_CC2|${OUT##* · }"
sr_world guess-done "6 6 12 12"
for sr_i in 5 6 7 8 9 10 11 12 13 14 15 16 17; do sr_state "T$sr_i" landed; done
sr_run "$SR_PLAN"
expect_eq "CC3 every task landed and the run open: the predicted close is now, nothing left to forecast" "3:00 PM|1|none: no task is open" \
  "$(sr_m close.predicted)|$(sr_d close.predicted | /usr/bin/grep -c 'no task is open')|$(sr_m close.chain)"
SR_APPROVED=none SR_EXTRA=4 sr_world guess-delivered "6 6 12 12"
for sr_i in 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do sr_set "T$sr_i" status landed; done; sr_set T21 status active
sr_ev "ev=approval|key=step3|by=fixture|said=approved|at=2026-10-18T03:00:00Z"
sr_ev "ev=step|n=9|delivered=2026-10-18T15:07Z wave-02-fx 9.9.0 — closed by close-out.sh|at=2026-10-18T15:07:00Z"
sr_run "$SR_PLAN"
expect_eq "CC4 a delivered run with a task still open after the delivery: its close is the delivery, against the forecast end" \
  "running|8:07 AM 2026-10-18|48 h, ends 8:00 PM 2026-10-19|1" \
  "$(sr_f "$(sr_task T21)" state)|$(sr_m close.predicted)|$(sr_m clock.forecast)|$(sr_d close.predicted | /usr/bin/grep -c 'basis: delivered at 8:07 AM 2026-10-18')"
sr_run --line "$SR_PLAN"
expect_eq "CC5 …and the Patrol's status closes at the delivery" "close 8:07 AM 2026-10-18" "${OUT##* · }"
# Four rows sized 100 min each, each launched 6 min before it landed: 24 min of their own against 400 sized, so the
# 150-min chain takes 9 min; T8 is running, so it has its 15 min cadence left, not 5: the close is 3:19 PM.
sr_world guess-fast "5 5 5 5"
for sr_i in 1 2 3 4; do sr_set "T$sr_i" size 100; done
sr_launch T1 09:59:00; sr_launch T2 10:29:00; sr_launch T3 10:59:00; sr_launch T4 11:59:00
sr_run "$SR_PLAN"
SR_CC6="$(sr_m close.predicted)"
sr_run --line "$SR_PLAN"
expect_eq "CC6 landed tasks far under their size: the chain scaled down, on the sheet and in the Patrol's status" "3:19 PM|close 3:19 PM" "$SR_CC6|${OUT##* · }"

# ============================================================
section "§LINE: --line is the Patrol's status, <k> of <m> tasks · owed: <n> on you · <m> on events · close <time>"
# ============================================================
sr_world line "6 6 12 12"
sr_bind
sr_run --line "$SR_PLAN"
expect_eq "L1 the clean world: one line, exit 0" "0|4 of 17 tasks · owed: 0 on you · 0 on events · close 5:30 PM" "$RC|$OUT"
sr_ev "ev=verdict|row=T8|commit=$SR_C1|suite=a.test.sh|result=red|log=/rec/T8.log|at=2026-10-06T14:00:00Z"
sr_ask_ev "key=approve:release|sent=-|title=approval: release|at=2026-10-06T20:00:00Z"
sr_ask_ev "key=gate:abc|sent=-|title=gate act: merge|at=2026-10-06T20:00:00Z"
sr_run --line "$SR_PLAN"
SR_L2="$OUT"
sr_run "$SR_PLAN"
expect_eq "L2 two asks open: owed counts them, the same asks the sheet lists" "4 of 17 tasks · owed: 2 on you · 0 on events · close 5:30 PM|2" \
  "$SR_L2|$(sr_lines ask | /usr/bin/grep -c .)"
SR_FORECAST= sr_world line-none none
sr_run --line "$SR_PLAN"
expect_eq "L3 no landing: the close is the chain at 1×" "0 of 17 tasks · owed: 0 on you · 0 on events · close 5:30 PM" "$OUT"
section "§UNBOUND: --line over a run with no landing record prints its line and nothing on stderr"
sr_b=bash; for sr_c in /opt/homebrew/bin/bash /usr/local/bin/bash; do [ -x "$sr_c" ] && { sr_b="$sr_c"; break; }; done; SR_BASH="$sr_b" sr_run --line "$SR_PLAN"
expect_eq "UB1 no record, under the newest bash here (older bash sets a bare local empty): exit 0, stderr empty, the line L3 read" "0||0 of 17 tasks · owed: 0 on you · 0 on events · close 5:30 PM" "$RC|$ERR|$OUT"

# ============================================================
section "§ARGS: the verb's operands"
# ============================================================
sr_world args "6 6 12 12"
sr_run --line --line "$SR_PLAN"
expect_eq "A1 --line twice is the usage error (2)" "2" "$RC"
sr_run "$SR_REPO/no/such.plan.md"
expect_eq "A2 a named plan that is no file is refused (2), naming it" \
  "2|1" "$RC|$(printf '%s\n' "$ERR" | /usr/bin/grep -c 'no plan file at')"
sr_run bottom-line 'schedule holds (line 3)' "$SR_PLAN"
expect_eq "A3 a word the verb does not know is the usage error (2), said as unknown" "2|1" "$RC|$(printf '%s\n' "$ERR" | /usr/bin/grep -c 'unknown')"

# ============================================================
section "§SURFACES: the tick prints \`poker: sitrep <the --line output>\` on every tick that decides, byte for byte"
# ============================================================
# sr_tick_world <label> <mins> -> a world the tick will decide on: engaged, a commit, bound, armed.
sr_tick_world() {
  sr_world "$1" "$2"
  : > "$SR_REPO/.bionic/tmp/engaged-$SID.state"
  ( cd "$SR_REPO" && git add -A >/dev/null 2>&1 && git -c user.email=t@t -c user.name=t commit -qm fixture >/dev/null 2>&1 )
  sr_poke bind "$SR_PLAN" >/dev/null 2>&1; sr_poke arm >/dev/null 2>&1
}
sr_tick() { sr_poke tick > "$TMPROOT/tick.out" 2> "$TMPROOT/tick.err"; RC=$?; OUT="$(cat "$TMPROOT/tick.out")"; }
# The tick's worlds are unapproved plans (an approved one FILLs, and S1 pins QUIET), so the close is not forecast.
SR_APPROVED=none sr_tick_world surf "6 6 12 12"
sr_tick
SR_T1="$OUT"
sr_run --line "$SR_PLAN"; SR_L1="$OUT"
expect_eq "S1 the tick exits 0 and its last line is still its decision line" "0|decision=QUIET" \
  "$RC|$(printf '%s\n' "$SR_T1" | tail -1 | /usr/bin/grep -oE 'decision=[A-Z]+')"
expect_eq "S2 …it prints exactly one sitrep line, the Patrol's status byte for byte" "1|poker: sitrep $SR_L1" \
  "$(printf '%s\n' "$SR_T1" | /usr/bin/grep -c '^poker: sitrep ')|$(printf '%s\n' "$SR_T1" | /usr/bin/grep '^poker: sitrep ')"
sr_ask_ev "key=approve:release|sent=-|title=approval: release|at=2026-10-06T20:00:00Z"
SR_AT=$((SR_NOW + 60)) sr_tick
SR_T2="$OUT"
SR_AT=$((SR_NOW + 60)) sr_run --line "$SR_PLAN"
expect_eq "S3 an ask opened: the next tick's sitrep line moves with the Patrol's status" "poker: sitrep $OUT|yes" \
  "$(printf '%s\n' "$SR_T2" | /usr/bin/grep '^poker: sitrep ')|$([ "$OUT" != "$SR_L1" ] && echo yes)"
SR_AT=$((SR_NOW + 120)) sr_tick
expect_contains "S4 an unchanged tick (nothing decided moved) still takes the unchanged path" "poker: unchanged since " "$OUT"

# ============================================================
section "§REST: the watcher's rest and the status line's waits-on-you agree: it rests only while the line says every open ask is on you"
# ============================================================
# The tick's world above, its plan unapproved, so nothing is ready and no agent is out: the asks alone decide the rest.
# The pass is the shipped `tick --watch`; its rest code is read from lib/patrol.sh, its one home.
SR_REST="$(bash -c '. "$1/patrol.sh" >/dev/null 2>&1 && printf %s "${WATCH_RC_REST:-}"' _ "$BIONIC_SCRIPTS_DIR/payload/scripts/lib")"
sr_pass() { sr_poke tick --watch > "$TMPROOT/pass.out" 2> "$TMPROOT/pass.err"; RC=$?; }
sr_owed_of() { printf '%s\n' "$1" | /usr/bin/grep -oE 'owed: [0-9]+ on you · [0-9]+ on events'; }
expect_nonempty "RS0 precondition: the library names the rest code" "$SR_REST"
SR_APPROVED=none sr_tick_world rest "6 6 12 12"
sr_pass; SR_R0="$RC"
sr_run --line "$SR_PLAN"
expect_eq "RS1 no ask open: the line owes nothing on you, and the pass does not rest" "owed: 0 on you · 0 on events|no" \
  "$(sr_owed_of "$OUT")|$([ "$SR_R0" = "$SR_REST" ] && echo yes || echo no)"
sr_ask_ev "key=approve:release|sent=-|title=approval: release|at=2026-10-06T20:00:00Z"
SR_AT=$((SR_NOW + 60)) sr_pass; SR_R1="$RC"
SR_AT=$((SR_NOW + 60)) sr_run --line "$SR_PLAN"
expect_eq "RS2 one ask open on the person: the line says one on you and none on events, and the pass rests" \
  "owed: 1 on you · 0 on events|$SR_REST" "$(sr_owed_of "$OUT")|$SR_R1"
sr_ask_ev "key=waive:Q1|sent=-|title=waiver: Q1|at=2026-10-06T20:01:00Z"
sr_ask_ev "key=waive:Q1|answer=no|event=-|at=2026-10-06T20:02:00Z"
SR_AT=$((SR_NOW + 120)) sr_pass; SR_R2="$RC"
SR_AT=$((SR_NOW + 120)) sr_run --line "$SR_PLAN"
expect_eq "RS3 a waiver answered no waits on its review's run: the line counts it on events, and the pass does not rest" \
  "owed: 1 on you · 1 on events|no" "$(sr_owed_of "$OUT")|$([ "$SR_R2" = "$SR_REST" ] && echo yes || echo no)"

# ============================================================
section "§SCOPE: the asks are read from the named plan's register, never the session running the verb, never a session acting for no run"
# ============================================================
SID2="9a8b7c6d-1e2f-4a3b-8c4d-5e6f7a8b9c0d"
SID3="0f1e2d3c-4b5a-4968-8778-695a4b3c2d1e"
sr_world scope "6 6 12 12"
SR_PLAN_A="$SR_PLAN"; SR_PLAN_B="$SR_REPO/.bionic/docs/plans/epic-01-fx/wave-03-fx.plan.md"
sed 's/wave-02-fx/wave-03-fx/g; s/wave\/02-fx/wave\/03-fx/g; s/9\.9\.0/9.10.0/' "$SR_PLAN_A" > "$SR_PLAN_B"
sr_bind "$SR_PLAN_A" "$SID"
sr_bind "$SR_PLAN_B" "$SID2"
sr_ask_ev "key=approve:release|sent=-|title=approval: release|at=2026-10-06T20:00:00Z" "$SR_PLAN_A"
sr_ask_ev "key=approve:merge|sent=-|title=approval: merge|at=2026-10-06T20:01:00Z" "$SR_PLAN_B"
sr_owed_sid "key=waive:structure|sent=-|title=waiver: structure|prompt=poker: the structure review is owed|at=2026-10-06T20:02:00Z" "$SID3"
sr_ask_keys() { sr_lines ask | while IFS= read -r l; do printf '%s %s\n' "$(sr_f "$l" key)" "$(sr_f "$l" holds)"; done | sr_join; }
sr_run "$SR_PLAN_B"
expect_eq "SC0 precondition: the other run's register is read — plan B owes its own ask, which T17 waits on" "approve:merge 4/17" "$(sr_ask_keys)"
sr_run "$SR_PLAN_A"
expect_eq "SC1 plan A owes only its own run's ask: not the other run's, not a session's acting for no run" "approve:release 4/12" "$(sr_ask_keys)"
SR_SID="$SID2" sr_run "$SR_PLAN_A"
expect_eq "SC2 …and the same when the verb runs in the other run's session: the session running it plays no part" "approve:release 4/12" "$(sr_ask_keys)"
sr_run --line "$SR_PLAN_A"
expect_eq "SC3 …the Patrol's status counts the plan's ask alone" "owed: 1" "$(printf '%s\n' "$OUT" | /usr/bin/grep -oE 'owed: [0-9]+')"

# ============================================================
section "§GOALS: each goal of the plan's goals: line is read from what it names and has one status, met, not met or not measured"
# ============================================================
sr_goal_st() { sr_lines goal | while IFS= read -r l; do printf '%s=%s\n' "$(sr_f "$l" name)" "$(sr_f "$l" status)"; done | sr_join; }
sr_goal_m() { sr_f "$(sr_lines goal | /usr/bin/grep -F "goal: name=$1 status=")" measure; }   # <name> -> its measure and what it read
# sr_goals_sum -> the goal lines counted by status, `<m> of <g> met`, then `; <k> not measured yet` and `; <u> with no
# measure the sitrep can read` when any; `none declared` for no goal line. The sheet's goal lines carry each status.
sr_goals_sum() {
  sr_lines goal | while IFS= read -r l; do sr_f "$l" status; done | awk '
    { g++ } $0 == "met" { m++ } $0 == "on course" { c++ } $0 == "not measured" { k++ } $0 == "unreadable" { u++ }
    END { if (!g) { print "none declared"; exit }
          s = (m + 0) " of " g " met"; if (c) s = s "; " c " on course"; if (k) s = s "; " k " not measured yet"; if (u) s = s "; " u " with no measure the sitrep can read"; print s }'
}
sr_world goals-none "6 6 12 12"
sr_run "$SR_PLAN"
expect_eq "G0 a plan that declares no goal: none declared, and no goal: line beside it" "none declared|0" \
  "$(sr_goals_sum)|$(sr_lines goal | /usr/bin/grep -c .)"
SR_GOALS="fast landings · one-file median under 15m (landing-report --rows)
tests · whole run under 45 min at the approved head (the Step-5 run log)
handoff · a fresh session continues a no-run handoff (record/reader-test-handoff.md)
taste · the user likes the card" sr_world goals "6 6 12 12"
printf 'Gating: 9 passed, 0 failed\nWall: 3000s · work 9000s · width 4\n' > "$SR_DIR/regression-run-$SR_H.log"
sr_ev "ev=proof|kind=regression|head=$SR_H|evidence=record/wave-02-fx/regression-run-$SR_H.log|at=2026-10-06T20:00:00Z"
sr_run "$SR_PLAN"
expect_eq "G1 four goals: the one-file median of 9 min met, the 50-minute whole run not met, the record not measured yet, the measure the sitrep cannot read unreadable" \
  "fast landings=met|tests=not met|handoff=not measured|taste=unreadable|1 of 4 met; 1 not measured yet; 1 with no measure the sitrep can read" "$(sr_goal_st)|$(sr_goals_sum)"
expect_eq "G2 …each with what it read: 50 min for the whole run; a measure the sitrep cannot read says so and names the forms it reads, never a missing reader" \
  "yes|the user likes the card — the sitrep reads no measure of this form: name a record/<file>.md with a verdict: line, a <suite> §<section>, the run log, the landing report or the hand-holds count|0" \
  "$(sr_goal_m tests | /usr/bin/grep -q 'the whole run took 50 min' && echo yes)|$(sr_goal_m taste)|$(printf '%s\n' "$OUT" | /usr/bin/grep -c 'no reader')"
expect_eq "G2b the status says a goal is not measured once: one goal says it, and no goal line's measure ends in it" "1|0|yes" \
  "$(sr_lines goal | /usr/bin/grep -c ' status=not measured ')|$(sr_lines goal | /usr/bin/grep -c ' — not measured$')|$(sr_goal_m taste | /usr/bin/grep -q . && echo yes)"
printf '# reader test\n\nverdict: pass\n' > "$SR_DIR/reader-test-handoff.md"
sr_run "$SR_PLAN"
expect_eq "G3 a record that passes flips its goal to met; a clause of none is left out" "handoff=met|2 of 4 met; 1 with no measure the sitrep can read" \
  "$(sr_goal_st | tr '|' '\n' | /usr/bin/grep '^handoff=')|$(sr_goals_sum)"

# sr_criteria <AC>:<status>... -> this world's plan holds an Eval design row per criterion, its requirement its dotted
# id's, and the run's log a passing proof of each one discharged and a waiver of each one waived
sr_criteria() {
  local e a r
  { printf '\n## Eval design\n\n| Requirement | Approach | Criterion | Eval type | Eval | Fails when |\n|---|---|---|---|---|---|\n'
    for e in "$@"; do a="${e%%:*}"; r="${a#AC-}"; printf '| REQ-%s | x | %s | hermetic | `tests/a.test.sh` | not |\n' "${r%%.*}" "$a"; done; } >> "$SR_PLAN"
  for e in "$@"; do a="${e%%:*}"
    case "${e#*:}" in discharged) sr_ev "ev=proof|kind=eval|ac=$a|head=$SR_H|rc=0|at=2026-10-06T10:00:00Z" ;;
      waived) sr_ev "ev=waiver|ac=$a|head=$SR_H|by=fixture|said=waive it|at=2026-10-06T10:00:00Z" ;; esac; done
}
# sr_themes <current> <nine statuses> -> this world's plan made
# wave scale at step <current> with nine criteria, the statuses in order (two criteria of the first REQ, one each of the
# second to the fourth, two each of the fifth and sixth), and a requirements file of three themes beside it:
# the first two REQs under the first theme, the next three under the second, the sixth under the third. SR_REQ_AT names the file
# the plan's Step-1 line points at; unset, the plan names none and the file is the sibling under specs/ by the slug.
sr_themes() {
  local cur="$1" q q2 a; shift
  q="$SR_REPO/.bionic/docs/specs/epic-01-fx/wave-02-fx.requirements.md"
  [ -z "${SR_REQ_AT:-}" ] || q="$SR_REPO/.bionic/docs/$SR_REQ_AT"
  mkdir -p "${q%/*}"
  awk -v at="${SR_REQ_AT:-}" '
    NR > 1 && /^---$/ && !fm { fm = 1; print "scale: wave" }
    /^# fixture plan$/ && at != "" { print; print "\n- Step 1: requirements: " at "; approved by fixture"; next }
    { print }' "$SR_PLAN" > "$SR_PLAN.t" && mv "$SR_PLAN.t" "$SR_PLAN"
  [ "$cur" = 4 ] || sr_ev "ev=step|n=$cur|at=2026-10-06T10:00:00Z"
  q2=""; for a in AC-1.1 AC-1.2 AC-2.1 AC-3.1 AC-4.1 AC-5.1 AC-5.2 AC-6.1 AC-6.2; do q2="$q2 $a:$1"; shift; done
  sr_criteria $q2
  {
    printf -- '---\nscale: wave\n---\n# fixture requirements\n\n## Goal\n\nThe fixture ships.\n'
    printf '\n## The run closes itself\n\nThe run reaches its card without a person.\n'
    printf '\n### REQ-1 — one\n\n- AC-1.1 a. Fails when: b.\n- AC-1.2 a. Fails when: b.\n\n### REQ-2 — two\n\n- AC-2.1 a. Fails when: b.\n'
    printf '\n## Rules tested where they run\n\nEvery rule is tested through the door.\n'
    printf '\n### REQ-3 — three\n\n- AC-3.1 a. Fails when: b.\n\n### REQ-4 — four\n\n- AC-4.1 a. Fails when: b.\n'
    printf '\n### REQ-5 — five\n\n- AC-5.1 a. Fails when: b.\n- AC-5.2 a. Fails when: b.\n'
    printf '\n## The pages\n\nThe pages say what the run knows.\n\n### REQ-6 — six\n\n- AC-6.1 a. Fails when: b.\n- AC-6.2 a. Fails when: b.\n'
    printf '\n## Not Doing\n\n- nothing\n'
  } > "$q"
}
SR_MIXED="discharged pending pending pending pending pending discharged discharged waived"

# ============================================================
section "§REQ-GOALS-1: a wave plan with no goals: line reads its requirements' themes, one goal per theme, its status staged by step"
# ============================================================
# fails-when: "none declared", or a theme with open criteria past Step 6 reads anything but not met.
sr_world rg1 "6 6 12 12"; sr_themes 4 $SR_MIXED
sr_run "$SR_PLAN"
expect_eq "RG1-1 at step 4 with rows pending: the two themes with a criterion discharged on course, the third met, in the document's order" \
  "The run closes itself=on course|Rules tested where they run=on course|The pages=met|1 of 3 met; 2 on course" \
  "$(sr_goal_st)|$(sr_goals_sum)"
expect_eq "RG1-1b …each theme with its criteria discharged and its open REQs" "1 of 3 criteria discharged — open: REQ-1, REQ-2" \
  "$(sr_goal_m 'The run closes itself')"
sr_world rg1-late "6 6 12 12"; sr_themes 7 $SR_MIXED
sr_run "$SR_PLAN"
expect_eq "RG1-2 past step 6 a theme with a pending row is not met" \
  "The run closes itself=not met|Rules tested where they run=not met|The pages=met|1 of 3 met" \
  "$(sr_goal_st)|$(sr_goals_sum)"
sr_world rg1-done "6 6 12 12"; sr_themes 7 discharged discharged discharged discharged waived discharged discharged discharged waived
sr_run "$SR_PLAN"
expect_eq "RG1-3 every row discharged or waived: every theme met" "3 of 3 met" "$(sr_goals_sum)"
# A criterion whose Eval design row names no requirement, and whose id is no dotted one, is in no theme's count; the
# sheet's line names the cell that maps it. fails-when: the line names a serves: line, which no page at 15 holds.
sr_world rg1-unmapped "6 6 12 12"; sr_themes 4 $SR_MIXED
sed 's/^| REQ-1 | x | AC-1\.1 |/| — | x | AC-101 |/' "$SR_PLAN" > "$SR_PLAN.t" && mv "$SR_PLAN.t" "$SR_PLAN"
sr_run "$SR_PLAN"; SR_UNM="$(printf '%s\n' "$OUT" | /usr/bin/grep '^not mapped: ')"
expect_contains "RG1-4 a criterion naming no requirement: the sheet's line names the Requirement cell of its Eval design row" "Requirement cell" "$SR_UNM"
expect_absent "RG1-4b …and no serves: line, which no page at 15 holds" "serves:" "$SR_UNM"

# ============================================================
section "§REQ-GOALS-2: a goals: line's measured goals follow the theme goals"
# ============================================================
# fails-when: a measured goal is lost.
SR_GOALS="fast landings · one-file median under 15m (landing-report --rows)
handoff · a fresh session continues a no-run handoff (record/reader-test-handoff.md)" sr_world rg2 "6 6 12 12"
SR_REQ_AT=specs/epic-01-fx/named-elsewhere.requirements.md sr_themes 4 $SR_MIXED
sr_run "$SR_PLAN"
expect_eq "RG2-1 the requirements file the Step-1 line names is read: three themes, then the two measured goals" \
  "The run closes itself=on course|Rules tested where they run=on course|The pages=met|fast landings=met|handoff=not measured|2 of 5 met; 2 on course; 1 not measured yet" \
  "$(sr_goal_st)|$(sr_goals_sum)"

# ============================================================
section "§REQ-GOALS-3: a hand-holds goal read from the landing report counts the window from the last build landing to delivery, against its target"
# ============================================================
# fails-when: the median reader answers, or it is not measured.
SR_GOALS="hand-holds · zero from the last landing to delivery (landing-report)" sr_world rg3 "6 6 12 12"
sr_run "$SR_PLAN"
expect_eq "RG3-1 no hand-hold since the last build landing: the zero target is met" "hand-holds=met" "$(sr_goal_st)"
sr_ev "ev=hand|what=stop-run|row=T8|at=2026-10-06T14:00:00Z"
sr_run "$SR_PLAN"
expect_eq "RG3-2 one stop-run after the last build landing: not met, the reading the window's count before the run is delivered" \
  "hand-holds=not met|zero from the last landing to delivery — 1 hand-hold from the last build landing (T4) to now: the run is not delivered" \
  "$(sr_goal_st)|$(sr_goal_m hand-holds)"

# sr_goal_put <goal text, \n for a line break> -> this world's plan carries a `## Goal` section before its Tasks.
sr_goal_put() {
  printf '## Goal\n\n%b\n' "$1" > "$TMPROOT/goal.txt"
  awk -v gf="$TMPROOT/goal.txt" '/^## Tasks$/ && !d { while ((getline l < gf) > 0) print l; print ""; d = 1 } { print }' "$SR_PLAN" > "$SR_PLAN.t" && mv "$SR_PLAN.t" "$SR_PLAN"
}
# sr_goal_card <goal text> -> the Purpose line the Step-1 card prints over a requirements artifact holding that Goal,
# drawn at a width no line folds at.
sr_goal_card() {
  printf -- '---\nscale: wave\n---\n# fx\n\n## Goal\n\n%b\n\n## Theme\n\nOpener.\n\n### REQ-1 — one\n\nThe fixture holds one requirement.\n\nprovenance: fixture\n\n- AC-1.1 a. Fails when: b.\n\n## Not Doing\n\n- nothing\n' "$1" > "$SR_REPO/g.requirements.md"
  ( cd "$SR_REPO" && env BIONIC_LINE_WIDTH=400 bash "$BIONIC_SCRIPTS_DIR/payload/scripts/card.sh" step1 g.requirements.md 2>/dev/null ) \
    | awk '/^  Purpose$/ { on = 1; next } on { sub(/^ +/, ""); print; exit }'
}

# ============================================================
section "§RUN-GOAL: the sheet's run.goal: is the plan's Goal paragraph, as the Step-1 card prints it; a plan with no Goal prints none"
# ============================================================
# fails-when: a plan with a Goal paragraph prints no run.goal: line, or the line differs from the paragraph; or a plan
# with no Goal prints a line or an error. One world, read before and after the Goal is put, so the absence is read
# through the extractor that then finds the line.
sr_world run-goal "6 6 12 12"
sr_run "$SR_PLAN"
SR_RG_NONE="$(sr_lines run.goal | /usr/bin/grep -c .)|$RC|$ERR"
SR_RG_TEXT='Ship the `fixture` so the run\nreads its own purpose.\n\nA second paragraph is not the goal.'
sr_goal_put "$SR_RG_TEXT"
sr_run "$SR_PLAN"
expect_eq "RUNG-1 a plan with a Goal paragraph prints run.goal: its first paragraph on one line, markup as the card drops it; the same plan before the Goal printed no line and no error" \
  "0|0||Ship the fixture so the run reads its own purpose." "$SR_RG_NONE|$(sr_val run.goal)"
expect_eq "RUNG-2 …and the line equals the Purpose the Step-1 card prints for that paragraph" "$(sr_goal_card "$SR_RG_TEXT")" "$(sr_val run.goal)"
expect_eq "RUNG-2b …the card's Purpose was read, not empty" "Ship the fixture so the run reads its own purpose." "$(sr_goal_card "$SR_RG_TEXT")"
expect_eq "RUNG-3 run.goal stands after run.last-landing and before the first step line" "run.last-landing|run.goal|step" \
  "$(sr_keys | tr '|' '\n' | awk '$0 == "run.last-landing" { on = 1 } on { print } $0 == "step" { exit }' | sr_join)"
expect_eq "RUNG-4 the verb's exit and stderr stay clean with the Goal in the plan" "0|" "$RC|$ERR"

# ============================================================
section "§FOR: each theme's goal: line ends for=<the theme's opening sentence>, the fields before it as they stood"
# ============================================================
# fails-when: a theme that opens on a sentence prints no for=, or the fields before it change.
sr_world for "6 6 12 12"; sr_themes 4 $SR_MIXED
sr_run "$SR_PLAN"
expect_eq "FOR1 each theme's line carries its opener, for= the last field, in the document's order" \
  "The run reaches its card without a person.|Every rule is tested through the door.|The pages say what the run knows." \
  "$(sr_lines goal | while IFS= read -r l; do sr_f "$l" for; done | sr_join)"
expect_eq "FOR2 the first theme's whole line: name, status and measure in their places, for= last" \
  "goal: name=The run closes itself status=on course measure=1 of 3 criteria discharged — open: REQ-1, REQ-2 for=The run reaches its card without a person." \
  "$(sr_lines goal | head -1)"
# a theme whose body opens on two sentences gives the first, one that opens on its first REQ gives none
sed -i.bak -e 's/^Every rule is tested through the door\.$/Every rule is tested through the door. Nothing is read twice./' -e '/^The pages say what the run knows\.$/d' \
  "$SR_REPO/.bionic/docs/specs/epic-01-fx/wave-02-fx.requirements.md" && rm -f "$SR_REPO/.bionic/docs/specs/epic-01-fx/wave-02-fx.requirements.md.bak"
sr_run "$SR_PLAN"
expect_eq "FOR3 a theme with two opening sentences gives the first; a theme with no opener prints no for= while the others keep theirs" \
  "The run reaches its card without a person.|Every rule is tested through the door.||2" \
  "$(sr_lines goal | while IFS= read -r l; do sr_f "$l" for; done | sr_join)|$(sr_lines goal | /usr/bin/grep -c ' for=')"
expect_eq "FOR3b …and the theme with no opener keeps its name, status and measure" \
  "The pages|met|1 of 2 criteria discharged, 1 waived — none open" \
  "$(sr_f "$(sr_lines goal | tail -1)" name)|$(sr_f "$(sr_lines goal | tail -1)" status)|$(sr_f "$(sr_lines goal | tail -1)" measure)"
SR_GOALS="handoff · a fresh session continues a no-run handoff (record/reader-test-handoff.md)" sr_world for-measured "6 6 12 12"; sr_themes 4 $SR_MIXED
sr_run "$SR_PLAN"
expect_eq "FOR4 a measured goal of the goals: line carries no for= while the three themes beside it do" "3||handoff" \
  "$(sr_lines goal | /usr/bin/grep -c ' for=')|$(sr_f "$(sr_lines goal | /usr/bin/grep -F 'goal: name=handoff status=')" for)|$(sr_f "$(sr_lines goal | /usr/bin/grep -F 'goal: name=handoff status=')" name)"

# ============================================================
section "§TASK-GOAL: at task scale the sheet reads one goal, the run, over every criterion of the matrix"
# ============================================================
# fails-when: a task-scale sheet prints no goal: line. The matrix is the §REQ-GOALS-1 fixture's, the plan made task scale.
sr_world task-goal "6 6 12 12"; sr_themes 4 $SR_MIXED
sed -i.bak 's/^scale: wave$/scale: task/' "$SR_PLAN" && rm -f "$SR_PLAN.bak"
sr_goal_put 'The run proves the fixture. It has two halves.'
sr_run "$SR_PLAN"
expect_eq "TG1 one goal: line named the run, its measure the whole matrix's, for= the Goal's first sentence" \
  "1|goal: name=the run status=on course measure=3 of 9 criteria discharged, 1 waived — open: REQ-1, REQ-2 and 3 more for=The run proves the fixture." \
  "$(sr_lines goal | /usr/bin/grep -c .)|$(sr_lines goal)"
rm -f "$SR_REPO/.bionic/docs/specs/epic-01-fx/wave-02-fx.requirements.md"
sr_run "$SR_PLAN"
expect_eq "TG2 a task plan with no requirements file reads the same matrix: the criteria name the REQs" \
  "goal: name=the run status=on course measure=3 of 9 criteria discharged, 1 waived — open: REQ-1, REQ-2 and 3 more for=The run proves the fixture." \
  "$(sr_lines goal)"
sr_world task-goal-late "6 6 12 12"; sr_themes 7 $SR_MIXED
sed -i.bak 's/^scale: wave$/scale: task/' "$SR_PLAN" && rm -f "$SR_PLAN.bak"
sr_run "$SR_PLAN"
expect_eq "TG3 past Step 6 with a criterion open the run is not met, and with no Goal in the plan the line has no for=" \
  "1|not met|3 of 9 criteria discharged, 1 waived — open: REQ-1, REQ-2 and 3 more|" \
  "$(sr_lines goal | /usr/bin/grep -c .)|$(sr_f "$(sr_lines goal)" status)|$(sr_f "$(sr_lines goal)" measure)|$(sr_f "$(sr_lines goal)" for)"
SR_SCALE=task sr_world task-goal-none "6 6 12 12"
sr_goal_put 'The run proves the fixture.'
sr_run "$SR_PLAN"
expect_eq "TG4 a task plan with a Goal and no matrix has no criterion to read: no goal: line, the Goal still on the sheet, the verb clean" "0|The run proves the fixture.|0" \
  "$(sr_lines goal | /usr/bin/grep -c .)|$(sr_val run.goal)|$RC"

# ============================================================
section "§GOAL-AGREE: one plan, both surfaces — the release approval card and the sheet give each goal the same status, from the one function"
# ============================================================
# fails-when: a goal reads two ways. The plan holds all three statuses, and themes past Step 6 with criteria open,
# the case the two surfaces once marked differently. The card is the release-approval verb's own, rendered with
# --preview, which writes nothing; its goal rows open on a mark, read back as the status it stands for.
SR_GOALS="fast landings · one-file median under 15m (landing-report --rows)
handoff · a fresh session continues a no-run handoff (record/reader-test-handoff.md)" sr_world goal-agree "6 6 12 12"
sr_themes 7 $SR_MIXED
sr_bind
git -C "$SR_REPO" branch -f wave/02-fx HEAD >/dev/null 2>&1   # the card renders at the working branch's head
sr_run "$SR_PLAN"
SR_GA_SHEET="$(sr_goal_st | tr '|' '\n' | sort | sr_join)"
SR_GA_CARD_OUT="$(sr_poke release-approval --preview "$SR_PLAN" 2>&1)"
sr_card_goals() {  # stdin: a release approval card -> `<name>=<status>` per goal row, read from its mark
  awk '/^Goals — / { on = 1; next } on && /^$/ { exit } on && /^[^ ]/ { print }' | while IFS= read -r l; do
    mk="${l%% *}"; rest="${l#* }"; nm="${rest%% — *}"
    case "$mk" in ✅) st=met ;; ✖*) st="not met" ;; ❔) st="not measured" ;; ⬜) st="on course" ;; *) st="unknown:$mk" ;; esac
    printf '%s=%s\n' "$nm" "$st"
  done
}
SR_GA_CARD="$(printf '%s\n' "$SR_GA_CARD_OUT" | sr_card_goals | sort | sr_join)"
expect_eq "GA0 precondition: the card renders its Goals and the sheet its goals, five each, all three statuses among them" "5|5|yes" \
  "$(printf '%s\n' "$SR_GA_CARD" | tr '|' '\n' | /usr/bin/grep -c .)|$(printf '%s\n' "$SR_GA_SHEET" | tr '|' '\n' | /usr/bin/grep -c .)|$(printf '%s\n' "$SR_GA_SHEET" | /usr/bin/grep -q '=met' && printf '%s\n' "$SR_GA_SHEET" | /usr/bin/grep -q '=not met' && printf '%s\n' "$SR_GA_SHEET" | /usr/bin/grep -q '=not measured' && echo yes)"
expect_eq "GA1 every goal reads the same on the card and on the sheet" "$SR_GA_SHEET" "$SR_GA_CARD"
expect_eq "GA2 …and the card's count of goals met is the sheet's" \
  "$(sr_goals_sum | sed 's/ met;.*//')" "$(printf '%s\n' "$SR_GA_CARD_OUT" | sed -n 's/^Goals — \([0-9]* of [0-9]*\) reached$/\1/p')"

# THE ON-COURSE WORD, on every surface. Two themes at step 4: Identity with eleven of its twelve criteria discharged,
# Cleanup with none. The sheet, the release card and the per-theme count each carry them apart.
# sr_course_world <label> -> a wave plan at step 4 whose requirements hold two themes: Identity, twelve criteria with the
# last pending, and Cleanup, twelve criteria all pending, and a goals: line beside them.
sr_course_world() {
  local q a i st
  sr_world "$1" "6 6 12 12"
  q="$SR_REPO/.bionic/docs/specs/epic-01-fx/wave-02-fx.requirements.md"; mkdir -p "${q%/*}"
  awk '/^---$/ && NR > 1 && !fm { fm = 1; print "scale: wave" } { print }' "$SR_PLAN" > "$SR_PLAN.t" && mv "$SR_PLAN.t" "$SR_PLAN"
  st=""; for a in 1 2; do for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
      st="$st AC-$a.$i:$([ "$a" = 1 ] && [ "$i" -le 11 ] && echo discharged || echo pending)"; done; done
  sr_criteria $st
  printf -- '---\nscale: wave\n---\n# fixture requirements\n\n## Goal\n\nThe fixture ships.\n\n## Identity\n\nIdentity is settled.\n\n### REQ-1 — identity\n\n- AC-1.1 a. Fails when: b.\n\n## Cleanup\n\nThe cruft goes.\n\n### REQ-2 — cleanup\n\n- AC-2.1 a. Fails when: b.\n' > "$q"
}
SR_GOALS="handoff · a fresh session continues a no-run handoff (record/reader-test-handoff.md)" sr_course_world ga-course
sr_bind
git -C "$SR_REPO" branch -f wave/02-fx HEAD >/dev/null 2>&1
sr_run "$SR_PLAN"
SR_GC_SHEET="$(sr_goal_st | tr "|" "\n" | LC_ALL=C sort | sr_join)"
SR_GC_CARD_OUT="$(sr_poke release-approval --preview "$SR_PLAN" 2>&1)"
SR_GC_CARD="$(printf "%s\n" "$SR_GC_CARD_OUT" | sr_card_goals | LC_ALL=C sort | sr_join)"
expect_eq "GA3 the theme at 11 of 12 reads on course and the one at 0 of 12 not measured, on the sheet" \
  "Cleanup=not measured|Identity=on course|handoff=not measured" "$SR_GC_SHEET"
expect_eq "GA4 …and the release card marks every goal as the sheet states it: on course has a mark of its own" "$SR_GC_SHEET" "$SR_GC_CARD"
expect_eq "GA5 …the counts are each theme's own on the sheet: 11 of 12 with REQ-1 open, 0 of 12 with REQ-2 open" \
  "11 of 12 criteria discharged — open: REQ-1|0 of 12 criteria discharged — open: REQ-2" \
  "$(sr_goal_m Identity)|$(sr_goal_m Cleanup)"
expect_eq "GA6 …and the release card's rows carry the same counts under the same names" \
  "11 of 12 criteria discharged, open: REQ-1|0 of 12 criteria discharged, open: REQ-2" \
  "$(printf '%s\n' "$SR_GC_CARD_OUT" | sed -n 's/^[^ ]* Identity — //p')|$(printf '%s\n' "$SR_GC_CARD_OUT" | sed -n 's/^[^ ]* Cleanup — //p')"
expect_eq "GA7 the on-course theme is not a goal reached: the card counts none of the three" "Goals — 0 of 3 reached" \
  "$(printf '%s\n' "$SR_GC_CARD_OUT" | /usr/bin/grep '^Goals')"

# ============================================================
section "§GOAL-MISS: the first landing that misses a goal makes the tick open decide:goal:<theme> on the run's register, once; it is an ask on the sheet until the goal reads met"
# ============================================================
SR_GOALS="fast landings · one-file median under 15m (landing-report --rows)
handoff · a fresh session continues a no-run handoff (record/reader-test-handoff.md)" SR_APPROVED=none sr_tick_world goal-miss "20 20 20 20"
sr_tick
expect_eq "GM1 four 20-minute one-file landings miss the 15-minute goal: the tick opens decide:goal:fast-landings on the register, and nothing for the goal not measured" \
  "decide:goal:fast-landings" "$(/usr/bin/grep -oE '\|key=decide:goal:[^|]*\|state=open\|' <(sr_asks) 2>/dev/null | cut -d'|' -f2 | sed 's/^key=//' | sr_join)"
expect_eq "GM2 …it is owed: the tick's sitrep line counts it" "owed: 1" \
  "$(/usr/bin/grep '^poker: sitrep ' "$TMPROOT/tick.out" | /usr/bin/grep -oE 'owed: [0-9]+')"
sr_run "$SR_PLAN"
expect_eq "GM3 the sheet carries it as one ask, its title naming the goal" "decide:goal:fast-landings|Goal missed: fast landings" \
  "$(sr_lines ask | while IFS= read -r l; do sr_f "$l" key; done | sr_join)|$(sr_f "$(sr_ask decide:goal:fast-landings)" title)"
expect_eq "GM3a …a goal missed holds no task, the release or the merge: the ask reads holds=nothing and blocks=no" "nothing|no" \
  "$(sr_f "$(sr_ask decide:goal:fast-landings)" holds)|$(sr_f "$(sr_ask decide:goal:fast-landings)" blocks)"
sed -i.bak 's/one-file median under 15m/one-file median under 30m/' "$SR_PLAN" && rm -f "$SR_PLAN.bak"
printf '# reader test\n\nverdict: pass\n' > "$SR_DIR/reader-test-handoff.md"
sr_ask_ev "key=approve:release|sent=-|title=approval: release|at=2026-10-06T20:00:00Z"
sr_run "$SR_PLAN"
expect_eq "GM3b both goals met while the decision is still open: the sheet drops it and keeps the approval, with nothing on stderr" \
  "approve:release|" "$(sr_lines ask | while IFS= read -r l; do sr_f "$l" key; done | sr_join)|$ERR"
SR_AT=$((SR_NOW + 60)) sr_tick
expect_eq "GM4 the goal now met: the tick closes its open decision, and the item stays on the register closed" "1|0" \
  "$(/usr/bin/grep -c '|key=decide:goal:fast-landings|state=closed|' <(sr_asks))|$(/usr/bin/grep -c '|key=decide:goal:fast-landings|state=open|' <(sr_asks))"

# ============================================================
section "§DECLARED-RED: a goal missed by a red the plan itself declares opens no decide:goal:; any other miss still does"
# ============================================================
# fails-when: the ask opens for a declared red, or a miss the plan did not declare opens none. Three suite goals read red
# from the run's log: one under a debt a Lands-red: row's landing admitted, one with no debt, one whose debt a void
# cancelled. The sheet still reads all three as not met: the red is declared, the goal is not reached.
SR_GOALS="declared · the declared suite stays green (decl.test.sh §A)
plain · the plain suite stays green (plain.test.sh §A)
voided · the voided suite stays green (void.test.sh §A)" SR_APPROVED=none sr_tick_world declared-red "20 20 20 20"
for sr_s in decl plain void; do
  sr_ev "ev=verdict|row=T9|commit=$SR_C1|suite=$sr_s.test.sh|result=red|log=/rec/$sr_s.log|at=2026-10-06T21:00:00Z"
done
sr_ev "ev=admitted|id=7.1|row=T9|branch=wt/02-T9|head=$SR_C1|suite=decl.test.sh|token=ext:fixture|at=2026-10-06T21:00:00Z"
sr_ev "ev=admitted|id=7.2|row=T9|branch=wt/02-T9|head=$SR_C1|suite=void.test.sh|token=ext:fixture|at=2026-10-06T21:00:00Z"
sr_ev "ev=void|id=7.2|branch=wt/02-T9|why=publish-failed|at=2026-10-06T21:30:00Z"
sr_run "$SR_PLAN"
expect_eq "DR0 precondition: the sheet reads all three suite goals not met, each from its red verdict" "declared=not met|plain=not met|voided=not met" "$(sr_goal_st)"
sr_tick
expect_eq "DR1 the tick opens decide:goal: for the plain miss and the voided debt's, and none for the declared red" \
  "decide:goal:plain|decide:goal:voided" "$(/usr/bin/grep -oE '\|key=decide:goal:[^|]*\|state=open\|' <(sr_asks) 2>/dev/null | cut -d'|' -f2 | sed 's/^key=//' | sr_join)"
expect_eq "DR2 …and it says only the two it opened" "2|0" \
  "$(/usr/bin/grep -c '^poker: GOAL .* missed' "$TMPROOT/tick.out")|$(/usr/bin/grep -c '^poker: GOAL declared' "$TMPROOT/tick.out")"

# ============================================================
section "§ONE-FILE: the one-file goal reads the one-file landings only; a landing of more files moves it not"
# ============================================================
SR_FORECAST=200h SR_GOALS="fast landings · one-file median under 5m (landing-report --rows)" sr_world one-file "90 90 10 10"
for sr_i in 1 2; do sr_set "T$sr_i" files "lib/t1.sh, lib/x.sh"; done
sr_run "$SR_PLAN"
expect_eq "OF1 two 90-minute landings of two files and two 10-minute one-file landings: the goal reads 10 min against its 5-minute target" \
  "fast landings=not met|yes" "$(sr_goal_st)|$(sr_goal_m 'fast landings' | /usr/bin/grep -q 'median is 10 min over 2 landings' && echo yes)"

# ============================================================
section "§DECISIONS: a decision put and not ruled is an ask on the sheet, owed once; ruled, it is gone while the reviews stay"
# ============================================================
# FIXTURE FIDELITY: the put and its wait line, and the ruling, in the fields `decisions put` and its ruling write (lib/proof.sh
# `proof_decision_event`).
sr_world decisions "6 6 12 12"
sr_bind
sr_ev "ev=decision|entry=Δ0|d=D19|verb=put|by=orchestrator|title=the regression rule the judge holds|wait=Answered now or in an hour.|at=2026-10-20T13:44:00Z"
sr_reviews
sr_run "$SR_PLAN"
expect_eq "DE1 one put with no ruling: one ask, its number and title, what it holds and when it was put" \
  "decide:D19|D19 · the regression rule the judge holds|nothing|6:44 AM" \
  "$(for f in key title holds raised; do sr_f "$(sr_lines ask)" "$f"; done | sr_join)"
expect_eq "DE1b …holding nothing, it blocks nothing: blocks=no" "no" "$(sr_f "$(sr_lines ask)" blocks)"
sr_run --line "$SR_PLAN"
expect_eq "DE2 …the Patrol's status counts it" "owed: 1" "$(printf '%s\n' "$OUT" | /usr/bin/grep -oE 'owed: [0-9]+')"
# The put's own ask on the register, as `decisions put` opens it, and a held merge naming the decision.
sr_ask_ev "key=decide:D19|sent=-|title=reply to D19|at=2026-10-06T20:30:00Z"
sr_ask_ev "key=hold:merge|sent=-|title=held merge: D19 unruled|at=2026-10-06T21:00:00Z"
sr_run "$SR_PLAN"
expect_eq "DE2b the decision is still one ask, now holding the merge a held merge names it in, raised when its ask was opened" \
  "decide:D19|the merge|1:30 PM|hold:merge" \
  "$(sr_f "$(sr_ask decide:D19)" key)|$(sr_f "$(sr_ask decide:D19)" holds)|$(sr_f "$(sr_ask decide:D19)" raised)|$(sr_f "$(sr_ask hold:merge)" key)"
expect_eq "DE2c …and holding the merge, it blocks: blocks=yes" "yes" "$(sr_f "$(sr_ask decide:D19)" blocks)"
sr_ev "ev=decision|entry=Δ1|d=D19|verb=ruled|said=2|by=Chris Lehman|title=the regression rule the judge holds|at=2026-10-20T14:00:00Z"
sr_run "$SR_PLAN"
expect_eq "DE3 the same decision ruled: no ask for it though its own ask is not yet closed, the held merge still one, both reviews still print" \
  "0|1|2" \
  "$(sr_lines ask | /usr/bin/grep -c 'key=decide:D19 ')|$(sr_lines ask | /usr/bin/grep -c 'key=hold:merge ')|$(sr_lines review | /usr/bin/grep -c .)"

# ============================================================
section "§RECAP: the resume recap carries the run's status line and one line per open ask, from the sheet's own facts"
# ============================================================
# The handoff document in the shape the handoff verb writes its first lines (its kind line, resume point, written,
# plan, working branch), read by the real resume verb. fails-when: the recap lacks the run line, or an open ask.
sr_handoff() {  # -> SR_HF, a handoff document naming this world's plan
  SR_HF="$SR_REPO/.bionic/handoffs/handoff.md"; mkdir -p "${SR_HF%/*}"
  printf 'bionic-handoff/v1\nresume point: Step 4, the build in flight\nwritten: 2026-10-06 2:00 PM PDT\nplan: %s\nworking branch: wave/02-fx\n' \
    "${SR_PLAN#"$SR_REPO"/}" > "$SR_HF"
}
sr_recap() {  # -> RECAP, the recap file the resume verb wrote, after resuming from SR_HF
  sr_poke resume "$SR_HF" > "$TMPROOT/rs.out" 2> "$TMPROOT/rs.err"; RC=$?
  RECAP="$(cat "$SR_DIR/resume-recap.md" 2>/dev/null)"
}
sr_world recap "6 6 12 12"
sr_bind
sr_ledger_put D21 "the gate the judge holds" "$SR_D_WAIT"
sr_reviews
sr_handoff
sr_recap
expect_eq "RC1 resume exits 0 and the recap names the open decision on its open: line, and no open: none" \
  "0|open: D21 — the gate the judge holds: reply with the option number. $SR_D_WAIT|0" \
  "$RC|$(printf '%s\n' "$RECAP" | /usr/bin/grep '^open: D21 ')|$(printf '%s\n' "$RECAP" | /usr/bin/grep -c '^open: none')"
expect_eq "RC2 …the run's status line, and the decision as an ask with what it holds" "yes|ask: D21 · the gate the judge holds — holds nothing" \
  "$(printf '%s\n' "$RECAP" | /usr/bin/grep -qE '^run: 4 of 17 tasks · owed: [0-9]+ on you · [0-9]+ on events · close [0-9]{1,2}:[0-9]{2} [AP]M$' && echo yes)|$(printf '%s\n' "$RECAP" | /usr/bin/grep '^ask: D21 ')"
sr_ev "ev=decision|entry=Δ1|d=D21|verb=ruled|said=1|by=Chris Lehman|title=the gate the judge holds|at=2026-10-06T21:00:00Z"
sr_recap
expect_eq "RC3 the decision ruled: no open: and no ask: line names it while the tick's approvals still read open, and the recap lists it settled" \
  "0|0|2|settled: D21 · \"1\" · Chris Lehman 2026-10-06 · the gate the judge holds" \
  "$(printf '%s\n' "$RECAP" | /usr/bin/grep -c '^open: .*D21')|$(printf '%s\n' "$RECAP" | /usr/bin/grep -c '^ask: .*D21')|$(printf '%s\n' "$RECAP" | /usr/bin/grep -c '^ask: approval: ')|$(printf '%s\n' "$RECAP" | /usr/bin/grep '^settled: D21')"

section "§RESUME-LINES: a resume says each step to the terminal as the step starts, before the step's own lines reach the recap"
# The terminal is appended to the recap's own path, so the terminal's lines and the recap's land in one file in the order
# they were written; the recap the verb keeps is read from a run with the terminal apart. fails-when: a step's line
# comes after its first line, a step goes unsaid, the lines reach the recap, or the lines arrive out of order.
sr_recap
RL_TERM="$(/usr/bin/grep -c '^poker: resume — step: ' "$TMPROOT/rs.out")"
RL_REC="$(printf '%s\n' "$RECAP" | /usr/bin/grep -c 'resume — step: ')"
RL_F="$SR_DIR/resume-recap.md"; : > "$RL_F"; sr_poke resume "$SR_HF" >> "$RL_F" 2>/dev/null
rl_at() { awk -v p="$1" 'index($0, p) == 1 { print NR; exit }' "$RL_F"; }  # <prefix> -> the number of the first line that starts with it
RL_PREV=0; RL_GOT=""; RL_WANT=""; RL_N=0
while IFS=$'\t' read -r RL_NAME RL_PFX; do  # <step> <the first line the step writes to the recap>
  RL_OWN="$(rl_at "$RL_PFX")"; RL_SAID="$(rl_at "poker: resume — step: $RL_NAME")"
  RL_N=$((RL_N + 1)); RL_WANT="$RL_WANT $RL_NAME:said-before"
  if [ -n "$RL_OWN" ] && [ -n "$RL_SAID" ] && [ "$RL_SAID" -lt "$RL_OWN" ] && [ "$RL_SAID" -gt "$RL_PREV" ]; then RL_GOT="$RL_GOT $RL_NAME:said-before"
  else RL_GOT="$RL_GOT $RL_NAME:${RL_SAID:-unsaid}/${RL_OWN:-no-lines}"; fi
  [ -z "$RL_SAID" ] || RL_PREV="$RL_SAID"
done <<EOT
bind	poker: bound
arm	poker: armed
adopt	poker-adopt/v1|
task list	task-list: 0:
recap	settled:
step file	step-file:
patrol	patrol-interval:
tick	poker: sitrep
EOT
expect_eq "RL1 each step's line is on the terminal before its first line in the recap and after the step before it" "$RL_WANT" "$RL_GOT"
expect_eq "RL2 …the terminal got one line a step and the recap the verb keeps got none" "$RL_N|0" "$RL_TERM|$RL_REC"

section "§FOLD: a fold that fails is no fact: the sheet prints none and exits 2, the line and the recap say the status could not be read, and nothing is held"
SR_ST="$TMPROOT/stand"; mkdir -p "$SR_ST/payload/scripts"; cp -R "$BIONIC_HOOKS_DIR" "$SR_ST/hooks"; cp -R "${SR_OWED_LIB%/*}" "$SR_ST/payload/scripts/lib"; echo 'reader_facts() { return 128; }' >> "$SR_ST/payload/scripts/lib/reader.sh"
sr_fd() { printf '%s %s %s' "$RC" "$(printf '%s\n' "$OUT" | grep -cE "$1")" "$(printf '%s\n%s\n' "$OUT" "$ERR" | grep -c 'could not be read')"; }  # <pattern> -> exit, its lines, could-not-read lines
sr_run --line "$SR_PLAN"; SR_F="$(sr_fd '^4 of 17 tasks ')"; POKER="$SR_ST/hooks/session-poker.sh" sr_run --line "$SR_PLAN"
expect_eq "FD1 the reader exiting 128, a refused fork's exit: the line form says the status could not be read and prints no count, exit 2; whole, its count" "0 1 0|2 0 1" "$SR_F|$(sr_fd '^4 of 17 tasks ')"
sr_recap; SR_F="$(OUT="$RECAP" ERR= sr_fd '^run: 4 of 17 tasks ')"; POKER="$SR_ST/hooks/session-poker.sh" sr_recap
expect_eq "FD2 …the resume stops at its bind, the recap naming the run's state that could not be read; whole, the count" "0 1 0|1 0 1|1" \
  "$SR_F|$(OUT="$RECAP" ERR= sr_fd '^run: 4 of 17 tasks ')|$(printf '%s\n' "$RECAP" | grep -c "REFUSED — the run's state could not be read (its facts did not fold)")"
sr_run "$SR_PLAN"; SR_S0="$OUT"; SR_F="$(sr_fd '^run\.step: ')"; POKER="$SR_ST/hooks/session-poker.sh" sr_run "$SR_PLAN"
expect_eq "FD3 …the sheet prints no fact and one line that the run's facts could not be read, exit 2; whole, run.step and exit 0" "0 1 0|2 0 1|" "$SR_F|$(sr_fd '^run\.step: ')|$OUT"
sr_run "$SR_PLAN"; expect_eq "FD4 …and the next sheet, the reader whole, is the whole sheet before it: nothing of the failed fold was held" "$SR_S0" "$OUT"
# ============================================================
section "§ONCE: a decision a row waits on is owed once, not as the tick's approval item and the ledger's decision both"
# ============================================================
# The real tick opens the item for the row's approval read; the real approve verb closes it. fails-when: the sheet
# carries the decision twice, or the recap names it on two lines.
SR_D_ROW="$(sr_row T20 "Decision-gated row · complexity: standard" approval:D21 30 pending)"
sr_tick_world once "6 6 12 12"
awk -v r="$SR_D_ROW" '{ print } /^\| T17 \|/ { print r }' "$SR_PLAN" > "$SR_PLAN.t" && mv "$SR_PLAN.t" "$SR_PLAN"
sr_ledger_put D21 "the gate the judge holds" "Answered in an hour rather than now, T20 starts an hour later and the predicted close holds: it is off the longest chain."
sr_tick
expect_eq "ON0 precondition: the tick says T20 waits on approval:D21 and opens an item for it on the register" "yes|1" \
  "$(/usr/bin/grep -q '^poker: WAIT T20 — approval:D21$' "$TMPROOT/tick.out" && echo yes)|$(/usr/bin/grep -cE '\|key=[a-z]+:D21\|state=open\|' <(sr_asks))"
sr_run "$SR_PLAN"
expect_eq "ON1 the sheet carries the decision once, beside the two approvals the tick opened, holding the row by its card label (step 4, id 20)" \
  "approve:release|approve:merge|decide:D21|4/20" \
  "$(sr_lines ask | while IFS= read -r l; do sr_f "$l" key; done | sr_join)|$(sr_f "$(sr_ask decide:D21)" holds)"
expect_eq "ON2 …and the row waiting on it is held on you" "held|waits on your approval of D21" \
  "$(sr_f "$(sr_task T20)" state)|$(sr_f "$(sr_task T20)" note)"
sr_handoff
sr_recap
expect_eq "ON3 the recap names D21 on one open: line and owes no second approval line for it" "1|0" \
  "$(printf '%s\n' "$RECAP" | /usr/bin/grep -c '^open: .*D21')|$(printf '%s\n' "$RECAP" | /usr/bin/grep -c '^owned-by-user: approval:D21')"
sr_typed 1; sr_poke approve D21 "1" >/dev/null 2>&1
expect_eq "ON4 the approve verb closes the tick's item: nothing for D21 is left open on the register" "0" \
  "$(/usr/bin/grep -cE '\|key=[a-z]+:D21\|state=open\|' <(sr_asks))"

# ============================================================
section "§STEPS: a step past current: with a landed or active task is running; a pending task alone does not make it so"
# ============================================================
# fails-when: a plan at current: 5 with an active step-7 task reads step 7 pending, or a pending one reads it running.
sr_step() { sr_lines step | /usr/bin/grep -E "^step: n=$1 " | while IFS= read -r l; do printf '%s %s\n' "$(sr_f "$l" state)" "$(sr_f "$l" tasks)"; done; }
sr_world title-ahead "6 6 12 12"
sed -i.bak -e 's/^| T7 | 4 | build |/| T7 | 7 | build |/' "$SR_PLAN" && rm -f "$SR_PLAN.bak"; sr_ev "ev=step|n=5|at=2026-10-06T12:00:00Z"
sr_run "$SR_PLAN"
expect_eq "TI1 current: 5 with T7 active at step 7: step 4 done, 5 running, 7 running with its one task, 6 pending" \
  "5|done 16|running 0|pending 0|running 1" "$(sr_val run.step)|$(sr_step 4)|$(sr_step 5)|$(sr_step 6)|$(sr_step 7)"
sr_world title-pending "6 6 12 12"
sed -i.bak -e 's/^| T9 | 4 | build |/| T9 | 7 | build |/' "$SR_PLAN" && rm -f "$SR_PLAN.bak"; sr_ev "ev=step|n=5|at=2026-10-06T12:00:00Z"
sr_run "$SR_PLAN"
expect_eq "TI2 a pending task at step 7 is not work at step 7" "pending 1" "$(sr_step 7)"

# ============================================================
section "§NAMES: every task has one line, its description its title as the plan card prints it, whole; its note says its state in a few words"
# ============================================================
# sr_cell <id> <cell> -> SR_PLAN with that task's description cell replaced, in the Tasks table alone (a row of the
# dispatch ledger names the same id)
sr_cell() { awk -v id=" $1 " -v t="$2" -F'|' 'BEGIN { OFS = "|" } $2 == id && NF > 9 { $5 = " " t " " } { print }' "$SR_PLAN" > "$SR_PLAN.t" && mv "$SR_PLAN.t" "$SR_PLAN"; }
SR_LONG300="$(awk 'BEGIN { for (i = 1; length(s) < 300; i++) s = s (i > 1 ? " " : "") "wordnumber" i; print substr(s, 1, 300) }')"
sr_world names "6 6 12 12"
sr_set T10 deps "T5, T6, T7"
sr_cell T1 "$SR_LONG300"
sr_cell T13 "Alpha one (the aside). And the rest"
sr_cell T14 "Beta two: its colon. And the rest"
sr_cell T15 "Gamma three. And the rest"
sr_cell T16 "Delta four · and the rest"
sr_ev "ev=ready|row=T6|name=w-T6|commit=$SR_C1|branch=wt/02-T6|tree=$SR_REPO/.worktrees/02-T6|suites=a.test.sh|debt=-|carrier=1:x|at=2026-10-06T13:30:00Z"
sr_ev "ev=verdict|row=T7|commit=$SR_C1|suite=a.test.sh|result=red|log=/rec/T7.log|at=2026-10-06T14:00:00Z"
sr_run "$SR_PLAN"
expect_eq "NM1 a 300-character cell with no delimiter is the whole description, on the one line" "yes|1" \
  "$([ "$(sr_f "$(sr_task T1)" desc)" = "$SR_LONG300" ] && echo yes)|$(sr_lines task | /usr/bin/grep -c '^task: id=T1 ')"
expect_eq "NM2 the description is the title: a period ends it before a space and a capital, else the first \" · \" does, keeping a paren or a colon before it, and the rest of the cell never prints" \
  "Alpha one (the aside)|Beta two: its colon|Gamma three|Delta four|0" \
  "$(for t in T13 T14 T15 T16; do sr_f "$(sr_task "$t")" desc; done | sr_join)|$(printf '%s\n' "$OUT" | /usr/bin/grep -ci 'and the rest')"
expect_eq "NM3 the note of each kind: done a time, next on the line, queued behind, building, red, waiting on each of three, waiting on one, none" \
  "T1 landed 3:06 AM|T8 next on the line|T6 queued behind 4/8|T5 building|T7 red|T10 waits on 4/5, 4/6 and 4/7|T9 waits on 4/8|T11 -" \
  "$(for t in T1 T8 T6 T5 T7 T10 T9 T11; do printf '%s %s\n' "$t" "$(sr_f "$(sr_task "$t")" note)"; done | sr_join)"
# a 40-task plan: one line per step and per task
SR_EXTRA=23 sr_world names-forty "6 6 12 12"
sr_run "$SR_PLAN"
expect_eq "NM4 a 40-task plan: ten step lines, forty task lines, every id once" "4 tasks, 120 of 1290 min, 9%|10|40|40" \
  "$(sr_m work.landed)|$(sr_lines step | /usr/bin/grep -c .)|$(sr_lines task | /usr/bin/grep -c .)|$(sr_tasks_f id | sort -u | /usr/bin/grep -c .)"

# ============================================================
section "§HELD-NOTE: a task held on you says what it waits on, whether it is building or not yet started"
# ============================================================
# FIXTURE FIDELITY: the decisions put in the fields `decisions put` writes into the run's log, the world's plan
# bound by the bind verb. fails-when: a task that has started and reads an approval still owed says building.
sr_world heldnote "6 6 12 12"
sr_bind
sr_ev "ev=decision|entry=Δ0|d=D1|verb=put|by=orchestrator|title=the stop rule|wait=Answered now or in an hour.|at=2026-10-20T13:44:00Z"
sr_ev "ev=decision|entry=Δ1|d=D2|verb=put|by=orchestrator|title=the second rule|wait=Answered now or in an hour.|at=2026-10-20T13:45:00Z"
awk -v a="$(sr_row T5 "Row 5 body · complexity: standard" approval:D1 30 active)" -v b="$(sr_row T6 "Row 6 body · complexity: standard" "approval:D1, approval:D2" 30 active)" \
  '/^\| T5 \|/ { print a; next } /^\| T6 \|/ { print b; next } { print }' "$SR_PLAN" > "$SR_PLAN.t" && mv "$SR_PLAN.t" "$SR_PLAN"
sr_run "$SR_PLAN"
expect_eq "HN1 precondition: both decisions are owed on the sheet" "decide:D1|decide:D2" \
  "$(sr_lines ask | while IFS= read -r l; do sr_f "$l" key; done | sr_join)"
expect_eq "HN2 a started task reading an approval still owed is held, and its note names the approval, not building" \
  "held|waits on your approval of D1" "$(sr_f "$(sr_task T5)" state)|$(sr_f "$(sr_task T5)" note)"
expect_eq "HN2b …reading two, it names both" "held|waits on your approval of D1 and your approval of D2" \
  "$(sr_f "$(sr_task T6)" state)|$(sr_f "$(sr_task T6)" note)"
expect_eq "HN2c …a started task reading nothing owed is still running and building (HN2 read the same sheet)" "running|building" \
  "$(sr_f "$(sr_task T7)" state)|$(sr_f "$(sr_task T7)" note)"

# ============================================================
section "§HELD-15: a nine-cell row at 15 waits on an approval through its deps, and the sheet reads that wait as it reads a reads cell's"
# ============================================================
# FIXTURE FIDELITY: §HELD-NOTE's world, its plan replaced by plan_fixture's page at 15 (nine cells, each wait in its deps,
# the launch in the log), the decision put and the asks in the fields their verbs write. fails-when: a launched row
# waiting on an owed decision reads running; an open approval's ask holds nothing; an approval's minutes go uncounted.
sr_world held15 "6 6 12 12"
plan_fixture "$SR_PLAN" wave "| T1 | 4 | build | the held build | implementor | approval:D7 | — | 30 | REQ-1 | lib/a.sh | — | — | active |" \
  "| T2 | 8 | integrate | the merge, held on the release | — | approval:release | — | 30 | REQ-1 | — | — | — | pending |" \
  "| T3 | 4 | build | waits on the design | — | approval:design | — | 30 | REQ-1 | lib/c.sh | — | — | pending |" > /dev/null
sr_bind
sr_ev "ev=decision|entry=Δ0|d=D7|verb=put|by=orchestrator|title=the rule|wait=Answered now or in an hour.|at=2026-10-06T12:00:00Z"
sr_ask_ev "key=approve:design|sent=-|title=approval: design|at=2026-10-06T13:00:00Z"; sr_ask_ev "key=approve:design|reply=approve|at=2026-10-06T14:00:00Z"
sr_ask_ev "key=approve:release|sent=-|title=approval: release|at=2026-10-06T13:30:00Z"
sr_run "$SR_PLAN"
expect_eq "H15-1 a launched row waiting on D7 through its deps is held, its note naming the approval" "held|waits on your approval of D7" \
  "$(sr_f "$(sr_task T1)" state)|$(sr_f "$(sr_task T1)" note)"
expect_eq "H15-2 …the release approval's ask holds the integrate task that waits on it, by its label, and blocks" "8/2|yes" \
  "$(sr_f "$(sr_ask approve:release)" holds)|$(sr_f "$(sr_ask approve:release)" blocks)"
expect_eq "H15-3 …and the minutes waiting on you count the decision and both approvals, each overlap once" \
  "600 min: decide:D7, approve:design and approve:release" \
  "$(sr_m waste.waiting-on-you)"

# ============================================================
section "§SCORECARD: the scorecard's last three lines are the sheet's pace, correctness and waste; its landing target is LINE_LANDING_BAR in lib/line.sh"
# ============================================================
SR_FORECAST=240h SR_EXTRA=22 sr_world scorecard "6 6 12 12"
SR_AT=$((SR_NOW - 3600)) sr_run "$SR_PLAN"
SR_SC="$(SR_AT=$((SR_NOW - 3600)) sr_poke landing-report --scorecard "$SR_PLAN" 2>/dev/null)"
expect_eq "SCO1 the scorecard's widest landing prints against target < 15, the landing bar" \
  "widest landing ready→landed: T3 12.0 min · target < 15" "$(printf '%s\n' "$SR_SC" | /usr/bin/grep '^widest landing ')"
expect_eq "SCO2 …and its last three lines are the sheet's pace, correctness and waste measurements, seven lines in all" \
  "pace: $(sr_m pace.work-landed) of the live work's sized minutes landed, in $(sr_m pace.time-used) of the forecast time|correctness: suites run $(sr_m tests.suites-run); whole run $(sr_m tests.whole-run); reviews $(sr_m reviews); $(sr_m findings.open) open findings|waste: dropped $(sr_m waste.dropped); $(sr_m waste.runs-discarded) suite runs discarded; $(sr_m waste.ready-unstarted) ready and unstarted; $(sr_m waste.waiting-on-you) waiting on you|7" \
  "$(printf '%s\n' "$SR_SC" | tail -3 | sr_join)|$(printf '%s\n' "$SR_SC" | /usr/bin/grep -c .)"
printf 'run/v1|ev=approval|key=merge|by=fixture|said=1|at=2026-10-06T14:00:00Z\n' >> "$SR_DIR/run.log"; sr_launch T9 14:04:30
expect_eq "SCO4 a merge approved in the log alone, no state line, starts the agent minutes: a launch 4.5 min after it reads 5" \
  "agent minutes after the final reply: 5 · target 0" "$(SR_AT=$((SR_NOW - 3600)) sr_poke landing-report --scorecard "$SR_PLAN" 2>/dev/null | /usr/bin/grep '^agent minutes ')"
# One constant: a mutant tree whose lib/line.sh sets the bar to 25 moves the scorecard's target.
SR_MUT="$TMPROOT/mut"; mkdir -p "$SR_MUT/payload"
cp -R "$BIONIC_HOOKS_DIR" "$SR_MUT/hooks" && cp -R "$BIONIC_HOOKS_DIR/../payload/scripts" "$SR_MUT/payload/scripts"
sed 's/^LINE_LANDING_BAR=15$/LINE_LANDING_BAR=25/' "$BIONIC_HOOKS_DIR/../payload/scripts/lib/line.sh" > "$SR_MUT/payload/scripts/lib/line.sh"
sr_world bar-plant-mut "20 20 20 20"
SR_MUT_SC="$(sr_poke_with "$SR_MUT/hooks/session-poker.sh" landing-report --scorecard "$SR_PLAN")"
expect_eq "SCO3 a mutant bar of 25 moves the scorecard's target" \
  "widest landing ready→landed: T1 20.0 min · target < 25" "$(printf '%s\n' "$SR_MUT_SC" | /usr/bin/grep '^widest landing ')"

# ============================================================
section "§ROUNDS: the scorecard's stops and wait are the register's rounds put after the plan's approval, every round counted"
# ============================================================
# A stop is a step card, release card or decision round opened after approved-by:, open or closed, whoever closed it;
# the wait sums those rounds' at= less opened= (now for an open one); `approve plan` closes the Step-3 card's ask at its
# own instant. Built with the verbs at the clock seam; the two cards' asks opened through lib/owed.sh as their openers do.
# fails-when: the numbers come from approved: lines or release pages, a re-put counts once, or a round before the
# approval counts (RD-1); an open round counts no wait (RD-2); the approval leaves the Step-3 ask open (RD-0).
SR_RLIB="${BIONIC_HOOKS_DIR}/../payload/scripts/lib"
sr_r_open() {  # <epoch> <key> -> the ask opened on this world's register at that instant, as its card opens it
  BIONIC_NOW_EPOCH="$1" OWED_ROOT="$SR_REPO" OWED_SID="$SID" OWED_PLAN="$SR_PLAN" \
    bash -c '. "$1/run.sh" && . "$1/owed.sh" && owed_open "$2" "approval: $2" "Reply approved."' _ "$SR_RLIB" "$2"
}
sr_r_put() { SR_AT="$1" sr_poke decisions put "$2" "the decision $2" >/dev/null 2>&1; }   # <epoch> <D<n>>
sr_r_rule() { SR_AT="$1" sr_poke decisions rule "$2" 1 >/dev/null 2>&1; }   # <epoch> <D<n>>: the verb's ruling closes the ask at <epoch>
sr_r_card() {  # <epoch> -> the scorecard's two human lines at that instant, joined
  SR_AT="$1" sr_poke landing-report --scorecard "$SR_PLAN" 2>/dev/null | /usr/bin/grep -E '^human( stops|-wait)' | sr_join
}
sr_r_want() { printf 'human stops (autonomous half): %s · target 1|human-wait minutes: %s · no target (the user'"'"'s)' "$1" "$2"; }
SR_APPROVED=none sr_world rounds "6 6 12 12"   # approved below, at SR_E0, 2026-10-06T10:00:00Z
git -C "$SR_REPO" config user.name "Dana Fixture"; sr_bind
SR_T="$CLAUDE_CONFIG_DIR/projects/$(cd "$SR_REPO" && pwd -P | sed 's/[^a-zA-Z0-9]/-/g')/$SID.jsonl"; mkdir -p "${SR_T%/*}"; : > "$SR_REPO/.bionic/tmp/loaded-$SID.state"
jq -nc '{type:"user",isSidechain:false,userType:"external",message:{role:"user",content:"carry on"}}' > "$SR_T"; sr_typed approved 1   # the session the ruling verb and the approvals read
sr_r_open $((SR_E0 - 10800)) approve:step3
sr_r_put $((SR_E0 - 7200)) D9; sr_r_rule $((SR_E0 - 5400)) D9; sr_r_put $((SR_E0 - 3600)) D9; sr_r_rule $((SR_E0 - 1800)) D9   # before
SR_AT=$SR_E0 sr_poke approve plan 'approved' >/dev/null 2>&1
expect_eq "RD-0 precondition: approve plan appended its approval at 10:00Z and closed the Step-3 card's ask at that instant" \
  "key=step3|by=Dana Fixture|2026-10-06T10:00:00Z|2026-10-06T10:00:00Z" \
  "$(sed -n 's/^run\/v1|ev=approval|\(key=step3|by=[^|]*\)|.*|at=\([^|]*\)$/\1|\2/p' "$SR_DIR/run.log")|$(sed -n 's/^run\/v1|ev=ask|key=approve:step3|state=closed|by=[^|]*|at=\([^|]*\)|.*/\1/p' <(sr_asks))"
sr_r_put $((SR_E0 + 600)) D1;    sr_r_rule $((SR_E0 + 1200)) D1     # 10 min
sr_r_put $((SR_E0 + 3600)) D2;   sr_r_rule $((SR_E0 + 5400)) D2     # 30 min
sr_r_put $((SR_E0 + 7200)) D2;   sr_r_rule $((SR_E0 + 8100)) D2     # 15 min, the same decision put again
sr_r_put $((SR_E0 + 48960)) D3;  sr_r_rule $((SR_E0 + 77520)) D3    # 23:36Z to 07:32Z, 476 min
sr_r_open $((SR_E0 + 79200)) approve:release
SR_AT=$((SR_E0 + 79500)) sr_poke approve release '1' >/dev/null 2>&1   # 5 min
expect_eq "RD-1 two rounds of D9 before the approval count none; after it four decision rounds and the release card: 5 stops, 10 + 30 + 15 + 476 + 5 minutes" \
  "2|2|0|$(sr_r_want 5 536)" \
  "$(/usr/bin/grep -c '|key=decide:D9|state=closed|' <(sr_asks) | tr -d ' ')|$(/usr/bin/grep -c '|key=decide:D2|state=closed|' <(sr_asks) | tr -d ' ')|$(/usr/bin/grep -c '|state=open|' <(sr_asks) | tr -d ' ')|$(sr_r_card $((SR_E0 + 82800)))"
sr_r_put $((SR_E0 + 81000)) D4
expect_eq "RD-2 a round still open is a stop, its wait running to now" "$(sr_r_want 6 566)" "$(sr_r_card $((SR_E0 + 82800)))"

# ============================================================
section "§WAIT: a decision's wait line names everything that waits on it: a row not landed or dropped that reads it, the release its newest approval page lists it on, the merge an open held-merge ask names it in"
# ============================================================
# FIXTURE FIDELITY: the world's plan bound by the bind verb, the put through the real `decisions put`, the held merge
# opened on the run's register through lib/owed.sh as close-out opens it, and the release approval page's replay
# line in the shape plan.sh `rr_record` writes. fails-when: a held merge naming D<n> leaves the put's wait line
# saying nothing waits, as a run's put once did while its merge waited on that decision.
SR_WLIB="${BIONIC_HOOKS_DIR}/../payload/scripts/lib"
sr_wait() {  # <D<n>> -> the wait: line the put prints, its label stripped
  sr_poke decisions put "$1" "the decision $1" 2>&1 | sed -n 's/^wait: //p'
}
sr_hold() {  # <title> -> hold:merge open on this world's register, as a refused close-out opens it
  OWED_ROOT="$SR_REPO" OWED_SID="$SID" OWED_PLAN="$SR_PLAN" bash -c '. "$1/run.sh" && . "$1/owed.sh" && owed_open hold:merge "$2" "bionic: close-out refused — $2"' \
    _ "$SR_WLIB" "$1"
}
sr_world wait "6 6 12 12"
sr_bind
SR_W_NONE="Answered now or in an hour, nothing moves: no task waits on it."
expect_eq "WA-0 nothing reads D31 and nothing names it: nothing moves" "$SR_W_NONE" "$(sr_wait D31)"
sr_hold "the commit gate refuses the merge until D30 is ruled"
expect_eq "WA-1 an open held merge naming D30: the put's wait line names the merge, and the close moves" \
  "Answered in an hour rather than now, the predicted close moves an hour later: the merge waits on it." "$(sr_wait D30)"
expect_eq "WA-1b …a held merge naming D30 does not name D3 (WA-0 read the same line)" "$SR_W_NONE" "$(sr_wait D3)"
SR_W_ROW="$(sr_row T20 "Decision-gated row · complexity: standard" approval:D32 30 held)"
awk -v r="$SR_W_ROW" '{ print } /^\| T17 \|/ { print r }' "$SR_PLAN" > "$SR_PLAN.t" && mv "$SR_PLAN.t" "$SR_PLAN"
expect_eq "WA-2 a row held, not pending, that reads approval:D32 waits on it" \
  "Answered in an hour rather than now, T20 starts an hour later and the predicted close holds: it is off the longest chain." \
  "$(sr_wait D32)"
sr_state T20 landed
expect_eq "WA-2b …landed, it waits on nothing" "$SR_W_NONE" "$(sr_wait D32)"
printf 'Release approval\n\n## Replay\n\nrelease-approval/v1|plan=%s|head=%s|at=2026-10-06T21:00:00Z|decisions=1\nrelease-approval/v1|dec=1|key=approve:D33|default=approve D33|other=-|pick=default|choices=approve/hold|why=-\n' \
  "$SR_PLAN" "$SR_H" > "$SR_DIR/release-approval-${SR_H:0:8}.md"
expect_eq "WA-3 the newest release approval page lists D33: the release waits on it" \
  "Answered in an hour rather than now, the predicted close moves an hour later: the release waits on it." "$(sr_wait D33)"
sr_hold "the commit gate refuses the merge until D30 is ruled"
printf 'release-approval/v1|dec=2|key=approve:D30|default=approve D30|other=-|pick=default|choices=approve/hold|why=-\n' \
  >> "$SR_DIR/release-approval-${SR_H:0:8}.md"
expect_eq "WA-4 the release and the merge both wait on D30" \
  "Answered in an hour rather than now, the predicted close moves an hour later: the release and the merge wait on it." "$(sr_wait D30)"

# ============================================================
section "§ONE-BLOCKS: the sheet, the handoff head and the Patrol line read the one function, so what blocks the user reads the same on all three"
# ============================================================
# FIXTURE FIDELITY: the asks are lines on the run's register, written as lib/owed.sh writes them; a waiver the user
# turned back is answered `no` by owed_answer itself, the call the release reply makes; the waiver holds an integrate
# row, so the old rule (blocked when something is held) would read it as blocking. The three surfaces are the real
# verbs: `sitrep` for the sheet, `handoff` for the head, `sitrep --line` for the Patrol's status.
# fails-when: a waiver answered `no` reads blocks=yes, the head says Blocked on you: yes over asks that all wait on an
# event, the Patrol counts an event-waiting ask as owed by the user, or any two surfaces read the same asks differently.
sr_ob_world() {  # <label> <with approval: yes|no> -> an integrate row held by a waiver answered no, and optionally an approval the user owes
  sr_world "$1" "6 6 12 12"
  sr_set T17 kind integrate
  sr_bind
  sr_ask_ev "key=waive:adversarial|sent=-|title=waiver: adversarial|at=2026-10-06T20:01:00Z"
  ( cd "$SR_REPO" && OWED_ROOT="$SR_REPO" OWED_SID="$SID" OWED_PLAN="$SR_PLAN" bash -c '. "$1" && owed_answer "$2" no "$3"' _ "$SR_OWED_LIB" waive:adversarial "review adversarial re-run" )
  [ "$2" != yes ] || sr_ask_ev "key=approve:release|sent=-|title=approval: release|at=2026-10-06T20:00:00Z"
}
sr_ob_read() {  # <poker> -> `<sheet blocks=yes>|<sheet waits=user>|<sheet waits=event>|<head word>|<Patrol on you>|<Patrol on events>`
  local pk="$1" sheet line head f
  sheet="$(sr_poke_with "$pk" sitrep "$SR_PLAN" 2>/dev/null)"
  line="$(sr_poke_with "$pk" sitrep --line "$SR_PLAN" 2>/dev/null)"
  rm -rf "$SR_REPO/.bionic/docs/record/handoffs"
  sr_poke_with "$pk" handoff < /dev/null > /dev/null 2>&1
  f="$(ls "$SR_REPO"/.bionic/docs/record/handoffs/*.md 2>/dev/null | head -n 1)"
  head="$(awk -F': ' '$1 == "Blocked on you" { print $2; exit }' "$f" 2>/dev/null)"
  printf '%s|%s|%s|%s|%s|%s\n' \
    "$(printf '%s\n' "$sheet" | /usr/bin/grep -c '^ask: .* blocks=yes waits=')" \
    "$(printf '%s\n' "$sheet" | /usr/bin/grep -c '^ask: .* waits=user$')" \
    "$(printf '%s\n' "$sheet" | /usr/bin/grep -c '^ask: .* waits=event ')" \
    "$head" \
    "$(printf '%s\n' "$line" | sed -n 's/.* owed: \([0-9]*\) on you .*/\1/p')" \
    "$(printf '%s\n' "$line" | sed -n 's/.* on you · \([0-9]*\) on events .*/\1/p')"
}
sr_ob_agree() {  # <read> -> agree when the head says yes exactly when the sheet has a blocking ask, no ask blocks that does not wait on the user, and the Patrol counts the sheet's asks by what they wait on
  awk -F'|' '{ ok = (($1 > 0) == ($4 == "yes")) && $1 <= $2 && $5 == $2 && $6 == $3 && $4 != ""; print ok ? "agree" : "disagree" }' <<< "$1"
}
sr_ob_world one-blocks-a no
SR_OB_A="$(sr_ob_read "$POKER")"
expect_eq "OB1 only a waiver answered no, waiting on its review: no ask blocks the user — the sheet reads blocks=no and waits=event, the head says no, the Patrol counts it on events" \
  "0|0|1|no|0|1" "$SR_OB_A"
SR_OB_AL="$(sr_poke_with "$POKER" sitrep "$SR_PLAN" 2>/dev/null | /usr/bin/grep '^ask: key=waive:adversarial ')"
expect_eq "OB1b …that ask holds the integrate row and still blocks=no, its waits= naming the event (OB1 counted it; the held row is why the old rule read yes)" \
  "4/17|no|event review adversarial re-run" "$(sr_f "$SR_OB_AL" holds)|$(sr_f "$SR_OB_AL" blocks)|$(sr_f "$SR_OB_AL" waits)"
sr_ob_world one-blocks-b yes
SR_OB_B="$(sr_ob_read "$POKER")"
expect_eq "OB2 the approval the user owes beside it: one ask blocks — the sheet reads one blocks=yes and one waits=user, the head says yes, the Patrol counts one on you and one on events" \
  "1|1|1|yes|1|1" "$SR_OB_B"
expect_eq "OB3 the three surfaces agree in both worlds" "agree|agree" "$(sr_ob_agree "$SR_OB_A")|$(sr_ob_agree "$SR_OB_B")"
expect_eq "OB3b the agreement reader returns a disagreement for a planted split (it is not a constant)" "disagree|disagree" \
  "$(sr_ob_agree '0|0|1|yes|0|1')|$(sr_ob_agree '1|0|1|yes|0|1')"
expect_eq "OB3c …and returns agree for the two worlds' own reads (OB3 read the same reader)" "agree|agree" "$(sr_ob_agree '0|0|1|no|0|1')|$(sr_ob_agree '1|1|1|yes|1|1')"
# THE PLANTS: a copy of the tree with one reader put back to its own rule; the surfaces then read the same register apart.
SR_OBM="$TMPROOT/ob-mut"; mkdir -p "$SR_OBM/payload"
cp -R "$BIONIC_HOOKS_DIR" "$SR_OBM/hooks" && cp -R "$BIONIC_HOOKS_DIR/../payload/scripts" "$SR_OBM/payload/scripts"
SR_OBM_F="$SR_OBM/hooks/poker/sitrep.sh"; SR_OBM_ORIG="$TMPROOT/ob-sitrep.orig"; cp "$SR_OBM_F" "$SR_OBM_ORIG"
sr_ob_plant() {  # <sed script> -> the copy's sitrep.sh is the shipped one with that edit; rc 1 when the edit changed nothing
  sed "$1" "$SR_OBM_ORIG" > "$SR_OBM_F"; ! cmp -s "$SR_OBM_ORIG" "$SR_OBM_F"
}
sr_ob_world one-blocks-p no
expect_eq "OB4 precondition: the shipped tree on this world still agrees (the plants below start from agreement)" "0|0|1|no|0|1|agree" \
  "$(sr_ob_read "$POKER")|$(sr_ob_agree "$(sr_ob_read "$POKER")")"
sr_ob_plant 's/"\$HO_BLOCKED"/"$([ -n "$HO_ASKS" ] \&\& echo yes || echo no)"/'; SR_PL1=$?
expect_eq "OB5 the head put back to say yes over any open ask: it says yes while the sheet blocks nothing, and the row reddens" "0|disagree" \
  "$SR_PL1|$(sr_ob_agree "$(sr_ob_read "$SR_OBM/hooks/session-poker.sh")")"
sr_ob_plant 's/index(\$5, "event ") == 1/0/'; SR_PL2=$?
expect_eq "OB6 the Patrol put back to count every ask as owed by the user: it counts the waiver on you, and the row reddens" "0|disagree" \
  "$SR_PL2|$(sr_ob_agree "$(sr_ob_read "$SR_OBM/hooks/session-poker.sh")")"
sr_ob_plant 's/\[ "\$w" = user \]/true/'; SR_PL3=$?
expect_eq "OB7 the sheet put back to block on what an ask holds alone: the waiver blocks=yes while it waits on an event, and the row reddens" "0|disagree" \
  "$SR_PL3|$(sr_ob_agree "$(sr_ob_read "$SR_OBM/hooks/session-poker.sh")")"
# THE CARD HAS NO RULE OF ITS OWN: it reads the sheet's blocks= and waits= fields and decides nothing from holds= (comment lines aside).
expect_eq "OB8 the card draws from the sheet's fields: no line of card.sh outside its comments names a blocks= rule" "0" \
  "$(/usr/bin/grep -v '^[[:space:]]*#' "$BIONIC_HOOKS_DIR/../payload/scripts/card.sh" | /usr/bin/grep -c 'nothing.*blocks\|blocks=')"
SR_OB_CARD="$(/usr/bin/grep -v '^[[:space:]]*#' "$BIONIC_HOOKS_DIR/../payload/scripts/card.sh")"
expect_eq "OB8b the card keeps the sheet's blocks field as the one function wrote it: one line stores it" "1" \
  "$(printf '%s\n' "$SR_OB_CARD" | /usr/bin/grep -c 'SR_ABLOCK\[\${#SR_ABLOCK\[@\]}\]="\$b"')"
expect_eq "OB8c …and no line before it decides blocks again from what the ask waits on (OB8b read the same lines)" "0" \
  "$(printf '%s\n' "$SR_OB_CARD" | /usr/bin/grep -c 'event\*) b=')"

# ============================================================
section "§FAST: the sheet verb and the card verb, run one after the other on a run of 35 tasks with four finding asks open; the card verb reads the saved sheet and refreshes its asks from the register alone"
# ============================================================
# FIXTURE FIDELITY: this suite's world at the size of a shipped run, 35 tasks, its log holding four finding asks open and
# a release approval asked and answered, in a repository of its own because the verbs write the repository's tmp folder
# and settle its register. The card verb is
# run with a judgment on its stdin that the card refuses, since drawing is card.sh's and its judgment is not this
# section's subject; the verb's own work is what is read. A second tree has card.sh replaced by a stub that keeps the sheet it was
# handed, and sitrep_gather counted, so the sheet the card draws from is read and the one gather is proved.
# fails-when: the card verb gathers a second time, or the sheet the card
# draws from carries the asks as they stood when the sheet was saved rather than as they stand now.
SR_EXTRA=18 sr_world fast "6 6 12 12"
for sr_k in critic-evidence.md:3 critic-evidence.md:4 critic-adversarial.md:1 critic-adversarial.md:3; do
  sr_ask_ev "key=finding:record:wave-02-fx:$sr_k|sent=-|title=Finding S2 needs a ruling|at=2026-10-06T20:00:00Z"
done
sr_ask_ev "key=approve:release|sent=-|title=approval: release|at=2026-10-06T19:00:00Z"; sr_ask_ev "key=approve:release|reply=approve|at=2026-10-06T19:30:00Z"
expect_eq "FA0 precondition: the world's plan holds 35 tasks and its log four finding asks" "35|4" \
  "$(/usr/bin/grep -c '^| T[0-9]' "$SR_PLAN")|$(/usr/bin/grep -c '|ev=ask|key=finding:' "$SR_REC")"
SR_FAST_AT="$SR_NOW"
SR_FAST_J="$TMPROOT/fast-judgment.txt"; printf 'call: Nothing is owed.\n' > "$SR_FAST_J"
SR_AT="$SR_FAST_AT" sr_run "$SR_PLAN"
SR_FA_RC1="$RC"; SR_FA_SHEET="$OUT"
SR_AT="$SR_FAST_AT" sr_run card "$SR_PLAN" < "$SR_FAST_J"
SR_FA_RC2="$RC"; SR_FA_ERR2="$ERR"
expect_eq "FA1 the sheet verb prints the sheet (rc 0, a first line, the wave's own open asks among them)" "0|$SR_HEAD|yes" \
  "$SR_FA_RC1|$(printf '%s\n' "$SR_FA_SHEET" | head -1)|$(printf '%s\n' "$SR_FA_SHEET" | /usr/bin/grep -q '^ask: key=finding:' && echo yes)"
expect_eq "FA2 the card verb read the saved sheet and ran the check: it refused the judgment (rc 1), and said nothing of a sheet that is missing or old" "1|0" \
  "$SR_FA_RC2|$(printf '%s\n' "$SR_FA_ERR2" | /usr/bin/grep -c 'the sheet you wrote from')"
# the stub tree: card.sh keeps the sheet it was handed; sitrep_gather counts its calls
SR_FM="$TMPROOT/fast-mut"; mkdir -p "$SR_FM/payload"
cp -R "$BIONIC_HOOKS_DIR" "$SR_FM/hooks" && cp -R "$BIONIC_HOOKS_DIR/../payload/scripts" "$SR_FM/payload/scripts"
sed 's|^sitrep_gather() {$|sitrep_gather() { [ -z "${SR_GATHER_MARK:-}" ] \|\| echo gather >> "$SR_GATHER_MARK";|' "$BIONIC_HOOKS_DIR/poker/sitrep.sh" > "$SR_FM/hooks/poker/sitrep.sh"
printf '#!/bin/bash\ncat "$2" > "$SR_CARD_KEPT"\necho drawn\n' > "$SR_FM/payload/scripts/card.sh"
# and the kept fold counts its entries, so a sheet that reads its findings by folding again is seen
SR_FA_LIB="$BIONIC_HOOKS_DIR/../payload/scripts/lib/proof.sh"
sed 's|^_proof_facts() {|_proof_facts() { [ -z "${SR_FOLD_MARK:-}" ] \|\| echo fold >> "$SR_FOLD_MARK";|' "$SR_FA_LIB" > "$SR_FM/payload/scripts/lib/proof.sh"
expect_eq "FA4 precondition: the counting plants took effect (each shipped file and its plant differ)" "yes|yes" \
  "$(cmp -s "$BIONIC_HOOKS_DIR/poker/sitrep.sh" "$SR_FM/hooks/poker/sitrep.sh" || echo yes)|$(cmp -s "$SR_FA_LIB" "$SR_FM/payload/scripts/lib/proof.sh" || echo yes)"
SR_FA_MARK="$TMPROOT/fast-gathers"; SR_FA_KEPT="$TMPROOT/fast-kept"; : > "$SR_FA_MARK"
export SR_GATHER_MARK="$SR_FA_MARK" SR_CARD_KEPT="$SR_FA_KEPT" SR_FOLD_MARK="$TMPROOT/fast-folds"
SR_AT="$SR_FAST_AT" sr_poke_with "$SR_FM/hooks/session-poker.sh" sitrep "$SR_PLAN" > "$TMPROOT/fast-sheet2.out" 2>/dev/null
SR_FA_G1="$(/usr/bin/grep -c gather "$SR_FA_MARK")"; SR_FA_F1="$(/usr/bin/grep -c fold "$SR_FOLD_MARK")"; unset SR_FOLD_MARK
expect_eq "FA4b the sheet verb enters the kept fold at least once and at most twice: its findings are answered from the fold its own shell holds" "yes" \
  "$([ "$SR_FA_F1" -ge 1 ] && [ "$SR_FA_F1" -le 2 ] && echo yes || echo "no: $SR_FA_F1 entries")"
# an ask opened after the sheet was saved, and one answered no; neither is in the saved sheet
sr_ask_ev "key=approve:release|round=2|sent=-|title=approval: release|prompt=poker: WAIT T12 — approval:release|at=2026-10-06T21:50:00Z"
SR_AT="$SR_FAST_AT" sr_poke_with "$SR_FM/hooks/session-poker.sh" sitrep card "$SR_PLAN" < "$SR_FAST_J" > "$TMPROOT/fast-card.out" 2>"$TMPROOT/fast-card.err"
SR_FA_RC3=$?
SR_FA_G2="$(/usr/bin/grep -c gather "$SR_FA_MARK")"
unset SR_GATHER_MARK SR_CARD_KEPT
expect_eq "FA5 the sheet verb gathers (at least once), the card verb after it gathers not at all, and the card is drawn from the stub (rc 0)" "yes|0|0" \
  "$([ "$SR_FA_G1" -ge 1 ] && echo yes)|$((SR_FA_G2 - SR_FA_G1))|$SR_FA_RC3"
expect_eq "FA6 the sheet the card draws from keeps every line of the saved sheet but its asks (the saved sheet read through the same extractor is not empty)" "yes|0" \
  "$([ "$(awk 'index($0, "ask: ") != 1' "$TMPROOT/fast-sheet2.out" | /usr/bin/grep -c .)" -gt 20 ] && echo yes)|$(diff <(awk 'index($0, "ask: ") != 1' "$TMPROOT/fast-sheet2.out") <(awk 'index($0, "ask: ") != 1' "$SR_FA_KEPT") | /usr/bin/grep -c '^[<>]')"
expect_eq "FA7 …and its ask lines are the register as it stands: the approval opened after the sheet was saved is there, with waits=user, the finding asks beside it each ending in a waits= field" "yes|yes|0" \
  "$(/usr/bin/grep -q '^ask: key=approve:release .* waits=user$' "$SR_FA_KEPT" && echo yes)|$([ "$(/usr/bin/grep -c '^ask: key=finding:.* waits=' "$SR_FA_KEPT")" -ge 1 ] && echo yes)|$(/usr/bin/grep '^ask: ' "$SR_FA_KEPT" | /usr/bin/grep -vc ' waits=')"
expect_eq "FA7b …and the saved sheet did not have the approval (so FA7 read a refresh)" "0" "$(/usr/bin/grep -c '^ask: key=approve:release ' "$TMPROOT/fast-sheet2.out")"

# ============================================================
section "§RECORD: the sitrep and canonical-sdlc skills record an ask through its verb before they put it to the user"
# ============================================================
# FIXTURE FIDELITY: the shipped skill texts read in place, the canonical-sdlc skill as rendered and as its source; the
# plant is a scratch copy with the verb cut from the line.
# fails-when: a skill puts an ask to the user with no recording verb named.
sr_put_lines() {  # <skill file> -> every line that puts something to the user, in chat or otherwise
  awk '{ l = tolower($0) } l ~ /(^|[^a-z])put(s|ting)?[^.]*(to the user|in chat)/ { print }' "$1"
}
sr_put_bad() {  # <skill file> -> each such line that names no recording verb before the put
  sr_put_lines "$1" | awk 'index($0, "`decisions put") == 0 || tolower($0) !~ /before/ { print }'
}
for sr_f in "$BIONIC_SKILLS_DIR/sitrep/SKILL.md" "$BIONIC_SKILLS_DIR/canonical-sdlc/SKILL.md" \
  "$BIONIC_SCRIPTS_DIR/agents-src/templates/skills/canonical-sdlc/SKILL.md.tmpl"; do
  sr_rel="${sr_f#"$BIONIC_SCRIPTS_DIR"/}"
  expect_nonempty "RC1 $sr_rel puts an ask to the user (the extractor reads the real text)" "$(sr_put_lines "$sr_f")"
  expect_empty "RC2 $sr_rel names the recording verb, decisions put, before every put (RC1 read the same lines)" "$(sr_put_bad "$sr_f")"
  sed 's/`decisions put[^`]*`/the decision skill/' "$sr_f" > "$TMPROOT/record-plant.md"
  expect_nonempty "RC3 $sr_rel with the verb cut from its put line is found" "$(sr_put_bad "$TMPROOT/record-plant.md")"
done


finish
