#!/bin/bash
# tests/doctor-restart.test.sh — doctor.sh's "restart needed" row and the tick's restart line
# (bionic 1.4.0 fold-in, spec AC-37, plan task DOCTOR-RESTART; wave-35 T5 REQ-4 AC-4.5; from
# wave-36 T2 a content fact: spec D7, AC-1.3, ADR-055).
#
# THE CONTRACT UNDER TEST. The CLI snapshots hooks/hooks.json, the skills, the role files and
# the commands once, at process start; a change on disk afterward registers nothing in a process
# already running. hooks/session-start.sh writes what the session loaded to
# `.bionic/tmp/loaded-<sid>.state` (wave-36 T1): `root=`, `commit=` for a checkout, `started=`,
# and one `<sha256> <path>` line per loaded file. Doctor's reader, `_doctor_restart_stale`, takes
# each live CLI session whose cwd is THIS project, re-hashes the recorded set in the tree a restart
# of that session would load, and names each class whose hash moved (hooks, skills, agents,
# commands): one `✗ restart needed` row naming the pid and the classes, plus a FIX line telling the
# operator to exit and restart. A file whose content is unchanged prints nothing, whatever its
# mtime says (§MANIFEST, MAN-1). A session with no record, no session file for this cwd, or a
# session file naming a DIFFERENT cwd — all silent (format rule: a healthy state prints nothing
# new). When the registry's install is newer than the record, the line says `or reloaded since
# <ISO>` (the spec's Worth-your-eye default: /reload-plugins firing the start hook is unverified).
# The tick prints its own session's line from the same reader (`doctor.sh --restart-lines`).
#
# HERMETIC, SAME POSTURE AS doctor-fleet.test.sh. Doctor runs with its cwd inside a fixture
# project holding its own .bionic/, so project_root answers the fixture and nothing reads this
# checkout's real state. The "live" session names this test's own pid ($$), alive by
# construction. The plugin tree is a SEPARATE fixture git repository named by a fixture
# plugins/installed_plugins.json registry entry — never this checkout's own tree. The load
# records are written in the writer's shape (A-T1-2) by `write_record`, and once (MAN-9) by the
# real start hook, so the reader is proved against what the writer writes.
#
# PHYSICAL PATHS. project_root canonicalises through `pwd -P` (lib/root.sh); on macOS /tmp is a
# symlink to /private/tmp, so a session's `cwd` field and a record's `root=` must be the
# CANONICAL path. PROJ_REAL below is the physical path.
#
# ASSERTION-HELPER RACE. No `printf | grep -q` anywhere below (tests/
# assert-helper-race.test.sh): containment is bash `[[ == * ]]` in-process.
#
# Usage: bash tests/doctor-restart.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"

REPO="${BIONIC_SCRIPTS_DIR}"
PAYLOAD="${REPO}/payload"
DOCTOR_SH="${PAYLOAD}/scripts/doctor.sh"

command -v jq >/dev/null 2>&1 || { echo "doctor-restart.test.sh: jq is required"; exit 1; }
command -v git >/dev/null 2>&1 || { echo "doctor-restart.test.sh: git is required"; exit 1; }
command -v shasum >/dev/null 2>&1 || command -v sha256sum >/dev/null 2>&1 \
  || { echo "doctor-restart.test.sh: shasum or sha256sum is required"; exit 1; }

TMP="$(mktemp -d /tmp/bionic-doctor-restart.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

CHOME="${TMP}/claude-home"
mkdir -p "${CHOME}/plugins" "${CHOME}/sessions"
PROJ="${TMP}/proj"
mkdir -p "${PROJ}/.bionic/tmp"
PROJ_REAL="$(cd "$PROJ" && pwd -P)"
FIXTURE_RC="${TMP}/dot.zshrc"
: > "$FIXTURE_RC"

LIVE_PID=$$
SID_LIVE="fixture-${LIVE_PID}"
REC="${PROJ}/.bionic/tmp/loaded-${SID_LIVE}.state"

