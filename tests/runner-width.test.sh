#!/bin/bash
# tests/runner-width.test.sh — tests/run.sh takes its job width from the machine's own
# pressure rung (wave-roster-lifecycle S9, spec AC-15, R4), read against the share's room,
# gate_width = floor(share × cores ÷ 100) (wave-32 T2; D1, Section 6).
#
# WHAT CHANGED. `JOBS="${BIONIC_TEST_JOBS:-8}"` — a literal a caller had to notice and set —
# became `pressure_sample` then `JOBS="$(pressure_level "${BIONIC_TEST_JOBS_CEILING:-8}")"`:
# one fresh reading, then the median-smoothed rung over resources.sh's ring, read against a
# ceiling. `BIONIC_TEST_JOBS` is retired as an input; a caller who still sets it is told once,
# on stderr, and ignored.
#
# THE ONLY SAFE WAY TO DRIVE THIS is `tests/run.sh --dry-run` (added by this same task):
# it reads the rung the ring already carries and prints it, without launching the
# 40-plus-suite roster a real run would. Every case below drives the REAL runner script
# this way; nothing here reimplements the width computation.
#
# --dry-run SAMPLES NOTHING (S25, critic K-4 option 2: a dry run writes nothing to the
# ring — Section 2 pins this). Every fixture below therefore pre-seeds the ring with
# however many lines the case needs BEFORE calling `dry_run` — most seed the SAME
# reading twice, which reads identically whether or not a live sample ever joins them,
# so removing the runner's own dry-run sample changed none of these cases' answers.
# `BIONIC_PROBE_FREE_PCT` / `_SWAP_PCT` / `_LOAD_1M` are still pinned on every call: they
# no longer feed a dry-run sample, but Section 2's ordinary-path case (the one path that
# still samples) reads them, and leaving them unset there would make that one case a
# weather report.
#
# FIXTURE DISCIPLINE (Fail-closed constants idiom, resources.sh:154). `BIONIC_PRESSURE_RING`
# always points under this suite's own mktemp root — never the real
# `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/bionic/pressure.ring` — and `BIONIC_NOW_EPOCH` pins the
# clock so every ring line this suite writes lands inside the smoothing window regardless of
# wall-clock time. A case is not left to the real, unpinned state of the machine running
# this suite.
#
# Usage: bash tests/runner-width.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"

RUN="${BIONIC_SCRIPTS_DIR}/tests/run.sh"

TMPROOT="$(mktemp -d "${TMPDIR:-/tmp}/runner-width-test.XXXXXX")"
trap 'rm -rf "$TMPROOT"' EXIT

NOW=1700000000

# THE SHARE AND THE CORES ARE THIS SUITE'S OWN (wave-32 T2; D1). The width a run takes is now
# the share's room, gate_width = floor(share × cores ÷ 100), read through the gate's one formula,
# and the pressure rung reads against it (capped by BIONIC_TEST_JOBS_CEILING when one is named).
# So every drive below runs under a planted home holding the share file (CLAUDE_CONFIG_DIR, which
# also keeps the gate store an ordinary run asks under this suite's root) and a planted 8-core
# probe. Sections 1-5 plant share 100, whose room on 8 cores is 8, the ceiling they were written
# against; Section 6 plants the machine's own default, 92.
RW_HOME="$TMPROOT/home"
mkdir -p "$RW_HOME/bionic"
rw_share() { printf '%s\n' "$1" > "$RW_HOME/bionic/share"; }
rw_share 100
RW_PIN=(CLAUDE_CONFIG_DIR="$RW_HOME" BIONIC_PROBE_CORES=8)

# ring_of <path> <epoch> <sample>... — rewrite a ring with one line per sample, all at <epoch>
ring_of() {
  local path="$1" t="$2"; shift 2
  mkdir -p "$(dirname "$path")"
  : > "$path"
  local s
  for s in "$@"; do printf '%s|%s\n' "$t" "$s" >> "$path"; done
}

