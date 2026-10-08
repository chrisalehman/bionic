# Spec — suite runs

## Requirements

**REQ-1.** A suite run leaves a stamp that says whether the suite passed.

- **AC-1.1.** A suite that exits non-zero is stamped with its exit code, and `run-suite.sh`
  exits with it. Fails when: a failing suite is stamped `rc=0`.

**REQ-2.** A suite's output is kept for a failed landing to show.

- **AC-2.1.** Running a suite leaves its output in `trellis-logs/<suite file>.log` in the
  checkout's git directory. Fails when: the log is missing or lacks a line the suite printed.
