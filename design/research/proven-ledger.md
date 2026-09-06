# Proven ledger — what epic-20 actually proved, by rung

Research ticket R1 (chrisalehman/bionic#20), resolved 2026-09-04 on branch `research/proven-ledger`.
Map: #19. Charting brief: `.bionic/docs/ideas/bionic-v1-wayfinder-kickoff.md` (machine-local).

## How to read this

**One row per claim, one status per row.** Where a requirement has several clauses that fared
differently, it is split so that no row carries a mixed verdict. Statuses:

| status | meaning |
|---|---|
| **proven** | a primary surface shows the claim: a machine-written drill cell, a test log with counts, a seat transcript or item store, a git object, a captured response. The surface is named and it still exists on disk as of 2026-09-04. |
| **refuted** | a primary surface contradicts the claim, or the claim's own instrument reports the opposite (a CONTROL that failed, a cell ALLOWED where a wall should have held). |
| **untested** | nothing but self-report exists (a report, record, plan row, auditor CONFIRMED that anchors into prose), or the instrument never reached the claim (UNTESTED cells, waived rows, "no live session"). |
| **in-flight** | a primary surface shows the defect and the W6 charter (`omni:.bionic/docs/ideas/wave-06-charter.md`) or a ratified ADR names the repair. The tree at `42f4cf8` does not yet carry it. |

**Sources.** Claims are read from surfaces, never from a document's statement that something
passed (standing rule A-W5-175/178). `omni:` = `/Users/admin/workspace/personal/bionic-omni`
@ `42f4cf8`; everything under `omni:.bionic/` is gitignored and machine-local. Drill evidence
directories under `/private/var/folders/…/T/bionic-omni-drill/<stamp>/` and seat transcripts
under `~/.claude/projects/…` and `~/.omnigent/codex-native/…` were confirmed present on
2026-09-04 but are not versioned anywhere.

**Version caveat that applies to every proven row.** Every live surface was taken on omnigent
**0.11.0**; omnigent **0.12.0** has been installed since 2026-09-03T21:55Z and nothing in the
tree has been run against it (`omni:.bionic/docs/ideas/session4-brief.md:11-14`). The tree names
0.11.0 in 27 tracked files (18 under `bundle/ bindings/ tests/ payload/`) and 0.12.0 in none. So "proven" below means *proven on
0.11.0*; the 0.12.0 status of each row is **untested** until the drill is re-run (TDD §9: "runs
on every omnigent upgrade").

**Three support tables, three dates.** The drill writes one table per run and overwrites
`support-table.md`; the tree holds three: the m2 mix at `48c99f7` (2026-09-01, `support-table.md`),
the orchestrator-only m1 run at `34a7107` (2026-09-02, `support-table.orchestrator.md`) and the
researcher-only m1 run at `c9588e0` (2026-09-01, `support-table.researcher.md`). Where a cell was
measured more than once the latest table is cited. The W1 table (green-11) survives only as a
verbatim copy in `omni:.bionic/docs/record/epic-20-w1/drill-green11.md:120-153`; W2's full m1
table is in `omni:.bionic/docs/record/epic-20-w2/drill-w2-4-6-3.log:135-193`.

**Rung mapping** follows the brief's ladder hypothesis (0–10). Rows that certify an instrument
rather than a capability are in the cross-cutting section at the end.

---

## Rung 0 — one home for the method (migration)

Nothing in epic-20 addressed this rung; it is the map's own decision (#19 ratified item 6). The
rows below are the facts the migration stands on, each read from a surface.

| requirement | source | status | primary surface | note |
|---|---|---|---|---|
| bionic and bionic-omni share root `1b12d1c`; last common commit `2e98368` (bionic 1.3.2); no merge/subtree since | brief §Facts | proven | both checkouts: `git rev-list --max-parents=0 HEAD` = `1b12d1c`; `git log -1 2e98368` resolves in both to "bionic 1.3.2" (re-derived 2026-09-04) | `git rev-list --count 2e98368..HEAD`: 274 omni-side (the brief's "~197" is likely first-parent), 127 bionic-side |
| the fork's payload was the *installed* bionic plugin for W5 (1.3.3 → 1.3.5), served from the `bionic@bionic` registry | ADR-012 (accepted 2026-09-02) | proven | `~/.claude/plugins/cache/bionic/bionic/{1.3.3,1.3.4,1.3.5}` dated Sep 2–3; `diff -rq` of the 1.3.5 cache against `omni:payload/` differs only by `.orphaned_at`; `omni:.bionic/docs/record/epic-20-w5/smoke-3-w5-ac4-ac5-evidence.log:18-20` (`…/cache/bionic/bionic/1.3.3 1.3.3`, `diff-rc=0`); W4 auditor re-exec (`record/epic-20-w4/step5-audit.md` addendum 3): `marketplace bionic: source.path = /Users/admin/workspace/personal/bionic-omni`, `installPath …/1.3.2, gitCommitSha 56aecb4…` | **Contradicts the brief's "bionic-omni's payload says 1.3.5 and was never installed."** The fork's payload was live for the W5 sessions and THE RUN. What is true: since 2026-09-03T20:16Z the registry points at `/Users/admin/workspace/personal/bionic` (`known_marketplaces.json:50-56`) and `bionic@bionic` is 1.4.1 (`installed_plugins.json:63-69`), so the fork's payload is now orphaned. |
| bionic-omni's launcher, shim, patrol and worktree scripts work against bionic 1.4.x's plugin root | session4-brief | untested | — | `omni:.bionic/docs/ideas/session4-brief.md:15-20` says "compatibility UNVERIFIED"; nothing has been run since. |
| the 1.4.1 per-session engagement marker is the right scoping for omnigent seats (every seat is a top-level session) | map fog | untested | — | F5 (role-blind hooks in seats, A-W5-151/169) is the measured harm 1.4.1 was built for; whether the marker cures it on a seat has not been run. |
| `.claude/rules/*.md` reach dispatched agents in this repo but not plugin users (tainted dogfooding) | map fog | proven (existence) | `.claude/rules/` committed via `.gitignore` negation (bionic `CLAUDE.md` §Path-scoped rules) | Whether any rule there changed a measurement is **untested**: no wave ran a control without them. |
| the domain glossary the map points at (`design/domain-dictionary.md`) exists in bionic | #19 Notes | refuted | bionic worktree `design/` holds only `orchestrator-subagent-coordination.md`; the dictionary exists in `omni:design/domain-dictionary.md` (cited at W5 for "seat constitution" :369, "walk switch" :466) | Migration item: the dictionary is omni-side. |

## Rung 1 — one-command launch

| requirement | source | status | primary surface | note |
|---|---|---|---|---|
| R1: the bundle is launched directly; the orchestrator is an omnigent agent, not a vendor TUI | PRD §3 R1 | proven | W4 AC-1 (see W4 rows below); THE RUN's orchestrator seat is omnigent conversation `c1df36a3` with 617 items (`omni:.bionic/docs/record/epic-20-w5/the-run/session-items.json`) | The orchestrator is a `claude-native` seat (TDD S3): the real `claude` TUI under omnigent, constituted by the shim (rung 2). |
| R3: omnigent running is a prerequisite; no no-omnigent mode | PRD §3 R3 | proven (by construction) | every launch path starts `omni server` (`omni:bindings/claude/launch.sh`); no code path runs the bundle without it | Never planted as a violation; nothing to refute. |
| one command from cold: server up, host tunnel, seats declared, roster printed from omnigent DETAIL, REPL attached, no browser | W4 AC-4 (T3) | proven (six of seven clauses) | `omni:.bionic/docs/record/epic-20-w4/evidence-smoke-w4-4b.log:38-39` (roster + orchestrator line from DETAIL), `:189` (DETAIL for the created session) | Seventh clause (web link) **refuted** by the same log: `:46` prints `c/caf7bd3b…` while the created session was `9005a5ab…` (`weblink-bisect.md:1`); withdrawn in place (A-W4-220) and repaired at W5 AC-9 (next row). |
| an expired or absent vendor login stops preflight and names the command; a valid one proceeds silently | W4 AC-5 (T2) | proven | `omni:.bionic/docs/record/epic-20-w4/evidence-audit-reexec-663f800.log:421-447` (27 S19 arms), `:639` `603/603 passed` | Hermetic arms over captured token shapes; no live expired login was planted. |
| relaunch reuses the running server and daemon; process census equal before and after | W4 AC-6 (T3) | proven | `omni:.bionic/docs/record/epic-20-w4/smoke-w4-3.md:115-116,123-124` ("server already up… reusing it", "CRITICAL: no second daemon", `18 processes / 18 processes`) | smoke-4b's wider `pgrep` census read 54; the clean equal-census reading is smoke-3's. |
| `stop` leaves zero launched processes | W4 AC-6 clause 3 | proven at W4, then contradicted by W5's driver (self-report) | W4 smoke-3 census above; W5 A-W5-109/114 (driver report, secondary) | Kept as two rows: the W4 proof stands on its surface; the W5 finding is in-flight below. |
| bundle skills appear as REPL slash commands | W4 AC-10 (T3) | proven (historical) | `evidence-smoke-w4-4b.log:281,356,362,364` (captured `/` menu: canonical-sdlc, browser-verify, map-instrument-narrow) | Superseded: `bundle/skills/` was removed at W5 (rung 2, one skill source); the menu now comes from the host plugin. |
| one home: the registered plugin source is this fork and `/bionic:doctor` says so | W4 AC-11 (T3), ADR-012 | proven (clauses 1–2) / untested (clause 3) | auditor re-exec table (`step5-audit.md` addendum 3 rows 3-4): `marketplace bionic: source.path = /Users/admin/workspace/personal/bionic-omni`, `installPath …/cache/bionic/bionic/1.3.2, gitCommitSha 56aecb4…`, cache `SKILL.md` identical to the fork's | `one-home-procedure.md:1-5` is labelled `unverified` by its own author. Clause 3 ("a freshly started orchestrator seat") was discharged on the cache file, not a seat (A-3.3). Since 2026-09-03 the registry points elsewhere (rung 0). |
| Chris, cold, one command, one real task; a Codex seat visibly works | W4 AC-12 (T4) | untested | `omni:.bionic/docs/record/epic-20-w4/walk-ac12-readme.patch:1-20` (a real diff, `1 file changed, 14 insertions`) is the only durable artifact; child DETAIL (`codex-native / gpt-5.6-terra`) is transcribed, not captured | The walk was contaminated (A-W4-196: the seat read the brief and plan before Chris typed); the README patch **never landed** (`grep Troubleshooting bundle/README.md` at `42f4cf8` → 0). |
| a web UI stands beside the REPL for the roster graph and seat-level interventions | R-W4-7, ADR-009 | untested | — | No criterion below T4 (W4 audit wave-finding 1); rests on a screenshot not in the record (A-W4-201). |
| cold start without the launcher is a documented procedure that has been dry-run | W3 AC-13 (T1), AC-7 | untested (partial dry-run) | `omni:.bionic/docs/record/epic-20-w3/evidence-4-7.log:22-36` (`Policy registry loaded: 31 entries` under `--config`; "steps 2/3/6 not executed") | Re-discharge after the audit's F1 fix rests on Chris's walk (prose, `wave-03…plan.md:392`). |
| the launch says only what it knows (no session-less `web:` link) | W5 AC-9 | proven | `omni:.bionic/docs/record/epic-20-w5/slice-4-7-evidence.log:498-499, 3266-3268, 3465` (`655/655 passed`) | Repairs W4 AC-4's contradicted web-link readback (`evidence-smoke-w4-4b.log:46` printed `c/caf7bd3b…` while the created session was `9005a5ab…`; withdrawn in place by `weblink-bisect.md`). |
| the launcher's served-model line reads truth back from omnigent DETAIL | W4 AC (served-model), TDD §13 W4-1 | proven, with a refuting caveat | `support-table.orchestrator.md:25` served by `claude-fable-5-1,claude-opus-4-8`; `omni:.bionic/docs/record/epic-20-w4/drill-3-cells/served-model.orchestrator.jsonl:80` (`model_refusal_fallback`, `scope: session`, 05:55:47Z) | DETAIL reports the **launch** model; a mid-session fallback to Opus 4.8 is invisible to it (A-W4-119, ADR-010). The cell scored ALLOWED because the roster id was present; the reader should name a fallback row (PROMOTE to W5, not done). |
| `launch.sh stop` returns the machine (no daemons, zygotes, or stopped seats left) | W6 charter §2; A-W5-109/114 | in-flight | `support-table.orchestrator.md:45` process-census CONTROL FINDING: 9 → 42 processes after the dispatches (`omnigent-processes=8→37 seat-terminals=1→5`), "the close→reap loop did not give the machine back" | The `stop` half itself is seat/driver self-report (A-W5-114); the census cell is the primary surface for the reap half. |
| `install-codex` honours `--data-dir` | W6 charter §2; A-W5-108 | in-flight | — | self-report only (driver report). |
| R18: nothing outside `omni run bundle/` holds authority; residue reduced to instrumentation only by W3 | epic.spec R18 | refuted | `omni:.bionic/docs/record/epic-20-w2/launcher-residue.md:46` "**R18 subtracted no code from `launch.sh`, and that is the finding**"; W3 dispositions `:57-68` = 0 RETIRE · 6 BLOCKED · 2 SLIVER · 1 PROCEDURE · 1 closed-by-charter; W4 `evidence-regression-a3003c6.log:82` `scoreboard: files=2 blocks=15 no-seam-code-lines=608 (launch.sh 570, lib/host.sh 38) total-lines=816`, `:95` `31/31`, cap dropped (ADR-011) | The requirement as worded was not met; ADR-011 (accepted 2026-09-02) reframed the launcher as a seam scoreboard. Note for R3/G3: the tracked ledger `omni:bindings/claude/RESIDUE.md:81` has columns `Block · Functions · omnigent gap · Ask · Retirement · File` with *Retirement* as free prose — the four-state vocabulary (RETIRE/PROCEDURE/SLIVER/BLOCKED) exists only in untracked `.bionic/` records. Whether any row retired under 0.12.0 is untested. |
| R16: nothing machine-specific hardcoded; a second install on another Mac works without editing agent files | PRD §3 R16 | untested | — | Never attempted on a second machine. The shim contract sidecar lives at `$HOME/.local/bin/.bionic-omni-shim.env` and omnigent hardcodes `~/.claude.json` (TDD §12 W3-11) — neither is a proof either way. The 1.4.0 wave charter names a second 128 GB machine. |
| R17: secrets stay with the vendor CLIs; the bundle stores none | PRD §3 R17 | untested | — | No probe ever grepped the bundle for credentials; by construction only. |
| Chris can walk the cold-start procedure from his own terminal | W3 AC-12 (T4), AC-13 | untested | `omni:.bionic/docs/plans/…/wave-03-cold-openai.plan.md:355-369` user-confirmed prose only | T4's own rule is user-confirmed alone. The same block records the machine fact for that walk: "2 Agent calls, 0 sys_session_send, 0 codex rollouts" — the walk delegated natively (see rung 3). |

## Rung 2 — a seat wakes with its identity and its walls (constitution)

| requirement | source | status | primary surface | note |
|---|---|---|---|---|
| R4: every role maps to a seat by config; roles are tiers of job | PRD §3 R4; TDD T2 | proven | `omni:bundle/config.yaml` `params.roster` (7 roles × primary/fallback `{harness, model, effort}`); `render-bundle.test.sh` 87/87 (`omni:.bionic/docs/record/epic-20-w5/merge-check-6d22852.log:102`) | Hermetic + the served-model CONTROL cells (rung 1). |
| R6 layer 1: standing default in the bundle config | PRD §3 R6 | proven | `omni:bundle/config.yaml` | |
| R6 layer 2: Step 0 stamps the resolved `seat_plan` into the plan (T4) | PRD §3 R6; TDD T4 | untested | — | No wave plan's Step-0 line was checked for a `seat_plan:` block by a machine; THE RUN's seat plan carries a model line but no drill or test reads it. |
| R6 layer 3: a wave may override the mix | PRD §3 R6 | untested | — | Never exercised. |
| a claude-native seat is constituted at launch: role text on `--append-system-prompt-file`, walls from `SKILL.md hooks:` into the seat's settings, omnigent's hook keys intact | W5 AC-3 (T2), ADR-013 | proven (on 0.11.0, via bionic's shim) | `omni:.bionic/docs/record/epic-20-w5/slice-4-1-evidence.log:364` `43/82` RED → `:1450` `82/82`; `merge-check-6d22852.log:286` `122/122`; revert-and-watch `auditor-revert-watch.log:374` `72/122 passed, 50 failed` | This is the **compensating write** ADR-013 describes, correct for 0.11.0. See the next two rows for what 0.12.0 does to it. |
| identity arrives live: orchestrator announces on turn 1; Claude worker references its role; Codex worker's rollout carries its own role text; the Codex hook selects the right seat | W5 AC-4 (T3) | proven (three of four conjuncts) | `smoke-3-w5-ac4-ac5-evidence.log:85` (announcement), `:101` (researcher self-reference), `:130,:138` (shim decisions tsv per seat) | Fourth conjunct (Codex rollout carries *its own* text, not another's) is on the primary surface as three **unlabelled** counts (`:145-147` = `1`,`0`,`0`); which grep produced which is readable only from plan prose (`wave-05…plan.md:180`). Weak anchor, not a refutation. |
| the seat wakes via omnigent's own `instructions:` channel, no injection | ladder rung 2 wording; #19 item 6 | untested | omnigent 0.12.0 source (`claude_native_bridge.py:1870` per session4-brief); PR #3929 merged 2026-08-27 (`omni:.bionic/docs/record/epic-20-w5/research-omnigent-identity-channel.md`) | The channel exists in the installed 0.12.0 but **no seat has been launched on 0.12.0**. On 0.11.0 the channel was refuted at source (`inner/claude_native_executor.py:140` `del tools, system_prompt`; TDD §14 W5-1). |
| on 0.12.0 the role text lands twice (omnigent's copy + the shim's compose) | brief §known-broken; W6 slice 1 | in-flight (predicted, not observed) | source reading only: research-omnigent-identity-channel.md §"What bionic got wrong" item 4 | Not yet measured live. W6 slice 1 = delete the shim's compose path and the Codex SessionStart role text; proof named there (role text ONCE in a launched seat's argv). |
| a codex-native worker is constituted via the binding's SessionStart hook (LIVE marker) | W5 4/3b, 4/3b-2, 4/3c; A-W5-A/B TRUE | proven (on 0.11.0) | `omni:.bionic/docs/record/epic-20-w5/slice-4-3b-report.md`, `slice-4-3b-2-report.md` (live half); smoke-3 `:106` `PONG` | Same retirement as the shim's compose on 0.12.0 (`developer_instructions` now fed by omnigent). |
| the walls arm from `SKILL.md` only (no second hook list) | TDD §14 W5-3 | proven | `seat-constitution.test.sh` ±1 arms, 122/122 (`merge-check-6d22852.log:286`) | Not duplicated by 0.12.0 (identity research §"What bionic got right" 6): survives the upgrade. |
| one skill source: `bundle/skills/` gone; `/` menu lists `canonical-sdlc` once from the host plugin | W5 AC-5 (T1), ADR-014 (proposed) | proven | `git ls-tree -r HEAD bundle/skills` empty; `slice-4-4-evidence.log:40` RED → `:141` `42/42`; live `smoke-3…log:87-89` | ADR-014 awaits Chris. |
| R12: auditor/critic/researcher/test-runner have no write tools — claude-native researcher | PRD R12; rule `tool-denied` | proven | `support-table.researcher.md:18` REFUSED: Claude's permission system removed `["Write","Edit","NotebookEdit"]`, "No such tool available"; M-7b `measure-7b.md:111` `verdict: holds` | |
| R12 — claude-native auditor | rule `tool-denied` | proven (W2 table only) | `omni:.bionic/docs/record/epic-20-w2/drill-w2-4-6-3.log:178` REFUSED | Not re-measured since 2026-08-31. |
| R12 — claude-native critic | rule `tool-denied` | untested | `drill-w2-4-6-3.log:182` UNTESTED ("never attempted") | |
| R12 — claude-native test-runner | rule `tool-denied` | proven (W2 table) | `drill-w2-4-6-3.log:173` REFUSED | AC-11 later added `Agent`/`Task` to the deny list (rung 3). |
| R12 — every codex-native assurance seat | rule `tool-denied`, A-W5-171 | refuted (no enforcement point) | `support-table.md:55,59` UNTESTED (cell measures claude-native only); TDD §4 `tool-denied` row: "`params.tools_denied` has no reader in 0.11.0" | Declarative only on Codex. W6 containment item; in-flight. |
| effort-pinned: a claude-native seat runs with the roster's `--effort` | rule `effort-pinned` (binding) | proven | `support-table.orchestrator.md:26` (122 sampled argv lines), `support-table.md:33,40`, `support-table.researcher.md:17` | |
| effort-pinned on codex-native | rule `effort-pinned` | untested | `support-table.md:25,45,50,55,59` UNTESTED | M1 used a shared `config.toml` value; per-seat effort was a W3 item never measured. |
| autonomy: rendered `permission_mode: auto` reaches a live claude-native seat; no park | W3 AC-8, ADR-008 | untested (cl.1 ground corrected; cl.2 unpaired) | `omni:.bionic/docs/record/epic-20-w3/step5-audit.md:227-243` (`terminal_launch_args` populated for 3 codex children, NULL for 11 claude rows) | Hermetic pin only (`render-bundle.test.sh` Group F). |
| a claude-native test-runner seat runs a suite unattended | W6 slice 2; seat F3 | in-flight | THE RUN item store: every suite this run came from Codex seats (scorecard prose); the F3 park itself is the seat's own record (secondary) | Contradicts the `permission_mode: auto` render above in practice; W6 slice 2 names the drill cell that would prove the fix. |
| bionic's plugin hooks load inside every seat, role-blind (F5) | A-W5-151/169; W6 charter §4 | in-flight | TDD App. B F1 (seat inherits real `HOME`; probe 6/6 hooks); farm-out checkpoint refusing a seat's suite commands (driver report, self-report) | Bionic 1.4.1's engagement marker is the candidate cure; untested on a seat (rung 0). |
| codex-native seat receives a project-level instruction file (`AGENTS.md`) | TDD §9 measure-first #6 | proven with caveat | `omni:.bionic/docs/record/epic-20-w1/measure-6.md:133` `verdict: holds with caveat: channel is <repo-root>/AGENTS.md (read live in 2 of 3 runs)…` | `.codex/instructions.md` is never read; `$CODEX_HOME/AGENTS.md` merges as a per-seat channel. |
| walk-hide: two walls, one switch, negative control | W5 AC-7 (T2), ADR-015 (proposed) | proven (hermetic) | `slice-4-5-evidence.log:118-119` (D8 negative control), `:345` `463 passed`, `:455` `93/93` | Never armed live outside the W5 walk; ships FALSE. |

## Rung 3 — dispatch through omnigent's roster; no native sub-agent spawns

| requirement | source | status | primary surface | note |
|---|---|---|---|---|
| T3: every dispatch goes through `sys_session_send`; vendor spawn tools denied in the orchestrator seat | TDD T3 | proven (Claude orchestrator, THE RUN) | `the-run/session-items.json`: 23 × `mcp__omnigent__sys_session_send`, 0 × `Agent`/`Task`, 0 × `sys_session_create` (re-derived 2026-09-04); scorecard log `effectiveness-scorecard-w5.log:3` | Task-scale run, 67 min. |
| the same model launched bare attempts native spawns | W5 AC-2 control | proven | `effectiveness-scorecard-w5.log:8,13` (`native Agent/Task attempts=2`, `=1`; `raw session_create=1` each); item stores under `omni:.bionic/docs/record/epic-20-w5/ac6-native-path*/native-path.items.json` | The difference against the control is the certifying measurement (A-W5-178). |
| `dispatch-convert` wall fires on a native `Agent`/`Task` call in the orchestrator seat | TDD §4 `dispatch-convert` | proven | `support-table.orchestrator.md:24` REFUSED (step 7, seat transcript) | |
| A-1: the model *acts* on the deny text and emits a schema-valid `sys_session_send` | W4 §5 A-1; W5 AC-6 | proven (after a refuting first run) | `omni:.bionic/docs/record/epic-20-w5/ac6-native-path/native-path.verdict:1` `UNTESTED-PARTIAL … NEXT call was 'Agent'` (A-1 FALSE) → fix `dfdca97` → `ac6-native-path-2/native-path.verdict:1` `REFUSED — A-1 measured TRUE … row 36 is sys_session_send and validates against the live send schema` | The RED is kept as the fix's own proof. |
| the re-route names the parameters `sys_session_send` declares (`agent`/`title`/`args`) | TDD §13 W4-2 | proven | `evidence-6-send-schema.log:8-9` RED vs `:84-85` GREEN (W4 record); `tests/policies/test_dispatch_convert.py` resolves against omnigent's live schema builder | First shipped spelling (`name`/`message`) was **refuted** by F-CORRECTNESS-1; the auditor withdrew AC-7/AC-8 and re-confirmed at `9f75a17`. |
| choosing-orchestrator: with doctrine in the room the seat delegates to the roster unprompted | W4 AC-9 | proven | `support-table.orchestrator.md:43` REFUSED (doctrine-route PASS; C3–C6 yes; conjuncts in `…/cells/choice.conjuncts`) | C1/C2 = no: no native call, so the conversion wall was not exercised on this path (that is AC-6's job). |
| a real orchestrator → codex dispatch lands on the roster's seat and delivers | rule `dispatch-probe` | proven | `support-table.orchestrator.md:39` ALLOWED: child `56994ead…` delivered `drill-probe.md`, served by `gpt-5.6-sol` per its rollout | |
| named-mode send creates the child with `sub_agent_name` so the rendered executor binds (A-2) | W4 §5 A-2 | proven | W4 audit Addendum 1: child `3044AEA8` carries `sub_agent_name=implementor-regular` in `omnigent_conversation_metadata`, `reported_model=gpt-5.6-terra` | |
| worker seats cannot dispatch natively (`Agent`/`Task` in `tools_denied`) — four worker roles | W5 AC-11 (T1), R-W5-9 | proven (declaration) | git objects at HEAD: `omni:bundle/agents/{researcher,test-runner,implementor-regular,implementor-complex}/config.yaml` list `- Agent`/`- Task` under `tools_denied`; `merge-check-6d22852.log:1505` `418/418` | Claude honours the names as deny targets at dispatch time: **untested** (A10, PROMOTE by trigger — fires the first time a constituted worker is seen attempting a native spawn). |
| auditor and critic seats are contained the same way | Chris D3 (2026-09-03), W6 §3 | in-flight | `omni:bundle/policies/dispatch_convert.py` `_names_a_worker` skips the two assurance seats; their configs grant `Agent`/`Task` (`tools_allowed`) | The conversion wall covers 4 of 6 worker seats. |
| `mcp__omnigent__sys_session_create` cannot be used to route around the roster | A-W5-156; W6 §3 | refuted → in-flight | `effectiveness-scorecard-w5.log:8,13` `raw session_create=1` on both bare-seat controls | The product seat did not take the route (0/23); a bare seat did, twice. Unwatched by any wall. |
| batched drain: several landed children close in one drain | W3 AC-11 cl.2; rule `batched-drain` | untested | `support-table.orchestrator.md:44` UNTESTED (CONTROL, 0 children landed); no `drain` line in any W3 drill/smoke log | Waived at W3, never re-proven. |
| the orchestrator's inbox carries the child's refusal text after a planted lie | rule `inbox-conjunct` | refuted (on the drill) | `support-table.orchestrator.md:46` CONTROL FINDING: inbox read returned "Inbox is empty — no completed tasks." | The seat-side wall refused (rung 4, citizen plant); the orchestrator-side echo did not appear on this act. Same shape as W3 AC-3's contradicted inbox conjunct. |
| Chris's own cold-start walk delegated through the roster | W3 AC-12 | refuted | plan `wave-03…plan.md:355-369`: "2 Agent calls, 0 sys_session_send, 0 codex rollouts" | The wall that later re-routes this (dispatch-convert) shipped at W4. |

## Rung 4 — the core walls refuse on a Claude seat (drill-proven)

Orchestrator seat = `claude-native/claude-fable-5-1`, table at `34a7107`, 2026-09-02 (m1). Implementor seats
from the m2 table at `48c99f7`, 2026-09-01. `omni:.bionic/docs/specs/epic-20-bionic-on-omnigent/` prefix omitted.

| requirement | source | status | primary surface | note |
|---|---|---|---|---|
| commit-evidence (core wall 1) refuses on the Claude orchestrator | TDD §4 | proven | `support-table.orchestrator.md:18` REFUSED, seat transcript | |
| artifact-layout (core wall 2) | TDD §4 | proven | `support-table.orchestrator.md:19` REFUSED | |
| dispatch-deliverable (core wall 3) refuses a dispatch naming no deliverable | TDD §4 | proven | `support-table.orchestrator.md:22` REFUSED; CONTROL `:30` ALLOWED (a compliant dispatch passes) | The paired control is what makes the REFUSED a wall rather than a wall-that-refuses-everything (A-W1-24(a)). |
| writer-delivered (core wall 4), seat-side Stop hook, on a **codex** child dispatched by the Claude orchestrator (citizen plant) | TDD §4 + §12 W3-1, ADR-007 | proven | `support-table.orchestrator.md:42` REFUSED: child said `[REFUSED: deliverable missing: …drill-citizen-plant.md]`, wall wrote `landing-swept/v1 … verdict=refused`, deliverable absent as planted; twin `:41` ALLOWED (`verdict=met`) | This is SC-1 clause 2's wall half, proven on a drill, 2026-09-02 — after W2 waived it and W3 proved it one-sided. |
| writer-delivered seat-side on a **claude** citizen child | TDD §4 | untested | `support-table.md:72-73` UNTESTED (`child=none`, nothing journalled); W3 audit: "No claude citizen dispatch was run at all" (`step5-audit.md:130-134`) | The claude Stop-hook route was proven only via the drill's `BIONIC_DELIVERABLE` wrapper (`support-table.md:35,42` REFUSED, `route=binding`), never in a citizen run. |
| writer-delivered backstop (server-side rewrite to `[REFUSED: deliverable missing]`) | TDD §4 backstop, F3 | proven | `support-table.orchestrator.md:37-38` REFUSED (`ALLOW + data rewrite`), both body shapes | A backstop, never counted as the wall (S4 accounting). |
| resume-before-dispatch refuses with no pulse and with a decayed clock | TDD §4 | proven | `support-table.orchestrator.md:31-32` REFUSED (server-side, state planted); live `:23` REFUSED | |
| resume-before-dispatch lets a compliant dispatch through when the clock is live (CONTROL) | drill CONTROL | refuted (instrument) | `support-table.orchestrator.md:33` CONTROL expected ALLOW, got REFUSED: "'drill-control' already names an OPEN contract" — same on the m2 table `support-table.md:64` | A compliant act was refused by the composed wall because a prior drill's contract row stayed open (TDD §12 W3-10 phantom-OPEN residue). **Not in the W6 charter**; fog candidate. |
| pulse-armed: the dispatch is refused before the first tick and allowed after one | rule `pulse-armed` (binding) | proven | `support-table.orchestrator.md:40` REFUSED (the pair holds) | |
| duties-on-tick: a tick that skipped last tick's duties is refused | TDD §4 | proven (unpaired) | `support-table.orchestrator.md:35` REFUSED (`duties skipped…`); CONTROL `:34` ALLOWED | "no usable twin session of another harness — UNPAIRED". Live cell `:28` ALLOWED = the tick reached the seat and nothing was refused (no violation was planted live). |
| deadline: an overdue dispatch on a tick is refused until escalated | TDD §4 | proven (unpaired, probe only) | `support-table.orchestrator.md:36` REFUSED; live `:29` ALLOWED | No production tick has ever armed and discharged duty 4 / the reaper (TDD §12 W3-4 "live-unverified"). |
| protect-main / protect-database on the Claude orchestrator | TDD §4 | proven | `support-table.orchestrator.md:20-21` REFUSED | Shadowing risk (P10): the installed plugin's PreToolUse hook can refuse first. `SHADOWED: 0` on this table, so these came from the bundle wall. |
| protect-main / protect-database on `claude-native/claude-sonnet-5` (implementor.regular) | TDD §4 | refuted | `support-table.md:30-31` ALLOWED: "attempted=yes issued=yes; no refusal from the bundle wall" | The same rule REFUSED on `claude-opus-5` (`:37-38`). Neither the bundle wall nor the plugin hook fired on the sonnet seat. Not in the W6 charter; fog candidate. |
| dispatch-convert (rung 3) on the orchestrator | TDD §4 | proven | `support-table.orchestrator.md:24` | |
| stop-guard, execution-recorder, context-spend (prompt layer) | TDD §4 | untested | `support-table.orchestrator.md:15-17` UNTESTED (`layer: prompt`, `violation.expect: UNTESTED`) | By declaration: nothing is planted for a prompt rule. |
| worktree-per-writer (prompt + attestation) — every seat | TDD §4; R15 | untested | `support-table.md:29,36,43,48`, `support-table.researcher.md:15` UNTESTED | R15's load-bearing half. |
| SC-5: every rule appears in exactly one layer; core four are policy/binding only | PRD SC-5; W1 AC | proven (hermetic) | `omni:bundle/rules.yaml` (16 rules: 10 policy · 1 binding · 5 prompt); `tests/rules.test.sh` 16/16 (`slice-4-9-evidence.log:48`) | Caveat: `tests/rules.test.sh:48` points the agreement arm at the untracked `TDD.md`, so arm (e) cannot run from a fresh clone. |
| R9: a vendor whose binding cannot carry a wall may not hold that role; the table decides | PRD §3 R9; TDD §7 | proven (ownership) / untested (enforcement) | `support-table.md:3-5` "written ONLY by `tests/drill/run.sh`… sole authority" | Nothing *reads* the table to refuse a roster assignment; the roster is hand-written config. The rule is a convention, not a wall. |
| R10 / R11: each rule has one recorded binding layer; non-core discipline may be prompt-level and the table says so | PRD §3 | proven | `omni:bundle/rules.yaml` `layer:` per rule; prompt rows carry `expect: UNTESTED` | |
| the drill's ALLOWED is a finding, not a test failure; SHADOWED is distinguished from ALLOWED | ADR-002, TDD §12 W3-9 | proven | `omni:.bionic/docs/record/epic-20-w3/probes.md:449` P10 `fails` (wall shadowing confirmed) → SHADOWED class; `tests/drill/README.md` §"What a cell means" | |
| a disarmed bundle reads ALLOWED or SHADOWED on every policy/binding cell (RED run) | drill `--disarmed` | proven (W1/W3) | `tests/drill/README.md` §"The RED run" (captured table); W3 4/8a amendment | Not re-run since W3. |

## Rung 5 — an audited-rigor run: Claude orchestrating, Codex working

| requirement | source | status | primary surface | note |
|---|---|---|---|---|
| SC-1 clause 1: one wave at `audited` completes end-to-end with orchestrator Anthropic, implementors OpenAI via Codex, reviewer Anthropic | PRD SC-1 | proven at **task** scale, untested at wave scale | THE RUN (W5 AC-1): `session-items.json` 617 items; dispatches by role researcher 3 · implementor-regular 6 · test-runner 7 · implementor-complex 3 · auditor 1 · critic 1; commits `59b67fa · 356d13b · f830c0d · 3770316` on base `536c284` (git objects); induced park idx 133; reap dry-run → live idx 503-507 | The change was AC-11 (four YAML edits), 67 min. W2's claim of clause 1 rests on chat.db readbacks quoted in prose (`step5-walk.md:504-521`, no captured log). Epic matrix row still `pending` (`epic.plan.md:127`). |
| the orchestrator loads the method unprompted | W5 AC-1 (a) substance | proven | `session-items.json` call #2 = `Skill {"skill":"bionic:canonical-sdlc"}` (idx 11) | |
| the orchestrator prints the engagement announcement on turn 1 | W5 AC-1 (a) literal | refuted | `session-items.json` `data[4]` first assistant text = "Resuming the W5 run. First the load-time announcement, then…"; seat transcript `~/.claude/projects/-Users-admin-workspace-personal-bionic-omni/e8ec3239-….jsonl` sole hit is a Bash writing `run-record.md` | A-W5-175: the seat's record claimed it printed; three readers passed the claim. Proven once live in smoke-3 (`:85`) on a one-piece brief. |
| the evidence gate refuses a placeholder commit and the seat honours it | W5 AC-1 (b) | proven | `session-items.json` idx 83-84: `BLOCKED: canonical-sdlc task T1 evidence line is a placeholder ('pending')` | Second refusal (idx 178/180) reached the store as a child's returned report — primary as a message, secondary as to the hook event. |
| independent auditor and critic seats produce verdicts | W5 AC-1, PRD §2 #2 | proven (dispatch) / untested (verdicts) | sends idx 431 (`agent=auditor`), 433 (`agent=critic`); verdicts live in `the-run/audit-t1.md`, `critic-t1.md` written by those seats | A seat-written verdict is self-report under A-W5-175's own rule. |
| SC-1 clause 2: a planted false delivery is refused by a wall, not a prompt, and the refusal is on the record | PRD SC-1 | proven on the drill (2026-09-02), untested inside a wave run | rung 4 citizen-plant row (`support-table.orchestrator.md:42`) | W2 AC-9 waived (backstop only, hook absent, A-W2-54); W3 AC-3 seat half proven / inbox half contradicted; no wave has run a planted lie through a real audited run. |
| SC-1 clause 3: the measured table shows every core wall carried for every role in the mix | PRD SC-1 | refuted (by scope) | `drill-w2-4-6-3.log:135-193`: 20 of 28 role × core-wall combinations emit no cell; commit-evidence / artifact-layout / dispatch-deliverable are measured for the orchestrator only (they are orchestrator-phase acts) | The AC-10 readback "no core cell for a role is UNTESTED" is literally true of the cells that exist. The criterion quantifies over a unit the drill does not produce. |
| AC-2: effectiveness is a measured difference against a bare-model control (containment 0/23 vs 2/5, 1/4; method loaded vs not; gate refusals 2 vs 0) | W5 AC-2 (re-tiered T4→T3 by the orchestrator on Chris's instruction; ratified A-W5-178) | proven (numbers) / untested (method) | numbers re-derived from the three item stores 2026-09-04 (see rung 3); `effectiveness-scorecard-w5.log` is 18 lines of **output only** — no command, no script, despite `effectiveness-scorecard-w5.md:3,49` saying it carries them | The computation is not re-runnable from its cited artifact. W6 charter §6 makes it the standing per-wave measurement. |
| R7: cross-vendor review is the default at `audited`; collapse → WARN and continue | PRD §3 R7 | untested | `support-table.md:53,57` `cross-vendor-review` prompt UNTESTED | No WARN has ever been written; SC-4 (rung 10). |
| R14 worker liveness: event-driven (completion + deadline policy) | PRD §3 R14 | proven (mechanism) / untested (live escalation) | deadline probe `support-table.orchestrator.md:36`; F4 "no per-sub-agent deadline" in omnigent (TDD App. B) | No worker has ever been escalated for an overdue deadline in a run. |
| R14 orchestrator liveness: a measured periodic pulse | PRD §3 R14; TDD S5 | proven with caveat | `measure-4.md:170` `holds with caveat` (seat cannot arm its own timer; armed off-seat); `measure-8.md:227` `holds with caveat: 4/6 delivered` (misses were bionic's own duty refusals); W2 AC-7's ≥3-tick readback is plan prose only (`wave-02…plan.md:245`) | The pulser is launcher residue (BLOCKED row 6): no omnigent route arms a timer for a native seat. |
| duty 4 (reap) arms and discharges on a production tick | TDD §12 W3-4 | untested | hermetic `reap-closed` 33/33 only; no cell for triage, reap or census exists under `tests/drill/` at W3 (W3 audit) | W3 AC-10 waived; the W5 reap was driven by the driver, not a tick. |
| R15: the orchestrator never runs in a worktree; workers each in their own | PRD §3 R15 | untested | prompt rows UNTESTED (rung 4) | |
| R13: a pivot preserves on-disk artifacts only; cold resume from the plan file (T1) | PRD §3 R13 | untested | — | Never performed (rung 9). |
| SC-6: PRD + TDD ratified, epic re-entered at Step 2 by 2026-08-30 (commitment) | PRD SC-6 (T0) | proven | `omni:.bionic/docs/specs/…/epic.spec.md` frontmatter `sdlc-step: 2`, `design: TDD.md`; `epic.plan.md` Step 2 line dated 2026-08-29 | The ambition half (SC-1 run once) is the clause-1 row above. Epic matrix row still `pending`. |
| every wave-close regression floor | W1–W5 close-outs | proven (per wave, on the wrong sha at three closes) | W2 `regression-b6ab6ff.log:46` 40/40 (delivered head `684b74a`, one docs commit later); W3 `regression-48c99f7.log:44` 41/41 (wave closed at `f71ec4a`, 8 commits later, per-suite only); W4 `a3003c6` 43/43; W5 `regression-50893e5.log:50` 44/44 — **30 minutes before the AC-11 merge `6d22852`**; 7 commits and 23 tracked files changed since, covered by an 8-suite merge-check (`merge-check-6d22852.md:42` ALL GREEN) not `tests/run.sh` | No full `tests/run.sh` record exists for the tree at `42f4cf8`. Consistent with "one regression means one", but the ledger records the gap. |

## Rung 6 — a Codex seat wakes with identity and walls

| requirement | source | status | primary surface | note |
|---|---|---|---|---|
| a codex-native implementor is served by the roster's model | rule `served-model` CONTROL | proven | `support-table.orchestrator.md:39` child served by `gpt-5.6-sol` (rollout `~/.omnigent/codex-native/d2ca6a65…/…/rollout-2026-09-01T22-58-01-….jsonl`, present) ; `support-table.md:24` codex orchestrator served by `gpt-5.6-sol` | |
| a codex-native worker carries its role text at first turn | W5 4/3b (SessionStart hook, 0.11.0) | proven (0.11.0 route) | smoke-3 `:106` `PONG`; `:144-147` rollout counts (unlabelled) | Retires with 0.12.0's `developer_instructions` (in-flight, W6 slice 1). |
| a codex-native seat's Stop hook fires at all | TDD §12 W3-6 | proven with a flag dependency | `omni:.bionic/docs/record/epic-20-w3/probes.md:148` P1 `holds with caveat`: runs only because omnigent passes `--dangerously-bypass-hook-trust` to the TUI; `p1-stop-payload.jsonl` | If the flag goes away the wall goes silent — absent, not wrong. Per-cell `hook ran=yes` evidence is load-bearing. |
| codex-native researcher / test-runner / auditor / critic seats can be launched and served | SC-2 precondition | untested | `support-table.md:44,49,54,58` UNTESTED "no live session for this seat, so nothing served it" | The m2 run never launched them. |
| tool denial on a codex-native assurance seat is enforced | R12 (rung 2) | refuted → in-flight | see rung 2 | |
| effort on a codex-native seat is the roster's | rule `effort-pinned` | untested | see rung 2 | |
| a codex-native seat reads a project instruction channel (`AGENTS.md`) | measure-6 | proven with caveat | see rung 2 | |
| the Codex subscription is above the free tier for the codex seats that ran | epic plan Assumption (2026-08-30), W2 slice 4/1 | not checked by this ledger | `~/.codex/auth.json` is a credential file and was not opened | 2026-08-29 measurement: `plan_type: free`. Whether W2's upgrade slice landed is in the W2 plan; this ledger did not read the token. |

## Rung 7 — dispatch from a Codex orchestrator through the roster

| requirement | source | status | primary surface | note |
|---|---|---|---|---|
| a codex-native orchestrator can complete a `sys_session_send` to a child seat | SC-2 mechanism | refuted (0.11.0) | `omni:.bionic/docs/record/epic-20-w3/m2-dispatch-investigation.md:9-23`: the send blocks indefinitely once the `omni run -p` client that launched the seat has exited; runner log `Codex native steered active turn` ×2; the seat issued 3 correctly-formed sends | "NOT seat-behavioural" — A-W1-24(c) refuted. Untested on 0.12.0. |
| the drill can join a codex-orchestrator dispatch to a child | rule `dispatch-probe` | untested | `support-table.md:70` UNTESTED ("issued no dispatch this drill could join to a child") | Consequence of the row above. |
| a compliant dispatch from a codex session passes the composed wall (CONTROL) | rule `dispatch-deliverable (control)` | proven | `support-table.md:61` ALLOWED | Server-side evaluate route; this is the engine, not the seat. |
| resume-before-dispatch refuses a codex session with no / decayed pulse | TDD §4 | proven (server-side) | `support-table.md:62-63` REFUSED | CONTROL `:64` REFUSED — same phantom-contract instrument defect as rung 4. |
| writer-delivered backstop on a codex orchestrator's inbox | TDD §4 backstop | proven (server-side) | `support-table.md:68-69` REFUSED | |
| reverse-direction conversion wall (Codex orchestrator's native spawn → roster) | W5 Not Doing; W6 | untested | — | A codex seat has no `Agent` tool (TDD §4 `dispatch-convert` "n/a"); what a Codex orchestrator would reach for instead has never been observed. |
| Chris walks a Sol orchestrator dispatching to a Claude seat | W4 AC-13 (T4) | untested (waived) | `wave-04…plan.md:401` waiver: "the conversion wall was built against Claude Code's tool names; a Codex orchestrator has no equivalent wall in this wave, so the reverse walk would measure what was never built" | Chris 2026-09-02; promoted to W5, then to W6. |

## Rung 8 — the core walls refuse on a Codex seat

Codex orchestrator seat = `codex-native/gpt-5.6-sol`, m2 table at `48c99f7`, 2026-09-01.

| requirement | source | status | primary surface | note |
|---|---|---|---|---|
| commit-evidence · artifact-layout · protect-main · protect-database · dispatch-deliverable · resume-before-dispatch on the Codex orchestrator | TDD §4 | untested | `support-table.md:18-23` UNTESTED: "seat printed step N's markers but never issued the violation — nothing was attempted, so the wall was never asked" | **The UNTESTED-rows problem** (#19 fog). The seat cooperated with the script but declined to commit the act; the drill plants by asking the seat to do it. |
| duties-on-tick and deadline run for a codex-native session at REQUEST phase | TDD §4 | refuted (0.11.0) | `support-table.md:66-67` UNTESTED with PAIRED evidence: identical body + planted state REFUSE on the claude session `008bdc04…` and return a bare ALLOW here — "this REQUEST-phase rule did not run for a codex-native session" | The brief's "`duties-on-tick` and `deadline` do not run on codex-native". Reading the ALLOW as ALLOWED is the A-W1-24(a) false-green shape; the drill declined to. Live `:27-28`: 2 ticks posted 2xx, tick reached the seat = **no**. |
| writer-delivered on codex-native researcher / test-runner (drill wrapper route) | TDD §4 | proven (drill route) | `support-table.md:47,52` REFUSED (`route=binding+seat-visible; hook ran=yes`) | Provoker-launched seats with `BIONIC_DELIVERABLE`; the citizen route on a codex child is the rung-4 plant. |
| writer-delivered citizen twin/plant on a **claude** child of a Codex orchestrator | TDD §4 | untested | `support-table.md:72-73` UNTESTED (`child=none`) | Depends on rung 7. |
| stop-guard · execution-recorder · context-spend · cross-vendor-review · worktree-per-writer on codex seats | TDD §4 prompt layer | untested | `support-table.md:15-17,43,48,53,57` | By declaration. |
| SC-2: a wave with every role on OpenAI reaches `standard`, then `audited` | PRD SC-2 | untested | W3 AC-5/AC-6 waived "D1: 1" (`wave-03…plan.md:262-274`); `epic.plan.md:128` `pending`; continuation carries it with trigger "upstream elicitation ships" | No unit at either rigor ever ran all-Codex. Note the m2 mix itself put implementors on claude-native (`support-table.md:29-42`), so "every role codex-native" was to be read as the m1 ∪ m2 union. |
| orchestrator-role walls on Codex: 5 REFUSED · 3 ALLOWED · 16 UNTESTED (the brief's "mostly UNTESTED") | brief | proven (count) | `support-table.md` rows 15-28, 61-71 | Of the 5 REFUSED, 4 are server-side probes (`[probe]`) and 1 is the failed control; **zero** are the seat itself refusing a planted act. |

## Rung 9 — mid-run orchestrator swap (relaunch + cold resume, same run id)

| requirement | source | status | primary surface | note |
|---|---|---|---|---|
| SC-3: orchestrator seat switched mid-wave (one flag, idle-only), wave resumes from on-disk artifacts, same wave id, no worktree lost | PRD SC-3; R5; R13 | untested | `epic.plan.md:129` `pending`; W5 spec Not Doing → W6 | Never attempted. |
| R5: each role declares primary + fallback; one flag switches | PRD §3 R5 | proven (declaration) / untested (switch) | `omni:bundle/config.yaml` roster `fallback:` per role, `active:` | `active: fallback` has never been flipped in a run. |
| omnigent's `switch-agent` route is not usable for a custom bundle | TDD App. B F7 | proven (source) | `POST /sessions/{id}/switch-agent` built-in agents only (0.11.0 read) | Pivot must be relaunch + cold resume. 0.12.0 untested. |
| the plan file is the entire run memory; resume re-registers open dispatches and re-arms the pulse (T1) | TDD T1 | untested | — | `session_state` does not persist to `chat.db` (TDD §12 W3-7), which vindicates the file as the only carrier; the resume step has never been run cold. |

## Rung 10 — reviewer primary unavailable → fallback with a WARN

| requirement | source | status | primary surface | note |
|---|---|---|---|---|
| SC-4: reviewer's primary vendor made unavailable; run proceeds on the fallback; record carries a WARN naming the collapse | PRD SC-4; R7 | untested | `epic.plan.md:130` `pending`; W5 spec Not Doing → W6 | Never attempted. |
| the dispatch policy writes `warn: "cross-vendor collapse…"` to the plan's registry row | TDD §4 `cross-vendor review` | untested (unimplemented) | `omni:bundle/rules.yaml:189-195` `cross-vendor-review` is `layer: prompt`, `violation: {expect: "UNTESTED"}`; the registry's header comment `:12-16` says the plan "folds" the TDD's "advisory WARN" into `layer: prompt`; `grep -i warn bundle/policies/*.py` returns nothing | The TDD's WARN-writing mechanism was never built. The fold is deliberate and commented, so SC-5 is satisfied, but nothing can produce SC-4's WARN today. |

---

## Cross-cutting: instruments, integrity, and the record

| requirement | source | status | primary surface | note |
|---|---|---|---|---|
| a seat's self-report is not evidence; "the seat did X" is read from items/transcript | A-W5-175/178; W6 §6 | proven (the failure) / in-flight (the rule) | rung 5 announcement row; `effectiveness-scorecard-w5.md` §finding | The auditor mandate amendment and the first-line drill cell are W6 items. |
| every measure-first verdict recorded before a wall was built on it | W1 gate; ADR-005 | proven | `omni:bundle/MEASURED` sha256 == `record/epic-20-w1/measure-{1..6}.md` (re-derived by the W1 extraction); four of six probe transcripts still on disk; verdicts: M-1 holds w/ caveat · M-2 holds · M-3 holds · M-4 holds w/ caveat · M-5 holds · M-6 holds w/ caveat; W2 M-7 holds · M-7b holds · M-8 holds w/ caveat | The gate checks the verdict's *grammar* (`holds(: .+)?`), not its strength. |
| the instruments read what is real: a doctored cell/item store turns the reader RED | W5 AC-10 (T1) | proven | `omni:.bionic/docs/record/epic-20-w5/slice-4-8-evidence.log:472` `FAIL: AB1…` (RED by stashing to `721d6c0`) → `:1970` PASS → `:6681` `403/403` | |
| every policy DENIES its planted violation and ALLOWS the clean twin, with mutation power | W1 AC-9 (T1), ADR-004 | proven | `omni:.bionic/docs/record/epic-20-w1/drill-green11.md:97-99` `173 passed`; `audit-revert-watch.md` (stub `dispatch_deliverable.evaluate` → `17/17 → 4/17`), `audit-revert-watch-2.md` (backstop `21/21 → 7/21`, protect_main `19/19 → 4/19`) | Later: pytest 496 collected at `6d22852` (`merge-check-6d22852.log:13`). |
| both bindings honour the exit-2 + stderr contract | W1 AC-10/11 (T2) | proven (Claude) / proven with weaker fidelity (Codex) | `audit-20260830.md:739-743` `134/134 passed`; power `audit-revert-watch-2.md` stub A `134/134 → 79/134` | The Codex fixture was hand-transcribed from a research record, not captured (`audit-20260830.md:220-228`); W3's P1 later captured the real payload and found the fixture one field short (TDD §12 W3-6). |
| the drill's CONTROL rows pass (a wall that refuses everything is a false green) | ADR-004, A-W1-24(a) | refuted for one control | rung 4 `resume-before-dispatch (control)` REFUSED on both live tables | Two CONTROL FINDINGS (process-census, inbox-conjunct) are also failures scored REFUSED; the brief's "20/32 REFUSED" therefore counts 3 instrument failures as wall holds. Net walls held on the orchestrator table: 17. |
| evidence pointers in the record anchor to real lines | auditor mandate | refuted in four places | `merge-check-6d22852.md` "Log Line" column cites lines holding unrelated PASS lines (real totals at `.log:13,102,147,286,1022,1505`); its "Command 9" output is not in the log; `auditor-revert-watch.md` cites 297/300/319, real 139/141/374 (A-W5-170); `effectiveness-scorecard-w5.log` carries no script | Counts were correct in every case; anchors were retyped. |
| the W5 record is versioned | — | refuted | every W5 SDLC commit (`180894d`, `8e1f09a`, `45b173c`, `42f4cf8`) shares tree `f5fa6df…` — empty; `.bionic/` is gitignored | Post-hoc corrections (A-W5-175 "CORRECTED 17:15:10Z") have no history. Bionic's "`.bionic/` stays out of git" is a standing decision; the ledger only notes the consequence. |
| the SC-5 agreement test runs from a fresh clone | tests/rules.test.sh | refuted | `omni:tests/rules.test.sh:48` reads the untracked `.bionic/docs/specs/…/TDD.md` | |
| no W3 close-out artifact exists | — | proven (absence) | `omni:.bionic/docs/record/epic-20-w3/` holds step5/6/7 files only; plan `:78` "close-out report delivered in-session" | SC-2's and R18's W3 status live in the plan matrix and the audit. |
| TDD §12–§14 amendments: 23 items, all additive | brief | proven (count) | `TDD.md:266-599` | Of note for a v1 spec: W5-1 (instructions never reach a seat) is itself now refuted-by-version (0.12.0). |
| ADRs 001–012 accepted; 013–015 proposed (Chris) | `omni:.bionic/docs/adrs/epic-20-bionic-on-omnigent/` | proven (status lines) | ADR-013/014/015 `:24` "Status: proposed — Chris ratifies at Step 9" | ADR-013 is correct for 0.11.0 and retires on upgrade (identity research). |

---

## Counts

Per rung, rows by status (a row split into clauses counts each clause; "proven with caveat"
and "proven (declaration) / untested (X)" count under the first status named):

| rung | proven | refuted | untested | in-flight | not checked |
|---|---|---|---|---|---|
| 0 one home | 3 | 1 | 2 | 0 | 0 |
| 1 launch | 10 | 1 | 6 | 2 | 0 |
| 2 seat constitution | 13 | 1 | 6 | 3 | 0 |
| 3 roster dispatch | 9 | 3 | 1 | 1 | 0 |
| 4 walls on Claude | 16 | 2 | 3 | 0 | 0 |
| 5 audited run | 10 | 2 | 4 | 0 | 0 |
| 6 Codex seat | 4 | 1 | 2 | 0 | 1 |
| 7 Codex dispatch | 3 | 1 | 3 | 0 | 0 |
| 8 walls on Codex / SC-2 | 2 | 1 | 4 | 0 | 0 |
| 9 pivot | 2 | 0 | 2 | 0 | 0 |
| 10 fallback WARN | 0 | 0 | 2 | 0 | 0 |
| cross-cutting | 8 | 5 | 0 | 0 | 0 |
| **total (140 rows)** | **80** | **18** | **35** | **6** | **1** |

Counting rule: a row whose status cell names two statuses (e.g. "proven (declaration) / untested
(switch)", "refuted → in-flight") is counted under the first. Rows tagged "refuted → in-flight" (three,
rungs 2–3) therefore sit under refuted; the in-flight column holds only rows whose *primary* status is
the pending repair. Read together, 9 rows have a named W6 repair.

Epic-level success criteria: SC-1 clause 1 proven at task scale · clause 2 proven on a drill only ·
clause 3 refuted by scope; SC-2 untested; SC-3 untested; SC-4 untested; SC-5 proven (hermetic);
SC-6 proven. All six rows still read `pending` in `omni:.bionic/docs/plans/epic-20-bionic-on-omnigent/epic.plan.md:127-132`.

## What the ledger revealed for the map

Candidates for fog or tickets on #19, each with the row above that produced it:

1. **The brief's rung-0 fact is wrong.** The fork's payload *was* the installed plugin for W5 (rung 0, row 2). The migration ledger (R3) should sort against "what ran" = the fork's 1.3.3–1.3.5, not "bionic 1.4.1 ran everything".
2. **Everything proven is proven on 0.11.0.** 0.12.0 is installed and untested; R2's seam inventory should say which rung-4 cells are expected to move (instructions channel, timer route, `switch-agent`). A v1 version policy (already fog) now has a concrete re-certification list: the three support tables.
3. **Two refuted walls with no owner in the W6 charter:** `protect-main`/`protect-database` ALLOWED on the sonnet implementor seat (rung 4), and the `resume-before-dispatch` CONTROL refusing a compliant act on both tables (rung 4 / 7). Neither is a W6 item.
4. **SC-1 clause 3 quantifies over a unit the drill cannot produce** (rung 5). The admission rule (P1) needs a rule for criteria whose proving surface does not exist: rewrite the criterion to the instrument's unit, or build the instrument first.
5. **The scorecard is the certifying measurement and is not reproducible from its artifact** (rung 5, AC-2 row). P1 should require the script beside the numbers.
6. **Codex-side climb is almost entirely untested, and one mechanism is refuted** (rungs 7–8): the send-blocks-after-client-exit defect is the reason no all-Codex unit ever ran. R2 should check whether 0.12.0 changed it before G2 orders the Codex rungs.
7. **R18 was refuted, then reframed by ADR-011.** G3's "whether the launcher survives" starts from 608 no-seam lines and six BLOCKED rows with asks, not from "reduce to instrumentation".
8. **SC-4's WARN has no producer** (rung 10): the TDD describes a policy-written WARN; the registry deliberately folds the rule into the prompt layer and no policy writes one. SC-4 cannot be certified without building it first.
9. **Three CONTROL failures are counted inside "20/32 REFUSED"** (cross-cutting). Any v1 measurement that reports a REFUSED total should report walls-held and controls-failed separately.
10. **The glossary the map cites does not exist in bionic** (rung 0, last row); it is omni-side. Rung zero's migration list should include it.

## Appendix A — per-wave criterion roll-up

One line per wave-level AC, with the ledger row it feeds. "PRIMARY" here is the extraction's
class for the strongest surface found; the ledger status above is what the admission rule reads.

**W1 substrate** (14 matrix rows, all PRIMARY; regression 36/36 @ `2778a59`, `drill-green11.md:90`).
AC-1..6 = measure-first M-1..M-6 (cross-cutting row; every sha matches `bundle/MEASURED` @ `2778a59`) ·
AC-7 gate test 12/12 (`walk-20260830.md:225-231`) · AC-8 roster 77/77 (`audit-20260830.md:723-729`) ·
AC-9 policies 173 + mutation power · AC-10/11 bindings 134/134 · AC-12 `render.sh --check` rc=0 and
bundle-load 33/33 PRIMARY, the declared render-bundle 44/44 **self-report only** (`s9-bundle-load.progress.md:18`) ·
AC-13 the W1 support table: REFUTED three ways at the first audit, CONFIRMED, **withdrawn as hand-assembled
evidence** under critic F-1, CONFIRMED again on verbatim output; the live `support-table.md` was overwritten by
W3's m2 run and the `/private/tmp/bionic-omni-drill/green-11` evidence dir is gone, so `drill-green11.md:120-153`
is the only surviving copy; critic F-8: 15/25 cells UNTESTED by AC-13's own unit, core walls measured on no
writer seat · AC-14 = SC-5, rules 16/16 · AC-15 (SC-6 half) reclassified out by Chris, auditor UNVERIFIABLE.
Coverage hole with no criterion: `bundle/skills/` (A-W1-30). `params.tools_denied` was a **declaration only** on
0.11.0 (A-W1-6) — the enforcement gap rung 2 still carries for Codex.

**W2 first-live** (12 ACs; 11 CONFIRMED, AC-9 waived; wave verdict UNVERIFIABLE closed by user waiver;
regression 40/40 @ `b6ab6ff`, delivered head one docs commit later). AC-1 drill re-run PRIMARY · AC-2
render/bundle-load counts transcribed in a slice report, corroborated at suite level · AC-3/4/6 drill cells
PRIMARY (`drill-w2-4-6-3.log`) · AC-5 247/247 · AC-7 M-8 `holds with caveat`, the ≥3-tick discharge is plan
prose · AC-8 SC-1 clause 1: chat.db readbacks quoted in the walk, and the criterion's named source
(`executor` column) **does not exist** in 0.11.0 · AC-9 SC-1 clause 2: backstop only, hook structurally absent
(A-W2-52/54), the inbox row reads `[deliverable missing: …]` not the spec's `[REFUSED: …]` — waived ·
AC-10 SC-1 clause 3: table literally true of the cells that exist, 20 of 28 role × core-wall combinations
have no cell · AC-11 43/43 · AC-12 RED→GREEN 0/7 → 7/7. W2-R5 (every act outside `omni run` ledgered) has
zero criteria; ratified as a close-out obligation.

**W3 cold-openai** (13 ACs; 4 PRIMARY for the full criterion, 7 waived on 2026-09-01 each with a W4 trigger,
2 partial; no close-out artifact; regression 41/41 @ `48c99f7`, wave head `f71ec4a` eight commits later,
per-suite evidence only). AC-1 codex citizen contract PRIMARY (`drill-w3-m1-2.log:125,128`), claude half never
run · AC-2 verdict rows PRIMARY (`1 met / 12 passthrough / 7 refused`) · AC-3 seat half PRIMARY, inbox half
CONTRADICTED by the same line · AC-4 twin PRIMARY · AC-5/6 (SC-2) ABSENT: the m2 codex orchestrator's
`sys_session_send` blocks once the `omni run -p` client exits (`m2-dispatch-investigation.md:9-23`) ·
AC-7 R18 accounting PRIMARY, "RETIRE demonstrated live" vacuous (zero RETIREs) · AC-8 permission_mode:
stated ground false, corrected; no-park unpaired; haiku PRIMARY (`probes.md:350`); triage ABSENT · AC-9
pulse grammar RED→GREEN PRIMARY · AC-10 reap loop hermetic only (33/33), no live cell · AC-11 refusal spelling
PRIMARY on a fresh server (backstop route), batched drain ABSENT · AC-12 Chris's walk delegated natively ·
AC-13 procedure REFUTED (wrong `--data-dir`), fixed, re-discharged on a walk. Probes P2, P4, P5, P6, P10 `fails`;
P1, P3, P7, P8b, P9 `holds with caveat`; P8a `holds`.

**W4 fundamentals-first** (13 ACs; 11 PRIMARY, AC-11/12 self-report quoting primary, AC-13 waived; ADR-009..012
accepted; regression 43/43 @ `a3003c6`, pytest 421). AC-1/2 scoreboard 608 / cap dropped · AC-3 four asks filed
(rows 9–12; "row 13" never existed) · AC-4 six of seven clauses, web link CONTRADICTED · AC-5 S19 arms 603/603 ·
AC-6 reuse 18→18 · AC-7/8 REFUTED at `663f800` (deny text named `name=`/`message=`), CONFIRMED at `9f75a17`
against omnigent's live schema builder (`evidence-6-send-schema.log:8-9` vs `:84-85`) · AC-9 choosing cell
PRIMARY (`choice.transcript.jsonl:16`, C1 no · C2 no · C3–C6 yes) · AC-10 REPL menu captured · AC-11 one home
via the auditor's re-exec · AC-12 walk contaminated, README patch never landed · AC-13 waived. A-W4-119: the
orchestrator seat fell back from Fable 5.1 to Opus 4.8 mid-drill (`served-model.orchestrator.jsonl:80`,
`apiRefusalCategory: cyber`; 21 opus rows to 16 fable rows in that file); AC-9's own cell was served by Fable.

**W5 sdlc-on-omnigent** (12 ACs; auditor-wave CONFIRMED with a post-audit correction; AC-2 re-tiered by the
orchestrator and ratified by Chris; AC-8 accepted at T2 by Chris; regression 44/44 @ `50893e5`, 30 minutes
before the AC-11 merge). AC-1 conjuncts (b)–(f) PRIMARY from the item store, (a) CONTRADICTED, (g) seat-plan
self-report · AC-2 numbers re-derivable, script absent from the log · AC-3 82/82, 122/122, revert-watch
72/122 · AC-4 three of four conjuncts PRIMARY · AC-5 PRIMARY · AC-6 two drill verdict files (FALSE then TRUE) ·
AC-7 PRIMARY · AC-8 T3 half powerless (`the-run-driver-evidence.log:382-388`), T2 half `1 failed, 54 passed` →
`55 passed` · AC-9 655/655 · AC-10 403/403 with a produced RED · AC-11 git objects at HEAD + 418/418 · AC-12
rules 16/16, TDD §14, asks 16/17. Evidence-pointer defects: `merge-check-6d22852.md` line anchors wrong and
"Command 9" absent from its log; `auditor-revert-watch.md` anchors retyped (A-W5-170); scorecard log
output-only; every W5 SDLC commit is an empty tree.

## Appendix B — the machine-enforced surface at `42f4cf8`

- **Registry** `omni:bundle/rules.yaml`: 16 rules — 10 `policy`, 1 `binding` (`writer-delivered`), 5 `prompt`
  (stop-guard, execution-recorder, context-spend, worktree-per-writer, cross-vendor-review, each
  `violation: {expect: "UNTESTED"}`). No `seat` layer; the support tables' `seat`/`binding` rows for served-model,
  effort-pinned, tool-denied, pulse-armed, dispatch-probe come from `tests/drill/binding-cells.tsv` (7 rows) and
  `probes.tsv` (9 rows), not from the registry.
- **Policies** `omni:bundle/policies/`: 11 handlers — commit_evidence, artifact_layout, dispatch_deliverable,
  dispatch_convert, resume_before_dispatch, duties_on_tick, deadline, protect_main, protect_database, walk_hide,
  writer_delivered_backstop (TOOL_RESULT, ALLOW + data rewrite). `dispatch_convert` abstains on any role in
  `roster_seats.json` (six roles) — with auditor/critic granting `Agent`/`Task`, those two seats are covered by
  neither the seat denial nor the wall.
- **Roster** `omni:bundle/config.yaml`: orchestrator claude-native/claude-fable-5-1 (fallback codex-native/gpt-5.6-sol);
  implementor.regular codex/gpt-5.6-terra (fallback sonnet-5); implementor.complex codex/gpt-5.6-sol (fallback opus-5);
  researcher/auditor/critic opus-5; test-runner haiku-4-5 medium. `tools_denied` lives per role in
  `bundle/agents/<role>/config.yaml`.
- **Bindings**: `bindings/claude/launch.sh` 763 lines / 16 blocks, `shim/claude` 853 lines, `hooks/landing.sh`,
  `lib/*`; `bindings/codex/scripts/{landing.sh,seat-prompt.sh}` + `hooks.json`. RESIDUE rows 9 and 20 record the
  0.11.0 `instructions:` gap on both harnesses; both are the rows 0.12.0 retires.
- **Tests**: `tests/run.sh` runs 44 gating suites (including `pytest tests/policies`, 352 test functions / 496
  collected, and `tests/drill/instrument.test.sh`). Last full run 44/44 @ `50893e5`; 23 tracked files changed since
  (AC-11 containment, 1.3.4/1.3.5 bumps); no full run at `42f4cf8`.
- **Machine footprint on 2026-09-04**: `~/.local/bin/claude` shim absent, `~/.codex/hooks.json` absent,
  `omni --version` = 0.12.0 (built 2026-09-01T20:58:30Z).
