#!/bin/bash
# setup.sh — `/bionic:setup` (epic-17 wave-03, spec AC-2 and AC-6).
#
# WHAT THIS SCRIPT OWNS. The whole of tier 2: everything that has to be true of
# a MACHINE for bionic to work, in one idempotent, re-runnable pass. Tier 2
# contains tier 1 — the native plugin install is this script's first step, not a
# prerequisite the user is expected to have done — so `/bionic:setup` is a
# complete answer to "set this machine up", whether the box is three quarters of
# the way there or has nothing but bionic's marketplace registered.
#
# THAT PRECONDITION IS REAL AND IT IS NOT "COLD". Step 1 installs the plugin; it
# does not ADD the marketplace the plugin comes from, and `claude plugin
# marketplace add` is a mutation nobody consented to at the moment this script
# is reached. A genuinely cold box needs that one command by hand first (the
# Step-5 field walk measured exactly this). It is not machinery worth building:
# in the production story the user reaches `/bionic:setup` through the installed
# plugin, so the only caller who can be on a cold box is a developer running
# this script directly, and they are the person who added the marketplace.
#
# WHAT IT DOES NOT OWN. Facts and mechanisms. Whether a dependency is present is
# `detect.sh`/`deps.sh`'s answer; HOW a dependency installs is `deps.sh`'s
# `install_dep`, the same function a just-in-time offer calls (AC-5: one owner,
# no second installer); how the permission profile renders and applies is
# `profile.sh`. This script decides ORDER, asks the questions, and reports. Any
# fact it recomputed itself would be a second implementation of somebody else's
# truth, which is the defect the wave's ownership table exists to prevent.
#
# THE NINE STEPS, in this order and for these reasons:
#
#   1. plugin               tier 1 first: everything after it assumes the payload
#                           is installed, and a machine that skips it gets an
#                           honest action line rather than six confusing ones.
#   2. dependencies         the two plugins bionic declares. The harness installs
#                           these; what it does NOT always do is leave them
#                           enabled (measured: W1 run B landed superpowers
#                           `enabled: false`). Repair is an explicit `claude
#                           plugin enable`, never a reinstall.
#   3. tools                the substrate every machine needs — git, node, jq and
#                           the rest — one row at a time through `install_dep`,
#                           the same function a just-in-time offer calls.
#   4. optional extras      the four tools nobody needs to work: offered once,
#                           each with a line of what it is, default No.
#   5. shell environment    CLAUDE_CODE_ENABLE_TODO_TOOLS=1, marker-scoped.
#   6. legacy shell alias   the block claude-bootstrap.sh used to write. Auto
#                           mode is the default now and the safer equivalent, so
#                           the block is retired footprint. Ported here because
#                           the installer retires at W5 and this obligation must
#                           not retire with it.
#   7. legacy-channel hooks settings.json entries still naming the machine's
#                           pre-plugin hooks directory. The plugin registers its
#                           own hooks through the payload's hooks.json, so a
#                           settings entry naming that directory is registered
#                           through the OTHER channel. Also ported from the
#                           retiring installer.
#   8. legacy skill copy    the skill directory claude-bootstrap.sh rendered into
#                           the CLI's own skills directory. The payload ships the
#                           same skill, so the installed copy is a second one that
#                           still registers hooks through the pre-plugin channel.
#                           Named by AC-8; the gap 4/6 found and reported.
#   9. permission profile   rendered against this machine's plugin root and
#                           applied under explicit consent (AC-6). Consent is
#                           obtained HERE and handed to `profile_apply` as a
#                           token: the library never asks, so there is exactly
#                           one place in the system where consent is decided.
#                           The step ends with one more question about the same
#                           settings file — whether Claude Code's default
#                           permission mode should be auto (AC-12).
#
# AND TWO THINGS THAT ARE NOT STEPS, both between 1 and 2 (wave-06 S5). The
# LOAD STATE is printed at step 1's indentation with no header of its own,
# because it is not another thing setup does — it is the half of step 1 the
# install's exit code cannot report (AC-13). DUPLICATES is a block that exists
# only on a machine that has some: it carries no number precisely because it is
# usually absent, and a numbered step missing from most transcripts would leave
# a hole in the sequence the nine steps above are counted in (AC-8).
#
# WHICH TOOLS THIS SCRIPT IS ALLOWED TO ASK ABOUT (wave-06 D-B, spec AC-11).
# Steps 3 and 4 walk `dep_names_class basic` and `dep_names_class extra`, and
# nothing here walks `when-needed`. That class exists because the moment to ask
# about a headless browser is the moment a route wants one — `lib/jit.sh` makes
# that offer, from the same `install_dep`. Setup asking would be asking about a
# capability the user has not reached, and one of those rows (impeccable) is
# native-kind, which `install_dep` is required to refuse outright. The classes
# are read from the table, never restated here: a second roster is a second
# opinion about what bionic depends on.
#
# CONSENT, AND WHY THERE IS ONE PROMPT SHAPE. Every mutation below is gated, per
# item, on an explicit `y` on this script's own standard input, and the gate is
# `deps.sh`'s `_dep_consent`
# — not a second prompt implementation. The plan is printed BEFORE the question
# and executed AFTER it, from the same string, so what the user agreed to is by
# construction what runs. There is no assume-yes knob: an env var that switched
# consent off would be the hole in "consent per event, never silent, never
# unattended". A closed stdin therefore declines everything, which is the
# fail-closed direction.
#
# WARN AND CONTINUE. `set -e` is deliberately absent. A machine that cannot do
# step 3 can still do steps 4-9, and stopping at the first problem is how a user
# ends up running setup five times. Every step that could not finish appends an
# ACTION LINE, and the run ends with all of them together — the summary is the
# interface, not the scroll. Exit status is 0 whenever setup itself worked,
# including a run where the user declined everything; declining is a valid
# answer, not an error.
#
# HONEST UNKNOWNS. `jq` is itself a row in the dependency table, so a cold
# machine may not have it. Where a fact cannot be read without it, this script
# says `unknown` and names jq as the fix rather than guessing — and never
# mutates on an unknown. Running setup twice on such a machine (once to install
# jq, once to use it) is the intended path, which is exactly what idempotence
# buys.
#
# IDEMPOTENT, AND WHAT THAT MEANS PRECISELY. A second run against an
# already-set-up machine performs no mutation and leaves every file it touches
# byte for byte identical. Each step's guard is the fact function that owns the
# question, so "already done" is decided by the same code doctor reports with.
#
# ROOTS ARE OVERRIDABLE, read at CALL time, so the hermetic suite can point the
# whole script at a fixture tree:
#
#   BIONIC_LIB_DIR        where scripts/lib/*.sh live   (default: beside this file)
#   BIONIC_PLUGIN_ROOT    the payload / render target   (or ${CLAUDE_PLUGIN_ROOT})
#   BIONIC_PROFILE_TEMPLATE  the profile template
#   BIONIC_CLAUDE_HOME    the CLI config dir            (or ${CLAUDE_CONFIG_DIR})
#   BIONIC_SETTINGS_FILE  user settings.json
#   BIONIC_INSTALLED_PLUGINS_FILE  the CLI's install registry
#   BIONIC_SHELL_RC       the shell rc bionic edits
#
# TWO FLAGS, AND NEITHER OF THEM IS AN ANSWER (critic F-1 and F-2):
#
#   --list          print the name of every item this machine can be asked about,
#                   one per line, and exit.
#   --only <name>   ask about exactly that one item. Every other item is neither
#                   run nor asked about, so a single answer on the standard input
#                   can only ever consent to the thing that was named.
#
# See "ADDRESSABLE ITEMS" below the constants for why that second flag exists.
#
# Executed, never sourced:  bash ${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh

set -uo pipefail

# No `dirname` here, same reason the libraries give: a cold or half-broken
# machine is exactly where this script has to run.
_setup_self_dir() {
  local self="${BASH_SOURCE[0]}"
  case "$self" in */*) echo "${self%/*}" ;; *) echo "." ;; esac
}

SETUP_LIB_DIR="${BIONIC_LIB_DIR:-$(_setup_self_dir)/lib}"

for _setup_lib in deps.sh detect.sh profile.sh hooks.sh jit.sh; do
  if [ ! -f "${SETUP_LIB_DIR}/${_setup_lib}" ]; then
    echo "setup.sh: cannot find ${SETUP_LIB_DIR}/${_setup_lib} — the payload looks incomplete." >&2
    echo "          reinstall with: claude plugin install bionic@bionic" >&2
    exit 1
  fi
done
# shellcheck source=/dev/null
. "${SETUP_LIB_DIR}/deps.sh"
# shellcheck source=/dev/null
. "${SETUP_LIB_DIR}/detect.sh"
# shellcheck source=/dev/null
. "${SETUP_LIB_DIR}/profile.sh"
# shellcheck source=/dev/null
. "${SETUP_LIB_DIR}/hooks.sh"
# jit.sh, for ONE function: `_jit_fix_line`, which spells the command that would
# install a row by hand. The summary needs that sentence and so does a route's
# just-in-time offer, and it has to be the SAME sentence — an action line that
# named a different command from the one a "yes" would run is a lie the user
# only discovers by pasting it. Sourcing the route contract to reuse its wording
# is cheaper than a second copy of the same derivation, which is what this
# script printed before: the raw `mechanism` field (`brew:git`), a locator the
# table stores and nobody can type.
# shellcheck source=/dev/null
. "${SETUP_LIB_DIR}/jit.sh"

# ─── Constants ───────────────────────────────────────────────────────────────

# THE DEPTH THIS SCRIPT'S BLOCKS SIT AT, declared once for both files that print
# into them (six-axis review R-2). setup's own `say` lines are written three
# spaces in; deps.sh prints the install prose that lands between them, and until
# this existed it used its own two-space literal, so the seam between the two
# files was visible on the user's screen down the whole of step 4.
BIONIC_DEP_INDENT="   "

SETUP_DEP_MARKETPLACE="${BIONIC_DEP_MARKETPLACE:-bionic}"
# The default is COMPOSED from the marketplace above rather than spelled whole,
# because `install_plugin_native` composes the id it installs the same way. A
# machine that re-points bionic's catalog moves both together; two independent
# defaults would move one of them and leave the other naming a plugin nobody
# installed.
SETUP_PLUGIN_ID="${BIONIC_PLUGIN_ID:-bionic@${SETUP_DEP_MARKETPLACE}}"

# bionic's own rc block. DISTINCT markers from the legacy alias block below on
# purpose: step 5 removes that block by exact marker match, and sharing a marker
# would have step 5 delete what step 4 just wrote.
SETUP_ENV_START='# ─── bionic:env:start ───'
SETUP_ENV_END='# ─── bionic:env:end ───'

# The retired alias block's markers, verbatim from claude-bootstrap.sh —
# box-drawing dashes included, because they are what makes the block
# addressable. `SETUP_ALIAS_PATTERN` is the pre-marker spelling the installer
# itself still migrates (claude-bootstrap.sh's do_install_shell_alias), and it
# is a separate case because a machine that stopped bootstrapping before markers
# existed has the alias with no markers around it at all.
SETUP_ALIAS_START='# ─── bionic:start ───'
SETUP_ALIAS_END='# ─── bionic:end ───'
SETUP_ALIAS_PATTERN='alias claude=.*dangerously-skip-permissions'

# ─── Reporting ───────────────────────────────────────────────────────────────
#
# Actions accumulate in one newline-delimited string rather than an array: an
# empty array under `set -u` is an unbound variable on bash 3.2, which is the
# bash a stock macOS box runs this script with.

SETUP_ACTIONS=""

# THE INVOCATION A PERSON CAN TYPE (critic F-1). Consent reaches this script
# through its standard input and nowhere else. The model runs it from a tool
# whose stdin carries nothing, so every question declines — and the action lines
# used to answer that by telling the user to "re-run /bionic:setup and answer y",
# which is the one route that cannot work: a second run through the same command
# declines identically, because the interactivity of the SESSION is not an answer
# channel for the SCRIPT. So an action line that asks for an answer names the
# terminal invocation, resolved to a real path rather than left as a variable the
# reader's shell has never heard of.
_setup_self_path() {
  local dir
  dir="$(cd "$(_setup_self_dir)" 2>/dev/null && pwd -P)" || dir="$(_setup_self_dir)"
  echo "${dir}/${BASH_SOURCE[0]##*/}"
}
SETUP_SELF_CMD="bash $(_setup_self_path)"