# dry_run <ring> <probe-sample> [ceiling-env-assignment]
# Runs the REAL tests/run.sh --dry-run with the ring, clock and probe pinned so its own
# internal pressure_sample call agrees with the band the pre-seeded ring already carries.
#
# THE CEILING KNOB IS SCRUBBED FIRST, ALWAYS (A-71). Case (c) asserts the DEFAULT ceiling,
# which is only the default when nothing in the environment names one — and this suite runs
# under a floor that exports `BIONIC_TEST_JOBS_CEILING=1` to every child, which made 1c read
# `JOBS=1` and call the runner broken. `env -u` deletes the inherited value; the optional
# assignment that follows it still wins, because `env` applies its options before its
# assignments. A case that wants a ceiling passes one; a case that wants the default now
# gets the default no matter who launched the suite.
DRY_OUT=""; DRY_ERR=""; DRY_ST=0
dry_run() {
  local ring="$1" sample="$2" ceiling_env="${3:-}"
  local f s l c
  IFS='|' read -r f s l c <<<"$sample"
  DRY_OUT=$(cd "$BIONIC_SCRIPTS_DIR" && \
    env -u BIONIC_TEST_JOBS_CEILING -u BIONIC_GATE_DIR "${RW_PIN[@]}" \
        BIONIC_PRESSURE_RING="$ring" BIONIC_NOW_EPOCH="$NOW" \
        BIONIC_PROBE_FREE_PCT="$f" BIONIC_PROBE_SWAP_PCT="$s" BIONIC_PROBE_LOAD_1M="$l" \
        ${ceiling_env:+BIONIC_TEST_JOBS_CEILING="$ceiling_env"} \
        bash "$RUN" --dry-run 2>"$TMPROOT/.err")
  DRY_ST=$?
  DRY_ERR=$(cat "$TMPROOT/.err")
}

# The plan's band table (S7/§I), reused verbatim: free|swap|load|cores.
S_CLEAR='44|69|1.6|8'
S_CRIT='10|50|1|8'

section "Section 1: --dry-run prints JOBS=<n> and exits before any suite runs"

# (a) a critical ring at ceiling 8 -> the quartered rung, 2.
RING_A="$TMPROOT/a/pressure.ring"
ring_of "$RING_A" "$NOW" "$S_CRIT" "$S_CRIT"
dry_run "$RING_A" "$S_CRIT" 8
expect_eq   "1a a critical ring at ceiling 8 prints JOBS=2" "0" "$DRY_ST"
expect_contains "1a …exactly that line" "JOBS=2" "$DRY_OUT"

# (b) a clear ring at ceiling 8 -> the full ceiling, 8.
RING_B="$TMPROOT/b/pressure.ring"
ring_of "$RING_B" "$NOW" "$S_CLEAR" "$S_CLEAR"
dry_run "$RING_B" "$S_CLEAR" 8
expect_contains "1b a clear ring at ceiling 8 prints JOBS=8" "JOBS=8" "$DRY_OUT"

# (c) no BIONIC_TEST_JOBS_CEILING at all -> the old default of 8 is the ceiling.
RING_C="$TMPROOT/c/pressure.ring"
ring_of "$RING_C" "$NOW" "$S_CLEAR" "$S_CLEAR"
dry_run "$RING_C" "$S_CLEAR"
expect_contains "1c no ceiling var: the default ceiling is 8" "JOBS=8" "$DRY_OUT"
# Sharper than (c) alone: a critical ring with no ceiling var quarters exactly 8, not some
# other unstated default.
RING_C2="$TMPROOT/c2/pressure.ring"
ring_of "$RING_C2" "$NOW" "$S_CRIT" "$S_CRIT"
dry_run "$RING_C2" "$S_CRIT"
expect_contains "1c …confirmed against a critical ring too (quarters 8, not another default)" \
  "JOBS=2" "$DRY_OUT"

echo
section "Section 2: --dry-run writes NOTHING (S25, critic K-4 option 2)"
#
# RATIFIED: `tests/run.sh --dry-run` is a user-facing surface, and the obligation that
# rides with it is that a dry run writes nothing. Before S25 the runner sampled the
# machine's pressure UNCONDITIONALLY, before the --dry-run early exit, so every dry run
# quietly appended one line to the ring documented at :131 as "print the job width and
# exit; run nothing" — nothing meant nothing, except one write. §2a proves the ring is
# byte-identical afterwards (count AND checksum — a rewrite that happened to keep the
# same line count would slip past a bare `wc -l`). §2b is the paired POSITIVE: the
# ORDINARY (non-dry) path this is an exception to must still sample exactly once, or the
# exception would have quietly swallowed the rule (AC-15) along with the bug.

