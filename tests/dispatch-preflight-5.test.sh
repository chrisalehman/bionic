#!/bin/bash
# Tests for hooks/dispatch-preflight.sh — THE START GATE. The fifth shard: §AGREE and §PROTOTYPE
# (wave-38 T21; REQ-13 AC-13.1, AC-13.2; design ledger Δ9, D16).
#
# A STEP-2 PROTOTYPE THE WALL ADMITS. steps/2.md sanctions a prototype at Step 2, before the plan
# carries `approved-by:`, and until 1.21.0 the wall refused every writer role there and named no
# prototype role (ideas/bionic-1.20.0-step2-prototype-wall.md). D16: before
# approval the wall admits a `Kind: prototype` dispatch that writes only under the docs root's
# record/ and inside the throwaway tree the dispatcher spawned for it, refuses it on any tracked
# path, and binds it to no plan row. "What the wall admits is decided by what the dispatch may
# write, not by when it runs."
#
# §AGREE pins the two texts to one set: the dispatches steps 0-2 promise (the grammar below) and
# the set the wall exports with `dispatch-preflight.sh --admitted-before-approval`. §PROTOTYPE
# drives the wall on a prototype brief, and the evidence gate's existing no-row arm on a matrix AC
# naming a prototype row.
#
# The suite's header (what the gate governs, how it stays hermetic) is in
# tests/dispatch-preflight.test.sh; the fixtures are in tests/dispatch-preflight.prelude.sh.
#
# FIXTURE FIDELITY (the rule of that name, .claude/rules/test-harness.md). §AGREE reads the
# SHIPPED steps 0-2 and the shipped hook's export; its plants are scratch copies of steps/2.md.
# §PROTOTYPE's repositories are make_repo's (a real git repository, a real bound plan), the
# approval line taken out; the throwaway tree is a real `git worktree add`, marked by the
# production writer `worktree_mark`. The evidence-gate plan is SYNTHESIZED in Section 38's shape
# (tests/canonical-sdlc-evidence-gate-2.test.sh).
# ANTI-VACUITY (the rule of that name). Every empty readback sits beside a positive on the same
# extractor: the grammar is proved to read the prototype promise before the agreement is asked,
# and each refusal case has an admitted control that differs by one line.
#
# Usage: bash tests/run.sh --only dispatch-preflight-5.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"
. "$(dirname "$0")/lib/bound-marker.sh"
. "$(dirname "$0")/lib/roster-row.sh"
. "$(dirname "$0")/lib/live-answer.sh"
. "$(dirname "$0")/lib/swept-marker.sh"
. "$(dirname "$0")/dispatch-preflight.prelude.sh"

STEPS_DIR="${BIONIC_SKILLS_DIR}/canonical-sdlc/steps"
AGENTS_DIR="${BIONIC_SCRIPTS_DIR}/agents"
DP5_LIB="${BIONIC_SCRIPTS_DIR}/payload/scripts/lib"

