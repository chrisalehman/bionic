#!/bin/bash
# tests/roots.test.sh — payload/scripts/lib/roots.sh: one resolver per root, and the
# consumers that move when a root moves (epic-22 wave-01, REQ-N1; AC-N1.1/N1.3; ADR-003).
#
# WHAT IT OWNS. Two questions the static pin in tests/cross-gate-agreement.test.sh §Roots
# cannot answer. §Roots counts DEFINITIONS — it proves there is one `docs_root` in the tree
# and that every former carrier stopped defining its own. It cannot prove the one definition
# is right, and it cannot prove a consumer actually routes through it: a hook that dropped
# its copy and then spelled `$PROJECT/.bionic/docs` inline satisfies every count in §Roots.
# So:
#
#   §1a  the project's roots: default, override, absolute override.
#   §1b  the machine's roots.
#   §1c  config_value is the one reader, and docs_root goes through it.
#   §1d  the output contract: absolute at source time, one trailing newline.
#   §1e  docs_tracked: the project's tracked home, and where a record is promoted.
#   §2b  hooks/stop-check.sh resolves a contracted path under docs-root:.
#   §2c  the governing-skill hook scaffolds under docs-root:.
#   §2d  doctor's active-run row reads the same root.
#   §3   the promote verb copies a durable record into the tracked home.
#
# ONE CONFIG CHANGE MOVES EVERY CONSUMER (§2b to §2d). A fixture project sets `docs-root: alt`;
# lib/run.sh's plan search, doctor's active-run row, hooks/stop-check.sh's contracted
# -path resolution and hooks/canonical-sdlc-governing-skill.sh's project scaffold must
# all land under `alt/`. AC-N1.3's fails-when is "one consumer still hard-codes", and
# the mutation arm is exactly that consumer: a scratch copy of stop-check with the
# library call replaced by the literal must go red where the shipped one is green.
#
# THE LIVE DEFECT §2c FIXES. canonical-sdlc-governing-skill.sh resolved `docs-root:` into
# `$DOCS_ROOT` at the top of the file and then scaffolded `$PROJECT/.bionic/docs/{specs,
# plans,adrs,incidents}` with a literal at the bottom — so a project that set the key got the
# DEFAULT tree created and its configured tree never created, and then met that same hook's
# misplacement refusal for writing into the tree it had asked for (surfaces map §C.2).
#
# HERMETIC. Every root is a fixture directory under a mktemp sandbox; HOME and
# CLAUDE_CONFIG_DIR are redirected into it, and the hooks are driven from a PLANTED TREE
# (hooks/ beside scripts/lib/) holding this checkout's library, never from the installed
# plugin — the loader's first candidate is `$(dirname "$0")/../scripts/lib`, so a hook copied
# alone into a temp directory would heal to whatever is installed on this machine and every
# row below would be measuring that instead.
#
# Usage: bash tests/roots.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"
# THE SHARED FIXTURE BUILDERS, not hand-written shapes. `live_answer_body` composes a
# ListAgents answer out of the committed corpus (tests/lib/live-answer.sh), and
# `roster_row_fixture` writes a roster row through the production writer
# (payload/scripts/lib/roster.sh). §2b needs both because hooks/stop-check.sh resolves a
# target against the session's recorded live set and its roster row before it resolves any
# path at all — and a hand-typed answer or row is how a fixture comes to test its own
# spelling instead of the hook.
. "$(dirname "$0")/lib/live-answer.sh"
. "$BIONIC_SCRIPTS_DIR/lib/roster.sh"
. "$(dirname "$0")/lib/roster-row.sh"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
LIB_DIR="$REPO_ROOT/payload/scripts/lib"
LIB="$LIB_DIR/roots.sh"
HOOKS_SRC="$REPO_ROOT/hooks"

SANDBOX="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/roots-test.XXXXXX")" && pwd -P)"
cleanup() { rm -rf "$SANDBOX"; }
trap cleanup EXIT

export HOME="$SANDBOX/home"
export CLAUDE_CONFIG_DIR="$SANDBOX/cfg"
mkdir -p "$HOME" "$CLAUDE_CONFIG_DIR"
unset CLAUDE_CODE_SESSION_ID
unset BIONIC_CLAUDE_HOME BIONIC_PLUGIN_ROOT CLAUDE_PLUGIN_ROOT 2>/dev/null || true

# call <fn> <args...> — the library in a child shell, so no row can be answered by a
# function some earlier row left defined in this one.
call() {
  local fn="$1"; shift
  bash -c '. "$1" || exit 1; fn="$2"; shift 2; "$fn" "$@"' _ "$LIB" "$fn" "$@" 2>"$SANDBOX/.err"
}

# contains <haystack> <needle> -> yes|no. A function and not a `case` inside a command
# substitution: bash 3.2 — this file's shebang interpreter — mis-parses that shape and
# truncates the substitution at the first `)` (run-predicate R0's own note).
contains() {
  case "$1" in
    *"$2"*) printf 'yes' ;;
    *)      printf 'no'  ;;
  esac
}

