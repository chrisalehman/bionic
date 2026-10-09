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
# tests/bash-walls-egd.test.sh, which is `# runner: solo`. The helpers both suites read live in
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
section "14 — repair: a suite call's timeout is raised to the harness maximum (T3, REQ-3, D4)"
#
# THE NEW ARM, between ARM 1 (backgrounded → refuse) and ARM 2 (the budget). It never
# refuses: a subagent's suite call whose `timeout` is absent, non-numeric, or below
# `BASH_MAX_TIMEOUT_MS` is rewritten via `hookSpecificOutput.updatedInput` and allowed to
# proceed, so every row here that repairs still exits 0.
#
# `agent_type: test-runner` on every repairing row, same as section 2j's convention: it
# silences farm-out-reminder so exactly one wall answers and these assertions are not
# reading a composed verdict by accident.

R_REPAIR="$(mk_repo repair)"
# ON THE BUDGET, so the budget arm passes every call below and the repair is what answers. A
# suite from an agent with no recorded set is refused since wave-27 T5 (D15), never repaired.
bw_dispatched "$R_REPAIR" t14repair suites_allowed=x.test.sh suites_source=declared files=

# (a) no `timeout` at all — the harness's own default (two minutes) is what kills a real
# suite, and this is the shape a dispatched worker's Bash call carries when it names none.
run_hook "$(mk_payload "$R_REPAIR" 'tests/run.sh --only x.test.sh' "$ACTOR" omit Bash test-runner)" \
  BASH_MAX_TIMEOUT_MS=600000
expect_status "14a: a subagent suite call with no timeout is not refused" 0 "$ST"
expect_eq "14b: …updatedInput.timeout is raised to the harness maximum" "600000" "$(updated_timeout_of)"
expect_contains "14c: …command and tool_name ride through unchanged" "tests/run.sh --only x.test.sh" \
  "$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.updatedInput.command // ""' 2>/dev/null)"
expect_contains "14d: …the repair is logged, naming the agent" \
  "canonical-sdlc [suite-timeout]: repaired from=absent to=600000 agent=$ACTOR" "$ERR"
# `log_finding`'s CHANNEL/SUBJECT/ROOT are declared lazily by the evidence gate's own
# internal body, reached only along a commit-class path a suite call never takes — a
# repair firing without its own declaration calls an undefined `bionic_finding_root`,
# which fails "command not found" on stderr beside the log line `expect_contains` above
# would still find. This is the ONE line that would have caught it.
expect_eq "14e0: …and stderr is EXACTLY that one log line — no stray shell error beside it" \
  "canonical-sdlc [suite-timeout]: repaired from=absent to=600000 agent=$ACTOR" "$ERR"
# ONE ANSWER, BOTH REWRITES (wave-26 T7, D8). The repair sets `timeout`; the booking wrap
# then rewrites `command` on the SAME object, so neither change overwrites the other.
expect_eq "14e1: …one JSON document on stdout" "1" "$(json_docs)"
expect_regex "14e2: …whose command is the booking wrap around the original" \
  "^bash [^ ]+/scripts/booked\\.sh( --shell [^ ]+)?( --agent [^ ]+)? --detach --suites x\\.test\\.sh --runner -- 'tests/run\\.sh --only x\\.test\\.sh'\$" \
  "$(updated_command_of)"
expect_eq "14e3: …beside the repaired timeout" "600000" "$(updated_timeout_of)"

# (b) a timeout BELOW the maximum — raised, not left alone.
run_hook "$(mk_payload "$R_REPAIR" 'tests/run.sh --only x.test.sh' "$ACTOR" omit Bash test-runner 3000)" \
  BASH_MAX_TIMEOUT_MS=600000
expect_eq "14e: a timeout below the maximum is raised to it" "600000" "$(updated_timeout_of)"
expect_contains "14f: …logged with the ORIGINAL value, not the repaired one" \
  "repaired from=3000 to=600000 agent=$ACTOR" "$ERR"

# (c) a timeout AT the maximum — nothing to repair, and ARM 2's budget arm decides the call
# instead (x.test.sh is on the row's budget, so it passes in silence).
run_hook "$(mk_payload "$R_REPAIR" 'tests/run.sh --only x.test.sh' "$ACTOR" omit Bash test-runner 600000)" \
  BASH_MAX_TIMEOUT_MS=600000
expect_status "14g: a suite call already at the harness maximum is not refused" 0 "$ST"
# THE WRAP RIDES EVERY ALLOWED SUITE CALL (wave-26 T7, D8), so updatedInput is present here
# too — but its timeout is the caller's own, untouched: there was nothing to repair.
expect_eq "14h: …its timeout is left as the caller set it — there is nothing to repair" \
  "600000" "$(updated_timeout_of)"
expect_regex "14h2: …and the only rewrite is the booking wrap around the original command" \
  "^bash [^ ]+/scripts/booked\\.sh( --shell [^ ]+)?( --agent [^ ]+)? --detach --suites x\\.test\\.sh --runner -- 'tests/run\\.sh --only x\\.test\\.sh'\$" \
  "$(updated_command_of)"
expect_empty "14i: …no repair logged either" "$ERR"

# (d) ARM 1 UNCHANGED — a backgrounded suite is still refused, and the repair arm (which
# sits textually after ARM 1) never gets a chance to speak for it.
run_hook "$(mk_payload "$R_REPAIR" 'tests/run.sh --only x.test.sh' "$ACTOR" true Bash test-runner)" \
  BASH_MAX_TIMEOUT_MS=600000
expect_status "14j: a backgrounded suite is still refused — ARM 1's own verdict, unchanged" 2 "$ST"
expect_contains "14k: …in ARM 1's own words" "a backgrounded suite's result is never read" "$ERR"
expect_eq "14l: …and carries no updatedInput" "no" "$(has_updated_input)"

# (e) MAIN-THREAD CONTROL — no `agent_id` at all. The partition above ARM 1 already
# returns before the repair arm is reached; whatever else fires on this payload (farm-out-
# reminder's own tier-1 deny, unrelated to this wall), no updatedInput ever appears.
run_hook "$(mk_payload "$R_REPAIR" 'bash tests/x.test.sh')" BASH_MAX_TIMEOUT_MS=600000
expect_eq "14m: a main-thread suite call carries no updatedInput — the repair never reaches it" \
  "no" "$(has_updated_input)"
# …BUT WHERE THE MAIN THREAD MAY RUN IT, IT IS BOOKED (wave-26 T7, D8). Under
# `farm-out-mode: advisory` farm-out nudges instead of refusing; the call is allowed, so the
# wrap rides beside the nudge in one document, and the timeout is the main thread's own.
R_ADV="$(mk_repo advisory)"
printf 'farm-out-mode: advisory\n' > "$R_ADV/.bionic/config.yaml"
run_hook "$(mk_payload "$R_ADV" 'bash tests/x.test.sh')" BASH_MAX_TIMEOUT_MS=600000
expect_status "14m1: an advisory main-thread suite call is allowed" 0 "$ST"
expect_eq "14m2: …one JSON document on stdout" "1" "$(json_docs)"
expect_regex "14m3: …carrying the booking wrap" \
  "^bash [^ ]+/scripts/booked\\.sh( --shell [^ ]+)?( --agent [^ ]+)? --detach --suites x\\.test\\.sh -- 'bash tests/x\\.test\\.sh'\$" \
  "$(updated_command_of)"
expect_eq "14m4: …and no timeout repair on the main thread" "" "$(updated_timeout_of)"
expect_nonempty "14m4: …(the reader works: the wrap's command is non-empty on the same object)" \
  "$(updated_command_of)"

# (f) SUBAGENT, NON-SUITE CONTROL — `cmd_class` never answers "suite", so the whole
# function returns before ARM 1 or the repair arm, exactly as section 1's `ls -la` row.
run_hook "$(mk_payload "$R_REPAIR" 'ls -la' "$ACTOR" omit Bash test-runner)" \
  BASH_MAX_TIMEOUT_MS=600000
expect_status "14n: a subagent's non-suite command is untouched" 0 "$ST"
expect_eq "14o: …no updatedInput — cmd_class never reaches 'suite'" "no" "$(has_updated_input)"
expect_empty "14p: …and nothing on either stream" "$OUT$ERR"

# (g) THE CEILING ITSELF MOVES — bionic setup's 30-minute ceiling, not the 600000 stock
# default, is what a repair on an armed machine raises to.
run_hook "$(mk_payload "$R_REPAIR" 'tests/run.sh --only x.test.sh' "$ACTOR" omit Bash test-runner)" \
  BASH_MAX_TIMEOUT_MS=1800000
expect_eq "14q: a wider harness ceiling (bionic setup's 30 minutes) is the value repaired to" \
  "1800000" "$(updated_timeout_of)"

# (h) NON-NUMERIC — a `timeout` that is not a plain integer repairs exactly like an absent
# one (D4: "absent, non-numeric, or < MAX" all repair the same way), and the log line's own
# two-shape contract (`from=<absent|n>`) has no third case for a name it cannot show, so it
# reads "absent" rather than the unusable text.
NONNUM_PAYLOAD=$(jq -n --arg s "$SID" --arg c "$R_REPAIR" --arg a "$ACTOR" \
  '{session_id:$s, cwd:$c, hook_event_name:"PreToolUse", tool_name:"Bash",
    tool_input:{command:"tests/run.sh --only x.test.sh", timeout:"soon"},
    tool_use_id:"toolu_01t23nonnum", agent_id:$a, agent_type:"test-runner"}')
run_hook "$NONNUM_PAYLOAD" BASH_MAX_TIMEOUT_MS=600000
expect_eq "14r: a non-numeric timeout repairs the same as an absent one" "600000" \
  "$(updated_timeout_of)"
expect_contains "14s: …logged as 'absent', the contract's own shape for it" \
  "repaired from=absent to=600000 agent=$ACTOR" "$ERR"

# (i) THE ARM ORDER (T13, A-orch-39) — the BUDGET arm decides BEFORE the repair arm, so an
# OFF-BUDGET suite call carrying no `timeout` is REFUSED, not repaired and allowed.
#
# THIS IS THE DISCRIMINATING PAYLOAD and it is why the fixture above states no `timeout`:
# ARM R shipped (T3) between ARM 1 and ARM 2 and `return`ed the moment it staged a rewrite,
# so this exact shape — the one a dispatched worker's Bash call carries when it names no
# ceiling — never reached the budget at all. Give the row a timeout and the defect vanishes
# from the fixture along with the test for it.
#
# THREE WIRES, NOT ONE. `fold.sh` drops a staged `updatedInput` whenever anything blocked,
# so 14w alone would pass even with the arms in the wrong order; 14v is the assertion that
# cannot be satisfied by the fold, because `log_finding`'s stderr line (and its audit write)
# leave the process before the fold ever renders a verdict.
R_ORDER="$(mk_repo armorder)"
# Through the one production writer, same as tests/agent-context-guard.test.sh §G9: a field
# this fixture believes in that `roster_row` stopped emitting fails loudly instead of
# quietly budgeting nothing. The id arrives through the start arm (`bw_dispatched`).
bw_dispatched "$R_ORDER" t13writer \
  suites_allowed=alpha.test.sh suites_source=declared files=

run_hook "$(mk_payload "$R_ORDER" 'tests/run.sh --only gamma.test.sh' "$ACTOR" omit Bash test-runner)" \
  BASH_MAX_TIMEOUT_MS=600000
expect_status "14t: off-budget + NO timeout: refused — the budget arm runs before the repair" \
  2 "$ST"
# Re-spelled (wave-14 T8 c088189 → T18 fcd5a16 → T25): "off budget:" inverted its own
# meaning (the set printed is the ALLOWED set, not what is off it) — the label is now
# "allowed:".
expect_contains "14u: …in the budget arm's own words" \
  "allowed:" "$ERR"
expect_contains "14u2: …and AC-5.2's set: the row's own allowed token is on this line, not just detail" \
  "alpha.test.sh" "$ERR"
expect_absent "14v: …and a REFUSED call is never repaired — no repair line on stderr" \
  "suite-timeout" "$ERR"
expect_eq "14w: …and no updatedInput on stdout either" "no" "$(has_updated_input)"

# (j) ITS PAIR — the same payload shape ON the budget is still repaired exactly as T3
# shipped it. Without this row, 14t-14w are satisfied by a wall that simply stopped
# repairing anything.
run_hook "$(mk_payload "$R_ORDER" 'tests/run.sh --only alpha.test.sh' "$ACTOR" omit Bash test-runner)" \
  BASH_MAX_TIMEOUT_MS=600000
expect_status "14x: on-budget + no timeout: allowed — reaching the repair arm at all proves the budget arm passed it" 0 "$ST"
expect_eq "14y: …updatedInput.timeout still raised to the harness maximum" "600000" \
  "$(updated_timeout_of)"
expect_contains "14z: …and the repair is still logged, naming the agent" \
  "repaired from=absent to=600000 agent=$ACTOR" "$ERR"

# ---------------------------------------------------------------------------
section "15 — §budget-on-the-wire (T8, AC-5.2): the allowed set reaches exit-2 stderr"
#
# Re-spelled (wave-14 T8 c088189 → T18 fcd5a16 → T25): T25 renamed the three fact labels
# ("off budget: " -> "allowed: ", "full tree off budget: " -> "full tree refused; allowed: ",
# "unexpanded name; budget: " -> "unexpanded name; allowed: ") because the old wording put
# the ALLOWED set right after the words "off budget", which reads backwards, and rendered
# an empty set as "off budget: none" — "nothing is off budget" on a line that is refusing.
# Every assertion below checks a TOKEN or COUNT, never the label text itself, so none of
# their values change; only this note and 14u (which pinned the label) needed a re-spell.
#
# T7's repro (record/wave-14-tune-181/T7-req5-repro.md §4, ruling D-1): "On the budget: …"
# lived only in `detail`, and refuse.sh's channel table marks exit2's `detail_to_user`
# `no` — a dispatched writer's own tool_result on a budget refusal never carried the
# recorded set, only the one-line fact/fix, and that line named no set. AC-5.2's
# fails-when is exactly this: "the stderr the harness relays on exit 2 carries no suite
# tokens." This section drives all three call sites `budget_refuse` (walls.sh) folds
# through and proves each one now does, on the DEFAULT (non-verbose) channel — never
# through $VERR, which section 14 and tests/agent-context-guard.test.sh §G9 already cover.

R15="$(mk_repo budgetwire)"
. "$(dirname "$0")/lib/roster-row.sh"
bw_dispatched "$R15" t15writer \
  "suites_allowed=archive.test.sh run.sh" suites_source=derived files=

WIRE_RE='^bionic: [a-z-]+ refused — .+ \(.{1,40}\)$'

# (a) the ordinary per-suite refusal — the primary AC-5.2 site (walls.sh's own line
# number for "On the budget:" cited by the wave plan).
run_hook "$(mk_payload "$R15" 'tests/run.sh --only close-out.test.sh' "$ACTOR" omit Bash test-runner)"
expect_status "15a: an off-budget suite is still refused" 2 "$ST"
expect_contains "15a2: …and the DEFAULT (non-verbose) exit-2 stderr carries the FIRST allowed token" \
  "archive.test.sh" "$ERR"
expect_contains "15a3: …and the SECOND" "run.sh" "$ERR"
# THE REMEDY (T6, REQ-5, AC-5.2): a refused writer is told who widens the budget and with
# which verb, so the report it sends is one the orchestrator can act on in one command.
expect_contains "15a6: …naming the remedy verb, amend" "session-poker.sh amend t15writer" "$ERR"
# THE FLAG FITS THE REFUSAL (wave-21 T13; walk-3b45d05 item 4). A refused SUITE is widened by
# `--suites+ <suite>`, the verb's own flag for a suite file; `--reexec+` is the flag for a run.
expect_contains "15a7: …and the flag that widens a SUITE, --suites+, naming the refused suite" \
  "amend t15writer --suites+ close-out.test.sh" "$ERR"
expect_absent "15a7b: …never the run flag --reexec+ for a suite" "--reexec+" "$ERR"
# THE LINE PASTES (wave-21 T14; critic-4e6d4a9 I4). `--reason <why>` was a redirect from a file
# named `why` with no word after it — a parse error, not a usage error — so the line the remedy
# promises is pasteable was not. The placeholder is quoted, and the whole line parses as bash.
expect_contains "15a7c: …and the reason placeholder is quoted, one shell word" \
  "amend t15writer --suites+ close-out.test.sh --reason '<why>' (main runs it)" "$ERR"
B15_LINE="$(printf '%s\n' "$ERR" | sed -n 's/.*widen it: \(.*\) (main runs it).*/\1/p' | head -1)"
expect_contains "15a7d precondition: the remedy line was read off the refusal" "session-poker.sh amend" "$B15_LINE"
expect_true "15a7e: …and the pasted line parses as bash [$B15_LINE]" bash -n -c "$B15_LINE"
expect_contains "15a8: …with the real plugin root, not the placeholder" "/hooks/session-poker.sh amend" "$ERR"
expect_absent "15a9: …never the literal <plugin-root> placeholder" "<plugin-root>" "$ERR"

# (a2) A REFUSED RUN keeps `--reexec+ '<cmd>'`: a runner command is no suite file, and a run
# is what that flag widens. A row whose budget declares one run, asked for another.
R15X="$(mk_repo budgetwirerun2)"
bw_dispatched "$R15X" t15runner \
  "re_executes=\`npx jest --testPathPatterns 'x'\`" suites_source=declared files=
run_hook "$(mk_payload "$R15X" 'npx jest --testPathPatterns y' "$ACTOR" omit Bash test-runner)"
expect_status "15a10: an undeclared run is refused" 2 "$ST"
expect_contains "15a11: …and its remedy names the run flag, --reexec+ '<cmd>'" \
  "amend t15runner --reexec+ '<cmd>'" "$ERR"
expect_absent "15a12: …never the suite flag" "--suites+" "$ERR"
expect_contains "15a12b: …with the reason placeholder quoted there too" \
  "amend t15runner --reexec+ '<cmd>' --reason '<why>' (main runs it)" "$ERR"
B15_LINE="$(printf '%s\n' "$ERR" | sed -n 's/.*widen it: \(.*\) (main runs it).*/\1/p' | head -1)"
expect_true "15a12c: …and that line parses as bash too [$B15_LINE]" bash -n -c "$B15_LINE"

# (a2b) A PLUGIN ROOT WITH A SPACE (wave-24 T28; critic I2, AC-6.5). The remedy line printed
# the root bare, so `<root with space>/hooks/session-poker.sh` pasted as two arguments. The
# line is built by `_budget_remedy_line` from `refuse_plugin_root`, which reads `$BIONIC_LIB`;
# no hook can be loaded from a root this test makes up, so the function is driven directly,
# extracted the way 15g2 extracts `_budget_wire_list`, with the loader's variable pointed at a
# root whose name holds a space. The printed line is then read back as the shell reads it.
SP_ROOT="$SANDBOX/plugin root"
mkdir -p "$SP_ROOT/scripts/lib"
SP_LINE=$(BIONIC_LIB="$SP_ROOT/scripts/lib" _BUDGET_ROW_NAME=t15sp bash -c '. "$1/refuse.sh"
  eval "$(awk "/^_budget_remedy_line\(\)/,/^}/" "$1/walls.sh")"; _budget_remedy_line alpha.test.sh' \
  _ "$WALLS_LIB")
SP_LINE="${SP_LINE#widen it: }"; SP_LINE="${SP_LINE% (main runs it)}"
expect_contains "15a13 precondition: the remedy line was built, under the spaced root" \
  "plugin root/hooks/session-poker.sh" "$SP_LINE"
SP_ARG2=$(eval "set -- $SP_LINE"; printf '%s' "$2")
expect_eq "15a13: …and pasted, the script path is ONE argument [$SP_LINE]" \
  "$SP_ROOT/hooks/session-poker.sh" "$SP_ARG2"
SP_ARG3=$(eval "set -- $SP_LINE"; printf '%s' "$3")
expect_eq "15a14: …and the verb is the next one, not the tail of a split path" "amend" "$SP_ARG3"

# (a3) THE WIRE-LIST COUNT NAMES DECLARATIONS (wave-22 T4; REQ-4, D7, AC-4.1/4.2). When the one
# declared run does not fit the verdict line's room, the line says what the count counts —
# `1 declared run (printed below)` — and the full command still prints after `On the budget:`.
# A fitting run is the command itself, unchanged (the short form, pinned below from a RED run).
R15W="$(mk_repo budgetwirelongrun)"
W15_RUN="pytest tests/unit/test_a_very_long_module_name_that_cannot_fit_on_any_line.py -k widget"
bw_dispatched "$R15W" t15wide \
  "re_executes=\`$W15_RUN\`" suites_source=declared files=
run_hook "$(mk_payload "$R15W" 'npx jest --testPathPatterns y' "$ACTOR" omit Bash test-runner)"
expect_status "15a20: an undeclared run against one over-wide declared run is refused" 2 "$ST"
W15_LINE="$(printf '%s\n' "$ERR" | /usr/bin/grep -m1 '^bionic: ')"
expect_contains "15a21: …and the allowed clause counts the declaration, naming where the run prints" \
  "allowed: 1 declared run (printed below)" "$W15_LINE"
W15_BLOCK="$(printf '%s\n' "$ERR" | sed -n '/On the budget:/,$p')"
expect_contains "15a22: …and the full command still prints in the On the budget: block" \
  "$W15_RUN" "$W15_BLOCK"
expect_absent "15a23: …and the line no longer reads the bare count 'allowed: 1 run'" \
  "allowed: 1 run" "$W15_LINE"
# THE SHORT FORM, PINNED VERBATIM (AC-4.2): a declared run that FITS prints as itself; the verdict
# line below was copied from a RED-time run at a220bd6 and must not change.
R15S="$(mk_repo budgetwireshortrun)"
bw_dispatched "$R15S" t15short \
  "re_executes=\`npm test\`" suites_source=declared files=
run_hook "$(mk_payload "$R15S" 'npx jest --testPathPatterns y' "$ACTOR" omit Bash test-runner)"
expect_eq "15a24: a fitting declared run keeps the verdict line byte-for-byte" \
  "bionic: suite-run refused — allowed: \`npm test\` (run only the budgeted suites)" "$(printf '%s\n' "$ERR" | /usr/bin/grep -m1 '^bionic: ')"

# (a3) THE NAME AS THE ROSTER CARRIES IT. A row named `w budget;rm` was printed as
# `amend wbudgetrm`, a name no row carries, so the pasted command addressed nobody. A name a
# shell would split or act on is single-quoted instead, so the line is still pasteable and
# still names the row.
R15Q="$(mk_repo budgetwirequote)"
bw_dispatched "$R15Q" "w budget;rm" \
  "suites_allowed=archive.test.sh" suites_source=derived files=
run_hook "$(mk_payload "$R15Q" 'tests/run.sh --only close-out.test.sh' "$ACTOR" omit Bash test-runner)"
expect_status "15a13: an off-budget suite for a row with an unsafe name is refused" 2 "$ST"
expect_contains "15a14: …and the remedy names the row as the roster carries it, quoted" \
  "amend 'w budget;rm' --suites+ close-out.test.sh" "$ERR"
