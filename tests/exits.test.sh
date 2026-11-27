#!/bin/bash
# tests/exits.test.sh — an ordinary answer exits 0, and every caller that needs the answer still gets it.
#
# §CALLERS. A command the gate did not admit ran nothing, and it says so with exit 0: the suite door, the shim
# (booked.sh) and regression-run. A caller that needs to know names a file in BIONIC_NOT_ADMITTED, and such a command
# appends one line to it. Driven here: the shim over the door, in the foreground, declared meant to fail and detached,
# stamps the run as not run (rc=75), which the proof reader never reads green; the tick's detached whole run, its line
# built by the tick's own builder, records no run when regression-run was not admitted, and is told apart from a run
# that wrote its log and from one that ran nothing; the poker's reader of the note gives the code of a run not run.
#
# §ORDINARY. The list of ordinary answers (lib/refuse.sh `refuse_ordinary`) is the one place that says which answers
# exit 0, and each command of it exits 0 on its answer and prints what it printed before. Driven here: the checked
# advance (`current <N> --check`) answering would refuse, beside its would-advance control and the advance itself, which
# still refuses non-zero in the same words; the judge (`judge <N>...`) answering a step that would refuse, which exits 0
# while its closing line keeps the step's code, the one a card reads; and the list's own exit for a code it does not
# hold, which stays that code.
#
# THE WORLD. A scratch git project carrying this tree's door, its framework, its payload libraries and the shim, with
# three stub suites: x, green; f2, red; f1, whose output holds the shell's own refusal of a process, which the door counts as a
# suite the machine did not run (the same not-admitted end a budget refusal takes, with no budget to plant). The gate's
# store, the share and every machine reading are pinned under this suite's own temp root.
#
# THE RUN §ORDINARY ASKS. A second scratch git project on main alone, its run bound to this suite's session through the
# real binder (tests/lib/bound-marker.sh) at step 7 of a plan_fixture page, whose header names a working branch,
# wave/01-fixture, that names no commit there: the advance to 8 is refused on it before any fact is read, and the
# check of step 7, the step the run stands at, would advance with nothing to judge. The poker is this tree's own.
#
# FIXTURE FIDELITY. The door, the shim, the libraries, the tick's builder and the poker's reader are this tree's own
# files, copied or sourced in place. The poker the tick's line calls is a STUB: it answers regression-run as the real
# verb answers each of the three ends (not admitted, ran and logged, ran nothing), and logs a proof-add call.
#
# ANTI-VACUITY. Each "not run" reading sits beside a green control read by the same extractor in the same world.
#
# Usage: bash tests/exits.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"
. "$(dirname "$0")/lib/plan-fixture.sh"
. "$(dirname "$0")/lib/bound-marker.sh"

REPO="$BIONIC_SCRIPTS_DIR"

TMPROOT="$(mktemp -d "${TMPDIR:-/tmp}/exits-test.XXXXXX")"
TMPROOT="$(cd "$TMPROOT" && pwd -P)"
trap 'rm -rf "$TMPROOT"' EXIT

export BIONIC_PLUGINS_DIR="$TMPROOT/no-plugins"
mkdir -p "$BIONIC_PLUGINS_DIR" "$TMPROOT/config/bionic" "$TMPROOT/gate/cost"
printf '80\n' > "$TMPROOT/config/bionic/share"
printf '1:0.1:1:1700000000\n' > "$TMPROOT/gate/cost/seed"
EX_ENV=(-u BIONIC_GATE_ADMIT -u BIONIC_GATE_AGENT -u BIONIC_GATE_LANDING -u BIONIC_NOT_ADMITTED -u CLAUDE_CODE_SESSION_ID
  "CLAUDE_CONFIG_DIR=$TMPROOT/config" "BIONIC_GATE_DIR=$TMPROOT/gate" BIONIC_GATE_POLL=0.1 BIONIC_RUN_POLL=0.2
  "BIONIC_PRESSURE_RING=$TMPROOT/pressure.ring" BIONIC_PROBE_USED_PCT=10 BIONIC_PROBE_BUSY_CORES=0
  BIONIC_PROBE_BUSY_CORES_5M=0 BIONIC_PROBE_CORES=8 BIONIC_PROBE_TOTAL_MB=8192 BIONIC_PROBE_FREE_PCT=44
  BIONIC_PROBE_SWAP_PCT=0 BIONIC_PROBE_LOAD_1M=0.1 BIONIC_PROBE_FREE_MB=8192)

