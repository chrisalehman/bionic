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
while [ $# -gt 0 ]; do
  case "$1" in
    --updates) DOCTOR_WANT_UPDATES=yes ;;
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
_doctor_unknown_cause() {  # <kind> — the install mechanism the table names
  case "${1:-}" in
    pnpm-store) echo "the pnpm content-addressable store is a cache, not an install surface" ;;
    native)
      if command -v jq >/dev/null 2>&1; then echo "the plugin registry could not be parsed"
      else echo "jq is not on PATH, so the plugin registry cannot be read"; fi ;;
    npm-global) echo "npm is not on PATH" ;;
    mcp-server) echo "the claude CLI is not on PATH" ;;
    statusline)
      if command -v jq >/dev/null 2>&1; then echo "settings.json could not be parsed"
      else echo "jq is not on PATH, so settings.json cannot be read"; fi ;;
    *)          echo "this mechanism exposes no presence surface" ;;
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
ROSTER_ROWS=""
DEGRADATION=""
DEP_VERSIONS=""
N_PRESENT=0; N_ABSENT=0; N_UNKNOWN=0; N_VIOLATION=0
N_ABSENT_ACTIONABLE=0; N_ABSENT_WHEN_NEEDED=0
ROSTER_TOTAL=0; ROSTER_TOTAL_KNOWN=yes
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

  DEP_ROWS="${DEP_ROWS}$(printf '  %-11s %-22s %-8s %-11s %-11s %s' \
    "$dep_class" "$dep_name" "$present" "$dep_version" "$constraint" "$verdict")"$'\n'

  # ── roster footprint ──
  if [ "$kind" != "native" ]; then
    # No parenthetical per row: the method paragraph above states once why a
    # dependency that is not plugin-shaped costs nothing, and repeating it twenty
    # times would bury the rows that carry an actual number.
    ROSTER_ROWS="${ROSTER_ROWS}$(printf '  %-22s %s' "$dep_name" "0")"$'\n'
  elif [ "$present" = "unknown" ]; then
    ROSTER_ROWS="${ROSTER_ROWS}$(printf '  %-22s %-9s %s' \
      "$dep_name" "unknown" "($(_doctor_unknown_cause "$kind"))")"$'\n'
    ROSTER_TOTAL_KNOWN=no
  elif [ "$present" = "no" ]; then
    ROSTER_ROWS="${ROSTER_ROWS}$(printf '  %-22s %-9s %s' \
      "$dep_name" "0" "(not installed — contributes nothing this session)")"$'\n'
  else
    install_path="$(detect_plugin_install_path "$dep_name")" || install_path=""
    if [ -z "$install_path" ] || [ ! -d "$install_path" ]; then
      ROSTER_ROWS="${ROSTER_ROWS}$(printf '  %-22s %-9s %s' \
        "$dep_name" "unknown" "(the registry records no readable installPath for it)")"$'\n'
      ROSTER_TOTAL_KNOWN=no
    else
      counts="$(_doctor_roster_counts "$install_path")"
      n_skills="${counts%% *}"; n_agents="${counts##* }"
      roster_lines=$((n_skills + n_agents))
      ROSTER_ROWS="${ROSTER_ROWS}$(printf '  %-22s %-9s %s' \
        "$dep_name" "$roster_lines" \
        "(${n_skills} $(_doctor_plural "$n_skills" skill skills) + ${n_agents} $(_doctor_plural "$n_agents" agent agents))")"$'\n'
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
  case "$present" in
    yes)
      N_PRESENT=$((N_PRESENT + 1))
      if [ "$verdict" = "violation" ]; then
        N_VIOLATION=$((N_VIOLATION + 1))
        case "$dep_class" in
          core)
            DEGRADATION="${DEGRADATION}  ${dep_name} ${dep_version} violates constraint ${constraint} → run /bionic:setup — it wraps the native plugin install, which resolves the version"$'\n' ;;
          when-needed)
            DEGRADATION="${DEGRADATION}  ${dep_name} ${dep_version} violates constraint ${constraint} → the next route that needs ${dep_name} offers to install a version that satisfies it"$'\n' ;;
          *)
            DEGRADATION="${DEGRADATION}  ${dep_name} ${dep_version} violates constraint ${constraint} → run /bionic:setup — it reinstalls ${dep_name} at a satisfying version"$'\n' ;;
        esac
      fi
      ;;
    no)
      N_ABSENT=$((N_ABSENT + 1))
      case "$dep_class" in
        when-needed)
          N_ABSENT_WHEN_NEEDED=$((N_ABSENT_WHEN_NEEDED + 1)) ;;
        core)
          N_ABSENT_ACTIONABLE=$((N_ABSENT_ACTIONABLE + 1))
          DEGRADATION="${DEGRADATION}  ${dep_name} is absent → run /bionic:setup — it wraps the native plugin install"$'\n' ;;
        *)
          N_ABSENT_ACTIONABLE=$((N_ABSENT_ACTIONABLE + 1))
          DEGRADATION="${DEGRADATION}  ${dep_name} is absent → run /bionic:setup — it offers to install ${dep_name}"$'\n' ;;
      esac
      ;;
    *)
      N_UNKNOWN=$((N_UNKNOWN + 1))
      cause="$(_doctor_unknown_cause "$kind")"
      # KEYED ON THE CLASS, WHICH IS WHAT THE SENTENCE IS ABOUT (six-axis review
      # C-2). This branch used to key on the mechanism — `pnpm-store` rows were
      # told "/bionic:setup re-warms the store either way" — and that was true
      # only while setup walked every non-native row. Setup now asks about
      # `core|basic|extra` and AC-11 makes a when-needed tool nobody's to install
      # until a route needs it, so the old clause named a command that would not
      # touch the row. A when-needed unknown has the same non-action as a
      # when-needed absence, and for the same reason.
      case "$dep_class" in
        when-needed)
          DEGRADATION="${DEGRADATION}  ${dep_name} presence is unknown (${cause}) → no action needed; ${dep_name} is installed the first time a workflow needs it"$'\n' ;;
        *)
          DEGRADATION="${DEGRADATION}  ${dep_name} presence is unknown (${cause}) → resolve the cause above, then re-run /bionic:doctor"$'\n' ;;
      esac
      ;;
  esac