expect_absent "15a15: …never a sanitised name no row carries" "wbudgetrm" "$ERR"
# ONE VERDICT LINE, AND A DETAIL BENEATH IT (ADR-030). Until field 9 flipped, "the stream
# is one line" and "the verdict is one line" were the same measurement on `exit2`. AC-E1.3
# asks for the second — a sentence the reader is interrupted by, never wrapped — so that is
# what is counted, with the positive beside it so narrowing the count cannot pass over a
# wall that went quiet.
expect_eq "15a4: …still exactly one VERDICT line" "1" \
  "$(printf '%s\n' "$ERR" | /usr/bin/grep -c '^bionic: ')"
expect_eq "15a4b: …with its detail beneath it, no knob set" "yes" \
  "$([ "$(printf '%s\n' "$ERR" | /usr/bin/grep -v '^bionic: ' | /usr/bin/grep -c .)" -ge 1 ] && echo yes || echo no)"
if printf '%s' "$ERR" | /usr/bin/grep -qE "$WIRE_RE"; then
  ok "15a5: …and still in AC-E1.3's one-line shape"
else
  no "15a5: …and still in AC-E1.3's one-line shape" "line=[$ERR]"
fi

# (b) the shell-variable-name case — an unexpanded `$s.test.sh` cannot be checked against
# the budget, but the budget it WOULD have checked against still belongs on the wire.
# THE BODY REASSIGNS THE VARIABLE (wave-24 T13, A-orch-15). Since T5 a loop over a literal
# word list resolves to its suites and meets the ORDINARY refusal, so the fixture that drives
# THIS arm is the one the classifier still cannot resolve: `s=c` in the body.
run_hook "$(mk_payload "$R15" 'for s in a b; do s=c; tests/run.sh --only "$s.test.sh"; done' "$ACTOR" omit Bash test-runner)"
expect_status "15b: an unexpanded suite name is still refused" 2 "$ST"
expect_contains "15b2: …and the recorded budget is on the DEFAULT stderr too" \
  "archive.test.sh" "$ERR"
expect_contains "15b3: …by the unexpanded-name arm, not the ordinary one" \
  "unexpanded name" "$(printf '%s\n' "$ERR" | /usr/bin/grep -m1 '^bionic: ')"
# THE HEADER'S WORDS ARE NOT WHAT RUNS (wave-24 T26, walk-head-b surprise 3): `s=c` makes this
# loop run c twice, so printing `bash tests/a.test.sh` would be a false fix — the same wall
# refuses it. The refusal says no list can be derived and asks for the literal lines meant.
# fails-when: the reassigning loop's refusal prints its header words.
expect_contains "15b4: …saying no literal list can be derived from a body that reassigns" \
  "no literal list can be derived" "$ERR"
expect_contains "15b5: …naming the reassignment as the reason" "reassigns its variable" "$ERR"
expect_contains "15b5b: …and asking for the literal lines the agent means" \
  "Write the literal names you mean, through the one door: tests/run.sh --only <name>.test.sh" "$ERR"
expect_absent "15b6: …never the header's words as a line to run" "tests/run.sh --only a.test.sh" "$ERR"
expect_absent "15b6b: …never the canned alpha example the arm used to print" "alpha.test.sh" "$ERR"
# THE FIX IS THE LOOP'S OWN WORDS when the body leaves the variable alone (wave-24 T13, D10,
# AC-6.3): an `eval` keeps the classifier from expanding the command, and the lines the loop
# would have run are read off `cmd_suite_loop_lines` — never a canned example.
run_hook "$(mk_payload "$R15" 'for s in a b; do tests/run.sh --only "$s.test.sh"; done; eval :' "$ACTOR" omit Bash test-runner)"
expect_status "15b10: a loop the classifier will not expand is refused as unexpanded" 2 "$ST"
expect_contains "15b11: …by the unexpanded-name arm" \
  "unexpanded name" "$(printf '%s\n' "$ERR" | /usr/bin/grep -m1 '^bionic: ')"
expect_contains "15b12: …printing the loop's first word as the literal line to run" \
  "    tests/run.sh --only a.test.sh" "$ERR"
expect_contains "15b13: …and its second" "    tests/run.sh --only b.test.sh" "$ERR"
# A `$` THE TEXT GIVES NO WORDS FOR still refuses, and says why it has no line to print.
run_hook "$(mk_payload "$R15" 'for s in $(ls tests); do tests/run.sh --only "$s.test.sh"; done' "$ACTOR" omit Bash test-runner)"
expect_status "15b7: a loop over a command substitution is refused as unexpanded" 2 "$ST"
expect_contains "15b8: …and says the text gives no literal list to print" \
  "no literal list" "$ERR"
expect_absent "15b9: …printing no line it cannot know" "tests/run.sh --only a.test.sh" "$ERR"

# (c) the full-tree case (`tests/run.sh`, not on this row's budget). A FRESH row: R15's
# own set literally contains the token "run.sh" as one of its two allowed SUITE NAMES,
# which is also the one token that waives this exact arm (walls.sh: `*" run.sh "*)
# continue`) — reusing it here would test nothing.
R15R="$(mk_repo budgetwirerun)"
bw_dispatched "$R15R" t15run \
  suites_allowed=archive.test.sh suites_source=declared files=
run_hook "$(mk_payload "$R15R" 'bash tests/run.sh' "$ACTOR" omit Bash test-runner)"
expect_status "15c: the full tree is refused when the row does not carry it" 2 "$ST"
expect_contains "15c2: …and the recorded budget is on the DEFAULT stderr" \
  "archive.test.sh" "$ERR"

# (d) THE PAIRED NEGATIVE — a brief that declared `Suites: none` carries no fabricated
# token, and the wire says so honestly rather than silently going quiet about it.
R15N="$(mk_repo budgetwirenone)"
bw_dispatched "$R15N" t15none \
  suites_allowed=none suites_source=declared files=
run_hook "$(mk_payload "$R15N" 'tests/run.sh --only gamma.test.sh' "$ACTOR" omit Bash test-runner)"
expect_status "15d: a Suites: none row still refuses" 2 "$ST"
expect_contains "15d2: …and the DEFAULT stderr says so honestly — 'none' on the wire" \
  "none" "$ERR"
# ON THE VERDICT LINE, which is where a fabricated token would do the damage: the line is
# what the reader is interrupted by and what names the budget. The refused command itself
# appears in the wall's `detail`, and since ADR-030 that detail is on the same stream, so a
# whole-stream grep can no longer tell the two apart.
expect_absent "15d3: …never a fabricated suite token on the verdict line" "gamma.test.sh" \
  "$(printf '%s\n' "$ERR" | /usr/bin/grep -m1 '^bionic: ')"

# (e) A WIDE BUDGET (A-orch-17's own incident: "the row carried a 38-suite set") still
# fits ONE line — token boundaries, not a mid-name cut, and a "+N more" count for what
# does not fit.
R15W="$(mk_repo budgetwirewide)"
WIDE_SET=""
for i in $(seq 1 38); do WIDE_SET="$WIDE_SET s${i}.test.sh"; done
WIDE_SET="${WIDE_SET# }"
bw_dispatched "$R15W" t15wide \
  "suites_allowed=$WIDE_SET" suites_source=derived files=
run_hook "$(mk_payload "$R15W" 'tests/run.sh --only zzz-off-budget.test.sh' "$ACTOR" omit Bash test-runner)"
expect_status "15e: an off-budget suite against a 38-suite row is refused" 2 "$ST"
expect_eq "15e2: …still exactly one VERDICT line" "1" \
  "$(printf '%s\n' "$ERR" | /usr/bin/grep -c '^bionic: ')"
if printf '%s' "$ERR" | /usr/bin/grep -qE "$WIRE_RE"; then
  ok "15e3: …still in AC-E1.3's one-line shape (never overflows past refuse()'s own cap)"
else
  no "15e3: …still in AC-E1.3's one-line shape (never overflows past refuse()'s own cap)" "line=[$ERR]"
fi
expect_contains "15e4: …and it names at least one real suite token, not a mid-name ellipsis" \
  "s1.test.sh" "$ERR"
expect_contains "15e5: …with an honest count of what did not fit" "more" "$ERR"

# (f) CONTROL — an on-budget suite is still silent on both streams; the change above is
# additive to the refusal only, never a new nudge on the allowed path. A payload timeout
# pinned to the SAME value this call sets `BASH_MAX_TIMEOUT_MS` to keeps ARM R's
# repair-and-log silent too (section 14c: "a timeout AT the maximum — nothing to
# repair"), regardless of whatever ceiling the calling shell happens to have exported.
run_hook "$(mk_payload "$R15" 'tests/run.sh --only archive.test.sh' "$ACTOR" omit Bash test-runner 600000)" \
  BASH_MAX_TIMEOUT_MS=600000
expect_status "15f: an on-budget suite is still allowed" 0 "$ST"
# THE ONLY STDOUT IS THE BOOKING WRAP (wave-26 T7, D8), which every allowed suite call
# carries: no nudge, no refusal, and nothing on stderr.
expect_empty "15f2: …stderr stays empty" "$ERR"
expect_regex "15f3: …and stdout is the booking wrap alone" \
  "^bash [^ ]+/scripts/booked\\.sh( --shell [^ ]+)?( --agent [^ ]+)? --detach --suites archive\\.test\\.sh --runner -- 'tests/run\\.sh --only archive\\.test\\.sh'\$" \
  "$(updated_command_of)"
expect_eq "15f4: …with no other channel beside it" '["hookEventName","updatedInput"]' \
  "$(printf '%s' "$OUT" | jq -c '.hookSpecificOutput | keys' 2>/dev/null)"

# (g) T25 fold-in (review-correctness-d3930dd.md F3, F7): THE HONEST FLOOR WHEN THERE IS NO
# ROOM AT ALL. (e) above proves the wide-budget case (a whole token plus a "+N more" count);
# these two prove the two ways that can still fail — a single token too long to fit even
# BARE (F3 — used to fall through to a character cut, printing a truncated, unrunnable
# suite name) and a column budget of zero or less on a NON-EMPTY set (F7 — used to print
# the literal `none`, the same word an EMPTY set gets). Both now render a bare count
# ("N suites") instead: never a cut name, never a false `none`.

# (g1) F3 — one suite name longer than the unexpanded-name label's own room (17 columns at
# this wave's other two literals in force) drives the deepest fallback for real, through
# the production hook.
R15L="$(mk_repo budgetwirelong)"
LONG_SUITE="tests/a-suite-name-far-too-long-to-fit-even-bare-on-one-refusal-line.test.sh"
bw_dispatched "$R15L" t15long \
  "suites_allowed=$LONG_SUITE" suites_source=derived files=
run_hook "$(mk_payload "$R15L" 'for s in a b; do s=c; tests/run.sh --only "$s.test.sh"; done' "$ACTOR" omit Bash test-runner)"
expect_status "15g1: an unexpanded name against a too-long single suite is still refused" 2 "$ST"
expect_contains "15g1: …through the unexpanded-name arm this fallback is named for" \
  "unexpanded name" "$(printf '%s\n' "$ERR" | /usr/bin/grep -m1 '^bionic: ')"
expect_contains "15g1: …and the line falls back to an honest count, never a cut name" \
  "1 suite" "$ERR"
expect_absent "15g1: …never a mid-name character cut (the ellipsis glyph)" "…" "$ERR"
# ON THE VERDICT LINE for the same reason as 15d3, and here the distinction is sharper
# still: the wall's detail names the suite in FULL, and the full name begins with the
# fragment a mid-name cut would leave. Only the line can answer whether anything was cut.
expect_absent "15g1: …and never the truncated fragment itself on the verdict line" \
  "tests/a-suite-name-far" "$(printf '%s\n' "$ERR" | /usr/bin/grep -m1 '^bionic: ')"
if printf '%s' "$ERR" | /usr/bin/grep -qE "$WIRE_RE"; then
  ok "15g1: …still in AC-E1.3's one-line shape"
else
  no "15g1: …still in AC-E1.3's one-line shape" "line=[$ERR]"
fi

# (g2) F7 — a column budget of zero (or less) is not reachable through any live call site
# today (all three labels leave positive room — 17/18/32 columns, this report), so this
# drives `_budget_wire_list` directly. It is a NESTED function (defined only when
# `wall_background_suite_guard` itself runs, per bash scoping — confirmed: sourcing
# walls.sh alone registers the outer wall functions but not this one), so it is extracted
# the way cross-gate-agreement.test.sh already extracts nested/inline bodies for a
# unit-level pin: `awk` between its own `()` line and its closing `}`, then `eval`.
G7_LIB="$WALLS_LIB"
G7_NONEMPTY=$(bash -c '. "'"$G7_LIB"'/refuse.sh"; . "'"$G7_LIB"'/fold.sh"; \
  eval "$(awk "/^_budget_wire_list\(\)/,/^}/" "'"$G7_LIB"'/walls.sh")"; \
  _budget_wire_list "tests/a.test.sh tests/b.test.sh" 0')
expect_eq "15g2: a non-empty set at cols<=0 renders an honest count, never a false 'none'" \
  "2 suites" "$G7_NONEMPTY"
G7_EMPTY=$(bash -c '. "'"$G7_LIB"'/refuse.sh"; . "'"$G7_LIB"'/fold.sh"; \
  eval "$(awk "/^_budget_wire_list\(\)/,/^}/" "'"$G7_LIB"'/walls.sh")"; \
  _budget_wire_list "" 0')
expect_eq "15g2: …and a GENUINELY empty set still says 'none' (the control this pin needs)" \
  "none" "$G7_EMPTY"

# ---------------------------------------------------------------------------
section "16 — the evidence gate folds a mis-cased worktree cell too, as the landing gate does (critic C14, T46)"
#
# T41 folded `_lg_row_for_tree` (payload/scripts/lib/stop.sh) so the LANDING gate matches a
# plan row's `worktree` cell against a tree's real basename case-insensitively — the tree
# name a real dispatch produces is always `<NN>-T<n>` (capital T) while a hand-edited cell
# can drift in case. `_eg_row_for_worktree` (walls.sh) makes the SAME match for the EVIDENCE
# gate and, until this fold, still compared exactly: a row cell spelled `17-T5` against a
# real tree directory git itself named `17-t5` (lowercase) matched in one wall and not the
# other — one plan, two answers for which row owns the tree, exactly what ADR-032 exists to
# prevent. `## Tasks` at step 4/active drives the D1/ADR-031 subject fork
# (`_EG_RSTATUS = active` and `_EG_RSTEP >= 4`, both required): found, the commit is judged
# by the row's task arms and says so; missed, the gate falls back to `current:` and says
# THAT instead. Both plans below hold `current: 4`, so the fork is a no-op on `CURRENT`
# either way — the two arms differ only in which line they print, which is what these
# assertions read.
#
# A REAL LINKED WORKTREE, never a hand-planted `.git` file (mirrors
# tests/canonical-sdlc-evidence-gate.test.sh's 25g fixtures): the name the arm reads is the
# one git itself chose out of `<main>/.git/worktrees/<name>`, and on any filesystem that name
# is the literal basename `git worktree add` was given — lowercase here, deliberately, so the
# row's capitalized cell is the one thing this fixture makes wrong.
R_ROWFOLD="$(mk_repo rowfold)"
git -C "$R_ROWFOLD" worktree add -q "$R_ROWFOLD/.worktrees/17-t5" -b wt/17-t5 2>/dev/null
expect_eq "16a: the fixture's tree really is a linked worktree, named lowercase by git" \
  "17-t5" "$(basename "$(git -C "$R_ROWFOLD/.worktrees/17-t5" rev-parse --git-dir)")"

T46_ROWFOLD_PLAN='---
governing-skill: canonical-sdlc
canonical_sdlc_version: 14
intent: build
rigor: audited
scale: wave
deploy_target: none
use_worktree: true
has_ui: false
walk: exempt
---
# plan

## SDLC State

current: 4
approved-by: fixture 2026-09-21T00:00Z "approved"
Step 4:
  worktree: .worktrees/17-t5
  base-sha: 0fe69ed
  branch: wt/17-t5

## Tasks

| id | step | kind | task | agent | deps | size | serves | Files | worktree | status |
|---|---|---|---|---|---|---|---|---|---|---|
| T1 | 4 | build | mis-cased worktree cell against the real (lowercase) tree | senior-implementor | — | 20m | REQ-2 | a.sh | 17-T5 | active |
'
printf '%s\n' "$T46_ROWFOLD_PLAN" > "$R_ROWFOLD/.bionic/docs/plans/active.md"
bw_bind "$R_ROWFOLD"

run_hook "$(mk_payload "$R_ROWFOLD/.worktrees/17-t5" 'git commit -m "x"')" CLAUDE_PROJECT_DIR="$R_ROWFOLD"
expect_status "16b: the commit is still allowed either way (Step 4's shape is honest regardless of which row answers)" 0 "$ST"
expect_contains "16c: the gate judges by the ROW's task arms — T1's cell (17-T5) still names the real (lowercase) tree" \
  "evidence-gate: judged by row T1's task arms (run at current: 4)" "$ERR"
expect_absent "16d: …never falling back to 'no ## Tasks row names worktree', which is the pre-fold miss" \
  "no ## Tasks row names worktree" "$ERR"

# THE MIRROR CASE (T50, T47's floor RED, §25g): 16a–16d's tree was lowercase, so `$_want`
# (the literal basename git gave the tree) happened to already equal a folded cell without
# needing any fold of its own — that fixture could not see a one-sided fold miss the OTHER
# direction. A real dispatch tree is never lowercase; `_eg_git_wt_name` hands back the
# capitalized name git itself chose (`<NN>-T<n>`, T46's own comment says so), and when the
# cell is spelled with the SAME case a one-sided fold still breaks the match: the cell gets
# folded to lowercase, `$_want` does not, and two identical strings compare unequal. That is
# the exact §25g failure (12 rows, `wt-T3`/`wt-T5`/`wt-T9`/`14-TC`), reproduced here with a
# real linked worktree so this file — not just the evidence-gate suite — pins it.
R_ROWFOLD2="$(mk_repo rowfold2)"
git -C "$R_ROWFOLD2" worktree add -q "$R_ROWFOLD2/.worktrees/17-T7" -b wt/17-T7 2>/dev/null
expect_eq "16e: the fixture's tree really is a linked worktree, named mixed-case by git (a real dispatch shape)" \
  "17-T7" "$(basename "$(git -C "$R_ROWFOLD2/.worktrees/17-T7" rev-parse --git-dir)")"

T50_ROWFOLD_PLAN='---
governing-skill: canonical-sdlc
canonical_sdlc_version: 14
intent: build
rigor: audited
scale: wave
deploy_target: none
use_worktree: true
has_ui: false
walk: exempt
---
# plan

## SDLC State

current: 4
approved-by: fixture 2026-09-21T00:00Z "approved"
Step 4:
  worktree: .worktrees/17-T7
  base-sha: 0fe69ed
  branch: wt/17-T7

## Tasks

| id | step | kind | task | agent | deps | size | serves | Files | worktree | status |
|---|---|---|---|---|---|---|---|---|---|---|
| T1 | 4 | build | mixed-case worktree cell against the real (mixed-case) tree | senior-implementor | — | 20m | REQ-2 | a.sh | 17-T7 | active |
'
printf '%s\n' "$T50_ROWFOLD_PLAN" > "$R_ROWFOLD2/.bionic/docs/plans/active.md"
bw_bind "$R_ROWFOLD2"

run_hook "$(mk_payload "$R_ROWFOLD2/.worktrees/17-T7" 'git commit -m "x"')" CLAUDE_PROJECT_DIR="$R_ROWFOLD2"
expect_status "16f: the commit is still allowed either way (Step 4's shape is honest regardless of which row answers)" 0 "$ST"
expect_contains "16g: the gate judges by the ROW's task arms — T1's cell (17-T7) still names the real (mixed-case) tree" \
  "evidence-gate: judged by row T1's task arms (run at current: 4)" "$ERR"
expect_absent "16h: …never falling back to 'no ## Tasks row names worktree', which is the ONE-SIDED-fold miss (T47 §25g)" \
  "no ## Tasks row names worktree" "$ERR"

# THE `use_worktree: false` TWIN (wave-18 REQ-11, D7, backlog row 3; AC-11.1). 16a-16h both
# declare `use_worktree: true`, which is why nothing ever measured what the fork's
# substitution is WORTH. It announces "judged by row T1's task arms" and substitutes
# `CURRENT=4` — and Step 4 is a POINTER step, so a few hundred lines later the pointer exit
# takes `exit 0` on it unless the frontmatter says `use_worktree: true`. The one arm the
# substitution exists to reach — `shape_block worktree base-sha branch`, the task arms the
# note promises — was therefore skipped on every `use_worktree: false` plan, and the commit
# was admitted with the note printed and nothing checked. A substituted step is not a
# pointer step: the fork now flags its substitution and the pointer exit honours it, so the
# fork owns the arms it announces whatever `use_worktree` says.
#
# THE FIXTURE IS 16e-16h's, with two bytes changed: `use_worktree: false`, and a `Step 4:`
# block that carries a real value but NOT the three worktree fields. Both halves matter —
# the block is non-empty and placeholder-free, so it clears every arm upstream of the shape
# check and the shape check is the only thing left to refuse it.
W18_POINTER_TASKS='
## Tasks

| id | step | kind | task | agent | deps | size | serves | Files | worktree | status |
|---|---|---|---|---|---|---|---|---|---|---|
| T1 | 4 | build | the row whose tree this commit comes from | senior-implementor | — | 20m | REQ-11 | a.sh | 18-T1 | active |
'

w18_pointer_plan() {  # $1 = use_worktree value
  printf -- '---\ngoverning-skill: canonical-sdlc\ncanonical_sdlc_version: 14\nintent: build\nrigor: audited\nscale: wave\ndeploy_target: none\nuse_worktree: %s\nhas_ui: false\nwalk: exempt\n---\n' "$1"
  printf '# plan\n\n## SDLC State\n\ncurrent: 4\napproved-by: fixture 2026-09-22T00:00Z approved\n'
  printf 'Step 4: dispatch ledger at .bionic/docs/record/w18/dispatch.md\n'
  printf '%s\n' "$W18_POINTER_TASKS"
}

R_PTR_FALSE="$(mk_repo ptrfalse)"
git -C "$R_PTR_FALSE" worktree add -q "$R_PTR_FALSE/.worktrees/18-T1" -b wt/18-T1 2>/dev/null
expect_eq "16i: the fixture's tree really is a linked worktree, named 18-T1 by git (a real dispatch shape)" \
  "18-T1" "$(basename "$(git -C "$R_PTR_FALSE/.worktrees/18-T1" rev-parse --git-dir)")"

w18_pointer_plan false > "$R_PTR_FALSE/.bionic/docs/plans/active.md"
bw_bind "$R_PTR_FALSE"
run_hook "$(mk_payload "$R_PTR_FALSE/.worktrees/18-T1" 'git commit -m "x"')" CLAUDE_PROJECT_DIR="$R_PTR_FALSE"
expect_contains "16j: the fork still announces the subject it chose, on a use_worktree: false plan" \
  "evidence-gate: judged by row T1's task arms (run at current: 4)" "$ERR"
expect_status "16k: …and the arms it announced RUN — the Step-4 shape refuses a block with no worktree fields, though use_worktree is false" \
  2 "$ST"
expect_contains "16k: …naming the three fields the task arms owe" \
  "worktree base-sha branch" "$ERR"

