#!/bin/bash
# tests/run-predicate.test.sh — payload/scripts/lib/run.sh: docs_root, active_plan,
# active_run (L-RUN, wave-bionic-1.4.0-update, spec AC-8; plan design-ledger S1) and the
# session-bound readers run_open / open_runs / session_plan / session_run
# (wave-session-bound-run S1, 2026-09-04; spec AC-1, AC-3, AC-6).
#
# WHAT IT OWNS. The "is there a run to protect" predicate: active_run <root> is exit 0 +
# the plan path iff the newest plan (by mtime) under the docs root's plans/incidents trees
# carries a flush-left `## SDLC State` and an open state — `current:` 0-8, or 9 without a
# `- Step 9:` line carrying `delivered:`, or the retired task-scale `current: T<n>`, kept open so
# its readers refuse it by name (wave-31 T24; REQ-1 AC-1.2, D2) — and the plan's frontmatter
# carries no `abandoned:` line; else exit 1 and prints nothing. Every always-on
# hook gates its own work behind this one call (ADOPT, Batch 1).
#
# AND, SINCE wave-session-bound-run, WHICH run answers for WHICH SESSION. `active_run` is
# root-keyed: two engaged sessions in one repository share its answer, which is the bug that
# wave exists to fix. R5-R8 below own the four readers that key the same question to a
# session — the verdict on one file (R5), the SET of open runs in a root (R6), the marker's
# `plan=` binding (R7), and the verdict a hook acts on (R8) — and R5's agreement rows hold
# `active_run` to being exactly `active_plan` + `run_open`, so the extraction stays lossless.
#
# FIXTURES mirror the plan's own SDLC State block shape (wave.plan.md's frontmatter and
# Step lines). The plan-search shape referenced for context is
# hooks/canonical-sdlc-evidence-gate.sh's resolve_docs_root/current-parsing — read for
# shape only, not copied: this library's interface is the simpler, single-purpose one the
# plan states (no fence-awareness, no misplacement sweep), not a restatement of the gate's
# richer parser.
#
# HERMETIC. Every plan is a fixture file under a mktemp sandbox; nothing reads a real
# .bionic tree or a live wave.
#
# Usage: bash tests/run-predicate.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/plan-fixture.sh"
. "$(dirname "$0")/lib/assert.sh"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
LIB="$REPO_ROOT/payload/scripts/lib/run.sh"

SANDBOX="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/run-predicate-test.XXXXXX")" && pwd -P)"
cleanup() { chmod -R u+rwx "$SANDBOX" 2>/dev/null; rm -rf "$SANDBOX"; }
trap cleanup EXIT

# SUBSTRING, AS A FUNCTION. Nine rows below asked this with a one-line `case` inside a
# command substitution. Under bash 3.2 — what `/bin/bash` is on macOS, and what this
# file's own shebang names — that shape PARSES and then truncates the substitution at the
# first `)` at run time, so the assertion compared against the tail of its own source text
# instead of an answer. `bash -n` cannot see it; tests/cross-gate-agreement.test.sh §BP
# greps for it. Step-6 review C-2.
rp_contains() {  # <haystack> <needle> -> yes|no
  case "$1" in
    *"$2"*) printf 'yes' ;;
    *)      printf 'no'  ;;
  esac
}

# ============================================================
section "R0 — the library exists and parses"
# ============================================================
if [ -f "$LIB" ]; then ok "payload/scripts/lib/run.sh is on disk"; else
  no "payload/scripts/lib/run.sh is on disk" "$LIB"
fi
if bash -n "$LIB" 2>"$SANDBOX/.syn"; then ok "the library parses (bash -n)"; else
  no "the library parses (bash -n)" "$(cat "$SANDBOX/.syn")"
fi

# Sourcing prints nothing (plan: "Functions only; sourcing prints nothing.")
SRC_OUT=$(bash -c '. "$1" 2>&1' _ "$LIB")
expect_empty "sourcing the library prints nothing" "$SRC_OUT"

# ---- driven through a child bash that sources the library ----
call_docs_root() {  # <root> -> stdout
  bash -c '. "$1" || exit 1; docs_root "$2"' _ "$LIB" "$1" 2>"$SANDBOX/.err"
}
AR_OUT=""; AR_ST=0
call_active_run() {  # <root> -> sets AR_OUT, AR_ST
  AR_OUT=$(bash -c '. "$1" || exit 1; active_run "$2"' _ "$LIB" "$1" 2>"$SANDBOX/.err")
  AR_ST=$?
}
# call_active_run_pf <root> -> sets AR_OUT, AR_ST, from a child bash with `set -uo
# pipefail` ENABLED IN THAT CHILD. `set -o` options are shell-local, not inherited by a
# nested `bash -c` merely because the parent process has them set (verified: SHELLOPTS
# does not carry pipefail across this bash's own `bash -c` boundary on this machine) — so
# call_active_run above, run under this suite's own top-of-file `set -uo pipefail`,
# NEVER actually exercises active_run under pipefail; every hook that calls this library
# sources it directly in ITS OWN shell, where its own `set -uo pipefail` (dispatch-preflight
# .sh:66 et al.) is genuinely in effect. This helper re-states the option inside the child
# so the R4 fixtures below test the real production condition, not an inherited illusion
# of it (AC-21).
call_active_run_pf() {
  AR_OUT=$(bash -c 'set -uo pipefail; . "$1" || exit 1; active_run "$2"' _ "$LIB" "$1" 2>"$SANDBOX/.err")
  AR_ST=$?
}
AP_OUT=""; AP_ST=0
call_active_plan() {  # <root> -> sets AP_OUT, AP_ST
  AP_OUT=$(bash -c '. "$1" || exit 1; active_plan "$2"' _ "$LIB" "$1" 2>"$SANDBOX/.err")
  AP_ST=$?
}

# ============================================================
section "R1 — docs_root: default and .bionic/config.yaml override"
# ============================================================
ROOT1="$SANDBOX/r1"
mkdir -p "$ROOT1/.bionic"
expect_eq "docs_root defaults to <root>/.bionic/docs" "$ROOT1/.bionic/docs" "$(call_docs_root "$ROOT1")"

