#!/bin/bash
# tests/engage.test.sh — hooks/engage.sh, the ENGAGEMENT TRIGGER (task-engaged-session,
# task T1; matrix AC-1, AC-2, AC-3, AC-4, AC-17, AC-18).
#
# WHAT IT OWNS. The one act that puts a session inside bionic: invoking the
# canonical-sdlc skill. The hook fires on the two paths that invocation can take —
# a model-issued `Skill` tool call (PreToolUse, `tool_input.skill`) and a user-typed
# slash command (UserPromptExpansion, `command_name`) — and writes
# `<root>/.bionic/tmp/engaged-<sid>.state`. Every other bionic wall reads that file
# through `engaged_session` in payload/scripts/lib/run.sh and stays silent without it.
#
# THE FAIL DIRECTION IS INVERTED HERE and that is the whole reason this suite is
# adversarial about the negative arms. Everywhere else in this tree, an unreadable
# state CLOSES a wall; here PRESENCE opens them. So a false positive — a marker
# written for a skill that is not canonical-sdlc, for a foreign session id, for the
# `unknown` fallback two advisories use, or through a symlink somebody planted — arms
# every wall in the fleet against a session that never consented. Each negative below
# is therefore PAIRED with the positive on the SAME fixture, so a negative that passes
# because the hook is inert cannot pass at all.
#
# HERMETIC. Every project is a fixture under a mktemp sandbox; no real .bionic tree,
# no real plan, no ~/.claude read. The hook is driven as a subprocess with JSON on
# stdin, exactly as the harness delivers it.
#
# Usage: bash tests/engage.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
HOOK="$BIONIC_HOOKS_DIR/engage.sh"
LIB="$REPO_ROOT/payload/scripts/lib/run.sh"
LOADER_LIB="$REPO_ROOT/payload/scripts/lib/loader.sh"
HOOKS_JSON="$REPO_ROOT/hooks/hooks.json"
RUNNER="$REPO_ROOT/tests/run.sh"

SANDBOX="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/engage-test.XXXXXX")" && pwd -P)"
cleanup() { rm -rf "$SANDBOX"; }
trap cleanup EXIT

PASS=0
FAIL=0
TOTAL=0
ok() { TOTAL=$((TOTAL + 1)); PASS=$((PASS + 1)); echo "PASS: $1"; }
no() { TOTAL=$((TOTAL + 1)); FAIL=$((FAIL + 1)); echo "FAIL: $1"; [ -n "${2:-}" ] && echo "      $2"; }
expect_eq()       { if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "expected [$2], got [$3]"; fi; }
expect_empty()    { if [ -z "$2" ]; then ok "$1"; else no "$1" "expected no output, got: $2"; fi; }
expect_contains() { case "$3" in *"$2"*) ok "$1" ;; *) no "$1" "expected to contain [$2], got: $3" ;; esac; }

SID="e40aged1-2222-3333-4444-555555555555"
OTHER_SID="0ther999-8888-7777-6666-555555555555"

# ---------- fixture builders ----------

# A project with a .bionic tree and an OPEN plan. `project_root` answers at the
# nearest ancestor carrying `.bionic/`, which is this directory itself.
make_repo() {  # [name] -> project dir on stdout
  local dir
  dir="$(cd "$(mktemp -d "$SANDBOX/${1:-repo}.XXXXXX")" && pwd -P)"
  mkdir -p "$dir/.bionic/tmp" "$dir/.bionic/docs/plans"
  cat > "$dir/.bionic/docs/plans/wave-01.plan.md" <<'ENGPLAN'
---
canonical_sdlc_version: 14
---

## SDLC State

current: 4

- Step 4: slices in flight
ENGPLAN
  printf '%s' "$dir"
}

# A project with a .bionic tree and NO plan at all (AC-18's first half: Step 0 of a
# new run precedes its plan file).
make_repo_planless() {  # -> project dir on stdout
  local dir
  dir="$(cd "$(mktemp -d "$SANDBOX/planless.XXXXXX")" && pwd -P)"
  mkdir -p "$dir/.bionic/tmp"
  printf '%s' "$dir"
}

