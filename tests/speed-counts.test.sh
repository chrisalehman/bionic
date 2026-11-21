#!/bin/bash
# tests/speed-counts.test.sh — THE READS EACH COMMAND MAKES, COUNTED, AT TWO SIZES OF ONE RUN
#
# WHAT THIS SUITE IS FOR. A command a person waits on is slow when it reads the same thing again and again: the
# run's log folded once per asker, the plan parsed once per row. A clock cannot pin that without flaking on a busy
# machine, so the libraries count their reads when asked, and this suite reads the counts. The variable is
# BIONIC_COUNT: when it names a file, each counted function appends one line, `<kind> <function>`, at its entry and
# does nothing else. The kinds:
#
#   log     lib/reader.sh reader_events     a whole read of the run's log
#   fold    lib/reader.sh reader_facts      a fold of the log into facts
#   overlay lib/reader.sh reader_facts -    pending lines laid over facts already folded (a judgment's pending step)
#   parse   lib/plan-read.sh _plan_read_lines  a parse of the plan
#   table   lib/units.sh _units_read        a read of the plan's Tasks table (a memo's answer is no read)
#   status  lib/reader.sh reader_q_status   one row's status asked
#           lib/reader.sh reader_q_statuses every row's status, in one pass
#   facts   lib/proof.sh facts_state        the run's facts answered at a head
#   gate    lib/walls.sh dispatch           one pass of the evidence gate's judging arms
#
# THE FIXTURE. One run, built at two sizes: SC_N rows and twice that, each size's every row but the last a landed
# Step-4 build and the last the integrate row, open. The plan is a version-15 wave at double rigor with
# multi_agent on, so the gate's ledger arm runs; it stands at Step 5 with every proof the dealing owes passing at the
# working head, so the card reaches its judge of Steps 6, 7 and 8; its pull request is open against a bare origin
# with a stand-in gh, so the watcher's pass fetches. The session is engaged and bound by the bind verb, and a handoff
# names the plan for resume. Each size is snapshotted once built, and every command is run from that snapshot, with
# its own TMPDIR, so no command reads what another left, and a kept file of an earlier run is never what is counted.
#
# THE FIVE COMMANDS (SC_CMDS): card `release-approval --preview <plan>` · check `current 6 --check` · tick `tick` ·
# resume `resume <handoff>` · watch `tick --watch`. Each runs once per size with the counters on (`on`), and at
# SC_N once more with them off (`off`), for §PRINT.
#
# ADDING A CEILING. `sc_count <size> <command> <kind>` prints how many lines of that kind the command wrote at that
# size (`n` or `2n`), 0 for none. A row that holds a command to a count adds one assertion over it, in a section of
# its own, and touches nothing above:
#     expect_eq "ONCE-fold card counts one fold" 1 "$(sc_count n card fold)"
#     expect_eq "SCALE-status check is the same at n and 2n" "$(sc_count n check status)" "$(sc_count 2n check status)"
#
# FIXTURE FIDELITY (.claude/rules/test-harness.md, "Fixture fidelity"). SYNTHESIZED, in the shape of the copy of
# wave 50's record the speed protocol times (.bionic/tests/w52-speed.md): a double multi_agent wave past Step 4, its
# rows landed but the integrate row, its request open. What a count depends on is pinned by §FIXTURE, not assumed:
# the triple that turns the ledger arm on, a head the judge can deal (a base-sha that is a commit, every owed proof
# passing there), the request the watcher looks at, and a TMPDIR of the command's own, so no kept facts or place
# cache from another run is read. A size differs from the other by its rows alone.
#
# ANTI-VACUITY (.claude/rules/test-harness.md, "Anti-vacuity"). The count extractor is proved on real output first:
# §REPORTS reads every kind as non-zero somewhere before any later row reads a ceiling through `sc_count`, and every
# command's lines are read whole against the nine known shapes. §PRINT compares only prints it has shown are not
# empty. RED: with the counter lines taken out of the libraries, §REPORTS is red and §FIXTURE and §PRINT stay
# green.
#
# Usage: bash tests/speed-counts.test.sh   (SPEED_COUNTS_TABLE=<file> also writes the counts' table there)

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"
. "$(dirname "$0")/lib/plan-fixture.sh"

POKER="${BIONIC_HOOKS_DIR}/session-poker.sh"
SC_LIB="${BIONIC_SCRIPTS_DIR}/payload/scripts/lib"

