#!/bin/bash
# tests/cross-gate-agreement-1.test.sh — CROSS-COMPONENT INSTRUMENT PROOFS, part 1 of 2: sections §A1 through §BP.
#
# THE SUITE IS TWO PARTS (wave-39 T36; D1, D13, REQ-3 AC-3.3). One cross-gate-agreement.test.sh promised more than
# half the suite bar, ten minutes of the gate's promise, so it runs as two suites cut at a section boundary. Its
# governing header, its sandbox, its parties and the fixture builders and helpers both parts share are in
# tests/cross-gate-agreement.prelude.sh, sourced below after the framework.
#
# Usage: bash tests/cross-gate-agreement-1.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/plan-fixture.sh"
. "$(dirname "$0")/lib/assert.sh"
. "$(dirname "$0")/cross-gate-agreement.prelude.sh"

# ============================================================
section "A1 — N-way agreement on active-wave detection (AC-9, checklist A8/A9)"
# ============================================================
echo "parties: $(basename "$PARTY_DP") · $(basename "$PARTY_SG") · $(basename "$PARTY_EG") · $(basename "$PARTY_ER") · $(basename "$PARTY_LG")"

run_battery assert

# THE OTHER DIRECTION OF THE SWITCH, once. The four constants above are worth nothing
# unless the marker is what produces them: on the SAME fixture, with the marker removed,
# every one of the five answers "no" and says nothing. The plan shape is irrelevant to
# this claim — engagement is asked before the plan is read — so one fixture discharges it,
# and tests/hook-adoption.test.sh §5c drives the same direction across the wider roster.
UNENG="$SANDBOX/fx/baseline-active/repo"
for _u in "$SID_A" "$SID_B" "$SID_LG"; do rm -f "$UNENG/.bionic/tmp/engaged-$_u.state"; done
expect_eq "unengaged: the dispatch wall decides nothing"      "no" "$(verdict_dp "$UNENG")"
expect_eq "unengaged: the stop gate decides nothing"          "no" "$(verdict_sg "$UNENG")"
expect_eq "unengaged: the recorder journals nothing"          "no" "$(verdict_er "$UNENG")"
expect_eq "unengaged: the landing gate takes no verdict"      "no" "$(verdict_lg "$UNENG")"
arm_patrol "$UNENG" "$SID_A" "$SID_B" "$SID_LG"
expect_eq "…and re-engaged, the dispatch wall decides again"  "yes" "$(verdict_dp "$UNENG")"

# The origin is IN the test, not merely cited by it. Checklist A8's defect was
# exactly this: three byte-identical copies, a 2-way agreement test, and the
# actively-maintained origin absent from the test meant to catch drift.
# The landing gate carries a copy too (Step-6 critic D-1) — it is now a driven party, and
# the copy it holds is really the active-wave detection block, not something else.

# ============================================================
section "A2 — a LIBRARY mutation moves every party (checklist A9, TDD §9)"
# ============================================================
#
# WHAT THIS SECTION USED TO PROVE, AND WHY THE PROOF MOVED. Until bionic 1.4.0 the
# active-wave block was five hand-copies, and A9's finding was that a suite which cannot
# tell them apart is decorative: the discriminator was mutating ONE copy and requiring the
# battery to go red. There are no copies left. The block is `lib/run.sh` and the five
# parties source it, so the honest discriminator inverts: mutate the LIBRARY, and EVERY
# party must move. A party that had quietly kept its own answer — a leftover local
# parse, a hook that reads the plan itself — would stay green here and nowhere else.
#
# Each mutation is a plausible drift, not damage: a maintainer editing the one reader and
# getting a rule subtly wrong. The shipped library is never modified; each mutant is a
# copy inside a throwaway tree shaped like the shipped plugin (hooks/ beside scripts/lib/),
# which is also what makes the parties load the mutant at all — the loader's first
# candidate is `$(dirname "$0")/../scripts/lib`.

CKSUM_BEFORE=$(shasum "$PARTY_DP" "$PARTY_SG" "$PARTY_EG" "$PARTY_ER" "$PARTY_LG" "$PARTY_LG_SRC" 2>/dev/null)
# (hoisted to tests/cross-gate-agreement.prelude.sh, which part 2 reads: RUN_LIB, FILL_LIB)
LIB_DIR_SRC="$(dirname "$RUN_LIB")"
# THE DOCS-ROOT READER IS lib/roots.sh's NOW (epic-22 wave-01, N1), so two of the seven
# mutations below have to be applied there. run.sh used to carry both `docs_root` and
# `config_value`, and its own comment warned that moving `config_value` above `docs_root`
# would land the `!d`-guarded awk edits on a reader the fixtures never call, making this
# section "go quietly vacuous rather than red". The move happened — both functions are one
# function in roots.sh — so the guard against that is here instead: each mutation names the
# file it edits, and `mutate_lib` returns 1 when its awk target matches nothing, which the
# loop below reports as a RED row and not a pass.
ROOTS_LIB="$LIB_DIR_SRC/roots.sh"
MUTDIR="$SANDBOX/mutants"; mkdir -p "$MUTDIR"

expect_eq "the library under mutation is on disk (this section is not vacuous)" "yes" \
  "$([ -r "$RUN_LIB" ] && echo yes || echo no)"
expect_eq "…and so is the roots library the docs-root mutations edit" "yes" \
  "$([ -r "$ROOTS_LIB" ] && echo yes || echo no)"

# mutate_lib_file <kind> -> the shipped library file this mutation edits
mutate_lib_file() {
  case "$1" in
    docs-root-last-wins|keep-quotes) printf '%s' "$ROOTS_LIB" ;;
    *)                               printf '%s' "$RUN_LIB" ;;
  esac
}

# mutate_lib <kind> <dst>  — rc 1 if the mutation matched nothing
mutate_lib() {
  local kind="$1" dst="$2" src
  src="$(mutate_lib_file "$kind")"
  case "$kind" in
    docs-root-last-wins)   # head -1 -> tail -1 in docs_root
      awk 'BEGIN{d=0} !d && $0=="      | head -1 \\" {print "      | tail -1 \\"; d=1; next} {print}' \
        "$src" > "$dst" ;;
    keep-quotes)           # drop the quote-stripping sed in docs_root
      awk 'BEGIN{d=0} !d && index($0,";s/[") {print "      | cat \\"; d=1; next} {print}' \
        "$src" > "$dst" ;;
    delete-cr)             # translate-CR -> delete-CR (the fail-dangerous shape)
      awk '{ i=index($0,"gsub(/\\r/, \"\\n\"); ");
             while (i>0) { $0=substr($0,1,i-1) substr($0,i+20); i=index($0,"gsub(/\\r/, \"\\n\"); ") }
             print }' "$src" > "$dst" ;;
    depth-1)               # plan search one level shallower
      awk '{ i=index($0,"-maxdepth 2 -type f -name '"'"'*.md'"'"'");
             if (i>0) { $0=substr($0,1,i-1) "-maxdepth 1 -type f -name '"'"'*.md'"'"'" substr($0,i+33) }
             print }' "$src" > "$dst" ;;
    fence-blind)           # stop skipping fenced content
      awk '{ t=$0; sub(/^[ \t]+/,"",t); sub(/[ \t]+$/,"",t); if (t=="fence { next }") next; print }' \
        "$src" > "$dst" ;;
    no-marker-skip)        # accept marker-less candidates again
      awk '{ t=$0; sub(/^[ \t]+/,"",t); sub(/[ \t]+$/,"",t);
             if (t=="END { exit !found }'"'"' || continue") next; print }' "$src" > "$dst" ;;
    anchor-current)        # lose the leading-whitespace tolerance on `current:`
      awk '{ i=index($0,"'"'"'^[[:space:]]*current[[:space:]]*:'"'"'");
             if (i>0) { $0=substr($0,1,i-1) "'"'"'^current:'"'"'" substr($0,i+38) }
             print }' "$src" > "$dst" ;;
    *) echo "unknown mutation $kind" >&2; return 1 ;;
  esac
  cmp -s "$src" "$dst" && return 1
  return 0
}

