---
paths:
  - "hooks/*.sh"
---

# Hook authoring

Anchors for the recurring traps when changing hooks in `bionic/hooks/`. Migrated from
`.bionic/memory/hooks-rules.md` (epic-12 wave-01 slice 6) with the correction ledger applied.

## CI + bootstrap registration

> **STALENESS NOTICE (self-retiring, ADR-003 pattern — see
> `.bionic/docs/adrs/epic-17-plugin-conversion/adr-003-self-retiring-transitional-tests.md`
> for the precedent this follows).** This section's registration mechanics
> (`MANAGED_HOOKS`, `tests/run.sh`'s `hooks/*.test.sh` glob-pick) describe the bootstrap-era
> hook-install path. **Retirement trigger: W5's deletion of `claude-bootstrap.sh`.** When
> that lands, this section either deletes or gets rewritten for the plugin-era
> `hooks/hooks.json` registration path (already live since W3) — the rest of this file
> (false-positive traps, MCP dependency traps, hook-writing discipline below) is NOT
> bootstrap-era and survives untouched. Added epic-17 W4 S4, 2026-08-18.

- **STALE-CORRECTED 2026-07-20 (wave-02): there is NO CI — `.github/workflows/` does not
  exist** (CI excised 2026-06-27, "no CI by design"; the old file-listed ci.yml rule is dead).
  Registration coverage for a new hook is structural: `tests/run.sh` glob-picks
  `hooks/*.test.sh` automatically, and `tests/scripts.test.sh` 4a/4b/4c enforce hook↔test
  pairing + `MANAGED_HOOKS` existence. Adding a hook = source file + `.test.sh` sibling +
  `MANAGED_HOOKS` entry; nothing else to register.

- **Architecture diagram (`architecture.excalidraw`) is manually authored and needs
  regeneration for install-layer changes** (new hooks, new install types, new managed files).
  It's not generated from code.

## False-positives and merge-commit handling

- **`~/.claude/hooks/protect-main.sh` false-positive on `GIT_VAR=... git commit`.** Commands
  starting with `GIT_VAR=... git commit` trip Block 3 on main (the loop's `^GIT_` regex
  catches the prefix, then Block 3 fires because the branch is main). Workaround: prefix with
  `env` — `env GIT_VAR=... git commit` is matched by `^env ` which additionally requires
  `git push` in the segment and passes.

- **Any hook inspecting HEAD's file list must use `git show -m --name-only --format= HEAD`**,
  not `git show --name-only --pretty=format: HEAD`. Without `-m`, a clean merge commit (no
  conflicts) emits zero output — git's default "combined diff" format is empty unless parents
  diverged with conflicts. Filters/guards that check "is this commit's file set all under X"
  then silently misclassify the merge as empty/matching and falsely skip. Caught 2026-04-16 by
  a Phase 8b adversarial critic on the (since-retired 2026-05-10) `memory-commit-save.sh`
  circular guard; fixed with `-m` before merge. Lesson generalizes to any future
  HEAD-inspecting hook.

## Plan-format-documenting-doc trap — RETIRED 2026-07-19

- **RETIRED (epic-07 wave 2):** the evidence-gate's `## SDLC State` parsing is now fence-aware
  on every read path (extraction, presence check, `## Tasks`, epic-plan merge-target read;
  matrix was fixed earlier in `2766364`). Fenced examples are documentation, invisible to
  parsing; a fenced-ONLY `## SDLC State` means the file passes through as non-canonical. The
  old `touch <real-plan>` workaround is obsolete. Regression tests 19o/19p/19q/19r pin the
  class. Origin: the trap's live recurrence false-blocked wave-2's own first commit (the plan's
  fenced D12 schema example shadowed the real section) — fixed at the root instead of
  re-worked-around.

## MCP dependencies in skills

- **`addy-agent-skills` ships skills with implicit MCP dependencies that the plugin metadata
  does not declare.** Confirmed 2026-04-26 with `browser-testing-with-devtools/SKILL.md`
  (assumes a `chrome-devtools` MCP server is configured; bionic now ships
  `chrome-devtools-mcp@latest` in `claude-config.txt` to satisfy it). When installing or
  upgrading the `addy-agent-skills` plugin, grep its skill files for MCP server references
  (`mcpServers`, `mcp__`, "MCP server") and ensure each referenced server is in
  `claude-config.txt`. Note also: that same SKILL.md references
  `@anthropic/chrome-devtools-mcp` — wrong package; the real npm name is `chrome-devtools-mcp`.
  Don't copy the bad name from the skill. **Update 2026-06-14:** canonical-sdlc Step 5 no
  longer *mandates* `browser-testing-with-devtools`/chrome-devtools MCP for routine browser
  verify — it now routes to the bionic-owned `browser-verify` skill, which drives via
  `playwright-cli` (CLI-first). The chrome-devtools MCP stays installed but is reserved as the
  deep-debug escalation only (Lighthouse, perf-trace analysis, profiling, network throttling).
  The MCP remains a real dependency — keep it in `claude-config.txt`; `tests/scripts.test.sh`
  3r/3s/3t still assert it.

## Discriminators in enforcement hooks

- **Enforcement hooks must discriminate by run-state marker, not by artifact-author field.**
  When a skill delegates artifact production to other skills (canonical-sdlc Step 3 →
  `superpowers:writing-plans`), the artifact correctly declares the *producer* via
  `governing-skill:`. Gating enforcement on `governing-skill: <self-skill>` makes the hook
  invisible to the artifacts the lifecycle itself produces. Use a separate state-marker field
  that the lifecycle stamps independently — canonical-sdlc uses `canonical_sdlc_version:`, set
  by Step 0. *(Correction 2026-07-27: the original text cited the then-current value
  `canonical_sdlc_version: 3`. The mechanism is live and unchanged; the supported value is now
  **12** — both hooks pin `SUPPORTED_SDLC_VERSION=12` and block loudly on anything else.)*
  Caught 2026-05-04 in the canonical-sdlc dispatch-gate + governing-skill hooks: every Step 3
  plan declared `governing-skill: superpowers:writing-plans`, both hooks early-returned, and
  `dispatch_enforce: true` was a no-op for the entire epic. Dispatch-gate hook retired
  2026-05-10 (too brittle); the governing-skill hook still uses the version-marker pattern.
  Generalizes to every skill with a multi-skill lifecycle that ships its own enforcement hooks.

## `set -u` and conditionally-bound variables

- **These hooks run `set -u`; a guard that references a variable bound on only SOME code paths
  crashes with "unbound variable" on the others.** Both
  `canonical-sdlc-{governing-skill,evidence-gate}.sh` run `set -u`. Caught 2026-07-20
  (bugfix·tested·task): adding `[ "$SCALE" != "task" ]` to the shared matrix-required block
  tripped `SCALE: unbound variable`, because `SCALE=$(yaml_get scale)` was assigned only inside
  one version arm while the shared block was reachable from another. Fix: read the var
  UNCONDITIONALLY near the other globals so it is `""` on every path — not `${SCALE:-}`
  scattered at each use. That fix is what the code does today: one unconditional line,
  `INTENT=$(yaml_get intent); RIGOR=$(yaml_get rigor); SCALE=$(yaml_get scale)`.

  *(Correction 2026-07-27: the original text described the bug in terms of "the v10-autonomous
  path" versus "the v11 arm", and prescribed mirroring a `MODE=$(yaml_get mode)` read. **Those
  version arms no longer exist** — v12 deleted all backward compatibility — and `mode:` is now
  a hard block, not a variable to mirror. Don't go looking for either. The rule survives on its
  own terms: whenever you add a guard on a variable, grep for its assignment and confirm every
  reaching path sets it.)*

  **What surfaced it: cross-version test coverage** — a suite that only exercised the arm being
  edited would have shipped the crash. With the version ladder gone, the equivalent discipline
  is to exercise every branch that reaches the shared block, not only the one you touched.

- **CR-only (classic-Mac `\r`) line endings: normalize by TRANSLATING `\r`→`\n`, never
  `tr -d '\r'` (delete).** `tr -d '\r'` handles CRLF (`\r\n`→`\n`) but on a CR-only file
  DELETES the sole line separators, collapsing the whole file to ONE line — line-anchored
  parsers (`$0 == "---"`, `^## SDLC State`, matrix grep) then mis-fire. In the evidence gate
  that was a fail-DANGEROUS silent bypass (every commit passed ungated, fixed wave-04
  `b1765c2`); the same `tr -d` in governing-skill was fail-SAFE (valid artifacts false-blocked,
  fixed 2026-07-20 `c191e71`). Canonical transform, used by both hooks now:
  `awk '{ sub(/\r$/, ""); gsub(/\r/, "\n"); print }'` (evidence-gate wraps it as
  `normalize_newlines()` reading a file; governing-skill pipes `$CONTENT` through it).
  CRLF-only test coverage does NOT catch this — add an explicit CR-only case
  (LF→`tr '\n' '\r'`).

- **No apostrophes anywhere inside a single-quoted awk program — comments included**
  (2026-08-08, epic-16 w1). The big awk blocks (e.g. dispatch-preflight's label grammar)
  are single shell-quoted strings; an apostrophe in an awk-side comment terminates the
  shell quote and cascades into ~100 unrelated suite failures. Hit twice in one slice by
  the same agent, both times in a comment, both caught by `bash -n` before commit. Rule:
  `bash -n <hook>` after ANY edit near an awk block, and reword comments rather than
  escaping ("it's" → "it is").
