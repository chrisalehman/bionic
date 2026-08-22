#!/bin/bash
# doctor.sh — the read-only diagnosis (epic-17 wave-03 slice S7, spec AC-3).
#
# WHAT THIS FILE OWNS. Nothing factual. Doctor is a RENDERING SURFACE: every
# number, verdict and state below is computed by detect.sh, deps.sh or
# profile.sh and printed here in a shape a person can act on. The design's
# ownership table says so in one word — doctor "diagnoses, never treats" — and
# that word is the whole contract: no mutations, one pass, exit 0.
#
# ONE QUESTION, ASKED LAST (wave-06, ratified D-D). The instant report —
# everything this machine can be asked about without leaving it — prints in full
# first. Then doctor asks whether to check for tool updates, because that is the
# one fact that costs a network round trip to two package managers and a user
# waiting on a diagnosis should not pay for it unasked. The rejected shapes are
# what this one has to keep out: always-on is a forced wait, an argument alone is
# forgettable, and a cache would make the read-only report write a file.
# Answering yes appends UPDATES and nothing else changes: doctor prints the
# upgrade command, and never runs it.
#
# THE QUESTION IS ALWAYS PRINTED; ONLY THE WAITING IS CONDITIONAL. Where stdin
# can carry an answer — a terminal, a pipe, a file — doctor asks and waits. Where
# it cannot (a closed stream, or the socket a tool harness hands a script) the
# same line is printed and the run ends: no wait, and no narration of why. That
# is setup.sh's rule applied here — it prints every consented question as it
# declines it, so whoever is relaying the script's output can put the question to
# the person who can answer it. A question the reader never sees is a feature
# nobody can use.
#
# `--updates` IS THAT ANSWER COMING BACK. The relay runs doctor again with the
# flag, which skips the question and appends UPDATES. It is NOT an assume-yes
# knob: the rule setup states in its own header — that an env var switching
# consent off would be the hole in "consent per event" — guards MUTATIONS, and
# this flag guards a read. Two package managers are asked what is outdated; the
# upgrade command is printed and never run. By the time the flag is passed the
# user has already said yes.
#
# EVERY SHELL-OUT IS BOUNDED. Three of the facts below leave this process: the
# CLI's own plugin listing, `brew outdated`, `npm outdated -g`. Each runs under a
# time limit (15 seconds; `BIONIC_DOCTOR_PROBE_SECONDS` accelerates it for the
# suite), because the machine where a diagnosis matters most is exactly the one
# where a CLI or a package manager hangs, and a doctor that hung with it would be
# useless at the only moment it was needed. A probe that runs out of time is
# `unknown` with a cause, never a confident answer.
#
# EXIT 0, ALWAYS — FOR A DIAGNOSIS. A diagnosis is not a failure. A machine with
# eleven absent dependencies and a stale permission profile has been diagnosed
# *successfully*; reporting that as a non-zero exit would make every caller treat
# a working doctor as a broken one. The report's content is the signal, never the
# status. The one exception is an option this script does not know, which has
# diagnosed nothing: answering a misspelled flag with a clean report and status 0
# would tell a caller that asked for something, and did not get it, that all was
# well. That exits 2, before any fact is gathered.
#
# WHY READ-ONLY IS STRUCTURAL AND NOT MERELY INTENDED. Doctor calls only the
# read-only half of each library — detect.sh's fact functions, profile.sh's
# `profile_diff` / `detect_profile_state`, deps.sh's table accessors. It never
# calls `install_dep`, `remove_dep`, `profile_apply` or `profile_strip`, and it
# never shells out to brew/npm/uv/claude for anything but a version probe the
# libraries already own. tests/doctor.test.sh fingerprints a whole fixture
# machine — every file's sha256 AND every path — before and after a full run.
#
# THE THREE-VALUED WORLD. `present`, `absent` and `unknown` are three answers,
# not two-plus-an-error. A dependency whose mechanism has no presence surface
# (the pnpm store is a cache), a count that cannot be taken because `jq` — one of
# the table's own rows — is missing: those are `unknown`, and coercing them to
# `absent`/`0` would report a machine that could not be read as one that read
# clean. Every `unknown` printed below carries a NAMED CAUSE, because "unknown"
# on its own is a shrug rather than a diagnosis.
#
# EVERY BROKEN FACT CARRIES ITS FIX. The degradation map names an action per
# absent or violating dependency; the summary block is action lines and nothing
# else. A report that tells a user what is wrong and not what to do about it has
# done half the job.
#
# ROOTS ARE OVERRIDABLE — the same env knobs the libraries read
# (BIONIC_PLUGIN_ROOT, BIONIC_CLAUDE_HOME, BIONIC_SETTINGS_FILE,
# BIONIC_INSTALLED_PLUGINS_FILE, BIONIC_SHELL_RC, BIONIC_PROFILE_TEMPLATE,
# BIONIC_PLAYWRIGHT_CACHE). Doctor adds none of its own: a knob only doctor
# honoured would be a second definition of where this machine keeps its state.
#
# Executed, never sourced:  bash ${CLAUDE_PLUGIN_ROOT}/scripts/doctor.sh

set -uo pipefail

# ─── Options ─────────────────────────────────────────────────────────────────
#
# Parsed FIRST, before a single fact is gathered: a caller who misspelled the one
# flag should be told so immediately, not after a full report they will not read.
DOCTOR_WANT_UPDATES=no
# THE REPORT IS AN INVENTORY, NOT A DOSSIER (certified 2026-08-22; verbose arm
# removed same day by owner order — the explainer prose is deleted, not parked).
# Three tables answer the three questions a user has — what ships in the plugin,
# what setup installed and at which version, what this machine's environment
# carries.
while [ $# -gt 0 ]; do
  case "$1" in
    --updates)          DOCTOR_WANT_UPDATES=yes ;;
    *)
      echo "doctor.sh: unknown option '$1' — the only option is --updates" >&2
      exit 2 ;;
  esac
  shift
done

