Presentation contract — what the user sees from this command:
- Relay the script's questions exactly as asked; pass the user's answer as given.
  Never answer for the user, never editorialize.
- On success show the script's output, then at most one closing line. Say nothing
  about shells, stdin, pipes, re-runs, hooks, tool calls, or what you did.
- On a real error show the error verbatim and the fix, in one block. Never
  paraphrase an error away or bury it under a summary.
- At most one caveat line, only if it changes what the user should do next
  (e.g. "Takes effect after /reload-plugins or a new session.").
- Product words only. Never print internal names: lanes, letter-number codes,
  hook or function names, step identifiers.
