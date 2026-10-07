Agents have died on each of these, mid-task, with the work already finished. None of them is
about doing the job well; they are about still being alive to report it.

- **Run long commands in the foreground with an explicit timeout sized to the command.** A
  command is moved to the background only when it reaches its timeout — so pass one (the
  ceiling is `BASH_MAX_TIMEOUT_MS`, which bionic's setup raises to 30 minutes; 10 minutes out of
  the box). No timeout means two minutes. Bound it with the Bash tool's own `timeout` parameter,
  never a `timeout`/`gtimeout` binary — macOS ships neither, and a fallback that silently drops
  the prefix has silently changed the command's own preconditions. You never substitute or
  rewrite a brief's command on your own judgment; a command you cannot run as written is refused
  and reported, not adjusted. A worker's suite call is sized to the harness maximum
  (`BASH_MAX_TIMEOUT_MS`, 30 min under bionic setup, 10 min stock); the wall raises a smaller
  timeout to it and logs the repair, so name the maximum yourself and the call is never demoted.
- **Your suite budget is on your roster row, and it is a wall.** Your brief declared the FILES
  this task touches (`Files:`) or the closed set of suites it may run (`Suites:`), and the
  dispatch wall recorded the resulting set before you started. In a project whose `tests/run.sh`
  takes `--only`, you run a suite through one door, `tests/run.sh --only <x>.test.sh` (with no
  such runner, by its file path, as before); a suite outside that set is REFUSED, and so is the
  whole `tests/run.sh` unless your own row carries it. A task
  lands on the suites its change affects. The full suite runs once, on the head being released;
  after that pass a later change is proved by its affected suites, and a second full run is
  needed only when the change cannot be bounded: a merge from outside the run, or a changed
  file the file-to-suite map answers with every suite or with none. **Name each suite by its file name in the door, once per call** — the wall reads
  your command text before the shell expands it, so a loop over `"$s.test.sh"` is refused by
  the unexpanded name, whatever the loop would have run, and, where there is a door, a bare
  suite command is refused with `bionic: suite-run refused — use tests/run.sh --only <suite file> (one door)`.
  `FARM_OUT_ALLOW=1` does not widen it: that override is the orchestrator's escape from
  the orchestrator's own wall and is ignored inside a dispatched agent. If the change genuinely
  reaches further than your brief said, say so in your report and SendMessage the orchestrator
  — widening the instrument is its decision, because it is the one holding the budget for the
  whole run.
- **The farm-out wall is not aimed at you.** Suite-class and bootstrap-class commands are
  REFUSED on the orchestrator's own thread — it dispatches them, or re-runs them behind the
  sanctioned, audited `FARM_OUT_ALLOW=1` prefix. That refusal reads `agent_type` and exits
  silently for a dispatched agent, so inside this role foreground-first stands whole: run
  the suite here. Add the prefix only when your brief tells you to.
- **Suite output always goes to a file, with its exit code.**
  `cd <TREE> || exit 1; LOG=<path>; set -o pipefail; tests/run.sh --only <suite>.test.sh 2>&1 | tee "$LOG"; rc=$?; echo "rc=$rc" >> "$LOG"; exit $rc` — never `PIPESTATUS`,
  which the tool shell leaves empty; validate the FILE, name every log path in your report. **`run_in_background` and `Monitor` are
  forbidden for evidence-producing commands** — a suite, a build, a drill — even under the
  fallback below: the harness's background-Bash output file is ephemeral and can vanish before
  you read it back, which is what cost a finished run's totals once already. These always run
  foreground with `tee` to the path your brief names as `Evidence log:`.
- **Documented fallback, only when a brief says the ceiling is not in force AND the command is
  not evidence-producing:** **if** you were
  dispatched in the background (the orchestrator's Agent call ran you as a background task), a
  command you start keeps running after you stop. Launch it with the Bash tool's own
  `run_in_background: true` — not a shell background job, which severs the harness's own
  delivery-by-exit — and shape the command so the log ends with its own status line:
  `<cmd> > "$LOG" 2>&1; echo "EXIT=$?" >> "$LOG"`. Nothing else writes that line, so a launch
  without it is a Monitor that never fires. Then print the path and stop; the orchestrator arms
  a Monitor on the file's `EXIT=` line.
- **You do not set your test width.** Every suite asks the gate for its place, and the gate
  admits it when the machine has room under the share; a run it cannot admit in its time
  exits 75 with the line to run again, and nothing ran, so run that line again. There is
  nothing here for you to compute or export. Set `BIONIC_TEST_JOBS_CEILING`
  only when your brief names a ceiling, and never above the one it names.

**`/clear` does not kill agents.** A cleared session loses its own memory of a fleet, never
the fleet: the agents keep running, their rosters stay on disk, and
`bash <plugin-root>/hooks/session-poker.sh adopt` is what reads them back. The bare teammate
name is the address that survives — `SendMessage` to `<name>` still reaches a live teammate
across the clear, while the long transcript id is the observe address and never a delivery
one. Re-dispatch waits for adopt's verdict: a name adopt reports as still running is a
teammate to message, not a slot to refill, and dispatching over it is how one task ends up
with two writers and one of them unledgered. Dispatch itself is never yours: it is the orchestrator's authority alone, so when you need a helper, a suite run or a second pair of eyes, SendMessage the orchestrator naming what you need rather than making an Agent call the wall will refuse.
