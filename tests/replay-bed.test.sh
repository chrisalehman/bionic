#!/bin/bash
# tests/replay-bed.test.sh — the replay bed: closed runs replayed from tracked, scrubbed copies.
#
# The bed reads tests/fixtures/replay alone: version-14 copies of two closed runs and of one cut mid-run, and
# one expected key=value file per release card with the facts the record lost listed in `gaps`.
#
#   §TRACKED  every fixture is a tracked file, neither the bed nor the scrub names the project's own record
#             store, and the private-name scan passes over the fixtures.
#   §CARDS    for each card, the reader's answers at the card's instant equal its expected file less the gaps
#             list; the cut run is read as it stands, beside the hand-written lines.
#   §CATCH    a copy of the reader with the replace rule taken out, then the cancel rule, disagrees with a card.
#   §COVER    every question of the closed list is asked and none is refused, and every event type has a line.
#   §FOLLOWS  a review row's rendered brief starts its range at the reader's last review proof of its questions.
#   §OPEN     run_open asks the reader's step of a run with a log, whatever its plan's prose says; a run with
#             none is judged from its plan, so each closed fixture run reads closed and the cut run open.
#
# A CARD'S INSTANT. The reader answers a run as it stands, so a card's world holds as its run log the reader's
# own translation of the fixture up to the card's instant, in the translation's order: a line with no instant
# of its own stands where the translation put it. The cut run has no log, so it is translated as it is read.
#
# FIXTURE FIDELITY. The fixtures are real files but hand-written.log: the lines of the event types no closed
# run holds, in the landing record's own shapes, each marked fixture=hand-written. They join the cut run only.

set -uo pipefail
. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"
. "$(dirname "$0")/lib/world.sh"
R="$BIONIC_SCRIPTS_DIR"; F=tests/fixtures/replay; GIT="git -C $R"; X="$R/$F"
B='\.bio''nic/'

section "TRACKED"
for d in wave-46-asks-nothing wave-49-what-a-run-costs wave-49-mid; do
  expect_eq "$d: its plan and its landing record are tracked" "1 1" \
    "$($GIT ls-files "$F/$d" | grep -c '\.plan\.md$') $($GIT ls-files "$F/$d" | grep -c '/landing-proofs\.log$')"
done
expect_eq "one expected file per release card and the gaps list are tracked" "4 1" \
  "$($GIT ls-files "$F" | grep -c '/release-approval-\(93683c5e\|31da41f7\|fcbb975f\|f87acbfc\)\.facts$') $($GIT ls-files "$F/gaps" | wc -l | tr -d ' ')"
expect_eq "four card files, every expected line key=value, none empty" "4 0 0" \
  "$(ls "$X"/release-approval-*.facts | wc -l | tr -d ' ') $(cat "$X"/*.facts | grep -vc '^[A-Za-z][A-Za-z0-9.:_-]*=') $(find "$X" -name '*.facts' -size 0 | wc -l | tr -d ' ')"
expect_true "the scrub is a tracked file" $GIT ls-files --error-unmatch tests/lib/replay-scrub.sh
expect_empty "no fixture file is untracked" "$($GIT ls-files --others "$F")"
expect_empty "neither the bed nor the scrub names the project's own record store" \
  "$(grep -n "$B" "$R/tests/replay-bed.test.sh" "$R/tests/lib/replay-scrub.sh")"
# The list's path comes from the environment alone: the project's config sits in its own store, which the bed
# never reads, and the release check's declared scan admits the fixtures at every landing either way.
L="${BIONIC_NAME_LIST:-}"
if [ -r "$L" ]; then
  S="$(mktemp -d)"; cp -R "$X" "$S/"
  ( cd "$S" && export GIT_CONFIG_GLOBAL=/dev/null && git init -q && git add -A \
    && git -c user.name=fixture -c user.email=fixture@example.invalid commit -qm fixtures \
    && bash "$R/tests/lib/name-scan.sh" "$L" >"$S/scan.out" 2>&1 ); rc=$?
  expect_status "the private-name scan passes over every fixture" 0 "$rc"
  [ "$rc" -eq 0 ] || cat "$S/scan.out"
else
  advise "the private-name scan" "BIONIC_NAME_LIST names no readable list, so it is skipped and the release check alone admits the fixtures" false
