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

# cur8_unruled [awaiting] -> the AC id of each criterion the advance to 8 finds unruled, one per line: walls.sh
# `matrix_unruled`, the commit gate's own reader and predicate (`matrix_row_ruled`) over the reader's answer, the
# evidence review read at the working head, asked in a subshell so nothing walls.sh defines outlives it. Never a second
# reading of the criteria here: the advance and every commit after it answer one row one way. With `awaiting`, only the
# ids that also await their person (`matrix_row_awaits`). rc 1 when the library cannot be had, 2 when the run's facts
# could not be read.
cur8_unruled() {
  [ -f "$BIONIC_LIB/walls.sh" ] || return 1
  ( . "$BIONIC_LIB/walls.sh" >/dev/null 2>&1 || exit 1
    declare -F matrix_unruled >/dev/null 2>&1 || exit 1
    matrix_unruled "$PV_PLAN" 8 "${PV_HEAD8:-}" "$@" )
}

# cur8_awaiting_line -> the printf format of the refusal's line for an unruled row that awaits its person, its one %s the
# criterion. THE ONE SPELLING of it: the release approval card (payload/scripts/card.sh `_card_settles`) reads this
# function from this file, so it settles the line by the words the judge prints, as it does `cur8_unapproved_line`.
cur8_awaiting_line() {
  printf '%s' "bionic: commit refused — %s awaits its person's confirmation (it is proved; its person confirms it at release: reply <n> confirm, <n> being the decision the release approval card gives it)"
}

# cur8_unruled_line <AC> -> the refusal's line for an unruled row: for a criterion in PV_AWAIT8, the ids
# `cur8_unruled awaiting` named, its person's confirmation (`cur8_awaiting_line`); for any other, the matrix arm's own
# fact, as a commit at current: 8 is refused with it. The release approval card settles either as `row:<AC>` whichever
# refusal names it.
cur8_unruled_line() {
  local fmt
  case $'\n'"${PV_AWAIT8:-}"$'\n' in
    *$'\n'"$1"$'\n'*)
      fmt="$(cur8_awaiting_line)"
      # shellcheck disable=SC2059  # the format is cur8_awaiting_line, whose only conversion is its one %s
      printf "$fmt" "$1"
      return 0 ;;
  esac
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
# WHENEVER THE PLAN HAS A ROW THAT INTEGRATES (lib/units.sh `units_integrates`), whatever its other rows, `current 8`
# asks besides that the newest `approved: release` line's head (lib/proof.sh `proof_approved_head`) is the working head,
# or one that only prose touching no release-set file follows (lib/proof.sh `proof_prose_past`): every run that reaches
# the merge stops at the release approval card, a run with no release row as one in the order build, regression,
# review, release (`units_order`). The whole run need not be at that head: the regression judge holds it covered past
# its run when every later commit is proved by the suites its row named. A plan with no row that integrates is asked no
# approval.
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

# cur8_unapproved_line -> the printf format of the refusal `current 8` prints while the release approval is missing, its
# three %s the order the plan is in with its regression row (empty for a plan with no release row), what is missing and
# the working head. THE ONE SPELLING of that refusal: the release approval card (payload/scripts/card.sh `_card_settles`) runs in a process of its own and reads
# this function from this file, so it settles the refusal by the words the judge prints, and a reworded refusal is
# reworded for both. The words are a printf format, so a percent sign in them is written as two.
cur8_unapproved_line() {
  printf '%s' "REFUSED — current: 8%s is admitted at the head the user approved for release, and %s; the user's word for the working head %s is approve release '<reply>'. The plan is unchanged."
}

# cur8_stale_line -> the printf format of the refusal `current 8` prints while the newest `approved:
# release` line names a head the working head has moved past with code or a release-set file, its two %s the working
# head and the approved one. THE ONE SPELLING of that refusal, read by the release approval card as
# `cur8_unapproved_line` is: a stale approval is the card's decision to renew, as a missing one is, so the card knows the
# refusal by these words and a reworded refusal is reworded for both.
cur8_stale_line() {
  printf '%s' "REFUSED — current: 8 is admitted at the head the user approved for release: the working head %s is not the head the user approved for release, %s, and a commit past it is code or a release-set file. Land only docs past the approval, or have the user approve this head (approve release '<reply>'). The plan is unchanged."
}