done < <(dep_names)

# ─── The report ──────────────────────────────────────────────────────────────

echo "bionic doctor — read-only diagnosis. Nothing on this machine is changed."
echo ""
# WHY THIS SECTION LEADS (AC-13, ratified D-D). Every section below describes a
# payload on disk. Whether the CLI actually LOADED that payload is a separate
# question with a separate answer, and when the answer is no, everything under
# this line describes something the session is not running — commands that
# silently do nothing, hooks that never fire, a machine that reads healthy by
# every other measure. W5 measured exactly that machine.
echo "=== LOAD STATE ==="
case "$LOAD_STATE" in
  loaded)
    printf '  %-19s %s\n' "bionic" "loaded — the CLI reports it enabled" ;;
  failed)
    printf '  %-19s %s\n' "bionic" "failed to load — bionic's commands do nothing until this is resolved"
    # VERBATIM, because the CLI's own sentence is the only one that names WHICH
    # dependency, and a paraphrase is how a user reinstalls the wrong thing.
    printf '  %-19s %s\n' "reported error" "$LOAD_ERROR"
    printf '  %-19s %s\n' "fix" "install what the error names, then start a new session — or reinstall bionic: claude plugin install ${BIONIC_PLUGIN_ID}" ;;
  absent)
    printf '  %-19s %s\n' "bionic" "not installed — the CLI's plugin list does not name it"
    printf '  %-19s %s\n' "fix" "claude plugin install ${BIONIC_PLUGIN_ID}" ;;
  *)
    printf '  %-19s %s\n' "bionic" "unknown — ${LOAD_CAUSE}" ;;
esac

