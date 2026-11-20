#!/bin/bash
# tests/opening-line.test.sh — hooks/opening-line.sh, THE VERSION LINE THE TOOL SHOWS when the
# method is invoked.
#
# WHAT IT OWNS. On the method's typed command (UserPromptExpansion, `command_name`) and on the
# model's own Skill call (PreToolUse, `tool_input.skill`), the hook prints one JSON object,
# `{"systemMessage": "<line>"}`, the line being what payload/scripts/version.sh prints. The hooks
# reference (code.claude.com/docs/en/hooks, JSON output) reads `systemMessage` as a message shown
# to the user; plain stdout and `additionalContext` go to the model and show the person nothing.
# On every other name, on a payload that is no JSON, and when the version read fails or prints
# nothing, it prints nothing. It exits 0 on every path: it stands in front of the method's front
# door and must never refuse it.
#
# THE TWO NAME TESTS. The platform matches the typed path's `matcher` against `command_name`; a
# matcher holding any character outside letters, digits, `_`, `-`, spaces, `,` and `|` is a
# JavaScript regular expression tested unanchored ("Matcher patterns"), so the registration's
# matcher is anchored at both ends. On PreToolUse the matcher sees the tool's name, `Skill`, and
# the script reads the skill's name itself. §AGREE feeds hooks/engage.sh, the engagement trigger,
# and this hook the same names on both paths and holds their answers equal.
#
# NOT SHOWN HERE. How the window draws the line, and that the model is not handed it: only a live
# session shows either.
#
# THE SECTIONS, in the order the body runs them:
#
#   §TYPED          the typed command's payload: one object, the version line, no other key, exit 0.
#   §MODEL          the Skill call naming the method: the same; another skill and another tool: nothing.
#   §QUIET          no JSON, a failing version read, an empty one, no version command: nothing, exit 0.
#   §AGREE          engage.sh and this hook answer the same names alike, on both paths.
#   §REGISTRATION   hooks.json holds both entries; the typed matcher takes the method's names alone.
#
# FIXTURE FIDELITY (the rule of that name, .claude/rules/test-harness.md). The payloads are
# SYNTHESIZED in the field shapes Claude Code 2.1.329 delivered to a plugin hook on both events:
# `command_name` qualified as `<plugin>:<name>`, `command_args` apart from it, `tool_input.skill`.
# The shipped hook and the shipped version command answer §TYPED and §MODEL; a copy of the hook
# beside a stub version command answers the rows that need the version read to fail, and that
# copy prints the stub's line on the same fixture before each of those rows reads its silence.
#
# ANTI-VACUITY (the rule of that name). The version command's line is proved non-empty before any
# row compares against it; every silent row stands beside a row that printed the line through the
# same driver and the same reader; §AGREE counts the names both hooks took and refused, so a pair
# of hooks that answered nothing would agree and still go red.
#
# HERMETIC. Every project is a fixture under one mktemp sandbox, HOME and BIONIC_PLUGINS_DIR are
# pointed into it, and the hook is driven as a subprocess with JSON on stdin, as the platform
# delivers it.
#
# Usage: bash tests/opening-line.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
HOOK="$BIONIC_HOOKS_DIR/opening-line.sh"
ENGAGE="$BIONIC_HOOKS_DIR/engage.sh"
VERSION="$REPO_ROOT/payload/scripts/version.sh"
HOOKS_JSON="$BIONIC_HOOKS_DIR/hooks.json"

command -v jq >/dev/null 2>&1 || { echo "opening-line: jq absent — suite cannot run"; exit 1; }

SANDBOX="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/opening-line-test.XXXXXX")" && pwd -P)"
cleanup() { rm -rf "$SANDBOX"; }
trap cleanup EXIT
mkdir -p "$SANDBOX/home" "$SANDBOX/plugins" "$SANDBOX/proj"

SID="0be71e00-1111-2222-3333-444455556666"
STUB_LINE="bionic 9.9.9 (stub) · 0123abcd · /stub/payload"

# ---------- payload builders (field names: code.claude.com/docs/en/hooks) ----------

typed_payload() {  # <command_name>
  jq -nc --arg c "$SANDBOX/proj" --arg n "$1" --arg s "$SID" \
    '{session_id:$s,prompt_id:"p-1",cwd:$c,permission_mode:"default",hook_event_name:"UserPromptExpansion",
      expansion_type:"slash_command",command_name:$n,command_args:"start the run",command_source:"plugin",
      prompt:("/" + $n + " start the run")}'
}
skill_payload() {  # <skill>
  jq -nc --arg c "$SANDBOX/proj" --arg k "$1" --arg s "$SID" \
    '{session_id:$s,prompt_id:"p-1",cwd:$c,permission_mode:"default",hook_event_name:"PreToolUse",
      tool_name:"Skill",tool_input:{skill:$k},tool_use_id:"toolu_opening_line"}'
}

