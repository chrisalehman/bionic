---
name: handoff
description: 'Use when the work has to continue in another session: /bionic:handoff, "handoff", "hand off", "hand this off", "I''m stepping away", "write the handoff", "before I /clear", or a copy of the work going to a fork while this session goes on. Works with or without a bionic run. Composes the sections only this session knows, runs the handoff verb with them, and ends on the file''s last line, the way the next session resumes.'
layer: technique
needs: []
loading: deferred
---

# Handoff

The handoff is one document a fresh session continues from without asking what was going on. Assume this session can be killed the moment the file is written. One verb writes the file: it computes the State (branch, head, uncommitted files, what runs, the agents, and the plan, step, open tasks and Patrol when a run is bound), redacts secrets, and adds the last line. This skill composes the rest and writes nothing else.

Typed as `/bionic:handoff` with no argument, it hands off whatever this session is doing. With an argument, the argument names what the next session is for (`/bionic:handoff review the parser change`): the document is tailored to that purpose, and the verb puts it in the title and, with no run bound, in the file name.

`<plugin-root>` below is the plugin's root, two directories above this skill's own.

## The steps

1. Compose the sections from this session, tailored to the purpose when one was given. Plain and specific, one line per item:
   - **Summary**, exactly four lines: `Doing:` what is in motion and where it stands; `Learned:` what the next session would otherwise relearn; `Open:` the question that decides what comes next; `First:` the first thing to do.
   - **Goal**: the person's own words, quoted verbatim, with who said them and when. Never a summary of them.
   - **Findings**: one fact per line, each ending on its source: a path with its line, a log, a commit or a URL. A finding you cannot source ends on `unverified`; the verb marks any line with no source that way.
   - **Decisions**: each ruling with who made it, when, and their words in quotes. A call you made yourself says so: `(the agent's call)`.
   - **Ruled out**: each approach dropped, with the evidence that dropped it.
   - **Open**: each unknown, labelled `hypothesis:` or `question:`.
   - **Suggested skills**: the skills the next session should reach for, and when.
   - **Next**: the commands to run, in order, the first one verbatim in backticks.

   Name a settled artifact (a spec, a plan, a log, a design) by its path; never paste it. A pasted block is left out by the verb. Leave a section out when it has nothing: the verb prints `- none.` under it. Never write State or Resume: they are the verb's.

2. Run the verb with the sections on its stdin, each under its heading, the purpose quoted when there is one:

   ```bash
   bash <plugin-root>/hooks/session-poker.sh handoff ['<purpose>'] <<'HANDOFF'
   Summary
   - Doing: <text>
   - Learned: <text>
   - Open: <text>
   - First: <text>

   Goal
   - "<the person's words>" (<who>, <when>)

   Findings
   - <fact> — <source>

   Decisions
   - <who> ruled "<their words>" (<when>)

   Ruled out
   - <approach> — <evidence>

   Open
   - hypothesis: <text>

   Suggested skills
   - <skill>, <when>

   Next
   - `<the first command>`
   HANDOFF
   ```

   A refusal is the answer: say it in one line and stop.

3. On success the verb prints one line, the file's last line, and nothing else. It is the one thing the next session needs, and it is your whole closing message: the line in a fenced block, with nothing after it. With a run bound the next session types it to rebind the run, arm its Patrol at a scale that has one and adopt the running agents. Typing it is the consent: the resume engages the session itself when the slash command did not, and says so in its first line. The resume prints about a dozen lines (bound, the step, the agents still open, what landed since, what is owed now, the Patrol) and the path of one recap file holding the rest. With no run the line is `Read <path> whole, then do Next 1.` and goes in the same fence. A second line, saying the plan's pointer was not written, is a warning about the plan, not the file: say it in one sentence above the fence. The last thing you write, with a run bound, is:

   ```
   /bionic:canonical-sdlc <path>
   ```

## The rules

- Never write the handoff file by hand, and never edit it: State is computed, and the rest passes through the verb's redaction.
- The document lives under `.bionic/docs/record/handoffs/`, which git never tracks; the verb creates the folder and its ignore file when the project has none.
- Nothing here changes a plan, a record or a run beyond the file and, with a run bound, the plan's `## Handoff` pointer the verb writes.
