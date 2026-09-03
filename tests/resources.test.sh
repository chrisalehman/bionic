#!/bin/bash
# tests/resources.test.sh — payload/scripts/lib/resources.sh and the attestation v2 it feeds.
#
# WHAT THIS SUITE PINS (spec AC-24, AC-25, AC-30 thresholds; wave 1.4.0 slice L-RESOURCES).
# The parallel budget stopped being a number a human guessed and became a function of the
# machine. Three questions, three functions, one file:
#
#   resources_probe                        what this machine IS
#   resources_budget <cores> <mem> <disk>   how wide a wave may run on a machine like that
#   resources_pressure <cores>              whether it is under strain RIGHT NOW
#
# WHY MEMORY IS THE HARD TERM AND COMPUTE THE SOFT ONE (user 2026-09-02, "1 amended").
# The measured failure is a kernel SIGKILL: seven concurrent suites on an 8 GB machine
# drove free memory to ~188 MB and the kernel killed a suite mid-run (tests/run.sh:63-68).
# Over-subscribing cores costs wall time; over-subscribing memory destroys work. So the
# memory term is measured and binding, and the compute term carries `measured: pending`
# until AC-32's live run at the wave head replaces CORES_PER_SUITE with a number.
#
# THE BUDGET IS DERIVED ONCE AND READ, NEVER RE-DERIVED (design-ledger S6). `resources_budget`
# is a pure function of its three arguments — it consults nothing live — so the same machine
# facts always answer the same budget, whatever the machine is doing at the time. Pressure is
# the separate, live question, and it can only HOLD or NARROW; it never moves the ceiling.
#
# HERMETIC. The budget and pressure arms take every reading as an argument or through the
# BIONIC_PROBE_FREE_MB / BIONIC_PROBE_LOAD_1M overrides, so the assertions do not depend on
# what this machine happens to be doing. Exactly one arm reads the real machine — §C, which
# asserts SHAPE and plausibility, never specific numbers. The attestation arms run the probe
# script inside a throwaway sandbox repo with HOME and CLAUDE_CONFIG_DIR redirected.
#
# FIXTURE FIDELITY (declared, per .claude memory fixtures-can-pin-away-the-test):
#   * The four budget fixtures are the plan's, and the fourth (18c / 128 GB / 1700 GB) is
#     THIS machine, measured 2026-09-02: `sysctl -n hw.ncpu` = 18, `hw.memsize` =
#     137438953472 (128 GiB), `df -Pg .` Available = 1710 GB, `sysctl -n vm.loadavg` =
#     { 4.34 2.63 2.18 }, `uname -s` = Darwin. Its expected budget is the hand-derived
#     budget this wave is running under (plan frontmatter `parallel-budget:`), so the
#     library reproducing it is what retires the hand derivation.
#   * The pressure readings are INJECTED, chosen to sit either side of the constants. The
#     emergency figure is anchored on the measured ~188 MB kill.
#   * The v1 attestation fixture is a real record shape: the field set hooks/preflight-probe.sh
#     wrote before this slice, which tests/preflight-probe.test.sh already drives.
#   * session ids are SHAPE-ONLY well-formed uuids, the same convention
#     tests/preflight-probe.test.sh uses.
#
# Usage: bash tests/resources.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
LIB="$REPO_ROOT/payload/scripts/lib/resources.sh"
PROBE="${BIONIC_HOOKS_DIR}/preflight-probe.sh"

TMPROOT="$(mktemp -d "${TMPDIR:-/tmp}/resources-test.XXXXXX")"
cleanup() { chmod -R u+rwX "$TMPROOT" 2>/dev/null; rm -rf "$TMPROOT"; }
trap cleanup EXIT

