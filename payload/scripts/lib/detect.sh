#!/bin/bash
# detect.sh — machine facts, read-only (epic-17 wave-03, spec AC-3/AC-5).
#
# WHAT THIS FILE OWNS. Every observable truth about the machine bionic is
# running on: is the payload intact, is a dependency there and at what version,
# does the shell rc carry the flag, is there a legacy alias block, are there
# hook registrations still on the legacy settings channel, is this box
# half-uninstalled. One function
# per fact class, and every door — doctor's report, setup's action list, a
# route's just-in-time offer, remove's teardown — reads the SAME function. A
# second implementation of any of these is the defect the ownership table
# exists to prevent.
#
# THE OUTPUT CONTRACT. One line, parseable, exit 0. Always exit 0: a fact
# function's job is to REPORT, and "I could not tell" is a fact with a value
# (`unknown`), not an error. Callers parse fields; they never branch on the
# exit code. The line shapes are fixed and consumed by later slices verbatim:
#
#   plugin: version=<v> hooks=<ok|degraded|absent>
#   agents: state=<stock|modified|unknown> total=<n|unknown> modified=<n|unknown> names=<a.md,b.md|-> cause=<text|->
#   dep:<name> lane=<3a|3b> present=<yes|no|unknown> version=<v|unknown> constraint=<c> verdict=<ok|violation|unknown>
#   env:todo-tools present=<yes|no>
#   env:zshrc-legacy present=<yes|no>
#   env:legacy-channel-hooks count=<n|unknown>
#   state:half-uninstalled=<yes|no>
#
# `unknown` APPEARS WHERE HONESTY REQUIRES IT. Two of these values can read
# `unknown` where the spec's table sketched only yes/no: a dependency whose
# mechanism has no presence surface at all (the pnpm store is a cache, not an
# install), and a count that cannot be taken because `jq` — itself one of the
# table's own rows — is missing. The alternative is a confident wrong answer,
# and a doctor that confidently reports a clean machine as dirty is worse than
# one that says it could not look.
#
# READ-ONLY IS A CONTRACT, NOT AN INTENTION. Nothing here writes, creates,
# moves, or removes anything, and `/bionic:doctor` is built entirely on it.
# tests/plugin-lib.test.sh fingerprints a fixture tree before and after a full
# sweep to keep that true.
#
# ROOTS ARE OVERRIDABLE, read at CALL time so one sourced copy can be pointed
# at several roots in turn (the suite does exactly that):
#
#   BIONIC_PLUGIN_ROOT     the payload tree            ${CLAUDE_PLUGIN_ROOT} or this file's ../..
#   BIONIC_CLAUDE_HOME     the CLI's config dir        ${CLAUDE_CONFIG_DIR:-~/.claude}
#   BIONIC_SETTINGS_FILE   user settings.json          <claude-home>/settings.json
#   BIONIC_SHELL_RC        the shell rc bionic edits   ~/.zshrc or ~/.bashrc, per $SHELL
#
# Sourced, never executed:  . "${CLAUDE_PLUGIN_ROOT}/scripts/lib/detect.sh"

# deps.sh is a sibling; the dependency table and the per-mechanism probes live
# there because they are properties of the DEPENDENCY, not of the machine.
# detect_dep below is their only formatter.
# No `dirname`/`basename` anywhere below, on purpose: a library that cannot be
# SOURCED without coreutils is a library that dies on the machine it is most
# needed on (jq missing, PATH broken, a half-uninstalled box). Bash's own
# parameter expansion does the same work with no process at all.
_detect_self_dir() {
  local self="${BASH_SOURCE[0]}"
  case "$self" in */*) echo "${self%/*}" ;; *) echo "." ;; esac
}

if ! declare -F check_dep >/dev/null 2>&1; then
  # shellcheck source=/dev/null
  . "$(cd "$(_detect_self_dir)" && pwd -P)/deps.sh"
fi

_detect_plugin_root() {
  if [ -n "${BIONIC_PLUGIN_ROOT:-}" ]; then echo "$BIONIC_PLUGIN_ROOT"; return; fi
  if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then echo "$CLAUDE_PLUGIN_ROOT"; return; fi
  # lib -> scripts -> payload root
  ( cd "$(_detect_self_dir)/../.." && pwd -P )
}

_detect_shell_rc() {
  if [ -n "${BIONIC_SHELL_RC:-}" ]; then echo "$BIONIC_SHELL_RC"; return; fi
  local shell_name="${SHELL:-/bin/bash}"
  case "${shell_name##*/}" in
    zsh) echo "$HOME/.zshrc" ;;
    *)   echo "$HOME/.bashrc" ;;
  esac
}