ring_fingerprint() {  # <ring> -> "<byte count> <sha256>", cheap non-vacuity for "unchanged"
  printf '%s %s' "$(wc -c < "$1" | tr -d ' ')" "$(shasum "$1" | awk '{print $1}')"
}

RING_D="$TMPROOT/d/pressure.ring"
ring_of "$RING_D" "$NOW" "$S_CLEAR" "$S_CLEAR"
BEFORE_FP="$(ring_fingerprint "$RING_D")"
dry_run "$RING_D" "$S_CLEAR" 8
AFTER_FP="$(ring_fingerprint "$RING_D")"
expect_contains "2a --dry-run still prints the width" "JOBS=8" "$DRY_OUT"
expect_eq "2a …a dry run leaves the ring byte-identical (bytes+sha unchanged)" \
  "$BEFORE_FP" "$AFTER_FP"

# §2b THE PAIRED POSITIVE. Driving the real (non-dry, non-serial) path directly would
# launch this repo's whole roster — including this very suite, and cross-gate-agreement
# and fresh-home, which also drive --dry-run — so instead this copies the REAL
# tests/run.sh, byte for byte, into a scratch tree whose tests/ holds ONE two-line stub
# suite and nothing else. The run costs that one trivial suite, while the width
# computation this case exists to observe runs — and samples — long before the queue is
# even built, so the copy proves the same thing a real run would without paying for one.
#
# WHY A STUB AND NOT AN EMPTY tests/ (fixit 1.5.1). The roster is the directory now, and a
# runner asked to gate on an empty one REFUSES rather than reporting green over nothing —
# which would stop this drive before it ever sampled. The stub carries the pinned shebang
# the roster wall asks for; this tree has no framework, so that half of the wall is inert
# here and the stub needs nothing else.
ORD_TREE="$TMPROOT/ordinary"
mkdir -p "$ORD_TREE/tests/lib" "$ORD_TREE/payload/scripts/lib"
cp "${BIONIC_SCRIPTS_DIR}/tests/run.sh" "$ORD_TREE/tests/run.sh"
cp "${BIONIC_SCRIPTS_DIR}/tests/lib/resolve-roots.sh" "$ORD_TREE/tests/lib/resolve-roots.sh"
cp "${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/"*.sh "$ORD_TREE/payload/scripts/lib/" 2>/dev/null
printf '#!/bin/bash\nexit 0\n' > "$ORD_TREE/tests/stub.test.sh"
expect_eq "2b the scratch runner is the shipped one, byte for byte (not vacuous)" "yes" \
  "$(cmp -s "${BIONIC_SCRIPTS_DIR}/tests/run.sh" "$ORD_TREE/tests/run.sh" && echo yes || echo no)"

RING_D2="$TMPROOT/d2/pressure.ring"
ring_of "$RING_D2" "$NOW" "$S_CLEAR"
BEFORE_LINES2=$(wc -l < "$RING_D2" | tr -d ' ')
( cd "$ORD_TREE" && env -u BIONIC_GATE_DIR "${RW_PIN[@]}" BIONIC_PRESSURE_RING="$RING_D2" BIONIC_NOW_EPOCH="$NOW" \
      BIONIC_PROBE_FREE_PCT=44 BIONIC_PROBE_SWAP_PCT=69 BIONIC_PROBE_LOAD_1M=1.6 \
      BIONIC_TEST_JOBS_CEILING=8 \
      bash tests/run.sh >/dev/null 2>&1 )
AFTER_LINES2=$(wc -l < "$RING_D2" | tr -d ' ')
expect_eq "2b the ordinary path still appends exactly one sample (AC-15 intact)" \
  "$((BEFORE_LINES2 + 1))" "$AFTER_LINES2"

echo
section "Section 3: BIONIC_TEST_JOBS is retired"