PASS=0; FAIL=0; TOTAL=0
ok()  { TOTAL=$((TOTAL + 1)); PASS=$((PASS + 1)); echo "PASS: $1"; }
bad() { TOTAL=$((TOTAL + 1)); FAIL=$((FAIL + 1)); echo "FAIL: $1"; [ -n "${2:-}" ] && echo "      $2"; }
expect_eq()    { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected [$2], got [$3]"; fi; }
expect_match() { if printf '%s' "$2" | grep -Eq "$3"; then ok "$1"; else bad "$1" "[$2] does not match /$3/"; fi; }
expect_true()  { if "${@:2}"; then ok "$1"; else bad "$1"; fi; }
expect_false() { if "${@:2}"; then bad "$1"; else ok "$1"; fi; }
section() { echo; echo "── $1"; }

# The library must load before anything else can be asked of it.
if [ ! -r "$LIB" ]; then
  echo "FAIL: payload/scripts/lib/resources.sh is not readable at $LIB"
  echo; echo "resources.test.sh: 0 passed, 1 failed, 1 total"
  exit 1
fi
# shellcheck disable=SC1090
. "$LIB"

# field <line> <key> — reads a `key=value` out of a space-separated one-line record BY KEY,
# never by position (the A6 rule the attestation schema already lives under).
field() {
  printf '%s\n' "$1" | tr ' ' '\n' | grep "^$2=" | head -1 | cut -d= -f2-
}

# ════════════════════════════════════════════════════════════ §A — the constants block

section "A — constants carry their datum (AC-24: 'every constant carries its datum and date')"

expect_eq   "MEM_RESERVE_GB"    "2"    "${MEM_RESERVE_GB:-unset}"
expect_eq   "MEM_PER_SUITE_GB"  "1.2"  "${MEM_PER_SUITE_GB:-unset}"
expect_eq   "CORES_PER_SUITE"   "1.61" "${CORES_PER_SUITE:-unset}"
expect_eq   "DISK_PER_TREE_GB"  "0.5"  "${DISK_PER_TREE_GB:-unset}"
expect_eq   "WRITERS_EXTRA"     "4"    "${WRITERS_EXTRA:-unset}"
expect_eq   "TEST_JOBS_MIN"     "4"    "${TEST_JOBS_MIN:-unset}"
expect_eq   "TEST_JOBS_MAX"     "24"   "${TEST_JOBS_MAX:-unset}"
expect_eq   "WORKTREES_MIN"     "2"    "${WORKTREES_MIN:-unset}"
expect_eq   "WORKTREES_MAX"     "32"   "${WORKTREES_MAX:-unset}"
expect_eq   "WRITERS_MIN"       "2"    "${WRITERS_MIN:-unset}"
expect_eq   "WRITERS_MAX"       "32"   "${WRITERS_MAX:-unset}"
expect_eq   "HOLD_FREE_MB"      "1024" "${HOLD_FREE_MB:-unset}"
expect_eq   "HOLD_LOAD_FACTOR"  "1.5"  "${HOLD_LOAD_FACTOR:-unset}"
expect_eq   "EMERGENCY_FREE_MB" "256"  "${EMERGENCY_FREE_MB:-unset}"

# The datum is the point of the constant. A number with no provenance is the thing this
# slice exists to remove, so every assignment above must carry a trailing comment.
for _c in MEM_RESERVE_GB MEM_PER_SUITE_GB CORES_PER_SUITE DISK_PER_TREE_GB WRITERS_EXTRA \
          TEST_JOBS_MIN TEST_JOBS_MAX WORKTREES_MIN WORKTREES_MAX WRITERS_MIN WRITERS_MAX \
          HOLD_FREE_MB HOLD_LOAD_FACTOR EMERGENCY_FREE_MB; do
  if grep -Eq "^${_c}=[^ ]+[[:space:]]+#[[:space:]]*\S" "$LIB"; then
    ok "$_c assignment carries a datum comment"
  else
    bad "$_c assignment carries a datum comment"
  fi
done

# AC-32 replaced AC-24's 'measured: pending' line at the wave head with the measurement
# and its provenance: date, job count, the sha it was taken at, and the record path.
expect_true "CORES_PER_SUITE carries its AC-32 measurement (date, jobs, sha, record)" \
  grep -q 'measured 2026-09-03 at BIONIC_TEST_JOBS=18' "$LIB"
expect_true "CORES_PER_SUITE names the full-suite record it was measured from" \
  grep -q 'record/wave-1.4.0/step5-full-suite-report.md' "$LIB"
# The 8 GB kernel-SIGKILL measurement is the memory term's whole justification.
expect_true "MEM_PER_SUITE_GB cites the tests/run.sh:63-68 kill datum" \
  grep -q 'tests/run.sh:63-68' "$LIB"

# ════════════════════════════════════════════════════════════ §B — resources_budget

section "B — resources_budget: memory hard, compute soft, disk for trees (AC-24)"

# fixture-fidelity: the plan's four fixtures, verbatim.
#   suites    = max(1, min(floor((mem_gb − 2) / 1.2), floor(cores / CORES_PER_SUITE)))
#   test_jobs = clamp(cores, 4, 24)
#   worktrees = clamp(floor(disk_free_gb / 0.5), 2, 32)
#   writers   = clamp(suites + 4, 2, 32)

B1="$(resources_budget 8 8 100)"
expect_eq "8c/8GB/100GB → suites 4 (compute binds: floor(8/1.61)=4 < floor(6/1.2)=5)" "4" "$(field "$B1" suites)"
expect_eq "8c/8GB/100GB → writers 8"                             "8" "$(field "$B1" writers)"
expect_eq "8c/8GB/100GB → test_jobs 8"                           "8" "$(field "$B1" test_jobs)"
expect_eq "8c/8GB/100GB → worktrees 32 (disk term clamped)"      "32" "$(field "$B1" worktrees)"

B2="$(resources_budget 32 128 1000)"
expect_eq "32c/128GB/1000GB → suites 19 (compute binds: floor(32/1.61))" "19" "$(field "$B2" suites)"
expect_eq "32c/128GB/1000GB → writers 23 (19 + 4)"       "23" "$(field "$B2" writers)"
expect_eq "32c/128GB/1000GB → test_jobs 24 (clamped)"    "24" "$(field "$B2" test_jobs)"

B3="$(resources_budget 2 4 10)"
expect_eq "2c/4GB/10GB → suites 1 (floor never falls below one)" "1"  "$(field "$B3" suites)"
expect_eq "2c/4GB/10GB → writers 5"                             "5"  "$(field "$B3" writers)"
expect_eq "2c/4GB/10GB → test_jobs 4 (clamped up)"              "4"  "$(field "$B3" test_jobs)"
expect_eq "2c/4GB/10GB → worktrees 20 (disk binds)"             "20" "$(field "$B3" worktrees)"

# fixture-fidelity: THIS machine, probed 2026-09-02; CORES_PER_SUITE measured on it 2026-09-03
# (AC-32). Its answer is narrower than the hand-derived budget the wave ran under (suites 18,
# writers 22) — the measurement moved the compute term from `cores` to floor(18/1.61) = 11.
B4="$(resources_budget 18 128 1700)"
expect_eq "18c/128GB/1700GB (this machine) → suites 11 (floor(18/1.61))" "11" "$(field "$B4" suites)"
expect_eq "18c/128GB/1700GB (this machine) → writers 15"   "15" "$(field "$B4" writers)"
expect_eq "18c/128GB/1700GB (this machine) → worktrees 32" "32" "$(field "$B4" worktrees)"
expect_eq "18c/128GB/1700GB (this machine) → test_jobs 18" "18" "$(field "$B4" test_jobs)"

expect_match "output is one key=value line, four keys, plan order" "$B4" \
  '^writers=[0-9]+ suites=[0-9]+ worktrees=[0-9]+ test_jobs=[0-9]+$'

# A pure function of its arguments: it must not consult the live machine at all, so a
# machine under load answers exactly what an idle one does (design-ledger S6).
expect_eq "budget ignores live pressure (never re-derived from readings)" \
  "$B4" "$(BIONIC_PROBE_FREE_MB=64 BIONIC_PROBE_LOAD_1M=99.0 resources_budget 18 128 1700)"

# Degenerate machines must still answer a runnable budget rather than zero or a crash.
B5="$(resources_budget 1 1 1)"
expect_eq "1c/1GB/1GB → suites 1 (memory term would be 0)"  "1" "$(field "$B5" suites)"
expect_eq "1c/1GB/1GB → writers 5"                          "5" "$(field "$B5" writers)"
expect_eq "1c/1GB/1GB → test_jobs 4"                        "4" "$(field "$B5" test_jobs)"
expect_eq "1c/1GB/1GB → worktrees 2 (clamped up)"           "2" "$(field "$B5" worktrees)"

# Junk in must not become a plausible-looking budget out.
resources_budget 8 abc 100 >/dev/null 2>&1
expect_true "non-numeric argument is refused (non-zero exit)" [ "$?" -ne 0 ]
resources_budget 8 8 >/dev/null 2>&1
expect_true "a missing argument is refused (non-zero exit)" [ "$?" -ne 0 ]

# ════════════════════════════════════════════════════════════ §C — resources_probe

section "C — resources_probe reads THIS machine (AC-24; shape and plausibility only)"

P="$(resources_probe)"
expect_match "probe prints all five keys in order" "$P" \
  '^cores=[0-9]+ mem_gb=[0-9]+ disk_free_gb=[0-9]+ load_1m=[0-9]+(\.[0-9]+)? os=(darwin|linux)$'

P_CORES="$(field "$P" cores)"; P_MEM="$(field "$P" mem_gb)"
P_DISK="$(field "$P" disk_free_gb)"; P_OS="$(field "$P" os)"

expect_true "cores is at least 1"       [ "$P_CORES" -ge 1 ]
expect_true "mem_gb is at least 1"      [ "$P_MEM" -ge 1 ]
expect_true "disk_free_gb is not negative" [ "$P_DISK" -ge 0 ]

case "$(uname -s)" in
  Darwin) expect_eq "os is darwin on this host" "darwin" "$P_OS"
          expect_eq "cores agrees with sysctl hw.ncpu" "$(sysctl -n hw.ncpu)" "$P_CORES"
          expect_eq "mem_gb agrees with sysctl hw.memsize" \
            "$(( $(sysctl -n hw.memsize) / 1073741824 ))" "$P_MEM" ;;
  Linux)  expect_eq "os is linux on this host" "linux" "$P_OS"
          expect_eq "cores agrees with nproc" "$(nproc)" "$P_CORES" ;;
  *)      ok "os arm: host is neither Darwin nor Linux; shape assertions above stand" ;;
