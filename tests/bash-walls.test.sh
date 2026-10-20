#!/bin/bash
# tests/bash-walls.test.sh — ONE PROCESS ON PreToolUse|Bash
# (epic-23 wave-11-lean-spine, REQ-1f (v), AC-1f.5; ADR-004; T23 rulings R3–R7).
#
# WHAT THIS FILE OWNS: the COMPOSITION. Five walls fired on every Bash tool call —
# protect-main, protect-database, the canonical-sdlc evidence gate, farm-out-reminder and
# background-suite-guard — each as its own process, each paying the loader and the preamble,
# and NO RULE said how five verdicts combine when more than one had something to say. The
# platform collected whichever arrived. This file drives the one process that replaced them
# and asserts the rule:
#
#     any block is a block · all reasons print · blocks before advisories
#
# EACH WALL'S OWN VERDICT IS *NOT* RE-TESTED HERE. Those five suites keep their own files
# and drive this same process through their own seam — tests/protect-main.test.sh,
# tests/protect-database.test.sh, tests/canonical-sdlc-evidence-gate.test.sh,
# tests/farm-out-reminder.test.sh and tests/background-suite-guard.test.sh. What is here is
# only what no per-wall suite can see: two walls speaking on one payload, two CHANNELS
# speaking on one payload, the manifest order, the partition that used to be a wrapper, and
# the fail-closed arm when the library is gone.
#
# THE TWO CHANNELS ARE THE POINT (T23 ruling R3). Four of the five refuse by exit 2 with the
# text on stderr; farm-out-reminder alone answers on stdout as JSON — `permissionDecision:
# deny` for a block and `hookSpecificOutput.additionalContext` for a nudge. Before the merge
# those were different processes and the harness reconciled them. Now they share one stdout,
# and the fold has to keep both wires legible: at most one JSON document, the refusal owning
# it when there is one.
#
# HERMETIC. Every payload is crafted and piped in; repos are throwaway git inits under a
# mktemp'd sandbox; HOME, CLAUDE_PROJECT_DIR and BIONIC_PLUGINS_DIR are pointed inside it so
# the loader cannot reach this machine's installed plugin and the audit stream cannot reach
# this machine's real one.
#
# FIXTURE FIDELITY (declared, per .claude/rules/test-harness.md, "Fixture fidelity"):
#   * PreToolUse|Bash payload envelope — the shape tests/cmd-class.test.sh pins, plus the
#     top-level `agent_id` measured for an agent context in
#     record/session-20260815-landing-supervision/t1-probe-report.md §3 (CLI 2.1.233).
#   * the engagement marker, the roster file name, the plan's `## SDLC State` block and its
#     frontmatter — each copied from the suite that owns it.
#   * session ids, agent ids, commands and plan text — SYNTHESIZED.
#
# Usage: bash tests/bash-walls.test.sh

# SPLIT AT WAVE-30 T9 (D8): the §EG-DERIVE sections carry wall-clock bounds, so they moved to
# tests/bash-walls-egd.test.sh (it ran solo until wave-35 T2 retired the marker, D11). The helpers both suites read live in
# tests/bash-walls.prelude.sh, sourced below before the framework.
set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
HOOK="${BIONIC_BASH_WALLS_UNDER_TEST:-${BIONIC_HOOKS_DIR}/bash-walls.sh}"

# THE PRELUDE IS SOURCED BEFORE THE FRAMEWORK, on purpose — see its header.
. "$(dirname "$0")/bash-walls.prelude.sh"
. "$(dirname "$0")/lib/assert.sh"
. "$(dirname "$0")/lib/roster-row.sh"
# The one bound-marker builder (wave-23-fixit-1810 T1), for bw_bind below.
. "$(dirname "$0")/lib/bound-marker.sh"

require_helpers mk_repo block_plan arm_roster mk_payload run_hook json_docs deny_reason \
                context_of line_of updated_timeout_of has_updated_input updated_command_of

setup_section "the repos"
R_QUIET="$(mk_repo quiet)"
R_PUSH="$(mk_repo push)"
R_TWO="$(mk_repo twoblocks)"
R_COMMIT="$(mk_repo commit)";   block_plan "$R_COMMIT"
R_CROSS="$(mk_repo crosschan)"
R_BG="$(mk_repo background)"
R_PLAIN="$(mk_repo bystander no)"
ok "seven repos built under $SANDBOX"

# ---------------------------------------------------------------------------
section "1 — five zeros: one process, one silence"

run_hook "$(mk_payload "$R_QUIET" 'ls -la')"
expect_status "1a: a command no wall objects to exits 0" 0 "$ST"
expect_empty "1b: …writing nothing to stdout" "$OUT"
expect_empty "1c: …and nothing to stderr" "$ERR"

run_hook "$(mk_payload "$R_QUIET" 'ls -la' '' omit Read)"
expect_status "1d: a non-Bash payload exits 0" 0 "$ST"
expect_empty "1e: …silently" "$OUT$ERR"

run_hook 'not json at all {'
expect_status "1f: a malformed payload exits 0" 0 "$ST"
expect_empty "1g: …silently" "$OUT$ERR"

run_hook "$(mk_payload "$R_PLAIN" 'bash tests/run.sh')"
expect_status "1h: a session that never invoked canonical-sdlc exits 0" 0 "$ST"
expect_empty "1i: …with every wall silent" "$OUT$ERR"

# ---------------------------------------------------------------------------
section "2 — the anti-vacuity control: each of the five still speaks through the one process"
#
# One payload per wall, chosen so that only that wall answers. If any row here goes quiet
# the merge dropped a verdict, and every composition assertion below would be measuring a
# process with fewer walls in it than it claims.

run_hook "$(mk_payload "$R_QUIET" 'git push origin main')"
expect_status "2a: protect-main still refuses a push to main" 2 "$ST"
expect_contains "2b: …in its own words" "main is a protected branch here" "$ERR"

# THE SCREEN AND THE PARSER MUST AGREE (wave-14 T24, security 1b). `_wall_mentions_git` is a
# cheap superset in front of `git_argv_*`: it strips backslashes and quotes and looks for the
# substring `git`, and only a MISS short-circuits. A backslash-NEWLINE is a line continuation
# — the backslash goes and a newline is left standing between `g` and `it` — so the screen
# said "provably not a git command" for a command the parser reads as a push. Both readers of
# the screen are in this one process: protect-main (here) and the evidence gate's IS_COMMIT
# (25g(n) in tests/canonical-sdlc-evidence-gate.test.sh), so one repair has to serve both.
run_hook "$(mk_payload "$R_QUIET" "$(printf 'g\\\n''it push origin main')")"
expect_status "2b1: a 'g\<newline>it push' is a push — the screen does not hide it from protect-main" 2 "$ST"
expect_contains "2b2: …refused in protect-main's own words" "main is a protected branch here" "$ERR"

run_hook "$(mk_payload "$R_QUIET" 'psql -c "DROP TABLE users"')"
expect_status "2c: protect-database still refuses a DROP" 2 "$ST"
expect_contains "2d: …in its own words" "this command DROPs a database object" "$ERR"

run_hook "$(mk_payload "$R_COMMIT" 'git commit -m "step 5"')"
expect_status "2e: the evidence gate still refuses a commit with placeholder evidence" 2 "$ST"
expect_contains "2f: …in its own words" "this step's evidence line is a placeholder" "$ERR"

run_hook "$(mk_payload "$R_QUIET" 'bash tests/run.sh')"
expect_status "2g: farm-out-reminder still denies at exit 0 — its channel, not exit 2" 0 "$ST"
expect_eq "2h: …on the deny wire" "deny" \
  "$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecision // ""' 2>/dev/null)"
