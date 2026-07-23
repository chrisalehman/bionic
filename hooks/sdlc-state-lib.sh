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
# base-commit, written-at.

# Deliberately NO top-level `set -u` (FLAG 4): this file is sourced by
# other scripts (context-spend.sh today; N2-N4 later), and a sourced
# file's `set` options persist in the CALLING shell — not scoped to a
# subshell. A top-level `set -u` here would silently flip nounset on for
# every future sourcer, whether or not it opted in. The pervasive
# `${x:-}` guards throughout this file are the actual safety net; they
# do not depend on nounset being active.

BATON_REQUIRED_KEYS="goal-id plan cwd branch integration-branch last-commit sdlc-step session ledger-position next-action wip base-commit written-at"

# SDLC_SPINE_CLASSES — the CLOSED set of effect-key classes the supervision
# spine journals into a goal's ledger (D-C10 / AS-C7): rung/park/spawn/complete/
# poke. Space-separated so it feeds an awk membership set. SINGLE SOURCE — both
# sdlc_ledger_position_check (benign-trailing-growth classification) and
# sdlc_ladder_anchor (passenger-class tail = highest seq whose class is NOT in
# this set) read it, so the two can never drift. Extending the set is a recorded
# decision, never a drive-by (AS-C7).
SDLC_SPINE_CLASSES="rung park spawn complete poke"

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
#             <next-action> <wip> <base-commit> [prose]
# Serializes goal state as structured markdown with the fixed required-key
# lines, `written-at:` stamped here (UTC, now). Atomic: written to a tmp
# file in the SAME dir, then `mv` into place (single rename, never a
# partial file visible to a concurrent cold reader). Creates the goal's
# dir if absent (AS-6). Returns nonzero + a `defect:`-prefixed line on
# stderr if the goal-id is empty or the write/rename fails.
#
# Value-grammar gates (D4/D9, AS-15/AS-25 discharge) run BEFORE the
# atomic write (and before the goal dir is even created) — a rejected
# call leaves no file behind:
#   - <ledger-position> (arg 9) must be `none` or `<seq>:<digest>` with
#     seq >= 1 and digest exactly 8 lowercase hex chars
#     (`^[1-9][0-9]*:[0-9a-f]{8}$`) → else `invalid-ledger-position`.
#     Cross-file value verification (does the digest match the ledger's
#     own stored digest at that seq) is sdlc_reconcile's domain (4/2) —
#     this is a shape/grammar gate only.
#   - <wip> (arg 11) must be `none` or a full 40-hex sha
#     (`^[0-9a-f]{40}$`) → else `invalid-wip-sha`. Abbreviation becomes
#     structurally impossible for every future writer, not a convention.
#   - <base-commit> (arg 12, N3/F2) must be `none` or a full 40-hex sha
#     (`^[0-9a-f]{40}$`) → else `invalid-base-commit`. This is the goal
#     branch's FORK BASELINE — the integration tip the branch forked from —
#     the recorded anchor that lets sdlc_complete_check prove a terminal
#     goal's WORK actually landed in integration (git topology alone cannot,
#     since a stale zero-work branch is a proper ancestor of an advancing
#     shared epic tip). Same abbreviation-impossible discipline as wip.
baton_write() {
  local goal_id="${1:-}" plan="${2:-}" cwd="${3:-}" branch="${4:-}" integ="${5:-}" \
        last_commit="${6:-}" step="${7:-}" session="${8:-}" ledger_pos="${9:-}" \
        next_action="${10:-}" wip="${11:-}" base_commit="${12:-}" prose="${13:-}"
  local dir target tmp written_at

  _sdlc_validate_goal_id "$goal_id" "baton_write" || return 1

  if [ "$ledger_pos" != "none" ] && ! printf '%s' "$ledger_pos" | grep -qE '^[1-9][0-9]*:[0-9a-f]{8}$'; then
    echo "defect: invalid-ledger-position: $ledger_pos — expected <seq>:<8-hex-digest> or none" >&2
    return 1
  fi

  if [ "$wip" != "none" ] && ! printf '%s' "$wip" | grep -qE '^[0-9a-f]{40}$'; then
    echo "defect: invalid-wip-sha: $wip — wip must be none or a full 40-hex sha" >&2
    return 1
  fi

  if [ "$base_commit" != "none" ] && ! printf '%s' "$base_commit" | grep -qE '^[0-9a-f]{40}$'; then
    echo "defect: invalid-base-commit: $base_commit — base-commit must be none or a full 40-hex sha" >&2
    return 1
  fi

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
    echo "base-commit: $base_commit"
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
  local v_goal_id v_plan v_cwd v_branch v_integ v_last_commit v_step v_session v_ledger_pos v_next_action v_wip v_base_commit v_written_at

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
      base-commit)         v_base_commit="$value" ;;
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
  BATON_BASE_COMMIT="$v_base_commit"
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

# ---------- D-C11: per-goal ledger append lock ----------
# The passenger session and the supervision ladder both append to a goal's
# ledger only through ledger_append; on IDLE_STALLED the passenger is ALIVE
# while the ladder journals, so two writers can race the read-tail→append
# window and mint a colliding seq. An advisory per-goal mkdir lock serializes
# that window (poker single-instance-lock heritage: mkdir is the atomic
# winner, a dead holder's orphan is reclaimed by mtime age).

# _ledger_lock_mtime <lockdir> — epoch mtime of the lock dir, cross-platform
# (BSD `stat -f` first, GNU `stat -c` fallback); empty if unreadable.
_ledger_lock_mtime() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null; }

# _ledger_lock_acquire <goal-dir> — take <goal-dir>/.ledger.lock. Bounded wait:
# SDLC_LEDGER_LOCK_TRIES attempts (default 50), 0.1s apart. A lock dir whose
# mtime is older than SDLC_LEDGER_LOCK_STALE seconds (default 60) is a dead
# writer's orphan — reclaimed (rmdir) and retried. rc 0 on acquisition; rc 1 on
# timeout (caller emits `ledger-locked` and writes nothing — the append window
# is never entered, so the ledger stays byte-unchanged).
_ledger_lock_acquire() {
  local lockdir="${1:-}/.ledger.lock"
  local tries="${SDLC_LEDGER_LOCK_TRIES:-50}" stale="${SDLC_LEDGER_LOCK_STALE:-60}"
  local i mtime now age
  for (( i = 0; i < tries; i++ )); do
    if mkdir "$lockdir" 2>/dev/null; then return 0; fi
    mtime=$(_ledger_lock_mtime "$lockdir")
    if [ -n "$mtime" ]; then
      now=$(date +%s); age=$((now - mtime))
      if [ "$age" -ge "$stale" ]; then
        rmdir "$lockdir" 2>/dev/null || rm -rf "$lockdir" 2>/dev/null
        continue   # reclaimed a stale orphan → retry mkdir immediately (loop still bounds i)
      fi
    fi
    sleep 0.1
  done
  return 1
}

# _ledger_lock_release <goal-dir> — drop the append lock (idempotent; a missing
# lock is not an error). Always rc 0 so it never perturbs a caller's status.
_ledger_lock_release() {
  rmdir "${1:-}/.ledger.lock" 2>/dev/null || rm -rf "${1:-}/.ledger.lock" 2>/dev/null
  return 0
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
  local dir path last_line prev seq ts content digest new_line _seam_i

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

  # D-C11: serialize the read-tail→append window against a racing second writer
  # (see the append-lock helpers above). Acquired here, released on EVERY exit
  # path below. Nothing is written to the ledger before this point, so a
  # lock timeout leaves the ledger byte-unchanged.
  _ledger_lock_acquire "$dir" || { echo "defect: ledger-locked: $goal_id" >&2; return 1; }

  if [ -s "$path" ]; then
    last_line=$(tail -n 1 "$path")
    seq=$(printf '%s' "$last_line" | awk -F'\t' '{print $2}')
    case "$seq" in
      ''|*[!0-9]*) _ledger_lock_release "$dir"; echo "defect: corrupt-ledger-tail: last line's seq field is not numeric ('${seq:-<empty>}'): $path" >&2; return 1 ;;
    esac
    # The self-covering chain reads the tail's own digest as this line's
    # <prev>; a malformed tail digest would silently poison the new digest,
    # so reject it loud (same class as the numeric-seq guard) before append.
    prev=$(printf '%s' "$last_line" | awk -F'\t' '{print $3}')
    case "$prev" in
      [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) ;;
      *) _ledger_lock_release "$dir"; echo "defect: corrupt-ledger-tail: last line's digest field is not 8 hex chars ('${prev:-<empty>}'): $path" >&2; return 1 ;;
    esac
    seq=$((seq + 1))
  else
    seq=1
    prev="$LEDGER_GENESIS_MARKER"
  fi

  # Test-only deterministic-interleaving seam (D-C11 concurrency contract):
  # when SDLC_LEDGER_SEAM_HOLD names a path, block HERE — after the tail-read,
  # before the append — until that path is removed (bounded, self-releasing),
  # signalling arrival by touching SDLC_LEDGER_SEAM_READY. A suite pins the
  # read→write window open with it to drive the append race deterministically;
  # both vars are unset in production, so this is inert on every real append.
  if [ -n "${SDLC_LEDGER_SEAM_HOLD:-}" ]; then
    [ -n "${SDLC_LEDGER_SEAM_READY:-}" ] && : > "$SDLC_LEDGER_SEAM_READY"
    _seam_i=0
    while [ -e "$SDLC_LEDGER_SEAM_HOLD" ] && [ "$_seam_i" -lt 500 ]; do
      sleep 0.02; _seam_i=$((_seam_i + 1))
    done
  fi

  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  # Self-covering digest (AS-28): hash <prev> together with this line's own
  # content (all fields but the digest column) — see the canonical
  # serialization documented at LEDGER_GENESIS_MARKER.
  content=$(printf '%s\t%s\t%s\t%s\t%s' "$ts" "$seq" "$type" "$key" "$summary")
  digest=$(ledger_digest "$prev"$'\t'"$content")
  new_line="$(printf '%s\t%s\t%s\t%s\t%s\t%s' "$ts" "$seq" "$digest" "$type" "$key" "$summary")"

  if ! printf '%s\n' "$new_line" >> "$path" 2>/dev/null; then
    _ledger_lock_release "$dir"
    echo "defect: append-failed: cannot append to $path" >&2
    return 1
  fi
  _ledger_lock_release "$dir"
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
    # Platform assumption (Step-6 critic re-verify): this covers APFS (the macOS
    # default) — restore writes via shell redirection, never `git checkout`, so
    # git's own is_hfs_dotgit/is_ntfs_dotgit normalization is not the writer, and
    # APFS does not alias trailing-dot/space ('.git.', '.git ') or HFS+
    # ignorable-codepoint ('.g<ZWNJ>it') forms to '.git'. A genuine HFS+ volume
    # is the only place those could alias; extend this match if N3 ports there.
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

