---
ticket: chrisalehman/bionic#21 (map #19, R2)
kind: research
subject: omnigent 0.12.0 seam inventory — behaviour · intent · trajectory, and where each bionic-omni piece stands
written: 2026-09-04
installed: omnigent 0.12.0 (wheel built 2026-09-01T20:58:30Z; INST = /Users/admin/.local/share/uv/tools/omnigent/lib/python3.14/site-packages/omnigent)
upstream: github.com/omnigent-ai/omnigent, main @ 571622d6 on 2026-09-04 (211 commits ahead of v0.12.0)
adapter: bionic-omni @ 42f4cf8 (`omni:` citations), branch epic/20-bionic-on-omnigent
method: installed source read directly (file:line); upstream via `gh api` and raw docs, quoted with URL; agent paraphrase treated as a lead only
---

# omnigent 0.12.0 seam inventory

## Headline

The adapter stands on real seams for its walls and its roster, and routes around omnigent for
everything that touches a seat at launch. 0.12.0 changed that picture in three places, and two of
them are already live on this machine:

1. **Role text is delivered by omnigent now.** `instructions:` reaches claude-native by
   `--append-system-prompt` and codex-native by `developer_instructions` (PR #3929, in 0.12.0).
   The shim's identity compose, the Codex SessionStart prompt hook, `write_seat_prompts` and the
   rendered `seat-prompt.md` files are obsolete and, until deleted, duplicate the text.
2. **Per-seat effort is a spec field now.** `executor.reasoning_effort` (PR #5753, in 0.12.0)
   reaches a claude-native seat as `--effort`. The shim's effort append and `params.seat.effort`
   are obsolete.
3. **There is a sanctioned launch-wrap seam.** `claude_launcher.py` (PRs #1476/#1525, merged
   2026-06-27/28, allow-listed across the daemon→runner boundary in 0.12.0) lets an installed
   Python entry point receive the fully augmented `claude` argv — `--settings` path included —
   and rewrite it. It is the seam the PATH shim exists for want of. It carries no codex twin.

Three walls stay route-arounds with nothing upstream heading for them: the writer-delivered
Stop hook (no turn-end policy phase exists or is planned), the externally armed pulse (no route
arms a timer; scheduled tasks start fresh sessions), and bundle-declared harness hooks and tool
denial (no spec field, no issue). The launcher's server-lifecycle blocks are unchanged except
that 0.12.0's daemon election makes `ensure_host_daemon` idempotent by omnigent's own hand.

Counts: 26 seams inventoried; of 41 adapter pieces, 17 stand on a seam, 20 route around one,
4 are bionic's own surface with no seam needed. 6 route-arounds are obsolete on the installed
0.12.0 today; 3 more have a merged upstream change waiting for the next release.

## 1. Seam inventory

Each seam: what it delivers · **behaviour** (installed 0.12.0, file:line under INST) · **intent**
(docs, docstrings, PR history) · **trajectory** (main since v0.12.0, open issues). Where a 0.11.0
citation from the epic-20 record was re-verified unchanged it is marked *(unchanged)*.

### Spec and policy seams

**S1 — `guardrails.policies`, `type: function`.** A bundle attaches Python callables as policies.
- Behaviour: parsed under `guardrails:` only; a top-level `policies:` key is not read and no
  unknown-key check rejects it — `spec/parser.py:246` (`guardrails = _parse_guardrails(raw.get("guardrails"), …)`). Function policies get `on=None`
  and self-select on `event["type"]`/`event["target"]` — `spec/parser.py:3259`, `:3282-3294` ("For ``type: function`` policies … the ``on`` field is ignored — the callable self-selects"). The
  callable contract is `evaluate(event, config) -> {"result": ALLOW|DENY|ASK, "reason", "data"?,
  "state_updates"?} | None` — `policies/function.py:25`, `:475-487`.
- Intent: docs/POLICIES.md — "`type` | yes | `\"function\"`", "`handler` | yes | Dotted Python
  import path to the callable or factory", "`factory_params` | no | Key-value arguments passed to
  a factory at build time" (https://github.com/omnigent-ai/omnigent/blob/main/docs/POLICIES.md).
  The bundle-form example in omnigent's own onboarding skill uses `guardrails: policies:
  blast_radius: type: function function: path: …`
  (https://github.com/omnigent-ai/omnigent/blob/main/omnigent/onboarding/agent/skills/omnigent-knowledge/SKILL.md).
  docs/AGENT_YAML_SPEC.md still spells the key top-level `policies:` — the docs and the parser
  disagree, and the parser wins.
- Trajectory: PR #6043 (merged 2026-09-03, post-0.12.0) "enforce a sub-agent's own guardrails on
  its conversation" — "A sub-agent conversation's policy engine was built from the **root**
  bundle spec only … the child spec's `guardrails.policies` were silently dropped at runtime"
  (https://github.com/omnigent-ai/omnigent/pull/6043). bionic declares every policy on the root
  bundle, so 0.12.0's drop did not bite; after the next release a role's own `config.yaml` can
  carry role-scoped walls. PR #6022 lets CEL policies write `state_updates` — a code-free wall
  channel bionic has not used.

**S2 — `policy_modules` (server config).** How a custom handler becomes importable.
- Behaviour: server-config only; the dotted name is imported with importlib — `spec/__init__.py`
  `spec/__init__.py:399`; `policies/registry.py:196-202` ("``policy_modules`` — is the single allowlist of policy handlers"). The HTTP policy routes (`POST /v1/policies`, `POST /v1/sessions/{id}/policies`)
  enforce the same registry allow-list, so they attach policies to sessions but do not admit a
  handler the server did not load `server/routes/session_policies.py:182-190` ("Restrict handlers to the registry allowlist … is not registered").
- Intent: docs/policies/custom — "Add the module to your server config: policy_modules: -
  myorg.policies" (https://omnigent.ai/docs/policies/custom).
- Trajectory: nothing bundle-local. Search `policy_modules bundle` on the tracker returned only
  #5939 (an unrelated claude-sdk RESPONSE-phase bug).

**S3 — policy phases and session state.**
- Behaviour: the phase enum has six members — `request`, `tool_call`, `tool_result`, `response`,
  `llm_request`, `llm_response` — `policies/schema.py:229-236`. No phase fires at a turn end,
  a Stop, or session end. `session_state` persists across turns and a DENY's own `state_updates`
  are applied — `runtime/policies/engine.py:361-362`, `:398`, `:440`. `data` on ALLOW replaces the payload
  `runtime/policies/engine.py:371-372`. Session policies are inherited by children `runtime/policies/builder.py:298`, `:477` *(unchanged from F8)*.
- Intent: docs/policies/custom lists the four author-facing phases and says of `response`:
  "Omnigent is about to deliver an assistant message" (https://omnigent.ai/docs/policies/custom).
- Trajectory: #765 (open) "Support interactive mid-flight policy ASK … currently collapsed to
  DENY"; #5939 (open) "RESPONSE phase never fires, LLM_RESPONSE DENY is discarded" on claude-sdk.
  Nothing proposes a completion or turn-end phase.

**S4 — the native policy hook (claude-native).** What a seat's own hooks report to the mediator.
- Behaviour: omnigent's `--settings` file registers `SessionStart`, `Stop`, `StopFailure`,
  `UserPromptSubmit`, `TaskCreated`, `TaskCompleted`, `PostToolUse` (TodoWrite/TaskUpdate),
  `PreCompact`, `MessageDisplay`, `PermissionRequest`, `PreToolUse` — `claude_native_bridge.py`
  `claude_native_bridge.py:1481-1527`, `:1566`, `:1632-1649`, built by `build_hook_settings` (`:1388`). Of those, `PreToolUse` (the catch-all `evaluate_policy_hook`), `PostToolUse` and
  `UserPromptSubmit` POST to the server for evaluation `claude_native_bridge.py:1601`, `:1632-1649`; `Stop`/`StopFailure` carry the
  transcript forwarder, write to `hooks.jsonl` and return 0 `claude_native_bridge.py:93`, `:2782`; `claude_native_forwarder.py:58`; `SubagentStop` is never
  registered. The evaluate route's wire-phase map has no `PHASE_RESPONSE`, so a hook cannot submit
  one `server/routes/sessions/routes_hooks.py:508-535` (entries: `PHASE_TOOL_CALL`, `PHASE_TOOL_RESULT`, `PHASE_LLM_REQUEST`, `PHASE_LLM_RESPONSE`, `PHASE_REQUEST`). `PermissionRequest` routes Claude's own ask to the web UI; only
  `bypassPermissions` suppresses it — `claude_native_bridge.py:1566`, `:1606-1608` ("In bypassPermissions mode PermissionRequest never fires"). That is the mechanism behind the parked
  claude-native test-runner (W6 slice 2): `auto` is on argv, and the park is the hook.
- Intent: the bridge's comments frame these as omnigent's own bridge, not an extension point;
  PR #6043's wording ("policy engine … built from the … bundle spec") confirms policies are the
  intended wall surface, hooks are plumbing.
- Trajectory: main since v0.12.0 touches hooks only for codex (#6227). #4443 (open) concerns the
  SessionStart hook's interpreter path on WSL.

**S5 — sub-agent completion (`PHASE_TOOL_RESULT` at inbox drain).**
- Behaviour: evaluated server-side when the parent drains its inbox; DENY rewrites the delivered
  text to `[Result suppressed…]`; cannot hold or re-open the worker; `cancelled` bypasses policy;
  eval failure suppresses and requeues — `server/routes/_sessions/orchestration.py:9202`; `runner/tool_dispatch.py:173`, `:7196` *(unchanged from F3)*.
- Trajectory (in 0.12.0): #5867 "Sub-agent completions now reach the parent session even when
  the server was briefly down … the runner re-delivers the wake after it reconnects"; #5630
  completes-before-stop reports `completed`/`failed` not `cancelled`. Post-0.12.0: #6238 "Recover
  sub-agent results after runner restart via delivery receipts", #6225 "mirror child status edges
  onto the parent stream", #5856 "keep native sub-agent failures from being laundered or lost".
  The completion channel bionic's backstop and tick duties read is getting more reliable, not
  changing shape.

**S6 — the roster tools: `tools.agents`, `spawn:`, `sys_session_create/send/get_info/close`.**
- Behaviour: `tools.agents` names are validated against discovered sub-agents' `name:`
  `spec/parser.py:456` (`tools.agents must be a list`), `:267-276`; `spawn:` is the broader grant — `spec/parser.py:268-273`: "Top-level ``spawn:``
  flag grants spawning OUTSIDE any declared sub-agent list: ``sys_session_create`` (existing
  agents by id, or custom bundles via config_path) plus send/close to drive the children.
  Distinct from ``tools.agents``". `sys_session_create` takes `agent_id, config_path, title,
  message, model, reasoning_effort` and nothing else — no `cwd`, `workspace`, `worktree`,
  `deadline` `tools/builtins/spawn.py:937-987`. `executor.timeout` and `max_iterations` are parsed and never read
  `spec/parser.py:685-686`; a tree-wide grep for `executor.timeout`/`.max_iterations` outside `spec/` returns nothing *(unchanged from F4)*. `sys_session_get_info` returns `last_activity_at` and
  `runner_online` `tools/builtins/spawn.py:655`. `sys_session_close` is a metadata tombstone that signals no
  process (`omni:bundle/scripts/reap-closed.sh:6-11`, citing `tools/builtins/spawn.py`).
- Intent: onboarding SKILL.md — "The parent's config.yaml lists sub-agent names under
  `tools.agents` … Each name must be the declared `name` of a sub-agent under `agents/` … The
  **parent** must use `executor.type: omnigent` — that's what provides the spawn tools."
- Trajectory: #5871 (0.12.0) sub-agents inherit the session's model when a dispatch names none.
  PR #6359 (open) rewrites `sys_session_send` to steer in-flight children and fixes the stale
  "returns the child's output" description (bionic ask row 15). PR #3273 (open) per-dispatch
  `reasoning_effort` on `sys_session_send`. Nothing on `cwd`/worktree or per-dispatch deadline.

**S7 — timers and the events route.**
- Behaviour: `sys_timer_set` is a runner-local `asyncio.sleep` task, cancelled at teardown, not
  persisted `runner/tool_dispatch.py:350` ("Timer tools — runner-local asyncio.sleep tasks"); `runner/app.py:2183-2198`; it fires by POSTing `[System: timer {id} fired]` with `is_meta: true` to
  `POST /v1/sessions/{id}/events` `runner/tool_dispatch.py:3654-3664` — the generic events route the pulse also uses.
  No route arms a timer; scheduled tasks (`server/scheduled/*`) create a fresh session per firing
  and take no target conversation `entities/scheduled_task.py:4-5` ("fires an agent session on a recurring schedule"); `server/scheduled/fire.py:420`, `:717`. A docstring at `spec/types.py:1511-1517` claims
  restart-durable workflow-backed timers; the implementation is in-memory.
- Intent: `tools/builtins/timer.py` docstring — "The firing itself runs in the runner … A firing
  arrives as a hidden ``[System: timer X fired]`` meta message that wakes the session on the
  normal ingest path."
- Trajectory: no commit or issue on session timers since v0.12.0. Automations' open item #4783
  says "missed fires are explicitly not replayed" and "The minimum interval is one hour".

**S8 — `params:`.**
- Behaviour: parsed at `spec/parser.py:249` (`params = raw.get("params", {})`) and read by nothing in the package. A
  function policy's `config` argument is its own `config:` block, never bundle params.
- Intent: AGENT_YAML_SPEC — "`params` | Optional | Typed user parameters available to
  tools/skills."; SKILL.md — "params: # Arbitrary key-value (readable by skills/tools)".
- Trajectory: none. bionic's use (roster, pulse, walk, fallback_all) is a data channel it reads
  with its own parsers; that is consistent with intent and cannot break, but nothing in omnigent
  honours a value placed there.

### Launch and identity seams

**S9 — `instructions:` delivery (`InstructionDelivery`).**
- Behaviour: `harness_capabilities.py` declares the enum; `harness_plugins.py` marks
  claude-native and codex-native `AGENT_STARTUP_ADDITIVE`, claude-sdk
  `COMPOSED_SESSION_SNAPSHOT`, nine natives `NOT_DELIVERED` `harness_capabilities.py:88`; `harness_plugins.py:343`, `:358` (additive), `:518` (snapshot), `:379-629` (ten `NOT_DELIVERED`).
  `_native_startup_raw_instructions_from_spec` joins the verbatim author text with the routing
  note into one `--append-system-prompt` (`runner/native/orchestration.py` `:5477`, `:6844-6846`) and into
  `developer_instructions` for codex `runner/native/orchestration.py:4102`, `:4120`. The top-level bundle agent resolves its own
  spec through the same path — `runner/app.py:3446`, `:9470` — so the orchestrator's text can
  ride `instructions:` too. Per-turn composed prompts are still dropped: `del tools,
  system_prompt` at `inner/claude_native_executor.py:143` and `inner/codex_native_executor.py:354`,
  now documented as deliberate ("claude-native delivers raw author instructions once, at terminal
  launch") `inner/claude_native_executor.py:129-133`. NOT_DELIVERED harnesses warn once `runner/app.py:2426`, `:6684-6687`.
- Intent: PR #3929 body — "An agent spec's `instructions:` was accepted, stored and documented as
  delivered. Most harnesses never sent it to the agent. There was no error and no warning." and
  "The two launch channels carry the authored text, not the per-turn composed text."
  (https://github.com/omnigent-ai/omnigent/pull/3929, merged 2026-08-27, "[x] Bug fix", closes
  #3530 #3269 #2853). Docs: "`instructions` | Optional | Inline instructions or a path to an
  instructions file. If set, it takes precedence over `prompt`."
  (https://github.com/omnigent-ai/omnigent/blob/main/docs/AGENT_YAML_SPEC.md).
- Trajectory: #3558 (open) claude-sdk snapshot staleness; PR #5035 (open, community) overlaps the
  merged fix. No follow-up changes the two native channels.

**S10 — `--append-system-prompt` composability (ask 17).** A Claude Code CLI property, not an
omnigent one.
- Behaviour: `claude --help` on 2.1.260 — "--append-system-prompt <prompt> Append a system prompt
  to the default system prompt"; nothing on repeatability. Measured last-wins on 2.1.259
  (`omni:.bionic/docs/record/epic-20-w5/design-ledger.md` F3).
- Intent: code.claude.com/docs/en/cli-reference rows for `--append-system-prompt` and
  `--append-system-prompt-file` say "Append custom text to the end of the default system prompt"
  and "Load additional system prompt text from a file and append"; neither says repeatable.
- Trajectory: anthropics/claude-code #38286 and #45935 both report "only the last
  `--append-system-prompt-file` value is applied" and were closed `not_planned` by the stale bot
  (2026-04-22, 2026-05-22). #91518 (open, 2026-09-02) asks for the append to be its own system
  block for cache reasons. Nothing open asks for cumulative append. omnigent sidesteps it by
  `"\n\n".join` into one flag (`claude_native.py:4518` docstring: "applied on fresh launch and cold
  resume only … so it never relaunches or duplicates the flag"). Ask 17 is dead on both trackers;
  the only viable composition point is inside one flag, which is what both omnigent and the shim do.

**S11 — `executor.reasoning_effort` → `--effort`.**
- Behaviour: parsed at `spec/parser.py:671-672`, `:693`; typed at `spec/types.py:557-559`;
  appended as `("--effort", reasoning_effort)` at `runner/native/orchestration.py:5775` (docstring
  `:5767` shows `("--resume", "<sid>", "--effort", "high")`); the bridge reads it back at
  `claude_native_bridge.py:1853`. Also accepted per create on `sys_session_create` ("Only valid
  with 'agent_id', and only for harnesses with effort plumbing").
- Intent: AGENT_YAML_SPEC — "`executor.reasoning_effort` sets the agent's default reasoning
  effort. It applies to the main session and to every sub-agent dispatch that doesn't pass its own
  per-dispatch effort, and is validated against the harness's effort vocabulary at launch." PR
  #5753 (merged 2026-08-31, in 0.12.0) "makes `executor.reasoning_effort` the first-class spec
  default … honored on every harness".
- Trajectory: PR #3273, #4779, #5733 (open) widen per-dispatch and max/ultra handling; #2800
  (open) "Top-level custom codex-native agents drop reasoning effort and yolo".

**S12 — `executor.config.permission_mode` → `--permission-mode`.**
- Behaviour: the sub-agent launch-arg channel carries autonomy only — `--permission-mode` for
  claude-native, `yolo` for codex/cursor/kimi, `bypassPermissions` for antigravity `server/routes/_sessions/helpers.py:8508-8545` (`_derive_terminal_launch_args_from_spec`)
  *(unchanged from ask row 2)*. No env, no `--settings`, no tool denial; `hooks` does not appear
  in `spec/*.py` at all `grep -c hooks spec/parser.py spec/types.py` → 0, 0; `os_env`/`TerminalEnvSpec` native YAML support is still
  deferred `spec/types.py:1504`.
- Trajectory: #5582 (0.12.0) permission-mode changes survive relaunch; #4585 (0.12.0) native
  workers no longer hang on the bypass-permissions dialog on self-hosted runners; PR #4029 (open)
  admin gates for bypass/modes/models; discussion #5931 proposes derived per-sub-agent permission
  subsets, no maintainer reply.

**S13 — `claude_launcher.py`: the launch-wrap plugin.**
- Behaviour: `resolve_claude_launch(command, args)` is applied on both launch paths after
  `augment_claude_args` `runner/native/orchestration.py:6859`; `claude_native.py:844`, `:1121`, `:5685`; `runner/background_titles/claude_native.py:64`; a plugin is a setuptools entry point in group
  `omnigent.claude_launcher`, selected by `OMNIGENT_CLAUDE_LAUNCHER`
  (`claude_launcher.py:58-61`); the variable is in `_RUNNER_ENV_ALLOWLIST` at
  `host/connect.py:535` with the comment "The daemon→runner env strip would otherwise drop it".
  Failure falls back to the default launch `claude_launcher.py:96-97`, `:115-116`. No codex twin: `codex_launcher`,
  `OMNIGENT_CODEX_LAUNCHER` → no matches tree-wide grep for `codex_launcher`, `OMNIGENT_CODEX_LAUNCHER`, `resolve_codex_launch` returns nothing. The `harness.<id>.command`/`args` config
  override (`harness_startup_config.py`) is wired to the CLI path only in 0.12.0
  (`cli_native.py:264-275`, `:402-421`, `:607`); no runner-path caller.
- Intent: module docstring — "Downstream integrations need to launch that *same* Claude Code
  process through a wrapper binary so the wrapper's process-level setup -- auth, telemetry, cost
  controls, enforcement hooks, plugin management -- is always applied … The selected launcher
  receives the fully-augmented argv (MCP config, hook settings and skill flags injected by
  :func:`augment_claude_args`), so a launcher that merely wraps the command preserves the Omnigent
  bridge unchanged." PR #1476 (merged 2026-06-27): "so the native Claude harness can be launched
  through a wrapper binary (e.g. Databricks' `isaac`) that applies its own process-level tooling,
  without forking the framework" (https://github.com/omnigent-ai/omnigent/pull/1476); PR #1525
  moved discovery to entry points.
- Trajectory: PR #5765 (merged 2026-09-01, post-0.12.0 on the runner path) "Honor harness.<id>
  command/args config in the runner native-terminal auto-create" — "A downstream integration can
  route the native launch through a wrapper via **config alone**, no plugin:
  `harness.claude-native: {command: isaac, args: ["--"]}` … `harness.codex-native: {command:
  isaac, args: ["codex", "--"]}`" (https://github.com/omnigent-ai/omnigent/pull/5765). #6175
  runs desktop-internal hosts through `isaac omni`. Direction: wrapping the seat binary is a
  first-class, documented pattern (https://omnigent.ai/docs/build/harnesses/configuration), and
  the config form reaches codex where the plugin does not.

**S14 — the `--settings` bridge file and `--disallowedTools`.**
- Behaviour: omnigent writes the seat's settings file with the hook keys of S4 and a permissions
  block `claude_native_bridge.py:1388` `build_hook_settings`; nothing lets a caller add to it. `_merge_disallowed_tools` merges
  `_OMNIGENT_DISALLOWED_TOOLS` (an empty tuple) into an existing user `--disallowedTools` flag
  "so a user-supplied ``--disallowedTools`` is not silently overridden"
  (`claude_native_bridge.py:1775`, `:1857`, `:1947-1964`). A launcher plugin can therefore add
  `--disallowedTools` on argv and omnigent will preserve it.
- Intent/trajectory: no spec-level tool denial; issue searches for `disallowedTools`,
  `permissions.deny` returned nothing.

**S15 — seat environment and workspace trust.**
- Behaviour: seat env is the runner's own lineage plus a three-key overlay `claude_native.py:1236`, keys at `:211-227`; `runner/native/orchestration.py:1462`, `:2230`, `:2494` *(F1
  unchanged)*; `CLAUDE_CONFIG_DIR` is absent from `_RUNNER_ENV_ALLOWLIST`, so it survives the
  local CLI path and is stripped at the daemon→runner boundary `host/connect.py:418-607` — `CLAUDE_CONFIG_DIR` occurs zero times. Trust seeding still
  hardcodes `Path.home() / ".claude.json"` (`claude_native_bridge.py:1113`) `claude_native_bridge.py:1113`.
- Trajectory: #503 (open, help wanted) "Switch Claude Code account per session via isolated
  profiles" and PR #583 (open) "per-session Claude Code account via isolated profiles
  (CLAUDE_CONFIG_DIR)" are the only CLAUDE_CONFIG_DIR items; #5866 (post-0.12.0) GCs orphaned
  bridge dirs.

**S16 — codex-native: hooks merge, trust, `developer_instructions`.**
- Behaviour: the seat's private `hooks.json` is one payload merged from omnigent's policy hooks
  and the user's `~/.codex/hooks.json` `inner/codex_executor.py:1154` `merge_codex_user_hooks`, `:1202` `write_codex_hooks_file`; `_trust_policy_hooks` trusts omnigent's own
  three; `--dangerously-bypass-hook-trust` goes to the TUI launch only `codex_native_app_server.py:1351`, `:3106`, `:3234`
  *(unchanged from probe P1)*. `_sync_codex_developer_instructions` keeps the operator's value in
  a sidecar and writes `base + "\n\n" + addition` `codex_native_app_server.py:332`, `:353`. No codex tool-denial enforcement:
  `tools_denied` appears nowhere in the tree tree-wide `grep -rc tools_denied` — no file with a non-zero count; the only codex controls are
  pre-approval lists and `approval_policy="never"` / `sandbox_mode="danger-full-access"`.
- Trajectory: PR #6227 (merged 2026-09-02, post-0.12.0) "fix(codex-native): trust merged hooks so
  resumed sessions skip the review screen" — closes the trust-gate ask (P1) by trusting merged
  user hooks; #5976/#8488dfc7/#6228 rework codex approval modes.

**S17 — harness readiness at seat launch.**
- Behaviour: `harness_is_configured` is presence-plus-version `onboarding/harness_readiness.py:501-514` ("an installed-but-not-logged-in CLI still returns ``True``"); `host/connect.py:188`; codex `login_required` at `runner/native/orchestration.py:4312`, `:4421`; `chatgpt_plan_type`
  → no matches tree-wide grep for `chatgpt_plan_type` returns nothing.
- Trajectory (in 0.12.0): PR #5877 "`resolve_native_codex_launch` now marks every credential-less
  login-fallback launch `login_required` at resolution time"; PR #5872 "`omnigent config list`
  shows whether codex is signed in with a ChatGPT plan or an API key"; #5468 enterprise-gateway
  detection. No plan-tier gate anywhere.

### Server and lifecycle seams

**S18 — `omni server --background` flags.** `cli.py:3944-3949` calls
`_run_background_server()` with no arguments before `--config`/`--host`/`--port` are read `cli.py:3944-3949` — `_run_background_server()` is called with no arguments. Upstream `host/local_server.py` spawns the server with the *global*
config path only. No issue filed. *(P5 unchanged.)*

**S19 — `omni run` session id.** No flag, no file, no echo `cli.py:7882` `def run(`; no echo or write of a conversation id in `cli.py` or `cli_native.py`. Nothing upstream.

**S20 — host daemon lifecycle.** `wait_for_host_online` polls the DB-backed hosts route;
`HOST_LIVENESS_TTL_S = 90` `stores/host_store.py:47`; `host/daemon_launch.py:121`; runner-launch retry fires on 409 `offline` only
`host/daemon_launch.py:298` (`transient = resp.status_code == 409 and "offline" in …`). In 0.12.0: #5213 "Stale host daemons now retire themselves when their registry
record is removed or claimed by a newer daemon, and a second host spin-up reuses the running
daemon instead of duplicating it"; #5631 (merged 2026-09-01) flock election per target. Open: PR
#5089 re-addresses a `wrong_replica` launch. `_ensure_host_daemon` is still lazy from `omni run`
`cli.py:3205`, called at `:3482`, `:7290`, `:8322`.

**S21 — orphan terminal reaper.** `reap_orphaned_terminals` still has one caller, at runner start
`runner/_entry.py:1327`, the sole caller. PR #6241 (open, 2026-09-03): "The runner's startup orphan sweep … can kill **live**
terminal tmux servers, taking a running agent's in-flight turn with it." The launcher's block 5
uses the same dead-owner-pid criterion.

**S22 — `switch-agent`.** Idle-only, top-level-only, built-in-only `server/routes/sessions/routes_core.py:2525-2593` ("Only built-in agents are bindable, and only while the session is idle") *(F7 unchanged)*.
#5666 (open) "The switch endpoint accepts only idle sessions"; #5944 (open) switching pins the
bundle version. Pivot stays relaunch + cold resume.

**S23 — sessions LIST vs DETAIL.** `SessionListItem` carries no `harness`/`llm_model`;
`SessionResponse` does *(row 12 unchanged)*. #6141 (post-0.12.0) persists the reported model;
#6324 resets the pick on fallback. Row 14's served-model drift is being addressed for SDK
harnesses first.

**S24 — `omni config set auto_open_conversation=false`.** Writes `$ROOT/.omnigent/config.yaml`
(`omni:bindings/claude/RESIDUE.md` row 19, citing `cli.py:1204`, `:7832`). A seam; unchanged.

**S25 — watchdogs.** 0.12.0 raised the per-turn absolute watchdog from 1 h to 3 h (#5713);
post-0.12.0 #6204 raises the idle watchdog to 1 h. Both are process-wide; there is still no
per-sub-agent deadline (S6).

**S26 — the Claude Code Stop hook (vendor seam).** Not an omnigent seam: the one turn-end event
any seat exposes. omnigent registers `Stop` itself for the forwarder (S4) and the shim appends
bionic's entry beside it; the hook array merges (M-7b obs. A).

## 2. bionic-omni pieces: seam or route-around

Legend — **SEAM**: stands on a seam above. **ROUTE**: works around a missing seam. **OWN**:
bionic's own surface, no seam needed. **OBSOLETE (installed)**: the seam exists in 0.12.0 as
installed. **OBSOLETE (merged)**: on upstream main, not yet released.

| Piece | Stands on | Verdict | What upstream change obsoletes it | Citation |
|---|---|---|---|---|
| `bundle/config.yaml` spec/executor/`spawn`/`timers`/`tools.agents` | S6 | SEAM | — | `omni:bundle/config.yaml:7-24` |
| `bundle/config.yaml` `guardrails.policies` (11 handlers) | S1 | SEAM | — | `omni:bundle/config.yaml:71-90`; parser `spec/parser.py:246` (`guardrails = _parse_guardrails(raw.get("guardrails"), …)`) |
| `bundle/config.yaml` `params.roster` (primary/fallback/active per role) | S8 | ROUTE | per-role `executor.config.harness` + `model` + `executor.reasoning_effort` already express the *active* seat (S11, S12); the fallback pair has no seam — S22 is built-in-only | `omni:bundle/config.yaml:34-42` |
| `bundle/config.yaml` `params.pulse` | S8 | ROUTE | an off-seat timer arm (S7) — nothing upstream | `omni:bundle/config.yaml:47-49` |
| `bundle/config.yaml` `params.walk` | S8 | OWN | a walk is bionic's measurement stance, not a harness capability | `omni:bundle/config.yaml:50-70` |
| `bundle/server.yaml` `policy_modules` | S2 | SEAM | — | `omni:bundle/server.yaml:16` |
| `bundle/bionic_omni/__init__.py` `__path__` shim + PYTHONPATH requirement | S2 | ROUTE | bundle-local policy modules — nothing upstream | `omni:bundle/bionic_omni/__init__.py:19` |
| `bundle/rules.yaml` + `policies/_registry.py` | — | OWN | — | `omni:bundle/rules.yaml:1-30` |
| `commit_evidence`, `artifact_layout`, `protect_main`, `protect_database`, `walk_hide` (TOOL_CALL on shell/write tools) | S1, S3, S4 | SEAM | — | `omni:bundle/policies/_event.py:132` |
| `dispatch_deliverable`, `resume_before_dispatch` (TOOL_CALL on `sys_session_send`) | S1, S3, S6 | SEAM | — | `omni:bundle/rules.yaml` rows |
| `dispatch_convert` (TOOL_CALL on native `Agent`/`Task`) | S4 (PreToolUse catch-all posts the native tool) | SEAM | — | `omni:bundle/policies/dispatch_convert.py:13-16,85,143` |
| `duties_on_tick`, `deadline` (REQUEST on the tick) | S3 | SEAM for the wall; ROUTE for the data | the deadline itself is bionic `session_state` because S6 has no per-sub-agent deadline; obsoleted by a per-dispatch deadline — nothing upstream | `omni:bundle/policies/_event.py:179`; `omni:bundle/policies/deadline.py` |
| `writer_delivered_backstop` (PHASE_TOOL_RESULT) | S5 | SEAM (backstop by design) | — | `omni:bundle/policies/writer_delivered_backstop.py:72` |
| `bundle/agents/*/config.yaml` `executor.config.harness/model/permission_mode` | S12 | SEAM | — | `omni:bundle/agents/researcher/config.yaml:8-13` |
| `bundle/agents/*/config.yaml` `instructions:` | S9 | SEAM — live since 0.12.0 | — | `omni:bundle/agents/researcher/config.yaml:31` |
| `bundle/agents/*/config.yaml` `params.seat.effort` | S8 | ROUTE — **OBSOLETE (installed)** | `executor.reasoning_effort` (S11) | `omni:bundle/agents/researcher/config.yaml:15-18` |
| `bundle/agents/*/config.yaml` `params.tools_denied` | S8 | ROUTE | a spec-level tool denial — nothing upstream; a launcher plugin (S13) can carry it as `--disallowedTools` (S14) instead of a settings edit | `omni:bundle/agents/researcher/config.yaml:27-32` |
| `bundle/agents/*/seat-prompt.md`, `orchestrator-seat-prompt.md` | — | ROUTE — **OBSOLETE (installed)** | S9; the orchestrator's text needs an `instructions:` field on the top-level bundle | `omni:bindings/claude/RESIDUE.md` row 20 |
| `bundle/scripts/reap-closed.sh` | S6 (close is a tombstone) | ROUTE | `reap_codex_native_processes_for_state_dir` called at close — nothing upstream; #5866 GCs bridge dirs only | `omni:bundle/scripts/reap-closed.sh:6-21` |
| `bundle/MEASURED` | — | OWN | — | — |
| shim: PATH interposition itself (`$HOME/.local/bin/claude`, sidecar `.bionic-omni-shim.env`) | — | ROUTE — **OBSOLETE (installed)** as a mechanism | S13: an entry-point launcher receives the augmented argv in-process, selected by an allow-listed env var; no PATH edit, no sidecar, no real-binary resolution. Post-0.12.0, `harness.claude-native.command` config does the same by config (#5765) but without argv access | `claude_launcher.py:1-45`; `host/connect.py:535` |
| shim rule: auth (`CLAUDE_CONFIG_DIR` re-export) | S15 | ROUTE | trust seeder honouring `CLAUDE_CONFIG_DIR` **and** the runner allow-list passing it (#503/#583 open) | `omni:bindings/claude/shim/claude:141-144` |
| shim rule: tool denial (`permissions.deny` ← `tools_denied`) | S14 | ROUTE | spec-level tool denial — nothing upstream | `omni:bindings/claude/shim/claude:609` |
| shim rule: Stop hook append (`landing.sh`) | S26 | ROUTE | a turn-end policy phase (S3) or bundle-declared hooks (S12) — neither exists or is proposed | `omni:bindings/claude/shim/claude:798-799` |
| shim rule: `--effort` append | S11 | ROUTE — **OBSOLETE (installed)** | `executor.reasoning_effort` | `omni:bindings/claude/shim/claude:845` |
| shim rule: `BIONIC_OMNI_BRIDGE_DIR` export | — | ROUTE | a seat told its own conversation id, or a Stop payload carrying it — nothing upstream | `omni:bindings/claude/shim/claude:841` |
| shim rule: identity compose (`--append-system-prompt-file`, the compose-and-drop rule) | S9, S10 | ROUTE — **OBSOLETE (installed), now harmful** (double role text) | S9 | `omni:bindings/claude/shim/claude:651-721,848` |
| shim rule: walls from `SKILL.md` `hooks:` into the seat's settings | S14 | ROUTE | bundle-declared hooks — nothing upstream | `omni:bindings/claude/shim/claude:727-764,806` |
| shim rule: walk deny (`Read(.bionic/**)`) | S14 | OWN/ROUTE | — | `omni:bindings/claude/shim/claude:444-473` |
| `bindings/claude/hooks/landing.sh`, `plugin.json`, `hooks.json` | S26 | SEAM (vendor) | a policy-visible turn end — nothing upstream | `omni:bindings/claude/hooks/landing.sh:1-8` |
| `bindings/codex/hooks.json` + `scripts/landing.sh` (machine-global `~/.codex/hooks.json`) | S16 (user-hooks merge) | ROUTE | bundle-declared hooks — nothing upstream. The *trust* dependency on `--dangerously-bypass-hook-trust` is **OBSOLETE (merged)** by #6227 | `omni:bindings/codex/scripts/landing.sh:4-17` |
| `bindings/codex/scripts/seat-prompt.sh` (SessionStart role text) | S16 | ROUTE — **OBSOLETE (installed), now harmful** | S9 `developer_instructions` | `omni:bindings/codex/scripts/seat-prompt.sh:1-20` |
| `bindings/claude/lib/{roster,preflight,roster_print,status,usage}.sh` | — | OWN | `roster.sh` changes shape if the roster moves to executor fields | `omni:bindings/claude/RESIDUE.md` "What left the count" |
| `launch.sh` block 2 (paths, log) | — | OWN | — | RESIDUE row 2 |
| `launch.sh` block 4 (duplicate `omni run` / pulser reap) | S20 | ROUTE | `omni run` refusing or adopting a second run — nothing upstream; daemon-level election only (#5213, #5631) | RESIDUE row 4 |
| `launch.sh` block 5 (orphan terminal sweep) | S21 | ROUTE | reaper at `omni server` start — nothing upstream; #6241 warns the shared criterion can kill live seats | RESIDUE row 5 |
| `launch.sh` block 6 (resolve real `claude`) | — | ROUTE — falls with the shim | S13 | RESIDUE row 6 |
| `launch.sh` block 7 (preflight: binaries, codex plan claim, logins) | S17 | ROUTE, partly **OBSOLETE (installed)** | codex `login_required` at resolution (#5877) and `omnigent config list` plan display (#5872) cover the login half; the plan-tier half has nothing upstream | RESIDUE row 7 |
| `launch.sh` block 8 (install shim + sidecar) | — | ROUTE — **OBSOLETE (installed)** | S13 | RESIDUE row 8 |
| `launch.sh` block 9 (render/install/restore codex hooks) | S16 | ROUTE; 9(b) **OBSOLETE (installed)** | (a) bundle-declared hooks — nothing; (b) S9 | RESIDUE row 9 |
| `launch.sh` block 10 (`start_server`, detached, pid, health poll) | S18 | ROUTE | background server honouring `--config`/`--port` — nothing upstream | RESIDUE row 10; `cli.py:3944-3949` |
| `launch.sh` block 11 (`wait_for_host`, `lib/host.sh` `ensure_host_daemon`) | S20 | ROUTE, partly **OBSOLETE (installed)** | #5213 makes daemon reuse omnigent's own; the 90 s TTL and `wrong_replica` retry stay open (PR #5089) | RESIDUE row 11 |
| `launch.sh` block 13 (trust seed/restore) | S15 | ROUTE | seeder honouring `CLAUDE_CONFIG_DIR` — #503/#583 open | RESIDUE row 13 |
| `launch.sh` block 15 (`resolve_session` newest-row inference) | S19, S23 | ROUTE | `omni run` reporting its id — nothing upstream | RESIDUE row 15 |
| `launch.sh` block 16 (the pulser) | S7 | ROUTE | an off-seat timer arm — nothing upstream | RESIDUE row 16 |
| `launch.sh` block 17 (`stop_all`) | — | derived | empties with its siblings | RESIDUE row 17 |
| `launch.sh` blocks 18/19 (usage, main, `omni config set`, `omni run` handover) | S24 | OWN | — | RESIDUE rows 18–19 |
| `launch.sh` block 20 (`write_seat_prompts`) | — | ROUTE — **OBSOLETE (installed)** | S9 | RESIDUE row 20 |

Tally: SEAM 17 · ROUTE 20 · OWN/derived 4 (counting each shim rule and launcher block as a
piece). OBSOLETE (installed): `params.seat.effort`, the seat-prompt files, the shim mechanism,
the shim's effort rule, the shim's identity compose, `seat-prompt.sh`, blocks 8 and 20, and half
of 7, 9 and 11. OBSOLETE (merged, awaiting release): codex hook trust (#6227), per-role guardrails
(#6043), `sys_session_send` description and steering (#6359 still open).

## 3. What the adapter assumed that 0.12.0 refutes or sharpens

- **Appendix B F1 "no `CLAUDE_CONFIG_DIR` set → bionic's plugin loads"** still holds on the
  local path, but the managed-host allow-list strips the variable; the shim's re-export is
  load-bearing on both paths for different reasons.
- **ADR-013's "native terminal owns its prompt" premise** was refuted before it was written
  (record `research-omnigent-identity-channel.md`); S9 is the primary surface now.
- **"No per-seat launch hook" (shim header)** was false at 0.11.0 already: `claude_launcher.py`
  landed 2026-06-27. The shim was built on the PATH because the seam was not looked for. Its
  runner-side allow-listing is what makes it usable from a managed host.
- **"omnigent notices no second `omni run`"** stands for `run`; 0.12.0 fixed the daemon layer.
- **The parked test-runner** is not a settings bug; it is the `PermissionRequest` hook (S4).
  W6 slice 2 should aim at that hook, or at `bypassPermissions` for worker seats, not at the
  shim's settings write.

## 4. Version-policy implications (fog "pin 0.12.0 or track")

- **Weekly minor releases, 211 commits in three days, no roadmap, no Unreleased section.** A
  tracking policy re-certifies every week; the changelog is generated from PR sections and is
  the only forward-looking artifact. Pinning is the only way a support table stays true for a
  wave.
- **What a bump re-certifies, by seam.** S9/S11 (identity, effort): re-read the seat argv and
  config.toml, never the seat's record. S4/S14 (hook keys, settings): re-diff omnigent's
  settings file against the shim's expectations — a new hook key or a renamed forwarder entry
  changes the merge. S3/S5 (phases, inbox drain): re-run the policies suite and the drill's
  backstop cells. S20/S21 (daemon, reaper): re-run the cold-start smoke; #6241 shows the reaper
  is in motion. S16: the trust census. Everything else is a grep against the file:line table
  in §1, which is the cheapest re-certification there is and should be a test
  (`tests/policies/fixtures/sys-session-send-schema.json` already pins one installed shape).
- **The three obsolete-on-install items are a forcing function.** Running 0.12.0 with the
  0.11.0 adapter double-injects role text on every seat; a pin that lags the installed tool is
  not a pin. Recommendation to carry into G2/G3: pin the version the adapter was certified on
  as a tested fact (`omni --version` in preflight, refuse a mismatch), and bump deliberately as
  its own slice with the §1 table as the checklist.

## 5. For the map: fog and ticket candidates

1. **Launcher plugin vs PATH shim (G3 input).** Rebuilding the shim as an
   `omnigent.claude_launcher` entry point removes PATH interposition, the sidecar, the real-binary
   scan and blocks 6/8, and keeps every rule the shim still needs (tool denial via
   `--disallowedTools`, walls into `--settings`, bridge-dir export, auth). It needs a pip-installed
   package in omnigent's venv — a machine-mutating install step, so it is a `/bionic:setup` item.
   Codex has no equivalent; its binding stays on the hooks merge.
2. **Roster in executor fields.** With S11 and S12, the active seat per role is expressible as
   `executor.config.harness` + `model` + `reasoning_effort`, leaving `params.roster` to hold only
   the fallback pair and the switch. Whether to keep one table or split is a G3 design call.
3. **Orchestrator `instructions:`.** The top-level bundle has no `instructions:` today; S9 shows
   it would be delivered. Rung-2 candidate: the orchestrator wakes constituted with no shim.
4. **The writer-delivered wall has no upstream future.** No turn-end phase, no proposal. Rung
   certification should treat the vendor Stop hook as the permanent seam and the backstop as the
   permanent backstop.
5. **Pulse has no upstream future** either; the clock stays outside the seat. The only design
   question is whether `sys_timer_set` (seat-armed) is acceptable — A-W2-42 said no.
6. **#6241 (reaper kills live terminals).** Block 5 shares the criterion. Watch it; if upstream
   changes the criterion, block 5 must follow or be deleted.
7. **Ask 17 is dead on both trackers.** Close it in the asks ledger; composition happens inside
   one flag by whoever writes the flag last, which after slice 1 is omnigent alone.
8. **Codex `tools_denied` has no enforcement point (A-W5-171)** — confirmed: the string does not
   occur in omnigent. It is declarative only; the ownership table should say so or the drill
   should stop counting it.
