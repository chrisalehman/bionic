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
section "F — the roster row and the observer/progress fields: writer, producer and GATE agree (task 4/6)"
# ============================================================
#
# Task 4/6 turned the stop gate into a reader of four things it had never read:
# the session roster's `name=`/`agent_id=` (the foreign-stop rule), and the
# record's `observer=`, `progress=`/`progress_mtime=`/`progress_state=` (the
# same-actor and progress-staleness checks). Every one of them is written by one
# script and read by another, which is this suite's whole subject — a field whose
# producer and consumer drift apart fails silently and in the OPEN direction (the
# gate simply stops finding what it is looking for).
#
# The roster row here is the one hooks/dispatch-preflight.sh REALLY WROTE in
# section B, from the real brief in mk_agent_payload — not a fixture. So the
# chain driven below is writer → producer → recorder → gate, end to end, over one
# row.

ROSTER_F="$IREPO/.bionic/tmp/roster-$SID_A.state"
expect_contains "the start gate really journalled the dispatch (section B's own row)" \
  "name=w99-impl" "$(cat "$ROSTER_F" 2>/dev/null)"
expect_contains "…carrying the progress path lifted from the brief" \
  "progress=.bionic/tmp/w99.progress" "$(cat "$ROSTER_F" 2>/dev/null)"

# The agent that row describes, now spawned. Its id is what a confirmed row would
# carry; the row itself is still `intended`, which is the mid-dispatch state the
# NAME fallback exists for.
plant "$ISUB" "aw99impl-8888888888888888" "w99-impl" "$IREPO"
printf 'stage 1\n' > "$IREPO/.bionic/tmp/w99.progress"

F_OUT=$( cd "$IREPO" && env CLAUDE_CODE_SESSION_ID="$SID_A" bash "$OBSERVE" w99-impl 2>&1 )
F_MLINE=$(printf '%s\n' "$F_OUT" | grep '^stop-check-observation/')
expect_contains "…and takes the contracted progress path from it" \
  "progress=.bionic/tmp/w99.progress" "$F_MLINE"
expect_contains "…recording where the contract came from" "progress_source=roster" "$F_MLINE"
expect_contains "…and the state it found the artifact in" "progress_state=present" "$F_MLINE"

# THE GATE TAKES THE SAME CONTRACT OFF THE SAME ROW (epic-23 wave-15, REQ-2). The record
# this used to pass through is gone, and the claim is stronger without it: the gate reads the
# roster's progress path itself, at the moment of the stop, so a divergence between what the
# writer lifted from the brief and what the gate measures cannot exist.
F_GATE=$(mk_stop_payload "$SID_A" "$ITR" "$IREPO" "w99-impl" \
  | env BIONIC_WALL_VERBOSE=1 bash "$PARTY_SG" 2>&1 >/dev/null); F_GST=$?
expect_contains "the gate reads the same contracted progress path off the same row" \
  ".bionic/tmp/w99.progress" "$F_GATE"
expect_eq "…and judges the target alive, because that artifact just moved (wave-31 T32: allowed, its verdict recorded as reason=)" "0" "$F_GST"
expect_contains "…saying so on the look" "is ALIVE and its contract is undelivered" "$F_GATE"

# …and a write to THAT path — the one the writer named, the producer resolved and
# the recorder stored — is what the gate calls stale. A disagreement anywhere in
# that chain shows up here as a stop that quietly stays permitted.
# mtime_after <file>… — set each file's mtime two seconds ahead of now. The rows below need a write
# whose mtime is strictly later than the file's earlier one (and than the row's launched_at), which
# mtime granularity of one second gives only to a write made a second later; setting the time says so
# without the wait. A future mtime reads as age 0 (observe.sh clamps it), so "inside the cadence" holds.
mtime_after() {
  touch -t "$(date -v+2S +%Y%m%d%H%M.%S 2>/dev/null || date -d '+2 seconds' +%Y%m%d%H%M.%S)" "$@"
}
F2_OUT=$( cd "$IREPO" && env CLAUDE_CODE_SESSION_ID="$SID_A" bash "$OBSERVE" w99-impl 2>&1 )
mk_bash_post "$SID_A" "$ITR" "$IREPO" "bash ~/.claude/hooks/stop-check.sh w99-impl" "$F2_OUT" \
  | bash "$PARTY_ER" >/dev/null 2>&1
printf 'stage 2\n' >> "$IREPO/.bionic/tmp/w99.progress"; mtime_after "$IREPO/.bionic/tmp/w99.progress"
OUT=$(mk_stop_payload "$SID_A" "$ITR" "$IREPO" "w99-impl" | bash "$PARTY_SG" 2>&1); ST=$?
expect_eq "a write to the roster-contracted progress path is what the look reads as alive (wave-31 T32: allowed, its verdict recorded as reason=)" "0" "$ST"
expect_contains "…the verdict naming it" "is ALIVE and its contract is undelivered" "$OUT"

# THE SAME CHAIN, WITH THE ROSTER LONG (Step-6 critic F-1). The shipped
# performance remediation capped the roster at 200 rows and evicted by RECENCY,
# which knows nothing about whether the evicted row belongs to an agent that is
# still running. A live agent's row is the only copy of its contract, and the
# refusal just proven above is sourced from it — so past the cap the wall did not
# weaken, it disappeared: `record/w3-critic-repro-cap.sh` measured the identical
# sequence as exit 2 under the cap and exit 0 over it, with the operator shown
# `progress=(none recorded)`, indistinguishable from a brief that declared none.
#
# This is the row that failed. It belongs in THIS suite rather than the
# recorder's own, because the property is cross-script: the file the recorder
# writes is the file the gate reads, and the recorder alone cannot see that
# dropping a row disarms another program. `tests/execution-recorder.test.sh`
# asserted only that the row THIS event confirmed survived the fold, which is why
# 110/110 was green over the defect.
F4_ROSTER="$IREPO/.bionic/tmp/roster-$SID_A.state"
F4_BEFORE=$(grep -c "^${ROSTER_ROW_SCHEMA}|" "$F4_ROSTER" 2>/dev/null || echo 0)
{
  _i=0
  while [ "$_i" -lt 260 ]; do
    roster_row_fixture status=confirmed session="$SID_A" name="old-$_i" \
      agent_id="aold-$_i" launched_at=2026-08-05T00:00:00Z tool_use_id="toolu_OLD$_i"
    _i=$((_i + 1))
  done
} >> "$F4_ROSTER"

# A SECOND dispatch, journalled by the REAL start gate, whose completion is the
# event that used to rewrite the file. The live agent's row is the OLDEST in it,
# which is exactly the position eviction-by-recency takes first.
mk_agent_payload "$SID_A" "$IREPO" \
  | jq '.tool_input.name = "w99-other" | .tool_use_id = "toolu_OTHER_DISPATCH"' \
  | bash "$PARTY_DP" >/dev/null 2>&1
mk_agent_post "$SID_A" "$ITR" "$IREPO" "toolu_OTHER_DISPATCH" "w99-other" \
  | bash "$PARTY_ER" >/dev/null 2>&1
expect_contains "the other dispatch's completion is journalled" \
  "agent_id=a26bd30bf8616411b" "$(grep 'status=confirmed|.*name=w99-other|' "$F4_ROSTER" 2>/dev/null)"
expect_eq "no row is evicted to make room for it (append-only, unbounded)" \
  "$((F4_BEFORE + 262))" "$(grep -c "^${ROSTER_ROW_SCHEMA}|" "$F4_ROSTER" 2>/dev/null || echo 0)"
# Both of these read the ROW, never the file. Scoping is load-bearing twice over:
# the second dispatch above carries the same brief, so a file-wide grep for the
# contract would stay green with the live row gone — and `expect_contains` cannot
# be trusted on a haystack this size at all. It is `printf | grep -qF` under
# `pipefail`, so a match near the TOP of a 68 KB haystack makes grep exit before
# printf finishes, printf takes SIGPIPE, and the pipeline returns 141: a FALSE
# FAIL on a string that is present. Verified in isolation — same haystack, early
# match 141, late match 0, and 0 with pipefail off. It fails safe (red, not
# green) and it is not this task's to fix in six suites at once, but it is why
# nothing here hands a whole roster to an assertion.
F4_LIVE_ROW=$(grep 'name=w99-impl|' "$F4_ROSTER" 2>/dev/null)
expect_contains "the LIVE agent's row survives a long session" \
  "name=w99-impl" "$F4_LIVE_ROW"
expect_contains "…carrying the contract state that is its only copy" \
  "progress=.bionic/tmp/w99.progress" "$F4_LIVE_ROW"

# …and the wall that hangs off that row still fires. Same three steps as the
# refusal above — observe, the agent writes, stop — with nothing different but
# the length of the file.
F4_OUT=$( cd "$IREPO" && env CLAUDE_CODE_SESSION_ID="$SID_A" bash "$OBSERVE" w99-impl 2>&1 )
expect_contains "the producer still reads the contract off the long roster" \
  "progress_source=roster" "$(printf '%s\n' "$F4_OUT" | grep '^stop-check-observation/')"
mk_bash_post "$SID_A" "$ITR" "$IREPO" "bash ~/.claude/hooks/stop-check.sh w99-impl" "$F4_OUT" \
  | bash "$PARTY_ER" >/dev/null 2>&1
printf 'stage 3\n' >> "$IREPO/.bionic/tmp/w99.progress"; mtime_after "$IREPO/.bionic/tmp/w99.progress"
OUT=$(mk_stop_payload "$SID_A" "$ITR" "$IREPO" "w99-impl" | bash "$PARTY_SG" 2>&1); ST=$?
# THE GUARD RECORDS ITS VERDICT AND DENIES NOTHING (wave-31 T32; D6, AC-6.5): the stop of a working
# agent is allowed and the look's verdict written on its row as reason=.
expect_eq "the guard still judges the target past the old cap (critic F-1), and allows the stop (wave-31 T32)" "0" "$ST"
# THE EXIT CODE ALONE CANNOT TELL A JUDGED STOP FROM AN UNJUDGED ONE (wave-28 T80). Since T70 the
# guard refuses with exit 2 when it runs past its own deadline, and on this long roster it did:
# every row here passed on a stop the guard never judged. The reason is what says it judged.
expect_contains "…on the target's own state: it is alive, its contract undelivered" \
  "is ALIVE and its contract is undelivered" "$OUT"
expect_absent "…and not because the guard ran out of time on the long roster" \
  "did not finish in" "$OUT"

# WHO IS STOPPING NO LONGER CHANGES THE ANSWER (epic-23 wave-15, REQ-2; ADR-028). D-3 asked
# whether the recorded look was the STOPPER'S OWN: any record for the target used to discharge
# any actor's stop, so a subagent's look could pay for the orchestrator's. Both halves of that
# rule are gone with the record — every stop takes its own look, in its own process — and the
# agreement worth pinning is the one that replaced it: the SAME target answered IDENTICALLY
# whichever actor asks, because the answer is a fact about the target and not about who looked.
F3_ORCH=$(mk_stop_payload "$SID_A" "$ITR" "$IREPO" "w99-impl" \
  | bash "$PARTY_SG" 2>&1 >/dev/null); F3_OST=$?
F3_SUB=$(mk_stop_payload "$SID_A" "$ITR" "$IREPO" "w99-impl" \
  | jq '. + {agent_id:"asubagent-2020202020202020", agent_type:"general-purpose"}' \
  | bash "$PARTY_SG" 2>&1 >/dev/null); F3_SST=$?
expect_eq "a subagent's stop and the orchestrator's reach the same verdict" "$F3_OST" "$F3_SST"
expect_eq "…and it is the same line, word for word" "$F3_ORCH" "$F3_SUB"
expect_eq "…which is the allowed stop this target's own state earns, its verdict recorded (wave-31 T32)" "0" "$F3_OST"
# Two deadline refusals are also the same line, word for word, and exit 2 (T80): the reason
# is what proves both actors' stops were judged.
expect_contains "…and its reason is the target's state, for both actors" \
  "is ALIVE and its contract is undelivered" "$F3_ORCH"
expect_absent "…not the guard's deadline" "did not finish in" "$F3_ORCH"

# The field NAMES themselves, stated as the agreement they are — so a rename
# breaks this suite with a legible reason rather than turning a wall inert.

# ============================================================
section "G — the roster FILENAME is one pattern with five sites (6-axis D-1)"
# ============================================================
#
# `roster-<session-id>.state` under `.bionic/tmp/` is constructed independently in
# five places: hooks/dispatch-preflight.sh (the writer, via ROSTER_PREFIX/SUFFIX),
# hooks/preflight-probe.sh (a declared reader copy of the same two constants), and
# BARE LITERALS in hooks/execution-recorder.sh, hooks/stop-guard.sh and
# hooks/stop-check.sh. The spec's ownership table named no owner for it, and the
# only cross-surface guard was a substring grep for `roster-` in the gate's source
# — which a change to the SUFFIX, or to the directory, passes untouched.
#
# So the pattern is driven, not grepped: the writer writes at the canonical path,
# each reader is shown finding it there, and the same file at a MUTATED name is
# found by NONE of them. The mutation is what makes this an agreement test rather
# than a restatement — a suffix change goes red here in four places at once.
G_ROSTER="$IREPO/.bionic/tmp/roster-$SID_A.state"
G_MUTANT="$IREPO/.bionic/tmp/roster-$SID_A.txt"

# THE LINEAGE §F LEFT OPEN IS LANDED FIRST (T29). §F planted an `identified` row for
# `w99-impl` under its own agent id, and `g_confirm` below completes a row for that same NAME
# under a different one — two rows of one name, both live. Since T29 the stop gate refuses
# that as an ambiguity, one step BEFORE the refusal this section measures, so the leg would
# answer about the ambiguity arm instead of about the roster filename. On the machine two live
# rows of one name are reached only by adoption; here they were reached by two sections
# sharing a fixture name. The marker is the real landing writer and it states what happened
# between the two sections: §F's agent finished, which is what frees the name for §G to use
# again — the exact discharge T26's latest-contract reading was built to honour.
swept_marker_write "$G_ROSTER" "2026-09-14T00:00:00Z" "$SID_A" "w99-impl" \
  "aw99impl-8888888888888888" "MET"
# RE-AUTHORED BY T17 (epic-23 wave-20, D10): the marker above used to be the whole discharge,
# because `live_ids_of_name` — the ambiguity arm's predicate — closed a name on a MET marker.
# It now asks `roster_open_names`, which closes a name only on the sweeper ledger's ack stamped
# after the row's launch; a MET marker records the landing and frees nothing. So §F's agent
# finishing is stated the way the Patrol states it, by an ack — and §G using the name again is
# stated the way the machine states it, by a re-dispatch: the wall's fresh `intended` row with a
# later launch, forward-copied from section B's (as `roster_identify` forward-copies), carrying
# the tool_use_id `g_confirm` completes. The ack discharges §F's id and not the re-dispatch, so
# the name is open with one live id, and the gate answers about the roster filename rather
# than about an ambiguity (or, with the whole name acked, a silent pass).
G_ACK_AT="$(date -u -v+1S +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '+1 second' +%Y-%m-%dT%H:%M:%SZ)"
G_RELAUNCH_AT="$(date -u -v+2S +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '+2 seconds' +%Y-%m-%dT%H:%M:%SZ)"
[ -f "$IREPO/.bionic/tmp/sweeper-$SID_A.state" ] \
  || printf '# bionic session sweeper ledger — schema sweeper-ledger/v1 — machine-local, safe to delete\n' \
       > "$IREPO/.bionic/tmp/sweeper-$SID_A.state"
printf 'sweeper-ledger/v1|event=ack|at=%s|epoch=0|pid=1|session=%s|name=w99-impl|by=patrol|reason=landed\n' \
  "$G_ACK_AT" "$SID_A" >> "$IREPO/.bionic/tmp/sweeper-$SID_A.state"
G_RELAUNCH_ROW="$(grep -F '|status=intended|' "$G_ROSTER" | grep -F '|name=w99-impl|' \
  | grep -F '|tool_use_id=toolu_018jyjgop7KMxP6yKtoAWWtB|' | tail -1 \
  | sed "s/|launched_at=[^|]*|/|launched_at=$G_RELAUNCH_AT|/")"
expect_contains "§G meta: the re-dispatch row was forward-copied with its later launch" \
  "launched_at=$G_RELAUNCH_AT" "$G_RELAUNCH_ROW"
printf '%s\n' "$G_RELAUNCH_ROW" >> "$G_ROSTER"

# READER 1 — the recorder's completion arm. At the canonical name a dispatch's
# `intended` row reaches `confirmed`; at any other name there is no row to
# complete and none is invented.
g_confirm() {  # -> the confirmed row, if any
  jq -n --arg s "$SID_A" --arg t "$ITR" --arg c "$IREPO" \
    '{session_id:$s, transcript_path:$t, cwd:$c, hook_event_name:"PostToolUse",
      tool_name:"Agent",
      tool_input:{description:"a dispatch", prompt:"go", subagent_type:"implementor",
                  name:"w99-impl", run_in_background:true},
      tool_response:{isAsync:true, status:"async_launched", agentId:"ag99confirm-5555555555",
                     description:"a dispatch"},
      tool_use_id:"toolu_018jyjgop7KMxP6yKtoAWWtB"}' \
    | bash "$PARTY_ER" >/dev/null 2>&1
  grep 'agent_id=ag99confirm-5555555555' "$G_ROSTER" 2>/dev/null
}
mv "$G_ROSTER" "$G_MUTANT"
g_confirm >/dev/null 2>&1
mv "$G_MUTANT" "$G_ROSTER"
expect_contains "the recorder completes the row at the canonical filename" \
  "status=confirmed" "$(g_confirm)"

# READER 2 — the observation. Its contract source is the roster; at any other
# filename the same look reports no contract at all.
g_progress_source() {
  ( cd "$IREPO" && env CLAUDE_CODE_SESSION_ID="$SID_A" bash "$OBSERVE" w99-impl 2>&1 ) \
    | grep '^stop-check-observation/' | tr '|' '\n' | grep '^progress_source=' | cut -d= -f2-
}
expect_eq "the observation takes its contract from the canonical roster" \
  "roster" "$(g_progress_source)"
mv "$G_ROSTER" "$G_MUTANT"
# At any other name the observation shows NOTHING — a stronger form of the same pin than the
# `progress_source=none` it used to print. Since S6 the roster is also where the agent id
# comes from, so a roster the reader cannot find leaves it without a working log to look at,
# and a run that shows no evidence tier prints no machine line at all.
expect_eq "…and finds no contract, and nothing else either, when the roster is named anything else" \
  "" "$(g_progress_source)"
mv "$G_MUTANT" "$G_ROSTER"

# READER 3 — the stop gate, over the same rename. With the roster at its canonical name the
# whole chain closes: the look resolves through the row, the recorder stores it and the gate
# spends it. At any other name neither party can identify the target, and the gate refuses.
# (The D-6 channel-blind refusal this leg used to drive lives in tests/stop-guard.test.sh §9,
# where a look taken BEFORE the contract was recorded is what makes a look channel-blind now
# — an observation with no session key cannot reach a live set and produces no record at all.)
g_stop_reason() {  # -> which refusal the gate reaches for an unobserved target
  local out
  rm -f "$IREPO/.bionic/tmp/stop-check.state"
  out=$(mk_stop_payload "$SID_A" "$ITR" "$IREPO" "w99-impl" | bash "$PARTY_SG" 2>&1)
  case "$out" in
    *"carries no agent id"*) echo unidentified ;;
    # IDENTIFIED IS NOW A VERDICT ABOUT THE TARGET (epic-23 wave-15, REQ-2). With the roster
    # at its canonical name the gate resolves the id and then answers on what it observes —
    # a refusal when the agent is working, a permit when it is not — and either answer is
    # the register having been found. What distinguishes this leg from the one below it is
    # that the gate got as far as having an opinion about the AGENT at all.
    *"No observation"*)      echo identified ;;
    *"still working"*)       echo identified ;;
    *"STOP ALLOWED"*)        echo identified ;;
    *"STOP PERMITTED"*)      echo identified ;;
    # T22, then D8 (T5): with the roster gone the gate has no standing over a bare name at
    # all — the register is what makes a target ours. Through 1.7.1 that was a passthrough
    # (a target it does not guard); since D8 it is a REFUSAL naming the same fact (a target
    # this gate cannot identify), one step earlier than the passthrough used to sit. Either
    # wire lands on the same label here — what moved is the verb, not the diagnosis.
    *"no roster row of this session"*) echo unrostered ;;
    *PASSTHROUGH*)           echo unrostered ;;
    *)                       echo "other" ;;
  esac
}
expect_eq "the stop gate identifies its target through the canonical roster" \
  "identified" "$(g_stop_reason)"
mv "$G_ROSTER" "$G_MUTANT"
expect_eq "…and has no standing over it at all when the roster is named anything else" \
  "unrostered" "$(g_stop_reason)"
mv "$G_MUTANT" "$G_ROSTER"

# READER 4 — the probe's roster coverage, which scans OTHER live sessions' roster
# files by the same pattern.
printf '{}\n' > "$IPROJ/$SID_B.jsonl"
G_ROSTER_B="$IREPO/.bionic/tmp/roster-$SID_B.state"
cp "$G_ROSTER" "$G_ROSTER_B"
g_probe_roster() {
  ( cd "$IREPO" && env CLAUDE_CODE_SESSION_ID="$SID_A" ANTHROPIC_API_KEY="sk-fixture-not-a-real-key" \
      HOME="$SANDBOX/home" CLAUDE_CONFIG_DIR="$CLAUDE_CONFIG_DIR" bash "$PROBE" 2>&1 ) \
    | grep -F "another live session on this project: $SID_B"
}
expect_contains "the probe finds another session's roster at the canonical filename" \
  "roster: present" "$(g_probe_roster)"
mv "$G_ROSTER_B" "$IREPO/.bionic/tmp/roster-$SID_B.txt"
expect_contains "…and reports absent for the same file under any other name" \
  "roster: absent" "$(g_probe_roster)"
rm -f "$IREPO/.bionic/tmp/roster-$SID_B.txt" "$IPROJ/$SID_B.jsonl"

# Both halves of the name, spelled by all five sites — so a rename of either half
# fails with a legible reason rather than silently halving the fleet's view.
for _party in "$PARTY_DP" "$PROBE" "$PARTY_ER" "$PARTY_SG" "$OBSERVE"; do
  _src=$(cat "$_party")
  expect_contains "$(basename "$_party") spells the roster filename prefix" "roster-" "$_src"
done

# ============================================================
section "H — the LIVENESS fields: writer lifts them, the observation displays them (6-axis A-1)"
# ============================================================
#
# The axis-3 FAIL: hooks/stop-check.sh read `claims=` off the roster row and NO
# writer emitted it, while task 4/7 shipped procedure prose instructing authors
# to declare both a `cadence` and a subprocess claim. A reader with no producer is
# dead substrate, and the only test exercising it hand-wrote a row shape the
# writer could not produce. Here the row is the one the real start gate wrote from
# a real brief, and the real observation is run over it.

H_BRIEF='Canonical-sdlc Step 4, task 4/13 of epic-99 wave-01; build · double · wave.
Expected artifact: .bionic/docs/record/w99-live.txt
Expected duration: ~45 minutes. Progress: .bionic/tmp/w99-live.progress, cadence ~7m.
Subprocess claim: `w99-suite-marker` → .bionic/tmp/w99-live.log
Exit condition: the artifact exists.
Suites: tests/widget.test.sh'
plant "$ISUB" "aw99live-9999999999999999" "w99-live"
jq -n --arg s "$SID_A" --arg c "$IREPO" --arg p "$H_BRIEF" \
  '{session_id:$s, transcript_path:"/irrelevant.jsonl", cwd:$c,
    permission_mode:"bypassPermissions", hook_event_name:"PreToolUse", tool_name:"Agent",
    tool_input:{description:"a liveness dispatch", subagent_type:"implementor",
                name:"w99-live", prompt:$p},
    tool_use_id:"toolu_01LIVENESS"}' \
  | bash "$PARTY_DP" >/dev/null 2>&1
H_ROW=$(grep 'name=w99-live' "$G_ROSTER" 2>/dev/null | tail -1)
expect_contains "the writer lifted the subprocess claim's pattern into the row" \
  "claims=w99-suite-marker" "$H_ROW"
expect_contains "the writer lifted the cadence declared beside the progress path" \
  "cadence=~7m." "$H_ROW"

# The field NAMES, both ends — a rename fails here rather than turning the
# display silently blank, which is how this defect shipped in the first place.
# THE READER MOVED INTO THE LIBRARY (epic-23 wave-15, REQ-2): one `observe_agent` reads the
# contract off the row for both the verb that prints it and the gate that decides on it.
expect_contains "the observation library reads that same key" \
  'line_field "$OBS_ROW" claims' "$(cat "$OBSERVE_LIB")"
expect_contains "the observation library reads that same key" \
  'line_field "$OBS_ROW" cadence' "$(cat "$OBSERVE_LIB")"

# ============================================================
section "I — DONE-DETECTION, and the primitives the sweeper says it copied (6-axis D-2, R-1)"
# ============================================================
#
# hooks/session-sweeper.sh's own header declares four functions "DELIBERATELY DUPLICATED
# from hooks/stop-check.sh, byte for byte… held together by the cross-gate agreement
# suite". Until this section existed that last clause was false: nothing here compared a
# single copy, so the comment named a guardrail the next reader would trust and the copies
# could drift silently (6-axis R-1). Below it is true.
#
# The heavier half is D-2. "Is this roster row's deliverable delivered?" has TWO owners and
# they answered differently on the same input. Both answers are asked here of the REAL
# scripts on ONE set of fixtures, and compared to each other rather than only to a literal —
# which is what goes red on the next divergence, whichever side moves.
#
# THE SWEEPER SIDE MOVED IN epic-16 wave-02, and this section moved with it. The sweeper
# used to answer through its watch loop: a row whose declared deliverables were all present
# was SATISFIED, dropped from watching, never woken on, and the loose `[ -s <dir> ]` reading
# behind that was the original defect (true for an EMPTY directory on both BSD and GNU, so a
# freshly-created directory read as landed work). The loop and its satisfied-check are
# deleted. The sweeper is still an owner of this question — through `verdict`, which is now
# its ONLY delivered-predicate — so the pairing is preserved and re-asked against that verb
# rather than dropped with the loop.

# --- I.1 the copied primitives ---
# BODIES are compared, not whole definitions: each file explains its copy in its own terms,
# so the signature comments legitimately differ and only the executable text must not.
# (hoisted to tests/cross-gate-agreement.prelude.sh, which part 2 reads: fn_body)

for _fn in file_mtime line_field; do
  expect_eq "the sweeper's ${_fn}() is the observation library's, body for body" \
    "$(fn_body "$OBSERVE_LIB" "$_fn")" "$(fn_body "$SWEEPER" "$_fn")"
done
# `claims_live` kept its body and lost its name: the library prefixes every function it
# exports, because a sourced file lands its names in the caller's shell and a bare
# `claims_live` there would shadow whatever else defines one. The body is the comparison.
expect_eq "the sweeper's claims_live() is the library's observe_claims_live(), body for body" \
  "$(fn_body "$OBSERVE_LIB" observe_claims_live)" "$(fn_body "$SWEEPER" claims_live)"
# Same body, different name: the sweeper normalizes its findings exactly as the stop gate
# normalizes its machine line, and says so in its comment.

# THE COPY COUNT WAS FIVE, NOT TWO (t6-review.md F-5): execution-recorder.sh's own
# line_field() sat outside this section entirely, and landing-gate.sh's own by-key reader
# was PINNED NOWHERE — it is the fifth copy and the one this wave added. Its signature is a
# genuinely different SHAPE (one argument, reading a global $LINE rather than taking the
# line as a parameter, because every candidate in its sweep loop already lives in that
# variable) — a byte comparison would be comparing apples to a legitimate shape change, so
# this half is BEHAVIOURAL: the same synthetic roster line, asked for the same key by all
# FIVE extractors (three literally named line_field, one named record_field, one shaped as
# _field), each run from ITS OWN file in its own subshell — the same precedent §N.2 uses for
# resolve_project_root — so five same-named definitions never shadow each other and the real
# pipeline is what answers, never a hand-copied stand-in.

field2_via() {  # <file> <fn-name> <line> <key> -> a <line> <key> extractor, real source, real call
  local f="$1" n="$2" line="$3" key="$4"
  ( eval "$(awk -v n="$n" '$0 ~ "^" n "\\(\\)" {f=1} f{print; if ($0=="}") exit}' "$f")"
    "$n" "$line" "$key" ) 2>/dev/null
}
field1_via() {  # <file> <line> <key> -> landing-gate.sh's ONE-argument _field(), real source
  local f="$1" line="$2" key="$3"
  ( eval "$(awk '/^_field\(\)/,/^\}/' "$f")"
    LINE="$line" _field "$key" ) 2>/dev/null
}

# DELIBERATELY NOT A ROW (and so not `roster_row_fixture`'s to build): it carries a
# `state=` key no writer emits, because what is under test is `line_field`'s by-key
# extraction, not the row. Only the schema token comes off the writer.
I1_LINE="${ROSTER_ROW_SCHEMA}|status=confirmed|name=w4-i1|agent_id=ai1test0000000000|deliverable=.bionic/docs/record/i1.md|state=UNMET"
for _key in status name agent_id deliverable state; do
  I1_WANT=$(field2_via "$SWEEPER" line_field "$I1_LINE" "$_key")
  expect_eq "…and the observation library's line_field(${_key}), called for real, agrees" \
    "$I1_WANT" "$(field2_via "$OBSERVE_LIB" line_field "$I1_LINE" "$_key")"
done

# THE DISCRIMINATING HALF: a copy of landing-gate.sh with the anchor dropped from _field()'s
# grep — the plausible drift where "asked for the FIELD" turns into an unanchored SUBSTRING
# match. A decoy field (`prev_status=`) that carries the real key as a substring is what
# makes the unanchored pattern answer wrong instead of merely reading identically anyway.
I1_MUT_DIR="$SANDBOX/fx/i1-unanchored"
mkdir -p "$I1_MUT_DIR"
anchor file payload/scripts/lib/stop.sh 'grep "^$1="'
awk '{ sub(/grep "\^\$1="/, "grep \"$1=\""); print }' "$PARTY_LG_SRC" > "$I1_MUT_DIR/stop.sh"
I1_DECOY="${ROSTER_ROW_SCHEMA}|prev_status=confirmed|status=UNMET"

# --- I.2 done-detection: one concept, two implementations, one answer ---

DREPO=$(new_repo "done-detection")
DSLUG=$(printf '%s' "$DREPO" | sed 's/[^a-zA-Z0-9]/-/g')
DPROJ="$CLAUDE_CONFIG_DIR/projects/$DSLUG"
mkdir -p "$DPROJ/$SID_A/subagents"
printf '{}\n' > "$DPROJ/$SID_A.jsonl"
plant "$DPROJ/$SID_A/subagents" "adeliv-2222222222222222" "deliv" "$DREPO"

DFX="$DREPO/deliv"
mkdir -p "$DFX/empty-dir" "$DFX/full-dir"
: > "$DFX/empty-file.md"
echo "the report"   > "$DFX/full-file.md"
echo "the report"   > "$DFX/full-dir/one.md"
echo "the report"   > "$DREPO/relative-target.md"
# An hour back, so every fixture written above is NEWER than the launch and the landing
# predicate's staleness conjunct is satisfied for all of them. Staleness is a NAMED
# divergence between these two owners (the stop gate never dates the artifact at all), and
# it is pinned separately below rather than smuggled into every row here.
D_LAUNCHED=$(date -u -v-3600S +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
  || date -u -d "-3600 seconds" +%Y-%m-%dT%H:%M:%SZ)

DROSTER="$DREPO/.bionic/tmp/roster-$SID_A.state"
mkdir -p "$DREPO/.bionic/tmp"
roster_header > "$DROSTER"
# The agent's own row, re-planted because the header write above truncates the file: since S6
# the observation takes the agent id — and therefore the working log — off this row, and every
# `d_row` below is a CONTRACT row named for its case rather than for the agent.
roster_identify "$DREPO" "$SID_A" "deliv" "adeliv-2222222222222222"
# Every contract row carries a Done marker written after its launch (wave-24 T9, D3): MET is the
# deliverable AND a completion signal, and this section compares the deliverable half only.
d_row() {  # <name> <deliverable value>
  : > "$DREPO/.bionic/tmp/$1.done"
  roster_row_fixture status=confirmed session="$SID_A" name="$1" \
    agent_id=adeliv-2222222222222222 launched_at="$D_LAUNCHED" deliverable="$2" \
    duration="1 minute" "done=$DREPO/.bionic/tmp/$1.done" tool_use_id="toolu_01$1" >> "$DROSTER"
}

# The stop gate's answer, read off the evidence it prints for a human rather than off a
# reimplementation of its branches here.
sc_answer() {  # <path as typed> -> delivered|not-delivered
  local out
  out=$( cd "$DREPO" && env CLAUDE_CODE_SESSION_ID="$SID_A" bash "$OBSERVE" deliv "$1" 2>&1 )
  case "$out" in
    *"${1} — PRESENT as a directory, 0 file(s)"*) echo not-delivered ;;
    *"${1} — PRESENT as a directory,"*)           echo delivered ;;
    *"${1} — PRESENT but EMPTY"*)                 echo not-delivered ;;
    *"${1} — PRESENT,"*)                          echo delivered ;;
    *"${1} — ABSENT"*)                            echo not-delivered ;;
    *) echo "other" ;;
  esac
}

# The sweeper's answer, read off the state its ONE surviving predicate computes. MET is
# delivered; anything else is not. The row carries no claims and no progress, so STILL-LIVE
# cannot mask a failure to deliver — the state is the predicate's answer and nothing else.
sw_answer() {  # <row name> -> delivered|not-delivered
  local st
  st=$( cd "$DREPO" && env CLAUDE_CODE_SESSION_ID="$SID_A" bash "$SWEEPER" verdict "$1" 2>/dev/null \
        | grep -F 'landing-verdict/v1|' | grep -F "|name=$1|" | head -1 \
        | tr '|' '\n' | grep '^state=' | head -1 | cut -d= -f2- )
  [ "$st" = "MET" ] && echo delivered || echo not-delivered
}

agree_on() {  # <label> <row name> <path as typed> <the right answer>
  local sc sw
  d_row "$2" "$3"
  sc=$(sc_answer "$3"); sw=$(sw_answer "$2")
  expect_eq "$1: the stop gate answers $4" "$4" "$sc"
  expect_eq "$1: the sweeper gives the stop gate's answer" "$sc" "$sw"
}

agree_on "a written file"        wfile "$DFX/full-file.md"  delivered
agree_on "an empty file"         efile "$DFX/empty-file.md" not-delivered
agree_on "an absent path"        nofile "$DFX/never.md"     not-delivered
agree_on "an EMPTY directory"    edir  "$DFX/empty-dir"     not-delivered
agree_on "a populated directory" fdir  "$DFX/full-dir"      delivered
# A repo-relative path, asked from the repo root — which is where the roster's own paths are
# written from, and the one place the two owners resolve it identically (the sweeper reads
# it against the REPO, the stop gate against the operator's typed cwd).
agree_on "a repo-relative path, asked from the repo root" relrow "relative-target.md" delivered

# THE NAMED DIVERGENCES, pinned as INEQUALITIES rather than left for the next reader to
# discover. These are the cases where the two owners are SUPPOSED to disagree, and a suite
# that only asserted agreement would go green on a drift that collapsed one into the other.
#
# SYMLINKS (Step-6 security review S-3). The stop gate follows a link on its file branch;
# the landing predicate refuses one on BOTH branches, because a contract satisfied by
# `ln -s` is satisfied with zero bytes written.
ln -s "$DFX/full-file.md" "$DFX/linked-file.md"
d_row linkrow "$DFX/linked-file.md"
expect_eq "a symlink to a written file: the stop gate reads it as delivered" \
  "delivered" "$(sc_answer "$DFX/linked-file.md")"

# STALENESS. The landing predicate requires an mtime AFTER the row's own launched_at; the
# stop gate does not date the artifact at all. Same file, same moment, two answers.
echo "written before this agent was ever dispatched" > "$DFX/prelaunch.md"
touch -t 202001010000 "$DFX/prelaunch.md"
d_row stalerow "$DFX/prelaunch.md"
expect_eq "a PRE-LAUNCH file: the stop gate reads it as delivered (it never dates it)" \
  "delivered" "$(sc_answer "$DFX/prelaunch.md")"

# ============================================================
section "J — THE LANDING CONTRACT: the gate refuses exactly when the verdict says UNMET"
# ============================================================
#
# epic-16 wave-01 split one answer across two scripts on purpose.
# hooks/session-sweeper.sh's `verdict` verb OWNS the delivered predicate (spec
# §Design ownership table); hooks/landing-gate.sh consumes it on SubagentStop and
# refuses the stop when it reads UNMET. The gate holds NO copy of the predicate —
# "a third copy of the delivered predicate in the landing gate" is a rejected
# alternative in the spec — so the property worth driving here is not whether the
# gate stats a file correctly, which it never does. It is AGREEMENT: over one
# roster and one set of artifacts, the gate refuses a stop if and only if the verb
# an orchestrator runs by hand says that contract is UNMET. Two people asking the
# same question about the same agent must not get two answers.
#
# THE ASYMMETRY IS THE SUBJECT, and both directions are asserted rather than
# assumed. §J.2 shows that only a change to the GATE can split the two answers,
# and §J.3 shows that a change to the PREDICATE moves both together. That is what
# having one owner buys operationally, and it is the claim this section keeps true.

JREPO=$(new_repo "landing-contract")
write_plan "$JREPO/.bionic/docs/plans/epic-16/wave-01.md" "current: 4"
JDELIV="$JREPO/deliv"
mkdir -p "$JDELIV" "$JREPO/.bionic/tmp"
JROSTER="$JREPO/.bionic/tmp/roster-$SID_A.state"
J_LAUNCHED=$(date -u -v-3600S +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
  || date -u -d "-3600 seconds" +%Y-%m-%dT%H:%M:%SZ)

# Roster rows in the shape hooks/dispatch-preflight.sh's `ROW=` line really writes
# TODAY — field for field, including `source=` (task 4/4) and `waiver=` (the
# absent-deliverable wall). A fixture missing a field the writer emits is how a
# suite ends up green over a row shape nothing produces; the sweeper's and the
# recorder's suites each had to make this same correction mid-wave.
#
# `agent_id=` is filled here because it is the SWEEP's join key (epic-16 wave-03, T4c): a
# row whose id is absent from the Stop payload's `background_tasks[]` has landed and is
# judged, and one still listed there is skipped. The rest of the row is the writer's own.
# Each row's agent said it was done, by its Done marker (wave-24 T9, D3): this section asks the
# deliverable half of MET, so the signal half is held true for every row.
jrow() {  # <name> <deliverable> <progress> <cadence> <waiver> [tool_use_id]
  : > "$JREPO/.bionic/tmp/$1.done"
  roster_row_fixture status=confirmed session="$SID_A" name="$1" agent_id="a-$1" \
    launched_at="$J_LAUNCHED" deliverable="$2" progress="$3" cadence="$4" waiver="$5" \
    "done=$JREPO/.bionic/tmp/$1.done" tool_use_id="${6:-toolu_01LANDING}" >> "$JROSTER"
}

roster_header > "$JROSTER"
echo "the report" > "$JDELIV/met.md"
: > "$JDELIV/empty.md"
echo "written before the agent was ever dispatched" > "$JDELIV/stale.md"
touch -t 202001010000 "$JDELIV/stale.md"
printf 'stage 1\n' > "$JREPO/.bionic/tmp/live.progress"

ln -s "$JDELIV/met.md" "$JDELIV/linked.md"

jrow met    "$JDELIV/met.md"   ""                                    ""     ""
jrow unmet  "$JDELIV/never.md" ""                                    ""     ""
jrow empty  "$JDELIV/empty.md" ""                                    ""     ""
jrow stale  "$JDELIV/stale.md" ""                                    ""     ""
jrow live   "$JDELIV/never.md" "$JREPO/.bionic/tmp/live.progress"    "~5m"  ""
# A GENUINE waiver names no artifact — the wall's own label reads "why this dispatch
# produces nothing durable" (Step-6 review S-1). The row below it is the contradictory
# shape: a declared artifact AND a waiver, which one line of quoted documentation in a
# brief used to produce, and which used to silence the contract entirely.
jrow waived ""                 ""                                    ""     "this dispatch produces nothing durable"
jrow quoter "$JDELIV/never.md" ""                                    ""     "<why this dispatch produces nothing durable>"
# The symlink half of S-3: a contract satisfied by `ln -s` is satisfied with zero bytes
# written, so the landing predicate refuses it and the gate refuses the stop.
jrow linked "$JDELIV/linked.md" ""                                   ""     ""
# C-2: two dispatches share a name, so the fold cannot tell whose contract is whose. The
# verb says AMBIGUOUS and the gate passes — a stop let through is recoverable, the wrong
# agent blocked is not.
jrow dup    "$JDELIV/met.md"   ""                                    ""     ""     toolu_01DUPA
jrow dup    "$JDELIV/never.md" ""                                    ""     ""     toolu_01DUPB

# The battery's baseline, restored before every gate call (see j_gate): the sweep is
# idempotent by design and journals a marker into this file to stay that way.
cp "$JROSTER" "$JROSTER.pristine"

j_line() {  # <name> -> the verb's machine line for that name, or empty
  ( cd "$JREPO" && env CLAUDE_CODE_SESSION_ID="$SID_A" bash "$PARTY_SW" verdict "$1" 2>/dev/null ) \
    | grep -F 'landing-verdict/v1|' | grep -F "|name=$1|" | head -1
}
j_field() {  # <line> <key>
  printf '%s' "$1" | tr '|' '\n' | grep "^$2=" | head -1 | cut -d= -f2-
}
j_verdict() {  # <name> -> the state the verb computed, or NONE when it prints no line
  local l; l=$(j_line "$1")
  if [ -z "$l" ]; then echo NONE; else j_field "$l" state; fi
}
# THE SWEEP JUDGES EVERY LANDED ROW AT ONCE, so asking it about ONE row means declaring
# every OTHER row still in flight. That is the mechanism's own vocabulary rather than a test
# seam: `background_tasks[]` is the payload's list of what is still running, and the gate
# skips exactly those. `ghost` is on no roster row, so nothing lands and nothing is judged.
J_ALL="met unmet empty stale live waived quoter linked dup"
j_live_except() {  # <name> -> every OTHER row's agent id
  local want="$1" n
  for n in $J_ALL; do [ "$n" = "$want" ] || printf 'a-%s\n' "$n"; done
}

# Globals rather than a captured echo: the refusal TEXT is asserted below, and a
# `$(…)` call would throw the stderr away.
J_ANSWER=""; J_GATE_ERR=""
j_gate() {  # <name> [stop_hook_active] -> sets J_ANSWER + J_GATE_ERR
  local st
  # THE ROSTER IS RESTORED FIRST. The sweep verdicts each landed row exactly ONCE and
  # journals a marker into the roster file to keep that promise; a battery that asked twice
  # about one row would be measuring the marker, not the agreement. Restoring is also what
  # every real session gets — a fresh roster per session.
  cp "$JROSTER.pristine" "$JROSTER"
  # shellcheck disable=SC2046
  J_GATE_ERR=$( mk_stopsweep_payload "$JREPO" "$SID_A" "${2:-false}" $(j_live_except "$1") \
                | bash "$PARTY_LG" 2>&1 >/dev/null )
  st=$?
  case "$st" in
    0) J_ANSWER=pass ;;
    2) J_ANSWER=refuse ;;
    *) J_ANSWER="other:exit-$st" ;;
  esac
}

# name|the verb's state|the gate's answer.  `ghost` is on no roster row at all —
# the phantom class the capture probe found firing three times per teammate run,
# where the verb prints nothing and the gate must not invent a contract.
J_CASES='
met|MET|pass
unmet|UNMET|refuse
empty|UNMET|refuse
stale|UNMET|refuse
waived|WAIVED|pass
quoter|UNMET|refuse
linked|UNMET|refuse
dup|AMBIGUOUS|pass
live|STILL-LIVE|pass
ghost|NONE|pass
'

run_j_battery() {  # assert|detect
  local mode="$1" name want ans v
  while IFS='|' read -r name want ans; do
    [ -n "$name" ] || continue
    v=$(j_verdict "$name"); j_gate "$name"
    if [ "$mode" = "assert" ]; then
      expect_eq "the verb computes $want for '$name'" "$want" "$v"
      expect_eq "…and the gate answers $ans, which is what $want means for a stop" \
        "$ans" "$J_ANSWER"
      # The agreement itself, computed from the verb's own answer rather than from
      # the table — so a case added to J_CASES with the wrong pairing cannot pass.
      expect_eq "…gate refuses IFF the verb says UNMET ('$name')" \
        "$([ "$v" = "UNMET" ] && echo refuse || echo pass)" "$J_ANSWER"
    else
      if [ "$v" != "$want" ]; then
        printf 'the verb moved on %s: want=%s got=%s\n' "$name" "$want" "$v"; return 1
      fi
      if [ "$J_ANSWER" != "$ans" ]; then
        printf 'gate/verb disagree on %s: verb=%s gate=%s (expected %s)\n' \
          "$name" "$v" "$J_ANSWER" "$ans"; return 1
      fi
    fi
  done <<EOF
$(printf '%s' "$J_CASES")
EOF
  return 0
}

run_j_battery assert

j_gate dup
expect_eq "a name carrying two contracts is not blocked on either of them" "pass" "$J_ANSWER"

# THE ONE DELIBERATE DIVERGENCE, pinned rather than left implicit. On re-entry the
# gate passes a contract the verb still calls UNMET — and the verb is re-run here
# rather than assumed, so this asserts a difference in AUTHORITY, not a difference
# of opinion about the disk. Blocking once is the R7 term: only the gate has a stop
# to refuse, and an agent refused twice has no way out of the loop.
j_gate unmet true
expect_eq "on re-entry (stop_hook_active true) the gate passes" "pass" "$J_ANSWER"
expect_eq "…while the verb's answer is unchanged, because the disk did not change" \
  "UNMET" "$(j_verdict unmet)"

# ============================================================
section "J.2 — only a GATE change can split the two answers (mutation goes RED)"
# ============================================================
#
# Each mutation is applied to a COPY of the gate, installed in its own directory
# beside a real sweeper — which is how bootstrap's flat `hooks/*.sh` install lets
# the gate find its sibling, and therefore the production resolution rather than a
# test seam. Every one is a plausible drift, not damage.

JMUT="$SANDBOX/landing-mutants"
J_CKSUM_BEFORE=$(shasum "$PARTY_LG" "$PARTY_LG_SRC" "$PARTY_SW" 2>/dev/null)

# NOT CALLED IN A COMMAND SUBSTITUTION (wave-35 T23): the anchors below run in THIS shell, so a red
# one counts and `finish`'s agreement row sees the call. The path comes back in J_MUTANT_PATH.
J_MUTANT_PATH=""
j_mutant() {  # <kind> -> sets J_MUTANT_PATH to a mutant gate with a sibling sweeper; returns 1 for none
  J_MUTANT_PATH=""
  # Two statements, not one: `local a=1 b="$a"` expands every word BEFORE it
  # assigns any of them, so under `set -u` the second reference is unbound.
  local kind="$1"
  local d lib
  d="$(plant_lg_tree "$JMUT/$kind")"; d="${d%/stop.sh}"
  lib="$d/../scripts/lib/stop.sh"
  cp "$PARTY_SW" "$d/session-sweeper.sh"
  case "$kind" in
    # THE LANDED/LIVE DISCRIMINATION DROPPED. `background_tasks[]` is the payload's
    # list of what is STILL RUNNING (T4b §2.2), and skipping those rows is the whole
    # of "judge it when it lands". Without the skip the sweep holds every mid-flight
    # agent to a contract it has not finished — the false-alarm direction.
    ignore-background-tasks)
      anchor file payload/scripts/lib/stop.sh 'case "$LIVE_IDS" in'
      awk '{ if (index($0, "$LIVE_IDS") > 0 && index($0, "case ") > 0) next
             print }' "$PARTY_LG_SRC" > "$lib" ;;
    # The hook process's ambient session key instead of the payload's (the gate
    # documents why at the code) — a wrong or absent roster, silently.
    ambient-session-key)
      # RE-POINTED (epic-23 wave-11-lean-spine, REQ-1f): the gate's session key is
      # `BIONIC_SID`, resolved once by `bionic_context`, so that is the variable the
      # sweeper is handed and the one this mutation strips. The `anchor` above is what
      # turned the stale literal into a loud failure rather than a byte-identical mutant.
      anchor file payload/scripts/lib/stop.sh 'CLAUDE_CODE_SESSION_ID="$BIONIC_SID" bash "$SWEEPER" verdict "$NAME"'
      awk '{ if (index($0, "CLAUDE_CODE_SESSION_ID=\"$BIONIC_SID\" bash \"$SWEEPER\" verdict \"$NAME\"") > 0) sub(/CLAUDE_CODE_SESSION_ID="[$]BIONIC_SID" /, ""); print }' \
        "$PARTY_LG_SRC" > "$lib" ;;
    # The sweeper resolves its own state directory from the working directory, so
    # dropping the cd asks the verb about whatever repo the hook happened to run in.
    no-cd-to-repo)
      anchor file payload/scripts/lib/stop.sh 'VERDICT=$( cd '
      awk '{ if (index($0, "VERDICT=$( cd ") > 0) $0 = "VERDICT=$( true"
             print }' "$PARTY_LG_SRC" > "$lib" ;;
    *) return 1 ;;
  esac
  # CONTROL FLOW, not a precondition: the three anchors above are what report a moved
  # target. This line only decides whether the caller gets a path back.
  cmp -s "$PARTY_LG_SRC" "$lib" && return 1
  J_MUTANT_PATH="$d/stop.sh"
}

for m in ignore-background-tasks ambient-session-key no-cd-to-repo; do
  if j_mutant "$m"; then mpath="$J_MUTANT_PATH"; else mpath=""; fi
  if [ -z "$mpath" ]; then
    # A mutation that matched nothing is not a passing test — it means the code
    # moved and this proof has gone vacuous.
    no "gate mutation '$m' applies to payload/scripts/lib/stop.sh" \
       "the doctored copy came out byte-identical — see the anchor row above"
    continue
  fi
  j_saved="$PARTY_LG"; PARTY_LG="$mpath"
  if jdetail=$(run_j_battery detect); then
    no "one-gate mutation '$m' makes the landing battery RED" \
       "the battery stayed green with the gate mutated — it does not discriminate"
  else
    ok "one-gate mutation '$m' makes the landing battery RED"
  fi
  PARTY_LG="$j_saved"
done

# ============================================================
section "J.3 — a PREDICATE change moves BOTH answers, never one (the single owner)"
# ============================================================
#
# The mutant sweeper below reads an EMPTY file as delivered — the `[ -s ]` defect
# §I.2 pins on the tick loop, here in the landing predicate. It is installed as the
# sibling of an UNMUTATED copy of the gate, so the only thing that changed is the
# owner of the predicate. Both answers flip together: that is not a lucky
# coincidence, it is what "the gate owns no predicate" means in operation, and it
# is the reason the two can never be caught telling different people different
# things about one contract.
JP="$(plant_hook_tree "$JMUT/predicate")"
cp "$PARTY_LG" "$JP/stop.sh"
anchor file hooks/session-sweeper.sh '[ ! -s "$p" ]'
awk '{ sub(/\[ ! -s "[$]p" \]/, "[ ! -e \"$p\" ]"); print }' "$PARTY_SW" > "$JP/session-sweeper.sh"
j_saved_lg="$PARTY_LG"; j_saved_sw="$PARTY_SW"
PARTY_LG="$JP/stop.sh"; PARTY_SW="$JP/session-sweeper.sh"
j_gate empty
expect_eq "with the predicate loosened, the verb calls the empty file delivered" \
  "MET" "$(j_verdict empty)"
expect_eq "…and the gate passes the same stop it refused a moment ago" "pass" "$J_ANSWER"
PARTY_LG="$j_saved_lg"; PARTY_SW="$j_saved_sw"

# ============================================================
section "J.4 — still-live has ONE owner now; the row that split the two is pinned"
# ============================================================
#
# "Is this row still live?" used to be computed at TWO sites in hooks/session-sweeper.sh
# that served different masters and were SUPPOSED to disagree (wave-01 Step-6 critic D-2):
#   * evaluate_row — the tick loop, a WAKE heuristic. A row that declared `claims=` opted
#     into process-liveness as its ONLY signal, so a dead claimed process was a dead-claim
#     finding full stop and progress was never consulted.
#   * row_still_live — the verdict verb, a STOP exemption. A dead claim falls THROUGH to
#     progress/cadence, so fresh progress can still answer STILL-LIVE and spare a stopping
#     agent a false UNMET.
# On a dead-claim-plus-fresh-progress row the two answered DIFFERENTLY, and this section
# pinned that inequality so neither could drift toward the other.
#
# THE TICK LOOP IS DELETED (epic-16 wave-02), so there is no second owner and no inequality
# left to pin — an equality assertion between one implementation and nothing is not a test,
# and asserting the difference persists would be asserting that deleted code still runs. What
# survives is the SURVIVOR'S HALF, driven on the identical fixture: the row shape that split
# the two owners is exactly the row shape most likely to be misjudged, and the verdict verb
# must still call it STILL-LIVE. If a future edit collapses row_still_live into the loop's
# old "a dead claim ends the question" reading, this goes red.
DLREPO=$(new_repo "still-live-divergence")
write_plan "$DLREPO/.bionic/docs/plans/epic-16/wave-01.md" "current: 4"
mkdir -p "$DLREPO/.bionic/tmp"
DL_ROSTER="$DLREPO/.bionic/tmp/roster-$SID_A.state"
DL_LAUNCHED=$(date -u -v-3600S +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
  || date -u -d "-3600 seconds" +%Y-%m-%dT%H:%M:%SZ)
# FRESH progress written now, well inside the declared cadence; a DEAD claim no live process
# carries; an ABSENT deliverable so the row has not landed and is genuinely judged.
printf 'stage 1\n' > "$DLREPO/.bionic/tmp/dl.progress"
# `-$$` is load-bearing, not decoration. This claim exists to be DEAD — the arm below asserts
# `pgrep -f` matches nothing, and hooks/stop-check.sh reads liveness the same way. `pgrep -f`
# matches on full argv, and a concurrent `tests/run.sh` running this very file carries the
# literal in its own argv, so a fixed string makes each run's shell satisfy the other run's
# "no such process" claim. The pid suffix gives every run a private literal that no sibling's
# argv can contain, which is what makes the claim's deadness a property of this run alone.
DL_CLAIM="bionic-xgate-D2-deadclaim-no-such-process-9f5c1a2b-$$"
{
  roster_header
  roster_row_fixture status=confirmed session="$SID_A" name=dl-row agent_id=adl-row-0001 \
    launched_at="$DL_LAUNCHED" deliverable=.bionic/docs/record/never-dl.md \
    progress=.bionic/tmp/dl.progress claims="$DL_CLAIM" cadence=~5m tool_use_id=toolu_DL
} > "$DL_ROSTER"
# Not vacuous: the claimed process really is dead.

DL_VERDICT=$( cd "$DLREPO" && env CLAUDE_CODE_SESSION_ID="$SID_A" bash "$PARTY_SW" verdict dl-row 2>/dev/null \
  | grep -F 'landing-verdict/v1|' | grep -F '|name=dl-row|' | head -1 \
  | tr '|' '\n' | grep '^state=' | head -1 | cut -d= -f2- )
expect_eq "the verdict verb calls the dead-claim-plus-fresh-progress row STILL-LIVE" \
  "STILL-LIVE" "$DL_VERDICT"

# The DISCRIMINATING half, and what makes the assertion above mean something: it is the
# PROGRESS that carries the row, not a blanket refusal to judge a claimed row. Stale the
# progress and the same row — same dead claim, same absent deliverable — reads UNMET.
touch -t 202001010000 "$DLREPO/.bionic/tmp/dl.progress"
DL_VERDICT_STALE=$( cd "$DLREPO" && env CLAUDE_CODE_SESSION_ID="$SID_A" bash "$PARTY_SW" verdict dl-row 2>/dev/null \
  | grep -F 'landing-verdict/v1|' | grep -F '|name=dl-row|' | head -1 \
  | tr '|' '\n' | grep '^state=' | head -1 | cut -d= -f2- )
expect_eq "…and once that progress goes stale the same row is UNMET" "UNMET" "$DL_VERDICT_STALE"

# The gate consumes exactly that, both ways round — one owner, and the stop follows it.
j_saved_lg2="$PARTY_LG"
# The sweep answers once per row, ever, so the marker it journals is cleared between the
# two halves: what is being asked twice is the PREDICATE, not the idempotency.
dl_sweep() {  # -> sets JDL_ST; echoes the refusal
  /usr/bin/grep -v '^landing-swept/' "$DL_ROSTER" > "$DL_ROSTER.tmp" 2>/dev/null
  mv "$DL_ROSTER.tmp" "$DL_ROSTER"
  mk_stopsweep_payload "$DLREPO" "$SID_A" false | bash "$PARTY_LG" 2>&1 >/dev/null
}
JDL_ERR=$(dl_sweep); JDL_ST=$?
expect_eq "the gate refuses the stop on the UNMET reading" "2" "$JDL_ST"
printf 'stage 2\n' > "$DLREPO/.bionic/tmp/dl.progress"
JDL_ERR2=$(dl_sweep); JDL_ST2=$?
expect_eq "…and passes it the moment the progress is fresh again" "0" "$JDL_ST2"
PARTY_LG="$j_saved_lg2"

# ============================================================
section "K — the IDENTITY CHAIN: intended → confirmed → identified, one contract"
# ============================================================
#
# The roster is append-only and a contract ADVANCES along it: `intended` at the
# dispatch wall, `confirmed` when the spawn returns, `identified` when the subagent
# starts (spec §1). Three rows, ONE contract — and four readers that must not
# disagree about it: the sweeper's verdict folds to the latest row per name,
# hooks/stop-check.sh and hooks/stop-guard.sh take the row by id and fall back to
# the row by name, and the recorder's own join reads the chain to extend it.
#
# The chain below is built by the REAL writers from a REAL brief — the start gate,
# then the recorder's completion arm on a teammate-shaped payload, then the
# recorder's identification arm on a SubagentStart. Nothing here is a hand-written
# row, because the defect this section exists to catch is a writer that stops
# copying a field forward, and a hand-written fixture would carry the fields the
# test author remembered rather than the ones the writer emits.

KREPO=$(new_repo "identity-chain")
KSLUG=$(printf '%s' "$KREPO" | sed 's/[^a-zA-Z0-9]/-/g')
KPROJ="$CLAUDE_CONFIG_DIR/projects/$KSLUG"
KSUB="$KPROJ/$SID_A/subagents"
KSUB_B="$KPROJ/$SID_B/subagents"
mkdir -p "$KSUB" "$KSUB_B" "$KREPO/.bionic/tmp"
KTR="$KPROJ/$SID_A.jsonl"; printf '{}\n' > "$KTR"
KTR_B="$KPROJ/$SID_B.jsonl"; printf '{}\n' > "$KTR_B"
write_live_plan "$KREPO/.bionic/docs/plans/epic-16/wave-01.md" "current: 4"
KROSTER="$KREPO/.bionic/tmp/roster-$SID_A.state"
KID="aw16chain-1234567890abcdef"

# The attestation the dispatch wall demands, as a fixture: whether the producer and
# the wall spell that key the same way is §B's subject, not this one.
{
  printf '# bionic environment attestation — machine-local, safe to delete\n'
  printf 'version=1\nkind=preflight-attestation\n'
  printf 'session_id=%s\nwritten_at=1785790000\nrepo=%s\n' "$SID_A" "$KREPO"
} > "$KREPO/.bionic/tmp/preflight-$SID_A.state"

K_BRIEF='Canonical-sdlc Step 4, task 6 of epic-16 wave-01; build · double · wave.
Expected artifact: .bionic/docs/record/w16-chain.md
Expected duration: ~30 minutes. Progress artifact: .bionic/tmp/w16-chain.progress, cadence ~7m.
Subprocess claim: `w16-chain-marker` → .bionic/tmp/w16-chain.log
Done marker: .bionic/tmp/w16-chain.done
Exit condition: the artifact exists.
Suites: tests/widget.test.sh'

# STAGE 1 — the dispatch wall writes `intended`.
mk_agent_payload "$SID_A" "$KREPO" \
  | jq --arg p "$K_BRIEF" '.tool_input.name = "w16-chain" | .tool_input.prompt = $p
                           | .tool_use_id = "toolu_01CHAIN"' \
  | bash "$PARTY_DP" >/dev/null 2>&1
K_INTENDED=$(grep 'status=intended|.*|name=w16-chain|' "$KROSTER" 2>/dev/null | tail -1)
expect_contains "the dispatch wall journalled the launch as intended" \
  "status=intended" "$K_INTENDED"
expect_contains "…carrying the deliverable the brief declared" \
  "deliverable=.bionic/docs/record/w16-chain.md" "$K_INTENDED"

# STAGE 2 — the spawn returns; the recorder completes the row to `confirmed`. The
# ASYNC shape, which is the one the id join spans end to end: `tool_response.agentId`
# here is the same string SubagentStart carries below and the same string the landing
# sweep matches against `background_tasks[].id` (t4b-probe-report.md §4). The TEAMMATE
# shape — addressing id recorded, `agent_id=` deliberately left empty, and therefore
# never identified — is pinned in tests/execution-recorder.test.sh Section 10.
mk_agent_post "$SID_A" "$KTR" "$KREPO" "toolu_01CHAIN" "w16-chain" "$KID" \
  | bash "$PARTY_ER" >/dev/null 2>&1
K_CONFIRMED=$(grep 'status=confirmed|.*|name=w16-chain|' "$KROSTER" 2>/dev/null | tail -1)
expect_contains "the spawn's completion advances the row to confirmed" \
  "status=confirmed" "$K_CONFIRMED"
expect_contains "…recording the transcript-form id the join needs" \
  "agent_id=$KID" "$K_CONFIRMED"

# STAGE 3 — the subagent starts; the recorder joins BY THAT ID and writes `identified`.
mk_start_payload "$SID_A" "$KTR" "$KREPO" "w16-chain" "$KID" | bash "$PARTY_ER" >/dev/null 2>&1
K_IDENTIFIED=$(grep 'status=identified|.*|name=w16-chain|' "$KROSTER" 2>/dev/null | tail -1)
expect_contains "the start advances the row to identified" "status=identified" "$K_IDENTIFIED"
expect_contains "…carrying the transcript-form id" "agent_id=$KID" "$K_IDENTIFIED"
expect_eq "the chain is three rows for one name, in order" "intended confirmed identified" \
  "$(grep '|name=w16-chain|' "$KROSTER" 2>/dev/null | tr '|' '\n' | grep '^status=' | cut -d= -f2 | tr '\n' ' ' | sed 's/ $//')"

# --- K.1 the chain invariant: every contract field survives every advance ---
#
# "Every field copied forward" is the recorder's own claim, and it is load-bearing
# rather than tidy: the verdict folds to the LATEST row per name and reads the whole
# contract — deliverable, launch clock, progress path, cadence, claims, waiver — off
# that row alone. A row that dropped a field would not merely be terse; it would
# silently RETRACT the contract it inherited, and the verdict would then call it MET
# for naming nothing. Compared generically, so a field added later is covered by this
# test the day it is added rather than the day someone remembers to list it.
k_contract_fields() {  # <row> -> the fields that must not change, one per line
  # The stop guard's verdict (`reason=`, wave-31 T32) rides a copied row and is not a contract field.
  printf '%s' "$1" | tr '|' '\n' \
    | grep -v '^roster-state/' | grep -v '^status=' | grep -v '^agent_id=' \
    | grep -v '^teammate_id=' | grep -v '^reason='
}
expect_eq "every contract field survives intended → confirmed" \
  "$(k_contract_fields "$K_INTENDED")" "$(k_contract_fields "$K_CONFIRMED")"

# --- K.2 the four readers, one row, one contract ---
plant "$KSUB" "$KID" "w16-chain"

# READER 1 — the sweeper's verdict. ONE line for the name, not three: a gate handed
# a line per roster row would have to guess which to believe. Taken BEFORE the
# progress artifact exists, because a progress file inside its declared cadence is
# STILL-LIVE by design and this reader is being asked about the deliverable.
K_VERDICT=$( cd "$KREPO" && env CLAUDE_CODE_SESSION_ID="$SID_A" bash "$PARTY_SW" verdict w16-chain 2>/dev/null )
expect_eq "the verdict prints exactly ONE line for a three-row chain" "1" \
  "$(printf '%s\n' "$K_VERDICT" | grep -cF 'landing-verdict/v1|')"
K_VLINE=$(printf '%s\n' "$K_VERDICT" | grep -F 'landing-verdict/v1|' | head -1)
# STILL-LIVE, and asserted rather than engineered away: this chain is seconds old
# and its brief declared a ~7m cadence, so an agent that has not written anything
# yet is visibly in flight, not in breach. What matters here is that the verb read
# the CONTRACT off the chain at all — it names the outstanding artifact either way.
expect_eq "…and it reads the contract off the chain, not off nothing" "STILL-LIVE" \
  "$(j_field "$K_VLINE" state)"

# The paired positive (AC-4's absence-readback rule): the same chain, the same verb,
# with the artifact on disk. Its mtime is set past the row's launched_at, because the delivered
# predicate is mtime > launched_at and the row was written this second.
mkdir -p "$KREPO/.bionic/docs/record"
echo "the task report" > "$KREPO/.bionic/docs/record/w16-chain.md"; mtime_after "$KREPO/.bionic/docs/record/w16-chain.md"
# …and the agent says it is done, through the Done marker its brief declared (wave-24 T9, D3):
# the lift carried it to the launch row, and every row of the chain copied it forward.
: > "$KREPO/.bionic/tmp/w16-chain.done"; mtime_after "$KREPO/.bionic/tmp/w16-chain.done"
expect_contains "…the chain carries the brief's Done marker to its latest row (T9)" \
  "|done=.bionic/tmp/w16-chain.done|" "$(grep '|name=w16-chain|' "$KROSTER" | tail -1)"
K_VERDICT=$( cd "$KREPO" && env CLAUDE_CODE_SESSION_ID="$SID_A" bash "$PARTY_SW" verdict w16-chain 2>/dev/null )
K_VLINE=$(printf '%s\n' "$K_VERDICT" | grep -F 'landing-verdict/v1|' | head -1)
expect_eq "…and the same chain reads MET once the artifact lands" "MET" \
  "$(j_field "$K_VLINE" state)"

# READER 2 — the observation. Same chain, same contract, reached by its own means:
# it takes no payload, so it finds the roster by slugifying its own cwd.
printf 'stage 1\n' > "$KREPO/.bionic/tmp/w16-chain.progress"
K_OBS=$( cd "$KREPO" && env CLAUDE_CODE_SESSION_ID="$SID_A" bash "$OBSERVE" w16-chain 2>&1 )
K_MLINE=$(printf '%s\n' "$K_OBS" | grep '^stop-check-observation/')
expect_contains "…naming the roster as where that contract came from" \
  "deliverable_source=roster" "$K_MLINE"
expect_contains "…and the same progress path" "progress=.bionic/tmp/w16-chain.progress" "$K_MLINE"
expect_contains "…from the same source" "progress_source=roster" "$K_MLINE"

# THE READERS COMPARED TO EACH OTHER, not each to a literal — which is what goes red
# when either one starts resolving a different row of the chain. The observation's
# machine line renders each deliverable as `<state>:<path>`, so the state is stripped
# before the paths are compared; the STATE itself is asserted separately, because
# both readers must also agree the artifact is not there.
k_sw_path() {  # the path the VERB says the contract names, whatever state it reports
  j_field "$K_VLINE" detail \
    | grep -oE '(missing|delivered|empty)=[^ ;]+' | head -1 | cut -d= -f2-
}   # `;` ends a conjunct: the detail joins them with "; " (a MET row adds `said=…`, T9)
K_SC_DELIV=$(printf '%s' "$K_MLINE" | tr '|' '\n' | grep '^deliverables=' | head -1 | cut -d= -f2-)
expect_eq "the verb and the observation name the same deliverable" \
  "$(k_sw_path)" "${K_SC_DELIV#*:}"
expect_eq "…and agree it is on disk" "present" "${K_SC_DELIV%%:*}"
expect_eq "…and it is the value on the row the writer wrote" \
  "$(printf '%s' "$K_IDENTIFIED" | tr '|' '\n' | grep '^deliverable=' | head -1 | cut -d= -f2-)" \
  "$(k_sw_path)"

# READER 3 — the stop gate, over the D-6 channel the chain contracted. The refusal
# is sourced from the roster row this gate resolved, so it names the path the START
# gate lifted out of the brief three rows ago.
mk_bash_post "$SID_A" "$KTR" "$KREPO" "bash ~/.claude/hooks/stop-check.sh w16-chain" "$K_OBS" \
  | bash "$PARTY_ER" >/dev/null 2>&1
printf 'stage 2\n' >> "$KREPO/.bionic/tmp/w16-chain.progress"; mtime_after "$KREPO/.bionic/tmp/w16-chain.progress"
# THE CONTRACT IS TAKEN BACK OFF DISK FIRST (epic-16 wave-02 task S3). D-6 is a rule about
# a stop that would end UNFINISHED work: since this wave, a LANDED contract discharges the
# stop outright and no channel is consulted, which is AC-1 and is asserted as the paired
# half below. Reader 3's question — does the chain carry the progress path all the way to
# the gate's refusal — is only askable while the contract is outstanding, so the artifact
# reader 1 delivered is moved aside for it and restored immediately after. Same chain, same
# roster, same gate; the only thing that varies is the one fact that decides.
mv "$KREPO/.bionic/docs/record/w16-chain.md" "$SANDBOX/k-chain-artifact.md"
K_SG_OUT=$(mk_stop_payload "$SID_A" "$KTR" "$KREPO" "w16-chain" | bash "$PARTY_SG" 2>&1); K_SG_ST=$?
expect_eq "the stop gate judges alive a target whose contracted channel moved under the look (wave-31 T32: allowed, its verdict recorded as reason=)" \
  "0" "$K_SG_ST"
expect_contains "…saying so" "is ALIVE and its contract is undelivered" "$K_SG_OUT"

# THE OTHER DIRECTION, one fact apart: the artifact comes back, the verdict says MET, and
# the identical stop — same stale observation, same moved progress channel — passes with no
# ceremony at all. This is AC-1 read across the gates rather than inside one: the fact that
# discharges the stop is the same fact the verb reports and the operator can see.
mv "$SANDBOX/k-chain-artifact.md" "$KREPO/.bionic/docs/record/w16-chain.md"
K_SG_OUT=$(mk_stop_payload "$SID_A" "$KTR" "$KREPO" "w16-chain" | bash "$PARTY_SG" 2>&1); K_SG_ST=$?
expect_eq "…and once the contract has landed, the same stop passes with no ceremony" \
  "0" "$K_SG_ST"
expect_eq "…silently — nothing is demanded of a stop the disk already answers for" \
  "" "$K_SG_OUT"

# READER 4 — the recorder's own join. A SECOND start for the SAME agent (the resume
# shape) re-joins the `confirmed` row rather than chaining off its own output — states
# advance, and a repeated start must not compound a field loss — and the row it writes
# still carries the original dispatch's tool_use_id, which is the proof it joined the
# chain rather than starting a new one. The id is the key, so a start for a DIFFERENT
# id is a different agent and joins nothing here.
mk_start_payload "$SID_A" "$KTR" "$KREPO" "w16-chain" "$KID" \
  | bash "$PARTY_ER" >/dev/null 2>&1
K_IDENT2=$(grep 'status=identified|.*|name=w16-chain|' "$KROSTER" 2>/dev/null | tail -1)
# RE-POINTED (T22). A second start for an id whose LAST row is already `identified` is a
# resumed copy, not a state advance, and the recorder journals it `duplicate-start` instead
# of identifying it twice. The chain claim survives whole — the row it writes still carries
# the id it joined on, the original dispatch tool_use_id and every contract field — and the
# row that used to prove it is the duplicate row itself.
K_DUP=$(grep 'status=duplicate-start|.*|name=w16-chain|' "$KROSTER" 2>/dev/null | tail -1)
# The stop guard's verdict above appended a copy of the identified row carrying reason= (wave-31
# T32), which is the guard's journal, not the recorder's: the count is of the recorder's rows.
expect_eq "a second start does NOT write a second identified row" \
  "1" "$(grep 'status=identified|.*|name=w16-chain|' "$KROSTER" 2>/dev/null | grep -vc '|reason=' | tr -d ' ')"
expect_eq "…it journals the duplicate start instead" \
  "1" "$(grep -c 'status=duplicate-start|.*|name=w16-chain|' "$KROSTER" 2>/dev/null | tr -d ' ')"
K_IDENT2="$K_DUP"
expect_contains "…carrying the id it joined on" "agent_id=$KID" "$K_IDENT2"
expect_contains "…still carrying the original dispatch's tool_use_id" \
  "tool_use_id=toolu_01CHAIN" "$K_IDENT2"
expect_eq "…and the same contract as every row before it" \
  "$(k_contract_fields "$K_INTENDED")" "$(k_contract_fields "$K_IDENT2")"

# --- K.3 the identified row is what makes the by-id walls reachable (paired) ---
#
# R4's whole point, re-aimed at what actually supplies the key (epic-16 wave-03). The
# by-id walls can only vouch for an agent whose TRANSCRIPT-form id is on the roster;
# a row that carries no such id is a row no by-id reader can satisfy. On an async
# dispatch the roster arm supplies it at confirmation and the identification arm
# re-states it; on a TEAMMATE dispatch neither does — `agent_id=` is deliberately
# empty because the launch response carries only the addressing form, and since the
# identification join is by id there is nothing to join with. That gap is real and
# named in hooks/execution-recorder.sh; what is pinned HERE is the consequence, over
# ONE roster, in the one shape where the answer is observable: the agent's metadata
# filed under ANOTHER session's directory, where only the roster can vouch for it.
# The negative half strips the transcript id from every row and nothing else.
# The agent MOVES rather than being copied: the same id filed under two session
# directories of one project is the AMBIGUOUS case (§C2), which would answer this
# question with "the operator was shown a candidate list" instead of with the
# ownership rule under test.
mkdir -p "$SANDBOX/k-own-meta"
mv "$KSUB/agent-$KID.meta.json" "$KSUB/agent-$KID.jsonl" "$SANDBOX/k-own-meta/"
plant "$KSUB_B" "$KID" "w16-chain" "$KREPO"
K_ROSTER_NOID="$SANDBOX/k-roster-without-identified.state"
grep -v 'status=identified' "$KROSTER" | sed -e "s/|agent_id=$KID|/|agent_id=|/" > "$K_ROSTER_NOID"
K_ROSTER_FULL="$SANDBOX/k-roster-full.state"
cp "$KROSTER" "$K_ROSTER_FULL"

k_observation_says() {  # -> the classification of the cross-session agent
  local out
  out=$( cd "$KREPO" && env CLAUDE_CODE_SESSION_ID="$SID_A" bash "$OBSERVE" "$KID" 2>&1 )
  case "$out" in
    *"Classification: OURS"*)         echo ours ;;
    *"Classification: FOREIGN"*)      echo foreign ;;
    *"Classification: DEAD HISTORY"*) echo dead ;;
    *) echo "other" ;;
  esac
}
# The stop is BY NAME, which is the only shape the foreign wall guards: a by-id
# stop is the documented escape hatch (an id is unambiguous by construction), so
# asking by id would answer a different question. The payload's session key and its
# transcript path DISAGREE — the gate's own comment names that as the one way a
# cross-session target reaches it — and the observation/record pair runs first,
# because the record wall sits behind the foreign one and an unrecorded look would
# refuse both halves for the same uninteresting reason.
k_stop_gate_says() {  # -> foreign | ours
  local out
  rm -f "$KREPO/.bionic/tmp/stop-check.state"
  out=$( cd "$KREPO" && env CLAUDE_CODE_SESSION_ID="$SID_A" bash "$OBSERVE" "$KID" 2>&1 )
  mk_bash_post "$SID_A" "$KTR_B" "$KREPO" "bash ~/.claude/hooks/stop-check.sh $KID" "$out" \
    | bash "$PARTY_ER" >/dev/null 2>&1
  out=$(mk_stop_payload "$SID_A" "$KTR_B" "$KREPO" "w16-chain" | bash "$PARTY_SG" 2>&1)
  case "$out" in
    # One refusal replaces the other: the gate no longer asks whose DIRECTORY the metadata
    # sits in, it asks whether this session's roster names an id for the target. Both are the
    # same row flipping, which is what this section pins.
    *"carries no agent id"*) echo foreign ;;
    *"is not live"*)         echo foreign ;;
    *) echo ours ;;
  esac
}
expect_eq "with the identified row, the observation vouches for a cross-session agent" \
  "ours" "$(k_observation_says)"
expect_eq "…and the stop gate's foreign wall stands down over the same row" \
  "ours" "$(k_stop_gate_says)"
cp "$K_ROSTER_NOID" "$KROSTER"
# Without the transcript id anywhere on the roster there is no working log either reader can
# name — the id is what it is filed under — so both refuse, and they refuse on the same row.
# The verdict used to be `foreign`, an answer about which session's DIRECTORY held the
# metadata; the row's job in the chain is unchanged, only what depends on it is narrower.
expect_eq "without the transcript id anywhere on the roster, the observation shows nothing" \
  "other" "$(k_observation_says)"
# The GATE's half needs one more thing said out loud than it used to. A LANDED contract
# discharges a stop before the gate ever asks where the working log is (epic-16 wave-02 R2),
# and the row under test here has one — so the id gap is invisible on that path, correctly.
# Strip the declared deliverable and nothing discharges any more; the gate then reaches the
# question the row answers, and refuses because no id on it can name a log to look at.
K_ROSTER_NOID_NOCONTRACT="$SANDBOX/k-roster-noid-nocontract.state"
sed 's/|deliverable=[^|]*|/|deliverable=|/' "$K_ROSTER_NOID" > "$K_ROSTER_NOID_NOCONTRACT"
cp "$K_ROSTER_NOID_NOCONTRACT" "$KROSTER"
expect_eq "…and the stop gate refuses it, both readers flipping on the same row" \
  "foreign" "$(k_stop_gate_says)"
cp "$K_ROSTER_FULL" "$KROSTER"

# --- K.4 a forward-copy that drops a field goes RED here ---
#
# The mutation is the plausible one: an identification arm that writes a fresh row
# instead of copying the joined row forward. It is applied to a COPY of the recorder
# and driven over a SECOND chain, so the chain above is untouched.
KMUT="$(plant_hook_tree "$SANDBOX/recorder-mutant")/execution-recorder.sh"
anchor file hooks/execution-recorder.sh 'if (f ~ /^status=/)   f = "status=confirmed"'
anchor file hooks/execution-recorder.sh 'if (f ~ /^status=/) f = "status=duplicate-start"'
anchor file hooks/execution-recorder.sh 'if (f ~ /^status=/)   f = "status=identified"'
awk '{ print; if (index($0, "if (f ~ /^status=/)   f = \"status=confirmed\"") || index($0, "if (f ~ /^status=/) f = \"status=duplicate-start\"") || index($0, "if (f ~ /^status=/)   f = \"status=identified\"")) print "      if (f ~ /^deliverable=/) f = \"deliverable=\"" }' \
  "$PARTY_ER" > "$KMUT"
if cmp -s "$PARTY_ER" "$KMUT"; then
  :
else
  mk_agent_payload "$SID_A" "$KREPO" \
    | jq --arg p "$K_BRIEF" '.tool_input.name = "w16-mut" | .tool_input.prompt = $p
                             | .tool_use_id = "toolu_01MUT"' \
    | bash "$PARTY_DP" >/dev/null 2>&1
  mk_agent_post "$SID_A" "$KTR" "$KREPO" "toolu_01MUT" "w16-mut" "aw16mut-1111111111111111" \
    | bash "$KMUT" >/dev/null 2>&1
  mk_start_payload "$SID_A" "$KTR" "$KREPO" "w16-mut" "aw16mut-1111111111111111" \
    | bash "$KMUT" >/dev/null 2>&1
  K_MUT_INTENDED=$(grep 'status=intended|.*|name=w16-mut|' "$KROSTER" 2>/dev/null | tail -1)
  K_MUT_IDENT=$(grep 'status=identified|.*|name=w16-mut|' "$KROSTER" 2>/dev/null | tail -1)
  if [ "$(k_contract_fields "$K_MUT_INTENDED")" = "$(k_contract_fields "$K_MUT_IDENT")" ]; then
    no "a dropped forward-copy makes the chain invariant RED" \
       "the invariant stayed green with the recorder mutated — it does not discriminate"
  else
    ok "a dropped forward-copy makes the chain invariant RED"
  fi
  # The mutant agent says it is done too (wave-24 T9, D3): its Done marker is dated past its
  # launch, so the one thing this verdict varies is the contract the mutation retracted.
  touch -t "$(date -v+60S +%Y%m%d%H%M.%S 2>/dev/null || date -d '+60 seconds' +%Y%m%d%H%M.%S)" \
    "$KREPO/.bionic/tmp/w16-chain.done"
  # …and the consequence the invariant is a proxy for: the contract is RETRACTED.
  # The verdict now calls a row MET for naming nothing, which is the false clean
  # answer the landing gate would pass a stopping agent on.
  expect_eq "…and the verdict then calls the retracted contract MET, vacuously" "MET" \
    "$( cd "$KREPO" && env CLAUDE_CODE_SESSION_ID="$SID_A" bash "$PARTY_SW" verdict w16-mut 2>/dev/null \
        | grep -F 'landing-verdict/v1|' | head -1 | tr '|' '\n' | grep '^state=' | cut -d= -f2- )"
fi

# ============================================================
# ============================================================
section "L — the WIRING: one hook, one registration, one manifest"
# ============================================================
#
# A hook that reads an event nobody registered it for is inert, and inert in the
# quietest possible way: it is installed, it is syntactically fine, its own suite is
# green, and it never runs.
#
# THERE IS ONE REGISTRATION SURFACE NOW (bionic 1.4.0, task ADOPT, spec AC-7):
# hooks/hooks.json. Until this wave there were two, and the split was not laziness —
# it was a partition. Skill-frontmatter hooks bind only in sessions that invoke the
# skill, which is what kept the sdlc walls off every unrelated project on the machine;
# settings-channel hooks are the only ones an AGENT-context event can reach, which is
# what got the same walls into teammate contexts. Three hooks were therefore registered
# on both channels, each entry covering the half the other could not.
#
# THE PARTITION IS WHAT BROKE. A skill's registrations are looked up per session, so a
# `/clear`, a continue or a `/reload-plugins` left every wall installed and not running
# — silently, while dispatches kept launching unrostered. The scope the frontmatter was
# buying is now bought by an ON-DISK fact instead: each hook asks `active_run` under the
# payload's project root and does nothing where there is no run. That is a better
# partition than the channel ever was, because it survives the conversation.
#
# THE THREE WAYS THIS CAN STILL BE SILENTLY WRONG, one assertion each below: the
# frontmatter could keep an entry (the hook then fires TWICE per event — the CLI does
# not deduplicate across the plugin/skill boundary), a hook could be missing from the
# manifest (inert), or a hook could be named twice within it (two refusals, two journal
# rows for one dispatch).
SKILL_SRC="$BIONIC_SKILLS_DIR/canonical-sdlc/SKILL.md"
HOOKS_JSON_SRC="$BIONIC_HOOKS_DIR/hooks.json"

# the shell's bare `grep` is ugrep with ignore-files active and lies about absence
# (reports 0 hits inside paths it silently skips) — every absence check below goes
# through /usr/bin/grep instead.
expect_absent_ug() {
  if /usr/bin/grep -qF -- "$2" <<<"$3"; then no "$1" "unexpectedly present: $2"; else ok "$1"; fi
}

# --- L.1 THE FRONTMATTER REGISTERS NOTHING ---
#
# Not "registers less" — nothing. The `hooks:` key is gone from SKILL.md's frontmatter
# entirely, and that is the half of the change that makes the other half safe: a hook
# named in both manifests fires twice per event, which for the landing sweep means two
# markers journalled per turn and for a wall means one refusal printed twice. The
# avoidance pattern this replaces is documented in the shipped file's own history —
# landing-gate was deliberately split across Stop (skill) and SubagentStop (settings)
# precisely so it would never be registered twice on one event.
SKILL_HOOKS_ROWS=$(skill_hooks_rows "$SKILL_SRC")
expect_eq "SKILL.md's frontmatter registers NOTHING — the hooks: block is gone" \
  "" "$SKILL_HOOKS_ROWS"
expect_eq "…and the key itself is absent, not merely empty" "0" \
  "$(awk 'NR==1 && $0=="---" {f=1; next} f && $0=="---" {exit} f' "$SKILL_SRC" \
     | /usr/bin/grep -c '^hooks:')"
# ANTI-VACUITY. An empty row set is what a BROKEN extractor also produces, so the
# extractor is proved against a fixture that does carry a block.
L1_FIX="$SANDBOX/fx-skill-with-hooks.md"
cat > "$L1_FIX" <<'L1EOF'
---
name: fixture
hooks:
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: ${CLAUDE_PLUGIN_ROOT}/hooks/x.sh
          timeout: 10
---
body
L1EOF
expect_contains "…and the extractor can still find one when there IS one (not vacuous)" \
  'PreToolUse|Bash|${CLAUDE_PLUGIN_ROOT}/hooks/x.sh|10' "$(skill_hooks_rows "$L1_FIX")"

# THE ALWAYS-ON MANIFEST, flattened to event|matcher|command|timeout rows. The plugin
# format makes both `matcher` and `timeout` optional, and an absent key yields an empty
# field rather than a missing column, so a row is always four fields wide.
HOOKS_JSON_ROWS=$(jq -r '
  .hooks | to_entries[] | .key as $ev | .value[]
  | (.matcher // "") as $mt
  | .hooks[] | "\($ev)|\($mt)|\(.command)|\(.timeout // "")"
' "$HOOKS_JSON_SRC" 2>/dev/null)

# --- L.2 EVERY HOOK ON THE SPINE IS REGISTERED, ON THE EVENTS IT READS ---
#
# Pinned BY VALUE including the ${CLAUDE_PLUGIN_ROOT} spelling, because the manifest is
# what the harness executes: a command that reverted to a machine-local ~ path is a wall
# that cannot resolve inside an installed plugin, and it fails in the quiet direction.
#
# THE GOVERNING SKILL IS REGISTERED THREE TIMES, ON TWO EVENTS, AND THE THIRD IS NOT A
# DUPLICATE (wave-session-bound-run S4, AC-9). Its PreToolUse|Write and PreToolUse|Edit rows
# are the wall; its PostToolUse|Write row is the bind arm, which cannot live on PreToolUse
# because the fact it needs — that this Write CREATED a plan file rather than updating one —
# is only in the tool_response. One hook file, three registrations, three distinct
# event+matcher pairs, which is what §L.3 below checks it against.
#
# ENGAGE.SH IS THE ONE ROW WITH AN EMPTY MATCHER BY CHOICE RATHER THAN BY EVENT SHAPE
# (task-engaged-session, T1). UserPromptExpansion does support a matcher, on the command
# name — the docs' own matcher table says so — but the exact spelling `command_name`
# carries for a plugin-qualified typed command (with the leading slash? without?) was
# measured only from the CLI binary, never from a live payload. A matcher that misses is a
# trigger that never fires and a session that stays unengaged forever, so the name is
# filtered INSIDE the hook, where both spellings and the leading slash are all accepted and
# tests/engage.test.sh drives each one.
# THE BASH EVENT IS ONE ROW (epic-23 wave-11-lean-spine, T23; AC-1f.5). Five command
# objects stood here — protect-main, protect-database, the evidence gate, farm-out-reminder
# and background-suite-guard behind its guard — each starting a process on every Bash tool
# call. They are functions of payload/scripts/lib/walls.sh now, composed by
# `bionic_fold`, behind the single `hooks/bash-walls.sh` row below.
L2_EXPECTED='
PreToolUse|Bash|${CLAUDE_PLUGIN_ROOT}/hooks/bash-walls.sh|10
PreToolUse|TaskStop|${CLAUDE_PLUGIN_ROOT}/hooks/stop-guard.sh|10
PreToolUse|Agent|${CLAUDE_PLUGIN_ROOT}/hooks/dispatch-preflight.sh|25
PreToolUse|Write|Edit|${CLAUDE_PLUGIN_ROOT}/hooks/canonical-sdlc-governing-skill.sh|10
PostToolUse|Write|${CLAUDE_PLUGIN_ROOT}/hooks/canonical-sdlc-governing-skill.sh|10
PostToolUse|Bash|Agent|${CLAUDE_PLUGIN_ROOT}/hooks/execution-recorder.sh|10
PostToolUse|*|${CLAUDE_PLUGIN_ROOT}/hooks/ruling-push.sh|10
SubagentStart||${CLAUDE_PLUGIN_ROOT}/hooks/execution-recorder.sh|10
SubagentStart||${CLAUDE_PLUGIN_ROOT}/hooks/execution-recorder.sh evidence|10
SubagentStart||${CLAUDE_PLUGIN_ROOT}/hooks/execution-recorder.sh adversarial|10
SubagentStart||${CLAUDE_PLUGIN_ROOT}/hooks/execution-recorder.sh structure|10
SubagentStart||${CLAUDE_PLUGIN_ROOT}/hooks/execution-recorder.sh severity|10
Stop||${CLAUDE_PLUGIN_ROOT}/hooks/stop.sh|10
PreToolUse|Skill|${CLAUDE_PLUGIN_ROOT}/hooks/engage.sh|10
UserPromptExpansion||${CLAUDE_PLUGIN_ROOT}/hooks/engage.sh|10
PermissionRequest||${CLAUDE_PLUGIN_ROOT}/hooks/permission-answer.sh|10
'
while IFS= read -r _row; do
  [ -n "$_row" ] || continue
  expect_contains "the manifest registers ${_row%%|*} $(printf '%s' "$_row" | cut -d'|' -f3 | sed 's|.*/||')" \
    "$_row" "$HOOKS_JSON_ROWS"
done <<L2EOF
$L2_EXPECTED
L2EOF
# THE CARRIER IS ON PermissionRequest AND NOWHERE ELSE (wave-25 T4; AC-5.2, spec D1). The
# question it answers is asked only when the platform would show a dialog; registered on
# PreToolUse too it would judge calls that run with no dialog, and a call that would have run
# unasked must run unchanged. Every row naming the file is read, so a second
# registration on any event fails here, not only a PreToolUse one.
expect_eq "the permission carrier is registered exactly once, on PermissionRequest only, timeout 10" \
  'PermissionRequest||${CLAUDE_PLUGIN_ROOT}/hooks/permission-answer.sh|10' \
  "$(printf '%s\n' "$HOOKS_JSON_ROWS" | /usr/bin/grep -F '/hooks/permission-answer.sh')"

# --- L.3 EXACTLY ONCE PER (hook, event, matcher) ---
#
# The CLI does not deduplicate. A hook named twice on one event refuses twice, journals
# twice, or sweeps twice — which is why the two-channel arrangement this replaces went
# to such lengths to keep landing-gate's two registrations on DIFFERENT events.
# THE COMMAND IS THE SECOND-TO-LAST FIELD, never the third — the same reason §L.4b reads
# the timeout as the last field. `startup|clear|resume|compact` is a matcher that contains
# the row delimiter, so a positional read counted from the left lands mid-matcher on that
# row and the SessionStart detector would drop out of this check entirely.
L3_DUPES=$(printf '%s\n' "$HOOKS_JSON_ROWS" \
  | awk -F'|' '{ n=split($(NF-1), parts, "/"); print $1 "|" $2 "|" parts[n] }' \
  | sort | uniq -d)
expect_eq "no hook is registered twice on one event+matcher" "" "$L3_DUPES"
# The exact-set claim, over the rows this section names. Two entries are counted elsewhere
# and excluded here by name rather than by accident: the two guarded pairs belong to §L.5,
# and the SessionStart detector to §L.8, which pins its whole row by value.
expect_eq "…and the manifest carries exactly the rows this section names, and no others" \
  "$(printf '%s' "$L2_EXPECTED" | /usr/bin/grep -c '|')" \
  "$(printf '%s\n' "$HOOKS_JSON_ROWS" \
     | /usr/bin/grep -vc -e 'agent-context-guard\.sh' -e 'session-start\.sh')"

# --- L.4 EVERY registration is bounded by a timeout ---
#
# The Step-6 review's C-4: a registration with no ceiling leaves the platform default in
# front of a gate's verdict subprocess. A timeout is the safe direction here precisely
# because these gates fail open — a hook that is killed lets the turn through. Asserted
# structurally over the parsed JSON rather than over the flattened text, so a leaf
# missing its `timeout` key fails a presence count taken over ALL leaves.
L4_HJ_TOTAL=$(jq '[.hooks | to_entries[] | .value[] | .hooks[]] | length' "$HOOKS_JSON_SRC")
L4_HJ_TIMED=$(jq '[.hooks | to_entries[] | .value[] | .hooks[] | select(has("timeout"))] | length' "$HOOKS_JSON_SRC")
expect_eq "the manifest: EVERY hook entry carries a timeout key — none unbounded" \
  "$L4_HJ_TOTAL" "$L4_HJ_TIMED"
# TEN IS THE CEILING FOR EVERY HOOK BUT ONE (wave-14 T35, ledger D1; wave-30 T35). The dispatch
# wall is registered at 25 because its own inner bound is 20 and an inner bound must sit
# STRICTLY under its registration or it can never fire (§L.4c below, which pins its deadline
# against the registration). The exception is named here by the hook it belongs to rather
# than counted away, so a SECOND hook drifting off the ceiling fails this row.
expect_eq "…each bounded by the ceiling the Step-6 review demanded: 10, the dispatch wall excepted" "0" \
  "$(jq '[.hooks | to_entries[] | .value[] | .hooks[]
         | select(.timeout != 10)
         | select((.command | test("/dispatch-preflight\\.sh( |$)")) | not)] | length' "$HOOKS_JSON_SRC")"
expect_eq "…and the one exception is the dispatch wall, at 25, so its 20s bound can fire before the CLI kills the hook" "25" \
  "$(jq -r '[.hooks | to_entries[] | .value[] | .hooks[]
            | select(.command | test("/dispatch-preflight\\.sh( |$)")) | .timeout] | unique | .[]' "$HOOKS_JSON_SRC")"

# --- L.5 THE GUARD SURVIVES WHERE ITS PURPOSE SURVIVES ---
#
# --- L.4b THE TIMEOUT IS THE LAST FIELD, NEVER THE FOURTH ---
#
# $NF, not $4 (bionic 1.4.0, task SSTART). A row is `event|matcher|command|timeout`, and
# until the SessionStart detector arrived every matcher in this tree was a single tool
# name, so the fourth field and the last field were the same field.
# `startup|clear|resume|compact` is a matcher that CONTAINS the delimiter — the platform's
# own spelling for "all four session sources" — and under `$4` that row's timeout read as
# `resume`. The timeout is always the last field, so read it as the last field; a matcher
# may not be. The cross-CHANNEL half of this check retired with the frontmatter block:
# there is one channel now, and §L.1 asserts the other is empty.
L4B_HJ_VALUES=$(printf '%s\n' "$HOOKS_JSON_ROWS" | awk -F'|' '{print $NF}' | sort -u \
  | tr '\n' ' ' | sed 's/ $//')
expect_eq "the manifest renders exactly the two timeout values the fleet has, read as the LAST field" \
  "10 25" "$L4B_HJ_VALUES"

# --- L.4c EVERY INNER BOUND SITS STRICTLY UNDER ITS HOOK'S REGISTRATION ---
#
# THE INVARIANT (epic-23 wave-14-tune-181, REQ-7; D2 ratified "(a)", D1 in-wave). A hook
# that waits on something slow owns an INNER bound: the second at which it stops waiting
# and refuses on its own terms. The manifest above registers that same hook at an OUTER
# timeout. If the inner bound is not STRICTLY under the outer registration it can never
# fire — the CLI kills the hook first, a killed hook exits 124 rather than the 2 a refusal
# spells, and the refusal that was in flight silently becomes a PASS.
#
# AND IT IS INVISIBLE TO EVERY SUITE THAT DRIVES A GATE DIRECTLY. A suite has no CLI
# timeout, so the two numbers can disagree for a whole release while each side's own
# section stays green. The gap is only visible where the two FILES meet, which is here.
# The landing sweep's derivation bound went with the map (wave-31 T23, REQ-4 AC-4.2): the
# sweep waits on nothing now, so the dispatch wall's deadline is the one inner bound left.
#
# BOTH SIDES ARE READ, NEITHER IS TRANSCRIBED. The registration comes out of
# hooks/hooks.json by the hook's own COMMAND PATH — never by array index, because the
# order of entries in a JSON array is nobody's contract and an index silently reads a
# different hook the moment one is inserted above it.

# l4c_registration <hook filename> -> the timeout(s) hooks.json registers that command at,
# one per line, de-duplicated. Matched on the path segment so `stop.sh` cannot match
# `stop-guard.sh`, and every entry naming the hook is read.
l4c_registration() {
  jq -r --arg h "$1" '[.hooks | to_entries[] | .value[] | .hooks[]
      | select(.command | test("/" + ($h | gsub("\\."; "\\.")) + "( |$)"))
      | .timeout] | unique | .[]' "$HOOKS_JSON_SRC" 2>/dev/null
}

# THE DISPATCH WALL'S OWN DEADLINE (wave-30 T35). DP_DEADLINE_S in hooks/dispatch-preflight.sh
# bounds the whole hook, strictly under its registration; the derivation bound that once sat
# under it is deleted with the map (wave-31 T2, REQ-4 AC-4.2).
L4C_DEADLINE="$(sed -n 's/^DP_DEADLINE_S=\([0-9][0-9]*\).*/\1/p' "${BIONIC_HOOKS_DIR}/dispatch-preflight.sh" | head -1)"
expect_nonempty "L.4c the dispatch wall names its own deadline (not vacuous: read from the hook)" "$L4C_DEADLINE"
expect_eq "L.4c …and the deadline strictly under the registration ($(l4c_registration dispatch-preflight.sh | head -1)s)" \
  "under" "$([ -n "$L4C_DEADLINE" ] && [ "$L4C_DEADLINE" -lt "$(l4c_registration dispatch-preflight.sh | head -1)" ] 2>/dev/null && echo under || echo 'NOT under')"

# hooks/agent-context-guard.sh runs the wall behind it only for a payload carrying a
# top-level agent_id in a session that has a roster on disk. It fronted four entries,
# and for three of them — the dispatch wall on Agent, the artifact wall on Write and
# Edit — its ONLY job was the channel partition: restrict the settings registration to
# agent contexts, because the skill channel already covered the main thread. With one
# channel there is no partition to keep, and keeping the guard there would be worse than
# redundant: it would restrict those walls to agent contexts and leave the MAIN THREAD
# uncovered, which is the reverse of what the guard was ever for.
#
# It survives on the two entries where the scope is real rather than channel-shaped:
#   landing-gate on SubagentStop — the teammate landing verdict. SubagentStop only ever
#     fires in an agent context, and the roster half of the guard is real arming.
#
# THE BASH ENTRY IS GONE (epic-23 wave-11-lean-spine, T23). It fronted
# background-suite-guard, and that wall is now one function of five in a single process:
# a wrapper there would have silenced protect-main, protect-database, the evidence gate
# and farm-out-reminder on every main-thread Bash call, which is the reverse of what the
# guard was ever for — the same sentence three paragraphs up, at a smaller scale. The
# predicate itself was NOT dropped: `wall_background_suite_guard` asks it of that one
# function, and tests/background-suite-guard.test.sh B6 drives both sides of it.
expect_absent_ug "the guard no longer fronts anything on Bash — the five walls are one process" \
  'PreToolUse|Bash|${CLAUDE_PLUGIN_ROOT}/hooks/agent-context-guard.sh' \
  "$HOOKS_JSON_ROWS"
expect_contains "…and the LANDING verdict on SubagentStop, with no matcher" \
  'SubagentStop||${CLAUDE_PLUGIN_ROOT}/hooks/agent-context-guard.sh ${CLAUDE_PLUGIN_ROOT}/hooks/stop.sh|' \
  "$HOOKS_JSON_ROWS"
for _unguarded in dispatch-preflight canonical-sdlc-governing-skill; do
  expect_absent_ug "…and no longer fronts ${_unguarded}.sh, whose only reason was the partition" \
    "agent-context-guard.sh \${CLAUDE_PLUGIN_ROOT}/hooks/${_unguarded}.sh" "$HOOKS_JSON_ROWS"
done
# The guard still hands stop.sh the channel marker on SubagentStop. The dispatch wall no
# longer depends on it: since wave-20 T7 (AC-9.2) its journal skip asks `is_agent_context`,
# which reads the payload's own top-level `agent_id` first — the variable is one spelling of
# three, and no registration hands it to dispatch-preflight.sh.
expect_contains "the guard sets the channel marker the dispatch wall reads" \
  'BIONIC_HOOK_CHANNEL=agent-context' "$(cat "$BIONIC_HOOKS_DIR/agent-context-guard.sh")"

# --- L.6 THE EVENT NAMES THE LANDING GATE ANSWERS TO ---
#
# Pinned as the SPAN that decides them rather than as a literal comparison a refactor can
# move: the relevance hoist is one `case` over `$EVENT`, and a registration whose event
# name is absent from these arms is a wall that exits before it reads anything. The gate
# now answers BOTH Stop (the orchestrator's own rows, straight) and SubagentStop (a
# teammate's, behind the guard), so both arms must be present in the script.
LG_EVENT_ARMS=$(awk '/^case "\$EVENT" in$/{f=1} f{print} f&&/^esac$/{exit}' "$PARTY_LG_SRC")
expect_eq "the landing gate's event case extracts at all (not vacuous)" "yes" \
  "$([ -n "$LG_EVENT_ARMS" ] && echo yes || echo no)"
expect_contains "…and answers Stop" "Stop" "$LG_EVENT_ARMS"
expect_contains "…and SubagentStop" "SubagentStop" "$LG_EVENT_ARMS"

# --- L.8 THE SESSIONSTART DETECTOR: one event, one channel, one owner (AC-1, SSTART) ---
#
# hooks/session-start.sh reports what `/clear` left behind — predecessor rosters, stamps,
# legacy `.bionic` links and the session-id triple — into the new conversation's context.
# It is registered ALWAYS-ON by necessity: the state it reports is left by the conversation
# that ENDED, so a registration that only binds while a skill is armed would be silent in
# exactly the session that needs it. That makes the always-on channel the right one and the
# ONLY one — a hook registered on both channels fires twice (R-2 §f), which for a detector
# means the block is pasted into context twice and a reader cannot tell the copies apart.
#
# The row is pinned BY VALUE, ${CLAUDE_PLUGIN_ROOT} spelling included, for the reason §L.3
# gives: the manifest is what the harness executes, and a command that reverted to a
# machine-local path is a hook that cannot resolve inside an installed plugin.
L8_ROWS=$(printf '%s\n' "$HOOKS_JSON_ROWS" | /usr/bin/grep -F 'session-start.sh')
expect_eq "session-start.sh is registered in hooks.json exactly once" \
  "1" "$(printf '%s\n' "$L8_ROWS" | /usr/bin/grep -c .)"
expect_eq "…on SessionStart, matching all four sources, bounded by a timeout" \
  'SessionStart|startup|clear|resume|compact|${CLAUDE_PLUGIN_ROOT}/hooks/session-start.sh|10' \
  "$L8_ROWS"
# The other half of "nowhere else": the skill frontmatter must not carry it too. Read off
# SKILL_HOOKS_ROWS, the same extractor L.1 pins the twelve armed-session rows with, so an
# empty result here means "absent from a channel this suite can still read" rather than
# "the extractor broke" — L.1's own row assertions above are what prove it still works.
expect_eq "…and NOWHERE in the skill frontmatter, which would fire it a second time" \
  "" "$(printf '%s\n' "$SKILL_HOOKS_ROWS" | /usr/bin/grep -F 'session-start.sh')"
# ONE OWNER OF THE EVENT. A second SessionStart registration would print a second block
# into the same context with no ordering guarantee between them (§L's founding finding F).
expect_eq "SessionStart carries exactly one registration in hooks.json" \
  "1" "$(printf '%s\n' "$HOOKS_JSON_ROWS" | /usr/bin/grep -c '^SessionStart|')"
# The hook the manifest names EXISTS and parses. §L.2's own header records that the
# structural "every command names a file that exists" arm died with tests/scripts.test.sh
# (8582861) and was never replaced; this row restores it for the one entry this task adds,
# so a renamed or deleted detector fails here instead of silently never firing.
expect_eq "…and the file that row names exists and parses" "ok" \
  "$( [ -f "$BIONIC_HOOKS_DIR/session-start.sh" ] \
      && bash -n "$BIONIC_HOOKS_DIR/session-start.sh" 2>/dev/null && echo ok )"

# ============================================================
section "M — THE ACK, and the stop order: ONE owner, three consumers (epic-16 w2 S3/S9)"
# ============================================================
#
# Two facts reach the stop arc from outside it, and each has ONE writer and several readers:
#
#   the ACK   — written by `hooks/session-sweeper.sh ack`, consumed by the stop gate, the
#               landing gate and the stand-down helper. Until epic-16 wave-02 S9 each of
#               those three opened the ledger itself through a byte-identical copy of a
#               `ledger_acked()` reader, and this section pinned the three bodies against
#               each other — the §9 convention, with the drift risk that convention always
#               carries. S9 promoted the answer onto the verdict machine line as `acked=`,
#               so the ledger now has ONE reader in the fleet: the file that owns it. The
#               three consumers read a field off a line they were already invoking the verb
#               to get.
#   the ORDER — written by `hooks/stop-orders.sh order`, read by the stop gate. Writer and
#               reader each hold the validity window as a literal.
#
# Per-component suites drive each consumer against its own fixtures. What none of them can
# see is the CROSS-SCRIPT property: that no consumer carries an ack-reading of its own, that
# the window is the same number, and that all three answer the same about one ledger the
# real writer wrote — including when the single owner is mutated to lie (§M.5).

SG_M="$BIONIC_HOOKS_DIR/stop-guard.sh"
LG_M="$BIONIC_HOOKS_DIR/stop.sh"
SO_M="$BIONIC_HOOKS_DIR/stop-orders.sh"

# --- M.1 ONE OWNER: no consumer reads the ledger, in any of the three ways it could ---
#
# The extractor is checked against a function that DOES survive, so an emptied `fn_body`
# result below means "the reader is gone" rather than "the extractor stopped working".

# --- M.2 one window, two holders ---
_ttl_of() { grep -E '^ORDER_TTL_SECONDS=' "$1" | head -1 | cut -d= -f2; }

# --- M.3 one ledger, written by the real ack verb, read the same by all three ---
MREPO=$(new_repo "ack-agreement")
MSLUG=$(printf '%s' "$MREPO" | sed 's/[^a-zA-Z0-9]/-/g')
MPROJ="$CLAUDE_CONFIG_DIR/projects/$MSLUG"
MSUB="$MPROJ/$SID_A/subagents"
mkdir -p "$MSUB" "$MREPO/.bionic/tmp"
MTR="$MPROJ/$SID_A.jsonl"
printf '{}\n' > "$MTR"
plant "$MSUB" "afinished-1111111111111111" "finished"
wake "$MSUB" "afinished-1111111111111111"
write_plan "$MREPO/.bionic/docs/plans/epic-99/wave-01.md" "current: 4"
# A contract that will NEVER land: the artifact is not written, so every party's verdict is
# UNMET and the ack is the only thing that can discharge anything. A fixture whose contract
# landed would agree for the wrong reason.
roster_row_fixture status=confirmed session="$SID_A" name=finished \
  agent_id=afinished-1111111111111111 launched_at=2026-08-05T00:00:00Z \
  deliverable=.bionic/docs/record/never.md \
  teammate_id="finished@session-$(printf '%s' "$SID_A" | cut -c1-8)" \
  >> "$MREPO/.bionic/tmp/roster-$SID_A.state"

# The landing sweep answers for each row ONCE, ever, and journals a marker into the roster
# to keep that promise. Each of the three drives below is a separate question about the same
# fixture, so the marker is cleared first — the property under test is what the consumers
# read off ONE ledger, not the sweep's idempotency (which tests/landing-gate.test.sh owns).
MROSTER="$MREPO/.bionic/tmp/roster-$SID_A.state"
#
# THE FIXTURE ROW IS A TEAMMATE ROW — it carries a `teammate_id=`, as every row the
# completion arm writes for a named dispatch does — so the arm that answers for it is the
# SubagentStop verdict, not the Stop-sweep (which skips those rows by design: their ids are
# in a namespace `background_tasks[]` does not use, and they never leave that array anyway).
# Driving the gate through the arm that actually owns the row is what keeps this section
# about the ACK rather than about routing, and it asks the new arm the same question the
# other two consumers are asked: does one ack ledger close this row for you too.
m_sweep() {  # <gate path> -> the gate's exit status, refusal on stdout
  /usr/bin/grep -v '^landing-swept/' "$MROSTER" > "$MROSTER.tmp" 2>/dev/null
  mv "$MROSTER.tmp" "$MROSTER"
  mk_substop_payload "$MREPO" "$SID_A" "afinished-1111111111111111" finished false | bash "$1" 2>&1
}

m_vline() {  # -> the verdict machine line all three consumers read for this fixture
  ( cd "$MREPO" && CLAUDE_CODE_SESSION_ID="$SID_A" bash "$SWEEPER" verdict finished 2>/dev/null ) \
    | grep -F 'landing-verdict/v1|' | head -1
}

# BEFORE the ack — all three say the row is open. This is the paired positive without which
# the three assertions after it would pass over a fixture nothing could ever block.
expect_contains "before the ack: the one line all three read says acked=no" \
  "|acked=no|" "$(m_vline)"
OUT=$(mk_stop_payload "$SID_A" "$MTR" "$MREPO" "finished" | bash "$SG_M" 2>&1); ST=$?
expect_eq "before the ack: the stop gate judges the row open, the look taken (wave-31 T32: allowed, its verdict recorded as reason=)" "0" "$ST"
expect_contains "before the ack: …its verdict on the look" "STOP ALLOWED" "$OUT"
OUT=$(m_sweep "$LG_M"); ST=$?
expect_eq "before the ack: the landing gate refuses" "2" "$ST"
OUT=$( cd "$MREPO" && CLAUDE_CODE_SESSION_ID="$SID_A" bash "$SO_M" standdown 2>&1 )
expect_contains "before the ack: the stand-down leaves it alone" "LEFT ALONE" "$OUT"

# THE REAL WRITER writes the one file all three read.
( cd "$MREPO" && CLAUDE_CODE_SESSION_ID="$SID_A" bash "$SWEEPER" ack finished ) >/dev/null 2>&1
expect_eq "the ack verb wrote its ledger where its one reader looks" "yes" \
  "$([ -f "$MREPO/.bionic/tmp/sweeper-$SID_A.state" ] && echo yes || echo no)"

# THE PROMOTION, end to end over the real writer: the same line now says acked=yes, and the
# STATE beside it did not move. The ack changed what the consumers know, not what the disk
# says — which is what "the ack's semantics are unchanged" means concretely.
M_VLINE=$(m_vline)
expect_contains "after the ack: the one line all three read says acked=yes" "|acked=yes|" "$M_VLINE"
expect_contains "…while the contract itself is still UNMET, computed from the disk alone" \
  "|state=UNMET|" "$M_VLINE"

OUT=$(mk_stop_payload "$SID_A" "$MTR" "$MREPO" "finished" | bash "$SG_M" 2>&1); ST=$?
expect_eq "after the ack: the stop gate passes" "0" "$ST"
expect_absent "after the ack: …discharged before any look, so no verdict is written" "STOP ALLOWED" "$OUT"
OUT=$(m_sweep "$LG_M"); ST=$?
OUT=$( cd "$MREPO" && CLAUDE_CODE_SESSION_ID="$SID_A" bash "$SO_M" standdown 2>&1 )
expect_contains "after the ack: the stand-down puts it in the batch" "1 row(s) have landed" "$OUT"
expect_contains "…addressed the way the stop primitive takes it" \
  "finished@session-$(printf '%s' "$SID_A" | cut -c1-8)" "$OUT"

# --- M.3b ONE OWNER, PROVEN BY MUTATION: blind the field, all three go back to holding ---
#
# What the three-copy pin used to buy was drift detection between the copies. With the
# copies gone that proof has to be replaced rather than dropped, and this is the stronger
# form of it: the three consumers are byte-identical copies of what ships, only the OWNER is
# mutated — to report every row unacked — and all three answers move together. A consumer
# that had kept a private reader would stay green here, which is exactly the regression
# §M.1's greps cannot catch on their own (a reader spelled some other way).
#
# The mutant is installed in its own directory beside the gates, which is how bootstrap's
# flat `hooks/*.sh` install lets each of them find its sibling — the production resolution,
# not a test seam.
MMUT="$(plant_hook_tree "$SANDBOX/ack-mutant")"
cp "$SG_M" "$MMUT/stop-guard.sh"
cp "$LG_M" "$MMUT/stop.sh"
cp "$SO_M" "$MMUT/stop-orders.sh"
anchor file hooks/session-sweeper.sh 'row_acked "$_pname"'
awk '{ if (index($0, "row_acked \"$_pname\"") > 0) $0 = "    _acked=no"
       print }' "$SWEEPER" > "$MMUT/session-sweeper.sh"
expect_contains "the mutated owner reports the acked row as unacked" "|acked=no|" \
  "$( cd "$MREPO" && CLAUDE_CODE_SESSION_ID="$SID_A" bash "$MMUT/session-sweeper.sh" verdict finished 2>/dev/null )"
OUT=$(mk_stop_payload "$SID_A" "$MTR" "$MREPO" "finished" | bash "$MMUT/stop-guard.sh" 2>&1); ST=$?
expect_eq "…and the stop gate takes the look again on the stop it passed a moment ago (wave-31 T32: allowed, its verdict recorded as reason=)" "0" "$ST"
expect_contains "…its verdict back on the look" "STOP ALLOWED" "$OUT"
OUT=$(m_sweep "$MMUT/stop.sh"); ST=$?
expect_eq "…and the landing gate refuses it too" "2" "$ST"
OUT=$( cd "$MREPO" && CLAUDE_CODE_SESSION_ID="$SID_A" bash "$MMUT/stop-orders.sh" standdown 2>&1 )
expect_contains "…and the stand-down puts it back in LEFT ALONE" "LEFT ALONE" "$OUT"
# The shipped files were never touched: the substitution is by path, and this says so.

# --- M.4 the order: one writer, one reader, one boundary ---
_now=$(date -u +%s)
_ttl=$(_ttl_of "$SO_M")
# JUST INSIDE the window and JUST OUTSIDE it, placed by arithmetic rather than by waiting:
# a suite that slept through a thirty-minute window would not be a suite. The pair is what
# makes this an assertion about the boundary rather than about the happy path.
# A FRESH WORLD, and no ack in it: the row above is acked, so an order placed there would
# be discharged by the ack whatever the window said, and the boundary would go untested
# while looking green.
mk_order_world() {  # <label> <name> <agent-id> -> "<repo>|<transcript>"
  local repo tr slug proj sub
  repo=$(new_repo "$1")
  slug=$(printf '%s' "$repo" | sed 's/[^a-zA-Z0-9]/-/g')
  proj="$CLAUDE_CONFIG_DIR/projects/$slug"
  sub="$proj/$SID_A/subagents"
  mkdir -p "$sub" "$repo/.bionic/tmp"
  tr="$proj/$SID_A.jsonl"
  printf '{}\n' > "$tr"
  plant "$sub" "$3" "$2"
  wake "$sub" "$3"
  write_plan "$repo/.bionic/docs/plans/epic-99/wave-01.md" "current: 4"
  cg_roster_row "$repo" "$SID_A" "$2" "$3"
  printf '%s|%s\n' "$repo" "$tr"
}

IFS='|' read -r IN_REPO IN_TR <<< "$(mk_order_world "order-inside" "inside" "ainside-1111111111111111")"
( cd "$IN_REPO" && CLAUDE_CODE_SESSION_ID="$SID_A" bash "$SO_M" order inside --at $((_now - _ttl + 60)) ) >/dev/null 2>&1
OUT=$(mk_stop_payload "$SID_A" "$IN_TR" "$IN_REPO" "inside" | bash "$SG_M" 2>&1); ST=$?
expect_eq "an order inside the shared window discharges the stop" "0" "$ST"

IFS='|' read -r EX_REPO EX_TR <<< "$(mk_order_world "order-expiry" "expired" "aexpired-2222222222222222")"
( cd "$EX_REPO" && CLAUDE_CODE_SESSION_ID="$SID_A" bash "$SO_M" order expired --at $((_now - _ttl - 60)) ) >/dev/null 2>&1
OUT=$(mk_stop_payload "$SID_A" "$EX_TR" "$EX_REPO" "expired" | bash "$SG_M" 2>&1); ST=$?
expect_eq "an order just outside it does not — the look decides, as it did (wave-31 T32: allowed, its verdict recorded as reason=)" "0" "$ST"
expect_contains "…the look's verdict" "STOP ALLOWED" "$OUT"
expect_absent "…never the order's line" "STOP ORDERED" "$OUT"

# --- M.4b the order's AUTHOR crosses the same seam (AC-1.1; T1, D1) ---
#
# The order widened from "a human said stop" to "a human OR a verified landing said stop",
# and the writer stamps which. The reader's rule is unchanged — an order is an order — and
# that is the property here: a Patrol-written order discharges the stop exactly as a human's
# does, at the same boundary. Writer and reader are different scripts, so no per-component
# suite can see it; stop-orders.test.sh proves the field is written, stop-guard.test.sh
# proves the line names it, and only this one proves they are the same field.
IFS='|' read -r PT_REPO PT_TR <<< "$(mk_order_world "order-patrol" "patrolled" "apatrolled-3333333333333333")"
( cd "$PT_REPO" && CLAUDE_CODE_SESSION_ID="$SID_A" bash "$SO_M" order patrolled --by patrol ) >/dev/null 2>&1
expect_contains "the writer stamped the author on the line the gate reads" "|by=patrol|target=patrolled" \
  "$(cat "$PT_REPO/.bionic/tmp/stop-orders-$SID_A.state" 2>/dev/null)"
OUT=$(mk_stop_payload "$SID_A" "$PT_TR" "$PT_REPO" "patrolled" | bash "$SG_M" 2>&1); ST=$?
expect_eq "a PATROL-written order discharges the stop, exactly as a human's does" "0" "$ST"
expect_contains "…and the gate reports the author it read, not one it assumed" "by patrol" "$OUT"

# The paired negative at the SAME boundary: attribution is not a second window. A patrol
# order outside the shared window is as expired as a human's.
IFS='|' read -r PX_REPO PX_TR <<< "$(mk_order_world "order-patrol-expiry" "patrol-expired" "apatrolx-4444444444444444")"
( cd "$PX_REPO" && CLAUDE_CODE_SESSION_ID="$SID_A" bash "$SO_M" order patrol-expired --by patrol --at $((_now - _ttl - 60)) ) >/dev/null 2>&1
OUT=$(mk_stop_payload "$SID_A" "$PX_TR" "$PX_REPO" "patrol-expired" | bash "$SG_M" 2>&1); ST=$?
expect_eq "…and an expired one does not, whoever wrote it (wave-31 T32: allowed, its verdict recorded as reason=)" "0" "$ST"
expect_contains "…the look's verdict, not the order's" "STOP ALLOWED" "$OUT"
expect_absent "…never the order's line" "STOP ORDERED" "$OUT"

# --- M.6 the ack's AUTHOR crosses it too (AC-1.3; T1, D2) ---
#
# The ack widened the same way: the Patrol writes one for a row the world shows moot
# (`by=patrol|reason=moot-and-gone`). ONE OWNER still writes the ledger and the three
# consumers still read the `acked=` field off the verdict line — so a patrol ack must close
# a row for all three, and the field must be on the line the real writer wrote. An ack that
# closed a row for the stop gate but not for the landing gate would be two answers to one
# question, which is what this whole section exists to forbid.
AREPO=$(new_repo "ack-by-agreement")
ASLUG=$(printf '%s' "$AREPO" | sed 's/[^a-zA-Z0-9]/-/g')
APROJ="$CLAUDE_CONFIG_DIR/projects/$ASLUG"
ASUB="$APROJ/$SID_A/subagents"
mkdir -p "$ASUB" "$AREPO/.bionic/tmp"
ATR="$APROJ/$SID_A.jsonl"
printf '{}\n' > "$ATR"
plant "$ASUB" "amoot-5555555555555555" "moot"
wake "$ASUB" "amoot-5555555555555555"
write_plan "$AREPO/.bionic/docs/plans/epic-99/wave-01.md" "current: 4"
roster_row_fixture status=confirmed session="$SID_A" name=moot \
  agent_id=amoot-5555555555555555 launched_at=2026-08-05T00:00:00Z \
  deliverable=.bionic/docs/record/never.md \
  teammate_id="moot@session-$(printf '%s' "$SID_A" | cut -c1-8)" \
  >> "$AREPO/.bionic/tmp/roster-$SID_A.state"

a_vline() {
  ( cd "$AREPO" && CLAUDE_CODE_SESSION_ID="$SID_A" bash "$SWEEPER" verdict moot 2>/dev/null ) \
    | grep -F 'landing-verdict/v1|' | head -1
}
expect_contains "before the patrol ack: the one line all three read says acked=no" \
  "|acked=no|" "$(a_vline)"
OUT=$(mk_stop_payload "$SID_A" "$ATR" "$AREPO" "moot" | bash "$SG_M" 2>&1); ST=$?
expect_eq "before the patrol ack: the stop gate judges the row open, the look taken (wave-31 T32: allowed, its verdict recorded as reason=)" "0" "$ST"
expect_contains "before the patrol ack: …its verdict on the look" "STOP ALLOWED" "$OUT"

( cd "$AREPO" && CLAUDE_CODE_SESSION_ID="$SID_A" bash "$SWEEPER" ack moot --by patrol --reason moot-and-gone ) >/dev/null 2>&1
expect_contains "the one owner wrote the author and the evidence onto its own line" \
  "|name=moot|by=patrol|reason=moot-and-gone" \
  "$(cat "$AREPO/.bionic/tmp/sweeper-$SID_A.state" 2>/dev/null)"
expect_contains "after the patrol ack: the one line all three read says acked=yes" \
  "|acked=yes|" "$(a_vline)"
expect_contains "…while the contract itself is still UNMET, computed from the disk alone" \
  "|state=UNMET|" "$(a_vline)"
OUT=$(mk_stop_payload "$SID_A" "$ATR" "$AREPO" "moot" | bash "$SG_M" 2>&1); ST=$?
expect_eq "after the patrol ack: the stop gate passes, as it does for a human's" "0" "$ST"
expect_absent "after the patrol ack: …discharged before any look" "STOP ALLOWED" "$OUT"
OUT=$( cd "$AREPO" && CLAUDE_CODE_SESSION_ID="$SID_A" bash "$SO_M" standdown 2>&1 )
expect_contains "…and the stand-down puts it in the batch, as it does for a human's" \
  "1 row(s) have landed" "$OUT"

# ============================================================
section "N — the wave-02 facts: one root, one vocabulary, one launch reference (S9)"
# ============================================================
#
# Six rows specified by the tasks that could not add them: `record/w2-s45-wallfacts.md` §6
# (the wall and the probe became one preflight, and duplicated the root resolver a fourth
# time doing it) and `record/w2-s6-launchref.md` §6 (the launch reference stopped being
# re-stamped on resume, in a file whose readers live elsewhere). Each is a property no
# single-component suite can see, because in each case the writer and the reader are
# different scripts.
#
# WHAT IS DEFERRED, and named rather than quietly dropped: w2-s6 §6 row 3, teammate-mode
# resume driven end to end. It needs a real repeated `teammate_spawned` PostToolUse capture —
# the same payload delivered twice for one agent — and no such capture exists on disk. The
# suite's `mk_agent_post_teammate` is faithful to a SINGLE spawn (capture probe §3-A); a
# second one synthesized here would be this suite asserting against its own guess about what
# a resume looks like in that mode, which is the fixture-fidelity failure the header forbids.
# The async half of the same property IS driven, at §N.6.

# ------------------------------------------------ N.1 one loader idiom, one root, one id
#
# `resolve_project_root()` WAS an eight-copy family: the governing-skill hook held the
# origin, the evidence gate its long-standing twin, the dispatch wall and the probe took
# copies when the wall ran the probe inline, the poker and stop-orders when answering
# `--show-toplevel` was found to name a worktree's own root, the agent-context guard when
# a guard that rooted a worktree at its own tree answered "unarmed" for every agent
# context inside one, and patrol-revive when the same reasoning reached the Patrol stamp.
# Eight files, one algorithm, held together by a body-for-body pin that could only ever
# prove they had not drifted YET.
#
# THEY ARE GONE (bionic 1.4.0, task ADOPT, spec AC-10). What is pinned instead is the
# convention that replaced them, and it has three parts, each with its own way of going
# quietly wrong: the loader block that finds the library must be ONE text in every hook
# (a hand edit to one copy), every reader must ASK for the root rather than restate it
# (a straggler keeps its own answer), and every reader must ask for the SESSION ID the
# same way (two spellings of one session make two rosters).
# The shipped paths §N's later subsections read. They named the eight resolver carriers
# before this wave; the ones that survive are the ones those subsections still drive.
DP_N="$BIONIC_HOOKS_DIR/dispatch-preflight.sh"

# expect_ne migrated onto tests/lib/assert.sh (S5a, AC-12) — same semantics, asserted the
# other way round: the value must have MOVED.

N_LOADER_LIB="$BIONIC_HOOKS_DIR/../payload/scripts/lib/loader.sh"
[ -r "$N_LOADER_LIB" ] || N_LOADER_LIB="$BIONIC_HOOKS_DIR/../scripts/lib/loader.sh"
N_BLOCK="$( . "$N_LOADER_LIB" && bionic_loader_pin )"
expect_eq "the canonical loader block extracts from lib/loader.sh (not vacuous)" "yes" \
  "$([ "$(printf '%s\n' "$N_BLOCK" | wc -l | tr -d ' ')" -gt 50 ] && echo yes || echo no)"

n_block_of() {  # <file> -> the marker-delimited span, markers inclusive
  awk '/^# --- bionic-loader\/v2 BEGIN$/{f=1} f{print} f&&/^# --- bionic-loader\/v2 END$/{exit}' "$1"
}

# THE ADOPTED SET, named rather than globbed: a glob would silently shrink to nothing if
# the marker were renamed, and this section would pass over air. session-poker.sh (the
# eighteenth hook off resolve_project_root, converted by task POKER) and session-start.sh
# (added by task SSTART) both carry the idiom too — verified live, byte for byte, against
# this section's own $N_BLOCK extraction — and both resolve their root through the library
# the same way every other member of this set does, so they belong in the SAME list rather
# than a sibling one (Step-6 duplication review, record/wave-1.4.0/review-duplication.md,
# ownership row 6: neither was pinned anywhere, so nothing would catch drift in either).
# THE FIVE PreToolUse|Bash WALLS ARE ONE FILE (epic-23 wave-11-lean-spine, T23):
# hooks/bash-walls.sh, whose bodies are functions of payload/scripts/lib/walls.sh.
N_ADOPTED='bash-walls
dispatch-preflight canonical-sdlc-governing-skill stop execution-recorder stop-guard
agent-context-guard preflight-probe stop-orders
session-sweeper stop-check session-poker session-start engage'
for _h in $N_ADOPTED; do
  expect_eq "$_h.sh carries the canonical loader block, byte for byte" \
    "$N_BLOCK" "$(n_block_of "$BIONIC_HOOKS_DIR/$_h.sh")"
done
# ------------------------------------------------ …AND IT IS SMALL (the cap, 1f-c)
#
# ONE TEXT was never the whole property. The block is pasted into 22 files, so every line
# of it is paid 22 times, and 64 of the original 147 were commentary restating the code
# beside them or repeating loader.sh's own header (census, record/wave-11-lean-spine/
# step1-census-1f.md §3.1). Byte-identity is satisfied by 147 identical lines exactly as
# happily as by 95, so the SIZE is pinned separately (REQ-1f, AC-1f.1): the rows above fix
# what the block says, this one fixes how much room it is allowed to say it in.
N_CAP=95
N_CAN_LINES=$(printf '%s\n' "$N_BLOCK" | wc -l | tr -d ' ')
expect_eq "the canonical loader block is at most $N_CAP lines (measured $N_CAN_LINES)" "yes" \
  "$([ "$N_CAN_LINES" -le "$N_CAP" ] && echo yes || echo no)"

# MEASURED IN THE HOOKS TOO, not inferred from the canonical text. The agreement rows above
# make this redundant only while they pass: rename the marker in one hook and `n_block_of`
# returns nothing there, and nothing is under any cap. So the longest span is reported BY
# NAME, and a span that failed to extract at all is reported as its own failure.
N_LONGEST=""; N_LONGEST_N=0; N_UNEXTRACTED=""
for _h in $N_ADOPTED; do
  _n=$(n_block_of "$BIONIC_HOOKS_DIR/$_h.sh" | wc -l | tr -d ' ')
  if [ "${_n:-0}" -lt 1 ]; then N_UNEXTRACTED="$N_UNEXTRACTED $_h"; continue; fi
  if [ "$_n" -gt "$N_LONGEST_N" ]; then N_LONGEST_N="$_n"; N_LONGEST="$_h"; fi
done
expect_eq "every adopted hook's loader span extracts (the cap is measuring text, not air)" \
  "" "$N_UNEXTRACTED"
expect_eq "the longest hook loader span is at most $N_CAP lines (${N_LONGEST:-none} at $N_LONGEST_N)" \
  "yes" "$([ "$N_LONGEST_N" -le "$N_CAP" ] && echo yes || echo no)"

# MUTATION, both pins at once. A cap and a byte pin that have never been seen to fail are
# two comments. ONE copy is doctored in the SANDBOX — never in the tree — by padding its
# span past the cap, and both properties must reject it: the bytes no longer agree, and the
# measurement no longer fits.
mkdir -p "$SANDBOX/fx"
N_MUT_HOOK="$SANDBOX/fx/fat-loader-copy.sh"
anchor insert hooks/agent-context-guard.sh '# --- bionic-loader/v2 BEGIN'
awk -v cap="$N_CAP" '
  { print }
  /^# --- bionic-loader\/v2 BEGIN$/ { for (i = 0; i <= cap; i++) print "# padding the span past the cap" }
' "$BIONIC_HOOKS_DIR/agent-context-guard.sh" > "$N_MUT_HOOK"
N_MUT_BLOCK="$(n_block_of "$N_MUT_HOOK")"
N_MUT_LINES=$(printf '%s\n' "$N_MUT_BLOCK" | wc -l | tr -d ' ')
expect_ne "the loader-cap mutation really doctored the span (not a byte-identical copy)" \
  "$(n_block_of "$BIONIC_HOOKS_DIR/agent-context-guard.sh")" "$N_MUT_BLOCK"
expect_ne "…and the byte-for-byte pin calls the doctored span a drift" "$N_BLOCK" "$N_MUT_BLOCK"
expect_eq "…and the cap rejects it ($N_MUT_LINES lines against a cap of $N_CAP)" "no" \
  "$([ "$N_MUT_LINES" -le "$N_CAP" ] && echo yes || echo no)"

# NO PRIVATE RESOLVER SURVIVES — none, not one. ADOPT converted seventeen hooks and task
# POKER the eighteenth, so the eight-copy family is empty and this row is what keeps a
# nineteenth from being written by hand.
N_STRAGGLERS=$(/usr/bin/grep -ln '^resolve_project_root()' "$BIONIC_HOOKS_DIR"/*.sh 2>/dev/null \
  | while IFS= read -r _f; do basename "$_f"; done | sort | tr '\n' ' ' | sed 's/ $//')
expect_eq "no hook defines a private resolve_project_root any more" "" "$N_STRAGGLERS"

# EVERY READER ASKS, and since task-engaged-session that is every member without exception.
# protect-main and background-suite-guard used to be excluded here — they classified a
# command and read no root at all — but the engagement marker lives UNDER a root, so both
# now resolve one through the library like everyone else and the carve-out is gone.
#
# RE-POINTED (epic-23 wave-11-lean-spine, REQ-1f). Fifteen of these hooks no longer NAME
# `project_root`: they ask `bionic_context`, which resolves the root by the one cwd ladder
# and calls the one resolver. The question this row asks is unchanged — does this hook get
# its root from the library, or work one out — so the ask is EITHER shared call, and a hook
# that resolves no root at all still fails. What stops that from being a weakening is the
# straggler row above (no private resolver) and §CTX below (the inline sequence in ZERO
# hook bodies), neither of which either call can satisfy.
for _h in $N_ADOPTED; do
  expect_eq "$_h.sh resolves its root through the library" "yes" \
    "$(/usr/bin/grep -qE '^bionic_context|project_root "' "$BIONIC_HOOKS_DIR/$_h.sh" && echo yes || echo no)"
done

# ------------------------------------------------ §CTX THE CONTEXT PREAMBLE, one lib call
#
# (epic-23 wave-11-lean-spine, REQ-1f (ii) AC-1f.2 and REQ-1h AC-1h.1; spec Design §1
# "ContextPreamble", §2 D6, §3 ownership row "context preamble".)
#
# WHAT WAS WRONG. Fifteen hooks opened the same way after the loader — read the payload,
# find the cwd, find the root, resolve the session id, ask engagement, ask the run — in 861
# lines that said one thing, and the T10 census measured that they did not in fact say the
# same thing: SEVEN cwd ladders, a session-id shape guard in six of the fifteen, three
# different actions on an empty id, and one hook reading its session key twice from two
# sources. `payload/scripts/lib/context.sh` says it once, as `bionic_context`.
#
# THE INVARIANT IS NEGATIVE, and that is the point. "Every hook calls the library" is
# satisfied by a hook that calls it and then restates the sequence anyway — which is how
# every duplicated-family regression in this tree has actually happened. So the pin has two
# halves: each of the fifteen CALLS it, and NO file under hooks/ carries the sequence
# inline. The second half is the one with teeth, and the mutation arm below is what keeps it
# from being a comment.
#
# THE FIFTEEN, named rather than globbed (A-40/A-41). session-sweeper and stop-check read a
# root, a sid and docs_root and ask neither engagement nor a run verdict — §Roots below pins
# that neither declares run.sh, which adopting context.sh would break — and the three CLIs
# (engage, preflight-probe, stop-orders) plus session-poker take no hook payload at all.
# All six keep their own calls, which is why the negative half is scoped by the SEQUENCE
# rather than by the presence of any one function.
# TWELVE NOW, NOT FIFTEEN (epic-23 wave-11, T12). The four Stop hooks became four
# FUNCTIONS in payload/scripts/lib/stop.sh and one process, hooks/stop.sh, which takes the
# call once for all four. The rule is unchanged — one hook, one `bionic_context` — and the
# roster is the tree's, not a number this file remembers.
# THE FIVE PreToolUse|Bash WALLS ARE ONE FILE (epic-23 wave-11-lean-spine, T23):
# hooks/bash-walls.sh, whose bodies are functions of payload/scripts/lib/walls.sh.
N_CTX_FIFTEEN='agent-context-guard bash-walls
canonical-sdlc-governing-skill dispatch-preflight execution-recorder
session-start stop stop-guard permission-answer'

for _h in $N_CTX_FIFTEEN; do
  expect_eq "$_h.sh asks lib/context.sh:bionic_context for its context" "yes" \
    "$(/usr/bin/grep -q 'bionic_context' "$BIONIC_HOOKS_DIR/$_h.sh" && echo yes || echo no)"
done

# AND THE COUNT IS EXACTLY THE ROSTER (AC-1f.2's own measurement, re-derived at T12 when
# the four Stop hooks became one). The per-hook rows above cannot see an EXTRA caller, and a hook that picked the call up without being part of
# the preamble family is a hook paying a root walk and a plan walk for nothing.
N_CTX_CALLERS=$(/usr/bin/grep -l 'bionic_context' "$BIONIC_HOOKS_DIR"/*.sh 2>/dev/null \
  | xargs -n1 basename 2>/dev/null | sed 's/\.sh$//' | sort | tr '\n' ' ' | sed 's/ $//')
N_CTX_EXPECTED=$(printf '%s\n' $N_CTX_FIFTEEN | sort | tr '\n' ' ' | sed 's/ $//')
expect_eq "the preamble roster names every hook that calls bionic_context, and no other" \
  "$N_CTX_EXPECTED" "$N_CTX_CALLERS"

# ── the negative half: the sequence occurs in ZERO hook bodies ────────────────
#
# THE SEQUENCE IS DEFINED BY WHAT IT DOES, not by a line of text: a body that, BELOW its
# loader span, calls `project_root "` AND `session_id "` AND `engaged_session "` itself is a
# hook that has restated the preamble whether or not it also calls the library. Below the
# span, because the span itself is byte-identical in 22 files and contains none of the three
# — scoping to it would be scoping to a constant.
#
# THE SIX NON-MEMBERS SURVIVE THIS TEST BY CONSTRUCTION, not by exemption: none of them
# calls all three. session-sweeper and stop-check ask for no engagement at all, the three
# CLIs ask for neither engagement nor a payload, and session-poker reads the predicate as
# data from inside a verb body. That is what makes an UNSCOPED sweep of hooks/*.sh the right
# shape here — an allow-list would have to be maintained, and the thing it would be hiding
# is exactly the thing this row exists to find.
ctx_inline_carriers() {  # <hooks-dir> -> basenames carrying the inline sequence below the span
  local _f _body
  for _f in "$1"/*.sh; do
    [ -f "$_f" ] || continue
    _body=$(awk '/^# --- bionic-loader\/v2 END$/{s=1;next} s{print}' "$_f")
    printf '%s\n' "$_body" | /usr/bin/grep -q 'project_root "'    || continue
    printf '%s\n' "$_body" | /usr/bin/grep -q 'session_id "'      || continue
    printf '%s\n' "$_body" | /usr/bin/grep -q 'engaged_session "' || continue
    basename "$_f"
  done | sort | tr '\n' ' ' | sed 's/ $//'
}

expect_eq "no hook body carries the context sequence inline any more" \
  "" "$(ctx_inline_carriers "$BIONIC_HOOKS_DIR")"

# MUTATION — the row above is a claim about ABSENCE, and an absence row passes just as
# happily when the detector is broken as when the tree is clean. One copy of the hooks
# directory, with the sequence re-inlined into ONE hook below its loader span, must be
# reported as a carrier. If it is not, the row above proves nothing.
N_CTX_MUT="$SANDBOX/fx/ctx-inline"
mkdir -p "$N_CTX_MUT/clean" "$N_CTX_MUT/inlined"
cp "$BIONIC_HOOKS_DIR"/*.sh "$N_CTX_MUT/clean/" 2>/dev/null
cp "$BIONIC_HOOKS_DIR"/*.sh "$N_CTX_MUT/inlined/" 2>/dev/null
# The mutant restates the preamble the way a hand edit would: three real calls, appended
# below the span, in a hook that is one of the fifteen.
{
  cat "$BIONIC_HOOKS_DIR/stop.sh"
  printf '%s\n' \
    'CWD_MUT=$(bionic_jq .cwd)' \
    'REPO_MUT=$(project_root "$CWD_MUT")' \
    'SID_MUT=$(session_id "$(bionic_jq .session_id)" 2>/dev/null) || SID_MUT=""' \
    'engaged_session "$REPO_MUT" "$SID_MUT" || exit 0'
} > "$N_CTX_MUT/inlined/stop.sh"
expect_eq "…and a hook that re-inlines the sequence below its span is caught" \
  "stop.sh" "$(ctx_inline_carriers "$N_CTX_MUT/inlined")"
expect_eq "control: the same copying, unmutated, reports no carrier" \
  "" "$(ctx_inline_carriers "$N_CTX_MUT/clean")"

# ── AC-1h.1's static half: no hook reads either cwd channel itself ────────────
#
# The ladder is ONE ladder because it is implemented once. A hook that still reached for
# the environment variable or the payload's own cwd field would be carrying rung 1 or rung 2
# of a second ladder, and the two would disagree exactly where this wave runs — a worktree
# whose cwd and project directory are different trees.
#
# THE SWEEP STARTS AT THE FIRST `. "$BIONIC_LIB/…"` LINE, which is the first line in a hook
# where a library function can be called at all. Everything above it — the loader span, the
# cheap relevance reads, and the fail-closed arm — runs in a world where the library may not
# exist, and ONE hook has a ladder there by necessity: canonical-sdlc-evidence-gate asks
# "could a run exist here" before refusing a command it cannot read, and the file that owns
# that rule is exactly the one that failed to load. That block is declared in the gate at
# its definition as the one place duplication is the design. Scoping to "the whole file"
# would have forced that necessary copy out and left the gate refusing `ls` in every
# repository on the machine.
#
# IT IS OVER THE TEXT, COMMENTS INCLUDED, and deliberately: a comment naming a channel its
# file no longer reads is how the next reader learns the wrong thing, so below the first
# source line the hooks name the LADDER (lib/context.sh) rather than its rungs.
ctx_ladder_carriers() {  # <hooks-dir> <names…> -> basenames reading a rung below the sources
  local _d="$1" _h _body; shift
  for _h in "$@"; do
    [ -r "$_d/$_h.sh" ] || continue
    _body=$(awk '/^\. "\$BIONIC_LIB\//{s=1} s{print}' "$_d/$_h.sh")
    printf '%s' "$_body" | /usr/bin/grep -qE 'CLAUDE_PROJECT_DIR|\.cwd' && echo "$_h.sh"
  done | sort | tr '\n' ' ' | sed 's/ $//'
}

# ONE DECLARED EXEMPTION, NAMED AND COUNTED rather than carved out of the pattern.
# canonical-sdlc-governing-skill's worktree-lease wall reads the payload's own `.cwd` to ask
# WHERE THE WRITE WAS ISSUED FROM — a different question from "which project is this hook
# scoped to", and one the ladder's `pwd` rung answers wrongly, since a hook process's
# directory is not documented to be the session's. It is exempt from the row below and held
# by the two rows after it instead: exactly one such read, and no CLAUDE_PROJECT_DIR at all.
# An exemption that grew to a second read, or to rung 1, fails.
# THE SECOND, FOR THE SAME QUESTION (wave-25 T4). hooks/permission-answer.sh hands the command
# reader the directory the asking agent's command runs in, so its relative targets resolve
# where the shell will resolve them: where the action was issued from, never which project
# the hook is scoped to (that is still the ladder's, through bionic_context). Held by the
# same two rows: one payload-cwd read, no rung 1.
N_CTX_LADDER_EXEMPT='canonical-sdlc-governing-skill
permission-answer'
# A `grep -v`, not a `case`: a one-line `case` inside a command substitution is the shape
# this suite's own §case row forbids, and bash refuses to parse it here too.
N_CTX_LADDER_SWEPT=$(printf '%s\n' $N_CTX_FIFTEEN \
  | /usr/bin/grep -vxF "$N_CTX_LADDER_EXEMPT")
expect_eq "none of the twelve reads CLAUDE_PROJECT_DIR or the payload cwd below its sources" \
  "" "$(ctx_ladder_carriers "$BIONIC_HOOKS_DIR" $N_CTX_LADDER_SWEPT)"

# THE EXEMPTION, BOUNDED. Rung 1 is forbidden to it like everyone else, and its payload-cwd
# read is exactly one — a wall, not a ladder.
for _h in $N_CTX_LADDER_EXEMPT; do
  _body=$(awk '/^\. "\$BIONIC_LIB\//{s=1} s{print}' "$BIONIC_HOOKS_DIR/$_h.sh")
  expect_eq "$_h.sh reaches for no CLAUDE_PROJECT_DIR either" "0" \
    "$(printf '%s' "$_body" | /usr/bin/grep -c 'CLAUDE_PROJECT_DIR' | tr -d ' ')"
  expect_eq "$_h.sh reads the payload cwd exactly once, and for its own wall" "1" \
    "$(printf '%s' "$_body" | /usr/bin/grep -c '\.cwd' | tr -d ' ')"
done

# NOT VACUOUS: the sweep really does reach fifteen non-empty bodies. A `. "$BIONIC_LIB/`
# line that moved or lost its column-0 spelling would make every row above pass over air.
N_CTX_READABLE=$(for _h in $N_CTX_FIFTEEN; do
    [ -n "$(awk '/^\. "\$BIONIC_LIB\//{s=1} s{print}' "$BIONIC_HOOKS_DIR/$_h.sh")" ] && echo x
  done | wc -l | tr -d ' ')
# THE TWO NUMBERS ARE DERIVED FROM THE ROSTER (T23), which shrank when the five Bash walls
# became one file. A typed literal here would go red on every future merge for the wrong
# reason, and — worse — would go GREEN over a roster that had silently lost a member.
N_CTX_COUNT=$(printf '%s\n' $N_CTX_FIFTEEN | /usr/bin/grep -c .)
expect_eq "…and the ladder sweep found a source line and a body in every one of them" \
  "$N_CTX_COUNT" "$N_CTX_READABLE"
expect_true "…over a roster that is not empty" test "$N_CTX_COUNT" -ge 6
expect_eq "…of which all but the declared exemptions are swept" \
  "$((N_CTX_COUNT - $(printf '%s\n' $N_CTX_LADDER_EXEMPT | /usr/bin/grep -c .)))" \
  "$(printf '%s\n' $N_CTX_LADDER_SWEPT | wc -l | tr -d ' ')"

# MUTATION — an absence row passes as happily when the detector is broken as when the tree
# is clean. A copy with one rung re-introduced BELOW the sources must be caught.
N_CTX_LMUT="$SANDBOX/fx/ctx-ladder"
mkdir -p "$N_CTX_LMUT"
cp "$BIONIC_HOOKS_DIR"/*.sh "$N_CTX_LMUT/" 2>/dev/null
{
  cat "$BIONIC_HOOKS_DIR/stop.sh"
  printf '%s\n' 'CWD_MUT="${CLAUDE_PROJECT_DIR:-}"'
} > "$N_CTX_LMUT/stop.sh"
expect_eq "…and a hook that reaches for a rung below its sources is caught" \
  "stop.sh" "$(ctx_ladder_carriers "$N_CTX_LMUT" $N_CTX_LADDER_SWEPT)"

# ------------------------------------------------ §P′ THE SESSION-ID SOURCE, bound
#
# The environment value is primary and the payload is a witness (design §1, R-1). A hook
# that reads `.session_id` straight out of its payload has silently chosen the witness
# over the record — and every roster, stamp and stop address is keyed on the answer, so
# two hooks choosing differently give one session two of each. What is pinned is the
# SOURCE, not the value: every reader calls `session_id`, and any payload read that
# remains is the ARGUMENT to that call.
# RE-POINTED (epic-23 wave-11-lean-spine, REQ-1f/REQ-1h). The rule is unchanged and the
# roster is unchanged; what split is HOW a member reaches `session_id`. Fifteen hooks reach
# it through `bionic_context`, which calls it once and then applies the ONE shape guard
# those hooks used to carry six copies of between them. Five reach it directly — the three
# CLIs and the two roots-only readers, none of which take a hook payload or ask engagement.
# The roster is split on that line rather than shortened, so a member that asks for NEITHER
# still fails, and both halves are derived from the tree below.
# THE FIVE PreToolUse|Bash WALLS ARE ONE FILE (epic-23 wave-11-lean-spine, T23):
# hooks/bash-walls.sh, whose bodies are functions of payload/scripts/lib/walls.sh.
N_SID_VIA_CTX='agent-context-guard bash-walls
canonical-sdlc-governing-skill dispatch-preflight execution-recorder
session-start stop stop-guard permission-answer'
N_SID_DIRECT='engage preflight-probe session-sweeper stop-check stop-orders'
N_SID_READERS="$N_SID_VIA_CTX
$N_SID_DIRECT"
for _h in $N_SID_VIA_CTX; do
  expect_eq "$_h.sh takes its session id from lib/session.sh, through bionic_context" "yes" \
    "$(/usr/bin/grep -q '^bionic_context' "$BIONIC_HOOKS_DIR/$_h.sh" && echo yes || echo no)"
done
for _h in $N_SID_DIRECT; do
  expect_eq "$_h.sh takes its session id from lib/session.sh" "yes" \
    "$(/usr/bin/grep -q 'session_id "' "$BIONIC_HOOKS_DIR/$_h.sh" && echo yes || echo no)"
done

# THE LIST IS COMPLETE, not just each named member correct (auditor A-1, AC-2): a static
# list can omit a real reader forever and every row above still passes silently.
# session-start.sh was exactly that member — a session_id caller this wave added,
# unpinned by this list until the line above. Derived from the tree and compared to the
# hand-written list, byte for byte — the same technique N_STRAGGLERS above uses for the
# private-resolver family.
N_SID_ACTUAL=$(/usr/bin/grep -l 'session_id "' "$BIONIC_HOOKS_DIR"/*.sh 2>/dev/null \
  | xargs -n1 basename 2>/dev/null | sed 's/\.sh$//' | sort | tr '\n' ' ' | sed 's/ $//')
N_SID_DIRECT_EXPECTED=$(printf '%s\n' $N_SID_DIRECT | sort | tr '\n' ' ' | sed 's/ $//')
expect_eq "the direct session-id roster names every hook that calls session_id, and no other" \
  "$N_SID_DIRECT_EXPECTED" "$N_SID_ACTUAL"
# AND THE OTHER HALF, derived the same way. A sixteenth hook that picked up the preamble
# call without joining the roster is the omission this half exists to catch — it is the
# same row §CTX states as the count of fifteen, asked here about the session key.
N_SID_CTX_ACTUAL=$(/usr/bin/grep -l '^bionic_context' "$BIONIC_HOOKS_DIR"/*.sh 2>/dev/null \
  | xargs -n1 basename 2>/dev/null | sed 's/\.sh$//' | sort | tr '\n' ' ' | sed 's/ $//')
N_SID_CTX_EXPECTED=$(printf '%s\n' $N_SID_VIA_CTX | sort | tr '\n' ' ' | sed 's/ $//')
expect_eq "the via-the-library roster names every hook that calls bionic_context, and no other" \
  "$N_SID_CTX_EXPECTED" "$N_SID_CTX_ACTUAL"


# ------------------------------------------------ §P‴ THE ENGAGEMENT-GUARD ROSTER, complete
#
# step-6 review R-7. The ownership table promised "guard line byte-identical across the
# roster" and nothing built it: the behavioural battery at §M covers four hooks of the
# fifteen, so a NEW hook shipped without the guard would deny, nudge or audit in a session
# that never invoked canonical-sdlc, and every suite would stay green. That is the same
# silent-omission class §P′ closes for the session-id readers, and it is closed the same
# way — derive the set from the tree, compare it to a hand-written roster, fail on drift in
# EITHER direction.
#
# WHY THE SHAPE AND NOT THE BYTES. The promise as written was never satisfiable: the
# fourteen guard lines legitimately differ in the root variable name (REPO, PM_REPO,
# DB_REPO, BSG_REPO, PROJECT_DIR, PROJECT_ROOT_FROM_PATH, ROOT — seven of them) and in the
# sid name, because each hook has already resolved both under its own local convention by
# the time it reaches the guard. What has to agree is the DECISION, so what is pinned here
# is the call shape — `engaged_session "$<root>" "$<sid>" || exit 0` at column 0, the
# hook's first scoping decision — not the characters.
#
# TWO ROSTERS, because two hooks read the predicate without exiting on it: session-start.sh
# uses it to choose WHICH notice to print (its whole job is to speak to a bystander) and
# session-poker.sh consults it inside the tick and adopt verbs. Their membership is pinned
# too; what they are exempt from is the `|| exit 0` shape.
# RE-POINTED (epic-23 wave-11-lean-spine, REQ-1f). The decision is what is pinned, and the
# decision has not moved — its SPELLING has. `bionic_context` asks `engaged_session` once
# and hands back BIONIC_ENGAGED as a 0 or a 1, deliberately as a value: session-start
# prints its bystander notice exactly where the other fourteen exit, and a library that
# acted on the predicate would have deleted that notice. So thirteen hooks now spell the
# guard `[ "$BIONIC_ENGAGED" = 1 ] || exit 0` at column 0, and THAT is the shape row below.
#
# THREE ROSTERS NOW, not two, because the third is a real and separate case:
#   GUARD     — the thirteen that exit on the value the preamble resolved.
#   OWN_ROOT  — canonical-sdlc-governing-skill, which asks the predicate ITSELF because it
#               scopes to the ARTIFACT's root rather than the session's cwd (its own comment
#               says why: a hook that scoped by one root and enforced against another would
#               go quiet exactly where it was added to bind). It keeps the old call shape.
#   DATA      — session-poker and session-start, which read the predicate without exiting.
# NINE NOW, NOT THIRTEEN (epic-23 wave-11, T12). The four Stop hooks' guards went into
# payload/scripts/lib/stop.sh with their bodies, where each spells it as a `return` rather
# than an `exit` — a folded function must not exit. hooks/stop.sh itself asks nothing about
# engagement: the four functions each answer for their own arm, exactly as the four hooks
# did. So the merged process is off this roster by design, not by omission.
# THE FIVE PreToolUse|Bash WALLS ARE ONE FILE (epic-23 wave-11-lean-spine, T23):
# hooks/bash-walls.sh, whose bodies are functions of payload/scripts/lib/walls.sh.
N_ENGAGED_READERS='agent-context-guard bash-walls
dispatch-preflight execution-recorder stop-guard permission-answer'
N_ENGAGED_OWN_ROOT='canonical-sdlc-governing-skill'
N_ENGAGED_DATA='session-poker session-start'

# derive_engaged <hooks-dir> -> sorted basenames of every hook calling the predicate DIRECTLY
derive_engaged() {
  /usr/bin/grep -l 'engaged_session ' "$1"/*.sh 2>/dev/null \
    | xargs -n1 basename 2>/dev/null | sed 's/\.sh$//' | sort | tr '\n' ' ' | sed 's/ $//'
}
# derive_engaged_value <hooks-dir> -> sorted basenames of every hook reading the VALUE
derive_engaged_value() {
  /usr/bin/grep -l 'BIONIC_ENGAGED' "$1"/*.sh 2>/dev/null \
    | xargs -n1 basename 2>/dev/null | sed 's/\.sh$//' | sort | tr '\n' ' ' | sed 's/ $//'
}

N_ENG_EXPECTED=$(printf '%s\n' $N_ENGAGED_OWN_ROOT session-poker | sort | tr '\n' ' ' | sed 's/ $//')
N_ENG_ACTUAL=$(derive_engaged "$BIONIC_HOOKS_DIR")
expect_eq "the direct-predicate roster names every hook that calls engaged_session, and no other" \
  "$N_ENG_EXPECTED" "$N_ENG_ACTUAL"

N_ENGV_EXPECTED=$(printf '%s\n' $N_ENGAGED_READERS $N_ENGAGED_OWN_ROOT $N_ENGAGED_DATA \
  | /usr/bin/grep -v '^session-poker$' | sort | tr '\n' ' ' | sed 's/ $//')
N_ENGV_ACTUAL=$(derive_engaged_value "$BIONIC_HOOKS_DIR")
expect_eq "…and the value roster names every hook that reads BIONIC_ENGAGED, and no other" \
  "$N_ENGV_EXPECTED" "$N_ENGV_ACTUAL"

# NOT VACUOUS: both derived sets are non-empty.
expect_ne "…and the derivation actually found hooks (this row is not vacuous)" "" "$N_ENG_ACTUAL"
expect_ne "…and so did the value derivation" "" "$N_ENGV_ACTUAL"

# THE GUARD SHAPE, per member. The FIRST BIONIC_ENGAGED line in the file must be the guard
# itself, at column 0, comparing to 1 and exiting 0 — the hook's first scoping decision
# after the context resolves. A guard that compared to the wrong value, swallowed the
# result, or exited non-zero would still satisfy the roster rows above and fail here.
# THE GUARD IS READ WHERE IT IS WRITTEN (T23). hooks/bash-walls.sh asks it ONCE for all
# five of its walls, at column zero like the rest, and the other members still ask it in
# their own bodies — so the file each member is read from is its own.
for _h in $N_ENGAGED_READERS; do
  _line=$(/usr/bin/grep -m1 'BIONIC_ENGAGED' "$BIONIC_HOOKS_DIR/$_h.sh" 2>/dev/null)
  case "$_line" in
    '[ "$BIONIC_ENGAGED" = 1 ] || exit 0') ok "$_h.sh guards on the canonical shape" ;;
    *) no "$_h.sh guards on the canonical shape" "first BIONIC_ENGAGED line was: [$_line]" ;;
  esac
done

# THE ONE THAT ASKS FOR ITSELF keeps the call shape it always had, against its own root.
for _h in $N_ENGAGED_OWN_ROOT; do
  _line=$(/usr/bin/grep -m1 'engaged_session ' "$BIONIC_HOOKS_DIR/$_h.sh" 2>/dev/null)
  case "$_line" in
    'engaged_session "$'*'" "$'*'" || exit 0') ok "$_h.sh guards on the canonical call shape, against the artifact root" ;;
    *) no "$_h.sh guards on the canonical call shape, against the artifact root" "first engaged_session line was: [$_line]" ;;
  esac
done

# THE DATA READERS are members and are NOT held to either shape — pinned so a future reader
# does not "fix" them into an exit. session-poker still asks the predicate directly inside
# its verb bodies; session-start reads the value the preamble resolved.
expect_eq "session-poker.sh reads the predicate (as data, exempt from the guard shape)" "yes" \
  "$(/usr/bin/grep -q 'engaged_session ' "$BIONIC_HOOKS_DIR/session-poker.sh" && echo yes || echo no)"
expect_eq "session-start.sh reads the value (as data, exempt from the guard shape)" "yes" \
  "$(/usr/bin/grep -q 'BIONIC_ENGAGED' "$BIONIC_HOOKS_DIR/session-start.sh" && echo yes || echo no)"

# MUTATION, both directions. A completeness row that never moves is a comment. Two doctored
# copies of the hooks directory: one with a guard DELETED (a hook silently leaves the
# roster) and one with a guard ADDED to a file the roster does not name (a new hook ships
# guarded and unlisted). The row above must disagree with the declared roster in both.
N_ENG_MUT="$SANDBOX/fx/engaged-roster"
mkdir -p "$N_ENG_MUT/drop" "$N_ENG_MUT/add"
cp "$BIONIC_HOOKS_DIR"/*.sh "$N_ENG_MUT/drop/" 2>/dev/null
cp "$BIONIC_HOOKS_DIR"/*.sh "$N_ENG_MUT/add/" 2>/dev/null
# RE-POINTED with the roster: landing-gate's guard is a BIONIC_ENGAGED test now, so the
# `drop` mutant deletes that line instead, and the completeness row it must turn red is the
# VALUE roster. A `grep -v` for a literal that had left the file would have deleted nothing
# and reported a mutation that never happened, which is why the anchor above it is the part
# that matters.
anchor file hooks/stop-guard.sh 'BIONIC_ENGAGED'
grep -v 'BIONIC_ENGAGED' "$BIONIC_HOOKS_DIR/stop-guard.sh" > "$N_ENG_MUT/drop/stop-guard.sh"
expect_ne "…and a hook that quietly loses its guard makes the roster row RED" \
  "$N_ENGV_EXPECTED" "$(derive_engaged_value "$N_ENG_MUT/drop")"
printf '[ "$BIONIC_ENGAGED" = 1 ] || exit 0\n' > "$N_ENG_MUT/add/zz-new-wall.sh"
expect_ne "…and an unlisted NEW hook carrying the guard makes it RED too" \
  "$N_ENGV_EXPECTED" "$(derive_engaged_value "$N_ENG_MUT/add")"

# THE PAIRED POSITIVE: the same copying, unmutated, still agrees — or both reds above are
# the `cp` and not the mutation.
mkdir -p "$N_ENG_MUT/clean"
cp "$BIONIC_HOOKS_DIR"/*.sh "$N_ENG_MUT/clean/" 2>/dev/null
expect_eq "control: an UNMUTATED copy of the hooks directory still matches the roster" \
  "$N_ENG_EXPECTED" "$(derive_engaged "$N_ENG_MUT/clean")"
expect_eq "control: …and matches the value roster too" \
  "$N_ENGV_EXPECTED" "$(derive_engaged_value "$N_ENG_MUT/clean")"

# ------------------------------------------------ §P″ THE DIVERGENT-CHANNEL FIXTURE, two
# real hooks, one filename (auditor A-1, AC-2's other half)
#
# §P′ above pins the SOURCE by static grep (every reader's call site names `session_id`),
# which the revert-and-watch capture in record/wave-1.4.0/revert-and-watch.md proved
# insensitive to a change INSIDE session_id's own body — a hook that silently switched to
# preferring the payload would still grep-match `session_id "` and every §P′ row would stay
# green. Nothing before this section drives a real hook end to end with env != payload and
# checks what filename it actually touched. This does, with two independent readers over the
# SAME repo under the SAME divergence: hooks/dispatch-preflight.sh, which builds
# `patrol-<sid>.state` / `roster-<sid>.state` by interpolating session_id's resolved value
# (its `PAYLOAD_SID` variable is that resolved value, not a raw payload read — see its own
# header comment), and hooks/session-start.sh, which excludes ITS OWN roster/stamp from the
# predecessor lists it prints because they are its own. If the two disagreed about which
# session this is, they would disagree about which file is "mine" — session-start would
# print a file dispatch-preflight had just written to as though it were a stranger's.
#
# session-poker.sh was considered as the second party and rejected: its `arm` verb calls
# `session_id` with NO payload argument at all (hooks/session-poker.sh, every `SESSION_ID=
# "$(session_id)"` site) — it never reads a payload session id, so there is no divergence
# for a fixture to drive it with. Recorded here rather than left for the next reader to
# rediscover.
P2_REPO=$(new_repo "sid-divergence")
# new_repo arms SID_A, SID_B and SID_LG together (arm_patrol) — re-armed here for SID_A
# ONLY, so a reader that wrongly resolved the payload session (SID_B) hits the loud
# "never armed" refusal instead of quietly finding a stamp under the wrong name too.
rm -f "$P2_REPO/.bionic/tmp/patrol-$SID_A.state" "$P2_REPO/.bionic/tmp/patrol-$SID_B.state" \
      "$P2_REPO/.bionic/tmp/patrol-$SID_LG.state"
arm_patrol "$P2_REPO" "$SID_A"
write_live_plan "$P2_REPO/.bionic/docs/plans/epic-p2/wave-01.md" "current: 4"
{
  printf '# bionic environment attestation — machine-local, safe to delete\n'
  printf 'version=1\nkind=preflight-attestation\n'
  printf 'session_id=%s\nwritten_at=1785790000\nrepo=%s\n' "$SID_A" "$P2_REPO"
} > "$P2_REPO/.bionic/tmp/preflight-$SID_A.state"

# READER 1 — the dispatch wall, driven with env=A / payload=B. Its OWN call site
# suppresses session_id's stderr (`session_id "$(_jq '.session_id')" 2>/dev/null`,
# hooks/dispatch-preflight.sh) — deliberately, per plan Assumption ADOPT/3: every hook
# but session-start.sh silences the divergence line so it does not land on every tool
# call of a divergent session, and session-start's SessionStart block is the one place
# it is designed to surface. So the wall's own stderr must stay silent about it; reader
# 2 below is where the line is expected.
P2_ERR=$(mk_agent_payload "$SID_B" "$P2_REPO" \
  | env CLAUDE_CODE_SESSION_ID="$SID_A" bash "$PARTY_DP" 2>&1 >/dev/null); P2_ST=$?
expect_eq "P2 the dispatch wall passes a well-formed dispatch under a divergent session" \
  "0" "$P2_ST"
expect_absent "P2 …its own call site suppresses the divergence line (ADOPT/3), by design" \
  "session-id:" "$P2_ERR"
expect_eq "P2 reader 1 (the dispatch wall) journalled the launch under the ENV session's roster" \
  "yes" "$([ -f "$P2_REPO/.bionic/tmp/roster-$SID_A.state" ] && echo yes || echo no)"
expect_eq "P2 …never under the payload session's" \
  "no" "$([ -e "$P2_REPO/.bionic/tmp/roster-$SID_B.state" ] && echo yes || echo no)"

# READER 2 — session-start, driven with the SAME env=A / payload=B, over the SAME repo.
# It never prints its own roster/stamp filename; it EXCLUDES them from the predecessor
# lists it prints, because they are its own. `roster-A.state` is a real file now (reader 1
# just wrote it) and carries one open row, so agreement means session-start does NOT list
# it as a predecessor — disagreement means it would, with an open-row count attached.
P2_SS_OUT=$(printf '{"session_id":"%s","transcript_path":"/irrelevant.jsonl","cwd":"%s","hook_event_name":"SessionStart","source":"resume"}' \
    "$SID_B" "$P2_REPO" \
  | env CLAUDE_CODE_SESSION_ID="$SID_A" bash "$BIONIC_HOOKS_DIR/session-start.sh" 2>&1)
expect_absent "P2 reader 2 (session-start) treats roster-A as ITS OWN, not a predecessor" \
  "roster-$SID_A.state" "$P2_SS_OUT"
expect_contains "P2 …and its own printed triple names the ENV value as CUR, agreeing with reader 1" \
  "env=$SID_A" "$P2_SS_OUT"
expect_contains "P2 …session-start is the ONE reader that does not suppress the divergence line" \
  "session-id: payload $SID_B" "$P2_SS_OUT"

# DIFFERENTIAL CONTROL — env UNSET: both readers fall back to the payload (design §1's
# second clause), and must now agree on B instead of A. Without this arm the two checks
# above could pass for a reader that always answers "the env value" as a constant, never
# actually reading either channel.
P2C_REPO=$(new_repo "sid-divergence-ctrl")
rm -f "$P2C_REPO/.bionic/tmp/patrol-$SID_A.state" "$P2C_REPO/.bionic/tmp/patrol-$SID_B.state" \
      "$P2C_REPO/.bionic/tmp/patrol-$SID_LG.state"
arm_patrol "$P2C_REPO" "$SID_B"
write_live_plan "$P2C_REPO/.bionic/docs/plans/epic-p2c/wave-01.md" "current: 4"
{
  printf '# bionic environment attestation — machine-local, safe to delete\n'
  printf 'version=1\nkind=preflight-attestation\n'
  printf 'session_id=%s\nwritten_at=1785790000\nrepo=%s\n' "$SID_B" "$P2C_REPO"
} > "$P2C_REPO/.bionic/tmp/preflight-$SID_B.state"
P2C_ST=$(mk_agent_payload "$SID_B" "$P2C_REPO" \
  | env CLAUDE_CODE_SESSION_ID="" bash "$PARTY_DP" >/dev/null 2>&1; echo $?)
expect_eq "P2c control: env unset, the wall falls back to the payload session" \
  "0" "$P2C_ST"
expect_eq "P2c …and journals it under the PAYLOAD session's roster this time" \
  "yes" "$([ -f "$P2C_REPO/.bionic/tmp/roster-$SID_B.state" ] && echo yes || echo no)"
P2C_SS_OUT=$(printf '{"session_id":"%s","transcript_path":"/irrelevant.jsonl","cwd":"%s","hook_event_name":"SessionStart","source":"resume"}' \
    "$SID_B" "$P2C_REPO" \
  | env CLAUDE_CODE_SESSION_ID="" bash "$BIONIC_HOOKS_DIR/session-start.sh" 2>&1)
expect_absent "P2c reader 2 also treats roster-B as ITS OWN under the fallback" \
  "roster-$SID_B.state" "$P2C_SS_OUT"

# --------------------------------------------------- N.2 one root, one ANSWER, on disk
#
# Bodies being equal was a claim about text. This is the claim about the ANSWER, taken
# where the field case took it: inside a real `git worktree add`, which is the input that
# separates a resolver that maps a worktree onto its main repository from one that does
# not. There is one implementation now, so what this drives is the library itself —
# and §N.1 above is what ties every hook to it.
NREPO="$SANDBOX/fx/nroot/repo"
mkdir -p "$NREPO/.bionic"
git -C "$NREPO" init -q 2>/dev/null
git -C "$NREPO" config user.email t@example.com
git -C "$NREPO" config user.name "T"
echo seed > "$NREPO/README.md"
git -C "$NREPO" add README.md >/dev/null 2>&1
git -C "$NREPO" commit -qm seed >/dev/null 2>&1
NWT="$SANDBOX/fx/nroot/wt"
git -C "$NREPO" worktree add -q -b n-root-wt "$NWT" >/dev/null 2>&1
NMAIN=$(cd "$NREPO" && pwd -P)

N_ROOT_LIB="$BIONIC_HOOKS_DIR/../payload/scripts/lib/root.sh"
[ -r "$N_ROOT_LIB" ] || N_ROOT_LIB="$BIONIC_HOOKS_DIR/../scripts/lib/root.sh"
root_at() {  # <cwd> -> project_root's answer from inside that directory
  ( . "$N_ROOT_LIB" || exit 1; cd "$1" 2>/dev/null || exit 1; project_root ) 2>/dev/null
}
root_at_path() {  # <path, which need not exist> -> project_root's answer for it
  ( . "$N_ROOT_LIB" || exit 1; project_root "$1" ) 2>/dev/null
}

expect_eq "a linked worktree cwd roots at the MAIN repository" "$NMAIN" "$(root_at "$NWT")"
expect_eq "…and the main repository roots at itself" "$NMAIN" "$(root_at "$NREPO")"
# DEEP INSIDE A DIRECTORY THAT DOES NOT EXIST YET — the shape a PreToolUse gate meets on
# the first artifact write into a project, where the climb to the nearest existing
# ancestor is the part of the resolver that has to answer.
expect_eq "…and so does a path deep inside the worktree that has not been created yet" \
  "$NMAIN" "$(root_at_path "$NWT/deep/not/created/yet")"

# THE PAIRED NEGATIVE, and a precondition it depends on. Outside any repository and with no
# `.bionic` anywhere above, the answer is the path itself. That second half is a fact about
# the MACHINE, not the code: $SANDBOX lives under $TMPDIR, which every bionic suite on this
# machine shares, and the walk climbs to `/` looking for a `.bionic`. Measured 2026-08-23: a
# stray `$TMPDIR/.bionic/` left by a SIBLING suite turned this battery red 7-of-7, naming
# neither the leak nor the leaker. This row measures the precondition first and says which
# directory is dirty — it cannot make the battery immune, but it turns mysterious diffs into
# one legible line.
NOUT="$SANDBOX/fx/nroot/notarepo"
mkdir -p "$NOUT"
NOUT_DIRTY=""
_anc="$NOUT"
while [ -n "$_anc" ] && [ "$_anc" != "/" ] && [ "$_anc" != "." ]; do
  if [ -d "$_anc/.bionic" ]; then NOUT_DIRTY="$_anc"; fi
  _anc=$(dirname "$_anc")
done
expect_eq "no ancestor of the fallback fixture carries a stray .bionic (shared \$TMPDIR)" \
  "" "$NOUT_DIRTY"
expect_eq "outside any repository, with no .bionic above, the answer is the path itself" \
  "$(cd "$NOUT" && pwd -P)" "$(root_at "$NOUT")"

# THE NO-GIT ARM, which the two git-derived checks above never reach. NBWS is a workspace
# carrying a real `.bionic/` that was never `git init`'d — the shape a repo nested under a
# workspace makes, and the one the old resolvers got wrong by answering the git root.
NBWS="$SANDBOX/fx/nroot/bws"
mkdir -p "$NBWS/.bionic/docs/record" "$NBWS/sub/deep"
expect_eq "a non-git workspace holding .bionic roots at the workspace" "$(cd "$NBWS" && pwd -P)" \
  "$(root_at "$NBWS/sub/deep")"

# MUTATION, the discriminator: drop the worktree mapping from a copy of the library and
# the worktree answers itself — the pre-R9 behaviour, and the one that made a worktree its
# own address space. Without this the section proves only that a function exists.
N_MUT_ROOT="$SANDBOX/fx/rootless-root.sh"
anchor file payload/scripts/lib/root.sh '--path-format=absolute --git-common-dir --git-dir'
anchor file payload/scripts/lib/root.sh 'rev-parse --git-common-dir --git-dir'
awk '{ if (index($0, "--git-common-dir") > 0 && $0 !~ /^[ \t]*#/) sub(/--git-common-dir/, "--git-dir"); print }' \
  "$N_ROOT_LIB" > "$N_MUT_ROOT"
N_MUT_ANSWER=$( ( . "$N_MUT_ROOT" || exit 1; cd "$NWT" 2>/dev/null || exit 1; project_root ) 2>/dev/null )
expect_ne "…and the mutated library no longer answers the main repository" "$NMAIN" "$N_MUT_ANSWER"

# ------------------------------------------- N.3 producer and consumer, one attestation path
#
# w2-s45 §6 row 2. The probe WRITES the attestation and the dispatch wall READS it, and since
# R5 the wall runs the probe itself when it finds none. From a worktree cwd those two paths
# are only equal because both sides resolve the root the same way — the inequality that would
# silently re-break the combined preflight, and it would present as a wall that auto-probes on
# every single dispatch while an attestation sits on disk one directory over.
#
# The credential is pinned PRESENT (a syntactic placeholder — the probe tests presence, never
# validity) for the reason §D records: unpinned, the probe consults the machine login keychain
# and the drive lands on the refused path or the accepted one depending on whose machine runs
# the suite. Only the accepted path writes anything, which is the path under test here.
write_live_plan "$NREPO/.bionic/docs/plans/epic-99/wave-01.md" "current: 4"
# Hand-built fixture, so it arms explicitly — under the MAIN repository, which is also the
# only place the arming wall reads from a worktree cwd (the property N.1/N.2 measure).
arm_patrol "$NREPO" "$SID_A"
NENV=(env HOME="$SANDBOX/home" CLAUDE_CONFIG_DIR="$CLAUDE_CONFIG_DIR"
      ANTHROPIC_API_KEY="pinned-placeholder-not-a-credential")

( cd "$NWT" && "${NENV[@]}" CLAUDE_CODE_SESSION_ID="$SID_A" bash "$PROBE" ) >/dev/null 2>&1
NATT="$NREPO/.bionic/tmp/preflight-$SID_A.state"
expect_eq "the PRODUCER, run from the worktree, writes under the main repository" "yes" \
  "$([ -f "$NATT" ] && echo yes || echo no)"
expect_eq "…and leaves no phantom .bionic in the worktree (R9: one address space)" "no" \
  "$([ -e "$NWT/.bionic" ] && echo yes || echo no)"

# THE CONSUMER, from the same worktree cwd. It must FIND that record — the observable is the
# absence of the auto-probe announce line, which the wall prints only when it had to take an
# attestation of its own. A wall that looked in the worktree would announce every time.
#
# THE PAYLOAD IS AN AGENT'S (bionic 1.4.0, spec AC-14, task WALLS). This section's subject is
# the ADDRESS SPACE — producer and consumer resolving one root from a worktree cwd — and the
# dispatch that legitimately happens there is a dispatched writer's, working in the tree it was
# given. A MAIN-THREAD dispatch from a worktree is now the refusal N.3b drives below, so the
# drives here carry the fields the harness puts in a subagent's own payload: a top-level
# `agent_id` (t1-probe-report §3) and `agent_type`.
#
# FLIPPED BY DESIGN (wave-20 T7, AC-9.2; Δ11/Δ12). A nested dispatch writes NO roster row — the
# roster is the orchestrator's depth-one ledger — and it may launch only a read-only role, so
# the drive launches `bionic:researcher`. This row used to assert the nested launch's roster
# row "landed under the main repository too"; that row is exactly what AC-9.2 removes, and
# keeping it by exempting `agent_type`-only payloads would re-open triage-B D2c. The address
# space is measured instead by the observable this section already relies on: the consumer
# FINDS the producer's attestation, so it takes none of its own and prints no auto-probe line.
N_AGENT_PAYLOAD() { mk_agent_payload "$SID_A" "$NWT" \
  | jq '.tool_input.subagent_type = "bionic:researcher"
        | . + {agent_id:"aNnested-0123456789abcd", agent_type:"bionic:senior-implementor"}'; }
N_OUT=$(N_AGENT_PAYLOAD | "${NENV[@]}" bash "$PARTY_DP" 2>&1); N_ST=$?
expect_eq "the CONSUMER, from the same worktree, passes the dispatch" "0" "$N_ST"
expect_absent "…having FOUND the producer's attestation under the main repository (no auto-probe)" \
  "the environment check was run automatically" "$N_OUT"
expect_eq "…and, nested, it wrote NO roster row anywhere (AC-9.2 — the ledger stays at depth one)" "no" \
  "$([ -f "$NREPO/.bionic/tmp/roster-$SID_A.state" ] && echo yes || echo no)"
expect_eq "…with no phantom .bionic in the worktree from the gate either" "no" \
  "$([ -e "$NWT/.bionic" ] && echo yes || echo no)"

# THE DISCRIMINATING HALF: remove the record and the same dispatch announces. Without it the
# assertions above would pass over a wall that had simply stopped announcing anything.
# A FRESH NAME (T22): the dispatch above journalled a `w99-impl` row, and since the
# name-in-flight arm a second dispatch under an open name is refused — which is that arm's
# subject, not this section's.
N_AGENT_PAYLOAD() { mk_agent_payload "$SID_A" "$NWT" \
  | jq '.tool_input.name = "w99-impl-r5" | .tool_input.subagent_type = "bionic:researcher"
        | . + {agent_id:"aNnested-0123456789abcd", agent_type:"bionic:senior-implementor"}'; }
rm -f "$NATT"
N_OUT=$(N_AGENT_PAYLOAD | "${NENV[@]}" bash "$PARTY_DP" 2>&1); N_ST=$?
expect_eq "with the record gone the dispatch still passes (R5: attestation never blocks)" "0" "$N_ST"
expect_contains "…and THIS time it announces the probe it ran (the absence above is not vacuous)" \
  "the environment check was run automatically" "$N_OUT"
expect_eq "…writing it back to the same path the consumer reads" "yes" \
  "$([ -f "$NATT" ] && echo yes || echo no)"

# ------------------------------------------- N.3b the lease wall, on the same one address space
#
# Spec AC-14, task WALLS. Everything above proves that a worktree cwd and the main checkout
# resolve to ONE address space; this is what the gate now does with that fact. A main-thread
# dispatch made from inside a linked worktree is refused and NAMES the main checkout — the
# same root N.1 measured — while the agent payload three lines up passes through the same
# wall. Asserted here rather than only in tests/dispatch-preflight.test.sh because the root
# in the refusal is the library's answer, which is this suite's whole subject.
# A FRESH NAME, for the reason N.3 above already states and this arm now needs too
# (wave-14 REQ-8, T6): the passing dispatches above journalled `w99-impl`, and with the
# gate's arms pooled a re-used name would put the name-in-flight fault beside the lease
# fault and refuse for both at once — one refusal on the deny channel, where this arm reads
# an exit status. The lease wall is what AC-14 is about.
N_LEASE_OUT=$(mk_agent_payload "$SID_A" "$NWT" \
  | jq -c '.tool_input.name = "w99-impl-lease"' \
  | "${NENV[@]}" bash "$PARTY_DP" 2>&1); N_LEASE_ST=$?
# A deny verdict, exit 0, since wave-19 T4 (REQ-7): the gate refuses every brief or state
# fault on one wire whatever the fault count. `2>&1` above keeps the stdout verdict in view.
expect_eq "a MAIN-THREAD dispatch from the same worktree is refused (AC-14)" "0" "$N_LEASE_ST"
expect_contains "…on a deny verdict" '"permissionDecision":"deny"' "$N_LEASE_OUT"
expect_contains "…naming the main checkout the library already resolves to" \
  "main checkout: $NMAIN" "$N_LEASE_OUT"

# --------------------------------------------------- N.4 source=: one word, and one reader
#
# w2-s45 §6 row 3, RE-EXPRESSED at R1 (inference withdrawn — plan assumption 48). Wave-02 R4
# let `hooks/dispatch-preflight.sh` write `source=inferred` for a deliverable it GUESSED from
# prose; the Step-6 critic (N-1) showed the guess was then enforced with a declared fact's
# full weight, so Chris withdrew inference. The wall now writes `source=` with exactly one
# non-empty value, `declared`. `hooks/session-sweeper.sh` is still its only reader, branching
# on `!= "inferred"` — a branch that is now always true (no writer emits `inferred`), harmless,
# and left in place because touching the sweeper is outside R1's file set. One word, one reader.
N_SRC_VALUES=$(grep -oE '^[[:space:]]*C_SOURCE="[a-z]*"' "$DP_N" \
  | sed -E 's/.*"([a-z]*)"/\1/' | grep -v '^$' | sort -u | tr '\n' ' ' | sed 's/ $//')

# Driven, not just grepped: three briefs, three routes to a path, and what the writer does with
# each now that it never guesses. A LABELED slot-free path is `declared` and lands; an UNLABELED
# prose path and a TEMPLATED `<slot>` are both REFUSED at dispatch (no roster row) — the
# withdrawal, asserted from the writer's own output in the paired verdict-AND-inventory shape.
#
# THE REFUSAL IS A `deny` VERDICT, NOT AN EXIT STATUS (wave-12 T17). Both refused briefs above
# carry a second shape fault — neither declares `Files:` or `Suites:` — and the wall now spends
# a multi-fault brief as ONE PreToolUse deny on stdout, exit 0, so the model reads every fault
# rather than the first. A row reading the status alone would call that an ALLOW.
NSRC=$(new_repo "source-vocab")
write_live_plan "$NSRC/.bionic/docs/plans/epic-99/wave-01.md" "current: 4"
# Run in the CURRENT shell (never a command-substitution subshell) so the wall's own exit
# code survives to the assertion; read the roster row in a separate step.
n_dispatch() {  # <name> <prompt> — runs the wall in this shell; its exit is the function's exit
  jq -n --arg s "$SID_A" --arg c "$NSRC" --arg n "$1" --arg p "$2" \
    '{session_id:$s, transcript_path:"/irrelevant.jsonl", cwd:$c,
      hook_event_name:"PreToolUse", tool_name:"Agent",
      tool_input:{description:"a dispatch", subagent_type:"implementor", name:$n, prompt:$p},
      tool_use_id:("toolu_01" + $n)}' \
    | "${NENV[@]}" bash "$PARTY_DP" 2>/dev/null
}
# n_verdict <status> <stdout> -> allow | exit2 | deny — both of the wall's wires, read together.
n_verdict() {
  case "$2" in *'"permissionDecision":"deny"'*) printf 'deny'; return 0 ;; esac
  case "$1" in
    0) printf 'allow' ;;
    2) printf 'exit2' ;;
    *) printf 'exit%s' "$1" ;;
  esac
}
n_row() { grep -F "|name=$1|" "$NSRC/.bionic/tmp/roster-$SID_A.state" 2>/dev/null | tail -1; }

N_OUT=$(n_dispatch declaring 'Expected artifact: .bionic/docs/record/declared.md
Suites: tests/widget.test.sh'); N_ST=$?
expect_eq "a LABELED slot-free path passes the wall" "allow" "$(n_verdict "$N_ST" "$N_OUT")"
expect_contains "…and records source=declared" "|source=declared|" "$(n_row declaring)"
N_OUT=$(n_dispatch inferring 'the notes go in .bionic/docs/record/inferred.md when done'); N_ST=$?
expect_eq "an UNLABELED record/ path is REFUSED at dispatch (no inference)" "deny" \
  "$(n_verdict "$N_ST" "$N_OUT")"
N_OUT=$(n_dispatch filling 'Expected artifact: .bionic/docs/record/<name>.md'); N_ST=$?
expect_eq "a TEMPLATED <slot> path is REFUSED at dispatch (no fill)" "deny" \
  "$(n_verdict "$N_ST" "$N_OUT")"

# ------------------------------------------------- N.5 the ghost row, asked of every writer
#
# w2-s45 §6 row 4. AC-12's "a refused dispatch leaves no row" is pinned in the wall's own
# suite, where the wall is the only writer in the room. The roster has THREE writers, and the
# other two are stop-side: a refused dispatch that later drew a row from `execution-recorder`
# would be a ghost with a different author, invisible to the wall's own before/after check.
#
# The recorder's two roster arms both key on a row the LAUNCH half wrote — ARM 2 on a matching
# `intended` row for the tool_use_id, ARM 3 on a matching intended/confirmed row for the name.
# A refused dispatch wrote neither, so both must find nothing and write nothing. In the field
# the tool call never runs at all (the wall exits 2), which is exactly why the defensive
# question is worth asking here rather than assuming the ordering holds.
NGH=$(new_repo "ghost-row")
write_live_plan "$NGH/.bionic/docs/plans/epic-99/wave-01.md" "current: 4"
mkdir -p "$NGH/.bionic/tmp"
# A brief naming NO inferable deliverable: the one shape R4 still refuses (AC-3's planted
# failure), and therefore the one that reaches this section with a refusal to leave no trace.
N_REFUSED=$(jq -n --arg s "$SID_A" --arg c "$NGH" \
  '{session_id:$s, transcript_path:"/irrelevant.jsonl", cwd:$c,
    hook_event_name:"PreToolUse", tool_name:"Agent",
    tool_input:{description:"a dispatch", subagent_type:"implementor", name:"ghosted",
                prompt:"Go and do the thing. Report back when you are finished."},
    tool_use_id:"toolu_01GHOST"}')
N_WALL_OUT=$(printf '%s' "$N_REFUSED" | "${NENV[@]}" bash "$PARTY_DP" 2>/dev/null)
N_WALL_ST=$?
expect_eq "the wall refuses a brief naming no inferable deliverable" "deny" \
  "$(n_verdict "$N_WALL_ST" "$N_WALL_OUT")"
N_INV_BEFORE=$(cat "$NGH/.bionic/tmp/roster-$SID_A.state" 2>/dev/null; echo "[no roster]")

# Now both stop-side writers, for the dispatch that never happened.
jq -n --arg s "$SID_A" --arg c "$NGH" \
  '{session_id:$s, transcript_path:"/irrelevant.jsonl", cwd:$c,
    hook_event_name:"PostToolUse", tool_name:"Agent",
    tool_input:{description:"a dispatch", prompt:"go", subagent_type:"implementor",
                run_in_background:true, name:"ghosted"},
    tool_response:{isAsync:true, status:"async_launched", agentId:"aghosted-1111111111111111"},
    tool_use_id:"toolu_01GHOST"}' | bash "$PARTY_ER" >/dev/null 2>&1
mk_start_payload "$SID_A" "/irrelevant.jsonl" "$NGH" "ghosted" "aghosted-1111111111111111" \
  | bash "$PARTY_ER" >/dev/null 2>&1
N_INV_AFTER=$(cat "$NGH/.bionic/tmp/roster-$SID_A.state" 2>/dev/null; echo "[no roster]")

# THE PAIRED POSITIVE, over the identical machinery: an ACCEPTED dispatch draws exactly one
# row from the wall and one more from each stop-side arm. Without it the three assertions
# above would pass over a recorder that had stopped writing rows at all.
printf '%s' "$N_REFUSED" \
  | jq '.tool_input.prompt = "Expected artifact: .bionic/docs/record/accepted.md\nSuites: tests/widget.test.sh"
        | .tool_input.name = "accepted" | .tool_use_id = "toolu_01ACCEPT"' \
  | "${NENV[@]}" bash "$PARTY_DP" >/dev/null 2>&1
expect_eq "an accepted dispatch draws exactly one row from the wall" "1" \
  "$(grep -cF '|name=accepted|' "$NGH/.bionic/tmp/roster-$SID_A.state" 2>/dev/null)"
jq -n --arg s "$SID_A" --arg c "$NGH" \
  '{session_id:$s, transcript_path:"/irrelevant.jsonl", cwd:$c,
    hook_event_name:"PostToolUse", tool_name:"Agent",
    tool_input:{description:"a dispatch", prompt:"go", subagent_type:"implementor",
                run_in_background:true, name:"accepted"},
    tool_response:{isAsync:true, status:"async_launched", agentId:"aaccepted-2222222222222222"},
    tool_use_id:"toolu_01ACCEPT"}' | bash "$PARTY_ER" >/dev/null 2>&1
expect_eq "…and the recorder advances it rather than ignoring the roster" "1" \
  "$(grep -cF '|status=confirmed|' "$NGH/.bionic/tmp/roster-$SID_A.state" 2>/dev/null)"

# ------------------------------------- N.6 the launch reference: written once, read by three
#
# w2-s6 §6 rows 1 and 2, driven as one arc because they are two halves of one property. The
# roster row is written by `hooks/dispatch-preflight.sh`, carried forward and pinned by
# `hooks/execution-recorder.sh`, and DATED AGAINST by `hooks/session-sweeper.sh` — three
# scripts, one field, and S6 could only prove the middle one from inside its own suite.
#
# THE FIELD-SHAPE HALF FIRST (row 2), because the rest is meaningless without it: a silent
# rename of `launched_at=` at the writer would make the pin scan for a key that no longer
# exists and FAIL OPEN — find nothing, treat every resume as a new agent, restore the exact
# bug S6 fixed, and stay green everywhere. This is what makes that rename fail loud.
# THE KEYS COME FROM THE WRITER, DRIVEN — not from a format string read out of the hook.
# Until S14 this scraped `ROW="roster-state/` from `hooks/dispatch-preflight.sh`, which is
# how it could report "the mutation target matched nothing" the moment the row moved. The
# row now has one writer, `roster_row` (payload/scripts/lib/roster.sh), and the honest way to
# ask what keys it emits is to run it. `$( … )` is a subshell, so the library never leaks
# into the rest of this suite and a mutated copy is a real substitution.
N_ROSTER_LIB="$BIONIC_HOOKS_DIR/../payload/scripts/lib/roster.sh"
[ -r "$N_ROSTER_LIB" ] || N_ROSTER_LIB="$BIONIC_HOOKS_DIR/../scripts/lib/roster.sh"
n_row_keys() {  # <library> -> the keys the row carries, in order, as the writer emits them
  ( . "$1" >/dev/null 2>&1 && roster_row status=probe ) \
    | tr '|' '\n' | sed -n 's/^\([a-z_]*\)=.*/\1/p' | tr '\n' ' ' | sed 's/ $//'
}
N_KEYS=$(n_row_keys "$N_ROSTER_LIB")
expect_contains "the writer's row carries launched_at at all" "launched_at" "$N_KEYS"
# Proven loud by mutation: rename the key at the writer and the assertion above is the one
# that goes red — a suite failure, not a silent fail-open at 3am. Only the EMITTED field is
# renamed (`|launched_at=`, which appears once, in the row `roster_row` builds); renaming the
# variable too would leave the mutant unable to run and prove nothing about the key.
mkdir -p "$SANDBOX/fx"
N_MUT_LIB="$SANDBOX/fx/renamed-roster.sh"
anchor file payload/scripts/lib/roster.sh '|launched_at='
sed 's/|launched_at=/|launchedat=/' "$N_ROSTER_LIB" > "$N_MUT_LIB"
if cmp -s "$N_ROSTER_LIB" "$N_MUT_LIB"; then
  no "the launched_at rename applies to the roster writer" \
     "the mutation target matched nothing — the row moved and this proof is vacuous"
else
  ok "the launched_at rename applies to the roster writer"
fi
# AND THE KEY REALLY LEAVES THE ROW. The `cmp` above only says the edit landed somewhere;
# this says the writer stopped emitting the field, which is the state that would fail open.
N_MUT_KEYS="$(n_row_keys "$N_MUT_LIB")"
expect_eq "…and the mutant's row no longer carries launched_at at all" "0" \
  "$(printf '%s\n' "$N_MUT_KEYS" | tr ' ' '\n' | LC_ALL=C grep -c '^launched_at$' | tr -d ' ')"
# Non-vacuity: the same count over the SHIPPED writer's keys is one, so the zero above is a
# fact about the mutant and not about the counting.
expect_eq "…while the shipped writer's row carries it exactly once" "1" \
  "$(printf '%s\n' "$N_KEYS" | tr ' ' '\n' | LC_ALL=C grep -c '^launched_at$' | tr -d ' ')"

# THE END-TO-END HALF (row 1): every writer real, every reader real, and the observable is the
# VERDICT rather than the roster row — which is the gap S6's own suite could not close, since
# it owns the recorder and not the thing that reads it.
NLR=$(new_repo "launch-ref")
write_live_plan "$NLR/.bionic/docs/plans/epic-99/wave-01.md" "current: 4"
NLR_ART="$NLR/.bionic/docs/record/resumed.md"
mkdir -p "$NLR/.bionic/docs/record"
NLR_ID="aresumed-3333333333333333"

n_cycle() {  # <tool_use_id> — one full dispatch cycle through all three real hooks
  jq -n --arg s "$SID_A" --arg c "$NLR" --arg u "$1" --arg d "$NLR_ART" \
    '{session_id:$s, transcript_path:"/irrelevant.jsonl", cwd:$c,
      hook_event_name:"PreToolUse", tool_name:"Agent",
      tool_input:{description:"a dispatch", subagent_type:"implementor", name:"resumed",
                  prompt:("Expected artifact: " + $d + "\nDone marker: " + $d + ".done\nSuites: tests/widget.test.sh")},
      tool_use_id:$u}' | "${NENV[@]}" bash "$PARTY_DP" >/dev/null 2>&1
  jq -n --arg s "$SID_A" --arg c "$NLR" --arg u "$1" --arg a "$NLR_ID" \
    '{session_id:$s, transcript_path:"/irrelevant.jsonl", cwd:$c,
      hook_event_name:"PostToolUse", tool_name:"Agent",
      tool_input:{description:"a dispatch", prompt:"go", subagent_type:"implementor",
                  run_in_background:true, name:"resumed"},
      tool_response:{isAsync:true, status:"async_launched", agentId:$a},
      tool_use_id:$u}' | bash "$PARTY_ER" >/dev/null 2>&1
  mk_start_payload "$SID_A" "/irrelevant.jsonl" "$NLR" "resumed" "$NLR_ID" \
    | bash "$PARTY_ER" >/dev/null 2>&1
}
n_state() {  # -> the verdict's state for the row, over the live roster
  ( cd "$NLR" && CLAUDE_CODE_SESSION_ID="$SID_A" bash "$SWEEPER" verdict resumed 2>/dev/null ) \
    | grep -F 'landing-verdict/v1|' | head -1 | tr '|' '\n' | grep '^state=' | cut -d= -f2-
}
n_latest_row() {  # -> the last row the real recorder wrote for this name
  grep -F '|name=resumed|' "$NLR/.bionic/tmp/roster-$SID_A.state" | tail -1
}
# THE READER, ASKED ABOUT ONE ROW. The row handed over is the REAL recorder's own output
# line, copied verbatim onto a fresh roster — not a hand-built fixture — because the
# discriminating question here is what a reader makes of the row the resume produced, and on
# the live roster that same reader answers AMBIGUOUS about the NAME (see below) whatever the
# row says. This is `latest_rows`' fold with the two-contract count removed, and nothing else.
n_state_of_row() {  # <roster row> -> the verdict's state for it alone
  local d="$SANDBOX/fx/lr-fold"
  rm -rf "$d"; mkdir -p "$d/.bionic/tmp"
  git -C "$d" init -q 2>/dev/null
  roster_header \
    > "$d/.bionic/tmp/roster-$SID_A.state"
  printf '%s\n' "$1" >> "$d/.bionic/tmp/roster-$SID_A.state"
  ( cd "$d" && CLAUDE_CODE_SESSION_ID="$SID_A" bash "$SWEEPER" verdict resumed 2>/dev/null ) \
    | grep -F 'landing-verdict/v1|' | head -1 | tr '|' '\n' | grep '^state=' | cut -d= -f2-
}

n_cycle toolu_01CYCLEA
# THE ROSTER IS AGED, and only the roster: both cycles would otherwise be stamped in the same
# second and there would be no difference for the pin to preserve. An hour between a dispatch
# and its resume is the field case's own shape (`record/w1-rc-verify-floor.md` §Amendment-2),
# and every hook that reads these rows below is the real one reading a real row.
N_T0=$(date -u -v-3600S +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "-3600 seconds" +%Y-%m-%dT%H:%M:%SZ)
sed -i.bak -E "s/launched_at=[^|]*/launched_at=$N_T0/" "$NLR/.bionic/tmp/roster-$SID_A.state"
rm -f "$NLR/.bionic/tmp/roster-$SID_A.state.bak"
# The takeover's delivery: written between the original launch and the resume, which is the
# artifact the field case's landing gate called missing.
echo "the takeover wrote this" > "$NLR_ART"
: > "$NLR_ART.done"   # the agent says so, by the Done marker its brief declared (wave-24 T9, D3)
touch -t "$(date -v-1800S +%Y%m%d%H%M.%S 2>/dev/null || date -d "-1800 seconds" +%Y%m%d%H%M.%S)" "$NLR_ART"
expect_eq "before the resume, the delivered contract reads MET" "MET" "$(n_state)"

n_cycle toolu_01CYCLEB
N_RESUMED_ROW=$(n_latest_row)
expect_eq "the resume kept the ORIGINAL launch reference, through the real hooks" "$N_T0" \
  "$(printf '%s' "$N_RESUMED_ROW" | tr '|' '\n' | grep '^launched_at=' | cut -d= -f2-)"
# RE-POINTED (T22). This "resume" is a BARE second SubagentStart: cycle B's Agent payload
# carries a tool_use_id no dispatch row exists for, so ARM 2 journals nothing and the last
# row of the id is still `identified` when the start arrives. That is the resumed-copy shape
# exactly, and the recorder now journals it `duplicate-start` instead of appending a second
# identified row. The claim the case came for is unchanged — the row is an APPEND, nothing is
# rewritten — and it is now asserted over the row the second start actually wrote.
expect_eq "…and appended its own row rather than rewriting one" "1" \
  "$(grep -cF '|status=duplicate-start|' "$NLR/.bionic/tmp/roster-$SID_A.state")"
expect_eq "…leaving the identified row it did not rewrite" "1" \
  "$(grep -cF '|status=identified|' "$NLR/.bionic/tmp/roster-$SID_A.state")"
N_RESUMED_ROW=$(grep -F '|status=identified|' "$NLR/.bionic/tmp/roster-$SID_A.state" | tail -1)
expect_eq "…so the reader still calls the delivered contract MET over that row" \
  "MET" "$(n_state_of_row "$N_RESUMED_ROW")"

# WHAT THE LIVE ROSTER SAYS, and it is not MET — recorded here because it is the thing no
# component suite could see, and because the honest answer is worth more than a green line.
#
# A resume through the real hook path is a SECOND Agent-tool cycle, so it writes a second
# `tool_use_id` under one name, and `verdict` counts contracts by distinct tool_use_id
# (wave-01 Step-6 review C-2: two dispatches sharing a name are indistinguishable to every
# reader downstream). The name therefore reads AMBIGUOUS, not MET, and no row is judged.
#
# THE FAIL DIRECTION IS THE SAFE ONE and that is why this is pinned rather than fixed here:
# the landing gate PASSES an AMBIGUOUS name (§J's `dup` row), so R6 holds — work delivered
# before a resume still cannot be read as undelivered, and the gate still cannot manufacture
# an UNMET over an artifact that exists. What is lost is only the sharpness of AC-5's "yields
# MET": through this route it yields "not judged". Reconciling C-2's contract count with S6's
# resume (same agent id, two tool_use_ids — arguably ONE contract resumed, not two dispatched)
# is a change to a wave-01 remediation and to S6's own keying rule, which is a cross-task
# decision this task surfaces rather than takes.
# THE RECORDED FINDING IS CLOSED (T22). It read AMBIGUOUS because the second start appended a
# second contract-shaped row under one name and `verdict` counts contracts. A
# `duplicate-start` row is a status no reader in the fleet recognises — it is inert to the
# verdict, to the budget, to the sweep and to both stop gates, and visible only to the tick —
# so one name now carries one contract again and the name reads MET. What was pinned as an
# honest loss of AC-5's sharpness is pinned here as its recovery.
expect_eq "on the LIVE roster the resumed name now reads MET (the recorded finding is closed)" \
  "MET" "$(n_state)"

# THE DISCRIMINATING HALF, by mutation of the middle party: with the override removed the
# resume re-stamps, the artifact predates the fresh stamp, and the verdict manufactures the
# UNMET the field case actually suffered. This is the assertion that proves the three above
# are about the pin rather than about a fixture that could never have failed.
N_MUT_ER="$SANDBOX/fx/unpinned-recorder.sh"
anchor file hooks/execution-recorder.sh 'PRIOR_LAUNCH=$(prior_launch_for_agent "$ROW_AGENT_ID")'
anchor file hooks/execution-recorder.sh 'PRIOR_LAUNCH=$(prior_launch_for_agent "$START_ID")'
awk '{ if (index($0, "PRIOR_LAUNCH=$(prior_launch_for_agent \"$ROW_AGENT_ID\")") > 0 || index($0, "PRIOR_LAUNCH=$(prior_launch_for_agent \"$START_ID\")") > 0)
         sub(/prior_launch_for_agent/, "true prior_launch_for_agent")
       print }' "$BIONIC_HOOKS_DIR/execution-recorder.sh" > "$N_MUT_ER"
expect_eq "the mutation really applies (the mutant is not the shipped recorder)" "no" \
  "$(cmp -s "$BIONIC_HOOKS_DIR/execution-recorder.sh" "$N_MUT_ER" && echo yes || echo no)"
n_saved_er="$PARTY_ER"; PARTY_ER="$N_MUT_ER"
n_cycle toolu_01CYCLEC
PARTY_ER="$n_saved_er"
# RE-POINTED, AND THE FINDING IS STRONGER THAN THE PIN IT REPLACES (T22).
#
# The mutation removes the launch-reference override, so a resume that IDENTIFIES re-stamps
# `launched_at` and the delivered artifact reads stale — the field case. It cannot reach that
# state any more, and not because the pin got weaker: a bare repeat start for an id whose
# last row is already `identified` no longer writes a contract row AT ALL. It writes a
# `duplicate-start` row, a status no verdict reader recognises, so there is no fresh launch
# reference for the mutation to move and the delivered contract still reads MET.
#
# What is asserted here is therefore the immunity itself, with its mechanism named: the
# mutant recorder ran (above), it wrote its row, and the row it wrote is inert.
# ASSERTED AT THE MECHANISM, not at a row count: the claim is that no row on this roster
# carries a launch reference other than the original, which is the fact the field case turned
# on. A mutant that had re-stamped one would put a second `launched_at=` value here.
expect_eq "…and no row on the roster carries a launch reference the mutation moved" \
  "1" "$(grep -oE 'launched_at=[^|]*' "$NLR/.bionic/tmp/roster-$SID_A.state" \
         | sort -u | grep -c .)"
expect_eq "…so the SAME delivered artifact is still MET — the field case is unreachable" \
  "MET" "$(n_state)"

# ============================================================
section "O — session-poker's copied primitives, CODE-identical (6-axis D-1)"
# ============================================================
#
# hooks/session-poker.sh's own header declared five functions "DELIBERATELY DUPLICATED from
# hooks/session-sweeper.sh, byte for byte" and called parse_seconds's copy "verbatim" —
# rd review D-1 (blocking-grade): nothing anywhere compared a single copy, and the
# "verbatim" claim was already false. `parse_seconds`'s SWEEPER copy carries nine lines of
# internal rationale comments (why "0.5h" and "1h30m" are refused) that the POKER copy
# drops, because that rationale describes the sweeper's own history — reading `cadence=` —
# which this script never does; it reads `duration=` instead. The §I.1 precedent this loop
# follows already excludes SIGNATURE comments from its body comparison ("each file explains
# its copy in its own terms"); this loop goes one step further and excludes every
# pure-comment line inside the body too, because parse_seconds is the one primitive here
# whose internal comments are legitimately script-specific. What must not drift silently is
# the EXECUTABLE TEXT, so that is what is compared — epic-16 w2 Step-6 remediation R3, and
# the two header comments this closes (session-poker.sh:84-88, :109-111) now say exactly
# this: code-identical, not byte-identical (R-3).
SPO="$BIONIC_HOOKS_DIR/session-poker.sh"

# (hoisted to tests/cross-gate-agreement.prelude.sh, which part 2 reads: fn_code)

# THE LOOP THE COMMENT ABOVE PROMISED (wave-01 S11, A-25). Until this task this section
# defined fn_code, said what the comparison would show, and made no comparison at all — an
# agreement suite asserting nothing, which is this wave's thesis in miniature. The five the
# comment spoke of is SEVEN as measured: every function hooks/session-poker.sh's own
# "DELIBERATELY DUPLICATED" header block introduces has a same-named copy in
# hooks/session-sweeper.sh, and all seven agree as code today. (session-poker.sh's own
# header called the family "the six" — one short of the file — from S11's measurement until
# the F2 fold-in (item 12) corrected it to "the seven" at session-poker.sh:426. The comment
# and this measurement agree now; the discrepancy this parenthetical used to report is gone.)
#
# SIX SINCE wave-39 T17 (D18, AC-12.1; A-orch-66): iso_epoch left the family. The poker's copy is now the one-line call
# to lib/time.sh `_time_epoch`, the one reader of an instant (strict `…Z`; tests/time.test.sh §AGREE holds it to its
# former callers), and the sweeper keeps its `date` copy because it sources no library. Comparing the two would pin
# the poker back to the reader the fold retired.
SPO_DUPES="now_epoch iso_now file_mtime line_field clean parse_seconds"

for _fn in $SPO_DUPES; do
  _poke_code="$(fn_code "$SPO" "$_fn")"
  _swee_code="$(fn_code "$SWEEPER" "$_fn")"
  # EXTRACTED, NOT MISSING. fn_code returns the empty string for a name neither file
  # defines, and two empty strings compare equal — the vacuity the comment below warns
  # about, made impossible per function rather than argued away.
  expect_nonempty "§O the poker's ${_fn}() body is extractable at all" "$_poke_code"
  expect_nonempty "§O the sweeper's ${_fn}() body is extractable at all" "$_swee_code"
  expect_eq "§O the poker's ${_fn}() is the sweeper's, code for code" "$_swee_code" "$_poke_code"
done

# The discriminating half: parse_seconds is NOT byte-identical (the comments legitimately
# differ), which is the whole reason this loop compares code rather than bytes. Without this
# the six expect_eq's above could be silently vacuous by fn_code stripping everything.
expect_ne "§O parse_seconds is NOT byte-identical — the comments legitimately differ" \
  "$(fn_body "$SWEEPER" parse_seconds)" "$(fn_body "$SPO" parse_seconds)"
expect_eq "§O …and it IS code-identical, which is what the loop above compares" \
  "$(fn_code "$SWEEPER" parse_seconds)" "$(fn_code "$SPO" parse_seconds)"
# …and the byte difference really is comments alone: the two bodies differ, and every line
# present in one and absent from the other starts with `#`.
expect_empty "§O …and every line the two bodies differ by is a comment line" \
  "$(diff <(fn_body "$SWEEPER" parse_seconds) <(fn_body "$SPO" parse_seconds) \
      | grep -E '^[<>]' | sed 's/^[<>] //' | grep -v '^#')"
expect_nonempty "§O …over a diff that really is non-empty (the filter is not eating it all)" \
  "$(diff <(fn_body "$SWEEPER" parse_seconds) <(fn_body "$SPO" parse_seconds) | grep -cE '^[<>]')"

# THE MUTATION ARM. A pin over two files that agree today passes just as loudly if the
# comparison itself is broken, so one copy is DOCTORED in a scratch tree and the same
# comparison is re-run against it: the `return 0` after the first match is dropped inside
# line_field, which is a real drift shape (the walk goes on and prints every `<key>=` field, so
# the two readers would disagree about which of two rows a key comes from — the drift the
# `head -1` → `tail -1` mutation stood for while the body was a pipeline, before wave-34 T11).
# The shipped files are never written to.
SPO_MUT="$SANDBOX/o-mutant-poker.sh"
# The needle is `line_field`'s first-match return, and it occurs exactly once in the file. That count is this mutation's PRECONDITION and it is declared through
# the framework's `anchor` (§S19): a sed whose target had moved would leave an identical
# copy and every row after it would be vacuous, and the anchor names the pattern and the
# count it actually found rather than only reporting that the bytes came out equal.
SPO_NEEDLE='"${_lf_f#"$2="}"; return 0 ;;'
SPO_MUT_NEEDLE='"${_lf_f#"$2="}" ;;'
anchor file hooks/session-poker.sh '"${_lf_f#"$2="}"; return 0 ;;'
sed "s@$(printf '%s' "$SPO_NEEDLE" | sed 's/[\\&@]/\\&/g')@$(printf '%s' "$SPO_MUT_NEEDLE" | sed 's/[\\&@]/\\&/g')@" \
  "$SPO" > "$SPO_MUT"
expect_ne "§O …and the SAME comparison calls the doctored copy a drift" \
  "$(fn_code "$SWEEPER" line_field)" "$(fn_code "$SPO_MUT" line_field)"
expect_eq "§O …while every OTHER primitive in the doctored copy still agrees (one row moved, not all)" \
  "$(fn_code "$SWEEPER" parse_seconds)" "$(fn_code "$SPO_MUT" parse_seconds)"

# ============================================================
section "P — the three roster folds agree that the LATER row wins (ap review P-1)"
# ============================================================
#
# The roster is append-only and a contract advances along it (`intended` → `confirmed` →
# `identified`), every writer copying the contract fields forward — so the LAST row carrying
# a name is the authoritative one. Three scripts fold the file on that rule and none of them
# can share code with the others (there is no library in this repo by decision, and each
# fold answers its own caller: hooks/session-sweeper.sh latest_rows also counts contracts
# and filters by session; hooks/session-poker.sh takes one row by name; hooks/stop-orders.sh
# needs a whole batch at once and, since epic-16 w2 Step-6 remediation R4, folds ONCE
# instead of re-walking the file per verdict row — the fix for P-1, whose per-row re-walk
# cost ~14·N² processes and 63 s at N=100).
#
# A code-comparison loop like §O cannot hold these three together, because they are
# legitimately different code. This is the behavioural equivalent: ONE roster in which a
# name appears TWICE, and all three asked what they see. A fold that silently starts taking
# the FIRST row — the plausible drift, and the one an off-by-one in a rewrite produces —
# turns this section red in three places at once.
#
# Overridable for the same reason the parties at the top of this file are: the
# discrimination proof for this section is a MUTATED copy of one fold — made to take the
# first row instead of the last — driven against the same fixture, with the shipped files
# never touched. A mutant copy must sit in a directory that also carries session-sweeper.sh,
# since both scripts resolve it as a sibling:
#   W2_PARTY_ORD=/tmp/mut/stop-orders.sh bash tests/cross-gate-agreement.test.sh
PORD="${W2_PARTY_ORD:-$BIONIC_HOOKS_DIR/stop-orders.sh}"
PPOKE="${W2_PARTY_POKE:-$BIONIC_HOOKS_DIR/session-poker.sh}"
PREPO=$(new_repo "fold-agreement")
mkdir -p "$PREPO/.bionic/tmp" "$PREPO/.bionic/docs/record"
PROSTER="$PREPO/.bionic/tmp/roster-$SID_A.state"
P_LANDED="$PREPO/.bionic/docs/record/p-landed.md"
printf 'landed\n' > "$P_LANDED"
P_OLD=$(date -u -v-100000S +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
        || date -u -d '-100000 seconds' +%Y-%m-%dT%H:%M:%SZ)
P_NEW=$(date -u -v-60S +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
        || date -u -d '-60 seconds' +%Y-%m-%dT%H:%M:%SZ)

p_row() {  # <name> <deliverable> <duration> <launched_at> <teammate_id>
  roster_row_fixture status=confirmed session="$SID_A" name="$1" agent_id= \
    launched_at="$4" deliverable="$2" duration="$3" teammate_id="$5" \
    tool_use_id="toolu_P$1"
}

roster_header \
  > "$PROSTER"
# dup-open: the EARLIER row would read as landed and unhurried (a delivered artifact, four
# hours to do it, launched a minute ago); the LATER row is the true contract and is neither.
p_row dup-open "$P_LANDED"                "4 hours"  "$P_NEW" "first@session-p"  >> "$PROSTER"
p_row dup-open "$PREPO/never-written.md"  "1 minute" "$P_OLD" "second@session-p" >> "$PROSTER"
# dup-landed: both rows have landed, so the row that wins is visible in the ADDRESS the
# stand-down prints — the one field standdown reads off the roster for a landed row.
p_row dup-landed "$P_LANDED" "4 hours" "$P_NEW" "first@session-p"  >> "$PROSTER"
p_row dup-landed "$P_LANDED" "4 hours" "$P_NEW" "second@session-p" >> "$PROSTER"


P_VERDICT=$( cd "$PREPO" && CLAUDE_CODE_SESSION_ID="$SID_A" bash "$SWEEPER" verdict 2>/dev/null )
# PARTY 1 — the sweeper latest_rows. The earlier row points at a file that EXISTS; reading
# it would make this row MET.
expect_contains "the sweeper judges dup-open from the LATER row (UNMET, not the earlier landed one)" \
  "|name=dup-open|state=UNMET|" "$P_VERDICT"
expect_contains "…and its detail names the LATER row deliverable" \
  "never-written.md" "$P_VERDICT"

# PARTY 2 — the poker per-row lookup. `duration=`/`launched_at=` come from the roster, not
# from the verdict line: the earlier row (four hours, launched a minute ago) is nowhere near
# due, the later one (one minute, launched a day ago) is long past.
P_TICK=$( cd "$PREPO" && CLAUDE_CODE_SESSION_ID="$SID_A" bash "$PPOKE" tick 2>&1 )
expect_contains "the poker reads dup-open duration off the LATER row (NOTIFY, not QUIET)" \
  "decision=NOTIFY" "$P_TICK"
expect_contains "…naming that row" "rows=dup-open" "$P_TICK"

# PARTY 3 — stop-orders single pre-loop fold. Both dup-landed rows have landed, so the
# stand-down prints an address, and the address is the discriminator.
P_STAND=$( cd "$PREPO" && CLAUDE_CODE_SESSION_ID="$SID_A" bash "$PORD" standdown 2>&1 )
# The stand-down must still leave the unlanded row alone, folded or not.
expect_contains "…while dup-open is left alone, not stood down" "LEFT ALONE" "$P_STAND"

# PARTY 4 — landing-gate.sh's OWN copy of the fold (t6-review.md F-3: a fourth "later row
# wins" implementation, outside this section until now). It needs an active wave to reach
# its fold at all, which the three parties above do not. The fixture mirrors dup-open's own
# shape: an EARLIER row that declares NO deliverable (so a fold that took the FIRST row
# would drop the contract entirely — `if (dl[nm] == "") continue`) and a LATER row that
# declares a genuinely missing one — so the correct (last-row-wins) fold refuses, and a
# first-row-wins drift passes the same contract silently.
p_lg_fixture() {  # <repo> -> an active wave + an lg-dup roster, earlier row bare
  mkdir -p "$1/.bionic/tmp" "$1/.bionic/docs/record"
  write_plan "$1/.bionic/docs/plans/epic-99/wave-01.md" "current: 4"
  {
    roster_header
    # SAME tool_use_id on both rows — the real writers (dispatch-preflight, then
    # execution-recorder at confirm/identify) never mint a second one for the same
    # dispatch, and the sweeper's OWN fold counts distinct tool_use_id as distinct
    # CONTRACTS: two different ids here would read as an unrelated second dispatch
    # sharing a name (AMBIGUOUS, §N's `dup` shape) rather than the SAME contract's
    # two rows, which is what this fixture is about.
    p_row lg-dup "" "1 minute" "$P_NEW" "" | sed "s/agent_id=|/agent_id=alg-dup-early001|/"
    roster_row_fixture status=confirmed session="$SID_A" name=lg-dup \
      agent_id=alg-dup-late0001 launched_at="$P_NEW" \
      deliverable="$1/.bionic/docs/record/lg-never-written.md" duration="1 minute" \
      teammate_id= tool_use_id=toolu_Plg-dup
  } > "$1/.bionic/tmp/roster-$SID_A.state"
}

PLGREPO=$(new_repo "fold-agreement-lg")
p_lg_fixture "$PLGREPO"
PLG_ROSTER="$PLGREPO/.bionic/tmp/roster-$SID_A.state"

LG_OUT=$( mk_stopsweep_payload "$PLGREPO" "$SID_A" false | bash "$PARTY_LG" 2>&1 ); LG_RC=$?
expect_eq "landing-gate joins §P: it refuses lg-dup, folding to the LATER row (the genuinely missing artifact)" \
  "2" "$LG_RC"
LG_MARK=$(grep -F '|name=lg-dup|' "$PLG_ROSTER" | grep -F "${SWEPT_SCHEMA}|" | tail -1)
expect_contains "…and the roster marker is keyed to the LATER row agent_id" \
  "agent_id=alg-dup-late0001" "$LG_MARK"

# THE DISCRIMINATING HALF: a copy of landing-gate.sh mutated to take the FIRST row's
# deliverable instead of the last, sibling of a real sweeper, driven against an identical
# fresh fixture (a fresh repo, so the real run's marker above cannot mask the mutant's
# silence).
LG_MUT_HOOK="$(plant_lg_tree "$SANDBOX/fx/lg-first-wins")"
LG_MUT_DIR="${LG_MUT_HOOK%/stop.sh}"
cp "$SWEEPER" "$LG_MUT_DIR/session-sweeper.sh"
anchor insert payload/scripts/lib/stop.sh '    dl[name] = deliv'
awk '{
       if ($0 == "    dl[name] = deliv") {
         print "    if (!(name in dl)) dl[name] = deliv"
         next
       }
       print
     }' "$PARTY_LG_SRC" > "$LG_MUT_DIR/../scripts/lib/stop.sh"

PLGREPO2=$(new_repo "fold-agreement-lg-mut")
p_lg_fixture "$PLGREPO2"
PLG_ROSTER2="$PLGREPO2/.bionic/tmp/roster-$SID_A.state"
lg_saved="$PARTY_LG"; PARTY_LG="$LG_MUT_HOOK"
LG_MUT_OUT=$( mk_stopsweep_payload "$PLGREPO2" "$SID_A" false | bash "$PARTY_LG" 2>&1 ); LG_MUT_RC=$?
PARTY_LG="$lg_saved"
expect_eq "…and with the fold flipped to first-row-wins, the SAME contract passes SILENTLY (§P discriminates)" \
  "0" "$LG_MUT_RC"

# ============================================================
section "Q — has_sdlc_state() has NO carrier left: the library is the only reader"
# ============================================================
#
# It was a five-copy family: the evidence gate held the origin (the file documenting the
# fence-aware, CR-normalizing contract at its definition site) and the dispatch wall,
# stop-guard, execution-recorder and the landing gate each carried a byte-identical twin.
# This section compared them body for body, which is the strongest thing a suite can do
# about a duplication it cannot remove.
#
# It could be removed (bionic 1.4.0, task ADOPT). The predicate is `lib/run.sh`'s
# `active_plan`, every one of the five asks for it, and §A2 above proves the asking is
# real by mutating the library and watching all five answers move. One straggler survived
# that task — hooks/session-poker.sh, whose tick carried its own copy — and this section
# NAMED it rather than excusing it. Task SCHED deleted it (POKER/2, ratified 2026-09-03),
# so the count this pin asserts is now ZERO. An empty answer is a weak assertion on its
# own, which is why the two rows below it are the ones with teeth: the library defines the
# predicate, and the tick reaches it by CALLING that function rather than by restating it.
Q_CARRIERS=$(/usr/bin/grep -ln '^has_sdlc_state()' "$BIONIC_HOOKS_DIR"/*.sh 2>/dev/null \
  | while IFS= read -r _f; do basename "$_f"; done | sort | tr '\n' ' ' | sed 's/ $//')
expect_eq "NO hook defines has_sdlc_state() any more — the family is gone, not shrunk" \
  "" "$Q_CARRIERS"
# TWO NAMES, AND EACH STANDS FOR A DIFFERENT ARM (wave-session-bound-run). The tick's own
# question moved from `active_plan` (which plan is newest in this ROOT) to `session_run`
# (which plan is THIS SESSION's), so `session_run` is what "asks the library by name" means
# for the tick now. The `active_plan` call did not go away and must not: it is
# `resolve_run`'s `none` arm, the one that keeps DISARM reachable for an unbound session
# whose run has already closed (S6 finding A, tests/session-poker.test.sh §18d). Pinning
# only the survivor would pass a tick that had stopped asking whose run it is in.
expect_eq "…and the tick, the last carrier, asks the library by name instead" "yes" \
  "$(/usr/bin/grep -q 'session_run "' "$BIONIC_HOOKS_DIR/session-poker.sh" && echo yes || echo no)"
expect_eq "…and keeps active_plan for the unbound-and-closed arm alone" "yes" \
  "$(/usr/bin/grep -q 'active_plan "' "$BIONIC_HOOKS_DIR/session-poker.sh" && echo yes || echo no)"
expect_eq "…and the evidence gate, which held the origin, no longer carries one" "" \
  "$(fn_body "$PARTY_EG" has_sdlc_state)"
expect_eq "…while the library defines the predicate it replaced them with" "yes" \
  "$(/usr/bin/grep -q '^active_plan()' "$BIONIC_HOOKS_DIR/../payload/scripts/lib/run.sh" && echo yes || echo no)"

# ============================================================
section "Roots — one resolver per root, one definition each (epic-22 wave-01, AC-N1.1/N1.2)"
# ============================================================
#
# WHAT THIS REPLACES. §R held FOUR copies of `resolve_docs_root()` — the evidence gate as
# designated origin, plus the governing-skill hook, the sweeper and stop-check — to one
# text, body for body, with a mutation arm proving the comparison discriminated. It could
# not see a fifth: its count globbed `"$BIONIC_HOOKS_DIR"/*.sh`, and `docs_root()` in
# payload/scripts/lib/run.sh answered the same question under another name, outside the
# glob. That is the shape a body-for-body wall has: it holds the copies it was told about.
#
# THERE ARE NO COPIES NOW. payload/scripts/lib/roots.sh owns one resolver per root and every
# former carrier is a caller, so the question this section asks is not "do the copies agree"
# but "is there still exactly one of each" — over hooks/, payload/scripts/ AND
# payload/scripts/lib/, which is what §R's glob could not reach.
#
# THE DISAGREEMENT §R ENDED, kept here because it is why any of this is pinned. A brief
# writes `Expected artifact: record/epic-17-w6/x.md` because that is the spelling the Step-5
# contract and canonical-sdlc-evidence-gate.sh publish for an artifact under the docs root.
# The gate resolved it there. hooks/session-sweeper.sh resolved it against the REPO root and
# reported the row missing; hooks/stop-check.sh resolved it against the observer's cwd and
# printed `progress_state=absent` for a file that was present. Three readers of one
# sentence, two of them wrong — and one task then wrote a duplicate copy at the repo root
# to satisfy the gate, so the wrong reader taught the work to be wrong too.
#
# STILL OUT OF SCOPE, and named so a later reader does not mistake absence for oversight:
# `resolve_walk_path()` in the gate and `abs_path()` in two hooks (same body, different
# name — the `clean()`/`mline_value()` precedent in §N.1), and the governing-skill hook's
# deliberately WIDER `resolve_design_path()`, which adds specs/plans/adrs/incidents/ leaders
# on top of `record/`. Those are path-SHAPE resolvers, not roots.

ROOTS_LIB_DIR="$BIONIC_HOOKS_DIR/../payload/scripts/lib"
[ -d "$ROOTS_LIB_DIR" ] || ROOTS_LIB_DIR="$BIONIC_HOOKS_DIR/../scripts/lib"
ROOTS_SCRIPTS_DIR="$(dirname "$ROOTS_LIB_DIR")"

# roots_defcount <search root> <fn> -> how many files under it define <fn> at column 0.
# The three directories are named rather than globbed from a marker, for §N.1's reason: a
# glob that shrinks to nothing passes over air.
roots_defcount() {  # <tree root> <fn>
  local t="$1" fn="$2" hooks lib scripts
  hooks="$t/hooks"; lib="$t/payload/scripts/lib"; scripts="$t/payload/scripts"
  [ -d "$lib" ] || { lib="$t/scripts/lib"; scripts="$t/scripts"; }
  /usr/bin/grep -lE "^${fn}\(\)" \
    "$hooks"/*.sh "$scripts"/*.sh "$lib"/*.sh 2>/dev/null | sort -u | wc -l | tr -d ' '
}

ROOTS_TREE="$(cd "$BIONIC_HOOKS_DIR/.." && pwd -P)"
ROOTS_NAMES='project_root bionic_root docs_root tmp_root archive_root plugin_root claude_home worktree_root transcripts_dir config_value'

# --- (a) NON-VACUITY. The search set is real, and the library is inside it. Without this
# every count below could be 0 over an empty glob and read as "no duplicates". ---
expect_eq "Roots the search set is non-empty (this section is not counting over air)" "yes" \
  "$([ "$(ls "$ROOTS_TREE/hooks"/*.sh "$ROOTS_LIB_DIR"/*.sh 2>/dev/null | wc -l | tr -d ' ')" -gt 20 ] \
     && echo yes || echo no)"
expect_eq "Roots payload/scripts/lib/roots.sh is on disk" "yes" \
  "$([ -r "$ROOTS_LIB_DIR/roots.sh" ] && echo yes || echo no)"

# --- (b) THE COUNT. Exactly one definition of each name, anywhere in the tree. ---
for _rn in $ROOTS_NAMES; do
  expect_eq "Roots $_rn() is defined exactly once across hooks/, scripts/ and scripts/lib/" \
    "1" "$(roots_defcount "$ROOTS_TREE" "$_rn")"
done

# --- (c) WHERE THE ONE DEFINITION IS. Nine of the ten live in roots.sh. `project_root` is
# the deliberate exception: its implementation is lib/root.sh's ancestor walk, with its own
# suite (tests/root.test.sh) and the candidate tags doctor and the SessionStart report
# render, and roots.sh SOFT-SOURCES root.sh rather than restating it — re-defining it would
# be the second definition this section forbids. ---
for _rn in bionic_root docs_root tmp_root archive_root plugin_root claude_home worktree_root transcripts_dir config_value; do
  expect_eq "Roots …and $_rn()'s one definition is in roots.sh" "1" \
    "$(/usr/bin/grep -cE "^${_rn}\(\)" "$ROOTS_LIB_DIR/roots.sh")"
done
expect_eq "Roots project_root()'s one definition is root.sh's, and roots.sh re-exports it" "1" \
  "$(/usr/bin/grep -cE '^project_root\(\)' "$ROOTS_LIB_DIR/root.sh")"
expect_eq "Roots …by sourcing it, not by restating it" "1" \
  "$(grep -cF '/root.sh"' "$ROOTS_LIB_DIR/roots.sh")"

# --- (d) THE FIVE RETIRED DOCS-ROOT COPIES ARE CALLERS. §R's four carriers plus run.sh's
# `docs_root()`, the one §R could not see. Each defines nothing and calls the library. ---
# THE GATE'S HALF IS IN THE LIBRARY (T23) and is asked for there; the other three are
# still hooks. Each name below resolves to whichever file carries that body now.
# EACH NAME IS READ FROM THE FILE THAT CARRIES ITS BODY (T23): the evidence gate's half is
# `wall_evidence_gate` in payload/scripts/lib/walls.sh, the other three are still hooks.
roots_file_for() {  # <name> -> the path whose body carries that docs-root caller
  case "$1" in
    walls) printf '%s\n' "$ROOTS_LIB_DIR/walls.sh" ;;
    *)     printf '%s\n' "$ROOTS_TREE/hooks/$1.sh" ;;
  esac
}
for _rh in walls canonical-sdlc-governing-skill session-sweeper stop-check; do
  expect_eq "Roots $_rh.sh defines no resolve_docs_root of its own" "0" \
    "$(/usr/bin/grep -cE '^resolve_docs_root\(\)' "$(roots_file_for "$_rh")")"
  expect_eq "Roots …and calls the library's docs_root" "yes" \
    "$([ "$(/usr/bin/grep -cE '(^|[^a-z_])docs_root "' "$(roots_file_for "$_rh")")" -ge 1 ] \
       && echo yes || echo no)"
  # THE DECLARATION RULE, and why it is a disjunction. A hook reaches `docs_root` one of
  # two ways: it declares roots.sh through the loader idiom, or it declares run.sh, which
  # soft-sources roots.sh from its own directory. The second is not a loophole — it is the
  # shape lib/detect.sh already has for lib/deps.sh, and no hook in the tree declares
  # deps.sh either. What matters is that a hook does not reach a library it never named a
  # route to; a hook declaring NEITHER is the regression this row catches.
  # THE DECLARATION IS THE HOOK'S, NOT THE LIBRARY'S. A library file declares nothing —
  # the hook that sources it does — so a caller whose body lives in walls.sh is asked about
  # hooks/bash-walls.sh's own BIONIC_LIB_WANT line.
  _rh_decl="$ROOTS_TREE/hooks/$_rh.sh"
  [ "$_rh" = walls ] && _rh_decl="$ROOTS_TREE/hooks/bash-walls.sh"
  expect_eq "Roots …declaring a route to it, roots.sh or the run.sh that pulls it in" "yes" \
    "$([ "$(/usr/bin/grep -cE '^BIONIC_LIB_WANT=.*(roots\.sh|run\.sh)' "$_rh_decl")" -ge 1 ] \
       && echo yes || echo no)"
done

# The two hooks that source NEITHER run.sh nor any other carrier name roots.sh outright —
# without the declaration the loader would qualify a directory that has no roots.sh in it,
# and these two would resolve every contracted path against the wrong root in silence.
for _rh in session-sweeper stop-check; do
  expect_eq "Roots $_rh.sh names roots.sh outright — it sources no other carrier" "1" \
    "$(/usr/bin/grep -cE '^BIONIC_LIB_WANT="roots\.sh( |")' "$ROOTS_TREE/hooks/$_rh.sh")"
  expect_eq "Roots …and sources it" "1" \
    "$(grep -cF '. "$BIONIC_LIB/roots.sh"' "$ROOTS_TREE/hooks/$_rh.sh")"
  expect_eq "Roots …and really does not source run.sh (the disjunction above is not vacuous)" "0" \
    "$(/usr/bin/grep -cE '^BIONIC_LIB_WANT=.*run\.sh' "$ROOTS_TREE/hooks/$_rh.sh")"
done

# lib/run.sh IS the carrier the disjunction leans on: it soft-sources roots.sh at source
# time, so `. lib/run.sh` on its own is still a complete thing.
expect_eq "Roots lib/run.sh soft-sources roots.sh, which is what makes the route real" "1" \
  "$(grep -cF '/roots.sh"' "$ROOTS_LIB_DIR/run.sh")"
expect_eq "Roots …and sourcing run.sh alone really does define docs_root and config_value" "yes" \
  "$(bash -c '. "$1" >/dev/null 2>&1; declare -F docs_root >/dev/null 2>&1 && declare -F config_value >/dev/null 2>&1 && echo yes || echo no' _ "$ROOTS_LIB_DIR/run.sh")"
expect_eq "Roots lib/run.sh defines no docs_root of its own (the fifth copy, invisible to §R)" "0" \
  "$(/usr/bin/grep -cE '^docs_root\(\)' "$ROOTS_LIB_DIR/run.sh")"
expect_eq "Roots …and lib/run.sh defines no config_value of its own either" "0" \
  "$(/usr/bin/grep -cE '^config_value\(\)' "$ROOTS_LIB_DIR/run.sh")"

# --- (e) MUTATION, THE DISCRIMINATOR. Without this, (b) proves only that the tree currently
# has one of each — not that a SECOND one would be caught. A scratch copy of the tree gets a
# second definition planted in a file that has no business owning one, and the same count
# must come back 2. The shipped tree is never touched. Both directions are asserted: the
# planted name goes to 2 AND an unplanted name stays at 1, so a plant that accidentally
# broke the counter would not read as a pass. ---
ROOTS_MUT="$SANDBOX/roots-mutant"
mkdir -p "$ROOTS_MUT/hooks" "$ROOTS_MUT/payload/scripts/lib"
cp "$ROOTS_TREE/hooks"/*.sh "$ROOTS_MUT/hooks/" 2>/dev/null
cp "$ROOTS_LIB_DIR"/*.sh "$ROOTS_MUT/payload/scripts/lib/" 2>/dev/null
cp "$ROOTS_SCRIPTS_DIR"/*.sh "$ROOTS_MUT/payload/scripts/" 2>/dev/null

expect_eq "Roots the scratch copy starts clean (the mutation below is what moves the count)" "1" \
  "$(roots_defcount "$ROOTS_MUT" docs_root)"

# The plant is the exact regression this section exists to catch: a hook growing its own
# copy of the docs-root rule back, under the library's name.
cat >> "$ROOTS_MUT/hooks/session-sweeper.sh" <<'ROOTS_PLANT'

docs_root() {
  local proj="$1"
  echo "$proj/.bionic/docs"
}
ROOTS_PLANT

expect_eq "Roots …a SECOND docs_root planted in a hook makes the count go red" "2" \
  "$(roots_defcount "$ROOTS_MUT" docs_root)"
expect_eq "Roots …and an unplanted resolver is unaffected (the counter is per-name)" "1" \
  "$(roots_defcount "$ROOTS_MUT" claude_home)"

# The same proof one layer over, on a LIBRARY rather than a hook — the direction §R's
# hooks/-only glob was blind to, and the one that hid `docs_root()` in run.sh for a wave.
cat >> "$ROOTS_MUT/payload/scripts/lib/run.sh" <<'ROOTS_PLANT2'

claude_home() {
  printf '%s' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
}
ROOTS_PLANT2

expect_eq "Roots …a second claude_home planted in a LIBRARY goes red too" "2" \
  "$(roots_defcount "$ROOTS_MUT" claude_home)"

# --- ONE DEFINITION OF live_ids_of_name() (T6, A-orch-32; research R1 §5) --------------
#
# hooks/stop-guard.sh's stop-ambiguity refusal (T29 §7) and hooks/session-poker.sh's
# adopt_write_row (AC-6.1) both need the identical DISTINCT-id, MET-discharge answer to
# "is this name already live on this roster". T6 moved the one body out of stop-guard.sh
# into payload/scripts/lib/roster.sh so the two callers share it instead of drifting the
# way `roots_defcount` above exists to catch a second copy of any name doing.
expect_eq "live_ids_of_name() is defined exactly once across hooks/, scripts/ and scripts/lib/" \
  "1" "$(roots_defcount "$ROOTS_TREE" live_ids_of_name)"
expect_eq "…and that one definition is roster.sh's" "1" \
  "$(/usr/bin/grep -cE '^live_ids_of_name\(\)' "$ROOTS_LIB_DIR/roster.sh")"
expect_eq "…hooks/stop-guard.sh defines none of its own any more" "0" \
  "$(/usr/bin/grep -cE '^live_ids_of_name\(\)' "$ROOTS_TREE/hooks/stop-guard.sh")"
expect_eq "…and still calls it — the one call site is unchanged" "1" \
  "$(/usr/bin/grep -cE '(^|[^a-z_])live_ids_of_name \"' "$ROOTS_TREE/hooks/stop-guard.sh")"

# ============================================================
section "V — SUPPORTED_SDLC_VERSION: one owner, every code and SVG carrier agrees (AC-19)"
# ============================================================
#
# r3 §1E item 13: one logical constant, several renderings, and the two hooks were not held
# in agreement by anything until this section — the only prior test hit was a single
# spot-check literal in tests/canonical-sdlc-evidence-gate.test.sh.
#
# THE OWNER is canonical-sdlc-evidence-gate.sh (spec AC-19, provenance table): the one whose
# refusal message names the fix. The carriers restate it: the governing-skill hook's own copy
# and two SVG renderings — lifecycle.svg's title and hook-chain.svg's three
# `class="version-pin"` chips. A per-file suite cannot see this drift: each carrier reads fine
# on its own while they disagree. (Wave-31: the value operational-rules.md documented in
# prose is no carrier here; a test proves what a program does, never what a document says.)

# THE ORIGIN IS THE LIBRARY THE GATE'S BODY LIVES IN (T23): `SUPPORTED_SDLC_VERSION`
# is inside `_eg_body` in payload/scripts/lib/walls.sh, at column zero, and the hook beside
# it is preamble and a fold.
# (hoisted to tests/cross-gate-agreement.prelude.sh, which part 2 reads: V_ORIGIN, V_HOOKCHAIN, v_hook_val, V_ORIGIN_VAL, v_hookchain_vals, v_hc_chips_ok, v_hc_agree)
V_GSKILL="$BIONIC_HOOKS_DIR/canonical-sdlc-governing-skill.sh"
V_LIFECYCLE="$BIONIC_SKILLS_DIR/canonical-sdlc/diagrams/lifecycle.svg"
# (hoisted to tests/cross-gate-agreement.prelude.sh, which part 2 reads: V_ORIGIN, V_HOOKCHAIN, v_hook_val, V_ORIGIN_VAL, v_hookchain_vals, v_hc_chips_ok, v_hc_agree)

# extractors — each pulls the bare integer out of its file's own rendering shape.
# (hoisted to tests/cross-gate-agreement.prelude.sh, which part 2 reads: V_ORIGIN, V_HOOKCHAIN, v_hook_val, V_ORIGIN_VAL, v_hookchain_vals, v_hc_chips_ok, v_hc_agree)
v_lifecycle_val() {  # <text class="version-pin" data-pin="lifecycle-title" ...>...(v14)</text>
  grep -m1 'data-pin="lifecycle-title"' "$1" 2>/dev/null | grep -oE '\(v[0-9]+\)' | tr -cd '0-9'
}
# (hoisted to tests/cross-gate-agreement.prelude.sh, which part 2 reads: V_ORIGIN, V_HOOKCHAIN, v_hook_val, V_ORIGIN_VAL, v_hookchain_vals, v_hc_chips_ok, v_hc_agree)

# (hoisted to tests/cross-gate-agreement.prelude.sh, which part 2 reads: V_ORIGIN, V_HOOKCHAIN, v_hook_val, V_ORIGIN_VAL, v_hookchain_vals, v_hc_chips_ok, v_hc_agree)
expect_eq "the origin (evidence gate) declares a non-vacuous SUPPORTED_SDLC_VERSION" "yes" \
  "$([ -n "$V_ORIGIN_VAL" ] && [ "$V_ORIGIN_VAL" -gt 0 ] 2>/dev/null && echo yes || echo no)"

expect_eq "the governing-skill hook's SUPPORTED_SDLC_VERSION agrees with the gate's" \
  "$V_ORIGIN_VAL" "$(v_hook_val "$V_GSKILL")"

expect_eq "lifecycle.svg's title renders the same version" \
  "$V_ORIGIN_VAL" "$(v_lifecycle_val "$V_LIFECYCLE")"

# v_hc_chips_ok <svg> -> yes when the file carries at least one chip. The agreement
# relation below (every chip equals the gate's version) is vacuous over an empty set; this is
# the row that says the set is not empty. A count is not asked: a fourth chip is not a defect.
# (hoisted to tests/cross-gate-agreement.prelude.sh, which part 2 reads: V_ORIGIN, V_HOOKCHAIN, v_hook_val, V_ORIGIN_VAL, v_hookchain_vals, v_hc_chips_ok, v_hc_agree)
# v_hc_agree <svg> <version> -> yes when no chip disagrees with the version (empty set: yes).
# THE ONE OWNER OF THE RELATION (review 9 F2): the live row below and §PIN-REL's arms all ask
# this helper, so a defect put into it reaches the live row and the pin together.
# (hoisted to tests/cross-gate-agreement.prelude.sh, which part 2 reads: V_ORIGIN, V_HOOKCHAIN, v_hook_val, V_ORIGIN_VAL, v_hookchain_vals, v_hc_chips_ok, v_hc_agree)
expect_eq "hook-chain.svg carries at least one version-pin chip (the agreement row below is not vacuous)" "yes" \
  "$(v_hc_chips_ok "$V_HOOKCHAIN")"
expect_eq "…every hook-chain.svg version-pin chip agrees with the gate's" "yes" \
  "$(v_hc_agree "$V_HOOKCHAIN" "$V_ORIGIN_VAL")"

# MUTATION, the discriminator: doctor the governing-skill hook's value on a COPY — the
# shipped file is never touched — and the comparison above must be provably able to catch
# it. Without this, the rows above prove only that five renderings exist and currently
# agree, not that disagreement is detectable. The replacement value is derived from the
# live one (never a hardcoded "14") so this arm keeps discriminating after the next version
# bump instead of silently passing over air the way the hook-authoring.md staleness did.
V_MUT_DIR="$SANDBOX/version-mutant"; mkdir -p "$V_MUT_DIR"
anchor insert hooks/canonical-sdlc-governing-skill.sh 'SUPPORTED_SDLC_VERSION='
anchor -E "$V_GSKILL" "^SUPPORTED_SDLC_VERSION=${V_ORIGIN_VAL}\$" 1
sed "s/^SUPPORTED_SDLC_VERSION=${V_ORIGIN_VAL}\$/SUPPORTED_SDLC_VERSION=$((V_ORIGIN_VAL + 1))/" \
  "$V_GSKILL" > "$V_MUT_DIR/canonical-sdlc-governing-skill.sh"
expect_ne "…and a doctored governing-skill copy no longer agrees with the gate" \
  "$V_ORIGIN_VAL" "$(v_hook_val "$V_MUT_DIR/canonical-sdlc-governing-skill.sh")"

# CONTROL — the same copy, unmutated, still agrees. Without this the RED above could be the
# `sed`/copy machinery itself rather than the mutation.
cp "$V_GSKILL" "$V_MUT_DIR/canonical-sdlc-governing-skill.clean.sh"
expect_eq "control: an UNMUTATED copy still agrees with the gate" \
  "$V_ORIGIN_VAL" "$(v_hook_val "$V_MUT_DIR/canonical-sdlc-governing-skill.clean.sh")"

# AC-R6.3 — the governing-skill hook's two HINTS (the version-mismatch Fix line and the
# missing-frontmatter YAML block) read SUPPORTED_SDLC_VERSION; neither one's source states a
# digit. Both sites went through the hook before: the Fix line always interpolated the
# variable, and the YAML block's `canonical_sdlc_version: 14` was a literal until this
# wave's ed78ae3 pick bound the value near the top of the file and interpolated it there too.
V_HINT_REPO="$(new_repo "v-hint")"
V_HINT_PLAN="$V_HINT_REPO/.bionic/docs/plans/epic-99/wave-01-x.plan.md"

# -- the version-mismatch Fix line, against the real (unmutated) hook: a planted write
# declaring canonical_sdlc_version: 13 (one below origin, never hardcoded as 13 anywhere but
# in this plant) must be told to set the LIVE value, not seed its own doctored one back. --
V_MISMATCH_STDERR="$(jq -n --arg p "$V_HINT_PLAN" --arg s "$SID_A" \
    --arg c $'---\ngoverning-skill: canonical-sdlc\ncanonical_sdlc_version: 13\n---\nbody\n' \
    '{session_id:$s, tool_name:"Write", tool_input:{file_path:$p, content:$c}}' \
  | env HOME="$V_HINT_REPO" CLAUDE_CODE_SESSION_ID="$SID_A" bash "$V_GSKILL" 2>&1 >/dev/null)"
expect_contains "…a planted version-13 write's Fix line names the live value, not 13" \
  "canonical_sdlc_version: ${V_ORIGIN_VAL}" "$V_MISMATCH_STDERR"
expect_eq "…and never echoes the doctored value back as the fix" "" \
  "$(printf '%s' "$V_MISMATCH_STDERR" | grep -oE "set 'canonical_sdlc_version: 13'" || true)"

# -- the missing-frontmatter YAML hint: against the real hook it must print the live value,
# and against the §V mutant built above (SUPPORTED_SDLC_VERSION=origin+1) it must print THAT
# value instead — proving the hint tracks the variable rather than a baked-in literal. --
V_MISSING_C='# no frontmatter here
'
V_MISSING_STDERR="$(jq -n --arg p "$V_HINT_PLAN" --arg s "$SID_A" --arg c "$V_MISSING_C" \
    '{session_id:$s, tool_name:"Write", tool_input:{file_path:$p, content:$c}}' \
  | env HOME="$V_HINT_REPO" CLAUDE_CODE_SESSION_ID="$SID_A" bash "$V_GSKILL" 2>&1 >/dev/null)"
expect_contains "…the missing-frontmatter hint prints the live value" \
  "canonical_sdlc_version: ${V_ORIGIN_VAL}" "$V_MISSING_STDERR"

# A hook copied bare into $V_MUT_DIR resolves its libraries via loader.sh's `../scripts/lib`
# fallback, which is not there — see .claude/rules/lib-changes-in-worktrees.md's trap, the
# same shape one level down: a hook run standalone needs its sibling library directory, not
# just its own file. §S.4's S4_MUT builds that sibling once for the whole suite; this arm
# needs its own copy since it mutates the hook the shared one does not.
V_EXEC_MUT="$SANDBOX/version-mutant-exec"
mkdir -p "$V_EXEC_MUT/hooks" "$V_EXEC_MUT/scripts/lib"
cp "$LIB_DIR_SRC"/*.sh "$V_EXEC_MUT/scripts/lib/" 2>/dev/null
cp "$V_MUT_DIR/canonical-sdlc-governing-skill.sh" "$V_EXEC_MUT/hooks/canonical-sdlc-governing-skill.sh"
V_MISSING_MUT_STDERR="$(jq -n --arg p "$V_HINT_PLAN" --arg s "$SID_A" --arg c "$V_MISSING_C" \
    '{session_id:$s, tool_name:"Write", tool_input:{file_path:$p, content:$c}}' \
  | env HOME="$V_HINT_REPO" CLAUDE_CODE_SESSION_ID="$SID_A" \
    bash "$V_EXEC_MUT/hooks/canonical-sdlc-governing-skill.sh" 2>&1 >/dev/null)"
expect_contains "…and a MUTATED hook's hint prints ITS value, proving the hint follows the variable" \
  "canonical_sdlc_version: $((V_ORIGIN_VAL + 1))" "$V_MISSING_MUT_STDERR"

# -- static proof: no site in the hook's own source states the value as a bare digit; every
# rendering of the field name is followed by the variable, never a literal. --
expect_eq "…no 'canonical_sdlc_version: <digit>' literal anywhere in the hook's source" "" \
  "$(grep -nE 'canonical_sdlc_version:[[:space:]]*[0-9]' "$V_GSKILL" || true)"


# ============================================================
section "Section P — the Patrol stamp: the poker WRITES exactly the path the gate READS"
# ============================================================
#
# epic-17 wave-05 task 4/4 (spec AC-6). A producer/consumer pair with the path spelled
# once on each side — hooks/session-poker.sh builds it out of PATROL_STAMP_PREFIX/SUFFIX
# under the pinned project root, hooks/dispatch-preflight.sh builds it out of STATE_DIR and
# the payload session id — and no single-component suite can see them disagree. A
# disagreement is not loud: the gate refuses every dispatch of a run whose Patrol is firing
# perfectly, and the named fix (`session-poker.sh arm`) writes to the other path and does
# not clear it. That is an unrecoverable wall by inspection, which is exactly the class this
# file exists for.
#
# Driven as a ROUND TRIP rather than as two greps, because the property is behavioural: the
# gate is asked where it looked, the poker is asked to arm, and the gate is asked again.

# (hoisted to tests/cross-gate-agreement.prelude.sh, which part 2 reads: PARTY_PK)
P_SID="$SID_A"
P_REPO=$(new_repo "patrol-stamp-pair")
write_live_plan "$P_REPO/.bionic/docs/plans/epic-99/wave-01.md" "current: 4"
mkdir -p "$P_REPO/.bionic/tmp"
# new_repo arms every fixture; this is the one section whose subject is an UNARMED session.
rm -f "$P_REPO"/.bionic/tmp/patrol-*.state
{
  printf '# bionic environment attestation — machine-local, safe to delete\n'
  printf 'version=1\nkind=preflight-attestation\nsession_id=%s\n' "$P_SID"
  printf 'written_at=1785790000\nrepo=%s\n' "$P_REPO"
} > "$P_REPO/.bionic/tmp/preflight-$P_SID.state"
chmod 600 "$P_REPO/.bionic/tmp/preflight-$P_SID.state"

P_OUT=$(mk_agent_payload "$P_SID" "$P_REPO" | bash "$PARTY_DP" 2>&1); P_ST=$?
# A deny verdict, exit 0, since wave-19 T4 (REQ-7); stdout is kept so the verdict is read.
expect_eq "the gate refuses a dispatch with no Patrol stamp" "0" "$P_ST"
expect_contains "…on a deny verdict" '"permissionDecision":"deny"' "$P_OUT"

# The path the CONSUMER named, taken out of its own words rather than rebuilt here.
P_READS=$(printf '%s\n' "$P_OUT" | grep -oE '/[^[:space:]]*/patrol-[^[:space:]]+\.state' | head -1)

# The path the PRODUCER wrote, discovered by running the named fix and looking.
( cd "$P_REPO" && CLAUDE_CODE_SESSION_ID="$P_SID" bash "$PARTY_PK" arm ) >/dev/null 2>&1
P_WRITES=$(ls "$P_REPO"/.bionic/tmp/patrol-*.state 2>/dev/null | head -1)
if [ -n "$P_WRITES" ]; then
  ok "the poker's arm verb wrote a stamp"
else
  no "the poker's arm verb wrote a stamp" "nothing matching .bionic/tmp/patrol-*.state"
fi
expect_eq "poker WRITES == gate READS (one stamp path, two spellings)" "$P_READS" "$P_WRITES"

# The round trip closes: the fix the wall named actually opens the wall.
P_OUT2=$(mk_agent_payload "$P_SID" "$P_REPO" | bash "$PARTY_DP" 2>&1 >/dev/null); P_ST2=$?
expect_eq "…and the named fix opens it: the same dispatch now passes" "0" "$P_ST2"

# ============================================================
section "Section Q — refusal credit: one rule, two readers"
# ============================================================
#
# Step-6 findings C1/C2/C3, .bionic/docs/record/task-dispatch-wall-channel-loss/
# review-close.md. "How many dispatches did the wall REFUSE this session" has TWO owners —
# hooks/session-poker.sh's count_refused_dispatches, answering for the live tick, and
# payload/scripts/lib/patrol.sh's _patrol_scan, answering for doctor's reconstruction — and
# on this machine's own transcript they answered 13 and 1 against a truth of 1. Neither
# number was a rounding error. The poker greped the WHOLE transcript for the CLI's marker,
# which the plan, the reports and every brief that quotes it carry too, so the detector was
# inert in the repository that builds it; patrol cut each tool_result to 200 characters
# BEFORE looking for a marker real refusals carry at offset 482.
#
# THE RULE, now single and shared: a refusal is credited only when a tool_result carrying
# `PreToolUse:Agent hook error:` JOINS BY tool_use_id to an `Agent` tool_use in the same
# transcript — the refused dispatch's own result. A literal quoted inside a file read, a
# brief or a report joins to nothing; truncation moves to the display side, after the test.
# The main-thread filter is the poker's, on both sides: `isSidechain:true` OR an explicit
# agent-id key is not this session's own dispatch.
#
# ONE FIXTURE, BOTH READERS, ONE (dispatches, refused) PAIR. The two answers are compared
# to EACH OTHER first — that is what goes red on the next divergence, whichever side moves
# — and only then to the number the rule implies. Neither reader may source the other
# (hooks/ ships as hooks, scripts/lib/ as payload), so the copies stay two and this section
# is what holds them together.

PARTY_PT="${W1R_PARTY_PT:-$REPO_ROOT/payload/scripts/lib/patrol.sh}"

# The transcript shapes, captured off this machine 2026-08-23 with:
#   jq -c 'select((.message.content?|type)=="array") | .message.content[]' <transcript>
# Two of them are the false positives that were being counted as refusals: a `Read`/`Bash`
# result whose text quotes the marker out of a file, and an Agent spawn whose SIBLING
# `toolUseResult` field echoes the brief back (the CLI writes the brief there verbatim, so
# a brief that quotes the marker — this task's own — planted one in the transcript).
q_agent() {  # <tx> <tool-use-id>
  jq -nc --arg id "$2" '{type:"assistant",isSidechain:false,message:{role:"assistant",
    content:[{type:"tool_use",id:$id,name:"Agent",
              input:{name:"q-agent",subagent_type:"bionic:implementor",prompt:"…"}}]}}' >> "$1"
}
q_agent_pair() {  # <tx> <id> <id> — a parallel fan-out: two dispatches in ONE entry
  jq -nc --arg a "$2" --arg b "$3" '{type:"assistant",isSidechain:false,message:{role:"assistant",
    content:[{type:"tool_use",id:$a,name:"Agent",input:{name:"q-alpha",prompt:"…"}},
             {type:"tool_use",id:$b,name:"Agent",input:{name:"q-beta",prompt:"…"}}]}}' >> "$1"
}
q_agent_ctx() {  # <tx> <id> — an entry carrying an explicit agent-id key: not this thread's
  jq -nc --arg id "$2" '{type:"assistant",isSidechain:false,agentId:"agent-inner-1",
    message:{role:"assistant",content:[{type:"tool_use",id:$id,name:"Agent",
      input:{name:"q-inner",prompt:"…"}}]}}' >> "$1"
}
q_agent_side() {  # <tx> <id> — a subagent's own dispatch
  jq -nc --arg id "$2" '{type:"assistant",isSidechain:true,message:{role:"assistant",
    content:[{type:"tool_use",id:$id,name:"Agent",input:{name:"q-side",prompt:"…"}}]}}' >> "$1"
}
q_read() {  # <tx> <id> — a NON-Agent tool_use, the thing a quoted marker belongs to
  jq -nc --arg id "$2" '{type:"assistant",isSidechain:false,message:{role:"assistant",
    content:[{type:"tool_use",id:$id,name:"Read",input:{file_path:"/p/wave.plan.md"}}]}}' >> "$1"
}
q_result() {  # <tx> <id> <text>
  jq -nc --arg id "$2" --arg t "$3" '{type:"user",isSidechain:false,message:{role:"user",
    content:[{type:"tool_result",tool_use_id:$id,content:$t}]}}' >> "$1"
}
q_spawn_echo() {  # <tx> <id> <brief-text> — a SUCCESSFUL spawn whose sibling field echoes the brief
  jq -nc --arg id "$2" --arg b "$3" '{type:"user",isSidechain:false,
    message:{role:"user",content:[{type:"tool_result",tool_use_id:$id,
      content:[{type:"text",text:"Spawned successfully."}]}]},
    toolUseResult:{status:"teammate_spawned",prompt:$b}}' >> "$1"
}

Q_MARK='PreToolUse:Agent hook error:'
# Past patrol's 200-character display cut. Real refusals carry the marker at 482 and 628 —
# the CLI prefixes the hook's own stderr with the tool name and the hook path.
Q_PAD="$(printf 'x%.0s' $(seq 1 400))"
Q_REFUSAL="$Q_PAD $Q_MARK [dispatch-preflight.sh]: BLOCKED: this dispatch brief names no deliverable."
Q_QUOTE="the review says the marker is \`$Q_MARK\` and the poker greps for it"

mkdir -p "$SANDBOX/fx/refusal-credit"
Q_TX="$SANDBOX/fx/refusal-credit/all.jsonl"; : > "$Q_TX"
q_agent_pair "$Q_TX" toolu_q1 toolu_q2      # two main-thread dispatches, one entry
q_agent_ctx  "$Q_TX" toolu_q3               # C2: an agent-context entry — not a dispatch
q_agent_side "$Q_TX" toolu_q5               # a subagent's own dispatch — not a dispatch
q_result     "$Q_TX" toolu_q1 "$Q_REFUSAL"  # C1: the ONE real refusal, marker past 200
q_result     "$Q_TX" toolu_q2 "Spawned successfully."
q_read       "$Q_TX" toolu_q4
q_result     "$Q_TX" toolu_q4 "$Q_QUOTE"    # C3: the marker quoted out of a plan
q_agent      "$Q_TX" toolu_q6
q_spawn_echo "$Q_TX" toolu_q6 "Read first: review-close.md. The marker is $Q_MARK — join it."

# Each reader answers from ITS OWN file, in its own subshell: the poker's counters are
# extracted and called for real (§I.1's precedent), patrol is sourced as doctor sources it.
q_poker() {  # <fn-name> <transcript> [<since ISO>]
  ( eval "$(awk -v n="$1" '$0 ~ "^" n "\\(\\)" {f=1} f{print; if ($0=="}") exit}' "$PARTY_PK")"
    "$1" "$2" "${3:-}" ) 2>/dev/null
}
q_patrol() {  # <transcript> [<since ISO>] -> "<dispatches> <refused>"
  ( . "$PARTY_PT" >/dev/null 2>&1
    _patrol_scan "$1" "${2:-}" ) 2>/dev/null \
  | awk -F'\t' '$1=="AGENTS"{a=$2} $1=="REFUSED"{r=$2} END{printf "%d %d", a+0, r+0}'
}

Q_PK_D="$(q_poker count_main_thread_dispatches "$Q_TX")"
Q_PK_R="$(q_poker count_refused_dispatches "$Q_TX")"
Q_PT="$(q_patrol "$Q_TX")"; Q_PT_D="${Q_PT%% *}"; Q_PT_R="${Q_PT##* }"

expect_eq "fixture: patrol's scan runs at all" \
  "yes" "$([ -n "$Q_PT_D" ] && [ "$Q_PT_D" != 0 ] && echo yes || echo no)"
expect_eq "DISPATCHES: the poker and patrol return one number, not two" "$Q_PK_D" "$Q_PT_D"
expect_eq "REFUSED: the poker and patrol return one number, not two" "$Q_PK_R" "$Q_PT_R"

# --- Q.1 the three findings, one transcript each -----------------------------
# Asked separately so a regression names the defect that came back rather than a total.

Q_C1="$SANDBOX/fx/refusal-credit/c1.jsonl"; : > "$Q_C1"
q_agent  "$Q_C1" toolu_c1
q_result "$Q_C1" toolu_c1 "$Q_REFUSAL"
expect_eq "C1 patrol: the same, from the untruncated content" "1" \
  "$(q_patrol "$Q_C1" | cut -d' ' -f2)"

Q_C3="$SANDBOX/fx/refusal-credit/c3.jsonl"; : > "$Q_C3"
q_agent  "$Q_C3" toolu_d1
q_result "$Q_C3" toolu_d1 "Spawned successfully."
q_read   "$Q_C3" toolu_d2
q_result "$Q_C3" toolu_d2 "$Q_QUOTE"

Q_C3B="$SANDBOX/fx/refusal-credit/c3b.jsonl"; : > "$Q_C3B"
q_agent      "$Q_C3B" toolu_e1
q_spawn_echo "$Q_C3B" toolu_e1 "the marker is $Q_MARK and this brief quotes it"

Q_C2="$SANDBOX/fx/refusal-credit/c2.jsonl"; : > "$Q_C2"
q_agent_ctx  "$Q_C2" toolu_f1
q_agent_side "$Q_C2" toolu_f2

# --- Q.2 the discriminator: blind ONE reader and the pair must split ---------
# Without this the section proves only that two files agree on a fixture neither is
# sensitive to. The mutation is the defect ITSELF — patrol's pre-test truncation, restored
# to a copy — so the assertion is that C1's fixture separates the copies again.
Q_MUT="$SANDBOX/fx/refusal-credit/patrol-truncating.sh"
anchor file payload/scripts/lib/patrol.sh '(if ($full | test('
sed 's/(if ($full | test(/(if (($full | .[0:200]) | test(/' "$PARTY_PT" > "$Q_MUT"
Q_MUT_R="$( ( . "$Q_MUT" >/dev/null 2>&1; _patrol_scan "$Q_C1" ) 2>/dev/null \
            | awk -F'\t' '$1=="REFUSED"{print $2+0}' )"
expect_eq "…and the truncating copy misses the late marker, so the pair splits (§Q discriminates)" \
  "0" "$Q_MUT_R"

# --- Q.3 the WINDOW: one rule, two readers ----------------------------------
#
# §Q above proved the refusal-JOIN rule is one rule on two files with `since` left empty
# ("the whole transcript") on both sides. This is the sibling proof for the WINDOW itself:
# hooks/session-poker.sh scopes count_main_thread_dispatches/count_refused_dispatches to
# the roster's own window (`roster_window()`, exposed as the `window` verb) and
# payload/scripts/lib/patrol.sh takes the identical `since` parameter through
# `_patrol_scan` (patrol_window() shells out to that verb the same way patrol_interval()
# already shells out for the interval). Windowing either file alone splits this pair, which
# is why the whole cluster is one commit.
#
# THE FIXTURE IS A FILE ON DISK, tests/fixtures/patrol-two-wave.jsonl, rather than built
# inline: this section's whole claim is about which entries a reader counts, so the entries
# are reviewable as one artifact instead of as a sequence of jq calls. It can be a static
# file precisely because `since` here is a LITERAL instant. tests/doctor-patrol.test.sh
# Section 12 asks the same question end-to-end through doctor, where the window is the
# roster file's own creation time and the waves have to be dated against it at run time —
# a static file cannot express that, so Section 12 builds its own dated transcript.
#
# TWO WAVES: three entries before 2026-09-01T00:00:00Z carrying one refusal, four entries
# after it carrying one refusal. Lifetime 5 dispatches / 2 refusals, windowed 3 / 1.
Q3_TX="$REPO_ROOT/tests/fixtures/patrol-two-wave.jsonl"
Q3_SINCE="2026-09-01T00:00:00Z"

expect_true "Q.3 fixture: the two-wave transcript is on disk" test -f "$Q3_TX"

Q3_PK_D="$(q_poker count_main_thread_dispatches "$Q3_TX" "$Q3_SINCE")"
Q3_PK_R="$(q_poker count_refused_dispatches "$Q3_TX" "$Q3_SINCE")"
Q3_PT="$(q_patrol "$Q3_TX" "$Q3_SINCE")"; Q3_PT_D="${Q3_PT%% *}"; Q3_PT_R="${Q3_PT##* }"

expect_eq "windowed DISPATCHES: the poker counts only wave two (3)" "3" "$Q3_PK_D"
expect_eq "windowed DISPATCHES: poker and patrol agree" "$Q3_PK_D" "$Q3_PT_D"
expect_eq "windowed REFUSED: the poker counts only wave two's refusal, not wave one's (1)" \
  "1" "$Q3_PK_R"
expect_eq "windowed REFUSED: poker and patrol agree" "$Q3_PK_R" "$Q3_PT_R"

# THE DISCRIMINATOR: with no window at all (since="") both readers fall back to the
# transcript's whole life, so BOTH counts rise (5 dispatches, 2 refusals — one refusal per
# wave) — proof `since`, not some other difference, is what produced the smaller windowed
# counts above, and that this is not the coincidence of a fixture with one refusal in it.
Q3_PK_D_LIFE="$(q_poker count_main_thread_dispatches "$Q3_TX" "")"
Q3_PK_R_LIFE="$(q_poker count_refused_dispatches "$Q3_TX" "")"
Q3_PT_LIFE="$(q_patrol "$Q3_TX" "")"; Q3_PT_D_LIFE="${Q3_PT_LIFE%% *}"; Q3_PT_R_LIFE="${Q3_PT_LIFE##* }"
expect_eq "…and with no window at all, both readers count the earlier wave's dispatches too (5)" \
  "5" "$Q3_PK_D_LIFE"
expect_eq "…poker and patrol agree on the lifetime dispatch count too" \
  "$Q3_PK_D_LIFE" "$Q3_PT_D_LIFE"
expect_eq "…and the earlier wave's refusal too (2, not 1)" "2" "$Q3_PK_R_LIFE"
expect_eq "…poker and patrol agree on the lifetime refused count too" \
  "$Q3_PK_R_LIFE" "$Q3_PT_R_LIFE"

# ============================================================
section "Section R — the ADOPTED address: one construction, three sites"
# ============================================================
#
# `<name>@session-<id8>` is the only spelling the platform's stop primitive takes for a
# teammate (capture record/session-20260814-wave-detector-terminal-state/min/logs/A-p3.jsonl:9),
# and after epic-20 W1 three scripts build or accept it: hooks/stop-guard.sh constructs it
# for its refusals and accepts it as an identity, hooks/stop-check.sh prints it beside every
# ambiguous candidate, and hooks/session-poker.sh's `adopt` prints it as the stop address
# for an agent this session has taken over. The field defect was exactly a disagreement of
# this kind — adopt printed the TRANSCRIPT form, which the platform rejects — so what is
# pinned here is not that three files contain a string but that the string ONE of them
# prints is the string the other two answer to, over one fixture world.

RREPO_AD=$(new_repo "adopted-address")
RSLUG_AD=$(printf '%s' "$RREPO_AD" | sed 's/[^a-zA-Z0-9]/-/g')
RPROJ_AD="$CLAUDE_CONFIG_DIR/projects/$RSLUG_AD"
RSUB_AD="$RPROJ_AD/$SID_A/subagents"
mkdir -p "$RSUB_AD" "$RPROJ_AD/$SID_B/subagents" "$RREPO_AD/.bionic/tmp"
printf '{}\n' > "$RPROJ_AD/$SID_A.jsonl"
printf '{}\n' > "$RPROJ_AD/$SID_B.jsonl"
# The agent's files, planted by hand rather than through `plant()`: this section wants the
# predecessor's roster to carry exactly ONE row for the agent — the one the printf below
# writes — because `adopt` renders what it reads and a second row of the same name would
# render twice.
printf '{"name":"adoptee","agentType":"implementor","description":"fixture","model":"opus"}' \
  > "$RSUB_AD/agent-aadoptee-4444444444444444.meta.json"
printf '{"type":"assistant","message":{"content":[{"type":"text","text":"working"}]}}\n' \
  > "$RSUB_AD/agent-aadoptee-4444444444444444.jsonl"
# AND IT IS LIVE IN THE SUCCESSOR'S SET (S6, D1′). That is what a `/clear`+resume leaves
# behind and what the whole adopted address is for: the same process, still listed as a
# teammate by the harness, its working log still filed under the session that LAUNCHED it.
# Both transcripts carry the answer, because both sessions are looking at the same agent.
cg_live "$RPROJ_AD/$SID_A.jsonl" "adoptee"
cg_live "$RPROJ_AD/$SID_B.jsonl" "adoptee"
write_plan "$RREPO_AD/.bionic/docs/plans/epic-99/wave-01.md" "current: 4"

# THE PREDECESSOR'S ROW, as hooks/execution-recorder.sh left it when that session died:
# `identified`, the transcript-form id, a contract that never landed.
roster_row_fixture status=identified session="$SID_A" name=adoptee \
  agent_id=aadoptee-4444444444444444 launched_at=2026-08-05T00:00:00Z \
  deliverable=.bionic/docs/record/never-lands.md cadence="10 minutes" \
  >> "$RREPO_AD/.bionic/tmp/roster-$SID_A.state"

# THE ADOPTING SESSION IS DELIBERATELY UNBOUND, and since wave-session-bound-run that is a
# decision rather than an accident. `adopt` now partitions foreign rows on `plan=`: a BOUND
# caller writes only the rows naming its own plan and merely LISTS the rest, and the
# predecessor row planted below carries no `plan=` at all — it is a pre-wave roster (spec
# assumption A2). Bind `$SID_B` here and that row becomes `unattributed`, adopt declines to
# journal it, and the `stop        : TaskStop ` line every assertion below reads disappears —
# so this section would go red for a reason that has nothing to do with the ADDRESS it is
# about. The partition belongs to tests/session-poker.test.sh §17, which drives all three
# arms; what this section needs is the arm where every row reaches the rendering.
#
# `new_repo` plants an EMPTY marker for `$SID_B` (see `engage_sids`), which lib/run.sh reads
# as engaged-and-unbound. That is now PINNED rather than assumed: the row below asserts the
# partition this fixture depends on, so a future change to what an empty marker means fails
# here with its own name instead of silently emptying the three sites' evidence.
R_AD_OUT=$( cd "$RREPO_AD" && CLAUDE_CODE_SESSION_ID="$SID_B" bash "$SPO" adopt 2>&1 )
expect_contains "the adopting session is unbound, so every row is adoptable (this section's precondition)" \
  "partition=all" "$R_AD_OUT"
# The suffixed address, off the `stop` line. The bare name is printed beneath it on its own
# continuation line, which this grep does not reach.
R_AD_ADDR=$(printf '%s\n' "$R_AD_OUT" | grep -F 'stop        : TaskStop ' | head -1 \
            | sed 's/.*TaskStop //' | awk '{print $1}')
expect_eq "adopt prints the addressing form, built from the LAUNCHING session" \
  "adoptee@session-$(printf '%s' "$SID_A" | cut -c1-8)" "$R_AD_ADDR"

# SITE 2 — the observation answers to that exact string, and says why it is ours.
R_AD_CHECK=$( cd "$RREPO_AD" && CLAUDE_CODE_SESSION_ID="$SID_B" bash "$OBSERVE" "$R_AD_ADDR" 2>&1 )
expect_contains "the observation resolves the address adopt printed" \
  "aadoptee-4444444444444444" "$R_AD_CHECK"
expect_contains "…and classifies it OURS by the adoption the poker wrote" \
  "Classification: OURS" "$R_AD_CHECK"
expect_contains "…naming the session it was adopted from" "adopted_from=$SID_A" "$R_AD_CHECK"
# …and the working log it reads is the one filed under the LAUNCHING session, which is the
# fact `adopted_from=` exists to carry now that no directory scan goes looking for it.
expect_contains "…and reads the working log filed under that session" \
  "$SID_A/subagents/agent-aadoptee-4444444444444444.jsonl" "$R_AD_CHECK"

# SITE 3 — the stop gate resolves the same string and accepts it as an IDENTITY. The
# paired negative first: resolution succeeding is not the ceremony being skipped.
R_AD_ST_OUT=$(mk_stop_payload "$SID_B" "$RPROJ_AD/$SID_B.jsonl" "$RREPO_AD" "$R_AD_ADDR" \
              | bash "$PARTY_SG" 2>&1); R_AD_ST=$?
expect_eq "before any discharge the stop gate still takes its look (wave-31 T32: allowed, its verdict recorded as reason=)" "0" "$R_AD_ST"
expect_contains "…and says what it saw" "STOP ALLOWED" "$R_AD_ST_OUT"
expect_absent "…and never with the unresolved refusal the field hit" \
  "no agent in THIS session's metadata" "$R_AD_ST_OUT"

( cd "$RREPO_AD" && CLAUDE_CODE_SESSION_ID="$SID_B" bash "$SWEEPER" ack adoptee ) >/dev/null 2>&1
R_AD_ST_OUT=$(mk_stop_payload "$SID_B" "$RPROJ_AD/$SID_B.jsonl" "$RREPO_AD" "$R_AD_ADDR" \
              | bash "$PARTY_SG" 2>&1); R_AD_ST=$?
expect_eq "the stop gate accepts the address adopt printed, discharged by the ack" \
  "0" "$R_AD_ST"
expect_absent "…before any look" "STOP ALLOWED" "$R_AD_ST_OUT"

# THE CONSTRUCTION ITSELF, at all three sites: eight characters of a session id, cut the
# same way. A site that starts spelling it differently — a full uuid, a different width —
# splits from the other two here rather than in the field.
# TWO SITES, NOT THREE (epic-23 wave-15, REQ-2). hooks/stop-check.sh carried an
# `accepted_addresses` of its own that nothing had called since T22 retired the unresolved
# arms it printed for; it went with the resolution that moved into the library. Its absence
# is asserted rather than assumed, so a copy that comes back comes back visibly.
for _f in "$PARTY_SG" "$SPO"; do
  expect_true "$(basename "$_f") builds the address as @session-<first 8 of a session id>" \
    grep -qE '@session-\$\(printf .%s. "\$[A-Za-z_]+" \| cut -c1-8\)' "$_f"
done
expect_absent "…and the observation builds no address at all: its dead copy is gone" \
  "accepted_addresses" "$(cat "$OBSERVE")"

# ============================================================
section "S — which plan answers for the run: the tick reads what the gate reads (wave-1.3.2 4/4, AC-13/AC-14)"
# ============================================================
#
# THE COPY THIS SECTION EXISTS FOR. `hooks/session-poker.sh tick` DISARMs the Patrol —
# terminally, for the rest of the session — and from 1.3.2 that decision needs the RUN to
# say it is delivered, which means the tick reads a plan. It is the sixth reader of "which
# *.md answers for this run", and hooks/patrol-revive.sh:64-70 refused to become the fifth
# for a reason worth restating: an UNFILTERED "newest *.md under plans/" read is a measured
# incident. On 2026-08-15 a marker-less scrap won the newest race, `current:` parsed empty,
# and every wall reading it passed silently for ~15 minutes
# (.bionic/docs/record/session-20260815-landing-supervision/t8-forensic-read.md).
#
# So the tick got the gate's read rather than an approximation of it, and this section is
# the wall that keeps the copy honest — in BOTH directions, because the two failures are
# different. A drifted PREDICATE (the `## SDLC State` filter, the fence rule, the CR
# translation) makes the tick DISARM off a scrap file: silent, terminal, unrecoverable. A
# drifted SELECTION (depth, the strict `-nt` ordering, the two plan directories) makes it
# answer for the wrong wave.
#
# TWO PROOFS, because either alone is weak. First the TEXT: the four bodies the tick copied
# are compared to canonical-sdlc-evidence-gate.sh's, which is the designated origin (it
# documents the contract at its definition site) — §N.1's and §Q's method. Then the
# BEHAVIOUR: both readers are handed the same repository and asked which file answered, and
# their answers are compared to each other. Text agreement without behaviour would miss a
# call site that never invokes its copy; behaviour without text would miss a drift the
# fixtures happen not to reach.

# (hoisted to tests/cross-gate-agreement.prelude.sh, which part 2 reads: PARTY_PK_S)

# ---- S.1 the family is down to one carrier, and it is this one -----------
#
# The four bodies this section used to compare — `has_sdlc_state`, `resolve_docs_root`,
# `normalize_newlines`, and the selection block — lived in the evidence gate as the
# designated origin and in the tick as copies. The gate's are gone (bionic 1.4.0, task
# ADOPT): it asks `lib/run.sh` now, and §A2 proves the asking is real by mutating the
# library and watching every party's answer move. The tick's are gone too (task SCHED,
# POKER/2 ratified 2026-09-03) — so there is no longer a text COMPARISON to make here,
# and pretending otherwise would leave a section comparing a body against nothing and
# calling it agreement. What §S pins about the TEXT now is the absence itself, in both
# directions: no party carries a private plan reader, and the tick names the library's
# functions where its own used to be.
expect_eq "the evidence gate carries no private has_sdlc_state() any more" "" \
  "$(fn_body "$PARTY_EG" has_sdlc_state)"
expect_eq "…and neither does the tick, the last file that did (SCHED converted it)" "" \
  "$(fn_body "$PARTY_PK_S" has_sdlc_state)"
expect_eq "…nor a private newest-plan selection beside it" "" \
  "$(fn_body "$PARTY_PK_S" newest_sdlc_plan)"
expect_eq "…nor a private docs-root resolver" "" \
  "$(fn_body "$PARTY_PK_S" resolve_docs_root)"
# THE READER THE TICK CALLS IS `session_run` (wave-session-bound-run). It used to be
# `active_plan`, and that call survives — but only on `resolve_run`'s `none` arm, where an
# unbound session over a closed run still needs a plan to read DISARM out of. So the pin
# that stands for "the tick asks the library which run it is in" is `session_run`, and the
# `active_plan` row beside it says what the leftover call is for rather than leaving a
# reader to guess it is the main path. Both, or the sentence above them is only half true.
expect_eq "…and the tick asks the library WHOSE run this session is in, by name" "yes" \
  "$(/usr/bin/grep -q 'session_run "' "$PARTY_PK_S" && echo yes || echo no)"
expect_eq "…and still calls active_plan, for the unbound-and-closed arm and nothing else" "yes" \
  "$(/usr/bin/grep -q 'active_plan "' "$PARTY_PK_S" && echo yes || echo no)"

# ---- S.2 the ONE selection block, proven by what it SELECTS -------------
#
# It used to live twice: at file scope in the evidence gate, and inside the tick's
# `newest_sdlc_plan()`. Both copies are gone and the block is `lib/run.sh`'s, so what is
# pinned here is the LIBRARY's selection on its three load-bearing properties — the DEPTH
# bound the layout needs, the FENCE rule that keeps a page ABOUT the lifecycle out of the
# set, and the STRICT newest ordering that makes `active_plan`'s answer a total one rather
# than one that depends on find's directory order.
#
# PINNED BY BEHAVIOUR, NOT BY SUBSTRING (wave-roster-lifecycle S1, AC-22). Until this wave
# the assertions below read `fn_body run.sh active_plan` and matched `-maxdepth 2 -type f`
# and `-nt "$plan"` inside it. That pinned the block's TEXT to one function's body, so the
# moment the walk moved into the `_run_candidates` helper the two readers now share, every
# one of those matches emptied — and an empty extraction reads as a PASS on a `case` that
# is looking for a substring, which is the failure mode this suite exists to refuse. The
# properties are unchanged; they are asked of the ANSWER now, over one fixture repository
# driven through both readers, so the walk can be refactored under them and only a change
# in what it SELECTS goes red.
#
# BOTH READERS, ONE FIXTURE. `active_plan` picks one file and `open_runs` returns the set;
# they walk the same candidates, so every exclusion below is asserted of BOTH answers. That
# agreement is what this section owns, and the depth discriminator at the end moves both.

# The RETIRED extractor, kept for one job only: proving the tick's copy is really gone.
# It is the exact reader this section used against `newest_sdlc_plan()`, so an empty answer
# means the block it looked for is absent rather than merely renamed out of reach. This one
# reads the TICK, not the library, so the extraction below leaves it exactly as it was.
sel_block_pk() {  # <file> -> the tick's old selection block, or empty
  awk '
    !f && index($0, "PLAN_DIRS=(") { f = 1 }
    f {
      line = $0
      sub(/^[[:space:]]+/, "", line); sub(/[[:space:]]+$/, "", line)
      if (line == "" || line ~ /^#/) next
      print line
      if (line == "done") exit
    }
  ' "$1"
}

S_RUN_LIB="$BIONIC_HOOKS_DIR/../payload/scripts/lib/run.sh"
[ -r "$S_RUN_LIB" ] || S_RUN_LIB="$BIONIC_HOOKS_DIR/../scripts/lib/run.sh"
expect_eq "the library under this section is on disk (§S.2 is not vacuous)" "yes" \
  "$([ -r "$S_RUN_LIB" ] && echo yes || echo no)"
expect_eq "…and the tick carries no selection block of its own to disagree with it" "" \
  "$(sel_block_pk "$PARTY_PK_S")"

# THE ANSWER AND THE STATUS RIDE ONE CAPTURE, separated by a byte no path can contain —
# `$?` read after a `$( … )` assignment under this file's `set -u` is the assignment's, not
# the function's. §OR's `or_ask` takes the same reading against the same library.
S2_OUT=""; S2_ST=0
s2_ask() {  # <library> <root> <function> -> sets S2_OUT, S2_ST
  local lib="$1" root="$2" fn="$3" raw
  raw=$( . "$lib" >/dev/null 2>&1; "$fn" "$root" 2>/dev/null; printf '\037%s' "$?" )
  S2_ST="${raw##*$'\037'}"
  S2_OUT="${raw%$'\037'*}"
  S2_OUT="${S2_OUT%$'\n'}"
}

# ONE FIXTURE, FOUR CANDIDATE FILES, EVERY EXCLUSION LOAD-BEARING. The mtimes are ordered so
# that each file the walk must REFUSE is NEWER than the one it must return: a depth-3 plan
# and a fenced example that were merely older would be excluded by the ordering and the
# selection rules would never be asked. Driven straight at the library — no hook, no session,
# no git repo — because the property under test is the walk, and `new_repo`'s patrol stamp
# and engagement markers would only add ways for the fixture to answer for another reason.
S2_R="$SANDBOX/s2-selection"
S2_REAL="$S2_R/.bionic/docs/plans/wave.plan.md"
S2_OLDER="$S2_R/.bionic/docs/plans/epic-99/older.plan.md"
S2_DEEP="$S2_R/.bionic/docs/plans/epic-99/sub/deep.plan.md"
S2_FENCED="$S2_R/.bionic/docs/plans/example.md"
write_plan "$S2_REAL"  "current: 4"
write_plan "$S2_OLDER" "current: 4"
write_plan "$S2_DEEP"  "current: 4"
mkdir -p "$(dirname "$S2_FENCED")"
cat > "$S2_FENCED" <<'S2FENCE'
# A page ABOUT the lifecycle, not a plan

```
## SDLC State

integration-branch: main
current: 4
```
S2FENCE
touch -t 202601010000 "$S2_OLDER"
touch -t 202602010000 "$S2_REAL"
touch -t 202603010000 "$S2_DEEP"
touch -t 202604010000 "$S2_FENCED"

s2_ask "$S_RUN_LIB" "$S2_R" active_plan; S2_AP="$S2_OUT"; S2_AP_ST="$S2_ST"
s2_ask "$S_RUN_LIB" "$S2_R" open_runs;   S2_SET="$S2_OUT"; S2_SET_ST="$S2_ST"

expect_eq "active_plan has an answer on the fixture (non-vacuity)" "0" "$S2_AP_ST"
expect_eq "…and it is the newest REAL plan inside the bound" "$S2_REAL" "$S2_AP"
expect_eq "open_runs has an answer too" "0" "$S2_SET_ST"
expect_eq "…and it is the two in-bound plans, newest first" \
  "$(printf '%s\n%s' "$S2_REAL" "$S2_OLDER")" "$S2_SET"
expect_eq "…so the selection is bounded at depth 2: the NEWER depth-3 plan is in neither" "no" \
  "$(cg_contains "$S2_AP$S2_SET" "$S2_DEEP")"
expect_eq "…and fence-aware: the NEWEST file, whose ## SDLC State is fenced, is in neither" "no" \
  "$(cg_contains "$S2_AP$S2_SET" "$S2_FENCED")"
expect_eq "…and the two readers agree: active_plan's answer IS line 1 of the set" \
  "$S2_AP" "$(printf '%s\n' "$S2_SET" | head -1)"

# THE DEPTH DISCRIMINATOR, AND IT MOVES BOTH READERS. Without it the exclusions above prove
# only that two paths are absent from two strings, which is also what a walk that found
# nothing at all would prove. The bound is raised to 3 on a COPY; the depth-3 plan is the
# newest real plan in the tree, so `active_plan` must switch to it and the set must gain it.
# The shipped file is never touched. One `sed` reaches every copy of the walk there is — two
# before the `_run_candidates` extraction, one after — which is why this proof survives it.
S2_MUT_DIR="$SANDBOX/runstate-mutant"; mkdir -p "$S2_MUT_DIR"
anchor file payload/scripts/lib/run.sh '-maxdepth 2 -type f'
sed 's/-maxdepth 2 -type f/-maxdepth 3 -type f/g' "$S_RUN_LIB" > "$S2_MUT_DIR/depth.sh"
s2_ask "$S2_MUT_DIR/depth.sh" "$S2_R" active_plan; S2_AP_M="$S2_OUT"
s2_ask "$S2_MUT_DIR/depth.sh" "$S2_R" open_runs;   S2_SET_M="$S2_OUT"
expect_eq "depth 3: active_plan switches to the deep plan (§S.2 discriminates)" \
  "$S2_DEEP" "$S2_AP_M"
expect_eq "…and the set gains it, newest first — BOTH readers moved on one mutation" \
  "$(printf '%s\n%s\n%s' "$S2_DEEP" "$S2_REAL" "$S2_OLDER")" "$S2_SET_M"

# THE ORDERING DISCRIMINATOR. Depth alone would stay green if `active_plan` stopped choosing
# the newest and started choosing whatever `find` handed it last, so the comparator is
# reversed on a second copy and the answer must become the OLDEST candidate. It is asserted
# of `active_plan` only: `open_runs` keeps its own newest-first insertion, which §OR.1 and
# run-predicate R6g pin, and a mutation that moved both would be measuring one of them twice.
anchor file payload/scripts/lib/run.sh '[ "$f" -nt "$plan" ]'
sed 's/\[ "\$f" -nt "\$plan" \]/[ "$plan" -nt "$f" ]/' "$S_RUN_LIB" > "$S2_MUT_DIR/order.sh"
s2_ask "$S2_MUT_DIR/order.sh" "$S2_R" active_plan
expect_eq "reversed comparator: active_plan answers with the OLDEST plan instead" \
  "$S2_OLDER" "$S2_OUT"

# RESTORED. The shipped library answers exactly as it did before either mutation, so the two
# rows above measured the mutations and not a fixture that had drifted underneath them.
s2_ask "$S_RUN_LIB" "$S2_R" active_plan
expect_eq "restored: the shipped library still names the newest in-bound plan" "$S2_REAL" "$S2_OUT"

# ---- S.3 the round trip: one repository, two readers, one answer ---------
#
# Driven rather than grepped, because the property is behavioural. The gate is asked through
# its own refusal (which names `Plan:` and the step it could not find); the tick is asked
# through the QUIET line it now prints over an empty roster, which names the plan it decided
# from and where that plan says the run is. Neither answer is rebuilt here.

# (hoisted to tests/cross-gate-agreement.prelude.sh, which part 2 reads: s_backdate)

# THE READERS TAKE A SESSION ID (wave-session-bound-run). Until this wave "which plan
# answers for the run" was a property of the ROOT, so a reader needed only a repo; it is now
# a property of the SESSION, and a helper that hard-coded one sid could only ever ask half
# the question. Both default to $SID_A so every case below §S.3 reads exactly as it did.
s_eg_read() {  # <repo> [sid] -> "<plan path>|<current>", or "none"
  local out st plan cur sid="${2:-$SID_A}" _b=0
  # An UNBOUND session is bound for the drive to its library's newest open run (cg_eg_bind,
  # wave-23-fixit-1810 D1); a session a case bound itself is read as it stands.
  cg_eg_bind "$1" "$sid" && _b=1
  out=$(mk_bash_payload "$sid" "$SANDBOX/t.jsonl" "$1" "git commit -m x" \
        | env -u CLAUDE_PROJECT_DIR CLAUDE_CODE_SESSION_ID="$sid" bash "$PARTY_EG" 2>&1); st=$?
  [ "$_b" = 1 ] && cg_eg_unbind "$1" "$sid"
  [ "$st" -eq 0 ] && { echo none; return; }
  plan=$(printf '%s\n' "$out" | sed -n 's/^Plan: //p' | head -1)
  cur=$(printf '%s\n' "$out" | sed -n "s/.*has no 'Step \([^']*\):' line.*/\1/p" | head -1)
  # FROM STEP 6 THE GATE ASKS FOR READINGS, NOT A STEP LINE (wave-27 T14; D3), so a plan there
  # meets another arm first; the step is the one its detail head names, "canonical-sdlc step N —",
  # or the reading refusal's "is at current: N,".
  [ -n "$cur" ] || cur=$(printf '%s\n' "$out" | sed -n -e 's/^canonical-sdlc step \([0-9][0-9ab]*\) — .*/\1/p' \
    -e 's/^canonical-sdlc .* is at current: \([^,]*\), and from Step 6 .*/\1/p' | head -1)
  if [ -z "$plan" ] || [ -z "$cur" ]; then echo "other:$(printf '%s' "$out" | head -1 | cut -c1-60)"; return; fi
  printf '%s|%s\n' "$plan" "$cur"
}

s_pk_read() {  # <repo> [sid] -> "<plan path>|<current>", or "none"
  local out plan cur sid="${2:-$SID_A}"
  roster_header \
    > "$1/.bionic/tmp/roster-$sid.state"
  # THE STAMP IS RE-PLANTED PER READ. A tick that decides DISARM removes this session's
  # Patrol stamp as its last act (hooks/session-poker.sh), so a second read of the same
  # fixture would meet a different world than the first. Every §S read is meant to be the
  # first one.
  rm -f "$1/.bionic/tmp/patrol-$sid.state.holds"
  # AN UNBOUND SESSION IS BOUND FOR THE DRIVE, as `s_eg_read` does for the gate (T11, after
  # the Step-6 review): the tick acts as under `none` for `fallback <p>`, so what this reader
  # compares, which plan the library selects, is read through a binding to that plan.
  local _b=0
  cg_eg_bind "$1" "$sid" && _b=1
  out=$( cd "$1" && env CLAUDE_CODE_SESSION_ID="$sid" CLAUDE_CONFIG_DIR="$1/no-such-config" \
           bash "$PARTY_PK_S" tick 2>&1 )
  [ "$_b" = 1 ] && cg_eg_unbind "$1" "$sid"
  case "$out" in *'no plan carrying an unfenced'*) echo none; return ;; esac
  plan=$(printf '%s\n' "$out" | sed -n 's/.*(\(\/[^ ]*\.md\) is at current: .*/\1/p' | head -1)
  cur=$(printf '%s\n' "$out" | sed -n 's/.* is at current: \([^ )]*\).*/\1/p' | head -1)
  if [ -z "$plan" ] || [ -z "$cur" ]; then echo "other:$(printf '%s' "$out" | head -1 | cut -c1-60)"; return; fi
  printf '%s|%s\n' "$plan" "$cur"
}

# S.3a — a NEWER marker-less .md must lose to an older real plan. This is the 2026-08-15
# incident in fixture form, and it is the case that decides whether the tick can DISARM off
# a scrap file.
S_R1=$(new_repo "s-marker-less-newest")
write_plan "$S_R1/.bionic/docs/plans/epic-99/wave-01.plan.md" "current: 4"
printf 'a scratch note — no SDLC State heading anywhere in it\n' \
  > "$S_R1/.bionic/docs/plans/epic-99/zz-newest-scrap.md"
# "Newest" is fixture DATA, set by backdating the loser — never by sleeping, and never left
# to a same-second tie, which `-nt` resolves as "not newer" and would pass this case for a
# reason the fixture never states.
s_backdate "$S_R1/.bionic/docs/plans/epic-99/wave-01.plan.md"
S_EG=$(s_eg_read "$S_R1"); S_PK=$(s_pk_read "$S_R1")
expect_eq "the gate skips the newer marker-less file and answers from the plan" \
  "$S_R1/.bionic/docs/plans/epic-99/wave-01.plan.md|4" "$S_EG"
expect_eq "…and the tick answers from the SAME file, at the same step" "$S_EG" "$S_PK"

# S.3b — the newest REAL plan wins, so the pin is on ordering and not merely on filtering.
# Its paired discriminator is S.3a: one case where the newest file loses, one where it wins.
S_R2=$(new_repo "s-newest-real-plan")
write_plan "$S_R2/.bionic/docs/plans/epic-98/wave-01.plan.md" "current: 4"
write_plan "$S_R2/.bionic/docs/plans/epic-99/wave-02.plan.md" "current: 6"
s_backdate "$S_R2/.bionic/docs/plans/epic-98/wave-01.plan.md"
S_EG=$(s_eg_read "$S_R2"); S_PK=$(s_pk_read "$S_R2")
expect_eq "the gate takes the NEWER of two real plans" \
  "$S_R2/.bionic/docs/plans/epic-99/wave-02.plan.md|6" "$S_EG"
expect_eq "…and so does the tick" "$S_EG" "$S_PK"

# S.3c — a `## SDLC State` that exists only inside a fence is documentation, not a run.
# Both readers must answer "no canonical run here" rather than parsing the example.
S_R3=$(new_repo "s-fenced-only")
mkdir -p "$S_R3/.bionic/docs/plans/epic-99"
{
  printf -- '---\ngoverning-skill: canonical-sdlc\ncanonical_sdlc_version: 14\n'
  printf -- 'intent: build\nrigor: double\nscale: wave\n---\n\n# a document ABOUT plans\n\n'
  printf '```\n## SDLC State\ncurrent: 4\n```\n'
} > "$S_R3/.bionic/docs/plans/epic-99/schema-notes.md"
S_EG=$(s_eg_read "$S_R3"); S_PK=$(s_pk_read "$S_R3")
expect_eq "a fenced-only heading is not a plan to the gate" "none" "$S_EG"
expect_eq "…and is not a plan to the tick either" "none" "$S_PK"

# S.3d — ONE BOUND, AND IT IS 2. This case used to pin a DISAGREEMENT: L-RUN shipped
# `active_plan` at depth 3 while the tick's private copy walked 2, and the honest thing a
# suite could do about two readers with different bounds was to state it. POKER/2's
# unification (ratified 2026-09-03) ended it — the tick has no reader of its own, the
# library is depth 2, and both parties answer from the same walk.
#
# BOTH DIRECTIONS, because the deep half alone would pass on a reader with no bound and the
# shallow half alone on one that finds nothing: a plan at depth 3 is invisible to BOTH, and
# the SAME content at depth 2 is seen by BOTH.
S_R4=$(new_repo "s-depth")
write_plan "$S_R4/.bionic/docs/plans/epic-99/wave-01/too-deep.plan.md" "current: 4"
S_EG=$(s_eg_read "$S_R4"); S_PK=$(s_pk_read "$S_R4")
expect_eq "a plan at depth 3 is out of the bound for the gate" "none" "$S_EG"
expect_eq "…and out of it for the tick, which now reads the same library" "none" "$S_PK"
write_plan "$S_R4/.bionic/docs/plans/epic-99/wave-01.plan.md" "current: 4"
S_EG=$(s_eg_read "$S_R4"); S_PK=$(s_pk_read "$S_R4")
expect_eq "…and the SAME content at depth 2 is seen by the gate (the bound is pinned)" \
  "$S_R4/.bionic/docs/plans/epic-99/wave-01.plan.md|4" "$S_EG"
expect_eq "…and by the tick" "$S_EG" "$S_PK"

# ============================================================
section "S.4 — THE RUN VERDICT: one root, two sessions, every consumer answers for ITS OWN run"
# ============================================================
#
# THE OWNERSHIP-TABLE ROW THIS DISCHARGES (spec §Design): "the run verdict · owning module
# lib/run.sh session_run · rendering surfaces: evidence-gate, governing-skill,
# dispatch-preflight, duties-gate, poker tick/scheduler, session-start, patrol-revive,
# context-spend".
#
# THE BUG IN ONE SENTENCE. Every hook used to answer "which run am I in" with
# `active_run "$ROOT"` — one answer per REPOSITORY — so two engaged sessions in one root
# shared a run identity: the evidence gate validated the wrong plan, `adopt` offered another
# run's agents, session-start steered a new session at the existing run. §S above pins that
# the parties agree with each other; it cannot see this bug at all, because with one session
# in the fixture the wrong answer and the right answer are the same string.
#
# SO THE FIXTURE HAS TWO SESSIONS AND THE ASSERTION IS ASYMMETRIC. One root, two open plans,
# one bound to each session, and every consumer is driven TWICE — once as A, once as B — and
# must name A's plan for A and B's for B. A consumer that kept the root-keyed reader answers
# the SAME plan both times and fails one of its two rows, whichever way the mtime fell.
#
# THREE VERDICTS, NOT ONE. `bound-open` is where the consumers that read a plan for DATA are
# discriminated; `bound-closed` and `fallback` are where the four consumers that use the run
# only as a boolean can be discriminated at all, because those are the two verdicts they
# ANNOUNCE by name (AC-3, AC-6). Leaving them out would leave half the ownership table's
# rendering surfaces outside the test that exists for it.
#
# WHERE EACH CONSUMER'S ANSWER IS READ FROM — measured, not assumed
# (.bionic/docs/record/wave-session-bound-run/s8-consumer-recon.md):
#
#   evidence-gate      bound-open: `Plan: <p>` on its refusal · closed/fallback: announced
#   dispatch-preflight bound-open: `declared by <p>` in the budget refusal · both announced
#   context-spend      bound-open: field 1 of .bionic/tmp/context-spend.state · both announced
#   session-poker tick bound-open: the QUIET line's `(<p> is at current: N)` · both announced
#   governing-skill    bound-open: NOTHING — the verdict is a boolean here · both announced
#   patrol-duties-gate bound-open: NOTHING (only the basename, into an awk fold) · both announced
#   patrol-revive      bound-open: NOTHING (a pure gate) · both announced
#   session-start      NOTHING, ever — its only plan output is `open_runs`, and only for an
#                      UNBOUND session in a root with two or more. Which is itself the claim,
#                      and S.4d asserts it in both directions.

# THE TWO SENTENCES, EACH PINNED IN FULL. Seven hooks carry a literal copy of each and the
# ownership table names no owner for the wording — row 2 licenses seven RENDERINGS of the
# verdict and says nothing about them being the same string — so these two regexes are the
# single authority for what the fleet says, and the loops below drive all seven against them.
#
# THE CLOSED SENTENCE INCLUDES ITS TAIL (S10a, review D6). It used to be pinned to its prefix
# alone, so the `; this session has no open run` half — the clause that tells the operator
# what the closed binding MEANS rather than merely that it exists — could be dropped by six of
# the seven and stay green. The fallback sentence was already pinned whole; this is the other
# half brought up to it. `.*` spans the path, which each row asserts separately.
S4_FALLBACK_RE='run resolved by newest-plan fallback \(session unbound\) — '
S4_CLOSED_RE='bound plan closed — .*; this session has no open run'

# ---- the fixture world ------------------------------------------------
#
# `write_plan` is this file's own builder; the budget line is appended for
# dispatch-preflight's ceiling, which is the only per-plan DATUM any consumer reads besides
# the step. A plan with no `parallel-budget:` makes the budget wall inert, and an inert wall
# is not an observation.
# (hoisted to tests/cross-gate-agreement.prelude.sh, which part 2 reads: s4_plan, s4_bind, s4_attest, s4_stop_payload)
s4_close() {  # <path> — the same plan, delivered
  write_plan "$1" "current: 9"
  printf -- '- Step 9: delivered: 2026-09-04\n' >> "$1"
}
# THE MARKER'S EXACT TWO-LINE SHAPE, hooks/engage.sh:287 — `plan=<path>` then
# `engaged_at=<iso>`, mode 600, written by the real `bind_plan` (S11,
# tests/lib/bound-marker.sh; spec AC-24). A fixture that invented a one-line marker
# would be testing a file no writer in the fleet produces.
# (hoisted to tests/cross-gate-agreement.prelude.sh, which part 2 reads: s4_plan, s4_bind, s4_attest, s4_stop_payload)
s4_unbind() {  # <repo> <sid> — engaged, no binding (the shape engage_sids plants)
  unbound_marker "$1" "$2" empty
}
# WITHOUT AN ATTESTATION THE DISPATCH WALL RUNS THE REAL ENVIRONMENT PROBE INLINE, which
# reads a credential and a config root off the machine this suite happens to be on — so the
# gate's answer would depend on the runner's shell rather than on the fixture, and a refusal
# there would make every assertion below it vacuously true. Planted in the shape
# hooks/preflight-probe.sh writes and tests/dispatch-preflight.test.sh:265 plants.
# (hoisted to tests/cross-gate-agreement.prelude.sh, which part 2 reads: s4_plan, s4_bind, s4_attest, s4_stop_payload)

# ---- one driver per consumer, each returning that consumer's whole channel ----
#
# STDOUT AND STDERR ARE MERGED for every driver but session-start's. Each hook chooses its
# own channel for the announcement (stderr for the seven, stdout for session-start's
# listing), and a section about whether the RIGHT PLAN was named has no business also
# pinning which file descriptor it was named on — §L and the per-hook suites own that.
s4_eg() {  # <repo> <sid>
  mk_bash_payload "$2" "$SANDBOX/t.jsonl" "$1" "git commit -m x" \
    | env -u CLAUDE_PROJECT_DIR HOME="$1" CLAUDE_CODE_SESSION_ID="$2" bash "$PARTY_EG" 2>&1
  return 0
}
s4_gs() {  # <repo> <sid> — the PreToolUse WALL arm: no hook_event_name key, per the hook's :56
  jq -n --arg p "$1/.bionic/docs/record/s4-note.md" --arg c "a note" --arg s "$2" \
    '{session_id:$s, tool_name:"Write", tool_input:{file_path:$p, content:$c}}' \
    | env HOME="$1" CLAUDE_CODE_SESSION_ID="$2" bash "$PARTY_SG_W" 2>&1
  return 0
}
s4_dp() {  # <repo> <sid>
  # The transcript is REDIRECTED onto this world's file. `mk_agent_payload` pins
  # `transcript_path:"/irrelevant.jsonl"`, which was true of the dispatch wall until S5: the
  # budget used to count `intended` rows against a landing-swept marker and never opened a
  # transcript. It now counts them against `live_agents_has`, so a payload pointing at a file
  # that does not exist reads NONE and the wall refuses with "call ListAgents, then dispatch"
  # BEFORE it ever computes a ceiling — no plan is named and §S.4a's two `expect_contains`
  # rows go missing. Pointing at the world's own transcript restores what the section asks.
  mk_agent_payload "$2" "$1" \
    | jq -c --arg t "$1/s4-transcript.jsonl" '.transcript_path = $t' \
    | env CLAUDE_CODE_SESSION_ID="$2" bash "$PARTY_DP" 2>&1
  return 0
}
# (hoisted to tests/cross-gate-agreement.prelude.sh, which part 2 reads: s4_plan, s4_bind, s4_attest, s4_stop_payload)
s4_pdg() {  # <repo> <sid>
  s4_stop_payload "$1" "$2" "$1/s4-transcript.jsonl" \
    | env CLAUDE_CODE_SESSION_ID="$2" bash "$PARTY_PDG" 2>&1
  return 0
}
s4_prv() {  # <repo> <sid>
  s4_stop_payload "$1" "$2" "$1/s4-transcript.jsonl" \
    | env CLAUDE_CODE_SESSION_ID="$2" bash "$PARTY_PRV" 2>&1
  return 0
}
s4_cs() {  # <repo> <sid>
  rm -f "$1/.bionic/tmp/context-spend.state"
  s4_stop_payload "$1" "$2" "$1/s4-usage.jsonl" \
    | env -u CLAUDE_PROJECT_DIR HOME="$1" CLAUDE_CODE_SESSION_ID="$2" bash "$PARTY_CS" 2>&1
  return 0
}
s4_pk() {  # <repo> <sid>
  roster_header \
    > "$1/.bionic/tmp/roster-$2.state"
  ( cd "$1" && env CLAUDE_CODE_SESSION_ID="$2" CLAUDE_CONFIG_DIR="$1/no-such-config" \
      bash "$PARTY_PK_S" tick 2>&1 )
  return 0
}
s4_ss() {  # <repo> <sid> — SessionStart; stdout is where its listing goes
  jq -nc --arg c "$1" --arg s "$2" \
    '{session_id:$s, transcript_path:"/dev/null", cwd:$c, hook_event_name:"SessionStart", source:"resume"}' \
    | env CLAUDE_CODE_SESSION_ID="$2" BIONIC_CLAUDE_HOME="$1/fakehome" bash "$PARTY_SS" 2>&1
  return 0
}

# (hoisted to tests/cross-gate-agreement.prelude.sh, which part 2 reads: PARTY_SG_W)
# THREE NAMES, ONE PROCESS (epic-23 wave-11, T12). The three used to be three hooks and
# are three functions inside hooks/stop.sh now. The names stay because this section is about
# which RUN each consumer answers for, and each function still answers for its own; what
# changed is that one process delivers all three answers.
PARTY_PDG="$BIONIC_HOOKS_DIR/stop.sh"
PARTY_PRV="$BIONIC_HOOKS_DIR/stop.sh"
PARTY_CS="$BIONIC_HOOKS_DIR/stop.sh"
PARTY_SS="$BIONIC_HOOKS_DIR/session-start.sh"

# THE SEVEN THAT ANNOUNCE, as a table driven by one loop: a per-consumer `case` written out
# seven times is seven places for one of them to be quietly dropped, which is checklist A8's
# defect in another costume. session-start is not a member — it announces nothing — and
# S.4d drives it separately for exactly that reason.
S4_ANNOUNCERS='evidence-gate|s4_eg
governing-skill|s4_gs
dispatch-preflight|s4_dp
patrol-duties-gate|s4_pdg
patrol-revive|s4_prv
context-spend|s4_cs
poker|s4_pk'

# (hoisted to tests/cross-gate-agreement.prelude.sh, which part 2 reads: s4_world)

# ---- S.4a — BOUND-OPEN: the four consumers that name the plan they read --------
#
# Each of these reads the plan for DATA — a step, a budget, a `current:` — so each has a
# rendering that names it. Every row is asserted in BOTH directions on the SAME tree: A's
# session names A and never B, B's names B and never A. One direction alone would pass on a
# consumer that always answered "the newest".
S4_R1=$(s4_world "s4-bound-open")
S4_PA="$S4_R1/.bionic/docs/plans/epic-99/run-a.md"
S4_PB="$S4_R1/.bionic/docs/plans/epic-99/run-b.md"
s4_bind "$S4_R1" "$SID_A" "$S4_PA"
s4_bind "$S4_R1" "$SID_B" "$S4_PB"

# the evidence gate — through §S's own reader, which now takes the session
expect_eq "bound-open: the gate answers session A's plan, at session A's step" \
  "$S4_PA|4" "$(s_eg_read "$S4_R1" "$SID_A")"
expect_eq "…and session B's plan for session B, on the same tree" \
  "$S4_PB|6" "$(s_eg_read "$S4_R1" "$SID_B")"

# the tick — through §S's own reader, likewise
expect_eq "…the tick answers session A's plan too" "$S4_PA|4" "$(s_pk_read "$S4_R1" "$SID_A")"
expect_eq "…and session B's for session B" "$S4_PB|6" "$(s_pk_read "$S4_R1" "$SID_B")"

# the dispatch wall — its budget refusal names the plan the ceiling came from. One open row
# on each session's roster meets `writers=1`, so the refusal fires for both.
# `status=intended` IS WHAT THE CEILING COUNTS. `budget_roster_counts` walks only the
# intended rows — a confirmed row is an agent that already reported in, not an open seat —
# so a confirmed fixture row leaves the wall inert and this pair of assertions vacuous.
#
# AND THE ROW MUST BE LIVE. Since S5 the ceiling counts an `intended` row only while
# `live_agents_has` finds its name in the session transcript — the landing-swept marker it
# used to consult is gone. The `{}` transcript s4_world writes reads NONE, every row counts
# closed, the wall stays inert and both `expect_contains` rows below go missing. Seed the
# same transcript with a fresh ListAgents answer naming both dispatched agents; that is the
# only reason this file names s4a/s4b at all.
cg_live "$S4_R1/s4-transcript.jsonl" "s4a" "s4b"
cg_roster_row "$S4_R1" "$SID_A" "s4a" "as4a-1111111111111111" "" "intended"
cg_roster_row "$S4_R1" "$SID_B" "s4b" "as4b-2222222222222222" "" "intended"
S4_DP_A=$(s4_dp "$S4_R1" "$SID_A")
S4_DP_B=$(s4_dp "$S4_R1" "$SID_B")
expect_contains "…the dispatch wall's ceiling is declared by session A's plan" "$S4_PA" "$S4_DP_A"
expect_absent   "…and never by the neighbour's" "$S4_PB" "$S4_DP_A"
expect_contains "…while session B's ceiling is declared by B's plan" "$S4_PB" "$S4_DP_B"
expect_absent   "…and never by A's" "$S4_PA" "$S4_DP_B"

# context-spend — the one consumer whose answer is a FILE rather than a line. Its state file
# is per-project, not per-session (one root, one file), so the driver clears it per drive;
# that collision is the hook's own design and is not this section's to relitigate.
s4_cs "$S4_R1" "$SID_A" >/dev/null
S4_CS_A=$(cut -f1 < "$S4_R1/.bionic/tmp/context-spend.state" 2>/dev/null)
s4_cs "$S4_R1" "$SID_B" >/dev/null
S4_CS_B=$(cut -f1 < "$S4_R1/.bionic/tmp/context-spend.state" 2>/dev/null)
expect_eq "…context-spend measures session A against A's plan" "$S4_PA" "$S4_CS_A"
expect_eq "…and session B against B's, from the same root" "$S4_PB" "$S4_CS_B"

# THE NEGATIVE THAT COVERS ALL SEVEN AT ONCE: a bound session is never told it fell back.
# This is AC-3's other direction and the cheapest row in the section — it is also the one
# that would fail first if a consumer stopped consulting the binding at all.
while IFS='|' read -r _n _fn; do
  [ -n "$_n" ] || continue
  expect_absent "…$_n never announces a fallback to a session that is bound (AC-3's negative)" \
    "fallback (session unbound)" "$("$_fn" "$S4_R1" "$SID_A")"
done <<S4EOF
$S4_ANNOUNCERS
S4EOF

# ---- S.4b — BOUND-CLOSED: every announcer names ITS OWN closed plan -------------
#
# THIS IS THE ROW THE OTHER FOUR CONSUMERS EXIST IN. governing-skill, patrol-duties-gate and
# patrol-revive read the verdict as a boolean and render nothing for `bound-open`, so the
# only place their answer is observable is the verdict they SPEAK. Here session A is bound to
# a plan that has been delivered while B's plan sits open and NEWEST beside it — the exact
# drift AC-6 is about — and the old root-keyed reader would have handed A the neighbour's
# open run. Each consumer must name A's dead plan and never B's live one.
S4_R2=$(s4_world "s4-bound-closed")
S4_R2A="$S4_R2/.bionic/docs/plans/epic-99/run-a.md"
S4_R2B="$S4_R2/.bionic/docs/plans/epic-99/run-b.md"
s4_close "$S4_R2A"
s_backdate "$S4_R2A"          # closed AND older: B is the newest open plan in this root
s4_bind "$S4_R2" "$SID_A" "$S4_R2A"

while IFS='|' read -r _n _fn; do
  [ -n "$_n" ] || continue
  _out=$("$_fn" "$S4_R2" "$SID_A")
  expect_true    "$_n says the bound plan is closed" \
    grep -qE "$S4_CLOSED_RE" <<<"$_out"
  expect_contains "…naming the plan THIS session is bound to" "$S4_R2A" "$_out"
  expect_absent   "…and never the neighbour's open run, which is also the newest" \
    "$S4_R2B" "$_out"
  expect_false   "…and never calls it a fallback (a binding is a commitment, AC-6)" \
    grep -qE "$S4_FALLBACK_RE" <<<"$_out"
done <<S4EOF
$S4_ANNOUNCERS
S4EOF

# ---- S.4c — FALLBACK: unbound, every announcer names the SAME newest plan --------
#
# AC-3 in one fixture: an unbound session is told which plan the root would have handed it.
# Since wave-23-fixit-1810 (REQ-1, D1) that plan is announced and never acted on — §UB pins
# the acting half, arm by arm. The agreement here is between the seven, not between two
# sessions — they must all name the one plan `active_run` would have named, which is the
# newest OPEN one. A consumer that announced something else, or went silent, splits from
# the other six here.
S4_R3=$(s4_world "s4-fallback")
S4_R3B="$S4_R3/.bionic/docs/plans/epic-99/run-b.md"
s4_unbind "$S4_R3" "$SID_A"

while IFS='|' read -r _n _fn; do
  [ -n "$_n" ] || continue
  _out=$("$_fn" "$S4_R3" "$SID_A")
  expect_true    "$_n announces the newest-plan fallback for an unbound session (AC-3)" \
    grep -qE "$S4_FALLBACK_RE" <<<"$_out"
  expect_contains "…naming the newest OPEN plan, which is what active_run would have said" \
    "$S4_R3B" "$_out"
done <<S4EOF
$S4_ANNOUNCERS
S4EOF

# ---- S.4f — BOUND-UNREADABLE: every reader names the plan it cannot read ------------
#
# (wave-20 T1, REQ-2, D2; AC-2.1, AC-2.3.) Session A is bound to a plan that is still on
# disk at mode 000, while B's plan sits open and NEWEST beside it. That is the world where a
# reader that took the unreadable plan for "closed" says "no open run" and stops protecting a
# run that may be mid-flight, and a reader whose default arm re-resolved lands on B. So every
# announcer must name A's plan as unreadable, never B's, never call A closed, never say
# fallback — and the evidence gate, the one of the seven that owns the commit, refuses it.
#
# PRIVILEGE IS CHECKED FIRST: a suite running as root reads a mode-000 file, and every row
# below would then pass on a readable plan. The premise row makes that visible.
S4_UNREADABLE_RE='bound plan unreadable — '
S4_R6=$(s4_world "s4-bound-unreadable")
S4_R6A="$S4_R6/.bionic/docs/plans/epic-99/run-a.md"
S4_R6B="$S4_R6/.bionic/docs/plans/epic-99/run-b.md"
s4_bind "$S4_R6" "$SID_A" "$S4_R6A"
chmod 000 "$S4_R6A"
expect_true "S.4f premise: A's plan exists and this user cannot read it" \
  bash -c '[ -e "$1" ] && [ ! -r "$1" ]' _ "$S4_R6A"

while IFS='|' read -r _n _fn; do
  [ -n "$_n" ] || continue
  _out=$("$_fn" "$S4_R6" "$SID_A")
  expect_true    "$_n says the bound plan is unreadable" \
    grep -qE "$S4_UNREADABLE_RE" <<<"$_out"
  expect_contains "…naming the plan THIS session is bound to" "$S4_R6A" "$_out"
  expect_absent   "…and never the neighbour's open run, which is also the newest" \
    "$S4_R6B" "$_out"
  expect_absent   "…and never says this session has no open run" "no open run" "$_out"
  expect_false   "…and never calls it closed" grep -qE "$S4_CLOSED_RE" <<<"$_out"
  expect_false   "…and never calls it a fallback" grep -qE "$S4_FALLBACK_RE" <<<"$_out"
done <<S4EOF
$S4_ANNOUNCERS
S4EOF

# THE GATE REFUSES, and the refusal is the gate's own — an exit 2 with the commit verb.
S4_R6_EG_RC=0
mk_bash_payload "$SID_A" "$SANDBOX/t.jsonl" "$S4_R6" "git commit -m x" \
  | env -u CLAUDE_PROJECT_DIR HOME="$S4_R6" CLAUDE_CODE_SESSION_ID="$SID_A" \
      bash "$PARTY_EG" >/dev/null 2>&1 || S4_R6_EG_RC=$?
expect_eq "…the evidence gate refuses the commit (exit 2) rather than admitting it" 2 "$S4_R6_EG_RC"
expect_contains "…and says the bound plan cannot be read" "commit refused — the bound plan cannot be read" \
  "$(s4_eg "$S4_R6" "$SID_A")"

# THE STOP WALL HOLDS THE TURN, once: patrol-duties refuses the Stop naming the plan. The
# re-entered Stop (stop_hook_active) is let through by hooks/stop.sh's one guard, so the
# refusal cannot loop.
expect_contains "…the stop wall refuses the turn naming the unreadable plan" \
  "stop refused — the bound plan cannot be read" "$(s4_pdg "$S4_R6" "$SID_A")"
chmod 644 "$S4_R6A"

# ---- S.4g — ONE UNREADABLE PLAN, THREE READERS: session_run, adopt and the walk agree ----
#
# (wave-20 T18, REQ-2, D2; T1's carry-over.) §S.4f drives the seven readers of the SESSION'S
# OWN binding. Two more readers take a plan's verdict without going through it: `adopt`, which
# asks it of the plan each FOREIGN row names, and the unbound candidate walk (`open_runs`,
# `active_plan`), which asks it of every plan in the root. Both read a plan that is there and
# cannot be read as if it were not there at all — adopt counted its rows `closed=` and printed
# nothing, the walk dropped it without a word. So the three are driven over ONE mode-000 plan
# and must give ONE answer about it: unreadable, never closed, never open.
#
# THE ADOPTER IS BOUND TO THAT PLAN, so its partition alone would say `own` and write the row:
# a reader that fell through to the partition fails here, not only one that called it closed.
S4_R7=$(s4_world "s4-unreadable-three")
S4_R7A="$S4_R7/.bionic/docs/plans/epic-99/run-a.md"
S4_R7B="$S4_R7/.bionic/docs/plans/epic-99/run-b.md"
S4_R7_PRED="d4d4d4d4-7777-4bbb-8ccc-000000000077"
S4_R7_ID="as4g-pred-7777777777777777"
s4_bind "$S4_R7" "$SID_A" "$S4_R7A"
roster_row_fixture status=identified session="$S4_R7_PRED" name=s4g-writer \
  agent_id="$S4_R7_ID" launched_at=2026-08-05T00:00:00Z tool_use_id=toolu_01S4GFIX \
  plan="$S4_R7A" >> "$S4_R7/.bionic/tmp/roster-$S4_R7_PRED.state"

# ONE CLASSIFIER PER READER, each reducing that reader's own channel to one word about plan A:
# `unreadable`, `closed`, `open`, or `silent` (the reader said nothing about A at all). The
# two that also keep their whole channel are called with stdout to a FILE, never inside
# `$( )`, so the globals they set survive into this shell.
s4g_sr() {  # <repo> <sid> -> session_run's word for its bound plan
  local out
  out=$(bash -c '. "$1" || exit 1; session_run "$2" "$3"' _ "$RUN_LIB" "$1" "$2" 2>/dev/null)
  case "$out" in
    "bound-unreadable $S4_R7A") echo unreadable ;;
    "bound-closed $S4_R7A")     echo closed ;;
    "bound-open $S4_R7A")       echo open ;;
    *)                          echo "silent:$out" ;;
  esac
}
s4g_adopt() {  # <repo> <sid> -> adopt's word for the row naming plan A; sets S4G_ADOPT_OUT
  S4G_ADOPT_OUT=$( cd "$1" && env CLAUDE_CODE_SESSION_ID="$2" bash "$PARTY_PK_S" adopt 2>&1 )
  local row closed
  row=$(printf '%s\n' "$S4G_ADOPT_OUT" | grep "^poker-adopt/v1|.*|name=s4g-writer|" | head -1)
  closed=$(printf '%s\n' "$S4G_ADOPT_OUT" | grep '^poker-adopt/v1|.*|scanned=' | tail -1 \
    | tr '|' '\n' | grep '^closed=' | cut -d= -f2)
  case "$row" in
    *'|partition=unreadable'*)  echo unreadable ;;
    *'|partition=own'*|*'|partition=all'*) echo open ;;
    '') [ "${closed:-0}" -gt 0 ] && echo closed || echo silent ;;
    *)  echo "listed:$row" ;;
  esac
}
s4g_walk() {  # <repo> -> the unbound walk's word for plan A; sets S4G_WALK_OUT / S4G_WALK_ERR
  S4G_WALK_OUT=$(bash -c '. "$1" || exit 1; open_runs "$2"' _ "$RUN_LIB" "$1" 2>"$SANDBOX/s4g.err")
  S4G_WALK_ERR=$(cat "$SANDBOX/s4g.err")
  if grep -qxF "bound-unreadable $S4_R7A" <<<"$S4G_WALK_ERR"; then echo unreadable
  elif grep -qxF "$S4_R7A" <<<"$S4G_WALK_OUT"; then echo open
  else echo silent
  fi
}

chmod 000 "$S4_R7A"
expect_true "S.4g premise: plan A exists and this user cannot read it" \
  bash -c '[ -e "$1" ] && [ ! -r "$1" ]' _ "$S4_R7A"
S4G_SR=$(s4g_sr "$S4_R7" "$SID_A")
s4g_adopt "$S4_R7" "$SID_A" > "$SANDBOX/s4g.adopt"; S4G_AD=$(cat "$SANDBOX/s4g.adopt")
s4g_walk "$S4_R7" > "$SANDBOX/s4g.walk"; S4G_WK=$(cat "$SANDBOX/s4g.walk")
expect_eq "S.4g the three readers agree: session_run|adopt|walk all say A is unreadable" \
  "unreadable|unreadable|unreadable" "$S4G_SR|$S4G_AD|$S4G_WK"
expect_contains "…adopt names the plan it cannot read" "$S4_R7A" "$S4G_ADOPT_OUT"
expect_absent   "…and never takes the row onto the adopter's roster" "$S4_R7_ID" \
  "$(cat "$S4_R7/.bionic/tmp/roster-$SID_A.state" 2>/dev/null)"
expect_contains "…the walk still answers for the run it CAN read — B is a member" \
  "$S4_R7B" "$S4G_WALK_OUT"
expect_absent   "…and A is not" "$S4_R7A" "$S4G_WALK_OUT"

# THE PAIRED POSITIVE, ON THE SAME WORLD: one fact moves — A's mode — and all three readers
# move together to `open`. Without it, the row above passes against three readers that simply
# agree on saying nothing.
chmod 644 "$S4_R7A"
S4G_SR=$(s4g_sr "$S4_R7" "$SID_A")
s4g_adopt "$S4_R7" "$SID_A" > "$SANDBOX/s4g.adopt"; S4G_AD=$(cat "$SANDBOX/s4g.adopt")
s4g_walk "$S4_R7" > "$SANDBOX/s4g.walk"; S4G_WK=$(cat "$SANDBOX/s4g.walk")
expect_eq "…A readable again: session_run|adopt|walk all say open" \
  "open|open|open" "$S4G_SR|$S4G_AD|$S4G_WK"
expect_eq "…and the walk names nothing on stderr" "" "$S4G_WALK_ERR"

# ---- S.4d — session-start: silent when bound, a listing when not (AC-5) ---------
#
# The eighth consumer, and the one with no announcement at all. Its whole rendering IS the
# open-run listing, and the listing is what a session gets when it is NOT bound — so its
# agreement row is the pair, driven over the same root: bound sees nothing, unbound sees
# every open run and the verb that ends the ambiguity.
# WHAT IS ABSENT FOR A BOUND SESSION IS THE LISTING, not all output. session-start still
# prints its ordinary engaged block — the roster and stamp report it has always printed —
# and falls through rather than exiting; the open-run listing is the part AC-5 adds, and it
# is the part a bound session must not see. Asserting total silence would pin a claim about
# the whole hook that this section is not about and that its own suite already owns.
S4_SS_BOUND=$(s4_ss "$S4_R1" "$SID_A")
expect_absent "session-start does not list the open runs to a session that is already bound (AC-5)" \
  "open runs exist here" "$S4_SS_BOUND"
expect_absent "…and names neither run's path at it" "$S4_PB" "$S4_SS_BOUND"
expect_absent "…not even its own" "$S4_PA" "$S4_SS_BOUND"
S4_SS_UNBOUND=$(s4_ss "$S4_R3" "$SID_A")
# Step-6 P3 (S10b): the listing prints paths RELATIVE to the docs root, so the set is
# asserted by its relative spellings — the absolute form is what the wave stopped printing.
expect_contains "…and lists both open runs to one that is not" "plans/epic-99/run-b.md" "$S4_SS_UNBOUND"
expect_contains "…naming A's too — the listing is the SET, not a verdict" \
  "plans/epic-99/run-a.md" "$S4_SS_UNBOUND"
expect_contains "…and names the verb that ends the ambiguity" \
  "session-poker.sh bind" "$S4_SS_UNBOUND"

# ---- S.4e — THE DISCRIMINATOR: mutate session_run, and EVERY party moves ---------
#
# §A2's pattern, applied to the reader this wave added. The eight rows above prove the fleet
# AGREES; they do not prove the agreement is produced by the library rather than by eight
# copies that happen to match today. So `session_run` is doctored in a COPY of the library —
# the binding branch is skipped, which is precisely "revert to the pre-wave rule" — and the
# consumers are re-driven out of a throwaway tree shaped like the shipped plugin. A party
# that kept its own answer stays green here and nowhere else.
#
# The shipped library is never touched: the mutant is a copy, and the parties are copies
# beside it, which is also what makes them load the mutant at all (the loader's first
# candidate is `$(dirname "$0")/../scripts/lib`).
S4_MUT="$SANDBOX/s4-mutant"
mkdir -p "$S4_MUT/hooks" "$S4_MUT/scripts/lib"
cp "$LIB_DIR_SRC"/*.sh "$S4_MUT/scripts/lib/" 2>/dev/null
cp "$BIONIC_HOOKS_DIR"/*.sh "$S4_MUT/hooks/" 2>/dev/null; cp -R "$BIONIC_HOOKS_DIR/poker" "$S4_MUT/hooks/" 2>/dev/null
anchor file payload/scripts/lib/run.sh '  if plan=$(session_plan "$root" "$sid"); then'
sed 's/  if plan=$(session_plan "$root" "$sid"); then/  if false \&\& plan=$(session_plan "$root" "$sid"); then/' \
  "$RUN_LIB" > "$S4_MUT/scripts/lib/run.sh"

s4_repoint() {  # aim every driver at the mutant tree
  PARTY_EG="$S4_MUT/hooks/bash-walls.sh"
  PARTY_SG_W="$S4_MUT/hooks/canonical-sdlc-governing-skill.sh"
  PARTY_DP="$S4_MUT/hooks/dispatch-preflight.sh"
  PARTY_PDG="$S4_MUT/hooks/stop.sh"
  PARTY_PRV="$S4_MUT/hooks/stop.sh"
  PARTY_CS="$S4_MUT/hooks/stop.sh"
  PARTY_PK_S="$S4_MUT/hooks/session-poker.sh"
}
s4_restore() {
  PARTY_EG="${W1R_PARTY_EG:-$BIONIC_HOOKS_DIR/bash-walls.sh}"
  PARTY_SG_W="$BIONIC_HOOKS_DIR/canonical-sdlc-governing-skill.sh"
  PARTY_DP="${W1R_PARTY_DP:-$BIONIC_HOOKS_DIR/dispatch-preflight.sh}"
  PARTY_PDG="$BIONIC_HOOKS_DIR/stop.sh"
  PARTY_PRV="$BIONIC_HOOKS_DIR/stop.sh"
  PARTY_CS="$BIONIC_HOOKS_DIR/stop.sh"
  PARTY_PK_S="${W1R_PARTY_PK:-$BIONIC_HOOKS_DIR/session-poker.sh}"
}

# THE CONTROL FIRST. The same throwaway tree with an UNMUTATED library must give the same
# answers the shipped tree did, or every move below is the copying and not the mutation.
cp "$RUN_LIB" "$S4_MUT/scripts/lib/run.sh"
s4_repoint
S4_CTRL=$(s4_pk "$S4_R2" "$SID_A")
expect_contains "control: the copied tree with an UNMUTATED library still honours the binding" \
  "$S4_R2A" "$S4_CTRL"

anchor file payload/scripts/lib/run.sh '  if plan=$(session_plan "$root" "$sid"); then'
sed 's/  if plan=$(session_plan "$root" "$sid"); then/  if false \&\& plan=$(session_plan "$root" "$sid"); then/' \
  "$RUN_LIB" > "$S4_MUT/scripts/lib/run.sh"

# EVERY ANNOUNCER MOVES. On the S.4b world session A is bound to a CLOSED plan while the
# neighbour's is open and newest, so the two answers are maximally far apart: honouring the
# binding says "closed, plan A"; ignoring it says "fallback, plan B". Both halves are
# asserted for each consumer — the closed line must be GONE and the neighbour's plan must
# now be NAMED — because either alone would pass on a consumer that had simply fallen silent.
while IFS='|' read -r _n _fn; do
  [ -n "$_n" ] || continue
  _out=$("$_fn" "$S4_R2" "$SID_A")
  expect_false   "mutated session_run: $_n stops saying the bound plan is closed" \
    grep -qE "$S4_CLOSED_RE" <<<"$_out"
  expect_contains "…and answers for the neighbour's run instead — the pre-wave bug, reproduced" \
    "$S4_R2B" "$_out"
done <<S4EOF
$S4_ANNOUNCERS
S4EOF

s4_restore
# AND THE RESTORE IS PROVED, not assumed: the same drive that moved must move back, or every
# section after this one is running against a mutant.
expect_contains "restored: the shipped tree honours the binding again" \
  "$S4_R2A" "$(s4_pk "$S4_R2" "$SID_A")"

# ============================================================
section "B2 — THE SESSION'S BOUND PLAN: three writers, one marker shape"
# ============================================================
#
# THE OWNERSHIP-TABLE ROW (spec §Design): "the session's bound plan · owning module
# lib/binding.sh bind_plan · rendering surfaces: engage.sh, poker `bind`, governing-skill
# bind-on-write · agreement test: three callers produce one marker shape; a doctored caller
# goes red".
#
# WHY A SHAPE AND NOT A VALUE. The marker is read by `session_plan`, which takes the `plan=`
# line and nothing else — so a caller that wrote the two lines in the other order, or dropped
# `engaged_at=`, or left the file 0644, would still be READ correctly today and would still
# be wrong: `engaged_at` is what the re-engagement path carries forward, and 0600 is the
# invariant the marker has had since it existed. A shape that only one of three writers keeps
# is a shape the next reader cannot rely on.
#
# ONE REPOSITORY, THREE CALLERS, THREE SESSIONS. Same root, same plan, three session ids —
# so the only thing that can differ between the three markers is the WRITER. The three are
# then compared to each other after the timestamp VALUE is masked (it is a clock reading, not
# a shape), which is what leaves the comparison about the shape.

B2_REPO=$(new_repo "b2-one-marker-shape")
B2_PLAN="$B2_REPO/.bionic/docs/plans/epic-99/only-run.md"
write_plan "$B2_PLAN" "current: 4"
B2_SID_E="e2e2e2e2-1111-4bbb-8ccc-000000000001"   # engage.sh's session
B2_SID_P="e2e2e2e2-2222-4bbb-8ccc-000000000002"   # poker bind's session
B2_SID_G="e2e2e2e2-3333-4bbb-8ccc-000000000003"   # the governing skill's session
B2_MARK="$B2_REPO/.bionic/tmp/engaged-"

PARTY_ENGAGE="$BIONIC_HOOKS_DIR/engage.sh"

# b2_shape <marker> -> the marker with the timestamp VALUE masked, plus its mode
b2_shape() {
  [ -f "$1" ] || { printf 'ABSENT\n'; return 0; }
  sed 's/^engaged_at=.*/engaged_at=<iso>/' "$1"
  printf 'mode=%s\n' "$(ls -l "$1" | cut -c1-10)"
}

# WRITER 1 — the engage hook, on the act that creates the relationship (AC-7). Exactly one
# open run in this root, so engagement binds it rather than writing `plan=none`.
jq -nc --arg c "$B2_REPO" --arg s "$B2_SID_E" \
  '{session_id:$s, cwd:$c, hook_event_name:"PreToolUse", tool_name:"Skill",
    tool_input:{skill:"bionic:canonical-sdlc"}}' \
  | ( cd "$B2_REPO" && env CLAUDE_CODE_SESSION_ID="$B2_SID_E" bash "$PARTY_ENGAGE" ) >/dev/null 2>&1

# WRITER 2 — the poker's `bind` verb, the hand-driven one (AC-8). It refuses an unengaged
# caller, so the session is engaged first exactly as the field produces it.
: > "${B2_MARK}${B2_SID_P}.state"
( cd "$B2_REPO" && env CLAUDE_CODE_SESSION_ID="$B2_SID_P" bash "$SPO" bind "$B2_PLAN" ) >/dev/null 2>&1

# WRITER 3 — the governing skill's bind-on-first-write, at PostToolUse (AC-9). The plan
# already exists here, which is what the arm requires; `tool_response.type` says `create`.
: > "${B2_MARK}${B2_SID_G}.state"
jq -n --arg p "$B2_PLAN" --arg s "$B2_SID_G" \
  '{session_id:$s, hook_event_name:"PostToolUse", tool_name:"Write",
    tool_input:{file_path:$p, content:"x"}, tool_response:{type:"create", filePath:$p}}' \
  | env HOME="$B2_REPO" CLAUDE_CODE_SESSION_ID="$B2_SID_G" bash "$PARTY_SG_W" >/dev/null 2>&1

B2_E=$(b2_shape "${B2_MARK}${B2_SID_E}.state")
B2_P=$(b2_shape "${B2_MARK}${B2_SID_P}.state")
B2_G=$(b2_shape "${B2_MARK}${B2_SID_G}.state")

# NON-VACUITY FIRST. Three empty strings compare equal, and an empty marker is what a
# refusing writer leaves behind — so each answer is pinned by VALUE before the three are
# compared to each other.
expect_contains "engage.sh bound the sole open run" "plan=$B2_PLAN" "$B2_E"
expect_contains "poker bind wrote the plan it was handed"  "plan=$B2_PLAN" "$B2_P"
expect_contains "the governing skill bound the plan its Write created" "plan=$B2_PLAN" "$B2_G"

expect_eq "engage.sh and poker bind write ONE marker shape" "$B2_E" "$B2_P"
expect_eq "…and so does the governing skill's bind-on-write" "$B2_E" "$B2_G"
# S5a NOTE (AC-12 migration): this needle is genuinely two lines, and the framework's
# expect_contains (a `case` glob) requires them contiguous and in order — stricter than
# the pre-migration private definition (`grep -F`, which reads the embedded newline as
# alternation and would have passed on EITHER line alone). b2_shape's own output always
# writes `plan=` then `engaged_at=` adjacent, so this call site never relied on the
# looser reading; before/after tallies for this assertion agree (see s5a-report.md).
expect_contains "…which is the two-line shape, plan first" "plan=$B2_PLAN
engaged_at=<iso>" "$B2_E"
expect_contains "…at mode 0600, the invariant the marker has always carried" "rw-------" "$B2_E"

# THE DISCRIMINATOR — one caller doctored, and the pin must go red. `engage.sh` is copied
# into a throwaway plugin-shaped tree and its `bind_plan` call is replaced by an inline
# write, which is exactly the shape this file carried BEFORE lib/binding.sh existed
# (hooks/engage.sh:275-290, pre-wave) — a plausible regression, not damage. The shipped hook
# is never touched.
B2_MUT="$SANDBOX/b2-mutant"
mkdir -p "$B2_MUT/hooks" "$B2_MUT/scripts/lib"
cp "$LIB_DIR_SRC"/*.sh "$B2_MUT/scripts/lib/" 2>/dev/null
cp "$BIONIC_HOOKS_DIR"/*.sh "$B2_MUT/hooks/" 2>/dev/null; cp -R "$BIONIC_HOOKS_DIR/poker" "$B2_MUT/hooks/" 2>/dev/null
anchor file hooks/engage.sh 'bind_plan "$REPO" "$SID"'
awk '
  /bind_plan "\$REPO" "\$SID"/ && !done {
    print "    printf '"'"'engaged_at=%s\\nplan=%s\\n'"'"' \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\" \"$PLAN\" > \"$MARKER\""
    done = 1
    next
  }
  { print }
' "$PARTY_ENGAGE" > "$B2_MUT/hooks/engage.sh"

B2_SID_M="e2e2e2e2-4444-4bbb-8ccc-000000000004"
jq -nc --arg c "$B2_REPO" --arg s "$B2_SID_M" \
  '{session_id:$s, cwd:$c, hook_event_name:"PreToolUse", tool_name:"Skill",
    tool_input:{skill:"bionic:canonical-sdlc"}}' \
  | ( cd "$B2_REPO" && env CLAUDE_CODE_SESSION_ID="$B2_SID_M" bash "$B2_MUT/hooks/engage.sh" ) >/dev/null 2>&1
B2_M=$(b2_shape "${B2_MARK}${B2_SID_M}.state")
expect_eq "a doctored writer's marker is NOT the shape the other two agree on (§B2 discriminates)" \
  "no" "$([ "$B2_M" = "$B2_P" ] && echo yes || echo no)"
# …AND IT IS NOT DISCRIMINATED BY BEING EMPTY. The mutant really did write a marker naming
# the same plan; what differs is only the shape, which is the whole claim of this section.
expect_contains "…while still naming the same plan, so the difference is the SHAPE" \
  "plan=$B2_PLAN" "$B2_M"

# ============================================================
section "OR — THE OPEN-RUN SET: active_run's answer is always a member of open_runs"
# ============================================================
#
# THE OWNERSHIP-TABLE ROW (spec §Design): "the open-run set · owning module lib/run.sh
# open_runs · rendering surfaces: engage uniqueness, session-start listing, poker `bind`
# validation". `tests/run-predicate.test.sh` owns the set's own behaviour over 0/1/2-member
# fixtures; what belongs HERE is the relation between the set and the answer every pre-wave
# reader still takes — because three surfaces now decide from the SET while every fallback in
# the fleet still decides from `active_run`, and a set that did not contain that answer would
# let engagement bind a plan no consumer would then resolve.
#
# THE SENTENCE IS QUALIFIED, AND THE QUALIFICATION IS THE POINT (S1 assumption 1). "Line 1 of
# `open_runs` equals `active_run`'s answer" is true only WHEN `active_run` HAS an answer. The
# case where it does not is not an edge: the newest plan in the root is CLOSED, `active_run`
# exits 1 with nothing while the set is non-empty, and that is precisely the state a
# session-keyed reader exists to survive. Writing the unqualified sentence here would pin a
# claim the library contradicts by design.

OR_LIB_SRC="$RUN_LIB"
# THE STATUS COMES BACK THROUGH THE STRING, not through a variable. `$( … )` is a SUBSHELL:
# a status assigned inside it is discarded at the closing paren, so the obvious spelling
# (`out=$(…); OR_ST=$?`) captures the SUBSHELL's status — always 0 here — and an `OR_ST` read
# afterwards is either stale or, under this file's `set -u`, an abort. Both halves ride one
# capture, separated by a byte no path can contain.
or_ask() {  # <root> <function> -> sets OR_OUT and OR_ST
  local root="$1"; shift
  local raw
  raw=$( . "$OR_LIB_SRC" >/dev/null 2>&1; "$@" "$root" 2>/dev/null; printf '\037%s' "$?" )
  OR_ST="${raw##*$'\037'}"
  OR_OUT="${raw%$'\037'*}"
  # …AND THE TRAILING NEWLINE GOES WITH IT. `$( … )` strips trailing newlines from the whole
  # capture, but the status marker sits after them, so they survive inside OR_OUT and every
  # exact compare below would be off by one byte.
  OR_OUT="${OR_OUT%$'\n'}"
  printf '%s' "$OR_OUT"
}

# --- OR.1 two open plans: the set has both, and line 1 IS active_run's answer ---
OR_R1=$(new_repo "or-two-open")
write_plan "$OR_R1/.bionic/docs/plans/epic-99/older.md" "current: 4"
write_plan "$OR_R1/.bionic/docs/plans/epic-99/newest.md" "current: 6"
s_backdate "$OR_R1/.bionic/docs/plans/epic-99/older.md"
or_ask "$OR_R1" open_runs >/dev/null;  OR_SET="$OR_OUT"
or_ask "$OR_R1" active_run >/dev/null; OR_AR="$OR_OUT"; OR_AR_ST="$OR_ST"
expect_eq "the set has both open plans (non-vacuity: this is not an empty answer)" "2" \
  "$(printf '%s\n' "$OR_SET" | grep -c '\.md$')"
expect_eq "active_run has an answer here" "0" "$OR_AR_ST"
expect_eq "…and it is line 1 of the set, newest first" \
  "$OR_AR" "$(printf '%s\n' "$OR_SET" | head -1)"
expect_true "…and active_run's answer is a MEMBER of the set" \
  grep -qxF -- "$OR_AR" <<<"$OR_SET"

# --- OR.2 a CLOSED plan is in neither, and both answers move together -----------
OR_R2=$(new_repo "or-closed-newest")
write_plan "$OR_R2/.bionic/docs/plans/epic-99/open-older.md" "current: 4"
s4_close "$OR_R2/.bionic/docs/plans/epic-99/closed-newest.md"
s_backdate "$OR_R2/.bionic/docs/plans/epic-99/open-older.md"
or_ask "$OR_R2" open_runs >/dev/null;  OR_SET2="$OR_OUT"
or_ask "$OR_R2" active_run >/dev/null; OR_AR2="$OR_OUT"; OR_AR2_ST="$OR_ST"
# THE QUALIFICATION, ASSERTED RATHER THAN NARRATED. The newest file is closed, so `active_run`
# has NO answer while the set is not empty — the one case where the equality above does not
# hold, and the reason its sentence carries a "when".
expect_eq "the newest plan is closed, so active_run has no answer at all" "1" "$OR_AR2_ST"
expect_eq "…while the set is NOT empty: it still holds the older open plan" \
  "$OR_R2/.bionic/docs/plans/epic-99/open-older.md" "$OR_SET2"
expect_absent "…and the closed plan is in neither" \
  "closed-newest.md" "$OR_SET2$OR_AR2"

# --- OR.3 THE DISCRIMINATOR: mutate run_open, and both readers move together ----
#
# `run_open` is the one predicate `open_runs` and `active_run` share. Force it open and the
# closed plan joins the set AND becomes active_run's answer — so a mutation to the shared
# predicate moves BOTH, which is what "one owner" means here. A copy is mutated; the shipped
# library is untouched.
OR_MUT="$SANDBOX/or-mutant-run.sh"
anchor insert payload/scripts/lib/run.sh 'run_open() {'
awk '
  /^run_open\(\) \{/ && !d { print; print "  [ -f \"$1\" ] && return 0"; d = 1; next }
  { print }
' "$OR_LIB_SRC" > "$OR_MUT"
OR_LIB_SRC="$OR_MUT"
or_ask "$OR_R2" open_runs >/dev/null;  OR_SET3="$OR_OUT"
or_ask "$OR_R2" active_run >/dev/null; OR_AR3="$OR_OUT"; OR_AR3_ST="$OR_ST"
OR_LIB_SRC="$RUN_LIB"
expect_eq "mutated run_open: the closed plan joins the set" "2" \
  "$(printf '%s\n' "$OR_SET3" | grep -c '\.md$')"
expect_eq "…and becomes active_run's answer, which it was not a moment ago" "0" "$OR_AR3_ST"
expect_contains "…which is the closed plan itself" "closed-newest.md" "$OR_AR3"
expect_true "…and the relation still holds: the answer is still a member of the set" \
  grep -qxF -- "$OR_AR3" <<<"$OR_SET3"
or_ask "$OR_R2" active_run >/dev/null
expect_eq "restored: the shipped library answers as it did before the mutation" \
  "$OR_AR2_ST" "$OR_ST"

# ============================================================
section "RA — ROSTER ATTRIBUTION: two row writers, one plan= field"
# ============================================================
#
# THE OWNERSHIP-TABLE ROW (spec §Design): "roster attribution · owning module
# dispatch-preflight.sh row writer · rendering surface: `adopt`'s partition".
#
# TWO WRITERS PUT ROWS ON A ROSTER. `hooks/dispatch-preflight.sh` writes the row for an agent
# this session LAUNCHES; `hooks/session-poker.sh adopt` writes the row for an agent this
# session TAKES OVER. `adopt`'s partition then reads `plan=` off every foreign row to decide
# what is adoptable — so the field has to mean the same thing on both, or the partition is
# reading two schemas and calling them one. It shipped on the dispatch writer alone (S5) and
# was added to the adopt writer at S8; before that an adopted row was the one row on any
# roster carrying no attribution, and a THIRD session bound to the same plan re-read this
# session's own adoption as `unattributed` and declined to take it.
#
# THE VALUE IS THE WRITING SESSION'S BINDING IN BOTH CASES — not the launching session's, and
# not the row's previous owner's. That is what makes the field answer one question ("which
# run does this row belong to") rather than two.
#
# ONE FIXTURE, BOTH WRITERS, ONE EXTRACTOR. The field is pulled out by KEY, not by position,
# by the same helper for both rows — a positional read would pass on two rows that agreed
# about the value and disagreed about where it sits.

ra_field() {  # <row> <key> -> the field's value
  printf '%s' "$1" | tr '|' '\n' | grep "^$2=" | head -1 | cut -d= -f2-
}

RA_REPO=$(new_repo "ra-attribution")
RA_PLAN="$RA_REPO/.bionic/docs/plans/epic-99/ra-run.md"
write_plan "$RA_PLAN" "current: 4"
RA_PRED="ra111111-2222-4bbb-8ccc-000000000099"
RA_PRED_ID="arapred-9999999999999999"
s4_attest "$RA_REPO" "$SID_A"

# WRITER 1 — the dispatch wall, from a session bound to RA_PLAN.
s4_bind "$RA_REPO" "$SID_A" "$RA_PLAN"
mk_agent_payload "$SID_A" "$RA_REPO" | env CLAUDE_CODE_SESSION_ID="$SID_A" bash "$PARTY_DP" >/dev/null 2>&1
RA_DISPATCH_ROW=$(grep '^roster-state/' "$RA_REPO/.bionic/tmp/roster-$SID_A.state" 2>/dev/null | tail -1)

# WRITER 2 — `adopt`, from a session bound to the SAME plan, over a predecessor's row.
# The predecessor's row carries `plan=` too, so it partitions as `own` and is journalled;
# that it does so is §17's claim in tests/session-poker.test.sh, not this section's.
mkdir -p "$CLAUDE_CONFIG_DIR/projects/$(printf '%s' "$RA_REPO" | sed 's/[^a-zA-Z0-9]/-/g')/$RA_PRED/subagents"
roster_row_fixture status=identified session="$RA_PRED" name=ra-writer \
  agent_id="$RA_PRED_ID" launched_at=2026-08-05T00:00:00Z tool_use_id=toolu_01RAFIX \
  plan="$RA_PLAN" >> "$RA_REPO/.bionic/tmp/roster-$RA_PRED.state"
s4_bind "$RA_REPO" "$SID_B" "$RA_PLAN"
( cd "$RA_REPO" && env CLAUDE_CODE_SESSION_ID="$SID_B" bash "$SPO" adopt ) >/dev/null 2>&1
RA_ADOPT_ROW=$(grep "agent_id=$RA_PRED_ID" "$RA_REPO/.bionic/tmp/roster-$SID_B.state" 2>/dev/null | tail -1)

# NON-VACUITY: both rows exist and are not the same row.
expect_eq "the dispatch wall wrote a row" "yes" \
  "$([ -n "$RA_DISPATCH_ROW" ] && echo yes || echo no)"
expect_eq "…and adopt wrote one on the other session's roster" "yes" \
  "$([ -n "$RA_ADOPT_ROW" ] && echo yes || echo no)"
expect_eq "…and they are two different rows" "no" \
  "$([ "$RA_DISPATCH_ROW" = "$RA_ADOPT_ROW" ] && echo yes || echo no)"

# THE AGREEMENT: same field name, same value rule, same position.
expect_eq "the dispatched row is attributed to its writer's bound plan" \
  "$RA_PLAN" "$(ra_field "$RA_DISPATCH_ROW" plan)"
expect_eq "…and the adopted row to ITS writer's bound plan, by the same rule" \
  "$RA_PLAN" "$(ra_field "$RA_ADOPT_ROW" plan)"
expect_eq "…the field is last on both rows, so a positional reader sees one schema" \
  "$(printf '%s' "$RA_DISPATCH_ROW" | sed 's/.*|\(plan=[^|]*\)$/\1/')" \
  "$(printf '%s' "$RA_ADOPT_ROW" | sed 's/.*|\(plan=[^|]*\)$/\1/')"

# THE UNBOUND SPELLING IS ALSO ONE WORD. Both writers say the literal `none`, never an empty
# field — an empty `plan=` and an absent `plan=` are the same thing to a key-based reader,
# and `adopt` needs to tell "this session had no binding" from "this row predates the field".
RA_REPO_U=$(new_repo "ra-unbound")
RA_PLAN_U="$RA_REPO_U/.bionic/docs/plans/epic-99/ra-run.md"
write_plan "$RA_PLAN_U" "current: 4"
s4_attest "$RA_REPO_U" "$SID_A"
# A READ-ONLY ROLE: an unbound session's writer is refused with the bind instruction and
# writes no row (wave-23-fixit-1810, REQ-1, D1); a researcher is admitted and rostered.
mk_agent_payload "$SID_A" "$RA_REPO_U" | jq -c '.tool_input.subagent_type = "bionic:researcher"' \
  | env CLAUDE_CODE_SESSION_ID="$SID_A" bash "$PARTY_DP" >/dev/null 2>&1
RA_DISPATCH_U=$(grep '^roster-state/' "$RA_REPO_U/.bionic/tmp/roster-$SID_A.state" 2>/dev/null | tail -1)
roster_row_fixture status=identified session="$RA_PRED" name=ra-writer \
  agent_id="$RA_PRED_ID" launched_at=2026-08-05T00:00:00Z tool_use_id=toolu_01RAFIX \
  plan=none >> "$RA_REPO_U/.bionic/tmp/roster-$RA_PRED.state"
mkdir -p "$CLAUDE_CONFIG_DIR/projects/$(printf '%s' "$RA_REPO_U" | sed 's/[^a-zA-Z0-9]/-/g')/$RA_PRED/subagents"
( cd "$RA_REPO_U" && env CLAUDE_CODE_SESSION_ID="$SID_B" bash "$SPO" adopt ) >/dev/null 2>&1
RA_ADOPT_U=$(grep "agent_id=$RA_PRED_ID" "$RA_REPO_U/.bionic/tmp/roster-$SID_B.state" 2>/dev/null | tail -1)
expect_eq "an unbound dispatcher writes the literal none" "none" "$(ra_field "$RA_DISPATCH_U" plan)"
expect_eq "…and so does an unbound adopter, the same word from the other writer" \
  "none" "$(ra_field "$RA_ADOPT_U" plan)"

# THE DISCRIMINATOR — drop the field from ONE writer and the agreement must break. The adopt
# writer is the one doctored, because it is the one the field was added to last and therefore
# the one a later reader is most likely to "simplify" back out. A copy; the shipped hook is
# never touched.
RA_MUT="$SANDBOX/ra-mutant"
mkdir -p "$RA_MUT/hooks" "$RA_MUT/scripts/lib"
cp "$LIB_DIR_SRC"/*.sh "$RA_MUT/scripts/lib/" 2>/dev/null
cp "$BIONIC_HOOKS_DIR"/*.sh "$RA_MUT/hooks/" 2>/dev/null; cp -R "$BIONIC_HOOKS_DIR/poker" "$RA_MUT/hooks/" 2>/dev/null
# The field is now an ARGUMENT to `roster_row` rather than a slot in a format string
# (S14, AC-25), so the doctoring deletes the line that passes it. What the mutant writes
# is `plan=` empty rather than no `plan=` at all, and both are the same thing to the
# reader under test: `ra_field` returns "" either way, and the row is still written.
anchor file hooks/poker/roster.sh '"plan=$(clean "$plan")"'
sed '/"plan=$(clean "$plan")"/d' \
  "$BIONIC_HOOKS_DIR/poker/roster.sh" > "$RA_MUT/hooks/poker/roster.sh"
RA_REPO_M=$(new_repo "ra-mutant-repo")
RA_PLAN_M="$RA_REPO_M/.bionic/docs/plans/epic-99/ra-run.md"
write_plan "$RA_PLAN_M" "current: 4"
roster_row_fixture status=identified session="$RA_PRED" name=ra-writer \
  agent_id="$RA_PRED_ID" launched_at=2026-08-05T00:00:00Z tool_use_id=toolu_01RAFIX \
  plan="$RA_PLAN_M" >> "$RA_REPO_M/.bionic/tmp/roster-$RA_PRED.state"
mkdir -p "$CLAUDE_CONFIG_DIR/projects/$(printf '%s' "$RA_REPO_M" | sed 's/[^a-zA-Z0-9]/-/g')/$RA_PRED/subagents"
s4_bind "$RA_REPO_M" "$SID_B" "$RA_PLAN_M"
( cd "$RA_REPO_M" && env CLAUDE_CODE_SESSION_ID="$SID_B" bash "$RA_MUT/hooks/session-poker.sh" adopt ) >/dev/null 2>&1
RA_ADOPT_M=$(grep "agent_id=$RA_PRED_ID" "$RA_REPO_M/.bionic/tmp/roster-$SID_B.state" 2>/dev/null | tail -1)
expect_eq "…and a doctored adopt writer leaves the row unattributed (§RA discriminates)" \
  "" "$(ra_field "$RA_ADOPT_M" plan)"
# NOT DISCRIMINATED BY WRITING NOTHING: the mutant still wrote a row, it just left the field off.
expect_contains "…while still writing the row, so the difference is the FIELD" \
  "$RA_PRED_ID" "$RA_ADOPT_M"

# --- §RA.2 — ONE WRITER OF roster-state/v1, PINNED TO A CAPTURED REAL ROW ----------
#
# (wave-01 verification-cannot-lie, S14; spec AC-25; design ledger D3.)
#
# WHAT THIS ROW USED TO SAY, AND WHY IT CHANGED. Until S14 the schema had TWO producers
# sharing no builder — `hooks/dispatch-preflight.sh`'s `ROW=` and
# `hooks/session-poker.sh`'s `adopt_write_row` — so the obligation here was a KEY-SET
# COMPARISON scraped out of the two source files: same keys in the same order, plus two
# adopt-only names listed by hand (Step-6 review D-8). That comparison could only ever
# notice the two writers disagreeing WITH EACH OTHER. Both drifting together, away from
# what the fleet's readers parse, was invisible to it — and "wrong but agreeing" is
# exactly the fog D3 ruled unacceptable. `roster_row` (payload/scripts/lib/roster.sh) is
# now the one writer, so the two CANNOT disagree any more, and the obligation becomes the
# one thing the old shape could not check: that the one writer still emits the row the
# fleet actually has on disk.
#
# THE PIN IS AGAINST A CAPTURE, NOT AN EXPECTATION. tests/fixtures/roster-row.captured
# holds two rows written by the two production call sites BEFORE either of them called
# `roster_row`; its header records which line came from which writer and from where.
# Comparing the one writer against a string this repo also wrote is a self-comparison —
# both halves move together and the pin survives any drift. A row the function did not
# write is the only version of this claim that can fail.
#
# THE ARGUMENTS ARE THE CAPTURE'S OWN FIELDS, HANDED OVER BACKWARDS. The test splits the
# captured row on `|`, gives `roster_row` the resulting `key=value` bag in REVERSE order,
# and requires the original line back. Field ORDER, field PRESENCE and the separators are
# therefore all the function's to supply; none of them can be echoed out of the input.
# The adopt row's two extra fields (`teammate_id=`, `adopted_from=`) are pinned in the one
# place they belong — a real row — instead of being listed by name in a test that would
# have to be edited to admit a third.
RA2_ROSTER_LIB="$BIONIC_HOOKS_DIR/../payload/scripts/lib/roster.sh"
[ -r "$RA2_ROSTER_LIB" ] || RA2_ROSTER_LIB="$BIONIC_HOOKS_DIR/../scripts/lib/roster.sh"
RA2_CAPTURE="$REPO_ROOT/tests/fixtures/roster-row.captured"

ra2_captured() {  # <status> -> the one captured row carrying that status
  LC_ALL=C grep "^${ROSTER_ROW_SCHEMA}|status=$1|" "$RA2_CAPTURE" 2>/dev/null | head -1
}

# The rebuild. `$( … )` is a subshell, so sourcing the library here cannot leak
# `roster_row` into the rest of this suite — every call pays for its own load, which is
# also what makes the mutant-library arm below a real substitution rather than a
# redefinition racing the first source.
ra2_rebuild() {  # <row> [library path] -> roster_row's output for that row's own fields
  local row="$1" lib="${2:-$RA2_ROSTER_LIB}" f
  local args=()
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    args=("$f" ${args[@]+"${args[@]}"})   # prepend: the bag reaches roster_row REVERSED
  done <<RA2_FIELDS
$(printf '%s' "$row" | tr '|' '\n' | tail -n +2)
RA2_FIELDS
  [ "${#args[@]}" -gt 0 ] || return 1
  ( . "$lib" >/dev/null 2>&1 && roster_row "${args[@]}" )
}

RA2_CAP_I="$(ra2_captured intended)"
RA2_CAP_A="$(ra2_captured identified)"
# NON-VACUITY FIRST: a capture that failed to load would make every equality below compare
# two empty strings and pass. Each row is checked for the field that identifies its writer.
expect_contains "the capture holds the launch-time row (dispatch-preflight's)" \
  "|status=intended|" "$RA2_CAP_I"
expect_contains "the capture holds the adopt-time row (session-poker's), with its extras" \
  "|adopted_from=" "$RA2_CAP_A"

expect_eq "roster_row reproduces the captured launch-time row byte for byte" \
  "$RA2_CAP_I" "$(ra2_rebuild "$RA2_CAP_I")"
expect_eq "roster_row reproduces the captured adopt-time row byte for byte" \
  "$RA2_CAP_A" "$(ra2_rebuild "$RA2_CAP_A")"

# REQ-7 AC-7.3 (epic-23 wave-16, 1.8.3) — THE NEW FIELD IS TRAILING AND OPTIONAL, and the
# capture is the proof. `re_executes=` is the runner-agnostic half of the instrument
# declaration (REQ-1): the dispatch wall lifts it off a brief's `Re-executes:` span and
# writes it here beside `suites_allowed=`. A schema field that changed the row's existing
# bytes would silently invalidate every reader built against what is on disk, so the claim
# has two halves and both are driven through the one writer.
#
# HALF ONE — ABSENT MEANS ABSENT. The captured rows predate the field; they must still come
# back byte for byte, which the two equalities above already require. The non-vacuity here is
# that the capture really does lack the key, so those equalities are saying something.
expect_absent "the captured launch-time row predates re_executes= (so the pin above is load-bearing)" \
  "re_executes=" "$RA2_CAP_I"
expect_absent "…and so does the captured adopt-time row" "re_executes=" "$RA2_CAP_A"

# HALF TWO — PASSED MEANS PRESENT, IN ITS PLACE. The same capture handed the same reversed
# bag PLUS one `re_executes=` pair comes back as the capture with exactly that field spliced
# in beside the other contract fields — after `waiver=`/the instrument group and before
# `tool_use_id=`. The expected string is DERIVED from the capture rather than transcribed, so
# it cannot drift away from the row on disk.
RA2_RUN='`npx jest --testPathPatterns x`'
ra2_rebuild_plus() {  # <row> <extra key=value> -> roster_row's output for that row plus the field
  local row="$1" extra="$2" f
  local args=("$extra")
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    args=("$f" ${args[@]+"${args[@]}"})
  done <<RA2_PLUS
$(printf '%s' "$row" | tr '|' '\n' | tail -n +2)
RA2_PLUS
  ( . "$RA2_ROSTER_LIB" >/dev/null 2>&1 && roster_row "${args[@]}" )
}
RA2_EXPECT_RUN="${RA2_CAP_I/|tool_use_id=/|re_executes=${RA2_RUN}|tool_use_id=}"
expect_eq "the expected string really differs from the capture (the splice is load-bearing)" "no" \
  "$([ "$RA2_EXPECT_RUN" = "$RA2_CAP_I" ] && echo yes || echo no)"
expect_eq "roster_row writes re_executes= as a trailing optional field, ahead of tool_use_id=" \
  "$RA2_EXPECT_RUN" "$(ra2_rebuild_plus "$RA2_CAP_I" "re_executes=$RA2_RUN")"

# THE MUTATION ARMS. Two, because the pin has two halves that can rot independently.
#
# ARM 1 — DOCTOR THE ROW. One field's value is changed in the capture handed to the
# rebuild; the output must then differ from the untouched capture. This is what proves the
# equality above is load-bearing rather than comparing a value to itself.
RA2_DOCTORED="$(printf '%s' "$RA2_CAP_I" | sed 's/|subagent_type=[^|]*|/|subagent_type=DOCTORED|/')"
expect_eq "the row-doctoring arm really changed one field" "yes" \
  "$([ "$RA2_DOCTORED" != "$RA2_CAP_I" ] && echo yes || echo no)"
expect_eq "…and the pin goes red on it (the doctored field does not reproduce the capture)" "no" \
  "$([ "$(ra2_rebuild "$RA2_DOCTORED")" = "$RA2_CAP_I" ] && echo yes || echo no)"
expect_contains "…and what came back carries the doctored value, so the writer was really driven" \
  "subagent_type=DOCTORED" "$(ra2_rebuild "$RA2_DOCTORED")"

# ARM 2 — DOCTOR THE WRITER. A copy of the library drops one field from the row it emits.
# This is the drift the pin exists for: the one writer moving away from the shape on disk.
RA2_MUT="$SANDBOX/ra2-mutant"
mkdir -p "$RA2_MUT"
anchor file payload/scripts/lib/roster.sh '|absent=$absent'
sed 's/|absent=\$absent//' "$RA2_ROSTER_LIB" > "$RA2_MUT/roster.sh"
expect_eq "the writer-doctoring arm really removed absent= from the emitted row" "yes" \
  "$([ "$(LC_ALL=C grep -c 'absent=\$absent' "$RA2_MUT/roster.sh" | tr -d ' ')" = "0" ] && echo yes || echo no)"
expect_eq "…and the pin goes red on the mutated writer" "no" \
  "$([ "$(ra2_rebuild "$RA2_CAP_I" "$RA2_MUT/roster.sh")" = "$RA2_CAP_I" ] && echo yes || echo no)"

# BOTH CALL SITES REALLY ROUTE THROUGH IT. The pin above proves the FUNCTION is right; these
# two prove the hooks are its callers, which is the other half of "one writer". The absence
# assertion is paired with the positive one on purpose: a hook that deleted its row
# entirely would satisfy the absence alone.
# THE PATTERN MUST NOT CATCH READERS. Both hooks still SELECT rows by prefix
# (`hooks/dispatch-preflight.sh`'s prune, `hooks/session-poker.sh`'s open-row grep) and a
# prefix test names `status=` without ever naming `session=`. A row being BUILT always
# carries the session it belongs to, so that is what separates the two.
ra2_code_hits() {  # <file> <extended regex> -> matching lines, whole-line comments removed
  LC_ALL=C grep -nE -- "$2" "$1" 2>/dev/null | LC_ALL=C grep -v ':[[:space:]]*#' | wc -l | tr -d ' '
}
RA2_BUILT_ROW='roster-state/[^|]*\|status=[a-z]+\|session='
# A CALL, NOT A MENTION (wave-28 T80). Since T70 the hook's "the launch row did not build"
# refusal names the function in its prose (`Reason:  roster_row (payload/…) refused …`), and a
# bare `roster_row ` counted that sentence as a second call site. A call is the name followed
# by an argument; the prose has the name followed by `(`.
RA2_CALL='roster_row[[:space:]]+[^([:space:]]'
RA2_DP="$BIONIC_HOOKS_DIR/dispatch-preflight.sh"
RA2_PK="$BIONIC_HOOKS_DIR/session-poker.sh"
expect_eq "dispatch-preflight builds its row by calling roster_row, and holds no row literal" \
  "1 0" "$(ra2_code_hits "$RA2_DP" "$RA2_CALL") $(ra2_code_hits "$RA2_DP" "$RA2_BUILT_ROW")"
expect_eq "…and the refusal that names roster_row in prose is a mention, not a call" \
  "1 0" "$(ra2_code_hits "$RA2_DP" 'Reason:  roster_row \(') $(ra2_code_hits "$RA2_DP" "Reason:  $RA2_CALL")"
# THE POKER CALLS THE BUILDER TWICE, AND ONE BUILDER IS STILL ONE SHAPE (re-authored at
# epic-23 wave-16, REQ-1 AC-1.1's adopt half). `adopt_write_row` passes the new trailing
# `re_executes=` field to `roster_row` and, for as long as the library's key table does not
# carry it, falls back to a call without it and appends the field itself — two call sites of
# ONE builder. What this row exists to hold is that no hook hand-writes a row: that is the
# second number, and it stays 0. A call count of exactly one was never the property; a
# LITERAL is, so the reading is "at least one call, and no literal".
RA2_PK_CALLS="$(ra2_code_hits "$RA2_PK" "$RA2_CALL")"
expect_eq "session-poker's adopt holds no row literal — the shape is the library's" \
  "0" "$(ra2_code_hits "$RA2_PK" "$RA2_BUILT_ROW")"
if [ "${RA2_PK_CALLS:-0}" -ge 1 ] 2>/dev/null; then
  ok "…and it builds the row by calling roster_row ($RA2_PK_CALLS call site(s), one builder)"
else
  no "…and it builds the row by calling roster_row" "no call to roster_row in $RA2_PK"
fi


# ============================================================
section "LR — THE LIVE-RUN SET: live_runs is always a subset of open_runs"
# ============================================================
#
# THE OWNERSHIP-TABLE ROW (spec §Design §3): "run is live · owning module `live_runs`
# (run.sh) · rendering surfaces: engage (bind), session-start (list + quiet count) ·
# agreement test: cross-gate new row: live ⊆ open; mutate `run_open`, both move; anti-vacuity
# arm". AC-5 words the obligation directly.
#
# WHY THE RELATION AND NOT THE SET. `tests/run-predicate.test.sh` owns what `live_runs`
# answers over 0/1/2-member fixtures; it cannot see the thing this file exists for. Two
# surfaces decide from the LIVE set (engage binds when exactly one run is live;
# session-start lists the live ones and counts the rest as quiet) while every gate in the
# fleet still rules on the OPEN set — so a live run that was not open would be a binding
# `session_run` then refuses, and `run_open` is the one predicate that can put it there.
# §OR above holds `active_run` to the same set from the other side.
#
# THE SUBSET CLAIM IS ONLY WORTH ASSERTING WHERE THE TWO SETS DIFFER. A fixture where every
# open run is also live makes `live ⊆ open` true by equality, which is the vacuous reading of
# it — so this world carries all three shapes at once: a FRESH open plan (live), a BACKDATED
# open plan (open, outside the `live-window:`, not live) and a DELIVERED plan (neither).

LR_LIB_SRC="$RUN_LIB"

# The status rides back inside the string for the reason §OR's `or_ask` gives: `$( … )` is a
# subshell and a status assigned inside it dies at the closing paren.
lr_ask() {  # <root> <function> -> sets LR_OUT and LR_ST
  local root="$1"; shift
  local raw
  raw=$( . "$LR_LIB_SRC" >/dev/null 2>&1; "$@" "$root" 2>/dev/null; printf '\037%s' "$?" )
  LR_ST="${raw##*$'\037'}"
  LR_OUT="${raw%$'\037'*}"
  LR_OUT="${LR_OUT%$'\n'}"
  printf '%s' "$LR_OUT"
}

# THE RELATION ITSELF, COMPUTED — never eyeballed from two printed sets. Returns how many
# lines of <live> are absent from <open>; zero IS the subset claim, and any other number is
# the counterexample named.
lr_missing() {  # <live> <open> -> count of live lines that are not open lines
  local l n=0
  while IFS= read -r l; do
    [ -n "$l" ] || continue
    grep -qxF -- "$l" <<<"$2" || n=$((n + 1))
  done <<<"$1"
  printf '%s' "$n"
}

# A plan older than the default 7-day `live-window:`. `s_backdate`'s hour is what makes one
# plan lose an ORDERING; days are what put a plan outside the WINDOW, and those are different
# fixture facts even though both are a `touch`.
lr_backdate_days() {  # <file> <days>
  touch -t "$(date -v-"$2"d +%Y%m%d%H%M.%S 2>/dev/null \
              || date -d "-$2 days" +%Y%m%d%H%M.%S)" "$1"
}

LR_R=$(new_repo "lr-live-subset")
LR_FRESH="$LR_R/.bionic/docs/plans/epic-99/lr-fresh.md"
LR_STALE="$LR_R/.bionic/docs/plans/epic-99/lr-backdated.md"
LR_DONE="$LR_R/.bionic/docs/plans/epic-99/lr-delivered.md"
write_plan "$LR_FRESH" "current: 4"
write_plan "$LR_STALE" "current: 6"
s4_close "$LR_DONE"
lr_backdate_days "$LR_STALE" 30

lr_ask "$LR_R" open_runs >/dev/null; LR_OPEN="$LR_OUT"; LR_OPEN_ST="$LR_ST"
lr_ask "$LR_R" live_runs >/dev/null; LR_LIVE="$LR_OUT"; LR_LIVE_ST="$LR_ST"

# --- LR.1 the fixture really carries all three shapes (non-vacuity) -------------
expect_eq "open_runs answers here" "0" "$LR_OPEN_ST"
expect_eq "live_runs answers here" "0" "$LR_LIVE_ST"
expect_eq "the open set holds BOTH open plans, fresh and backdated" "2" \
  "$(printf '%s\n' "$LR_OPEN" | grep -c '\.md$')"
expect_eq "…while the live set holds exactly one: the two sets are NOT equal here" "1" \
  "$(printf '%s\n' "$LR_LIVE" | grep -c '\.md$')"
expect_contains "the fresh plan is live" "lr-fresh.md" "$LR_LIVE"
expect_absent "…and the backdated plan is not, though it IS open" "lr-backdated.md" "$LR_LIVE"
expect_contains "…which is what makes the subset claim below a real one" \
  "lr-backdated.md" "$LR_OPEN"

# --- LR.2 THE RELATION: live ⊆ open, and the delivered plan is in neither -------
expect_eq "every live run is an open run (AC-5)" "0" "$(lr_missing "$LR_LIVE" "$LR_OPEN")"
expect_absent "the delivered plan is not open" "lr-delivered.md" "$LR_OPEN"
expect_absent "…and not live either" "lr-delivered.md" "$LR_LIVE"

# --- LR.3 THE SHARED PREDICATE: mutate run_open and BOTH readers move ----------
#
# `run_open` is the one predicate `open_runs` walks and `live_runs` inherits by calling it.
# Force it open and the DELIVERED plan — whose mtime is fresh, so the window admits it —
# joins the open set AND the live set in one step. A mutation that moved only one of them
# would mean `live_runs` had a second opinion about openness, which is the defect this row
# exists to catch. The shipped library is never touched: a copy is mutated in the sandbox.
LR_MUT_OPEN="$SANDBOX/lr-mutant-run-open.sh"
anchor insert payload/scripts/lib/run.sh 'run_open() {'
awk '
  /^run_open\(\) \{/ && !d { print; print "  [ -f \"$1\" ] && return 0"; d = 1; next }
  { print }
' "$RUN_LIB" > "$LR_MUT_OPEN"

LR_LIB_SRC="$LR_MUT_OPEN"
lr_ask "$LR_R" open_runs >/dev/null; LR_OPEN_M="$LR_OUT"
lr_ask "$LR_R" live_runs >/dev/null; LR_LIVE_M="$LR_OUT"
LR_LIB_SRC="$RUN_LIB"

expect_eq "mutated run_open: the open set gains the delivered plan" "3" \
  "$(printf '%s\n' "$LR_OPEN_M" | grep -c '\.md$')"
expect_eq "…and the LIVE set gains it too, in the same step" "2" \
  "$(printf '%s\n' "$LR_LIVE_M" | grep -c '\.md$')"
expect_contains "…by name, on the open side" "lr-delivered.md" "$LR_OPEN_M"
expect_contains "…and by name on the live side" "lr-delivered.md" "$LR_LIVE_M"
expect_eq "…and the subset relation still holds under the mutation" "0" \
  "$(lr_missing "$LR_LIVE_M" "$LR_OPEN_M")"
# The backdated plan is STILL not live under the mutation — the window is a second,
# independent rule, and forcing openness did not quietly widen it.
expect_absent "…while the backdated plan is still not live: the window is its own rule" \
  "lr-backdated.md" "$LR_LIVE_M"

# --- LR.4 THE ANTI-VACUITY ARM: prove the subset assertion can go RED ----------
#
# LR.2 asserts a count of zero. A count of zero is also what a broken comparison, an empty
# live set or a helper that never ran would produce, so the assertion is worth nothing until
# it has been SEEN to fail. Here `live_runs` is doctored to emit one path `open_runs` does
# not list — the exact defect the row is written against — and the same helper, over the same
# fixture, must report the counterexample.
LR_MUT_SUB="$SANDBOX/lr-mutant-live-extra.sh"
anchor insert payload/scripts/lib/run.sh 'live_runs() {'
awk '
  /^live_runs\(\) \{/ && !d { print; print "  printf '"'"'%s\\n'"'"' \"/nonexistent/ghost-run.md\""; d = 1; next }
  { print }
' "$RUN_LIB" > "$LR_MUT_SUB"

LR_LIB_SRC="$LR_MUT_SUB"
lr_ask "$LR_R" live_runs >/dev/null; LR_LIVE_G="$LR_OUT"
LR_LIB_SRC="$RUN_LIB"
expect_contains "the doctored live_runs really did emit the ghost" \
  "/nonexistent/ghost-run.md" "$LR_LIVE_G"
expect_eq "…and LR.2's own check reports it as NOT a member of the open set (the arm goes red)" \
  "1" "$(lr_missing "$LR_LIVE_G" "$LR_OPEN")"
# NOT DISCRIMINATED BY EMPTINESS: the doctored reader still returned the real live run too,
# so what the check caught is the EXTRA member, not a vanished set.
expect_contains "…while still returning the real live run, so the difference is the MEMBER" \
  "lr-fresh.md" "$LR_LIVE_G"

lr_ask "$LR_R" live_runs >/dev/null
expect_eq "restored: the shipped library answers as it did before the mutations" \
  "$LR_LIVE" "$LR_OUT"

# --- LR.5 EVERY GATE KEEPS THE STRICT OPEN RULE: NO GATE CONSULTS live_runs (AC-4) -------
#
# THE HALF OF AC-4 THE READBACK FLAGGED AS UNPROVEN. LR.1-LR.4 prove the SUBSET relation
# between the two readers; none of them says, in words, that a gate never reads the live
# reader at all. `bind` succeeding on a quiet-but-open plan (session-poker's own suite) is
# only "every gate keeps the strict open rule" if the gates really do stay off `live_runs` —
# so this row greps the two callers this wave gave `live_runs` and the eight gates a
# dispatch/stop/evidence/landing decision runs through, and pins the split directly.
LR_LIVE_CALLERS="engage.sh session-start.sh"
LR_GATES="bash-walls.sh canonical-sdlc-governing-skill.sh dispatch-preflight.sh stop-guard.sh stop.sh"

for f in $LR_LIVE_CALLERS; do
  expect_eq "…$f (a live_runs caller) really does reference it (non-vacuity)" "1" \
    "$( [ "$(/usr/bin/grep -c 'live_runs' "$BIONIC_HOOKS_DIR/$f")" -ge 1 ] && echo 1 || echo 0 )"
done

for f in $LR_GATES; do
  expect_eq "…$f carries zero references to live_runs" "0" \
    "$(/usr/bin/grep -c 'live_runs' "$BIONIC_HOOKS_DIR/$f")"
done

# THE ANTI-VACUITY ARM. A doctored copy of one gate (stop-guard.sh) with a live_runs call
# inserted must fail the pin above — proving the grep is a real check on this gate's
# content, not a path that always reads zero regardless of what the file says.
LR_GATE_MUT_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/lr-gate-live-runs-mut.XXXXXX")"
LR_GATE_MUT="$LR_GATE_MUT_ROOT/stop-guard.sh"
{ printf '# doctored: %s\n' 'RUNS=$(live_runs "$REPO_REAL" 2>/dev/null) || RUNS=""'
  cat "$BIONIC_HOOKS_DIR/stop-guard.sh"
} > "$LR_GATE_MUT"
expect_eq "gate-mut meta: the doctored live_runs call landed (the file is not the original)" "no" \
  "$(cmp -s "$BIONIC_HOOKS_DIR/stop-guard.sh" "$LR_GATE_MUT" && echo yes || echo no)"
expect_eq "…and the doctored gate now fails the very pin above (the arm goes red)" "1" \
  "$(/usr/bin/grep -c 'live_runs' "$LR_GATE_MUT")"
rm -rf "$LR_GATE_MUT_ROOT"

# ============================================================
section "LA — THE LIVE-AGENT SET: one parser, and who still reads it (T22)"
# ============================================================
#
# THE OWNERSHIP-TABLE ROW (spec §Design §3): "live agent set · owning module `live_agents`
# (agents.sh) · rendering surfaces: dispatch-preflight budget, stop-guard, stop-check,
# standdown, poker tick · agreement test: cross-gate new row: one parser; mutate it, every
# reader moves". AC-10 words the stop half of it directly.
#
# WHY THIS ROW EXISTS. Liveness used to be answered three ways — a `landing-swept` marker for
# the budget, a directory walk for the observation, a roster read for the gate — and the
# whole wave is the claim that there is now ONE answer, the harness's own recorded
# `ListAgents`, parsed in ONE place. That claim is not visible in any single suite:
# `tests/live-agents.test.sh` owns what the parser returns, and each hook's own suite owns
# what that hook does with it. What is only visible HERE is that the three hooks are reading
# the SAME parser — which is proved by breaking it once and watching all three answers move.
#
# WHO READS IT NOW (T22, A-orch-33). The stop path left this row: `hooks/stop-guard.sh` and
# `hooks/stop-check.sh` resolve a typed target on THIS SESSION'S ROSTER, because the live set
# is a reading only the model can ask for and a stop that waited for one was a chore in front
# of a judgement (ADR-024, P-A). What survives is the reader that was never a precondition —
# the dispatch budget — and `hooks/session-poker.sh`'s tick, which owns AC-4.3's tell.
#
# SO THIS SECTION NOW PROVES TWO THINGS AT ONCE, and the mutation battery below proves both
# with the same doctored parser: the budget MOVES when the parser breaks (it reads it), and
# the stop path DOES NOT (it reads the roster). A shared parser with one reader would pass
# the first half; a stop path that had quietly kept a private copy would fail the second.
#
# THE SURFACES, never the library:
#   · dispatch-preflight — its budget refusal, which counts the roster's open rows against
#     the live set (`open=` in the BLOCKED line)
#   · stop-guard          — its resolution of a typed target on the Stop path (roster-only)
#   · stop-check          — the operator's listing, whose `Resolved:` line is the answer
#
# TWO NAMES, ONE ROSTER, FOR A REASON. The budget walks `status=intended` rows and
# resolution needs an `identified` row carrying an agent id, and the row-dedupe keeps the
# LAST row for a name — so one name cannot be both. `la-budget` is the open seat the ceiling
# counts; `la-target` is the identified agent the other two resolve. Both are named in the
# one recorded answer, which is the point: one parser, two questions.

LA_REPO=$(new_repo "la-one-parser")
LA_PLAN="$LA_REPO/.bionic/docs/plans/epic-99/la-run.md"
s4_plan "$LA_PLAN" 4 1
s4_bind "$LA_REPO" "$SID_A" "$LA_PLAN"
s4_attest "$LA_REPO" "$SID_A"

LA_SLUG=$(printf '%s' "$LA_REPO" | sed 's/[^a-zA-Z0-9]/-/g')
LA_PROJ="$CLAUDE_CONFIG_DIR/projects/$LA_SLUG"
mkdir -p "$LA_PROJ/$SID_A/subagents"
LA_TR="$LA_PROJ/$SID_A.jsonl"
LA_TID="alat-9999999999999999"

# THE ONE RECORDED ANSWER both questions are asked against — the harness's `ListAgents`
# result, in the shape `tests/live-agents.test.sh` establishes and the S6 `cg_live` helper
# above builds.
cg_live "$LA_TR" "la-budget" "la-target"

# the open seat (budget) and the identified agent (resolution)
cg_roster_row "$LA_REPO" "$SID_A" "la-budget" "alab-8888888888888888" "" "intended"
printf '{"name":"la-target","agentType":"implementor","description":"fixture","model":"opus"}' \
  > "$LA_PROJ/$SID_A/subagents/agent-$LA_TID.meta.json"
printf '{"type":"assistant","message":{"content":[{"type":"text","text":"working"}]}}\n' \
  > "$LA_PROJ/$SID_A/subagents/agent-$LA_TID.jsonl"
roster_identify "$LA_REPO" "$SID_A" "la-target" "$LA_TID"

# ---- the three questions, each asked of the REAL hook, out of a NAMED TREE ----
#
# The tree is a parameter because that is how the mutation is taken: every driver loads its
# hook from `$LA_TREE/hooks`, whose `../scripts/lib` is the library those hooks resolve
# first, so pointing `LA_TREE` at a doctored copy swaps the PARSER under all three at once
# without the shipped files being touched.
# A FRESH DISPATCH NAME PER DRIVE (wave-14 REQ-8, T6). Some of the drives below are
# ALLOWED — that is half of what the mutation battery measures — and an allowed dispatch
# JOURNALS its name on this roster. With the gate's arms pooled, the next drive under the
# same name is refused for the budget AND for the name being in flight, which is a true
# answer to a question this section is not asking: the channel it compares would then carry
# two faults and no per-fault detail. The counter is a file because every call site spends
# this function inside `$( )`, where a shell variable's increment does not survive.
LA_NAME_SEQ="$SANDBOX/.la-name-seq"
printf '0' > "$LA_NAME_SEQ"
la_next_name() {
  local n; n=$(( $(cat "$LA_NAME_SEQ" 2>/dev/null || echo 0) + 1 ))
  printf '%s' "$n" > "$LA_NAME_SEQ"
  printf 'la-w%s' "$n"
}
la_budget() {  # -> the dispatch wall's whole channel
  mk_agent_payload "$SID_A" "$LA_REPO" \
    | jq -c --arg t "$LA_TR" --arg n "$(la_next_name)" \
        '.transcript_path = $t | .tool_input.name = $n' \
    | env CLAUDE_CODE_SESSION_ID="$SID_A" bash "$LA_TREE/hooks/dispatch-preflight.sh" 2>&1
  return 0
}
la_guard() {  # <typed> -> the stop guard's whole channel
  mk_stop_payload "$SID_A" "$LA_TR" "$LA_REPO" "$1" \
    | env CLAUDE_CODE_SESSION_ID="$SID_A" bash "$LA_TREE/hooks/stop-guard.sh" 2>&1
  return 0
}
la_check() {  # <typed> -> the observation's whole channel
  ( cd "$LA_REPO" && env CLAUDE_CODE_SESSION_ID="$SID_A" \
      bash "$LA_TREE/hooks/stop-check.sh" "$1" 2>&1 )
  return 0
}

LA_TREE="$BIONIC_HOOKS_DIR/.."
[ -d "$LA_TREE/scripts/lib" ] || LA_TREE="$BIONIC_HOOKS_DIR/../payload"
expect_eq "the shipped tree this section drives really holds the parser (not vacuous)" "yes" \
  "$([ -r "$LA_TREE/scripts/lib/agents.sh" ] && echo yes || echo no)"

LA_B0=$(la_budget)
LA_G0=$(la_guard la-target)
LA_C0=$(la_check la-target)

# --- LA.1 all three read the live set, and each SAYS what it read --------------
expect_contains "the dispatch wall counts the live open seat against the ceiling" \
  "open=1" "$LA_B0"
expect_contains "…and refuses on it, which is the answer the count produces" \
  "bionic: " "$LA_B0"
expect_absent "…rather than refusing because it could not read the answer at all" \
  "call ListAgents" "$LA_B0"
expect_contains "the observation resolves a live target to its agent id" "$LA_TID" "$LA_C0"
expect_absent "…and does not report it as absent from the live set" "not live" "$LA_C0"
# THE GUARD SPEAKS ITS RESOLUTION AS A VERDICT, not as an id: a target it finds in the live
# set is one it has standing to guard, so it BLOCKS the stop and names the observation to
# take; a target it does not find is not this gate's business and PASSES THROUGH. Those two
# words ARE the resolution, and they are what moves when the parser does.
expect_contains "the stop guard has standing over the same target: it takes its look and allows the stop, its verdict recorded (wave-31 T32)" \
  "STOP ALLOWED — 'la-target' (" "$LA_G0"
expect_contains "…naming the working log its look read" \
  "working log:" "$LA_G0"
expect_absent "…rather than passing it through as no agent of this session" \
  "PASSTHROUGH" "$LA_G0"
# THE LIVE READING IS A SENTENCE IN THE REFUSAL, and it is the half that moves. Standing is
# broader than liveness — a roster row or an agent-address shape also earns it — so BLOCKED
# alone would still be printed by a guard that had stopped consulting the live set entirely.
# What only a live target gets is a refusal that does NOT say it is absent from the answer.
expect_absent "…and it does not call the target absent from the recorded answer" \
  "is not live" "$LA_G0"

# --- LA.2 a name the recorded answer does NOT carry is refused by both readers --
#
# The negative direction, on the SAME transcript: what separates `la-target` from `la-ghost`
# is one line of the harness's answer and nothing else, so a reader that resolved both would
# be resolving from something other than the live set.
LA_CG=$(la_check la-ghost)
LA_GG=$(la_guard la-ghost)
# RE-POINTED (T22): what separates `la-target` from `la-ghost` on the stop path is a ROSTER
# ROW, not a line of the harness's answer — both names are equally absent from this session's
# register, and `la-ghost` has no row.
expect_contains "a name the roster does not carry resolves no id for the observation" \
  "no agent id" "$LA_CG"
expect_absent "…and carries no agent id with it" "$LA_TID" "$LA_CG"
# D8 (T5): a bare name with no roster row and no agent-address or bash-task-id shape used to
# pass through (T22); it is refused now, naming the same fact one step earlier.
expect_absent "…and the stop guard refuses it, having no standing over it (D8, T5)" \
  "PASSTHROUGH" "$LA_GG"
expect_contains "…saying so in the register's own words" \
  "no roster row of this session" "$LA_GG"

# --- LA.3 THE DISCRIMINATOR: mutate the parser's awk, all three answers move ----
#
# The mutation removes ONE line of `_la_parse_teammates` — the `sub()` that drops the
# harness's `[ref]` suffix off the name. It is the smallest plausible regression in that awk
# and it leaves the parser working: the set still has two entries, they are just spelled
# `la-target [8895ce]`. So no reader can find its name, and none of them can blame an empty
# answer for it — which is exactly the failure a second, private parser would produce and a
# shared one cannot.
LA_MUT="$SANDBOX/la-mutant"
mkdir -p "$LA_MUT/hooks" "$LA_MUT/scripts/lib"
cp "$LIB_DIR_SRC"/*.sh "$LA_MUT/scripts/lib/" 2>/dev/null
cp "$BIONIC_HOOKS_DIR"/*.sh "$LA_MUT/hooks/" 2>/dev/null; cp -R "$BIONIC_HOOKS_DIR/poker" "$LA_MUT/hooks/" 2>/dev/null
anchor file payload/scripts/lib/agents.sh 'drop the harness ref suffix'
grep -v 'drop the harness ref suffix' "$LIB_DIR_SRC/agents.sh" > "$LA_MUT/scripts/lib/agents.sh"
# …AND THE MUTANT IS STILL A PARSER. If it returned nothing the three readers would move for
# a reason that proves nothing about sharing — every one of them refuses an unreadable answer
# already. The set is asked for directly, once, to pin that it is non-empty and merely WRONG.
LA_MUT_SET=$( . "$LA_MUT/scripts/lib/agents.sh" >/dev/null 2>&1; live_agents "$LA_TR" 2>/dev/null )
expect_contains "…and the doctored parser still returns a live set" "la-target [" "$LA_MUT_SET"
expect_absent "…which simply spells the name wrong" "la-target|" "$LA_MUT_SET"

LA_TREE="$LA_MUT"
LA_B1=$(la_budget)
LA_G1=$(la_guard la-target)
LA_C1=$(la_check la-target)
LA_TREE="$BIONIC_HOOKS_DIR/.."
[ -d "$LA_TREE/scripts/lib" ] || LA_TREE="$BIONIC_HOOKS_DIR/../payload"

expect_absent "mutated parser: the dispatch wall no longer counts the seat as open" \
  "open=1" "$LA_B1"
# THE OTHER HALF OF THE DISCRIMINATOR (T22). The budget moved, one line up, because it reads
# the parser. The stop path must NOT move, because it reads the roster — and the strongest
# statement of that is byte equality of the whole channel across the mutation.
expect_contains "mutated parser: the observation still resolves the target from the ROSTER" \
  "$LA_TID" "$LA_C1"
expect_absent "…and never reports it as absent from a set it no longer consults" \
  "not live" "$LA_C1"
# THE AGE IS A READING, NOT A RENDERING (epic-23 wave-15, REQ-2). Since the gate looks for
# itself its refusal carries how long ago the target last wrote, so two drives a second apart
# spell the same channel differently. The normalizer folds the reading and keeps everything
# this section is about — which arm spoke, about which target, on which channel.
la_norm_m() {
  printf '%s\n' "$1" | sed -e 's#/[^ ]*/hooks/#TREE/#g' -e 's/last write:.*$/last write: AGE/'
}
expect_eq "mutated parser: the stop guard's whole channel is unchanged — it reads no parser" \
  "$(la_norm_m "$LA_G0")" "$(la_norm_m "$LA_G1")"
expect_contains "…and that channel is a real verdict, not an empty string (not vacuous)" \
  "STOP ALLOWED" "$LA_G1"

# --- LA.4 restored: the shipped tree answers as it did before the mutation ------
# The observation prints an AGE, which moves by a second between two runs of the same
# fixture — so the compare is on the `Resolved:` line, which is the answer this section is
# about, rather than on a whole channel that carries a clock reading.
la_resolved() { printf '%s\n' "$1" | sed -n 's/^Resolved: *//p' | head -1; }
expect_eq "restored: the wall's answer is the one it gave before" "$LA_B0" "$(la_budget)"
expect_eq "…and the observation resolves what it resolved before" \
  "$(la_resolved "$LA_C0")" "$(la_resolved "$(la_check la-target)")"
expect_eq "…which is the agent id, not an empty line (the restore is not vacuous)" \
  "$LA_TID" "$(la_resolved "$LA_C0")"

# --- LA.5 ONE PARSE, TWO QUESTIONS: the status column (spec R2, AC-27; S16) ----
#
# S16 gives the budget a NARROWER question than the guard. The budget stops counting a row
# whose agent reads `idle` — a teammate that finished its turn and was never stopped is not
# a writer. The guard keeps resolving on PRESENCE, because an idle agent is exactly the one
# a stop is for. Both answers come off the SAME parse (`live_agents_status` and
# `live_agents_has` are two views of one `live_agents` call), and that is what this block
# proves: two one-line doctorings of that single parser, each moving exactly the consumer
# whose question it changes, on one fixture neither consumer can otherwise tell apart.
#
# LA.3 already moves all three readers by breaking the NAME. LA.5 is the other half — the
# STATUS is read from that same parse, by one of them.

rm -f "${LA_TR%.jsonl}.names"
cg_live "$LA_TR" "la-budget:idle" "la-target:idle"
expect_contains "LA.5 meta: the one answer now names both teammates idle" \
  "la-budget [8895ce]  ·  bionic:implementor  ·  idle" "$(cat "$LA_TR")"

LA_B5=$(la_budget)
LA_G5=$(la_guard la-target)
expect_absent "idle open seat: the dispatch wall stops counting it" "open=1" "$LA_B5"
expect_absent "…and prints no writers refusal at all" "writers:" "$LA_B5"
expect_contains "…while the SAME answer still gives the stop guard standing over its target" \
  "STOP ALLOWED" "$LA_G5"
expect_absent "…which it does not call absent from the recorded answer" "is not live" "$LA_G5"

# MUTATION A — the parser writes `running` into every row. The status the BUDGET reads is
# gone; the presence the GUARD reads is untouched. Exactly one consumer moves.
LA_MUT_S="$SANDBOX/la-mutant-status"
mkdir -p "$LA_MUT_S/hooks" "$LA_MUT_S/scripts/lib"
cp "$LIB_DIR_SRC"/*.sh "$LA_MUT_S/scripts/lib/" 2>/dev/null
cp "$BIONIC_HOOKS_DIR"/*.sh "$LA_MUT_S/hooks/" 2>/dev/null; cp -R "$BIONIC_HOOKS_DIR/poker" "$LA_MUT_S/hooks/" 2>/dev/null
anchor file payload/scripts/lib/agents.sh 'print name "|" type "|" status'
sed 's/print name "|" type "|" status/print name "|" type "|" "running"/' \
  "$LIB_DIR_SRC/agents.sh" > "$LA_MUT_S/scripts/lib/agents.sh"
expect_eq "mutation A applies (the parser's print line has not moved)" "no" \
  "$(cmp -s "$LIB_DIR_SRC/agents.sh" "$LA_MUT_S/scripts/lib/agents.sh" && echo yes || echo no)"
LA_MUTS_SET=$( . "$LA_MUT_S/scripts/lib/agents.sh" >/dev/null 2>&1; live_agents "$LA_TR" 2>/dev/null )
expect_contains "…and the mutant is still a parser: the set is intact, only the status lies" \
  "la-budget|bionic:implementor|running" "$LA_MUTS_SET"

LA_TREE="$LA_MUT_S"
LA_B5A=$(la_budget)
LA_G5A=$(la_guard la-target)
LA_TREE="$BIONIC_HOOKS_DIR/.."
[ -d "$LA_TREE/scripts/lib" ] || LA_TREE="$BIONIC_HOOKS_DIR/../payload"

expect_contains "mutation A: the wall counts the finished agent open again — the budget moved" \
  "open=1" "$LA_B5A"
expect_contains "…and refuses on it" "bionic: " "$LA_B5A"
# The guard's channel quotes the tree it was loaded from in its `Fix:` lines, so the
# compare normalises that one path away and is byte-exact on everything else — including
# the verdict, which is the thing under test.
# …and the same age fold LA.4 needs, for the same reason (epic-23 wave-15, REQ-2): the
# guard's channel carries a reading of how long ago the target wrote, which is a fact about
# the clock rather than about the arm that spoke.
la_norm() {
  printf '%s\n' "$1" | sed -e 's#/[^ ]*/hooks/#TREE/#g' -e 's/last write:.*$/last write: AGE/'
}
expect_eq "…while the guard's whole channel is otherwise unchanged — presence never moved" \
  "$(la_norm "$LA_G5")" "$(la_norm "$LA_G5A")"
expect_contains "…and the normaliser really did fold the age (not comparing raw text)" \
  "last write: AGE" "$(la_norm "$LA_G5")"
expect_contains "…and that channel is a real verdict, not an empty string (not vacuous)" \
  "STOP ALLOWED" "$LA_G5A"

# MUTATION B — the parser drops every row that is not `running`. This is the WRONG place to
# put S16's rule: filtering in the reader rather than in the budget. Now the GUARD moves and
# the budget does not, which is why the rule lives where it does.
LA_MUT_F="$SANDBOX/la-mutant-filter"
mkdir -p "$LA_MUT_F/hooks" "$LA_MUT_F/scripts/lib"
cp "$LIB_DIR_SRC"/*.sh "$LA_MUT_F/scripts/lib/" 2>/dev/null
cp "$BIONIC_HOOKS_DIR"/*.sh "$LA_MUT_F/hooks/" 2>/dev/null; cp -R "$BIONIC_HOOKS_DIR/poker" "$LA_MUT_F/hooks/" 2>/dev/null
anchor file payload/scripts/lib/agents.sh 'if (name != "") print name "|" type "|" status'
sed 's/if (name != "") print name "|" type "|" status/if (name != "" \&\& status == "running") print name "|" type "|" status/' \
  "$LIB_DIR_SRC/agents.sh" > "$LA_MUT_F/scripts/lib/agents.sh"
expect_eq "mutation B applies" "no" \
  "$(cmp -s "$LIB_DIR_SRC/agents.sh" "$LA_MUT_F/scripts/lib/agents.sh" && echo yes || echo no)"
LA_MUTF_SET=$( . "$LA_MUT_F/scripts/lib/agents.sh" >/dev/null 2>&1; live_agents "$LA_TR" 2>/dev/null )
expect_empty "…and it really does drop the idle rows from the set" "$LA_MUTF_SET"
# THE PAIRED POSITIVE FOR THAT ABSENCE (wave-01 S11, AC-14 / A-10a). This `expect_empty`
# was the call the framework did not define: for as long as the suite carried no
# `expect_empty`, it was a `command not found` on a discarded stderr, counted nothing, and
# an 818/818 green covered it. Now that it asserts, it is a NEGATIVE assertion over a
# mutant extractor — and an extractor that returns the empty string for EVERY transcript
# would satisfy it just as well as one that filters. The same mutant, over the same
# builder, against an answer whose teammates are RUNNING, has to come back non-empty.
LA_TR_RUN="$LA_PROJ/$SID_B.jsonl"
rm -f "${LA_TR_RUN%.jsonl}.names"
cg_live "$LA_TR_RUN" "la-budget:running" "la-target:running"
LA_MUTF_RUN=$( . "$LA_MUT_F/scripts/lib/agents.sh" >/dev/null 2>&1; live_agents "$LA_TR_RUN" 2>/dev/null )
expect_nonempty "…while the SAME mutant extractor over a RUNNING answer returns a set" \
  "$LA_MUTF_RUN"
expect_contains "…carrying the row it kept, so the emptiness above is a filter and not a blank" \
  "la-budget|bionic:implementor|running" "$LA_MUTF_RUN"

LA_TREE="$LA_MUT_F"
LA_G5B=$(la_guard la-target)
LA_B5B=$(la_budget)
LA_TREE="$BIONIC_HOOKS_DIR/.."
[ -d "$LA_TREE/scripts/lib" ] || LA_TREE="$BIONIC_HOOKS_DIR/../payload"

# RE-POINTED (T22). Filtering `idle` out inside the reader was the WRONG place for S16's
# rule, and the reason it was wrong is that it took the finished agent away from the gate
# whose whole job is stopping it. The gate no longer reads the parser at all, so the mutation
# cannot reach it — which is the same finding stated as an immunity rather than a loss.
expect_absent "mutation B: the guard does not lose the finished agent it exists to stop" \
  "names no teammate 'la-target'" "$LA_G5B"
expect_contains "…it still has standing and still judges on the evidence" "STOP ALLOWED" "$LA_G5B"
expect_absent "…a sentence the shipped parser never said of the same target" \
  "names no teammate" "$LA_G5"
expect_absent "mutation B: the wall's count is unchanged — it read idle as closed already" \
  "open=1" "$LA_B5B"

# RESTORED, on the idle fixture: neither mutation left anything behind.
expect_eq "restored: the wall answers the idle fixture as it did before both mutations" \
  "$LA_B5" "$(la_budget)"
# THE SAME FOLD AS LA.4's (epic-23 wave-15, REQ-2): the guard's channel now carries how long
# ago the target last wrote, and the claim here is that the mutations left nothing behind —
# not that two clocks a second apart read alike.
expect_eq "…and so does the guard" "$(la_norm_m "$LA_G5")" "$(la_norm_m "$(la_guard la-target)")"

# --- LA.6 ONE PREDICATE, TWO CONSUMERS: the budget and the tick count the same (S19) ---
#
# THE OWNERSHIP-TABLE ROW names `session-poker.sh tick` a rendering surface of the live
# agent set. Until S19 it was not one: the tick counted roster rows by sweeper verdict and
# never read the harness's answer, so the Patrol could print a FILL the dispatch wall was
# about to refuse — a finished-but-unstopped teammate is not open to the budget and WAS
# open to the tick. LA.5 proves the budget and the guard ask DIFFERENT questions off one
# parse. LA.6 is the other shape of the same claim: two consumers asking the SAME question
# must get the same answer, and they do because there is one predicate — `live_row_open`.
#
# THE OBSERVABLE IS A NUMBER EACH SIDE PRINTS ITSELF: `open=` in the wall's refusal and
# `open=` in the tick's decision line. Neither is computed by this suite.
#
# ONE ROSTER, ONE ANSWER, TWO ROWS: an idle teammate beside a running one. Every consumer
# below reads the same two files; only the tree they are loaded from ever changes.

# A SESSION ID OF ITS OWN, and that is not fixture hygiene — it is the contract. The tick
# finds its transcript by walking CLAUDE_CONFIG_DIR/projects/*/<session-id>.jsonl and takes
# the first match, so two fixtures sharing one id would hand it a NEIGHBOUR'S answer. The
# budget is handed its transcript in the hook payload and would not notice. This suite
# already plants `$SID_A.jsonl` under two other project directories, so on the shared id the
# two consumers would be reading two different files — and an agreement row measured that
# way proves nothing about either.
LA6_SID="7d31be55-2c48-4f90-b1a7-63e0c4a91d55"
LA6_REPO=$(new_repo "la-one-predicate")
arm_patrol "$LA6_REPO" "$LA6_SID"
LA6_PLAN="$LA6_REPO/.bionic/docs/plans/epic-99/la6-run.md"
s4_plan "$LA6_PLAN" 4 1
s4_bind "$LA6_REPO" "$LA6_SID" "$LA6_PLAN"
s4_attest "$LA6_REPO" "$LA6_SID"

LA6_SLUG=$(printf '%s' "$LA6_REPO" | sed 's/[^a-zA-Z0-9]/-/g')
LA6_PROJ="$CLAUDE_CONFIG_DIR/projects/$LA6_SLUG"
mkdir -p "$LA6_PROJ"
LA6_TR="$LA6_PROJ/$LA6_SID.jsonl"
cg_live "$LA6_TR" "la6-idle:idle" "la6-live:running"
# NOT SHARED WITH ANY OTHER FIXTURE: the id resolves to exactly this file.
expect_eq "LA.6 meta: this session's id names exactly one transcript on the whole machine" "1" \
  "$(ls "$CLAUDE_CONFIG_DIR"/projects/*/"$LA6_SID.jsonl" 2>/dev/null | wc -l | tr -d ' ')"

# THE ROWS CARRY A DELIVERABLE THAT DOES NOT EXIST, so the sweeper calls both contracts
# UNMET and the tick has two candidate-open rows to narrow. A row declaring nothing stats
# MET for want of anything to hold it to, and would make the tick's count zero for a reason
# that has nothing to do with the live set.
la6_row() {  # <name>
  roster_row_fixture status=intended session="$LA6_SID" name="$1" agent_id= \
    launched_at=2026-08-05T00:00:00Z deliverable="$LA6_REPO/never-written-$1.md" \
    duration="4 hours" tool_use_id="toolu_01LA6$1" \
    >> "$LA6_REPO/.bionic/tmp/roster-$LA6_SID.state"
}
roster_header \
  > "$LA6_REPO/.bionic/tmp/roster-$LA6_SID.state"
la6_row "la6-idle"
la6_row "la6-live"

la6_budget() {  # -> the dispatch wall's whole channel, out of $LA_TREE
  mk_agent_payload "$LA6_SID" "$LA6_REPO" \
    | jq -c --arg t "$LA6_TR" '.transcript_path = $t' \
    | env CLAUDE_CODE_SESSION_ID="$LA6_SID" bash "$LA_TREE/hooks/dispatch-preflight.sh" 2>&1
  return 0
}
la6_tick() {  # -> the Patrol tick's whole channel, out of $LA_TREE
  ( cd "$LA6_REPO" && env CLAUDE_CODE_SESSION_ID="$LA6_SID" \
      BIONIC_PROBE_FREE_MB=8192 BIONIC_PROBE_LOAD_1M=1.0 \
      bash "$LA_TREE/hooks/session-poker.sh" tick 2>&1 )
  return 0
}
la6_open_budget() { printf '%s\n' "$1" | sed -n 's/.*writers: budget=[0-9]* open=\([0-9]*\) .*/\1/p' | head -1; }
la6_open_tick()   { printf '%s\n' "$1" | sed -n 's/.*decision=[A-Z]*|total=[0-9]*|open=\([0-9]*\).*/\1/p' | head -1; }

LA6_B=$(la6_budget); LA6_T=$(la6_tick)
LA6_BN=$(la6_open_budget "$LA6_B"); LA6_TN=$(la6_open_tick "$LA6_T")

# NON-VACUITY FIRST: both consumers really did print a number, and it is the one the
# fixture predicts — two roster rows, one of them finished, so exactly one is open.
expect_eq "LA.6 the dispatch wall counts one open row on this roster" "1" "$LA6_BN"
expect_eq "LA.6 the Patrol tick counts one open row on the SAME roster" "1" "$LA6_TN"
expect_eq "…so the two consumers agree" "$LA6_BN" "$LA6_TN"
# And the tick really did consult the live set rather than land on 1 by luck: its own
# roster carries TWO unmet rows, which is what a tick that read no answer would print.
expect_contains "…while the tick's own roster carries two rows (the narrowing is real)" \
  "total=2" "$LA6_T"

# THE MUTATION: ONE LINE of the shared predicate, and BOTH consumers move together. That
# is the whole point of one owner — a rule spelled twice would move one of them.
LA6_MUT="$SANDBOX/la-mutant-predicate"
mkdir -p "$LA6_MUT/hooks" "$LA6_MUT/scripts/lib"
cp "$LIB_DIR_SRC"/*.sh "$LA6_MUT/scripts/lib/" 2>/dev/null
cp "$BIONIC_HOOKS_DIR"/*.sh "$LA6_MUT/hooks/" 2>/dev/null; cp -R "$BIONIC_HOOKS_DIR/poker" "$LA6_MUT/hooks/" 2>/dev/null
anchor file payload/scripts/lib/agents.sh '_LA_ROW_CLOSED_STATUS="idle"'
sed 's/_LA_ROW_CLOSED_STATUS="idle"/_LA_ROW_CLOSED_STATUS="no-such-status"/' \
  "$LIB_DIR_SRC/agents.sh" > "$LA6_MUT/scripts/lib/agents.sh"
# …and the mutant is still a predicate: it now calls the idle row OPEN rather than
# returning nothing at all.
LA6_MUT_RC=0
( . "$LA6_MUT/scripts/lib/agents.sh" >/dev/null 2>&1; live_row_open "$LA6_TR" "la6-idle" ) 2>/dev/null \
  || LA6_MUT_RC=$?
expect_eq "…and the doctored predicate now calls the idle row OPEN" "0" "$LA6_MUT_RC"

LA_TREE="$LA6_MUT"
LA6_BM=$(la6_budget); LA6_TM=$(la6_tick)
LA_TREE="$BIONIC_HOOKS_DIR/.."
[ -d "$LA_TREE/scripts/lib" ] || LA_TREE="$BIONIC_HOOKS_DIR/../payload"

expect_eq "mutated predicate: the dispatch wall now counts BOTH rows open" "2" \
  "$(la6_open_budget "$LA6_BM")"
expect_eq "…and the tick moves with it, off the same one line" "2" \
  "$(la6_open_tick "$LA6_TM")"
expect_eq "…so they still agree — one owner, moved once, moves both" \
  "$(la6_open_budget "$LA6_BM")" "$(la6_open_tick "$LA6_TM")"

# RESTORED: the shipped tree answers as it did before the mutation, on both surfaces.
expect_eq "restored: the wall counts one open row again" "1" "$(la6_open_budget "$(la6_budget)")"
expect_eq "…and so does the tick" "1" "$(la6_open_tick "$(la6_tick)")"

# ============================================================
section "PC — THE PLAN PATH's CANONICAL FORM: one canonicalizer, three sites"
# ============================================================
#
# THE OWNERSHIP-TABLE ROW (spec §Design §3): "plan path canonical form · owning module
# `_bind_resolve` (binding.sh) · rendering surfaces: bind_plan, poker adopt, poker bind ·
# agreement test: cross-gate new row: relative path + trailing slash, three sites agree".
# AC-23 is its wording.
#
# THE DEFECT THE ROW IS WRITTEN AGAINST. Before S8 each of the three sites spelled the
# canonical form its own way: `bind_plan` resolved through `_bind_resolve`, `adopt_plan_key`
# carried an inline normalizer of its own, and `bind`'s refusal arm carried a third. Two
# spellings of one plan then produced two bindings — and `adopt`, comparing a roster row's
# `plan=` against this session's, read its own run as somebody else's.
#
# THE TWO SPELLINGS ARE THE ONES AN OPERATOR ACTUALLY PRODUCES. `./plans/…` is what a shell
# leaves when the path is completed from the docs root, and `plans/…/` is what completion
# leaves on a directory-looking path the operator was still typing. Neither is exotic and
# both name one file.
#
# EACH SITE IS ASKED IN THE FORM IT ACCEPTS, which is not a weakening of the row — it is what
# the row is about. `bind_plan` is a library function contracted to take an ABSOLUTE path, so
# its odd spellings are absolute ones; the `bind` verb takes what the operator types, so its
# are docs-root-relative; `adopt` never takes a path at all — it READS one off a foreign
# roster row — so its odd spelling is planted in that row. Three interfaces, one answer.

PC_REPO=$(new_repo "pc-canonical")
PC_DOCS="$PC_REPO/.bionic/docs"
PC_PLAN="$PC_DOCS/plans/epic-99/pc-run.md"
write_plan "$PC_PLAN" "current: 4"
# THE CANONICAL SPELLING IS THE LIBRARY'S OWN ANSWER, not a string built here. A hand-written
# expectation would pass on a tree whose sandbox path is itself a symlink (macOS `/tmp` is),
# and would be pinning this suite's idea of canonical rather than `_bind_resolve`'s.
PC_CANON=$( . "$RUN_LIB" >/dev/null 2>&1; . "$LIB_DIR_SRC/binding.sh" >/dev/null 2>&1
            _bind_resolve "$PC_PLAN" )
expect_contains "the canonicalizer answers for the fixture plan at all (not vacuous)" \
  "pc-run.md" "$PC_CANON"

pc_marker() {  # <sid> -> the plan= value on that session's marker, or empty
  sed -n 's/^plan=//p' "$PC_REPO/.bionic/tmp/engaged-$1.state" 2>/dev/null | head -1
}
pc_bind_lib() {  # <sid> <plan spelling> -> drive the LIBRARY's writer directly
  rm -f "$PC_REPO/.bionic/tmp/engaged-$1.state"
  : > "$PC_REPO/.bionic/tmp/engaged-$1.state"
  ( . "$PC_LIB_RUN" >/dev/null 2>&1; . "$PC_LIB_BIND" >/dev/null 2>&1
    bind_plan "$PC_REPO" "$1" "$2" ) >/dev/null 2>&1
  pc_marker "$1"
}
pc_bind_verb() {  # <sid> <operand> -> drive the poker's `bind` verb
  rm -f "$PC_REPO/.bionic/tmp/engaged-$1.state"
  : > "$PC_REPO/.bionic/tmp/engaged-$1.state"
  ( cd "$PC_REPO" && env CLAUDE_CODE_SESSION_ID="$1" bash "$PC_SPO" bind "$2" ) >/dev/null 2>&1
  pc_marker "$1"
}

PC_LIB_RUN="$RUN_LIB"
PC_LIB_BIND="$LIB_DIR_SRC/binding.sh"
PC_SPO="$SPO"

# --- PC.1 the library's writer: three absolute spellings, one stored value -----
PC_DOT="$PC_DOCS/./plans/epic-99/pc-run.md"
PC_SLASH="$PC_PLAN/"
expect_eq "bind_plan stores the canonical spelling for the plain path" \
  "$PC_CANON" "$(pc_bind_lib "$SID_A" "$PC_PLAN")"
expect_eq "…the same value for the ./ spelling" \
  "$PC_CANON" "$(pc_bind_lib "$SID_A" "$PC_DOT")"
expect_eq "…and the same value for the trailing-slash spelling" \
  "$PC_CANON" "$(pc_bind_lib "$SID_A" "$PC_SLASH")"

# --- PC.2 the poker's `bind` verb: the two operands an operator types ----------
#
# DOCS-ROOT-RELATIVE, because that is the spelling hooks/session-start.sh prints in its
# open-run listing and therefore the one an operator copies (S8b).
expect_eq "poker bind stores the same canonical spelling for ./plans/…" \
  "$PC_CANON" "$(pc_bind_verb "$SID_B" "./plans/epic-99/pc-run.md")"
expect_eq "…and for plans/…/ with the slash completion left on it" \
  "$PC_CANON" "$(pc_bind_verb "$SID_B" "plans/epic-99/pc-run.md/")"

# --- PC.3 the poker's `adopt`: the key it compares a foreign row's plan= by -----
#
# `adopt` produces no `plan=` of its own from a spelling — it READS one off a predecessor's
# roster row and asks whether that row belongs to THIS session's run. The canonical form is
# what makes that question answerable, so the observable is the PARTITION: a foreign row
# whose `plan=` is one of the odd spellings must land under this session's own run, and one
# naming a genuinely different plan must not.
PC_PRED="9a9a9a9a-1111-4bbb-8ccc-0000000000c1"
PC_OTHER="$PC_DOCS/plans/epic-99/pc-other.md"
write_plan "$PC_OTHER" "current: 6"
mkdir -p "$CLAUDE_CONFIG_DIR/projects/$(printf '%s' "$PC_REPO" | sed 's/[^a-zA-Z0-9]/-/g')/$PC_PRED/subagents"

pc_adopt() {  # <foreign plan= spelling> -> the adopt listing
  roster_header \
    > "$PC_REPO/.bionic/tmp/roster-$PC_PRED.state"
  roster_row_fixture status=identified session="$PC_PRED" name=pc-agent \
    agent_id=apc-1111111111111111 launched_at=2026-08-05T00:00:00Z \
    tool_use_id=toolu_01PCFIX plan="$1" \
    >> "$PC_REPO/.bionic/tmp/roster-$PC_PRED.state"
  s4_bind "$PC_REPO" "$SID_A" "$PC_PLAN"
  ( cd "$PC_REPO" && env CLAUDE_CODE_SESSION_ID="$SID_A" bash "$PC_SPO" adopt 2>&1 )
  return 0
}

PC_A_ABS=$(pc_adopt "$PC_CANON")
PC_A_DOT=$(pc_adopt "./.bionic/docs/plans/epic-99/pc-run.md")
PC_A_SLASH=$(pc_adopt ".bionic/docs/plans/epic-99/pc-run.md/")
PC_A_OTHER=$(pc_adopt "$PC_OTHER")

# NON-VACUITY FIRST: the listing must actually be about the planted row, or every `grep`
# below is asking a question of an empty answer.
expect_contains "adopt listed the planted predecessor row" "pc-agent" "$PC_A_ABS"
expect_absent "…and did NOT file it under another run when the spelling is canonical" \
  "another run" "$PC_A_ABS"
expect_absent "…nor when the row spells it ./…" "another run" "$PC_A_DOT"
expect_absent "…nor when the row spells it with a trailing slash" "another run" "$PC_A_SLASH"
# THE OTHER DIRECTION, WHICH IS WHAT MAKES THE THREE ABOVE MEAN SOMETHING: a row naming a
# genuinely different plan of the same root IS filed under another run. Without this the
# three absences would also be produced by a partition that had stopped comparing at all.
expect_contains "…while a row naming a DIFFERENT plan is filed under another run" \
  "another run" "$PC_A_OTHER"

# --- PC.4 THE DISCRIMINATOR: doctor _bind_resolve, all three sites move --------
#
# The mutation removes the directory resolution — `pwd -P` — and leaves the function
# returning what it was handed. That is precisely the pre-S8 inline normalizer's behaviour on
# these spellings, so it is a regression the codebase has actually shipped rather than
# invented damage. The shipped library is never touched: a mutant plugin tree is built
# alongside it and the three sites are driven out of THAT.
PC_MUT="$SANDBOX/pc-mutant"
mkdir -p "$PC_MUT/hooks" "$PC_MUT/scripts/lib"
cp "$LIB_DIR_SRC"/*.sh "$PC_MUT/scripts/lib/" 2>/dev/null
cp "$BIONIC_HOOKS_DIR"/*.sh "$PC_MUT/hooks/" 2>/dev/null; cp -R "$BIONIC_HOOKS_DIR/poker" "$PC_MUT/hooks/" 2>/dev/null
anchor insert payload/scripts/lib/binding.sh '_bind_resolve() {'
awk '
  /^_bind_resolve\(\) \{/ && !d { print; print "  printf '"'"'%s\\n'"'"' \"$1\"; return 0"; d = 1; next }
  { print }
' "$LIB_DIR_SRC/binding.sh" > "$PC_MUT/scripts/lib/binding.sh"

PC_LIB_BIND="$PC_MUT/scripts/lib/binding.sh"
PC_SPO="$PC_MUT/hooks/session-poker.sh"
PC_M_DOT=$(pc_bind_lib "$SID_A" "$PC_DOT")
PC_M_PLAIN=$(pc_bind_lib "$SID_A" "$PC_PLAN")
PC_M_VERB=$(pc_bind_verb "$SID_B" "./plans/epic-99/pc-run.md")
PC_M_ADOPT=$(pc_adopt "./.bionic/docs/plans/epic-99/pc-run.md")
PC_LIB_BIND="$LIB_DIR_SRC/binding.sh"
PC_SPO="$SPO"

expect_eq "doctored canonicalizer: bind_plan no longer answers canonically for ./…" \
  "no" "$([ "$PC_M_DOT" = "$PC_CANON" ] && echo yes || echo no)"
expect_eq "doctored canonicalizer: the bind VERB moves with it" \
  "no" "$([ "$PC_M_VERB" = "$PC_CANON" ] && echo yes || echo no)"
expect_contains "doctored canonicalizer: adopt files this session's own row under another run" \
  "another run" "$PC_M_ADOPT"
# NOT DISCRIMINATED BY BREAKING EVERYTHING. The mutant still binds the ALREADY-canonical
# spelling correctly, so what the three rows above caught is the missing canonicalization,
# not a writer that stopped writing.
expect_eq "…while the mutant still binds the already-canonical spelling (the arm is precise)" \
  "$PC_CANON" "$PC_M_PLAIN"

# --- PC.5 restored ------------------------------------------------------------
expect_eq "restored: bind_plan answers canonically again for ./…" \
  "$PC_CANON" "$(pc_bind_lib "$SID_A" "$PC_DOT")"

# ============================================================
section "RG — THE PRESSURE RUNG: the runner reads one ring (the tick's half retired, wave-28 T13)"
# ============================================================
#
# THE OWNERSHIP-TABLE ROW (spec §Design §3): "machine pressure level · owning module
# `pressure_level` (resources.sh) over the ring · rendering surfaces: poker fill,
# tests/run.sh, tick report line · agreement test: new row: two consumers over one ring
# compute one rung; band mutation moves both". AC-14 states the function's own contract and
# AC-15 states the consumers' obligation to SAMPLE before they read.
#
# THE TICK'S HALF IS RETIRED (wave-28 T13; D14, AC-2.8): the tick sizes its fill at the gate and
# prints no rung, so every row below that drove `session-poker.sh tick` for a rung is gone, and
# what stays holds the runner's half until its own row retires it. §ROOM holds the tick and the
# stop wall to one answer now.
#
# THE TWO CONSUMERS WERE UNRELATED PROGRAMS. `tests/run.sh` sets a suite's job width;
# `session-poker.sh tick` reports the rung and fills writers by it. They share nothing but
# the library and the ring — which is the design (D4: pressure describes the machine, so the
# ring is machine-scoped) and therefore the thing to hold. Every ring in this section lives
# under the sandbox via `BIONIC_PRESSURE_RING`; the machine's own ring is never read or
# written.
#
# THE CLOCK AND THE SENSORS ARE PINNED, or this section would be a weather report.
# `BIONIC_NOW_EPOCH` fixes the smoothing window's `now` and `BIONIC_PROBE_FREE_PCT` /
# `_SWAP_PCT` / `_LOAD_1M` fix the reading a sample takes. The load pin is not optional
# housekeeping: `pressure_band`'s load term compares the real one-minute average against
# 1.5 × cores, and this suite runs inside a parallel test run, so an unpinned drive would
# read `warning` on a busy runner and `clear` on an idle one.

RG_CEIL=8
RG_NOW=1757030000
RG_RING="$SANDBOX/rg/pressure.ring"
mkdir -p "$SANDBOX/rg"
# THE RUNNER'S ROOM IS THE CEILING (wave-32 T21). Since T2 tests/run.sh caps its ceiling at
# gate_width = floor(share x cores / 100), and this suite pins share 80 on 8 cores for ROOM
# (so the gate's room is 6). The runner this section drives gets its own config dir holding
# share 100, whose room on 8 cores is 8: the ceiling RG_CEIL names, so RG.1-RG.3 read the whole
# ceiling, its half and its quarter. The rest of the suite keeps share 80. Same move as
# tests/runner-width.test.sh (rw_share 100).
RG_HOME="$SANDBOX/rg/cfg"
mkdir -p "$RG_HOME/bionic"
printf '100\n' > "$RG_HOME/bionic/share"
# CLEAR and CRITICAL as the sensors see them: 80 % free is above every band threshold;
# 8 % free is below BAND_FREE_CRITICAL_PCT (12) and above BAND_FREE_EMERGENCY_PCT (5).
RG_CLEAR_ENV="BIONIC_PROBE_FREE_PCT=80 BIONIC_PROBE_SWAP_PCT=0 BIONIC_PROBE_LOAD_1M=0.1 BIONIC_PROBE_FREE_MB=8192"
RG_CRIT_ENV="BIONIC_PROBE_FREE_PCT=8 BIONIC_PROBE_SWAP_PCT=0 BIONIC_PROBE_LOAD_1M=0.1 BIONIC_PROBE_FREE_MB=8192"

# ONE CLEAR READING, WRITTEN BY THE REAL WRITER — not a hand-built ring file. The line's
# shape is `pressure_sample`'s to own, and a fixture that wrote it by hand would keep passing
# after the writer changed it.
rg_seed() {  # the ring, reset to exactly one sample under the given probe env — S25
             # (critic K-4 option 2): `tests/run.sh --dry-run` stopped sampling (a dry
             # run writes nothing), so a case that needs the RUNNER to read a specific
             # band must put that reading in the ring directly rather than counting on
             # the runner's own (now nonexistent) live sample under --dry-run.
  local env="$1"
  rm -f "$RG_RING"
  ( eval "export $env"
    export BIONIC_PRESSURE_RING="$RG_RING" BIONIC_NOW_EPOCH="$RG_NOW"
    . "$RG_LIB_RES" >/dev/null 2>&1
    pressure_sample "$RG_CEIL" ) >/dev/null 2>&1
}
rg_seed_clear() { rg_seed "$RG_CLEAR_ENV"; }  # the ring, reset to exactly one clear sample

# ---- the fixture world the tick needs ----------------------------------------
#
# The tick reaches its scheduler — and therefore its rung line — only with a roster carrying
# at least one row; above that it exits on `armed, nothing dispatched yet` and reports no
# rung at all. The plan carries the ceiling both consumers read against, so the two answers
# are comparable numbers rather than two scales.
RG_REPO=$(new_repo "rg-one-ring")
RG_PLAN="$RG_REPO/.bionic/docs/plans/epic-99/rg-run.md"
mkdir -p "$(dirname "$RG_PLAN")"
{
  printf -- '---\n'
  printf 'governing-skill: canonical-sdlc\ncanonical_sdlc_version: 14\n'
  printf 'intent: build\nrigor: double\nscale: wave\n'
  printf 'parallel-budget: writers=%s test_jobs=%s model=opus source=user\n' "$RG_CEIL" "$RG_CEIL"
  printf -- '---\n\n# Fixture plan\n\n## SDLC State\n\nintegration-branch: main\n'
  printf 'current: 4\n\n- Step 3: prior evidence\n'
} > "$RG_PLAN"
s4_bind "$RG_REPO" "$SID_A" "$RG_PLAN"
cg_roster_row "$RG_REPO" "$SID_A" "rg-writer" "arg-1111111111111111" "" "identified"

# ---- the two consumers, each asked through its own surface -------------------
rg_runner() {  # -> the width tests/run.sh would run at, under the pinned environment
  ( eval "export $1"
    export BIONIC_PRESSURE_RING="$RG_RING" BIONIC_NOW_EPOCH="$RG_NOW" \
           BIONIC_TEST_JOBS_CEILING="$RG_CEIL" CLAUDE_CONFIG_DIR="$RG_HOME"
    bash "$RG_TREE_RUNNER/tests/run.sh" --dry-run 2>/dev/null ) \
    | sed -n 's/^JOBS=//p' | head -1
}
RG_LIB_RES="$LIB_DIR_SRC/resources.sh"
RG_TREE_RUNNER="$REPO_ROOT"
RG_TREE_POKER="$BIONIC_HOOKS_DIR/.."
[ -d "$RG_TREE_POKER/scripts/lib" ] || RG_TREE_POKER="$BIONIC_HOOKS_DIR/../payload"

expect_eq "the runner this section drives is on disk (not vacuous)" "yes" \
  "$([ -r "$RG_TREE_RUNNER/tests/run.sh" ] && echo yes || echo no)"

# --- RG.1 one ring, one rung: a CLEAR machine gives both consumers the ceiling --
rg_seed_clear; RG_RUN_CLEAR=$(rg_runner "$RG_CLEAR_ENV")
expect_eq "a clear machine gives the runner the whole ceiling" "$RG_CEIL" "$RG_RUN_CLEAR"

# --- RG.2 …and a CRITICAL machine quarters it for both, identically ------------
# The runner's half is seeded directly with the critical reading (S25: --dry-run only
# reads the ring now, it does not sample), while the tick still takes its own live
# sample under the same env — two different mechanisms landing on the same rung.
rg_seed "$RG_CRIT_ENV"; RG_RUN_CRIT=$(rg_runner "$RG_CRIT_ENV")
expect_eq "a critical machine quarters the runner's width" "2" "$RG_RUN_CRIT"
# NON-VACUITY: the two numbers differ between RG.1 and RG.2, so the equality above is not
# two constants agreeing.
expect_eq "…and it is not the clear answer wearing a different name" "no" \
  "$([ "$RG_RUN_CRIT" = "$RG_RUN_CLEAR" ] && echo yes || echo no)"

# --- RG.3 THE BAND MUTATION: move one threshold, both consumers move -----------
#
# `BAND_FREE_CRITICAL_PCT` is the constant that decides whether 8 % free is critical. Moved
# to 1, the same reading falls through to the WARNING arm (8 < 25) and the fraction becomes a
# half instead of a quarter — so both consumers must read 4 where they read 2. A mutation
# that moved only one of them would mean one consumer had its own copy of the band table.
#
# ONE MUTANT TREE SERVES BOTH, in the two layouts the two consumers resolve: the poker finds
# its library at `$(dirname "$0")/../scripts/lib`, and `tests/run.sh` sources
# `$REPO/payload/scripts/lib`. The shipped files are never touched.
RG_MUT="$SANDBOX/rg-mutant"
mkdir -p "$RG_MUT/hooks" "$RG_MUT/scripts/lib" "$RG_MUT/tests" "$RG_MUT/payload/scripts/lib"
cp "$LIB_DIR_SRC"/*.sh "$RG_MUT/scripts/lib/" 2>/dev/null
cp "$BIONIC_HOOKS_DIR"/*.sh "$RG_MUT/hooks/" 2>/dev/null; cp -R "$BIONIC_HOOKS_DIR/poker" "$RG_MUT/hooks/" 2>/dev/null
cp "$REPO_ROOT/tests/run.sh" "$RG_MUT/tests/run.sh"
# ONE STUB SUITE, because the roster is the directory (fixit 1.5.1) and a runner
# asked to gate on an empty tests/ refuses rather than reporting green over
# nothing. This tree is only ever driven with --dry-run, which reads the same
# derived roster; the stub carries the pinned shebang the roster wall asks for,
# and the tree has no framework, so that half of the wall is inert here.
printf '#!/bin/bash\nexit 0\n' > "$RG_MUT/tests/stub.test.sh"
anchor insert payload/scripts/lib/resources.sh 'BAND_FREE_CRITICAL_PCT=12'
sed 's/^BAND_FREE_CRITICAL_PCT=12/BAND_FREE_CRITICAL_PCT=1/' \
  "$RG_LIB_RES" > "$RG_MUT/scripts/lib/resources.sh"
cp "$RG_MUT/scripts/lib"/*.sh "$RG_MUT/payload/scripts/lib/" 2>/dev/null

RG_TREE_RUNNER="$RG_MUT"; RG_TREE_POKER="$RG_MUT"
rg_seed "$RG_CRIT_ENV"; RG_RUN_BAND=$(rg_runner "$RG_CRIT_ENV")
RG_TREE_RUNNER="$REPO_ROOT"; RG_TREE_POKER="$BIONIC_HOOKS_DIR/.."
[ -d "$RG_TREE_POKER/scripts/lib" ] || RG_TREE_POKER="$BIONIC_HOOKS_DIR/../payload"

expect_eq "moved band threshold: the runner halves instead of quartering" "4" "$RG_RUN_BAND"

# --- RG.4 THE SAMPLING PROBE (S8's uncaught-probe finding) --------------------
#
# THE FINDING. S8 observed that every rung fixture in the fleet starts from an EMPTY ring —
# and over an empty ring `pressure_level` takes a sample of its own before answering. So a
# consumer that had stopped sampling would still read the right number, and deleting
# `pressure_sample` from either consumer was a change no suite could catch. AC-15 is exactly
# the obligation that hole hid.
#
# THE TICK HALF is unchanged since S9: seed the ring with ONE clear reading through the real
# writer, then put the sensors in critical. The ring is no longer empty, so `pressure_level`
# takes no sample of its own — a tick that SAMPLES appends the critical reading, medians
# clear+critical to critical (an even count resolves to the higher band) and reads the
# QUARTER: 2; a tick that only READS sees one clear sample and reports the whole CEILING: 8.
#
# THE RUNNER HALF IS RE-POINTED (S25, critic K-4 option 2). `tests/run.sh --dry-run`
# legitimately stopped sampling — a dry run now writes nothing to the ring by design — so
# the band trick above can no longer separate "removed the sample call" from "working as
# specified": neither a shipped nor a doctored --dry-run touches the ring, so both would
# read the same seeded band and this probe would go vacuous for the runner's half. AC-15
# still binds the runner's ORDINARY (non-dry) path — the one that actually launches
# suites — so that half of this probe now drives THAT path directly and checks the RING'S
# OWN LINE COUNT, not a band read back through --dry-run. Both trees below carry ONE
# two-line stub suite and nothing else, so each run completes in well under a second —
# nothing here launches the real suite roster, which would recurse into this very file.
# (The stub is what an empty tests/ became at fixit 1.5.1: the roster is the directory,
# and a runner asked to gate on an empty one refuses instead of sampling and reporting
# green.)
RG_NOSAMP="$SANDBOX/rg-nosample"
mkdir -p "$RG_NOSAMP/hooks" "$RG_NOSAMP/scripts/lib" "$RG_NOSAMP/tests/lib" "$RG_NOSAMP/payload/scripts/lib"
cp "$LIB_DIR_SRC"/*.sh "$RG_NOSAMP/scripts/lib/" "$RG_NOSAMP/payload/scripts/lib/" 2>/dev/null
cp "$BIONIC_HOOKS_DIR"/*.sh "$RG_NOSAMP/hooks/" 2>/dev/null; cp -R "$BIONIC_HOOKS_DIR/poker" "$RG_NOSAMP/hooks/" 2>/dev/null
cp "$REPO_ROOT/tests/lib/resolve-roots.sh" "$RG_NOSAMP/tests/lib/resolve-roots.sh"
printf '#!/bin/bash\nexit 0\n' > "$RG_NOSAMP/tests/stub.test.sh"
# the runner with its `pressure_sample` line removed, and nothing else changed.
#
# ANCHORED ON THE CALL'S STABLE TOKENS, NOT ON ITS INDENTATION (critic K-1 — the same
# lesson the poker's own anchor just below already carries). S25 moved this call inside an
# `if [ "$DRY_RUN" -eq 0 ]` guard, re-indenting it two spaces; `[[:space:]]*` absorbs that
# reindent and any future one.
#
# REPLACED BY `:`, NOT DELETED (wave-28 T53). The call is the only command in its `if …; then`,
# and a deleted line left `then fi`, which bash refuses to parse: the mutant died before its
# first suite, so its untouched ring proved a dead runner, not a runner that stopped sampling.
anchor file tests/run.sh 'pressure_sample >/dev/null 2>&1 || :'
sed -E 's/^([[:space:]]*)pressure_sample >\/dev\/null 2>&1 \|\| :$/\1:/' "$REPO_ROOT/tests/run.sh" \
  > "$RG_NOSAMP/tests/run.sh"
# THE SHIPPED CONTROL TREE for the runner half: the real tests/run.sh, byte for byte, in a
# scratch tree with no real suite files — so "shipped" and "no-sample" differ ONLY in the
# one line the grep above removed, never in which suites they would (fail to) run.
RG_SHIPPED="$SANDBOX/rg-shipped"
mkdir -p "$RG_SHIPPED/tests/lib" "$RG_SHIPPED/payload/scripts/lib"
cp "$LIB_DIR_SRC"/*.sh "$RG_SHIPPED/payload/scripts/lib/" 2>/dev/null
cp "$REPO_ROOT/tests/lib/resolve-roots.sh" "$RG_SHIPPED/tests/lib/resolve-roots.sh"
cp "$REPO_ROOT/tests/run.sh" "$RG_SHIPPED/tests/run.sh"
printf '#!/bin/bash\nexit 0\n' > "$RG_SHIPPED/tests/stub.test.sh"
expect_eq "the shipped control tree carries the runner byte for byte (not vacuous)" "yes" \
  "$(cmp -s "$REPO_ROOT/tests/run.sh" "$RG_SHIPPED/tests/run.sh" && echo yes || echo no)"

# THE DRIVES HOLD AN ADMISSION, AND EACH IS BOUNDED (wave-28 T53; AC-2.6, AC-2.12). Since T12
# every `--one` worker asks the gate for its suite with no ceiling (a wait at the gate never
# ends a run, AC-2.6), and the gate reads the machine through the same pins this section
# plants critical: with its memory reader unpinned it read 92 % used, admitted nothing, and the
# worker polled for ever (T44's third merge; T9's RED). So the fixture asks ONCE, under the
# clear reading, in a store of this section's own, and hands both drives that admission in
# BIONIC_GATE_ADMIT. Its holder is this suite's shell (the `$$` of a `$( )`), the gate believes
# it for any descendant, so the workers run as a nested run's do (tests/run.sh NESTING) and ask
# nothing of their own — while the ring's sensors stay critical for the sample under test.
# The ask itself is bounded (`--within`, on the real clock: `_res_now` under a pinned epoch
# never moves), and each drive runs under lib/detect.sh's `detect_bounded`, so a drive the
# gate still holds ends "hung" — red on both rows below — inside RG_DRIVE_BOUND seconds
# instead of hanging the suite. The bound is the rows' guard; the admission is the fix.
RG_GATE="$SANDBOX/rg/gate"
RG_DRIVE_BOUND=120
RG_ADMIT="$( unset BIONIC_GATE_ADMIT BIONIC_NOW_EPOCH BIONIC_LOAD_NOW_FILE BIONIC_PROBE_USED_PCT
  eval "export $RG_CLEAR_ENV"; export BIONIC_GATE_DIR="$RG_GATE"
  . "$LIB_DIR_SRC/gate.sh" >/dev/null 2>&1 && gate_ask work rg-runner-drive --within 30 2>/dev/null )" \
  || RG_ADMIT=""
expect_eq "§RG the bound the drives run under is loaded (not vacuous)" "yes" \
  "$( . "$LIB_DIR_SRC/detect.sh" >/dev/null 2>&1; declare -F detect_bounded >/dev/null && echo yes || echo no)"

# rg_runner_samples <tree> -> "yes" if <tree>/tests/run.sh's ORDINARY (non-dry) path
# appends exactly one line to a ring seeded with one clear sample; "no" otherwise; "hung"
# when the drive did not end inside RG_DRIVE_BOUND.
rg_runner_samples() {
  local tree="$1" before after rc
  rg_seed_clear
  before="$(wc -l < "$RG_RING" | tr -d ' ')"
  ( eval "export $RG_CRIT_ENV"
    cd "$tree" &&
    export BIONIC_PRESSURE_RING="$RG_RING" BIONIC_NOW_EPOCH="$RG_NOW" \
           BIONIC_TEST_JOBS_CEILING="$RG_CEIL" \
           BIONIC_GATE_DIR="$RG_GATE" BIONIC_GATE_ADMIT="$RG_ADMIT" &&
    . "$LIB_DIR_SRC/detect.sh" >/dev/null 2>&1 &&
    detect_bounded "$RG_DRIVE_BOUND" bash tests/run.sh >"$SANDBOX/rg/drive-${tree##*/}.out" 2>&1 )
  rc=$?
  after="$(wc -l < "$RG_RING" | tr -d ' ')"
  [ "$rc" -ne 124 ] || { echo hung; return 0; }
  [ "$after" -eq "$((before + 1))" ] && echo yes || echo no
}

RG_RUN_SHIPPED_SAMPLES=$(rg_runner_samples "$RG_SHIPPED")
RG_RUN_NOSAMP_SAMPLES=$(rg_runner_samples "$RG_NOSAMP")
[ -z "$RG_ADMIT" ] || ( unset BIONIC_NOW_EPOCH BIONIC_LOAD_NOW_FILE; export BIONIC_GATE_DIR="$RG_GATE"
  . "$LIB_DIR_SRC/gate.sh" >/dev/null 2>&1 && gate_end "$RG_ADMIT" 0 >/dev/null 2>&1 )
expect_eq "the shipped runner's ordinary path samples once (AC-15)" "yes" \
  "$RG_RUN_SHIPPED_SAMPLES"
expect_eq "a runner that stopped sampling leaves the ring untouched: the removal is CAUGHT" \
  "no" "$RG_RUN_NOSAMP_SAMPLES"
# T53 ROWS. "no" above means the mutant RAN and did not sample — never that it died before its
# first suite, which a deleted line inside `if …; then` once made it do — so each drive shows
# its stub ran; and the admission is shown held: the fixture's one request is in the store and
# no worker of either drive took one of its own.
expect_eq "§RG the no-sample mutant is a script bash can read (not vacuous)" "0" \
  "$(bash -n "$RG_NOSAMP/tests/run.sh" >/dev/null 2>&1; echo $?)"
expect_contains "§RG the shipped drive ran its stub suite to the end" "Gating: 1 passed" \
  "$(cat "$SANDBOX/rg/drive-rg-shipped.out" 2>/dev/null)"
expect_contains "§RG …and so did the no-sample drive: its 'no' is a runner that ran" "Gating: 1 passed" \
  "$(cat "$SANDBOX/rg/drive-rg-nosample.out" 2>/dev/null)"
rg_store_keys() {  # <key> -> how many requests in the section's own gate store carry it
  cat "$RG_GATE"/requests/* 2>/dev/null | LC_ALL=C awk -v k="key=$1" '$0 == k { c++ } END { print c + 0 }'
}
expect_eq "§RG the fixture holds one admission for its drives, in the section's own store" "1" \
  "$(rg_store_keys rg-runner-drive)"
expect_eq "§RG …and the drives' workers ran under it: they asked the gate nothing of their own" "0" \
  "$(rg_store_keys stub.test.sh)"
expect_eq "§RG …and the fixture ends what it took: its admission is closed, rc 0" "0" \
  "$(sed -n 's/^rc=//p' "$RG_GATE/requests/${RG_ADMIT:-none}" 2>/dev/null)"

# --- RG.5 the pin is honoured: this section's readings are on this section's ring ---
#
# Asserted rather than trusted. Every drive above ran with `BIONIC_PRESSURE_RING` set, and a
# consumer that ignored the pin would append to the DEFAULT ring under
# `${CLAUDE_CONFIG_DIR}/bionic/` instead. Both paths are inside the sandbox — the suite
# redirects `CLAUDE_CONFIG_DIR` in its header, which is what keeps the machine's own ring out
# of reach of every section in this file — so the question is not whether a default ring
# exists (other sections in this file drive the tick without a pin and create one), but
# whether any reading STAMPED WITH THIS SECTION'S PINNED CLOCK landed on it.
rg_ring_count() {  # <ring file> -> how many of this section's samples it holds
  [ -f "$1" ] || { printf '0'; return 0; }
  LC_ALL=C awk -F'|' -v n="$RG_NOW" '$1 == n { c++ } END { print c + 0 }' "$1" 2>/dev/null
}
expect_eq "the sandbox ring holds this section's readings" "yes" \
  "$([ "$(rg_ring_count "$RG_RING")" -gt 0 ] && echo yes || echo no)"
expect_eq "…and the default ring holds none of them: the pin was honoured by every consumer" \
  "0" "$(rg_ring_count "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/bionic/pressure.ring")"
expect_contains "…and that default ring is itself inside the sandbox, never the machine's" \
  "$SANDBOX" "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/bionic/pressure.ring"
# ============================================================
section "BP — no hook or wall library pipes a variable into a quitting grep"
# ============================================================
#
# WHAT MOVED (wave-28 T37). This section held three sweeps. The `/bin/bash -n` parse sweep
# with its mutant, and the one-line `$(case` grep with its quoted plant, are now
# tests/shell-lint.test.sh §PARSE and §CASE, rows unchanged, beside the lexer that sees what
# both miss. What stays is the one shape no lexer of 3.2's grammar can see.
#
# THE SHAPE NEITHER `-n` NOR A RUN CAN SEE UNTIL THE DATA GROWS (wave-14 T37).
# `echo "$VAR" | grep -q PAT` parses, and answers correctly, for as long as $VAR fits in the
# 64 KB pipe buffer. Past that the producer is still writing when `grep -q` exits at its
# FIRST match; it takes SIGPIPE and exits 141, and under `set -o pipefail` — which
# hooks/bash-walls.sh (:86) and hooks/stop-guard.sh (:46) both set — the pipeline reports
# 141 rather than grep's 0. So `if ! …` reads a MATCH as a failure, and the wall inverts.
# This is not hypothetical: the evidence gate refused EVERY commit in this repo once the
# plan's `## Verification Matrix` section passed 64 KB, on a plan whose `stack-health:` line
# was present and valid (tests/canonical-sdlc-evidence-gate.test.sh Section 40 pins the
# behaviour; this row pins the IDIOM, which is what stops it coming back).
#
# The fix is a here-string, which has no second process to lose, so the rule is: no wall
# library and no hook reads a variable through a pipe into a quitting `grep`. Tests are NOT
# swept — a fixture builder is not a wall, and several here legitimately pipe.
# The pattern is written in bracket classes so this file's own source does not match the
# rule it enforces.
# A literal `$` the printf builders below plant into fixture files without this file's own
# expansion reaching it.
BP_Q_DOL='$'
BP_Q_RE='(echo|printf)[^|]*"[$][{A-Za-z_][^|]*[|][[:space:]]*(/usr/bin/)?grep[[:space:]]+-[A-Za-z]*q'
BP_Q_FILES="$(cd "$BIONIC_SCRIPTS_DIR" && find hooks payload/scripts/lib -name '*.sh' -type f \
  2>/dev/null | LC_ALL=C sort)"
expect_eq "the quitting-grep sweep found shell files to check" "yes" \
  "$([ -n "$BP_Q_FILES" ] && echo yes || echo no)"
# CODE LINES ONLY. A WHOLE-LINE COMMENT IS EXEMPT, and it has to be: the fix in
# walls.sh explains the defect by SPELLING the banned idiom, and a rule that forbids
# documenting what it bans would be paid for in silence. A comment executes nothing, so
# the exemption costs the rule no power — and it is narrow, dropping only lines whose
# FIRST non-blank character is `#`, never a code line that carries the idiom with a
# comment after it. The pair of rows below pins both halves of that.
# `-H` IS FORCED ON EVERY CALL, not decoration: BSD and GNU grep both omit the filename
# when given exactly ONE file, so a single-file planted fixture would print `2:  # …`
# while the multi-file sweep prints `path:2:  # …`. One output shape means one filter.
bp_q_code_only() {  # <grep -nH output> -> the same rows minus whole-line comments
  LC_ALL=C grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' || true
}
BP_Q_HITS="$(cd "$BIONIC_SCRIPTS_DIR" && LC_ALL=C grep -nHE "$BP_Q_RE" \
  $(printf '%s\n' "$BP_Q_FILES" | tr '\n' ' ') 2>/dev/null | bp_q_code_only)"
expect_eq "no hook or wall library pipes a variable into a quitting \`grep -q\`" "" "$BP_Q_HITS"

# THE EXEMPTION IS NARROW, both directions, on planted lines rather than on the tree.
BP_Q_CMT="$SANDBOX/bp-q-comment.sh"
printf '#!/bin/bash\n  # echo "%sBIG" | grep -qE needle  <- a comment, not a site\nx=1\n' \
  "$BP_Q_DOL" > "$BP_Q_CMT"
expect_eq "…and a whole-line COMMENT spelling the idiom is not a site" "" \
  "$(LC_ALL=C grep -nHE "$BP_Q_RE" "$BP_Q_CMT" | bp_q_code_only)"
expect_eq "…though the raw grep did match it, so the exemption is what dropped it" "yes" \
  "$([ -n "$(LC_ALL=C grep -nHE "$BP_Q_RE" "$BP_Q_CMT")" ] && echo yes || echo no)"
BP_Q_TRAIL="$SANDBOX/bp-q-trailing.sh"
printf '#!/bin/bash\nif echo "%sBIG" | grep -qE needle ; then :; fi  # still a site\n' \
  "$BP_Q_DOL" > "$BP_Q_TRAIL"
expect_eq "…while a CODE line carrying the idiom is still caught, comment or not" "yes" \
  "$([ -n "$(LC_ALL=C grep -nHE "$BP_Q_RE" "$BP_Q_TRAIL" | bp_q_code_only)" ] && echo yes || echo no)"

# THE MUTATION ARM, in two halves. The first proves the grep discriminates; the second
# proves the defect it stands for is REAL under pipefail, so the row is not a style pin.
# A plant written whole by printf: nothing shipped to anchor.
BP_Q_PLANT="$SANDBOX/bp-quitting-grep.sh"
printf '#!/bin/bash\nset -uo pipefail\nBIG="%s1"\nif ! echo "%sBIG" | grep -qE "^needle" ; then\n  echo REFUSED\nelse\n  echo ALLOWED\nfi\n' \
  "$BP_Q_DOL" "$BP_Q_DOL" > "$BP_Q_PLANT"
expect_eq "the mutation arm: the planted idiom PARSES, so -n cannot catch it" "0" \
  "$(/bin/bash -n "$BP_Q_PLANT" >/dev/null 2>&1; echo $?)"
expect_eq "…and the grep catches it" "yes" \
  "$([ -n "$(LC_ALL=C grep -nHE "$BP_Q_RE" "$BP_Q_PLANT")" ] && echo yes || echo no)"
# The same planted file, run twice on the SAME needle, differing only in how much data
# trails the match: under the buffer it answers ALLOWED, over it the wall inverts.
BP_Q_SMALL="$(/bin/bash "$BP_Q_PLANT" "$(printf 'needle\npadding\n')")"
BP_Q_BIG="$(/bin/bash "$BP_Q_PLANT" "$(printf 'needle\n'; LC_ALL=C awk 'BEGIN{for(i=0;i<9000;i++) print "padding padding padding padding padding padding"}')")"
expect_eq "…the planted idiom answers correctly while the subject fits the pipe buffer" \
  "ALLOWED" "$BP_Q_SMALL"
expect_eq "…and INVERTS once it does not: a present needle read as absent" \
  "REFUSED" "$BP_Q_BIG"
# The here-string the sweep requires instead, on the same oversized subject, does not.
BP_Q_FIX="$SANDBOX/bp-herestring.sh"
printf '#!/bin/bash\nset -uo pipefail\nBIG="%s1"\nif ! grep -qE "^needle" <<< "%sBIG" ; then\n  echo REFUSED\nelse\n  echo ALLOWED\nfi\n' \
  "$BP_Q_DOL" "$BP_Q_DOL" > "$BP_Q_FIX"
expect_eq "…while the here-string answers ALLOWED on the SAME oversized subject" "ALLOWED" \
  "$(/bin/bash "$BP_Q_FIX" "$(printf 'needle\n'; LC_ALL=C awk 'BEGIN{for(i=0;i<9000;i++) print "padding padding padding padding padding padding"}')")"
expect_eq "…and the sweep does not flag the here-string form" "" \
  "$(LC_ALL=C grep -nHE "$BP_Q_RE" "$BP_Q_FIX")"

# ------------------------------------------------ §DS OWNERSHIP: the fix hint and the roster
#
# ONE TABLE, TWO RENDERERS, FOUR WAYS OF ASKING WHETHER THEY AGREE (fixit 1.5.1).
# `payload/scripts/lib/checks.sh` holds the table: one row per fact bionic needs true on a
# machine, carrying that fact's detector, the party who repairs it, the setup item when that
# party is setup, and the hint a report must print. doctor.sh and setup.sh render from it and
# neither owns a check of its own, so this section stopped comparing the two SCRIPTS against
# each other and started comparing each of them against the table. The four legs, each with
# its own sub-banner below:
#
#   DS.2a  every labelled row that FIRES renders somewhere on doctor's page, with its hint
#   DS.2   everything doctor renders resolves to a row of the table, party and item included
#   DS.2b  setup's `--list` IS the table's item column, set against set, both directions
#   DS.2c  the same machine, both sides: an item setup would offer is flagged by doctor
#
# and the mutation arms DS.5–DS.10 plant, on copies, each drift those legs exist to catch.
#
# THE TWO PARTIES ARE doctor.sh AND setup.sh, and the question they have to answer the same
# way is "what can /bionic:setup repair on this machine". Doctor ends a row with
# `→ /bionic:setup` to say the command below will clear it; setup's `--list` is the roster of
# what that command can be asked for, and `_setup_item_pending` decides which of those it
# would actually offer on the machine in front of it. Nothing bound the three together, and
# on 2026-09-05 they disagreed in the field: doctor printed `16 legacy hook files … →
# /bionic:setup` and `6/6 differ … → /bionic:setup`, and `/bionic:setup --all` run straight
# afterwards planned one dependency and ended "nothing left to do — this machine is set up."
# (bug report .bionic/docs/ideas/bug-doctor-setup-ownership.md, filed against payload 1.4.3).
# A hint naming a command that then reports nothing to do is worse than no hint: the reader
# runs it, believes the green summary, and the ✗ row is still there on the next run.
#
# ONE FIXTURE, BOTH SCRIPTS, THE SAME MACHINE STATE. Every row below is taken on a
# claude-home this section builds — leftover hook FILES the payload ships by the same name,
# leftover agent role files that no longer match the payload — with `BIONIC_PLUGIN_ROOT`
# pointing at the shipped payload so both scripts read the same idea of what bionic ships.
# Doctor is rendered and its rows are parsed; setup is asked `--list` and then asked to run
# the one item narrowed, with the answer channel CLOSED so a pending item reports itself
# through its action line and nothing on the fixture is ever written.
#
# BOTH TABLES ARE IN SCOPE NOW (1.4.4 fixit T1, AC-1). The scan used to take doctor's
# ENVIRONMENT section alone — the table that reports the machine's own state, where the five
# leftover rows and the environment keys live — and said so here: the THIRD PARTY table was
# "a separate question with a separate answer", because a core dependency doctor reports
# absent is installed by the CLI as bionic's own dependency and not by a setup item. That
# was the right answer to the wrong question. The separate answer is what the ROW must say;
# it is not a reason to leave the row unscanned, and while it was unscanned the row went on
# ending `→ /bionic:setup` over a command that plans nothing for it — the same defect this
# section exists to catch, in the one table it could not see. So the hint is checked in both
# tables against one rule (every `→ /bionic:setup` needs an item that fires), and the core
# row is checked against the other half of the contract: it names the CLI's repair route and
# never sends anyone to setup. §DS.7 and §DS.8 below.
#
# THE MUTATION ARMS ARE BOTH DIRECTIONS OF THE SAME DRIFT. A doctored setup.sh whose roster
# has lost `legacy-hook-files` must take the agreement row red — that is the exact field
# defect, a hint with no item behind it. A doctored doctor.sh carrying a NEW hinted row must
# take the completeness row red — that is the defect arriving tomorrow, a row added with the
# suffix and no item to go with it. Neither mutant is ever the shipped file: both are copies
# under the sandbox, driven through the same `W1R_PARTY_*` override the four parties above
# use.

DS_PAYLOAD="${BIONIC_SCRIPTS_DIR}/payload"
PARTY_DOCTOR="${W1R_PARTY_DOCTOR:-$DS_PAYLOAD/scripts/doctor.sh}"
PARTY_SETUP="${W1R_PARTY_SETUP:-$DS_PAYLOAD/scripts/setup.sh}"

DS_DIR="$SANDBOX/ds"
mkdir -p "$DS_DIR"

# The claude-home the field machine had: hook SCRIPTS the retired installer copied in, and
# role files two builds behind the payload's. Sixteen of the payload's hook names and all six
# of its agent names, which is the shape the bug report measured (16 in ~/.claude/hooks, 6/6
# differ) — and NOT every hook the payload ships, so a run that removed by wildcard instead of
# by name would show up as a count that is too high.
#
# ONE FILE IN EACH DIRECTORY IS NOT BIONIC'S, and it is the whole point of planting them: both
# detectors match payload-side names only, both removals must too, and a machine's own hook or
# its own agent is not bionic's leftover to delete.
# AND THE STATUS LINE THE FIELD MACHINE ACTUALLY HAD (epic-21 1.4.4 T5). Every machine
# that ran setup before this patch carries `npx ccstatusline@latest` in settings.json AND
# the shipped layout under ~/.config/ccstatusline — the two halves `_dep_check_statusline`
# reads. Planting only the first would leave the row absent for the layout's sake and prove
# nothing about the command; planting both is the pre-1.4.4 shape, where the ONLY thing
# wrong is the recorded command. That is the state doctor's `statusLine command` row fires
# on, so it is the state this scan has to see it in.
ds_plant() {  # <home> <hooks:yes|no> <agents:yes|no> [alias:changed|no, default no]
  local h="$1" want_hooks="$2" want_agents="$3" want_alias="${4:-no}" f n=0
  rm -rf "$h"; mkdir -p "$h/.claude"
  # AND ONE ENVIRONMENT NAME WRITTEN TO THE WRONG VALUE (Step-6 review B-1). The
  # environment row has two firing states — the name is absent from the `env`
  # object, or it is there carrying something other than the value bionic sets —
  # and this fixture used to reach only the first, because it wrote no `env`
  # object at all. The second is the state where doctor and setup disagreed in
  # the field's own shape: a tick from the page over a repair setup was still
  # offering. One key is planted wrong and the other two are left absent, so the
  # scans below see both states of the same row on one machine.
  cat > "$h/.claude/settings.json" <<'DSJSON'
{
  "statusLine": {
    "type": "command",
    "command": "npx ccstatusline@latest"
  },
  "env": {
    "BASH_MAX_TIMEOUT_MS": "600000"
  }
}
DSJSON
  mkdir -p "$h/.config/ccstatusline"
  cp "$DS_PAYLOAD/ccstatusline/settings.json" "$h/.config/ccstatusline/settings.json"
  # AND THE PLUGIN REGISTRY, WITH ONE CORE DEPENDENCY MISSING (1.4.4 fixit T1). This is the
  # seam `_dep_check_native` reads — `$BIONIC_CLAUDE_HOME/plugins/installed_plugins.json` via
  # `_dep_installed_json` — and writing it is what makes a core dependency absent WITHOUT
  # installing or uninstalling anything for real. The shape is this machine's own registry
  # (`bionic`, `agent-skills`, `impeccable` from bionic's catalog; the two anthropic skill
  # packs from theirs) minus `superpowers`, which is exactly the machine epic-17 W5 F12 §4.1
  # measured: the CLI refuses to load bionic and its own error names the repair
  # (record/epic-17-w5/f12-runtime-report.md §4.1). Leaving the file out entirely — which is
  # what this fixture used to do — reads as EVERY native row absent, including the ones that
  # are fine, so the table under test would have been all one state.
  mkdir -p "$h/.claude/plugins"
  cat > "$h/.claude/plugins/installed_plugins.json" <<'DSREG'
{
  "plugins": {
    "bionic@bionic":                          [{"version": "1.4.4", "installPath": "/nonexistent/bionic"}],
    "agent-skills@bionic":                    [{"version": "0.6.7", "installPath": "/nonexistent/agent-skills"}],
    "impeccable@bionic":                      [{"version": "4.1.1", "installPath": "/nonexistent/impeccable"}],
    "document-skills@anthropic-agent-skills": [{"version": "41bbe19d1a1a", "installPath": "/nonexistent/document-skills"}],
    "example-skills@anthropic-agent-skills":  [{"version": "41bbe19d1a1a", "installPath": "/nonexistent/example-skills"}]
  }
}
DSREG
  if [ "$want_hooks" = "yes" ]; then
    mkdir -p "$h/.claude/hooks"
    for f in "$DS_PAYLOAD"/hooks/*.sh; do
      [ -f "$f" ] || continue
      [ "$n" -lt 16 ] || break
      printf '#!/bin/bash\n# an older build of %s\n' "${f##*/}" > "$h/.claude/hooks/${f##*/}"
      n=$((n + 1))
    done
    # THE COUNT THE ROW ASSERTS IS THE COUNT THIS LOOP PLANTED (T23). The cap is the field
    # machine's sixteen, and the payload has carried fewer hook names since the five Bash
    # walls became one file — so a literal here would go stale with the roster while still
    # looking like a measurement.
    DS_PLANTED_HOOKS="$n"
    printf '#!/bin/bash\n# the machine owner wrote this one\n' > "$h/.claude/hooks/not-bionics.sh"
  fi
  # THE RETIRED ALIAS BLOCK, ITS BODY CHANGED, OFF BY DEFAULT (Step-6 recheck part 4,
  # R-2; the state moved at wave-27 T75, A-orch-173). The one leftover whose two rules
  # can still differ: `bionic_check_legacy_alias` fires only on bionic's own whole
  # block, the body bionic wrote between its markers and free to go, while the raw fact
  # `detect_zshrc_legacy_block` reads the markers and nothing else. Planted here is a
  # marked block whose body the user changed: present to the raw fact, nothing to do to
  # the table. (The state this arm first planted, the bare pre-marker line, is gone:
  # under the markers rule no door takes a bare line out, and rc-item §T75 pins that it
  # is named, never offered.) BOTH rc names are written because `shell_rc_file` picks
  # between `$HOME/.zshrc` and `$HOME/.bashrc` off `$SHELL`, and the suite must not read
  # the runner's shell. Default `no`, so every fixture planted before this arm existed
  # is byte-identical to what it was.
  if [ "$want_alias" = "changed" ]; then
    printf '%s\n' '# ─── bionic:start ───' "alias claude='claude --dangerously-skip-permissions'" 'export MINE=1' \
      '# ─── bionic:end ───' > "$h/.zshrc"
    cp "$h/.zshrc" "$h/.bashrc"
  fi
  # AND THE PROJECT THIS MACHINE IS ASKED ABOUT, CARRYING BOTH AUTO-MEMORY FACTS
  # (wave-23 D5, AC-3.4). The `auto-memory` row is the second project-scoped row in
  # the table: it reads the project's own `.claude/settings.json` for an `env`
  # value that sets CLAUDE_CODE_DISABLE_AUTO_MEMORY back to "0", and the CLI's
  # `projects/<slug>/memory/` directory for files written before the switch was
  # set. A row whose detector never fires on this fixture passes DS.2a vacuously,
  # so both facts are planted, on every home, at `<home>/project` — which every
  # runner below names as the project through `BIONIC_ROOT`. The slug is the
  # physical path with every non-alphanumeric replaced by `-`, as the CLI names it.
  mkdir -p "$h/project/.claude"
  printf '{"env": {"CLAUDE_CODE_DISABLE_AUTO_MEMORY": "0"}}\n' > "$h/project/.claude/settings.json"
  DS_AM_DIR="$h/.claude/projects/$( (cd "$h/project" && pwd -P) | sed 's/[^a-zA-Z0-9]/-/g')/memory"
  mkdir -p "$DS_AM_DIR"
  printf 'index\n' > "$DS_AM_DIR/MEMORY.md"
  printf 'a fact\n' > "$DS_AM_DIR/some-fact.md"
  if [ "$want_agents" = "yes" ]; then
    mkdir -p "$h/.claude/agents"
    for f in "$DS_PAYLOAD"/agents/*.md; do
      [ -f "$f" ] || continue
      printf -- '---\nname: %s\n---\nan older build of this role.\n' "${f##*/}" \
        > "$h/.claude/agents/${f##*/}"
    done
    printf -- '---\nname: not-bionics\n---\nthe machine owner wrote this one.\n' \
      > "$h/.claude/agents/not-bionics.md"
  fi
}

ds_doctor() {  # <home> -> doctor's whole report
  HOME="$1" BIONIC_CLAUDE_HOME="$1/.claude" BIONIC_PLUGIN_ROOT="$DS_PAYLOAD" BIONIC_ROOT="$1/project" \
    bash "$PARTY_DOCTOR" 2>/dev/null
}

# The answer channel is CLOSED on purpose: every question this reaches goes unanswered, the
# step reports itself through its action line, and the fixture is never written to. That is
# what makes a pending item observable without consenting to anything.
ds_setup() {  # <home> <args…> -> setup's whole run
  local h="$1"; shift
  HOME="$h" BIONIC_CLAUDE_HOME="$h/.claude" BIONIC_PLUGIN_ROOT="$DS_PAYLOAD" BIONIC_ROOT="$h/project" \
    bash "$PARTY_SETUP" "$@" < /dev/null 2>/dev/null
}

# The one arm that consents, for the removal rows: exactly one `y`, to exactly one question.
ds_setup_yes() {  # <home> <args…>
  local h="$1"; shift
  printf 'y\n' | HOME="$h" BIONIC_CLAUDE_HOME="$h/.claude" BIONIC_PLUGIN_ROOT="$DS_PAYLOAD" BIONIC_ROOT="$h/project" \
    bash "$PARTY_SETUP" "$@" 2>/dev/null
}

# ── The table both parties render from ───────────────────────────────────────
#
# ONE SOURCE, READ THE WAY BOTH SCRIPTS READ IT. `payload/scripts/lib/checks.sh`
# holds one row per fact bionic needs true on a machine — id, doctor's label, the
# read-only detector, the repair party, the setup item when that party is setup,
# and the hint the report must carry. Doctor renders from it and setup renders
# from it, so this section asks the table what the answer should be instead of
# carrying a hand-written map of its own. The two maps that used to live here
# (`ds_item_for`, `ds_party_item_for`, 22 dependency names and six labels spelled
# out by hand) were the claim under test only while nothing in the payload held
# the claim; now something does, and a copy of it here would be the second source
# this whole task exists to remove.
#
# READ UNDER THE FIXTURE'S OWN ENVIRONMENT, exactly as `ds_doctor` and `ds_setup`
# are: the table's generated half asks the dependency catalog and the CLI's own
# duplicate probe, and a table read under the SUITE's environment would be a
# different machine's table than the one the two renderers just read.
DS_CHECKS_LIB="${W1R_PARTY_CHECKS:-$DS_PAYLOAD/scripts/lib/checks.sh}"

ds_rows() {  # <home> -> the whole check table, one row per line
  HOME="$1" BIONIC_CLAUDE_HOME="$1/.claude" BIONIC_PLUGIN_ROOT="$DS_PAYLOAD" BIONIC_ROOT="$1/project" \
    bash -c '. "$1" >/dev/null 2>&1 || exit 1; bionic_check_rows' _ "$DS_CHECKS_LIB" 2>/dev/null
}

ds_field() {  # <row> <1..6>
  printf '%s' "$(printf '%s' "$1" | cut -d'|' -f"$2")"
}

# ONE EXTRACTOR, TAKING THE HEADER (fixit B-8). `ds_env_section` and
# `ds_third_section` were the same four lines of awk twice, differing only in the
# header they open on, and `ds_hint_labels`/`ds_party_hint_labels` were the same
# loop twice, differing only in which of those two they called. Four helpers, two
# behaviours, and a fix applied to one copy of either pair would have been a fix
# the other copy did not get. Rows are indented two columns, so a bare capitalised
# line is always a section header and never a row; the header itself is consumed
# before any row is read, so a section name can never be mistaken for a hint.
ds_section() {  # <doctor report> <header pattern>
  awk -v hdr="$2" '
    $0 ~ ("^" hdr) && !inside { inside = 1; next }
    inside && /^[A-Z][A-Z]/ { exit }
    inside { print }' <<<"$1"
}

# Every line in doctor's two machine-state tables that carries a repair route. A
# route is whatever the table says a route is — `/bionic:setup` for the rows setup
# clears, the CLI's own reinstall verb for the rows it does not — so a row that
# names a party gets scanned no matter which party that is, and no matter whether
# the hint reaches it through an arrow or an em-dash. THAT last part is the
# widening: the old extractor matched the literal `→ /bionic:setup`, and three
# hinted rows (doctor.sh's stale-dependency row and both claude()-proxy rows) said
# `— /bionic:setup …` instead and were never scanned at all.
ds_hinted_lines() {  # <doctor report> <routes, one per line>
  local line route hit
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    hit=""
    while IFS= read -r route; do
      [ -n "$route" ] || continue
      case "$line" in *"$route"*) hit=1; break ;; esac
    done <<<"$2"
    [ -n "$hit" ] && printf '%s\n' "$line"
  done <<<"$(ds_section "$1" "ENVIRONMENT$")
$(ds_section "$1" "THIRD PARTY")"
  return 0
}

# EVERY LABELLED ROW THAT FIRES ON THIS MACHINE, asked in ONE process (Step-6
# review A-2/A-4, C-1). `ds_hinted_lines` starts from doctor's page and keeps the
# lines that already carry a route, which can only ever prove "the route you
# printed is the one your row names" — a row that lost its route, or a row doctor
# never renders at all, is filtered out before any leg reads it. This starts from
# the TABLE instead: every row with a label whose detector fires, whatever its
# party, so the walk below can require a rendering rather than notice one.
ds_fired_rows() {  # <home> -> id|label|hint for every labelled row that fires
  HOME="$1" BIONIC_CLAUDE_HOME="$1/.claude" BIONIC_PLUGIN_ROOT="$DS_PAYLOAD" BIONIC_ROOT="$1/project" \
    bash -c '. "$1" >/dev/null 2>&1 || exit 1
             bionic_check_rows | while IFS="|" read -r ds_i ds_l ds_d ds_p ds_it ds_h; do
               [ -n "$ds_l" ] || continue
               [ -n "$ds_d" ] || continue
               "$ds_d" "$ds_i" || continue
               printf "%s|%s|%s\n" "$ds_i" "$ds_l" "$ds_h"
             done' _ "$DS_CHECKS_LIB" 2>/dev/null
}

# THE WHOLE PAGE, NOT TWO SECTIONS (plan A-T5-5). A row renders where its section
# puts it — the environment loop, the dependency walk, the leftover block — and a
# leg that reads ENVIRONMENT and THIRD PARTY alone cannot see a row rendered in
# PATROL or RESOURCES, or one rendered nowhere. Every rendered row has the same
# shape: two spaces, one state glyph, a space, then the label. The column-header
# line starts with four spaces and is skipped by the glyph test.
ds_page_line_for() {  # <doctor report> <label> -> the rendered line carrying it
  local line rest
  while IFS= read -r line; do
    case "$line" in ("  "*) ;; (*) continue ;; esac
    rest="${line#  }"
    case "$rest" in (" "*) continue ;; esac
    rest="${rest#* }"
    case "$rest" in
      ("$2") printf '%s' "$line"; return 0 ;;
      ("$2 "*) printf '%s' "$line"; return 0 ;;
    esac
  done <<<"$1"
  return 1
}

# The walk itself, factored out because the two mutation arms at the end of this
# section run the very same code over a doctored library and have to come out
# non-empty. Answers with one line per row that is missing, unrendered or hintless.
ds_unrendered() {  # <doctor report> <fired rows> -> the rows the page does not carry
  local row id label hint line out=""
  while IFS='|' read -r id label hint; do
    [ -n "$id" ] || continue
    if [ -z "$hint" ]; then
      out="${out}${out:+, }${id} carries no hint at all"
      continue
    fi
    if ! line="$(ds_page_line_for "$1" "$label")"; then
      out="${out}${out:+, }${id} (${label}) renders nowhere on the page"
      continue
    fi
    case "$line" in
      (*"$hint"*) ;;
      (*) out="${out}${out:+, }${id} (${label}) renders without its hint" ;;
    esac
  done <<<"$2"
  printf '%s' "$out"
}

# The label a rendered row carries: two spaces, the state glyph, a space, then the
# label padded out with spaces, so cutting at the first DOUBLE space ends it.
ds_label_of() {  # <rendered row>
  local rest="${1#  }"
  rest="${rest#* }"
  printf '%s' "${rest%%  *}"
}

# THE SETTING CELL CAN BE FULL, so a label is not always followed by two spaces:
# `_doctor_env3` pads the setting to 36 columns and one environment key is exactly
# 36 characters long, which runs its label straight into its value column with a
# single space between. A label that IS a table label and one that BEGINS with a
# table label followed by a space are the same row.
ds_row_for() {  # <rendered label> <table> -> the table row that owns it
  local label="$1" row l
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    l="$(ds_field "$row" 2)"
    [ -n "$l" ] || continue
    [ "$label" = "$l" ] && { printf '%s' "$row"; return 0; }
    case "$label" in "$l "*) printf '%s' "$row"; return 0 ;; esac
  done <<<"$2"
  return 1
}

# The completeness half of the scan, factored out because the mutation arm below
# runs the very same code over a doctored doctor and has to come out non-empty.
# It asks nothing of setup, so it is cheap enough to run twice.
ds_unmapped() {  # <doctor report> <table> <routes> -> the hinted labels with no row behind them
  local line label out=""
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    label="$(ds_label_of "$line")"
    ds_row_for "$label" "$2" >/dev/null && continue
    out="${out}${out:+, }${label}"
  done <<<"$(ds_hinted_lines "$1" "$3")"
  printf '%s' "$out"
}

# Is the item on setup's roster at all — the `--list` half of the agreement.
ds_listed() {  # <home> <item>
  local id
  while IFS= read -r id; do
    [ "$id" = "$2" ] && return 0
  done <<<"$(ds_setup "$1" --list)"
  return 1
}

ds_listed_in() {  # <--list output> <item>
  local id
  while IFS= read -r id; do [ "$id" = "$2" ] && return 0; done <<<"$1"
  return 1
}

# Would setup OFFER it on this machine — the presence-check half. A narrowed run
# that found nothing to do says so in its own summary, by name; anything else
# means the step asked.
ds_pending() {  # <home> <item>
  local out
  out="$(ds_setup "$1" --only "$2")"
  case "$out" in
    *"nothing left to do for $2."*) return 1 ;;
    *) return 0 ;;
  esac
}

# EVERY ITEM THIS MACHINE WOULD BE OFFERED, ASKED ONCE. `ds_pending` starts a whole
# setup run per item, which is the right instrument for the handful of rows DS.2
# drives — that arm is about setup's own narrowed behaviour — and the wrong one for
# a walk over the roster: thirty script starts for one fact, on the suite the whole
# fleet waits behind. setup's `_setup_item_pending` IS `bionic_check_item_pending`,
# so this asks setup's own predicate in one process. DS.2c pairs the two below, so
# the cheap oracle is bound to the expensive one rather than trusted.
ds_pending_items() {  # <home> -> the items that fire on it, one per line
  HOME="$1" BIONIC_CLAUDE_HOME="$1/.claude" BIONIC_PLUGIN_ROOT="$DS_PAYLOAD" BIONIC_ROOT="$1/project" \
    bash -c '. "$1" >/dev/null 2>&1 || exit 1
             bionic_check_items | while IFS= read -r i; do
               [ -n "$i" ] || continue
               bionic_check_item_pending "$i" && printf "%s\n" "$i"
             done' _ "$DS_CHECKS_LIB" 2>/dev/null
}

# ── DS.1 the field state, and both parties' answers to it ────────────────────
DS_HOME="$DS_DIR/full"
ds_plant "$DS_HOME" yes yes
DS_REPORT="$(ds_doctor "$DS_HOME")"
DS_TABLE="$(ds_rows "$DS_HOME")"
DS_LIST="$(ds_setup "$DS_HOME" --list)"
DS_ROUTES="$(while IFS= read -r ds_r; do [ -n "$ds_r" ] && ds_field "$ds_r" 6 && echo; done <<<"$DS_TABLE" | sort -u | grep -v '^$')"
DS_HINTED="$(ds_hinted_lines "$DS_REPORT" "$DS_ROUTES")"
DS_LABELS="$(while IFS= read -r ds_l; do [ -n "$ds_l" ] && ds_label_of "$ds_l" && echo; done <<<"$DS_HINTED")"

expect_true "DS.1 the check table loaded and carries rows (everything below reads it)" \
  test "$(printf '%s\n' "$DS_TABLE" | grep -c '|')" -ge 20
expect_true "DS.1 …and it names at least two distinct repair routes (setup's and the CLI's)" \
  test "$(printf '%s\n' "$DS_ROUTES" | grep -c .)" -ge 2
expect_contains "DS.1 doctor flags the leftover hook FILES on the fixture machine" \
  "legacy hook files" "$DS_LABELS"
expect_contains "DS.1 …and the installed agent copies that no longer match the payload" \
  "legacy installed agent copies" "$DS_LABELS"
expect_contains "DS.1 …and it counts the payload-named files, not the whole directory" \
  "$DS_PLANTED_HOOKS in ~/.claude/hooks" "$DS_REPORT"
expect_true "DS.1 …over a non-empty plant (the count is not zero over zero)" \
  test "${DS_PLANTED_HOOKS:-0}" -ge 10
# RE-POINTED (wave-27 T11): was a literal "6/6", which a seventh role turned red for no defect.
# The fixture plants one stale copy per payload role file, so the expected figure is that plant.
DS_ROLE_N="$(for ds_f in "$DS_PAYLOAD"/agents/*.md; do [ -f "$ds_f" ] && echo x; done | grep -c x)"
expect_true "DS.1 …over a non-empty role plant" test "${DS_ROLE_N:-0}" -ge 1
expect_contains "DS.1 …and every planted role file as drifted" \
  "${DS_ROLE_N}/${DS_ROLE_N} differ" "$DS_REPORT"

# ── DS.2a THE FIRST WAY: every row that fires renders, with its hint ─────────
#
# THE DIRECTION THE OTHER LEGS CANNOT SEE. DS.2 below starts from doctor's page
# and asks whether what it found is in the table; that is `render ⊆ table`, and
# it says nothing about a row the page never printed. This is the other
# containment — every labelled row whose detector fires on this machine has to
# appear SOMEWHERE on doctor's page, carrying the hint its row names — and it is
# the leg the design's first way asks for (plan AC-1).
#
# TWO DEFECTS IT CATCHES THAT NOTHING ELSE DID. A row whose hint went missing
# (a mistyped id resolves to nothing, and `bionic_check_hint`'s non-zero is
# discarded by every call site) used to vanish from the route-keyed scan and
# leave a ✗ row with no cure — the reader-facing half of the field defect. And a
# labelled row added to the table with no call site in doctor.sh renders nowhere
# at all: setup's roster derives from the rows, doctor's page does not, and until
# this leg nothing said so. Both are planted and watched red at DS.9 and DS.10.
DS_FIRED="$(ds_fired_rows "$DS_HOME")"
DS_UNRENDERED="$(ds_unrendered "$DS_REPORT" "$DS_FIRED")"
expect_true "DS.2a the table names labelled rows that fire on this fixture (the rows under it are not vacuous)" \
  test "$(printf '%s\n' "$DS_FIRED" | grep -c '|')" -ge 6
expect_eq "DS.2a every labelled row that fires renders on doctor's page, with its hint" \
  "" "$DS_UNRENDERED"
# THE PROJECT-SCOPED ROW IS AMONG THEM (wave-23 D5, AC-3.4): `ds_plant` planted both
# of its facts, so the walk above exercised it rather than passing over it.
expect_contains "DS.2a …and the auto-memory row is one of the rows that fired" \
  "auto-memory|" "$DS_FIRED"
# The empty-route half said on its own, so a table that lost a hint fails here
# even if the row still renders: an empty hint matches every line ever printed,
# which is how a vacuous scan looks from the inside (review A-2, A-5).
expect_eq "DS.2a …and no row in the whole table carries an empty hint" "" \
  "$(while IFS='|' read -r ds_r; do
       [ -n "$ds_r" ] || continue
       [ -n "$(ds_field "$ds_r" 6)" ] || printf '%s ' "$(ds_field "$ds_r" 1)"
     done <<<"$DS_TABLE")"
# THE ENVIRONMENT ROW'S SECOND FIRING STATE, named (review B-1). The fixture
# writes one key wrong and leaves two absent, so this row is asserted in the
# state that used to render ✓ with no cure.
expect_contains "DS.2a the fixture really does carry an environment name written to the wrong value" \
  "env:BASH_MAX_TIMEOUT_MS" "$DS_FIRED"
expect_contains "DS.2a …and doctor's page says so rather than ticking it" \
  "not the value bionic sets" "$(ds_page_line_for "$DS_REPORT" "BASH_MAX_TIMEOUT_MS")"

# ── DS.2 THE SECOND WAY: everything doctor renders is in the table ───────────
#
# Every hinted row in either machine-state table must resolve to a row of the
# check table, and — where that row is setup's — the item it names must be on the
# roster and must fire on the same machine doctor just read. A row that reaches
# here without a table row is the defect arriving tomorrow: a hint added on
# doctor's side with nothing behind it.
DS_UNMAPPED="$(ds_unmapped "$DS_REPORT" "$DS_TABLE" "$DS_ROUTES")"
DS_UNLISTED=""; DS_UNPENDING=""; DS_MISPARTY=""; DS_SEEN=0
while IFS= read -r ds_line; do
  [ -n "$ds_line" ] || continue
  DS_SEEN=$((DS_SEEN + 1))
  ds_label="$(ds_label_of "$ds_line")"
  ds_row="$(ds_row_for "$ds_label" "$DS_TABLE")" || continue
  ds_party="$(ds_field "$ds_row" 4)"
  ds_item="$(ds_field "$ds_row" 5)"
  ds_hint="$(ds_field "$ds_row" 6)"
  case "$ds_line" in
    *"$ds_hint"*) ;;
    *) DS_MISPARTY="${DS_MISPARTY}${DS_MISPARTY:+, }${ds_label} renders a route its row does not name" ;;
  esac
  if [ "$ds_party" = "setup" ]; then
    [ -n "$ds_item" ] \
      || DS_MISPARTY="${DS_MISPARTY}${DS_MISPARTY:+, }${ds_label} is setup's with no item"
    ds_listed_in "$DS_LIST" "$ds_item" \
      || DS_UNLISTED="${DS_UNLISTED}${DS_UNLISTED:+, }${ds_label} → ${ds_item}"
    ds_pending "$DS_HOME" "$ds_item" \
      || DS_UNPENDING="${DS_UNPENDING}${DS_UNPENDING:+, }${ds_label} → ${ds_item}"
  else
    [ -z "$ds_item" ] \
      || DS_MISPARTY="${DS_MISPARTY}${DS_MISPARTY:+, }${ds_label} is ${ds_party}'s and still names item ${ds_item}"
    case "$ds_line" in
      *"/bionic:setup"*) DS_MISPARTY="${DS_MISPARTY}${DS_MISPARTY:+, }${ds_label} is ${ds_party}'s and sends the reader to setup" ;;
    esac
  fi
done <<<"$DS_HINTED"

# The anti-vacuity control: an extractor that returned nothing would pass every
# row below without asking either script anything.
expect_true "DS.2 the scan found hinted rows to check (the rows under it are not vacuous)" \
  test "$DS_SEEN" -ge 8
expect_eq "DS.2 every hinted row doctor renders is a row of the check table" "" "$DS_UNMAPPED"
expect_eq "DS.2 …and every setup-party row's item is on setup's --list" "" "$DS_UNLISTED"
expect_eq "DS.2 …and every one of those items fires on the machine doctor read" "" "$DS_UNPENDING"
expect_eq "DS.2 …and every row states the party its table row names" "" "$DS_MISPARTY"

# ── DS.2b THE THIRD WAY: setup's roster IS the table's item column ───────────
#
# Set against set, not count against count. A roster that gained an item the table
# has never heard of is a repair nothing diagnoses; a table item missing from the
# roster is a hint pointing at a name setup would refuse.
DS_TABLE_ITEMS="$(while IFS= read -r ds_r; do [ -n "$ds_r" ] && ds_field "$ds_r" 5 && echo; done <<<"$DS_TABLE" | grep -v '^$' | sort -u)"
DS_LIST_ITEMS="$(printf '%s\n' "$DS_LIST" | grep -v '^$' | sort -u)"
expect_true "DS.2b setup's --list is not empty (the two rows under it are not vacuous)" \
  test "$(printf '%s\n' "$DS_LIST_ITEMS" | grep -c .)" -ge 10
expect_eq "DS.2b every item on setup's --list is an item the check table names" \
  "" "$(comm -23 <(printf '%s\n' "$DS_LIST_ITEMS") <(printf '%s\n' "$DS_TABLE_ITEMS") | tr '\n' ' ' | sed 's/ *$//')"
expect_eq "DS.2b …and every item the check table names is on setup's --list" \
  "" "$(comm -13 <(printf '%s\n' "$DS_LIST_ITEMS") <(printf '%s\n' "$DS_TABLE_ITEMS") | tr '\n' ' ' | sed 's/ *$//')"

# ── DS.2c THE FOURTH WAY: the same state, both sides ─────────────────────────
#
# The two parties agree about the ROSTER above; this is whether they agree about
# THIS MACHINE. Every item setup would offer, whose rows doctor renders a label
# for, must be flagged by doctor on the same fixture — that is the field defect in
# its pure form, and it is asked at the ITEM level because several rows can share
# one item (the three environment names are one step).
DS_CLEAN_EARLY="$DS_DIR/clean-early"
ds_plant "$DS_CLEAN_EARLY" no no
DS_PENDING_ITEMS="$(ds_pending_items "$DS_HOME")"

# THE WALK ITSELF, NAMED — DS.12 below runs its reverse (`ds_loud_items`) over a
# doctored doctor and has to come out non-empty. Every item setup would offer,
# whose table rows carry a label, must have one of those labels on the hinted
# lines of doctor's page; what comes back is the items that went unsaid, and the
# count of items the walk actually reached is left in `DS_STATE_SEEN` so a caller
# can prove it was not vacuous.
# THE COUNT COMES BACK WITH THE ANSWER, on one line, because a command
# substitution is a subshell and a global set inside one never reaches the
# caller — which is how the first draft of this helper turned the non-vacuity
# guard below into an unbound-variable error. No id and no label carries a `|`;
# the table's own record separator is that character, so one could not.
ds_silent_items() {  # <pending items> <page labels> <table> -> "<items reached>|<items doctor never said>"
  local pending="$1" labels="$2" table="$3" silent="" item labs hit r seen=0
  while IFS= read -r item; do
    [ -n "$item" ] || continue
    labs="$(while IFS= read -r r; do
        [ -n "$r" ] || continue
        [ "$(ds_field "$r" 5)" = "$item" ] || continue
        ds_field "$r" 2 && echo
      done <<<"$table" | grep -v '^$')"
    [ -n "$labs" ] || continue
    ds_listed_in "$pending" "$item" || continue
    seen=$((seen + 1))
    hit=""
    while IFS= read -r ds_l; do
      [ -n "$ds_l" ] || continue
      case "$labels" in *"$ds_l"*) hit=1; break ;; esac
    done <<<"$labs"
    [ -n "$hit" ] || silent="${silent}${silent:+, }${item} (${labs//$'\n'/, })"
  done <<<"$(while IFS= read -r r; do [ -n "$r" ] && ds_field "$r" 5 && echo; done <<<"$table" | grep -v '^$' | sort -u)"
  printf '%s|%s' "$seen" "$silent"
}

DS_2C="$(ds_silent_items "$DS_PENDING_ITEMS" "$DS_LABELS" "$DS_TABLE")"
DS_STATE_SEEN="${DS_2C%%|*}"; DS_SILENT="${DS_2C#*|}"

expect_true "DS.2c the fixture leaves setup work to do on labelled rows (the row under it is not vacuous)" \
  test "$DS_STATE_SEEN" -ge 4
# THE CHEAP ORACLE, BOUND TO THE EXPENSIVE ONE. One item both ways: the one-process
# predicate says it fires, and a real `--only` run of setup on the same fixture
# agrees. Without this pair the walk above would be trusting a reading nothing had
# checked against the script it is a claim about.
expect_true "DS.2c the one-process predicate names an item setup's own narrowed run agrees on" \
  ds_listed_in "$DS_PENDING_ITEMS" legacy-hook-files
expect_true "DS.2c …and that run really does have something to do for it" \
  ds_pending "$DS_HOME" legacy-hook-files
# The other direction on the clean fixture, so the pair is a measurement: with no
# leftovers the same item is absent from the predicate's answer AND from setup's.
expect_false "DS.2c …while on a machine with no leftovers the predicate does not name it" \
  ds_listed_in "$(ds_pending_items "$DS_CLEAN_EARLY")" legacy-hook-files
expect_eq "DS.2c every item setup would offer is flagged by doctor on the same machine" "" "$DS_SILENT"

# ── DS.2d the core row: the party that is NOT setup, on a real absence ───────
DS_CORE_ROW="$(ds_section "$DS_REPORT" "THIRD PARTY" | grep -E '^  . +superpowers ' | head -1)"
expect_true "DS.2d doctor renders a THIRD PARTY row for the absent core dependency (the two below are not vacuous)" \
  test -n "$DS_CORE_ROW"
expect_contains "DS.2d …and the row names the route its table row carries, not setup's" \
  "$(ds_field "$(ds_row_for superpowers "$DS_TABLE")" 6)" "$DS_CORE_ROW"
expect_absent "DS.2d …and never /bionic:setup, which has no item that installs a core dependency" \
  "/bionic:setup" "$DS_CORE_ROW"
# The paired positive on the SAME fixture, so the row above is a measurement and not a
# constant: `agent-skills` is present in the planted registry and earns no hint at all.
DS_OK_ROW="$(ds_section "$DS_REPORT" "THIRD PARTY" | grep -E '^  . +agent-skills ' | head -1)"
expect_true "DS.2d …and that dependency has a row at all (the row below is not vacuous)" \
  test -n "$DS_OK_ROW"
expect_absent "DS.2d …while the core dependency the registry DOES carry earns no hint" \
  "→" "$DS_OK_ROW"

# ── DS.2e the two items that had no doctor surface at all before 1.5.1 ───────
#
# `legacy-permission-block` and `permission-mode` were on setup's roster and
# nowhere in doctor: the only mention of either in doctor.sh was a comment naming
# a mutation doctor must never call (step-0 map §B.4). A repair with no diagnosis
# is a half pair, and D-2 closes it — both are rows now, and both render.
expect_true "DS.2e the check table carries a labelled row for the retired permission block" \
  test -n "$(ds_field "$(ds_row_for 'legacy permission block' "$DS_TABLE")" 1)"
expect_true "DS.2e …and one for the default permission mode" \
  test -n "$(ds_field "$(ds_row_for 'default permission mode' "$DS_TABLE")" 1)"
DS_PM_RUN="$(ds_setup "$DS_HOME" --only permission-mode)"
expect_contains "DS.2e …and the narrowed run names the mode it would set" \
  "permission mode" "$DS_PM_RUN"
expect_absent "DS.2e …and setup does not call it an unknown name" \
  "there is nothing called permission-mode" "$DS_PM_RUN"

# ── DS.3 the restored pin: hook files as the ONLY leftover ───────────────────
# tests/doctor.test.sh Group 14 pinned this from the other side — a machine whose only
# leftover is hook files, whose setup run says "nothing to do" — and was deleted at 8582861
# with nothing to replace it (doctor.sh's own comment says so). This is that pin, put back on
# the side that can go red: the narrowed run must have something to do.
DS_HOOKS_ONLY="$DS_DIR/hooks-only"
ds_plant "$DS_HOOKS_ONLY" yes no
DS_HO_RUN="$(ds_setup "$DS_HOOKS_ONLY" --only legacy-hook-files)"
expect_absent "DS.3 legacy-hook-files is a name setup takes" \
  "there is nothing called" "$DS_HO_RUN"
expect_absent "DS.3 …and a hook-files-only machine does NOT read \"nothing to do\" from it" \
  "nothing left to do for legacy-hook-files." "$DS_HO_RUN"
expect_contains "DS.3 …the run names the directory it would clear" \
  ".claude/hooks" "$DS_HO_RUN"
# The other side of the same fixture: with the files gone the item has nothing to say, which
# is what makes the row above a measurement rather than a constant.
DS_CLEAN="$DS_DIR/clean"
ds_plant "$DS_CLEAN" no no
expect_contains "DS.3 …and on a machine with no leftovers it DOES read nothing to do" \
  "nothing left to do for legacy-hook-files." "$(ds_setup "$DS_CLEAN" --only legacy-hook-files)"

# ── DS.4 consented removal takes exactly what it named ───────────────────────
DS_RM="$DS_DIR/removal"
ds_plant "$DS_RM" yes yes
DS_RM_HOOKS="$(ds_setup_yes "$DS_RM" --only legacy-hook-files)"
DS_RM_AGENTS="$(ds_setup_yes "$DS_RM" --only legacy-agent-copies)"
ds_count() { local d="$1" pat="$2" n=0 f; for f in "$d"/$pat; do [ -e "$f" ] && n=$((n + 1)); done; printf '%s' "$n"; }

expect_eq "DS.4 the consented hook-files removal leaves the machine's own hook behind" \
  "1" "$(ds_count "$DS_RM/.claude/hooks" '*.sh')"
expect_true "DS.4 …and that survivor is the one the payload does not ship" \
  test -f "$DS_RM/.claude/hooks/not-bionics.sh"
expect_eq "DS.4 the consented agent-copies removal leaves the machine's own agent behind" \
  "1" "$(ds_count "$DS_RM/.claude/agents" '*.md')"
expect_true "DS.4 …and that survivor is the one the payload does not ship" \
  test -f "$DS_RM/.claude/agents/not-bionics.md"
expect_contains "DS.4 the hook-files step reports what it removed" "removed" "$DS_RM_HOOKS"
expect_contains "DS.4 the agent-copies step reports what it removed" "removed" "$DS_RM_AGENTS"

DS_AFTER="$(ds_doctor "$DS_RM")"
expect_absent "DS.4 …and doctor's hook-files row is gone afterwards" \
  "legacy hook files" "$(ds_section "$DS_AFTER" "ENVIRONMENT$")"
expect_absent "DS.4 …and so is the agent-copies row" \
  "legacy installed agent copies" "$(ds_section "$DS_AFTER" "ENVIRONMENT$")"

# ── DS.4b the walls name the party that can actually repair them ─────────────
#
# A wall missing from the payload is a broken install, not a setup item: setup's
# argv takes `--all`, `--only` and `--list` and there is no `repair` verb anywhere
# in it, so the line doctor printed until 1.5.1 — `run /bionic:setup — repair` —
# named a command that could not have worked. The row's party is the CLI now, and
# this is the state that proves it: a payload root with one wall hook absent.
DS_WALL_ROOT="$DS_DIR/wall-root"
rm -rf "$DS_WALL_ROOT"; mkdir -p "$DS_WALL_ROOT/hooks"
for ds_h in "$DS_PAYLOAD"/hooks/*.sh; do
  [ -f "$ds_h" ] || continue
  case "${ds_h##*/}" in bash-walls.sh) continue ;; esac
  cp "$ds_h" "$DS_WALL_ROOT/hooks/"
done
DS_WALL_REPORT="$(HOME="$DS_HOME" BIONIC_CLAUDE_HOME="$DS_HOME/.claude" \
  BIONIC_PLUGIN_ROOT="$DS_WALL_ROOT" bash "$PARTY_DOCTOR" 2>/dev/null)"
expect_true "DS.4b the sparse payload root really is missing the wall (the rows under it are not vacuous)" \
  test ! -e "$DS_WALL_ROOT/hooks/bash-walls.sh"
# THE ROW NAMES THE WALL, NOT THE FILE (T23, A-56.2). The five PreToolUse|Bash
# walls share one hook, so taking hooks/bash-walls.sh away takes all five — and
# doctor says so per wall, because "bash-walls is missing" leaves a reader to work
# out which behaviours they just lost. Two of the five are asserted here: one
# fail-closed, one advisory, so a row that only knew the first name cannot pass.
expect_contains "DS.4b doctor raises the missing wall, by the wall's own name" \
  "protect-main wall is missing from the payload" "$DS_WALL_REPORT"
expect_contains "DS.4b …and every other wall the same hook carried" \
  "background-suite-guard wall is missing from the payload" "$DS_WALL_REPORT"
expect_contains "DS.4b …and routes it to the party its table row names" \
  "$(ds_field "$(printf '%s\n' "$DS_TABLE" | grep '^wall-payload|')" 6)" "$DS_WALL_REPORT"
expect_absent "DS.4b …and never to setup's phantom repair verb" \
  "/bionic:setup — repair" "$DS_WALL_REPORT"

# ── DS.4c the wall row's DETECTOR answers what doctor's page just said ───────
#
# ONE VERDICT PER WALL (Step-6 review B-2). Until this fixit's fix-up batch,
# doctor's wall loop re-implemented "is the file readable" and "does the loader
# answer" beside the two detectors in checks.sh that ask the same two questions —
# and nothing ever invoked those detectors, so the copy the page ran and the copy
# the row named were free to drift with nothing going red. They share one
# implementation now (`bionic_check_wall_state`), and this is the arm that binds
# the sharing to an observation: the same sparse root doctor just reported on,
# asked of the row.
ds_wall_fires() {  # <payload root> <row id> -> yes | no
  HOME="$DS_HOME" BIONIC_CLAUDE_HOME="$DS_HOME/.claude" BIONIC_PLUGIN_ROOT="$1" \
    bash -c '. "$1" >/dev/null 2>&1 || exit 9
             bionic_check_fires "$2" && echo yes || echo no' _ "$DS_CHECKS_LIB" "$2" 2>/dev/null
}
ds_wall_state() {  # <payload root> <wall name> -> the row's own per-wall verdict
  HOME="$DS_HOME" BIONIC_CLAUDE_HOME="$DS_HOME/.claude" BIONIC_PLUGIN_ROOT="$1" \
    bash -c '. "$1" >/dev/null 2>&1 || exit 9
             bionic_check_wall_state "$2"' _ "$DS_CHECKS_LIB" "$2" 2>/dev/null
}
expect_eq "DS.4c the row's detector fires on the very root whose page raised the wall" \
  "yes" "$(ds_wall_fires "$DS_WALL_ROOT" wall-payload)"
expect_eq "DS.4c …and names that wall as the missing one" \
  "missing" "$(ds_wall_state "$DS_WALL_ROOT" bash-walls)"
# PAIRED: the shipped payload root, where doctor's page reports 4/4 and the row
# is quiet — so the two rows above are a measurement and not a constant.
expect_eq "DS.4c …while on the shipped payload root the same detector is quiet" \
  "no" "$(ds_wall_fires "$DS_PAYLOAD" wall-payload)"
expect_eq "DS.4c …and that wall resolves its library there" \
  "ok" "$(ds_wall_state "$DS_PAYLOAD" bash-walls)"
expect_contains "DS.4c …which is what doctor's page says about it too" \
  "walls" "$(ds_page_line_for "$DS_REPORT" "walls")"

# ── DS.5 mutation: a NEW hinted row with no table row goes red ───────────────
#
# The defect arriving tomorrow, planted. DS.2's completeness row is the one that
# must catch it, and this proves that row can fail: a label the table has never
# heard of resolves to nothing. Neither mutant below is ever the shipped file —
# both are copies under the sandbox, driven through the same `W1R_PARTY_*`
# override the four parties above use.
DS_MUT="$DS_DIR/mutant"
rm -rf "$DS_MUT"; mkdir -p "$DS_MUT"
cp -R "$DS_PAYLOAD/scripts" "$DS_MUT/scripts"
DS_INVENTED="legacy invented leftover"
expect_false "DS.5 a hinted row with no table entry resolves to no row" \
  ds_row_for "$DS_INVENTED" "$DS_TABLE"
# The paired positive: a label the table DOES carry resolves, on the same table.
expect_true "DS.5 …while a label the table carries does resolve (the row above is not vacuous)" \
  ds_row_for "legacy hook files" "$DS_TABLE"
DS_MUT_DOC="$DS_MUT/scripts/doctor.sh"
anchor insert payload/scripts/doctor.sh 'echo "RESOURCES"'
LC_ALL=C awk -v row="$DS_INVENTED" '
  $0 == "echo \"RESOURCES\"" {
    print "_doctor_env_row \"$DOCTOR_BAD\" \"" row "\" \"present\" \" \xe2\x86\x92 /bionic:setup\""
  }
  { print }' "$PARTY_DOCTOR" > "$DS_MUT_DOC"
expect_eq "DS.5 the doctored doctor differs from the shipped one by exactly the planted row" \
  "1" "$(diff "$PARTY_DOCTOR" "$DS_MUT_DOC" | grep -c '^> ')"
DS_MUT_REPORT="$( PARTY_DOCTOR="$DS_MUT_DOC"; ds_doctor "$DS_HOME" )"
expect_contains "DS.5 …and the completeness scan goes RED on it" \
  "$DS_INVENTED" "$(ds_unmapped "$DS_MUT_REPORT" "$DS_TABLE" "$DS_ROUTES")"
# And the same scan over the UNDOCTORED report is empty, which is what makes the
# row above a measurement rather than a constant.
expect_eq "DS.5 …while the shipped doctor leaves it empty" \
  "" "$(ds_unmapped "$DS_REPORT" "$DS_TABLE" "$DS_ROUTES")"

# ── DS.6 mutation: a renderer that spells the route itself goes red ─────────
#
# The regression this task exists to prevent, planted. Not the 1.4.4 defect —
# THAT one is now unreachable by the edit that used to cause it: striking out the
# `core` branch of the absent arm leaves the row reading its hint from the table
# anyway, so it still names the CLI. What can still go wrong is a renderer that
# stops asking. This copy of doctor.sh replaces the one line that reads the
# dependency's row with a literal `/bionic:setup`, which is exactly how the file
# was written before 1.5.1, and the core row goes straight back to promising a
# repair setup has no item for. DS.2's party row must go red on it.
DS_MUT_CORE="$DS_MUT/scripts/doctor-literal.sh"
anchor file payload/scripts/doctor.sh '_doctor_dep_hint="$(bionic_check_dep_hint'
LC_ALL=C awk '
  /_doctor_dep_hint="\$\(bionic_check_dep_hint/ { print "  _doctor_dep_hint=\"/bionic:setup\""; next }
  { print }' "$PARTY_DOCTOR" > "$DS_MUT_CORE"
expect_eq "DS.6 the doctored doctor differs from the shipped one by exactly the one read" \
  "1" "$(diff "$PARTY_DOCTOR" "$DS_MUT_CORE" | grep -c '^< ')"
expect_eq "DS.6 …and by exactly the one literal that replaced it" \
  "1" "$(diff "$PARTY_DOCTOR" "$DS_MUT_CORE" | grep -c '^> ')"
DS_MUT_CORE_REPORT="$( PARTY_DOCTOR="$DS_MUT_CORE"; ds_doctor "$DS_HOME" )"
DS_MUT_CORE_ROW="$(ds_section "$DS_MUT_CORE_REPORT" "THIRD PARTY" | grep -E '^  . +superpowers ' | head -1)"
expect_true "DS.6 the doctored doctor still renders the core row (the rows below are not vacuous)" \
  test -n "$DS_MUT_CORE_ROW"
expect_contains "DS.6 …and it is back on the hint that has no item behind it" \
  "/bionic:setup" "$DS_MUT_CORE_ROW"
expect_absent "DS.6 …while the shipped doctor's same row never says that" \
  "/bionic:setup" "$DS_CORE_ROW"

# The party scan, run over the doctored report exactly as DS.2 runs it over the
# shipped one: a row whose table party is not setup, sending the reader to setup.
ds_misparty() {  # <doctor report> -> the rows that state a party their row does not name
  local line label row out=""
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    label="$(ds_label_of "$line")"
    row="$(ds_row_for "$label" "$DS_TABLE")" || continue
    [ "$(ds_field "$row" 4)" = "setup" ] && continue
    case "$line" in *"/bionic:setup"*) out="${out}${out:+, }${label}" ;; esac
  done <<<"$(ds_hinted_lines "$1" "$DS_ROUTES")"
  printf '%s' "$out"
}
expect_contains "DS.6 …and the party scan goes RED on it" \
  "superpowers" "$(ds_misparty "$DS_MUT_CORE_REPORT")"
expect_eq "DS.6 …while the same scan over the shipped report is empty" \
  "" "$(ds_misparty "$DS_REPORT")"

# ── DS.7 mutation: a row deleted from the TABLE goes red on both renders ─────
#
# The direction neither old arm could reach, because until 1.5.1 there was no
# table to delete from. This is the proof that both renderers actually read it: a
# copy of lib/checks.sh with exactly one row struck out must take the item off
# setup's roster AND take the hint off doctor's row, from one edit, with neither
# script touched. If either render survived the deletion unchanged, that renderer
# is still carrying its own copy of the check — which is the whole defect.
# ITS OWN TREE, so the doctored library cannot reach the arm below it: DS.8 drives
# a setup copy out of $DS_MUT, and a setup reading a library with a row missing
# would make DS.8's set comparison about two edits instead of one.
DS_MUT7="$DS_DIR/mutant-lib"
rm -rf "$DS_MUT7"; mkdir -p "$DS_MUT7"
cp -R "$DS_PAYLOAD/scripts" "$DS_MUT7/scripts"
DS_MUT_CHECKS="$DS_MUT7/scripts/lib/checks.sh"
anchor insert payload/scripts/lib/checks.sh '  _bionic_checks_emit "legacy-hook-files" '
LC_ALL=C sed '/^  _bionic_checks_emit "legacy-hook-files" /d' "$DS_CHECKS_LIB" > "$DS_MUT_CHECKS"
expect_eq "DS.7 the doctored library differs from the shipped one by exactly the row" \
  "1" "$(diff "$DS_CHECKS_LIB" "$DS_MUT_CHECKS" | grep -c '^< ')"
expect_eq "DS.7 …and by nothing added" \
  "0" "$(diff "$DS_CHECKS_LIB" "$DS_MUT_CHECKS" | grep -c '^> ')"

# The table the doctored library builds no longer knows the row.
DS_MUT_TABLE="$( DS_CHECKS_LIB="$DS_MUT_CHECKS"; ds_rows "$DS_HOME" )"
expect_true "DS.7 the doctored table still builds (the rows below are not vacuous)" \
  test "$(printf '%s\n' "$DS_MUT_TABLE" | grep -c '|')" -ge 20
expect_false "DS.7 …and no longer carries the deleted row" \
  ds_row_for "legacy hook files" "$DS_MUT_TABLE"
expect_true "DS.7 …while the shipped table does" \
  ds_row_for "legacy hook files" "$DS_TABLE"

# THE SETUP SIDE. `setup.sh` sources the library beside it, so the copy under the
# sandbox reads the doctored one and its roster loses the item.
DS_MUT_LISTED=no
( PARTY_SETUP="$DS_MUT7/scripts/setup.sh"; ds_listed "$DS_HOME" legacy-hook-files ) && DS_MUT_LISTED=yes
expect_eq "DS.7 the doctored roster no longer carries the item" "no" "$DS_MUT_LISTED"
expect_true "DS.7 …while the shipped roster does (the row above is a measurement)" \
  ds_listed_in "$DS_LIST" legacy-hook-files

# THE DOCTOR SIDE, from the same one edit. Doctor reads the row's label and its
# hint from the table, so with the row gone the machine's leftover hook files stop
# being reported as anything a reader can act on.
DS_MUT_DOC7="$DS_MUT7/scripts/doctor.sh"
cp "$PARTY_DOCTOR" "$DS_MUT_DOC7"
DS_MUT_REPORT7="$( PARTY_DOCTOR="$DS_MUT_DOC7"; ds_doctor "$DS_HOME" )"
DS_MUT_LABELS7="$(while IFS= read -r ds_l; do [ -n "$ds_l" ] && ds_label_of "$ds_l" && echo; done \
  <<<"$(ds_hinted_lines "$DS_MUT_REPORT7" "$DS_ROUTES")")"
expect_true "DS.7 the doctored doctor still renders hinted rows (the row below is not vacuous)" \
  test "$(printf '%s\n' "$DS_MUT_LABELS7" | grep -c .)" -ge 5
expect_absent "DS.7 …but the deleted row's hint is gone from doctor's render too" \
  "legacy hook files" "$DS_MUT_LABELS7"
expect_contains "DS.7 …while the shipped doctor still carries it, from the same fixture" \
  "legacy hook files" "$DS_LABELS"

# ── DS.8 mutation: an item setup names on its own goes red ──────────────────
#
# The other side of DS.7. A roster line added by hand — the way the roster used to
# be written, before it was the table's item column — is a name /bionic:setup would
# take with nothing in the table to say what it repairs or who repairs it. DS.2b's
# set-against-set row is the one that must catch it.
DS_MUT_SETUP8="$DS_MUT/scripts/setup-invented.sh"
anchor insert payload/scripts/setup.sh '_setup_item_ids() {'
LC_ALL=C awk '
  /^_setup_item_ids\(\) \{$/ { print; print "  say \"invented-item\""; next }
  { print }' "$PARTY_SETUP" > "$DS_MUT_SETUP8"
expect_eq "DS.8 the doctored setup differs from the shipped one by exactly the planted item" \
  "1" "$(diff "$PARTY_SETUP" "$DS_MUT_SETUP8" | grep -c '^> ')"
expect_eq "DS.8 …and by nothing removed" \
  "0" "$(diff "$PARTY_SETUP" "$DS_MUT_SETUP8" | grep -c '^< ')"
DS_MUT_LIST8="$( PARTY_SETUP="$DS_MUT_SETUP8"; ds_setup "$DS_HOME" --list )"
expect_contains "DS.8 the doctored roster carries the planted item (the row below is not vacuous)" \
  "invented-item" "$DS_MUT_LIST8"
DS_MUT_ITEMS8="$(printf '%s\n' "$DS_MUT_LIST8" | grep -v '^$' | sort -u)"
expect_eq "DS.8 …and the set-against-set scan goes RED on exactly that name" \
  "invented-item" \
  "$(comm -23 <(printf '%s\n' "$DS_MUT_ITEMS8") <(printf '%s\n' "$DS_TABLE_ITEMS") | tr '\n' ' ' | sed 's/ *$//')"
expect_eq "DS.8 …while the shipped roster leaves that scan empty" \
  "" "$(comm -23 <(printf '%s\n' "$DS_LIST_ITEMS") <(printf '%s\n' "$DS_TABLE_ITEMS") | tr '\n' ' ' | sed 's/ *$//')"

# ── DS.9 mutation: a row that loses its hint goes red rather than quiet ─────
#
# THE FALSE GREEN THIS LEG WAS BUILT FOR (Step-6 review A-2). Every route doctor
# prints is `$(bionic_check_hint <id>)`, and an id that does not resolve returns
# non-zero having printed nothing — a return value all twenty-odd call sites
# discard. The row still renders, as a ✗ with no cure, which is the reader-facing
# half of the field defect this whole fixit exists to end. The route-keyed scan
# could not see it: a line with no route is filtered out before any leg reads it,
# so removing a hint made the evidence quieter instead of redder. DS.2a starts
# from the table, so it fails on exactly this.
DS_MUT9="$DS_DIR/mutant-hint"
rm -rf "$DS_MUT9"; mkdir -p "$DS_MUT9"
cp -R "$DS_PAYLOAD/scripts" "$DS_MUT9/scripts"
DS_MUT_CHECKS9="$DS_MUT9/scripts/lib/checks.sh"
anchor insert payload/scripts/lib/checks.sh '  _bionic_checks_emit "legacy-hook-files" "legacy hook files" "bionic_check_legacy_hook_files" "setup" "legacy-hook-files" "$r_setup"'
LC_ALL=C sed 's|^\(  _bionic_checks_emit "legacy-hook-files" .*\) "\$r_setup"$|\1 ""|' \
  "$DS_CHECKS_LIB" > "$DS_MUT_CHECKS9"
expect_eq "DS.9 the doctored library differs from the shipped one by exactly the one hint" \
  "1" "$(diff "$DS_CHECKS_LIB" "$DS_MUT_CHECKS9" | grep -c '^< ')"
DS_MUT_TABLE9="$( DS_CHECKS_LIB="$DS_MUT_CHECKS9"; ds_rows "$DS_HOME" )"
expect_eq "DS.9 …and the table it builds carries an empty hint for that row" "" \
  "$(ds_field "$(ds_row_for 'legacy hook files' "$DS_MUT_TABLE9")" 6)"
expect_true "DS.9 …while the shipped table's same row carries one (the row above is a measurement)" \
  test -n "$(ds_field "$(ds_row_for 'legacy hook files' "$DS_TABLE")" 6)"
# The doctored library is what doctor reads, so the row renders with no cure —
# and the fired-row walk goes red on it, naming the row.
DS_MUT_DOC9="$DS_MUT9/scripts/doctor.sh"
DS_MUT_REPORT9="$( PARTY_DOCTOR="$DS_MUT_DOC9"; ds_doctor "$DS_HOME" )"
DS_MUT_FIRED9="$( DS_CHECKS_LIB="$DS_MUT_CHECKS9"; ds_fired_rows "$DS_HOME" )"
expect_true "DS.9 the doctored doctor still renders that row (the rows below are not vacuous)" \
  test -n "$(ds_page_line_for "$DS_MUT_REPORT9" 'legacy hook files')"
expect_absent "DS.9 …with no cure on it at all" \
  "/bionic:setup" "$(ds_page_line_for "$DS_MUT_REPORT9" 'legacy hook files')"
expect_contains "DS.9 …and the fired-row walk goes RED on it" \
  "legacy-hook-files" "$(ds_unrendered "$DS_MUT_REPORT9" "$DS_MUT_FIRED9")"
expect_eq "DS.9 …while the same walk over the shipped pair is empty" \
  "" "$(ds_unrendered "$DS_REPORT" "$DS_FIRED")"

# ── DS.10 mutation: a labelled row with no doctor call site goes red ────────
#
# THE ASYMMETRY A NEWCOMER WOULD GET WRONG (Step-6 review C-1), planted. Setup's
# roster is DERIVED from the rows — add a row with an item and `--list` carries
# it — while doctor's rows each have a call site written by hand, so a labelled
# row added to the table renders in setup and nowhere in doctor. This plants
# exactly that: one more row, labelled, party `user` (so it can never reach the
# item-keyed legs at all), sharing a detector that fires on this fixture, and
# with no call site anywhere in doctor.sh.
DS_MUT10="$DS_DIR/mutant-row"
rm -rf "$DS_MUT10"; mkdir -p "$DS_MUT10"
cp -R "$DS_PAYLOAD/scripts" "$DS_MUT10/scripts"
DS_MUT_CHECKS10="$DS_MUT10/scripts/lib/checks.sh"
anchor insert payload/scripts/lib/checks.sh '  _bionic_checks_emit "statusline-npx" '
LC_ALL=C awk '
  /^  _bionic_checks_emit "statusline-npx" / {
    print "  _bionic_checks_emit \"probe-unrendered\" \"planted probe row\" \"bionic_check_legacy_hook_files\" \"user\" \"\" \"clear it by hand\""
  }
  { print }' "$DS_CHECKS_LIB" > "$DS_MUT_CHECKS10"
expect_eq "DS.10 the doctored library differs from the shipped one by exactly the planted row" \
  "1" "$(diff "$DS_CHECKS_LIB" "$DS_MUT_CHECKS10" | grep -c '^> ')"
expect_eq "DS.10 …and by nothing removed" \
  "0" "$(diff "$DS_CHECKS_LIB" "$DS_MUT_CHECKS10" | grep -c '^< ')"
DS_MUT_FIRED10="$( DS_CHECKS_LIB="$DS_MUT_CHECKS10"; ds_fired_rows "$DS_HOME" )"
expect_contains "DS.10 the planted row fires on this fixture (the rows below are not vacuous)" \
  "probe-unrendered" "$DS_MUT_FIRED10"
DS_MUT_DOC10="$DS_MUT10/scripts/doctor.sh"
DS_MUT_REPORT10="$( PARTY_DOCTOR="$DS_MUT_DOC10"; ds_doctor "$DS_HOME" )"
expect_absent "DS.10 …and doctor renders it nowhere, because no call site names it" \
  "planted probe row" "$DS_MUT_REPORT10"
expect_contains "DS.10 …so the page-wide walk goes RED on it, by name" \
  "probe-unrendered" "$(ds_unrendered "$DS_MUT_REPORT10" "$DS_MUT_FIRED10")"
# PAIRED: the same doctored library's SETUP side is untouched, which is the
# asymmetry itself — a party `user` row adds no item, and a labelled row lands on
# doctor's page only if someone wrote the call site.
expect_absent "DS.10 …while the roster gains nothing from it" \
  "probe-unrendered" "$( PARTY_SETUP="$DS_MUT10/scripts/setup.sh"; ds_setup "$DS_HOME" --list )"

# ── DS.10b mutation: the auto-memory row loses its doctor call site ──────────
#
# DS.10 plants a NEW row with no call site; this takes the call site away from the
# real one (wave-23 D5, AC-3.4). The row is labelled, party `user`, no item, so
# setup never carries it, and the only thing putting it on the page is the
# hand-written `_run_add` in doctor's project section. A copy of doctor.sh with
# those lines deleted must take the fired-row walk red, by name.
DS_MUT10B="$DS_DIR/mutant-am"
rm -rf "$DS_MUT10B"; mkdir -p "$DS_MUT10B"
cp -R "$DS_PAYLOAD/scripts" "$DS_MUT10B/scripts"
DS_MUT_DOC10B="$DS_MUT10B/scripts/doctor-no-am-row.sh"
anchor file payload/scripts/doctor.sh '"$DOCTOR_BAD" "$(bionic_check_label auto-memory)" "$(bionic_check_hint auto-memory)"'
anchor file payload/scripts/doctor.sh '"$(bionic_check_label auto-memory)" "project settings unreadable (jq missing, or a file does not parse)"'
anchor file payload/scripts/doctor.sh '"$DOCTOR_OK" "$(bionic_check_label auto-memory)" "no override in project settings, no memory files under its slug"'
LC_ALL=C awk 'index($0, "\"$DOCTOR_BAD\" \"$(bionic_check_label auto-memory)\" \"$(bionic_check_hint auto-memory)\"") || index($0, "\"$(bionic_check_label auto-memory)\" \"project settings unreadable (jq missing, or a file does not parse)\"") || index($0, "\"$DOCTOR_OK\" \"$(bionic_check_label auto-memory)\" \"no override in project settings, no memory files under its slug\"") { next } { print }' \
  "$PARTY_DOCTOR" > "$DS_MUT_DOC10B"
expect_eq "DS.10b the doctored doctor gained nothing" \
  "0" "$(diff "$PARTY_DOCTOR" "$DS_MUT_DOC10B" | grep -c '^> ')"
DS_MUT_REPORT10B="$( PARTY_DOCTOR="$DS_MUT_DOC10B"; ds_doctor "$DS_HOME" )"
expect_contains "DS.10b …so the page-wide walk goes RED on it, by name" \
  "auto-memory" "$(ds_unrendered "$DS_MUT_REPORT10B" "$DS_FIRED")"

# ── DS.11 mutation: a renderer that keeps its OWN firing rule goes red ──────
#
# THE SECOND OWNER OF "DOES THIS CHECK FIRE", planted (Step-6 review B-1). Until
# the fix-up batch doctor's environment loop asked its own question — does
# `env_get` fail, i.e. is the name absent from settings.json — while the row's
# detector asks whether the configured value IS the value bionic sets. The two
# answers differ on exactly one machine, the one this fixture now plants: a name
# written to something else. There doctor printed ✓ with no cure while setup went
# on offering to rewrite it, which is the 2026-09-05 field defect inverted. This
# copy of doctor.sh puts that rule back, in one line, and the fired-row walk must
# go red on the name the fixture wrote wrong.
DS_MUT11="$DS_DIR/mutant-env"
rm -rf "$DS_MUT11"; mkdir -p "$DS_MUT11"
cp -R "$DS_PAYLOAD/scripts" "$DS_MUT11/scripts"
DS_MUT_DOC11="$DS_MUT11/scripts/doctor-own-env-rule.sh"
anchor file payload/scripts/doctor.sh 'if bionic_check_fires "env:${_env_key}"; then _env_fires=yes; else _env_fires=no; fi'
LC_ALL=C awk '
  /if bionic_check_fires "env:\$\{_env_key\}"; then _env_fires=yes; else _env_fires=no; fi/ {
    print "  if [ -z \"$_env_configured\" ]; then _env_fires=yes; else _env_fires=no; fi"; next }
  { print }' "$PARTY_DOCTOR" > "$DS_MUT_DOC11"
expect_eq "DS.11 the doctored doctor differs from the shipped one by exactly the one read" \
  "1" "$(diff "$PARTY_DOCTOR" "$DS_MUT_DOC11" | grep -c '^< ')"
expect_eq "DS.11 …and by exactly the one rule that replaced it" \
  "1" "$(diff "$PARTY_DOCTOR" "$DS_MUT_DOC11" | grep -c '^> ')"
DS_MUT_REPORT11="$( PARTY_DOCTOR="$DS_MUT_DOC11"; ds_doctor "$DS_HOME" )"
DS_MUT_ENV_ROW11="$(ds_page_line_for "$DS_MUT_REPORT11" "BASH_MAX_TIMEOUT_MS")"
expect_true "DS.11 the doctored doctor still renders the environment row (the rows below are not vacuous)" \
  test -n "$DS_MUT_ENV_ROW11"
expect_absent "DS.11 …and it is back to a tick with no cure on it" \
  "/bionic:setup" "$DS_MUT_ENV_ROW11"
expect_contains "DS.11 …while setup, reading the same machine, still offers the item" \
  "environment" "$DS_PENDING_ITEMS"
expect_contains "DS.11 …so the fired-row walk goes RED on that name" \
  "env:BASH_MAX_TIMEOUT_MS" "$(ds_unrendered "$DS_MUT_REPORT11" "$DS_FIRED")"
expect_eq "DS.11 …while the shipped doctor leaves the same walk empty" \
  "" "$(ds_unrendered "$DS_REPORT" "$DS_FIRED")"

# ── DS.12 mutation: the LEFTOVER rows have one owner too ────────────────────
#
# THE SAME SECOND OWNER, ON THE FIVE ROWS B-1 DID NOT COVER (Step-6 recheck part
# 4, ruling R-2). doctor decided `legacy-hook-files`, `legacy-agent-copies`,
# `legacy-alias`, `legacy-hooks` and `legacy-skill-copy` twice each — once for the
# fix line, once for the row — by re-applying the table's rule to the raw fact.
# Four of those five pairs agreed on every state a fixture can reach; the fifth
# did not, and that is what this arm plants.
#
# THE STATE (wave-27 T75, A-orch-173). `bionic_check_legacy_alias` fires only on bionic's
# whole block, free to go; `detect_zshrc_legacy_block` knows only the markers. A machine
# carrying a marked block whose body the user changed is one the table says has nothing to
# do and the raw fact calls present: a doctor that re-derived the row from the raw fact
# would send the user to a setup step that removes nothing, the field defect's other
# direction. `ds_plant`'s fourth argument `changed` writes exactly that machine and
# nothing else.
#
# WHY ITS OWN HOME. Adding an rc file to the shared fixture would change what
# `claude-proxy` answers there too (an rc that exists with no bionic block is a
# different state from no rc at all), so the drift is planted where it is the only
# thing that moved.
DS_ALIAS_HOME="$DS_DIR/alias-changed"
ds_plant "$DS_ALIAS_HOME" no no changed
expect_true "DS.12 the fixture carries bionic's alias markers (the rows below are not vacuous)" \
  grep -q 'bionic:start' "$DS_ALIAS_HOME/.zshrc"
expect_true "DS.12 …around a body the user changed, which is what makes the two rules disagree" \
  grep -q '^export MINE=1$' "$DS_ALIAS_HOME/.zshrc"

DS_ALIAS_TABLE="$(ds_rows "$DS_ALIAS_HOME")"
DS_ALIAS_PENDING="$(ds_pending_items "$DS_ALIAS_HOME")"
# The row's rendered LABEL, read out of the table by id rather than spelled here —
# a literal would go stale the day the column's wording changes, which is the
# class of pin §DS exists to replace.
DS_ALIAS_LABEL="$(while IFS= read -r ds_r; do
    [ -n "$ds_r" ] || continue
    [ "$(ds_field "$ds_r" 1)" = "legacy-alias" ] || continue
    ds_field "$ds_r" 2
  done <<<"$DS_ALIAS_TABLE")"
expect_true "DS.12 the table names a label for the row under test" test -n "$DS_ALIAS_LABEL"
expect_false "DS.12 setup offers no removal on this machine" \
  ds_listed_in "$DS_ALIAS_PENDING" legacy-alias
# setup's own narrowed run names the changed block for the user's hand (so it does not
# say "nothing left to do") and asks nothing: no removal is on offer.
DS_ALIAS_ONLY="$(ds_setup "$DS_ALIAS_HOME" --only legacy-alias)"
expect_contains "DS.12 …and setup's own narrowed run names the block for the user's hand" \
  "changed since bionic wrote it" "$DS_ALIAS_ONLY"
expect_absent "DS.12 …and asks nothing" "[y/N]" "$DS_ALIAS_ONLY"

ds_alias_labels() {  # <report> -> the labels on that page's hinted lines
  local rep="$1" routes hinted
  routes="$(while IFS= read -r r; do [ -n "$r" ] && ds_field "$r" 6 && echo; done <<<"$DS_ALIAS_TABLE" | sort -u | grep -v '^$')"
  hinted="$(ds_hinted_lines "$rep" "$routes")"
  while IFS= read -r l; do [ -n "$l" ] && ds_label_of "$l" && echo; done <<<"$hinted"
}

# THE REVERSE WALK: every item whose label doctor routes to setup must be one setup
# would offer on the same machine. `<items routed>|<items routed that setup would not
# offer>`, the count first for the same reason `ds_silent_items` gives it.
ds_loud_items() {  # <pending items> <page labels> <table>
  local pending="$1" labels="$2" table="$3" loud="" item labs hit r seen=0
  while IFS= read -r item; do
    [ -n "$item" ] || continue
    labs="$(while IFS= read -r r; do
        [ -n "$r" ] || continue
        [ "$(ds_field "$r" 5)" = "$item" ] || continue
        ds_field "$r" 2 && echo
      done <<<"$table" | grep -v '^$')"
    [ -n "$labs" ] || continue
    hit=""
    while IFS= read -r ds_l; do
      [ -n "$ds_l" ] || continue
      case "$labels" in *"$ds_l"*) hit=1; break ;; esac
    done <<<"$labs"
    [ -n "$hit" ] || continue
    seen=$((seen + 1))
    ds_listed_in "$pending" "$item" || loud="${loud}${loud:+, }${item}"
  done <<<"$(while IFS= read -r r; do [ -n "$r" ] && ds_field "$r" 5 && echo; done <<<"$table" | grep -v '^$' | sort -u)"
  printf '%s|%s' "$seen" "$loud"
}

DS_ALIAS_REPORT="$(ds_doctor "$DS_ALIAS_HOME")"
DS_ALIAS_LABELS="$(ds_alias_labels "$DS_ALIAS_REPORT")"
expect_absent "DS.12 the shipped doctor routes no one to setup for it, because it asks the table" \
  "$DS_ALIAS_LABEL" "$DS_ALIAS_LABELS"
expect_contains "DS.12 …and names the changed block for the user's hand instead" \
  "changed since written" "$DS_ALIAS_REPORT"
DS_ALIAS_LOUD="$(ds_loud_items "$DS_ALIAS_PENDING" "$DS_ALIAS_LABELS" "$DS_ALIAS_TABLE")"
expect_true "DS.12 …and the reverse walk reaches this page's routed items at all" \
  test "${DS_ALIAS_LOUD%%|*}" -ge 1
expect_absent "DS.12 …so it names nothing setup would not offer, on the shipped doctor" \
  "legacy-alias" "${DS_ALIAS_LOUD#*|}"

# THE MUTANT: one line, doctor's own pre-1.5.1 rule put back where the table's
# answer now goes. Everything else on the page is the shipped renderer.
DS_MUT12="$DS_DIR/mutant-alias"
rm -rf "$DS_MUT12"; mkdir -p "$DS_MUT12"
cp -R "$DS_PAYLOAD/scripts" "$DS_MUT12/scripts"
DS_MUT_DOC12="$DS_MUT12/scripts/doctor-own-alias-rule.sh"
anchor insert payload/scripts/doctor.sh 'LEGACY_ALIAS_FIRES=no; bionic_check_fires legacy-alias'
LC_ALL=C awk -v repl='LEGACY_ALIAS_FIRES=no; case "$(detect_zshrc_legacy_block)" in *present=yes) LEGACY_ALIAS_FIRES=yes ;; esac' '
  /^LEGACY_ALIAS_FIRES=no; bionic_check_fires legacy-alias/ { print repl; next }
  { print }' "$PARTY_DOCTOR" > "$DS_MUT_DOC12"
expect_eq "DS.12 the doctored doctor differs from the shipped one by exactly the one read" \
  "1" "$(diff "$PARTY_DOCTOR" "$DS_MUT_DOC12" | grep -c '^< ')"
expect_eq "DS.12 …and by exactly the one rule that replaced it" \
  "1" "$(diff "$PARTY_DOCTOR" "$DS_MUT_DOC12" | grep -c '^> ')"

DS_MUT_REPORT12="$( PARTY_DOCTOR="$DS_MUT_DOC12"; ds_doctor "$DS_ALIAS_HOME" )"
expect_contains "DS.12 the doctored doctor still renders a page (the rows below are not vacuous)" \
  "ENVIRONMENT" "$DS_MUT_REPORT12"
expect_contains "DS.12 …and its own rule reads the markers alone, so the row routes to setup" \
  "$DS_ALIAS_LABEL" "$(ds_alias_labels "$DS_MUT_REPORT12")"
expect_contains "DS.12 …so the reverse walk goes RED on it, by item name" \
  "legacy-alias" "$(DS_M="$(ds_loud_items "$DS_ALIAS_PENDING" "$(ds_alias_labels "$DS_MUT_REPORT12")" "$DS_ALIAS_TABLE")"; printf '%s' "${DS_M#*|}")"


finish
