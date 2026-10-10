#!/bin/bash
# tests/refuse.test.sh — payload/scripts/lib/refuse.sh: the refusal object, its one
# renderer, and the channel table it renders by (epic-22 wave-01 task 11, REQ-E1;
# AC-E1.3 and AC-E1.5; ADR-002).
#
# WHAT IT OWNS. Three questions no static pin can answer, each driven through a REAL
# call site — a scratch hook that sources the shipped library and calls `refuse` — so
# nothing here is measuring a test-only re-implementation of the renderer:
#
#   §1  the channel table is DATA, ten fields per mode, and its cells are the ones
#       record/wave-01-plugin-only/e1-measurement.md measured — including the cells
#       that say `unverified`, which are the point rather than a gap.
#   §2  AC-E1.3. In each refusal mode the user stream is one line in the criterion's
#       own shape, and a malformed refusal (a seven-word fix, a two-line fact, an
#       unknown mode) is refused loudly at the call site instead of truncated.
#   §3  AC-E1.5. `BIONIC_WALL_VERBOSE=1` puts `detail` on the user stream, in every
#       mode, and its absence keeps it off the modes that have somewhere else to put it.
#   §4  the model stream's shape per mode: `deny` carries `detail` in
#       `permissionDecisionReason`, `block` in `reason`, and `exit2` carries the verdict
#       and the detail on the one wire it has for both readers, so what the model reads
#       there is what the reader reads (ADR-030).
#   §5  the fail-closed properties. `refuse` exits and never returns to a call site
#       that could then wave the action through, and every path out of it — including
#       every authoring error — leaves a non-zero status or a blocking JSON verdict.
#   §6  ADR-030, with `BIONIC_WALL_VERBOSE` UNSET — the state a real refusal runs in and
#       the one no other detail assertion in this tree is taken in: an `exit2` wall's
#       computed detail reaches the reader, at most twelve lines of it plus a `+N more`.
#
# THE SHAPES ARE ASSERTED LITERALLY, NOT READ BACK OUT OF THE TABLE. §2's exit2 rows say
# what the stream IS — a verdict line, then the detail behind it — as a literal
# expectation, never as `refuse_channel exit2 detail_to_user`. A suite that asks the
# library what to expect and then checks the library did it agrees with itself for any
# value of the cell, which is the one thing these rows exist to make impossible.
#
# THE CELL HAS MOVED TWICE, AND BOTH TIMES THESE ROWS WENT RED AND WERE EDITED ON PURPOSE.
# Task 12 flipped it to `no` under ruling D-1 ("a refusal is a sentence with a pointer",
# 2026-09-07) and task 13 re-authored them; epic-23 wave-16 T4 flipped it back to `yes`
# under ADR-030 ("a refusal prints what it knows", 2026-09-19) and re-authored them again.
# A pin that had read the cell would have gone green through both.
#
# EVERY ASSERTION HAS A MUTANT. Each section drives a scratch copy of refuse.sh with
# exactly one guard removed and requires the copy to fail where the shipped file
# passes. The mutants are built with `anchor` first, so a refactor that renames the
# guarded line makes the mutation fail loudly rather than silently mutate nothing and
# leave the arm passing over an unmutated file.
#
# HERMETIC. A mktemp sandbox, no HOME writes, no network, no plugin registry read.
# The scratch hook sources the library by absolute path rather than through the
# loader block: the loader's own behaviour is tests/loader.test.sh's, and reaching
# refuse.sh through `BIONIC_LIB_WANT` is task 13's edit to 21 hooks, not this file's.
#
# Usage: bash tests/refuse.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
LIB_DIR="$REPO_ROOT/payload/scripts/lib"
LIB="$LIB_DIR/refuse.sh"

SANDBOX="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/refuse-test.XXXXXX")" && pwd -P)"
cleanup() { rm -rf "$SANDBOX"; }
trap cleanup EXIT

# THE CRITERION'S OWN REGEX, spelled once. AC-E1.3, plan §Eval design row E1/format.
USER_LINE_RE='^bionic: [a-z-]+ refused — .+ \(.{1,40}\)$'

# A REAL CALL SITE. The scratch hook is what a migrated wall will be: source the
# library, build the object, call `refuse`. The line after the call is the fail-open
# regression `refuse` exists to make impossible — if `refuse` ever returns, this hook
# prints FELL-THROUGH and exits 0, and §5 reads for exactly that.
WALL="$SANDBOX/wall.sh"
cat > "$WALL" <<'WALL_EOF'
#!/bin/bash
set -uo pipefail
. "$1" || exit 9
shift
refuse "$@"
echo "FELL-THROUGH" >&2
exit 0
WALL_EOF

# drive <lib> <refuse args...> — runs the scratch hook and splits the two streams.
# stdout and stderr go to their own files, never merged: the whole subject of this
# suite is which stream carries what, and a `2>&1` capture would answer it by erasing
# the question.
#
# THE KNOB IS PASSED TO AN EXTERNAL COMMAND, NEVER AS A PREFIX ON THIS FUNCTION.
# `VAR=1 some_function` leaves VAR set in the caller's shell under bash 3.2, so a
# verbose row would silently arm every row after it; `VAR=1 bash ...` is scoped to
# the child and nothing leaks. Every drive passes the value explicitly, empty by
# default, which also masks an inherited BIONIC_WALL_VERBOSE from the environment.
#
# THE STRICT SETTING IS PASSED THE SAME WAY (T47). `DRV_STRICT` is the value `drive_v` hands
# the child as BIONIC_REFUSE_STRICT: `1` by default, because sections 1-6 assert the library
# as the suites see it, strict, where an over-wide line refuses the call. §T47 sets it to
# empty (a hook as a user runs it) or `UNSET` (the variable absent) around ONE drive and
# restores it, and the child never inherits the runner's value either way.
DRV_STRICT=1
DRV_LC=""
DRV_RC=0; DRV_OUT=""; DRV_ERR=""; DRV_ERR_LINES=0; DRV_ERR_1=""
drive_v() {
  local v="$1" lib="$2"; shift 2
  if [ "$DRV_STRICT" = "UNSET" ]; then
    env -u BIONIC_REFUSE_STRICT ${DRV_LC:+LC_ALL="$DRV_LC"} BIONIC_WALL_VERBOSE="$v" \
      bash "$WALL" "$lib" "$@" >"$SANDBOX/.out" 2>"$SANDBOX/.err"
  else
    env BIONIC_REFUSE_STRICT="$DRV_STRICT" ${DRV_LC:+LC_ALL="$DRV_LC"} BIONIC_WALL_VERBOSE="$v" \
      bash "$WALL" "$lib" "$@" >"$SANDBOX/.out" 2>"$SANDBOX/.err"
  fi
  DRV_RC=$?
  DRV_OUT="$(cat "$SANDBOX/.out")"
  DRV_ERR="$(cat "$SANDBOX/.err")"
  DRV_ERR_LINES="$(wc -l <"$SANDBOX/.err" | tr -d ' ')"
  DRV_ERR_1="$(sed -n '1p' "$SANDBOX/.err")"
}
drive() { drive_v "" "$@"; }

# THE FIXTURE REFUSAL, one object reused everywhere so a stream comparison is between
# two renderings of the same thing. The detail deliberately carries a double quote, a
# backslash and two newlines — §4 escapes it into JSON and parses the result back.
FX_VERB="run-arm"
FX_FACT="tests/run.sh is not on this task's budget"
FX_FIX="add it to Suites:"
FX_DETAIL='The wall reads the plan brief'"'"'s `Suites:` line and nothing else.
A path-qualified "run.sh" token counts; a bare name does not.
Widen the budget with a C:\task brief, then re-dispatch.'

# THE SEVEN-WORD ARMS GET THEIR OWN, SHORT FACT, and this is a finding rather than a
# convenience. With FX_FACT the seven-word fix pushes the whole line to 103 columns,
# so the LINE budget fires first and the word budget is never reached — the mutant
# that removes the word guard still gets refused, by the other guard, and the arm
# reads green while proving nothing. Two guards that overlap on a fixture leave the
# narrower one unmeasured. This fact keeps the line at 86 columns so the word count
# is the only thing that can refuse it.
FX_FACT_SHORT="the run arm has no budget"
FX_FIX_7="add it to the Suites budget line"

# THE MUTANT DIRECTORY. refuse.sh soft-sources width.sh from its OWN directory, so a
# copy has to land beside a width.sh or it is testing a source failure instead of a
# removed guard. It is a real copy of the shipped width.sh, not a stub: the column
# budget the renderer enforces is that file's number.
MUT_DIR="$SANDBOX/lib"
mkdir -p "$MUT_DIR"
cp "$LIB_DIR/width.sh" "$MUT_DIR/width.sh"

# mutant <name> <sed-expr> <anchor-substring> — sets MUT_PATH to a scratch copy of the
# shipped library with one guard removed. `anchor` runs FIRST: a mutation whose
# pattern no longer matches would leave an unmutated copy and an arm that passes over
# the shipped file while claiming to have broken it.
#
# IT SETS A VARIABLE AND DOES NOT PRINT THE PATH. `anchor` reports through the
# framework's `ok`, which writes to stdout, so a `MUT="$(mutant …)"` capture swallows
# the PASS line into the path and every arm below sources a filename with a test
# report in it — which fails, but for the wrong reason and while still reading as a
# real mutation result.
MUT_PATH=""
mutant() {
  # SEPARATE STATEMENTS, and not one `local` with four assignments: `local a=1 b=$a`
  # creates every name as an unset local FIRST and then assigns, so `$name` in the
  # fourth word expands to the unset local and `set -u` kills the function — silently,
  # inside a command substitution, leaving an empty path the arms below then source.
  local name="$1" expr="$2" pat="$3"
  local dst="$MUT_DIR/$name.sh"
  anchor "$LIB" "$pat" 1
  sed -E "$expr" "$LIB" > "$dst"
  MUT_PATH="$dst"
}

# ============================================================
section "1 — the channel table is data, and every cell is the measurement's"
# ============================================================
#
# WHY THE CELLS ARE PINNED BY VALUE. The table is the only thing in the tree that
# says what a Claude Code hook emission mode does, and it is quoted from a
# measurement that cost a task. A cell edited to a plausible guess — most likely
# turning an `unverified` into a `yes` because the guess feels safe — would be
# invisible, and every later reader would treat the guess as measured. The
# `user_interactive` rows are the ones this protects: task 12's attended run
# (e1-measurement.md §D-2) measured the three BLOCKING modes and replaced their
# cells; the two non-blocking modes were never driven interactively and still say
# `unverified`, which is a gap named rather than a guess written.

expect_true "1a refuse.sh is on disk and parses" bash -n "$LIB"

TBL_FIELDS="$(bash -c '. "$1"; printf "%s\n" "$BIONIC_REFUSE_TABLE"' _ "$LIB" | awk -F'|' '{print NF}' | sort -u | tr '\n' ' ')"
expect_eq "1b every table row carries exactly ten fields" "10 " "$TBL_FIELDS"

TBL_MODES="$(bash -c '. "$1"; printf "%s\n" "$BIONIC_REFUSE_TABLE"' _ "$LIB" | awk -F'|' '{print $1}' | tr '\n' ' ')"
expect_eq "1c the five measured modes are all present, in measurement order" \
  "exit2 deny systemmessage block additionalcontext " "$TBL_MODES"

cell() {  # <mode> <field> -> the cell, resolved by the library in a child shell
  bash -c '. "$1"; refuse_channel "$2" "$3"' _ "$LIB" "$1" "$2" 2>/dev/null
}

# (a) THE THREE REFUSAL CHANNELS. Each blocks, each was measured to deliver its
# payload to the model in full.
for _m in exit2 deny block; do
  expect_eq "1d $_m is a refusal channel" "yes" "$(cell "$_m" refusal)"
  expect_eq "1e …and it blocks" "yes" "$(cell "$_m" blocks)"
done
expect_eq "1f refuse_modes lists exactly those three" "exit2 deny block " \
  "$(bash -c '. "$1"; refuse_modes' _ "$LIB" | tr '\n' ' ')"

# (b) THE TWO THAT ARE NOT. `systemMessage` reached only a stream-json informational
# event and `additionalContext` reached nothing at all (measurement modes 3 and 5,
# plan A-13). They are in the table so a later reader sees why they are not options.
for _m in systemmessage additionalcontext; do
  expect_eq "1g $_m is NOT a refusal channel" "no" "$(cell "$_m" refusal)"
  expect_eq "1h …and does not block" "no" "$(cell "$_m" blocks)"
  expect_eq "1i …and its detail reaches the model nowhere (model_only=no)" "no" "$(cell "$_m" model_only)"
done

# (c) THE MEASURED CELLS, by value.
for _m in exit2 deny systemmessage block additionalcontext; do
  expect_eq "1j $_m: the headless terminal showed nothing" "none" "$(cell "$_m" user_headless)"
  expect_regex "1l $_m: the source cell names the measurement row it is quoted from" \
    '^e1-measurement\.md channel table, mode [1-5]( \+ D-2)?$' "$(cell "$_m" source)"