fi

RD="$R/payload/scripts"   # the reader under test; §CATCH points it at a planted copy
ask() { bash "$RD/reader.sh" "$@"; }
events() { ( . "$RD/lib/reader.sh" && reader_events "$1" ); }
# A reader answer as the expected files' keys, by question: a value names its fact, a count stands for a list
# whose items the cards only count.
_PROJ='function f(k,   i, n, p) { n = split($0, p, "|"); for (i = 2; i <= n; i++) if (index(p[i], k "=") == 1) return substr(p[i], length(k) + 2); return "" }
  function ref(s) { sub(/^record\/[^\/]*\//, "", s); sub(/#/, ":", s); return s }
  { e = f("ev"); k = f("kind") }
  q == "proof" { print "proof." f("head") "." k (f("question") == "" ? "" : "." f("question")) "=" (k == "regression" ? "rc=" f("rc") : k == "review" ? f("result") "/" f("scope") : f("result") == "fail" ? "fail" : "pass") }
  q == "landed" { print "landed." f("row") "=" f("commit") }
  q == "asks" { print "asks." f("key") "=open" }
  q == "holds" { print "holds." f("key") "=" f("holds") }
  q == "findings" { print "finding." ref(f("ref")) "=" f("to") }
  q == "reviews" { print "reviews." f("head") "." f("question") "=" (e == "waiver" ? "waived" : f("result") "/" f("scope")) }
  q == "ledger" { print "ledger." f("d") "." f("verb") "=" f("at") }
  q == "debts" { print "debts." (e == "debt" ? f("concept") : e == "admitted" ? f("id") : ref(f("ref"))) "=" e }
  q == "verdicts" { c["verdicts." f("row") "." f("result")]++ }
  q == "hands" { c["hands." (e == "hand" ? f("what") : "by-hand")]++ }
  END { for (k in c) print k "=" c[k] }'
facts() {  # <plan> <expected file> -> the reader's answers over the plan's run, as the expected file's keys
  local p="$1" x="$2" k q
  { ask "$p" step | sed 's/^/step./'
    for q in approved green ready; do
      for k in $(sed -n "s/^$q\\.\\([^=]*\\)=.*/\\1/p" "$x"); do ask "$p" "$q" "$k" && echo "$q.$k=yes" || echo "$q.$k=no"; done
    done
    for k in $(sed -n 's/^status\.\([^=]*\)=.*/\1/p' "$x"); do q="$(ask "$p" status "$k" | sed -n 's/^state=//p')"; echo "status.$k=${q:-absent}"; done
    for k in $(sed -n 's/^proof\.\([0-9a-f]*\)\..*/\1/p' "$x" | sort -u); do ask "$p" proof "$k"; done | awk -v q=proof "$_PROJ"
    for q in landed asks holds findings reviews ledger debts verdicts hands; do ask "$p" "$q" | awk -v q="$q" "$_PROJ"; done
    ask "$p" order | sed '1!s/^/order./'; ask "$p" handoff | sed 's/^/handoff./'; ask "$p" stop | sed 's/^/stop./'
  } | LC_ALL=C sort
}
less() {  # <name> <run> -> stdin's key=value lines less each key the gaps list names for all, the run or the name
  awk -v n="$1" -v w="$2" 'NR == FNR { k = substr($0, 1, index($0, "=") - 1); s = substr(k, 1, index(k, ".") - 1)
      if (s == "all" || s == n || s == w) g[substr(k, length(s) + 2)] = 1; next }
    /^(card|cut)\.(at|head)=/ { next }
    { k = substr($0, 1, index($0, "=") - 1); for (p in g) if (k == p || index(k, p ".") == 1) next; print }' "$X/gaps" - | LC_ALL=C sort
}
cut_at() {  # <instant> -> stdin's events up to the first one timed after it
  awk -F'|' -v c="$1" '{ t = substr($NF, 4); if (t ~ /T[0-9][0-9]:[0-9][0-9]Z$/) t = substr(t, 1, 16) ":00Z" }
    t ~ /^[0-9-]+T[0-9:]+Z$/ && t > c { exit } { print }'
}
disagree() {  # -> `<name> <|> <key=value>` for each fact a world's expected file and the reader part on
  local e n w p
  for e in $WORLDS; do n=${e%%:*}; w=${e#*:}; p=${w#*:}; w=${w%%:*}
    diff <(less "$n" "$w" < "$X/$n.facts") <(facts "$p" "$X/$n.facts" | less "$n" "$w") | sed -n "s/^\([<>]\) /$n \1 /p"
  done
}

section "CARDS"
WORLDS=""
for x in "$X"/*.facts; do
  n="${x##*/}"; n="${n%.facts}"; w="$n"
  [ -d "$X/$w" ] || w="$(cd "$X" && ls -d */record/*/"$n.md" | cut -d/ -f1)"
  cp -R "$X/$w" "$WORLD_ROOT/$n"; p="$(ls "$WORLD_ROOT/$n"/plans/*/*.plan.md)"; at="$(sed -n 's/^card\.at=//p' "$x")"
  # The log is moved into place whole, since the reader reads a run that has one from it alone, even while
  # empty; the cut ends the translation early, so the pipe's status is not the move's condition.
  if [ -n "$at" ]; then events "$p" | cut_at "$at" > "$WORLD_ROOT/$n.log"; mv "$WORLD_ROOT/$n.log" "${p%/plans/*}/record/$(basename "$p" .plan.md)/run.log"
  else cat "$X/hand-written.log" >> "$WORLD_ROOT/$n/record/$(basename "$p" .plan.md)/landing-proofs.log"; fi
  WORLDS="$WORLDS $n:$w:$p"
done
D="$(disagree)"
for e in $WORLDS; do n=${e%%:*}; w=${e#*:}; p=${w#*:}; w=${w%%:*}
  expect_eq "$n: the reader answers as many facts as its expected file holds less the gaps" \
    "$(less "$n" "$w" < "$X/$n.facts" | wc -l | tr -d ' ')" "$(facts "$p" "$X/$n.facts" | less "$n" "$w" | wc -l | tr -d ' ')"
  expect_empty "$n: every answer equals its expected fact" "$(printf '%s\n' "$D" | grep "^$n ")"
done

section "CATCH"
for m in 'replace:s/if \(\(id in live\) && fact\[id\] == body\) next/if (id in live) next/' \
         'cancel:s/if \(t == "cancel"\) \{ delete live\[id\]; next \}/if (t == "cancel") next/'; do
  RD="$WORLD_ROOT/plant-${m%%:*}"; mkdir -p "$RD"; cp -R "$R/payload/scripts/reader.sh" "$R/payload/scripts/lib" "$RD/"
  perl -pi -e "${m#*:}" "$RD/lib/reader.sh"
  expect_false "the copy without the ${m%%:*} rule differs from the reader" cmp -s "$RD/lib/reader.sh" "$R/payload/scripts/lib/reader.sh"
  expect_regex "the copy without the ${m%%:*} rule still answers" '^n=[0-9]' "$(ask "${WORLDS##*:}" step)"
  expect_nonempty "the bed disagrees with the reader without the ${m%%:*} rule" "$(disagree | grep -vxF -- "$D")"
done
RD="$R/payload/scripts"

section "COVER"
QS="step approved proof green landed asks holds reviews ledger findings debts stop order hands status ready handoff verdicts header row criterion cell"
expect_eq "the bed asks each question of the closed list, and the list has no other" "$(printf '%s\n' $QS | sort | tr '\n' ' ')" \
  "$(ask /dev/null - 2>&1 | awk 'NR > 1 { print $1 }' | sort | tr '\n' ' ')"
for e in $WORLDS; do n=${e%%:*}; p=${e##*:}; h="$(sed -n 's/^proof\.\([0-9a-f]*\)\..*/\1/p' "$X/$n.facts" | head -1)"; r=""; c=0
  for q in $QS; do a=""
    case $q in approved) a=step0 ;; proof|green) a=${h:-0} ;; status|ready) a=T13 ;; row) a=T1 ;; criterion|cell) a=AC-1.1 ;; esac
    ask "$p" "$q" $a >/dev/null 2>&1; [ $? -eq 2 ] && r="$r $q" || c=$((c + 1))
  done
  expect_eq "$n: each question answers and none is refused" "$(printf "%s\n" $QS | wc -l | tr -d " ")" "$c$r"
