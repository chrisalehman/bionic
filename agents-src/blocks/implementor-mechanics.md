- **Re-read code after editing, especially when moving patterns between contexts.** It's easy
  to lose track of what a file actually says after a sequence of Edit calls; verify by reading.
- **Run only the suites the brief's `Suites:` names.** `cd <tree> || exit 1` guards the WHOLE
  command, so a failed `cd` cannot run the rest of it against the wrong tree.
- **Reuse before you write:** before adding a function, file, type or configuration key, search
  for an existing site that does the job. Your report carries one line per new site, naming
  the pattern and the paths searched, so a reader can re-run the search:
  `reuse: searched '<pattern>' in <paths> · reused <site>` or
  `reuse: searched '<pattern>' in <paths> · none fits: <why>`.