echo ""
echo "=== PLUGIN INTEGRITY ==="
printf '  %-19s %s\n' "payload version" "$PLUGIN_VERSION"
case "$PLUGIN_HOOKS" in
  ok)       printf '  %-19s %s\n' "hooks" "ok — every hooks.json command resolves to a file on disk" ;;
  degraded) printf '  %-19s %s\n' "hooks" "degraded — a hooks.json command names a script that is not on disk" ;;
  absent)   printf '  %-19s %s\n' "hooks" "absent — the payload carries no hooks/hooks.json" ;;
  *)        printf '  %-19s %s\n' "hooks" "$PLUGIN_HOOKS" ;;
esac
# ONE LINE, AND IT REPORTS RATHER THAN POLICES (spec AC-4). The six role files
# are instructions subagents obey, so a hand-edit there changes behaviour with
# no other symptom — worth a line. It is not worth a verdict: editing your own
# installed files is allowed, so the line names the state, names the files, and
# names the undo in the same breath. Deliberately absent: any exit-code effect,
# any repair, and any second mention in the SUMMARY, whose action lines would
# turn "you changed something" into "you should change it back".
case "$AGENT_STATE" in
  stock)
    printf '  %-19s %s\n' "agent files" \
      "stock — all ${AGENT_TOTAL} match the checksums this payload shipped" ;;
  modified)
    printf '  %-19s %s\n' "agent files" \
      "${AGENT_MODIFIED} of ${AGENT_TOTAL} modified locally (${AGENT_NAMES//,/, }) — may be intentional; reinstall restores stock" ;;
  *)
    printf '  %-19s %s\n' "agent files" "unknown — ${AGENT_CAUSE}" ;;
esac
printf '  %-19s %s\n' "payload root" "$(_detect_plugin_root)"

# WHICH COMMIT IS INSTALLED, against which commit this tree is on. The label says exactly
# that: it read `registry sha` until epic-17 W6 S9a, which is the name of the FILE the fact
# comes from rather than the name of the fact, and a user who never asked about a registry
# reads it as git internals leaking into a report meant for them (walk finding W-3). Same
# fact, same states, product word.
#
# WHICH COMMIT IS INSTALLED, against which commit this tree is on. ONE LINE, AND IT REPORTS
# RATHER THAN POLICES — the agent-files posture, and deliberately: an install behind the tip
# is what a developer machine looks like between any two commits, so a SUMMARY action line
# would nag on every one of them. The action rides inline on the one state that has one.
#
# `unknown` is the ORDINARY answer here and carries no apology: installed from the public
# feed, with no checkout of this repo under the cwd, the question genuinely has no answer.
_doctor_sha12() { printf '%.12s' "${1:-}"; }
case "$REG_SHA_STATE" in
  match)
    printf '  %-19s %s\n' "installed commit" \
      "match — the installed build is this tree's HEAD ($(_doctor_sha12 "$REG_SHA_REG"))" ;;
  lag)
    printf '  %-19s %s\n' "installed commit" \
      "installed at $(_doctor_sha12 "$REG_SHA_REG"), this tree is $(_doctor_sha12 "$REG_SHA_REPO") — the install is behind; re-run: claude plugin install bionic@bionic" ;;
  not-in-repo)
    printf '  %-19s %s\n' "installed commit" \
      "installed at $(_doctor_sha12 "$REG_SHA_REG") — not a commit in this repository, so this tree is not what is running" ;;
  *)
    printf '  %-19s %s\n' "installed commit" "unknown — ${REG_SHA_CAUSE}" ;;
esac

echo ""
echo "=== TIER STATE ==="
# Labels here are deliberately ASCII: printf pads to a BYTE width, so a label
# carrying a multi-byte dash would be padded three bytes short of its neighbours
# and the column would visibly step.
printf '  %-28s %s\n' "tier 1 (plugin install)" \
  "payload ${PLUGIN_VERSION}, hooks ${PLUGIN_HOOKS}"
printf '  %-28s %s\n' "tier 2 (environment setup)" \
  "${N_PRESENT} dependencies present, ${N_ABSENT} absent, ${N_UNKNOWN} unknown, ${N_VIOLATION} constraint $(_doctor_plural "$N_VIOLATION" violation violations)"