# THE CONTROL: the same plan, the same tree, the same commit, `use_worktree: true` — refused
# for the same three fields. Two verdicts that now agree; before this they differed on the
# frontmatter key alone, which is the defect backlog row 3 named.
R_PTR_TRUE="$(mk_repo ptrtrue)"
git -C "$R_PTR_TRUE" worktree add -q "$R_PTR_TRUE/.worktrees/18-T1" -b wt/18-T1 2>/dev/null
w18_pointer_plan true > "$R_PTR_TRUE/.bionic/docs/plans/active.md"
bw_bind "$R_PTR_TRUE"
run_hook "$(mk_payload "$R_PTR_TRUE/.worktrees/18-T1" 'git commit -m "x"')" CLAUDE_PROJECT_DIR="$R_PTR_TRUE"
expect_status "16l: the use_worktree: true twin refuses the same commit for the same fields" 2 "$ST"
expect_contains "16l: …naming them" "worktree base-sha branch" "$ERR"

# THE STEP-BELOW TWIN (critic C1; wave-18 REQ-11 AC-11.1, D7). 16i-16l fixed the fork that
# fires when the row's step EQUALS current: (the `active` arm at walls.sh ~:2835). A second
# fork substitutes CURRENT the same way when the row's step is BELOW current: (walls.sh
# ~:2768, `_EG_RSTEP -lt _EG_CURNUM`) — the ordinary shape once a run has advanced past Step 4
# while writer trees are still live — and until this row it set `CURRENT` without setting
# `_EG_SUBSTITUTED`, so the pointer exit fell back to the frontmatter key alone on this branch
# even though 16i-16l closed the other one.
#
# THE FIXTURE IS 16i-16l's, with one byte changed: `current: 5` instead of `current: 4`, so
# the row's step 4 is now BELOW current: and the step-below arm fires instead of the
# step-equal arm. Same tree, same row, same missing fields.
W18_BELOW_TASKS='
## Tasks

| id | step | kind | task | agent | deps | size | serves | Files | worktree | status |
|---|---|---|---|---|---|---|---|---|---|---|
| T1 | 4 | build | the row whose tree this commit comes from | senior-implementor | — | 20m | REQ-11 | a.sh | 18-T1 | active |
'

w18_below_plan() {  # $1 = use_worktree value
  printf -- '---\ngoverning-skill: canonical-sdlc\ncanonical_sdlc_version: 14\nintent: build\nrigor: audited\nscale: wave\ndeploy_target: none\nuse_worktree: %s\nhas_ui: false\nwalk: exempt\n---\n' "$1"
  printf '# plan\n\n## SDLC State\n\ncurrent: 5\napproved-by: fixture 2026-09-22T00:00Z approved\n'
  printf 'Step 4: dispatch ledger at .bionic/docs/record/w18/dispatch.md\n'
  printf '%s\n' "$W18_BELOW_TASKS"
}

R_BELOW_FALSE="$(mk_repo belowfalse)"
git -C "$R_BELOW_FALSE" worktree add -q "$R_BELOW_FALSE/.worktrees/18-T1" -b wt/18-T1 2>/dev/null
w18_below_plan false > "$R_BELOW_FALSE/.bionic/docs/plans/active.md"
bw_bind "$R_BELOW_FALSE"
run_hook "$(mk_payload "$R_BELOW_FALSE/.worktrees/18-T1" 'git commit -m "x"')" CLAUDE_PROJECT_DIR="$R_BELOW_FALSE"
expect_contains "16m: the step-below fork announces the row's step too, on a use_worktree: false plan" \
  "evidence-gate: judged at row T1's step 4 (run at current: 5)" "$ERR"
expect_status "16n: …and the arms it announced RUN — the Step-4 shape refuses a block with no worktree fields, though use_worktree is false" \
  2 "$ST"
expect_contains "16n: …naming the three fields the task arms owe" \
  "worktree base-sha branch" "$ERR"

# THE CONTROL: the same plan, the same tree, the same commit, `use_worktree: true` — refused
# for the same three fields, exactly as 16l controls 16j/16k.
R_BELOW_TRUE="$(mk_repo belowtrue)"
git -C "$R_BELOW_TRUE" worktree add -q "$R_BELOW_TRUE/.worktrees/18-T1" -b wt/18-T1 2>/dev/null
w18_below_plan true > "$R_BELOW_TRUE/.bionic/docs/plans/active.md"
bw_bind "$R_BELOW_TRUE"
run_hook "$(mk_payload "$R_BELOW_TRUE/.worktrees/18-T1" 'git commit -m "x"')" CLAUDE_PROJECT_DIR="$R_BELOW_TRUE"
expect_status "16o: the use_worktree: true twin refuses the same commit for the same fields" 2 "$ST"
expect_contains "16o: …naming them" "worktree base-sha branch" "$ERR"


# ---------------------------------------------------------------------------
section "17 — a read-only role's commit is refused by its roster row (wave-19 REQ-8, D9)"
#
# THE BREACH (wave-18 T7c-green, ideas row 5). A `bionic:test-runner` dispatched to run the
# green suites committed on its own. Nothing stopped it: the four read-only roles carry
# `disallowedTools: Write, Edit, NotebookEdit`, never `Bash`, so `git commit` was a promise
# in prose. The role arm in wall_background_suite_guard joins the payload's `agent_id` to the
# roster and reads the winning row's `subagent_type=`.
#
# FIXTURE FIDELITY. The rows are the LIVE teammate shape R3 Q2 measured: an `intended` and a
# `confirmed` row with `agent_id=` EMPTY, then the `identified` row the recorder's
# SubagentStart arm writes carrying the id. The role is plugin-qualified (`bionic:<role>`)
# and `agent_type` carries the dispatch NAME, not the role (R3 Q2, meta.json). No plan in the
# repo, so the evidence gate admits every commit here and the role arm is the only speaker.

RO_ID="aw18-T7c-green-0123456789abcdef"
R_RO="$(mk_repo readonly)"
roster_header > "$R_RO/.bionic/tmp/roster-$SID.state"

ro_rows() {  # <repo> <name> <agent_id> <subagent_type> — the three live rows, in order
  local rf="$1/.bionic/tmp/roster-$SID.state"
  roster_row_fixture "session=$SID" status=intended   "name=$2" agent_id=   "subagent_type=$4" >> "$rf"
  roster_row_fixture "session=$SID" status=confirmed  "name=$2" agent_id=   "subagent_type=$4" \
    "teammate_id=$2@session-x" >> "$rf"
  roster_row_fixture "session=$SID" status=identified "name=$2" "agent_id=$3" "subagent_type=$4" >> "$rf"
}
ro_rows "$R_RO" w18-T7c-green "$RO_ID" bionic:test-runner
RO_COMMIT="git -C $R_RO add -A && git -C $R_RO commit -qm \"T7c-green: suites green\""

run_hook "$(mk_payload "$R_RO" "$RO_COMMIT" "$RO_ID" omit Bash w18-T7c-green)"
expect_status "17a: AC-8.1 — the T7c-green shape (a bionic:test-runner row's git commit) is REFUSED" 2 "$ST"
expect_contains "17a: …naming the role" "bionic:test-runner" "$ERR"
expect_contains "17a: …and the rule" "a read-only role never commits" "$ERR"
expect_eq "17a: …on ONE refusal line" "1" "$(printf '%s\n' "$ERR" | grep -c 'a read-only role never commits')"

# THE OTHER THREE READ-ONLY ROLES, one row each on the same repo, each with its own id.
for _ro in researcher auditor critic; do
  ro_rows "$R_RO" "w19-$_ro" "a$_ro-0123456789abcdef" "bionic:$_ro"
  run_hook "$(mk_payload "$R_RO" 'git commit -m "x"' "a$_ro-0123456789abcdef" omit Bash "w19-$_ro")"
  expect_status "17b: AC-8.1 — a bionic:$_ro row's git commit is REFUSED" 2 "$ST"
  expect_contains "17b: …naming bionic:$_ro" "bionic:$_ro" "$ERR"
done

# `git -C <dir> commit` and `git -c k=v commit` are commits by argv position — the same
# parser the evidence gate reads (tests/git-argv.test.sh).
run_hook "$(mk_payload "$R_RO" "git -c user.name=x -C $R_RO commit -m x" "$RO_ID" omit Bash w18-T7c-green)"
expect_status "17c: a global-option spelling of the commit is refused too" 2 "$ST"

# THE CONTROLS (AC-8.1's second half, AC-8.2). Each is refused by nothing else here, so an
# arm that over-reaches turns one of these to 2.
R_RO_OK="$(mk_repo readonly-controls)"
roster_header > "$R_RO_OK/.bionic/tmp/roster-$SID.state"
ro_rows "$R_RO_OK" w19-T5 aimplementor-0123456789abcdef bionic:implementor
run_hook "$(mk_payload "$R_RO_OK" 'git commit -m "x"' aimplementor-0123456789abcdef omit Bash w19-T5)"
expect_status "17d: AC-8.1 — a bionic:implementor row's commit is ADMITTED" 0 "$ST"
expect_absent "17d: …and this arm says nothing" "read-only role" "$ERR"

run_hook "$(mk_payload "$R_RO_OK" 'git commit -m "x"')"
expect_status "17e: AC-8.2 — a nameless (main-thread, no agent_id) commit is ADMITTED" 0 "$ST"
expect_absent "17e: …silently on this arm" "read-only role" "$ERR"

run_hook "$(mk_payload "$R_RO_OK" 'git commit -m "x"' anorow-0123456789abcdef omit Bash w19-norow)"
expect_status "17f: AC-8.2 — an agent_id with NO roster row is ADMITTED" 0 "$ST"

ro_rows "$R_RO_OK" w19-norole anorole-0123456789abcdef ""
run_hook "$(mk_payload "$R_RO_OK" 'git commit -m "x"' anorole-0123456789abcdef omit Bash w19-norole)"
expect_status "17g: AC-8.2 — a row with an EMPTY subagent_type is ADMITTED" 0 "$ST"

# THE SUFFIX TRAP (AC-8.2: "a role is guessed from a -runner suffix"). The dispatch NAME and
# `agent_type` both read `x-runner`; the row's role is an implementor. Admitted.
ro_rows "$R_RO_OK" x-runner axrunner-0123456789abcdef bionic:implementor
run_hook "$(mk_payload "$R_RO_OK" 'git commit -m "x"' axrunner-0123456789abcdef omit Bash x-runner)"
expect_status "17h: AC-8.2 — a row NAMED x-runner with an implementor role is ADMITTED" 0 "$ST"

# A CONSUMER'S OWN ROLE of the same bare name is not bionic's (R3 Q2 spelling 1).
ro_rows "$R_RO_OK" w19-acme aacme-0123456789abcdef acme:test-runner
run_hook "$(mk_payload "$R_RO_OK" 'git commit -m "x"' aacme-0123456789abcdef omit Bash w19-acme)"
expect_status "17i: a consumer's acme:test-runner row is ADMITTED (the match is exact, never a suffix)" 0 "$ST"

# NOT A COMMIT: a read-only role reading git, or quoting the words, is not this arm's.
run_hook "$(mk_payload "$R_RO" 'git status && echo "git commit later"' "$RO_ID" omit Bash w18-T7c-green)"
expect_status "17j: a bionic:test-runner's git status / quoted 'git commit' is ADMITTED" 0 "$ST"

# EVERY COMMIT-CREATING VERB, IN BOTH SPELLINGS (wave-20 T3, REQ-3, AC-3.2). The arm read
# `git commit` only, so a test-runner's `git revert HEAD`, `git cherry-pick <sha>` or `git merge`
# made a commit the arm never saw, and `env -C <dir> git commit` hid even the one verb it read
# (triage-D row 3). The arm now asks one set of eight verbs over the env-aware reader.
for _v in commit merge revert cherry-pick am rebase commit-tree update-ref; do
  run_hook "$(mk_payload "$R_RO" "git $_v x" "$RO_ID" omit Bash w18-T7c-green)"
  expect_status "17k: AC-3.2 — a bionic:test-runner's 'git $_v' is REFUSED" 2 "$ST"
  expect_contains "17k: …by the role arm ('git $_v')" "a read-only role never commits" "$ERR"
  run_hook "$(mk_payload "$R_RO" "env -C $R_RO git $_v x" "$RO_ID" omit Bash w18-T7c-green)"
  expect_status "17k: AC-3.2 — a bionic:test-runner's 'env -C <dir> git $_v' is REFUSED" 2 "$ST"
  expect_contains "17k: …by the role arm ('env -C <dir> git $_v')" "a read-only role never commits" "$ERR"
done
run_hook "$(mk_payload "$R_RO" 'git revert HEAD' "$RO_ID" omit Bash w18-T7c-green)"
expect_status "17k: AC-3.2 — the criterion's own 'git revert HEAD' is REFUSED" 2 "$ST"
run_hook "$(mk_payload "$R_RO" "env -C $R_RO git cherry-pick 0123abc" "$RO_ID" omit Bash w18-T7c-green)"
expect_status "17k: AC-3.2 — the criterion's own 'env -C <dir> git cherry-pick <sha>' is REFUSED" 2 "$ST"
run_hook "$(mk_payload "$R_RO" "env -i git commit -m x" "$RO_ID" omit Bash w18-T7c-green)"
expect_status "17k: …and 'env -i git commit' is REFUSED" 2 "$ST"
# NOT A COMMIT-CREATING VERB: reading history is still a read-only role's work.
run_hook "$(mk_payload "$R_RO" "env -C $R_RO git log --merge -1 && git diff HEAD~1" "$RO_ID" omit Bash w18-T7c-green)"
expect_status "17k: a bionic:test-runner's 'env -C <dir> git log --merge' / 'git diff' is ADMITTED" 0 "$ST"

# AC-3.3: A WRITER IS UNAFFECTED. An implementor merging its wave head into its task branch is
# exactly what the brief tells it to do before reporting; the widened set is the role arm's only.
run_hook "$(mk_payload "$R_RO_OK" 'git merge --no-ff wave/20-fixit-187' aimplementor-0123456789abcdef omit Bash w19-T5)"
expect_status "17l: AC-3.3 — a bionic:implementor's 'git merge --no-ff <wave head>' is ADMITTED" 0 "$ST"
expect_absent "17l: …and the role arm says nothing" "read-only role" "$ERR"
run_hook "$(mk_payload "$R_RO_OK" "git -C $R_RO_OK merge --no-ff wave/20-fixit-187" aimplementor-0123456789abcdef omit Bash w19-T5)"
expect_status "17l: AC-3.3 — …and spelled 'git -C <tree> merge --no-ff', ADMITTED" 0 "$ST"


# ---------------------------------------------------------------------------
section "18 — a commit into another repository is outside the evidence gate, and only it (wave-19 REQ-9, D10)"
#
# THE FAULT (A-T11.1). From an engaged session, `git -C <scratch repo> commit` was judged by
# the evidence gate against THIS repository's plan and refused for its evidence. The gate now
# asks which repository the commit lands in before it reads a plan; another repository — a
# scratch one, or one NESTED under the root — is admitted with one line. The walls folded
# beside the gate never read a plan and are not exempted with it: the read-only-role arm (T5)
# still refuses a test-runner's commit wherever it lands.
#
# R_COMMIT carries `block_plan` (current: 5, a placeholder Step-5 line), so every commit the
# gate still judges there is refused — the control that makes each allow a boundary verdict.
R_SCR="$SANDBOX/scratchpad/scratch-repo"
mkdir -p "$R_SCR"; git -C "$R_SCR" init -q 2>/dev/null
R_NEST="$R_COMMIT/.bionic/docs/record/x/bed"
mkdir -p "$R_NEST"; git -C "$R_NEST" init -q 2>/dev/null
jur_line() {  # <the commit's repository> [engaged root, default R_COMMIT]
  printf 'evidence-gate: %s is outside the engaged repository (%s); the evidence gate has no plan here' "$1" "${2:-$R_COMMIT}"
}

run_hook "$(mk_payload "$R_COMMIT" 'git commit -m "x"')"
expect_status "18a: control — a commit inside the engaged root under block_plan is refused as before" 2 "$ST"
expect_contains "18a: …by the evidence gate" "commit refused" "$ERR"

run_hook "$(mk_payload "$R_COMMIT" "git -C $R_SCR commit -q --allow-empty -m x")"
expect_status "18b: AC-9.1 — 'git -C <scratch repo> commit' from the engaged root is ADMITTED" 0 "$ST"
expect_eq "18b: …with exactly one line naming both repositories" "$(jur_line "$R_SCR")" "$ERR"
expect_empty "18b: …and nothing on stdout" "$OUT"

run_hook "$(mk_payload "$R_COMMIT" "git -C $R_NEST commit -q --allow-empty -m x")"
expect_status "18c: AC-9.3 — a repository nested at <root>/.bionic/docs/record/x/bed is ADMITTED" 0 "$ST"
expect_eq "18c: …with the same one line" "$(jur_line "$R_NEST")" "$ERR"

# THE EXEMPTION IS THE GATE'S ALONE. A bionic:test-runner row committing into the scratch
# repo is outside the gate's jurisdiction and still inside the role arm's: refused, by ARM C.
R_JUR_RO="$(mk_repo jurisdiction-ro)"; block_plan "$R_JUR_RO"
roster_header > "$R_JUR_RO/.bionic/tmp/roster-$SID.state"
ro_rows "$R_JUR_RO" w19-jur-runner ajurrunner-0123456789abcdef bionic:test-runner
run_hook "$(mk_payload "$R_JUR_RO" "git -C $R_SCR commit -q --allow-empty -m x" ajurrunner-0123456789abcdef omit Bash w19-jur-runner)"
expect_status "18d: a bionic:test-runner's commit into the scratch repo is still REFUSED (the role arm is not exempt)" 2 "$ST"
expect_contains "18d: …by the role arm" "a read-only role never commits" "$ERR"
expect_contains "18d: …while the gate itself only names the boundary" "$(jur_line "$R_SCR" "$R_JUR_RO")" "$ERR"
expect_eq "18d: …so exactly one refusal is rendered" "1" "$(printf '%s\n' "$ERR" | grep -c 'refused')"

# A LINKED WORKTREE of the engaged repository shares its common dir and is inside: judged.
git -C "$R_COMMIT" worktree add -q "$R_COMMIT/.worktrees/19-T6" -b wt/19-T6 2>/dev/null
run_hook "$(mk_payload "$R_COMMIT" "git -C $R_COMMIT/.worktrees/19-T6 commit -m x")"
expect_status "18e: a commit from a linked worktree of the engaged repository is still judged — refused" 2 "$ST"
expect_absent "18e: …and never called outside" "outside the engaged repository" "$ERR"

