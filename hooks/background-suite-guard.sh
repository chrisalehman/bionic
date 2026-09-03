#!/bin/bash
# BACKGROUND-SUITE GUARD — a subagent may not run a suite where nobody reads the output.
# (B-9, wave-bionic-1.3.2; spec R-9, AC-23/AC-24.)
#
# THE DEFECT. A dispatched agent that runs `bash tests/run.sh` with the Bash tool's
# `run_in_background: true` gets a shell id back instead of a result. The suite runs, the
# agent's turn ends, and the evidence the slice was dispatched to produce exists nowhere:
# no file, no transcript, no exit status anyone read. The fix the role files carry in prose
# — foreground, bounded by the Bash tool's own `timeout` parameter, output tee'd to an
# evidence log — is a rule, and a rule that only lives in prose is a wish. This is the wall.
#
# WHAT IT REFUSES. Exactly one shape: a Bash call whose `tool_input.run_in_background` is
# `true` AND whose command is suite-class by payload/scripts/lib/cmd-class.sh. Everything
# else exits 0 in silence — a backgrounded `git status`, a foreground suite, and a suite
# whose `run_in_background` key is simply absent.
#
# ABSENT, NOT FALSE. The CLI omits `run_in_background` from `tool_input` when the caller
# did not set it (@anthropic-ai/claude-code 2.1.251, sdk-tools.d.ts:722 declares it
# optional on the Bash tool input), so the test is `== true` and never `!= false`.
#
# WHERE IT LIVES. hooks/hooks.json, PreToolUse|Bash, BEHIND hooks/agent-context-guard.sh —
# so it is alive only inside an agent context of a session that is armed (design D2, Chris
# 2026-08-30). The main thread is already walled by hooks/farm-out-reminder.sh on the skill
# channel, which refuses a suite there whether backgrounded or not; registering this raw
# as well would refuse background suites in every session on the machine, bionic or not.
# The guard in front owns `agent_id` and the roster; this file re-checks neither, which is
# what lets the positive controls in tests/cmd-class.test.sh drive it straight.
#
# Exit 2 + stderr = block the tool call, the protect-main.sh convention. Exit 0 otherwise.
# [WALL: tests/cmd-class.test.sh]

set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0
INPUT=$(cat) || exit 0
[ -n "$INPUT" ] || exit 0

_jq() { printf '%s' "$INPUT" | jq -r "$1 // empty" 2>/dev/null || printf ''; }

[ "$(_jq '.tool_name')" = "Bash" ] || exit 0
[ "$(_jq '.tool_input.run_in_background|tostring')" = "true" ] || exit 0
COMMAND=$(_jq '.tool_input.command')
[ -n "$COMMAND" ] || exit 0

