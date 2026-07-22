#!/bin/bash
# sdlc-state-lib — durable per-goal state primitives (epic-10-never-die,
# waves 01-02): baton primitives, ledger, WIP shadow store, effect guard.
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
# last-commit, sdlc-step, session, ledger-position, next-action, wip,
# written-at.

# Deliberately NO top-level `set -u` (FLAG 4): this file is sourced by
# other scripts (context-spend.sh today; N2-N4 later), and a sourced
# file's `set` options persist in the CALLING shell — not scoped to a
# subshell. A top-level `set -u` here would silently flip nounset on for
# every future sourcer, whether or not it opted in. The pervasive
# `${x:-}` guards throughout this file are the actual safety net; they
# do not depend on nounset being active.

BATON_REQUIRED_KEYS="goal-id plan cwd branch integration-branch last-commit sdlc-step session ledger-position next-action wip written-at"

# ---------- path helpers (read SDLC_STATE_DIR/HOME at call time) ----------
sdlc_state_dir() { printf '%s' "${SDLC_STATE_DIR:-$HOME/.claude/sdlc-state}"; }
baton_goal_dir()  { printf '%s/%s' "$(sdlc_state_dir)" "$1"; }
baton_path()      { printf '%s/baton.md' "$(baton_goal_dir "$1")"; }

# ---------- R-B1/AS-26: sdlc_goal_id (canonical goal-id derivation) ----------
# sdlc_goal_id <plan-path> — the canonical goal-id transform for future
# writers (N2-N4): sanitized, lowercased stem of the plan path, byte-
# equivalent to context-spend.sh's own inline derivation (~line 120).
# context-spend.sh deliberately keeps its inline copy rather than
# sourcing this lib (reviewed self-containment) — a divergence-guard
# test in the suite proves the two stay byte-identical on a probe set;
# any future edit to either site MUST update the other.
sdlc_goal_id() {
  basename "${1:-}" .plan.md | sed 's/[^A-Za-z0-9-]/-/g' | tr '[:upper:]' '[:lower:]'
}

