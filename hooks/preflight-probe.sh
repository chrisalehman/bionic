#!/bin/bash
# ENVIRONMENT CHECK — the start-side PRODUCER of epic-15's dispatch resilience.
# Design: design/orchestrator-subagent-coordination.md §4 "The environment check", §7, §8.
# [WALL: hooks/preflight-probe.test.sh]
#
# This is NOT a hook. It lives in hooks/ for test-harness pairing only; the component
# boundary is the registration list, and this script is never registered. It is run by
# hand, once per session, before dispatching subagents:
#
#     bash ~/.claude/hooks/preflight-probe.sh
#
# It verifies what a fleet dies without, and — only if those checks pass — writes an
# attestation keyed to THIS session. The start gate later reads that file's existence as
# the whole verdict; it parses no check detail, so the contract kept here is the only
# thing standing behind it:
#
#   * blocking probes (any failure => no attestation, and any earlier one destroyed):
#       - a credential is present    (presence, NOT validity — see "Named limit" below)
#       - the repo is writable
#       - the state directory is writable
#   * context probes (recorded, never blocking): git baseline; a warn-only scan for other
#     live sessions working in this same project.
#
# Named limit: this proves a credential is PRESENT, not that it is valid or unexpired —
# expiry detection needs a live API call (backlog, design §4).
#
# Session key: taken from CLAUDE_CODE_SESSION_ID, which Claude Code exports into every
# Bash subprocess and which equals the `session_id` field hook payloads carry (record
# §2.2). Every actor in a fleet shares one session key — that is a known, ratified
# exposure (design D-3), not a defect here.
#
# Attestation record — this script OWNS the schema (spec §Design ownership table); the
# start gate carries its own reader copy, and the two are held together by the agreement
# tests in slice 4/6. Format: `# comment` lines plus `key=value` lines in any order, read
# BY KEY and never by position (checklist A6). A version line is always present so a
# future field addition is a readable change rather than a silent parse break.
#
#     version=1                       kind=preflight-attestation
#     session_id=<session key>        written_at=<epoch>   written_at_iso=<UTC>
#     repo=<resolved repo root>       git_branch= git_head= git_dirty=
#     credential_source=<where the credential was found, never the credential>
#     other_sessions=<count seen by the warn-only scan>
#
# The key is spelled `session_id` deliberately: it is the payload field name the reading
# gate receives, and it is what the CURRENTLY INSTALLED old-name gate greps for. Until
# the user's bootstrap replaces that install, a run of this script must not silently
# disarm the live gate by renaming the one field it reads.
#
# Exit codes — this list is pinned against the code by preflight-probe.test.sh, because a
# doc/behavior split on exactly this point (checklist A5) is what let a stale pass survive
# a failed write in the discarded run:
#   exit 0 — the attestation for THIS session is present on disk
#   exit 1 — a blocking probe failed; no usable attestation on disk (any prior one was
#            deleted, or emptied where the directory forbade deleting it; if even that
#            failed the message says so and names the file to remove by hand)
#   exit 2 — refused or could not complete; no attestation on disk (prior one deleted)
#   exit 3 — no session key; REFUSED, state left untouched
#   exit 4 — the state lock is held by another writer; state left untouched
#
# Hostile-repo posture (design §8): a repo controls its own .bionic/ contents, so every
# path this script writes is checked for symlink redirection first and the record is
# installed through mktemp + rename. A hostile repo can make this check REFUSE; it cannot
# make it attest.

set -u

ATTESTATION_VERSION=1
STATE_BASENAME="preflight.state"
LOCK_BASENAME=".preflight.lock"
OTHER_SESSION_WINDOW_MIN=15   # warn-only liveness heuristic; mtime-based, known to
                              # false-positive on recently-dead sessions (spec Not Doing)

say()  { printf 'preflight: %s\n' "$1"; }
warn() { printf 'preflight: WARN %s\n' "$1"; }
die()  { printf 'preflight: %s\n' "$1" >&2; }

# ---------------------------------------------------------------- session key (design §7)

