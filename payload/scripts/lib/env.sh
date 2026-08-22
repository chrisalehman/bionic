#!/bin/bash
# env.sh — the ONE home for bionic's environment settings (epic-17 wave-07 slice
# S4, spec R4 / AC-5, AC-6, AC-7).
#
# WHAT THIS FILE OWNS. The `env` object in the CLI's own settings.json: which
# names bionic puts there, what value each one carries, and the read/write/delete
# of them. Nothing else in the payload may reach into `.env` — setup writes
# through `env_set`, remove deletes through `env_unset`, doctor reads through
# `env_get`, and every one of them asks `env_live` whether the running process
# actually has the value.
#
# WHY A FILE AND NOT A SHELL RC. bionic used to append `export
# CLAUDE_CODE_ENABLE_TODO_TOOLS=1` to ~/.zshrc, and on 2026-08-21 that was
# measured not reaching the session it was written for: the host that launches
# the CLI runs its shell with rc files disabled, so the export was present on
# disk, absent from the process, and doctor could not tell the two apart. The
# settings file is read by the CLI itself, once, however the session was
# started — it is the only home that reaches every session. ~/.zshrc is now
# footprint remove cleans up, never a place setup writes.
#
# CONFIGURED IS NOT LIVE, AND THE DIFFERENCE IS THE WHOLE POINT. `env_get`
# answers "what does the file say"; `env_live` answers "what does THIS process
# have". A value written into the file reaches a process that starts afterwards
# and no other, so a report that collapsed the two would tell a user to fix
# something already fixed, or call a session ready that is not. Both are
# reported, separately, and the gap between them is a restart — not a repair.
#
# THE WRITER IS DEPS.SH'S. Every rewrite of settings.json in the payload goes
# through `_dep_settings_write_jq`, which captures the file's mode, builds the
# replacement under `umask 077` and chmods it BEFORE the rename, so a settings
# file a user deliberately kept at 0600 — it routinely holds tokens — never
# comes back wider as a side effect of bionic writing two of its own names into
# it. tests/remove.test.sh pins that writer's shape and walls the payload
# against a second one appearing beside it; this file adds no writer, it calls
# that one.
#
# ROOTS. The settings path is deps.sh's `_dep_settings_file`, so a suite that
# points the payload at a fixture machine moves this file with it and no seam
# substitutes the value under test.
#
# Sourced, never executed:  . "${CLAUDE_PLUGIN_ROOT}/scripts/lib/env.sh"