printf 'docs-root: .bionic/other-docs\n' > "$ROOT1/.bionic/config.yaml"
expect_eq "docs_root honours a relative docs-root: override" \
  "$ROOT1/.bionic/other-docs" "$(call_docs_root "$ROOT1")"

printf 'docs-root: /elsewhere/docs\n' > "$ROOT1/.bionic/config.yaml"
expect_eq "docs_root honours an absolute docs-root: override" \
  "/elsewhere/docs" "$(call_docs_root "$ROOT1")"
rm -f "$ROOT1/.bionic/config.yaml"

# ============================================================
section "R2 — active_plan / active_run fixtures"
# ============================================================
# mk_plan_in <root> <reldir under the docs root> <name> <current-line-body> [extra-lines...]
# The general form: mk_plan below is its plans/ special case. R6 needs `incidents/` and
# `plans/<epic>/` fixtures to show that open_runs walks the same two trees to the same
# depth as active_plan.
mk_plan_in() {
  local root="$1" rel="$2" name="$3" current="$4"
  shift 4
  local dir; dir="$root/.bionic/docs/$rel"
  mkdir -p "$dir"
  {
    echo "---"
    echo "governing-skill: superpowers:writing-plans"
    echo "sdlc-step: 3"
    echo "---"
    echo
    echo "# fixture plan"
    echo
    echo "## SDLC State"
    echo
    echo "integration-branch: main"
    echo "current: $current"
    for l in "$@"; do echo "$l"; done
  } > "$dir/$name"
  printf '%s/%s\n' "$dir" "$name"
}

# mk_plan <root> <name under docs/plans> <current-line-body> [extra-lines...]
# Writes a plan with the plan's own frontmatter/SDLC-State shape (wave.plan.md), prints
# its absolute path.
mk_plan() {
  local root="$1" name="$2" current="$3"
  shift 3
  mk_plan_in "$root" "plans" "$name" "$current" "$@"
}

# --- current 4 -> active ---
R="$SANDBOX/r2a"; mkdir -p "$R/.bionic"
P=$(mk_plan "$R" "wave.plan.md" "4" "- Step 4: in progress")
call_active_run "$R"
expect_eq "current: 4 -> active_run exits 0" 0 "$AR_ST"
expect_eq "current: 4 -> active_run prints the plan path" "$P" "$AR_OUT"

# --- current 9 without a delivered Step 9 line -> active ---
R="$SANDBOX/r2b"; mkdir -p "$R/.bionic"
P=$(mk_plan "$R" "wave.plan.md" "9" "- Step 9: report drafted, not yet delivered")
call_active_run "$R"
expect_eq "current: 9 without 'delivered:' -> active_run exits 0" 0 "$AR_ST"
expect_eq "current: 9 without 'delivered:' -> prints the plan path" "$P" "$AR_OUT"

# --- current 9 WITH a delivered Step 9 line -> inactive ---
R="$SANDBOX/r2c"; mkdir -p "$R/.bionic"
mk_plan "$R" "wave.plan.md" "9" "- Step 9: report record/x.md, delivered: 2026-09-02" >/dev/null
call_active_run "$R"
expect_eq "current: 9 with 'delivered:' -> active_run exits 1" 1 "$AR_ST"
expect_empty "current: 9 with 'delivered:' -> prints nothing" "$AR_OUT"

# --- frontmatter abandoned: line -> inactive ---
R="$SANDBOX/r2d"; mkdir -p "$R/.bionic/docs/plans"
cat > "$R/.bionic/docs/plans/wave.plan.md" <<'EOF'
---
governing-skill: superpowers:writing-plans
sdlc-step: 3
abandoned: chris 2026-09-02
---

## SDLC State

current: 4
- Step 4: in progress
EOF
call_active_run "$R"
expect_eq "frontmatter abandoned: -> active_run exits 1" 1 "$AR_ST"
expect_empty "frontmatter abandoned: -> prints nothing" "$AR_OUT"

# --- no plans dir -> inactive ---
R="$SANDBOX/r2e"; mkdir -p "$R/.bionic"
call_active_run "$R"
expect_eq "no plans dir -> active_run exits 1" 1 "$AR_ST"
expect_empty "no plans dir -> prints nothing" "$AR_OUT"

# --- task scale: the one plan at current: 4 is active, and so is the retired current: T2 ---
# ONE LEDGER SHAPE (wave-31 T24; REQ-1, D2). A task-scale plan is the shared fixture's
# (tests/lib/plan-fixture.sh); its `current:` is a step number like any plan's. The retired
# `current: T<n>` stays an open run so launch-sync, the stop wall and the tick reach the plan and
# refuse it by name (AC-1.2); any other malformed value is closed (`banana`, §R5).
R="$SANDBOX/r2f"; mkdir -p "$R/.bionic"
P=$(plan_fixture "$R/.bionic/docs/plans/task.plan.md" task)
call_active_run "$R"
expect_eq "task scale, current: 4 -> active_run exits 0" 0 "$AR_ST"
expect_eq "task scale, current: 4 -> prints the plan path" "$P" "$AR_OUT"
P=$(plan_fixture --current T2 "$R/.bionic/docs/plans/task.plan.md" task)
expect_eq "…the same plan carries current: T2" "1" "$(/usr/bin/grep -c '^current: T2$' "$P")"
call_active_run "$R"
expect_eq "task scale, current: T2 -> active_run exits 0 (kept open, so its readers refuse it)" 0 "$AR_ST"
expect_eq "task scale, current: T2 -> prints the plan path" "$P" "$AR_OUT"

# --- newest-by-mtime wins over an older closed plan ---
R="$SANDBOX/r2g"; mkdir -p "$R/.bionic"
OLD=$(mk_plan "$R" "old.plan.md" "9" "- Step 9: report record/x.md, delivered: 2026-08-01")
touch -t 202601010000 "$OLD"
NEW=$(mk_plan "$R" "new.plan.md" "4" "- Step 4: in progress")
call_active_plan "$R"
expect_eq "active_plan picks the newest file by mtime" "$NEW" "$AP_OUT"
call_active_run "$R"
expect_eq "newest-by-mtime (open) wins over an older closed plan -> active_run exits 0" 0 "$AR_ST"
expect_eq "…and prints the newer plan's path" "$NEW" "$AR_OUT"