# cur8_approved_head -> returns when the newest `approved: release` line names the working head PV_HEAD8, or a head on its
# first-parent line past which nothing the approval covers changed (`proof_prose_past`); otherwise refuses `current 8`,
# exit 1, naming both heads, the plan unchanged.
cur8_approved_head() {
  local ah fmt missing order=""
  ah="$(proof_approved_head "$PV_PLAN" release 2>/dev/null)" || ah=""
  [ -z "$PV_ORDER" ] || order=" in the order (the regression row $PV_ORDER before review and the release)"
  if [ -z "$ah" ]; then
    missing="$PV_PLAN carries no approved: release line"
    ! proof_approved "$PV_PLAN" release || missing="the newest approved: release line names no head"
    fmt="$(cur8_unapproved_line)"
    # shellcheck disable=SC2059  # the format is cur8_unapproved_line, whose only conversions are its three %s
    die "$(printf "$fmt" "$order" "$missing" "$PV_HEAD8")"
    exit 1
  fi
  if [ "$ah" != "$PV_HEAD8" ] && ! proof_prose_past "$PV_PLAN" "$ah" "$PV_HEAD8"; then
    fmt="$(cur8_stale_line)"
    # shellcheck disable=SC2059  # the format is cur8_stale_line, whose only conversions are its two %s
    die "$(printf "$fmt" "${PV_HEAD8:0:12}" "${ah:0:12}")"
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
  PV_INTEG="$(units_integrates "$PV_PLAN" 2>/dev/null)" || PV_INTEG=""
  # THE RULING IS THE MERGE ADVANCE'S: at 8 every matrix row is ruled, or the advance is refused naming each one.
  local unruled="" ac
  if [ "$step" = 8 ] && ! unruled="$(cur8_unruled)"; then
    die "REFUSED — current: 8 is admitted only when every matrix row is ruled, and the matrix check (walls.sh matrix_unruled) cannot be loaded from $BIONIC_LIB or the run's facts could not be read; the plan is unchanged."
    exit 2
  fi
  # Who is awaited is the line's words only: a predicate that cannot be asked leaves the line as it was and the verdict where it is.
  PV_AWAIT8=""
  [ -z "$unruled" ] || PV_AWAIT8="$(cur8_unruled awaiting 2>/dev/null)" || PV_AWAIT8=""
  out="$(facts_state "$PV_PLAN" "$PV_HEAD8" 2>"$PV_NEW.judge")"; rc=$?
  err="$(cat "$PV_NEW.judge" 2>/dev/null)"; rm -f "$PV_NEW.judge"
  # The check-only advance (`current <N> --check`; wave-38 T1, D20) takes this judgment and not its ledger write.
  if [ "$rc" -ne 2 ] && [ -z "${PV_CHECK:-}" ]; then
    if [ "$step" = 8 ]; then cur8_owed_waivers "$out" "$unruled"; else cur8_owed_waivers "$out"; fi
  fi
  # THE APPROVAL IS ASKED LAST, once every other fact the run owes holds: it is the person's last stop, and asked
  # first its refusal would hide the facts behind it from the release card's check of what it can settle.
  if [ "$rc" -eq 0 ] && [ -z "$unruled" ]; then
    [ "$step" != 8 ] || [ -z "$PV_INTEG" ] || cur8_approved_head
    return 0
  fi
  for ac in $unruled; do printf '%s\n' "$(cur8_unruled_line "$ac")" >&2; done
  if [ "$rc" -eq 0 ]; then
    die "current: 8 waits on a ruling of each row above; settle each on the release approval card, or waive it with waive <AC> '<their words>'. The plan is unchanged."
    exit 1
  fi
  if [ "$rc" -eq 2 ]; then
    die "REFUSED — current: $step is admitted on the facts the run owes, and the judge could not deal this plan (facts_state exit 2); the plan is unchanged. The judge said:"
    [ -z "$err" ] || printf '%s\n' "$err" >&2
    [ -z "$out" ] || printf '%s\n' "$out" >&2
    exit 1
  fi
  # THE EXIT IS THE STEP'S: facts_state knows no step, so its unproved regression line carries the release card's reply.
  # At 7 no card can exist yet, so the line is printed again with the one printer's exit for 7; every other line stays.
  if [ "$step" = 7 ]; then
    out="$(printf '%s\n' "$out" | awk -F'\t' -v OFS='\t' -v x="$(proof_unproved_needs "$PV_PLAN" "$PV_REPO" "$PV_HEAD8" 7)" \
      '$1 == "regression" && $2 == "unproved" && NF == 4 { $4 = x } { print }')"
  fi
  die "REFUSED — current: $step is admitted only when every fact the run owes holds at the working head $PV_HEAD8, and these do not (facts_state):"
  # THE BASIS UNDER THE LINE: a `review <q> … uncovered <a>..<b>` line is a judge's "no" with no why; under it go the
  # `cover <sha> <basis>` lines for that range and question. The text above is the refusal's own and does not change.
  local cv_line cv_k cv_q cv_rest cv_st cv_rng
  while IFS= read -r cv_line; do
    [ -n "$cv_line" ] || continue
    IFS='	' read -r cv_k cv_q cv_rest cv_rest cv_st cv_rng <<COVER_LINE
$cv_line
COVER_LINE
    case "$cv_k:$cv_st:$cv_rng" in
      review:uncovered:?*..?*)
        printf '%s\n' "$cv_line" >&2
        cover_basis "$PV_PLAN" "$cv_q" "${cv_rng%%..*}" "${cv_rng##*..}" >&2 || : ;;
      *) printf '%s\n' "$cv_line" >&2 ;;
    esac
  done <<COVER_JUDGED