SESSION_ID="${CLAUDE_CODE_SESSION_ID:-}"
if [ -z "$SESSION_ID" ]; then
  die "REFUSED — no session key (CLAUDE_CODE_SESSION_ID is unset or empty)."
  die "An unkeyed attestation validates nothing, so none is written and existing state is"
  die "left untouched. Run this from inside a Claude Code session."
  exit 3
fi

# ---------------------------------------------------------------- where state lives

REPO="$(git rev-parse --show-toplevel 2>/dev/null)"
[ -n "$REPO" ] || REPO="$PWD"
REPO_REAL="$(cd "$REPO" 2>/dev/null && pwd -P)"
if [ -z "$REPO_REAL" ]; then
  die "REFUSED — cannot resolve the working directory."
  exit 2
fi

BIONIC_DIR="$REPO_REAL/.bionic"
STATE_DIR="$BIONIC_DIR/tmp"
STATE_FILE="$STATE_DIR/$STATE_BASENAME"
LOCK_DIR="$STATE_DIR/$LOCK_BASENAME"

# Path safety BEFORE anything is created or written: a planted symlink anywhere on the
# way to the state directory redirects every later write out of the repo.
for _component in "$BIONIC_DIR" "$STATE_DIR"; do
  if [ -L "$_component" ]; then
    die "REFUSED — $_component is a symbolic link."
    die "The state directory must be a real directory inside the repo. Remove the link"
    die "and re-run; nothing was written."
    exit 2
  fi
done

# ---------------------------------------------------------------- blocking probes

BLOCKING_FAILED=0
STATE_DIR_OK=1

fail_probe() {  # <message>
  printf 'preflight: FAIL  %s\n' "$1"
  BLOCKING_FAILED=1
}
pass_probe() { printf 'preflight: ok    %s\n' "$1"; }

# 1. credential present (presence only). Three sources, cheapest first. Nothing here ever
#    reads or prints credential material — only its existence.
CRED_SOURCE=""
if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
  CRED_SOURCE="environment"
elif [ -s "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.credentials.json" ]; then
  CRED_SOURCE="credentials file"
elif command -v security >/dev/null 2>&1 &&
     security find-generic-password -s "Claude Code-credentials" >/dev/null 2>&1; then
  CRED_SOURCE="login keychain"
fi
if [ -n "$CRED_SOURCE" ]; then
  pass_probe "credential present ($CRED_SOURCE)"
else
  fail_probe "credential absent — no ANTHROPIC_API_KEY, no credentials file, no keychain entry"
fi

# 2. repo writable — proven by writing, not by mode bits
_probe_file="$(mktemp "$REPO_REAL/.preflight-write-check.XXXXXX" 2>/dev/null)"
if [ -n "$_probe_file" ] && [ -f "$_probe_file" ]; then
  rm -f "$_probe_file"
  pass_probe "repo writable ($REPO_REAL)"
else
  fail_probe "repo NOT writable ($REPO_REAL)"
fi

# 3. state dir writable — created if absent, then proven by writing
mkdir -p "$STATE_DIR" 2>/dev/null
if [ -d "$STATE_DIR" ]; then
  _probe_file="$(mktemp "$STATE_DIR/.preflight-write-check.XXXXXX" 2>/dev/null)"
  if [ -n "$_probe_file" ] && [ -f "$_probe_file" ]; then
    rm -f "$_probe_file"
    pass_probe "state dir writable ($STATE_DIR)"
  else
    STATE_DIR_OK=0
    fail_probe "state dir NOT writable ($STATE_DIR)"
  fi
else
  STATE_DIR_OK=0
  fail_probe "state dir could not be created ($STATE_DIR)"
fi