# ---------- FLAG 3: goal-id path guard ----------
# _sdlc_validate_goal_id <goal-id> <caller-label> — shared by baton_write,
# baton_parse, ledger_append, ledger_verify, ledger_applied. Rejects a
# goal-id that is empty, contains '/', or begins with '.' (covers '..')
# — every goal-id is used to build a filesystem path (baton_goal_dir),
# so an unguarded value is a path-traversal opening. Nonzero + one
# `defect: invalid-goal-id:` line on stderr.
_sdlc_validate_goal_id() {
  local gid="${1:-}" who="${2:-goal-id}"
  case "$gid" in
    '') echo "defect: invalid-goal-id: $who requires a non-empty goal-id" >&2; return 1 ;;
    */*) echo "defect: invalid-goal-id: $who goal-id must not contain '/': '$gid'" >&2; return 1 ;;
    .*) echo "defect: invalid-goal-id: $who goal-id must not begin with '.': '$gid'" >&2; return 1 ;;
  esac
  return 0
}

# ---------- R-B1: baton_write ----------
# baton_write <goal-id> <plan> <cwd> <branch> <integration-branch>
#             <last-commit> <sdlc-step> <session> <ledger-position>
#             <next-action> <wip> [prose]
# Serializes goal state as structured markdown with the fixed required-key
# lines, `written-at:` stamped here (UTC, now). Atomic: written to a tmp
# file in the SAME dir, then `mv` into place (single rename, never a
# partial file visible to a concurrent cold reader). Creates the goal's
# dir if absent (AS-6). Returns nonzero + a `defect:`-prefixed line on
# stderr if the goal-id is empty or the write/rename fails.
baton_write() {
  local goal_id="${1:-}" plan="${2:-}" cwd="${3:-}" branch="${4:-}" integ="${5:-}" \
        last_commit="${6:-}" step="${7:-}" session="${8:-}" ledger_pos="${9:-}" \
        next_action="${10:-}" wip="${11:-}" prose="${12:-}"
  local dir target tmp written_at

  _sdlc_validate_goal_id "$goal_id" "baton_write" || return 1

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
    echo "wip: $wip"
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
  local v_goal_id v_plan v_cwd v_branch v_integ v_last_commit v_step v_session v_ledger_pos v_next_action v_wip v_written_at

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
      goal-id)
        _sdlc_validate_goal_id "$value" "baton_parse" || return 1
        v_goal_id="$value" ;;
      plan)                v_plan="$value" ;;
      cwd)                 v_cwd="$value" ;;
      branch)               v_branch="$value" ;;
      integration-branch)  v_integ="$value" ;;
      last-commit)         v_last_commit="$value" ;;
      sdlc-step)           v_step="$value" ;;
      session)             v_session="$value" ;;
      ledger-position)     v_ledger_pos="$value" ;;
      next-action)         v_next_action="$value" ;;
      wip)                 v_wip="$value" ;;
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
  BATON_WIP="$v_wip"
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
# Tamper evidence (D4, AS-28 — SELF-COVERING chain): `digest` is an 8-hex
# prefix of sha256 over BOTH the previous line's digest AND this line's own
# content, so every line — including the terminal one — is covered by a
# check. A prev-line-only chain (the original design) left the LAST line
# protected by nothing: an in-place edit of the terminal line passed verify
# while ledger_applied returned the forged value. The self-covering rule
# closes that: editing any line changes its own digest's expected value,
# surfacing on verify at that very line.
#
# Digested material for line i (the CANONICAL serialization both append and
# verify hash, fixed here so the two sites can never drift):
#   <prev> <TAB> ts <TAB> seq <TAB> type <TAB> effect-key <TAB> summary
# where <prev> is digest[i-1] (the previous line's stored 8-hex digest
# field) for i>1, or the literal LEDGER_GENESIS_MARKER for i=1, and the
# trailing five TAB-joined fields are exactly the line's own fields with its
# OWN digest column (field 3) omitted — see _ledger_content. So:
#   digest[1] = H(GENESIS_MARKER \t content_1)
#   digest[i] = H(digest[i-1]    \t content_i)   for i > 1
# This is accident/naive-edit tamper evidence via an 8-hex truncation — NOT
# a cryptographic tamper-proof guarantee (an adversary who recomputes the
# whole chain forward from the edit still passes; trailing whole-line
# DELETION stays chain-undetectable, AS-25, owed to N3's ledger-position
# cross-check).
#
# Format version: the marker is v2 because the chain rule itself changed
# (self-covering vs prev-line-only). A v1-format ledger cannot silently
# verify under v2 rules — its digests were computed over different material,
# so verify reports in-place-edit rather than a false pass. There are ZERO
# real ledgers in existence (checked: ~/.claude/sdlc-state is empty), so no
# migration is owed.
#
# Digest tool portability (AS-1): probed once per process into
# LEDGER_DIGEST_TOOL — `shasum -a 256` (macOS) else `sha256sum` (linux);
# loud error if neither is on PATH.

LEDGER_GENESIS_MARKER="SDLC-LEDGER-GENESIS-v2"

# _ledger_content <raw-line> — the canonical digested material's line-half:
# the TAB-joined line fields with the digest column (field 3) omitted, i.e.
# `ts \t seq \t type \t effect-key \t summary`. Both ledger_append (building
# the material from the fields it is about to write) and ledger_verify
# (extracting it from a stored line) MUST agree on this shape.
_ledger_content() {
  printf '%s' "$1" | awk -F'\t' -v OFS='\t' '{ print $1, $2, $4, $5, $6 }'
}

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
  local dir path last_line prev seq ts content digest new_line

  _sdlc_validate_goal_id "$goal_id" "ledger_append" || return 1
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
    case "$seq" in
      ''|*[!0-9]*) echo "defect: corrupt-ledger-tail: last line's seq field is not numeric ('${seq:-<empty>}'): $path" >&2; return 1 ;;
    esac
    # The self-covering chain reads the tail's own digest as this line's
    # <prev>; a malformed tail digest would silently poison the new digest,
    # so reject it loud (same class as the numeric-seq guard) before append.
    prev=$(printf '%s' "$last_line" | awk -F'\t' '{print $3}')
    case "$prev" in
      [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) ;;
      *) echo "defect: corrupt-ledger-tail: last line's digest field is not 8 hex chars ('${prev:-<empty>}'): $path" >&2; return 1 ;;
    esac
    seq=$((seq + 1))
  else
    seq=1
    prev="$LEDGER_GENESIS_MARKER"
  fi

  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  # Self-covering digest (AS-28): hash <prev> together with this line's own
  # content (all fields but the digest column) — see the canonical
  # serialization documented at LEDGER_GENESIS_MARKER.
  content=$(printf '%s\t%s\t%s\t%s\t%s' "$ts" "$seq" "$type" "$key" "$summary")
  digest=$(ledger_digest "$prev"$'\t'"$content")
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
  _sdlc_validate_goal_id "$goal_id" "ledger_verify" || return 1
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

  # Self-covering chain (AS-28): recompute every line's digest — INCLUDING
  # the terminal line — from <prev> plus that line's own content, so a
  # tampered terminal line surfaces at its own digest rather than at a
  # (non-existent) next line. <prev> is the previous line's STORED digest
  # field (genesis marker for line 1), matching ledger_append.
  local prev expected_digest actual_digest content
  prev="$LEDGER_GENESIS_MARKER"
  for ((i = 0; i < n; i++)); do
    actual_digest=$(printf '%s' "${lines[$i]}" | awk -F'\t' '{print $3}')
    content=$(_ledger_content "${lines[$i]}")
    expected_digest=$(ledger_digest "$prev"$'\t'"$content")
    if [ "$actual_digest" != "$expected_digest" ]; then
      echo "defect: in-place-edit: line $((i + 1)) digest mismatch (expected $expected_digest, got $actual_digest) — content changed without a chain-consistent digest: $path" >&2
      return 1
    fi
    prev="$actual_digest"
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
  _sdlc_validate_goal_id "$goal_id" "ledger_applied" || return 1
  path="$(ledger_path "$goal_id")"
  [ -f "$path" ] && [ -s "$path" ] || return 1

  while IFS=$'\t' read -r _ _ _ l_type l_key _; do
    [ "$l_type" = "effect" ] && [ "$l_key" = "$key" ] && return 0
  done < "$path"
  return 1
}

# ---------- D4/D5: effect guard — exactly-once replay (slice 4/3) ----------
#
# The exactly-once leg atop the ledger primitives: journal-before-act plus a
# post-crash replay that runs an effect no more than once, even when a death
# fell between the intent and the outcome.
#
# Effect-key grammar (D4): `<class>:<qualifier>`.
#   * class — an OPEN lowercase set naming the KIND of side effect
#     (notify, merge, poke, append, ...). New classes need no registration.
#   * qualifier — deterministic and REPLAY-STABLE: the SAME logical action
#     must derive the SAME key on every replay. NEVER embed a timestamp, pid,
#     or session-id — a key that changes between the original run and its
#     replay defeats the guard (the replayer sees `unapplied` and re-runs).
#   Examples:
#     notify:slack-run-done        (one Slack ping per run)
#     merge:pr-1487                (merge a specific PR exactly once)
#     poke:reviewer-jane-wave-02   (nudge a named reviewer once per wave)
#
# The two states that gate a replay decision (see sdlc_effect_state):
#   applied        — an effect line for the key exists; the outcome landed.
#   indeterminate  — a decision line exists but NO effect line: intent was
#                    journaled, outcome unknown (the crash window).
#   unapplied      — neither exists (absent/empty ledger included): "not yet".

# sdlc_effect_state <goal-id> <effect-key>
# Prints exactly one of `applied` / `indeterminate` / `unapplied` (rc 0).
# Membership mirrors ledger_applied (effect-type, exact key); an absent or
# empty ledger is `unapplied` — "not yet" is ordinary, not a defect (AS-27).
# Loud named defects (rc 1, one stderr line): invalid-goal-id (shared guard),
# missing-effect-key (matches ledger_append's class).
sdlc_effect_state() {
  local goal_id="${1:-}" key="${2:-}" path l_type l_key has_decision=0
  _sdlc_validate_goal_id "$goal_id" "sdlc_effect_state" || return 1
  [ -n "$key" ] || { echo "defect: missing-effect-key: sdlc_effect_state requires a non-empty effect-key" >&2; return 1; }

  path="$(ledger_path "$goal_id")"
  if [ -f "$path" ] && [ -s "$path" ]; then
    while IFS=$'\t' read -r _ _ _ l_type l_key _; do
      [ "$l_key" = "$key" ] || continue
      [ "$l_type" = "effect" ] && { printf 'applied\n'; return 0; }
      [ "$l_type" = "decision" ] && has_decision=1
    done < "$path"
  fi
  [ "$has_decision" -eq 1 ] && { printf 'indeterminate\n'; return 0; }
  printf 'unapplied\n'
  return 0
}

# sdlc_effect_run <goal-id> <effect-key> <summary> [--replay-safe] -- <cmd> [args...]
# Runs <cmd> AT MOST ONCE for the key, journal-before-act. The literal `--`
# separates the guard's own args from the command; `--replay-safe` (the only
# flag) sits before it. Behavior by state:
#   applied        → rc 0, command NOT executed (idempotent success, silent).
#   indeterminate, no --replay-safe → fail-closed (J1): one stderr line
#                    `effect-indeterminate`, nonzero, command NOT executed —
#                    the caller parks GATED for a human replay decision.
#   indeterminate + --replay-safe, OR unapplied → journal the decision intent
#                    (SKIP when a decision line already exists — the
#                    indeterminate replay-safe path must not double-journal),
#                    run the command, and on rc 0 journal the effect line.
#                    Command nonzero → that rc, NO effect line: the intent
#                    stands so a live caller may retry, and a future replayer
#                    correctly sees `indeterminate` and parks (D5/AS-8).
# Any ledger_append failure propagates loud (its own named defect, nonzero) —
# never swallowed. Loud guard defects: invalid-goal-id, missing-effect-key,
# missing-command (no command after `--`), bad-args (unexpected token before
# `--`).
sdlc_effect_run() {
  local goal_id="${1:-}" key="${2:-}" summary="${3:-}" replay_safe=0 state

  _sdlc_validate_goal_id "$goal_id" "sdlc_effect_run" || return 1
  [ -n "$key" ] || { echo "defect: missing-effect-key: sdlc_effect_run requires a non-empty effect-key" >&2; return 1; }

  if [ "$#" -ge 3 ]; then shift 3; else shift "$#"; fi
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --replay-safe) replay_safe=1; shift ;;
      --)            shift; break ;;
      *) echo "defect: bad-args: sdlc_effect_run expected '--replay-safe' or '--' before the command, got '$1'" >&2; return 1 ;;
    esac
  done
  [ "$#" -ge 1 ] || { echo "defect: missing-command: sdlc_effect_run requires a command after '--'" >&2; return 1; }

  state="$(sdlc_effect_state "$goal_id" "$key")" || return 1
  case "$state" in
    applied)
      return 0 ;;
    indeterminate)
      if [ "$replay_safe" -eq 0 ]; then
        echo "defect: effect-indeterminate: $key — journaled intent has no recorded effect; replay requires a decision" >&2
        return 1
      fi
      ;;  # replay-safe: the decision is already journaled — do NOT re-append
    unapplied)
      ledger_append "$goal_id" decision "$key" "$summary" || return 1 ;;
  esac

  "$@"
  local cmd_rc=$?
  [ "$cmd_rc" -eq 0 ] || return "$cmd_rc"   # intent stands; no effect line

  ledger_append "$goal_id" effect "$key" "$summary" || return 1
  return 0
}

# ---------- R-W1/R-W2: WIP shadow store (slice 4/2) ----------
#
# The durable-state substrate's third leg: a git-plumbing SIDE STORE for
# work-in-progress that survives a session death without ever touching the
# working tree, the real index, the branch, or the evidence gate (D1). A
# confused successor that would otherwise clobber uncommitted work instead
# finds it captured under refs/sdlc-wip/<goal-id> and replays it byte-faithful.
#
# Evidence-gate neutrality (D1, binding): snapshot uses ONLY plumbing —
# read-tree/add/write-tree into a TEMPORARY index (GIT_INDEX_FILE, never the
# repo's real index), commit-tree, update-ref. Porcelain `git commit` is NEVER
# invoked: the evidence gate's matcher word-bounds `git commit`, and a stray
# porcelain commit here would trip it. Every git invocation is `-C <dir>` so
# the caller's $PWD is irrelevant (D3: the repo is the caller-supplied dir).
#
# Gitignored lifecycle artifacts (the goal's plan/spec under .bionic/docs) are
# part of the work product but `git add -A` skips them, so snapshot force-adds
# each caller-named path (`git add -f`). ONE ref per goal, overwritten each
# checkpoint; a clean tree deletes the ref and reports `none`, so the snapshot
# always reflects now (never a stale capture). Superseded snapshots become
# unreachable and gc-able — accepted, no retention machinery (D1).

# sdlc_wip_snapshot <goal-id> <dir> [force-include-path ...]
# Captures the repo-at-<dir>'s WIP into a shadow commit under
# refs/sdlc-wip/<goal-id> without touching the working tree, real index, or
# branch. Prints the snapshot sha (rc 0), or `none` (rc 0) when there is
# nothing to capture — deleting any stale ref in that case. Loud named
# defects (one stderr line, nonzero): invalid-goal-id, not-a-repo,
# snapshot-failed.
sdlc_wip_snapshot() {
  local goal_id="${1:-}" dir="${2:-}"
  if [ "$#" -ge 2 ]; then shift 2; else set --; fi   # remaining args = force-include paths
  local tmp_index head_tree tree snap p

  _sdlc_validate_goal_id "$goal_id" "sdlc_wip_snapshot" || return 1

  # not-a-repo: dir absent, not a git repo, or no HEAD commit to parent onto.
  # HEAD^{tree} both proves a usable repo/HEAD and gives the clean-tree anchor.
  head_tree=$(git -C "$dir" rev-parse --verify --quiet 'HEAD^{tree}' 2>/dev/null) || true
  if [ -z "$head_tree" ]; then
    echo "defect: not-a-repo: sdlc_wip_snapshot needs a git repo with a HEAD at: ${dir:-<empty dir>}" >&2
    return 1
  fi

  tmp_index=$(mktemp 2>/dev/null) || { echo "defect: snapshot-failed: cannot mint a temp index" >&2; return 1; }
  # Build the snapshot tree in the TEMP index only (real index untouched):
  # seed from HEAD, stage every dirty/untracked-unignored change, then
  # force-add each caller-named gitignored lifecycle-artifact path.
  if ! GIT_INDEX_FILE="$tmp_index" git -C "$dir" read-tree HEAD 2>/dev/null \
     || ! GIT_INDEX_FILE="$tmp_index" git -C "$dir" add -A 2>/dev/null; then
    rm -f "$tmp_index"
    echo "defect: snapshot-failed: could not stage WIP into the temp index for: $dir" >&2
    return 1
  fi
  for p in "$@"; do
    [ -n "$p" ] || continue
    if ! GIT_INDEX_FILE="$tmp_index" git -C "$dir" add -f -- "$p" 2>/dev/null; then
      rm -f "$tmp_index"
      echo "defect: snapshot-failed: could not force-add '$p' for: $dir" >&2
      return 1
    fi
  done
  tree=$(GIT_INDEX_FILE="$tmp_index" git -C "$dir" write-tree 2>/dev/null) \
    || { rm -f "$tmp_index"; echo "defect: snapshot-failed: write-tree failed for: $dir" >&2; return 1; }
  rm -f "$tmp_index"

  # Nothing captured (tree matches HEAD): report none, drop any stale ref.
  if [ "$tree" = "$head_tree" ]; then
    git -C "$dir" update-ref -d "refs/sdlc-wip/$goal_id" 2>/dev/null || :
    printf 'none\n'
    return 0
  fi

  snap=$(git -C "$dir" commit-tree "$tree" -p HEAD -m "sdlc-wip snapshot: $goal_id" 2>/dev/null) \
    || { echo "defect: snapshot-failed: commit-tree failed for: $dir" >&2; return 1; }
  git -C "$dir" update-ref "refs/sdlc-wip/$goal_id" "$snap" 2>/dev/null \
    || { echo "defect: snapshot-failed: update-ref refs/sdlc-wip/$goal_id failed for: $dir" >&2; return 1; }
  printf '%s\n' "$snap"
  return 0
}

# sdlc_wip_restore <goal-id> <sha> <dir>
# Replays the captured delta into the repo-at-<dir>'s working tree,
# byte-faithful, touching ONLY the captured paths: for each added/modified
# path write the snapshot blob (creating parent dirs; restoring the exec bit
# when the dst mode is 100755); for each deleted path remove the working-tree
# file. Loud named defects (one stderr line, nonzero): invalid-goal-id,
# wip-lost (object missing/unreadable), restore-failed.
#
# The delta is `diff-tree -r -z <sha>^ <sha>` — the snapshot vs its HEAD
# parent (snapshots always `commit-tree -p HEAD`, so <sha>^ resolves). -z
# (NUL-delimited) is chosen so paths with spaces or shell metacharacters
# survive intact: each record is a metadata field
# `:<src-mode> <dst-mode> <src-sha> <dst-sha> <status>` terminated by NUL,
# then the path terminated by NUL. Rename/copy detection is off (snapshots
# never emit R/C), so there is never a second path field to consume; statuses
# seen are A/M/D and, defensively, T (type change) — all non-D are treated as
# "write the dst blob". Only the exec bit is mode-faithful (100755 → +x); a
# 100644 restore leaves the freshly written file at the umask default and does
# not actively clear a pre-existing +x (out of scope; content is faithful).
sdlc_wip_restore() {
  local goal_id="${1:-}" sha="${2:-}" dir="${3:-}"
  local difftmp meta path src_mode dst_mode src_sha dst_sha status target

  _sdlc_validate_goal_id "$goal_id" "sdlc_wip_restore" || return 1

  if [ -z "$sha" ] || ! git -C "$dir" cat-file -e "$sha" 2>/dev/null; then
    echo "defect: wip-lost: sdlc_wip_restore cannot read snapshot object '${sha:-<empty>}' in: $dir" >&2
    return 1
  fi

  difftmp=$(mktemp 2>/dev/null) || { echo "defect: restore-failed: cannot mint a temp file" >&2; return 1; }
  # NUL-safe stream to a temp file: command substitution would strip the NUL
  # delimiters, so the -z output is consumed from a file, not a variable.
  if ! git -C "$dir" diff-tree -r -z "$sha^" "$sha" > "$difftmp" 2>/dev/null; then
    rm -f "$difftmp"
    echo "defect: restore-failed: diff-tree failed for snapshot '$sha' in: $dir" >&2
    return 1
  fi

  while IFS= read -r -d '' meta; do
    IFS= read -r -d '' path || { rm -f "$difftmp"; echo "defect: restore-failed: truncated diff-tree stream for '$sha' in: $dir" >&2; return 1; }
    # meta = ":<src-mode> <dst-mode> <src-sha> <dst-sha> <status>" (leading ':' stripped).
    read -r src_mode dst_mode src_sha dst_sha status <<< "${meta#:}"
    # Path-containment guard (forged/corrupted-object hardening, ADR-001 D5).
    # $path is about to be joined as "$dir/$path" and written or removed. A
    # normal snapshot can't carry an escaping path (git add rejects absolute
    # paths and '..'), but a FORGED/corrupted snapshot object can — a tree
    # with a '..'-named subtree yields a '../escape' delta path, and a raw
    # tree hand-built past fsck can carry a leading '/'. Either would let
    # restore write/remove outside "$dir". Reject BEFORE building $target, so
    # neither branch (A/M write, D remove) can act on it. The '..' test is
    # slash-bounded ("/$path/" vs */../*) — a precise PATH-COMPONENT match, so
    # a legitimate dotted filename like 'a..b.txt' is NOT rejected, whereas a
    # bare '..' substring test would false-reject it.
    case "$path" in
      /*) rm -f "$difftmp"
          echo "defect: restore-unsafe-path: refusing absolute path '$path' from snapshot '$sha' in: $dir" >&2
          return 1 ;;
    esac
    case "/$path/" in
      */../*) rm -f "$difftmp"
              echo "defect: restore-unsafe-path: refusing '..' traversal in path '$path' from snapshot '$sha' in: $dir" >&2
              return 1 ;;
    esac
    # A forged path with a '.git' component (no '..', not absolute → passes the
    # tests above) would let restore write an executable hook or clobber config
    # inside "$dir/.git" — the next git op then runs it (RCE). Reject any '.git'
    # path component, CASE-FOLDED: APFS/HFS are case-insensitive, so '.GIT' etc
    # alias the real dir. Lowercase via tr (no bash-4 ${x,,}, preserving the
    # lib's 3.2-compatible idiom), then a slash-bounded component match — precise,
    # so a legit 'foo.git.txt' or '.github/' (no bare '.git' component) is spared.
    case "$(printf '%s' "/$path/" | tr '[:upper:]' '[:lower:]')" in
      */.git/*) rm -f "$difftmp"
                echo "defect: restore-unsafe-path: refusing '.git'-component path '$path' from snapshot '$sha' in: $dir" >&2
                return 1 ;;
    esac
    # Symlink containment: a string test on $path cannot catch a PRE-EXISTING
    # worktree symlink at any component — 'mkdir -p $dir/link' is a no-op on a
    # symlinked dir and 'cat-file blob > $dir/link/leaf' (or a rm of it) then
    # follows the link OUTSIDE "$dir". Walk each component from the trusted root
    # "$dir" down to and including the leaf; if any existing prefix is a symlink
    # (lstat, -L), refuse. Not-yet-existing real dirs are not symlinks, so a
    # legitimate nested restore still mkdir -p's them and writes. Guards BOTH the
    # write (A/M) and remove (D) branches, which follow below.
    local _walk="$path" _comp _accum="$dir"
    while [ -n "$_walk" ]; do
      case "$_walk" in
        */*) _comp="${_walk%%/*}"; _walk="${_walk#*/}" ;;
        *)   _comp="$_walk";       _walk="" ;;
      esac
      [ -z "$_comp" ] && continue
      _accum="$_accum/$_comp"
      if [ -L "$_accum" ]; then
        rm -f "$difftmp"
        echo "defect: restore-unsafe-target: refusing to restore through symlinked component '$_comp' in path '$path' from snapshot '$sha' in: $dir" >&2
        return 1
      fi
    done
    target="$dir/$path"
    case "$status" in
      D)
        rm -f "$target" 2>/dev/null || { rm -f "$difftmp"; echo "defect: restore-failed: cannot remove '$path' in: $dir" >&2; return 1; }
        ;;
      *)  # A / M / T — materialize the snapshot blob at the worktree path.
        mkdir -p "$(dirname "$target")" 2>/dev/null || { rm -f "$difftmp"; echo "defect: restore-failed: cannot mkdir for '$path' in: $dir" >&2; return 1; }
        if ! git -C "$dir" cat-file blob "$dst_sha" > "$target" 2>/dev/null; then
          rm -f "$difftmp"
          echo "defect: restore-failed: cannot write blob for '$path' in: $dir" >&2
          return 1
        fi
        [ "$dst_mode" = "100755" ] && { chmod +x "$target" 2>/dev/null || :; }
        ;;
    esac
  done < "$difftmp"
  rm -f "$difftmp"
  return 0
}

