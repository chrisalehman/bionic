#!/bin/bash
# Tests for `hooks/session-poker.sh handoff [path]` — the handoff file is the store (wave-38 T12;
# REQ-3 AC-3.1, AC-3.2, AC-3.5; design-ledger Δ17 D23, Δ21 D4, D13).
#
# THE VERB WRITES A FILE, AND THE PLAN CARRIES A POINTER. `handoff` writes record/<wave>/handoff.md
# (or the [path] it is given, under the docs root): the kind line `bionic-handoff/v1`; the sitrep
# head (the last recorded Bottom line with its time, and the one-line form, both the sitrep verb's
# own lines); the machine lines (written, plan, branch, integration, step, open rows, last landed,
# live writers with tree and current act, last proof, patrol); the five human lines from
# --mid-flight --order --rulings --lessons --risks, carried from the previous file when a flag is
# absent; the safe line (`safe to clear`, or `wait N minutes` while a landing's `ready` is in
# flight); and last the literal next command `/bionic:canonical-sdlc <path>`. The plan's
# `## Handoff` becomes the heading and one line `handoff: <path> written <local time>`. A delivered
# plan gets the closed form `resume point: NONE — DELIVERED at …` instead of a refusal. adopt's
# STALE note and launch-sync's HANDOFF-STALE judge the file's own written instant.
#
# Sections: §WRITE §CARRY §POINTER §SAFE §CLOSED §READERS. §RESUME (AC-3.3) is T13's and joins later.
#
# FIXTURE FIDELITY (HERMETIC). The session-poker prelude's sandbox, pins and gate-admitted plan (`s42_plan`, as
# session-poker-4 §HANDOFF builds it), one repository per world. The landing record and the sitrep
# log are planted in the shapes their writers write (lib/line.sh's `line/v1` events, as
# tests/sitrep.test.sh plants them; T10's `sitrep-log/v1` lines). A live landing is a real process
# whose pid and start time are the `ready` event's carrier, the rule lib/slots.sh reads.
#
# THE CLOCK IS PINNED. Now is BIONIC_NOW_EPOCH, the poker's seam (sitrep_now), fixed below; the suite reads no
# clock and waits on nothing, so the shell-lint census has no row for it. The verb's own `written:` instant is the
# machine's clock, and session-poker-4 §HANDOFF HO-2b holds it to the clock around the run.
#
# ANTI-VACUITY. Every absence sits beside a positive read through the same extractor on the same
# file: the shape extractor is proved non-empty by W2, the human-line extractor by C1, the safe
# line by S1 before S2 reads its absence.
#
# THE SEAM, for RED evidence against a mutated copy without touching the shipped file:
#   HANDOFF_POKER_UNDER_TEST=/path/to/mutant.sh bash tests/handoff-file.test.sh
#
# Usage: bash tests/handoff-file.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"
. "$(dirname "$0")/lib/bound-marker.sh"
. "$(dirname "$0")/lib/roster-row.sh"
. "$(dirname "$0")/lib/swept-marker.sh"
. "$(dirname "$0")/lib/live-answer.sh"

POKER="${HANDOFF_POKER_UNDER_TEST:-${BIONIC_HOOKS_DIR}/session-poker.sh}"
S46_LIB="${BIONIC_HOOKS_DIR}/../payload/scripts/lib/proof.sh"
. "$(dirname "$0")/session-poker.prelude.sh"
POKE_BOUND=180
export TZ=America/Los_Angeles

HF_PIDS=""
trap 'for _p in $HF_PIDS; do kill "$_p" 2>/dev/null; done; cleanup' EXIT

HF_NOW=1791324000     # 2026-10-06T22:00:00Z = 3:00 PM PDT, the pinned now
export BIONIC_NOW_EPOCH="$HF_NOW"
HF_DOOR=".bionic/docs/record/wave-01-fixture/handoff.md"
HF_PLAN_REL=".bionic/docs/plans/epic-99-fixture/wave-01-fixture.plan.md"
HF_OPEN_SHAPE="bionic-handoff/v1,sitrep head,sitrep line,written,plan,branch,integration,step,open rows,last landed,live writers,last proof,patrol,mid-flight,order,rulings,lessons,risks,safe,door"
HF_CLOSED_SHAPE="bionic-handoff/v1,resume point,written,plan,branch,patrol,continuation,mid-flight,order,rulings,lessons,risks,safe,door"