section "§AGREE — every dispatch a step file promises before approval is one the wall admits (REQ-13 AC-13.1)"
# ============================================================================
#
# THE WALL'S SIDE IS DATA. `dispatch-preflight.sh --admitted-before-approval` prints the set it
# admits before `approved-by:`, one token a line: each read-only role as `role_is_readonly`
# (lib/roster.sh) holds it, and each brief kind as `kind:<k>`. Never a regex over the hook's prose.
#
# THE STEPS' SIDE IS A GRAMMAR (pinned here, recorded in record/wave-38-one-stop/T21-prototype.md).
# The steps before approval are 0, 1 and 2 (Step 3 ends on the approval). A SENTENCE is a run of a
# paragraph line ended by `.`, `!` or `?` and a blank, by `;`, or by the line end (a clause, then).
# A clause PROMISES a dispatch when it holds `dispatch`, `dispatches`, `dispatched` or `dispatching`
# as a whole word (so `dispatch-preflight` and `dispatched-task` are not it) and no form of `refuse`
# (a clause saying the wall refuses a role states a refusal, not a promise); what it promises is
# every token in it of
#   - `bionic:<role>`, or a bare bionic role name (a basename of agents/*.md) as a whole word,
#     read as `bionic:<role>`;
#   - the harness roles `Explore` and `Plan`, spelled as a code span;
#   - a code span `kind: <k>`, read as `kind:<k>`.
# The agreement holds when the promised set of steps 0-2 is non-empty and inside the admitted set.
# Equality is not asked: the read-only roles are dispatched at any step on SKILL.md's word, and
# steps 0-2 need not name each one (A-T21-3).
#
# fails-when: a step sentence promises a dispatch the wall refuses before approval (a planted
# `bionic:senior-implementor` at Step 2 shows it); the wall's set is unreadable or empty.
ap_roles() {  # -> the bionic role names, one a line, from agents/*.md
  local f
  for f in "$AGENTS_DIR"/*.md; do [ -f "$f" ] && basename "$f" .md; done
}
ap_promised() {  # <step file>... -> each promised token, one a line, sorted, unique
  LC_ALL=C /usr/bin/awk -v roles="$(ap_roles | tr '\n' ' ')" '
    BEGIN { nr = split(roles, R, " ") }
    function wordat(s, p, l,   a, b) {
      a = (p == 1) ? "" : substr(s, p - 1, 1)
      b = substr(s, p + l, 1)
      return (a !~ /[A-Za-z0-9:_-]/ && b !~ /[A-Za-z0-9_-]/)
    }
    function hasword(s, re,   rest, off) {
      rest = s; off = 0
      while (match(rest, re)) {
        if (wordat(s, off + RSTART, RLENGTH)) return 1
        off += RSTART; rest = substr(rest, RSTART + 1)
      }
      return 0
    }
    function scan(s,   t, i, p, rest, off) {
      if (!hasword(tolower(s), "dispatch(es|ed|ing)?")) return
      if (hasword(tolower(s), "refus(e|es|ed|ing)")) return
      rest = s
      while (match(rest, /bionic:[a-z][a-z-]*/)) {
        print substr(rest, RSTART, RLENGTH); rest = substr(rest, RSTART + RLENGTH)
      }
      rest = s
      while (match(rest, /`kind:[ ]*[a-z][a-z-]*`/)) {
        t = substr(rest, RSTART + 1, RLENGTH - 2); sub(/^kind:[ ]*/, "", t)
        print "kind:" t; rest = substr(rest, RSTART + RLENGTH)
      }
      if (index(s, "`Explore`")) print "Explore"
      if (index(s, "`Plan`")) print "Plan"
      for (i = 1; i <= nr; i++) {
        rest = s; off = 0
        while ((p = index(rest, R[i])) > 0) {
          if (wordat(s, off + p, length(R[i]))) { print "bionic:" R[i]; break }
          off += p; rest = substr(rest, p + 1)
        }
      }
    }
    {
      line = $0
      # scan() calls match(), which resets RSTART and RLENGTH, so both are kept before the call.
      while (match(line, /([.!?][ \t]|;)/)) {
        cs = RSTART; cl = RLENGTH; scan(substr(line, 1, cs)); line = substr(line, cs + cl)
      }
      scan(line)
    }' "$@" | sort -u
}
ap_admitted() { bash "$GATE" --admitted-before-approval < /dev/null 2>/dev/null | sort -u; }
ap_outside() {  # <promised> <admitted> -> each promised token the admitted set lacks
  /usr/bin/awk 'FILENAME == ARGV[1] { a[$0] = 1; next } NF && !($0 in a)' <(printf '%s\n' "$2") <(printf '%s\n' "$1")
}

AP_ADMITTED="$(ap_admitted)"
expect_contains "AGREE.1 the wall exports its admitted pre-approval set: the prototype kind" \
  "kind:prototype" "$AP_ADMITTED"
expect_contains "AGREE.1b …and the read-only roles, as role_is_readonly holds them" \
  "bionic:researcher" "$AP_ADMITTED"
AP_RO="$( ( . "$DP5_LIB/roster.sh" >/dev/null 2>&1; printf '%s\n' $ROLE_READONLY_SET ) | sort -u)"
expect_nonempty "AGREE.1c precondition: roster.sh's read-only set reads non-empty" "$AP_RO"
expect_eq "AGREE.1c …and the exported set is that set and the prototype kind, nothing else" \
  "$(printf '%s\nkind:prototype\n' "$AP_RO" | sort -u)" "$AP_ADMITTED"
expect_absent "AGREE.1d …a writer role is not in it" "bionic:senior-implementor" "$AP_ADMITTED"

AP_PROMISED="$(ap_promised "$STEPS_DIR/0.md" "$STEPS_DIR/1.md" "$STEPS_DIR/2.md")"
expect_contains "AGREE.2 the grammar reads steps 0-2: steps/2.md promises the prototype dispatch" \
  "kind:prototype" "$AP_PROMISED"
