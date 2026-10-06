#!/bin/bash
# env.sh — the ONE home for bionic's environment settings (epic-17 wave-07 task
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
# it. This file adds no second settings.json writer — it calls that one.
#
# NO CROSS-WRITER PIN, AND THAT IS LOGGED DEBT RATHER THAN AN OVERSIGHT.
# tests/remove.test.sh used to pin that writer's shape and wall the payload
# against a second one appearing beside it. It was deleted at epic-18 wave-03
# and nothing replaced it. In the same wave this file grew a staging pair of its
# own for the shell rc (now lib/markers.sh's `_markers_stage_tmp` /
# `_markers_publish_tmp`, moved there at wave-27 T7), which makes three copies of
# the stage-then-publish shape in the payload — setup.sh's, remove.sh's, and
# that one. They are spelled alike on purpose and today they
# are held together by nothing but that: wave-03 plan residual (b), weighed by
# its critic at F4 as acceptable debt. Do not read the resemblance as a pin.
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

# markers.sh, the same soft source: the marker-block walk both of this file's
# block items (the shell rc, the working principles) write and strip through.
if ! declare -F markers_set >/dev/null 2>&1; then
  # shellcheck source=/dev/null
  . "$(cd "$(_env_self_dir)" && pwd -P)/markers.sh"
fi

# ─── The names bionic owns ───────────────────────────────────────────────────
#
# THE LIST IS THE ROSTER. setup writes this list, remove deletes this list,
# doctor reports this list. A name added here reaches all three; a name added in
# one of them and not here is a name nothing else can see. Space-separated rather
# than an array because bash 3.2 is the floor and a word-split loop is the one
# form every caller can write identically.
#
# remove.sh carries a byte copy of this literal as `RM_ENV_KEYS`, because its
# standalone door cannot source this file. tests/env.test.sh Group 1 reads both
# literals with `sed` and fails when they differ, so a name added here has to be
# added there in the same change.
ENV_KEYS="CLAUDE_CODE_ENABLE_TODO_TOOLS BASH_MAX_TIMEOUT_MS CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS CLAUDE_CODE_DISABLE_AUTO_MEMORY"

# The value each name carries, and why:
#
#   CLAUDE_CODE_ENABLE_TODO_TOOLS=1  — current CLI builds gate the native task
#                                      tools behind it, and a plan ledger with
#                                      no task list behind it is a plan nobody
#                                      can see the state of.
#                                      HOW THE GATE WAS FOUND (2026-08-15, two
#                                      axes). Version: a census of session
#                                      transcripts, `grep -rl
#                                      '"name":"TaskCreate"' ~/.claude/projects/`,
#                                      showed fable-tier sessions calling
#                                      TaskCreate on every CLI from 2.1.211
#                                      through 2.1.227 and on none from 2.1.228,
#                                      so the removal shipped somewhere in
#                                      2.1.228-2.1.233. Model: on CLI 2.1.233 the
#                                      same `claude -p` tool-enumeration probe
#                                      listed TaskCreate/TaskGet/TaskList/
#                                      TaskUpdate under haiku and none under the
#                                      fable tier, so haiku is unaffected and the
#                                      gate is model-scoped. The fix was measured
#                                      by the same probe: with this name set to
#                                      1 the four tools come back. Re-confirmed
#                                      2026-08-21 on 2.1.238 with the name unset:
#                                      still gated. Two consequences a reader
#                                      meets elsewhere: a process started on an
#                                      older binary keeps its task list, so two
#                                      sessions side by side can disagree; and
#                                      TaskOutput/TaskStop were never gated, so
#                                      stopping an agent works either way.
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
#   CLAUDE_CODE_DISABLE_AUTO_MEMORY=1
#                                    — turns off the CLI's auto memory: the
#                                      per-project directory under
#                                      <claude-home>/projects/<slug>/memory/
#                                      whose MEMORY.md index the CLI loads into
#                                      every session and which the model writes
#                                      to on its own. Text that reaches every
#                                      session with no review and no owner is a
#                                      fifth channel, and bionic keeps its
#                                      standing guidance in ADR-040's four: the
#                                      user's global CLAUDE.md; the repo's
#                                      CLAUDE.md and .claude/rules/; the
#                                      doctrine the plugin ships; the wave
#                                      record (wave-23). The CLI's docs give this name
#                                      precedence over `autoMemoryEnabled` in
#                                      either direction, and a settings `env`
#                                      value overwrites a shell export, so the
#                                      user-scope `env` entry setup writes is
#                                      the strongest switch bionic can own; only
#                                      a managed-settings entry outranks it, and
#                                      that is not bionic's to write. A project
#                                      or local `env` block (`.claude/settings
#                                      .json`, `.claude/settings.local.json`) can
#                                      still set it back to "0" for one project,
#                                      and the switch cannot delete files the
#                                      CLI wrote before it was set. doctor's
#                                      `auto-memory` row reports both, reading
#                                      the project and local settings only: a
#                                      managed settings file, a `--settings`
#                                      argument and the Desktop app's launch
#                                      environment can also set the name and are
#                                      outside what doctor reads
#                                      (lib/checks.sh, detect_auto_memory in
#                                      lib/detect.sh).
env_default() {  # <key> — prints the value, exit 1 if the key is not bionic's
  case "${1:-}" in
    CLAUDE_CODE_ENABLE_TODO_TOOLS)        echo "1" ;;
    BASH_MAX_TIMEOUT_MS)                  echo "1800000" ;;
    CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS) echo "1" ;;
    CLAUDE_CODE_DISABLE_AUTO_MEMORY)      echo "1" ;;
    *)                                    return 1 ;;
  esac
  return 0
}

