#!/bin/bash
# tests/landing-line-2.test.sh — the landing line, part 2 of 2: §INPUTS through §LAND-RC-HAND.
#
# THE SUITE IS TWO PARTS (wave-39 T35; D1, D13, REQ-3 AC-3.3). One landing-line.test.sh promised more than the suite
# bar, ten minutes of the gate's promise, so it runs as two suites cut at a section boundary. Its governing header, its
# model world and the helpers both parts share are in tests/landing-line.prelude.sh, sourced below after the framework.
#
# Usage: bash tests/landing-line-2.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"
. "$(dirname "$0")/landing-line.prelude.sh"

ll_carrier_env   # the same environment part 1 sets where the carrier section begins (tests/landing-line.prelude.sh)

# ---------------------------------------------------------------------------
section "§INPUTS: the poll and --within read as numbers (read-structure-p12 #7, read-adversarial-p12 #4)"
expect_eq "(i1) BIONIC_LINE_POLL that is no number falls back to 1 s; a decimal one is kept" "1 0.2" \
  "$(BIONIC_LINE_POLL=abc bash -c '. "$1" && printf %s "$LINE_POLL"' _ "$LINE") $(BIONIC_LINE_POLL=0.2 bash -c '. "$1" && printf %s "$LINE_POLL"' _ "$LINE")"
RI="$(ll_rworld)"
ll_verb "$RI" T1 --within 08
expect_eq "(i2) --within 08 is eight seconds, not an octal error: the 5 s suite runs and lands" "0" "$LL_RC"

# ============================================================================ the landing's environment (wave-33 T2)
#
# REQ-7, D3: a suite proved at a landing starts as the whole run starts it, through the plugin's one
# suite primitive (lib/suite.sh): INT and QUIT at their defaults (job control on around each of the
# landing's two spawns, the booked.sh precedent), BIONIC_GATE_DIR unset in the suite, the runner's
# admission in BIONIC_GATE_ADMIT. Each fixture pins its OWN starting dispositions with perl, as slots
# K6 does: a shell started in the background without job control (an installed 1.15.0 landing starts
# this very suite that way) has INT and QUIT ignored at entry, and nothing below it can reset that.
LL_SUITE_LIB="${REPO}/payload/scripts/lib/suite.sh"
ll_dfl() { perl -e '$SIG{INT} = $SIG{QUIT} = "DEFAULT"; exec @ARGV or exit 126' "$@"; }
# The K6 controls of tests/slots.test.sh as a suite of their own, with the store and admission it sees.
LL_K6_BODY="$(cat <<'K6'
f=0; n=0
k6_row() { n=$((n + 1)); if [ "$2" = "$3" ]; then echo "PASS: $1"; else echo "FAIL: $1 (got: $3)"; f=$((f + 1)); fi; }
echo "entry: $(trap -p INT QUIT | tr '\n' ' ')"
k6_row "K6.1-like the INT trap runs" "got-int after" "$(echo $(bash -c 'trap "echo got-int" INT; kill -INT $$; sleep 0.2; echo after' 2>&1))"
k6_row "K6.3-like the QUIT trap runs" "got-quit after" "$(echo $(bash -c 'trap "echo got-quit" QUIT; kill -QUIT $$; sleep 0.2; echo after' 2>&1))"
k6_row "K6.5-like a process below dies of INT" "rc=130" "$(bash -c "sh -c 'kill -INT \$\$; echo survived'; echo \"rc=\$?\"" 2>&1)"
k6_row "the gate store is not the suite's" "unset" "${BIONIC_GATE_DIR-unset}"
echo "admit=${BIONIC_GATE_ADMIT-unset}"
echo "cwd=$(pwd -P)"
echo; echo "a.test.sh: $((n - f))/$n passed, $f failed  sections=1 setup=0"; [ "$f" -eq 0 ]
K6
)"
LL_SX="$WORLD_ROOT/suite-driver.sh"
cat > "$LL_SX" <<'SX'
#!/bin/bash
# <suite.sh> <start|exec> <tree> <suite> [admission]: the primitive, called from a shell of its own;
# LL_MUTANT is a sed over bionic_job.
. "$1" || exit 99
if [ -n "${LL_MUTANT:-}" ]; then eval "$(declare -f bionic_job | sed "$LL_MUTANT")"; fi
if [ "$2" = start ]; then
  bionic_suite_start ${5:+--admit "$5"} "$3" "$4" || { echo "start-rc=$?"; exit 0; }
  wait "$BIONIC_SUITE_PID"; echo "rc=$?"
else
  bionic_suite_exec ${5:+--admit "$5"} "$3" "$4"; echo "rc=$?"
fi
SX
ll_k6_tree() {  # <dir> -> a directory holding probe.sh, the K6 body
  mkdir -p "$1" && printf '#!/bin/bash\n%s\n' "$LL_K6_BODY" > "$1/probe.sh" && (cd "$1" && pwd -P)
}

# ---------------------------------------------------------------------------
section "§SIGNALS: a suite at a landing keeps its signal traps, and the whole run's store and admission (AC-7.1)"
# fails-when: slots K6.1, K6.3 or K6.5 is red under ready at a head where the suite is green through the door.
expect_true "(sig0) perl, which pins each fixture's own starting dispositions, is on PATH" command -v perl
expect_nonempty "(sig0) the caller's environment names a gate store (the world's), which the suite must not inherit" "${BIONIC_GATE_DIR:-}"
SXT="$(ll_k6_tree "$WORLD_ROOT/sx")"
G1="$(cd "$WORLD_ROOT" && ll_dfl bash "$LL_SX" "$LL_SUITE_LIB" start "$SXT" probe.sh 41 2>&1)"
expect_contains "(sig1-pre) bionic_suite_start ran the suite in its tree" "cwd=$SXT" "$G1"
expect_contains "(sig1) started as a job, its INT trap runs (K6.1)" "PASS: K6.1-like the INT trap runs" "$G1"
expect_contains "(sig1) …its QUIT trap runs (K6.3)" "PASS: K6.3-like the QUIT trap runs" "$G1"
expect_contains "(sig1) …the caller's admission is the suite's BIONIC_GATE_ADMIT" "admit=41" "$G1"
expect_contains "(sig1) …and its exit code is the suite's" "rc=0" "$G1"
expect_absent "(sig1) …no row of it fails" "FAIL:" "$G1"
G2="$(cd "$WORLD_ROOT" && BIONIC_GATE_ADMIT=7 ll_dfl bash "$LL_SX" "$LL_SUITE_LIB" start "$SXT" probe.sh 2>&1)"
expect_contains "(sig2-pre) the primitive ran without --admit" "cwd=$SXT" "$G2"
expect_contains "(sig2) with no admission of the caller's, an inherited BIONIC_GATE_ADMIT is left as it was" "admit=7" "$G2"
printf '#!/bin/bash\necho "cwd=$(pwd -P) store=${BIONIC_GATE_DIR-unset} admit=${BIONIC_GATE_ADMIT-unset}"\nread -r l; echo "stdin=${l:-none}"\nexit 3\n' > "$SXT/rc3.sh"
G3="$(cd "$WORLD_ROOT" && printf 'piped\n' | ll_dfl bash "$LL_SX" "$LL_SUITE_LIB" exec "$SXT" rc3.sh 42 2>&1)"
expect_eq "(sig3) bionic_suite_exec runs the suite to its end in its tree, without the store, with the admission, stdin closed, its rc the suite's" \
  "$(printf 'cwd=%s store=unset admit=42\nstdin=none\nrc=3' "$SXT")" "$G3"
G4="$( . "$LL_SUITE_LIB" 2>/dev/null; bionic_suite_exec --admit '' "$SXT" probe.sh 2>&1 )"; G4R=$?
expect_eq "(sig4) an empty --admit is refused (exit 2), naming the flag" "2" "$G4R"
expect_contains "(sig4) …saying so" "--admit" "$G4"
expect_absent "(sig4) …and nothing ran" "cwd=" "$G4"
# MUTANT: job control off in bionic_job. The suite starts as a plain background job, INT and QUIT ignored.
G5="$(cd "$WORLD_ROOT" && LL_MUTANT='s/set -m/:/' ll_dfl bash "$LL_SX" "$LL_SUITE_LIB" start "$SXT" probe.sh 43 2>&1)"
expect_contains "(sig5m-pre) the mutant ran the suite" "cwd=$SXT" "$G5"
expect_contains "(sig5m) MUTANT job control off: the INT trap is not run (the rows can fail)" "FAIL: K6.1-like the INT trap runs" "$G5"

# THE LANDING PATH: T1 lands a suite of the K6 controls through `ready`, from a carrier whose own
# dispositions are the defaults, as the door's and the whole run's are.
world_cost a.test.sh 5 0.5 5
ll_verb_dfl() {  # <root> <row> — ll_verb, from a shell whose INT and QUIT are at their defaults
  printf 'ready\n' >> "$(world_verbs)"
  LL_OUT="$( cd "$1/.worktrees/$2" && ll_dfl bash "$SPAWN" ready 2>&1 )"; LL_RC=$?
}
RG="$(ll_world)"; ll_launch "$RG" T1 a
ll_commit_suite "$RG" T1 a "$LL_K6_BODY"
ll_verb_dfl "$RG" T1
KG="$(ll_last_cand "$RG" T1)"; LG="$RG/.bionic/docs/record/wave-x/line/T1-a-${KG:0:12}.log"
expect_contains "(sig6-pre) the suite ran on the candidate, in the landing tree" "entry: " "$(cat "$LG" 2>/dev/null)"
expect_eq "(sig6) the K6 controls are green at the landing: ready exits 0, the candidate's verdict green" "0 green" \
  "$LL_RC $(ll_results "$RG" T1 "$KG")"
expect_absent "(sig6) …no row of the suite fails under the landing" "FAIL:" "$(cat "$LG" 2>/dev/null)"
ll_req_kind() {  # <admission id> -> its request's kind= line in the world's store, or the id when it is none
  case "$1" in ''|*[!0-9]*) echo "admit=$1"; return 0 ;; esac
  grep '^kind=' "$BIONIC_GATE_DIR/requests/$1" 2>/dev/null
}
GA="$(sed -n 's/^admit=//p' "$LG" 2>/dev/null)"
expect_eq "(sig7) the suite's BIONIC_GATE_ADMIT is the landing's own admission, a request of kind landing in the gate's store" \
  "kind=landing" "$(ll_req_kind "$GA")"
