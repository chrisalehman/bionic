# Changelog

## 0.3.0

- `bin/run-suite.sh` stamps a suite that exits 0 after printing a line that starts with `not ok`
  as `rc=1`, so the landing check refuses it.

Known limits:

- Known limit: a suite that reports failure in some other way than `not ok` lines and exits 0 is
  stamped green. `bin/run-suite.sh` guards the `not ok` form by reading the suite's output, so
  only a suite with another format must exit non-zero itself.

## 0.2.0

- `bin/run-suite.sh` stamps each run with the head it saw.