# ─── The jq programs ─────────────────────────────────────────────────────────
#
# NAMED CONSTANTS, NOT INLINE TEXT, because remove.sh's standalone door cannot
# source this file and has to carry a copy — a copy of a named literal is
# pinnable in principle (tests/remove.test.sh used to do exactly that for six
# other literals; it was deleted at 8582861 and nothing replaced it), and a
# copy of an inline expression is not.
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
# own interactive shell or the launch flag never reaches the command they type.
# The rc channel was retired for exports (see the header) and
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
#   claude-proxy — `claude` typed at a prompt STARTS in whatever
#                  `permissions.defaultMode` says (setup writes `auto`) and can
#                  reach the bypass mode from the Shift+Tab cycle. Those are two
#                  different flags and bionic carries the second one:
#                  `--dangerously-skip-permissions` STARTS the session in bypass,
#                  which is what this item used to do and is not what anyone
#                  asked for; `--allow-dangerously-skip-permissions` only puts
#                  bypass in the cycle and leaves the starting mode alone.
#                  MEASURED, not assumed — three PTY arms against CLI 2.1.248 in
#                  record/epic-19/w1/s1-f2-probe.md: without one of those two
#                  flags the cycle is default → acceptEdits → plan → auto and
#                  bypass is not in it at all, so dropping the flag outright
#                  would have taken the capability away with the default.
#                  A SETTING CANNOT DO THIS, which is the whole reason the item
#                  is a line of shell: bypass availability is decided from the
#                  argv at launch, and the only settings key in that decision
#                  (`disableBypassPermissionsMode`, managed-settings-only) can
#                  turn it off and never on.
#                  `command claude` inside the body is what stops the function
#                  calling itself, and is also why a script or a hook that runs
#                  `claude` in a non-interactive shell is unaffected: the rc is
#                  never sourced there, so the function does not exist and the
#                  binary is reached directly.
#                  THE FIRST LINE CLEARS THE NAME (wave-27 T75, A-orch-185). An
#                  alias named `claude` standing above the block (bionic's own
#                  retired bare alias, which no door removes, or the user's) is
#                  expanded by zsh and interactive bash into the function's
#                  definition line: a syntax error at every shell start, nothing
#                  after it run, and the alias still in force. `-n` does not see
#                  it, because no alias is expanded under `-n`. So the body opens
#                  with `unalias claude`, which the shell runs before it reads the
#                  next line; `2>/dev/null || true` keeps it silent and at status
#                  zero where no alias stands, so it cannot fail an rc under
#                  `set -e`. An alias defined BELOW the block still wins when
#                  `claude` is typed: an alias is looked up before a function.
rc_default() {  # <item> — prints the body, one line per line, exit 1 if the item is not bionic's
  case "${1:-}" in
    claude-proxy) printf '%s\n' 'unalias claude 2>/dev/null || true' 'claude() { command claude --allow-dangerously-skip-permissions "$@"; }' ;;
    *)            return 1 ;;
  esac
  return 0
}