# The absent count is the honest total; this line is what stops a reader acting
# on it. A tool that installs itself the first time a route needs it is not
# missing from a machine that has not run that route yet.
if [ "$N_ABSENT_WHEN_NEEDED" -gt 0 ]; then
  printf '  %-28s %s\n' "" \
    "${N_ABSENT_WHEN_NEEDED} of the absent $(_doctor_plural "$N_ABSENT_WHEN_NEEDED" "installs itself" "install themselves") the first time a route needs $(_doctor_plural "$N_ABSENT_WHEN_NEEDED" it them)"
fi
printf '  %-28s %s\n' "half-uninstalled" "$HALF_STATE"

echo ""
echo "=== DEPENDENCIES ==="
echo "  The class column says WHEN bionic installs a tool: core with the plugin,"
echo "  basic at setup, when-needed the first time a route asks for it, extra only"
echo "  if you said yes. The constraint column is the table in scripts/lib/deps.sh —"
echo "  the sole place a version range is declared — and the verdict is that range"
echo "  judged against what this machine actually has."
echo ""
printf '  %-11s %-22s %-8s %-11s %-11s %s\n' class name present version constraint verdict
printf '%s' "$DEP_ROWS"

# ─── Two catalogs, one name ──────────────────────────────────────────────────
#
# SILENT DUPLICATION IS THE DEFECT (AC-9). Nothing stops a machine holding the
# same plugin from two catalogs at once, and which copy a session loads is then a
# coin flip nobody saw tossed. REPORTED, NOT RESOLVED, and not nagged about
# either: coexistence can be a deliberate choice, so the row hands over the
# consolidation command and stops rather than raising a SUMMARY action.
echo ""
echo "=== DUPLICATES ==="
if [ -z "$DUP_LINES" ]; then
  echo "  none — every plugin here comes from exactly one catalog."
else
  echo "  The same name installed from two catalogs. Which copy a session loads is"
  echo "  not bionic's decision — consolidate, or keep both deliberately."
  echo ""
  while IFS= read -r _dup; do
    [ -n "$_dup" ] || continue
    _dup_name="${_dup#dup=}";  _dup_name="${_dup_name%% *}"
    _dup_ids="${_dup#*ids=}";  _dup_ids="${_dup_ids%% *}"
    _dup_fix="${_dup#*fix=}"
    if [ "$_dup_name" = "unknown" ]; then
      # A registry that could not be read has not been read clean. Silence here
      # would be a claim of no duplicates that nobody earned.
      _dup_cause="${_dup##*cause=}"
      printf '  %-22s %s\n' "unknown" "— ${_dup_cause}"
    else
      _dup_fix="${_dup_fix%% cause=*}"
      printf '  %-22s %s\n' "$_dup_name" "installed from ${_dup_ids//,/, }"
      printf '  %-22s %s\n' "" "→ ${_dup_fix}"
    fi
  done <<< "$DUP_LINES"
fi

echo ""
echo "=== ENVIRONMENT ==="
printf '  %-38s %s\n' "CLAUDE_CODE_ENABLE_TODO_TOOLS export" "$(_doctor_word "$TODO_STATE")"
printf '  %-38s %s\n' "legacy .zshrc alias block" "$(_doctor_word "$LEGACY_STATE")"
if [ "$LEGACY_HOOK_COUNT" = "unknown" ]; then
  printf '  %-38s %s\n' "legacy-channel managed-hook entries" \
    "unknown — jq is not on PATH, so settings.json cannot be read"
else
  printf '  %-38s %s\n' "legacy-channel managed-hook entries" "$LEGACY_HOOK_COUNT"
fi
# THE SKILL COPY IS NOT INERT, and that is the whole reason it gets a line and an action
# while the hook files below get only a line. The retired installer rendered canonical-sdlc
# into the CLI's own skills directory, and W5 (4/6) measured eleven hook registrations in
# that copy's frontmatter — every one spelled for the pre-plugin hooks directory. A session
# that loads it arms the same walls twice, through the channel the cutover retired, and
# until now nothing in this report said so: doctor could call a machine clean while it was
# running two of everything.
if [ "$SKILL_COPY_STATE" = "yes" ]; then
  printf '  %-38s %s\n' "legacy installed skill copy" \
    "${SKILL_COPY_PATH} — a second canonical-sdlc, arming the same walls again"
