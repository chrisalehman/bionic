# Codex orchestrator dispatch on omnigent 0.12.0

Resolves [chrisalehman/bionic#28](https://github.com/chrisalehman/bionic/issues/28). Read-only
research, 2026-09-03/04. Nothing was run except `omni --version` and `codex --version`.

**Verdict: still blocks on 0.12.0, and the block is not where the W3 record put it.** The
sending client's exit was a consequence, not the cause. The cause is Codex's own MCP tool
approval: omnigent's `serve-mcp` server advertises `sys_session_send` with no tool annotations
and pre-approves it only for Smart Routing sessions, so Codex asks for approval on every call.
That approval is serviced by whatever client is attached. A headless `-p` client declines it
in 25 ms and the decline interrupts the turn. An attached REPL prints a `y / a / n` prompt and
waits for a human. No client at all parks the call for a day, and later messages are steered
into that parked turn. Every one of those three paths is byte-identical or semantically
identical between the 0.11.0 wheel and the installed 0.12.0. No upstream commit on `main`
changes the pre-approval list. A live re-measurement is needed only to confirm the predicted
behaviour of the attached form and to test two levers that source alone cannot settle.

Citation prefixes: `omni-0.12.0:` is the installed tree at
`/Users/admin/.local/share/uv/tools/omnigent/lib/python3.14/site-packages/omnigent/`
(`omni --version` → `omnigent 0.12.0 (built 2026-09-01T20:58:30Z)`); `omni-0.11.0:` is the
unpacked wheel in the uv cache at
`/Users/admin/.cache/uv/archive-v0/OHAgKvAnwpsHOhz6/omnigent/` (`METADATA` `Version: 0.11.0`);
`client:` is `omnigent_client/` beside the installed tree; `drill:` is the W3 m2 evidence
directory `/private/var/folders/rj/zjjl57pj0_z5bg90891s99tc0000gn/T/bionic-omni-drill/20260901T004701Z/`,
still intact; `omni:` is the bionic-omni checkout at `42f4cf8`. Codex CLI on this machine is
`codex-cli 0.145.0`.

## 1. What actually happened on 0.11.0 (re-read from the primary logs)

The W3 record (`omni:.bionic/docs/record/epic-20-w3/m2-dispatch-investigation.md:9-11`) says
the send "blocks indefinitely once the `omni run -p` client that launched it has exited" and
that the first call was "cancelled at client exit". The surviving logs say otherwise. All
times are local (UTC-7); the rollout is UTC.

| t | source | event |
|---|---|---|
| 17:48:32.647 | `drill:data/codex-native/…` rollout `:53` (`~/.omnigent/codex-native/e9620742…/codex-home/sessions/2026/08/31/rollout-2026-08-31T17-47-11-….jsonl`) | seat issues `sys_session_send {agent:"worker", title:"drill5"}` |
| 17:48:32.820 | `drill:data/logs/runner/runner-b2b949ba…-20260831-174707-573703.log:119` | `post_session_events … type=approval` |
| 17:48:32.821 | same `:120` | `post_session_events … type=interrupt` |
| 17:48:32.826 | `drill:data/logs/server/server-20260831-174703-498596.log:165` | `POST …/elicitations/elicit_codex_2b345d4a…/resolve 202` from port 65138 (the `omni run -p` client) |
| 17:48:32.829 | rollout `:54` | `custom_tool_call_output … "aborted by user after 0.2s"` |
| 17:48:32.831 | rollout `:57` | `turn_aborted … reason: "interrupted"` |
| 17:48:32.832 | server `:167`, runner `:125` | `POST …/hooks/codex-elicitation-request 200 OK 25.7ms` (the forwarder's long-poll returns) |
| 17:48:32.832 | rollout `:58` | `mcp_tool_call_end … server: 'omnigent', tool: 'sys_session_send' … result: {'Err': 'user cancelled MCP tool call'}` |
| 17:48:32.849 | runner `:132` | `observed completed item … item_type=mcpToolCall` |
| 00:48:35Z | `drill:logs/drill.log` | `seat orchestrator: pane exited after 90s` |

Reading: Codex raised an approval request for the MCP tool call; the forwarder posted it to
the server; the attached one-shot client answered it with a decline within milliseconds; the
decline interrupted the turn; the interrupted turn ended the one-shot run, and only then did the
pane exit. The client did not exit and take the elicitation with it. The client killed the turn.

**The request was Codex's, not omnigent's.** Omnigent's elicitation ids are deterministic
(`omni-0.12.0:codex_native_elicitation.py:26-53`, unchanged from 0.11.0), so the id in the
server log can be inverted. `codex_elicitation_id("b2b949ba…", "mcpServer/elicitation/request",
0)` reproduces `elicit_codex_2b345d4a5708c9f56d2e240310a01be5` exactly; no other recognised
method or id under 5000 does. So the app-server sent `mcpServer/elicitation/request` with
JSON-RPC id 0. The `serve-mcp` bridge itself never elicits: its tool-call path is
`_call_mcp_tool` → `_call_relay_tool` → HTTP POST to the relay
(`omni-0.12.0:claude_native_bridge.py:5077-5116`, `:5149-5195`), and no `/policies/evaluate`
line appears in the server log between 17:48:27.451 (`:162`) and the resolve (`:165`), so the
call never reached the relay or the policy engine. Both of bionic's dispatch walls
(`dispatch-deliverable`, `resume-before-dispatch`) sit behind that relay and were never asked.

**Why the one-shot client declined.** `omni run … -p` goes to `run_chat` "one-shot"
(`omni-0.12.0:cli.py:7586-7600`) → `_run_one_shot` (`chat.py:4080`) → `_query_sessions_once`
(`chat.py:2279`), which builds `SessionsChat(namespace=…, session=…, tool_callables=…)` with no
`hooks` (`chat.py:2366-2373`). The SDK then declines fail-closed: "No registered hook means
fail-closed decline … avoiding a parked workflow that waits forever for a decision the SDK will
never send" (`client:_sessions_chat.py:1107-1116`; `_invoke_elicitation_hook`, `:1505-1513`,
returns `False` when `hooks.on_elicitation_request is None`). The server's codex hook route turns
an explicit decline into an interrupt before answering Codex: "Explicit user decline: interrupt
Codex before returning the deny response" (`omni-0.12.0:server/routes/sessions/routes_hooks.py:1022-1031`).
That is the `type=approval` / `type=interrupt` pair in the runner log.

**Why the second and third sends hung.** After the pane exited there was no client. The drill's
grace-poll posted two more instructions; each started a fresh turn (`runner:151` 17:51:30
`started turn 01a05a73…`, `:205` 17:55:08 `started turn 01a05a76…`), the seat sent again
(rollout `:72` drill6, `:81` drillprobe), Codex raised the same approval, and the forwarder's
long-poll parked server-side with nobody subscribed. The park is a day on both ends:
`_CODEX_NATIVE_ELICITATION_HOOK_TIMEOUT_S = 86400.0`
(`omni-0.12.0:server/routes/_sessions/common.py:393`) and
`_CODEX_ELICITATION_REQUEST_TIMEOUT_SECONDS = 86405.0` (`codex_native_forwarder.py:118`). The
wait ends only on a web verdict, a native-side resolution, or upstream disconnect/timeout
(`server/routes/_sessions/orchestration.py:359-384`). Uvicorn writes an access line only when a
request completes, so a parked long-poll leaves the server log silent, which is exactly the
"server log goes quiet after 17:55:11" the record noticed. The record's "no elicitation" for
attempts 2 and 3 is an absence of a resolve line, not an absence of a request.

**Why the citizen instructions were swallowed.** With the turn still active from Codex's point
of view, the next two POSTs were injected with `turn/steer` (`runner:224` 18:00:10, `:232`
18:10:14 `Codex native steered active turn: turn_id=01a05a76…`). A steer queues input behind
the pending tool call; the tool call is waiting on an approval nobody will give.

The record's own mitigation guess was wrong in a useful way. The drill was changed the same night
to launch codex seats attached (`omni:tests/drill/instrument.test.sh:1991-2003`; commit
`3185095`, 2026-08-31 18:59 -0700, "a codex seat keeps its client for the life of the session")
on the theory that a live client would have "somewhere to resolve". A live REPL client does
resolve it, by asking a human (§2). No codex-orchestrator drill has run since that commit
(`omni:` W4/W5 records contain no codex-native orchestrator table; the proven ledger's rung 7
row is still the W3 run).

## 2. The 0.12.0 code path, link by link

Each link is cited in the installed tree, then compared with the 0.11.0 wheel.

**Link 1: Codex asks.** Omnigent writes the session's `config.toml` with a `[mcp_servers.omnigent]`
table and a per-tool `approval_mode = "approve"` only for `framework_approved_tools(...)`
(`omni-0.12.0:codex_native_app_server.py:234-270`, render at `:263-265`). That list is
`("sys_session_rename",)` for every ordinary session; `sys_session_create`, `sys_agent_list`,
`sys_session_send`, `sys_read_inbox` are added only when `routed_spawns=True`, i.e. "an
auto-harness Smart Routing session" (`:198-231`). The comment on the routed list names the
failure this research found: "Without the last one the redirect stalls on an approval prompt
nobody is watching. A plain or pinned session can never receive a redirect, so it gets none of
them and its approval surface stays a plain codex session's" (`:207-212`). The W3 session's
config confirms the shape: `~/.omnigent/codex-native/e9620742…/codex-home/config.toml:20-25`
carries `[mcp_servers.omnigent]` and one `[mcp_servers.omnigent.tools.sys_session_rename]
approval_mode = "approve"`, nothing for `sys_session_send`. The rollout's
`thread_settings_applied` (`:72`) shows the session ran at `approval_policy: "on-request"`,
`approvals_reviewer: "user"`.

On the Codex side the rule is in `codex-rs/core/src/mcp_tool_call.rs` at
[openai/codex `main` @ 956aa3f](https://raw.githubusercontent.com/openai/codex/main/codex-rs/core/src/mcp_tool_call.rs):

```rust
fn requires_mcp_tool_approval_for_mode(annotations, approval_mode) -> bool {
    match approval_mode {
        AppToolApproval::Auto => requires_mcp_tool_approval(annotations),
        AppToolApproval::Prompt => true,
        AppToolApproval::Writes => !annotations.and_then(|a| a.read_only_hint).unwrap_or(false),
        AppToolApproval::Approve => false,
    }
}
```

with `Auto` the default when nothing is configured, and `requires_mcp_tool_approval` true
"unless the tool has read_only_hint set to true". The bridge advertises relay tools with only
`name`, `description`, `parameters` (`omni-0.12.0:claude_native_bridge.py:5211-5237`), so no
annotation is ever present and every un-pre-approved omnigent tool prompts. The same file also
answers the obvious escape: under `approval_policy = Never` the call is refused, not allowed:
`ReviewDecision::denied("MCP tool call requires approval, but approval policy is never")`.
The docs agree in outline ("Codex can also elicit approval for app (connector) tool calls that
advertise side effects", [Agent approvals & security](https://learn.chatgpt.com/docs/agent-approvals-security);
`mcp_servers.<id>.tools.<tool>.approval_mode` "Per-tool approval behavior override for one MCP
tool on this server", values `auto | prompt | writes | approve`,
[Configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference)). The
codex version that decided the W3 run is not in the evidence (`unverified`); the installed CLI
is 0.145.0 and the rule above is `main` today.

0.11.0 vs 0.12.0: the whole approvals block, from `_FRAMEWORK_APPROVED_TOOLS` through
`_codex_mcp_server_config_section`, is byte-identical (`diff` of that span is empty; 0.11.0 lines
`201-231`). `_inject_mcp_server_config` is also unchanged and matters for the route-around
question: it strips the entire `mcp_servers.omnigent` table "and its subtables" from the copied
user config before appending its own (`omni-0.12.0:codex_native_app_server.py:176-198`,
`:434-475`), so a pre-approval placed in `~/.codex/config.toml` never survives into a session.

**Link 2: omnigent forwards and parks.** The forwarder recognises seven server-to-client
methods including `mcpServer/elicitation/request` (`codex_native_forwarder.py:185-195`),
POSTs the envelope to `/hooks/codex-elicitation-request` and waits up to 86405 s, re-posting
across severed long-polls (`:3758-3795`, `:3870-3935`); an empty body means "leaving
app-server request pending" (`:3833`). The server route parks a Future, publishes
`response.elicitation_request` to the session stream, and waits 86400 s
(`routes_hooks.py:963-1035`; `orchestration.py:359-384`). A decline is turned into an
interrupt before the deny reaches Codex (`routes_hooks.py:1022-1031`). Every one of these
constants and branches is present at the same values in 0.11.0 (`omni-0.11.0:…common.py:378`,
`codex_native_forwarder.py:116`, `routes_hooks.py:1010`); the GitHub compare
`v0.11.0...v0.12.0` lists `routes_hooks.py`, `_sessions/common.py` and `_sessions_chat.py`
with `+0 -0`.

**Link 3: who answers.**
- Headless `-p`: declines in milliseconds, unchanged (`chat.py:2366`;
  `client:_sessions_chat.py:1505-1513`, `+0 -0` in the compare).
- Interactive REPL (the product's tmux form and the drill's post-`3185095` form): the SDK
  routes the event to `_make_elicitation_prompt` (`omni-0.12.0:repl/_repl.py:984-1110`), which
  prints "⚠ approval required" and "y = approve once, a = approve always (this session), n =
  refuse" and awaits a keystroke on the main input loop (`:1059`, `:1102`, `:1108-1109`). With
  no human at the pane the turn waits for the day-long timeout. `a` caches
  `(policy_name, phase)`; every Codex MCP elicitation is published with the same fixed pair,
  `policy_name="codex_native_mcp_elicitation"`, `phase="codex_mcp_elicitation"`
  (`server/routes/_codex_elicitation.py:557-580`, `_codex_mcp_elicitation_params`), so one `a`
  pre-approves every later Codex MCP elicitation in that REPL session
  (`_repl.py:1046`, `state.is_pre_approved(ctx.policy_name, ctx.phase)`). `unverified` live;
  read from source.
- Web UI: an approval card; a human clicks.
- No client: parks for a day.

**Link 4: the steer.** 0.12.0 is the one place the code changed. `enqueue_session_message`
(`inner/codex_native_executor.py:230-271`) and `run_turn` (`:331-441`) now both go through
`_inject_codex_turn` (`:145-190`), which still steers whenever the bridge records an active turn.
The new part recovers exactly one case: Codex answers `-32600 "no active turn to steer"`, i.e.
the turn had already ended, and the bridge then clears the stale id and starts a fresh turn
(`:58-68`, `:166-190`). That is upstream PR
[#5398](https://github.com/omnigent-ai/omnigent/pull/5398) "Fix stale Codex turn steering after
completion", merged 2026-08-24 and inside the `v0.12.0` tag (`f04b0354`); its summary is
"Omnigent sometimes still had turn A marked 'active' after Codex had finished it, so the next
message was sent to a closed turn." A turn parked on an unanswered approval has not finished, so
Codex accepts the steer and the message queues behind the pending tool call exactly as on
0.11.0 (`omni-0.11.0:inner/codex_native_executor.py:112-125`, `:279-290`, the pre-refactor
`turn/steer` branches). Pending hook waits are cleared only when the turn actually ends
(`codex_native_forwarder.py:1627-1660`, `resolve_by_terminal_turn_event`).

**Link 5: the send itself is not the blocker.** `_execute_subagent_tool` "returns a launching
handle immediately" (`omni-0.12.0:runner/tool_dispatch.py:1986-2004`; same sentence at
`omni-0.11.0:runner/tool_dispatch.py:1850-1851`). Once the approval is granted the dispatch is
non-blocking on both versions. The W3 investigation's read of PR
[#6359](https://github.com/omnigent-ai/omnigent/pull/6359) as a possible fix does not apply:
that PR (still open, `merged_at: null`) is about the parent→child direction, "Both
sys_session_send dispatch paths … blanket-refused any send to a child with a non-terminal turn",
not about the parent's own turn.

**Upstream trajectory.** `omnigent-ai/omnigent` `main` is at `a9e7634` today (the brief's
`571622d6` is behind). Commits to `codex_native_app_server.py` since 0.12.0
(`gh api …/commits?path=…`): #6227 hooks trust, #6249 provider config, #6270 rollout fallback,
and #5864 (merged 2026-09-03 22:35 UTC, `8488dfc7`). None touches `framework_approved_tools`;
the `main` copy of the file still defines
`_FRAMEWORK_APPROVED_TOOLS = ("sys_session_rename",)` and the four-tool routed list (fetched
from `raw.githubusercontent.com/omnigent-ai/omnigent/main/omnigent/codex_native_app_server.py`).
[PR #5864](https://github.com/omnigent-ai/omnigent/pull/5864) is the one live thread worth a
measurement: for a codex-native session "created with the default (Auto) permission stance"
it now appends `-c approvals_reviewer="auto_review"` "so Codex's automatic reviewer settles
eligible escalated requests instead of prompting". Its stated target is
`item/commandExecution/requestApproval` (out-of-workspace writes); whether Codex's auto reviewer
also adjudicates `mcpServer/elicitation/request` is `unverified` (the codex tree has a
`codex-rs/core/tests/suite/guardian_mcp_elicitation.rs`, which says the guardian path can see
MCP elicitations, but I did not read it). It is post-0.12.0 and unreleased. A GitHub search of
the omnigent tracker for `sys_session_send` + codex (issues and PRs, 30 hits) returns nothing
about pre-approving the spawn tools for ordinary sessions; the closest are #2428 "sys_session_send
to a completed session hangs to ReadTimeout" (closed) and #5662 (closed), both on the child side.

## 3. Verdict

**Still blocks on 0.12.0.** Not fixed at any commit. The three exits of the block are unchanged:

| launch form | 0.11.0 | 0.12.0 (installed) | basis |
|---|---|---|---|
| `omni run … -p` (W3's form) | declined in 25 ms, turn interrupted, send never dispatched | same | `chat.py:2366`; `_sessions_chat.py:1505-1513`; `routes_hooks.py:1022-1031`; compare `+0 -0` |
| attached REPL (drill since `3185095`, product tmux form) | human `y/a/n` prompt; unattended = day-long park | same | `_repl.py:984-1110`; `common.py:393` |
| no client | day-long park; later POSTs steered into the parked turn | same, plus recovery only for a turn Codex reports as already ended | `_inject_codex_turn` `:145-190`; PR #5398 |

What changed the picture is the cause, which moves the ask from "omnigent, time out a hung send"
to "omnigent, pre-approve the spawn toolkit for any session whose spec grants it". Ordinary
bundle sessions with `spawn: true` or `tools.agents` get the same four tools the Smart-Routing
path already pre-approves; the code change is one predicate in `framework_approved_tools`.
Until then no all-Codex unit can dispatch unattended on any released omnigent.

## 4. What a live re-measurement has to plant

The measurement is cheap because the 0.11.0 evidence already fixes the read-out: the elicitation
id is derivable, the server logs the resolve, the rollout logs the MCP result. Read the same
three surfaces; do not read the seat's prose.

Plant, per cell:

1. **Control, attached REPL, nobody answers.** The drill's current codex launch line (`exec omni
   run "<bundle>" --server "<url>"`, `omni:tests/drill/instrument.test.sh:2053`). Expected on
   0.12.0: the pane shows "approval required"; server log shows a `hooks/codex-elicitation-request`
   POST with no completion line; rollout shows `mcp_tool_call` with no `mcp_tool_call_end` for
   the wait window; runner log `steered active turn` on the next POST. This is the row that
   converts the ledger's "refuted (0.11.0)" into "refuted (0.12.0)" with the cause named.
2. **One keystroke.** Same launch, then `tmux send-keys a Enter` into the pane when the prompt
   appears (or once, blind, after the first send). Expected: `POST …/elicitations/<id>/resolve
   202`, then `POST /v1/sessions` creating the child, then `POST …/policies/evaluate` for the
   `dispatch-deliverable` wall. If the `a` pre-approval works as read from `_repl.py:1046-1054`,
   the second send in the same session produces no prompt at all. This is the cheapest unattended
   drill form available today, and it also puts bionic's dispatch walls in front of a Codex seat
   for the first time.
3. **Bionic-owned attendant (the durable form).** Attach `omnigent_client.SessionsChat` with
   `hooks=StreamHooks(on_elicitation_request=<accept iff message names sys_session_send /
   sys_session_create / sys_read_inbox>)` (`client:_tool_handler.py:293-349`). This is a
   route-around omnigent has no seam for; it should be recorded as one on the seam inventory.
4. **Negative control, bypass.** Launch with `--dangerously-bypass-approvals-and-sandbox` /
   `approval_policy="never"` (`omni-0.12.0:codex_native_app_server.py:2953-2980`,
   `normalize_codex_permission_launch_args`). Expected per the codex source: the MCP call is
   denied with "MCP tool call requires approval, but approval policy is never"; the rollout
   `mcp_tool_call_end` carries that error. This cell exists to kill the tempting "just bypass"
   route-around with evidence.
5. **Post-0.12.0 lever, only after an omnigent bump.** Default stance with
   `-c approvals_reviewer="auto_review"` (PR #5864). `unverified` whether the reviewer settles
   `mcpServer/elicitation/request`; the cell reads the same three surfaces.

Not plantable: a per-tool `approval_mode = "approve"` in the user's `~/.codex/config.toml`,
because `_inject_mcp_server_config` strips `mcp_servers.omnigent` and every subtable before
writing its own (`:473`). Do not spend a cell on it.

Instruments to carry: the deterministic-id inversion used in §1 (a five-line script against
`omnigent.codex_native_elicitation.codex_elicitation_id`) so any future `elicit_codex_*` line can
be attributed to its Codex method without guessing.

## 5. Corrections to the standing record

- `m2-dispatch-investigation.md:11` "blocks indefinitely once the `omni run -p` client … has
  exited": the first send was declined by the still-attached client; the exit followed the
  decline. Attempts 2 and 3 hung because no client existed to be asked, which is the same
  approval gate with nobody at it.
- `:65` "no elicitation" for attempts 2 and 3: no *resolved* elicitation. A parked long-poll
  leaves no server log line.
- `:71` "a launch form that keeps a client attached … would have given attempts 2 and 3
  somewhere to resolve": true, and the somewhere is a human at a keyboard.
- Proven ledger rung 7, row 1 note: the cause is Codex's MCP tool approval, not an omnigent hang.
  The A-W1-24(c) "not seat-behavioural" reading stands.
- Seam inventory S6 trajectory line on PR #6359: unrelated to this block.

## Sources

Primary, local: files cited above under `omni-0.12.0:`, `omni-0.11.0:`, `client:`, `drill:`,
`omni:`; `~/.omnigent/codex-native/e9620742…/codex-home/{config.toml,sessions/…/rollout-….jsonl}`.
Primary, remote:
[omnigent-ai/omnigent PR #5398](https://github.com/omnigent-ai/omnigent/pull/5398),
[PR #5864](https://github.com/omnigent-ai/omnigent/pull/5864),
[PR #6359](https://github.com/omnigent-ai/omnigent/pull/6359),
[v0.12.0 release](https://github.com/omnigent-ai/omnigent/releases/tag/v0.12.0),
`main` copy of `omnigent/codex_native_app_server.py` (raw.githubusercontent.com, fetched 2026-09-04),
[openai/codex `codex-rs/core/src/mcp_tool_call.rs` @ main 956aa3f](https://raw.githubusercontent.com/openai/codex/main/codex-rs/core/src/mcp_tool_call.rs),
[openai/codex PR #17843](https://github.com/openai/codex/pull/17843) (server-level
`default_tools_approval_mode`, precedence "per-tool override, then server default, then auto"),
[Codex configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference),
[Codex agent approvals & security](https://learn.chatgpt.com/docs/agent-approvals-security).
