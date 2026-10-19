#!/bin/bash
# Tests for `hooks/session-poker.sh sitrep` — the situation report's renderer (wave-38 T10; REQ-2
# AC-2.2 to AC-2.8; design-ledger Δ0–Δ8, D9–D14).
#
# THE VERB PRINTS THE FACT HALF OF THE REPORT. Bottom line (the last recorded judgment, with its time),
# Situation (every row of ## Tasks, a glyph in column 1), Assessment (three indicators by thresholds
# printed on the page; the schedule one against the clock and the 15-minute bar, wave-39 T9), Blockers (the person's open owed items), Forecast (percent, closing time from
# measured pace, basis, the waits assumption). `--line` is the patrol's one-line form, and
# `sitrep bottom-line '<item>'…` records the judgment items to record/<wave>/sitrep.log. The skill
# that fills the judgment slots is T11's (skills/sitrep/SKILL.md); its sections, §ORDER, §FACTS and §SURFACES,
# follow §ARGS below.
#
# HERMETIC. One repository per world under a temp root: a 17-row plan, its landing record, its fill
# ledger, the session's owed store and a gate store of its own. The clock is BIONIC_NOW_EPOCH (the
# poker's seam, fill-report's too) and the zone is pinned, so every local time below is a fixed
# string; no case reads this machine's clock. The machine's probes are pinned as the session-poker
# prelude pins them, because the gate's scan samples them.
#
# FIXTURE FIDELITY. SYNTHESIZED, in the shapes the writers write: the landing record's `line/v1`
# events as lib/line.sh writes them (the shapes tests/session-poker-4.test.sh §REPORT-RTL plants),
# the fill ledger's `fill-ledger/v1` lines as lib/stop.sh writes them (measured on
# record/wave-37-landing-pace/fill-ledger.log), the owed store's `owed/v1` lines as lib/owed.sh
# writes them (one line per key), the gate's request files as lib/gate.sh writes them, and the
# plan's `## Tasks` header copied from wave-38-one-stop.plan.md. What each world pins is what the
# indicator under test reads, and nothing it does not: the landing minutes, the declared sizes, the
# verdicts, the idle turns, the open items, the admitted requests.
#
# ANTI-VACUITY. Every mark is asserted in a clean world first (M0–M2, L1) and then moved by one
# planted defect (M3–M9, L2); each absence (R6, R8, B2's closed item) sits beside a positive read
# through the same extractor on the same render. The row extractor is proved non-empty by R3.
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
# SR_DIR, SR_GATE. Seventeen rows, all Step 4 builds: T1–T4 landed (sizes 5 5 10 10, so the median
# declared is 7.5), T5–T8 active, T9–T17 pending. T9 reads lib/t8.sh, which T8 writes, so the remaining
# chain is T8→T9 (90 + 60 = 150 min); every other open row is 30 min and reads nothing of another's.
# T12 reads approval:release and T17 approval:merge. With `none`, T1–T4 are pending too and the
# landing record holds no landing. Two gate requests are admitted and held by this shell, so the
# gate's admitted count is 2.
# THE CLOCK (wave-39 T9; D25): the plan is approved at 10:00Z (its `approved-by:` instant, 12 hours before
# NOW; SR_APPROVED=none leaves the line out, an unapproved plan) and declares `forecast: $SR_FORECAST` (48h when
# unset; an empty SR_FORECAST declares none). SR_EXTRA
# appends that many more pending 30-minute rows (T18…), reading nothing, so the plan's total grows and the
# chain does not.
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
    [ -z "${SR_FORECAST-48h}" ] || printf 'forecast: %s\n' "${SR_FORECAST-48h}"
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
      i=$((i + 1))
    done
  fi
  sr_ev "ev=ready|row=T8|name=w-T8|commit=$SR_C1|branch=wt/02-T8|tree=$r/.worktrees/02-T8|suites=a.test.sh|debt=-|carrier=1:x|at=2026-10-06T13:00:00Z"
  {
    printf '\n## Tasks\n\n'
    printf '| id | step | kind | task | agent | deps | reads | size | serves | Files | worktree | base | status | suites | lands-on | artifact |\n'
    printf '|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|\n'
    sr_row T1 "Row one the thing (D1; AC-1.1). More words · complexity: standard" — 5 "$st1"
    sr_row T2 "Haiku 5.5 at high (REQ-8; AC-8.1) · complexity: standard" — 5 "$st1"
    sr_row T3 "Third row. A second sentence · complexity: standard" — 10 "$st1"
    sr_row T4 "Fourth · complexity: complex" — 10 "$st1"
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
sr_owed() {  # <owed/v1 fields after the schema> -> one line in the session's owed store
  printf 'owed/v1|%s\n' "$1" >> "$SR_REPO/.bionic/tmp/owed-$SID.state"
}
# sr_prev <minutes> -> a delivered plan beside this one (wave-01-prev, T1 of 60 min declared) whose
# landing record lands T1 in <minutes>: the previous wave's measured ratio is <minutes> / 60.
sr_prev() {
  local p="$SR_REPO/.bionic/docs/plans/epic-01-fx/wave-01-prev.plan.md" d="$SR_REPO/.bionic/docs/record/wave-01-prev"
  mkdir -p "$d"
  {
    printf -- '---\nwave: wave-01-prev\nrelease: 9.8.0\n---\n# prev\n\n## SDLC State\n\ncurrent: 9\n\n'
    printf -- '- Step 9: delivered: 2026-10-05T20:00Z wave-01-prev 9.8.0 — closed by close-out.sh\n'
    printf '\n## Tasks\n\n| id | step | kind | task | agent | deps | reads | size | serves | Files | worktree | base | status | suites | lands-on | artifact |\n'
    printf '|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|\n'
    printf '| T1 | 4 | build | Prev row · complexity: standard | — | — | — | 60 | REQ-1 | lib/p1.sh | — | — | landed | — | — | — |\n'
  } > "$p"
  {
    printf 'line/v1|ev=ready|row=T1|name=p-T1|commit=%s|branch=wt/01-T1|tree=%s/.worktrees/01-T1|suites=a.test.sh|debt=-|carrier=1:x|at=2026-10-05T10:00:00Z\n' "$SR_C1" "$SR_REPO"
    printf 'line/v1|ev=published|row=T1|commit=%s|kind=queue|by=-|why=-|at=%s\n' "$SR_C1" "$(sr_iso $((SR_E0 - 86400 + $1 * 60)))"
  } > "$d/landing-proofs.log"
}
sr_run() {  # <args after the verb…> -> OUT (stdout), ERR (stderr), RC; the world's plan is named last by the caller
  ( cd "$SR_REPO" && exec env CLAUDE_CODE_SESSION_ID="$SID" BIONIC_NOW_EPOCH="${SR_AT:-$SR_NOW}" BIONIC_GATE_DIR="$SR_GATE" \
      bash "$POKER" sitrep "$@" ) > "$TMPROOT/sr.out" 2> "$TMPROOT/sr.err"
  RC=$?
  OUT="$(cat "$TMPROOT/sr.out")"; ERR="$(cat "$TMPROOT/sr.err")"
}
sr_poke() { sr_poke_with "$POKER" "$@"; }
sr_poke_with() {  # <poker> <verb args…> -> the verb run in the world, as sr_run runs it
  local pk="$1"; shift
  ( cd "$SR_REPO" && exec env CLAUDE_CODE_SESSION_ID="$SID" BIONIC_NOW_EPOCH="${SR_AT:-$SR_NOW}" BIONIC_GATE_DIR="$SR_GATE" bash "$pk" "$@" )
}
sr_line() { printf '%s\n' "$OUT" | /usr/bin/grep -E "^$1" | head -1; }
sr_sit() {  # -> the Situation's lines: from the counts header's next line to the first blank
  printf '%s\n' "$OUT" | awk '/^[0-9]+ landed · / { on = 1; next } on && /^$/ { exit } on { print }'
}
sr_rows() { sr_sit | /usr/bin/grep -E '^[^ ]+ [^ /]+/[^ ]+: '; }   # -> its row lines, `<glyph> <step>/<row>: …`
sr_steps() { sr_sit | /usr/bin/grep -E '^[^ ]+ [0-9]+: '; }        # -> its step lines, `<glyph> <step>: …`
# THE MARKS, from one place: a measurement held against a bar is within it, near it, over it, or not measurable
# (D31). The next re-mark is these four lines. The legend prints once, under the three indicator lines (D29).
SR_MARK_WITHIN='✅'
SR_MARK_NEAR='➖'
SR_MARK_OVER='✖️'
SR_MARK_NONE='❔'
SR_LEGEND='within / near / over — schedule at or ahead of the pace its forecast needs and the median landing at or under the bar / either within 1.25× / further · correctness no red at head and no open S1/S2 / reds all returned and fixed / an open S1/S2 or a red at head · waste < 5% discarded and < 10% idle / < 15% either / above'
# sr_ind <name> -> the indicator's line: the mark leads, then the name
sr_ind() { printf '%s\n' "$OUT" | /usr/bin/grep -E "^[^ ]+ $1 " | head -1; }

# ============================================================
section "§ROWS: every row of ## Tasks, glyph in column 1, [step]/[task]: desc, landed rows with a local 12-hour time, and the counts header (AC-2.3, D14, Δ5)"
# ============================================================
sr_world rows "6 6 12 12"
sr_run "$SR_PLAN"
expect_eq "R0 sitrep <plan> exits 0 with nothing on stderr" "0|" "$RC|$ERR"
expect_eq "R1 the title line: Sitrep · wave · release · local date and time · step" \
  "Sitrep · wave-02-fx · 9.9.0 · 2026-10-06 3:00 PM PDT · step 4" "$(printf '%s\n' "$OUT" | head -1)"
expect_eq "R2 the counts header" "4 landed · 4 in flight · 9 not started · 0 red/blocked of 17" "$(sr_line '[0-9]+ landed · ')"
SR_ROWS="$(sr_rows)"
expect_eq "R3 seventeen row lines, contiguous under the header" "17" "$(printf '%s\n' "$SR_ROWS" | /usr/bin/grep -c .)"
expect_eq "R4 every row line opens with one of the four glyphs in column 1, then [step]/[task]:" "17" \
  "$(printf '%s\n' "$SR_ROWS" | /usr/bin/grep -cE '^(✅|🔄|⬜|⛔) 4/T[0-9]+: ')"
expect_eq "R5 the rows in execution order (wave-39 T10; AC-6.3): landed by time, then in flight by their place on the line, then pending in dependency order; each glyph by status, the description cut at its first ( . or ·, its time or state in parentheses" \
  "✅ 4/T1: Row one the thing (3:06 AM)|✅ 4/T2: Haiku 5.5 at high (3:36 AM)|✅ 4/T3: Third row (4:12 AM)|✅ 4/T4: Fourth (5:12 AM)|🔄 4/T8: The long one (next on the line)|🔄 4/T5: Row 5 body (building)|🔄 4/T6: Row 6 body (building)|🔄 4/T7: Row 7 body (building)|⬜ 4/T9: Waits on the long one (waits on T8)|⬜ 4/T10: Row 10 body (not started)|⬜ 4/T11: Row 11 body (not started)|⬜ 4/T13: Row 13 body (not started)|⬜ 4/T14: Row 14 body (not started)|⬜ 4/T15: Row 15 body (not started)|⬜ 4/T16: Row 16 body (not started)|⬜ 4/T12: Release-gated row (waits on approval:release)|⬜ 4/T17: Merge-gated row (waits on approval:merge)" \
  "$(printf '%s\n' "$SR_ROWS" | tr '\n' '|' | sed 's/|$//')"
expect_eq "R6 no UTC instant anywhere on the page (no ISO Z time, no UTC word)" "" \
  "$(printf '%s\n' "$OUT" | /usr/bin/grep -E '[0-9]{2}:[0-9]{2}(:[0-9]{2})?Z|UTC')"
expect_eq "R7 the section headings, title case, in order, no rule line" \
  "Bottom line — none recorded yet|Situation|Assessment|Blockers|Forecast" \
  "$(printf '%s\n' "$OUT" | /usr/bin/grep -E '^(Bottom line|Situation|Assessment|Blockers|Forecast)' | tr '\n' '|' | sed 's/|$//')"
expect_eq "R8 …and no line of rule characters" "" "$(printf '%s\n' "$OUT" | /usr/bin/grep -E '^[-=─━_]{3,}$')"
# A landing on another day than now's carries its local date after the time.
SR_AT=$((SR_NOW + 86400)) sr_run "$SR_PLAN"
expect_eq "R9 a landing on another local day than now's: H:MM AM/PM then its local date" \
  "✅ 4/T1: Row one the thing (3:06 AM 2026-10-06)" "$(sr_rows | head -1)"

# ============================================================
section "§SHAPES — wave-39 T10 (D14; AC-6.1): a landed row is timed from whichever shape its step line has, landed <sha> <ISO>, landed-by-hand: <who> <ISO> \"<why>\", or either after text; over wave 38's plan all 38 landed rows print a time"
# ============================================================
# FIXTURE FIDELITY. The `- Step` and `- T<n>:` lines below are wave-38-one-stop.plan.md's `## SDLC State` lines,
# byte for byte as the run left them at close (record/wave-38-one-stop; the AC-2.3 walk found 16 of its 27 landed
# rows untimed then). Its `## Tasks` table is synthesized: each row's id, step and kind as wave 38's table holds
# them, status landed, the task cell a stand-in. The landing record is empty, so every time on the page is the
# step line's own.
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
expect_eq "SH0 precondition: wave 38's plan renders (rc 0), its 38 rows all landed, read by the counts header" \
  "0|38 landed · 0 in flight · 0 not started · 0 red/blocked of 38" "$RC|$(sr_line '[0-9]+ landed · ')"
expect_eq "SH0b precondition: the fixture holds the three shapes — bare, text before landed, landed-by-hand (lead and after text)" "yes|yes|yes|yes" \
  "$(sr_w38_lines | /usr/bin/grep -qE '^- T1: landed [0-9a-f]{40} ' && echo yes)|$(sr_w38_lines | /usr/bin/grep -qE '^- T2: reason: .* landed [0-9a-f]{40} ' && echo yes)|$(sr_w38_lines | /usr/bin/grep -qE '^- T12: landed-by-hand: ' && echo yes)|$(sr_w38_lines | /usr/bin/grep -qE '^- T3: reason: .* landed-by-hand: ' && echo yes)"
expect_eq "SH1 38 of 38 landed rows print a time" "38" \
  "$(sr_rows | /usr/bin/grep -cE '^✅ [0-9]+/T[0-9]+: .* \([0-9]{1,2}:[0-9]{2} [AP]M( [0-9]{4}-[0-9]{2}-[0-9]{2})?(, by hand)?\)$')"
expect_eq "SH2 the bare shape, landed <sha> <ISO>: T1 at its local time" \
  "✅ 4/T1: Row 1 of wave 38 (2:08 AM 2026-10-16)" "$(sr_rows | /usr/bin/grep '/T1: ')"
expect_eq "SH3 text before landed <sha> <ISO>: T2 at its landing's time, not the reason's" \
  "✅ 4/T2: Row 2 of wave 38 (12:06 PM 2026-10-16)" "$(sr_rows | /usr/bin/grep '/T2: ')"
expect_eq "SH4 landed-by-hand: <who> <ISO> \"<why>\" as the lead: T12 at its time, said by hand" \
  "✅ 4/T12: Row 12 of wave 38 (2:22 PM 2026-10-17, by hand)" "$(sr_rows | /usr/bin/grep '/T12: ')"
expect_eq "SH5 landed-by-hand after text, its who holding parentheses: T3 at its time, by hand" \
  "✅ 4/T3: Row 3 of wave 38 (2:22 PM 2026-10-17, by hand)" "$(sr_rows | /usr/bin/grep '/T3: ')"
expect_eq "SH6 two reason: clauses before the landing, one saying lands and one landed with no sha after it: T28 at its landing's time" \
  "✅ 8/T28: Row 28 of wave 38 (8:07 AM 2026-10-18)" "$(sr_rows | /usr/bin/grep '/T28: ')"

# ============================================================
section "§ORDER (wave-39 T10; A-orch-19; AC-6.3): the Situation lists steps 0 to 3 with their approval times, then every row in execution order — landed by landing time, hand landings included; in flight by their place on the line with what each is doing; pending in dependency order with what each waits on"
# ============================================================
# The world: §ROWS' fixture, re-landed out of table order (T2 3:36, T3 by hand 3:50, T1 4:00, T4 5:12), its four
# attended steps approved, T8 in its landing with one of its two suites green, T6 and T5 queued behind it, T7
# building, and T10 reading what T11 writes so that dependency order puts T11 first.
sr_world order-run "60 6 12 12"
awk '
  /^- Step 4: / {
    print "- Step 0: configured at 2026-10-06T08:00Z; approved by fixture 2026-10-06T08:10Z \"approved\" at the Step-0 card"
    print "- Step 1: requirements: specs/x.requirements.md; approved by fixture 2026-10-06T08:40Z \"approved\" at the Step-1 card"
    print "- Step 2: spec: specs/x.spec.md; frame approved at 2026-10-06T08:50Z; approved by fixture 2026-10-06T09:20Z \"approved\" at the Step-2 card"
    print "- Step 3: plan: this file; approved by fixture 2026-10-06T10:00Z \"approved\" at the Step-3 card"
  }
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
expect_eq "ORD0 precondition: the world renders (rc 0) and its counts are §ROWS' own" \
  "0|4 landed · 4 in flight · 9 not started · 0 red/blocked of 17" "$RC|$(sr_line '[0-9]+ landed · ')"
expect_eq "ORD1 the Situation opens on steps 0 to 3, each with its approval time (the approved by instant, not an earlier approved)" \
  "✅ 0: Configure (approved 1:10 AM)|✅ 1: Scope (approved 1:40 AM)|✅ 2: Design (approved 2:20 AM)|✅ 3: Plan (approved 3:00 AM)" \
  "$(sr_sit | head -4 | tr '\n' '|' | sed 's/|$//')"
expect_eq "ORD2 …then the landed rows by landing time, each with it, the hand landing in its place" \
  "✅ 4/T2: Haiku 5.5 at high (3:36 AM)|✅ 4/T3: Third row (3:50 AM, by hand)|✅ 4/T1: Row one the thing (4:00 AM)|✅ 4/T4: Fourth (5:12 AM)" \
  "$(sr_sit | sed -n '5,8p' | tr '\n' '|' | sed 's/|$//')"
expect_eq "ORD3 …then the rows in flight by their place on the line, each saying what it is doing" \
  "🔄 4/T8: The long one (in its landing, 1 of 2 suites green)|🔄 4/T6: Row 6 body (queued on the line behind T8)|🔄 4/T5: Row 5 body (queued on the line behind T6)|🔄 4/T7: Row 7 body (building)" \
  "$(sr_sit | sed -n '9,12p' | tr '\n' '|' | sed 's/|$//')"
expect_eq "ORD4 …then the pending rows in dependency order, T11 before T10 which reads what it writes, each waiting row saying on what" \
  "⬜ 4/T9: Waits on the long one (waits on T8)|⬜ 4/T11: Row 11 body (not started)|⬜ 4/T10: Row 10 body (waits on T11)|⬜ 4/T13: Row 13 body (not started)|⬜ 4/T14: Row 14 body (not started)|⬜ 4/T15: Row 15 body (not started)|⬜ 4/T16: Row 16 body (not started)|⬜ 4/T12: Release-gated row (waits on approval:release)|⬜ 4/T17: Merge-gated row (waits on approval:merge)" \
  "$(sr_sit | sed -n '13,$p' | tr '\n' '|' | sed 's/|$//')"
expect_eq "ORD5 …and nothing else: 4 steps and 17 rows, one line each" "21|4|17" \
  "$(sr_sit | /usr/bin/grep -c .)|$(sr_steps | /usr/bin/grep -c .)|$(sr_rows | /usr/bin/grep -c .)"
# A step with no approval instant on its line says so; one not reached is not started.
awk '/^- Step 2: / { print "- Step 2: spec: specs/x.spec.md; frame approved at the card"; next } { print }' "$SR_PLAN" > "$SR_PLAN.t" && mv "$SR_PLAN.t" "$SR_PLAN"
sr_run "$SR_PLAN"
expect_eq "ORD6 a passed step whose line names no approval instant says so, its neighbours still timed" \
  "✅ 1: Scope (approved 1:40 AM)|✅ 2: Design (done, no approval time on its line)|✅ 3: Plan (approved 3:00 AM)" \
  "$(sr_steps | sed -n '2,4p' | tr '\n' '|' | sed 's/|$//')"


# ============================================================
section "§MARKS: three indicators, each line opening on its mark (✅ within · ➖ near · ✖️ over · ❔ not measurable) then its number, the thresholds printed once under the three; a planted defect moves its mark (AC-2.4, D10, D29, D31)"
# ============================================================
sr_world marks "6 6 12 12"
sr_run "$SR_PLAN"
expect_eq "M0 the clean world: schedule ✅, 4 of 17 landed in the 12 hours since approval where a 48-hour forecast needs 4, and the median ready→landed 9m (landing-report's) under the 15m bar, the mark first, no legend on the line" \
  "$SR_MARK_WITHIN schedule — 4 of 17 landed in 12h, pace needs 4 · median ready→landed 9m over the 15m bar" "$(sr_ind schedule)"
expect_eq "M1 …correctness ✅, no red, no open S1/S2" \
  "$SR_MARK_WITHIN correctness — no red run at head, no open S1/S2" "$(sr_ind correctness)"
expect_eq "M2 …waste ✅, nothing discarded, nothing idle" \
  "$SR_MARK_WITHIN waste 0% discarded · 0% idle-width" "$(sr_ind waste)"
expect_eq "M2a the legend prints once, as one line directly under the third indicator, inside the Assessment, byte for byte" \
  "$SR_LEGEND" "$(printf '%s\n' "$OUT" | awk '/^Assessment$/ { f = 1; next } f && /^[^ ]+ waste / { w = 1; next } w { print; exit }')"
expect_eq "M2b …and nowhere else: one line of the page opens on within / near / over, no indicator line carries a parenthesised bar" "1|0" \
  "$(printf '%s\n' "$OUT" | /usr/bin/grep -c '^within / near / over')|$(printf '%s\n' "$OUT" | /usr/bin/grep -E '^[^ ]+ (schedule|correctness|waste) ' | /usr/bin/grep -c '(')"
expect_eq "M2c …each indicator line opens on one of the four marks, then its name" "3" \
  "$(printf '%s\n' "$OUT" | /usr/bin/grep -cE "^($SR_MARK_WITHIN|$SR_MARK_NEAR|$SR_MARK_OVER|$SR_MARK_NONE) (schedule|correctness|waste) ")"
# A planted red run, not returned: correctness over its bar, and the row it is on reads ⛔.
sr_ev "ev=verdict|row=T8|commit=$SR_C1|suite=a.test.sh|result=red|log=/rec/T8.log|at=2026-10-06T14:00:00Z"
sr_run "$SR_PLAN"
expect_eq "M3 a planted red run at head → correctness ✖️" \
  "$SR_MARK_OVER correctness — 1 red at head, no open S1/S2" "$(sr_ind correctness)"
expect_eq "M4 …the row it is on reads ⛔, and the counts move it out of in flight" \
  "⛔ 4/T8: The long one (next on the line)|4 landed · 3 in flight · 9 not started · 1 red/blocked of 17" \
  "$(sr_rows | /usr/bin/grep 'T8:')|$(sr_line '[0-9]+ landed · ')"
# The red returned: a later green on the same row and suite.
sr_ev "ev=verdict|row=T8|commit=$SR_C1|suite=a.test.sh|result=green|log=/rec/T8b.log|at=2026-10-06T15:00:00Z"
sr_run "$SR_PLAN"
expect_eq "M5 every red returned by a later green on its row and suite → correctness ➖, the row back in flight" \
  "$SR_MARK_NEAR correctness — 1 red, all returned, no open S1/S2|🔄 4/T8: The long one (next on the line)" \
  "$(sr_ind correctness)|$(sr_rows | /usr/bin/grep 'T8:')"
# An open S2 finding of a registered reading: correctness ✖️.
printf 'reviewed: %s..%s\nfindings: 1\nfinding: 1 S2 on lib/t1.sh:3 the thing breaks\nshown: 1 bash tests/x.test.sh\n' "$SR_C1" "$SR_H" > "$SR_DIR/critic.md"
awk -v h="$SR_H" '{ print } /^current: 4$/ { print "proved: kind=review head=" h " at=2026-10-06T20:00:00Z evidence=record/wave-02-fx/critic.md question=adversarial reader=crit result=fail scope=piece" }' "$SR_PLAN" > "$SR_PLAN.t" && mv "$SR_PLAN.t" "$SR_PLAN"
sr_run "$SR_PLAN"
expect_eq "M6 an open S2 finding of a registered reading → correctness ✖️" \
  "$SR_MARK_OVER correctness — 1 red, all returned, 1 open S1/S2" "$(sr_ind correctness)"
# The clock 1.25× behind: a 40-hour forecast needs 17 × 12/40 = 5.1, so 5, and 4 landed: schedule ➖.
SR_FORECAST=40h sr_world marks-slow "6 6 12 12"
sr_run "$SR_PLAN"
expect_eq "M7 4 landed where the forecast's pace needs 5 (within 1.25× behind) → schedule ➖" \
  "$SR_MARK_NEAR schedule — 4 of 17 landed in 12h, pace needs 5 · median ready→landed 9m over the 15m bar" "$(sr_ind schedule)"
# …further behind: a 24-hour forecast needs 17 × 12/24 = 8.5, so 9.
SR_FORECAST=24h sr_world marks-late "6 6 12 12"
sr_run "$SR_PLAN"
expect_eq "M7b 4 landed where the pace needs 9 (over 1.25× behind) → schedule ✖️, the bar half still within" \
  "$SR_MARK_OVER schedule — 4 of 17 landed in 12h, pace needs 9 · median ready→landed 9m over the 15m bar" "$(sr_ind schedule)"
# 20% of runs discarded: waste ✖️.
sr_world marks-waste "6 6 12 12"
sr_ev "ev=verdict|row=T8|commit=$SR_C1|suite=a.test.sh|result=discarded|log=/rec/T8.log|at=2026-10-06T14:00:00Z"
sr_run "$SR_PLAN"
expect_eq "M8 one run in five discarded (20%) → waste ✖️" \
  "$SR_MARK_OVER waste 20% discarded · 0% idle-width" "$(sr_ind waste)"
# Idle width: an idle turn from 16:00Z to 17:12Z is 72 of 720 elapsed minutes, 10%: ➖.
sr_world marks-idle "6 6 12 12"
printf 'fill-ledger/v1|at=2026-10-06T16:00:00Z|session=%s|turn=t2|current=4|state=ok|ceiling=|width=4|open=3|free=1|ready=T9|launched=|declined=|missed=1|idle=T9|room=1\n' "$SID" >> "$SR_DIR/fill-ledger.log"
printf 'fill-ledger/v1|at=2026-10-06T17:12:00Z|session=%s|turn=t3|current=4|state=ok|ceiling=|width=4|open=4|free=0|ready=|launched=T9|declined=|missed=0|idle=|room=0\n' "$SID" >> "$SR_DIR/fill-ledger.log"
sr_run "$SR_PLAN"
expect_eq "M9 72 idle minutes over 720 elapsed (10%) → waste ➖, the minutes fill-report's" \
  "$SR_MARK_NEAR waste 0% discarded · 10% idle-width" "$(sr_ind waste)"
# No landing on this run, 12 hours in: the clock still reads, and is behind; the bar still prints.
sr_world marks-none none
sr_run "$SR_PLAN"
expect_eq "M10 no landing yet: the clock half is behind (0 where 4 are needed) → ✖️, and the bar still prints with its number" \
  "$SR_MARK_OVER schedule — 0 of 17 landed in 12h, pace needs 4 · no landing yet against the 15m bar" "$(sr_ind schedule)"
# …and with no forecast declared, neither half can be graded: ❔, each half saying why.
SR_FORECAST= sr_world marks-bare none
sr_run "$SR_PLAN"
expect_eq "M10b no forecast: declared and no landing: schedule ❔, the bar still on the line" \
  "$SR_MARK_NONE schedule — clock unverified, the plan declares no forecast: · no landing yet against the 15m bar" "$(sr_ind schedule)"
expect_eq "M11 …the legend is the same one line, under the third indicator" "$SR_LEGEND" \
  "$(printf '%s\n' "$OUT" | awk '/^Assessment$/ { f = 1; next } f && /^[^ ]+ waste / { w = 1; next } w { print; exit }')"

# ============================================================
section "§CLOCK — wave-39 T9 (D25, Δ9; AC-5.1): the schedule mark reads the clock, rows landed since the Step-3 approval against the pace the plan's forecast: needs, ✅ at or ahead, ➖ within 1.25× behind, ✖️ further; the median ready→landed against the 15-minute bar beside it; the declared sizes feed nothing"
# ============================================================
# The fixture of the finding: 39 rows, 4 landed (10%), 11 hours after approval, against a 24-hour forecast:
# the pace needs 39 × 11/24 = 17.9, so 18. The four landings take 120 120 134 134 minutes: median 127.
SR_FORECAST=24h SR_EXTRA=22 sr_world clock "120 120 134 134"
SR_AT=$((SR_NOW - 3600)) sr_run "$SR_PLAN"
expect_eq "CK0 precondition: 39 rows, 4 landed, read by the Situation's counts" \
  "4 landed · 4 in flight · 31 not started · 0 red/blocked of 39" "$(sr_line '[0-9]+ landed · ')"
SR_CK1="$(sr_ind schedule)"
SR_CK1_BASIS="$(sr_line 'basis: ')"
expect_eq "CK1 10% landed after 11 hours of a 24-hour forecast: ✖️, the counts and the needed pace, the median against the 15m bar beside it" \
  "$SR_MARK_OVER schedule — 4 of 39 landed in 11h, pace needs 18 · median ready→landed 127m over the 15m bar" "$SR_CK1"
# The declared sizes change and nothing else: the mark and its line do not move. The Forecast's basis, which
# still reads the sizes, is the proof the rewrite reached the renderer.
awk -F'|' 'BEGIN { OFS = "|" } $2 ~ /^ T[1-4] $/ { $9 = " 500 " } { print }' "$SR_PLAN" > "$SR_PLAN.t" && mv "$SR_PLAN.t" "$SR_PLAN"
SR_AT=$((SR_NOW - 3600)) sr_run "$SR_PLAN"
expect_eq "CK2a precondition: the sizes rewrite reached the page (the Forecast's basis moved: median declared 500m)" \
  "yes|yes" "$(sr_line 'basis: ' | /usr/bin/grep -q 'over median declared 500m' && echo yes)|$([ "$(sr_line 'basis: ')" != "$SR_CK1_BASIS" ] && echo yes)"
expect_eq "CK2 …and the schedule line is byte for byte what it was: the declared sizes feed nothing of the mark" \
  "$SR_CK1" "$(sr_ind schedule)"
# Ahead of pace: a 120-hour forecast needs 39 × 11/120 = 3.6, so 4, and 4 landed in a 9-minute median.
SR_FORECAST=120h SR_EXTRA=22 sr_world clock-ahead "6 6 12 12"
SR_AT=$((SR_NOW - 3600)) sr_run "$SR_PLAN"
expect_eq "CK3 a fixture at the forecast's pace, its median under the bar: ✅" \
  "$SR_MARK_WITHIN schedule — 4 of 39 landed in 11h, pace needs 4 · median ready→landed 9m over the 15m bar" "$(sr_ind schedule)"
# The scorecard's target is the same bar.
SR_SC="$(SR_AT=$((SR_NOW - 3600)) sr_poke landing-report --scorecard "$SR_PLAN" 2>/dev/null)"
expect_eq "CK4 the scorecard's widest landing prints against target < 15, the landing bar" \
  "widest landing ready→landed: T3 12.0 min · target < 15" "$(printf '%s\n' "$SR_SC" | /usr/bin/grep '^widest landing ')"
expect_eq "CK5 …and its schedule line is the sitrep's, byte for byte" \
  "$(sr_ind schedule)" "$(printf '%s\n' "$SR_SC" | /usr/bin/grep -E '^[^ ]+ schedule ')"

# ============================================================
section "§BAR-PLANT — wave-39 T9 (D12; AC-5.2): planted 20-minute landings turn the indicator ✖️ with the clock at pace; the bar is LINE_LANDING_BAR in lib/line.sh, read by the sitrep and the scorecard alike"
# ============================================================
sr_world bar-plant "20 20 20 20"
sr_run "$SR_PLAN"
expect_eq "BP1 four landings of 20 minutes, the clock at pace (4 of 17, needs 4): the median over the 15m bar turns the indicator ✖️" \
  "$SR_MARK_OVER schedule — 4 of 17 landed in 12h, pace needs 4 · median ready→landed 20m over the 15m bar" "$(sr_ind schedule)"
sr_run --line "$SR_PLAN"
expect_eq "BP2 …and the one-line form opens on it (the line: $OUT)" "yes" "$([ "${OUT#"$SR_MARK_OVER$SR_MARK_WITHIN$SR_MARK_WITHIN · "}" != "$OUT" ] && echo yes)"
sr_world bar-near "17 17 17 17"
sr_run "$SR_PLAN"
expect_eq "BP3 a 17-minute median, within 1.25× of the bar: ➖" \
  "$SR_MARK_NEAR schedule — 4 of 17 landed in 12h, pace needs 4 · median ready→landed 17m over the 15m bar" "$(sr_ind schedule)"
# One constant: a mutant tree whose lib/line.sh sets the bar to 25 moves both surfaces that read it.
SR_MUT="$TMPROOT/mut"; mkdir -p "$SR_MUT/payload"
cp -R "$BIONIC_HOOKS_DIR" "$SR_MUT/hooks" && cp -R "$BIONIC_HOOKS_DIR/../payload/scripts" "$SR_MUT/payload/scripts"
sed 's/^LINE_LANDING_BAR=15$/LINE_LANDING_BAR=25/' "$BIONIC_HOOKS_DIR/../payload/scripts/lib/line.sh" > "$SR_MUT/payload/scripts/lib/line.sh"
expect_eq "BP4 precondition: the shipped line.sh defines the bar once, at 15, and the mutant at 25" "1|1" \
  "$(/usr/bin/grep -c '^LINE_LANDING_BAR=15$' "$BIONIC_HOOKS_DIR/../payload/scripts/lib/line.sh" | tr -d ' ')|$(/usr/bin/grep -c '^LINE_LANDING_BAR=25$' "$SR_MUT/payload/scripts/lib/line.sh" | tr -d ' ')"
sr_world bar-plant-mut "20 20 20 20"
SR_KEEP_POKER="$POKER"; POKER="$SR_MUT/hooks/session-poker.sh"
sr_run "$SR_PLAN"
SR_MUT_SC="$(sr_poke_with "$POKER" landing-report --scorecard "$SR_PLAN")"
POKER="$SR_KEEP_POKER"
expect_eq "BP5 under the mutant bar of 25 the same 20-minute landings render (rc 0) and read ✅ over the 25m bar" \
  "0|$SR_MARK_WITHIN schedule — 4 of 17 landed in 12h, pace needs 4 · median ready→landed 20m over the 25m bar" "$RC|$(sr_ind schedule)"
expect_eq "BP6 …and the scorecard's target reads it too" \
  "widest landing ready→landed: T1 20.0 min · target < 25" "$(printf '%s\n' "$SR_MUT_SC" | /usr/bin/grep '^widest landing ')"

# ============================================================
section "§BLOCKERS: every open approve:, waive:, finding: and gate: item the person owes, one line each, or the none line (AC-2.5, D11)"
# ============================================================
sr_world blockers "6 6 12 12"
sr_run "$SR_PLAN"
expect_eq "B1 an empty ledger prints the one none line under Blockers" \
  "none — no decision or action is owed by you" \
  "$(printf '%s\n' "$OUT" | awk '/^Blockers$/ { getline; print; exit }')"
sr_owed "key=approve:release|state=open|sent=-|at=2026-10-06T20:00:00Z|title=approval: release|reply=poker: WAIT T12 — approval:release"
sr_owed "key=ruling:r1|state=open|sent=-|at=2026-10-06T20:01:00Z|title=ruling unread: w-T5|reply=poker: RULING r1 unread by w-T5"
sr_owed "key=approve:merge|state=open|sent=-|at=2026-10-06T20:02:00Z|title=approval: merge|reply=poker: WAIT T17 — approval:merge"
sr_owed "key=approve:old|state=closed|by=approve|at=2026-10-06T19:30:00Z"
sr_owed "key=waive:structure|state=open|sent=-|at=2026-10-06T20:03:00Z|title=waiver: structure|reply=poker: the structure reading is owed at the head — waive structure '<reply>' or read it"
sr_run "$SR_PLAN"
expect_eq "B2 two open approve: items and one waive: print as three lines, in the ledger's order; a closed item and a writer's ruling item do not" \
  "approve:release — WAIT T12 — approval:release|approve:merge — WAIT T17 — approval:merge|waive:structure — the structure reading is owed at the head — waive structure '<reply>' or read it" \
  "$(printf '%s\n' "$OUT" | awk '/^Blockers$/ { on = 1; next } on && /^$/ { exit } on { print }' | tr '\n' '|' | sed 's/|$//')"
expect_eq "B3 …a row whose reads wait on an open approval reads ⛔ (blocked), and the counts say so" \
  "⛔ 4/T12: Release-gated row (waits on approval:release)|⛔ 4/T17: Merge-gated row (waits on approval:merge)|4 landed · 4 in flight · 7 not started · 2 red/blocked of 17" \
  "$(sr_rows | /usr/bin/grep -E 'T1[27]:' | tr '\n' '|')$(sr_line '[0-9]+ landed · ')"

# ============================================================
section "§FORECAST: percent landed over all rows; closes at now + remaining chain × pace ratio ÷ admitted width, local 12-hour; the basis line; the waits line; before any landing the previous wave's ratio, said (AC-2.6, D12)"
# ============================================================
sr_world forecast "6 6 12 12"
sr_run "$SR_PLAN"
SR_FC="$(printf '%s\n' "$OUT" | awk '/^Forecast$/ { on = 1; next } on && /^$/ { exit } on { print }')"
expect_eq "F1 the Forecast section is four lines: percent, closing time, basis, waits" \
  "4/17 rows landed (24%)|closes ~4:30 PM|basis: median ready→landed 9.0m over median declared 7.5m = 1.2× · admitted width 2 · remaining chain T8→T9 150m|assuming open blockers are answered now; each hour they wait moves it an hour" \
  "$(printf '%s\n' "$SR_FC" | tr '\n' '|' | sed 's/|$//')"
# The width moves the time: one admitted request, not two → 150 × 1.2 ÷ 1 = 180 min → 6:00 PM.
rm -f "$SR_GATE/requests/2"
sr_run "$SR_PLAN"
expect_eq "F2 one admitted run: the chain's measured minutes are not divided → closes ~6:00 PM, width 1 in the basis" \
  "closes ~6:00 PM|admitted width 1" "$(sr_line 'closes ')|$(sr_line 'basis: ' | /usr/bin/grep -oE 'admitted width [0-9]+')"
# No admitted run at all: the width is at least 1.
rm -f "$SR_GATE/requests/1"
sr_run "$SR_PLAN"
expect_eq "F3 no admitted run: the width is 1, never 0" "closes ~6:00 PM|admitted width 1" \
  "$(sr_line 'closes ')|$(sr_line 'basis: ' | /usr/bin/grep -oE 'admitted width [0-9]+')"
# Before the first landing: the previous delivered wave's measured ratio, and the line says so.
sr_world forecast-none none
sr_prev 96
sr_run "$SR_PLAN"
SR_FC="$(printf '%s\n' "$OUT" | awk '/^Forecast$/ { on = 1; next } on && /^$/ { exit } on { print }')"
expect_eq "F4 no landing on this run: 0/17, closes on wave-01's 1.6× (150 × 1.6 ÷ 2 = 120 min → 5:00 PM), and the basis line says whose ratio it is" \
  "0/17 rows landed (0%)|closes ~5:00 PM|basis: wave-01's measured ratio 1.6× — no landing yet on this run · admitted width 2 · remaining chain T8→T9 150m|assuming open blockers are answered now; each hour they wait moves it an hour" \
  "$(printf '%s\n' "$SR_FC" | tr '\n' '|' | sed 's/|$//')"
# No landing here and no delivered wave to borrow from: unverified, said.
sr_world forecast-bare none
sr_run "$SR_PLAN"
expect_eq "F5 no landing and no delivered wave: the closing time is unverified, and says why" \
  "closes unverified — no measured pace on this run or a delivered one" "$(sr_line 'closes ')"
# A closing time past midnight carries its local date.
sr_world forecast-late "6 6 12 12"
SR_AT=$((SR_NOW + 6 * 3600)) sr_run "$SR_PLAN"
expect_eq "F6 at 9:00 PM, 90 minutes on is the same local day: no date" \
  "closes ~10:30 PM" "$(sr_line 'closes ')"
SR_AT=$((SR_NOW + 12 * 3600)) sr_run "$SR_PLAN"
expect_eq "F7 …at 3:00 AM the next morning, now's own day: no date" "closes ~4:30 AM" "$(sr_line 'closes ')"
SR_AT=$((SR_NOW + 8 * 3600 + 1800)) sr_run "$SR_PLAN"
expect_eq "F8 …at 11:30 PM, 90 minutes on is past midnight: the date follows" "closes ~1:00 AM 2026-10-07" "$(sr_line 'closes ')"

# ============================================================
section "§BOTTOM: sitrep bottom-line records up to four items with the time; a fifth and an uncited unlabelled item are refused; the next render prints them since that time (AC-2.7, D9, Δ7)"
# ============================================================
sr_world bottom "6 6 12 12"
SR_LOG="$SR_DIR/sitrep.log"
sr_run bottom-line 'T8 is the chain, 150m of it (line 30)' 'hypothesis: two admitted runs is the gate keeping to its share' 'diagnosis: the pace is under declared (line 24)' 'projection: closes before 5 PM if T12 is approved now' "$SR_PLAN"
expect_eq "BL1 four items, each cited (line n) or labelled: exit 0, nothing on stderr" "0|" "$RC|$ERR"
expect_eq "BL2 …record/<wave>/sitrep.log gains four sitrep-log/v1 lines, each with the time" \
  "sitrep-log/v1|at=2026-10-06T22:00:00Z|item=T8 is the chain, 150m of it (line 30)
sitrep-log/v1|at=2026-10-06T22:00:00Z|item=hypothesis: two admitted runs is the gate keeping to its share
sitrep-log/v1|at=2026-10-06T22:00:00Z|item=diagnosis: the pace is under declared (line 24)
sitrep-log/v1|at=2026-10-06T22:00:00Z|item=projection: closes before 5 PM if T12 is approved now" "$(cat "$SR_LOG" 2>/dev/null)"
sr_run bottom-line 'a (line 1)' 'b (line 2)' 'c (line 3)' 'd (line 4)' 'e (line 5)' "$SR_PLAN"
expect_eq "BL3 a fifth item is refused (usage, 2), naming the limit, and the log is unchanged" \
  "2|1|4" "$RC|$(printf '%s\n' "$ERR" | /usr/bin/grep -c 'at most four')|$(/usr/bin/grep -c . "$SR_LOG")"
sr_run bottom-line 'the run is going fine' "$SR_PLAN"
expect_eq "BL4 an item neither cited (line n) nor labelled hypothesis:/diagnosis:/projection: is refused (1), naming it, and the log is unchanged" \
  "1|1|4" "$RC|$(printf '%s\n' "$ERR" | /usr/bin/grep -c "'the run is going fine'")|$(/usr/bin/grep -c . "$SR_LOG")"
sr_run bottom-line 'hypothesis: a | b' "$SR_PLAN"
expect_eq "BL5 an item holding a | (the record's separator) is refused (1), the log unchanged" "1|4" "$RC|$(/usr/bin/grep -c . "$SR_LOG")"
sr_run "$SR_PLAN"
expect_eq "BL6 the next render opens on the recorded Bottom line, since its local time" \
  "Bottom line (since 3:00 PM)|- T8 is the chain, 150m of it (line 30)|- hypothesis: two admitted runs is the gate keeping to its share|- diagnosis: the pace is under declared (line 24)|- projection: closes before 5 PM if T12 is approved now" \
  "$(printf '%s\n' "$OUT" | sed -n '2,6p' | tr '\n' '|' | sed 's/|$//')"
SR_AT=$((SR_NOW + 600)) sr_run bottom-line 'diagnosis: nothing moved (line 12)' "$SR_PLAN"
SR_AT=$((SR_NOW + 900)) sr_run "$SR_PLAN"
expect_eq "BL7 a later recording replaces the Bottom line shown: only its items, since its time" \
  "Bottom line (since 3:10 PM)|- diagnosis: nothing moved (line 12)||" \
  "$(printf '%s\n' "$OUT" | sed -n '2,4p' | tr '\n' '|')"

# ============================================================
section "§LINE: --line is the one-line form, the three indicator glyphs in order · owed: <n> · closes ~<time> (AC-2.8, D13)"
# ============================================================
sr_world line "6 6 12 12"
sr_run --line "$SR_PLAN"
expect_eq "L1 the clean world: one line, exit 0" "0|$SR_MARK_WITHIN$SR_MARK_WITHIN$SR_MARK_WITHIN · owed: 0 · closes ~4:30 PM" "$RC|$OUT"
sr_ev "ev=verdict|row=T8|commit=$SR_C1|suite=a.test.sh|result=red|log=/rec/T8.log|at=2026-10-06T14:00:00Z"
sr_owed "key=approve:release|state=open|sent=-|at=2026-10-06T20:00:00Z|title=approval: release|reply=poker: WAIT T12 — approval:release"
sr_owed "key=gate:abc|state=open|sent=-|at=2026-10-06T20:00:00Z|title=gate act: merge|reply=poker: GATE T28 — merge: approve it"
sr_run --line "$SR_PLAN"
expect_eq "L2 a red at head and two owed items: the correctness glyph moves, owed counts them" \
  "$SR_MARK_WITHIN$SR_MARK_OVER$SR_MARK_WITHIN · owed: 2 · closes ~4:30 PM" "$OUT"
sr_run "$SR_PLAN"
expect_eq "L3 …the one line's glyphs are the full report's three marks, in order" \
  "$SR_MARK_WITHIN$SR_MARK_OVER$SR_MARK_WITHIN" "$(printf '%s\n' "$OUT" | awk '$2 == "schedule" || $2 == "correctness" || $2 == "waste" { printf "%s", $1 }')"
SR_FORECAST= sr_world line-none none
sr_run --line "$SR_PLAN"
expect_eq "L4 an indicator the record cannot compute (no forecast:, no landing) prints ❔ in the one line, and so does an unverified closing time" \
  "$SR_MARK_NONE$SR_MARK_WITHIN$SR_MARK_WITHIN · owed: 0 · closes unverified" "$OUT"

# ============================================================
section "§ARGS: the verb's operands"
# ============================================================
sr_world args "6 6 12 12"
sr_run --line --line "$SR_PLAN"
expect_eq "A1 --line twice is the usage error (2)" "2" "$RC"
sr_run "$SR_REPO/no/such.plan.md"
expect_eq "A2 a named plan that is no file is refused (2), naming it" \
  "2|1" "$RC|$(printf '%s\n' "$ERR" | /usr/bin/grep -c 'no plan file at')"
sr_run bottom-line "$SR_PLAN"
expect_eq "A3 bottom-line with no item is the usage error (2)" "2" "$RC"


# ============================================================
# THE SKILL AND ITS SURFACES (wave-38 T11; D9, D11, D13; AC-2.1, AC-2.7, AC-2.8).
#
# THE CONTRACT CHECKER. /bionic:sitrep is a skill: the model runs the verb, fills two judgment slots and
# shows the page. What a suite can pin is the contract, so `sr_check` is that contract as code and every
# case below feeds it a report built from the verb's own page. Its heading list is read from the skill's
# shape block, not written here, so without the skill nothing in these sections can pass. The rules:
#   - the title line is the page's first line, byte for byte, and opens `Sitrep · `; no rule line;
#   - the headings are the shape's, in the shape's order, title case;
#   - Bottom line is the heading alone, then two to four `- <item>` lines, each cited `(line n)` to a
#     non-blank line of the verb's page or labelled `hypothesis:`; a `diagnosis:` or `projection:` item
#     cites too, and no citation points past the page;
#   - Diagnosis sits directly under Assessment: one to five lines, each cited `(line n)`;
#   - with the Bottom line section and the Diagnosis block taken out, the report IS the page with its own
#     Bottom line section taken out: every other line the verb's, byte for byte, in the verb's order.
# `(line n)` numbers the verb's page as `sitrep <plan>` prints it, the title line being 1 (A-T11-2).
# ============================================================
SR_SKILL="${BIONIC_SKILLS_DIR}/sitrep/SKILL.md"
# sr_shape -> the skill's report shape: the first ```text fence whose first line opens `Sitrep · `.
sr_shape() {
  awk '/^```text$/ { if (!done) { f = 1; first = 1 }; next } f && /^```$/ { if (keep) exit; f = 0; next }
       f && first { first = 0; if (index($0, "Sitrep · ") == 1) keep = 1 } f && keep { print }' "$SR_SKILL" 2>/dev/null
}
# sr_heads <file> -> its heading lines, `|`-joined: a line of one or two words and nothing else.
sr_heads() { awk '/^[A-Za-z][A-Za-z]+( [A-Za-z]+)?$/' "$1" | tr '\n' '|' | sed 's/|$//'; }
sr_strip_bl() { awk 'NR == 1 { print; next } s == 0 && $0 != "" { next } { s = 1; print }' "$1"; }
sr_strip_dg() { awk '$0 == "Diagnosis" { d = 1; next } d && $0 == "" { d = 0; next } !d { print }' "$1"; }
# sr_cites_ok <line> <page file> -> 0 when the line cites at least one (line n) and every n is a non-blank page line
sr_cites_ok() {
  local c k any=1
  for c in $(printf '%s\n' "$1" | /usr/bin/grep -oE '\(line [0-9]+\)' | tr -dc '0-9\n'); do
    k=$((10#$c)); [ "$k" -ge 1 ] && [ -n "$(sed -n "${k}p" "$2")" ] || return 2; any=0
  done
  return $any
}
sr_check() {  # <report file> <page file> -> `ok`, or the first rule the report breaks
  local rep="$1" page="$2" want l items=0 dl=0 sect="" rc
  want="$(sr_shape > "$TMPROOT/shape.txt"; sr_heads "$TMPROOT/shape.txt")"
  [ -n "$want" ] || { echo "no shape"; return; }
  l="$(head -1 "$rep")"
  { [ "$l" = "$(head -1 "$page")" ] && [ "${l#Sitrep · }" != "$l" ]; } || { echo "title"; return; }
  /usr/bin/grep -qE '^[-=─━_]{3,}$' "$rep" && { echo "rule line"; return; }
  [ "$(sr_heads "$rep")" = "$want" ] || { echo "headings: $(sr_heads "$rep")"; return; }
  while IFS= read -r l; do
    case "$l" in "Bottom line"|Situation|Assessment|Diagnosis|Blockers|Forecast) sect="$l"; continue ;; "") sect=""; continue ;; esac
    if [ "$sect" = "Bottom line" ]; then
      case "$l" in "- "*) items=$((items + 1)) ;; *) echo "bottom line: not an item: $l"; return ;; esac
      sr_cites_ok "$l" "$page"; rc=$?
      [ "$rc" -ne 2 ] || { echo "cite: $l"; return; }
      case "$l" in
        "- hypothesis: "*) : ;;
        *) [ "$rc" -eq 0 ] || { echo "uncited: $l"; return; } ;;
      esac
    elif [ "$sect" = Diagnosis ]; then
      dl=$((dl + 1))
      sr_cites_ok "$l" "$page" || { echo "diagnosis uncited: $l"; return; }
    fi
  done < "$rep"
  { [ "$items" -ge 2 ] && [ "$items" -le 4 ]; } || { echo "bottom line: $items items"; return; }
  { [ "$dl" -ge 1 ] && [ "$dl" -le 5 ]; } || { echo "diagnosis: $dl lines"; return; }
  sr_strip_bl "$rep" > "$TMPROOT/rep.f"; sr_strip_dg "$TMPROOT/rep.f" > "$TMPROOT/rep.ff"
  sr_strip_bl "$page" > "$TMPROOT/page.f"
  l="$(diff "$TMPROOT/page.f" "$TMPROOT/rep.ff" | /usr/bin/grep -E '^[<>]' | head -1)"
  [ -z "$l" ] || { echo "fact: $l"; return; }
  echo ok
}
# sr_compose <page file> <items, one per line> <diagnosis lines> -> the report the skill shows: the page,
# its Bottom line section replaced by the heading and the items, a Diagnosis block under Assessment.
sr_compose() {
  SR_C_ITEMS="$2" SR_C_DIAG="$3" awk '
    NR == 1 { print; print "Bottom line"; printf "%s\n", ENVIRON["SR_C_ITEMS"]; skip = 1; next }
    skip && $0 != "" { next }
    { skip = 0 }
    $0 == "Assessment" { inA = 1 }
    inA && $0 == "" { print; print "Diagnosis"; printf "%s\n", ENVIRON["SR_C_DIAG"]; inA = 0 }
    { print }' "$1"
}
SR_ITEMS_OK="- schedule runs at 1.2× declared, inside ✅ (line 29) — no move
- the chain T8→T9 sets the close at 4:30 PM (line 39) (line 40) — keep T8 first · costs nothing
- hypothesis: two admitted runs is the gate keeping to its share — raise the share for a third · 1.6s of tick"
SR_DIAG_OK="schedule is on pace: four landings at 1.2× their declared size (line 29)
correctness and waste are clean: no red, nothing discarded, nothing idle (line 30) (line 31)"

