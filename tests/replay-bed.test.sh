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
#   §FOLLOWS  a review row's rendered brief starts its range at the reader's last review proof of its questions,
#             and a step card asks again for an approval a cancel appended to the run's log retracted.
#   §OPEN     run_open asks the reader's step of a run with a log, whatever its plan's prose says; a run with
#             none is judged from its plan, so each closed fixture run reads closed and the cut run open.
#   §FOLLOWS-CONTINUATION  close-out's check reads a debt only the run's log holds into its debt line and Deferrals.
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
expect_contains "a hand-written refusal is an act taken by hand: a hand event that says it was a refusal" "|ev=hand|what=refusal|row=T14|" \
  "$(events "$MID")"

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
# The sheet follows the reader: a copy of the closed run whose log is its own translation and three facts its plan
# and record never held, its Step 9 retracted, a decision put and a review read; the sheet prints all three.
SW="$WORLD_ROOT/sheet"; mkdir -p "$SW/.bio""nic"; cp -R "$X/wave-49-what-a-run-costs" "$SW/.bio""nic/docs"; git -C "$SW" init -q
SP="$(ls "$SW"/.bio*/docs/plans/*/*.plan.md)"; SL="${SP%/plans/*}/record/wave-49-what-a-run-costs/run.log"
{ events "$SP"; printf 'run/v1|ev=%s|at=2026-11-08T00:0%dZ\n' "cancel|of=step|n=9" 0 "decision|d=D90|verb=put|by=orchestrator|title=Only the log holds it" 1 \
  "proof|kind=review|head=$(printf 'e%.0s' {1..40})|question=evidence|reader=w-T99|result=pass|scope=whole|evidence=record/x/log-only.md" 2; } > "$SL.t"; mv "$SL.t" "$SL"
sheet="$(cd "$SW" && TZ=America/Los_Angeles BIONIC_NOW_EPOCH=1794300000 bash "$R/hooks/session-poker.sh" sitrep "$SP" 2>/dev/null)"
expect_contains "the sheet over the logged run names the run" "run.name: wave-49-what-a-run-costs" "$sheet"
expect_eq "its step is the log's, Step 9 retracted, not the plan's current:" "run.step: 8" "$(printf '%s\n' "$sheet" | grep '^run.step: ')"
expect_contains "a decision only the log puts is an ask" "ask: key=decide:D90 " "$sheet"
expect_contains "a review only the log holds is a review line" "review: question=evidence scope=whole result=pass " "$(printf '%s\n' "$sheet" | grep 'record=record/x/log-only.md')"
# The tick follows it too: in the same run, now with a log, a fact the log alone holds changes the tick's fill line.
# Each tick forgets the last one's digest, which would otherwise print only that nothing changed.
FL="$FB/docs/record/wave-49-what-a-run-costs/run.log"; events "$FP" > "$FW/run.log"; mv "$FW/run.log" "$FL"
nofill() { rm -f "$FB"/tmp/tick-digest-*; ( cd "$FW" && CLAUDE_CODE_SESSION_ID=$FS bash "$R/hooks/session-poker.sh" tick 2>&1 ) | grep -m1 '^poker: no FILL — '; }
( cd "$FW" && CLAUDE_CODE_SESSION_ID=$FS bash "$R/hooks/session-poker.sh" arm ) >/dev/null 2>&1
expect_regex "the tick over the logged run fills nothing, every row landed" '^poker: no FILL — width=' "$(nofill)"
sed '/^approved-by: /d' "$FP" > "$FP.t" && mv "$FP.t" "$FP"
expect_regex "an approval only the log holds is the run's Step-3 approval to the tick" '^poker: no FILL — width=' "$(nofill)"
printf 'run/v1|ev=order|act=given|said=hold the run|at=2026-11-10T00:00:00Z\n' >> "$FL"
expect_eq "an order only the log holds holds the tick's fill" \
  'poker: no FILL — an order of the user stands: given 2026-11-10T00:00:00Z "hold the run"; order lift ends it' "$(nofill)"
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
# The landing report and the release note follow the reader: a landing only a run's log holds, with no landing
# record beside it, is counted by the report and rendered in the note, and the note's cut drops a later landing.
NW="$WORLD_ROOT/note"; NP="$NW/.bio""nic/docs/plans/e/w9.plan.md"; NR="$NW/.bio""nic/docs/record/w9"; mkdir -p "${NP%/*}" "$NR"
printf -- '---\ncanonical_sdlc_version: 15\n---\n\n## SDLC State\n\ncurrent: 4\n' > "$NP"; git -C "$NW" init -q
git -C "$NW" -c user.name=fixture -c user.email=fixture@example.invalid commit -q --allow-empty -m w9; NC="$(git -C "$NW" rev-parse HEAD)"
printf 'run/v1|ev=%s|row=T%s|commit=%s|%sat=2026-11-01T00:0%s:00Z\n' ready 1 "$NC" 'suite=a.test.sh|' 0 published 1 "$NC" 'kind=queue|' 3 \
  ready 2 "$NC" 'suite=a.test.sh|' 4 published 2 "$NC" 'kind=hand|' 6 > "$NR/run.log"