# ---------- D1/D4: reconciliation predicates (slice 4/2) ----------
#
# The pre-session, fail-closed reconciliation leg: deterministic predicates over
# durable state ONLY (no project code, no test suites, no builds — cron-safe and
# bounded, D1). The spine calls these BEFORE any session exists; a divergence
# never spawns, it parks. Verdict tokens print on stdout (consumers branch on
# them); every defect is one named single-class line on stderr, nonzero rc
# (ADR-001 D5). AS-N3.

# sdlc_ledger_position_check <goal-id> <position> — the AS-25 discharge: the
# baton records the ledger's own stored digest at its tail seq (`<seq>:<digest>`,
# or `none` for an empty ledger), an INDEPENDENT record the chain cannot forge.
# The self-covering chain (ADR-001 D2) is blind to a clean trailing whole-line
# deletion — ledger_verify passes a truncated ledger silently. This cross-check
# holds the baton's recorded position against the ledger's actual tail and
# catches what the chain cannot.
#
# Outcomes (goal-id validated via the shared guard first):
#   `none` + no/empty ledger        → silent rc 0 (nothing yet, consistent).
#   `none` + non-empty ledger        → `ledger-ahead: baton at none, ledger tail
#                                       <tail-seq>` (entries the baton never saw).
#   `<seq>:<digest>`: runs ledger_verify FIRST — chain defects (missing-ledger,
#     seq-gap, in-place-edit, ...) pass through under their own names. Then:
#       tail seq < baton seq → `ledger-truncated: baton at <seq>:<digest>, ledger
#                               tail <tail-seq> — trailing entries missing` (the
#                               trailing-deletion catch, AS-25).
#       stored digest at line <seq> ≠ <digest> → `ledger-truncated` naming both
#                               the baton's and the ledger's stored digest
#                               (a deeper rewrite AT the recorded position).
#       tail seq > baton seq → classify the trailing entries (D-C10): if EVERY
#                               entry past <seq> has a spine-class effect-key
#                               (rung|park|spawn|complete|poke) it is benign
#                               supervision growth → silent rc 0; otherwise
#                               `ledger-ahead: baton at <seq>, ledger tail
#                               <tail-seq>` (a passenger/garbled entry
#                               post-dates the checkpoint — fail-closed).
#       exact match (tail seq == seq AND digest matches) → silent rc 0.
# The digest check precedes the ledger-ahead check by design: a rewrite AT the
# baton's position is a stronger signal than mere growth past it.
sdlc_ledger_position_check() {
  local goal_id="${1:-}" position="${2:-}" path seq digest tail_seq stored_digest passenger
  _sdlc_validate_goal_id "$goal_id" "sdlc_ledger_position_check" || return 1
  path="$(ledger_path "$goal_id")"

  if [ "$position" = "none" ]; then
    if [ -s "$path" ]; then
      tail_seq=$(tail -n 1 "$path" | awk -F'\t' '{print $2}')
      echo "defect: ledger-ahead: baton at none, ledger tail $tail_seq" >&2
      return 1
    fi
    return 0
  fi

  # position is <seq>:<digest> (grammar already enforced by baton_write, D4).
  # Chain verify first — its defects pass through under their own names.
  ledger_verify "$goal_id" || return 1

  seq="${position%%:*}"
  digest="${position#*:}"
  # tail seq is 0 for an empty ledger (verify passed it as vacuously pristine);
  # verify guarantees a contiguous 1..N run, so tail seq == line count == N.
  if [ -s "$path" ]; then
    tail_seq=$(tail -n 1 "$path" | awk -F'\t' '{print $2}')
  else
    tail_seq=0
  fi

  if [ "$tail_seq" -lt "$seq" ]; then
    echo "defect: ledger-truncated: baton at $position, ledger tail $tail_seq — trailing entries missing" >&2
    return 1
  fi

  stored_digest=$(awk -F'\t' -v s="$seq" '$2==s {print $3; exit}' "$path")
  if [ "$stored_digest" != "$digest" ]; then
    echo "defect: ledger-truncated: baton at $position, ledger stored digest at seq $seq is $stored_digest — position rewritten" >&2
    return 1
  fi

  if [ "$tail_seq" -gt "$seq" ]; then
    # D-C10 (amendment to ADR-003 D2/AS-N12): the ladder journals rung attempts
    # into the goal's ledger, so the tail advances past the baton position on
    # every supervision event. Trailing entries are BENIGN iff EVERY one's
    # effect-key class (the token before the first ':' of field 5) is in the
    # CLOSED spine set (rung|park|spawn|complete|poke). Any other trailing
    # class — including empty or delimiter-less (garbled) — is a passenger
    # write and keeps `ledger-ahead` (fail-closed: unknown = passenger = stale
    # baton = park). ledger-truncated logic above is untouched in every case.
    passenger=$(awk -F'\t' -v s="$seq" -v spine="$SDLC_SPINE_CLASSES" '
      BEGIN { n = split(spine, a, " "); for (i = 1; i <= n; i++) sp[a[i]] = 1 }
      $2 > s {
        cls = $5; sub(/:.*/, "", cls)
        if (!(cls in sp)) { print "passenger"; exit }
      }
    ' "$path")
    if [ -n "$passenger" ]; then
      echo "defect: ledger-ahead: baton at $seq, ledger tail $tail_seq" >&2
      return 1
    fi
  fi

  return 0
}

# _sdlc_reconcile_snapshot_triage <snap-sha> <dir> — F1 worktree triage for a
# baton naming a WIP snapshot. sdlc_wip_snapshot FORCE-INCLUDES gitignored
# lifecycle artifacts (.bionic/docs) into the snapshot tree, but a plain `add -A`
# worktree tree never carries them — so the old whole-tree compare false-parked a
# faithfully-present MIXED WIP (tracked edit + force-included artifact) as drift,
# and `clean` was unreachable once anything was force-included.
#
# Fix: rebuild the worktree tree UNDER THE SNAPSHOT'S OWN BUILD RULE. Start from a
# plain `add -A` (tracked + untracked-unignored, in a TEMP index only), then
# force-add each of the snapshot's OWN delta paths (`diff-tree <snap>^ <snap>`)
# that still exists in the worktree — reproducing the snapshot's force-include
# GENERICALLY (the delta names the paths; no docs-root knowledge, project-silent).
# A whole-tree compare of that tree then both (a) sees force-included artifacts
# and (b) still catches drift on paths OUTSIDE the delta (a genuine third writer):
#   worktree tree == snapshot tree → `clean`          (WIP faithfully present)
#   worktree tree == HEAD tree      → `restore:<snap>` (clobbered back to HEAD)
#   neither                         → `worktree-drift` (genuine divergence)
#
# DEVIATION from the slice brief's prescribed per-path filesystem-read mechanism
# (logged, ASSUMPTIONS): that mechanism iterates ONLY the snapshot-delta paths, so
# it is blind to a third writer that changes a path OUTSIDE the delta (e.g. adds a
# new untracked file) — which must still verdict `worktree-drift`. Reproducing the
# snapshot build rule and comparing whole trees satisfies that requirement, reuses
# sdlc_wip_snapshot's own proven temp-index/add -f discipline, and stays generic.
#
# NUL-safe path handling (diff-tree -z, temp-file streamed per AS-10); a forged
# absolute-or-'..' delta path is refused before any force-add (containment parity
# with sdlc_wip_restore, ADR-001 D5). Temp-file/diff-tree/add/write-tree failures
# fold into the worktree-unreadable defensive class (AS-N9).
_sdlc_reconcile_snapshot_triage() {
  local snap="$1" dir="$2"
  local difftmp tmp_index path head_tree snap_tree worktree_tree

  head_tree=$(git -C "$dir" rev-parse --verify --quiet 'HEAD^{tree}' 2>/dev/null) || true
  snap_tree=$(git -C "$dir" rev-parse --verify --quiet "$snap^{tree}" 2>/dev/null) || true
  if [ -z "$head_tree" ] || [ -z "$snap_tree" ]; then
    echo "defect: worktree-unreadable: cannot resolve HEAD/snapshot tree for '$snap' in: $dir" >&2
    return 1
  fi

  difftmp=$(mktemp 2>/dev/null) || { echo "defect: worktree-unreadable: cannot mint a temp file for: $dir" >&2; return 1; }
  # NUL-safe stream to a temp file: command substitution would strip the NUL
  # delimiters, so the -z output is consumed from a file, not a variable.
  if ! git -C "$dir" diff-tree -r -z --name-only "$snap^" "$snap" > "$difftmp" 2>/dev/null; then
    rm -f "$difftmp"
    echo "defect: worktree-unreadable: diff-tree failed for snapshot '$snap' in: $dir" >&2
    return 1
  fi

  tmp_index=$(mktemp 2>/dev/null) || { rm -f "$difftmp"; echo "defect: worktree-unreadable: cannot mint a temp index for: $dir" >&2; return 1; }
  if ! GIT_INDEX_FILE="$tmp_index" git -C "$dir" read-tree HEAD 2>/dev/null \
     || ! GIT_INDEX_FILE="$tmp_index" git -C "$dir" add -A 2>/dev/null; then
    rm -f "$difftmp" "$tmp_index"
    echo "defect: worktree-unreadable: could not stage the worktree for tree comparison in: $dir" >&2
    return 1
  fi
  while IFS= read -r -d '' path; do
    # Path-containment guard (forged/corrupted-object hardening; parity with
    # sdlc_wip_restore). $path is about to be force-added from "$dir".
    case "$path" in
      /*) rm -f "$difftmp" "$tmp_index"
          echo "defect: worktree-drift: refusing absolute path '$path' from snapshot '$snap' in: $dir" >&2
          return 1 ;;
    esac
    case "/$path/" in
      */../*) rm -f "$difftmp" "$tmp_index"
              echo "defect: worktree-drift: refusing '..' traversal in path '$path' from snapshot '$snap' in: $dir" >&2
              return 1 ;;
    esac
    # Force-add only a path that STILL EXISTS in the worktree; an absent delta
    # path (a snapshot-added artifact clobbered away, or a snapshot-deleted path)
    # is left to the plain add -A staging, which already reflects its absence.
    if [ -e "$dir/$path" ]; then
      GIT_INDEX_FILE="$tmp_index" git -C "$dir" add -f -- "$path" 2>/dev/null || {
        rm -f "$difftmp" "$tmp_index"
        echo "defect: worktree-unreadable: could not force-add '$path' for tree comparison in: $dir" >&2
        return 1; }
    fi
  done < "$difftmp"
  rm -f "$difftmp"
  worktree_tree=$(GIT_INDEX_FILE="$tmp_index" git -C "$dir" write-tree 2>/dev/null) \
    || { rm -f "$tmp_index"; echo "defect: worktree-unreadable: write-tree failed for: $dir" >&2; return 1; }
  rm -f "$tmp_index"

  if [ "$worktree_tree" = "$snap_tree" ]; then printf 'clean\n'; return 0; fi
  if [ "$worktree_tree" = "$head_tree" ]; then printf 'restore:%s\n' "$snap"; return 0; fi
  echo "defect: worktree-drift: snapshot $snap — worktree matches neither HEAD nor snapshot" >&2
  return 1
}

# sdlc_reconcile <goal-id> [dir] — the D1 predicate chain. Evaluates durable
# state (baton + plan + git + ledger + WIP) in a fixed order; the FIRST failing
# predicate short-circuits to one named stderr defect + nonzero rc (the caller
# parks GATED). All predicates passing prints ONE stdout verdict token — `clean`
# (WIP already present or none) or `restore:<sha>` (a clobbered worktree the
# caller must repopulate from the snapshot) — and returns 0. `dir` (default
# $PWD) is the goal's repo; every git op is `-C "$dir"`. No project code runs.
#
# Predicate order (each loud, first refusal wins):
#   1. baton parse — malformed-baton family passes through (goal-id guarded first
#      because baton_path is built from it; baton_parse only guards the FILE's
#      own goal-id value, never this arg).
#   2. plan file readable + a parseable `current:` line → else `plan-unreadable`.
#   3. baton sdlc-step == plan current (EXACT string match) → else `baton-stale:
#      baton step <a>, plan current <b>` (AS-N4: a checkpoint boundary, so any
#      divergence means the checkpoint is untrustworthy).
#   4. baton last-commit == `git rev-parse <branch>` tip → else `baton-stale:
#      last-commit <sha> not branch tip <tip>`.
#   5. sdlc_ledger_position_check with the baton's ledger-position — pass-through.
#   6. sdlc_wip_check — wip-lost/wip-drift pass-through.
#   7. Worktree triage (D5), split by the baton's wip:
#        wip == none: no snapshot exists, so build the worktree tree via a
#          TEMPORARY index (GIT_INDEX_FILE, read-tree HEAD + add -A + write-tree
#          — the same plain build rule under which a wip-none baton was written)
#          and compare to HEAD: equal → `clean`; else → `worktree-drift:
#          unexplained work product with wip none`.
#        wip is a sha: delegate to _sdlc_reconcile_snapshot_triage (F1). A plain
#          `add -A` worktree tree could never see the gitignored lifecycle
#          artifacts that sdlc_wip_snapshot FORCE-INCLUDES, so a faithfully-present
#          mixed WIP (tracked edit + force-included artifact) false-parked as drift
#          and `clean` was unreachable once anything was force-included. The triage
#          rebuilds the worktree tree under the snapshot's OWN build rule (plain
#          add -A + a generic force-add of the snapshot's delta paths) then
#          whole-tree compares: == snapshot → `clean`; == HEAD → `restore:<sha>`;
#          neither → `worktree-drift` (genuine divergence, in- OR out-of-delta).
sdlc_reconcile() {
  local goal_id="${1:-}" dir="${2:-$PWD}"
  local baton plan_path plan_current tip
  local tmp_index head_tree worktree_tree

  # 1. baton parse (goal-id guarded first — it builds the baton path).
  _sdlc_validate_goal_id "$goal_id" "sdlc_reconcile" || return 1
  baton="$(baton_path "$goal_id")"
  baton_parse "$baton" || return 1

  # 2. plan readable + a parseable current: line.
  plan_path="$BATON_PLAN"
  if [ ! -f "$plan_path" ]; then
    echo "defect: plan-unreadable: $plan_path" >&2
    return 1
  fi
  plan_current=$(grep -E '^current:' "$plan_path" 2>/dev/null | head -1 | sed -E 's/^current:[[:space:]]*//; s/[[:space:]]+$//')
  if [ -z "$plan_current" ]; then
    echo "defect: plan-unreadable: $plan_path" >&2
    return 1
  fi

  # 3. baton step vs plan current (exact match — AS-N4).
  if [ "$BATON_SDLC_STEP" != "$plan_current" ]; then
    echo "defect: baton-stale: baton step $BATON_SDLC_STEP, plan current $plan_current" >&2
    return 1
  fi

  # 4. baton last-commit vs recorded-branch tip.
  tip=$(git -C "$dir" rev-parse "$BATON_BRANCH" 2>/dev/null)
  if [ "$tip" != "$BATON_LAST_COMMIT" ]; then
    echo "defect: baton-stale: last-commit $BATON_LAST_COMMIT not branch tip $tip" >&2
    return 1
  fi

  # 5. ledger-position cross-check (AS-25) — pass-through.
  sdlc_ledger_position_check "$goal_id" "$BATON_LEDGER_POSITION" || return 1

  # 6. WIP reconciliation — wip-lost/wip-drift pass-through.
  sdlc_wip_check "$goal_id" "$BATON_WIP" "$dir" || return 1

  # 7. Worktree triage (D5).
  head_tree=$(git -C "$dir" rev-parse --verify --quiet 'HEAD^{tree}' 2>/dev/null) || true
  if [ -z "$head_tree" ]; then
    echo "defect: worktree-unreadable: no HEAD tree to compare against in: $dir" >&2
    return 1
  fi

  if [ "$BATON_WIP" = "none" ]; then
    # No snapshot exists: any tracked/untracked-unignored change is unexplained.
    # Build the worktree tree with a plain `add -A` — the SAME build rule under
    # which a wip-none baton was written (gitignored artifacts excluded) — in a
    # TEMP index only, and compare to HEAD.
    tmp_index=$(mktemp 2>/dev/null) || { echo "defect: worktree-unreadable: cannot mint a temp index for: $dir" >&2; return 1; }
    if ! GIT_INDEX_FILE="$tmp_index" git -C "$dir" read-tree HEAD 2>/dev/null \
       || ! GIT_INDEX_FILE="$tmp_index" git -C "$dir" add -A 2>/dev/null; then
      rm -f "$tmp_index"
      echo "defect: worktree-unreadable: could not stage the worktree for tree comparison in: $dir" >&2
      return 1
    fi
    worktree_tree=$(GIT_INDEX_FILE="$tmp_index" git -C "$dir" write-tree 2>/dev/null) \
      || { rm -f "$tmp_index"; echo "defect: worktree-unreadable: write-tree failed for: $dir" >&2; return 1; }
    rm -f "$tmp_index"
    if [ "$worktree_tree" = "$head_tree" ]; then
      printf 'clean\n'
      return 0
    fi
    echo "defect: worktree-drift: unexplained work product with wip none" >&2
    return 1
  fi

  # wip is a snapshot sha; sdlc_wip_check (predicate 6) already proved the object
  # readable, so <sha>^ resolves. A whole-tree compare cannot see force-included
  # gitignored artifacts (F1) — delegate to the per-path triage, which prints the
  # verdict token (`clean` / `restore:<sha>`) or its own worktree-drift defect.
  _sdlc_reconcile_snapshot_triage "$BATON_WIP" "$dir"
}

# ---------- D2: completion latch (slice 4/3) ----------
#
# sdlc_complete_check <goal-id> [dir] — verifies a COMPLETE claim against git
# reality, structurally only (no project code, no test-suite execution: the
# lifecycle's own Step-5 gate already evidenced suite-green in the plan these
# predicates read). `dir` (default $PWD) is the goal's repo; both branches are
# resolved via `git rev-parse` in that dir.
#
# rc semantics (the three named outcomes, D2):
#   0 — complete-verified: every predicate passed; the completion latch
#       (`complete:<goal-id>`, exactly-once via sdlc_effect_run) is journaled.
#   1 — not-complete (BENIGN): the plan is not yet terminal. One stderr line,
#       deliberately NOT `defect:`-prefixed — this is the ordinary in-flight
#       case, not a fault, and must never be mistaken for one downstream.
#   2 — false-complete-or-defect (LOUD): either the plan claims terminal but a
#       predicate refutes it (`defect: false-complete: ...`), or an earlier
#       structural guard/parse/chain failed and its own named defect passes
#       through under this same rc class (goal-id guard, baton_parse,
#       ledger_verify).
#
# Predicate order (first refusal wins):
#   1. goal-id via the shared guard, then baton_parse — both classes fold into
#      rc 2, the defect line is whichever primitive printed it.
#   2. Plan `current:` (read from BATON_PLAN, same grep+sed shape as
#      sdlc_reconcile) != "10" → benign not-complete, rc 1. This is the ONLY
#      rc-1 exit; every later exit in this function is rc 2.
#   3. current == "10": sound merged-ness (F2, critic re-attack). Resolve
#      BATON_BRANCH and BATON_INTEGRATION_BRANCH to their tips via `git
#      rev-parse`. A terminal goal is complete iff BOTH hold, checked in order:
#        (a) WORK HAPPENED — base-commit is the recorded fork baseline. If it is
#            `none`, merged work is structurally unprovable → fail CLOSED
#            (`defect: false-complete: current 10 but no base-commit recorded to
#            prove merged work`). If `<branch-tip>` string-equals the base-commit,
#            the branch committed nothing since forking (a stale zero-work branch,
#            even one that is a proper ancestor of an advancing shared integration
#            tip — the epic topology) → `defect: false-complete: current 10 but
#            <branch> did no work since base-commit <sha> (stale zero-work
#            branch)`.
#        (b) WORK IS IN INTEGRATION — `git merge-base --is-ancestor <branch-tip>
#            <integration-tip>`; refusal → `defect: false-complete: current 10
#            but <branch> not merged into <integration-branch>`.
#      Why not tip-equality / is-ancestor alone: git topology cannot distinguish
#      landed work from a stale pointer the integration tip passed for UNRELATED
#      reasons. Tip-equality also over-corrects — it wrongly refuses a genuine
#      fast-forward merge (tips equal but real work merged). The fork baseline is
#      the only anchor that answers both directions.
#   4. BATON_WIP != "none" → `defect: false-complete: terminal plan with
#      stranded wip <sha>` (a terminal plan must have no work product left
#      shadowed — that work was either landed or abandoned, never stranded).
#   5. `ledger_verify` — chain defects pass through under their own names.
#   6. All predicates passed → journal the latch via `sdlc_effect_run
#      <goal-id> "complete:<goal-id>" "completion verified structurally" --
#      true`; print `complete-verified` on stdout, rc 0. sdlc_effect_run's own
#      exactly-once guard makes a second invocation idempotent for free: the
#      effect is already `applied`, so no command runs and no duplicate
#      ledger line lands — this function does not need its own memo.
sdlc_complete_check() {
  local goal_id="${1:-}" dir="${2:-$PWD}"
  local baton plan_path plan_current branch_tip integ_tip

  _sdlc_validate_goal_id "$goal_id" "sdlc_complete_check" || return 2
  baton="$(baton_path "$goal_id")"
  baton_parse "$baton" || return 2

  plan_path="$BATON_PLAN"
  plan_current=$(grep -E '^current:' "$plan_path" 2>/dev/null | head -1 | sed -E 's/^current:[[:space:]]*//; s/[[:space:]]+$//')

  if [ "$plan_current" != "10" ]; then
    echo "not-complete: plan current $plan_current" >&2
    return 1
  fi

  branch_tip=$(git -C "$dir" rev-parse "$BATON_BRANCH" 2>/dev/null)
  integ_tip=$(git -C "$dir" rev-parse "$BATON_INTEGRATION_BRANCH" 2>/dev/null)

  # Sound merged-ness (F2, critic re-attack). Git topology ALONE cannot tell
  # "the goal branch's WORK is in integration" from "the goal branch is a stale
  # pointer at an old commit that integration happens to have passed" — both the
  # is-ancestor check and tip-equality fail on the epic topology, where multiple
  # waves merge into a shared integration branch and a zero-work goal branch is a
  # proper ancestor of the advancing tip. The recorded FORK BASELINE
  # (base-commit) is what closes the gap. A terminal goal is complete iff BOTH:
  #   (1) WORK HAPPENED — the branch committed at least once since its baseline
  #       (branch_tip != base-commit). A base-commit of `none` cannot prove work
  #       structurally, so a terminal claim without one fails CLOSED.
  #   (2) WORK IS IN INTEGRATION — the branch tip (hence every commit it added
  #       since the baseline) is reachable from the integration tip.
  if [ "$BATON_BASE_COMMIT" = "none" ]; then
    echo "defect: false-complete: current 10 but no base-commit recorded to prove merged work" >&2
    return 2
  fi
  if [ "$branch_tip" = "$BATON_BASE_COMMIT" ]; then
    echo "defect: false-complete: current 10 but $BATON_BRANCH did no work since base-commit $BATON_BASE_COMMIT (stale zero-work branch)" >&2
    return 2
  fi
  if ! git -C "$dir" merge-base --is-ancestor "$branch_tip" "$integ_tip" 2>/dev/null; then
    echo "defect: false-complete: current 10 but $BATON_BRANCH not merged into $BATON_INTEGRATION_BRANCH" >&2
    return 2
  fi

  if [ "$BATON_WIP" != "none" ]; then
    echo "defect: false-complete: terminal plan with stranded wip $BATON_WIP" >&2
    return 2
  fi

  ledger_verify "$goal_id" || return 2

  sdlc_effect_run "$goal_id" "complete:$goal_id" "completion verified structurally" -- true || return 2
  printf 'complete-verified\n'
  return 0
}

# ---------- D7/AS-N10: gate park (slice 4/4) ----------
#
# sdlc_gate_park <goal-id> <plan-path> <defect> <detail> — appends a
# `## Wake Note` block (User Decision Protocol shape) to the caller-supplied
# plan file, wrapped in `sdlc_effect_run` under key `park:<goal-id>:<defect>`
# so a replay of the same defect cannot double-append (idempotent by key).
#
# AS-N10 (deviation from spec D7's original 3-arg draft, ruling recorded in
# the wave plan): plan-path is a CALLER arg, never derived via baton_parse.
# A malformed or missing baton is itself a park CAUSE (sdlc_reconcile's first
# predicate can fail before BATON_PLAN exists) — the park primitive must not
# depend on baton derivation succeeding. Spine callers (the spawn pipeline,
# a future poker) know the plan path independently of the baton. The shared
# goal-id guard still applies (AS-26) — only plan-path provenance is exempt.
#
# Presence-probe BELT (AS-N6, first-park-wins): the appender itself refuses
# a second `## Wake Note` heading regardless of which defect key drove it.
# A DIFFERENT defect arriving while already parked gets its OWN effect key
# (`park:<goal-id>:<other-defect>`), so sdlc_effect_run still journals its
# decision/effect lines for that key (a distinct record that this defect was
# seen and handled) — but the appender no-ops the actual file write and
# returns 0: the goal IS parked, which is the caller's desired postcondition,
# so "rc 0, one stderr note, no second block" beats a refusal that would
# leave the caller unsure whether it's safe to stop. Documented choice, not
# the only valid one.
#
# Plan-file-missing/unwritable → `defect: park-failed: <plan-path> — park
# could not land durable state`, nonzero, NO file created. Composes with
# sdlc_effect_run's own contract without special-casing: the decision line
# was already journaled (unapplied → decision-then-run), the appender then
# fails, so no effect line lands — a replay of the SAME defect key correctly
# reads back `indeterminate` (sdlc_effect_state), never a false `applied`.
_sdlc_gate_park_append() {
  local plan_path="$1" defect="$2" detail="$3"
  if [ ! -f "$plan_path" ]; then
    echo "defect: park-failed: $plan_path — park could not land durable state" >&2
    return 1
  fi
  if grep -q '^## Wake Note$' "$plan_path" 2>/dev/null; then
    echo "park-skipped: wake note already present — first park wins" >&2
    return 0
  fi
  # The append is wrapped in a SUBSHELL so a failed-open redirect (an unwritable
  # plan) propagates as a nonzero exit — the bare `if ! { …; } >> file` form
  # silently evaluates to 0 when the redirect cannot open the file (bash
  # compound-redirect quirk), which would report a park that never landed as
  # success. The subshell also confines the redirect's own error to the outer
  # `2>/dev/null`, so a failed park is loud through THIS function's named defect
  # only, never a stray shell message.
  if ! ( {
    printf '\n## Wake Note\n\n'
    printf 'GATED by rollover spine: %s\n' "$defect"
    printf '%s\n\n' "$detail"
    printf '**Options:**\n'
    printf '1. Resolve the named divergence and delete this note to re-arm.\n'
    printf '2. Close the goal manually (plan current: 10 + merge) if it is in fact done.\n\n'
    printf '**Why it matters:** the spine refuses to spawn a successor while this note stands (fail-closed).\n'
  } >> "$plan_path" ) 2>/dev/null; then
    echo "defect: park-failed: $plan_path — park could not land durable state" >&2
    return 1
  fi
  return 0
}

sdlc_gate_park() {
  local goal_id="${1:-}" plan_path="${2:-}" defect="${3:-}" detail="${4:-}"
  _sdlc_validate_goal_id "$goal_id" "sdlc_gate_park" || return 1
  [ -n "$defect" ] || { echo "defect: missing-defect: sdlc_gate_park requires a non-empty defect" >&2; return 1; }

  sdlc_effect_run "$goal_id" "park:$goal_id:$defect" "$detail" -- \
    _sdlc_gate_park_append "$plan_path" "$defect" "$detail"
}

# ---------- D3/D6/D8: successor-spawn pipeline (slice 4/5) ----------
#
# The rollover vehicle: a refuse-first pipeline that a dumb cron drives against
# a goal's durable state and, only when every gate clears, launches ONE headless
# successor to pick the goal back up. Every stage is loud and the FIRST refusal
# wins; nothing here kills or signals any session (ADR-002 no-force). The ledger
# IS the spawn record (AS-N5) — no separate file.

# sdlc_successor_pointer_prompt <goal-id> <plan-path> <baton-path> <next-action>
# Prints the pointer prompt handed to the successor, project-silent and in ONE
# place so the T3 live walk and any future poker (N4) reuse a single source.
# The text is the wave plan's block verbatim (hard line breaks preserved — the
# block is the contract; a reflow would diverge the two consumers from the plan).
sdlc_successor_pointer_prompt() {
  local goal_id="${1:-}" plan="${2:-}" baton="${3:-}" next_action="${4:-}"
  cat <<EOF
Rollover pickup for goal $goal_id. The rollover spine verified
state clean; do not re-derive reconciliation, do not override
any Wake Note. Read the plan at $plan and the baton at
$baton; resume per the canonical-sdlc session-resume
protocol. Baton next-action is the literal resume point:
$next_action
EOF
}

# _sdlc_spawn_launch <cwd> <sid> <prompt> — the DEFAULT spawn executor (used
# only when SDLC_SPAWN_CMD is unset — i.e. the real T3 path, never fixtures).
# Fires the headless successor in the BACKGROUND from the goal's cwd and returns
# on successful LAUNCH: spawn is fire-and-observe (plan D8) — the spine does not
# block on the successor's whole turn, so sdlc_effect_run reads a 0 here as "a
# successor WAS launched", not "its turn completed". The `( cmd & )` idiom
# detaches the child (reparented, survives this shell) with rc 0 for the launch;
# a cd failure exits nonzero so the intent stands and no effect line lands.
#
# Permission posture (AS-N14, Chris ruling — "strong workers, strong walls"):
# the successor launches FULLY CAPABLE by default; safety lives in the spine's
# structural walls (pre-spawn reconciliation, fail-closed parks, exactly-once
# effects), never in worker weakness. SDLC_SPAWN_PERMISSIONS is the posture
# seam: UNSET → the default full-capability flag; SET (non-empty) → its
# contents word-split verbatim replace the permission args; SET EMPTY → no
# permission args at all (weak posture, the caller's explicit choice). The lib
# has no `set -u`, so `${VAR+set}` (not `${VAR:-}`) is the only form that
# tells "unset" apart from "set to empty" — that distinction is the whole
# point of this seam.
_sdlc_spawn_launch() {
  local cwd="$1" sid="$2" prompt="$3"
  local perm_args
  if [ "${SDLC_SPAWN_PERMISSIONS+set}" = "set" ]; then
    # shellcheck disable=SC2206  # intentional word-split, AS-N14 seam contract
    perm_args=( $SDLC_SPAWN_PERMISSIONS )
  else
    perm_args=( --dangerously-skip-permissions )
  fi
  ( cd "$cwd" 2>/dev/null || exit 1
    claude -p "$prompt" --session-id "$sid" "${perm_args[@]}" >/dev/null 2>&1 & )
}

# _sdlc_spawn_defect_class <stderr-line> — the defect class token (text between
# `defect: ` and the next `:`) from a primitive's one-line stderr, for keying a
# park. Empty when the line is not `defect:`-shaped.
_sdlc_spawn_defect_class() {
  printf '%s' "$1" | sed -n 's/^defect: \([^:]*\):.*/\1/p' | head -1
}

# sdlc_successor_spawn <goal-id> [dir]  (dir default $PWD, the goal's repo)
# Env seams (AS-N2, fixtures only; T3 runs both defaults real):
#   SDLC_SPAWN_CMD    — the complete spawn command, word-split on IFS (default:
#                       _sdlc_spawn_launch, the real backgrounded `claude -p`).
#                       When set, the spine injects nothing: a fixture bakes its
#                       own counter into the stub. A stub runs SYNCHRONOUSLY, so
#                       double-drive launch-counting is race-free; the real
#                       default backgrounds itself (fire-and-observe).
#   SDLC_REGISTRY_CMD — command emitting the live-session registry as JSON,
#                       word-split on IFS (default: `claude agents --json`).
#
# Pipeline (each stage loud, first refusal wins):
#   1. goal-id guard + baton_parse — parse defects pass through, nonzero.
#   2. plan carries `## Wake Note` → `goal-gated` (stderr), nonzero, NO park
#      (already parked), no spawn.
#   3. complete latch: sdlc_effect_state `complete:<gid>` applied → `goal-complete`
#      (stdout), rc 0. Else sdlc_complete_check — rc 0 (latch just landed) →
#      `goal-complete`, rc 0; rc 2 → park the check's defect class, nonzero, no
#      spawn; rc 1 (benign not-complete) → proceed.
#   4. single-writer: the newest `spawn:` EFFECT line's recorded sid (summary
#      `sid=<uuid>`) looked up BY ID in SDLC_REGISTRY_CMD's output (a literal
#      grep — no jq dependency). Found → `goal-owned` (stderr), nonzero, no park
#      (a healthy live owner). Registry fails/empty → conservative `goal-owned`
#      refusal (transient; cron re-drives — fail-closed, no park spam). Sid
#      absent, or no prior spawn effect line → proceed. Decision-only spawn keys
#      are deliberately NOT matched here — an intent that never became an effect
#      is the crash window, resolved at stage 6, not a live owner.
#   5. spawn-key state for `spawn:<gid>:<written-at>` (evaluated BEFORE reconcile,
#      AS-N12): applied (same baton replayed) → `spawn-skipped` (stdout), rc 0,
#      no launch; indeterminate (a journaled spawn intent with no effect — the
#      crash window) → sdlc_effect_run refuses `effect-indeterminate` (no
#      --replay-safe, command not run) → park that class, nonzero; unapplied →
#      proceed. This precedes reconcile because the spine's OWN spawn journal
#      entries advance the ledger past the baton's ledger-position — a re-drive's
#      reconcile would otherwise trip `ledger-ahead` on the spine's bookkeeping.
#   6. sdlc_reconcile → nonzero: park its defect class, nonzero, no spawn.
#      Verdict `restore:<sha>` → sdlc_wip_restore (failure → park `restore-failed`);
#      `clean` → proceed.
#   7. spawn: mint a fresh lowercased-uuid sid; sdlc_effect_run under the spawn
#      key launches at most once. The effect summary carries `sid=<sid> pid=na
#      cwd=<cwd>` (pid=na by design — the durable record does not track a live
#      pid; liveness is the registry's answer at stage 4, and a pid is not
#      replay-stable across a cron re-drive).
#   8. success → print the fresh sid on stdout (callers/N4 need it), rc 0.
sdlc_successor_spawn() {
  local goal_id="${1:-}" dir="${2:-$PWD}"
  local baton plan_path lpath
  local cc_errf cc_rc cc_err cclass
  local spawn_line prior_sid reg_out reg_rc
  local rec_errf rec_out rec_rc rec_err rclass verdict rsha rst_errf rst_err
  local sid prompt spawn_key spawn_errf spawn_rc spawn_err sclass

  # 1. goal-id guard (builds the baton path) then baton parse.
  _sdlc_validate_goal_id "$goal_id" "sdlc_successor_spawn" || return 1
  baton="$(baton_path "$goal_id")"
  baton_parse "$baton" || return 1
  plan_path="$BATON_PLAN"
  lpath="$(ledger_path "$goal_id")"

  # 2. Wake Note standing → already parked; refuse without re-parking.
  if [ -f "$plan_path" ] && grep -q '^## Wake Note$' "$plan_path" 2>/dev/null; then
    echo "goal-gated: wake note standing in $plan_path" >&2
    return 1
  fi

  # 3. completion. An applied latch short-circuits the git predicates.
  if [ "$(sdlc_effect_state "$goal_id" "complete:$goal_id")" = "applied" ]; then
    echo "goal-complete"
    return 0
  fi
  cc_errf="$(mktemp)"
  sdlc_complete_check "$goal_id" "$dir" >/dev/null 2>"$cc_errf"; cc_rc=$?
  cc_err="$(cat "$cc_errf")"; rm -f "$cc_errf"
  case "$cc_rc" in
    0) echo "goal-complete"; return 0 ;;
    2) cclass="$(_sdlc_spawn_defect_class "$cc_err")"
       [ -n "$cclass" ] || cclass="false-complete"
       sdlc_gate_park "$goal_id" "$plan_path" "$cclass" "$cc_err"
       return 1 ;;
    *) : ;;  # rc 1 benign not-complete → proceed
  esac

  # 4. single-writer — is a prior spawned session still live?
  spawn_line=""
  [ -f "$lpath" ] && spawn_line="$(awk -F'\t' '$4=="effect" && $5 ~ /^spawn:/ {l=$0} END{print l}' "$lpath")"
  if [ -n "$spawn_line" ]; then
    prior_sid="$(printf '%s' "$spawn_line" | awk -F'\t' '{print $6}' | sed -n 's/.*sid=\([0-9a-f-]*\).*/\1/p')"
    if [ -n "$prior_sid" ]; then
      reg_out="$(${SDLC_REGISTRY_CMD:-claude agents --json} 2>/dev/null)"; reg_rc=$?
      if [ "$reg_rc" -ne 0 ] || [ -z "$reg_out" ]; then
        echo "goal-owned: session $prior_sid live — registry unavailable, refusing conservatively" >&2
        return 1
      fi
      if printf '%s' "$reg_out" | grep -qF "$prior_sid"; then
        echo "goal-owned: session $prior_sid live" >&2
        return 1
      fi
      # sid absent from the registry → the owner is dead → proceed.
    fi
  fi

  # 5. spawn-key state — have we already acted on THIS baton? Evaluated HERE,
  #    with the single-writer gate and BEFORE reconcile (AS-N12): the spine's
  #    own spawn journal entries (decision+effect) advance the ledger past the
  #    baton's recorded ledger-position, so a re-drive's sdlc_reconcile would
  #    report `ledger-ahead` on the spine's own bookkeeping. The exactly-once
  #    states must short-circuit before reconcile reads the ledger.
  #    applied  → this baton was already serviced → `spawn-skipped`, rc 0.
  #    indet.   → a journaled spawn intent never became an effect (crash window):
  #               sdlc_effect_run refuses `effect-indeterminate` (no
  #               --replay-safe, command not run) → park that class.
  #    unapplied → fresh baton → proceed to reconcile + launch.
  spawn_key="spawn:$goal_id:$BATON_WRITTEN_AT"
  case "$(sdlc_effect_state "$goal_id" "$spawn_key")" in
    applied)
      echo "spawn-skipped: already spawned for baton $BATON_WRITTEN_AT"
      return 0 ;;
    indeterminate)
      spawn_errf="$(mktemp)"
      sdlc_effect_run "$goal_id" "$spawn_key" "sid=pending pid=na cwd=$BATON_CWD" -- true 2>"$spawn_errf"
      spawn_err="$(cat "$spawn_errf")"; rm -f "$spawn_errf"
      sclass="$(_sdlc_spawn_defect_class "$spawn_err")"
      [ -n "$sclass" ] || sclass="effect-indeterminate"
      sdlc_gate_park "$goal_id" "$plan_path" "$sclass" "$spawn_err"
      return 1 ;;
    *) : ;;  # unapplied → proceed
  esac

  # 6. reconcile (fresh baton only — the ledger is consistent with it here).
  rec_errf="$(mktemp)"
  rec_out="$(sdlc_reconcile "$goal_id" "$dir" 2>"$rec_errf")"; rec_rc=$?
  rec_err="$(cat "$rec_errf")"; rm -f "$rec_errf"
  if [ "$rec_rc" -ne 0 ]; then
    rclass="$(_sdlc_spawn_defect_class "$rec_err")"
    [ -n "$rclass" ] || rclass="reconcile-defect"
    sdlc_gate_park "$goal_id" "$plan_path" "$rclass" "$rec_err"
    return 1
  fi
  verdict="$rec_out"
  case "$verdict" in
    clean) : ;;
    restore:*)
      rsha="${verdict#restore:}"
      rst_errf="$(mktemp)"
      if ! sdlc_wip_restore "$goal_id" "$rsha" "$dir" 2>"$rst_errf"; then
        rst_err="$(cat "$rst_errf")"; rm -f "$rst_errf"
        sdlc_gate_park "$goal_id" "$plan_path" "restore-failed" "wip restore of $rsha failed: $rst_err"
        return 1
      fi
      rm -f "$rst_errf" ;;
    *) echo "goal-gated: unexpected reconcile verdict '$verdict'" >&2
       return 1 ;;
  esac

  # 7. spawn (unapplied key, state clean) — launch at most once.
  sid="$(uuidgen | tr '[:upper:]' '[:lower:]')"
  prompt="$(sdlc_successor_pointer_prompt "$goal_id" "$plan_path" "$baton" "$BATON_NEXT_ACTION")"
  spawn_errf="$(mktemp)"
  if [ -n "${SDLC_SPAWN_CMD:-}" ]; then
    sdlc_effect_run "$goal_id" "$spawn_key" "sid=$sid pid=na cwd=$BATON_CWD" -- $SDLC_SPAWN_CMD 2>"$spawn_errf"
    spawn_rc=$?
  else
    sdlc_effect_run "$goal_id" "$spawn_key" "sid=$sid pid=na cwd=$BATON_CWD" -- \
      _sdlc_spawn_launch "$BATON_CWD" "$sid" "$prompt" 2>"$spawn_errf"
    spawn_rc=$?
  fi
  spawn_err="$(cat "$spawn_errf")"; rm -f "$spawn_errf"
  if [ "$spawn_rc" -ne 0 ]; then
    # a launch/journal failure — park the named class so a human decides.
    sclass="$(_sdlc_spawn_defect_class "$spawn_err")"
    [ -n "$sclass" ] || sclass="spawn-failed"
    sdlc_gate_park "$goal_id" "$plan_path" "$sclass" "$spawn_err"
    return 1
  fi

  # 8. success — the fresh sid is the caller/N4 handle.
  echo "$sid"
  return 0
}

