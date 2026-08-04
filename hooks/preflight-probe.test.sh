#!/bin/bash
# Tests for hooks/preflight-probe.sh — the epic-15 environment check (start-side PRODUCER).
#
# Governing design: design/orchestrator-subagent-coordination.md §4 "The environment check",
# §7 (failure model), §8 (security), §9 (verification strategy).
# Serves AC-1, and the slice-4/1 share of AC-8 and AC-10.
#
# Hermetic: every run happens inside a throwaway sandbox git repo with HOME and
# CLAUDE_CONFIG_DIR redirected into that sandbox. Nothing reads or writes the real
# ~/.claude, the real bionic repo state, or a live wave. The one machine-global source
# the probe consults (the macOS Keychain, via `security`) is substituted by prepending a
# stub directory to PATH — a genuine environment substitution, not a seam inside the
# script under test.
#
# FIXTURE FIDELITY is declared at each fixture site below. The fidelity source is
# .bionic/docs/record/epic-15-kill-interception-experiment.md (CLI 2.1.220 verbatim
# captures); anything not traceable to it is declared shape-only.
#
# Usage: bash hooks/preflight-probe.test.sh

set -uo pipefail

PROBE="$(cd "$(dirname "$0")" && pwd)/preflight-probe.sh"
TMPROOT="$(mktemp -d)"
OUT="$TMPROOT/stdout"; ERR="$TMPROOT/stderr"
PASS=0; FAIL=0; TOTAL=0

cleanup() {
  # sandboxes may contain deliberately unwritable dirs (repo-not-writable case)
  chmod -R u+rwX "$TMPROOT" 2>/dev/null
  rm -rf "$TMPROOT"
}
trap cleanup EXIT

# fixture-fidelity: VERBATIM session_id from record §2.2 (PreToolUse payload on TaskStop,
# CLI 2.1.220). This is the exact string shape the probe must key an attestation to.
SESSION_A="6c85684c-9588-45a0-bd26-e8c46956c94f"
# fixture-fidelity: SHAPE-ONLY. The record captures one session per run, so no second
# verbatim session_id exists. Only "a different, well-formed session id" is load-bearing
# here; the digits are arbitrary.
SESSION_B="1f4a7c02-3bd9-4e15-8a66-90c1de77b204"

# ---------- assertion helpers ----------