note() { ( cd "$NW" && BIONIC_GATE_DIR="$NW/gate" bash "$R/hooks/session-poker.sh" "$@" "$NP" 2>&1 ); }
expect_contains "the report counts the log's landings" "landings: queue=1 hand=1 git=0 · ready-to-landed median=3.0m" "$(note landing-report --rows)"
expect_contains "…and prints the queue landing's row" "T1 queue ready=2026-11-01T00:00:00Z landed=2026-11-01T00:03:00Z minutes=3.0" "$(note landing-report --rows)"
NN="$(note release-note --at "$NC" --on 2026-11-01T00:05:00Z)"
expect_contains "the note at an instant renders the landing the log holds before it" "landings: queue=1 hand=0 git=0" "$NN"
expect_eq "…and not the one after it" "0" "$(printf '%s\n' "$NN" | grep -c '^T2 ')"
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

section "FOLLOWS-CONTINUATION"
# The second closed fixture run reopened at Step 8, its log its own translation, then that log and a debt only the log holds.
CW="$WORLD_ROOT/close"; CB="$CW/.bio""nic"; mkdir -p "$CB/tmp"; cp -R "$X/wave-49-what-a-run-costs" "$CB/docs"; git -C "$CW" init -q
CP="$(ls "$CB"/docs/plans/*/*.plan.md)"; CR="$CB/docs/record/$(basename "$CP" .plan.md)"
printf 'archive-root: %s\n' "$(sed -n 's/^archive-root: *//p' "$CP" | head -1)" > "$CB/config.yaml"
sed -e '/^- Step 9: delivered: /d' -e 's/^current: 9$/current: 8/' "$CP" > "$CP.open" && mv "$CP.open" "$CP"
printf '# continuation\n\n## Deferrals\n' > "$CR/continuation.md"
events "$CP" > "$CW/own.log"; mv "$CW/own.log" "$CR/run.log"
closecheck() { ( cd "$CW" && env -u CLAUDE_CODE_SESSION_ID HOME="$CW/home" CLAUDE_PROJECT_DIR="" BIONIC_PLUGIN_ROOT="$R/payload" \
  BIONIC_CLAUDE_HOME="$CW/home/.claude" bash "$RD/close-out.sh" "$CP" check 2>&1 ); }
C0="$(closecheck)"
expect_eq "the reopened run reads at step 8, and its own log carries no debt" "step: current: 8|debt: touched 0 · burned 0" \
  "$(printf '%s\n' "$C0" | grep -m1 '^step: ')|$(printf '%s\n' "$C0" | grep -m1 '^debt: ')"
printf 'run/v1|ev=debt|concept=follow_x|kind=duplicate|sites=lib/f.sh:1|raised-by=record/x.md|touches=3|at=\n' >> "$CR/run.log"
C1="$(closecheck)"
expect_eq "a debt the log alone holds is counted on the card's debt line" "debt: touched 3 · burned 0" "$(printf '%s\n' "$C1" | grep -m1 '^debt: ')"
expect_contains "…and the continuation would carry it under ## Deferrals" " follow_x" "$(printf '%s\n' "$C1" | grep -m1 '^continuation: ')"
expect_contains "the log without it carries the run's own deferrals there" "under ## Deferrals: record/" "$(printf '%s\n' "$C0" | grep -m1 '^continuation: ')"
expect_absent "…and not that debt" " follow_x" "$(printf '%s\n' "$C0" | grep -m1 '^continuation: ')"

finish