expect_contains "2i: …naming the role it redirects to" "subagent_type: test-runner" "$(deny_reason)"

# `agent_type` SILENCES farm-out-reminder so this row reads ONE wall. Without it the
# same payload is a main-thread suite command by farm-out's own rule and BOTH walls
# block — which is faithful, and section 6's business rather than this one's.
arm_roster "$R_BG"
run_hook "$(mk_payload "$R_BG" 'bash tests/run.sh' "$ACTOR" true Bash test-runner)"
expect_status "2j: background-suite-guard still refuses a backgrounded suite" 2 "$ST"
expect_contains "2k: …in its own words" "a backgrounded suite's result is never read" "$ERR"

# ---------------------------------------------------------------------------
section "3 — two walls, one payload: both reasons print, in manifest order"
#
# THE CASE ADR-004 EXISTS FOR. `git push origin main` refused by protect-main and
# `DROP TABLE` refused by protect-database, on one command line. Before the merge these
# were two processes with two unreconciled verdicts and no rule; after it, one composed
# refusal carrying both reasons in the order the manifest listed the walls.

# THE DESTRUCTIVE LITERAL IS ASSEMBLED AT RUN TIME, never spelled in this file. Every
# command a run of this suite issues passes through the machine's own installed walls,
# and a fixture that spells the statement in a tool call is refused by the very wall it
# is here to drive.
DROPSQL="$(printf 'D%sP T%sLE users' 'RO' 'AB')"
run_hook "$(mk_payload "$R_TWO" "git push origin main && psql -c \"$DROPSQL\"")"
expect_status "3a: two blockers still block" 2 "$ST"
expect_contains "3b: the FIRST wall's sentence is on the user stream" \
  "bionic: push refused — main is a protected branch here (push from your own terminal)" "$ERR"
expect_contains "3c: the SECOND wall's sentence is too — not just the first" \
  "bionic: sql refused — this command DROPs a database object (run the migration yourself)" "$ERR"
expect_true "3d: …in manifest order, by line" \
  test "$(line_of 'push refused')" -lt "$(line_of 'sql refused')"
# ONE LINE PER BLOCKER, NOT ONE PER FOLD. `refuse`'s "the user sees exactly one line" is
# the rule for ONE refusal; two walls refusing one command are two refusals, and two
# lines is exactly what the two processes this replaced put on that stream. Measured
# against the originals at the base SHA — T23 report section 7.
expect_eq "3e: exactly one user line per blocker — no more, no fewer" "2" \
  "$(printf '%s\n' "$ERR" | /usr/bin/grep -c '^bionic: ')"
# …AND THE `detail` RIDES THAT WIRE NOW (ADR-030, epic-23 wave-16). Ruling D-1 spent the
# channel's one stream on the sentences alone; field 9 is `yes` for `exit2` since that
# ruling was superseded, so the composed detail follows them, bounded at twelve lines.
# WHAT 3e GUARDS IS UNCHANGED AND IS THE POINT: one SENTENCE per blocker, never two. The
# fold's extra-lines branch used to print each later blocker's line because the detail
# reached nobody; now that the detail carries that line itself, the branch stands down
# (fold.sh, A-T4.6), and 3f2 is where a return of the doubling would show.
expect_contains "3f: the exit2 channel carries the composed detail too" \
  "The destination this segment resolved to" "$ERR"
expect_eq "3f2: …with the second wall's sentence on it exactly once, not twice" "1" \
  "$(printf '%s\n' "$ERR" | /usr/bin/grep -c 'sql refused')"
expect_absent "3f3: …and none of it on stdout, which is the JSON modes' wire" \
  "The destination this segment resolved to" "$OUT"

# ---------------------------------------------------------------------------
section "4 — a block and a model-facing nudge on one payload (R7)"
#
# A push to main that ALSO draws a farm-out nudge (a `git clone` head — the chain tier-2 nudge
# this fixture used to ride is retired, wave-24 T11). protect-main refuses on stderr at
# exit 2; farm-out-reminder nudges on stdout as JSON. Two channels, one process, and
# neither may eat the other.

run_hook "$(mk_payload "$R_PUSH" 'git clone u d && git push origin main')"
expect_status "4a: the refusal decides the status" 2 "$ST"
expect_contains "4b: …and the user stream carries the push refusal" \
  "bionic: push refused — main is a protected branch here" "$ERR"
expect_eq "4c: stdout carries exactly one JSON document" "1" "$(json_docs)"
expect_contains "4d: …the nudge, on its own channel" "clone-class command on the main thread" \
  "$(context_of)"
expect_absent "4e: the nudge never leaks onto the user's stream" \
  "production-shaped work belongs in a subagent" "$ERR"

# ---------------------------------------------------------------------------
section "5 — a refused commit and a nudge: the same shape from the other gate"

run_hook "$(mk_payload "$R_COMMIT" 'git clone u d && git commit -m "step 5"')"
expect_status "5a: the gate's refusal decides the status" 2 "$ST"
expect_contains "5b: …with the gate's own words on the user stream" \
  "bionic: commit refused" "$ERR"
expect_eq "5c: stdout still carries exactly one JSON document" "1" "$(json_docs)"
expect_contains "5d: …and it is the nudge" "clone-class command" "$(context_of)"

# ---------------------------------------------------------------------------
section "6 — two channels blocking at once: the JSON wire wins, and keeps both reasons"
#
# farm-out-reminder blocks on `deny` (exit 0 + JSON) while protect-main blocks on `exit2`
# (exit 2 + stderr). refuse.sh's channel table is what settles it: `exit2` spends its one
# wire on the user line and carries no `detail` at all, so composing onto it would DISCARD
# the very reasons the fold exists to keep. The fold picks the first mode whose channel
# carries detail, which is `deny` — and every reason survives.

run_hook "$(mk_payload "$R_CROSS" 'bash tests/run.sh && git push origin main')"
expect_eq "6a: stdout carries exactly one JSON document" "1" "$(json_docs)"
expect_contains "6b: the push refusal's reason survives the cross-channel fold" \
  "main is a protected branch here" "$(deny_reason)$ERR"
expect_contains "6c: …and so does the farm-out redirect" "belongs in a subagent" \
  "$(deny_reason)$ERR"
# ONE USER LINE HERE, AND THAT IS THE RULING RATHER THAN A LOSS. `deny` carries the
# composed detail to the MODEL in full, so the second wall's own sentence is inside the
# reason above; refuse.sh's D-1 spends the user's stream on one line whenever the model
# has the rest, and T12 pinned that shape. Section 3's exit2-only fold is the case with
# nowhere else to put a second sentence, and it prints two.
expect_eq "6d: the user stream keeps one line when the model got the rest" "1" \
  "$(printf '%s\n' "$ERR" | /usr/bin/grep -c '^bionic: ')"
expect_contains "6e: …and the other wall's sentence is on the model's wire" \
  "bionic: run refused — this command belongs in a subagent" "$(deny_reason)"

# ---------------------------------------------------------------------------
section "7 — the partition that used to be a wrapper (R2)"
#
# hooks/agent-context-guard.sh wrapped background-suite-guard's registration and was the
# ONLY thing keeping its backgrounded-suite arm off the main thread: driven straight, that
# wall refuses a main-thread backgrounded suite; driven through the guard it did not. The
# guard cannot wrap the compound — it would silence the other four walls in every
# main-thread session — so its predicate is a gate on that ONE function now.

run_hook "$(mk_payload "$R_BG" 'bash tests/run.sh' '' true Bash test-runner)"
expect_status "7a: a MAIN-THREAD backgrounded suite is not this wall's business" 0 "$ST"
expect_absent "7b: …the backgrounded-suite refusal does not fire there" \
  "a backgrounded suite's result is never read" "$ERR"