# No `dirname` here for the same reason the libraries give: a diagnosis that
# needs coreutils to locate itself dies on the broken machine it exists for.
_doctor_self_dir() {
  local self="${BASH_SOURCE[0]}"
  case "$self" in */*) echo "${self%/*}" ;; *) echo "." ;; esac
}
DOCTOR_LIB="$(cd "$(_doctor_self_dir)" && pwd -P)/lib"

# shellcheck source=/dev/null
. "${DOCTOR_LIB}/detect.sh"
# shellcheck source=/dev/null
. "${DOCTOR_LIB}/profile.sh"
# env.sh, for its READ half only — `env_get` (what settings.json says) and
# `env_live` (what THIS process has). Those are two different facts and the gap
# between them is a restart, not a repair; a report that collapsed them is the
# 2026-08-21 defect this section exists to end. env.sh's write half is never
# called from here, the same way this file never calls install_dep.
# shellcheck source=/dev/null
. "${DOCTOR_LIB}/env.sh"

# The standalone removal door (design D5a: the remover must not depend on the
# thing it removes). Printed as TEXT for the user to run — doctor never fetches
# it. scripts/remove.sh is the same file this URL serves; slice S8 owns that
# script, and this constant is the one place doctor names its public location.
BIONIC_REMOVE_RAW_URL="https://raw.githubusercontent.com/chrisalehman/bionic/main/payload/scripts/remove.sh"

# The id the CLI knows this plugin by — `<name>@<catalog>`, which is the key the
# listing prints and the argument an install command takes. Named once here
# because it appears in a fact lookup and in two fix lines.
BIONIC_PLUGIN_ID="bionic@bionic"

# ─── Bounded probes ──────────────────────────────────────────────────────────
#
# THE THREE THINGS DOCTOR RUNS THAT IT DOES NOT CONTROL — the CLI's plugin
# listing, `brew outdated`, `npm outdated` — go through `detect_bounded`, which
# lives in detect.sh beside the probe it was written for. It moved there at S11
# (critic F-3): setup runs the same listing through the same function, and a
# bound only one of two callers has is a bound the product does not have. The
# mechanism, and why it is one mechanism rather than two, is documented at the
# function.

# ─── Small renderers ─────────────────────────────────────────────────────────
#
# THE FOUR FORMAT RULES (spec AC-15, approved 2026-08-22). This report used to
# spend two lines on every fact — a value, then a sentence explaining the value —
# and open each section with a paragraph about how the section works. Read down a
# terminal that is eighty columns wide, a long line then wrapped into a second
# one, and a twenty-row machine printed as a hundred and twelve lines nobody
# could scan. The rules, in the shape they are implemented here:
#
#   1. ONE LINE PER ITEM, with a status symbol in column one. `_doctor_item` is
#      the only way a fact reaches the page, so a row added by any future arm
#      inherits the format without knowing it exists.
#   2. NO PROSE ON A HEALTHY ITEM. A value that is fine is the value and nothing
#      else; the sentence that used to follow it explained a state the symbol now
#      carries. Section explainers are gone from the default output entirely —
#      what the DEPENDENCIES class column means, how a roster line is counted,
#      what the permission block is three-way between. That reasoning lives in
#      the comments of this file, where the person it is addressed to is reading.
#   3. THE VERDICT FIRST. SUMMARY is the first section and FIX is the second, so
#      the two questions a reader actually has — is anything wrong, and what do I
#      type — are answered before the detail they can skip.
#   4. FILLER COLLAPSES TO A COUNT. Fourteen dependencies contributing zero
#      roster lines, six legacy checks all clean: those are one line each about
#      nothing. They are counted and summarised, and only the rows carrying a
#      real value are printed.
#
# AND EVERY LINE FITS. Nothing printed below may exceed 100 columns —
# tests/doctor.test.sh walls it for both fixture machines — because a wrapped
# line is rule 1 broken by the terminal rather than by this file.

# The three symbols, and the invariant that gives them meaning: ✗ is printed if
# and only if the same run puts a matching line in FIX. Anything true but not
# actionable — an install behind the tip, a locally edited role file, a
# when-needed tool nobody has needed yet — is `–`, never ✗. A report that marked
# every unusual fact as broken would be nagging a machine that is working, which
# is the defect the degradation map already had to have designed out of it.
DOCTOR_OK='✓'
DOCTOR_BAD='✗'
DOCTOR_NIL='–'

# A padded column with nothing after it is trailing whitespace, which every diff
# and every `git show` renders as an error. Rows are built and then trimmed.
_doctor_rtrim() {  # <line>
  local s="${1}"
  printf '%s' "${s%"${s##*[! ]}"}"
}

# All three are three bytes, so `%s` in the symbol position pads the same width
# for each and the label column below it stays straight. Padding the symbol
# itself with `%-Ns` would NOT be safe: printf pads to a byte count, and a
# multi-byte glyph in a padded field steps the whole column two places left.
# 30, because the longest label this report prints is an environment name —
# CLAUDE_CODE_ENABLE_TODO_TOOLS, 29 characters — and a label that overruns its
# column pushes one row's value out of line with every other row's.
_doctor_item() {  # <symbol> <label> <value>
  local line
  printf -v line '  %s %-30s %s' "$1" "$2" "${3:-}"
  printf '%s\n' "$(_doctor_rtrim "$line")"
}

# A path under the user's home, written the way they would type it. Not
# cosmetics: `/Users/<name>/…` costs a dozen columns before the interesting part
# of the path starts, and those are the columns that decide whether the line
# wraps. The substitution is exact-prefix only, so a path that merely begins with
# the same letters is left alone.
_doctor_tilde() {  # <path>
  local p="${1:-}"
  case "$p" in
    "$HOME"/*) printf '~%s' "${p#"$HOME"}" ;;
    *)         printf '%s' "$p" ;;
  esac
}

# The FIX section, accumulated as the run discovers problems and printed near the
# top — which is why it is collected rather than echoed where it is found. One
# line per problem, and the line ENDS with what to type: a problem stated without
# its command is the half of the job this report used to leave undone.
FIX_LINES=""
# THE VERDICT LINE NAMES THE PROBLEMS, so the problems have to be nameable. Each
# fix sentence is `<what is wrong> → <what to type>`, and the half before the
# arrow is already the name — accumulated here rather than re-derived later,
# because a second parse of this report's own prose is exactly the kind of
# reading that drifts. Problems /bionic:setup can repair are kept apart from the
# ones it cannot: one command covers the first group and is said once, and the
# rest each need their own line or they reach the user as a count with no cure.
FIX_NAMES_SETUP=""
FIX_LINES_OTHER=""
fix() {  # <problem> → <command>
  local line="${1}" name="${1%% → *}"
  FIX_LINES="${FIX_LINES}  ${DOCTOR_BAD} ${line}"$'\n'
  case "$line" in
    *"/bionic:setup") FIX_NAMES_SETUP="${FIX_NAMES_SETUP}${FIX_NAMES_SETUP:+; }${name}" ;;
    *)                FIX_LINES_OTHER="${FIX_LINES_OTHER}${line}"$'\n' ;;
  esac
}

# yes/no/unknown as the words a person reads in a report.
_doctor_word() {  # <yes|no|unknown>
  case "${1:-}" in
    yes)     echo "present" ;;
    no)      echo "absent" ;;
    unknown) echo "unknown" ;;
    *)       echo "${1:-unknown}" ;;
  esac
}

_doctor_plural() {  # <count> <singular> <plural>
  if [ "${1:-0}" = "1" ]; then echo "$2"; else echo "$3"; fi
}

# Why a value came back `unknown`. The mechanism decides: a cache has no
# presence surface at all, and everything else is a missing tool the report can
# name. Rendering-layer explanation only — the VALUE is always the library's.
#
# SHORT ENOUGH TO RIDE ON THE ROW (AC-15). These used to be sentences, printed on
# a line of their own under the row they explained; they are now the row's last
# column, so each has to leave the line inside 100 columns. Nothing was dropped
# that a reader could act on: "the pnpm content-addressable store is a cache, not
# an install surface" and "a cache, no presence surface" answer the same question,
# and only one of them fits beside the fact it is about.
_doctor_unknown_cause() {  # <kind> — the install mechanism the table names
  case "${1:-}" in
    pnpm-store) echo "a cache, no presence surface" ;;
    native)
      if command -v jq >/dev/null 2>&1; then echo "the plugin registry could not be parsed"
      else echo "jq is not on PATH"; fi ;;
    npm-global) echo "npm is not on PATH" ;;
    mcp-server) echo "the claude CLI is not on PATH" ;;
    statusline)
      if command -v jq >/dev/null 2>&1; then echo "settings.json could not be parsed"
      else echo "jq is not on PATH"; fi ;;
    *)          echo "no presence surface" ;;
  esac
}

# ─── The three certified tables ──────────────────────────────────────────────
#
# ONE ROW BUILDER PER TABLE, and the widths live here rather than at each
# callsite, because a column is only a column while every row agrees about it.
# Each builder trims its own tail, so a row whose last cell is empty — the
# healthy case, since rule 2 gives a working item no prose — leaves no trailing
# whitespace behind.
#
# PRINTF PADS BYTES; A TERMINAL LAYS OUT COLUMNS, and every glyph this report
# reaches for outside ASCII — ✓ ✗ – — ≥ … — is three bytes wide and one column
# wide. A `%-11s` field holding one of them therefore comes out two columns
# short, and the whole table steps left from that row down. It is not
# hypothetical: `—` is the version cell of every row whose mechanism keeps no
# version, which on an ordinary machine is a third of the table.
#
# SO CELLS ARE PADDED BY COLUMN COUNT. The multi-byte glyphs are a closed set —
# this file names all of them — so measuring is a substitution away from being
# exact, with no locale to depend on and no external process per cell.
_doctor_cols() {  # <string> -> its width in terminal columns
  local s="${1:-}"
  s="${s//✓/.}"; s="${s//✗/.}"; s="${s//–/.}"; s="${s//—/.}"
  s="${s//≥/.}"; s="${s//…/.}"; s="${s//·/.}"
  printf '%s' "${#s}"
}

# One cell, padded to a column width. A cell already at or over its width is
# printed whole and pushes its neighbours right — truncating a name to keep a
# column straight would be choosing the table's looks over its content.
_doctor_cell() {  # <string> <width>
  local s="${1:-}" w="${2:-0}" n
  n=$(( w - $(_doctor_cols "$s") ))
  if [ "$n" -gt 0 ]; then printf '%s%*s' "$s" "$n" ""; else printf '%s' "$s"; fi
}

# `component  count  detail` — four rows on a healthy machine, so the count
# column is narrow and the detail column gets the room.
_doctor_native_row() {  # <symbol> <component> <count> <detail>
  local line
  line="  $1 $(_doctor_cell "$2" 10) $(_doctor_cell "$3" 8) ${4:-}"
  printf '%s\n' "$(_doctor_rtrim "$line")"
}

# `name  version  source  state`. The source column is what makes this table
# worth reading twice: two rows can both say `present 1.2.3` and be installed by
# entirely different machinery, and which machinery it was decides what a user
# types to repair or remove it.
_doctor_third_row() {  # <symbol> <name> <version> <source> <state>
  local line
  line="  $1 $(_doctor_cell "$2" 21) $(_doctor_cell "$3" 11) $(_doctor_cell "$4" 17) ${5:-}"
  printf '%s\n' "$(_doctor_rtrim "$line")"
}

# `KEY=value  state`. The left cell is one token on purpose — an environment
# name and its value are a single fact, and splitting them into two columns made
# a reader join them back up by eye on every row.
_doctor_env_row() {  # <symbol> <key=value or label> <state>
  local line
  line="  $1 $(_doctor_cell "$2" 42) ${3:-}"
  printf '%s\n' "$(_doctor_rtrim "$line")"
}

# WHICH MACHINERY PUT IT THERE, in the words a user would use for it. Keyed on
# the table's `kind`, which IS the install mechanism, with one deliberate
# exception: a `native` row's mechanism field holds the upstream git URL, but the
# CLI installs it through a marketplace and records it in installed_plugins.json,
# so `marketplace` is the honest answer for where that version came from. The
# github fallback is not speculative — it reads the mechanism field a row
# actually carries, so a source-of-truth that is a repository names the
# repository rather than a scheme nobody would recognise.
_doctor_source_of() {  # <name> -> one of the source words
  local name="${1:-}" kind mech owner_repo
  kind="$(dep_field "$name" kind)"
  mech="$(dep_field "$name" source_url)"
  case "$kind" in
    native)             echo "marketplace" ;;
    brew-dep|brew-cask) echo "brew" ;;
    npm-global)         echo "npm -g" ;;
    uv-tool)            echo "uv tool" ;;
    mcp-server)         echo "MCP" ;;
    statusline)         echo "npx" ;;
    playwright-browser) echo "playwright cache" ;;
    pnpm-store)         echo "pnpm" ;;
    *)
      case "$mech" in
        https://github.com/*|http://github.com/*)
          owner_repo="${mech#*github.com/}"; owner_repo="${owner_repo%.git}"
          echo "github ${owner_repo}" ;;
        *:*) echo "${mech%%:*}" ;;
        *)   echo "${mech:-unknown}" ;;
      esac ;;
  esac
}

# WHY A ROW HAS NO VERSION, said in the version column's own terms. `—` is the
# cell, and the state cell has to earn it: a reader who sees a dash where every
# neighbouring row carries a number is owed the reason, and "unknown" alone is
# the shrug this report is not allowed to make. Keyed on the mechanism, because
# the mechanism is what does or does not keep a version.
_doctor_no_version_reason() {  # <kind>
  case "${1:-}" in
    mcp-server) echo "an MCP registration records no version" ;;
    statusline) echo "npx resolves at run time; nothing cached to read" ;;
    pnpm-store) echo "a content-addressable cache, no version surface" ;;
    *)          echo "this mechanism records no version" ;;
  esac
}

# ─── Facts, gathered once ────────────────────────────────────────────────────
#
# Every function called here is one of detect.sh's or profile.sh's. Nothing
# below re-derives a fact from the filesystem that a library already owns.

PLUGIN_FACT="$(detect_plugin_integrity)"
PLUGIN_VERSION="${PLUGIN_FACT#plugin: version=}"; PLUGIN_VERSION="${PLUGIN_VERSION%% *}"
PLUGIN_HOOKS="${PLUGIN_FACT##*hooks=}"

AGENT_FACT="$(detect_agent_integrity)"
AGENT_STATE="${AGENT_FACT#*state=}";       AGENT_STATE="${AGENT_STATE%% *}"
AGENT_TOTAL="${AGENT_FACT#*total=}";       AGENT_TOTAL="${AGENT_TOTAL%% *}"
AGENT_MODIFIED="${AGENT_FACT#*modified=}"; AGENT_MODIFIED="${AGENT_MODIFIED%% *}"
AGENT_NAMES="${AGENT_FACT#*names=}";       AGENT_NAMES="${AGENT_NAMES%% *}"
AGENT_CAUSE="${AGENT_FACT##*cause=}"

TODO_FACT="$(detect_env_todo_tools)";        TODO_STATE="${TODO_FACT##*present=}"
LEGACY_FACT="$(detect_zshrc_legacy_block)";  LEGACY_STATE="${LEGACY_FACT##*present=}"
LEGACY_HOOK_FACT="$(detect_legacy_channel_hooks)"; LEGACY_HOOK_COUNT="${LEGACY_HOOK_FACT##*count=}"
SKILL_COPY_FACT="$(detect_legacy_skill_copy)"
SKILL_COPY_STATE="${SKILL_COPY_FACT#*present=}"; SKILL_COPY_STATE="${SKILL_COPY_STATE%% *}"
SKILL_COPY_PATH="${SKILL_COPY_FACT##*path=}"
HOOK_FILES_FACT="$(detect_legacy_hook_files)"
HOOK_FILES_COUNT="${HOOK_FILES_FACT#*count=}"; HOOK_FILES_COUNT="${HOOK_FILES_COUNT%% *}"
HOOK_FILES_CAUSE="${HOOK_FILES_FACT##*cause=}"
REG_SHA_FACT="$(detect_registry_sha_lag)"
REG_SHA_STATE="${REG_SHA_FACT#*state=}"; REG_SHA_STATE="${REG_SHA_STATE%% *}"
REG_SHA_REG="${REG_SHA_FACT#*registry=}"; REG_SHA_REG="${REG_SHA_REG%% *}"
REG_SHA_REPO="${REG_SHA_FACT#*repo=}";    REG_SHA_REPO="${REG_SHA_REPO%% *}"
REG_SHA_CAUSE="${REG_SHA_FACT##*cause=}"

# THE COMMIT THE HEADER NAMES IS THE ONE THE CLI IS RUNNING, which is not always
# the one the registry recorded. On a directory-source feed the CLI reads the
# TREE — the registry copy is a lagging snapshot nothing executes (W7 A5.1) — so
# on that feed, and only on that feed, a lag resolves to the tree's own HEAD.
# Printing the registry's sha there would put a commit in the header that no
# behaviour on this machine comes from, which is the one thing a provenance line
# must never do.
_doctor_sha8() { printf '%.8s' "${1:-}"; }
case "$REG_SHA_STATE" in
  match)       PAYLOAD_SHA="$(_doctor_sha8 "$REG_SHA_REG")" ;;
  lag)
    if [ "$(detect_marketplace_feed_kind)" = "directory" ]; then
      PAYLOAD_SHA="$(_doctor_sha8 "$REG_SHA_REPO")"
    else
      PAYLOAD_SHA="$(_doctor_sha8 "$REG_SHA_REG")"
    fi ;;
  not-in-repo) PAYLOAD_SHA="$(_doctor_sha8 "$REG_SHA_REG")" ;;
  *)           PAYLOAD_SHA="unknown" ;;
esac
[ -n "$PAYLOAD_SHA" ] || PAYLOAD_SHA="unknown"

HOOK_WIRING_FACT="$(detect_hook_wiring)"
HOOK_TOTAL="${HOOK_WIRING_FACT#*total=}";     HOOK_TOTAL="${HOOK_TOTAL%% *}"
HOOK_RESOLVING="${HOOK_WIRING_FACT##*resolving=}"

# ─── What the payload itself carries ─────────────────────────────────────────
#
# THE PLUGIN'S OWN INVENTORY, counted from the tree the CLI resolved. Skills and
# commands have no checksum manifest the way the role files do — nothing declares
# how many there ought to be — so the denominator is what the payload directory
# holds and the numerator is how much of it is actually usable: a skill directory
# without its SKILL.md, a command file that is empty. On a whole payload those
# are equal, which is the point of printing them as `n/n` rather than as `n`: the
# reader sees at a glance both that the count is right and what it is counted
# against.
#
# COUNTED HERE, not in a library, and that is the same judgement `_doctor_roster_counts`
# already makes two hundred lines down for every OTHER plugin's install path.
# This is a directory listing, not a schema parse — there is no second reading of
# a format that could drift away from a first one, which is what the RV-7 rule
# against re-deriving facts in this file is protecting against.
_doctor_payload_root="$(_detect_plugin_root)"
SKILLS_TOTAL=0; SKILLS_OK=0; SKILL_NAMES=""
for _sk in "$_doctor_payload_root"/skills/*/; do
  [ -d "$_sk" ] || continue
  SKILLS_TOTAL=$((SKILLS_TOTAL + 1))
  _sk_name="${_sk%/}"; _sk_name="${_sk_name##*/}"
  SKILL_NAMES="${SKILL_NAMES}${SKILL_NAMES:+, }${_sk_name}"
  [ -s "${_sk}SKILL.md" ] && SKILLS_OK=$((SKILLS_OK + 1))
done
COMMANDS_TOTAL=0; COMMANDS_OK=0; COMMAND_NAMES=""
for _cm in "$_doctor_payload_root"/commands/*.md; do
  [ -f "$_cm" ] || continue
  COMMANDS_TOTAL=$((COMMANDS_TOTAL + 1))
  _cm_name="${_cm##*/}"; _cm_name="${_cm_name%.md}"
  COMMAND_NAMES="${COMMAND_NAMES}${COMMAND_NAMES:+, }${_cm_name}"
  [ -s "$_cm" ] && COMMANDS_OK=$((COMMANDS_OK + 1))
