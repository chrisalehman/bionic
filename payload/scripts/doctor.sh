#!/bin/bash
# doctor.sh — the read-only diagnosis (epic-17 wave-03 slice S7, spec AC-3).
#
# WHAT THIS FILE OWNS. Nothing factual. Doctor is a RENDERING SURFACE: every
# number, verdict and state below is computed by detect.sh, deps.sh or
# profile.sh and printed here in a shape a person can act on. The design's
# ownership table says so in one word — doctor "diagnoses, never treats" — and
# that word is the whole contract: no prompts, no mutations, no network, one
# pass, exit 0.
#
# EXIT 0, ALWAYS. A diagnosis is not a failure. A machine with eleven absent
# dependencies and a stale permission profile has been diagnosed *successfully*;
# reporting that as a non-zero exit would make every caller treat a working
# doctor as a broken one. The report's content is the signal, never the status.
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
# Executed, never sourced:  bash "${CLAUDE_PLUGIN_ROOT}/scripts/doctor.sh"

set -uo pipefail

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
_doctor_unknown_cause() {  # <mechanism>
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

# ─── The dependency sweep ────────────────────────────────────────────────────
#
# One pass over the table produces three renderings at once — the dependency
# rows, the roster-footprint rows, and the degradation map — because they are
# three views of the same facts and a second pass would be a second chance to
# disagree with the first.

# The installed tree of a plugin-shaped dependency, as the CLI recorded it.
# `installPath` is the registry's own answer to "where did this land", which is
# what makes the roster count a measurement rather than a guess about layout.
_doctor_install_path() {  # <name>
  local name="${1:-}" file path
  file="${BIONIC_INSTALLED_PLUGINS_FILE:-${BIONIC_CLAUDE_HOME:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}}/plugins/installed_plugins.json}"
  [ -f "$file" ] || return 1
  command -v jq >/dev/null 2>&1 || return 1
  path="$(jq -r --arg n "$name" '
      [ (.plugins // {}) | to_entries[]
        | select((.key | split("@")[0]) == $n)
        | .value[0].installPath // empty ] | first // ""' "$file" 2>/dev/null)"
  [ -n "$path" ] || return 1
  echo "$path"
}

# ROSTER FOOTPRINT, the counting method (design-ledger D6). Skill and agent
# METADATA — name plus description — is what loads into every session; the
# bodies are just-in-time. So a dependency's session cost is the number of skill
# and agent entries it contributes, and the layout the CLI installs says exactly
# where those live: one `skills/<slug>/SKILL.md` per skill, one `agents/<name>.md`
# per agent, under the registry's `installPath`. Counting the files IS counting
# the roster lines. Lane-3b dependencies are binaries, packages and MCP
# registrations — no skill or agent metadata, so no roster cost at all.
_doctor_roster_counts() {  # <install-path> -> "<skills> <agents>"
  local root="${1:-}" p skills=0 agents=0
  for p in "$root"/skills/*/SKILL.md; do [ -f "$p" ] && skills=$((skills + 1)); done
  for p in "$root"/agents/*.md;       do [ -f "$p" ] && agents=$((agents + 1)); done
  echo "${skills} ${agents}"
}

DEP_ROWS=""
ROSTER_ROWS=""
DEGRADATION=""
N_PRESENT=0; N_ABSENT=0; N_UNKNOWN=0; N_VIOLATION=0
ROSTER_TOTAL=0; ROSTER_TOTAL_KNOWN=yes
CCSTATUSLINE_STATE="unknown"

while IFS= read -r dep_name; do
  [ -n "$dep_name" ] || continue
  fact="$(detect_dep "$dep_name")" || continue

  lane="${fact#*lane=}";           lane="${lane%% *}"
  present="${fact#*present=}";     present="${present%% *}"
  dep_version="${fact#*version=}"; dep_version="${dep_version%% *}"
  constraint="${fact#*constraint=}"; constraint="${constraint%% *}"
  verdict="${fact##*verdict=}"
  mechanism="$(dep_field "$dep_name" install_fn_or_check)"

  [ "$dep_name" = "ccstatusline" ] && CCSTATUSLINE_STATE="$present"

  DEP_ROWS="${DEP_ROWS}$(printf '  %-5s %-22s %-8s %-11s %-11s %s' \
    "$lane" "$dep_name" "$present" "$dep_version" "$constraint" "$verdict")"$'\n'

  # ── roster footprint ──
  if [ "$lane" != "3a" ]; then
    # No parenthetical per row: the method paragraph above states once why every
    # lane-3b dependency costs nothing, and repeating it twenty times would bury
    # the two rows that carry an actual number.
    ROSTER_ROWS="${ROSTER_ROWS}$(printf '  %-22s %s' "$dep_name" "0")"$'\n'
  elif [ "$present" = "unknown" ]; then
    ROSTER_ROWS="${ROSTER_ROWS}$(printf '  %-22s %-9s %s' \
      "$dep_name" "unknown" "($(_doctor_unknown_cause "$mechanism"))")"$'\n'
    ROSTER_TOTAL_KNOWN=no
  elif [ "$present" = "no" ]; then
    ROSTER_ROWS="${ROSTER_ROWS}$(printf '  %-22s %-9s %s' \
      "$dep_name" "0" "(not installed — contributes nothing this session)")"$'\n'
  else
    install_path="$(_doctor_install_path "$dep_name")" || install_path=""
    if [ -z "$install_path" ] || [ ! -d "$install_path" ]; then
      ROSTER_ROWS="${ROSTER_ROWS}$(printf '  %-22s %-9s %s' \
        "$dep_name" "unknown" "(the registry records no readable installPath for it)")"$'\n'
      ROSTER_TOTAL_KNOWN=no
    else
      counts="$(_doctor_roster_counts "$install_path")"
      n_skills="${counts%% *}"; n_agents="${counts##* }"
      roster_lines=$((n_skills + n_agents))
      ROSTER_ROWS="${ROSTER_ROWS}$(printf '  %-22s %-9s %s' \
        "$dep_name" "$roster_lines" "(${n_skills} skills + ${n_agents} agents)")"$'\n'
      ROSTER_TOTAL=$((ROSTER_TOTAL + roster_lines))
    fi
  fi

  # ── tallies and the degradation map ──
  case "$present" in
    yes)
      N_PRESENT=$((N_PRESENT + 1))
      if [ "$verdict" = "violation" ]; then
        N_VIOLATION=$((N_VIOLATION + 1))
        if [ "$lane" = "3a" ]; then
          DEGRADATION="${DEGRADATION}  ${dep_name} ${dep_version} violates constraint ${constraint} → run /bionic:setup — it wraps the native plugin install, which resolves the version"$'\n'
        else
          DEGRADATION="${DEGRADATION}  ${dep_name} ${dep_version} violates constraint ${constraint} → run /bionic:setup — it reinstalls ${dep_name} at a satisfying version"$'\n'
        fi
      fi
      ;;
    no)
      N_ABSENT=$((N_ABSENT + 1))
      if [ "$lane" = "3a" ]; then
        DEGRADATION="${DEGRADATION}  ${dep_name} is absent (lane 3a) → run /bionic:setup — it wraps the native plugin install"$'\n'
      else
        DEGRADATION="${DEGRADATION}  ${dep_name} is absent (lane 3b) → run /bionic:setup, or accept the just-in-time install offer the next route needing ${dep_name} makes"$'\n'
      fi
      ;;
    *)
      N_UNKNOWN=$((N_UNKNOWN + 1))
      cause="$(_doctor_unknown_cause "$mechanism")"
      if [ "$mechanism" = "pnpm-store" ]; then
        DEGRADATION="${DEGRADATION}  ${dep_name} presence is unknown (${cause}) → no action available; /bionic:setup re-warms the store either way"$'\n'
      else
        DEGRADATION="${DEGRADATION}  ${dep_name} presence is unknown (${cause}) → resolve the cause above, then re-run /bionic:doctor"$'\n'
      fi
      ;;
  esac
done < <(dep_names)

# ─── The report ──────────────────────────────────────────────────────────────

echo "bionic doctor — read-only diagnosis. Nothing on this machine is changed."
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

echo ""
echo "=== TIER STATE ==="
# Labels here are deliberately ASCII: printf pads to a BYTE width, so a label
# carrying a multi-byte dash would be padded three bytes short of its neighbours
# and the column would visibly step.
printf '  %-28s %s\n' "tier 1 (plugin install)" \
  "payload ${PLUGIN_VERSION}, hooks ${PLUGIN_HOOKS}"
printf '  %-28s %s\n' "tier 2 (environment setup)" \
  "${N_PRESENT} dependencies present, ${N_ABSENT} absent, ${N_UNKNOWN} unknown, ${N_VIOLATION} constraint $(_doctor_plural "$N_VIOLATION" violation violations)"
printf '  %-28s %s\n' "half-uninstalled" "$HALF_STATE"

echo ""
echo "=== DEPENDENCIES ==="
echo "  Both lanes. The constraint column is the dep table in scripts/lib/deps.sh —"
echo "  the sole place a dependency's version range is declared — and the verdict is"
echo "  that range judged against what this machine actually has."
echo ""
printf '  %-5s %-22s %-8s %-11s %-11s %s\n' lane name present version constraint verdict
printf '%s' "$DEP_ROWS"

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
echo "  number of roster entries it contributes (design-ledger D6)."
echo "  method: for a plugin-shaped (lane 3a) dependency, roster lines = the count of"
echo "          skills/*/SKILL.md plus agents/*.md under the installPath the CLI"
echo "          recorded in plugins/installed_plugins.json. Lane-3b dependencies are"
echo "          binaries, packages and MCP registrations: no skill or agent metadata,"
echo "          so no roster cost."
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
  echo "  Every dependency is present and within its declared constraint."
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

# Half-uninstalled first: it is the one state /bionic:setup cannot repair,
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
[ "$N_ABSENT" -gt 0 ] && add_setup_reason "install ${N_ABSENT} absent $(_doctor_plural "$N_ABSENT" dependency dependencies)"
[ "$N_VIOLATION" -gt 0 ] && add_setup_reason "repair ${N_VIOLATION} constraint $(_doctor_plural "$N_VIOLATION" violation violations)"
[ "$TODO_STATE" = "no" ] && add_setup_reason "write the CLAUDE_CODE_ENABLE_TODO_TOOLS export"
[ "$LEGACY_STATE" = "yes" ] && add_setup_reason "remove the legacy .zshrc alias block"
case "$LEGACY_HOOK_COUNT" in
  unknown|0) ;;
  *) add_setup_reason "clean ${LEGACY_HOOK_COUNT} legacy-channel managed-hook $(_doctor_plural "$LEGACY_HOOK_COUNT" entry entries) out of settings.json" ;;
esac
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

exit 0