# ─── Plugin integrity ────────────────────────────────────────────────────────
#
# Two questions in one line: which version of the payload is running, and are
# its hooks wired to files that actually exist. `degraded` is the interesting
# state — hooks.json present but naming a script that is not there is exactly
# what a partial update or a half-copied install leaves behind, and it is
# invisible to any check that only asks whether hooks.json exists.

detect_plugin_integrity() {
  local root version="unknown" hooks_json hooks_state cmd script tok
  local -a toks
  root="$(_detect_plugin_root)"
  hooks_json="${root}/hooks/hooks.json"

  if [ -f "${root}/.claude-plugin/plugin.json" ]; then
    if command -v jq >/dev/null 2>&1; then
      version="$(jq -r '.version // "unknown"' "${root}/.claude-plugin/plugin.json" 2>/dev/null)"
    else
      version="$(grep -oE '"version"[[:space:]]*:[[:space:]]*"[^"]+"' "${root}/.claude-plugin/plugin.json" 2>/dev/null \
                 | head -1 | grep -oE '"[^"]+"$' | tr -d '"')"
    fi
    [ -n "$version" ] || version="unknown"
  fi

  if [ ! -f "$hooks_json" ]; then
    hooks_state="absent"
  else
    hooks_state="ok"
    # Every command in hooks.json names a script under the plugin root via
    # ${CLAUDE_PLUGIN_ROOT}. Resolve that prefix against the root we are
    # actually inspecting and confirm the file is there.
    #
    # EVERY token, not just the first. Four of the six shipped entries CHAIN
    # two scripts (`agent-context-guard.sh <inner>`), and the inner one is
    # where the evidence gate, the governing-skill gate and the landing gate
    # live. Reading `${cmd%% *}` alone called a payload missing all three
    # healthy. `read -a` splits on whitespace without letting the shell glob
    # the pieces; the `/*` guard then skips anything that is not a resolved
    # absolute path (a flag, a plain argument, an unexpanded env reference).
    while IFS= read -r cmd; do
      [ -n "$cmd" ] || continue
      read -r -a toks <<<"$cmd"
      for tok in "${toks[@]}"; do
        script="${tok//\$\{CLAUDE_PLUGIN_ROOT\}/$root}"
        script="${script//\$CLAUDE_PLUGIN_ROOT/$root}"
        case "$script" in /*) ;; *) continue ;; esac
        [ -f "$script" ] || { hooks_state="degraded"; break 2; }
      done
    done < <(grep -oE '"command"[[:space:]]*:[[:space:]]*"[^"]+"' "$hooks_json" 2>/dev/null \
             | sed -e 's/.*:[[:space:]]*"//' -e 's/"$//')
  fi

  echo "plugin: version=${version} hooks=${hooks_state}"
  return 0
}

# ─── Rendered-agent integrity ────────────────────────────────────────────────
#
# Has anything edited the role files this payload installed? The six agent files
# are instructions a dispatched subagent obeys, so a stray edit there changes
# behaviour everywhere and leaves no trace anywhere else — the machine keeps
# working, differently. The payload ships a checksum manifest beside them
# (integrity/agents.sha256, written by agents-src/render.sh), and this compares
# it against what is on disk.
#
# REPORTING, NOT POLICING. A user who edited a role file may have meant to; that
# is their machine. The fact line says WHICH files differ and stops there — no
# repair, no exit status, no second mention. The caller renders one line.
#
# THE THIRD VALUE MATTERS MOST HERE. Two conditions make the question
# unanswerable: no manifest (an old payload, or a hand-assembled install) and no
# sha256 tool on PATH. Answering `stock` in either case would report the very
# state this function exists to detect as the state it exists to reassure about,
# so both return `unknown` with the cause named.

_detect_sha256() {  # <file> -> hex digest on stdout; nonzero if no tool can answer
  local out
  if command -v shasum >/dev/null 2>&1; then
    out="$(shasum -a 256 "$1" 2>/dev/null)" || return 1
  elif command -v sha256sum >/dev/null 2>&1; then
    out="$(sha256sum "$1" 2>/dev/null)" || return 1
  else
    return 1
  fi
  [ -n "$out" ] || return 1
  echo "${out%% *}"
}

detect_agent_integrity() {
  local root manifest line want rel got total=0 modified=0 names=""
  root="$(_detect_plugin_root)"
  manifest="${root}/integrity/agents.sha256"

  if [ ! -f "$manifest" ]; then
    echo "agents: state=unknown total=unknown modified=unknown names=- cause=this payload ships no checksum manifest at integrity/agents.sha256"
    return 0
  fi
  if ! command -v shasum >/dev/null 2>&1 && ! command -v sha256sum >/dev/null 2>&1; then
    echo "agents: state=unknown total=unknown modified=unknown names=- cause=neither shasum nor sha256sum is on PATH, so the agent files cannot be digested"
    return 0
  fi

  # `<digest>  <path>` rows, path relative to the plugin root; `#` comments and
  # blank lines skipped. A row whose file is GONE counts as modified and is
  # named: deleting a role file is a local change like any other, and silently
  # skipping it would report five-of-six as a whole set.
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*) continue ;; esac
    want="${line%% *}"
    rel="${line#* }"; rel="${rel# }"
    [ -n "$want" ] && [ -n "$rel" ] || continue
    total=$((total + 1))
    got="$(_detect_sha256 "${root}/${rel}")" || got=""
    if [ "$got" != "$want" ]; then
      modified=$((modified + 1))
      names="${names:+${names},}${rel##*/}"
    fi
  done < "$manifest"

  if [ "$total" = 0 ]; then
    echo "agents: state=unknown total=0 modified=unknown names=- cause=the checksum manifest lists no files"
  elif [ "$modified" = 0 ]; then
    echo "agents: state=stock total=${total} modified=0 names=- cause=-"
  else
    echo "agents: state=modified total=${total} modified=${modified} names=${names} cause=-"
  fi
  return 0
}