TMPROOT="$(mktemp -d)" && TMPROOT="$(cd "$TMPROOT" && pwd -P)" || exit 1
cleanup() { chmod -R u+rwX "$TMPROOT" 2>/dev/null; rm -rf "$TMPROOT"; }
trap cleanup EXIT

export BIONIC_PLUGINS_DIR="$TMPROOT/no-plugins"; mkdir -p "$BIONIC_PLUGINS_DIR"
export BIONIC_PRESSURE_RING="$TMPROOT/pressure.ring"
export BIONIC_PROBE_FREE_MB=8192 BIONIC_PROBE_LOAD_1M=1.0 BIONIC_PROBE_FREE_PCT=60 BIONIC_PROBE_SWAP_PCT=0
export BIONIC_PROBE_CORES=8 BIONIC_PROBE_USED_PCT=30 BIONIC_PROBE_BUSY_CORES=1.0 BIONIC_PROBE_BUSY_CORES_5M=1.0
export CLAUDE_CONFIG_DIR="$TMPROOT/config"; mkdir -p "$CLAUDE_CONFIG_DIR/bionic"; printf '80\n' > "$CLAUDE_CONFIG_DIR/bionic/share"
export BIONIC_GATE_DIR="$TMPROOT/gate"; mkdir -p "$BIONIC_GATE_DIR/requests" "$BIONIC_GATE_DIR/cost"
export TZ=America/Los_Angeles
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
unset BIONIC_COUNT CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_ROOT CLAUDE_PLUGIN_DATA

SID="5c1e7a2b-3d4f-4e8a-9b6c-1f2e3d4c5b6a"
SC_NOW=1791324000     # 2026-10-06T22:00:00Z
SC_AT=2026-10-06T12:00:00Z
SC_N=5
SC_CMDS="card check tick resume watch"
SC_KINDS="log fold overlay parse table status facts gate"
SC_OUT="$TMPROOT/out"; mkdir -p "$SC_OUT"

# ---------- the run ----------
#
# sc_world <size> <rows> -> the run of <rows> Tasks rows built under $TMPROOT/<size>/live, then snapshotted to
# $TMPROOT/<size>/snap. Inside live: proj (the project), origin.git (its bare origin), tmp (the commands' TMPDIR),
# home (their HOME) and bin (the stand-in gh). The run's names are fixed, so every size's prints differ only by its rows.
sc_world() {
  local size="$1" rows="$2" w r p l rec base h i q
  w="$TMPROOT/$size/live"; r="$w/proj"
  mkdir -p "$r/.bionic/tmp" "$w/tmp" "$w/home" "$w/bin" || return 1
  # The stand-in host: a request it is asked of is open, and the ask is logged, so no pass reaches a network.
  printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s/gh.log"\nprintf "OPEN -\\n"\n' "$w" > "$w/bin/gh"; chmod +x "$w/bin/gh"
  git init -q -b main "$r" && git -C "$r" commit -q --allow-empty -m base || return 1
  base="$(git -C "$r" rev-parse HEAD)"
  git init -q --bare "$w/origin.git" && git -C "$r" remote add origin "$w/origin.git" && git -C "$r" push -q origin main || return 1
  git -C "$r" checkout -q -b wave/02-fx || return 1
  set --
  i=1; while [ "$i" -lt "$rows" ]; do
    set -- "$@" "| T$i | 4 | build | row $i · complexity: standard | w-T$i | — | — | 30 | REQ-1 | lib/t$i.sh | — | — | landed |"
    i=$((i + 1))
  done
  set -- "$@" "| T$rows | 8 | integrate | the integrate row · complexity: standard | w-int | — | — | 30 | REQ-1 | — | — | — | active |"
  p="$(plan_fixture --current 5 "$r/.bionic/docs/plans/epic-01-fx/wave-02-fx.plan.md" wave "$@")" || return 1
  l="$(plan_fixture_log "$p")"; rec="${l%/run.log}"
  # The audited triple, the working branch and its base, so the gate's ledger arm and the judge both run.
  sed -e 's/^rigor: single$/rigor: double/' -e 's/^multi_agent: false$/multi_agent: true/' \
      -e "s|^working-branch: .*|working-branch: wave/02-fx\\
integration-branch: main|" -e "s/^base-sha: .*/base-sha: $base/" "$p" > "$p.t" && mv "$p.t" "$p" || return 1
  seal_fixture "$p" "$l"
  # Every proof the dealing owes passes at the working head: its evidence is committed there, its event written after.
  for q in evidence adversarial structure; do : > "$rec/$q-piece.md"; : > "$rec/$q-whole.md"; done
  printf 'whole\n' > "$rec/reg.log"; printf 'ok\n' > "$rec/check.log"
  git -C "$r" add -A && git -C "$r" commit -q -m fixture || return 1
  h="$(git -C "$r" rev-parse HEAD)"
  bash -c '. "$1/run.sh" && . "$1/proof.sh" || exit 1
    facts_owed "$(plan_frontmatter_get "$2" rigor)" "$(plan_frontmatter_get "$2" scale)" "$4" \
      | while IFS="	" read -r k q role scope; do
          case "$k" in
            regression) l="$(proof_line regression "$3" "$6" record/wave-02-fx/reg.log)" ;;
            review) l="$(proof_line review "$3" "$6" "record/wave-02-fx/$q-$scope.md" "$q" r pass "$scope")" ;;
            check) l="$(proof_line check "$3" "$6" record/wave-02-fx/check.log)" ;;
            *) echo "sc_world: no proof planted for $k" >&2; exit 1 ;;
          esac
          f="${l#proved: }"; LOG_AT="$6" proof_event "$2" ${f/ at=$6/}
        done' _ "$SC_LIB" "$p" "$h" "$r" "$rec" "$SC_AT" || return 1
  printf 'run/v1|ev=published|part=pr|url=https://example.invalid/pull/1|branch=wave/02-fx|commit=%s|base=main|by=publish|at=%s\n' \
    "$h" "$SC_AT" >> "$l"
  seal_fixture "$p" "$l"
  : > "$r/.bionic/tmp/engaged-$SID.state"
  SC_ROOT="$r"; SC_PLAN="$p"; SC_W="$w"
  sc_env "$POKER" bind "$p" > "$TMPROOT/$size.bind.out" 2>&1 || return 1
  mkdir -p "$r/.bionic/handoffs"
  printf 'bionic-handoff/v1\nresume point: Step 5\nwritten: 2026-10-06 2:00 PM PDT\nplan: %s\nworking branch: wave/02-fx\n' \
    "${p#"$r"/}" > "$r/.bionic/handoffs/handoff.md"
  rm -rf "$TMPROOT/$size/snap" && cp -Rp "$w" "$TMPROOT/$size/snap"
}