# ---------- driving it ----------
#
# drive <hook file> <stdin> -> OUT, RC. The cwd is the fixture project, as the platform runs a
# command hook in the session's current directory.
OUT=""; RC=0
drive() {
  OUT="$(printf '%s' "$2" | (cd "$SANDBOX/proj" && env HOME="$SANDBOX/home" BIONIC_PLUGINS_DIR="$SANDBOX/plugins" \
    CLAUDE_PROJECT_DIR= CLAUDE_CODE_SESSION_ID="$SID" /bin/bash "$1" 2>"$SANDBOX/.err"))"
  RC=$?
}
# the version command as the person's /bionic:version runs it, from the same cwd and environment
real_line() {
  (cd "$SANDBOX/proj" && env HOME="$SANDBOX/home" BIONIC_PLUGINS_DIR="$SANDBOX/plugins" \
    CLAUDE_PROJECT_DIR= CLAUDE_CODE_SESSION_ID="$SID" /bin/bash "$VERSION" 2>/dev/null)
}
objects() { printf '%s' "$OUT" | jq -s 'length' 2>/dev/null; }
keys_of() { printf '%s' "$OUT" | jq -r 'keys | join(",")' 2>/dev/null; }
message() { printf '%s' "$OUT" | jq -r '.systemMessage // empty' 2>/dev/null; }

# A plugin tree of the fixture's own: the shipped hook copied beside a stub version command, so
# the version read can be made to fail without touching the shipped one.
PLUG="$SANDBOX/plug"
mkdir -p "$PLUG/hooks" "$PLUG/scripts"
STUBHOOK="$PLUG/hooks/opening-line.sh"
cp "$HOOK" "$STUBHOOK" 2>/dev/null
stub_version() {  # <stdout> <exit>
  printf '#!/bin/bash\nprintf "%%s" %q\nexit %s\n' "$1" "$2" > "$PLUG/scripts/version.sh"
}

section "TYPED"

REAL="$(real_line)"
expect_nonempty "precondition: version.sh prints a line in the fixture" "$REAL"
expect_eq "precondition: the shipped hook is executable" "yes" "$([ -x "$HOOK" ] && echo yes || echo no)"
drive "$HOOK" "$(typed_payload bionic:canonical-sdlc)"
expect_status "typed /bionic:canonical-sdlc: exit 0" 0 "$RC"
expect_eq "…stdout is one JSON object" "1" "$(objects)"
expect_eq "…holding systemMessage and no other key" "systemMessage" "$(keys_of)"
expect_eq "…whose systemMessage is version.sh's line" "$REAL" "$(message)"
expect_eq "…on one line of stdout" "1" "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')"
expect_eq "…and nothing on stderr" "" "$(cat "$SANDBOX/.err")"

stub_version "$STUB_LINE" 0
drive "$STUBHOOK" "$(typed_payload bionic:canonical-sdlc)"
expect_eq "beside a stub version command: the stub's line, whole" "$STUB_LINE" "$(message)"
drive "$STUBHOOK" "$(typed_payload canonical-sdlc)"
expect_eq "typed bare canonical-sdlc: the same line" "$STUB_LINE" "$(message)"
drive "$STUBHOOK" "$(typed_payload bionic:sitrep)"
expect_status "typed /bionic:sitrep: exit 0" 0 "$RC"
expect_eq "…and nothing on stdout (the same fixture printed the line for the method above)" "" "$OUT"

section "MODEL"

drive "$HOOK" "$(skill_payload bionic:canonical-sdlc)"
expect_status "Skill call naming bionic:canonical-sdlc: exit 0" 0 "$RC"
expect_eq "…stdout is one JSON object" "1" "$(objects)"
expect_eq "…holding systemMessage and no other key" "systemMessage" "$(keys_of)"
expect_eq "…whose systemMessage is version.sh's line" "$REAL" "$(message)"

drive "$STUBHOOK" "$(skill_payload canonical-sdlc)"
expect_eq "Skill call naming bare canonical-sdlc: the line" "$STUB_LINE" "$(message)"
drive "$STUBHOOK" "$(skill_payload bionic:sitrep)"
expect_status "Skill call naming bionic:sitrep: exit 0" 0 "$RC"
expect_eq "…and nothing on stdout" "" "$OUT"
drive "$STUBHOOK" "$(skill_payload bionic:canonical-sdlc | jq -c '.tool_name = "Bash" | .tool_input = {command: "bionic:canonical-sdlc"}')"
expect_status "a Bash call on the same event: exit 0" 0 "$RC"
expect_eq "…and nothing on stdout" "" "$OUT"

section "QUIET"

stub_version "$STUB_LINE" 0
drive "$STUBHOOK" "$(typed_payload bionic:canonical-sdlc)"
expect_eq "positive: the stub that prints and exits 0 gives the line" "$STUB_LINE" "$(message)"
drive "$STUBHOOK" "not json {"
expect_status "a payload that is no JSON: exit 0" 0 "$RC"
expect_eq "…and nothing on stdout" "" "$OUT"
stub_version "$STUB_LINE" 2
drive "$STUBHOOK" "$(typed_payload bionic:canonical-sdlc)"
expect_status "the version command printing and failing: exit 0" 0 "$RC"
expect_eq "…and nothing on stdout" "" "$OUT"
stub_version "" 0
drive "$STUBHOOK" "$(typed_payload bionic:canonical-sdlc)"
expect_status "the version command printing nothing: exit 0" 0 "$RC"
expect_eq "…and nothing on stdout" "" "$OUT"
rm -f "$PLUG/scripts/version.sh"
drive "$STUBHOOK" "$(skill_payload bionic:canonical-sdlc)"
expect_status "no version command beside the hook: exit 0" 0 "$RC"
expect_eq "…and nothing on stdout" "" "$OUT"
stub_version "$STUB_LINE" 0
drive "$STUBHOOK" "$(skill_payload bionic:canonical-sdlc)"
expect_eq "positive again, the stub restored: the line" "$STUB_LINE" "$(message)"