# ─── ADDRESSABLE ITEMS ───────────────────────────────────────────────────────
#
# THE PROBLEM (critic F-1 and F-2). Consent reaches this script through its own
# standard input and nowhere else. The model that runs it has nothing to put
# there, so a whole pass declines — and the one channel that DOES work, a single
# answer piped in, is POSITIONAL: it is read by the first question asked, which
# is whichever item this machine happens to have unfinished. A user who says
# "yes, set the permission mode" and has that yes relayed the obvious way gets
# whatever question came first instead. The answer channel worked; it just could
# not be aimed.
#
# THE FIX IS AN ADDRESS, NOT A SWITCH. `--only <name>` runs exactly one item —
# the one named — and asks about nothing else, so an answer delivered that way
# can only consent to the thing the user said yes to. `--list` prints the names.
#
# WHAT DID NOT CHANGE, AND MUST NOT. The answer is still one explicit `y` read
# from this script's own standard input, per item, and a closed input still
# declines. There is no assume-yes flag and no environment knob: `--only`
# narrows WHICH question gets asked, never whether it is asked. A flag that
# answered a question would be the hole in "consent per event, never silent,
# never unattended".
#
# ONE TABLE, TWO READERS. `_setup_item_ids` is the only place the roster is
# spelled. `--list` prints it and `--only` is checked against it, so a name a
# reader can see is a name the dispatcher takes, and a name it will not take is
# not printed anywhere. The rows that come from the dependency table are READ
# from it rather than restated here — a second roster is a second opinion about
# what bionic depends on, which is the defect the ownership table exists to
# prevent. It is also why `--list` names only the tools steps 3 and 4 are
# allowed to ask about: the names come from the same two classes those steps
# walk, so the flag cannot reach a row the full pass would never offer.
#
# THE NAMES ARE THE USER'S WORDS. Each one names the item as the question that
# gates it names it — `permission-mode`, `shell-env`, `tool:git` — never the
# function, the step number or the class behind it.

SETUP_ONLY=""

_setup_item_ids() {
  local n line bare
  say "plugin"
  # fd 3 throughout: these lists must never be read on the standard input, which
  # belongs to the questions.
  while IFS= read -r line <&3; do
    [ -n "$line" ] || continue
    bare="${line#dup=}"; bare="${bare%% *}"
    [ "$bare" = "unknown" ] && continue
    say "duplicate:${bare}"
  done 3< <(detect_plugin_duplicates)
  while IFS= read -r n <&3; do [ -n "$n" ] && say "dependency:${n}"; done 3< <(dep_names_class core)
  while IFS= read -r n <&3; do [ -n "$n" ] && say "tool:${n}"; done 3< <(dep_names_class basic)
  while IFS= read -r n <&3; do [ -n "$n" ] && say "tool:${n}"; done 3< <(dep_names_class extra)
  say "shell-env"
  say "legacy-alias"
  say "legacy-hooks"
  say "legacy-skill-copy"
  say "permission-profile"
  say "permission-mode"
  return 0
}

# True during a whole pass, and during a narrowed run only for the item named.
# Every step below asks this before it prints its own header, so a narrowed run
# is silent about the items it is not doing rather than listing them as skipped.
_setup_wants() {  # <name>
  [ -z "$SETUP_ONLY" ] || [ "$SETUP_ONLY" = "$1" ]
}

# True when a tools step should run at all: always during a whole pass, and
# during a narrowed run only for the step that holds the named tool. Without it
# a narrowed run would print both tools headers and one of them would have
# nothing under it. The class is read from the dependency table, never guessed.
_setup_class_wanted() {  # <class>
  [ -z "$SETUP_ONLY" ] && return 0
  case "$SETUP_ONLY" in tool:*) ;; *) return 1 ;; esac
  [ "$(dep_field "${SETUP_ONLY#tool:}" class)" = "$1" ]
}

# ONE OWNER FOR THE SENTENCE THAT TELLS SOMEONE HOW TO SAY YES. Every declined
# item ends up quoting this, and it must name a route that works: the item's own
# name, and an invocation that delivers one answer to that one question. Written
# once here so an action line and the summary cannot come to differ about what
# the user should run — the same reason the install prose has one owner.
SETUP_YES_PIPE="printf 'y\\n' | "

_setup_answer_yes() {  # <name>
  printf 'answer yes to %s with: %s%s --only %s' "$1" "$SETUP_YES_PIPE" "$SETUP_SELF_CMD" "$1"
}

say()    { printf '%s\n' "$*"; }
action() { SETUP_ACTIONS="${SETUP_ACTIONS}${1}"$'\n'; }
consent() { _dep_consent "$1"; }   # deps.sh owns the one prompt shape

# ─── The CLI's own view of a plugin ──────────────────────────────────────────
#
# Presence of a core dependency is `check_dep`'s answer (it reads the install
# registry, and it is the one owner of that fact). ENABLED-ness is not in that
# registry at all — it lives in the CLI's settings — so it is asked of the CLI
# itself, the same tool that would repair it. Matching is on the NAME half of
# `name@marketplace`, exactly as `_dep_check_native` does, so a dependency
# re-pointed at a different marketplace still resolves.
#
# Prints `<state>|<id>` where state is enabled | disabled | absent | unknown.
# `unknown` is a real answer here: without the CLI or without jq there is no
# honest way to look, and a confident `absent` would make setup offer to install
# a plugin that is already there.

_setup_cli_plugin() {  # <name>
  local name="${1:-}" json row
  command -v claude >/dev/null 2>&1 || { echo "unknown|"; return 0; }
  command -v jq >/dev/null 2>&1     || { echo "unknown|"; return 0; }
  json="$(claude plugin list --json 2>/dev/null)" || { echo "unknown|"; return 0; }
  [ -n "$json" ] || { echo "unknown|"; return 0; }
  row="$(jq -r --arg n "$name" '
      [ .[]? | select(((.id // "") | split("@")[0]) == $n) ] as $m
      | if ($m | length) == 0 then "absent|"
        else (if ($m[0].enabled // false) then "enabled|" else "disabled|" end) + ($m[0].id // "")
        end' <<< "$json" 2>/dev/null)" || row=""
  case "$row" in
    enabled*|disabled*|absent*) echo "$row" ;;
    *)                          echo "unknown|" ;;
  esac
}

# ─── rc block surgery ────────────────────────────────────────────────────────
#
# Ported from claude-reset.sh's alias removal, with one deliberate difference:
# reset deletes the rc file when only whitespace is left, and this script must
# not — step 4 writes to the same file, and a setup that can delete a user's
# shell rc is a setup nobody should run.

_setup_rc_strip_block() {  # <file> <start-marker> <end-marker>
  local file="${1:-}" start="${2:-}" end="${3:-}" tmp
  [ -f "$file" ] || return 0
  grep -qF "$start" "$file" 2>/dev/null || return 0
  tmp="${file}.bionic.tmp"
  awk -v start="$start" -v end="$end" '
    $0 == start { skip=1; next }
    $0 == end   { skip=0; next }
    !skip { print }
  ' "$file" > "$tmp" && mv "$tmp" "$file"
}

# ─── Step 1 — the native plugin install (tier 2 ⊃ tier 1) ────────────────────

setup_plugin_install() {
  _setup_wants plugin || return 0
  say ""
  say "1. Plugin"
  local state id
  IFS='|' read -r state id <<< "$(_setup_cli_plugin bionic)"

  case "$state" in
    enabled|disabled)
      say "   bionic is already installed (${id}) — nothing to do."
      return 0 ;;
    unknown)
      say "   plugin install state is unknown — the claude CLI or jq could not be used to read it."
      action "install jq (and make sure the claude CLI is on PATH), then re-run /bionic:setup — the plugin install state read as unknown"
      return 0 ;;
  esac

  # THE QUESTION AND THE INSTALL BOTH BELONG TO deps.sh NOW (wave-06 S5). This
  # step used to carry its own copy of "name the command, ask, run it", which was
  # fine while it was the only place a plugin got installed — and stopped being
  # fine the moment a just-in-time offer needed the same three lines for a
  # when-needed native row and had nothing to call. There is one such function
  # and both callers reach it, so what a user is asked here and what a route asks
  # mid-session cannot drift into two different conversations.
  if ! install_plugin_native bionic; then
    action "run: claude plugin install ${SETUP_PLUGIN_ID} --scope user --yes (add bionic's marketplace first if it is not registered) — $(_setup_answer_yes plugin)"
  fi
  return 0
}

# ─── After step 1 — is the CLI actually LOADING us? (AC-13, setup half) ──────
#
# THE FACT THE INSTALL'S OWN EXIT CODE CANNOT GIVE. Epic-17 W5 measured it four
# times: `claude plugin install` exits 0, prints a success line and writes the
# registry, and if a dependency is missing the plugin then loads NOTHING — no
# hook, no command, no error anywhere a user would look. Every registry-reading
# check on this machine stays green through it. So the step that installs is
# followed by the one question the install cannot answer itself, asked of the
# only surface that knows: the CLI's own listing.
#
# This prints at the install step's indentation and carries no header of its own,
# because it is not another thing setup DOES — it is what step 1 amounts to.
#
# FOUR STATES, FOUR SENTENCES, and the two that are not good news carry the fix.
# `unknown` renders its cause verbatim: the probe names why it could not look
# (A-4.S2.4), and an unknown with no reason is a shrug the user cannot act on.

#
# BOUNDED, BECAUSE THIS ONE SHELLS OUT (critic F-3). Every other fact step 1
# reads is a file; this one runs the CLI's own listing, and a CLI mid-update or
# a listing waiting on a lock never answers. Unbounded it hung setup here —
# after the install, with the report half-printed, where a user cannot tell a
# wedge from a crash. `detect_bounded` is the same bound doctor uses, from the
# same owner; a timeout arrives as the `unknown` state with the wait named as
# its cause, which is the shape the four-state case below already handles.
setup_load_state() {
  # Not an item: it asks nothing and changes nothing. It is what step 1 amounts
  # to, so it belongs to the whole pass and not to a narrowed one.
  [ -z "$SETUP_ONLY" ] || return 0
  local line state err cause rc
  line="$(detect_bounded "$(detect_probe_seconds)" detect_plugin_load_state "$SETUP_PLUGIN_ID")"
  rc=$?
  if [ "$rc" = "124" ] || [ -z "$line" ]; then
    line="load-state=unknown error=- cause=the plugin listing did not answer within $(detect_probe_seconds) seconds"
  fi
  state="${line#load-state=}"; state="${state%% *}"
  err="${line#*error=}";       err="${err%% cause=*}"
  case "$line" in *cause=*) cause="${line#*cause=}" ;; *) cause="" ;; esac

  case "$state" in
    loaded)
      say "   bionic: loaded."
      ;;
    failed)
      # A real error, so it is reported the way the contract requires: the CLI's
      # own words first, unedited, then one line naming what to do about them.
      say "   bionic is installed but did not load. The CLI reports:"
      say "   ${err}"
      say "   Fix: install what the message names, then start a new session — or reinstall bionic with: claude plugin install ${SETUP_PLUGIN_ID} --scope user --yes"
      action "bionic did not load: ${err}"
      ;;
    absent)
      # Step 1 already owns the install and its action line; saying so twice
      # would make one problem look like two.
      say "   bionic is not in the plugin list, so nothing of it is loaded here yet."
      ;;
    *)
      say "   bionic's load state is unknown — ${cause}"
      action "check that bionic is loading: run claude plugin list and read the Status line for bionic"
      ;;
  esac
  return 0
}

