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
#   held    lib/proof.sh _proof_facts       the command's held fold read by a shell that did not hold it yet
#   gate    lib/walls.sh dispatch           one pass of the evidence gate's judging arms: one step's checks
#   pass    lib/walls.sh wall_evidence_gate one pass of the evidence gate, its reads and every step it judges
#           lib/walls.sh wall_gate_judge_steps  one pass for several steps, each step's checks run in it
#   matrix  lib/walls.sh matrix_load        a load of the criteria's cells, tasks and rows
#   owing   lib/walls.sh matrix_owing_step  one criterion's owing step asked
#           lib/walls.sh matrix_owing_open  one criterion's openness asked
#           lib/walls.sh matrix_owing_load  every criterion's owing step and openness, in one pass
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
# FIXTURE FIDELITY (.claude/rules/test-harness.md, "Fixture fidelity"). SYNTHESIZED, in the shape of the recorded
# run the speed protocol times: a double multi_agent run past Step 4, its rows landed but the integrate row, its
# request open. What a count depends on is pinned by §FIXTURE, not assumed:
# the triple that turns the ledger arm on, a head the judge can deal (a base-sha that is a commit, every owed proof
# passing there), the request the watcher looks at, and a TMPDIR of the command's own, so no kept facts or place
# cache from another run is read. A size differs from the other by its rows alone.
#
# ANTI-VACUITY (.claude/rules/test-harness.md, "Anti-vacuity"). The count extractor is proved on real output first:
# §REPORTS reads every kind as non-zero somewhere before any later row reads a ceiling through `sc_count`, and every
# command's lines are read whole against the sixteen known shapes. §PRINT compares only prints it has shown are not
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
SC_KINDS="log fold overlay parse table status facts held gate pass matrix owing"
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
  # A section that needs more in the record writes it here, before the commit the proofs are planted at.
  [ -z "${SC_WORLD_RECORDS:-}" ] || "$SC_WORLD_RECORDS" "$rec" || return 1
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
      '^([0-9]+ (log reader_events|fold reader_facts|overlay reader_facts|parse _plan_read_lines|table _units_read|status reader_q_status|status reader_q_statuses|facts facts_state|held _proof_facts|gate dispatch|pass wall_evidence_gate|pass wall_gate_judge_steps|matrix matrix_load|owing matrix_owing_step|owing matrix_owing_open|owing matrix_owing_load)( |$))+$' \
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
section "§GATE: one gate pass a command, whatever steps it judges"
# fails-when: the judge asked for several steps runs a whole gate pass for each, or the gate's matrix arm loads the
# criteria twice in one step's checks, or asks a criterion's owing step and openness once a criterion; then the reads a
# pass shares are made again for each step, and the asks of the matrix grow with the criteria.
for SC_SIZE in n 2n; do
  for SC_C in $SC_CMDS; do
    expect_eq "GATE-1 ($SC_SIZE) $SC_C makes one gate pass" 1 "$(sc_count "$SC_SIZE" "$SC_C" pass)"
  done
  # The card's judge asks Steps 6, 7 and 8 and the gate judges the first two (Step 8 is the facts judge's alone), so its
  # one pass runs two steps' checks; the check asks one step.
  expect_eq "GATE-2 ($SC_SIZE) card runs the checks of each of its two gated steps once, in its one pass" "1 2" \
    "$(sc_count "$SC_SIZE" card pass) $(sc_count "$SC_SIZE" card gate)"
  expect_eq "GATE-3 ($SC_SIZE) check loads the matrix once and asks every criterion's owing step and openness in one pass" "1 1" \
    "$(sc_count "$SC_SIZE" check matrix) $(sc_count "$SC_SIZE" check owing)"
done