done
P49="$(ls "$X"/wave-49-what-a-run-costs/plans/*/*.plan.md)"
expect_eq "header, row, criterion and cell answer from the closed plan" \
  "canonical_sdlc_version=14|id=T1|criterion=AC-7.3|state=discharged by=waiver" \
  "$(ask "$P49" header canonical_sdlc_version)|$(ask "$P49" row T1 | head -1)|$(ask "$P49" criterion AC-7.3 | grep '^criterion=')|$(ask "$P49" cell AC-7.3 | tr '\n' ' ' | sed 's/ $//')"
A="$WORLD_ROOT/all.events"; { for e in $WORLDS; do events "${e##*:}"; done; events "$P49"; events "$(ls "$X"/wave-46-asks-nothing/plans/*/*.plan.md)"; } > "$A"
TYPES="$(. "$RD/lib/log.sh" && printf '%s' "$LOG_TYPES")"; none=""; only=""
for t in $TYPES; do
  grep -q "^run/v1|ev=$t|" "$A" || none="$none $t"
  grep -q "^run/v1|ev=$t|" "$A" && [ "$(grep -c "^run/v1|ev=$t|" "$A")" = "$(grep "^run/v1|ev=$t|" "$A" | grep -c '|fixture=hand-written|')" ] && only="$only $t"
