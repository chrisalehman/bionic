#!/bin/bash
# jit.sh — the route-facing degradation contract (epic-17 wave-03, spec AC-5).
#
# WHAT THIS FILE OWNS. The two functions a route calls when it needs a
# `when-needed` dependency it cannot assume is there: "is it present"
# (jit_check) and "offer to install it, on consent, right now" (jit_offer).
# Both lean entirely on
# deps.sh's own table and its ONE mutating entry point, install_dep. jit_offer
# is not a second installer: it calls install_dep BY NAME, so a route's JIT
# offer and setup's own loop over the rows bionic installs itself always reach
# the identical function (ownership table, wave-03 spec §Design, "per-dep install" row) —
# tests/jit.test.sh proves that dynamically, by overriding `install_dep` after
# sourcing this file and watching jit_offer's "yes" path land in the override.
#
# WHAT IT DOES NOT OWN. Presence facts (deps.sh's check_dep / detect.sh's
# detect_dep), the dependency table (deps.sh), or how a route explains its own
# capability in prose. A route names its own <capability>/<what-changes> text
# in the call to jit_offer (see below) — jit.sh has no per-dependency opinion
# on wording, because it has no way to know which capability a given caller is
# gating on. jit_offer's signature is therefore four positional args, not the
# single <dep-name> the spec's ownership-table row shorthands it as: the
# contracted degradation line ("<route> continues without <capability>: <what
# changes>") names three things only the calling route can supply. Recorded
# as this slice's discretionary resolution — see the wave report.
#
# CONSENT. jit_offer asks AT MOST ONE question, and it is install_dep's own —
# jit.sh adds no second prompt and no dry-run seam. There is no assume-yes
# knob here either: the "consent per event, never silent, never unattended"
# rule binds through the function jit_offer delegates to. The one row it asks
# NOTHING about is the native-kind one, which this file cannot install at all;
# see the note above jit_offer.
#
# ROOTS. jit.sh reads no paths of its own — every root deps.sh's functions
# touch is already overridable there, and jit.sh calls them through their own
# public names rather than re-deriving anything.
#
# Sourced, never executed:  . "${CLAUDE_PLUGIN_ROOT}/scripts/lib/jit.sh"

_jit_self_dir() {
  local self="${BASH_SOURCE[0]}"
  case "$self" in */*) echo "${self%/*}" ;; *) echo "." ;; esac
}

if ! declare -F check_dep >/dev/null 2>&1; then
  # shellcheck source=/dev/null
  . "$(cd "$(_jit_self_dir)" && pwd -P)/deps.sh"
fi

# The catalog a native-kind row installs from used to be spelled here, because
# this file composed the install command itself. `install_plugin_native` composes
# it now and reads `BIONIC_DEP_MARKETPLACE` at call time exactly as this did, so
# a second copy of the default would be a second opinion about which catalog a
# plugin comes from — and the one that drifted would be the one nobody ran.

# ─── jit_check ───────────────────────────────────────────────────────────

# One line naming what would resolve an absence, reusing deps.sh's own
# install plan (`_dep_install_argv`) so the named fix can never drift from
# what a "yes" answer to jit_offer would actually run.
_jit_fix_line() {  # <dep-name>
  local name="$1" mech line
  local -a argv=()
  mech="$(dep_field "$name" install_fn_or_check 2>/dev/null)" || { echo "see /bionic:setup"; return 0; }
  if [ "$mech" = "statusline" ]; then
    echo "record 'npx $(_dep_locator_target "$(dep_field "$name" source_url)")' as the statusline"
    return 0
  fi
  # A native row has no argv of bionic's, but it does have a command the USER can
  # run — which is what this line is for. Before epic-18 T4 every native row fell
  # through to "see /bionic:setup", a redirection back to the step that just
  # failed rather than the one thing that would fix it.
  if [ "$mech" = "native" ]; then
    echo "claude plugin install ${name}@$(dep_marketplace "$name") --scope user"
    return 0
  fi
  while IFS= read -r line; do argv+=("$line"); done < <(_dep_install_argv "$name" 2>/dev/null) || true
  if [ "${#argv[@]}" -gt 0 ]; then
    printf '%s\n' "${argv[*]}"
  else
    echo "see /bionic:setup"
  fi
}

# <dep-name> -> exit 0 present, exit 1 absent. A presence the underlying probe
# could not read (`unknown` — no presence surface, or a missing prober) is
# treated as absent here: a route deciding whether to OFFER an install needs a
# plain yes/no, and offering on an unreadable presence is the safe direction —
# unlike doctor's report, which is honest that "unknown" is its own value.
#
# Prints the one-line named fix on the absent arm only; prints nothing when
# present, so a caller can pipe straight to a message without filtering.
jit_check() {  # <dep-name>
  local name="${1:-}" raw present
  raw="$(check_dep "$name")" || return 1
  present="${raw#present=}"; present="${present%%|*}"
  [ "$present" = "yes" ] && return 0
  echo "  ${name} is not installed — fix: $(_jit_fix_line "$name")"
  return 1
}

# ─── jit_offer ───────────────────────────────────────────────────────────

# <dep-name> <route> <capability> <what-changes-on-decline>
#
# States the offer in one line, then hands off entirely to install_dep: its
# own plan-then-consent prompt IS the one question this function asks. A
# "yes" that installs returns install_dep's own exit code unchanged — no
# translation, no swallowed failure. Anything else — an explicit "no", empty
# stdin, or a real install failure after consent — prints the contracted
# degradation line and returns non-zero. Nothing goes to stderr on the
# decline path: install_dep's own decline message is stdout-only
# ("declined — <name> stays absent."), and jit_offer adds no output of its
# own there beyond the degradation line, which is also stdout.
#
# ONE ROW GOES THROUGH THE OTHER INSTALLER (wave-06 D-B/AC-11, plan
# A-4.S4.4-RULING). `impeccable` is `when-needed` AND `native`: the moment to
# install it is the moment the design route asks for it, but the thing that
# installs a plugin is the CLI, and `install_dep` REFUSES every native row by
# design — a second installer for a natively-installed plugin is the kludge the
# ownership table exists to prevent. Handing it to install_dep anyway would print
# deps.sh's refusal at a user who did nothing wrong.
#
# The first cut of this branch printed the command and asked nothing, which
# narrowed AC-11's "one question at the moment of need" for exactly one row. The
# fix went to the layer it lives instead: deps.sh now owns `install_plugin_native`
# — one consent question, then the CLI's install, then the one line saying when
# it takes effect — and setup's first step calls the same function. So this file
# is still not a second installer; it is a second CALLER of the one that exists,
# which is precisely what it already is for install_dep.
#
# AND IT STILL RETURNS NON-ZERO, EVEN ON A SUCCESSFUL INSTALL. The plugin is on
# the machine; it is not in the session that asked for it until the plugins are
# re-read. `jit_offer`'s return answers "can this route use the capability NOW",
# and for a native row installed this second the honest answer is no. The
# contracted degradation line prints for the same reason: the route has to know
# what this run does without it.
jit_offer() {  # <dep-name> <route> <capability> <what-changes>
  local name="${1:-}" route="${2:-}" capability="${3:-}" degrade="${4:-}"
  echo "  ${route}: ${capability} needs ${name}, which is not installed."
  if [ "$(dep_field "$name" kind 2>/dev/null)" = "native" ]; then
    install_plugin_native "$name"
    echo "  ${route} continues without ${capability}: ${degrade}"
    return 1
  fi
  if install_dep "$name"; then
    return 0
  fi
  echo "  ${route} continues without ${capability}: ${degrade}"
  return 1
}