# EVERY BODY AN EARLIER BIONIC WROTE BETWEEN THESE MARKERS, and the one place they are
# listed (wave-27 T77, review pass 64): every spelling `rc_default` has printed, found
# with `git log -p -G'claude-proxy\) *printf' -- payload/scripts/lib/env.sh`. <n>
# counts from 1, oldest first; rc 1 past the last. When `rc_default` changes, the body
# it printed until then is added here.
rc_earlier() {  # <item> <n> — prints the nth earlier body, rc 1 when there is none
  case "${1:-}:${2:-}" in
    # 48b37383 (2026-08-22) until 40be1c30: the flag that started the session in bypass.
    claude-proxy:1) printf '%s\n' 'claude() { command claude --dangerously-skip-permissions "$@"; }' ;;
    # 40be1c30 (2026-08-27) until 484afee2 (wave-27 T75), which put `unalias` above it.
    claude-proxy:2) printf '%s\n' 'claude() { command claude --allow-dangerously-skip-permissions "$@"; }' ;;
    *) return 1 ;;
  esac
  return 0
}

# A BLOCK IS BIONIC'S TO REWRITE ONLY WHEN ITS BODY IS BYTE FOR BYTE A BODY BIONIC
# WROTE (wave-27 T77, review pass 64; the rule A-orch-162 gave the retired blocks). T75
# read a block holding bionic's lines and a line of the user's as "not written", and a
# yes rewrote it whole without that line. The one answer every door asks:
#
#   written    — every line of the current body, in order, with or without other
#                lines among or around them: bionic's lines are in force, and the
#                block is left as it is, the user's lines with it
#   stale      — nothing between the markers, or byte for byte an earlier body
#                (`rc_earlier`): bionic's own block out of date, rewritten on a yes
#   changed    — anything else: the user's to edit by hand. Nothing asks about it,
#                nothing writes it (`rc_set` refuses), every door names its lines
#   no         — no block
#   malformed  — the markers do not pair up (markers.sh `markers_check`)
#   not-a-file — the rc is not a text file bionic can read (`markers_regular`)
#
# rc 1, and nothing printed, when the item is not bionic's or no rc can be named.
rc_state() {  # <item>
  local item="${1:-}" want file got line n=1 i=0 old
  local -a lines=()
  want="$(rc_default "$item")" || return 1
  file="$(rc_file)" || return 1
  markers_regular "$file" >/dev/null || { printf 'not-a-file\n'; return 0; }
  got="$(markers_get "$file" "$RC_START" "$RC_END"; printf 'rc=%s' "$?")"
  case "$got" in
    *rc=1) printf 'no\n'; return 0 ;;
    *rc=2) printf 'malformed\n'; return 0 ;;
  esac
  got="${got%rc=0}"
  while IFS= read -r line; do lines[${#lines[@]}]="$line"; done <<< "$want"
  while IFS= read -r line || [ -n "$line" ]; do
    [ "$i" -lt "${#lines[@]}" ] && [ "$line" = "${lines[$i]}" ] && i=$((i + 1))
  done < <(printf '%s' "$got")
  if [ "$i" = "${#lines[@]}" ]; then printf 'written\n'; return 0; fi
  if [ -z "$got" ]; then printf 'stale\n'; return 0; fi
  while old="$(rc_earlier "$item" "$n")"; do
    if [ "$got" = "${old}"$'\n' ]; then printf 'stale\n'; return 0; fi
    n=$((n + 1))
  done
  printf 'changed\n'
  return 0
}

# The block's start and end marker lines, `<first> <last>`, for a door to name it by
# number and never by its text. Nothing when the rc holds no block.
rc_block_range() {
  local file line n=0 first=""
  file="$(rc_file 2>/dev/null)" || return 0
  [ -f "$file" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    if [ -z "$first" ] && [ "$line" = "$RC_START" ]; then first="$n"
    elif [ -n "$first" ] && [ "$line" = "$RC_END" ]; then printf '%s %s\n' "$first" "$n"; return 0; fi
  done < "$file"
  return 0
}

# Are bionic's lines in force: `rc_state` says written.
rc_get() {  # <item>
  [ "$(rc_state "${1:-}" 2>/dev/null)" = "written" ]
}

# MAY THE BLOCK GO WHOLE (wave-27 T78). Remove takes the block out only when nothing of
# the user's can be between the markers: its body is byte for byte the current body, an
# earlier one, or nothing — `rc_state`'s stale, or its written with no other line. A
# written block that also holds a line of the user's, and every changed block, stay.
# remove.sh asks this in payload mode; its standalone door decides by its copy of the
# two body lists (`rc_default`, `rc_earlier`).
rc_removable() {  # <item> — rc 0 when the block's body is one bionic wrote, or nothing
  local item="${1:-}" want file got
  case "$(rc_state "$item" 2>/dev/null)" in
    stale)   return 0 ;;
    written) ;;
    *)       return 1 ;;
  esac
  want="$(rc_default "$item")" || return 1
  file="$(rc_file)" || return 1
  got="$(markers_get "$file" "$RC_START" "$RC_END"; printf 'rc=%s' "$?")"
  [ "$got" = "${want}"$'\n'"rc=0" ]
}