# ---------- fixture builders ----------

# A git repository standing in for "the plugin tree the CLI loads", holding one file of each of
# the four loaded classes. doctor.sh's DOCTOR_INSTALL_PATH resolution (`_doctor_is_repo`)
# requires a real repository; `git init` with no commit already satisfies it.
make_plugin_tree() {  # [<dir>] -> dir on stdout (physical)
  local dir="${1:-}"
  if [ -n "$dir" ]; then mkdir -p "$dir"; else dir="$(mktemp -d -p "$TMP")"; fi
  git init -q "$dir" >/dev/null 2>&1
  mkdir -p "$dir/hooks" "$dir/skills/demo" "$dir/agents" "$dir/commands"
  printf '{}' > "$dir/hooks/hooks.json"
  printf 'skill\n' > "$dir/skills/demo/SKILL.md"
  printf 'role\n' > "$dir/agents/critic.md"
  printf 'command\n' > "$dir/commands/x.md"
  (cd "$dir" && pwd -P)
}

sha_line() {  # <file> -> its sha256
  local out
  if command -v shasum >/dev/null 2>&1; then out="$(shasum -a 256 "$1")"; else out="$(sha256sum "$1")"; fi
  printf '%s' "${out%% *}"
}

# The load record in the writer's shape (hooks/session-start.sh ss_load_record; A-T1-2):
# root=, commit= when given, started=, then `<sha256> <path>` sorted by path under LC_ALL=C.
REC_STARTED="2026-08-27T14:00:00Z"
write_record() {  # <sid> <tree> [<commit>] -> PROJ/.bionic/tmp/loaded-<sid>.state
  local sid="$1" tree="$2" commit="${3:-}" p
  {
    printf 'root=%s\n' "$tree"
    [ -n "$commit" ] && printf 'commit=%s\n' "$commit"
    printf 'started=%s\n' "$REC_STARTED"
    ( cd "$tree" && { [ -f hooks/hooks.json ] && printf '%s\n' hooks/hooks.json
        find -L skills agents -type f -name '*.md' 2>/dev/null
        find -L commands -maxdepth 1 -type f -name '*.md' 2>/dev/null; } | LC_ALL=C sort ) \
      | while IFS= read -r p; do printf '%s %s\n' "$(sha_line "$tree/$p")" "$p"; done
  } > "${PROJ}/.bionic/tmp/loaded-${sid}.state"
}
manifest_lines() {  # <record> -> how many `<64-hex> <path>` lines it holds
  /usr/bin/grep -cE '^[0-9a-f]{64} ' "$1" 2>/dev/null | tr -d ' '
}

write_installed_plugins() {  # <installPath> [<lastUpdated>]
  jq -nc --arg path "$1" --arg at "${2:-}" \
    '{plugins:{"bionic@bionic":[({installPath:$path} + (if $at == "" then {} else {lastUpdated:$at} end))]}}' \
    > "${CHOME}/plugins/installed_plugins.json"
}

# The real CLI's own session shape, named by pid.
BEFORE_MS=1788000000000    # 2026-08-27T13:00:00Z, before every fixture mtime below
write_session() {  # <pid> <cwd>
  jq -nc --arg cwd "$2" --argjson pid "$1" --argjson started "$BEFORE_MS" \
    '{pid:$pid, sessionId:("fixture-" + ($pid|tostring)), cwd:$cwd, startedAt:$started, status:"busy"}' \
    > "${CHOME}/sessions/$1.json"
}

# `touch -t` reads its spec in LOCAL time, so the spec is generated with `date -r` (also local).
set_mtime() {  # <file> <epoch-seconds>
  touch -t "$(date -r "$2" +%Y%m%d%H%M.%S)" "$1"
}
mtime_of() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null; }