expect_eq "AGREE.3 every dispatch steps 0-2 promise is one the wall admits before approval" \
  "" "$(ap_outside "$AP_PROMISED" "$AP_ADMITTED")"

# THE PLANT: a scratch copy of steps/2.md promising a senior-implementor at Step 2.
AP_SCRATCH="$SANDBOX/ap-steps"; mkdir -p "$AP_SCRATCH"
cp "$STEPS_DIR/2.md" "$AP_SCRATCH/2.md"
printf '\nAt Step 2 a `bionic:senior-implementor` is dispatched to build the prototype.\n' >> "$AP_SCRATCH/2.md"
AP_PLANTED="$(ap_promised "$STEPS_DIR/0.md" "$STEPS_DIR/1.md" "$AP_SCRATCH/2.md")"
expect_contains "AGREE.4 the planted sentence is read as a promise of the writer role" \
  "bionic:senior-implementor" "$AP_PLANTED"
expect_eq "AGREE.4b …and the agreement fails, naming it" "bionic:senior-implementor" \
  "$(ap_outside "$AP_PLANTED" "$AP_ADMITTED")"
cp "$STEPS_DIR/2.md" "$AP_SCRATCH/2b.md"
printf '\nThe design interview dispatches an implementor to try the shape.\n' >> "$AP_SCRATCH/2b.md"
expect_eq "AGREE.4c a bare role name in a dispatch sentence is a promise too" "bionic:implementor" \
  "$(ap_outside "$(ap_promised "$AP_SCRATCH/2b.md")" "$AP_ADMITTED")"
cp "$STEPS_DIR/2.md" "$AP_SCRATCH/2c.md"
printf '\nThe implementor writes nothing before approval.\n' >> "$AP_SCRATCH/2c.md"
expect_eq "AGREE.4d a role named in a sentence with no dispatch in it promises nothing" "" \
  "$(ap_outside "$(ap_promised "$AP_SCRATCH/2c.md")" "$AP_ADMITTED")"
expect_contains "AGREE.4d …while the same file's prototype promise is still read" "kind:prototype" \
  "$(ap_promised "$AP_SCRATCH/2c.md")"
cp "$STEPS_DIR/2.md" "$AP_SCRATCH/2d.md"
printf '\nBefore approval dispatch-preflight refuses every writer-class dispatch (implementor, senior-implementor).\n' >> "$AP_SCRATCH/2d.md"
printf 'The model of every tier (implementor, critic) is read from the dispatched-task ledger.\n' >> "$AP_SCRATCH/2d.md"
expect_eq "AGREE.4e a refusal clause, and a compound of the word, promise nothing" "" \
  "$(ap_outside "$(ap_promised "$AP_SCRATCH/2d.md")" "$AP_ADMITTED")"
expect_contains "AGREE.4e …while the same file's prototype promise is still read" "kind:prototype" \
  "$(ap_promised "$AP_SCRATCH/2d.md")"
cp "$STEPS_DIR/2.md" "$AP_SCRATCH/2e.md"
printf '\nThe walk is ruled; then a senior-implementor is dispatched to try it.\n' >> "$AP_SCRATCH/2e.md"
expect_eq "AGREE.4f …while a promise in the next clause of the same sentence is still read" \
  "bionic:senior-implementor" "$(ap_outside "$(ap_promised "$AP_SCRATCH/2e.md")" "$AP_ADMITTED")"

