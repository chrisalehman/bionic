#!/bin/bash
# sdlc-state-lib — durable per-goal state primitives (epic-10-never-die,
# wave-01-substrate, slice 4/1: baton primitives).
#
# A sourced function library (D3) — no standalone process, nothing runs on
# source. Ships the baton half of the durable-state substrate: a structured-
# markdown file a dumb cron can cold-parse (R-B1/R-B2), with strict
# malformed-baton detection (R-B3) so a corrupted file is never partially
# trusted. Ledger primitives (R-L1/R-L2) and the context-spend ceiling
# extension (R-C1/R-C2) are later slices in this same wave; both will source
# this file.
#
# Placement (D1): per-goal durable state lives at
# $SDLC_STATE_DIR/<goal-id>/baton.md, defaulting to $HOME/.claude/sdlc-state
# — a sibling of the poker's consent registry (sdlc-goals/, untouched) and
# derived-status dir (sdlc-status/). SDLC_STATE_DIR is override-able so
# fixture suites never touch the real home surface (AS-6); the goal dir is
# created lib-side on write (mkdir -p), not bootstrap-provisioned.
#
# Baton format: fixed `key: value` lines, one per required key, in any
# order, with NO blank line among them. An optional blank line followed by
# free-prose text may appear after the keys (R-B1) — baton_parse treats
# everything from the first blank line onward as opaque prose and never
# scans it for state, so prose text can never be mistaken for a duplicate
# or malformed key.
#
# Required keys (R-B1): goal-id, plan, cwd, branch, integration-branch,
# last-commit, sdlc-step, session, ledger-position, next-action, written-at.

set -u

BATON_REQUIRED_KEYS="goal-id plan cwd branch integration-branch last-commit sdlc-step session ledger-position next-action written-at"

# ---------- path helpers (read SDLC_STATE_DIR/HOME at call time) ----------
sdlc_state_dir() { printf '%s' "${SDLC_STATE_DIR:-$HOME/.claude/sdlc-state}"; }
baton_goal_dir()  { printf '%s/%s' "$(sdlc_state_dir)" "$1"; }
baton_path()      { printf '%s/baton.md' "$(baton_goal_dir "$1")"; }

# ---------- R-B1: baton_write ----------
# baton_write <goal-id> <plan> <cwd> <branch> <integration-branch>
#             <last-commit> <sdlc-step> <session> <ledger-position>
#             <next-action> [prose]
# Serializes goal state as structured markdown with the fixed required-key
# lines, `written-at:` stamped here (UTC, now). Atomic: written to a tmp
# file in the SAME dir, then `mv` into place (single rename, never a
# partial file visible to a concurrent cold reader). Creates the goal's
# dir if absent (AS-6). Returns nonzero + a `defect:`-prefixed line on
# stderr if the goal-id is empty or the write/rename fails.
baton_write() {
  local goal_id="${1:-}" plan="${2:-}" cwd="${3:-}" branch="${4:-}" integ="${5:-}" \
        last_commit="${6:-}" step="${7:-}" session="${8:-}" ledger_pos="${9:-}" \
        next_action="${10:-}" prose="${11:-}"
  local dir target tmp written_at

  [ -n "$goal_id" ] || { echo "defect: missing-goal-id: baton_write requires a non-empty goal-id" >&2; return 1; }

  dir="$(baton_goal_dir "$goal_id")"
  mkdir -p "$dir" 2>/dev/null || { echo "defect: mkdir-failed: cannot create $dir" >&2; return 1; }

  target="$dir/baton.md"
  tmp="$dir/.baton.md.tmp.$$"
  written_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  {
    echo "goal-id: $goal_id"
    echo "plan: $plan"
    echo "cwd: $cwd"
    echo "branch: $branch"
    echo "integration-branch: $integ"
    echo "last-commit: $last_commit"
    echo "sdlc-step: $step"
    echo "session: $session"
    echo "ledger-position: $ledger_pos"
    echo "next-action: $next_action"
    echo "written-at: $written_at"
    if [ -n "$prose" ]; then
      echo ""
      printf '%s\n' "$prose"
    fi
  } > "$tmp" 2>/dev/null || { echo "defect: write-failed: cannot write $tmp" >&2; rm -f "$tmp" 2>/dev/null; return 1; }

  mv -f "$tmp" "$target" 2>/dev/null || { echo "defect: rename-failed: cannot install $target" >&2; rm -f "$tmp" 2>/dev/null; return 1; }
  return 0
}

