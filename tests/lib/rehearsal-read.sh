# Readers shared by the rehearsal suites (tests/rehearsal*.test.sh): each plays one run state through
# tests/lib/rehearsal.sh `rehearse`, then reads the sandbox's own sheet and card through the sandbox's own poker.
# Sourced after assert.sh, resolve-roots.sh, rehearsal.sh, world.sh and lib/width.sh; it defines functions and
# declares the measured keys, and runs nothing. A suite calls rt_true_state and rt_facts_state over the one state it
# rehearsed, so every state is read by the same checks wherever it is rehearsed.

# rt_state <state> -> RT_RC, RT_PLAN, RT_ROOT, RT_LOG of `rehearse <state>` into its own directory under WORLD_ROOT
rt_state() {
  RT_RC=0; RT_PLAN=""; RT_ROOT=""; RT_LOG="$WORLD_ROOT/$1/rehearsal.log"
  if [ "$RH_LOADED" = 1 ]; then
    RT_PLAN="$(rehearse "$1" "$WORLD_ROOT/$1" 2> "$WORLD_ROOT/$1.err")" || RT_RC=$?
  else
    RT_RC=127
  fi
  RT_ROOT="${RT_PLAN%/.bionic/docs/plans/*}"
  [ "$RT_RC" = 0 ] || { printf '    rehearse %s said:\n' "$1"; sed 's/^/    | /' "$WORLD_ROOT/$1.err" 2>/dev/null | tail -25; }
}
# rt_poker <args…> [stdin] -> RT_OUT, RT_ERR, RT_PRC of the sandbox's own poker, run from its root as the bound session
rt_poker() {
  RT_PRC=0
  ( cd "$RT_ROOT" && exec env CLAUDE_CODE_SESSION_ID="$WORLD_SID" bash "$RT_ROOT/hooks/session-poker.sh" "$@" ) \
    > "$WORLD_ROOT/rt.out" 2> "$WORLD_ROOT/rt.err" || RT_PRC=$?
  RT_OUT="$(cat "$WORLD_ROOT/rt.out")"; RT_ERR="$(cat "$WORLD_ROOT/rt.err")"
}
rt_asks() { printf '%s\n' "$1" | sed -n 's/^ask: key=\([^ ]*\) .*/\1/p' | LC_ALL=C sort | paste -sd' ' -; }   # <sheet>
# <sheet> -> each ask as <key>><what it holds>, sorted, space-joined
rt_holds() { printf '%s\n' "$1" | sed -n 's/^ask: key=\([^ ]*\) holds=\(.*\) title=.*/\1>\2/p' | LC_ALL=C sort | paste -sd' ' -; }
rt_ran() { /usr/bin/grep -c -F -- "$1" "$RT_LOG" 2>/dev/null; }   # <command text> -> how many logged commands hold it
# rt_m <sheet> <key> -> a measured line's value alone, the part before its ` — `
rt_m() { printf '%s\n' "$1" | awk -v k="$2: " 'index($0, k) == 1 { v = substr($0, length(k) + 1); i = index(v, " — "); print (i ? substr(v, 1, i - 1) : v); exit }'; }   # <sheet> <key>
# rt_judgment <sheet> -> a judgment in the card's grammar written from the sheet: the seven lines. The purpose is the
# sheet's run.goal, else a plain sentence; the call has two arms; one point; one `ask <key>:` for each ask whose line
# waits on the user (or names no wait), since the card counts the ones that wait on events; the predicted close. Code
# draws every other row, so the judgment writes none of them.
rt_judgment() {
  printf '%s\n' "$1" | awk '
    function val(f, nxt,   s, r, e) {
      s = index($0, " " f "="); if (!s) return ""
      r = substr($0, s + length(f) + 2)
      if (nxt != "") { e = index(r, " " nxt "="); if (e) r = substr(r, 1, e - 1) }
      return r
    }
    /^run\.goal: / { goal = substr($0, 11); next }
    /^[a-z][a-z.-]*: / && index($0, " — ") { k = substr($0, 1, index($0, ": ") - 1); v = substr($0, index($0, ": ") + 2); mv[k] = substr(v, 1, index(v, " — ") - 1) }
    /^close\.predicted: / { pr = mv["close.predicted"]; next }
    /^ask: / { w = $0; $0 = " " substr($0, 6)
      if (w ~ / waits=event/) next
      na++; ak[na] = val("key", "holds"); ah[na] = val("holds", "title"); next }
    END {
      print "purpose: " ((goal == "") ? "the run ships its rows; on course" : goal)
      if (na) print "call: Answer what the run waits on, below."; else print "call: Nothing is owed: let the build land."
      print "grade: B"; print "point: The run moved through its own commands to this state."
      for (i = 1; i <= na; i++) print "ask " ak[i] ": The ask that holds " ah[i] " — recommend the default"
      print "close: " ((pr == "" || pr == "-") ? "No close predicted yet" : pr) ", if the next command lands first time."
    }'
}
rt_wide() {  # <text> -> each line wider than BIONIC_LINE_WIDTH columns, as `<columns>: <line>`
  local l
  while IFS= read -r l; do
    _bionic_cols_into "$l"
    [ "$BIONIC_COLS" -le "$BIONIC_LINE_WIDTH" ] || printf '%s: %s\n' "$BIONIC_COLS" "$l"
  done <<< "$1"
}
# rt_sheet_and_card <label> <want asks> <want holds> <drop key|""> -> the sheet, the card and the refusal of one state
rt_sheet_and_card() {
  local lb="$1" want="$2" holds="$3" drop="$4" asks j lab
  rt_poker sitrep "$RT_PLAN"
  expect_eq "$lb-2 the sandbox's poker prints the sheet (exit 0)" "0|yes" \
    "$RT_PRC|$(printf '%s\n' "$RT_OUT" | head -1 | /usr/bin/grep -q '^sheet/v1' && echo yes)"
  asks="$(rt_asks "$RT_OUT")"
  expect_eq "$lb-3 the sheet's ask: lines are exactly the state's asks" "$want" "$asks"
  [ -z "$want" ] || expect_eq "$lb-3a …each holding the row that reads it" "$holds" "$(rt_holds "$RT_OUT")"
  [ -n "$want" ] || expect_eq "$lb-3b …the same sheet read line by line: its tasks are there, and no ask: line" "yes|0" \
    "$([ "$(printf '%s\n' "$RT_OUT" | /usr/bin/grep -c '^task: ')" -ge 1 ] && echo yes)|$(printf '%s\n' "$RT_OUT" | /usr/bin/grep -c '^ask: ')"
  j="$(rt_judgment "$RT_OUT")"
  rt_poker sitrep card "$RT_PLAN" <<< "$j"
  expect_eq "$lb-4 a judgment naming every open ask renders the card (exit 0, nothing on stderr)" "0|" "$RT_PRC|$RT_ERR"
  expect_eq "$lb-4b …the card's head and its Blocked on you section" "yes|yes" \
    "$(printf '%s\n' "$RT_OUT" | head -1 | /usr/bin/grep -q '^Sitrep · ' && echo yes)|$(printf '%s\n' "$RT_OUT" | /usr/bin/grep -qx '  Blocked on you' && echo yes)"
  expect_eq "$lb-5 every line of the card is at most $BIONIC_LINE_WIDTH columns (it has $(printf '%s\n' "$RT_OUT" | wc -l | tr -d ' ') lines)" \
    "" "$(rt_wide "$RT_OUT")"
  if [ -n "$drop" ]; then
    # An ask the judgment leaves out is repaired, never refused: the card draws it alone, its title then ` · holds <label>`.
    lab="$(printf '%s\n' "$holds" | tr ' ' '\n' | sed -n "s|^$drop>||p")"
    rt_poker sitrep card "$RT_PLAN" <<< "$(printf '%s\n' "$j" | /usr/bin/grep -v -F "ask $drop: ")"
    expect_eq "$lb-6 a judgment that drops $drop still draws (exit 0): the ask is drawn alone, with what it holds" "0|yes" \
      "$RT_PRC|$(printf '%s\n' "$RT_OUT" | /usr/bin/grep -qF -- " · holds $lab" && echo yes)"
    expect_nonempty "$lb-6b …naming what it holds (the label $drop>$lab was read from the state's holds)" "$lab"
  else
    rt_poker sitrep card "$RT_PLAN" <<< "$(printf '%s\nask decide:D9: a decision nobody put — recommend 1\n' "$j")"
    expect_eq "$lb-6 a judgment naming an ask the register lacks is refused: exit 1, stdout empty" "1|" "$RT_PRC|$RT_OUT"
    expect_contains "$lb-6b …the reason naming the key on stderr" "decide:D9" "$RT_ERR"
  fi
}

