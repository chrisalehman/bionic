#!/bin/bash
# Tests for `hooks/session-poker.sh sitrep` — the situation report's renderer.
#
# THE VERB PRINTS THE WHOLE PAGE BUT ONE JUDGMENT. The title (project, release, weekday and time, the
# step of nine, the tasks done), the Bottom line's four answers (what you owe, what is next, what is
# done, when it closes), the Task list (a glyph, `step/task: description`, a time in parentheses or a
# state after " — "), the Score's five indicator lines and Blocked on you, every section bulleted
# and every line folded at 92 columns; `--basis` prints the close's arithmetic. The one judgment is the grade and its
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
# chain does not. SR_SCALE, when set, declares `scale:`.
# THE DISPATCH LEDGER: each landed row of SR_DISPATCH_ROWS (all four when unset) has a `dispatched` instant,
# at its ready instant, or SR_DISPATCH_LEAD minutes before its landing when set, minute-precise as the
# roster writes it. At the ready instant the pace is the queue's own 1.2×, so the close moves only where a
# world sets a lead apart from the queue time.
sr_world() {
  local label="$1" mins="$2" r d p led=""
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
      case " ${SR_DISPATCH_ROWS-1 2 3 4} " in
        *" $i "*) led="$led$(sr_disp "T$i" $(( e - ${SR_DISPATCH_LEAD:-${!i}} * 60 )))"$'\n' ;;
      esac
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
    printf '\n## Dispatch ledger\n\n| id | agent | dispatched | expected | artifact | landed | notes |\n|---|---|---|---|---|---|---|\n%s' "$led"
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
sr_disp() {  # <id> <epoch> -> its dispatch ledger row, dispatched at that minute
  printf '| %s | implementor (w-%s) | %s | 30 min | — | — | — |' "$1" "$1" "$(date -u -r "$2" +%Y-%m-%dT%H:%MZ 2>/dev/null || date -u -d "@$2" +%Y-%m-%dT%H:%MZ)"
}
sr_row() {  # <id> <task> <reads> <size> <status>
  local n="${1#T}"
  printf '| %s | 4 | build | %s | — | — | %s | %s | REQ-1 | lib/t%s.sh | — | — | %s | — | — | — |\n' "$1" "$2" "$3" "$4" "$n" "$5"
}
sr_owed() {  # <owed/v1 fields after the schema> [<session>] -> one line in that session's owed store (this world's own by default)
  printf 'owed/v1|%s\n' "$1" >> "$SR_REPO/.bionic/tmp/owed-${2:-$SID}.state"
}
# sr_prev <minutes> [<scale>] -> a delivered plan beside this one (T1 of 60 min declared,
# declaring `scale: <scale>` when given) whose T1 is dispatched at 10:00Z the day before and lands <minutes>
# later: the previous wave's measured ratio is <minutes> / 60. Its queue time is 1 minute, so a pace read
# from the queue would be 1/60.
sr_prev() {
  local p="$SR_REPO/.bionic/docs/plans/epic-01-fx/wave-40-prev.plan.md" d="$SR_REPO/.bionic/docs/record/wave-40-prev"
  local land=$((SR_E0 - 86400 + $1 * 60))
  mkdir -p "$d"
  {
    printf -- '---\nwave: wave-40-prev\nrelease: 9.8.0\n%s---\n# prev\n\n## SDLC State\n\ncurrent: 9\n\n' "${2:+scale: $2$'\n'}"
    printf -- '- Step 9: delivered: 2026-10-05T20:00Z wave-40-prev 9.8.0 — closed by close-out.sh\n'
    printf '\n## Tasks\n\n| id | step | kind | task | agent | deps | reads | size | serves | Files | worktree | base | status | suites | lands-on | artifact |\n'
    printf '|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|\n'
    printf '| T1 | 4 | build | Prev row · complexity: standard | — | — | — | 60 | REQ-1 | lib/p1.sh | — | — | landed | — | — | — |\n'
    printf '\n## Dispatch ledger\n\n| id | agent | dispatched | expected | artifact | landed | notes |\n|---|---|---|---|---|---|---|\n%s\n' \
      "$(sr_disp T1 $((SR_E0 - 86400)))"
  } > "$p"
  {
    printf 'line/v1|ev=ready|row=T1|name=p-T1|commit=%s|branch=wt/01-T1|tree=%s/.worktrees/01-T1|suites=a.test.sh|debt=-|carrier=1:x|at=%s\n' "$SR_C1" "$SR_REPO" "$(sr_iso $((land - 60)))"
    printf 'line/v1|ev=published|row=T1|commit=%s|kind=queue|by=-|why=-|at=%s\n' "$SR_C1" "$(sr_iso "$land")"
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
sr_tasks() { sr_page | head -1 | /usr/bin/grep -oE '[0-9]+ of [0-9]+ tasks done'; }   # -> the title's count of tasks done
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
section "§ROWS: every task of ## Tasks, glyph in column 1, [step]/[task]: description, a done task with its local 12-hour time, a state after \" — \"; the title's counts and the Bottom line's four answers"
# ============================================================
sr_world rows "6 6 12 12"
sr_run "$SR_PLAN"
expect_eq "R0 sitrep <plan> exits 0 with nothing on stderr" "0|" "$RC|$ERR"
expect_eq "R2 the title carries the step of nine and the tasks done, and the page has no Completion section" "step 4 of 9 · 4 of 17 tasks done|0" \
  "$(sr_page | head -1 | /usr/bin/grep -oE 'step [0-9]+ of 9 · [0-9]+ of [0-9]+ tasks done')|$(sr_page | /usr/bin/grep -c '^Completion$')"
SR_ROWS="$(sr_rows)"
expect_eq "R2b the title's task count carries its percent, rounded" "4 of 17 tasks done (24%)" \
  "$(sr_page | head -1 | /usr/bin/grep -oE '[0-9]+ of [0-9]+ tasks done \([0-9]+%\)')"
expect_eq "R3 seventeen task lines under Task list" "17" "$(printf '%s\n' "$SR_ROWS" | /usr/bin/grep -c .)"
expect_eq "R4 every task line opens with one of the four glyphs in column 1, then [step]/[task]:" "17" \
  "$(printf '%s\n' "$SR_ROWS" | /usr/bin/grep -cE '^(✅|🔄|⬜|⛔) 4/T[0-9]+: ')"
expect_eq "R6 no UTC instant anywhere on the page (no ISO Z time, no UTC word)" "" \
  "$(printf '%s\n' "$OUT" | /usr/bin/grep -E '[0-9]{2}:[0-9]{2}(:[0-9]{2})?Z|UTC')"
expect_eq "R7 the section headings in order, each after a blank line" \
  "Bottom line|Task list|Score: not graded yet|Blocked on you" "$(printf '%s\n' "$OUT" | sr_heads)"
expect_eq "R8 …and no line of rule characters" "" "$(printf '%s\n' "$OUT" | /usr/bin/grep -E '^[-=─━_]{3,}$')"
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
expect_eq "SH0 precondition: the 38-task plan renders (rc 0), every task done, read by the title" \
  "0|38 of 38 tasks done" "$RC|$(sr_tasks)"
expect_eq "SH0b precondition: the fixture holds the three shapes — bare, text before landed, landed-by-hand (lead and after text)" "yes|yes|yes|yes" \
  "$(sr_w38_lines | /usr/bin/grep -qE '^- T1: landed [0-9a-f]{40} ' && echo yes)|$(sr_w38_lines | /usr/bin/grep -qE '^- T2: reason: .* landed [0-9a-f]{40} ' && echo yes)|$(sr_w38_lines | /usr/bin/grep -qE '^- T12: landed-by-hand: ' && echo yes)|$(sr_w38_lines | /usr/bin/grep -qE '^- T3: reason: .* landed-by-hand: ' && echo yes)"
expect_eq "SH1 38 of 38 done tasks print a time" "38" \
  "$(sr_rows | /usr/bin/grep -cE '^✅ [0-9]+/T[0-9]+: .* \([0-9]{1,2}:[0-9]{2} [AP]M( [0-9]{4}-[0-9]{2}-[0-9]{2})?(, by hand)?\)$')"
expect_eq "SH2 the bare shape, landed <sha> <ISO>: T1 at its local time" \
  "✅ 4/T1: Row 1 of wave 38 (2:08 AM 2026-10-16)" "$(sr_rows | /usr/bin/grep '/T1: ')"
expect_eq "SH3 text before landed <sha> <ISO>: T2 at its landing's time, not the reason's" \
  "✅ 4/T2: Row 2 of wave 38 (12:06 PM 2026-10-16)" "$(sr_rows | /usr/bin/grep '/T2: ')"
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
  "0|4 of 17 tasks done" "$RC|$(sr_tasks)"
expect_eq "ORD1 the Task list opens on steps 0 to 3, each with its approval time (the approved by instant, not an earlier approved)" \
  "✅ 0: Configure (1:10 AM)|✅ 1: Scope (1:40 AM)|✅ 2: Design (2:20 AM)|✅ 3: Plan (3:00 AM)" \
  "$(sr_sit | head -4 | sr_join)"
expect_eq "ORD5 …and nothing else: the four attended steps and 17 tasks, one logical line each" "21|4|17" \
  "$(sr_sit | /usr/bin/grep -c .)|$(sr_steps | /usr/bin/grep -c .)|$(sr_rows | /usr/bin/grep -c .)"
# A step with no approval instant on its line says so.
awk '/^- Step 2: / { print "- Step 2: spec: specs/x.spec.md; frame approved at the card"; next } { print }' "$SR_PLAN" > "$SR_PLAN.t" && mv "$SR_PLAN.t" "$SR_PLAN"
sr_run "$SR_PLAN"

# ============================================================
section "§MARKS: the Score's five indicator lines, each opening on its mark (✅ within · ➖ near · ✖️ over · ❔ not measurable) then its name and what it measured, in words; no legend line; a planted defect moves its mark"
# ============================================================
sr_world marks "6 6 12 12"
sr_run "$SR_PLAN"
expect_eq "M2a the five indicators in order, and no legend line anywhere on the page" "schedule|correctness|waste|decisions|goals|0" \
  "$(sr_sect 'Score: .*' | awk '$2 ~ /^(schedule|correctness|waste|decisions|goals)$/ { print $2 }' | sr_join)|$(printf '%s\n' "$OUT" | /usr/bin/grep -c '^within / near / over')"
expect_eq "M2b …no indicator line carries a parenthesised bar" "0" \
  "$(sr_sect 'Score: .*' | /usr/bin/grep -E '^[^ ]+ (schedule|correctness|waste|decisions|goals) ' | /usr/bin/grep -c '(')"
expect_eq "M2c …each indicator line opens on one of the four marks, then its name" "5" \
  "$(sr_sect 'Score: .*' | /usr/bin/grep -cE "^($SR_MARK_WITHIN|$SR_MARK_NEAR|$SR_MARK_OVER|$SR_MARK_NONE) (schedule|correctness|waste|decisions|goals) ")"
# A planted red run, not answered: correctness over its bar, and the task it is on reads ⛔.
sr_ev "ev=verdict|row=T8|commit=$SR_C1|suite=a.test.sh|result=red|log=/rec/T8.log|at=2026-10-06T14:00:00Z"
sr_run "$SR_PLAN"
# The red answered: a later green on the same task and suite.
sr_ev "ev=verdict|row=T8|commit=$SR_C1|suite=a.test.sh|result=green|log=/rec/T8b.log|at=2026-10-06T15:00:00Z"
sr_run "$SR_PLAN"
# An open S2 finding of a registered reading: correctness ✖️.
printf 'reviewed: %s..%s\nfindings: 1\nfinding: 1 S2 on lib/t1.sh:3 the thing breaks\nshown: 1 bash tests/x.test.sh\n' "$SR_C1" "$SR_H" > "$SR_DIR/critic.md"
awk -v h="$SR_H" '{ print } /^current: 4$/ { print "proved: kind=review head=" h " at=2026-10-06T20:00:00Z evidence=record/wave-02-fx/critic.md question=adversarial reader=crit result=fail scope=piece" }' "$SR_PLAN" > "$SR_PLAN.t" && mv "$SR_PLAN.t" "$SR_PLAN"
sr_run "$SR_PLAN"
expect_eq "M3a the correctness line names the class of the one open finding, never the bucket" "1 open S2 finding|0" \
  "$(sr_ind correctness | /usr/bin/grep -oE '[0-9]+ open S[12] finding')|$(sr_ind correctness | /usr/bin/grep -c 'S1 or S2')"
printf 'reviewed: %s..%s\nfindings: 2\nfinding: 1 S2 on lib/t1.sh:3 the thing breaks\nfinding: 2 S1 on lib/t2.sh:4 and so does this\nshown: 1 bash tests/x.test.sh\nshown: 2 bash tests/y.test.sh\n' "$SR_C1" "$SR_H" > "$SR_DIR/critic.md"
sr_run "$SR_PLAN"
expect_eq "M3b …and of two, each class counted" "2 open findings, one S1 and one S2" \
  "$(sr_ind correctness | /usr/bin/grep -oE '[0-9]+ open findings, [^;.]*')"
# The clock 1.25× behind: a 40-hour forecast needs 17 × 12/40 = 5.1, so 5, and 4 done: schedule ➖.
SR_FORECAST=40h sr_world marks-slow "6 6 12 12"
sr_run "$SR_PLAN"
# …further behind: a 24-hour forecast needs 17 × 12/24 = 8.5, so 9.
SR_FORECAST=24h sr_world marks-late "6 6 12 12"
sr_run "$SR_PLAN"
# 20% of runs discarded: waste ✖️.
sr_world marks-waste "6 6 12 12"
sr_ev "ev=verdict|row=T8|commit=$SR_C1|suite=a.test.sh|result=discarded|log=/rec/T8.log|at=2026-10-06T14:00:00Z"
sr_run "$SR_PLAN"
# A run killed at the gate (rc 137) is a wasted run: the landing report's killed count reads as discarded.
sr_world marks-killed "6 6 12 12"
printf 'key=a.test.sh\nkind=landing\nwho=%s:w-T9\ntree=%s/.worktrees/02-T9\nasked=%d\nholder=-\nadmitted=%d\nended=%d\nrc=137\npromise=5:0.1:30\n' \
  "$SID" "$(cd "$SR_REPO" && pwd -P)" "$((SR_NOW - 600))" "$((SR_NOW - 590))" "$((SR_NOW - 300))" > "$SR_GATE/requests/3"
sr_run "$SR_PLAN"
expect_eq "M4 a killed run counts as discarded on the waste line" "yes" \
  "$(sr_ind waste | /usr/bin/grep -qE 'waste — ([0-9]+%|under 1%) of suite runs discarded' && echo yes)"
# Idle width: an idle turn from 16:00Z to 17:12Z is 72 of 720 elapsed minutes, 10%: ➖.
sr_world marks-idle "6 6 12 12"
printf 'fill-ledger/v1|at=2026-10-06T16:00:00Z|session=%s|turn=t2|current=4|state=ok|ceiling=|width=4|open=3|free=1|ready=T9|launched=|declined=|missed=1|idle=T9|room=1\n' "$SID" >> "$SR_DIR/fill-ledger.log"
printf 'fill-ledger/v1|at=2026-10-06T17:12:00Z|session=%s|turn=t3|current=4|state=ok|ceiling=|width=4|open=4|free=0|ready=|launched=T9|declined=|missed=0|idle=|room=0\n' "$SID" >> "$SR_DIR/fill-ledger.log"
sr_run "$SR_PLAN"
# Nothing done on this run, 12 hours in: the clock still reads, and is behind; the bar still prints.
sr_world marks-none none
sr_run "$SR_PLAN"
# …and with no forecast declared, neither half can be graded: ❔, each half saying why.
SR_FORECAST= sr_world marks-bare none
sr_run "$SR_PLAN"

# ============================================================
section "§RATIO: the waste line carries the two shell-line counts the release check printed, in words, on the same line; a planted count moves it"
# ============================================================
# sr_check <log line> -> a passing release-check proof at SR_H whose log holds that line, written in the shapes the
# release-check verb writes (the log's head=/rc= lines, the command's output after a blank line), and the plan's
# section carrying the proof once. The log is rewritten on every call, so a planted count is the same proof read again.
SR_CHK_REL="record/wave-02-fx/release-check-$SR_H.log"
sr_check() {
  printf 'head=%s rc=0\nbase=%s (tag)\ncommand: bash tests/lib/release-check.sh /x\n\n%s\n' "$SR_H" "$SR_C1" "$1" > "$SR_REPO/.bionic/docs/$SR_CHK_REL"
  /usr/bin/grep -q 'kind=check' "$SR_PLAN" && return 0
  awk -v h="$SR_H" -v e="$SR_CHK_REL" '{ print } /^current: 4$/ { print "proved: kind=check head=" h " at=2026-10-06T20:00:00Z evidence=" e }' "$SR_PLAN" > "$SR_PLAN.t" \
    && mv "$SR_PLAN.t" "$SR_PLAN"
}
sr_world ratio "6 6 12 12"
sr_run "$SR_PLAN"
SR_Z_LINES="$(sr_sect 'Score: .*' | /usr/bin/grep -c .)"
expect_regex "RT0 precondition: with no check proof the waste line reads its two measures and no count of lines" \
  "^[^ ]+ waste — [^;]*; [^;]*\$" "$(sr_ind waste)"
expect_eq "RT0b …and the Score holds its five indicator lines" "5" \
  "$(sr_sect 'Score: .*' | /usr/bin/grep -cE '^[^ ]+ (schedule|correctness|waste|decisions|goals) ')"
sr_check "test-ratio: 85334/95969"
sr_run "$SR_PLAN"
expect_eq "RT1 a passing check whose log prints test-ratio: 85334/95969: the waste line ends on both counts, in words" \
  "yes" "$(sr_ind waste | /usr/bin/grep -qE 'waste — [^;]*; [^;]*; tests 85,334 lines against code 95,969$' && echo yes)"
expect_eq "RT1b …on the same line: the Score holds as many lines as without the clause" "$SR_Z_LINES" "$(sr_sect 'Score: .*' | /usr/bin/grep -c .)"
sr_check "test-ratio: 950/12345678"
sr_run "$SR_PLAN"
expect_eq "RT2 a planted count moves the line: 950 against 12,345,678, grouped by thousands" \
  "yes" "$(sr_ind waste | /usr/bin/grep -qE '; tests 950 lines against code 12,345,678$' && echo yes)"
sr_check "release-check: test-ratio 96000/95000 — tests exceed code at HEAD"
sr_run "$SR_PLAN"
expect_eq "RT3 a refused ratio in the log reads the same: both counts on the line" \
  "yes" "$(sr_ind waste | /usr/bin/grep -qE '; tests 96,000 lines against code 95,000$' && echo yes)"
sr_check "known-limits: nothing to say about the ratio"
sr_run "$SR_PLAN"
expect_regex "RT4 a log with no ratio line says no count, beside the three that did" "^[^ ]+ waste — [^;]*; [^;]*\$" "$(sr_ind waste)"

# ============================================================
section "§CLOCK: the schedule mark grades the likely close against the forecast end, the Step-3 approval plus the plan's forecast:; the pace behind the likely close is the run's own, whose sizes it reads; the median landing against the 15-minute bar beside it"
# ============================================================
# 39 tasks, 4 done, 11 hours after approval, against a 24-hour forecast. The four landings take 120 120 134 134
# minutes against sizes of 5 5 10 10: a pace of 18.7×, a likely close far past the forecast end.
SR_FORECAST=24h SR_EXTRA=22 sr_world clock "120 120 134 134"
SR_AT=$((SR_NOW - 3600)) sr_run "$SR_PLAN"
expect_eq "CK0 precondition: 39 tasks, 4 done, read by the title" "4 of 39 tasks done" "$(sr_tasks)"
SR_CK1="$(sr_ind schedule)"
SR_AT=$((SR_NOW - 3600)) sr_run --basis "$SR_PLAN"; SR_CK1_PACE="$(sr_line '- The pace: ')"
expect_eq "CK1 behind: the likely close is past the 24 h forecast's end, the mark is ✖️ and the line names the forecast and the pace" \
  "$SR_MARK_OVER|yes|yes" \
  "${SR_CK1%% *}|$(printf '%s\n' "$SR_CK1" | /usr/bin/grep -qE 'over the 24 h forecast; this run.s 18\.7×' && echo yes)|$(printf '%s\n' "$SR_CK1" | /usr/bin/grep -qE 'likely .* against 3:00 AM 2026-10-07, [0-9]+ min over' && echo yes)"
# The declared sizes change: the pace is the likely close's, and the sizes are what it reads, so the line moves with
# it. The close's pace is the proof the rewrite reached the renderer: 127 min over 500 planned, 0.25×.
awk -F'|' 'BEGIN { OFS = "|" } $2 ~ /^ T[1-4] $/ { $9 = " 500 " } { print }' "$SR_PLAN" > "$SR_PLAN.t" && mv "$SR_PLAN.t" "$SR_PLAN"
SR_AT=$((SR_NOW - 3600)) sr_run --basis "$SR_PLAN"
expect_eq "CK2a precondition: the sizes rewrite reached the renderer (the pace moved to 0.25×)" \
  "yes|yes" "$(sr_line '- The pace: ' | /usr/bin/grep -q '^- The pace: 0\.25×, ' && echo yes)|$([ "$(sr_line '- The pace: ')" != "$SR_CK1_PACE" ] && echo yes)"
SR_AT=$((SR_NOW - 3600)) sr_run "$SR_PLAN"
expect_eq "CK2 …and the schedule line names that pace: the sizes reach the mark only through the likely close" \
  "yes|yes" "$(sr_ind schedule | /usr/bin/grep -q "; this run.s 0\.25×" && echo yes)|$([ "$(sr_ind schedule)" != "$SR_CK1" ] && echo yes)"
# Ahead: a 240-hour forecast, the same four landings at 1.2×.
SR_FORECAST=240h SR_EXTRA=22 sr_world clock-ahead "6 6 12 12"
SR_AT=$((SR_NOW - 3600)) sr_run "$SR_PLAN"
expect_eq "CK3 ahead: the likely close is inside the 240 h forecast, ✅, and the line names that forecast" \
  "$SR_MARK_WITHIN|yes" "$(sr_ind schedule | awk '{ print $1 }')|$(sr_ind schedule | /usr/bin/grep -q 'min inside the 240 h forecast; this run.s 1\.2×; ' && echo yes)"
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
sr_run --line "$SR_PLAN"
expect_eq "BP2 …and the one-line form opens on it (the line: $OUT)" "yes" "$([ "${OUT#"$SR_MARK_OVER$SR_MARK_WITHIN$SR_MARK_WITHIN · "}" != "$OUT" ] && echo yes)"
sr_world bar-near "17 17 17 17"
sr_run "$SR_PLAN"
# One constant: a mutant tree whose lib/line.sh sets the bar to 25 moves both surfaces that read it.
SR_MUT="$TMPROOT/mut"; mkdir -p "$SR_MUT/payload"
cp -R "$BIONIC_HOOKS_DIR" "$SR_MUT/hooks" && cp -R "$BIONIC_HOOKS_DIR/../payload/scripts" "$SR_MUT/payload/scripts"
sed 's/^LINE_LANDING_BAR=15$/LINE_LANDING_BAR=25/' "$BIONIC_HOOKS_DIR/../payload/scripts/lib/line.sh" > "$SR_MUT/payload/scripts/lib/line.sh"
sr_world bar-plant-mut "20 20 20 20"
SR_KEEP_POKER="$POKER"; POKER="$SR_MUT/hooks/session-poker.sh"
sr_run "$SR_PLAN"
SR_MUT_SC="$(sr_poke_with "$POKER" landing-report --scorecard "$SR_PLAN")"
POKER="$SR_KEEP_POKER"
expect_eq "BP6 …and the scorecard's target reads it too" \
  "widest landing ready→landed: T1 20.0 min · target < 25" "$(printf '%s\n' "$SR_MUT_SC" | /usr/bin/grep '^widest landing ')"

# ============================================================
section "§SHAPE: the page is the prototype's — title with the step and the task count, Bottom line, Task list, Score, Blocked on you; no glyph before the Bottom line; every section bulleted; every line at most 92 columns; a task in flight carries its state in words"
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
  "Bottom line|Task list|Score: not graded yet|Blocked on you" "$(printf '%s\n' "$OUT" | sr_heads)"
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
expect_eq "H6 every section is bulleted: no physical line breaks its section's form" "" "$(sr_breaks)"
expect_eq "H6b …read through the same sections: four Bottom line bullets, one under Blocked on you" "4|1" \
  "$(sr_sect 'Bottom line' | /usr/bin/grep -c '^- ')|$(sr_sect 'Blocked on you' | /usr/bin/grep -c '^- ')"
expect_eq "H7 every task in flight carries its state in words after a dash" "4|4" \
  "$(sr_rows | /usr/bin/grep -c '^🔄 ')|$(sr_rows | /usr/bin/grep -cE '^🔄 [^ ]+: .* — [a-z]')"

# ============================================================
section "§GRADE: the skill writes only a grade and a rationale that names an indicator line; a rationale that names none is refused"
# ============================================================
sr_world slots "6 6 12 12"
sr_run grade C 'the decisions line is the red one: three rounds too many' "$SR_PLAN"; GR_RC1="$RC"
sr_run grade B 'the run is going fine' "$SR_PLAN"; GR_RC2="$RC"
sr_run "$SR_PLAN"
expect_eq "SL1 a grade citing an indicator line exits 0, one citing none exits 1, and the page still shows the first grade's letter" "0|1|C" \
  "$GR_RC1|$GR_RC2|$(printf '%s\n' "$OUT" | sr_heads | cut -d'|' -f3 | sed 's/^Score: \(.\) .*/\1/')"

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
expect_eq "SC6 …no closing time anywhere on its page, its close the delivery (the forecast page below prints one: FC1b)" "0|1" \
  "$(printf '%s\n' "$OUT" | /usr/bin/grep -cE 'not before|likely|About ')|$(sr_line '- Close: ' | /usr/bin/grep -c '^- Close: delivered at ')"
sr_run --line "$SR_PLAN"
expect_eq "SC7 …and the one-line form says delivered, no time" "yes" "$(printf '%s\n' "$OUT" | /usr/bin/grep -qE ' · delivered$' && echo yes)"
for SR_W in A D; do
  eval "SR_PG=\"\$SR_PAGE_$SR_W\""
  expect_eq "SC8$SR_W the plan's table words never print on page $SR_W: no 'rows', no status name, no cell value — beside its task lines" "0|0|0|yes" \
    "$(printf '%s\n' "$SR_PG" | /usr/bin/grep -ciw 'rows')|$(printf '%s\n' "$SR_PG" | /usr/bin/grep -ciwE 'landed|pending|active|dropped|held')|$(printf '%s\n' "$SR_PG" | /usr/bin/grep -cE 'approval:|step:[0-9]|lib/[a-z]')|$([ "$(printf '%s\n' "$SR_PG" | /usr/bin/grep -cE '^(✅|🔄|⬜|⛔) [0-9]+/T')" -ge 17 ] && echo yes)"
done

# ============================================================
section "§FORECAST: the close is the open work, the larger of the longest chain and the work over the count the gate admits, from now: a floor at the plan's own minutes and a likely close at the measured pace; no typed number moves it, and admitting more never shortens one chain"
# ============================================================
# The work left is 480 min over 2 admitted, 240 min, above the 150-min chain: the floor is 3:00 PM + 4 h, the
# likely close the same 240 min at this run's 1.2× (its four rows land 1.2× their planned minutes after dispatch).
sr_world forecast "6 6 12 12"
sr_run "$SR_PLAN"
expect_eq "FC1b the Bottom line's close is the floor and the likely close, naming whose pace" \
  "- Close: not before 7:00 PM · likely 7:48 PM (this run's 1.2×)." "$(sr_line '- Close: ')"
SR_FC1_CLOSE="$(sr_line '- Close: ')"
awk '{ sub(/^forecast: 48h$/, "forecast: 24h") } { print }' "$SR_PLAN" > "$SR_PLAN.t" && mv "$SR_PLAN.t" "$SR_PLAN"
sr_run "$SR_PLAN"
expect_eq "FC2 a typed number moves nothing: the plan's forecast: halved, the close is the same (the schedule line did read it: it names the 24 h forecast)" \
  "$SR_FC1_CLOSE|yes" "$(sr_line '- Close: ')|$(sr_ind schedule | /usr/bin/grep -q 'inside the 24 h forecast' && echo yes)"
# The close on the local clock: a time on now's day bare, past midnight with its date.
sr_world forecast-late "6 6 12 12"
SR_AT=$((SR_NOW - 6 * 3600)) sr_run "$SR_PLAN"
expect_eq "FC8 at 9:00 AM, 4 h and 4 h 48 min on are the same local day: no date" \
  "- Close: not before 1:00 PM · likely 1:48 PM (this run's 1.2×)." "$(sr_line '- Close: ')"
SR_AT=$((SR_NOW + 12 * 3600)) sr_run "$SR_PLAN"
expect_eq "FC9 …at 3:00 AM the next morning, now's own day: no date" \
  "- Close: not before 7:00 AM · likely 7:48 AM (this run's 1.2×)." "$(sr_line '- Close: ')"
SR_AT=$((SR_NOW + 8 * 3600 + 1800)) sr_run "$SR_PLAN"
expect_eq "FC10 …at 11:30 PM, both are past midnight: the date follows each" \
  "- Close: not before 3:30 AM 2026-10-07 · likely 4:18 AM 2026-10-07 (this run's 1.2×)." "$(sr_line '- Close: ')"
# One chain: every open task reads what the one before it writes, so no width can shorten it.
sr_world one-chain "6 6 12 12"
awk -F'|' 'BEGIN { OFS = "|" }
  $2 ~ /^ T([5-9]|1[0-7]) $/ { n = $2; gsub(/[ T]/, "", n); if (n + 0 > 5) $8 = " lib/t" (n - 1) ".sh " }
  { print }' "$SR_PLAN" > "$SR_PLAN.t" && mv "$SR_PLAN.t" "$SR_PLAN"
sr_run "$SR_PLAN"; SR_OC2="$(sr_line '- Close: ')"
sr_run --basis "$SR_PLAN"
SR_OC2W="$(sr_line '- The work left ' | /usr/bin/grep -oE 'over the [0-9]+ suite runs')"
SR_OC2MAX="$(printf '%s\n' "$OUT" | sr_maxw)"
for i in 3 4; do
  printf 'key=a.test.sh\nkind=landing\nwho=%s:w-T%d\ntree=/elsewhere/project\nasked=%d\nholder=%s:\nadmitted=%d\npromise=5:0.1:30\n' \
    "$SID" "$((i + 4))" "$((SR_NOW - 600))" "$$" "$((SR_NOW - 590))" > "$SR_GATE/requests/$i"
done
sr_run --basis "$SR_PLAN"
expect_eq "FC11 precondition: the chain is every open task, and the gate's count reached the basis, 2 then 4" \
  "yes|over the 2 suite runs|over the 4 suite runs" \
  "$(sr_line '- The work left ' | /usr/bin/grep -q 'T5 → T6 → T7 → T8 → T9 → T10 → T11 → T12 → T13 → T14 → T15 → T16 → T17, is 480 min' && echo yes)|$SR_OC2W|$(sr_line '- The work left ' | /usr/bin/grep -oE 'over the [0-9]+ suite runs')"
sr_run "$SR_PLAN"
expect_eq "FC12 admitted 2 then 4 on one chain: the close does not move, 480 min at 1× and at 1.2× either way" \
  "- Close: not before 11:00 PM · likely 12:36 AM 2026-10-07 (this run's 1.2×).|$SR_OC2" "$(sr_line '- Close: ')|$SR_OC2"
expect_eq "FC13 …and the long chain folds within 92 columns on the basis (widest $SR_OC2MAX)" "yes" "$([ "${SR_OC2MAX:-999}" -le 92 ] && echo yes)"

# ============================================================
section "§PACE: the pace is the median, over this run's queue landings with a dispatched instant and a declared size, of landed less dispatched over the planned minutes; the queue's ready-to-landed time feeds nothing; a pace that is not positive is unmeasured"
# ============================================================
# Three rows sized 60 min, dispatched 90 min before each landing and ready 5 min before it: the pace is 1.5×,
# never the queue's 5/60. T4 lands too, with no ledger row, and joins nothing.
SR_DISPATCH_LEAD=90 SR_DISPATCH_ROWS="1 2 3" sr_world pace "5 5 5 5"
awk -F'|' 'BEGIN { OFS = "|" } $2 ~ /^ T[1-3] $/ { $9 = " 60 " } { print }' "$SR_PLAN" > "$SR_PLAN.t" && mv "$SR_PLAN.t" "$SR_PLAN"
sr_run --basis "$SR_PLAN"
expect_eq "PA1 --basis names this run's pace, 1.5×, over the three landings with a dispatched instant" \
  "- The pace: 1.5×, the median over 3 landings of the minutes from dispatch to landing over the minutes planned." \
  "$(sr_line '- The pace: ')"
sr_run "$SR_PLAN"
expect_regex "PA1b …and the page's close names it" " \(this run's 1\.5×\)\.$" "$(sr_line '- Close: ')"
# Landings 0 min after ready and no dispatched instant: nothing measures a pace, so the floor alone prints.
SR_DISPATCH_ROWS="" sr_world pace-zero "0 0 0 0"
sr_run "$SR_PLAN"
expect_eq "PA2 no dispatched instant: the floor with no pace, and no likely close or About" \
  "- Close: not before 7:00 PM (no pace yet).|0" "$(sr_line '- Close: ')|$(sr_line '- Close: ' | /usr/bin/grep -cE 'likely|About ')"
# Dispatched at the very minute each lands: every ratio is 0, a pace that is not positive, unmeasured.
SR_DISPATCH_LEAD=0 sr_world pace-nil "0 0 0 0"
sr_run "$SR_PLAN"
expect_eq "PA3 a zero pace is unmeasured: the floor with no pace, and now's clock nowhere in the close" \
  "- Close: not before 7:00 PM (no pace yet)." "$(sr_line '- Close: ')"

# ============================================================
section "§FLOOR: before this run measures a pace, the newest delivered run on the same project at the same scale lends its pace, named; with none the floor stands alone; a likely close at or before now never prints; the page states the close once and --basis prints its arithmetic"
# ============================================================
# No landing: the work left is 510 min over 2 admitted, 255 min, so the floor is 7:15 PM; at the delivered run's 72/60 the
# likely close is 306 min on, 8:06 PM.
SR_SCALE=wave sr_world floor none
sr_prev 72 wave
sr_run "$SR_PLAN"
expect_eq "FL1 a delivered run at the same scale lends its pace, named" \
  "- Close: not before 7:15 PM · likely 8:06 PM (wave-40's 1.2×).|0" "$(sr_line '- Close: ')|$(printf '%s\n' "$OUT" | /usr/bin/grep -cE 'No forecast|About ')"
sr_run --line "$SR_PLAN"
expect_eq "FL1b …and the one-line form carries both" "closes ≥7:15 PM ~8:06 PM" "${OUT##* · }"
SR_SCALE=wave sr_world floor-epic none
sr_prev 72 epic
sr_run "$SR_PLAN"
expect_eq "FL1c a delivered run at another scale lends nothing: the floor, no pace yet" \
  "- Close: not before 7:15 PM (no pace yet)." "$(sr_line '- Close: ')"
sr_run --line "$SR_PLAN"
expect_eq "FL1d …and the one-line form carries the floor alone" "closes ≥7:15 PM" "${OUT##* · }"
SR_SCALE=wave sr_world floor-bare none
sr_run "$SR_PLAN"
expect_eq "FL1e no delivered run at all: the floor, no pace yet" "- Close: not before 7:15 PM (no pace yet)." "$(sr_line '- Close: ')"
# This run's pace 0.001× (three rows sized 1000 min, each landed 1 min after dispatch) over a 10-minute chain, one
# task open: the likely close is now's own minute, so the floor prints with the pace named.
SR_DISPATCH_LEAD=1 SR_DISPATCH_ROWS="1 2 3" sr_world floor-fast "5 5 5 5"
awk -F'|' 'BEGIN { OFS = "|" }
  $2 ~ /^ T[1-3] $/ { $9 = " 1000 " }
  $2 ~ /^ T([5-9]|1[0-7]) $/ { $14 = ($2 == " T9 ") ? " pending " : " dropped "; if ($2 == " T9 ") $9 = " 10 " }
  { print }' "$SR_PLAN" > "$SR_PLAN.t" && mv "$SR_PLAN.t" "$SR_PLAN"
sr_run "$SR_PLAN"
expect_eq "FL2 a likely close at or before now prints the floor, never now's clock" \
  "- Close: not before 3:10 PM (this run's 0.001×).|0" "$(sr_line '- Close: ')|$(sr_line '- Close: ' | /usr/bin/grep -c '3:00 PM')"
# The same pace over a 6000-minute task: the likely close is 6 minutes on, after now, so it prints though the
# floor is days off; it is the estimate, the floor the plan's own minutes.
awk -F'|' 'BEGIN { OFS = "|" } $2 == " T9 " { $9 = " 6000 " } { print }' "$SR_PLAN" > "$SR_PLAN.t" && mv "$SR_PLAN.t" "$SR_PLAN"
sr_run "$SR_PLAN"
expect_eq "FL2b a likely close before the floor is the one instant, the floor omitted" \
  "- Close: likely 3:06 PM (this run's 0.001×).|0" "$(sr_line '- Close: ')|$(sr_line '- Close: ' | /usr/bin/grep -c 'not before')"
# The page states the close once; the arithmetic is --basis's.
sr_world floor-basis "6 6 12 12"
sr_run "$SR_PLAN"
expect_eq "FL3 the page has no Predicted close section beside its Bottom line, and one close line" "Bottom line|0|1" \
  "$(printf '%s\n' "$OUT" | sr_heads | cut -d'|' -f1)|$(printf '%s\n' "$OUT" | /usr/bin/grep -c '^Predicted close$')|$(sr_page | /usr/bin/grep -ciE 'not before|about ')"
sr_run --basis "$SR_PLAN"
expect_eq "FL3b --basis prints the work and the width, the chain, the pace, and the floor and likely instants" \
  "- The work left is 480 min as planned, 240 min over the 2 suite runs the gate admits; the longest chain left, T8 → T9, is 150 min; the larger is 240 min.|- The pace: 1.2×, the median over 4 landings of the minutes from dispatch to landing over the minutes planned.|- The earliest instant: 240 min at 1× from now, 7:00 PM; the likely close: 288 min at 1.2×, 7:48 PM." \
  "$(sr_line '- The work left ')|$(sr_line '- The pace: ')|$(sr_line '- The earliest instant: ')"

# ============================================================
section "§GUESS: the schedule always has a best guess — the likely close against the forecast end (the Step-3 approval plus the typed forecast:, else the plan's own minutes), ✅ inside, ➖ over by at most a quarter, ✖️ beyond; before the first one-file landing the bar half is words and the mark is the clock's; a likely close at or before the floor is the one instant"
# ============================================================
# The `none` world has no landing and 510 open minutes, 255 over the 2 admitted, above the 150-minute chain: the floor
# is 255 minutes on. Run at 9:00 AM, 360 minutes after the 3:00 AM approval, a delivered run at the same scale lending
# 1× puts the likely close at 1:15 PM. The 12 h forecast ends at 3:00 PM, 105 minutes on.
SR_NINE=$((SR_NOW - 21600))
SR_SCALE=wave SR_FORECAST=12h sr_world guess-in none
sr_prev 60 wave
SR_AT=$SR_NINE sr_run "$SR_PLAN"
SR_G1="$(sr_ind schedule)"
expect_eq "G-1 an approved plan with forecast: 12h and a delivered run lending 1×, the likely close inside: ✅, the line against the forecast end, naming the forecast, the pace and the bar in words" \
  "$SR_MARK_WITHIN schedule — likely 1:15 PM against 3:00 PM, 105 min inside the 12 h forecast; wave-40's 1×; no one-file landing yet against the 15 min bar" "$SR_G1"
expect_eq "G-1b …and the line never says it cannot be graded, nor reads ❔ (a positive read of the same line first)" "yes|0|0" \
  "$(printf '%s\n' "$SR_G1" | /usr/bin/grep -q '^.* schedule — likely ' && echo yes)|$(printf '%s\n' "$SR_G1" | /usr/bin/grep -c 'declares no forecast\|cannot be graded')|$(printf '%s\n' "$SR_G1" | /usr/bin/grep -c "^$SR_MARK_NONE")"
# The same likely close, 1:00 PM at 345 minutes in, against forecasts of 500, 400 and 480 minutes: 100, 200 and 120
# minutes over, a fifth, a half and exactly a quarter of the forecast.
SR_AT=$((SR_NOW - 22500))
for fc in 500m 400m 8h; do
  SR_SCALE=wave SR_FORECAST=$fc sr_world "guess-$fc" none
  sr_prev 60 wave
  sr_run "$SR_PLAN"
  eval "SR_G2_$fc=\"\$(sr_ind schedule)\""
done
unset SR_AT
expect_eq "G-2 the likely close a fifth over the forecast end: ➖, the minutes over said" \
  "$SR_MARK_NEAR schedule — likely 1:00 PM against 11:20 AM, 100 min over the 8 h 20 min forecast; wave-40's 1×; no one-file landing yet against the 15 min bar" "$SR_G2_500m"
expect_eq "G-2b …half over: ✖️" \
  "$SR_MARK_OVER schedule — likely 1:00 PM against 9:40 AM, 200 min over the 6 h 40 min forecast; wave-40's 1×; no one-file landing yet against the 15 min bar" "$SR_G2_400m"
expect_eq "G-2c …exactly a quarter over: ➖, the bound inclusive" \
  "$SR_MARK_NEAR schedule — likely 1:00 PM against 11:00 AM, 120 min over the 8 h forecast; wave-40's 1×; no one-file landing yet against the 15 min bar" "$SR_G2_8h"
# No forecast: the plan's own minutes, 510, end the forecast at 11:30 AM; the run at 9:00 AM likely closes 1:15 PM,
# 105 minutes over, a fifth of 510.
SR_SCALE=wave SR_FORECAST= sr_world guess-plan none
sr_prev 60 wave
SR_AT=$SR_NINE sr_run "$SR_PLAN"
expect_eq "G-3 no forecast:, graded against the plan's own 510 minutes, said: ➖, never \"declares no forecast\" or ❔" \
  "$SR_MARK_NEAR schedule — likely 1:15 PM against 11:30 AM, 105 min over the plan's 510 min; wave-40's 1×; no one-file landing yet against the 15 min bar" "$(sr_ind schedule)"
# No landing, no delivered run to lend a pace: the floor is the guess at 1×. At 3:00 PM it is 7:15 PM, inside the 48 h
# forecast ending 3:00 AM on the 8th, 1905 minutes on.
sr_world guess-bare none
sr_run "$SR_PLAN"
expect_eq "G-4 before any one-file landing and with no pace yet, the tasks on pace: ✅, the floor is the guess and says so, the bar half in words" \
  "$SR_MARK_WITHIN schedule — likely 7:15 PM against 3:00 AM 2026-10-08, 1905 min inside the 48 h forecast; at 1×, no pace yet; no one-file landing yet against the 15 min bar" "$(sr_ind schedule)"
# From the first landing the mark is the worse half. Four 20-minute landings put the bar over with the clock inside; a
# 6 h forecast puts the clock over with the bar within.
sr_world guess-bar "20 20 20 20"
sr_run "$SR_PLAN"
SR_G4B="$(sr_ind schedule)"
SR_FORECAST=6h sr_world guess-clock "6 6 12 12"
sr_run "$SR_PLAN"
SR_G4C="$(sr_ind schedule)"
sr_world guess-both "6 6 12 12"
sr_run "$SR_PLAN"
expect_eq "G-4b from the first landing, the bar over and the clock inside: the worse half, ✖️, the bar half the median landing in words" \
  "$SR_MARK_OVER|yes|yes" "${SR_G4B%% *}|$(printf '%s\n' "$SR_G4B" | /usr/bin/grep -q 'min inside the 48 h forecast; ' && echo yes)|$(printf '%s\n' "$SR_G4B" | /usr/bin/grep -q '; the median one-file landing takes 20 min, over the 15 min bar$' && echo yes)"
expect_eq "G-4c …the clock over and the bar within: ✖️ again; both within: ✅" \
  "$SR_MARK_OVER|yes|$SR_MARK_WITHIN" \
  "${SR_G4C%% *}|$(printf '%s\n' "$SR_G4C" | /usr/bin/grep -q '; the median one-file landing takes 9 min, within the 15 min bar$' && echo yes)|$(sr_ind schedule | awk '{ print $1 }')"
# An unapproved plan keeps its sentence: nothing to grade the close against.
SR_APPROVED=none sr_world guess-unapproved none
sr_run "$SR_PLAN"
expect_eq "G-4d no Step 3 approval: the sentence stays, ❔, and the bar half is words" \
  "$SR_MARK_NONE schedule — the clock cannot be graded, no Step 3 approval time; no one-file landing yet against the 15 min bar" "$(sr_ind schedule)"
# Nothing left to forecast: every task landed, the run not yet delivered, the guess is now; delivered, it is the
# delivery instant. Neither says it cannot be graded.
sr_world guess-done "6 6 12 12"
awk -F'|' 'BEGIN { OFS = "|" } $2 ~ /^ T([5-9]|1[0-7]) $/ { $14 = " landed " } { print }' "$SR_PLAN" > "$SR_PLAN.t" && mv "$SR_PLAN.t" "$SR_PLAN"
sr_run "$SR_PLAN"
expect_eq "G-6 every task landed and the run open: the guess is now, 3:00 PM, inside the 48 h forecast" \
  "$SR_MARK_WITHIN schedule — likely 3:00 PM against 3:00 AM 2026-10-08, 2160 min inside the 48 h forecast; every task done; the median one-file landing takes 9 min, within the 15 min bar" "$(sr_ind schedule)"
sr_w38_world
awk '{ print } /^current: 9$/ && !d { print "approved-by: fixture 2026-10-18T03:00:00Z \"approved\""; d = 1 }' "$SR_PLAN" > "$SR_PLAN.t" && mv "$SR_PLAN.t" "$SR_PLAN"
sr_run "$SR_PLAN"
expect_eq "G-6b a delivered run: the delivery instant against the forecast end (727 of 2880 minutes), the pace \"delivered\", never cannot be graded" \
  "$SR_MARK_WITHIN schedule — closed 8:07 AM 2026-10-18 against 8:00 PM 2026-10-19, 2153 min inside the 48 h forecast; delivered; no one-file landing yet against the 15 min bar" "$(sr_ind schedule)"
# A pace of 0.36× on this run (four rows sized 100 min, dispatched 36 min before they land) puts the likely close at
# 4:26 PM, before the 7:00 PM floor: the one instant, the floor omitted.
SR_DISPATCH_LEAD=36 sr_world guess-fast "5 5 5 5"
awk -F'|' 'BEGIN { OFS = "|" } $2 ~ /^ T[1-4] $/ { $9 = " 100 " } { print }' "$SR_PLAN" > "$SR_PLAN.t" && mv "$SR_PLAN.t" "$SR_PLAN"
sr_run "$SR_PLAN"
expect_eq "G-5 a pace of 0.36× on this run: the Bottom line prints the one instant and the pace, no \"not before\"" \
  "- Close: likely 4:26 PM (this run's 0.36×).|0" "$(sr_line '- Close: ')|$(printf '%s\n' "$OUT" | /usr/bin/grep -c 'not before')"
expect_eq "G-5b …and the schedule line grades that same instant" "yes" "$(sr_ind schedule | /usr/bin/grep -q 'schedule — likely 4:26 PM against ' && echo yes)"
sr_run --line "$SR_PLAN"
expect_eq "G-5c …and --line reads closes ~<clock>" "closes ~4:26 PM" "${OUT##* · }"
# The pace the floor is made of, 1×: the likely close is the floor, still the one instant.
SR_SCALE=wave sr_world guess-equal none
sr_prev 60 wave
SR_AT=$SR_NINE sr_run "$SR_PLAN"
expect_eq "G-5d a likely close equal to the floor is the one instant too" "- Close: likely 1:15 PM (wave-40's 1×)." "$(sr_line '- Close: ')"
SR_AT=$SR_NINE sr_run --basis "$SR_PLAN"
expect_eq "G-5e …and --basis still prints both instants (the arithmetic is whole)" "yes" \
  "$(sr_line '- The earliest instant: ' | /usr/bin/grep -q '^- The earliest instant: 255 min at 1× from now, 1:15 PM; the likely close: 255 min at 1×, 1:15 PM\.$' && echo yes)"

# ============================================================
section "§LINE: --line is the one-line form, the three indicator glyphs in order · owed: <n> · the close"
# ============================================================
sr_world line "6 6 12 12"
sr_bind
sr_run --line "$SR_PLAN"
expect_eq "L1 the clean world: one line, exit 0" "0|$SR_MARK_WITHIN$SR_MARK_WITHIN$SR_MARK_WITHIN · owed: 0 · closes ≥7:00 PM ~7:48 PM" "$RC|$OUT"
sr_ev "ev=verdict|row=T8|commit=$SR_C1|suite=a.test.sh|result=red|log=/rec/T8.log|at=2026-10-06T14:00:00Z"
sr_owed "key=approve:release|state=open|sent=-|at=2026-10-06T20:00:00Z|title=approval: release|reply=poker: WAIT T12 — approval:release"
sr_owed "key=gate:abc|state=open|sent=-|at=2026-10-06T20:00:00Z|title=gate act: merge|reply=poker: GATE T28 — merge: approve it"
sr_run --line "$SR_PLAN"
expect_eq "L2 a red at head and two owed items: the correctness glyph moves, owed counts them" \
  "$SR_MARK_WITHIN$SR_MARK_OVER$SR_MARK_WITHIN · owed: 2 · closes ≥7:00 PM ~7:48 PM" "$OUT"
sr_run "$SR_PLAN"
expect_eq "L3 …the one line's glyphs are the full page's first three marks, in order" \
  "$SR_MARK_WITHIN$SR_MARK_OVER$SR_MARK_WITHIN" "$(sr_page | awk '$2 == "schedule" || $2 == "correctness" || $2 == "waste" { printf "%s", $1 }')"
SR_FORECAST= sr_world line-none none
sr_run --line "$SR_PLAN"
expect_eq "L4 no forecast: and no landing: the schedule is graded against the plan's own minutes, never ❔, and a close with no pace is its floor" \
  "$SR_MARK_OVER$SR_MARK_WITHIN$SR_MARK_WITHIN · owed: 0 · closes ≥7:15 PM" "$OUT"
SR_APPROVED=none sr_world line-unapproved "6 6 12 12"
sr_run --line "$SR_PLAN"
expect_eq "L5 an unapproved plan: no forecast, said" "$SR_MARK_NONE$SR_MARK_WITHIN$SR_MARK_WITHIN · owed: 0 · no forecast until approved" "$OUT"

# ============================================================
section "§ARGS: the verb's operands"
# ============================================================
sr_world args "6 6 12 12"
sr_run --line --line "$SR_PLAN"
expect_eq "A1 --line twice is the usage error (2)" "2" "$RC"
sr_run --line --basis "$SR_PLAN"
expect_eq "A1b --line with --basis is the usage error (2), one form at a time" "2" "$RC"
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
section "§SKILL: the skill's page opens Sitrep · …, then Bottom line, Task list, Score, Blocked on you; it records only the grade and its rationale, and shows the verb's page unaltered"
# ============================================================
SR_SHAPE="$(sr_shape)"
expect_eq "O2 …its headings, in order, the prototype's" \
  "Bottom line|Task list|Score: <grade> (graded <time>)|Blocked on you" "$(printf '%s\n' "$SR_SHAPE" | sr_heads)"
expect_eq "O3 …and no rule line in the shape (the same block O1 read)" "" "$(printf '%s\n' "$SR_SHAPE" | /usr/bin/grep -E '^[-=─━_]{3,}$')"
expect_eq "O3b the skill shows the page in one code block and stops: it names no confirmation line to quote under it" "yes|0" \
  "$(/usr/bin/grep -q 'inside one fenced code block' "$SR_SKILL" && echo yes)|$(/usr/bin/grep -ci 'confirmation line' "$SR_SKILL")"
sr_world skill "6 6 12 12"
sr_run grade C 'the schedule line holds; nothing else is graded yet' "$SR_PLAN"
sr_run "$SR_PLAN"; printf '%s\n' "$OUT" > "$TMPROOT/page.txt"
expect_eq "O4 the verb's page after a grade: its headings are the shape's, the Score heading carrying the letter and time" \
  "Bottom line|Task list|Score: C (graded 3:00 PM)|Blocked on you" "$(sr_heads "$TMPROOT/page.txt")"
cp "$TMPROOT/page.txt" "$TMPROOT/rep.txt"
expect_eq "O5 the page shown unaltered meets the contract" "ok" "$(sr_check "$TMPROOT/rep.txt" "$TMPROOT/page.txt")"
awk '$0 == "Blocked on you" { print "Task list"; next } $0 == "Task list" { print "Blocked on you"; next } { print }' "$TMPROOT/rep.txt" > "$TMPROOT/bad.txt"
expect_regex "O6 …Task list and Blocked on you swapped: refused on the headings" "^headings: " "$(sr_check "$TMPROOT/bad.txt" "$TMPROOT/page.txt")"
sed 's/^Task list$/TASK LIST/' "$TMPROOT/rep.txt" > "$TMPROOT/bad.txt"
expect_regex "O7 …a heading uppercased: refused on the headings" "^headings: " "$(sr_check "$TMPROOT/bad.txt" "$TMPROOT/page.txt")"
awk '{ print } index($0, "- the schedule line holds") == 1 { print "- diagnosis: the gate is the bottleneck" }' "$TMPROOT/rep.txt" > "$TMPROOT/bad.txt"
awk 'NR == 1 { print; print "─────"; next } { print }' "$TMPROOT/rep.txt" > "$TMPROOT/bad.txt"
expect_eq "O9 …a rule line under the title: refused" "rule line" "$(sr_check "$TMPROOT/bad.txt" "$TMPROOT/page.txt")"

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
sr_ev "ev=verdict|row=T8|commit=$SR_C1|suite=a.test.sh|result=red|log=/rec/T8.log|at=2026-10-06T14:00:00Z"
sr_owed "key=approve:release|state=open|sent=-|at=2026-10-06T20:00:00Z|title=approval: release|reply=poker: WAIT T12 — approval:release"
SR_AT=$((SR_NOW + 60)) sr_tick
SR_AT=$((SR_NOW + 60)) sr_run --line "$SR_PLAN"
SR_AT=$((SR_NOW + 120)) sr_tick
SR_T3="$OUT"
expect_contains "S5 an unchanged tick (nothing decided moved) still takes the unchanged path" "poker: unchanged since " "$SR_T3"
SR_APPROVED=none sr_tick_world surf-none none
sr_tick
SR_T4="$OUT"
sr_run --line "$SR_PLAN"

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
section "§REQ-GOALS-1: a wave plan with no goals: line reads its requirements' themes, one line per theme with its criteria discharged and its open REQs, staged by step"
# ============================================================
# fails-when: "none declared", ❔, or a flat count.
sr_world rg1 "6 6 12 12"; sr_themes 4 $SR_MIXED
sr_run "$SR_PLAN"
expect_eq "RG1-1 at step 4 with rows pending: ➖, one of the three themes reached" \
  "$SR_MARK_NEAR goals — 1 of 3 reached" "$(printf '%s\n' "$OUT" | /usr/bin/grep -E '^[^ ]+ goals — ')"
expect_eq "RG1-1b …and never \"none declared\"" "0" "$(printf '%s\n' "$OUT" | /usr/bin/grep -c 'none declared')"
expect_eq "RG1-2 …one line per theme, in the document's order, each with its count and at most two open REQs named" \
  "$SR_MARK_NEAR The run closes itself — 1 of 3 criteria discharged; open: REQ-1, REQ-2|$SR_MARK_NEAR Rules tested where they run — 1 of 4 criteria discharged; open: REQ-3, REQ-4 and 1 more|$SR_MARK_WITHIN The pages — 1 of 2 criteria discharged, 1 waived" \
  "$(sr_goal_lines | sr_join)"
sr_world rg1-late "6 6 12 12"; sr_themes 7 $SR_MIXED
sr_run "$SR_PLAN"
expect_eq "RG1-3 past step 6 a theme with a pending row is ✖️, and so is the indicator" \
  "$SR_MARK_OVER goals — 1 of 3 reached|$SR_MARK_OVER|$SR_MARK_OVER|$SR_MARK_WITHIN" \
  "$(printf '%s\n' "$OUT" | /usr/bin/grep -E '^[^ ]+ goals — ')|$(sr_goal_lines | awk '{ print $1 }' | sr_join)"
sr_world rg1-done "6 6 12 12"; sr_themes 7 discharged discharged discharged discharged waived discharged discharged discharged waived
sr_run "$SR_PLAN"
expect_eq "RG1-4 every row discharged or waived: every theme ✅, the indicator ✅" \
  "$SR_MARK_WITHIN goals — 3 of 3 reached|$SR_MARK_WITHIN The run closes itself — 3 of 3 criteria discharged|$SR_MARK_WITHIN Rules tested where they run — 3 of 4 criteria discharged, 1 waived|$SR_MARK_WITHIN The pages — 1 of 2 criteria discharged, 1 waived" \
  "$(printf '%s\n' "$OUT" | /usr/bin/grep -E '^[^ ]+ goals — ')|$(sr_goal_lines | sr_join)"

# ============================================================
section "§REQ-GOALS-2: a goals: line's measured goals print after the theme lines, as they print without themes"
# ============================================================
# fails-when: a measured line is lost.
SR_GOALS="fast landings · one-file median under 15m (landing-report --rows)
handoff · a fresh session continues a no-run handoff (record/reader-test-handoff.md)" sr_world rg2 "6 6 12 12"
SR_REQ_AT=specs/epic-01-fx/named-elsewhere.requirements.md sr_themes 4 $SR_MIXED
sr_run "$SR_PLAN"
expect_eq "RG2-1 the requirements file the Step-1 line names is read: three themes and two measured goals, two reached" \
  "$SR_MARK_NONE goals — 2 of 5 reached" "$(printf '%s\n' "$OUT" | /usr/bin/grep -E '^[^ ]+ goals — ')"
expect_eq "RG2-2 …the theme lines first, then the measured goal not reached, in today's form; the reached one in the count only" \
  "$SR_MARK_NEAR The run closes itself|$SR_MARK_NEAR Rules tested where they run|$SR_MARK_WITHIN The pages|$SR_MARK_NONE handoff: a fresh session continues a no-run handoff — no record yet" \
  "$(sr_goal_lines | sed 's/ — [0-9].*//' | sr_join)"

# ============================================================
section "§REQ-GOALS-3: a hand-holds goal read from the landing report counts the window from the last build landing to the card, against its target"
# ============================================================
# fails-when: the median reader answers, or unmeasured.
SR_GOALS="hand-holds · zero from the last landing to the release approval card (landing-report)" sr_world rg3 "6 6 12 12"
sr_run "$SR_PLAN"
expect_eq "RG3-1 no hand-hold since the last build landing: the zero target is reached" \
  "$SR_MARK_WITHIN goals — 1 of 1 reached" "$(printf '%s\n' "$OUT" | /usr/bin/grep -E '^[^ ]+ goals — ')"
sr_ev "ev=stop-run|row=T8|at=2026-10-06T14:00:00Z"
sr_run "$SR_PLAN"
expect_eq "RG3-2 one stop-run after the last build landing misses it" \
  "$SR_MARK_OVER goals — 0 of 1 reached" "$(printf '%s\n' "$OUT" | /usr/bin/grep -E '^[^ ]+ goals — ')"
expect_eq "RG3-3 …the reading is the window's count, from the last build landing to now, before the card has rendered" \
  "$SR_MARK_OVER hand-holds: zero from the last landing to the release approval card — 1 hand-hold from the last build landing (T4) to now: the card has not rendered" \
  "$(sr_goal_lines)"

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
sr_run "$SR_PLAN"
expect_eq "GM3 the page prints the open goal decision as one sentence: one bullet under Blocked on you, the theme named once" "1|1" \
  "$(sr_sect 'Blocked on you' | /usr/bin/grep -c '^- ')|$(sr_sect 'Blocked on you' | /usr/bin/grep -o 'fast landings' | /usr/bin/grep -c .)"
sed -i.bak 's/one-file median under 15m/one-file median under 30m/' "$SR_PLAN" && rm -f "$SR_PLAN.bak"
printf '# reader test\n\nverdict: pass\n' > "$SR_DIR/reader-test-handoff.md"
sr_owed "key=approve:release|state=open|sent=-|at=2026-10-06T20:00:00Z|title=approval: release|reply=poker: WAIT T12 — approval:release"
sr_run "$SR_PLAN"
expect_eq "GM3b both goals read reached while the decision is still open: the page drops it and keeps the approval, in You owe and in Blocked on you, with nothing on stderr" \
  "- You owe 1: approve release.|- approve release: T12 waits on it|" "$(sr_line '- You owe')|$(sr_sect 'Blocked on you' | sr_join)|$ERR"
SR_AT=$((SR_NOW + 60)) sr_tick
expect_eq "GM4 the goal now reads reached: the tick closes its open decision, and the item stays on the ledger closed" "1|0" \
  "$(/usr/bin/grep -c '|key=decide:goal:fast-landings|state=closed|' "$SR_OWED_F")|$(/usr/bin/grep -c '|key=decide:goal:fast-landings|state=open|' "$SR_OWED_F")"

# ============================================================
section "§ONE-FILE: the schedule's bar half and the one-file goal read the one-file landings only; a landing of more files moves neither"
# ============================================================
# The forecast is 200 h: the landings' pace puts the likely close far out, and only the bar half is under test here.
SR_FORECAST=200h SR_GOALS="fast landings · one-file median under 5m (landing-report --rows)" sr_world one-file "90 90 10 10"
awk -F'|' 'BEGIN { OFS = "|" } $2 ~ /^ T[12] $/ { $11 = " lib/t1.sh, lib/x.sh " } { print }' "$SR_PLAN" > "$SR_PLAN.t" && mv "$SR_PLAN.t" "$SR_PLAN"
sr_run "$SR_PLAN"
expect_eq "OF1 two 90-minute landings of two files and two 10-minute one-file landings: the schedule mark reads 10 min, ✅ within the bar" \
  "$SR_MARK_WITHIN|10 min" "$(sr_ind schedule | awk '{ print $1 }')|$(sr_ind schedule | /usr/bin/grep -oE 'takes [0-9]+ min' | sed 's/^takes //')"
expect_eq "OF2 …and the one-file goal reads 10 min against its 5-minute target" \
  "10 min" "$(sr_goal_lines | /usr/bin/grep ' fast landings: ' | sed 's/.* — //' | /usr/bin/grep -oE '[0-9]+ min')"

# ============================================================
section "§WAIT-WORDS: a task waiting on the review facts says so in words; the judge's facts string and its record paths never reach the page"
# ============================================================
sr_world wait-words "6 6 12 12"
SR_W_ROW="$(sr_row T19 "Review-gated row · complexity: standard" proof:review 30 pending)"
awk -v r="$SR_W_ROW" '{ print } /^\| T17 \|/ { print r }' "$SR_PLAN" > "$SR_PLAN.t" && mv "$SR_PLAN.t" "$SR_PLAN"
sr_run "$SR_PLAN"
SR_W_LINE="$(sr_rows | /usr/bin/grep '/T19: ')"
expect_eq "WW1 the review-gated task's clause names the review facts at the head, with no facts string and no record path" "yes|0" \
  "$(printf '%s\n' "$SR_W_LINE" | /usr/bin/grep -q ' — waits on the review facts at the head' && echo yes)|$(printf '%s\n' "$SR_W_LINE" | /usr/bin/grep -cE 'facts_state|record/|\.md')"


# ============================================================
section "§NEXT-STOPS: the Bottom line's Next names the release approval card to the user, in order, while it lies ahead of the merge; once it is replied it names no stop"
# ============================================================
sr_world next-stops "6 6 12 12"
sed -i.bak 's/^| T17 | 4 | build |/| T17 | 4 | integrate |/' "$SR_PLAN" && rm -f "$SR_PLAN.bak"
sr_run "$SR_PLAN"
expect_eq "NX1 an open integrate row ahead and no reply to the release approval: Next puts the card to you before that row" "yes" \
  "$(sr_line '- Next: ' | /usr/bin/grep -q ', then the release approval card to you, then T17\.$' && echo yes)"
printf 'release-approval/v1|plan=%s|head=%s|at=2026-10-06T20:00:00Z|decisions=0\nreplied: at=2026-10-06T20:30:00Z all default\n' "$SR_PLAN" "$SR_H" > "$SR_DIR/release-approval-abcd1234.md"
sr_run "$SR_PLAN"
expect_eq "NX2 …the card replied: Next is still there, and names no stop" "1|0" \
  "$(sr_line '- Next: ' | /usr/bin/grep -c 'then')|$(sr_line '- Next: ' | /usr/bin/grep -c 'release approval card')"
# A page written before the card was renamed carries the old stem and tag; it is a reply all the same.
SR_OLDW="review"
sed -e "s#^release-approval/v1|#${SR_OLDW}-results/v1|#" "$SR_DIR/release-approval-abcd1234.md" > "$SR_DIR/${SR_OLDW}-results-abcd1234.md"
rm -f "$SR_DIR/release-approval-abcd1234.md"
sr_run "$SR_PLAN"
expect_eq "NX3 …a reply recorded under the card's old stem and tag is read the same: no stop named" "1|0" \
  "$(sr_line '- Next: ' | /usr/bin/grep -c 'then')|$(sr_line '- Next: ' | /usr/bin/grep -c 'release approval card')"


# ============================================================
section "§OPEN-DECISION: a decision put to the user and not yet ruled is owed by the user, on the page and in the one-line form"
# ============================================================
sr_world open-dec "6 6 12 12"
sr_bind
printf '# Design ledger — wave-02-fx\n\n## Δ0 — D19 put (orchestrator 2026-10-20 6:44 AM PDT): the regression rule the judge holds\n\nAnswered now or in an hour.\n' > "$SR_DIR/design-ledger.md"
sr_run "$SR_PLAN"
expect_eq "OD1 one put with no ruling: You owe counts it" "- You owe 1: reply to D19." "$(sr_line '- You owe')"
expect_eq "OD2 …Blocked on you prints one sentence with its number, its title, the reply asked and its wait line" \
  "- D19 · the regression rule the judge holds: reply with the option number. Answered now or in an hour." "$(sr_sect 'Blocked on you' | sr_join)"
sr_run --line "$SR_PLAN"
expect_eq "OD3 …the one-line form's owed number counts it" "owed: 1" "$(printf '%s\n' "$OUT" | /usr/bin/grep -oE 'owed: [0-9]+')"
printf '\n## Δ1 — D19 ruled "2" (Chris Lehman 2026-10-20): the regression rule the judge holds\n' >> "$SR_DIR/design-ledger.md"
sr_run "$SR_PLAN"
expect_eq "OD4 the same decision ruled: the page owes nothing and says so, and the decisions line reads it ruled" \
  "- You owe nothing now.|- Nothing: no decision or action is owed by you.|yes" \
  "$(sr_line '- You owe')|$(sr_sect 'Blocked on you' | sr_join)|$(printf '%s\n' "$OUT" | /usr/bin/grep -q 'decisions — 1 ruled in 1 round;' && echo yes)"


# ============================================================
section "§DECISIONS: every decision put and not ruled is on the page with its wait line, and every landed reading with its result, one line each"
# ============================================================
# FIXTURE FIDELITY: the put heading and the wait line under it in the shape `decisions put` writes them, and the
# reading lines in the shape `proof-add review` writes them under ## SDLC State. fails-when: the open decision, its
# wait line, or a reading's result is absent from the page.
SR_D_WAIT="Answered now or in an hour, nothing moves: no task waits on it."
sr_ledger_put() {  # <D<n>> <title> <wait line> -> the run's design ledger holds one put of it, nothing ruled
  printf '# Design ledger — wave-02-fx\n\n## Δ0 — %s put (orchestrator 2026-10-06 1:30 PM PDT): %s\n\n%s\n' "$1" "$2" "$3" > "$SR_DIR/design-ledger.md"
}
sr_readings() {  # -> two readings landed on the plan: the evidence reading of the whole failing, the adversarial one of a piece passing
  awk -v h="$SR_H" '{ print } /^current: [0-9]+$/ {
    print "proved: kind=review head=" h " at=2026-10-06T20:00:00Z evidence=record/wave-02-fx/auditor-evidence.md question=evidence reader=w-T20 result=fail scope=whole"
    print "proved: kind=review head=" h " at=2026-10-06T20:05:00Z evidence=record/wave-02-fx/critic-adversarial.md question=adversarial reader=w-T21 result=pass scope=piece" }' \
    "$SR_PLAN" > "$SR_PLAN.t" && mv "$SR_PLAN.t" "$SR_PLAN"
}
sr_world decisions "6 6 12 12"
sr_bind
sr_ledger_put D21 "the gate the judge holds" "$SR_D_WAIT"
sr_readings
sr_run "$SR_PLAN"
expect_eq "DE1 the open decision is one bullet under Blocked on you: its number, its title, the reply asked, then its wait line" \
  "- D21 · the gate the judge holds: reply with the option number. $SR_D_WAIT" "$(sr_sect 'Blocked on you' | /usr/bin/grep 'D21')"
expect_eq "DE2 each landed reading is one line of the Score with its result in words, the failing one first as the plan has it" \
  "$SR_MARK_OVER reading — evidence on the whole: failed at 1:00 PM|$SR_MARK_WITHIN reading — adversarial on a piece: passed at 1:05 PM" \
  "$(sr_sect 'Score: .*' | /usr/bin/grep -E '^[^ ]+ reading — ' | sr_join)"
printf '\n## Δ1 — D21 ruled "1" (Chris Lehman 2026-10-06): the gate the judge holds\n' >> "$SR_DIR/design-ledger.md"
sr_run "$SR_PLAN"
expect_eq "DE3 the decision ruled: Blocked on you no longer names it and says nothing is owed, while both readings still print" \
  "- Nothing: no decision or action is owed by you.|2" \
  "$(sr_sect 'Blocked on you' | sr_join)|$(sr_sect 'Score: .*' | /usr/bin/grep -cE '^[^ ]+ reading — ')"

# ============================================================
section "§RECAP: the resume recap reads the same open decisions and readings through the same reader as the page"
# ============================================================
# The handoff document in the shape the handoff verb writes its first lines (its kind line, resume point, written,
# plan, working branch), read by the real resume verb. fails-when: the recap prints "open: none" while the ledger
# holds an unruled put.
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
sr_readings
sr_handoff
sr_recap
expect_eq "RC1 resume exits 0 and the recap names the open decision with its title and wait line, and no open: none" \
  "0|open: D21 — the gate the judge holds: reply with the option number. $SR_D_WAIT|0" \
  "$RC|$(printf '%s\n' "$RECAP" | /usr/bin/grep '^open: D21 ')|$(printf '%s\n' "$RECAP" | /usr/bin/grep -c '^open: none')"
expect_eq "RC2 …and each landed reading with its result, in the page's words" \
  "reading: evidence on the whole: failed at 1:00 PM|reading: adversarial on a piece: passed at 1:05 PM" \
  "$(printf '%s\n' "$RECAP" | /usr/bin/grep '^reading: ' | sr_join)"
printf '\n## Δ1 — D21 ruled "1" (Chris Lehman 2026-10-06): the gate the judge holds\n' >> "$SR_DIR/design-ledger.md"
sr_recap
expect_eq "RC3 the decision ruled: no open: line names it while the tick's approvals still read open, and the recap lists it settled" \
  "0|2|settled: D21 · \"1\" · Chris Lehman 2026-10-06 · the gate the judge holds" \
  "$(printf '%s\n' "$RECAP" | /usr/bin/grep -c '^open: .*D21')|$(printf '%s\n' "$RECAP" | /usr/bin/grep -c '^open: approve:')|$(printf '%s\n' "$RECAP" | /usr/bin/grep '^settled: D21')"

# ============================================================
section "§ONCE: a decision a row waits on is owed once, not as the tick's approval item and the page's decision item both"
# ============================================================
# The real tick opens the owed item for the row's approval read; the real approve verb closes it. fails-when: You owe
# counts the decision twice, or the recap names it on two lines.
SR_D_ROW="$(sr_row T20 "Decision-gated row · complexity: standard" approval:D21 30 pending)"
sr_tick_world once "6 6 12 12"
awk -v r="$SR_D_ROW" '{ print } /^\| T17 \|/ { print r }' "$SR_PLAN" > "$SR_PLAN.t" && mv "$SR_PLAN.t" "$SR_PLAN"
# the approve verb dry-commits the plan through the commit gate, which reads the declared SDLC version
sed -i.bak 's/^wave: wave-02-fx$/&\
canonical_sdlc_version: 14/' "$SR_PLAN" && rm -f "$SR_PLAN.bak"
sr_ledger_put D21 "the gate the judge holds" "Answered in an hour rather than now, T20 starts an hour later and the predicted close holds: it is off the longest chain."
sr_tick
expect_eq "ON0 precondition: the tick says T20 waits on approval:D21 and opens an item for it on the person's ledger" "yes|1" \
  "$(/usr/bin/grep -q '^poker: WAIT T20 — approval:D21$' "$TMPROOT/tick.out" && echo yes)|$(/usr/bin/grep -cE '\|key=[a-z]+:D21\|state=open\|' "$SR_REPO/.bionic/tmp/owed-$SID.state")"
sr_run "$SR_PLAN"
expect_eq "ON1 You owe counts the decision once, beside the two approvals the tick opened" \
  "- You owe 3: approve release, approve merge and reply to D21." "$(sr_line '- You owe')"
expect_eq "ON2 …Blocked on you names D21 on one bullet, the decision's own" "1|yes" \
  "$(sr_sect 'Blocked on you' | /usr/bin/grep -c 'D21')|$(sr_sect 'Blocked on you' | /usr/bin/grep -q '^- D21 · the gate the judge holds: reply with the option number\. ' && echo yes)"
expect_eq "ON3 …and the row waiting on it is blocked on the person" "yes" \
  "$(sr_rows | /usr/bin/grep -q '^⛔ 4/T20: ' && echo yes)"
sr_handoff
sr_recap
expect_eq "ON4 the recap names D21 on one open: line and owes no second approval line for it" "1|0" \
  "$(printf '%s\n' "$RECAP" | /usr/bin/grep -c '^open: .*D21')|$(printf '%s\n' "$RECAP" | /usr/bin/grep -c '^owned-by-user: approval:D21')"
sr_poke approve D21 "1" >/dev/null 2>&1
expect_eq "ON5 the approve verb closes the tick's item: nothing for D21 is left open on the person's ledger" "0" \
  "$(/usr/bin/grep -cE '\|key=[a-z]+:D21\|state=open\|' "$SR_REPO/.bionic/tmp/owed-$SID.state")"

# ============================================================
section "§TITLE: the title says the step of nine, and the step the work stands at when a landed or active task is ahead of it"
# ============================================================
# fails-when: a plan at current: 5 with an active step-7 task prints step 5 alone, or an agreeing plan prints the clause.
sr_title() { sr_page | head -1 | /usr/bin/grep -oE 'step [0-9]+ of 9( · work at step [0-9]+ \([^)]*\))?'; }
sr_world title-ahead "6 6 12 12"
sed -i.bak -e 's/^current: 4$/current: 5/' -e 's/^| T7 | 4 | build |/| T7 | 7 | build |/' "$SR_PLAN" && rm -f "$SR_PLAN.bak"
sr_run "$SR_PLAN"
expect_eq "TI1 current: 5 with T7 active at step 7: the title names both" "step 5 of 9 · work at step 7 (T7)" "$(sr_title)"
sr_world title-agree "6 6 12 12"
sed -i.bak -e 's/^current: 4$/current: 5/' -e 's/^| T7 | 4 | build |/| T7 | 5 | build |/' "$SR_PLAN" && rm -f "$SR_PLAN.bak"
sr_run "$SR_PLAN"
expect_eq "TI2 current: 5 with the furthest active task at step 5: one step alone" "step 5 of 9" "$(sr_title)"
sr_world title-pending "6 6 12 12"
sed -i.bak -e 's/^current: 4$/current: 5/' -e 's/^| T9 | 4 | build |/| T9 | 7 | build |/' "$SR_PLAN" && rm -f "$SR_PLAN.bak"
sr_run "$SR_PLAN"
expect_eq "TI3 a pending task at step 7 is not work at step 7: one step alone" "step 5 of 9" "$(sr_title)"

# ============================================================
section "§ONE-LINE: every task of the plan has one Task list line, never continued: the name is the cell up to its first \" (\", \": \", \". \" or \" · \", cut at a word with … to fit 92 columns, the glyph, the label and the short state whole"
# ============================================================
# fails-when: a 300-character task cell prints over two lines or past 92 columns; a clipped line loses its state or
# time, or names two blockers; the cut falls inside a word; a task of a 40-task plan has no line, or the list holds
# any line beyond one per step 0 to 3 and per task.
# sr_rawsit -> the Task list's physical lines as printed (nothing unfolded), heading excluded, to the first blank.
sr_rawsit() { printf '%s\n' "$OUT" | awk 'on && /^$/ { exit } on { print } $0 == "Task list" { on = 1 }'; }
# sr_cell <id> <cell> -> SR_PLAN with that task's description cell replaced, in the Tasks table alone (a row of the
# dispatch ledger names the same id)
sr_cell() { awk -v id=" $1 " -v t="$2" -F'|' 'BEGIN { OFS = "|" } $2 == id && NF > 12 { $5 = " " t " " } { print }' "$SR_PLAN" > "$SR_PLAN.t" && mv "$SR_PLAN.t" "$SR_PLAN"; }
SR_LONG300="$(awk 'BEGIN { for (i = 1; length(s) < 300; i++) s = s (i > 1 ? " " : "") "wordnumber" i; print substr(s, 1, 300) }')"
sr_world oneline "6 6 12 12"
sed -i.bak -e 's#^\(| T10 | 4 | build | [^|]*| — | — | \)—#\1lib/t5.sh,lib/t6.sh,lib/t7.sh#' "$SR_PLAN" && rm -f "$SR_PLAN.bak"
sed -i.bak -e 's/^\(| T11 | .*| 30 | REQ-1 | lib\/t11.sh | — | — | \)pending/\1held/' "$SR_PLAN" && rm -f "$SR_PLAN.bak"
for SR_T in T1 T5 T10 T11; do sr_cell "$SR_T" "$SR_LONG300"; done
sr_run "$SR_PLAN"
expect_eq "ONE0 precondition: the world renders, four task cells are 300 characters, and T10 waits on three open tasks, T11 is held" "0|4|yes|yes" \
  "$RC|$(/usr/bin/grep -E '^\| (T1|T5|T10|T11) \|' "$SR_PLAN" | awk -F'|' 'NF > 12 && length($5) == 302 { n++ } END { print n + 0 }')|$(/usr/bin/grep -q '^| T10 | .*lib/t5.sh,lib/t6.sh,lib/t7.sh' "$SR_PLAN" && echo yes)|$(/usr/bin/grep -q '^| T11 | .*| held |' "$SR_PLAN" && echo yes)"
SR_ONE_LINES="$(for SR_T in T1 T5 T10 T11; do sr_rawsit | /usr/bin/grep -E "^[^ ]+ 4/$SR_T: "; done)"
expect_eq "ONE1 a 300-character cell in each state (done, building, waiting on three, held) prints one line each, and the list has no continuation line" "4|0" \
  "$(printf '%s\n' "$SR_ONE_LINES" | /usr/bin/grep -c .)|$(sr_rawsit | /usr/bin/grep -c '^ ')"
expect_eq "ONE1b …each at most 92 columns by the suite's own measure, and the widest is within a word of the edge (widest $(printf '%s\n' "$SR_ONE_LINES" | sr_maxw))" "yes" \
  "$([ "$(printf '%s\n' "$SR_ONE_LINES" | sr_maxw)" -le 92 ] && [ "$(printf '%s\n' "$SR_ONE_LINES" | sr_maxw)" -ge 70 ] && echo yes)"
expect_eq "ONE2 each clipped line ends in its short state whole: the time, building, waits on the first blocker and a count, held" \
  "(3:06 AM)|— building|— waits on T5 +2|— held" \
  "$(for SR_T in T1 T5 T10 T11; do printf '%s\n' "$SR_ONE_LINES" | /usr/bin/grep -E "^[^ ]+ 4/$SR_T: " | sed -E 's/^.*… (\(3:06 AM\)|— .*)$/\1/'; done | sr_join)"
# the cut: the name ends in … after a whole word of the cell, never inside one
sr_cutok() {  # <task line> -> yes when its name is a whole-word prefix of the 300-character cell, ending in …
  local nm; nm="$(printf '%s\n' "$1" | sed -E 's/^[^ ]+ [0-9]+\/T[0-9]+: (.*)… (\(.*|— .*)$/\1/')"
  case "$SR_LONG300" in "$nm "*) echo yes ;; *) echo no ;; esac
}
expect_eq "ONE2b the name of each clipped line is a whole-word prefix of the cell, then …" "yes|yes|yes|yes" \
  "$(for SR_T in T1 T5 T10 T11; do sr_cutok "$(printf '%s\n' "$SR_ONE_LINES" | /usr/bin/grep -E "^[^ ]+ 4/$SR_T: ")"; done | sr_join)"