# wave-25 T12: the words in front of git are names, read as the machine resolves them. On a
# case-blind filesystem `ENV`, `SUDO` and `BASH` run env, sudo and bash, so each of these is a
# commit the gate judges exactly as its lower-case form, and R_COMMIT's block_plan refuses it.
# Before T12 the reader left `ENV` as argv[0], saw no git, and the gate admitted the commit.
for _bw12 in "env -C $R_SCR git commit -q --allow-empty -m x|ENV -C $R_SCR git commit -q --allow-empty -m x" \
             "env --chdir=$R_SCR git commit -m x|Env --chdir=$R_SCR git commit -m x" \
             "sudo git commit -m x|SUDO git commit -m x" \
             "bash -c 'git commit -m x'|BASH -c 'git commit -m x'"; do
  run_hook "$(mk_payload "$R_COMMIT" "${_bw12%%|*}")"
  expect_status "18f: control — [${_bw12%%|*}] is judged and refused" 2 "$ST"
  run_hook "$(mk_payload "$R_COMMIT" "${_bw12#*|}")"
  expect_status "18f: [${_bw12#*|}] is judged and refused exactly as its lower-case form" 2 "$ST"
  expect_contains "18f: …by the evidence gate" "commit refused" "$ERR"
done



# ---------------------------------------------------------------------------
section "REQ7 — a redirected run is the budgeted run, and every refusal's remedy is admitted (wave-20 T4, D7)"
#
# AC-7.1. The budget arm compared a run claim, redirections and all, to the author's
# declared run — so the spelling every role file prescribes for saving evidence,
# `<command> 2>&1 | tee <log>`, was refused for exactly the run the brief declared
# (triage-B B1, driven there). Eight spellings, three kinds of budget: a shell suite on
# `suites_allowed=`, a non-shell runner on `re_executes=`, and a shell suite that is on the
# budget only through `Re-executes:`. Every cell is admitted where the bare command is.
#
# AC-7.3. Three refusals suggested a command the same wall then refused: the full-tree
# refusal named no single-suite spelling (B1a), the backgrounded-suite remedy echoed the
# `&` that tripped it (B2), and the budget one-liner cut a declared run mid-token (B3).
# Each remedy row below takes the suggestion OFF the refusal's own text and drives it back
# through the wall.
#
# fails-when: a spelling is refused where the bare command is admitted; a remedy the wall
# printed is refused when run; the one-liner carries half a run.

T4_LOG="$SANDBOX/t4-ev.log"
T4_BT='`'
# WHAT A REMEDY ROW RUNS WHEN THE REFUSAL SUGGESTED NOTHING: an off-budget suite, which every
# row below refuses — so a missing suggestion fails the "admitted" row instead of passing it
# on a command no wall has an opinion about.
T4_NONE='bash tests/no-suggestion-was-printed.test.sh'
t4_row() {  # <repo> <name> <key=value>... — an armed roster with one budgeted row for ACTOR
  bw_dispatched "$@"
}
t4_drive() {  # <repo> <command> [run_in_background] — as a dispatched test-runner, timeout set
  run_hook "$(mk_payload "$1" "$2" "$ACTOR" "${3:-omit}" Bash test-runner 600000)"
}
t4_admitted() {  # <label> <repo> <command>
  t4_drive "$2" "$3"
  expect_status "$1" 0 "$ST"
  expect_absent "$1 …with no refusal on stderr" "refused" "$ERR"
}
t4_refused() {  # <label> <repo> <command>
  t4_drive "$2" "$3"
  expect_status "$1" 2 "$ST"
}
t4_eight() {  # <kind label> <repo> <bare command>
  local k="$1" r="$2" j="$3"
  t4_admitted "REQ7 $k: the bare command is admitted (control)" "$r" "$j"
  t4_admitted "REQ7 $k: > p"            "$r" "$j > $T4_LOG"
  t4_admitted "REQ7 $k: >> p"           "$r" "$j >> $T4_LOG"
  t4_admitted "REQ7 $k: 2>&1"           "$r" "$j 2>&1"
  t4_admitted "REQ7 $k: &> p"           "$r" "$j &> $T4_LOG"
  t4_admitted "REQ7 $k: | tee p"        "$r" "$j | tee $T4_LOG"
  t4_admitted "REQ7 $k: 2>&1 | tee p"   "$r" "$j 2>&1 | tee $T4_LOG"
  t4_admitted "REQ7 $k: |& tee p"       "$r" "$j |& tee $T4_LOG"
  t4_admitted "REQ7 $k: || true"        "$r" "$j || true"
}

# --- AC-7.1, the three budget kinds ---
R7S="$(mk_repo t4shell)"
t4_row "$R7S" t4shell suites_allowed=alpha.test.sh suites_source=declared files=
t4_eight "shell suite" "$R7S" 'tests/run.sh --only alpha.test.sh'

R7N="$(mk_repo t4runner)"
t4_row "$R7N" t4runner suites_allowed=alpha.test.sh suites_source=declared files= \
  "re_executes=${T4_BT}npx jest --testPathPatterns 'x'${T4_BT}"
t4_eight "non-shell runner" "$R7N" "npx jest --testPathPatterns 'x'"

R7R="$(mk_repo t4reonly)"
t4_row "$R7R" t4reonly suites_allowed=none suites_source=declared files= \
  "re_executes=${T4_BT}tests/run.sh --only gamma.test.sh${T4_BT}"
t4_eight "Re-executes-only budget" "$R7R" 'tests/run.sh --only gamma.test.sh'

# THE NEGATIVE CONTROLS: normalising cannot widen the budget. A run that is not the declared
# one is still refused however it is redirected, and so is a suite neither channel names.
t4_refused "REQ7 control: the whole-tree jest, redirected, is still REFUSED against a narrower declaration" \
  "$R7N" "npx jest 2>&1 | tee $T4_LOG"
t4_refused "REQ7 control: an undeclared shell suite, redirected, is still REFUSED on a Re-executes-only row" \
  "$R7R" "tests/run.sh --only delta.test.sh > $T4_LOG 2>&1"

# THE DECLARED SIDE IS NORMALISED AT ITS ONE DECODE. A row written before the lift refused
# redirections (or by hand) carries one inside its marks; the rule is written once and held
# on both sides of the compare, so the bare command and its redirected spelling both match.
R7L="$(mk_repo t4legacy)"
t4_row "$R7L" t4legacy suites_allowed=alpha.test.sh suites_source=declared files= \
  "re_executes=${T4_BT}npx jest --testPathPatterns 'x' 2>&1${T4_BT}"
t4_admitted "REQ7 decode: a declared run stored with a redirect admits the bare command" \
  "$R7L" "npx jest --testPathPatterns 'x'"
t4_admitted "REQ7 decode: …and its tee spelling" \
  "$R7L" "npx jest --testPathPatterns 'x' 2>&1 | tee $T4_LOG"

# --- AC-7.3 (1): the full-tree refusal names the single-suite spelling, and it runs ---
t4_refused "REQ7 remedy 1: bash tests/run.sh --one is refused as the full tree" \
  "$R7S" 'bash tests/run.sh --one alpha.test.sh'
T4_R1=$(printf '%s\n' "$ERR" | grep -o 'tests/run.sh --only [A-Za-z0-9._-]*\.test\.sh' | head -1)
expect_eq "REQ7 remedy 1: …and the refusal names the per-suite spelling from the budget (the door, wave-28 T36)" \
  "tests/run.sh --only alpha.test.sh" "$T4_R1"
expect_contains "REQ7 remedy 1: …and says --one is the runner's internal worker mode" "--one" "$ERR"
t4_admitted "REQ7 remedy 1: …and that spelling, run, is admitted" "$R7S" "${T4_R1:-$T4_NONE}"

# --- AC-7.3 (2): the backgrounded-suite remedy carries no &, and it runs ---
t4_remedy_bg() {  # <label> <repo> <backgrounded command>
  local label="$1" r="$2" cmd="$3" fix
  t4_refused "$label: the backgrounded suite is refused" "$r" "$cmd"
  expect_contains "$label: …by the backgrounded arm" "a backgrounded suite" "$ERR"
  fix=$(printf '%s\n' "$ERR" | grep '| tee <evidence log>' | head -1 | sed 's/^[[:space:]]*//')
  expect_nonempty "$label: …suggesting a foreground command" "$fix"
  fix="${fix//<evidence log>/$T4_LOG}"
  t4_admitted "$label: …and the suggestion, run as printed, is admitted" "$r" "${fix:-$T4_NONE}"
}
t4_remedy_bg "REQ7 remedy 2a shell suite &" "$R7S" 'tests/run.sh --only alpha.test.sh &'
t4_remedy_bg "REQ7 remedy 2b runner &" "$R7N" "npx jest --testPathPatterns 'x' &"
t4_remedy_bg "REQ7 remedy 2c nohup, redirected, &" "$R7S" "nohup tests/run.sh --only alpha.test.sh > $T4_LOG 2>&1 &"
# THE TOOL-FLAG CASE: the text is already foreground, so the remedy is the flag.
t4_drive "$R7S" 'bash tests/alpha.test.sh' true
expect_status "REQ7 remedy 2d: run_in_background true on a suite is refused" 2 "$ST"
expect_contains "REQ7 remedy 2d: …and the remedy names the flag to clear" "run_in_background: false" "$ERR"

# --- AC-7.3 (3): the budget one-liner shows whole runs or a count, never half a run ---
R7W="$(mk_repo t4wire)"
t4_row "$R7W" t4wire suites_allowed=none suites_source=declared files= \
  "re_executes=${T4_BT}npm test${T4_BT} ${T4_BT}pytest tests/unit/test_widget_rendering_pipeline_end_to_end.py${T4_BT} ${T4_BT}go test ./internal/rendering/pipeline/...${T4_BT}"
t4_refused "REQ7 remedy 3: an undeclared run is refused" "$R7W" 'npx jest'
T4_LINE=$(printf '%s\n' "$ERR" | grep -m1 '^bionic: ')
expect_eq "REQ7 remedy 3: …on a verdict line whose marks are balanced" "0" \
  "$(( $(printf '%s' "$T4_LINE" | tr -cd '`' | wc -c) % 2 ))"
expect_contains "REQ7 remedy 3: …showing the first declared run whole, and the rest counted as runs" \
  "${T4_BT}npm test${T4_BT} +2 more" "$T4_LINE"
T4_R3=$(printf '%s' "$T4_LINE" | awk -F'`' 'NF >= 3 { print $2 }')
t4_admitted "REQ7 remedy 3: …and the run it shows, run, is admitted" "$R7W" "${T4_R3:-$T4_NONE}"
# NOTHING FITS: the count, never a cut. Three runs each wider than the line has room for.
R7X="$(mk_repo t4wirewide)"
T4_LONG="pytest tests/unit/test_a_very_long_module_name_that_cannot_fit_on_any_line.py -k"
t4_row "$R7X" t4wirewide suites_allowed=none suites_source=declared files= \
  "re_executes=${T4_BT}$T4_LONG one${T4_BT} ${T4_BT}$T4_LONG two${T4_BT} ${T4_BT}$T4_LONG three${T4_BT}"
t4_refused "REQ7 remedy 3b: an undeclared run against three over-wide runs is refused" "$R7X" 'npx jest'
T4_LINE=$(printf '%s\n' "$ERR" | grep -m1 '^bionic: ')
expect_contains "REQ7 remedy 3b: …and the line counts them as declared runs, printed below (wave-22 T4)" "3 declared runs (printed below)" "$T4_LINE"
expect_absent "REQ7 remedy 3b: …never a cut run" "pytest" "$T4_LINE"


# ---------------------------------------------------------------------------
section "19 — a subagent may not change a contract or the plan (wave-20 T9, REQ-4, AC-4.2)"
#
# `session-poker.sh amend` widens a live row's Files/Suites/Re-executes, `extend` re-opens a
# MET row, and `task-add` writes the bound plan. All three are the orchestrator's: an agent
# that could run them would grant itself a wider budget, or schedule its own work. The
# script cannot tell who called it (in-process teammates share the session's environment,
# research D2 REQ-4), so the refusal is the Bash wall's, keyed on the payload's top-level
# `agent_id` — the same partition ARM C and the budget arm take. The match is on the
# segment's argv after `cd …&&` and `env` prefixes, never on the text: a quoted mention is
# an argument to something else and is admitted.
#
# The roster exists (the session is armed) and carries the writer's own row, so the
# refusal is not an artefact of an unarmed session.
R_AM="$(mk_repo amendwall)"
AM_ID="aw20-T9sub-0123456789abcdef"
roster_header > "$R_AM/.bionic/tmp/roster-$SID.state"
roster_row_fixture "session=$SID" status=identified name=w20-sub "agent_id=$AM_ID" \
  subagent_type=bionic:senior-implementor >> "$R_AM/.bionic/tmp/roster-$SID.state"
AM_POKER="/opt/plugin/hooks/session-poker.sh"

am_refused() {  # <label> <command>
  run_hook "$(mk_payload "$R_AM" "$2" "$AM_ID" omit Bash w20-sub)"
  expect_status "$1 — refused from a subagent" 2 "$ST"
  expect_contains "$1 — …naming the rule" "a subagent may not change a contract or the plan" "$ERR"
}
am_admitted() {  # <label> <command> [agent_id]
  run_hook "$(mk_payload "$R_AM" "$2" "${3-$AM_ID}" omit Bash w20-sub)"
  expect_status "$1 — admitted" 0 "$ST"
  expect_absent "$1 — …with no contract refusal" "a subagent may not change a contract" "$ERR"
}

am_refused "19a: bash session-poker.sh amend" \
  "bash $AM_POKER amend w20-sub --files+ hooks/x.sh --reason 'need x'"
am_refused "19b: bash session-poker.sh extend" "bash $AM_POKER extend w20-sub 'more time'"
am_refused "19c: bash session-poker.sh task-add" \
  "bash $AM_POKER task-add T99 4 build 'x' bionic:implementor — 30 REQ-1 hooks/x.sh"
am_refused "19d: behind cd … &&" "cd $R_AM && bash $AM_POKER amend w20-sub --suites+ a.test.sh --reason r"
am_refused "19e: behind an env prefix with options and an assignment" \
  "env -u FOO BAR=1 bash $AM_POKER extend w20-sub r"
am_refused "19f: the script run directly, by relative path" "./hooks/session-poker.sh amend w20-sub --reason r --files+ a/b.sh"
# wave-25 T12: BASH runs bash on a case-blind filesystem, so the runner word folds here too.
am_refused "19f2: BASH session-poker.sh amend" "BASH $AM_POKER amend w20-sub --reason r --files+ a/b.sh"
am_refused "19f3: SUDO Sh session-poker.sh task-set" "SUDO Sh $AM_POKER task-set T2 status=landed"
am_refused "19g: second segment of a chain" "echo hi; bash hooks/session-poker.sh task-add a b c d e f g h i"
am_refused "19h: inside bash -c" "bash -c 'bash $AM_POKER amend w20-sub --reason r --files+ a/b.sh'"
# §ARM-A (hold) — wave-24 T7, REQ-4 AC-4.6, D1: a hold is the orchestrator's standing answer to a
# stand-down, so an agent that could run it would keep itself up.
am_refused "19o: bash session-poker.sh hold" "bash $AM_POKER hold w20-sub 'idle on purpose'"
# §ARM-A (plan-row verbs) — wave-24 T15, REQ-9 AC-9.4, D14: the five verbs write the bound plan,
# and an agent that could run them could move `current:` or mark its own row landed.
am_refused "19p: bash session-poker.sh task-set" "bash $AM_POKER task-set T2 status=landed"
am_refused "19q: bash session-poker.sh step-line" "bash $AM_POKER step-line T2 'landed at abc1234'"
am_refused "19r: bash session-poker.sh current" "bash $AM_POKER current 5"
am_refused "19s: bash session-poker.sh ledger-add" "bash $AM_POKER ledger-add T2 agent=w20-sub"
am_refused "19t: bash session-poker.sh ledger-set" "bash $AM_POKER ledger-set T2 landed=yes"
# §ARM-A (proof-add) — wave-26 T5, REQ-3 D5/D6: a proof line decides whether the full run is
# admitted, so an agent that could write one could prove its own head.
am_refused "19u: bash session-poker.sh proof-add" \
  "bash $AM_POKER proof-add floor record/wave-26-never-idle/floor.txt"
# §ARM-A (approve) — wave-26 T5 after T13: an approval line is what releases a gate act, so an
# agent that could write one would approve its own step.
am_refused "19v: bash session-poker.sh approve" "bash $AM_POKER approve release 'approved'"
# §ARM-A (waive) — wave-27 T9, D2: a waiver covers a reading question up to the working head, so
# an agent that could write one would waive the read of its own code.
am_refused "19v2: bash session-poker.sh waive" "bash $AM_POKER waive adversarial 'ship it'"
# §ARM-A (release-check) — wave-27 T16, D12, A-orch-44: the verb writes the release's check fact,
# so an agent that could run it could record the release check of its own head.
am_refused "19v3: bash session-poker.sh release-check" "bash $AM_POKER release-check"
# §ARM-A (finding-stated) — wave-28 T17, REQ-8 AC-8.7, D21: the sentence a deferral is stated by is
# what the release check reads against the changelog, so an agent that could write one could state
# its own deferral. The verb joins the existing arm's list; there is no second arm.
am_refused "19v4: bash session-poker.sh finding-stated" \
  "bash $AM_POKER finding-stated 'record/wave-01/r.md#1' 'a sentence'"
# §ARM-A (row-landed) — wave-28 T6, REQ-3 AC-3.2, D7, A-orch-81: the verb writes a row's status
# `landed`, its step line and its ledger line in one transaction, so an agent that could run it could
# mark its own row landed. `ready` runs it as a command, after the publish; a subagent never does.
am_refused "19v5: bash session-poker.sh row-landed" \
  "bash $AM_POKER row-landed T2 0123456789abcdef0123456789abcdef01234567 2026-10-07T03:30:00Z"
# §ARM-A (share) — wave-28 T10, REQ-2 AC-2.1 surfaces, D16: the share is the one number that bounds every heavy command on
# the machine, so an agent that could set it could widen its own room. Both forms are the main thread's: the arm reads the
# verb, not its operands. The verb joins the existing arm's list; there is no second arm.
am_refused "19v6: bash session-poker.sh share <n>" "bash $AM_POKER share 90"
am_refused "19v7: bash session-poker.sh share, the bare form" "bash $AM_POKER share"
# §ARM-A (finding-check) — wave-28 T41, REQ-8 AC-8.6, D33: a settlement re-rates a finding its reader
# could not settle, so an agent that could write one could settle the check on its own code. The verb
# joins the existing arm's list; there is no second arm.
am_refused "19v8: bash session-poker.sh finding-check" \
  "bash $AM_POKER finding-check 'record/wave-01/r.md#1' refuted record/wave-01/c.md"
# §ARM-A (finding-move) — wave-28 T42, REQ-8 AC-8.9, D34: a move carries a finding across the line on the
# user's word, so an agent that could run it could defer a finding against its own code. The verb joins the
# existing arm's list; there is no second arm.
am_refused "19v9: bash session-poker.sh finding-move" \
  "bash $AM_POKER finding-move 'record/wave-01/r.md#1' defer 'later' 'the docs pass'"
# §ARM-A (step-field) — wave-28 T8, REQ-3 AC-3.5, D17: the verb writes the fields the evidence gate reads (`head:`,
# `pass:`, `total:`), so an agent that could run it could write the evidence of its own step. The verb joins the
# existing arm's list; there is no second arm.
am_refused "19v10: bash session-poker.sh step-field" "bash $AM_POKER step-field 5 head=0123456"
am_refused "19v11: bash session-poker.sh task-split, with its children" \
  "bash $AM_POKER task-split T6 -- 'T8:the interface:20:lib/c.sh' 'T9:the rest:70:lib/d.sh'"
am_refused "19v12: bash session-poker.sh handoff" "bash $AM_POKER handoff"
# §ARM-A (land --by-hand) — wave-28 T3, REQ-5 AC-5.2, D9: the hand landing publishes a row past the
# line, so only the main thread may call it. The arm gains a second script name, not a second arm.
AM_SW="/opt/plugin/scripts/spawn-worktree.sh"
am_refused "19w: bash spawn-worktree.sh land --by-hand" "bash $AM_SW land .worktrees/x --by-hand --reason 'why'"
am_refused "19w1: behind cd … &&, the flag after the reason" "cd $R_AM && bash $AM_SW land .worktrees/x --reason r --by-hand"
run_hook "$(mk_payload "$R_AM" "bash $AM_SW land .worktrees/x --by-hand --reason 'why'" "$AM_ID" omit Bash w20-sub)"
expect_contains "19w2: …the detail names the script and the verb" "spawn-worktree.sh land --by-hand" "$ERR"
am_admitted "19w3: land --by-hand from the main thread" "bash $AM_SW land .worktrees/x --by-hand --reason 'why'" ""
am_admitted "19w4: a subagent's spawn-worktree.sh remove passes this arm" "bash $AM_SW remove .worktrees/x"
am_admitted "19w5: a subagent's quoted mention of the hand landing is not a call" "echo 'spawn-worktree.sh land x --by-hand'"

# THE PAIRED POSITIVES. The same verbs from the main thread (no agent_id) are the
# orchestrator's and pass this arm; a subagent's own read-only poker verbs pass; and a quoted
# mention is an argument to echo, not a call.
am_admitted "19i: amend from the main thread" "bash $AM_POKER amend w20-sub --reason r --files+ a/b.sh" ""
am_admitted "19j: task-add from the main thread" "bash $AM_POKER task-add a b c d e f g h i" ""
am_admitted "19j2: hold from the main thread" "bash $AM_POKER hold w20-sub 'idle on purpose'" ""
am_admitted "19j3: current from the main thread" "bash $AM_POKER current 5" ""
am_admitted "19j4: task-set from the main thread" "bash $AM_POKER task-set T2 status=landed" ""
am_admitted "19j5: proof-add from the main thread" \
  "bash $AM_POKER proof-add floor record/wave-26-never-idle/floor.txt" ""
am_admitted "19j6: approve from the main thread" "bash $AM_POKER approve release 'approved'" ""
am_admitted "19j7: waive from the main thread" "bash $AM_POKER waive adversarial 'ship it'" ""
am_admitted "19j8: release-check from the main thread" "bash $AM_POKER release-check" ""
am_admitted "19j9: finding-stated from the main thread" \
  "bash $AM_POKER finding-stated 'record/wave-01/r.md#1' 'a sentence'" ""
am_admitted "19j10: row-landed from the main thread" \
  "bash $AM_POKER row-landed T2 0123456789abcdef0123456789abcdef01234567 2026-10-07T03:30:00Z" ""
am_admitted "19j11: share <n> from the main thread" "bash $AM_POKER share 90" ""
am_admitted "19j12: share from the main thread" "bash $AM_POKER share" ""
am_admitted "19j13: finding-check from the main thread" \
  "bash $AM_POKER finding-check 'record/wave-01/r.md#1' refuted record/wave-01/c.md" ""
am_admitted "19j14: finding-move from the main thread" \
  "bash $AM_POKER finding-move 'record/wave-01/r.md#1' defer 'later' 'the docs pass'" ""
am_admitted "19j15: task-split from the main thread" \
  "bash $AM_POKER task-split T6 -- 'T8:the interface:20:lib/c.sh' 'T9:the rest:70:lib/d.sh'" ""

# EVERY VERB ON THE LIST, READ FROM THE LIST (wave-27 T16; team-lead ruling). The refusal line is
# `bionic: <verb> refused — <fact> (<fix>)`, capped at 100 columns by refuse.sh, and a verb long
# enough to overflow it is still refused, but by refuse.sh's own self-refusal, which names no rule.
# `release-check` overflowed it first (103 columns before the fix field was shortened). So each
# verb in `_wall_poker_contract_verb`'s case arm, read from walls.sh rather than retyped, must be
# refused from a subagent with exit 2 AND name the rule: the next verb added that overflows fails here.
AM_VERBS="$(awk '/^_wall_poker_contract_verb\(\)/ { f = 1 } f && /^}/ { exit }
  f && /^[[:space:]]*[a-z-]+(\|[a-z-]+)+\)[[:space:]]*$/ { s = $0; gsub(/[[:space:]\)]/, "", s); gsub(/\|/, " ", s); print s; exit }' \
  "$WALLS_LIB/walls.sh")"
expect_contains "19x0 precondition: the verb list is read from walls.sh's case arm (it names amend)" "amend" "$AM_VERBS"
expect_contains "19x0b …and the last verb added, release-check" "release-check" "$AM_VERBS"
expect_contains "19x0c …and the verb T17 added, finding-stated" "finding-stated" "$AM_VERBS"
expect_contains "19x0d …and the verb T6 added, row-landed" "row-landed" "$AM_VERBS"
expect_contains "19x0e …and the verb T10 added, share" " share " " $AM_VERBS "
expect_contains "19x0f …and the verb T41 added, finding-check" "finding-check" "$AM_VERBS"
expect_contains "19x0g …and the verb T42 added, finding-move" "finding-move" "$AM_VERBS"
# THE PLAN VERBS WAVE-30 ADDED (T14 matrix-render and discharge, T15 handoff, T17 task-split; A-orch-50,
# A-orch-52): each writes the bound plan, so each is the main thread's. Their refusal lines measure 99, 95,
# 93 and 96 columns (printf | wc -m, A-T14.10's measure), inside refuse.sh's 100.
for _am_v in matrix-render discharge handoff task-split; do
  expect_contains "19x0h …and the plan verb wave-30 added, $_am_v" " $_am_v " " $AM_VERBS "
done
for _am_v in $AM_VERBS; do
  am_refused "19x: every listed verb — $_am_v" "bash $AM_POKER $_am_v"
done
am_admitted "19k: a subagent's tick" "bash $AM_POKER tick"
am_admitted "19l: a subagent's interval" "bash $AM_POKER interval"
am_admitted "19m: a quoted mention" "echo 'bash $AM_POKER amend w20-sub'"
am_admitted "19n: a different script's amend verb" "bash tools/other.sh amend w20-sub"

# ---------------------------------------------------------------------------
section "20 — an UNROSTERED nested delegate is bound by the verb wall through its own agent_type (wave-20 T7b; review R15)"
#
# THE COMPOSITION HOLE (review R15, security high). Δ12 made a delegate read-only by "no
# Write/Edit tools PLUS REQ-3's commit refusal", and AC-9.2 made every nested delegate
# UNROSTERED by design — the orchestrator's roster is the depth-one ledger. ARM C read the role
# only from a roster row, so the one population Δ12 created was admitted for every
# commit-creating verb (walk §3, "no row" column).
#
# THE PAYLOAD SHAPE IS THE LIVE ONE (T12, live-rows-802ee6d.md §AC-9.2/9.4): a nested
# delegate's own Bash payload carries its `agent_id` AND its own `agent_type`. When no roster
# row carries that `agent_id`, the arm reads the role from `agent_type`; a rostered agent keeps
# the row reading (§17: a teammate's `agent_type` is its dispatch NAME), and a payload with no
# `agent_id` is the orchestrator and never reaches the arm.
R_NEST="$(mk_repo nested-unrostered)"
roster_header > "$R_NEST/.bionic/tmp/roster-$SID.state"
# the orchestrator's own writer, so the roster is a live one and the join has rows to miss
ro_rows "$R_NEST" w20-T7 awriter-0123456789abcdef bionic:senior-implementor
NEST_ID="a8b824d95c81dd996"

for _nt in bionic:researcher Explore bionic:test-runner; do
  run_hook "$(mk_payload "$R_NEST" 'git commit -m "x"' "$NEST_ID" omit Bash "$_nt")"
  expect_status "20a: an unrostered nested $_nt's 'git commit' is REFUSED" 2 "$ST"
  expect_contains "20a: …naming the role $_nt" "$_nt: a read-only role never commits" "$ERR"
  run_hook "$(mk_payload "$R_NEST" 'git merge wave/20-fixit-187' "$NEST_ID" omit Bash "$_nt")"
  expect_status "20a: an unrostered nested $_nt's 'git merge' is REFUSED" 2 "$ST"
  expect_contains "20a: …naming the role $_nt (merge)" "$_nt: a read-only role never commits" "$ERR"
  run_hook "$(mk_payload "$R_NEST" "env -C $R_NEST git commit -m x" "$NEST_ID" omit Bash "$_nt")"
  expect_status "20a: an unrostered nested $_nt's 'env -C <r> git commit' is REFUSED" 2 "$ST"
  expect_contains "20a: …naming the role $_nt (env -C)" "$_nt: a read-only role never commits" "$ERR"