# ---------- the world ----------
W="$TMPROOT/world"
mkdir -p "$W/tests/lib" "$W/payload/scripts/lib" "$W/.bionic/tmp"
cp "$REPO/tests/run.sh" "$W/tests/run.sh"
cp "$REPO/tests/lib/resolve-roots.sh" "$REPO/tests/lib/assert.sh" "$W/tests/lib/"
cp "$REPO"/payload/scripts/lib/*.sh "$W/payload/scripts/lib/"
cp "$REPO/payload/scripts/booked.sh" "$W/payload/scripts/booked.sh"
printf '#!/bin/bash\n. "$(dirname "$0")/lib/resolve-roots.sh"; . "$(dirname "$0")/lib/assert.sh"\nexpect_eq "x runs" 1 1\nfinish\n' > "$W/tests/x.test.sh"
RF='fork: Resource temporarily unavailable'
printf '#!/bin/bash\n. "$(dirname "$0")/lib/resolve-roots.sh"; . "$(dirname "$0")/lib/assert.sh"\necho "tests/f1.test.sh: %s" >&2\nexit 1\nfinish\n' "$RF" > "$W/tests/f1.test.sh"
printf '#!/bin/bash\n. "$(dirname "$0")/lib/resolve-roots.sh"; . "$(dirname "$0")/lib/assert.sh"\necho "FAIL: red" >&2\nexit 1\nfinish\n' > "$W/tests/f2.test.sh"
( cd "$W" && git init -q . && git config user.name "Dana Fixture" && git config user.email d@example.com \
  && printf '.bionic/\n' > .gitignore && git add -A && git commit -qm world ) >/dev/null 2>&1
WH="$(git -C "$W" rev-parse HEAD)"
STAMPS="$(git -C "$W" rev-parse --absolute-git-dir)/bionic-stamps"

ex_booked() {  # <shim options...> -- <command> -> OUT (stdout and stderr), RC: the shim in the world
  OUT="$(cd "$W" && env "${EX_ENV[@]}" bash payload/scripts/booked.sh "$@" 2>&1)"; RC=$?
}
ex_stamp() {  # -> the rc= and suites= of the world's last stamp, as <rc>:<suites>
  tail -n 1 "$STAMPS" 2>/dev/null | tr '|' '\n' | awk -F= '$1 == "rc" { r = $2 } $1 == "suites" { s = $2 } END { print r ":" s }'
}
ex_records() {  # <suite key> -> the proof reader's R lines for the key at the world's head, as their verdicts
  bash -c '. "$1/roots.sh" && . "$1/proof.sh" && _proof_records "$2"' _ "$REPO/payload/scripts/lib" "$W" 2>/dev/null \
    | awk -F'\t' -v h="$WH" -v k="$1" '$1 == "R" && $3 == h && $4 == k { printf "%s%s", (n++ ? "," : ""), $5 } END { print "" }'
}
ex_wait_rc() {  # <log> -> 0 once <log>.rc exists, within 30 s
  local i=0
  while [ ! -s "$1.rc" ] && [ "$i" -lt 150 ]; do i=$((i + 1)); sleep 0.2; done
  [ -s "$1.rc" ]
}

# ============================================================
section "§CALLERS: a run the gate did not admit exits 0, and every caller that needs the answer reads it, never the exit"
# ============================================================
# fails-when: the shim stamps a run the door did not admit with the door's 0, so the proof reader reads it green; the
# shim's console takes the not-admitted end through the meant-to-fail inversion; the detached caller exits 75, or the
# detached run's records lose the 75; the tick's line records a run regression-run was not admitted to as a run, or as
# one that ran nothing; the poker's reader takes the door's 0 for a run.

# The control first: a green suite through the shim is stamped green and read green.
ex_booked --suites x.test.sh --runner -- "bash tests/run.sh --only x.test.sh"
expect_eq "C0 control: a green suite through the shim exits 0, stamped rc=0 with its suite" "0|0:x.test.sh" "$RC|$(ex_stamp)"
expect_eq "C0b …and the proof reader reads it green at the head" "green" "$(ex_records x.test.sh)"

ex_booked --suites f1.test.sh --runner -- "bash tests/run.sh --only f1.test.sh"
expect_eq "C1 a suite the door did not run, through the shim: exit 0, the door's REFUSED line shown" "0|REFUSED" \
  "$RC|$(printf '%s\n' "$OUT" | awk '$1 == "f1.test.sh" { print $3; exit }')"
[ "$RC" = 0 ] || printf '%s\n' "$OUT" | sed 's/^/      the shim said: /'
expect_eq "C1b …stamped as not run, rc=75, with its suite" "75:f1.test.sh" "$(ex_stamp)"
expect_eq "C1c …and the proof reader reads no run of it at the head, beside x's green (C0b)" "" "$(ex_records f1.test.sh)"

ex_booked --expect red --suites f1.test.sh --runner -- "bash tests/run.sh --only f1.test.sh"
expect_eq "C2 declared meant to fail and not run: exit 0, the REFUSED line shown, stamped rc=75" "0|REFUSED|75:f1.test.sh" \
  "$RC|$(printf '%s\n' "$OUT" | awk '$1 == "f1.test.sh" { print $3; exit }')|$(ex_stamp)"
expect_eq "C2b …never said to have failed as declared" "0" "$(printf '%s\n' "$OUT" | grep -c 'failed as declared' || true)"
ex_booked --expect red --suites f2.test.sh -- "exit 1"
expect_eq "C2c control: a declared run that failed is said to have failed as declared, in the same output" "0|1" \
  "$RC|$(printf '%s\n' "$OUT" | grep -c 'failed as declared' || true)"

ex_booked --detach --agent ex --suites f1.test.sh --runner -- "bash tests/run.sh --only f1.test.sh"
EX_LOG="$(printf '%s\n' "$OUT" | sed -n 's/^booked: started .* log=\([^ ]*\) .*/\1/p' | head -n 1)"
expect_nonempty "C3-pre the detached run started and named its log" "$EX_LOG"
expect_eq "C3 detached, the caller exits 0; the run's end and its log's last line keep 75" "0|75|rc=75" \
  "$RC|$(cat "${EX_LOG:-$TMPROOT/none}.rc" 2>/dev/null)|$(tail -n 1 "${EX_LOG:-$TMPROOT/none}" 2>/dev/null)"