# ============================================================
section "§ORDER: the skill's report opens Sitrep · …, then Bottom line, Situation, Assessment, Diagnosis under it, Blockers, Forecast; title case, no rule line (AC-2.1, D11, Δ4)"
# ============================================================
SR_SHAPE="$(sr_shape)"
expect_eq "O1 the skill's shape block is found and its first line is the title line's form" \
  "Sitrep · <wave> · <release> · <local date and time> · step <n>" "$(printf '%s\n' "$SR_SHAPE" | head -1)"
printf '%s\n' "$SR_SHAPE" > "$TMPROOT/shape.txt"
expect_eq "O2 …its headings, in order: the verb's five with Diagnosis directly under Assessment" \
  "Bottom line|Situation|Assessment|Diagnosis|Blockers|Forecast" "$(sr_heads "$TMPROOT/shape.txt")"
expect_true "O3a …and its Assessment placeholder names the Assessment lines: three indicators, then the within/near/over line" \
  grep -qF "<the verb's Assessment lines: three indicators, then the within/near/over line>" "$SR_SKILL"
expect_eq "O3 …and no rule line in the shape (the same block O1 read)" "" "$(printf '%s\n' "$SR_SHAPE" | /usr/bin/grep -E '^[-=─━_]{3,}$')"
sr_world order "6 6 12 12"
sr_run "$SR_PLAN"; printf '%s\n' "$OUT" > "$TMPROOT/page.txt"
expect_eq "O4 the verb's page is the fixture: 41 lines (the legend line under the three indicators, steps 0 to 3 in the Situation), title first" "41|Sitrep · wave-02-fx · 9.9.0 · 2026-10-06 3:00 PM PDT · step 4" \
  "$(/usr/bin/grep -c '' "$TMPROOT/page.txt")|$(head -1 "$TMPROOT/page.txt")"