# A project with NO .bionic AT ALL (AC-18's second half). Nothing in the payload owns
# tree creation today, so a fresh project would otherwise engage and stay unwalled.
# git-init'd so `project_root` lands on this directory by the git-toplevel fallback
# rather than on whatever ancestor of $TMPDIR happens to exist.
make_repo_fresh() {  # -> project dir on stdout
  local dir
  dir="$(cd "$(mktemp -d "$SANDBOX/fresh.XXXXXX")" && pwd -P)"
  git -C "$dir" init -q 2>/dev/null
  printf '%s' "$dir"
}

marker_path() { printf '%s/.bionic/tmp/engaged-%s.state' "$1" "$2"; }

mode_of() {  # <file> -> octal permission bits
  stat -f %Lp "$1" 2>/dev/null || stat -c %a "$1" 2>/dev/null
}

# ---------- payload builders (field names: code.claude.com/docs/en/hooks) ----------

skill_payload() {  # <sid> <cwd> <skill>
  jq -nc --arg s "$1" --arg c "$2" --arg k "$3" \
    '{session_id:$s,prompt_id:"p-1",transcript_path:"/dev/null",cwd:$c,
      permission_mode:"default",hook_event_name:"PreToolUse",
      tool_name:"Skill",tool_input:{skill:$k},tool_use_id:"toolu_engage_test"}'
}

expansion_payload() {  # <sid> <cwd> <command_name>
  jq -nc --arg s "$1" --arg c "$2" --arg n "$3" \
    '{session_id:$s,prompt_id:"p-1",transcript_path:"/dev/null",cwd:$c,
      permission_mode:"default",hook_event_name:"UserPromptExpansion",
      expansion_type:"slash_command",command_name:$n,command_args:"",
      command_source:"plugin",prompt:"# Canonical SDLC"}'
}

# ---------- driving the hook ----------
#
# THE ENVIRONMENT AGREES WITH THE PAYLOAD, because on the machine it does. The hook
# takes its session key from lib/session.sh — env first, payload as witness — and the
# marker filename is built from the answer, so a driver that left the runner's own id
# in the environment would have the hook writing a file the assertions never look at.
# CLAUDE_PROJECT_DIR is removed so the payload's `cwd` is what resolves the root.
HOOK_OUT=""; HOOK_ERR=""; HOOK_RC=0
fire() {  # <sid> <json>
  HOOK_OUT=$(env -u CLAUDE_PROJECT_DIR CLAUDE_CODE_SESSION_ID="$1" \
    bash "$HOOK" <<< "$2" 2>"$SANDBOX/.err")
  HOOK_RC=$?
  HOOK_ERR=$(cat "$SANDBOX/.err" 2>/dev/null)
}

# ---------- driving the library predicate ----------

ES_ST=0
call_engaged() {  # <root> <sid> -> sets ES_ST
  bash -c '. "$1" || exit 9; engaged_session "$2" "$3"' _ "$LIB" "$1" "$2" >/dev/null 2>&1
  ES_ST=$?
}

# ============================================================
echo "=== E0 — the hook exists, parses, and is executable ==="
# ============================================================

if [ -f "$HOOK" ]; then ok "hooks/engage.sh is on disk"; else no "hooks/engage.sh is on disk" "$HOOK"; fi
if bash -n "$HOOK" 2>"$SANDBOX/.syn"; then ok "engage.sh parses (bash -n)"; else
  no "engage.sh parses (bash -n)" "$(cat "$SANDBOX/.syn")"
fi
# §EXEC in hook-adoption pins this too; a hook that lost its bit is `Permission denied`
# on every event, and the trigger is silently gone.
if [ -x "$HOOK" ]; then ok "engage.sh carries the exec bit"; else no "engage.sh carries the exec bit"; fi

if grep -q '^run "engage.test.sh" bash tests/engage.test.sh$' "$RUNNER" 2>/dev/null; then
  ok "tests/run.sh carries this suite's own run line"
else
  no "tests/run.sh carries this suite's own run line" "no matching run line in $RUNNER"
fi

# ============================================================
echo ""
echo "=== E1 (AC-1) — a Skill call for canonical-sdlc engages the session ==="
# ============================================================

