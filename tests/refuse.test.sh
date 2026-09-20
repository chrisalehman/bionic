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
DRV_RC=0; DRV_OUT=""; DRV_ERR=""; DRV_ERR_LINES=0; DRV_ERR_1=""
drive_v() {
  local v="$1" lib="$2"; shift 2
  BIONIC_WALL_VERBOSE="$v" bash "$WALL" "$lib" "$@" >"$SANDBOX/.out" 2>"$SANDBOX/.err"
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

# A MANY-LINE DETAIL ON THE `deny` WIRE (wave-12 T17). The dispatch gate's combined
# brief-shape refusal is a FINDINGS LIST — a count header and one block per fault, tens of
# lines — and it rides this field because it is the one the measurement proved reaches the
# model in full. Three properties it depends on, pinned here rather than inferred from the
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

# --- (d) THE SPLIT IS UNCHANGED FOR THE MODEL-ONLY CHANNELS. `deny` and `block` keep
# their `detail_to_user=no` cell, so the reader still gets one line there, and their
# model wire still carries the whole list — the property wave-12 T17's combined refusal
# depends on (tests/fold.test.sh 13i, tests/dispatch-preflight.test.sh §combined-deny). ---
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

finish