esac

# The probe's own numbers must be a legal budget input — the two halves are one pipeline.
PB="$(resources_budget "$P_CORES" "$P_MEM" "$P_DISK")"
expect_match "probe output feeds resources_budget without editing" "$PB" \
  '^writers=[0-9]+ suites=[0-9]+ worktrees=[0-9]+ test_jobs=[0-9]+$'

# ════════════════════════════════════════════════════════════ §D — resources_pressure

section "D — resources_pressure: HOLD and EMERGENCY thresholds (AC-30)"

pressure() {  # <free_mb> <load_1m> <cores>
  BIONIC_PROBE_FREE_MB="$1" BIONIC_PROBE_LOAD_1M="$2" resources_pressure "$3"
}

R="$(pressure 8000 2.0 18)"
expect_eq "ample memory, load well under cores×1.5 → ok" "ok" "$(field "$R" state)"
expect_match "pressure prints all three keys in order" "$R" \
  '^state=(ok|hold|emergency) free_mb=[0-9]+ load_1m=[0-9]+(\.[0-9]+)?$'
expect_eq "pressure echoes the free reading it judged"  "8000" "$(field "$R" free_mb)"
expect_eq "pressure echoes the load reading it judged"  "2.0"  "$(field "$R" load_1m)"

# HOLD arm 1 — free memory below HOLD_FREE_MB (half the 2 GB reserve).
expect_eq "free 1023 MB (below HOLD_FREE_MB) → hold" "hold" \
  "$(field "$(pressure 1023 1.0 18)" state)"
