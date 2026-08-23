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
# THE LIST IS THE ROSTER. setup writes this list, remove deletes this list,
# doctor reports this list. A name added here reaches all three; a name added in
# one of them and not here is a name nothing else can see. Space-separated rather
# than an array because bash 3.2 is the floor and a word-split loop is the one
# form every caller can write identically.
ENV_KEYS="CLAUDE_CODE_ENABLE_TODO_TOOLS BASH_MAX_TIMEOUT_MS CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS"

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
#   CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
#                                    — the teammate channel a dispatched agent
#                                      reports back through. bionic's whole
#                                      orchestration model is a session that
#                                      dispatches writers and reads their
#                                      deliveries; without this the CLI gates
#                                      that off and the model has no channel.
#                                      Carried forward at epic-18 T4 from the
#                                      retired installer's roster, where it was
#                                      an `env-var` line the port dropped in
#                                      silence (AC-8).
env_default() {  # <key> — prints the value, exit 1 if the key is not bionic's
  case "${1:-}" in
    CLAUDE_CODE_ENABLE_TODO_TOOLS)        echo "1" ;;
    BASH_MAX_TIMEOUT_MS)                  echo "1800000" ;;
    CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS) echo "1" ;;
    *)                                    return 1 ;;
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

# ─── The rc item ─────────────────────────────────────────────────────────────
#
# A SECOND KIND OF SETTING, AND WHY IT LIVES BESIDE THE FIRST. Everything above
# is a NAME AND A VALUE in the CLI's settings.json. This is a LINE OF SHELL, and
# no `env` object can hold one: `claude` has to become a function in the user's
# own interactive shell or `--dangerously-skip-permissions` never reaches the
# command they type. The rc channel was retired for exports (see the header) and
# it comes back here for the one thing only it can carry — not as a fourth
# `ENV_KEYS` entry, which would put a shell function through a jq writer aimed at
# a JSON object, but as its own item kind with its own roster and its own
# markers.
#
# WRITTEN ONLY BY SETUP, AFTER CONSENT (Chris 2026-08-23: "Don't you dare make
# the change directly. It may only be made if it is permanently added"). A line
# put into someone's rc by hand is footprint doctor cannot report and remove
# cannot strip. Inside these markers it is an item with an owner: offered with a
# why, reported present or absent, and taken back out on request.
#
# THE MARKERS ARE THE ONLY THING ANY DOOR MATCHES ON. Not the function name, not
# the flag — the marker pair. A `claude()` function a user wrote themselves sits
# outside them and is invisible to `rc_get`, untouched by `rc_unset`, and
# unreported by doctor, which is the whole difference between bionic's footprint
# and someone else's file.

# THE LIST IS THE ROSTER, exactly as ENV_KEYS is for settings.json: setup writes
# this list, remove deletes this list, doctor reports this list.
RC_ITEMS="claude-proxy"

# Verbatim, box-drawing dashes included — they are what makes the block
# addressable, and remove.sh's standalone door carries byte-equal copies
# (RM_RC_START / RM_RC_END) because it cannot source this file.
RC_START='# ─── bionic:rc:start ───'
RC_END='# ─── bionic:rc:end ───'

# WHICH FILE, AND WHY IT CAN REFUSE. `$SHELL` is what the user's terminal starts,
# and zsh and bash are the two shells bionic knows the rc name of. Anything else
# gets a printed skip and a non-zero exit rather than a guess: writing a bash
# function into a fish rc would break the shell it was meant to help. The
# override is read first and at call time, the same convention detect.sh and
# deps.sh use, so a suite can point every door at one fixture file.
rc_file() {
  if [ -n "${BIONIC_SHELL_RC:-}" ]; then printf '%s\n' "$BIONIC_SHELL_RC"; return 0; fi
  case "${SHELL:-}" in
    */zsh)  printf '%s\n' "${HOME}/.zshrc" ;;
    */bash) printf '%s\n' "${HOME}/.bashrc" ;;
    *)
      # To stderr, so the one thing this function writes to stdout is a path.
      printf 'bionic: %s is not a shell bionic writes an rc for — zsh and bash are.\n' \
        "${SHELL:-<unset>}" >&2
      return 1 ;;
  esac
  return 0
}

