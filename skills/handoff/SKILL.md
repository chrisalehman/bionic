---
name: handoff
description: 'Use when the user is about to leave the session or clear it: /bionic:handoff, "handoff", "hand off", "I''m stepping away", "write the handoff", "before I /clear". Runs the handoff verb on the bound run with the five human lines composed from this session, quotes what it wrote, and ends on the file''s last line, the one command that resumes the run after /clear.'
layer: technique
needs: []
loading: deferred
---

# Handoff

The handoff file carries a run across a `/clear` or a new session. One verb writes it from the plan and the machine; this skill adds only the five lines a person or the model knows and the record does not.

Typed as `/bionic:handoff` with no argument, it writes the run's default file, `record/<wave>/handoff.md` under the docs root. With an argument, it writes the `.md` path named, which must sit under the docs root.

`<plugin-root>` below is the plugin's root, two directories above this skill's own.

## The steps

1. Compose the five human lines from this session, one line each, plain and specific:
   - **mid-flight:** what is in motion right now, and where it stands.
   - **order:** what is dispatched next, in order.
   - **rulings:** the user's rulings this session, each with its decision number.
   - **lessons:** what this session learned that the next one would otherwise relearn.
   - **risks:** what could go wrong next, and what would show it.

   A line with nothing new is left out: the verb carries it from the previous file.

2. Run the verb, each line quoted, the path first when one was named:

   ```bash
   bash <plugin-root>/hooks/session-poker.sh handoff [<path>] --mid-flight '<text>' --order '<text>' --rulings '<text>' --lessons '<text>' --risks '<text>'
   ```

   A refusal (no bound run, a path outside the docs root) is the answer: say it in one line and stop.

3. Quote the verb's say line (`poker: handoff — written to …`). It names the file, the open rows, the live writers, and whether it is safe to clear or how many minutes to wait.

4. End on the file's last line, `/bionic:canonical-sdlc <path>`, in a fenced block, as the one thing to paste after `/clear`. That command binds the run, arms the Patrol, adopts the running agents and prints the recap; there is no other resume command.

## The rules

- Never write the handoff file by hand, and never edit it: every fact in it is the verb's, and the plan's `## Handoff` is the one pointer line the verb writes.
- When the say line reads `wait N minutes`, a landing is in flight: say so, and clear only after it lands or once the user accepts the wait.
- Nothing here changes a plan, a record or a run beyond the file and the pointer the verb writes.