done
# every verb of the eight, once, from the harness's no-write type the live bed drove
for _v in revert cherry-pick am rebase commit-tree update-ref; do
  run_hook "$(mk_payload "$R_NEST" "git $_v x" "$NEST_ID" omit Bash Explore)"
  expect_status "20b: an unrostered nested Explore's 'git $_v' is REFUSED" 2 "$ST"
done
# the detail says where the role came from: there is no roster row to name
run_hook "$(mk_payload "$R_NEST" 'git commit -m "x"' "$NEST_ID" omit Bash Explore)"
expect_contains "20c: the refusal's detail names the agent type, not a roster row" \
  "no roster row names you" "$ERR"
expect_eq "20c: …on ONE refusal line" "1" "$(printf '%s\n' "$ERR" | grep -c 'a read-only role never commits')"

# NOT A COMMIT: the read-only delegate's reading of history is its work.
run_hook "$(mk_payload "$R_NEST" 'git log -1 && git status' "$NEST_ID" omit Bash Explore)"
expect_status "20d: an unrostered nested Explore's 'git log' / 'git status' is ADMITTED" 0 "$ST"

# THE CONTROLS. Each is refused by nothing else here, so an arm that over-reaches turns one to 2.
for _nt in general-purpose bionic:implementor fork researcher; do
  run_hook "$(mk_payload "$R_NEST" 'git commit -m "x"' "$NEST_ID" omit Bash "$_nt")"
  expect_status "20e: an unrostered '$_nt'-typed payload's commit is ADMITTED (not a read-only type)" 0 "$ST"
  expect_absent "20e: …and the role arm says nothing ($_nt)" "read-only role" "$ERR"
done
run_hook "$(mk_payload "$R_NEST" 'git commit -m "x"')"
expect_status "20f: the orchestrator's own commit (no agent_id, no agent_type) is ADMITTED" 0 "$ST"
expect_absent "20f: …silently on this arm" "read-only role" "$ERR"
run_hook "$(mk_payload "$R_NEST" 'git commit -m "x"' '' omit Bash bionic:test-runner)"
expect_status "20g: a 'claude --agent' main session (agent_type, no agent_id) commits — ADMITTED, it is the orchestrator" 0 "$ST"
expect_absent "20g: …silently on this arm" "read-only role" "$ERR"

# A ROSTERED AGENT KEEPS THE ROW READING: the row wins over the payload's agent_type in both
# directions, so a teammate named like a read-only type is not refused and a read-only row is
# not escaped by its name.
ro_rows "$R_NEST" Explore arowimpl-0123456789abcdef bionic:implementor
run_hook "$(mk_payload "$R_NEST" 'git commit -m "x"' arowimpl-0123456789abcdef omit Bash Explore)"
expect_status "20h: a ROSTERED implementor whose agent_type reads 'Explore' is ADMITTED (the row wins)" 0 "$ST"
ro_rows "$R_NEST" w20-runner arowrun-0123456789abcdef bionic:test-runner
run_hook "$(mk_payload "$R_NEST" 'git commit -m "x"' arowrun-0123456789abcdef omit Bash general-purpose)"
expect_status "20h: a ROSTERED test-runner whose agent_type reads 'general-purpose' is REFUSED (the row wins)" 2 "$ST"
expect_contains "20h: …naming the row's role" "bionic:test-runner: a read-only role never commits" "$ERR"
ro_rows "$R_NEST" w20-norole arownorole-0123456789abcdef ""
run_hook "$(mk_payload "$R_NEST" 'git commit -m "x"' arownorole-0123456789abcdef omit Bash Explore)"
expect_status "20h: a ROSTERED row with an empty role is ADMITTED whatever its agent_type (§17g's reading)" 0 "$ST"

# 20i: ONE PICK, ONE SITE (wave-22 T10; review 2). The arm asks `roster_row_for_id` — the budget
# arm's own pick — which takes a row's FIRST `agent_id=` as its id. A forged row that carries a
# read-only role and a SECOND `agent_id=<id>` segment is not this agent's row (the old inline
# awk matched the id in any segment and would have refused it); a row naming the id in any
# other segment (`teammate_id=`) is not either. The payload's own agent_type then decides.
R_FORGE="$(mk_repo forged-segment)"
roster_header > "$R_FORGE/.bionic/tmp/roster-$SID.state"
FORGE_ID="aforged-0123456789abcdef"
printf '%s|agent_id=%s\n' "$(roster_row_fixture "session=$SID" status=identified name=w20-other \
  "agent_id=aother-0123456789abcdef" subagent_type=bionic:test-runner)" "$FORGE_ID" >> "$R_FORGE/.bionic/tmp/roster-$SID.state"
roster_row_fixture "session=$SID" status=identified name=w20-tm "agent_id=atm-0123456789abcdef" "teammate_id=$FORGE_ID" \
  subagent_type=bionic:test-runner >> "$R_FORGE/.bionic/tmp/roster-$SID.state"
expect_eq "20i meta: the forged roster holds the id in a second agent_id= segment" "1" \
  "$(grep -c "|agent_id=aother-0123456789abcdef|.*|agent_id=$FORGE_ID\$" "$R_FORGE/.bionic/tmp/roster-$SID.state")"
run_hook "$(mk_payload "$R_FORGE" 'git commit -m "x"' "$FORGE_ID" omit Bash general-purpose)"
expect_status "20i: an id found only in a SECOND agent_id= segment (or a teammate_id=) is no roster row — ADMITTED on its own type" 0 "$ST"
expect_absent "20i: …the role arm says nothing" "read-only role" "$ERR"
run_hook "$(mk_payload "$R_FORGE" 'git commit -m "x"' "$FORGE_ID" omit Bash bionic:test-runner)"
expect_status "20i: …and with no row the payload's own read-only type still binds (the fallback)" 2 "$ST"
expect_contains "20i: …saying no roster row names it" "no roster row names you" "$ERR"

# ---------------------------------------------------------------------------
section "21 — AC-5.3: the shared screen still says maybe for every spelling the parser reads (wave-24 T4, REQ-5, D6)"
#
# fails-when: `g\<newline>it`, `'g'it`, `"gi"t` or `\g\i\t` reads "provably not" through the new
# screen, or the screen's cache answers one command with another command's strip.
#
# THE SCREEN CHANGED SHAPE, NOT MEANING (wave-24-fixit-1811 T4). `_wall_mentions_git` used to
# strip the command itself with four `${v//…/}` passes, and so did three other screens in this
# process; bash 3.2 pays matches × length for each, and a quote-dense command timed the hook
# out. Now a literal `git` answers at once, and only a miss runs `_wall_screen` — one awk pass,
# cached at file scope keyed on the text. The T24 spellings are exactly the ones the literal
# check misses, so each of them is the awk path, read two ways: the function itself, and
# protect-main's refusal through the one process.
WALLS_LIB="${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/walls.sh"
mg_answer() {  # <command text>... -> one 0/1 per argument, space-joined, all in ONE process
  bash -c '. "$1" >/dev/null 2>&1; shift; o=""
    for c in "$@"; do _wall_mentions_git "$c"; o="$o$? "; done; printf "%s" "${o% }"' _ "$WALLS_LIB" "$@"
}
BW21_NL="$(printf 'g\\\n''it push origin main')"
expect_eq "21a: each obfuscated spelling is still 'maybe' (0), and a git-free quoted command is 'provably not' (1)" \
  "0 0 0 0 1" "$(mg_answer "$BW21_NL" "'g'it push origin main" '"gi"t push origin main' '\g\i\t push origin main' "echo 'hi' \"there\"")"
# THE CACHE IS KEYED ON THE TEXT: one process, three different commands asked in turn — a hit,
# a miss, the hit again. A single-slot cache that forgot to compare its key would answer the
# second with the first's strip, or the third with the second's.
expect_eq "21b: …asked in one process in turn, the cache never answers one command with another's strip" \
  "0 1 0" "$(mg_answer "'g'it push" "echo 'x'" "'g'it push")"

# 21d (wave-25 T12): the tier-2 screen in ANY letter case, answered by the same strip pass. A
# capitalised tier-2 word is a maybe, through the awk pass (a text holding a quote or a
# backslash, a continuation joining the word included) and through the fast path (a text with
# neither, which keeps the text as its strip); a text with no tier-2 word at all is not. The
# strip itself is the one the screen always made: the flag never reaches it.
t2_answer() {  # <command text>... -> "<rc>:<strip>" per argument, `|`-joined, all in ONE process
  bash -c '. "$1" >/dev/null 2>&1; shift; o=""
    for c in "$@"; do _wall_screen "$c"; _wall_tier2_any_case; o="$o$?:$_WALL_STRIPPED|"; done
    printf "%s" "$o"' _ "$WALLS_LIB" "$@"
}
BW21_T2NL="$(printf 'G\\\nIT clone x')"
expect_eq "21d: each capitalised tier-2 word is 'maybe' (0) by either path, prose is not (1), and the strip is unchanged" \
  "0:GIT clone x|0:NPX create-thing x y|0:Docker run x|0:GIT clone x|1:echo x y|1:ls -la|0:uvx tool|" \
  "$(t2_answer 'GIT clone x' 'NPX create-thing "x y"' "'Docker' run x" "$BW21_T2NL" "echo 'x y'" 'ls -la' 'uvx tool')"

for _bw21 in "$BW21_NL" "'g'it push origin main" '"gi"t push origin main' '\g\i\t push origin main'; do
  run_hook "$(mk_payload "$R_QUIET" "$_bw21")"
  expect_status "21c: [$(printf '%q' "$_bw21")] is still a push to main through the one process" 2 "$ST"
  expect_contains "21c: …refused in protect-main's own words" "main is a protected branch here" "$ERR"
done

# ---------------------------------------------------------------------------
section "§MEM — an engaged session never writes the auto-memory store (REQ-3, D16; AC-3.2)"
#
# THE INCIDENT (wave-23 A-orch-30). An engaged orchestrator obeyed the harness's standing
# memory directive in ONE Bash call: `cd <store> && cat >> <topic>.md <<'EOF' … EOF` then
# `sed -i '' …` on MEMORY.md. The store's path appeared only in the `cd`. The wall is
# `wall_memory_store` in payload/scripts/lib/walls.sh; this hook is its collector, handing it
# the store root and the command's write targets (`cmd_write_targets`, cmd-class.sh).
#
# THE STORE ROOT IS `${BIONIC_CLAUDE_HOME:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}}/projects/*/memory`.
# run_hook pins HOME inside the sandbox; the two variables are emptied on every row that does
# not set them, so the machine's own values cannot leak in.
R_MEM="$(mk_repo memwall)"
MEM_STORE="$FAKE_HOME/.claude/projects/-x/memory"
mkdir -p "$MEM_STORE"
MEM_NOENV=(BIONIC_CLAUDE_HOME= CLAUDE_CONFIG_DIR=)
MEM_REPLAY="$(printf 'cd %s && cat >> decision-reframe.md <<%sEOF%s\n- refined: goal, options, recommendation\nEOF\nsed -i %s%s %ss|^- \\[Decision reframe|- [Decision reframe|%s MEMORY.md' \
  "$MEM_STORE" "'" "'" "'" "'" "'" "'")"

mem_refused() {  # <label> <cwd> <command> [env…]
  local _l="$1" _d="$2" _c="$3"; shift 3
  run_hook "$(mk_payload "$_d" "$_c")" "$@"
  expect_status "§MEM $_l: refused" 2 "$ST"
  expect_contains "§MEM $_l: …naming the run's own record" "record/<wave>/assumptions.md" "$ERR"
  expect_contains "§MEM $_l: …and a rule proposal" "rule proposal" "$ERR"
}

mem_refused "replay of A-orch-30 (cd + heredoc append + sed -i)" "$R_MEM" "$MEM_REPLAY" "${MEM_NOENV[@]}"
mem_refused "redirect under ~" "$R_MEM" 'echo x > ~/.claude/projects/-x/memory/a.md' "${MEM_NOENV[@]}"
mem_refused "append under \$HOME" "$R_MEM" 'echo x >> $HOME/.claude/projects/-x/memory/a.md' "${MEM_NOENV[@]}"
mem_refused "redirect under \"\${HOME}\"" "$R_MEM" 'printf x > "${HOME}/.claude/projects/-x/memory/a.md"' "${MEM_NOENV[@]}"
mem_refused "tee" "$R_MEM" 'printf x | tee ~/.claude/projects/-x/memory/a.md' "${MEM_NOENV[@]}"
mem_refused "sed -i" "$R_MEM" "sed -i '' 's/a/b/' ~/.claude/projects/-x/memory/MEMORY.md" "${MEM_NOENV[@]}"
mem_refused "cp destination" "$R_MEM" 'cp /tmp/x ~/.claude/projects/-x/memory/' "${MEM_NOENV[@]}"
mem_refused "mv destination" "$R_MEM" 'mv /tmp/x ~/.claude/projects/-x/memory/b.md' "${MEM_NOENV[@]}"
mem_refused "touch" "$R_MEM" 'touch ~/.claude/projects/-x/memory/c.md' "${MEM_NOENV[@]}"
mem_refused "mkdir of the store itself" "$R_MEM" 'mkdir -p ~/.claude/projects/-x/memory' "${MEM_NOENV[@]}"
mem_refused "ln" "$R_MEM" 'ln -s /tmp/x ~/.claude/projects/-x/memory/d.md' "${MEM_NOENV[@]}"
# wave-25 T12: on a case-blind filesystem `TEE` runs tee and `CP` runs cp, so each writer is
# the same writer in any letter case, behind any prefix in any letter case.
mem_refused "TEE" "$R_MEM" 'printf x | TEE ~/.claude/projects/-x/memory/a.md' "${MEM_NOENV[@]}"
mem_refused "CP destination" "$R_MEM" 'CP /tmp/x ~/.claude/projects/-x/memory/' "${MEM_NOENV[@]}"
mem_refused "SUDO Mv destination" "$R_MEM" 'SUDO Mv /tmp/x ~/.claude/projects/-x/memory/b.md' "${MEM_NOENV[@]}"
mem_refused "BASH -c touch" "$R_MEM" "BASH -c 'touch ~/.claude/projects/-x/memory/c.md'" "${MEM_NOENV[@]}"
mem_refused "cd into the store, SED -i" "$R_MEM" \
  "cd ~/.claude/projects/-x/memory && SED -i '' 's/a/b/' MEMORY.md" "${MEM_NOENV[@]}"
# …and `CD` is NOT cd: /usr/bin/CD runs `builtin cd` in a child and moves nothing, so the tee
# below still writes into the store. A reader that folded CD would place it under /tmp.
mem_refused "CD moves nothing, so a relative write stays in the store" "$R_MEM" \
  "cd ~/.claude/projects/-x/memory && CD /tmp && tee a.md" "${MEM_NOENV[@]}"
mem_refused "cd into the store, relative sed -i" "$R_MEM" \
  "cd ~/.claude/projects/-x && cd memory && sed -i '' 's/a/b/' MEMORY.md" "${MEM_NOENV[@]}"
mem_refused "a dot-dot spelling" "$R_MEM" 'touch ~/.claude/projects/-x/notes/../memory/e.md' "${MEM_NOENV[@]}"
# THE ROOT MOVES WITH ITS VARIABLES, each spelled out in the command and as a literal path.
MEM_BCH="$SANDBOX/bch"; MEM_CCD="$SANDBOX/ccd"
mem_refused "BIONIC_CLAUDE_HOME, literal path" "$R_MEM" "touch $MEM_BCH/projects/-y/memory/a.md" \
  BIONIC_CLAUDE_HOME="$MEM_BCH" CLAUDE_CONFIG_DIR=
mem_refused "BIONIC_CLAUDE_HOME, spelled" "$R_MEM" 'echo x > "$BIONIC_CLAUDE_HOME/projects/-y/memory/a.md"' \
  BIONIC_CLAUDE_HOME="$MEM_BCH" CLAUDE_CONFIG_DIR=
mem_refused "CLAUDE_CONFIG_DIR, literal path" "$R_MEM" "touch $MEM_CCD/projects/-y/memory/a.md" \
  BIONIC_CLAUDE_HOME= CLAUDE_CONFIG_DIR="$MEM_CCD"
mem_refused "CLAUDE_CONFIG_DIR, spelled" "$R_MEM" 'echo x >> $CLAUDE_CONFIG_DIR/projects/-y/memory/a.md' \
  BIONIC_CLAUDE_HOME= CLAUDE_CONFIG_DIR="$MEM_CCD"
mem_refused "CLAUDE_CONFIG_DIR given as ~/…" "$R_MEM" 'touch ~/ccd/projects/-y/memory/a.md' \
  BIONIC_CLAUDE_HOME= 'CLAUDE_CONFIG_DIR=~/ccd'
# THE STORE IS THE ROOT'S, NOT EVERY `memory` DIRECTORY: with BIONIC_CLAUDE_HOME set, the
# default root is not the store — the precedence the collector resolves.
run_hook "$(mk_payload "$R_MEM" "touch $MEM_BCH/projects/-y/memory/a.md")" BIONIC_CLAUDE_HOME="$MEM_BCH" CLAUDE_CONFIG_DIR=
expect_status "§MEM precedence: BIONIC_CLAUDE_HOME's store is refused…" 2 "$ST"
run_hook "$(mk_payload "$R_MEM" 'touch ~/.claude/projects/-x/memory/a.md')" BIONIC_CLAUDE_HOME="$MEM_BCH" CLAUDE_CONFIG_DIR=
expect_status "§MEM precedence: …and ~/.claude's is not the store while BIONIC_CLAUDE_HOME names another" 0 "$ST"
# A RELATIVE TARGET WITH NO cd RESOLVES AGAINST THE PAYLOAD'S cwd. The cwd is the engaged
# repo, because engagement is the cwd's project's: a payload whose cwd IS the store resolves
# no engaged root, and every wall in this process stands down for it (A-T12.6).
mem_refused "relative target joined to the payload cwd" "$R_MEM" \
  'echo x > ../home/.claude/projects/-x/memory/a.md' "${MEM_NOENV[@]}"

# ---------------------------------------------------------------------------
section "§MEM-ok — reading the store, and writing elsewhere, stay open (AC-3.3)"
#
# THE SAME ENGAGED REPO, THE SAME EXTRACTOR (the hook's exit status) as §MEM above, so each
# admission here is read beside a refusal of the same shape. The fourth row is the wave's own
# AC-5.4 readback: it names the store AND redirects, to a path outside it.
for _mo in \
  'cat ~/.claude/projects/-x/memory/MEMORY.md' \
  'ls -la ~/.claude/projects/-x/memory' \
  'find ~/.claude/projects/-x/memory -newer .bionic/tmp/m -type f' \
  '{ find ~/.claude/projects/-x/memory -newer .bionic/tmp/m -type f; } > .bionic/docs/record/x.txt' \
  'rm -f ~/.claude/projects/-x/memory/old.md' \
  'tar -cf /tmp/mem.tar ~/.claude/projects/-x/memory' \
  'cp ~/.claude/projects/-x/memory/MEMORY.md .bionic/docs/record/memory-copy.md' \
  "$(printf 'cat > .bionic/docs/record/n.md <<%sEOF%s\necho x > ~/.claude/projects/-x/memory/a.md\nEOF' "'" "'")" \
  'touch ~/.claude/projects/-x/notes.md'; do
  run_hook "$(mk_payload "$R_MEM" "$_mo")" "${MEM_NOENV[@]}"
  expect_status "§MEM-ok [$(printf '%.60s' "$_mo")]: admitted" 0 "$ST"
  expect_absent "§MEM-ok …and no memory refusal on the wire" "assumptions.md" "$ERR"
done

# ---------------------------------------------------------------------------
section "§MEM-unengaged — a session that never invoked bionic writes its store freely (AC-3.4)"
#
# R_PLAIN carries no engagement marker. The same writes §MEM refuses, with the same env.
for _mu in \
  "$(printf '%s' "$MEM_REPLAY")" \
  'echo x > ~/.claude/projects/-x/memory/a.md' \
  'printf x | tee ~/.claude/projects/-x/memory/a.md' \
  "sed -i '' 's/a/b/' ~/.claude/projects/-x/memory/MEMORY.md" \
  'touch ~/.claude/projects/-x/memory/c.md'; do
  run_hook "$(mk_payload "$R_PLAIN" "$_mu")" "${MEM_NOENV[@]}"
  expect_status "§MEM-unengaged [$(printf '%.60s' "$_mu")]: admitted" 0 "$ST"
  expect_empty "§MEM-unengaged …silently" "$OUT$ERR"
done

# ---------------------------------------------------------------------------
section "§CDT — the later-cd scan reads every segment before the first git, in one split (T28)"
#
# `_eg_cd_targets` lists the `cd` targets after the command's first separator and before its
# first `git`, for the evidence gate's ambiguity check. T28 replaced its one-pass-per-segment
# loop with a single `read` split (the 64 KB timing is tests/hook-timeout.test.sh b4). These
# rows pin what the split must still answer: the four separators, the empty segments a
# doubled or trailing separator leaves, a `git` inside a segment ending the scan there, and
# nothing read after it. Each row answers the same on the loop it replaced.
# The function is defined past walls.sh's early `return`, so it is extracted the way 15g2
# extracts `_budget_wire_list`: awk between its own `()` line and its closing `}`, then eval.
cdt_of() {  # <command> -> the targets, `|`-terminated
  # git-argv.sh is sourced first, as the evidence gate always has it (wave-25 T12): the scan
  # asks it whether a segment's word is git in another letter case.
  bash -c '. "${1%/*}/git-argv.sh"; eval "$(awk "/^_eg_cd_targets\(\)/,/^}/" "$1")"; _eg_cd_targets "$2"
    printf "%s" "$_EG_CDS" | tr "\n" "|"' _ "$WALLS_LIB" "$1"
}
expect_contains "§CDT the extractor finds the function" "_eg_cd_targets()" \
  "$(awk '/^_eg_cd_targets\(\)/,/^}/' "$WALLS_LIB")"
expect_eq "§CDT the leading cd is not in the list; the second is" "/b|" "$(cdt_of 'cd /a && cd /b && git commit')"
expect_eq "§CDT every separator splits, and a bare cd is home" "/b|/c d|/e|~|" \
  "$(cdt_of "$(printf 'cd /a; cd /b|cd "/c d"&cd %s/e%s\ncd\ngit commit' "'" "'")")"
