### Scaffold

```
Expected duration: <N> minutes
Expected artifact: <ONE path inside the repo, e.g. .bionic/docs/record/<wave>/<name>.md>
Progress artifact: <path>  (tasks of 15 min or more)
Cadence: <N> min  (tasks of 15 min or more)
Done marker: <path>  # optional
Subprocess claim: <process pattern>   # a backgrounded watcher, e.g. gh run watch — optional
Files: <every path the task may create or edit>  # writers; a read-only brief omits this and keeps Suites: none
Suites: none  # *.test.sh names or a path-qualified run.sh; other runners: Re-executes:
Re-executes: `<cmd>`
Lands-red: <suite> until <ext:slug | approval:name>  # optional
Red-evidence: <path under record/>  # with Lands-red:
Deliverable-waiver: <reason>  # only for a report returned by message
```