# ─── Dependencies ────────────────────────────────────────────────────────────
#
# The fact line for one dependency. Everything factual comes from deps.sh —
# the row from the table, the probe from the mechanism — and this function
# only renders. That split is why there is exactly one place a dependency's
# presence is decided.

detect_dep() {  # <name>
  local name="${1:-}" lane constraint raw present version verdict
  lane="$(dep_field "$name" lane)" || return 1
  constraint="$(dep_field "$name" constraint)"
  raw="$(check_dep "$name")" || return 1
  present="${raw#present=}"; present="${present%%|*}"
  version="${raw#*version=}"; version="${version%%|*}"
  verdict="${raw##*verdict=}"
  echo "dep:${name} lane=${lane} present=${present} version=${version} constraint=${constraint} verdict=${verdict}"
  return 0
}

# ─── Environment class ───────────────────────────────────────────────────────

# The flag current CLI builds need for the native task tools. A commented-out
# line does not count: it is the state a user lands in after commenting the
# export out, and reporting it as present would make setup skip the very
# repair that is wanted.
detect_env_todo_tools() {
  local rc present=no
  rc="$(_detect_shell_rc)"
  if [ -f "$rc" ] && grep -qE '^[[:space:]]*export[[:space:]]+CLAUDE_CODE_ENABLE_TODO_TOOLS=1' "$rc" 2>/dev/null; then
    present=yes
  fi
  echo "env:todo-tools present=${present}"
  return 0
}

# The legacy alias block claude-bootstrap.sh used to write:
#
#     # ─── bionic:start ───
#     alias claude='claude --dangerously-skip-permissions'
#     # ─── bionic:end ───
#
# Auto mode is the default now and the safer equivalent, so the block is
# retired footprint that setup removes. The markers are matched verbatim,
# box-drawing dashes included — they are what makes the block addressable.
detect_zshrc_legacy_block() {
  local rc present=no
  rc="$(_detect_shell_rc)"
  if [ -f "$rc" ] && grep -qF '# ─── bionic:start ───' "$rc" 2>/dev/null; then
    present=yes
  fi
  echo "env:zshrc-legacy present=${present}"
  return 0
}

