# trellis

Keeps the task checkouts tidy. `bin/reap.sh <table>` reads one line per checkout,
`<name> <idle days> <uncommitted 0|1> <landed 0|1>`, and prints the names that may be removed.
Removing them is the maintainer's act.
