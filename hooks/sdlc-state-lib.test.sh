#!/bin/bash
# Fixture suite for hooks/sdlc-state-lib.sh — slice 4/1 (baton primitives):
# baton_write (atomic tmp+mv, required-key serialization, R-B1), baton_parse
# (strict key anchors, cold next-action/ledger-position readback, R-B2), and
# malformed-baton detection (missing/duplicate/empty required key, truncated
# file — R-B3).
#
# Harness idiom mirrors hooks/sdlc-poker.test.sh: PASS/FAIL counters, a fresh
# fake $HOME + SDLC_STATE_DIR per case (mktemp) so no case ever touches the
# real home surface (D1/AS-6). Fixtures drive the REAL lib functions against
# planted files — never reimplement baton parsing/serialization here.
#
# "Cold" parse (R-B2) is modeled literally as a fresh bash CHILD PROCESS that
# sources the lib and calls baton_parse — no reuse of the writer's own shell
# state, matching "a cold reader names the next action from the file alone."
#
# Usage: bash hooks/sdlc-state-lib.test.sh

set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
LIB="$REPO/hooks/sdlc-state-lib.sh"
PASS=0; FAIL=0; TOTAL=0
CLEAN_DIRS=()

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; [ -n "${2:-}" ] && echo "  $2"; FAIL=$((FAIL + 1)); }

cleanup() { for d in "${CLEAN_DIRS[@]:-}"; do [ -n "$d" ] && rm -rf "$d"; done; }
trap cleanup EXIT

# Source the library directly in THIS shell for the write-side assertions
# (baton_write, path helpers). The cold-parse assertions below deliberately
# spawn a fresh child instead of relying on this sourced copy.
. "$LIB"

# ---------- fresh fake HOME + SDLC_STATE_DIR per case ----------
new_state_dir() {
  HOME=$(mktemp -d); export HOME
  SDLC_STATE_DIR="$(mktemp -d)"; export SDLC_STATE_DIR
  CLEAN_DIRS+=("$HOME" "$SDLC_STATE_DIR")
}

# ---------- assertions ----------
assert_eq() {  # <label> <expected> <actual>
  TOTAL=$((TOTAL + 1))
  if [ "$3" = "$2" ]; then pass "$1"; else fail "$1" "expected='$2' actual='$3'"; fi
}
assert_true() {  # <label> <cmd...>
  local label="$1"; shift
  TOTAL=$((TOTAL + 1))
  if "$@"; then pass "$label"; else fail "$label"; fi
}
assert_contains() {  # <label> <needle> <haystack>
  TOTAL=$((TOTAL + 1))
  if printf '%s' "$3" | grep -qF -- "$2"; then pass "$1"; else fail "$1" "expected to contain '$2' — got: $3"; fi
}
assert_nonzero() {  # <label> <actual-exit-code>
  TOTAL=$((TOTAL + 1))
  if [ "$2" -ne 0 ]; then pass "$1"; else fail "$1" "expected nonzero exit, got 0"; fi
}

# ---------- fixture helpers ----------
# write_healthy <goal-id> [wip] → writes a healthy baton via the REAL
# baton_write, returns its path. wip defaults to "none" (the common case);
# pass a sha for round-trip fidelity assertions.
write_healthy() {
  local gid="$1" wip="${2:-none}" base="${3:-none}"
  baton_write "$gid" "/plans/$gid.plan.md" "/work/$gid" "wave-01-substrate" \
    "epic/10-never-die" "abc1234" "4" "sid-$gid/4242" "42:deadbeef" \
    "run the next slice" "$wip" "$base" >/dev/null 2>&1
  baton_path "$gid"
}

