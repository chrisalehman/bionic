# payload/scripts/lib/scale.sh — THE SCALE PROFILE (epic-23 wave-38 T16; D25, REQ-5 AC-5.1,
# AC-5.3; spec §Design "Scale profile").
#
# [WALL: tests/scale-profile.test.sh]
#
# ONE ROW PER SCALE, ONE CELL PER PROPERTY. What a scale changes about a run was five literals in
# five files: the Patrol armed at engagement, the regression line's default, the dealing's whole
# read, the branch-shape refusal and the merge act. Each is a column here, and each site reads its
# cell through `scale_cell`. The rule (D25): the next property of a scale is a column, never a
# check.
#
#   scale  patrol  rigor   writers   regression  branch            integrate  dealing
#   task   no      single  3         no          any               pr         piece
#   wave   yes     double  uncapped  yes         wave/<NN>-<slug>  merge      piece+whole
#   epic   yes     double  uncapped  no          epic/<NN>-<slug>  merge      piece
#
# THE COLUMNS AND THEIR READERS:
#   patrol      `yes` arms the Patrol at engagement and holds the dispatch wall's arming check;
#               `no` arms nothing and the check does not apply. Read through `scale_patrol <plan>`
#               below, by arm, the session-start text, the tick, the stop wall, engagement, resume
#               and handoff, and the dispatch wall.
#   rigor       the default review rigor. A flag, the intent, the project or the epic may raise
#               it (skills/canonical-sdlc/SKILL.md, the Step 0 derivation).
#   writers     the writer cap when no person wrote a `parallel-budget:` line; a person's line
#               overrides it. `uncapped` caps nothing. Read by `fill_cap` (lib/fill.sh) alone, which
#               the tick's FILL, the stop wall and the dispatch wall's budget check all ask.
#   regression  the Step 0 regression default (payload/scripts/card.sh `regression <scale>`).
#   branch      the working branch's shape: `any`, or a pattern whose `<NN>` is the run's number
#               and `<slug>` its name (payload/scripts/close-out.sh, the shape refusal and the
#               worktree census's wt/NN-* scope).
#   integrate   `merge`: the working branch is merged before the tail; `pr`: close-out merges
#               nothing and prints and records the `gh pr create` command (payload/scripts/close-out.sh).
#   dealing     the reads each code question is dealt: `piece`, or `piece+whole` for one more read
#               of the whole. WHO reads at each rigor stays lib/proof.sh's PROOF_DEALING, the
#               per-rigor map, because a flag can raise a task-scale run to `double` and the
#               dealing must answer it (payload/scripts/lib/proof.sh `facts_owed`, read by the
#               dispatch wall's Questions: check).
#
# THE DOCTRINE TABLE IS THIS TABLE. SKILL.md's scale table carries the seven columns, and
# tests/scale-profile.test.sh §TABLE compares it to `scale_cell` cell by cell.
#
# A SITE THAT CANNOT KNOW THE SCALE (no plan, or a plan with no `scale:`) keeps the behaviour it
# had before this file: it does not ask.
#
# BASH 3.2. Functions and constants only; nothing runs or prints at source time.

SCALE_COLUMNS="patrol rigor writers regression branch integrate dealing"
SCALE_ROWS="task wave epic"
SCALE_TABLE="task|no|single|3|no|any|pr|piece
wave|yes|double|uncapped|yes|wave/<NN>-<slug>|merge|piece+whole
epic|yes|double|uncapped|no|epic/<NN>-<slug>|merge|piece"

# scale_cell <scale> <column> -> that cell on stdout, exit 0. A scale or a column the table does
# not hold: nothing on stdout, one line on stderr naming the words it takes, exit 1.
scale_cell() {
  local scale="${1:-}" col="${2:-}" i=0 c n="" row
  for c in $SCALE_COLUMNS; do
    i=$((i + 1))
    [ "$c" = "$col" ] && n=$((i + 1))
  done
  case " $SCALE_ROWS " in
    *" $scale "*) [ -n "$scale" ] ;;
    *) false ;;
  esac || {
    printf "scale.sh: '%s' is no scale — use task, wave or epic\n" "$scale" >&2
    return 1
  }
  if [ -z "$n" ]; then
    printf "scale.sh: '%s' is no column — use patrol, rigor, writers, regression, branch, integrate or dealing\n" "$col" >&2
    return 1
  fi
  row="$(printf '%s\n' "$SCALE_TABLE" | awk -F'|' -v s="$scale" '$1 == s')"
  printf '%s\n' "$row" | awk -F'|' -v n="$n" '{ print $n }'
}