sr_compose "$TMPROOT/page.txt" "$SR_ITEMS_OK" "$SR_DIAG_OK" > "$TMPROOT/rep.txt"
expect_eq "O5 the page with both slots filled meets the contract" "ok" "$(sr_check "$TMPROOT/rep.txt" "$TMPROOT/page.txt")"
awk '$0 == "Blockers" { print "Forecast"; next } $0 == "Forecast" { print "Blockers"; next } { print }' "$TMPROOT/rep.txt" > "$TMPROOT/bad.txt"
expect_regex "O6 …Blockers and Forecast swapped: refused on the headings" "^headings: " "$(sr_check "$TMPROOT/bad.txt" "$TMPROOT/page.txt")"
sed 's/^Situation$/SITUATION/' "$TMPROOT/rep.txt" > "$TMPROOT/bad.txt"
expect_regex "O7 …a heading uppercased: refused on the headings" "^headings: " "$(sr_check "$TMPROOT/bad.txt" "$TMPROOT/page.txt")"
sr_compose "$TMPROOT/page.txt" "$SR_ITEMS_OK" "$SR_DIAG_OK" | awk '$0 == "Diagnosis" { d = 1; next } d && $0 == "" { d = 0; next } d { held = held $0 "\n"; next } { print } END { printf "\nDiagnosis\n%s", held }' > "$TMPROOT/bad.txt"
expect_regex "O8 …Diagnosis moved under Forecast: refused on the headings" "^headings: " "$(sr_check "$TMPROOT/bad.txt" "$TMPROOT/page.txt")"
awk 'NR == 1 { print; print "─────"; next } { print }' "$TMPROOT/rep.txt" > "$TMPROOT/bad.txt"
expect_eq "O9 …a rule line under the title: refused" "rule line" "$(sr_check "$TMPROOT/bad.txt" "$TMPROOT/page.txt")"
sr_compose "$TMPROOT/page.txt" "$SR_ITEMS_OK" "$SR_DIAG_OK
a third (line 5)
a fourth (line 6)
a fifth (line 7)
a sixth (line 8)" > "$TMPROOT/bad.txt"
expect_eq "O10 …six Diagnosis lines: refused on the length" "diagnosis: 6 lines" "$(sr_check "$TMPROOT/bad.txt" "$TMPROOT/page.txt")"
sr_compose "$TMPROOT/page.txt" "$SR_ITEMS_OK
- a (line 5)
- b (line 6)" "$SR_DIAG_OK" > "$TMPROOT/bad.txt"
expect_eq "O11 …five Bottom line items: refused on the count" "bottom line: 5 items" "$(sr_check "$TMPROOT/bad.txt" "$TMPROOT/page.txt")"
sr_compose "$TMPROOT/page.txt" "- the run is going fine
- hypothesis: nothing is wrong" "$SR_DIAG_OK" > "$TMPROOT/bad.txt"
expect_eq "O12 …an item neither cited nor labelled hypothesis: refused" "uncited: - the run is going fine" "$(sr_check "$TMPROOT/bad.txt" "$TMPROOT/page.txt")"
sr_compose "$TMPROOT/page.txt" "- projection: it closes by five
- hypothesis: nothing is wrong" "$SR_DIAG_OK" > "$TMPROOT/bad.txt"
expect_eq "O13 …a projection that cites no line: refused" "uncited: - projection: it closes by five" "$(sr_check "$TMPROOT/bad.txt" "$TMPROOT/page.txt")"
# The skill's own text says the rules, one sentence each, and names the verbs it runs.
expect_true "O14 the skill runs the verb on the bound plan" grep -qF 'bash <plugin-root>/hooks/session-poker.sh sitrep' "$SR_SKILL"
expect_true "O15 …records the items with sitrep bottom-line" grep -qF "hooks/session-poker.sh sitrep bottom-line '<item>'" "$SR_SKILL"
expect_true "O16 …says a fact outside the verb's output is a contract violation" grep -qiE "fact .*outside the verb's output is a contract violation" "$SR_SKILL"
expect_true "O17 …says the shape and length rules: two to four items, at most five Diagnosis lines" \
  bash -c 'grep -qiE "two to four" "$1" && grep -qiE "at most five" "$1"' _ "$SR_SKILL"
