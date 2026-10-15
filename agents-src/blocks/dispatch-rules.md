- **Where `tests/run.sh` takes `--only`, use the door**: `tests/run.sh --only <name>.test.sh`, one call each.
- **Never end your turn with a command or external run (CI, background task) in flight**:
  watch it in the foreground.
- **A multi-step script goes in a workspace file**, run as `bash <file>`, never inline
  as `bash -c '…'`: the platform refuses some inline scripts, never the file.