# ---------- D-C1/D-C2/D-C4: revival ladder derivation (slice 4/3) ----------
#
# sdlc_ladder_next <goal-id> <classification> <anchor> [dir] — the PURE ladder
# oracle the poker dispatcher (4/4) consults each poll. Given a goal's
# classification and the current DURABLE-PROGRESS anchor (8-hex digest from
# sdlc_ladder_anchor — D-C2 amendment), it DERIVES the single next rung action
# by reading the goal's ledger (rung attempts already journaled) and, at the
# rollover step, the current baton generation. It writes NOTHING, reads no clock
# and no world state beyond the <anchor> arg, and makes no registry call:
# the poker owns EXECUTING the returned action (each through sdlc_effect_run);
# this function only decides WHICH one.
#
# Contract (D-C2 rung effect-key grammar; D-C1 rung order; D-C4 rollover):
#   stdout exactly one token, rc 0:
#     poke:<n> | re-prompt:<n> | observe:<n> | rollover | human | none
#   Invalid args (goal-id, non-epoch anchor, garbled cap) or a corrupt ledger →
#   one `defect: <class>: <detail>` line on stderr, rc 1 (caller fail-closed
#   skips + audits). A journaled rung DECISION with no matching EFFECT under the
#   current anchor (the crash window) → `defect: effect-indeterminate` (caller
#   parks).
#
# Derivation:
#   * An attempt = one COMPLETED (effect-line) rung action under the key
#     `rung:<goal-id>:<rung-name>:<anchor>:<n>` (n from 1). Attempts are counted
#     per rung for the CURRENT anchor ONLY; entries under an older anchor are
#     dead history (durable progress happened — a fresh episode starts at n=1
#     for the new digest) and are neither reused nor garbage-collected. Because
#     the anchor keys off durable progress, a poke's own resume turn (which only
#     moves the transcript) does NOT change it — the ladder cannot reset the
#     episode it is judged by (Step-6 critic F1 fix).
#   * Caps: SDLC_RUNG_CAP (default 2 — poke and re-prompt each) and
#     SDLC_OBSERVE_CAP (default 3). A rung with < cap completed attempts yields
#     `<rung>:<count+1>`; at cap it is exhausted and the next rung is consulted.
#   * Rung order by classification (D-C1):
#       DEAD          → poke → re-prompt → rollover → human
#       IDLE_STALLED  → poke → re-prompt → human   (alive: the single-writer
#                       constitution forbids rollover — STRUCTURALLY unreachable)
#       WEDGED        → observe → human            (alive + busy: no safe
#                       automated action, only bounded observation, no kill verb)
#       anything else → none                        (no ladder)
#   * Rollover (D-C4): read the CURRENT baton generation; the spawn key
#     `spawn:<goal-id>:<baton-written-at>` state via sdlc_effect_state:
#       unapplied     → rollover (the spine will spawn a successor)
#       applied       → human    (spawn-skipped steady state, AS-N13 — the ladder
#                                 NEVER re-keys a spawn around exactly-once)
#       indeterminate → defect effect-indeterminate (caller parks)
#     An unparseable baton passes its own defect through (caller fail-closed).
#
# [dir] is accepted for dispatcher-signature parity but the derivation is
# repo-INDEPENDENT: every input (baton, ledger, effect state) derives from
# SDLC_STATE_DIR + goal-id, never from a working tree.