# Managed-hook entries in USER settings.json that still point at the
# pre-plugin copies under ~/.claude/hooks/. The plugin channel registers hooks
# through the payload's own hooks.json using ${CLAUDE_PLUGIN_ROOT}, so any
# settings.json command naming .claude/hooks/ is registered through the
# SETTINGS channel rather than the plugin channel.
#
# THAT IS ALL THIS COUNTS, and the name says so. The predicate is a path match
# with no staleness term in it: on a machine that has not cut over yet, the
# entries it finds are six LIVE hooks doing their job, and calling them "stale"
# was a claim this function has no evidence for. Which channel a hook is
# registered through is a fact; whether that registration is redundant depends
# on the cutover, which is a later wave's business. Callers that want to say
# more must find the extra evidence themselves.
#
# THE PREDICATE AND THE PROGRAM ARE NAMED, not inline, because remove.sh's
# standalone door carries a second copy of both — legitimately, since that door
# has to run on the machine where these libraries are already gone. A copy that
# is entitled to exist still has to be pinned against its original, and an
# inline program is a program the pin cannot reach: tests/remove.test.sh
# extracts these two assignments, neutralises the one difference the two files
# are entitled to (the variable's name), and requires the rest to be equal.
# hooks.sh's header makes the same argument for the STRIP program; this is the
# other half of the same channel.
DETECT_LEGACY_HOOK_SUBSTR='.claude/hooks/'

DETECT_LEGACY_HOOK_COUNT_JQ='
  [ (.hooks // {}) | to_entries[] | .value[]? | .hooks[]?
    | .command? // empty
    | select(contains("'"${DETECT_LEGACY_HOOK_SUBSTR}"'")) ] | length
'

detect_legacy_channel_hooks() {
  local settings count
  settings="${BIONIC_SETTINGS_FILE:-${BIONIC_CLAUDE_HOME:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}}/settings.json}"
  if ! command -v jq >/dev/null 2>&1; then
    echo "env:legacy-channel-hooks count=unknown"
    return 0
  fi
  if [ ! -f "$settings" ]; then
    echo "env:legacy-channel-hooks count=0"
    return 0
  fi
  count="$(jq "$DETECT_LEGACY_HOOK_COUNT_JQ" "$settings" 2>/dev/null)"
  case "$count" in
    ''|*[!0-9]*) count=unknown ;;
  esac
  echo "env:legacy-channel-hooks count=${count}"
  return 0
}

# ─── The legacy installed skill copy ─────────────────────────────────────────
#
# The retired installer rendered bionic's skills into the CLI's OWN skills
# directory. The plugin ships the same skill inside its payload, so after the
# cutover the installed copy is a SECOND canonical-sdlc — and not an inert one.
# Epic-17 W5 (4/6) measured eleven hook-registration lines in that copy's
# frontmatter, every one of them spelled for the pre-plugin hooks directory: a
# session that loads it arms the same walls twice, once through the channel the
# cutover was supposed to have retired, and nothing in the output says so.
#
# ONE NAME, NOT A WILDCARD. The same installer left copies of bionic's other
# skills behind. 4/6 measured those as registering nothing, and what to do with
# them is the wave's close-out decision — a consented step reading a wildcard
# would remove directories nobody has decided about, which is a larger defect
# than the one it fixes. So the name is stated, and the caller offers exactly
# what this function found.
#
# THE PREDICATE IS THE DIRECTORY PLUS ITS SKILL.md. A bare directory of that
# name is not evidence of a rendered skill, and "present" is about to authorise
# a recursive delete: the file the installer always wrote is what makes the
# claim, not the directory alone.
DETECT_LEGACY_SKILL_NAME='canonical-sdlc'

detect_legacy_skill_copy() {
  local dir present=no
  dir="${BIONIC_CLAUDE_HOME:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}}/skills/${DETECT_LEGACY_SKILL_NAME}"
  if [ -d "$dir" ] && [ -f "${dir}/SKILL.md" ]; then
    present=yes
  fi
  echo "env:legacy-skill-copy present=${present} path=${dir}"
  return 0
}

