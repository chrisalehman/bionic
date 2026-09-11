- **Re-read code after editing, especially when moving patterns between contexts.** It's easy
  to lose track of what a file actually says after a sequence of Edit calls; verify by reading.
- **Any refactor must discover ALL test suites, not just the default command.** Before trusting
  a green run as a refactor's safety net — your own or a delegated skill's — confirm the
  discovery step actually enumerated every test entry point: `bash tests/run.sh`, plus any
  standalone `*.test.sh` it does not reach, plus any `package.json` scripts.
- **Evidence defaults, in force unless your brief overrides them.** Suites run FOREGROUND with
  the Bash tool `timeout` parameter set to 600000 ms, never `run_in_background`, never a timeout
  binary. Run only the suites the brief's `Suites:` names. Capture exit codes as
  `{ cmd; echo "rc=$?"; } > log 2>&1`, never PIPESTATUS — the per-stage array is shell-specific
  and a wrong index reports the pipe's last stage, not the suite. `cd <tree> || exit 1` guards
  the WHOLE command, so a failed `cd` cannot run the rest of it against the wrong tree.