expect_true "O18 …says what the three surfaces are: /bionic:sitrep, the handoff head, the tick's one line" \
  grep -qiE 'three surfaces.*/bionic:sitrep.*handoff.*tick' "$SR_SKILL"
expect_true "O19 …and quotes the verb's confirmation line" grep -qiE "quote the verb's confirmation line" "$SR_SKILL"

# ============================================================
section "§FACTS: every line outside the two judgment slots is the verb's, byte for byte; a planted fact, an altered line or a citation past the page fails (AC-2.8, D9, Δ1)"
# ============================================================
expect_eq "FA1 the report built from the verb's page meets the contract (the positive, same checker as below)" \
  "ok" "$(sr_check "$TMPROOT/rep.txt" "$TMPROOT/page.txt")"
awk '{ print } /^✅ 4\/T4: / { print "✅ 4/T18: Shipped early (7:30 AM)" }' "$TMPROOT/rep.txt" > "$TMPROOT/bad.txt"
expect_true "FA2 the plant is in the copy" grep -q '^✅ 4/T18: ' "$TMPROOT/bad.txt"
expect_eq "FA3 …a planted row the verb never printed: refused, naming it" "fact: > ✅ 4/T18: Shipped early (7:30 AM)" \
  "$(sr_check "$TMPROOT/bad.txt" "$TMPROOT/page.txt")"
