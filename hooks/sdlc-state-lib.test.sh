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
# write_healthy <goal-id> → writes a healthy baton via the REAL baton_write,
# returns its path.
write_healthy() {
  local gid="$1"
  baton_write "$gid" "/plans/$gid.plan.md" "/work/$gid" "wave-01-substrate" \
    "epic/10-never-die" "abc1234" "4" "sid-$gid/4242" "42" \
    "run the next slice" >/dev/null 2>&1
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

REQUIRED_KEYS="goal-id plan cwd branch integration-branch last-commit sdlc-step session ledger-position next-action written-at"

# ============================================================
echo "=== AC-B1: round-trip write → cold parse → next-action + ledger-position readback ==="
ac_b1() {
  new_state_dir
  local gid="wave-01-substrate-4-1"
  local f; f=$(write_healthy "$gid")
  assert_true "AC-B1 baton_write produced a file" test -f "$f"
  assert_eq "AC-B1 baton_write went through the goal's dir (AS-6 mkdir -p)" \
    "$SDLC_STATE_DIR/$gid/baton.md" "$f"

  cold_parse "$f"
  local rc na lp
  IFS=$'\t' read -r rc na lp <<< "$COLD_OUT"
  assert_eq "AC-B1 cold parse exit 0 on a healthy baton" "0" "$rc"
  assert_eq "AC-B1 cold next-action readback" "run the next slice" "$na"
  assert_eq "AC-B1 cold ledger-position readback" "42" "$lp"

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
  baton_parse "$dst" >/dev/null 2>&1
  assert_eq "AC-B2 a failed parse leaves prior BATON_* state untouched (no partial trust)" \
    "sentinel-untouched" "$BATON_GOAL_ID"
}
ac_b2_no_partial_trust

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
echo ""
echo "========================================"
echo "sdlc-state primitives (baton + ledger): $PASS/$TOTAL passed, $FAIL failed"
echo "========================================"
[ "$FAIL" -eq 0 ] || exit 1