section "§PROTOTYPE — a confined prototype is admitted before approval and owns no row (REQ-13 AC-13.2)"
# ============================================================================
#
# THE CONFINEMENT RULE. A brief whose `Kind:` line is `prototype` is admitted before `approved-by:`
# when every `Files:` path sits under the docs root's record/ or under the tree its
# `Throwaway tree:` line names, and no path is one git tracks at the head. The tree is one
# `spawn-worktree.sh create --for <name>` made for this dispatch: a linked worktree whose marker
# (lib/worktree.sh `worktree_mark`, the writer `create --for` calls) holds the agent's name. A
# prototype owns no plan row: it is admitted with no `Row:`, and a `Row:` on one is refused. A
# writer brief without the kind is refused before approval, as before.
#
# FIXTURES: make_repo's plan, its approval line taken out and `current:` set to 2; a linked tree
# under .worktrees/ marked for the agent. README.md is tracked at the head.
#
# fails-when: a confined prototype is refused before approval; one is admitted that names a
# tracked path, a path outside both places, a tree not made for it, or a Row:.
pt_unapprove() {  # <repo> — the bound plan at Step 2, with no approved-by: line
  local p="$1/.bionic/docs/plans/epic-99-test/wave-01-test.plan.md"
  /usr/bin/awk '/^approved-by:/ { next } /^current:/ { print "current: 2"; next } { print }' "$p" > "$p.tmp" \
    && mv "$p.tmp" "$p"
}
pt_tree() {  # <repo> <tree name> <marker name> -> a linked tree under .worktrees/, marked
  local t="$1/.worktrees/$2"
  git -C "$1" worktree add -q -b "proto/$2" "$t" >/dev/null 2>&1 || return 1
  ( . "$DP5_LIB/worktree.sh" >/dev/null 2>&1; worktree_mark "$t" "$3" ) || return 1
  printf '%s' "$t"
}
pt_brief() {  # <Files span> [<extra line>...] — a prototype brief with its tree line
  printf 'Your task: answer the design question with a throwaway.\nKind: prototype\n'
  printf 'Throwaway tree: .worktrees/w99-proto\n'
  printf 'Expected artifact: .bionic/docs/record/w99-proto.md\nExpected duration: ~20 minutes.\n'
  printf 'Progress artifact: .bionic/docs/record/w99-proto.progress.md\nSuites: none\n'
  printf 'Files: %s' "$1"; shift
  local l; for l in "$@"; do printf '\n%s' "$l"; done
}
PT_OK_FILES='.bionic/docs/record/w99-proto.md, .bionic/docs/record/w99-proto.progress.md, .worktrees/w99-proto/lib/try.sh'
pt_gate() {  # <repo> <brief> [<name>] [<role>]
  run_gate "$(mk_agent_payload "$SID_A" "$1" "$2" "${3:-w99-proto}" "claude-sonnet-5" "$S5_LIVE_TRANSCRIPT" \
    "${4:-bionic:senior-implementor}")"
}
pt_repo() {  # <name> -> an unapproved Step-2 fixture with the tree made for w99-proto
  local r; r=$(make_repo "$1" yes) || return 1
  write_attestation "$r" "$SID_A"
  pt_unapprove "$r"
  pt_tree "$r" w99-proto w99-proto >/dev/null || return 1
  printf '%s' "$r"
}

REPO=$(pt_repo rpt1)
PT_PLAN="$REPO/.bionic/docs/plans/epic-99-test/wave-01-test.plan.md"
expect_absent "PT.0 precondition: the plan carries no approved-by: line" "approved-by:" "$(cat "$PT_PLAN")"
expect_true "PT.0b precondition: the throwaway tree is a linked worktree" test -f "$REPO/.worktrees/w99-proto/.git"
expect_eq "PT.0c precondition: …marked for the agent" "w99-proto" \
  "$( ( . "$DP5_LIB/worktree.sh" >/dev/null 2>&1; worktree_marker "$REPO/.worktrees/w99-proto" ) )"
expect_eq "PT.0d precondition: README.md is tracked at the head" "README.md" "$(git -C "$REPO" ls-files -- README.md)"

# --- PT.1: the confined prototype is admitted before approval, with no Row: ---
pt_gate "$REPO" "$(pt_brief "$PT_OK_FILES")"
expect_eq "PT.1 AC-13.2 a confined Kind: prototype brief is admitted before approved-by:" "allow" "$GATE_VERDICT"
expect_absent "PT.1b …with no word of approval" "unapproved" "$GATE_ERR$GATE_VERR"
expect_eq "PT.1c …and it is journalled, a launch like any other" "1" "$(roster_rows "$(roster_path "$REPO" "$SID_A")")"

# --- PT.2: THE CONTROL — the same brief without the kind is a writer, refused before approval ---
REPO=$(pt_repo rpt2)
pt_gate "$REPO" "$(pt_brief "$PT_OK_FILES" | /usr/bin/grep -v '^Kind:')"
expect_eq "PT.2 control: the same brief with no Kind: line is refused before approval" "deny" "$GATE_VERDICT"
expect_contains "PT.2b …as an unapproved writer" "the plan this writer builds is unapproved" "$GATE_ERR"

# --- PT.3: one tracked path refuses, naming it ---
REPO=$(pt_repo rpt3)
pt_gate "$REPO" "$(pt_brief "$PT_OK_FILES, README.md")"
expect_eq "PT.3 AC-13.2 a prototype naming one tracked path is refused" "deny" "$GATE_VERDICT"
expect_contains "PT.3b …the line names the path as tracked" "README.md is tracked" "$GATE_ERR"
expect_contains "PT.3c …the detail states the confinement rule" \
  "a prototype writes only under record/ or its throwaway tree; README.md is tracked" "$GATE_VERR"

