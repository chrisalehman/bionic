# payload/scripts/lib/run.sh — ONE READER FOR "is there a run to protect".
#
# WHAT IT OWNS (L-RUN, wave-bionic-1.4.0-update, spec AC-8; design-ledger S1). Three pure
# functions of disk, no writes:
#   docs_root <root>   -> <root>/<docs-root from .bionic/config.yaml, default .bionic/docs>
#   active_plan <root> -> the newest *.md (by mtime) under <docs_root>/plans (depth <= 2)
#                         and <docs_root>/incidents (depth <= 2) that carries a flush-left
#                         `## SDLC State` heading; exit 1 and silent if none.
#   active_run <root>  -> exit 0 + the plan path iff active_plan exists AND its flush-left
#                         `current:` value is 0-8, or 9 with no `- Step 9:` line carrying
#                         `delivered:`, or a task-scale `current: T<n>` — AND the plan's own
#                         frontmatter carries no `abandoned:` line; else exit 1, silent.
#
# WHY A DEDICATED FUNCTION (design-ledger S1, rejecting a time-bounded or stamp-keyed
# "active"). A run stays active until CLOSED (current: 9 with delivered:) or ABANDONED
# (frontmatter abandoned:) explicitly — never by a clock or a day-N silent disarm, because
# the thing walls check must be the thing that can arm them. Every always-on hook (ADOPT,
# Batch 1) calls `active_run "$ROOT"` and does its own work only when it succeeds.
#
# DELIBERATELY SIMPLER than hooks/canonical-sdlc-evidence-gate.sh's plan search (read for
# shape, not copied): no fence-awareness, no misplacement sweep, no task-ledger validation.
# Those exist there to keep a COMMIT gate from mis-firing on a documentation example; this
# predicate answers a narrower question for a WALL that fails open on any doubt, so a false
# "active" here costs nothing a fail-open hook cannot already absorb, and a false "inactive"
# is caught the same way every hook's own always-on fixture catches it.
#
# BASH 3.2. No associative arrays, no `${var^^}`, no `mapfile`.
#
# FUNCTIONS ONLY — sourcing this file executes no top-level command and prints nothing.
#
# [WALL: tests/run-predicate.test.sh]

# _run_lines <file> -> the file with its line endings TRANSLATED to \n, never deleted.
# A trailing \r is stripped from each record (CRLF) and any remaining lone \r becomes a
# real newline (classic-Mac CR-only). Every read in this file is line-anchored, so it
# must see real newlines: `tr -d '\r'` would collapse a CR-only plan to one line, every
# match would miss, and the run would read as CLOSED while it was live — the
# fail-dangerous direction (.claude/rules/hook-authoring.md).
_run_lines() {
  awk '{ sub(/\r$/, ""); gsub(/\r/, "\n"); print }' "$1" 2>/dev/null
}