$(printf '%s\n' "$out" | awk -F'\t' '$NF != "covered"')
COVER_JUDGED
  die "Take the review or the regression run each line names and record it with proof-add, or have the user waive a question with waive <question> '<reply>'; the plan is unchanged. A red suite of the whole run is a fix row's: its own suites plus the red one."
  exit 1
}

# current_admit -> everything `current <N>` asks before it appends: the commit gate on the plan itself with the step it
# moves to pending (hooks/session-poker.sh `plan_verb_dry`), and the facts judge at 7 and 8. Sets PV_HOW; exits on every refusal in
# the advance's own words and code. THE ONE PATH: the advance calls it and then appends; `current <N> --check` calls it
# and stops, so the two cannot answer differently. Step 8 is admitted on the judge alone (lib/proof.sh `facts_state`),
# since what the gate asks at 8 is the close's to give, and close-out judges it itself; Step 7 asks the gate and then the
# judge, so a refusal a real commit at 7 would meet is met here in the gate's own words.
current_admit() {
  PV_HOW="judged at that step first"
  case "$PV_KEY" in
    8|8a|8b) ;;
    # A run already at the step is judged at 8 alone, on the facts; below it there is no move to judge.
    *) [ "$PV_CUR" != "$PV_KEY" ] || return 0 ;;
  esac
  case "$PV_KEY" in
    7)
      plan_verb_dry current "current: $PV_KEY" "$PV_KEY"
      cur7_judge 7
      PV_HOW="judged at that step first; every fact the run owes holds at $PV_HEAD8 (facts_state)" ;;
    8|8a|8b)
      cur7_judge 8
      PV_HOW="every fact the run owes holds at $PV_HEAD8 (facts_state)"
      [ -z "$PV_INTEG" ] || PV_HOW="$PV_HOW, the head the user approved for release" ;;
    *) plan_verb_dry current "current: $PV_KEY" "$PV_KEY" ;;
  esac
}
  # THE STEP MOVE. A step is an event in the run's log and nothing writes it into the plan: the advance asks what a
  # commit at the step it moves to would be asked (current_admit), then appends the step through its one writer
  # (lib/proof.sh `proof_step_event`). The plan's bytes are the same before and after. Step 9 is close-out's.
  poker_verb_current() {
    case "$PV_KEY" in
      9|9a|9b)
        die "REFUSED — step 9 is close-out's to take, with its delivery (bash <plugin-root>/scripts/close-out.sh); nothing was appended."
        exit 1 ;;
    esac
    plan_verb_open current
    if [ -n "${PV_CUR_UNREAD:-}" ]; then
      die "REFUSED — the step of $PV_PLAN could not be read (the run's facts did not fold), so the advance is judged from no step; nothing was appended. run again: session-poker.sh current $PV_KEY, once the fold's own line above is mended."
      exit 2
    fi
    # THE CHECK-ONLY ADVANCE: `current <N> --check` runs current_admit, the advance's own path up to its append, in a
    # subshell, and prints its verdict above whatever that path printed; it exits as the advance would and appends nothing.
    if [ -n "$PV_CHECK" ]; then
      PV_CK_OUT="$(current_admit 2>&1)"; PV_CK_RC=$?
      if [ "$PV_CK_RC" -eq 0 ]; then
        say "current $PV_KEY --check: would advance"
        [ -z "$PV_CK_OUT" ] || printf '%s\n' "$PV_CK_OUT"
        [ "$PV_CUR" != "$PV_KEY" ] || say "current — the run already stands at step $PV_KEY; the advance would append nothing."
      else
        die "current $PV_KEY --check: would refuse"
        [ -z "$PV_CK_OUT" ] || printf '%s\n' "$PV_CK_OUT" >&2
      fi
      exit "$PV_CK_RC"
    fi
    current_admit
    if [ "$PV_CUR" = "$PV_KEY" ]; then
      say "current — the run already stands at step $PV_KEY; nothing was appended."
      exit 0
    fi
    if ! proof_step_event "$PV_PLAN" "$PV_KEY"; then
      die "REFUSED — step $PV_KEY could not be appended to the run's log of $PV_PLAN; nothing was appended."
      exit 2
    fi
    say "current — step $PV_KEY appended to the run's log (was ${PV_CUR:-none}); $PV_PLAN is unchanged; $PV_HOW."
    exit 0
  }