# the name of a cell that fits is whole, cut at the first " (", ": ", ". " or " · "
sr_cell T13 "Alpha one (the aside) and the rest"
sr_cell T14 "Beta two: and the rest"
sr_cell T15 "Gamma three. And the rest"
sr_cell T16 "Delta four · and the rest"
sr_run "$SR_PLAN"
expect_eq "ONE3 the name stops at the first of \" (\", \": \", \". \" and \" · \", and the rest of the cell never prints" \
  "⬜ 4/T13: Alpha one|⬜ 4/T14: Beta two|⬜ 4/T15: Gamma three|⬜ 4/T16: Delta four" \
  "$(for SR_T in T13 T14 T15 T16; do sr_rawsit | /usr/bin/grep -E "^[^ ]+ 4/$SR_T: "; done | sr_join)"
# every state, in short form
sr_world oneline-states "6 6 12 12"
sed -i.bak -e 's/^\(| T11 | .*| 30 | REQ-1 | lib\/t11.sh | — | — | \)pending/\1held/' "$SR_PLAN" && rm -f "$SR_PLAN.bak"
sr_ev "ev=ready|row=T6|name=w-T6|commit=$SR_C1|branch=wt/02-T6|tree=$SR_REPO/.worktrees/02-T6|suites=a.test.sh|debt=-|carrier=1:x|at=2026-10-06T13:30:00Z"
sr_ev "ev=verdict|row=T7|commit=$SR_C1|suite=a.test.sh|result=red|log=/rec/T7.log|at=2026-10-06T14:00:00Z"
sr_run "$SR_PLAN"
expect_eq "ONE4 the short state of each kind: done a time, next on the line, queued behind, building, red, waiting on one, held" \
  "T1 (3:06 AM)|T8 — next on the line|T6 — queued behind T8|T5 — building|T7 — red|T9 — waits on T8|T11 — held" \
  "$(for SR_T in T1 T8 T6 T5 T7 T9 T11; do sr_rawsit | /usr/bin/grep -E "^[^ ]+ 4/$SR_T: " | sed -E 's/^[^ ]+ 4\/(T[0-9]+): [^(—]*(\(.*|— .*)$/\1 \2/'; done | sr_join)"