# sc_env <poker> <verb args…> -> the verb run from the project of the size last named (SC_ROOT, SC_W), in its world
sc_env() {
  local pk="$1"; shift
  ( cd "$SC_ROOT" && exec env PATH="$SC_W/bin:$PATH" HOME="$SC_W/home" TMPDIR="$SC_W/tmp" CLAUDE_CODE_SESSION_ID="$SID" \
      BIONIC_NOW_EPOCH="$SC_NOW" bash "$pk" "$@" )
}

# sc_args <command> -> the verb and its arguments, one per line
sc_args() {
  case "$1" in
    card) printf '%s\n' release-approval --preview "$SC_PLAN" ;;
    check) printf '%s\n' current 6 --check ;;
    tick) printf '%s\n' tick ;;
    resume) printf '%s\n' resume "$SC_ROOT/.bionic/handoffs/handoff.md" ;;
    watch) printf '%s\n' tick --watch ;;
  esac
}

# sc_run <size> <command> <on|off> -> the command run from the size's snapshot, restored in place first; it leaves
# $SC_OUT/<size>.<command>.<mode>.{count,out,err,rc}, and the live tree as the command left it. `count` is the
# counters' file, made empty before the run, so a command that counts nothing leaves it empty, never absent.
sc_run() {
  local size="$1" cmd="$2" mode="$3" f a
  f="$SC_OUT/$size.$cmd.$mode"
  rm -rf "$TMPROOT/$size/live" && cp -Rp "$TMPROOT/$size/snap" "$TMPROOT/$size/live" || return 1
  SC_W="$TMPROOT/$size/live"; SC_ROOT="$SC_W/proj"; SC_PLAN="$SC_ROOT/.bionic/docs/plans/epic-01-fx/wave-02-fx.plan.md"
  set --; while IFS= read -r a; do set -- "$@" "$a"; done < <(sc_args "$cmd")
  : > "$f.count"
  if [ "$mode" = on ]; then
    BIONIC_COUNT="$f.count" sc_env "$POKER" "$@" > "$f.out" 2> "$f.err"
  else
    sc_env "$POKER" "$@" > "$f.out" 2> "$f.err"
  fi
  printf '%s\n' "$?" > "$f.rc"
}

