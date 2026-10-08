# Spec — tidying checkouts

## Requirements

**REQ-1.** A task checkout is listed for removal only when removing it loses nothing.

- **AC-1.1.** A landed checkout with no uncommitted changes, idle one day or more, is listed.
  Fails when: such a checkout is left out.
- **AC-1.2.** A checkout with uncommitted changes is never listed, whatever its age or state.
  Fails when: a checkout with uncommitted changes is listed.

## Design

- **D1.** `lib/reap.sh` decides each checkout from its idle days, its uncommitted flag and its
  landed flag. `bin/reap.sh` reads the table and prints the names. (REQ-1)