R1="$(make_repo e1)"
M1="$(marker_path "$R1" "$SID")"

fire "$SID" "$(skill_payload "$SID" "$R1" "bionic:canonical-sdlc")"
expect_eq "the plugin-qualified Skill call exits 0" "0" "$HOOK_RC"
expect_empty "…and prints nothing on stdout" "$HOOK_OUT"
if [ -f "$M1" ]; then ok "…and writes the engagement marker"; else
  no "…and writes the engagement marker" "no file at $M1"
fi
expect_contains "the marker names the open plan" \
  "plan=$R1/.bionic/docs/plans/wave-01.plan.md" "$(cat "$M1" 2>/dev/null)"
ENG_AT=$(grep '^engaged_at=' "$M1" 2>/dev/null | sed 's/^engaged_at=//')
if printf '%s' "$ENG_AT" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'; then
  ok "…and an ISO-8601 UTC engaged_at stamp"
else
  no "…and an ISO-8601 UTC engaged_at stamp" "engaged_at was [$ENG_AT]"
fi
expect_eq "the marker is mode 0600" "600" "$(mode_of "$M1")"
expect_eq "the marker is exactly two lines" "2" "$(wc -l < "$M1" | tr -d ' ')"

# The bare (unqualified) spelling the Skill tool also emits.
rm -f "$M1"
fire "$SID" "$(skill_payload "$SID" "$R1" "canonical-sdlc")"
if [ -f "$M1" ]; then ok "the bare 'canonical-sdlc' Skill call engages too"; else
  no "the bare 'canonical-sdlc' Skill call engages too" "no file at $M1"
fi

# Overwrite is idempotent, not an error: a session may invoke the skill many times.
BEFORE=$(cat "$M1")
fire "$SID" "$(skill_payload "$SID" "$R1" "canonical-sdlc")"
expect_eq "a second invocation exits 0 (the write is idempotent)" "0" "$HOOK_RC"
expect_eq "…and the marker is still mode 0600 after the overwrite" "600" "$(mode_of "$M1")"
expect_contains "…and still names the plan" "plan=" "$(cat "$M1")"
[ -n "$BEFORE" ] || no "the first marker was non-empty (non-vacuity)" "empty"

# ============================================================
echo ""
echo "=== E2 (AC-2) — no other skill engages anything ==="
# ============================================================
#
# EACH NEGATIVE IS PAIRED WITH THE POSITIVE ON THE SAME FIXTURE. A negative arm that
# passed because the hook could not find the root, could not resolve the sid, or was
# not executable would be a vacuous pass, and this is the arm where a vacuous pass
# costs the most: it is the one asserting that bionic's walls stay off.

R2="$(make_repo e2)"
M2="$(marker_path "$R2" "$SID")"

for other in bionic:map-instrument-narrow bionic:doctor bionic:browser-verify bionic:help \
             bionic:setup bionic:remove humanizer map-instrument-narrow; do
  rm -f "$M2"
  fire "$SID" "$(skill_payload "$SID" "$R2" "$other")"
  expect_eq "Skill '$other' exits 0" "0" "$HOOK_RC"
  if [ -e "$M2" ]; then no "Skill '$other' writes NO marker" "marker appeared at $M2"; else
    ok "Skill '$other' writes NO marker"
  fi
  # the pair: the same fixture, the same driver, one skill name apart
  fire "$SID" "$(skill_payload "$SID" "$R2" "bionic:canonical-sdlc")"
  if [ -f "$M2" ]; then ok "…paired: canonical-sdlc on the same fixture DOES engage"; else
    no "…paired: canonical-sdlc on the same fixture DOES engage" "no file at $M2 — the negative above was vacuous"
  fi
done

# Near-misses on the name itself. `^(bionic:)?canonical-sdlc$` is anchored at both ends.
for near in canonical-sdlc-v2 xcanonical-sdlc bionic:canonical-sdlc-helper \
            other:canonical-sdlc "canonical-sdlc " ""; do
  rm -f "$M2"
  fire "$SID" "$(skill_payload "$SID" "$R2" "$near")"
  if [ -e "$M2" ]; then no "the near-miss skill name [$near] writes NO marker" "marker appeared"; else
    ok "the near-miss skill name [$near] writes NO marker"
  fi