R_UNARMED="$(mk_repo unarmed)"
run_hook "$(mk_payload "$R_UNARMED" 'bash tests/run.sh' "$ACTOR" true Bash test-runner)"
expect_status "7c: an agent context with NO roster is not armed" 0 "$ST"
expect_absent "7d: …and the wall stays silent" "a backgrounded suite's result" "$ERR"

# THE OTHER FOUR ARE NOT GATED BY IT. This is the failure the wrapper would have caused:
# a main-thread push must still be refused, in a session with no roster at all.
run_hook "$(mk_payload "$R_UNARMED" 'git push origin main')"
expect_status "7e: the other four walls are NOT silenced on the main thread" 2 "$ST"
expect_contains "7f: …the push is still refused with no roster and no agent context" \
  "main is a protected branch here" "$ERR"

# ---------------------------------------------------------------------------
section "8 — blocks before advisories, by offset"
#
# A rule about OUTPUT order, not run order: farm-out-reminder's instrument line is written
# while it runs, which is before the fold renders anything, and the refusal still leads the
# user's stream.

run_hook "$(mk_payload "$R_TWO" "git push origin main && psql -c \"$DROPSQL\"")"
expect_nonempty "8a: the composed refusal reached the user stream" "$(line_of '^bionic: ')"
expect_eq "8b: …as the FIRST bionic line on it" "1" \
  "$(printf '%s\n' "$ERR" | /usr/bin/grep -n '^bionic: ' | head -1 | cut -d: -f1)"

# ---------------------------------------------------------------------------
section "9 — no library: fail-closed direction and reach, unchanged (R4)"
#
# THE CLASSES DISAGREE, AND THE COMPOUND ASKS FOR ONLY WHAT THE CLOSED ONES NEED.
# protect-main and the evidence gate refuse when the library cannot load; the other three
# step aside. `BIONIC_LIB_WANT` in hooks/bash-walls.sh is therefore the two CLOSED walls'
# lists and nothing else. This section's fixture has NO library at all, so the closed arm
# is the one that fires — and protect-main's arm is armed in EVERY project on the machine
# with no `.bionic` needed, which is what makes its reach every project. The four repair
# commands are still matched as whole strings, ahead of everything, and the refusal names
# `bash-walls` — what actually refused (A-54).
#
# SECTION 10 IS THE OTHER HALF of this one: a library that is whole except for a file only
# an ADVISORY wall wants, which must NOT reach this arm.

BROKEN="$SANDBOX/broken-plugin"
mkdir -p "$BROKEN/hooks" "$SANDBOX/plugins-empty"
BROKEN_REAL="$(cd "$BROKEN" && pwd -P)"
cp "$HOOK" "$BROKEN/hooks/bash-walls.sh"
NOBIONIC="$SANDBOX/nowhere/deep"
mkdir -p "$NOBIONIC"

DRV_ST=0; DRV_ERR=""; DRV_OUT=""
drive_broken() {  # <command> <cwd>
  DRV_OUT=$(jq -n --arg s "$SID" --arg c "$2" --arg m "$1" \
      '{session_id:$s,cwd:$c,hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$m}}' \
    | env HOME="$SANDBOX/home" BIONIC_PLUGINS_DIR="$SANDBOX/plugins-empty" \
          CLAUDE_CODE_SESSION_ID="$SID" CLAUDE_PROJECT_DIR= \
          bash "$BROKEN/hooks/bash-walls.sh" 2>"$SANDBOX/.berr")
  DRV_ST=$?
  DRV_ERR=$(cat "$SANDBOX/.berr")
  return 0
}
require_helpers drive_broken

drive_broken 'git push origin main' "$NOBIONIC"
expect_status "9a: with no library the compound refuses a push" 2 "$DRV_ST"
expect_contains "9b: …in the ruled one line" "cannot load the bionic library (run /bionic:doctor)" "$DRV_ERR"

drive_broken 'ls' "$NOBIONIC"
expect_status "9c: …and refuses a command it cannot classify, in a project with no .bionic" \
  2 "$DRV_ST"

drive_broken "claude plugin update bionic@bionic" "$NOBIONIC"
expect_status "9d: the repair itself is PERMITTED, whole-string matched" 0 "$DRV_ST"
expect_empty "9e: …silently" "$DRV_ERR"

drive_broken "bash $BROKEN_REAL/scripts/doctor.sh" "$NOBIONIC"
expect_status "9f: …and so is doctor" 0 "$DRV_ST"

drive_broken "bash $BROKEN_REAL/scripts/doctor.sh; git push origin main" "$NOBIONIC"
expect_status "9g: a repair with a command chained after it is not a repair" 2 "$DRV_ST"

expect_contains "9h: …and the line names the compound, which is what refused (A-54)" \
  "bash-walls cannot load the bionic library" "$DRV_ERR"