done

INST_AGENT_FACT="$(detect_installed_agent_copies)"
INST_AGENT_STATE="${INST_AGENT_FACT#*state=}"; INST_AGENT_STATE="${INST_AGENT_STATE%% *}"
INST_AGENT_TOTAL="${INST_AGENT_FACT#*total=}"; INST_AGENT_TOTAL="${INST_AGENT_TOTAL%% *}"
INST_AGENT_DRIFT="${INST_AGENT_FACT#*drift=}"; INST_AGENT_DRIFT="${INST_AGENT_DRIFT%% *}"
INST_AGENT_NAMES="${INST_AGENT_FACT#*names=}"; INST_AGENT_NAMES="${INST_AGENT_NAMES%% *}"
INST_AGENT_CAUSE="${INST_AGENT_FACT##*cause=}"
HALF_FACT="$(detect_half_uninstalled)";      HALF_STATE="${HALF_FACT##*half-uninstalled=}"

PROFILE_FACT="$(detect_profile_state)"
PROFILE_APPLIED="${PROFILE_FACT#*applied=}";     PROFILE_APPLIED="${PROFILE_APPLIED%% *}"
PROFILE_VERSION="${PROFILE_FACT#*version=}";     PROFILE_VERSION="${PROFILE_VERSION%% *}"
PROFILE_ACCRETION="${PROFILE_FACT##*accretion=}"