# THE PASS JUDGES EACH STEP AS A PASS OF ITS OWN WOULD. The judge asked for Steps 6, 7 and 8 at once prints, step by
# step, what it prints asked for each alone, and exits with the highest exit of the three; each from a copy of the
# snapshot, counters off. The fixture's gate refuses both steps, each for a fact of its own (Step 6 a criterion's
# evidence, Step 7 its document), so a step judged at the other's step reads back another refusal.
# fails-when: a step of the one pass is judged at another step, or its refusal, its notes or its exit is not the one a
# pass of its own gives.
sg_judge() {  # <size> <tag> <steps…> -> $SC_OUT/<size>.judge-<tag>.{out,err,rc}, from a fresh copy of the snapshot
  local size="$1" tag="$2" f; shift 2
  f="$SC_OUT/$size.judge-$tag"
  rm -rf "$TMPROOT/$size/live" && cp -Rp "$TMPROOT/$size/snap" "$TMPROOT/$size/live" || return 1
  SC_W="$TMPROOT/$size/live"; SC_ROOT="$SC_W/proj"
  sc_env "$POKER" judge "$@" > "$f.out" 2> "$f.err"; printf '%s\n' "$?" > "$f.rc"
}
for SC_SIZE in n 2n; do
  sg_judge "$SC_SIZE" all 6 7 8
  for SC_S in 6 7 8; do sg_judge "$SC_SIZE" "$SC_S" "$SC_S"; done
  SG="$SC_OUT/$SC_SIZE.judge"
  expect_contains "GATE-4 ($SC_SIZE) the pass refuses Step 6 for its criterion (the reader proved)" \
    "missing: step 6 — matrix row 'AC-1.1' (T2) is missing evidence key 'evidence'" "$(cat "$SG-all.err")"
  expect_contains "GATE-4 ($SC_SIZE) the pass refuses Step 7 for its document (the reader proved)" \
    "owed at 15: Step 7's document" "$(cat "$SG-all.err")"
  expect_eq "GATE-4 ($SC_SIZE) the steps' prints, asked at once, are each step's asked alone" \
    "$(cat "$SG-6.out" "$SG-7.out" "$SG-8.out")" "$(cat "$SG-all.out")"
  expect_eq "GATE-4 ($SC_SIZE) the steps' refusals, asked at once, are each step's asked alone" \
    "$(cat "$SG-6.err" "$SG-7.err" "$SG-8.err")" "$(cat "$SG-all.err")"
  expect_eq "GATE-4 ($SC_SIZE) the exit asked at once is the highest of the steps' alone" \
    "$(sort -n "$SG-6.rc" "$SG-7.rc" "$SG-8.rc" | tail -1)" "$(cat "$SG-all.rc")"
done

