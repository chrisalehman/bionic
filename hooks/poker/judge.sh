# shellcheck shell=bash
# hooks/poker/judge.sh — the judge: whether a question is covered at a head, and the verbs that ask it (current,
# cover).
#
# A part of hooks/session-poker.sh, which sets every global and loads this file before any verb runs. A part
# defines functions only, and is never run by itself.

# A FAILING QUESTION IS THE PERSON'S TO WAIVE (wave-33 T35; AC-2.2, D2). A reading whose newest fact is
# result=fail leaves the person the call: fix it, or waive the question. So the judge's every answer
# settles the ledger (lib/owed.sh) for the waivable questions: each `failing` review line opens
# `waive:<question>`, the key the waive verb closes, carrying the line the refusal prints; every other
# question's item is closed, its block gone (a passing reading over the fix). Opening is idempotent per
# key, so a second refusal on the same question is one item. Prints nothing; never changes the verdict.
#
# AN UNRULED MATRIX ROW IS THE PERSON'S TO RULE. Asked with a second argument, the matrix rows the advance to 8
# finds unruled (`cur8_unruled`), it opens `row:<AC>` for each, the key the release approval card settles with its
# row decision, carrying the line the refusal prints for it, and closes every other open `row:` item, the row
# ruled since. Without the argument (the advance to 7) the row items are left as they are: the card puts them.
cur8_owed_waivers() {  # <facts_state output> [<unruled AC ids, one per line>] -> always 0
  local q fl k
  declare -F owed_open >/dev/null 2>&1 || return 0
  for q in $PROOF_QUESTIONS; do
    fl="$(printf '%s\n' "$1" | awk -F'\t' -v q="$q" '$1 == "review" && $2 == q && $(NF - 1) == "failing" { print; exit }')"
    if [ -n "$fl" ]; then
      OWED_ROOT="$PV_REPO" owed_open "waive:$q" "waiver: $q" "$fl" >/dev/null 2>&1
    else
      poker_owed_close "$PV_REPO" "waive:$q" "no longer failing"
    fi
  done
  [ "$#" -ge 2 ] || return 0
  for k in $2; do
    OWED_ROOT="$PV_REPO" owed_open "row:$k" "ruling: row $k" "$(cur8_unruled_line "$k")" >/dev/null 2>&1
  done
  while IFS= read -r k; do
    case "$k" in row:?*) : ;; *) continue ;; esac
    /usr/bin/grep -qxF "${k#row:}" <<< "$2" || poker_owed_close "$PV_REPO" "$k" "ruled"
  done <<OWED_ROWS
$(OWED_ROOT="$PV_REPO" owed_list 2>/dev/null | cut -f1)
OWED_ROWS
  return 0
}

# cur8_unruled -> the AC id of each matrix row the advance to 8 finds unruled, one per line: walls.sh
# `matrix_unruled`, the commit gate's own reader and predicate (`matrix_row_ruled`), asked in a subshell so nothing
# walls.sh defines outlives it. Never a second reading of the matrix here: the advance and every commit after it
# answer one row one way. rc 1 when the library or the reader cannot be had.
cur8_unruled() {
  [ -f "$BIONIC_LIB/walls.sh" ] || return 1
  ( . "$BIONIC_LIB/walls.sh" >/dev/null 2>&1 || exit 1
    declare -F matrix_unruled >/dev/null 2>&1 || exit 1
    matrix_unruled "$PV_PLAN" 8 )
}

# cur8_unruled_line <AC> -> the refusal's line for an unruled row: the matrix arm's own fact, as a commit at
# current: 8 is refused with it, so the release approval card settles it as `row:<AC>` whichever refusal names it.
cur8_unruled_line() {
  printf 'bionic: commit refused — the auditor has not confirmed %s (rule it: the auditor confirms it, the row is waived, or a T4 row carries its user'"'"'s confirmation)' "$1"
}