# ---------------------------------------------------------------------------
section "10 — fail-closed is PER WALL, not per compound (A-56.1)"
#
# THE DEFECT THIS SECTION EXISTS FOR, MEASURED. Folding five hooks into one made
# `BIONIC_LIB_WANT` the UNION of five want lists, and the loader qualifies a directory
# only when it holds EVERY name on the list — so `cmd-class.sh` absent, a file only
# farm-out-reminder and background-suite-guard read, failed the WHOLE compound closed and
# refused every Bash command in every project on the machine. Before the fold that same
# damage made those two walls step aside and touched nothing else
# (tests/cmd-class.test.sh §C5). R4 puts fail-closed per WALL; this is the proof.
#
# THE TREE IS C5's OWN: a plugin-shaped directory, hooks/ beside scripts/lib/, every
# library present except the classifier. Nothing outside $SANDBOX is touched — the
# shipped library is never moved, which is the correction §C5 carries in its own header.
NOCLASS="$SANDBOX/no-classifier"
mkdir -p "$NOCLASS/hooks" "$NOCLASS/scripts/lib"
for _nc in "${BIONIC_SCRIPTS_DIR}"/payload/scripts/lib/*.sh; do
  case "$(basename "$_nc")" in cmd-class.sh) continue ;; esac
  cp "$_nc" "$NOCLASS/scripts/lib/"
done
cp "$HOOK" "$NOCLASS/hooks/bash-walls.sh"
expect_true "10a: the fixture library is whole except for the classifier" \
  test ! -e "$NOCLASS/scripts/lib/cmd-class.sh" -a -r "$NOCLASS/scripts/lib/git-argv.sh"

R_NOCLASS="$(mk_repo noclassifier)"
arm_roster "$R_NOCLASS"
NC_ST=0; NC_ERR=""; NC_OUT=""
drive_noclass() {  # <payload>
  NC_OUT=$(printf '%s' "$1" | env HOME="$FAKE_HOME" \
      BIONIC_PLUGINS_DIR="$SANDBOX/no-plugins" CLAUDE_CODE_SESSION_ID="$SID" \
      CLAUDE_PROJECT_DIR= bash "$NOCLASS/hooks/bash-walls.sh" 2>"$SANDBOX/.nerr")
  NC_ST=$?
  NC_ERR=$(cat "$SANDBOX/.nerr")
  return 0
}
require_helpers drive_noclass

# THE CLOSED WALLS ARE UNTOUCHED: a push is still refused, by its own wall and not by the
# loader — the fact is protect-main's, not "cannot load the bionic library".
drive_noclass "$(mk_payload "$R_NOCLASS" 'git push origin main')"
expect_status "10b: a push is STILL refused with the classifier absent" 2 "$NC_ST"
expect_contains "10c: …by protect-main's own fact, not by the loader arm" \
  "push refused" "$NC_ERR"
expect_absent "10d: …and nothing on this stream says the library would not load" \
  "cannot load the bionic library" "$NC_ERR"

# AND AN ORDINARY COMMAND PASSES, which is the row the union broke: before this fix `ls`
# was refused in every project on the machine.
drive_noclass "$(mk_payload "$R_NOCLASS" 'ls')"
expect_status "10e: an ordinary command PASSES, where the union refused it" 0 "$NC_ST"
expect_empty "10f: …writing nothing to stdout" "$NC_OUT"

# THE TWO ADVISORY WALLS STEP ASIDE, each naming the file, once, in the words its own hook
# used before the fold (`git show 60c528b:hooks/farm-out-reminder.sh`, loader_fail_open).
drive_noclass "$(mk_payload "$R_NOCLASS" 'bash tests/run.sh' "$ACTOR" true)"
expect_status "10g: a backgrounded suite is neither refused nor classified" 0 "$NC_ST"
expect_empty "10h: …with nothing on stdout" "$NC_OUT"
expect_contains "10i: farm-out-reminder names the file it could not load" \
  "farm-out-reminder: library cmd-class.sh not found" "$NC_ERR"
expect_contains "10j: background-suite-guard names it too, for itself" \
  "background-suite-guard: library cmd-class.sh not found" "$NC_ERR"
expect_contains "10k: …and both point at the diagnosis" "/bionic:doctor" "$NC_ERR"
expect_eq "10l: …one line per wall that stood down, and no more" "2" \
  "$(printf '%s\n' "$NC_ERR" | grep -c .)"

# ANTI-VACUITY: the same payload on the WHOLE library carries the background arm's refusal,
# so the silence above is the missing file and not a fixture that never reached the wall.
R_ARMED="$(mk_repo noclassifier-control)"
arm_roster "$R_ARMED"
run_hook "$(mk_payload "$R_ARMED" 'bash tests/run.sh' "$ACTOR" true)"
expect_contains "10m: control — with the classifier present that wall does refuse" \
  "a backgrounded suite's result is never read" "$OUT$ERR"

# ---------------------------------------------------------------------------
section "11 — the refusal staging is private, and its old name buys an attacker nothing (security F-1, performance A-1)"
#
# WHAT THIS OWNS. `wall_evidence_gate` stages its refusal in files, because the body runs in
# a subshell and a subshell cannot hand a variable back. T23 named that staging directory
# `$TMPDIR/bionic-gate-$$-$RANDOM` and created it with `mkdir -p` — a name an attacker on the
# same machine can pre-create (32,768 per pid) and a creation that accepts whatever is
# already there. Two consequences were DRIVEN by the Step-6 security axis: a symlink planted
# at `<stage>/1` was followed and its target truncated, and a regular file planted there was
# read back as a refusal the gate never made, on EVERY Bash call in an engaged session
# rather than only on a refusing one.
#
# HOW THESE ROWS PLANT DETERMINISTICALLY, which is the only reason this is testable at all.
# The old name needs the hook's pid and its first `$RANDOM` draw, and an outside attacker has
# neither. The driver below is the process under test, so it has both: `$$` is its own, and
# seeding `RANDOM` makes the first draw predictable (`a=$( RANDOM=n; echo $RANDOM )` yields
# the same value the next in-process read will). The driver plants, then re-seeds, then calls
# the wall. A trap laid at the vulnerable path is therefore laid EXACTLY, not approximately.
#
# THE BODY IS STUBBED, NOT DRIVEN. `_eg_body` is the gate's whole evidence walk; what is
# under test here is the STAGING its caller does around it, so the stub refuses (row a/b) or
# stays silent (rows c/d) on demand. The stub is installed after the library is sourced,
# which is what a shell function permits and what keeps these rows off the gate's fixtures.

TMPC="$SANDBOX/tmpctl"; mkdir -p "$TMPC"
VICTIM_DIR="$SANDBOX/victim"; mkdir -p "$VICTIM_DIR"
WALLS_LIB="$BIONIC_HOOKS_DIR/../payload/scripts/lib"
[ -d "$WALLS_LIB" ] || WALLS_LIB="$BIONIC_HOOKS_DIR/../scripts/lib"

# tmp_drive <seed> <plant script> <stub body> -> runs wall_evidence_gate in a scratch
# process whose TMPDIR is ours, with `$RANDOM` seeded so <plant script> can name the old
# staging directory exactly. Sets TD_OUT / TD_ERR / TD_ST.
TD_OUT=""; TD_ERR=""; TD_ST=0; TD_TMPDIR=""
tmp_drive() {  # <seed> <plant> <stub>
  local seed="$1" plant="$2" stub="$3" d
  d=$(mktemp -d "$SANDBOX/drive.XXXXXX")
  # ONE TMPDIR PER DRIVE, so a row asking "what is left under TMPDIR" is asking about this
  # drive and not about the traps an earlier row deliberately left lying there.
  TD_TMPDIR="$TMPC/t$seed"; mkdir -p "$TD_TMPDIR"
  {
    printf '%s\n' '#!/bin/bash'
    printf '%s\n' 'set -uo pipefail'
    printf 'export TMPDIR=%s\n' "$TD_TMPDIR"
    printf 'export PATH=%s:$PATH\n' "$SHIMDIR"
    printf '. "%s/refuse.sh"\n' "$WALLS_LIB"
    printf '. "%s/fold.sh"\n' "$WALLS_LIB"
    printf '. "%s/walls.sh"\n' "$WALLS_LIB"
    # The old name, named here and nowhere in the shipped tree: seed, predict, plant, re-seed.
    printf 'T20_SEED=%s\n' "$seed"
    printf '%s\n' 'T20_PRED=$( RANDOM=$T20_SEED; echo $RANDOM )'
    printf '%s\n' 'T20_OLD="$TMPDIR/bionic-gate-$$-$T20_PRED"'
    printf '%s\n' "$plant"
    printf '%s\n' 'RANDOM=$T20_SEED'
    printf '%s\n' "$stub"
    printf '%s\n' 'COMMAND="git commit -m x"'
    # THROUGH THE FOLD, because `wall_evidence_gate` only STAGES its verdict — the render
    # that puts a refusal on a reader's stream is `bionic_fold`'s, and a row asserting what
    # a reader saw has to go the way the hook goes.
    printf '%s\n' 'bionic_fold PreToolUse wall_evidence_gate; exit $?'
  } > "$d/drive.sh"
  TD_OUT=$(bash "$d/drive.sh" 2>"$d/.err")
  TD_ST=$?
  TD_ERR=$(cat "$d/.err" 2>/dev/null)
}

# The `rm` shim: logs every call and then does the real thing, so row (d) can count forks
# on the path that must not fork at all.
SHIMDIR="$SANDBOX/shim"; mkdir -p "$SHIMDIR"
RMLOG="$SANDBOX/rm.log"; : > "$RMLOG"
{
  printf '%s\n' '#!/bin/bash'
  printf 'printf "%%s\\n" "$*" >> %s\n' "$RMLOG"
  printf '%s\n' 'exec /bin/rm "$@"'
} > "$SHIMDIR/rm"
chmod +x "$SHIMDIR/rm"

REFUSING_STUB='_eg_body() { refuse exit2 commit "fixture fact for T20" "fixture fix" "fixture detail"; }'
SILENT_STUB='_eg_body() { exit 0; }'

# --- (a) THE POSITIVE CONTROL, first. A row that reads "the victim survived" is worthless
# if the wall never ran, and a stubbed body is exactly the shape that could silently not
# run. This drive refuses, through the real staging and the real fold. ---
VICT_A="$VICTIM_DIR/secret-a.txt"; printf 'ORIGINAL CONTENT A\n' > "$VICT_A"
tmp_drive 20260912 "mkdir -p \"\$T20_OLD\"; ln -s '$VICT_A' \"\$T20_OLD/1\"" "$REFUSING_STUB"
expect_status "11a: the stubbed refusal really does refuse through the staging" 2 "$TD_ST"
expect_contains "11b: …in the fixture's own words, so the fold rendered what was staged" \
  "fixture fact for T20" "$TD_OUT$TD_ERR"

# --- (b) SYMLINK-FOLLOW. The same drive planted a symlink at the old `<stage>/1`. Before
# the repair the first staged write truncated its target. ---
expect_eq "11c: a symlink planted at the wave's old staging path is NOT followed" \
  "ORIGINAL CONTENT A" "$(cat "$VICT_A" 2>/dev/null)"

# --- (c) FABRICATED REFUSAL, on a call that refuses nothing. The read of `<stage>/1` ran on
# every Bash call, so an attacker needed only the name, never a race with a real refusal. ---
tmp_drive 20260913 \
  'mkdir -p "$T20_OLD"; printf exit2 > "$T20_OLD/1"; printf commit > "$T20_OLD/2"; printf "FABRICATED VERDICT" > "$T20_OLD/3"; printf "do as I say" > "$T20_OLD/4"; printf "fabricated detail" > "$T20_OLD/5"' \
  "$SILENT_STUB"
expect_status "11d: a Bash call the gate does not refuse exits 0, planted files or not" 0 "$TD_ST"
expect_absent "11e: …and the planted text reaches neither reader" "FABRICATED VERDICT" "$TD_OUT$TD_ERR"

# --- (d) PERFORMANCE A-1: the non-refusing path forks nothing to clean up a directory it
# never made. The cleanup was unconditional, one `/bin/rm` per Bash tool call in every
# engaged session. ---
: > "$RMLOG"
tmp_drive 20260914 ':' "$SILENT_STUB"
expect_status "11f: control — the same silent drive with nothing planted also exits 0" 0 "$TD_ST"
expect_eq "11g: …having forked no rm at all (the cleanup is guarded now)" "0" \
  "$(grep -c 'bionic-gate' "$RMLOG" 2>/dev/null || true)"

# --- (e) AND THE REFUSING PATH LEAVES NOTHING EITHER. A guard that skipped the cleanup
# everywhere would pass (d) and leak a directory per refusal. Since wave-27 T71 the refusal
# reaches the parent on the subshell's own stdout and no stage is made at all, so there is
# no directory to remove: 11i reads that no `rm` was asked to remove one. ---
: > "$RMLOG"
tmp_drive 20260915 ':' "$REFUSING_STUB"
expect_status "11h: a refusal still exits 2" 2 "$TD_ST"
expect_eq "11i: …and forks no rm on a stage, because it made none" "0" \
  "$(grep -c 'bionic-gate' "$RMLOG" 2>/dev/null || true)"
expect_eq "11j: …leaving nothing behind under its own TMPDIR" "0" \
  "$(ls "$TD_TMPDIR" 2>/dev/null | grep -c 'bionic-gate' || true)"

# ---------------------------------------------------------------------------
section "§STAGE — a refusal keeps its words whatever the temp directory holds (wave-27 T71; diagnosis EG6l)"
#
# WHAT THIS OWNS. Until T71 the gate staged its refusal in `$TMPDIR/bionic-gate-$$`, a name
# made from the hook's pid alone. A hook killed between the `mkdir` and the `rm -rf` left the
# directory behind; the next refusing hook at that pid could not stage, and printed "the
# evidence gate's own refusal is malformed" with nothing above it. One row of §EG-6 lost its
# words that way in a landing run. A temp directory that cannot be written lost every
# refusal's words, of every wall, because `fold_block` sent the renderer's stderr (the user's
# line) to /dev/null when it could not make its capture file.
#
# HOW THE PID IS HELD. The driver plants at `$TMPDIR/bionic-gate-$$` and then runs the gate in
# its own shell, so the gate's `$$` is the planting process's (the diagnosis's instrument.sh).
# STAGE-e holds the REAL hook's pid the same way: `bash -c` plants, then `exec`s the hook,
# and exec keeps the pid.
#
# FIXTURE FIDELITY: the planted shapes are the four a dead 1.11.0 hook or a local user can
# leave at that name (a full five-file stage, a regular file, a FIFO, a dangling symlink),
# SYNTHESIZED; the refusing stub carries §EG-6's own fact and fix.

ST_OUT=""; ST_ERR=""; ST_RC=0; ST_TMP=""; ST_DIR=""
st_drive() {  # <name> <before the gate> <stub> [<after the gate>] — sets ST_OUT/ST_ERR/ST_RC
  ST_DIR="$SANDBOX/stage-$1"; ST_TMP="$ST_DIR/tmp"; mkdir -p "$ST_TMP"
  {
    printf '%s\n' '#!/bin/bash' 'set -uo pipefail'
    printf 'export TMPDIR=%s\n' "$ST_TMP"
    printf '. "%s/refuse.sh"\n. "%s/fold.sh"\n. "%s/walls.sh"\n' "$WALLS_LIB" "$WALLS_LIB" "$WALLS_LIB"
    printf '%s\n' "$3"
    printf '%s\n' 'COMMAND="git commit -m x"' 'OLD="$TMPDIR/bionic-gate-$$"'
    # The planted thing's identity: inode, type, mode, size, link target, and what it holds.
    printf '%s\n' 'sig() { /bin/ls -ldin "$OLD" 2>&1; if [ -d "$OLD" ] && [ ! -L "$OLD" ]; then /bin/ls -A "$OLD"; for f in "$OLD"/*; do [ -f "$f" ] && /bin/cat "$f"; done; elif [ -f "$OLD" ] && [ ! -L "$OLD" ]; then /bin/cat "$OLD"; fi; }'
    printf '%s\n' "$2"
    printf '%s\n' 'bionic_fold PreToolUse wall_evidence_gate; ST_GATE=$?'
    printf '%s\n' "${4:-:}"
    printf '%s\n' 'exit $ST_GATE'
  } > "$ST_DIR/drive.sh"
  ST_OUT=$(bash ${ST_X:-} "$ST_DIR/drive.sh" 2>"$ST_DIR/err"); ST_RC=$?
  ST_ERR=$(cat "$ST_DIR/err" 2>/dev/null)
}
st_first() { printf '%s\n' "$ST_ERR" | awk 'NF { print; exit }'; }

ST_FACT="the step-6 readings are not all held"
ST_FIX="record the missing reading"
ST_LINE="bionic: commit refused — $ST_FACT ($ST_FIX)"
ST_REFUSING="_eg_body() { refuse exit2 commit \"$ST_FACT\" \"$ST_FIX\" \"- adversarial: no reading, and no waiver\"; }"
ST_SILENT='_eg_body() { exit 0; }'
ST_BEFORE='sig > "$TMPDIR/../before"'
ST_AFTER='sig > "$TMPDIR/../after"; [ -z "${ST_WD:-}" ] || kill "$ST_WD" 2>/dev/null'

# st_planted <tag> <shape> <plant> — one row set per shape left at the old name.
st_planted() {
  st_drive "$1" "$3
$ST_BEFORE" "$ST_REFUSING" "$ST_AFTER"
  expect_status "STAGE-$1a: $2 at bionic-gate-<this pid>: the commit is still refused" 2 "$ST_RC"
  expect_eq "STAGE-$1b: …and its first line is the refusal's own fact and fix" "$ST_LINE" "$(st_first)"
  expect_absent "STAGE-$1c: …never the malformed line" "own refusal is malformed" "$ST_ERR"
  expect_absent "STAGE-$1d: …and nothing planted there is read" "PLANTED" "$ST_OUT$ST_ERR"
  expect_contains "STAGE-$1e: the planted thing was there before the gate" "bionic-gate-" \
    "$(cat "$ST_DIR/before" 2>/dev/null)"
  expect_eq "STAGE-$1f: …and is exactly as it was after it (not removed, not followed)" \
    "$(cat "$ST_DIR/before" 2>/dev/null)" "$(cat "$ST_DIR/after" 2>/dev/null)"
}

# (a) A dead hook's full stage, the shape bionic-gate-99905 had on disk.
st_planted dir "a full five-file stage" \
  'mkdir -m 700 "$OLD"; for i in 1 2 3 4 5; do printf "PLANTED$i" > "$OLD/$i"; done'
# (b) A regular file.
st_planted file "a regular file" 'printf PLANTED-FILE > "$OLD"'
# (c) A FIFO: opening it would block, so a watchdog ends a hung drive at 30 s (a red row,
# never a hung suite). Its fds go to /dev/null so it holds no pipe of this suite's.
st_planted fifo "a FIFO" \
  'mkfifo "$OLD"; { sleep 30; kill -9 $$; } >/dev/null 2>&1 </dev/null & ST_WD=$!'
# (d) A dangling symlink.
st_planted link "a dangling symlink" 'ln -s "$TMPDIR/nowhere" "$OLD"'

# (e) THE ROW THAT FAILED ONCE, MADE DETERMINISTIC, through the real hook: §EG-6's own
# commit refusal with a stage already sitting at the hook's pid.
ST_HT="$SANDBOX/stage-hook"; mkdir -p "$ST_HT"
OUT=$(printf '%s' "$(mk_payload "$R_COMMIT" 'git commit -m "step 5"')" | env HOME="$FAKE_HOME" \
        BIONIC_PLUGINS_DIR="$SANDBOX/no-plugins" CLAUDE_CODE_SESSION_ID="$SID" \
        CLAUDE_PROJECT_DIR= TMPDIR="$ST_HT" \
        bash -c 'mkdir -m 700 "$TMPDIR/bionic-gate-$$" || exit 99; printf PLANTED > "$TMPDIR/bionic-gate-$$/1"; exec bash "$0"' "$HOOK" \
        2>"$SANDBOX/.err")
ST=$?; ERR=$(cat "$SANDBOX/.err")
expect_status "STAGE-e1: the real hook, a stage already at its pid: the commit is refused" 2 "$ST"
expect_contains "STAGE-e2: …in the evidence gate's own words" "this step's evidence line is a placeholder" "$ERR"
expect_absent "STAGE-e3: …never the malformed line" "own refusal is malformed" "$ERR"
expect_eq "STAGE-e4: …and the stage it found is still there, untouched" "PLANTED" \
  "$(cat "$ST_HT"/bionic-gate-*/1 2>/dev/null)"