# ---------- the command reader ----------
#
# One loader idiom, byte-identical in every hook; its source of truth is
# payload/scripts/lib/loader.sh, and tests/hook-adoption.test.sh pins this copy
# against it. The idiom heals before it fails: a library damaged beside this hook is
# still found in the marketplace source tree or the newest plugin-cache version.
#
# FAIL OPEN (design ledger S4, bionic 1.4.0). It refused until 1.4.0, on the reasoning
# the two irreversible-action walls still use. It is not one of them: what this guard
# prevents is a suite whose OUTPUT nobody reads, which costs a re-run — reversible, and
# cheap next to refusing every backgrounded command in every session on the machine
# because one file is missing. The failure directions in this repo are chosen by the
# cost of the mistake, never uniformly.
BIONIC_LIB_WANT="cmd-class.sh"
# --- bionic-loader/v2 BEGIN
# Find the bionic library. This text is pasted BYTE-IDENTICALLY into every hook; a
# library cannot load itself, so the duplication is the design and
# tests/cross-gate-agreement.test.sh pins every copy against `bionic_loader_pin` in
# payload/scripts/lib/loader.sh. Behaviour: tests/loader.test.sh.
#
# CONTRACT. Set BIONIC_LIB_WANT to the space-separated basenames this hook sources,
# on a line above this block. Afterwards exactly one of these is non-empty:
#   BIONIC_LIB          a readable directory holding every wanted basename
#   BIONIC_LIB_MISSING  the library this hook wanted and did not get
# BIONIC_LIB_CANDS always lists, in order, every location that was tried.
#
# CANDIDATES. Later classes are evaluated only after the earlier ones fail, so a
# healthy hook pays nothing for the healing path — not a jq, not a registry read.
#  (1) beside the hook. TWO SPELLINGS OF ONE DIRECTORY, because the shipped tree has
#      two real shapes: the installed plugin root, where hooks/ and scripts/ are
#      siblings, and the repo, where payload/hooks is a symlink to the top-level
#      hooks/ and the library lives under payload/scripts/lib. "$0" is textual and
#      `..` is resolved by the kernel AFTER the symlink, so the first spelling alone
#      would find nothing in a directory-source session.
#  (2) the marketplace SOURCE TREE. installed_plugins.json names the marketplace this
#      plugin was installed from; that marketplace's source.path in
#      known_marketplaces.json is the tree. The marketplace is read, never assumed:
#      a fork installs under its own name.
#  (3) the newest version directory in that marketplace's plugin cache, by
#      THREE-INTEGER compare — 1.10.0 beats 1.3.2, which a lexical sort gets backwards.
# (2) and (3) heal a partial breakage: one location damaged, a sibling intact. An
# upstream-broken publish breaks every location equally and is not covered.
#
# TESTS OVERRIDE THE MACHINE, never the reverse. BIONIC_PLUGINS_DIR (default
# "$HOME/.claude/plugins") is the only door to the registry and the cache.
BIONIC_LIB=""; BIONIC_LIB_MISSING=""; BIONIC_LIB_CANDS=""
_bl_dir="$(dirname "$0")"
_bl_want="${BIONIC_LIB_WANT:-}"
_bl_try() {
  [ -n "${1:-}" ] || return 1
  if [ -z "$BIONIC_LIB_CANDS" ]; then BIONIC_LIB_CANDS="$1"; else BIONIC_LIB_CANDS="$BIONIC_LIB_CANDS, $1"; fi
  [ -d "$1" ] || return 1
  for _bl_f in $_bl_want; do [ -r "$1/$_bl_f" ] || return 1; done
  BIONIC_LIB="$1"
}
if ! _bl_try "$_bl_dir/../scripts/lib" && ! _bl_try "$_bl_dir/../payload/scripts/lib"; then
  _bl_pd="${BIONIC_PLUGINS_DIR:-${HOME:-/nonexistent}/.claude/plugins}"
  _bl_mk=""
  if [ -r "$_bl_pd/installed_plugins.json" ]; then
    # First key only, and the prefix stripped by parameter expansion rather than
    # `sed | head`: the block's only external commands are `dirname` and `jq`, and
    # `jq` runs with its stderr closed, so a machine missing jq degrades to
    # BIONIC_LIB_MISSING in silence instead of printing a shell diagnostic.
    _bl_keys="$(jq -r '(.plugins // {}) | keys[] | select(startswith("bionic@"))' "$_bl_pd/installed_plugins.json" 2>/dev/null)"
    _bl_mk="${_bl_keys%%
*}"
    _bl_mk="${_bl_mk#bionic@}"
  fi
  if [ -n "$_bl_mk" ]; then
    _bl_src=""
    if [ -r "$_bl_pd/known_marketplaces.json" ]; then
      _bl_src="$(jq -r --arg mk "$_bl_mk" '.[$mk].source.path // empty' "$_bl_pd/known_marketplaces.json" 2>/dev/null)"
    fi
    if [ -n "$_bl_src" ]; then _bl_try "$_bl_src/payload/scripts/lib" || :; fi
    if [ -z "$BIONIC_LIB" ]; then
      _bl_best=""; _bl_bestk=""
      for _bl_v in "$_bl_pd/cache/$_bl_mk/bionic"/*; do
        [ -d "$_bl_v" ] || continue
        _bl_n="${_bl_v##*/}"
        case "$_bl_n" in ''|*[!0-9.]*) continue ;; esac
        _bl_x1=""; _bl_x2=""; _bl_x3=""
        IFS=. read -r _bl_x1 _bl_x2 _bl_x3 _bl_rest <<BIONIC_LOADER_VER
