# tests/lib/bound-marker.sh — the one bound-marker fixture builder
# (wave-roster-lifecycle S11, spec AC-24; research-code-map §6.1).
#
#     . "$(dirname "$0")/lib/resolve-roots.sh"      # first, so BIONIC_SCRIPTS_DIR is set
#     . "$(dirname "$0")/lib/bound-marker.sh"
#
# WHAT IT REPLACES. Five suites each hand-wrote the two-line marker
# `payload/scripts/lib/binding.sh`'s `bind_plan` is the one production writer of:
# `plan=<value>\nengaged_at=<iso>\n`, mode 600 (research-code-map §6.1 names all
# five: canonical-sdlc-evidence-gate.test.sh `s35_bind`/`s35_unbind`,
# session-poker.test.sh `bind_marker`, session-start.test.sh `plant_bound`,
# dispatch-preflight.test.sh `s25_bind`, cross-gate-agreement.test.sh `s4_bind`/
# `s4_unbind` — the last replaced by S11b, in a parallel tree, after S12 lands).
# None of them called `bind_plan`, so none of them could catch a marker shape the
# real writer stopped producing. This file is the one place that still hand-writes
# a marker; every suite's own builder becomes a one-line wrapper over it.
#
# bound_marker <root> <sid> <plan|none> -> binds through the real `bind_plan`
# (`payload/scripts/lib/binding.sh`). `plan` is validated exactly as engage.sh's own
# dispatch validates it: an absolute path that `open_runs "$root"` lists at the
# instant of the call, or the literal `none` (always accepted, never validated).
#
# THE FALLBACK, AND WHY IT IS HERE, NOT A SECOND WRITER. Several existing fixtures
# bind deliberately to a plan that is no longer an open run — DELIVERED
# (session-poker.test.sh §18b's `P18B_DONE`; canonical-sdlc-evidence-gate.test.sh
# §35d's `S35_D`) or never written at all / since deleted
# (canonical-sdlc-evidence-gate.test.sh §35e/§35g1's `S35_GONE`/`S35_GONE2`). Those
# suites are not testing `bind_plan`'s write path — they are testing what every
# READER does once a binding that WAS valid has since gone stale, a real lifecycle
# `bind_plan` cannot retroactively forbid: it only ever validates open-run
# membership AT THE INSTANT OF THE WRITE, by design (binding.sh: "a bound plan must
# be an absolute path that `open_runs` lists for THIS root... IT REFUSES RATHER
# THAN GUESSES"). So `bind_plan` correctly refuses to WRITE such a marker fresh;
# this function's fallback reproduces the exact two-line shape it would have
# produced back when the plan was still open, with the plan argument stored
# VERBATIM — there is nothing left on disk to canonicalise against. The fallback is
# fixture-only: nothing in the fleet is a second production writer of this marker,
# and every caller that needs the validated path (the overwhelming majority of call
# sites) gets it, unchanged, through the first branch.
bound_marker() {  # <root> <sid> <plan|none>
  local root="$1" sid="$2" plan="$3" path stamp
  if bind_plan "$root" "$sid" "$plan"; then
    return 0
  fi
  path=$(engaged_marker_path "$root" "$sid") || return 1
  mkdir -p "$(dirname "$path")"
  stamp=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) || stamp="2026-09-04T00:00:00Z"
  printf 'plan=%s\nengaged_at=%s\n' "$plan" "$stamp" > "$path"
  chmod 600 "$path"
}

# unbound_marker <root> <sid> [empty|none|nofield] -> the three shapes that are NOT
# a binding, all of which the fleet really produces (s35_unbind's own comment,
# canonical-sdlc-evidence-gate.test.sh:5230): an EMPTY marker (what every `engage`
# in these suites writes before a plan is chosen), the literal `plan=none` (what
# engagement writes when the root holds zero or several open runs), and a marker
# carrying no `plan=` line at all. None of the three is a binding for `bind_plan` to
# validate — writing `plan=none` through it would also work (`none` is always
# accepted), but the other two shapes have no `bind_plan` equivalent at all, so all
# three are written the same direct way here for one consistent contract.
unbound_marker() {  # <root> <sid> [empty|none|nofield]
  local root="$1" sid="$2" shape="${3:-empty}" f
  f="$root/.bionic/tmp/engaged-$sid.state"
  mkdir -p "$(dirname "$f")"
  case "$shape" in
    none)    printf 'plan=none\nengaged_at=2026-09-04T00:00:00Z\n' > "$f" ;;
    nofield) printf 'engaged_at=2026-09-04T00:00:00Z\n' > "$f" ;;
    *)       : > "$f" ;;
  esac
  chmod 600 "$f"
}

if ! type -t bind_plan >/dev/null 2>&1; then
  . "${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/run.sh"
  . "${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/binding.sh"
fi
