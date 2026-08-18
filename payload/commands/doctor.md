---
description: Read-only diagnosis of the bionic install on this machine — plugin integrity, tier state, dependencies, environment, permission profile, and what to do about anything broken. Changes nothing.
---

Run:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/doctor.sh"
```

Show the report to the user as it was printed. It is already organised for
reading, and its closing SUMMARY block is the list of actions — do not
summarise it further, and do not act on any of those actions unless the user
asks.