# cold_parse <baton-file> — a FRESH bash child sources the lib and calls
# baton_parse; echoes "<exit-code>\t<next-action>\t<ledger-position>" on
# stdout and the defect line (if any) on stderr, both captured separately.
cold_parse() {
  local f="$1" errf
  errf="$(mktemp)"; CLEAN_DIRS+=("$errf")
  COLD_OUT=$(bash -c '
    . "$1" || exit 90
    if baton_parse "$2"; then
      printf "%s\t%s\t%s\n" "0" "$BATON_NEXT_ACTION" "$BATON_LEDGER_POSITION"
    else
      printf "%s\t%s\t%s\n" "$?" "" ""
    fi
  ' bash "$LIB" "$f" 2>"$errf")
  COLD_ERR=$(cat "$errf" 2>/dev/null)
}

# delete_key <src> <dst> <key> — copy src to dst with the given key's line
# removed entirely (missing-key fixture).
delete_key() { grep -v -E "^${3}:" "$1" > "$2"; }

# duplicate_key <src> <dst> <key> — copy src to dst with the given key's
# line appended a second time immediately after the original (duplicate-key
# fixture); the append lands inside the header block (before any blank-line
# prose separator) since there is none in a bare baton_write output.
duplicate_key() {
  local src="$1" dst="$2" key="$3" line
  line=$(grep -E "^${key}:" "$src")
  awk -v k="^${key}:" -v extra="$line" '{ print } $0 ~ k { print extra }' "$src" > "$dst"
}

# empty_value <src> <dst> <key> — copy src to dst with the given key's
# value blanked (key: with nothing after it).
empty_value() { sed -E "s/^(${3}):.*/\1:/" "$1" > "$2"; }

# truncate_file <src> <dst> — copy src to dst with the trailing newline of
# the last line stripped ($()  strips ALL trailing newlines on capture), so
# every required key/value stays intact but the file no longer ends in \n —
# the "cut off mid-flush" signal distinct from missing/duplicate/empty.
truncate_file() { printf '%s' "$(cat "$1")" > "$2"; }

REQUIRED_KEYS="goal-id plan cwd branch integration-branch last-commit sdlc-step session ledger-position next-action wip base-commit written-at"

# ============================================================
echo "=== AC-B1: round-trip write → cold parse → next-action + ledger-position readback ==="
ac_b1() {
  new_state_dir
  local gid="wave-01-substrate-4-1"
  local f; f=$(write_healthy "$gid" "deadbeef1234567890abcdef1234567890abcdef" "beefcafe1234567890abcdef1234567890abcdef")
  assert_true "AC-B1 baton_write produced a file" test -f "$f"
  assert_eq "AC-B1 baton_write went through the goal's dir (AS-6 mkdir -p)" \
    "$SDLC_STATE_DIR/$gid/baton.md" "$f"

  cold_parse "$f"
  local rc na lp
  IFS=$'\t' read -r rc na lp <<< "$COLD_OUT"
  assert_eq "AC-B1 cold parse exit 0 on a healthy baton" "0" "$rc"
  assert_eq "AC-B1 cold next-action readback" "run the next slice" "$na"
  assert_eq "AC-B1 cold ledger-position readback" "42:deadbeef" "$lp"

  # Same-process parse of the remaining required fields (round-trip fidelity
  # beyond the two R-B2-named fields).
  baton_parse "$f"
  assert_eq "AC-B1 goal-id round-trips" "$gid" "$BATON_GOAL_ID"
  assert_eq "AC-B1 plan round-trips" "/plans/$gid.plan.md" "$BATON_PLAN"
  assert_eq "AC-B1 cwd round-trips" "/work/$gid" "$BATON_CWD"
  assert_eq "AC-B1 branch round-trips" "wave-01-substrate" "$BATON_BRANCH"
  assert_eq "AC-B1 integration-branch round-trips" "epic/10-never-die" "$BATON_INTEGRATION_BRANCH"
  assert_eq "AC-B1 last-commit round-trips" "abc1234" "$BATON_LAST_COMMIT"
  assert_eq "AC-B1 sdlc-step round-trips" "4" "$BATON_SDLC_STEP"
  assert_eq "AC-B1 session round-trips" "sid-$gid/4242" "$BATON_SESSION"
  assert_eq "AC-B1 wip round-trips" "deadbeef1234567890abcdef1234567890abcdef" "$BATON_WIP"
  assert_eq "AC-B1 base-commit round-trips" "beefcafe1234567890abcdef1234567890abcdef" "$BATON_BASE_COMMIT"
  assert_true "AC-B1 written-at is non-empty" test -n "$BATON_WRITTEN_AT"
}
ac_b1

# ============================================================
echo "=== AC-B2: malformed baton detection — each direction ==="

echo "--- healthy baton passes (positive control, both-directions discipline) ---"
ac_b2_healthy() {
  new_state_dir
  local f errf; f=$(write_healthy "healthy-goal")
  errf="$(mktemp)"; CLEAN_DIRS+=("$errf")
  TOTAL=$((TOTAL + 1))
  if baton_parse "$f" 2>"$errf"; then pass "AC-B2 healthy baton parses cleanly"; else
    fail "AC-B2 healthy baton parses cleanly" "$(cat "$errf" 2>/dev/null)"
  fi
}
ac_b2_healthy

echo "--- each required key missing → nonzero + defect names that key ---"
ac_b2_missing() {
  local key src dst rc err
  new_state_dir
  src=$(write_healthy "missing-src")
  for key in $REQUIRED_KEYS; do
    dst="$(mktemp -d)/baton.md"; CLEAN_DIRS+=("$(dirname "$dst")")
    delete_key "$src" "$dst" "$key"
    err=$(baton_parse "$dst" 2>&1 >/dev/null); rc=$?
    assert_nonzero "AC-B2 missing '$key' → nonzero exit" "$rc"
    assert_contains "AC-B2 missing '$key' → defect names the key" "$key" "$err"
  done
}
ac_b2_missing

echo "--- one duplicated key → nonzero + defect names it ---"
ac_b2_duplicate() {
  new_state_dir
  local src dst rc err
  src=$(write_healthy "dup-src")
  dst="$(mktemp -d)/baton.md"; CLEAN_DIRS+=("$(dirname "$dst")")
  duplicate_key "$src" "$dst" "sdlc-step"
  err=$(baton_parse "$dst" 2>&1 >/dev/null); rc=$?
  assert_nonzero "AC-B2 duplicate 'sdlc-step' → nonzero exit" "$rc"
  assert_contains "AC-B2 duplicate 'sdlc-step' → defect names it" "sdlc-step" "$err"
}
ac_b2_duplicate

echo "--- empty value → nonzero + defect names it ---"
ac_b2_empty() {
  new_state_dir
  local src dst rc err
  src=$(write_healthy "empty-src")
  dst="$(mktemp -d)/baton.md"; CLEAN_DIRS+=("$(dirname "$dst")")
  empty_value "$src" "$dst" "next-action"
  err=$(baton_parse "$dst" 2>&1 >/dev/null); rc=$?
  assert_nonzero "AC-B2 empty 'next-action' value → nonzero exit" "$rc"
  assert_contains "AC-B2 empty 'next-action' value → defect names it" "next-action" "$err"
}
ac_b2_empty

echo "--- truncated file (no trailing newline, mid-flush cut) → nonzero + defect ---"
ac_b2_truncated() {
  new_state_dir
  local src dst rc err
  src=$(write_healthy "trunc-src")
  dst="$(mktemp -d)/baton.md"; CLEAN_DIRS+=("$(dirname "$dst")")
  truncate_file "$src" "$dst"
  TOTAL=$((TOTAL + 1))
  if [ "$(tail -c1 "$dst" | wc -l | tr -d ' ')" = "0" ]; then
    pass "AC-B2 truncation fixture actually lacks a trailing newline"
  else
    fail "AC-B2 truncation fixture actually lacks a trailing newline" "fixture construction failed"
  fi
  err=$(baton_parse "$dst" 2>&1 >/dev/null); rc=$?
  assert_nonzero "AC-B2 truncated file → nonzero exit" "$rc"
  assert_contains "AC-B2 truncated file → defect names truncation" "truncat" "$err"
}
ac_b2_truncated

echo "--- baton_parse never partially populates state on defect ---"
ac_b2_no_partial_trust() {
  new_state_dir
  local src dst
  src=$(write_healthy "partial-src")
  dst="$(mktemp -d)/baton.md"; CLEAN_DIRS+=("$(dirname "$dst")")
  delete_key "$src" "$dst" "next-action"
  BATON_GOAL_ID="sentinel-untouched"
  BATON_WIP="sentinel-wip-untouched"
  baton_parse "$dst" >/dev/null 2>&1
  assert_eq "AC-B2 a failed parse leaves prior BATON_* state untouched (no partial trust)" \
    "sentinel-untouched" "$BATON_GOAL_ID"
  assert_eq "AC-B2 a failed parse leaves prior BATON_WIP untouched (no partial trust)" \
    "sentinel-wip-untouched" "$BATON_WIP"
}
ac_b2_no_partial_trust

# ============================================================
echo "=== D4/D9: baton_write value-grammar gates — wip (full 40-hex or none) + ledger-position (<seq>:<8-hex-digest> or none) ==="

# assert_no_file_written <label> <goal-id> — asserts baton_write's target
# path for <goal-id> was never created (the reject contract: loud defect,
# nonzero rc, no file — not even a partial one).
assert_no_file_written() {
  local label="$1" gid="$2"
  TOTAL=$((TOTAL + 1))
  if [ -e "$(baton_path "$gid")" ]; then
    fail "$label" "baton file exists at $(baton_path "$gid")"
  else
    pass "$label"
  fi
}

echo "--- wip: abbreviated 7-hex sha → invalid-wip-sha, no file written ---"
ac_grammar_wip_abbrev() {
  new_state_dir
  local gid="grammar-wip-abbrev" err rc
  err=$(baton_write "$gid" "p" "c" "b" "i" "lc" "4" "s" "1:abcd1234" "na" "deadbee" "none" 2>&1 1>/dev/null); rc=$?
  assert_nonzero "abbreviated 7-hex wip rejected (nonzero rc)" "$rc"
  assert_contains "abbreviated 7-hex wip names invalid-wip-sha" "invalid-wip-sha" "$err"
  assert_no_file_written "abbreviated 7-hex wip: no baton file written" "$gid"
}
ac_grammar_wip_abbrev

echo "--- wip: full-length but non-hex sha → invalid-wip-sha, no file written ---"
ac_grammar_wip_nonhex() {
  new_state_dir
  local gid="grammar-wip-nonhex" err rc
  err=$(baton_write "$gid" "p" "c" "b" "i" "lc" "4" "s" "1:abcd1234" "na" "deadbeef1234567890abcdef1234567890abcdeg" "none" 2>&1 1>/dev/null); rc=$?
  assert_nonzero "full-length non-hex wip rejected (nonzero rc)" "$rc"
  assert_contains "full-length non-hex wip names invalid-wip-sha" "invalid-wip-sha" "$err"
  assert_no_file_written "full-length non-hex wip: no baton file written" "$gid"
}
ac_grammar_wip_nonhex

echo "--- ledger-position: bare-seq (no digest) → invalid-ledger-position, no file written ---"
ac_grammar_ledger_bare_seq() {
  new_state_dir
  local gid="grammar-ledger-bare-seq" err rc
  err=$(baton_write "$gid" "p" "c" "b" "i" "lc" "4" "s" "42" "na" "none" "none" 2>&1 1>/dev/null); rc=$?
  assert_nonzero "bare-seq ledger-position rejected (nonzero rc)" "$rc"
  assert_contains "bare-seq ledger-position names invalid-ledger-position" "invalid-ledger-position" "$err"
  assert_no_file_written "bare-seq ledger-position: no baton file written" "$gid"
}
ac_grammar_ledger_bare_seq

echo "--- ledger-position: zero-seq → invalid-ledger-position, no file written ---"
ac_grammar_ledger_zero_seq() {
  new_state_dir
  local gid="grammar-ledger-zero-seq" err rc
  err=$(baton_write "$gid" "p" "c" "b" "i" "lc" "4" "s" "0:abcd1234" "na" "none" "none" 2>&1 1>/dev/null); rc=$?
  assert_nonzero "zero-seq ledger-position rejected (nonzero rc)" "$rc"
  assert_contains "zero-seq ledger-position names invalid-ledger-position" "invalid-ledger-position" "$err"
  assert_no_file_written "zero-seq ledger-position: no baton file written" "$gid"
}
ac_grammar_ledger_zero_seq

echo "--- ledger-position: missing digest (seq: with nothing after) → invalid-ledger-position, no file written ---"
ac_grammar_ledger_missing_digest() {
  new_state_dir
  local gid="grammar-ledger-missing-digest" err rc
  err=$(baton_write "$gid" "p" "c" "b" "i" "lc" "4" "s" "42:" "na" "none" "none" 2>&1 1>/dev/null); rc=$?
  assert_nonzero "missing-digest ledger-position rejected (nonzero rc)" "$rc"
  assert_contains "missing-digest ledger-position names invalid-ledger-position" "invalid-ledger-position" "$err"
  assert_no_file_written "missing-digest ledger-position: no baton file written" "$gid"
}
ac_grammar_ledger_missing_digest

echo "--- accept: 'none' for both wip and ledger-position ---"
ac_grammar_accept_none() {
  new_state_dir
  local gid="grammar-accept-none" rc f
  baton_write "$gid" "p" "c" "b" "i" "lc" "4" "s" "none" "na" "none" "none" >/dev/null 2>&1; rc=$?
  assert_eq "accept: 'none'/'none' returns rc 0" "0" "$rc"
  f="$(baton_path "$gid")"
  assert_true "accept: 'none'/'none' wrote a file" test -f "$f"
  baton_parse "$f"
  assert_eq "accept: 'none'/'none' ledger-position round-trips" "none" "$BATON_LEDGER_POSITION"
  assert_eq "accept: 'none'/'none' wip round-trips" "none" "$BATON_WIP"
}
ac_grammar_accept_none

echo "--- accept: full 40-hex wip + minimal '1:00000000'-style ledger-position, round-trip unchanged ---"
ac_grammar_accept_full() {
  new_state_dir
  local gid="grammar-accept-full" rc f
  baton_write "$gid" "p" "c" "b" "i" "lc" "4" "s" "1:00000000" "na" \
    "cafebabe1234567890abcdef1234567890abcdef" "none" >/dev/null 2>&1; rc=$?
  assert_eq "accept: full-form wip + minimal ledger-position returns rc 0" "0" "$rc"
  f="$(baton_path "$gid")"
  assert_true "accept: full-form wip + minimal ledger-position wrote a file" test -f "$f"
  baton_parse "$f"
  assert_eq "accept: minimal ledger-position round-trips" "1:00000000" "$BATON_LEDGER_POSITION"
  assert_eq "accept: full 40-hex wip round-trips" "cafebabe1234567890abcdef1234567890abcdef" "$BATON_WIP"
}
ac_grammar_accept_full

echo "--- base-commit: abbreviated 7-hex sha → invalid-base-commit, no file written ---"
ac_grammar_base_abbrev() {
  new_state_dir
  local gid="grammar-base-abbrev" err rc
  err=$(baton_write "$gid" "p" "c" "b" "i" "lc" "4" "s" "1:abcd1234" "na" "none" "deadbee" 2>&1 1>/dev/null); rc=$?
  assert_nonzero "abbreviated 7-hex base-commit rejected (nonzero rc)" "$rc"
  assert_contains "abbreviated 7-hex base-commit names invalid-base-commit" "invalid-base-commit" "$err"
  assert_no_file_written "abbreviated 7-hex base-commit: no baton file written" "$gid"
}
ac_grammar_base_abbrev

echo "--- base-commit: full-length but non-hex sha → invalid-base-commit, no file written ---"
ac_grammar_base_nonhex() {
  new_state_dir
  local gid="grammar-base-nonhex" err rc
  err=$(baton_write "$gid" "p" "c" "b" "i" "lc" "4" "s" "1:abcd1234" "na" "none" "deadbeef1234567890abcdef1234567890abcdeg" 2>&1 1>/dev/null); rc=$?
  assert_nonzero "full-length non-hex base-commit rejected (nonzero rc)" "$rc"
  assert_contains "full-length non-hex base-commit names invalid-base-commit" "invalid-base-commit" "$err"
  assert_no_file_written "full-length non-hex base-commit: no baton file written" "$gid"
}
ac_grammar_base_nonhex

echo "--- accept: full 40-hex base-commit round-trips unchanged ---"
ac_grammar_base_accept_full() {
  new_state_dir
  local gid="grammar-base-accept-full" rc f
  baton_write "$gid" "p" "c" "b" "i" "lc" "4" "s" "1:00000000" "na" "none" \
    "abadfeed1234567890abcdef1234567890abcdef" >/dev/null 2>&1; rc=$?
  assert_eq "accept: full-form base-commit returns rc 0" "0" "$rc"
  f="$(baton_path "$gid")"
  baton_parse "$f"
  assert_eq "accept: full 40-hex base-commit round-trips" "abadfeed1234567890abcdef1234567890abcdef" "$BATON_BASE_COMMIT"
}
ac_grammar_base_accept_full

# ============================================================
# ledger fixture helpers (slice 4/2) — build via the REAL ledger_append;
# planted-corruption cases forge lines by construction (awk splice), never
# by reimplementing digest/seq logic.
# ============================================================

# build_healthy_ledger <goal-id> — three real appends (decision, effect,
# decision); echoes the ledger's path.
build_healthy_ledger() {
  local gid="$1"
  ledger_append "$gid" "decision" "step-a" "first decision" >/dev/null 2>&1
  ledger_append "$gid" "effect" "step-a-applied" "applied step a" >/dev/null 2>&1
  ledger_append "$gid" "decision" "step-b" "second decision" >/dev/null 2>&1
  printf '%s' "$(ledger_path "$gid")"
}

# ============================================================
echo "=== AC-L1: ordered ledger journaling + ledger_applied (both directions) ==="
ac_l1() {
  new_state_dir
  local gid="wave-01-substrate-4-2"
  assert_true "AC-L1 first decision append succeeds" ledger_append "$gid" "decision" "choose-approach" "decided to use tab-separated chained log"
  assert_true "AC-L1 second append (effect) succeeds" ledger_append "$gid" "effect" "wrote-file-x" "wrote config to /tmp/x"
  assert_true "AC-L1 third append (decision) succeeds" ledger_append "$gid" "decision" "choose-approach-2" "picked a fixed genesis marker"

  local path="$SDLC_STATE_DIR/$gid/ledger.log"
  assert_true "AC-L1 ledger file exists" test -f "$path"
  assert_eq "AC-L1 exactly 3 lines written" "3" "$(wc -l < "$path" | tr -d ' ')"

  local seqs
  seqs=$(awk -F'\t' '{print $2}' "$path" | tr '\n' ',')
  assert_eq "AC-L1 seq is strictly monotonic from 1" "1,2,3," "$seqs"

  assert_true "AC-L1 ledger_applied finds a known effect-key" ledger_applied "$gid" "wrote-file-x"

  TOTAL=$((TOTAL + 1))
  if ledger_applied "$gid" "never-happened"; then
    fail "AC-L1 ledger_applied rejects an unknown effect-key"
  else
    pass "AC-L1 ledger_applied rejects an unknown effect-key"
  fi

  TOTAL=$((TOTAL + 1))
  if ledger_applied "$gid" "choose-approach"; then
    fail "AC-L1 ledger_applied does not false-positive on a decision-type line sharing the key"
  else
    pass "AC-L1 ledger_applied does not false-positive on a decision-type line sharing the key"
  fi
}
ac_l1

echo "--- ledger_applied on an absent ledger: nonzero, silent (not-applied) ---"
ac_l1_absent() {
  new_state_dir
  local err rc
  err=$(ledger_applied "no-such-goal" "whatever" 2>&1 1>/dev/null); rc=$?
  assert_nonzero "AC-L1 ledger_applied on absent ledger returns nonzero" "$rc"
  assert_eq "AC-L1 ledger_applied on absent ledger is silent (no stderr)" "" "$err"
}
ac_l1_absent

echo "--- ledger_append rejects a bad type (fail-closed) ---"
ac_l1_bad_type() {
  new_state_dir
  local rc
  ledger_append "bad-type-goal" "not-a-type" "k" "s" >/dev/null 2>&1; rc=$?
  assert_nonzero "AC-L1 ledger_append rejects an invalid type" "$rc"
}
ac_l1_bad_type

echo "--- ledger_append onto a ledger whose LAST line has a non-numeric seq field → nonzero + corrupt-ledger-tail (fail loud, not a shell arithmetic error) ---"
ac_l1_corrupt_tail() {
  new_state_dir
  local gid="corrupt-tail-goal" path errf rc total
  path=$(build_healthy_ledger "$gid")
  total=$(wc -l < "$path" | tr -d ' ')
  awk -F'\t' -v OFS='\t' -v ln="$total" 'NR==ln{$2="NOTANUMBER"} {print}' "$path" > "$path.new" && mv "$path.new" "$path"
  errf="$(mktemp)"; CLEAN_DIRS+=("$errf")
  ledger_append "$gid" "decision" "new-after-tamper" "should fail loud, not crash" 2>"$errf"; rc=$?
  assert_nonzero "AC-L1 append onto tampered-seq ledger returns nonzero" "$rc"
  assert_contains "AC-L1 append onto tampered-seq ledger names corrupt-ledger-tail" "corrupt-ledger-tail" "$(cat "$errf")"
}
ac_l1_corrupt_tail

# ============================================================
echo "=== AC-L2: ledger tamper evidence — pristine + each planted defect class ==="

echo "--- pristine ledger verifies silent, exit 0 ---"
ac_l2_pristine() {
  new_state_dir
  local gid="pristine-goal" errf rc
  build_healthy_ledger "$gid" >/dev/null
  errf="$(mktemp)"; CLEAN_DIRS+=("$errf")
  ledger_verify "$gid" 2>"$errf"; rc=$?
  assert_eq "AC-L2 pristine ledger exits 0" "0" "$rc"
  assert_eq "AC-L2 pristine ledger is silent on stderr" "" "$(cat "$errf")"
}
ac_l2_pristine

echo "--- absent ledger: named defect, distinct from empty ---"
ac_l2_absent() {
  new_state_dir
  local err rc
  err=$(ledger_verify "no-such-goal" 2>&1 1>/dev/null); rc=$?
  assert_nonzero "AC-L2 absent ledger returns nonzero" "$rc"
  assert_contains "AC-L2 absent ledger defect names it missing" "missing-ledger" "$err"
}
ac_l2_absent

echo "--- empty (zero-byte) ledger: silent, exit 0 — distinct from absent ---"
ac_l2_empty() {
  new_state_dir
  local gid="empty-goal" dir path errf rc
  dir="$SDLC_STATE_DIR/$gid"; mkdir -p "$dir"
  path="$dir/ledger.log"; : > "$path"
  errf="$(mktemp)"; CLEAN_DIRS+=("$errf")
  ledger_verify "$gid" 2>"$errf"; rc=$?
  assert_eq "AC-L2 empty ledger exits 0 (vacuously pristine)" "0" "$rc"
  assert_eq "AC-L2 empty ledger is silent on stderr" "" "$(cat "$errf")"
}
ac_l2_empty

echo "--- planted seq-gap (middle line deleted) → nonzero + named defect ---"
ac_l2_gap() {
  new_state_dir
  local gid="gap-goal" path errf rc
  path=$(build_healthy_ledger "$gid")
  awk 'NR!=2' "$path" > "$path.new" && mv "$path.new" "$path"
  errf="$(mktemp)"; CLEAN_DIRS+=("$errf")
  ledger_verify "$gid" 2>"$errf"; rc=$?
  assert_nonzero "AC-L2 seq-gap returns nonzero" "$rc"
  assert_contains "AC-L2 seq-gap defect names it" "seq-gap" "$(cat "$errf")"
}
ac_l2_gap

echo "--- planted reorder (two lines swapped) → nonzero + named defect ---"
ac_l2_reorder() {
  new_state_dir
  local gid="reorder-goal" path errf rc
  path=$(build_healthy_ledger "$gid")
  awk 'NR==1 { print; next } NR==2 { l2=$0; next } NR==3 { print; print l2; next } { print }' "$path" > "$path.new" && mv "$path.new" "$path"
  errf="$(mktemp)"; CLEAN_DIRS+=("$errf")
  ledger_verify "$gid" 2>"$errf"; rc=$?
  assert_nonzero "AC-L2 reorder returns nonzero" "$rc"
  assert_contains "AC-L2 reorder defect names it" "seq-reorder" "$(cat "$errf")"
}
ac_l2_reorder

echo "--- planted in-place edit (line-2 summary rewritten, digest field untouched) → nonzero + named defect ---"
ac_l2_edit() {
  new_state_dir
  local gid="edit-goal" path errf rc
  path=$(build_healthy_ledger "$gid")
  awk -F'\t' -v OFS='\t' 'NR==2 { $6="TAMPERED SUMMARY" } { print }' "$path" > "$path.new" && mv "$path.new" "$path"
  errf="$(mktemp)"; CLEAN_DIRS+=("$errf")
  ledger_verify "$gid" 2>"$errf"; rc=$?
  assert_nonzero "AC-L2 in-place edit returns nonzero" "$rc"
  assert_contains "AC-L2 in-place edit defect names it" "in-place-edit" "$(cat "$errf")"
}
ac_l2_edit

echo "--- planted in-place edit of the TERMINAL line (effect-key + summary rewritten, seq + digest fields kept) → nonzero + named defect (AS-28: self-covering chain — the terminal line is the kill-moment line and must be tamper-evident) ---"
ac_l2_edit_terminal() {
  new_state_dir
  local gid="edit-terminal-goal" path errf rc total
  path=$(build_healthy_ledger "$gid")
  total=$(wc -l < "$path" | tr -d ' ')
  # Edit the LAST line's effect-key (field 5) + summary (field 6), keeping
  # its seq (field 2) and digest (field 3) fields byte-for-byte — the exact
  # forgery a prev-line-only chain could not see (nothing chains past the tail).
  awk -F'\t' -v OFS='\t' -v ln="$total" 'NR==ln { $5="FORGED-KEY"; $6="FORGED SUMMARY" } { print }' "$path" > "$path.new" && mv "$path.new" "$path"
  errf="$(mktemp)"; CLEAN_DIRS+=("$errf")
  ledger_verify "$gid" 2>"$errf"; rc=$?
  assert_nonzero "AC-L2 terminal-line in-place edit returns nonzero" "$rc"
  assert_contains "AC-L2 terminal-line in-place edit defect names it" "in-place-edit" "$(cat "$errf")"
}
ac_l2_edit_terminal

echo "--- planted truncation (no trailing newline, mid-flush cut) → nonzero + named defect ---"
ac_l2_truncated() {
  new_state_dir
  local gid="trunc-goal" path errf rc
  path=$(build_healthy_ledger "$gid")
  printf '%s' "$(cat "$path")" > "$path.new" && mv "$path.new" "$path"
  errf="$(mktemp)"; CLEAN_DIRS+=("$errf")
  ledger_verify "$gid" 2>"$errf"; rc=$?
  assert_nonzero "AC-L2 truncated ledger returns nonzero" "$rc"
  assert_contains "AC-L2 truncated ledger defect names truncation" "truncat" "$(cat "$errf")"
}
ac_l2_truncated

# ============================================================
# WIP shadow store (slice 4/2) — sdlc_wip_snapshot / _restore / _check.
# Every case builds a HERMETIC fixture git repo in a fresh temp dir (git
# init + local user config + a base commit) so no test ever touches the
# real repo's git state; new_state_dir also freshens HOME/SDLC_STATE_DIR so
# no real home surface is read (the fixture's own local config is the only
# git config in play). Fixtures drive the REAL lib functions against planted
# WIP — never reimplement the plumbing here. refs/sdlc-wip/<goal-id> lives
# inside the fixture repo (WIP functions are repo-scoped via -C <dir>, D3),
# not under SDLC_STATE_DIR.
# ============================================================

# new_wip_repo — a hermetic fixture git repo; echoes its dir. Base commit
# carries tracked.txt, todelete.txt, control.txt and a .gitignore that
# ignores .bionic/docs/ (the lifecycle-artifact dir a snapshot force-includes).
new_wip_repo() {
  new_state_dir
  local d; d=$(mktemp -d); CLEAN_DIRS+=("$d")
  git -C "$d" init -q
  git -C "$d" config user.name  "fixture"
  git -C "$d" config user.email "fixture@example.com"
  printf 'base line\n'    > "$d/tracked.txt"
  printf 'delete me\n'    > "$d/todelete.txt"
  printf 'do not touch\n' > "$d/control.txt"
  printf '.bionic/docs/\n' > "$d/.gitignore"
  git -C "$d" add -A
  git -C "$d" commit -qm base
  printf '%s' "$d"
}

echo ""
echo "=== AC-W1: WIP snapshot → clobber → restore, byte-faithful across all four WIP classes (+ exec bit, spaces, deletion, controls untouched) ==="
ac_w1() {
  local d gid snap rc
  d=$(new_wip_repo); gid="wip-goal-w1"

  # All captured WIP classes at once:
  printf 'base line\nmodified\n' > "$d/tracked.txt"                 # 1. tracked modification
  printf 'brand new\n'           > "$d/untracked.txt"               # 2. untracked new file
  mkdir -p "$d/.bionic/docs"
  printf 'artifact v1\n'         > "$d/.bionic/docs/artifact.md"    # 3. gitignored, force-included
  rm -f "$d/todelete.txt"                                           # 4. tracked deletion
  printf '#!/bin/sh\necho hi\n'  > "$d/added-exec.sh"; chmod +x "$d/added-exec.sh"  # exec bit
  printf 'has spaces\n'          > "$d/a spacey file.txt"           # path with a space

  snap=$(sdlc_wip_snapshot "$gid" "$d" ".bionic/docs" 2>/dev/null)
  TOTAL=$((TOTAL + 1)); if [ -n "$snap" ] && [ "$snap" != "none" ]; then
    pass "AC-W1 snapshot prints a captured sha (WIP present, not 'none')"
  else fail "AC-W1 snapshot prints a captured sha (WIP present, not 'none')" "got: '$snap'"; fi
  assert_eq "AC-W1 refs/sdlc-wip/<gid> points at the snapshot" \
    "$snap" "$(git -C "$d" rev-parse --verify --quiet "refs/sdlc-wip/$gid" || true)"

  # Clobber every captured path; plant a post-snapshot untracked file that
  # restore must NOT delete (proves restore touches only captured paths).
  git -C "$d" checkout -q -- tracked.txt                 # revert tracked mod
  rm -f "$d/untracked.txt"                                # remove untracked
  printf 'CLOBBERED\n' > "$d/.bionic/docs/artifact.md"    # overwrite artifact
  printf 'delete me\n' > "$d/todelete.txt"               # resurrect deleted file
  rm -f "$d/added-exec.sh"
  rm -f "$d/a spacey file.txt"
  printf 'survivor\n'  > "$d/post-snapshot.txt"          # non-captured control

  sdlc_wip_restore "$gid" "$snap" "$d" 2>/dev/null; rc=$?
  assert_eq "AC-W1 restore exits 0" "0" "$rc"

  assert_eq "AC-W1 tracked modification restored byte-faithful" \
    "$(printf 'base line\nmodified')" "$(cat "$d/tracked.txt")"
  assert_eq "AC-W1 untracked file restored byte-faithful" \
    "brand new" "$(cat "$d/untracked.txt" 2>/dev/null)"
  assert_eq "AC-W1 gitignored force-included artifact restored byte-faithful" \
    "artifact v1" "$(cat "$d/.bionic/docs/artifact.md" 2>/dev/null)"
  assert_true "AC-W1 tracked deletion re-applied (file removed again)" test ! -e "$d/todelete.txt"
  assert_true "AC-W1 exec bit survived restore" test -x "$d/added-exec.sh"
  assert_eq "AC-W1 path-with-space file restored byte-faithful" \
    "has spaces" "$(cat "$d/a spacey file.txt" 2>/dev/null)"
  assert_eq "AC-W1 committed control file untouched by restore" \
    "do not touch" "$(cat "$d/control.txt" 2>/dev/null)"
  assert_eq "AC-W1 non-captured post-snapshot file untouched by restore" \
    "survivor" "$(cat "$d/post-snapshot.txt" 2>/dev/null)"
}
ac_w1

echo "--- clean tree → snapshot prints 'none' and deletes a stale ref ---"
ac_w1_clean() {
  local d gid out
  d=$(new_wip_repo); gid="wip-goal-clean"
  git -C "$d" update-ref "refs/sdlc-wip/$gid" "$(git -C "$d" rev-parse HEAD)"  # stale ref
  out=$(sdlc_wip_snapshot "$gid" "$d" 2>/dev/null)
  assert_eq "AC-W1 clean-tree snapshot prints none" "none" "$out"
  assert_eq "AC-W1 clean-tree snapshot deleted the stale ref" "" \
    "$(git -C "$d" rev-parse --verify --quiet "refs/sdlc-wip/$gid" || true)"
}
ac_w1_clean

echo "--- snapshot loud defects: not-a-repo, invalid-goal-id ---"
ac_w1_defects() {
  local nonrepo d err rc
  new_state_dir
  nonrepo=$(mktemp -d); CLEAN_DIRS+=("$nonrepo")
  err=$(sdlc_wip_snapshot "good-goal" "$nonrepo" 2>&1 1>/dev/null); rc=$?
  assert_nonzero "AC-W1 snapshot on a non-repo dir returns nonzero" "$rc"
  assert_contains "AC-W1 snapshot on a non-repo dir names not-a-repo" "not-a-repo" "$err"

  d=$(new_wip_repo)
  err=$(sdlc_wip_snapshot "bad/goal" "$d" 2>&1 1>/dev/null); rc=$?
  assert_nonzero "AC-W1 snapshot with a '/'-goal-id returns nonzero" "$rc"
  assert_contains "AC-W1 snapshot bad goal-id names invalid-goal-id" "invalid-goal-id" "$err"
}
ac_w1_defects

echo "--- restore on a missing object → wip-lost ---"
ac_w1_restore_lost() {
  local d err rc
  d=$(new_wip_repo)
  err=$(sdlc_wip_restore "wip-goal-rlost" "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef" "$d" 2>&1 1>/dev/null); rc=$?
  assert_nonzero "AC-W1 restore on a missing object returns nonzero" "$rc"
  assert_contains "AC-W1 restore on a missing object names wip-lost" "wip-lost" "$err"
}
ac_w1_restore_lost

echo "--- restore path-containment (FLAG-1): forged '..'/absolute delta paths refused, legit dotted/nested paths restore ---"
# Threat model: a FORGED or corrupted snapshot object whose delta carries a
# path that escapes "$dir". A normal snapshot can't (git add rejects '..' and
# absolute paths), so both fixtures below forge tree objects directly. The
# traversal object is a real git tree (a '..'-named subtree, built with
# mktree); the absolute-path object is a raw tree hand-built past fsck with
# `hash-object --literally` (mktree forbids slashes in a name). Both drive the
# REAL sdlc_wip_restore — the plumbing is forged, the restore is not.
hex2bin() {  # <hex-sha> → 20 raw bytes on stdout
  local h="$1" i
  for ((i = 0; i < ${#h}; i += 2)); do printf "\\x${h:i:2}"; done
}
# forge_traversal_commit <repo-dir> <sentinel-basename> <content> → commit sha.
# Delta path is "../<sentinel-basename>" so restore's "$dir/$path" join escapes
# to <dir>'s SIBLING. -p HEAD so the restore's "$sha^" parent resolves.
forge_traversal_commit() {
  local d="$1" name="$2" content="$3" blob inner outer
  blob=$(printf '%s' "$content" | git -C "$d" hash-object -w --stdin)
  inner=$(printf '100644 blob %s\t%s\n' "$blob" "$name" | git -C "$d" mktree)
  outer=$(printf '040000 tree %s\t..\n' "$inner" | git -C "$d" mktree)
  git -C "$d" commit-tree "$outer" -p "$(git -C "$d" rev-parse HEAD)" -m forged-traversal
}
# forge_absolute_commit <repo-dir> <content> → commit sha; delta path "/abs.txt".
forge_absolute_commit() {
  local d="$1" content="$2" blob binf tree
  blob=$(printf '%s' "$content" | git -C "$d" hash-object -w --stdin)
  binf=$(mktemp); CLEAN_DIRS+=("$binf")
  { printf '100644 /abs.txt\0'; hex2bin "$blob"; } > "$binf"
  tree=$(git -C "$d" hash-object -w -t tree --literally "$binf")
  git -C "$d" commit-tree "$tree" -p "$(git -C "$d" rev-parse HEAD)" -m forged-absolute
}

ac_w1_restore_traversal() {
  local d gid sentinel forged err rc
  d=$(new_wip_repo); gid="wip-goal-traversal"
  sentinel="$(dirname "$d")/wip-escape-sentinel-$$.txt"
  rm -f "$sentinel"                                   # ensure a clean slate
  forged=$(forge_traversal_commit "$d" "wip-escape-sentinel-$$.txt" "PWNED")
  err=$(sdlc_wip_restore "$gid" "$forged" "$d" 2>&1 1>/dev/null); rc=$?
  assert_nonzero "AC-W1 FLAG-1 restore refuses a '..'-traversal delta path (nonzero)" "$rc"
  assert_contains "AC-W1 FLAG-1 traversal defect names restore-unsafe-path" "restore-unsafe-path" "$err"
  assert_true "AC-W1 FLAG-1 traversal wrote NO file outside the fixture dir" test ! -e "$sentinel"
  rm -f "$sentinel"
}
ac_w1_restore_traversal

ac_w1_restore_absolute() {
  local d gid forged err rc
  d=$(new_wip_repo); gid="wip-goal-absolute"
  forged=$(forge_absolute_commit "$d" "PWNED-ABS")
  err=$(sdlc_wip_restore "$gid" "$forged" "$d" 2>&1 1>/dev/null); rc=$?
  assert_nonzero "AC-W1 FLAG-1 restore refuses an absolute delta path (nonzero)" "$rc"
  assert_contains "AC-W1 FLAG-1 absolute defect names restore-unsafe-path" "restore-unsafe-path" "$err"
}
ac_w1_restore_absolute

# Positive control: legit nested and dotted-filename paths must NOT false-reject
# (proves the '..' check is a precise PATH-COMPONENT match, not a bare substring).
ac_w1_restore_legit_dotted() {
  local d gid snap rc
  d=$(new_wip_repo); gid="wip-goal-dotted"
  mkdir -p "$d/sub/dir"
  printf 'nested ok\n'  > "$d/sub/dir/ok.txt"          # legit nested path
  printf 'dotted ok\n'  > "$d/a..b.txt"                # filename literally containing '..'
  snap=$(sdlc_wip_snapshot "$gid" "$d" 2>/dev/null)
  rm -f "$d/sub/dir/ok.txt" "$d/a..b.txt"              # clobber both
  sdlc_wip_restore "$gid" "$snap" "$d" 2>/dev/null; rc=$?
  assert_eq "AC-W1 FLAG-1 legit nested+dotted paths restore exits 0 (no false-reject)" "0" "$rc"
  assert_eq "AC-W1 FLAG-1 nested path restored byte-faithful" \
    "nested ok" "$(cat "$d/sub/dir/ok.txt" 2>/dev/null)"
  assert_eq "AC-W1 FLAG-1 dotted filename 'a..b.txt' restored byte-faithful" \
    "dotted ok" "$(cat "$d/a..b.txt" 2>/dev/null)"
}
ac_w1_restore_legit_dotted

echo "--- restore path-containment (Step-6 critic): '.git'-component write + symlink-parent/leaf write-through refused, legit '.github' still restores ---"
# Two further forged-snapshot escapes that the '..'/absolute string guards do
# NOT catch (no '..', not absolute):
#   ESCAPE 1 — a '.git'-component delta path (e.g. '.git/hooks/pre-commit')
#     would plant an executable hook the next git op runs (RCE). Also aliased
#     case-insensitively on APFS/HFS ('.GIT/…' hits the real .git).
#   ESCAPE 2 — a pre-existing worktree symlink at a parent (or leaf) component
#     lets 'cat-file blob > $dir/link/…' follow the link and write OUTSIDE $dir.
#     A string test on $path cannot catch this — an lstat check is required.
# Both forge trees directly (git add refuses a '.git' entry) and drive the REAL
# sdlc_wip_restore. forge_*_commit preserve HEAD's entries so the delta carries
# ONLY the escaping path (no incidental deletions to reason about).

# forge_gitdir_commit <repo-dir> <gitname> <content> → commit sha; delta path
# "<gitname>/hooks/pre-commit" (mode 100755). <gitname> is '.git' or a case
# variant ('.GIT') to exercise the case-folded component match.
forge_gitdir_commit() {
  local d="$1" gitname="$2" content="$3" blob hooks_tree git_tree root
  blob=$(printf '%s' "$content" | git -C "$d" hash-object -w --stdin)
  hooks_tree=$(printf '100755 blob %s\tpre-commit\n' "$blob" | git -C "$d" mktree)
  git_tree=$(printf '040000 tree %s\thooks\n' "$hooks_tree" | git -C "$d" mktree)
  root=$( { git -C "$d" ls-tree HEAD; printf '040000 tree %s\t%s\n' "$git_tree" "$gitname"; } \
            | git -C "$d" mktree )
  git -C "$d" commit-tree "$root" -p "$(git -C "$d" rev-parse HEAD)" -m forged-gitdir
}
# forge_underdir_commit <repo-dir> <dirname> <leaf> <content> → commit sha;
# delta path "<dirname>/<leaf>" (no '..', not absolute). Used to aim a write at
# a path under a pre-existing worktree symlink named <dirname>.
forge_underdir_commit() {
  local d="$1" dirname="$2" leaf="$3" content="$4" blob sub root
  blob=$(printf '%s' "$content" | git -C "$d" hash-object -w --stdin)
  sub=$(printf '100644 blob %s\t%s\n' "$blob" "$leaf" | git -C "$d" mktree)
  root=$( { git -C "$d" ls-tree HEAD; printf '040000 tree %s\t%s\n' "$sub" "$dirname"; } \
            | git -C "$d" mktree )
  git -C "$d" commit-tree "$root" -p "$(git -C "$d" rev-parse HEAD)" -m forged-underdir
}
# forge_topfile_commit <repo-dir> <name> <content> → commit sha; delta path
# "<name>" (a top-level file). Used to aim a write at a pre-existing symlink LEAF.
forge_topfile_commit() {
  local d="$1" name="$2" content="$3" blob root
  blob=$(printf '%s' "$content" | git -C "$d" hash-object -w --stdin)
  root=$( { git -C "$d" ls-tree HEAD; printf '100644 blob %s\t%s\n' "$blob" "$name"; } \
            | git -C "$d" mktree )
  git -C "$d" commit-tree "$root" -p "$(git -C "$d" rev-parse HEAD)" -m forged-topfile
}

# ESCAPE 1 — '.git'-component write → RCE.
ac_w1_restore_gitdir() {
  local d gid forged err rc
  d=$(new_wip_repo); gid="wip-goal-gitdir"
  rm -f "$d/.git/hooks/pre-commit"
  forged=$(forge_gitdir_commit "$d" ".git" "#!/bin/sh"$'\n'"echo PWNED")
  err=$(sdlc_wip_restore "$gid" "$forged" "$d" 2>&1 1>/dev/null); rc=$?
  assert_nonzero "AC-W1 critic restore refuses a '.git'-component delta path (nonzero)" "$rc"
  assert_contains "AC-W1 critic '.git' defect names restore-unsafe-path" "restore-unsafe-path" "$err"
  assert_true "AC-W1 critic '.git' write planted NO hook in .git/hooks" test ! -e "$d/.git/hooks/pre-commit"
}
ac_w1_restore_gitdir

# ESCAPE 1b — case-folded '.GIT' component (APFS/HFS alias the real .git dir).
ac_w1_restore_gitdir_casefold() {
  local d gid forged err rc
  d=$(new_wip_repo); gid="wip-goal-gitcase"
  rm -f "$d/.git/hooks/pre-commit"
  forged=$(forge_gitdir_commit "$d" ".GIT" "#!/bin/sh"$'\n'"echo PWNED")
  err=$(sdlc_wip_restore "$gid" "$forged" "$d" 2>&1 1>/dev/null); rc=$?
  assert_nonzero "AC-W1 critic restore refuses a case-folded '.GIT'-component path (nonzero)" "$rc"
  assert_contains "AC-W1 critic '.GIT' defect names restore-unsafe-path" "restore-unsafe-path" "$err"
  assert_true "AC-W1 critic '.GIT' write planted NO hook in the real .git/hooks" test ! -e "$d/.git/hooks/pre-commit"
}
ac_w1_restore_gitdir_casefold

# ESCAPE 2 — write-through a pre-existing symlink at a PARENT component.
ac_w1_restore_symlink_parent() {
  local d gid outside forged err rc
  d=$(new_wip_repo); gid="wip-goal-slparent"
  outside=$(mktemp -d); CLEAN_DIRS+=("$outside")
  rm -f "$outside/pwn.txt"
  ln -s "$outside" "$d/linkdir"                      # pre-existing worktree symlink OUTSIDE $dir
  forged=$(forge_underdir_commit "$d" "linkdir" "pwn.txt" "ESCAPED_OUTSIDE")
  err=$(sdlc_wip_restore "$gid" "$forged" "$d" 2>&1 1>/dev/null); rc=$?
  assert_nonzero "AC-W1 critic restore refuses a write through a symlinked PARENT (nonzero)" "$rc"
  assert_contains "AC-W1 critic symlink-parent defect names restore-unsafe-target" "restore-unsafe-target" "$err"
  assert_true "AC-W1 critic symlink-parent wrote NO file outside \$dir" test ! -e "$outside/pwn.txt"
}
ac_w1_restore_symlink_parent

# ESCAPE 2b — write-through a pre-existing symlink at the LEAF component.
ac_w1_restore_symlink_leaf() {
  local d gid outside forged err rc
  d=$(new_wip_repo); gid="wip-goal-slleaf"
  outside=$(mktemp -d); CLEAN_DIRS+=("$outside")
  rm -f "$outside/target"
  ln -s "$outside/target" "$d/leaflink"             # pre-existing worktree symlink LEAF
  forged=$(forge_topfile_commit "$d" "leaflink" "ESCAPED_VIA_LEAF")
  err=$(sdlc_wip_restore "$gid" "$forged" "$d" 2>&1 1>/dev/null); rc=$?
  assert_nonzero "AC-W1 critic restore refuses writing through a symlink LEAF (nonzero)" "$rc"
  assert_contains "AC-W1 critic symlink-leaf defect names restore-unsafe-target" "restore-unsafe-target" "$err"
  assert_true "AC-W1 critic symlink-leaf wrote NO file through the link" test ! -e "$outside/target"
}
ac_w1_restore_symlink_leaf

# Positive control: '.github' is a legit real dir whose name merely CONTAINS
# 'git' — the component match must be precise, not a substring, so it restores.
ac_w1_restore_legit_github() {
  local d gid snap rc
  d=$(new_wip_repo); gid="wip-goal-github"
  mkdir -p "$d/.github/workflows"
  printf 'name: ci\n' > "$d/.github/workflows/ci.yml"
  snap=$(sdlc_wip_snapshot "$gid" "$d" 2>/dev/null)
  rm -f "$d/.github/workflows/ci.yml"
  sdlc_wip_restore "$gid" "$snap" "$d" 2>/dev/null; rc=$?
  assert_eq "AC-W1 critic legit '.github' path restores exits 0 (no false-reject)" "0" "$rc"
  assert_eq "AC-W1 critic '.github/workflows/ci.yml' restored byte-faithful" \
    "name: ci" "$(cat "$d/.github/workflows/ci.yml" 2>/dev/null)"
}
ac_w1_restore_legit_github

echo ""
echo "=== AC-W2: WIP loss detection — healthy/none silent, each planted loss class named loud (both directions) ==="

echo "--- healthy match → silent, exit 0 ---"
ac_w2_healthy() {
  local d gid snap errf rc
  d=$(new_wip_repo); gid="wip-goal-w2-ok"
  printf 'wip\n' > "$d/untracked.txt"
  snap=$(sdlc_wip_snapshot "$gid" "$d" 2>/dev/null)
  errf=$(mktemp); CLEAN_DIRS+=("$errf")
  sdlc_wip_check "$gid" "$snap" "$d" 2>"$errf"; rc=$?
  assert_eq "AC-W2 healthy check exits 0" "0" "$rc"
  assert_eq "AC-W2 healthy check is silent on stderr" "" "$(cat "$errf")"
}
ac_w2_healthy

echo "--- honest 'none' → silent, exit 0 ---"
ac_w2_none() {
  local d errf rc
  d=$(new_wip_repo)
  errf=$(mktemp); CLEAN_DIRS+=("$errf")
  sdlc_wip_check "wip-goal-none" "none" "$d" 2>"$errf"; rc=$?
  assert_eq "AC-W2 none check exits 0" "0" "$rc"
  assert_eq "AC-W2 none check is silent on stderr" "" "$(cat "$errf")"
}
ac_w2_none

echo "--- object pruned (ref deleted + gc prune) → wip-lost naming the sha ---"
ac_w2_pruned() {
  local d gid snap errf rc out
  d=$(new_wip_repo); gid="wip-goal-pruned"
  printf 'wip\n' > "$d/untracked.txt"
  snap=$(sdlc_wip_snapshot "$gid" "$d" 2>/dev/null)
  git -C "$d" update-ref -d "refs/sdlc-wip/$gid"
  git -C "$d" prune --expire=now 2>/dev/null; git -C "$d" gc --prune=now -q 2>/dev/null || true
  errf=$(mktemp); CLEAN_DIRS+=("$errf")
  sdlc_wip_check "$gid" "$snap" "$d" 2>"$errf"; rc=$?; out=$(cat "$errf")
  assert_nonzero "AC-W2 pruned-object check returns nonzero" "$rc"
  assert_contains "AC-W2 pruned-object check names wip-lost" "wip-lost" "$out"
  assert_contains "AC-W2 pruned-object check names the lost sha" "$snap" "$out"
}
ac_w2_pruned

echo "--- ref deleted but object alive → wip-lost (ref half) ---"
ac_w2_ref_deleted() {
  local d gid snap errf rc out
  d=$(new_wip_repo); gid="wip-goal-refgone"
  printf 'wip\n' > "$d/untracked.txt"
  snap=$(sdlc_wip_snapshot "$gid" "$d" 2>/dev/null)
  git -C "$d" update-ref "refs/anchor/$gid" "$snap"   # anchor the object
  git -C "$d" update-ref -d "refs/sdlc-wip/$gid"          # drop only the sdlc-wip ref
  errf=$(mktemp); CLEAN_DIRS+=("$errf")
  sdlc_wip_check "$gid" "$snap" "$d" 2>"$errf"; rc=$?; out=$(cat "$errf")
  assert_nonzero "AC-W2 ref-deleted (object alive) check returns nonzero" "$rc"
  assert_contains "AC-W2 ref-deleted check names wip-lost" "wip-lost" "$out"
}
ac_w2_ref_deleted

echo "--- ref reseated to a different sha, baton names the old sha → wip-drift naming both ---"
ac_w2_drift() {
  local d gid snap snap2 errf rc out
  d=$(new_wip_repo); gid="wip-goal-drift"
  printf 'wip\n' > "$d/untracked.txt"
  snap=$(sdlc_wip_snapshot "$gid" "$d" 2>/dev/null)
  printf 'more wip\n' > "$d/untracked2.txt"
  snap2=$(sdlc_wip_snapshot "$gid" "$d" 2>/dev/null)     # reseats the ref to snap2
  TOTAL=$((TOTAL + 1)); if [ "$snap" != "$snap2" ]; then
    pass "AC-W2 drift fixture: the two snapshots differ"
  else fail "AC-W2 drift fixture: the two snapshots differ" "both '$snap'"; fi
  errf=$(mktemp); CLEAN_DIRS+=("$errf")
  sdlc_wip_check "$gid" "$snap" "$d" 2>"$errf"; rc=$?; out=$(cat "$errf")  # baton still names old snap
  assert_nonzero "AC-W2 drift check returns nonzero" "$rc"
  assert_contains "AC-W2 drift check names wip-drift" "wip-drift" "$out"
  assert_contains "AC-W2 drift check names the baton (old) sha" "$snap" "$out"
  assert_contains "AC-W2 drift check names the ref (new) sha" "$snap2" "$out"
}
ac_w2_drift

# ============================================================
# Effect guard (slice 4/3) — sdlc_effect_state / sdlc_effect_run: the
# exactly-once replay leg. Every case drives the REAL guard against a real
# ledger and proves the SIDE EFFECT via a counter file the command appends
# to (one line per execution) — never by inspecting the guard's return value
# alone. `counter` lines == executions; ledger effect/decision line counts
# come from awk over the real ledger file (never a reimplemented parser).
# ============================================================

# key_lines <ledger-path> <type> <key> — count of lines of that type with
# that exact effect-key (field 4 = type, field 5 = effect-key).
key_lines() { awk -F'\t' -v t="$2" -v k="$3" '$4==t && $5==k' "$1" | wc -l | tr -d ' '; }
# runs <counter-file> — how many times the guarded command executed.
runs() { wc -l < "$1" | tr -d ' '; }

echo ""
echo "=== AC-W3: effect guard idempotency — double-drive executes exactly once ==="
ac_w3() {
  new_state_dir
  local gid="effect-w3" counter key path rc
  counter=$(mktemp); CLEAN_DIRS+=("$counter"); : > "$counter"
  key="notify:slack-done"
  path="$(ledger_path "$gid")"

  sdlc_effect_run "$gid" "$key" "notify slack the run is done" -- sh -c "echo x >> '$counter'"; rc=$?
  assert_eq "AC-W3 first drive exits 0" "0" "$rc"
  assert_eq "AC-W3 first drive executed the command once (counter=1)" "1" "$(runs "$counter")"
  assert_eq "AC-W3 exactly one effect line for the key after first drive" "1" "$(key_lines "$path" effect "$key")"

  sdlc_effect_run "$gid" "$key" "notify slack the run is done" -- sh -c "echo x >> '$counter'"; rc=$?
  assert_eq "AC-W3 second drive exits 0 (idempotent success)" "0" "$rc"
  assert_eq "AC-W3 second drive did NOT re-execute (counter still 1)" "1" "$(runs "$counter")"
  assert_eq "AC-W3 still exactly one effect line for the key after second drive" "1" "$(key_lines "$path" effect "$key")"

  assert_true "AC-W3 ledger_verify passes after guard appends (chain intact)" ledger_verify "$gid"
}
ac_w3

echo ""
echo "=== AC-W4: crash window — indeterminate fails closed by default, --replay-safe completes ==="

echo "--- planted intent-without-effect, default replay parks (fail-closed J1) ---"
ac_w4_default_parks() {
  new_state_dir
  local gid="effect-w4-default" counter key errf rc
  counter=$(mktemp); CLEAN_DIRS+=("$counter"); : > "$counter"
  key="merge:pr-42"
  ledger_append "$gid" decision "$key" "intent to merge" >/dev/null   # crash window: intent, no effect
  errf=$(mktemp); CLEAN_DIRS+=("$errf")
  sdlc_effect_run "$gid" "$key" "merge pr 42" -- sh -c "echo x >> '$counter'" 2>"$errf"; rc=$?
  assert_nonzero "AC-W4 default replay of indeterminate returns nonzero" "$rc"
  assert_contains "AC-W4 default replay names effect-indeterminate" "effect-indeterminate" "$(cat "$errf")"
  assert_eq "AC-W4 default replay did NOT execute the command (counter=0)" "0" "$(runs "$counter")"
}
ac_w4_default_parks

echo "--- --replay-safe completes the journal, executes exactly once, no duplicate decision ---"
ac_w4_replay_safe_completes() {
  new_state_dir
  local gid="effect-w4-rs" counter key path rc
  counter=$(mktemp); CLEAN_DIRS+=("$counter"); : > "$counter"
  key="merge:pr-42"
  path="$(ledger_path "$gid")"
  ledger_append "$gid" decision "$key" "intent to merge" >/dev/null
  sdlc_effect_run "$gid" "$key" "merge pr 42" --replay-safe -- sh -c "echo x >> '$counter'"; rc=$?
  assert_eq "AC-W4 replay-safe of indeterminate exits 0" "0" "$rc"
  assert_eq "AC-W4 replay-safe executed exactly once (counter=1)" "1" "$(runs "$counter")"
  assert_eq "AC-W4 replay-safe completed the journal (one effect line)" "1" "$(key_lines "$path" effect "$key")"
  assert_eq "AC-W4 replay-safe did NOT journal a duplicate decision line" "1" "$(key_lines "$path" decision "$key")"
  assert_eq "AC-W4 state after replay-safe completion is applied" "applied" "$(sdlc_effect_state "$gid" "$key")"
  assert_true "AC-W4 ledger_verify passes after replay-safe completion" ledger_verify "$gid"
}
ac_w4_replay_safe_completes

echo "--- fresh key (nothing journaled) runs normally under --replay-safe ---"
ac_w4_fresh_key_runs() {
  new_state_dir
  local gid="effect-w4-fresh" counter key path rc
  counter=$(mktemp); CLEAN_DIRS+=("$counter"); : > "$counter"
  key="poke:fresh"
  path="$(ledger_path "$gid")"
  sdlc_effect_run "$gid" "$key" "poke fresh" --replay-safe -- sh -c "echo x >> '$counter'"; rc=$?
  assert_eq "AC-W4 fresh key with --replay-safe exits 0" "0" "$rc"
  assert_eq "AC-W4 fresh key executed once (counter=1)" "1" "$(runs "$counter")"
  assert_eq "AC-W4 fresh key journaled a decision line" "1" "$(key_lines "$path" decision "$key")"
  assert_eq "AC-W4 fresh key journaled an effect line" "1" "$(key_lines "$path" effect "$key")"
}
ac_w4_fresh_key_runs

echo "--- failed command: attempt stands, no effect line, state stays indeterminate ---"
ac_w4_failed_command() {
  new_state_dir
  local gid="effect-w4-fail" counter key path rc
  counter=$(mktemp); CLEAN_DIRS+=("$counter"); : > "$counter"
  key="merge:pr-99"
  path="$(ledger_path "$gid")"
  sdlc_effect_run "$gid" "$key" "merge pr 99" -- sh -c "echo x >> '$counter'; exit 3"; rc=$?
  assert_nonzero "AC-W4 failed command returns nonzero" "$rc"
  assert_eq "AC-W4 failed command still shows the attempt (counter=1)" "1" "$(runs "$counter")"
  assert_eq "AC-W4 failed command appended NO effect line" "0" "$(key_lines "$path" effect "$key")"
  assert_eq "AC-W4 failed command left the decision (intent) standing" "1" "$(key_lines "$path" decision "$key")"
  assert_eq "AC-W4 state after failed command is indeterminate" "indeterminate" "$(sdlc_effect_state "$gid" "$key")"
}
ac_w4_failed_command

echo ""
echo "=== sdlc_effect_state direct: three states + decision/effect key non-collision ==="
ac_effect_state() {
  new_state_dir
  local gid="effect-state-direct"
  assert_eq "effect_state unapplied on an absent ledger" "unapplied" "$(sdlc_effect_state "$gid" "notify:x")"

  ledger_append "$gid" decision "notify:x" "intent" >/dev/null
  assert_eq "effect_state indeterminate after a decision line only" "indeterminate" "$(sdlc_effect_state "$gid" "notify:x")"

  ledger_append "$gid" effect "notify:x" "done" >/dev/null
  assert_eq "effect_state applied once an effect line exists" "applied" "$(sdlc_effect_state "$gid" "notify:x")"

  # Non-collision (extends AC-L1's decision/effect split): an effect line for
  # key A must not make an untouched key B applied.
  assert_eq "effect_state key B unapplied though key A is applied" "unapplied" "$(sdlc_effect_state "$gid" "notify:y")"

  # A decision line alone for another key is indeterminate, never applied.
  ledger_append "$gid" decision "merge:z" "intent z" >/dev/null
  assert_eq "effect_state a decision-only key is indeterminate, not applied" "indeterminate" "$(sdlc_effect_state "$gid" "merge:z")"
}
ac_effect_state

echo "--- effect guard loud defects: invalid-goal-id + missing-effect-key (both functions) ---"
ac_effect_defects() {
  new_state_dir
  local err rc
  err=$(sdlc_effect_state "bad/goal" "notify:x" 2>&1 1>/dev/null); rc=$?
  assert_nonzero "effect_state rejects a goal-id with '/'" "$rc"
  assert_contains "effect_state '/' goal-id names invalid-goal-id" "invalid-goal-id" "$err"

  err=$(sdlc_effect_state "good-goal" "" 2>&1 1>/dev/null); rc=$?
  assert_nonzero "effect_state rejects an empty effect-key" "$rc"
  assert_contains "effect_state empty key names missing-effect-key" "missing-effect-key" "$err"

  err=$(sdlc_effect_run "bad/goal" "notify:x" "s" -- true 2>&1 1>/dev/null); rc=$?
  assert_nonzero "effect_run rejects a goal-id with '/'" "$rc"
  assert_contains "effect_run '/' goal-id names invalid-goal-id" "invalid-goal-id" "$err"

  err=$(sdlc_effect_run "good-goal" "" "s" -- true 2>&1 1>/dev/null); rc=$?
  assert_nonzero "effect_run rejects an empty effect-key" "$rc"
  assert_contains "effect_run empty key names missing-effect-key" "missing-effect-key" "$err"

  # No '--'/command → loud, never a silent no-op.
  err=$(sdlc_effect_run "good-goal" "notify:x" "s" 2>&1 1>/dev/null); rc=$?
  assert_nonzero "effect_run with no '--'/command returns nonzero" "$rc"
}
ac_effect_defects

# ============================================================
# Goal-id contract + divergence guard (FLAG 2, AS-26) — sdlc_goal_id() is
# the canonical transform for future writers (N2-N4). context-spend.sh
# keeps its own inline copy (reviewed-acceptable self-containment); this
# guard proves the two agree on a probe set of plan paths, so the two
# sites are proven byte-identical rather than assumed so. inline_goal_id
# extracts and evals the REAL line out of context-spend.sh's own source
# at test time — never a hand-copied reimplementation — so a future edit
# to either site that breaks agreement fails this test loudly.
# ============================================================

# inline_goal_id <plan-path> — runs the deployed context-spend.sh
# goal-id transform, extracted from its own source.
inline_goal_id() {
  local plan="$1" line
  line=$(grep -E '_goal_id=\$\(printf' "$REPO/hooks/context-spend.sh")
  [ -n "$line" ] || { echo "FIXTURE-ERROR: could not locate the inline goal-id transform in context-spend.sh" >&2; return 1; }
  PLAN="$plan" bash -c "$line"$'\nprintf %s "$_goal_id"'
}

echo ""
echo "=== Goal-id contract (AS-26): sdlc_goal_id() matches context-spend.sh's inline transform on a probe set ==="
ac_goal_id_divergence() {
  new_state_dir
  local probes=(
    "wave-01-substrate.plan.md"
    "WAVE-01-SUBSTRATE.plan.md"
    "wave.01.substrate.plan.md"
    "wave_01_substrate.plan.md"
    "wave 01 substrate.plan.md"
    "/some/nested/dir/wave-01-substrate.plan.md"
    "wave-01-substrate"
    "epic-10/wave-01-substrate.plan.md"
  )
  local p lib_out inline_out
  for p in "${probes[@]}"; do
    lib_out=$(sdlc_goal_id "$p")
    inline_out=$(inline_goal_id "$p")
    assert_eq "goal-id divergence guard: lib vs inline agree on '$p'" "$inline_out" "$lib_out"
  done
}
ac_goal_id_divergence

# ============================================================
# Goal-id path guards (FLAG 3) — baton_write, baton_parse, ledger_append,
# ledger_verify, ledger_applied all reject a goal-id that is empty,
# contains '/', or begins with '.' (covers '..'), via one shared helper.
# Representative coverage across the two distinct invocation surfaces:
# baton_write (positional arg) and baton_parse (value read from a file,
# a different surface entirely), plus ledger_append as the representative
# for ledger_append/ledger_verify/ledger_applied, which all call the
# identical shared helper on their own positional goal-id arg.
# ============================================================

echo ""
echo "=== Goal-id path guards (FLAG 3): reject '/' / leading '.' — nonzero + invalid-goal-id ==="

echo "--- baton_write: goal-id containing '/' ---"
ac_goal_guard_write_slash() {
  new_state_dir
  local err rc
  err=$(baton_write "bad/goal" "p" "c" "b" "i" "lc" "4" "s" "1:00000000" "na" "none" 2>&1 1>/dev/null); rc=$?
  assert_nonzero "baton_write rejects goal-id with '/'" "$rc"
  assert_contains "baton_write '/' goal-id names invalid-goal-id" "invalid-goal-id" "$err"
}
ac_goal_guard_write_slash

echo "--- baton_write: goal-id beginning with '.' ---"
ac_goal_guard_write_dot() {
  new_state_dir
  local err rc
  err=$(baton_write ".hidden-goal" "p" "c" "b" "i" "lc" "4" "s" "1:00000000" "na" "none" 2>&1 1>/dev/null); rc=$?
  assert_nonzero "baton_write rejects goal-id beginning with '.'" "$rc"
  assert_contains "baton_write leading-'.' goal-id names invalid-goal-id" "invalid-goal-id" "$err"
}
ac_goal_guard_write_dot

echo "--- baton_parse: FILE's goal-id value containing '/' (distinct surface — value from file content, not a positional arg) ---"
ac_goal_guard_parse_slash() {
  new_state_dir
  local src dst rc err
  src=$(write_healthy "guard-parse-src")
  dst="$(mktemp -d)/baton.md"; CLEAN_DIRS+=("$(dirname "$dst")")
  sed -E "s#^goal-id:.*#goal-id: bad/goal#" "$src" > "$dst"
  err=$(baton_parse "$dst" 2>&1 >/dev/null); rc=$?
  assert_nonzero "baton_parse rejects a file goal-id containing '/'" "$rc"
  assert_contains "baton_parse '/' goal-id names invalid-goal-id" "invalid-goal-id" "$err"
}
ac_goal_guard_parse_slash

echo "--- ledger_append: goal-id containing '/' (representative for ledger_append/ledger_verify/ledger_applied) ---"
ac_goal_guard_ledger_append_slash() {
  new_state_dir
  local err rc
  err=$(ledger_append "bad/goal" "decision" "k" "s" 2>&1 1>/dev/null); rc=$?
  assert_nonzero "ledger_append rejects goal-id with '/'" "$rc"
  assert_contains "ledger_append '/' goal-id names invalid-goal-id" "invalid-goal-id" "$err"
}
ac_goal_guard_ledger_append_slash

# ============================================================
# Sourced-lib nounset guard (FLAG 4) — the lib is sourced by future
# writers (N2-N4) that may not themselves run under `set -u`. A
# top-level `set -u` in the lib would leak into the sourcing shell (a
# sourced file's `set` options persist in the caller — this is not a
# subshell). Proven here by sourcing in a child WITHOUT nounset, calling
# a function with a missing optional trailing arg, then referencing a
# bare unset variable in the CALLER's own script after the source
# returns — if `-u` leaked, that bare reference aborts the script.
# ============================================================

echo ""
echo "=== Sourced-lib nounset guard (FLAG 4): sourcing must not enable -u in the caller's shell ==="
ac_nounset_no_leak() {
  new_state_dir
  local out rc
  out=$(bash -c '
    . "$1"
    baton_write "leak-goal" "p" "c" "b" "i" "lc" "4" "s" "1:00000000" "na" "none" "none" >/dev/null 2>&1
    wrc=$?
    printf "unbound-ok:%s write-rc:%s\n" "$SOME_UNSET_VAR_NEVER_DEFINED_ANYWHERE" "$wrc"
  ' bash "$LIB" 2>&1)
  rc=$?
  assert_eq "nounset leak guard: exit 0 (sourcing the lib does not enable -u in the caller shell)" "0" "$rc"
  assert_contains "nounset leak guard: bare unset-var reference survives after sourcing (no -u leak)" "unbound-ok: write-rc:0" "$out"
}
ac_nounset_no_leak

# ============================================================
# Ledger-position cross-check + reconcile (slice 4/2, AS-25 discharge) —
# sdlc_ledger_position_check and sdlc_reconcile. Fixtures drive the REAL
# functions against real batons (baton_write) + real ledgers (ledger_append)
# + hermetic repos; planted divergence one class at a time, both directions.
# ============================================================

# ledger_line_digest <ledger-path> <seq> — the stored 8-hex digest at that seq.
ledger_line_digest() { awk -F'\t' -v s="$2" '$2==s {print $3; exit}' "$1"; }

echo ""
echo "=== AC-N4: ledger-position cross-check — trailing-deletion hole demo + digest-mismatch + ledger-ahead + exact-match ==="

echo "--- 'none' position + empty/absent ledger → silent, exit 0 ---"
ac_n4_none_empty() {
  new_state_dir
  local gid="pos-none-empty" errf rc
  errf=$(mktemp); CLEAN_DIRS+=("$errf")
  sdlc_ledger_position_check "$gid" "none" 2>"$errf"; rc=$?
  assert_eq "AC-N4 none+empty exits 0" "0" "$rc"
  assert_eq "AC-N4 none+empty silent on stderr" "" "$(cat "$errf")"
}
ac_n4_none_empty

echo "--- 'none' position + non-empty ledger → ledger-ahead (entries the baton never saw) ---"
ac_n4_none_nonempty() {
  new_state_dir
  local gid="pos-none-nonempty" path errf rc out
  path=$(build_healthy_ledger "$gid")
  errf=$(mktemp); CLEAN_DIRS+=("$errf")
  sdlc_ledger_position_check "$gid" "none" 2>"$errf"; rc=$?; out=$(cat "$errf")
  assert_nonzero "AC-N4 none+non-empty returns nonzero" "$rc"
  assert_contains "AC-N4 none+non-empty names ledger-ahead" "ledger-ahead" "$out"
  assert_contains "AC-N4 none+non-empty says 'baton at none'" "baton at none" "$out"
}
ac_n4_none_nonempty

echo "--- HOLE DEMO (AS-25): trailing line deleted — ledger_verify ALONE passes, position cross-check catches it ---"
ac_n4_hole_demo() {
  new_state_dir
  local gid="pos-hole" path tail_seq tail_dig errf rc out
  path=$(build_healthy_ledger "$gid")            # seq 1..3
  tail_seq=$(tail -n 1 "$path" | awk -F'\t' '{print $2}')
  tail_dig=$(ledger_line_digest "$path" "$tail_seq")
  # Delete the trailing line — a clean whole-line truncation.
  awk -v ln="$tail_seq" 'NR!=ln' "$path" > "$path.new" && mv "$path.new" "$path"
  # LOAD-BEARING (AS-25 residual documented): the chain cannot see a trailing
  # deletion — ledger_verify ALONE still exits 0. This assertion PROVES the hole
  # the position cross-check closes; it must pass in RED as well as GREEN.
  assert_true "AC-N4 HOLE DEMO ledger_verify ALONE passes after trailing deletion (the hole)" ledger_verify "$gid"
  # The cross-check, holding the baton's recorded tail position, catches it.
  errf=$(mktemp); CLEAN_DIRS+=("$errf")
  sdlc_ledger_position_check "$gid" "$tail_seq:$tail_dig" 2>"$errf"; rc=$?; out=$(cat "$errf")
  assert_nonzero "AC-N4 HOLE DEMO position cross-check catches the trailing deletion (nonzero)" "$rc"
  assert_contains "AC-N4 HOLE DEMO names ledger-truncated" "ledger-truncated" "$out"
  assert_contains "AC-N4 HOLE DEMO says trailing entries missing" "trailing entries missing" "$out"
}
ac_n4_hole_demo

echo "--- exact match (tail seq + digest) → silent, exit 0 (positive control) ---"
ac_n4_exact() {
  new_state_dir
  local gid="pos-exact" path tail_seq tail_dig errf rc
  path=$(build_healthy_ledger "$gid")
  tail_seq=$(tail -n 1 "$path" | awk -F'\t' '{print $2}')
  tail_dig=$(ledger_line_digest "$path" "$tail_seq")
  errf=$(mktemp); CLEAN_DIRS+=("$errf")
  sdlc_ledger_position_check "$gid" "$tail_seq:$tail_dig" 2>"$errf"; rc=$?
  assert_eq "AC-N4 exact-match exits 0" "0" "$rc"
  assert_eq "AC-N4 exact-match silent on stderr" "" "$(cat "$errf")"
}
ac_n4_exact

echo "--- digest mismatch at the recorded seq (rewrite-at-position) → ledger-truncated naming both digests ---"
ac_n4_digest_mismatch() {
  new_state_dir
  local gid="pos-rewrite" path real_dig errf rc out
  path=$(build_healthy_ledger "$gid")            # seq 1..3
  real_dig=$(ledger_line_digest "$path" 2)
  errf=$(mktemp); CLEAN_DIRS+=("$errf")
  # Baton claims seq 2 with a WRONG digest; tail (3) >= 2 so it is not a length
  # truncation — the stored digest at line 2 refutes the baton's recorded one.
  sdlc_ledger_position_check "$gid" "2:00000000" 2>"$errf"; rc=$?; out=$(cat "$errf")
  assert_nonzero "AC-N4 digest-mismatch returns nonzero" "$rc"
  assert_contains "AC-N4 digest-mismatch names ledger-truncated" "ledger-truncated" "$out"
  assert_contains "AC-N4 digest-mismatch names the baton digest" "00000000" "$out"
  assert_contains "AC-N4 digest-mismatch names the ledger's stored digest" "$real_dig" "$out"
}
ac_n4_digest_mismatch

echo "--- tail seq > baton seq (matching digest at the recorded seq) → ledger-ahead ---"
ac_n4_ahead() {
  new_state_dir
  local gid="pos-ahead" path dig2 errf rc out
  path=$(build_healthy_ledger "$gid")            # seq 1..3
  dig2=$(ledger_line_digest "$path" 2)
  errf=$(mktemp); CLEAN_DIRS+=("$errf")
  # Baton is at seq 2 with the CORRECT digest, but the ledger has grown to 3 —
  # decisions post-date the checkpoint.
  sdlc_ledger_position_check "$gid" "2:$dig2" 2>"$errf"; rc=$?; out=$(cat "$errf")
  assert_nonzero "AC-N4 ledger-ahead returns nonzero" "$rc"
  assert_contains "AC-N4 ledger-ahead names ledger-ahead" "ledger-ahead" "$out"
  assert_contains "AC-N4 ledger-ahead says 'baton at 2'" "baton at 2" "$out"
}
ac_n4_ahead

echo "--- chain defect passes through under its own name (verify runs first) ---"
ac_n4_chain_passthrough() {
  new_state_dir
  local gid="pos-chain" path tail_seq tail_dig errf rc out
  path=$(build_healthy_ledger "$gid")
  tail_seq=$(tail -n 1 "$path" | awk -F'\t' '{print $2}')
  tail_dig=$(ledger_line_digest "$path" "$tail_seq")
  # Tamper line 2's summary WITHOUT touching its digest → in-place-edit.
  awk -F'\t' -v OFS='\t' 'NR==2 { $6="TAMPERED" } { print }' "$path" > "$path.new" && mv "$path.new" "$path"
  errf=$(mktemp); CLEAN_DIRS+=("$errf")
  sdlc_ledger_position_check "$gid" "$tail_seq:$tail_dig" 2>"$errf"; rc=$?; out=$(cat "$errf")
  assert_nonzero "AC-N4 chain defect returns nonzero" "$rc"
  assert_contains "AC-N4 chain defect passes through as in-place-edit" "in-place-edit" "$out"
}
ac_n4_chain_passthrough

echo "--- position-check goal-id guard: '/' → invalid-goal-id ---"
ac_n4_guard() {
  new_state_dir
  local err rc
  err=$(sdlc_ledger_position_check "bad/goal" "none" 2>&1 1>/dev/null); rc=$?
  assert_nonzero "AC-N4 position-check rejects a '/' goal-id" "$rc"
  assert_contains "AC-N4 position-check '/' names invalid-goal-id" "invalid-goal-id" "$err"
}
ac_n4_guard

# ============================================================
echo ""
echo "=== D-C10: spine-class ledger-ahead amendment — supervision trailing entries benign, passenger/garbled still park ==="

# lp_spine_benign <class> — a trailing entry of a CLOSED spine class past the
# baton's recorded position is a benign supervision event: no ledger-ahead.
# (Fails TODAY: any growth past the position fires ledger-ahead.)
lp_spine_benign() {
  new_state_dir
  local cls="$1"
  local gid="pos-spine-$cls" path dig1 errf rc out
  ledger_append "$gid" "decision" "seed:baseline" "baseline entry" >/dev/null 2>&1   # seq 1 (baton pos)
  path=$(ledger_path "$gid")
  dig1=$(ledger_line_digest "$path" 1)
  ledger_append "$gid" "effect" "$cls:g:detail:100:1" "trailing supervision event" >/dev/null 2>&1  # seq 2 (trailing)
  errf=$(mktemp); CLEAN_DIRS+=("$errf")
  sdlc_ledger_position_check "$gid" "1:$dig1" 2>"$errf"; rc=$?; out=$(cat "$errf")
  assert_eq "D-C10 trailing '$cls:' past baton pos → silent pass (rc 0)" "0" "$rc"
  assert_eq "D-C10 trailing '$cls:' silent on stderr" "" "$out"
}
for _c in rung park spawn complete poke; do lp_spine_benign "$_c"; done

echo "--- multiple trailing spine-class entries (rung then park) → still benign ---"
lp_spine_multi() {
  new_state_dir
  local gid="pos-spine-multi" path dig1 errf rc out
  ledger_append "$gid" "decision" "seed:baseline" "baseline" >/dev/null 2>&1        # seq 1 (baton pos)
  path=$(ledger_path "$gid")
  dig1=$(ledger_line_digest "$path" 1)
  ledger_append "$gid" "decision" "rung:g:poke:100:1" "poke attempt journaled" >/dev/null 2>&1  # seq 2
  ledger_append "$gid" "effect"   "park:g:ladder-exhausted" "escalated to human" >/dev/null 2>&1  # seq 3
  errf=$(mktemp); CLEAN_DIRS+=("$errf")
  sdlc_ledger_position_check "$gid" "1:$dig1" 2>"$errf"; rc=$?; out=$(cat "$errf")
  assert_eq "D-C10 two trailing spine entries → silent pass (rc 0)" "0" "$rc"
  assert_eq "D-C10 two trailing spine entries silent on stderr" "" "$out"
}
lp_spine_multi

echo "--- trailing PASSENGER-class entry (merge:) past baton pos → ledger-ahead still fires ---"
lp_passenger() {
  new_state_dir
  local gid="pos-passenger" path dig1 errf rc out
  ledger_append "$gid" "decision" "seed:baseline" "baseline" >/dev/null 2>&1        # seq 1 (baton pos)
  path=$(ledger_path "$gid")
  dig1=$(ledger_line_digest "$path" 1)
  ledger_append "$gid" "effect" "merge:pr-42" "a passenger merge, not supervision" >/dev/null 2>&1  # seq 2
  errf=$(mktemp); CLEAN_DIRS+=("$errf")
  sdlc_ledger_position_check "$gid" "1:$dig1" 2>"$errf"; rc=$?; out=$(cat "$errf")
  assert_nonzero "D-C10 trailing passenger 'merge:' → ledger-ahead (nonzero)" "$rc"
  assert_contains "D-C10 passenger names ledger-ahead" "ledger-ahead" "$out"
}
lp_passenger

echo "--- MIXED trailing: one spine (rung:) + one passenger (merge:) → ledger-ahead (any passenger trips it) ---"
lp_mixed() {
  new_state_dir
  local gid="pos-mixed" path dig1 errf rc out
  ledger_append "$gid" "decision" "seed:baseline" "baseline" >/dev/null 2>&1        # seq 1 (baton pos)
  path=$(ledger_path "$gid")
  dig1=$(ledger_line_digest "$path" 1)
  ledger_append "$gid" "decision" "rung:g:poke:100:1" "supervision" >/dev/null 2>&1  # seq 2 (spine)
  ledger_append "$gid" "effect"   "merge:pr-9" "a passenger slipped in" >/dev/null 2>&1  # seq 3 (passenger)
  errf=$(mktemp); CLEAN_DIRS+=("$errf")
  sdlc_ledger_position_check "$gid" "1:$dig1" 2>"$errf"; rc=$?; out=$(cat "$errf")
  assert_nonzero "D-C10 mixed spine+passenger → ledger-ahead (nonzero)" "$rc"
  assert_contains "D-C10 mixed names ledger-ahead" "ledger-ahead" "$out"
}
lp_mixed

echo "--- garbled trailing class (no ':' delimiter) → ledger-ahead (fail-closed: unknown = passenger) ---"
lp_garbled() {
  new_state_dir
  local gid="pos-garbled" path dig1 errf rc out
  ledger_append "$gid" "decision" "seed:baseline" "baseline" >/dev/null 2>&1        # seq 1 (baton pos)
  path=$(ledger_path "$gid")
  dig1=$(ledger_line_digest "$path" 1)
  ledger_append "$gid" "effect" "garbled" "a delimiter-less key" >/dev/null 2>&1     # seq 2, class "garbled"
  errf=$(mktemp); CLEAN_DIRS+=("$errf")
  sdlc_ledger_position_check "$gid" "1:$dig1" 2>"$errf"; rc=$?; out=$(cat "$errf")
  assert_nonzero "D-C10 garbled (no ':') trailing → ledger-ahead (nonzero)" "$rc"
  assert_contains "D-C10 garbled names ledger-ahead" "ledger-ahead" "$out"
}
lp_garbled

echo "--- empty trailing class (leading ':') → ledger-ahead (fail-closed) ---"
lp_empty_class() {
  new_state_dir
  local gid="pos-empty-class" path dig1 errf rc out
  ledger_append "$gid" "decision" "seed:baseline" "baseline" >/dev/null 2>&1        # seq 1 (baton pos)
  path=$(ledger_path "$gid")
  dig1=$(ledger_line_digest "$path" 1)
  ledger_append "$gid" "effect" ":orphan" "empty class prefix" >/dev/null 2>&1       # seq 2, class ""
  errf=$(mktemp); CLEAN_DIRS+=("$errf")
  sdlc_ledger_position_check "$gid" "1:$dig1" 2>"$errf"; rc=$?; out=$(cat "$errf")
  assert_nonzero "D-C10 empty-class (leading ':') trailing → ledger-ahead (nonzero)" "$rc"
  assert_contains "D-C10 empty-class names ledger-ahead" "ledger-ahead" "$out"
}
lp_empty_class

# ============================================================
echo ""
echo "=== D-C11: ledger_append per-goal single-writer lock — race repro, held-lock timeout, stale reclaim ==="

# back_date <path> <seconds-ago> — set mtime into the past (BSD `touch -t`
# first, GNU `touch -d` fallback); heritage of the poker suite's set_mtime_age.
back_date() {
  local f="$1" age="$2" ts
  if ts=$(date -v "-${age}S" +%Y%m%d%H%M.%S 2>/dev/null); then
    touch -t "$ts" "$f"
  else
    touch -d "@$(( $(date +%s) - age ))" "$f"
  fi
}

echo "--- concurrent-append race: two interleaved writers → strictly monotonic seqs, chain verifies (collides pre-lock) ---"
lock_race_monotonic() {
  new_state_dir
  local gid="lock-race" path ready hold apid bpid i seqs
  ledger_append "$gid" "decision" "seed:baseline" "seed" >/dev/null 2>&1             # seq 1
  path=$(ledger_path "$gid")
  ready=$(mktemp -u); hold=$(mktemp)   # $hold EXISTS → writer A parks in the window; $ready ABSENT → A creates it
  CLEAN_DIRS+=("$ready" "$hold")
  # Writer A parks in the read-tail→write window (via the test seam) holding
  # whatever lock ledger_append took, until we remove $hold.
  bash -c '. "$1"; SDLC_LEDGER_SEAM_READY="$3" SDLC_LEDGER_SEAM_HOLD="$4" ledger_append "$2" decision "writer:a" "A" >/dev/null 2>&1' \
    _ "$LIB" "$gid" "$ready" "$hold" &
  apid=$!
  # Wait until A has entered the window (read the tail).
  i=0; while [ ! -e "$ready" ] && [ "$i" -lt 300 ]; do sleep 0.02; i=$((i + 1)); done
  # Writer B, no seam. Pre-lock: reads the SAME tail A saw → seq collision.
  # Post-lock: blocks on the lock A holds until A releases → next seq.
  bash -c '. "$1"; ledger_append "$2" decision "writer:b" "B" >/dev/null 2>&1' _ "$LIB" "$gid" &
  bpid=$!
  sleep 0.4               # let B reach its write (pre-lock) or park on the lock (post-lock)
  rm -f "$hold"           # release A → it appends
  wait "$apid" 2>/dev/null; wait "$bpid" 2>/dev/null
  seqs=$(awk -F'\t' '{printf "%s ", $2}' "$path"); seqs="${seqs% }"
  assert_eq "D-C11 race drive yields strictly monotonic seqs (1 2 3)" "1 2 3" "$seqs"
  assert_true "D-C11 race-driven ledger verifies (chain intact)" ledger_verify "$gid"
}
lock_race_monotonic

echo "--- held lock (fresh, live holder) → ledger-locked defect, rc 1, ledger byte-unchanged ---"
lock_held_timeout() {
  new_state_dir
  local gid="lock-held" path lockdir before after errf rc
  local SDLC_LEDGER_LOCK_TRIES=3     # 3 x 0.1s → fast timeout
  ledger_append "$gid" "decision" "seed:baseline" "seed" >/dev/null 2>&1             # seq 1
  path=$(ledger_path "$gid")
  before=$(cksum < "$path")
  lockdir="$SDLC_STATE_DIR/$gid/.ledger.lock"
  mkdir "$lockdir"                    # fresh mtime = now → a LIVE holder, not stale
  errf=$(mktemp); CLEAN_DIRS+=("$errf")
  ledger_append "$gid" "decision" "blocked:write" "must not land" 2>"$errf"; rc=$?
  after=$(cksum < "$path")
  assert_nonzero "D-C11 held lock → append returns nonzero" "$rc"
  assert_contains "D-C11 held lock names ledger-locked" "ledger-locked" "$(cat "$errf")"
  assert_contains "D-C11 ledger-locked names the goal-id" "$gid" "$(cat "$errf")"
  assert_eq "D-C11 held lock → ledger byte-unchanged" "$before" "$after"
  rmdir "$lockdir" 2>/dev/null
}
lock_held_timeout

echo "--- stale lock (mtime back-dated past SDLC_LEDGER_LOCK_STALE) → reclaimed, append succeeds ---"
lock_stale_reclaim() {
  new_state_dir
  local gid="lock-stale" path lockdir rc
  local SDLC_LEDGER_LOCK_TRIES=3
  ledger_append "$gid" "decision" "seed:baseline" "seed" >/dev/null 2>&1             # seq 1
  path=$(ledger_path "$gid")
  lockdir="$SDLC_STATE_DIR/$gid/.ledger.lock"
  mkdir "$lockdir"
  back_date "$lockdir" 120            # older than default 60s stale ceiling → reclaimable
  ledger_append "$gid" "decision" "after:reclaim" "lands after stale reclaim" >/dev/null 2>&1; rc=$?
  assert_eq "D-C11 back-dated stale lock → append succeeds (rc 0)" "0" "$rc"
  assert_eq "D-C11 stale reclaim → ledger now has 2 lines" "2" "$(wc -l < "$path" | tr -d ' ')"
  assert_true "D-C11 stale-reclaim ledger verifies" ledger_verify "$gid"
}
lock_stale_reclaim

# ---------- reconcile fixtures ----------
# setup_reconcile <goal-id> [current] — sets REPO_DIR + PLAN_STUB globals (NOT
# echoed: it must run in THIS shell, not a command-substitution subshell, so
# new_state_dir's HOME/SDLC_STATE_DIR exports reach the parent — a subshell
# would lose them and the baton/plan would land under a stale dir). Freshens
# HOME/SDLC_STATE_DIR, builds a hermetic repo, and writes a plan stub OUTSIDE
# the repo worktree (so it never perturbs the worktree-tree comparison in
# predicate 7). Callers: `setup_reconcile "$gid" 4; d="$REPO_DIR"`.
setup_reconcile() {
  local gid="$1" current="${2:-4}"
  new_state_dir
  REPO_DIR=$(mktemp -d); CLEAN_DIRS+=("$REPO_DIR")
  git -C "$REPO_DIR" init -q
  git -C "$REPO_DIR" config user.name  "fixture"
  git -C "$REPO_DIR" config user.email "fixture@example.com"
  printf 'base line\n' > "$REPO_DIR/tracked.txt"
  git -C "$REPO_DIR" add -A
  git -C "$REPO_DIR" commit -qm base
  mkdir -p "$SDLC_STATE_DIR/$gid"
  PLAN_STUB="$SDLC_STATE_DIR/$gid/plan.stub.md"
  printf 'current: %s\n' "$current" > "$PLAN_STUB"
}
# write_recon_baton <gid> <repo-dir> <current> <ledger-pos> <wip> — an aligned
# healthy baton whose branch/last-commit track the repo's real HEAD.
write_recon_baton() {
  local gid="$1" d="$2" current="$3" lpos="$4" wip="$5"
  baton_write "$gid" "$PLAN_STUB" "$d" "$(git -C "$d" rev-parse --abbrev-ref HEAD)" \
    "epic/10-never-die" "$(git -C "$d" rev-parse HEAD)" "$current" "sid-$gid/1" \
    "$lpos" "resume the slice" "$wip" "none" >/dev/null 2>&1
}

echo ""
echo "=== AC-N2/AC-N5: sdlc_reconcile — clean/restore verdicts + each planted divergence parks (both directions) ==="

echo "--- clean fixture (wip none, clean worktree) → 'clean' verdict, exit 0 ---"
ac_recon_clean_none() {
  local gid="recon-clean-none" d errf out rc
  setup_reconcile "$gid" 4; d="$REPO_DIR"
  write_recon_baton "$gid" "$d" 4 none none
  errf=$(mktemp); CLEAN_DIRS+=("$errf")
  out=$(sdlc_reconcile "$gid" "$d" 2>"$errf"); rc=$?
  assert_eq "AC-N2 clean fixture exits 0" "0" "$rc"
  assert_eq "AC-N2 clean fixture prints the 'clean' verdict token" "clean" "$out"
  assert_eq "AC-N2 clean fixture silent on stderr" "" "$(cat "$errf")"
}
ac_recon_clean_none

echo "--- current: with a trailing CR (CRLF plan) → parses as clean, not false baton-stale ---"
ac_recon_current_crlf() {
  local gid="recon-current-crlf" d errf out rc
  setup_reconcile "$gid" 4; d="$REPO_DIR"
  printf 'current: 4\r\n' > "$PLAN_STUB"          # CRLF line ending leaves "4\r" without a trailing trim
  write_recon_baton "$gid" "$d" 4 none none        # baton sdlc-step: 4
  errf=$(mktemp); CLEAN_DIRS+=("$errf")
  out=$(sdlc_reconcile "$gid" "$d" 2>"$errf"); rc=$?
  assert_eq "reconcile CRLF current: exits 0" "0" "$rc"
  assert_eq "reconcile CRLF current: prints 'clean'" "clean" "$out"
  assert_eq "reconcile CRLF current: silent on stderr" "" "$(cat "$errf")"
}
ac_recon_current_crlf

echo "--- clean fixture with a present WIP (worktree == snapshot) → 'clean' verdict ---"
ac_recon_clean_wip_present() {
  local gid="recon-clean-wip" d snap errf out rc
  setup_reconcile "$gid" 4; d="$REPO_DIR"
  printf 'work in progress\n' > "$d/wip.txt"
  snap=$(sdlc_wip_snapshot "$gid" "$d" 2>/dev/null)   # snap tree = HEAD + wip.txt; worktree still has wip.txt
  write_recon_baton "$gid" "$d" 4 none "$snap"
  errf=$(mktemp); CLEAN_DIRS+=("$errf")
  out=$(sdlc_reconcile "$gid" "$d" 2>"$errf"); rc=$?
  assert_eq "AC-N5 wip-present fixture exits 0" "0" "$rc"
  assert_eq "AC-N5 wip-present (worktree==snapshot) prints 'clean'" "clean" "$out"
}
ac_recon_clean_wip_present

echo "--- clobbered worktree (worktree == HEAD, baton names a wip sha) → 'restore:<sha>' verdict ---"
ac_recon_restore() {
  local gid="recon-restore" d snap errf out rc
  setup_reconcile "$gid" 4; d="$REPO_DIR"
  printf 'work in progress\n' > "$d/wip.txt"
  snap=$(sdlc_wip_snapshot "$gid" "$d" 2>/dev/null)
  rm -f "$d/wip.txt"                                   # clobber: worktree back to HEAD
  write_recon_baton "$gid" "$d" 4 none "$snap"
  errf=$(mktemp); CLEAN_DIRS+=("$errf")
  out=$(sdlc_reconcile "$gid" "$d" 2>"$errf"); rc=$?
  assert_eq "AC-N5 clobbered fixture exits 0" "0" "$rc"
  assert_eq "AC-N5 clobbered (worktree==HEAD + wip sha) prints 'restore:<sha>'" "restore:$snap" "$out"
}
ac_recon_restore

# ---------- F1 (critic): mixed-WIP triage over a force-included snapshot ----------
# The existing AC-N5 clean/restore fixtures snapshot with NO force-include, so a
# snapshot tree that carries a gitignored lifecycle artifact was never exercised.
# These three fixtures snapshot WITH a force-include path (.bionic/docs) atop a
# tracked edit — a faithful mixed WIP — and assert the triage classifies it as
# clean/restore/drift by CONTENT, not by whole-tree equality (which the plain
# `add -A` worktree tree can never satisfy once the snapshot force-included a
# gitignored path).
echo "--- F1 mixed WIP (tracked edit + force-included gitignored artifact) faithfully present → 'clean' ---"
ac_recon_mixed_wip_clean() {
  local gid="recon-mixed-clean" d snap errf out rc
  setup_reconcile "$gid" 4; d="$REPO_DIR"
  printf '.bionic/\n' > "$d/.gitignore"
  git -C "$d" add -A; git -C "$d" commit -qm gitignore     # .bionic/ ignored, committed into base
  printf 'v2 work in progress\n' > "$d/tracked.txt"        # tracked edit
  mkdir -p "$d/.bionic/docs"; printf 'plan wip\n' > "$d/.bionic/docs/plan.md"  # gitignored artifact
  snap=$(sdlc_wip_snapshot "$gid" "$d" ".bionic/docs" 2>/dev/null)   # force-include the gitignored path
  write_recon_baton "$gid" "$d" 4 none "$snap"
  errf=$(mktemp); CLEAN_DIRS+=("$errf")
  out=$(sdlc_reconcile "$gid" "$d" 2>"$errf"); rc=$?
  assert_eq "AC-N5 mixed-WIP faithfully present exits 0" "0" "$rc"
  assert_eq "AC-N5 mixed-WIP (tracked edit + force-included artifact) prints 'clean'" "clean" "$out"
  assert_eq "AC-N5 mixed-WIP clean silent on stderr" "" "$(cat "$errf")"
}
ac_recon_mixed_wip_clean

echo "--- F1 mixed WIP clobbered (both paths back to HEAD) → 'restore:<sha>' ---"
ac_recon_mixed_wip_clobbered() {
  local gid="recon-mixed-clobber" d snap errf out rc
  setup_reconcile "$gid" 4; d="$REPO_DIR"
  printf '.bionic/\n' > "$d/.gitignore"
  git -C "$d" add -A; git -C "$d" commit -qm gitignore
  printf 'v2 work in progress\n' > "$d/tracked.txt"
  mkdir -p "$d/.bionic/docs"; printf 'plan wip\n' > "$d/.bionic/docs/plan.md"
  snap=$(sdlc_wip_snapshot "$gid" "$d" ".bionic/docs" 2>/dev/null)
  git -C "$d" checkout -q -- tracked.txt                   # revert tracked edit to HEAD
  rm -rf "$d/.bionic"                                      # drop the force-included artifact
  write_recon_baton "$gid" "$d" 4 none "$snap"
  errf=$(mktemp); CLEAN_DIRS+=("$errf")
  out=$(sdlc_reconcile "$gid" "$d" 2>"$errf"); rc=$?
  assert_eq "AC-N5 mixed-WIP clobbered exits 0" "0" "$rc"
  assert_eq "AC-N5 mixed-WIP clobbered (both paths back to HEAD) prints 'restore:<sha>'" "restore:$snap" "$out"
}
ac_recon_mixed_wip_clobbered

echo "--- F1 mixed WIP, genuine third-writer divergence on a snapshot path → 'worktree-drift' ---"
ac_recon_mixed_wip_drift() {
  local gid="recon-mixed-drift" d snap err rc
  setup_reconcile "$gid" 4; d="$REPO_DIR"
  printf '.bionic/\n' > "$d/.gitignore"
  git -C "$d" add -A; git -C "$d" commit -qm gitignore
  printf 'v2 work in progress\n' > "$d/tracked.txt"
  mkdir -p "$d/.bionic/docs"; printf 'plan wip\n' > "$d/.bionic/docs/plan.md"
  snap=$(sdlc_wip_snapshot "$gid" "$d" ".bionic/docs" 2>/dev/null)
  printf 'v3 a third writer clobbered this\n' > "$d/tracked.txt"   # neither HEAD nor snapshot
  write_recon_baton "$gid" "$d" 4 none "$snap"
  err=$(sdlc_reconcile "$gid" "$d" 2>&1 1>/dev/null); rc=$?
  assert_nonzero "AC-N5 mixed-WIP third-writer returns nonzero" "$rc"
  assert_contains "AC-N5 mixed-WIP third-writer names worktree-drift" "worktree-drift" "$err"
  assert_contains "AC-N5 mixed-WIP third-writer says 'matches neither'" "matches neither" "$err"
}
ac_recon_mixed_wip_drift

echo "--- baton-stale: sdlc-step != plan current → baton-stale naming both ---"
ac_recon_stale_step() {
  local gid="recon-stale-step" d err rc
  setup_reconcile "$gid" 5; d="$REPO_DIR"                        # plan current: 5
  write_recon_baton "$gid" "$d" 4 none none            # baton sdlc-step: 4
  err=$(sdlc_reconcile "$gid" "$d" 2>&1 1>/dev/null); rc=$?
  assert_nonzero "AC-N2 step-mismatch returns nonzero" "$rc"
  assert_contains "AC-N2 step-mismatch names baton-stale" "baton-stale" "$err"
  assert_contains "AC-N2 step-mismatch names the baton step" "baton step 4" "$err"
  assert_contains "AC-N2 step-mismatch names the plan current" "plan current 5" "$err"
}
ac_recon_stale_step

echo "--- baton-stale: last-commit != branch tip (branch advanced after checkpoint) → baton-stale ---"
ac_recon_stale_tip() {
  local gid="recon-stale-tip" d err rc
  setup_reconcile "$gid" 4; d="$REPO_DIR"
  write_recon_baton "$gid" "$d" 4 none none            # last-commit = current tip
  printf 'later work\n' > "$d/later.txt"; git -C "$d" add -A; git -C "$d" commit -qm later  # advance tip
  err=$(sdlc_reconcile "$gid" "$d" 2>&1 1>/dev/null); rc=$?
  assert_nonzero "AC-N2 tip-advanced returns nonzero" "$rc"
  assert_contains "AC-N2 tip-advanced names baton-stale" "baton-stale" "$err"
  assert_contains "AC-N2 tip-advanced says 'not branch tip'" "not branch tip" "$err"
}
ac_recon_stale_tip

echo "--- plan file missing → plan-unreadable ---"
ac_recon_plan_missing() {
  local gid="recon-plan-missing" d err rc
  setup_reconcile "$gid" 4; d="$REPO_DIR"
  write_recon_baton "$gid" "$d" 4 none none
  rm -f "$PLAN_STUB"
  err=$(sdlc_reconcile "$gid" "$d" 2>&1 1>/dev/null); rc=$?
  assert_nonzero "AC-N2 plan-missing returns nonzero" "$rc"
  assert_contains "AC-N2 plan-missing names plan-unreadable" "plan-unreadable" "$err"
}
ac_recon_plan_missing

echo "--- plan present but no parseable 'current:' line → plan-unreadable ---"
ac_recon_plan_no_current() {
  local gid="recon-plan-nocurrent" d err rc
  setup_reconcile "$gid" 4; d="$REPO_DIR"
  write_recon_baton "$gid" "$d" 4 none none
  printf 'no current key here\n' > "$PLAN_STUB"
  err=$(sdlc_reconcile "$gid" "$d" 2>&1 1>/dev/null); rc=$?
  assert_nonzero "AC-N2 plan-no-current returns nonzero" "$rc"
  assert_contains "AC-N2 plan-no-current names plan-unreadable" "plan-unreadable" "$err"
}
ac_recon_plan_no_current

echo "--- malformed baton passes through (parse defect family) ---"
ac_recon_baton_malformed() {
  local gid="recon-malformed" d err rc baton
  setup_reconcile "$gid" 4; d="$REPO_DIR"
  write_recon_baton "$gid" "$d" 4 none none
  baton=$(baton_path "$gid")
  grep -v -E '^next-action:' "$baton" > "$baton.new" && mv "$baton.new" "$baton"   # drop a required key
  err=$(sdlc_reconcile "$gid" "$d" 2>&1 1>/dev/null); rc=$?
  assert_nonzero "AC-N2 malformed-baton returns nonzero" "$rc"
  assert_contains "AC-N2 malformed-baton passes through the parse defect" "missing-key" "$err"
}
ac_recon_baton_malformed

echo "--- ledger-position cross-check passes through (ledger-ahead) ---"
ac_recon_ledger_passthrough() {
  local gid="recon-ledger" d err rc
  setup_reconcile "$gid" 4; d="$REPO_DIR"
  build_healthy_ledger "$gid" >/dev/null              # non-empty ledger
  write_recon_baton "$gid" "$d" 4 none none           # baton ledger-position: none
  err=$(sdlc_reconcile "$gid" "$d" 2>&1 1>/dev/null); rc=$?
  assert_nonzero "AC-N4 reconcile ledger-position pass-through returns nonzero" "$rc"
  assert_contains "AC-N4 reconcile passes through ledger-ahead" "ledger-ahead" "$err"
}
ac_recon_ledger_passthrough

echo "--- WIP check passes through (wip-lost: baton names a sha with no ref/object) ---"
ac_recon_wip_passthrough() {
  local gid="recon-wiplost" d err rc
  setup_reconcile "$gid" 4; d="$REPO_DIR"
  write_recon_baton "$gid" "$d" 4 none "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"  # full 40-hex, absent object
  err=$(sdlc_reconcile "$gid" "$d" 2>&1 1>/dev/null); rc=$?
  assert_nonzero "AC-N5 reconcile wip-check pass-through returns nonzero" "$rc"
  assert_contains "AC-N5 reconcile passes through wip-lost" "wip-lost" "$err"
}
ac_recon_wip_passthrough

echo "--- worktree-drift: wip none but a dirty worktree (unexplained work product) → worktree-drift ---"
ac_recon_drift_none() {
  local gid="recon-drift-none" d err rc
  setup_reconcile "$gid" 4; d="$REPO_DIR"
  write_recon_baton "$gid" "$d" 4 none none
  printf 'unexplained\n' > "$d/surprise.txt"           # dirty worktree, baton says wip none
  err=$(sdlc_reconcile "$gid" "$d" 2>&1 1>/dev/null); rc=$?
  assert_nonzero "AC-N5 wip-none dirty-worktree returns nonzero" "$rc"
  assert_contains "AC-N5 wip-none dirty-worktree names worktree-drift" "worktree-drift" "$err"
  assert_contains "AC-N5 wip-none dirty-worktree says 'unexplained work product'" "unexplained work product" "$err"
}
ac_recon_drift_none

echo "--- worktree-drift: worktree matches NEITHER HEAD nor snapshot (third writer) → worktree-drift ---"
ac_recon_drift_neither() {
  local gid="recon-drift-neither" d snap err rc
  setup_reconcile "$gid" 4; d="$REPO_DIR"
  printf 'wip one\n' > "$d/wip.txt"
  snap=$(sdlc_wip_snapshot "$gid" "$d" 2>/dev/null)   # snap = HEAD + wip.txt (ref seated once)
  printf 'third writer\n' > "$d/wip2.txt"              # worktree now HEAD + wip.txt + wip2.txt (matches neither)
  write_recon_baton "$gid" "$d" 4 none "$snap"
  err=$(sdlc_reconcile "$gid" "$d" 2>&1 1>/dev/null); rc=$?
  assert_nonzero "AC-N5 third-writer drift returns nonzero" "$rc"
  assert_contains "AC-N5 third-writer names worktree-drift" "worktree-drift" "$err"
  assert_contains "AC-N5 third-writer says 'matches neither'" "matches neither" "$err"
}
ac_recon_drift_neither

echo "--- reconcile goal-id guard: '/' → invalid-goal-id ---"
ac_recon_guard() {
  new_state_dir
  local err rc
  err=$(sdlc_reconcile "bad/goal" "." 2>&1 1>/dev/null); rc=$?
  assert_nonzero "reconcile rejects a '/' goal-id" "$rc"
  assert_contains "reconcile '/' names invalid-goal-id" "invalid-goal-id" "$err"
}
ac_recon_guard

# ============================================================
# Completion latch (slice 4/3, spec D2) — sdlc_complete_check. Fixtures build
# a hermetic repo with two REAL named branches (goal-branch, integ-branch),
# merged or left unmerged one class at a time, plus a plan stub (current:)
# and a real baton (baton_write). rc semantics under test: 0 verified / 1
# benign not-complete / 2 loud false-complete-or-defect.
# ============================================================

# setup_complete <goal-id> <current> [merge: yes|no, default yes] — sets
# REPO_DIR + PLAN_STUB globals (NOT echoed — must run in THIS shell so
# new_state_dir's HOME/SDLC_STATE_DIR exports reach the parent). Builds a
# repo with goal-branch branched from integ-branch's base commit, one extra
# commit on goal-branch; merge=yes fast-forwards integ-branch to goal-branch's
# tip (branch tip becomes an ancestor), merge=no leaves integ-branch behind
# (branch tip is NOT an ancestor). Writes the plan stub OUTSIDE the repo.
setup_complete() {
  local gid="$1" current="$2" merge="${3:-yes}"
  new_state_dir
  REPO_DIR=$(mktemp -d); CLEAN_DIRS+=("$REPO_DIR")
  git -C "$REPO_DIR" init -q
  git -C "$REPO_DIR" config user.name  "fixture"
  git -C "$REPO_DIR" config user.email "fixture@example.com"
  printf 'base\n' > "$REPO_DIR/base.txt"
  git -C "$REPO_DIR" add -A
  git -C "$REPO_DIR" commit -qm base
  # The fork baseline: integ-branch's tip at the moment goal-branch forks
  # from it. A genuinely completed goal has branch_tip != BASE_COMMIT (work
  # was committed since) AND is-ancestor(branch_tip, integ_tip).
  BASE_COMMIT=$(git -C "$REPO_DIR" rev-parse HEAD)
  git -C "$REPO_DIR" branch -q integ-branch
  git -C "$REPO_DIR" checkout -q -b goal-branch
  printf 'goal work\n' > "$REPO_DIR/goal.txt"
  git -C "$REPO_DIR" add -A
  git -C "$REPO_DIR" commit -qm goal-work
  if [ "$merge" = "yes" ]; then
    git -C "$REPO_DIR" checkout -q integ-branch
    # --no-ff so integ-branch carries a REAL merge commit: its tip then DIFFERS
    # from goal-branch's tip (a completed goal's realistic post-merge topology).
    # A fast-forward would leave the tips EQUAL — indistinguishable from the
    # vacuous zero-goal-work case the F2 tip-distinctness guard rejects.
    git -C "$REPO_DIR" merge -q --no-ff goal-branch -m merge-goal
    git -C "$REPO_DIR" checkout -q goal-branch
  fi
  mkdir -p "$SDLC_STATE_DIR/$gid"
  PLAN_STUB="$SDLC_STATE_DIR/$gid/plan.stub.md"
  printf 'current: %s\n' "$current" > "$PLAN_STUB"
}
# setup_complete_vacuous <goal-id> <current> — F2 (critic): builds a repo where
# goal-branch AND integ-branch BOTH point at the base commit (NO goal work ever
# committed). The tips are EQUAL, so `merge-base --is-ancestor` passes VACUOUSLY
# (a commit is its own ancestor) — the exact topology a forged current:10 latch
# exploits. Same globals/discipline as setup_complete.
setup_complete_vacuous() {
  local gid="$1" current="$2"
  new_state_dir
  REPO_DIR=$(mktemp -d); CLEAN_DIRS+=("$REPO_DIR")
  git -C "$REPO_DIR" init -q
  git -C "$REPO_DIR" config user.name  "fixture"
  git -C "$REPO_DIR" config user.email "fixture@example.com"
  printf 'base\n' > "$REPO_DIR/base.txt"
  git -C "$REPO_DIR" add -A
  git -C "$REPO_DIR" commit -qm base
  # Both branches AND the fork baseline sit at base — zero goal work: a stale
  # zero-work branch (branch_tip == BASE_COMMIT) that the merged-ness predicate
  # must reject regardless of what integration did.
  BASE_COMMIT=$(git -C "$REPO_DIR" rev-parse HEAD)
  git -C "$REPO_DIR" branch -q integ-branch    # both at base — zero goal work
  git -C "$REPO_DIR" branch -q goal-branch
  mkdir -p "$SDLC_STATE_DIR/$gid"
  PLAN_STUB="$SDLC_STATE_DIR/$gid/plan.stub.md"
  printf 'current: %s\n' "$current" > "$PLAN_STUB"
}
# write_complete_baton <gid> <dir> <current> <wip> — a baton whose branch/
# integration-branch name the fixture's two real branches.
write_complete_baton() {
  local gid="$1" d="$2" current="$3" wip="$4" base="${5:-$BASE_COMMIT}"
  baton_write "$gid" "$PLAN_STUB" "$d" "goal-branch" "integ-branch" \
    "$(git -C "$d" rev-parse HEAD)" "$current" "sid-$gid/1" \
    "none" "resume the slice" "$wip" "$base" >/dev/null 2>&1
}
# count_key_lines <ledger-path> <effect-key> — raw TSV line count (any type)
# whose effect-key column (field 5) matches exactly; 0 if the file is absent.
count_key_lines() {
  local path="$1" key="$2"
  [ -f "$path" ] || { printf '0'; return; }
  awk -F'\t' -v k="$key" '$5==k {c++} END{print c+0}' "$path"
}

echo ""
echo "=== AC-N3: sdlc_complete_check — structural completion latch (both directions) ==="

echo "--- GENUINE: current 10, branch merged into integration-branch, wip none → complete-verified, latch once, idempotent on replay ---"
ac_complete_genuine() {
  local gid="complete-genuine" d errf out rc path count1 count2
  setup_complete "$gid" 10 yes; d="$REPO_DIR"
  write_complete_baton "$gid" "$d" 10 none
  path=$(build_healthy_ledger "$gid")   # a real completed goal has journaled things along the way
  errf=$(mktemp); CLEAN_DIRS+=("$errf")
  out=$(sdlc_complete_check "$gid" "$d" 2>"$errf"); rc=$?
  assert_eq "AC-N3 genuine exits 0" "0" "$rc"
  assert_eq "AC-N3 genuine prints 'complete-verified'" "complete-verified" "$out"
  assert_eq "AC-N3 genuine silent on stderr" "" "$(cat "$errf")"
  count1="$(count_key_lines "$path" "complete:$gid")"
  assert_true "AC-N3 genuine journals the complete: latch" test "$count1" -ge 1

  # second invocation: effect already applied — still complete-verified, no
  # duplicate ledger lines for the key.
  out=$(sdlc_complete_check "$gid" "$d" 2>"$errf"); rc=$?
  assert_eq "AC-N3 second call exits 0" "0" "$rc"
  assert_eq "AC-N3 second call prints 'complete-verified'" "complete-verified" "$out"
  count2="$(count_key_lines "$path" "complete:$gid")"
  assert_eq "AC-N3 idempotent: ledger line count for complete: key unchanged" "$count1" "$count2"
}
ac_complete_genuine

echo "--- current: 10 with a trailing space → parses as terminal, not false not-complete ---"
ac_complete_current_trailing_space() {
  local gid="complete-current-trailws" d errf out rc path
  setup_complete "$gid" 10 yes; d="$REPO_DIR"
  printf 'current: 10 \n' > "$PLAN_STUB"          # trailing space leaves "10 " without a trailing trim
  write_complete_baton "$gid" "$d" 10 none
  path=$(build_healthy_ledger "$gid")
  errf=$(mktemp); CLEAN_DIRS+=("$errf")
  out=$(sdlc_complete_check "$gid" "$d" 2>"$errf"); rc=$?
  assert_eq "complete_check trailing-space current:10 exits 0" "0" "$rc"
  assert_eq "complete_check trailing-space current:10 prints 'complete-verified'" "complete-verified" "$out"
  assert_eq "complete_check trailing-space current:10 silent on stderr" "" "$(cat "$errf")"
}
ac_complete_current_trailing_space

echo "--- FALSE-COMPLETE unmerged: current 10, branch NOT merged into integration-branch → defect, rc 2, no latch ---"
ac_complete_false_unmerged() {
  local gid="complete-false-unmerged" d errf out rc path
  setup_complete "$gid" 10 no; d="$REPO_DIR"
  write_complete_baton "$gid" "$d" 10 none
  path="$(ledger_path "$gid")"
  errf=$(mktemp); CLEAN_DIRS+=("$errf")
  out=$(sdlc_complete_check "$gid" "$d" 2>"$errf"); rc=$?
  assert_eq "AC-N3 false-complete unmerged returns rc 2" "2" "$rc"
  assert_eq "AC-N3 false-complete unmerged exact defect text" \
    "defect: false-complete: current 10 but goal-branch not merged into integ-branch" "$(cat "$errf")"
  assert_eq "AC-N3 false-complete unmerged prints nothing on stdout" "" "$out"
  assert_eq "AC-N3 false-complete unmerged: no complete: line in the ledger" \
    "0" "$(count_key_lines "$path" "complete:$gid")"
}
ac_complete_false_unmerged

echo "--- FALSE-COMPLETE stranded wip: current 10, merged, wip != none → defect, rc 2, no latch ---"
ac_complete_false_stranded_wip() {
  local gid="complete-false-wip" d errf out rc path wip
  setup_complete "$gid" 10 yes; d="$REPO_DIR"
  wip="$(git -C "$d" rev-parse HEAD)"
  write_complete_baton "$gid" "$d" 10 "$wip"
  path="$(ledger_path "$gid")"
  errf=$(mktemp); CLEAN_DIRS+=("$errf")
  out=$(sdlc_complete_check "$gid" "$d" 2>"$errf"); rc=$?
  assert_eq "AC-N3 stranded-wip returns rc 2" "2" "$rc"
  assert_eq "AC-N3 stranded-wip exact defect text" \
    "defect: false-complete: terminal plan with stranded wip $wip" "$(cat "$errf")"
  assert_eq "AC-N3 stranded-wip: no complete: line in the ledger" \
    "0" "$(count_key_lines "$path" "complete:$gid")"
}
ac_complete_false_stranded_wip

echo "--- F2 FALSE-COMPLETE vacuous: current 10, goal-branch tip == base-commit (zero goal work) → defect, rc 2, no latch ---"
ac_complete_false_vacuous() {
  local gid="complete-false-vacuous" d errf out rc path
  setup_complete_vacuous "$gid" 10; d="$REPO_DIR"
  write_complete_baton "$gid" "$d" 10 none
  path=$(build_healthy_ledger "$gid")   # a valid ledger so the vacuous latch is what must refuse, not a missing chain
  errf=$(mktemp); CLEAN_DIRS+=("$errf")
  out=$(sdlc_complete_check "$gid" "$d" 2>"$errf"); rc=$?
  assert_eq "AC-N3 vacuous-complete returns rc 2" "2" "$rc"
  assert_contains "AC-N3 vacuous-complete names the false-complete class" "defect: false-complete:" "$(cat "$errf")"
  assert_contains "AC-N3 vacuous-complete names the stale zero-work branch" \
    "goal-branch did no work since base-commit" "$(cat "$errf")"
  assert_contains "AC-N3 vacuous-complete tags stale-zero-work" "stale zero-work branch" "$(cat "$errf")"
  assert_eq "AC-N3 vacuous-complete prints nothing on stdout" "" "$out"
  assert_eq "AC-N3 vacuous-complete: no complete: line in the ledger" \
    "0" "$(count_key_lines "$path" "complete:$gid")"
}
ac_complete_false_vacuous

# setup_complete_stale_escape <gid> <current> — F2a (critic re-attack, THE
# merge-blocker): goal-branch forks at BASE_COMMIT and NEVER advances (zero
# goal work), while integ-branch advances via an UNRELATED commit (another wave
# merging into the shared epic branch). goal-branch's tip is thus a PROPER
# ANCESTOR of integ-branch's tip — is-ancestor TRUE, tips DIFFER — the exact
# epic topology a forged current:10 on a stale pointer exploits. The old
# is-ancestor + tip-distinctness guards BOTH pass here (fail-open); the
# base-commit work-happened predicate must reject.
setup_complete_stale_escape() {
  local gid="$1" current="$2"
  new_state_dir
  REPO_DIR=$(mktemp -d); CLEAN_DIRS+=("$REPO_DIR")
  git -C "$REPO_DIR" init -q
  git -C "$REPO_DIR" config user.name  "fixture"
  git -C "$REPO_DIR" config user.email "fixture@example.com"
  printf 'base\n' > "$REPO_DIR/base.txt"
  git -C "$REPO_DIR" add -A
  git -C "$REPO_DIR" commit -qm base
  BASE_COMMIT=$(git -C "$REPO_DIR" rev-parse HEAD)
  git -C "$REPO_DIR" branch -q goal-branch "$BASE_COMMIT"   # forks at base, never advances
  git -C "$REPO_DIR" checkout -q -b integ-branch "$BASE_COMMIT"
  printf 'unrelated other-wave work\n' > "$REPO_DIR/other.txt"
  git -C "$REPO_DIR" add -A
  git -C "$REPO_DIR" commit -qm "other wave merged"        # integ advances for unrelated reasons
  git -C "$REPO_DIR" checkout -q goal-branch
  mkdir -p "$SDLC_STATE_DIR/$gid"
  PLAN_STUB="$SDLC_STATE_DIR/$gid/plan.stub.md"
  printf 'current: %s\n' "$current" > "$PLAN_STUB"
}
# setup_complete_ff <gid> <current> — F2b (critic re-attack, over-correction):
# goal-branch forks at BASE_COMMIT, commits real work, and integ-branch
# FAST-FORWARDS to goal-branch's tip → tips EQUAL. Work happened
# (branch_tip != BASE_COMMIT) and is-ancestor holds vacuously; a genuine
# completion the old tip-equality guard WRONGLY refused. Must verify.
setup_complete_ff() {
  local gid="$1" current="$2"
  new_state_dir
  REPO_DIR=$(mktemp -d); CLEAN_DIRS+=("$REPO_DIR")
  git -C "$REPO_DIR" init -q
  git -C "$REPO_DIR" config user.name  "fixture"
  git -C "$REPO_DIR" config user.email "fixture@example.com"
  printf 'base\n' > "$REPO_DIR/base.txt"
  git -C "$REPO_DIR" add -A
  git -C "$REPO_DIR" commit -qm base
  BASE_COMMIT=$(git -C "$REPO_DIR" rev-parse HEAD)
  git -C "$REPO_DIR" branch -q integ-branch
  git -C "$REPO_DIR" checkout -q -b goal-branch
  printf 'real goal work\n' > "$REPO_DIR/goal.txt"
  git -C "$REPO_DIR" add -A
  git -C "$REPO_DIR" commit -qm goal-work
  git -C "$REPO_DIR" checkout -q integ-branch
  git -C "$REPO_DIR" merge -q --ff-only goal-branch       # fast-forward: tips become EQUAL
  git -C "$REPO_DIR" checkout -q goal-branch
  mkdir -p "$SDLC_STATE_DIR/$gid"
  PLAN_STUB="$SDLC_STATE_DIR/$gid/plan.stub.md"
  printf 'current: %s\n' "$current" > "$PLAN_STUB"
}

echo "--- F2a MERGE-BLOCKER: stale zero-work goal branch, integ advanced UNRELATED (proper-ancestor, is-ancestor TRUE, tips differ) → false-complete rc 2, no latch ---"
ac_complete_stale_escape() {
  local gid="complete-stale-escape" d errf out rc path btip itip
  setup_complete_stale_escape "$gid" 10; d="$REPO_DIR"
  write_complete_baton "$gid" "$d" 10 none
  path=$(build_healthy_ledger "$gid")
  # Prove the fixture IS the escape topology, not a plain unmerged case:
  btip=$(git -C "$d" rev-parse goal-branch); itip=$(git -C "$d" rev-parse integ-branch)
  assert_true "F2a fixture: is-ancestor(goal,integ) is TRUE (proper ancestor)" \
    git -C "$d" merge-base --is-ancestor "$btip" "$itip"
  TOTAL=$((TOTAL + 1))
  if [ "$btip" != "$itip" ]; then pass "F2a fixture: tips DIFFER (old distinctness guard would pass)"; else fail "F2a fixture: tips DIFFER" "tips equal"; fi
  errf=$(mktemp); CLEAN_DIRS+=("$errf")
  out=$(sdlc_complete_check "$gid" "$d" 2>"$errf"); rc=$?
  assert_eq "F2a stale-escape returns rc 2 (was fail-open complete-verified)" "2" "$rc"
  assert_contains "F2a stale-escape names the false-complete class" "defect: false-complete:" "$(cat "$errf")"
  assert_contains "F2a stale-escape names the stale zero-work branch" "goal-branch did no work since base-commit" "$(cat "$errf")"
  assert_eq "F2a stale-escape prints nothing on stdout" "" "$out"
  assert_eq "F2a stale-escape: no complete: line latched" "0" "$(count_key_lines "$path" "complete:$gid")"
}
ac_complete_stale_escape

echo "--- F2b OVER-CORRECTION: genuine FF merge (work since base, integ FF'd, tips EQUAL, is-ancestor TRUE) → complete-verified rc 0, latch (was wrongly refused) ---"
ac_complete_genuine_ff() {
  local gid="complete-genuine-ff" d errf out rc path btip itip
  setup_complete_ff "$gid" 10; d="$REPO_DIR"
  write_complete_baton "$gid" "$d" 10 none
  path=$(build_healthy_ledger "$gid")
  btip=$(git -C "$d" rev-parse goal-branch); itip=$(git -C "$d" rev-parse integ-branch)
  TOTAL=$((TOTAL + 1))
  if [ "$btip" = "$itip" ]; then pass "F2b fixture: tips EQUAL (FF merge — old guard's false trigger)"; else fail "F2b fixture: tips EQUAL" "tips differ"; fi
  TOTAL=$((TOTAL + 1))
  if [ "$btip" != "$BASE_COMMIT" ]; then pass "F2b fixture: branch_tip != base-commit (work happened)"; else fail "F2b fixture: work happened" "branch_tip == base"; fi
  errf=$(mktemp); CLEAN_DIRS+=("$errf")
  out=$(sdlc_complete_check "$gid" "$d" 2>"$errf"); rc=$?
  assert_eq "F2b genuine-ff exits 0 (was wrongly rc 2)" "0" "$rc"
  assert_eq "F2b genuine-ff prints complete-verified" "complete-verified" "$out"
  assert_eq "F2b genuine-ff silent on stderr" "" "$(cat "$errf")"
  assert_true "F2b genuine-ff journals the complete: latch" test "$(count_key_lines "$path" "complete:$gid")" -ge 1
}
ac_complete_genuine_ff

echo "--- FAIL-CLOSED: current 10, genuinely merged, but base-commit none → false-complete rc 2 (cannot prove merged work), no latch ---"
ac_complete_base_none() {
  local gid="complete-base-none" d errf out rc path
  setup_complete "$gid" 10 yes; d="$REPO_DIR"
  write_complete_baton "$gid" "$d" 10 none none   # base override = none: no baseline recorded
  path=$(build_healthy_ledger "$gid")
  errf=$(mktemp); CLEAN_DIRS+=("$errf")
  out=$(sdlc_complete_check "$gid" "$d" 2>"$errf"); rc=$?
  assert_eq "base-none fail-closed returns rc 2" "2" "$rc"
  assert_eq "base-none fail-closed exact defect text" \
    "defect: false-complete: current 10 but no base-commit recorded to prove merged work" "$(cat "$errf")"
  assert_eq "base-none fail-closed prints nothing on stdout" "" "$out"
  assert_eq "base-none fail-closed: no complete: line latched" "0" "$(count_key_lines "$path" "complete:$gid")"
}
ac_complete_base_none

echo "--- BENIGN: current 4 → not-complete (no 'defect:' prefix), rc 1, no ledger writes ---"
ac_complete_benign() {
  local gid="complete-benign" d errf out rc path
  setup_complete "$gid" 4 no; d="$REPO_DIR"
  write_complete_baton "$gid" "$d" 4 none
  path="$(ledger_path "$gid")"
  errf=$(mktemp); CLEAN_DIRS+=("$errf")
  out=$(sdlc_complete_check "$gid" "$d" 2>"$errf"); rc=$?
  assert_eq "AC-N3 benign not-complete returns rc 1" "1" "$rc"
  assert_eq "AC-N3 benign not-complete exact text" "not-complete: plan current 4" "$(cat "$errf")"
  assert_eq "AC-N3 benign not-complete has NO 'defect:' prefix" "" "$(printf '%s' "$(cat "$errf")" | grep -o '^defect:')"
  assert_eq "AC-N3 benign not-complete prints nothing on stdout" "" "$out"
  assert_eq "AC-N3 benign not-complete: ledger untouched (no file)" "0" "$(count_key_lines "$path" "complete:$gid")"
}
ac_complete_benign

echo "--- chain-broken ledger: ledger_verify fails → its defect passes through, rc 2, no latch ---"
ac_complete_chain_broken() {
  local gid="complete-chain-broken" d errf out rc path
  setup_complete "$gid" 10 yes; d="$REPO_DIR"
  write_complete_baton "$gid" "$d" 10 none
  path=$(build_healthy_ledger "$gid")
  awk -F'\t' -v OFS='\t' 'NR==2 { $6="TAMPERED SUMMARY" } { print }' "$path" > "$path.new" && mv "$path.new" "$path"
  errf=$(mktemp); CLEAN_DIRS+=("$errf")
  out=$(sdlc_complete_check "$gid" "$d" 2>"$errf"); rc=$?
  assert_eq "AC-N3 chain-broken returns rc 2" "2" "$rc"
  assert_contains "AC-N3 chain-broken passes through in-place-edit" "in-place-edit" "$(cat "$errf")"
  assert_eq "AC-N3 chain-broken: no complete: line landed" "0" "$(count_key_lines "$path" "complete:$gid")"
}
ac_complete_chain_broken

echo "--- malformed baton passes through (parse defect family), rc 2 ---"
ac_complete_baton_malformed() {
  local gid="complete-malformed" d errf rc baton
  setup_complete "$gid" 10 yes; d="$REPO_DIR"
  write_complete_baton "$gid" "$d" 10 none
  baton=$(baton_path "$gid")
  grep -v -E '^next-action:' "$baton" > "$baton.new" && mv "$baton.new" "$baton"
  errf=$(mktemp); CLEAN_DIRS+=("$errf")
  sdlc_complete_check "$gid" "$d" 2>"$errf" 1>/dev/null; rc=$?
  assert_eq "AC-N3 malformed-baton returns rc 2" "2" "$rc"
  assert_contains "AC-N3 malformed-baton passes through the parse defect" "missing-key" "$(cat "$errf")"
}
ac_complete_baton_malformed

echo "--- complete-check goal-id guard: '/' → invalid-goal-id, rc 2 ---"
ac_complete_guard() {
  new_state_dir
  local errf rc
  errf=$(mktemp); CLEAN_DIRS+=("$errf")
  sdlc_complete_check "bad/goal" "." 2>"$errf" 1>/dev/null; rc=$?
  assert_eq "AC-N3 complete-check rejects a '/' goal-id with rc 2" "2" "$rc"
  assert_contains "AC-N3 complete-check '/' names invalid-goal-id" "invalid-goal-id" "$(cat "$errf")"
}
ac_complete_guard

# ============================================================
# Gate park (slice 4/4, spec D7 + AS-N10) — sdlc_gate_park <goal-id>
# <plan-path> <defect> <detail>. Wraps a Wake-Note append to a caller-
# supplied plan file in sdlc_effect_run, keyed park:<goal-id>:<defect>.
# AS-N10: plan-path is a caller-supplied arg (NOT derived via baton_parse) —
# a malformed/missing baton is itself a park cause, so park must not depend
# on baton derivation succeeding. Fixtures use a bare temp plan file (no
# baton, no git repo) plus SDLC_STATE_DIR isolation for the ledger.
# ============================================================

# wake_note_count <plan-path> — number of '## Wake Note' headings present.
wake_note_count() { grep -c '^## Wake Note$' "$1" 2>/dev/null || true; }

echo ""
echo "=== AC-N2/AC-N6: sdlc_gate_park — Wake Note through the effect guard (both directions) ==="

echo "--- first park: Wake Note block appended exactly once, fields substituted, effect journaled once ---"
ac_park_first() {
  local gid="park-first" plan errf rc path
  new_state_dir
  plan=$(mktemp); CLEAN_DIRS+=("$plan")
  printf 'current: 4\n' > "$plan"
  errf=$(mktemp); CLEAN_DIRS+=("$errf")
  sdlc_gate_park "$gid" "$plan" "baton-stale" "baton step 4, plan current 5" 2>"$errf"; rc=$?
  assert_eq "AC-N2 first park exits 0" "0" "$rc"
  assert_eq "AC-N2 first park silent on stderr" "" "$(cat "$errf")"
  assert_eq "AC-N2 first park: exactly one Wake Note block" "1" "$(wake_note_count "$plan")"
  assert_contains "AC-N2 first park: defect substituted" "GATED by rollover spine: baton-stale" "$(cat "$plan")"
  assert_contains "AC-N2 first park: detail substituted" "baton step 4, plan current 5" "$(cat "$plan")"
  assert_contains "AC-N2 first park: options skeleton present" "**Options:**" "$(cat "$plan")"
  assert_contains "AC-N2 first park: re-arm option present" "delete this note to re-arm" "$(cat "$plan")"
  assert_contains "AC-N2 first park: why-it-matters present" "**Why it matters:**" "$(cat "$plan")"
  assert_contains "AC-N2 first park: original plan content preserved" "current: 4" "$(cat "$plan")"
  path="$(ledger_path "$gid")"
  assert_eq "AC-N2 first park: effect line journaled exactly once" "1" "$(key_lines "$path" effect "park:$gid:baton-stale")"
}
ac_park_first

echo "--- double-drive SAME defect: idempotent by effect key — still one block, one effect line, rc 0 ---"
ac_park_double_same() {
  local gid="park-double-same" plan errf rc path
  new_state_dir
  plan=$(mktemp); CLEAN_DIRS+=("$plan")
  printf 'current: 4\n' > "$plan"
  errf=$(mktemp); CLEAN_DIRS+=("$errf")
  sdlc_gate_park "$gid" "$plan" "baton-stale" "first drive detail" >/dev/null 2>&1
  sdlc_gate_park "$gid" "$plan" "baton-stale" "second drive detail" 2>"$errf"; rc=$?
  path="$(ledger_path "$gid")"
  assert_eq "AC-N6 double-drive same defect exits 0" "0" "$rc"
  assert_eq "AC-N6 double-drive same defect: still exactly one Wake Note block" "1" "$(wake_note_count "$plan")"
  assert_eq "AC-N6 double-drive same defect: effect line count unchanged (still 1)" "1" "$(key_lines "$path" effect "park:$gid:baton-stale")"
  assert_contains "AC-N6 double-drive same defect: first drive's detail wins (no re-append)" "first drive detail" "$(cat "$plan")"
}
ac_park_double_same

echo "--- second park, DIFFERENT defect while parked: presence-probe belt — no double-append, decision for new key journaled ---"
ac_park_different_defect() {
  local gid="park-different" plan errf rc path
  new_state_dir
  plan=$(mktemp); CLEAN_DIRS+=("$plan")
  printf 'current: 4\n' > "$plan"
  sdlc_gate_park "$gid" "$plan" "baton-stale" "first defect detail" >/dev/null 2>&1
  errf=$(mktemp); CLEAN_DIRS+=("$errf")
  sdlc_gate_park "$gid" "$plan" "worktree-drift" "second, different defect detail" 2>"$errf"; rc=$?
  path="$(ledger_path "$gid")"
  assert_eq "AC-N6 different-defect-while-parked exits 0 (postcondition: goal IS parked)" "0" "$rc"
  assert_eq "AC-N6 different-defect-while-parked: still exactly one Wake Note block" "1" "$(wake_note_count "$plan")"
  assert_contains "AC-N6 different-defect-while-parked: park-skipped note on stderr" "park-skipped: wake note already present — first park wins" "$(cat "$errf")"
  assert_eq "AC-N6 different-defect-while-parked: decision journaled for the NEW key" "1" "$(key_lines "$path" decision "park:$gid:worktree-drift")"
  assert_contains "AC-N6 different-defect-while-parked: first block's defect text untouched" "GATED by rollover spine: baton-stale" "$(cat "$plan")"
}
ac_park_different_defect

echo "--- plan file missing → park-failed, nonzero, effect state left indeterminate (no false 'applied') ---"
ac_park_plan_missing() {
  local gid="park-plan-missing" plan errf rc state
  new_state_dir
  plan="$(mktemp -u)"   # a path that does not exist and is never created
  errf=$(mktemp); CLEAN_DIRS+=("$errf")
  sdlc_gate_park "$gid" "$plan" "baton-stale" "detail text" 2>"$errf"; rc=$?
  assert_nonzero "AC-N2 plan-missing returns nonzero" "$rc"
  assert_eq "AC-N2 plan-missing exact defect text" \
    "defect: park-failed: $plan — park could not land durable state" "$(cat "$errf")"
  state="$(sdlc_effect_state "$gid" "park:$gid:baton-stale")"
  assert_eq "AC-N2 plan-missing: effect state is indeterminate, NOT applied" "indeterminate" "$state"
}
ac_park_plan_missing

echo "--- human-cleared consent: Wake Note manually deleted, replay SAME defect → effect applied, skip, file stays clean (no re-append) ---"
ac_park_human_cleared() {
  local gid="park-cleared" plan errf rc
  new_state_dir
  plan=$(mktemp); CLEAN_DIRS+=("$plan")
  printf 'current: 4\n' > "$plan"
  sdlc_gate_park "$gid" "$plan" "baton-stale" "original detail" >/dev/null 2>&1
  assert_eq "AC-N2 human-cleared setup: Wake Note landed once" "1" "$(wake_note_count "$plan")"
  printf 'current: 4\n' > "$plan"   # human deletes the note — plan back to pristine
  errf=$(mktemp); CLEAN_DIRS+=("$errf")
  sdlc_gate_park "$gid" "$plan" "baton-stale" "original detail" 2>"$errf"; rc=$?
  assert_eq "AC-N2 human-cleared replay exits 0 (effect already applied)" "0" "$rc"
  assert_eq "AC-N2 human-cleared replay: no re-append — plan stays pristine" "0" "$(wake_note_count "$plan")"
  assert_eq "AC-N2 human-cleared replay: plan content untouched" "current: 4" "$(cat "$plan")"
}
ac_park_human_cleared

echo "--- defect arg empty → loud reject, no ledger writes, no effect key journaled ---"
ac_park_missing_defect() {
  local gid="park-missing-defect" plan errf rc path
  new_state_dir
  plan=$(mktemp); CLEAN_DIRS+=("$plan")
  printf 'current: 4\n' > "$plan"
  errf=$(mktemp); CLEAN_DIRS+=("$errf")
  sdlc_gate_park "$gid" "$plan" "" "some detail" 2>"$errf"; rc=$?
  path="$(ledger_path "$gid")"
  assert_nonzero "AC-N2 empty-defect returns nonzero" "$rc"
  assert_contains "AC-N2 empty-defect names missing-defect" "missing-defect" "$(cat "$errf")"
  assert_eq "AC-N2 empty-defect: no Wake Note appended" "0" "$(wake_note_count "$plan")"
  assert_eq "AC-N2 empty-defect: ledger untouched (no file)" "0" "$([ -f "$path" ] && wc -l < "$path" | tr -d ' ' || echo 0)"
}
ac_park_missing_defect

echo "--- gate-park goal-id guard: '/' → invalid-goal-id ---"
ac_park_guard() {
  new_state_dir
  local plan errf rc
  plan=$(mktemp); CLEAN_DIRS+=("$plan")
  printf 'current: 4\n' > "$plan"
  errf=$(mktemp); CLEAN_DIRS+=("$errf")
  sdlc_gate_park "bad/goal" "$plan" "baton-stale" "detail" 2>"$errf" 1>/dev/null; rc=$?
  assert_nonzero "AC-N2 gate-park rejects a '/' goal-id" "$rc"
  assert_contains "AC-N2 gate-park '/' names invalid-goal-id" "invalid-goal-id" "$(cat "$errf")"
}
ac_park_guard

# ============================================================
# Successor-spawn pipeline (slice 4/5, spec D3/D6/D8) —
# sdlc_successor_pointer_prompt + sdlc_successor_spawn. Every case stubs the
# two env seams (AS-N2): SDLC_SPAWN_CMD is a synchronous counter script (one
# line appended per launch — deterministic, race-free), SDLC_REGISTRY_CMD is
# a canned command emitting JSON (or `false` for the failure path). The real
# `claude` binary is NEVER invoked here — the T3 live row (Step 5) exercises
# the defaults. Both seams are set as `local` in each test fn so dynamic
# scope reaches sdlc_successor_spawn and they auto-clear on return.
# ============================================================

# make_spawn_stub <counter-path> — a synchronous stub that records one launch
# per invocation (echoes the stub's own path for SDLC_SPAWN_CMD).
make_spawn_stub() {
  local counter="$1" stub
  stub="$(mktemp)"; CLEAN_DIRS+=("$stub")
  printf '#!/bin/bash\nprintf x >> %q\nprintf "\\n" >> %q\n' "$counter" "$counter" > "$stub"
  chmod +x "$stub"
  printf '%s' "$stub"
}
# make_registry_stub <json> — a `cat <file>` command emitting the given JSON
# (echoes the command string for SDLC_REGISTRY_CMD).
make_registry_stub() {
  local json="$1" f
  f="$(mktemp)"; CLEAN_DIRS+=("$f")
  printf '%s\n' "$json" > "$f"
  printf 'cat %s' "$f"
}
# spawn_counter <counter-path> — launches recorded (0 if absent/empty).
spawn_counter() { if [ -f "$1" ]; then grep -c . "$1" | tr -d ' '; else printf '0'; fi; }
# ledger_tail_pos <goal-id> — the ledger tail's `<seq>:<digest>` (baton
# ledger-position grammar), so a planted-ledger fixture's baton stays
# consistent for sdlc_reconcile's position cross-check.
ledger_tail_pos() { awk -F'\t' 'END{print $2":"$3}' "$(ledger_path "$1")"; }
# write_complete_baton_pos <gid> <dir> <current> <wip> <ledger-position> — the
# two-branch complete baton with an explicit ledger-position.
write_complete_baton_pos() {
  baton_write "$1" "$PLAN_STUB" "$2" "goal-branch" "integ-branch" \
    "$(git -C "$2" rev-parse HEAD)" "$3" "sid-$1/1" "$5" "resume the slice" "$4" "${6:-$BASE_COMMIT}" >/dev/null 2>&1
}
# spawn_line_sid <ledger-path> <goal-id> — sid= from the newest spawn effect line.
spawn_line_sid() {
  awk -F'\t' '$4=="effect" && $5 ~ /^spawn:/ {l=$6} END{print l}' "$1" \
    | sed -n 's/.*sid=\([0-9a-f-]*\).*/\1/p'
}

echo ""
echo "=== AC-N1 substrate: sdlc_successor_pointer_prompt — one source, exact block ==="
ac_pointer_prompt() {
  local out expected
  out="$(sdlc_successor_pointer_prompt "my-goal" "/p/my-goal.plan.md" "/s/my-goal/baton.md" "resume slice 3")"
  expected="$(cat <<'EOF'
Rollover pickup for goal my-goal. The rollover spine verified
state clean; do not re-derive reconciliation, do not override
any Wake Note. Read the plan at /p/my-goal.plan.md and the baton at
/s/my-goal/baton.md; resume per the canonical-sdlc session-resume
protocol. Baton next-action is the literal resume point:
resume slice 3
EOF
)"
  assert_eq "AC-N1 pointer prompt matches the plan block verbatim (with substitutions)" "$expected" "$out"
}
ac_pointer_prompt

echo ""
echo "=== AC-N2/AC-N5/AC-N6: sdlc_successor_spawn — refuse-first rollover, exactly-once spawn ==="

echo "--- HAPPY + double-drive: healthy goal spawns once (sid printed, counter 1, spawn effect line carries sid=); replay same baton → spawn-skipped, counter unchanged ---"
ac_spawn_happy_double() {
  local gid="spawn-happy" d counter path sid sid2 rc out
  local SDLC_SPAWN_CMD SDLC_REGISTRY_CMD
  setup_complete "$gid" 4 no; d="$REPO_DIR"          # current 4 → benign not-complete → proceed
  write_complete_baton "$gid" "$d" 4 none
  counter=$(mktemp); CLEAN_DIRS+=("$counter"); : > "$counter"
  SDLC_SPAWN_CMD="$(make_spawn_stub "$counter")"
  SDLC_REGISTRY_CMD="$(make_registry_stub '{"sessions":[]}')"   # re-drive: no live owner
  path="$(ledger_path "$gid")"

  out="$(sdlc_successor_spawn "$gid" "$d" 2>/dev/null)"; rc=$?
  assert_eq "AC-N5 happy drive exits 0" "0" "$rc"
  assert_eq "AC-N5 happy drive launched the successor once (counter=1)" "1" "$(spawn_counter "$counter")"
  sid="$out"
  TOTAL=$((TOTAL + 1))
  if printf '%s' "$sid" | grep -qE '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'; then
    pass "AC-N5 happy drive prints a lowercased uuid sid on stdout"
  else fail "AC-N5 happy drive prints a lowercased uuid sid on stdout" "got: $sid"; fi
  assert_eq "AC-N5 happy drive: spawn effect line journaled with the printed sid" "$sid" "$(spawn_line_sid "$path" "$gid")"
  assert_eq "AC-N5 happy drive: exactly one spawn effect line" "1" \
    "$(awk -F'\t' '$4=="effect" && $5 ~ /^spawn:/' "$path" | wc -l | tr -d ' ')"

  # replay SAME baton (written-at unchanged) → key applied → skip, no new launch.
  out="$(sdlc_successor_spawn "$gid" "$d" 2>/dev/null)"; rc=$?
  assert_eq "AC-N6 replay same baton exits 0" "0" "$rc"
  assert_contains "AC-N6 replay same baton prints spawn-skipped" "spawn-skipped: already spawned for baton" "$out"
  assert_eq "AC-N6 replay same baton did NOT re-launch (counter still 1)" "1" "$(spawn_counter "$counter")"
  sid2="$(spawn_line_sid "$path" "$gid")"
  assert_eq "AC-N6 replay same baton: spawn sid unchanged" "$sid" "$sid2"
}
ac_spawn_happy_double

echo "--- WAKE NOTE STANDING: plan already parked → goal-gated, no spawn, no second Wake Note ---"
ac_spawn_wake_note() {
  local gid="spawn-gated" d counter err rc
  local SDLC_SPAWN_CMD SDLC_REGISTRY_CMD
  setup_reconcile "$gid" 4; d="$REPO_DIR"
  write_recon_baton "$gid" "$d" 4 none none
  printf '\n## Wake Note\n\nGATED by something earlier\n' >> "$PLAN_STUB"   # already parked
  counter=$(mktemp); CLEAN_DIRS+=("$counter"); : > "$counter"
  SDLC_SPAWN_CMD="$(make_spawn_stub "$counter")"
  SDLC_REGISTRY_CMD="$(make_registry_stub '{"sessions":[]}')"
  err="$(sdlc_successor_spawn "$gid" "$d" 2>&1 1>/dev/null)"; rc=$?
  assert_nonzero "AC-N6 wake-note-standing returns nonzero" "$rc"
  assert_contains "AC-N6 wake-note-standing names goal-gated" "goal-gated: wake note standing" "$err"
  assert_eq "AC-N6 wake-note-standing did not spawn (counter 0)" "0" "$(spawn_counter "$counter")"
  assert_eq "AC-N6 wake-note-standing left exactly one Wake Note (no second append)" "1" "$(wake_note_count "$PLAN_STUB")"
}
ac_spawn_wake_note

echo "--- COMPLETE goal (current 10, merged, wip none): goal-complete rc 0, no spawn; second drive hits the applied-latch branch ---"
ac_spawn_complete() {
  local gid="spawn-complete" d counter out rc
  local SDLC_SPAWN_CMD SDLC_REGISTRY_CMD
  setup_complete "$gid" 10 yes; d="$REPO_DIR"
  write_complete_baton "$gid" "$d" 10 none
  build_healthy_ledger "$gid" >/dev/null      # a genuinely-completed goal journaled along the way
  counter=$(mktemp); CLEAN_DIRS+=("$counter"); : > "$counter"
  SDLC_SPAWN_CMD="$(make_spawn_stub "$counter")"
  SDLC_REGISTRY_CMD="$(make_registry_stub '{"sessions":[]}')"
  out="$(sdlc_successor_spawn "$gid" "$d" 2>/dev/null)"; rc=$?
  assert_eq "AC-N3 complete goal exits 0" "0" "$rc"
  assert_eq "AC-N3 complete goal prints goal-complete" "goal-complete" "$out"
  assert_eq "AC-N3 complete goal did not spawn (counter 0)" "0" "$(spawn_counter "$counter")"
  # second drive: complete latch is now applied → the effect_state short-circuit.
  out="$(sdlc_successor_spawn "$gid" "$d" 2>/dev/null)"; rc=$?
  assert_eq "AC-N3 complete goal second drive (applied latch) exits 0" "0" "$rc"
  assert_eq "AC-N3 complete goal second drive prints goal-complete" "goal-complete" "$out"
  assert_eq "AC-N3 complete goal second drive still did not spawn" "0" "$(spawn_counter "$counter")"
}
ac_spawn_complete

echo "--- FALSE-COMPLETE (current 10, NOT merged): park lands, no spawn, rc nonzero ---"
ac_spawn_false_complete() {
  local gid="spawn-false" d counter rc
  local SDLC_SPAWN_CMD SDLC_REGISTRY_CMD
  setup_complete "$gid" 10 no; d="$REPO_DIR"
  write_complete_baton "$gid" "$d" 10 none
  counter=$(mktemp); CLEAN_DIRS+=("$counter"); : > "$counter"
  SDLC_SPAWN_CMD="$(make_spawn_stub "$counter")"
  SDLC_REGISTRY_CMD="$(make_registry_stub '{"sessions":[]}')"
  sdlc_successor_spawn "$gid" "$d" >/dev/null 2>&1; rc=$?
  assert_nonzero "AC-N3 false-complete returns nonzero" "$rc"
  assert_eq "AC-N3 false-complete did not spawn (counter 0)" "0" "$(spawn_counter "$counter")"
  assert_eq "AC-N3 false-complete parked exactly one Wake Note" "1" "$(wake_note_count "$PLAN_STUB")"
  assert_contains "AC-N3 false-complete parks the false-complete class" "GATED by rollover spine: false-complete" "$(cat "$PLAN_STUB")"
}
ac_spawn_false_complete

echo "--- LIVE OWNER: prior spawn line's sid found in the registry → goal-owned, no park, no spawn ---"
ac_spawn_live_owner() {
  local gid="spawn-owned" d counter fakesid err rc
  local SDLC_SPAWN_CMD SDLC_REGISTRY_CMD
  setup_complete "$gid" 4 no; d="$REPO_DIR"
  write_complete_baton "$gid" "$d" 4 none
  fakesid="11111111-2222-3333-4444-555555555555"
  ledger_append "$gid" effect "spawn:$gid:2026-01-01T00:00:00Z" "sid=$fakesid pid=na cwd=$d" >/dev/null 2>&1
  counter=$(mktemp); CLEAN_DIRS+=("$counter"); : > "$counter"
  SDLC_SPAWN_CMD="$(make_spawn_stub "$counter")"
  SDLC_REGISTRY_CMD="$(make_registry_stub "{\"sessions\":[{\"id\":\"$fakesid\"}]}")"
  err="$(sdlc_successor_spawn "$gid" "$d" 2>&1 1>/dev/null)"; rc=$?
  assert_nonzero "AC-N6 live-owner returns nonzero" "$rc"
  assert_contains "AC-N6 live-owner names goal-owned + the sid" "goal-owned: session $fakesid live" "$err"
  assert_eq "AC-N6 live-owner did not spawn (counter 0)" "0" "$(spawn_counter "$counter")"
  assert_eq "AC-N6 live-owner did not park (no Wake Note)" "0" "$(wake_note_count "$PLAN_STUB")"
}
ac_spawn_live_owner

echo "--- REGISTRY UNAVAILABLE: registry command fails → conservative goal-owned refusal, no park, no spawn ---"
ac_spawn_registry_down() {
  local gid="spawn-regdown" d counter fakesid err rc
  local SDLC_SPAWN_CMD SDLC_REGISTRY_CMD
  setup_complete "$gid" 4 no; d="$REPO_DIR"
  write_complete_baton "$gid" "$d" 4 none
  fakesid="aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
  ledger_append "$gid" effect "spawn:$gid:2026-01-01T00:00:00Z" "sid=$fakesid pid=na cwd=$d" >/dev/null 2>&1
  counter=$(mktemp); CLEAN_DIRS+=("$counter"); : > "$counter"
  SDLC_SPAWN_CMD="$(make_spawn_stub "$counter")"
  SDLC_REGISTRY_CMD="false"
  err="$(sdlc_successor_spawn "$gid" "$d" 2>&1 1>/dev/null)"; rc=$?
  assert_nonzero "AC-N6 registry-down returns nonzero" "$rc"
  assert_contains "AC-N6 registry-down: conservative refusal suffix" "registry unavailable, refusing conservatively" "$err"
  assert_eq "AC-N6 registry-down did not spawn (counter 0)" "0" "$(spawn_counter "$counter")"
  assert_eq "AC-N6 registry-down did not park" "0" "$(wake_note_count "$PLAN_STUB")"
}
ac_spawn_registry_down

echo "--- DEAD OWNER: prior spawn sid absent from the registry → proceeds to spawn ---"
ac_spawn_dead_owner() {
  local gid="spawn-dead" d counter fakesid out rc
  local SDLC_SPAWN_CMD SDLC_REGISTRY_CMD
  setup_complete "$gid" 4 no; d="$REPO_DIR"
  fakesid="99999999-8888-7777-6666-555555555555"
  ledger_append "$gid" effect "spawn:$gid:2026-01-01T00:00:00Z" "sid=$fakesid pid=na cwd=$d" >/dev/null 2>&1
  write_complete_baton_pos "$gid" "$d" 4 none "$(ledger_tail_pos "$gid")"   # baton position tracks the planted line → reconcile clean
  counter=$(mktemp); CLEAN_DIRS+=("$counter"); : > "$counter"
  SDLC_SPAWN_CMD="$(make_spawn_stub "$counter")"
  SDLC_REGISTRY_CMD="$(make_registry_stub '{"sessions":[{"id":"00000000-0000-0000-0000-000000000000"}]}')"
  out="$(sdlc_successor_spawn "$gid" "$d" 2>/dev/null)"; rc=$?
  assert_eq "AC-N6 dead-owner proceeds and exits 0" "0" "$rc"
  assert_eq "AC-N6 dead-owner launched a fresh successor (counter 1)" "1" "$(spawn_counter "$counter")"
  TOTAL=$((TOTAL + 1))
  if printf '%s' "$out" | grep -qE '^[0-9a-f-]{36}$'; then pass "AC-N6 dead-owner printed a fresh sid"; else fail "AC-N6 dead-owner printed a fresh sid" "got: $out"; fi
}
ac_spawn_dead_owner

echo "--- DIVERGENCE (baton-stale tip): reconcile defect → park that class, no spawn; double-drive → still one Wake Note ---"
ac_spawn_divergence() {
  local gid="spawn-diverge" d counter rc
  local SDLC_SPAWN_CMD SDLC_REGISTRY_CMD
  setup_reconcile "$gid" 4; d="$REPO_DIR"
  write_recon_baton "$gid" "$d" 4 none none
  printf 'later work\n' > "$d/later.txt"; git -C "$d" add -A; git -C "$d" commit -qm later  # tip advances past baton
  counter=$(mktemp); CLEAN_DIRS+=("$counter"); : > "$counter"
  SDLC_SPAWN_CMD="$(make_spawn_stub "$counter")"
  SDLC_REGISTRY_CMD="$(make_registry_stub '{"sessions":[]}')"
  sdlc_successor_spawn "$gid" "$d" >/dev/null 2>&1; rc=$?
  assert_nonzero "AC-N2 divergence returns nonzero" "$rc"
  assert_eq "AC-N2 divergence did not spawn (counter 0)" "0" "$(spawn_counter "$counter")"
  assert_eq "AC-N2 divergence parked one Wake Note" "1" "$(wake_note_count "$PLAN_STUB")"
  assert_contains "AC-N2 divergence parks the baton-stale class" "GATED by rollover spine: baton-stale" "$(cat "$PLAN_STUB")"
  # double-drive: still exactly one Wake Note (park idempotent by key).
  sdlc_successor_spawn "$gid" "$d" >/dev/null 2>&1
  assert_eq "AC-N6 divergence double-drive: still one Wake Note" "1" "$(wake_note_count "$PLAN_STUB")"
  assert_eq "AC-N6 divergence double-drive: still no spawn (counter 0)" "0" "$(spawn_counter "$counter")"
}
ac_spawn_divergence

echo "--- RESTORE: reconcile verdict restore:<sha> → wip_restore replays the clobbered file, then spawns ---"
ac_spawn_restore() {
  local gid="spawn-restore" d counter snap out rc
  local SDLC_SPAWN_CMD SDLC_REGISTRY_CMD
  setup_reconcile "$gid" 4; d="$REPO_DIR"
  printf 'work in progress\n' > "$d/wip.txt"
  snap=$(sdlc_wip_snapshot "$gid" "$d" 2>/dev/null)
  rm -f "$d/wip.txt"                                  # clobber → worktree == HEAD
  write_recon_baton "$gid" "$d" 4 none "$snap"
  counter=$(mktemp); CLEAN_DIRS+=("$counter"); : > "$counter"
  SDLC_SPAWN_CMD="$(make_spawn_stub "$counter")"
  SDLC_REGISTRY_CMD="$(make_registry_stub '{"sessions":[]}')"
  out="$(sdlc_successor_spawn "$gid" "$d" 2>/dev/null)"; rc=$?
  assert_eq "AC-N5 restore drive exits 0" "0" "$rc"
  assert_true "AC-N5 restore replayed the clobbered wip.txt" test -f "$d/wip.txt"
  assert_eq "AC-N5 restore replayed byte-faithful content" "work in progress" "$(cat "$d/wip.txt")"
  assert_eq "AC-N5 restore then launched the successor (counter 1)" "1" "$(spawn_counter "$counter")"
}
ac_spawn_restore

echo "--- INDETERMINATE spawn key (decision, no effect): effect-indeterminate → park, no launch ---"
ac_spawn_indeterminate() {
  local gid="spawn-indet" d counter baton wat rc
  local SDLC_SPAWN_CMD SDLC_REGISTRY_CMD
  setup_complete "$gid" 4 no; d="$REPO_DIR"
  write_complete_baton "$gid" "$d" 4 none
  baton="$(baton_path "$gid")"
  baton_parse "$baton"; wat="$BATON_WRITTEN_AT"
  # plant a DECISION line for the exact spawn key stage 6 will compute — a crash
  # window: intent journaled, no effect. (decision-type → stage 4 does not match it.)
  ledger_append "$gid" decision "spawn:$gid:$wat" "sid=deadbeef-0000-0000-0000-000000000000 pid=na cwd=$d" >/dev/null 2>&1
  counter=$(mktemp); CLEAN_DIRS+=("$counter"); : > "$counter"
  SDLC_SPAWN_CMD="$(make_spawn_stub "$counter")"
  SDLC_REGISTRY_CMD="$(make_registry_stub '{"sessions":[]}')"
  sdlc_successor_spawn "$gid" "$d" >/dev/null 2>&1; rc=$?
  assert_nonzero "AC-N6 indeterminate spawn key returns nonzero" "$rc"
  assert_eq "AC-N6 indeterminate did not launch (counter 0)" "0" "$(spawn_counter "$counter")"
  assert_eq "AC-N6 indeterminate parked one Wake Note" "1" "$(wake_note_count "$PLAN_STUB")"
  assert_contains "AC-N6 indeterminate parks the effect-indeterminate class" "GATED by rollover spine: effect-indeterminate" "$(cat "$PLAN_STUB")"
}
ac_spawn_indeterminate

echo "--- goal-id guard: '/' → invalid-goal-id, nonzero ---"
ac_spawn_guard() {
  new_state_dir
  local err rc
  err="$(sdlc_successor_spawn "bad/goal" "." 2>&1 1>/dev/null)"; rc=$?
  assert_nonzero "AC-N2 successor-spawn rejects a '/' goal-id" "$rc"
  assert_contains "AC-N2 successor-spawn '/' names invalid-goal-id" "invalid-goal-id" "$err"
}
ac_spawn_guard

echo ""
echo "=== AS-N14: successor spawn posture — strong workers, strong walls (default full-capability launch) ==="

# make_claude_fake <argv-file> [sleep-secs] — a PATH-fake `claude` binary that
# records its full argv (one token per line) to argv-file, optionally
# sleeping first (to prove the real launch backgrounds rather than blocking
# on the successor's whole turn — spec D8 fire-and-observe). Echoes the
# fixture DIRECTORY (to prepend onto PATH so the default `_sdlc_spawn_launch`
# resolves this stub instead of the real binary).
make_claude_fake() {
  local argv_file="$1" sleep_secs="${2:-0}" dir stub
  dir="$(mktemp -d)"; CLEAN_DIRS+=("$dir")
  stub="$dir/claude"
  cat > "$stub" <<STUBEOF
#!/bin/bash
sleep $sleep_secs
for a in "\$@"; do printf '%s\n' "\$a" >> "$argv_file"; done
STUBEOF
  chmod +x "$stub"
  printf '%s' "$dir"
}
# wait_for_file <path> <max-tenths> — polls up to max-tenths*0.1s for a
# non-empty file (the default spawn launch backgrounds itself, so the fake
# claude's argv write races the assertion).
wait_for_file() {
  local path="$1" max="${2:-30}" n=0
  while [ ! -s "$path" ] && [ "$n" -lt "$max" ]; do sleep 0.1; n=$((n + 1)); done
}

echo "--- DEFAULT posture: SDLC_SPAWN_PERMISSIONS unset → argv carries --dangerously-skip-permissions; launch backgrounds (returns before the fake claude's sleep elapses, effect line still journals) ---"
ac_spawn_posture_default() {
  local gid="spawn-posture-default" d argvf fakedir path out rc
  local SDLC_SPAWN_CMD SDLC_REGISTRY_CMD SDLC_SPAWN_PERMISSIONS
  unset SDLC_SPAWN_PERMISSIONS
  setup_complete "$gid" 4 no; d="$REPO_DIR"          # current 4 → benign not-complete → proceed
  write_complete_baton "$gid" "$d" 4 none
  argvf=$(mktemp); CLEAN_DIRS+=("$argvf"); : > "$argvf"
  fakedir="$(make_claude_fake "$argvf" 2)"
  SDLC_REGISTRY_CMD="$(make_registry_stub '{"sessions":[]}')"
  local PATH="$fakedir:$PATH"
  path="$(ledger_path "$gid")"

  SECONDS=0
  out="$(sdlc_successor_spawn "$gid" "$d" 2>/dev/null)"; rc=$?
  assert_eq "AS-N14 default drive exits 0" "0" "$rc"
  assert_true "AS-N14 default drive returned before the fake claude's 2s sleep elapsed (backgrounded)" test "$SECONDS" -lt 2
  assert_eq "AS-N14 default drive: spawn effect line journaled (fire-and-observe, not launch-completion)" "1" \
    "$(awk -F'\t' '$4=="effect" && $5 ~ /^spawn:/' "$path" | wc -l | tr -d ' ')"

  wait_for_file "$argvf" 40
  assert_contains "AS-N14 default argv carries -p" "-p" "$(cat "$argvf")"
  assert_contains "AS-N14 default argv carries --session-id" "--session-id" "$(cat "$argvf")"
  assert_contains "AS-N14 default argv carries --dangerously-skip-permissions" "--dangerously-skip-permissions" "$(cat "$argvf")"
}
ac_spawn_posture_default

echo "--- OVERRIDE posture: SDLC_SPAWN_PERMISSIONS set non-empty → its tokens replace the permission args verbatim, no --dangerously-skip-permissions ---"
ac_spawn_posture_override() {
  local gid="spawn-posture-override" d argvf fakedir out rc
  local SDLC_SPAWN_CMD SDLC_REGISTRY_CMD SDLC_SPAWN_PERMISSIONS
  SDLC_SPAWN_PERMISSIONS="--permission-mode acceptEdits"
  setup_complete "$gid" 4 no; d="$REPO_DIR"
  write_complete_baton "$gid" "$d" 4 none
  argvf=$(mktemp); CLEAN_DIRS+=("$argvf"); : > "$argvf"
  fakedir="$(make_claude_fake "$argvf" 0)"
  SDLC_REGISTRY_CMD="$(make_registry_stub '{"sessions":[]}')"
  local PATH="$fakedir:$PATH"

  out="$(sdlc_successor_spawn "$gid" "$d" 2>/dev/null)"; rc=$?
  assert_eq "AS-N14 override drive exits 0" "0" "$rc"
  wait_for_file "$argvf" 40
  assert_contains "AS-N14 override argv carries --permission-mode" "--permission-mode" "$(cat "$argvf")"
  assert_contains "AS-N14 override argv carries acceptEdits" "acceptEdits" "$(cat "$argvf")"
  TOTAL=$((TOTAL + 1))
  if grep -qF -- "--dangerously-skip-permissions" "$argvf"; then
    fail "AS-N14 override argv does NOT carry --dangerously-skip-permissions" "found it in: $(cat "$argvf")"
  else
    pass "AS-N14 override argv does NOT carry --dangerously-skip-permissions"
  fi
}
ac_spawn_posture_override

echo "--- WEAK posture: SDLC_SPAWN_PERMISSIONS set EMPTY (caller's explicit choice) → no permission args at all ---"
ac_spawn_posture_empty() {
  local gid="spawn-posture-empty" d argvf fakedir out rc
  local SDLC_SPAWN_CMD SDLC_REGISTRY_CMD SDLC_SPAWN_PERMISSIONS
  SDLC_SPAWN_PERMISSIONS=""
  setup_complete "$gid" 4 no; d="$REPO_DIR"
  write_complete_baton "$gid" "$d" 4 none
  argvf=$(mktemp); CLEAN_DIRS+=("$argvf"); : > "$argvf"
  fakedir="$(make_claude_fake "$argvf" 0)"
  SDLC_REGISTRY_CMD="$(make_registry_stub '{"sessions":[]}')"
  local PATH="$fakedir:$PATH"

  out="$(sdlc_successor_spawn "$gid" "$d" 2>/dev/null)"; rc=$?
  assert_eq "AS-N14 empty-posture drive exits 0" "0" "$rc"
  wait_for_file "$argvf" 40
  assert_contains "AS-N14 empty-posture argv still carries -p" "-p" "$(cat "$argvf")"
  assert_contains "AS-N14 empty-posture argv still carries --session-id" "--session-id" "$(cat "$argvf")"
  TOTAL=$((TOTAL + 1))
  if grep -qF -- "--dangerously-skip-permissions" "$argvf" || grep -qF -- "--permission-mode" "$argvf"; then
    fail "AS-N14 empty-posture argv carries NO permission tokens" "found permission token in: $(cat "$argvf")"
  else
    pass "AS-N14 empty-posture argv carries NO permission tokens"
  fi
}
ac_spawn_posture_empty

# ============================================================
# slice 4/3: sdlc_ladder_next — ledger-derived rung position, capped rungs.
# The ladder derivation is PURE: it reads the goal's baton + ledger (via the
# existing parse helpers) and derives exactly one token from (classification,
# anchor, ledger, current-baton-generation) — no writes, no clock reads beyond
# the anchor ARG, no registry. Rung attempts are journaled here EXACTLY as the
# poker dispatcher (4/4) will: a completed attempt is one decision+effect pair
# through sdlc_effect_run under `rung:<gid>:<rung>:<anchor>:<n>`.
# ============================================================
echo ""
echo "=== AC-C3/AC-C4/AC-C5: sdlc_ladder_next — ledger-derived rung position, capped rungs (4/3) ==="

# The episode anchor is now an 8-hex DURABLE-PROGRESS DIGEST (D-C2 amendment,
# Step-6 critic F1) — no longer a transcript-mtime epoch. sdlc_ladder_next treats
# it as an opaque token, so these ledger-derivation tests pass a fixed valid
# 8-hex; the digest's derivation from durable state is covered by the dedicated
# sdlc_ladder_anchor block below.
LADDER_ANCHOR=a1b2c3d4

# journal_rung <gid> <rung> <anchor> <n> — a COMPLETED (applied) rung attempt
# (decision+effect through the real effect guard, as the poker will).
journal_rung() { sdlc_effect_run "$1" "rung:$1:$2:$3:$4" "rung $2 attempt $4" -- true >/dev/null 2>&1; }
# journal_rung_decision <gid> <rung> <anchor> <n> — a decision-only rung line
# (the crash window: intent journaled, effect never landed).
journal_rung_decision() { ledger_append "$1" decision "rung:$1:$2:$3:$4" "rung $2 intent $4" >/dev/null 2>&1; }
# baton_written_at <gid> — the CURRENT baton generation key (BATON_WRITTEN_AT).
baton_written_at() { baton_parse "$(baton_path "$1")" >/dev/null 2>&1; printf '%s' "$BATON_WRITTEN_AT"; }
# journal_spawn_applied <gid> <written-at> — the spawn effect for a generation.
journal_spawn_applied() { sdlc_effect_run "$1" "spawn:$1:$2" "spawned" -- true >/dev/null 2>&1; }
# journal_spawn_decision <gid> <written-at> — decision-only spawn line (indeterminate).
journal_spawn_decision() { ledger_append "$1" decision "spawn:$1:$2" "spawn intent" >/dev/null 2>&1; }
# state_manifest — content+structure fingerprint of SDLC_STATE_DIR (purity probe).
state_manifest() { { find "$SDLC_STATE_DIR" | sort; echo "--"; find "$SDLC_STATE_DIR" -type f -exec cksum {} + 2>/dev/null | sort; }; }

echo "--- DEAD progression: fresh → poke:1 → poke:2 → re-prompt:1 → re-prompt:2 → rollover (spawn unapplied) ---"
ac_ladder_dead_progression() {
  new_state_dir
  local gid="ladder-dead-prog" a="$LADDER_ANCHOR" out rc
  write_healthy "$gid" >/dev/null                    # baton present for the rollover derivation
  out="$(sdlc_ladder_next "$gid" DEAD "$a" 2>/dev/null)"; rc=$?
  assert_eq "4/3 DEAD fresh episode exits 0" "0" "$rc"
  assert_eq "4/3 DEAD fresh episode (empty rung-space) → poke:1" "poke:1" "$out"
  journal_rung "$gid" poke "$a" 1
  assert_eq "4/3 DEAD after 1 failed poke → poke:2" "poke:2" "$(sdlc_ladder_next "$gid" DEAD "$a" 2>/dev/null)"
  journal_rung "$gid" poke "$a" 2
  assert_eq "4/3 DEAD after 2 failed pokes (cap) → re-prompt:1" "re-prompt:1" "$(sdlc_ladder_next "$gid" DEAD "$a" 2>/dev/null)"
  journal_rung "$gid" re-prompt "$a" 1
  assert_eq "4/3 DEAD after 2 poke + 1 re-prompt → re-prompt:2" "re-prompt:2" "$(sdlc_ladder_next "$gid" DEAD "$a" 2>/dev/null)"
  journal_rung "$gid" re-prompt "$a" 2
  assert_eq "4/3 DEAD after 2 poke + 2 re-prompt, spawn unapplied → rollover" "rollover" "$(sdlc_ladder_next "$gid" DEAD "$a" 2>/dev/null)"
}
ac_ladder_dead_progression

echo "--- DEAD at rollover position, spawn key APPLIED → human (spawn-skipped, AS-N13; ladder never re-keys a spawn) ---"
ac_ladder_dead_spawn_applied() {
  new_state_dir
  local gid="ladder-dead-applied" a="$LADDER_ANCHOR" wa
  write_healthy "$gid" >/dev/null
  wa="$(baton_written_at "$gid")"
  journal_rung "$gid" poke "$a" 1; journal_rung "$gid" poke "$a" 2
  journal_rung "$gid" re-prompt "$a" 1; journal_rung "$gid" re-prompt "$a" 2
  journal_spawn_applied "$gid" "$wa"
  assert_eq "4/3 DEAD rollover pos + spawn APPLIED → human" "human" "$(sdlc_ladder_next "$gid" DEAD "$a" 2>/dev/null)"
}
ac_ladder_dead_spawn_applied

echo "--- DEAD at rollover position, spawn key INDETERMINATE (decision, no effect) → defect effect-indeterminate ---"
ac_ladder_dead_spawn_indeterminate() {
  new_state_dir
  local gid="ladder-dead-indet" a="$LADDER_ANCHOR" wa err rc
  write_healthy "$gid" >/dev/null
  wa="$(baton_written_at "$gid")"
  journal_rung "$gid" poke "$a" 1; journal_rung "$gid" poke "$a" 2
  journal_rung "$gid" re-prompt "$a" 1; journal_rung "$gid" re-prompt "$a" 2
  journal_spawn_decision "$gid" "$wa"
  err="$(sdlc_ladder_next "$gid" DEAD "$a" 2>&1 1>/dev/null)"; rc=$?
  assert_nonzero "4/3 DEAD spawn-indeterminate returns nonzero" "$rc"
  assert_contains "4/3 DEAD spawn-indeterminate names effect-indeterminate" "effect-indeterminate" "$err"
}
ac_ladder_dead_spawn_indeterminate

echo "--- DEAD unparseable baton at the rollover step → defect passthrough (caller fail-closed skips) ---"
ac_ladder_dead_baton_malformed() {
  new_state_dir
  local gid="ladder-dead-badbaton" a="$LADDER_ANCHOR" err rc
  write_healthy "$gid" >/dev/null
  journal_rung "$gid" poke "$a" 1; journal_rung "$gid" poke "$a" 2
  journal_rung "$gid" re-prompt "$a" 1; journal_rung "$gid" re-prompt "$a" 2
  printf 'garbage without keys\n' > "$(baton_path "$gid")"   # corrupt the baton
  err="$(sdlc_ladder_next "$gid" DEAD "$a" 2>&1 1>/dev/null)"; rc=$?
  assert_nonzero "4/3 DEAD malformed baton at rollover returns nonzero" "$rc"
  assert_contains "4/3 DEAD malformed baton passes a baton defect through" "defect:" "$err"
}
ac_ladder_dead_baton_malformed

echo "--- CRASH WINDOW: a decision-only rung line under the CURRENT anchor → defect effect-indeterminate (before rollover) ---"
ac_ladder_crash_window() {
  new_state_dir
  local gid="ladder-crash" a="$LADDER_ANCHOR" err rc
  journal_rung_decision "$gid" poke "$a" 1     # poke intent, no effect
  err="$(sdlc_ladder_next "$gid" DEAD "$a" 2>&1 1>/dev/null)"; rc=$?
  assert_nonzero "4/3 crash-window rung decision-only returns nonzero" "$rc"
  assert_contains "4/3 crash-window names effect-indeterminate" "effect-indeterminate" "$err"
}
ac_ladder_crash_window

echo "--- IDLE_STALLED at 2 poke + 2 re-prompt (spawn unapplied) → human; rollover STRUCTURALLY unreachable for this class ---"
ac_ladder_idle_stalled_human() {
  new_state_dir
  local gid="ladder-idle-stalled" a="$LADDER_ANCHOR" out
  write_healthy "$gid" >/dev/null                    # spawn key would be unapplied → DEAD would rollover
  journal_rung "$gid" poke "$a" 1; journal_rung "$gid" poke "$a" 2
  journal_rung "$gid" re-prompt "$a" 1; journal_rung "$gid" re-prompt "$a" 2
  out="$(sdlc_ladder_next "$gid" IDLE_STALLED "$a" 2>/dev/null)"
  assert_eq "4/3 IDLE_STALLED after 2+2 → human" "human" "$out"
  TOTAL=$((TOTAL + 1))
  if [ "$out" = "rollover" ]; then
    fail "4/3 IDLE_STALLED NEVER emits rollover (session alive)" "got rollover"
  else
    pass "4/3 IDLE_STALLED NEVER emits rollover (session alive)"
  fi
}
ac_ladder_idle_stalled_human

echo "--- IDLE_STALLED fresh → poke:1 (shares the automated rungs with DEAD) ---"
ac_ladder_idle_stalled_fresh() {
  new_state_dir
  local gid="ladder-idle-fresh" a="$LADDER_ANCHOR"
  assert_eq "4/3 IDLE_STALLED fresh → poke:1" "poke:1" "$(sdlc_ladder_next "$gid" IDLE_STALLED "$a" 2>/dev/null)"
}
ac_ladder_idle_stalled_fresh

echo "--- WEDGED: observe:1 → observe:2 → observe:3 (cap 3) → human ---"
ac_ladder_wedged() {
  new_state_dir
  local gid="ladder-wedged" a="$LADDER_ANCHOR"
  assert_eq "4/3 WEDGED fresh → observe:1" "observe:1" "$(sdlc_ladder_next "$gid" WEDGED "$a" 2>/dev/null)"
  journal_rung "$gid" observe "$a" 1
  assert_eq "4/3 WEDGED after 1 observe → observe:2" "observe:2" "$(sdlc_ladder_next "$gid" WEDGED "$a" 2>/dev/null)"
  journal_rung "$gid" observe "$a" 2
  assert_eq "4/3 WEDGED after 2 observe → observe:3" "observe:3" "$(sdlc_ladder_next "$gid" WEDGED "$a" 2>/dev/null)"
  journal_rung "$gid" observe "$a" 3
  assert_eq "4/3 WEDGED after 3 observe (cap) → human" "human" "$(sdlc_ladder_next "$gid" WEDGED "$a" 2>/dev/null)"
}
ac_ladder_wedged

echo "--- ANCHOR RESET: attempts under anchor A stay history; called with anchor B → poke:1 (fresh episode) ---"
ac_ladder_anchor_reset() {
  new_state_dir
  local gid="ladder-anchor" a="$LADDER_ANCHOR" b="beefcafe"   # a distinct 8-hex digest
  journal_rung "$gid" poke "$a" 1; journal_rung "$gid" poke "$a" 2
  assert_eq "4/3 under anchor A (2 poke) → re-prompt:1 (A history intact)" "re-prompt:1" "$(sdlc_ladder_next "$gid" DEAD "$a" 2>/dev/null)"
  assert_eq "4/3 under anchor B (no B attempts) → poke:1 (episode reset)" "poke:1" "$(sdlc_ladder_next "$gid" DEAD "$b" 2>/dev/null)"
}
ac_ladder_anchor_reset

echo "--- classification not in {DEAD,IDLE_STALLED,WEDGED} → none ---"
ac_ladder_classification_none() {
  new_state_dir
  local gid="ladder-none" a="$LADDER_ANCHOR"
  assert_eq "4/3 BUSY → none" "none" "$(sdlc_ladder_next "$gid" BUSY "$a" 2>/dev/null)"
  assert_eq "4/3 IDLE → none" "none" "$(sdlc_ladder_next "$gid" IDLE "$a" 2>/dev/null)"
  assert_eq "4/3 GATED → none" "none" "$(sdlc_ladder_next "$gid" GATED "$a" 2>/dev/null)"
  assert_eq "4/3 empty classification → none" "none" "$(sdlc_ladder_next "$gid" "" "$a" 2>/dev/null)"
}
ac_ladder_classification_none

echo "--- guards: invalid goal-id / malformed anchor / empty anchor / corrupt ledger → loud defect, rc 1 ---"
ac_ladder_guards() {
  new_state_dir
  local a="$LADDER_ANCHOR" err rc gid="ladder-guard"
  err="$(sdlc_ladder_next "bad/goal" DEAD "$a" 2>&1 1>/dev/null)"; rc=$?
  assert_nonzero "4/3 invalid goal-id returns nonzero" "$rc"
  assert_contains "4/3 invalid goal-id names invalid-goal-id" "invalid-goal-id" "$err"

  err="$(sdlc_ladder_next "$gid" DEAD "not-an-epoch" 2>&1 1>/dev/null)"; rc=$?
  assert_nonzero "4/3 malformed anchor returns nonzero" "$rc"
  assert_contains "4/3 malformed anchor names invalid-anchor" "invalid-anchor" "$err"

  err="$(sdlc_ladder_next "$gid" DEAD "" 2>&1 1>/dev/null)"; rc=$?
  assert_nonzero "4/3 empty anchor returns nonzero" "$rc"
  assert_contains "4/3 empty anchor names invalid-anchor" "invalid-anchor" "$err"

  local cgid="ladder-corrupt" path
  path=$(build_healthy_ledger "$cgid")
  awk -F'\t' -v OFS='\t' 'NR==2 { $6="TAMPERED" } { print }' "$path" > "$path.new" && mv "$path.new" "$path"
  err="$(sdlc_ladder_next "$cgid" DEAD "$a" 2>&1 1>/dev/null)"; rc=$?
  assert_nonzero "4/3 corrupt ledger returns nonzero" "$rc"
  assert_contains "4/3 corrupt ledger surfaces a chain defect" "defect:" "$err"
}
ac_ladder_guards

echo "--- cap overrides: SDLC_RUNG_CAP=1 shrinks poke/re-prompt; SDLC_OBSERVE_CAP=1 shrinks observe ---"
ac_ladder_cap_rung() {
  new_state_dir
  local gid="ladder-cap-rung" a="$LADDER_ANCHOR"
  local SDLC_RUNG_CAP=1
  write_healthy "$gid" >/dev/null
  assert_eq "4/3 cap=1 fresh → poke:1" "poke:1" "$(sdlc_ladder_next "$gid" DEAD "$a" 2>/dev/null)"
  journal_rung "$gid" poke "$a" 1
  assert_eq "4/3 cap=1 after 1 poke → re-prompt:1" "re-prompt:1" "$(sdlc_ladder_next "$gid" DEAD "$a" 2>/dev/null)"
  journal_rung "$gid" re-prompt "$a" 1
  assert_eq "4/3 cap=1 after 1 poke + 1 re-prompt → rollover" "rollover" "$(sdlc_ladder_next "$gid" DEAD "$a" 2>/dev/null)"
}
ac_ladder_cap_rung

ac_ladder_cap_observe() {
  new_state_dir
  local gid="ladder-cap-obs" a="$LADDER_ANCHOR"
  local SDLC_OBSERVE_CAP=1
  assert_eq "4/3 observe cap=1 fresh → observe:1" "observe:1" "$(sdlc_ladder_next "$gid" WEDGED "$a" 2>/dev/null)"
  journal_rung "$gid" observe "$a" 1
  assert_eq "4/3 observe cap=1 after 1 observe → human" "human" "$(sdlc_ladder_next "$gid" WEDGED "$a" 2>/dev/null)"
}
ac_ladder_cap_observe

ac_ladder_cap_garbled() {
  new_state_dir
  local gid="ladder-cap-bad" a="$LADDER_ANCHOR" err rc
  local SDLC_RUNG_CAP="abc"
  err="$(sdlc_ladder_next "$gid" DEAD "$a" 2>&1 1>/dev/null)"; rc=$?
  assert_nonzero "4/3 garbled SDLC_RUNG_CAP returns nonzero" "$rc"
  assert_contains "4/3 garbled cap names invalid-cap" "invalid-cap" "$err"
}
ac_ladder_cap_garbled

echo "--- key grammar: _sdlc_rung_key mints exactly rung:<gid>:<rung>:<anchor>:<n>; rejects malformed anchor/ordinal/rung loud ---"
ac_ladder_key_grammar() {
  new_state_dir
  local out rc
  out="$(_sdlc_rung_key "wave-01" poke a1b2c3d4 1 2>/dev/null)"; rc=$?
  assert_eq "4/3 rung-key mint exits 0" "0" "$rc"
  assert_eq "4/3 rung-key mint is exact" "rung:wave-01:poke:a1b2c3d4:1" "$out"
  assert_eq "4/3 rung-key mints re-prompt name" "rung:g:re-prompt:a1b2c3d4:2" "$(_sdlc_rung_key g re-prompt a1b2c3d4 2 2>/dev/null)"

  # anchor grammar is now the 8-hex durable-progress digest (D-C2 amendment): an
  # epoch/mtime integer is no longer a valid anchor.
  _sdlc_rung_key g poke "notepoch"   1 2>/dev/null; assert_nonzero "4/3 rung-key rejects a non-8-hex anchor (letters)" "$?"
  _sdlc_rung_key g poke "1721600000" 1 2>/dev/null; assert_nonzero "4/3 rung-key rejects a non-8-hex anchor (epoch integer)" "$?"
  _sdlc_rung_key g poke a1b2c3d4 0 2>/dev/null;     assert_nonzero "4/3 rung-key rejects ordinal 0" "$?"
  _sdlc_rung_key g poke a1b2c3d4 "x" 2>/dev/null;   assert_nonzero "4/3 rung-key rejects a non-numeric ordinal" "$?"
  _sdlc_rung_key g bogus a1b2c3d4 1 2>/dev/null;    assert_nonzero "4/3 rung-key rejects an unknown rung name" "$?"
}
ac_ladder_key_grammar

echo "--- purity: a derivation call writes NOTHING under SDLC_STATE_DIR ---"
ac_ladder_purity_fresh() {
  new_state_dir
  local gid="ladder-pure-fresh" a="$LADDER_ANCHOR" out
  out="$(sdlc_ladder_next "$gid" DEAD "$a" 2>/dev/null)"
  assert_eq "4/3 purity: fresh DEAD still derives poke:1" "poke:1" "$out"
  TOTAL=$((TOTAL + 1))
  if [ -e "$SDLC_STATE_DIR/$gid" ]; then
    fail "4/3 purity: fresh derivation created NO goal dir" "found: $SDLC_STATE_DIR/$gid"
  else
    pass "4/3 purity: fresh derivation created NO goal dir"
  fi
}
ac_ladder_purity_fresh

ac_ladder_purity_populated() {
  new_state_dir
  local gid="ladder-pure-pop" a="$LADDER_ANCHOR" before after out
  write_healthy "$gid" >/dev/null
  journal_rung "$gid" poke "$a" 1; journal_rung "$gid" poke "$a" 2
  journal_rung "$gid" re-prompt "$a" 1; journal_rung "$gid" re-prompt "$a" 2
  before="$(state_manifest)"
  out="$(sdlc_ladder_next "$gid" DEAD "$a" 2>/dev/null)"
  after="$(state_manifest)"
  assert_eq "4/3 purity: populated fixture derives rollover" "rollover" "$out"
  assert_eq "4/3 purity: SDLC_STATE_DIR manifest byte-unchanged across the derivation" "$before" "$after"
}
ac_ladder_purity_populated

# ============================================================
# slice 6/critic-fix: sdlc_ladder_anchor — the DURABLE-PROGRESS DIGEST that
# replaces the transcript-mtime anchor (D-C2 amendment, Step-6 critic F1). The
# anchor keys off durable progress ONLY (plan current, goal branch tip,
# passenger-class ledger tail, baton written-at), so a poke's own resume turn
# (which only moves the transcript) can never reset the episode it is judged by.
# ============================================================
echo ""
echo "=== critic-F1 fix: sdlc_ladder_anchor — durable-progress episode digest ==="

# anchor_fixture <gid> <current> — a real git repo + plan + aligned baton so the
# durable tuple is fully readable. Sets AF_DIR / AF_PLAN / AF_BRANCH.
anchor_fixture() {
  local gid="$1" current="$2"
  new_state_dir
  AF_DIR=$(mktemp -d); CLEAN_DIRS+=("$AF_DIR")
  git -C "$AF_DIR" init -q
  git -C "$AF_DIR" config user.name fixture; git -C "$AF_DIR" config user.email f@e.com
  printf 'base\n' > "$AF_DIR/f.txt"; git -C "$AF_DIR" add -A; git -C "$AF_DIR" commit -qm base >/dev/null 2>&1
  AF_BRANCH=$(git -C "$AF_DIR" symbolic-ref --short HEAD)
  AF_PLAN="$AF_DIR/plan.md"; printf 'current: %s\n' "$current" > "$AF_PLAN"
  baton_write "$gid" "$AF_PLAN" "$AF_DIR" "$AF_BRANCH" "epic/x" \
    "$(git -C "$AF_DIR" rev-parse HEAD)" "$current" "sid-$gid/1" none "go" none none >/dev/null 2>&1
}
anchor_of_lib() { sdlc_ladder_anchor "$1" "$AF_PLAN" "$AF_DIR" 2>/dev/null; }

echo "--- shape + determinism: 8-hex, reproducible in-process AND cold (AC-C3 heritage) ---"
ac_anchor_shape() {
  anchor_fixture "anc-shape" 4
  local gid="anc-shape" a rc cold
  a="$(sdlc_ladder_anchor "$gid" "$AF_PLAN" "$AF_DIR")"; rc=$?
  assert_eq "anchor derivation exits 0 on a healthy fixture" "0" "$rc"
  TOTAL=$((TOTAL + 1))
  if printf '%s' "$a" | grep -qE '^[0-9a-f]{8}$'; then pass "anchor is an 8-hex digest"
  else fail "anchor is an 8-hex digest" "got '$a'"; fi
  assert_eq "anchor deterministic in-process" "$a" "$(anchor_of_lib "$gid")"
  cold="$(bash -c '. "$1"; SDLC_STATE_DIR="$2" sdlc_ladder_anchor "$3" "$4" "$5"' \
            bash "$LIB" "$SDLC_STATE_DIR" "$gid" "$AF_PLAN" "$AF_DIR" 2>/dev/null)"
  assert_eq "anchor deterministic across a COLD process (cold-readable, D-C7)" "$a" "$cold"
}
ac_anchor_shape

echo "--- purity: derivation writes NOTHING under SDLC_STATE_DIR ---"
ac_anchor_purity() {
  anchor_fixture "anc-pure" 4
  local gid="anc-pure" before after
  before="$(state_manifest)"
  sdlc_ladder_anchor "$gid" "$AF_PLAN" "$AF_DIR" >/dev/null 2>&1
  after="$(state_manifest)"
  assert_eq "anchor derivation is pure (manifest byte-unchanged)" "$before" "$after"
}
ac_anchor_purity

echo "--- reset grid: EACH durable-tuple component changing individually → fresh digest; spine-class growth → UNCHANGED ---"
ac_anchor_reset_grid() {
  anchor_fixture "anc-grid" 4
  local gid="anc-grid" prev cur
  prev="$(anchor_of_lib "$gid")"
  # (a) plan current: bump
  printf 'current: 5\n' > "$AF_PLAN"
  cur="$(anchor_of_lib "$gid")"
  assert_true "reset-grid (a) plan current: bump → fresh episode digest" test "$prev" != "$cur"
  prev="$cur"
  # (b) new commit on the goal branch (tip sha advances)
  printf 'x\n' >> "$AF_DIR/f.txt"; git -C "$AF_DIR" add -A; git -C "$AF_DIR" commit -qm w >/dev/null 2>&1
  cur="$(anchor_of_lib "$gid")"
  assert_true "reset-grid (b) new commit on goal branch → fresh episode digest" test "$prev" != "$cur"
  prev="$cur"
  # (c) passenger-class ledger append
  ledger_append "$gid" effect "passwork:$gid:1" "passenger progress" >/dev/null 2>&1
  cur="$(anchor_of_lib "$gid")"
  assert_true "reset-grid (c) passenger-class ledger append → fresh episode digest" test "$prev" != "$cur"
  prev="$cur"
  # (d) new baton written-at (new generation) — patch just the written-at line so
  # only that tuple component changes (deterministic, no wall-clock sleep).
  awk '/^written-at:/{print "written-at: 2099-01-01T00:00:00Z"; next}{print}' \
    "$(baton_path "$gid")" > "$(baton_path "$gid").tmp" && mv "$(baton_path "$gid").tmp" "$(baton_path "$gid")"
  cur="$(anchor_of_lib "$gid")"
  assert_true "reset-grid (d) new baton written-at → fresh episode digest" test "$prev" != "$cur"
  prev="$cur"
  # (e) spine-class ledger growth (the ladder's OWN rung/park/spawn entries) does
  # NOT move the anchor — the ladder can never reset the episode it is judged by.
  journal_rung "$gid" poke "$prev" 1
  ledger_append "$gid" effect "park:$gid:x"  "park entry"  >/dev/null 2>&1
  ledger_append "$gid" effect "spawn:$gid:y" "spawn entry" >/dev/null 2>&1
  assert_eq "reset-grid (e) spine-class ledger growth → anchor UNCHANGED" \
    "$prev" "$(anchor_of_lib "$gid")"
}
ac_anchor_reset_grid

echo "--- CRITIC REPRO (F1): a non-progress poke does NOT reset the episode (mtime observer-effect gone) ---"
ac_anchor_critic_repro() {
  anchor_fixture "anc-critic" 4
  local gid="anc-critic" a a2
  a="$(anchor_of_lib "$gid")"
  assert_eq "critic-repro fresh DEAD under the durable anchor → poke:1" \
    "poke:1" "$(sdlc_ladder_next "$gid" DEAD "$a" 2>/dev/null)"
  # a poke's own resume turn ONLY moves the transcript; the durable tuple is
  # unchanged, so re-deriving the anchor yields the SAME digest (pre-fix, an
  # mtime anchor bumped here and reset the episode to poke:1 forever).
  journal_rung "$gid" poke "$a" 1
  a2="$(anchor_of_lib "$gid")"
  assert_eq "critic-repro anchor STABLE across a non-progress poke (no observer effect)" "$a" "$a2"
  assert_eq "critic-repro re-poll, tuple unchanged → poke:2 (escalates), NOT reset to poke:1" \
    "poke:2" "$(sdlc_ladder_next "$gid" DEAD "$a2" 2>/dev/null)"
  journal_rung "$gid" poke "$a" 2
  assert_eq "critic-repro poke cap reached under a stable anchor → re-prompt:1 (escalation reachable)" \
    "re-prompt:1" "$(sdlc_ladder_next "$gid" DEAD "$a" 2>/dev/null)"
}
ac_anchor_critic_repro

echo "--- WEDGED churn no longer evades the observe cap (tuple stable → cap reached → human) ---"
ac_anchor_wedged_cap() {
  anchor_fixture "anc-wedged" 4
  local gid="anc-wedged" a
  a="$(anchor_of_lib "$gid")"
  journal_rung "$gid" observe "$a" 1
  journal_rung "$gid" observe "$a" 2
  journal_rung "$gid" observe "$a" 3
  assert_eq "wedged-cap anchor stable despite transcript churn" "$a" "$(anchor_of_lib "$gid")"
  assert_eq "wedged-cap observe cap reached despite churn → human" \
    "human" "$(sdlc_ladder_next "$gid" WEDGED "$a" 2>/dev/null)"
}
ac_anchor_wedged_cap

echo "--- defects: unreadable plan / unreadable cwd / corrupt ledger / unparseable baton → loud defect, rc 1 ---"
ac_anchor_defects() {
  anchor_fixture "anc-def" 4
  local gid="anc-def" err rc lp
  err="$(sdlc_ladder_anchor "bad/goal" "$AF_PLAN" "$AF_DIR" 2>&1 1>/dev/null)"; rc=$?
  assert_nonzero "anchor invalid goal-id → nonzero" "$rc"
  assert_contains "anchor invalid goal-id names invalid-goal-id" "invalid-goal-id" "$err"

  err="$(sdlc_ladder_anchor "$gid" "/nonexistent/plan.md" "$AF_DIR" 2>&1 1>/dev/null)"; rc=$?
  assert_nonzero "anchor unreadable plan → nonzero" "$rc"
  assert_contains "anchor unreadable plan names plan-unreadable" "plan-unreadable" "$err"

  err="$(sdlc_ladder_anchor "$gid" "$AF_PLAN" "/no/such/repo" 2>&1 1>/dev/null)"; rc=$?
  assert_nonzero "anchor unreadable cwd → nonzero" "$rc"
  assert_contains "anchor unreadable cwd names cwd-unreadable" "cwd-unreadable" "$err"

  ledger_append "$gid" effect "passwork:$gid" "p" >/dev/null 2>&1
  lp="$(ledger_path "$gid")"
  awk -F'\t' -v OFS='\t' 'NR==1{$6="TAMPERED"}{print}' "$lp" > "$lp.new" && mv "$lp.new" "$lp"
  err="$(sdlc_ladder_anchor "$gid" "$AF_PLAN" "$AF_DIR" 2>&1 1>/dev/null)"; rc=$?
  assert_nonzero "anchor corrupt ledger → nonzero" "$rc"
  assert_contains "anchor corrupt ledger surfaces a chain defect" "defect:" "$err"

  printf 'garbage without keys\n' > "$(baton_path "$gid")"
  err="$(sdlc_ladder_anchor "$gid" "$AF_PLAN" "$AF_DIR" 2>&1 1>/dev/null)"; rc=$?
  assert_nonzero "anchor unparseable baton → nonzero" "$rc"
  assert_contains "anchor unparseable baton passes a baton defect through" "defect:" "$err"
}
ac_anchor_defects

echo "--- F1b (critic-fix-2): unresolvable baton branch → fail-closed defect, NOT a fail-open literal-ref digest ---"
ac_anchor_branch_neverexisted() {
  anchor_fixture "anc-brF1b" 4
  local gid="anc-brF1b" err rc out
  # baton's recorded branch is a typo/never-existed name in a perfectly valid repo
  # (critic-poc/failopen.sh repro). Unpatched: git rev-parse echoes the LITERAL
  # ref name to stdout at rc 128; the `-z` guard misses it → fail-open digest.
  awk '/^branch:/{print "branch: feat/does-not-exist"; next}{print}' \
    "$(baton_path "$gid")" > "$(baton_path "$gid").tmp" && mv "$(baton_path "$gid").tmp" "$(baton_path "$gid")"

  err="$(sdlc_ladder_anchor "$gid" "$AF_PLAN" "$AF_DIR" 2>&1 1>/dev/null)"; rc=$?
  assert_nonzero "F1b never-existed branch → nonzero (fail-closed, not fail-open)" "$rc"
  assert_contains "F1b never-existed branch surfaces a named defect" "defect:" "$err"

  out="$(sdlc_ladder_anchor "$gid" "$AF_PLAN" "$AF_DIR" 2>/dev/null)"
  assert_eq "F1b never-existed branch → NOTHING digested on stdout" "" "$out"
}
ac_anchor_branch_neverexisted

echo "--- F1b: branch renamed/deleted after merge (baton still names the old ref) → same fail-closed defect ---"
ac_anchor_branch_deleted() {
  anchor_fixture "anc-brdel" 4
  local gid="anc-brdel" err rc out
  # the goal branch existed and had a real tip, but was renamed away (deleted
  # post-merge is the same shape) — the baton's recorded name no longer resolves.
  git -C "$AF_DIR" branch -m "$AF_BRANCH" "${AF_BRANCH}-renamed" -q

  err="$(sdlc_ladder_anchor "$gid" "$AF_PLAN" "$AF_DIR" 2>&1 1>/dev/null)"; rc=$?
  assert_nonzero "F1b renamed/deleted branch → nonzero (fail-closed)" "$rc"
  assert_contains "F1b renamed/deleted branch surfaces a named defect" "defect:" "$err"

  out="$(sdlc_ladder_anchor "$gid" "$AF_PLAN" "$AF_DIR" 2>/dev/null)"
  assert_eq "F1b renamed/deleted branch → NOTHING digested on stdout" "" "$out"
}
ac_anchor_branch_deleted

echo "--- F1b regression: a VALID branch still digests IDENTICALLY (resolvable-branch behavior is unchanged by the fix) ---"
ac_anchor_branch_valid_unchanged() {
  anchor_fixture "anc-brok" 4
  local gid="anc-brok" want got tip
  # independently reproduce the durable tuple via the OLD raw rev-parse
  # resolution (which agrees byte-for-byte with the new --verify resolution on
  # any REAL, resolvable ref) and assert the library's actual output matches —
  # proving the fix changes nothing for the healthy path.
  tip=$(git -C "$AF_DIR" rev-parse "$AF_BRANCH" 2>/dev/null)
  baton_parse "$(baton_path "$gid")" >/dev/null 2>&1
  want="$(ledger_digest "$(printf '%s\n%s\n%s\n%s' 4 "$tip" 0 "$BATON_WRITTEN_AT")")"
  got="$(anchor_of_lib "$gid")"
  assert_eq "F1b regression: resolvable-branch anchor byte-identical to the raw-rev-parse formula" "$want" "$got"
}
ac_anchor_branch_valid_unchanged

# ============================================================
# ===== 4/S1 watchdog: flag resolution + arm/disarm =========
# ============================================================
# Fixtures drive the REAL lib functions (sdlc_watchdog_effective,
# sdlc_pilot_effective, sdlc_arm, sdlc_disarm) against planted plan
# files + a fresh fake $HOME (goals dir + audit log live under it).

# write_plan <path> <scale> [watchdog] [pilot] — emit a plan with a
# frontmatter block. Empty watchdog/pilot arg ⇒ that key is ABSENT
# (drives the fallback table); a non-on/off or non-manual/auto value
# is an off-enum fixture.
write_plan() {
  local path="$1" scale="$2" wd="${3:-}" pilot="${4:-}"
  mkdir -p "$(dirname "$path")" 2>/dev/null
  {
    echo "---"
    echo "scale: $scale"
    [ -n "$wd" ] && echo "watchdog: $wd"
    [ -n "$pilot" ] && echo "pilot: $pilot"
    echo "---"
    echo ""
    echo "# plan body"
  } > "$path"
}

# read a KEY=VALUE from a planted registration record.
reg_field() { grep -E "^$2=" "$1" 2>/dev/null | head -1 | sed -E "s/^$2=//"; }
poker_audit() { printf '%s/.claude/sdlc-poker-audit.log' "$HOME"; }
goals_reg() { printf '%s/.claude/sdlc-goals/%s' "$HOME" "$1"; }

echo ""
echo "=== 4/S1-G1: effective-flag grid (watchdog/pilot × scale × presence) ==="
ac_s1_effgrid() {
  new_state_dir
  local scale p out rc
  # --- watchdog: explicit on/off is scale-independent; absent →
  #     continuous:on, task/wave/epic:off (fallback table) ---
  for scale in continuous task wave epic; do
    write_plan "$HOME/p-$scale-t.plan.md" "$scale" on
    out=$(sdlc_watchdog_effective "$HOME/p-$scale-t.plan.md"); rc=$?
    assert_eq "watchdog explicit on ($scale) → on" "on" "$out"
    assert_eq "watchdog explicit on ($scale) → rc 0" "0" "$rc"

    write_plan "$HOME/p-$scale-f.plan.md" "$scale" off
    out=$(sdlc_watchdog_effective "$HOME/p-$scale-f.plan.md")
    assert_eq "watchdog explicit off ($scale) → off" "off" "$out"

    write_plan "$HOME/p-$scale-a.plan.md" "$scale"
    out=$(sdlc_watchdog_effective "$HOME/p-$scale-a.plan.md")
    if [ "$scale" = continuous ]; then
      assert_eq "watchdog absent (continuous) → on (fallback)" "on" "$out"
    else
      assert_eq "watchdog absent ($scale) → off (fallback)" "off" "$out"
    fi
  done

  # --- pilot: explicit manual/auto scale-independent; absent →
  #     continuous:auto, else manual ---
  write_plan "$HOME/pp-man.plan.md" wave "" manual
  out=$(sdlc_pilot_effective "$HOME/pp-man.plan.md"); rc=$?
  assert_eq "pilot explicit manual → manual" "manual" "$out"
  assert_eq "pilot explicit manual → rc 0" "0" "$rc"
  write_plan "$HOME/pp-auto.plan.md" task "" auto
  out=$(sdlc_pilot_effective "$HOME/pp-auto.plan.md")
  assert_eq "pilot explicit auto → auto" "auto" "$out"
  for scale in continuous task wave epic; do
    write_plan "$HOME/pp-$scale-a.plan.md" "$scale"
    out=$(sdlc_pilot_effective "$HOME/pp-$scale-a.plan.md")
    if [ "$scale" = continuous ]; then
      assert_eq "pilot absent (continuous) → auto (fallback)" "auto" "$out"
    else
      assert_eq "pilot absent ($scale) → manual (fallback)" "manual" "$out"
    fi
  done

  # --- off-enum pilot → rc 2 + stderr names the bad value (never guess);
  #     legacy uppercase MANUAL is now off-enum (KA-R16 lowercase contract) ---
  write_plan "$HOME/pp-bad.plan.md" wave "" SEMI
  out=$(sdlc_pilot_effective "$HOME/pp-bad.plan.md" 2>/dev/null); rc=$?
  assert_eq "pilot off-enum → rc 2" "2" "$rc"
  local err
  err=$(sdlc_pilot_effective "$HOME/pp-bad.plan.md" 2>&1 1>/dev/null)
  assert_contains "pilot off-enum → stderr names the bad value" "SEMI" "$err"
  write_plan "$HOME/pp-upper.plan.md" wave "" MANUAL
  out=$(sdlc_pilot_effective "$HOME/pp-upper.plan.md" 2>/dev/null); rc=$?
  assert_eq "pilot legacy uppercase MANUAL → rc 2 (off-enum)" "2" "$rc"

  # --- off-enum watchdog → rc 2 + stderr (symmetric fail-loud) ---
  write_plan "$HOME/pk-bad.plan.md" wave "maybe"
  out=$(sdlc_watchdog_effective "$HOME/pk-bad.plan.md" 2>/dev/null); rc=$?
  assert_eq "watchdog off-enum → rc 2" "2" "$rc"
  err=$(sdlc_watchdog_effective "$HOME/pk-bad.plan.md" 2>&1 1>/dev/null)
  assert_contains "watchdog off-enum → stderr names the bad value" "maybe" "$err"

  # --- a plan still carrying the pre-rename flag key → rc 2 + stderr
  #     "renamed to watchdog:" (never a silent fallthrough to fallback) ---
  { echo "---"; echo "scale: wave"; echo "keep${_none:-}alive: true"; echo "---"; } > "$HOME/pk-stale.plan.md"
  out=$(sdlc_watchdog_effective "$HOME/pk-stale.plan.md" 2>/dev/null); rc=$?
  assert_eq "watchdog stale pre-rename key → rc 2" "2" "$rc"
  err=$(sdlc_watchdog_effective "$HOME/pk-stale.plan.md" 2>&1 1>/dev/null)
  assert_contains "watchdog stale key → stderr says renamed to watchdog:" "renamed to watchdog:" "$err"

  # --- unreadable/missing plan → rc 1 + empty stdout (both fns) ---
  out=$(sdlc_watchdog_effective "$HOME/does-not-exist.plan.md" 2>/dev/null); rc=$?
  assert_eq "watchdog missing plan → rc 1" "1" "$rc"
  assert_eq "watchdog missing plan → empty stdout" "" "$out"
  out=$(sdlc_pilot_effective "$HOME/does-not-exist.plan.md" 2>/dev/null); rc=$?
  assert_eq "pilot missing plan → rc 1" "1" "$rc"
  assert_eq "pilot missing plan → empty stdout" "" "$out"
}
ac_s1_effgrid

echo ""
echo "=== 4/S1-G2: arm round-trip (5-field record, atomic, audit) ==="
ac_s1_arm_roundtrip() {
  new_state_dir
  local plan out rc rec
  plan="$HOME/plans/mywave.plan.md"
  write_plan "$plan" wave on         # watchdog:on task/wave/epic → armable
  export SDLC_ARM_SESSION_ID="sid-fixture-1"
  export SDLC_ARM_PID="31337"

  out=$(sdlc_arm "$plan"); rc=$?
  assert_eq "arm watchdog:on wave → rc 0" "0" "$rc"
  assert_eq "arm → stdout is the goal-id" "mywave" "$out"

  rec="$(goals_reg mywave)"
  assert_true "arm → registration record exists" test -f "$rec"
  # 5 fields exact
  assert_eq "record PLAN = resolved absolute plan path" "$plan" "$(reg_field "$rec" PLAN)"
  assert_eq "record CWD = arm-time pwd" "$(pwd)" "$(reg_field "$rec" CWD)"
  assert_eq "record SESSION_ID = SDLC_ARM_SESSION_ID seam" "sid-fixture-1" "$(reg_field "$rec" SESSION_ID)"
  assert_eq "record PID = SDLC_ARM_PID seam" "31337" "$(reg_field "$rec" PID)"
  # ARMED_AT is an ISO-8601 Z stamp
  assert_true "record ARMED_AT is ISO-8601 Zulu" bash -c \
    'printf "%s" "$1" | grep -qE "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"' _ "$(reg_field "$rec" ARMED_AT)"
  # exactly the 5 keys, no partial / extra
  assert_eq "record has exactly 5 KEY= lines" "5" "$(grep -cE '^[A-Z_]+=' "$rec")"

  # audit line follows the poker's audit_line convention (<iso> <gid> <event>
  # <detail>): the ARM <gid> <plan> pilot=<p> content lands as
  # "<iso> mywave ARM <plan> pilot=manual" (pilot falls back to manual for wave).
  local audit; audit="$(cat "$(poker_audit)" 2>/dev/null)"
  assert_contains "arm → audit ARM line present" "mywave ARM $plan pilot=manual" "$audit"

  unset SDLC_ARM_SESSION_ID SDLC_ARM_PID

  # --- atomicity: injected write failure leaves NO record behind ---
  new_state_dir
  plan="$HOME/plans/atom.plan.md"
  write_plan "$plan" wave on
  # plant the goals dir as a regular FILE so mkdir/write into it fails
  mkdir -p "$HOME/.claude"
  : > "$HOME/.claude/sdlc-goals"
  out=$(sdlc_arm "$plan" 2>/dev/null); rc=$?
  assert_nonzero "arm with unwritable goals dir → nonzero" "$rc"
  assert_true "arm failure → no partial record file" test ! -e "$(goals_reg atom)"
}
ac_s1_arm_roundtrip

echo ""
echo "=== 4/S1-G3: arm refusals (missing/malformed/collision/false) + --force ==="
ac_s1_arm_refusals() {
  new_state_dir
  local plan out rc err
  export SDLC_ARM_SESSION_ID="sid-fixture-3"; export SDLC_ARM_PID="4242"

  # --- missing plan → refuse, no record ---
  err=$(sdlc_arm "$HOME/nope/ghost.plan.md" 2>&1 1>/dev/null); rc=$?
  assert_nonzero "arm missing plan → nonzero" "$rc"
  assert_contains "arm missing plan → defect on stderr" "defect:" "$err"
  assert_true "arm missing plan → no record" test ! -e "$(goals_reg ghost)"

  # --- malformed frontmatter: off-enum watchdog → refuse, no record ---
  plan="$HOME/plans/badka.plan.md"; write_plan "$plan" wave "maybe"
  err=$(sdlc_arm "$plan" 2>&1 1>/dev/null); rc=$?
  assert_nonzero "arm off-enum watchdog → nonzero" "$rc"
  assert_contains "arm off-enum watchdog → defect on stderr" "defect:" "$err"
  assert_true "arm off-enum watchdog → no record" test ! -e "$(goals_reg badka)"

  # --- malformed frontmatter: off-enum pilot (no override) → refuse ---
  plan="$HOME/plans/badpilot.plan.md"; write_plan "$plan" wave on SEMI
  err=$(sdlc_arm "$plan" 2>&1 1>/dev/null); rc=$?
  assert_nonzero "arm off-enum pilot (no override) → nonzero" "$rc"
  assert_true "arm off-enum pilot → no record" test ! -e "$(goals_reg badpilot)"
  # an explicit pilot-override bypasses the unreadable plan pilot (still armable)
  out=$(sdlc_arm "$plan" auto 2>/dev/null); rc=$?
  assert_eq "arm off-enum pilot WITH override → rc 0" "0" "$rc"
  assert_contains "override → audit pilot=auto" "badpilot ARM $plan pilot=auto" "$(cat "$(poker_audit)")"

  # --- collision: existing record, different PLAN → refuse, record intact ---
  new_state_dir
  export SDLC_ARM_SESSION_ID="sid-fixture-3"; export SDLC_ARM_PID="4242"
  mkdir -p "$HOME/.claude/sdlc-goals" "$HOME/a"
  local rec; rec="$(goals_reg foo)"
  {
    echo "PLAN=/somewhere/else/foo.plan.md"; echo "CWD=/x"; echo "SESSION_ID=sid-old"
    echo "PID=999"; echo "ARMED_AT=2026-07-20T00:00:00Z"
  } > "$rec"
  plan="$HOME/a/foo.plan.md"; write_plan "$plan" wave on
  err=$(sdlc_arm "$plan" 2>&1 1>/dev/null); rc=$?
  assert_nonzero "arm collision (gid taken, different PLAN) → nonzero" "$rc"
  assert_contains "arm collision → defect on stderr" "defect:" "$err"
  assert_eq "arm collision → original record PLAN untouched" "/somewhere/else/foo.plan.md" "$(reg_field "$rec" PLAN)"

  # --- same-plan re-arm is idempotent (not a collision) ---
  new_state_dir
  export SDLC_ARM_SESSION_ID="sid-fixture-3"; export SDLC_ARM_PID="4242"
  plan="$HOME/plans/rearm.plan.md"; write_plan "$plan" wave on
  sdlc_arm "$plan" >/dev/null 2>&1
  out=$(sdlc_arm "$plan" 2>/dev/null); rc=$?
  assert_eq "arm same-plan re-arm → rc 0 (idempotent)" "0" "$rc"

  # --- watchdog-effective=off → refuse unless --force ---
  new_state_dir
  export SDLC_ARM_SESSION_ID="sid-fixture-3"; export SDLC_ARM_PID="4242"
  plan="$HOME/plans/kf.plan.md"; write_plan "$plan" wave off   # explicit off
  err=$(sdlc_arm "$plan" 2>&1 1>/dev/null); rc=$?
  assert_nonzero "arm watchdog:off without --force → nonzero" "$rc"
  assert_contains "arm watchdog:off → defect names force" "force" "$err"
  assert_true "arm watchdog:off without --force → no record" test ! -e "$(goals_reg kf)"
  out=$(sdlc_arm "$plan" --force 2>/dev/null); rc=$?
  assert_eq "arm watchdog:off WITH --force → rc 0" "0" "$rc"
  assert_true "arm --force → record written" test -f "$(goals_reg kf)"

  # absent-flag task/wave/epic is also watchdog-off → same refusal
  plan="$HOME/plans/absk.plan.md"; write_plan "$plan" epic
  rc=0; sdlc_arm "$plan" >/dev/null 2>&1 || rc=$?
  assert_nonzero "arm absent-watchdog epic (fallback off) without --force → nonzero" "$rc"

  unset SDLC_ARM_SESSION_ID SDLC_ARM_PID
}
ac_s1_arm_refusals

echo ""
echo "=== 4/S1-G4: disarm (present removes + audits; absent rc1 + no-op audit) ==="
ac_s1_disarm() {
  new_state_dir
  local plan out rc rec audit
  export SDLC_ARM_SESSION_ID="sid-fixture-4"; export SDLC_ARM_PID="4242"

  # --- present → removed + audit DISARM <gid> <reason>, default reason manual ---
  plan="$HOME/plans/dw.plan.md"; write_plan "$plan" wave on
  sdlc_arm "$plan" >/dev/null 2>&1
  rec="$(goals_reg dw)"
  assert_true "disarm setup → record present" test -f "$rec"
  out=$(sdlc_disarm dw); rc=$?
  assert_eq "disarm present → rc 0" "0" "$rc"
  assert_true "disarm present → record removed" test ! -e "$rec"
  audit="$(cat "$(poker_audit)")"
  assert_contains "disarm → audit DISARM line, default reason manual" "dw DISARM manual" "$audit"

  # second disarm of the same gid → rc 1 (absent), still audited as a no-op
  out=$(sdlc_disarm dw 2>/dev/null); rc=$?
  assert_eq "disarm absent → rc 1" "1" "$rc"
  assert_contains "disarm absent → audit line still emitted (no-op)" "dw DISARM" "$(cat "$(poker_audit)")"

  # --- custom reason surfaces in the audit line ---
  new_state_dir
  export SDLC_ARM_SESSION_ID="sid-fixture-4"; export SDLC_ARM_PID="4242"
  plan="$HOME/plans/dc.plan.md"; write_plan "$plan" wave on
  sdlc_arm "$plan" >/dev/null 2>&1
  out=$(sdlc_disarm dc complete); rc=$?
  assert_eq "disarm custom reason → rc 0" "0" "$rc"
  assert_contains "disarm → audit carries the custom reason" "dc DISARM complete" "$(cat "$(poker_audit)")"

  # --- guard: an invalid goal-id is refused loud (path-traversal guard) ---
  out=$(sdlc_disarm "" 2>/dev/null); rc=$?
  assert_nonzero "disarm empty goal-id → nonzero" "$rc"
  out=$(sdlc_disarm "a/b" 2>/dev/null); rc=$?
  assert_nonzero "disarm goal-id with slash → nonzero" "$rc"

  unset SDLC_ARM_SESSION_ID SDLC_ARM_PID
}
ac_s1_disarm

# ============================================================
echo ""
echo "========================================"
echo "sdlc-state primitives (baton + ledger): $PASS/$TOTAL passed, $FAIL failed"
echo "========================================"
[ "$FAIL" -eq 0 ] || exit 1
