# Plan — archiving landed branches

| task | what | state |
|---|---|---|
| T1 | lib/archive.sh and bin/archive.sh (D1) | for this change |

## Verification Matrix

| criterion | task | evidence | tier |
|---|---|---|---|
| AC-1.1 | T1 | `bash tests/archive.test.sh` → the tarball is written and lists the tip's file | T2: a real repository, a real tarball |
| AC-1.2 | T1 | `bash tests/archive.test.sh` → a name with a `/` makes one flat file | T2: a real repository, a real tarball |