# a 40-task plan in every state: one line per step 0 to 3 and per task
SR_EXTRA=23 sr_world oneline-forty "6 6 12 12"
sed -i.bak -e 's/^\(| T11 | .*| 30 | REQ-1 | lib\/t11.sh | — | — | \)pending/\1held/' "$SR_PLAN" && rm -f "$SR_PLAN.bak"
sr_ev "ev=verdict|row=T7|commit=$SR_C1|suite=a.test.sh|result=red|log=/rec/T7.log|at=2026-10-06T14:00:00Z"
for SR_T in T1 T9 T20 T30 T40; do sr_cell "$SR_T" "$SR_LONG300"; done
sr_run "$SR_PLAN"
SR_FORTY_IDS="$(sr_rawsit | /usr/bin/grep -oE '^[^ ]+ 4/T[0-9]+:' | sed -E 's/^[^ ]+ 4\/(T[0-9]+):$/\1/' | sort -u | wc -l | tr -d ' ')"
expect_eq "ONE5 a 40-task plan in every state: 44 lines in the Task list and every task id prints once" "of 40 tasks done|44|40" \
  "$(sr_page | head -1 | /usr/bin/grep -oE 'of [0-9]+ tasks done')|$(sr_rawsit | /usr/bin/grep -c .)|$SR_FORTY_IDS"
expect_eq "ONE5b …the four attended steps and nothing but the tasks after them: no step 5 to 9 line" "4|0" \
  "$(sr_rawsit | /usr/bin/grep -cE '^[^ ]+ [0-3]: ')|$(sr_rawsit | /usr/bin/grep -cE '^[^ ]+ [4-9]: ')"
expect_eq "ONE5c …no line wider than 92 columns, none continued" "yes|0" \
  "$([ "$(sr_rawsit | sr_maxw)" -le 92 ] && echo yes)|$(sr_rawsit | /usr/bin/grep -c '^ ')"


finish