expect_eq "free exactly 1024 MB is not yet hold"     "ok" \
  "$(field "$(pressure 1024 1.0 18)" state)"

# HOLD arm 2 — load above cores × HOLD_LOAD_FACTOR. Strictly above: 18 × 1.5 = 27.
expect_eq "load 27.1 on 18 cores (> 27) → hold" "hold" \
  "$(field "$(pressure 8000 27.1 18)" state)"
expect_eq "load exactly 27.0 on 18 cores is not hold" "ok" \
  "$(field "$(pressure 8000 27.0 18)" state)"
expect_eq "load 26.9 on 18 cores → ok" "ok" \
  "$(field "$(pressure 8000 26.9 18)" state)"
# The factor is per-core, so the same load is fine on a big machine and a hold on a small one.
expect_eq "load 4.0 on 2 cores (> 3) → hold" "hold" \
  "$(field "$(pressure 8000 4.0 2)" state)"
expect_eq "load 4.0 on 18 cores → ok"       "ok" \
  "$(field "$(pressure 8000 4.0 18)" state)"

# EMERGENCY — the kernel-kill floor. Measured: the SIGKILL landed at ~188 MB free.
expect_eq "free 255 MB (below EMERGENCY_FREE_MB) → emergency" "emergency" \
  "$(field "$(pressure 255 1.0 18)" state)"