# sdlc_ladder_anchor <goal-id> <plan-path> <cwd> [dir] — mint the episode's
# DURABLE-PROGRESS DIGEST (D-C2 anchor amendment, Step-6 critic F1): an 8-hex
# token over the tuple of the goal's DURABLE progress, so the anchor moves iff
# real progress happened and is IMMUNE to a poke's own resume turn (which only
# advances the transcript). Transcript mtime is OUT of escalation state entirely
# — it stays a staleness-classification signal only.
#
# Tuple (order fixed here so the digest is reproducible cold, D-C7 / AC-C3):
#   1. plan `current:` value      — read from <plan-path> (the goal's REGISTRATION
#                                    plan, trusted provenance; same grep+sed shape
#                                    as reconcile/complete-check).
#   2. goal branch tip sha        — `git -C <dir> rev-parse <baton branch>`.
#   3. passenger-class ledger tail — highest ledger seq whose effect-key class is
#                                    NOT in SDLC_SPINE_CLASSES (0 when none); the
#                                    ladder's OWN spine-class journaling never
#                                    moves it, so the anchor cannot reset itself.
#   4. baton `written-at`         — the current baton generation stamp.
#
# Pure (no writes), deterministic, cold-readable. rc 0 + 8-hex on stdout; on any
# unreadable input a loud named `defect:` on stderr + rc 1 (caller fail-closed
# skips). Reads: baton (BATON_BRANCH/BATON_WRITTEN_AT), plan file, git repo,
# goal ledger. [dir] overrides the git repo for tests; defaults to <cwd>.
sdlc_ladder_anchor() {
  local goal_id="${1:-}" plan_path="${2:-}" cwd="${3:-}" dir="${4:-${3:-}}"
  local baton plan_current branch_tip lpath passenger_tail

  _sdlc_validate_goal_id "$goal_id" "sdlc_ladder_anchor" || return 1
  ledger_digest_tool_probe || return 1

  # 1. baton (branch + written-at) — its own defect passes through, fail-closed.
  baton="$(baton_path "$goal_id")"
  baton_parse "$baton" || return 1

  # 2. plan readable + a parseable current: line (mirrors reconcile's shape).
  if [ ! -f "$plan_path" ]; then
    echo "defect: plan-unreadable: $plan_path" >&2
    return 1
  fi
  plan_current=$(grep -E '^current:' "$plan_path" 2>/dev/null | head -1 | sed -E 's/^current:[[:space:]]*//; s/[[:space:]]+$//')
  if [ -z "$plan_current" ]; then
    echo "defect: plan-unreadable: $plan_path" >&2
    return 1
  fi

  # 3. goal branch tip — an unreadable repo/branch is fail-closed (the durable
  #    tuple cannot be completed without it). `--verify --quiet ... ^{commit}`
  #    (never plain rev-parse) so an unresolvable ref yields EMPTY output at a
  #    nonzero rc instead of git's literal-ref-echoed-to-stdout quirk (rc 128,
  #    ref name on stdout) — the `-z` guard below would otherwise miss that
  #    literal and digest it (F1b, Step-6 critic-fix-2). The 40-hex check is a
  #    second, independent gate on the same fail-closed contract.
  branch_tip=$(git -C "$dir" rev-parse --verify --quiet "${BATON_BRANCH}^{commit}" 2>/dev/null)
  if ! printf '%s' "$branch_tip" | grep -qE '^[0-9a-f]{40}$'; then
    echo "defect: cwd-unreadable: cannot resolve branch tip for '$BATON_BRANCH' in: $dir" >&2
    return 1
  fi

  # 4. passenger-class ledger tail. A non-empty ledger must chain-verify first
  #    (corruption is fail-closed, its defect passes through); a missing/empty
  #    ledger is a fresh episode (tail 0), never a defect — mirrors the effect
  #    primitives' "not yet". Spine-class entries (SDLC_SPINE_CLASSES) never move
  #    the tail, so the ladder's own journaling cannot reset the anchor.
  lpath="$(ledger_path "$goal_id")"
  if [ -s "$lpath" ]; then
    ledger_verify "$goal_id" || return 1
    passenger_tail=$(awk -F'\t' -v spine="$SDLC_SPINE_CLASSES" '
      BEGIN { n = split(spine, a, " "); for (i = 1; i <= n; i++) sp[a[i]] = 1; max = 0 }
      { cls = $5; sub(/:.*/, "", cls); if (!(cls in sp) && $2 + 0 > max) max = $2 + 0 }
      END { print max + 0 }
    ' "$lpath")
  else
    passenger_tail=0
  fi

  # Digest the tuple (newline-joined; components are single logical fields with
  # no embedded newline) → 8-hex, the same truncation the ledger chain uses.
  ledger_digest "$(printf '%s\n%s\n%s\n%s' "$plan_current" "$branch_tip" "$passenger_tail" "$BATON_WRITTEN_AT")"
}

# _sdlc_rung_key <goal-id> <rung-name> <anchor> <n> — mint the canonical rung
# effect-key `rung:<goal-id>:<rung-name>:<anchor>:<n>` (D-C2), in ONE place so
# the derivation and any future consumer can never drift the grammar. rung-name
# ∈ poke|re-prompt|observe; anchor is the 8-hex DURABLE-PROGRESS DIGEST minted by
# sdlc_ladder_anchor (D-C2 anchor amendment — NEVER an epoch/mtime); n a positive
# ordinal — each rejected loud (one named defect, rc 1) so a malformed key is
# never minted.
_sdlc_rung_key() {
  local gid="${1:-}" rung="${2:-}" anchor="${3:-}" n="${4:-}"
  case "$rung" in
    poke|re-prompt|observe) ;;
    *) echo "defect: invalid-rung: rung-name must be poke|re-prompt|observe, got '${rung:-<empty>}'" >&2; return 1 ;;
  esac
  if ! printf '%s' "$anchor" | grep -qE '^[0-9a-f]{8}$'; then
    echo "defect: invalid-anchor: rung anchor must be an 8-hex durable-progress digest, got '${anchor:-<empty>}'" >&2
    return 1
  fi
  if ! printf '%s' "$n" | grep -qE '^[1-9][0-9]*$'; then
    echo "defect: invalid-ordinal: rung ordinal must be a positive integer, got '${n:-<empty>}'" >&2
    return 1
  fi
  printf 'rung:%s:%s:%s:%s' "$gid" "$rung" "$anchor" "$n"
}

