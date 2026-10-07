# tests/fixtures/upgrade-1.12.0/install.sh — a run open at upgrade, planted in a model world (wave-28 T21; D26, REQ-2
# AC-2.11, REQ-7 AC-7.2).
#
#     . "$(dirname "$0")/lib/world.sh"; . "$(dirname "$0")/lib/roster-row.sh"
#     . "$(dirname "$0")/fixtures/upgrade-1.12.0/install.sh"
#     root="$(world_repo)"; up_install "$root"
#
# WHAT IT PLANTS, all of it the SHAPE 1.12.0 wrote and no word of any real run:
#   - `wave-x.plan.md` over the world's bound plan: `canonical_sdlc_version: 14`, the `parallel-budget:` line as
#     the probe wrote it (`source=probe`), a `## Tasks` ledger of 13 columns whose rows carry no `Lands-on:`
#     label (1.12.0 had none), a `## Dispatch ledger`, and Step evidence the real commit gate admits;
#   - the files that evidence names (requirements, spec, adr, design ledger), so the gate resolves them;
#   - each row's roster launch row as 1.12.0 wrote it: `suites_allowed=` and `files=`, and neither `row=` nor
#     `lands_on=` (those are 1.13.0's, lib/roster.sh);
#   - in T1's tree, a stamp file in the bare form 1.12.0's `land` read, saying RED (rc=1) for a.test.sh at T1's
#     head: the one fact a reader of stamps would refuse the landing on.
# up_install <world root> [<T1's suites_allowed: a value | - for none stated>]; the default is a.test.sh. T2's
# launch row waives every suite (`suites_allowed=none`), as a 1.12.0 brief with `Suites: none` did.
up_install() {  # <world root> [<T1 suites_allowed>]
  local r="${1:-}" sa="${2-a.test.sh}" here d p t gd extra
  here="${BASH_SOURCE[0]%/*}"
  [ -n "$r" ] && [ "$(git -C "$r" rev-parse --show-toplevel 2>/dev/null)" = "$r" ] || return 1
  d="$r/.bionic/docs"; p="$d/plans/epic-x/wave-x.plan.md"
  mkdir -p "$d/specs/epic-x" "$d/adrs/epic-x" "$d/record/wave-x" || return 1
  cp "$here/wave-x.plan.md" "$p" \
    && cp "$here/requirements.md" "$d/specs/epic-x/wave-x.requirements.md" \
    && cp "$here/spec.md" "$d/specs/epic-x/wave-x.spec.md" \
    && cp "$here/adr.md" "$d/adrs/epic-x/adr-001-fixture.md" \
    && cp "$here/design-ledger.md" "$d/record/wave-x/design-ledger.md" || return 1
  for t in T1 T2; do
    case "$t:$sa" in T1:-) extra="" ;; T1:*) extra="suites_allowed=$sa" ;; *) extra="suites_allowed=none" ;; esac
    roster_row_fixture status=intended session="$WORLD_SID" name="wx-$t" agent_id="b00$t" plan="$p" \
      ${extra:+"$extra"} suites_source=declared "files=$t.txt" >> "$r/.bionic/tmp/roster-$WORLD_SID.state" || return 1
  done
  gd="$(git -C "$r/.worktrees/T1" rev-parse --absolute-git-dir)" || return 1
  sed "s/@HEAD@/$(git -C "$r/.worktrees/T1" rev-parse HEAD)/" "$here/stamps" >> "$gd/bionic-stamps"
}