done
rm -f "$M2"
fire "$SID" "$(skill_payload "$SID" "$R2" "canonical-sdlc")"
if [ -f "$M2" ]; then ok "…paired: the exact name on the same fixture still engages"; else
  no "…paired: the exact name on the same fixture still engages" "no file at $M2"
fi

# A PreToolUse for any OTHER tool is not the trigger, whatever its input carries.
rm -f "$M2"
OTHER_TOOL=$(jq -nc --arg s "$SID" --arg c "$R2" \
  '{session_id:$s,transcript_path:"/dev/null",cwd:$c,hook_event_name:"PreToolUse",
    tool_name:"Bash",tool_input:{command:"echo canonical-sdlc",skill:"bionic:canonical-sdlc"}}')
fire "$SID" "$OTHER_TOOL"
if [ -e "$M2" ]; then no "a Bash PreToolUse naming the skill writes NO marker" "marker appeared"; else
  ok "a Bash PreToolUse naming the skill writes NO marker"
fi

# An unrelated event is not the trigger either.
rm -f "$M2"
STOP_EV=$(jq -nc --arg s "$SID" --arg c "$R2" \
  '{session_id:$s,transcript_path:"/dev/null",cwd:$c,hook_event_name:"Stop",stop_hook_active:false}')
fire "$SID" "$STOP_EV"
expect_eq "an unrelated event (Stop) exits 0" "0" "$HOOK_RC"
if [ -e "$M2" ]; then no "…and writes NO marker" "marker appeared"; else ok "…and writes NO marker"; fi

# ============================================================
echo ""
echo "=== E3 (AC-3) — the TYPED path: UserPromptExpansion by command name ==="
# ============================================================
#
# R-A §5.2 proved a typed /bionic:canonical-sdlc is NOT a Skill tool call and NOT a
# plain UserPromptSubmit prompt: it arrives as a command expansion whose `command_name`
# is the match key. The docs' matcher table says as much — `UserPromptExpansion` |
# command name | your skill or command names.

R3="$(make_repo e3)"
M3="$(marker_path "$R3" "$SID")"

for name in canonical-sdlc bionic:canonical-sdlc /canonical-sdlc /bionic:canonical-sdlc; do
  rm -f "$M3"
  fire "$SID" "$(expansion_payload "$SID" "$R3" "$name")"
  expect_eq "the expansion of [$name] exits 0" "0" "$HOOK_RC"
  expect_empty "…and prints nothing on stdout" "$HOOK_OUT"
  if [ -f "$M3" ]; then ok "…and engages the session"; else
    no "…and engages the session" "no file at $M3"
  fi
done

for name in loop bionic:help bionic:doctor clear canonical-sdlc-notes ""; do
  rm -f "$M3"
  fire "$SID" "$(expansion_payload "$SID" "$R3" "$name")"
  if [ -e "$M3" ]; then no "the expansion of [$name] writes NO marker" "marker appeared"; else
    ok "the expansion of [$name] writes NO marker"
  fi
  fire "$SID" "$(expansion_payload "$SID" "$R3" "bionic:canonical-sdlc")"
  if [ -f "$M3" ]; then ok "…paired: the real command on the same fixture DOES engage"; else
    no "…paired: the real command on the same fixture DOES engage" "the negative above was vacuous"
  fi
done

# ============================================================
echo ""
echo "=== E4 (AC-4) — engaged_session: the predicate every wall reads ==="
# ============================================================

R4="$(make_repo e4)"
M4="$(marker_path "$R4" "$SID")"

call_engaged "$R4" "$SID"
expect_eq "no marker on disk -> engaged_session is FALSE" "1" "$ES_ST"

fire "$SID" "$(skill_payload "$SID" "$R4" "bionic:canonical-sdlc")"
call_engaged "$R4" "$SID"
expect_eq "a regular file at the marker path -> TRUE" "0" "$ES_ST"

# A FOREIGN session's marker is not this session's engagement. The path is keyed by
# sid precisely so one session cannot arm another's walls.
call_engaged "$R4" "$OTHER_SID"
expect_eq "another session's sid -> FALSE even though a marker exists" "1" "$ES_ST"