sc_rows() { case "$1" in n) echo "$SC_N" ;; 2n) echo $((SC_N * 2)) ;; esac; }   # <size> -> its Tasks rows

# sc_count <size> <command> <kind> -> how many lines of that kind the command counted at that size, on; 0 for none
sc_count() {
  awk -v k="$3" '$1 == k { n++ } END { print n + 0 }' "$SC_OUT/$1.$2.on.count" 2>/dev/null || echo 0
}

# sc_print <size> <command> <mode> -> what the command printed, its exit last, every instant written as <at>: an
# instant read from the machine's clock is the one thing two runs of one command from one snapshot may differ by
sc_print() {
  { cat "$SC_OUT/$1.$2.$3.out"; printf -- '--- stderr\n'; cat "$SC_OUT/$1.$2.$3.err"; printf -- '--- rc %s\n' "$(cat "$SC_OUT/$1.$2.$3.rc")"; } \
    | sed -E 's/[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z/<at>/g'
}

setup_section "the run at n and 2n rows, and the five commands over each"

SC_BUILT=""; SC_FETCHED=""
for SC_SIZE in n 2n; do
  if sc_world "$SC_SIZE" "$(sc_rows "$SC_SIZE")"; then SC_BUILT="$SC_BUILT $SC_SIZE"; else echo "sc_world $SC_SIZE: the run was not built"; continue; fi
  for SC_C in $SC_CMDS; do
    sc_run "$SC_SIZE" "$SC_C" on
    [ "$SC_C" != watch ] || [ -f "$TMPROOT/$SC_SIZE/snap/proj/.git/FETCH_HEAD" ] || [ ! -f "$SC_W/proj/.git/FETCH_HEAD" ] \
      || SC_FETCHED="$SC_FETCHED $SC_SIZE"
    [ "$SC_SIZE" != n ] || sc_run n "$SC_C" off
  done
done 2>&1

# THE COUNTS, printed: one line per size and command, every kind in SC_KINDS order. The runner keeps no green suite's
# output, so SPEED_COUNTS_TABLE, when it names a file, is handed the same table.
sc_table() {
  printf '%-4s %-7s' size command; for SC_K in $SC_KINDS; do printf ' %6s' "$SC_K"; done; printf ' %4s\n' rc
  for SC_SIZE in n 2n; do
    for SC_C in $SC_CMDS; do
      printf '%-4s %-7s' "$SC_SIZE" "$SC_C"
      for SC_K in $SC_KINDS; do printf ' %6s' "$(sc_count "$SC_SIZE" "$SC_C" "$SC_K")"; done
      printf ' %4s\n' "$(cat "$SC_OUT/$SC_SIZE.$SC_C.on.rc" 2>/dev/null || echo -)"
    done
  done
}
printf '\n'; sc_table
[ -z "${SPEED_COUNTS_TABLE:-}" ] || sc_table > "$SPEED_COUNTS_TABLE"

section "§FIXTURE: each size is built, and each command runs the path its counts are read on"
# fails-when: a size is not built, or a command exits other than its path's code, or the card stops before its
# judge, or the watcher's pass never looks at the open request; then a count of zero would read as a command that
# read nothing.
expect_eq "FX-1 both sizes are built" " n 2n" "$SC_BUILT"
for SC_SIZE in n 2n; do
  expect_eq "FX-2 ($SC_SIZE) the exits: card 0, check 1 (it would refuse), tick 0, resume 0, watch 0" "0 1 0 0 0" \
    "$(for SC_C in $SC_CMDS; do cat "$SC_OUT/$SC_SIZE.$SC_C.on.rc" 2>/dev/null || echo -; done | paste -sd' ' -)"
  SC_ROWS="$(sc_rows "$SC_SIZE")"
  expect_regex "FX-3 ($SC_SIZE) the card's head counts every row, all but the integrate row landed" \
    " · $((SC_ROWS - 1)) of $SC_ROWS tasks landed\$" "$(head -1 "$SC_OUT/$SC_SIZE.card.on.out" 2>/dev/null)"
  expect_contains "FX-4 ($SC_SIZE) the card's judge of Step 7 was asked and refused, so it judged Steps 6 and 7" \
    "Not ready for your decisions: current 7 --check: would refuse." "$(cat "$SC_OUT/$SC_SIZE.card.on.out" 2>/dev/null)"