# ============================================================
section "1a — the project's roots: default, override, absolute override"
# ============================================================

P="$SANDBOX/p1"; mkdir -p "$P/.bionic"

expect_eq "bionic_root is <root>/.bionic"          "$P/.bionic"      "$(call bionic_root "$P")"
expect_eq "tmp_root is <root>/.bionic/tmp"          "$P/.bionic/tmp"  "$(call tmp_root "$P")"
expect_eq "docs_root defaults to <root>/.bionic/docs" "$P/.bionic/docs" "$(call docs_root "$P")"

printf 'docs-root: alt\n' > "$P/.bionic/config.yaml"
expect_eq "docs_root: a relative docs-root: joins onto the project" "$P/alt" "$(call docs_root "$P")"

printf 'docs-root: /srv/elsewhere\n' > "$P/.bionic/config.yaml"
expect_eq "docs_root: an absolute docs-root: passes through unchanged" "/srv/elsewhere" \
  "$(call docs_root "$P")"

# THE SPELLINGS `config_value` ALREADY TOLERATES reach docs_root now, because docs_root IS a
# caller of it. Before N1 the two readers were six duplicated lines apiece, held together by
# tests/run-predicate.test.sh R9h asserting they agreed edge for edge.
printf '  docs-root:   alt2  \n' > "$P/.bionic/config.yaml"
expect_eq "docs_root: indentation and trailing space, through the one reader" \
  "$P/alt2" "$(call docs_root "$P")"
printf 'docs-root: "alt3"\n' > "$P/.bionic/config.yaml"
expect_eq "docs_root: a quoted value comes back unquoted" "$P/alt3" "$(call docs_root "$P")"
# THE SHARED WART, pinned rather than fixed. The quote strip runs BEFORE the trailing-space
# trim in `config_value`, so a quoted value with a trailing space keeps its closing quote.
# tests/run-predicate.test.sh R9h pinned exactly this on the two readers that used to exist
# separately, as the thing holding them in agreement. There is one reader now, so the wart
# is one wart — and it is pinned here too, because a future task that fixes it should have
# to come past a row that says so rather than discover it in a hook.
printf 'docs-root: "alt4" \n' > "$P/.bionic/config.yaml"
expect_eq "docs_root: a quoted value with a trailing space keeps its closing quote" \
  "$P/alt4\"" "$(call docs_root "$P")"

rm -f "$P/.bionic/config.yaml"
expect_eq "docs_root: the config file removed -> back to the default" "$P/.bionic/docs" \
  "$(call docs_root "$P")"

# --- archive_root (ADR-003 decision 2, AC-C.6) ---
expect_eq "archive_root defaults to \$HOME/bionic-archive" "$HOME/bionic-archive" \
  "$(call archive_root "$P")"
printf 'archive-root: /vol/arch\n' > "$P/.bionic/config.yaml"
expect_eq "archive_root: an absolute archive-root: stands" "/vol/arch" "$(call archive_root "$P")"
printf 'archive-root: ../arch\n' > "$P/.bionic/config.yaml"
expect_eq "archive_root: a relative one joins onto the project, docs_root's rule" \
  "$P/../arch" "$(call archive_root "$P")"
rm -f "$P/.bionic/config.yaml"

# ============================================================
section "1b — the machine's roots"
# ============================================================

expect_eq "claude_home follows CLAUDE_CONFIG_DIR" "$CLAUDE_CONFIG_DIR" "$(call claude_home)"
expect_eq "…and BIONIC_CLAUDE_HOME wins over it" "$SANDBOX/override" \
  "$(BIONIC_CLAUDE_HOME="$SANDBOX/override" call claude_home)"
expect_eq "transcripts_dir is claude_home's projects/ directory" "$CLAUDE_CONFIG_DIR/projects" \
  "$(call transcripts_dir)"
expect_eq "…and it moves with claude_home, never independently" "$SANDBOX/override/projects" \
  "$(BIONIC_CLAUDE_HOME="$SANDBOX/override" call transcripts_dir)"

expect_eq "plugin_root is the payload root two levels above the library" \
  "$(cd "$LIB_DIR/../.." && pwd -P)" "$(call plugin_root)"
expect_eq "…and BIONIC_PLUGIN_ROOT overrides it" "/opt/bionic" \
  "$(BIONIC_PLUGIN_ROOT=/opt/bionic call plugin_root)"
expect_eq "…and CLAUDE_PLUGIN_ROOT does too" "/opt/from-cli" \
  "$(CLAUDE_PLUGIN_ROOT=/opt/from-cli call plugin_root)"

# --- worktree_root: the answer that made three resolvers exist ---
GITP="$SANDBOX/gitp"
mkdir -p "$GITP"
( cd "$GITP" && git init -q . && git config user.email t@t && git config user.name t \
  && printf 'x\n' > f && git add f && git commit -qm init ) >/dev/null 2>&1