# MUTANTS, one spawn each: a copy of the library with ONE of the landing's two spawns a plain `&`. R4
# proved either alone leaves the suite's INT and QUIT ignored.
ll_lib_mutant() {  # <dir> <file> <from> <to> -> a copy of the library, <from> made <to> in <file>, _ll_plain defined there
  rm -rf "$1"; cp -R "$REPO/payload/scripts/lib" "$1" || return 1
  sed "s/$3/$4/" "$1/$2" > "$1/$2.m" && mv "$1/$2.m" "$1/$2" || return 1
  printf '\n_ll_plain() { "$@" & BIONIC_JOB_PID=$!; }\n' >> "$1/$2"
}
for LGM in "line.sh|bionic_job bash -c|_ll_plain bash -c|the carrier's spawn of the runner" \
           "suite.sh|bionic_job _bionic_suite_run|_ll_plain _bionic_suite_run|the runner's spawn of the suite"; do
  IFS='|' read -r LGF LGA LGB LGW <<EOF_LGM
$LGM
EOF_LGM
  RGM="$(ll_world)"; ll_launch "$RGM" T1 a
  ll_commit_suite "$RGM" T1 a "$LL_K6_BODY"
  ll_lib_mutant "$WORLD_ROOT/lib-${LGF%.sh}" "$LGF" "$LGA" "$LGB"
  expect_eq "(sig8m-pre) the mutant copy of $LGF is doctored: one '$LGB' spawn, no '$LGA' left" "1 0" \
    "$(grep -c "$LGB" "$WORLD_ROOT/lib-${LGF%.sh}/$LGF") $(grep -c "$LGA" "$WORLD_ROOT/lib-${LGF%.sh}/$LGF")"
  ( cd "$RGM/.worktrees/T1" && ll_dfl bash "$LL_RD" "$WORLD_ROOT/lib-${LGF%.sh}" > "$WORLD_ROOT/g8-${LGF}.out" 2>&1 )
  KGM="$(ll_last_cand "$RGM" T1)"; LGL="$RGM/.bionic/docs/record/wave-x/line/T1-a-${KGM:0:12}.log"
  expect_contains "(sig8m-pre) the mutant ran the suite on a candidate ($LGW plain)" "entry: " "$(cat "$LGL" 2>/dev/null)"
  expect_contains "(sig8m) MUTANT $LGW a plain background job: K6.1 is red at the landing (the rows can fail)" \
    "FAIL: K6.1-like the INT trap runs" "$(cat "$LGL" 2>/dev/null)"
done

# THE RUNNER'S --one WORKER calls the primitive when the plugin library is present, and keeps its own
# path for a tree without it. A scratch tree holds a copy of tests/run.sh; a spy library records the call.
ll_one_tree() {  # <dir> <with: real | spy | none> -> the tree: tests/run.sh, tests/x.test.sh, the library or not
  rm -rf "$1"; mkdir -p "$1/tests" || return 1
  cp "$REPO/tests/run.sh" "$1/tests/run.sh"
  printf '#!/bin/bash\necho "cwd=$(pwd -P) store=${BIONIC_GATE_DIR-unset} admit=${BIONIC_GATE_ADMIT-unset}"\nexit 3\n' > "$1/tests/x.test.sh"
  case "$2" in
    real) mkdir -p "$1/payload/scripts/lib" && cp "$LL_SUITE_LIB" "$1/payload/scripts/lib/suite.sh" ;;
    spy) mkdir -p "$1/payload/scripts/lib"
         printf 'bionic_suite_exec() { printf "%%s\\n" "$*" >> "%s/spy.log"; ( cd "$1" && bash "$2" ); }\n' "$1" > "$1/payload/scripts/lib/suite.sh" ;;
  esac
  printf 'x.test.sh\tbash tests/x.test.sh\n' > "$1/queue"; mkdir -p "$1/work"
  (cd "$1" && pwd -P)
}
ll_one() {  # <tree> -> runs its --one worker for x.test.sh, BIONIC_GATE_ADMIT=9 inherited; prints <rc file>|<out>
  ( cd "$1" && BIONIC_GATE_ADMIT=9 BIONIC_TEST_QUEUE="$1/queue" BIONIC_TEST_WORK="$1/work" bash tests/run.sh --one x.test.sh </dev/null >/dev/null 2>&1 )
  printf '%s|%s' "$(cat "$1/work/x.test.sh.rc" 2>/dev/null)" "$(cat "$1/work/x.test.sh.out" 2>/dev/null)"
}
O1="$(ll_one_tree "$WORLD_ROOT/one-spy" spy)"
expect_eq "(sig9) --one with the library present calls bionic_suite_exec with the tree and the suite's path" \
  "$O1 tests/x.test.sh" "$(ll_one "$O1" >/dev/null; cat "$O1/spy.log" 2>/dev/null)"
O2="$(ll_one_tree "$WORLD_ROOT/one-real" real)"
expect_eq "(sig9) …and through the real primitive the suite runs without the store, the inherited admission kept, its rc in the .rc file" \
  "3|cwd=$O2 store=unset admit=9" "$(ll_one "$O2")"
O3="$(ll_one_tree "$WORLD_ROOT/one-none" none)"
expect_eq "(sig10) a tree without the plugin library runs the suite by the runner's own path, the same" \
  "3|cwd=$O3 store=unset admit=9" "$(ll_one "$O3")"
expect_false "(sig10) …and no spy log exists there" test -e "$O3/spy.log"

# ---------------------------------------------------------------------------
section "§CAUSE: a standing red names its cause and the run that disagrees; the floor judge does not count an environment red (AC-7.2)"
# fails-when: a landing records a standing red with no cause, or the floor judge counts an environment red as the suite's state.
#
# `a` is red at the accepted head while $LL_SIG/<tag>.env exists (a fact outside the tree, as the share
# is) and green otherwise. T2 merges the head first, so the candidate's tree is T2's own, where a door
# run (its stamp, as booked.sh writes one) can be green: that run disagrees with the landing's red.
# a.test.sh DECLARES T2's code file (wave-35 T38; A-T38-1): since T9 the floor judge proves a commit's code
# only through the suites the anchor index names for it (lib/anchors.sh `anchors_index`), and T2 commits
# T2.txt (world_repo's `T2 work`), so the suite carries the shaped call the index reads. This a.test.sh is
# RUN by the landing and sources no assert.sh, so `anchor` is a no-op here; the extractor reads the call.
ll_cause_world() {  # <tag> [<lands_on>; default a] -> root
  local r
  r="$(ll_world)" || return 1
  ll_launch "$r" T2 "${2:-a}"
  printf '#!/bin/bash\nanchor() { :; }\nanchor file T2.txt %s\necho "PASS: a ran"\nif [ -e "$LL_SIG/%s.env" ]; then echo "FAIL: a reads its environment"; echo; echo "a.test.sh: 1/2 passed, 1 failed  sections=1 setup=0"; exit 1; fi\necho; echo "a.test.sh: 1/1 passed, 0 failed  sections=1 setup=0"\n' \
    "'T2 work'" "$1" > "$r/tests/a.test.sh"
  git -C "$r" commit -qam "a reads its environment" || return 1
  git -C "$r/.worktrees/T2" merge -q --no-edit wave/x >/dev/null 2>&1 || return 1
  : > "$LL_SIG/$1.env"
  printf '%s' "$r"
}
ll_stamp() {  # <tree> <commit> <suite> <rc> <at> — a door run's stamp in the tree's git dir
  printf 'stamp/v1|head=%s|dirty=0|rc=%s|at=%s|suites=%s|cmd=bash tests/run.sh --only %s\n' "$2" "$4" "$5" "$3" "$3" \
    >> "$(git -C "$1" rev-parse --absolute-git-dir)/bionic-stamps"
}
ll_runs() {  # <root> <suite> <red commit> <green commit> -> "<reds> <greens>": the records the floor judge weighs, for the suite
  ( . "$REPO/payload/scripts/lib/proof.sh" >/dev/null 2>&1; _proof_records "$1" "$(ll_rec "$1")" ) 2>/dev/null \
    | awk -F'\t' -v s="$2" -v rc="$3" -v gc="$4" '$1 == "R" && $4 == s { if ($5 == "red" && $3 == rc) r++; if ($5 == "green" && $3 == gc) g++ }
      END { print r + 0, g + 0 }'
}
RC1="$(ll_cause_world c1)"; HC1="$(ll_head "$RC1")"; TC1="$(git -C "$RC1/.worktrees/T2" rev-parse HEAD)"
ll_stamp "$RC1/.worktrees/T2" "$TC1" a.test.sh 0 2020-01-01T00:00:00Z
ll_verb "$RC1" T2
KC1="$(ll_last_cand "$RC1" T2)"; LC1="$RC1/.bionic/docs/record/wave-x/line/T2-a-${HC1:0:12}.log"
expect_eq "(cause1-pre) T2's red fails at the head too: published (exit 0), its own verdict red" "0 $KC1 red" \
  "$LL_RC $(ll_head "$RC1") $(ll_results "$RC1" T2 "$KC1")"
expect_eq "(cause1-pre) the candidate's tree is T2's, where the door run was green" \
  "$(git -C "$RC1" rev-parse "$TC1^{tree}")" "$(git -C "$RC1" rev-parse "$KC1^{tree}")"
expect_regex "(cause1) the standing event names its cause, environment, and the run that disagrees: the door run's stamp" \
  "^line/v1\\|ev=standing\\|head=${HC1}\\|suite=a.test.sh\\|lines=1\\|log=${LC1}\\|cause=environment\\|against=stamp:${TC1}@2020-01-01T00:00:00Z\\|at=[0-9T:-]+Z$" \
  "$(ll_ev "$RC1" standing)"
expect_contains "(cause2) ready reports the environment red as a defect, with the run that disagrees and the head's log" \
  "STANDING T2 a.test.sh cause=environment against=stamp:${TC1}@2020-01-01T00:00:00Z log=${LC1}" "$LL_OUT"
expect_eq "(cause3) the records the floor judge weighs leave the environment red out and keep the door run's green" \
  "0 1" "$(ll_runs "$RC1" a.test.sh "$KC1" "$TC1")"
RC2="$(ll_cause_world c2)"; HC2="$(ll_head "$RC2")"
ll_verb "$RC2" T2
KC2="$(ll_last_cand "$RC2" T2)"; LC2="$RC2/.bionic/docs/record/wave-x/line/T2-a-${HC2:0:12}.log"
expect_eq "(cause4-pre) with no run disagreeing, T2's red is standing all the same: published, its verdict red" "0 $KC2 red" \
  "$LL_RC $(ll_head "$RC2") $(ll_results "$RC2" T2 "$KC2")"
expect_regex "(cause4) …and its standing event names its cause, code, and no run disagreeing" \
  "^line/v1\\|ev=standing\\|head=${HC2}\\|suite=a.test.sh\\|lines=1\\|log=${LC2}\\|cause=code\\|against=-\\|at=[0-9T:-]+Z$" \
  "$(ll_ev "$RC2" standing)"
expect_contains "(cause5-pre) ready printed its landing" "LANDED T2 $KC2" "$LL_OUT"
expect_absent "(cause5) …and no STANDING report: a code red is the branch's own, as before" "STANDING " "$LL_OUT"
expect_eq "(cause6) the records the floor judge weighs keep the code red as the suite's state at the landed commit" \
  "1" "$(ll_runs "$RC2" a.test.sh "$KC2" "$KC2" | cut -d' ' -f1)"