RING_E="$TMPROOT/e/pressure.ring"
ring_of "$RING_E" "$NOW" "$S_CLEAR"
DRY_OUT=""; DRY_ERR=""
DRY_OUT=$(cd "$BIONIC_SCRIPTS_DIR" && \
  env -u BIONIC_GATE_DIR "${RW_PIN[@]}" BIONIC_PRESSURE_RING="$RING_E" BIONIC_NOW_EPOCH="$NOW" \
      BIONIC_PROBE_FREE_PCT=44 BIONIC_PROBE_SWAP_PCT=69 BIONIC_PROBE_LOAD_1M=1.6 \
      BIONIC_TEST_JOBS=4 BIONIC_TEST_JOBS_CEILING=8 \
      bash "$RUN" --dry-run 2>"$TMPROOT/.err3")
DRY_ERR=$(cat "$TMPROOT/.err3")
expect_contains "3a a caller who still sets BIONIC_TEST_JOBS is told once, on stderr" \
  "BIONIC_TEST_JOBS is retired" "$DRY_ERR"
expect_contains "3b …and the value is ignored: width still comes from the rung (clear -> 8, not 4)" \
  "JOBS=8" "$DRY_OUT"

# A caller who never set it at all gets no notice.
RING_F="$TMPROOT/f/pressure.ring"
ring_of "$RING_F" "$NOW" "$S_CLEAR"
dry_run "$RING_F" "$S_CLEAR" 8
expect_absent "3c no notice when BIONIC_TEST_JOBS was never set" "BIONIC_TEST_JOBS is retired" "$DRY_ERR"

echo
section "Section 5: a garbage ceiling falls back, it does not kill the run (C-6)"

# `pressure_level` refuses a ceiling that is not a positive integer with exit 2 and prints
# nothing on stdout. `:-8` covers UNSET and nothing else, so `JOBS` came out empty and
# `xargs -P ""` aborted the whole run — and the wave's own briefs instruct agents to set
# this variable, so a typo is the likely way to meet it.
RING_G="$TMPROOT/g/pressure.ring"
for BAD_CEIL in 0 eight -1 "3 4"; do
  ring_of "$RING_G" "$NOW" "$S_CLEAR" "$S_CLEAR"
  dry_run "$RING_G" "$S_CLEAR" "$BAD_CEIL"
  expect_eq "5 ceiling [$BAD_CEIL]: the runner still exits 0" "0" "$DRY_ST"
  expect_contains "5 ceiling [$BAD_CEIL]: falls back to the default width" "JOBS=8" "$DRY_OUT"
  expect_contains "5 ceiling [$BAD_CEIL]: and the refusal is on stderr to explain it" \
    "pressure_level: need <ceiling> as a positive integer" "$DRY_ERR"
done

# The fallback is a FALLBACK, not a floor: a VALID ceiling still decides the width.
ring_of "$RING_G" "$NOW" "$S_CLEAR" "$S_CLEAR"
dry_run "$RING_G" "$S_CLEAR" 3
expect_contains "5 a valid ceiling of 3 is still honoured (not replaced by 8)" "JOBS=3" "$DRY_OUT"

echo
section "Section 6: the width is the share's room, read through the gate's one formula (wave-32 T2; D1)"
#
# THE CLAIM. A run's width is gate_width (payload/scripts/lib/gate.sh): floor(share × cores ÷ 100),
# 7 at share 92 on 8 cores. The runner keeps no number of its own; BIONIC_TEST_JOBS_CEILING is a
# cap UNDER the width, never above it; the pressure rung still narrows a strained machine. The
# expected width is read from the library under the same pins, so the runner and the gate are held
# to one formula rather than to a literal both could drift from.
rw_width() {  # the gate's own width under this suite's pins
  env "${RW_PIN[@]}" bash -c '. "$1/payload/scripts/lib/gate.sh" 2>/dev/null; gate_width' _ "$BIONIC_SCRIPTS_DIR"
}
RING_W="$TMPROOT/w/pressure.ring"
rw_share 92
RW_W92="$(rw_width)"
expect_eq "6a the formula's width at share 92 on 8 cores is 7 (the readback is real)" "7" "$RW_W92"
ring_of "$RING_W" "$NOW" "$S_CLEAR" "$S_CLEAR"
dry_run "$RING_W" "$S_CLEAR"
expect_contains "6b no ceiling named: a clear ring runs at the formula's width" "JOBS=$RW_W92" "$DRY_OUT"
expect_absent "6c …not the old literal default of 8" "JOBS=8" "$DRY_OUT"
ring_of "$RING_W" "$NOW" "$S_CLEAR" "$S_CLEAR"
dry_run "$RING_W" "$S_CLEAR" 8
expect_contains "6d a ceiling above the width is a cap, not a raise: ceiling 8 at share 92 is the width" \
  "JOBS=$RW_W92" "$DRY_OUT"