# docs_root <root> -> the absolute docs root for <root>: its .bionic/config.yaml's
# `docs-root:` value if set (relative values are joined onto <root>; absolute values pass
# through unchanged), else <root>/.bionic/docs. Byte-identical convention to
# hooks/canonical-sdlc-evidence-gate.sh's resolve_docs_root.
docs_root() {
  local root="$1"
  local config="$root/.bionic/config.yaml"
  local override=""
  if [ -f "$config" ]; then
    override=$(grep -E '^[[:space:]]*docs-root[[:space:]]*:' "$config" 2>/dev/null \
      | head -1 \
      | sed -E 's/^[[:space:]]*docs-root[[:space:]]*:[[:space:]]*//' \
      | sed -E "s/^['\"]//;s/['\"]\$//" \
      | sed -E 's/[[:space:]]+$//')
  fi
  if [ -n "$override" ]; then
    case "$override" in
      /*) printf '%s\n' "$override" ;;
      *)  printf '%s\n' "$root/$override" ;;
    esac
    return 0
  fi
  printf '%s\n' "$root/.bionic/docs"
}

# active_plan <root> -> the newest *.md by mtime under <docs_root>/plans and
# <docs_root>/incidents (each walked to depth <= 2) that contains a flush-left
# `## SDLC State` line; exit 1 and print nothing when no candidate qualifies.
#
# DEPTH 2, AND IT IS THE FLEET'S ONLY BOUND (POKER/2, ratified 2026-09-03). This function
# shipped at 3 and the readers it replaced walked 2, which is the bionic layout's own depth:
# `plans/<epic>/<wave>.plan.md`. For one wave the two bounds ran side by side and
# tests/cross-gate-agreement.test.sh §S.3d PINNED the disagreement rather than papering over
# it. It is resolved here, at 2, on the layout's own terms — a file three levels down under
# plans/ is a note, a fixture or a scratch draft, and admitting it re-opens the newest-race
# the `## SDLC State` filter exists to close. Every hook reads this one walk now, so the
# bound is stated once and pinned by number in three suites (run-predicate §R3,
# cross-gate §S.2, and the fixture battery's `nested-three-deep`).
active_plan() {
  local root="$1"
  local droot
  droot=$(docs_root "$root")
  local plan="" f d
  for d in "$droot/plans" "$droot/incidents"; do
    [ -d "$d" ] || continue
    while IFS= read -r -d '' f; do
      # FENCE-AWARE, and line endings TRANSLATED rather than deleted. Two failure modes,
      # opposite directions, both recorded:
      #   - a `## SDLC State` heading that appears only inside a ``` fenced example is
      #     DOCUMENTATION. Counting it makes a page about the lifecycle look like a live
      #     run, and every always-on hook then binds in a project that has none.
      #   - `tr -d '\r'` collapses a CR-only (classic-Mac) file to a single line, every
      #     line-anchored match misses, and a real plan becomes invisible to the whole
      #     fleet while a wave is live (.claude/rules/hook-authoring.md).
      # awk splits on \n, so a CR-only file arrives as one record that gsub re-splits
      # into real lines. The evidence gate carries the same reading at its own parse.
      _run_lines "$f" | awk '
        /^[[:space:]]*```/ { fence = !fence; next }
        fence { next }
        /^## SDLC State/ { found = 1 }
        END { exit !found }' || continue
      if [ -z "$plan" ] || [ "$f" -nt "$plan" ]; then
        plan="$f"
      fi
    done < <(find "$d" -maxdepth 2 -type f -name '*.md' -print0 2>/dev/null)
  done
  [ -n "$plan" ] || return 1
  printf '%s\n' "$plan"
}

# active_run <root> -> exit 0 + the plan path iff active_plan succeeds and the plan's state
# is open (see file header); else exit 1, silent.
active_run() {
  local root="$1"
  local plan
  plan=$(active_plan "$root") || return 1

  # Frontmatter close: a plan explicitly abandoned is never active, regardless of `current:`.
  local frontmatter
  frontmatter=$(_run_lines "$plan" | awk '
    NR == 1 && $0 == "---" { f = 1; next }
    f && $0 == "---" { exit }
    f { print }
  ')
  if printf '%s\n' "$frontmatter" | grep -q '^abandoned:'; then
    return 1
  fi

  # The `current:` line. LEADING WHITESPACE IS TOLERATED and the read is fence-aware, for
  # the same reason the marker test above is: this is the exact tolerance the five
  # hand-copies in hooks/ carried, and a predicate that is stricter than the walls it
  # replaces goes silently inert on a plan those walls read perfectly well.
  local current
  current=$(_run_lines "$plan" | awk '
    /^[[:space:]]*```/ { fence = !fence; next }
    fence { next }
    { print }' | grep -m1 -E '^[[:space:]]*current[[:space:]]*:' \
    | sed -E 's/^[[:space:]]*current[[:space:]]*:[[:space:]]*//' \
    | tr -d '[:space:]')
  [ -n "$current" ] || return 1

  # Task-scale: current: T<n> is always active (no numbered close).
  if printf '%s' "$current" | grep -qE '^T[0-9]+$'; then
    printf '%s\n' "$plan"
    return 0
  fi

  # THE STEP NUMBER MAY CARRY A SUB-STEP LETTER — `8a`, `8b` — which the lifecycle uses
  # and every wall this replaces accepted (`^[0-9]+[ab]?$`). A predicate that read `8b`
  # as malformed would call a live run closed for the whole of step 8, which is where
  # implementation happens. The letter is stripped; what decides is the number.
  local step="${current%[ab]}"
  case "$step" in
    ''|*[!0-9]*) return 1 ;;
  esac

  # Steps 0-8: open by definition.
  if [ "$((10#$step))" -lt 9 ]; then
    printf '%s\n' "$plan"
    return 0
  fi

  # Step 9: open unless a Step-9 evidence line records delivery. Anything past 9 is not a
  # step this lifecycle has, and an unrecognised state is not an open run.
  if [ "$((10#$step))" -eq 9 ]; then
    if _run_lines "$plan" | grep -qE '^[[:space:]]*-?[[:space:]]*Step 9:.*delivered:'; then
      return 1
    fi
    printf '%s\n' "$plan"
    return 0
  fi

  # Anything else (out-of-range current:, malformed) is not a recognized open state.
  return 1
}

# ---------- ENGAGEMENT: the single switch every bionic hook reads FIRST ----------
#
# task-engaged-session (Chris, 2026-09-03): "all guardrails imposed by bionic should only
# apply when exercising bionic. Nothing should apply until bionic is triggered" — and the
# trigger is the canonical-sdlc skill, nothing else. `hooks/engage.sh` writes the marker at
# the instant of invocation; every hook asks this before it asks anything else, and exits
# silently when it is false. Engagement decides WHETHER a hook acts; the plan (`active_run`,
# above) decides WHAT — a hook that finds the marker and no plan runs its plan-free walls
# and skips the plan-bound ones. The marker is never removed during the session: `disarm`
# removes the Patrol stamp only, and a session that invoked the skill is bionic's for its
# whole life.
#
# FAIL DIRECTION IS INVERTED HERE, deliberately: this is the one artifact whose PRESENCE
# opens walls. Every unreadable state — absent, symlink, foreign sid, empty sid, the
# `unknown` fallback two advisories use — reads as NOT engaged, because the arming
# partition is the consent boundary (1.3.2 close-out ruling) and a wall that binds a
# session which never consented is the bug this exists to fix.

# engaged_marker_path <root> <sid> -> the marker path, or exit 1 on a sid that is empty,
# `unknown`, or carries any character outside [A-Za-z0-9_-] (the stamp's own shape rule).
engaged_marker_path() {
  local root="$1" sid="$2"
  [ -n "$root" ] && [ -n "$sid" ] || return 1
  [ "$sid" = "unknown" ] && return 1
  case "$sid" in *[!A-Za-z0-9_-]*) return 1 ;; esac
  printf '%s/.bionic/tmp/engaged-%s.state\n' "$root" "$sid"
}

# engaged_session <root> <sid> -> exit 0 iff a REGULAR file exists at the marker path. A
# symlink there is refused before it is followed, matching the stamp guard. Silent both ways.
engaged_session() {
  local f
  f=$(engaged_marker_path "$1" "$2") || return 1
  [ -L "$f" ] && return 1
  [ -f "$f" ]
}