# ─── After the load state — two catalogs, one name (AC-8) ────────────────────
#
# WHY THIS COMES BEFORE ANYTHING IS INSTALLED. A machine can hold
# `superpowers@bionic` and `superpowers@claude-plugins-official` at once, and
# nothing tells the user which one a session loads. Installing more things beside
# an unsettled duplicate just adds to the pile, so the question is asked here —
# after the plugin is in place and before the dependency steps run.
#
# SILENT WHEN THERE IS NOTHING TO SAY. No duplicate means no header, no question,
# no line: on the machines this will mostly run on, this step does not exist.
# That is also why it carries no step NUMBER — a numbered step absent from most
# transcripts leaves a hole in the sequence, and the numbers belong to the nine
# things setup does every time.
#
# THE THREE ANSWERS, AND WHY THE PROMPT IS deps.sh's ONE SHAPE. Chris named
# consolidate / coexist / skip. Setup persists no state of its own, so coexist
# and skip leave the machine in the identical condition and are asked again on
# the next run — two names for one outcome. Rather than invent a second prompt
# mechanism to tell them apart, all three answers are named in the prose and the
# gate is the same `[y/N]` every other question here uses: yes consolidates, no
# leaves both installed and says so.
#
# `dup=unknown` IS NOT A DUPLICATE. It is the probe reporting that it could not
# read the registry, and there is nothing to consolidate — so nothing is offered.
# It is not silence either: silence is the claim "no duplicates", which a reader
# that could not look has not earned.

# The ids to uninstall, one per line, derived from the probe's own fix clause and
# only when every piece of it is exactly `claude plugin uninstall <id>`. This is
# what keeps the consented plan and the executed command the same text without
# ever handing a composed string to a shell: an id is a registry key, and a
# registry key is not something this script gets to trust into `eval`. Anything
# else — notably the "choose one: …" clause the probe returns when bionic has no
# standing to pick a winner — fails the shape test and is reported, not run.
_setup_dup_uninstall_ids() {  # <fix-clause>
  local fix="${1:-}" piece id out=""
  [ -n "$fix" ] || return 1
  while IFS= read -r piece; do
    [ -n "$piece" ] || continue
    case "$piece" in
      "claude plugin uninstall "*) id="${piece#claude plugin uninstall }" ;;
      *) return 1 ;;
    esac
    case "$id" in
      ''|*[!A-Za-z0-9@._-]*) return 1 ;;
    esac
    out="${out}${id}
"
  done <<< "${fix//; /$'\n'}"
  [ -n "$out" ] || return 1
  printf '%s' "$out"
  return 0
}