# ============================================================
section "R3 — the plan-search DEPTH BOUND is 2, and it is the fleet's only one"
# ============================================================
#
# THE BOUND IS A CONTRACT, not an implementation detail, and it is pinned here because this
# library is now the ONE reader of "which *.md answers for this run" (POKER/2, ratified
# 2026-09-03: the tick's private copy is deleted and every hook asks this function). Two
# depths were live during the wave — the five hand-copies and the evidence gate walked 2,
# which is the bionic layout's own depth (`plans/<epic>/<wave>.plan.md`), and L-RUN shipped
# 3 — and tests/cross-gate-agreement.test.sh §S.3d PINNED the disagreement rather than
# papering over it. Unification resolves it AT 2: the gate's descend-2 read is the one held
# body-for-body by §S, deeper files under `plans/` are notes and scratch rather than plans,
# and a bound nobody can state from the layout is a bound that drifts again.
#
# BOTH DIRECTIONS, because the shallow half alone would pass on a library that had no bound
# at all: depth 2 is FOUND, depth 3 is NOT.
R="$SANDBOX/r3a"; mkdir -p "$R/.bionic/docs/plans/epic-99"
P2="$R/.bionic/docs/plans/epic-99/wave-01.plan.md"
{ echo "# fixture plan"; echo; echo "## SDLC State"; echo; echo "current: 4"; } > "$P2"
call_active_plan "$R"
expect_eq "a plan at depth 2 (plans/<epic>/<wave>.md) is found" "$P2" "$AP_OUT"

R="$SANDBOX/r3b"; mkdir -p "$R/.bionic/docs/plans/epic-99/sub"
P3="$R/.bionic/docs/plans/epic-99/sub/wave-01.plan.md"
{ echo "# fixture plan"; echo; echo "## SDLC State"; echo; echo "current: 4"; } > "$P3"
call_active_plan "$R"
expect_eq "a plan at depth 3 is OUT of the bound -> active_plan exits 1" 1 "$AP_ST"
expect_empty "…and prints nothing" "$AP_OUT"
call_active_run "$R"
expect_eq "…so active_run does not see it either" 1 "$AR_ST"

# The bound is on the SEARCH, not on the docs root: the same file one level shallower is
# found, so R3b measures the depth and not some other property of the fixture.
mv "$R/.bionic/docs/plans/epic-99/sub/wave-01.plan.md" "$R/.bionic/docs/plans/epic-99/"
call_active_plan "$R"
expect_eq "…while the same file at depth 2 is found (the fixture measures depth)" \
  "$R/.bionic/docs/plans/epic-99/wave-01.plan.md" "$AP_OUT"

# ============================================================
echo
section "R4 — SIGPIPE-under-pipefail does not flip a >64 KB plan's verdict (AC-21)"
# ============================================================
#
# WHY THIS SECTION EXISTS AND R0-R3 DID NOT CATCH IT (research-refusal.md VERDICT,
# 2026-09-03). `active_run` decides Step 9 by `_run_lines "$plan" | grep -qE
# '…delivered:'`. `grep -q`/`-m1` exit at their FIRST match; the awk feeding them is
# still writing when a match sits well before end-of-file, awk takes SIGPIPE and reports
# 141, and this whole suite runs under `set -uo pipefail` (line 24) — same as every hook
# that calls this library — so the PIPELINE's status becomes 141, not the grep's own 0.
# `if pipeline; then return 1; fi` reads that as false: a CLOSED run (current: 9,
# `delivered:` present) falls through to the Step-9-open arm and reads OPEN. Every fixture
# in R0-R3 is a handful of lines, so `awk` always finishes writing before `grep` even
# looks — too small to reach the SIGPIPE window at all. This section is the one place in
# the suite where the fixture is deliberately padded PAST that window, on this shell's own
# options, so a regression here is caught by size rather than only by content.
#
# THE MEASURED THRESHOLD (research-refusal.md INSTRUMENT §threshold table, this machine):
# 16 167 bytes never flips, 20 214 bytes flips 5/5. 64 KB is the plan's own AC-21 floor —
# comfortably past the measured knee — so every fixture below pads to that literal target,
# and each one asserts its own size to keep the premise visible if the target ever drifts.

mk_filler() {  # <min-bytes> -> that many-or-more bytes of inert filler lines on stdout
  local target="$1" n=0
  while [ "$n" -lt "$target" ]; do
    echo "filler filler filler filler filler filler filler filler filler filler"
    n=$((n + 72))
  done
}
FILLER_TARGET=70000   # > 64 KB (65536) with margin

# --- Step 9 delivered:, filler AFTER the state block, > 64 KB -> CLOSED ---
R="$SANDBOX/r4a"; mkdir -p "$R/.bionic/docs/plans"
F="$R/.bionic/docs/plans/wave.plan.md"
{
  echo "---"
  echo "governing-skill: superpowers:writing-plans"
  echo "sdlc-step: 9"
  echo "---"
  echo
  echo "# fixture plan"
  echo
  echo "## SDLC State"
  echo
  echo "integration-branch: main"
  echo "current: 9"
  echo "- Step 9: report record/x.md, delivered: 2026-09-02"
  echo
  echo "## Notes"
  echo
  mk_filler "$FILLER_TARGET"
} > "$F"
SZ=$(wc -c < "$F" | tr -d '[:space:]')
expect_eq "r4a fixture is actually past 64 KB (size=$SZ)" "yes" "$([ "$SZ" -gt 65536 ] && echo yes || echo no)"
call_active_run_pf "$R"
expect_eq "Step 9 delivered:, filler AFTER state, >64 KB -> active_run exits 1 (closed)" 1 "$AR_ST"
expect_empty "…and prints nothing" "$AR_OUT"