expect_eq "worktree_root in the main checkout is the main checkout" "$(cd "$GITP" && pwd -P)" \
  "$(call worktree_root "$GITP")"
( cd "$GITP" && git worktree add -q -b wtb "$GITP/.wt/one" HEAD ) >/dev/null 2>&1
expect_eq "worktree_root from INSIDE a linked worktree is still the main checkout" \
  "$(cd "$GITP" && pwd -P)" "$(call worktree_root "$GITP/.wt/one")"
# THE PAIRED NEGATIVE: --show-toplevel, asked in the same place, answers with the LINKED
# tree. That difference is the whole reason three resolvers existed for this question, and
# without this row the assertion above could be green against a resolver that just called
# --show-toplevel in a repository that happened to have no worktree.
expect_ne "…which is exactly what --show-toplevel answers differently" \
  "$(cd "$GITP" && pwd -P)" "$(cd "$GITP/.wt/one" && git rev-parse --show-toplevel)"
expect_eq "worktree_root outside a repository exits non-zero" "1" \
  "$(call worktree_root "$SANDBOX/home" >/dev/null 2>&1; echo $?)"

# ============================================================
section "1d — the output contract: absolute at source time, one trailing newline"
# ============================================================
#
# TWO STEP-6 REVIEW FINDINGS, both about the SHAPE of an answer rather than its value.
#
# C-3: `plugin_root`'s fallback resolved its self-locator at CALL time, so a caller that
# sourced the library by a relative path and then `cd`-ed away got `/` — a root, silently
# wrong, in the fail-dangerous direction. The four sibling libraries (refuse.sh, patrol.sh,
# worktree.sh, detect.sh) all resolve theirs at SOURCE time; this pins that roots.sh does
# too. Not reachable through today's callers — every one sources absolutely — which is
# exactly why it needs a pin rather than a caller.
#
# R-2: the resolvers disagreed about the trailing newline. Harmless under `$( )`, which
# strips it, and therefore invisible to every other row in this file — so a caller that
# ever reads a resolver WITHOUT command substitution gets a different shape per resolver.
# One rule, `printf '%s\n'`, and this section is what holds it.

# THE RELATIVE-SOURCE DRIVE. `cd` into the library's own directory, source `./roots.sh`,
# leave, and ask. The expected answer is the same payload root §1b already pins for the
# absolute-source case — the point is that the two agree.
expect_eq "plugin_root survives a relative source followed by a cd" \
  "$(cd "$LIB_DIR/../.." && pwd -P)" \
  "$( /bin/bash -c 'unset BIONIC_PLUGIN_ROOT CLAUDE_PLUGIN_ROOT
                    cd "$1" || exit 1
                    . ./roots.sh || exit 1
                    cd / || exit 1
                    plugin_root' _ "$LIB_DIR" 2>/dev/null )"

# THE PAIRED NEGATIVE, so the row above cannot pass on a resolver that ignores its
# self-locator entirely: the same drive against a COPY of the library two directories
# deeper answers with that copy's payload root, not with the shipped one.
DEEP="$SANDBOX/deep/payload/scripts/lib"
mkdir -p "$DEEP"
cp "$LIB_DIR/roots.sh" "$LIB_DIR/root.sh" "$DEEP/"
expect_eq "…and it is genuinely the SOURCED file's location, not a constant" \
  "$SANDBOX/deep/payload" \
  "$( /bin/bash -c 'unset BIONIC_PLUGIN_ROOT CLAUDE_PLUGIN_ROOT
                    cd "$1" || exit 1
                    . ./roots.sh || exit 1
                    cd / || exit 1
                    plugin_root' _ "$DEEP" 2>/dev/null )"

# trailing_nl <fn> <args...> -> yes|no. NOT `$( )` anywhere near the resolver's own
# output: command substitution strips the very byte under test, which is why no existing
# row in this file could have caught R-2.
trailing_nl() {
  local fn="$1"; shift
  bash -c '. "$1" || exit 1; fn="$2"; shift 2; "$fn" "$@"' _ "$LIB" "$fn" "$@" \
    >"$SANDBOX/.nl" 2>/dev/null
  if [ ! -s "$SANDBOX/.nl" ]; then printf 'empty'; return 0; fi
  case "$(tail -c 1 "$SANDBOX/.nl" | od -An -tu1 | tr -d ' ')" in
    10) printf 'yes' ;;
    *)  printf 'no'  ;;
  esac
}

NLP="$SANDBOX/nlproj"; mkdir -p "$NLP/.bionic"
expect_eq "bionic_root ends with one newline"     "yes" "$(trailing_nl bionic_root "$NLP")"
expect_eq "docs_root ends with one newline"       "yes" "$(trailing_nl docs_root "$NLP")"
expect_eq "tmp_root ends with one newline"        "yes" "$(trailing_nl tmp_root "$NLP")"
expect_eq "archive_root ends with one newline"    "yes" "$(trailing_nl archive_root "$NLP")"
expect_eq "config_value ends with one newline"    "yes" "$(trailing_nl config_value "$NLP" nope dflt)"
expect_eq "claude_home ends with one newline"     "yes" "$(trailing_nl claude_home)"
expect_eq "transcripts_dir ends with one newline" "yes" "$(trailing_nl transcripts_dir)"
expect_eq "plugin_root ends with one newline"     "yes" "$(trailing_nl plugin_root)"