done

# THE INTERACTIVE CELLS, filled by task 12's attended run (e1-measurement.md §D-2,
# F-D2-1..3) for the three blocking modes and still `unverified` for the two that
# were never driven live. Pinned by a phrase each, not by the whole cell: the phrase
# is the finding, and a cell rewritten to say something else about the same mode
# should go red here.
expect_contains "1k1 exit2: the interactive cell carries D-2's red-paint finding" \
  "painted in red" "$(cell exit2 user_interactive)"
expect_contains "1k2 exit2: …and the Bash collapse that hides it" \
  "Ran N shell commands" "$(cell exit2 user_interactive)"
expect_contains "1k3 deny: the interactive cell says the raw text never painted" \
  "nothing raw" "$(cell deny user_interactive)"
expect_contains "1k4 block: the interactive cell carries F-D2-2, that the command RAN" \
  "the command RAN" "$(cell block user_interactive)"
for _m in exit2 deny block; do
  expect_ne "1k5 $_m: the interactive cell is no longer the placeholder" \
    "unverified" "$(cell "$_m" user_interactive)"
  expect_contains "1k6 $_m: …and its source cell says D-2 is where it came from" \
    "D-2" "$(cell "$_m" source)"
done
for _m in systemmessage additionalcontext; do
  expect_eq "1k7 $_m: never driven interactively, so still unverified and not guessed" \
    "unverified" "$(cell "$_m" user_interactive)"
done
expect_eq "1m deny is model-only: the reason rides JSON, the terminal showed nothing" \
  "yes" "$(cell deny model_only)"
expect_eq "1n block is model-only, on PreToolUse and on Stop alike" \
  "yes" "$(cell block model_only)"
expect_eq "1o exit2 is NOT model-only: one wire carries both halves" \
  "no" "$(cell exit2 model_only)"

# (d) FIELD 9, the switch ADR-030 moved. Asserted by value so the ruling is a
# deliberate edit here and not a silent library change.
expect_eq "1p exit2 DOES put detail on the user stream — ADR-030 flipped this cell back" \
  "yes" "$(cell exit2 detail_to_user)"
expect_eq "1q deny does not: it has a model-only channel" "no" "$(cell deny detail_to_user)"
expect_eq "1r block does not, for the same reason" "no" "$(cell block detail_to_user)"

# (e) AN UNKNOWN MODE OR FIELD IS AN ERROR, silently, and NOT an empty cell that a
# caller could read as "no".
expect_false "1s an unknown mode exits 1" bash -c '. "$1"; refuse_channel nosuchmode refusal' _ "$LIB"
expect_false "1t an unknown field exits 1" bash -c '. "$1"; refuse_channel exit2 nosuchfield' _ "$LIB"

# ============================================================
section "2 — AC-E1.3: the user stream is one line, in the criterion's shape"
# ============================================================
#
# THE CRITERION: `bionic: <verb> refused — <fact> (<fix ≤ 6 words>)`, one line.
# fails-when: two lines, or a fix over six words. Both halves are driven below, and
# both have a mutant.
#
# THE THREE MODES AGREE ON THE VERDICT AND NOT ON WHAT FOLLOWS IT. `deny` and `block`
# have a model-only channel, so their user stream is one line and the detail has somewhere
# else to be. `exit2` has ONE wire for both halves: ruling D-1 spent it on the line alone
# and ADR-030 spends it on the line plus the bounded detail, because a detail that reaches
# neither reader is a fault the wall already diagnosed and then withheld. Either way the
# VERDICT is one line in the criterion's shape, which is what AC-E1.3 asks. Each is
# spelled out here rather than derived from the table.

# --- (a) deny and block: exactly one line on the user stream. ---
for _m in deny block; do
  drive "$LIB" "$_m" "$FX_VERB" "$FX_FACT" "$FX_FIX" "$FX_DETAIL"
  expect_eq "2a $_m: the user stream is exactly one line" "1" "$DRV_ERR_LINES"
  expect_regex "2b $_m: …and it matches AC-E1.3's shape" "$USER_LINE_RE" "$DRV_ERR_1"
  expect_eq "2c $_m: …spelled from the object's four fields" \
    "bionic: $FX_VERB refused — $FX_FACT ($FX_FIX)" "$DRV_ERR_1"
  expect_absent "2d $_m: the detail is NOT on the user stream" \
    "A path-qualified" "$DRV_ERR"
done

# --- (b) exit2: one verdict line, and the detail behind it. Its single wire is the
# user's, so ADR-030 puts the detail on it — and the shape rows (2e/2e2/2f) are asserted
# together with the content row (2g), because "the verdict is one line" is worthless
# beside a stream that carries nothing else and "the detail is there" is worthless beside
# a stream whose first line has stopped being the verdict. ---
drive "$LIB" exit2 "$FX_VERB" "$FX_FACT" "$FX_FIX" "$FX_DETAIL"
expect_regex "2e exit2: the FIRST line matches AC-E1.3's shape" "$USER_LINE_RE" "$DRV_ERR_1"
expect_eq "2e2 exit2: …spelled from the object's four fields" \
  "bionic: $FX_VERB refused — $FX_FACT ($FX_FIX)" "$DRV_ERR_1"
expect_eq "2f exit2: …and the verdict is exactly ONE line of the stream — it does not wrap" \
  "1" "$(printf '%s\n' "$DRV_ERR" | /usr/bin/grep -c '^bionic: ')"
expect_contains "2g exit2: …with the detail on the same wire behind it (ADR-030 superseded D-1)" \
  "A path-qualified" "$DRV_ERR"
expect_eq "2g2 exit2: …and a blank line between the two, so the verdict reads as a sentence" \
  "" "$(sed -n '2p' "$SANDBOX/.err")"
expect_eq "2h exit2: nothing at all on stdout (stdout is the JSON modes' wire)" "" "$DRV_OUT"

# --- (c) with no detail, every mode's user stream is one line and only one. ---
for _m in exit2 deny block; do
  drive "$LIB" "$_m" "$FX_VERB" "$FX_FACT" "$FX_FIX" ""
  expect_eq "2i $_m: a detail-less refusal is one line in every mode" "1" "$DRV_ERR_LINES"
  expect_regex "2j $_m: …still in the criterion's shape" "$USER_LINE_RE" "$DRV_ERR_1"
done

# --- (d) THE EXIT STATUS IS PART OF THE MODE. exit2 blocks by status; the two JSON
# modes block by verdict and must exit 0, or the CLI reads the status instead of the
# JSON and the reason never reaches the model. ---
drive "$LIB" exit2 "$FX_VERB" "$FX_FACT" "$FX_FIX" "$FX_DETAIL"
expect_status "2k exit2 exits 2" "2" "$DRV_RC"
drive "$LIB" deny "$FX_VERB" "$FX_FACT" "$FX_FIX" "$FX_DETAIL"
expect_status "2l deny exits 0 and blocks by verdict" "0" "$DRV_RC"
drive "$LIB" block "$FX_VERB" "$FX_FACT" "$FX_FIX" "$FX_DETAIL"
expect_status "2m block exits 0 and blocks by verdict" "0" "$DRV_RC"

# --- (e) THE FIX BUDGET, refused loudly at the call site. A seven-word fix is a
# programming error; the library refuses ITSELF through its own format rather than
# emitting a line the criterion rejects, and it still exits 2 so the wall holds. ---
drive "$LIB" exit2 "$FX_VERB" "$FX_FACT_SHORT" "$FX_FIX_7" "$FX_DETAIL"
expect_status "2n a seven-word fix is refused, fail-closed (exit 2)" "2" "$DRV_RC"
expect_eq "2o …in one line" "1" "$DRV_ERR_LINES"
expect_regex "2p …in the library's own format, under the verb refuse-call" \
  "$USER_LINE_RE" "$DRV_ERR_1"
expect_contains "2q …naming the count and the budget, not truncating" \
  "the fix field has 7 words, max 6" "$DRV_ERR_1"
expect_absent "2r …and the over-long fix is NOT emitted anywhere" "$FX_FIX_7" "$DRV_ERR"
# THE ARM IS ISOLATED: this fix is inside the COLUMN budget, so only the word count
# can be what refused it — see the FX_FIX_7 note above.
expect_true "2r2 …and the seven-word fix was inside the column budget, so the word count is what fired" \
  bash -c '. "$1"; [ "$(bionic_cols "$2")" -le 40 ]' _ "$LIB_DIR/width.sh" "$FX_FIX_7"

# A six-word fix is accepted: the budget is a boundary, not a mood.
drive "$LIB" exit2 "$FX_VERB" "$FX_FACT" "put it on the Suites line" "$FX_DETAIL"
expect_contains "2s a six-word fix passes the budget" "(put it on the Suites line)" "$DRV_ERR_1"

# --- (f) THE OTHER AUTHORING ERRORS. Each is one line, in format, exit 2. ---
drive "$LIB" exit2 "$FX_VERB" "$(printf 'two\nlines')" "$FX_FIX" "$FX_DETAIL"
expect_status "2t a two-line fact is refused, fail-closed" "2" "$DRV_RC"
expect_eq "2u …in one line" "1" "$DRV_ERR_LINES"
expect_contains "2v …naming the field" "the fact field carries a newline" "$DRV_ERR_1"

drive "$LIB" nosuchmode "$FX_VERB" "$FX_FACT" "$FX_FIX" "$FX_DETAIL"
expect_status "2w an unknown mode is refused, fail-closed" "2" "$DRV_RC"
expect_contains "2x …naming the three that exist" "use exit2, deny or block" "$DRV_ERR_1"

drive "$LIB" systemmessage "$FX_VERB" "$FX_FACT" "$FX_FIX" "$FX_DETAIL"
expect_status "2y a measured-but-undelivered mode is refused too (A-13)" "2" "$DRV_RC"
expect_contains "2z …as not a refusal channel" "is not a refusal channel" "$DRV_ERR_1"

drive "$LIB" exit2 "Run Arm" "$FX_FACT" "$FX_FIX" "$FX_DETAIL"
expect_status "2aa a verb outside [a-z-]+ is refused" "2" "$DRV_RC"
expect_contains "2ab …naming the alphabet the criterion's regex allows" \
  "is not lower-case letters and hyphens" "$DRV_ERR_1"

# A fact long enough to push the line past 100 columns is a programming error too:
# a wrapped line is one row rendered as two, which is what the one-line contract is for.
LONG_FACT="$(printf 'x%.0s' $(seq 1 120))"
drive "$LIB" exit2 "$FX_VERB" "$LONG_FACT" "$FX_FIX" "$FX_DETAIL"
expect_status "2ac a fact that overflows 100 columns is refused, fail-closed" "2" "$DRV_RC"
expect_contains "2ad …naming the measured width and the budget" "columns, max 100" "$DRV_ERR_1"
expect_true "2ae …and the complaint itself fits the budget" \
  bash -c '. "$1"; [ "$(bionic_cols "$2")" -le 100 ]' _ "$LIB_DIR/width.sh" "$DRV_ERR_1"

# --- (g) THE MUTANTS. Without these, every row above could be passing over a
# renderer that never checked anything. ---
mutant m-words 's/"\$fix_words" -gt/0 -gt/' '"$fix_words" -gt'
M_WORDS="$MUT_PATH"
drive "$M_WORDS" exit2 "$FX_VERB" "$FX_FACT_SHORT" "$FX_FIX_7" "$FX_DETAIL"
expect_contains "2af MUTANT without the word budget the over-long fix is emitted (the arm discriminates)" \
  "$FX_FIX_7" "$DRV_ERR_1"
# AND THE REGEX DOES NOT CATCH IT — measured, not assumed. AC-E1.3's
# `\(.{1,40}\)$` bounds the fix in CHARACTERS; a seven-word fix of 32 columns
# satisfies it. So the six-word rule is enforceable only in the library, and a suite
# that pinned the format regex alone would pass over every over-long fix that happens
# to be short. This row states that gap rather than papering over it: the mutant's
# line is well-formed by the criterion's own regex and still wrong.
expect_regex "2ag MUTANT …and the criterion's regex CANNOT see the word count: the mutant's line still matches it" \
  "$USER_LINE_RE" "$DRV_ERR_1"
expect_eq "2ag2 MUTANT …so the library, not the regex, is the only thing enforcing six words" \
  "7" "$(bash -c '. "$1"; _refuse_words "$2"' _ "$LIB" "$FX_FIX_7")"

mutant m-leak 's/refuse_channel "\$mode" detail_to_user/echo yes/' 'refuse_channel "$mode" detail_to_user'
M_LEAK="$MUT_PATH"
drive "$M_LEAK" deny "$FX_VERB" "$FX_FACT" "$FX_FIX" "$FX_DETAIL"
expect_ne "2ah MUTANT with the stream split removed, deny's user stream is no longer one line" \
  "1" "$DRV_ERR_LINES"