# (f) A GATE KILLED MID-STAGE, then a refusing gate at the same pid. On its first call the
# `cat` shim SIGKILLs the shell running the gate (`$KILL_PID`, that subshell's own pid; the
# diagnosis's E5): in 1.11.0 that call was the gate's first `$(cat <stage>/1)`, with the
# stage on disk. The subshell's pid is read as the PPID of a `sh` it execs into a command
# substitution: `$BASHPID` is bash 4's, and under /bin/bash 3.2 it is empty, so the shim
# killed nothing and this control was red under tests/run.sh's pin (T80).
ST_KSHIM="$SANDBOX/killshim"; mkdir -p "$ST_KSHIM"
printf '%s\n' '#!/bin/bash' \
  'if [ -n "${KILL_FLAG:-}" ] && [ ! -e "$KILL_FLAG" ]; then : > "$KILL_FLAG"; kill -9 "$KILL_PID"; sleep 1; fi' \
  'exec /bin/cat "$@"' > "$ST_KSHIM/cat"
chmod +x "$ST_KSHIM/cat"
st_drive kill "{ ( KILL_PID=\$(exec sh -c 'echo \$PPID'); export KILL_PID; PATH=\"$ST_KSHIM:\$PATH\" KILL_FLAG=\"\$TMPDIR/../killflag\" bionic_fold PreToolUse wall_evidence_gate ); echo \"\$?\" > \"\$TMPDIR/../killed\"; } >/dev/null 2>&1" \
  "$ST_REFUSING"
