#!/bin/bash
# tests/close-out-6.test.sh — payload/scripts/close-out.sh, part 6 of 6: sections RUNS through §REG.
#
# THE SUITE IS SIX PARTS: one close-out.test.sh outran the suite bar, so it runs as parts cut at section boundaries,
# and the two longest were cut again by the seconds of one run: RUNS through §REG left close-out-3 for this part.
# Its design, sandbox, fixture builders and helpers are in tests/close-out.prelude.sh, sourced below after the framework.
#
# Usage: bash tests/close-out-6.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"
. "$(dirname "$0")/lib/regression-fixture.sh"
. "$(dirname "$0")/lib/roster-row.sh"   # the one roster-row builder
. "$(dirname "$0")/close-out.prelude.sh"

# ============================================================
section "RUNS: the Step-8 sweep stops every orphan run"
# ============================================================
#
# THE SWEEP: a detached run
# (booked.sh --detach) whose pid is alive and that wrote no end, left by a closing run, is an orphan;
# `run` stops it through `session-poker.sh stop-run` and names it with its last progress line, then
# the wipe takes its files; `check` names it and sends nothing. FIXTURE FIDELITY: the roster row is a
# run record in the shim's shape; the orphan is a stand-in shim (a loop that dies on TERM, under the
# real perl setsid, its pid file and progress line beside its log), because a closing run's orphan is
# a process nobody is waiting on and the sweep reads nothing else of it.
PR="$(mk_fixture pruns)"; advance_to "$PR" 8
PR_RUNS="$PR/.bionic/tmp/runs"; mkdir -p "$PR_RUNS" "$SANDBOX/fake-shim"
roster_row_fixture status=identified session=fixture name=w-reg agent_id=areg \
  "run_log=$PR_RUNS/w-reg-run.sh.log" run_cmd=tests/run.sh run_rc=0 >> "$PR/.bionic/tmp/roster-fixture.state"