$_bl_n
BIONIC_LOADER_VER
        _bl_k="$(printf '%05d%05d%05d' "$((10#${_bl_x1:-0}))" "$((10#${_bl_x2:-0}))" "$((10#${_bl_x3:-0}))" 2>/dev/null)" || continue
        if [ -z "$_bl_bestk" ] || [ "$_bl_k" \> "$_bl_bestk" ]; then _bl_bestk="$_bl_k"; _bl_best="$_bl_n"; fi
      done
      if [ -n "$_bl_best" ]; then _bl_try "$_bl_pd/cache/$_bl_mk/bionic/$_bl_best/scripts/lib" || :; fi
    fi
  fi
fi
if [ -z "$BIONIC_LIB" ]; then
  # The name in the message is the first library this hook asked for. A candidate
  # directory qualifies only when it holds ALL of them, so with none qualifying the
  # first wanted name is the honest thing to hand the reader.
  BIONIC_LIB_MISSING="${_bl_want%% *}"
  [ -n "$BIONIC_LIB_MISSING" ] || BIONIC_LIB_MISSING="scripts/lib"
fi
# FAIL OPEN — for every hook whose work is advisory or reversible. One line, then
# stand aside. Blocking reversible work because a file is missing buys no safety and
# costs the session.
loader_fail_open() {
  echo "$1: library ${BIONIC_LIB_MISSING:-the bionic library} not found at ${BIONIC_LIB_CANDS:-(no candidate)} — hook stepping aside; run /bionic:doctor" >&2
  exit 0
}
# FAIL CLOSED — for a wall over an irreversible action. Refuse, but never lock the
# user out of the repair: four commands are permitted by WHOLE-STRING match, checked
# here, before the hook sources anything. Whole-string and not prefix, so
# `claude plugin update bionic@bionic; git push origin main` is refused like any
# other push. There is no env-var override: a variable an agent turn can set on
# itself is not a wall.
loader_fail_closed() {
  _bl_root="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd -P)" || _bl_root=""
  [ -n "$_bl_root" ] || _bl_root="$(dirname "$0")/.."
  case "${2:-}" in
    "claude plugin update bionic@bionic"|\
    "claude plugin install bionic@bionic"|\
    "bash $_bl_root/scripts/doctor.sh"|\
    "bash $_bl_root/scripts/setup.sh") exit 0 ;;
  esac
  cat >&2 <<BIONIC_LOADER_REFUSE
BLOCKED: $1 cannot load its library (${BIONIC_LIB_MISSING:-the bionic library}), so it
cannot read this command. A wall that cannot read a command refuses it rather than
waving it through.

Looked in: ${BIONIC_LIB_CANDS:-(no candidate)}

Until the plugin is whole again this wall permits exactly four commands, each matched
as a whole string:

    claude plugin update bionic@bionic
    claude plugin install bionic@bionic
    bash $_bl_root/scripts/doctor.sh
    bash $_bl_root/scripts/setup.sh

Anything else is refused, including one of those four with another command chained
after it. Run one of them, or act from your own terminal.
BIONIC_LOADER_REFUSE
  exit 2
}
# --- bionic-loader/v2 END
if [ -n "$BIONIC_LIB_MISSING" ]; then loader_fail_open "background-suite-guard"; fi
# shellcheck source=/dev/null
. "$BIONIC_LIB/cmd-class.sh"

[ "$(cmd_class "$COMMAND")" = "suite" ] || exit 0

# ---------- refuse, naming the shape that works ----------
#
# The command is echoed back so the fix is a copy-paste rather than a retype. It is the
# agent's own text going back to the agent — no third party reads this stream — so it is
# quoted whole rather than scrubbed and truncated the way farm-out-reminder.sh's audit
# line is.
cat >&2 <<EOF
BLOCKED: a suite may not run with run_in_background — nobody would read the result.

A backgrounded suite returns a shell id, not an outcome. Your turn can end before it
finishes, and then the evidence this slice exists to produce lives nowhere: no file, no
exit status anyone saw. Reports are turn-scoped; files are not.

Run it in the FOREGROUND instead, bounded by the Bash tool's own timeout parameter (never
a timeout/gtimeout binary), with the output tee'd to the evidence log your brief names:

    $COMMAND 2>&1 | tee <evidence log>

Then read the log and quote the pass/total line. If the suite is genuinely longer than any
timeout you can set, say so in your report and stop — do not background it.
EOF
exit 2