expect_eq "STAGE-k1: control — the first gate really was killed (KILL, 137)" "137" \
  "$(cat "$ST_DIR/killed" 2>/dev/null)"
expect_status "STAGE-k2: the next refusing gate at the same pid refuses" 2 "$ST_RC"
expect_eq "STAGE-k3: …in its own words" "$ST_LINE" "$(st_first)"
expect_absent "STAGE-k4: …never the malformed line" "own refusal is malformed" "$ST_ERR"

# (g) TEN REFUSING GATES IN A ROW leave nothing of theirs in the temp directory. The planted
# `keep.me` is the positive on the same listing: the listing reads the directory.
st_drive ten ': > "$TMPDIR/keep.me"; for i in 1 2 3 4 5 6 7 8 9; do bionic_fold PreToolUse wall_evidence_gate 2>/dev/null; echo "$?" >> "$TMPDIR/../rcs"; done' \
  "$ST_REFUSING" '/bin/ls -A "$TMPDIR" > "$TMPDIR/../left"'
expect_eq "STAGE-t1: ten refusing gates each exit 2" "2 2 2 2 2 2 2 2 2 2" \
  "$(tr '\n' ' ' < "$ST_DIR/rcs" 2>/dev/null)$ST_RC"
expect_eq "STAGE-t2: …and the temp directory holds only what was there before" "keep.me" \
  "$(cat "$ST_DIR/left" 2>/dev/null)"

# (h) A TEMP DIRECTORY THAT CANNOT BE WRITTEN, and (i) one that does not exist (S1).
st_drive ro 'chmod 500 "$TMPDIR"' "$ST_REFUSING" 'chmod 700 "$TMPDIR"'
expect_status "STAGE-h1: TMPDIR of mode 500: the commit is refused" 2 "$ST_RC"
expect_eq "STAGE-h2: …with its own first line" "$ST_LINE" "$(st_first)"
st_drive gone 'export TMPDIR=/nonexistent/x' "$ST_REFUSING"
expect_status "STAGE-i1: TMPDIR=/nonexistent/x: the commit is refused" 2 "$ST_RC"
expect_eq "STAGE-i2: …with its own first line" "$ST_LINE" "$(st_first)"