# Containment backstop. This deliberately OVERLAPS the component checks above: with those
# present, no reachable input makes this fire, so it carries no RED of its own in the
# suite. It is kept as the second layer that still refuses an out-of-repo redirect if a
# future edit weakens the first — mutation-proven: removing the -L loop leaves the
# out-of-repo cases refused by this check alone.
if [ "$STATE_DIR_OK" -eq 1 ]; then
  STATE_DIR_REAL="$(cd "$STATE_DIR" 2>/dev/null && pwd -P)"
  case "${STATE_DIR_REAL:-}/" in
    "$REPO_REAL"/*) : ;;
    *)
      die "REFUSED — the state directory resolves outside the repo (${STATE_DIR_REAL:-unresolvable})."
      exit 2
      ;;
  esac
fi

# ---------------------------------------------------------------- context probes

GIT_BRANCH="-"; GIT_HEAD="-"; GIT_DIRTY="-"
if git rev-parse --git-dir >/dev/null 2>&1; then
  GIT_BRANCH="$(git symbolic-ref --short -q HEAD 2>/dev/null)"; [ -n "$GIT_BRANCH" ] || GIT_BRANCH="-"
  GIT_HEAD="$(git rev-parse --short HEAD 2>/dev/null)";          [ -n "$GIT_HEAD" ]   || GIT_HEAD="-"
  GIT_DIRTY="$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')"; [ -n "$GIT_DIRTY" ] || GIT_DIRTY="-"
  say "git baseline: branch $GIT_BRANCH @ $GIT_HEAD, $GIT_DIRTY uncommitted path(s)"
else
  say "git baseline: not a git working tree (context only, not blocking)"
fi

# Other live sessions in this project. Warn-only by design (§4, UC-6): detection, never
# prevention. The project directory is located by finding the one that holds THIS
# session's own transcript, so no filename-encoding scheme has to be guessed.
CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
OTHER_SESSIONS=0
PROJ_DIR=""
if [ -d "$CONFIG_DIR/projects" ]; then
  for _d in "$CONFIG_DIR"/projects/*/; do
    [ -d "$_d" ] || continue
    if [ -f "$_d$SESSION_ID.jsonl" ]; then PROJ_DIR="${_d%/}"; break; fi
  done
fi
if [ -n "$PROJ_DIR" ]; then
  while IFS= read -r _t; do
    [ -n "$_t" ] || continue
    _other="$(basename "$_t" .jsonl)"
    [ "$_other" = "$SESSION_ID" ] && continue
    OTHER_SESSIONS=$((OTHER_SESSIONS + 1))
    warn "another live session on this project: $_other (transcript touched within ${OTHER_SESSION_WINDOW_MIN}m)"
  done <<EOF
$(find "$PROJ_DIR" -maxdepth 1 -name '*.jsonl' -mmin "-$OTHER_SESSION_WINDOW_MIN" 2>/dev/null)
EOF
  [ "$OTHER_SESSIONS" -eq 0 ] && say "no other live session detected on this project"
else
  say "session roster: this session's transcript directory was not found (context only)"
fi

# ---------------------------------------------------------------- state mutation

# An unusable state directory does NOT mean the directory is empty: it can be readable
# and non-writable (or full) while holding a perfectly readable prior attestation, and the
# start gate would read that file and pass — a stale pass outliving the environment it
# described (§7 row 5, checklist A5). So the delete-on-fail obligation holds on THIS path
# too, even though the lock below is unreachable from here.
#
# `rm` needs write permission on the DIRECTORY and can fail here; truncation needs it only
# on the FILE, and an emptied attestation carries no `session_id=` line, which the start
# gate refuses as "not a valid attestation record". A symlink is never truncated — that
# would write through the redirect a hostile repo planted (§8) — only unlinked.
if [ "$STATE_DIR_OK" -eq 0 ]; then
  if [ -L "$STATE_FILE" ]; then
    rm -f "$STATE_FILE" 2>/dev/null
  elif [ -f "$STATE_FILE" ]; then
    rm -f "$STATE_FILE" 2>/dev/null
    [ -f "$STATE_FILE" ] && : > "$STATE_FILE" 2>/dev/null
  fi
  if [ -e "$STATE_FILE" ] && [ -s "$STATE_FILE" ]; then
    die "BLOCKED — a blocking probe failed, and the prior attestation at $STATE_FILE could"
    die "NEITHER be deleted nor emptied. It may still admit dispatches. Remove it by hand:"
    die "  rm -f $STATE_FILE"
  else
    die "BLOCKED — a blocking probe failed. No attestation was written, and any earlier"
    die "attestation has been deleted or emptied."
  fi
  die "Fix the failure above and re-run: bash ~/.claude/hooks/preflight-probe.sh"
  exit 1
fi