# The `unknown` fallback farm-out-reminder and context-spend substitute for a missing
# sid must never name a readable marker: `.bionic/tmp/engaged-unknown.state` would
# otherwise engage every session that lost its id.
printf 'plan=none\nengaged_at=2026-09-03T00:00:00Z\n' > "$R4/.bionic/tmp/engaged-unknown.state"
call_engaged "$R4" "unknown"
expect_eq "the sid 'unknown' -> FALSE even with engaged-unknown.state planted" "1" "$ES_ST"

call_engaged "$R4" ""
expect_eq "an empty sid -> FALSE" "1" "$ES_ST"

# A sid carrying a path separator must never escape .bionic/tmp.
printf 'plan=none\n' > "$SANDBOX/escape.state"
call_engaged "$R4" "../../../escape"
expect_eq "a sid carrying '/' -> FALSE (no traversal)" "1" "$ES_ST"
call_engaged "$R4" "a b"
expect_eq "a sid carrying a space -> FALSE" "1" "$ES_ST"

# A SYMLINK at the marker path is refused before it is followed — the guard idiom
# patrol-revive.sh uses on its stamp. A hostile repo may CLOSE a wall and must never
# OPEN one, and this is the one artifact whose presence opens them.
rm -f "$M4"
printf 'plan=none\nengaged_at=2026-09-03T00:00:00Z\n' > "$SANDBOX/planted.state"
ln -s "$SANDBOX/planted.state" "$M4"
call_engaged "$R4" "$SID"
expect_eq "a symlink at the marker path -> FALSE (refused, not followed)" "1" "$ES_ST"

# …and the hook refuses to write through it, rather than clobbering the target.
fire "$SID" "$(skill_payload "$SID" "$R4" "bionic:canonical-sdlc")"
expect_eq "the hook exits 0 on a symlinked marker path" "0" "$HOOK_RC"
if [ -L "$M4" ]; then ok "…and leaves the symlink in place"; else no "…and leaves the symlink in place"; fi
expect_eq "…and does not write through it" \
  "plan=none" "$(head -1 "$SANDBOX/planted.state")"
rm -f "$M4"

# A DIRECTORY at the marker path is not a regular file either.
mkdir -p "$M4"
call_engaged "$R4" "$SID"
expect_eq "a directory at the marker path -> FALSE" "1" "$ES_ST"
rmdir "$M4"

# ============================================================
echo ""
echo "=== E5 (AC-17) — registration and the loader idiom ==="
# ============================================================