setup_duplicates() {
  case "$SETUP_ONLY" in ''|duplicate:*) ;; *) return 0 ;; esac
  local line bare ids fix cause header=0 id losers
  # fd 3, not stdin — the consent prompt below reads stdin, and a loop that fed
  # its own list into it would answer every question with the next duplicate.
  while IFS= read -r line <&3; do
    [ -n "$line" ] || continue
    bare="${line#dup=}"; bare="${bare%% *}"
    ids="${line#*ids=}"; ids="${ids%% *}"
    fix="${line#*fix=}"; fix="${fix%% cause=*}"
    case "$line" in *cause=*) cause="${line#*cause=}" ;; *) cause="" ;; esac
    _setup_wants "duplicate:${bare}" || continue

    if [ "$header" = "0" ]; then say ""; say "Duplicates"; header=1; fi

    if [ "$bare" = "unknown" ]; then
      # THE ACTION CARRIES THE CAUSE, it does not guess it (W6 S15, A-6.S15.3). This line
      # used to say "install jq", which was the only way the read could fail when it was
      # written. The read is bounded now, so a stalled registry is a second cause — and
      # telling that user to install a tool they already have is worse than saying nothing.
      say "   bionic could not check for duplicate copies — ${cause}"
      action "duplicate copies were not checked for — ${cause}; /bionic:doctor lists them once bionic can read the plugin registry"
      continue
    fi

    say "   ${bare} is installed twice: ${ids}."
    say "   A session loads one of them, and which one is not something you chose."
    if ! losers="$(_setup_dup_uninstall_ids "$fix")"; then
      # Both copies are somebody else's catalog: bionic has no standing to pick
      # a winner, so it names the choice and does not offer to make it.
      say "   ${fix}"
      action "settle the duplicate copies of ${bare}: ${fix}"
      continue
    fi
    say "   bionic would run: ${fix}"
    say "   Saying no lets them coexist: nothing changes, and bionic asks again next run."
    if ! consent "   Consolidate — remove the copy bionic did not install?"; then
      say "   left as they are."
      action "settle the duplicate copies of ${bare}: ${fix} — $(_setup_answer_yes "duplicate:${bare}")"
      continue
    fi
    while IFS= read -r id; do
      [ -n "$id" ] || continue
      if claude plugin uninstall "$id"; then
        say "   removed ${id}."
      else
        say "   ${id} could not be removed."
        action "remove the duplicate copy by hand: claude plugin uninstall ${id}"
      fi
    done <<< "$losers"
  done 3< <(detect_plugin_duplicates)
  return 0
}

# ─── Step 2 — the core dependencies: present AND enabled ─────────────────────
#
# The harness installs these; the measured failure mode is that it can leave one
# `enabled: false`, which looks installed to every check that only counts rows.
# Repair is an explicit enable — never a reinstall, which would be the second
# installer the native install mechanism exists to avoid.

setup_dep_enable_verify() {
  case "$SETUP_ONLY" in ''|dependency:*) ;; *) return 0 ;; esac
  say ""
  say "2. Dependencies"
  say "   The two plugins bionic depends on. They are installed with bionic itself."
  local name line present state id
  # The list is read on fd 3, NEVER on stdin. A `while read ... done < <(list)`
  # loop redirects the BODY's stdin too, so the consent prompt inside it would
  # read the next dependency NAME as the user's answer and decline every item
  # while consuming the rest of the list.
  while IFS= read -r name <&3; do
    [ -n "$name" ] || continue
    _setup_wants "dependency:${name}" || continue
    line="$(detect_dep "$name")" || continue
    present="${line#*present=}"; present="${present%% *}"
    IFS='|' read -r state id <<< "$(_setup_cli_plugin "$name")"
    [ -n "$id" ] || id="${name}@${SETUP_DEP_MARKETPLACE}"

    case "$state" in
      enabled)
        say "   ${name}: installed and enabled."
        ;;
      disabled)
        say "   ${name}: installed but DISABLED."
        say "   bionic would run: claude plugin enable ${id}"
        if ! consent "   Enable ${name} now?"; then
          say "   declined — ${name} stays disabled."
          action "run: claude plugin enable ${id} — $(_setup_answer_yes "dependency:${name}")"
        elif claude plugin enable "$id"; then
          say "   enabled."
        else
          action "run: claude plugin enable ${id}"
        fi
        ;;
      absent)
        say "   ${name}: not installed — it should have come with bionic, so this install is incomplete."
        action "reinstall bionic so its dependencies resolve: claude plugin install ${SETUP_PLUGIN_ID} --scope user --yes (${name} is missing)"
        ;;
      *)
        say "   ${name}: enabled-state unknown (present=${present}) — the claude CLI or jq could not be used to read it."
        action "install jq, then re-run /bionic:setup — ${name}'s enabled-state read as unknown"
        ;;
    esac
  done 3< <(dep_names_class core)
  return 0
}

# ─── Steps 3 and 4 — one row at a time, through the one installer ────────────
#
# ONE BODY, TWO STEPS. The basics and the extras differ in what the user is told
# before the question, not in what the question does: both consent per item,
# both mutate through `install_dep`, both accept "no" as a complete answer. So
# the walk is one function taking a class, and the difference is one line of
# prose printed ahead of each extra.
#
# `unknown` presence gets an OFFER, not a skip. Some mechanisms genuinely have
# no presence surface to read (the pnpm store is a cache, not an install; the
# statusline lives in a settings file jq may not be there to parse), and the
# installer these steps replaced re-warmed those unconditionally — skipping them
# would quietly drop coverage the old installer had. The offer is consented like
# every other, and the unknown is named in the same breath so the user is
# deciding with the real state in front of them.

_setup_install_class() {  # <class>
  local name raw present
  # fd 3, not stdin — see the note in setup_dep_enable_verify. install_dep
  # prompts, so this loop must leave stdin alone.
  while IFS= read -r name <&3; do
    [ -n "$name" ] || continue
    _setup_wants "tool:${name}" || continue
    [ "$(dep_field "$name" class)" = "extra" ] && say "   ${name} — $(_setup_extra_why "$name")"
    raw="$(check_dep "$name")" || continue
    present="${raw#present=}"; present="${present%%|*}"
    case "$present" in
      yes)
        say "   ${name}: present."
        ;;
      unknown)
        say "   ${name}: presence unknown — bionic has no way to read whether this one is here."
        install_dep "$name" || action "install ${name} by hand: $(_jit_fix_line "$name") — bionic could not confirm whether it is already there; $(_setup_answer_yes "tool:${name}")"
        ;;
      *)
        install_dep "$name" || action "install ${name} by hand: $(_jit_fix_line "$name") — $(_setup_answer_yes "tool:${name}")"
        ;;
    esac
  done 3< <(dep_names_class "$1")
  return 0
}

