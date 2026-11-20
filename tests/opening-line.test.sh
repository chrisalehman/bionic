#!/bin/bash
# tests/opening-line.test.sh — hooks/opening-line.sh prints {"systemMessage": <version.sh's line>} on the method's typed command and the model's Skill call, nothing on any other name, on no JSON or when the version read fails, and exits 0 always; hooks.json registers it on both paths.
# FIXTURE FIDELITY: payloads SYNTHESIZED in the fields Claude Code 2.1.329 gave a plugin hook; the shipped hook beside the shipped version.sh, and a copy beside a stub version command. Each case is one table line, read by one loop.
# ANTI-VACUITY: the version line is proved non-empty first, and every silent case runs beside a case that printed the line through the same driver and reader.
set -uo pipefail
. "$(dirname "$0")/lib/resolve-roots.sh"; . "$(dirname "$0")/lib/assert.sh"
command -v jq >/dev/null 2>&1 || { echo "opening-line: jq absent — suite cannot run"; exit 1; }
H="$BIONIC_HOOKS_DIR"; S="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/opening-line.XXXXXX")" && pwd -P)"; trap 'rm -rf "$S"' EXIT
mkdir -p "$S/home" "$S/plugins" "$S/proj" "$S/plug/hooks" "$S/plug/scripts"; cp "$H/opening-line.sh" "$S/plug/hooks/" 2>/dev/null
SID=0be71e00-1111-2222-3333-444455556666; STUB="bionic 9.9.9 (stub) · 0123abcd · /stub"; COPY="$S/plug/hooks/opening-line.sh"
pay() {  # <typed|skill|bash|raw> <name> [cwd] -> that event's payload, in the platform's field names
  [ "$1" = raw ] && { printf 'not json {'; return; }
  jq -nc --arg p "$1" --arg n "$2" --arg c "${3:-$S/proj}" --arg s "$SID" '{session_id:$s,cwd:$c,permission_mode:"default"} + if $p == "typed"
    then {hook_event_name:"UserPromptExpansion",expansion_type:"slash_command",command_name:$n,command_args:"go",command_source:"plugin",prompt:("/"+$n+" go")}
    else {hook_event_name:"PreToolUse",tool_name:(if $p == "skill" then "Skill" else "Bash" end),tool_input:{skill:$n,command:$n}} end'
}
run() { (cd "$S/proj" && env HOME="$S/home" BIONIC_PLUGINS_DIR="$S/plugins" CLAUDE_PROJECT_DIR= CLAUDE_CODE_SESSION_ID="$SID" /bin/bash "$@"); }
stub() {  # <ok|fail|empty|gone> -> the copy's version command prints the stub line, prints it and exits 2, prints nothing, or is not there
  rm -f "$S/plug/scripts/version.sh"; case "$1" in ok) echo "printf '%s' '$STUB'" ;; fail) echo "printf '%s' '$STUB'; exit 2" ;; empty) echo "exit 0" ;; *) return ;; esac > "$S/plug/scripts/version.sh"
}
REAL="$(run "$BIONIC_SCRIPTS_DIR/payload/scripts/version.sh" 2>/dev/null)"
cases() {  # <real|copy>|<stub state>|<path>|<name>|<line|->, one argument a case
  local f st p n want out rc c a
  for a in "$@"; do IFS='|' read -r f st p n want <<< "$a"
    if [ "$f" = real ]; then f="$H/opening-line.sh"; c="$p '$n'"; else f="$COPY"; stub "$st"; c="$p '$n', version command $st"; fi
    out="$(pay "$p" "$n" | run "$f" 2>"$S/err")"; rc=$?
    expect_status "$c: exit 0" 0 "$rc"
    if [ "$want" = - ]; then expect_eq "$c: nothing on stdout" "" "$out"; continue; fi
    expect_eq "$c: stdout is one JSON object" 1 "$(printf '%s' "$out" | jq -s length 2>/dev/null)"
    expect_eq "$c: …on one line" 1 "$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
    expect_eq "$c: …holding systemMessage and no other key" systemMessage "$(printf '%s' "$out" | jq -r 'keys | join(",")' 2>/dev/null)"
    expect_eq "$c: …whose systemMessage is the version command's line" "$([ "$f" = "$COPY" ] && echo "$STUB" || echo "$REAL")" "$(printf '%s' "$out" | jq -r '.systemMessage // empty' 2>/dev/null)"
    expect_eq "$c: …and nothing on stderr" "" "$(cat "$S/err")"
  done
}

