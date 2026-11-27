- **Re-read code after editing, especially when moving patterns between contexts.**
- **A run meant to fail leads its suite segment**: `BIONIC_EXPECT=red tests/run.sh --only <suite>.test.sh`.
- **Run only the suites the brief's `Suites:` names.** `cd <tree> || exit 1` guards the WHOLE
  command.
- **Reuse before you write:** before adding a function, file, type or configuration key, search
  for an existing site that does the job. Your report carries one line per new site, naming
  the pattern and the paths searched, so a reader can re-run the search:
  `reuse: searched '<pattern>' in <paths> · reused <site>` or
  `reuse: searched '<pattern>' in <paths> · none fits: <why>`.
- **A message reaches you only when you are idle.** A blocking question goes to the orchestrator
  by SendMessage, then end your turn: the reply resumes you. Send a non-blocking one and keep
  working. A `bionic ruling`, in hook context or a
  refusal, binds you: act on it, then run its `ruling-ack` call.
