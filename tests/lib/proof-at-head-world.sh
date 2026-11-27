# tests/lib/proof-at-head-world.sh — THE FULL PASS AT A HEAD: the close-out project with a whole run at F and the
# landings since, and the readers of the state each surface prints
#
#     . "$(dirname "$0")/lib/proof-at-head-world.sh"
#
# tests/proof-at-head.test.sh holds what the surfaces print over this world; the release card's and the continuation's
# own suites draw their surface over the same world by loading this file. pah_world stands on the close-out fixture,
# loaded here when the caller has not loaded it.
#
# THE CALLER SETS PAH_LIB (the payload/scripts/lib the proof writers come from), PAH_POKER (the poker pah_poke runs)
# and what the close-out fixture reads (tests/lib/close-out-fixture.sh); each is read when a builder runs.

declare -F mk_fixture >/dev/null 2>&1 || { [ -r "${BASH_SOURCE[0]%/*}/close-out-fixture.sh" ] && . "${BASH_SOURCE[0]%/*}/close-out-fixture.sh"; } \
  || { echo "proof-at-head-world.sh: cannot load ${BASH_SOURCE[0]%/*}/close-out-fixture.sh" >&2; return 1; }

# pah_world <label> <owed suites, comma-joined, or empty> <landings> -> PAH_P, PAH_PLAN, PAH_F (the whole run's head)
# and PAH_H (the working head): the close-out fixture at Step 8 with a whole run at F that left <owed> red, then
# <landings> code landings, landing k greening the owed suites at positions k, k + <landings>, …; with landings the
# integration branch takes the working branch, the readings move to H and the run carries the word to merge at H.
# The page is at 15, where the proof, the readings' head and the word are the run's log's events, each by its writer.
pah_world() {
  local label="$1" owed="$2" n="${3:-0}" p plan w k i s su c log
  p="$(mk_fixture "$label")" || return 1
  advance_to "$p" 8
  plan="$p/$PLAN_REL"; w="$p-wave"
  PAH_F="$(fixture_git "$p" rev-parse wave/01-fixture)"
  log="$p/$LOG_REL"
  sed '/|ev=proof|kind=regression|/d' "$log" > "$log.n" && mv "$log.n" "$log"
  seal_fixture "$plan" "$log"
  bash -c '. "$1/run.sh" && . "$1/proof.sh" || exit 1
    LOG_AT=2026-10-04T12:00:00Z proof_event "$2" kind=regression "head=$3" "evidence=record/wave-01-fixture/regression-run-$3.log" ${4:+"owed=$4"}' \
    _ "$PAH_LIB" "$plan" "$PAH_F" "$owed" || return 1
  k=1
  while [ "$k" -le "$n" ]; do
    su=""; i=0
    for s in ${owed//,/ }; do
      [ $(( i % n + 1 )) -ne "$k" ] || su="$su${su:+,}$s"
      i=$((i + 1))
    done
    printf 'T%d\n' "$((k + 2))" >> "$w/land-$k.txt"
    fixture_git "$w" add "land-$k.txt" && fixture_git "$w" commit -qm "T$((k + 2)): a fix" || return 1
    c="$(fixture_git "$w" rev-parse HEAD)"
    {
      printf 'run/v1|ev=ready|row=T%d|name=w-T%d|commit=%s|branch=wt/01-T%d|tree=%s|suites=%s|debt=-|carrier=1:x|at=2026-10-04T13:%02d:00Z\n' \
        "$((k + 2))" "$((k + 2))" "$c" "$((k + 2))" "$w" "${su:-a.test.sh}" "$((k * 10))"
      for s in ${su//,/ }; do
        printf 'run/v1|ev=verdict|row=T%d|commit=%s|suite=%s|result=green|log=/rec/T%d-%s.log|at=2026-10-04T13:%02d:30Z\n' \
          "$((k + 2))" "$c" "$s" "$((k + 2))" "$s" "$((k * 10))"
      done
      printf 'run/v1|ev=published|row=T%d|commit=%s|kind=queue|by=-|why=-|at=2026-10-04T13:%02d:50Z\n' "$((k + 2))" "$c" "$((k * 10))"
    } >> "$log"
    k=$((k + 1))
  done
  seal_fixture "$plan" "$log"
  PAH_H="$(fixture_git "$p" rev-parse wave/01-fixture)"
  if [ "$n" -gt 0 ]; then
    fixture_git "$p" merge -q --no-ff -m "merge wave" wave/01-fixture >/dev/null 2>&1 || return 1
    # The landings cover the head and no pass ran at it, so the merge close-out delivers is the person's word at H.
    sed "s/|ev=proof|kind=review|head=$PAH_F|/|ev=proof|kind=review|head=$PAH_H|/" "$log" > "$log.n" && mv "$log.n" "$log"
    seal_fixture "$plan" "$log"
    bash -c '. "$1/run.sh" && . "$1/proof.sh" || exit 1
      LOG_AT=2026-10-04T14:00:00Z proof_approval_event "$2" merge-unproved by=fixture "head=$3" "said=merge it"' \
      _ "$PAH_LIB" "$plan" "$PAH_H" || return 1
  fi
  PAH_P="$p"; PAH_PLAN="$plan"
}

# pah_poke <project> <sid> <verb> [<arg>...] -> PAH_OUT, PAH_RC: the real poker verb in the project, as that session.
pah_poke() {
  local p="$1" sid="$2"; shift 2
  ( in_fixture "$p" || exit 9
    HOME="$SB_HOME" CLAUDE_PROJECT_DIR="" BIONIC_CLAUDE_HOME="$SB_HOME/.claude" CLAUDE_CODE_SESSION_ID="$sid" \
      bash "$PAH_POKER" "$@" ) > "$SANDBOX/pah-poker" 2>&1
  PAH_RC=$?; PAH_OUT="$(cat "$SANDBOX/pah-poker")"
}

# THE THREE EXTRACTORS, one per surface, each printing the state the surface states and nothing else.
# pah_card_state <card> -> the state after `whole suite: ` on the Tests line, its folded lines joined.
pah_card_state() {
  printf '%s\n' "$1" | awk '
    on && /^   [^ ]/ { s = s " " substr($0, 4); next }
    on { exit }
    { i = index($0, "whole suite: ") }
    i { s = substr($0, i + 13); on = 1 }
    END { print s }'
}
# pah_score_state <scorecard> -> the state after `whole run ` on the correctness line, to its `; `.
pah_score_state() {
  printf '%s\n' "$1" | awk 'index($0, "correctness: ") == 1 { i = index($0, "; whole run "); if (!i) exit
    s = substr($0, i + 12); j = index(s, "; "); print (j ? substr(s, 1, j - 1) : s); exit }'
}
# pah_cont_state <continuation file> -> the state after `the regression: whole suite ` in its header, to ` (proved`.
pah_cont_state() {
  awk '{ i = index($0, "the regression: whole suite "); if (!i) next
    s = substr($0, i + 28); j = index(s, " (proved"); print (j ? substr(s, 1, j - 1) : s); exit }' "$1" 2>/dev/null
}