expect_contains "2ai MUTANT …it is the detail that leaked onto it" "A path-qualified" "$DRV_ERR"

# ============================================================
section "3 — AC-E1.5: BIONIC_WALL_VERBOSE=1 shows the detail to the user"
# ============================================================
#
# fails-when: the knob is ignored. The knob is asserted in every mode, including the
# one whose user stream already carries the detail — a knob that silently does
# nothing in two modes out of three is ignored in the way that matters.

for _m in exit2 deny block; do
  drive_v 1 "$LIB" "$_m" "$FX_VERB" "$FX_FACT" "$FX_FIX" "$FX_DETAIL"
  expect_contains "3a $_m: with the knob the user stream carries the detail" \
    "A path-qualified" "$DRV_ERR"
  expect_regex "3b $_m: …and the one line is still the first of it" "$USER_LINE_RE" "$DRV_ERR_1"
  expect_eq "3c $_m: …with the blank line between them" "" "$(sed -n '2p' "$SANDBOX/.err")"
done

# The knob does not change the WIRE — only what the user stream carries. A verbose
# refusal still blocks, and its model payload is unchanged.
drive_v 1 "$LIB" block "$FX_VERB" "$FX_FACT" "$FX_FIX" "$FX_DETAIL"
expect_status "3d the knob does not disarm the wall" "0" "$DRV_RC"
expect_contains "3e …and the model's reason is still there" '"decision":"block"' "$DRV_OUT"

# Any other value is not the knob: it is a set-and-forget footgun otherwise.
drive_v 0 "$LIB" deny "$FX_VERB" "$FX_FACT" "$FX_FIX" "$FX_DETAIL"
expect_eq "3f BIONIC_WALL_VERBOSE=0 is off, and the user stream is one line again" "1" "$DRV_ERR_LINES"
drive_v yes "$LIB" deny "$FX_VERB" "$FX_FACT" "$FX_FIX" "$FX_DETAIL"
expect_eq "3g BIONIC_WALL_VERBOSE=yes is off: the knob's value is 1" "1" "$DRV_ERR_LINES"

# THE MUTANT: the knob removed from the condition. deny is the mode to drive it on —
# its `detail_to_user` cell is `no`, so the knob is the only thing that can put the
# detail on the user stream there.
mutant m-knob 's/BIONIC_WALL_VERBOSE:-/BIONIC_KNOB_THE_MUTANT_IGNORES:-/' 'BIONIC_WALL_VERBOSE:-'
M_KNOB="$MUT_PATH"
drive_v 1 "$M_KNOB" deny "$FX_VERB" "$FX_FACT" "$FX_FIX" "$FX_DETAIL"
expect_absent "3h MUTANT with the knob ignored the detail never reaches the user (the arm discriminates)" \
  "A path-qualified" "$DRV_ERR"

# ============================================================
section "4 — the model stream: one shape per mode, the three the measurement proved"
# ============================================================
#
# The measurement (e1-measurement.md, modes 1/2/4) proved three channels deliver the
# payload to the model in full. This section pins that the renderer puts `detail` on
# each of them, in the field that channel uses, and that the JSON is JSON — escaped
# by parameter expansion here rather than by `jq`, so the escaping is this file's
# responsibility and needs a parser to check it.

json_field() {  # <json> <jq-ish path> -> the value, via python3 (no jq dependency)
  python3 -c 'import json,sys; d=json.loads(sys.stdin.read())
for k in sys.argv[1].split("."): d=d[k]
sys.stdout.write(d)' "$1" <<<"$2"
}

drive "$LIB" deny "$FX_VERB" "$FX_FACT" "$FX_FIX" "$FX_DETAIL"
expect_contains "4a deny: the wire is a PreToolUse permissionDecision deny" \
  '"permissionDecision":"deny"' "$DRV_OUT"
DENY_REASON="$(json_field hookSpecificOutput.permissionDecisionReason "$DRV_OUT")"
expect_status "4b deny: the JSON parses" "0" "$?"
expect_contains "4c deny: permissionDecisionReason opens with the user line" \
  "bionic: $FX_VERB refused — $FX_FACT ($FX_FIX)" "$DENY_REASON"
expect_contains "4d deny: …and carries the detail the user did not see" \
  "A path-qualified" "$DENY_REASON"
expect_contains "4e deny: …with the quotes, backslash and newlines intact through the escaper" \
  'C:\task' "$DENY_REASON"

drive "$LIB" block "$FX_VERB" "$FX_FACT" "$FX_FIX" "$FX_DETAIL"
expect_contains "4f block: the wire is a decision:block verdict" '"decision":"block"' "$DRV_OUT"
BLOCK_REASON="$(json_field reason "$DRV_OUT")"
expect_status "4g block: the JSON parses" "0" "$?"
expect_contains "4h block: reason opens with the user line" \
  "bionic: $FX_VERB refused — $FX_FACT ($FX_FIX)" "$BLOCK_REASON"
expect_contains "4i block: …and carries the detail" "A path-qualified" "$BLOCK_REASON"

# exit2 has no second channel: the model reads the same stderr the user does. Under D-1
# that meant the model got the one line and the detail was the log's and the knob's — the
# D4 degradation named in refuse.sh's header. ADR-030 ends it in the only way one wire
# allows, by giving both readers the detail, which is why the knob has nothing left to add
# on this mode (4k2).
drive "$LIB" exit2 "$FX_VERB" "$FX_FACT" "$FX_FIX" "$FX_DETAIL"
expect_contains "4j exit2: stderr carries the one line, which is what the model reads" \
  "bionic: $FX_VERB refused — $FX_FACT ($FX_FIX)" "$DRV_ERR_1"
expect_contains "4k exit2: …and the detail is on it too, in both directions (ADR-030)" \
  "A path-qualified" "$DRV_ERR"
EXIT2_KNOB_OFF="$DRV_ERR"
drive_v 1 "$LIB" exit2 "$FX_VERB" "$FX_FACT" "$FX_FIX" "$FX_DETAIL"
expect_eq "4k2 exit2: the knob adds nothing here — this channel already carries the detail" \
  "$EXIT2_KNOB_OFF" "$DRV_ERR"

# THE ESCAPER, on the shapes that break a hand-rolled one: a lone backslash before a
# quote, a tab, a carriage return. A refusal naming a Windows path or a regex is not
# hypothetical — `C:\task` above is already one.
HARD='a "quoted" thing, a \backslash, a \" pair, a	tab and a
newline'
drive "$LIB" block "$FX_VERB" "$FX_FACT" "$FX_FIX" "$HARD"
HARD_BACK="$(json_field reason "$DRV_OUT")"
expect_status "4l the escaper survives quotes, backslashes, a tab and a newline" "0" "$?"
expect_contains "4m …and the detail comes back byte-identical" "$HARD" "$HARD_BACK"

# CONTROL BYTES, the class a hand-rolled escaper forgets (Step-6 review F-1). JSON
# forbids EVERY code point below U+0020 unescaped, not just the five with a short
# spelling, and `detail` is not a field the library controls: farm-out-reminder.sh
# interpolates the model's own Bash command text into it, scrubbed for secrets and
# truncated but never filtered for control bytes. An unescaped 0x01 makes the whole
# `deny` verdict unparseable, and `deny` exits 0 — so the wall reports success while
# telling the CLI nothing, which is the fail-OPEN direction.
CTRL="$(printf 'a\001b\033c\016d')"
drive "$LIB" deny "$FX_VERB" "$FX_FACT" "$FX_FIX" "$CTRL"
CTRL_BACK="$(json_field hookSpecificOutput.permissionDecisionReason "$DRV_OUT")"
expect_status "4n deny: a detail carrying control bytes still parses as JSON" "0" "$?"
expect_contains "4o deny: …and the bytes survive the escaper" "$CTRL" "$CTRL_BACK"
expect_absent "4p deny: …and no raw control byte is on the wire" "$CTRL" "$DRV_OUT"

drive "$LIB" block "$FX_VERB" "$FX_FACT" "$FX_FIX" "$CTRL"
CTRL_BACK="$(json_field reason "$DRV_OUT")"
expect_status "4q block: the same detail parses on the block wire" "0" "$?"
expect_contains "4r block: …and the bytes survive there too" "$CTRL" "$CTRL_BACK"
expect_absent "4s block: …and no raw control byte is on the wire" "$CTRL" "$DRV_OUT"

# A MANY-LINE DETAIL ON THE `deny` WIRE (wave-12 T17). The dispatch gate's refusals ride
# this field whatever their fault count (wave-19 T4, REQ-7): a lone fault's own detail, or
# several faults' lines and a marked scaffold — tens of lines either way — because it is
# the one the measurement proved reaches the model in full. The fixture below keeps the
# older findings-list shape; the properties it pins do not depend on the shape. Three properties it depends on, pinned here rather than inferred from the
# newline arm above: the verdict is ONE line of output whatever the detail's shape, no raw
# newline survives onto the wire, and the list comes back from a parser byte-identical,
# blank lines and indentation included. A wall whose JSON spanned several lines would be a
# wall the CLI cannot read, and `deny` exits 0 — the fail-OPEN direction.
MANY="$(printf 'THIS BRIEF HAS 3 SHAPE FAULTS.\n\n── 1. a fact (a fix)\n\nFix: do the thing —\n    Expected artifact: .bionic/docs/record/x.md\n\n── 2. another fact (another fix)\n\nFix: do the other thing\n')"
drive "$LIB" deny "$FX_VERB" "$FX_FACT" "$FX_FIX" "$MANY"
expect_status "4u deny: a many-line findings list is emitted as ONE line of JSON" "1" \
  "$(printf '%s\n' "$DRV_OUT" | grep -c . || true)"
expect_absent "4v deny: …with no raw newline left on the wire" "$(printf '\n── 1.')" "$DRV_OUT"
MANY_BACK="$(json_field hookSpecificOutput.permissionDecisionReason "$DRV_OUT")"
expect_status "4w deny: …and the verdict parses" "0" "$?"
expect_contains "4x deny: …carrying the whole list back byte-identical" "$MANY" "$MANY_BACK"
expect_eq "4y deny: …with every line of it, blank lines included" \
  "$(printf '%s\n' "$MANY" | wc -l | tr -d ' ')" \
  "$(printf '%s\n' "$MANY_BACK" | sed -n '3,$p' | wc -l | tr -d ' ')"
expect_status "4z deny: …and the status is still 0, because the verdict is the block" "0" "$DRV_RC"

# THE ESCAPER IS STILL PARAMETER EXPANSION, not `jq`. refuse.sh's header gives the
# reason — `jq` is a dependency this machine can lose and a wall that cannot format
# its refusal must not therefore fail open — and F-1's fix must not buy validity by
# reintroducing it. The permit path is the one that must stay free of processes, and
# sourcing the library is the whole permit path.
expect_absent "4t the escaper does not shell out to jq" "jq" \
  "$(sed -n '/^_refuse_json_escape()/,/^}/p' "$LIB")"

# ============================================================
section "5 — fail-closed: refuse exits, and no path out of it waves the action past"
# ============================================================
#
# THE REGRESSION THIS FORBIDS. A wall that formats its refusal and returns leaves the
# call site to remember `exit`. 62 refusal texts across 21 files is 62 chances to
# forget one, and a forgotten exit is invisible: the wall prints its refusal and the
# action happens anyway. `refuse` owns the exit, and the scratch hook's FELL-THROUGH
# line is how this section reads whether it ever gave it back.

for _m in exit2 deny block; do
  drive "$LIB" "$_m" "$FX_VERB" "$FX_FACT" "$FX_FIX" "$FX_DETAIL"
  expect_absent "5a $_m: refuse never returns to its call site" "FELL-THROUGH" "$DRV_ERR"
done
for _bad in nosuchmode systemmessage additionalcontext; do
  drive "$LIB" "$_bad" "$FX_VERB" "$FX_FACT" "$FX_FIX" "$FX_DETAIL"
  expect_absent "5b $_bad: an authoring error does not return either" "FELL-THROUGH" "$DRV_ERR"
  expect_status "5c $_bad: …it exits 2, so the wall still holds" "2" "$DRV_RC"
done

# WRONG ARITY is the authoring error most likely to reach production from a migration
# script, and it must not be the one that fails open.
bash "$WALL" "$LIB" exit2 "$FX_VERB" "$FX_FACT" >"$SANDBOX/.out" 2>"$SANDBOX/.err"; ARITY_RC=$?
expect_status "5d too few arguments is refused, fail-closed" "2" "$ARITY_RC"
expect_contains "5e …naming the shape it wanted" "pass mode verb fact fix detail" "$(cat "$SANDBOX/.err")"
expect_absent "5f …and does not return" "FELL-THROUGH" "$(cat "$SANDBOX/.err")"