# A STANDING EVENT WITH NO cause= (a record written before 1.16.0) is counted as code: the judge
# drops only what an environment-class event names.
RC3="$(ll_cause_world c3)"; HC3="$(ll_head "$RC3")"; TC3="$(git -C "$RC3/.worktrees/T2" rev-parse HEAD)"
ll_stamp "$RC3/.worktrees/T2" "$TC3" a.test.sh 0 2020-01-01T00:00:00Z
ll_verb "$RC3" T2
KC3="$(ll_last_cand "$RC3" T2)"
expect_contains "(cause7-pre) the landing wrote an environment-class standing event" "cause=environment" "$(ll_ev "$RC3" standing)"
sed 's/|cause=environment|against=[^|]*|/|/' "$(ll_rec "$RC3")" > "$(ll_rec "$RC3").n" && mv "$(ll_rec "$RC3").n" "$(ll_rec "$RC3")"
expect_eq "(cause7) a standing event with no cause is counted: the red stays in the records the floor judge weighs, the door run's green beside it" \
  "1 1" "$(ll_runs "$RC3" a.test.sh "$KC3" "$TC3")"

# ---------------------------------------------------------------------------
section "§KEY: a standing red and the floor judge key a suite by its file name (wave-35 T6; REQ-5 AC-5.2; D14)"
# A stamp names a suite by its file name (the wall's --suites); since wave-34 T27 a landing files its verdict
# under the declared path. `Lands-on: tests/a.test.sh` and a door run's green of `a.test.sh` on the same tree
# are one suite, as the gate, cost and debt already read them. fails-when: the standing red stays `code`
# (critic-adversarial-2 #1, the debt line `suite-key`).
RK="$(ll_cause_world k1 tests/a.test.sh)"; HK="$(ll_head "$RK")"; TK="$(git -C "$RK/.worktrees/T2" rev-parse HEAD)"
ll_stamp "$RK/.worktrees/T2" "$TK" a.test.sh 0 2020-01-01T00:00:00Z
ll_verb "$RK" T2
KK="$(ll_last_cand "$RK" T2)"
expect_eq "(key0-pre) Lands-on: tests/a.test.sh, red at the head too: published (exit 0), its verdict red" "0 $KK red" \
  "$LL_RC $(ll_head "$RK") $(ll_results "$RK" T2 "$KK")"
expect_contains "(key0-pre) …the verdict filed under the declared path" "|suite=tests/a.test.sh|result=red|" "$(ll_ev "$RK" verdict)"
expect_contains "(key1) the door run's green of a.test.sh on the candidate's tree makes the standing red environment" \
  "|cause=environment|against=stamp:${TK}@2020-01-01T00:00:00Z|" "$(ll_ev "$RK" standing)"
expect_contains "(key2) …and ready reports it as one" "STANDING T2 tests/a.test.sh cause=environment against=stamp:${TK}@2020-01-01T00:00:00Z" "$LL_OUT"
expect_eq "(key3) the records the floor judge weighs key the suite by file name: the declared path's red is left out, the door run's green kept" \
  "0 1" "$(ll_runs "$RK" a.test.sh "$KK" "$TK")"

# ---------------------------------------------------------------------------
section "§CAUSE-TREE: a standing red's cause reads only runs the shim could place (wave-35 T6; REQ-5 AC-5.1; D14, Δ7)"
# 1.17.0: a door run in a writer's DIRTY tree, typed from the main checkout behind a `cd` the wall could not
# read, was stamped where the shim stood, as a clean run at the main head; that "green" made a code red
# read as environment (research-walls §5). The wall now hands such a run --unplaced: the shim stamps
# nothing and says on the run's output that the run did not count. fails-when: a green record appears at
# the main head, or the standing red reads environment.
RT="$(ll_cause_world t1)"; HT="$(ll_head "$RT")"
CT_SHIM="$REPO/payload/scripts/booked.sh"
ct_run() {  # <root> [shim options] — from the main checkout, as the wall wraps `cd "$T" || exit 1; bash tests/a.test.sh`
  CT_OUT="$(cd "$1" && T="$1/.worktrees/T2" bash "$CT_SHIM" "${@:2}" --suites a.test.sh -- 'cd "$T" || exit 1; bash tests/a.test.sh' 2>&1)"; CT_RC=$?
}
ct_green_at() {  # <root> <commit> -> how many green records of a.test.sh the floor judge reads at <commit>
  ( . "$REPO/payload/scripts/lib/proof.sh" >/dev/null 2>&1; _proof_records "$1" "$(ll_rec "$1")" ) |
    awk -F'\t' -v h="$2" '$1 == "R" && $3 == h && $4 == "a.test.sh" && $5 == "green" { n++ } END { print n + 0 }'
}
# The writer's tree, dirty: an uncommitted a.test.sh, green whatever the environment.
printf '#!/bin/bash\necho "PASS: a ran dirty"\necho; echo "a.test.sh: 1/1 passed, 0 failed  sections=1 setup=0"\n' > "$RT/.worktrees/T2/tests/a.test.sh"
ct_run "$RT" --unplaced
expect_eq "(ct0-pre) the unplaced run ran, green, in the writer's dirty tree" "0 1" \
  "$CT_RC $(printf '%s\n' "$CT_OUT" | grep -c 'PASS: a ran dirty')"
expect_contains "(ct1) AC-5.1 the run's own output says it did not count" "not counted" "$CT_OUT"
expect_eq "(ct2) AC-5.1 …and it left no record at the main head" "0" "$(ct_green_at "$RT" "$HT")"
git -C "$RT/.worktrees/T2" checkout -q -- tests/a.test.sh
ll_verb "$RT" T2
expect_contains "(ct3-pre) T2's red fails at the head too: published" "LANDED T2 " "$LL_OUT"
expect_contains "(ct3) AC-5.1 the standing red's cause reads only the runs it can place: code, no run named" \
  "|cause=code|against=-|" "$(ll_ev "$RT" standing)"
expect_absent "(ct3b) …and no STANDING report" "STANDING " "$LL_OUT"
# The positive on the same extractor, same world: the shim handed no --unplaced stamps where it stands,
# the main checkout (now at the landed head), and that run is a green record there (the wrap 1.17.0 sent).
printf '#!/bin/bash\necho "PASS: a ran dirty"\necho; echo "a.test.sh: 1/1 passed, 0 failed  sections=1 setup=0"\n' > "$RT/.worktrees/T2/tests/a.test.sh"
HT4="$(git -C "$RT" rev-parse HEAD)"
expect_eq "(ct4-pre) the main checkout is clean at the branch head" "$(ll_head "$RT") 0" "$HT4 $(git -C "$RT" status --porcelain | awk 'END { print NR }')"
ct_run "$RT"
expect_eq "(ct4) [positive] the same run, stamped where the shim stands, is a green record at the main head" "1" \
  "$(ct_green_at "$RT" "$HT4")"
expect_absent "(ct4b) …and says nothing of not counting" "not counted" "$CT_OUT"
# THE GATE'S TREE IS THE PLACEMENT READER'S (wave-36 T25; D11, AC-5.1). The shim asks the gate from the
# tree the run is in: its --stamp-dir, else `cmd_place <command> <cwd> suite` (lib/placement.sh), the
# question the wall asks for the stamp. Before T25 it read only a plain-word `cd` opening the text, so a
# pinned variable or a cd behind `true &&` asked from the main checkout while the run went to the tree.
# Read off the one request the shim's run leaves at the gate (its `tree=`, the toplevel git names).
ct_tree() {  # <root> <command> -> the tree= of the request the shim's run of <command> wrote, from the main checkout
  local before after f
  before="$(ls "$BIONIC_GATE_DIR/requests" 2>/dev/null)"
  ( cd "$1" && T="$1/.worktrees/T2" bash "$CT_SHIM" --suites a.test.sh -- "$2" >/dev/null 2>&1 )
  after="$(ls "$BIONIC_GATE_DIR/requests" 2>/dev/null)"
  f="$(comm -13 <(printf '%s\n' "$before" | sort) <(printf '%s\n' "$after" | sort) | grep . | head -n 1)"
  [ -n "$f" ] && sed -n 's/^tree=//p' "$BIONIC_GATE_DIR/requests/$f" | tail -n 1
}
CT_T2="$(cd "$RT/.worktrees/T2" && pwd -P)"; CT_MAIN="$(cd "$RT" && pwd -P)"
expect_eq "(ct5-pre) [positive] a literal leading cd asks from the tree it names" "$CT_T2" \
  "$(ct_tree "$RT" "cd $RT/.worktrees/T2 && bash tests/a.test.sh")"
expect_eq "(ct5) AC-5.1 a pinned variable's cd asks from the tree it names, not the main checkout" "$CT_T2" \
  "$(ct_tree "$RT" "D=$RT/.worktrees/T2; cd \"\$D\" && bash tests/a.test.sh")"
expect_eq "(ct6) AC-5.1 …and so does a literal cd behind 'true &&'" "$CT_T2" \
  "$(ct_tree "$RT" "true && cd $RT/.worktrees/T2 && bash tests/a.test.sh")"
expect_eq "(ct7) a cd the reader cannot be sure of asks from where the shim stands" "$CT_MAIN" \
  "$(ct_tree "$RT" 'cd "$T" || exit 1; bash tests/a.test.sh')"

# ---------------------------------------------------------------------------
section "§PATH: a landing runs a Lands-on suite where it lives, not only under tests/ (wave-34 T7; D23, AC-14.4)"
# A suite under `scripts/deploy/__tests__/` reached `ready` as `x.test.sh` and was started as
# `bash tests/x.test.sh`: no such file, no verdict, STALLED. The launch line below is written by the real
# lift and the real row writer. fails-when: a suite under a directory other than tests/ stalls at `ready`
# with "No such file". THE DECLARED PATH IS THE ONE RUN (wave-34 T27; critic S2): the lift keeps a
# path-qualified entry as declared, so a same-named tests/<name> never stands in for it (pa4, pa5).
PA_ON="$( . "${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/brief.sh" 2>/dev/null
  brief_field "$(lift_contract_fields 'Lands-on: scripts/deploy/__tests__/x.test.sh')" lands_on)"
expect_eq "(pa0) precondition: the lift keeps the path-qualified Lands-on: line as declared (the positive on that extractor)" \
  "scripts/deploy/__tests__/x.test.sh" "$PA_ON"
