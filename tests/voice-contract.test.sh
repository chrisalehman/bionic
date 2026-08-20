#!/usr/bin/env bash
# THE VOICE CONTRACT — epic-17 wave-06 slice S1 (spec R3, AC-5/AC-6; design ledger D-C).
#
# WHAT THIS SUITE OWNS. The presentation contract that governs what a user SEES when any
# bionic command runs, and the one place it is written down.
#
# WHY IT IS A RENDERED BLOCK AND NOT FOUR PARAGRAPHS. The four shipped command files under
# payload/commands/ are the whole of what the model reads before acting on a bionic command,
# so the contract has to be in all four. Four pasted copies pinned equal is identity by
# ENFORCEMENT — green until someone edits three of the four. D-C (Chris, 2026-08-20: "Why
# not #2? That still seems cleaner. Consistency of approach.") chose identity by
# CONSTRUCTION instead: one source at agents-src/blocks/voice-contract.md, rendered into all
# four by the same pipeline that renders the six agent role files.
#
# THE DIVISION OF LABOUR WITH tests/agent-render.test.sh. That suite owns STALENESS — that
# the committed command files are the render of the committed sources, in both directions,
# proven by planting each drift into a hermetic copy. This suite owns PRESENCE and CONTENT:
# that each command file actually carries the block (a template can lose its INJECT
# directive and --check stays perfectly green, because output and source still agree — on a
# file with the contract missing), that help.md carries the render-in-full instruction AC-1
# turns on, and that no internal vocabulary leaks into the command surface outside the
# block. Construction propagates a gutted block as faithfully as a good one.
#
# THE BLOCK IS EXEMPT FROM ITS OWN BAN, AND THAT EXEMPTION IS LOAD-BEARING. The contract's
# text quotes the very words it forbids ("Say nothing about shells, stdin, pipes …"), so the
# vocabulary lint skips the block's own body. An exemption that never covers anything is a
# silent hole, so §D asserts the block body really does contain a banned token — if the
# contract is ever reworded to stop quoting them, this arm says so rather than letting the
# exemption quietly become decoration.
#
# HERMETIC. Reads committed files; every mutation in §E goes into a scratch copy. No
# network, no `claude` CLI, nothing under payload/ is opened for writing.
#
# ASSERTION-HELPER RACE. Pipe-free by construction (tests/assert-helper-race.test.sh):
# containment is tested in-process with bash `[[ == * ]]`, and every grep runs against a
# FILE argument, never against another process's stdout. Nothing here to pin there.
#
# Usage: bash tests/voice-contract.test.sh
# Registered by name in tests/run.sh (tests/*.test.sh is NOT auto-globbed).

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"

REPO="${BIONIC_SCRIPTS_DIR}"
BLOCK="${REPO}/agents-src/blocks/voice-contract.md"
BANNED_LIST="${REPO}/tests/fixtures/banned-display-vocabulary.txt"
COMMANDS_DIR="${REPO}/payload/commands"
COMMANDS="help setup doctor remove"

PASS=0; FAIL=0; TOTAL=0
ok() { TOTAL=$((TOTAL + 1)); PASS=$((PASS + 1)); echo "PASS: $1"; }
no() { TOTAL=$((TOTAL + 1)); FAIL=$((FAIL + 1)); echo "FAIL: $1"; [ -n "${2:-}" ] && echo "      $2"; return 0; }