# cur7_judge <step> -> returns when lib/proof.sh `facts_state` says every fact the bound plan owes holds at
# the working head, with that head in PV_HEAD8; otherwise refuses `current <step>`, exit 1, the plan unchanged,
# printing each owed line that does not hold, in the judge's own words: the owed suite, or the commit the walk
# cannot prove (wave-27 T14; D3). The judge's rc 2, a plan it cannot deal, refuses too, printing whatever the
# judge printed, whatever the reason.
# STEPS 7 AND 8 ASK IT (wave-35 T10; D10, AC-1.2): Step 7 is entered once the floor is Step 6's last act, so
# `current 7` is held to the same judge `current 8` is, and a run never leaves Step 6 with its floor behind
# the head.
# IN THE ORDER build, regression, review, release (lib/units.sh `units_order`) `current 8` asks besides that the
# newest `approved: release` line's head (lib/proof.sh `proof_approved_head`) is the working head, or one that only prose
# touching no release-set file follows (lib/proof.sh `proof_prose_past`). The whole run need
# not be at that head: the regression judge holds it covered past its run when every later commit is proved by the
# suites its row named. A plan outside that order is judged as before.
# THE HEAD IS THE WORKING BRANCH'S REF (wave-35 T10; AC-1.7): lib/proof.sh `proof_branch_head`, the judge's one
# reading of it, never the head of a checkout, so a branch no checkout holds is judged where its ref points,
# and a branch that names no commit (deleted, or never made) is refused: there is no head, so the floor is
# uncovered.
# cover_basis <plan> <question> <a> <b> -> lib/proof.sh `facts_cover`'s lines for that range and question, with its rc
# (wave-37 T8; D8, AC-4.1, AC-4.2). THE ONE CALL OF THE LIBRARY'S BASIS in this file, shared by what prints it under
# a refused line (`cur7_judge`) and what prints it on ask (the `cover` verb), so the two cannot say different
# things of one range. Never called from the tick, `sched_facts_state`, `live_judge` or any wall: a person asks.
cover_basis() {
  if ! { declare -F facts_cover >/dev/null 2>&1 || { [ -f "$BIONIC_LIB/proof.sh" ] && . "$BIONIC_LIB/proof.sh"; }; } \
     || ! declare -F facts_cover >/dev/null 2>&1; then
    printf 'cover: the proof record (lib/proof.sh) cannot be loaded from %s\n' "$BIONIC_LIB" >&2
    return 2
  fi
  facts_cover "$1" "$3" "$4" "$2"
}

# cur8_approved_head -> returns when the newest `approved: release` line names the working head PV_HEAD8, or a head on its
# first-parent line past which nothing the approval covers changed (`proof_prose_past`); otherwise refuses `current 8`,
# exit 1, naming both heads, the plan unchanged.
cur8_approved_head() {
  local ah
  ah="$(proof_approved_head "$PV_PLAN" release 2>/dev/null)" || ah=""
  if [ -z "$ah" ]; then
    if proof_approved "$PV_PLAN" release; then
      die "REFUSED — current: 8 in the order (the regression row $PV_ORDER before review and the release) is admitted at the head the user approved for release, and the newest approved: release line names no head; the user's word for the working head $PV_HEAD8 is approve release '<reply>'. The plan is unchanged."
    else
      die "REFUSED — current: 8 in the order (the regression row $PV_ORDER before review and the release) is admitted at the head the user approved for release, and $PV_PLAN carries no approved: release line; the user's word for the working head $PV_HEAD8 is approve release '<reply>'. The plan is unchanged."
    fi
    exit 1
  fi
  if [ "$ah" != "$PV_HEAD8" ] && ! proof_prose_past "$PV_PLAN" "$ah" "$PV_HEAD8"; then
    die "REFUSED — current: 8 is admitted at the head the user approved for release: the working head ${PV_HEAD8:0:12} is not the head the user approved for release, ${ah:0:12}, and a commit past it is code or a release-set file. Land only docs past the approval, or have the user approve this head (approve release '<reply>'). The plan is unchanged."
    exit 1
  fi
}