else
  printf '  %-38s %s\n' "legacy installed skill copy" \
    "none — the skill ships in the payload"
fi
# THE HOOK FILES ARE THE OTHER HALF OF A QUESTION THIS REPORT ONLY ANSWERED HALFWAY. The
# line above counts REGISTRATIONS in settings.json; the installer also left the scripts
# themselves in the CLI's hooks directory, and a machine cleaned of every registration still
# has them. That machine and a clean one read identically here until now — and the person
# reading is the one who can see the directory with `ls`.
#
# REPORTED, NEVER PRESCRIBED — the same contract the agent-copies line keeps. With the
# registrations gone these files run nothing: they are disk, not behaviour, and turning
# "this exists" into "you should delete it" on an otherwise-fine machine is how a diagnosis
# turns into nagging. The close-out that removes them is a decision, not a default.
if [ "$HOOK_FILES_COUNT" = "unknown" ]; then
  printf '  %-38s %s\n' "legacy installed hook files" "unknown — ${HOOK_FILES_CAUSE}"
elif [ "$HOOK_FILES_COUNT" = "0" ]; then
  printf '  %-38s %s\n' "legacy installed hook files" \
    "none — hooks run from the payload"
else
  # The COUNT, and where to look — not the roster. A machine that never ran a cleanup
  # carries sixteen of these, and sixteen filenames on one line is a paragraph nobody
  # reads. The agent-copies line above names its files because it names only the ones that
  # DRIFTED, which is a short and actionable set; here every leftover is the same leftover
  # and the number is the whole finding. The names stay in the fact line for a caller that
  # wants them.
  printf '  %-38s %s\n' "legacy installed hook files" \
    "${HOOK_FILES_COUNT} left by the retired installer, inert — see ${SKILL_COPY_PATH%/skills/*}/hooks"
fi
# THE PLUGIN-ERA TRUTH LEADS, because it is the half a reader needs whichever
# state the machine is in: role files ship in the PAYLOAD, and anything in the
# CLI's own agents directory is what the retired installer left. Those copies
# are what a session actually loads, so a machine can be running dispatch
# instructions two plugin updates old with no other symptom.
#
# READ-ONLY, AND NO ACTION LINE — the same contract the agent-integrity line
# keeps. /bionic:setup owns the offer to remove a legacy copy, under consent;
# doctor's job is to say the directory is there. A SUMMARY entry here would
# turn "this exists" into "you should delete it" on a machine that is otherwise
# fine.
case "$INST_AGENT_STATE" in
  absent)
    printf '  %-38s %s\n' "installed agent role files" \
      "none — role files ship in the payload" ;;
  present)
    if [ "$INST_AGENT_DRIFT" = "0" ]; then
      printf '  %-38s %s\n' "installed agent role files" \
        "${INST_AGENT_TOTAL} legacy copies, none differing from the payload (the payload is what ships)" ;
    else
      printf '  %-38s %s\n' "installed agent role files" \
        "${INST_AGENT_TOTAL} legacy copies, ${INST_AGENT_DRIFT} differing from the payload (${INST_AGENT_NAMES//,/, }) — the payload is what ships" ;
    fi ;;
  *)
    printf '  %-38s %s\n' "installed agent role files" "unknown — ${INST_AGENT_CAUSE}" ;;
esac
if [ "$CCSTATUSLINE_STATE" = "unknown" ]; then
  printf '  %-38s %s\n' "ccstatusline statusline" \
    "unknown — $(_doctor_unknown_cause statusline)"
else
  printf '  %-38s %s\n' "ccstatusline statusline" "$(_doctor_word "$CCSTATUSLINE_STATE")"
fi

echo ""
echo "=== PERMISSION PROFILE ==="
echo "  Three-way: what the payload SHIPS, what this machine has APPLIED, and"
echo "  everything in permissions.allow OUTSIDE bionic's marker block."
echo ""
printf '  %-26s %s\n' "shipped template version" "$TEMPLATE_VERSION"
if [ "$PROFILE_APPLIED" = "yes" ]; then
  printf '  %-26s %s\n' "applied block version" "$PROFILE_VERSION"