# _sdlc_ladder_rung_probe <goal-id> <rung-name> <anchor> <cap> — walk ordinals
# 1..cap for ONE rung under this anchor. Prints the next open ordinal (rc 0)
# when a slot is free; prints nothing (rc 2) when the rung is exhausted (all
# <cap> attempts applied); emits a loud effect-indeterminate defect (rc 1) on a
# decision-without-effect crash-window key. Pure (reads effect state only).
_sdlc_ladder_rung_probe() {
  local gid="$1" rung="$2" anchor="$3" cap="$4"
  local n key state
  for (( n = 1; n <= cap; n++ )); do
    key="$(_sdlc_rung_key "$gid" "$rung" "$anchor" "$n")" || return 1
    state="$(sdlc_effect_state "$gid" "$key")" || return 1
    case "$state" in
      applied) ;;                                    # completed attempt — keep counting
      indeterminate)
        echo "defect: effect-indeterminate: $key — journaled rung intent has no recorded effect (crash window)" >&2
        return 1 ;;
      *) printf '%s' "$n"; return 0 ;;               # unapplied → this is the next open slot
    esac
  done
  return 2                                           # all cap attempts applied → rung exhausted
}

# _sdlc_ladder_rollover <goal-id> — the DEAD ladder's terminal-automated step
# (D-C4): derive from the CURRENT baton generation's spawn-key state. Prints
# `rollover` (unapplied) or `human` (applied, AS-N13); a decision-only spawn key
# (crash window) → defect effect-indeterminate; an unparseable baton passes its
# own defect through. rc 0 on a token, 1 on any defect.
_sdlc_ladder_rollover() {
  local gid="$1" baton spawn_key
  baton="$(baton_path "$gid")"
  baton_parse "$baton" || return 1
  spawn_key="spawn:$gid:$BATON_WRITTEN_AT"
  case "$(sdlc_effect_state "$gid" "$spawn_key")" in
    applied)   printf 'human\n'; return 0 ;;
    unapplied) printf 'rollover\n'; return 0 ;;
    *) echo "defect: effect-indeterminate: $spawn_key — journaled spawn intent has no recorded effect (crash window)" >&2
       return 1 ;;
  esac
}

