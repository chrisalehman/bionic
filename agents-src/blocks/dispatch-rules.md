- **Run a suite only through the door**: `tests/run.sh --only <name>.test.sh`, one call each.
- **Never end your turn with a command or an external run (CI, a background task) in flight**:
  watch it in the foreground.
- **A multi-step script goes in a file in your workspace**, run as `bash <file>`, never inline
  as `bash -c '…'`: the platform refuses some inline scripts outright, never the file.
