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
# HERMETIC. One repository per world under a temp root: a 17-task plan, its landing record, its fill
# ledger, the run's register of asks and a gate store of its own. The clock is BIONIC_NOW_EPOCH
# (the poker's seam, fill-report's too) and the zone is pinned, so every local time below is a fixed
# string; no case reads this machine's clock. The machine's probes are pinned as the session-poker
# prelude pins them, because the gate's scan samples them.
#
# FIXTURE FIDELITY. SYNTHESIZED, in the shapes the writers write: the landing record's `line/v1`
# events as lib/line.sh writes them, the fill ledger's `fill-ledger/v1` lines as lib/stop.sh writes
# them, the register's `owed/v1` lines as lib/owed.sh writes them (one line per key) at the path
# lib/owed.sh `owed_register` resolves, the gate's request files as lib/gate.sh writes them, a
# session's binding through the bind verb itself, the review lines in the shape `proof-add review`
# writes them, and a `## Tasks` header in the shipped table shape. What each world pins is what the
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
# sr_world <label> <landing minutes for T1..T4, space-separated | none> -> SR_REPO, SR_PLAN, SR_REC,
# SR_DIR, SR_GATE. Seventeen rows, all Step 4 builds: T1–T4 landed (30 min each), T5–T8 active, T9–T17 pending. T9 reads lib/t8.sh, which T8 writes, so the remaining
# chain is T8→T9 (90 + 60 = 150 min); every other open row is 30 min and reads nothing of another's.
# T12 reads approval:release and T17 approval:merge. With `none`, T1–T4 are pending too and the
# landing record holds no landing. Two gate requests are admitted and held by this shell, so the
# gate's admitted count is 2.
# THE CLOCK (wave-39 T9; D25): the plan is approved at 10:00Z (its `approved-by:` instant, 12 hours before
# NOW; SR_APPROVED=none leaves the line out, an unapproved plan) and declares `forecast: $SR_FORECAST` (48h when
# unset; an empty SR_FORECAST declares none). SR_EXTRA
# appends that many more pending 30-minute rows (T18…), reading nothing, so the plan's total grows and the
# chain does not. SR_SCALE, when set, declares `scale:`.
# THE LANDING RECORD: each landed row has a `landed: row=…` header at its landing instant, as the landing writes it,
# beside the queue's `published` event. The plan has no dispatch ledger, as the live plan has none.
sr_world() {
  local label="$1" mins="$2" r d p
  r="$TMPROOT/$label"; mkdir -p "$r/.bionic/tmp" "$r/.bionic/docs/plans/epic-01-fx"
  ( cd "$r" && git init -q . 2>/dev/null )
  d="$r/.bionic/docs/record/wave-02-fx"; mkdir -p "$d"
  p="$r/.bionic/docs/plans/epic-01-fx/wave-02-fx.plan.md"
  SR_REPO="$r"; SR_PLAN="$p"; SR_DIR="$d"; SR_REC="$d/landing-proofs.log"; : > "$SR_REC"
  local st1=landed land=yes
  [ "$mins" = none ] && { st1=pending; land=no; }
  {
    printf -- '---\nwave: wave-02-fx\nrelease: 9.9.0\nworking-branch: wave/02-fx\nintegration-branch: main\n'
    [ -z "${SR_SCALE:-}" ] || printf 'scale: %s\n' "$SR_SCALE"
    [ -z "${SR_FORECAST-48h}" ] || printf 'forecast: %s\n' "${SR_FORECAST-48h}"
    [ -z "${SR_GOALS:-}" ] || printf '%s\n' "$SR_GOALS" | sed 's/^/goals: /'
    printf -- '---\n'
    printf '# fixture plan\n\n## SDLC State\n\n'
    [ "${SR_APPROVED-}" = none ] || printf 'approved-by: fixture 2026-10-06T10:00:00Z "approved"\n'
    printf 'current: 4\n\n'
    printf -- '- Step 4: implementation opened\n'
  } > "$p"
  local i at
  if [ "$land" = yes ]; then
    set -- $mins
    local readies="10:00:00 10:30:00 11:00:00 12:00:00" rd e
    i=1
    for rd in $readies; do
      e=$(( SR_E0 + $(sr_hms "$rd") + ${!i} * 60 ))
      at="$(sr_iso "$e")"
      printf -- '- T%d: landed %s %s — .worktrees/02-T%d\n' "$i" "$SR_C1" "$at" "$i" >> "$p"
      sr_ev "ev=ready|row=T$i|name=w-T$i|commit=$SR_C1|branch=wt/02-T$i|tree=$r/.worktrees/02-T$i|suites=a.test.sh|debt=-|carrier=1:x|at=2026-10-06T${rd}Z"
      sr_ev "ev=verdict|row=T$i|commit=$SR_C1|suite=a.test.sh|result=green|log=/rec/T$i.log|at=$(sr_iso $((e - 60)))"
      sr_ev "ev=published|row=T$i|commit=$SR_C1|kind=queue|by=-|why=-|at=$at"
      printf 'landed: row=T%d branch=wt/02-T%d head=%s merge=%s at=%s\n' "$i" "$i" "$SR_C1" "$SR_C1" "$at" >> "$SR_REC"
      i=$((i + 1))
    done
  fi
  sr_ev "ev=ready|row=T8|name=w-T8|commit=$SR_C1|branch=wt/02-T8|tree=$r/.worktrees/02-T8|suites=a.test.sh|debt=-|carrier=1:x|at=2026-10-06T13:00:00Z"
  {
    printf '\n## Tasks\n\n'
    printf '| id | step | kind | task | agent | deps | reads | size | serves | Files | worktree | base | status | suites | lands-on | artifact |\n'
    printf '|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|\n'
    sr_row T1 "Row one the thing (D1; AC-1.1). More words · complexity: standard" — 30 "$st1"
    sr_row T2 "Haiku 5.5 at high (REQ-8; AC-8.1) · complexity: standard" — 30 "$st1"
    sr_row T3 "Third row. A second sentence · complexity: standard" — 30 "$st1"
    sr_row T4 "Fourth · complexity: complex" — 30 "$st1"
    for i in 5 6 7; do sr_row "T$i" "Row $i body · complexity: standard" — 30 active; done
    sr_row T8 "The long one (D8) · complexity: complex" — 90 active
    sr_row T9 "Waits on the long one · complexity: standard" lib/t8.sh 60 pending
    for i in 10 11 13 14 15 16; do sr_row "T$i" "Row $i body · complexity: standard" — 30 pending; done
    sr_row T12 "Release-gated row · complexity: standard" approval:release 30 pending
    sr_row T17 "Merge-gated row · complexity: standard" approval:merge 30 pending
    i=18; while [ "$i" -le $((17 + ${SR_EXTRA:-0})) ]; do sr_row "T$i" "Row $i body · complexity: standard" — 30 pending; i=$((i + 1)); done
    printf '\n## Not Doing\n\n- nothing\n'
  } >> "$p"
  # The fill ledger: two turns, nothing idle, the first at 10:00Z (elapsed 720 min at NOW).
  printf 'fill-ledger/v1|at=2026-10-06T10:00:00Z|session=%s|turn=t1|current=4|state=ok|ceiling=|width=4|open=0|free=4|ready=|launched=|declined=|missed=0|idle=|room=4\n' "$SID" > "$d/fill-ledger.log"
  printf 'fill-ledger/v1|at=2026-10-06T16:00:00Z|session=%s|turn=t2|current=4|state=ok|ceiling=|width=4|open=4|free=0|ready=|launched=|declined=|missed=0|idle=|room=0\n' "$SID" >> "$d/fill-ledger.log"
  SR_GATE="$TMPROOT/gate-$label"; mkdir -p "$SR_GATE/requests" "$SR_GATE/cost"
  for i in 1 2; do
    printf 'key=a.test.sh\nkind=landing\nwho=%s:w-T%d\ntree=/elsewhere/project\nasked=%d\nholder=%s:\nadmitted=%d\npromise=5:0.1:30\n' \
      "$SID" "$((i + 4))" "$((SR_NOW - 600))" "$$" "$((SR_NOW - 590))" > "$SR_GATE/requests/$i"
  done
}
sr_iso() { date -u -r "$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ; }
sr_hms() { local h="${1%%:*}" r="${1#*:}"; printf '%d' $(( 10#$h * 3600 + 10#${r%%:*} * 60 + 10#${r#*:} - 36000 )); }
sr_ev() { printf 'line/v1|%s\n' "$1" >> "$SR_REC"; }
sr_row() {  # <id> <task> <reads> <size> <status>
  local n="${1#T}"
  printf '| %s | 4 | build | %s | — | — | %s | %s | REQ-1 | lib/t%s.sh | — | — | %s | — | — | — |\n' "$1" "$2" "$3" "$4" "$n" "$5"
}
# sr_reg [<plan>] -> the run's register of asks at the path lib/owed.sh `owed_register` resolves for the plan, so a
# seeded ask lands where every reader of the run reads it (this world's plan by default).
SR_OWED_LIB="${BIONIC_HOOKS_DIR}/../payload/scripts/lib/owed.sh"
sr_reg() { bash -c '. "$1" && owed_register "$2" "$3"' _ "$SR_OWED_LIB" "$SR_REPO" "${1:-$SR_PLAN}"; }
sr_owed() {  # <owed/v1 fields after the schema> [<plan>] -> one line on that run's register (this world's own by default)
  local f; f="$(sr_reg "${2:-$SR_PLAN}")" || return 1
  mkdir -p "${f%/*}"; printf 'owed/v1|%s\n' "$1" >> "$f"
}
sr_owed_sid() {  # <owed/v1 fields after the schema> <session> -> one line in the store of a session acting for no run
  printf 'owed/v1|%s\n' "$1" >> "$SR_REPO/.bionic/tmp/owed-$2.state"
}
# sr_prev <minutes> [<scale>] -> a delivered plan beside this one (T1 of 60 min declared,
# declaring `scale: <scale>` when given) approved at 10:00Z the day before, whose T1 lands <minutes>
# later: the previous wave's measured ratio is <minutes> / 60. Its queue time is 1 minute, so a pace read
# from the queue would be 1/60.
sr_prev() {
  local p="$SR_REPO/.bionic/docs/plans/epic-01-fx/wave-40-prev.plan.md" d="$SR_REPO/.bionic/docs/record/wave-40-prev"
  local land=$((SR_E0 - 86400 + $1 * 60))
  mkdir -p "$d"
  {
    printf -- '---\nwave: wave-40-prev\nrelease: 9.8.0\n%s---\n# prev\n\n## SDLC State\n\napproved-by: fixture 2026-10-05T10:00:00Z "approved"\ncurrent: 9\n\n' "${2:+scale: $2$'\n'}"
    printf -- '- Step 9: delivered: 2026-10-05T20:00Z wave-40-prev 9.8.0 — closed by close-out.sh\n'
    printf '\n## Tasks\n\n| id | step | kind | task | agent | deps | reads | size | serves | Files | worktree | base | status | suites | lands-on | artifact |\n'
    printf '|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|\n'
    printf '| T1 | 4 | build | Prev row · complexity: standard | — | — | — | 60 | REQ-1 | lib/p1.sh | — | — | landed | — | — | — |\n'
  } > "$p"
  {
    printf 'line/v1|ev=ready|row=T1|name=p-T1|commit=%s|branch=wt/01-T1|tree=%s/.worktrees/01-T1|suites=a.test.sh|debt=-|carrier=1:x|at=%s\n' "$SR_C1" "$SR_REPO" "$(sr_iso $((land - 60)))"
    printf 'line/v1|ev=published|row=T1|commit=%s|kind=queue|by=-|why=-|at=%s\n' "$SR_C1" "$(sr_iso "$land")"
    printf 'landed: row=T1 branch=wt/01-T1 head=%s merge=%s at=%s\n' "$SR_C1" "$SR_C1" "$(sr_iso "$land")"
  } > "$d/landing-proofs.log"
}
sr_run() {  # <args after the verb…> -> OUT (stdout), ERR (stderr), RC; the world's plan is named last by the caller
  ( cd "$SR_REPO" && exec env CLAUDE_CODE_SESSION_ID="${SR_SID:-$SID}" BIONIC_NOW_EPOCH="${SR_AT:-$SR_NOW}" BIONIC_GATE_DIR="$SR_GATE" \
      bash "$POKER" sitrep "$@" ) > "$TMPROOT/sr.out" 2> "$TMPROOT/sr.err"
  RC=$?
  OUT="$(cat "$TMPROOT/sr.out")"; ERR="$(cat "$TMPROOT/sr.err")"
}
sr_poke() { sr_poke_with "$POKER" "$@"; }
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
SR_ORDER="run.release|run.name|run.wave|run.now|run.step|run.project|run.started|run.last-landing|step|task|clock.now|clock.approved|clock.forecast|clock.elapsed|clock.elapsed-share|work.planned|work.added|work.dropped|work.landed|work.left|work.width|work.task-time|pace.time-used|pace.work-landed|close.chain|close.predicted|close.unscaled|close.waits-on-you|tests.suites-run|tests.suites-total|tests.whole-run|reviews|findings.open|waste.dropped|waste.runs-discarded|waste.ready-unstarted|waste.waiting-on-you|goal|ask|review"
# sr_m <key> -> the measurement alone, the value before its ` — `; sr_d <key> -> what follows it
sr_m() { sr_val "$1" | awk '{ i = index($0, " — "); print (i ? substr($0, 1, i - 1) : $0) }'; }
sr_d() { sr_val "$1" | awk '{ i = index($0, " — "); print (i ? substr($0, i + 5) : "") }'; }
# sr_correct -> the correctness measurements joined; sr_waste -> dropped, discarded and ready-unstarted joined
sr_correct() { for k in tests.suites-run tests.whole-run reviews findings.open; do sr_m "$k"; done | sr_join; }
sr_waste() { for k in waste.dropped waste.runs-discarded waste.ready-unstarted; do sr_m "$k"; done | sr_join; }

# ---------- the world that holds every fact kind ----------
#
# sr_sheet_world -> the world moved so it holds one of each fact: T7 red at head (failed), T11 held, T13 a
# review row in flight, T16 dropped, one discarded suite run, a 72-minute idle turn, a review of the whole failing
# with one open S2 finding and a review of a piece passing, three goals (one met, one not met, one not measured),
# five asks of five kinds open on the register beside one closed, and a decision put and not ruled.
SR_D_WAIT="Answered now or in an hour, nothing moves: no task waits on it."
sr_ledger_put() {  # <D<n>> <title> <wait line> -> the run's design ledger holds one put of it, nothing ruled
  printf '# Design ledger — wave-02-fx\n\n## Δ0 — %s put (orchestrator 2026-10-06 1:30 PM PDT): %s\n\n%s\n' "$1" "$2" "$3" > "$SR_DIR/design-ledger.md"
}
sr_close_ask() {  # <key> [<plan>] -> the ask closed by lib/owed.sh's own closer on that run's register
  ( cd "$SR_REPO" && OWED_ROOT="$SR_REPO" OWED_SID="$SID" OWED_PLAN="${2:-$SR_PLAN}" bash -c '. "$1" && owed_close "$2" fixture' _ "$SR_OWED_LIB" "$1" )
}
sr_reviews() {  # -> two reviews landed on the plan: evidence on the whole failing, adversarial on a piece passing
  awk -v h="$SR_H" '{ print } /^current: [0-9]+$/ {
    print "proved: kind=review head=" h " at=2026-10-06T20:00:00Z evidence=record/wave-02-fx/auditor-evidence.md question=evidence reader=w-T20 result=fail scope=whole"
    print "proved: kind=review head=" h " at=2026-10-06T20:05:00Z evidence=record/wave-02-fx/critic-adversarial.md question=adversarial reader=w-T21 result=pass scope=piece" }' \
    "$SR_PLAN" > "$SR_PLAN.t" && mv "$SR_PLAN.t" "$SR_PLAN"
}
sr_sheet_world() {
  SR_GOALS="fast landings · one-file median under 15m (landing-report --rows)
tests · whole run under 45 min at the approved head (the Step-5 run log)
handoff · a fresh session continues a no-run handoff (record/reader-test-handoff.md)" sr_world "$1" "6 6 12 12"
  awk -F'|' 'BEGIN { OFS = "|" }
    $2 == " T11 " && NF > 12 { $14 = " held " }
    $2 == " T13 " && NF > 12 { $4 = " review "; $14 = " active " }
    $2 == " T16 " && NF > 12 { $14 = " dropped " }
    { print }' "$SR_PLAN" > "$SR_PLAN.t" && mv "$SR_PLAN.t" "$SR_PLAN"
  sr_ev "ev=verdict|row=T7|commit=$SR_C1|suite=a.test.sh|result=red|log=/rec/T7.log|at=2026-10-06T14:00:00Z"
  sr_ev "ev=verdict|row=T8|commit=$SR_C1|suite=a.test.sh|result=discarded|log=/rec/T8.log|at=2026-10-06T14:10:00Z"
  printf 'fill-ledger/v1|at=2026-10-06T16:00:00Z|session=%s|turn=t2|current=4|state=ok|ceiling=|width=4|open=3|free=1|ready=T9|launched=|declined=|missed=1|idle=T9|room=1\n' "$SID" >> "$SR_DIR/fill-ledger.log"
  printf 'fill-ledger/v1|at=2026-10-06T17:12:00Z|session=%s|turn=t3|current=4|state=ok|ceiling=|width=4|open=4|free=0|ready=|launched=T9|declined=|missed=0|idle=|room=0\n' "$SID" >> "$SR_DIR/fill-ledger.log"
  printf 'reviewed: %s..%s\nfindings: 1\nfinding: 1 S2 on lib/t1.sh:3 the thing breaks\nshown: 1 bash tests/x.test.sh\n' "$SR_C1" "$SR_H" > "$SR_DIR/auditor-evidence.md"
  printf 'reviewed: %s..%s\nfindings: 0\n' "$SR_C1" "$SR_H" > "$SR_DIR/critic-adversarial.md"
  sr_reviews
  printf 'Gating: 9 passed, 0 failed\nWall: 3000s · work 9000s · width 4\n' > "$SR_DIR/regression-run-$SR_H.log"
  awk -v h="$SR_H" '{ print } /^current: 4$/ { print "proved: kind=regression head=" h " at=2026-10-06T20:00:00Z evidence=record/wave-02-fx/regression-run-" h ".log" }' "$SR_PLAN" > "$SR_PLAN.t" && mv "$SR_PLAN.t" "$SR_PLAN"
  sr_owed "key=approve:release|state=open|sent=-|at=2026-10-06T20:00:00Z|title=approval: release|reply=poker: WAIT T12 — approval:release"
  sr_owed "key=waive:adversarial|state=open|sent=-|at=2026-10-06T20:01:00Z|title=waiver: adversarial|reply=poker: the adversarial review failed at the head"
  sr_owed "key=row:AC-1.2|state=open|sent=-|at=2026-10-06T20:02:00Z|title=ruling: row AC-1.2|reply=poker: AC-1.2 is not proved — rule it"
  sr_owed "key=ruling:r1|state=open|sent=-|at=2026-10-06T20:03:00Z|title=ruling unread: F1|reply=poker: a ruling waits to be read"
  sr_owed "key=gate:abc|state=open|sent=-|at=2026-10-06T20:04:00Z|title=gate act: merge|reply=poker: GATE T17 — merge: approve it"
  sr_owed "key=approve:merge|state=open|sent=-|at=2026-10-06T20:05:00Z|title=approval: merge|reply=poker: WAIT T17 — approval:merge"
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
  "4|done|landed 3:06 AM|failed|red|held|held|held|waits on your approval of the release|running|pending|waits on 4/8|pending|-" \
  "$(sr_f "$(sr_task T1)" step)|$(sr_f "$(sr_task T1)" state)|$(sr_f "$(sr_task T1)" note)|$(sr_f "$(sr_task T7)" state)|$(sr_f "$(sr_task T7)" note)|$(sr_f "$(sr_task T11)" state)|$(sr_f "$(sr_task T11)" note)|$(sr_f "$(sr_task T12)" state)|$(sr_f "$(sr_task T12)" note)|$(sr_f "$(sr_task T13)" state)|$(sr_f "$(sr_task T9)" state)|$(sr_f "$(sr_task T9)" note)|$(sr_f "$(sr_task T10)" state)|$(sr_f "$(sr_task T10)" note)"
expect_eq "SH8 each task's title, the plan card's: the cell up to its first '. ', else up to its first ' · '" \
  "Row one the thing (D1; AC-1.1)|Haiku 5.5 at high (REQ-8; AC-8.1)|Third row|The long one (D8)" \
  "$(for t in T1 T2 T3 T8; do sr_f "$(sr_task "$t")" desc; done | sr_join)"
expect_eq "SH9 the measurements in numbers: landed, pace, correctness and waste; no metric line" \
  "4 tasks, 120 of 570 min, 21%|25%|21%|1: 0 green, 1 red|green at aaaaaaaa|1 passed, 1 failed, 1 running|1|1 task, 30 min|1 of 6|72 min|0" \
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
  awk -F'|' 'BEGIN { OFS = "|" } $2 == " T16 " && NF > 12 { $14 = " dropped " } { print }' "$SR_PLAN" > "$SR_PLAN.t" && mv "$SR_PLAN.t" "$SR_PLAN"
  awk '{ print } /^- Step 4: / { print "- T17: pending dispatch — added by task-add at 2026-10-06T09:00:00Z"
                                 print "- T18: pending dispatch — added by task-add at 2026-10-06T12:00:00Z" }' "$SR_PLAN" > "$SR_PLAN.t" && mv "$SR_PLAN.t" "$SR_PLAN"
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
sr_owed "key=approve:release|state=open|sent=-|at=2026-10-06T20:00:00Z|title=approval: release|reply=poker: WAIT T12 — approval:release"
sr_run "$SR_PLAN"
expect_eq "PC7 an ask holding 4/12, off the chain: the prediction waits on no answer" "no" "$(sr_m close.waits-on-you)"
awk -F'|' 'BEGIN { OFS = "|" } $2 == " T9 " { $8 = " lib/t8.sh, approval:design " } { print }' "$SR_PLAN" > "$SR_PLAN.t" && mv "$SR_PLAN.t" "$SR_PLAN"
sr_owed "key=approve:design|state=open|sent=-|at=2026-10-06T20:00:00Z|title=approval: design|reply=poker: WAIT T9 — approval:design"
sr_run "$SR_PLAN"
expect_eq "PC8 an ask holding 4/9, on the chain: the prediction assumes it is answered now, and names it" "yes: approve:design" \
  "$(sr_m close.waits-on-you)"

# ============================================================
# The close counts what is running and scales by kind. The world: T1 to T4 landed, each 100 sized min and launched 6 min
# before its landing, so the landed build tasks' own time is 24 min over 400 sized min, a ratio of 0.06 that any build
# row left pending is scaled by; every other row is landed, and a test opens the rows it reads. A row's reads is set
# to approval:plan, met, so no default read (head, the proofs) joins it to another row. Now is 3:00 PM.
sr_set() {  # <id> <kind|reads|size|status> <value> -> that cell of the row, in this world's plan
  awk -F'|' -v id=" $1 " -v k="$2" -v v=" $3 " 'BEGIN { OFS = "|"; c["kind"] = 4; c["reads"] = 8; c["size"] = 9; c["status"] = 14 }
    $2 == id && NF > 12 { i = c[k]; $i = v } { print }' "$SR_PLAN" > "$SR_PLAN.t" && mv "$SR_PLAN.t" "$SR_PLAN"
}
sr_open() {  # <id> <kind> <size> <status> [<reads>] -> the row opened as that kind, size and status, reading approval:plan
  sr_set "$1" kind "$2"; sr_set "$1" size "$3"; sr_set "$1" status "$4"; sr_set "$1" reads "${5:-approval:plan}"
}
sr_close_world() {  # <label> -> the world above
  local i
  sr_world "$1" "5 5 5 5"
  for i in 1 2 3 4; do sr_set "T$i" size 100; done
  sr_launch T1 09:59:00; sr_launch T2 10:29:00; sr_launch T3 10:59:00; sr_launch T4 11:59:00
  for i in 5 6 7 8 9 10 11 12 13 14 15 16 17; do sr_set "T$i" status landed; done
}

# ============================================================
section "§CLOSE-RUNNING: the predicted close counts a running row off the chain at its size less its elapsed, floored at its cadence"
# ============================================================
# fails-when: a sheet with a running 90-minute row five minutes in, off the chain, predicts a close before that row's
# remaining time, a running row past its size counts nothing, or the roster's cadence is not the floor.
sr_close_world close-running
sr_open T5 verify 90 active
sr_open T6 build 30 pending; sr_open T7 build 30 pending lib/t6.sh
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
sr_open T6 build 30 pending; sr_open T7 build 30 pending lib/t6.sh
sr_launch T5 20:00:00
sr_run "$SR_PLAN"
expect_eq "CR3 a running row past its size has a cadence left, 15 min when its roster row names none" "3:15 PM" "$(sr_m close.predicted)"
sr_close_world close-running-cad
sr_open T5 verify 90 active
sr_open T6 build 30 pending; sr_open T7 build 30 pending lib/t6.sh
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
sr_owed "key=approve:design|state=open|sent=-|at=2026-10-06T20:00:00Z|title=approval: design|reply=poker: WAIT T5 — approval:design"
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
sr_open T5 verify 60 pending lib/t9.sh
sr_run "$SR_PLAN"
expect_eq "UP4 a verify row that reads what the integrate row writes keeps that order: no cycle, the chain 4/9 then 4/5" \
  "0|4/9 → 4/5, 90 min" "$RC|$(sr_m close.chain)"

# ============================================================
section "§WASTE: correctness and waste as measurements; the minutes a task waited on you, overlaps counted once"
# ============================================================
# fails-when: a count is not the record's, a closed ask's minutes are lost, an overlap counts twice, or a decision with
# no opened time is not read from the design ledger.
sr_mw_world waste
mkdir -p "$SR_REPO/tests"; : > "$SR_REPO/tests/a.test.sh"; : > "$SR_REPO/tests/b.test.sh"
sr_run "$SR_PLAN"
expect_eq "WS1 correctness: the suites run by their last verdict, the suites the project has, the whole run, the reviews, the open findings" \
  "1: 1 green, 0 red|2|not run yet|0 passed, 0 failed, 0 running|0" \
  "$(for k in tests.suites-run tests.suites-total tests.whole-run reviews findings.open; do sr_m "$k"; done | sr_join)"
expect_eq "WS2 waste: dropped, suite runs discarded, ready tasks unstarted, minutes waiting on you" "1 task, 30 min|0 of 4|0 min|0 min" \
  "$(for k in waste.dropped waste.runs-discarded waste.ready-unstarted waste.waiting-on-you; do sr_m "$k"; done | sr_join)"
# T9 reads approval:design, asked 13:00Z and closed 14:00Z: 60 minutes. approve:other held nothing: no minute.
awk -F'|' 'BEGIN { OFS = "|" } $2 == " T9 " { $8 = " lib/t8.sh, approval:design " } { print }' "$SR_PLAN" > "$SR_PLAN.t" && mv "$SR_PLAN.t" "$SR_PLAN"
sr_owed "key=approve:design|state=closed|by=approve|at=2026-10-06T14:00:00Z|opened=2026-10-06T13:00:00Z"
sr_owed "key=approve:other|state=closed|by=approve|at=2026-10-06T11:00:00Z|opened=2026-10-06T10:00:00Z"
sr_run "$SR_PLAN"
expect_eq "WS3 a closed ask that held a task counts from opened to closed; one that held nothing counts no minute" \
  "60 min: approve:design" "$(sr_m waste.waiting-on-you)"
# approve:release, holding T12, open since 13:30Z: 13:00Z to now, 540 min, the half hour both were open counted once.
sr_owed "key=approve:release|state=open|sent=-|at=2026-10-06T13:30:00Z|title=approval: release|reply=poker: WAIT T12 — approval:release"
sr_run "$SR_PLAN"
expect_eq "WS4 an open ask counts from its raising to now, an overlap once" "540 min: approve:design and approve:release" \
  "$(sr_m waste.waiting-on-you)"
# A decision closed with no opened time: its first put in the design ledger, 1:30 PM PDT, to its close at 2:00 PM.
sr_mw_world waste-ledger
awk -F'|' 'BEGIN { OFS = "|" } $2 == " T10 " { $8 = " approval:D5 " } { print }' "$SR_PLAN" > "$SR_PLAN.t" && mv "$SR_PLAN.t" "$SR_PLAN"
printf '# Design ledger — wave-02-fx\n\n## Δ1 — D5 put (orchestrator 2026-10-06 1:30 PM PDT): the thing\n\n%s\n\n## Δ2 — D5 put (orchestrator 2026-10-06 1:45 PM PDT): the thing again\n\n%s\n\n## Δ3 — D5 ruled "1" (fixture 2026-10-06 2:00 PM PDT): the thing\n' \
  "$SR_D_WAIT" "$SR_D_WAIT" > "$SR_DIR/design-ledger.md"
sr_owed "key=decide:D5|state=closed|by=ruled|at=2026-10-06T21:00:00Z"
sr_run "$SR_PLAN"
expect_eq "WS5 a decision with no opened time: from its first put in the design ledger to its close" "30 min: decide:D5" "$(sr_m waste.waiting-on-you)"
rm -f "$(sr_reg)"
sr_run "$SR_PLAN"
expect_eq "WS6 …and with no line on the register, to the ruling's own time in the ledger" "30 min: decide:D5" "$(sr_m waste.waiting-on-you)"

# ============================================================
section "§ONE-PARSER: one reader of the design ledger's headings, one rule for what rules a decision, settled among its verbs"
# ============================================================
# fails-when: a ledger whose only ruling of D<n> is a `settled` heading is open to one reader and ruled to the other, a
# ruling the ledger writes as a bullet is no ruling to the clock reader, or a second program parses a ledger heading.
sr_world one-parser "6 6 12 12"
awk -F'|' 'BEGIN { OFS = "|" } $2 == " T10 " { $8 = " approval:D5 " } { print }' "$SR_PLAN" > "$SR_PLAN.t" && mv "$SR_PLAN.t" "$SR_PLAN"
sr_bind
printf '# Design ledger — wave-02-fx\n\n## Δ1 — D5 put (orchestrator 2026-10-06 1:30 PM PDT): the thing\n\n%s\n\n## Δ2 — D5 settled "1" (fixture 2026-10-06 2:00 PM PDT): the thing\n' \
  "$SR_D_WAIT" > "$SR_DIR/design-ledger.md"
sr_owed "key=decide:D5|state=closed|by=ruled|at=2026-10-06T21:00:00Z"
sr_run "$SR_PLAN"
expect_eq "OP1 a decision whose only ruling is a settled heading is ruled to the register's reader: the decisions verb prints it" \
  'D5 · settled "1" · fixture 2026-10-06 · the thing' "$(sr_poke decisions 2>&1)"
expect_eq "OP1b …and to the clock reader: from its put to the ruling's own clock, 30 minutes" "30 min: decide:D5" "$(sr_m waste.waiting-on-you)"
expect_eq "OP1c …and open to neither: the sheet owes no ask for it" "0" "$(sr_lines ask | /usr/bin/grep -c 'key=decide:D5 ')"
# A ruling the ledger writes as a bullet under a Δ is a ruling to the clock reader too: with no register line, the
# bullet's clock ends the span.
printf '# Design ledger — wave-02-fx\n\n## Δ1 — D5 put (orchestrator 2026-10-06 1:30 PM PDT): the thing\n\n%s\n\n## Δ2 — steps folded\n\n- D5 ruled "1" (fixture 2026-10-06 2:00 PM PDT): the thing\n' \
  "$SR_D_WAIT" > "$SR_DIR/design-ledger.md"
rm -f "$(sr_reg)"
sr_run "$SR_PLAN"
expect_eq "OP2 a bullet ruling ends the span at its own clock, as a heading's does" "30 min: decide:D5" "$(sr_m waste.waiting-on-you)"
# The static row: the code recognises a ledger heading (`## Δn — `) in one program. The control plants the same line
# twice, and once beside a comment that names the shape, through the same counter.
op_count() { /usr/bin/grep -vE '^[[:space:]]*#' "$1" | /usr/bin/grep -cE 'Δ\[0-9\]\+ — '; }
OP_P="$TMPROOT/op-plant.sh"
printf '%s\n' "# a comment naming Δ[0-9]+ — is no parser" "  index(\$0, 1) { sub(/^## Δ[0-9]+ — /, \"\") }" > "$OP_P"
expect_eq "OP3a (control) the counter finds one parser in a file with one, and passes a comment by" "1" "$(op_count "$OP_P")"
printf '%s\n' "  \$0 ~ /^## Δ[0-9]+ — D[0-9]+ / { next }" >> "$OP_P"
expect_eq "OP3b (control) …and two in a file with a second" "2" "$(op_count "$OP_P")"
expect_eq "OP3 the sheet's code holds one heading parser of the design ledger" "1" "$(op_count "${BIONIC_HOOKS_DIR}/poker/sitrep.sh")"

# ============================================================
section "§SPAN: an ask closed with no opened= takes its span from the run's record, or the count says it is partial"
# ============================================================
# fails-when: a closed waiver with no opened= adds no minute though the plan holds its span, the opened= it has is
# passed over for the record, a carry, which waits on the release card and never on you, counts its span, or an ask
# the record cannot time leaves the count unmarked.
sr_mw_world span
awk '/^\| T17 / { print; print "| T18 | 8 | integrate | Merge row · complexity: standard | — | — | — | 10 | REQ-1 | lib/t18.sh | — | — | pending | — | — | — |"; next } { print }' \
  "$SR_PLAN" > "$SR_PLAN.t" && mv "$SR_PLAN.t" "$SR_PLAN"
SP_REC="record/wave-02-fx/critic-structure.md"
awk -v h="$SR_H" -v rec="$SP_REC" '{ print } /^current: 4$/ {
  print "proved: kind=review head=" h " at=2026-10-06T12:00:00Z evidence=" rec " question=structure reader=w-T2 result=flag scope=whole"
  print "deferred: " rec "#2 S2 on \"a thing\""
  print "proved: kind=review head=" h " at=2026-10-06T13:00:00Z evidence=record/wave-02-fx/critic-evidence.md question=evidence reader=w-T1 result=fail scope=whole"
  print "waived: question=evidence head=" h " by Chris Lehman 2026-10-06T14:00:00Z \"waive it\"" }' \
  "$SR_PLAN" > "$SR_PLAN.t" && mv "$SR_PLAN.t" "$SR_PLAN"
SP_CARRY="carry:record:wave-02-fx:critic-structure.md:2"
sr_owed "key=waive:evidence|state=closed|by=waive|at=2026-10-06T14:00:00Z"
sr_run "$SR_PLAN"
expect_eq "SP1 a closed waiver with no opened=: from the review's fail line to the waived: line, 60 minutes, nothing partial" \
  "60 min: waive:evidence" "$(sr_m waste.waiting-on-you)"
rm -f "$(sr_reg)"
sr_owed "key=waive:evidence|state=closed|by=waive|at=2026-10-06T14:00:00Z|opened=2026-10-06T13:30:00Z"
sr_run "$SR_PLAN"
expect_eq "SP2 (control) the same waiver with opened= present uses it: 30 minutes" "30 min: waive:evidence" "$(sr_m waste.waiting-on-you)"
rm -f "$(sr_reg)"
sr_owed "key=$SP_CARRY|state=closed|by=ruled|at=2026-10-06T14:00:00Z"
sr_run "$SR_PLAN"
expect_eq "SP3 a closed carry waits on the release card, an event, never on you: it counts no minute and is no ask left untimed (SP1 timed the waiver through the same reader)" \
  "0 min" "$(sr_m waste.waiting-on-you)"
rm -f "$(sr_reg)"
sr_owed "key=finding:record:wave-02-fx:nowhere.md:1|state=closed|by=ruled|at=2026-10-06T14:00:00Z"
sr_run "$SR_PLAN"
expect_eq "SP4 a closed ask the record holds no span for: the count is marked partial and says how many asks it could not time" \
  "0 min partial, 1 ask not timed" "$(sr_m waste.waiting-on-you)"
sr_owed "key=waive:evidence|state=closed|by=waive|at=2026-10-06T14:00:00Z"
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
awk -F'|' 'BEGIN { OFS = "|" } $2 == " T5 " && NF > 12 { $8 = " approval:release, approval:D4 " } { print }
  /^\| T17 / {
    print "| T18 | 8 | integrate | Merge row · complexity: standard | — | — | proof:review, head, approval:release, lib/t8.sh, approval:D4 | 10 | REQ-1 | lib/t18.sh | — | — | pending | — | — | — |"
    print "| T19 | 9 | close | Close · complexity: standard | — | — | — | 10 | REQ-1 | .bionic/docs/record/wave-02-fx/close.md | — | — | pending | — | — | — |" }' \
  "$SR_PLAN" > "$SR_PLAN.t" && mv "$SR_PLAN.t" "$SR_PLAN"
sr_owed "key=approve:release|state=open|sent=-|at=2026-10-06T20:00:00Z|title=approval: release|reply=poker: WAIT T12 — approval:release"
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
section "§KINDS: an unruled matrix row (row:) and an unread ruling (ruling:) open on the register are asks on the sheet"
# ============================================================
# fails-when: either is open and missing from the sheet.
sr_world kinds "6 6 12 12"
sr_owed "key=row:AC-2.1|state=open|sent=-|at=2026-10-06T21:00:00Z|title=ruling: row AC-2.1|reply=poker: AC-2.1 is not proved — rule it"
sr_owed "key=ruling:r9|state=open|sent=-|at=2026-10-06T21:01:00Z|title=ruling unread: T5|reply=poker: NOT-LANDED T5 — w-T5 ended (MET) with an orchestrator ruling unread (r9); the row holds until a writer reads it: re-dispatch the row, or drop it"
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
section "§SHAPES: a done task's note is timed from whichever shape its step line has, landed <sha> <ISO>, landed-by-hand: <who> <ISO> \"<why>\", or either after text; over a 38-task plan every one is"
# ============================================================
# FIXTURE FIDELITY. The `- Step` and `- T<n>:` lines below are a delivered plan's `## SDLC State` lines, byte
# for byte as its run left them at close. Its `## Tasks` table is synthesized: each task's id, step and kind as
# that table holds them, all done, the task cell a stand-in. The landing record is empty, so every time on the
# sheet is the step line's own.
sr_w38_lines() {
  cat <<'SR38'
- Step 0: configured at 2026-10-16T00:36Z via "approved"; prereqs: ok; model_plan=orchestrator=claude-fable-5-1; implementor=sonnet-high; senior-implementor=opus-high; researcher=opus-high; test-runner=haiku-high; auditor=opus-high; critic=opus-high; probe 8 cores, 8 GB, 27 GB free, load 1.80; share 92; branch wave/38-one-stop off main @ 433f7134; charter amendment: the twelve 1.20.0 leftovers are Step-1 items (Chris Lehman 2026-10-15 "I want these included in the charter for 1.21.0 - to be considered in step 1")
- Step 1: requirements: specs/epic-23-bionic-tech-debt/wave-38-one-stop.requirements.md; REQ-1 to REQ-12, 49 criteria; approved by Chris Lehman 2026-10-16T03:03Z "approved" at the Step-1 card; D1–D6 scope rulings and D8–D14 sitrep design rulings (record/wave-38-one-stop/step1-rulings.md, design-ledger.md Δ0–Δ8), D7 withdrawn; six inherited findings disposed (5 adopted, 1 closed), 24 debt lines adopted (record/wave-38-one-stop/debt.md); research w38-R1..R4 under record/wave-38-one-stop/research-*.md; A-orch-1, A-orch-2; REQ-13 added after the card on Chris Lehman's word (2026-10-16T03:25Z): the Step-2 prototype vs the dispatch wall (ideas/bionic-1.20.0-step2-prototype-wall.md); 51 criteria
- Step 2: spec: specs/epic-23-bionic-tech-debt/wave-38-one-stop.spec.md; D8–D14, D16–D26 (D15 the frame), Eval design 52 rows; ADR-059 and ADR-060 (Proposed); design ledger record/wave-38-one-stop/design-ledger.md Δ0–Δ21; approved by Chris Lehman 2026-10-16T04:00Z "approved" at the Step-2 card, the tactical defaults of §5 Assumptions standing
- Step 3: plan: plans/epic-23-bionic-tech-debt/wave-38-one-stop.plan.md; 29 rows (21 build, 1 doc, 2 verify, 2 review, 1 test, 1 integrate, 1 close); matrix 52 rows rendered from the spec Eval design, every block naming its row; rows written by hand at Step 3 (A-orch-3), chains as reads of the upstream record (A-orch-4, A-orch-5); approved by Chris Lehman 2026-10-16T04:27Z "approved" at the Step-3 card
- Step 4: implementation opened 2026-10-16T04:30Z; no row dispatched yet — the first FILL names T4, T1, T2, T3 and the widest rows the gate gives room for; records T<n>-*.md under record/wave-38-one-stop/; assumptions A-orch-1 to A-orch-5
- Step 5: matrix filled by T24 from the landed records (record/wave-38-one-stop/T24-matrix-fill.md): 48 of 52 rows discharged, AC-1.5 and AC-6.6 pending until close-out, AC-9.5 and AC-12.1 pending until the release row T22; walk record/wave-38-one-stop/walk.md (T23, zero AC identifiers); regression: the whole run at d3c4ed2e (96/108) covers the settled head a4658ae0 by rule, every owed suite green in a later landing (A-orch-74); auditor: record/wave-38-one-stop/auditor-evidence.md — REFUTED wave verdict: 39 CONFIRMED, 10 REFUTED (I1, I4, I6, I8, I9, I10, I11, I16), 3 UNVERIFIABLE (AC-1.5, AC-6.6, AC-12.1); the REFUTED rows go to the final card as waive-or-fix defaults
- Step 6: readings on the settled whole at a4658ae0: evidence by the auditor (REFUTED, 39 CONFIRMED / 10 REFUTED / 3 UNVERIFIABLE, record/wave-38-one-stop/auditor-evidence.md), adversarial and structure by the critic (fail: 6 and 1 findings, record/wave-38-one-stop/critic-adversarial.md, critic-structure.md); the two S2-on findings fixed by policy as T36 (5085b1a1) and T37 (74a11248), both landed on their suites; S3 findings #3, #4, #5 deferred to the final card; the piece reading of a4658ae0..74a11248 for adversarial and structure registered at 74a11248 (critic-adversarial-2.md, critic-structure-2.md); regression: covered by rule at every head since d3c4ed2e (A-orch-74), the whole-run verb refusing a second run; the REFUTED rows and the failing readings go to the final card as waive-or-fix defaults
- Step 7: adr: adrs/epic-23-bionic-tech-debt/adr-059-the-lifecycle-has-four-human-stops.md · adrs/epic-23-bionic-tech-debt/adr-060-the-gate-owns-capacity.md (drafted at Step 2, Proposed; Accepted by the release row T22, which writes the 1.21.0 CHANGELOG entry, plugin.json, the rendered help and version pages and rendered.sha256, release-check green from 433f7134)
- Step 8: CLOSED 2026-10-18T15:07Z — wave/38-one-stop merged into main; the tail was performed by close-out.sh 1.21.0
- Step 9: delivered: 2026-10-18T15:07Z wave-38-one-stop 1.21.0 — the Step 8/9 tail was performed by close-out.sh and attested against the commit gate; continuation at record/wave-38-one-stop/continuation.md
- T4: reason: every writer row names its record so T24 fills the matrix from landed records; the brief renderer needs one Expected artifact reason: AC-8.1 wants the roster row to read model=haiku-high; the row is written at dispatch-preflight.sh:3398 from .tool_input.model alone, so the composition lives there (A-orch-6) landed fbfcff25da71bf3c9f40238c5178ea269caae78f 2026-10-17T03:50:19Z
- T2: reason: every writer row names its record so T24 fills the matrix from landed records; the brief renderer needs one Expected artifact landed b6236608b5035cc7d9eb58791c2f5bb7cee1a293 2026-10-16T19:06:02Z
- T1: landed 089674832d046549d5888fcb3343c9524019f9b2 2026-10-16T09:08:37Z
- T3: reason: every writer row names its record (A-orch-6) landed-by-hand: orchestrator bionic-78 under user AUTOPILOT (A-orch-61) 2026-10-17T21:22:27Z "D28 option 3 (A-orch-58, A-orch-64): fourteen built rows gathered into one candidate wt/38-gather, fast-forwarded onto wave/38-one-stop at d3c4ed2e, proven by one full run (regression-run) at that head"
- T10: landed 3c138a39126a3ebf785ed5fec0663a05c7a05ff3 2026-10-16T13:06:02Z
- T11: reason: every writer row names its record (A-orch-6) landed-by-hand: orchestrator bionic-78 under user AUTOPILOT (A-orch-61) 2026-10-17T21:22:47Z "D28 option 3 (A-orch-58, A-orch-64): fourteen built rows gathered into one candidate wt/38-gather, fast-forwarded onto wave/38-one-stop at d3c4ed2e, proven by one full run (regression-run) at that head"
- T6: reason: T6 stacked on T5 tree d8eae687 (T5 built, T5-gate.md on record): the behavioural dependency is met by construction, the landing line orders T6 behind T5 (A-orch-21) landed 56373f8c3b7882554077e66dbd7e5f1177e03718 2026-10-17T14:20:49Z
- T9: reason: T9 stacked on T8 tree ac9eef49 (T8 built, T8-rename.md on record): dependency met by construction, the line orders T9 behind T8 (A-orch-21) reason: T8-rename.md §Printed lines left for T9 names three prose lines in hooks/canonical-sdlc-governing-skill.sh (floors at double, project floor, epic floor) and AC-9.2 doctrine half pins SKILL.md and the diagrams in canonical-sdlc-governing-skill.test.sh §MINIMUM landed-by-hand: orchestrator bionic-78 under user AUTOPILOT (A-orch-61) 2026-10-17T21:22:47Z "D28 option 3 (A-orch-58, A-orch-64): fourteen built rows gathered into one candidate wt/38-gather, fast-forwarded onto wave/38-one-stop at d3c4ed2e, proven by one full run (regression-run) at that head"
- T13: reason: T13 stacked on T12 tree 6ae0c9e3 (T12 built, T12-handoff.md on record): dependency met by construction, the line orders T13 behind T12 (A-orch-21) reason: every writer row names its record so T24 fills the matrix from landed records (A-orch-6 pattern) landed-by-hand: orchestrator bionic-78 under user AUTOPILOT (A-orch-61) 2026-10-17T21:22:47Z "D28 option 3 (A-orch-58, A-orch-64): fourteen built rows gathered into one candidate wt/38-gather, fast-forwarded onto wave/38-one-stop at d3c4ed2e, proven by one full run (regression-run) at that head"
- T30: landed c04eb6b77006001c131e03e39fdd804f7a7c7873 2026-10-17T19:34:12Z — added by task-add at 2026-10-17T07:03:32Z reason: the carrier opens and closes the landing lease the gate orders by; line.sh is T6's file, landed into T30's tree
- T5: landed fda9f0fce16b4a7bd2da2f3b8dbb7f19d71ae1d9 2026-10-17T07:36:24Z
- T14: reason: every writer row names its record so T24 fills the matrix from landed records (A-orch-6 pattern) landed-by-hand: orchestrator bionic-78 under user AUTOPILOT (A-orch-61) 2026-10-17T21:22:47Z "D28 option 3 (A-orch-58, A-orch-64): fourteen built rows gathered into one candidate wt/38-gather, fast-forwarded onto wave/38-one-stop at d3c4ed2e, proven by one full run (regression-run) at that head"
- T15: reason: every writer row names its record so T24 fills the matrix from landed records (A-orch-6 pattern) landed-by-hand: orchestrator bionic-78 under user AUTOPILOT (A-orch-61) 2026-10-17T21:22:47Z "D28 option 3 (A-orch-58, A-orch-64): fourteen built rows gathered into one candidate wt/38-gather, fast-forwarded onto wave/38-one-stop at d3c4ed2e, proven by one full run (regression-run) at that head"
- T16: reason: every writer row names its record (A-orch-6 pattern) landed-by-hand: orchestrator bionic-78 under user AUTOPILOT (A-orch-61) 2026-10-17T21:22:47Z "D28 option 3 (A-orch-58, A-orch-64): fourteen built rows gathered into one candidate wt/38-gather, fast-forwarded onto wave/38-one-stop at d3c4ed2e, proven by one full run (regression-run) at that head"
- T18: reason: every writer row names its record (A-orch-6 pattern) landed-by-hand: orchestrator bionic-78 under user AUTOPILOT (A-orch-61) 2026-10-17T21:22:47Z "D28 option 3 (A-orch-58, A-orch-64): fourteen built rows gathered into one candidate wt/38-gather, fast-forwarded onto wave/38-one-stop at d3c4ed2e, proven by one full run (regression-run) at that head"
- T31: landed d133a3e636b80ca2097e6a4bc90cddb89479be85 2026-10-17T21:21:06Z — added by task-add at 2026-10-17T11:33:24Z
- T17: reason: every writer row names its record (A-orch-6 pattern) landed-by-hand: orchestrator bionic-78 under user AUTOPILOT (A-orch-61) 2026-10-17T21:22:47Z "D28 option 3 (A-orch-58, A-orch-64): fourteen built rows gathered into one candidate wt/38-gather, fast-forwarded onto wave/38-one-stop at d3c4ed2e, proven by one full run (regression-run) at that head"
- T8: landed 64640a8de2be98b285ee6134683145d36eccc847 2026-10-17T12:51:14Z
- T7: reason: every writer row names its record (A-orch-6 pattern) landed-by-hand: orchestrator bionic-78 under user AUTOPILOT (A-orch-61) 2026-10-17T21:22:47Z "D28 option 3 (A-orch-58, A-orch-64): fourteen built rows gathered into one candidate wt/38-gather, fast-forwarded onto wave/38-one-stop at d3c4ed2e, proven by one full run (regression-run) at that head"
- T19: reason: every writer row names its record (A-orch-6 pattern) landed-by-hand: orchestrator bionic-78 under user AUTOPILOT (A-orch-61) 2026-10-17T21:22:47Z "D28 option 3 (A-orch-58, A-orch-64): fourteen built rows gathered into one candidate wt/38-gather, fast-forwarded onto wave/38-one-stop at d3c4ed2e, proven by one full run (regression-run) at that head"
- T20: reason: every writer row names its record (A-orch-6 pattern) landed-by-hand: orchestrator bionic-78 under user AUTOPILOT (A-orch-61) 2026-10-17T21:22:47Z "D28 option 3 (A-orch-58, A-orch-64): fourteen built rows gathered into one candidate wt/38-gather, fast-forwarded onto wave/38-one-stop at d3c4ed2e, proven by one full run (regression-run) at that head"
- T21: reason: every writer row names its record (A-orch-6 pattern) landed-by-hand: orchestrator bionic-78 under user AUTOPILOT (A-orch-61) 2026-10-17T21:22:47Z "D28 option 3 (A-orch-58, A-orch-64): fourteen built rows gathered into one candidate wt/38-gather, fast-forwarded onto wave/38-one-stop at d3c4ed2e, proven by one full run (regression-run) at that head"
- T12: landed-by-hand: orchestrator bionic-78 under user AUTOPILOT (A-orch-61) 2026-10-17T21:22:47Z "D28 option 3 (A-orch-58, A-orch-64): fourteen built rows gathered into one candidate wt/38-gather, fast-forwarded onto wave/38-one-stop at d3c4ed2e, proven by one full run (regression-run) at that head"
- T32: landed 777d2214a4d94d403917cb6d8a5a3b32274d5120 2026-10-18T05:09:19Z — added by task-add at 2026-10-17T22:11:06Z born: regression session-poker-4.test.sh of=regression
- T33: landed 350f0a02097f80c3e711e16b33072c0fc68dc403 2026-10-18T03:13:15Z — added by task-add at 2026-10-17T22:11:07Z born: regression regression-rename.test.sh of=regression
- T34: landed 5af153bcab274a6fd8b9fb51f57da150873f828a 2026-10-18T02:04:55Z — added by task-add at 2026-10-17T22:11:08Z born: regression refuse.test.sh of=regression
- T35: landed a4658ae061ffe28e921e8cc6517d23849ba5178c 2026-10-18T06:19:30Z — added by task-add at 2026-10-17T22:50:41Z reason: D30 amended by the user: the off mark is the plain heavy cross, not the red X emoji reason: D30 amended by the user: green, grey, and a calm off mark; the black circle, no cross, no red reason: the sitrep skill shape names three indicator lines; the legend line makes four reason: D31 ruled: the tolerance model, ✅ within · 🔸 near · 🔶 over · ◇ not measurable reason: D31 glyphs re-ruled by the user: ✅ ➖ 🔼 ❔ reason: D31 glyphs final by the user: the grey X for over
- T23: landed a4658ae061ffe28e921e8cc6517d23849ba5178c 2026-10-18T06:28:58Z
- T26: landed a4658ae061ffe28e921e8cc6517d23849ba5178c 2026-10-18T06:35:07Z
- T36: landed 5085b1a1d37b073b2cb06671476fbdece5fae97c 2026-10-18T07:33:06Z — added by task-add at 2026-10-18T06:35:47Z born: review S2 on of=record/wave-38-one-stop/critic-adversarial.md#1
- T37: landed 74a11248d6e03803342ed43cd86baa620cc1c587 2026-10-18T09:23:36Z — added by task-add at 2026-10-18T06:35:48Z born: review S2 on of=record/wave-38-one-stop/critic-adversarial.md#2,record/wave-38-one-stop/critic-structure.md#1
- T25: landed a4658ae061ffe28e921e8cc6517d23849ba5178c 2026-10-18T06:37:04Z
- T24: landed a4658ae061ffe28e921e8cc6517d23849ba5178c 2026-10-18T06:38:25Z
- T27: reason: the regression verb refused a second whole run at both settled heads under its coverage rule (A-orch-74); the row's artifact is the rule's record, not a timing file no run wrote landed 74a11248d6e03803342ed43cd86baa620cc1c587 2026-10-18T09:36:54Z
- T28: reason: the release scan hits a private name in two historical blobs of tests/dispatch-preflight-5.test.sh (T21 commits 1c99bfdd, ab4acf46); the user rules on the history before the merge, and T22 lands red on release-check until that approval reason: the history token is read by T38, before integration landed acd8c99944e366753b73f581d64431be361010a7 2026-10-18T15:07:33Z
- T38: landed 0fd9782dd2a82e26391b2b1ccdf1a4432e71261c 2026-10-18T15:07:26Z — added by task-add at 2026-10-18T09:39:17Z
- T22: landed d06c2364653d76ea1aabc8dec97dbf41220df64d 2026-10-18T10:46:10Z
- T29: landed acd8c99944e366753b73f581d64431be361010a7 2026-10-18T15:07:33Z
SR38
}
SR_W38_ROWS="T4:4:build T1:4:build T2:4:build T3:4:build T5:4:build T6:4:build T7:4:build T8:4:build T9:4:build T10:4:build T11:4:build T12:4:build T13:4:build T14:4:build T15:4:build T16:4:build T17:4:build T18:4:build T19:4:build T20:4:build T21:4:build T22:7:doc T23:5:verify T24:5:verify T25:6:review T26:6:review T27:6:test T28:8:integrate T29:9:close T30:4:build T31:4:build T32:4:build T33:4:build T34:4:build T35:4:build T36:4:build T37:4:build T38:7:doc"
sr_w38_world() {
  local r="$TMPROOT/w38" d p e n
  mkdir -p "$r/.bionic/tmp" "$r/.bionic/docs/plans/epic-01-fx"
  ( cd "$r" && git init -q . 2>/dev/null )
  d="$r/.bionic/docs/record/wave-38-fx"; mkdir -p "$d"
  p="$r/.bionic/docs/plans/epic-01-fx/wave-38-fx.plan.md"
  SR_REPO="$r"; SR_PLAN="$p"; SR_DIR="$d"; SR_REC="$d/landing-proofs.log"; : > "$SR_REC"
  SR_GATE="$TMPROOT/gate-w38"; mkdir -p "$SR_GATE/requests" "$SR_GATE/cost"
  {
    printf -- '---\nwave: wave-38-fx\nrelease: 1.21.0\nworking-branch: wave/38-fx\nintegration-branch: main\nforecast: 48h\n---\n'
    printf '# wave 38 as a fixture\n\n## SDLC State\n\ncurrent: 9\n\n'
    sr_w38_lines
    printf '\n## Tasks\n\n'
    printf '| id | step | kind | task | agent | deps | reads | size | serves | Files | worktree | base | status | suites | lands-on | artifact |\n'
    printf '|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|\n'
    for e in $SR_W38_ROWS; do
      n="${e%%:*}"
      printf '| %s | %s | %s | Row %s of wave 38 · complexity: standard | — | — | — | 30 | REQ-1 | lib/w%s.sh | — | — | landed | — | — | — |\n' \
        "$n" "$(printf '%s' "$e" | cut -d: -f2)" "${e##*:}" "${n#T}" "${n#T}"
    done
    printf '\n## Not Doing\n\n- nothing\n'
  } > "$p"
}
sr_w38_world
sr_run "$SR_PLAN"
expect_eq "SP0 precondition: the 38-task plan prints (rc 0), every task done, read by the completed count" \
  "0|38 tasks, 1140 of 1140 min, 100%" "$RC|$(sr_m work.landed)"
expect_eq "SP0b precondition: the fixture holds the three shapes — bare, text before landed, landed-by-hand (lead and after text)" "yes|yes|yes|yes" \
  "$(sr_w38_lines | /usr/bin/grep -qE '^- T1: landed [0-9a-f]{40} ' && echo yes)|$(sr_w38_lines | /usr/bin/grep -qE '^- T2: reason: .* landed [0-9a-f]{40} ' && echo yes)|$(sr_w38_lines | /usr/bin/grep -qE '^- T12: landed-by-hand: ' && echo yes)|$(sr_w38_lines | /usr/bin/grep -qE '^- T3: reason: .* landed-by-hand: ' && echo yes)"
expect_eq "SP1 38 of 38 done tasks carry a landing time in their note" "38" \
  "$(sr_tasks_f note | /usr/bin/grep -cE '^landed [0-9]{1,2}:[0-9]{2} [AP]M( [0-9]{4}-[0-9]{2}-[0-9]{2})?( by hand)?$')"
expect_eq "SP2 the bare shape, the text before landed, and two reason clauses before it: each at its landing's local time" \
  "landed 2:08 AM 2026-10-16|landed 12:06 PM 2026-10-16|landed 8:07 AM 2026-10-18" \
  "$(for t in T1 T2 T28; do sr_f "$(sr_task "$t")" note; done | sr_join)"
expect_eq "SP3 a landing by hand says so" "landed 2:22 PM 2026-10-17 by hand" "$(sr_f "$(sr_task T12)" note)"

# ============================================================
section "§ORDER: the task lines are in execution order — done by landing time, hand landings included; in flight by place on the line with what each is doing; the rest in dependency order"
# ============================================================
# The world: the plain fixture landed out of table order (T2 3:36, T3 by hand 3:50, T1 4:00, T4 5:12), T8 in its
# landing with one of its two suites green, T6 and T5 queued behind it, T7 building, and T10 reading what T11 writes
# so that dependency order puts T11 first.
sr_world order-run "60 6 12 12"
awk '
  /^- T3: / { print "- T3: reason: rebuilt after T2 landed-by-hand: Dana Fixture (the orchestrator) 2026-10-06T10:50:00Z \"merged by hand on its greens\" — .worktrees/02-T3"; next }
  /^\| T10 \| / { sub(/\| — \| 30 \|/, "| lib/t11.sh | 30 |") }
  { print }' "$SR_PLAN" > "$SR_PLAN.t" && mv "$SR_PLAN.t" "$SR_PLAN"
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
awk -v h="$SR_H" '{ print } /^current: 4$/ { print "proved: kind=review head=" h " at=2026-10-06T20:00:00Z evidence=record/wave-02-fx/critic.md question=adversarial reader=crit result=fail scope=piece" }' "$SR_PLAN" > "$SR_PLAN.t" && mv "$SR_PLAN.t" "$SR_PLAN"
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
awk -F'|' 'BEGIN { OFS = "|" } ($2 == " T15 " || $2 == " T16 ") && NF > 12 { $14 = " dropped " } { print }' "$SR_PLAN" > "$SR_PLAN.t" && mv "$SR_PLAN.t" "$SR_PLAN"
printf 'fill-ledger/v1|at=2026-10-06T16:00:00Z|session=%s|turn=t2|current=4|state=ok|ceiling=|width=4|open=3|free=1|ready=T9|launched=|declined=|missed=1|idle=T9|room=1\n' "$SID" >> "$SR_DIR/fill-ledger.log"
printf 'fill-ledger/v1|at=2026-10-06T17:12:00Z|session=%s|turn=t3|current=4|state=ok|ceiling=|width=4|open=4|free=0|ready=|launched=T9|declined=|missed=0|idle=|room=0\n' "$SID" >> "$SR_DIR/fill-ledger.log"
sr_run "$SR_PLAN"
expect_eq "ME5 two tasks dropped and a 72-minute idle turn: the waste in numbers; the dropped tasks leave the count" \
  "2 tasks, 60 min|2 of 6|72 min|4 tasks, 120 of 540 min, 22%" "$(sr_waste)|$(sr_m work.landed)"

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
# (one failed), adversarial on a piece failed then passed (one passed), evidence on the whole passed once.
sr_world metrics-reviews "6 6 12 12"
for f in s1 s2 a1 a2 e1; do printf 'reviewed: %s..%s\nfindings: 0\n' "$SR_C1" "$SR_H" > "$SR_DIR/$f.md"; done
awk -v h="$SR_H" '{ print } /^current: 4$/ {
  print "proved: kind=review head=" h " at=2026-10-06T19:00:00Z evidence=record/wave-02-fx/s1.md question=structure reader=c1 result=pass scope=whole"
  print "proved: kind=review head=" h " at=2026-10-06T19:05:00Z evidence=record/wave-02-fx/a1.md question=adversarial reader=c2 result=fail scope=piece"
  print "proved: kind=review head=" h " at=2026-10-06T19:10:00Z evidence=record/wave-02-fx/e1.md question=evidence reader=a1 result=pass scope=whole"
  print "proved: kind=review head=" h " at=2026-10-06T20:00:00Z evidence=record/wave-02-fx/s2.md question=structure reader=c3 result=fail scope=whole"
  print "proved: kind=review head=" h " at=2026-10-06T20:05:00Z evidence=record/wave-02-fx/a2.md question=adversarial reader=c4 result=pass scope=piece" }' \
  "$SR_PLAN" > "$SR_PLAN.t" && mv "$SR_PLAN.t" "$SR_PLAN"
sr_run "$SR_PLAN"
expect_eq "RV1 five results of reviews, each still a review: line, and the count by question and scope at its latest: 2 passed, 1 failed" \
  "5|2 passed, 1 failed, 0 running" \
  "$(sr_lines review | /usr/bin/grep -c .)|$(sr_m reviews)"

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
expect_eq "SU1 three suites by their last verdict (a discarded run is none), the whole run red at its head, the reviews after" \
  "3: 2 green, 1 red|red at aaaaaaaa|0 passed, 0 failed, 0 running|0" \
  "$(sr_correct)"
SR_H2="$(printf 'b%.0s' $(seq 40))"
awk -v h="$SR_H2" '{ print } /^current: 4$/ { print "proved: kind=regression head=" h " at=2026-10-06T15:00:00Z evidence=record/wave-02-fx/regression-run-" h ".log" }' \
  "$SR_PLAN" > "$SR_PLAN.t" && mv "$SR_PLAN.t" "$SR_PLAN"
sr_run "$SR_PLAN"
expect_eq "SU2 a later whole run proved green: green at its head" "green at bbbbbbbb" \
  "$(sr_m tests.whole-run)"
awk 'NR > 1 && /^---$/ && !d { print "regression: no"; d = 1 } { print }' "$SR_PLAN" > "$SR_PLAN.t" && mv "$SR_PLAN.t" "$SR_PLAN"
sr_run "$SR_PLAN"
expect_eq "SU3 a plan that owes no whole run says so, beside the suites it ran" \
  "3: 2 green, 1 red|not run (regression: no, Step 0)" \
  "$(sr_m tests.suites-run)|$(sr_m tests.whole-run)"

section "§COUNTS: a count agrees in number with what it counts — one task, two tasks; the sheet never says 1 tests"
# ============================================================
# fails-when: any count phrase on the sheet says a plural for one, or a singular for two.
sr_world counts-one "6 6 12 12"
awk -F'|' '!(/^\| T[0-9]+ / && $2 != " T1 ")' "$SR_PLAN" > "$SR_PLAN.t" && mv "$SR_PLAN.t" "$SR_PLAN"
sr_ev "ev=standing|head=$SR_H|suite=b.test.sh|lines=2|log=/rec/standing-b.log|cause=code|against=-|at=2026-10-06T14:00:00Z"
printf 'fill-ledger/v1|at=2026-10-06T16:00:00Z|session=%s|turn=t2|current=4|state=ok|ceiling=|width=4|open=3|free=1|ready=T9|launched=|declined=|missed=1|idle=T9|room=1\n' "$SID" >> "$SR_DIR/fill-ledger.log"
printf 'fill-ledger/v1|at=2026-10-06T16:01:00Z|session=%s|turn=t3|current=4|state=ok|ceiling=|width=4|open=4|free=0|ready=|launched=T9|declined=|missed=0|idle=|room=0\n' "$SID" >> "$SR_DIR/fill-ledger.log"
sr_run "$SR_PLAN"
expect_eq "CN0 precondition: the plan holds the one task, landed, and the sheet draws it" "1|1" \
  "$(sr_lines task | /usr/bin/grep -c .)|$(sr_tasks_f state | /usr/bin/grep -c '^done$')"
expect_eq "CN1 one task: landed says 1 task, none left says 0 tasks, correctness counts its two suites" \
  "1 task, 30 of 30 min, 100%|0 tasks, 0 min|2: 1 green, 1 red" \
  "$(sr_m work.landed)|$(sr_m work.left)|$(sr_m tests.suites-run)"
expect_eq "CN2 one minute idle is 1 min" "1 min" "$(sr_m waste.ready-unstarted)"
expect_eq "CN3 the status line says 1 of 1 task" "yes" \
  "$(sr_poke sitrep --line "$SR_PLAN" 2>/dev/null | /usr/bin/grep -q '^1 of 1 task · ' && echo yes)"
sr_world counts-two "6 6 12 12"
sr_ev "ev=standing|head=$SR_H|suite=b.test.sh|lines=2|log=/rec/standing-b.log|cause=code|against=-|at=2026-10-06T14:00:00Z"
sr_ev "ev=standing|head=$SR_H|suite=c.test.sh|lines=2|log=/rec/standing-c.log|cause=code|against=-|at=2026-10-06T14:00:00Z"
sr_run "$SR_PLAN"
expect_eq "CN4 two of each stays plural: a plan of many tasks" "3: 1 green, 2 red|4 tasks, 120 of 600 min, 20%|13 tasks, 480 min" \
  "$(sr_m tests.suites-run)|$(sr_m work.landed)|$(sr_m work.left)"
sr_world counts-landing "6 6 12 12"
sr_ev "ev=candidate|row=T8|base=$SR_C1|commit=$(printf 'd%.0s' $(seq 40))|tree=/landing/1|at=2026-10-06T13:35:00Z"
sr_ev "ev=verdict|row=T8|commit=$(printf 'd%.0s' $(seq 40))|suite=a.test.sh|result=green|log=/rec/T8a.log|at=2026-10-06T13:50:00Z"
sr_run "$SR_PLAN"
expect_eq "CN5 a landing with its one suite green says 1 of 1 suite green" "in its landing, 1 of 1 suite green" "$(sr_f "$(sr_task T8)" note)"

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
  $2 ~ /^ T([5-9]|1[0-7]) $/ { n = $2; gsub(/[ T]/, "", n); if (n + 0 > 5) $8 = " lib/t" (n - 1) ".sh " }
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
# A row landed twice counts once, to its later header; a header naming no row of the plan counts nothing.
printf 'landed: row=T1 branch=wt/02-T1 head=%s merge=%s at=2026-10-06T12:30:00Z\nlanded: row=— branch=wt/02-x head=%s merge=%s at=2026-10-06T13:00:00Z\nlanded: row=T99 branch=wt/02-y head=%s merge=%s at=2026-10-06T13:00:00Z\n' \
  "$SR_C1" "$SR_C1" "$SR_C1" "$SR_C1" "$SR_C1" "$SR_C1" >> "$SR_REC"
sr_run "$SR_PLAN"
expect_eq "PA1b a re-landed row counts once, to its later header; a header naming no row of the plan counts nothing" \
  "4 tasks, 280 min against 120 sized min" "$(sr_m work.task-time)"
# No landing: nothing measures the scale, so the chain stands at 1×.
sr_world pace-zero none
sr_run "$SR_PLAN"
expect_eq "PA2 no landing: the chain at 1×, nothing landed to measure" \
  "5:30 PM|0 tasks: none has landed|yes" \
  "$(sr_m close.predicted)|$(sr_m work.task-time)|$(sr_d close.predicted | /usr/bin/grep -q 'at 1×: 0 landed build tasks have a launch and a landing on record, under 3' && echo yes)"
# Fewer than three landings scale nothing: two of the four rows land (T3's and T4's headers gone); then one; then three.
sr_world pace-two "5 5 5 5"
sr_launch T1 09:35:00; sr_launch T2 10:05:00; sr_launch T3 10:35:00; sr_launch T4 11:20:00
awk '!/^landed: row=T[34] /' "$SR_REC" > "$SR_REC.t" && mv "$SR_REC.t" "$SR_REC"
sr_run "$SR_PLAN"
expect_eq "PA4 two landings: their time counted, the rows with no landing header said (precondition)" \
  "2 tasks, 60 min against 60 sized min; 2 landed tasks with no launch or landing on record" "$(sr_m work.task-time)"
expect_eq "PA4b …the close is the chain at 1×, and the basis says 2, under 3" "5:30 PM|yes" \
  "$(sr_m close.predicted)|$(sr_d close.predicted | /usr/bin/grep -q 'at 1×: 2 landed build tasks have a launch and a landing on record, under 3' && echo yes)"
sr_run --line "$SR_PLAN"
expect_eq "PA4c …and the Patrol's status carries it" "close 5:30 PM" "${OUT##* · }"
awk '!/^landed: row=T2 /' "$SR_REC" > "$SR_REC.t" && mv "$SR_REC.t" "$SR_REC"
sr_run "$SR_PLAN"
expect_eq "PA4d one landing: the same, said for 1" "yes" \
  "$(sr_d close.predicted | /usr/bin/grep -q 'at 1×: 1 landed build task has a launch and a landing on record, under 3' && echo yes)"
sr_world pace-three "5 5 5 5"
sr_launch T1 09:35:00; sr_launch T2 10:05:00; sr_launch T3 10:35:00; sr_launch T4 11:20:00
awk '!/^landed: row=T4 /' "$SR_REC" > "$SR_REC.t" && mv "$SR_REC.t" "$SR_REC"
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
awk -F'|' 'BEGIN { OFS = "|" } $2 ~ /^ T([5-9]|1[0-7]) $/ { $14 = " landed " } { print }' "$SR_PLAN" > "$SR_PLAN.t" && mv "$SR_PLAN.t" "$SR_PLAN"
sr_run "$SR_PLAN"
expect_eq "CC3 every task landed and the run open: the predicted close is now, nothing left to forecast" "3:00 PM|1|none: no task is open" \
  "$(sr_m close.predicted)|$(sr_d close.predicted | /usr/bin/grep -c 'no task is open')|$(sr_m close.chain)"
sr_w38_world
awk '{ print } /^current: 9$/ && !d { print "approved-by: fixture 2026-10-18T03:00:00Z \"approved\""; d = 1 }' "$SR_PLAN" > "$SR_PLAN.t" && mv "$SR_PLAN.t" "$SR_PLAN"
awk '/^\| T21 \| / { sub(/\| landed \|/, "| active |") } { print }' "$SR_PLAN" > "$SR_PLAN.t" && mv "$SR_PLAN.t" "$SR_PLAN"
sr_run "$SR_PLAN"
expect_eq "CC4 a delivered run with a task still open after the delivery: its close is the delivery, against the forecast end" \
  "running|8:07 AM 2026-10-18|48 h, ends 8:00 PM 2026-10-19|1" \
  "$(sr_f "$(sr_task T21)" state)|$(sr_m close.predicted)|$(sr_m clock.forecast)|$(sr_d close.predicted | /usr/bin/grep -c 'basis: delivered at 8:07 AM 2026-10-18')"
sr_run --line "$SR_PLAN"
expect_eq "CC5 …and the Patrol's status closes at the delivery" "close 8:07 AM 2026-10-18" "${OUT##* · }"
# Four rows sized 100 min each, each launched 6 min before it landed: 24 min of their own against 400 sized, so the
# 150-min chain takes 9 min; T8 is running, so it has its 15 min cadence left, not 5: the close is 3:19 PM.
sr_world guess-fast "5 5 5 5"
awk -F'|' 'BEGIN { OFS = "|" } $2 ~ /^ T[1-4] $/ { $9 = " 100 " } { print }' "$SR_PLAN" > "$SR_PLAN.t" && mv "$SR_PLAN.t" "$SR_PLAN"
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
sr_owed "key=approve:release|state=open|sent=-|at=2026-10-06T20:00:00Z|title=approval: release|reply=poker: WAIT T12 — approval:release"
sr_owed "key=gate:abc|state=open|sent=-|at=2026-10-06T20:00:00Z|title=gate act: merge|reply=poker: GATE T28 — merge: approve it"
sr_run --line "$SR_PLAN"
SR_L2="$OUT"
sr_run "$SR_PLAN"
expect_eq "L2 two asks open: owed counts them, the same asks the sheet lists" "4 of 17 tasks · owed: 2 on you · 0 on events · close 5:30 PM|2" \
  "$SR_L2|$(sr_lines ask | /usr/bin/grep -c .)"
SR_FORECAST= sr_world line-none none
sr_run --line "$SR_PLAN"
expect_eq "L3 no landing: the close is the chain at 1×" "0 of 17 tasks · owed: 0 on you · 0 on events · close 5:30 PM" "$OUT"

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
sr_run --line "$SR_PLAN"
expect_eq "A4 …while --line and the plan alone print (0)" "0" "$RC"

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
sr_owed "key=approve:release|state=open|sent=-|at=2026-10-06T20:00:00Z|title=approval: release|reply=poker: WAIT T12 — approval:release"
SR_AT=$((SR_NOW + 60)) sr_tick
SR_T2="$OUT"
SR_AT=$((SR_NOW + 60)) sr_run --line "$SR_PLAN"
expect_eq "S3 an ask opened: the next tick's sitrep line moves with the Patrol's status" "poker: sitrep $OUT|yes" \
  "$(printf '%s\n' "$SR_T2" | /usr/bin/grep '^poker: sitrep ')|$([ "$OUT" != "$SR_L1" ] && echo yes)"
SR_AT=$((SR_NOW + 120)) sr_tick
expect_contains "S4 an unchanged tick (nothing decided moved) still takes the unchanged path" "poker: unchanged since " "$OUT"

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
sr_owed "key=approve:release|state=open|sent=-|at=2026-10-06T20:00:00Z|title=approval: release|reply=poker: WAIT T12 — approval:release" "$SR_PLAN_A"
sr_owed "key=approve:merge|state=open|sent=-|at=2026-10-06T20:01:00Z|title=approval: merge|reply=poker: WAIT T17 — approval:merge" "$SR_PLAN_B"
sr_owed_sid "key=waive:structure|state=open|sent=-|at=2026-10-06T20:02:00Z|title=waiver: structure|reply=poker: the structure review is owed" "$SID3"
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
awk -v h="$SR_H" '{ print } /^current: 4$/ { print "proved: kind=regression head=" h " at=2026-10-06T20:00:00Z evidence=record/wave-02-fx/regression-run-" h ".log" }' "$SR_PLAN" > "$SR_PLAN.t" && mv "$SR_PLAN.t" "$SR_PLAN"
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

# sr_themes <current> <nine statuses> -> this world's plan made
# wave scale at step <current> with a matrix of nine rows, the statuses in order (two criteria of the first REQ, one each of the
# second to the fourth, two each of the fifth and sixth), and a requirements file of three themes beside it:
# the first two REQs under the first theme, the next three under the second, the sixth under the third. SR_REQ_AT names the file
# the plan's Step-1 line points at; unset, the plan names none and the file is the sibling under specs/ by the slug.
sr_themes() {
  local cur="$1" q a; shift
  q="$SR_REPO/.bionic/docs/specs/epic-01-fx/wave-02-fx.requirements.md"
  [ -z "${SR_REQ_AT:-}" ] || q="$SR_REPO/.bionic/docs/$SR_REQ_AT"
  mkdir -p "${q%/*}"
  awk -v c="$cur" -v at="${SR_REQ_AT:-}" '
    NR > 1 && /^---$/ && !fm { fm = 1; print "scale: wave" }
    /^current: / { print "current: " c; if (at != "") print "\n- Step 1: requirements: " at "; approved by fixture"; next }
    { print }' "$SR_PLAN" > "$SR_PLAN.t" && mv "$SR_PLAN.t" "$SR_PLAN"
  { printf '\n## Verification Matrix\n\n| AC | tier | status | evidence | auditor |\n|---|---|---|---|---|\n'
    for a in AC-1.1 AC-1.2 AC-2.1 AC-3.1 AC-4.1 AC-5.1 AC-5.2 AC-6.1 AC-6.2; do printf '| %s | T2 | %s | pending | — |\n' "$a" "$1"; shift; done
  } >> "$SR_PLAN"
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
section "§REQ-GOALS-3: a hand-holds goal read from the landing report counts the window from the last build landing to the card, against its target"
# ============================================================
# fails-when: the median reader answers, or it is not measured.
SR_GOALS="hand-holds · zero from the last landing to the release approval card (landing-report)" sr_world rg3 "6 6 12 12"
sr_run "$SR_PLAN"
expect_eq "RG3-1 no hand-hold since the last build landing: the zero target is met" "hand-holds=met" "$(sr_goal_st)"
sr_ev "ev=stop-run|row=T8|at=2026-10-06T14:00:00Z"
sr_run "$SR_PLAN"
expect_eq "RG3-2 one stop-run after the last build landing: not met, the reading the window's count before the card has rendered" \
  "hand-holds=not met|zero from the last landing to the release approval card — 1 hand-hold from the last build landing (T4) to now: the card has not rendered" \
  "$(sr_goal_st)|$(sr_goal_m hand-holds)"

# sr_goal_put <goal text, \n for a line break> -> this world's plan carries a `## Goal` section before its SDLC State.
sr_goal_put() {
  printf '## Goal\n\n%b\n' "$1" > "$TMPROOT/goal.txt"
  awk -v gf="$TMPROOT/goal.txt" '/^## SDLC State$/ && !d { while ((getline l < gf) > 0) print l; print ""; d = 1 } { print }' "$SR_PLAN" > "$SR_PLAN.t" && mv "$SR_PLAN.t" "$SR_PLAN"
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
  { printf '\n## Verification Matrix\n\n| AC | tier | status | evidence | auditor |\n|---|---|---|---|---|\n'
    for a in 1 2; do for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
      st=pending; [ "$a" = 1 ] && [ "$i" -le 11 ] && st=discharged
      printf '| AC-%s.%s | T2 | %s | pending | — |\n' "$a" "$i" "$st"; done; done
  } >> "$SR_PLAN"
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
SR_REG_F="$(sr_reg)"
sr_tick
expect_eq "GM1 four 20-minute one-file landings miss the 15-minute goal: the tick opens decide:goal:fast-landings on the register, and nothing for the goal not measured" \
  "decide:goal:fast-landings" "$(/usr/bin/grep -oE '\|key=decide:goal:[^|]*\|state=open\|' "$SR_REG_F" 2>/dev/null | cut -d'|' -f2 | sed 's/^key=//' | sr_join)"
expect_eq "GM2 …it is owed: the tick's sitrep line counts it" "owed: 1" \
  "$(/usr/bin/grep '^poker: sitrep ' "$TMPROOT/tick.out" | /usr/bin/grep -oE 'owed: [0-9]+')"
sr_run "$SR_PLAN"
expect_eq "GM3 the sheet carries it as one ask, its title naming the goal" "decide:goal:fast-landings|Goal missed: fast landings" \
  "$(sr_lines ask | while IFS= read -r l; do sr_f "$l" key; done | sr_join)|$(sr_f "$(sr_ask decide:goal:fast-landings)" title)"
expect_eq "GM3a …a goal missed holds no task, the release or the merge: the ask reads holds=nothing and blocks=no" "nothing|no" \
  "$(sr_f "$(sr_ask decide:goal:fast-landings)" holds)|$(sr_f "$(sr_ask decide:goal:fast-landings)" blocks)"
sed -i.bak 's/one-file median under 15m/one-file median under 30m/' "$SR_PLAN" && rm -f "$SR_PLAN.bak"
printf '# reader test\n\nverdict: pass\n' > "$SR_DIR/reader-test-handoff.md"
sr_owed "key=approve:release|state=open|sent=-|at=2026-10-06T20:00:00Z|title=approval: release|reply=poker: WAIT T12 — approval:release"
sr_run "$SR_PLAN"
expect_eq "GM3b both goals met while the decision is still open: the sheet drops it and keeps the approval, with nothing on stderr" \
  "approve:release|" "$(sr_lines ask | while IFS= read -r l; do sr_f "$l" key; done | sr_join)|$ERR"
SR_AT=$((SR_NOW + 60)) sr_tick
expect_eq "GM4 the goal now met: the tick closes its open decision, and the item stays on the register closed" "1|0" \
  "$(/usr/bin/grep -c '|key=decide:goal:fast-landings|state=closed|' "$SR_REG_F")|$(/usr/bin/grep -c '|key=decide:goal:fast-landings|state=open|' "$SR_REG_F")"

# ============================================================
section "§DECLARED-RED: a goal missed by a red the plan itself declares opens no decide:goal:; any other miss still does"
# ============================================================
# fails-when: the ask opens for a declared red, or a miss the plan did not declare opens none. Three suite goals read red
# from the landing record: one under a `debt:` line a Lands-red: row wrote, one with no debt, one whose debt a `void:`
# line cancelled. The sheet still reads all three as not met: the red is declared, the goal is not reached.
SR_GOALS="declared · the declared suite stays green (decl.test.sh §A)
plain · the plain suite stays green (plain.test.sh §A)
voided · the voided suite stays green (void.test.sh §A)" SR_APPROVED=none sr_tick_world declared-red "20 20 20 20"
for sr_s in decl plain void; do
  sr_ev "ev=verdict|row=T9|commit=$SR_C1|suite=$sr_s.test.sh|result=red|log=/rec/$sr_s.log|at=2026-10-06T21:00:00Z"
done
printf 'debt: id=7.1 row=T9 branch=wt/02-T9 head=%s suite=decl.test.sh token=ext:fixture at=2026-10-06T21:00:00Z\n' "$SR_C1" >> "$SR_REC"
printf 'debt: id=7.2 row=T9 branch=wt/02-T9 head=%s suite=void.test.sh token=ext:fixture at=2026-10-06T21:00:00Z\n' "$SR_C1" >> "$SR_REC"
printf 'void: id=7.2 branch=wt/02-T9 at=2026-10-06T21:30:00Z why=publish-failed\n' >> "$SR_REC"
SR_REG_F="$(sr_reg)"
sr_run "$SR_PLAN"
expect_eq "DR0 precondition: the sheet reads all three suite goals not met, each from its red verdict" "declared=not met|plain=not met|voided=not met" "$(sr_goal_st)"
sr_tick
expect_eq "DR1 the tick opens decide:goal: for the plain miss and the voided debt's, and none for the declared red" \
  "decide:goal:plain|decide:goal:voided" "$(/usr/bin/grep -oE '\|key=decide:goal:[^|]*\|state=open\|' "$SR_REG_F" 2>/dev/null | cut -d'|' -f2 | sed 's/^key=//' | sr_join)"
expect_eq "DR2 …and it says only the two it opened" "2|0" \
  "$(/usr/bin/grep -c '^poker: GOAL .* missed' "$TMPROOT/tick.out")|$(/usr/bin/grep -c '^poker: GOAL declared' "$TMPROOT/tick.out")"

# ============================================================
section "§ONE-FILE: the one-file goal reads the one-file landings only; a landing of more files moves it not"
# ============================================================
SR_FORECAST=200h SR_GOALS="fast landings · one-file median under 5m (landing-report --rows)" sr_world one-file "90 90 10 10"
awk -F'|' 'BEGIN { OFS = "|" } $2 ~ /^ T[12] $/ { $11 = " lib/t1.sh, lib/x.sh " } { print }' "$SR_PLAN" > "$SR_PLAN.t" && mv "$SR_PLAN.t" "$SR_PLAN"
sr_run "$SR_PLAN"
expect_eq "OF1 two 90-minute landings of two files and two 10-minute one-file landings: the goal reads 10 min against its 5-minute target" \
  "fast landings=not met|yes" "$(sr_goal_st)|$(sr_goal_m 'fast landings' | /usr/bin/grep -q 'median is 10 min over 2 landings' && echo yes)"

# ============================================================
section "§WAIT-WORDS: a task waiting on the review facts says so in words; the judge's facts string and its record paths never reach its line"
# ============================================================
sr_world wait-words "6 6 12 12"
SR_W_ROW="$(sr_row T19 "Review-gated row · complexity: standard" proof:review 30 pending)"
awk -v r="$SR_W_ROW" '{ print } /^\| T17 \|/ { print r }' "$SR_PLAN" > "$SR_PLAN.t" && mv "$SR_PLAN.t" "$SR_PLAN"
sr_run "$SR_PLAN"
SR_W_LINE="$(sr_task T19)"
expect_eq "WW1 the review-gated task's note names the reviews, with no facts string and no record path" "waits on the reviews|0" \
  "$(sr_f "$SR_W_LINE" note)|$(printf '%s\n' "$SR_W_LINE" | /usr/bin/grep -cE 'facts_state|record/|\.md')"

# ============================================================
section "§DECISIONS: a decision put and not ruled is an ask on the sheet, owed once; ruled, it is gone while the reviews stay"
# ============================================================
# FIXTURE FIDELITY: the put heading and the wait line under it in the shape `decisions put` writes them.
sr_world decisions "6 6 12 12"
sr_bind
printf '# Design ledger — wave-02-fx\n\n## Δ0 — D19 put (orchestrator 2026-10-20 6:44 AM PDT): the regression rule the judge holds\n\nAnswered now or in an hour.\n' > "$SR_DIR/design-ledger.md"
sr_reviews
sr_run "$SR_PLAN"
expect_eq "DE1 one put with no ruling: one ask, its number and title, what it holds and when it was put" \
  "decide:D19|D19 · the regression rule the judge holds|nothing|6:44 AM" \
  "$(for f in key title holds raised; do sr_f "$(sr_lines ask)" "$f"; done | sr_join)"
expect_eq "DE1b …holding nothing, it blocks nothing: blocks=no" "no" "$(sr_f "$(sr_lines ask)" blocks)"
sr_run --line "$SR_PLAN"
expect_eq "DE2 …the Patrol's status counts it" "owed: 1" "$(printf '%s\n' "$OUT" | /usr/bin/grep -oE 'owed: [0-9]+')"
# The put's own ask on the register, as `decisions put` opens it, and a held merge naming the decision.
sr_owed "key=decide:D19|state=open|sent=-|at=2026-10-06T20:30:00Z|title=reply to D19|reply=D19 · the regression rule the judge holds: reply with the option number."
sr_owed "key=hold:merge|state=open|sent=-|at=2026-10-06T21:00:00Z|title=held merge: D19 unruled|reply=bionic: close-out refused — the merge waits on D19"
sr_run "$SR_PLAN"
expect_eq "DE2b the decision is still one ask, now holding the merge a held merge names it in, raised when its ask was opened" \
  "decide:D19|the merge|1:30 PM|hold:merge" \
  "$(sr_f "$(sr_ask decide:D19)" key)|$(sr_f "$(sr_ask decide:D19)" holds)|$(sr_f "$(sr_ask decide:D19)" raised)|$(sr_f "$(sr_ask hold:merge)" key)"
expect_eq "DE2c …and holding the merge, it blocks: blocks=yes" "yes" "$(sr_f "$(sr_ask decide:D19)" blocks)"
printf '\n## Δ1 — D19 ruled "2" (Chris Lehman 2026-10-20): the regression rule the judge holds\n' >> "$SR_DIR/design-ledger.md"
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
printf '\n## Δ1 — D21 ruled "1" (Chris Lehman 2026-10-06): the gate the judge holds\n' >> "$SR_DIR/design-ledger.md"
sr_recap
expect_eq "RC3 the decision ruled: no open: and no ask: line names it while the tick's approvals still read open, and the recap lists it settled" \
  "0|0|2|settled: D21 · \"1\" · Chris Lehman 2026-10-06 · the gate the judge holds" \
  "$(printf '%s\n' "$RECAP" | /usr/bin/grep -c '^open: .*D21')|$(printf '%s\n' "$RECAP" | /usr/bin/grep -c '^ask: .*D21')|$(printf '%s\n' "$RECAP" | /usr/bin/grep -c '^ask: approval: ')|$(printf '%s\n' "$RECAP" | /usr/bin/grep '^settled: D21')"

# ============================================================
section "§ONCE: a decision a row waits on is owed once, not as the tick's approval item and the ledger's decision both"
# ============================================================
# The real tick opens the item for the row's approval read; the real approve verb closes it. fails-when: the sheet
# carries the decision twice, or the recap names it on two lines.
SR_D_ROW="$(sr_row T20 "Decision-gated row · complexity: standard" approval:D21 30 pending)"
sr_tick_world once "6 6 12 12"
awk -v r="$SR_D_ROW" '{ print } /^\| T17 \|/ { print r }' "$SR_PLAN" > "$SR_PLAN.t" && mv "$SR_PLAN.t" "$SR_PLAN"
# the approve verb dry-commits the plan through the commit gate, which reads the declared SDLC version
sed -i.bak 's/^wave: wave-02-fx$/&\
canonical_sdlc_version: 14/' "$SR_PLAN" && rm -f "$SR_PLAN.bak"
sr_ledger_put D21 "the gate the judge holds" "Answered in an hour rather than now, T20 starts an hour later and the predicted close holds: it is off the longest chain."
SR_REG_F="$(sr_reg)"
sr_tick
expect_eq "ON0 precondition: the tick says T20 waits on approval:D21 and opens an item for it on the register" "yes|1" \
  "$(/usr/bin/grep -q '^poker: WAIT T20 — approval:D21$' "$TMPROOT/tick.out" && echo yes)|$(/usr/bin/grep -cE '\|key=[a-z]+:D21\|state=open\|' "$SR_REG_F")"
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
sr_poke approve D21 "1" >/dev/null 2>&1
expect_eq "ON4 the approve verb closes the tick's item: nothing for D21 is left open on the register" "0" \
  "$(/usr/bin/grep -cE '\|key=[a-z]+:D21\|state=open\|' "$SR_REG_F")"

# ============================================================
section "§STEPS: a step past current: with a landed or active task is running; a pending task alone does not make it so"
# ============================================================
# fails-when: a plan at current: 5 with an active step-7 task reads step 7 pending, or a pending one reads it running.
sr_step() { sr_lines step | /usr/bin/grep -E "^step: n=$1 " | while IFS= read -r l; do printf '%s %s\n' "$(sr_f "$l" state)" "$(sr_f "$l" tasks)"; done; }
sr_world title-ahead "6 6 12 12"
sed -i.bak -e 's/^current: 4$/current: 5/' -e 's/^| T7 | 4 | build |/| T7 | 7 | build |/' "$SR_PLAN" && rm -f "$SR_PLAN.bak"
sr_run "$SR_PLAN"
expect_eq "TI1 current: 5 with T7 active at step 7: step 4 done, 5 running, 7 running with its one task, 6 pending" \
  "5|done 16|running 0|pending 0|running 1" "$(sr_val run.step)|$(sr_step 4)|$(sr_step 5)|$(sr_step 6)|$(sr_step 7)"
sr_world title-pending "6 6 12 12"
sed -i.bak -e 's/^current: 4$/current: 5/' -e 's/^| T9 | 4 | build |/| T9 | 7 | build |/' "$SR_PLAN" && rm -f "$SR_PLAN.bak"
sr_run "$SR_PLAN"
expect_eq "TI2 a pending task at step 7 is not work at step 7" "pending 1" "$(sr_step 7)"

# ============================================================
section "§NAMES: every task has one line, its description its title as the plan card prints it, whole; its note says its state in a few words"
# ============================================================
# sr_cell <id> <cell> -> SR_PLAN with that task's description cell replaced, in the Tasks table alone (a row of the
# dispatch ledger names the same id)
sr_cell() { awk -v id=" $1 " -v t="$2" -F'|' 'BEGIN { OFS = "|" } $2 == id && NF > 12 { $5 = " " t " " } { print }' "$SR_PLAN" > "$SR_PLAN.t" && mv "$SR_PLAN.t" "$SR_PLAN"; }
SR_LONG300="$(awk 'BEGIN { for (i = 1; length(s) < 300; i++) s = s (i > 1 ? " " : "") "wordnumber" i; print substr(s, 1, 300) }')"
sr_world names "6 6 12 12"
sed -i.bak -e 's#^\(| T10 | 4 | build | [^|]*| — | — | \)—#\1lib/t5.sh,lib/t6.sh,lib/t7.sh#' "$SR_PLAN" && rm -f "$SR_PLAN.bak"
sed -i.bak -e 's/^\(| T11 | .*| 30 | REQ-1 | lib\/t11.sh | — | — | \)pending/\1held/' "$SR_PLAN" && rm -f "$SR_PLAN.bak"
sr_cell T1 "$SR_LONG300"
sr_cell T13 "Alpha one (the aside). and the rest"
sr_cell T14 "Beta two: its colon. and the rest"
sr_cell T15 "Gamma three. and the rest"
sr_cell T16 "Delta four · and the rest"
sr_ev "ev=ready|row=T6|name=w-T6|commit=$SR_C1|branch=wt/02-T6|tree=$SR_REPO/.worktrees/02-T6|suites=a.test.sh|debt=-|carrier=1:x|at=2026-10-06T13:30:00Z"
sr_ev "ev=verdict|row=T7|commit=$SR_C1|suite=a.test.sh|result=red|log=/rec/T7.log|at=2026-10-06T14:00:00Z"
sr_run "$SR_PLAN"
expect_eq "NM1 a 300-character cell with no delimiter is the whole description, on the one line" "yes|1" \
  "$([ "$(sr_f "$(sr_task T1)" desc)" = "$SR_LONG300" ] && echo yes)|$(sr_lines task | /usr/bin/grep -c '^task: id=T1 ')"
expect_eq "NM2 the description is the title: it stops at the first \". \", else at the first \" · \", keeping a paren or a colon before it, and the rest of the cell never prints" \
  "Alpha one (the aside)|Beta two: its colon|Gamma three|Delta four|0" \
  "$(for t in T13 T14 T15 T16; do sr_f "$(sr_task "$t")" desc; done | sr_join)|$(printf '%s\n' "$OUT" | /usr/bin/grep -c 'and the rest')"
expect_eq "NM3 the note of each kind: done a time, next on the line, queued behind, building, red, waiting on each of three, waiting on one, held" \
  "T1 landed 3:06 AM|T8 next on the line|T6 queued behind 4/8|T5 building|T7 red|T10 waits on 4/5, 4/6 and 4/7|T9 waits on 4/8|T11 held" \
  "$(for t in T1 T8 T6 T5 T7 T10 T9 T11; do printf '%s %s\n' "$t" "$(sr_f "$(sr_task "$t")" note)"; done | sr_join)"
# a 40-task plan: one line per step and per task
SR_EXTRA=23 sr_world names-forty "6 6 12 12"
sr_run "$SR_PLAN"
expect_eq "NM4 a 40-task plan: ten step lines, forty task lines, every id once" "4 tasks, 120 of 1290 min, 9%|10|40|40" \
  "$(sr_m work.landed)|$(sr_lines step | /usr/bin/grep -c .)|$(sr_lines task | /usr/bin/grep -c .)|$(sr_tasks_f id | sort -u | /usr/bin/grep -c .)"

# ============================================================
section "§HELD-NOTE: a task held on you says what it waits on, whether it is building or not yet started"
# ============================================================
# FIXTURE FIDELITY: the decisions put in the shape `decisions put` writes them into the design ledger, the world's plan
# bound by the bind verb. fails-when: a task that has started and reads an approval still owed says building.
sr_world heldnote "6 6 12 12"
sr_bind
printf '# Design ledger — wave-02-fx\n\n## Δ0 — D1 put (orchestrator 2026-10-20 6:44 AM PDT): the stop rule\n\nAnswered now or in an hour.\n## Δ1 — D2 put (orchestrator 2026-10-20 6:45 AM PDT): the second rule\n\nAnswered now or in an hour.\n' > "$SR_DIR/design-ledger.md"
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
# One constant: a mutant tree whose lib/line.sh sets the bar to 25 moves the scorecard's target.
SR_MUT="$TMPROOT/mut"; mkdir -p "$SR_MUT/payload"
cp -R "$BIONIC_HOOKS_DIR" "$SR_MUT/hooks" && cp -R "$BIONIC_HOOKS_DIR/../payload/scripts" "$SR_MUT/payload/scripts"
sed 's/^LINE_LANDING_BAR=15$/LINE_LANDING_BAR=25/' "$BIONIC_HOOKS_DIR/../payload/scripts/lib/line.sh" > "$SR_MUT/payload/scripts/lib/line.sh"
sr_world bar-plant-mut "20 20 20 20"
SR_MUT_SC="$(sr_poke_with "$SR_MUT/hooks/session-poker.sh" landing-report --scorecard "$SR_PLAN")"
expect_eq "SCO3 a mutant bar of 25 moves the scorecard's target" \
  "widest landing ready→landed: T1 20.0 min · target < 25" "$(printf '%s\n' "$SR_MUT_SC" | /usr/bin/grep '^widest landing ')"

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
sed -e 's/^\(| T20 | .*| \)held\( | — | — | — |\)$/\1landed\2/' "$SR_PLAN" > "$SR_PLAN.t" && mv "$SR_PLAN.t" "$SR_PLAN"
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
  sr_owed "key=waive:adversarial|state=open|sent=-|at=2026-10-06T20:01:00Z|title=waiver: adversarial|reply=poker: the adversarial review failed at the head"
  ( cd "$SR_REPO" && OWED_ROOT="$SR_REPO" OWED_SID="$SID" OWED_PLAN="$SR_PLAN" bash -c '. "$1" && owed_answer "$2" no "$3"' _ "$SR_OWED_LIB" waive:adversarial "review adversarial re-run" )
  [ "$2" != yes ] || sr_owed "key=approve:release|state=open|sent=-|at=2026-10-06T20:00:00Z|title=approval: release|reply=poker: WAIT T12 — approval:release"
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
section "§FAST: the sheet verb and the card verb, run one after the other on a copy of the wave-43 plan and its record, finish together in under 5 seconds; the card verb reads the saved sheet and refreshes its asks from the register alone"
# ============================================================
# FIXTURE FIDELITY: a shipped 35-task plan and its whole record, copied into a repository of their own because the
# verbs write the repository's tmp folder and settle its register; the clock is the end of that run. The card verb is
# timed with a judgment on its stdin that the card refuses, since drawing is card.sh's and its judgment is not this
# section's subject; the verb's own work is what is timed. A second tree has card.sh replaced by a stub that keeps the sheet it was
# handed, and sitrep_gather counted, so the sheet the card draws from is read and the one gather is proved.
# fails-when: the two verbs together take 5 seconds or more, the card verb gathers a second time, or the sheet the card
# draws from carries the asks as they stood when the sheet was saved rather than as they stand now.
# The docs tree lives beside the repository, not in a checkout of it: this checkout when it holds one, else the
# main checkout the git directory belongs to (a landing checkout holds none).
SR_FAST_SRC="$BIONIC_HOOKS_DIR/../.bionic/docs"
[ -d "$SR_FAST_SRC" ] || SR_FAST_SRC="$(cd "$(git -C "$BIONIC_HOOKS_DIR" rev-parse --git-common-dir 2>/dev/null)/.." 2>/dev/null && pwd -P)/.bionic/docs"
SR_FAST_PLAN_REL="plans/epic-23-bionic-tech-debt/wave-43-no-hand-hold.plan.md"
SR_FAST_REC_REL="record/wave-43-no-hand-hold"
expect_true "FA0 precondition: the wave-43 plan and its record are on this tree" test -f "$SR_FAST_SRC/$SR_FAST_PLAN_REL" -a -d "$SR_FAST_SRC/$SR_FAST_REC_REL"
SR_REPO="$TMPROOT/fast"; mkdir -p "$SR_REPO/.bionic/tmp" "$SR_REPO/.bionic/docs/plans/epic-23-bionic-tech-debt" "$SR_REPO/.bionic/docs/record"
( cd "$SR_REPO" && git init -q . 2>/dev/null )
cp "$SR_FAST_SRC/$SR_FAST_PLAN_REL" "$SR_REPO/.bionic/docs/$SR_FAST_PLAN_REL"
cp -R "$SR_FAST_SRC/$SR_FAST_REC_REL" "$SR_REPO/.bionic/docs/$SR_FAST_REC_REL"
SR_PLAN="$SR_REPO/.bionic/docs/$SR_FAST_PLAN_REL"
SR_GATE="$TMPROOT/gate-fast"; mkdir -p "$SR_GATE/requests" "$SR_GATE/cost"
SR_FAST_AT=1792739640     # 2026-10-23T07:14:00Z, the end of that run
SR_FAST_J="$TMPROOT/fast-judgment.txt"; printf 'call: Nothing is owed.\n' > "$SR_FAST_J"
sr_ms() { perl -MTime::HiRes=time -e 'printf "%d\n", time * 1000'; }
SR_FA_T0="$(sr_ms)"
SR_AT="$SR_FAST_AT" sr_run "$SR_PLAN"
SR_FA_RC1="$RC"; SR_FA_SHEET="$OUT"
SR_AT="$SR_FAST_AT" sr_run card "$SR_PLAN" < "$SR_FAST_J"
SR_FA_RC2="$RC"; SR_FA_ERR2="$ERR"
SR_FA_T1="$(sr_ms)"
expect_eq "FA1 the sheet verb prints the sheet (rc 0, a first line, the wave's own open asks among them)" "0|$SR_HEAD|yes" \
  "$SR_FA_RC1|$(printf '%s\n' "$SR_FA_SHEET" | head -1)|$(printf '%s\n' "$SR_FA_SHEET" | /usr/bin/grep -q '^ask: key=finding:' && echo yes)"
expect_eq "FA2 the card verb read the saved sheet and ran the check: it refused the judgment (rc 1), and said nothing of a sheet that is missing or old" "1|0" \
  "$SR_FA_RC2|$(printf '%s\n' "$SR_FA_ERR2" | /usr/bin/grep -c 'the sheet you wrote from')"
expect_eq "FA3 the two verbs, one after the other on the wave-43 plan, finish in under 5 seconds" "yes" \
  "$([ $((SR_FA_T1 - SR_FA_T0)) -lt 5000 ] && echo yes || echo "no: $((SR_FA_T1 - SR_FA_T0)) ms")"
# the stub tree: card.sh keeps the sheet it was handed; sitrep_gather counts its calls
SR_FM="$TMPROOT/fast-mut"; mkdir -p "$SR_FM/payload"
cp -R "$BIONIC_HOOKS_DIR" "$SR_FM/hooks" && cp -R "$BIONIC_HOOKS_DIR/../payload/scripts" "$SR_FM/payload/scripts"
sed 's|^sitrep_gather() {$|sitrep_gather() { [ -z "${SR_GATHER_MARK:-}" ] \|\| echo gather >> "$SR_GATHER_MARK";|' "$BIONIC_HOOKS_DIR/poker/sitrep.sh" > "$SR_FM/hooks/poker/sitrep.sh"
printf '#!/bin/bash\ncat "$2" > "$SR_CARD_KEPT"\necho drawn\n' > "$SR_FM/payload/scripts/card.sh"
expect_eq "FA4 precondition: the counting plant took effect (the shipped file and the plant differ)" "yes" \
  "$(cmp -s "$BIONIC_HOOKS_DIR/poker/sitrep.sh" "$SR_FM/hooks/poker/sitrep.sh" || echo yes)"
SR_FA_MARK="$TMPROOT/fast-gathers"; SR_FA_KEPT="$TMPROOT/fast-kept"; : > "$SR_FA_MARK"
export SR_GATHER_MARK="$SR_FA_MARK" SR_CARD_KEPT="$SR_FA_KEPT"
SR_AT="$SR_FAST_AT" sr_poke_with "$SR_FM/hooks/session-poker.sh" sitrep "$SR_PLAN" > "$TMPROOT/fast-sheet2.out" 2>/dev/null
SR_FA_G1="$(/usr/bin/grep -c gather "$SR_FA_MARK")"
# an ask opened after the sheet was saved, and one answered no; neither is in the saved sheet
sr_owed "key=approve:release|state=open|sent=-|at=2026-10-23T07:10:00Z|title=approval: release|reply=poker: WAIT T12 — approval:release"
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
section "§SKILL: the sitrep skill reads the sheet and shows only the card the card verb printed; it never tells the model to show the sheet"
# ============================================================
# FIXTURE FIDELITY: the shipped skill text, read in place; each plant is a scratch copy of it with one line appended.
# fails-when: the skill text tells the model to show the sheet, or to show anything but the card verb's output.
SR_SKILL="$BIONIC_SKILLS_DIR/sitrep/SKILL.md"
sr_show_lines() {  # <skill file> -> every line that tells the model to show something (show, shows, display), a negated show cut first
  awk '{ l = tolower($0); gsub(/(never|not|n.t) (show|display)/, "", l) } l ~ /(^|[^a-z])(shows?|display)([^a-z]|$)/ { print }' "$1"
}
sr_show_bad() {  # <skill file> -> each show line that shows the sheet or the page, or anything but the card
  sr_show_lines "$1" | awk '{ l = tolower($0) } l ~ /sheet|page/ || l !~ /card/ { print }'
}
expect_contains "SK0 the skill runs the sheet verb" 'hooks/session-poker.sh sitrep' "$(cat "$SR_SKILL")"
expect_contains "SK0b …and the card verb, the judgment on its stdin" 'hooks/session-poker.sh sitrep card <<' "$(cat "$SR_SKILL")"
expect_eq "SK0c the skill offers no plan operand (D13: the sitrep takes no argument)" "0" "$(/usr/bin/grep -c '\[<plan>\]' "$SR_SKILL")"
expect_nonempty "SK1 the skill has lines that say what to show (the extractor reads the real text)" "$(sr_show_lines "$SR_SKILL")"
expect_eq "SK1b …one of them shows the card exactly as printed, in one fenced code block, with nothing after it" "1" \
  "$(sr_show_lines "$SR_SKILL" | /usr/bin/grep -i 'card' | /usr/bin/grep -i 'exactly as printed' | /usr/bin/grep -i 'one fenced code block' | /usr/bin/grep -ci 'nothing after')"
expect_eq "SK2 the sheet is named as the model's input, never shown" "1" \
  "$(/usr/bin/grep -i 'sheet' "$SR_SKILL" | /usr/bin/grep -i 'input' | /usr/bin/grep -ci 'never show')"
expect_empty "SK3 no line of the skill shows the sheet, the page or anything but the card (SK1 read the same lines)" "$(sr_show_bad "$SR_SKILL")"
for sr_plant in 'Show the sheet to the user.' 'Then show its page inside one fenced code block.' 'Show the card and the sheet beside it.' 'Display the facts as a list.'; do
  cp "$SR_SKILL" "$TMPROOT/skill-plant.md"; printf '%s\n' "$sr_plant" >> "$TMPROOT/skill-plant.md"
  expect_eq "SK4 a planted '$sr_plant' is found" "$sr_plant" "$(sr_show_bad "$TMPROOT/skill-plant.md")"
done
# The card places each ask from the fact: a held ask under Blocked on you, an unheld one under the Assessment, and
# Blocked on you reads None when nothing is held. The skill says so, in the model's own register.
expect_eq "SK4b the skill says the card puts a held ask under Blocked on you, an unheld one under the Assessment, and Blocked on you is None when nothing is held" "1|1" \
  "$(/usr/bin/grep -i 'blocked on you' "$SR_SKILL" | /usr/bin/grep -i 'held' | /usr/bin/grep -i 'assessment' | /usr/bin/grep -ci 'none')|$(/usr/bin/grep -i 'ask <key>' "$SR_SKILL" | /usr/bin/grep -i 'never choose' | /usr/bin/grep -ci 'section')"
# The skill weighs measurements: each fact states what it measures, and two are compared only when they share a unit.
# Pace is the work landed against the forecast time used, the grade's rubric is that same comparison, and the close's
# basis is said in words. The example judgment states the sheet's measurements, never the plan's allowance.
expect_eq "SK5 each fact states what it measures; compare only measurements that share a unit" "1" \
  "$(/usr/bin/grep -i 'what it measures' "$SR_SKILL" | /usr/bin/grep -ci 'share a unit')"
expect_eq "SK6 the Pace question is pace.work-landed against pace.time-used" "1" \
  "$(/usr/bin/grep -F '**Pace.**' "$SR_SKILL" | /usr/bin/grep -F 'pace.work-landed' | /usr/bin/grep -cF 'pace.time-used')"
expect_eq "SK7 the rubric: on pace when pace.work-landed is at least pace.time-used, behind when lower" "1" \
  "$(/usr/bin/grep -i 'on pace' "$SR_SKILL" | /usr/bin/grep -F 'pace.work-landed' | /usr/bin/grep -F 'pace.time-used' | /usr/bin/grep -ci 'behind')"
expect_eq "SK8 the close row is the condition in words, and the card draws the basis" "1" \
  "$(/usr/bin/grep -F 'close:' "$SR_SKILL" | /usr/bin/grep -i 'basis' | /usr/bin/grep -ci 'in words')"
# The example is the seven lines of the judgment and nothing else: code draws the Metrics, so the example holds no
# metric: or task: line and does not restate the Pace; it opens on the purpose.
sr_example() {  # <skill file> -> the lines of the skill's one example judgment, between the heredoc and its terminator
  awk '/<<.JUDGMENT.$/ { f = 1; next } /^ *JUDGMENT$/ { f = 0 } f { sub(/^ +/, ""); print }' "$1"
}
expect_eq "SK9 the example judgment is seven lines, opens on purpose:, and holds no metric: or task: line" "7|purpose|0" \
  "$(sr_example "$SR_SKILL" | /usr/bin/grep -c .)|$(sr_example "$SR_SKILL" | head -1 | cut -d: -f1)|$(sr_example "$SR_SKILL" | /usr/bin/grep -cE '^(metric|task):')"
sed 's/^\( *\)grade: .*/\1grade: B\n\1metric: Pace: 37% of the work landed in 60% of the time./' "$SR_SKILL" > "$TMPROOT/skill-plant.md"
expect_eq "SK9b a planted metric: line in the example is found (SK9 read the same lines)" "1" \
  "$(sr_example "$TMPROOT/skill-plant.md" | /usr/bin/grep -cE '^(metric|task):')"

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