# ---------- R-B2/R-B3: baton_parse ----------
# baton_parse <baton-file>
# Strict cold parse: a fresh process sourcing only this file can call
# baton_parse on a path alone and read every required field back (R-B2 —
# no dependency on the writer's shell state). On success (rc 0) sets the
# BATON_* globals below and returns 0. On ANY malformation (rc 1) prints
# exactly one line to stderr, `defect: <class>: <detail>`, and — critical
# to R-B3's "never partial trust" — leaves the BATON_* globals completely
# UNTOUCHED (validation runs to completion into local staging vars first;
# the globals are only ever committed together, after every required key
# has passed every check).
#
# Defect classes: missing-file, truncated-file (empty, or missing a
# trailing newline — the mid-flush-cut signal, distinct from a merely
# absent key), missing-key, duplicate-key, empty-value.
#
# Required keys are recognized ANYWHERE in the file's header block (every
# line up to the first blank line, or EOF if there is none) via a strict
# `^key:` anchor — never a "first match wins" `head -1` scan, so a
# duplicated required key is caught rather than silently shadowed. Any
# free-prose section after the first blank line is never scanned.
baton_parse() {
  local f="${1:-}"
  local header key count value
  local v_goal_id v_plan v_cwd v_branch v_integ v_last_commit v_step v_session v_ledger_pos v_next_action v_written_at

  [ -n "$f" ] && [ -f "$f" ] || { echo "defect: missing-file: baton not found: ${f:-<empty path>}" >&2; return 1; }
  [ -s "$f" ] || { echo "defect: truncated-file: baton is empty: $f" >&2; return 1; }
  if [ "$(tail -c1 "$f" 2>/dev/null | wc -l | tr -d '[:space:]')" != "1" ]; then
    echo "defect: truncated-file: baton does not end with a newline (cut off mid-write): $f" >&2
    return 1
  fi

  header=$(awk '{ if ($0 == "") exit; print }' "$f")

  for key in $BATON_REQUIRED_KEYS; do
    count=$(printf '%s\n' "$header" | grep -c -E "^${key}:")
    if [ "$count" -eq 0 ]; then
      echo "defect: missing-key: required key '$key' not found: $f" >&2
      return 1
    fi
    if [ "$count" -gt 1 ]; then
      echo "defect: duplicate-key: required key '$key' appears $count times: $f" >&2
      return 1
    fi
    value=$(printf '%s\n' "$header" | grep -E "^${key}:" | sed -E "s/^${key}:[[:space:]]*//")
    if [ -z "$value" ]; then
      echo "defect: empty-value: required key '$key' has an empty value: $f" >&2
      return 1
    fi
    case "$key" in
      goal-id)             v_goal_id="$value" ;;
      plan)                v_plan="$value" ;;
      cwd)                 v_cwd="$value" ;;
      branch)               v_branch="$value" ;;
      integration-branch)  v_integ="$value" ;;
      last-commit)         v_last_commit="$value" ;;
      sdlc-step)           v_step="$value" ;;
      session)             v_session="$value" ;;
      ledger-position)     v_ledger_pos="$value" ;;
      next-action)         v_next_action="$value" ;;
      written-at)          v_written_at="$value" ;;
    esac
  done

  # Every required key validated — commit atomically. Nothing above this
  # line ever touches a BATON_* global, so any earlier `return 1` leaves
  # the caller's prior state exactly as it was.
  BATON_GOAL_ID="$v_goal_id"
  BATON_PLAN="$v_plan"
  BATON_CWD="$v_cwd"
  BATON_BRANCH="$v_branch"
  BATON_INTEGRATION_BRANCH="$v_integ"
  BATON_LAST_COMMIT="$v_last_commit"
  BATON_SDLC_STEP="$v_step"
  BATON_SESSION="$v_session"
  BATON_LEDGER_POSITION="$v_ledger_pos"
  BATON_NEXT_ACTION="$v_next_action"
  BATON_WRITTEN_AT="$v_written_at"
  return 0
}