# Lock before any read-modify-write, so two sessions racing on the single-slot state file
# (design D-5) serialize instead of interleaving.
LOCK_HELD=0
release_lock() { [ "$LOCK_HELD" -eq 1 ] && rmdir "$LOCK_DIR" 2>/dev/null; LOCK_HELD=0; }
trap release_lock EXIT

# A lock left behind by a killed run would wedge every later run; break clearly stale ones.
if [ -d "$LOCK_DIR" ] && [ -n "$(find "$LOCK_DIR" -maxdepth 0 -mmin +2 2>/dev/null)" ]; then
  rmdir "$LOCK_DIR" 2>/dev/null
fi
_tries=0
while ! mkdir "$LOCK_DIR" 2>/dev/null; do
  _tries=$((_tries + 1))
  if [ "$_tries" -ge 20 ]; then
    die "BUSY — another writer holds $LOCK_DIR. State left untouched; re-run in a moment."
    exit 4
  fi
  sleep 0.1
done
LOCK_HELD=1

# The attestation path itself, now that the write is imminent.
if [ -L "$STATE_FILE" ]; then
  rm -f "$STATE_FILE"
  die "REFUSED — the attestation path was a symbolic link; it was removed, not followed."
  die "Nothing was written through it, and no attestation is present."
  exit 2
fi
if [ -d "$STATE_FILE" ]; then
  die "REFUSED — the attestation path is occupied by a directory ($STATE_FILE)."
  die "Remove it and re-run; no attestation is present."
  exit 2
fi

if [ "$BLOCKING_FAILED" -eq 1 ]; then
  # A stale pass must not outlive the environment it described (design §7).
  rm -f "$STATE_FILE"
  die "BLOCKED — a blocking probe failed. No attestation was written, and any earlier"
  die "attestation has been deleted. Fix the failure above and re-run:"
  die "  bash ~/.claude/hooks/preflight-probe.sh"
  exit 1
fi

tmp=""
abort_write() {  # <message> — leaves no attestation of any kind behind
  [ -n "${tmp:-}" ] && rm -f "$tmp"
  rm -f "$STATE_FILE" 2>/dev/null
  die "FAILED — $1"
  die "No attestation is present (any earlier one was deleted). Fix the cause and re-run."
  exit 2
}

# Delete first, then install atomically. The ordering is the point: every failure after
# this line leaves NO attestation rather than a surviving stale one (checklist A5).
rm -f "$STATE_FILE" 2>/dev/null

tmp="$(mktemp "$STATE_DIR/$STATE_BASENAME.XXXXXX" 2>/dev/null)"
[ -n "$tmp" ] && [ -f "$tmp" ] || abort_write "could not create a temporary file in $STATE_DIR"
chmod 600 "$tmp" 2>/dev/null || abort_write "could not restrict permissions on the temporary file"

{
  printf '# bionic environment attestation — machine-local, safe to delete\n'
  printf 'version=%s\n'      "$ATTESTATION_VERSION"
  printf 'kind=%s\n'         "preflight-attestation"
  printf 'session_id=%s\n'   "$SESSION_ID"
  printf 'written_at=%s\n'   "$(date -u +%s)"
  printf 'written_at_iso=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'repo=%s\n'         "$REPO_REAL"
  printf 'git_branch=%s\n'   "$GIT_BRANCH"
  printf 'git_head=%s\n'     "$GIT_HEAD"
  printf 'git_dirty=%s\n'    "$GIT_DIRTY"
  printf 'credential_source=%s\n' "$CRED_SOURCE"
  printf 'other_sessions=%s\n'    "$OTHER_SESSIONS"
} > "$tmp" 2>/dev/null || abort_write "could not write the attestation record"

mv -f "$tmp" "$STATE_FILE" 2>/dev/null || abort_write "could not install the attestation at $STATE_FILE"
tmp=""

# Read back what was installed: the file must exist and carry THIS session's key, looked
# up by key rather than by position (checklist A6).
_readback="$(grep -m1 '^session_id=' "$STATE_FILE" 2>/dev/null | cut -d= -f2-)"
[ "$_readback" = "$SESSION_ID" ] || abort_write "the installed attestation did not read back correctly"

say "attestation written for session $SESSION_ID"
say "  $STATE_FILE"
release_lock
exit 0