# The line each item carries, and why:
#
#   claude-proxy — `claude` typed at a prompt launches with the bypass mode
#                  AVAILABLE in the mode cycle. `command claude` inside the body
#                  is what stops the function calling itself, and is also why a
#                  script or a hook that runs `claude` in a non-interactive shell
#                  is unaffected: the rc is never sourced there, so the function
#                  does not exist and the binary is reached directly.
rc_default() {  # <item> — prints the line, exit 1 if the item is not bionic's
  case "${1:-}" in
    claude-proxy) printf '%s\n' 'claude() { command claude --dangerously-skip-permissions "$@"; }' ;;
    *)            return 1 ;;
  esac
  return 0
}

# Is the item's line INSIDE bionic's markers. The two halves both matter: a line
# that is not there, and a line that is there but outside the block, are both
# "bionic has not written this" — the second because it is somebody else's line.
rc_get() {  # <item>
  local item="${1:-}" want file line inside=0
  want="$(rc_default "$item")" || return 1
  file="$(rc_file)" || return 1
  [ -f "$file" ] || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$line" = "$RC_START" ]; then inside=1; continue; fi
    if [ "$line" = "$RC_END" ];   then inside=0; continue; fi
    if [ "$inside" = "1" ] && [ "$line" = "$want" ]; then return 0; fi
  done < "$file"
  return 1
}

# ─── The rc writer ───────────────────────────────────────────────────────────
#
# THE MODE TRAVELS WITH THE CONTENT. Staged beside the target under `umask 077`,
# widened to the target's mode only at the instant of publication, and renamed
# over the RESOLVED target rather than a symlink — setup.sh's `_setup_stage_tmp`
# / `_setup_publish_tmp` pair and remove.sh's `_rm_stage_tmp` / `_rm_publish_tmp`
# pair, spelled the same way here so a third door cannot drift from the other
# two. A shell rc is if anything the likeliest of bionic's three write targets to
# hold a plaintext token — it is where people put `export …_API_KEY=` — and `mv`
# replaces the inode, so without this a file a user deliberately kept at 0600
# comes back at whatever the umask says.

_rc_file_mode() {  # <file> — the mode of what <file> RESOLVES to, empty if unknowable
  local mode
  mode="$(stat -L -f '%Lp' "$1" 2>/dev/null || stat -L -c '%a' "$1" 2>/dev/null)"
  [ -e "$1" ] || mode=""
  printf '%s' "$mode"
}

_rc_stage_tmp() {  # <tmp> — created empty at 0600; the caller writes, then publishes
  local tmp="$1"
  rm -f "$tmp"
  (umask 077; : > "$tmp") || return 1
  return 0
}

_rc_publish_tmp() {  # <tmp> <file> — <file> is the resolved target
  local tmp="$1" file="$2" mode
  mode="$(_rc_file_mode "$file")"
  [ -n "$mode" ] && chmod "$mode" "$tmp"
  mv "$tmp" "$file"
}

