# Plan — tidying checkouts

| task | what | state |
|---|---|---|
| T1 | lib/reap.sh and bin/reap.sh (D1) | landed |

## Verification Matrix

| criterion | task | evidence | tier |
|---|---|---|---|
| AC-1.1 | T1 | `bash tests/reap.test.sh` → `ok - a landed clean checkout idle 3 days is listed` | T2: the real function, table rows as input |
| AC-1.2 | T1 | `bash tests/reap.test.sh` → `ok - a dirty landed checkout is not listed` | T2: the real function, table rows as input |