# A HELD ANSWER IS THE PASS'S OWN. The gate serves a step from the judge's pass only when the pass set it in this
# process; an answer, or a held prelude, handed down by the environment is refused. The check of Step 7 is run once
# plain and once with both exported, the answer forged for exactly this ask (`exec` keeps the pid the session is named
# for), admitting it.
# fails-when: an exported variable is read as the pass's answer or prelude, so the forged run prints another verdict.
sg_forged() {  # <size> <tag> [forge] -> $SC_OUT/<size>.check7-<tag>.{out,err,rc}
  local size="$1" f="$SC_OUT/$1.check7-$2" forge="${3:-}"
  rm -rf "$TMPROOT/$size/live" && cp -Rp "$TMPROOT/$size/snap" "$TMPROOT/$size/live" || return 1
  SC_W="$TMPROOT/$size/live"; SC_ROOT="$SC_W/proj"
  # shellcheck disable=SC2016  # the script is the child shell's, expanded there
  ( cd "$SC_ROOT" && exec env PATH="$SC_W/bin:$PATH" HOME="$SC_W/home" TMPDIR="$SC_W/tmp" CLAUDE_CODE_SESSION_ID="$SID" \
      BIONIC_NOW_EPOCH="$SC_NOW" SG_FORGE="$forge" bash -c '
        if [ -n "$SG_FORGE" ]; then
          export _WG_HELD="$(printf "\036%s\035%s\035%s\035%s\037%s\037" "$(pwd -P)" "planverb-$$" "git commit -m current" 7 0)"
          export _EG_PRELUDE_HELD=1
        fi
        exec bash "$1" current 7 --check' _ "$POKER" ) > "$f.out" 2> "$f.err"
  printf '%s\n' "$?" > "$f.rc"
}
sg_forged n plain; sg_forged n forged forge
expect_contains "GATE-5 the plain check of Step 7 refuses (the reader proved)" "current 7 --check: would refuse" "$(cat "$SC_OUT/n.check7-plain.err")"
expect_eq "GATE-5 an answer and a prelude handed down by the environment move no verdict" \
  "$(cat "$SC_OUT/n.check7-plain.out" "$SC_OUT/n.check7-plain.err" "$SC_OUT/n.check7-plain.rc")" \
  "$(cat "$SC_OUT/n.check7-forged.out" "$SC_OUT/n.check7-forged.err" "$SC_OUT/n.check7-forged.rc")"

# THE PASS'S TIME (SPEED_COUNTS_TIMES=<file>): the judge of Steps 6 and 7 at 2n, counters off, three runs, each run's
# real seconds a line. A record's figure, beside the counts; nothing here asserts a clock.
if [ -n "${SPEED_COUNTS_TIMES:-}" ]; then
  : > "$SPEED_COUNTS_TIMES"
  for SC_I in 1 2 3; do
    rm -rf "$TMPROOT/2n/live" && cp -Rp "$TMPROOT/2n/snap" "$TMPROOT/2n/live"
    SC_W="$TMPROOT/2n/live"; SC_ROOT="$SC_W/proj"
    SC_T0="$(perl -MTime::HiRes=time -e 'printf "%.3f", time')"
    sc_env "$POKER" judge 6 7 >/dev/null 2>&1
    printf '2n judge 6 7 run %s %s s\n' "$SC_I" "$(perl -MTime::HiRes=time -e "printf '%.2f', time - $SC_T0")" >> "$SPEED_COUNTS_TIMES"
  done
fi

# The prints the five commands made, for a record to compare across two runs of the suite (SPEED_COUNTS_PRINTS=<dir>).
[ -z "${SPEED_COUNTS_PRINTS:-}" ] || { mkdir -p "$SPEED_COUNTS_PRINTS"
  for SC_SIZE in n 2n; do for SC_C in $SC_CMDS; do sc_print "$SC_SIZE" "$SC_C" on > "$SPEED_COUNTS_PRINTS/$SC_SIZE.$SC_C.txt"; done; done
  cp "$SC_OUT"/*.judge-* "$SPEED_COUNTS_PRINTS/" 2>/dev/null; }

section "§WATCH-ONE: with the request open and nothing the tick reads changed, the watcher's pass asks the host one question"
# fails-when: a pass over an unchanged run, the request open, runs the tick again (a gate pass, a fold of the log, a
# status pass, a read of the table or a facts answer is counted); makes no fetch; prints; or counts more at 2n rows than
# at n. The first passes run the tick and settle the file the watcher keeps its look in (BIONIC_WATCH_LOOK): a fetch that
# moves origin/main, which the tick reads, makes the next pass run it once more, so the third is the one sure to be unchanged.
# sc_watch_seq <size> -> three passes in one world, one look file, each with its own counts and prints:
# $SC_OUT/<size>.watchseq.<i>.{count,out,err,rc}, and .fetched for the third (its FETCH_HEAD made new by that pass)
sc_watch_seq() {
  local size="$1" i f
  rm -rf "$TMPROOT/$size/live" && cp -Rp "$TMPROOT/$size/snap" "$TMPROOT/$size/live" || return 1
  SC_W="$TMPROOT/$size/live"; SC_ROOT="$SC_W/proj"; SC_PLAN="$SC_ROOT/.bionic/docs/plans/epic-01-fx/wave-02-fx.plan.md"
  : > "$SC_W/look"
  for i in 1 2 3; do
    f="$SC_OUT/$size.watchseq.$i"; : > "$f.count"; rm -f "$SC_ROOT/.git/FETCH_HEAD"
    BIONIC_COUNT="$f.count" BIONIC_WATCH_LOOK="$SC_W/look" sc_env "$POKER" tick --watch > "$f.out" 2> "$f.err"
    printf '%s\n' "$?" > "$f.rc"
    [ -f "$SC_ROOT/.git/FETCH_HEAD" ] && echo yes > "$f.fetched" || echo no > "$f.fetched"
  done
}
sc_seq_count() { awk -v k="$3" '$1 == k { n++ } END { print n + 0 }' "$SC_OUT/$1.watchseq.$2.count" 2>/dev/null || echo 0; }   # <size> <i> <kind>
for SC_SIZE in n 2n; do
  sc_watch_seq "$SC_SIZE"
  expect_eq "WO-1 ($SC_SIZE) the first pass runs the tick, so the extractor reads real counts (gate>0, facts>0)" "yes" \
    "$([ "$(sc_seq_count "$SC_SIZE" 1 gate)" -gt 0 ] && [ "$(sc_seq_count "$SC_SIZE" 1 facts)" -gt 0 ] && echo yes)"
  expect_eq "WO-2 ($SC_SIZE) the three passes are quiet" "0 0 0" \
    "$(for SC_I in 1 2 3; do cat "$SC_OUT/$SC_SIZE.watchseq.$SC_I.rc"; done | paste -sd' ' -)"
  expect_eq "WO-3 ($SC_SIZE) the third pass runs no tick: no gate pass, no status pass, no facts answer, no read of the table, no parse" \
    "0 0 0 0 0" "$(for SC_K in gate status facts table parse; do sc_seq_count "$SC_SIZE" 3 "$SC_K"; done | paste -sd' ' -)"
  expect_eq "WO-4 ($SC_SIZE) …and reads the log no more than the one question needs: at most one fold" "1" \
    "$([ "$(sc_seq_count "$SC_SIZE" 3 fold)" -le 1 ] && echo 1 || echo 0)"
  expect_eq "WO-5 ($SC_SIZE) …it asked the host: the integration branch was fetched, and nothing was printed" "yes||" \
    "$(cat "$SC_OUT/$SC_SIZE.watchseq.3.fetched")|$(cat "$SC_OUT/$SC_SIZE.watchseq.3.out")|$(cat "$SC_OUT/$SC_SIZE.watchseq.3.err")"
done
for SC_K in $SC_KINDS; do
  expect_eq "WO-6 the third pass counts the same $SC_K at n rows and 2n" "$(sc_seq_count n 3 "$SC_K")" "$(sc_seq_count 2n 3 "$SC_K")"
done

section "§CARD: the release approval card draws from one load of its rows, one pass of its findings, and the held facts"
# fails-when: the card's rows load the criteria again or ask a criterion's owing step and openness one at a time; or
# its findings start a process of the tool for a record's debt lines; or a shell of the card reads the held fold
# where the shell it was started from already held it. Then a read the card's one pass holds is made again.
# The world `f` is the run of n rows whose adversarial reading holds two findings and a debt line: the findings'
# reader reads it, and the debt verb is asked for it. Its card is run twice from the snapshot: once as it is, so the
# debt verb writes the debt, and once with the debt already in the ledger, as a card drawn again finds it, counted.
sc_card_records() {  # <record dir> -> the adversarial whole reading's findings, two notes and a debt line
  printf '%s\n' 'reviewed: main..wave/02-fx' 'findings: 2' \
    'finding: 1 S3 off - the card reads its rows twice' 'finding: 2 S4 off - the card names a row once' \
    'debt: duplicate card-rows-read lib/t1.sh:1' > "$1/adversarial-whole.md"
}
SC_WORLD_RECORDS=sc_card_records; export SC_WORLD_RECORDS
if sc_world f "$SC_N" > "$TMPROOT/f.world.out" 2>&1; then SC_CF=built; else SC_CF=""; cat "$TMPROOT/f.world.out"; fi
unset SC_WORLD_RECORDS
expect_eq "CARD-0 the run with findings is built" built "$SC_CF"
# The first card from the snapshot: the debt verb writes the record's debt into the ledger.
sc_run f card off
SC_CDEBT="$(sc_env "$POKER" debt list "$SC_PLAN" 2>&1)"
expect_contains "CARD-1 the card's findings asked the debt verb, which wrote the record's debt to the ledger" \
  "card-rows-read duplicate" "$SC_CDEBT"
expect_contains "CARD-1 the card's findings were read: the page counts the reading's two" "Findings — 2" \
  "$(cat "$SC_OUT/f.card.off.out" 2>/dev/null)"
# The counted card: the debt is in the ledger before it starts, so the verb writes nothing and the log is the one held.
rm -rf "$TMPROOT/f/live" && cp -Rp "$TMPROOT/f/snap" "$TMPROOT/f/live"
SC_W="$TMPROOT/f/live"; SC_ROOT="$SC_W/proj"; SC_PLAN="$SC_ROOT/.bionic/docs/plans/epic-01-fx/wave-02-fx.plan.md"
sc_env "$POKER" debt add record/wave-02-fx/adversarial-whole.md "$SC_PLAN" > "$TMPROOT/f.debt.out" 2>&1
rm -rf "$TMPROOT/f/snap" && cp -Rp "$TMPROOT/f/live" "$TMPROOT/f/snap"
sc_run f card on
expect_eq "CARD-2 the counted card draws the same page as the first" "$(cat "$SC_OUT/f.card.off.out")" "$(cat "$SC_OUT/f.card.on.out")"
for SC_SIZE in n 2n f; do
  SC_M="$(sc_count "$SC_SIZE" card matrix)"; SC_O="$(sc_count "$SC_SIZE" card owing)"; SC_H="$(sc_count "$SC_SIZE" card held)"
  # The judge the card asks loads the criteria and reads their owing once for each of its two gated steps; the rows
  # load them once more and read every owing step and openness in one pass, so three of each in all.
  expect_eq "CARD-3 ($SC_SIZE) the card loads the criteria three times at most, the judge's two and its rows' one ($SC_M)" 1 \
    "$([ "$SC_M" -ge 1 ] && [ "$SC_M" -le 3 ] && echo 1 || echo 0)"
  expect_eq "CARD-4 ($SC_SIZE) the card reads the owing steps three times at most, one pass each ($SC_O)" 1 \
    "$([ "$SC_O" -ge 1 ] && [ "$SC_O" -le 3 ] && echo 1 || echo 0)"
  # Two pokers each read it twice (the bound run's place, then the shell that primes), card.sh early once.
  expect_eq "CARD-5 ($SC_SIZE) the card's processes read the held fold four times at most ($SC_H)" 1 \
    "$([ "$SC_H" -ge 1 ] && [ "$SC_H" -le 4 ] && echo 1 || echo 0)"
done
# A record's debt line starts no process: the card over the run with findings reads the held fold as often as over
# the run with none.
expect_eq "CARD-6 the findings' debt verb, asked in the card, reads the held fold no more than a card with no debt line" \
  "$(sc_count n card held)" "$(sc_count f card held)"
[ -z "${SPEED_COUNTS_PRINTS:-}" ] || { mkdir -p "$SPEED_COUNTS_PRINTS"; sc_print f card on > "$SPEED_COUNTS_PRINTS/f.card.txt"; }

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
