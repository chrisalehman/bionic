### Scaffold

```
Expected duration: <N> minutes
Expected artifact: <ONE path inside the repo, or a bare file name, e.g. .bionic/docs/record/<wave>/<name>.md>
Progress artifact: <path>  (tasks of 15 min or more)
Cadence: <N> min  (tasks of 15 min or more)
Done marker: <path>  # optional
Subprocess claim: <process pattern>   # a backgrounded watcher, e.g. gh run watch — optional
Files: <every path the task may create or edit>  # a reader lists its records here, one per question, its artifact among them; a researcher or test-runner omits it
Suites: none  # *.test.sh names or a path-qualified run.sh; other runners: Re-executes:; a reader dealt evidence names 1 to 3 runs across both labels
Re-executes: `<cmd>`
Questions: <q>[, <q>]  # reader roles only
Row: <id>  # the plan row a writer runs
Lands-on: <suite>[, <suite>] | none <reason>  # what ready proves, within Suites:
Lands-red: <suite> until <ext:slug | approval:name>  # optional
Red-evidence: <path under record/>  # with Lands-red:
Deliverable-waiver: <reason>  # only for a report returned by message
```