sed 's/^4 landed · 4 in flight/5 landed · 3 in flight/' "$TMPROOT/rep.txt" > "$TMPROOT/bad.txt"
expect_regex "FA4 …a rendered line altered (the counts): refused on the fact" "^fact: " "$(sr_check "$TMPROOT/bad.txt" "$TMPROOT/page.txt")"
printf 'closes ~4:30 PM, so the release ships tonight\n' > "$TMPROOT/extra"
awk -v x="$(cat "$TMPROOT/extra")" '{ print } $0 == "Forecast" { f = 1 } f && /^assuming / { print x }' "$TMPROOT/rep.txt" > "$TMPROOT/bad.txt"
expect_regex "FA5 …an unlabelled claim appended to Forecast: refused on the fact" "^fact: > closes ~4:30 PM, so" "$(sr_check "$TMPROOT/bad.txt" "$TMPROOT/page.txt")"
sr_compose "$TMPROOT/page.txt" "- the plan has a 40th row (line 99)
- hypothesis: nothing is wrong" "$SR_DIAG_OK" > "$TMPROOT/bad.txt"
expect_eq "FA6 …an item citing a line past the page: refused on the citation" "cite: - the plan has a 40th row (line 99)" \
  "$(sr_check "$TMPROOT/bad.txt" "$TMPROOT/page.txt")"