printf '#!/bin/bash\nwhile :; do sleep 0.2; done\n' > "$SANDBOX/fake-shim/booked.sh"
pr_shim() {  # <log> -> a stand-in shim on that log, its pid file written; the pid on stdout
  : > "$1"
  perl -MPOSIX -e 'my $l = shift; my $p = fork; exit 0 if $p; POSIX::setsid(); open(my $f, ">", "$l.pid"); print $f "$$\n"; close $f; open(STDIN, "<", "/dev/null"); open(STDOUT, ">>", $l); open(STDERR, ">&", \*STDOUT); exec @ARGV' \
    "$1" bash "$SANDBOX/fake-shim/booked.sh" --run-log "$1"
  i=0; while [ ! -s "$1.pid" ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
  cat "$1.pid" 2>/dev/null
}
PR_LOG="$PR_RUNS/w-orph-o.test.sh.log"; PR_PID="$(pr_shim "$PR_LOG")"
printf '2026-10-08T00:00:02Z\to.test.sh\t§sec-orph\n' > "$PR_LOG.progress.tsv"
TS_LIVE_PIDS="$TS_LIVE_PIDS ${PR_PID:-}"
expect_true "RUNS.0 precondition: the orphan's shim is alive" kill -0 "${PR_PID:-0}"
# The session closing the run is bound to it, so a hand act would reach its log: a person's stop of a second run, with
# its reason, is one hand event there; the close's own sweep, the tool working, adds none.
printf 'plan=%s\nengaged_at=2026-10-08T00:00:00Z\n' "$PR/$PLAN_REL" > "$PR/.bionic/tmp/engaged-fixture.state"
PR_HAND="$PR_RUNS/w-hand-h.test.sh.log"; TS_LIVE_PIDS="$TS_LIVE_PIDS $(pr_shim "$PR_HAND")"
( cd "$PR" && HOME="$SB_HOME" CLAUDE_CODE_SESSION_ID=fixture bash "$REPO_ROOT/hooks/session-poker.sh" stop-run "$PR_HAND" --why 'a person stopped it' ) >/dev/null 2>&1
pr_hands() { /usr/bin/grep '^run/v1|ev=hand|what=stop-run|' "$PR/.bionic/docs/record/wave-01-fixture/run.log" 2>/dev/null | sed 's/.*|why=\([^|]*\)|.*/\1/' | paste -sd'|' -; }
expect_eq "RUNS.0b precondition: a person's stop with its reason is one hand event in the run's log" "a person stopped it" "$(pr_hands)"

run_close "$PR" check
expect_eq "RUNS.2b …ending in the run's last progress line" "yes" \
  "$(contains "$(printf '%s\n' "$CO_OUT" | grep '^orphan: ')" "; last progress: 2026-10-08T00:00:02Z o.test.sh §sec-orph")"
expect_true "RUNS.3 …and sends nothing: the orphan is still alive" kill -0 "${PR_PID:-0}"

run_close_as fixture "$PR" run
expect_eq "RUNS.4 run exits 0" "0" "$CO_RC"
expect_false "RUNS.7 …and the orphan's process is gone" kill -0 "${PR_PID:-0}"
expect_eq "RUNS.8 …and the wipe took its files with the rest of .bionic/tmp" "0" "$(tmp_entries "$PR")"
expect_eq "RUNS.9 one orphan, one line" "1" "$(printf '%s\n' "$CO_OUT" | grep -c '^orphan: ')"
expect_eq "RUNS.10 …and the close's sweep of it is no hand event: the person's stop is still the only one" "a person stopped it" "$(pr_hands)"

# ============================================================
section "FILL — wave-33 T8 (REQ-3 AC-3.3, D8): the epic row and the continuation are written whole"
# ============================================================
#
# The epic row's ADR cell was `<fill: ADRs>` when no source named one, and wave-30's still reads so; the
# continuation carried fourteen marks the orchestrator completed by hand (A-orch-50). Close-out now writes every
# field it can derive, refuses the row when the plan says nothing about its ADRs, and leaves a mark only where
# a person must decide, naming each in its output. The row is read from the close's output: the close writes no plan.
printed_row() { printf '%s\n' "$CO_OUT" | sed -n 's/^shipped-row: //p'; }
printed_adr_cell() { printed_row | awk -F'|' '{ c = $6; gsub(/^[ \t]+|[ \t]+$/, "", c); print c }'; }

FA="$(mk_fixture fill-a)"; advance_to "$FA" 8
FA_MAIN="$(fixture_git "$FA" rev-parse --short main)"
run_close "$FA" run
FA_ROW="$(printed_row)"
FA_CONT="$(cat "$FA/$CONT_REL" 2>/dev/null)"
expect_eq "FILL.2 AC-3.3 the epic row carries no <fill:, and holds the merge commit it names" "no/yes" \
  "$(contains "$FA_ROW" "<fill:")/$(contains "$FA_ROW" "main @ $FA_MAIN")"
expect_eq "FILL.3 …and an ADR cell that says so when the plan says none (adrs: none)" "—" "$(printed_adr_cell)"
expect_contains "FILL.4 the continuation states the task count from the plan (the two build rows)" "2 tasks, every one RED→GREEN" "$FA_CONT"
expect_contains "FILL.7 …and the commit it closed at, written whole" "main at $FA_MAIN." "$FA_CONT"
expect_absent "FILL.8 no Patrol sentence when no job is known (this session has no transcript) and no mark for it" "Patrol" "$FA_CONT"

# THE ROW IS REFUSED, NOT MARKED, when the plan says nothing about its ADRs.
FB="$(mk_fixture fill-b)"; advance_to "$FB" 8
/usr/bin/grep -v '^adrs:' "$FB/$PLAN_REL" > "$FB/plan.tmp" && mv "$FB/plan.tmp" "$FB/$PLAN_REL"
FB_STATE="$(presence_state "$FB")/$(sha_of "$FB/$PLAN_REL")/$(sha_of "$FB/$EPIC_REL")"
run_close "$FB" check
expect_eq "FILL.12 check says the close would refuse, naming the missing field and the line to write" "yes/yes" \
  "$(contains "$CO_OUT" "presence: WOULD REFUSE")/$(contains "$CO_OUT" "adrs: none")"
run_close "$FB" run
expect_eq "FILL.13 run refuses (rc 2) naming the field, before any act" "2/yes/no" "$CO_RC/$(contains "$CO_OUT" "adrs:")/$(contains "$CO_OUT" "worktree-removed:")"
expect_eq "FILL.14 …branch, tmp, continuation, plan and epic plan untouched" "$FB_STATE" \
  "$(presence_state "$FB")/$(sha_of "$FB/$PLAN_REL")/$(sha_of "$FB/$EPIC_REL")"
# …AND A PLAN THAT SAYS WHICH ADRS (paired with FILL.12–14: the same fixture with the line written closes).
set_plan_keys "$FB" "-" "adrs: adrs/epic-fx/adr-052-the-workhorse.md"
run_close "$FB" run
expect_eq "FILL.15 the same plan with an adrs: line closes (rc 0) and the cell and the continuation name the ADR" "0/052/yes" \
  "$CO_RC/$(printed_adr_cell)/$(contains "$(cat "$FB/$CONT_REL")" "ADRs: 052.")"

# A LANDING REPORT THAT CANNOT BE READ is a sentence, not a mark: the plugin root's poker is a stub that fails.
FQ="$(mk_fixture fill-q)"; advance_to "$FQ" 8
FQ_PLUG="$SANDBOX/fill-q-plugin"
mkdir -p "$FQ_PLUG"
for f in "$REPO_ROOT"/payload/* "$REPO_ROOT"/payload/.claude-plugin; do [ -e "$f" ] && ln -s "$f" "$FQ_PLUG/${f##*/}"; done
rm -f "$FQ_PLUG/hooks"; mkdir -p "$FQ_PLUG/hooks"
for f in "$BIONIC_HOOKS_DIR"/*; do ln -s "$f" "$FQ_PLUG/hooks/${f##*/}"; done
rm -f "$FQ_PLUG/hooks/session-poker.sh"; printf '#!/bin/bash\nexit 1\n' > "$FQ_PLUG/hooks/session-poker.sh"
( in_fixture "$FQ" || exit 9
  HOME="$SB_HOME" CLAUDE_PROJECT_DIR="" BIONIC_PLUGIN_ROOT="$FQ_PLUG" BIONIC_CLAUDE_HOME="$SB_HOME/.claude" \
    bash "$SCRIPT" "$FQ/$PLAN_REL" run ) > "$SANDBOX/fq-out" 2>&1
