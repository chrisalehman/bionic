# Rules for writers

- Run each suite in its own call: `bin/run-suite.sh tests/<name>.test.sh`, once per suite the
  task names. A task that names two suites makes two calls.
- Commit before you run the suites; the stamp records the head the run saw.