rt_elapsed_min() {  # <sheet> -> the minutes clock.elapsed says have passed since the approval, nothing when it names none
  rt_m "$1" clock.elapsed | /usr/bin/grep -E '^[0-9]' \
    | awk '{ m = 0; for (i = 2; i <= NF; i++) { if ($i == "h") m += $(i - 1) * 60; if ($i == "min") m += $(i - 1) } print m }'
}
rt_taskline() { printf '%s\n' "$1" | /usr/bin/grep "^task: id=$2 "; }   # <sheet> <id> -> its task line

RT_MEASURED="clock.now clock.approved clock.forecast clock.elapsed clock.elapsed-share work.planned work.added work.dropped work.landed work.left work.width work.task-time pace.time-used pace.work-landed close.chain close.predicted close.unscaled close.waits-on-you tests.suites-run tests.suites-total tests.whole-run reviews findings.open waste.dropped waste.runs-discarded waste.ready-unstarted waste.waiting-on-you"
rt_unlabelled() {  # <sheet> -> each measured key with no line, or whose line names no measure, unit and source (or basis)
  local k l
  for k in $RT_MEASURED; do
    l="$(printf '%s\n' "$1" | /usr/bin/grep -F "$k: " | head -1)"
    case "$l" in "$k: "?*' — '?*' · unit: '*' · source: '?*|"$k: "?*' — '?*' · unit: '*' · basis: '?*) ;; *) printf '%s ' "$k" ;; esac
  done
}
rt_goal_lines() { printf '%s\n' "$1" | sed -n 's/^goal: name=\([^ ]*\) status=\(.*\) measure=.*/\1=\2/p' | paste -sd'|' -; }   # <sheet>