# WHAT AN EXTRA IS, IN ONE SENTENCE. D-B's rule for this class is "asked once,
# default No, one line of why each", and the why is the only part the dependency
# table cannot supply: `consumer` answers which route needs a tool, and the
# whole point of an extra is that no route does. So the sentences live here,
# beside the step that prints them, rather than as an eighth column nothing else
# would read. A row with no sentence says so plainly instead of printing an
# empty dash — the table is the roster, and this function must never become a
# second one that can silently disagree with it.
_setup_extra_why() {  # <name>
  case "${1:-}" in
    ccstatusline)    echo "a status line in Claude Code showing the model, context use and session cost." ;;
    notebooklm)      echo "a command-line client for Google NotebookLM, for research passes over sources." ;;
    context7)        echo "up-to-date documentation for libraries, fetched on demand inside a session." ;;
    '@pencil.dev/cli') echo "the Pencil design tool's command line, for turning design files into code." ;;
    *)               echo "an optional extra; bionic ships no description for it." ;;
  esac
}

setup_tools_loop() {
  _setup_class_wanted basic || return 0
  say ""
  say "3. Tools"
  say "   The substrate bionic expects on a working machine. Asked one at a time;"
  say "   bionic never removes these, because it did not put them on your machine to own."
  _setup_install_class basic
}

setup_extras_loop() {
  _setup_class_wanted extra || return 0
  say ""
  say "4. Optional extras"
  say "   Nothing here is needed to use bionic. Each is offered once, with a line of"
  say "   what it is, and the answer is No unless you say otherwise."
  _setup_install_class extra
}

# ─── Step 5 — the todo-tools export ──────────────────────────────────────────

setup_env_export() {
  _setup_wants shell-env || return 0
  say ""
  say "5. Shell environment"
  local rc line present
  rc="$(_detect_shell_rc)"
  line="$(detect_env_todo_tools)"; present="${line#*present=}"

  if [ "$present" = "yes" ]; then say "   CLAUDE_CODE_ENABLE_TODO_TOOLS=1 is already exported in ${rc} — nothing to do."; return 0; fi  # idempotence guard: rc export

  say "   ${rc} does not export CLAUDE_CODE_ENABLE_TODO_TOOLS=1 (current CLI builds need it for the native task tools)."
  say "   bionic would append a marker-scoped block to ${rc}."
  if ! consent "   Add the export to ${rc}?"; then say "   declined — ${rc} is unchanged."; action "add 'export CLAUDE_CODE_ENABLE_TODO_TOOLS=1' to ${rc} — $(_setup_answer_yes shell-env)"; return 0; fi  # consent gate: rc export

  # Replace rather than stack: a block whose export was commented out reads as
  # absent above, and appending beside it would leave two blocks.
  _setup_rc_strip_block "$rc" "$SETUP_ENV_START" "$SETUP_ENV_END"
  if printf '\n%s\nexport CLAUDE_CODE_ENABLE_TODO_TOOLS=1\n%s\n' "$SETUP_ENV_START" "$SETUP_ENV_END" >> "$rc"; then
    say "   added."
  else
    say "   could not write ${rc}."
    action "add 'export CLAUDE_CODE_ENABLE_TODO_TOOLS=1' to ${rc} (bionic could not write the file)"
  fi
  return 0
}

# ─── Step 6 — the retired alias block ────────────────────────────────────────

setup_legacy_alias() {
  _setup_wants legacy-alias || return 0
  say ""
  say "6. Legacy shell alias"
  local rc line present tmp
  rc="$(_detect_shell_rc)"
  line="$(detect_zshrc_legacy_block)"; present="${line#*present=}"

  if [ "$present" = "yes" ]; then
    say "   ${rc} carries the legacy bionic alias block (claude --dangerously-skip-permissions)."
    say "   Auto mode is the default now and is the safer equivalent, so the block is retired footprint."
    if ! consent "   Remove the legacy alias block from ${rc}?"; then
      say "   declined — the block stays."
      action "remove the legacy bionic alias block from ${rc} — $(_setup_answer_yes legacy-alias)"
      return 0
    fi
    _setup_rc_strip_block "$rc" "$SETUP_ALIAS_START" "$SETUP_ALIAS_END"
    if grep -qF "$SETUP_ALIAS_START" "$rc" 2>/dev/null; then
      say "   the block could not be removed."
      action "remove the legacy bionic alias block from ${rc} by hand"
    else
      say "   removed."
    fi
    return 0
  fi

  if [ -f "$rc" ] && grep -qE "$SETUP_ALIAS_PATTERN" "$rc" 2>/dev/null; then
    say "   ${rc} carries the legacy UNMARKED alias — the spelling that predates the marker block."
    if ! consent "   Remove the legacy alias line from ${rc}?"; then
      say "   declined — the alias stays."
      action "remove the legacy 'alias claude=...--dangerously-skip-permissions' line from ${rc} — $(_setup_answer_yes legacy-alias)"
      return 0
    fi
    tmp="${rc}.bionic.tmp"
    if grep -vE "$SETUP_ALIAS_PATTERN" "$rc" > "$tmp" && mv "$tmp" "$rc"; then
      say "   removed (legacy unmarked alias)."
    else
      rm -f "$tmp"
      say "   could not rewrite ${rc}."
      action "remove the legacy 'alias claude=...--dangerously-skip-permissions' line from ${rc} by hand"
    fi
    return 0
  fi

  say "   no legacy alias block in ${rc} — nothing to remove."
  return 0
}

# ─── Step 7 — legacy-channel managed-hook entries ────────────────────────────
#
# COUNT here, REWRITE in hooks.sh. This step decides whether to ask and what to
# say; it does not carry a jq program of its own, because it used to and
# remove.sh's differently-shaped copy of the same rewrite drifted away from it
# unpinned. The count that decides to prompt and the edit that clears it are the
# same question, so they spell the same predicate — and the one caller with a
# real excuse for a second copy is remove.sh's standalone door, not this script,
# which refuses to start without the libraries beside it.
#
# Foreign hooks — anything not pointing into the pre-plugin directory — are
# untouched: this is bionic's leftover being removed, not the machine's hook
# config being taken over.