# --- Step 9 delivered:, filler BEFORE the state block, > 64 KB -> CLOSED ---
R="$SANDBOX/r4b"; mkdir -p "$R/.bionic/docs/plans"
F="$R/.bionic/docs/plans/wave.plan.md"
{
  echo "---"
  echo "governing-skill: superpowers:writing-plans"
  echo "sdlc-step: 9"
  echo "---"
  echo
  echo "# fixture plan"
  echo
  echo "## Notes"
  echo
  mk_filler "$FILLER_TARGET"
  echo
  echo "## SDLC State"
  echo
  echo "integration-branch: main"
  echo "current: 9"
  echo "- Step 9: report record/x.md, delivered: 2026-09-02"
} > "$F"
SZ=$(wc -c < "$F" | tr -d '[:space:]')
expect_eq "r4b fixture is actually past 64 KB (size=$SZ)" "yes" "$([ "$SZ" -gt 65536 ] && echo yes || echo no)"
call_active_run_pf "$R"
expect_eq "Step 9 delivered:, filler BEFORE state, >64 KB -> active_run exits 1 (closed)" 1 "$AR_ST"
expect_empty "…and prints nothing" "$AR_OUT"

# --- paired positive: current: 4, > 64 KB -> stays OPEN ---
R="$SANDBOX/r4c"; mkdir -p "$R/.bionic/docs/plans"
F="$R/.bionic/docs/plans/wave.plan.md"
{
  echo "---"
  echo "governing-skill: superpowers:writing-plans"
  echo "sdlc-step: 4"
  echo "---"
  echo
  echo "# fixture plan"
  echo
  echo "## SDLC State"
  echo
  echo "integration-branch: main"
  echo "current: 4"
  echo "- Step 4: in progress"
  echo
  echo "## Notes"
  echo
  mk_filler "$FILLER_TARGET"
} > "$F"
SZ=$(wc -c < "$F" | tr -d '[:space:]')
expect_eq "r4c fixture is actually past 64 KB (size=$SZ)" "yes" "$([ "$SZ" -gt 65536 ] && echo yes || echo no)"
call_active_run_pf "$R"
expect_eq "current: 4, >64 KB -> active_run exits 0 (open, paired positive)" 0 "$AR_ST"
expect_eq "…and prints the plan path" "$F" "$AR_OUT"

# --- paired positive: frontmatter abandoned:, > 64 KB -> CLOSED ---
R="$SANDBOX/r4d"; mkdir -p "$R/.bionic/docs/plans"
F="$R/.bionic/docs/plans/wave.plan.md"
{
  echo "---"
  echo "governing-skill: superpowers:writing-plans"
  echo "sdlc-step: 4"
  echo "abandoned: chris 2026-09-03"
  echo "---"
  echo
  echo "# fixture plan"
  echo
  echo "## SDLC State"
  echo
  echo "integration-branch: main"
  echo "current: 4"
  echo "- Step 4: in progress"
  echo
  echo "## Notes"
  echo
  mk_filler "$FILLER_TARGET"
} > "$F"
SZ=$(wc -c < "$F" | tr -d '[:space:]')
expect_eq "r4d fixture is actually past 64 KB (size=$SZ)" "yes" "$([ "$SZ" -gt 65536 ] && echo yes || echo no)"
call_active_run_pf "$R"
expect_eq "frontmatter abandoned:, >64 KB -> active_run exits 1 (closed, paired positive)" 1 "$AR_ST"
expect_empty "…and prints nothing" "$AR_OUT"

# ============================================================
echo
section "R5 — run_open <plan>: the verdict table, on ONE file, with no root walk"
# ============================================================
#
# WHY THIS FUNCTION EXISTS (wave-session-bound-run, spec §Design; AC-6). Until this wave the
# open/closed verdict was reachable only through `active_run <root>`, which chooses the file
# for you — the newest plan in the root. A session bound to a plan needs the verdict on THAT
# file, and `open_runs` needs it on every candidate, so the verdict is extracted here and
# `active_run` becomes `active_plan` + `run_open` + print.
#
# THE CONTRACT IS "UNCHANGED, BYTE FOR BYTE": every row below is a row `active_run` already
# decided the same way, and R2/R4 above still drive `active_run` over the same states. If the
# two ever disagree, one of the two sections goes red.
#
# run_open PRINTS NOTHING — the path is the caller's already. Every row asserts that beside
# its status, so an implementation that leaked the path could not pass.

RO_OUT=""; RO_ST=0
call_run_open() {  # <plan-path> -> sets RO_OUT, RO_ST
  RO_OUT=$(bash -c '. "$1" || exit 1; run_open "$2"' _ "$LIB" "$1" 2>"$SANDBOX/.err")
  RO_ST=$?
}

R5="$SANDBOX/r5"; mkdir -p "$R5/.bionic"

# --- the OPEN rows ---
P=$(mk_plan "$R5" "open-4.plan.md" "4" "- Step 4: in progress")
call_run_open "$P"
expect_eq "run_open: current: 4 -> exit 0 (open)" 0 "$RO_ST"
expect_empty "run_open: current: 4 -> prints nothing" "$RO_OUT"

P=$(mk_plan "$R5" "open-0.plan.md" "0")
call_run_open "$P"
expect_eq "run_open: current: 0 -> exit 0 (open)" 0 "$RO_ST"

P=$(mk_plan "$R5" "open-8b.plan.md" "8b" "- Step 8b: integrating")
call_run_open "$P"
expect_eq "run_open: current: 8b -> exit 0 (the sub-step letter is stripped)" 0 "$RO_ST"

P=$(mk_plan "$R5" "open-8a.plan.md" "8a")
call_run_open "$P"
expect_eq "run_open: current: 8a -> exit 0 (the sub-step letter is stripped)" 0 "$RO_ST"

P=$(plan_fixture "$R5/.bionic/docs/plans/task-4.plan.md" task)
call_run_open "$P"
expect_eq "run_open: task scale, current: 4 -> exit 0 (open, as at wave scale)" 0 "$RO_ST"
P=$(plan_fixture --current T3 "$R5/.bionic/docs/plans/task-t3.plan.md" task)
call_run_open "$P"
expect_eq "run_open: task scale, current: T3 -> exit 0 (the retired pointer, kept open so it is refused by name)" 0 "$RO_ST"

P=$(mk_plan "$R5" "open-9.plan.md" "9" "- Step 9: report drafted, not yet delivered")
call_run_open "$P"
expect_eq "run_open: current: 9 without 'delivered:' -> exit 0 (open)" 0 "$RO_ST"

P=$(mk_plan "$R5" "open-indented.plan.md" "  4" "- Step 4: in progress")
call_run_open "$P"
expect_eq "run_open: leading whitespace on current: is tolerated -> exit 0" 0 "$RO_ST"

