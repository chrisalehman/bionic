#!/bin/bash
# Tests for `hooks/session-poker.sh sitrep` — the situation report's renderer.
#
# THE VERB PRINTS THE WHOLE PAGE BUT ONE JUDGMENT. The title (project, release, weekday and time, the
# step of nine, the tasks done), the Bottom line's four answers (what you owe, what is next, what is
# done, when it closes), the Task list (a glyph, `step/task: description`, a time in parentheses or a
# state after " — "), the Score's five indicator lines, Blocked on you, Completion and Predicted close,
# every section bulleted and every line folded at 92 columns. The one judgment is the grade and its
# rationale, which the skill writes through `sitrep grade <A-F> '<rationale>'`, refused unless the
# rationale names an indicator line; the page prints the newest one recorded. `--line` is the Patrol's
# one-line form.
#
# HERMETIC. One repository per world under a temp root: a 17-task plan, its landing record, its fill
# ledger, the bound sessions' owed stores and a gate store of its own. The clock is BIONIC_NOW_EPOCH
# (the poker's seam, fill-report's too) and the zone is pinned, so every local time below is a fixed
# string; no case reads this machine's clock. The machine's probes are pinned as the session-poker
# prelude pins them, because the gate's scan samples them.
#
# FIXTURE FIDELITY. SYNTHESIZED, in the shapes the writers write: the landing record's `line/v1`
# events as lib/line.sh writes them, the fill ledger's `fill-ledger/v1` lines as lib/stop.sh writes
# them, the owed store's `owed/v1` lines as lib/owed.sh writes them (one line per key), the gate's
# request files as lib/gate.sh writes them, a session's binding through the bind verb itself, and a
# `## Tasks` header in the shipped table shape. What each world pins is what the line under test
# reads, and nothing it does not.
#
# ANTI-VACUITY. Every mark is asserted in a clean world first and then moved by one planted defect;
# each absence sits beside a positive read through the same extractor on the same render; the width
# measure is proved on known strings before it judges a page.
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
sr_owed() {  # <owed/v1 fields after the schema> [<session>] -> one line in that session's owed store (this world's own by default)
  printf 'owed/v1|%s\n' "$1" >> "$SR_REPO/.bionic/tmp/owed-${2:-$SID}.state"
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
# sr_unfold -> stdin with every folded line joined back onto the line it continues (a continuation opens on a
# space), one space between, so a check reads a logical line whole.
sr_unfold() { awk 'NR > 1 && /^ / { sub(/^ +/, ""); l = l " " $0; next } NR > 1 { print l } { l = $0 } END { if (NR) print l }'; }
sr_page() { printf '%s\n' "$OUT" | sr_unfold; }
sr_line() { sr_page | /usr/bin/grep -E "^$1" | head -1; }
sr_sect() {  # <heading, an extended regex matched whole> -> the section's logical lines, heading excluded, to the first blank
  sr_page | awk -v h="^$1\$" 'on && /^$/ { exit } on { print } $0 ~ h { on = 1 }'
}
sr_sit() { sr_sect 'Task list'; }
sr_rows() { sr_sit | /usr/bin/grep -E '^[^ ]+ [^ /]+/[^ ]+: '; }   # -> its task lines, `<glyph> <step>/<task>: …`
sr_steps() { sr_sit | /usr/bin/grep -E '^[^ ]+ [0-9]+: '; }        # -> its step lines, `<glyph> <step>: …`
sr_heads() { awk 'p && NF { print } { p = ($0 == "") }' "${1:--}" | tr '\n' '|' | sed 's/|$//'; }   # -> the line after each blank
sr_join() { tr '\n' '|' | sed 's/|$//'; }
# THE MARKS, from one place: a measurement held against a bar is within it, near it, over it, or not measurable.
SR_MARK_WITHIN='✅'
SR_MARK_NEAR='➖'
SR_MARK_OVER='✖️'
SR_MARK_NONE='❔'
# sr_ind <name> -> the indicator's logical line in the Score: the mark leads, then the name
sr_ind() { sr_sect 'Score: .*' | /usr/bin/grep -E "^[^ ]+ $1 " | head -1; }
# THE WIDTH A TERMINAL GIVES A LINE, measured byte-wise so no locale decides it: a character is one column, a
# four-byte one (an emoji) two, the six mark glyphs that are three-byte (✅ ⬜ ⛔ ❔ ➖ ✖) two, the emoji
# variation selector U+FE0F none. Proved on known strings (H5a) before it judges a page.
SR_CW_AWK='function cw(s,   t, n, w) {
  t = s; n = gsub(/[\200-\277]/, "", t); w = length(s) - n
  t = s; w -= gsub(/\357\270\217/, "", t)
  t = s; w += gsub(/[\360-\364]/, "", t)
  t = s; w += gsub(/\342\234\205|\342\254\234|\342\233\224|\342\235\224|\342\236\226|\342\234\226/, "", t)
  return w }'
sr_widths() { LC_ALL=C awk "$SR_CW_AWK"'{ print cw($0) }'; }   # -> one width per stdin line
sr_maxw() { sr_widths | sort -n | tail -1; }

# ============================================================
section "§ROWS: every task of ## Tasks, glyph in column 1, [step]/[task]: description, a done task with its local 12-hour time, a state after \" — \"; the title, the Completion counts and the Bottom line's four answers"
# ============================================================
sr_world rows "6 6 12 12"
sr_run "$SR_PLAN"
expect_eq "R0 sitrep <plan> exits 0 with nothing on stderr" "0|" "$RC|$ERR"
expect_eq "R1 the title line: Sitrep · project release · weekday and time · step of nine · tasks done" \
  "Sitrep · rows 9.9.0 · Tuesday 3:00 PM · step 4 of 9 · 4 of 17 tasks done" "$(printf '%s\n' "$OUT" | head -1)"
expect_eq "R2 the Completion: steps, then tasks done with the percent" "- 4 of 9 steps.|- 4 of 17 tasks done (24%)." \
  "$(sr_sect Completion | sr_join)"
SR_ROWS="$(sr_rows)"
expect_eq "R3 seventeen task lines under Task list" "17" "$(printf '%s\n' "$SR_ROWS" | /usr/bin/grep -c .)"
expect_eq "R4 every task line opens with one of the four glyphs in column 1, then [step]/[task]:" "17" \
  "$(printf '%s\n' "$SR_ROWS" | /usr/bin/grep -cE '^(✅|🔄|⬜|⛔) 4/T[0-9]+: ')"
expect_eq "R5 the tasks in execution order: done by time with it, in flight by place on the line, then the rest in dependency order; the description cut at its first ( . or ·, a time in parentheses, a state after a dash, a task not started bare, an approval it waits on in words" \
  "✅ 4/T1: Row one the thing (3:06 AM)|✅ 4/T2: Haiku 5.5 at high (3:36 AM)|✅ 4/T3: Third row (4:12 AM)|✅ 4/T4: Fourth (5:12 AM)|🔄 4/T8: The long one — next on the line|🔄 4/T5: Row 5 body — building|🔄 4/T6: Row 6 body — building|🔄 4/T7: Row 7 body — building|⬜ 4/T9: Waits on the long one — waits on T8|⬜ 4/T10: Row 10 body|⬜ 4/T11: Row 11 body|⬜ 4/T13: Row 13 body|⬜ 4/T14: Row 14 body|⬜ 4/T15: Row 15 body|⬜ 4/T16: Row 16 body|⬜ 4/T12: Release-gated row — waits on your approval of release|⬜ 4/T17: Merge-gated row — waits on your approval of merge" \
  "$(printf '%s\n' "$SR_ROWS" | sr_join)"
expect_eq "R6 no UTC instant anywhere on the page (no ISO Z time, no UTC word)" "" \
  "$(printf '%s\n' "$OUT" | /usr/bin/grep -E '[0-9]{2}:[0-9]{2}(:[0-9]{2})?Z|UTC')"
expect_eq "R7 the section headings in order, each after a blank line" \
  "Bottom line|Task list|Score: not graded yet|Blocked on you|Completion|Predicted close" "$(printf '%s\n' "$OUT" | sr_heads)"
expect_eq "R8 …and no line of rule characters" "" "$(printf '%s\n' "$OUT" | /usr/bin/grep -E '^[-=─━_]{3,}$')"
expect_eq "R10 the step lines: 0 to 3 first (3 done by its approval instant, the rest done with no time), then each later step with no task of its own" \
  "✅ 0: Configure — done, no time on record|✅ 1: Scope — done, no time on record|✅ 2: Design — done, no time on record|✅ 3: Plan (3:00 AM)|⬜ 5: Verify|⬜ 6: Review|⬜ 7: Document|⬜ 8: Integrate|⬜ 9: Close-out" \
  "$(sr_steps | sr_join)"
expect_eq "R11 the Bottom line: what you owe, what is next, what is done, when it closes" \
  "- You owe nothing now.|- Next: T8, T5, T6 and T7 in flight; then T9, T10, T11 and 6 more.|- Done: steps 0 to 3; 4 of 17 tasks, the last T4 at 5:12 AM.|- Close: about 7:48 PM." \
  "$(sr_sect 'Bottom line' | sr_join)"