ex_booked --detach --agent ex --suites x.test.sh --runner -- "bash tests/run.sh --only x.test.sh"
EX_LOG="$(printf '%s\n' "$OUT" | sed -n 's/^booked: started .* log=\([^ ]*\) .*/\1/p' | head -n 1)"
expect_eq "C3b control: detached and green, the caller exits 0 and the run's end is 0" "0|0" \
  "$RC|$(cat "${EX_LOG:-$TMPROOT/none}.rc" 2>/dev/null)"

# THE TICK'S LINE, built by the tick's builder, run as the tick runs it: detached through the shim, as run.sh.
STUB="$TMPROOT/poker.sh"
cat > "$STUB" <<'STUBPOKER'
#!/bin/bash
# The poker, stubbed: regression-run answers as the real verb's three ends; proof-add is logged.
case "$1" in
  regression-run)
    case "$(cat "$EX_MODE")" in
      refused)
        [ -z "${BIONIC_NOT_ADMITTED:-}" ] || printf 'regression-run: not admitted\n' >> "$BIONIC_NOT_ADMITTED"
        printf 'poker: regression-run — the gate did not admit the whole run, so nothing ran and no log was written; run regression-run again.\n' >&2
        exit 0 ;;
      ran) printf 'head=x dirty=0\nrc=0\n' > "$EX_RUNLOG"; exit 0 ;;
      *) printf 'poker: REFUSED — nothing was run.\n' >&2; exit 1 ;;
    esac ;;
  proof-add) printf '%s\n' "$*" >> "$EX_PROOFS"; exit 0 ;;