# rt_true_state <state> -> the checks that the sheet of a rehearsed state reads true to the person accepting the release
rt_true_state() {
  local TR_ST="$1" TR_SHEET TR_MIN
  RT_ROOT="$WORLD_ROOT/$TR_ST/project"; RT_PLAN="$RT_ROOT/$DOOR_PLAN_REL"
  if [ ! -f "$RT_PLAN" ]; then
    expect_eq "TR-0 $TR_ST: the sandbox of its section is there to be read again" "yes" "no"
    return 0
  fi
  rt_poker sitrep "$RT_PLAN"
  TR_SHEET="$RT_OUT"
  TR_MIN="$(rt_elapsed_min "$TR_SHEET")"
  expect_eq "TR-1 $TR_ST: the sheet's clock names the time since the approval, and it is under an hour (it says $TR_MIN min)" "yes" \
    "$([ -n "$TR_MIN" ] && [ "$TR_MIN" -lt 60 ] && echo yes)"
  expect_eq "TR-2 $TR_ST: the predicted close and the forecast name no day, so neither is weeks out" "" \
    "$(printf '%s\n' "$TR_SHEET" | /usr/bin/grep -E '^(close\.predicted|clock\.forecast): ' | /usr/bin/grep -E '[0-9]{4}-[0-9]{2}-[0-9]{2}')"
  expect_eq "TR-3 $TR_ST: no task held on you says it is building or gives no note" "" \
    "$(printf '%s\n' "$TR_SHEET" | /usr/bin/grep '^task: .* state=held ' | /usr/bin/grep -vE 'note=waits on ')"
  rt_poker sitrep card "$RT_PLAN" <<< "$(rt_judgment "$TR_SHEET")"
  expect_eq "TR-4 $TR_ST: the plan has no wave number, and the card's head leaves the wave out (exit 0)" \
    "run.wave: -|0|Sitrep · project 99.0.0" \
    "$(printf '%s\n' "$TR_SHEET" | /usr/bin/grep '^run\.wave: ')|$RT_PRC|$(printf '%s\n' "$RT_OUT" | head -1 | sed 's/ · [A-Za-z]* [0-9:]* [AP]M$//')"
}