# sdlc_wip_check <goal-id> <baton-wip-value> <dir>
# Verifies the baton's recorded WIP against the repo-at-<dir>, mutating
# nothing. `none` → silent rc 0. Otherwise the value is a snapshot sha:
# object readable AND refs/sdlc-wip/<goal-id> resolves to that SAME sha →
# silent rc 0; object or ref missing/unreadable → `wip-lost` (naming the
# sha), nonzero; ref resolves to a DIFFERENT sha → `wip-drift` (naming both),
# nonzero. The goal-id is validated on the non-none path (it builds the ref
# path — same shared guard as every sibling); `none` short-circuits before
# any check, so an honest `none` is always silent regardless.
sdlc_wip_check() {
  local goal_id="${1:-}" wip="${2:-}" dir="${3:-}" ref_sha
  [ "$wip" = "none" ] && return 0

  _sdlc_validate_goal_id "$goal_id" "sdlc_wip_check" || return 1

  if ! git -C "$dir" cat-file -e "$wip" 2>/dev/null; then
    echo "defect: wip-lost: snapshot object '$wip' is unreadable (pruned/gone) in: $dir" >&2
    return 1
  fi
  ref_sha=$(git -C "$dir" rev-parse --verify --quiet "refs/sdlc-wip/$goal_id" 2>/dev/null) || true
  if [ -z "$ref_sha" ]; then
    echo "defect: wip-lost: ref refs/sdlc-wip/$goal_id is missing though object '$wip' survives, in: $dir" >&2
    return 1
  fi
  if [ "$ref_sha" != "$wip" ]; then
    echo "defect: wip-drift: baton names '$wip' but refs/sdlc-wip/$goal_id resolves to '$ref_sha', in: $dir" >&2
    return 1
  fi
  return 0
}