expect_eq "free 188 MB (the measured kill point) → emergency" "emergency" \
  "$(field "$(pressure 188 1.0 18)" state)"
expect_eq "free exactly 256 MB is hold, not emergency" "hold" \
  "$(field "$(pressure 256 1.0 18)" state)"
# Emergency outranks a merely-high load: the scarcer resource decides.
expect_eq "free 100 MB with a calm load is still emergency" "emergency" \
  "$(field "$(pressure 100 0.1 18)" state)"

# With no overrides it must read the live machine and still answer one of the three states.
R_LIVE="$(resources_pressure "$P_CORES")"
expect_match "live pressure answers a legal state" "$R_LIVE" \
  '^state=(ok|hold|emergency) free_mb=[0-9]+ load_1m=[0-9]+(\.[0-9]+)?$'

# ════════════════════════════════════════════════════════════ §E — attestation v2

section "E — the preflight attestation is version 2 and carries the machine + the budget (AC-25)"

SESSION_A="6c85684c-9588-45a0-bd26-e8c46956c94f"   # fixture-fidelity: SHAPE-ONLY uuid
SESSION_V1="2b7d90aa-51c4-4f8e-9d21-6c0b3ea4517f"  # fixture-fidelity: SHAPE-ONLY uuid

SBX="$TMPROOT/sbx"
mkdir -p "$SBX/home/.claude/projects/proj" "$SBX/repo"
( cd "$SBX/repo" && git init -q . && git config user.email t@e && git config user.name t ) >/dev/null 2>&1
: > "$SBX/home/.claude/projects/proj/$SESSION_A.jsonl"
STATE_REL=".bionic/tmp/preflight-$SESSION_A.state"

run_probe() {  # runs the probe in the sandbox as SESSION_A
  ( cd "$SBX/repo" && \
    HOME="$SBX/home" CLAUDE_CONFIG_DIR="$SBX/home/.claude" \
    ANTHROPIC_API_KEY=fixture-not-a-real-key \
    CLAUDE_CODE_SESSION_ID="$SESSION_A" \
    bash "$PROBE" ) >"$TMPROOT/probe.out" 2>"$TMPROOT/probe.err"
}

run_probe
PRC=$?
expect_true "the probe still exits 0 on a healthy sandbox" [ "$PRC" -eq 0 ]
ATT="$SBX/repo/$STATE_REL"
expect_true "an attestation was written" [ -f "$ATT" ]

att_field() { grep -m1 "^$1=" "$ATT" 2>/dev/null | cut -d= -f2-; }

expect_eq "the attestation declares version 2" "2" "$(att_field version)"
expect_eq "kind is unchanged"      "preflight-attestation" "$(att_field kind)"
expect_eq "session_id is unchanged" "$SESSION_A"           "$(att_field session_id)"