ok()   { TOTAL=$((TOTAL+1)); PASS=$((PASS+1)); printf 'PASS: %s\n' "$1"; }
bad()  { TOTAL=$((TOTAL+1)); FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1"
         [ $# -gt 1 ] && printf '      %s\n' "$2"; }

expect_eq() {  # <label> <expected> <actual>
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected [$2] got [$3]"; fi
}
expect_true() {  # <label> <cmd...>
  local label="$1"; shift
  if "$@"; then ok "$label"; else bad "$label" "condition failed: $*"; fi
}
expect_false() {  # <label> <cmd...>
  local label="$1"; shift
  if "$@"; then bad "$label" "condition unexpectedly true: $*"; else ok "$label"; fi
}
expect_match() {  # <label> <regex> <file>
  if [ ! -f "$3" ]; then bad "$1" "file absent: $3"; return; fi
  if grep -qE "$2" "$3"; then ok "$1"; else bad "$1" "no match for /$2/ in $(basename "$3")"; fi
}
# A missing file must never satisfy a "must not contain" assertion — that is the
# fixture-pins-away-the-test class this wave exists to avoid.
expect_nomatch() {  # <label> <regex> <file>
  if [ ! -f "$3" ]; then bad "$1" "file absent: $3"; return; fi
  if grep -qE "$2" "$3"; then bad "$1" "unexpected match for /$2/"; else ok "$1"; fi
}

section() { printf '\n=== %s ===\n' "$1"; }

# ---------- sandbox ----------

# fixture-fidelity: the transcript layout <config-dir>/projects/<project-slug>/<session_id>.jsonl
# is VERBATIM from record §2.2 (`transcript_path`). The slug string itself is shape-only —
# the probe locates the project directory by finding the one that contains its own
# transcript, so the slug's spelling is deliberately not depended upon.
PROJSLUG="-sandbox-repo"

mk_sandbox() {  # echoes the sandbox root
  local d; d="$(mktemp -d "$TMPROOT/sbx.XXXXXX")"
  mkdir -p "$d/repo" "$d/home" "$d/config/projects/$PROJSLUG"
  git -C "$d/repo" init -q -b main >/dev/null 2>&1
  # credential source 2: a credentials file under the (sandboxed) config dir
  printf '{}' > "$d/config/.credentials.json"
  : > "$d/config/projects/$PROJSLUG/$SESSION_A.jsonl"
  printf '%s' "$d"
}

STATE_REL=".bionic/tmp/preflight.state"

run_probe() {  # <sandbox> [KEY=VAL ...] -> echoes exit code; stdout/stderr in $OUT/$ERR
  local sbx="$1"; shift
  ( cd "$sbx/repo" && env -u ANTHROPIC_API_KEY \
      HOME="$sbx/home" \
      CLAUDE_CONFIG_DIR="$sbx/config" \
      CLAUDE_CODE_SESSION_ID="$SESSION_A" \
      "$@" bash "$PROBE" ) >"$OUT" 2>"$ERR"
  echo $?
}

stub_dir() {  # <sandbox> <security-exit-code> -> echoes a PATH prefix with a `security` stub
  local sbx="$1"; local rc="$2"; local d="$sbx/stubs"
  mkdir -p "$d"
  printf '#!/bin/bash\nexit %s\n' "$rc" > "$d/security"
  chmod +x "$d/security"
  printf '%s' "$d:$PATH"
}

# ============================================================
section "S1 — positive pair: passing environment writes the attestation (AC-1)"
# ============================================================

expect_true "the probe script exists" [ -f "$PROBE" ]

SBX="$(mk_sandbox)"
rc="$(run_probe "$SBX")"
expect_eq "clean environment exits 0" "0" "$rc"
expect_true "attestation written at .bionic/tmp/preflight.state" [ -f "$SBX/repo/$STATE_REL" ]
expect_true "attestation is a regular file, not a symlink" [ ! -L "$SBX/repo/$STATE_REL" ]
expect_match "attestation carries a version line (A6)" '^version=[0-9]+$' "$SBX/repo/$STATE_REL"
expect_match "attestation is keyed to this session" "^session_id=$SESSION_A\$" "$SBX/repo/$STATE_REL"
expect_match "attestation names the repo it describes" '^repo=/' "$SBX/repo/$STATE_REL"
expect_match "attestation records when it was written" '^written_at=[0-9]+$' "$SBX/repo/$STATE_REL"
expect_match "stdout reports the credential probe" 'credential' "$OUT"
expect_match "stdout reports the state-dir probe" 'state dir' "$OUT"
expect_eq "attestation mode is 0600" "600" "$(stat -f '%OLp' "$SBX/repo/$STATE_REL" 2>/dev/null || stat -c '%a' "$SBX/repo/$STATE_REL")"

# every content line is key=value (A6: no fixed-field-order positional record)
_badlines="$(grep -vE '^(#|[a-z][a-z0-9_]*=)' "$SBX/repo/$STATE_REL" | grep -v '^$' | head -3)"
expect_eq "every attestation line is a comment or key=value (A6)" "" "$_badlines"

# no temp debris left behind
_debris="$(find "$SBX/repo/.bionic/tmp" -name 'preflight.state.*' 2>/dev/null | head -3)"
expect_eq "no temp files left in the state dir" "" "$_debris"
_lock="$(find "$SBX/repo/.bionic/tmp" -name '.preflight.lock' 2>/dev/null | head -1)"
expect_eq "state lock released on the success path" "" "$_lock"

# credential source 1: the environment variable, with no credentials file present
SBX2="$(mk_sandbox)"; rm -f "$SBX2/config/.credentials.json"
rc="$(run_probe "$SBX2" PATH="$(stub_dir "$SBX2" 1)" ANTHROPIC_API_KEY=sk-fixture-marker-0001)"
expect_eq "credential satisfied by ANTHROPIC_API_KEY alone" "0" "$rc"

# credential source 3: the macOS keychain, via a substituted `security`
SBX3="$(mk_sandbox)"; rm -f "$SBX3/config/.credentials.json"
rc="$(run_probe "$SBX3" PATH="$(stub_dir "$SBX3" 0)")"
expect_eq "credential satisfied by the keychain source alone" "0" "$rc"

# re-run over an attestation carrying unknown extra fields in a different order (A6
# forward-compatibility: the record must not be parsed positionally)
SBX4="$(mk_sandbox)"
mkdir -p "$SBX4/repo/.bionic/tmp"
printf 'unknown_future_field=x\nsession_id=%s\nversion=1\nrepo=/somewhere\n' "$SESSION_B" \
  > "$SBX4/repo/$STATE_REL"
rc="$(run_probe "$SBX4")"
expect_eq "re-run over a reordered/extended prior record exits 0" "0" "$rc"
expect_match "re-run replaces the foreign record with this session's" "^session_id=$SESSION_A\$" "$SBX4/repo/$STATE_REL"
expect_nomatch "re-run does not leave the foreign session key behind" "^session_id=$SESSION_B\$" "$SBX4/repo/$STATE_REL"

# ============================================================
section "S2 — blocking failure writes nothing and destroys the prior stamp (AC-1)"
# ============================================================

# credential missing: no env var, no credentials file, keychain lookup fails
SBX="$(mk_sandbox)"; rm -f "$SBX/config/.credentials.json"
rc="$(run_probe "$SBX" PATH="$(stub_dir "$SBX" 1)")"
expect_eq "missing credential exits 1" "1" "$rc"
expect_false "missing credential writes no attestation" [ -e "$SBX/repo/$STATE_REL" ]
if grep -qE 'credential' "$OUT" "$ERR" 2>/dev/null; then ok "failure output names the credential probe"
else bad "failure output names the credential probe"; fi

# the founding invariant: a prior PASS must not outlive the environment it described
SBX="$(mk_sandbox)"
rc="$(run_probe "$SBX")"
expect_eq "prior attestation established" "0" "$rc"
expect_true "prior attestation on disk before the failing run" [ -f "$SBX/repo/$STATE_REL" ]
rm -f "$SBX/config/.credentials.json"
rc="$(run_probe "$SBX" PATH="$(stub_dir "$SBX" 1)")"
expect_eq "failing re-run exits 1" "1" "$rc"
expect_false "failing re-run DELETED the prior attestation" [ -e "$SBX/repo/$STATE_REL" ]

# state directory not creatable: .bionic occupied by a regular file
SBX="$(mk_sandbox)"
printf 'not a directory' > "$SBX/repo/.bionic"
rc="$(run_probe "$SBX")"
expect_eq "uncreatable state dir exits 1" "1" "$rc"
if grep -qE 'state dir' "$OUT" "$ERR" 2>/dev/null; then ok "failure output names the state-dir probe"
else bad "failure output names the state-dir probe"; fi

# repo not writable (state dir pre-created and left writable, so the delete path still runs)
SBX="$(mk_sandbox)"
rc="$(run_probe "$SBX")"
expect_eq "attestation established before making the repo read-only" "0" "$rc"
chmod 500 "$SBX/repo"
rc="$(run_probe "$SBX")"
chmod 700 "$SBX/repo"
expect_eq "unwritable repo exits 1" "1" "$rc"
expect_false "unwritable repo leaves no attestation" [ -e "$SBX/repo/$STATE_REL" ]

# C2 (Step-6 correctness review, slice 4/7). THE STATE DIRECTORY ITSELF is the
# failing blocking probe. The delete-on-fail obligation holds here too: a
# directory can be readable-but-not-writable while holding a perfectly readable
# prior attestation, and the start gate reads that file and passes — a stale pass
# outliving the environment it described (§7 row 5, AC-1, checklist A5). The
# fixture above deliberately keeps the state dir writable "so the delete path
# still runs", which is exactly the branch that had no coverage.
SBX="$(mk_sandbox)"
rc="$(run_probe "$SBX")"
expect_eq "attestation established before making the STATE DIR read-only" "0" "$rc"
chmod 500 "$SBX/repo/.bionic/tmp"
rc="$(run_probe "$SBX")"
chmod 700 "$SBX/repo/.bionic/tmp"
expect_eq "unwritable state dir exits 1" "1" "$rc"
if grep -q '^session_id=' "$SBX/repo/$STATE_REL" 2>/dev/null; then
  bad "an unwritable state dir leaves NO usable prior attestation (C2)" \
      "the prior attestation survived a blocking failure and still keys this session"
else
  ok "an unwritable state dir leaves NO usable prior attestation (C2)"
fi
expect_match "the state-dir failure says what happened to the prior attestation" \
  'deleted or emptied|could' "$ERR"

# ============================================================
section "S3 — no session key REFUSES (AC-10 / design §7)"
# ============================================================

SBX="$(mk_sandbox)"
rc="$(run_probe "$SBX" CLAUDE_CODE_SESSION_ID=)"
expect_eq "empty session key exits 3 (REFUSE)" "3" "$rc"
expect_false "refused run writes no attestation" [ -e "$SBX/repo/$STATE_REL" ]
if grep -qiE 'session' "$ERR" "$OUT" 2>/dev/null; then ok "refusal explains the missing session key"
else bad "refusal explains the missing session key"; fi

# the refusal is a producer-side refusal, not a probe failure: it touches no state at all
SBX="$(mk_sandbox)"
rc="$(run_probe "$SBX")"
expect_eq "attestation established before the unkeyed run" "0" "$rc"
_before="$(cat "$SBX/repo/$STATE_REL")"
rc="$(run_probe "$SBX" CLAUDE_CODE_SESSION_ID=)"
expect_eq "unkeyed re-run exits 3" "3" "$rc"
expect_eq "unkeyed run leaves existing state byte-identical" "$_before" "$(cat "$SBX/repo/$STATE_REL" 2>/dev/null)"

# ============================================================
section "S4 — hostile repo: symlinks and unpredictable temp names (AC-8 / design §8)"
# ============================================================

# file-level symlink plant
SBX="$(mk_sandbox)"
mkdir -p "$SBX/repo/.bionic/tmp"
printf 'ORIGINAL' > "$SBX/victim.txt"
ln -s "$SBX/victim.txt" "$SBX/repo/$STATE_REL"
rc="$(run_probe "$SBX")"
expect_eq "planted file symlink is refused (exit 2)" "2" "$rc"
expect_eq "symlink target NOT written through" "ORIGINAL" "$(cat "$SBX/victim.txt")"
expect_false "the planted link does not survive as an attestation" [ -e "$SBX/repo/$STATE_REL" ]

# directory-level symlink plant
SBX="$(mk_sandbox)"
mkdir -p "$SBX/repo/.bionic" "$SBX/outside"
ln -s "$SBX/outside" "$SBX/repo/.bionic/tmp"
rc="$(run_probe "$SBX")"
expect_eq "planted dir symlink is refused (exit 2)" "2" "$rc"
_outside="$(find "$SBX/outside" -type f 2>/dev/null | head -3)"
expect_eq "nothing written into the symlinked-away directory" "" "$_outside"

# directory-level symlink that stays INSIDE the repo. This case is what makes the
# component symlink check independently load-bearing: an in-repo redirect passes any
# containment test, so only the -L check can refuse it.
SBX="$(mk_sandbox)"
mkdir -p "$SBX/repo/.bionic" "$SBX/repo/decoy"
ln -s "$SBX/repo/decoy" "$SBX/repo/.bionic/tmp"
rc="$(run_probe "$SBX")"
expect_eq "in-repo dir symlink is refused (exit 2)" "2" "$rc"
_decoy="$(find "$SBX/repo/decoy" -type f 2>/dev/null | head -3)"
expect_eq "nothing written into the in-repo decoy directory" "" "$_decoy"

# ancestor symlink: .bionic itself redirected outside the repo
SBX="$(mk_sandbox)"
mkdir -p "$SBX/elsewhere"
ln -s "$SBX/elsewhere" "$SBX/repo/.bionic"
rc="$(run_probe "$SBX")"
expect_eq "ancestor symlink is refused (exit 2)" "2" "$rc"
_elsewhere="$(find "$SBX/elsewhere" -type f 2>/dev/null | head -3)"
expect_eq "nothing written through the ancestor symlink" "" "$_elsewhere"

# attestation path occupied by a directory — a real, seam-free write-failure condition
SBX="$(mk_sandbox)"
mkdir -p "$SBX/repo/$STATE_REL/subdir"
rc="$(run_probe "$SBX")"
expect_eq "attestation path occupied by a directory exits 2" "2" "$rc"
expect_false "no readable attestation results from the occupied path" [ -f "$SBX/repo/$STATE_REL" ]

# credential material must never reach the record or the operator output (credential-leak class)
SBX="$(mk_sandbox)"
rc="$(run_probe "$SBX" ANTHROPIC_API_KEY=sk-ant-fixture-SECRET-9f2b)"
expect_eq "run with a credential in the environment exits 0" "0" "$rc"
expect_nomatch "credential value absent from the attestation" 'SECRET-9f2b' "$SBX/repo/$STATE_REL"
expect_nomatch "credential value absent from stdout" 'SECRET-9f2b' "$OUT"
expect_nomatch "credential value absent from stderr" 'SECRET-9f2b' "$ERR"

# static regression pins for the A2 defect class (predictable "$$"-derived temp names)
expect_true "temp files are created with mktemp" grep -q 'mktemp' "$PROBE"
expect_nomatch 'no \$\$-derived temp filename (A2)' '\.tmp\.\$\$|\$\$\.tmp|\$\{?\$\}?"?\.' "$PROBE"
expect_match "mktemp template uses XXXXXX" 'mktemp[^|&;]*XXXXXX' "$PROBE"

# ============================================================
section "S5 — locking against racing writers (A4)"
# ============================================================

SBX="$(mk_sandbox)"
mkdir -p "$SBX/repo/.bionic/tmp/.preflight.lock"
rc="$(run_probe "$SBX")"
expect_eq "a held lock yields exit 4, not a racing write" "4" "$rc"
expect_false "a held lock leaves no attestation behind" [ -e "$SBX/repo/$STATE_REL" ]
rmdir "$SBX/repo/.bionic/tmp/.preflight.lock"

# two writers in parallel: the survivor's record must be whole, never interleaved
SBX="$(mk_sandbox)"
( cd "$SBX/repo" && env -u ANTHROPIC_API_KEY HOME="$SBX/home" CLAUDE_CONFIG_DIR="$SBX/config" \
    CLAUDE_CODE_SESSION_ID="$SESSION_A" bash "$PROBE" ) >/dev/null 2>&1 &
p1=$!
( cd "$SBX/repo" && env -u ANTHROPIC_API_KEY HOME="$SBX/home" CLAUDE_CONFIG_DIR="$SBX/config" \
    CLAUDE_CODE_SESSION_ID="$SESSION_B" bash "$PROBE" ) >/dev/null 2>&1 &
p2=$!
wait $p1; wait $p2
expect_true "a record exists after two parallel writers" [ -f "$SBX/repo/$STATE_REL" ]
expect_eq "exactly one session line survives (no interleaving)" "1" "$(grep -c '^session_id=' "$SBX/repo/$STATE_REL")"
expect_eq "exactly one version line survives (no interleaving)" "1" "$(grep -c '^version=' "$SBX/repo/$STATE_REL")"
_debris="$(find "$SBX/repo/.bionic/tmp" -name 'preflight.state.*' 2>/dev/null | head -3)"
expect_eq "parallel writers leave no temp debris" "" "$_debris"

# ============================================================
section "S6 — context probes never block (design §4)"
# ============================================================

SBX="$(mk_sandbox)"
rc="$(run_probe "$SBX")"
expect_match "git baseline recorded in the attestation" '^git_branch=' "$SBX/repo/$STATE_REL"
expect_match "git head recorded in the attestation" '^git_head=' "$SBX/repo/$STATE_REL"
expect_match "git baseline reported to the operator" 'git' "$OUT"

# a non-git directory is a context miss, never a block
SBX="$(mk_sandbox)"
rm -rf "$SBX/repo/.git"
rc="$(run_probe "$SBX")"
expect_eq "non-git working directory still exits 0" "0" "$rc"
expect_true "non-git run still writes an attestation" [ -f "$SBX/repo/$STATE_REL" ]

# other-session scan: warn-only, names the other session, never blocks
SBX="$(mk_sandbox)"
: > "$SBX/config/projects/$PROJSLUG/$SESSION_B.jsonl"
rc="$(run_probe "$SBX")"
expect_eq "another live session does not block the check" "0" "$rc"
if grep -qE "WARN.*$SESSION_B" "$OUT" "$ERR" 2>/dev/null; then ok "other live session warned by identity"
else bad "other live session warned by identity" "expected a WARN naming $SESSION_B"; fi

# an old transcript is not a live session
SBX="$(mk_sandbox)"
: > "$SBX/config/projects/$PROJSLUG/$SESSION_B.jsonl"
touch -t 202601010000 "$SBX/config/projects/$PROJSLUG/$SESSION_B.jsonl"
rc="$(run_probe "$SBX")"
expect_eq "stale transcript still exits 0" "0" "$rc"
expect_nomatch "stale transcript raises no live-session warning" "WARN.*$SESSION_B" "$OUT"

# our own transcript is never reported as somebody else
SBX="$(mk_sandbox)"
rc="$(run_probe "$SBX")"
expect_nomatch "own session never warned about" "WARN.*$SESSION_A" "$OUT"

# ============================================================
section "S7 — mutation-and-restore proofs (design §9, checklist A5/A2)"
# ============================================================

ORIG_SUM="$(shasum "$PROBE" | awk '{print $1}')"

mutate() {  # <label> <awk-or-sed marker> — echoes path of a mutated COPY, or empty on no-op
  local out="$TMPROOT/mutant-$1.sh"
  case "$1" in
    failmv)   sed 's|^\( *\)mv -f "\$tmp"|\1false "$tmp"|' "$PROBE" > "$out" ;;
    showtmp)  awk '{print} /tmp="\$\(mktemp/ {print "  printf \"TMPNAME=%s\\n\" \"$tmp\" >&2"}' "$PROBE" > "$out" ;;
  esac
  if cmp -s "$out" "$PROBE"; then printf ''; else printf '%s' "$out"; fi
}