expect_eq "§CDT doubled and trailing separators name nothing" "/b|" "$(cdt_of 'cd /a;; ;cd /b ;')"
expect_eq "§CDT blank lines name nothing" "/b|" "$(cdt_of "$(printf 'cd /a\n\n\ncd /b\n\ngit commit')")"
expect_eq "§CDT a subshell opener comes off the front" "/b|" "$(cdt_of 'cd /a && (cd /b && git commit)')"
expect_eq "§CDT the first git ends the scan, inside a word too" "/b|" "$(cdt_of 'cd /a && cd /b && echo legit; cd /c')"
expect_eq "§CDT a cd after the commit is never read" "" "$(cdt_of 'cd /a && git commit -m x && cd /z')"
expect_eq "§CDT one segment has nothing after it to read" "" "$(cdt_of 'cd /a')"
# wave-25 T12: a commit spelled GIT ends the scan exactly as git does. Before T12 the scan cut
# only at the literal `git`, so a cd AFTER `GIT commit` was read as a second directory and the
# commit refused where its lower-case form passes. Only a segment whose WORD folds to git
# ends it: an `echo GITHUB` is no commit, and the scan reads on past it.
expect_eq "§CDT a cd after a GIT commit is never read, as after git" "" "$(cdt_of 'cd /a && GIT commit -m x && cd /z')"
expect_eq "§CDT …nor after Git, behind its own subshell opener" "/b|" "$(cdt_of 'cd /a && cd /b && (Git commit -m x); cd /z')"
expect_eq "§CDT an uppercase word that is not git ends nothing" "/b|" "$(cdt_of 'cd /a && echo GITHUB && cd /b && git commit -m x')"

section "§WAIT-CEIL — a wrapped suite run is detached; only a short call is bounded inside its call (wave-27 T6, AC-8.3; wave-30 T12, AC-3.1)"
#
# Critic 3 S2 (wave 26) found a writer on a full machine waiting for a place past its own call,
# which the harness then moved to the background. Wave-27 T6 bounded that wait with `--max-wait`,
# the staged timeout less ten seconds. Wave-30 T12 (D6, A-orch-7) replaces the bound with the
# detach: the shim runs the whole run, the wait at the gate included, in a session of its own and
# waits on it from the call, so a call the harness kills or backgrounds takes nothing with it and
# the same command typed again attaches. The wrap therefore carries `--detach` whatever the staged
# timeout is. A short call still carries `--kill-after`, and stays in the foreground: its limit is
# the point (farm-out's short arm). The checks keep their numbers (A-T12 mapping in the record).
wrap_mode_of() {  # the staged wrap's wait options before its `--`: detach, kill-after <s>, max-wait <s>; none
  updated_command_of | awk '{
    m = ""
    for (i = 1; i <= NF; i++) {
      if ($i == "--") break
      if ($i == "--detach") m = m " detach"
      else if ($i == "--kill-after" || $i == "--max-wait") m = m " " substr($i, 3) " " $(i + 1)
    }
    sub(/^ /, "", m); print (m == "" ? "none" : m)
  }'
}
R_WC="$(mk_repo waitceil)"
# ON THE BUDGET (wave-27 T5, D15): an agent suite with no recorded set is refused, never wrapped.
bw_dispatched "$R_WC" twaitceil suites_allowed=x.test.sh suites_source=declared files=
# (a) the eval: an agent's suite call with no timeout, raised by ARM R to 600 000 ms.
run_hook "$(mk_payload "$R_WC" 'tests/run.sh --only x.test.sh' "$ACTOR" omit Bash test-runner)" \
  BASH_MAX_TIMEOUT_MS=600000
expect_eq "WC1: an agent's suite call is staged at the harness maximum" "600000" "$(updated_timeout_of)"
expect_contains "WC2: …and wrapped (the reader works on this output)" "/scripts/booked.sh" "$(updated_command_of)"
expect_eq "WC3: …and handed to the shim detached, so the run outlives the call (AC-3.1)" "detach" "$(wrap_mode_of)"
expect_eq "WC4: …which is its one wait option: no --max-wait and no --kill-after beside it" "1" \
  "$(updated_command_of | awk '{ n = 0; for (i = 1; i <= NF; i++) { if ($i == "--") break; if ($i == "--detach" || $i == "--max-wait" || $i == "--kill-after") n++ } print n }')"
expect_regex "WC5: …named before --suites, the original command intact after --" \
  "^bash [^ ]+/scripts/booked\\.sh( --shell [^ ]+)?( --agent [^ ]+)? --detach --suites x\\.test\\.sh --runner -- 'tests/run\\.sh --only x\\.test\\.sh'\$" \
  "$(updated_command_of)"
# (b) under the tier-2 ceiling the mode does not follow the staged value.
run_hook "$(mk_payload "$R_WC" 'tests/run.sh --only x.test.sh' "$ACTOR" omit Bash test-runner 1800000)" \
  BASH_MAX_TIMEOUT_MS=1800000
expect_eq "WC6: a call staged at 1 800 000 ms is detached the same (the mode does not follow the timeout)" \
  "detach" "$(wrap_mode_of)"
# (c) the main thread's own timeout, where the main thread may run a suite (advisory mode).
R_WCA="$(mk_repo waitceil-adv)"
printf 'farm-out-mode: advisory\n' > "$R_WCA/.bionic/config.yaml"
run_hook "$(mk_payload "$R_WCA" 'bash tests/x.test.sh' '' omit Bash '' 300000)" BASH_MAX_TIMEOUT_MS=600000
expect_eq "WC7: a main-thread call keeps its own timeout, unrepaired" "300000" "$(updated_timeout_of)"
expect_eq "WC8: …and its run is detached too: a /clear of the main thread leaves it running" "detach" "$(wrap_mode_of)"
# (d) no timeout at all: no default ceiling is computed any more, whatever BASH_DEFAULT_TIMEOUT_MS says.
run_hook "$(mk_payload "$R_WCA" 'bash tests/x.test.sh')" BASH_MAX_TIMEOUT_MS=600000 BASH_DEFAULT_TIMEOUT_MS=
expect_eq "WC9: a call with no timeout is detached" "detach" "$(wrap_mode_of)"
run_hook "$(mk_payload "$R_WCA" 'bash tests/x.test.sh')" BASH_MAX_TIMEOUT_MS=600000 BASH_DEFAULT_TIMEOUT_MS=240000
expect_eq "WC10: …and so is one under BASH_DEFAULT_TIMEOUT_MS, when it is set" "detach" "$(wrap_mode_of)"
# (e) a short call is bounded by its kill limit and stays in the foreground.
run_hook "$(mk_payload "$R_WC" 'bash tests/x.test.sh' '' omit Bash '' 60000)" BASH_MAX_TIMEOUT_MS=600000
expect_contains "WC11: a short call is wrapped with its kill limit" "--kill-after 55" "$(updated_command_of)"
expect_eq "WC12: …which is its one wait option: not detached, no --max-wait (beside WC3 on the same reader)" \
  "kill-after 55" "$(wrap_mode_of)"
# (f) a staged timeout too small for the old margin is detached like any other.
run_hook "$(mk_payload "$R_WC" 'tests/run.sh --only x.test.sh' "$ACTOR" omit Bash test-runner)" BASH_MAX_TIMEOUT_MS=5000
expect_eq "WC13: a call staged at 5000 ms is detached, never handed a ceiling of 0 or 1" "detach" "$(wrap_mode_of)"


# ---------------------------------------------------------------------------
section "§EG-6 — from current: 6 a commit is admitted on the readings the run owes, not on a Step 6 line or a word (wave-27 T14; REQ-2 AC-2.2, D3)"
# ---------------------------------------------------------------------------
# The evidence gate, from `current: 6`, reads the section it already holds: for each question
# lib/proof.sh `facts_owed` deals at the plan's rigor, a `proved: kind=review … question=<q>` line
# whose newest is not `result=fail`, or a `waived: question=<q>` line later than it. The Step-6
# pointer line no longer answers for it, at either scale, and nothing new binds below Step 6.
# The reading lines here are written in the production writer's shape (lib/proof.sh `proof_line`,
# `proof_waiver_line`); the gate reads plan text whatever wrote it.
# eg6_reading, eg6_waiver, eg6_plan, eg6_gate, EG6_LIB, R_EG6 and H_EG6 are in tests/bash-walls.prelude.sh.
EG6_ALL="$(eg6_reading "$H_EG6" evidence pass)
$(eg6_reading "$H_EG6" adversarial flag)
$(eg6_reading "$H_EG6" structure pass)"

eg6_gate "$(eg6_plan 6 wave "" "- Step 6: review at record/w27/review.md")"
expect_status "EG6a AC-2.2: a wave plan at current: 6 with a Step 6 line and no fact is refused" 2 "$ST"
expect_contains "EG6a2 …in the gate's words, naming the refusal" "a reading question is unanswered" "$ERR"
expect_contains "EG6a3 …and each question it lacks" "- adversarial: no reading, and no waiver" "$ERR"
eg6_gate "$(eg6_plan 6 wave "$EG6_ALL")"
expect_status "EG6b worked answer 1: a reading for each question, the newest pass or flag, no Step 6 line: admitted" 0 "$ST"
eg6_gate "$(eg6_plan 6 wave "$(eg6_reading "$H_EG6" evidence pass)
$(eg6_reading "$H_EG6" adversarial pass)
$(eg6_reading "$H_EG6" structure pass record/w27/structure-old.md)
$(eg6_reading "$H_EG6" structure fail record/w27/structure-new.md)")"
expect_status "EG6c worked answer 2: the newest structure reading is result=fail, an older one pass: refused" 2 "$ST"
expect_contains "EG6c2 …naming structure and the failing line's evidence" \
  "- structure: the newest reading is result=fail (evidence=record/w27/structure-new.md), and no waiver is newer" "$ERR"
expect_absent "EG6c3 …and not the questions that hold (beside EG6c2 on the same refusal)" "- evidence:" "$ERR"
eg6_gate "$(eg6_plan 6 wave "$(eg6_reading "$H_EG6" evidence pass)
$(eg6_reading "$H_EG6" adversarial pass)
$(eg6_reading "$H_EG6" structure pass record/w27/structure-old.md)
$(eg6_reading "$H_EG6" structure fail record/w27/structure-new.md)
$(eg6_waiver "$H_EG6" structure)")"
expect_status "EG6d worked answer 3: a waived: question=structure line later than the failing reading: admitted" 0 "$ST"
eg6_gate "$(eg6_plan 6 wave "$(eg6_waiver "$H_EG6" structure)
$(eg6_reading "$H_EG6" evidence pass)
$(eg6_reading "$H_EG6" adversarial pass)
$(eg6_reading "$H_EG6" structure fail record/w27/structure-new.md)")"
expect_status "EG6d2 …a waiver EARLIER than the failing reading does not: refused" 2 "$ST"
expect_contains "EG6d3 …naming structure" "- structure: the newest reading is result=fail" "$ERR"
eg6_gate "$(eg6_plan 6 wave "$(eg6_reading "$H_EG6" evidence pass)
$(eg6_reading "$H_EG6" structure pass)")"
expect_status "EG6e worked answer 4: no adversarial reading and no waiver: refused" 2 "$ST"
expect_contains "EG6e2 …naming adversarial" "- adversarial: no reading, and no waiver" "$ERR"
eg6_gate "$(eg6_plan 6 wave "- adversarial: critic CONFIRMED
$(eg6_reading "$H_EG6" evidence pass)
$(eg6_reading "$H_EG6" structure pass)" "- Step 6: critic CONFIRMED, auditor CONFIRMED")"
expect_status "EG6f the word critic on a line is not a reading: refused" 2 "$ST"
expect_contains "EG6f2 …naming adversarial" "- adversarial: no reading, and no waiver" "$ERR"
eg6_gate "$(eg6_plan 7 wave "$(eg6_reading "$H_EG6" evidence pass)
$(eg6_reading "$H_EG6" structure pass)" "- Step 6: review at record/w27/review.md
- Step 7:
  n/a: no ADR owed by a fixture")"
expect_status "EG6g the predicate is a prefix condition: at current: 7 the same lack is refused" 2 "$ST"
expect_contains "EG6g2 …naming adversarial" "- adversarial: no reading, and no waiver" "$ERR"

# A LETTERED STEP IS ITS STEP (wave-27 T31; review pass 25 F1). The gate admits `current: <N>[ab]`,
# and the readings bind from 6 whatever the letter: each lettered value at or past 6 is refused as
# its step is, and 5 and 5b, below 6, owe nothing new.
for eg6c in 6a 6b 7a 8a 8b; do
  eg6_gate "$(eg6_plan "$eg6c" wave "" "- Step 6: review record/w27/review.md
- Step ${eg6c}: done record/generic-evidence.md")"
  expect_status "EG6l-${eg6c} F1 at current: ${eg6c} with no reading, the commit is refused as at its step" 2 "$ST"
  expect_contains "EG6l-${eg6c}b …naming the question it lacks" "- adversarial: no reading, and no waiver" "$ERR"
done
for eg6c in 5 5b; do
  eg6_gate "$(eg6_plan "$eg6c" wave "" | awk -v h="$H_EG6" '/^- Step 5: floor green/ {
    print "- Step 5:"; print "  cmd: bash tests/run.sh"; print "  pass: 10"; print "  total: 10"
    print "  output: record/generic-evidence.md"; print "  head: " h; print "  auditor: record/generic-evidence.md"
    if (c ~ /[ab]$/) print "- Step " c ": done record/generic-evidence.md"; next } { print }' c="$eg6c")"
  expect_status "EG6m-${eg6c} F1 at current: ${eg6c}, below Step 6, with no reading at all: admitted (nothing new binds)" 0 "$ST"
done