# ---------- extractors ----------
hf_shape() {  # <file> -> the labels of its top-level lines, in order, comma-joined
  awk '
    NR == 1 { out = $0; next }
    /^[ \t]/ || /^- / { next }
    { l = $0
      if (l ~ /^(safe to clear$|wait [0-9]+ minutes|STALE — )/) l = "safe"
      else if (index(l, "/bionic:") == 1) l = "door"
      else { sub(/:.*$/, "", l); sub(/ \(.*$/, "", l) }
      out = out "," l }
    END { print out }' "$1" 2>/dev/null
}
hf_human() {  # <file> -> the five human lines with their continuation lines, verbatim
  awk '/^(mid-flight|order|rulings|lessons|risks):/ { h = 1; print; next } h && /^[ \t]/ { print; next } { h = 0 }' "$1" 2>/dev/null
}
hf_label() {  # <file> <label> -> that line, verbatim (the first)
  awk -v k="$2: " 'index($0, k) == 1 { print; exit }' "$1" 2>/dev/null
}
hf_section() {  # <plan> -> the lines of ## Handoff, the heading excluded
  awk '/^```/ { f = !f } !f && /^## / { h = ($0 ~ /^## Handoff[ \t]*$/); next } h { print }' "$1"
}
hf_outside() {  # <plan> -> every line outside ## Handoff
  awk '/^```/ { f = !f } !f && /^## / { h = ($0 ~ /^## Handoff[ \t]*$/) } !h { print }' "$1"
}
hf_safe() { tail -2 "$1" 2>/dev/null | head -1; }   # <file> -> its safe line (the one before the door)
hf_iso() { date -u -r "$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ; }
hf_ev() { mkdir -p "${HF_REC%/*}"; printf 'line/v1|%s\n' "$1" >> "$HF_REC"; }
hf_live() {  # -> HF_CARRIER, a live process's `<pid>:<start>` (lib/slots.sh's rule); its pid in HF_PID
  tail -f /dev/null & HF_PID=$!
  HF_PIDS="$HF_PIDS $HF_PID"
  local s; s="$(LC_ALL=C TZ=UTC0 ps -o lstart= -p "$HF_PID" 2>/dev/null)"
  # shellcheck disable=SC2086
  set -- $s
  HF_CARRIER="$HF_PID:$*"
}

# ---------- the world ----------
#
# hf_world <label> [roster yes|no] -> HF_R (repo), HF_P (plan), HF_F (the default handoff file),
# HF_REC (its landing record), HF_INT/HF_WORK (the two heads). session-poker-4 §HANDOFF's plan: the
# frontmatter branch keys over real branches, two landed lines, two proof lines, active rows T2 and
# T3 and a pending T6 with a worktree, a Not Doing; with `roster yes`, w-T2's finished run.
hf_world() {
  local label="$1" roster="${2:-yes}" rd
  HF_R="$(make_repo "hf-$label")"; ( cd "$HF_R" && git commit -q --allow-empty -m init )
  git -C "$HF_R" config user.name "Dana Fixture"
  git -C "$HF_R" branch -f trunk HEAD
  git -C "$HF_R" commit -q --allow-empty -m "work"
  git -C "$HF_R" branch -f wave/01-fixture HEAD
  HF_INT="$(git -C "$HF_R" rev-parse trunk)"
  HF_WORK="$(git -C "$HF_R" rev-parse wave/01-fixture)"
  HF_P="$(s42_plan "$HF_R" 4)"
  awk -v w="$HF_WORK" '
    NR == 1 && $0 == "---" { print; print "working-branch: wave/01-fixture"; print "integration-branch: trunk"; next }
    /^approved-by:/ { print; print "proved: kind=floor head=" w " at=2026-10-08T11:00:00Z evidence=record/old-floor.log"
                      print "proved: kind=review head=" w " at=2026-10-08T12:30:00Z evidence=record/last-review.md"; next }
    /^- T5: pending dispatch/ { print "- T4: landed 2222222222222222222222222222222222222222 2026-10-08T10:30:00Z"
                                print "- T3: landed 1111111111111111111111111111111111111111 2026-10-08T09:00:00Z"; print; next }
    /^\| T2 \| 4 \| build \|/ { sub(/\| implementor \|/, "| w-T2 |"); print
                               print "| T3 | 4 | build | the third build | — | — | 30 | REQ-1 | c.sh | .worktrees/01-T3 | abc1234 | active |"
                               print "| T6 | 4 | build | the sixth build | — | — | 30 | REQ-1 | d.sh | .worktrees/01-T6 | abc1234 | pending |"; next }
    { print }
    END { print "\n## Not Doing\n\n- nothing, in this fixture" }' "$HF_P" > "$HF_P.hf" && mv "$HF_P.hf" "$HF_P"
  if [ "$roster" = yes ]; then
    rd="$HF_R/.bionic/tmp/runs"; mkdir -p "$rd"; : > "$rd/w-T2-x.test.sh.log"
    roster_row_fixture session="$SID" name=w-T2 agent_id=a-w-T2 subagent_type=implementor \
      run_log="$rd/w-T2-x.test.sh.log" run_cmd='tests/run.sh --only x.test.sh' run_rc=0 >> "$(roster_of "$HF_R")"
  fi
  HF_F="$HF_R/$HF_DOOR"
  HF_REC="$HF_R/.bionic/docs/record/wave-01-fixture/landing-proofs.log"
  s42_snap "$HF_R" "$HF_P"
}

# ============================================================
section "§WRITE: handoff writes record/<wave>/handoff.md — kind line, sitrep head, machine lines, five human lines, safe line, the literal next command (AC-3.1; D23, D4, D13)"
# ============================================================
hf_world write
mkdir -p "$HF_R/.bionic/docs/record/wave-01-fixture"
printf 'sitrep-log/v1|at=2026-10-08T21:00:00Z|item=an older item (line 9)\n' > "$HF_R/.bionic/docs/record/wave-01-fixture/sitrep.log"
printf 'sitrep-log/v1|at=2026-10-08T22:00:00Z|item=schedule holds at 1.2x (line 37)\n' >> "$HF_R/.bionic/docs/record/wave-01-fixture/sitrep.log"
printf 'sitrep-log/v1|at=2026-10-08T22:00:00Z|item=hypothesis: the gate sets the close\n' >> "$HF_R/.bionic/docs/record/wave-01-fixture/sitrep.log"
expect_false "W0 precondition: no handoff file before the first run" test -e "$HF_F"
poke "$HF_R" sitrep --line
HF_LINE="$OUT"
expect_nonempty "W0b precondition: the sitrep verb's one-line form reads non-empty on this world" "$HF_LINE"
poke "$HF_R" handoff --mid-flight 'T2 is in its ready loop' --order 'T2, then T6'
expect_eq "W1 handoff exits 0" "0" "$RC"
expect_true "W1b …and writes the default file record/<wave>/handoff.md" test -s "$HF_F"
expect_eq "W2 every line in order: kind, sitrep head, machine lines, the five human lines, the safe line, the door" \
  "$HF_OPEN_SHAPE" "$(hf_shape "$HF_F")"
expect_eq "W3 line 1 is the kind line" "bionic-handoff/v1" "$(sed -n 1p "$HF_F")"
expect_eq "W4 the sitrep head is the last recorded Bottom line with its time (the sitrep verb's own line)" \
  "sitrep head: Bottom line (since 3:00 PM 2026-10-08)" "$(sed -n 2p "$HF_F")"
expect_eq "W4b …its first item" "- schedule holds at 1.2x (line 37)" "$(sed -n 3p "$HF_F")"
expect_eq "W4c …its second item" "- hypothesis: the gate sets the close" "$(sed -n 4p "$HF_F")"
expect_absent "W4d …and not the older Bottom line (W4b read the same file)" "an older item" "$(cat "$HF_F")"
expect_eq "W5 the sitrep line is byte-equal to sitrep --line (D13: one renderer)" "sitrep line: $HF_LINE" "$(sed -n 5p "$HF_F")"
HF_W="$(hf_label "$HF_F" written)"; HF_AT="${HF_W#written: }"
expect_regex "W6 written: is the ISO-UTC instant" '^written: [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' "$HF_W"
expect_eq "W7 plan: the bound plan, project-root-relative" "plan: $HF_PLAN_REL" "$(hf_label "$HF_F" plan)"
expect_eq "W8 branch: the working branch and its head" "branch: wave/01-fixture @ $HF_WORK" "$(hf_label "$HF_F" branch)"
expect_eq "W8b integration: the integration branch and its head" "integration: trunk @ $HF_INT" "$(hf_label "$HF_F" integration)"
expect_eq "W9 step: the plan's current:" "step: 4" "$(hf_label "$HF_F" step)"
expect_eq "W10 open rows: the count" "open rows (3):" "$(awk 'index($0, "open rows (") == 1 { print; exit }' "$HF_F")"
expect_contains "W10b …the active row T2 with its agent, worktree and status" "  - T2 · w-T2 · 01-T2 · active" "$(cat "$HF_F")"
expect_contains "W10c …a pending row with a worktree" "  - T6 · — · .worktrees/01-T6 · pending" "$(cat "$HF_F")"
expect_absent "W10d …not a pending row with none (T5; W10b read the same file)" "  - T5 ·" "$(cat "$HF_F")"
expect_eq "W11 last landed: by its time" "last landed: T4 2222222222222222222222222222222222222222 2026-10-08T10:30:00Z" "$(hf_label "$HF_F" 'last landed')"
expect_regex "W12 live writers: the count, with how it was verified" '^live writers \(1\): ' "$(awk 'index($0, "live writers (") == 1 { print; exit }' "$HF_F")"
expect_contains "W12b …each writer with its tree and current act (the roster's run line)" "  - w-T2 · 01-T2 · FINISHED rc=0 run=w-T2-x.test.sh" "$(cat "$HF_F")"
expect_eq "W13 last proof: the newest" "last proof: kind=review head=$HF_WORK at=2026-10-08T12:30:00Z" "$(hf_label "$HF_F" 'last proof')"
expect_eq "W14 patrol: not armed (no stamp for this session)" "patrol: not armed" "$(hf_label "$HF_F" patrol)"
expect_eq "W15 mid-flight: the flag's text" "mid-flight: T2 is in its ready loop" "$(hf_label "$HF_F" mid-flight)"
expect_eq "W15b order: the flag's text" "order: T2, then T6" "$(hf_label "$HF_F" order)"
expect_eq "W15c rulings: no flag and no previous file — the stub" "rulings: (to fill)" "$(hf_label "$HF_F" rulings)"
expect_eq "W15d lessons: the stub" "lessons: (to fill)" "$(hf_label "$HF_F" lessons)"
expect_eq "W15e risks: the stub" "risks: (to fill)" "$(hf_label "$HF_F" risks)"
expect_eq "W16 the safe line: no landing in flight" "safe to clear" "$(hf_safe "$HF_F")"
expect_eq "W17 the last line is the literal next command naming the file (D4: one door)" \
  "/bionic:canonical-sdlc $HF_DOOR" "$(tail -1 "$HF_F")"
expect_absent "W17b …no /bionic:resume anywhere in the file (W17 read the same file)" "/bionic:resume" "$(cat "$HF_F")"
expect_contains "W18 it says what it wrote" "handoff — written to $(cd "${HF_F%/*}" && pwd -P)/handoff.md" "$OUT"
# A missing line is a failure of W2: the shape extractor goes red on a planted file with one line cut.
grep -v '^step: ' "$HF_F" > "$TMPROOT/hf-cut"
expect_ne "W19 anti-vacuity: the shape extractor tells a file with the step line cut" "$HF_OPEN_SHAPE" "$(hf_shape "$TMPROOT/hf-cut")"
HF_FIRST_FILE="$(cat "$HF_F")"

# ============================================================
section "§CARRY: a second run with no flags carries the five human lines byte for byte; a flag replaces only its line (AC-3.1; D23)"
# ============================================================
HF_H1="$(hf_human "$HF_F")"
expect_eq "C1 precondition: the human-line extractor reads five lines" "5" "$(printf '%s\n' "$HF_H1" | grep -c .)"
sed 's/^written: .*/written: 2026-01-01T00:00:00Z/' "$HF_F" > "$HF_F.e" && mv "$HF_F.e" "$HF_F"
poke "$HF_R" handoff
expect_eq "C2 a second handoff with no flags exits 0" "0" "$RC"
expect_eq "C2b …the five human lines carried byte for byte" "$HF_H1" "$(hf_human "$HF_F")"
expect_eq "C2c …and the shape is the same" "$HF_OPEN_SHAPE" "$(hf_shape "$HF_F")"
expect_ne "C2d …written: is refreshed (an older instant planted before the run is gone)" "written: 2026-01-01T00:00:00Z" "$(hf_label "$HF_F" written)"
poke "$HF_R" handoff --risks 'the gate queue is long'
expect_eq "C3 a flag on a later run exits 0" "0" "$RC"
expect_eq "C3b …replaces its own line" "risks: the gate queue is long" "$(hf_label "$HF_F" risks)"
expect_eq "C3c …and only its line: the other four are as they were" \
  "$(printf '%s\n' "$HF_H1" | grep -v '^risks:')" "$(hf_human "$HF_F" | grep -v '^risks:')"
poke "$HF_R" handoff --lessons $'brief renders at the head\nre-render after every landing'
expect_eq "C4 a flag holding a line break exits 0" "0" "$RC"
expect_eq "C4b …its first line on the label" "lessons: brief renders at the head" "$(hf_label "$HF_F" lessons)"
expect_contains "C4c …its next line as an indented continuation" $'lessons: brief renders at the head\n  re-render after every landing' "$(cat "$HF_F")"
HF_H2="$(hf_human "$HF_F")"
poke "$HF_R" handoff
expect_eq "C5 a run with no flags carries the continuation line too" "$HF_H2" "$(hf_human "$HF_F")"
expect_eq "C5b …and the shape holds" "$HF_OPEN_SHAPE" "$(hf_shape "$HF_F")"
cp "$HF_F" "$TMPROOT/hf-before"
poke "$HF_R" handoff --risks
expect_eq "C6 a flag with no value is the usage error" "2" "$RC"
expect_true "C6b …and the file is untouched (cmp)" cmp -s "$TMPROOT/hf-before" "$HF_F"
poke "$HF_R" handoff --whatever 'x'
expect_eq "C7 an unknown flag is the usage error" "2" "$RC"
expect_true "C7b …and the file is untouched (cmp)" cmp -s "$TMPROOT/hf-before" "$HF_F"

# ============================================================
section "§POINTER: the plan's ## Handoff is the heading and one line handoff: <path> written <local time> (AC-3.1; D23)"
# ============================================================
HF_SEC="$(hf_section "$HF_P")"
expect_eq "P1 the section holds exactly one non-blank line" "1" "$(printf '%s\n' "$HF_SEC" | grep -c .)"
expect_regex "P1b …the pointer, in handoff_local_time's format" \
  "^handoff: $(printf '%s' "$HF_DOOR" | sed 's/\./\\./g') written [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2} P[DS]T$" \
  "$(printf '%s\n' "$HF_SEC" | grep .)"
expect_eq "P2 one ## Handoff heading in the plan" "1" "$(grep -c '^## Handoff' "$HF_P")"
expect_eq "P2b …placed before ## Not Doing" "## Not Doing" "$(awk '/^## Handoff[ \t]*$/ { f = 1; next } f && /^## / { print; exit }' "$HF_P")"
expect_absent "P2c …no machine line is left in the plan (P1b read the section)" "open rows" "$HF_SEC"
s34_gate "$HF_R"
expect_eq "P3 the plan with the pointer is admitted by the real gate" "0" "$GATE_RC"
s42_snap "$HF_R" "$HF_P"
poke "$HF_R" handoff .bionic/docs/record/wave-01-fixture/alt-handoff.md
expect_eq "P4 handoff <path> exits 0" "0" "$RC"
expect_true "P4b …writes the file at that path" test -s "$HF_R/.bionic/docs/record/wave-01-fixture/alt-handoff.md"
expect_eq "P4c …whose last line names it" "/bionic:canonical-sdlc .bionic/docs/record/wave-01-fixture/alt-handoff.md" \
  "$(tail -1 "$HF_R/.bionic/docs/record/wave-01-fixture/alt-handoff.md")"
expect_contains "P4d …and the pointer names it" "handoff: .bionic/docs/record/wave-01-fixture/alt-handoff.md written " "$(hf_section "$HF_P")"
expect_eq "P4e …the rest of the plan is as it was" "$(hf_outside "$TMPROOT/s42-before")" "$(hf_outside "$HF_P")"
expect_eq "P4f …and the human lines carried from the file the pointer named" "$HF_H2" \
  "$(hf_human "$HF_R/.bionic/docs/record/wave-01-fixture/alt-handoff.md")"
s42_snap "$HF_R" "$HF_P"
poke "$HF_R" handoff notes/elsewhere.md
expect_eq "P5 a path outside the docs root is refused" "2" "$RC"
expect_true "P5b …the plan is byte-identical (cmp)" cmp -s "$TMPROOT/s42-before" "$HF_P"
expect_false "P5c …and nothing is written there" test -e "$HF_R/notes/elsewhere.md"
poke "$HF_R" handoff "$HF_DOOR" "$HF_DOOR"
expect_eq "P6 two paths is the usage error" "2" "$RC"

# ============================================================
section "§SAFE: a ready in flight prints wait N minutes from the landing's remaining measured time; none prints safe to clear (AC-3.2; D23)"
# ============================================================
# The record: T1 and T4 landed through the queue in 20 and 40 minutes (landing-report's median 30.0m).
hf_world safe
hf_ev "ev=ready|row=T1|name=w-T1|commit=$HF_WORK|branch=wt/01-T1|tree=$HF_R/.worktrees/01-T1|suites=a.test.sh|debt=-|carrier=1:x|at=2026-10-08T10:00:00Z"
hf_ev "ev=published|row=T1|commit=$HF_WORK|kind=queue|by=-|why=-|at=2026-10-08T10:20:00Z"
hf_ev "ev=ready|row=T4|name=w-T4|commit=$HF_WORK|branch=wt/01-T4|tree=$HF_R/.worktrees/01-T4|suites=a.test.sh|debt=-|carrier=1:x|at=2026-10-08T11:00:00Z"
hf_ev "ev=published|row=T4|commit=$HF_WORK|kind=queue|by=-|why=-|at=2026-10-08T11:40:00Z"
cp "$HF_REC" "$TMPROOT/hf-rec-base"
hf_live
hf_ev "ev=ready|row=T2|name=w-T2|commit=$HF_WORK|branch=wt/01-T2|tree=$HF_R/01-T2|suites=a.test.sh|debt=-|carrier=$HF_CARRIER|at=$(hf_iso $((HF_NOW - 720)))"
poke "$HF_R" handoff
expect_eq "S1 a live ready, 12 minutes in, median 30.0m: handoff exits 0" "0" "$RC"
expect_regex "S1b …the safe line is wait 18 minutes (30 measured − 12 elapsed)" '^wait 18 minutes' "$(hf_safe "$HF_F")"
expect_contains "S1c …naming the landing row" "T2" "$(hf_safe "$HF_F")"
expect_absent "S2 …and never safe while it runs (S1b read the same line)" "safe to clear" "$(hf_safe "$HF_F")"
expect_eq "S2b …the shape holds with the wait form" "$HF_OPEN_SHAPE" "$(hf_shape "$HF_F")"
kill "$HF_PID" 2>/dev/null; wait "$HF_PID" 2>/dev/null
poke "$HF_R" handoff
expect_eq "S3 the ready's carrier is gone: safe to clear" "safe to clear" "$(hf_safe "$HF_F")"
# A live carrier whose entry has published is no landing in flight.
cp "$TMPROOT/hf-rec-base" "$HF_REC"; hf_live
hf_ev "ev=ready|row=T2|name=w-T2|commit=$HF_WORK|branch=wt/01-T2|tree=$HF_R/01-T2|suites=a.test.sh|debt=-|carrier=$HF_CARRIER|at=$(hf_iso $((HF_NOW - 720)))"
hf_ev "ev=published|row=T2|commit=$HF_WORK|kind=queue|by=-|why=-|at=$(hf_iso $((HF_NOW - 60)))"
poke "$HF_R" handoff
expect_eq "S4 a live carrier whose entry published: safe to clear" "safe to clear" "$(hf_safe "$HF_F")"
# The floor: a landing past its measured time still says wait, 1 minute.
cp "$TMPROOT/hf-rec-base" "$HF_REC"
hf_ev "ev=ready|row=T2|name=w-T2|commit=$HF_WORK|branch=wt/01-T2|tree=$HF_R/01-T2|suites=a.test.sh|debt=-|carrier=$HF_CARRIER|at=$(hf_iso $((HF_NOW - 7200)))"
poke "$HF_R" handoff
expect_regex "S5 a landing 120 minutes in against a 30.0m median: floor 1 minute" '^wait 1 minutes' "$(hf_safe "$HF_F")"
# The ceiling: the row's declared size (30) bounds a longer measured median (landings of 80 and 120 minutes).
{ printf 'line/v1|ev=ready|row=T1|name=w-T1|commit=%s|branch=wt/01-T1|tree=/x|suites=a.test.sh|debt=-|carrier=1:x|at=2026-10-08T10:00:00Z\n' "$HF_WORK"
  printf 'line/v1|ev=published|row=T1|commit=%s|kind=queue|by=-|why=-|at=2026-10-08T11:20:00Z\n' "$HF_WORK"
  printf 'line/v1|ev=ready|row=T4|name=w-T4|commit=%s|branch=wt/01-T4|tree=/x|suites=a.test.sh|debt=-|carrier=1:x|at=2026-10-08T12:00:00Z\n' "$HF_WORK"
  printf 'line/v1|ev=published|row=T4|commit=%s|kind=queue|by=-|why=-|at=2026-10-08T14:00:00Z\n' "$HF_WORK"
  printf 'line/v1|ev=ready|row=T2|name=w-T2|commit=%s|branch=wt/01-T2|tree=%s/01-T2|suites=a.test.sh|debt=-|carrier=%s|at=%s\n' "$HF_WORK" "$HF_R" "$HF_CARRIER" "$(hf_iso $((HF_NOW - 720)))"
} > "$HF_REC"
poke "$HF_R" handoff
expect_regex "S6 a 100.0m median, 12 minutes in, a 30-minute row: the declared size caps it" '^wait 30 minutes' "$(hf_safe "$HF_F")"
kill "$HF_PID" 2>/dev/null; wait "$HF_PID" 2>/dev/null

# ============================================================
section "§CLOSED: handoff on a delivered plan writes the closed form instead of refusing; the pointer stays in the plan (AC-3.5; D23)"
# ============================================================
hf_world closed
poke "$HF_R" handoff --rulings 'D1 ruled "1"'
expect_eq "D0 precondition: the open handoff carries a rulings line" 'rulings: D1 ruled "1"' "$(hf_label "$HF_F" rulings)"
awk '
  /^current: 4$/ { print "current: 9"; next }
  /^- T1: landed at record\/T1.md$/ { print "- Step 9: delivered: 2026-10-08T13:00Z wave-01-fixture 9.9.9 — closed by close-out.sh"; print; next }
  { print }' "$HF_P" > "$HF_P.d" && mv "$HF_P.d" "$HF_P"
s42_snap "$HF_R" "$HF_P"
poke "$HF_R" handoff
expect_eq "D1 handoff on a delivered plan exits 0" "0" "$RC"
expect_absent "D1b …and does not refuse" "REFUSED" "$OUT"
expect_contains "D1c …saying it wrote the closed form" "closed form" "$OUT"
expect_eq "D2 line 1 is the kind line" "bionic-handoff/v1" "$(sed -n 1p "$HF_F")"
expect_eq "D2b line 2 is the closed form" \
  "resume point: NONE — DELIVERED at 2026-10-08T13:00Z; trunk @ $(git -C "$HF_R" rev-parse --short trunk)." "$(sed -n 2p "$HF_F")"
expect_eq "D2c the closed file's lines in order" "$HF_CLOSED_SHAPE" "$(hf_shape "$HF_F")"
expect_eq "D2d the human lines are kept" 'rulings: D1 ruled "1"' "$(hf_label "$HF_F" rulings)"
expect_eq "D2e the last line is still the door" "/bionic:canonical-sdlc $HF_DOOR" "$(tail -1 "$HF_F")"
expect_contains "D3 the plan keeps the pointer" "handoff: $HF_DOOR written " "$(hf_section "$HF_P")"
expect_eq "D3b …and only the pointer" "1" "$(hf_section "$HF_P" | grep -c .)"

# ============================================================
section "§READERS: adopt's STALE note and launch-sync's HANDOFF-STALE read the file's written instant; a wave-37 plan's in-place section reads as before (D23)"
# ============================================================
hf_world readers no
poke "$HF_R" handoff
expect_eq "R0 precondition: the handoff is written" "0" "$RC"
expect_eq "R0b …with no sitrep log, the head says so" "sitrep head: (none recorded)" "$(sed -n 2p "$HF_F")"
# The file's instant is moved, so only a reader of the FILE can tell the dispatch from the handoff.
sed 's/^written: .*/written: 2026-01-01T00:00:00Z/' "$HF_F" > "$HF_F.e" && mv "$HF_F.e" "$HF_F"
new_roster "$HF_R"
add_row "$HF_R" name=w-after status=intended agent_id= plan="$HF_P" launched_at=2026-06-01T00:00:00Z
poke "$HF_R" adopt --report-only
expect_contains "R1 adopt judges the file's instant: a dispatch after it is STALE" \
  "handoff written 2026-01-01T00:00:00Z — STALE: 1 dispatch(es) of this plan since (w-after)" "$OUT"
s42_snap "$HF_R" "$HF_P"
poke "$HF_R" launch-sync
expect_eq "R2 launch-sync exits 0 with a later dispatch to mark" "0" "$RC"
expect_regex "R2b the file's safe line reads STALE, naming the dispatch" \
  '^STALE — dispatched after this handoff was written: w-after at .*\(2026-06-01T00:00:00Z\)' "$(hf_safe "$HF_F")"
expect_contains "R2c …and launch-sync says so, naming the file" "HANDOFF-STALE — $HF_DOOR" "$OUT"
expect_true "R2d …the plan is byte-identical: the pointer stands (cmp)" cmp -s "$TMPROOT/s42-before" "$HF_P"
expect_eq "R2e …the door is still the last line" "/bionic:canonical-sdlc $HF_DOOR" "$(tail -1 "$HF_F")"
cp "$HF_F" "$TMPROOT/hf-marked"
poke "$HF_R" launch-sync
expect_true "R3 a second launch-sync with nothing new leaves the file byte-identical (cmp)" cmp -s "$TMPROOT/hf-marked" "$HF_F"
poke "$HF_R" handoff
expect_eq "R4 handoff written again clears the mark" "safe to clear" "$(hf_safe "$HF_F")"
sed 's/^written: .*/written: 2027-01-01T00:00:00Z/' "$HF_F" > "$HF_F.e" && mv "$HF_F.e" "$HF_F"
poke "$HF_R" adopt --report-only
expect_contains "R5 a dispatch before the file's instant: adopt reads the handoff current" \
  "handoff written 2027-01-01T00:00:00Z — current: no dispatch of this plan since" "$OUT"
expect_absent "R5b …not STALE (R1 read STALE through the same verb)" "STALE" "$OUT"
cp "$HF_F" "$TMPROOT/hf-current"
poke "$HF_R" launch-sync
expect_true "R5c …and launch-sync marks nothing (cmp)" cmp -s "$TMPROOT/hf-current" "$HF_F"
# A wave-37 plan: the old in-place section, no pointer. Both readers judge its written: as before.
awk '
  /^## Handoff[ \t]*$/ { print; print ""; print "written: 2026-01-01T00:00:00Z"; print "- safe to exit: yes"; print "- safe to /clear: yes"; print ""; h = 1; next }
  h && /^## / { h = 0 }
  h { next }
  { print }' "$HF_P" > "$HF_P.o" && mv "$HF_P.o" "$HF_P"
s42_snap "$HF_R" "$HF_P"
poke "$HF_R" adopt --report-only
expect_contains "R6 a wave-37 in-place section: adopt still reads its written:" \
  "handoff written 2026-01-01T00:00:00Z — STALE: 1 dispatch(es) of this plan since (w-after)" "$OUT"
poke "$HF_R" launch-sync
expect_contains "R6b …and launch-sync marks the plan's safety line as before" \
  "- safe to exit: no — STALE: dispatched after this handoff was written: w-after at " "$(hf_section "$HF_P")"

finish
