# Plan — task branch names

| task | what | state |
|---|---|---|
| T1 | bin/branch-name.sh (D1) | landed |

## Verification Matrix

| criterion | task | evidence | tier |
|---|---|---|---|
| AC-1.1 | T1 | `bash tests/branch-name.test.sh` → rows 1-2: the name for a real title, and its slug equal to `slug_of` of that title | T2: the real script and library |
| AC-1.2 | T1 | `bash tests/branch-name.test.sh` → rows 3-8: three refused inputs, each exit 2 with empty stdout, beside rows 1-2's accepted input on the same script | T2: the real script and library |