# ─── The rc writer ───────────────────────────────────────────────────────────
#
# THE WALK IS lib/markers.sh's. `_rc_rewrite` and its staging pair lived here
# until wave-27 T7, when the principles item needed the same block in a second
# file; they moved there whole (`_markers_rewrite`, `_markers_stage_tmp`,
# `_markers_publish_tmp`) and the reasons moved with them — the mode that travels
# with the content, and the block rebuilt wholesale rather than filtered (epic-18
# wave-03 critic F1/F2). What stays here is what is the rc item's own: which file,
# which markers, and which one line goes between them.

# THE WRITER ASKS `rc_state` FIRST, SO NO CALLER CAN LOSE A LINE (wave-27 T77). It
# writes only where nothing of the user's can be between the markers:
#
#   no      — the block is appended by `markers_set`, as it always was
#   stale   — the block's body is replaced WHERE IT STANDS, and no other byte of the
#             rc changes (markers.sh `markers_replace`, A-orch-193): `markers_set`
#             would move the block to the end of the file, past the user's own lines
#   written — nothing is written: bionic's lines are in force, and rewriting would
#             drop the user's lines beside them; rc 0
#   changed — refused, rc 5, the rc byte for byte as it was
#
# The other exit codes are markers.sh's (its header): 1 a write failed, 2 the markers
# do not pair up, 3 read-only, 4 not a regular text file. A second run produces the
# same bytes: the first leaves the block written.
#
# THE BODY IS STAGED BESIDE THE RC, not in `$TMPDIR` (wave-27 T40, review pass 9
# note 11): the rc's own directory is the one place this write already needs, so
# a full or unwritable `$TMPDIR` cannot fail it.
rc_set() {  # <item>
  local item="${1:-}" want file state body rc
  want="$(rc_default "$item")" || return 1
  file="$(rc_file)" || return 1
  state="$(rc_state "$item")" || return 1
  case "$state" in
    not-a-file) return 4 ;;
    malformed)  return 2 ;;
    written)    return 0 ;;
    changed)    return 5 ;;  # guard: a changed block is never written
  esac
  body="$(bionic_link_target "$file").bionic.body"
  rm -f "$body"
  (umask 077; printf '%s\n' "$want" > "$body") || { rm -f "$body"; return 1; }
  if [ "$state" = "stale" ]; then
    markers_replace "$file" "$RC_START" "$RC_END" "$body"; rc=$?
  else
    markers_set "$file" "$RC_START" "$RC_END" "$body"; rc=$?
  fi
  rm -f "$body"
  return "$rc"
}

