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
# The fixture world: one repository with an open run, the CONFIGURED metadata root holding
# both sessions' transcripts, and the agent "worker" planted under this session's own
# directory. The claim under test is agreement over ONE resolution, not a resolver case.

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

plant "$RPROJ/$SID_A/subagents" "aworker-7777777777777777" "worker"

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