# The items the skill shows are the items it records: the verb takes them, and the next page opens on them.
SR_I1="$(printf '%s\n' "$SR_ITEMS_OK" | sed -n 1p)"; SR_I1="${SR_I1#- }"
SR_I2="$(printf '%s\n' "$SR_ITEMS_OK" | sed -n 2p)"; SR_I2="${SR_I2#- }"
SR_I3="$(printf '%s\n' "$SR_ITEMS_OK" | sed -n 3p)"; SR_I3="${SR_I3#- }"
sr_run bottom-line "$SR_I1" "$SR_I2" "$SR_I3" "$SR_PLAN"
expect_eq "FA7 the contract's items are the verb's to record: exit 0, the confirmation line" \
  "0|poker: sitrep bottom-line — 3 item(s) recorded at 3:00 PM in $(cd "$SR_DIR" && pwd -P)/sitrep.log; the next sitrep opens on them" "$RC|$OUT"
sr_run "$SR_PLAN"
expect_eq "FA8 …and the next page opens on them, since their time" "Bottom line (since 3:00 PM)
$SR_ITEMS_OK" \
  "$(printf '%s\n' "$OUT" | sed -n '2,5p')"

# ============================================================
section "§SURFACES: one renderer, three surfaces — the tick prints \`poker: sitrep <the --line output>\` on every tick, byte for byte (AC-2.8, D13, Δ7)"
# ============================================================
# The handoff head (the last recorded Bottom line with its time) is the third surface; it is T12's, and its
# byte-equality with the verb is pinned by T12's §READERS when the handoff verb lands, not here.
# sr_tick_world <label> <mins> -> a world the tick will decide on: engaged, a commit, bound, armed.
sr_tick_world() {
  sr_world "$1" "$2"
  : > "$SR_REPO/.bionic/tmp/engaged-$SID.state"
  ( cd "$SR_REPO" && git add -A >/dev/null 2>&1 && git -c user.email=t@t -c user.name=t commit -qm fixture >/dev/null 2>&1 )
  sr_poke bind "$SR_PLAN" >/dev/null 2>&1; sr_poke arm >/dev/null 2>&1
}
sr_tick() { sr_poke tick > "$TMPROOT/tick.out" 2> "$TMPROOT/tick.err"; RC=$?; OUT="$(cat "$TMPROOT/tick.out")"; }
# The tick's worlds are unapproved plans (an approved one FILLs, and S1 pins QUIET), so the clock half reads ❔.
SR_APPROVED=none sr_tick_world surf "6 6 12 12"
sr_tick
SR_T1="$OUT"
sr_run --line "$SR_PLAN"; SR_L1="$OUT"
expect_eq "S1 the tick exits 0 and its last line is still its decision line" "0|decision=QUIET" \
  "$RC|$(printf '%s\n' "$SR_T1" | tail -1 | /usr/bin/grep -oE 'decision=[A-Z]+')"