world_cost x.test.sh 5 0.5 5
ll_commit_at() {  # <root> <row> <path in the tree> <suite file name> [<rc>] — the row commits <path> as a suite that says where it ran, green (rc 0) or red
  local t="$1/.worktrees/$2" rc="${5:-0}" end="1/1 passed, 0 failed" line="PASS: $3 ran"
  [ "$rc" = 0 ] || { end="0/1 passed, 1 failed"; line="FAIL: $3 ran"; }
  mkdir -p "$t/$(dirname "$3")"
  printf '#!/bin/bash\necho "%s"\necho "ran-from=$(pwd -P) as=$0"\necho\necho "%s: %s  sections=1 setup=0"\nexit %s\n' \
    "$line" "$4" "$end" "$rc" > "$t/$3"
  git -C "$t" add "$3" && git -C "$t" commit -qm "$2: $3 as planted"
}
PA="$(ll_world)"; ll_launch "$PA" T1 "$PA_ON"
ll_commit_at "$PA" T1 scripts/deploy/__tests__/x.test.sh x.test.sh
expect_false "(pa0) precondition: the tree has no tests/x.test.sh, so the old path names nothing" test -e "$PA/.worktrees/T1/tests/x.test.sh"
ll_verb "$PA" T1
KPA="$(ll_last_cand "$PA" T1)"
expect_eq "(pa1) AC-14.4 Lands-on: scripts/deploy/__tests__/x.test.sh runs and lands: ready exits 0, the candidate's verdict green" "0 green" \
  "$LL_RC $(ll_results "$PA" T1 "$KPA")"
expect_contains "(pa1b) …printing LANDED" "LANDED T1 $KPA" "$LL_OUT"
expect_contains "(pa1c) …the log is the suite's own, started at the path it lives at, in the landing tree" \
  "as=scripts/deploy/__tests__/x.test.sh" "$(cat "$PA/.bionic/docs/record/wave-x/line/T1-x-${KPA:0:12}.log" 2>/dev/null)"
expect_absent "(pa1d) …and no 'No such file'" "No such file" "$(cat "$PA/.bionic/docs/record/wave-x/line/T1-x-${KPA:0:12}.log" 2>/dev/null)"
# A suite under tests/ is still started there, whatever else carries its name.
PB="$(ll_world)"; ll_launch "$PB" T1 x
ll_commit_at "$PB" T1 tests/x.test.sh x.test.sh
ll_commit_at "$PB" T1 scripts/deploy/__tests__/x.test.sh x.test.sh
ll_verb "$PB" T1
KPB="$(ll_last_cand "$PB" T1)"
expect_eq "(pa2) a suite named x.test.sh under tests/ and elsewhere: tests/ wins, as before" "0 green" "$LL_RC $(ll_results "$PB" T1 "$KPB")"
expect_contains "(pa2b) …the log shows tests/x.test.sh ran" "as=tests/x.test.sh" "$(cat "$PB/.bionic/docs/record/wave-x/line/T1-x-${KPB:0:12}.log" 2>/dev/null)"
# Two files of that name and neither under tests/: ready does not pick one. The suite cannot start, as for
# any suite the tree does not have, and the entry stalls where the writer sees it.
PC="$(ll_world)"; ll_launch "$PC" T1 x
ll_commit_at "$PC" T1 scripts/deploy/__tests__/x.test.sh x.test.sh
ll_commit_at "$PC" T1 other/x.test.sh x.test.sh
ll_verb "$PC" T1
expect_eq "(pa3) the same name at two paths, none under tests/: ready picks neither and stalls (exit 70, two none verdicts)" "70 none none" \
  "$LL_RC $(ll_results "$PC" T1 "$(ll_last_cand "$PC" T1)")"
# The declared path runs even when tests/ carries a suite of the same name: here tests/x.test.sh is green
# and the declared scripts/deploy/__tests__/x.test.sh is red, so a landing that ran the first would land.
# fails-when: ready runs tests/<name> in place of the declared path and lands green (the critic's S2).
PD="$(ll_world)"; ll_launch "$PD" T1 "$PA_ON"
ll_commit_at "$PD" T1 tests/x.test.sh x.test.sh
ll_commit_at "$PD" T1 scripts/deploy/__tests__/x.test.sh x.test.sh 1
ll_verb "$PD" T1
KPD="$(ll_last_cand "$PD" T1)"
expect_eq "(pa4) Lands-on: scripts/deploy/__tests__/x.test.sh, red, beside a green tests/x.test.sh: ready returns the row (exit 1, verdict red)" \
  "1 red" "$LL_RC $(ll_results "$PD" T1 "$KPD")"
expect_contains "(pa4b) …RED names the declared path" "RED T1 scripts/deploy/__tests__/x.test.sh " "$LL_OUT"
expect_contains "(pa4c) …its verdict is filed under the declared path" "|suite=scripts/deploy/__tests__/x.test.sh|result=red|" \
  "$(ll_ev "$PD" verdict)"
expect_contains "(pa4d) …and the log is the declared suite's run" "as=scripts/deploy/__tests__/x.test.sh" \
  "$(cat "$PD/.bionic/docs/record/wave-x/line/T1-x-${KPD:0:12}.log" 2>/dev/null)"
expect_absent "(pa4e) …not tests/x.test.sh's" "as=tests/x.test.sh" \
  "$(cat "$PD/.bionic/docs/record/wave-x/line/T1-x-${KPD:0:12}.log" 2>/dev/null)"
expect_absent "(pa4f) …and nothing LANDED" "LANDED T1" "$LL_OUT"
# A declared path the tree does not have is never replaced by a same-named file: the suite cannot start,
# and the entry stalls on the declared path. fails-when: ready falls back to tests/<name> and lands.
PE="$(ll_world)"; ll_launch "$PE" T1 "$PA_ON"
ll_commit_at "$PE" T1 tests/x.test.sh x.test.sh
ll_verb "$PE" T1
KPE="$(ll_last_cand "$PE" T1)"
expect_eq "(pa5) Lands-on: scripts/deploy/__tests__/x.test.sh, absent from the tree, beside tests/x.test.sh: ready stalls (exit 70, two none verdicts)" \
  "70 none none" "$LL_RC $(ll_results "$PE" T1 "$KPE")"
expect_contains "(pa5b) …STALLED" "STALLED T1 " "$LL_OUT"
expect_contains "(pa5c) …the verdicts filed under the declared path" "|suite=scripts/deploy/__tests__/x.test.sh|result=none|" \
  "$(ll_ev "$PE" verdict)"
expect_contains "(pa5d) …the log names the declared path it could not start" "scripts/deploy/__tests__/x.test.sh" \
  "$(cat "$PE/.bionic/docs/record/wave-x/line/T1-x-${KPE:0:12}.log" 2>/dev/null)"
expect_absent "(pa5e) …and tests/x.test.sh never ran" "as=tests/x.test.sh" \
  "$(cat "$PE/.bionic/docs/record/wave-x/line/T1-x-${KPE:0:12}"*.log 2>/dev/null)"
# The declared debt names a suite by its file name (the wall writes `lands_red=` so), and a path-qualified
# suite of that name is the debt: its red publishes with the debt written. fails-when: the debt is matched
# against the declared path's whole spelling, so the declared red returns the row, or publishes with no debt.
PF="$(ll_world)"; ll_launch "$PF" T1 "$PA_ON" lands_red='x.test.sh until T9'
ll_commit_at "$PF" T1 scripts/deploy/__tests__/x.test.sh x.test.sh 1
ll_verb "$PF" T1
KPF="$(ll_last_cand "$PF" T1)"
expect_eq "(pa6) a declared red on the path-qualified suite publishes (exit 0, verdict red)" "0 red" \
  "$LL_RC $(ll_results "$PF" T1 "$KPF")"
expect_contains "(pa6b) …its verdict filed under the declared path" "|suite=scripts/deploy/__tests__/x.test.sh|result=red|" \
  "$(ll_ev "$PF" verdict)"
expect_eq "(pa6c) …saying DEBT for the declared suite, once" "1" "$(printf '%s\n' "$LL_OUT" | grep -c '^DEBT T1 x.test.sh ')"
expect_eq "(pa6d) …and the gate's reader of the bound plan deals the debt" "debt	x.test.sh	T9" \
  "$(bash -c '. "$1/proof.sh" && proof_debts "$2"' _ "$REPO/payload/scripts/lib" "$(ll_plan "$PF")" | cut -f1-3)"