# --- the CLOSED rows, each beside the open row above that shares its builder ---
P=$(mk_plan "$R5" "closed-9.plan.md" "9" "- Step 9: report record/x.md, delivered: 2026-09-02")
call_run_open "$P"
expect_eq "run_open: current: 9 WITH 'delivered:' -> exit 1 (closed)" 1 "$RO_ST"
expect_empty "run_open: closed -> prints nothing" "$RO_OUT"

P=$(mk_plan "$R5" "closed-12.plan.md" "12")
call_run_open "$P"
expect_eq "run_open: current: 12 (out of range) -> exit 1" 1 "$RO_ST"

P=$(mk_plan "$R5" "closed-junk.plan.md" "banana")
call_run_open "$P"
expect_eq "run_open: a non-numeric current: -> exit 1" 1 "$RO_ST"

R5D="$R5/.bionic/docs/plans"
cat > "$R5D/closed-abandoned.plan.md" <<'EOF'
---
governing-skill: superpowers:writing-plans
sdlc-step: 3
abandoned: chris 2026-09-04
---

## SDLC State

current: 4
- Step 4: in progress
EOF
call_run_open "$R5D/closed-abandoned.plan.md"
expect_eq "run_open: frontmatter abandoned: -> exit 1 regardless of current:" 1 "$RO_ST"

cat > "$R5D/closed-nocurrent.plan.md" <<'EOF'
---
governing-skill: superpowers:writing-plans
---

## SDLC State

integration-branch: main
EOF
call_run_open "$R5D/closed-nocurrent.plan.md"
expect_eq "run_open: no current: line at all -> exit 1" 1 "$RO_ST"

cat > "$R5D/closed-fenced-current.plan.md" <<'EOF'
---
governing-skill: superpowers:writing-plans
---

## SDLC State

An example of the block, not the block itself:

```
current: 4
```
EOF
call_run_open "$R5D/closed-fenced-current.plan.md"
expect_eq "run_open: a current: line only INSIDE a fence -> exit 1 (fence-aware)" 1 "$RO_ST"

call_run_open "$R5D/no-such-plan.md"
expect_eq "run_open: a path that does not exist -> exit 1" 1 "$RO_ST"
expect_empty "run_open: a missing path -> prints nothing" "$RO_OUT"

call_run_open ""
expect_eq "run_open: an empty path -> exit 1" 1 "$RO_ST"

# --- AGREEMENT: active_run is active_plan + run_open, and says so on the same fixtures ---
# R2's roots are still on disk. For each, active_run's status must equal run_open's status
# on the file active_plan names — the property that makes the extraction lossless.
for _r in r2a r2b r2c r2f; do
  call_active_plan "$SANDBOX/$_r"
  call_run_open "$AP_OUT"
  call_active_run "$SANDBOX/$_r"
  expect_eq "agreement ($_r): active_run's status == run_open on active_plan's file" \
    "$AR_ST" "$RO_ST"
done

# ============================================================
echo
section "R6 — open_runs <root>: every open run in the root, newest first"
# ============================================================
#
# WHY (spec §Design, ownership table "the open-run set"). Engagement binds a session to the
# sole open run when there is exactly one; session-start lists them when there are several;
# poker's `bind` verb validates membership. All three need the SET, which nothing could name
# before this wave — `active_run` answers with at most one path and only ever the newest.
#
# THE WALK IS active_plan's WALK: same two trees, same depth 2, same fence-aware
# `## SDLC State` filter. R6e drives all three of those properties through open_runs so a
# copy that drifted from active_plan's own walk is caught behaviourally, which is the wall
# the spec's ownership table names for this concept.
#
# ORDERING IS NEWEST-MTIME-FIRST, so line 1 is the file active_plan names whenever that file
# is itself open. R6d is the one case where the two answers differ: the newest plan is
# CLOSED, so active_run has no answer at all while the set is non-empty.

OR_OUT=""; OR_ST=0
call_open_runs() {  # <root> -> sets OR_OUT (newline-joined), OR_ST
  OR_OUT=$(bash -c '. "$1" || exit 1; open_runs "$2"' _ "$LIB" "$1" 2>"$SANDBOX/.err")
  OR_ST=$?
}
first_line() { printf '%s\n' "$1" | head -1; }
line_count() { [ -z "$1" ] && { echo 0; return; }; printf '%s\n' "$1" | wc -l | tr -d '[:space:]'; }

# --- R6a: a root whose only plan is CLOSED -> the set is empty; then re-open it ---
R="$SANDBOX/r6a"; mkdir -p "$R/.bionic"
C=$(mk_plan "$R" "only.plan.md" "9" "- Step 9: report record/x.md, delivered: 2026-09-02")
call_open_runs "$R"
expect_eq "open_runs: a root with one CLOSED plan -> exit 1" 1 "$OR_ST"
expect_empty "open_runs: …and prints nothing" "$OR_OUT"
# The paired positive on the SAME fixture: re-open that same file and the set is non-empty,
# so the empty answer above measured the verdict and not a broken walk.
mk_plan "$R" "only.plan.md" "4" "- Step 4: in progress" >/dev/null
call_open_runs "$R"
expect_eq "open_runs: …the same file re-opened -> exit 0" 0 "$OR_ST"
expect_eq "open_runs: …and it is the one line" "$C" "$OR_OUT"

# --- R6b: exactly one open run ---
R="$SANDBOX/r6b"; mkdir -p "$R/.bionic"
ONE=$(mk_plan "$R" "wave.plan.md" "4" "- Step 4: in progress")
call_open_runs "$R"
expect_eq "open_runs: one open run -> exit 0" 0 "$OR_ST"
expect_eq "open_runs: one open run -> one line, that path" "$ONE" "$OR_OUT"
expect_eq "open_runs: one open run -> exactly one line" 1 "$(line_count "$OR_OUT")"
call_active_run "$R"
expect_eq "open_runs line 1 == active_run's answer (one open run)" "$AR_OUT" "$(first_line "$OR_OUT")"