expect_eq "S2 …it prints exactly one sitrep line" "1" "$(printf '%s\n' "$SR_T1" | /usr/bin/grep -c '^poker: sitrep ')"
expect_eq "S3 …and that line is the --line output, byte for byte (here an unapproved clean world's ❔✅✅)" \
  "poker: sitrep $SR_MARK_NONE$SR_MARK_WITHIN$SR_MARK_WITHIN · owed: 0 · closes ~4:30 PM|poker: sitrep $SR_L1" \
  "$(printf '%s\n' "$SR_T1" | /usr/bin/grep '^poker: sitrep ')|poker: sitrep $SR_L1"
sr_ev "ev=verdict|row=T8|commit=$SR_C1|suite=a.test.sh|result=red|log=/rec/T8.log|at=2026-10-06T14:00:00Z"
sr_owed "key=approve:release|state=open|sent=-|at=2026-10-06T20:00:00Z|title=approval: release|reply=poker: WAIT T12 — approval:release"
SR_AT=$((SR_NOW + 60)) sr_tick
SR_AT=$((SR_NOW + 60)) sr_run --line "$SR_PLAN"
expect_eq "S4 a red at head and an owed item move the tick's line exactly as they move --line" \
  "poker: sitrep $SR_MARK_NONE$SR_MARK_OVER$SR_MARK_WITHIN · owed: 1 · closes ~4:31 PM|poker: sitrep $OUT" \
  "$(/usr/bin/grep '^poker: sitrep ' "$TMPROOT/tick.out")|poker: sitrep $OUT"