# ─── The legacy installed agent role files ───────────────────────────────────
#
# The same installer copied the six rendered role files into the CLI's own
# agents directory. Role files are instructions a dispatched subagent obeys, so
# a machine carrying installed copies can be running a build of its own
# dispatch discipline that no plugin update will ever reach — the payload moves,
# the copies do not, and nothing else on the machine reports the gap.
#
# THIS IS THE OTHER QUESTION FROM `detect_agent_integrity`, and the two are
# easy to confuse. That one asks whether the PAYLOAD's files still match the
# checksums the payload shipped: a local-edit question, answered inside the
# plugin. This one asks whether a SECOND, older set exists outside the plugin
# at all. A machine can be perfectly stock by the first measure and two builds
# behind by this one.
#
# DIGESTED, NOT DIFFED, and through the same `_detect_sha256` the integrity
# function uses. A direct `cmp` would have been simpler to read and would have
# added a tool this library does not otherwise require — measured absent from
# the hermetic suite's own PATH, which is the fixture standing in for a machine
# that lacks it. Reusing the digest helper means one dependency for both agent
# questions and one `unknown` arm, phrased the same way, when it is missing.
#
# TWO UNKNOWNS, both real: no digest tool, and a payload with no agents/
# directory to compare against. Answering `absent` for either would report the
# state this function exists to detect as the state it exists to reassure about.
detect_installed_agent_copies() {
  local root dir f name total=0 drift=0 names="" payload_total=0 want got

  root="$(_detect_plugin_root)"
  dir="${BIONIC_CLAUDE_HOME:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}}/agents"

  for f in "${root}/agents/"*.md; do
    [ -f "$f" ] || continue
    payload_total=$((payload_total + 1))
  done
  if [ "$payload_total" = 0 ]; then
    echo "env:installed-agents state=unknown total=0 drift=0 names=- cause=this payload ships no agents/ directory to compare against"
    return 0
  fi
  if ! command -v shasum >/dev/null 2>&1 && ! command -v sha256sum >/dev/null 2>&1; then
    echo "env:installed-agents state=unknown total=0 drift=0 names=- cause=neither shasum nor sha256sum is on PATH, so the installed copies cannot be compared"
    return 0
  fi

  if [ ! -d "$dir" ]; then
    echo "env:installed-agents state=absent total=0 drift=0 names=- cause=-"
    return 0
  fi

  # Payload-side names only. A file in the installed directory that the payload
  # does not ship is somebody else's agent, not bionic's leftover, and counting
  # it would report a machine's own work as bionic drift.
  for f in "${root}/agents/"*.md; do
    [ -f "$f" ] || continue
    name="${f##*/}"
    [ -f "${dir}/${name}" ] || continue
    total=$((total + 1))
    want="$(_detect_sha256 "$f")"           || want=""
    got="$(_detect_sha256 "${dir}/${name}")" || got=""
    if [ -z "$want" ] || [ "$got" != "$want" ]; then
      drift=$((drift + 1))
      names="${names:+${names},}${name}"
    fi
  done

  if [ "$total" = 0 ]; then
    echo "env:installed-agents state=absent total=0 drift=0 names=- cause=-"
  else
    echo "env:installed-agents state=present total=${total} drift=${drift} names=${names:--} cause=-"
  fi
  return 0
}

# ─── Plugin registration ─────────────────────────────────────────────────────
#
# Is bionic registered with the CLI on this machine? This is the fact that says
# whether the PLUGIN channel is live, and it is not the same question as
# `detect_plugin_integrity`, which asks whether a payload tree is on disk and
# well-formed: a machine can carry a perfectly good payload the CLI has never
# been told about, and that machine is exactly the one every user is on before
# the cutover.
#
# It matters to more than the half-uninstall verdict. Anything that offers to
# REMOVE a settings-channel registration is implicitly claiming the plugin
# channel covers what it removes, and that claim is only true when this fact
# says yes — setup's step 6 promised it unconditionally until this line existed
# for it to read.
#
# `unknown` is a real answer, not a hedge. A registry file that is present and
# unparseable supports neither "yes" nor "no", and both lies are expensive in
# opposite directions: `no` tells a covered user their hooks will stop firing,
# `yes` tells an uncovered one they are safe to delete their only enforcement.
# A registry that is simply ABSENT is a different case — the CLI writes that
# file when it installs anything, so its absence means nothing is installed.
# The registry file, named ONCE. Both the registration fact and the root resolver below
# read it through this expression, so a machine whose config dir moves cannot have the two
# answering about different files — the drift that makes a "registered" plugin resolve to a
# root nobody installed.
_detect_installed_plugins_file() {
  printf '%s' "${BIONIC_INSTALLED_PLUGINS_FILE:-${BIONIC_CLAUDE_HOME:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}}/plugins/installed_plugins.json}"
}