sdlc_ladder_next() {
  local goal_id="${1:-}" classification="${2:-}" anchor="${3:-}"
  local rung_cap="${SDLC_RUNG_CAP:-2}" observe_cap="${SDLC_OBSERVE_CAP:-3}"
  local lpath next

  _sdlc_validate_goal_id "$goal_id" "sdlc_ladder_next" || return 1

  # anchor is the episode's DURABLE-PROGRESS DIGEST (D-C2 amendment): an 8-hex
  # token the caller derives via sdlc_ladder_anchor over durable progress only
  # (plan current, goal branch tip, passenger-class ledger tail, baton
  # written-at) — replay-stable and IMMUNE to a poke's own transcript write. A
  # non-8-hex value is a caller bug, refused loud.
  if ! printf '%s' "$anchor" | grep -qE '^[0-9a-f]{8}$'; then
    echo "defect: invalid-anchor: sdlc_ladder_next anchor must be an 8-hex durable-progress digest, got '${anchor:-<empty>}'" >&2
    return 1
  fi
  # caps are env-overridable; a garbled override must fail LOUD, never silently
  # coerce to 0 (which would collapse the ladder straight to its terminal rung).
  if ! printf '%s' "$rung_cap" | grep -qE '^[1-9][0-9]*$'; then
    echo "defect: invalid-cap: SDLC_RUNG_CAP must be a positive integer, got '$rung_cap'" >&2
    return 1
  fi
  if ! printf '%s' "$observe_cap" | grep -qE '^[1-9][0-9]*$'; then
    echo "defect: invalid-cap: SDLC_OBSERVE_CAP must be a positive integer, got '$observe_cap'" >&2
    return 1
  fi

  # Corrupt-ledger fail-closed: a NON-EMPTY ledger must chain-verify before any
  # rung is derived from it. A missing/empty ledger is a fresh episode, NOT a
  # defect — the same "not yet" the effect primitives treat as ordinary.
  lpath="$(ledger_path "$goal_id")"
  if [ -s "$lpath" ]; then
    ledger_verify "$goal_id" || return 1
  fi

  case "$classification" in
    DEAD)
      next="$(_sdlc_ladder_rung_probe "$goal_id" poke "$anchor" "$rung_cap")"
      case $? in 0) printf 'poke:%s\n' "$next"; return 0 ;; 1) return 1 ;; esac
      next="$(_sdlc_ladder_rung_probe "$goal_id" re-prompt "$anchor" "$rung_cap")"
      case $? in 0) printf 're-prompt:%s\n' "$next"; return 0 ;; 1) return 1 ;; esac
      _sdlc_ladder_rollover "$goal_id"; return $? ;;
    IDLE_STALLED)
      next="$(_sdlc_ladder_rung_probe "$goal_id" poke "$anchor" "$rung_cap")"
      case $? in 0) printf 'poke:%s\n' "$next"; return 0 ;; 1) return 1 ;; esac
      next="$(_sdlc_ladder_rung_probe "$goal_id" re-prompt "$anchor" "$rung_cap")"
      case $? in 0) printf 're-prompt:%s\n' "$next"; return 0 ;; 1) return 1 ;; esac
      printf 'human\n'; return 0 ;;
    WEDGED)
      next="$(_sdlc_ladder_rung_probe "$goal_id" observe "$anchor" "$observe_cap")"
      case $? in 0) printf 'observe:%s\n' "$next"; return 0 ;; 1) return 1 ;; esac
      printf 'human\n'; return 0 ;;
    *)
      printf 'none\n'; return 0 ;;
  esac
}