# THE LIBRARY IS SOURCEABLE ALONE. A hook that declares refuse.sh and nothing else
# must get a working renderer: the soft source of width.sh is the file's only
# top-level command, and it prints nothing.
SRC_OUT="$(bash -c '. "$1"' _ "$LIB" 2>&1)"
expect_empty "5g sourcing refuse.sh alone prints nothing and needs no other library" "$SRC_OUT"
expect_true "5h …and defines the whole interface" \
  bash -c '. "$1"; declare -F refuse >/dev/null && declare -F refuse_channel >/dev/null && declare -F refuse_modes >/dev/null' _ "$LIB"

# ============================================================
section "6 — ADR-030: an exit2 refusal prints the detail it computed, bounded"
# ============================================================
#
# THE DEFECT THIS SECTION EXISTS FOR (seed A §8a, carry-over 8, research R2, ADR-030).
# Field 9 shipped `no` for `exit2` under ruling D-1, and `exit2` has ONE wire: the evidence
# gate computed the whole `units_validate` violation list, handed it to `refuse`, and the
# list reached neither reader. A consumer's orchestrator read "that dispatched task's row is
# invalid (fix the row the detail names)" and sourced the validator by hand to learn which
# row. ADR-030 flips the cell and bounds what prints instead of spending the wire on the
# headline alone.
#
# EVERY ROW HERE RUNS WITH THE KNOB UNSET, which is the state a real refusal runs in and
# the seam that hid the defect for three releases: §3's rows pass either way because they
# SET `BIONIC_WALL_VERBOSE`, so not one of them could express this. `drive` passes an empty
# value, which also masks an inherited one from the environment.
#
# THE BOUND IS ON WHAT PRINTS, NOT ON WHAT THE MODEL READS (A-T4.1). Twelve is the number
# the terminal paints before it folds the rest away — the `exit2` row's own field 6, measured
# on CLI 2.1.263 — so the fold applies where `detail` lands on the USER stream. A channel
# whose `detail` is model-only (`deny`, `block`) still carries its whole list to the model:
# wave-12 T17's combined findings list is tens of lines and rides that field precisely
# because the measurement proved it arrives in full. 6p/6q pin both halves of that split.
#
# fails-when: an exit2 refusal prints one line with the knob unset; or a thirty-line detail
# prints thirty lines; or the `+N more` line is absent or names the wrong count; or the
# bound is off by one at twelve or thirteen; or the fold reaches a model-only channel.
# [REQ-2 AC-2.3 KNOB-UNSET SECTION: BEGIN]

# --- (a) AC-2.1 at the library: the detail is on the wire the reader reads. ---
drive "$LIB" exit2 "$FX_VERB" "$FX_FACT" "$FX_FIX" "$FX_DETAIL"
expect_regex "6a exit2, knob unset: the first line is still the one-line verdict" \
  "$USER_LINE_RE" "$DRV_ERR_1"
expect_contains "6b …and the detail it computed is on the wire behind it (ADR-030)" \
  "A path-qualified" "$DRV_ERR"
expect_eq "6c …separated from the verdict by one blank line" "" "$(sed -n '2p' "$SANDBOX/.err")"
expect_eq "6d …carrying the whole three-line detail and nothing more" "5" "$DRV_ERR_LINES"
expect_status "6d2 …and it still blocks by status" "2" "$DRV_RC"

# --- (b) AC-2.2 the bound, driven through the same real call site. Thirty lines in,
# twelve out, and one line naming the eighteen that were dropped. ---
FX_D30="$(awk 'BEGIN { for (i = 1; i <= 30; i++) printf "D%02d a violation line\n", i }')"
drive "$LIB" exit2 "$FX_VERB" "$FX_FACT" "$FX_FIX" "$FX_D30"
expect_contains "6e a thirty-line detail: the twelfth line prints" "D12 a violation line" "$DRV_ERR"
expect_absent "6f …and the thirteenth does not" "D13 a violation line" "$DRV_ERR"
expect_absent "6g …nor the thirtieth" "D30 a violation line" "$DRV_ERR"
expect_contains "6h …with one line naming how many were dropped" "+18 more" "$DRV_ERR"
expect_eq "6i …so the stream is fifteen lines: the verdict, a blank, twelve, the count" \
  "15" "$DRV_ERR_LINES"
expect_regex "6j …and the verdict is still the first line, untouched by the fold" \
  "$USER_LINE_RE" "$DRV_ERR_1"
expect_eq "6k …with the count line last, and nothing after it" "+18 more" \
  "$(sed -n '15p' "$SANDBOX/.err")"

# --- (c) THE HELPER'S OWN EDGES, as a unit: 0 prints nothing, 12 prints twelve with no
# count line, 13 prints twelve and `+1 more`. A bound asserted only at thirty cannot tell
# twelve from eleven. ---
fold_detail() { bash -c '. "$1"; _refuse_fold_detail "$2"' _ "$LIB" "${1:-}"; }
require_helpers fold_detail
FX_D12="$(awk 'BEGIN { for (i = 1; i <= 12; i++) printf "L%02d\n", i }')"
FX_D13="$(awk 'BEGIN { for (i = 1; i <= 13; i++) printf "L%02d\n", i }')"
expect_eq "6l the helper on no detail at all emits nothing" "" "$(fold_detail "")"
expect_eq "6m …on exactly twelve lines emits twelve" "12" \
  "$(fold_detail "$FX_D12" | wc -l | tr -d ' ')"
expect_absent "6n …and no count line, because none were dropped" "more" "$(fold_detail "$FX_D12")"
expect_eq "6o …on thirteen it emits thirteen: the twelve and the count" "13" \
  "$(fold_detail "$FX_D13" | wc -l | tr -d ' ')"
expect_eq "6p …whose twelfth line is the twelfth line in, unrewritten" "L12" \
  "$(fold_detail "$FX_D13" | sed -n '12p')"
expect_eq "6q …and whose last line names the one it dropped" "+1 more" \
  "$(fold_detail "$FX_D13" | sed -n '13p')"

# --- (c2) THE TRAILING-NEWLINE OFF-BY-ONE (wave-16 T21; walk-2c882be.md §2). A caller
# that builds `detail` by appending "…\n" per row hands the helper a string that already
# ends in a newline; `printf '%s\n' "$1"` then adds a SECOND one, and `awk`'s NR sees the
# resulting empty final record as one more line to count — twenty real lines read as
# twenty-one records, so `+8 more` (20 - 12) becomes `+9 more` for no reason the caller's
# content explains. The fix must count real lines only, regardless of how the caller
# terminated its string.
#
# fails-when: a detail ending in a trailing newline reports a different `+N more` count,
# or a different total line count, than the SAME content with no trailing newline.
FX_D20="$(awk 'BEGIN { for (i = 1; i <= 20; i++) printf "N%02d\n", i }')"
# `$( )` strips ALL trailing newlines from FX_D20 itself, so the "with a trailing newline"
# fixture below adds exactly one back — deliberately, not incidentally.
FX_D20_NL="${FX_D20}
"
expect_eq "6q2 no trailing newline: twenty lines, twelve minus eight, fold to +8 more" \
  "+8 more" "$(fold_detail "$FX_D20" | tail -1)"
expect_eq "6q3 ONE trailing newline: the count is UNCHANGED, not inflated to +9 more" \
  "+8 more" "$(fold_detail "$FX_D20_NL" | tail -1)"
expect_eq "6q4 …and the two fixtures fold to the identical LINE COUNT as well" \
  "$(fold_detail "$FX_D20" | wc -l | tr -d ' ')" \
  "$(fold_detail "$FX_D20_NL" | wc -l | tr -d ' ')"
expect_eq "6q5 …thirteen lines each: the twelve kept plus the one count line" "13" \
  "$(fold_detail "$FX_D20_NL" | wc -l | tr -d ' ')"

# --- (d) THE SPLIT IS UNCHANGED FOR THE MODEL-ONLY CHANNELS. `deny` and `block` keep
# their `detail_to_user=no` cell, so the reader still gets one line there, and their
# model wire still carries the whole list — the property wave-12 T17's combined refusal
# depends on (tests/fold.test.sh 13i, tests/dispatch-preflight-3.test.sh §combined-deny). ---
drive "$LIB" deny "$FX_VERB" "$FX_FACT" "$FX_FIX" "$FX_D30"
expect_eq "6r deny: the user stream is still exactly one line — the flip is exit2's alone" \
  "1" "$DRV_ERR_LINES"
expect_contains "6s …while the model's wire still carries the thirtieth line, unfolded" \
  "D30 a violation line" "$DRV_OUT"
expect_absent "6t …and no count line was spliced into it" "+18 more" "$DRV_OUT"

# --- (e) THE MUTANTS. Both halves of ADR-030 have one: the cell, and the fold. ---
mutant m-cell 's/refuse_channel "\$mode" detail_to_user/echo no/' 'refuse_channel "$mode" detail_to_user'
M_CELL="$MUT_PATH"
drive "$M_CELL" exit2 "$FX_VERB" "$FX_FACT" "$FX_FIX" "$FX_DETAIL"
expect_absent "6u MUTANT with the cell forced back to no, exit2's detail vanishes again" \
  "A path-qualified" "$DRV_ERR"
expect_eq "6v MUTANT …and the user stream is the one line the defect shipped (the arm discriminates)" \
  "1" "$DRV_ERR_LINES"

mutant m-bound 's/_refuse_fold_detail "\$detail"/printf %s "\$detail"/' '_refuse_fold_detail "$detail"'
M_BOUND="$MUT_PATH"
drive "$M_BOUND" exit2 "$FX_VERB" "$FX_FACT" "$FX_FIX" "$FX_D30"
expect_contains "6w MUTANT without the fold the thirtieth line prints (the bound is what stops it)" \
  "D30 a violation line" "$DRV_ERR"
expect_absent "6x MUTANT …and no count line is emitted at all" "+18 more" "$DRV_ERR"
expect_eq "6y MUTANT …so the stream is the whole thirty-two lines the call site handed it" \
  "32" "$DRV_ERR_LINES"
# [REQ-2 AC-2.3 KNOB-UNSET SECTION: END]

# --- (f) THE KNOB IS STILL PURE ADDITION, AND THESE TWO ROWS SIT OUTSIDE THE MARKED SPAN
# BECAUSE OF IT (A-T4.2). Two readers reach `detail` on the user stream: one did not ask
# for it and gets the bounded twelve, because twelve is what that reader's terminal paints;
# the other typed `BIONIC_WALL_VERBOSE=1` to see the facts, and bounding what they asked
# for would delete diagnostics on the one path whose purpose is to show them (the
# stop-guard arms in tests/cross-gate-agreement.test.sh read exactly such a line out of an
# eighteen-line detail). The asymmetry is the decision, so it is pinned rather than
# discovered. The span above is the knob-UNSET harness AC-2.3 holds to that rule, and a
# knob-on row inside it would read as a breach of the very thing it marks. ---
drive_v 1 "$LIB" exit2 "$FX_VERB" "$FX_FACT" "$FX_FIX" "$FX_D30"
expect_contains "6z with the knob set the thirtieth line prints too — the knob only adds" \
  "D30 a violation line" "$DRV_ERR"
expect_absent "6z2 …and no count line, because nothing was held back" "+18 more" "$DRV_ERR"
expect_eq "6z3 …so the whole thirty-two lines are on the stream" "32" "$DRV_ERR_LINES"

section "§T47 — a refusal never loses its own line to a long value (wave-27 T47, A-orch-59)"
# Before T47 an over-wide line refused ITS OWN CALL, so a wall that put a user's value into its
# fact (a file name, a verb, a brief word) printed `refuse-call refused — the user line is N
# columns` in place of the rule that fired (T16's `release-check` at 103 columns; T42's `Files:`
# word of 17 characters). The library now cuts the FACT to fit, with its own `bionic_trunc`, and
# gives the whole fact as the first line of the detail. The fix is never cut; the other
# self-refusals are unchanged; and under BIONIC_REFUSE_STRICT=1, which every suite runs with,
# an over-wide STATIC line still refuses the call as it always did, so an author's too-long
# literal is found at test time.
#
# fails-when: an over-wide fact still refuses the call strict-off; the cut line leaves the
# caller's verb, channel or exit; the whole fact is not the detail's first line; the cap drops
# the fact instead of the last detail line; the cut splits a multi-byte character under either
# locale; a long fix is cut instead of refused; any other self-refusal moves; the strict setting
# stops refusing, or is set by anything under hooks/ or payload/, or is off for a suite.

# A line is `bionic: run-arm refused — ` (26 cols) + fact + ` (add it to Suites:)` (20 cols), so
# a fact has 54 columns before the line is 100. T47_FIT is 54; T47_ONE is 55, one column over.
T47_FIT="$(printf 'f%.0s' $(seq 1 54))"
T47_ONE="$(printf 'o%.0s' $(seq 1 55))"
t47_drive() {  # <strict: 1 | "" | UNSET> <locale or ""> <refuse args…>
  DRV_STRICT="$1"; DRV_LC="$2"; shift 2
  drive "$LIB" "$@"
  DRV_STRICT=1; DRV_LC=""
}
t47_line_cols() { bash -c '. "$1"; bionic_cols "$2"' _ "$LIB_DIR/width.sh" "$1"; }