# Absent is success, for env_unset's reason: a teardown that failed because there
# was nothing to tear down would make every second `/bionic:remove` report a
# problem. The rc FILE is never deleted, even if the block was all it held — a
# script that can be curl-fetched onto an unknown machine does not delete a
# user's shell rc.
#
# THE BLOCK GOES WHOLE. An empty marker pair left in a user's rc is bionic
# footprint that reads as a bionic setting whose value nobody can find — the
# same defect the retired env block left behind, and the reason remove strips
# markers rather than filtering the line between them.
#
# AND IT GOES ONLY WHEN IT IS ALL BIONIC'S (wave-27 T78): a block holding a line bionic
# never wrote (`rc_removable`) is refused with rc 5, `rc_set`'s reason for the same
# block, and the rc is byte for byte as it was, so no caller can lose a line by calling
# it. No block, markers that do not pair up and an rc that is no text file are
# `markers_strip`'s to answer, as before.
rc_unset() {  # <item>
  local item="${1:-}" file
  rc_default "$item" >/dev/null || return 1
  file="$(rc_file)" || return 1
  case "$(rc_state "$item" 2>/dev/null)" in
    written|changed) rc_removable "$item" || return 5 ;;  # guard: a changed claude() block is never stripped
  esac
  markers_strip "$file" "$RC_START" "$RC_END"
}

# ─── The working-principles item ─────────────────────────────────────────────
#
# A SHORT SET OF WORKING PRINCIPLES IN THE USER'S OWN INSTRUCTION FILE, offered
# at setup (wave-27 D16, REQ-9). `<claude home>/CLAUDE.md` is the user's file and
# the CLI reads it into every session; bionic's text goes in between its own
# markers, written only on a yes, and comes out by those markers on remove.
#
# THE TEXT HAS ONE SOURCE. agents-src/templates/context/working-principles.md.tmpl
# renders payload/context/working-principles.md, and the shipped file carries the
# text between these same two markers, so the body setup writes is
# `markers_get` of the payload file — the same walk that reads the user's block,
# and no parser for the render's do-not-edit header. Doctor's three states are a
# comparison of those two reads.
#
#   present   — the user's block is byte-for-byte the shipped text
#   edited    — a block is there and differs. The user's to keep: doctor shows it
#               as a state and setup leaves it alone unless the item is asked for
#               by name. It cannot yet be told from an OLDER shipped text, and
#               needs no telling until a release changes the text (wave-27 T40).
#   absent    — no block
#   malformed — the markers do not pair up (markers.sh `markers_check`); every
#               door says what it found and where, and writes nothing
#   not-a-file — the path is a directory, a dangling link, or anything else that
#               is not a regular file or a link to one (markers.sh
#               `markers_regular`, wave-27 T46); every door says what it is, and
#               nothing is created in it or beside it
#
# AN EDIT IS NEVER DISCARDED SILENTLY. `markers_set` rebuilds a block whole, so
# setup on an `edited` block prints the difference and writes only on a second,
# live yes (setup.sh `setup_working_principles`), and remove does the same.
#
# THE FILE GOES ONLY WITH NOTHING OF THE USER'S IN IT (wave-27 T40, review pass 9
# finding 4). Remove deletes CLAUDE.md only when the block is the shipped text
# unedited and nothing else is in the file: there is then no text of the user's
# to lose, and a file that was empty before setup comes back as absent, which
# loses nothing either. An edited block leaves the emptied file in place, and a
# file with no block is never touched, whatever its size.
#
# Verbatim. remove.sh's standalone door carries byte-equal copies
# (RM_PRINCIPLES_START / RM_PRINCIPLES_END) because
# it cannot source this file; tests/principles-item.test.sh §REMOVE pins them equal.
PRINCIPLES_START='<!-- bionic:principles:start -->'
PRINCIPLES_END='<!-- bionic:principles:end -->'

principles_file()      { printf '%s/CLAUDE.md\n' "$(claude_home)"; }
principles_text_file() { printf '%s/context/working-principles.md\n' "$(plugin_root)"; }