# The same two through the real hook, for two walls that render through `fold_block`: an
# exit2 wall (protect-main) and the dispatch-voice deny wall (farm-out-reminder, exit 0 on
# its own channel with JSON on stdout). The deny row compares its stdout with the same
# call's under a writable TMPDIR, byte for byte.
run_hook "$(mk_payload "$R_QUIET" 'bash tests/run.sh')"
ST_DENY_OK="$OUT"
for ST_BAD in ro gone; do
  if [ "$ST_BAD" = ro ]; then ST_T="$SANDBOX/stage-hook-ro"; mkdir -p "$ST_T"; chmod 500 "$ST_T"
  else ST_T=/nonexistent/x; fi
  run_hook "$(mk_payload "$R_QUIET" 'git push origin main')" TMPDIR="$ST_T"
  expect_status "STAGE-$ST_BAD-p1: protect-main still refuses a push to main" 2 "$ST"
  expect_eq "STAGE-$ST_BAD-p2: …with its first line on stderr" \
    "bionic: push refused — main is a protected branch here (push from your own terminal)" \
    "$(printf '%s\n' "$ERR" | awk 'NF { print; exit }')"
  run_hook "$(mk_payload "$R_COMMIT" 'git commit -m "step 5"')" TMPDIR="$ST_T"
  expect_status "STAGE-$ST_BAD-g1: the evidence gate still refuses the commit" 2 "$ST"
  expect_contains "STAGE-$ST_BAD-g2: …in its own words" "this step's evidence line is a placeholder" "$ERR"
  run_hook "$(mk_payload "$R_QUIET" 'bash tests/run.sh')" TMPDIR="$ST_T"
  expect_status "STAGE-$ST_BAD-d1: farm-out-reminder still denies on its own channel" 0 "$ST"
  expect_nonempty "STAGE-$ST_BAD-d2: …its JSON is on stdout" "$OUT"
  expect_eq "STAGE-$ST_BAD-d3: …byte for byte what a writable TMPDIR gets" "$ST_DENY_OK" "$OUT"
  expect_contains "STAGE-$ST_BAD-d4: …and its user line is on stderr" \
    "bionic: run refused — this command belongs in a subagent" "$ERR"
  [ "$ST_BAD" = ro ] && chmod 700 "$ST_T"
done

# (j) WHEN THE REFUSAL STILL CANNOT REACH THE PARENT, the line says so and where. The stub
# closes its own stdout, the pipe the refusal travels on, and then refuses.
st_drive pipe ':' "_eg_body() { exec 1>&-; refuse exit2 commit \"$ST_FACT\" \"$ST_FIX\" \"detail\"; }"
ST_FALLBACK="bionic: commit refused — the evidence gate could not stage its refusal on its pipe (commit again)"
expect_status "STAGE-j1: a refusal that cannot be staged still refuses the commit" 2 "$ST_RC"
expect_eq "STAGE-j2: …and its line says the gate could not stage it, and where" "$ST_FALLBACK" \
  "$(printf '%s\n' "$ST_ERR" | grep -F 'bionic: commit refused')"
expect_absent "STAGE-j3: …it does not say malformed" "malformed" "$ST_ERR"
expect_absent "STAGE-j4: …and does not send the user to doctor" "doctor" "$ST_ERR"
expect_true "STAGE-j5: …in at most 100 columns" \
  test "$(printf '%s' "$ST_FALLBACK" | LC_ALL=en_US.UTF-8 awk '{ print length($0) }')" -le 100

# (k) THE MALFORMED LINE KEEPS THE ONE CASE IT NAMES: the library refused the gate's own
# refusal (four arguments), and its complaint is on the stream above the line.
st_drive arity ':' "_eg_body() { refuse exit2 commit \"$ST_FACT\" \"$ST_FIX\"; }"
expect_status "STAGE-m1: a refusal with four arguments still refuses the commit" 2 "$ST_RC"
expect_eq "STAGE-m2: …the library's complaint comes first" \
  "bionic: refuse-call refused — refuse takes 5 arguments and got 4 (pass mode verb fact fix detail)" \
  "$(st_first)"
expect_contains "STAGE-m3: …and the malformed line follows it" \
  "bionic: commit refused — the evidence gate's own refusal is malformed" "$ST_ERR"

# (n) THE RECORD'S OWN SHAPE (A-orch-141). The five fields travel as `\036` then the fields
# with `\037` between them. A field holding either byte shows it as `?` and moves no other
# field; a field ending in line breaks loses them, as `$(cat <stage>/N)` did; and what the
# body prints on stdout for another reader reaches the hook's stdout, refusal or not.
st_drive sep ':' "_eg_body() { refuse exit2 commit \$'the \\037fact\\036 here' \$'fix\\037 it' \$'a \\036detail\\037 line'; }"
expect_status "STAGE-n1: a refusal whose fields hold the separators still refuses" 2 "$ST_RC"
expect_eq "STAGE-n2: …each separator byte shows as ?, and no field moves into another" \
  "bionic: commit refused — the ?fact? here (fix? it)" "$(st_first)"
expect_contains "STAGE-n3: …the detail keeps its words too" "a ?detail? line" "$ST_ERR"
st_drive nl ':' "_eg_body() { refuse exit2 commit \$'$ST_FACT\\n\\n' \$'$ST_FIX\\n' \$'the detail\\n\\n\\n'; }"
expect_status "STAGE-n4: fields ending in line breaks still refuse" 2 "$ST_RC"
expect_eq "STAGE-n5: …and lose them, as the files did" "$ST_LINE" "$(st_first)"
expect_eq "STAGE-n6: …the detail too: it is the last line on the stream" "the detail" \
  "$(printf '%s\n' "$ST_ERR" | awk 'NF { l = $0 } END { print l }')"
st_drive out ':' "_eg_body() { printf 'BODY-LINE-1\\nBODY-LINE-2\\n'; refuse exit2 commit \"$ST_FACT\" \"$ST_FIX\" \"d\"; }"
expect_status "STAGE-n7: a body that prints on stdout and then refuses still refuses" 2 "$ST_RC"
expect_eq "STAGE-n8: …and what it printed is on the hook's stdout, whole" \
  "BODY-LINE-1
BODY-LINE-2" "$ST_OUT"
expect_eq "STAGE-n9: …beside its refusal on stderr" "$ST_LINE" "$(st_first)"
st_drive outq ':' "_eg_body() { printf 'BODY-QUIET\\n'; exit 0; }"
expect_status "STAGE-n10: a body that prints on stdout and refuses nothing exits 0" 0 "$ST_RC"
expect_eq "STAGE-n11: …and what it printed is on the hook's stdout" "BODY-QUIET" "$ST_OUT"

# (l) THE PATH THAT REFUSES NOTHING forks no external command and leaves no file, counted the
# way tests/hook-latency.test.sh counts (`bash -x`, one `+` line per external command). The
# refusing drive is the positive on the same counter: it forks at least the fold's `mktemp`.
ST_EXT='^\++ (jq|grep|awk|sed|cut|tr|git|date|stat|find|sort|uniq|head|tail|wc|mkdir|rm|mktemp|cat|ls|mv|cp|ln)( |$)'
ST_X=-x st_drive quiet ': > "$TMPDIR/keep.me"' "$ST_SILENT" '/bin/ls -A "$TMPDIR" > "$TMPDIR/../left"'
expect_status "STAGE-q1: the silent gate exits 0" 0 "$ST_RC"
expect_eq "STAGE-q2: …forking no external command" "0" \
  "$(printf '%s\n' "$ST_ERR" | grep -cE "$ST_EXT" || true)"
expect_eq "STAGE-q3: …and leaving no file" "keep.me" "$(cat "$ST_DIR/left" 2>/dev/null)"
ST_X=-x st_drive quietpos ':' "$ST_REFUSING"
expect_true "STAGE-q4: control — the same counter sees the refusing gate's forks" \
  test "$(printf '%s\n' "$ST_ERR" | grep -cE "$ST_EXT" || true)" -ge 1

# ---------------------------------------------------------------------------
section "12 — the two-repos day: a CLAUDE_PROJECT_DIR that is no project may not disarm the walls (critic Issue 2, A-85)"
#
# THE CONDITION IS ORDINARY. A session launched outside a bionic project and then worked
# inside one keeps CLAUDE_PROJECT_DIR at the LAUNCH directory while every payload carries
# the project as its `.cwd`. Before A-85 the ladder took the launch directory on `-d`
# alone, resolved a root that held no engagement marker, and every wall in this process
# went silent: the critic measured `push refused, rc 2` becoming rc 0 and an empty stream.
# Nine of the fifteen pre-fold hooks recovered through `.cwd` and stayed armed, so this
# suite is asserting base-faithful reach, not a new one.
#
# TWO WALLS, DELIBERATELY. protect-main refuses whether or not the session is engaged, so
# it proves the ROOT was found; the evidence gate refuses only an ENGAGED session under a
# blocking plan, so it proves the engagement marker was found under that root too. A fix
# that resolved the root and lost the marker would pass the first row and fail the second.