expect_true()     { local label="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$label"; else no "$label"; fi; }
expect_eq()       { local label="$1" want="$2" got="$3"; if [ "$got" = "$want" ]; then ok "$label"; else no "$label" "expected='$want' actual='$got'"; fi; }
expect_contains() { local label="$1" needle="$2" hay="$3"; if [[ "$hay" == *"$needle"* ]]; then ok "$label"; else no "$label" "expected to contain '$needle'"; fi; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

BEGIN_MARKER='<!-- VOICE-CONTRACT-BEGIN -->'
END_MARKER='<!-- VOICE-CONTRACT-END -->'

# ---------------------------------------------------------------------------
# Extractors. Each takes a FILE and writes to stdout; no pipes into the callers.
# ---------------------------------------------------------------------------

# block_body <file>: the lines strictly between the two markers.
block_body() {
  awk -v b="$BEGIN_MARKER" -v e="$END_MARKER" '
    index($0, b) { f = 1; next }
    index($0, e) { f = 0 }
    f { print }
  ' "$1"
}

# outside_block <file>: the file with the marker span (markers included) removed. This is
# the text the vocabulary lint judges — the contract's own quotation of the banned words is
# not a leak of them.
outside_block() {
  awk -v b="$BEGIN_MARKER" -v e="$END_MARKER" '
    index($0, b) { f = 1; next }
    index($0, e) { f = 0; next }
    !f { print }
  ' "$1"
}

# banned_tokens: the fixture's tokens, comments and blank lines dropped. The format rule is
# stated in the fixture's own header, because slice S4's script-output lint reads the same
# file and has to parse it the same way.
banned_tokens() {
  awk '
    { sub(/^[[:space:]]+/, "") }
    /^#/ { next }
    /^$/ { next }
    { print }
  ' "$BANNED_LIST"
}

# banned_hits <file>: every banned token that appears outside the block, one per line.
# Case-insensitive substring matching (`grep -iF` against a FILE argument), matching the
# rule the fixture documents.
banned_hits() {
  local f="$1" scratch="$TMP/outside.$$" tok
  outside_block "$f" > "$scratch"
  while IFS= read -r tok; do
    [ -n "$tok" ] || continue
    if grep -iqF -- "$tok" "$scratch"; then printf '%s\n' "$tok"; fi
  done < "$TMP/banned-tokens.txt"
  rm -f "$scratch"
}

# ---------------------------------------------------------------------------
echo ""
echo "=== A — the two sources exist ==="
# ---------------------------------------------------------------------------

expect_true "agents-src/blocks/voice-contract.md exists and is non-empty" test -s "$BLOCK"
expect_true "tests/fixtures/banned-display-vocabulary.txt exists and is non-empty" test -s "$BANNED_LIST"

if [ -s "$BANNED_LIST" ]; then
  banned_tokens > "$TMP/banned-tokens.txt"
  TOKEN_COUNT="$(grep -c . "$TMP/banned-tokens.txt" 2>/dev/null | tr -d ' ')"
  if [ "${TOKEN_COUNT:-0}" -ge 1 ]; then
    ok "the banned list parses to at least one token (got $TOKEN_COUNT)"
  else
    no "the banned list parses to at least one token" "parsed 0 — comment/blank handling changed?"
  fi
else
  : > "$TMP/banned-tokens.txt"
fi

# ---------------------------------------------------------------------------
echo ""
echo "=== B — all four command files carry the contract, byte-identically (AC-6) ==="
# ---------------------------------------------------------------------------
#
# The block source with trailing blank lines normalised away is exactly what render.sh
# emits between the markers, so this comparison is the rendered-vs-source identity stated
# on the SHIPPED side: whatever the pipeline did, this is what the model will read.

if [ -s "$BLOCK" ]; then
  printf '%s\n' "$(cat "$BLOCK")" > "$TMP/block-canonical.txt"
else
  : > "$TMP/block-canonical.txt"
fi

for c in $COMMANDS; do
  f="$COMMANDS_DIR/$c.md"
  if [ ! -f "$f" ]; then
    no "payload/commands/$c.md exists"
    continue
  fi
  ok "payload/commands/$c.md exists"

  text="$(cat "$f")"
  expect_contains "$c.md: opens the contract with $BEGIN_MARKER" "$BEGIN_MARKER" "$text"
  expect_contains "$c.md: closes the contract with $END_MARKER"  "$END_MARKER"   "$text"

  block_body "$f" > "$TMP/$c-body.txt"
  if [ ! -s "$TMP/$c-body.txt" ]; then
    no "$c.md: the contract body is present and non-empty" "nothing between the markers"
  elif cmp -s "$TMP/$c-body.txt" "$TMP/block-canonical.txt"; then
    ok "$c.md: the contract body is byte-identical to blocks/voice-contract.md"
  else
    no "$c.md: the contract body is byte-identical to blocks/voice-contract.md" \
       "$(diff -u "$TMP/block-canonical.txt" "$TMP/$c-body.txt" | head -20)"
  fi
done

# ---------------------------------------------------------------------------
echo ""
echo "=== C — help.md's render-in-full instruction (AC-1) ==="
# ---------------------------------------------------------------------------
#
# AC-1's defect is MODEL behaviour, not text baked into the file: with no instruction to
# render the page every time, a second invocation is exactly the case a model compresses
# into "same page as before". The instruction is the fix, so the instruction is what a
# hermetic suite can pin; the readback of two live invocations is the T3 half.

HELP_MD="$COMMANDS_DIR/help.md"
if [ -f "$HELP_MD" ]; then
  HELP_TEXT="$(cat "$HELP_MD")"
  expect_contains "help.md instructs a full render on every invocation" \
    "every time this command runs" "$HELP_TEXT"
  expect_contains "help.md forbids a back-reference to an earlier rendering" \
    "never summarize it or refer back" "$HELP_TEXT"
else
  no "payload/commands/help.md exists (§C skipped)"
fi

# ---------------------------------------------------------------------------
echo ""
echo "=== D — no internal vocabulary on the command surface (AC-6) ==="
# ---------------------------------------------------------------------------

# D0 — the exemption is load-bearing: the block really does quote a banned word. Without
# this arm, "skip the block" could become a skip of nothing and no one would notice.
if [ -s "$BLOCK" ]; then
  QUOTED=""
  while IFS= read -r tok; do
    [ -n "$tok" ] || continue
    if grep -iqF -- "$tok" "$BLOCK"; then QUOTED="$QUOTED $tok"; fi
  done < "$TMP/banned-tokens.txt"
  if [ -n "$QUOTED" ]; then
    ok "the contract quotes the vocabulary it bans, so the block exemption covers something ($QUOTED)"
  else
    no "the contract quotes the vocabulary it bans, so the block exemption covers something" \
       "no banned token appears in the block — the exemption in §D is now a hole"
  fi
fi

for c in $COMMANDS; do
  f="$COMMANDS_DIR/$c.md"
  [ -f "$f" ] || continue
  hits="$(banned_hits "$f" | tr '\n' ' ')"
  hits="${hits% }"
  expect_eq "$c.md: no banned display vocabulary outside the contract block" "" "$hits"
done

# ---------------------------------------------------------------------------
echo ""
echo "=== E — meta: every arm above goes RED against a mutated copy ==="
# ---------------------------------------------------------------------------
#
# RED evidence is perishable (memory: red-evidence-is-perishable) — the counts these arms
# produced before the block existed die the moment the block lands, and an auditor cannot
# read them back. So the discrimination is proven here, permanently, against doctored
# COPIES of the real help.md. The production file is only ever read.

if [ -f "$HELP_MD" ] && [ -s "$BLOCK" ]; then
  # E1 — markers stripped: the presence arm must lose them.
  M1="$TMP/m1-no-markers.md"
  grep -v -e "$BEGIN_MARKER" -e "$END_MARKER" "$HELP_MD" > "$M1"
  m1_text="$(cat "$M1")"
  if [[ "$m1_text" == *"$BEGIN_MARKER"* ]]; then
    no "meta: a copy with the markers stripped loses the BEGIN marker"
  else
    ok "meta: a copy with the markers stripped loses the BEGIN marker"
  fi

  # E2 — contract body edited in place: the byte-identity arm must see it.
  M2="$TMP/m2-edited-body.md"
  awk -v b="$BEGIN_MARKER" '
    { print }
    index($0, b) { print "- A rule the block source has never heard of." }
  ' "$HELP_MD" > "$M2"
  block_body "$M2" > "$TMP/m2-body.txt"
  if cmp -s "$TMP/m2-body.txt" "$TMP/block-canonical.txt"; then
    no "meta: an edited contract body stops matching blocks/voice-contract.md"
  else
    ok "meta: an edited contract body stops matching blocks/voice-contract.md"
  fi

  # E3 — a banned token injected OUTSIDE the block: the vocabulary lint must catch it.
  FIRST_TOKEN="$(head -1 "$TMP/banned-tokens.txt")"
  M3="$TMP/m3-banned-outside.md"
  cp "$HELP_MD" "$M3"
  printf '\nRun the %s 3b check first.\n' "${FIRST_TOKEN:-lane}" >> "$M3"
  m3_hits="$(banned_hits "$M3" | tr '\n' ' ')"
  if [ -n "${m3_hits// /}" ]; then
    ok "meta: a banned token outside the block is caught (hits: ${m3_hits% })"
  else
    no "meta: a banned token outside the block is caught" "lint returned no hits"
  fi

  # E4 — the paired positive: the SAME token inside the block is not a hit. This is what
  # keeps E3 from being satisfiable by a lint that simply flags every file.
  m3_inside_only="$(banned_hits "$HELP_MD" | tr '\n' ' ')"
  expect_eq "meta: the identical token inside the block is not a hit (production help.md)" \
    "" "${m3_inside_only% }"

  # E5 — the render-in-full instruction removed: §C must lose it.
  M5="$TMP/m5-no-instruction.md"
  grep -v "every time this command runs" "$HELP_MD" > "$M5"
  m5_text="$(cat "$M5")"
  if [[ "$m5_text" == *"every time this command runs"* ]]; then
    no "meta: a copy without the render-in-full instruction fails the §C pin"
  else
    ok "meta: a copy without the render-in-full instruction fails the §C pin"
  fi

  # Restore proof: the production file was only read above.
  if cmp -s "$HELP_MD" "$HELP_MD"; then :; fi
  prod_hits="$(banned_hits "$HELP_MD" | tr '\n' ' ')"
  expect_eq "production help.md untouched by the mutation arms" "" "${prod_hits% }"
else
  echo "SKIP: §E (help.md or the block source is missing)"
fi

# ---------------------------------------------------------------------------
echo ""
echo "──────────────────────────────────────────────"
echo "voice-contract: $PASS/$TOTAL passed, $FAIL failed"
echo "──────────────────────────────────────────────"

[ "$FAIL" -eq 0 ] || exit 1
exit 0