# --- PT.4: a tracked record is tracked too ---
REPO=$(pt_repo rpt4)
mkdir -p "$REPO/.bionic/docs/record"; printf 'kept\n' > "$REPO/.bionic/docs/record/kept.md"
git -C "$REPO" add -f .bionic/docs/record/kept.md && git -C "$REPO" commit -qm kept 2>/dev/null
expect_eq "PT.4 precondition: the record is tracked" ".bionic/docs/record/kept.md" \
  "$(git -C "$REPO" ls-files -- .bionic/docs/record/kept.md)"
pt_gate "$REPO" "$(pt_brief "$PT_OK_FILES, .bionic/docs/record/kept.md")"
expect_eq "PT.4b a prototype naming a tracked record is refused" "deny" "$GATE_VERDICT"
expect_contains "PT.4c …naming it" ".bionic/docs/record/kept.md is tracked" "$GATE_VERR"

# --- PT.5: a path outside both places refuses ---
REPO=$(pt_repo rpt5)
pt_gate "$REPO" "$(pt_brief "$PT_OK_FILES, lib/new.sh")"
expect_eq "PT.5 a prototype naming an untracked path outside record/ and its tree is refused" "deny" "$GATE_VERDICT"
expect_contains "PT.5b …naming it as outside both" "lib/new.sh is outside both" "$GATE_VERR"

# --- PT.6: a Row: on a prototype refuses ---
REPO=$(pt_repo rpt6)
pt_gate "$REPO" "$(pt_brief "$PT_OK_FILES" 'Row: T1')"
expect_eq "PT.6 AC-13.2 a prototype brief carrying Row: is refused" "deny" "$GATE_VERDICT"
expect_contains "PT.6b …the line says a prototype owns no row" "a prototype owns no plan row" "$GATE_ERR"

# --- PT.7: a tree not made for this dispatch refuses ---
REPO=$(make_repo rpt7 yes); write_attestation "$REPO" "$SID_A"; pt_unapprove "$REPO"
pt_tree "$REPO" w99-proto w99-other >/dev/null
pt_gate "$REPO" "$(pt_brief "$PT_OK_FILES")"
expect_eq "PT.7 a throwaway tree marked for another agent is refused" "deny" "$GATE_VERDICT"
expect_contains "PT.7b …naming the tree and the name its marker holds" "w99-other" "$GATE_VERR"
REPO=$(make_repo rpt7b yes); write_attestation "$REPO" "$SID_A"; pt_unapprove "$REPO"
mkdir -p "$REPO/.worktrees/w99-proto"
pt_gate "$REPO" "$(pt_brief "$PT_OK_FILES")"
expect_eq "PT.7c a throwaway tree that is no linked worktree is refused" "deny" "$GATE_VERDICT"
expect_contains "PT.7d …as a tree spawn-worktree did not make" "throwaway tree" "$GATE_ERR"

# --- PT.8: with no Throwaway tree: line, only record/ paths are confined ---
REPO=$(pt_repo rpt8)
pt_gate "$REPO" "$(pt_brief '.bionic/docs/record/w99-proto.md, .bionic/docs/record/w99-proto.progress.md' | /usr/bin/grep -v '^Throwaway tree:')"
expect_eq "PT.8 a prototype writing only under record/ needs no tree, and is admitted" "allow" "$GATE_VERDICT"
REPO=$(pt_repo rpt8b)
pt_gate "$REPO" "$(pt_brief "$PT_OK_FILES" | /usr/bin/grep -v '^Throwaway tree:')"
expect_eq "PT.8b …and a tree path with no Throwaway tree: line is outside both" "deny" "$GATE_VERDICT"
expect_contains "PT.8c …naming it" ".worktrees/w99-proto/lib/try.sh is outside both" "$GATE_VERR"

# --- PT.9: the confinement holds after approval too: what it may write decides, not when ---
REPO=$(make_repo rpt9 yes); write_attestation "$REPO" "$SID_A"; pt_tree "$REPO" w99-proto w99-proto >/dev/null
expect_contains "PT.9 precondition: this plan is approved" "approved-by:" \
  "$(cat "$REPO/.bionic/docs/plans/epic-99-test/wave-01-test.plan.md")"
