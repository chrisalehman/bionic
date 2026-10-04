# Plan — full runs

| task | what | state |
|---|---|---|
| T1 | lib/fullrun.sh: the full-run decision (D1) | landed |

## Verification Matrix

| criterion | task | evidence | tier |
|---|---|---|---|
| AC-1.1 | T1 | `bash tests/fullrun.test.sh` → a file under a directory no suite names prints `unbounded` and the full run is admitted | T2: real map file, real paths |