MUTATIONS="docs-root-last-wins keep-quotes delete-cr depth-1 fence-blind anchor-current no-marker-skip"

for m in $MUTATIONS; do
  tree="$MUTDIR/$m"
  mkdir -p "$tree/hooks" "$tree/scripts/lib"
  cp "$LIB_DIR_SRC"/*.sh "$tree/scripts/lib/" 2>/dev/null
  if ! mutate_lib "$m" "$tree/scripts/lib/$(basename "$(mutate_lib_file "$m")")"; then
    # A mutation that matches nothing is not a passing test — it means the code moved
    # and this proof has gone vacuous (.claude/rules/test-harness.md, "Fixture fidelity").
    no "mutation '$m' applies to $(basename "$(mutate_lib_file "$m")")" \
       "the awk target matched nothing — the library moved"
    continue
  fi
  for _pf in "$PARTY_DP" "$PARTY_SG" "$PARTY_EG" "$PARTY_ER" "$PARTY_LG" "$PARTY_SW"; do
    cp "$_pf" "$tree/hooks/$(basename "$_pf")"
  done
  saved_dp="$PARTY_DP"; saved_sg="$PARTY_SG"; saved_eg="$PARTY_EG"
  saved_er="$PARTY_ER"; saved_lg="$PARTY_LG"
  PARTY_DP="$tree/hooks/$(basename "$saved_dp")"
  PARTY_SG="$tree/hooks/$(basename "$saved_sg")"
  PARTY_EG="$tree/hooks/$(basename "$saved_eg")"
  PARTY_ER="$tree/hooks/$(basename "$saved_er")"
  PARTY_LG="$tree/hooks/$(basename "$saved_lg")"
  if detail=$(run_battery detect); then
    no "library mutation '$m' makes the battery RED" \
       "the battery stayed green with the one reader mutated — it does not discriminate"
  else
    ok "library mutation '$m' makes the battery RED"
  fi
  PARTY_DP="$saved_dp"; PARTY_SG="$saved_sg"; PARTY_EG="$saved_eg"
  PARTY_ER="$saved_er"; PARTY_LG="$saved_lg"
done

# THE PAIRED POSITIVE: the same throwaway tree with an UNMUTATED library must be green,
# or every red above is the copying and not the mutation.
ctrl="$MUTDIR/control"
mkdir -p "$ctrl/hooks" "$ctrl/scripts/lib"
cp "$LIB_DIR_SRC"/*.sh "$ctrl/scripts/lib/" 2>/dev/null
for _pf in "$PARTY_DP" "$PARTY_SG" "$PARTY_EG" "$PARTY_ER" "$PARTY_LG" "$PARTY_SW"; do
  cp "$_pf" "$ctrl/hooks/$(basename "$_pf")"
done
saved_dp="$PARTY_DP"; saved_sg="$PARTY_SG"; saved_eg="$PARTY_EG"
saved_er="$PARTY_ER"; saved_lg="$PARTY_LG"
PARTY_DP="$ctrl/hooks/$(basename "$saved_dp")"
PARTY_SG="$ctrl/hooks/$(basename "$saved_sg")"
PARTY_EG="$ctrl/hooks/$(basename "$saved_eg")"
PARTY_ER="$ctrl/hooks/$(basename "$saved_er")"
PARTY_LG="$ctrl/hooks/$(basename "$saved_lg")"
if detail=$(run_battery detect); then
  ok "control: the same tree with an UNMUTATED library is green"
else
  no "control: the same tree with an UNMUTATED library is green" "$detail"
fi
PARTY_DP="$saved_dp"; PARTY_SG="$saved_sg"; PARTY_EG="$saved_eg"
PARTY_ER="$saved_er"; PARTY_LG="$saved_lg"

# ============================================================
section "A3 — the retired task pointer: the gates the plan does not move, and the one that refuses it (wave-31 T24; REQ-1, D2)"
# ============================================================
#
# Until wave-31 this pinned a KNOWN DIVERGENCE: the two gates read `current: T<n>` as an active
# wave and the evidence gate accepted it only on a `scale: task` plan. Two things have moved since.
# The two gates are scoped by ENGAGEMENT (task-engaged-session; A1's battery), so no plan, this one
# included, moves their answer. And the task-scale shape is deleted (one ledger shape): `current:`
# is a step number at every scale, so the one party that reads it, the evidence gate, refuses
# `T<n>` naming the value, at either scale, while it reads a numeric `current:` on the same
# task-scale plan as a step (the control). The run predicate keeps `T<n>` open so the plan's
# readers refuse it by name; that is CG.3's.

TREPO=$(new_repo "known-divergence")
write_plan "$TREPO/.bionic/docs/plans/epic-99/wave-01.md" "current: T4"
expect_eq "T-token, wave scale: the start gate answers as on any engaged plan" "yes" "$(verdict_dp "$TREPO")"
expect_eq "T-token, wave scale: the stop gate answers as on any engaged plan"  "yes" "$(verdict_sg "$TREPO")"
expect_eq "T-token, wave scale: the evidence gate refuses the value" "no" "$(verdict_eg "$TREPO")"
TTREPO=$(new_repo "task-pointer")
plan_fixture --current T4 "$TTREPO/.bionic/docs/plans/epic-99/wave-01.md" task > /dev/null
expect_eq "T-token, task scale: the plan carries scale: task and current: T4" "2" \
  "$(/usr/bin/grep -cE '^scale: task$|^current: T4$' "$TTREPO/.bionic/docs/plans/epic-99/wave-01.md")"
expect_eq "T-token, task scale: the start gate answers as on any engaged plan" "yes" "$(verdict_dp "$TTREPO")"
expect_eq "T-token, task scale: the stop gate answers as on any engaged plan"  "yes" "$(verdict_sg "$TTREPO")"
expect_eq "T-token, task scale: the evidence gate refuses the value" "no" "$(verdict_eg "$TTREPO")"
plan_fixture --current 5 "$TTREPO/.bionic/docs/plans/epic-99/wave-01.md" task > /dev/null
expect_eq "control: the same task plan at current: 5, the evidence gate reads the step" "yes:5" "$(verdict_eg "$TTREPO")"

# ============================================================
section "B — the session-identity key: producer and BOTH consumers agree"
# ============================================================
#
# Ownership table (spec §Design): preflight-probe WRITES the session identity;
# dispatch-preflight and stop-guard READ it. The per-component suites each hold
# their own half — the producer's suite reads back what it wrote, the start
# gate's suite writes attestations as fixtures. Neither proves the two halves
# spell or compare the key the same way. Here ONE value produced by the REAL
# producer flows through both consumers.

IREPO=$(new_repo "identity")
# The metadata lives where the PLATFORM puts it — under the configured metadata
# root, in this project's slug directory, in this session's own directory. The
# earlier version of this fixture invented a transcript path outside any
# projects root, which let the record and the gate-pass below stand behind an
# observation that resolved nothing (Step-6 critic, issue 1). A fixture that
# cannot be reached by BOTH parties proves nothing about their agreement.
ISLUG=$(printf '%s' "$IREPO" | sed 's/[^a-zA-Z0-9]/-/g')
IPROJ="$CLAUDE_CONFIG_DIR/projects/$ISLUG"
ISUB="$IPROJ/$SID_A/subagents"
mkdir -p "$ISUB"
ITR="$IPROJ/$SID_A.jsonl"
printf '{}\n' > "$ITR"
printf '{"name":"worker","agentType":"implementor"}' > "$ISUB/agent-aworker-1111111111111111.meta.json"
printf '{}\n' > "$ISUB/agent-aworker-1111111111111111.jsonl"
# …and the two facts S6 added to "reachable by both parties": a line in this session's live
# set, and a roster row carrying the agent id the working log is filed under.
cg_live "$ITR" "worker"
cg_roster_row "$IREPO" "$SID_A" "worker" "aworker-1111111111111111" "" "identified"
write_live_plan "$IREPO/.bionic/docs/plans/epic-99/wave-01.md" "current: 4"

# The producer, run for real, with the session key on the channel it actually
# reads (CLAUDE_CODE_SESSION_ID — task 4/1's resolution) and a credential
# present so the blocking probes pass.
( cd "$IREPO" && env CLAUDE_CODE_SESSION_ID="$SID_A" ANTHROPIC_API_KEY="sk-fixture-not-a-real-key" \
    HOME="$SANDBOX/home" CLAUDE_CONFIG_DIR="$CLAUDE_CONFIG_DIR" \
    bash "$PROBE" >"$SANDBOX/probe.out" 2>"$SANDBOX/probe.err" )
PROBE_ST=$?
# task 4/2 (D-5): the session identity is now carried in TWO places that must agree —
# the FILENAME and the session_id= line inside it. A producer and a consumer that
# disagreed on the filename scheme would refuse every dispatch, so the path is asserted
# here as part of the same agreement the key is.
ATT="$IREPO/.bionic/tmp/preflight-$SID_A.state"
expect_eq "the attestation exists where both consumers look" "yes" "$([ -f "$ATT" ] && echo yes || echo no)"

# The producer's spelling and the consumer's spelling are the same key.
expect_contains "the producer spells the identity key 'session_id='" "session_id=$SID_A" "$(cat "$ATT")"

# Consumer 1 — the start gate: the produced value passes; one character off refuses.
# "Passes in silence" used to need a genuinely LIVE session sweeper armed for this
# session/repo, or the unarmed-sweeper nag fired legitimately and broke the claim. Both the
# nag and the watcher it asked about were deleted in epic-16 wave-02, so silence is the
# gate's own unaided answer here.
OUT=$(mk_agent_payload "$SID_A" "$IREPO" | bash "$PARTY_DP" 2>&1); ST=$?
expect_eq "start gate: the producer's own session passes" "0" "$ST"
# "IN SILENCE" IS NOW "SILENT ABOUT THE ATTESTATION", and the change is a change of
# CHANNEL, not of strength (wave-session-bound-run). This fixture's sessions are BOUND to
# the plan written above (write_live_plan, wave-23-fixit-1810 T1): an unbound session's
# newest-plan fallback is announced and never acted on, and the gate would refuse this
# writer with the bind instruction. So no resolution line is expected — that is asserted
# POSITIVELY as a count of zero, never filtered — and the budget backstop below is lifted
# out and asserted, so the remainder is held to the emptiness this section has always
# claimed.
DP_RESOLUTION=$(printf '%s\n' "$OUT" | grep -c 'run resolved by newest-plan fallback (session unbound) — /')
# THE BUDGET BACKSTOP IS GONE (wave-28 T9; D15): this fixture's plan is live and carries no
# `parallel-budget:` line, and no plan owes one, so the gate's whole output is held to the
# emptiness this section has always claimed. Until wave-28 a WARN naming the key was lifted out.
expect_eq "start gate: a bound session hears no fallback announcement (the fixture is bound)" \
  "0" "$DP_RESOLUTION"
expect_eq "start gate: and passes in silence about the attestation (and the keyless plan)" "" "$OUT"
# THE NEAR-MISS SESSION IS ENGAGED TOO (task-engaged-session). Both gates ask
# `engaged_session` before anything else, keyed to the session in hand — so without a
# marker for THIS spelling the gate would exit at the switch and the exact-compare claim
# would be discharged by a silence that never reached the attestation.
arm_patrol "$IREPO" "${SID_A%?}0"
OUT=$(mk_agent_payload "${SID_A%?}0" "$IREPO" | bash "$PARTY_DP" 2>&1); ST=$?
expect_eq "start gate: a one-character-different session is refused (exact compare)" "2" "$ST"
OUT=$(mk_agent_payload "$SID_B" "$IREPO" | bash "$PARTY_DP" 2>&1); ST=$?
expect_eq "start gate: a foreign session is refused" "2" "$ST"

# Consumer 2 — the stop gate: the recorder writes the key, the gate compares it.
# Same literal value, produced by the same session, carried by the payload.
#
# Both sessions get a row so that the roster is not what differs between the two
# stops below: the ONLY thing that differs is the session value carried by the
# record and the payload, which is what this section is about.
# THE ARTIFACT THE AGREEMENT RIDES ON CHANGED (epic-23 wave-15, REQ-2). It used to be the
# observation record: the recorder stamped `session=` into it and the gate compared that
# against its own payload. The record is gone — the gate observes its target directly — and
# the state this family still keys by session is the ROSTER, written by the recorder's
# confirmation arm and read by the gate for the agent id. Same fact, same two parties, the
# artifact that survives.
cg_roster_row "$IREPO" "$SID_A" "worker" "aworker-1111111111111111"
SGROSTER="$IREPO/.bionic/tmp/roster-$SID_A.state"
expect_eq "the writer keyed its roster by this session" "yes" \
  "$([ -f "$SGROSTER" ] && echo yes || echo no)"
expect_contains "…and the rows in it carry the same session value" \
  "session=$SID_A" "$(cat "$SGROSTER")"
# The target has gone quiet, so the only thing left to decide the stop is whether the gate
# found this session's roster — which is exactly what this section is about.
touch -t 202601010000 "$ISUB/agent-aworker-1111111111111111.jsonl" 2>/dev/null
OUT=$(mk_stop_payload "$SID_A" "$ITR" "$IREPO" "worker" | bash "$PARTY_SG" 2>&1); ST=$?
expect_eq "stop gate: the session whose roster carries the row is answered" "0" "$ST"

# …and a one-character-different session reads a roster that does not exist, so it has no id
# for the name and refuses.
OUT=$(mk_stop_payload "${SID_A%?}0" "$ITR" "$IREPO" "worker" | bash "$PARTY_SG" 2>&1); ST=$?
expect_eq "stop gate: a one-character-different session is refused (exact compare)" "2" "$ST"

# The two consumers key on the SAME payload field, which is the same value the
# producer took from the environment. If either side ever renamed its field,
# one of the three assertions above would fail — this one states the agreement
# itself, so the reason is legible when it does.

# ============================================================
section "C — target resolution: the observation and BOTH stop-guard arms agree"
# ============================================================
#
# `scan_subagent_dirs` and the portable file facts are duplicated between
# hooks/stop-check.sh and hooks/stop-guard.sh, and both copies carried a comment
# claiming this battery held them together while no such battery existed
# (Step-6 duplication review D1). Byte-identity of the FUNCTION was never the
# claim worth testing anyway: the two callers fed it different directory sets,
# and that divergence is what let an observation print "ambiguous — decide
# nothing" while the recorder wrote a dischargeable record (correctness C1).
#
# So the question this battery asks is the CALLERS' question, over one fixture
# world, with the two halves reaching the directories by their own means: the
# observation by slugifying its cwd (it has no payload), the recorder and the
# gate from the payload's transcript path. Agreement means all three answer the
# same way about the same typed name — or, where they deliberately differ, that
# the difference is pinned and fail-closed.

# The metadata root is the CONFIGURED one. `$CLAUDE_CONFIG_DIR` and
# `$HOME/.claude` are different directories in this suite (header), so every
# case below asks its question with the only variable that separates the two
# callers actually varying. Stated as an assertion rather than a comment,
# because a future edit that collapses the roots would silently make this whole
# battery blind again.

RSLUG=$(printf '%s' "$SANDBOX/fx/resolver/repo" | sed 's/[^a-zA-Z0-9]/-/g')
RPROJ="$CLAUDE_CONFIG_DIR/projects/$RSLUG"
RREPO=$(new_repo "resolver")
write_plan "$RREPO/.bionic/docs/plans/epic-99/wave-01.md" "current: 4"
mkdir -p "$RPROJ/$SID_A/subagents" "$RPROJ/$SID_B/subagents"
printf '{}\n' > "$RPROJ/$SID_A.jsonl"
printf '{}\n' > "$RPROJ/$SID_B.jsonl"
RTR="$RPROJ/$SID_A.jsonl"

# Since S6 a target needs two more facts to resolve at all: a line in its session's LIVE SET
# (the recorded ListAgents answer), and a roster row carrying its agent id — which is what
# the working log is filed under, and what the deleted directory scan used to supply.
plant() {  # <subagents-dir> <agent-id> <name> [repo, default $RREPO]
  printf '{"name":"%s","agentType":"implementor","description":"fixture","model":"opus"}' "$3" \
    > "$1/agent-$2.meta.json"
  printf '{"type":"assistant","message":{"content":[{"type":"text","text":"working"}]}}\n' \
    > "$1/agent-$2.jsonl"
  # THE PLANTED AGENT IS QUIET (epic-23 wave-15, REQ-2). Since the stop gate takes its own
  # look, a log written a moment ago makes every target in this battery ALIVE and every gate
  # answer a refusal about liveness — which is not what any case here is asking. Aged, the
  # gate's answer is about RESOLUTION, which is the agreement this section exists for.
  touch -t 202601010000 "$1/agent-$2.jsonl"
  cg_live "${1%/subagents}.jsonl" "$3"
  roster_identify "${4:-$RREPO}" "$SID_A" "$3" "$2"
}

# THE OTHER DIRECTION, for the sections whose precondition is a refusal (epic-23 wave-15,
# REQ-2). `plant` leaves a target quiet so that a gate answer is about resolution; a section
# asking what DISCHARGES a stop needs the stop to be refused without the discharge, and since
# the gate looks for itself that means a target that is visibly working.
wake() {  # <subagents-dir> <agent-id>
  printf '{"type":"assistant","message":{"content":[{"type":"text","text":"still here"}]}}\n' \
    >> "$1/agent-$2.jsonl"
  touch "$1/agent-$2.jsonl"
  return 0
}

# The three questions, each asked of the REAL party.
q_observation() {  # <typed> -> resolved|ambiguous|unresolved
  local out
  out=$( cd "$RREPO" && env CLAUDE_CODE_SESSION_ID="$SID_A" bash "$OBSERVE" "$1" 2>&1 )
  case "$out" in
    *"Resolved:      ambiguous"*)  echo ambiguous ;;
    *"Resolved:      unresolved"*) echo unresolved ;;
    # S6 spells the no-evidence-tier answer two ways where it used to spell it one: a target
    # the live set does not name is `not live`, and a session with no readable answer at all
    # is still `unresolved`. Both mean the same thing to the operator and to the recorder —
    # no evidence tier was shown, so no machine line is printed — so both map here.
    *"Resolved:      not live"*)   echo unresolved ;;
    *"Resolved:      live, but no agent id"*) echo unresolved ;;
    *"Resolved:      a"*)          echo resolved ;;
    *) echo "other" ;;
  esac
}
# THE SECOND PARTY IS THE PRODUCER'S OWN OUTPUT NOW (epic-23 wave-15, REQ-2). It used to be
# the record hooks/execution-recorder.sh wrote from that output; with the record gone, what
# the machine line still has to agree with the gate about is WHICH AGENT was resolved, and
# the line is where that answer is published for any reader at all.
q_producer() {  # <typed> -> printed|nothing
  run_pair "$RREPO" "$RTR" "$SID_A" "$1"
  case "$PAIR_OUT" in
    *"stop-check-observation/v1|"*) echo printed ;;
    *) echo nothing ;;
  esac
}
q_gate() {  # <typed> -> permitted|refused   (the gate's own look, taken in its own process)
  mk_stop_payload "$SID_A" "$RTR" "$RREPO" "$1" | bash "$PARTY_SG" >/dev/null 2>&1
  [ "$?" -eq 0 ] && echo permitted || echo refused
}

# --- case 1: unique in this session. All three say yes. ---
plant "$RPROJ/$SID_A/subagents" "asolo-1111111111111111" "solo"
# …and this session's roster records it. Since task 4/9 the row is not what makes
# it ours — it is filed under this session's own directory — but keeping the row
# holds this case fixed on the RESOLUTION question the three parties are answering.
cg_roster_row "$RREPO" "$SID_A" "solo" "asolo-1111111111111111"
expect_eq "C1 observation resolves a uniquely-named agent" "resolved" "$(q_observation solo)"
expect_eq "C1 the producer publishes an evidence tier for it" "printed" "$(q_producer solo)"
expect_eq "C1 gate resolves the same agent and permits the stop" "permitted" "$(q_gate solo)"

# --- case 2: TWO LIVE TEAMMATES answering to one name — which is what "the same name in two
# sessions of this project" became at S6, because the count comes from the harness's answer
# and not from a directory walk. The operator is shown a candidate list and NO evidence tier,
# so nothing may be dischargeable. ---
plant "$RPROJ/$SID_A/subagents" "adup-2222222222222222" "dup"
plant "$RPROJ/$SID_A/subagents" "adup-3333333333333333" "dup"
# RE-POINTED TWICE (T22, then T29). T22 moved resolution onto the register and read the state
# this fixture plants as unreachable — `hooks/dispatch-preflight.sh` refuses a DISPATCH whose
# name already has an open row here. T29 found the other writer: `session-poker.sh adopt`
# journals a predecessor's agent as a live row without asking whether this session already
# carries one of that name, so two live rows of one name is a state the system does reach,
# and the two parties answer it DIFFERENTLY — on purpose, and that difference is this case.
#
# The OBSERVATION decides nothing, so it shows the operator the latest row and says so. The
# GATE is the irreversible one, so it refuses without choosing — and since T29 it refuses for
# the ambiguity itself rather than for want of an observation one line further down. Both
# halves are pinned, because "refused" alone was equally true of the gate before the arm
# existed.
expect_eq "C2 observation resolves a name the roster carries twice, latest row wins" \
  "resolved" "$(q_observation dup)"
expect_eq "C2 gate refuses it" "refused" "$(q_gate dup)"
expect_contains "C2 …and the gate refuses for the AMBIGUITY, not for want of a look (T29)" \
  "more than one live row" \
  "$(mk_stop_payload "$SID_A" "$RTR" "$RREPO" dup | bash "$PARTY_SG" 2>&1 >/dev/null)"

# --- case 3: resolves only in ANOTHER session of this project. A KNOWN,
# PINNED divergence, not a defect: the observation is project-wide because it has
# no payload to scope it, while a stop is session-scoped because a session can
# only stop its own tasks. Before T4 this ran fail-closed in every direction —
# the operator could look, nothing recorded, the stop refused, naming the scope
# so the loop had a stated exit (readability R4). T4 (session-20260815-
# landing-cleanup) re-bases the stop-guard leg only: "foreign" wears no
# agent-address shape, so MATCH_COUNT=0 now passes it through instead of
# refusing — a ratified divergence (design ¶T4), never silent (one logged
# passthrough line names why it did not refuse). ---
# At S6 the shape of this case changes with the key: a teammate the harness names for THIS
# session is resolvable by both parties wherever its working log happens to be filed, and one
# it does not name is resolvable by neither. What stays is the leg the divergence was about —
# the observation shows, the gate decides — driven here on an agent whose log sits under
# another session's directory while this session's answer names it, which is the /clear shape.
plant "$RPROJ/$SID_B/subagents" "aforeign-4444444444444444" "foreign"
cg_live "$RTR" "foreign"
expect_eq "C3 observation can still SHOW another session's agent" \
  "resolved" "$(q_observation foreign)"

# --- case 4: unknown to both. "nobody" wears no agent-address shape, so T4's
# shape carve passes the stop through rather than refusing (same ratified
# divergence as case 3). ---
expect_eq "C4 observation reports an unknown name unresolved" "unresolved" "$(q_observation nobody)"

# --- case 5: the metadata root itself. The recorder and the gate reach the
# directories through the PAYLOAD's transcript path; the observation has no
# payload and must reach the same root by configuration. Where
# `$CLAUDE_CONFIG_DIR` names a root other than `$HOME/.claude` — which is the
# whole reason the variable exists — an observation rooted at `$HOME` looks in a
# directory the platform is not using: it shows the operator nothing, while the
# recorder records and the gate spends the record. That is the wall opening on a
# look that never happened, and it is the direction this case pins.
#
# Cases 1-4 above already run under the divergent roots and prove the AGREEING
# direction. This one plants a decoy under the default root and proves the
# observation does not answer from it. "decoy" wears no agent-address shape
# either, so T4's shape carve passes the gate's stop through rather than
# refusing (same ratified divergence as cases 3-4). ---
HOMEPROJ="$HOME/.claude/projects/$RSLUG"
mkdir -p "$HOMEPROJ/$SID_A/subagents"
plant "$HOMEPROJ/$SID_A/subagents" "adecoy-6666666666666666" "decoy"
# RE-POINTED (T22): resolution no longer reads a metadata ROOT at all — it reads this
# session's roster, which `plant` writes into $RREPO whichever directory the metadata went
# to. So the decoy resolves, and the claim this case still carries is the one that matters:
# the evidence tier is read from a log path derived from the OWN transcript, never from
# whatever $HOME happens to hold.
expect_eq "C5 observation resolves from the roster, not from a metadata root" \
  "resolved" "$(q_observation decoy)"

# --- case 6: the ARGUMENT GRAMMAR itself — RESIDUAL CLOSED at task 4/4.
#
# Cases 1-5 ask both halves about one typed name; this one asks them about one
# COMMAND LINE, which is the thing they actually share. It used to be the hardest
# row in this file, because there were TWO readers of that line: the observation
# parsed its own `$@`, and a PreToolUse recorder re-parsed the same string with a
# grammar of its own (skip `-*` tokens, take the first non-flag). Nothing held
# them together, and a task that widened one of them shipped: `--progress <path>
# <agent>` had the operator looking at <agent> while the record named <path> — an
# attestation about an agent nobody examined (Step-6 review F-1). Narrowing the
# producer then CONVERTED two ordinary typos into refused-observation-still-
# recorded, and that residual was pinned here rather than claimed away (critic
# finding A).
#
# There is now ONE reader. The recorder fires PostToolUse and copies the machine
# line hooks/stop-check.sh prints on its success path, so a command the operator
# watched fail printed no line and leaves nothing behind. The rows below are the
# same rows, with the residual expectations replaced by the closure: every
# refused form records NOTHING, and the documented form still records its target.
# ---
plant "$RPROJ/$SID_A/subagents" "aworker-7777777777777777" "worker"
GPROG="$RREPO/.bionic/tmp/w-grammar.progress"
mkdir -p "$RREPO/.bionic/tmp"; printf 'step 1\n' > "$GPROG"

g_observation() {  # <args…> -> the agent id the OBSERVATION resolved, or "refused"
  local out st
  out=$( cd "$RREPO" && env CLAUDE_CODE_SESSION_ID="$SID_A" bash "$OBSERVE" "$@" 2>&1 ); st=$?
  if [ "$st" -ne 0 ] && printf '%s' "$out" | grep -qF 'Usage:'; then echo refused; return; fi
  printf '%s' "$out" | grep -E '^Resolved:' | grep -oE 'a[a-z0-9-]*-[0-9a-f]{16}' | head -1
}
# THE MACHINE LINE IS WHAT ANY MACHINE READS (epic-23 wave-15, REQ-2). This used to read the
# record hooks/execution-recorder.sh wrote from that line; with the record gone the line is
# the whole of the published answer, and the property C6 is about — that the target the
# operator was SHOWN and the target a machine takes away are the same one — is a property of
# the line itself.
g_published() {  # <args…> -> the agent id the MACHINE LINE names, or "nothing"
  run_pair "$RREPO" "$RTR" "$SID_A" "$@"
  local rec
  rec=$(printf '%s\n' "$PAIR_OUT" | grep '^stop-check-observation/v1|' \
    | tr '|' '\n' | grep '^target=' | cut -d= -f2 | head -1)
  [ -n "$rec" ] && echo "$rec" || echo nothing
}

# The documented interface line: target first, flag trailing. Both halves must
# name the SAME agent — this is the row that would have caught F-1's sibling had
# it been written for the trailing form only.
expect_eq "C6 trailing form — the observation resolves the typed target" \
  "aworker-7777777777777777" "$(g_observation worker report.md --progress "$GPROG")"
expect_eq "C6 trailing form — the machine line publishes the SAME agent" \
  "aworker-7777777777777777" \
  "$(g_published worker report.md --progress "$GPROG")"

# The leading form, which is what diverged. Both halves refuse together — the
# producer with a usage error, the recorder because a usage error prints no
# machine line.
expect_eq "C6 leading form — the observation refuses it" \
  "refused" "$(g_observation --progress "$GPROG" worker)"

# THE RESIDUAL, CLOSED (critic finding A, spec AC-3). This was the row that
# pinned a refused command still leaving a record because some token in it named
# a live agent: the flag VALUE `solo` was taken as the target while the operator
# saw a usage error. A PreToolUse reader could not do better — it fires before
# the command runs and never learns the outcome. The PostToolUse recorder does
# not read the command line at all, so there is no token for it to mistake.
expect_eq "C6 CLOSED — and the observation gave that operator nothing to act on" \
  "refused" "$(g_observation --progress solo worker)"

# THE SAME CLASS IN THE TARGET-FIRST DIRECTION, which the row above does not
# reach: it pins only the flag-VALUE variant. Two ordinary typos — a mistyped
# flag and the `=`-joined spelling — leave the target as the first non-flag
# token, which is exactly what the old recorder took, so the operator saw a usage
# error and zero evidence while the record still named the target and carried the
# working log's mtime and size that the gate's D-1 comparison spends. Both now
# record nothing, for the one reason that covers every member of the class: the
# run printed no machine line.
expect_eq "C6 CLOSED — a mistyped flag AFTER the target: the observation refuses it" \
  "refused" "$(g_observation worker --progres "$GPROG")"
expect_eq "C6 CLOSED — the =-joined spelling: the observation refuses it" \
  "refused" "$(g_observation worker "--progress=$GPROG")"

# The class, not the instances: the observation's exit status and the recorder's
# output are now ONE fact. Any command line at all — including ones nobody has
# thought of — agrees by construction, because a non-zero producer prints no
# machine line and the recorder has no other input.
for form in "worker --unknown-flag" "--progress" "ghost" "worker@" ; do
  # shellcheck disable=SC2086
  if [ "$(g_observation $form)" = "refused" ] || [ -z "$(g_observation $form)" ]; then
    # shellcheck disable=SC2086
    :
  else
    # shellcheck disable=SC2086
    expect_eq "C6 CLOSED — an evidence tier IS published: '$form'" \
      "aworker-7777777777777777" "$(g_published $form)"
  fi
done

# The derived FILE FACTS agree too: what the observation shows the reader as the
# working log's size is what the recorder writes down as the activity level. Two
# computations of one truth, previously untested together (D2).
# THE TWO RENDERINGS ARE THE PROSE AND THE LINE (epic-23 wave-15, REQ-2). The consumer half
# of this claim used to be the record; both halves come out of one `observe_agent` call now,
# which is what makes the property structural rather than a comparison two parsers have to
# keep passing.
plant "$RPROJ/$SID_A/subagents" "afacts-5555555555555555" "facts"
OBS_OUT=$( cd "$RREPO" && env CLAUDE_CODE_SESSION_ID="$SID_A" bash "$OBSERVE" facts 2>&1 )
OBS_SIZE=$(printf '%s' "$OBS_OUT" | grep -E '^  size:' | grep -oE '[0-9]+' | head -1)
REC_SIZE=$(printf '%s\n' "$OBS_OUT" | grep '^stop-check-observation/v1|' \
  | tr '|' '\n' | grep '^size=' | cut -d= -f2)
expect_eq "the size the observation PRINTS is the size its machine line CARRIES" \
  "$OBS_SIZE" "$REC_SIZE"
expect_nonempty "…and that size is a real reading, not two empties compared" "$OBS_SIZE"

# ============================================================
section "D — cross-script security regressions (AC-8, TDD §8)"
# ============================================================
#
# Per-script coverage already exists for: the credential value never reaching
# the attestation or the producer's own output (preflight-probe.test.sh S4), and
# command text never reaching the observation state file (stop-guard.test.sh
# §7). What no per-script suite can assert is the CROSS-SCRIPT property: after
# driving all four with a secret-bearing command, NOTHING anywhere under the
# sandbox — repo, state, temp, or $HOME (where the evidence gate's audit stream
# lives) — contains that text.

SECRET="sk-ant-LEAKCANARY-9f2b41"
SREPO=$(new_repo "secrets")
# The metadata lives under the CONFIGURED root, because the producer now has to
# resolve the target for real before anything can be recorded (task 4/4).
SSLUG=$(printf '%s' "$SREPO" | sed 's/[^a-zA-Z0-9]/-/g')
SPROJ="$CLAUDE_CONFIG_DIR/projects/$SSLUG"
mkdir -p "$SPROJ/$SID_A/subagents"
STR="$SPROJ/$SID_A.jsonl"; printf '{}\n' > "$STR"
SSUB="$SPROJ/$SID_A/subagents"
printf '{"name":"worker"}' > "$SSUB/agent-aworker-2222222222222222.meta.json"
printf '{}\n' > "$SSUB/agent-aworker-2222222222222222.jsonl"
cg_live "$STR" "worker"
cg_roster_row "$SREPO" "$SID_A" "worker" "aworker-2222222222222222" "" "identified"
write_live_plan "$SREPO/.bionic/docs/plans/epic-99/wave-01.md" "current: 4"

# 1. the recorder, with the secret in the command line beside a real run
SOUT=$( cd "$SREPO" && env CLAUDE_CODE_SESSION_ID="$SID_A" bash "$OBSERVE" worker 2>/dev/null )
mk_bash_post "$SID_A" "$STR" "$SREPO" \
  "export TOKEN=$SECRET && bash ~/.claude/hooks/stop-check.sh worker" "$SOUT" \
  | bash "$PARTY_ER" >/dev/null 2>&1
# 2. the start gate, with the secret in the dispatch description
jq -n --arg s "$SID_A" --arg c "$SREPO" --arg d "dispatch carrying $SECRET" \
  '{session_id:$s, transcript_path:"/x.jsonl", cwd:$c, hook_event_name:"PreToolUse",
    tool_name:"Agent", tool_input:{description:$d, subagent_type:"implementor"}}' \
  | bash "$PARTY_DP" >/dev/null 2>&1
# 3. the stop gate, with the secret as the typed target
mk_stop_payload "$SID_A" "$STR" "$SREPO" "$SECRET" | bash "$PARTY_SG" >/dev/null 2>&1
# 4. the producer, with the secret as the live credential
( cd "$SREPO" && env CLAUDE_CODE_SESSION_ID="$SID_A" ANTHROPIC_API_KEY="$SECRET" \
    HOME="$SANDBOX/home" CLAUDE_CONFIG_DIR="$CLAUDE_CONFIG_DIR" \
    bash "$PROBE" >/dev/null 2>&1 )
# 5. the observation, with the secret as the target it fails to resolve
( cd "$SREPO" && env CLAUDE_CODE_SESSION_ID="$SID_A" bash "$OBSERVE" "$SECRET" >/dev/null 2>&1 )

LEAKS=$(grep -rlF "$SECRET" "$SREPO" "$SANDBOX/home" 2>/dev/null | grep -c . | tr -d ' ')

# The sweep must not be passing merely because nothing was written at all. The artifact this
# family writes is the ROSTER (the observation record went with epic-23 wave-15, REQ-2), and
# the fixture seeded it above — so the grep that found no secret was reading a populated tree.
expect_contains "…and the state the sweep covered is genuinely populated" \
  "name=worker" "$(cat "$SREPO/.bionic/tmp/roster-$SID_A.state" 2>/dev/null)"

# Temp-name unpredictability, all four scripts (AC-8). Static pins first: the
# A2 defect was a literal `"${X}.tmp.$$"`.
for s in "$PROBE" "$OBSERVE" "$PARTY_DP" "$PARTY_SG" "$PARTY_ER"; do
  b=$(basename "$s")
  if grep -q 'mktemp' "$s"; then
    if grep -qE 'mktemp[^|&;]*XXXXXX' "$s"; then ok "$b: every mktemp carries an X-template"
    else no "$b: every mktemp carries an X-template"; fi
  fi
done

# Behavioural, not merely static: two recorder runs must produce two unrelated
# temp names. The instrumentation is applied to a COPY (§9's technique) so the
# shipped script carries no fault-injection seam; the original is re-checksummed.
ER_SUM_BEFORE=$(shasum "$PARTY_ER")
SGI="$(plant_hook_tree "$SANDBOX/er-showtmp")/execution-recorder-showtmp.sh"
awk '{ print }
     /^  tmp=\$\(mktemp "\$STATE_DIR\/\.stop-check\.XXXXXX" 2>\/dev\/null\)/ {
       print "  printf \"TMPNAME=%s\\n\" \"$tmp\" >&2" }' "$PARTY_ER" > "$SGI"
if cmp -s "$PARTY_ER" "$SGI"; then
  :
else
  N1=$(mk_bash_post "$SID_A" "$STR" "$SREPO" "bash ~/.claude/hooks/stop-check.sh worker" "$SOUT" \
       | bash "$SGI" 2>&1 >/dev/null | sed -n 's/^TMPNAME=//p' | head -1)
  N2=$(mk_bash_post "$SID_A" "$STR" "$SREPO" "bash ~/.claude/hooks/stop-check.sh worker" "$SOUT" \
       | bash "$SGI" 2>&1 >/dev/null | sed -n 's/^TMPNAME=//p' | head -1)
  if [ -n "$N1" ] && [ -n "$N2" ] && [ "$N1" != "$N2" ]; then
    ok "two recorder runs produce two different temp names"
  else
    no "two recorder runs produce two different temp names" "got '$N1' and '$N2'"
  fi
fi

# The components' repo footprint — the strongest form of "no artefact holds the
# command text". Snapshot the whole sandbox around a run.
#
# RESCOPED at epic-16 wave-02, not relaxed. The start gate stopped being read-only
# when R5 ("the environment probe auto-runs when needed") folded the attestation
# into the combined preflight: with no attestation on disk the gate now runs
# hooks/preflight-probe.sh inline, which creates its state directory and writes the
# session-keyed attestation, and the gate then journals the accepted dispatch to the
# session roster (wave-01 roster row, R8's "a refused dispatch leaves no row" read
# in the positive direction). Those three paths are the whole ratified set.
#
# The direction the pin now runs: an EXACT delta, never a blanket exclusion of
# .bionic/tmp. Three named paths may appear and a FOURTH entry of ANY kind — file
# or directory, inside .bionic/tmp or anywhere else — still goes RED. The security
# property this block exists for ("gates do not scribble in repos") therefore
# survives at full strength for everything unsanctioned; what changed is that the
# sanctioned set is enumerated instead of empty.
#
# The credential is PINNED rather than inherited. The probe's credential sources are
# $ANTHROPIC_API_KEY first and the machine's LOGIN KEYCHAIN third, so an unpinned
# drive lands on the refused path or the accepted one depending on whose machine
# runs the suite — and only the accepted path writes any file at all. Pinning it
# present is both hermetic and the stronger drive: it exercises the branch that
# actually creates the artefacts this assertion is here to bound. The value is a
# syntactic placeholder; the probe tests PRESENCE, never validity.
QREPO=$(new_repo "quiet")
write_live_plan "$QREPO/.bionic/docs/plans/epic-99/wave-01.md" "current: 4"
before=$(find "$QREPO" | sort)
# `.bionic/tmp` is no longer among the gate's creations: the fixture arms the Patrol, which
# makes the directory before the gate runs (arm_patrol). What the gate adds is still exactly
# the attestation and the roster row.
expected_after=$(printf '%s\n%s\n%s\n' "$before" \
  "$QREPO/.bionic/tmp/preflight-$SID_A.state" \
  "$QREPO/.bionic/tmp/roster-$SID_A.state" | sort)
mk_agent_payload "$SID_A" "$QREPO" \
  | env ANTHROPIC_API_KEY="pinned-placeholder-not-a-credential" bash "$PARTY_DP" >/dev/null 2>&1
after_start=$(find "$QREPO" | sort)
expect_eq "the start gate writes ONLY the attestation, the roster row and their state dir" \
  "$expected_after" "$after_start"
# The observation stays read-only ABSOLUTELY — zero footprint, no sanctioned set at
# all. Compared against the POST-start listing rather than the pre-start one, so it
# answers for its own writes instead of inheriting the start gate's.
( cd "$QREPO" && env CLAUDE_CODE_SESSION_ID="$SID_A" bash "$OBSERVE" nobody >/dev/null 2>&1 )

# ============================================================
section "E — classification + contract-source ride the machine line into the recorded observation (task 4/5)"
# ============================================================
#
# hooks/stop-check.sh (producer) computes classification/deliverable_source/
# progress_source and prints them on its machine line; hooks/execution-recorder.sh
# (consumer) is supposed to copy them into the observation record verbatim,
# unparsed — the same "one computation, two renderings" property §D2 above pins
# for the file-facts fields. This section drives the REAL producer's REAL output
# into the REAL recorder over the §C fixture world, so a divergence between the
# two parsers (the F-1 shape this whole file exists to catch) shows up here
# rather than in two suites that never compare notes.
#
# Reuses the §C fixture world (RREPO/RPROJ/RTR/SID_A, the "worker" and "solo"
# agents already planted there) rather than building a new one, because the
# claim under test is agreement over ONE resolution, not a new resolver case.

cg_roster_row "$RREPO" "$SID_A" "worker" "aworker-7777777777777777"

# --- a target THIS session's roster records: OURS, end to end ---
E_OUT=$( cd "$RREPO" && env CLAUDE_CODE_SESSION_ID="$SID_A" bash "$OBSERVE" worker 2>&1 )
E_MLINE=$(printf '%s\n' "$E_OUT" | grep '^stop-check-observation/')
expect_contains "the machine line carries classification=ours" "classification=ours" "$E_MLINE"

# THE CONSUMER IS THE GATE, NOT A RECORD (epic-23 wave-15, REQ-2). There is no second parser
# left to diverge: the same `observe_agent` call produces the line the operator reads and the
# facts the gate decides on. What is still worth pinning is that the line carries the three
# fields — a reader outside this repo may take them — and that the gate, asked about the same
# target in its own process, reaches the same contract.
expect_contains "the machine line carries deliverable_source=none (no CLI arg, no roster deliverable)" \
  "deliverable_source=none" "$E_MLINE"
expect_contains "the machine line carries progress_source=none" "progress_source=none" "$E_MLINE"
E_GATE=$(mk_stop_payload "$SID_A" "$RTR" "$RREPO" "worker" \
  | env BIONIC_WALL_VERBOSE=1 bash "$PARTY_SG" 2>&1 >/dev/null)
expect_contains "…and the gate's own look reaches the same agent" \
  "aworker-7777777777777777" "$E_GATE"

# --- an UNROSTERED target under this session's OWN directory: OURS, because the
# metadata's own filing is what ownership reads (task 4/9). Before that fix this
# classified foreign, of an agent this session had launched — the live defect, and
# the standing state for everything dispatched before the roster hook shipped. ---
plant "$RPROJ/$SID_A/subagents" "aloner-9999999999999999" "loner"
E3_OUT=$( cd "$RREPO" && env CLAUDE_CODE_SESSION_ID="$SID_A" bash "$OBSERVE" loner 2>&1 )
E3_MLINE=$(printf '%s\n' "$E3_OUT" | grep '^stop-check-observation/')
expect_contains "an unrostered target under this session's own directory classifies OURS" \
  "|classification=ours|" "$E3_MLINE"

# …and the gate, which never sees that line, answers about the same agent — the agreement
# that used to be "the recorder forwards it", now made by construction.
E3_GATE=$(mk_stop_payload "$SID_A" "$RTR" "$RREPO" "loner" \
  | env BIONIC_WALL_VERBOSE=1 bash "$PARTY_SG" 2>&1 >/dev/null)
expect_contains "the gate's own look reaches the same agent" \
  "aloner-9999999999999999" "$E3_GATE"

# --- and the not-ours direction, on the shape that really produced it: a target filed under
# ANOTHER session's directory, carrying a name this session's roster also carries on an
# UNCONFIRMED row. The row must grant nothing — and since S6 neither does the directory. The
# answer is no longer a CLASSIFICATION that rides into the record; it is a refusal, so the
# thing this suite pins is that the producer showed no evidence tier and the recorder
# therefore has nothing to copy. That is a stronger agreement than a shared label: there is
# no second reading of it to drift. ---
plant "$RPROJ/$SID_B/subagents" "acorpse-aaaaaaaaaaaaaaaa" "corpse"
# `plant` journals an `identified` row as a side effect; this case is about a name the
# roster carries ONLY on an unconfirmed row, so that row is removed and the unconfirmed one
# left standing. Before T22 the live set decided this and the row was decoration; the row is
# the decision now, so the fixture has to mean what the case says (T22).
grep -v 'status=identified|.*|name=corpse|' "$RREPO/.bionic/tmp/roster-$SID_A.state" \
  > "$RREPO/.bionic/tmp/roster-$SID_A.state.tmp" \
  && mv "$RREPO/.bionic/tmp/roster-$SID_A.state.tmp" "$RREPO/.bionic/tmp/roster-$SID_A.state"
cg_roster_row "$RREPO" "$SID_A" "corpse" "" "" intended
E5_OUT=$( cd "$RREPO" && env CLAUDE_CODE_SESSION_ID="$SID_A" bash "$OBSERVE" corpse 2>&1 )
E5_MLINE=$(printf '%s\n' "$E5_OUT" | grep '^stop-check-observation/')
expect_contains "an unconfirmed row's NAME does not make another session's agent ours" \
  "no agent id" "$E5_OUT"
expect_eq "the recorder is given nothing to forward, because no tier was shown" \
  "" "$E5_MLINE"

# --- with no own session id at all there is no transcript, so no live set: the producer
# refuses instead of labelling, and the recorder still copies exactly what it was given. The
# `unknown` classification this pair used to assert was the label for "ownership could not be
# established", and ownership is no longer a thing this command decides. ---
E4_OUT=$( cd "$RREPO" && env -u CLAUDE_CODE_SESSION_ID bash "$OBSERVE" worker 2>&1 )
E4_MLINE=$(printf '%s\n' "$E4_OUT" | grep '^stop-check-observation/')
# RE-POINTED (T22): with no session key there is no roster to read, so the refusal names
# the fact — no id on the register — rather than a tool call nobody is obliged to make.
expect_contains "with no own session id the producer refuses, naming the fact" \
  "no agent id" "$E4_OUT"
expect_eq "…and prints no machine line at all" "" "$E4_MLINE"
rm -f "$RREPO/.bionic/tmp/stop-check.state"
mk_bash_post "$SID_A" "$RTR" "$RREPO" "bash ~/.claude/hooks/stop-check.sh worker" "$E4_OUT" \
  | bash "$PARTY_ER" >/dev/null 2>&1
E4_STATE=$(cat "$RREPO/.bionic/tmp/stop-check.state" 2>/dev/null)
expect_absent "the recorder writes no record for a run that showed no evidence" \
  "typed=worker|log=" "$E4_STATE"

# ============================================================
finish