# A5: a write failure must leave NO attestation — not the new one, not the prior one.
MUT="$(mutate failmv)"
if [ -z "$MUT" ]; then
  bad "mutation 'failmv' changed the script" "sed matched nothing — the write step moved"
else
  ok "mutation 'failmv' changed the script"
  SBX="$(mk_sandbox)"
  rc="$(run_probe "$SBX")"
  expect_eq "prior attestation established for the write-failure proof" "0" "$rc"
  rc="$( ( cd "$SBX/repo" && env -u ANTHROPIC_API_KEY HOME="$SBX/home" \
            CLAUDE_CONFIG_DIR="$SBX/config" CLAUDE_CODE_SESSION_ID="$SESSION_A" \
            bash "$MUT" ) >"$OUT" 2>"$ERR"; echo $?)"
  expect_eq "write failure exits 2, never 1 (A5 doc/behavior split)" "2" "$rc"
  expect_false "write failure leaves NO stale stamp (A5)" [ -e "$SBX/repo/$STATE_REL" ]
  _debris="$(find "$SBX/repo/.bionic/tmp" -name 'preflight.state.*' 2>/dev/null | head -3)"
  expect_eq "write failure leaves no temp debris" "" "$_debris"
  _lock="$(find "$SBX/repo/.bionic/tmp" -name '.preflight.lock' 2>/dev/null | head -1)"
  expect_eq "write failure releases the state lock" "" "$_lock"