FQ_RC=$?
expect_eq "FILL.18 with a poker that cannot report landings the close still finishes (rc 0)" "0" "$FQ_RC"

# ============================================================
section "§REF — wave-35 T10 (REQ-1 AC-1.7, D10): the facts judge reads the working branch's ref through the one reader; a branch that names no commit stays uncovered"
# ============================================================
# close-out's facts judge (`facts_judge`) hands lib/proof.sh `facts_state` the head of the working branch, and it now
# reads that head through lib/proof.sh `proof_branch_head` (`refs/heads/<branch>`), the reader `current 7`, `current 8`
# and the floor judge share, never a checkout's and never whatever else git would resolve the bare name to. The
# branch name itself is read through lib/run.sh `plan_working_branch` (SDLC State, then frontmatter), so close-out
# has no second reader of it (A-orch-16).
# FIXTURE FIDELITY: mk_fixture's run at Step 8: wave/01-fixture merged into main, every fact planted at its head by
# the product's pair, the branch checked out in `<project>-wave`. Each row then takes away one thing a run that has
# merged takes away: the worktree, the branch, the SDLC-State key.
# fails-when: the judge reads the checkout's head, or a ref other than the branch; a deleted branch reads covered;
# a plan whose working-branch: is in its frontmatter alone is refused for naming none.
ref_head() { fixture_git "$1" rev-parse --verify -q "refs/heads/wave/01-fixture" 2>/dev/null; }
PREF="$(mk_fixture ref-merged)"; advance_to "$PREF" 8
REF_H="$(ref_head "$PREF")"
fixture_git "$PREF" worktree remove --force "$PREF-wave" >/dev/null 2>&1
expect_eq "REF-0 precondition: the branch names a commit, no checkout holds it, and the main checkout is on main" "yes|0|main" \
  "$([ -n "$REF_H" ] && echo yes)|$(fixture_git "$PREF" worktree list --porcelain | grep -c '^branch refs/heads/wave/01-fixture$' | tr -d ' ')|$(fixture_git "$PREF" symbolic-ref --short HEAD)"
run_close "$PREF" check
run_close "$PREF" run
expect_eq "REF-2 …and run closes the plan (rc 0)" "0|1" "$CO_RC|$(run_open_rc "$PREF/$PLAN_REL")"