# --- (a) a fact that fits is printed byte for byte, strict or not ---
t47_drive "" "" exit2 "$FX_VERB" "$T47_FIT" "$FX_FIX" "$FX_DETAIL"
expect_eq "T47-a1 a fact that fits is printed whole, strict off" \
  "bionic: run-arm refused — $T47_FIT (add it to Suites:)" "$DRV_ERR_1"
expect_eq "T47-a2 …at exactly 100 columns" "100" "$(t47_line_cols "$DRV_ERR_1")"
expect_eq "T47-a3 …with the caller's detail untouched behind it (verdict, blank, three lines)" "5" "$DRV_ERR_LINES"
expect_contains "T47-a4 …and its first detail line is the caller's own, not the fact" \
  "The wall reads the plan brief" "$(sed -n '3p' "$SANDBOX/.err")"

# --- (b) one column over: cut by the library's truncation, on the caller's verb, channel, exit ---
for _m in exit2 deny block; do
  t47_drive "" "" "$_m" "$FX_VERB" "$T47_ONE" "$FX_FIX" "$FX_DETAIL"
  expect_eq "T47-b1 $_m: a fact one column over is cut (ellipsis inside the width), on the caller's verb" \
    "bionic: run-arm refused — $(printf 'o%.0s' $(seq 1 53))… (add it to Suites:)" "$DRV_ERR_1"
  expect_eq "T47-b2 $_m: …the line is 100 columns" "100" "$(t47_line_cols "$DRV_ERR_1")"
  expect_regex "T47-b3 $_m: …and it is still in the criterion's shape" "$USER_LINE_RE" "$DRV_ERR_1"
done
t47_drive "" "" exit2 "$FX_VERB" "$T47_ONE" "$FX_FIX" "$FX_DETAIL"
expect_status "T47-b4 exit2: the cut refusal exits 2, the caller's own status" "2" "$DRV_RC"
expect_eq "T47-b5 exit2: the detail's FIRST line is the whole uncut fact" "$T47_ONE" "$(sed -n '3p' "$SANDBOX/.err")"
expect_contains "T47-b6 exit2: …the caller's own detail follows it" \
  "The wall reads the plan brief" "$(sed -n '4p' "$SANDBOX/.err")"
expect_eq "T47-b7 exit2: …verdict, blank, the fact, the caller's three lines" "6" "$DRV_ERR_LINES"
t47_drive "" "" deny "$FX_VERB" "$T47_ONE" "$FX_FIX" "$FX_DETAIL"
expect_status "T47-b8 deny: the cut refusal exits 0, the caller's own status" "0" "$DRV_RC"
expect_eq "T47-b9 deny: …the user stream is the one cut line, as for any deny" "1" "$DRV_ERR_LINES"
expect_contains "T47-b10 deny: …and the model's reason carries the whole fact as the detail's first line" \
  "\\n\\n$T47_ONE\\n" "$DRV_OUT"
t47_drive "" "" block "$FX_VERB" "$T47_ONE" "$FX_FIX" "$FX_DETAIL"
expect_status "T47-b11 block: the cut refusal exits 0, the caller's own status" "0" "$DRV_RC"
expect_contains "T47-b12 block: …and the model's reason carries the whole fact" "\\n\\n$T47_ONE\\n" "$DRV_OUT"
t47_drive "" "" exit2 "$FX_VERB" "$T47_ONE" "$FX_FIX" ""
expect_eq "T47-b13 a cut refusal with NO caller detail still gives the whole fact: verdict, blank, fact" "3" "$DRV_ERR_LINES"
expect_eq "T47-b14 …and the fact is its third line" "$T47_ONE" "$(sed -n '3p' "$SANDBOX/.err")"

# --- (c) the detail's cap: the fact is first, and the LAST caller line is the one dropped ---
FX_D12B="$(awk 'BEGIN { for (i = 1; i <= 12; i++) printf "L%02d\n", i }')"
t47_drive "" "" exit2 "$FX_VERB" "$T47_ONE" "$FX_FIX" "$FX_D12B"
expect_eq "T47-c1 twelve caller lines + the fact is one over the cap: the fact is still the first detail line" \
  "$T47_ONE" "$(sed -n '3p' "$SANDBOX/.err")"
expect_eq "T47-c2 …the caller's eleventh line is the last printed" "L11" "$(sed -n '14p' "$SANDBOX/.err")"
expect_absent "T47-c3 …the caller's twelfth, LAST line is the one dropped" "L12" "$DRV_ERR"
expect_eq "T47-c4 …and the count line names it" "+1 more" "$(sed -n '15p' "$SANDBOX/.err")"
t47_drive "" "" exit2 "$FX_VERB" "$T47_ONE" "$FX_FIX" "$(printf 'M%02d\n' $(seq 1 11))"
expect_eq "T47-c5 eleven caller lines + the fact is exactly the cap: all of them print, no count line" \
  "M11" "$(sed -n '14p' "$SANDBOX/.err")"
expect_absent "T47-c6 …and nothing is held back" "more" "$DRV_ERR"

# --- (d) a long fact with a multi-byte character at the cut, under UTF-8 and under LC_ALL=C ---
# THE CUT IS bionic_trunc's, which pins LC_ALL=C and drops a whole character by walking off its
# continuation bytes, so the printed line holds no partial character under either locale
# (A-T47.3). Both offsets are driven: the character straddling the cut (52 narrow columns then
# `é`, two bytes) and one ending exactly at it (51 then `é`).
T47_UTF8="$(locale -a 2>/dev/null | grep -i 'utf-\{0,1\}8' | head -1)"
expect_nonempty "T47-d0 a UTF-8 locale is installed to drive the UTF-8 half" "$T47_UTF8"
T47_NARROW51="$(printf 'x%.0s' $(seq 1 51))"
T47_NARROW52="$(printf 'x%.0s' $(seq 1 52))"
T47_TAIL="$(printf 'é日%.0s' $(seq 1 100))"
# THE DECODER CAN FAIL: a line cut in the middle of a character is rejected by the same check.
expect_false "T47-d0b the decoder check rejects a half character (so d4 can fail)" \
  bash -c 'printf "a\303\n" | iconv -f UTF-8 -t UTF-8 >/dev/null 2>&1'
for _lc in "$T47_UTF8" C; do
  for _pre in "$T47_NARROW51" "$T47_NARROW52"; do
    _fact="${_pre}${T47_TAIL}"
    t47_drive "" "$_lc" exit2 "$FX_VERB" "$_fact" "$FX_FIX" "$FX_DETAIL"
    expect_status "T47-d1 [$_lc, ${#_pre} narrow] a ~350-column fact is refused on its own verb" "2" "$DRV_RC"
    expect_regex "T47-d2 [$_lc, ${#_pre} narrow] …cut to a line in the criterion's shape" "$USER_LINE_RE" "$DRV_ERR_1"
    expect_false "T47-d3 [$_lc, ${#_pre} narrow] …not the library refusing its own call" \
      grep -q 'refuse-call' "$SANDBOX/.err"
    expect_true "T47-d4 [$_lc, ${#_pre} narrow] …the printed line's bytes decode as UTF-8 (no partial character)" \
      bash -c 'printf "%s\n" "$1" | iconv -f UTF-8 -t UTF-8 >/dev/null 2>&1' _ "$DRV_ERR_1"
    expect_contains "T47-d5 [$_lc, ${#_pre} narrow] …the cut ends in the ellipsis" "… (add it to Suites:)" "$DRV_ERR_1"
    expect_eq "T47-d6 [$_lc, ${#_pre} narrow] …and the whole fact is the detail's first line, byte for byte" \
      "$_fact" "$(sed -n '3p' "$SANDBOX/.err")"
    expect_true "T47-d7 [$_lc, ${#_pre} narrow] …the line fits 100 columns by the library's own count" \
      bash -c '. "$1"; [ "$(bionic_cols "$2")" -le 100 ]' _ "$LIB_DIR/width.sh" "$DRV_ERR_1"
  done
done

# --- (e) the fix is never cut ---
t47_drive "" "" exit2 "$FX_VERB" "$T47_ONE" "add it to the Suites budget line" "$FX_DETAIL"
expect_status "T47-e1 a seven-word fix with an over-wide fact is refused, strict off" "2" "$DRV_RC"
expect_contains "T47-e2 …as a refusal of the call, naming the words" "the fix field has 7 words, max 6" "$DRV_ERR_1"
t47_drive "" "" exit2 "$FX_VERB" "$FX_FACT_SHORT" "add it to the Suites budget line" "$FX_DETAIL"
expect_contains "T47-e3 …and the same with a fact that fits" "the fix field has 7 words, max 6" "$DRV_ERR_1"
t47_drive "" "" exit2 "$FX_VERB" "$T47_ONE" "$(printf 'z%.0s' $(seq 1 41))" "$FX_DETAIL"
expect_contains "T47-e4 a 41-column fix is refused, strict off, over-wide fact or not" \
  "the fix field is 41 columns, max 40" "$DRV_ERR_1"
t47_drive "" "" exit2 "$FX_VERB" "$FX_FACT_SHORT" "$(printf 'z%.0s' $(seq 1 41))" "$FX_DETAIL"
expect_contains "T47-e5 …and with a fact that fits" "the fix field is 41 columns, max 40" "$DRV_ERR_1"

# --- (f) every other self-refusal is unchanged, strict off ---
t47_drive "" "" exit2 "$FX_VERB" "$FX_FACT" "$FX_FIX"
expect_contains "T47-f1 a wrong argument count" "refuse takes 5 arguments and got 4" "$DRV_ERR_1"
t47_drive "" "" nosuchmode "$FX_VERB" "$FX_FACT" "$FX_FIX" "$FX_DETAIL"
expect_contains "T47-f2 an unknown mode" "is not a refusal channel" "$DRV_ERR_1"
t47_drive "" "" exit2 "Run Arm" "$FX_FACT" "$FX_FIX" "$FX_DETAIL"
expect_contains "T47-f3 a verb outside [a-z-]+" "is not lower-case letters and hyphens" "$DRV_ERR_1"
t47_drive "" "" exit2 "$FX_VERB" "" "$FX_FIX" "$FX_DETAIL"
expect_contains "T47-f4 an empty fact" "the fact field is empty" "$DRV_ERR_1"
t47_drive "" "" exit2 "$FX_VERB" "$FX_FACT" "" "$FX_DETAIL"
expect_contains "T47-f5 an empty fix" "the fix field is empty" "$DRV_ERR_1"
t47_drive "" "" exit2 "$FX_VERB" "$(printf 'two\nlines')" "$FX_FIX" "$FX_DETAIL"
expect_contains "T47-f6 a newline in the fact" "the fact field carries a newline" "$DRV_ERR_1"
t47_drive "" "" exit2 "$FX_VERB" "$FX_FACT" "$(printf 'two\nlines')" "$FX_DETAIL"
expect_contains "T47-f7 a newline in the fix" "the fix field carries a newline" "$DRV_ERR_1"
# A verb so long that no fact budget is left is the caller's value, which the library cannot
# cut, so the call is refused as today (A-T47.4).
T47_LONGVERB="$(printf 'v%.0s' $(seq 1 80))"
t47_drive "" "" exit2 "$T47_LONGVERB" "$FX_FACT" "$FX_FIX" "$FX_DETAIL"
expect_status "T47-f8 a verb that leaves no room for any fact is still refused" "2" "$DRV_RC"
expect_contains "T47-f9 …as a refusal of the call" "bionic: refuse-call refused — the user line is" "$DRV_ERR_1"
# …while a verb that leaves exactly one column cuts the fact to the ellipsis alone and the
# detail holds the whole of it.
t47_drive "" "" exit2 "$(printf 'v%.0s' $(seq 1 60))" "$FX_FACT" "$FX_FIX" "$FX_DETAIL"
expect_contains "T47-f10 a verb with one column to spare cuts the fact to the ellipsis" \
  " refused — … (add it to Suites:)" "$DRV_ERR_1"
expect_eq "T47-f11 …and the whole fact is the detail's first line" "$FX_FACT" "$(sed -n '3p' "$SANDBOX/.err")"

# --- (g) the strict setting: an over-wide line refuses the call exactly as before ---
t47_drive 1 "" exit2 "$FX_VERB" "$T47_ONE" "$FX_FIX" "$FX_DETAIL"
expect_eq "T47-g1 strict on: a fact one column over refuses the call, same text as before T47" \
  "bionic: refuse-call refused — the user line is 101 columns, max 100 (shorten the fact)" "$DRV_ERR_1"
expect_status "T47-g2 …same exit (2)" "2" "$DRV_RC"
expect_eq "T47-g3 …and one line, no detail" "1" "$DRV_ERR_LINES"
for _m in deny block; do
  t47_drive 1 "" "$_m" "$FX_VERB" "$T47_ONE" "$FX_FIX" "$FX_DETAIL"
  expect_status "T47-g4 strict on, $_m: the call is refused with exit 2, as for any malformed call" "2" "$DRV_RC"
  expect_contains "T47-g5 strict on, $_m: …the same text" "the user line is 101 columns, max 100" "$DRV_ERR_1"