detect_plugin_registered() {
  local installed_json count
  installed_json="$(_detect_installed_plugins_file)"

  if [ ! -f "$installed_json" ]; then
    echo "plugin:registered=no"
    return 0
  fi

  # No jq: the key is a literal string in the file, so grep answers this one
  # honestly rather than degrading. `"bionic@` cannot match another plugin —
  # the marketplace suffix follows the name, never precedes it.
  if ! command -v jq >/dev/null 2>&1; then
    if grep -q '"bionic@' "$installed_json" 2>/dev/null; then
      echo "plugin:registered=yes"
    else
      echo "plugin:registered=no"
    fi
    return 0
  fi

  count="$(jq -r '[ (.plugins // {}) | keys[] | select(split("@")[0] == "bionic") ] | length' \
            "$installed_json" 2>/dev/null)"
  case "$count" in
    ''|*[!0-9]*) echo "plugin:registered=unknown" ;;
    0)           echo "plugin:registered=no" ;;
    *)           echo "plugin:registered=yes" ;;
  esac
  return 0
}

# ─── The installed plugin root ───────────────────────────────────────────────
#
# WHERE THE PLUGIN ACTUALLY IS, answered out of the CLI's own record rather than guessed.
#
# THE PROBLEM THIS RETIRES. Payload-native scripts are typed into a model's own shell as
# often as they are registered as commands, and `${CLAUDE_PLUGIN_ROOT}` is substituted only
# in the latter. The old spelling covered the gap with `${CLAUDE_PLUGIN_ROOT:-$HOME/.claude}`
# — which always resolves, and resolves to a bootstrap-era copy that can be an OLDER BUILD
# than the plugin the CLI loaded. A stale hook that runs is worse than a missing one: it
# enforces a doctrine nobody is following and reports success doing it.
#
# THE ORACLE IS THE REGISTRY, ratified 2026-08-19 (design ledger D-B). Not because we own
# it — we do not, its schema is CLI-internal — but because it is the same record the CLI
# itself loads from, which is the only property that makes an answer here true. The schema
# being someone else's is why the parse is pinned by tests and why an unreadable file
# REFUSES instead of degrading.
#
# THIS IS THE ONE FUNCTION IN THIS FILE THAT DOES NOT ANSWER `unknown`, and the deviation is
# the point. Every other fact here feeds a REPORT, where "I could not tell" is a legitimate
# and useful value. This one feeds a PATH that something is about to execute, and there is
# no honest degraded form of that: a caller handed a plausible directory cannot tell it
# apart from a resolved one. So the contract is: the absolute installPath on stdout and exit
# 0, or NOTHING on stdout, a named fix on stderr, and exit 1. No fallback exists anywhere in
# this function, deliberately — including the one it was written to replace.
# ─── THE PARSE ──────────────────────────────────────────────────────────────
#
# ONE reading of the registry's schema, for ANY plugin name. Generalized at W5 Step-6
# (review RV-4/RV-7): doctor.sh had grown a second, unpinned parse of the same CLI-internal
# shape, and the pinned one — detect_plugin_root — had no production callsite at all, so the
# copy under test was the copy that did not run. Two readings of a schema we do not own is
# the exact duplication this file's ownership rule exists to forbid: the CLI renames
# `installPath`, one of them gets fixed, and the other keeps answering in the old shape with
# no less confidence.
#
# QUIET, DELIBERATELY, and this is the one place this file's posture splits by CALLER rather
# than by fact. Loudness is a claim about CONSEQUENCE, not about failure. Asking where
# `superpowers` landed and finding it absent is an ORDINARY answer that `/bionic:doctor`
# renders in a table cell twenty times a run; a parse that shouted it would bury the report
# on exactly the half-configured machine the report exists for. So the parse says nothing and
# the SPECIALIZATION below — bionic's own, feeding a path something is about to execute —
# carries the three-line refusal and the named fix.
#
# THE EXIT CODE CARRIES WHAT THE STDERR NO LONGER DOES, so no distinction was lost in the
# move; detect_plugin_root rebuilds its three refusal messages from these:
#
#   0  resolved; the absolute installPath is on stdout
#   2  no registry file at all
#   3  no entry for this name, or the registry could not be parsed
#   4  the entry is there and names a directory that does not exist
#
# THE TWO JQ PROGRAMS ARE ONE PROGRAM. `DETECT_PLUGIN_ROOT_JQ` below stays a bionic-shaped
# one-line literal because it is also the DOCTRINE SEED: skills/canonical-sdlc/SKILL.md
# carries it verbatim for a model to paste at Patrol arming, which is the one moment nothing
# in this file can be sourced yet (resolving the plugin root is precisely what you cannot do
# from inside the plugin). `--arg n` is not pasteable, so the literal cannot simply become
# the general form. tests/dispatch-spans.test.sh §5i reads it out of here with a `sed` that
# requires exactly that spelling, and tests/plugin-lib.test.sh Group S pins the literal to be
# this general program with `$n` bound to "bionic" and nothing else — so the seed cannot
# quietly become a THIRD parse.
DETECT_PLUGIN_INSTALL_PATH_JQ='.plugins // {} | to_entries[] | select(.key | split("@")[0] == $n) | .value[0].installPath // empty'
DETECT_PLUGIN_ROOT_JQ='.plugins // {} | to_entries[] | select(.key | split("@")[0] == "bionic") | .value[0].installPath // empty'