PREFD="$(mk_fixture ref-deleted)"; advance_to "$PREFD" 8
fixture_git "$PREFD" worktree remove --force "$PREFD-wave" >/dev/null 2>&1
fixture_git "$PREFD" branch -D wave/01-fixture >/dev/null 2>&1
expect_eq "REF-3 precondition: the working branch is deleted (no ref names it)" "" "$(ref_head "$PREFD")"
run_close "$PREFD" check
expect_contains "REF-3b AC-1.7 a deleted branch: check says the facts would be refused" "facts: WOULD REFUSE" "$CO_OUT"
# A TAG OF THE SAME NAME IS NOT THE BRANCH. `git rev-parse <name>` resolves refs/tags/<name> before refs/heads/<name>, so a
# judge that asks git for the bare name reads a tag where the branch is gone; the branch's ref reader does not.
fixture_git "$PREFD" tag wave/01-fixture main >/dev/null 2>&1
expect_nonempty "REF-4 precondition: a tag of the branch's name names a commit" \
  "$(fixture_git "$PREFD" rev-parse --verify -q 'refs/tags/wave/01-fixture^{commit}' 2>/dev/null)"
run_close "$PREFD" check

PREFF="$(mk_fixture ref-frontmatter)"; advance_to "$PREFF" 8   # a page at 15 names its branch in its header alone
run_close "$PREFF" check
expect_absent "REF-5b A-orch-16 close-out reads the branch through the one reader: a frontmatter key is not refused as none" \
  "names no working-branch" "$CO_OUT"

# ============================================================
section "§ORDER — close-out publishes the reviews part before its merge readback, so the readback reads the branch the part is on"
# ============================================================
# close-out merges nothing: its merge act is a readback that the working branch is reachable from the
# integration branch, and the person's merge came first. When close-out itself renders the part (no integrate row did), it
# publishes it BEFORE that readback, so the readback reads the branch the part is on, and holds until that tip is merged.
# FIXTURE FIDELITY: mk_fixture's wave-scale plan (integrate cell `merge`) at Step 8 with the release entry committed on the
# working branch and merged into main, as the release row's landing and the person's merge leave it; the part is not yet
# listed, as a run with no integrate row leaves it.
# fails-when: the reviews line comes after the merge line; the branch is not at the part's commit when the readback reads it;
#   the run closes with the part on no branch main holds; or the second run, after the person merges the published tip,
#   renders a second part.
ord_fixture() {  # <name> -> a wave-scale project at Step 8 whose release entry has no ### The reviews part, merged into main
  local p wt
  p="$(mk_fixture "$1")" && advance_to "$p" 8 || return 1
  wt="$p-wave"
  awk '{ print } /^adrs: none$/ && !d { print "release: 9.9.9"; d = 1 }' "$p/$PLAN_REL" > "$p/$PLAN_REL.r" \
    && mv "$p/$PLAN_REL.r" "$p/$PLAN_REL" && seal_fixture "$p/$PLAN_REL" "$p/$LOG_REL"
  printf '# Changelog\n\n## 9.9.9 — 2026-10-22\n\nThe prose a person wrote.\n\n### Known limits\n\n- one limit\n' > "$wt/CHANGELOG.md"
  fixture_git "$wt" add CHANGELOG.md && fixture_git "$wt" commit -q -m "the release entry" >/dev/null 2>&1 \
    && fixture_git "$p" merge -q --no-ff -m "merge the release" wave/01-fixture >/dev/null 2>&1 || return 1
  printf '%s\n' "$p"
}
PMO="$(ord_fixture order-merge)"
plant_facts "$PMO"
OM_H="$(fixture_git "$PMO" rev-parse --verify -q refs/heads/wave/01-fixture)"
expect_eq "ORDER-5 precondition: the integration branch holds the working branch's tip, as the person's merge left it" "yes" \
  "$(fixture_git "$PMO" merge-base --is-ancestor wave/01-fixture main && echo yes || echo no)"
run_close "$PMO" run
OM_TIP="$(fixture_git "$PMO" rev-parse --verify -q refs/heads/wave/01-fixture)"
expect_eq "ORDER-6 close-out published a part: the working branch moved past the tip the person merged" "yes" \
  "$([ -n "$OM_TIP" ] && [ "$OM_TIP" != "$OM_H" ] && fixture_git "$PMO" log -1 --format='%an <%ae>' "$OM_TIP" | /usr/bin/grep -qxF 'fixture <fixture@example.invalid>' && echo yes || echo no)"
OM_ACT="$(printf '%s\n' "$CO_OUT" | /usr/bin/grep -c '^merge: ')"
expect_eq "ORDER-7 …so the readback, read on that branch, held: the run did not close, and its merge act never ran" "yes|0" \
  "$([ "$CO_RC" -ne 0 ] && echo yes)|$OM_ACT"