_env_self_dir() {
  local self="${BASH_SOURCE[0]}"
  case "$self" in */*) echo "${self%/*}" ;; *) echo "." ;; esac
}

# The same softly-conditional source detect.sh and jit.sh use: a caller that
# already loaded deps.sh does not load it twice, and one that did not gets it.
if ! declare -F _dep_settings_write_jq >/dev/null 2>&1; then
  # shellcheck source=/dev/null
  . "$(cd "$(_env_self_dir)" && pwd -P)/deps.sh"
fi

# ─── The names bionic owns ───────────────────────────────────────────────────
#
# TWO, AND THE LIST IS THE ROSTER. setup writes this list, remove deletes this
# list, doctor reports this list. A third name is added here and reaches all
# three; a name added in one of them and not here is a name nothing else can
# see. Space-separated rather than an array because bash 3.2 is the floor and a
# word-split loop is the one form every caller can write identically.
ENV_KEYS="CLAUDE_CODE_ENABLE_TODO_TOOLS BASH_MAX_TIMEOUT_MS"

# The value each name carries, and why:
#
#   CLAUDE_CODE_ENABLE_TODO_TOOLS=1  — current CLI builds gate the native task
#                                      tools behind it, and a plan ledger with
#                                      no task list behind it is a plan nobody
#                                      can see the state of.
#   BASH_MAX_TIMEOUT_MS=1800000      — the ceiling on how long a command may be
#                                      asked to run in the foreground. bionic's
#                                      own test suite takes about fifteen
#                                      minutes; under the default ten-minute
#                                      ceiling a run that long is taken away
#                                      from the agent that started it mid-flight
#                                      and its result is lost. Thirty minutes is
#                                      the smallest value larger than the
#                                      longest command bionic runs.
env_default() {  # <key> — prints the value, exit 1 if the key is not bionic's
  case "${1:-}" in
    CLAUDE_CODE_ENABLE_TODO_TOOLS) echo "1" ;;
    BASH_MAX_TIMEOUT_MS)           echo "1800000" ;;
    *)                             return 1 ;;
  esac
  return 0
}

# ─── The jq programs ─────────────────────────────────────────────────────────
#
# NAMED CONSTANTS, NOT INLINE TEXT, because remove.sh's standalone door cannot
# source this file and has to carry a copy — a copy of a named literal is
# pinnable (tests/remove.test.sh does exactly that for six other literals), and
# a copy of an inline expression is not.
#
# `(.env // {})` on the write side: a settings.json with no `env` object at all
# is the ordinary shape of a machine that never ran setup, and `+` on `null`
# fails rather than creating it.
ENV_SET_JQ='.env = ((.env // {}) + {($k): $v})'
# And on the delete side the mirror: delete the one name, and when that empties
# the object, delete the object too. An `"env": {}` left behind is bionic
# footprint that reads as a bionic setting nobody can find the value of.
ENV_UNSET_JQ='if has("env") then (.env |= del(.[$k])) | (if (.env | length) == 0 then del(.env) else . end) else . end'

# ─── The interface ───────────────────────────────────────────────────────────

# A name is used as a shell variable in `env_live` and as a jq argument here, so
# it is checked against the one shape both can take. This is not a defence
# against a hostile caller — the roster above is the only source of names in the
# payload — it is what stops a typo becoming an eval.
_env_valid_key() {  # <key>
  case "${1:-}" in
    [A-Za-z_]*) ;;
    *) return 1 ;;
  esac
  case "${1}" in
    *[!A-Za-z0-9_]*) return 1 ;;
  esac
  return 0
}

# What the FILE says. Prints the value; exits 1 when the name is absent, the
# file is absent, or jq is not there to read it — three different reasons for
# the same honest answer, "bionic cannot tell you this is configured".
env_get() {  # <key>
  local key="${1:-}" settings value
  _env_valid_key "$key" || return 1
  command -v jq >/dev/null 2>&1 || return 1
  settings="$(_dep_settings_file)"
  [ -f "$settings" ] || return 1
  value="$(jq -r --arg k "$key" '.env[$k] // empty' "$settings" 2>/dev/null)" || return 1
  [ -n "$value" ] || return 1
  printf '%s\n' "$value"
  return 0
}

# MERGE, NEVER CLOBBER. The `env` block is the user's too — it is where API
# tokens live on a lot of machines — so the program above adds one name to
# whatever is already there rather than assigning an object bionic composed.
# Every other key in the file, `permissions` included, is untouched by
# construction: jq rewrites the document it was given.
env_set() {  # <key> <value>
  local key="${1:-}" value="${2:-}" settings
  _env_valid_key "$key" || return 1
  command -v jq >/dev/null 2>&1 || return 1
  settings="$(_dep_settings_file)"
  # Deliberately not under `umask 077`, for deps.sh's reason at
  # `_dep_install_statusline`: the defect being avoided is widening a mode the
  # user chose, and a file that does not exist yet carries no such choice.
  [ -f "$settings" ] || echo '{}' > "$settings" || return 1
  _dep_settings_write_jq "$settings" "$ENV_SET_JQ" --arg k "$key" --arg v "$value"
}

# Absent is success. A teardown that failed because there was nothing to tear
# down would make every second `/bionic:remove` report a problem.
env_unset() {  # <key>
  local key="${1:-}" settings
  _env_valid_key "$key" || return 1
  settings="$(_dep_settings_file)"
  [ -f "$settings" ] || return 0
  command -v jq >/dev/null 2>&1 || return 1
  _dep_settings_write_jq "$settings" "$ENV_UNSET_JQ" --arg k "$key"
}

# What THIS PROCESS has. Read from the caller's own environment — not from the
# file, not from a shell rc — because that is the only thing that answers "will
# the session I am in behave the way the setting says". An empty string is a
# live value: `FOO=` is set, and reporting it as absent would send a user to
# repair something they deliberately cleared.
env_live() {  # <key>
  local key="${1:-}"
  _env_valid_key "$key" || return 1
  eval "[ -n \"\${${key}+x}\" ]" || return 1
  eval "printf '%s\\n' \"\${${key}}\""
  return 0
}