# ---------------------------------------------------------------------------
section "§DRAIN: a landing drains its suites at most J at once, J the gate's answer; one tree per candidate, the red judge in another (wave-37 T1; D3, REQ-1 AC-1.1; wave-38 T6, D21)"
#
# The planted machine: share 80 on 5 cores is room 4.0; at load 0.5 the gate answers 2 (0.5 + PROMISE,
# then 2 × PROMISE + PROMISE = 4.83 > 4.0), and with one run admitted it answers 1: J=2, whatever the
# order the runs end in. The branch carries four suites. `a` fails one planted line on the
# candidate and at the accepted head alike (a standing red, judged by a run at the head); `b`, `c`
# and `d` each write `start <HEAD> <tree>`, wait for their go file, write `end <HEAD> <tree>` and end
# green. T1 adds a file of its own and lands on all four. The landing tree's points are read by a spy
# over `landing_tree_point` (the anchor below), so "pointed once" is counted, not inferred.
ll_drain_body() {  # <tag> <name> — start, ll_block_body's wait for <tag>-<name>.go (30 s at most), end; green
  printf 'echo "start $(git rev-parse HEAD) $(pwd -P)" >> "$LL_SIG/%s-%s.runs"\n%s\necho "end $(git rev-parse HEAD) $(pwd -P)" >> "$LL_SIG/%s-%s.runs"\necho "PASS: %s"; echo; echo "%s.test.sh: 1/1 passed, 0 failed  sections=1 setup=0"; exit 0\n' \
    "$1" "$2" "$(ll_block_body "$1-$2" "$2" green | sed -n 2p)" "$1" "$2" "$2" "$2"
}
ll_drain_world() {  # <tag> -> root; T1 lands on a b c d, all four carried by the branch
  local r s
  r="$(ll_world)" || return 1
  ll_launch "$r" T1 'a b c d'
  printf '#!/bin/bash\necho "run $(git rev-parse HEAD) $(pwd -P)" >> "$LL_SIG/%s-a.runs"\necho "FAIL: a planted red"\necho; echo "a.test.sh: 0/1 passed, 1 failed  sections=1 setup=0"; exit 1\n' \
    "$1" > "$r/tests/a.test.sh"
  for s in b c d; do printf '#!/bin/bash\n%s' "$(ll_drain_body "$1" "$s")" > "$r/tests/$s.test.sh"; done
  git -C "$r" add tests && git -C "$r" commit -qm "the branch's four suites" || return 1
  printf 'T1 adds this\n' > "$r/.worktrees/T1/drain.txt"
  git -C "$r/.worktrees/T1" add drain.txt && git -C "$r/.worktrees/T1" commit -qm "T1: a file of its own" || return 1
  printf '%s' "$r"
}
ll_live_landings() {  # -> the keys of the landing requests admitted and not ended, sorted
  local f
  for f in "$BIONIC_GATE_DIR"/requests/*; do
    grep -q '^admitted=' "$f" && ! grep -q '^ended=' "$f" && grep -q '^kind=landing$' "$f" && sed -n 's/^key=//p' "$f"
  done | sort | tr '\n' ' ' | sed 's/ $//'
}
ll_widths() {  # <root> <commit> -> `suite:result:width` of each verdict on <commit>, in record order
  ll_ev "$1" verdict | grep -F "|commit=$2|" | while IFS= read -r v; do
    printf '%s:%s:%s ' "$(ll_field "$v" suite)" "$(ll_field "$v" result)" "$(ll_field "$v" width)"
  done | sed 's/ $//'
}
world_machine 5 8192 40 0.5
expect_eq "(dr0-pre) the planted machine: the gate answers a landing with nothing open 2" "2" "$(ll_width_ask dr-probe)"
RDR="$(ll_drain_world d)"; HDR="$(ll_head "$RDR")"
# THE SPY IS NO MUTATION, so it is no shaped anchor: framework §21 checks this suite's anchors on a copy
# that holds line.sh and not worktree.sh. Its precondition is the row below, and (dr4)'s first row.
DR_SPY='s/local t="/echo "$1 $2" >> "$LL_SIG\/d.points"; local t="/'
expect_contains "(dr0-pre) the spy is in landing_tree_point as the driver defines it" 'echo "$1 $2" >> "$LL_SIG/d.points"; local t=' \
  "$(declare -f landing_tree_point | sed "$DR_SPY")"
LL_MUTANT="$DR_SPY" LL_MUTANT_FN=landing_tree_point ll_drive "$RDR" T1 "$WORLD_ROOT/d.out"; DR_BG=$!
expect_true "(dr1-pre) a ran and was judged, and c started while b waits" ll_wait_lines "$LL_SIG/d-c.runs" 1 300
expect_eq "(dr1) two runner jobs live at once: b's and c's landings admitted, neither ended" "b.test.sh c.test.sh" "$(ll_live_landings)"
expect_eq "(dr1) …and no third asked while two run (J=2, the gate's answer): b and c started once each, d not at all" "1 1 0" \
  "$(ll_lines "$LL_SIG/d-b.runs") $(ll_lines "$LL_SIG/d-c.runs") $(ll_lines "$LL_SIG/d-d.runs")"
touch "$LL_SIG/d-b.go" "$LL_SIG/d-c.go" "$LL_SIG/d-d.go"
ll_wait_file "$WORLD_ROOT/d.out.rc" 600 || ll_kill_bg "$DR_BG"
KDR="$(ll_last_cand "$RDR" T1)"
expect_nonempty "(dr2-pre) a candidate was built" "$KDR"
expect_eq "(dr2) the row lands: exit 0, the branch at its candidate" "0 $KDR" "$(cat "$WORLD_ROOT/d.out.rc" 2>/dev/null) $(ll_head "$RDR")"
expect_eq "(dr2) …four verdicts on the candidate, in the order named, each with width=2" \
  "a.test.sh:red:2 b.test.sh:green:2 c.test.sh:green:2 d.test.sh:green:2" "$(ll_widths "$RDR" "$KDR")"
expect_eq "(dr2) …and the judge's run at the head writes its verdict with width=2 too" "a.test.sh:red:2" "$(ll_widths "$RDR" "$HDR")"
expect_eq "(dr3) every run of b, c and d started and ended on the candidate" "6 6" \
  "$(cat "$LL_SIG"/d-[bcd].runs 2>/dev/null | awk 'END { print NR }') $(cat "$LL_SIG"/d-[bcd].runs 2>/dev/null | awk -v k="$KDR" '$2 == k { n++ } END { print n + 0 }')"
DR_LT="$(awk 'NR == 1 { print $3 }' "$LL_SIG/d-b.runs" 2>/dev/null)"
expect_eq "(dr3) …all in one landing tree" "6" "$(cat "$LL_SIG"/d-[bcd].runs 2>/dev/null | awk -v t="$DR_LT" '$3 == t { n++ } END { print n + 0 }')"
expect_eq "(dr4) the spy saw the candidate built in that tree (its base pointed once)" "1" \
  "$(awk -v t="$DR_LT" -v h="$HDR" '$1 == t && $2 == h { n++ } END { print n + 0 }' "$LL_SIG/d.points" 2>/dev/null)"
expect_eq "(dr4) …and that tree pointed at the candidate exactly once" "1" \
  "$(awk -v t="$DR_LT" -v k="$KDR" '$1 == t && $2 == k { n++ } END { print n + 0 }' "$LL_SIG/d.points" 2>/dev/null)"
expect_eq "(dr4) …never at the head after it was built" "0" \
  "$(awk -v t="$DR_LT" -v h="$HDR" '$1 == t { if (b) { if ($2 == h) n++ } else if ($2 == h) b = 1 } END { print n + 0 }' "$LL_SIG/d.points" 2>/dev/null)"
expect_eq "(dr5) a ran twice: on the candidate in that tree, then at the head in another (tree n+1)" "$KDR yes|$HDR no" \
  "$(awk -v t="$DR_LT" 'NR <= 2 { printf "%s%s %s", (NR > 1 ? "|" : ""), $2, ($3 == t ? "yes" : "no") }' "$LL_SIG/d-a.runs" 2>/dev/null)"
# MUTANT: the judge re-points the candidate's tree at the head mid-drain (the hazard the drain retires).
# b is still running in it, and c starts in it after: both run on the head while their verdicts name
# the candidate.
RDM="$(ll_drain_world dm)"; HDM="$(ll_head "$RDM")"
anchor fn payload/scripts/lib/line.sh 'landing_tree_point "$jt" "$head"' _line_red_owner 'landing_tree_point "$_LINE_LT" "$head"'
LL_MUTANT="$ANCHOR_SED" LL_MUTANT_FN=_line_red_owner ll_drive "$RDM" T1 "$WORLD_ROOT/dm.out"; DM_BG=$!
ll_wait_lines "$LL_SIG/dm-c.runs" 1 300
touch "$LL_SIG/dm-b.go" "$LL_SIG/dm-c.go" "$LL_SIG/dm-d.go"
ll_wait_file "$WORLD_ROOT/dm.out.rc" 600 || ll_kill_bg "$DM_BG"
KDM="$(ll_last_cand "$RDM" T1)"
expect_eq "(dr6m-pre) the mutant ran: a was judged at the head" "$HDM" "$(awk 'NR == 2 { print $2 }' "$LL_SIG/dm-a.runs" 2>/dev/null)"
expect_true "(dr6m) MUTANT the candidate's tree re-pointed mid-drain: a sibling ran on the head, its verdict on the candidate (the rows can fail)" \
  test "$(cat "$LL_SIG"/dm-[bcd].runs 2>/dev/null | awk -v h="$HDM" '$2 == h { n++ } END { print n + 0 }')" -ge 1
world_machine 8 8192 40 0.5

# ---------------------------------------------------------------------------
section "§GRAMMAR: a verdict's admitted= and width= go after log=, and every reader reads them by key (wave-37 T1; D3, AC-3.2; wave-38 T6, AC-6.4; ownership row 'the landing record grammar')"
#
# `line/v1|ev=verdict|row=<row>|commit=<candidate>|suite=<suite>|result=<result>|log=<log>|admitted=<epoch|->|width=<J>|promised=<s|->|actual=<s|->|at=<UTC>`.
# admitted= is the gate's admission instant for the run the verdict judges, `-` when no admission is on
# record for it (wave-38 T6; AC-6.4).
# Every reader (`_line_proved`, `_line_red_log`, `_line_none_logs`, `_line_head_verdict`, `_line_declared`,
# `_line_fold` and the landing report) reads a field by its key, so a field's place is the writer's own.
# One writer, `_line_verdict_put`, writes every verdict line a landing writes.
RGR="$(ll_world)"; PGR="$(ll_plan "$RGR")"; RECGR="$(ll_rec "$RGR")"; KGR="$(ll_head "$RGR")"
# The ready names the row's own commit: a commit the head already holds would be counted published by git.
line_event "$PGR" ready row=T1 name=wx-T1 "commit=$(git -C "$RGR/.worktrees/T1" rev-parse HEAD)" branch=wt/T1 tree=/t "suites=a.test.sh,b.test.sh,c.test.sh" \
  debt=b.test.sh "carrier=$(ll_carrier)" >/dev/null
ll_grammar_put() {  # <plan> — three verdicts by the writer, J=2; a and b admitted at 1000, c with no admission given
  LINE_WIDTH=2 _line_verdict_put "$1" T1 "$KGR" a.test.sh green /logs/a.log 1000 \
    && LINE_WIDTH=2 _line_verdict_put "$1" T1 "$KGR" b.test.sh red /logs/b.log 1000 300 280 \
    && LINE_WIDTH=2 _line_verdict_put "$1" T1 "$KGR" c.test.sh none /logs/c.log
}
ll_grammar_read() {  # <record> -> every positional reader's answer, one line
  printf '%s|%s|%s|%s|%s' "$(_line_proved "$1" a.test.sh "$KGR" >/dev/null && echo proved)" "$(_line_red_log "$1" T1 "$KGR" b.test.sh)" \
    "$(_line_none_logs "$1" T1 "$KGR" c.test.sh)" "$(_line_head_verdict "$1" "$KGR" b.test.sh | tr '\t' ' ')" "$(_line_declared "$1" T1 "$KGR")"
}
ll_grammar_put "$PGR"
expect_regex "(g1) the writer puts admitted=, width=, then promised= and actual= after log=, and at= last (wave-39 T8; AC-4.2)" \
  "^line/v1\\|ev=verdict\\|row=T1\\|commit=${KGR}\\|suite=b\\.test\\.sh\\|result=red\\|log=/logs/b\\.log\\|admitted=1000\\|width=2\\|promised=300\\|actual=280\\|at=[0-9T:-]+Z$" \
  "$(ll_ev "$RGR" verdict)"
expect_regex "(g1b) …and a verdict given no admission carries admitted=-, promised=- and actual=-" \
  "^line/v1\\|ev=verdict\\|row=T1\\|commit=${KGR}\\|suite=c\\.test\\.sh\\|result=none\\|log=/logs/c\\.log\\|admitted=-\\|width=2\\|promised=-\\|actual=-\\|at=[0-9T:-]+Z$" \
  "$(ll_ev "$RGR" verdict)"
expect_eq "(g2) every reader reads it: green proved, the red's log, the none's log, the head's verdict, the declared debt" \
  "proved|/logs/b.log|/logs/c.log|red /logs/b.log|b.test.sh" "$(ll_grammar_read "$RECGR")"
line_event "$PGR" candidate row=T1 "base=$KGR" "commit=$KGR" tree=/t >/dev/null
LINE_WIDTH=2 _line_verdict_put "$PGR" T1 "$KGR" c.test.sh green /logs/c-2.log 1000
expect_eq "(g3) the fold reads them by key: a and c green, b the declared debt's red, so the entry is declared" "T1 declared" \
  "$(line_state "$PGR" | awk -F'\t' '$1 == "T1" { print $1, $7 }')"
# The fields placed before log= (a mutated writer): the readers, reading by key, answer as before.
RGM="$(ll_world)"; PGM="$(ll_plan "$RGM")"
line_event "$PGM" ready row=T1 name=wx-T1 "commit=$(git -C "$RGM/.worktrees/T1" rev-parse HEAD)" branch=wt/T1 tree=/t "suites=a.test.sh,b.test.sh,c.test.sh" \
  debt=b.test.sh "carrier=$(ll_carrier)" >/dev/null
anchor fn payload/scripts/lib/line.sh '"log=$6" "admitted=${7:--}" "width=${LINE_WIDTH:--}"' _line_verdict_put '"admitted=${7:--}" "width=${LINE_WIDTH:--}" "log=$6"'
GM_READ="$( eval "$(declare -f _line_verdict_put | sed "$ANCHOR_SED")"; ll_grammar_put "$PGM"; ll_grammar_read "$(ll_rec "$RGM")" )"
expect_contains "(g4m-pre) the mutated writer put admitted= and width= before log=" "|result=red|admitted=1000|width=2|log=/logs/b.log|" "$(ll_ev "$RGM" verdict)"
expect_eq "(g4m) …and every reader answers as it did: they read by key, not by place" \
  "proved|/logs/b.log|/logs/c.log|red /logs/b.log|b.test.sh" "$GM_READ"


# ============================================================================ the drain asks the gate (wave-38 T6)
#
# D21 (design-ledger Δ15, ADR-060): before each pass the drain asks the gate how many runners it may start
# now (gate.sh `gate_width_ask <landing key>`) and starts exactly that many, asking again as each one ends;
# no landing runner waits in the gate's queue. Each world here has a gate store of its own, so no landing
# of an earlier section is older than the one under test.
ll_ask_world() {  # <tag> <name>... -> root; T1 lands on the named suites: each writes start, waits for its go file (30 s at most), writes end, green
  local r t="$1" s
  shift
  r="$(ll_world)" || return 1
  ll_launch "$r" T1 "$*"
  for s in "$@"; do printf '#!/bin/bash\n%s' "$(ll_drain_body "$t" "$s")" > "$r/tests/$s.test.sh"; done
  git -C "$r" add tests && git -C "$r" commit -qm "the branch's suites" || return 1
  printf 'T1 adds this\n' > "$r/.worktrees/T1/ask.txt"
  git -C "$r/.worktrees/T1" add ask.txt && git -C "$r/.worktrees/T1" commit -qm "T1: a file of its own" || return 1
  printf '%s' "$r"
}
ll_reqs() {  # -> `<filed> <admitted, not ended> <waiting>`: the landing requests in the gate's store
  local f n=0 a=0 w=0
  for f in "$BIONIC_GATE_DIR"/requests/*; do
    [ -f "$f" ] && grep -q '^kind=landing$' "$f" || continue
    n=$((n + 1))
    if grep -q '^ended=' "$f"; then :; elif grep -q '^admitted=' "$f"; then a=$((a + 1)); else w=$((w + 1)); fi
  done
  printf '%s %s %s' "$n" "$a" "$w"
}
ll_req_tags() {  # -> `<requests naming a landing that ends :T1> <distinct promise cores>`
  local f
  for f in "$BIONIC_GATE_DIR"/requests/*; do
    [ -f "$f" ] && grep -q '^kind=landing$' "$f" || continue
    printf '%s %s\n' "$(sed -n 's/^landing=.*:\(T1\)$/\1/p' "$f")" "$(sed -n 's/^promise=[^:]*:\([^:]*\):.*/\1/p' "$f")"
  done | awk '$1 == "T1" { n++ } $2 != "" { c[$2] = 1 } END { for (k in c) s = s (s == "" ? "" : ",") k; print n + 0, s }'
}
ll_started() { cat "$LL_SIG/$1"-*.runs 2>/dev/null | awk '$1 == "start" { n++ } END { print n + 0 }'; }   # <tag> -> runs started
ll_has_started() { [ "$(ll_started "$1")" -ge "$2" ]; }   # <tag> <n>
ll_wait_started() { wait_ticks 300 0.1 ll_has_started "$@"; }   # <tag> <n> -> 0 once at least <n> runs of <tag> have started (30 s at most)
ll_filed_over() { local r; r="$(ll_reqs)"; [ "${r%% *}" -gt "$1" ]; }   # <n> -> 0 once more than <n> landing requests are filed
ll_req_admitted() {  # <suite> -> the gate's admitted= on that suite's landing request(s), space-separated, in id order
  local f
  for f in $(ls "$BIONIC_GATE_DIR/requests" 2>/dev/null | sort -n); do
    grep -q "^key=$1\$" "$BIONIC_GATE_DIR/requests/$f" && sed -n 's/^admitted=//p' "$BIONIC_GATE_DIR/requests/$f"
  done | tr '\n' ' ' | sed 's/ $//'
}
ll_admitted() {  # <root> <commit> -> `suite:admitted` of each verdict on <commit>, in record order
  ll_ev "$1" verdict | grep -F "|commit=$2|" | while IFS= read -r v; do
    printf '%s:%s ' "$(ll_field "$v" suite)" "$(ll_field "$v" admitted)"
  done | sed 's/ $//'
}
LL_GATE_WAS="$BIONIC_GATE_DIR"