cur7_judge() {  # <step>   (named for Step 7, the first step it judges; it judges Step 8 too)
  local step="$1" wb out rc err
  if ! { declare -F facts_state >/dev/null 2>&1 || { [ -f "$BIONIC_LIB/proof.sh" ] && . "$BIONIC_LIB/proof.sh"; }; } \
     || ! declare -F facts_state >/dev/null 2>&1; then
    die "REFUSED — current: $step is admitted on the facts the run owes, and the proof record (lib/proof.sh) cannot be loaded from $BIONIC_LIB; the plan is unchanged."
    exit 2
  fi
  wb="$(plan_working_branch "$PV_PLAN")"
  if [ -z "$wb" ]; then
    die "REFUSED — current: $step is admitted on the facts the run owes at the working head, and the plan names no working-branch: (## SDLC State or its frontmatter), so the regression is uncovered; the plan is unchanged."
    exit 1
  fi
  PV_HEAD8="$(proof_branch_head "$PV_PLAN" "$PV_REPO")" || PV_HEAD8=""
  case "$PV_HEAD8" in
    [0-9a-f]*) : ;;
    *)
      die "REFUSED — current: $step is admitted on the facts the run owes at the working head, and the working branch $wb names no commit here, so the regression is uncovered (there is no head to judge); the plan is unchanged."
      exit 1 ;;
  esac
  PV_ORDER="$(units_order "$PV_PLAN" 2>/dev/null)" || PV_ORDER=""
  [ "$step" != 8 ] || [ -z "$PV_ORDER" ] || cur8_approved_head
  # THE RULING IS THE MERGE ADVANCE'S: at 8 every matrix row is ruled, or the advance is refused naming each one.
  local unruled="" ac
  if [ "$step" = 8 ] && ! unruled="$(cur8_unruled)"; then
    die "REFUSED — current: 8 is admitted only when every matrix row is ruled, and the matrix reader (walls.sh matrix_unruled) cannot be loaded from $BIONIC_LIB; the plan is unchanged."
    exit 2
  fi
  out="$(facts_state "$PV_PLAN" "$PV_HEAD8" 2>"$PV_NEW.judge")"; rc=$?
  err="$(cat "$PV_NEW.judge" 2>/dev/null)"; rm -f "$PV_NEW.judge"
  # The check-only advance (`current <N> --check`; wave-38 T1, D20) takes this judgment and not its ledger write.
  if [ "$rc" -ne 2 ] && [ -z "${PV_CHECK:-}" ]; then
    if [ "$step" = 8 ]; then cur8_owed_waivers "$out" "$unruled"; else cur8_owed_waivers "$out"; fi
  fi
  [ "$rc" -eq 0 ] && [ -z "$unruled" ] && return 0
  for ac in $unruled; do printf '%s\n' "$(cur8_unruled_line "$ac")" >&2; done
  if [ "$rc" -eq 0 ]; then
    die "current: 8 waits on a ruling of each row above; settle each on the release approval card, or waive it with waive-row <AC> '<reply>'. The plan is unchanged."
    exit 1
  fi
  if [ "$rc" -eq 2 ]; then
    die "REFUSED — current: $step is admitted on the facts the run owes, and the judge could not deal this plan (facts_state exit 2); the plan is unchanged. The judge said:"
    [ -z "$err" ] || printf '%s\n' "$err" >&2
    [ -z "$out" ] || printf '%s\n' "$out" >&2
    exit 1
  fi
  die "REFUSED — current: $step is admitted only when every fact the run owes holds at the working head $PV_HEAD8, and these do not (facts_state):"
  # THE BASIS UNDER THE LINE (wave-37 T8; D8, AC-4.1): a `review <q> … uncovered <a>..<b>` line is a judge's "no"
  # with no why; under it go the `cover <sha> <basis>` lines for that range and question, and the line ends with
  # the ask that reproduces them (the `cover` verb). The text above is the refusal's own and does not change.
  local cv_line cv_k cv_q cv_rest cv_st cv_rng
  while IFS= read -r cv_line; do
    [ -n "$cv_line" ] || continue
    IFS='	' read -r cv_k cv_q cv_rest cv_rest cv_st cv_rng <<COVER_LINE
$cv_line
COVER_LINE
    case "$cv_k:$cv_st:$cv_rng" in
      review:uncovered:?*..?*)
        printf '%s · ask: session-poker.sh cover %s %s\n' "$cv_line" "$cv_q" "$cv_rng" >&2
        cover_basis "$PV_PLAN" "$cv_q" "${cv_rng%%..*}" "${cv_rng##*..}" >&2 || : ;;
      *) printf '%s\n' "$cv_line" >&2 ;;
    esac
  done <<COVER_JUDGED
$(printf '%s\n' "$out" | awk -F'\t' '$NF != "covered"')
COVER_JUDGED
  die "Take the reading or the regression run each line names and record it with proof-add, or have the user waive a question with waive <question> '<reply>'; the plan is unchanged. A red suite of the whole run is a fix row's: its own suites plus the red one."
  exit 1
}

