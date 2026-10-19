# tests/dispatch-preflight-4.prelude.sh — THE HALF OF THE DISPATCH-PREFLIGHT-4 SUITE BOTH PARTS SHARE
# (wave-39 T37; D1, D13, REQ-3 AC-3.3).
#
# Sourced by tests/dispatch-preflight-4a.test.sh and -4b.test.sh, after the framework, the shared libraries and
# tests/dispatch-preflight.prelude.sh. It is not a suite: the runner launches `*.test.sh` only. It sits beside the
# parts rather than under tests/lib/ so the reads index follows it from each part's `source` line, one hop
# (lib/anchors.sh, the prelude hop), and an edit to it is answered with these two suites, not the full run.
#
# WHY TWO PARTS. dispatch-preflight-4.test.sh was the fourth shard of the start gate's suite (wave-30 T1). Its 29
# sections took 490 s on the gate under load (timing.tsv holds 392 s at width 2), the longest of the four shards
# and close to the suite bar (lib/line.sh LINE_SUITE_BAR, ten minutes of the gate's promise; D1) that `ready`
# refuses a suite past. D13 rules it in two. It is cut at a section boundary into two suites of about equal
# cost, every section kept whole and in its order:
#
#   dispatch-preflight-4a.test.sh   S10h … §LR       (16 sections)
#   dispatch-preflight-4b.test.sh   §T72 … §FILES    (13 sections)
#
# The suite's header (what the start gate is, how the four shards hold it, how it stays hermetic) is in
# tests/dispatch-preflight.test.sh; the fixtures and their fidelity notes are in tests/dispatch-preflight.prelude.sh.
#
# WHAT IT HOLDS. Each helper or constant a section of part a defined that a section of part b calls: a block here is
# marked with the section it came from, and that section keeps a one-line pointer where the block stood. Part a
# sources this file too, since the sections it keeps call the same helpers.
#
# WHAT IT NEVER HOLDS. A fixture a section builds and a later one reads, apart from the one decoy file below, which
# is a single plain file each part makes afresh in its own sandbox.

# ---- from S10h (part a): the decoy roster file §RECORDER (part b) points a symlink at ----
DECOY_ROSTER="$SANDBOX/decoy-roster.txt"
printf 'untouched\n' > "$DECOY_ROSTER"

# ---- from §Q (part a): the reader-brief builders and the gate driver §T72 and later sections call ----
q_rigor() {  # <repo> <rigor> — the bound plan's frontmatter rigor, rewritten in place
  local p="$1/.bionic/docs/plans/epic-99-test/wave-01-test.plan.md"
  awk -v r="$2" '/^rigor:/ && !done { print "rigor: " r; done = 1; next } { print }' "$p" > "$p.tmp" \
    && mv "$p.tmp" "$p"
}
q_brief() {  # <tag> [<questions line>] — a reader brief with one declared suite
  printf 'Your task: read the wave-99 change for the questions below.\nExpected artifact: .bionic/docs/record/wq-%s.md\nExpected duration: ~30 minutes.\nSuites: tests/widget.test.sh' "$1"
  [ -n "${2:-}" ] && printf '\n%s' "$2"
  # A reader names a record for each question it is dealt (wave-27 T49): beside a set of several
  # questions the brief carries a Files: line holding the artifact and one more record apiece.
  local _qb_n _qb_i _qb_f
  _qb_n=$(( $(printf '%s' "${2:-}" | tr -cd ',' | wc -c) + 1 ))
  if [ -n "${2:-}" ] && [ "$_qb_n" -gt 1 ]; then
    _qb_f=".bionic/docs/record/wq-$1.md"
    for ((_qb_i = 2; _qb_i <= _qb_n; _qb_i++)); do _qb_f="$_qb_f, .bionic/docs/record/wq-$1-$_qb_i.md"; done
    printf '\nFiles: %s' "$_qb_f"
  fi
  return 0
}
q_row() { roster_nth_row "$(roster_path "$1" "$SID_A")" 1; }
q_gate() {  # <repo> <tag> <role> <brief>
  run_gate "$(mk_agent_payload "$SID_A" "$1" "$4" "wq-$2" "claude-sonnet-5" "$S5_LIVE_TRANSCRIPT" "$3")"
}

# ---- from §Q: the repo bound to no plan ----
q_unbound() {  # <name> -> a repo whose session is engaged and bound to no plan
  local repo; repo=$(make_repo "$1" yes)
  rm -f "$repo/.bionic/docs/plans/epic-99-test/wave-01-test.plan.md"
  unbound_marker "$repo" "$SID_A" empty
  write_attestation "$repo" "$SID_A"
  printf '%s' "$repo"
}