# A task done on another day than now's carries its local date after the time.
SR_AT=$((SR_NOW + 86400)) sr_run "$SR_PLAN"
expect_eq "R9 a task done on another local day than now's: H:MM AM/PM then its local date" \
  "✅ 4/T1: Row one the thing (3:06 AM 2026-10-06)" "$(sr_rows | head -1)"

# ============================================================
section "§SHAPES: a done task is timed from whichever shape its step line has, landed <sha> <ISO>, landed-by-hand: <who> <ISO> \"<why>\", or either after text; over a 38-task plan every one prints a time"
# ============================================================
# FIXTURE FIDELITY. The `- Step` and `- T<n>:` lines below are a delivered plan's `## SDLC State` lines, byte
# for byte as its run left them at close. Its `## Tasks` table is synthesized: each task's id, step and kind as
# that table holds them, all done, the task cell a stand-in. The landing record is empty, so every time on the
# page is the step line's own.
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
expect_eq "SH0 precondition: the 38-task plan renders (rc 0), every task done, read by the Completion" \
  "0|- 38 of 38 tasks done (100%)." "$RC|$(sr_sect Completion | sed -n 2p)"
expect_eq "SH0b precondition: the fixture holds the three shapes — bare, text before landed, landed-by-hand (lead and after text)" "yes|yes|yes|yes" \
  "$(sr_w38_lines | /usr/bin/grep -qE '^- T1: landed [0-9a-f]{40} ' && echo yes)|$(sr_w38_lines | /usr/bin/grep -qE '^- T2: reason: .* landed [0-9a-f]{40} ' && echo yes)|$(sr_w38_lines | /usr/bin/grep -qE '^- T12: landed-by-hand: ' && echo yes)|$(sr_w38_lines | /usr/bin/grep -qE '^- T3: reason: .* landed-by-hand: ' && echo yes)"
expect_eq "SH1 38 of 38 done tasks print a time" "38" \
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
section "§ORDER: the Task list opens on steps 0 to 3 with their approval times, then every task in execution order — done by time, hand landings included; in flight by place on the line with what each is doing; the rest in dependency order with what each waits on"
# ============================================================
# The world: §ROWS' fixture, landed out of table order (T2 3:36, T3 by hand 3:50, T1 4:00, T4 5:12), its four
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
  "0|- 4 of 17 tasks done (24%)." "$RC|$(sr_sect Completion | sed -n 2p)"
expect_eq "ORD1 the Task list opens on steps 0 to 3, each with its approval time (the approved by instant, not an earlier approved)" \
  "✅ 0: Configure (1:10 AM)|✅ 1: Scope (1:40 AM)|✅ 2: Design (2:20 AM)|✅ 3: Plan (3:00 AM)" \
  "$(sr_sit | head -4 | sr_join)"
expect_eq "ORD2 …then the done tasks by time, each with it, the hand landing in its place" \
  "✅ 4/T2: Haiku 5.5 at high (3:36 AM)|✅ 4/T3: Third row (3:50 AM, by hand)|✅ 4/T1: Row one the thing (4:00 AM)|✅ 4/T4: Fourth (5:12 AM)" \
  "$(sr_sit | sed -n '5,8p' | sr_join)"
expect_eq "ORD3 …then the tasks in flight by their place on the line, each saying what it is doing" \
  "🔄 4/T8: The long one — in its landing, 1 of 2 suites green|🔄 4/T6: Row 6 body — queued on the line behind T8|🔄 4/T5: Row 5 body — queued on the line behind T6|🔄 4/T7: Row 7 body — building" \
  "$(sr_sit | sed -n '9,12p' | sr_join)"
expect_eq "ORD4 …then the rest in dependency order, T11 before T10 which reads what it writes, each waiting task saying on what" \
  "⬜ 4/T9: Waits on the long one — waits on T8|⬜ 4/T11: Row 11 body|⬜ 4/T10: Row 10 body — waits on T11|⬜ 4/T13: Row 13 body|⬜ 4/T14: Row 14 body|⬜ 4/T15: Row 15 body|⬜ 4/T16: Row 16 body|⬜ 4/T12: Release-gated row — waits on your approval of release|⬜ 4/T17: Merge-gated row — waits on your approval of merge" \
  "$(sr_sit | sed -n '13,21p' | sr_join)"
expect_eq "ORD5 …and nothing else: 9 steps and 17 tasks, one logical line each" "26|9|17" \
  "$(sr_sit | /usr/bin/grep -c .)|$(sr_steps | /usr/bin/grep -c .)|$(sr_rows | /usr/bin/grep -c .)"
# A step with no approval instant on its line says so.
awk '/^- Step 2: / { print "- Step 2: spec: specs/x.spec.md; frame approved at the card"; next } { print }' "$SR_PLAN" > "$SR_PLAN.t" && mv "$SR_PLAN.t" "$SR_PLAN"
sr_run "$SR_PLAN"
expect_eq "ORD6 a passed step whose line names no approval instant says so, its neighbours still timed" \
  "✅ 1: Scope (1:40 AM)|✅ 2: Design — done, no time on record|✅ 3: Plan (3:00 AM)" \
  "$(sr_steps | sed -n '2,4p' | sr_join)"

# ============================================================
section "§MARKS: the Score's five indicator lines, each opening on its mark (✅ within · ➖ near · ✖️ over · ❔ not measurable) then its name and what it measured, in words; no legend line; a planted defect moves its mark"
# ============================================================
sr_world marks "6 6 12 12"
sr_run "$SR_PLAN"
expect_eq "M0 the clean world: schedule ✅, 4 of 17 tasks done in the 12 hours since approval where a 48-hour forecast needs 4, and the median landing 9 min (landing-report's) within the 15 min bar" \
  "$SR_MARK_WITHIN schedule — 4 of 17 tasks done in 12 h, the forecast's pace needs 4; the median one-file landing takes 9 min, within the 15 min bar" "$(sr_ind schedule)"
expect_eq "M1 …correctness ✅, no red, no open S1 or S2" \
  "$SR_MARK_WITHIN correctness — no red suite at head; no open S1 or S2 finding" "$(sr_ind correctness)"
expect_eq "M2 …waste ✅, nothing discarded, nothing idle" \
  "$SR_MARK_WITHIN waste — nothing discarded; no writer slot sat idle" "$(sr_ind waste)"
expect_eq "M2a the five indicators in order, and no legend line anywhere on the page" "schedule|correctness|waste|decisions|goals|0" \
  "$(sr_sect 'Score: .*' | awk '$2 ~ /^(schedule|correctness|waste|decisions|goals)$/ { print $2 }' | sr_join)|$(printf '%s\n' "$OUT" | /usr/bin/grep -c '^within / near / over')"
expect_eq "M2b …no indicator line carries a parenthesised bar" "0" \
  "$(sr_sect 'Score: .*' | /usr/bin/grep -E '^[^ ]+ (schedule|correctness|waste|decisions|goals) ' | /usr/bin/grep -c '(')"
expect_eq "M2c …each indicator line opens on one of the four marks, then its name" "5" \
  "$(sr_sect 'Score: .*' | /usr/bin/grep -cE "^($SR_MARK_WITHIN|$SR_MARK_NEAR|$SR_MARK_OVER|$SR_MARK_NONE) (schedule|correctness|waste|decisions|goals) ")"
expect_eq "M2d …decisions print their no-record form, ❔; a plan that declares no goals says so" \
  "$SR_MARK_NONE decisions — rounds not counted yet|$SR_MARK_NONE goals — none declared" "$(sr_ind decisions)|$(sr_ind goals)"
# A planted red run, not answered: correctness over its bar, and the task it is on reads ⛔.
sr_ev "ev=verdict|row=T8|commit=$SR_C1|suite=a.test.sh|result=red|log=/rec/T8.log|at=2026-10-06T14:00:00Z"
sr_run "$SR_PLAN"
expect_eq "M3 a planted red run at head → correctness ✖️" \
  "$SR_MARK_OVER correctness — 1 red suite at head; no open S1 or S2 finding" "$(sr_ind correctness)"
expect_eq "M4 …the task it is on reads ⛔ with the red in its clause, and the Bottom line moves it from in flight to blocked" \
  "⛔ 4/T8: The long one — red at head, next on the line|- Next: T5, T6 and T7 in flight; T8 blocked; then T9, T10, T11 and 6 more." \
  "$(sr_rows | /usr/bin/grep 'T8:')|$(sr_line '- Next: ')"
# The red answered: a later green on the same task and suite.
sr_ev "ev=verdict|row=T8|commit=$SR_C1|suite=a.test.sh|result=green|log=/rec/T8b.log|at=2026-10-06T15:00:00Z"
sr_run "$SR_PLAN"
expect_eq "M5 every red answered by a later green on its task and suite → correctness ➖, the task back in flight" \
  "$SR_MARK_NEAR correctness — 1 red suite run, answered by a later green; no open S1 or S2 finding|🔄 4/T8: The long one — next on the line" \
  "$(sr_ind correctness)|$(sr_rows | /usr/bin/grep 'T8:')"