# THE OLDER ARMS BIND THE LETTERED STEPS TOO (wave-27 T67; review pass 46 N10). The matrix is a
# prefix contract from the Verify gate on: a REFUTED auditor cell refuses a commit at 6, and at each
# lettered step past it the same, every reading present so nothing else refuses. The walk arm binds
# from 5 the same way: a plan that owes a walk and narrates none is refused at 6a as at 6.
EG6_REFUTED() { eg6_plan "$1" wave "$EG6_ALL" "- Step 6: review record/w27/review.md
- Step ${1}: done record/generic-evidence.md" | sed 's/| AC-1 | T1 | discharged | see AC-1 | CONFIRMED |/| AC-1 | T1 | discharged | see AC-1 | REFUTED |/'; }
eg6_gate "$(eg6_plan 6 wave "$EG6_ALL")"
expect_status "EG6n0 control: at current: 6 every reading present and the auditor CONFIRMED, admitted" 0 "$ST"
for eg6c in 6 6a 7a 8a 8b; do
  eg6_gate "$(EG6_REFUTED "$eg6c")"
  expect_status "EG6n-${eg6c} N10 at current: ${eg6c} a REFUTED auditor cell refuses the commit, as at 6" 2 "$ST"
  expect_contains "EG6n-${eg6c}b …the matrix naming the row" "AC-1" "$ERR"
done
for eg6c in 6 6a 8b; do
  eg6_gate "$(eg6_plan "$eg6c" wave "$EG6_ALL" "- Step 6: review record/w27/review.md
- Step ${eg6c}: done record/generic-evidence.md" | sed 's/^walk: exempt$/walk: required/')"
  expect_status "EG6w-${eg6c} N10 at current: ${eg6c} a plan that owes a walk and narrates none is refused" 2 "$ST"
done

# THE WALL AND THE JUDGE READ ONE TEXT ONE WAY (the agreement row). The same section through the
# real gate and through lib/proof.sh `facts_state` at the head every line names: the questions the
# gate names are exactly the questions whose piece line the judge does not hold. evidence holds;
# adversarial failed and was then waived; structure passed and then failed.
EG6_AGREE="$(eg6_reading "$H_EG6" evidence pass)
$(eg6_reading "$H_EG6" adversarial fail)
$(eg6_waiver "$H_EG6" adversarial)
$(eg6_reading "$H_EG6" structure pass)
$(eg6_reading "$H_EG6" structure fail)"
eg6_gate "$(eg6_plan 6 task "$EG6_AGREE")"
EG6_WALL="$(printf '%s\n' "$ERR" | sed -n 's/^- \([a-z]*\): .*/\1/p' | tr '\n' ' ')"
EG6_JUDGE="$(bash -c '. "$1" && facts_state "$2" "$3"' _ "$EG6_LIB" "$R_EG6/.bionic/docs/plans/active.md" "$H_EG6" 2>/dev/null \
  | awk -F'\t' '$1 == "review" && $4 == "piece" && $5 != "covered" { printf "%s ", $2 }')"
expect_eq "EG6h precondition: the judge reads the fixture (its evidence line covered)" "covered" \
  "$(bash -c '. "$1" && facts_state "$2" "$3"' _ "$EG6_LIB" "$R_EG6/.bionic/docs/plans/active.md" "$H_EG6" 2>/dev/null \
    | awk -F'\t' '$2 == "evidence" && $4 == "piece" { print $5 }')"
expect_eq "EG6h2 §EG-6 agreement: the gate names structure alone" "structure " "$EG6_WALL"
expect_eq "EG6h3 …and the judge holds every question but structure, on the same text" "$EG6_WALL" "$EG6_JUDGE"

# THE TASK LANE (AC-2.2's second half): a task-scale row carrying only the word `critic`, from its
# own tree, at current: 6, is refused the same way, by the row.
R_EG6T="$(mk_repo eg6t)"
git -C "$R_EG6T" worktree add -q "$R_EG6T/.worktrees/27-T1" -b wt/27-T1 2>/dev/null
eg6_task_plan() {  # <lines> -> a task plan at current: 6 whose T1 row is done, its line carrying the words
  printf -- '---\ngoverning-skill: canonical-sdlc\ncanonical_sdlc_version: 14\nintent: build\nrigor: audited\nscale: task\n'
  printf 'deploy_target: none\nuse_worktree: false\nhas_ui: false\nwalk: exempt\n---\n# plan\n\n## SDLC State\n\n'
  printf 'current: 6\napproved-by: fixture 2026-09-22T00:00Z approved\n'
  printf -- '- T1: bash tests/x.test.sh 12/12, auditor CONFIRMED, critic CONFIRMED\n'
  [ -n "$1" ] && printf '%s\n' "$1"
  printf '\n## Tasks\n\n| id | intent | rigor | description | status | worktree |\n|---|---|---|---|---|---|\n'
  printf '| T1 | build | audited | the work | done | 27-T1 |\n'
}
printf '%s\n' "$(eg6_task_plan "")" > "$R_EG6T/.bionic/docs/plans/active.md"
bw_bind "$R_EG6T"
run_hook "$(mk_payload "$R_EG6T/.worktrees/27-T1" 'git commit -m "x"')" CLAUDE_PROJECT_DIR="$R_EG6T"
expect_status "EG6i AC-2.2: a task row carrying only the words auditor and critic is refused at current: 6" 2 "$ST"
expect_contains "EG6i2 …naming the row" "canonical-sdlc task T1 is at current: 6" "$ERR"
expect_contains "EG6i3 …and the question it lacks" "- adversarial: no reading, and no waiver" "$ERR"
H_EG6T="$(git -C "$R_EG6T" rev-parse HEAD)"
printf '%s\n' "$(eg6_task_plan "$(eg6_reading "$H_EG6T" evidence pass)
$(eg6_reading "$H_EG6T" adversarial pass)
$(eg6_reading "$H_EG6T" structure pass)")" > "$R_EG6T/.bionic/docs/plans/active.md"
run_hook "$(mk_payload "$R_EG6T/.worktrees/27-T1" 'git commit -m "x"')" CLAUDE_PROJECT_DIR="$R_EG6T"
expect_status "EG6j …and admitted once the section holds a reading of each question" 0 "$ST"

# THE DECLARED DEBT (wave-27 T31, T67; REQ-14 AC-14.3, D23; A-orch-121), the Step-5 row. A debt
# `land` wrote to the run's landing record holds every commit from Step 6 until a `proved:
# kind=floor` or `kind=task` line carries an `at=` later than its threshold: the red landing, and for
# an `approval:` token also its `approved:` line. The hook's collector reads the record into one fact
# the gate judges beside the section; a `landed red:` line in the plan changes nothing. FIXTURE
# FIDELITY: each debt is written by `land`'s own writer (lib/worktree.sh `_wt_debt_write`), into the
# record `land` names for this plan; the proof and approval lines in their production writers' shape.
eg6_floor_at() {  # <at> -> one floor proof line at that time
  bash -c '. "$1" && proof_line floor "$2" "$3" record/w27/floor-late.log' _ "$EG6_LIB" "$H_EG6" "$1"
}
EG6_WTLIB="${BIONIC_HOOKS_DIR}/../payload/scripts/lib/worktree.sh"
EG6_REC="$R_EG6/.bionic/docs/record/active.md/landing-proofs.log"
eg6_debt() {  # <token> <at> -> the record holds exactly this one debt on widget.test.sh
  rm -f "$EG6_REC"; mkdir -p "${EG6_REC%/*}"
  bash -c '. "$1" && _wt_debt_write "$2" "d$RANDOM" T9 wt/27-T9 "$3" widget.test.sh "$4" "$5"' _ "$EG6_WTLIB" "$EG6_REC" "$H_EG6" "$1" "$2"
}
EG6_NOTE="- T9: landed at record/w27/T9.md, landed red: widget.test.sh until approval:release at 2026-10-04T11:00:00Z"
EG6_APPROVED='approved: release by Dana Fixture 2026-10-04T13:00:00Z "ship it"'
eg6_debt approval:release 2026-10-04T11:00:00Z
eg6_gate "$(eg6_plan 6 wave "$EG6_ALL")"
expect_status "EG6k AC-14.3 every reading held, and a debt land wrote with no proof after its token cleared: refused" 2 "$ST"
expect_contains "EG6k2 …in its own words" "a declared red is still owed" "$ERR"
expect_contains "EG6k3 …naming the suite and its token" "- widget.test.sh: landed red until approval:release" "$ERR"
eg6_gate "$(eg6_plan 6 wave "$EG6_ALL
$(eg6_floor_at 2026-10-04T12:30:00Z)
$EG6_APPROVED")"
expect_status "EG6k4 …a floor proof dated BEFORE the approval does not cover it: refused" 2 "$ST"
expect_contains "EG6k5 …naming it still" "- widget.test.sh: landed red until approval:release" "$ERR"
eg6_gate "$(eg6_plan 6 wave "$EG6_ALL
$EG6_APPROVED
$(eg6_floor_at 2026-10-04T14:00:00Z)")"
expect_status "EG6k6 …and a floor proof after the approval clears it: admitted" 0 "$ST"
eg6_gate "$(eg6_plan 6 wave "$EG6_ALL
$(eg6_floor_at 2026-10-04T14:00:00Z)")"
expect_status "EG6k7 …while with no approved: line the same late proof clears nothing: refused" 2 "$ST"
eg6_debt approval:release sometime
eg6_gate "$(eg6_plan 6 wave "$EG6_ALL
$EG6_APPROVED
$(eg6_floor_at 2026-10-04T14:00:00Z)")"
expect_status "EG6k8 a debt whose at= is no <ISO-UTC> is never cleared: refused though approved and proved after" 2 "$ST"
# An ext: debt: the gate holds the ## SDLC State section, so it reads only the dated proof after the
# red landing's own time; whether the slug is still in a ## Tasks cell is the judge's.
eg6_debt ext:vendor-key 2026-10-05T04:00:00Z
eg6_gate "$(eg6_plan 6 wave "$EG6_ALL
$(eg6_floor_at 2026-10-05T03:00:00Z)")"
expect_status "EG6k9 an ext: debt whose only proof is dated before the red landing: refused" 2 "$ST"
expect_contains "EG6k9b …naming it" "- widget.test.sh: landed red until ext:vendor-key" "$ERR"
eg6_gate "$(eg6_plan 6 wave "$EG6_ALL
$(eg6_floor_at 2026-10-05T05:00:00Z)")"
expect_status "EG6k10 …and with a floor proof after it the gate admits (the slug test is the judge's)" 0 "$ST"
# B1 at the gate (wave-27 T67): approval, green, red. And the note changes nothing either way.
eg6_debt approval:release 2026-10-04T15:00:00Z
eg6_gate "$(eg6_plan 6 wave "$EG6_ALL
$EG6_APPROVED
$(eg6_floor_at 2026-10-04T14:00:00Z)")"
expect_status "EG6k11 B1 approval 13:00, green 14:00, red landing 15:00: refused" 2 "$ST"
eg6_gate "$(eg6_plan 6 wave "$EG6_ALL
$EG6_APPROVED
$(eg6_floor_at 2026-10-04T15:00:00Z)")"
expect_status "EG6k12 …a green floor at the landing's own second: refused" 2 "$ST"
eg6_gate "$(eg6_plan 6 wave "$EG6_ALL
$EG6_APPROVED
$(eg6_floor_at 2026-10-04T15:00:01Z)")"
expect_status "EG6k13 …one second after it: admitted" 0 "$ST"
rm -f "$EG6_REC"
eg6_gate "$(eg6_plan 6 wave "$EG6_ALL
$EG6_NOTE")"
expect_status "EG6k14 B3 a hand-written landed red: note with no debt in the record changes nothing: admitted" 0 "$ST"
eg6_debt approval:release 2026-10-04T11:00:00Z
eg6_gate "$(eg6_plan 6 wave "$EG6_ALL")"
expect_status "EG6k15 …and the record's debt with no note anywhere is refused (the same gate, the positive)" 2 "$ST"
# THE READ'S COST (A-orch-121): a record of 5,000 lines, every debt covered, adds at most a second to
# three commits through the hook. The lines are the writer's own shape, one written by it.
eg6_debt ext:vendor-key 2026-10-05T04:00:00Z
awk -v l="$(cat "$EG6_REC")" 'BEGIN { for (i = 1; i < 5000; i++) { x = l; sub(/id=[^ ]*/, "id=bulk" i, x); print x } }' >> "$EG6_REC"
expect_eq "EG6k16 precondition: the record holds 5,000 lines" "5000" "$(awk 'END { print NR }' "$EG6_REC")"
EG6_COV="$(eg6_plan 6 wave "$EG6_ALL
$(eg6_floor_at 2026-10-05T05:00:00Z)")"
EG6_T0=$SECONDS; for eg6i in 1 2 3; do eg6_gate "$EG6_COV"; done; EG6_TBIG=$((SECONDS - EG6_T0))
expect_status "EG6k16b …the covered commit is admitted through it" 0 "$ST"
rm -f "$EG6_REC"
EG6_T0=$SECONDS; for eg6i in 1 2 3; do eg6_gate "$EG6_COV"; done; EG6_TNONE=$((SECONDS - EG6_T0))
expect_true "EG6k16c …and three commits with it take at most a second more than without (${EG6_TBIG}s, ${EG6_TNONE}s)" \
  test "$EG6_TBIG" -le $((EG6_TNONE + 1))
# A PLAN VERB'S DRY COMMIT (wave-27 T76; review pass 60 P0-1; A-orch-170, A-orch-171). The verb binds
# a session `planverb-<pid>` to a COPY of the plan, `<plan>.<verb>-dry.<pid>`, with a marker naming the
# plan it was made from (`dry_of=`; written here in hooks/session-poker.sh `plan_verb_dry`'s shape).
# The collector reads that plan's record, and only for a plan verb's session and copy: a field in
# any other marker, or beside a copy not named from it, changes nothing.
EG6_P="$R_EG6/.bionic/docs/plans/active.md"
EG6_O="$R_EG6/.bionic/docs/plans/other.md"
EG6_OREC="$R_EG6/.bionic/docs/record/other.md/landing-proofs.log"
eg6_dry() {  # <plan text> <sid> <copy path> [<dry_of>] -> ST, ERR of a commit bound to that copy of the text
  local sid_was="$SID" m
  printf '%s\n' "$1" > "$EG6_P"; cp "$EG6_P" "$3"
  SID="$2"; m="$R_EG6/.bionic/tmp/engaged-$SID.state"
  { printf 'plan=%s\n' "$3"; [ -n "${4:-}" ] && printf 'dry_of=%s\n' "$4"; printf 'engaged_at=2026-10-05T00:00:00Z\n'; } > "$m"
  run_hook "$(mk_payload "$R_EG6" 'git commit -m "x"')"
  rm -f "$3" "$m"; SID="$sid_was"
}
eg6_debt ext:vendor-key 2026-10-05T04:00:00Z
EG6_OPEN="$(eg6_plan 6 wave "$EG6_ALL")"
eg6_gate "$EG6_OPEN"
expect_status "EG6k17 control: the real commit with the record's debt open is refused" 2 "$ST"
eg6_dry "$EG6_OPEN" planverb-4242 "$EG6_P.current-dry.4242" "$EG6_P"
expect_status "EG6k18 P0-1 the dry commit of the same text, bound to the copy, is refused as the real one" 2 "$ST"
expect_contains "EG6k18b …in the debt arm's words" "- widget.test.sh: landed red until ext:vendor-key" "$ERR"
eg6_dry "$EG6_OPEN" planverb-4242 "$EG6_P.current-dry.4242"
expect_status "EG6k19 …a copy's marker with no dry_of= names no record (the field is what is read, not the name)" 0 "$ST"
eg6_dry "$EG6_OPEN" planverb-4242 "$EG6_P.current-dry.9999" "$EG6_P"
expect_status "EG6k20 …and a copy whose pid is not the session's is not honoured (beside EG6k18)" 0 "$ST"
rm -f "$EG6_REC"; printf '# another plan\n' > "$EG6_O"; mkdir -p "${EG6_OREC%/*}"
bash -c '. "$1" && _wt_debt_write "$2" d-other T9 wt/27-T9 "$3" widget.test.sh ext:vendor-key 2026-10-05T04:00:00Z' _ "$EG6_WTLIB" "$EG6_OREC" "$H_EG6"
eg6_dry "$EG6_OPEN" planverb-4242 "$EG6_P.current-dry.4242" "$EG6_O"
expect_status "EG6k21 a dry_of= naming a plan the copy was not made from reads nothing of it (another plan's debt)" 0 "$ST"
eg6_dry "$EG6_OPEN" planverb-4242 "$EG6_O.current-dry.4242" "$EG6_O"
expect_status "EG6k21b …while that plan's own copy reads it (the positive on the same record)" 2 "$ST"
eg6_gate "$EG6_OPEN"
printf 'dry_of=%s\n' "$EG6_O" >> "$R_EG6/.bionic/tmp/engaged-$SID.state"
expect_contains "EG6k22 precondition: a real session's marker carries a planted dry_of=" "dry_of=$EG6_O" "$(cat "$R_EG6/.bionic/tmp/engaged-$SID.state")"
rm -f "$EG6_OREC"; eg6_debt ext:vendor-key 2026-10-05T04:00:00Z
mkdir -p "${EG6_OREC%/*}"; : > "$EG6_OREC"
run_hook "$(mk_payload "$R_EG6" 'git commit -m "x"')"
expect_status "EG6k22b …and its commit still reads its own plan's record: refused" 2 "$ST"
expect_contains "EG6k22c …naming its own debt" "- widget.test.sh: landed red until ext:vendor-key" "$ERR"
rm -f "$EG6_REC" "$EG6_OREC" "$EG6_O"

# ---------------------------------------------------------------------------
section "§EG-OPEN — an open 1.11.0-shaped plan continues untouched until Step 6 (wave-27 T14; REQ-10 AC-10.3, D19)"
# ---------------------------------------------------------------------------
# A plan written under 1.11.0 carries no reading line, no waiver and no new field. At `current: 4`
# and `current: 5` its commits are admitted as they were; the new arm binds from Step 6 alone.
eg6_open() {  # <current> <step lines> -> a 1.11.0-shaped audited wave plan
  printf -- '---\ngoverning-skill: canonical-sdlc\ncanonical_sdlc_version: 14\nintent: build\nrigor: audited\nscale: wave\n'
  printf 'deploy_target: none\nuse_worktree: false\nhas_ui: false\nwalk: exempt\n---\n# plan\n\n## SDLC State\n\n'
  printf 'current: %s\napproved-by: fixture 2026-09-22T00:00Z approved\n%s\n' "$1" "$2"
  printf '\n## Verification Matrix\n\nstack-health: n/a: no long-running serve\n\n'
  printf '| AC | tier | status | evidence | auditor |\n|---|---|---|---|---|\n| AC-1 | T1 | discharged | see AC-1 | CONFIRMED |\n\n'
  printf 'AC-1:\n  fails-when: the planted defect this eval must go red on\n  evidence: record/generic-evidence.md\n'
  printf '  tier-run: bash tests/x.test.sh\n  readback: the line it wrote\n'
}
eg6_gate "$(eg6_open 4 '- Step 4: dispatched, record/w27/dispatch.md')"
expect_status "EGO1 AC-10.3: a 1.11.0-shaped plan commits at current: 4 with no new field" 0 "$ST"
eg6_gate "$(eg6_open 5 "- Step 4: dispatched, record/w27/dispatch.md
- Step 5:
  cmd: bash tests/run.sh
  pass: 10
  total: 10
  output: record/generic-evidence.md
  head: $H_EG6
  auditor: record/generic-evidence.md")"
expect_status "EGO2 AC-10.3: …and at current: 5" 0 "$ST"
eg6_gate "$(eg6_open 6 '- Step 4: dispatched, record/w27/dispatch.md
- Step 5: floor green, record/w27/floor.log
- Step 6: review at record/w27/review.md')"
expect_status "EGO4 …and the same plan at current: 6 is refused for lacking a reading (D19's boundary)" 2 "$ST"


# ============================================================
section "§UNPLACED — an agent its start could not place runs the suite its printed remedy records (wave-27 T38; review pass 8 F3)"
# ============================================================
#
# Two id-less launches of one bionic type and a start that names neither: the recorder cannot
# choose, so no row carries the agent's id (SJ-d in tests/execution-recorder.test.sh), and until
# T38 the refusal's remedy was "nothing to widen until the orchestrator records one", an act no
# verb performed. The refusal now prints an `amend` line for the agent's id; the orchestrator runs
# it EXACTLY AS PRINTED, and the agent's next call runs the suite, wrapped and stamped.
#
# FIXTURE FIDELITY: both launch rows through `roster_row_fixture` → `roster_row` in the dispatch
# wall's shape, launched now; the start through the real hooks/execution-recorder.sh; the Bash
# payload the agent-context shape `mk_payload` builds, `agent_type` the plain dispatch's TYPE.
#
# fails-when: the refusal prints no runnable line; the line refuses or records nothing; the suite
# is still refused after it.
RU="$(mk_repo unplaced)"
roster_header > "$RU/.bionic/tmp/roster-$SID.state"
for _ru in one:alpha two:beta; do
  roster_row_fixture "session=$SID" status=intended "name=u-${_ru%%:*}" agent_id= \
    subagent_type=bionic:test-runner "tool_use_id=toolu_01bwunpl${_ru%%:*}" \
    "launched_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)" "suites_allowed=${_ru#*:}.test.sh" suites_source=declared \
    >> "$RU/.bionic/tmp/roster-$SID.state"
done
jq -n --arg s "$SID" --arg c "$RU" --arg a "$ACTOR" \
  '{session_id:$s, transcript_path:"/irrelevant.jsonl", cwd:$c, agent_id:$a,
    agent_type:"bionic:test-runner", hook_event_name:"SubagentStart"}' \
  | env HOME="$FAKE_HOME" BIONIC_PLUGINS_DIR="$SANDBOX/no-plugins" \
      CLAUDE_CODE_SESSION_ID="$SID" CLAUDE_PROJECT_DIR= bash "$REC_HOOK" >/dev/null 2>&1
expect_absent "UP0 precondition: the start was placed on neither launch" "agent_id=$ACTOR" "$(cat "$RU/.bionic/tmp/roster-$SID.state")"
expect_contains "UP0 precondition: …both launches are on the roster" "|name=u-two|" "$(cat "$RU/.bionic/tmp/roster-$SID.state")"
run_hook "$(mk_payload "$RU" 'tests/run.sh --only alpha.test.sh' "$ACTOR" "" Bash bionic:test-runner 600000)" BIONIC_WALL_VERBOSE=1
expect_status "UP1 the unplaced agent's suite is refused" 2 "$ST"
expect_contains "UP2 …because no row carries its id" "no roster row carries your agent id $ACTOR" "$ERR"
expect_absent "UP3 …a bionic type is not told its type is the reason" "is not a bionic: role" "$ERR"
UP_FIX=$(printf '%s\n' "$ERR" | grep -F 'widen it: ' | head -1)
UP_CMD="${UP_FIX#*widen it: }"; UP_CMD="${UP_CMD% (main runs it)}"
expect_contains "UP4 …printing the amend line for its id" "session-poker.sh amend $ACTOR --suites+ alpha.test.sh --reason" "$UP_CMD"
mkdir -p "$FAKE_HOME/.claude/projects/-unplaced/$SID/subagents"
: > "$FAKE_HOME/.claude/projects/-unplaced/$SID.jsonl"
: > "$FAKE_HOME/.claude/projects/-unplaced/$SID/subagents/agent-$ACTOR.jsonl"
# No remedy line printed is a failure, not an empty command run (`bash -c ""` exits 0): T59, pass 36 S3.
if [ -n "$UP_FIX" ]; then
  UP_OUT=$( cd "$RU" && env HOME="$FAKE_HOME" CLAUDE_CONFIG_DIR="$FAKE_HOME/.claude" BIONIC_PLUGINS_DIR="$SANDBOX/no-plugins" \
    CLAUDE_CODE_SESSION_ID="$SID" CLAUDE_PROJECT_DIR= bash -c "$UP_CMD" 2>&1 ); UP_RC=$?
else
  UP_OUT=""; UP_RC=1
fi
expect_status "UP5 the line, run as printed by the orchestrator, exits 0" 0 "$UP_RC"
expect_contains "UP6 …and says it recorded the set" "poker: amended — $ACTOR" "$UP_OUT"
run_hook "$(mk_payload "$RU" 'tests/run.sh --only alpha.test.sh' "$ACTOR" "" Bash bionic:test-runner 600000)"
expect_status "UP7 …and the agent's next call runs the suite" 0 "$ST"
expect_contains "UP8 …wrapped and stamped with that suite" "--suites alpha.test.sh" "$(updated_command_of)"
run_hook "$(mk_payload "$RU" 'tests/run.sh --only beta.test.sh' "$ACTOR" "" Bash bionic:test-runner 600000)"
expect_status "UP9 a suite the line did not name is still refused (beta is the other launch's)" 2 "$ST"
# The row amend wrote names no role (none is known for an agent no launch was joined to), so the
# read-only arm answers from the payload's own type, as for an agent with no row: a test-runner
# still never commits. §17g's reading (an empty role on a dispatched row is admitted) stands.
run_hook "$(mk_payload "$RU" 'git commit -m "x"' "$ACTOR" omit Bash bionic:test-runner)"
expect_contains "UP10 the unplaced test-runner's commit is refused by its own type" \
  "bionic:test-runner: a read-only role never commits" "$ERR"

section "§LOOPVAR — a suite run through a glob loop or a bare variable is refused from a subagent (wave-28 T11, D13)"
# ============================================================
#
# Wave-27 review pass 8 F5: the walk's hand-copied loop `{ for s in tests/*.test.sh; do if bash
# "$s"; … } | tee` read class none, so a budgeted agent ran every suite in the tree unrefused. The
# classifier now claims the variable (tests/cmd-class.test.sh §LOOP T11), and the budget's
# unexpanded-name arm refuses it in one line inside 100 columns (the suites run with
# BIONIC_REFUSE_STRICT=1, so a longer first line refuses its own call). Beside it, a loop over
# files that are plainly no suite passes, on the same agent and row.
#
# fails-when: the glob loop or the bare variable passes; the refusal is not the unexpanded arm.
R_LV="$(mk_repo loopvar)"
bw_dispatched "$R_LV" t11writer "suites_allowed=archive.test.sh" suites_source=declared files=
for _lv in '{ for s in tests/*.test.sh; do if bash "$s"; then :; fi; done; } | tee log' 'bash "$SUITE"'; do
  run_hook "$(mk_payload "$R_LV" "$_lv" "$ACTOR" omit Bash test-runner)"
  expect_status "LV1 [$_lv] is refused" 2 "$ST"
  LV_LINE="$(printf '%s\n' "$ERR" | /usr/bin/grep -m1 '^bionic: ')"
  # Since wave-28 T36 the one door answers first: a bare form from an agent is refused naming
  # `tests/run.sh --only`, before the budget's unexpanded-name arm is reached.
  expect_contains "LV2 …by the door's line (wave-28 T36), ahead of the unexpanded-name arm" "use tests/run.sh --only " "$LV_LINE"
  expect_eq "LV3 …in one line of at most 100 columns" "yes" "$([ -n "$LV_LINE" ] && [ "${#LV_LINE}" -le 100 ] && echo yes || echo no)"
done
run_hook "$(mk_payload "$R_LV" 'for f in docs/*.md; do bash "$f"; done' "$ACTOR" omit Bash test-runner)"
expect_status "LV4 a loop over files that are plainly no suite passes" 0 "$ST"
expect_absent "LV4 …with no suite refusal" "unexpanded name" "$ERR"

section "§DOOR — a dispatched agent runs a suite through tests/run.sh --only, never bare (wave-28 T36; D27, AC-10.1, AC-10.3)"
# ============================================================
#
# THE ONE DOOR. A bare suite command typed by a dispatched agent runs in whatever world the
# agent's shell gives it; `tests/run.sh --only <suite>` runs it in the runner's (the interpreter
# pin, the environment, the adoption wall, one gate ask per suite). So the wall refuses every bare
# form the classifier reads — the literal path, the rule-5 evidence shape, a script at argv[0], a
# literal loop, a glob loop, a bare variable — in one line of at most 100 columns that names the
# door; the door form itself goes on to the budget like a suite file, and is never the full tree.
# The main thread is not refused: a person's bare run keeps the seam's pin
# (tests/interpreter-pin.test.sh §2 drives that pin on a hand run).
#
# fails-when: an agent's bare run passes, or its refusal omits `tests/run.sh --only`; the door
# form is refused on its own budget or read as the full tree; the main thread's bare run is refused.
R_DR="$(mk_repo door)"
bw_dispatched "$R_DR" t36writer "suites_allowed=alpha.test.sh" suites_source=declared files=
dr_line() { printf '%s\n' "$ERR" | /usr/bin/grep -m1 '^bionic: '; }
dr_fits() { local l; l="$(dr_line)"; [ -n "$l" ] && [ "${#l}" -le 100 ] && echo yes || echo no; }
for _dr in 'bash tests/alpha.test.sh' \
           "cd '$R_DR' || exit 1; LOG=x.log; set -o pipefail; bash tests/alpha.test.sh 2>&1 | tee \"\$LOG\"; rc=\$?; echo \"rc=\$rc\" >> \"\$LOG\"; exit \$rc" \
           './tests/alpha.test.sh' 'bash -x tests/alpha.test.sh'; do
  run_hook "$(mk_payload "$R_DR" "$_dr" "$ACTOR" omit Bash test-runner 1800000)"
  expect_status "DOOR.1 [$_dr] an on-budget bare run from an agent is refused" 2 "$ST"
  expect_contains "DOOR.2 [$_dr] …with one line naming the door and the suite" \
    "use tests/run.sh --only alpha.test.sh" "$(dr_line)"
  expect_eq "DOOR.3 [$_dr] …of at most 100 columns" "yes" "$(dr_fits)"
done
for _dr in 'for s in alpha beta; do bash "tests/$s.test.sh"; done' \
           'for s in tests/*.test.sh; do bash "$s"; done' 'bash "$SUITE"' \
           'while read -r s; do bash "$s"; done < list'; do
  run_hook "$(mk_payload "$R_DR" "$_dr" "$ACTOR" omit Bash test-runner 1800000)"
  expect_status "DOOR.4 [$_dr] a loop or variable form from an agent is refused" 2 "$ST"
  expect_contains "DOOR.5 [$_dr] …by the door's line" "use tests/run.sh --only " "$(dr_line)"
  expect_eq "DOOR.6 [$_dr] …of at most 100 columns" "yes" "$(dr_fits)"
done
run_hook "$(mk_payload "$R_DR" 'bash tests/canonical-sdlc-governing-skill.test.sh' "$ACTOR" omit Bash test-runner 1800000)"
expect_contains "DOOR.7 a suite name too long for the line still names the door, by placeholder" \
  "use tests/run.sh --only <suite>" "$(dr_line)"
expect_eq "DOOR.7b …and stays inside 100 columns" "yes" "$(dr_fits)"
expect_contains "DOOR.7c …while the detail carries the suite's own command" \
  "tests/run.sh --only canonical-sdlc-governing-skill.test.sh" "$ERR"

# The door itself: on the budget it passes, wrapped for the runner; off it, the budget refuses.
run_hook "$(mk_payload "$R_DR" 'tests/run.sh --only alpha.test.sh' "$ACTOR" omit Bash test-runner 1800000)"
expect_ne "DOOR.8 the door form on the budget is not refused" "2" "$ST"
expect_absent "DOOR.8b …with no refusal line" "refused" "$ERR"
expect_regex "DOOR.9 …it is wrapped, its suite named, and the shim told it is the runner" \
  "booked\\.sh.* --suites alpha\\.test\\.sh --runner -- " "$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.updatedInput.command // ""' 2>/dev/null)"
run_hook "$(mk_payload "$R_DR" "cd '$R_DR' || exit 1; LOG=x.log; set -o pipefail; bash tests/run.sh --only alpha.test.sh 2>&1 | tee \"\$LOG\"; rc=\$?; echo \"rc=\$rc\" >> \"\$LOG\"; exit \$rc" "$ACTOR" omit Bash test-runner 1800000)"
expect_ne "DOOR.10 the door in the evidence shape passes on the budget" "2" "$ST"
run_hook "$(mk_payload "$R_DR" 'tests/run.sh --only beta.test.sh' "$ACTOR" omit Bash test-runner 1800000)"
expect_status "DOOR.11 the door form naming a suite off the budget is refused" 2 "$ST"
expect_contains "DOOR.12 …by the budget arm, naming the budget" "allowed: alpha.test.sh" "$(dr_line)"
expect_absent "DOOR.13 …and never as the full tree" "full tree" "$ERR"
run_hook "$(mk_payload "$R_DR" 'tests/run.sh --only alpha.test.sh beta.test.sh' "$ACTOR" omit Bash test-runner 1800000)"
expect_status "DOOR.14 one off-budget name among several refuses the call" 2 "$ST"