# The five probe fields, by key.
for _k in cores mem_gb disk_free_gb load_1m os; do
  if [ -n "$(att_field "$_k")" ]; then ok "attestation carries $_k"; else bad "attestation carries $_k"; fi
done
expect_match "attestation cores is an integer"  "$(att_field cores)"        '^[0-9]+$'
expect_match "attestation mem_gb is an integer" "$(att_field mem_gb)"       '^[0-9]+$'
expect_match "attestation disk_free_gb is an integer" "$(att_field disk_free_gb)" '^[0-9]+$'
expect_match "attestation load_1m is a number"  "$(att_field load_1m)"      '^[0-9]+(\.[0-9]+)?$'
expect_match "attestation os is darwin or linux" "$(att_field os)"          '^(darwin|linux)$'

# The recorded machine must be THIS machine — the attestation is a record, not a template.
expect_eq "attestation cores match the live probe"  "$P_CORES" "$(att_field cores)"
expect_eq "attestation mem_gb matches the live probe" "$P_MEM"  "$(att_field mem_gb)"

# The budget line, in the same shape the plan frontmatter's `parallel-budget:` carries, so
# WALLS and DOCTOR read one string rather than re-deriving anything (ownership table).
BUD="$(att_field budget)"
expect_match "attestation carries a budget line in parallel-budget shape" "$BUD" \
  '^writers=[0-9]+ suites=[0-9]+ worktrees=[0-9]+ test_jobs=[0-9]+ source=probe$'
expect_eq "the recorded budget is what the library derives from the recorded machine" \
  "$(resources_budget "$(att_field cores)" "$(att_field mem_gb)" "$(att_field disk_free_gb)") source=probe" \
  "$BUD"

# ════════════════════════════════════════════════════════════ §F — the reader takes 1 and 2

section "F — the attestation reader accepts version 1 and version 2 (AC-25)"

read_att() { bash "$PROBE" --read "$1" >"$TMPROOT/read.out" 2>"$TMPROOT/read.err"; }

read_att "$ATT"
expect_true "reader accepts the v2 record it just wrote" [ "$?" -eq 0 ]
expect_true "reader echoes the budget line" grep -q "^budget=" "$TMPROOT/read.out"

# fixture-fidelity: a v1 record — the exact field set hooks/preflight-probe.sh wrote before
# this slice, which tests/preflight-probe.test.sh drives today.
V1="$TMPROOT/preflight-$SESSION_V1.state"
cat > "$V1" <<EOF
# bionic environment attestation — machine-local, safe to delete
version=1
kind=preflight-attestation
session_id=$SESSION_V1
written_at=1756800000
written_at_iso=2026-09-02T12:00:00Z
repo=/somewhere
git_branch=main
git_head=deadbee
git_dirty=0
credential_source=environment
other_sessions=0
EOF

read_att "$V1"
expect_true "reader still accepts a version 1 record" [ "$?" -eq 0 ]
expect_false "a v1 record carries no budget line" grep -q "^budget=" "$TMPROOT/read.out"

# An unknown future version must be refused loudly rather than half-parsed.
V9="$TMPROOT/preflight-v9.state"
sed 's/^version=1$/version=9/' "$V1" > "$V9"
read_att "$V9"
expect_true "reader refuses an unrecognised version" [ "$?" -ne 0 ]
expect_true "the refusal names the version it saw" grep -q '9' "$TMPROOT/read.err"

# A record with no version line at all is not an attestation.
V0="$TMPROOT/preflight-v0.state"
grep -v '^version=' "$V1" > "$V0"
read_att "$V0"
expect_true "reader refuses a record with no version line" [ "$?" -ne 0 ]

read_att "$TMPROOT/definitely-absent.state"
expect_true "reader refuses an absent file" [ "$?" -ne 0 ]