# An open S2 finding of a registered reading: correctness ✖️.
printf 'reviewed: %s..%s\nfindings: 1\nfinding: 1 S2 on lib/t1.sh:3 the thing breaks\nshown: 1 bash tests/x.test.sh\n' "$SR_C1" "$SR_H" > "$SR_DIR/critic.md"
awk -v h="$SR_H" '{ print } /^current: 4$/ { print "proved: kind=review head=" h " at=2026-10-06T20:00:00Z evidence=record/wave-02-fx/critic.md question=adversarial reader=crit result=fail scope=piece" }' "$SR_PLAN" > "$SR_PLAN.t" && mv "$SR_PLAN.t" "$SR_PLAN"
sr_run "$SR_PLAN"
expect_eq "M6 an open S2 finding of a registered reading → correctness ✖️" \
  "$SR_MARK_OVER correctness — 1 red suite run, answered by a later green; 1 open S1 or S2 finding" "$(sr_ind correctness)"
# The clock 1.25× behind: a 40-hour forecast needs 17 × 12/40 = 5.1, so 5, and 4 done: schedule ➖.
SR_FORECAST=40h sr_world marks-slow "6 6 12 12"
sr_run "$SR_PLAN"
expect_eq "M7 4 done where the forecast's pace needs 5 (within 1.25× behind) → schedule ➖" \
  "$SR_MARK_NEAR schedule — 4 of 17 tasks done in 12 h, the forecast's pace needs 5; the median one-file landing takes 9 min, within the 15 min bar" "$(sr_ind schedule)"
# …further behind: a 24-hour forecast needs 17 × 12/24 = 8.5, so 9.
SR_FORECAST=24h sr_world marks-late "6 6 12 12"
sr_run "$SR_PLAN"
expect_eq "M7b 4 done where the pace needs 9 (over 1.25× behind) → schedule ✖️, the bar half still within" \
  "$SR_MARK_OVER schedule — 4 of 17 tasks done in 12 h, the forecast's pace needs 9; the median one-file landing takes 9 min, within the 15 min bar" "$(sr_ind schedule)"
# 20% of runs discarded: waste ✖️.
sr_world marks-waste "6 6 12 12"
sr_ev "ev=verdict|row=T8|commit=$SR_C1|suite=a.test.sh|result=discarded|log=/rec/T8.log|at=2026-10-06T14:00:00Z"
sr_run "$SR_PLAN"
expect_eq "M8 one run in five discarded (20%) → waste ✖️" \
  "$SR_MARK_OVER waste — 20% of suite runs discarded; no writer slot sat idle" "$(sr_ind waste)"
# Idle width: an idle turn from 16:00Z to 17:12Z is 72 of 720 elapsed minutes, 10%: ➖.
sr_world marks-idle "6 6 12 12"
printf 'fill-ledger/v1|at=2026-10-06T16:00:00Z|session=%s|turn=t2|current=4|state=ok|ceiling=|width=4|open=3|free=1|ready=T9|launched=|declined=|missed=1|idle=T9|room=1\n' "$SID" >> "$SR_DIR/fill-ledger.log"
printf 'fill-ledger/v1|at=2026-10-06T17:12:00Z|session=%s|turn=t3|current=4|state=ok|ceiling=|width=4|open=4|free=0|ready=|launched=T9|declined=|missed=0|idle=|room=0\n' "$SID" >> "$SR_DIR/fill-ledger.log"
sr_run "$SR_PLAN"
expect_eq "M9 72 idle minutes over 720 elapsed (10%) → waste ➖, the minutes fill-report's" \
  "$SR_MARK_NEAR waste — nothing discarded; a writer slot sat idle 10% of the time" "$(sr_ind waste)"
# Nothing done on this run, 12 hours in: the clock still reads, and is behind; the bar still prints.
sr_world marks-none none
sr_run "$SR_PLAN"
expect_eq "M10 nothing done yet: the clock half is behind (0 where 4 are needed) → ✖️, and the bar still prints with its number" \
  "$SR_MARK_OVER schedule — 0 of 17 tasks done in 12 h, the forecast's pace needs 4; no one-file landing yet against the 15 min bar" "$(sr_ind schedule)"
# …and with no forecast declared, neither half can be graded: ❔, each half saying why.
SR_FORECAST= sr_world marks-bare none
sr_run "$SR_PLAN"
expect_eq "M10b no forecast declared and no landing: schedule ❔, the bar still on the line" \
  "$SR_MARK_NONE schedule — the clock cannot be graded, the plan declares no forecast; no one-file landing yet against the 15 min bar" "$(sr_ind schedule)"

# ============================================================
section "§CLOCK: the schedule mark reads the clock, tasks done since the Step-3 approval against the pace the plan's forecast: needs, ✅ at or ahead, ➖ within 1.25× behind, ✖️ further; the median landing against the 15-minute bar beside it; the declared sizes feed nothing of the mark"
# ============================================================
# 39 tasks, 4 done (10%), 11 hours after approval, against a 24-hour forecast: the pace needs 39 × 11/24 = 17.9,
# so 18. The four landings take 120 120 134 134 minutes: median 127.
SR_FORECAST=24h SR_EXTRA=22 sr_world clock "120 120 134 134"
SR_AT=$((SR_NOW - 3600)) sr_run "$SR_PLAN"
expect_eq "CK0 precondition: 39 tasks, 4 done, read by the Completion" "- 4 of 39 tasks done (10%)." "$(sr_sect Completion | sed -n 2p)"
SR_CK1="$(sr_ind schedule)"
SR_CK1_PACE="$(sr_line '- The pace: ')"
expect_eq "CK1 10% done after 11 hours of a 24-hour forecast: ✖️, the counts and the needed pace, the median against the 15 min bar beside it" \
  "$SR_MARK_OVER schedule — 4 of 39 tasks done in 11 h, the forecast's pace needs 18; the median one-file landing takes 127 min, over the 15 min bar" "$SR_CK1"
# The declared sizes change and nothing else: the mark and its line do not move. The forecast's pace line, which
# still reads the sizes, is the proof the rewrite reached the renderer.
awk -F'|' 'BEGIN { OFS = "|" } $2 ~ /^ T[1-4] $/ { $9 = " 500 " } { print }' "$SR_PLAN" > "$SR_PLAN.t" && mv "$SR_PLAN.t" "$SR_PLAN"
SR_AT=$((SR_NOW - 3600)) sr_run "$SR_PLAN"
expect_eq "CK2a precondition: the sizes rewrite reached the page (the pace line moved: 500 min planned)" \
  "yes|yes" "$(sr_line '- The pace: ' | /usr/bin/grep -q 'against 500 min planned' && echo yes)|$([ "$(sr_line '- The pace: ')" != "$SR_CK1_PACE" ] && echo yes)"
expect_eq "CK2 …and the schedule line is byte for byte what it was: the declared sizes feed nothing of the mark" \
  "$SR_CK1" "$(sr_ind schedule)"
# Ahead of pace: a 120-hour forecast needs 39 × 11/120 = 3.6, so 4, and 4 done in a 9-minute median.
SR_FORECAST=120h SR_EXTRA=22 sr_world clock-ahead "6 6 12 12"
SR_AT=$((SR_NOW - 3600)) sr_run "$SR_PLAN"
expect_eq "CK3 a fixture at the forecast's pace, its median under the bar: ✅" \
  "$SR_MARK_WITHIN schedule — 4 of 39 tasks done in 11 h, the forecast's pace needs 4; the median one-file landing takes 9 min, within the 15 min bar" "$(sr_ind schedule)"
# The scorecard's target is the same bar, and its schedule line is the page's, joined to one line.
SR_SC="$(SR_AT=$((SR_NOW - 3600)) sr_poke landing-report --scorecard "$SR_PLAN" 2>/dev/null)"
expect_eq "CK4 the scorecard's widest landing prints against target < 15, the landing bar" \
  "widest landing ready→landed: T3 12.0 min · target < 15" "$(printf '%s\n' "$SR_SC" | /usr/bin/grep '^widest landing ')"
expect_eq "CK5 …and its schedule line is the page's logical schedule line, byte for byte" \
  "$(sr_ind schedule)" "$(printf '%s\n' "$SR_SC" | /usr/bin/grep -E '^[^ ]+ schedule ')"

# ============================================================
section "§BAR-PLANT: planted 20-minute landings turn the indicator ✖️ with the clock at pace; the bar is LINE_LANDING_BAR in lib/line.sh, read by the sitrep and the scorecard alike"
# ============================================================
sr_world bar-plant "20 20 20 20"
sr_run "$SR_PLAN"
expect_eq "BP1 four landings of 20 minutes, the clock at pace (4 of 17, needs 4): the median over the 15 min bar turns the indicator ✖️" \
  "$SR_MARK_OVER schedule — 4 of 17 tasks done in 12 h, the forecast's pace needs 4; the median one-file landing takes 20 min, over the 15 min bar" "$(sr_ind schedule)"