# The main thread: the door's arm never speaks there. Engaged, in farm-out's advisory mode (as
# WC7 drives it), so the one wall that may refuse a main-thread suite stands aside.
R_DRM="$(mk_repo door-main)"
printf 'farm-out-mode: advisory\n' > "$R_DRM/.bionic/config.yaml"
bw_dispatched "$R_DRM" t36main "suites_allowed=beta.test.sh" suites_source=declared files=
run_hook "$(mk_payload "$R_DRM" 'bash tests/alpha.test.sh' "" omit Bash "" 1800000)"
expect_ne "DOOR.15 the main thread's bare run is not refused" "2" "$ST"
expect_absent "DOOR.16 …and the door's line is not printed" "tests/run.sh --only" "$ERR"
expect_regex "DOOR.17 …it is wrapped as it always was, so the suite it runs gets the seam's pin" \
  "booked\\.sh.* --suites alpha\\.test\\.sh -- " "$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.updatedInput.command // ""' 2>/dev/null)"

# THE DOOR FIRES ONLY WHERE THE PROJECT HAS IT (wave-28 T54, D27; A-orch-124). bionic bears on
# other projects: one with suites under tests/ and no tests/run.sh, or a tests/run.sh of its own
# that takes no `--only`, has no door to be pointed at, so an agent's ON-BUDGET bare run there goes
# on to the budget as it did before T36 (the verdict and the rewrite of 903c971b). The project is
# the tree the shim asks from (`cd <dir>` or the payload's cwd, read by `_bsg_cd_walk`), not the
# repository the hook's root names. The budget arm itself is untouched: an off-budget bare run in
# a project without the door is refused by it, so the door's absence widens nothing.
#
# fails-when: a project without the door has its on-budget bare run refused; a project with the
# door has it passed; an off-budget run passes without the door; the tree read is the root's and
# not the command's.
R_NR="$(mk_repo door-norunner yes none)"
R_NO="$(mk_repo door-noonly yes noonly)"
bw_dispatched "$R_NR" t54writer "suites_allowed=alpha.test.sh" suites_source=declared files=
expect_eq "DOOR.21a the no-runner world has no tests/run.sh" "absent" "$([ -e "$R_NR/tests/run.sh" ] && echo present || echo absent)"
expect_eq "DOOR.21a2 the no-flag world has a tests/run.sh that never says --only" "present/0" \
  "$([ -f "$R_NO/tests/run.sh" ] && echo present || echo absent)/$(grep -cF -e '--only' "$R_NO/tests/run.sh")"
expect_eq "DOOR.21a3 the door world's tests/run.sh says --only" "yes" "$(grep -qF -e '--only' "$R_DR/tests/run.sh" && echo yes || echo no)"
for _wd in "$R_NR" "$R_NO"; do
  bw_dispatched "$_wd" t54writer "suites_allowed=alpha.test.sh" suites_source=declared files=
  for _dr in 'bash tests/alpha.test.sh' './tests/alpha.test.sh' \
             "cd '$_wd' || exit 1; LOG=x.log; set -o pipefail; bash tests/alpha.test.sh 2>&1 | tee \"\$LOG\"; rc=\$?; echo \"rc=\$rc\" >> \"\$LOG\"; exit \$rc"; do
    run_hook "$(mk_payload "$_wd" "$_dr" "$ACTOR" omit Bash test-runner 1800000)"
    expect_status "DOOR.21 [${_wd##*/}] [$_dr] an on-budget bare run passes where the project has no door" 0 "$ST"
    expect_absent "DOOR.21b …with no refusal line" "refused" "$ERR"
    expect_regex "DOOR.21c …it is wrapped for the shim exactly as before the door: its suite named, no --runner" \
      "booked\\.sh.* --agent t54writer .*--detach .*--suites alpha\\.test\\.sh -- " "$(updated_command_of)"
    expect_absent "DOOR.21d …and the shim is not told it is the runner" " --runner" "$(updated_command_of)"
  done
  run_hook "$(mk_payload "$_wd" 'bash tests/beta.test.sh' "$ACTOR" omit Bash test-runner 1800000)"
  expect_status "DOOR.22 [${_wd##*/}] an OFF-budget bare run is still refused without the door" 2 "$ST"
  expect_contains "DOOR.22b …by the budget arm, naming the budget" "allowed: alpha.test.sh" "$(dr_line)"
  expect_absent "DOOR.22c …and not by the door, which has nothing to point at" "use tests/run.sh --only" "$ERR"
  expect_eq "DOOR.22d …in a line of at most 100 columns" "yes" "$(dr_fits)"
done
# The same extractor and the same call in a project WITH the door: refused, the line exactly as T36 printed it.
run_hook "$(mk_payload "$R_DR" 'bash tests/alpha.test.sh' "$ACTOR" omit Bash test-runner 1800000)"
expect_status "DOOR.23 a project whose tests/run.sh takes --only still refuses the on-budget bare run" 2 "$ST"
expect_eq "DOOR.23b …with the door's line, text unchanged" \
  "bionic: suite-run refused — use tests/run.sh --only alpha.test.sh (one door)" "$(dr_line)"

# THE RUNNER HALF (A-orch-125): the same predicate governs the call that NAMES the door. Where the
# project has none, `tests/run.sh --only <suite>` is the full tree under the project's own runner,
# judged as at 903c971b (the budget names the full tree, never the shim's `--runner`), so a runner
# that ignores the flag cannot be handed an admission it never asks for.
bw_dispatched "$R_NO" t54writer "suites_allowed=alpha.test.sh" suites_source=declared files=
run_hook "$(mk_payload "$R_NO" 'tests/run.sh --only alpha.test.sh' "$ACTOR" omit Bash test-runner 1800000)"
expect_status "DOOR.29 a runner without --only, called with --only, is the full tree: refused" 2 "$ST"
expect_contains "DOOR.29b …by the full-tree arm, as at 903c971b" "full tree refused; allowed: alpha.test.sh" "$(dr_line)"
expect_absent "DOOR.29c …and the door has no say" "(one door)" "$(dr_line)"
bw_dispatched "$R_NO" t54full "suites_allowed=run.sh" suites_source=declared files=
run_hook "$(mk_payload "$R_NO" 'tests/run.sh --only alpha.test.sh' "$ACTOR" omit Bash test-runner 1800000)"
expect_status "DOOR.30 …and passes on a row that carries the full tree" 0 "$ST"
expect_regex "DOOR.30b …wrapped for the shim" "booked\\.sh.* --suites [^ ]+ -- " "$(updated_command_of)"
expect_absent "DOOR.30c …with no --runner, so the gate is asked for the run" " --runner" "$(updated_command_of)"
bw_dispatched "$R_NO" t54writer "suites_allowed=alpha.test.sh" suites_source=declared files=
R_NOM="$(mk_repo door-main-noonly yes noonly)"
printf 'farm-out-mode: advisory\n' > "$R_NOM/.bionic/config.yaml"
bw_dispatched "$R_NOM" t54main "suites_allowed=beta.test.sh" suites_source=declared files=
run_hook "$(mk_payload "$R_NOM" 'tests/run.sh --only alpha.test.sh' "" omit Bash "" 1800000)"
expect_status "DOOR.31 the main thread, no door: the call passes" 0 "$ST"
expect_regex "DOOR.31b …wrapped, the shim named" "booked\\.sh.* --suites [^ ]+ -- " "$(updated_command_of)"
expect_absent "DOOR.31c …and not told it is the runner" " --runner" "$(updated_command_of)"
run_hook "$(mk_payload "$R_DRM" 'tests/run.sh --only alpha.test.sh' "" omit Bash "" 1800000)"
expect_regex "DOOR.31d control: the same call where the project has the door IS the runner's" \
  "booked\\.sh.* --suites alpha\\.test\\.sh --runner -- " "$(updated_command_of)"

# THE TREE IS THE COMMAND'S: a leading `cd <tree>` moves the project the door is looked for in,
# the way it moves the shim's --stamp-dir. The checkout the hook's root names is not asked.
DR_WT_DOOR="$R_NR/.worktrees/door"; DR_WT_NONE="$R_DR/.worktrees/nodoor"
git -C "$R_NR" worktree add -q -b wt-door "$DR_WT_DOOR" 2>/dev/null
git -C "$R_DR" worktree add -q -b wt-nodoor "$DR_WT_NONE" 2>/dev/null
bw_door "$DR_WT_DOOR" with; bw_door "$DR_WT_NONE" none
expect_eq "DOOR.24a the two trees are real worktrees of their own" "$DR_WT_DOOR/$DR_WT_NONE" \
  "$(git -C "$DR_WT_DOOR" rev-parse --show-toplevel)/$(git -C "$DR_WT_NONE" rev-parse --show-toplevel)"
bw_dispatched "$R_NR" t54writer "suites_allowed=alpha.test.sh" suites_source=declared files=
run_hook "$(mk_payload "$R_NR" "cd '$DR_WT_DOOR' || exit 1; bash tests/alpha.test.sh" "$ACTOR" omit Bash test-runner 1800000)"
expect_status "DOOR.24 a root with no runner, a cd into a tree that has the door: refused" 2 "$ST"
expect_eq "DOOR.24b …by the door's line" "bionic: suite-run refused — use tests/run.sh --only alpha.test.sh (one door)" "$(dr_line)"
bw_dispatched "$R_DR" t54writer "suites_allowed=alpha.test.sh" suites_source=declared files=
run_hook "$(mk_payload "$R_DR" "cd '$DR_WT_NONE' || exit 1; bash tests/alpha.test.sh" "$ACTOR" omit Bash test-runner 1800000)"
expect_status "DOOR.25 a root with the door, a cd into a tree that has none: passes" 0 "$ST"
expect_regex "DOOR.25b …wrapped, stamping the tree it ran in" "--stamp-dir [^ ]*/nodoor .*--suites alpha\\.test\\.sh -- " "$(updated_command_of)"
# A cwd inside the project is still the project: the runner is looked for at the checkout's top.
mkdir -p "$R_DR/sub"
for _dr in "bash $R_DR/tests/alpha.test.sh" 'bash "$PWD/../tests/alpha.test.sh"'; do
  run_hook "$(mk_payload "$R_DR/sub" "$_dr" "$ACTOR" omit Bash test-runner 1800000)"
  expect_status "DOOR.25c [$_dr] standing in a subdirectory of the project with the door: refused" 2 "$ST"
  expect_contains "DOOR.25d …by the door's line" "use tests/run.sh --only " "$(dr_line)"
done
bw_dispatched "$R_DR" t36writer "suites_allowed=alpha.test.sh" suites_source=declared files=

# THE MUTANTS of the predicate, on doctored copies of the library: with it removed the door fires
# in every project (the defect), with it inverted it fires only where there is none, and with the
# `--only` read dropped a runner of the project's own is taken for the door. Each runs before its
# absence is read: the mutant parses, and still refuses an off-budget run.
DRP_FN='^_door_in_tree\(\) \{'
DRP_READ='grep -qF -- '"'--only'"
mk_door_mutant() {  # <dir> <shell text appended to walls.sh: a later definition wins>
  rm -rf "$1"; mkdir -p "$1/hooks"
  cp -R "$BIONIC_SCRIPTS_DIR/payload/scripts" "$1/scripts"
  cp "$HOOK" "$1/hooks/bash-walls.sh"
  case "$2" in
    UNREAD) sed -e "s/! grep -qF -- '--only' .*|| _DOOR_HERE=yes/_DOOR_HERE=yes/" "$1/scripts/lib/walls.sh" > "$1/walls.tmp" && mv "$1/walls.tmp" "$1/scripts/lib/walls.sh" ;;
    *) printf '\n%s\n' "$2" >> "$1/scripts/lib/walls.sh" ;;
  esac
}
anchor -E "$BIONIC_SCRIPTS_DIR/payload/scripts/lib/walls.sh" "$DRP_FN" 1
anchor "$BIONIC_SCRIPTS_DIR/payload/scripts/lib/walls.sh" "$DRP_READ" 1
DRP_KEEP="$HOOK"
for _m in removed inverted unread; do
  DRP_DIR="$SANDBOX/door-pred-$_m"
  case "$_m" in
    removed)  mk_door_mutant "$DRP_DIR" '_door_in_tree() { _DOOR_HERE=yes; }' ;;
    inverted) mk_door_mutant "$DRP_DIR" 'eval "$(declare -f _door_in_tree | sed "1s/_door_in_tree/_door_in_tree_real/")"
_door_in_tree() { _door_in_tree_real; if [ "$_DOOR_HERE" = yes ]; then _DOOR_HERE=no; else _DOOR_HERE=yes; fi; }' ;;
    unread)   mk_door_mutant "$DRP_DIR" UNREAD ;;
  esac
  expect_eq "DOOR.26 [$_m] the mutant library parses" "0" "$(bash -n "$DRP_DIR/scripts/lib/walls.sh" >/dev/null 2>&1; echo $?)"
  expect_eq "DOOR.26b [$_m] and differs from the shipped library" "differs" "$(diff -q "$DRP_DIR/scripts/lib/walls.sh" "$BIONIC_SCRIPTS_DIR/payload/scripts/lib/walls.sh" >/dev/null 2>&1 && echo same || echo differs)"
  HOOK="$DRP_DIR/hooks/bash-walls.sh"
  run_hook "$(mk_payload "$R_NR" 'bash tests/beta.test.sh' "$ACTOR" omit Bash test-runner 1800000)"
  expect_status "DOOR.26c [$_m] the mutant still refuses an off-budget run (it runs, not vacuous)" 2 "$ST"
  run_hook "$(mk_payload "$R_NR" 'bash tests/alpha.test.sh' "$ACTOR" omit Bash test-runner 1800000)"
  # The shipped library answers 0 to both calls (DOOR.21). Removed and inverted fire the door at both;
  # the unread one takes the no-flag runner for the door and still finds no runner at all in R_NR.
  case "$_m" in unread) _want_nr=0 ;; *) _want_nr=2 ;; esac
  expect_status "DOOR.27 [$_m] the no-runner project's on-budget bare run reads $_want_nr under the mutant" "$_want_nr" "$ST"
  run_hook "$(mk_payload "$R_NO" 'bash tests/alpha.test.sh' "$ACTOR" omit Bash test-runner 1800000)"
  expect_status "DOOR.28 [$_m] the no-flag runner project's run is refused under the mutant (red against DOOR.21)" 2 "$ST"
  run_hook "$(mk_payload "$R_NO" 'tests/run.sh --only alpha.test.sh' "$ACTOR" omit Bash test-runner 1800000)"
  expect_status "DOOR.28b [$_m] the no-flag runner's --only call passes as a door claim under the mutant (red against DOOR.29)" 0 "$ST"
  run_hook "$(mk_payload "$R_DR" 'bash tests/alpha.test.sh' "$ACTOR" omit Bash test-runner 1800000)"
  case "$_m" in inverted) _want_dr=0 ;; *) _want_dr=2 ;; esac
  expect_status "DOOR.28c [$_m] the project with the door reads $_want_dr (the shipped library: 2)" "$_want_dr" "$ST"
  HOOK="$DRP_KEEP"
done

# THE MUTANT: the door's block cut from a copy of the library. The bare on-budget run must then
# pass, which is what DOOR.1 exists to refuse. The copy is a plugin tree of its own (hooks/ beside
# scripts/), so the hook's loader finds the doctored library first.
DR_MUT="$SANDBOX/door-mutant"
mkdir -p "$DR_MUT/hooks"
cp -R "$BIONIC_SCRIPTS_DIR/payload/scripts" "$DR_MUT/scripts"
cp "$HOOK" "$DR_MUT/hooks/bash-walls.sh"
anchor "$DR_MUT/scripts/lib/walls.sh" '# ---- BEGIN THE ONE DOOR' 1
awk '/# ---- BEGIN THE ONE DOOR/ { skip = 1 } !skip { print } /# ---- END THE ONE DOOR ----/ { skip = 0 }' \
  "$DR_MUT/scripts/lib/walls.sh" > "$DR_MUT/walls.tmp" && mv "$DR_MUT/walls.tmp" "$DR_MUT/scripts/lib/walls.sh"
expect_eq "DOOR.18 the mutant library parses" "0" "$(bash -n "$DR_MUT/scripts/lib/walls.sh" >/dev/null 2>&1; echo $?)"
DR_HOOK_KEEP="$HOOK"; HOOK="$DR_MUT/hooks/bash-walls.sh"
run_hook "$(mk_payload "$R_DR" 'bash tests/beta.test.sh' "$ACTOR" omit Bash test-runner 1800000)"
expect_status "DOOR.19 the mutant still refuses an off-budget run (it runs, not vacuous)" 2 "$ST"
run_hook "$(mk_payload "$R_DR" 'bash tests/alpha.test.sh' "$ACTOR" omit Bash test-runner 1800000)"
expect_ne "DOOR.20 under the mutant an agent's bare on-budget run passes (the defect DOOR.1 guards)" "2" "$ST"
HOOK="$DR_HOOK_KEEP"

# ---------------------------------------------------------------------------
section "§EG-STEPFIELD — the evidence gate reads each field the step-field verb wrote, at its step (wave-28 T8; REQ-3 AC-3.5; D17)"
# ---------------------------------------------------------------------------
# `session-poker.sh step-field <N> <key>=<value>` writes or replaces the indented `<key>: <value>` line under
# `- Step N:` in the grammar the gate reads (walls.sh `extract_continuation`, `block_get`). FIXTURE FIDELITY: §EG-6's
# repository and plan writer (a plan the gate admits bar the field under test); the VERB is the real one, run in this
# repository under the session the gate judges, writing the bound plan through its own dry commit; the next
# `git commit` is judged by the real gate. Each row below is a field the gate reads: absent, the commit is refused
# naming it; written by the verb, admitted; replaced by the verb with a value the gate rejects, refused again.
SFE_POKER="${BIONIC_HOOKS_DIR}/session-poker.sh"
SFE_HEAD="$H_EG6"
sfe_verb() {  # <args...> -> SFE_RC, SFE_OUT of the verb, run in R_EG6 under the gate's session
  SFE_OUT="$( cd "$R_EG6" && env HOME="$FAKE_HOME" BIONIC_PLUGINS_DIR="$SANDBOX/no-plugins" CLAUDE_CODE_SESSION_ID="$SID" CLAUDE_PROJECT_DIR= \
    bash "$SFE_POKER" "$@" 2>&1 )"
  SFE_RC=$?
}
sfe_commit() { run_hook "$(mk_payload "$R_EG6" 'git commit -m "x"')"; }
sfe_plan() {  # <current> <scale> <body lines for steps 5.. > -> a plan the gate admits at <current> bar what <body> leaves out
  eg6_plan "$1" "$2" "$3" "${4:-}" | awk '/^- Step 5: floor green/ { print "- Step 5: floor run"; print "  auditor: record/generic-evidence.md"; next } { print }'
}
sfe_set() { printf '%s\n' "$1" > "$R_EG6/.bionic/docs/plans/active.md"; bw_bind "$R_EG6"; }

# Step 5: cmd, pass, total, output, head
sfe_set "$(sfe_plan 5 wave "")"
sfe_commit
expect_status "SFE-0 control: the Step-5 block without cmd, pass, total, output and head is refused by the gate" 2 "$ST"
expect_contains "SFE-0b …naming the fields it lacks" "cmd pass total output" "$ERR"
sfe_verb step-field 5 cmd="bash tests/run.sh"
expect_eq "SFE-1 step-field 5 cmd= writes the field (exit 0)" "0" "$SFE_RC"
sfe_verb step-field 5 pass=3
sfe_verb step-field 5 total=3
sfe_verb step-field 5 output=record/generic-evidence.md
sfe_commit
expect_status "SFE-2 cmd, pass, total and output written by the verb, the head still absent: refused" 2 "$ST"
expect_contains "SFE-2b …on the head alone" "carries no 'head:'" "$ERR"
sfe_verb step-field 5 head="$SFE_HEAD"
expect_eq "SFE-3 step-field 5 head= writes the field (exit 0)" "0" "$SFE_RC"
sfe_commit
expect_status "SFE-4 the five fields the verb wrote are read by the gate: admitted" 0 "$ST"
sfe_verb step-field 5 pass=2
expect_eq "SFE-5 step-field 5 pass=2 replaces the field (exit 0)" "0" "$SFE_RC"
sfe_commit
expect_status "SFE-5b the gate reads the pass the verb wrote: pass 2 of total 3 is refused" 2 "$ST"
expect_contains "SFE-5c …in the gate's words" "pass=2 but total=3" "$ERR"
expect_eq "SFE-5d …and the block holds one pass: line" "1" "$(awk '/^- Step 5:/ { f = 1; next } /^- Step 6:|^## / { f = 0 } f && /^  pass:/ { n++ } END { print n + 0 }' "$R_EG6/.bionic/docs/plans/active.md")"
sfe_verb step-field 5 pass=3
sfe_verb step-field 5 head=feedfacecafe
sfe_commit
expect_status "SFE-6 a head the verb replaced with a hash that is no commit here: refused" 2 "$ST"
expect_contains "SFE-6b …in the gate's words" "is not a commit in the repository" "$ERR"
sfe_verb step-field 5 head="$SFE_HEAD"
sfe_commit
expect_status "SFE-7 the head replaced by the verb with the commit: admitted again" 0 "$ST"

# Step 7: adr
sfe_set "$(sfe_plan 7 wave "$EG6_ALL" "- Step 6: review record/w27/review.md
- Step 7: documenting")"
sfe_commit
expect_status "SFE-8 control: the Step-7 block with no adr, rca or n/a is refused" 2 "$ST"
expect_contains "SFE-8b …naming them" "adr: <path>" "$ERR"
sfe_verb step-field 7 adr=docs/adr-0001.md
expect_eq "SFE-9 step-field 7 adr= writes the field (exit 0)" "0" "$SFE_RC"
sfe_commit
expect_status "SFE-9b the gate reads the adr the verb wrote: admitted" 0 "$ST"

# Step 8: merge, worktree-removed (cleanup: n/a is the block's own line)
sfe_set "$(sfe_plan 8 wave "$EG6_ALL" "- Step 6: review record/w27/review.md
- Step 8: integrating
  cleanup: n/a")"
sfe_commit
expect_status "SFE-10 control: the Step-8 block without merge and worktree-removed is refused" 2 "$ST"
expect_contains "SFE-10b …naming both" "merge worktree-removed" "$ERR"
sfe_verb step-field 8 merge=0123456789abcdef0123456789abcdef01234567
sfe_commit
expect_status "SFE-11 merge written by the verb, worktree-removed still absent: refused, on that field alone" 2 "$ST"
expect_contains "SFE-11b …naming worktree-removed" "worktree-removed" "$ERR"
sfe_verb step-field 8 worktree-removed=yes
sfe_commit
expect_status "SFE-12 both fields the verb wrote are read by the gate: admitted" 0 "$ST"

# Step 4: share (no rule of the gate's reads it; the block stays admitted and the line is the gate's own grammar)
sfe_set "$(sfe_plan 4 wave "")"
sfe_commit
expect_status "SFE-13 control: the Step-4 block, as the gate admits it" 0 "$ST"
sfe_verb step-field 4 share=55
expect_eq "SFE-14 step-field 4 share= writes the field (exit 0)" "0" "$SFE_RC"
sfe_commit
expect_status "SFE-14b …and the block with the share line is admitted" 0 "$ST"
expect_eq "SFE-14c …the line is the indented one, under the Step 4 line, before Step 5" "  share: 55|- Step 5: floor run" \
  "$(awk '/^- Step 4:/ { f = 1; next } f && /^  share:/ { l = $0; getline n; print l "|" n; exit }' "$R_EG6/.bionic/docs/plans/active.md")"
sfe_set "$(sfe_plan 5 wave "")"

finish