fi

# AC-8: temp names are unpredictable — two runs, two unrelated names.
MUT="$(mutate showtmp)"
if [ -z "$MUT" ]; then
  bad "mutation 'showtmp' changed the script" "awk matched nothing — the mktemp step moved"
else
  ok "mutation 'showtmp' changed the script"
  SBX="$(mk_sandbox)"
  n1="$( ( cd "$SBX/repo" && env -u ANTHROPIC_API_KEY HOME="$SBX/home" \
            CLAUDE_CONFIG_DIR="$SBX/config" CLAUDE_CODE_SESSION_ID="$SESSION_A" \
            bash "$MUT" ) 2>&1 >/dev/null | grep '^TMPNAME=' | head -1)"
  n2="$( ( cd "$SBX/repo" && env -u ANTHROPIC_API_KEY HOME="$SBX/home" \
            CLAUDE_CONFIG_DIR="$SBX/config" CLAUDE_CODE_SESSION_ID="$SESSION_A" \
            bash "$MUT" ) 2>&1 >/dev/null | grep '^TMPNAME=' | head -1)"
  expect_true "temp name captured on run 1" [ -n "$n1" ]
  expect_true "temp name captured on run 2" [ -n "$n2" ]
  expect_false "two runs produce different temp names (AC-8)" [ "$n1" = "$n2" ]
  if printf '%s' "$n1" | grep -qE 'preflight\.state\.[A-Za-z0-9]{6}$'; then
    ok "temp name carries a 6-character random suffix"
  else bad "temp name carries a 6-character random suffix" "got [$n1]"; fi