# --- R6c: two open runs and a closed one, mtimes controlled ---
R="$SANDBOX/r6c"; mkdir -p "$R/.bionic"
OLDOPEN=$(mk_plan "$R" "old-open.plan.md" "4" "- Step 4: in progress")
MIDSHUT=$(mk_plan "$R" "mid-closed.plan.md" "9" "- Step 9: report record/x.md, delivered: 2026-09-01")
NEWOPEN=$(mk_plan "$R" "new-open.plan.md" "4" "- Step 4: in progress")
touch -t 202601010000 "$OLDOPEN"
touch -t 202602010000 "$MIDSHUT"
touch -t 202603010000 "$NEWOPEN"
call_open_runs "$R"
expect_eq "open_runs: two open + one closed -> exit 0" 0 "$OR_ST"
expect_eq "open_runs: …exactly two lines" 2 "$(line_count "$OR_OUT")"
expect_eq "open_runs: …newest open first, older open second" \
  "$(printf '%s\n%s' "$NEWOPEN" "$OLDOPEN")" "$OR_OUT"
expect_eq "open_runs: …the CLOSED plan is not in the set" "no" \
  "$(rp_contains "$OR_OUT" "$MIDSHUT")"
call_active_run "$R"
expect_eq "open_runs line 1 == active_run's answer (two open runs)" "$AR_OUT" "$(first_line "$OR_OUT")"

# --- R6d: the newest plan is CLOSED — the set is NOT empty, active_run is ---
R="$SANDBOX/r6d"; mkdir -p "$R/.bionic"
DOPEN=$(mk_plan "$R" "open.plan.md" "4" "- Step 4: in progress")
DSHUT=$(mk_plan "$R" "closed.plan.md" "9" "- Step 9: report record/x.md, delivered: 2026-09-02")
touch -t 202601010000 "$DOPEN"
touch -t 202602010000 "$DSHUT"
call_active_run "$R"
expect_eq "newest plan closed -> active_run exits 1 (today's answer, unchanged)" 1 "$AR_ST"
call_open_runs "$R"
expect_eq "…while open_runs still finds the older OPEN plan -> exit 0" 0 "$OR_ST"
expect_eq "…and lists exactly it" "$DOPEN" "$OR_OUT"

# --- R6e: the walk is active_plan's walk — incidents/, depth 2, fence-aware ---
R="$SANDBOX/r6e"; mkdir -p "$R/.bionic"
EPLAN=$(mk_plan "$R" "wave.plan.md" "4" "- Step 4: in progress")
EINC=$(mk_plan_in "$R" "incidents" "inc-01.md" "4" "- Step 4: in progress")
EDEEP=$(mk_plan_in "$R" "plans/epic-99/sub" "deep.plan.md" "4" "- Step 4: in progress")
EFENCE="$R/.bionic/docs/plans/example.md"
cat > "$EFENCE" <<'EOF'
# a page ABOUT the lifecycle, not a plan

```
## SDLC State

current: 4
```
EOF
touch -t 202603010000 "$EPLAN"
touch -t 202602010000 "$EINC"
touch -t 202604010000 "$EDEEP"
touch -t 202605010000 "$EFENCE"
call_open_runs "$R"
expect_eq "open_runs: plans/ and incidents/ are both walked -> exit 0" 0 "$OR_ST"
expect_eq "open_runs: …two members, plans/ newest first" \
  "$(printf '%s\n%s' "$EPLAN" "$EINC")" "$OR_OUT"
expect_eq "open_runs: …a plan at depth 3 is OUT of the bound even though it is newest" "no" \
  "$(rp_contains "$OR_OUT" "$EDEEP")"
expect_eq "open_runs: …a fenced ## SDLC State is documentation, not a run" "no" \
  "$(rp_contains "$OR_OUT" "$EFENCE")"
call_active_plan "$R"
expect_eq "…and active_plan agrees on which file is newest-and-real" "$EPLAN" "$AP_OUT"

# --- R6g: the ORDER is the mtime's, and no path ever enters the sort (S10a, review P2c) ---
#
# WHY THIS ROW EXISTS. R6a–R6f measure membership; every one of them would stay green with
# the order reversed, because a re-keyed sort still prints every member. S10a rewrote the
# ordering pass (linear insertion → binary insertion, review P2c) and that is exactly the
# class of change whose failure mode is a set that is right and an order that is not — the
# first attempt at it, keyed on `stat`'s nanoseconds instead of the shell's own `-nt`,
# reordered 21 of 500 members on a tree built in one burst and every existing row stayed
# green, because they all set their mtimes with `touch -t`.
#
# THREE mtimes, NONE of them in the walk's own order, so no accident — neither "print in the
# order found" nor "print it backwards" — lands on the expected answer.
#
# THE PATHS CARRY SPACES, deliberately. The ordering keys are the mtime and the discovery
# index and the paths stay in a bash array, so a path that word-split would surface here as a
# member in the wrong slot or a member that vanished.
R="$SANDBOX/r6g"; mkdir -p "$R/.bionic"
G_MID=$(mk_plan "$R" "a walked one.plan.md" "4" "- Step 4: in progress")
G_OLD=$(mk_plan "$R" "b walked two.plan.md" "4" "- Step 4: in progress")
G_NEW=$(mk_plan "$R" "c walked three.plan.md" "4" "- Step 4: in progress")
touch -t 202602010000 "$G_MID"
touch -t 202601010000 "$G_OLD"
touch -t 202603010000 "$G_NEW"
call_open_runs "$R"
expect_eq "open_runs: three open plans -> exit 0" 0 "$OR_ST"
expect_eq "open_runs: …exactly three lines (the ordering dropped no member)" \
  3 "$(line_count "$OR_OUT")"
expect_eq "open_runs: …newest mtime first, oldest last, whatever order the walk found them" \
  "$(printf '%s\n%s\n%s' "$G_NEW" "$G_MID" "$G_OLD")" "$OR_OUT"
call_active_plan "$R"
expect_eq "open_runs line 1 == active_plan's answer, with spaces in every path" \
  "$G_NEW" "$AP_OUT"