PROFILE_VERDICT="unknown"
while IFS= read -r _pline; do
  case "$_pline" in "profile:diff verdict="*) PROFILE_VERDICT="${_pline#profile:diff verdict=}" ;; esac
done < <(profile_diff "$(_profile_template_path)" "$(_profile_plugin_root)")

# The version the payload SHIPS, as distinct from the version a machine has
# applied. They differ exactly when a plugin update has outrun /bionic:setup.
TEMPLATE_PATH="$(_profile_template_path)"
TEMPLATE_VERSION="unknown"
if [ -f "$TEMPLATE_PATH" ]; then
  if command -v jq >/dev/null 2>&1; then
    TEMPLATE_VERSION="$(jq -r '.version // "unknown"' "$TEMPLATE_PATH" 2>/dev/null)"
  else
    TEMPLATE_VERSION="$(grep -oE '"version"[[:space:]]*:[[:space:]]*"[^"]+"' "$TEMPLATE_PATH" 2>/dev/null \
                        | head -1 | grep -oE '"[^"]+"$' | tr -d '"')"
  fi
  [ -n "$TEMPLATE_VERSION" ] || TEMPLATE_VERSION="unknown"
fi

HAVE_JQ=yes; command -v jq >/dev/null 2>&1 || HAVE_JQ=no

# The default permission mode (item 1 + O-3): a fact of the SETTINGS file, not
# of the marker block profile.sh renders — the same `.permissions.defaultMode`
# key `_setup_default_mode` writes. `unset` means the key is genuinely absent;
# `unknown` means jq is missing and the file could not be read at all, which is
# a different claim and must not collapse into the same word.
PROFILE_MODE="unknown"
if [ "$HAVE_JQ" = "yes" ]; then
  PROFILE_SETTINGS_PATH="$(_profile_settings_file)"
  if [ -f "$PROFILE_SETTINGS_PATH" ]; then
    PROFILE_MODE="$(jq -r '.permissions.defaultMode // ""' "$PROFILE_SETTINGS_PATH" 2>/dev/null)"
  else
    PROFILE_MODE=""
  fi
  [ -n "$PROFILE_MODE" ] || PROFILE_MODE="unset"
fi

# ─── The two facts that come from outside this machine's files ───────────────
#
# LOAD STATE is the CLI's own conclusion and is not written anywhere readable, so
# the probe runs the listing — bounded, because a wedged CLI must not wedge the
# diagnosis of the machine it is wedging.
#
# THE FIELD SPLIT. `load-state=<s> error=<e>` in the three determinate states;
# `unknown` adds ` cause=<text>` (A-4.S2.4). `error` can hold spaces and the CLI's
# own punctuation, so it is taken to the end of the line and then trimmed of the
# cause suffix when there is one — the reverse order would truncate an error at
# the first space.
LOAD_FACT="$(detect_bounded "$(detect_probe_seconds)" detect_plugin_load_state "$BIONIC_PLUGIN_ID")"
LOAD_RC=$?
if [ "$LOAD_RC" = "124" ] || [ -z "$LOAD_FACT" ]; then
  LOAD_STATE="unknown"
  LOAD_ERROR="-"
  LOAD_CAUSE="the plugin listing did not answer within $(detect_probe_seconds) seconds"
else
  LOAD_STATE="${LOAD_FACT#load-state=}"; LOAD_STATE="${LOAD_STATE%% *}"
  LOAD_ERROR="${LOAD_FACT#*error=}"
  case "$LOAD_FACT" in
    *" cause="*) LOAD_CAUSE="${LOAD_FACT##* cause=}"; LOAD_ERROR="${LOAD_ERROR%% cause=*}" ;;
    *)           LOAD_CAUSE="" ;;
  esac
fi

# DUPLICATES: zero or more lines, each already carrying its own consolidation
# command. Silence means none — except that the probe never stays silent when it
# could not look (A-4.S2.8), which is why an unreadable registry arrives here as
# a `dup=unknown` line rather than as nothing. The bound is the probe's own now
# (W6 S15): the registry read runs `jq` over a path that can stall, so it goes
# through the same `detect_bounded` the listing does, and a stalled read arrives
# here as one more `dup=unknown` line with the seconds in its cause.
DUP_LINES="$(detect_plugin_duplicates)"

# ─── The dependency sweep ────────────────────────────────────────────────────
#
# One pass over the table produces three renderings at once — the dependency
# rows, the roster-footprint rows, and the degradation map — because they are
# three views of the same facts and a second pass would be a second chance to
# disagree with the first.

# The installed tree of a plugin-shaped dependency, as the CLI recorded it, comes from
# detect.sh's `detect_plugin_install_path` — the same parse `detect_plugin_root` resolves
# bionic through. `installPath` is the registry's own answer to "where did this land", which
# is what makes the roster count a measurement rather than a guess about layout.
#
# THIS USED TO BE A SECOND PARSE (Step-6 review, RV-7). A local `_doctor_install_path` read
# the same CLI-internal schema with its own jq program, which is a duplication that cannot
# be noticed from either side: the CLI renames a field, the pinned copy in detect.sh gets
# fixed, and this one keeps answering in the old shape just as confidently. It also left
# detect_plugin_root with zero production callsites (RV-4) — the parse under test was the
# parse nobody ran. Deleting the local copy discharges both: one reading, and it is the
# reading the suite drives.
#
# TWO THINGS IMPROVED IN THE MOVE, both in the direction of answering rather than shrugging.
# The local copy gave up outright without `jq`; the shared parse has an awk lane, so a
# jq-less box now gets real roster counts instead of `unknown` wherever presence itself was
# knowable. And the shared parse checks that the recorded directory EXISTS, so a stale
# registry entry reports as unreadable here rather than as a confident count of zero.