ring_of "$RING_W" "$NOW" "$S_CLEAR" "$S_CLEAR"
dry_run "$RING_W" "$S_CLEAR" 3
expect_contains "6e a ceiling under the width still decides: 3" "JOBS=3" "$DRY_OUT"
rw_share 50
RW_W50="$(rw_width)"
expect_eq "6f the formula's width at share 50 on 8 cores is 4" "4" "$RW_W50"
ring_of "$RING_W" "$NOW" "$S_CLEAR" "$S_CLEAR"
dry_run "$RING_W" "$S_CLEAR"
expect_contains "6g …and the runner follows the share: JOBS=4" "JOBS=$RW_W50" "$DRY_OUT"
ring_of "$RING_W" "$NOW" "$S_CLEAR" "$S_CLEAR"
dry_run "$RING_W" "$S_CLEAR" "eight"
expect_contains "6h a garbage ceiling falls back to the width, not to 8" "JOBS=$RW_W50" "$DRY_OUT"
rw_share 100

echo
section "§NO-VOID nothing passes or fails by the clock: no solo drain, no settle, no VOID (wave-35 T2; D11, AC-2.1)"
#
# THE CLAIM. A suite carrying `# runner: solo` is an ordinary suite: the dry run lists it in the one
# launch order, a whole run starts it with no wait for a settled load, and its verdict is its exit
# code. Nothing reports VOID. `booked.sh --quiet` is an option the shim does not know (usage, 2), and
# `BIONIC_QUIET=1` is read by nobody: the shim asks `work` and runs at once whatever the load reads.
# FAILS WHEN: a suite ends VOID, or a settle wait or a retry runs.
#
# FIXTURE FIDELITY. A scratch tree carrying the shipped runner byte for byte and this tree's
# libraries (Section 2b's shape: no framework, so its plain suites gate on their exit codes). The
# load the old settle read is planted far over any line, 99, through BIONIC_LOAD_NOW_FILE, and the
# old ceiling knob is set to 1 second, so the code this section retires would have waited, then
# printed VOID; the drive names its own gate store and an idle planted machine, so the whole run's
# one admission never waits on this machine.
NV="$TMPROOT/novoid"
NV_MARKS="$TMPROOT/novoid-marks"; NV_LOAD="$TMPROOT/novoid-load"
mkdir -p "$NV/tests/lib" "$NV/payload/scripts/lib" "$NV_MARKS"
cp "${BIONIC_SCRIPTS_DIR}/tests/run.sh" "$NV/tests/run.sh"
cp "${BIONIC_SCRIPTS_DIR}/tests/lib/resolve-roots.sh" "$NV/tests/lib/resolve-roots.sh"
cp "${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/"*.sh "$NV/payload/scripts/lib/" 2>/dev/null
# aaa-marked: the marker verbatim, green. b-plain: no marker, green.
printf '#!/bin/bash\n# runner: solo\necho run >> "$NV_MARKS/marked.runs"\nexit 0\n' > "$NV/tests/aaa-marked.test.sh"
printf '#!/bin/bash\necho run >> "$NV_MARKS/plain.runs"\nexit 0\n' > "$NV/tests/b-plain.test.sh"
expect_eq "NV.0 the fixture's marked suite carries the marker verbatim within its first 30 lines" "1" \
  "$(head -n 30 "$NV/tests/aaa-marked.test.sh" | grep -cE '^# runner: solo[[:space:]]*$')"