done
expect_eq "FX-5 the watcher's pass fetched the integration branch at each size, the request being open" " n 2n" "${SC_FETCHED:-}"

section "§REPORTS: every counter reports, at each size"
# fails-when: a counted function writes no line when BIONIC_COUNT names a file, or a command counts nothing.
for SC_SIZE in n 2n; do
  for SC_K in $SC_KINDS; do
    SC_BY=""
    for SC_C in $SC_CMDS; do [ "$(sc_count "$SC_SIZE" "$SC_C" "$SC_K")" -eq 0 ] || SC_BY="$SC_BY $SC_C"; done
    expect_nonempty "REP-1 ($SC_SIZE) $SC_K is counted by a command of the five (by:${SC_BY:- none})" "$SC_BY"
  done
  for SC_C in $SC_CMDS; do
    expect_regex "REP-2 ($SC_SIZE) $SC_C counts its reads, each line a known kind and its function" \
      '^([0-9]+ (log reader_events|fold reader_facts|overlay reader_facts|parse _plan_read_lines|table _units_read|status reader_q_status|status reader_q_statuses|facts facts_state|gate dispatch)( |$))+$' \
      "$(sort "$SC_OUT/$SC_SIZE.$SC_C.on.count" 2>/dev/null | uniq -c | awk '{ $1 = $1; print }' | paste -sd' ' -)"
  done
done

section "§ONCE: one fold of the run's log a command, one answer of its facts at a head"
# fails-when: a reader in any of the commands folds the run's log for itself, or a subshell or a process the command
# starts is not served the command's one fold, or the facts at the head are judged a second time in one command; or
# a judgment's pending step is laid over the fold more than once a gate pass.
for SC_SIZE in n 2n; do
  for SC_C in card check; do
    expect_eq "ONCE-1 ($SC_SIZE) $SC_C folds the run's log once" 1 "$(sc_count "$SC_SIZE" "$SC_C" fold)"
  done
  for SC_C in card tick resume watch; do
    expect_eq "ONCE-2 ($SC_SIZE) $SC_C answers the facts at its head once" 1 "$(sc_count "$SC_SIZE" "$SC_C" facts)"
  done
  expect_eq "ONCE-3 ($SC_SIZE) check judges at its step and asks no facts at a head" 0 "$(sc_count "$SC_SIZE" check facts)"
  expect_eq "ONCE-4 ($SC_SIZE) check lays its pending step over the fold once, in its one gate pass" "1 1" \
    "$(sc_count "$SC_SIZE" check overlay) $(sc_count "$SC_SIZE" check gate)"
  for SC_C in $SC_CMDS; do
    SC_O="$(sc_count "$SC_SIZE" "$SC_C" overlay)"; SC_G="$(sc_count "$SC_SIZE" "$SC_C" gate)"
    expect_eq "ONCE-5 ($SC_SIZE) $SC_C lays a pending step over the fold no more than once a gate pass ($SC_O for $SC_G)" 1 \
      "$([ "$SC_O" -le "$SC_G" ] && echo 1 || echo 0)"
  done
done

section "§SCALE: the reads of the log and the facts do not grow with the rows"
# fails-when: a whole read of the log, a fold, an overlay or a facts answer is made once a row, so a run of 2n rows
# counts more of it than a run of n.
for SC_C in $SC_CMDS; do
  for SC_K in log fold overlay facts; do
    expect_eq "SCALE-1 $SC_C counts the same $SC_K at n rows and 2n" "$(sc_count n "$SC_C" "$SC_K")" "$(sc_count 2n "$SC_C" "$SC_K")"
  done
done

section "§ONCE-status: the ledger makes one status pass, at either size"
# fails-when: the ledger asks a row's status once a row again, so a pass costs as many asks as the plan has rows.
# A ledger pass is one per gate pass, and the tick reads one more of its own (its LEDGER), as do resume and the watcher's
# pass, which run a tick: so the check counts one, the card at most two, and the three tick commands at most three.
for SC_SIZE in n 2n; do
  expect_eq "ONCE-status-1 ($SC_SIZE) check: its one gate pass makes one status pass" 1 "$(sc_count "$SC_SIZE" check status)"
  expect_regex "ONCE-status-2 ($SC_SIZE) card: one status pass for each of its two gate passes at most" '^[12]$' \
    "$(sc_count "$SC_SIZE" card status)"
  for SC_C in tick resume watch; do
    expect_regex "ONCE-status-3 ($SC_SIZE) $SC_C: one status pass for each of its gate passes and its own ledger at most" '^[123]$' \
      "$(sc_count "$SC_SIZE" "$SC_C" status)"
  done