done
t47_drive 1 "" exit2 "$FX_VERB" "$T47_FIT" "$FX_FIX" "$FX_DETAIL"
expect_regex "T47-g6 strict on: a line that fits is still a refusal on its own verb" "$USER_LINE_RE" "$DRV_ERR_1"
for _s in "" 0 yes UNSET; do
  t47_drive "$_s" "" exit2 "$FX_VERB" "$T47_ONE" "$FX_FIX" "$FX_DETAIL"
  expect_regex "T47-g7 BIONIC_REFUSE_STRICT='$_s' is off: the cut refusal is printed" "$USER_LINE_RE" "$DRV_ERR_1"
  expect_absent "T47-g8 …and the call is not refused" "refuse-call" "$DRV_ERR_1"
done

# --- (h) WHERE THE SETTING IS SET: on for every suite, off in a hook's environment ---
# ONE variable, READ in refuse.sh and in no other file under hooks/ or payload/, and SET only by
# the seam every suite sources. Found by `grep -L resolve-roots.sh tests/*.test.sh` (no suite
# lacks it) and by tests/run.sh sourcing it for its own environment.
SEAM="$REPO_ROOT/tests/lib/resolve-roots.sh"
expect_eq "T47-h1 a fresh shell that sources the shared seam has the strict setting on" "1" \
  "$(env -i PATH="$PATH" HOME="$SANDBOX" bash -c '. "$1" >/dev/null 2>&1; printf "%s" "${BIONIC_REFUSE_STRICT:-}"' _ "$SEAM")"
expect_eq "T47-h2 …and so does THIS suite, run alone or by tests/run.sh" "1" "${BIONIC_REFUSE_STRICT:-}"
T47_USERS="$(/usr/bin/grep -rl 'BIONIC_REFUSE_STRICT' "$REPO_ROOT/hooks/" "$REPO_ROOT/payload/" 2>/dev/null | sed "s|^$REPO_ROOT/||")"
expect_eq "T47-h3 refuse.sh is the ONE file under hooks/ and payload/ that names the setting" \
  "payload/scripts/lib/refuse.sh" "$T47_USERS"
T47_SETS="$(/usr/bin/grep -rn 'BIONIC_REFUSE_STRICT' "$REPO_ROOT/hooks/" "$REPO_ROOT/payload/" 2>/dev/null \
  | /usr/bin/grep -v ':[0-9]*:[[:space:]]*#' | /usr/bin/grep -v '\${BIONIC_REFUSE_STRICT:-}')"
expect_eq "T47-h4 …and outside its comments it only READS it, never assigns or exports it" "" "$T47_SETS"
expect_regex "T47-h5 …and the one read is there (the extractor returns something)" 'BIONIC_REFUSE_STRICT:-' \
  "$(/usr/bin/grep -n 'BIONIC_REFUSE_STRICT' "$LIB" | /usr/bin/grep -v ':[0-9]*:[[:space:]]*#')"
t47_drive UNSET "" exit2 "$FX_VERB" "$T47_ONE" "$FX_FIX" "$FX_DETAIL"
expect_regex "T47-h6 a wall run with no such variable in its environment (a hook as a user runs it) cuts, it does not self-refuse" \
  "$USER_LINE_RE" "$DRV_ERR_1"

# --- (i) THE MUTANTS. The strict guard and the detail's first line each have one. ---
mutant m-strict 's/BIONIC_REFUSE_STRICT:-/BIONIC_STRICT_THE_MUTANT_IGNORES:-/' 'BIONIC_REFUSE_STRICT:-'
M_STRICT="$MUT_PATH"
expect_true "T47-i0 the strict mutant parses" bash -n "$M_STRICT"
DRV_STRICT=1; drive "$M_STRICT" exit2 "$FX_VERB" "$T47_ONE" "$FX_FIX" "$FX_DETAIL"
expect_regex "T47-i1 MUTANT with the setting ignored, an over-wide line is cut even under strict (the strict rows discriminate)" \
  "$USER_LINE_RE" "$DRV_ERR_1"
mutant m-firstline 's/^( *)detail="\$fact_whole.*/\1:/' 'detail="$fact_whole'
M_FIRST="$MUT_PATH"
expect_true "T47-i2 the first-line mutant parses" bash -n "$M_FIRST"
DRV_STRICT=""; drive "$M_FIRST" exit2 "$FX_VERB" "$T47_ONE" "$FX_FIX" "$FX_DETAIL"; DRV_STRICT=1
expect_regex "T47-i3 MUTANT without the fact in the detail the line is still cut (the mutant runs)" "$USER_LINE_RE" "$DRV_ERR_1"
expect_absent "T47-i4 MUTANT …but the whole fact is nowhere on the wire (the first-line rows discriminate)" "$T47_ONE" "$DRV_ERR"

section "§T50 — the cut costs the line's width, not the value's length (wave-27 T50; review pass 29)"
# `bionic_trunc` drops one character at a time and re-measures the whole string each time, so
# cutting a 20,000-character fact took 43 seconds against a hook's timeout of 10. `refuse` now
# shortens the fact by BYTES, to at most four times the room it has, walking back to a whole
# character, before the cut; the whole fact is still the detail's first line. Four bytes is the
# most one character takes, so every character the cut keeps is still there: the printed line is
# what the unbounded cut would print.
#
# fails-when: a 20,000-character fact takes 5 seconds or more; the printed line differs from the
# unbounded cut's; the whole fact is not the detail's first line; the byte cut ends inside a
# character, under either locale or either shell; a fact that fits is changed; the strict setting
# no longer refuses an over-wide line, quickly.
T50_ROOM=54   # 100 columns less `bionic: run-arm refused — ` (26) and ` (add it to Suites:)` (20)
t50_bytes() { head -c "$1" /dev/zero | tr '\0' 'o'; }
T50_LONG="$(t50_bytes 20000)"
T50_PREFIX="$(t50_bytes 2000)"
expect_eq "T50-a0 fixture: the long fact is 20,000 characters" "20000" "${#T50_LONG}"

# --- (a) THE TIME, measured by the row; 5 seconds is generous, the bound was 43 seconds ---
T50_T0=$SECONDS
t47_drive "" "" exit2 "$FX_VERB" "$T50_LONG" "$FX_FIX" "$FX_DETAIL"
T50_DT=$((SECONDS - T50_T0))
expect_status "T50-a1 a 20,000-character fact is refused on its own verb, strict off" "2" "$DRV_RC"
expect_regex "T50-a2 …cut to a line in the criterion's shape" "$USER_LINE_RE" "$DRV_ERR_1"
expect_true "T50-a3 …in under 5 seconds (took ${T50_DT}s)" test "$T50_DT" -lt 5
expect_eq "T50-a4 …and the detail's first line is the whole 20,000 characters, uncut" \
  "$T50_LONG" "$(sed -n '3p' "$SANDBOX/.err")"

# --- (b) THE SAME FIRST LINE AS THE UNBOUNDED CUT, on a fact where that cut is still fast ---
T50_UNB="$(bash -c '. "$1"; bionic_trunc "$2" "$3"' _ "$LIB_DIR/width.sh" "$T50_PREFIX" "$T50_ROOM")"
expect_eq "T50-b0 fixture: the unbounded cut is 54 columns, ellipsis last (the reference is not empty)" \
  "54" "$(t47_line_cols "$T50_UNB")"
t47_drive "" "" exit2 "$FX_VERB" "$T50_PREFIX" "$FX_FIX" "$FX_DETAIL"
expect_eq "T50-b1 a 2,000-character fact prints byte for byte what the unbounded cut prints" \
  "bionic: run-arm refused — $T50_UNB (add it to Suites:)" "$DRV_ERR_1"
t47_drive "" "" exit2 "$FX_VERB" "$T47_FIT" "$FX_FIX" "$FX_DETAIL"
expect_eq "T50-b2 a fact that fits is untouched" "bionic: run-arm refused — $T47_FIT (add it to Suites:)" "$DRV_ERR_1"

# --- (c) THE BYTE CUT NEVER ENDS INSIDE A CHARACTER: _refuse_bytecut, driven directly ---
# The fact is narrow characters, then `é` (2 bytes), `日` (3) and `😀` (4) in turn; every byte limit
# from 40 to 47 puts the cut at a different offset in them, so some limit lands inside a
# character of each width. The child prints one verdict per limit: the result is a prefix of the
# fact, at most the limit in bytes and less than four bytes short of it, and decodes as UTF-8.
T50_MB="$(printf 'x%.0s' $(seq 1 38))é日😀é日😀é日😀é日😀"
cat > "$SANDBOX/t50-bytecut.sh" <<'T50_EOF'
. "$1" || exit 9
fact="$2"
for n in 40 41 42 43 44 45 46 47; do
  r="$(_refuse_bytecut "$fact" "$n")"
  b="$(printf '%s' "$r" | LC_ALL=C wc -c | tr -d ' ')"
  verdict=OK
  [ "$b" -le "$n" ] && [ "$b" -gt $((n - 4)) ] || verdict="BAD(bytes=$b)"
  case "$fact" in "$r"*) ;; *) verdict="BAD(not a prefix)" ;; esac
  printf '%s' "$r" | iconv -f UTF-8 -t UTF-8 >/dev/null 2>&1 || verdict="BAD(not UTF-8)"
  echo "n=$n $verdict"
done
T50_EOF
expect_true "T50-c0 fixture: the multi-byte fact decodes (the check can pass)" \
  bash -c 'printf "%s" "$1" | iconv -f UTF-8 -t UTF-8 >/dev/null 2>&1' _ "$T50_MB"
expect_false "T50-c0b …and a half character does not (the check can fail)" \
  bash -c 'printf "a\360\237" | iconv -f UTF-8 -t UTF-8 >/dev/null 2>&1'
for _sh in /bin/bash bash; do
  for _lc in "$T47_UTF8" C; do
    T50_OUT="$(env LC_ALL="$_lc" "$_sh" "$SANDBOX/t50-bytecut.sh" "$LIB" "$T50_MB" 2>&1)"
    expect_eq "T50-c1 [$_sh, $_lc] eight limits answered (the child ran)" "8" \
      "$(printf '%s\n' "$T50_OUT" | grep -c '^n=[0-9]* OK$')"
    expect_absent "T50-c2 [$_sh, $_lc] …and none is short, long, off the prefix or inside a character" "BAD" "$T50_OUT"
  done
done

# --- (d) THE MULTI-BYTE FACT THROUGH THE WHOLE REFUSAL, both locales: fast, whole, decodable ---
T50_MBLONG="$(printf 'é日%.0s' $(seq 1 4000))"
for _lc in "$T47_UTF8" C; do
  T50_T0=$SECONDS
  t47_drive "" "$_lc" exit2 "$FX_VERB" "$T50_MBLONG" "$FX_FIX" "$FX_DETAIL"
  T50_DT=$((SECONDS - T50_T0))
  expect_regex "T50-d1 [$_lc] an 8,000-character multi-byte fact is cut to a line in the criterion's shape" "$USER_LINE_RE" "$DRV_ERR_1"
  expect_true "T50-d2 [$_lc] …in under 5 seconds (took ${T50_DT}s)" test "$T50_DT" -lt 5
  expect_true "T50-d3 [$_lc] …the printed line decodes as UTF-8" \
    bash -c 'printf "%s\n" "$1" | iconv -f UTF-8 -t UTF-8 >/dev/null 2>&1' _ "$DRV_ERR_1"
  expect_eq "T50-d4 [$_lc] …and the whole fact is the detail's first line" "$T50_MBLONG" "$(sed -n '3p' "$SANDBOX/.err")"
done

# --- (e) THE STRICT SETTING: nothing changes, and the refusal is quick ---
T50_T0=$SECONDS
t47_drive 1 "" exit2 "$FX_VERB" "$T50_LONG" "$FX_FIX" "$FX_DETAIL"
T50_DT=$((SECONDS - T50_T0))
expect_eq "T50-e1 strict on: a 20,000-character fact refuses the call, the same text as before" \
  "bionic: refuse-call refused — the user line is 20046 columns, max 100 (shorten the fact)" "$DRV_ERR_1"
expect_status "T50-e2 …same exit (2)" "2" "$DRV_RC"
expect_true "T50-e3 …in under 5 seconds (took ${T50_DT}s)" test "$T50_DT" -lt 5