else
  printf '  %-26s %s\n' "applied block version" "none — no bionic block is applied"
fi
case "$PROFILE_VERDICT" in
  identical) printf '  %-26s %s\n' "render diff" "identical — the applied block matches a fresh render" ;;
  stale)     printf '  %-26s %s\n' "render diff" "stale — the applied block differs from a fresh render" ;;
  absent)    printf '  %-26s %s\n' "render diff" "absent — there is nothing applied to compare" ;;
  *)         printf '  %-26s %s\n' "render diff" "unknown — jq is not on PATH, so the applied block cannot be compared" ;;
esac
if [ "$PROFILE_ACCRETION" = "unknown" ]; then
  printf '  %-26s %s\n' "accretion outside block" \
    "unknown — jq is not on PATH, so settings.json cannot be counted"
else
  printf '  %-26s %s\n' "accretion outside block" \
    "${PROFILE_ACCRETION} $(_doctor_plural "$PROFILE_ACCRETION" rule rules) this machine owns"
fi

echo ""
echo "=== ROSTER FOOTPRINT ==="
echo "  Skill and agent METADATA — name plus description — loads into every session;"
echo "  bodies are just-in-time. A dependency's standing session cost is therefore the"
echo "  number of roster entries it contributes."
echo "  method: for a plugin-shaped dependency, roster lines = the count of"
echo "          skills/*/SKILL.md plus agents/*.md under the installPath the CLI"
echo "          recorded for it. Everything else — binaries, packages, MCP"
echo "          registrations — carries no skill or agent metadata, so it costs"
echo "          nothing."
echo ""
printf '%s' "$ROSTER_ROWS"
if [ "$ROSTER_TOTAL_KNOWN" = "yes" ]; then
  printf '  %-22s %-9s %s\n' "total" "$ROSTER_TOTAL" "roster lines contributed by dependencies"
else
  printf '  %-22s %-9s %s\n' "total" "≥${ROSTER_TOTAL}" "roster lines (some counts unknown — see the causes above)"
fi

echo ""
echo "=== DEGRADATION MAP ==="
if [ -z "$DEGRADATION" ]; then
  # Not "every dependency is present" — on a correct machine some are absent on
  # purpose, and the tier line above has already said how many and why.
  echo "  Nothing is degraded — every dependency this machine needs now is present"
  echo "  and within its declared constraint."
else
  printf '%s' "$DEGRADATION"
fi

# ─── The summary ─────────────────────────────────────────────────────────────
#
# Action lines and nothing else. Facts live in the sections above; a summary
# that restates them is a second report, and the reader stops trusting either.

echo ""
echo "=== SUMMARY ==="

ACTED=no

# LOAD STATE FIRST, for the reason its section leads: on a machine where the
# plugin did not load, every other action line below is advice about a payload
# nothing is running. `unknown` earns no line — nobody can act on "I could not
# tell", and the section already named why.
case "$LOAD_STATE" in
  failed)
    echo "  → bionic is installed but the CLI refused to load it, so its commands do nothing."
    echo "      The error above names what is missing; install that, then start a new session."
    ACTED=yes ;;
  absent)
    echo "  → bionic is not installed for this CLI — install it with:"
    echo "      claude plugin install ${BIONIC_PLUGIN_ID}"
    ACTED=yes ;;
esac

# Half-uninstalled next: it is the one state /bionic:setup cannot repair,
# because the command surface itself is gone. The curl door is the fix (D5a —
# the remover must not depend on the thing it removes).
if [ "$HALF_STATE" = "yes" ]; then
  echo "  → this machine is half-uninstalled: bionic is no longer registered with the CLI,"
  echo "      but its footprint is still here. Finish the removal with:"
  # The `set -o pipefail` wrapper is not decoration. `curl … | bash` reports
  # BASH's status, and bash handed an empty stream exits 0 — so a fetch that
  # 404s (a moved script, no network, a private repo) leaves the user with a
  # command that looked like it worked and removed nothing. The wrapper is a
  # subshell, so it fixes the status without touching the options of the shell
  # the user pasted it into. `-S` inside `-fsSL` is what puts curl's own error
  # on the terminal; the wrapper is what stops the pipe from swallowing it.
  echo "      bash -c 'set -o pipefail; curl -fsSL ${BIONIC_REMOVE_RAW_URL} | bash'"
  ACTED=yes