run_doctor() {
  ( cd "$PROJ" && HOME="$TMP" BIONIC_SHELL_RC="$FIXTURE_RC" \
      BIONIC_CLAUDE_HOME="$CHOME" BIONIC_PLUGIN_ROOT="$PAYLOAD" \
      BIONIC_DOCTOR_PROBE_SECONDS=15 \
      bash "$DOCTOR_SH" < /dev/null 2>&1 )
}
run_lines() {  # -> doctor.sh --restart-lines in PROJ
  ( cd "$PROJ" && HOME="$TMP" BIONIC_SHELL_RC="$FIXTURE_RC" \
      BIONIC_CLAUDE_HOME="$CHOME" BIONIC_PLUGIN_ROOT="$PAYLOAD" \
      bash "$DOCTOR_SH" --restart-lines < /dev/null 2>&1 )
}
POKER="${REPO}/hooks/session-poker.sh"
run_tick() {  # -> the tick's output in PROJ, as this live session (engaged and armed first)
  : > "${PROJ}/.bionic/tmp/engaged-${SID_LIVE}.state"
  ( cd "$PROJ" && HOME="$TMP" BIONIC_SHELL_RC="$FIXTURE_RC" BIONIC_CLAUDE_HOME="$CHOME" \
      BIONIC_PLUGIN_ROOT="$PAYLOAD" CLAUDE_CODE_SESSION_ID="$SID_LIVE" bash "$POKER" arm >/dev/null 2>&1
    rm -f "${PROJ}/.bionic/tmp/tick-digest-${SID_LIVE}.state"
    HOME="$TMP" BIONIC_SHELL_RC="$FIXTURE_RC" BIONIC_CLAUDE_HOME="$CHOME" \
      BIONIC_PLUGIN_ROOT="$PAYLOAD" CLAUDE_CODE_SESSION_ID="$SID_LIVE" bash "$POKER" tick < /dev/null 2>&1 )
}
count_of() {  # <needle> <text> -> lines of text holding needle
  local n=0 l
  while IFS= read -r l; do [[ "$l" == *"$1"* ]] && n=$((n + 1)); done <<< "$2"
  printf '%s' "$n"
}

section "Section 1: a recorded file's content moved — restart needed"

TREE1="$(make_plugin_tree)"
write_installed_plugins "$TREE1"
write_session "$LIVE_PID" "$PROJ_REAL"
write_record "$SID_LIVE" "$TREE1"
expect_eq "0: precondition — the record holds one manifest line per loaded file" "4" "$(manifest_lines "$REC")"
printf '{"hooks":{}}' > "$TREE1/hooks/hooks.json"

OUT1="$(run_doctor)"

expect_match "1: the row fires" "*✗ restart needed*" "$OUT1"
expect_match "2: it names the pid and the class whose content moved" \
  "*restart needed*pid ${LIVE_PID} — hooks changed since load*" "$OUT1"
expect_match "3: a fix line tells the operator to exit and restart" \
  "*exit claude and start it again*" "$OUT1"
expect_match "4: the fix line cites what the process loaded, and when" \
  "*pid ${LIVE_PID} loaded hooks at 2026-08-27 14:00Z*" "$OUT1"

section "Section 2: nothing the session loaded moved — silent"

TREE2="$(make_plugin_tree)"
write_installed_plugins "$TREE2"
write_record "$SID_LIVE" "$TREE2"

OUT2="$(run_doctor)"

expect_match "5a: doctor ran its PROJECT section" "*PROJECT*" "$OUT2"
expect_no_match "5: no restart-needed row" "*restart needed*" "$OUT2"
expect_no_match "6: no matching fix line" "*exit claude and start it again*" "$OUT2"

section "Section 3: no session file for this cwd — silent"

printf 'moved\n' > "$TREE2/skills/demo/SKILL.md"   # a content move that WOULD fire the row
mv "${CHOME}/sessions/${LIVE_PID}.json" "${TMP}/session.parked"
OUT3="$(run_doctor)"
mv "${TMP}/session.parked" "${CHOME}/sessions/${LIVE_PID}.json"
OUT3B="$(run_doctor)"