# ---------------------------------------------------------------------------
section "§ASK: the drain asks the gate before each pass and starts exactly its answer, asking again as each run ends (wave-38 T6; D21, REQ-6 AC-6.1; ADR-060)"
#
# The planted machine of T5's worked table (record/wave-38-one-stop/T5-gate.md): 8 cores at share 92, room
# 7.36 cores, each run promised resources.sh's measured suite cost. At load 2 the sums are 3.61 3.61 4.83
# 6.44, and 8.05 refuses a fifth: the answer is 4. At load 6, 7.61 > 7.36 refuses even one, so the oldest
# landing with nothing open is answered 1 (the floor), and 0 while its own run is open.
printf '92\n' > "$CLAUDE_CONFIG_DIR/bionic/share"
world_machine 8 8192 30 2.0
export BIONIC_GATE_DIR="$WORLD_ROOT/gate-k"
expect_eq "(k0) the promise read is the measured suite cost: 1.61 cores a run" "1.61" "$(_res_suite_cores)"
expect_eq "(k0) …and at load 2 the gate answers a landing with nothing open 4" "4" "$(ll_width_ask k-probe)"
RK="$(ll_ask_world k p1 p2 p3 p4 p5 p6)"
ll_verb_bg "$RK" T1 "$WORLD_ROOT/k.out"; K_BG=$!
expect_true "(k1-pre) four runs started" ll_wait_started k 4
expect_false "(k1) no fifth ask is filed in the 2 s after" wait_for 2 ll_filed_over 4
expect_eq "(k1) the drain started exactly the answer: four landing requests, four admitted, none waiting in the gate's queue" "4 4 0" "$(ll_reqs)"
expect_eq "(k1) …four suites running, p5 and p6 not started" "4 0 0" "$(ll_started k) $(ll_lines "$LL_SIG/k-p5.runs") $(ll_lines "$LL_SIG/k-p6.runs")"
expect_eq "(k1) …each request names the row's landing and is promised the measured cost" "4 $(_res_suite_cores)" "$(ll_req_tags)"
K_KEY="$(ll_open_landing)"
expect_eq "(k1) …and the gate answers the landing 0 more while its four run" "0" "$(ll_width_ask "$K_KEY")"
world_tick 50
touch "$LL_SIG/k-p1.go"
expect_true "(k2-pre) a fifth run started once p1 ended" ll_wait_started k 5
expect_false "(k2) no sixth ask is filed in the 2 s after" wait_for 2 ll_filed_over 5
expect_eq "(k2) asked again as p1 ended, the gate answered 1 and the drain started one: five filed, four admitted, none waiting" "5 4 0" "$(ll_reqs)"
expect_eq "(k2) …p5 started, p6 not" "1 0" "$(ll_lines "$LL_SIG/k-p5.runs") $(ll_lines "$LL_SIG/k-p6.runs")"
touch "$LL_SIG/k-p2.go" "$LL_SIG/k-p3.go" "$LL_SIG/k-p4.go" "$LL_SIG/k-p5.go" "$LL_SIG/k-p6.go"
ll_wait_file "$WORLD_ROOT/k.out.rc" 600 || ll_kill_bg "$K_BG"
KK="$(ll_last_cand "$RK" T1)"
expect_eq "(k3) the row lands: exit 0, the branch at its candidate" "0 $KK" "$(cat "$WORLD_ROOT/k.out.rc" 2>/dev/null) $(ll_head "$RK")"
expect_eq "(k3) …six verdicts, each width=4: the width the gate gave the landing" \
  "p1.test.sh:green:4 p2.test.sh:green:4 p3.test.sh:green:4 p4.test.sh:green:4 p5.test.sh:green:4 p6.test.sh:green:4" "$(ll_widths "$RK" "$KK")"
expect_eq "(k3) …and six landing requests in all, one per run: the drain never filed an ask past the answer" "6 0 0" "$(ll_reqs)"
world_machine 8 8192 30 6.0
export BIONIC_GATE_DIR="$WORLD_ROOT/gate-k6"
expect_eq "(k4-pre) at load 6 the gate answers a landing with nothing open 1 (0 by the rule, 1 by the floor)" "1" "$(ll_width_ask k6-probe)"
RK6="$(ll_ask_world k6 q1 q2)"
ll_verb_bg "$RK6" T1 "$WORLD_ROOT/k6.out"; K6_BG=$!
expect_true "(k4-pre) one run started" ll_wait_started k6 1
expect_false "(k4) no second ask is filed in the 2 s after" wait_for 2 ll_filed_over 1
expect_eq "(k4) at load 6 the drain started one: one request, admitted, none waiting; q2 not started" "1 1 0 0" "$(ll_reqs) $(ll_lines "$LL_SIG/k6-q2.runs")"
expect_eq "(k4) …the gate answers the landing 0 while its run is open" "0" "$(ll_width_ask "$(ll_open_landing)")"
touch "$LL_SIG/k6-q1.go"
expect_true "(k5-pre) q2 started once q1 ended" ll_wait_started k6 2
touch "$LL_SIG/k6-q2.go"
ll_wait_file "$WORLD_ROOT/k6.out.rc" 600 || ll_kill_bg "$K6_BG"
expect_eq "(k5) the row lands, one run at a time: two requests, none waiting, each verdict width=1" "0 2 0 0 q1.test.sh:green:1 q2.test.sh:green:1" \
  "$(cat "$WORLD_ROOT/k6.out.rc" 2>/dev/null) $(ll_reqs) $(ll_widths "$RK6" "$(ll_last_cand "$RK6" T1)")"