# ============================================================================
# Keepalive wave (4/S1): flag resolution + arm/disarm
# ============================================================================
# Universal keepalive — any governed run armable with explicit keepalive/pilot
# consents. Two effective-flag resolvers (frontmatter → scale-keyed fallback)
# and the arm/disarm registration primitives. These write to the POKER's
# consent registry ($HOME/.claude/sdlc-goals) and audit log
# ($HOME/.claude/sdlc-poker-audit.log): the poker (sdlc-poker.sh) is the sole
# consumer of both. This lib is sourced STANDALONE by its own fixture suite, so
# the goals-dir / audit-log / iso-now helpers are mirrored here (byte-equivalent
# to sdlc-poker.sh:89/92/97) rather than reached from the poker — the same
# self-containment stance sdlc_goal_id takes toward context-spend.sh. All
# helpers read $HOME at call time so a fixture's fake HOME is honored.

_sdlc_goals_dir()   { printf '%s/.claude/sdlc-goals' "$HOME"; }
_sdlc_poker_audit() { printf '%s/.claude/sdlc-poker-audit.log' "$HOME"; }
_sdlc_iso_now()     { date -u +%Y-%m-%dT%H:%M:%SZ; }

# _sdlc_audit <goal-id> <event> [detail] — append an audit line in the poker's
# format (`<iso> <gid> <event> <detail>`) to the shared poker audit log. Never
# fails the caller (best-effort append, matching sdlc-poker.sh:audit_line).
_sdlc_audit() {
  local log; log="$(_sdlc_poker_audit)"
  mkdir -p "$(dirname "$log")" 2>/dev/null
  printf '%s %s %s %s\n' "$(_sdlc_iso_now)" "$1" "$2" "${3:-}" >> "$log" 2>/dev/null
}

