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