# THE OVERRIDE PATHS TOO — plugin_root had three exits and R-2 named all three.
expect_eq "…with BIONIC_PLUGIN_ROOT set" "yes" \
  "$(BIONIC_PLUGIN_ROOT=/opt/bionic trailing_nl plugin_root)"
expect_eq "…with CLAUDE_PLUGIN_ROOT set" "yes" \
  "$(CLAUDE_PLUGIN_ROOT=/opt/from-cli trailing_nl plugin_root)"

# AND THE VALUES ARE UNCHANGED BY THE NEWLINE RULE. Every caller reads through `$( )`,
# so this is the row that says so out loud rather than assuming it.
expect_eq "claude_home's VALUE is untouched by the newline rule" "$CLAUDE_CONFIG_DIR" \
  "$(call claude_home)"
expect_eq "…and transcripts_dir's" "$CLAUDE_CONFIG_DIR/projects" "$(call transcripts_dir)"

# ============================================================
section "1c — config_value is the one reader, and docs_root goes through it"
# ============================================================
#
# tests/run-predicate.test.sh §R9 owns config_value's twelve behaviours and still does — it
# sources lib/run.sh, which soft-sources this file. What is asserted here is the property
# that made the move worth taking: docs-root: is read by the general reader now, so a fix to
# one is a fix to both, and there is no pair left to hold in agreement.

C="$SANDBOX/cfgroot"; mkdir -p "$C/.bionic"
printf 'docs-root: dd\nlive-window: 30d\n' > "$C/.bionic/config.yaml"
expect_eq "config_value reads docs-root: itself" "dd" "$(call config_value "$C" docs-root "")"
expect_eq "…and docs_root returns exactly that, joined" "$C/dd" "$(call docs_root "$C")"
expect_eq "…and another key from the same file" "30d" "$(call config_value "$C" live-window 7d)"
expect_eq "config_value: a missing key is the default" "7d" "$(call config_value "$C" nope 7d)"

# ============================================================
section "1e — docs_tracked: the project's tracked home, and where a record is promoted"
# ============================================================
#
# A durable record belongs to the project, so its tracked home is a project folder named by
# `docs-tracked:`, `docs/` when the key is absent. promote_target answers where a record of a
# kind lands there, and refuses anything operational: a plan, a log, a run's record, or a
# home that resolves under the state directory.

T="$SANDBOX/tracked"; mkdir -p "$T/.bionic"
expect_eq "docs_tracked defaults to <root>/docs" "$T/docs" "$(call docs_tracked "$T")"
printf 'docs-tracked: handbook\n' > "$T/.bionic/config.yaml"
expect_eq "docs_tracked: a relative docs-tracked: joins onto the project" "$T/handbook" \
  "$(call docs_tracked "$T")"
rm -f "$T/.bionic/config.yaml"

TS="$T/.bionic/docs"
expect_eq "promote_target: an ADR lands under adrs/ with its own name" \
  "$T/docs/adrs/adr-007-one-door.md" \
  "$(call promote_target "$T" adr "$TS/adrs/epic-99/adr-007-one-door.md")"
expect_eq "promote_target: a design's name drops its run-number prefix" \
  "$T/docs/designs/tidy.spec.md" \
  "$(call promote_target "$T" design "$TS/specs/epic-99/wave-03-tidy.spec.md")"
expect_eq "promote_target: a requirement lands under requirements/" \
  "$T/docs/requirements/tidy.requirements.md" \
  "$(call promote_target "$T" requirement "$TS/specs/epic-99/wave-03-tidy.requirements.md")"

expect_eq "promote_target: the kind plan is refused, and names no target" "1|" \
  "$(out="$(call promote_target "$T" plan "$TS/plans/epic-99/wave-03-tidy.plan.md")"; echo "$?|$out")"
expect_eq "promote_target: a plan file under a durable kind is refused" "1|" \
  "$(out="$(call promote_target "$T" design "$TS/plans/epic-99/wave-03-tidy.plan.md")"; echo "$?|$out")"
expect_eq "promote_target: a log is refused" "1|" \
  "$(out="$(call promote_target "$T" design "$T/build.log")"; echo "$?|$out")"
expect_eq "promote_target: a run's record, a handoff among them, is refused" "1|" \
  "$(out="$(call promote_target "$T" design "$TS/record/handoffs/2026-01-01-x.md")"; echo "$?|$out")"
expect_eq "promote_target: an ADR's kind holds ADRs only" "1|" \
  "$(out="$(call promote_target "$T" adr "$TS/specs/epic-99/wave-03-tidy.spec.md")"; echo "$?|$out")"