fi

# jq next: it gates several of the facts above, so acting on anything else while
# the report is partly unreadable is acting on half a diagnosis.
if [ "$HAVE_JQ" = "no" ]; then
  echo "  → install jq, then re-run /bionic:doctor — without it several facts above read"
  echo "      \"unknown\" rather than a value (/bionic:setup installs jq)."
  ACTED=yes
fi

# One setup action carrying every reason it would repair. /bionic:setup is
# idempotent, so a user with five problems runs one command, not five.
SETUP_REASONS=""
add_setup_reason() {
  if [ -z "$SETUP_REASONS" ]; then SETUP_REASONS="$1"; else SETUP_REASONS="${SETUP_REASONS}, $1"; fi
}
# The ACTIONABLE absences, not every absence: a when-needed tool is absent by
# design until a route asks for it, and setup would not install it if it ran.
[ "$N_ABSENT_ACTIONABLE" -gt 0 ] && add_setup_reason "install ${N_ABSENT_ACTIONABLE} absent $(_doctor_plural "$N_ABSENT_ACTIONABLE" dependency dependencies)"
[ "$N_VIOLATION" -gt 0 ] && add_setup_reason "repair ${N_VIOLATION} constraint $(_doctor_plural "$N_VIOLATION" violation violations)"
[ "$TODO_STATE" = "no" ] && add_setup_reason "write the CLAUDE_CODE_ENABLE_TODO_TOOLS export"
[ "$LEGACY_STATE" = "yes" ] && add_setup_reason "remove the legacy .zshrc alias block"
case "$LEGACY_HOOK_COUNT" in
  unknown|0) ;;
  *) add_setup_reason "clean ${LEGACY_HOOK_COUNT} legacy-channel managed-hook $(_doctor_plural "$LEGACY_HOOK_COUNT" entry entries) out of settings.json" ;;
esac
# The skill copy, and NOT the hook files beside it. Setup step 7 owns the consented removal,
# so there is a real thing to offer; and unlike the files, this copy is doing something —
# arming eleven registrations a second time. The asymmetry is the point, and
# tests/doctor.test.sh Group 14 pins it from the other side with a machine whose only
# leftover is hook files and whose summary still reads "nothing to do".
[ "$SKILL_COPY_STATE" = "yes" ] && add_setup_reason "remove the legacy skill copy at ${SKILL_COPY_PATH}"
if [ -n "$SETUP_REASONS" ]; then
  echo "  → run /bionic:setup — it would ${SETUP_REASONS}."
  ACTED=yes
fi

# The permission profile is its own action: it is repaired by the same command,
# but the reason is a state a user should see named rather than folded into a
# list of dependency counts.
if [ "$PROFILE_VERDICT" = "stale" ]; then
  echo "  → the applied permission profile is stale — it was rendered for a different plugin"
  echo "      path or an older rule set. Re-render it by running /bionic:setup."
  ACTED=yes
elif [ "$PROFILE_APPLIED" = "no" ] && [ "$PROFILE_VERDICT" = "absent" ]; then
  echo "  → no permission profile is applied — run /bionic:setup to apply it under consent."
  ACTED=yes
fi

if [ "$PLUGIN_HOOKS" = "degraded" ] || [ "$PLUGIN_HOOKS" = "absent" ]; then
  echo "  → the payload's hook wiring is ${PLUGIN_HOOKS} — reinstall the plugin"
  echo "      (\`claude plugin install bionic@bionic\`), then re-run /bionic:doctor."
  ACTED=yes
fi

if [ "$ACTED" = "no" ]; then
  echo "  → nothing to do — this machine is fully set up."
fi

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
  # Printed, not asked. Whoever is relaying this report can put the question to
  # the person who can answer it and come back with `--updates`; the line itself
  # says nothing about why nobody was waited for.
  printf '%s\n' "$DOCTOR_UPDATES_QUESTION"
fi

exit 0