# The read mode must be READ-ONLY: it may not write, prune, or take an attestation.
BEFORE="$(ls "$SBX/repo/.bionic/tmp" | sort | tr '\n' ' ')"
read_att "$ATT"
AFTER="$(ls "$SBX/repo/.bionic/tmp" | sort | tr '\n' ' ')"
expect_eq "--read changes nothing in the state directory" "$BEFORE" "$AFTER"

# ════════════════════════════════════════════════════════════ §G — degraded library

section "G — a missing library degrades the attestation to v1, never blocks the probe (fail-open)"

# Resources are a CONTEXT probe, not a blocking one: a machine whose library cannot be read
# must still be able to take an attestation and dispatch. The honest record of that is a v1
# attestation — the version the reader still accepts — not a v2 with empty fields.
DEG="$TMPROOT/degraded"
mkdir -p "$DEG/hooks" "$DEG/scripts/lib"
cp "$PROBE" "$DEG/hooks/preflight-probe.sh"
# every OTHER lib is present; only resources.sh is missing (mirrors hooks/ + scripts/lib,
# the pattern POKER/4 and ADOPT/9 use for a hook copied out of the shipped tree — without
# this, the loader idiom's own required libs (root.sh, session.sh) are ALSO absent, the
# probe never resolves a project root or session key, and no attestation is written at
# all: the degraded-attestation path is never reached).
cp "$REPO_ROOT/payload/scripts/lib/"*.sh "$DEG/scripts/lib/"
rm -f "$DEG/scripts/lib/resources.sh"
mkdir -p "$DEG/home/.claude/projects/proj" "$DEG/repo"
( cd "$DEG/repo" && git init -q . ) >/dev/null 2>&1
: > "$DEG/home/.claude/projects/proj/$SESSION_A.jsonl"
( cd "$DEG/repo" && \
  HOME="$DEG/home" CLAUDE_CONFIG_DIR="$DEG/home/.claude" \
  ANTHROPIC_API_KEY=fixture-not-a-real-key \
  CLAUDE_CODE_SESSION_ID="$SESSION_A" \
  bash "$DEG/hooks/preflight-probe.sh" ) >"$TMPROOT/deg.out" 2>"$TMPROOT/deg.err"
DRC=$?
expect_true "the probe still exits 0 with the library missing" [ "$DRC" -eq 0 ]
DATT="$DEG/repo/$STATE_REL"
expect_true "an attestation was still written" [ -f "$DATT" ]
expect_eq "the degraded attestation declares version 1" "1" \
  "$(grep -m1 '^version=' "$DATT" 2>/dev/null | cut -d= -f2-)"
expect_false "the degraded attestation carries no budget line" \
  grep -q '^budget=' "$DATT"

# Differential control: put resources.sh BACK into the same tree and re-run against the
# same session id (same DATT path, so a real flip overwrites the v1 record). This proves
# the v1 result above is caused by the missing library, not by some other defect in the
# fixture that would yield v1 regardless — the anti-vacuity pattern L-ROOT/7 names.
cp "$REPO_ROOT/payload/scripts/lib/resources.sh" "$DEG/scripts/lib/resources.sh"
( cd "$DEG/repo" && \
  HOME="$DEG/home" CLAUDE_CONFIG_DIR="$DEG/home/.claude" \
  ANTHROPIC_API_KEY=fixture-not-a-real-key \
  CLAUDE_CODE_SESSION_ID="$SESSION_A" \
  bash "$DEG/hooks/preflight-probe.sh" ) >"$TMPROOT/undeg.out" 2>"$TMPROOT/undeg.err"
URC=$?
expect_true "the probe still exits 0 with the library restored" [ "$URC" -eq 0 ]
expect_eq "restoring resources.sh flips the same attestation to version 2" "2" \
  "$(grep -m1 '^version=' "$DATT" 2>/dev/null | cut -d= -f2-)"
expect_true "the restored attestation carries a budget line" \
  grep -q '^budget=' "$DATT"

# ════════════════════════════════════════════════════════════ report

echo
echo "resources.test.sh: $PASS passed, $FAIL failed, $TOTAL total"
[ "$FAIL" -eq 0 ]
