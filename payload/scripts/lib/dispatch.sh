#!/bin/bash
# lib/dispatch.sh — the words of every refusal hooks/dispatch-preflight.sh gives, each under a key.
#
# THE HOOK DECIDES AND THIS FILE SPEAKS. The wall reads its facts (the payload, the plan through the
# reader, the roster, the stamp, the brief) and decides which refusal stands; it then names the refusal
# by its key and hands over the facts the words print. Nothing here reads a file or the environment to
# find a fact: a value printed comes in as an argument, and a path a fix prints comes from the hook's
# own directory, so a fix names the command beside the hook and never one beside this library.
#
#   dispatch_say <key> [facts...]       sets DISPATCH_FACT, DISPATCH_FIX and DISPATCH_DETAIL; exit 0,
#                                       or 2 with all three empty for a key it does not know
#   dispatch_refuse <wire> <key> [...]  says the key and refuses on <wire> (exit2 or deny); never returns
#   dispatch_finding <key> [facts...]   says the key and records it in the pool; never exits
#   dispatch_refuse_findings            spends the pool as one refusal, or returns when it is empty
#   dispatch_keys                       every key, one per line
#
# THE POOL. Every state and brief arm records its fault and the wall carries on, so one refusal names
# every fault the wall found: one fault in its arm's own words and detail, several as the first fault's
# user line with one `<fact> (<fix>)` line for each other and a pointer. Both go out on `deny`, the wire
# whose reason reaches the model whole; the status never depends on the count. The attestation's two
# refusals stay on `exit2` and outside the pool, since their subject is the machine every other arm
# reads from. A key with no words leaves the fact empty, and `refuse` then refuses its own call: an
# unknown key still refuses, it never admits.
#
# Sourced, never executed; it defines functions and the pool's counters, and needs lib/refuse.sh
# (`refuse`, `refuse_shell_word`, `refuse_quote`) and lib/width.sh (`bionic_trunc`) loaded first.

DISPATCH_FACT=""; DISPATCH_FIX=""; DISPATCH_DETAIL=""
_DISPATCH_N=0; _DISPATCH_LINES=""; _DISPATCH_FIRST_FACT=""; _DISPATCH_FIRST_FIX=""; _DISPATCH_FIRST_DETAIL=""

_dispatch_words() { DISPATCH_FACT="$1"; DISPATCH_FIX="$2"; DISPATCH_DETAIL="$3"; }

# The role a dispatch with no subagent_type runs as, in every frame that names the role.
_dispatch_role() { printf '%s' "${1:-(none given, so general-purpose)}"; }

# The brief file's frame: <key's fact> <fix> <why> <name> <bound row> <brief path> <hook dir> <file row>.
_dispatch_brief() {
  local fact="$1" fix="$2" why="$3" name="$4" bound="$5" path="$6" hook="$7" frow="$8" row render
  row="${bound:-${frow:-<row>}}"
  render="bash $(refuse_shell_word "$hook/session-poker.sh") brief ${row} ${name:-<name>}"
  _dispatch_words "$fact" "$fix" "    Dispatch:   ${name:-<unnamed>}${bound:+ (row ${bound})}
    Brief file: ${path:-<none on the first line of the prompt>}

${why}

Fix: render the brief for this dispatch; it writes briefs/${name:-<name>}.md and prints its path:
       ${render}
     Put that path alone on the prompt's first line, and dispatch under the name it was rendered for.
     A brief is changed by editing the plan's section for the row and rendering again, never by hand.

Then retry the dispatch."
}

# The Patrol frame: <fact> <fix> <fix block> <state lines, newline-joined>.
_dispatch_patrol() {
  _dispatch_words "$1" "$2" "${4}
A dispatch with no Patrol behind it is an agent nobody is waiting on.

${3}

Then retry the dispatch."
}