# ROSTER FOOTPRINT, the counting method (design-ledger D6). Skill and agent
# METADATA — name plus description — is what loads into every session; the
# bodies are just-in-time. So a dependency's session cost is the number of skill
# and agent entries it contributes, and the layout the CLI installs says exactly
# where those live: one `skills/<slug>/SKILL.md` per skill, one `agents/<name>.md`
# per agent, under the registry's `installPath`. Counting the files IS counting
# the roster lines. A dependency that is not plugin-shaped — a binary, an npm
# package, an MCP registration — carries no skill or agent metadata, so it costs
# nothing at all.
#
# THE BRANCH IS ON SHAPE, NOT ON CLASS, and that distinction is a corrected bug
# (S3's hand-on). It used to key on the old dependency-lane code, which meant
# "installed by the harness" — and impeccable installs through the CLI exactly
# like the two core plugins while belonging to a different class. Keyed the old
# way, an INSTALLED plugin contributing a skill to every session was reported as
# contributing zero.
_doctor_roster_counts() {  # <install-path> -> "<skills> <agents>"
  local root="${1:-}" p skills=0 agents=0
  for p in "$root"/skills/*/SKILL.md; do [ -f "$p" ] && skills=$((skills + 1)); done
  for p in "$root"/agents/*.md;       do [ -f "$p" ] && agents=$((agents + 1)); done
  echo "${skills} ${agents}"
}

DEP_ROWS=""
THIRD_ROWS=""
ROSTER_ROWS=""
DEP_VERSIONS=""
N_PRESENT=0; N_ABSENT=0; N_UNKNOWN=0; N_VIOLATION=0
N_ABSENT_ACTIONABLE=0; N_ABSENT_WHEN_NEEDED=0
ROSTER_TOTAL=0; ROSTER_TOTAL_KNOWN=yes
ROSTER_ZERO=0
ABSENT_NAMES=""
CCSTATUSLINE_STATE="unknown"

while IFS= read -r dep_name; do
  [ -n "$dep_name" ] || continue
  fact="$(detect_dep "$dep_name")" || continue

  present="${fact#*present=}";     present="${present%% *}"
  dep_version="${fact#*version=}"; dep_version="${dep_version%% *}"
  constraint="${fact#*constraint=}"; constraint="${constraint%% *}"
  verdict="${fact##*verdict=}"
  # WHEN bionic installs it, and HOW. `class` is what the table now declares and
  # what this report prints; `kind` names the install mechanism and decides the
  # two branches below that are about shape rather than policy.
  dep_class="$(dep_field "$dep_name" class)"
  kind="$(dep_field "$dep_name" kind)"

  [ "$dep_name" = "ccstatusline" ] && CCSTATUSLINE_STATE="$present"
  DEP_VERSIONS="${DEP_VERSIONS}${dep_name}	${dep_version}"$'\n'

  # THE SYMBOL IS THE VERDICT COLUMN (AC-15 rule 1). The table used to carry the
  # word `ok`/`violation` in a sixth column; ✓/✗/– says the same thing in column
  # one, where a reader scanning twenty rows for the one that is wrong is already
  # looking. `violation` survives as the row's tail because it names WHICH kind of
  # wrong, which a symbol cannot, and the unknown rows carry their cause there for
  # the same reason.
  case "$present" in
    yes) if [ "$verdict" = "violation" ]; then dep_sym="$DOCTOR_BAD"; dep_tail="violation"
         else dep_sym="$DOCTOR_OK"; dep_tail=""; fi ;;
    no)  dep_tail=""
         if [ "$dep_class" = "when-needed" ]; then dep_sym="$DOCTOR_NIL"; dep_tail="installs on first use"
         else dep_sym="$DOCTOR_BAD"; fi ;;
    *)   dep_tail="$(_doctor_unknown_cause "$kind")"
         if [ "$dep_class" = "when-needed" ]; then dep_sym="$DOCTOR_NIL"; else dep_sym="$DOCTOR_BAD"; fi ;;
  esac
  [ "$present" = "no" ] && dep_version="-"
  DEP_ROWS="${DEP_ROWS}$(_doctor_rtrim "$(printf '  %s %-12s %-20s %-8s %-9s %-11s %s' \
    "$dep_sym" "$dep_class" "$dep_name" "$(_doctor_word "$present")" \
    "$dep_version" "$constraint" "$dep_tail")")"$'\n'

  # ── the certified THIRD PARTY row ──
  #
  # A LITERAL VERSION WHEREVER ONE EXISTS. That is the whole point of the table:
  # `present` is a yes/no a user already assumed, and the version is the fact
  # that settles whether the thing on this machine is the thing the constraint
  # was written about. So a row reaches for a number twice — once through the
  # library's own probe, and once more through the npx cache for the one
  # mechanism whose probe cannot pin a version by construction — and only prints
  # `—` when there is genuinely nothing on disk to read.
  #
  # AND THE DASH IS NEVER BARE. Where a version could not be had, the state cell
  # says which mechanism could not keep one. A dash on its own reads as a bug in
  # this report rather than as a property of the thing being reported.
  third_version="$dep_version"
  third_state=""
  # MULTI-PART ROWS SAY WHAT IS PRESENT (Chris 2026-08-22: "Why is ccstatusline
  # 'ok' for version, with no status?"). The two-half probes return a status word
  # in the version slot — it is not a version and never prints as one. The
  # version comes from wherever the mechanism actually keeps one (the npx cache,
  # the clone's HEAD), and the state cell names the halves that are in place.
  if [ "$present" = "yes" ]; then
    case "$kind" in
      statusline)
        third_version="$(dep_npx_version "$(_dep_locator_target "$(dep_field "$dep_name" source_url)")")"
        third_state="command + layout file match" ;;
      mcp-server)
        [ "$third_version" = "unknown" ] && \
          third_version="$(dep_npx_version "$(_dep_locator_target "$(dep_field "$dep_name" source_url)")")" ;;
      github-skill)
        third_version="$(git -C "$(_dep_skills_dir)/${dep_name}" rev-parse --short=12 HEAD 2>/dev/null || echo unknown)"
        third_state="skill installed" ;;
      uv-tool)
        [ "$dep_name" = "notebooklm" ] && third_state="CLI + skill installed" ;;
    esac
  fi
  case "$present" in
    yes)
      if [ "$verdict" = "violation" ]; then
        third_state="violates ${constraint} → /bionic:setup"
      elif [ "$third_version" = "unknown" ] && [ -z "$third_state" ]; then
        third_state="$(_doctor_no_version_reason "$kind")"
      fi ;;
    no)
      if [ "$dep_class" = "when-needed" ]; then third_state="installs on demand"
      else third_state="not installed → /bionic:setup"; fi ;;
    *)
      third_state="$(_doctor_unknown_cause "$kind")"
      [ "$dep_class" = "when-needed" ] || third_state="${third_state} → /bionic:setup" ;;
  esac
  case "$third_version" in unknown|-|"") third_version="—" ;; esac
  THIRD_ROWS="${THIRD_ROWS}$(_doctor_third_row "$dep_sym" "$dep_name" "$third_version" \
    "$(_doctor_source_of "$dep_name")" "$third_state")"$'\n'

  # ── roster footprint ──
  #
  # ZERO IS FILLER (AC-15 rule 4). A dependency that is not plugin-shaped
  # contributes nothing to the session roster, and so does one that is not
  # installed — fourteen such rows on this machine, each a line saying nothing.
  # They are counted here and printed as a single line below. An `unknown` is NOT
  # filler and keeps its own row: it is a number this report could not take, and
  # collapsing it into a count of zeroes would report an unreadable machine as a
  # cheap one.
  if [ "$kind" != "native" ] || [ "$present" = "no" ]; then
    ROSTER_ZERO=$((ROSTER_ZERO + 1))
  elif [ "$present" = "unknown" ]; then
    ROSTER_ROWS="${ROSTER_ROWS}$(_doctor_rtrim "$(printf '  %s %-21s %-9s %s' \
      "$DOCTOR_NIL" "$dep_name" "unknown" "$(_doctor_unknown_cause "$kind")")")"$'\n'
    ROSTER_TOTAL_KNOWN=no
  else
    install_path="$(detect_plugin_install_path "$dep_name")" || install_path=""
    if [ -z "$install_path" ] || [ ! -d "$install_path" ]; then
      ROSTER_ROWS="${ROSTER_ROWS}$(_doctor_rtrim "$(printf '  %s %-21s %-9s %s' \
        "$DOCTOR_NIL" "$dep_name" "unknown" "no readable installPath in the registry")")"$'\n'
      ROSTER_TOTAL_KNOWN=no
    else
      counts="$(_doctor_roster_counts "$install_path")"
      n_skills="${counts%% *}"; n_agents="${counts##* }"
      roster_lines=$((n_skills + n_agents))
      if [ "$roster_lines" = "0" ]; then
        ROSTER_ZERO=$((ROSTER_ZERO + 1))
      else
        ROSTER_ROWS="${ROSTER_ROWS}$(_doctor_rtrim "$(printf '  %s %-21s %-9s %s' \
          "$DOCTOR_OK" "$dep_name" "$roster_lines" \
          "${n_skills} $(_doctor_plural "$n_skills" skill skills) + ${n_agents} $(_doctor_plural "$n_agents" agent agents)")")"$'\n'
      fi
      ROSTER_TOTAL=$((ROSTER_TOTAL + roster_lines))
    fi
  fi

  # ── tallies and the degradation map ──
  #
  # AN ABSENT WHEN-NEEDED TOOL IS NOT A DEGRADATION (D-B, ratified 2026-08-20).
  # Absence is its NORMAL state: these install at the moment a route first needs
  # them, so a machine that has never run that route is correct to be without
  # them. Doctor used to call every absence a degradation and raise a matching
  # action, which told users to repair a machine that was working — and told them
  # to run the one command that would not have installed it anyway, since setup
  # deliberately never asks about these rows.
  #
  # AND A NO-ACTION LINE IS NOT A FIX (AC-15 rule 2). The degradation map used to
  # carry a line for every unusual row, including the when-needed ones whose line
  # ended "no action needed" — a problem list with entries that are not problems,
  # which is how a reader learns to skip the list. Those rows say what they are in
  # the DEPENDENCIES table (`– … installs on first use`) and reach FIX never.
  case "$present" in
    yes)
      N_PRESENT=$((N_PRESENT + 1))
      if [ "$verdict" = "violation" ]; then
        N_VIOLATION=$((N_VIOLATION + 1))
        case "$dep_class" in
          when-needed)
            fix "${dep_name} ${dep_version} violates constraint ${constraint} → the next route that needs it reinstalls it" ;;
          *)
            fix "${dep_name} ${dep_version} violates constraint ${constraint} → run /bionic:setup" ;;
        esac
      fi
      ;;
    no)
      N_ABSENT=$((N_ABSENT + 1))
      case "$dep_class" in
        when-needed)
          N_ABSENT_WHEN_NEEDED=$((N_ABSENT_WHEN_NEEDED + 1)) ;;
        *)
          N_ABSENT_ACTIONABLE=$((N_ABSENT_ACTIONABLE + 1))
          # NAMED HERE, PRINTED AS ONE LINE BELOW. Eleven absences on a cold
          # machine are eleven problems with one identical command, and eleven
          # copies of `run /bionic:setup` is the filler rule 4 exists to stop.
          # The names are what the reader needs; the command is said once.
          ABSENT_NAMES="${ABSENT_NAMES}${ABSENT_NAMES:+, }${dep_name}" ;;
      esac
      ;;
    *)
      N_UNKNOWN=$((N_UNKNOWN + 1))
      # KEYED ON THE CLASS, WHICH IS WHAT THE SENTENCE IS ABOUT (six-axis review
      # C-2). This branch used to key on the mechanism — `pnpm-store` rows were
      # told "/bionic:setup re-warms the store either way" — and that was true
      # only while setup walked every non-native row. Setup now asks about
      # `core|basic|extra` and AC-11 makes a when-needed tool nobody's to install
      # until a route needs it, so the old clause named a command that would not
      # touch the row. A when-needed unknown has the same non-action as a
      # when-needed absence, and for the same reason — so it earns no FIX line.
      #
      # AMENDED 2026-08-22: TWO FACTS DECIDE THIS SENTENCE, and they are
      # orthogonal. The CLASS says whose job the row is. The MECHANISM says
      # whether the unknown can ever be RESOLVED — the pnpm store is a cache with
      # no installed-state to read, so "resolve the cause, then re-run doctor"
      # names a repair that does not exist. Class alone was enough while the only
      # such row was `when-needed`; the ruling that made `motion` an `extra` sent
      # it straight to the sentence about a repair nobody can perform.
      case "${dep_class}/${kind}" in
        when-needed/*) ;;
        */pnpm-store)  ;;
        *) fix "${dep_name} presence is unknown → resolve $(_doctor_unknown_cause "$kind"), then re-run /bionic:doctor" ;;
      esac
      ;;
  esac