sr_run --line "$SR_PLAN"
expect_eq "BP2 …and the one-line form opens on it (the line: $OUT)" "yes" "$([ "${OUT#"$SR_MARK_OVER$SR_MARK_WITHIN$SR_MARK_WITHIN · "}" != "$OUT" ] && echo yes)"
sr_world bar-near "17 17 17 17"
sr_run "$SR_PLAN"
expect_eq "BP3 a 17-minute median, within 1.25× of the bar: ➖" \
  "$SR_MARK_NEAR schedule — 4 of 17 tasks done in 12 h, the forecast's pace needs 4; the median one-file landing takes 17 min, over the 15 min bar" "$(sr_ind schedule)"
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
expect_eq "BP5 under the mutant bar of 25 the same 20-minute landings render (rc 0) and read ✅ within the 25 min bar" \
  "0|$SR_MARK_WITHIN schedule — 4 of 17 tasks done in 12 h, the forecast's pace needs 4; the median one-file landing takes 20 min, within the 25 min bar" "$RC|$(sr_ind schedule)"
expect_eq "BP6 …and the scorecard's target reads it too" \
  "widest landing ready→landed: T1 20.0 min · target < 25" "$(printf '%s\n' "$SR_MUT_SC" | /usr/bin/grep '^widest landing ')"

# ============================================================
section "§BLOCKERS: every open approve:, waive:, finding: and gate: item the run's sessions owe, one bullet each in words, or the nothing bullet; the Bottom line counts them"
# ============================================================
sr_world blockers "6 6 12 12"
sr_bind
sr_run "$SR_PLAN"
expect_eq "B1 an empty ledger prints the one nothing bullet under Blocked on you, and the Bottom line says you owe nothing" \
  "- Nothing: no decision or action is owed by you.|- You owe nothing now." \
  "$(sr_sect 'Blocked on you' | sr_join)|$(sr_line '- You owe ')"
sr_owed "key=approve:release|state=open|sent=-|at=2026-10-06T20:00:00Z|title=approval: release|reply=poker: WAIT T12 — approval:release"
sr_owed "key=ruling:r1|state=open|sent=-|at=2026-10-06T20:01:00Z|title=ruling unread: w-T5|reply=poker: RULING r1 unread by w-T5"
sr_owed "key=approve:merge|state=open|sent=-|at=2026-10-06T20:02:00Z|title=approval: merge|reply=poker: WAIT T17 — approval:merge"
sr_owed "key=approve:old|state=closed|by=approve|at=2026-10-06T19:30:00Z"
sr_owed "key=waive:structure|state=open|sent=-|at=2026-10-06T20:03:00Z|title=waiver: structure|reply=poker: the structure reading is owed at the head — waive structure '<reply>' or read it"
sr_run "$SR_PLAN"
expect_eq "B2 two open approve: items and one waive: print as three bullets in the ledger's order, each saying what to do and what waits on it; a closed item and a writer's ruling item do not" \
  "- approve release: T12 waits on it|- approve merge: T17 waits on it|- waive or read structure: the structure reading is owed at the head — waive structure '<reply>' or read it" \
  "$(sr_sect 'Blocked on you' | sr_join)"
expect_eq "B2b …and the Bottom line names them, counted" \
  "- You owe 3: approve release, approve merge and waive or read structure." "$(sr_line '- You owe ')"
expect_eq "B3 …a task whose reads wait on an open approval reads ⛔ (blocked), and the Bottom line says so" \
  "⛔ 4/T12: Release-gated row — waits on your approval of release|⛔ 4/T17: Merge-gated row — waits on your approval of merge|- Next: T8, T5, T6 and T7 in flight; T12 and T17 blocked; then T9, T10, T11 and 4 more." \
  "$(sr_rows | /usr/bin/grep -E 'T1[27]:' | sr_join)|$(sr_line '- Next: ')"

# ============================================================
section "§SHAPE: the page is the prototype's — title with the step and the task count, Bottom line, Task list, Score, Blocked on you, Completion, Predicted close; no glyph before the Bottom line; every section bulleted; every line at most 92 columns; a task in flight carries its state in words"
# ============================================================
# sr_breaks -> the first physical line that breaks its section's form, or nothing: a bulleted section's lines open
# on `- ` or a two-space continuation; a Task list line on a glyph or a five-space continuation; a Score line on a
# mark, a three-space continuation, or the rationale's bullet and its continuation.
sr_breaks() {
  printf '%s\n' "$OUT" | awk '
    NR == 1 { next }
    $0 == "" { h = ""; nh = 1; next }
    nh { h = $0; nh = 0; next }
    h == "Task list" { if ($0 ~ /^     [^ ]/ || $0 ~ /^[^ -][^ ]* [0-9]/) next; print; exit }
    h ~ /^Score: / { if ($0 ~ /^   [^ ]/ || $0 ~ /^- / || $0 ~ /^  [^ ]/ || $0 ~ /^[^ -][^ ]* [a-z]/) next; print; exit }
    h != "" { if ($0 ~ /^- / || $0 ~ /^  [^ ]/) next; print; exit }
    { print; exit }'
}
SR_LONG="A task whose description runs well past the width of the page, so the renderer has to fold it onto a second line"
sr_world shape "6 6 12 12"
awk -v t="$SR_LONG" -F'|' 'BEGIN { OFS = "|" } $2 == " T10 " { $5 = " " t " · complexity: standard " } { print }' "$SR_PLAN" > "$SR_PLAN.t" && mv "$SR_PLAN.t" "$SR_PLAN"
sr_run "$SR_PLAN"
expect_eq "H1 the sections, in the prototype's order, each heading after a blank line" \
  "Bottom line|Task list|Score: not graded yet|Blocked on you|Completion|Predicted close" "$(printf '%s\n' "$OUT" | sr_heads)"
expect_eq "H2 the title carries the step of nine and the task count" \
  "Sitrep · shape 9.9.0 · Tuesday 3:00 PM · step 4 of 9 · 4 of 17 tasks done" "$(printf '%s\n' "$OUT" | head -1)"
SR_GL1="$(printf '%s\n' "$OUT" | /usr/bin/grep -nE '✅|🔄|⬜|⛔|❔|➖|✖' | head -1 | cut -d: -f1)"
SR_BL1="$(printf '%s\n' "$OUT" | /usr/bin/grep -n '^Bottom line$' | head -1 | cut -d: -f1)"
expect_eq "H3 no glyph before the Bottom line: the first glyph sits below its heading, which is line 3" "3|yes" \
  "$SR_BL1|$([ -n "$SR_GL1" ] && [ "$SR_GL1" -gt "${SR_BL1:-0}" ] && echo yes)"
expect_eq "H4 the Bottom line's four bullets answer owe, next, done and close, in that order" "You|Next:|Done:|Close:" \
  "$(sr_sect 'Bottom line' | cut -d' ' -f2 | sr_join)"
expect_eq "H5a the width measure, proved on known strings: a mark is two columns, U+FE0F none, an emoji two, an accented letter one" \
  "5|4|10|11" "$(printf '%s\n' '✅ ab' '✖️ x' '🔄 4/T1: é' '⬜ ⛔ ❔ ➖' | sr_widths | sr_join)"
SR_MAXW="$(printf '%s\n' "$OUT" | sr_maxw)"
expect_eq "H5 every line of the page is at most 92 columns, and the widest is a folded one near the edge (widest $SR_MAXW)" "yes" \
  "$([ "${SR_MAXW:-999}" -le 92 ] && [ "${SR_MAXW:-0}" -ge 80 ] && echo yes)"
expect_eq "H5b …the long description folds at a space onto a five-space continuation, and reads whole when joined" \
  "yes|⬜ 4/T10: $SR_LONG" \
  "$(printf '%s\n' "$OUT" | /usr/bin/grep -A1 '^⬜ 4/T10: ' | sed -n 2p | /usr/bin/grep -qE '^     [^ ]' && echo yes)|$(sr_rows | /usr/bin/grep '/T10: ')"
expect_eq "H6 every section is bulleted: no physical line breaks its section's form" "" "$(sr_breaks)"
expect_eq "H6b …read through the same sections: four Bottom line bullets, one under Blocked on you, two under Completion" "4|1|2" \
  "$(sr_sect 'Bottom line' | /usr/bin/grep -c '^- ')|$(sr_sect 'Blocked on you' | /usr/bin/grep -c '^- ')|$(sr_sect Completion | /usr/bin/grep -c '^- ')"
expect_eq "H7 every task in flight carries its state in words after a dash" "4|4" \
  "$(sr_rows | /usr/bin/grep -c '^🔄 ')|$(sr_rows | /usr/bin/grep -cE '^🔄 [^ ]+: .* — [a-z]')"

# ============================================================
section "§SLOTS: the skill writes only the grade and a rationale that names an indicator line; sitrep grade records it, refuses an uncited one, and the page prints the newest under its Score"
# ============================================================
sr_world slots "6 6 12 12"
SR_LOG="$SR_DIR/sitrep.log"
sr_run grade C 'the decisions line is the red one: three rounds too many' "$SR_PLAN"
expect_eq "SL1 a grade with a rationale naming an indicator: exit 0, nothing on stderr, the confirmation line" \
  "0||poker: sitrep grade C — recorded at 3:00 PM in $(cd "$SR_DIR" && pwd -P)/sitrep.log; the next sitrep prints it" "$RC|$ERR|$OUT"
expect_eq "SL2 …the run's sitrep.log gains one sitrep-grade/v1 line with the time, the letter and the words" \
  "sitrep-grade/v1|at=2026-10-06T22:00:00Z|grade=C|why=the decisions line is the red one: three rounds too many" "$(cat "$SR_LOG" 2>/dev/null)"
sr_run "$SR_PLAN"
expect_eq "SL3 the next page heads its Score with the grade and its time, and ends the Score on the rationale, under the goals line" \
  "Score: C (graded 3:00 PM)|$SR_MARK_NONE goals — none declared|- the decisions line is the red one: three rounds too many" \
  "$(printf '%s\n' "$OUT" | sr_heads | cut -d'|' -f3)|$(sr_sect 'Score: .*' | tail -2 | sr_join)"
sr_run grade C 'the run is going fine' "$SR_PLAN"
expect_eq "SL4 a rationale naming no indicator line is refused (1), naming it, and the log is unchanged" \
  "1|1|1" "$RC|$(printf '%s\n' "$ERR" | /usr/bin/grep -c "'the run is going fine'")|$(/usr/bin/grep -c . "$SR_LOG")"
sr_run grade G 'the schedule line is behind' "$SR_PLAN"
expect_eq "SL5 a grade outside A to F is refused (1), the log unchanged" "1|1" "$RC|$(/usr/bin/grep -c . "$SR_LOG")"
sr_run grade C 'waste | correctness' "$SR_PLAN"
expect_eq "SL6 a rationale holding a | (the record's separator) is refused (1), the log unchanged" "1|1" "$RC|$(/usr/bin/grep -c . "$SR_LOG")"
sr_run grade C "$SR_PLAN"
expect_eq "SL7 a grade with no rationale is the usage error (2), the log unchanged" "2|1" "$RC|$(/usr/bin/grep -c . "$SR_LOG")"
SR_AT=$((SR_NOW + 600)) sr_run grade B 'Schedule caught up once the long task moved' "$SR_PLAN"
SR_AT=$((SR_NOW + 900)) sr_run "$SR_PLAN"
expect_eq "SL8 a later grade, its indicator named in any case, replaces the one shown: its letter, its time, its words alone" \
  "Score: B (graded 3:10 PM)|- Schedule caught up once the long task moved|0" \
  "$(printf '%s\n' "$OUT" | sr_heads | cut -d'|' -f3)|$(sr_sect 'Score: .*' | tail -1)|$(sr_sect 'Score: .*' | /usr/bin/grep -c 'three rounds too many')"

# ============================================================
section "§SCOPE: what you owe is read from the named plan's run, never the session running the verb; a delivered plan prints no close; the plan's table words never print"
# ============================================================
SID2="9a8b7c6d-1e2f-4a3b-8c4d-5e6f7a8b9c0d"
SID3="0f1e2d3c-4b5a-4968-8778-695a4b3c2d1e"
sr_world scope "6 6 12 12"
SR_PLAN_A="$SR_PLAN"; SR_PLAN_B="$SR_REPO/.bionic/docs/plans/epic-01-fx/wave-03-fx.plan.md"
sed 's/wave-02-fx/wave-03-fx/g; s/wave\/02-fx/wave\/03-fx/g; s/9\.9\.0/9.10.0/' "$SR_PLAN_A" > "$SR_PLAN_B"
sr_bind "$SR_PLAN_A" "$SID"
sr_bind "$SR_PLAN_B" "$SID2"
sr_owed "key=approve:release|state=open|sent=-|at=2026-10-06T20:00:00Z|title=approval: release|reply=poker: WAIT T12 — approval:release" "$SID"
sr_owed "key=approve:merge|state=open|sent=-|at=2026-10-06T20:01:00Z|title=approval: merge|reply=poker: WAIT T17 — approval:merge" "$SID2"
sr_owed "key=waive:structure|state=open|sent=-|at=2026-10-06T20:02:00Z|title=waiver: structure|reply=poker: the structure reading is owed" "$SID3"
sr_run "$SR_PLAN_B"
expect_eq "SC0 precondition: the other run's session is bound and its store is read — plan B owes its own item" \
  "- approve merge: T17 waits on it" "$(sr_sect 'Blocked on you' | sr_join)"
sr_run "$SR_PLAN_A"
SR_PAGE_A="$OUT"
expect_eq "SC1 plan A owes only its own session's item: not the other run's, not an unbound session's" \
  "- approve release: T12 waits on it" "$(sr_sect 'Blocked on you' | sr_join)"
SR_SID="$SID2" sr_run "$SR_PLAN_A"
expect_eq "SC2 …and the same when the verb runs in the other run's session: the session running it plays no part" \
  "- approve release: T12 waits on it" "$(sr_sect 'Blocked on you' | sr_join)"
sr_run --line "$SR_PLAN_A"
expect_eq "SC3 …the one-line form counts the plan's item alone" "owed: 1" "$(printf '%s\n' "$OUT" | /usr/bin/grep -oE 'owed: [0-9]+')"
# A delivered plan with a task still open after the delivery: its close is gone, whatever the chain says.
sr_w38_world
awk '/^\| T21 \| / { sub(/\| landed \|/, "| active |") } { print }' "$SR_PLAN" > "$SR_PLAN.t" && mv "$SR_PLAN.t" "$SR_PLAN"
sr_run "$SR_PLAN"
SR_PAGE_D="$OUT"
expect_eq "SC4 precondition: the delivered plan still holds an open task" "🔄 4/T21: Row 21 of wave 38 — building" "$(sr_rows | /usr/bin/grep '/T21: ')"
expect_eq "SC5 a delivered plan prints its delivery and no close, in Predicted close and in the Bottom line" \
  "- Delivered at 8:07 AM 2026-10-18; nothing is left to forecast.|- Close: delivered at 8:07 AM 2026-10-18." \
  "$(sr_sect 'Predicted close' | sr_join)|$(sr_line '- Close: ')"
expect_eq "SC6 …no closing time anywhere on its page (the forecast page above prints one: FC1)" "0" "$(printf '%s\n' "$OUT" | /usr/bin/grep -c 'About ')"
sr_run --line "$SR_PLAN"
expect_eq "SC7 …and the one-line form says delivered, no time" "yes" "$(printf '%s\n' "$OUT" | /usr/bin/grep -qE ' · delivered$' && echo yes)"
for SR_W in A D; do
  eval "SR_PG=\"\$SR_PAGE_$SR_W\""
  expect_eq "SC8$SR_W the plan's table words never print on page $SR_W: no 'rows', no status name, no cell value — beside its task lines" "0|0|0|yes" \
    "$(printf '%s\n' "$SR_PG" | /usr/bin/grep -ciw 'rows')|$(printf '%s\n' "$SR_PG" | /usr/bin/grep -ciwE 'landed|pending|active|dropped|held')|$(printf '%s\n' "$SR_PG" | /usr/bin/grep -cE 'approval:|step:[0-9]|lib/[a-z]')|$([ "$(printf '%s\n' "$SR_PG" | /usr/bin/grep -cE '^(✅|🔄|⬜|⛔) [0-9]+/T')" -ge 17 ] && echo yes)"
done

# ============================================================
section "§FORECAST: the close is the open work at the measured pace, the larger of the longest chain and the work over the count the gate admits; before approval it is the no-forecast sentence; no typed number moves it, and admitting more never shortens one chain"
# ============================================================
sr_world forecast "6 6 12 12"
sr_run "$SR_PLAN"
expect_eq "FC1 the Predicted close: the time, the work and the chain behind it, the pace, the assumption" \
  "- About 7:48 PM.|- The work left is 480 min as planned, 240 min over the 2 suite runs the gate admits; the longest chain left, T8 → T9, is 150 min; the larger, 240 min, at the pace below is 4 h 48 min.|- The pace: the median landing takes 9 min against 7.5 min planned, 1.2×.|- It assumes what you owe is answered now." \
  "$(sr_sect 'Predicted close' | sr_join)"
expect_eq "FC1b …and the Bottom line's close is the same time" "- Close: about 7:48 PM." "$(sr_line '- Close: ')"
SR_FC1_ABOUT="$(sr_line '- About ')"
awk '{ sub(/^forecast: 48h$/, "forecast: 24h") } { print }' "$SR_PLAN" > "$SR_PLAN.t" && mv "$SR_PLAN.t" "$SR_PLAN"
sr_run "$SR_PLAN"
expect_eq "FC2 a typed number moves nothing: the plan's forecast: halved, the close is the same (the schedule line did read it: pace needs 9)" \
  "$SR_FC1_ABOUT|yes" "$(sr_line '- About ')|$(sr_ind schedule | /usr/bin/grep -q 'pace needs 9' && echo yes)"
# One admitted request, not two: the work is no longer divided and outweighs the chain.
rm -f "$SR_GATE/requests/2"
sr_run "$SR_PLAN"
expect_eq "FC3 one admitted run: 480 min of work, 9 h 36 min at 1.2×, past midnight with its date" \
  "- About 12:36 AM 2026-10-07.|- The work left is 480 min as planned, 480 min over the 1 suite run the gate admits; the longest chain left, T8 → T9, is 150 min; the larger, 480 min, at the pace below is 9 h 36 min." \
  "$(sr_sect 'Predicted close' | sed -n 1,2p | sr_join)"
rm -f "$SR_GATE/requests/1"
sr_run "$SR_PLAN"
expect_eq "FC4 no admitted run: one, never none, and said" \
  "- About 12:36 AM 2026-10-07.|yes" "$(sr_line '- About ')|$(sr_line '- The work left ' | /usr/bin/grep -q 'over 1 suite run, none admitted now' && echo yes)"
# Before the first landing: the previous delivered run's measured pace, and the line says so.
sr_world forecast-none none
sr_prev 96
sr_run "$SR_PLAN"
expect_eq "FC5 nothing done on this run: the pace is the delivered run's 1.6×, said; 510 min of work over 2 is 255, at 1.6× 6 h 48 min" \
  "- About 9:48 PM.|- The work left is 510 min as planned, 255 min over the 2 suite runs the gate admits; the longest chain left, T8 → T9, is 150 min; the larger, 255 min, at the pace below is 6 h 48 min.|- The pace: wave-01's measured 1.6×; no landing yet on this run.|- It assumes what you owe is answered now." \
  "$(sr_sect 'Predicted close' | sr_join)"
sr_world forecast-bare none
sr_run "$SR_PLAN"
expect_eq "FC6 no pace on this run or a delivered one: no forecast, said, in both places" \
  "- No forecast: no pace is measured on this run or a delivered one.|- Close: no forecast; no pace is measured on this run or a delivered one." \
  "$(sr_sect 'Predicted close' | sr_join)|$(sr_line '- Close: ')"
SR_APPROVED=none sr_world forecast-unapproved "6 6 12 12"
sr_run "$SR_PLAN"
expect_eq "FC7 no approved-by: the no-forecast sentence, in Predicted close and the Bottom line, and no time" \
  "- No forecast until the plan is approved at Step 3.|- The forecast will be the plan's chain at the line's measured pace, never a typed number.|- Close: no forecast until the plan is approved at Step 3.|0" \
  "$(sr_sect 'Predicted close' | sr_join)|$(sr_line '- Close: ')|$(printf '%s\n' "$OUT" | /usr/bin/grep -c 'About ')"
# The close on the local clock: a time on now's day bare, past midnight with its date.
sr_world forecast-late "6 6 12 12"
SR_AT=$((SR_NOW - 6 * 3600)) sr_run "$SR_PLAN"
expect_eq "FC8 at 9:00 AM, 4 h 48 min on is the same local day: no date" "- About 1:48 PM." "$(sr_line '- About ')"
SR_AT=$((SR_NOW + 12 * 3600)) sr_run "$SR_PLAN"
expect_eq "FC9 …at 3:00 AM the next morning, now's own day: no date" "- About 7:48 AM." "$(sr_line '- About ')"
SR_AT=$((SR_NOW + 8 * 3600 + 1800)) sr_run "$SR_PLAN"
expect_eq "FC10 …at 11:30 PM, 4 h 48 min on is past midnight: the date follows" "- About 4:18 AM 2026-10-07." "$(sr_line '- About ')"
# One chain: every open task reads what the one before it writes, so no width can shorten it.
sr_world one-chain "6 6 12 12"
awk -F'|' 'BEGIN { OFS = "|" }
  $2 ~ /^ T([5-9]|1[0-7]) $/ { n = $2; gsub(/[ T]/, "", n); if (n + 0 > 5) $8 = " lib/t" (n - 1) ".sh " }
  { print }' "$SR_PLAN" > "$SR_PLAN.t" && mv "$SR_PLAN.t" "$SR_PLAN"
sr_run "$SR_PLAN"
SR_OC2="$(sr_line '- About ')"; SR_OC2W="$(sr_line '- The work left ' | /usr/bin/grep -oE 'over the [0-9]+ suite runs')"
SR_OC2MAX="$(printf '%s\n' "$OUT" | sr_maxw)"
for i in 3 4; do
  printf 'key=a.test.sh\nkind=landing\nwho=%s:w-T%d\ntree=/elsewhere/project\nasked=%d\nholder=%s:\nadmitted=%d\npromise=5:0.1:30\n' \
    "$SID" "$((i + 4))" "$((SR_NOW - 600))" "$$" "$((SR_NOW - 590))" > "$SR_GATE/requests/$i"
done
sr_run "$SR_PLAN"
expect_eq "FC11 precondition: the chain is every open task, and the gate's count reached the page, 2 then 4" \
  "yes|over the 2 suite runs|over the 4 suite runs" \
  "$(sr_line '- The work left ' | /usr/bin/grep -q 'T5 → T6 → T7 → T8 → T9 → T10 → T11 → T12 → T13 → T14 → T15 → T16 → T17, is 480 min' && echo yes)|$SR_OC2W|$(sr_line '- The work left ' | /usr/bin/grep -oE 'over the [0-9]+ suite runs')"
expect_eq "FC12 admitted 2 then 4 on one chain: the close does not move, 480 min at 1.2× either way" \
  "- About 12:36 AM 2026-10-07.|- About 12:36 AM 2026-10-07." "$SR_OC2|$(sr_line '- About ')"
expect_eq "FC13 …and the long chain folds within 92 columns (widest $SR_OC2MAX)" "yes" "$([ "${SR_OC2MAX:-999}" -le 92 ] && echo yes)"

# ============================================================
section "§LINE: --line is the one-line form, the three indicator glyphs in order · owed: <n> · the close"
# ============================================================
sr_world line "6 6 12 12"
sr_bind
sr_run --line "$SR_PLAN"
expect_eq "L1 the clean world: one line, exit 0" "0|$SR_MARK_WITHIN$SR_MARK_WITHIN$SR_MARK_WITHIN · owed: 0 · closes ~7:48 PM" "$RC|$OUT"
sr_ev "ev=verdict|row=T8|commit=$SR_C1|suite=a.test.sh|result=red|log=/rec/T8.log|at=2026-10-06T14:00:00Z"
sr_owed "key=approve:release|state=open|sent=-|at=2026-10-06T20:00:00Z|title=approval: release|reply=poker: WAIT T12 — approval:release"
sr_owed "key=gate:abc|state=open|sent=-|at=2026-10-06T20:00:00Z|title=gate act: merge|reply=poker: GATE T28 — merge: approve it"
sr_run --line "$SR_PLAN"
expect_eq "L2 a red at head and two owed items: the correctness glyph moves, owed counts them" \
  "$SR_MARK_WITHIN$SR_MARK_OVER$SR_MARK_WITHIN · owed: 2 · closes ~7:48 PM" "$OUT"
sr_run "$SR_PLAN"
expect_eq "L3 …the one line's glyphs are the full page's first three marks, in order" \
  "$SR_MARK_WITHIN$SR_MARK_OVER$SR_MARK_WITHIN" "$(sr_page | awk '$2 == "schedule" || $2 == "correctness" || $2 == "waste" { printf "%s", $1 }')"
SR_FORECAST= sr_world line-none none
sr_run --line "$SR_PLAN"
expect_eq "L4 an indicator the record cannot compute (no forecast:, no landing) prints ❔ in the one line, and so does an unverified close" \
  "$SR_MARK_NONE$SR_MARK_WITHIN$SR_MARK_WITHIN · owed: 0 · closes unverified" "$OUT"
SR_APPROVED=none sr_world line-unapproved "6 6 12 12"
sr_run --line "$SR_PLAN"
expect_eq "L5 an unapproved plan: no forecast, said" "$SR_MARK_NONE$SR_MARK_WITHIN$SR_MARK_WITHIN · owed: 0 · no forecast until approved" "$OUT"

# ============================================================
section "§ARGS: the verb's operands"
# ============================================================
sr_world args "6 6 12 12"
sr_run --line --line "$SR_PLAN"
expect_eq "A1 --line twice is the usage error (2)" "2" "$RC"
sr_run "$SR_REPO/no/such.plan.md"
expect_eq "A2 a named plan that is no file is refused (2), naming it" \
  "2|1" "$RC|$(printf '%s\n' "$ERR" | /usr/bin/grep -c 'no plan file at')"
sr_run grade "$SR_PLAN"
expect_eq "A3 grade with no letter is the usage error (2)" "2" "$RC"
sr_run grade C 'the schedule line' 'the waste line' "$SR_PLAN"
expect_eq "A4 grade with two rationales is the usage error (2)" "2" "$RC"
sr_run bottom-line 'schedule holds (line 3)' "$SR_PLAN"
expect_eq "A5 the old bottom-line slot is gone: refused (2), nothing written" "2|no" "$RC|$([ -e "$SR_DIR/sitrep.log" ] && echo yes || echo no)"


# ============================================================
# THE SKILL AND ITS SURFACES.
#
# THE CONTRACT CHECKER. /bionic:sitrep is a skill: the model runs the verb, writes the grade and its rationale
# through the verb, and shows the page the verb then prints. What a suite can pin is the contract, so `sr_check`
# is that contract as code. Its heading list is read from the skill's shape block, not written here, so without
# the skill nothing in these sections can pass. The rules: the title line is the page's first line, byte for byte,
# and opens `Sitrep · `; no rule line; the headings are the shape's, in the shape's order (the Score heading by
# its `Score:` lead, the letter being the run's); and the report IS the page, every line the verb's, byte for byte.
# ============================================================
SR_SKILL="${BIONIC_SKILLS_DIR}/sitrep/SKILL.md"
# sr_shape -> the skill's page shape: the first ```text fence whose first line opens `Sitrep · `.
sr_shape() {
  awk '/^```text$/ { if (!done) { f = 1; first = 1 }; next } f && /^```$/ { if (keep) exit; f = 0; next }
       f && first { first = 0; if (index($0, "Sitrep · ") == 1) keep = 1 } f && keep { print }' "$SR_SKILL" 2>/dev/null
}
sr_norm() { tr '|' '\n' | sed 's/^Score: .*/Score:/' | sr_join; }
sr_check() {  # <report file> <page file> -> `ok`, or the first rule the report breaks
  local rep="$1" page="$2" want l
  want="$(sr_shape | sr_heads | sr_norm)"
  [ -n "$want" ] || { echo "no shape"; return; }
  l="$(head -1 "$rep")"
  { [ "$l" = "$(head -1 "$page")" ] && [ "${l#Sitrep · }" != "$l" ]; } || { echo "title"; return; }
  /usr/bin/grep -qE '^[-=─━_]{3,}$' "$rep" && { echo "rule line"; return; }
  [ "$(sr_heads "$rep" | sr_norm)" = "$want" ] || { echo "headings: $(sr_heads "$rep")"; return; }
  l="$(diff "$page" "$rep" | /usr/bin/grep -E '^[<>]' | head -1)"
  [ -z "$l" ] || { echo "fact: $l"; return; }
  echo ok
}

# ============================================================
section "§SKILL: the skill's page opens Sitrep · …, then Bottom line, Task list, Score, Blocked on you, Completion, Predicted close; it records only the grade and its rationale, and shows the verb's page unaltered"
# ============================================================
SR_SHAPE="$(sr_shape)"
expect_eq "O1 the skill's shape block is found and its first line is the title line's form" \
  "Sitrep · <project> <release> · <weekday> <time> · step <n> of 9 · <k> of <m> tasks done" "$(printf '%s\n' "$SR_SHAPE" | head -1)"
expect_eq "O2 …its headings, in order, the prototype's" \
  "Bottom line|Task list|Score: <grade> (graded <time>)|Blocked on you|Completion|Predicted close" "$(printf '%s\n' "$SR_SHAPE" | sr_heads)"
expect_eq "O3 …and no rule line in the shape (the same block O1 read)" "" "$(printf '%s\n' "$SR_SHAPE" | /usr/bin/grep -E '^[-=─━_]{3,}$')"
sr_world skill "6 6 12 12"
sr_run grade C 'the schedule line holds; nothing else is graded yet' "$SR_PLAN"
sr_run "$SR_PLAN"; printf '%s\n' "$OUT" > "$TMPROOT/page.txt"
expect_eq "O4 the verb's page after a grade: its headings are the shape's, the Score heading carrying the letter and time" \
  "Bottom line|Task list|Score: C (graded 3:00 PM)|Blocked on you|Completion|Predicted close" "$(sr_heads "$TMPROOT/page.txt")"
cp "$TMPROOT/page.txt" "$TMPROOT/rep.txt"
expect_eq "O5 the page shown unaltered meets the contract" "ok" "$(sr_check "$TMPROOT/rep.txt" "$TMPROOT/page.txt")"
awk '$0 == "Blocked on you" { print "Completion"; next } $0 == "Completion" { print "Blocked on you"; next } { print }' "$TMPROOT/rep.txt" > "$TMPROOT/bad.txt"
expect_regex "O6 …Blocked on you and Completion swapped: refused on the headings" "^headings: " "$(sr_check "$TMPROOT/bad.txt" "$TMPROOT/page.txt")"
sed 's/^Task list$/TASK LIST/' "$TMPROOT/rep.txt" > "$TMPROOT/bad.txt"
expect_regex "O7 …a heading uppercased: refused on the headings" "^headings: " "$(sr_check "$TMPROOT/bad.txt" "$TMPROOT/page.txt")"
awk '{ print } index($0, "- the schedule line holds") == 1 { print "- diagnosis: the gate is the bottleneck" }' "$TMPROOT/rep.txt" > "$TMPROOT/bad.txt"
expect_eq "O8 …a line of the model's own under the Score: refused, naming it" "fact: > - diagnosis: the gate is the bottleneck" \
  "$(sr_check "$TMPROOT/bad.txt" "$TMPROOT/page.txt")"
awk 'NR == 1 { print; print "─────"; next } { print }' "$TMPROOT/rep.txt" > "$TMPROOT/bad.txt"
expect_eq "O9 …a rule line under the title: refused" "rule line" "$(sr_check "$TMPROOT/bad.txt" "$TMPROOT/page.txt")"
expect_true "O14 the skill runs the verb on the bound plan" grep -qF 'bash <plugin-root>/hooks/session-poker.sh sitrep' "$SR_SKILL"
expect_true "O15 …records the grade with sitrep grade" grep -qF "hooks/session-poker.sh sitrep grade <A-F> '<rationale>'" "$SR_SKILL"
expect_eq "O15b …and names no other slot: no bottom-line verb, no Diagnosis (beside O15's read of the same file)" "0" \
  "$(/usr/bin/grep -cE 'bottom-line|Diagnosis' "$SR_SKILL")"
expect_true "O16 …says a fact outside the verb's output is a contract violation" grep -qiE "fact .*outside the verb's output is a contract violation" "$SR_SKILL"
expect_true "O17 …says the rationale names an indicator line, and which five" \
  bash -c 'grep -qiE "names? an indicator line" "$1" && grep -qF "schedule, correctness, waste, decisions or goals" "$1"' _ "$SR_SKILL"
expect_true "O18 …says what the three surfaces are: /bionic:sitrep, the handoff head, the tick's one line" \
  grep -qiE 'three surfaces.*/bionic:sitrep.*handoff.*tick' "$SR_SKILL"
expect_true "O19 …quotes the verb's confirmation line" grep -qiE "quote the verb's confirmation line" "$SR_SKILL"
expect_true "O20 …and shows the page inside one fenced code block" grep -qiE 'one fenced code block' "$SR_SKILL"

# ============================================================
section "§FACTS: every line of the report is the verb's, byte for byte; a planted fact, an altered line or an added claim fails"
# ============================================================
expect_eq "FA1 the report that is the verb's page meets the contract (the positive, same checker as below)" \
  "ok" "$(sr_check "$TMPROOT/rep.txt" "$TMPROOT/page.txt")"
awk '{ print } /^✅ 4\/T4: / { print "✅ 4/T18: Shipped early (7:30 AM)" }' "$TMPROOT/rep.txt" > "$TMPROOT/bad.txt"
expect_true "FA2 the plant is in the copy" grep -q '^✅ 4/T18: ' "$TMPROOT/bad.txt"
expect_eq "FA3 …a planted task the verb never printed: refused, naming it" "fact: > ✅ 4/T18: Shipped early (7:30 AM)" \
  "$(sr_check "$TMPROOT/bad.txt" "$TMPROOT/page.txt")"
sed 's/^- 4 of 17 tasks done (24%)\.$/- 5 of 17 tasks done (29%)./' "$TMPROOT/rep.txt" > "$TMPROOT/bad.txt"
expect_regex "FA4 …a rendered line altered (the counts): refused on the fact" "^fact: " "$(sr_check "$TMPROOT/bad.txt" "$TMPROOT/page.txt")"
awk '{ print } index($0, "- It assumes ") == 1 { print "- the release ships tonight" }' "$TMPROOT/rep.txt" > "$TMPROOT/bad.txt"
expect_eq "FA5 …an unlabelled claim appended to Predicted close: refused on the fact" "fact: > - the release ships tonight" \
  "$(sr_check "$TMPROOT/bad.txt" "$TMPROOT/page.txt")"

# ============================================================
section "§SURFACES: one renderer, three surfaces — the tick prints \`poker: sitrep <the --line output>\` on every tick, byte for byte"
# ============================================================
# sr_tick_world <label> <mins> -> a world the tick will decide on: engaged, a commit, bound, armed.
sr_tick_world() {
  sr_world "$1" "$2"
  : > "$SR_REPO/.bionic/tmp/engaged-$SID.state"
  ( cd "$SR_REPO" && git add -A >/dev/null 2>&1 && git -c user.email=t@t -c user.name=t commit -qm fixture >/dev/null 2>&1 )
  sr_poke bind "$SR_PLAN" >/dev/null 2>&1; sr_poke arm >/dev/null 2>&1
}
sr_tick() { sr_poke tick > "$TMPROOT/tick.out" 2> "$TMPROOT/tick.err"; RC=$?; OUT="$(cat "$TMPROOT/tick.out")"; }
# The tick's worlds are unapproved plans (an approved one FILLs, and S1 pins QUIET), so the clock half reads ❔
# and the close is the no-forecast form.
SR_APPROVED=none sr_tick_world surf "6 6 12 12"
sr_tick
SR_T1="$OUT"
sr_run --line "$SR_PLAN"; SR_L1="$OUT"
expect_eq "S1 the tick exits 0 and its last line is still its decision line" "0|decision=QUIET" \
  "$RC|$(printf '%s\n' "$SR_T1" | tail -1 | /usr/bin/grep -oE 'decision=[A-Z]+')"
expect_eq "S2 …it prints exactly one sitrep line" "1" "$(printf '%s\n' "$SR_T1" | /usr/bin/grep -c '^poker: sitrep ')"
expect_eq "S3 …and that line is the --line output, byte for byte (here an unapproved clean world's ❔✅✅)" \
  "poker: sitrep $SR_MARK_NONE$SR_MARK_WITHIN$SR_MARK_WITHIN · owed: 0 · no forecast until approved|poker: sitrep $SR_L1" \
  "$(printf '%s\n' "$SR_T1" | /usr/bin/grep '^poker: sitrep ')|poker: sitrep $SR_L1"
sr_ev "ev=verdict|row=T8|commit=$SR_C1|suite=a.test.sh|result=red|log=/rec/T8.log|at=2026-10-06T14:00:00Z"
sr_owed "key=approve:release|state=open|sent=-|at=2026-10-06T20:00:00Z|title=approval: release|reply=poker: WAIT T12 — approval:release"
SR_AT=$((SR_NOW + 60)) sr_tick
SR_AT=$((SR_NOW + 60)) sr_run --line "$SR_PLAN"
expect_eq "S4 a red at head and an owed item move the tick's line exactly as they move --line" \
  "poker: sitrep $SR_MARK_NONE$SR_MARK_OVER$SR_MARK_WITHIN · owed: 1 · no forecast until approved|poker: sitrep $OUT" \
  "$(/usr/bin/grep '^poker: sitrep ' "$TMPROOT/tick.out")|poker: sitrep $OUT"
SR_AT=$((SR_NOW + 120)) sr_tick
SR_T3="$OUT"
expect_contains "S5 an unchanged tick (nothing decided moved) still takes the unchanged path" "poker: unchanged since " "$SR_T3"
expect_eq "S6 …and still prints the sitrep line, above the unchanged line, which stays last" \
  "poker: sitrep $SR_MARK_NONE$SR_MARK_OVER$SR_MARK_WITHIN · owed: 1 · no forecast until approved|unchanged" \
  "$(printf '%s\n' "$SR_T3" | /usr/bin/grep '^poker: sitrep ')|$(printf '%s\n' "$SR_T3" | tail -1 | /usr/bin/grep -q '^poker: unchanged since ' && echo unchanged)"
SR_APPROVED=none sr_tick_world surf-none none
sr_tick
SR_T4="$OUT"
sr_run --line "$SR_PLAN"
expect_eq "S7 a plan with no landing: the tick prints the forms --line prints" \
  "poker: sitrep $SR_MARK_NONE$SR_MARK_WITHIN$SR_MARK_WITHIN · owed: 0 · no forecast until approved|poker: sitrep $OUT" \
  "$(printf '%s\n' "$SR_T4" | /usr/bin/grep '^poker: sitrep ')|poker: sitrep $OUT"

# ============================================================
section "§GOALS: the plan's goals: lines, each read from the reader it names; reached goals collapse into the count, the rest print one line each, mark first, with their reading"
# ============================================================
# sr_goal_lines -> the raw page's goal lines under the goals indicator, `<mark> <theme>: <measure> — <reading>`, each
# folded line joined back
sr_goal_lines() { printf '%s\n' "$OUT" | awk '/^[^ ]+ goals — / { on = 1; next } on && /^   [^ ]/ { if (l != "") print l; l = substr($0, 4); next }
  on && /^      / { sub(/^ +/, ""); l = l " " $0; next } on { exit } END { if (l != "") print l }'; }
SR_GOALS="fast landings · one-file median under 15m (landing-report --rows)
tests · whole run under 45 min at the approved head (the Step-5 run log)
handoff · a fresh session continues a no-run handoff (record/reader-test-handoff.md)" sr_world goals "6 6 12 12"
printf 'Gating: 9 passed, 0 failed\nWall: 3000s · work 9000s · width 4\n' > "$SR_DIR/regression-run-$SR_H.log"
awk -v h="$SR_H" '{ print } /^current: 4$/ { print "proved: kind=regression head=" h " at=2026-10-06T20:00:00Z evidence=record/wave-02-fx/regression-run-" h ".log" }' "$SR_PLAN" > "$SR_PLAN.t" && mv "$SR_PLAN.t" "$SR_PLAN"
sr_run "$SR_PLAN"
expect_eq "G1 three goals, the one-file median of 9 min reached, the 50-minute whole run missed, the reader test unrecorded: ✖️, 1 of 3" \
  "$SR_MARK_OVER goals — 1 of 3 reached" "$(printf '%s\n' "$OUT" | /usr/bin/grep -E '^[^ ]+ goals — ')"
expect_eq "G2 …the two not reached print one line each, mark and theme first, in the plan's order; the reached one is in the count only" \
  "$SR_MARK_OVER tests|$SR_MARK_NONE handoff" "$(sr_goal_lines | awk -F': ' '{ print $1 }' | sr_join)"
expect_eq "G3 …the missed goal's line carries the reading its reader took, 50 min" \
  "50 min" "$(sr_goal_lines | /usr/bin/grep ' tests: ' | sed 's/.* — //' | /usr/bin/grep -oE '[0-9]+ min')"
printf '# reader test\n\nverdict: pass\n' > "$SR_DIR/reader-test-handoff.md"
sr_run "$SR_PLAN"
expect_eq "G4 a reader-test record that passes flips its goal: 2 of 3 reached, and only the missed goal still prints" \
  "$SR_MARK_OVER goals — 2 of 3 reached|$SR_MARK_OVER tests" \
  "$(printf '%s\n' "$OUT" | /usr/bin/grep -E '^[^ ]+ goals — ')|$(sr_goal_lines | awk -F': ' '{ print $1 }' | sr_join)"

# ============================================================
section "§GOAL-MISS: the first landing that misses a goal makes the tick open decide:goal:<theme> on the person's ledger, once"
# ============================================================
SR_GOALS="fast landings · one-file median under 15m (landing-report --rows)
handoff · a fresh session continues a no-run handoff (record/reader-test-handoff.md)" SR_APPROVED=none sr_tick_world goal-miss "20 20 20 20"
SR_OWED_F="$SR_REPO/.bionic/tmp/owed-$SID.state"
sr_tick
expect_eq "GM1 four 20-minute one-file landings miss the 15-minute goal: the tick opens decide:goal:fast-landings, and nothing for the unmeasured goal" \
  "decide:goal:fast-landings" "$(/usr/bin/grep -oE '\|key=decide:goal:[^|]*\|state=open\|' "$SR_OWED_F" 2>/dev/null | cut -d'|' -f2 | sed 's/^key=//' | sr_join)"
expect_eq "GM2 …it is owed: the tick's sitrep line counts it" "owed: 1" \
  "$(/usr/bin/grep '^poker: sitrep ' "$TMPROOT/tick.out" | /usr/bin/grep -oE 'owed: [0-9]+')"
sed 's/^owed\/v1|key=decide:goal:fast-landings|state=open|.*/owed\/v1|key=decide:goal:fast-landings|state=closed|by=ruled|at=2026-10-06T22:00:30Z/' "$SR_OWED_F" > "$SR_OWED_F.t" && mv "$SR_OWED_F.t" "$SR_OWED_F"
SR_AT=$((SR_NOW + 60)) sr_tick
expect_eq "GM3 once the person has ruled, a later tick on the same miss opens nothing again: the key closed, none open" "1|0" \
  "$(/usr/bin/grep -c '|key=decide:goal:fast-landings|state=closed|' "$SR_OWED_F")|$(/usr/bin/grep -c '|key=decide:goal:fast-landings|state=open|' "$SR_OWED_F")"

# ============================================================
section "§ONE-FILE: the schedule's bar half and the one-file goal read the one-file landings only; a landing of more files moves neither"
# ============================================================
SR_GOALS="fast landings · one-file median under 5m (landing-report --rows)" sr_world one-file "90 90 10 10"
awk -F'|' 'BEGIN { OFS = "|" } $2 ~ /^ T[12] $/ { $11 = " lib/t1.sh, lib/x.sh " } { print }' "$SR_PLAN" > "$SR_PLAN.t" && mv "$SR_PLAN.t" "$SR_PLAN"
sr_run "$SR_PLAN"
expect_eq "OF1 two 90-minute landings of two files and two 10-minute one-file landings: the schedule mark reads 10 min, ✅ within the bar" \
  "$SR_MARK_WITHIN|10 min" "$(sr_ind schedule | awk '{ print $1 }')|$(sr_ind schedule | /usr/bin/grep -oE 'takes [0-9]+ min' | sed 's/^takes //')"
expect_eq "OF2 …and the one-file goal reads 10 min against its 5-minute target" \
  "10 min" "$(sr_goal_lines | /usr/bin/grep ' fast landings: ' | sed 's/.* — //' | /usr/bin/grep -oE '[0-9]+ min')"


finish