done
expect_empty "every event type has a fixture line" "$none"
expect_eq "the types no closed run holds a line of are the hand-written ones" " stalled admitted void decision debt abandon cancel" "$only"
expect_eq "every hand-written line is marked, and one is a dispatch" "$(grep -c . "$X/hand-written.log") 1" \
  "$(grep -c '[| ]fixture=hand-written[| ]' "$X/hand-written.log") $(grep -c '^line/v1|ev=dispatch|' "$X/hand-written.log")"
MID="$(ls "$WORLD_ROOT"/wave-49-mid/plans/*/*.plan.md)"
expect_contains "a hand-written refusal, which no type carries, is named on the gaps list" "gap/v1|ev=refusal|row=" \
  "$( ( . "$RD/lib/reader.sh" && reader_events "$MID" >/dev/null && translate "$MID" gaps ) )"

section "FOLLOWS"
# The brief follows the reader: over the closed run, a review row's rendered range starts where the reader's last
# review proof of its questions stands, and each row's Questions are its own. The run is a project's docs root here,
# its close line taken out of the copy: the verb renders for an open run only, and the range reads no step.
. "$(dirname "$0")/lib/bound-marker.sh"
FW="$WORLD_ROOT/brief"; FB="$FW/.bio""nic"; mkdir -p "$FB"; cp -R "$X/wave-49-what-a-run-costs" "$FB/docs"; git -C "$FW" init -q
FP="$(ls "$FB"/docs/plans/*/*.plan.md)"; FS=fe11a5e0-0000-4000-8000-000000000001; bound_marker "$FW" "$FS" "$FP"
sed '/^- Step 9: delivered: /d' "$FP" > "$FP.open" && mv "$FP.open" "$FP"
last() { ask "$FP" reviews | awk -F'|' -v q="question=$1" '$1 == "run/v1" && index($0, "|ev=proof|") && index($0 "|", "|" q "|") { h = $0; sub(/.*\|head=/, "", h); sub(/\|.*/, "", h) } END { print h }'; }
for r in T23:evidence T24:adversarial,structure; do id=${r%%:*}; q=${r#*:}
  ( cd "$FW" && CLAUDE_CODE_SESSION_ID=$FS bash "$R/hooks/session-poker.sh" brief "$id" "w49-$id" ) >/dev/null 2>&1
  expect_status "$id: the brief renders over the closed run" 0 "$?"
  h="$(last "${q%%,*}")"; expect_regex "$id: the reader holds a review proof of ${q%%,*}" '^[0-9a-f]{40}$' "$h"
  f="$FB/docs/record/wave-49-what-a-run-costs/briefs/w49-$id.md"
  expect_regex "$id: its range starts at that proof's head" "^Reviewed range: $h\\.\\." "$(grep '^Reviewed range' "$f")"
  expect_eq "$id: its Questions are the row's" "Questions: ${q//,/, }" "$(grep '^Questions:' "$f")"
done
# The step card follows the reader: a render opens the step's approval on the run's register only while the log holds
# no approval of it, so a cancel appended to the log reopens it though the plan's own approved-by: line still stands.
CW="$WORLD_ROOT/card"; CS=fe11a5e0-0000-4000-8000-000000000002; CP="$CW/.bio""nic/docs/plans/e/wave-98-cancel.plan.md"
mkdir -p "${CP%/*}" "$CW/.bio""nic/tmp"; git -C "$CW" init -q
printf -- '---\ncanonical_sdlc_version: 15\nscale: wave\n---\n\n## Goal\n\nThe card follows the log.\n\n## SDLC State\n\ncurrent: 0\napproved-by: Dana Fixture 2026-11-01T00:00Z "approved"\n' > "$CP"
bound_marker "$CW" "$CS" "$CP"
CL="$CW/.bio""nic/docs/record/wave-98-cancel"
logged() { ( . "$RD/lib/log.sh" && RUN_LOG="$CL/run.log" log_append "$@" ); }
logged step n=0 && logged approval key=step0 by=Dana
carded() { ( cd "$CW" && CLAUDE_CODE_SESSION_ID=$CS bash "$RD/card.sh" step0 "$CP" >/dev/null 2>&1 0<&- ) || echo "rc=$?"
  awk -F'|' '{ k = ""; s = ""; for (i = 1; i <= NF; i++) { if ($i ~ /^key=/) k = substr($i, 5); if ($i ~ /^state=/) s = substr($i, 7) } if (s == "open") print k }' "$CL/asks.state" 2>/dev/null; }
expect_true "card: the reader holds the logged approval of step0" ask "$CP" approved step0
expect_empty "card: while the log holds the approval, the render opens nothing" "$(carded)"
logged cancel of=approval key=step0
expect_false "card: the cancel retracts the approval in the reader" ask "$CP" approved step0
expect_eq "card: after the cancel the render opens the approval again, though the plan's approved-by: stands" "approve:step0" "$(carded)"
section "OPEN"
opened() { ( . "$RD/lib/run.sh" && run_open "$1" ); echo $?; }
plant() {  # <wave> <current:> <Step 9 line> [log line…] -> the plan's path; its run log holds the lines given
  local w="$1" p="$WORLD_ROOT/open/plans/e/$1.plan.md"; mkdir -p "${p%/*}" "$WORLD_ROOT/open/record/$w"
  printf -- '---\ncanonical_sdlc_version: 15\n---\n\n## SDLC State\n\ncurrent: %s\n%s\n' "$2" "$3" > "$p"; shift 3
  [ $# -eq 0 ] || printf '%s\n' "$@" > "$WORLD_ROOT/open/record/$w/run.log"
  printf '%s' "$p"
}
expect_eq "a run whose delivery is only its log's step 9 is closed, though its plan says current: 4" 1 \
  "$(opened "$(plant gone 4 '- Step 4: opened' 'run/v1|ev=step|n=9|at=2026-11-01T00:00:00Z')")"
expect_eq "a run whose log stands at step 8 is open, though its plan says current: 9" 0 \
  "$(opened "$(plant at9 9 '- Step 9: closing' 'run/v1|ev=step|n=8|at=2026-11-01T00:00:00Z')")"
expect_eq "a run whose log holds an abandon is closed" 1 \
  "$(opened "$(plant quit 6 '' 'run/v1|ev=step|n=6|at=2026-11-01T00:00:00Z' 'run/v1|ev=abandon|why=w|at=2026-11-01T00:00:01Z')")"
expect_eq "with no log, current: 9 and no delivery is open, and a delivered: Step 9 line closes it" "0 1" \
  "$(opened "$(plant v14 9 '- Step 9: closing')") $(opened "$(plant v14d 9 '- Step 9: delivered: 2026-11-01T00:00Z')")"
expect_eq "the closed fixture runs read closed and the cut run open" "1 1 0" "$(opened "$P49") $(opened "$(ls "$X"/wave-46-asks-nothing/plans/*/*.plan.md)") $(opened "$(ls "$X"/wave-49-mid/plans/*/*.plan.md)")"

finish