# MUTANT: the drain sizes itself (an answer it never asked the gate for): it files more asks than the gate
# admits, and the rest wait in the gate's queue, the harm D21 retires.
world_machine 8 8192 30 2.0
export BIONIC_GATE_DIR="$WORLD_ROOT/gate-km"
RKM="$(ll_ask_world km m1 m2 m3 m4 m5 m6)"
anchor fn payload/scripts/lib/line.sh 'gate_width_ask "$1"' _line_width_ask 'echo 9'
LL_MUTANT="$ANCHOR_SED" LL_MUTANT_FN=_line_width_ask ll_drive "$RKM" T1 "$WORLD_ROOT/km.out"; KM_BG=$!
ll_wait_started km 4
wait_for 5 ll_filed_over 4
KM_REQS="$(ll_reqs)"
expect_eq "(k6m-pre) the mutant ran: the gate admitted four, as on the shipped drain" "4" "$(ll_started km)"
expect_true "(k6m) MUTANT the drain sizes itself: more asks filed than the gate's answer, the rest waiting in its queue (the rows can fail; got $KM_REQS)" \
  test "${KM_REQS%% *}" -gt 4
touch "$LL_SIG"/km-m1.go "$LL_SIG"/km-m2.go "$LL_SIG"/km-m3.go "$LL_SIG"/km-m4.go "$LL_SIG"/km-m5.go "$LL_SIG"/km-m6.go
ll_wait_file "$WORLD_ROOT/km.out.rc" 600 || ll_kill_bg "$KM_BG"

# ---------------------------------------------------------------------------
section "§ADMITTED: every verdict line carries admitted=<epoch> after log=, the gate's admission instant for its run (wave-38 T6; REQ-6 AC-6.4)"
#
# From §ASK's landing: p1 to p4 were admitted at one instant, the clock then moved 50 s, and p1's verdict
# was written after that; p5 was admitted after it. The epoch on each verdict is its run's admission,
# read from the gate, never the time the verdict was written.
export BIONIC_GATE_DIR="$WORLD_ROOT/gate-k"
K_T0="$(ll_req_admitted p1.test.sh)"
expect_true "(ad0-pre) the gate recorded p1's admission instant" test -n "$K_T0"
expect_eq "(ad2) …p1 to p4 carry the instant before the clock moved, p5 the one after" \
  "p1.test.sh:${K_T0} p2.test.sh:${K_T0} p3.test.sh:${K_T0} p4.test.sh:${K_T0} p5.test.sh:$((K_T0 + 50))" \
  "$(ll_admitted "$RK" "$KK" | cut -d' ' -f1-5)"
expect_eq "(ad3) …each the gate's own admitted= for that run" \
  "$(for s in p1 p2 p3 p4 p5 p6; do printf '%s.test.sh:%s ' "$s" "$(ll_req_admitted "$s.test.sh")"; done | sed 's/ $//')" "$(ll_admitted "$RK" "$KK")"
export BIONIC_GATE_DIR="$LL_GATE_WAS"
printf '80\n' > "$CLAUDE_CONFIG_DIR/bionic/share"
world_machine 8 8192 40 0.5

# ---------------------------------------------------------------------------
section "§STALL: a bounded ready keeps its none count across ev=ready, so the stall fires (wave-38 T6; REQ-6 AC-6.3)"
#
# A suite that ends with no verdict once per call: its recorded 600 s fits a 900 s bound once, and each run
# moves the planted clock 400 s, so the pass after a none finds 500 s left and says WAITING. The count is
# of `none` verdicts since the entry was published, returned or stalled, never since its latest `ready`:
# the third bounded ready stalls the entry. (A ready after STALLED is the asked-for retry, §STALLED t5.)
ll_stall_world() {  # <tag> -> root; T1 lands on c, which moves the clock 400 s, records its run and ends with no end line
  local r
  r="$(ll_world)" || return 1
  ll_launch "$r" T1 c
  ( cd "$r" && world_cost c.test.sh 600 ) || return 1
  cat > "$r/tests/c.test.sh" <<SUITE
#!/bin/bash
n=\$(awk 'NR == 1 { print \$1; exit }' "$WORLD_ROOT/clock")
printf '%s\n' "\$((n + 400))" > "$WORLD_ROOT/clock.t" && mv "$WORLD_ROOT/clock.t" "$WORLD_ROOT/clock"
echo run >> "\$LL_SIG/$1.runs"
echo "PASS: a run that ends with no end line"
exit 0
SUITE
  git -C "$r" add tests/c.test.sh && git -C "$r" commit -qm "suite c: no end line, 400 s a run" || return 1
  printf '%s' "$r"
}
export BIONIC_GATE_DIR="$WORLD_ROOT/gate-st"
RS="$(ll_stall_world st)"
ll_verb "$RS" T1 --within 500; ST1="$LL_RC"
ll_verb "$RS" T1 --within 900; ST2="$LL_RC"
ll_verb "$RS" T1 --within 900; ST3="$LL_RC"; ST3_OUT="$LL_OUT"
KS="$(ll_last_cand "$RS" T1)"
LS1="$RS/.bionic/docs/record/wave-x/line/T1-c-${KS:0:12}.log"; LS2="$RS/.bionic/docs/record/wave-x/line/T1-c-${KS:0:12}-2.log"
expect_eq "(st1) three bounded readies with no progress: WAITING, WAITING, then STALLED on the third" "75 75 70" "$ST1 $ST2 $ST3"
expect_eq "(st1) …the first started nothing (600 s promised, 500 left); the second and third ran once each, both none" "2 none none" \
  "$(ll_lines "$LL_SIG/st.runs") $(ll_results "$RS" T1 "$KS")"
expect_eq "(st1) …the stall names the two runs' logs, one from each call" "STALLED T1 ${LS1},${LS2}" "$(printf '%s\n' "$ST3_OUT" | grep '^STALLED ')"
# MUTANT: the count reset at every ready, as before. Each call starts from nothing, and the stall never fires.
export BIONIC_GATE_DIR="$WORLD_ROOT/gate-stm"
RSM="$(ll_stall_world stm)"
anchor fn payload/scripts/lib/line.sh 'e == "stalled"' _line_none_logs 'e == "ready"'
STM=""
for w in 500 900 900; do
  rm -f "$WORLD_ROOT/stm.out.rc"
  LL_MUTANT="$ANCHOR_SED" LL_MUTANT_FN=_line_none_logs ll_drive "$RSM" T1 "$WORLD_ROOT/stm.out" "$w"; STM_BG=$!
  ll_wait_file "$WORLD_ROOT/stm.out.rc" 300 || ll_kill_bg "$STM_BG"
  STM="$STM$(cat "$WORLD_ROOT/stm.out.rc" 2>/dev/null) "
done
expect_eq "(st2m-pre) the mutant ran: two runs, both none" "2 none none" "$(ll_lines "$LL_SIG/stm.runs") $(ll_results "$RSM" T1 "$(ll_last_cand "$RSM" T1)")"
expect_eq "(st2m) MUTANT the count reset at every ready: three bounded readies, never a stall (the rows can fail)" "75 75 75 |" \
  "$STM|$(ll_ev "$RSM" stalled)"
export BIONIC_GATE_DIR="$LL_GATE_WAS"

# ---------------------------------------------------------------------------
section "§GAP: the oldest landing keeps the gate across its run gaps and its re-entries; ready opens, keeps and closes its lease (wave-38 T30; D22; A-T6-10)"
#
# An older landing is planted as a lease whose carrier lives and which holds no request: the gap
# between its runs, as the gate sees it. T1's ready is answered 0 while that lease is open, starts no
# run, and returns WAITING when its time is up. Its own lease is then kept, nobody's, at its first-ask
# instant, and the next ready takes it over at that instant. Once the older lease closes, T1 is
# answered, proves and publishes, and its lease is closed. Before T30 the gate read a landing as active
# only while it held an open request, so T1 ran in the older one's gap (A-T6-10).
export BIONIC_GATE_DIR="$WORLD_ROOT/gate-gap"
GP_OLD="older:wave-y:T9"
GP_CAR="$(ll_carrier)"
RG="$(ll_rworld)"; ll_commit_suite "$RG" T1 a "$(ll_block_body g-T1 a green)"
GP_KEY="$(_line_landing_key "$RG" "$(ll_plan "$RG")" T1)"
expect_eq "(g0-pre) the older landing's lease is opened, carried by a live process, with no request in the store" "0 yes 0" \
  "$(ll_lease_gate gate_landing_open "$GP_OLD" "$GP_CAR" 3600) $(ll_lease_carried "$GP_OLD" && echo yes) $(ls "$BIONIC_GATE_DIR/requests" 2>/dev/null | grep -c '^[0-9]')"
ll_verb_bg "$RG" T1 "$WORLD_ROOT/g1.out" --within 30; G1_BG=$!
expect_true "(g1-pre) T1's ready opened its own lease, carried" wait_for 20 ll_lease_carried "$GP_KEY"
expect_false "(g1) no run of T1 starts in the 2 s while the older lease is open, though it holds no request" wait_for 2 ll_has_lines "$LL_SIG/g-T1.runs" 1
expect_eq "(g1) …the gate answers T1 0" "0" "$(ll_width_ask "$GP_KEY")"
GP_FIRST="$(ll_lease_field "$GP_KEY" first)"
expect_regex "(g1) …T1's lease holds its first-ask instant" '^[0-9]+$' "$GP_FIRST"
world_tick 60
ll_wait_file "$WORLD_ROOT/g1.out.rc" 300 || ll_kill_bg "$G1_BG"
expect_eq "(g2) T1's ready returns WAITING once its time is up, having run nothing" "75 0" \
  "$(cat "$WORLD_ROOT/g1.out.rc" 2>/dev/null) $(ll_lines "$LL_SIG/g-T1.runs")"
expect_eq "(g2) …its lease kept, nobody's (carrier -), at the same first-ask instant" "-|$GP_FIRST" \
  "$(ll_lease_field "$GP_KEY" carrier)|$(ll_lease_field "$GP_KEY" first)"