dispatch_keys() {
  printf '%s\n' deadline attest-none attest-failed plan-unreadable patrol-never patrol-silent patrol-stopped \
    reviewer-retired facts-unread fill-missing unapproved unbound name-ambiguous approval-waits approval-unread \
    waits-unread nested-writer worktree budget in-flight deliverable-outside proto-row proto-tree proto-path \
    no-deliverable no-suites row-unknown row-mismatch lands-none live-writer brief-unreadable brief-unnamed \
    brief-outside brief-absent brief-unrendered brief-unsummed brief-unsummable brief-edited brief-other-name \
    brief-other-row brief-slot roster-link row-unbuilt roster-unwritable
}

dispatch_say() {  # <key> [facts...]
  local key="${1-}" a b c q p w
  shift
  DISPATCH_FACT=""; DISPATCH_FIX=""; DISPATCH_DETAIL=""
  case "$key" in
    deadline)  # <seconds> <roster file, empty before it is named>
      _dispatch_words "the wall ran out of time" "dispatch again" \
"The dispatch wall had not finished ${1-} s after it started. The harness cancels a hook at its
registration's timeout and admits the call, so this wall refuses first.

Roster:  ${2:-(not reached)}
No row was written for this launch, and nothing was spawned.

Fix: dispatch again. If it recurs the machine is overloaded: wait for the running suites to finish,
     or run /bionic:doctor." ;;
    attest-none)  # <the probe's command>
      _dispatch_words "this repo has no environment attestation" "run the preflight probe" \
"No environment attestation was found for this repo, and the probe that writes one
could not be located (looked beside this gate and under the Claude config directory).

This subagent start needs a working environment, and a wave is active.

Fix: ${1-}
Then retry the dispatch." ;;
    attest-failed)  # <the probe's output> <the probe's command>
      q="$(printf '%s\n' "${1-}" | sed 's/^/    /')"
      _dispatch_words "the environment check ran and did not pass" "fix what the probe named" \
"The check was run automatically for this session and did not pass:
${q}

A fleet inherits this environment and dies collectively if it is wrong.
Fix the failure above, then retry the dispatch (or re-run by hand: ${2-})." ;;
    plan-unreadable)  # <plan>
      _dispatch_words "the bound plan cannot be read" "restore read access to the plan" \
"The plan this session is bound to exists and cannot be read: ${1-}
Approval and the writer budget are read out of it, so neither can be measured. It is not
closed and not gone, so no other plan is read in its place.
Fix: restore read access (chmod u+r on the plan, u+rx on its folder), then dispatch." ;;
    patrol-never)  # <poker script> <stamp file>
      _dispatch_patrol "no Patrol stamp exists for this session" "CronCreate the Patrol job" \
"Fix: CronList, then CronCreate a RECURRING session job at the interval \`bash ${1-} interval\`
  reports, carrying the patrol prompt (skills/canonical-sdlc/SKILL.md §Dispatch). That is the
  one half this model owns. The stamp is the other half and it is written for you:
  hooks/engage.sh arms it as the session engages canonical-sdlc, so a session that engaged
  has one. Engage the skill again in this session if it is still missing." \
"There is no Patrol stamp for this session at:
    ${2-}
The Patrol was never armed on this session (a symbolic link at that path is never
followed and reads the same way), so nothing is watching the fleet this dispatch joins.
" ;;
    patrol-silent)  # <stamp age> <marker turns since it> <poker script> <stamp file>
      _dispatch_words "the Patrol fires but never ticks" "run the tick; replace the job" \