setup_legacy_channel_hooks() {
  _setup_wants legacy-hooks || return 0
  say ""
  say "7. Legacy-channel managed-hook entries"
  local line count settings registered
  line="$(detect_legacy_channel_hooks)"; count="${line#*count=}"
  settings="$(_dep_settings_file)"
  line="$(detect_plugin_registered)";    registered="${line#*registered=}"

  case "$count" in
    0)
      say "   no legacy-channel managed-hook entries in ${settings} — nothing to remove."
      return 0 ;;
    unknown)
      say "   legacy-channel managed-hook entries: count unknown — jq is unavailable, so ${settings} was not parsed."
      action "install jq, then re-run /bionic:setup — legacy-channel managed-hook entries could not be counted"
      return 0 ;;
  esac

  # The pre-plugin hooks directory is named without a path literal on purpose:
  # tests/plugin-paths.test.sh forbids an installed-path literal on any
  # executable line in the payload, and a user-facing string is still one.
  say "   ${count} hook entr(ies) in ${settings} still point into the machine's pre-plugin hooks directory."
  say "   They are registered through the settings channel rather than the plugin channel."
  # WHAT THIS PROMPT IS ALLOWED TO PROMISE. Offering to delete a user's only
  # live hook registrations is safe when the plugin channel already carries the
  # same hooks and destructive when it does not, and which of those is true is a
  # machine fact — not a property of this script. It was stated unconditionally
  # until `detect_plugin_registered` existed to condition it on, which made the
  # sentence false on every machine before the plugin is installed. `unknown`
  # falls to the cautious branch on purpose: an unreadable registry is not
  # evidence of coverage.
  if [ "$registered" = "yes" ]; then
    say "   The plugin registers its own copy of each through the payload's hooks.json, so the same"
    say "   hooks keep firing through the plugin channel once these are gone."
  else
    say "   The plugin is NOT registered with the CLI on this machine, so nothing takes their place:"
    say "   removing these entries leaves these hooks not firing at all until the plugin is installed."
  fi
  if ! consent "   Remove the legacy-channel entries from ${settings}?"; then
    say "   declined — ${settings} is unchanged."
    action "remove ${count} legacy-channel managed-hook entr(ies) from ${settings} — $(_setup_answer_yes legacy-hooks)"
    return 0
  fi

  if hooks_strip_legacy_channel "$settings"; then
    say "   removed."
  else
    say "   could not rewrite ${settings}."
    action "remove ${count} legacy-channel managed-hook entr(ies) from ${settings} by hand"
  fi
  return 0
}

# ─── Step 8 — the legacy installed skill copy ────────────────────────────────
#
# The third ported obligation, and the one the installer never had: it CREATED
# this. `claude-bootstrap.sh` rendered bionic's skills into the CLI's own
# skills directory, and the plugin ships the same skill inside its payload — so
# after the cutover the installed copy is a second canonical-sdlc whose
# frontmatter still registers hooks through the pre-plugin channel. A session
# that loads it arms the same walls twice, silently, from a build no plugin
# update will ever move.
#
# W5 4/6 hit exactly this and removed the copy by hand to keep its live-fire
# attribution clean, then reported the gap rather than closing it quietly. This
# step is the gap closed: the removal is the shipped migration's own act.
#
# WHAT THE PROMPT NAMES IS WHAT GOES. `detect_legacy_skill_copy` resolves one
# directory; this step prints that path, asks about that path, and removes that
# path. Sibling copies the same installer left are a separate decision and are
# not offered here — see the library's note.

setup_legacy_skill_copy() {
  _setup_wants legacy-skill-copy || return 0
  say ""
  say "8. Legacy installed skill copy"
  local line present dir
  line="$(detect_legacy_skill_copy)"
  present="${line#*present=}"; present="${present%% *}"
  dir="${line##*path=}"

  if [ "$present" != "yes" ]; then
    say "   no pre-plugin skill copy in the CLI's skills directory — nothing to remove."
    return 0
  fi

  say "   ${dir} is a pre-plugin rendered copy of a skill this payload already ships."
  say "   Its frontmatter registers hooks through the pre-plugin channel, so a session that"
  say "   loads it arms the same walls twice — once from the plugin, once from the retired copy."
  # The gate is one line so a mutation arm can delete it whole and watch the
  # decline stop protecting anything (tests/setup.test.sh Group 12, mutation 4).
  if ! consent "   Remove ${dir} and everything under it?"; then say "   declined — ${dir} is unchanged."; action "remove the pre-plugin skill copy at ${dir} — $(_setup_answer_yes legacy-skill-copy)"; return 0; fi  # consent gate: legacy skill copy

  # The guard is not decoration. This is the only recursive delete in the
  # script, and the path it takes comes from an environment the caller controls;
  # re-reading the two conditions the fact function used means a resolution that
  # went wrong between then and now removes nothing.
  if [ -n "$dir" ] && [ -d "$dir" ] && [ -f "${dir}/SKILL.md" ]; then
    rm -rf "$dir" 2>/dev/null
  fi
  if [ ! -e "$dir" ]; then
    say "   removed."
  else
    say "   could not remove ${dir}."
    action "remove the pre-plugin skill copy at ${dir} by hand"
  fi
  return 0
}

# ─── Step 9 — the permission profile ─────────────────────────────────────────
#
# Consent is obtained here and handed to `profile_apply` as a token. The library
# refuses to write without it and never prompts, so there is one conversation
# with the user and one gate, not two.

setup_profile() {
  _setup_wants permission-profile || _setup_wants permission-mode || return 0
  say ""
  say "9. Permission profile"
  _setup_wants permission-profile && _setup_profile_block
  _setup_wants permission-mode && _setup_default_mode
  return 0
}

# THE STEP IS TWO DECISIONS, SO IT IS TWO FUNCTIONS. The profile block and the
# default permission mode are both about the same settings file and both belong
# in this step, but they are independent: a machine whose profile is applied and
# current still has a mode question to answer, and the profile half returns early
# on exactly that machine. Left inline, the second question would have been
# unreachable on every machine that had already been set up once — which is most
# of them, and the ones least likely to notice.

_setup_profile_block() {
  local state applied stale template root settings rendered
  state="$(detect_profile_state)"
  applied="${state#*applied=}"; applied="${applied%% *}"
  stale="${state#*stale=}";     stale="${stale%% *}"
  settings="$(_dep_settings_file)"

  if [ "$applied" = "yes" ] && [ "$stale" = "no" ]; then
    say "   the permission profile is applied and current — nothing to do."
    return 0
  fi

  template="$(_profile_template_path)"
  root="$(_profile_plugin_root)"
  rendered="$(mktemp 2>/dev/null)" || rendered=""
  if [ -z "$rendered" ]; then
    say "   could not create a temporary file to render the profile."
    action "apply the permission profile: re-run /bionic:setup once a temporary directory is writable"
    return 0
  fi
  if ! render_profile "$template" "$root" > "$rendered"; then
    rm -f "$rendered"
    say "   the profile template could not be rendered."
    action "apply the permission profile: reinstall bionic — ${template} is missing or unreadable"
    return 0
  fi

  if [ "$applied" = "yes" ]; then
    say "   the applied permission profile is stale (${state})."
    say "   A plugin update moves the install path, which is what stales the rendered rules."
  else
    say "   bionic ships a permission profile for its own scripts and hooks, rendered for ${root}."
  fi
  say "   It goes into ${settings} inside a marker block; nothing outside that block is read or changed."
  if ! consent "   Apply the permission profile to ${settings}?"; then
    rm -f "$rendered"
    say "   declined — ${settings} is unchanged."
    action "apply the permission profile — $(_setup_answer_yes permission-profile)"
    return 0
  fi

  if profile_apply "$rendered" "$BIONIC_PROFILE_CONSENT"; then
    say "   applied."
  else
    say "   the permission profile could not be applied."
    action "apply the permission profile: see the message above (jq is required to edit ${settings} safely)"
  fi
  rm -f "$rendered"
  return 0
}