expect_contains "ORDER-7b …saying the working branch is not merged" "is not reachable from" "$CO_OUT"
expect_contains "ORDER-7c …after the reviews line named the published commit" "reviews: " "$CO_OUT"
expect_contains "ORDER-7d …which names the commit the branch is at" "$(printf '%.12s' "$OM_TIP")" "$(printf '%s\n' "$CO_OUT" | /usr/bin/grep '^reviews: ')"
expect_eq "ORDER-8 main does not hold the part until the published tip is merged" "no" \
  "$(fixture_git "$PMO" show main:CHANGELOG.md 2>/dev/null | /usr/bin/grep -q '^### The reviews' && echo yes || echo no)"
fixture_git "$PMO" merge -q --no-ff -m "merge the published part" wave/01-fixture >/dev/null 2>&1
run_close "$PMO" run
expect_eq "ORDER-9 after the person merges the published tip, the run closes and finds the part already listed" "0|yes" \
  "$CO_RC|$(printf '%s\n' "$CO_OUT" | /usr/bin/grep '^reviews: ' | /usr/bin/grep -q 'already lists' && echo yes)"
expect_eq "ORDER-9b …and rendered no second part: the branch is where the first run left it" "$OM_TIP" \
  "$(fixture_git "$PMO" rev-parse --verify -q refs/heads/wave/01-fixture)"

# ============================================================
section "§ADRS — close-out's epic row writes an ADR named by a path with no adr-<n> as the path (REQ-9 AC-9.1)"
# ============================================================
# The document step's pointer is the plan's `adrs:` header line, written by the orchestrator. An ADR path with no
# `adr-<n>` gives no number, so the row carries the path as written. FIXTURE FIDELITY: mk_fixture's plan with its
# `adrs:` line naming a record by path, as set_plan_keys writes a header key.
# fails-when: a value with no adr-<n> is refused by `epic_row_missing` or written as no ADR.
PAP="$(mk_fixture adrs-path)"; set_plan_keys "$PAP" - "adrs: record/wave-01-fixture/adr.md"; advance_to "$PAP" 8
run_close "$PAP" run
expect_eq "AD-5 a path with no adr-<n>: the epic row is written, its ADR cell the path, never refused" "0|record/wave-01-fixture/adr.md" "$CO_RC|$(printed_adr_cell)"

# ============================================================
section "§REG: the continuation's regression line prints the full pass's state at this head from the one printer"
# ============================================================
# fails-when: the continuation reads the proof line alone, so over a whole run red at F whose reds two later landings
# greened it says the whole run holds, or green, or leaves the landings since it uncounted.
# FIXTURE FIDELITY: the run is tests/proof-at-head.test.sh's (`pah_world`, from tests/lib/proof-at-head-world.sh), laid on
# this suite's own fixture; the continuation is the one `close-out.sh run` writes.
# ANTI-VACUITY: REG-1 reads the line before REG-2 reads its state through the extractor REG-1 proved non-empty.
. "$(dirname "$0")/lib/proof-at-head-world.sh" || { echo "close-out-6.test.sh: cannot load lib/proof-at-head-world.sh"; exit 1; }
PAH_LIB="$REPO_ROOT/payload/scripts/lib"
pah_world reg-red "notify.test.sh,rehearsal-failed-review.test.sh,shell-lint.test.sh,sitrep.test.sh" 2
run_close_as reg-close "$PAH_P" run
expect_eq "REG-1 close-out delivers over the run (exit 0), its continuation holding a regression line" "0|1" \
  "$CO_RC|$(/usr/bin/grep -c 'the regression: ' "$PAH_P/$CONT_REL" 2>/dev/null)"
expect_eq "REG-2 …which prints the whole suite red at the whole run's head, the two landings since counted, then the proof's instant and log" \
  "red at ${PAH_F:0:8}, 2 landings before this head|yes" \
  "$(pah_cont_state "$PAH_P/$CONT_REL")|$(/usr/bin/grep -qF "the regression: whole suite red at ${PAH_F:0:8}, 2 landings before this head (proved 2026-10-04T12:00:00Z, record/wave-01-fixture/regression-run-$PAH_F.log)" "$PAH_P/$CONT_REL" && echo yes)"
expect_absent "REG-3 …and never says the whole run holds" "holds at" "$(/usr/bin/grep -F 'the regression: ' "$PAH_P/$CONT_REL")"

finish