"The Patrol was armed on this session and its job still fires, but it never ticks.
Its last tick stamp is ${1-}s old, and since then ${2-} Patrol marker turn(s)
have run on this session without the tick stamping — the job's prompt carries the marker
but does not run \`bash ${3-} tick\`, so nothing has decided anything since:
    ${4-}

A dispatch with no Patrol behind it is an agent nobody is waiting on.

Fix: repair the job, not the clock:
  1. Run the tick now: bash ${3-} tick
  2. CronList, and CronDelete this session's Patrol job.
  3. CronCreate a RECURRING session job at the interval \`bash ${3-} interval\`
     reports, carrying exactly the prompt \`bash ${3-} prompt\` prints.

Then retry the dispatch." ;;
    patrol-stopped)  # <poker script> <stamp age> <idle gap> <fire window> <interval> <default|configured> <stamp file>
      case "${6-}" in
        default) q="the poker's ${5-}s default interval (this project's configured value could not be read)" ;;
        *)       q="the ${5-}s poker-interval this project configures" ;;
      esac
      _dispatch_patrol "the Patrol was armed and stopped firing" "re-arm the Patrol, both halves" \
"Fix: re-arm the Patrol — look first, then the clock, then the stamp:
  1. CronList — is this session's Patrol job still listed?
  2. ONLY IF it is ABSENT: CronCreate a RECURRING session job at the interval
     \`bash ${1-} interval\` reports, carrying the patrol prompt
     (skills/canonical-sdlc/SKILL.md §Dispatch).
  3. bash ${1-} arm" \
"The Patrol was armed on this session and has stopped firing.
Its last stamp is ${2-}s old, and this session has since sat idle for
${3-}s in one stretch with no tick in it — past the ${4-}s fire window,
which is ${q} plus the scheduler's jitter:
    ${7-}
" ;;
    reviewer-retired)  # <subagent type>
      _dispatch_words "bionic:reviewer is retired (1.14.0)" "dispatch bionic:critic" \
"The structure reviewer is not a role any more, so a brief cannot name it:
    Role: ${1-}

Fix: structure is the critic's question; dispatch bionic:critic. Its Questions: line is the
set the plan's rigor deals it, and its checks (reuse and one site per concept among them) are
pushed to it at start.

Then retry the dispatch." ;;
    facts-unread)  # <subagent type> <plan>
      _dispatch_words "the run's facts could not be read" "dispatch again" \
"Role: $(_dispatch_role "${1-}")
Plan: ${2-}
The run's step and its Step-3 approval could not be read (lib/proof.sh proof_step_held), so whether
this plan is approved is not known. A writer is admitted only on an approval this hook has read.

Fix: dispatch again; the fold's own line on stderr names why it failed." ;;
    fill-missing)  # <subagent type> <plan> <library directory> <read-only roles>
      _dispatch_words "the approval check lib/fill.sh cannot be loaded" "reinstall the plugin" \
"Role: $(_dispatch_role "${1-}")
Plan: ${2-}
Lookup: fill_plan_approved, from ${3:-<no library directory>}/fill.sh — not there, or it
        does not define the function, so whether this plan is approved cannot be read.

A writer is admitted only on an approval this hook has read; one it cannot read is no approval.
Before approval only a read-only role dispatches: ${4-}.

Fix: reinstall the plugin (claude plugin install bionic@bionic) so its scripts/lib carries
     fill.sh again, then retry the dispatch." ;;
    unapproved)  # <subagent type> <plan> <step> <read-only roles>
      _dispatch_words "the plan this writer builds is unapproved" "get the Step-3 plan approved" \
"Role: $(_dispatch_role "${1-}")
Plan: ${2-}
Step: ${3:-(unreadable)} — writers run against an APPROVED plan, and nothing recorded one.

A writer is the first act of a plan that cannot be taken back by closing a file. Before
approval only a read-only role dispatches: ${4-}.

Fix: put the Step-3 card to the user and wait for the literal word 'approved'; then
     record it under '## SDLC State' in the plan above:
       approved-by: <user> <ISO-UTC> \"<verbatim reply>\"
     Silence, a question, or a partial reply is never transcribed as approval.

Then retry the dispatch." ;;
    unbound)  # <subagent type> <the unbound advisory> <read-only roles>
      _dispatch_words "this session is bound to no run" "bind it, or write its plan" \
"Role: $(_dispatch_role "${1-}")
${2-}

A writer is the first act of a plan that cannot be taken back by closing a file, and this
session has no plan of its own: the run above is the root's newest, announced and never
acted on. Before approval only a read-only role dispatches: ${3-}.

Fix: bind this session to the run it is working, or write this session's own plan (the
     governing-skill hook binds it on the first write), then retry the dispatch." ;;
    name-ambiguous)  # <dispatch name> <the rows it matches, one per line> <plan>
      a="${2-}"; b="${a#*$'\n'}"; a="${a%%$'\n'*}"; b="${b%%$'\n'*}"
      _dispatch_words "the name matches rows $(bionic_trunc "$a" 11), $(bionic_trunc "$b" 11)" "add Row: <id>" \
"The agent's name matches more than one row of the bound plan, and the brief has no Row: to say which:
    Dispatch: ${1-}
    Rows:     $(printf '%s' "${2-}" | tr '\n' ' ')
    Plan:     ${3-}

Every wall reads one row per dispatch, and the launch record records none for such a name.

Fix: add a line of its own to the brief naming the row this agent runs, as the plan's ## Tasks table
spells it —
    Row: <id>
  or name the agent for one row only.

Then retry the dispatch." ;;
    approval-waits)  # <row> <approval name> <dispatch name> <plan> <hook dir>
      _dispatch_words "row ${1-} waits for approval:${2-}" "record it with the approve verb" \
"Dispatch: ${3:-<unnamed>} (row ${1-} of ${4-})
Reads:    approval:${2-} — and ## SDLC State carries no 'approved: ${2-}' line.

An approval is an act of the user. The row waits for it, the ready set does not offer it, and no
dispatch starts it before the line exists.

Fix: put the decision to the user; on their reply, record it, then retry the dispatch:
       bash $(refuse_shell_word "${5-}/session-poker.sh") approve ${2-} '<the reply, verbatim>'
     Silence, a question, or a partial reply is never recorded as approval." ;;
    approval-unread)  # <row> <approval name> <dispatch name> <plan>
      _dispatch_words "the run's facts could not be read" "dispatch again" \
"Dispatch: ${3:-<unnamed>} (row ${1-} of ${4-})
Reads:    approval:${2-} — and whether it stands could not be read (lib/proof.sh proof_approved), so
whether this row may start is not known. A row that waits for an approval starts only on one this
hook has read.

Fix: dispatch again; the fold's own line on stderr names why it failed." ;;
    waits-unread)  # <row> <dispatch name> <plan>
      _dispatch_words "row ${1-}'s waits could not be read" "dispatch again" \
"Dispatch: ${2:-<unnamed>} (row ${1-} of ${3-})
Waits:    not read — the row's approvals (lib/units.sh units_approval_names, over the plan's reader
          lib/plan-read.sh plan_read_waits) could not be read, so whether this row waits for an
          approval of the person's is not known.
A row starts only on waits this hook has read.

Fix: dispatch again; if it is refused the same way, run /bionic:doctor." ;;
    nested-writer)  # <subagent type> <caller agent id> <hook channel> <caller agent type> <read-only roles>
      _dispatch_words "a subagent may launch only read-only roles" "ask the orchestrator" \
"Type: $(_dispatch_role "${1-}")
Caller: ${2-}${3:+ (channel ${3})} ${4-}

Only the orchestrator dispatches writers. A dispatch made from inside an agent may launch
one of: ${5-} — and those cannot launch further.

Fix: launch a read-only role for the help you need, or report back and let the
     orchestrator dispatch the writer on its own roster." ;;
    worktree)  # <cwd> <worktree> <main checkout>
      _dispatch_words "this dispatch came from a worktree" "dispatch from the main checkout" \
"    cwd:           ${1-}
    worktree:      ${2-}
    main checkout: ${3-}

A spawned tree is leased to the writer it was spawned for, and dispatch authority sits
with the main checkout: the roster this dispatch would be journalled to hangs off
${3-}, so a dispatch made here is recorded in one address space by an author
working in another, and the tree's lease carries no row accounting for the orchestrator.

Fix: dispatch from ${3-}. A dispatched agent working in its own tree may dispatch
from there — this refusal is the main thread's alone." ;;
    budget)  # <cap> <open> <with this dispatch> <open writer names, one per line> <ack script word>
             # <parallel-budget line> <plan> <person|scale> <scale> <hook dir>
      a=""
      while IFS= read -r b; do
        [ -n "$b" ] || continue
        a="${a:+$a
}    open: ${b} — once it has landed, close it: bash ${5-} ack $(refuse_quote "$b")"
      done <<DISPATCH_WRITERS
${4-}
DISPATCH_WRITERS
      q="budget: ${6-}
  declared by ${7-}

That cap is a person's (source=user or source=override): the hand cap verb wrote it, or
someone typed it. Nothing here raises it; raising it is that person's edit of the line."
      c="raise the plan's writers= cap"
      if [ "${8-}" = scale ]; then
        q="writers=${1-} is the ${9-} scale's writer cap (payload/scripts/lib/scale.sh),
  read for ${7-}, which carries no person's parallel-budget: line

A person's line overrides it: the hand cap verb writes one."
        c="write a parallel-budget: writers= line for the plan"
      fi
      _dispatch_words "this passes the run's writer budget" "land or stand down a row" \
"    writers: budget=${1-} open=${2-} with-this-dispatch=${3-}${a:+
$a}

${q}

Fix: land or stand down an open row first (\`bash ${10-}/stop-orders.sh
standdown\` computes the batch), or ask the user to ${c}." ;;
    in-flight)  # <name> <its row's status>
      _dispatch_words "that name is in flight" "use the FILL line's name" \
"    name: ${1-}   ·   its row on this session's roster: ${2-}

A name is an identity here. The stop gate resolves one, \`session-poker.sh adopt\` prints
one as the message address, and the landing sweep folds this roster to the latest row per
name — so two agents under one name is one contract, one address and two processes.

Fix: dispatch under the name the Patrol tick's FILL line printed for this task. It derives
one that is free: the task id, or \`<id>-r<n>\` when that id has already had a run. You never
choose a name yourself. If this row is finished, land it: the Patrol's ack, taken once the
agent is gone, frees the name — a landing marker alone does not." ;;
    deliverable-outside)  # <deliverable> <where it resolves> <project root>
      _dispatch_words "the deliverable is outside this repository" "name a path inside the repo" \
"    ${1-}
  resolves to ${2-}, which is not under ${3-}.

The landing check stats — and, for a directory, walks — whatever this names,
on every stop of the agent that owns it. It must be a path inside this repo.

Fix: name a repo-relative artifact path in the brief —
    Expected artifact: .bionic/docs/record/my-task-notes.md

Then retry the dispatch." ;;
    proto-row)  # <row>
      _dispatch_words "a prototype owns no plan row; it names Row: $(bionic_trunc "${1-}" 11)" "drop Row:" \
"    Row: ${1-}

A Kind: prototype dispatch answers a design question with a throwaway and owns no row of the plan:
nothing it writes ships, so no row waits on it and no matrix row is discharged by it.

Fix: take the Row: line off the brief. Work a row owns is dispatched without Kind: prototype, after
the plan is approved.

Then retry the dispatch." ;;
    proto-tree)  # <agent name> <the brief's tree line> <where it resolves> <none|marked|unmarked> <marker> <spawn script>
      case "${4-}" in
        none)   q="which is no linked worktree." ;;
        marked) q="a linked worktree whose marker holds the name ${5-}." ;;
        *)      q="a linked worktree carrying no marker." ;;
      esac
      _dispatch_words "throwaway tree not made for $(bionic_trunc "${1:-this agent}" 16)" "spawn it for this agent" \
"    Throwaway tree: ${2-}
  resolves to ${3-}
  ${q}

A prototype writes code only inside a throwaway tree the dispatcher spawned for it, so that nothing
it writes reaches a tree that lands. The tree is verified by its marker: the name of the agent it
was made for${1:+ (${1})}.

Fix: spawn the tree for this agent and name it on its own line:
    bash $(refuse_shell_word "${6-}") create <base-sha> <branch> --for ${1:-<name>}
    Throwaway tree: <the tree it printed>

Then retry the dispatch." ;;
    proto-path)  # <Files, comma-joined> <record root> <tree> <refused paths: `<path>TAB<tracked|outside>` a line>
      a=""; b=""; c=0; q=""
      while IFS=$'\t' read -r p w; do
        [ -n "$p" ] || continue
        case "$w" in tracked) w="is tracked" ;; outside) w="is outside both" ;; esac
        c=$((c + 1)); q="${q}    ${p} ${w}
"
        [ -n "$a" ] || { a="$p"; b="$w"; }
      done <<DISPATCH_REFUSED
${4-}
DISPATCH_REFUSED
      _dispatch_words "prototype path $(bionic_trunc "$a" 20) ${b}" "drop it from Files:" \
"    a prototype writes only under record/ or its throwaway tree; ${a} ${b}

Files:          $(printf '%s' "${1-}" | sed 's/,/, /g')
Record root:    ${2-}
Throwaway tree: ${3:-(none named)}
Refused (${c}):
${q}
A prototype ships nothing, so it may write only where nothing ships: a record under the docs root's
record/, and code inside the throwaway tree spawned for it. A path git tracks at the head is the
project own file, whichever of the two it sits under.

Fix: take each refused path off Files:. Name a record under record/, and code the prototype tries
under its throwaway tree (its own line, Throwaway tree: <path>), each path written from the project
root.

Then retry the dispatch." ;;
    no-deliverable)
      _dispatch_words "this brief names no deliverable" "add an Expected artifact: line" \
"An agent with nothing durable to produce cannot be checked on: there is no
path to stat when it reports done, and nothing left behind if it dies quietly.

Fix: declare one durable artifact path, on a line of its own —
    Expected artifact: .bionic/docs/record/my-task-notes.md
  The value is one path; the wall never guesses one from prose, and a <slot> is not a name.
  A dispatch that binds a plan row carries it in its rendered brief file: fill the row and render again.

Or waive it — the reason is recorded on the session roster either way:
    Deliverable-waiver: <why this dispatch produces nothing durable>

Then retry the dispatch." ;;
    no-suites)
      _dispatch_words "this brief declares no Files: and no Suites:" "declare Suites:" \
"An agent with no declared instrument runs whatever it decides to run, and the budget binds
only when it is on the roster row.

Fix: name the closed set of suites this task may run, on a line of its own —
    Suites: one.test.sh, two.test.sh
  For tests that are not shell suites, name each command in backticks —
    Re-executes: \`pytest tests/unit\`
  Or waive the budget for a brief that runs no suite at all —
    Suites: none
  A dispatch that binds a plan row carries these in its rendered brief file: fill the row and render again.

Then retry the dispatch." ;;
    row-unknown)  # <row> <plan>
      _dispatch_words "Row: $(bionic_trunc "${1-}" 20) names no plan row" "name a ## Tasks row id" \
"The Row: label binds this dispatch to a row of the bound plan, and the plan has no such row:
    Given: Row: ${1-}
    Plan:  ${2-}

Fix: name the id of the row this agent runs, as the plan's ## Tasks table spells it.

Then retry the dispatch." ;;
    row-mismatch)  # <row> <the name's row> <dispatch name> <plan>
      _dispatch_words "Row: $(bionic_trunc "${1-}" 11) is not the name's row $(bionic_trunc "${2-}" 11)" "rename or drop Row:" \
"The Row: label binds this dispatch to one row of the bound plan and the agent's name to another:
    Row:  ${1-}
    Name: ${3-} (row ${2-})
    Plan: ${4-}

Every wall reads one row per dispatch, so a label and a name that disagree leave the walls asking
different rows. A name that matches no row may carry any Row:.

Fix: name the agent for its row (the name the Patrol's FILL line printed), or give Row: the id that
name matches, or drop Row: and let the name bind.

Then retry the dispatch." ;;
    lands-none)  # <the path that is not prose> <the brief's reason> <Files>
      _dispatch_words "Lands-on: none, not prose: $(bionic_trunc "${1-}" 23)" "add suites or prose:" \
"Lands-on: none on a row whose Files name ${1-}, which is not prose: only a whole run at its commit proves it; name the suites that read it in Lands-on:, or list it under prose: in .bionic/config.yaml
    Given: Lands-on: none ${2-}
    Files: ${3-}

The prose list holds the record and the notes no suite executes. A path outside it is read by a suite or runs as code, so
the row must land on the suites that read it.

Then retry the dispatch." ;;
    live-writer)  # <row> <live writer> <its session> <dispatch name> <the row's tree> <this session>
      a="this session's roster"; w="${3-}"
      [ "$w" = "${6-}" ] || a="the roster of session ${w:0:8} (.bionic/tmp/roster-${w}.state)"
      _dispatch_words "row ${1-} has a live writer ${2-} (session ${w:0:8})" "stop it or ack it" \
"    row: ${1-}   ·   live writer: ${2-}   ·   session: ${3-}   ·   dispatch: ${4-}
    tree: ${5:-(none recorded)}

The row's writer is open on ${a}, so the row and its tree are still its own:
dispatching ${4-} onto it would put two writers on one row, the second asking every wall as the first.

Fix: if ${2-} is finished, land it and let the Patrol's ack close it, or stop it (stop-orders.sh
stopped writes the ack, in the session that launched it); then dispatch again. If it is still working, let it
finish. A writer of a session that is gone is taken over with session-poker.sh adopt, then acked; once that
session's files are older than the poker interval, session-poker.sh sweep removes them, and the row is free." ;;
    brief-*)  # <dispatch name> <bound row> <brief path> <hook dir> <the file's row> <the file's name>
      a="run the brief verb"
      case "$key" in
        brief-unreadable) a="reinstall the plugin"; b="the brief check lib/brief.sh cannot be loaded"
          q="The library this hook loaded has no brief_file_read, so no brief file can be read or summed." ;;
        brief-unnamed) b="the prompt names no brief file of row $(bionic_trunc "${2:-${5:-<row>}}" 11)"
          q="The prompt's first line is not a briefs/<name>.md path. A dispatch that binds a plan row is
given the file the brief verb rendered for it, and the wall reads that file, never the prompt's prose." ;;
        brief-outside) b="the brief file is outside this project"
          q="The path leaves the project root, or is a symbolic link." ;;
        brief-absent) b="the brief file the prompt names is not there"
          q="No readable file is at that path under the project root." ;;
        brief-unrendered) b="the brief file carries no render mark"
          q="Its first line is not the render's mark, so nothing says which row and name it is for." ;;
        brief-unsummed) b="the brief file's mark carries no sum"
          q="It was rendered before the render wrote a sum, so an edit since cannot be told apart." ;;
        brief-unsummable) b="the brief file's sum cannot be taken"; a="install shasum or sha256sum"
          q="Neither shasum nor sha256sum answered, so the file cannot be held to its render." ;;
        brief-edited) b="the brief file was edited after its render"
          q="The sum of the file now differs from the sum its mark records." ;;
        brief-other-name) b="the brief file is for $(bionic_trunc "${6-}" 15), not this name"
          q="Its mark names the dispatch ${6-}; this one is named ${1:-<unnamed>}. Each
dispatch has its own file, so the record keeps what each agent was given." ;;
        brief-other-row) b="the brief file is row $(bionic_trunc "${5-}" 8)'s, not row $(bionic_trunc "${2-}" 8)'s"
          q="Its mark names row ${5-}; this dispatch binds row ${2-}." ;;
        brief-slot) b="the brief file has a slot left for the orchestrator"; a="fill the row, render again"
          q="A contract line above its ## The row heading still reads <ORCHESTRATOR: ...>: the row lacks a cell
the render needs, so the file is not a contract yet." ;;
        *) return 2 ;;
      esac
      _dispatch_brief "$b" "$a" "$q" "${1-}" "${2-}" "${3-}" "${4-}" "${5-}" ;;
    roster-link)  # <roster file>
      _dispatch_words "the roster path is a symbolic link" "remove the link" \
"Roster:  ${1-}
Reason:  it is a symbolic link, and nothing is ever written through one.

No row was written, so the launch is not admitted: a dispatch the roster does not carry is one no
later wall can judge.

Fix: remove the link (rm ${1-}), then dispatch again." ;;
    row-unbuilt)  # <roster file>
      _dispatch_words "the launch row did not build" "run /bionic:doctor" \
"Roster:  ${1-}
Reason:  roster_row (payload/scripts/lib/roster.sh) refused a field of this launch.

No row was written, so the launch is not admitted: a dispatch the roster does not carry is one no
later wall can judge.

Fix: run /bionic:doctor; if it reports nothing, the library and this hook are from different
     versions — reinstall the plugin." ;;
    roster-unwritable)  # <roster file> <the append's reason> <state directory>
      _dispatch_words "the roster cannot be written" "make it writable" \
"Roster:  ${1-}
Reason:  ${2-}

No row was written, so the launch is not admitted: a dispatch the roster does not carry is one no
later wall can judge (the suite wall, amend, the Patrol and the stop guard all read the row).

Fix: make ${3-} and the roster writable by this user, then dispatch again." ;;
    *) return 2 ;;
  esac
}

dispatch_refuse() {  # <exit2|deny> <key> [facts...]
  local wire="$1"; shift
  dispatch_say "$@"
  refuse "$wire" dispatch "$DISPATCH_FACT" "$DISPATCH_FIX" "$DISPATCH_DETAIL"
}

# The first fault adds no line of its own: `refuse` renders it as the user line, so faults two and up
# cost one line each in the same `<fact> (<fix>)` shape, and every fault's detail is kept for the case
# where it stands alone.
dispatch_finding() {  # <key> [facts...]
  dispatch_say "$@"
  _DISPATCH_N=$((_DISPATCH_N + 1))
  if [ "$_DISPATCH_N" -eq 1 ]; then
    _DISPATCH_FIRST_FACT="$DISPATCH_FACT"; _DISPATCH_FIRST_FIX="$DISPATCH_FIX"; _DISPATCH_FIRST_DETAIL="$DISPATCH_DETAIL"
    return 0
  fi
  _DISPATCH_LINES="${_DISPATCH_LINES}${DISPATCH_FACT} (${DISPATCH_FIX})
"
}

dispatch_refuse_findings() {
  [ "$_DISPATCH_N" -gt 0 ] || return 0
  if [ "$_DISPATCH_N" -eq 1 ]; then
    refuse deny dispatch "$_DISPATCH_FIRST_FACT" "$_DISPATCH_FIRST_FIX" "$_DISPATCH_FIRST_DETAIL"
  fi
  refuse deny dispatch "$_DISPATCH_FIRST_FACT" "$_DISPATCH_FIRST_FIX" \
    "${_DISPATCH_LINES}See skills/canonical-sdlc/dispatch.md §Dispatch for why each line is required."
}