printf 'docs-tracked: .bionic/kept\n' > "$T/.bionic/config.yaml"
expect_eq "promote_target: a tracked home under .bionic/ is refused" "1|" \
  "$(out="$(call promote_target "$T" adr "$TS/adrs/epic-99/adr-007-one-door.md")"; echo "$?|$out")"
rm -f "$T/.bionic/config.yaml"

# ============================================================
setup_section "2 — one config change moves EVERY consumer (AC-N1.3)"
# ============================================================
#
# THE PLANTED TREE. hooks/ beside scripts/lib/, holding this checkout's library, because the
# loader's first candidate is `$(dirname "$0")/../scripts/lib` — see the header.

PLANT="$SANDBOX/plant"
mkdir -p "$PLANT/hooks" "$PLANT/scripts/lib"
cp "$HOOKS_SRC"/*.sh "$PLANT/hooks/" 2>/dev/null
cp "$HOOKS_SRC"/hooks.json "$PLANT/hooks/" 2>/dev/null
cp "$LIB_DIR"/*.sh "$PLANT/scripts/lib/" 2>/dev/null

# THE FIXTURE PROJECT. `docs-root: alt`, and every artifact under `alt/` rather than under
# `.bionic/docs/`. A consumer that hard-codes the default finds an empty tree.
PROJ="$SANDBOX/proj"
mkdir -p "$PROJ/.bionic/tmp" "$PROJ/alt/plans/epic-99" "$PROJ/alt/record"
printf 'docs-root: alt\n' > "$PROJ/.bionic/config.yaml"
cat > "$PROJ/alt/plans/epic-99/wave-01.plan.md" <<'PLAN'
---
canonical_sdlc_version: 14
intent: build
rigor: double
scale: wave
---

# Wave 01

## SDLC State

current: 4

- Step 0: confirmed
PLAN
printf 'progress\n' > "$PROJ/alt/record/s99.md"

# THE OBSERVING SESSION, for §2b. hooks/stop-check.sh resolves a typed target against the
# newest recorded ListAgents answer in that session's transcript, then against the roster
# row carrying the agent id. Only after both does it resolve the contracted path — so
# without these two the row below would measure the resolution refusal, not the root.
PROJ_SID="rootssid1"
PROJ_SLUG="$(printf '%s' "$PROJ" | sed 's/[^a-zA-Z0-9]/-/g')"
mkdir -p "$CLAUDE_CONFIG_DIR/projects/$PROJ_SLUG"
{
  jq -nc --arg ts "2026-09-05T00:50:00.000Z" \
    '{type:"user",timestamp:$ts,message:{role:"user",content:"go"}}'
  jq -nc --arg ts "2026-09-05T00:51:00.000Z" \
    '{type:"assistant",timestamp:$ts,message:{role:"assistant",content:[{type:"tool_use",id:"toolu_01FIXTURELISTAGENTS",name:"ListAgents",input:{}}]}}'
  jq -nc --arg ts "2026-09-05T00:52:23.349Z" --arg b "$(live_answer_body some-agent)" \
    '{type:"user",timestamp:$ts,message:{role:"user",content:[{type:"tool_result",tool_use_id:"toolu_01FIXTURELISTAGENTS",content:$b}]}}'
} > "$CLAUDE_CONFIG_DIR/projects/$PROJ_SLUG/$PROJ_SID.jsonl"
roster_row_fixture status=identified session="$PROJ_SID" name=some-agent \
  agent_id=a0000001 deliverable=record/s99.md > "$PROJ/.bionic/tmp/roster-$PROJ_SID.state"

# The same artifacts under the DEFAULT root, holding different content, so a hard-coding
# consumer is not merely wrong-and-empty but demonstrably reading the other tree.
mkdir -p "$PROJ/.bionic/docs/plans/epic-00"
cat > "$PROJ/.bionic/docs/plans/epic-00/decoy.plan.md" <<'PLAN'
---
canonical_sdlc_version: 14
---

## SDLC State

current: 4
PLAN

expect_eq "fixture: the planted tree carries the library" "yes" \
  "$([ -r "$PLANT/scripts/lib/roots.sh" ] && echo yes || echo no)"
expect_eq "fixture: the project's docs root resolves to alt/" "$PROJ/alt" \
  "$(call docs_root "$PROJ")"

# ============================================================
section "2b — hooks/stop-check.sh resolves a contracted path under docs-root:"
# ============================================================
#
# `record/`-led paths are docs-root-relative — the rule this whole lineage exists for, and
# the one stop-check got wrong before epic-17 W6 S15: it stat'd a relative path against
# whatever directory the observer stood in, so a landed deliverable read ABSENT.
#
# THE OBSERVABLE IS PRESENT vs ABSENT, not a path in the prose. The command prints the
# deliverable under the spelling the contract used (`record/s99.md`) and never the resolved
# absolute, so the honest reading of "which root did it resolve against" is whether it
# FOUND the file — and the file exists under `alt/` and nowhere else. The machine line at
# the end of the output is what other bionic readers parse, so it is what is read here.

SC_OUT="$( cd "$PROJ" && CLAUDE_CODE_SESSION_ID="$PROJ_SID" \
  bash "$PLANT/hooks/stop-check.sh" some-agent record/s99.md 2>&1 )"
expect_eq "stop-check found record/s99.md, which exists only under alt/" "yes" \
  "$(contains "$SC_OUT" "deliverables=present:record/s99.md")"
expect_eq "…so it did not resolve against the default root, where nothing is" "no" \
  "$(contains "$SC_OUT" "deliverables=absent:record/s99.md")"

# --- THE FAILS-WHEN ARM (AC-N1.3: "one consumer still hard-codes"). A scratch copy of the
# hook with the library call replaced by the literal the four retired copies used to spell.
# The shipped file is never touched; the mutant is a copy in the sandbox. Without this row
# the two above prove only that the hook currently agrees, not that a hard-coding one would
# be visible here. ---
SC_MUT_DIR="$SANDBOX/stopcheck-mutant"
mkdir -p "$SC_MUT_DIR/hooks" "$SC_MUT_DIR/scripts/lib"
cp "$PLANT/scripts/lib"/*.sh "$SC_MUT_DIR/scripts/lib/"
anchor file hooks/stop-check.sh 'DOCS_ROOT="$(docs_root "$PROJECT_DIR")"'
sed 's|DOCS_ROOT="$(docs_root "$PROJECT_DIR")"|DOCS_ROOT="$PROJECT_DIR/.bionic/docs"|' \
  "$PLANT/hooks/stop-check.sh" > "$SC_MUT_DIR/hooks/stop-check.sh"
expect_eq "the mutant really differs from the shipped hook (the sed landed)" "no" \
  "$(cmp -s "$PLANT/hooks/stop-check.sh" "$SC_MUT_DIR/hooks/stop-check.sh" && echo yes || echo no)"

SC_MUT_OUT="$( cd "$PROJ" && CLAUDE_CODE_SESSION_ID="$PROJ_SID" \
  bash "$SC_MUT_DIR/hooks/stop-check.sh" some-agent record/s99.md 2>&1 )"
expect_eq "…and a hard-coding stop-check reports the SAME deliverable ABSENT" "yes" \
  "$(contains "$SC_MUT_OUT" "deliverables=absent:record/s99.md")"
expect_eq "…so the two rows above do discriminate" "no" \
  "$(contains "$SC_MUT_OUT" "deliverables=present:record/s99.md")"

# ============================================================
section "2c — the governing-skill hook SCAFFOLDS under docs-root: (the live defect)"
# ============================================================
#
# The hook resolved `docs-root:` at the top and then scaffolded a literal at the bottom, so
# a project with the key set got the default tree created and its configured tree never
# created — and then met this same hook's misplacement refusal for writing where it had
# asked to write. Both directions are asserted: the configured tree appears, and no default
# tree is created beside it.
#
# THE PAYLOAD IS A COMPLETE ONE. The scaffold runs at the hook's single `exit 0`, past every
# gate — deliberately, so a Write this hook REFUSES leaves no tree behind — so a fixture
# missing one frontmatter flag proves nothing about the scaffold. The session id is pinned
# in the environment as well as the payload because `session_id` prefers the environment,
# and an unpinned call would engage against the id of whatever session is running the suite.
# IT ALSO OPENS WITH `## Goal`, for the same reason: K5.4 (wave-01 task 21) made that the
# first section every canonical-sdlc artifact carries, and content without it meets this
# hook's own write refusal before the scaffold at `exit 0` is ever reached.

gs_payload() {  # <cwd> <file_path> -> a complete PreToolUse Write payload on stdout
  jq -nc --arg cwd "$1" --arg fp "$2" --arg c "$GS_CONTENT" \
    '{session_id:"rootssid2",hook_event_name:"PreToolUse",cwd:$cwd,tool_name:"Write",
      tool_input:{file_path:$fp,content:$c}}'
}

GS_CONTENT='---
canonical_sdlc_version: 14
governing-skill: agent-skills:spec-driven-development
sdlc-step: 1
intent: build
rigor: double
scale: wave
surface_type: cli-plugin
language: bash
has_ui: false
multi_agent: false
deploy_target: n/a
cleanup_on_finish: true
use_worktree: false
model_plan: orchestrator=claude-fable-5-1
---

# Spec

## Goal

One resolver per root, so every hook and script reads the same docs tree.

## Design

One resolver per root; every former copy calls it.
'

GS_PROJ="$SANDBOX/gsproj"
mkdir -p "$GS_PROJ/.bionic/tmp" "$GS_PROJ/alt/specs/epic-99"
printf 'docs-root: alt\n' > "$GS_PROJ/.bionic/config.yaml"
touch "$GS_PROJ/.bionic/tmp/engaged-rootssid2.state"

GS_OUT="$( cd "$GS_PROJ" && CLAUDE_CODE_SESSION_ID=rootssid2 \
  bash "$PLANT/hooks/canonical-sdlc-governing-skill.sh" \
    < <(gs_payload "$GS_PROJ" "$GS_PROJ/alt/specs/epic-99/w.spec.md") 2>&1 )"; GS_ST=$?

expect_eq "the governing-skill hook allowed the fixture write (the scaffold runs at exit 0)" \
  "0" "$GS_ST"
expect_eq "…with nothing on the refusal channel (a refused write scaffolds nothing)" "" "$GS_OUT"
for _leader in specs plans adrs incidents; do
  expect_eq "…scaffolded alt/$_leader, the CONFIGURED tree" "yes" \
    "$([ -d "$GS_PROJ/alt/$_leader" ] && echo yes || echo no)"
done
expect_eq "…and created no .bionic/docs tree the project never asked for" "no" \
  "$([ -d "$GS_PROJ/.bionic/docs" ] && echo yes || echo no)"
expect_eq "…while the two state paths are still the project's own, not the docs root's" "yes" \
  "$([ -d "$GS_PROJ/.bionic/tmp" ] && [ -f "$GS_PROJ/.bionic/.gitignore" ] && echo yes || echo no)"

# THE OTHER DIRECTION, and the one a fix could break: a project WITHOUT the key still gets
# `.bionic/docs`. `alt/plans` proves the value moved; this proves it moved because of the
# config and not because the literal was simply swapped for another literal.
GS_DEF="$SANDBOX/gsdefault"
mkdir -p "$GS_DEF/.bionic/tmp" "$GS_DEF/.bionic/docs/specs/epic-99"
touch "$GS_DEF/.bionic/tmp/engaged-rootssid2.state"
( cd "$GS_DEF" && CLAUDE_CODE_SESSION_ID=rootssid2 \
  bash "$PLANT/hooks/canonical-sdlc-governing-skill.sh" \
    < <(gs_payload "$GS_DEF" "$GS_DEF/.bionic/docs/specs/epic-99/w.spec.md") ) >/dev/null 2>&1
for _leader in specs plans adrs incidents; do
  expect_eq "no docs-root: set -> .bionic/docs/$_leader, exactly as before" "yes" \
    "$([ -d "$GS_DEF/.bionic/docs/$_leader" ] && echo yes || echo no)"
done
expect_eq "…and no stray alt/ tree in a project that never named one" "no" \
  "$([ -d "$GS_DEF/alt" ] && echo yes || echo no)"

# ============================================================
section "2d — doctor's active-run row reads the same root"
# ============================================================
#
# Doctor is the third consumer AC-N1.3 names, and it reaches the docs root transitively:
# `active_run` -> `active_plan` -> `docs_root`. A doctor that resolved its own way would
# report "none" on a project whose walls are armed, which is the exact class of disagreement
# this library exists to end.

DOC_OUT="$( cd "$PROJ" && bash "$REPO_ROOT/payload/scripts/doctor.sh" 2>&1 )"
expect_eq "doctor's active-run row names the plan under alt/" "yes" \
  "$(contains "$DOC_OUT" "alt/plans/epic-99/wave-01.plan.md")"
expect_eq "…and not the decoy under the default root" "no" "$(contains "$DOC_OUT" "decoy.plan.md")"

# ============================================================
section "3 — the promote verb copies a durable record into the tracked home"
# ============================================================
#
# The verb is driven from the planted tree with its parts beside it, in a project whose
# records sit in their default places. What is proved is the file on disk: it is in the
# tracked home, byte for byte the record, and a second promotion of an edited record lands at
# the same path.

mkdir -p "$PLANT/hooks/poker"
cp "$HOOKS_SRC"/poker/*.sh "$PLANT/hooks/poker/" 2>/dev/null
PR="$SANDBOX/promote"
PRD="$PR/.bionic/docs"
mkdir -p "$PRD/adrs/epic-99" "$PRD/specs/epic-99" "$PRD/plans/epic-99"
printf '# ADR-007 — One door\n' > "$PRD/adrs/epic-99/adr-007-one-door.md"
printf '# Tidy, the design\n' > "$PRD/specs/epic-99/wave-03-tidy.spec.md"
printf '# Tidy, the requirements\n' > "$PRD/specs/epic-99/wave-03-tidy.requirements.md"
printf '# Tidy, the plan\n' > "$PRD/plans/epic-99/wave-03-tidy.plan.md"
git -C "$PR" init -q 2>/dev/null

promote() { ( cd "$PR" && bash "$PLANT/hooks/session-poker.sh" promote "$@" ) >"$SANDBOX/.promote.out" 2>&1; }
tracked_list() { ( cd "$PR" && find docs -type f 2>/dev/null | sort | tr '\n' ' ' ); }

promote adr .bionic/docs/adrs/epic-99/adr-007-one-door.md
expect_status "promote adr: exits 0" 0 "$?"
expect_eq "…and the tracked copy is the record, byte for byte" "yes" \
  "$(cmp -s "$PRD/adrs/epic-99/adr-007-one-door.md" "$PR/docs/adrs/adr-007-one-door.md" && echo yes || echo no)"
promote design .bionic/docs/specs/epic-99/wave-03-tidy.spec.md
expect_status "promote design: exits 0" 0 "$?"
promote requirement "$PRD/specs/epic-99/wave-03-tidy.requirements.md"
expect_status "promote requirement, by absolute path: exits 0" 0 "$?"
expect_eq "the tracked home holds the three records, under their kinds" \
  "docs/adrs/adr-007-one-door.md docs/designs/tidy.spec.md docs/requirements/tidy.requirements.md " \
  "$(tracked_list)"

printf '# ADR-007 — One door, amended\n' > "$PRD/adrs/epic-99/adr-007-one-door.md"
promote adr .bionic/docs/adrs/epic-99/adr-007-one-door.md
expect_eq "an edited record promoted again lands at the same path, refreshed" "yes" \
  "$(cmp -s "$PRD/adrs/epic-99/adr-007-one-door.md" "$PR/docs/adrs/adr-007-one-door.md" && echo yes || echo no)"

BEFORE="$(tracked_list)"
promote plan .bionic/docs/plans/epic-99/wave-03-tidy.plan.md
expect_status "promote plan: refused, exit 1" 1 "$?"
expect_eq "…and the tracked home is as it was" "$BEFORE" "$(tracked_list)"

# ============================================================
section "PROMOTE-TREE — promote writes where it runs"
# ============================================================
#
# The record lives in the state home, which a linked worktree shares through its .bionic link;
# the copy belongs to the checkout the verb runs in. The source is read against the state home
# and the target is written under the running checkout's top level.

mkdir -p "$PR/.worktrees"
printf 'fixture\n' > "$PR/README"
git -C "$PR" add README
git -C "$PR" -c user.name=t -c user.email=t@t commit -q -m fixture
git -C "$PR" worktree add -q "$PR/.worktrees/wt-1" -b wt-1
ln -s "$PR/.bionic" "$PR/.worktrees/wt-1/.bionic"
WT="$(cd "$PR/.worktrees/wt-1" && pwd -P)"
printf '# ADR-008 — Two doors\n' > "$PRD/adrs/epic-99/adr-008-two-doors.md"
promote_in() { local d="$1"; shift; ( cd "$d" && bash "$PLANT/hooks/session-poker.sh" promote "$@" ) >"$SANDBOX/.promote.out" 2>&1; }

# Fails when the verb resolves its target through the state home, so the copy lands in the main
# checkout and the worktree holds none.
promote_in "$WT" adr .bionic/docs/adrs/epic-99/adr-008-two-doors.md
expect_status "AC-4.1: promote from the worktree exits 0" 0 "$?"
expect_eq "AC-4.1: the copy is in the worktree's tracked home, byte for byte" "yes" \
  "$(cmp -s "$PRD/adrs/epic-99/adr-008-two-doors.md" "$WT/docs/adrs/adr-008-two-doors.md" && echo yes || echo no)"
expect_eq "AC-4.1: …and the main checkout's tracked home holds nothing of it" "no" \
  "$([ -e "$PR/docs/adrs/adr-008-two-doors.md" ] && echo yes || echo no)"
# Fails when the success line names no tree, so a reader cannot tell where the copy went.
expect_eq "AC-4.1: the success line names the worktree" "yes" \
  "$(contains "$(cat "$SANDBOX/.promote.out")" "in $WT.")"

# Fails when a docs-root-relative source is read against the worktree's top and refused as no file.
promote_in "$WT" adr adrs/epic-99/adr-008-two-doors.md
expect_status "AC-4.3: a docs-root-relative source from the worktree exits 0" 0 "$?"
expect_eq "AC-4.3: …and the copy still holds the record" "yes" \
  "$(cmp -s "$PRD/adrs/epic-99/adr-008-two-doors.md" "$WT/docs/adrs/adr-008-two-doors.md" && echo yes || echo no)"

# Fails when the main-checkout promotion is refused or lands elsewhere.
promote_in "$PR" adr .bionic/docs/adrs/epic-99/adr-008-two-doors.md
expect_status "AC-4.2: promote from the main checkout exits 0" 0 "$?"
expect_eq "AC-4.2: …and the copy lands in the main checkout's tracked home" "yes" \
  "$(cmp -s "$PRD/adrs/epic-99/adr-008-two-doors.md" "$PR/docs/adrs/adr-008-two-doors.md" && echo yes || echo no)"
# Fails when the success line gains a tree clause where the running checkout is the state home.
expect_eq "AC-4.2: …and its success line has no tree clause" "no" \
  "$(contains "$(cat "$SANDBOX/.promote.out")" " in $PR.")"

finish