# The raw reading: what the registry RECORDS for this name, with no claim that the
# directory is there. Split out from the public function for one reason — the refusal
# detect_plugin_root prints when a recorded tree has vanished has to NAME the path it could
# not find, and the public function deliberately hands back nothing in that case. One parse,
# two questions: "what is written down" and "is it true".
_detect_registry_install_path() {  # <plugin-name>
  local name="${1:-}" reg path

  [ -n "$name" ] || return 3

  reg="$(_detect_installed_plugins_file)"
  [ -f "$reg" ] || return 2

  if command -v jq >/dev/null 2>&1; then
    path="$(jq -r --arg n "$name" "$DETECT_PLUGIN_INSTALL_PATH_JQ" "$reg" 2>/dev/null | head -1)"
  else
    # No jq: the key is a literal string in the file, and the marketplace suffix follows the
    # name rather than preceding it, so `"<name>@` is a whole-name match — `superpowers-extras@`
    # does not carry the `@` in that position. `index()` and not a regex, on purpose: a plugin
    # name is someone else's string and a `.` or `+` in it must be a character, not a
    # metacharacter. The first installPath after the key is this entry's; `exit` stops before
    # the next plugin's.
    path="$(awk -v key="\"${name}@" '
      index($0, key) { f = 1 }
      f && /"installPath"/ {
        line = $0
        sub(/.*"installPath"[[:space:]]*:[[:space:]]*"/, "", line)
        sub(/".*/, "", line)
        print line
        exit
      }' "$reg" 2>/dev/null)"
  fi

  case "$path" in
    ''|null) return 3 ;;
  esac

  printf '%s\n' "$path"
  return 0
}

detect_plugin_install_path() {  # <plugin-name>
  local path st
  path="$(_detect_registry_install_path "${1:-}")"; st=$?
  [ "$st" -eq 0 ] || return "$st"
  [ -d "$path" ] || return 4
  printf '%s\n' "$path"
  return 0
}

# ─── The installed plugin root ───────────────────────────────────────────────
#
# WHERE THE PLUGIN ACTUALLY IS, answered out of the CLI's own record rather than guessed.
# Bionic's specialization of the parse above; the reading is shared, the POSTURE is this
# function's own.
#
# THE PROBLEM THIS RETIRES. Payload-native scripts are typed into a model's own shell as
# often as they are registered as commands, and `${CLAUDE_PLUGIN_ROOT}` is substituted only
# in the latter. The old spelling covered the gap with `${CLAUDE_PLUGIN_ROOT:-$HOME/.claude}`
# — which always resolves, and resolves to a bootstrap-era copy that can be an OLDER BUILD
# than the plugin the CLI loaded. A stale hook that runs is worse than a missing one: it
# enforces a doctrine nobody is following and reports success doing it.
#
# THE ORACLE IS THE REGISTRY, ratified 2026-08-19 (design ledger D-B). Not because we own
# it — we do not, its schema is CLI-internal — but because it is the same record the CLI
# itself loads from, which is the only property that makes an answer here true. The schema
# being someone else's is why the parse is pinned by tests and why an unreadable file
# REFUSES instead of degrading.
#
# THIS IS THE ONE FUNCTION IN THIS FILE THAT DOES NOT ANSWER `unknown`, and the deviation is
# the point. Every other fact here feeds a REPORT, where "I could not tell" is a legitimate
# and useful value. This one feeds a PATH that something is about to execute, and there is
# no honest degraded form of that: a caller handed a plausible directory cannot tell it
# apart from a resolved one. So the contract is: the absolute installPath on stdout and exit
# 0, or NOTHING on stdout, a named fix on stderr, and exit 1. No fallback exists anywhere in
# this function, deliberately — including the one it was written to replace.

_detect_plugin_root_refuse() {  # <what went wrong>
  echo "detect_plugin_root: REFUSED — $1" >&2
  echo "  Fix: claude plugin install bionic@bionic" >&2
  echo "  There is deliberately no fallback root: a guessed path can be an older build than" >&2
  echo "  the one the CLI loads, and a stale hook that runs is worse than a missing one." >&2
  return 1
}

detect_plugin_root() {
  local root st reg

  # The refusals name the file and the path, so the registry expression is re-read here for
  # the MESSAGE only — never for a second answer. The parse below is the only reading that
  # decides anything.
  reg="$(_detect_installed_plugins_file)"

  root="$(detect_plugin_install_path bionic)"
  st=$?
  [ "$st" -eq 0 ] && { printf '%s\n' "$root"; return 0; }

  case "$st" in
    2) _detect_plugin_root_refuse "no plugin registry at ${reg} — bionic is not installed." ;;
    4) _detect_plugin_root_refuse "the registry names $(_detect_registry_install_path bionic) as bionic's install path, and no such directory exists — the install is broken or half-removed." ;;
    *) _detect_plugin_root_refuse "no bionic entry in ${reg}, or the registry could not be read — bionic is not installed." ;;
  esac
  return 1
}