# ─── The default permission mode (AC-12) ─────────────────────────────────────
#
# ONE QUESTION, ASKED AFTER THE PROFILE AND NEVER ASSUMED. The profile decides
# which of bionic's own commands run without a prompt; this decides whether the
# machine asks about everything else once or every time. The smaller question
# goes second on purpose, and it is its own consent whatever was answered above.
#
# NOT A RULE INSIDE THE MARKER BLOCK. `defaultMode` is a preference of the
# machine's, not one of bionic's rendered rules — the template ships no
# defaultMode and tests/profile.test.sh walls it out. Writing it inside the block
# would mean /bionic:remove's strip silently reverted a decision the user was
# asked for separately, which is not what either question promised.
#
# ALREADY-AUTO ASKS NOTHING. Every other step here is guarded by the fact that
# owns its question, and this is no different: a machine already in auto has
# nothing to decide, and asking anyway would be the interrogation this wave is
# removing. Without jq the value cannot be read at all, so the honest answer is
# to say so and change nothing — never to write over a mode we could not see.
_setup_default_mode() {
  local settings mode want
  settings="$(_dep_settings_file)"
  want="$BIONIC_DEFAULT_PERMISSION_MODE"

  if ! command -v jq >/dev/null 2>&1; then
    say "   the default permission mode is unknown — jq is unavailable, so ${settings} was not parsed."
    action "install jq, then re-run /bionic:setup — the default permission mode could not be read"
    return 0
  fi

  if [ -f "$settings" ]; then
    mode="$(jq -r '.permissions.defaultMode // ""' "$settings" 2>/dev/null)" || mode=""
  else
    mode=""
  fi

  # THE VALUE IS DEPS.SH'S, NOT THIS FILE'S (six-axis review D-1). remove.sh
  # offers to reset exactly the value bionic wrote and leaves any other alone,
  # so the two scripts are one decision; this used to be a bare literal here and
  # a second bare literal there, agreeing by luck. Written with `--arg` so a
  # value with a quote in it could never become part of the jq program.
  if [ "$mode" = "$want" ]; then say "   the default permission mode is already ${want} — nothing to do."; return 0; fi  # idempotence guard: default mode

  say "   Claude Code asks before each command unless a default mode says otherwise."
  consent "   Set Claude Code's default permission mode to ${want}? Recommended — you approve once, not on every command."
  local _setup_mode_consent=$?
  # item 1: the note follows the question itself, whichever way it was
  # answered — a Remote Control session overrides this either way, so a
  # decline that leaves the setting unchanged and a yes that writes it both
  # need the same one sentence.
  say "   ${PROFILE_RC_NOTE}"
  if [ "$_setup_mode_consent" -ne 0 ]; then say "   declined — the default permission mode is unchanged."; action "set Claude Code's default permission mode to ${want} in ${settings} — $(_setup_answer_yes permission-mode)"; return 0; fi  # consent gate: default mode

  # Created only AFTER consent: a declined run must leave a machine that has no
  # settings file without one.
  [ -f "$settings" ] || echo '{}' > "$settings"
  if _dep_settings_write_jq "$settings" '.permissions.defaultMode = $m' --arg m "$want"; then
    say "   set."
  else
    say "   the default permission mode could not be set."
    action "set Claude Code's default permission mode to ${want} in ${settings} by hand"
  fi
  return 0
}

# ─── The summary ─────────────────────────────────────────────────────────────

setup_summary() {
  say ""
  say "Summary"
  if [ -z "$SETUP_ACTIONS" ]; then
    # A NARROWED RUN MAY NOT CLAIM THE WHOLE MACHINE (the RV-6 class: a summary
    # that overreaches teaches the reader to stop reading it). One item finished
    # is one item finished; the other eight were never looked at.
    if [ -n "$SETUP_ONLY" ]; then
      say "   nothing left to do for ${SETUP_ONLY}."
    else
      say "   nothing left to do — this machine is set up."
    fi
    return 0
  fi
  local a
  while IFS= read -r a; do
    [ -n "$a" ] && say "   - ${a}"
  done <<< "$SETUP_ACTIONS"
  return 0
}

# ─── Run ─────────────────────────────────────────────────────────────────────

# THE FLAGS ARE READ HERE, not in a wrapper, because the roster they are checked
# against is built from the dependency table this script has already sourced. An
# unrecognised name stops the run before anything is printed at it: a narrowed
# run that silently did nothing would look exactly like a machine with nothing
# left to do, which is the one report this script must never fake.
SETUP_LIST=0
while [ $# -gt 0 ]; do
  case "$1" in
    --list)
      SETUP_LIST=1; shift ;;
    --only)
      if [ $# -lt 2 ] || [ -z "${2:-}" ]; then
        say "setup: --only needs the name of the one item to set up."
        say "       run ${SETUP_SELF_CMD} --list to see the names."
        exit 2
      fi
      SETUP_ONLY="$2"; shift 2 ;;
    --only=*)
      SETUP_ONLY="${1#--only=}"; shift ;;
    *)
      say "setup: ${1} is not something this command takes."
      say "       run ${SETUP_SELF_CMD} --list to see what can be set up one item at a time."
      exit 2 ;;
  esac
done

if [ "$SETUP_LIST" = "1" ]; then
  _setup_item_ids
  exit 0
fi

if [ -n "$SETUP_ONLY" ]; then
  setup_known=""
  while IFS= read -r setup_id <&3; do
    [ "$setup_id" = "$SETUP_ONLY" ] && { setup_known=1; break; }
  done 3< <(_setup_item_ids)
  if [ -z "$setup_known" ]; then
    say "setup: there is nothing called ${SETUP_ONLY} to set up on this machine."
    say "       run ${SETUP_SELF_CMD} --list to see the names."
    exit 2
  fi
fi

say "bionic setup — every change below is asked for first, one item at a time."

setup_plugin_install
setup_load_state
setup_duplicates
setup_dep_enable_verify
setup_tools_loop
setup_extras_loop
setup_env_export
setup_legacy_alias
setup_legacy_channel_hooks
setup_legacy_skill_copy
setup_profile
setup_summary

exit 0