esac
exit 2
STUBPOKER
export EX_MODE="$TMPROOT/mode" EX_RUNLOG="$W/.bionic/run.log" EX_PROOFS="$TMPROOT/proofs"
EX_CMD="$(. "$REPO/hooks/poker/tick.sh" && tick_run_cmd "$W" "$STUB" "" regression "$EX_RUNLOG" record/run.log)"
expect_contains "C4-pre the tick's builder gives the line: regression-run as the tick, then proof-add over its log" \
  "regression-run --starter tick; rc=\$?" "$EX_CMD"
ex_tick() {  # <mode> -> RC, EX_LOG and EX_TICK (<caller rc>|<run's end>|<stamp>|<proof-adds>)
  printf '%s\n' "$1" > "$EX_MODE"; rm -f "$EX_RUNLOG"; : > "$EX_PROOFS"
  OUT="$(cd "$W" && env "${EX_ENV[@]}" EX_MODE="$EX_MODE" EX_RUNLOG="$EX_RUNLOG" EX_PROOFS="$EX_PROOFS" \
    bash payload/scripts/booked.sh --detach --agent "tick-$1" --suites run.sh -- "$EX_CMD" 2>&1)"; RC=$?
  EX_LOG="$(printf '%s\n' "$OUT" | sed -n 's/^booked: started .* log=\([^ ]*\) .*/\1/p' | head -n 1)"
  ex_wait_rc "${EX_LOG:-$TMPROOT/none}"
  EX_TICK="$RC|$(cat "${EX_LOG:-$TMPROOT/none}.rc" 2>/dev/null)|$(ex_stamp)|$(awk 'END { print NR }' "$EX_PROOFS")"
}
ex_tick ran
expect_eq "C4 control: the run wrote its log: the end is 0, the stamp green, proof-add called once" "0|0|0:run.sh|1" "$EX_TICK"
expect_eq "C4b …and the proof reader reads a whole run, green, at the head" "green" "$(ex_records '*' | cut -d, -f1)"
ex_tick refused
expect_eq "C5 regression-run not admitted (exit 0, its note written): the end is 75, the stamp 75, no proof-add" \
  "0|75|75:run.sh|0" "$EX_TICK"
expect_contains "C5b …its line shown in the run's log" "the gate did not admit the whole run" "$(cat "${EX_LOG:-$TMPROOT/none}" 2>/dev/null)"
ex_tick nothing
expect_eq "C6 regression-run refused, nothing run and no note: the end is 69, no proof-add" "69|69|69:run.sh|0" "$EX_TICK"