# current_admit -> everything `current <N>` asks before it writes, on the copy plan_verb_open made: the projection
# of `current:` (and the Step-4 fill), the dry commit through the real gate, and the facts judge at 7 and 8. Sets
# PV_NEW, PV_FILLED, PV_DRYMODE (`judged` once the copy has been asked; `as-is` when the copy is the plan), PV_HOW;
# exits on every refusal in the advance's own words and code. THE ONE PATH (wave-38 T1; D20, AC-1.3): the advance
# calls it and then swaps; `current <N> --check` calls it and stops, so the two cannot answer differently.
current_admit() {
  if ! units_set_current "$PV_PLAN" "$PV_KEY" > "$PV_NEW" 2>/dev/null; then
    die "REFUSED — $PV_PLAN carries no current: line under ## SDLC State; the plan is unchanged."
    if /usr/bin/grep -q '^##[[:space:]][[:space:]]*SDLC State' "$PV_PLAN" 2>/dev/null; then
      die "missing: the line 'current: $PV_KEY' under ## SDLC State"
    else
      die "missing: a ## SDLC State section carrying 'current: $PV_KEY', above the plan's ## Tasks"
    fi
    exit 1
  fi
  PV_FILLED=""
  if [ "$PV_KEY" = 4 ]; then
    # lib/run.sh `plan_working_branch`, the one reader: SDLC State, then frontmatter (wave-35 T7; D14).
    PV_WB="$(plan_working_branch "$PV_PLAN")"
    if [ -n "$PV_WB" ]; then
      PV_FIELDS=()
      PV_WT="$(git -C "$PV_REPO" worktree list --porcelain 2>/dev/null \
        | awk -v b="branch refs/heads/$PV_WB" '/^worktree / { p = substr($0, 10) } $0 == b { print p; exit }')"
      if [ -n "$PV_WT" ]; then
        PV_WT="$(cd "$PV_WT" 2>/dev/null && pwd -P)"
        case "$PV_WT" in
          "$PV_REPO") PV_FIELDS+=("worktree=.") ;;
          "$PV_REPO"/*) PV_FIELDS+=("worktree=${PV_WT#"$PV_REPO"/}") ;;
          ?*) PV_FIELDS+=("worktree=$PV_WT") ;;
        esac
      fi
      PV_SHA="$(git -C "$PV_REPO" rev-parse --short --verify -q "refs/heads/$PV_WB" 2>/dev/null)"
      [ -n "$PV_SHA" ] && PV_FIELDS+=("base-sha=$PV_SHA")
      PV_FIELDS+=("branch=$PV_WB")
      # D16's PLAN FACT (wave-28 T8; A-orch-140): at wave scale the block also records the machine share the
      # run started under, `gate_share`'s value, through the same writer; a block already carrying the line
      # keeps it (the fill never rewrites), and a plan of another scale gets none.
      if [ "$(plan_frontmatter_get "$PV_PLAN" scale 2>/dev/null)" = wave ] && declare -F gate_share >/dev/null 2>&1; then
        PV_SHARE="$(gate_share 2>/dev/null)"
        [ -z "$PV_SHARE" ] || PV_FIELDS+=("share=$PV_SHARE")
      fi
      if units_step_fields "$PV_NEW" 4 "${PV_FIELDS[@]}" > "$PV_NEW.2" 2>/dev/null; then
        cmp -s "$PV_NEW.2" "$PV_NEW" || PV_FILLED="; the Step-4 block gained what it lacked of: ${PV_FIELDS[*]}"
        mv -f "$PV_NEW.2" "$PV_NEW"
      fi
    fi
  fi
  # STEP 8 IS ADMITTED ON THE JUDGE, NOT ON A DRY COMMIT (wave-27 T14; D3, D14, AC-2.3, AC-2.4,
  # AC-3.1, AC-7.1). The dry commit at Step 8 asked for the Step-8 block, which close-out writes
  # and judges through the gate itself (close-out.sh `gate_preflight`), so a run closed by its
  # tools alone could never take this step. 8 is exempt from it as 9 is from this verb, and is
  # refused instead unless lib/proof.sh `facts_state` says every fact the run owes holds at the
  # working head: the regression, and each reading its rigor and scale deal. Each line that does not
  # hold is printed as the judge gave it.
  # The mode has a name of its own: PV_DRY is the dry copy's PATH (wave-27 T76; A-orch-171).
  # STEP 7 ASKS THE JUDGE TOO (wave-35 T10; D10, AC-1.2; A-T10-12). The copy is dry-committed at Step 7 first, as
  # every other step's is, so the gate refuses what a real commit at Step 7 would refuse in its own words (a
  # declared red still owed, a missing line); then the judge holds the facts the run owes at the working head;
  # then the swap, which does not commit the copy a second time. A plan already at 7 is the swap's to say.
  PV_DRYMODE=as-is; PV_HOW="dry-committed at that step first"
  case "$PV_KEY" in
    7)
      if ! cmp -s "$PV_NEW" "$PV_PLAN"; then
        plan_verb_dry current "current: $PV_KEY" as-is "${PV_CUR%[ab]}"
        cur7_judge 7
        PV_DRYMODE=judged
        PV_HOW="dry-committed at that step first; every fact the run owes holds at $PV_HEAD8 (facts_state)"
      fi ;;
    8|8a|8b)
      cur7_judge 8
      PV_DRYMODE=judged; PV_HOW="every fact the run owes holds at $PV_HEAD8 (facts_state)"
      [ -z "$PV_ORDER" ] || PV_HOW="$PV_HOW, the head the user approved for release" ;;
  esac
  # THE DRY COMMIT AT 5 AND 6 IS RUN HERE, NOT IN THE SWAP (wave-38 T1; D20): the swap would run it for an
  # `as-is` copy that differs from the plan, so this runs it on the same condition and hands the swap `judged`.
  # Whatever the advance asks before it writes is asked in this function, so `current <N> --check` asks it all.
  if [ "$PV_DRYMODE" = as-is ] && ! cmp -s "$PV_NEW" "$PV_PLAN"; then
    plan_verb_dry current "current: $PV_KEY" as-is "${PV_CUR%[ab]}"
    PV_DRYMODE=judged
  fi
}
  # THE STEP MOVE (wave-24 T15; REQ-9 AC-9.5, D14; A-orch-8). `current:` moves through
  # `units_set_current`, and the copy is judged AT the step it moves to — the advance is the
  # commit the gate is asked about, so a step whose block is not written yet is refused here,
  # in the gate's words, and not at the first commit after it. `current: 9` is close-out's.
  #
  # ADVANCING TO 4 WRITES WHAT THE FIRST WRITER'S COMMIT IS REFUSED WITHOUT. The Step-4 block's
  # `worktree:`, `base-sha:` and `branch:` (walls.sh `shape_block`) are facts of the moment of
  # the advance: the branch is the plan's own `working-branch:`, its head is the base every
  # writer starts from, and the checkout holding it is the worktree. Each field the block lacks
  # is filled from those (`units_step_fields`); a field already written is never rewritten, and
  # a fact that cannot be read is not guessed — the field stays absent and the gate says so.
  # At wave scale the block also gains `share: <n>`, D16's plan fact (wave-28 T8, below).
  poker_verb_current() {
    case "$PV_KEY" in
      9|9a|9b)
        die "REFUSED — current: 9 is close-out's to write, with the Step 9 line (bash <plugin-root>/scripts/close-out.sh); the plan is unchanged."
        exit 1 ;;
    esac
    plan_verb_open current
    # THE CHECK-ONLY ADVANCE (wave-38 T1; D20, AC-1.3): `current <N> --check` runs current_admit, the advance's own
    # path up to its swap, in a subshell, and prints its verdict above whatever that path printed; it exits as the
    # advance would and writes nothing (the copies go with the trap, the judge's ledger write is not taken).
    if [ -n "$PV_CHECK" ]; then
      PV_CK_OUT="$(current_admit 2>&1)"; PV_CK_RC=$?
      if [ "$PV_CK_RC" -eq 0 ]; then
        say "current $PV_KEY --check: would advance"
        [ -z "$PV_CK_OUT" ] || printf '%s\n' "$PV_CK_OUT"
        cmp -s "$PV_NEW" "$PV_PLAN" && say "current — current: $PV_KEY: the plan already reads so; the advance would write nothing."
      else
        die "current $PV_KEY --check: would refuse"
        [ -z "$PV_CK_OUT" ] || printf '%s\n' "$PV_CK_OUT" >&2
      fi
      exit "$PV_CK_RC"
    fi
    current_admit
    plan_verb_swap current "current: $PV_KEY" "$PV_DRYMODE"
    say "current — current: $PV_KEY in $PV_PLAN (was ${PV_CUR:-none})$PV_FILLED; $PV_HOW."
    exit 0
  }

  # THE BASIS, ON ASK (wave-37 T8; D8, REQ-4 AC-4.2). `cover <question> <a>..<b>` prints, on stdout, the
  # `cover <sha> <basis>` lines `cover_basis` builds for that range and question, the ones `cur7_judge` prints under
  # its `review <question> … uncovered <a>..<b>` line, and ends that line by asking for. It writes nothing and asks
  # the judge nothing more: a range every commit of which holds prints no line, exit 0. A head that is no commit
  # here, or a plan the library cannot read, is the library's sentence on stderr and exit 1. Never called from the
  # tick or any wall.
  poker_verb_cover() {
    plan_verb_open cover
    COV_VERB_LINES="$(cover_basis "$PV_PLAN" "$COV_Q" "$COV_A" "$COV_B")"; COV_RC=$?
    [ "$COV_RC" -ne 2 ] || exit 1
    if [ -n "${COV_VERB_LINES}" ]; then
      printf '%s\n' "$COV_VERB_LINES"
    fi
    exit 0
  }