section "TYPED"
expect_nonempty "precondition: version.sh prints a line in the fixture" "$REAL"
expect_eq "precondition: the shipped hook is executable" yes "$([ -x "$H/opening-line.sh" ] && echo yes || echo no)"
cases 'real|-|typed|bionic:canonical-sdlc|line' 'copy|ok|typed|bionic:canonical-sdlc|line' 'copy|ok|typed|canonical-sdlc|line' 'copy|ok|typed|bionic:sitrep|-'
section "MODEL"
cases 'real|-|skill|bionic:canonical-sdlc|line' 'copy|ok|skill|canonical-sdlc|line' 'copy|ok|skill|bionic:sitrep|-' 'copy|ok|bash|bionic:canonical-sdlc|-'
section "QUIET"
cases 'copy|ok|typed|bionic:canonical-sdlc|line' 'copy|ok|raw|-|-' 'copy|fail|typed|bionic:canonical-sdlc|-' 'copy|empty|typed|bionic:canonical-sdlc|-' \
  'copy|gone|skill|bionic:canonical-sdlc|-' 'copy|ok|skill|bionic:canonical-sdlc|line'

section "AGREE"
stub ok; Y=0; N=0
for p in typed skill; do for n in bionic:canonical-sdlc canonical-sdlc /bionic:canonical-sdlc /canonical-sdlc bionic:sitrep canonical-sdlc-x xbionic:canonical-sdlc other:canonical-sdlc bionic:canonical-sdlc-notes; do
  d="$(mktemp -d "$S/agree.XXXXXX")"; mkdir -p "$d/.bionic/tmp"; pay "$p" "$n" "$d" | run "$H/engage.sh" >/dev/null 2>&1
  e="$([ -f "$d/.bionic/tmp/engaged-$SID.state" ] && echo yes || echo no)"; s="$([ "$(pay "$p" "$n" | run "$COPY" 2>/dev/null | jq -r .systemMessage 2>/dev/null)" = "$STUB" ] && echo yes || echo no)"
  expect_eq "$p '$n': the line is shown exactly when engage.sh engages" "$e" "$s"; case "$e$s" in yesyes) Y=$((Y + 1)) ;; nono) N=$((N + 1)) ;; esac
done; done
expect_eq "the method's four spellings on both paths are agreed yes" 8 "$Y"; expect_eq "the five other names on both paths are agreed no" 10 "$N"

section "REGISTRATION"
R="$(jq -r '.hooks | to_entries[] | .key as $e | .value[] | (.matcher // "") as $m | .hooks[] | "\($e)|\($m)|\(.command)|\(.timeout // "")"' "$H/hooks.json" 2>/dev/null)"
for e in 'UserPromptExpansion||${CLAUDE_PLUGIN_ROOT}/hooks/engage.sh|10' 'UserPromptExpansion|^(bionic:)?canonical-sdlc$|${CLAUDE_PLUGIN_ROOT}/hooks/opening-line.sh|10' 'PreToolUse|Skill|${CLAUDE_PLUGIN_ROOT}/hooks/opening-line.sh|10'; do
  expect_contains "hooks.json holds $e" "$e" "$R"; done
expect_eq "opening-line.sh is registered exactly twice" 2 "$(printf '%s\n' "$R" | /usr/bin/grep -c 'opening-line\.sh')"
M="$(jq -r '.hooks.UserPromptExpansion[] | select(any(.hooks[]; .command | test("opening-line"))) | .matcher' "$H/hooks.json" 2>/dev/null)"; expect_nonempty "the typed entry's matcher is read" "$M"
# The platform reads a matcher holding any character outside letters, digits, _ - space , | as a regular expression tested anywhere in the value.
case "$M" in *[!A-Za-z0-9_\ ,\|-]*) ok "the matcher is on the regular-expression path" ;; *) no "the matcher is on the regular-expression path" "read: [$M]" ;; esac
for t in takes:bionic:canonical-sdlc takes:canonical-sdlc refuses:bionic:sitrep refuses:canonical-sdlc-x refuses:xbionic:canonical-sdlc refuses:other:canonical-sdlc; do
  expect_eq "the matcher ${t%%:*} '${t#*:}'" "${t%%:*}" "$([[ "${t#*:}" =~ $M ]] && echo takes || echo refuses)"; done
finish