section "AGREE"

# engaged <path: typed|skill> <name> -> yes|no: engage.sh's marker in a planless fixture of its own
engaged() {
  local d payload
  d="$(cd "$(mktemp -d "$SANDBOX/agree.XXXXXX")" && pwd -P)"; mkdir -p "$d/.bionic/tmp"
  if [ "$1" = typed ]; then payload="$(typed_payload "$2")"; else payload="$(skill_payload "$2")"; fi
  printf '%s' "$payload" | jq -c --arg c "$d" '.cwd = $c' \
    | env -u CLAUDE_PROJECT_DIR HOME="$SANDBOX/home" BIONIC_PLUGINS_DIR="$SANDBOX/plugins" CLAUDE_CODE_SESSION_ID="$SID" \
      /bin/bash "$ENGAGE" >/dev/null 2>&1
  [ -f "$d/.bionic/tmp/engaged-$SID.state" ] && echo yes || echo no
}
shown() {  # <path> <name> -> yes|no
  if [ "$1" = typed ]; then drive "$STUBHOOK" "$(typed_payload "$2")"; else drive "$STUBHOOK" "$(skill_payload "$2")"; fi
  [ "$(message)" = "$STUB_LINE" ] && echo yes || echo no
}
YES=0; NOS=0
for path in typed skill; do
  for name in bionic:canonical-sdlc canonical-sdlc /bionic:canonical-sdlc /canonical-sdlc \
              bionic:sitrep canonical-sdlc-x xbionic:canonical-sdlc other:canonical-sdlc bionic:canonical-sdlc-notes; do
    e="$(engaged "$path" "$name")"; s="$(shown "$path" "$name")"
    expect_eq "$path '$name': the line is shown exactly when engage.sh engages" "$e" "$s"
    case "$e$s" in yesyes) YES=$((YES + 1)) ;; nono) NOS=$((NOS + 1)) ;; esac
  done
done
expect_eq "the method's four spellings on both paths are agreed yes" "8" "$YES"
expect_eq "the five other names on both paths are agreed no" "10" "$NOS"

section "REGISTRATION"

ROWS="$(jq -r '.hooks | to_entries[] | .key as $ev | .value[] | (.matcher // "") as $mt
  | .hooks[] | "\($ev)|\($mt)|\(.command)|\(.timeout // "")"' "$HOOKS_JSON" 2>/dev/null)"
expect_contains "hooks.json is read: engage.sh's typed entry is there" \
  'UserPromptExpansion||${CLAUDE_PLUGIN_ROOT}/hooks/engage.sh|10' "$ROWS"
expect_contains "hooks.json registers opening-line.sh on UserPromptExpansion, matched to the method" \
  'UserPromptExpansion|^(bionic:)?canonical-sdlc$|${CLAUDE_PLUGIN_ROOT}/hooks/opening-line.sh|10' "$ROWS"
expect_contains "hooks.json registers opening-line.sh on PreToolUse, matcher Skill" \
  'PreToolUse|Skill|${CLAUDE_PLUGIN_ROOT}/hooks/opening-line.sh|10' "$ROWS"
expect_eq "opening-line.sh is registered exactly twice" "2" \
  "$(printf '%s\n' "$ROWS" | /usr/bin/grep -c 'opening-line\.sh')"

MATCHER="$(jq -r '.hooks.UserPromptExpansion[] | select(any(.hooks[]; .command | test("opening-line"))) | .matcher' \
  "$HOOKS_JSON" 2>/dev/null)"
expect_nonempty "the typed entry's matcher is read" "$MATCHER"
# The platform's rule: a matcher of only letters, digits, `_`, `-`, spaces, `,` and `|` is an exact
# list; anything else is a regular expression tested anywhere in the value.
case "$MATCHER" in
  *[!A-Za-z0-9_\ ,\|-]*) ok "the matcher is on the regular-expression path" ;;
  *) no "the matcher is on the regular-expression path" "read: [$MATCHER]" ;;
esac
takes() { [[ "$1" =~ $MATCHER ]] && echo takes || echo refuses; }
for name in bionic:canonical-sdlc canonical-sdlc; do
  expect_eq "the matcher takes '$name'" "takes" "$(takes "$name")"
done
for name in bionic:sitrep canonical-sdlc-x xbionic:canonical-sdlc other:canonical-sdlc; do
  expect_eq "the matcher refuses '$name'" "refuses" "$(takes "$name")"
done

finish