done < <(dep_names)

# ─── What is left to fix ─────────────────────────────────────────────────────
#
# COLLECTED BEFORE ANYTHING IS PRINTED, because FIX is the second section on the
# page and the facts that fill it are discovered all the way down this file. The
# dependency sweep above has already contributed its lines; what follows is the
# machine-level half — the states that are not about one dependency.
#
# ONE LINE PER PROBLEM, ENDING IN THE COMMAND (AC-15 rule 2). The report used to
# say each of these twice: once in the degradation map as a fact, once in the
# summary as an action. One section now, one line, and the line ends with what to
# type.

# LOAD STATE FIRST, for the reason its section leads: on a machine where the
# plugin did not load, every other line here is advice about a payload nothing is
# running. `unknown` earns no line — nobody can act on "I could not tell", and
# the section names why.
case "$LOAD_STATE" in
  failed)
    fix "bionic is installed but the CLI refused to load it → install what LOAD STATE names" ;;
  absent)
    fix "bionic is not installed for this CLI → claude plugin install ${BIONIC_PLUGIN_ID}" ;;
esac

# Half-uninstalled next: it is the one state /bionic:setup cannot repair, because
# the command surface itself is gone. The curl door is the fix (D5a — the remover
# must not depend on the thing it removes).
#
# THE ONE FIX THAT TAKES TWO LINES, and deliberately. Every other line here fits
# inside 100 columns; this one carries a raw GitHub URL inside a pipefail wrapper
# and cannot. A command the reader has to unwrap from a wrapped line is worse
# than a command on a line of its own, so the problem is stated and the command
# is given whole underneath it.
if [ "$HALF_STATE" = "yes" ]; then
  fix "this machine is half-uninstalled — the CLI no longer knows bionic. Finish with:"
  # The `set -o pipefail` wrapper is not decoration. `curl … | bash` reports
  # BASH's status, and bash handed an empty stream exits 0 — so a fetch that
  # 404s (a moved script, no network, a private repo) leaves the user with a
  # command that looked like it worked and removed nothing. The wrapper is a
  # subshell, so it fixes the status without touching the options of the shell
  # the user pasted it into. `-S` inside `-fsSL` is what puts curl's own error
  # on the terminal; the wrapper is what stops the pipe from swallowing it.
  FIX_LINES="${FIX_LINES}      bash -c 'set -o pipefail; curl -fsSL ${BIONIC_REMOVE_RAW_URL} | bash'"$'\n'
fi

# jq next: it gates several of the facts above, so acting on anything else while
# the report is partly unreadable is acting on half a diagnosis.
if [ "$HAVE_JQ" = "no" ]; then
  fix "several facts below read unknown without it → install jq (/bionic:setup does)"
fi

# THE ABSENCES AS ONE LINE, NAMED. The ACTIONABLE absences, not every absence: a
# when-needed tool is absent by design until a route asks for it, and setup would
# not install it if it ran. The names are truncated rather than wrapped — a cold
# machine has eleven of them and the line has 100 columns.
if [ -n "$ABSENT_NAMES" ]; then
  _doctor_absent_list="$ABSENT_NAMES"
  if [ "${#_doctor_absent_list}" -gt 44 ]; then
    _doctor_absent_list="$(printf '%.41s' "$_doctor_absent_list")…"
  fi
  fix "${N_ABSENT_ACTIONABLE} $(_doctor_plural "$N_ABSENT_ACTIONABLE" dependency dependencies) absent (${_doctor_absent_list}) → run /bionic:setup"
fi

# THE FILE IS WHAT SETUP CAN REPAIR. A name live in this process but absent from
# settings.json still earns this line: the value dies with the session, and the
# next one starts without it. A name configured and merely not live earns
# NOTHING here — that is a restart, which the ENVIRONMENT section names, and
# setup would find nothing to do.
ENV_MISSING=0
for _env_key in $ENV_KEYS; do
  env_get "$_env_key" >/dev/null 2>&1 || ENV_MISSING=$((ENV_MISSING + 1))
done
if [ "$ENV_MISSING" -gt 0 ]; then
  fix "${ENV_MISSING} of bionic's environment settings $(_doctor_plural "$ENV_MISSING" is are) not written → run /bionic:setup"
fi

[ "$LEGACY_STATE" = "yes" ] && fix "the legacy .zshrc alias block is still there → run /bionic:setup"
case "$LEGACY_HOOK_COUNT" in
  unknown|0) ;;
  *) fix "${LEGACY_HOOK_COUNT} legacy-channel managed-hook $(_doctor_plural "$LEGACY_HOOK_COUNT" entry entries) in settings.json → run /bionic:setup" ;;
esac
# The skill copy, and NOT the hook files beside it. Setup step 7 owns the consented removal,
# so there is a real thing to offer; and unlike the files, this copy is doing something —
# arming eleven registrations a second time. The asymmetry is the point, and
# tests/doctor.test.sh Group 14 pins it from the other side with a machine whose only
# leftover is hook files and whose summary still reads "nothing to do".
[ "$SKILL_COPY_STATE" = "yes" ] && fix "a legacy skill copy is installed, arming the same walls twice → run /bionic:setup"

# The permission profile is its own line: it is repaired by the same command, but
# the reason is a state a user should see named rather than folded into a count.
if [ "$PROFILE_VERDICT" = "stale" ]; then
  fix "the applied permission profile is stale → run /bionic:setup"
elif [ "$PROFILE_APPLIED" = "no" ] && [ "$PROFILE_VERDICT" = "absent" ]; then
  fix "no permission profile is applied → run /bionic:setup"
fi

if [ "$PLUGIN_HOOKS" = "degraded" ] || [ "$PLUGIN_HOOKS" = "absent" ]; then
  # THE HINT IS THE WHOLE TAIL, AND IT KNOWS WHICH STATE IS ASKING (W7 S11,
  # six-axis review axis 2). This used to print `re-converge with:` and then the hint
  # inside backticks — which on a directory-source machine handed a user whose tree is
  # genuinely broken the words "nothing to do" formatted as a command to type.
  # TERSE ON PURPOSE (AC-15): the hint this line ends with is 76 columns of
  # named copy and verbatim command, and the PLUGIN INTEGRITY row two sections
  # down already spells out what "degraded" means. Anything longer here wraps.
  fix "hooks ${PLUGIN_HOOKS} → $(detect_reconverge_hint hooks)"
fi

# How many problems, for the summary line. Counted from the printed lines rather
# than from a tally kept alongside them, so the number and the list cannot come
# to disagree: the continuation line under the half-uninstalled fix is indented
# and does not carry the symbol, which is exactly why the count keys on it.
N_FIX=0
if [ -n "$FIX_LINES" ]; then
  while IFS= read -r _fix_line; do
    case "$_fix_line" in "  ${DOCTOR_BAD} "*) N_FIX=$((N_FIX + 1)) ;; esac
  done <<< "$FIX_LINES"
fi

# ─── The report ──────────────────────────────────────────────────────────────
#
# THE HEADER IS A PROVENANCE LINE, and it replaces a sentence that told the
# reader what doctor does. They already know — they typed it. What they cannot
# know without being told is WHICH payload just answered them, and on a machine
# carrying a plugin install, a checkout and a marketplace copy of the same thing,
# that is the fact every other line below is relative to.
echo "Bionic Doctor — payload ${PLUGIN_VERSION} @ ${PAYLOAD_SHA}"

# ─── The verdict, on the line under it ───────────────────────────────────────
#
# TWO QUESTIONS, ANSWERED BEFORE ANY EVIDENCE: is anything wrong, and what do I
# type. The arrow is not decoration — it marks the only lines in this report that
# are addressed to the reader as instructions rather than as facts, so a reader
# scanning for "what am I supposed to do" has one shape to look for.
#
# THE SETUP-FIXABLE PROBLEMS COLLAPSE INTO ONE LINE and the rest each get their
# own. Eleven absences on a cold machine are eleven problems with one identical
# command; printing that command eleven times teaches a reader to stop reading
# it. A problem setup CANNOT repair — a half-uninstalled machine, a CLI that
# refused to load the plugin — would be buried by that collapse, so it stays a
# line of its own with its own command on it.
if [ "$N_FIX" = "0" ]; then
  echo "→ Nothing to do. This machine is fully set up."