fi

expect_eq "the script under test is byte-identical after mutation testing" \
  "$ORIG_SUM" "$(shasum "$PROBE" | awk '{print $1}')"

# ============================================================
section "S8 — documented exit codes match the code (A5) and hot-path hygiene (A7)"
# ============================================================

_doc_codes="$(grep -oE '^#[[:space:]]+exit [0-9]+' "$PROBE" | grep -oE '[0-9]+' | sort -u | tr '\n' ' ')"
_code_codes="$(grep -vE '^[[:space:]]*#' "$PROBE" | grep -oE '(^|[^[:alnum:]_])exit [0-9]+' \
  | grep -oE '[0-9]+' | sort -u | tr '\n' ' ')"
expect_true "the script documents its exit codes" [ -n "$_doc_codes" ]
expect_eq "documented exit codes == reachable exit codes (A5)" "$_doc_codes" "$_code_codes"

# A7's surface is the always-on gates, not this once-per-session producer; pin that the
# producer never grows a plan-directory walk of its own.
expect_nomatch "the producer performs no plan-directory walk (A7)" 'docs/plans' "$PROBE"

expect_true "script is bash and runs under set -u" grep -q '^set -u' "$PROBE"

# ============================================================
printf '\n──────────────────────────────────────────────\n'
printf 'preflight-probe.test.sh: %d passed, %d failed, %d total\n' "$PASS" "$FAIL" "$TOTAL"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
