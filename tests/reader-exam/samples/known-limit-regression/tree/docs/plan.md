# Plan — suite runs

| task | what | state |
|---|---|---|
| T1 | bin/run-suite.sh stamps the run | landed |
| T2 | REQ-2: keep the output | for this change |

## Verification Matrix

| criterion | task | evidence | tier |
|---|---|---|---|
| AC-1.1 | T1 | `bash tests/run-suite.test.sh` → `ok - the suite's exit code is passed on`, `ok - a red run is stamped` | T2: a real repository, a real suite |
| AC-2.1 | T2 | `bash tests/run-suite.test.sh` → `ok - the output is kept in the log` | T2: a real repository, a real suite |