expect_match "7a: with the session file back, the same fixture fires the row" "*restart needed*pid ${LIVE_PID} — skills*" "$OUT3B"
expect_match "7b: without it, doctor still ran its PROJECT section" "*PROJECT*" "$OUT3"
expect_no_match "7: no restart-needed row with no session file" "*restart needed*" "$OUT3"

section "Section 4: a session file for ANOTHER cwd is ignored"

ELSEWHERE="${TMP}/elsewhere"
mkdir -p "$ELSEWHERE"
ELSEWHERE_REAL="$(cd "$ELSEWHERE" && pwd -P)"
write_session "$LIVE_PID" "$ELSEWHERE_REAL"   # the content move above WOULD fire the row
OUT4="$(run_doctor)"

expect_match "8a: doctor ran its PROJECT section" "*PROJECT*" "$OUT4"
expect_no_match "8: a session naming a different cwd is not this project's row" \
  "*restart needed*" "$OUT4"
write_session "$LIVE_PID" "$PROJ_REAL"

section "Section 5 §MANIFEST: restart needed is a content difference, named by class (wave-36 T2; D7, AC-1.3)"

# A reinstall, or a branch edit under --plugin-dir, rewrites files the CLI holds as they were at
# its start. Through wave-35 the row compared mtimes against the session's startedAt, so an
# identical-content copy (rsync -a, git archive | tar -x, the CLI's own reinstall) told the
# operator to restart for nothing. Now the recorded set is re-hashed and each class whose hash
# moved is named; the tick prints its one line from the same reader.
TREE5="$(make_plugin_tree)"
write_installed_plugins "$TREE5"
write_record "$SID_LIVE" "$TREE5"
OUT5Q="$(run_doctor)"
TICK5Q="$(run_tick)"
expect_match "MAN-0 precondition: nothing moved, doctor runs its PROJECT section" "*PROJECT*" "$OUT5Q"
expect_no_match "MAN-0b …and the restart row is silent" "*restart needed*" "$OUT5Q"
expect_match "MAN-0c precondition: the tick ran in the fixture (its decision line)" "*poker-tick/v1|*" "$TICK5Q"
expect_no_match "MAN-0d …and prints no restart line" "*restart needed*" "$TICK5Q"

# MAN-1: every loaded file stamped an hour after the session started, the content untouched.
LATE=$(( BEFORE_MS / 1000 + 7200 ))
for f in hooks/hooks.json skills/demo/SKILL.md agents/critic.md commands/x.md; do set_mtime "$TREE5/$f" "$LATE"; done
MOVED=0
for f in hooks/hooks.json skills/demo/SKILL.md agents/critic.md commands/x.md; do
  [ "$(mtime_of "$TREE5/$f")" = "$LATE" ] && MOVED=$((MOVED + 1))
done
expect_eq "MAN-1a precondition: touch -t moved every loaded file's mtime past the session's start" "4" "$MOVED"
OUT51="$(run_doctor)"
TICK51="$(run_tick)"
expect_match "MAN-1b doctor ran its PROJECT section" "*PROJECT*" "$OUT51"
expect_no_match "MAN-1 AC-1.3 an mtime-only change prints no restart row" "*restart needed*" "$OUT51"
expect_match "MAN-1c the tick ran (its decision line)" "*poker-tick/v1|*" "$TICK51"
expect_no_match "MAN-1d …and prints no restart line" "*restart needed*" "$TICK51"

printf 'skill, edited\n' > "$TREE5/skills/demo/SKILL.md"
OUT52="$(run_doctor)"
TICK52="$(run_tick)"
expect_match "MAN-2 AC-1.3 a skill's content moved: the row names skills" \
  "*✗ restart needed*pid ${LIVE_PID} — skills changed since load*" "$OUT52"