# ---------- R-L1/R-L2: ledger primitives (slice 4/2) ----------
#
# Ledger placement mirrors the baton (D1): $SDLC_STATE_DIR/<goal-id>/ledger.log,
# same override convention, dir created lib-side (mkdir -p) on first append.
#
# Line format (D4/R-L1), TAB-separated (matches context-spend's existing TSV
# state-file convention, AS-2) with the free-text summary as the LAST field:
#   ts \t seq \t digest \t type \t effect-key \t summary
# The summary is deliberately the final field: bash `read` folds any excess
# tokens (including embedded separators) into the last variable, so a summary
# containing spaces is always safe. Embedded tabs/newlines in effect-key or
# summary are rejected at append time (see ledger_append) rather than
# tolerated, so every line is guaranteed to carry exactly 6 fields — the
# invariant ledger_verify's chain walk depends on.
#
# Tamper evidence (D4): `digest` is an 8-hex prefix of sha256(previous line's
# full raw content) — NOT of the line's own content — so editing a line in
# place does not corrupt its own digest field, but breaks the NEXT line's
# chain reference, surfacing the edit on verify. The first line has no
# previous line, so it chains from a fixed genesis marker,
# LEDGER_GENESIS_MARKER, named here for auditability.
#
# Digest tool portability (AS-1): probed once per process into
# LEDGER_DIGEST_TOOL — `shasum -a 256` (macOS) else `sha256sum` (linux);
# loud error if neither is on PATH.

LEDGER_GENESIS_MARKER="SDLC-LEDGER-GENESIS-v1"

ledger_path() { printf '%s/ledger.log' "$(baton_goal_dir "$1")"; }

# ledger_digest_tool_probe — sets LEDGER_DIGEST_TOOL once; idempotent.
ledger_digest_tool_probe() {
  [ -n "${LEDGER_DIGEST_TOOL:-}" ] && return 0
  if command -v shasum >/dev/null 2>&1; then LEDGER_DIGEST_TOOL="shasum"; return 0; fi
  if command -v sha256sum >/dev/null 2>&1; then LEDGER_DIGEST_TOOL="sha256sum"; return 0; fi
  echo "defect: no-digest-tool: neither shasum nor sha256sum found on PATH" >&2
  return 1
}

# ledger_digest <content> — prints the 8-hex prefix of sha256(content).
# Requires LEDGER_DIGEST_TOOL already probed.
ledger_digest() {
  case "$LEDGER_DIGEST_TOOL" in
    shasum)    printf '%s' "$1" | shasum -a 256 | cut -c1-8 ;;
    sha256sum) printf '%s' "$1" | sha256sum    | cut -c1-8 ;;
  esac
}

# ---------- R-L1: ledger_append ----------
# ledger_append <goal-id> <type> <effect-key> <summary>
# type is `decision` or `effect` (R-L1). Appends one line: journal-before-act
# is a prose contract on the CALLER (append is the first act of any
# non-deterministic decision) — this primitive only guarantees the append
# itself is well-formed and atomic (single O_APPEND-style write; no tmp+mv,
# per the append-only contract — never rewrites existing lines). seq is
# strictly monotonic, derived from the last line currently on disk (1 if the
# ledger is absent or empty).
ledger_append() {
  local goal_id="${1:-}" type="${2:-}" key="${3:-}" summary="${4:-}"
  local dir path last_line prev_content seq ts digest new_line

  [ -n "$goal_id" ] || { echo "defect: missing-goal-id: ledger_append requires a non-empty goal-id" >&2; return 1; }
  case "$type" in
    decision|effect) ;;
    *) echo "defect: bad-type: ledger_append type must be 'decision' or 'effect', got '${type:-<empty>}'" >&2; return 1 ;;
  esac
  [ -n "$key" ] || { echo "defect: missing-effect-key: ledger_append requires a non-empty effect-key" >&2; return 1; }
  case "$key" in
    *$'\t'*|*$'\n'*) echo "defect: invalid-effect-key: effect-key must not contain a tab or newline" >&2; return 1 ;;
  esac
  case "$summary" in
    *$'\t'*|*$'\n'*) echo "defect: invalid-summary: summary must not contain a tab or newline" >&2; return 1 ;;
  esac

  ledger_digest_tool_probe || return 1

  dir="$(baton_goal_dir "$goal_id")"
  mkdir -p "$dir" 2>/dev/null || { echo "defect: mkdir-failed: cannot create $dir" >&2; return 1; }
  path="$(ledger_path "$goal_id")"

  if [ -s "$path" ]; then
    last_line=$(tail -n 1 "$path")
    seq=$(printf '%s' "$last_line" | awk -F'\t' '{print $2}')
    seq=$((seq + 1))
    prev_content="$last_line"
  else
    seq=1
    prev_content="$LEDGER_GENESIS_MARKER"
  fi

  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  digest=$(ledger_digest "$prev_content")
  new_line="$(printf '%s\t%s\t%s\t%s\t%s\t%s' "$ts" "$seq" "$digest" "$type" "$key" "$summary")"

  printf '%s\n' "$new_line" >> "$path" 2>/dev/null || { echo "defect: append-failed: cannot append to $path" >&2; return 1; }
  return 0
}

