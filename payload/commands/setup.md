---
description: Set this machine up for bionic — idempotent, consented, one item at a time.
---

Run bionic's setup script and show the user its output verbatim, including the
end summary. The script asks before every change; relay its questions and the
user's answers without deciding on their behalf.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh"
```