HJ_ROWS=$(jq -r '
  .hooks | to_entries[] | .key as $ev | .value[]
  | (.matcher // "") as $mt
  | .hooks[] | "\($ev)|\($mt)|\(.command)|\(.timeout // "")"
' "$HOOKS_JSON" 2>/dev/null)

expect_contains "hooks.json registers engage.sh on PreToolUse matcher Skill" \
  'PreToolUse|Skill|${CLAUDE_PLUGIN_ROOT}/hooks/engage.sh|10' "$HJ_ROWS"
expect_contains "hooks.json registers engage.sh on UserPromptExpansion" \
  'UserPromptExpansion||${CLAUDE_PLUGIN_ROOT}/hooks/engage.sh|10' "$HJ_ROWS"
expect_eq "engage.sh is registered exactly twice, and no more" "2" \
  "$(printf '%s\n' "$HJ_ROWS" | /usr/bin/grep -c 'engage\.sh')"

# The loader idiom, byte for byte against the pin — the same comparison
# cross-gate §N.1 and hook-adoption §1 make, restated here so this suite fails on
# its own subject rather than only in the roster suites.
N_BLOCK="$( . "$LOADER_LIB" && bionic_loader_pin )"
BLOCK_OF=$(awk '/^# --- bionic-loader\/v2 BEGIN$/{f=1} f{print} f&&/^# --- bionic-loader\/v2 END$/{exit}' "$HOOK")
expect_eq "engage.sh carries the canonical loader block, byte for byte" "$N_BLOCK" "$BLOCK_OF"

WANT_LINE=$(awk '/^# --- bionic-loader\/v2 BEGIN$/{print prev; exit} {prev=$0}' "$HOOK")
case "$WANT_LINE" in
  BIONIC_LIB_WANT=\"*\") ok "engage.sh declares BIONIC_LIB_WANT above the block" ;;
  *) no "engage.sh declares BIONIC_LIB_WANT above the block" "line above BEGIN was: [$WANT_LINE]" ;;
esac
WANTS=$(printf '%s' "$WANT_LINE" | sed -e 's/^BIONIC_LIB_WANT="//' -e 's/"$//')
SOURCED=$(/usr/bin/grep -oE '^\. "\$BIONIC_LIB/[a-z.-]+\.sh"' "$HOOK" \
  | sed -E 's|^\. "\$BIONIC_LIB/||; s|"$||' | sort | tr '\n' ' ' | sed 's/ $//')
expect_eq "engage.sh sources exactly the libraries it wants" \
  "$(printf '%s' "$WANTS" | tr ' ' '\n' | sort | tr '\n' ' ' | sed 's/ $//')" "$SOURCED"

# The trigger must never block an invocation: it fails OPEN on a missing library.
expect_eq "engage.sh fails OPEN on a missing library (and only that)" "0 1" \
  "$(/usr/bin/grep -c 'loader_fail_closed "' "$HOOK") $(/usr/bin/grep -c 'loader_fail_open "' "$HOOK")"

# It resolves its root and its session id through the library, like every other reader.
expect_eq "engage.sh resolves its root through the library" "yes" \
  "$(/usr/bin/grep -q 'project_root "' "$HOOK" && echo yes || echo no)"
expect_eq "engage.sh takes its session id from lib/session.sh" "yes" \
  "$(/usr/bin/grep -q 'session_id "' "$HOOK" && echo yes || echo no)"
expect_eq "engage.sh defines no private root resolver" "" \
  "$(/usr/bin/grep -l '^resolve_project_root()' "$HOOK" 2>/dev/null)"

# ============================================================
echo ""
echo "=== E6 (AC-18) — engagement precedes the plan, and precedes the tree ==="
# ============================================================

# (a) A run's Step 0 happens BEFORE its plan file exists. The marker is still written,
# with plan=none, and the walls bind once the plan lands — without re-invocation.
R6="$(make_repo_planless)"
M6="$(marker_path "$R6" "$SID")"
fire "$SID" "$(skill_payload "$SID" "$R6" "bionic:canonical-sdlc")"
expect_eq "with no plan on disk the hook still exits 0" "0" "$HOOK_RC"
if [ -f "$M6" ]; then ok "…and still writes the marker"; else no "…and still writes the marker" "no file at $M6"; fi
expect_eq "…whose plan field reads none" "plan=none" "$(head -1 "$M6" 2>/dev/null)"
call_engaged "$R6" "$SID"
expect_eq "…and engaged_session is TRUE with no run open" "0" "$ES_ST"

# (b) A FRESH project with no .bionic at all. Nothing else in the payload owns tree
# creation, so without this the first engagement of a new project runs unwalled.
R7="$(make_repo_fresh)"
M7="$(marker_path "$R7" "$SID")"
if [ -e "$R7/.bionic" ]; then no "the fresh fixture starts with no .bionic (non-vacuity)" "it has one"; else
  ok "the fresh fixture starts with no .bionic (non-vacuity)"
fi
fire "$SID" "$(skill_payload "$SID" "$R7" "bionic:canonical-sdlc")"
expect_eq "a fresh project exits 0" "0" "$HOOK_RC"
if [ -d "$R7/.bionic/tmp" ]; then ok "…and the .bionic/tmp tree is created"; else
  no "…and the .bionic/tmp tree is created" "no directory at $R7/.bionic/tmp"
fi
expect_eq "…and .bionic/.gitignore is exactly '*'" "*" "$(cat "$R7/.bionic/.gitignore" 2>/dev/null)"
if [ -f "$M7" ]; then ok "…and the marker lands in the new tree"; else
  no "…and the marker lands in the new tree" "no file at $M7"
fi

# The tree is created ONCE and an existing .gitignore is never rewritten.
printf 'kept-by-the-project\n' > "$R7/.bionic/.gitignore"
fire "$SID" "$(skill_payload "$SID" "$R7" "bionic:canonical-sdlc")"
expect_eq "a second engagement leaves an existing .bionic/.gitignore alone" \
  "kept-by-the-project" "$(cat "$R7/.bionic/.gitignore" 2>/dev/null)"

# (c) A .bionic that is a SYMLINK is refused outright: the hook neither follows it nor
# writes into whatever it points at.
R8="$(make_repo_fresh)"
mkdir -p "$SANDBOX/elsewhere/tmp"
ln -s "$SANDBOX/elsewhere" "$R8/.bionic"
fire "$SID" "$(skill_payload "$SID" "$R8" "bionic:canonical-sdlc")"
expect_eq "a symlinked .bionic exits 0" "0" "$HOOK_RC"
if [ -e "$SANDBOX/elsewhere/tmp/engaged-$SID.state" ]; then
  no "…and nothing is written through the symlink" "marker appeared in the link target"
else
  ok "…and nothing is written through the symlink"
fi

# (d) A .bionic/tmp that is a FILE, not a directory: report, never block.
R9="$(make_repo_fresh)"
mkdir -p "$R9/.bionic"
printf 'not a directory\n' > "$R9/.bionic/tmp"
fire "$SID" "$(skill_payload "$SID" "$R9" "bionic:canonical-sdlc")"
expect_eq "a non-directory .bionic/tmp exits 0 — reported, never blocking" "0" "$HOOK_RC"
expect_empty "…and prints nothing on stdout" "$HOOK_OUT"
expect_eq "…and leaves the file alone" "not a directory" "$(cat "$R9/.bionic/tmp" 2>/dev/null)"

# ============================================================
echo ""
echo "=== E7 — the sid must resolve, or nothing is written ==="
# ============================================================

RA="$(make_repo e7)"
# No sid anywhere: not in the env, not in the payload. `session_id` returns 1 and the
# hook has no file to name.
NOSID=$(jq -nc --arg c "$RA" \
  '{transcript_path:"/dev/null",cwd:$c,hook_event_name:"PreToolUse",
    tool_name:"Skill",tool_input:{skill:"bionic:canonical-sdlc"}}')
HOOK_OUT=$(env -u CLAUDE_PROJECT_DIR -u CLAUDE_CODE_SESSION_ID bash "$HOOK" <<< "$NOSID" 2>/dev/null)
HOOK_RC=$?
expect_eq "a payload with no session id anywhere exits 0" "0" "$HOOK_RC"
expect_eq "…and writes no marker at all" "0" \
  "$(find "$RA/.bionic/tmp" -maxdepth 1 -name 'engaged-*' 2>/dev/null | wc -l | tr -d ' ')"

# The env value is primary and the payload is a witness: a divergence keys the marker
# to the env id, never the payload's.
fire "$SID" "$(skill_payload "$OTHER_SID" "$RA" "bionic:canonical-sdlc")"
if [ -f "$(marker_path "$RA" "$SID")" ]; then ok "on divergence the marker is keyed to the ENV id"; else
  no "on divergence the marker is keyed to the ENV id" "no file at $(marker_path "$RA" "$SID")"
fi
if [ -e "$(marker_path "$RA" "$OTHER_SID")" ]; then
  no "…and not to the payload's witness id" "a marker appeared for the payload id"
else
  ok "…and not to the payload's witness id"
fi

# A malformed payload is not a crash.
HOOK_OUT=$(env -u CLAUDE_PROJECT_DIR CLAUDE_CODE_SESSION_ID="$SID" bash "$HOOK" <<< 'not json at all' 2>/dev/null)
HOOK_RC=$?
expect_eq "a non-JSON payload exits 0" "0" "$HOOK_RC"
expect_empty "…and prints nothing" "$HOOK_OUT"

# ============================================================
echo ""
echo "========================================"
echo "engage.test.sh: $PASS/$TOTAL passed, $FAIL failed"
echo "========================================"
[ "$FAIL" -eq 0 ]