# --- R6h: plans written inside ONE SECOND — the two selectors still agree (AC-9) ---
#
# THE LIMITATION IS DOCUMENTED, AND THIS IS WHAT THE DOCUMENTATION BUYS. `-nt`
# compares whole seconds under /bin/bash 3.2, so two plans written in the same
# second tie and the tie is broken by directory order — which of them
# `active_plan` names is genuinely unspecified, and asserting a winner here
# would pin the filesystem rather than the library. What is NOT unspecified is
# that both selectors resolve the tie the SAME way, because they run the same
# comparator over the same walk: `open_runs`' line 1 is `active_plan`'s answer.
# That is the invariant lib/run.sh accepts the whole-second reading in order to
# keep, and the reason a sub-second comparator in ONE of them was rejected
# rather than taken (see the block under `open_runs`).
#
# NO `touch -t` HERE, ON PURPOSE. Every other fixture in R6 sets its mtimes
# explicitly and can therefore never meet a tie; this one writes three plans as
# fast as the shell can and lets them collide, which is the state
# patrol-revive's rows 33/34 actually hit.
R="$SANDBOX/r6-burst"; mkdir -p "$R/.bionic"
mk_plan "$R" "burst-a.plan.md" "4" "- Step 4: in progress" >/dev/null
mk_plan "$R" "burst-b.plan.md" "4" "- Step 4: in progress" >/dev/null
mk_plan "$R" "burst-c.plan.md" "4" "- Step 4: in progress" >/dev/null
call_open_runs "$R"
call_active_plan "$R"
expect_eq "same-second burst: all three plans are in the open set" 3 "$(line_count "$OR_OUT")"
expect_eq "same-second burst: open_runs line 1 == active_plan's answer" \
  "$AP_OUT" "$(first_line "$OR_OUT")"

# --- R6f: no docs tree at all ---
R="$SANDBOX/r6f"; mkdir -p "$R/.bionic"
call_open_runs "$R"
expect_eq "open_runs: no plans dir -> exit 1" 1 "$OR_ST"
expect_empty "open_runs: no plans dir -> prints nothing" "$OR_OUT"

# --- R6i: an UNREADABLE candidate is named, and neither opened nor closed (wave-20 T18) ---
#
# (REQ-2, D2; T1's carry-over, research D3's residual.) T1 made a BOUND session's plan answer
# `bound-unreadable`. The unbound walk still read a mode-000 candidate through `_run_lines`,
# got no text, found no `## SDLC State`, and dropped it: an unreadable plan vanished from
# `open_runs` and `active_plan` without a word, and the walk moved on to the next-newest run
# as if nothing were there. It now prints `bound-unreadable <path>` on STDERR — stdout stays
# the set of runs it CAN read, so every caller that parses the set is unchanged — and the
# candidate is in neither answer: not a member of the open set, and never read as closed.
#
# PRIVILEGE, CHECKED FIRST (R8h's reason): as root the mode-000 file reads, and every row
# would pass on a readable plan.
R="$SANDBOX/r6i"; mkdir -p "$R/.bionic"
I_OK=$(mk_plan "$R" "readable.plan.md" "4" "- Step 4: in progress")
I_LOCKED=$(mk_plan "$R" "locked.plan.md" "4" "- Step 4: in progress")
touch -t 202601010000 "$I_OK"
touch -t 202603010000 "$I_LOCKED"
chmod 000 "$I_LOCKED"
expect_eq "r6i premise: the newest candidate exists and this user cannot read it" "yes" \
  "$([ -e "$I_LOCKED" ] && [ ! -r "$I_LOCKED" ] && echo yes || echo no)"
call_open_runs "$R"
expect_eq "open_runs: an unreadable candidate beside a readable open one -> exit 0, the readable one only" \
  "0|$I_OK" "$OR_ST|$OR_OUT"
expect_eq "open_runs: …and names the unreadable one on stderr, never silently" \
  "bound-unreadable $I_LOCKED" "$(grep -F "$I_LOCKED" "$SANDBOX/.err")"
call_active_plan "$R"
expect_eq "active_plan: …selects over the same walk, so it names it too" \
  "bound-unreadable $I_LOCKED" "$(grep -F "$I_LOCKED" "$SANDBOX/.err")"
# session_run's own driver is R8's; this is its body, because R8 is further down the file.
I_SR_ST=0
I_SR=$(bash -c '. "$1" || exit 1; session_run "$2" "$3"' _ "$LIB" "$R" "u-i" 2>"$SANDBOX/.err") || I_SR_ST=$?
expect_eq "session_run, unbound: …the fallback is the readable run" "0|fallback $I_OK" "$I_SR_ST|$I_SR"
expect_eq "session_run, unbound: …and the unreadable candidate is named beside it" \
  "bound-unreadable $I_LOCKED" "$(grep -F "$I_LOCKED" "$SANDBOX/.err")"
I_RO=0; bash -c '. "$1" || exit 1; run_open "$2"' _ "$LIB" "$I_LOCKED" 2>/dev/null || I_RO=$?
expect_eq "run_open: …the same file is neither open (0) nor closed (1): unreadable (3)" 3 "$I_RO"
# THE PAIRED POSITIVE, ON THE SAME ROOT: one fact moves — the mode — and the file is a member
# again, newest first, with nothing on stderr.
chmod 644 "$I_LOCKED"
call_open_runs "$R"
expect_eq "open_runs: …the same file readable again -> a member, newest first" \
  "$(printf '%s\n%s' "$I_LOCKED" "$I_OK")" "$OR_OUT"
expect_empty "open_runs: …and nothing is named on stderr" "$(cat "$SANDBOX/.err")"

# --- R6j: the ONLY candidate is unreadable -> no open run, and still named ---
R="$SANDBOX/r6j"; mkdir -p "$R/.bionic"
J_LOCKED=$(mk_plan "$R" "only.plan.md" "4" "- Step 4: in progress")
chmod 000 "$J_LOCKED"
call_open_runs "$R"
expect_eq "open_runs: the only candidate unreadable -> exit 1, nothing on stdout" "1|" "$OR_ST|$OR_OUT"
expect_eq "open_runs: …and it is named on stderr" \
  "bound-unreadable $J_LOCKED" "$(grep -F "$J_LOCKED" "$SANDBOX/.err")"
chmod 644 "$J_LOCKED"