pt_gate "$REPO" "$(pt_brief "$PT_OK_FILES, README.md")"
expect_eq "PT.9b a prototype naming a tracked path is refused on an approved plan" "deny" "$GATE_VERDICT"
expect_contains "PT.9c …naming it" "README.md is tracked" "$GATE_ERR"

# --- PT.10: the evidence gate still refuses a matrix AC naming a prototype row (its existing arm) ---
# Driven as it stands (lib/walls.sh validate_prototype_no_matrix_row): a plan at `current: 4` whose
# `## Tasks` names T12 `kind: prototype` and whose AC-1 block names `task: T12`. The control
# repoints AC-1 at the build row T13 and changes nothing else.
EG_GATE="${BIONIC_HOOKS_DIR}/bash-walls.sh"   # the evidence gate is a wall of bash-walls.sh
PT_EG_SID="5d4c3b2a-9e8f-4a76-8b1c-2d3e4f506172"
pt_eg_plan() {  # <dir> <AC-1's task> -> writes the plan, echoes its path
  local p="$1/.bionic/docs/plans/active.md"
  mkdir -p "$1/.bionic/docs/plans" "$1/.bionic/docs/record" "$1/.bionic/tmp" "$1/.claude/plans"
  printf 'generic fixture proof\n' > "$1/.bionic/docs/record/generic-evidence.md"
  cat > "$p" <<EOF
---
governing-skill: canonical-sdlc
canonical_sdlc_version: 14
intent: build
rigor: double
scale: wave
deploy_target: none
use_worktree: false
has_ui: true
walk: exempt
---
## SDLC State
current: 4
approved-by: dana 2026-09-07T19:05Z "Ok, amazing! Approved."
Step 4:
  plan-doc: .bionic/docs/plans/wave-01.plan.md#step-4

## Tasks

| id | step | kind | task | agent | deps | size | serves | Files | status |
|---|---|---|---|---|---|---|---|---|---|
| T12 | 4 | prototype | E1: refusal wording (attended) | senior-implementor | — | 30m | E1 | record/x.md | pending |
| T13 | 4 | build | E1: hooks migrated | senior-implementor | T12 | 60m | E1 | hooks/*.sh | pending |

## Verification Matrix

stack-health: n/a: no long-running serve

| AC | tier | status | evidence | auditor |
|---|---|---|---|---|
| AC-1 | T0 | pending | see AC-1 | |

AC-1:
  criterion: the refusal wording is proven
  provenance: user 2026-09-07 "approved"
  task: $2
  fails-when: the wording is untested
EOF
  printf '%s' "$p"
}
pt_eg_run() {  # <dir> -> PT_EG_RC and PT_EG_ERR (the verbose stream) for a `git commit` there
  local in
  : > "$1/.bionic/tmp/engaged-$PT_EG_SID.state"
  bound_marker "$1" "$PT_EG_SID" "$1/.bionic/docs/plans/active.md"
  in=$(jq -n --arg c 'git commit -m "x"' --arg cwd "$1" --arg s "$PT_EG_SID" \
         '{session_id: $s, tool_input: {command: $c}, cwd: $cwd}')
  PT_EG_ERR=$(HOME="$1" CLAUDE_PROJECT_DIR="" CLAUDE_CODE_SESSION_ID="$PT_EG_SID" BIONIC_WALL_VERBOSE=1 \
    bash "$EG_GATE" <<< "$in" 2>&1 >/dev/null)
  PT_EG_RC=$?
}
PT_EG1="$SANDBOX/pt-eg1"; mkdir -p "$PT_EG1"
pt_eg_plan "$PT_EG1" T12 >/dev/null
pt_eg_run "$PT_EG1"
expect_status "PT.10 AC-13.2 a matrix AC naming the prototype row is refused by the evidence gate" "2" "$PT_EG_RC"
expect_contains "PT.10b …by its no-row arm, naming the AC and the row" \
  "matrix row 'AC-1' names 'task: T12', a 'kind: prototype' row" "$PT_EG_ERR"
PT_EG2="$SANDBOX/pt-eg2"; mkdir -p "$PT_EG2"
pt_eg_plan "$PT_EG2" T13 >/dev/null
pt_eg_run "$PT_EG2"
expect_status "PT.10c control: the same AC pointed at the build row is admitted" "0" "$PT_EG_RC"
expect_absent "PT.10d …with no word of the prototype" "kind: prototype" "$PT_EG_ERR"

finish
