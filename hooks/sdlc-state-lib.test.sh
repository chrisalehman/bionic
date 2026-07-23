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
  local gid="$1" wip="${2:-none}"
  baton_write "$gid" "/plans/$gid.plan.md" "/work/$gid" "wave-01-substrate" \
    "epic/10-never-die" "abc1234" "4" "sid-$gid/4242" "42:deadbeef" \
    "run the next slice" "$wip" >/dev/null 2>&1
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

REQUIRED_KEYS="goal-id plan cwd branch integration-branch last-commit sdlc-step session ledger-position next-action wip written-at"

# ============================================================
echo "=== AC-B1: round-trip write → cold parse → next-action + ledger-position readback ==="
ac_b1() {
  new_state_dir
  local gid="wave-01-substrate-4-1"
  local f; f=$(write_healthy "$gid" "deadbeef1234567890abcdef1234567890abcdef")
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
  err=$(baton_write "$gid" "p" "c" "b" "i" "lc" "4" "s" "1:abcd1234" "na" "deadbee" 2>&1 1>/dev/null); rc=$?
  assert_nonzero "abbreviated 7-hex wip rejected (nonzero rc)" "$rc"
  assert_contains "abbreviated 7-hex wip names invalid-wip-sha" "invalid-wip-sha" "$err"
  assert_no_file_written "abbreviated 7-hex wip: no baton file written" "$gid"
}
ac_grammar_wip_abbrev

echo "--- wip: full-length but non-hex sha → invalid-wip-sha, no file written ---"
ac_grammar_wip_nonhex() {
  new_state_dir
  local gid="grammar-wip-nonhex" err rc
  err=$(baton_write "$gid" "p" "c" "b" "i" "lc" "4" "s" "1:abcd1234" "na" "deadbeef1234567890abcdef1234567890abcdeg" 2>&1 1>/dev/null); rc=$?
  assert_nonzero "full-length non-hex wip rejected (nonzero rc)" "$rc"
  assert_contains "full-length non-hex wip names invalid-wip-sha" "invalid-wip-sha" "$err"
  assert_no_file_written "full-length non-hex wip: no baton file written" "$gid"
}
ac_grammar_wip_nonhex

echo "--- ledger-position: bare-seq (no digest) → invalid-ledger-position, no file written ---"
ac_grammar_ledger_bare_seq() {
  new_state_dir
  local gid="grammar-ledger-bare-seq" err rc
  err=$(baton_write "$gid" "p" "c" "b" "i" "lc" "4" "s" "42" "na" "none" 2>&1 1>/dev/null); rc=$?
  assert_nonzero "bare-seq ledger-position rejected (nonzero rc)" "$rc"
  assert_contains "bare-seq ledger-position names invalid-ledger-position" "invalid-ledger-position" "$err"
  assert_no_file_written "bare-seq ledger-position: no baton file written" "$gid"
}
ac_grammar_ledger_bare_seq

echo "--- ledger-position: zero-seq → invalid-ledger-position, no file written ---"
ac_grammar_ledger_zero_seq() {
  new_state_dir
  local gid="grammar-ledger-zero-seq" err rc
  err=$(baton_write "$gid" "p" "c" "b" "i" "lc" "4" "s" "0:abcd1234" "na" "none" 2>&1 1>/dev/null); rc=$?
  assert_nonzero "zero-seq ledger-position rejected (nonzero rc)" "$rc"
  assert_contains "zero-seq ledger-position names invalid-ledger-position" "invalid-ledger-position" "$err"
  assert_no_file_written "zero-seq ledger-position: no baton file written" "$gid"
}
ac_grammar_ledger_zero_seq

echo "--- ledger-position: missing digest (seq: with nothing after) → invalid-ledger-position, no file written ---"
ac_grammar_ledger_missing_digest() {
  new_state_dir
  local gid="grammar-ledger-missing-digest" err rc
  err=$(baton_write "$gid" "p" "c" "b" "i" "lc" "4" "s" "42:" "na" "none" 2>&1 1>/dev/null); rc=$?
  assert_nonzero "missing-digest ledger-position rejected (nonzero rc)" "$rc"
  assert_contains "missing-digest ledger-position names invalid-ledger-position" "invalid-ledger-position" "$err"
  assert_no_file_written "missing-digest ledger-position: no baton file written" "$gid"
}
ac_grammar_ledger_missing_digest

echo "--- accept: 'none' for both wip and ledger-position ---"
ac_grammar_accept_none() {
  new_state_dir
  local gid="grammar-accept-none" rc f
  baton_write "$gid" "p" "c" "b" "i" "lc" "4" "s" "none" "na" "none" >/dev/null 2>&1; rc=$?
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
    "cafebabe1234567890abcdef1234567890abcdef" >/dev/null 2>&1; rc=$?
  assert_eq "accept: full-form wip + minimal ledger-position returns rc 0" "0" "$rc"
  f="$(baton_path "$gid")"
  assert_true "accept: full-form wip + minimal ledger-position wrote a file" test -f "$f"
  baton_parse "$f"
  assert_eq "accept: minimal ledger-position round-trips" "1:00000000" "$BATON_LEDGER_POSITION"
  assert_eq "accept: full 40-hex wip round-trips" "cafebabe1234567890abcdef1234567890abcdef" "$BATON_WIP"
}
ac_grammar_accept_full

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
  git -C "$d" update-ref "refs/keepalive/$gid" "$snap"   # anchor the object
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
    baton_write "leak-goal" "p" "c" "b" "i" "lc" "4" "s" "1:00000000" "na" "none" >/dev/null 2>&1
    wrc=$?
    printf "unbound-ok:%s write-rc:%s\n" "$SOME_UNSET_VAR_NEVER_DEFINED_ANYWHERE" "$wrc"
  ' bash "$LIB" 2>&1)
  rc=$?
  assert_eq "nounset leak guard: exit 0 (sourcing the lib does not enable -u in the caller shell)" "0" "$rc"
  assert_contains "nounset leak guard: bare unset-var reference survives after sourcing (no -u leak)" "unbound-ok: write-rc:0" "$out"
}
ac_nounset_no_leak

# ============================================================
echo ""
echo "========================================"
echo "sdlc-state primitives (baton + ledger): $PASS/$TOTAL passed, $FAIL failed"
echo "========================================"
[ "$FAIL" -eq 0 ] || exit 1