expect_match "MAN-2b …and its fix line names the same class" \
  "*pid ${LIVE_PID} loaded skills at 2026-08-27 14:00Z → exit claude and start it again*" "$OUT52"
expect_match "MAN-2c the tick prints the restart line from the same reader, naming the class" \
  "*poker: restart needed — skills changed after this session loaded them (pid ${LIVE_PID}): exit claude and start it again*" "$TICK52"
expect_eq "MAN-2d …one line" "1" "$(count_of "restart needed" "$TICK52")"
expect_no_match "MAN-2e only the class that moved is named" "*restart needed*pid ${LIVE_PID} — skills, *" "$OUT52"

printf 'skill\n' > "$TREE5/skills/demo/SKILL.md"     # the recorded content back (a new mtime)
OUT53Q="$(run_doctor)"
expect_match "MAN-3a the content back, the mtime new: PROJECT printed" "*PROJECT*" "$OUT53Q"
expect_no_match "MAN-3b …and no restart row" "*restart needed*" "$OUT53Q"
printf 'role, edited\n' > "$TREE5/agents/critic.md"
OUT53="$(run_doctor)"
TICK53="$(run_tick)"
expect_match "MAN-3 a role file's content moved: the row names agents" "*restart needed*pid ${LIVE_PID} — agents changed since load*" "$OUT53"
expect_match "MAN-3c …and the tick names it" "*poker: restart needed — agents changed after this session loaded them*" "$TICK53"

printf 'role\n' > "$TREE5/agents/critic.md"
printf 'command, edited\n' > "$TREE5/commands/x.md"
OUT54="$(run_doctor)"
TICK54="$(run_tick)"
expect_match "MAN-4 AC-1.3 commands/x.md's content moved: the row names commands" \
  "*restart needed*pid ${LIVE_PID} — commands changed since load*" "$OUT54"
expect_match "MAN-4b …and the tick names it" "*poker: restart needed — commands changed after this session loaded them*" "$TICK54"

printf '{"edited":1}' > "$TREE5/hooks/hooks.json"
printf 'skill, edited\n' > "$TREE5/skills/demo/SKILL.md"
OUT55="$(run_doctor)"
expect_match "MAN-5 three classes moved: one row names each, in the order hooks, skills, agents, commands" \
  "*restart needed*pid ${LIVE_PID} — hooks, skills, commands changed since load*" "$OUT55"
expect_eq "MAN-5b …one row for the one session" "1" "$(count_of "✗ restart needed" "$OUT55")"

printf '{}' > "$TREE5/hooks/hooks.json"; printf 'skill\n' > "$TREE5/skills/demo/SKILL.md"; printf 'command\n' > "$TREE5/commands/x.md"
rm -f "$TREE5/agents/critic.md"
OUT56="$(run_doctor)"
expect_match "MAN-6 a recorded file removed is a move: the row names agents" \
  "*restart needed*pid ${LIVE_PID} — agents changed since load*" "$OUT56"
printf 'role\n' > "$TREE5/agents/critic.md"

# MAN-7: the registry's install newer than the record — a /reload-plugins may have loaded it
# without rewriting the record, so the line says so; older, and it says nothing of a reload.
printf 'skill, edited\n' > "$TREE5/skills/demo/SKILL.md"
write_installed_plugins "$TREE5" "2026-08-27T15:30:00.250Z"
OUT57="$(run_doctor)"
TICK57="$(run_tick)"
expect_match "MAN-7 the registry installed after the record: the fix line says or reloaded since <ISO>" \
  "*pid ${LIVE_PID} loaded skills, or reloaded since 2026-08-27 15:30Z → exit claude and start it again*" "$OUT57"
expect_match "MAN-7b …and so does the tick's line" \
  "*poker: restart needed — skills changed after this session loaded them, or reloaded since 2026-08-27T15:30:00Z (pid ${LIVE_PID}): exit claude and start it again*" "$TICK57"
