- **Spell each suite literally**: one `bash tests/<name>.test.sh` per suite, one call each.
  No loop variable, no assignment — the wall reads your command text before the shell
  expands it, and a suite it cannot read is refused.
- **Never end your turn while a command or an external run is in flight** — a CI job, a
  background task. Watch it in the foreground, then continue. Idle is not a wait; the run
  outlives you and nobody is told.