# ---------- R-L2: ledger_verify ----------
# ledger_verify <goal-id>
# Walks the whole chain. Defect classes (each named on stderr, nonzero
# exit): missing-ledger (file absent — distinct from an empty file, which is
# vacuously pristine and verifies silent/0, since there is nothing yet to
# tamper with), truncated-ledger (missing trailing newline — the same
# mid-flush-cut signal AS-10 established for the baton), seq-gap (the seq
# values present do not form a contiguous 1..N run — something is missing),
# seq-reorder (the seq values ARE the complete 1..N set, but not in
# ascending physical file order — lines were transposed), in-place-edit
# (chained-digest mismatch — a line's content was changed without
# recomputing the chain). A pristine ledger is silent and returns 0.
ledger_verify() {
  local goal_id="${1:-}" path
  [ -n "$goal_id" ] || { echo "defect: missing-goal-id: ledger_verify requires a non-empty goal-id" >&2; return 1; }
  path="$(ledger_path "$goal_id")"

  [ -f "$path" ] || { echo "defect: missing-ledger: ledger not found: $path" >&2; return 1; }
  [ -s "$path" ] || return 0

  if [ "$(tail -c1 "$path" 2>/dev/null | wc -l | tr -d '[:space:]')" != "1" ]; then
    echo "defect: truncated-ledger: ledger does not end with a newline (cut off mid-write): $path" >&2
    return 1
  fi

  ledger_digest_tool_probe || return 1

  local n=0 line
  local seqs=() lines=()
  while IFS= read -r line; do
    n=$((n + 1))
    seqs+=("$(printf '%s' "$line" | awk -F'\t' '{print $2}')")
    lines+=("$line")
  done < "$path"

  local unique_sorted unique_count max_seq
  unique_sorted=$(printf '%s\n' "${seqs[@]}" | sort -n -u)
  unique_count=$(printf '%s\n' "$unique_sorted" | grep -c .)
  max_seq=$(printf '%s\n' "$unique_sorted" | tail -1)

  if [ "$unique_count" -ne "$n" ] || [ "$max_seq" != "$n" ]; then
    echo "defect: seq-gap: ledger has $n lines but sequence numbers do not form a contiguous 1..$n run (distinct values: $unique_count, max: $max_seq): $path" >&2
    return 1
  fi

  local i
  for ((i = 0; i < n; i++)); do
    if [ "${seqs[$i]}" != "$((i + 1))" ]; then
      echo "defect: seq-reorder: line $((i + 1)) has seq=${seqs[$i]}, expected seq=$((i + 1)) in file order: $path" >&2
      return 1
    fi
  done

  local prev_content expected_digest actual_digest rest
  prev_content="$LEDGER_GENESIS_MARKER"
  for ((i = 0; i < n; i++)); do
    actual_digest=$(printf '%s' "${lines[$i]}" | awk -F'\t' '{print $3}')
    expected_digest=$(ledger_digest "$prev_content")
    if [ "$actual_digest" != "$expected_digest" ]; then
      echo "defect: in-place-edit: line $((i + 1)) digest mismatch (expected $expected_digest, got $actual_digest) — content changed without a chain-consistent digest: $path" >&2
      return 1
    fi
    prev_content="${lines[$i]}"
  done

  return 0
}

# ---------- R-L1: ledger_applied ----------
# ledger_applied <goal-id> <effect-key>
# Exit 0 iff an `effect`-type line with that exact effect-key exists;
# nonzero otherwise (including an absent or empty ledger — silent, since
# "not yet applied" is the ordinary case, not a defect). A `decision`-type
# line sharing the same key is deliberately NOT a match (both directions of
# R-L1's membership check).
ledger_applied() {
  local goal_id="${1:-}" key="${2:-}" path line l_type l_key
  [ -n "$goal_id" ] || return 1
  path="$(ledger_path "$goal_id")"
  [ -f "$path" ] && [ -s "$path" ] || return 1

  while IFS=$'\t' read -r _ _ _ l_type l_key _; do
    [ "$l_type" = "effect" ] && [ "$l_key" = "$key" ] && return 0
  done < "$path"
  return 1
}