NV_OUT=""; NV_RC=0
nv_drive() {  # [runner args...] — the scratch runner on the planted load, old ceiling NV_MAXW (1 s); NV_OUT, NV_RC
  NV_OUT="$( cd "$NV" && env -u BIONIC_GATE_DIR -u BIONIC_GATE_ADMIT -u BIONIC_GATE_AGENT -u BIONIC_TEST_JOBS_CEILING \
      "${RW_PIN[@]}" NV_MARKS="$NV_MARKS" NV_LOAD="$NV_LOAD" BIONIC_GATE_DIR="$TMPROOT/novoid-gate" BIONIC_GATE_POLL=0.1 \
      BIONIC_PROBE_USED_PCT=10 BIONIC_PROBE_BUSY_CORES=0 BIONIC_PROBE_TOTAL_MB=8192 \
      BIONIC_LOAD_NOW_FILE="$NV_LOAD" BIONIC_SETTLE_MAX_WAIT="${NV_MAXW:-1}" \
      BIONIC_PRESSURE_RING="$TMPROOT/novoid-ring" BIONIC_NOW_EPOCH="$NOW" \
      BIONIC_PROBE_FREE_PCT=44 BIONIC_PROBE_SWAP_PCT=0 BIONIC_PROBE_LOAD_1M=0.1 \
      bash tests/run.sh "$@" 2>&1 )"
  NV_RC=$?
}
nv_line() { printf '%s\n' "$NV_OUT" | grep -F "  $1 "; }
nv_runs() { awk 'END { print NR + 0 }' "$NV_MARKS/$1.runs" 2>/dev/null || echo 0; }

# The dry run: one launch order, the marked suite in it, no `solo:` listing.
printf '99\n' > "$NV_LOAD"
nv_drive --dry-run
NV_ORDER="$(printf '%s\n' "$NV_OUT" | awk -F'\t' 'NF == 2 { print $1 }')"
expect_eq "NV.1 the dry run's launch order holds both suites, the marked one among them" \
  "aaa-marked.test.sh b-plain.test.sh" "$(printf '%s\n' "$NV_ORDER" | sort | paste -sd' ' -)"
expect_eq "NV.2 …and lists no suite as solo (NV.1 is the positive on the same output)" "" \
  "$(printf '%s\n' "$NV_OUT" | grep '^solo:')"