# THE POKER'S READER, as regression-run and proof-add inherited read the door through it.
ex_note_rc() {  # <suite> -> the reader's code for the door's run of it, given the reader's own note
  ( cd "$W" && env "${EX_ENV[@]}" bash -c '. "$1/hooks/poker/proof.sh" && n="$(poker_note_make)" || exit 9
    BIONIC_NOT_ADMITTED="$n" bash tests/run.sh --only "$2" >/dev/null 2>&1
    poker_note_said "$n" "$?"' _ "$REPO" "$1" ) 2>/dev/null
}
expect_eq "C7 the poker's reader: the door that ran nothing is read 75 (it exits 0) · a red run 1 · a green run 0" "75 1 0" \
  "$(ex_note_rc f1.test.sh) $(ex_note_rc f2.test.sh) $(ex_note_rc x.test.sh)"

# ============================================================
section "§ORDINARY: each answer the list holds exits 0 and prints what it printed before; the code it keeps stays in its words"
# ============================================================
# fails-when: the checked advance exits non-zero on would refuse, or prints other first words; the advance itself stops
# refusing non-zero; the judge exits non-zero for a step that would refuse, or its closing line loses the step's code;
# the list loses the check's or the judge's answer, or maps a code it does not hold to 0.
ex_list() {  # <expression over the list's fields> -> what it prints, the library this tree's own
  bash -c '. "$1/refuse.sh" >/dev/null 2>&1 || exit 9; refuse_ordinary | awk -F"|" "$2"' _ "$REPO/payload/scripts/lib" "$1" 2>/dev/null
}
ex_ordexit() {  # <key> <code>... -> the list's exit for each, space-joined
  bash -c '. "$1/refuse.sh" >/dev/null 2>&1 || exit 9; k="$2"; shift 2; for c in "$@"; do printf "%s " "$(refuse_ordinary_exit "$k" "$c")"; done' \
    _ "$REPO/payload/scripts/lib" "$@" 2>/dev/null
}
expect_eq "O0 the list holds the checked advance's answer and the judge's, each with the code it keeps and its words" \
  "check:1:would refuse judge:1:would refuse" "$(ex_list '$1 == "check" || $1 == "judge" { printf "%s%s:%s:%s", (n++ ? " " : ""), $1, $3, $4 }')"
expect_eq "O0b …every row of it five fields with a code, and the list not empty" "yes|0" \
  "$([ "$(ex_list 'END { print NR }')" -gt 0 ] && echo yes)|$(ex_list 'NF != 5 || $3 !~ /^[0-9]+$/ { n++ } END { print n + 0 }')"
expect_eq "O0c the list's exit: the check's 1 and the judge's 1 are 0, the landing's 75 is 0; a 2, a landing's 1 (RED) and a 0 stay" \
  "0 2 0 |0 2 |0 1 " "$(ex_ordexit check 1 2 0)|$(ex_ordexit judge 1 2)|$(ex_ordexit ready 75 1)"

EX_SID=0e1d2c3b-4a59-4687-9a6b-5c4d3e2f1a0b
O="$TMPROOT/ordinary"; mkdir -p "$O/.bionic/tmp" "$TMPROOT/ohome" "$TMPROOT/ocfg"
( cd "$O" && git init -q . && git config user.name "Dana Fixture" && git config user.email d@example.com \
  && printf '.bionic/\n' > .gitignore && git add -A && git commit -qm base && git branch -M main ) >/dev/null 2>&1
: > "$O/.bionic/tmp/engaged-$EX_SID.state"
OP="$(plan_fixture --current 7 "$O/.bionic/docs/plans/epic-99-fixture/wave-01-fixture.plan.md" wave)"
bound_marker "$O" "$EX_SID" "$OP" >/dev/null 2>&1
ex_poke() {  # <verb args...> -> OUT (both streams), RC: this tree's poker in the run's root, as the bound session
  OUT="$(cd "$O" && env "${EX_ENV[@]}" HOME="$TMPROOT/ohome" CLAUDE_CONFIG_DIR="$TMPROOT/ocfg" CLAUDE_PROJECT_DIR= \
    CLAUDE_CODE_SESSION_ID="$EX_SID" bash "$REPO/hooks/session-poker.sh" "$@" 2>&1)"; RC=$?
}
ex_poke current 7 --check
expect_eq "O1 control: the check of the step the run stands at would advance (exit 0), saying so first" \
  "0|poker: current 7 --check: would advance" "$RC|$(printf '%s\n' "$OUT" | head -n 1)"
ex_poke current 8 --check; EX_CK="$OUT"
expect_eq "O2 the check that would refuse exits 0, its first line the verdict it printed before" \
  "0|poker: current 8 --check: would refuse" "$RC|$(printf '%s\n' "$EX_CK" | head -n 1)"
[ "$RC" = 0 ] || printf '%s\n' "$EX_CK" | sed 's/^/      the check said: /'
ex_poke current 8
expect_eq "O2b …the advance itself still refuses (exit 1), in the words the check printed under its verdict" \
  "1|$OUT" "$RC|$(printf '%s\n' "$EX_CK" | tail -n +2)"
expect_contains "O2c …which name what refuses it: the working branch names no commit" "names no commit here" "$OUT"
ex_poke judge 7 8
expect_eq "O3 the judge asked for a step that would advance and one that would refuse exits 0, each block closed with its code" \
  "0|poker: judged 7 exit 0|poker: judged 8 exit 1" \
  "$RC|$(printf '%s\n' "$OUT" | /usr/bin/grep '^poker: judged ' | paste -sd'|' -)"
expect_contains "O3b …the step that would refuse said so as the check does" "poker: current 8 --check: would refuse" "$OUT"

finish