# _sdlc_plan_fm <plan> <key> — value of a top-frontmatter `key:` line, CR-
# tolerant, quote-stripped. Byte-equivalent to sdlc-poker.sh:plan_frontmatter
# (normalize_nl + the ---…--- window scan): the poker and lib MUST read a plan's
# flags identically. Empty output = key absent (or empty value).
_sdlc_plan_fm() {
  awk '{ sub(/\r$/, ""); gsub(/\r/, "\n"); print }' "$1" 2>/dev/null \
    | awk 'NR==1 && $0=="---"{f=1; next} f && $0=="---"{exit} f' \
    | grep -E "^[[:space:]]*$2[[:space:]]*:" | head -1 \
    | sed -E "s/^[[:space:]]*$2[[:space:]]*:[[:space:]]*//" \
    | sed -E 's/[[:space:]]+$//' | sed -E "s/^['\"]//;s/['\"]\$//"
}

# _sdlc_scale_is_continuous <plan> — 0 iff the plan's effective scale row is the
# `continuous` row of the fallback table. Any other value (task/wave/epic, an
# unknown scale, or an absent scale) is the conservative non-continuous row:
# keepalive off / pilot MANUAL — never arm/drive on a scale we cannot read.
_sdlc_scale_is_continuous() {
  [ "$(_sdlc_plan_fm "$1" scale)" = "continuous" ]
}

# sdlc_keepalive_effective <plan-path> → stdout `true|false`, rc 0.
#   unreadable/missing plan → rc 1, empty stdout.
#   explicit off-enum keepalive value → rc 2 + stderr (fail-loud, never guess —
#   symmetric with the pilot resolver; a `keepalive: flase` typo must not
#   silently fall through to the fallback and flip armability on a guess).
sdlc_keepalive_effective() {
  local plan="${1:-}" v
  [ -n "$plan" ] && [ -f "$plan" ] && [ -r "$plan" ] || { return 1; }
  v="$(_sdlc_plan_fm "$plan" keepalive)"
  case "$v" in
    true)  printf 'true\n';  return 0 ;;
    false) printf 'false\n'; return 0 ;;
    '')    # absent → scale-keyed fallback
      if _sdlc_scale_is_continuous "$plan"; then printf 'true\n'; else printf 'false\n'; fi
      return 0 ;;
    *)
      echo "defect: invalid-keepalive: '$v' — keepalive must be true or false: $plan" >&2
      return 2 ;;
  esac
}

# sdlc_pilot_effective <plan-path> → stdout `MANUAL|AUTO`, rc 0.
#   unreadable/missing plan → rc 1, empty stdout.
#   explicit off-enum pilot value → rc 2 + stderr naming it (fail-loud).
sdlc_pilot_effective() {
  local plan="${1:-}" v
  [ -n "$plan" ] && [ -f "$plan" ] && [ -r "$plan" ] || { return 1; }
  v="$(_sdlc_plan_fm "$plan" pilot)"
  case "$v" in
    MANUAL) printf 'MANUAL\n'; return 0 ;;
    AUTO)   printf 'AUTO\n';   return 0 ;;
    '')     # absent → scale-keyed fallback
      if _sdlc_scale_is_continuous "$plan"; then printf 'AUTO\n'; else printf 'MANUAL\n'; fi
      return 0 ;;
    *)
      echo "defect: invalid-pilot: '$v' — pilot must be MANUAL or AUTO: $plan" >&2
      return 2 ;;
  esac
}

# _sdlc_abspath <path> — path with its directory resolved to an absolute
# physical path (basename left intact, so a not-yet-existing file resolves as
# long as its parent dir exists). BSD-safe (no realpath dependency). The
# registration stores the plan absolute so the poker — polling from the cron
# cwd — can always re-read the plan's frontmatter (REG_PLAN).
_sdlc_abspath() {
  local p="${1:-}" d b
  d="$(cd "$(dirname "$p")" 2>/dev/null && pwd)" || return 1
  b="$(basename "$p")"
  printf '%s/%s' "$d" "$b"
}

# sdlc_arm <plan-path> [pilot-override] [--force] → arm a governed run:
# derive the goal-id (sdlc_goal_id), capture PLAN/CWD/SESSION_ID/PID/ARMED_AT
# and write the 5-field consent record atomically (tmp+mv) into the poker's
# goals dir. SESSION_ID/PID come from the SDLC_ARM_SESSION_ID / SDLC_ARM_PID
# env seams when set (testability + headless callers), else best-effort real
# values ($$ for PID; $CLAUDE_SESSION_ID for the session). On success: emits
# `ARM <gid> <plan> pilot=<p>` to the audit log and prints the goal-id.
#
# pilot-override (a bare MANUAL|AUTO token) sets the pilot shown in the audit
# line; --force authorizes arming when keepalive-effective is false (the sole
# legitimate arm-on-false path). Refusals (rc≠0 + stderr + NO record write):
# missing/unreadable plan, malformed frontmatter (off-enum keepalive/pilot),
# a colliding record (same goal-id, different PLAN), and keepalive-effective
# false without --force. [refusals land in a later case-group.]
sdlc_arm() {
  local plan="${1:-}" pilot_override="" force=0
  shift 2>/dev/null || true
  local a
  for a in "$@"; do
    case "$a" in
      --force)       force=1 ;;
      MANUAL|AUTO)   pilot_override="$a" ;;
      '')            ;;
      *) echo "defect: arm-bad-arg: unrecognized argument '$a' (expected MANUAL|AUTO or --force)" >&2; return 1 ;;
    esac
  done

  local abs gid dir rec tmp sid pid cwd armed pilot ka krc prc

  # 1. plan must be a readable file — refuse loud, before any resolution.
  [ -n "$plan" ] && [ -f "$plan" ] && [ -r "$plan" ] || {
    echo "defect: missing-plan: sdlc_arm requires a readable plan file: ${plan:-<empty>}" >&2; return 1; }

  abs="$(_sdlc_abspath "$plan")" || abs="$plan"
  gid="$(sdlc_goal_id "$plan")"
  _sdlc_validate_goal_id "$gid" "sdlc_arm" || return 1

  # 2. malformed frontmatter is fail-loud: an off-enum keepalive (rc 2) refuses
  #    regardless of --force (garbage is not a false to be forced past).
  ka="$(sdlc_keepalive_effective "$abs")"; krc=$?
  if [ "$krc" -ne 0 ]; then
    echo "defect: malformed-frontmatter: cannot resolve keepalive for $abs" >&2; return 1
  fi

  # pilot for the audit line: explicit override wins; else the effective value.
  # An off-enum pilot with NO override is malformed → refuse.
  if [ -n "$pilot_override" ]; then
    pilot="$pilot_override"
  else
    pilot="$(sdlc_pilot_effective "$abs")"; prc=$?
    if [ "$prc" -ne 0 ]; then
      echo "defect: malformed-frontmatter: cannot resolve pilot for $abs (pass MANUAL|AUTO to override)" >&2; return 1
    fi
  fi

  # 3. keepalive-effective false arms only under an explicit --force.
  if [ "$ka" = false ] && [ "$force" -ne 1 ]; then
    echo "defect: keepalive-false: $abs is not keepalive-armable; pass --force to arm anyway" >&2; return 1
  fi

  # 4. collision: a record already at this goal-id whose PLAN differs is a
  #    distinct goal claiming the same id — refuse (a same-PLAN re-arm is an
  #    idempotent overwrite, allowed).
  dir="$(_sdlc_goals_dir)"
  rec="$dir/$gid"
  if [ -f "$rec" ]; then
    local existing_plan; existing_plan="$(grep -E '^PLAN=' "$rec" 2>/dev/null | head -1 | sed -E 's/^PLAN=//')"
    if [ -n "$existing_plan" ] && [ "$existing_plan" != "$abs" ]; then
      echo "defect: arm-collision: goal-id '$gid' already registered to a different plan ($existing_plan); refusing to overwrite with $abs" >&2
      return 1
    fi
  fi

  cwd="$(pwd)"
  sid="${SDLC_ARM_SESSION_ID:-${CLAUDE_SESSION_ID:-}}"
  pid="${SDLC_ARM_PID:-$$}"
  armed="$(_sdlc_iso_now)"

  mkdir -p "$dir" 2>/dev/null || { echo "defect: arm-mkdir-failed: cannot create goals dir: $dir" >&2; return 1; }
  tmp="$(mktemp "$dir/.arm.$gid.XXXXXX" 2>/dev/null)" || { echo "defect: arm-mktemp-failed: cannot mint a temp record in $dir" >&2; return 1; }
  {
    printf 'PLAN=%s\n' "$abs"
    printf 'CWD=%s\n' "$cwd"
    printf 'SESSION_ID=%s\n' "$sid"
    printf 'PID=%s\n' "$pid"
    printf 'ARMED_AT=%s\n' "$armed"
  } > "$tmp" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; echo "defect: arm-write-failed: cannot write $tmp" >&2; return 1; }
  mv -f "$tmp" "$rec" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; echo "defect: arm-rename-failed: cannot install $rec" >&2; return 1; }

  _sdlc_audit "$gid" ARM "$abs pilot=$pilot"
  printf '%s\n' "$gid"
}

# sdlc_disarm <goal-id> [reason] → remove the consent record and emit
# `DISARM <gid> <reason>` (reason defaults to `manual`). Idempotent-safe: an
# absent record is a rc-1 no-op that is STILL audited (today's silent delete is
# replaced by a durable trail). An invalid goal-id is refused loud (path guard,
# shared with the baton primitives) — no audit, no filesystem touch.
sdlc_disarm() {
  local gid="${1:-}" reason="${2:-manual}" rec rc
  _sdlc_validate_goal_id "$gid" "sdlc_disarm" || return 1
  rec="$(_sdlc_goals_dir)/$gid"
  if [ -f "$rec" ]; then
    rm -f "$rec" 2>/dev/null
    if [ -e "$rec" ]; then
      echo "defect: disarm-remove-failed: cannot remove $rec" >&2
      _sdlc_audit "$gid" DISARM "$reason remove-failed"
      return 1
    fi
    _sdlc_audit "$gid" DISARM "$reason"
    return 0
  fi
  # absent → audited no-op, rc 1
  _sdlc_audit "$gid" DISARM "$reason no-op-absent"
  return 1
}