# scale_patrol <plan> -> `no` when the plan's scale has no Patrol (its patrol cell is `no`), else `yes`; exit 0 either
# way. A plan with no readable `scale:`, a scale the table does not hold, or no plan reads `yes`: an unreadable scale
# never silences a Patrol that may be needed. This is the one place a plan's scale is turned into "does it have a
# Patrol", so every reader that asks the question gets the same answer for the same plan.
scale_patrol() {  # <plan>
  local cell
  declare -F plan_frontmatter_get >/dev/null 2>&1 || { printf 'yes\n'; return 0; }
  cell="$(scale_cell "$(plan_frontmatter_get "${1:-}" scale 2>/dev/null)" patrol 2>/dev/null)" || cell=yes
  if [ "$cell" = no ]; then printf 'no\n'; else printf 'yes\n'; fi
  return 0
}

# scale_branch_number <scale> <branch> -> what the branch pattern's `<NN>` matched on <branch>,
# exit 0; nothing and exit 0 when the cell is `any`; nothing and exit 1 when <branch> does not
# have the cell's shape or <scale> is no scale. The pattern is the cell itself: `<NN>` reads
# digits, `<slug>` one or more characters, every other character itself.
scale_branch_number() {
  local pat ere
  pat="$(scale_cell "${1:-}" branch 2>/dev/null)" || return 1
  [ "$pat" != any ] || return 0
  ere="$(printf '%s' "$pat" | sed -e 's/[][\.*^$(){}+?|/]/\\&/g' -e 's/<NN>/([0-9]+)/' -e 's/<slug>/.+/')"
  printf '%s\n' "${2:-}" | sed -nE "s/^${ere}\$/\\1/p" | /usr/bin/grep . || return 1
}

# THE EVAL TYPE'S TIER. The Eval design names each criterion's eval type in words; the matrix table names its
# tier, and the tier decides the keys its block owes (walls.sh `keys_for_tier`). This is the one map between the
# two, so the render that writes a missing table row and any reader that asks agree on the tier a type owes.
# A bare tier (`T2`, any case) is itself: a plan that names the tier in the Eval type cell already said it.
SCALE_EVAL_TIERS="static=T0 unit=T1 hermetic=T2 live=T3 human=T4"

# scale_tier_awk -> the awk text of `tier_of(type)`: the tier SCALE_EVAL_TIERS gives a type (any case, blanks
# trimmed), a bare T<n> as itself, else "". Built from the table, so an awk pass reads the map without a copy.
scale_tier_awk() {
  local c
  printf '%s\n' 'function tier_of(t) {' \
    '  t = tolower(t); gsub(/^[ \t]+|[ \t]+$/, "", t)' \
    '  if (t ~ /^t[0-9]+$/) return "T" substr(t, 2)'
  for c in $SCALE_EVAL_TIERS; do
    printf '  if (t == "%s") return "%s"\n' "${c%%=*}" "${c#*=}"
  done
  printf '%s\n' '  return ""' '}'
}

# tier_of_eval_type <type> -> its tier on stdout, exit 0; nothing and exit 1 for a type the map does not hold.
# It asks `tier_of`, so the shell's answer and the awk pass's are one rule.
tier_of_eval_type() {
  local t
  t="$(SCALE_TYPE="${1:-}" awk "$(scale_tier_awk)"'BEGIN { print tier_of(ENVIRON["SCALE_TYPE"]) }' </dev/null 2>/dev/null)" || return 1
  [ -n "$t" ] || return 1
  printf '%s\n' "$t"
}