else
  _doctor_verdict="→ ${N_FIX} $(_doctor_plural "$N_FIX" problem problems)."
  if [ -n "$FIX_NAMES_SETUP" ]; then
    _doctor_verdict="${_doctor_verdict} Run /bionic:setup to fix: ${FIX_NAMES_SETUP}"
    # TRUNCATED RATHER THAN WRAPPED. The names are what makes this line worth
    # reading, and a cold machine has enough of them to run past a terminal's
    # width — where the line would break into a second one and undo the whole
    # rule. The count above is exact either way.
    
    if [ "${#_doctor_verdict}" -gt 99 ]; then
      _doctor_verdict="$(printf '%.96s' "$_doctor_verdict")…"
    fi
  fi
  printf '%s\n' "$_doctor_verdict"
  if [ -n "$FIX_LINES_OTHER" ]; then
    while IFS= read -r _fix_other; do
      [ -n "$_fix_other" ] || continue
      printf '→ %s\n' "$_fix_other"
    done <<< "$FIX_LINES_OTHER"
    # The one command that cannot ride on its own line: a raw URL inside a
    # pipefail wrapper, printed whole underneath rather than wrapped by the
    # terminal into something nobody can paste.
    [ "$HALF_STATE" = "yes" ] && \
      echo "   bash -c 'set -o pipefail; curl -fsSL ${BIONIC_REMOVE_RAW_URL} | bash'"
  fi
fi

# ─── Table 1 — what ships inside the plugin ──────────────────────────────────
#
# THE OWNERSHIP SPLIT IS THE ORGANISING IDEA of all three tables, and it answers
# the question the old section list never did: when something here is wrong, whose
# machinery repairs it. Everything in this table arrived with the plugin install
# and is repaired by re-installing the plugin; everything in the next arrived
# through /bionic:setup and is repaired by running it again. A reader who knows
# which table a broken row is in already knows what to type.
echo ""
echo "BIONIC NATIVE — ships inside the plugin"
_doctor_native_row " " "component" "count" "detail"
if [ "$SKILLS_OK" = "$SKILLS_TOTAL" ] && [ "$SKILLS_TOTAL" -gt 0 ]; then
  _doctor_native_row "$DOCTOR_OK" "skills" "${SKILLS_OK}/${SKILLS_TOTAL}" "$SKILL_NAMES"
else
  _doctor_native_row "$DOCTOR_BAD" "skills" "${SKILLS_OK}/${SKILLS_TOTAL}" \
    "a skill directory carries no SKILL.md → reinstall the plugin"
fi
case "$AGENT_STATE" in
  stock)
    _doctor_native_row "$DOCTOR_OK" "agents" "${AGENT_TOTAL}/${AGENT_TOTAL}" "stock" ;;
  modified)
    # `–`, NOT ✗, and nothing in the verdict above asks for these files back.
    # Editing your own installed role files is allowed; the row says what the
    # machine has and names the undo in the same breath.
    _doctor_native_row "$DOCTOR_NIL" "agents" \
      "$((AGENT_TOTAL - AGENT_MODIFIED))/${AGENT_TOTAL}" \
      "${AGENT_MODIFIED} edited locally (${AGENT_NAMES//,/, }) — reinstall restores stock" ;;
  *)
    _doctor_native_row "$DOCTOR_NIL" "agents" "?/${AGENT_TOTAL}" "unknown — ${AGENT_CAUSE}" ;;
esac
case "$PLUGIN_HOOKS" in
  ok)
    _doctor_native_row "$DOCTOR_OK" "hooks" "${HOOK_RESOLVING}/${HOOK_TOTAL}" "" ;;
  absent)
    _doctor_native_row "$DOCTOR_BAD" "hooks" "0/0" \
      "the payload carries no hooks/hooks.json → reinstall the plugin" ;;
  *)
    _doctor_native_row "$DOCTOR_BAD" "hooks" "${HOOK_RESOLVING}/${HOOK_TOTAL}" \
      "$(detect_reconverge_hint hooks)" ;;
esac
if [ "$COMMANDS_OK" = "$COMMANDS_TOTAL" ] && [ "$COMMANDS_TOTAL" -gt 0 ]; then
  _doctor_native_row "$DOCTOR_OK" "commands" "${COMMANDS_OK}/${COMMANDS_TOTAL}" "$COMMAND_NAMES"
else
  _doctor_native_row "$DOCTOR_BAD" "commands" "${COMMANDS_OK}/${COMMANDS_TOTAL}" \
    "a command file is empty → reinstall the plugin"
fi
# THE TWO STATES THAT MAKE EVERY ROW ABOVE MOOT, and they are printed here only
# when they are true. A payload can be whole on disk and not be running: the CLI
# may have refused to load it, or a teardown may have taken the command surface
# away and left the files. Either way the four rows above describe something this
# session is not executing, and a table that did not say so would be four
# confident answers to the wrong question.
case "$LOAD_STATE" in
  loaded) ;;
  failed)
    _doctor_native_row "$DOCTOR_BAD" "plugin" "—" "the CLI refused to load it: ${LOAD_ERROR}" ;;
  absent)
    _doctor_native_row "$DOCTOR_BAD" "plugin" "—" \
      "not installed for this CLI → claude plugin install ${BIONIC_PLUGIN_ID}" ;;
  *)
    _doctor_native_row "$DOCTOR_NIL" "plugin" "—" "load state unknown — ${LOAD_CAUSE}" ;;
esac
[ "$HALF_STATE" = "yes" ] && \
  _doctor_native_row "$DOCTOR_BAD" "install" "—" "half-uninstalled — the CLI no longer knows bionic"

# ─── Table 2 — what /bionic:setup put on this machine ────────────────────────
echo ""
echo "THIRD PARTY — installed by /bionic:setup"
_doctor_third_row " " "name" "version" "source" "state"
printf '%s' "$THIRD_ROWS"

# ─── Table 3 — the environment this machine runs bionic in ───────────────────
#
# TWO FACTS PER NAME, AND NEITHER ANSWERS THE OTHER. `env_get` reads the CLI's
# settings.json — what a session started from now on will have. `env_live` reads
# THIS process — what the session you are in has. On 2026-08-21 a session ran
# with the task-list name written to disk and absent from the process (the host
# launches its shell with rc files disabled, so the export bionic used to append
# never arrived), and the one line this section carried could not say so.
# Configured-and-not-live is a RESTART; absent is a setup gap; and telling a user
# to run setup over a restart sends them to repair something already repaired.
# Which is also why a restart-pending name is `–` and an absent one is ✗: only
# one of them has a line in the verdict.
echo ""
echo "ENVIRONMENT"
for _env_key in $ENV_KEYS; do
  _env_configured="$(env_get "$_env_key" 2>/dev/null)" || _env_configured=""
  if _env_live_value="$(env_live "$_env_key" 2>/dev/null)"; then _env_is_live=yes; else _env_is_live=no; fi
  if [ -n "$_env_configured" ]; then
    if [ "$_env_is_live" = "yes" ]; then
      _doctor_env_row "$DOCTOR_OK" "${_env_key}=${_env_configured}" "live in session"
    else
      _doctor_env_row "$DOCTOR_NIL" "${_env_key}=${_env_configured}" "restart to pick it up"
    fi
  elif [ "$_env_is_live" = "yes" ]; then
    # Live and not configured: the state the retired shell export leaves behind.
    # It works right now and dies with this session, which is why setup is still
    # named for it in the verdict above.
    _doctor_env_row "$DOCTOR_BAD" "${_env_key}=${_env_live_value}" \
      "live in session, not written → /bionic:setup"
  else
    _doctor_env_row "$DOCTOR_BAD" "${_env_key}" "not set → /bionic:setup"
  fi
done
# The permission profile as ONE row. Three facts stand behind it — what the
# payload ships, what this machine applied, and whether the applied block still
# matches a fresh render — and on a healthy machine they agree, so the row is the
# version and nothing else. They disagree in exactly two ways worth a user's
# attention, and each of those has a line in the verdict.

case "$PROFILE_VERDICT" in
  identical) _doctor_env_row "$DOCTOR_OK"  "permission profile" "${PROFILE_VERSION} applied" ;;
  stale)     _doctor_env_row "$DOCTOR_BAD" "permission profile" \
               "${PROFILE_VERSION} applied, stale → /bionic:setup" ;;
  absent)    _doctor_env_row "$DOCTOR_BAD" "permission profile" "none applied → /bionic:setup" ;;
  *)         _doctor_env_row "$DOCTOR_NIL" "permission profile" "unknown — jq is not on PATH" ;;
esac
case "$CCSTATUSLINE_STATE" in
  yes)     _doctor_env_row "$DOCTOR_OK"  "statusline" "ccstatusline" ;;
  unknown) _doctor_env_row "$DOCTOR_NIL" "statusline" "unknown — $(_doctor_unknown_cause statusline)" ;;
  *)       _doctor_env_row "$DOCTOR_BAD" "statusline" "not configured → /bionic:setup" ;;