world_tick 5
ll_verb_bg "$RG" T1 "$WORLD_ROOT/g3.out" --within 30; G3_BG=$!
expect_true "(g3-pre) the next ready took T1's lease over: carried again" wait_for 20 ll_lease_carried "$GP_KEY"
expect_eq "(g3) …at the first ready's instant, not this one's" "$GP_FIRST" "$(ll_lease_field "$GP_KEY" first)"
expect_false "(g3) …and T1 is still held: no run in the 2 s while the older lease is open" wait_for 2 ll_has_lines "$LL_SIG/g-T1.runs" 1
world_tick 60
ll_wait_file "$WORLD_ROOT/g3.out.rc" 300 || ll_kill_bg "$G3_BG"
expect_eq "(g3) WAITING again, nothing run" "75 0" "$(cat "$WORLD_ROOT/g3.out.rc" 2>/dev/null) $(ll_lines "$LL_SIG/g-T1.runs")"
expect_eq "(g4-pre) the older landing's carrier closes its lease" "0" "$(ll_lease_gate gate_landing_close "$GP_OLD" "$GP_CAR")"
expect_true "(g4) …and the gate now answers T1 at least 1" test "$(ll_width_ask "$GP_KEY")" -ge 1
ll_verb_bg "$RG" T1 "$WORLD_ROOT/g4.out" --within 300; G4_BG=$!
expect_true "(g4) T1's run starts once the older lease is closed" ll_wait_lines "$LL_SIG/g-T1.runs" 1
touch "$LL_SIG/g-T1.go"
ll_wait_file "$WORLD_ROOT/g4.out.rc" 300 || ll_kill_bg "$G4_BG"
expect_eq "(g5) T1 publishes: exit 0, the branch at its candidate" "0 $(ll_last_cand "$RG" T1)" \
  "$(cat "$WORLD_ROOT/g4.out.rc" 2>/dev/null) $(ll_head "$RG")"
expect_eq "(g5) …and its lease is closed with it" "no" "$(if [ -e "$(ll_lease "$GP_KEY")" ]; then echo yes; else echo no; fi)"
export BIONIC_GATE_DIR="$LL_GATE_WAS"
touch "$LL_SIG/g-T1.go"

# ---------------------------------------------------------------------------
section "§ORDER: the line's order is the gate's: a ready opens its lease and records its entry in one act, and both landings land (wave-38 T30; A-orch-49)"
#
# A landing waits to publish behind the entries ahead of it in the line, and the gate holds every
# landing behind the oldest lease. If the two orders disagree, the gate's oldest waits on the line's
# first while the gate answers that one 0: neither moves (T31 found it in §ALONE). So a ready takes the
# record's ready lock, opens its lease and appends its ready event, which carries the lease's age, in
# one act; a new entry takes a fresh age, and a ready of an entry still open takes the age its entry
# was given. o1: two readies in one planted instant. o2: a lease of T1 kept from an entry already
# closed would make T1 the gate's oldest though its new entry is behind T2's in the line.
ll_order_world() {  # <tag> -> root; T1 lands on a, T2 on b, each a suite that waits for its go file
  local r
  r="$(ll_rworld)" || return 1
  ll_commit_suite "$r" T1 a "$(ll_block_body "$1-T1" a green)"
  ll_commit_suite "$r" T2 b "$(ll_block_body "$1-T2" b green)"
  printf '%s' "$r"
}
ll_line_order() { ll_ev "$1" ready | awk -F'|' '{ r = $3; sub(/^row=/, "", r); if (!(r in s)) { s[r] = 1; o = o (o == "" ? "" : " ") r } } END { print o }'; }   # <root> -> rows in the order their entries opened
ll_lease_order() {  # <root> -> T1 and T2 in the gate's order: by first, then seq
  local p k1 k2
  p="$(ll_plan "$1")"; k1="$(_line_landing_key "$1" "$p" T1)"; k2="$(_line_landing_key "$1" "$p" T2)"
  printf 'T1 %s %s\nT2 %s %s\n' "$(ll_lease_field "$k1" first)" "$(ll_lease_field "$k1" seq)" "$(ll_lease_field "$k2" first)" "$(ll_lease_field "$k2" seq)" \
    | sort -k2,2n -k3,3n | awk 'NF == 3 { o = o (o == "" ? "" : " ") $1 } END { print o }'
}
ll_has_ready() { ll_ev "$1" ready | grep -q "|row=$2|"; }   # <root> <row> -> 0 once the row's ready event is on the record
ll_both_carried() { local p; p="$(ll_plan "$1")"; ll_lease_carried "$(_line_landing_key "$1" "$p" T1)" && ll_lease_carried "$(_line_landing_key "$1" "$p" T2)" && ll_has_ready "$1" T1 && ll_has_ready "$1" T2; }   # <root> -> 0 once both hold a lease and both entries are recorded
export BIONIC_GATE_DIR="$WORLD_ROOT/gate-order"
RO="$(ll_order_world o1)"
ll_verb_bg "$RO" T1 "$WORLD_ROOT/o1-T1.out"; O1A=$!; ll_verb_bg "$RO" T2 "$WORLD_ROOT/o1-T2.out"; O1B=$!
expect_true "(o1-pre) both readies hold their leases and have recorded their entries, in one planted instant" wait_for 20 ll_both_carried "$RO"
expect_true "(o1) …the ready event carries the lease's age" test -n "$(ll_ev "$RO" ready | grep -E '\|age=[0-9]+:[0-9]+\|' | head -1)"
touch "$LL_SIG/o1-T1.go" "$LL_SIG/o1-T2.go"
ll_wait_file "$WORLD_ROOT/o1-T1.out.rc" 450 || ll_kill_bg "$O1A"; ll_wait_file "$WORLD_ROOT/o1-T2.out.rc" 450 || ll_kill_bg "$O1B"
expect_eq "(o1) both land, in the line's order" "0 0 $(ll_line_order "$RO")" \
  "$(cat "$WORLD_ROOT/o1-T1.out.rc" 2>/dev/null) $(cat "$WORLD_ROOT/o1-T2.out.rc" 2>/dev/null) $(ll_ev "$RO" published | sed 's/.*|row=\([^|]*\)|.*/\1/' | tr '\n' ' ' | sed 's/ $//')"
export BIONIC_GATE_DIR="$WORLD_ROOT/gate-order2"
RO2="$(ll_order_world o2)"
O2_K1="$(_line_landing_key "$RO2" "$(ll_plan "$RO2")" T1)"
O2_CAR="$(ll_carrier)"
expect_eq "(o2-pre) a lease of T1 is kept from an entry already closed: opened, then left, nobody's" "0 0 -" \
  "$(ll_lease_gate gate_landing_open "$O2_K1" "$O2_CAR" 3600) $(ll_lease_gate gate_landing_leave "$O2_K1" "$O2_CAR") $(ll_lease_field "$O2_K1" carrier)"
O2_OLD="$(ll_lease_field "$O2_K1" first):$(ll_lease_field "$O2_K1" seq)"
world_tick 5
ll_verb_bg "$RO2" T2 "$WORLD_ROOT/o2-T2.out"; O2B=$!
expect_true "(o2-pre) T2's ready opened the line and holds its lease" wait_for 20 ll_has_ready "$RO2" T2
world_tick 5
ll_verb_bg "$RO2" T1 "$WORLD_ROOT/o2-T1.out"; O2A=$!
expect_true "(o2-pre) T1's ready holds a lease and has recorded its entry" wait_for 20 ll_has_ready "$RO2" T1
expect_eq "(o2) T1's new entry is behind T2's in the line, and so is its lease: a fresh age, not the kept $O2_OLD" "T2 T1|T2 T1" \
  "$(ll_line_order "$RO2")|$(ll_lease_order "$RO2")"
touch "$LL_SIG/o2-T1.go" "$LL_SIG/o2-T2.go"
ll_wait_file "$WORLD_ROOT/o2-T2.out.rc" 450 || ll_kill_bg "$O2B"; ll_wait_file "$WORLD_ROOT/o2-T1.out.rc" 450 || ll_kill_bg "$O2A"
expect_eq "(o2) both land, T2 then T1" "0 0 T2 T1" \
  "$(cat "$WORLD_ROOT/o2-T2.out.rc" 2>/dev/null) $(cat "$WORLD_ROOT/o2-T1.out.rc" 2>/dev/null) $(ll_ev "$RO2" published | sed 's/.*|row=\([^|]*\)|.*/\1/' | tr '\n' ' ' | sed 's/ $//')"

# ---------------------------------------------------------------------------
section "§LINT: a comment that cites the run is refused at its line; a tracked docs path, a test's fixture row ids and a .bionic/tmp path are accepted"
#
# The landing line reads the comments a candidate adds to a shell file under payload/ or tests/ and refuses one that
# names a wave or a record path, printing the file, the line and the shapes. A tracked docs path, a fixture's row ids
# in a test and a path under .bionic/tmp name no shape.
# fails-when: a planted citation is not named by its file and line, or one of the three accepted comments is named.
LN_REPO="$WORLD_ROOT/lint-repo"
mkdir -p "$LN_REPO/payload/scripts" "$LN_REPO/tests"
git -C "$LN_REPO" init -q && git -C "$LN_REPO" config user.name lint && git -C "$LN_REPO" config user.email lint@example.invalid
printf '%s\n' '#!/bin/bash' 'echo one' > "$LN_REPO/payload/scripts/a.sh"; printf '%s\n' '#!/bin/bash' 'echo t' > "$LN_REPO/tests/t.test.sh"
git -C "$LN_REPO" add -A && git -C "$LN_REPO" commit -qm base
LN_BASE="$(git -C "$LN_REPO" rev-parse HEAD)"
printf '%s\n' '# reads .bionic/docs/record/x.md' '# started in wave-39 T5' >> "$LN_REPO/payload/scripts/a.sh"; printf '%s\n' '# from wave-39' >> "$LN_REPO/tests/t.test.sh"
git -C "$LN_REPO" add -A && git -C "$LN_REPO" commit -qm cited
LN_CITED="$(git -C "$LN_REPO" rev-parse HEAD)"
LN_OUT="$(_line_comment_lint "$LN_REPO" "$LN_BASE" "$LN_CITED")"; LN_RC=$?
expect_eq "(ln1) a comment citing a record path, and one naming a wave in a script and in a test, are refused at their lines: rc 1, each named" \
  "1|payload/scripts/a.sh:3 record-path|payload/scripts/a.sh:4 wave|tests/t.test.sh:3 wave" "$LN_RC|$(printf '%s\n' "$LN_OUT" | paste -sd'|' -)"
printf '%s\n' '# see docs/adrs/adr-001.md' '# scratch goes under .bionic/tmp/scratch' >> "$LN_REPO/payload/scripts/a.sh"; printf '%s\n' '# T12 waits on T2' >> "$LN_REPO/tests/t.test.sh"
git -C "$LN_REPO" add -A && git -C "$LN_REPO" commit -qm tracked
LN_OUT="$(_line_comment_lint "$LN_REPO" "$LN_CITED" "$(git -C "$LN_REPO" rev-parse HEAD)")"; LN_RC=$?
expect_eq "(ln2) AC-16.2 a tracked docs path and a .bionic/tmp path in a script, and a test's T12 waits on T2, are accepted: rc 0, nothing named" "0|" "$LN_RC|$LN_OUT"

# ---------------------------------------------------------------------------
finish