write_installed_plugins "$TREE5" "2026-08-27T13:30:00.000Z"
OUT57B="$(run_doctor)"
expect_match "MAN-7c the registry installed before the record: the row still fires" "*restart needed*pid ${LIVE_PID} — skills*" "$OUT57B"
expect_no_match "MAN-7d …and says nothing of a reload" "*reloaded since*" "$OUT57B"
write_installed_plugins "$TREE5"

# MAN-8: a live session with no record says nothing — content cannot be compared with nothing.
mv "$REC" "${TMP}/record.parked"
OUT58="$(run_doctor)"
mv "${TMP}/record.parked" "$REC"
OUT58B="$(run_doctor)"
expect_match "MAN-8 the record back, the same fixture fires the row" "*restart needed*pid ${LIVE_PID} — skills*" "$OUT58B"
expect_match "MAN-8b without the record, doctor ran its PROJECT section" "*PROJECT*" "$OUT58"
expect_no_match "MAN-8c …and prints no restart row" "*restart needed*" "$OUT58"

# MAN-9: the record the real start hook writes is the record this reader reads. The hook is
# exec'd by its shebang, as the CLI runs it.
TREE9="$(make_plugin_tree)"
write_installed_plugins "$TREE9"
rm -f "$REC"
printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s","hook_event_name":"SessionStart","source":"startup"}' \
  "$SID_LIVE" "$TMP/t.jsonl" "$PROJ_REAL" \
  | ( cd "$PROJ_REAL" && HOME="$TMP" BIONIC_SHELL_RC="$FIXTURE_RC" BIONIC_CLAUDE_HOME="$CHOME" \
      CLAUDE_CODE_SESSION_ID="$SID_LIVE" CLAUDE_PLUGIN_ROOT="$TREE9" "${REPO}/hooks/session-start.sh" >/dev/null 2>&1 )
expect_eq "MAN-9a precondition: the start hook wrote the record, naming the tree and four files" \
  "root=${TREE9}|4" "$(/usr/bin/grep '^root=' "$REC" 2>/dev/null)|$(manifest_lines "$REC")"
OUT59Q="$(run_doctor)"
expect_match "MAN-9b doctor ran its PROJECT section" "*PROJECT*" "$OUT59Q"
expect_no_match "MAN-9c over the hook's own record, nothing moved: no row" "*restart needed*" "$OUT59Q"
printf 'command, edited\n' > "$TREE9/commands/x.md"
OUT59="$(run_doctor)"
expect_match "MAN-9 …and a command edited after it names commands" "*restart needed*pid ${LIVE_PID} — commands changed since load*" "$OUT59"

# MAN-10: the tree a restart would load. A session that loaded an installed version dir (no
# commit) restarts into the version dir the registry now names; one that runs a checkout in
# place (commit=) restarts into the same checkout, whatever the registry says.
CACHE="${TMP}/cache/bionic/bionic"
OLD="$(make_plugin_tree "$CACHE/1.0.0")"
NEW="$(make_plugin_tree "$CACHE/1.1.0")"
printf 'skill, released\n' > "$NEW/skills/demo/SKILL.md"
write_installed_plugins "$NEW"
write_record "$SID_LIVE" "$OLD"
OUT510="$(run_lines)"
expect_match "MAN-10 a session on installed 1.0.0, the registry at 1.1.0 with a skill moved: the reader names skills" \
  "*${SID_LIVE}*skills*" "$OUT510"
write_record "$SID_LIVE" "$OLD" "0123456789abcdef0123456789abcdef01234567"
OUT510B="$(run_lines)"
OUT510C="$(run_doctor)"
expect_match "MAN-10b the same session run in place: doctor ran its PROJECT section" "*PROJECT*" "$OUT510C"
expect_empty "MAN-10c …and the reader compares the checkout it loaded, which did not move" "$OUT510B"

finish