# ─── Half-uninstalled ────────────────────────────────────────────────────────
#
# The plugin is gone but its machine footprint is not. This is the state
# `/bionic:remove`'s standalone door (AC-4) exists to serve, which fixes how
# the question must be asked: NOT "does this payload tree exist" — in the case
# being detected the payload tree is exactly what is missing — but "is bionic
# still registered with the CLI, and is there anything left behind".
#
# Three of the four pieces of footprint are detect.sh's own: the legacy rc
# block, stale managed-hook entries, and the todo-tools export setup writes.
# The fourth — the applied permission marker block — is profile.sh's fact, and
# it is reachable ALONE: decline the permission-block question during
# /bionic:remove, accept the uninstall, and it is the only thing left.
#
# So the fourth term is consulted SOFTLY. `declare -F` asks whether the caller
# has profile.sh loaded and uses the fact when it does (doctor sources both);
# when it does not, the disjunction is the three terms it has always been.
# That is not defensive habit — this function's whole reason to exist is the
# machine where the payload is gone, and a hard dependency on a sibling library
# would fail exactly there. profile.sh's line wears this file's shape on
# purpose, so `applied=` reads the way `present=` does.
detect_half_uninstalled() {
  local registered footprint=no line

  # The registration probe used to live inline here, which made it a fact only
  # this verdict could see. It is `detect_plugin_registered` now; nothing about
  # the disjunction below changed, including that an `unknown` registration is
  # NOT treated as "gone" — this verdict tells the user their machine is broken
  # and points them at the standalone remove door, and it must not say that on
  # a registry it could not read.
  line="$(detect_plugin_registered)"
  case "$line" in
    "plugin:registered=no") registered=no ;;
    *)                      registered=yes ;;
  esac

  if [ "$registered" = "no" ]; then
    line="$(detect_zshrc_legacy_block)";   [ "$line" = "env:zshrc-legacy present=yes" ] && footprint=yes
    line="$(detect_env_todo_tools)";       [ "$line" = "env:todo-tools present=yes" ] && footprint=yes
    line="$(detect_legacy_channel_hooks)"
    case "$line" in *"count=0"|*"count=unknown") ;; *) footprint=yes ;; esac
    if declare -F detect_profile_state >/dev/null 2>&1; then
      line="$(detect_profile_state)"
      case "$line" in *"applied=yes"*) footprint=yes ;; esac
    fi
  fi

  if [ "$registered" = "no" ] && [ "$footprint" = "yes" ]; then
    echo "state:half-uninstalled=yes"
  else
    echo "state:half-uninstalled=no"
  fi
  return 0
}

# ─── Sweep ───────────────────────────────────────────────────────────────────
#
# Every fact, once, in a stable order. doctor renders this; it does not
# recompute any of it.
detect_all() {
  local name
  detect_plugin_integrity
  detect_env_todo_tools
  detect_zshrc_legacy_block
  detect_legacy_channel_hooks
  detect_legacy_skill_copy
  detect_installed_agent_copies
  detect_plugin_registered
  detect_half_uninstalled
  while IFS= read -r name; do
    [ -n "$name" ] && detect_dep "$name"
  done < <(dep_names)
  return 0
}