# The whole run, the load at 99 throughout.
rm -f "$NV_MARKS"/*; rm -rf "$TMPROOT/novoid-gate"; printf '99\n' > "$NV_LOAD"
nv_drive
expect_eq "NV.3 a whole run with the marked suite, the load at 99, is green" "0" "$NV_RC"
expect_contains "NV.4 the marked suite's verdict is its exit code: PASS" "✓ PASS" "$(nv_line aaa-marked.test.sh)"
expect_eq "NV.5 …it ran once" "1" "$(nv_runs marked)"
expect_absent "NV.6 nothing in the run reads VOID (NV.4 is the positive on the same output)" "VOID" "$NV_OUT"
expect_absent "NV.7 …no Void: line" "Void:" "$NV_OUT"
expect_absent "NV.8 …and no wait for the load to settle" "waiting for the load" "$NV_OUT"
expect_contains "NV.9 the run calls itself green, as a run with no failure is" "All gating suites green" "$NV_OUT"

# booked.sh: --quiet is unknown; BIONIC_QUIET=1 is read by nobody.
NV_BK="${BIONIC_SCRIPTS_DIR}/payload/scripts/booked.sh"
NV_BKD="$TMPROOT/novoid-booked"; mkdir -p "$NV_BKD"
nv_booked() {  # [env assignments...] -- <booked args...>; NV_OUT, NV_RC; run outside any checkout
  local pre=()
  while [ "$#" -gt 0 ] && [ "$1" != -- ]; do pre+=("$1"); shift; done
  shift
  NV_OUT="$( cd "$NV_BKD" && env -u BIONIC_GATE_ADMIT -u BIONIC_GATE_AGENT -u BIONIC_QUIET \
      "${RW_PIN[@]}" BIONIC_GATE_DIR="$TMPROOT/novoid-bgate" BIONIC_GATE_POLL=0.1 \
      BIONIC_PROBE_USED_PCT=10 BIONIC_PROBE_BUSY_CORES=0 BIONIC_PROBE_TOTAL_MB=8192 \
      BIONIC_LOAD_NOW_FILE="$NV_LOAD" BIONIC_SETTLE_MAX_WAIT=1 ${pre[@]+"${pre[@]}"} \
      bash "$NV_BK" "$@" 2>&1 )"
  NV_RC=$?
}
nv_kinds() {  # the kinds of the requests in the booked drives' store, sorted, space-joined
  sed -n 's/^kind=//p' "$TMPROOT/novoid-bgate"/requests/[0-9]* 2>/dev/null | sort | paste -sd' ' -
}
rm -f "$NV_BKD"/*; rm -rf "$TMPROOT/novoid-bgate"
nv_booked -- -- "touch $NV_BKD/plain.ran"
expect_eq "NV.10 control: the shim runs a command, rc 0" "0 yes" \
  "$NV_RC $([ -f "$NV_BKD/plain.ran" ] && echo yes || echo no)"
nv_booked -- --quiet -- "touch $NV_BKD/quiet.ran"
expect_eq "NV.11 --quiet is an option the shim does not know: usage, 2, and the command never ran" "2 no" \
  "$NV_RC $([ -f "$NV_BKD/quiet.ran" ] && echo yes || echo no)"
expect_contains "NV.12 …the usage line says so (NV.10 ran the same shim)" "booked: usage:" "$NV_OUT"
rm -rf "$TMPROOT/novoid-bgate"
nv_booked BIONIC_QUIET=1 -- -- "touch $NV_BKD/envq.ran"
expect_eq "NV.13 BIONIC_QUIET=1 is read by nobody: the command runs at once, the load at 99, rc 0" "0 yes" \
  "$NV_RC $([ -f "$NV_BKD/envq.ran" ] && echo yes || echo no)"
expect_absent "NV.14 …and nothing says void (NV.13 is the positive on the same drive)" "void" "$NV_OUT"
expect_eq "NV.15 …asking the gate as work, never for the whole machine" "work" "$(nv_kinds)"

echo
section "§NO-RETRY a suite red once stays red in the log, run once (wave-35 T2; D11, AC-2.4)"
#
# THE CLAIM. A suite that fails is reported failed, from the one run it had: the runner never runs
# it again, whatever the load did while it ran. FAILS WHEN: the runner re-runs a failed suite.
#
# FIXTURE FIDELITY. The suite carries the marker the retired retry keyed on, starts on a load of 0,
# raises it to 99 during its first run and lowers it again two seconds later, inside the old
# ceiling of ten, which is the shape the retired code read as "disturbed" and re-ran
# (runner-roster §11 (d), retired with it). The
# second run, if one came, would pass: so a retry would turn this red suite green, and the run
# count and the verdict both say whether one happened.
printf '#!/bin/bash\n# runner: solo\necho run >> "$NV_MARKS/red.runs"\nn="$(awk "END { print NR + 0 }" "$NV_MARKS/red.runs")"\nif [ "$n" -eq 1 ]; then printf "99\\n" > "$NV_LOAD"; ( sleep 2; printf "0\\n" > "$NV_LOAD" ) >/dev/null 2>&1 & exit 1; fi\nexit 0\n' \
  > "$NV/tests/aaa-red.test.sh"
rm -f "$NV_MARKS"/*; rm -rf "$TMPROOT/novoid-gate"; printf '0\n' > "$NV_LOAD"
NV_MAXW=10 nv_drive
NV_RED_RUNS="$(nv_runs red)"
expect_eq "NR.1 the run with a red suite is red" "1" "$NV_RC"
expect_eq "NR.2 …the red suite ran once" "1" "$NV_RED_RUNS"
expect_contains "NR.3 …its verdict line reads FAIL" "✗ FAIL" "$(nv_line aaa-red.test.sh)"
expect_eq "NR.4 …and the Gating line counts it failed once beside the two green suites" \
  "Gating: 2 passed, 1 failed" "$(printf '%s\n' "$NV_OUT" | grep '^Gating: ')"
expect_contains "NR.5 …it is named under Failed:" "- aaa-red.test.sh" "$NV_OUT"
expect_absent "NR.6 …and nothing said it was retried (NR.3 is the positive on the same output)" "retrying" "$NV_OUT"
rm -f "$NV/tests/aaa-red.test.sh"

finish
