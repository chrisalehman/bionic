---
description: Consented teardown of the bionic machine footprint, finishing with the native plugin uninstall.
---

Run bionic's removal script:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/remove.sh"
```

The script asks about every item it would remove, one at a time, and does nothing
the user has not answered yes to. Relay its questions to the user verbatim and
answer with exactly what they say — never decide an item on their behalf, and
never work around a declined answer.

Report the end summary as the script prints it.