esac
# THE LEFTOVERS, AND ONLY WHEN THERE ARE ANY. Six checks ask the same kind of
# question — did the retired installer leave something behind — and on a machine
# that never ran it, or has been cleaned once, all six answer no. Silence is the
# right output for that.

[ "$LEGACY_STATE" = "yes" ] && \
  _doctor_env_row "$DOCTOR_BAD" "legacy .zshrc alias block" "present → /bionic:setup"
case "$LEGACY_HOOK_COUNT" in
  unknown|0) ;;
  *) _doctor_env_row "$DOCTOR_BAD" "legacy-channel managed hooks" \
       "${LEGACY_HOOK_COUNT} in settings.json → /bionic:setup" ;;
esac
[ "$SKILL_COPY_STATE" = "yes" ] && \
  _doctor_env_row "$DOCTOR_BAD" "legacy installed skill copy" \
    "arms the same walls twice → /bionic:setup"


# ─── The one question, and the section it appends ────────────────────────────
#
# EVERYTHING ABOVE THIS LINE IS INSTANT. That is what earns the question its
# place at the end: the report is already complete and already printed, so a user
# who says no has lost nothing and a user who says yes knows exactly what they
# are waiting for. The question states its own cost in the same breath, because a
# prompt that hides a thirty-second wait is not a question, it is a trap.
#
# WHERE THE ANSWER CAN COME FROM. A terminal, a pipe, or a file — the three ways
# a caller can actually answer. Anything else (a closed stream, the socket a tool
# harness hands a script) gets no question at all: printing one there would put
# an unanswerable prompt in a report and then, if this code read anyway, block
# forever waiting for a reply nobody is going to send. Measured, not assumed —
# an unguarded read against a harness-supplied stream does not return.
#
# THE PROMPT SHAPE IS deps.sh's, by eye and not by call: doctor is forbidden to
# reach into the consent machinery (that library's asking function belongs to the
# code that mutates things, and this code mutates nothing), so the shape is
# reproduced here and the ban stays intact.
_doctor_can_ask() {
  [ -t 0 ] && return 0
  [ -p /dev/stdin ] && return 0
  [ -f /dev/stdin ] && return 0
  return 1
}

# The version the dependency sweep already probed. Used only where a package
# manager reports that a row is outdated without saying what is installed — the
# answer is already in this report and asking twice could disagree with itself.
_doctor_row_version() {  # <name>
  local want="${1:-}" n v
  while IFS="$(printf '\t')" read -r n v; do
    [ "$n" = "$want" ] || continue
    printf '%s' "${v:-unknown}"
    return 0
  done <<< "$DEP_VERSIONS"
  printf '%s' "unknown"
}

# INTERSECTED WITH THE TABLE, ALWAYS. Both managers answer about the whole
# machine; bionic reports only on the rows it manages. Anything else would make a
# tool bionic never installed look like bionic's problem — including, on this
# machine's own history, tools this wave deliberately dropped.
_doctor_updates_brew() {
  local out rc name target line cur latest
  if ! command -v brew >/dev/null 2>&1; then
    printf '  %-22s %s\n' "not checked" "— Homebrew is not on this machine"
    return 0
  fi
  # HOMEBREW_NO_AUTO_UPDATE, and it is not a preference. `brew outdated` will
  # otherwise fetch Homebrew's own repositories first — a write to the machine
  # doctor promised not to change, and a fetch slow enough to spend the whole
  # bound before the question even gets answered. The user asked what is
  # outdated, not for Homebrew to update itself.
  out="$(detect_bounded "$(detect_probe_seconds)" env HOMEBREW_NO_AUTO_UPDATE=1 brew outdated --verbose 2>/dev/null)"
  rc=$?
  if [ "$rc" = "124" ] || { [ "$rc" -ne 0 ] && [ -z "$out" ]; }; then
    printf '  %-22s %s\n' "not checked" "— Homebrew offline or timed out"
    return 0
  fi
  [ -n "$out" ] || return 0
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    target="$(_dep_locator_target "$(dep_field "$name" mechanism)")"
    line="$(printf '%s\n' "$out" | awk -v t="$target" '$1 == t { print; exit }')"
    [ -n "$line" ] || continue
    # `<formula> (<installed>) < <latest>` is the verbose shape. A terser
    # Homebrew that prints the bare name still gets a row — with the version this
    # report already knows and an honest word for the half it was not told.
    case "$line" in
      *" < "*)
        cur="${line%% <*}"; cur="${cur#* (}"; cur="${cur%)*}"
        latest="${line##*< }" ;;
      *)
        cur="$(_doctor_row_version "$name")"; latest="a newer version" ;;
    esac
    printf '  %-22s %-11s → %-13s %s\n' "$name" "$cur" "$latest" "brew upgrade ${target}"
  done < <(dep_names_kind brew-dep)
  return 0
}

_doctor_updates_npm() {
  local out rc parsed name target line cur latest
  if ! command -v npm >/dev/null 2>&1; then
    printf '  %-22s %s\n' "not checked" "— npm is not on this machine"
    return 0
  fi
  out="$(detect_bounded "$(detect_probe_seconds)" npm outdated -g --json 2>/dev/null)"
  rc=$?
  # npm EXITS 1 WHEN IT FINDS SOMETHING OUTDATED. That is the answer, not a
  # failure, and treating it as one would make the section silent on exactly the
  # machines it exists for.
  if [ "$rc" = "124" ] || { [ "$rc" -ne 0 ] && [ -z "$out" ]; }; then
    printf '  %-22s %s\n' "not checked" "— npm offline or timed out"
    return 0
  fi
  [ -n "$out" ] || return 0
  if [ "$HAVE_JQ" = "no" ]; then
    printf '  %-22s %s\n' "not checked" "— npm answers in JSON and jq is not on PATH"
    return 0
  fi
  parsed="$(printf '%s' "$out" | jq -r 'to_entries[] | [.key, (.value.current // "unknown"), (.value.latest // "unknown")] | @tsv' 2>/dev/null)"
  if [ -z "$parsed" ]; then
    printf '  %-22s %s\n' "not checked" "— npm's report could not be read"
    return 0
  fi
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    target="$(_dep_locator_target "$(dep_field "$name" mechanism)")"
    line="$(printf '%s\n' "$parsed" | awk -F'\t' -v t="$target" '$1 == t { print; exit }')"
    [ -n "$line" ] || continue
    cur="$(printf '%s' "$line" | awk -F'\t' '{print $2}')"
    latest="$(printf '%s' "$line" | awk -F'\t' '{print $3}')"
    [ "$cur" != "unknown" ] || cur="$(_doctor_row_version "$name")"
    printf '  %-22s %-11s → %-13s %s\n' "$name" "$cur" "$latest" "npm install -g ${target}@latest"
  done < <(dep_names_kind npm-global)
  return 0
}

_doctor_render_updates() {
  local UPDATES_BREW UPDATES_NPM
  UPDATES_BREW="$(_doctor_updates_brew)"
  UPDATES_NPM="$(_doctor_updates_npm)"
  echo "=== UPDATES ==="
  # THE COMMAND IS THE DELIVERABLE. Doctor diagnoses and never treats, so what a
  # row hands over is the exact line to run, not an offer to run it.
  echo "  Nothing is installed or upgraded here — each row is the command to run."
  echo ""
  if [ -z "$UPDATES_BREW" ] && [ -z "$UPDATES_NPM" ]; then
    echo "  Every managed tool is at its latest version."
  else
    # `printf '%s\n'`, and only when there is something to print: command
    # substitution eats the trailing newline, so the bare `%s` that every other
    # block here uses would run the last brew row into the first npm one.
    [ -n "$UPDATES_BREW" ] && printf '%s\n' "$UPDATES_BREW"
    [ -n "$UPDATES_NPM" ] && printf '%s\n' "$UPDATES_NPM"
  fi
  return 0
}

# The question, written once. Three places would otherwise spell it: the prompt
# that waits, the line that does not, and a caller trying to match it.
DOCTOR_UPDATES_QUESTION="Check for tool updates? This asks Homebrew and npm and can take up to 30 seconds. [y/N]"

echo ""
if [ "$DOCTOR_WANT_UPDATES" = "yes" ]; then
  # The answer already given, coming back as a second run. No question, no read.
  _doctor_render_updates
elif _doctor_can_ask; then
  printf '%s ' "$DOCTOR_UPDATES_QUESTION"
  IFS= read -r DOCTOR_UPDATE_ANSWER || DOCTOR_UPDATE_ANSWER=""
  echo ""
  case "$DOCTOR_UPDATE_ANSWER" in
    y|Y|yes|YES|Yes) _doctor_render_updates ;;
  esac
else
  # Not a terminal: nothing is printed. The relaying command (commands/doctor.md)
  # owns the question in that case and asks it once — printing it here too put
  # the same line on the screen twice (Chris 2026-08-22, "the last line is
  # repeated").
  :
fi

exit 0