# ---- from §scaffold-walk: the walk's repo and the recorder start ----
walk_repo() {  # <name> <rigor> -> a repo whose bound plan carries base-sha: and working-branch:
  local repo plan base wb
  repo=$(make_repo "$1" yes); write_attestation "$repo" "$SID_A"; q_rigor "$repo" "$2"
  plan="$repo/.bionic/docs/plans/epic-99-test/wave-01-test.plan.md"
  base="$(git -C "$repo" rev-parse HEAD)"; wb="$(git -C "$repo" rev-parse --abbrev-ref HEAD)"
  awk -v b="$base" -v w="$wb" '/^rigor:/ { print; print "base-sha: " b; print "working-branch: " w; next } { print }' \
    "$plan" > "$plan.tmp" && mv "$plan.tmp" "$plan"
  echo c1 > "$repo/a.txt"; git -C "$repo" add a.txt; git -C "$repo" commit -qm c1
  printf '%s' "$repo"
}
walk_start() {  # <repo> <name> -> the real execution recorder starts the dispatched agent
  jq -n --arg s "$SID_A" --arg c "$1" --arg a "a-$2" --arg n "$2" \
    '{session_id:$s, transcript_path:($c+"/t.jsonl"), cwd:$c, agent_id:$a, agent_type:$n,
      hook_event_name:"SubagentStart"}' \
    | ( cd "$1" && env -u CLAUDE_PROJECT_DIR CLAUDE_CODE_SESSION_ID="$SID_A" \
          bash "${BIONIC_HOOKS_DIR}/execution-recorder.sh" >/dev/null 2>&1 )
}

# ---- from §brief-lib: the library's path, the empty root, and the two verdict printers ----
BRIEF_LIB="${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/brief.sh"
BRIEF_NOCONF="$SANDBOX/brief-noconf"; mkdir -p "$BRIEF_NOCONF"
# brief_verdict <role> <root> <brief text> -> one `finding: <fact>` or `warn: <line>` per sink
# call, then `rc=`, `suites=` and `source=`. The library is sourced by nothing but this
# shell, so a dependency it forgets to bring in is a failure here and not a pass on a
# neighbour's load.
brief_verdict() {
  bash -c '
    . "$1" || exit 9
    sink() { case "$1" in finding) printf "finding: %s\n" "$2" ;; warn) printf "warn: %s\n" "$2" ;; esac; }
    rc=0
    brief_validate_fields "$(lift_contract_fields "$4" "$2")" "$2" "$3" sink || rc=$?
    printf "rc=%s\nsuites=%s\nsource=%s\n" "$rc" "${BRIEF_SUITES_ALLOWED-}" "${BRIEF_SUITES_SOURCE-}"
  ' _ "$BRIEF_LIB" "$1" "$2" "$3" 2>&1
}

# wave-22 T3 (D5/D6): EVERY Re-executes: line counts, and the Files-alone refusal names the
# fix that applies when runs are declared.
# the sink's fourth argument is the refusal body, which brief_verdict does not print
brief_detail() {
  bash -c '
    . "$1" || exit 9
    sink() { case "$1" in finding) printf "finding: %s\nfix: %s\n%s\n" "$2" "$3" "$4" ;; esac; }
    rc=0
    brief_validate_fields "$(lift_contract_fields "$4" "$2")" "$2" "$3" sink || rc=$?
    printf "rc=%s\n" "$rc"
  ' _ "$BRIEF_LIB" "$1" "$2" "$3" 2>&1
}

# ---- from §ADV: the brief builder and the advisory reader ----
adv_brief() {  # <body lines> -> BRIEF_FULL's contract with the given body lines before Suites:
  printf 'Canonical-sdlc Step 4, task 4/9 of epic-99 wave-01; build · double · wave.
Your task: implement the widget behind the existing seam.
%s
Expected artifact: .bionic/docs/record/w99-widget.txt
Exit condition: the artifact exists and the paired suite is green.
Expected duration: ~25 minutes.
Progress artifact: .bionic/tmp/w99-widget.progress
Files: payload/scripts/lib/widget.sh
Suites: tests/widget.test.sh' "$1"
}

# adv_ctx -> the model-facing advisory text of the last gate run, `` when stdout carries none.
# THE ADVISORY RIDES `hookSpecificOutput.additionalContext` on stdout (A-orch-20), so it is read
# through `jq` like the harness reads it; a stdout that is not one parseable object reads as empty.
adv_ctx() { printf '%s' "$GATE_OUT" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null; }