# The shipped text, the body setup would write: what the consent screen shows.
principles_text() {
  markers_get "$(principles_text_file)" "$PRINCIPLES_START" "$PRINCIPLES_END"
}

# What `malformed` found, one `line <n>: …` per fault; nothing when well formed.
principles_where() {
  markers_check "$(principles_file)" "$PRINCIPLES_START" "$PRINCIPLES_END"
  return 0
}

# present | edited | absent | malformed | not-a-file. A shipped file that cannot
# be read leaves a block reading `edited`, never `present`: nothing can be said
# to match a text that is not there.
principles_state() {
  local mine shipped
  markers_regular "$(principles_file)" >/dev/null || { printf 'not-a-file\n'; return 0; }
  mine="$(markers_get "$(principles_file)" "$PRINCIPLES_START" "$PRINCIPLES_END"; printf '%s' "rc=$?")"
  case "$mine" in
    *rc=1) printf 'absent\n'; return 0 ;;
    *rc=2) printf 'malformed\n'; return 0 ;;
  esac
  shipped="$(markers_get "$(principles_text_file)" "$PRINCIPLES_START" "$PRINCIPLES_END"; printf '%s' "rc=$?")"
  if [ "$mine" = "$shipped" ]; then printf 'present\n'; else printf 'edited\n'; fi
  return 0
}

# The difference between the user's block and the shipped text, as a unified
# diff — what a yes would change. Empty when they agree.
principles_diff() {
  local mine shipped
  mine="$(mktemp "${TMPDIR:-/tmp}/bionic-principles-mine.XXXXXX")" || return 1
  shipped="$(mktemp "${TMPDIR:-/tmp}/bionic-principles-shipped.XXXXXX")" || { rm -f "$mine"; return 1; }
  markers_get "$(principles_file)" "$PRINCIPLES_START" "$PRINCIPLES_END" > "$mine"
  markers_get "$(principles_text_file)" "$PRINCIPLES_START" "$PRINCIPLES_END" > "$shipped"
  diff -u -L "your block" -L "bionic's text" "$mine" "$shipped"
  rm -f "$mine" "$shipped"
  return 0
}

# Writes the shipped text between the markers, creating the claude home and the
# file if neither is there: the caller asked first. Refuses when the payload's
# text cannot be read, rather than writing an empty block. The body is staged
# beside the target, as rc_set's is. Exit codes are markers_set's.
principles_set() {
  local file body rc
  file="$(principles_file)"
  markers_regular "$file" >/dev/null || return 4
  mkdir -p "${file%/*}" || return 1
  body="$(bionic_link_target "$file").bionic.body"
  rm -f "$body"
  if ! (umask 077; principles_text > "$body") || [ ! -s "$body" ]; then
    rm -f "$body"; return 1
  fi
  markers_set "$file" "$PRINCIPLES_START" "$PRINCIPLES_END" "$body"; rc=$?
  rm -f "$body"
  return "$rc"
}

# Would `principles_unset` delete the file: the block is the shipped text
# unedited, and nothing else is in it. A symlink never goes: its
# target belongs to whatever manages the link. Asked before the question, so
# the question can say so.
principles_unset_deletes() {
  local file
  file="$(principles_file)"
  [ -f "$file" ] && [ ! -L "$file" ] || return 1
  [ "$(principles_state)" = "present" ] || return 1
  markers_only "$file" "$PRINCIPLES_START" "$PRINCIPLES_END"
}

# Strips the block, and deletes the file when `principles_unset_deletes` said so
# before the strip. Exit codes are markers_strip's; on any non-zero nothing was
# changed.
principles_unset() {
  local file deletes=no rc
  file="$(principles_file)"
  principles_unset_deletes && deletes=yes
  markers_strip "$file" "$PRINCIPLES_START" "$PRINCIPLES_END"; rc=$?
  [ "$rc" = "0" ] || return "$rc"
  if [ "$deletes" = "yes" ] && [ -f "$file" ] && [ ! -s "$file" ]; then rm -f "$file"; fi
  return 0
}