section "§T58 — the same first line on multi-byte facts, and a pre-cut that leaves nothing (wave-27 T58; review pass 34 S3, N1)"
# The b rows above use a run of `o`, one byte a column, so a pre-cut of three times the room, or of
# one byte past it, still hands the cut every character it keeps: those rows cannot fail on the
# multiplier. A run of `—` (three bytes, one column) or of `é` (two bytes) can: the pre-cut must
# leave more columns than the room, or the fact fits, prints whole and loses its ellipsis. And a
# fact the walk-back empties (continuation bytes with no lead byte) prints the ellipsis where the
# fact stood, never nothing; the whole fact is still the detail's first line.
#
# fails-when: a 2,000-character fact of `—` or of `é` prints a first line other than the unbounded
# cut's; a copy with the multiplier three, or `room + 1`, prints the same line as the shipped
# library (the rows could not fail); a run of continuation bytes prints an empty fact.
T58_ELL='…'
for _glyph in '—' 'é'; do
  T58_FACT="$(printf "${_glyph}%.0s" $(seq 1 2000))"
  T58_UNB="$(bash -c '. "$1"; bionic_trunc "$2" "$3"' _ "$LIB_DIR/width.sh" "$T58_FACT" "$T50_ROOM")"
  expect_eq "T58-b0 [$_glyph] fixture: the unbounded cut is a cut (shorter than the fact), ellipsis last" "yes|yes" \
    "$([ "${#T58_UNB}" -lt "${#T58_FACT}" ] && echo yes)|$([ "${T58_UNB%"$T58_ELL"}" != "$T58_UNB" ] && echo yes)"
  t47_drive "" "" exit2 "$FX_VERB" "$T58_FACT" "$FX_FIX" "$FX_DETAIL"
  expect_eq "T58-b1 [$_glyph] a 2,000-character fact prints byte for byte what the unbounded cut prints" \
    "bionic: run-arm refused — $T58_UNB (add it to Suites:)" "$DRV_ERR_1"
done

# THE TWO DOCTORED MULTIPLIERS: each copy still refuses with a line in the criterion's shape, and
# its line for the `—` fact is not the unbounded cut's, so T58-b1 [—] goes red on it; `room + 1`
# also turns T58-b1 [é] red.
T58_EM="$(printf '—%.0s' $(seq 1 2000))"; T58_E2="$(printf 'é%.0s' $(seq 1 2000))"
T58_UNB_EM="$(bash -c '. "$1"; bionic_trunc "$2" "$3"' _ "$LIB_DIR/width.sh" "$T58_EM" "$T50_ROOM")"
T58_UNB_E2="$(bash -c '. "$1"; bionic_trunc "$2" "$3"' _ "$LIB_DIR/width.sh" "$T58_E2" "$T50_ROOM")"
mutant m-times3 's/\$\(\(room \* 4\)\)/$((room * 3))/' '$((room * 4))'
M_TIMES3="$MUT_PATH"
mutant m-plus1 's/\$\(\(room \* 4\)\)/$((room + 1))/' '$((room * 4))'
M_PLUS1="$MUT_PATH"
expect_true "T58-m0 the two mutants parse, and each holds its multiplier" \
  bash -c 'bash -n "$1" && bash -n "$2" && grep -qF "\$((room * 3))" "$1" && grep -qF "\$((room + 1))" "$2"' _ "$M_TIMES3" "$M_PLUS1"
DRV_STRICT=""; drive "$M_TIMES3" exit2 "$FX_VERB" "$T58_EM" "$FX_FIX" "$FX_DETAIL"; DRV_STRICT=1
expect_regex "T58-m1 MUTANT ×3 the line is still a refusal line (the mutant runs)" "$USER_LINE_RE" "$DRV_ERR_1"
expect_ne "T58-m2 MUTANT ×3 …but its — line is not the unbounded cut's (T58-b1 [—] discriminates)" \
  "bionic: run-arm refused — $T58_UNB_EM (add it to Suites:)" "$DRV_ERR_1"
DRV_STRICT=""; drive "$M_PLUS1" exit2 "$FX_VERB" "$T58_EM" "$FX_FIX" "$FX_DETAIL"; DRV_STRICT=1
expect_regex "T58-m3 MUTANT +1 the line is still a refusal line (the mutant runs)" "$USER_LINE_RE" "$DRV_ERR_1"
expect_ne "T58-m4 MUTANT +1 …but its — line is not the unbounded cut's (T58-b1 [—] discriminates)" \
  "bionic: run-arm refused — $T58_UNB_EM (add it to Suites:)" "$DRV_ERR_1"
DRV_STRICT=""; drive "$M_PLUS1" exit2 "$FX_VERB" "$T58_E2" "$FX_FIX" "$FX_DETAIL"; DRV_STRICT=1
expect_regex "T58-m5 MUTANT +1 the é line is a refusal line too" "$USER_LINE_RE" "$DRV_ERR_1"
expect_ne "T58-m6 MUTANT +1 …and not the unbounded cut's (T58-b1 [é] discriminates)" \
  "bionic: run-arm refused — $T58_UNB_E2 (add it to Suites:)" "$DRV_ERR_1"

# THE EMPTIED FACT: 400 continuation bytes, no lead byte, both locales.
T58_CONT="$(printf '\200%.0s' $(seq 1 400))"
expect_eq "T58-n0 fixture: the fact is 400 bytes, every one a continuation byte" "400|0" \
  "$(printf '%s' "$T58_CONT" | LC_ALL=C wc -c | tr -d ' ')|$(printf '%s' "$T58_CONT" | LC_ALL=C tr -d '\200' | LC_ALL=C wc -c | tr -d ' ')"
for _lc in C "$T47_UTF8"; do
  t47_drive "" "$_lc" exit2 "$FX_VERB" "$T58_CONT" "$FX_FIX" "$FX_DETAIL"
  expect_eq "T58-n1 [$_lc] a fact the pre-cut empties prints the ellipsis where the fact stood" \
    "bionic: run-arm refused — … (add it to Suites:)" "$DRV_ERR_1"
  expect_eq "T58-n2 [$_lc] …and the whole fact is still the detail's first line" "$T58_CONT" "$(sed -n '3p' "$SANDBOX/.err")"
done

section "§ROOT — the fix line's pieces live beside the renderer (wave-24 T13, D10)"
# Moved from lib/walls.sh so the landing refusal in lib/stop.sh prints the same root and the
# same quoting the budget arm does. Each answer is read through a fresh shell that sources
# only this library.
fixpiece() {  # <BIONIC_LIB or ""> <function> [args…]
  local lib="$1"; shift
  BIONIC_LIB="$lib" bash -c '. "$1" || exit 9; shift; "$@"' _ "$LIB" "$@" 2>&1
}
expect_eq "R1 the plugin root is the tree the library was loaded from" \
  "$(cd "$LIB_DIR/../.." && pwd)" "$(fixpiece "$LIB_DIR" refuse_plugin_root)"
expect_eq "R2 …and the placeholder only when the loader's variable is absent" \
  "<plugin-root>" "$(fixpiece "" refuse_plugin_root)"
expect_eq "R3 a word a shell would split is one single-quoted argument" "'a b.sh'" "$(fixpiece "" refuse_shell_word 'a b.sh')"
expect_eq "R4 …a plain word stays bare" "w-1" "$(fixpiece "" refuse_shell_word w-1)"
expect_eq "R5 …an empty word prints the placeholder" "<name>" "$(fixpiece "" refuse_shell_word '' '<name>')"
expect_eq "R6 refuse_quote always quotes, and an embedded quote survives a shell's reading" \
  "it's" "$(eval "printf '%s' $(fixpiece "" refuse_quote "it's")")"
expect_eq "R7 …and quotes a plain word too" "'w-1'" "$(fixpiece "" refuse_quote w-1)"

section "§INV — every refusal site prints its fix or says why it cannot (wave-24 T13, D10, AC-6.6)"
# fails-when: a site in the four files has no bullet in the inventory carrying `— fix:` or
# `— none:`. A SITE is a `fold_block`, `refuse`, `dp_finding`, `budget_deny` or `deny` call at
# the start of a statement (or after `&&`, `||`, `;` or a case label), and its key is its first
# source line, trimmed. A key shared by n sites needs n bullets.
INV_FILE="$REPO_ROOT/tests/fixtures/refusal-inventory.md"
inv_sites() {  # <source file> -> each site's first line, trimmed, one per line
  awk '
    /^[[:space:]]*#/ { next }
    match($0, /(^|[[:space:];&|)])(fold_block|refuse|dp_finding|budget_deny|deny)[[:space:]]+(exit2|deny|block|"|\\|\$)/) {
      t = $0; sub(/^[[:space:]]+/, "", t); sub(/[[:space:]]+$/, "", t); print t
    }' "$1"
}
inv_missing() {  # <inventory> <section label> <source file> -> each site key short of a fix/none bullet
  # `FILENAME == ARGV[1]`, NEVER `FNR == NR`: an EMPTY inventory leaves NR at zero into the
  # second file, so `FNR == NR` would read every site as inventory and report nothing missing.
  awk -v lab="$2" '
    FILENAME == ARGV[1] {
      if (index($0, "## ") == 1) { sec = substr($0, 4); next }
      if (sec == lab && index($0, "- `") == 1 && (index($0, " — fix:") || index($0, " — none:"))) b[++nb] = $0
      next
    }
    { want[$0]++ }
    END {
      for (t in want) {
        c = 0
        for (i = 1; i <= nb; i++) if (index(b[i], "`" t "`")) c++
        if (c < want[t]) print t
      }
    }' "$1" <(inv_sites "$3")
}
require_helpers inv_sites inv_missing

# THE CHECKER CAN FAIL — a synthetic source and inventory, beside the real run. A site with no
# bullet, a bullet that carries neither marker, and a key shared by two sites with one bullet
# are each reported; the covered site is not. An EMPTY inventory reports every site.
INV_SYN="$(mktemp -d)"
cat > "$INV_SYN/src.sh" <<'SYN'
# fold_block exit2 x "a comment is no site" "x" \
  fold_block exit2 x "covered" "fix it" \
  refuse exit2 x "uncovered" "fix it" "d"
  dp_finding "unmarked" "fix it" "d"
  [ -n "$a" ] || deny "twice" "fix it" "d"
  [ -n "$a" ] || deny "twice" "fix it" "d"
  echo "would otherwise refuse the next commit"
SYN
cat > "$INV_SYN/inv.md" <<'SYN'
## src.sh

- `fold_block exit2 x "covered" "fix it" \` — covered — fix: `x`
- `dp_finding "unmarked" "fix it" "d"` — a bullet with no marker
- `[ -n "$a" ] || deny "twice" "fix it" "d"` — none: one of two
SYN
INV_SYN_SITES="$(inv_sites "$INV_SYN/src.sh")"
expect_eq "INV-c1 the extractor reads five sites, never a comment or prose" "5" \
  "$(printf '%s\n' "$INV_SYN_SITES" | awk 'NF { c++ } END { print c + 0 }')"
INV_SYN_MISS="$(inv_missing "$INV_SYN/inv.md" src.sh "$INV_SYN/src.sh")"
expect_contains "INV-c2 a site with no bullet is reported" 'refuse exit2 x "uncovered"' "$INV_SYN_MISS"
expect_contains "INV-c3 a bullet with neither marker does not cover its site" 'dp_finding "unmarked"' "$INV_SYN_MISS"
expect_contains "INV-c4 one bullet does not cover two sites that share its key" '[ -n "$a" ] || deny "twice"' "$INV_SYN_MISS"
expect_absent "INV-c5 …and the covered site is not reported" '"covered"' "$INV_SYN_MISS"
: > "$INV_SYN/empty.md"
expect_eq "INV-c6 an empty inventory reports every key (five sites, four distinct keys)" "4" \
  "$(inv_missing "$INV_SYN/empty.md" src.sh "$INV_SYN/src.sh" | awk 'NF { c++ } END { print c + 0 }')"
rm -rf "$INV_SYN"

# THE INVENTORY IS TRACKED (A-orch-40, A-T13.10): `tests/fixtures/refusal-inventory.md`, read from
# this suite's own repo root. An ABSENT inventory is a failure, never an advisory: a clone that
# lost the file has lost the check, and a green suite would say otherwise.
inv_check() {  # <inventory> -> one line per problem: the file absent, or a site short of a bullet
  local inv="$1" src
  [ -f "$inv" ] || { printf 'absent: %s\n' "$inv"; return 0; }
  for src in payload/scripts/lib/walls.sh payload/scripts/lib/stop.sh \
             hooks/dispatch-preflight.sh hooks/stop-guard.sh; do
    inv_missing "$inv" "$src" "$REPO_ROOT/$src" | sed "s|^|$src: |"
  done
}
expect_contains "INV-c7 an absent inventory is reported, so the check goes red" \
  "absent: $REPO_ROOT/tests/fixtures/no-such-inventory.md" \
  "$(inv_check "$REPO_ROOT/tests/fixtures/no-such-inventory.md")"
for _inv_src in payload/scripts/lib/walls.sh payload/scripts/lib/stop.sh \
                hooks/dispatch-preflight.sh hooks/stop-guard.sh; do
  _inv_n="$(inv_sites "$REPO_ROOT/$_inv_src" | awk 'NF { c++ } END { print c + 0 }')"
  expect_true "INV ${_inv_src}: the extractor finds its refusal sites (${_inv_n})" test "$_inv_n" -gt 0
done
expect_eq "INV the tracked inventory exists and every site has a fix line or a reason" "" \
  "$(inv_check "$INV_FILE")"

# THE WAVE ADDS NO WALL (wave-28 T3; REQ-5 AC-5.4, D9). The landing line is a verb's work, never a
# wall's: no shipped hook gains an arm that enforces the queue. Read as a CEILING on the four wall
# files' refusal sites: 1.12.0 held 122 (walls.sh 60, stop.sh 13, dispatch-preflight.sh 40,
# stop-guard.sh 9, by `inv_sites` over `git show v1.12.0:<file>`), and the wave's one new non-verb
# line is REQ-10's door, whose bullet names it. The hand landing joins ARM A's existing site (its
# first line unchanged), so it adds none. And `hooks/hooks.json` registers no new blocking hook: every
# registration on an event that can refuse is one 1.12.0 shipped.
INV_W28_BASE=122
inv_w28_sites() {  # <root> -> the four wall files' refusal sites, counted
  local r="$1" f n=0 c
  for f in payload/scripts/lib/walls.sh payload/scripts/lib/stop.sh hooks/dispatch-preflight.sh hooks/stop-guard.sh; do
    c="$(inv_sites "$r/$f" | awk 'NF { c++ } END { print c + 0 }')"; n=$((n + c))
  done
  printf '%s' "$n"
}
# AND T7's FOUR (wave-28 T7; D4, D17; ruling A-orch-88): the brief check inside the dispatch wall gains
# four refusals, a writer binding a row with no Lands-on: line, none with no reason, a suite outside the
# row's set, and a Row: naming no plan row. They are brief-check refusals, not a wall that enforces the
# queue, so they ride on top of the ceiling as the door does: one per inventory bullet tagged
# `(wave-28 T7`, at most four. A fifth site with no tagged bullet still fails the pin.
INV_W28_T7_MAX=4
# AND T55's ONE (wave-28 T55; D4): the dispatch wall refuses a Row: that names a row other than the one
# the agent's name matches. It is a brief-check refusal beside T7's, not a wall that enforces the queue,
# so it rides on top as T7's four do: one per inventory bullet tagged `(wave-28 T55`, at most one.
INV_W28_T55_MAX=1
# AND T58's ONE (wave-28 T58; D8): the dispatch wall refuses a name that matches more than one plan row
# when the brief has no Row: to say which. A brief-check refusal beside T55's, one per inventory bullet
# tagged `(wave-28 T58`, at most one.
INV_W28_T58_MAX=1
# AND T70's SIX (wave-28 T70; REQ-5, REQ-6, D8; A-orch-231): the dispatch wall and the stop guard stop
# admitting what they could not record or judge. The dispatch wall refuses a launch whose roster path is a
# link, whose row did not build, or whose roster cannot be written, and refuses first when its own
# deadline passes (four sites); the stop guard refuses first when its own deadline passes and refuses a
# recorded unrostered stop it cannot write onto the roster (two). Each is a refusal beside T58's, one per
# inventory bullet tagged `(wave-28 T70`, at most six.
INV_W28_T70_MAX=6
# THE ALLOWANCE IS ONE TABLE (wave-28 T58, read-structure-p31 #4): `<inventory tag>|<most bullets that
# many sites may carry>`, read by `inv_w28_ceiling`. A new row adds its constant and one line here.
INV_W28_TAGGED="REQ-10's door|1
(wave-28 T7|$INV_W28_T7_MAX
(wave-28 T55|$INV_W28_T55_MAX
(wave-28 T58|$INV_W28_T58_MAX
(wave-28 T70|$INV_W28_T70_MAX"
# A TAG ENDING IN A DIGIT IS NOT THE PREFIX OF A LONGER NUMBER (wave-28 T70; A-orch-230 b): `(wave-28 T7`
# is counted in a bullet tagged `(wave-28 T7)` or `(wave-28 T7;`, never in one tagged `(wave-28 T70)`, which
# a plain substring match counted under T7 and turned this pin red the day a row with a longer id landed.
# A bullet is counted once, however many times it carries the tag.
inv_tag_count() {  # <tag> <inventory> -> the bullets carrying the tag
  awk -v tag="$1" '
    { line = $0; ld = (substr(tag, length(tag)) ~ /[0-9]/)
      while ((i = index(line, tag)) > 0) {
        nx = substr(line, i + length(tag), 1)
        if (!(ld && nx ~ /[0-9]/)) { c++; break }
        line = substr(line, i + length(tag))
      }
    }
    END { print c + 0 }' "$2" 2>/dev/null
}
inv_w28_ceiling() {  # <inventory> -> 1.12.0's sites, plus each tagged row's, as the inventory tags them
  local n=0 tag max c
  while IFS='|' read -r tag max; do
    c="$(inv_tag_count "$tag" "$1")"; [ "${c:-0}" -le "$max" ] || c="$max"
    n=$((n + ${c:-0}))
  done <<EOF
$INV_W28_TAGGED
EOF
  printf '%s' $((INV_W28_BASE + n))
}
inv_w28_excess() {  # <root> <inventory> -> a line when the sites pass 1.12.0's but for the door's one and T7's
  local n c
  n="$(inv_w28_sites "$1")"; c="$(inv_w28_ceiling "$2")"
  [ "$n" -le "$c" ] || printf 'sites=%s over %s: 1.12.0 %s plus the door, T7, T55, T58 and T70, as tagged\n' "$n" "$c" "$INV_W28_BASE"
}
INV_W28_N="$(inv_w28_sites "$REPO_ROOT")"
expect_true "INV-W28a precondition: the four wall files' sites are read (${INV_W28_N})" test "$INV_W28_N" -gt 0
expect_eq "INV-W28t7 precondition: the inventory carries T7's four tagged bullets" "4" \
  "$(inv_tag_count '(wave-28 T7' "$INV_FILE")"
expect_eq "INV-W28t55 precondition: the inventory carries T55's one tagged bullet" "1" \
  "$(inv_tag_count '(wave-28 T55' "$INV_FILE")"
expect_eq "INV-W28t58 precondition: the inventory carries T58's one tagged bullet" "1" \
  "$(inv_tag_count '(wave-28 T58' "$INV_FILE")"
expect_eq "INV-W28t70 precondition: the inventory carries T70's six tagged bullets" "6" \
  "$(inv_tag_count '(wave-28 T70' "$INV_FILE")"
expect_eq "INV-W28t7b the tag count reads a tag as a whole number: T7's four bullets, not T70's beside them" "4" \
  "$(inv_tag_count '(wave-28 T7' "$INV_FILE")"
expect_eq "INV-W28a no wall file gains a refusal site beyond 1.12.0's, but REQ-10's door, T7's four, T55's one, T58's one and T70's six" "" \
  "$(inv_w28_excess "$REPO_ROOT" "$INV_FILE")"
INV_W28_SYN="$(mktemp -d)"
for _f in payload/scripts/lib/walls.sh payload/scripts/lib/stop.sh hooks/dispatch-preflight.sh hooks/stop-guard.sh; do
  mkdir -p "$INV_W28_SYN/${_f%/*}"; cp "$REPO_ROOT/$_f" "$INV_W28_SYN/$_f"
done
# AS MANY ARMS AS PASS THE CEILING FROM WHERE THE TREE STANDS (wave-28 T9): a row that removes
# refusal sites (T9 took out two) leaves the tree under 1.12.0's count, so a fixed two would not
# reach past it. One arm more than the room left under the ceiling, the door's, T7's, T55's and T58's included (the
# ceiling is read from the inventory as inv_w28_excess reads it, so the two cannot part).
_inv_w28_k=$(( $(inv_w28_ceiling "$INV_FILE") + 1 - INV_W28_N )); [ "$_inv_w28_k" -ge 1 ] || _inv_w28_k=1
while [ "$_inv_w28_k" -gt 0 ]; do
  printf '%s\n' "  fold_block exit2 queue \"planted arm ${_inv_w28_k}\" \"say ready\" \"planted\"" >> "$INV_W28_SYN/payload/scripts/lib/walls.sh"
  _inv_w28_k=$((_inv_w28_k - 1))
done
expect_contains "INV-W28b a planted queue arm past the ceiling is reported, so the check can fail" "sites=" \
  "$(inv_w28_excess "$INV_W28_SYN" "$INV_FILE")"
rm -rf "$INV_W28_SYN"
# THE TASK-ENTRY DUTY IS THE DUTY WALL'S OWN (wave-28 T38; REQ-13 AC-13.2, D30). A dispatch turn's
# task entries are a second trigger of the task-list duty, refused through its existing forwarder:
# lib/stop.sh gains no refusal site over 1.12.0's 13 (`inv_sites` over `git show v1.12.0:<file>`),
# and the duty's first line is a FACT the forwarder carries, never a site of its own, so the
# inventory's `lib/stop.sh` section gains no line. The duty itself went with the Patrol's entry
# duty (wave-31 T32), and with it the forwarder INV-T38b pinned; INV-T38c and d stay, the ceiling
# and the planted site. fails-when: lib/stop.sh passes 13 sites, or the entry duty's fact is
# spelled on a site.
INV_T38_BASE=13
INV_T38_STOP="$REPO_ROOT/payload/scripts/lib/stop.sh"
INV_T38_SITES="$(inv_sites "$INV_T38_STOP")"
INV_T38_N="$(printf '%s\n' "$INV_T38_SITES" | awk 'NF { c++ } END { print c + 0 }')"
expect_true "INV-T38a precondition: lib/stop.sh's refusal sites are read (${INV_T38_N})" test "$INV_T38_N" -gt 0
expect_true "INV-T38a lib/stop.sh gains no refusal site over 1.12.0's ${INV_T38_BASE}" test "$INV_T38_N" -le "$INV_T38_BASE"
expect_absent "INV-T38c …and no refusal site spells it" "entry is not in progress" "$INV_T38_SITES"
INV_T38_SYN="$(mktemp -d)"
cp "$INV_T38_STOP" "$INV_T38_SYN/stop.sh"
printf '%s\n' "  fold_block block stop \"a dispatched row's entry is not in progress\" \"TaskUpdate each to in_progress\" \"x\"" \
  >> "$INV_T38_SYN/stop.sh"
INV_T38_SYN_SITES="$(inv_sites "$INV_T38_SYN/stop.sh")"
expect_contains "INV-T38d a planted entry site is read by the extractor, so INV-T38c can fail" \
  "entry is not in progress" "$INV_T38_SYN_SITES"
expect_true "INV-T38d …and it puts lib/stop.sh one site past what it was, so INV-T38a can fail" \
  test "$(printf '%s\n' "$INV_T38_SYN_SITES" | awk 'NF { c++ } END { print c + 0 }')" -eq $((INV_T38_N + 1))
rm -rf "$INV_T38_SYN"
# The events a hook can refuse on, and every registration 1.12.0 shipped on them.
INV_W28_HOOKS='PermissionRequest - ${CLAUDE_PLUGIN_ROOT}/hooks/permission-answer.sh
PreToolUse Agent ${CLAUDE_PLUGIN_ROOT}/hooks/dispatch-preflight.sh
PreToolUse Bash ${CLAUDE_PLUGIN_ROOT}/hooks/bash-walls.sh
PreToolUse Skill ${CLAUDE_PLUGIN_ROOT}/hooks/engage.sh
PreToolUse TaskStop ${CLAUDE_PLUGIN_ROOT}/hooks/stop-guard.sh
PreToolUse Write|Edit ${CLAUDE_PLUGIN_ROOT}/hooks/canonical-sdlc-governing-skill.sh
Stop - ${CLAUDE_PLUGIN_ROOT}/hooks/stop.sh
SubagentStop - ${CLAUDE_PLUGIN_ROOT}/hooks/agent-context-guard.sh ${CLAUDE_PLUGIN_ROOT}/hooks/stop.sh
UserPromptExpansion - ${CLAUDE_PLUGIN_ROOT}/hooks/engage.sh'
inv_w28_blocking() {  # <hooks.json> -> each registration on an event that can refuse, sorted
  jq -r '.hooks | to_entries[] | select(.key | test("^(PreToolUse|PermissionRequest|Stop|SubagentStop|UserPromptSubmit|UserPromptExpansion)$"))
    | .key as $e | .value[] | (.matcher // "-") as $m | .hooks[] | "\($e) \($m) \(.command)"' "$1" 2>/dev/null | LC_ALL=C sort
}
INV_W28_REG="$(inv_w28_blocking "$REPO_ROOT/hooks/hooks.json")"
expect_contains "INV-W28c precondition: the blocking registrations are read" "PreToolUse Bash" "$INV_W28_REG"
expect_eq "INV-W28c hooks.json registers no blocking hook 1.12.0 did not" "" \
  "$(comm -23 <(printf '%s\n' "$INV_W28_REG") <(printf '%s\n' "$INV_W28_HOOKS" | LC_ALL=C sort))"

finish
