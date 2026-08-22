Agents have died on each of these, mid-task, with the work already finished. None of them is
about doing the job well; they are about still being alive to report it.

- **Run long commands in the foreground with an explicit timeout sized to the command.** A
  command is moved to the background only when it reaches its timeout — so pass one (the
  ceiling is `BASH_MAX_TIMEOUT_MS`, which bionic's setup raises to 30 minutes; 10 minutes out of
  the box). No timeout means two minutes.
- **The farm-out wall is not aimed at you.** Suite-class and bootstrap-class commands are
  REFUSED on the orchestrator's own thread — it dispatches them, or re-runs them behind the
  sanctioned, audited `FARM_OUT_ALLOW=1` prefix. That refusal reads `agent_type` and exits
  silently for a dispatched agent, so inside this role foreground-first stands whole: run
  the suite here. Add the prefix only when your brief tells you to.
- **Never end your turn while a command is running.** When a foreground agent gives its final
  response the harness ENDS its running commands — stopping to wait kills the work and gets no
  wake. Not to save tokens, not to be polite, not because the context is long.
- **Suite output always goes to a file, with `set -o pipefail`.** `<command> 2>&1 | tee "$LOG"`;
  validate the FILE, name every log path in your report.
- **Documented fallback, only when a brief says the ceiling is not in force:** **if** you were
  dispatched in the background (the orchestrator's Agent call ran you as a background task), a
  command you start keeps running after you stop. Launch it with the Bash tool's own
  `run_in_background: true` — not a shell background job, which severs the harness's own
  delivery-by-exit — and shape the command so the log ends with its own status line:
  `<cmd> > "$LOG" 2>&1; echo "EXIT=$?" >> "$LOG"`. Nothing else writes that line, so a launch
  without it is a Monitor that never fires. Then print the path and stop; the orchestrator arms
  a Monitor on the file's `EXIT=` line. **Otherwise stay in the foreground and do not stop** — a
  foreground agent's final response ENDS the command, so the fallback would kill the work it
  exists to protect. Never arm a watcher and go idle yourself.