# Everything the file holds EXCEPT bionic's block, and — when <keep> is `keep` —
# the block's own non-roster lines are kept inside a rebuilt block. One walk, so
# `rc_set` and `rc_unset` cannot come to disagree about what the block is.
#
# WHY A LINE INSIDE THE BLOCK CAN SURVIVE. `RC_ITEMS` is a roster and rosters
# grow. Deleting one item must not take a second item's line with it, so
# `rc_unset` filters only the line it was asked about and drops the markers when
# what is left inside them is nothing. A line inside the markers that is no
# item's default is bionic's own footprint from an older payload; it goes with
# the block rather than being stranded in a file with no markers around it.
_rc_rewrite() {  # <file> <tmp> <drop-line> <mode: all|one>
  local file="$1" tmp="$2" drop="$3" mode="$4"
  local line inside=0 kept="" pending=0 body=""
  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$line" = "$RC_START" ]; then inside=1; continue; fi
    if [ "$line" = "$RC_END" ];   then inside=0; continue; fi
    if [ "$inside" = "1" ]; then
      # Inside the block: `all` drops everything, `one` keeps what it was not
      # asked about.
      if [ "$mode" = "one" ] && [ "$line" != "$drop" ] && [ -n "$line" ]; then
        body="${body}${line}"$'\n'
      fi
      continue
    fi
    # Outside the block, the file is reproduced line for line. Blank lines are
    # deferred so a run of them survives exactly as it was — the same shape
    # remove.sh's `_rm_strip_marker_block` holds to.
    if [ "$pending" = "1" ]; then printf '\n' >> "$tmp"; pending=0; fi
    if [ -z "$line" ]; then pending=1; continue; fi
    printf '%s\n' "$line" >> "$tmp"
    kept=1
  done < "$file"
  [ "$pending" = "1" ] && printf '\n' >> "$tmp"
  printf '%s' "$body"
  [ -n "$kept" ] || true
  return 0
}

# IDEMPOTENT BY CONSTRUCTION, not by a guard that could be wrong: the block is
# removed and rewritten whole on every call, so a second run produces the same
# bytes and a block left half-written by an interrupted run is repaired rather
# than appended beside.
rc_set() {  # <item>
  local item="${1:-}" want file target tmp body
  want="$(rc_default "$item")" || return 1
  file="$(rc_file)" || return 1
  target="$(bionic_link_target "$file")"
  tmp="${target}.bionic.tmp"
  _rc_stage_tmp "$tmp" || return 1
  if [ -f "$file" ]; then
    body="$(_rc_rewrite "$file" "$tmp" "$want" one)" || { rm -f "$tmp"; return 1; }
  else
    body=""
  fi
  {
    printf '%s\n' "$RC_START"
    [ -n "$body" ] && printf '%s' "$body"
    printf '%s\n' "$want"
    printf '%s\n' "$RC_END"
  } >> "$tmp" || { rm -f "$tmp"; return 1; }
  _rc_publish_tmp "$tmp" "$target" || { rm -f "$tmp"; return 1; }
  return 0
}

# Absent is success, for env_unset's reason: a teardown that failed because there
# was nothing to tear down would make every second `/bionic:remove` report a
# problem. The rc FILE is never deleted, even if the block was all it held — a
# script that can be curl-fetched onto an unknown machine does not delete a
# user's shell rc.
rc_unset() {  # <item>
  local item="${1:-}" want file target tmp body
  want="$(rc_default "$item")" || return 1
  file="$(rc_file)" || return 1
  [ -f "$file" ] || return 0
  target="$(bionic_link_target "$file")"
  tmp="${target}.bionic.tmp"
  _rc_stage_tmp "$tmp" || return 1
  body="$(_rc_rewrite "$file" "$tmp" "$want" one)" || { rm -f "$tmp"; return 1; }
  # THE BLOCK GOES WHEN IT EMPTIES. An empty marker pair left in a user's rc is
  # bionic footprint that reads as a bionic setting whose value nobody can find —
  # the same defect the retired env block left behind, and the reason remove
  # strips markers rather than filtering the line between them.
  if [ -n "$body" ]; then
    {
      printf '%s\n' "$RC_START"
      printf '%s' "$body"
      printf '%s\n' "$RC_END"
    } >> "$tmp" || { rm -f "$tmp"; return 1; }
  fi
  _rc_publish_tmp "$tmp" "$target" || { rm -f "$tmp"; return 1; }
  return 0
}