done

section "§SCALE-status: a plan of 2n rows asks the statuses as often as one of n"
# fails-when: a status is asked, or the plan parsed for one, once per row, so the 2n run counts more than the n run.
for SC_C in $SC_CMDS; do
  for SC_K in status parse; do
    expect_eq "SCALE-status $SC_C counts its $SC_K the same at n and 2n" "$(sc_count n "$SC_C" "$SC_K")" "$(sc_count 2n "$SC_C" "$SC_K")"
  done
done

section "§STATUS-JOIN: the one pass answers every row as its own status ask, over each size's run"
# fails-when: the one answer gives some Tasks row of the suite's run another state, dispatch field, tree or commit
# than the per-row ask gives it. Read over a copy of each size's snapshot, so nothing a command left is read.
# sj_block <answer> <row> -> the row's lines of the one answer, `state=pending` when it opens no block for the row
sj_block() {
  printf '%s\n' "$1" | awk -v r="$2" 'index($0, "row=") == 1 { on = ($0 == "row=" r); seen = seen || on; next } on { print }
    END { if (!seen) print "state=pending" }'
}
for SC_SIZE in n 2n; do
  SJ="$TMPROOT/$SC_SIZE/join"; rm -rf "$SJ" && cp -Rp "$TMPROOT/$SC_SIZE/snap" "$SJ"
  SJ_PLAN="$SJ/proj/.bionic/docs/plans/epic-01-fx/wave-02-fx.plan.md"
  sj_ask() { ( cd "$SJ/proj" && env TMPDIR="$SJ/tmp" HOME="$SJ/home" bash "$SC_LIB/../reader.sh" "$SJ_PLAN" "$@" ); }
  SJ_ALL="$(sj_ask statuses)"; SC_ROWS="$(sc_rows "$SC_SIZE")"
  expect_contains "SJ-1 ($SC_SIZE) the one answer reads the open integrate row as dispatched (the block reader proved)" \
    "state=dispatched" "$(sj_block "$SJ_ALL" "T$SC_ROWS")"
  SJ_DIFF=""; SJ_SAME=0; i=1
  while [ "$i" -le "$SC_ROWS" ]; do
    if [ "$(sj_ask status "T$i")" = "$(sj_block "$SJ_ALL" "T$i")" ]; then SJ_SAME=$((SJ_SAME + 1)); else SJ_DIFF="$SJ_DIFF T$i"; fi
    i=$((i + 1))
  done
  expect_eq "SJ-2 ($SC_SIZE) each of the $SC_ROWS rows: the one answer is its own status ask (rows that differ:${SJ_DIFF:- none})" \
    "$SC_ROWS" "$SJ_SAME"
done
# The prints the five commands made, for a record to compare across two runs of the suite (SPEED_COUNTS_PRINTS=<dir>).
[ -z "${SPEED_COUNTS_PRINTS:-}" ] || { mkdir -p "$SPEED_COUNTS_PRINTS"
  for SC_SIZE in n 2n; do for SC_C in $SC_CMDS; do sc_print "$SC_SIZE" "$SC_C" on > "$SPEED_COUNTS_PRINTS/$SC_SIZE.$SC_C.txt"; done; done; }

section "§PRINT: counting changes no print"
# fails-when: a counter writes to the command's stdout or stderr, or moves its exit, so the print with BIONIC_COUNT
# set differs from the print without it, from the same snapshot.
# The watcher's pass prints nothing when it has no wake, so what it is compared by is its exit, with FX-5 showing it
# looked; every other command prints a page.
for SC_C in $SC_CMDS; do
  if [ "$SC_C" = watch ]; then
    expect_eq "PR-1 watch has no wake, so its print is its exit, 0" "0" "$(cat "$SC_OUT/n.watch.off.rc" 2>/dev/null)"
  else
    expect_nonempty "PR-1 $SC_C prints something to compare" "$(cat "$SC_OUT/n.$SC_C.off.out" "$SC_OUT/n.$SC_C.off.err" 2>/dev/null)"
  fi
  expect_eq "PR-2 $SC_C prints the same with the counters on as off" "$(sc_print n "$SC_C" off)" "$(sc_print n "$SC_C" on)"
done

finish