SR_AT=$((SR_NOW + 120)) sr_tick
SR_T3="$OUT"
expect_contains "S5 an unchanged tick (nothing decided moved) still takes the unchanged path" "poker: unchanged since " "$SR_T3"
expect_eq "S6 …and still prints the sitrep line, above the unchanged line, which stays last" \
  "poker: sitrep $SR_MARK_NONE$SR_MARK_OVER$SR_MARK_WITHIN · owed: 1 · closes ~4:32 PM|unchanged" \
  "$(printf '%s\n' "$SR_T3" | /usr/bin/grep '^poker: sitrep ')|$(printf '%s\n' "$SR_T3" | tail -1 | /usr/bin/grep -q '^poker: unchanged since ' && echo unchanged)"
SR_APPROVED=none sr_tick_world surf-none none
sr_tick
SR_T4="$OUT"
sr_run --line "$SR_PLAN"
expect_eq "S7 a plan with no landing: the tick prints the ❔ forms --line prints" \
  "poker: sitrep $SR_MARK_NONE$SR_MARK_WITHIN$SR_MARK_WITHIN · owed: 0 · closes unverified|poker: sitrep $OUT" \
  "$(printf '%s\n' "$SR_T4" | /usr/bin/grep '^poker: sitrep ')|poker: sitrep $OUT"

finish