R_NOPROJ="$SANDBOX/launched-elsewhere"
mkdir -p "$R_NOPROJ"
git -C "$R_NOPROJ" init -q 2>/dev/null
expect_eq "12a: the launch directory is a git repo and NOT a bionic project" "yes" \
  "$([ -d "$R_NOPROJ/.git" ] && [ ! -e "$R_NOPROJ/.bionic" ] && echo yes || echo no)"

run_hook "$(mk_payload "$R_PUSH" 'git push origin main')" CLAUDE_PROJECT_DIR="$R_NOPROJ"
expect_status "12b: a push to main is still refused, rc 2" 2 "$ST"
expect_contains "12c: …in protect-main's own words" \
  "main is a protected branch here" "$ERR"

run_hook "$(mk_payload "$R_COMMIT" 'git commit -m wip')" CLAUDE_PROJECT_DIR="$R_NOPROJ"
expect_status "12d: the evidence gate still refuses a commit under a blocking plan" 2 "$ST"

# THE CONTROLS. The same two payloads with CLAUDE_PROJECT_DIR pointing at the project
# itself — the rung is still taken when it names one — and with it empty, which is how
# every other row in this file drives the hook.
run_hook "$(mk_payload "$R_PUSH" 'git push origin main')" CLAUDE_PROJECT_DIR="$R_PUSH"
expect_status "12e: control — the env naming the project itself refuses too" 2 "$ST"
run_hook "$(mk_payload "$R_PUSH" 'git push origin main')"
expect_status "12f: control — the env empty refuses too" 2 "$ST"

# AND THE BYSTANDER IS STILL A BYSTANDER: falling through to `.cwd` may not arm a session
# that never engaged. The evidence gate is the arm to ask, since protect-main refuses
# unconditionally by design (§7).
run_hook "$(mk_payload "$R_PLAIN" 'bash tests/run.sh')" CLAUDE_PROJECT_DIR="$R_NOPROJ"
expect_status "12g: an unengaged session is still silent through the fall-through" 0 "$ST"
expect_empty "12h: …on both streams" "$OUT$ERR"

# ---------------------------------------------------------------------------
section "13 — §cwd-split: the push wall judges the payload's cwd, not the hook process's own (D2, REQ-5)"
#
# walls.sh:265 used to ask `git symbolic-ref --short HEAD` with no `-C`, which answers
# about the directory the HOOK PROCESS happens to be running in — an accident of how the
# CLI launched the hook — rather than the directory the PAYLOAD names (P-B: a wall reads
# facts from its input, never from ambient process state). Every other row in this file
# lets the hook inherit this suite's own cwd, so the two are always the same directory
# and the bug is invisible (A2). This section is the one place they are made to differ
# on purpose.
#
# run_hook_in <dir> <payload> [env...] — like run_hook, but the HOOK PROCESS itself
# starts in <dir> rather than wherever this suite runs from.
run_hook_in() {
  local dir="$1" payload="$2"; shift 2
  OUT=$(cd "$dir" && printf '%s' "$payload" | env HOME="$FAKE_HOME" \
          BIONIC_PLUGINS_DIR="$SANDBOX/no-plugins" CLAUDE_CODE_SESSION_ID="$SID" \
          CLAUDE_PROJECT_DIR= "$@" bash "$HOOK" 2>"$SANDBOX/.err")
  ST=$?
  ERR=$(cat "$SANDBOX/.err")
  return 0
}

# mk_cwd_repo <name> <branch> <engaged:yes|no> — a real repo pinned to <branch> by
# `git init -b`, never mk_repo's automatic `feature/t23` checkout, because this section
# needs BOTH a main-branch and a feature-branch repo under its own control.
mk_cwd_repo() {
  local repo="$SANDBOX/$1"
  mkdir -p "$repo/.bionic/tmp"
  git -C "$repo" init -q -b "$2" 2>/dev/null
  git -C "$repo" config user.email t@example.com
  git -C "$repo" config user.name "T"
  printf 'seed\n' > "$repo/README.md"
  git -C "$repo" add README.md
  git -C "$repo" commit -qm seed 2>/dev/null
  [ "$3" = yes ] && : > "$repo/.bionic/tmp/engaged-$SID.state"
  printf '%s' "$repo"
}

# THE LAUNCH REPOS — where the hook PROCESS starts. Not engaged: engagement is resolved
# from the PAYLOAD's cwd (CLAUDE_PROJECT_DIR is empty in every row below, same as the
# rest of this file), so these two never need the marker.
CWD_LAUNCH_MAIN="$(mk_cwd_repo cwd-launch-main main no)"
CWD_LAUNCH_FEATURE="$(mk_cwd_repo cwd-launch-feature feature/launch no)"

# THE PAYLOAD REPOS — the directory `.cwd` names. Engaged, because this is the root
# `bionic_context` resolves and the engagement guard in hooks/bash-walls.sh reads it
# before any wall runs.
CWD_PAYLOAD_FEATURE="$(mk_cwd_repo cwd-payload-feature feature/payload yes)"
CWD_PAYLOAD_MAIN="$(mk_cwd_repo cwd-payload-main main yes)"
CWD_FALLBACK="$(mk_cwd_repo cwd-fallback main yes)"

expect_eq "13-setup: the launch repo is on main" "main" \
  "$(git -C "$CWD_LAUNCH_MAIN" symbolic-ref --short HEAD 2>/dev/null)"
expect_eq "13-setup: the other launch repo is on a feature branch" "feature/launch" \
  "$(git -C "$CWD_LAUNCH_FEATURE" symbolic-ref --short HEAD 2>/dev/null)"

# (a) Process on a main checkout, payload cwd a sandbox on a feature branch → ALLOWED.
# `git push origin HEAD` (no explicit destination name) reaches Block 3 only — the block
# a fix must scope to the PAYLOAD's branch, not the launch directory's.
run_hook_in "$CWD_LAUNCH_MAIN" "$(mk_payload "$CWD_PAYLOAD_FEATURE" 'git push origin HEAD')"
expect_status "13a: process on main + payload cwd on a feature branch — allowed" 0 "$ST"
expect_empty "13b: …silently, on both streams" "$OUT$ERR"

# (b) The reverse — process on a feature checkout, payload cwd a sandbox on main →
# REFUSED, in the existing words. Before the fix this row passed the current directory's
# OWN branch (feature/launch, not protected) and let the push through.
run_hook_in "$CWD_LAUNCH_FEATURE" "$(mk_payload "$CWD_PAYLOAD_MAIN" 'git push origin HEAD')"
expect_status "13c: process on a feature branch + payload cwd on main — refused" 2 "$ST"
expect_contains "13d: …in the existing words" "the current branch is protected" "$ERR"

# (c) A payload with no usable cwd — today's outcome, UNCHANGED. `bionic_context`'s own
# rung 3 falls back to `pwd` when the payload names nothing usable, so launching the hook
# FROM the engaged repo and handing it an empty `.cwd` reproduces exactly the behaviour
# this wall always had (AC-5.4): the branch it judges is the directory it is standing in.
run_hook_in "$CWD_FALLBACK" "$(mk_payload "" 'git push origin HEAD')"
expect_status "13e: no usable payload cwd — falls back to the hook's own directory, refused" 2 "$ST"
expect_contains "13f: …in the existing words" "the current branch is protected" "$ERR"

# ---------------------------------------------------------------------------
finish