# --- R6k: a FOLDER in the walk that cannot be opened is named (research D3 N1's shape) ---
#
# `find` cannot list a mode-000 folder, so a plan inside it never reaches the loop at all and
# only the folder can be named — the same rule `plan_unreadable` applies to a bound path.
R="$SANDBOX/r6k"; mkdir -p "$R/.bionic"
K_OK=$(mk_plan "$R" "readable.plan.md" "4" "- Step 4: in progress")
K_IN=$(mk_plan_in "$R" "plans/epic-vault" "vaulted.plan.md" "4" "- Step 4: in progress")
K_VAULT="$R/.bionic/docs/plans/epic-vault"
chmod 000 "$K_VAULT"
call_open_runs "$R"
expect_eq "open_runs: a plan inside an unopenable folder is not a member" "0|$K_OK" "$OR_ST|$OR_OUT"
expect_eq "open_runs: …and the folder is named on stderr" \
  "bound-unreadable $K_VAULT" "$(grep -F "$K_VAULT" "$SANDBOX/.err")"
chmod 755 "$K_VAULT"
call_open_runs "$R"
expect_eq "open_runs: …the folder opened again -> the plan inside is a member" "yes" \
  "$(rp_contains "$OR_OUT" "$K_IN")"
expect_empty "open_runs: …and nothing is named on stderr" "$(cat "$SANDBOX/.err")"

# ============================================================
echo
section "R7 — session_plan <root> <sid>: the marker's plan= field, and only that"
# ============================================================
#
# WHY (spec §Design, "Session binding"). hooks/engage.sh has written `plan=<path>` into
# engaged-<sid>.state since 1.4.1 and nothing has ever read it. This is the reader. It is
# deliberately NOT a verdict: it reports what the marker says, and session_run decides what
# that means.
#
# THE THREE UNBOUND SHAPES ARE ALL REAL. Absent is a session that never engaged; `plan=none`
# is what engage.sh writes when the root holds zero or several open runs; EMPTY is what
# tests/session-poker.test.sh:82 plants (`: > "$1/.bionic/tmp/engaged-$SID.state"`), so a
# reader that treated an empty marker as anything but unbound would break that suite's whole
# fixture set.
#
# THE SYMLINK REFUSAL is engaged_session's, restated: a link at the marker path is refused
# BEFORE it is followed, so a planted link cannot make a session read a plan= line from a
# file outside the tree.

SP_OUT=""; SP_ST=0
call_session_plan() {  # <root> <sid> -> sets SP_OUT, SP_ST
  SP_OUT=$(bash -c '. "$1" || exit 1; session_plan "$2" "$3"' _ "$LIB" "$1" "$2" 2>"$SANDBOX/.err")
  SP_ST=$?
}
mk_marker() {  # <root> <sid> <exact file body>
  local root="$1" sid="$2" body="$3"
  mkdir -p "$root/.bionic/tmp"
  printf '%s' "$body" > "$root/.bionic/tmp/engaged-$sid.state"
  chmod 600 "$root/.bionic/tmp/engaged-$sid.state"
}

R7="$SANDBOX/r7"; mkdir -p "$R7/.bionic/tmp"
P7=$(mk_plan "$R7" "wave.plan.md" "4" "- Step 4: in progress")

# --- the POSITIVE the negatives are measured against ---
mk_marker "$R7" "s-bound" "$(printf 'plan=%s\nengaged_at=2026-09-04T10:00:00Z\n' "$P7")"
call_session_plan "$R7" "s-bound"
expect_eq "session_plan: a marker with plan=<path> -> exit 0" 0 "$SP_ST"
expect_eq "session_plan: …prints exactly that path" "$P7" "$SP_OUT"

# --- the UNBOUND shapes ---
call_session_plan "$R7" "s-absent"
expect_eq "session_plan: no marker -> exit 1" 1 "$SP_ST"
expect_empty "session_plan: no marker -> prints nothing" "$SP_OUT"

mk_marker "$R7" "s-empty" ""
call_session_plan "$R7" "s-empty"
expect_eq "session_plan: an EMPTY marker -> exit 1 (session-poker.test.sh:82 plants one)" 1 "$SP_ST"
expect_empty "session_plan: an empty marker -> prints nothing" "$SP_OUT"

mk_marker "$R7" "s-none" "$(printf 'plan=none\nengaged_at=2026-09-04T10:00:00Z\n')"
call_session_plan "$R7" "s-none"
expect_eq "session_plan: plan=none -> exit 1" 1 "$SP_ST"
expect_empty "session_plan: plan=none -> prints nothing" "$SP_OUT"

mk_marker "$R7" "s-emptyval" "$(printf 'plan=\nengaged_at=2026-09-04T10:00:00Z\n')"
call_session_plan "$R7" "s-emptyval"
expect_eq "session_plan: an empty plan= value -> exit 1" 1 "$SP_ST"

mk_marker "$R7" "s-nofield" "$(printf 'engaged_at=2026-09-04T10:00:00Z\n')"
call_session_plan "$R7" "s-nofield"
expect_eq "session_plan: a marker with no plan= line at all -> exit 1" 1 "$SP_ST"

# --- LINE ENDINGS: translated, never deleted (the _run_lines discipline) ---
printf 'plan=%s\r\nengaged_at=2026-09-04T10:00:00Z\r\n' "$P7" \
  > "$R7/.bionic/tmp/engaged-s-crlf.state"
call_session_plan "$R7" "s-crlf"
expect_eq "session_plan: a CRLF marker -> exit 0" 0 "$SP_ST"
expect_eq "session_plan: …and the path carries no trailing CR" "$P7" "$SP_OUT"

# --- the marker-path guards, inherited from engaged_marker_path/engaged_session ---
ln -s "$R7/.bionic/tmp/engaged-s-bound.state" "$R7/.bionic/tmp/engaged-s-link.state"
call_session_plan "$R7" "s-link"
expect_eq "session_plan: a SYMLINK at the marker path is refused before it is followed" 1 "$SP_ST"
expect_empty "session_plan: …and prints nothing, though its target is a valid marker" "$SP_OUT"

call_session_plan "$R7" "unknown"
expect_eq "session_plan: the 'unknown' sid fallback -> exit 1" 1 "$SP_ST"

call_session_plan "$R7" "bad/sid"
expect_eq "session_plan: a sid outside [A-Za-z0-9_-] -> exit 1" 1 "$SP_ST"

call_session_plan "$R7" ""
expect_eq "session_plan: an empty sid -> exit 1" 1 "$SP_ST"

# ============================================================
echo
finish