# rt_facts_state <state> -> the checks that the sheet of a rehearsed state states its facts true
rt_facts_state() {
  local TR_ST="$1" TR_SHEET TR_N
  RT_ROOT="$WORLD_ROOT/$TR_ST/project"; RT_PLAN="$RT_ROOT/$DOOR_PLAN_REL"
  if [ ! -f "$RT_PLAN" ]; then
    expect_eq "FA-0 $TR_ST: the sandbox of its section is there to be read again" "yes" "no"
    return 0
  fi
  rt_poker sitrep "$RT_PLAN"
  TR_SHEET="$RT_OUT"
  expect_eq "FA-0b $TR_ST: every measured line is there and names what it measures, its unit and its source; no metric. line" "|0|yes" \
    "$(rt_unlabelled "$TR_SHEET")|$(printf '%s\n' "$TR_SHEET" | /usr/bin/grep -c '^metric\.')|$(printf '%s\n' "$TR_SHEET" | /usr/bin/grep -q '^clock\.now: ' && echo yes)"
  expect_eq "FA-1 $TR_ST: the sheet's goal: lines, one per declared goal, met, not met and not measured" \
    "shown=met|asks=not met|walked=not measured" "$(rt_goal_lines "$TR_SHEET")"
  TR_N="$(rt_m "$TR_SHEET" work.task-time | sed -n 's/^\([0-9][0-9]*\) tasks*[,:].*/\1/p')"
  expect_eq "FA-2 $TR_ST: $TR_N landed task(s) with a launch, under 3: the close is unscaled, build tasks at 1×, and the basis says so" "yes|yes|yes" \
    "$([ -n "$TR_N" ] && [ "$TR_N" -lt 3 ] && echo yes)|$([ "$(rt_m "$TR_SHEET" close.predicted)" = "$(rt_m "$TR_SHEET" close.unscaled)" ] && echo yes)|$(printf '%s\n' "$TR_SHEET" | /usr/bin/grep '^close\.predicted: ' | /usr/bin/grep -q 'basis: .*at 1×.*under 3' && echo yes)"
  expect_eq "FA-2b $TR_ST: pace states two shares of one unit, the work landed and the forecast time used" "yes|yes" \
    "$(rt_m "$TR_SHEET" pace.work-landed | /usr/bin/grep -qE '^[0-9]+%$' && echo yes)|$(rt_m "$TR_SHEET" pace.time-used | /usr/bin/grep -qE '^[0-9]+%$' && echo yes)"
  expect_eq "FA-3 $TR_ST: correctness names the suites run by their last run and the whole run" "yes|yes" \
    "$(rt_m "$TR_SHEET" tests.suites-run | /usr/bin/grep -qE '^[0-9]+: [0-9]+ green, [0-9]+ red$' && echo yes)|$(rt_m "$TR_SHEET" tests.whole-run | /usr/bin/grep -qE '^(not run yet|green at [0-9a-f]{8}|red at [0-9a-f]{8})$' && echo yes)"
  expect_eq "FA-4 $TR_ST: no task's note counts what it leaves out (FA-1 read the same sheet)" "0" \
    "$(printf '%s\n' "$TR_SHEET" | /usr/bin/grep '^task: ' | /usr/bin/grep -cE ' note=.* \+[0-9]+$')"
}
