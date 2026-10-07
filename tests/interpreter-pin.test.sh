#!/bin/bash
# tests/interpreter-pin.test.sh — the interpreter pin, the environment stamp, and the
# runner's stderr-strict arm (wave-01 verification-cannot-lie, task S2; spec AC-1, AC-2,
# AC-3, AC-10, and the runner half of AC-14).
#
# WHAT THE PIN IS. Every payload script and hook pins `#!/bin/bash` — bash 3.2 on a Mac —
# and the CLI runs a hook by path, so the shebang chooses the interpreter. The suites,
# though, type `bash "$HOOK"`, which picks up whatever `bash` is first on PATH: Homebrew
# 5.3 on this machine. A green run the default way therefore proved the payload under an
# interpreter it is never executed with (ADR-001, "one interpreter: the shebang is the
# contract"). `tests/run.sh` now launches every child with a one-entry LAUNCH DIRECTORY
# first on PATH whose only entry is `bash -> /bin/bash`; the rest of PATH is the caller's
# own, so `jq`, `git` and `claude` still resolve exactly where they did.
#
# ITS NAME IS "THE INTERPRETER PIN", never "the PATH shim" (design ledger now-4: v1 wave 0
# deletes an unrelated omnigent piece by that name, and two mechanisms sharing one name is
# how a reader ends up reading the wrong file).
#
# WHY A SUITE OF ITS OWN. A verification instrument must be proven to CATCH what it exists
# to catch. §3 plants two constructs that are MEASURED divergences between 3.2 and 5.x —
# not guesses:
#
#   (a) the quoted-`$( )`-inside-`case` leak: 3.2's parser ends the command substitution at
#       the first `)` of a `case` pattern and leaks the remainder as literal text, so the
#       function returns garbage and exits 0 — a green for the wrong reason;
#   (b) the here-string temporary-assignment divergence (research-code-map §4.e, measured
#       there for the first time): in `VAR=x cmd <<< "$(f)"` the temporary assignment IS in
#       effect while the here-string's command substitution expands under 3.2 and is NOT
#       under 5.3, so `f` runs under the stripped PATH and the here-string arrives empty.
#       This is the live defect behind `jq: command not found` in the recorded 3.2 baseline
#       and behind tests/patrol-revive.test.sh:264.
#
# Each planted suite asserts the 5.x answer. Driven through the pinned runner both go RED;
# run directly under the machine's other interpreter both go GREEN. A pin that stopped
# pinning would show up here as two suites that quietly started passing.
#
# THE SECOND INTERPRETER IS DISCOVERED, NOT ASSUMED. Rows that need a bash whose version
# differs from /bin/bash's are SKIPPED, loudly and by name, on a host that has only one —
# a Linux box where /bin/bash is 5.x has nothing to compare against, and a row that cannot
# be driven must say so rather than pass.
#
# HERMETIC. Every runner drive below is against a SCRATCH TREE (the shipped tests/run.sh,
# byte for byte, over a tests/ directory holding only this suite's own probe files — the
# roster is derived from the directory, so nothing needs rewriting) under this suite's own
# mktemp root, with the pressure ring and clock pinned. Nothing here runs the real roster —
# that would recurse into this very file.
#
# Usage: bash tests/interpreter-pin.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"
REPO="$BIONIC_SCRIPTS_DIR"

SKIPPED=0
skip() { SKIPPED=$((SKIPPED + 1)); echo "SKIP: $1"; [ -n "${2:-}" ] && echo "      $2"; return 0; }

TMPROOT="$(mktemp -d "${TMPDIR:-/tmp}/interpreter-pin-test.XXXXXX")"
trap 'chmod -R -N "$TMPROOT" 2>/dev/null; rm -rf "$TMPROOT"' EXIT   # an ACL row's entry never outlives the run (T57)

SYS_BASH="/bin/bash"
SYS_VER="$("$SYS_BASH" -c 'echo "$BASH_VERSION"' 2>/dev/null)"

# The other interpreter, if this host has one: any bash whose $BASH_VERSION differs from
# /bin/bash's. Homebrew's is looked at first because that is what this machine has; the
# rest of the search is whatever `type -ap` can see.
find_alt_bash() {
  local c v
  for c in /opt/homebrew/bin/bash /usr/local/bin/bash $(type -ap bash 2>/dev/null); do
    [ -x "$c" ] || continue
    v="$("$c" -c 'echo "$BASH_VERSION"' 2>/dev/null)"
    [ -n "$v" ] || continue
    if [ "$v" != "$SYS_VER" ]; then printf '%s' "$c"; return 0; fi
  done
  return 1
}
ALT_BASH="$(find_alt_bash)" || ALT_BASH=""
ALT_VER=""
ALT_DIR="$TMPROOT/alt-bin"
mkdir -p "$ALT_DIR"
if [ -n "$ALT_BASH" ]; then
  ALT_VER="$("$ALT_BASH" -c 'echo "$BASH_VERSION"')"
  ln -sf "$ALT_BASH" "$ALT_DIR/bash"
fi

echo "=== interpreter-pin: /bin/bash is ${SYS_VER:-unknown}; other interpreter: ${ALT_BASH:-none} ${ALT_VER}"
echo ""

# ── the scratch tree ─────────────────────────────────────────────────────────
# The shipped runner, byte for byte. Same layout the runner resolves against: it derives
# $REPO from its own path and sources $REPO/payload/scripts/lib/resources.sh, and
# tests/lib/resolve-roots.sh sits beside it.
#
# THE ROSTER IS THE TREE (fixit 1.5.1). The runner derives its roster from the tests/
# directory it is run in, so a drive's roster is exactly the probe files planted below
# and no rewrite is needed — the copy is the shipped file, unedited. These trees carry
# no tests/lib/assert.sh, so the roster wall's framework half is inert here and the
# probes are raw interpreter probes rather than framework clients, which is what they
# have to be: §3 runs two of them directly under a second interpreter.
mk_tree() {  # mk_tree <dir>
  local dir="$1"
  mkdir -p "$dir/tests/lib" "$dir/payload/scripts/lib"
  cp "$REPO/tests/run.sh" "$dir/tests/run.sh"
  cp "$REPO/tests/lib/resolve-roots.sh" "$dir/tests/lib/resolve-roots.sh"
  cp "$REPO"/payload/scripts/lib/*.sh "$dir/payload/scripts/lib/" 2>/dev/null
}

# drive <tree> <mode|""> — run the scratch runner with the ALTERNATE interpreter first on
# PATH (the hostile case: a foreign `bash` is what `bash tests/…` would otherwise pick),
# leaving DRV_OUT and DRV_RC behind. The pin marker is unset first: this very suite may be
# running under the real runner, which exports it, and an inherited marker would make the
# hand-run rows below vacuous.
DRV_OUT=""; DRV_RC=0
drive() {
  local tree="$1" mode="${2:-}"
  DRV_OUT="$( cd "$tree" && \
    unset BIONIC_TEST_INTERPRETER_PINNED && \
    PATH="$ALT_DIR:$PATH" \
    BIONIC_PRESSURE_RING="$TMPROOT/ring" \
    BIONIC_NOW_EPOCH="1700000000" \
    BIONIC_TEST_JOBS_CEILING="2" \
    BIONIC_PROBE_OUT="$TMPROOT/probe.out" \
    bash tests/run.sh ${mode:+"$mode"} 2>&1 )"
  DRV_RC=$?
}

section "§1 the pin: every child of the runner is /bin/bash, and the rest of PATH is intact (AC-1)"
#
# The probe is a real suite in the roster. It cannot report through stdout — the runner
# prints a passing suite's captured output nowhere — so it writes the facts it reads to
# $BIONIC_PROBE_OUT, which the runner passes through by inheriting this suite's environment.

PROBE_TREE="$TMPROOT/probe-tree"
mk_tree "$PROBE_TREE"
cat > "$PROBE_TREE/tests/probe.test.sh" <<'PROBE_EOF'
#!/bin/bash
{ echo "BASH_VERSION=$BASH_VERSION"
  echo "bash=$(command -v bash 2>/dev/null || echo MISSING)"
  echo "git=$(command -v git 2>/dev/null || echo MISSING)"
  echo "first_path_entry=${PATH%%:*}"
  echo "bash_target=$(readlink "$(command -v bash 2>/dev/null)" 2>/dev/null || echo NONE)"
} > "$BIONIC_PROBE_OUT"
exit 0
PROBE_EOF

HOST_GIT="$(command -v git 2>/dev/null || echo MISSING)"

for MODE in "--serial" ""; do
  MODE_NAME="parallel"; [ -n "$MODE" ] && MODE_NAME="serial"
  : > "$TMPROOT/probe.out"
  drive "$PROBE_TREE" "$MODE"
  P_OUT="$(cat "$TMPROOT/probe.out" 2>/dev/null)"
  P_VER="$(printf '%s\n' "$P_OUT" | sed -n 's/^BASH_VERSION=//p')"
  P_BASH="$(printf '%s\n' "$P_OUT" | sed -n 's/^bash=//p')"
  P_GIT="$(printf '%s\n' "$P_OUT" | sed -n 's/^git=//p')"
  P_FIRST="$(printf '%s\n' "$P_OUT" | sed -n 's/^first_path_entry=//p')"

  expect_eq "1.1 ($MODE_NAME) the probe suite ran at all (not vacuous)" "0" "$DRV_RC"
  expect_eq "1.2 ($MODE_NAME) the suite's interpreter is the system one" "$SYS_VER" "$P_VER"
  expect_eq "1.3 ($MODE_NAME) \`bash\` inside a suite resolves through the launch directory" \
    "$P_FIRST/bash" "$P_BASH"
  if [ -n "$ALT_BASH" ]; then
    expect_ne "1.3b ($MODE_NAME) …a directory the RUNNER put ahead of the caller's own PATH" \
      "$ALT_DIR" "$P_FIRST"
  else
    skip "1.3b ($MODE_NAME) the launch directory is the runner's, not the caller's" "this host has only one bash"
  fi
  expect_eq "1.4 ($MODE_NAME) …and that entry is /bin/bash" "$SYS_BASH" \
    "$(printf '%s\n' "$P_OUT" | sed -n 's/^bash_target=//p')"
  expect_eq "1.5 ($MODE_NAME) the rest of PATH is the caller's own: git resolves where it did" \
    "$HOST_GIT" "$P_GIT"
  # NON-VACUITY: the drive really did put a foreign interpreter first, so 1.2 is the pin
  # answering and not "there is only one bash on this machine".
  if [ -n "$ALT_BASH" ]; then
    expect_ne "1.6 ($MODE_NAME) …and the interpreter the drive offered was NOT the system one" \
      "$SYS_VER" "$ALT_VER"
  else
    skip "1.6 ($MODE_NAME) the drive offered a foreign interpreter" "this host has only one bash"
  fi
done
echo ""

section "§2 hand-run parity: a suite invoked by hand re-execs once under /bin/bash (AC-2)"
#
# The seam every suite already sources does the work, so a suite typed at a prompt under
# another interpreter lands on the same one the runner would have given it. The guard is the
# RUNNING INTERPRETER, not a marker: after `exec /bin/bash "$0"`, `$BASH` is `/bin/bash`, so
# the re-exec happens exactly once and can never loop (critic K-4, Step 6).

# THE CHILDREN, NOT ONLY THE SUITE (wave-27 T81). The seam once re-executed the suite and
# pinned nothing for what it starts, so a hand-run suite was 3.2 while every `bash "$HOOK"`
# it ran took PATH's 5.3 — the world tests/run.sh never gives a suite. The probe therefore
# also records what a child `bash -c` and a child `bash <a hook copy>` report, and the PATH
# its children are handed. The hook copy is a real hook with one line put after its shebang
# that prints the interpreter and exits.
HOOK_COPY="$TMPROOT/hook-copy.sh"
{ head -1 "$BIONIC_HOOKS_DIR/session-poker.sh"
  printf 'printf "%%s\\n" "$BASH_VERSION"; exit 0\n'
  tail -n +2 "$BIONIC_HOOKS_DIR/session-poker.sh"
} > "$HOOK_COPY"

mk_hand() {  # mk_hand <seam> <file> — a hand-run suite that sources <seam>
  { printf '#!/bin/bash\n'
    printf 'echo start >> "$HAND_COUNT"\n'
    printf '. "%s"\n' "$1"
    cat <<'HAND_EOF'
echo "BASH_VERSION=$BASH_VERSION" > "$HAND_OUT"
echo "argv=$*" >> "$HAND_OUT"
echo "roots=$BIONIC_HOOKS_DIR" >> "$HAND_OUT"
echo "child=$(bash -c 'echo "$BASH_VERSION"' 2>/dev/null)" >> "$HAND_OUT"
echo "hook=$(bash "$HAND_HOOK" 2>/dev/null)" >> "$HAND_OUT"
echo "first_target=$(readlink "${PATH%%:*}/bash" 2>/dev/null || echo NONE)" >> "$HAND_OUT"
echo "rest=${PATH#*:}" >> "$HAND_OUT"
echo "git=$(command -v git 2>/dev/null || echo MISSING)" >> "$HAND_OUT"
echo "jq=$(command -v jq 2>/dev/null || echo MISSING)" >> "$HAND_OUT"
HAND_EOF
  } > "$2"
  chmod +x "$2"
}
HAND="$TMPROOT/hand.test.sh"
mk_hand "$REPO/tests/lib/resolve-roots.sh" "$HAND"

# The PATH a hand-run is given: the foreign interpreter first, then this suite's own.
HAND_GIVEN_PATH="$ALT_DIR:$PATH"

hand_run() {  # hand_run <interpreter> [marker] [suite] — leaves HAND_VER / HAND_STARTS / HAND_ARGV / HAND_CHILD …
  : > "$TMPROOT/hand.count"; : > "$TMPROOT/hand.out"
  ( if [ -n "${2:-}" ]; then
      BIONIC_TEST_INTERPRETER_PINNED="$2"; export BIONIC_TEST_INTERPRETER_PINNED
    else
      unset BIONIC_TEST_INTERPRETER_PINNED
    fi
    PATH="$HAND_GIVEN_PATH" \
    HAND_COUNT="$TMPROOT/hand.count" HAND_OUT="$TMPROOT/hand.out" HAND_HOOK="$HOOK_COPY" \
    "$1" "${3:-$HAND}" one two ) >/dev/null 2>&1
  HAND_VER="$(sed -n 's/^BASH_VERSION=//p' "$TMPROOT/hand.out")"
  HAND_ARGV="$(sed -n 's/^argv=//p' "$TMPROOT/hand.out")"
  HAND_ROOTS="$(sed -n 's/^roots=//p' "$TMPROOT/hand.out")"
  HAND_CHILD="$(sed -n 's/^child=//p' "$TMPROOT/hand.out")"
  HAND_HOOKVER="$(sed -n 's/^hook=//p' "$TMPROOT/hand.out")"
  HAND_FIRST_TARGET="$(sed -n 's/^first_target=//p' "$TMPROOT/hand.out")"
  HAND_REST="$(sed -n 's/^rest=//p' "$TMPROOT/hand.out")"
  HAND_GIT="$(sed -n 's/^git=//p' "$TMPROOT/hand.out")"
  HAND_JQ="$(sed -n 's/^jq=//p' "$TMPROOT/hand.out")"
  HAND_STARTS="$(wc -l < "$TMPROOT/hand.count" | tr -d ' ')"
}

# The hook copy is a real reader of its interpreter, proved under each before any row uses it.
expect_eq "2.0 the hook copy reports the interpreter it is run with (/bin/bash)" \
  "$SYS_VER" "$("$SYS_BASH" "$HOOK_COPY" 2>/dev/null)"
if [ -n "$ALT_BASH" ]; then
  expect_eq "2.0b …and the other one under the other interpreter" \
    "$ALT_VER" "$("$ALT_BASH" "$HOOK_COPY" 2>/dev/null)"
else
  skip "2.0b the hook copy under the other interpreter" "this host has only one bash"
fi

if [ -n "$ALT_BASH" ]; then
  hand_run "$ALT_BASH"
  expect_eq "2.1 a hand-run suite under the other interpreter reports the system version" \
    "$SYS_VER" "$HAND_VER"
  expect_eq "2.2 …by re-executing exactly once (the marker cannot loop)" "2" "$HAND_STARTS"
  expect_eq "2.3 …with its arguments intact across the re-exec" "one two" "$HAND_ARGV"
  expect_eq "2.4 …and the seam still answers the question it exists for" \
    "$REPO/hooks" "$HAND_ROOTS"

  # --- THE MARKER IS NOT THE TEST (critic K-4) ------------------------------
  # `tests/run.sh` exports BIONIC_TEST_INTERPRETER_PINNED to every descendant of
  # a run, so a hand-run started from inside a suite, a debugger, or a shell that
  # had once run the runner INHERITS it. While the guard trusted that marker the
  # pin was skipped and nothing said so: the suite reported bash 5.3 and there is
  # no stamp on the hand-run path to record which interpreter made the log.
  hand_run "$ALT_BASH" "1"
  expect_eq "2.4a an inherited pin marker does not defeat the pin" "$SYS_VER" "$HAND_VER"
  expect_eq "2.4b …and the re-exec still happens exactly once" "2" "$HAND_STARTS"
  expect_eq "2.4c …with its arguments still intact" "one two" "$HAND_ARGV"
  # PAIRED, so 2.4a is not a row that would pass under any interpreter: the same
  # marker with the SYSTEM bash must not provoke a second start.
  hand_run "$SYS_BASH" "1"
  expect_eq "2.4d …and a suite already under /bin/bash still does not re-exec" "1" "$HAND_STARTS"
else
  skip "2.1–2.4d hand-run parity under a foreign interpreter" "this host has only one bash"
fi

hand_run "$SYS_BASH"
expect_eq "2.5 a hand-run suite ALREADY under /bin/bash does not re-exec" "1" "$HAND_STARTS"
expect_eq "2.6 …and reports the system version" "$SYS_VER" "$HAND_VER"
echo ""

section "§2b hand-run parity reaches the children: the suite and all it starts get /bin/bash (T81)"
#
# The world tests/run.sh gives a suite is the pin first on PATH for the suite AND every process
# it starts. A suite typed at a prompt now gets the same world from the same function, which the
# seam calls on the hand-run path. Both ways a suite starts by hand are driven: under the other
# interpreter (the seam re-executes it) and already under /bin/bash (no re-exec; this second
# shape is the one that hid a 5.x-only `case` arm for weeks — the suite was 3.2 and every hook it
# spawned was not).
HAND_EXP_GIT="$(PATH="$HAND_GIVEN_PATH" command -v git 2>/dev/null || echo MISSING)"
HAND_EXP_JQ="$(PATH="$HAND_GIVEN_PATH" command -v jq 2>/dev/null || echo MISSING)"
for HAND_IN in "$ALT_BASH" "$SYS_BASH"; do
  [ -n "$HAND_IN" ] || continue
  HAND_SHAPE="started under /bin/bash"; [ "$HAND_IN" = "$SYS_BASH" ] || HAND_SHAPE="re-executed"
  hand_run "$HAND_IN"
  expect_eq "2.7 ($HAND_SHAPE) the suite itself reports the system version" "$SYS_VER" "$HAND_VER"
  if [ -n "$ALT_BASH" ]; then
    expect_eq "2.8 ($HAND_SHAPE) a child \`bash -c\` reports the system version" "$SYS_VER" "$HAND_CHILD"
    expect_eq "2.9 ($HAND_SHAPE) a child \`bash <a hook copy>\` reports the system version" \
      "$SYS_VER" "$HAND_HOOKVER"
  else
    skip "2.8–2.9 ($HAND_SHAPE) a child under a foreign interpreter first on PATH" "this host has only one bash"
  fi
  expect_eq "2.10 ($HAND_SHAPE) the first PATH entry the children get is the pin: bash -> /bin/bash" \
    "$SYS_BASH" "$HAND_FIRST_TARGET"
  expect_eq "2.11 ($HAND_SHAPE) …and the rest of PATH is the PATH the suite was given, unchanged" \
    "$HAND_GIVEN_PATH" "$HAND_REST"
  expect_eq "2.12 ($HAND_SHAPE) git resolves where it did" "$HAND_EXP_GIT" "$HAND_GIT"
  expect_eq "2.13 ($HAND_SHAPE) jq resolves where it did" "$HAND_EXP_JQ" "$HAND_JQ"
done
# NOT VACUOUS: git is on this host, so 2.12 compared two real paths.
expect_ne "2.14 git was found at all on the PATH the hand-run was given" "MISSING" "$HAND_EXP_GIT"
echo ""

section "§3 the planted 3.2 incompatibilities: the pin catches what it exists to catch (AC-10)"

PLANT_TREE="$TMPROOT/plant-tree"
mk_tree "$PLANT_TREE"

# (a) 3.2 ends the command substitution at the first `)` of the case pattern and leaks the
#     rest as text. Measured: 3.2.57 prints a parse error and garbage, exit 0; 5.3.15 prints A.
#
#     THE CONSTRUCT IS ASSEMBLED, NOT TYPED. tests/cross-gate-agreement.test.sh §BP forbids
#     the one-line `case` inside a command substitution anywhere under tests/ — the idiom is
#     banned in this tree precisely because `bash -n` cannot see it — and that lint reads
#     source text, so a planted copy typed literally here would trip the rule it is meant to
#     demonstrate. The same file's own mutation arm builds its copy through printf for the
#     same reason; this follows it.
PLANT_DOLLAR='$'
{ printf '#!/bin/bash\n'
  printf 'f() { echo "%s(case "%s1" in a) echo A;; *) echo other;; esac)"; }\n' \
    "$PLANT_DOLLAR" "$PLANT_DOLLAR"
  cat <<'PLANT_A_EOF'
got="$(f a 2>/dev/null)"
if [ "$got" = "A" ]; then echo "planted-case-leak: OK"; exit 0; fi
echo "planted-case-leak: expected [A], got [$got]"
exit 1
PLANT_A_EOF
} > "$PLANT_TREE/tests/planted-case-leak.test.sh"

# (b) the here-string temporary-assignment divergence (research-code-map §4.e). Hermetic:
#     the command the here-string's substitution needs is this file's own marker script, so
#     the row does not depend on jq being installed.
cat > "$PLANT_TREE/tests/planted-herestring.test.sh" <<'PLANT_B_EOF'
#!/bin/bash
BIN="$(mktemp -d)"; STRIP="$(mktemp -d)"
trap 'rm -rf "$BIN" "$STRIP"' EXIT
printf '#!/bin/bash\necho MARKER-OK\n' > "$BIN/probe_marker"; chmod +x "$BIN/probe_marker"
PATH="$BIN:$PATH"; export PATH
f() { probe_marker; }
for b in bash cat; do ln -sf "$(command -v "$b")" "$STRIP/$b"; done
got="$(PATH="$STRIP" cat <<< "$(f)" 2>/dev/null)"
if [ "$got" = "MARKER-OK" ]; then echo "planted-herestring: OK"; exit 0; fi
echo "planted-herestring: expected [MARKER-OK], got [$got]"
exit 1
PLANT_B_EOF

drive "$PLANT_TREE" "--serial"
expect_eq "3.1 the runner fails the run when a planted incompatibility is present" "1" "$DRV_RC"
expect_contains "3.2 …and reports both planted suites red" "Gating: 0 passed, 2 failed" "$DRV_OUT"
expect_contains "3.3 the quoted-\$( ) case leak is named" "- planted-case-leak.test.sh" "$DRV_OUT"
expect_contains "3.4 the here-string divergence is named" "- planted-herestring.test.sh" "$DRV_OUT"

# …and the same two files, unchanged, under the other interpreter: green. The planted
# constructs are 3.2/5.x DIVERGENCES, not broken scripts — which is the whole claim.
if [ -n "$ALT_BASH" ]; then
  ALT_A_OUT="$("$ALT_BASH" "$PLANT_TREE/tests/planted-case-leak.test.sh" 2>&1)"; ALT_A_RC=$?
  ALT_B_OUT="$("$ALT_BASH" "$PLANT_TREE/tests/planted-herestring.test.sh" 2>&1)"; ALT_B_RC=$?
  expect_eq "3.5 the case-leak file is GREEN under the other interpreter" "0" "$ALT_A_RC"
  expect_contains "3.6 …reporting the 5.x answer" "planted-case-leak: OK" "$ALT_A_OUT"
  expect_eq "3.7 the here-string file is GREEN under the other interpreter" "0" "$ALT_B_RC"
  expect_contains "3.8 …reporting the 5.x answer" "planted-herestring: OK" "$ALT_B_OUT"
else
  skip "3.5–3.8 the planted files are green under the other interpreter" "this host has only one bash"
fi
echo ""

section "§4 the environment stamp: the run says which environment it ran in (AC-3)"
#
# One line, twice: in the header, where a reader meets the run, and beside `Gating:`, where
# they read its verdict — a tail -5 of a captured log carries the environment with it.

drive "$PROBE_TREE" "--serial"
STAMPS="$(printf '%s\n' "$DRV_OUT" | grep -c '^env: ')"
expect_eq "4.1 the stamp is printed exactly twice" "2" "$STAMPS"
expect_regex "4.2 …with all four fields, in order" \
  '^env: os=[a-z]+ bash=[^ ]+ locale=[^ ]+ path=/' "$DRV_OUT"
STAMP_LINE="$(printf '%s\n' "$DRV_OUT" | grep '^env: ' | head -1)"
STAMP_TAIL="$(printf '%s\n' "$DRV_OUT" | grep '^env: ' | tail -1)"
expect_eq "4.3 the header stamp and the Gating stamp are the same line" "yes" \
  "$( [ -n "$STAMP_LINE" ] && [ "$STAMP_LINE" = "$STAMP_TAIL" ] && echo yes || echo no )"
expect_contains "4.4 the version it names is the interpreter the suites actually got" \
  "bash=$SYS_VER" "$STAMP_LINE"
expect_eq "4.5 the os field is this machine's" \
  "$(uname -s | tr '[:upper:]' '[:lower:]')" \
  "$(printf '%s\n' "$STAMP_LINE" | sed -n 's/^env: os=\([^ ]*\).*/\1/p')"
expect_eq "4.6 the locale field is the one the run inherited" \
  "${LC_ALL:-${LANG:-unset}}" \
  "$(printf '%s\n' "$STAMP_LINE" | sed -n 's/.* locale=\([^ ]*\).*/\1/p')"
# The path field names the launch directory the pin was built in — the same directory the
# probe suite saw first on its own PATH, so the stamp is reporting the mechanism and not a
# label somebody typed.
STAMP_PATH="$(printf '%s\n' "$STAMP_LINE" | sed -n 's/.* path=\(.*\)$/\1/p')"
expect_eq "4.7 the path field is the launch directory the suites were given" \
  "$(sed -n 's/^first_path_entry=//p' "$TMPROOT/probe.out")" "$STAMP_PATH"
# The Gating line still says what it always said, in the shape every reader and every
# close-out log greps for.
expect_contains "4.8 the Gating line is unchanged in shape" "Gating: 1 passed, 0 failed" "$DRV_OUT"
echo ""

section "§5 stderr-strict: a green suite that lost a command is red (the runner half of AC-14)"
#
# `set -uo pipefail` with no `-e` is this repo's suite convention, so a call to a helper
# that vanished is a `command not found` on stderr and nothing else — the suite finishes,
# its own tally never notices, and the runner prints ✓ PASS. The runner now reads the
# captured output of a suite that exited 0 and refuses it if the interpreter told it a
# command was missing.
#
# THE FALSE-POSITIVE GUARD is the second suite: several suites in the real roster PRINT the
# phrase in an assertion label (tests/dispatch-preflight.test.sh:771 asserts a fix command
# produces no 'command not found'). The arm matches the interpreter's own diagnostic shape,
# not the words, so a suite that merely quotes them stays green.

STRICT_TREE="$TMPROOT/strict-tree"
mk_tree "$STRICT_TREE"
cat > "$STRICT_TREE/tests/noisy.test.sh" <<'NOISY_EOF'
#!/bin/bash
set -uo pipefail
echo "PASS: 1: a helper that still exists"
bionic_helper_that_vanished "argument"
echo "PASS: 2: and the suite finished, none the wiser"
exit 0
NOISY_EOF
cat > "$STRICT_TREE/tests/quoting.test.sh" <<'QUOTING_EOF'
#!/bin/bash
set -uo pipefail
echo "PASS: fix-command run produces no 'command not found'"
echo "PASS: and no 'command not found' anywhere else either"
exit 0
QUOTING_EOF

drive "$STRICT_TREE" "--serial"
expect_eq "5.1 the run fails when a green suite lost a command" "1" "$DRV_RC"
expect_contains "5.2 …and the tally counts it failed" "Gating: 1 passed, 1 failed" "$DRV_OUT"
expect_contains "5.3 …naming the suite and why" "- noisy.test.sh" "$DRV_OUT"
expect_contains "5.4 …in words that send the reader to the missing command" "command not found" "$DRV_OUT"
expect_regex "5.5 a suite that only QUOTES the phrase stays green" \
  '^  quoting\.test\.sh +✓ PASS' "$DRV_OUT"
echo ""

section "§6 one pin, one owner: the runner and the seam pin through the same function (T81)"
#
# Two copies of the pin are two worlds: the runner's own pin code once gave a suite and its
# children /bin/bash while the seam, for a hand-run, gave the suite alone. The seam now owns
# the one function and the runner calls it. Proved both ways: the runner carries no pin code of
# its own, and a mutant of the seam's function — its PATH line removed, nothing else — takes
# the pin away from a suite the RUNNER launches and from the children of a suite run by HAND.
RUN_LN="$(grep -cE 'ln -sf? /bin/bash' "$REPO/tests/run.sh")"
SEAM_LN="$(grep -cE 'ln -sf? /bin/bash' "$REPO/tests/lib/resolve-roots.sh")"
expect_eq "6.1 the seam builds the pin (the extractor finds it there)" "1" "$SEAM_LN"
expect_eq "6.2 …and the runner builds none of its own" "0" "$RUN_LN"

MUT_TREE="$TMPROOT/mut-tree"
mk_tree "$MUT_TREE"
cp "$PROBE_TREE/tests/probe.test.sh" "$MUT_TREE/tests/probe.test.sh"
MUT_SEAM="$MUT_TREE/tests/lib/resolve-roots.sh"
anchor -E "$MUT_SEAM" '^  PATH="\$phys:\$PATH"' 1
grep -vE '^  PATH="\$phys:\$PATH"' "$REPO/tests/lib/resolve-roots.sh" > "$MUT_SEAM"
expect_eq "6.3 the mutant seam still parses" "0" "$(bash -n "$MUT_SEAM" >/dev/null 2>&1; echo $?)"
if [ -n "$ALT_BASH" ]; then
  : > "$TMPROOT/probe.out"
  drive "$MUT_TREE" "--serial"
  expect_eq "6.4 the mutant tree's runner still ran its probe (not vacuous)" "0" "$DRV_RC"
  expect_eq "6.5 the mutant takes the pin from a suite the RUNNER launches" "$ALT_VER" \
    "$(sed -n 's/^BASH_VERSION=//p' "$TMPROOT/probe.out")"
  mk_hand "$MUT_SEAM" "$TMPROOT/hand-mut.test.sh"
  hand_run "$SYS_BASH" "" "$TMPROOT/hand-mut.test.sh"
  expect_eq "6.6 …and from the children of a suite run by HAND" "$ALT_VER" "$HAND_CHILD"
  expect_eq "6.7 …while the mutant hand-run itself still ran (not vacuous)" "$SYS_VER" "$HAND_VER"
else
  skip "6.4–6.7 the seam mutant breaks the runner and the hand-run alike" "this host has only one bash"
fi
echo ""

section "§7 the pin's root is judged by the path itself, never by what a link points at (T87)"
#
# A hand-run's root is one predictable directory per user under the temp directory. The owner test
# `-O` follows a link, so a link planted at that path to any directory this user owns once passed,
# PATH carried the link's path, and repointing the link mid-run made a child `bash` run another
# script (review pass 75, drive e1b). Each state below is planted in a directory of this suite's
# own and handed to the function by path — never the real per-user root. A refusal returns
# non-zero, pins nothing, leaves PATH as it was and prints the seam's line naming the check, once.
T87_DIR="$TMPROOT/t87"
mkdir -p "$T87_DIR"; chmod 0755 "$T87_DIR"   # a parent no other user can write (T36; AC-10.6)
PIN_GIVEN="$HAND_GIVEN_PATH"

# pin_call <seam> <root> — call the seam's function in a fresh /bin/bash, leaving PIN_RC, PIN_PATH
# (PATH after the call) and PIN_ERR (the function's own stderr).
pin_call() {
  local out
  out="$(PATH="$PIN_GIVEN" /bin/bash -c '. "$1" >/dev/null 2>&1 || exit 9
    bionic_interpreter_pin "$2" 2>"$3"; echo "rc=$?"; echo "path=$PATH"' \
    pin-call "$1" "$2" "$TMPROOT/pin.err" 2>/dev/null)"
  PIN_RC="$(printf '%s\n' "$out" | sed -n 's/^rc=//p')"
  PIN_PATH="$(printf '%s\n' "$out" | sed -n 's/^path=//p')"
  PIN_ERR="$(cat "$TMPROOT/pin.err" 2>/dev/null)"
}
# pin_plant <state> <base> — plant one state under <base>; prints the root to hand the function.
pin_plant() {
  local base="$2"
  rm -rf "$base"; mkdir -p "$base/owned"; chmod 0755 "$base"; chmod 0700 "$base/owned"
  case "$1" in
    fresh)      ;;
    reuse)      mkdir -m 0700 "$base/root" "$base/root/pin"; ln -s /bin/bash "$base/root/pin/bash" ;;
    link-root)  ln -s "$base/owned" "$base/root" ;;
    link-pin)   mkdir -m 0700 "$base/root"; ln -s "$base/owned" "$base/root/pin" ;;
    mode-0777)  mkdir "$base/root"; chmod 0777 "$base/root" ;;
    mode-0770)  mkdir "$base/root"; chmod 0770 "$base/root" ;;
    file-root)  : > "$base/root" ;;
    bash-other) mkdir -m 0700 "$base/root" "$base/root/pin"; ln -s /bin/sh "$base/root/pin/bash" ;;
    runner)     printf '%s' "$(mktemp -d "$base/run.XXXXXX")"; return 0 ;;
  esac
  printf '%s' "$base/root"
}
there() { if [ -e "$1" ] || [ -L "$1" ]; then echo present; else echo absent; fi; }
phys() { ( cd "$1" 2>/dev/null && pwd -P ); }   # the path with no link on it: what PATH carries (T65)
inode() { ls -di "$1" 2>/dev/null | awk '{print $1}'; }
SEAM="$REPO/tests/lib/resolve-roots.sh"

# THE ACCEPTED STATES. Positives first, so every negative below has its extractor proven here.
R="$(pin_plant fresh "$T87_DIR/fresh")"
pin_call "$SEAM" "$R"
expect_eq "7.1 nothing at the root path: the function builds the pin and returns 0" "0" "$PIN_RC"
expect_eq "7.2 …PATH's first entry is <root>/pin, as its physical path, and the rest of PATH is unchanged" \
  "$(phys "$R/pin"):$PIN_GIVEN" "$PIN_PATH"
expect_match "7.3 …the root it created is mode 0700" 'drwx------*' "$(ls -ld "$R" 2>/dev/null)"
expect_eq "7.4 …and pin/bash is a link to exactly /bin/bash" "/bin/bash" "$(readlink "$R/pin/bash")"
expect_eq "7.5 …with nothing printed" "" "$PIN_ERR"
expect_eq "7.5b …and the presence extractor the refusals read finds the pin it built" "present" "$(there "$R/pin")"

R="$(pin_plant reuse "$T87_DIR/reuse")"
T87_ROOT_INO="$(inode "$R")"; T87_LINK_INO="$(inode "$R/pin/bash")"
expect_nonempty "7.6 the inode extractor reads the planted link" "$T87_LINK_INO"
pin_call "$SEAM" "$R"
expect_eq "7.7 a plain 0700 root holding pin/bash -> /bin/bash is reused: returns 0" "0" "$PIN_RC"
expect_eq "7.8 …PATH's first entry is <root>/pin (physical)" "$(phys "$R/pin"):$PIN_GIVEN" "$PIN_PATH"
expect_eq "7.9 …the root is the same directory" "$T87_ROOT_INO" "$(inode "$R")"
expect_eq "7.10 …and the bash link is untouched, never replaced" "$T87_LINK_INO" "$(inode "$R/pin/bash")"

R="$(pin_plant runner "$T87_DIR/runner")"
pin_call "$SEAM" "$R"
expect_eq "7.11 tests/run.sh's kind of root (its run's mktemp -d) passes every check" "0" "$PIN_RC"
expect_eq "7.12 …and the runner's pin is what it was: <root>/pin first (physical)" "$(phys "$R/pin"):$PIN_GIVEN" "$PIN_PATH"

# THE REFUSED STATES. Each: non-zero, PATH as given, nothing built, the seam's line once, naming
# the check that failed.
t87_refused() {  # t87_refused <n> <state> <what the line names> [a path that must stay absent]
  pin_call "$SEAM" "$R"
  expect_ne "$1a $2: refused (non-zero)" "0" "$PIN_RC"
  expect_eq "$1b $2: …PATH is the PATH the call was given" "$PIN_GIVEN" "$PIN_PATH"
  [ -z "${4:-}" ] || expect_eq "$1c $2: …nothing was built (${4##*/t87/})" "absent" "$(there "$4")"
  expect_contains "$1d $2: …the seam's own line" \
    "resolve-roots.sh: cannot build the interpreter pin under $R" "$PIN_ERR"
  expect_contains "$1e $2: …naming the check that failed" "$3" "$PIN_ERR"
  expect_eq "$1f $2: …printed once" "1" "$(printf '%s\n' "$PIN_ERR" | grep -c 'cannot build the interpreter pin')"
}
R="$(pin_plant link-root "$T87_DIR/link-root")"
t87_refused 7.13 "a symlink at the root path, to a directory this user owns" \
  "$R is a symlink" "$T87_DIR/link-root/owned/pin"
R="$(pin_plant link-pin "$T87_DIR/link-pin")"
t87_refused 7.14 "a plain root with a symlink at <root>/pin" \
  "$R/pin is a symlink" "$T87_DIR/link-pin/owned/bash"
R="$(pin_plant mode-0777 "$T87_DIR/mode-0777")"
t87_refused 7.15 "a plain root writable by others (0777)" \
  "$R is writable by group or others" "$R/pin"
R="$(pin_plant mode-0770 "$T87_DIR/mode-0770")"
t87_refused 7.16 "a plain root writable by its group (0770)" \
  "$R is writable by group or others" "$R/pin"
R="$(pin_plant file-root "$T87_DIR/file-root")"
t87_refused 7.17 "a file at the root path" "$R is not a directory"
R="$(pin_plant bash-other "$T87_DIR/bash-other")"
t87_refused 7.18 "pin/bash a link to something other than /bin/bash" \
  "$R/pin/bash is not a link to /bin/bash"
expect_eq "7.18g …and the foreign link is left as it was, not replaced" "/bin/sh" "$(readlink "$R/pin/bash")"
# A root owned by another user cannot be made in a suite run without privileges (chown needs
# root), so the owner arm is not driven here; the mode arm (7.15, 7.16) is the test of that rule.
skip "7.19 a root owned by another user" "unprivileged: chown to another uid needs root; the mode arm 7.15-7.16 stands in"

# THE MUTANT: the -L test removed from a copy of the seam, nothing else. The root and the pin go through one
# function (T67), so it is one test, and it must turn the two link states, the root's and the pin's, and those
# alone from refused to accepted — the other checks do not lean on it, and it is what stands between a
# planted link and PATH.
T87_MUT="$TMPROOT/t87-mutant-seam.sh"
T67_LINK_LINE='  [ ! -L "$1" ] || { _BIONIC_PIN_STEP="$1 is a symlink"; return 0; }'
anchor "$SEAM" "$T67_LINK_LINE" 1
grep -vxF "$T67_LINK_LINE" "$SEAM" > "$T87_MUT"
expect_eq "7.20 the mutant seam still parses" "0" "$(bash -n "$T87_MUT" >/dev/null 2>&1; echo $?)"
T87_FLIPS=""
for T87_STATE in fresh reuse runner link-root link-pin mode-0777 mode-0770 file-root bash-other; do
  R="$(pin_plant "$T87_STATE" "$T87_DIR/real-$T87_STATE")"; pin_call "$SEAM" "$R"; T87_REAL="$PIN_RC"
  R="$(pin_plant "$T87_STATE" "$T87_DIR/mut-$T87_STATE")"; pin_call "$T87_MUT" "$R"
  [ "$T87_REAL" = "$PIN_RC" ] || T87_FLIPS="$T87_FLIPS $T87_STATE"
  [ "$T87_STATE" != link-root ] || T87_MUT_PATH="$PIN_PATH" T87_MUT_R="$R"
done
expect_eq "7.21 the mutant turns the two link states, the root's and the pin's, and those alone, from refused to accepted" \
  " link-root link-pin" "$T87_FLIPS"
expect_eq "7.22 …and under the mutant the link is followed and PATH carries the pin built through it, physically (the defect it guards)" \
  "$(phys "$T87_MUT_R/pin"):$PIN_GIVEN" "$T87_MUT_PATH"

# A REFUSED PIN STOPS A HAND RUN (wave-28 T36; AC-10.5), AND AN OPEN PARENT IS REFUSED (AC-10.6).
# The hand path used to call the function with `|| :`, so a refused pin printed its line and the
# suite ran on, unpinned. Now the suite stops before any check: the interfaces' line, the pin
# marker unset, exit 2. The hand-run's root is `$TMPDIR/bionic-interpreter-pin.<uid>`, so each
# drive points TMPDIR at a directory of this suite's own; the real per-user root is never touched.
# The parent rule: a root whose parent group or other can write, with no sticky bit, is refused,
# since anyone who can write the parent can rename the root away and plant their own.
mk_stop() {  # mk_stop <seam> <file> — a hand-run suite: one line before the seam, one check after
  { printf '#!/bin/bash\n'
    printf 'trap '\''echo "pinned=${BIONIC_TEST_INTERPRETER_PINNED:-unset}" >> "$STOP_OUT"'\'' EXIT\n'
    printf 'echo start >> "$STOP_OUT"\n'
    printf '. "%s"\n' "$1"
    printf 'echo "check ran" >> "$STOP_OUT"\n'
  } > "$2"
  chmod +x "$2"
}
# stop_run <suite> <tmpdir> — a hand run under /bin/bash; leaves STOP_RC, STOP_ERR, STOP_LOG
stop_run() {
  : > "$TMPROOT/stop.out"
  ( unset BIONIC_TEST_INTERPRETER_PINNED
    PATH="${STOP_PATH:-$HAND_GIVEN_PATH}" TMPDIR="$2" STOP_OUT="$TMPROOT/stop.out" \
    /bin/bash "$1" 2>"$TMPROOT/stop.err" >/dev/null )
  STOP_RC=$?
  STOP_ERR="$(cat "$TMPROOT/stop.err" 2>/dev/null)"
  STOP_LOG="$(cat "$TMPROOT/stop.out" 2>/dev/null)"
}
STOP_SUITE="$TMPROOT/stop.test.sh"
mk_stop "$SEAM" "$STOP_SUITE"
STOP_UID="$(id -u)"

# The positive first: a clean temp directory, the pin built, the check runs.
T36_OK="$T87_DIR/t36-ok"; mkdir -p "$T36_OK"; chmod 0700 "$T36_OK"
stop_run "$STOP_SUITE" "$T36_OK"
expect_eq "7.23 a hand run whose pin can be built exits 0" "0" "$STOP_RC"
expect_contains "7.23b …runs its check (the log extractor reads it)" "check ran" "$STOP_LOG"
expect_contains "7.23c …with the pin marker set" "pinned=1" "$STOP_LOG"
expect_eq "7.23d …and builds the pin under the temp directory it was given" "/bin/bash" \
  "$(readlink "$T36_OK/bionic-interpreter-pin.$STOP_UID/pin/bash" 2>/dev/null)"

# A planted symlink at the per-user root: the pin is refused, so the run stops.
T36_LINK="$T87_DIR/t36-link"; mkdir -p "$T36_LINK/owned"; chmod 0700 "$T36_LINK" "$T36_LINK/owned"
ln -s "$T36_LINK/owned" "$T36_LINK/bionic-interpreter-pin.$STOP_UID"
T36_ROOT="$T36_LINK/bionic-interpreter-pin.$STOP_UID"
stop_run "$STOP_SUITE" "$T36_LINK"
expect_eq "7.24 a hand run whose pin is refused exits 2" "2" "$STOP_RC"
expect_contains "7.24b …it started (the line before the seam is there)" "start" "$STOP_LOG"
expect_absent "7.24c …and ran no check" "check ran" "$STOP_LOG"
expect_contains "7.24d …the pin marker is unset" "pinned=unset" "$STOP_LOG"
expect_contains "7.24e …the line names the pin's path and the reason, as the interfaces give it" \
  "resolve-roots.sh: no interpreter pin at $T36_ROOT — $T36_ROOT is a symlink; remove $T36_ROOT or set TMPDIR, then run again" \
  "$STOP_ERR"
expect_eq "7.24f …printed once, and nothing else on stderr" "1" "$(printf '%s\n' "$STOP_ERR" | grep -c .)"

# The parent: open to others with no sticky bit is refused; the same mode with the sticky bit is not.
T36_OPEN="$T87_DIR/t36-open"; mkdir -p "$T36_OPEN"; chmod 0777 "$T36_OPEN"
T36_OPEN_ROOT="$T36_OPEN/bionic-interpreter-pin.$STOP_UID"
stop_run "$STOP_SUITE" "$T36_OPEN"
expect_eq "7.25 a temp directory others can write, with no sticky bit: the hand run exits 2" "2" "$STOP_RC"
expect_absent "7.25b …and runs no check" "check ran" "$STOP_LOG"
expect_contains "7.25c …naming the open parent" \
  "resolve-roots.sh: no interpreter pin at $T36_OPEN_ROOT — $T36_OPEN is writable by group or others and has no sticky bit; set TMPDIR to an absolute directory only you can write, then run again" \
  "$STOP_ERR"
expect_eq "7.25d …and builds nothing there" "absent" "$(there "$T36_OPEN_ROOT")"
T36_GRP="$T87_DIR/t36-group"; mkdir -p "$T36_GRP"; chmod 0770 "$T36_GRP"
stop_run "$STOP_SUITE" "$T36_GRP"
expect_eq "7.26 a temp directory its group can write, with no sticky bit: exits 2" "2" "$STOP_RC"
expect_contains "7.26b …naming the open parent" "$T36_GRP is writable by group or others and has no sticky bit" "$STOP_ERR"
T36_STICKY="$T87_DIR/t36-sticky"; mkdir -p "$T36_STICKY"; chmod 1777 "$T36_STICKY"
stop_run "$STOP_SUITE" "$T36_STICKY"
expect_eq "7.27 a temp directory others can write WITH the sticky bit (/tmp's mode): exits 0" "0" "$STOP_RC"
expect_contains "7.27b …and runs its check" "check ran" "$STOP_LOG"
expect_eq "7.27c …with the pin built under it" "/bin/bash" \
  "$(readlink "$T36_STICKY/bionic-interpreter-pin.$STOP_UID/pin/bash" 2>/dev/null)"
# The function itself, as tests/run.sh calls it: an open parent is refused with the seam's line.
R="$T36_OPEN/fn-root"; pin_call "$SEAM" "$R"
expect_ne "7.28 the function refuses a root under an open parent (non-zero)" "0" "$PIN_RC"
expect_eq "7.28b …PATH is as given" "$PIN_GIVEN" "$PIN_PATH"
expect_contains "7.28c …naming the parent" "$T36_OPEN is writable by group or others and has no sticky bit" "$PIN_ERR"
R="$T36_STICKY/fn-root"; pin_call "$SEAM" "$R"
expect_eq "7.28d …and builds one under a sticky parent" "0" "$PIN_RC"

# A PARENT REACHED THROUGH A SYMLINK IS JUDGED BY WHERE IT LEADS (wave-28 T54; pass 25 adversarial #2).
# A link's own mode is always open (lrwxr-xr-x on macOS, lrwxrwxrwx on Linux), so `ls -ld` read the
# link and not the directory: a TMPDIR that is a link to an open, non-sticky directory built its pin
# there. The positive beside it: a link to a directory no other user can write still builds one.
T36_LNK_OPEN="$T87_DIR/t36-lnk-open"; ln -s "$T36_OPEN" "$T36_LNK_OPEN"
T36_LNK_OPEN_ROOT="$T36_LNK_OPEN/bionic-interpreter-pin.$STOP_UID"
stop_run "$STOP_SUITE" "$T36_LNK_OPEN"
expect_eq "7.31 a temp directory that is a link to an open, non-sticky directory: the hand run exits 2" "2" "$STOP_RC"
expect_absent "7.31b …and runs no check" "check ran" "$STOP_LOG"
expect_contains "7.31c …naming the link as the open parent, with the pin's existing line" \
  "resolve-roots.sh: no interpreter pin at $T36_LNK_OPEN_ROOT — $T36_LNK_OPEN is writable by group or others and has no sticky bit; set TMPDIR to an absolute directory only you can write, then run again" \
  "$STOP_ERR"
expect_eq "7.31d …and builds nothing in the directory it leads to" "absent" "$(there "$T36_OPEN/bionic-interpreter-pin.$STOP_UID")"
T36_LNK_OK="$T87_DIR/t36-lnk-ok"; ln -s "$T36_OK" "$T36_LNK_OK"
stop_run "$STOP_SUITE" "$T36_LNK_OK"
expect_eq "7.32 a link to a directory only this user can write builds its pin (the refusal is the mode, not the link)" "0" "$STOP_RC"
expect_contains "7.32b …and runs its check" "check ran" "$STOP_LOG"
T36_LNK_STICKY="$T87_DIR/t36-lnk-sticky"; ln -s "$T36_STICKY" "$T36_LNK_STICKY"
stop_run "$STOP_SUITE" "$T36_LNK_STICKY"
expect_eq "7.32c a link to an open directory WITH the sticky bit builds its pin too" "0" "$STOP_RC"
# The mutant: the link followed no more (`ls -ld`, in the one predicate of an open directory, which
# reads the directory with `ls -ldLe` and, where ls has no -e, with `ls -ldL`: both lines are turned).
# The open-parent link is then accepted.
T36_MUT3="$TMPROOT/t36-mut-nolink.sh"
anchor "$SEAM" 'out="$(ls -ldLe "$1" 2>/dev/null)"' 1
anchor "$SEAM" '[ -n "$out" ] || out="$(ls -ldL "$1" 2>/dev/null)"' 1
sed -e 's|out="$(ls -ldLe "$1"|out="$(ls -lde "$1"|' -e 's|out="$(ls -ldL "$1"|out="$(ls -ld "$1"|' "$SEAM" > "$T36_MUT3"
expect_eq "7.33 the no-link mutant parses" "0" "$(bash -n "$T36_MUT3" >/dev/null 2>&1; echo $?)"
R="$T36_LNK_OK/mut-ok-root"; pin_call "$T36_MUT3" "$R"
expect_eq "7.33b …and builds a pin under a link to a closed directory (not vacuous)" "0" "$PIN_RC"
R="$T36_LNK_OPEN/mut-root"; pin_call "$T36_MUT3" "$R"
expect_eq "7.33c under the no-link mutant the open parent behind a link is accepted (the defect 7.31 guards)" "0" "$PIN_RC"
R="$T36_LNK_OPEN/fn-root"; pin_call "$SEAM" "$R"
expect_ne "7.33d control: the shipped function refuses that same root" "0" "$PIN_RC"

# A LINK ON THE PARENT'S PATH IS JUDGED BY THE DIRECTORY THAT HOLDS IT (wave-28 T56; AC-10.6; pass 27).
# T54 read where a parent link LEADS and never the directory the link sits in: a link held in a
# directory others can write, with no sticky bit, is replaced by whoever can write that directory, and
# the pin's `bash` is then theirs. The walk judges every link on the parent's path by its holder.
# Holders and targets are explicit modes, never the umask's.
T56_TGT="$T87_DIR/t56-tgt"; mkdir -p "$T56_TGT"; chmod 0700 "$T56_TGT"
T56_HOLD="$T87_DIR/t56-hold-open"; mkdir -p "$T56_HOLD"; chmod 0777 "$T56_HOLD"
ln -s "$T56_TGT" "$T56_HOLD/lnk"
T56_ROOT="$T56_HOLD/lnk/bionic-interpreter-pin.$STOP_UID"
stop_run "$STOP_SUITE" "$T56_HOLD/lnk"
expect_eq "7.34 a temp directory that is a link held in an open, non-sticky directory: the hand run exits 2" "2" "$STOP_RC"
expect_absent "7.34b …and runs no check" "check ran" "$STOP_LOG"
expect_contains "7.34c …naming the link and the directory that holds it, with the pin's existing line" \
  "resolve-roots.sh: no interpreter pin at $T56_ROOT — $T56_HOLD/lnk is a symlink held in $T56_HOLD, which is writable by group or others and has no sticky bit; set TMPDIR to an absolute directory only you can write, then run again" \
  "$STOP_ERR"
expect_eq "7.34d …and builds nothing in the directory it leads to" "absent" "$(there "$T56_TGT/bionic-interpreter-pin.$STOP_UID")"
T56_STK="$T87_DIR/t56-hold-sticky"; mkdir -p "$T56_STK"; chmod 1777 "$T56_STK"
ln -s "$T56_TGT" "$T56_STK/lnk"
stop_run "$STOP_SUITE" "$T56_STK/lnk"
expect_eq "7.35 the same link held in an open directory WITH the sticky bit builds its pin" "0" "$STOP_RC"
expect_eq "7.35b …in the directory the link leads to" "/bin/bash" \
  "$(readlink "$T56_TGT/bionic-interpreter-pin.$STOP_UID/pin/bash" 2>/dev/null)"
T56_CLOSED="$T87_DIR/t56-hold-closed"; mkdir -p "$T56_CLOSED"; chmod 0700 "$T56_CLOSED"
ln -s "$T36_OPEN" "$T56_CLOSED/lnk"
stop_run "$STOP_SUITE" "$T56_CLOSED/lnk"
expect_eq "7.36 a link held in a closed directory that leads to an open one is still refused (7.31's case)" "2" "$STOP_RC"
expect_contains "7.36b …by where it leads" "$T56_CLOSED/lnk is writable by group or others and has no sticky bit" "$STOP_ERR"
# Two links in a chain. Outer: the open holder is the outer link's. Inner: the outer link is held
# in a closed directory and leads through a link that an open directory holds.
T56_MID="$T87_DIR/t56-mid"; mkdir -p "$T56_MID"; chmod 0700 "$T56_MID"
ln -s "$T56_TGT" "$T56_MID/inner"
ln -s "$T56_MID/inner" "$T56_HOLD/outer"
stop_run "$STOP_SUITE" "$T56_HOLD/outer"
expect_eq "7.37 two links in a chain, the outer one held in an open directory: exits 2" "2" "$STOP_RC"
expect_contains "7.37b …naming the outer link and its holder" "$T56_HOLD/outer is a symlink held in $T56_HOLD, which is writable" "$STOP_ERR"
ln -s "$T56_HOLD/lnk" "$T56_MID/outer2"
stop_run "$STOP_SUITE" "$T56_MID/outer2"
expect_eq "7.37c two links in a chain, the outer one held closed, the inner one in an open directory: exits 2" "2" "$STOP_RC"
expect_contains "7.37d …naming the inner link and its holder" "$T56_HOLD/lnk is a symlink held in $T56_HOLD, which is writable" "$STOP_ERR"
ln -s "$T56_HOLD" "$T56_MID/holder-link"; ln -s "$T56_TGT" "$T56_HOLD/lnk2"
stop_run "$STOP_SUITE" "$T56_MID/holder-link/lnk2"
expect_eq "7.37e a holder that is itself a link is judged where it leads, and that directory is open: exits 2" "2" "$STOP_RC"
expect_contains "7.37f …naming the link and the holder as the path spells it" \
  "$T56_MID/holder-link/lnk2 is a symlink held in $T56_MID/holder-link, which is writable" "$STOP_ERR"
# A cycle of links ends in a refusal, never a hang.
T56_CYC="$T87_DIR/t56-cycle"; mkdir -p "$T56_CYC"; chmod 0700 "$T56_CYC"; ln -s "$T56_CYC/a" "$T56_CYC/a"
stop_run "$STOP_SUITE" "$T56_CYC/a"
expect_eq "7.38 a link that leads back to itself is refused" "2" "$STOP_RC"
expect_contains "7.38b …naming the links" "$T56_CYC/a leads through more than 16 links" "$STOP_ERR"
# The mutants. (1) The walk's call removed: the open holder is accepted. (2) The holder judged with
# no sticky exemption: the sticky holder is refused. Each is proved to run before its claim is read.
T56_MUT1="$TMPROOT/t56-mut-walk.sh"
anchor "$SEAM" '_bionic_pin_links "$parent" 0' 1
grep -vF '_bionic_pin_links "$parent" 0' "$SEAM" > "$T56_MUT1"
expect_eq "7.39 the no-walk mutant parses" "0" "$(bash -n "$T56_MUT1" >/dev/null 2>&1; echo $?)"
R="$T56_CLOSED/lnk/mut-closed-root"; pin_call "$T56_MUT1" "$R"
expect_ne "7.39b …and still refuses the open parent behind a closed holder (not vacuous)" "0" "$PIN_RC"
R="$T56_HOLD/lnk/mut-root"; pin_call "$T56_MUT1" "$R"
expect_eq "7.39c under the no-walk mutant the link held in an open directory is accepted (the defect 7.34 guards)" "0" "$PIN_RC"
R="$T56_HOLD/lnk/fn-root"; pin_call "$SEAM" "$R"
expect_ne "7.39d control: the shipped function refuses that same root" "0" "$PIN_RC"
T56_MUT2="$TMPROOT/t56-mut-sticky.sh"
anchor "$SEAM" '    ?????????[tT]*) sticky=1 ;;' 1
grep -vF '    ?????????[tT]*) sticky=1 ;;' "$SEAM" > "$T56_MUT2"
expect_eq "7.40 the no-sticky mutant parses" "0" "$(bash -n "$T56_MUT2" >/dev/null 2>&1; echo $?)"
R="$T36_LNK_OK/mut-nosticky-root"; pin_call "$T56_MUT2" "$R"
expect_eq "7.40b …and builds a pin under a link held in a closed directory (not vacuous)" "0" "$PIN_RC"
R="$T56_STK/lnk/mut-root"; pin_call "$T56_MUT2" "$R"
expect_ne "7.40c under the no-sticky mutant the link held in a sticky directory is refused (the row 7.35 guards)" "0" "$PIN_RC"
R="$T56_STK/lnk/fn-root"; pin_call "$SEAM" "$R"
expect_eq "7.40d control: the shipped function builds under that same root" "0" "$PIN_RC"

# EVERY DIRECTORY ON THE PARENT'S PATH IS JUDGED, AND AN ACL COUNTS AS OPEN (wave-28 T57; AC-10.6; pass 29).
# T56 judged a component's holder only when the component was a link: `TMPDIR=<0777>/sub` with `sub`
# at 0700 still built a pin, and `sub` can be renamed away mid-run. And "open" was read from the mode
# string alone, so a macOS ACL letting everyone add and delete entries in a 0700 parent passed, and the
# root and pin the function makes inherited it. Mutants first (their anchors, then the rows that use them).
T57_MUT1="$TMPROOT/t57-mut-ancestor.sh"
anchor -E "$SEAM" '^    cur="\$cur/\$part"$' 1
awk '{print} $0 == "    cur=\"$cur/$part\"" {print "    [ -L \"$cur\" ] || continue"}' "$SEAM" > "$T57_MUT1"
T57_MUT2="$TMPROOT/t57-mut-acl.sh"
anchor "$SEAM" '  _bionic_pin_acl "$1" "$out"' 1
grep -vF '  _bionic_pin_acl "$1" "$out"' "$SEAM" > "$T57_MUT2"
# t57_line <tmpdir> <why> <remedy> — the hand run's one stderr line, as the seam prints it
t57_line() { printf 'resolve-roots.sh: no interpreter pin at %s — %s; %s, then run again' \
  "$1/bionic-interpreter-pin.$STOP_UID" "$2" "$3"; }
T57_FIX="set TMPDIR to an absolute directory only you can write"
# Case A: a closed leaf inside an open, non-sticky directory, no link anywhere.
T57_OPEN="$T87_DIR/t57-open"; mkdir -p "$T57_OPEN/sub"; chmod 0700 "$T57_OPEN/sub"; chmod 0777 "$T57_OPEN"
T57_SUB="$T57_OPEN/sub"
stop_run "$STOP_SUITE" "$T57_SUB"
expect_eq "7.41 a temp directory that is closed but sits in an open, non-sticky directory: the hand run exits 2" "2" "$STOP_RC"
expect_absent "7.41b …and runs no check" "check ran" "$STOP_LOG"
expect_contains "7.41c …naming the open ancestor, and the remedy that helps" \
  "$(t57_line "$T57_SUB" "$T57_OPEN is writable by group or others and has no sticky bit" "$T57_FIX")" "$STOP_ERR"
expect_eq "7.41d …and builds nothing there" "absent" "$(there "$T57_SUB/bionic-interpreter-pin.$STOP_UID")"
R="$T57_SUB/fn-root"; pin_call "$SEAM" "$R"
expect_ne "7.41e the function refuses a root under that path (non-zero)" "0" "$PIN_RC"
expect_eq "7.41f …PATH is as given" "$PIN_GIVEN" "$PIN_PATH"
expect_contains "7.41g …naming the ancestor" "$T57_OPEN is writable by group or others and has no sticky bit" "$PIN_ERR"
# Case A2: the open directory is three levels above the parent.
T57_OPEN2="$T87_DIR/t57-open2"; mkdir -p "$T57_OPEN2/s1/s2/s3"; chmod 0777 "$T57_OPEN2"
chmod 0700 "$T57_OPEN2/s1" "$T57_OPEN2/s1/s2" "$T57_OPEN2/s1/s2/s3"
stop_run "$STOP_SUITE" "$T57_OPEN2/s1/s2/s3"
expect_eq "7.42 the same, three levels above the temp directory: exits 2" "2" "$STOP_RC"
expect_contains "7.42b …naming the open directory" \
  "$(t57_line "$T57_OPEN2/s1/s2/s3" "$T57_OPEN2 is writable by group or others and has no sticky bit" "$T57_FIX")" "$STOP_ERR"
# The same shape with the sticky bit builds (a shared /tmp over a private directory).
T57_STK="$T87_DIR/t57-sticky"; mkdir -p "$T57_STK/sub"; chmod 0700 "$T57_STK/sub"; chmod 1777 "$T57_STK"
stop_run "$STOP_SUITE" "$T57_STK/sub"
expect_eq "7.43 a closed temp directory in an open directory WITH the sticky bit builds its pin" "0" "$STOP_RC"
expect_eq "7.43b …in that directory" "/bin/bash" \
  "$(readlink "$T57_STK/sub/bionic-interpreter-pin.$STOP_UID/pin/bash" 2>/dev/null)"
R="$T57_STK/sub/mut-root"; pin_call "$T56_MUT2" "$R"
expect_ne "7.43c under the no-sticky mutant the sticky ancestor is refused (the row 7.43 guards)" "0" "$PIN_RC"
# The mutant for this half: the link-only short-circuit restored.
expect_eq "7.44 the no-ancestor mutant parses" "0" "$(bash -n "$T57_MUT1" >/dev/null 2>&1; echo $?)"
R="$T57_STK/sub/mut-ok-root"; pin_call "$T57_MUT1" "$R"
expect_eq "7.44b …and builds under a sticky ancestor (not vacuous)" "0" "$PIN_RC"
R="$T57_SUB/mut-root"; pin_call "$T57_MUT1" "$R"
expect_eq "7.44c under the no-ancestor mutant the open ancestor is accepted (the defect 7.41 guards)" "0" "$PIN_RC"
expect_eq "7.44d …and the pin is built there" "present" "$(there "$R/pin")"
R="$T57_SUB/fn-root2"; pin_call "$SEAM" "$R"
expect_ne "7.44e control: the shipped function refuses that same path" "0" "$PIN_RC"
# The ACL reader, on macOS. The rows skip with their reason where `chmod +a` is not there.
T57_ACLP="$T87_DIR/t57-aclprobe"; mkdir -p "$T57_ACLP"; chmod 0700 "$T57_ACLP"
T57_ACL=0
if chmod +a "everyone allow add_file,add_subdirectory,delete_child" "$T57_ACLP" 2>/dev/null \
   && [ "$(ls -lde "$T57_ACLP" 2>/dev/null | grep -c 'group:everyone allow add_file,add_subdirectory,delete_child')" = 1 ]; then
  T57_ACL=1
fi
if [ "$T57_ACL" = 1 ]; then
  T57_WHY_ACL="$T57_ACLP carries an ACL letting group:everyone add_file,add_subdirectory,delete_child"
  stop_run "$STOP_SUITE" "$T57_ACLP"
  expect_eq "7.45 a 0700 temp directory whose ACL lets everyone add and delete entries: the hand run exits 2" "2" "$STOP_RC"
  expect_absent "7.45b …and runs no check" "check ran" "$STOP_LOG"
  expect_contains "7.45c …naming the entry" "$(t57_line "$T57_ACLP" "$T57_WHY_ACL" "$T57_FIX")" "$STOP_ERR"
  expect_eq "7.45d …and builds nothing there" "absent" "$(there "$T57_ACLP/bionic-interpreter-pin.$STOP_UID")"
  # The same entry on an ancestor of a closed temp directory.
  mkdir -p "$T57_ACLP/up/sub"; chmod 0700 "$T57_ACLP/up" "$T57_ACLP/up/sub"; chmod -N "$T57_ACLP"
  chmod +a "everyone allow add_file,add_subdirectory,delete_child" "$T57_ACLP/up"
  stop_run "$STOP_SUITE" "$T57_ACLP/up/sub"
  expect_eq "7.45e the entry on an ancestor of the temp directory: exits 2" "2" "$STOP_RC"
  expect_contains "7.45f …naming the ancestor" \
    "$(t57_line "$T57_ACLP/up/sub" "$T57_ACLP/up carries an ACL letting group:everyone add_file,add_subdirectory,delete_child" "$T57_FIX")" "$STOP_ERR"
  R="$T57_ACLP/up/sub/mut-root"; pin_call "$T57_MUT2" "$R"
  expect_eq "7.45g under the no-ACL mutant the entry is accepted (the defect 7.45 guards)" "0" "$PIN_RC"
  expect_eq "7.45h …and the pin is built there" "present" "$(there "$R/pin")"
  R="$T57_ACLP/up/sub/fn-root"; pin_call "$SEAM" "$R"
  expect_ne "7.45i control: the shipped function refuses that same path" "0" "$PIN_RC"
  chmod -N "$T57_ACLP/up"
  # Entries that grant no one else the power to replace anything build: a deny, a read, the owner's own.
  T57_NO1="$T87_DIR/t57-acl-deny"; mkdir -p "$T57_NO1"; chmod 0700 "$T57_NO1"; chmod +a "everyone deny add_file,delete_child" "$T57_NO1"
  stop_run "$STOP_SUITE" "$T57_NO1"
  expect_eq "7.46 a 0700 temp directory whose ACL only DENIES builds its pin" "0" "$STOP_RC"
  chmod -N "$T57_NO1"
  T57_NO2="$T87_DIR/t57-acl-read"; mkdir -p "$T57_NO2"; chmod 0700 "$T57_NO2"; chmod +a "everyone allow read" "$T57_NO2"
  expect_eq "7.46b the ACL extractor reads the read-only entry" "1" "$(ls -lde "$T57_NO2" | grep -c 'group:everyone allow list')"
  stop_run "$STOP_SUITE" "$T57_NO2"
  expect_eq "7.46c …a read-only entry for everyone builds its pin" "0" "$STOP_RC"
  chmod -N "$T57_NO2"
  T57_NO3="$T87_DIR/t57-acl-owner"; mkdir -p "$T57_NO3"; chmod 0700 "$T57_NO3"
  chmod +a "$(id -un) allow add_file,add_subdirectory,delete_child" "$T57_NO3"
  expect_eq "7.46d the ACL extractor reads the owner's entry" "1" "$(ls -lde "$T57_NO3" | grep -c "user:$(id -un) allow add_file")"
  stop_run "$STOP_SUITE" "$T57_NO3"
  expect_eq "7.46e …an entry for the owner alone builds its pin" "0" "$STOP_RC"
  chmod -N "$T57_NO3"
  # An inheritable entry that does not apply to the parent itself: the root the function makes inherits it.
  T57_INH="$T87_DIR/t57-acl-inherit"; mkdir -p "$T57_INH"; chmod 0700 "$T57_INH"
  chmod +a "everyone allow add_file,add_subdirectory,delete_child,file_inherit,directory_inherit,only_inherit" "$T57_INH"
  T57_INH_ROOT="$T57_INH/bionic-interpreter-pin.$STOP_UID"
  stop_run "$STOP_SUITE" "$T57_INH"
  expect_eq "7.47 an inheritable entry on a 0700 temp directory: the made root inherits it, the hand run exits 2" "2" "$STOP_RC"
  expect_contains "7.47b …naming the root and the entry, with the path remedy (the root is gone, so removing it helps nothing)" \
    "resolve-roots.sh: no interpreter pin at $T57_INH_ROOT — $T57_INH_ROOT carries an ACL letting group:everyone add_file,add_subdirectory,delete_child; $T57_FIX, then run again" \
    "$STOP_ERR"
  expect_eq "7.47c …and the root it made is removed" "absent" "$(there "$T57_INH_ROOT")"
  R="$T57_INH/fn-root"; pin_call "$SEAM" "$R"
  expect_ne "7.47d the function refuses it too" "0" "$PIN_RC"
  expect_eq "7.47e …PATH is as given" "$PIN_GIVEN" "$PIN_PATH"
  expect_eq "7.47f …and removes the root it made" "absent" "$(there "$R")"
  R="$T57_INH/mut-root"; pin_call "$T57_MUT2" "$R"
  expect_eq "7.47g under the no-ACL mutant the inheriting root is accepted (the defect 7.47 guards)" "0" "$PIN_RC"
  expect_eq "7.47h …and stays, with its pin" "present" "$(there "$R/pin")"
  chmod -N "$T57_INH" "$R" "$R/pin" 2>/dev/null
else
  skip "7.45 the ACL reader (macOS: a 0700 directory whose ACL lets everyone add and delete entries)" \
    "chmod +a is not available on this host, or ls -lde does not list the entry it made"
  skip "7.47 an inheritable ACL entry on the temp directory: the made root is refused and removed" \
    "chmod +a is not available on this host"
fi
chmod -N "$T57_ACLP" 2>/dev/null
# The reader for a host with getfacl (Linux), driven by a stub that answers for one directory only.
T57_STUB="$TMPROOT/t57-stub"; mkdir -p "$T57_STUB"
cat > "$T57_STUB/getfacl" <<'STUB'
#!/bin/sh
for d; do :; done
case "$d" in
  */t57-lx) cat "$T57_GETFACL_OUT" ;;
  *) if [ -f "$T59_GETFACL_DIR/${d##*/}" ]; then cat "$T59_GETFACL_DIR/${d##*/}"
     else printf 'user::rwx\ngroup::r-x\nother::r-x\n'
     fi ;;
esac
STUB
chmod +x "$T57_STUB/getfacl"
T57_LX="$T87_DIR/t57-lx"; mkdir -p "$T57_LX"; chmod 0700 "$T57_LX"
T57_GETFACL_OUT="$TMPROOT/t57-getfacl.out"; export T57_GETFACL_OUT
T59_GETFACL_DIR="$TMPROOT/t59-getfacl"; mkdir -p "$T59_GETFACL_DIR"; export T59_GETFACL_DIR  # answers by the directory's own name
t57_lx() {  # t57_lx <seam> <root-name> <acl text> — pin_call with the stub's answer for the parent
  printf '%b' "$3" > "$T57_GETFACL_OUT"
  PIN_GIVEN="$T57_STUB:$HAND_GIVEN_PATH"; pin_call "$1" "$T57_LX/$2"; PIN_GIVEN="$HAND_GIVEN_PATH"
}
t57_lx "$SEAM" lx-plain '# file: x\nuser::rwx\ngroup::---\nother::---\n'
expect_eq "7.48 getfacl lists only the owner's and the base entries: the pin is built" "0" "$PIN_RC"
expect_eq "7.48b …and is there" "present" "$(there "$T57_LX/lx-plain/pin")"
t57_lx "$SEAM" lx-named 'user::rwx\nuser:mallory:rw-\ngroup::---\nmask::rw-\nother::---\n'
expect_ne "7.48c a named user with w: the function refuses (non-zero)" "0" "$PIN_RC"
expect_contains "7.48d …naming the entry" "$T57_LX carries an ACL letting user:mallory write" "$PIN_ERR"
t57_lx "$SEAM" lx-group 'user::rwx\ngroup:wheel:-w-\nmask::rwx\nother::---\n'
expect_contains "7.48e a named group with w: refused, naming it" "$T57_LX carries an ACL letting group:wheel write" "$PIN_ERR"
t57_lx "$SEAM" lx-masked 'user::rwx\nuser:mallory:rwx\t#effective:r--\ngroup::---\nmask::r--\nother::---\n'
expect_eq "7.48f a named user whose effective rights lack w: the pin is built" "0" "$PIN_RC"
t57_lx "$SEAM" lx-default 'user::rwx\ngroup::---\nother::---\ndefault:user:mallory:rwx\n'
expect_eq "7.48g a default entry (it applies to what is made inside, not to the directory): the pin is built" "0" "$PIN_RC"
expect_eq "7.48h …and is there" "present" "$(there "$T57_LX/lx-default/pin")"
t57_lx "$T57_MUT2" lx-mut 'user::rwx\nuser:mallory:rw-\ngroup::---\nmask::rw-\nother::---\n'
expect_eq "7.48i under the no-ACL mutant the named user is accepted (the defect 7.48c guards)" "0" "$PIN_RC"
expect_eq "7.48j …and the pin is built there" "present" "$(there "$T57_LX/lx-mut/pin")"

# THE PREDICATE READS THE ACL'S BASE ENTRIES AS THE MODE, THE OWNER, AND THE RIGHTS THAT GRANT RIGHTS
# (wave-28 T59; AC-10.6; pass 32). Linux `getfacl -p` prints the base entries `user::`, `group::`,
# `other::` and `mask::` for EVERY directory: they repeat the mode and are not grants, so a sticky
# 1777 /tmp, which the mode check lets through, must not be refused for them. A default: entry is
# what CHILDREN inherit; a made root and pin are judged after they are made, where an inherited entry
# is an access entry, so default: entries are never counted (the macOS only_inherit rule). Whose
# directory it is can only be stubbed (no hermetic row can plant another uid's directory): the owner
# reader is `stat`, and the stub answers for one directory name and passes every other call through.
T59_ME="$(id -un)"
T59_MUT_BASE="$TMPROOT/t59-mut-base.sh"
anchor "$SEAM" '[ -n "$name" ] || continue' 1
sed 's/\[ -n "\$name" \] || continue.*/case "$line" in user::*|mask::*) continue ;; esac/' "$SEAM" > "$T59_MUT_BASE"  # the reader as T57 shipped it
t59_lx() {  # t59_lx <seam> <name> <mode> <getfacl text> [<root>] — a directory of this row's own, the stub's answer for it, pin_call under it
  local d="$T87_DIR/t59-lx-$2"
  mkdir -p "$d"; chmod "$3" "$d"
  printf '%b' "$4" > "$T59_GETFACL_DIR/t59-lx-$2"
  PIN_GIVEN="$T57_STUB:$HAND_GIVEN_PATH"; pin_call "$1" "$d/${5:-root}"; PIN_GIVEN="$HAND_GIVEN_PATH"
}
T59_BASE="# file: tmp\\n# owner: $T59_ME\\n# group: wheel\\n# flags: --t\\nuser::rwx\\ngroup::rwx\\nother::rwx\\n"
t59_lx "$SEAM" sticky 1777 "$T59_BASE"
expect_eq "7.49 a sticky 1777 directory whose getfacl lists only the base entries (a Linux /tmp): the pin is built" "0" "$PIN_RC"
expect_eq "7.49b …and is there" "present" "$(there "$T87_DIR/t59-lx-sticky/root/pin")"
expect_eq "7.49c the fixture is open by mode and sticky (the extractor reads the t)" "t" "$(ls -ld "$T87_DIR/t59-lx-sticky" | cut -c10)"
t59_lx "$T59_MUT_BASE" sticky-mut 1777 "$T59_BASE"
expect_ne "7.49d under the base-entries mutant the same directory is refused (the defect 7.49 guards)" "0" "$PIN_RC"
expect_contains "7.49e …naming the base entry" "$T87_DIR/t59-lx-sticky-mut carries an ACL letting group write" "$PIN_ERR"
t59_lx "$T59_MUT_BASE" closed 0700 "# file: d\\n# owner: $T59_ME\\nuser::rwx\\ngroup::---\\nother::---\\n"
expect_eq "7.49f …and builds a closed directory whose base entries hold no w (not vacuous)" "0" "$PIN_RC"
t59_lx "$SEAM" named 0700 "# file: d\\n# owner: $T59_ME\\n# group: wheel\\nuser::rwx\\nuser:bob:rwx\\ngroup::---\\nmask::rwx\\nother::---\\n"
expect_ne "7.50 a full getfacl listing with a named user holding w: refused" "0" "$PIN_RC"
expect_contains "7.50b …naming the entry" "$T87_DIR/t59-lx-named carries an ACL letting user:bob write" "$PIN_ERR"
t59_lx "$SEAM" named-me 0700 "# file: d\\n# owner: $T59_ME\\nuser::rwx\\nuser:$T59_ME:rwx\\ngroup::---\\nmask::rwx\\nother::---\\n"
expect_eq "7.50c the same entry naming the directory's own owner is the owner's: built" "0" "$PIN_RC"
t59_lx "$SEAM" named-me2 0700 "# file: d\\n# owner: someone-else\\nuser::rwx\\nuser:$T59_ME:rwx\\ngroup::---\\nmask::rwx\\nother::---\\n"
expect_contains "7.50d …and when the owner is another it is a grant" "$T87_DIR/t59-lx-named-me2 carries an ACL letting user:$T59_ME write" "$PIN_ERR"
t59_lx "$SEAM" default 0700 "# file: d\\n# owner: $T59_ME\\nuser::rwx\\ngroup::---\\nother::---\\ndefault:user::rwx\\ndefault:group::rwx\\ndefault:other::---\\n"
expect_eq "7.51 default entries on the parent are what children inherit, not a grant on the parent: built" "0" "$PIN_RC"
expect_eq "7.51b …and is there" "present" "$(there "$T87_DIR/t59-lx-default/root/pin")"
printf '%b' "user::rwx\\nuser:bob:rwx\\ngroup::---\\nmask::rwx\\nother::---\\n" > "$T59_GETFACL_DIR/inhroot"
t59_lx "$SEAM" inherit 0700 "user::rwx\\ngroup::---\\nother::---\\ndefault:user:bob:rwx\\n" inhroot
expect_ne "7.51c the made root carries what it inherited, as an access entry: refused" "0" "$PIN_RC"
expect_contains "7.51d …naming the root and the entry" "$T87_DIR/t59-lx-inherit/inhroot carries an ACL letting user:bob write" "$PIN_ERR"
expect_eq "7.51e …and the root it made is removed" "absent" "$(there "$T87_DIR/t59-lx-inherit/inhroot")"
# The owner. A directory on the path owned by neither this user nor root can rename what it holds.
T59_STUB="$TMPROOT/t59-stub"; mkdir -p "$T59_STUB"
cat > "$T59_STUB/stat" <<'STUB'
#!/bin/sh
for d; do :; done
[ "$d" != / ] || d=t61-fsroot  # the filesystem root has no name of its own
f="$T59_STAT_DIR/${d##*/}"
case " $* " in *" -L "*) ;; *) f="$f.nf" ;; esac  # a call that does not follow links reads <name>.nf
if [ -f "$f" ]; then cat "$f"; else PATH=/usr/bin:/bin exec stat "$@"; fi
STUB
chmod +x "$T59_STUB/stat"
T59_STAT_DIR="$TMPROOT/t59-stat"; mkdir -p "$T59_STAT_DIR"; export T59_STAT_DIR
t59_own() {  # t59_own <seam> <root> — pin_call with the stat stub first on PATH
  PIN_GIVEN="$T59_STUB:$HAND_GIVEN_PATH"; pin_call "$1" "$2"; PIN_GIVEN="$HAND_GIVEN_PATH"
}
T59_OWN="$T87_DIR/t59-own"; mkdir -p "$T59_OWN/t59-anc/t59-sub"
chmod 0755 "$T59_OWN" "$T59_OWN/t59-anc"; chmod 0700 "$T59_OWN/t59-anc/t59-sub"
T59_ANC="$T59_OWN/t59-anc"; T59_SUB="$T59_ANC/t59-sub"
T59_OTHER=54321; [ "$T59_OTHER" != "$(id -u)" ] || T59_OTHER=54322
T59_WHY_OWN="is owned by uid $T59_OTHER, who is not you, root or the owner of /"
t59_own "$SEAM" "$T59_SUB/r1"
expect_eq "7.52 under the stub with no answer set, the real reader passes this user's own directories: built" "0" "$PIN_RC"
printf '%s\n' "$T59_OTHER" > "$T59_STAT_DIR/t59-anc"
t59_own "$SEAM" "$T59_SUB/r2"
expect_ne "7.52b an ancestor owned by another user, closed by mode: refused" "0" "$PIN_RC"
expect_contains "7.52c …naming the directory and its owner" "$T59_ANC $T59_WHY_OWN" "$PIN_ERR"
expect_eq "7.52d …PATH is as given" "$T59_STUB:$HAND_GIVEN_PATH" "$PIN_PATH"
expect_eq "7.52e …and nothing is built there" "absent" "$(there "$T59_SUB/r2")"
STOP_PATH="$T59_STUB:$HAND_GIVEN_PATH" stop_run "$STOP_SUITE" "$T59_SUB"; unset STOP_PATH
expect_eq "7.52f the hand run exits 2" "2" "$STOP_RC"
expect_contains "7.52g …naming the directory and its owner, with the path remedy" \
  "$(t57_line "$T59_SUB" "$T59_ANC $T59_WHY_OWN" "$T57_FIX")" "$STOP_ERR"
printf '0\n' > "$T59_STAT_DIR/t59-anc"
t59_own "$SEAM" "$T59_SUB/r3"
expect_eq "7.52h the same ancestor owned by root: built" "0" "$PIN_RC"
expect_eq "7.52i …and is there" "present" "$(there "$T59_SUB/r3/pin")"
rm -f "$T59_STAT_DIR/t59-anc"; printf '%s\n' "$T59_OTHER" > "$T59_STAT_DIR/t59-sub"
t59_own "$SEAM" "$T59_SUB/r4"
expect_contains "7.52j the parent itself owned by another user: refused, naming it" "$T59_SUB $T59_WHY_OWN" "$PIN_ERR"
rm -f "$T59_STAT_DIR/t59-sub"
T59_MUT_OWN="$TMPROOT/t59-mut-owner.sh"
anchor "$SEAM" '_bionic_pin_trusted "$owner" ||' 1
grep -vF '_bionic_pin_trusted "$owner" ||' "$SEAM" > "$T59_MUT_OWN"
expect_eq "7.53 the no-owner mutant parses" "0" "$(bash -n "$T59_MUT_OWN" >/dev/null 2>&1; echo $?)"
t59_own "$T59_MUT_OWN" "$T57_SUB/mut-owner-ctl"
expect_ne "7.53b …and still refuses an open ancestor (not vacuous)" "0" "$PIN_RC"
printf '%s\n' "$T59_OTHER" > "$T59_STAT_DIR/t59-anc"
t59_own "$T59_MUT_OWN" "$T59_SUB/mut-owner"
expect_eq "7.53c under the no-owner mutant the other user's ancestor is accepted (the defect 7.52b guards)" "0" "$PIN_RC"
expect_eq "7.53d …and the pin is built there" "present" "$(there "$T59_SUB/mut-owner/pin")"
t59_own "$SEAM" "$T59_SUB/r5"
expect_ne "7.53e control: the shipped function refuses that same path" "0" "$PIN_RC"
rm -f "$T59_STAT_DIR/t59-anc"
# A link's OWN owner (A-T56.5; ruling A-orch-157). `stat -L` reads where a link leads; a link planted by
# another user in a sticky holder leading to a directory this user owns passes every judgment above, and
# its owner may repoint it. The no-follow read is the stub's `<name>.nf`.
T59_HOLD="$T87_DIR/t59-hold"; mkdir -p "$T59_HOLD"; chmod 1777 "$T59_HOLD"
T59_TGT="$T87_DIR/t59-tgt"; mkdir -p "$T59_TGT"; chmod 0700 "$T59_TGT"
ln -s "$T59_TGT" "$T59_HOLD/t59-lnk"; T59_LNK="$T59_HOLD/t59-lnk"
T59_WHY_LNK="$T59_LNK is a symlink owned by uid $T59_OTHER, who is not you, root or the owner of /"
t59_own "$SEAM" "$T59_LNK/r1"
expect_eq "7.56 a link in a sticky holder leading to this user's directory, owned by this user: built" "0" "$PIN_RC"
expect_eq "7.56b …and is there" "present" "$(there "$T59_LNK/r1/pin")"
printf '%s\n' "$T59_OTHER" > "$T59_STAT_DIR/t59-lnk.nf"
t59_own "$SEAM" "$T59_LNK/r2"
expect_ne "7.56c the same link owned by another user: refused" "0" "$PIN_RC"
expect_contains "7.56d …naming the link and its owner" "$T59_WHY_LNK" "$PIN_ERR"
expect_eq "7.56e …and nothing is built there" "absent" "$(there "$T59_TGT/r2")"
STOP_PATH="$T59_STUB:$HAND_GIVEN_PATH" stop_run "$STOP_SUITE" "$T59_LNK"; unset STOP_PATH
expect_eq "7.56f the hand run exits 2" "2" "$STOP_RC"
expect_contains "7.56g …naming the link and its owner, with the path remedy" \
  "$(t57_line "$T59_LNK" "$T59_WHY_LNK" "$T57_FIX")" "$STOP_ERR"
printf '0\n' > "$T59_STAT_DIR/t59-lnk.nf"
t59_own "$SEAM" "$T59_LNK/r3"
expect_eq "7.56h the same link owned by root: built" "0" "$PIN_RC"
rm -f "$T59_STAT_DIR/t59-lnk.nf"
T59_MUT_LNK="$TMPROOT/t59-mut-linkowner.sh"
anchor "$SEAM" '_bionic_pin_trusted "$linkowner" ||' 1
grep -vF '_bionic_pin_trusted "$linkowner" ||' "$SEAM" > "$T59_MUT_LNK"
expect_eq "7.57 the no-link-owner mutant parses" "0" "$(bash -n "$T59_MUT_LNK" >/dev/null 2>&1; echo $?)"
printf '%s\n' "$T59_OTHER" > "$T59_STAT_DIR/t59-lnk.nf"
t59_own "$T59_MUT_LNK" "$T59_LNK/mut-root"
expect_eq "7.57b under the no-link-owner mutant the other user's link is accepted (the defect 7.56c guards)" "0" "$PIN_RC"
expect_eq "7.57c …and the pin is built there" "present" "$(there "$T59_LNK/mut-root/pin")"
t59_own "$SEAM" "$T59_LNK/r4"
expect_ne "7.57d control: the shipped function refuses that same path" "0" "$PIN_RC"
rm -f "$T59_STAT_DIR/t59-lnk.nf"
# THE OWNER OF THE FILESYSTEM ROOT IS TRUSTED TOO (wave-28 T61; AC-10.6; pass 34). In an unprivileged Linux
# user namespace every uid with no mapping, root's included, reads as the overflow uid 65534: `/` and the
# directories on the way down all read 65534, and "this user or root" refused every pin. The stub answers
# 65534 for `/` (it is named t61-fsroot) and for an ancestor: the namespace's shape. An ancestor owned by
# a DIFFERENT uid is still refused, and the owner of `/` is trusted only where it is the root's own.
T61_FS="$T59_STAT_DIR/t61-fsroot"; T61_NS=65534
printf '%s\n' "$T61_NS" > "$T61_FS"; printf '%s\n' "$T61_NS" > "$T59_STAT_DIR/t59-anc"
t59_own "$SEAM" "$T59_SUB/n1"
expect_eq "7.58 the stub answers 65534 for / and for an ancestor (a user namespace): the pin is built" "0" "$PIN_RC"
expect_eq "7.58b …and is there" "present" "$(there "$T59_SUB/n1/pin")"
STOP_PATH="$T59_STUB:$HAND_GIVEN_PATH" stop_run "$STOP_SUITE" "$T59_SUB"; unset STOP_PATH
expect_eq "7.58c …a hand run there exits 0" "0" "$STOP_RC"
expect_contains "7.58d …and runs its check" "check ran" "$STOP_LOG"
printf '%s\n' "$T59_OTHER" > "$T59_STAT_DIR/t59-anc"
t59_own "$SEAM" "$T59_SUB/n2"
expect_ne "7.59 / reads 65534 and an ancestor reads another, mapped uid: refused" "0" "$PIN_RC"
expect_contains "7.59b …naming the directory and that uid" "$T59_ANC $T59_WHY_OWN" "$PIN_ERR"
expect_eq "7.59c …and nothing is built there" "absent" "$(there "$T59_SUB/n2")"
STOP_PATH="$T59_STUB:$HAND_GIVEN_PATH" stop_run "$STOP_SUITE" "$T59_SUB"; unset STOP_PATH
expect_eq "7.59d the hand run exits 2" "2" "$STOP_RC"
expect_contains "7.59e …naming the directory and that uid, with the path remedy" \
  "$(t57_line "$T59_SUB" "$T59_ANC $T59_WHY_OWN" "$T57_FIX")" "$STOP_ERR"
rm -f "$T61_FS"; printf '%s\n' "$T61_NS" > "$T59_STAT_DIR/t59-anc"
t59_own "$SEAM" "$T59_SUB/n3"
expect_ne "7.59f / reads as the root it is and an ancestor reads 65534: refused (the overflow uid is trusted only where / has it)" "0" "$PIN_RC"
expect_contains "7.59g …naming the directory and 65534" "$T59_ANC is owned by uid $T61_NS, who is not you, root or the owner of /" "$PIN_ERR"
printf '%s\n' "$T61_NS" > "$T61_FS"; printf '%s\n' "$T61_NS" > "$T59_STAT_DIR/t59-lnk.nf"
t59_own "$SEAM" "$T59_LNK/n4"
expect_eq "7.59h a link on the path owned by the uid / has: built (the link's own owner is judged by the same rule)" "0" "$PIN_RC"
printf '%s\n' "$T59_OTHER" > "$T59_STAT_DIR/t59-lnk.nf"
t59_own "$SEAM" "$T59_LNK/n5"
expect_ne "7.59i …and a link owned by another mapped uid is still refused" "0" "$PIN_RC"
rm -f "$T59_STAT_DIR/t59-lnk.nf" "$T59_STAT_DIR/t59-anc" "$T61_FS"
# a TMPDIR that does not exist names its real cause, not an owner nobody could read
T61_MISS="$T59_OWN/t61-no-such-tmp"
stop_run "$STOP_SUITE" "$T61_MISS"
expect_eq "7.60 a TMPDIR that does not exist: the hand run exits 2" "2" "$STOP_RC"
expect_contains "7.60b …naming the missing parent as not a directory (T63: refused where the walk meets it), with the path remedy" \
  "$(t57_line "$T61_MISS" "$T61_MISS is not a directory" "$T57_FIX")" "$STOP_ERR"
expect_absent "7.60c …and not naming an owner nobody could read" "uid unknown" "$STOP_ERR"
pin_call "$SEAM" "$T61_MISS/bionic-interpreter-pin.$STOP_UID"
expect_contains "7.60d the function's own line says the same" "$T61_MISS is not a directory, so nothing is pinned" "$PIN_ERR"
# a root another user planted at the predictable name cannot be removed from a sticky /tmp: the path remedy
T61_STK="$T87_DIR/t61-sticky"; mkdir -p "$T61_STK"; chmod 1777 "$T61_STK"
T61_PLANT="$T61_STK/bionic-interpreter-pin.$STOP_UID"; mkdir -m 0700 "$T61_PLANT"
printf '%s\n' "$T59_OTHER" > "$T59_STAT_DIR/bionic-interpreter-pin.$STOP_UID"
cp "$T59_STAT_DIR/bionic-interpreter-pin.$STOP_UID" "$T59_STAT_DIR/bionic-interpreter-pin.$STOP_UID.nf"
STOP_PATH="$T59_STUB:$HAND_GIVEN_PATH" stop_run "$STOP_SUITE" "$T61_STK"; unset STOP_PATH
expect_eq "7.61 a root planted by another uid at the predictable name: the hand run exits 2" "2" "$STOP_RC"
expect_contains "7.61b …naming the root and its owner (T65: the entry itself must be this user's), with the path remedy (this user cannot remove it)" \
  "$(t57_line "$T61_STK" "$T61_PLANT is owned by uid $T59_OTHER, who is not you" "$T57_FIX")" "$STOP_ERR"
expect_eq "7.61c …and the root is still there" "present" "$(there "$T61_PLANT")"
rm -f "$T59_STAT_DIR/bionic-interpreter-pin.$STOP_UID" "$T59_STAT_DIR/bionic-interpreter-pin.$STOP_UID.nf"
# the mutant: the third trusted owner removed. The namespace shape is refused again (the defect 7.58 guards).
T61_MUT="$TMPROOT/t61-mut-fsowner.sh"
anchor "$SEAM" '[ "$1" = "$(_bionic_pin_owner /)" ]' 1
T61_LINE='[ "$1" = "$(_bionic_pin_owner /)" ]' \
  awk 'index($0, ENVIRON["T61_LINE"]) { print "  return 1"; next } { print }' "$SEAM" > "$T61_MUT"
expect_eq "7.62 the no-root-owner mutant parses" "0" "$(bash -n "$T61_MUT" >/dev/null 2>&1; echo $?)"
t59_own "$T61_MUT" "$T59_SUB/n6"
expect_eq "7.62b …and builds where no stub is set (not vacuous)" "0" "$PIN_RC"
printf '%s\n' "$T61_NS" > "$T61_FS"; printf '%s\n' "$T61_NS" > "$T59_STAT_DIR/t59-anc"
t59_own "$T61_MUT" "$T59_SUB/n7"
expect_ne "7.62c under the mutant the namespace shape is refused (the defect 7.58 guards)" "0" "$PIN_RC"
expect_contains "7.62d …naming 65534 as an owner who is not this user, root or the owner of /" "is owned by uid $T61_NS, who is not you, root or the owner of /" "$PIN_ERR"
t59_own "$SEAM" "$T59_SUB/n8"
expect_eq "7.62e control: the shipped function builds that same shape" "0" "$PIN_RC"
rm -f "$T61_FS" "$T59_STAT_DIR/t59-anc"
# A MISSING PARENT IS REFUSED, NEVER "NOT OPEN" (wave-28 T63; AC-10.6; pass 38). T61 let a path that does not
# exist read "not open", so a parent that was absent when the walk judged it passed, and another user made it
# before the mkdir: it was never judged again and owned the pin. A path that does not exist is refused where
# the walk meets it, as `<path> is not a directory`. The race is built the reader's way: the walk's own
# function is wrapped so that the parent appears (mode 0777) right after the walk has judged it.
T63_DIR="$T87_DIR/t63"; mkdir -p "$T63_DIR"; chmod 0755 "$T63_DIR"
# t63_race <seam> <parent> — pin <parent>'s child root; <parent> is made 0777 right after the walk, before the mkdir
t63_race() {
  local out
  out="$(PATH="$PIN_GIVEN" /bin/bash -c '. "$1" >/dev/null 2>&1 || exit 9
    racer="$2"
    eval "t63_orig_$(declare -f _bionic_pin_parent)"
    _bionic_pin_parent() { local r; r="$(t63_orig__bionic_pin_parent "$@")"; mkdir -m 0777 "$racer" 2>/dev/null; chmod 0777 "$racer"; printf "%s" "$r"; }
    bionic_interpreter_pin "$racer/bionic-interpreter-pin.$UID" 2>"$3"; echo "rc=$?"' \
    t63-race "$1" "$2" "$TMPROOT/pin.err" 2>/dev/null)"
  PIN_RC="$(printf '%s\n' "$out" | sed -n 's/^rc=//p')"
  PIN_ERR="$(cat "$TMPROOT/pin.err" 2>/dev/null)"
}
# t63_fn <seam> <function> [args] — one helper run alone, with the stat stub first on PATH: prints its output, then rc=<n>
t63_fn() {
  local seam="$1"; shift
  PATH="$T59_STUB:$HAND_GIVEN_PATH" /bin/bash -c '. "$1" >/dev/null 2>&1 || exit 9; shift; "$@"; echo "rc=$?"' t63-fn "$seam" "$@" 2>/dev/null
}
T63_RACER="$T63_DIR/racer"
t63_race "$SEAM" "$T63_RACER"
expect_ne "7.63 a parent absent when the walk judged it and made 0777 before the mkdir: refused" "0" "$PIN_RC"
expect_contains "7.63b …naming the parent as not a directory" "$T63_RACER is not a directory" "$PIN_ERR"
expect_eq "7.63c …the racer's directory is there (the harness ran the race)" "present" "$(there "$T63_RACER")"
expect_eq "7.63d …and nothing is built in it" "absent" "$(there "$T63_RACER/bionic-interpreter-pin.$STOP_UID")"
mkdir -m 0700 "$T63_DIR/closed"
pin_call "$SEAM" "$T63_DIR/closed/bionic-interpreter-pin.$STOP_UID"
expect_eq "7.63e a parent present and closed: built" "0" "$PIN_RC"
expect_eq "7.63f …and is there" "present" "$(there "$T63_DIR/closed/bionic-interpreter-pin.$STOP_UID/pin/bash")"
pin_call "$SEAM" "$T63_DIR/gone/deeper/root"
expect_ne "7.64 an ancestor of the parent that does not exist: refused" "0" "$PIN_RC"
expect_contains "7.64b …naming the first path that is missing as not a directory" "$T63_DIR/gone is not a directory" "$PIN_ERR"
expect_eq "7.64c …and nothing is made there" "absent" "$(there "$T63_DIR/gone")"
ln -s "$T63_DIR/nowhere" "$T63_DIR/dangling"
pin_call "$SEAM" "$T63_DIR/dangling/root"
expect_ne "7.64d a parent that is a link to nowhere: refused" "0" "$PIN_RC"
expect_contains "7.64e …naming the link as not a directory" "$T63_DIR/dangling is not a directory" "$PIN_ERR"
expect_eq "7.64f …and nothing is made through it" "absent" "$(there "$T63_DIR/nowhere")"
# the trust rule is one predicate: this user, root, and the owner of `/`; the owner reader prints the raw uid
rm -f "$T61_FS"
expect_eq "7.65 _bionic_pin_trusted, alone: this user" "rc=0" "$(t63_fn "$SEAM" _bionic_pin_trusted "$STOP_UID")"
expect_eq "7.65b …root" "rc=0" "$(t63_fn "$SEAM" _bionic_pin_trusted 0)"
expect_eq "7.65c …a mapped other uid is not" "rc=1" "$(t63_fn "$SEAM" _bionic_pin_trusted "$T59_OTHER")"
expect_eq "7.65d …an owner that could not be read is not" "rc=1" "$(t63_fn "$SEAM" _bionic_pin_trusted "")"
expect_eq "7.65e …65534 is not, where / is root's" "rc=1" "$(t63_fn "$SEAM" _bionic_pin_trusted "$T61_NS")"
printf '%s\n' "$T61_NS" > "$T61_FS"
expect_eq "7.65f …the owner of / is, called alone (no entry point has set anything)" "rc=0" "$(t63_fn "$SEAM" _bionic_pin_trusted "$T61_NS")"
expect_eq "7.65g …a mapped other uid is still not, where / reads 65534" "rc=1" "$(t63_fn "$SEAM" _bionic_pin_trusted "$T59_OTHER")"
printf '%s\n' "$T61_NS" > "$T59_STAT_DIR/t59-anc"
expect_eq "7.65h the owner reader prints the raw uid, the namespace's included" "$(printf '%s\nrc=0' "$T61_NS")" "$(t63_fn "$SEAM" _bionic_pin_owner "$T59_ANC")"
rm -f "$T61_FS" "$T59_STAT_DIR/t59-anc"
# the remedy chooser reads the raw owner: `remove` is offered for a root this user owns, even where / reads as this user
T63_CH="$T63_DIR/chooser"; mkdir -m 0700 "$T63_CH"
T63_CH_ROOT="$T63_CH/bionic-interpreter-pin.$STOP_UID"; mkdir -m 0777 "$T63_CH_ROOT"; chmod 0777 "$T63_CH_ROOT"
T63_CH_LINE="$(t57_line "$T63_CH" "$T63_CH_ROOT is writable by group or others" "remove $T63_CH_ROOT or set TMPDIR")"
stop_run "$STOP_SUITE" "$T63_CH"
expect_eq "7.66 a root of this user's, open by mode: the hand run exits 2" "2" "$STOP_RC"
expect_contains "7.66b …and offers to remove it" "$T63_CH_LINE" "$STOP_ERR"
printf '%s\n' "$STOP_UID" > "$T61_FS"
STOP_PATH="$T59_STUB:$HAND_GIVEN_PATH" stop_run "$STOP_SUITE" "$T63_CH"; unset STOP_PATH
expect_eq "7.66c the same where / reads as this user: the hand run exits 2" "2" "$STOP_RC"
expect_contains "7.66d …and still offers to remove it (the owner it reads is the raw one)" "$T63_CH_LINE" "$STOP_ERR"
rm -f "$T61_FS"
# the mutant: the missing-path refusal removed, T61's "not open" back. The race builds (the defect 7.63 guards).
T63_MUT="$TMPROOT/t63-mut-missing.sh"
anchor "$SEAM" '[ -e "$1" ] || { _BIONIC_PIN_OPEN="is not a directory"; return 0; }' 1
T63_LINE='[ -e "$1" ] || { _BIONIC_PIN_OPEN="is not a directory"; return 0; }' \
  awk 'index($0, ENVIRON["T63_LINE"]) { print "  [ -e \"$1\" ] || return 1"; next } { print }' "$SEAM" > "$T63_MUT"
expect_eq "7.67 the missing-path mutant parses" "0" "$(bash -n "$T63_MUT" >/dev/null 2>&1; echo $?)"
pin_call "$T63_MUT" "$T63_DIR/closed/mut-root"
expect_eq "7.67b …and builds where the parent is present (not vacuous)" "0" "$PIN_RC"
T63_RACER2="$T63_DIR/racer2"
t63_race "$T63_MUT" "$T63_RACER2"
expect_eq "7.67c under the mutant the race builds the pin (the defect 7.63 guards)" "0" "$PIN_RC"
expect_eq "7.67d …and it is there, in a directory made after the walk" "present" "$(there "$T63_RACER2/bionic-interpreter-pin.$STOP_UID/pin/bash")"
t63_race "$SEAM" "$T63_DIR/racer3"
expect_ne "7.67e control: the shipped function refuses the same race" "0" "$PIN_RC"

# THE ROOT'S OWN ENTRY IS JUDGED BY ITS OWN OWNER, WITHOUT FOLLOWING (wave-28 T65; AC-10.6; pass 40 #1). T63's
# walk judged the root after the `-L` test, and every reader after that test follows links: a root another
# user planted at the predictable name in a sticky /tmp and swapped for a link between the `-L` test and the
# judge passed (the link leads to a directory of the victim's), the pin was built there and PATH carried it
# through the planter's link, which the planter can repoint. The entry's own owner (`stat` without `-L`, the
# stub's `<name>.nf`) is now read before the `-L` test and the judge, for the root and for `pin`, and must be
# this user. The swap is built the reader's way: the judge is wrapped so the swap happens right after the
# `-L` test; the stub says the planted entry's own owner is another user, as a planter's would be.
T65_DIR="$T87_DIR/t65"; mkdir -p "$T65_DIR"; chmod 0755 "$T65_DIR"
# t65_swap <seam> <root> <victim> — pin <root> under the stat stub; right after the root's -L test it is renamed away and a link to <victim> takes its name
t65_swap() {
  local out
  out="$(PATH="$T59_STUB:$HAND_GIVEN_PATH" T65_ROOT="$2" T65_VICTIM="$3" /bin/bash -c '. "$1" >/dev/null 2>&1 || exit 9
    eval "t65_orig_$(declare -f _bionic_pin_judge)"
    t65_done=""
    _bionic_pin_judge() {
      if [ "$1" = "$T65_ROOT" ] && [ -z "$t65_done" ]; then t65_done=1; mv "$T65_ROOT" "$T65_ROOT.away"; ln -s "$T65_VICTIM" "$T65_ROOT"; fi
      t65_orig__bionic_pin_judge "$@"
    }
    bionic_interpreter_pin "$T65_ROOT" 2>"$2"; echo "rc=$?"; echo "path=$PATH"' \
    t65-swap "$1" "$TMPROOT/pin.err" 2>/dev/null)"
  PIN_RC="$(printf '%s\n' "$out" | sed -n 's/^rc=//p')"
  PIN_PATH="$(printf '%s\n' "$out" | sed -n 's/^path=//p')"
  PIN_ERR="$(cat "$TMPROOT/pin.err" 2>/dev/null)"
}
# t65_plant <name> — a closed root of this user's under its own parent, a victim directory beside it, the stub saying the root's OWN owner is another user
t65_plant() {
  mkdir -p "$T65_DIR/$1"; chmod 0755 "$T65_DIR/$1"
  mkdir -m 0700 "$T65_DIR/$1/t65-root-$1" "$T65_DIR/$1/victim"
  printf '%s\n' "$T59_OTHER" > "$T59_STAT_DIR/t65-root-$1.nf"
}
T65_WHY="is owned by uid $T59_OTHER, who is not you"
t65_plant swap
T65_R="$T65_DIR/swap/t65-root-swap"; T65_V="$T65_DIR/swap/victim"
expect_eq "7.68 the owner reader without following prints this user's uid on a real entry (the extractor the rows below lean on)" \
  "$(printf '%s\nrc=0' "$STOP_UID")" "$(t63_fn "$SEAM" _bionic_pin_owner "$T65_DIR/swap/victim" nofollow)"
t65_swap "$SEAM" "$T65_R" "$T65_V"
expect_ne "7.68b a root whose own entry is another user's, swapped for a link after the -L test: refused" "0" "$PIN_RC"
expect_contains "7.68c …naming the entry and its owner" "$T65_R $T65_WHY" "$PIN_ERR"
expect_eq "7.68d …and nothing is made in the victim's directory" "absent" "$(there "$T65_V/pin")"
expect_eq "7.68e …PATH is as given" "$T59_STUB:$HAND_GIVEN_PATH" "$PIN_PATH"
expect_eq "7.68f …the planter's entry is still there, not replaced" "present" "$(there "$T65_R")"
# the mutant: the root's owner read removed. The swap builds through the link (the defect 7.68b guards).
T65_MUT="$TMPROOT/t65-mut-rootowner.sh"
T67_ENTRY_LINE='  _BIONIC_PIN_STEP="$(_bionic_pin_entry "$1")"'
anchor "$SEAM" "$T67_ENTRY_LINE" 1
grep -vxF "$T67_ENTRY_LINE" "$SEAM" > "$T65_MUT"
expect_eq "7.69 the no-root-owner mutant parses" "0" "$(bash -n "$T65_MUT" >/dev/null 2>&1; echo $?)"
t65_plant mut
t65_swap "$T65_MUT" "$T65_DIR/mut/t65-root-mut" "$T65_DIR/mut/victim"
expect_eq "7.69b under the mutant the swap builds (the defect 7.68b guards)" "0" "$PIN_RC"
expect_eq "7.69c …through the link, in the victim's directory (the harness ran the swap)" "present" "$(there "$T65_DIR/mut/victim/pin/bash")"
expect_eq "7.69d …and PATH carries a pin built there" "$(phys "$T65_DIR/mut/victim/pin"):$T59_STUB:$HAND_GIVEN_PATH" "$PIN_PATH"
t65_plant ctl
t65_swap "$SEAM" "$T65_DIR/ctl/t65-root-ctl" "$T65_DIR/ctl/victim"
expect_ne "7.69e control: the shipped function refuses the same swap" "0" "$PIN_RC"
expect_eq "7.69f …and the victim's directory is untouched" "absent" "$(there "$T65_DIR/ctl/victim/pin")"
rm -f "$T59_STAT_DIR"/t65-root-*.nf
# a link planted before the call is refused as before (7.24e), and a pre-existing root of this user's is built
R="$(pin_plant link-root "$T65_DIR/link")"; pin_call "$SEAM" "$R"
expect_ne "7.70 a root that is a link planted before the call: refused" "0" "$PIN_RC"
expect_contains "7.70b …as a symlink" "$R is a symlink" "$PIN_ERR"
expect_eq "7.70c …and PATH is as given" "$PIN_GIVEN" "$PIN_PATH"
R="$(pin_plant reuse "$T65_DIR/reuse")"
printf '%s\n' "$STOP_UID" > "$T59_STAT_DIR/root.nf"
t59_own "$SEAM" "$R"
expect_eq "7.70d a root pre-existing, closed, whose own owner reads as this user: built" "0" "$PIN_RC"
rm -f "$T59_STAT_DIR/root.nf"
# the pin directory's own entry is read the same way
T65_PR="$T65_DIR/pinown/t65-pin-root"; mkdir -p "$T65_DIR/pinown"; chmod 0755 "$T65_DIR/pinown"; mkdir -m 0700 "$T65_PR" "$T65_PR/pin"
printf '%s\n' "$T59_OTHER" > "$T59_STAT_DIR/pin.nf"
t59_own "$SEAM" "$T65_PR"
expect_ne "7.71 a pin directory whose own entry is another user's: refused" "0" "$PIN_RC"
expect_contains "7.71b …naming the entry and its owner" "$T65_PR/pin $T65_WHY" "$PIN_ERR"
expect_eq "7.71c …and no bash link is made in it" "absent" "$(there "$T65_PR/pin/bash")"
expect_eq "7.71d …PATH is as given" "$T59_STUB:$HAND_GIVEN_PATH" "$PIN_PATH"
T65_MUT_PIN="$TMPROOT/t65-mut-pinowner.sh"
anchor "$SEAM" "$T67_ENTRY_LINE" 1
grep -vxF "$T67_ENTRY_LINE" "$SEAM" > "$T65_MUT_PIN"
expect_eq "7.71e the no-pin-owner mutant parses" "0" "$(bash -n "$T65_MUT_PIN" >/dev/null 2>&1; echo $?)"
t59_own "$T65_MUT_PIN" "$T65_PR"
expect_eq "7.71f under the mutant the other user's pin directory is used (the defect 7.71 guards)" "0" "$PIN_RC"
expect_eq "7.71g …and bash is linked in it" "present" "$(there "$T65_PR/pin/bash")"
rm -f "$T59_STAT_DIR/pin.nf"
# PATH carries the physical path: a TMPDIR reached through a link this user owns
mkdir -p "$T65_DIR/phys/real"; chmod 0755 "$T65_DIR/phys"; chmod 0700 "$T65_DIR/phys/real"; ln -s real "$T65_DIR/phys/lnk"
pin_call "$SEAM" "$T65_DIR/phys/lnk/t65-phys-root"
expect_eq "7.72 a root reached through a link this user owns: built" "0" "$PIN_RC"
T65_FIRST="${PIN_PATH%%:*}"
expect_eq "7.72b …PATH's first entry is the physical directory, pinned" "$(phys "$T65_DIR/phys/real")/t65-phys-root/pin" "$T65_FIRST"
expect_eq "7.72c …and it holds bash -> /bin/bash" "/bin/bash" "$(readlink "$T65_FIRST/bash" 2>/dev/null)"
expect_eq "7.72d …and it names no link: it is its own physical path" "$T65_FIRST" "$(phys "$T65_FIRST")"
expect_eq "7.72e …the rest of PATH is unchanged" "$T65_FIRST:$PIN_GIVEN" "$PIN_PATH"
T65_MUT_PHYS="$TMPROOT/t65-mut-phys.sh"
anchor "$SEAM" ' cd -P -- "$dir" 2>/dev/null && pwd -P)"' 1
sed 's#cd -P -- "$dir" 2>/dev/null && pwd -P)"#cd -- "$dir" 2>/dev/null \&\& pwd)"#' "$SEAM" > "$T65_MUT_PHYS"
expect_eq "7.73 the logical-path mutant parses" "0" "$(bash -n "$T65_MUT_PHYS" >/dev/null 2>&1; echo $?)"
pin_call "$T65_MUT_PHYS" "$T65_DIR/phys/lnk/t65-mut-root"
expect_eq "7.73b under the mutant the pin is built (not vacuous)" "0" "$PIN_RC"
expect_eq "7.73c …and PATH's first entry is the path through the link (the defect 7.72b guards)" \
  "$(cd "$T65_DIR/phys/lnk" && pwd)/t65-mut-root/pin" "${PIN_PATH%%:*}"

# AN ENTRY THAT IS ABSENT AT THE OWNER READ IS REFUSED (wave-28 T67; AC-10.6; pass 42 #1). T65's owner read said
# nothing for a path that was not there ("the judge names it"). A planter whose root existed at the mkdir guard
# removed it before that read, and planted a LINK after the `-L` test: the judge followed the link into a
# directory of the victim's that the walk never judged, and `pin` was made there. The same gap is a mkdir that
# fails. Now an absent entry is refused where the owner is read (`<path> does not exist`), and a mkdir that fails
# is refused at the call (`cannot make <path>`). The race is built the reader's way: the entry read and the judge
# are wrapped, the first removes the target before it reads, the second plants the link when nothing is there.
T67_DIR="$T87_DIR/t67"; mkdir -p "$T67_DIR"; chmod 0755 "$T67_DIR"
# t67_plant <name> [pin] — a sticky parent holding this user's closed, empty root (with `pin` inside when asked), and a victim: a closed directory of this user's in a group-writable, non-sticky holder
t67_plant() {
  local b="$T67_DIR/$1"
  mkdir -p "$b"; chmod 0755 "$b"
  mkdir -m 1777 "$b/par"; chmod 1777 "$b/par"
  mkdir -m 0700 "$b/par/t67-root"
  [ "${2:-}" != pin ] || mkdir -m 0700 "$b/par/t67-root/pin"
  mkdir -m 0775 "$b/shared"; chmod 0775 "$b/shared"; mkdir -m 0700 "$b/shared/work"
}
# t67_vanish <seam> <root> <target> <victim> — pin <root>; <target> is removed right before its owner is read, and a link to <victim> takes its name right before the judge reads it
t67_vanish() {
  local out
  out="$(PATH="$PIN_GIVEN" T67_TARGET="$3" T67_VICTIM="$4" /bin/bash -c '. "$1" >/dev/null 2>&1 || exit 9
    eval "t67_orig_$(declare -f _bionic_pin_entry)"; eval "t67_orig_$(declare -f _bionic_pin_judge)"
    _bionic_pin_entry() { if [ "$1" = "$T67_TARGET" ]; then rmdir "$T67_TARGET"; fi; t67_orig__bionic_pin_entry "$@"; }
    _bionic_pin_judge() { if [ "$1" = "$T67_TARGET" ] && [ ! -e "$T67_TARGET" ]; then ln -s "$T67_VICTIM" "$T67_TARGET"; fi; t67_orig__bionic_pin_judge "$@"; }
    bionic_interpreter_pin "$2" 2>"$3"; echo "rc=$?"; echo "path=$PATH"' \
    t67-vanish "$1" "$2" "$TMPROOT/pin.err" 2>/dev/null)"
  PIN_RC="$(printf '%s\n' "$out" | sed -n 's/^rc=//p')"
  PIN_PATH="$(printf '%s\n' "$out" | sed -n 's/^path=//p')"
  PIN_ERR="$(cat "$TMPROOT/pin.err" 2>/dev/null)"
}
# the mutant: the absent return restored. The vanished entry passes the owner read (the defect 7.74b guards).
T67_MUT_ABS="$TMPROOT/t67-mut-absent.sh"
T67_ABS_LINE='  [ -e "$1" ] || [ -L "$1" ] || { echo "$1 does not exist"; return 0; }'
anchor "$SEAM" "$T67_ABS_LINE" 1
T67_LINE="$T67_ABS_LINE" awk 'ENVIRON["T67_LINE"] == $0 { print "  [ -e \"$1\" ] || [ -L \"$1\" ] || return 0"; next } { print }' "$SEAM" > "$T67_MUT_ABS"
t67_plant root; T67_R="$T67_DIR/root/par/t67-root"; T67_V="$T67_DIR/root/shared/work"
t67_vanish "$SEAM" "$T67_R" "$T67_R" "$T67_V"
expect_ne "7.74 a root present at the mkdir guard, removed before its owner is read, a link planted after: refused" "0" "$PIN_RC"
expect_contains "7.74b …naming the entry as not there" "$T67_R does not exist" "$PIN_ERR"
expect_eq "7.74c …and nothing is made in the victim's directory" "absent" "$(there "$T67_V/pin")"
expect_eq "7.74d …PATH is as given" "$HAND_GIVEN_PATH" "$PIN_PATH"
expect_eq "7.74e …the root is gone and nothing took its place (the harness ran the removal)" "absent" "$(there "$T67_R")"
expect_eq "7.75 the absent-return mutant parses" "0" "$(bash -n "$T67_MUT_ABS" >/dev/null 2>&1; echo $?)"
t67_plant rmut
t67_vanish "$T67_MUT_ABS" "$T67_DIR/rmut/par/t67-root" "$T67_DIR/rmut/par/t67-root" "$T67_DIR/rmut/shared/work"
expect_eq "7.75b under the mutant the vanished root builds (the defect 7.74 guards)" "0" "$PIN_RC"
expect_eq "7.75c …the planted link took its name (the harness ran the plant)" "$T67_DIR/rmut/shared/work" "$(readlink "$T67_DIR/rmut/par/t67-root")"
expect_eq "7.75d …and the pin is made in the victim's directory, which the walk refuses" "present" "$(there "$T67_DIR/rmut/shared/work/pin/bash")"
expect_eq "7.75e …and PATH carries it" "$(phys "$T67_DIR/rmut/shared/work/pin"):$HAND_GIVEN_PATH" "$PIN_PATH"
# the same for `pin`
t67_plant pin pin; T67_PR="$T67_DIR/pin/par/t67-root"; T67_PV="$T67_DIR/pin/shared/work"
t67_vanish "$SEAM" "$T67_PR" "$T67_PR/pin" "$T67_PV"
expect_ne "7.76 a pin present at the mkdir guard, removed before its owner is read, a link planted after: refused" "0" "$PIN_RC"
expect_contains "7.76b …naming the entry as not there" "$T67_PR/pin does not exist" "$PIN_ERR"
expect_eq "7.76c …and no bash link is made in the victim's directory" "absent" "$(there "$T67_PV/bash")"
expect_eq "7.76d …PATH is as given" "$HAND_GIVEN_PATH" "$PIN_PATH"
expect_eq "7.76e …the pin is gone and nothing took its name (the harness ran the removal)" "absent" "$(there "$T67_PR/pin")"
t67_plant pmut pin
t67_vanish "$T67_MUT_ABS" "$T67_DIR/pmut/par/t67-root" "$T67_DIR/pmut/par/t67-root/pin" "$T67_DIR/pmut/shared/work"
expect_eq "7.76f under the mutant the vanished pin builds (the defect 7.76 guards)" "0" "$PIN_RC"
expect_eq "7.76g …through the planted link, bash linked in the victim's directory" "present" "$(there "$T67_DIR/pmut/shared/work/bash")"
expect_eq "7.76h …and PATH carries the victim's directory" "$(phys "$T67_DIR/pmut/shared/work"):$HAND_GIVEN_PATH" "$PIN_PATH"
# the owner read alone: what it says of an absent path, a dangling link (an entry) and a real directory
mkdir -p "$T67_DIR/alone"; chmod 0755 "$T67_DIR/alone"; mkdir -m 0700 "$T67_DIR/alone/real"; ln -s "$T67_DIR/alone/nowhere" "$T67_DIR/alone/dangling"
expect_eq "7.77 _bionic_pin_entry, alone: a path that is not there is named" \
  "$(printf '%s\nrc=0' "$T67_DIR/alone/nowhere does not exist")" "$(t63_fn "$SEAM" _bionic_pin_entry "$T67_DIR/alone/nowhere")"
expect_eq "7.77b …a directory of this user's says nothing" "rc=0" "$(t63_fn "$SEAM" _bionic_pin_entry "$T67_DIR/alone/real")"
expect_eq "7.77c …and a link to nowhere is an entry: its own owner is read, this user's says nothing" "rc=0" "$(t63_fn "$SEAM" _bionic_pin_entry "$T67_DIR/alone/dangling")"
# a mkdir that fails is refused by name. The stub is first on PATH: it fails the paths its glob matches and passes the rest to the real one.
T67_STUB="$TMPROOT/t67-stub"; mkdir -p "$T67_STUB"
cat > "$T67_STUB/mkdir" <<'STUB'
#!/bin/sh
for d; do :; done
case "$d" in $T67_MKDIR_FAIL) echo "$d" >> "$T67_MKDIR_LOG"; exit 1 ;; esac
PATH=/usr/bin:/bin exec mkdir "$@"
STUB
chmod +x "$T67_STUB/mkdir"
T67_MKDIR_LOG="$TMPROOT/t67-mkdir.log"; export T67_MKDIR_LOG
# t67_mk <seam> <root> <glob> — pin_call with the mkdir stub first on PATH, failing the paths <glob> matches
t67_mk() { PIN_GIVEN="$T67_STUB:$HAND_GIVEN_PATH"; T67_MKDIR_FAIL="$3" pin_call "$1" "$2"; PIN_GIVEN="$HAND_GIVEN_PATH"; }
mkdir -p "$T67_DIR/mk"; chmod 0755 "$T67_DIR/mk"
: > "$T67_MKDIR_LOG"
t67_mk "$SEAM" "$T67_DIR/mk/ok-root" 'no-such-path'
expect_eq "7.78 the mkdir stub that fails nothing passes the real one: built" "0" "$PIN_RC"
expect_eq "7.78a …and the pin is there" "present" "$(there "$T67_DIR/mk/ok-root/pin/bash")"
t67_mk "$SEAM" "$T67_DIR/mk/no-root" '*'
expect_ne "7.78c a root that cannot be made: refused" "0" "$PIN_RC"
expect_contains "7.78d …by name, in the seam's own line" "under $T67_DIR/mk/no-root — cannot make $T67_DIR/mk/no-root, so nothing is pinned" "$PIN_ERR"
expect_eq "7.78e …PATH is as given" "$T67_STUB:$HAND_GIVEN_PATH" "$PIN_PATH"
expect_contains "7.78f …and the stub is what refused it (the harness ran the failure)" "$T67_DIR/mk/no-root" "$(cat "$T67_MKDIR_LOG")"
t67_mk "$SEAM" "$T67_DIR/mk/no-pin" '*/pin'
expect_ne "7.79 a pin that cannot be made: refused" "0" "$PIN_RC"
expect_contains "7.79b …by name" "cannot make $T67_DIR/mk/no-pin/pin, so nothing is pinned" "$PIN_ERR"
expect_eq "7.79c …the root this call made is removed" "absent" "$(there "$T67_DIR/mk/no-pin")"
expect_eq "7.79d …PATH is as given" "$T67_STUB:$HAND_GIVEN_PATH" "$PIN_PATH"
# the mutant: the mkdir refusal removed. The failure reads as a later reader's wording (the defect 7.78d guards).
T67_MUT_MK="$TMPROOT/t67-mut-mkdir.sh"
T67_MK_LINE='    mkdir -m 0700 "$1" 2>/dev/null && _BIONIC_PIN_MADE=1 || { _bionic_pin_unmade "$1" "$2"; return 0; }'
anchor "$SEAM" "$T67_MK_LINE" 1
T67_LINE="$T67_MK_LINE" awk 'ENVIRON["T67_LINE"] == $0 { print "    mkdir -m 0700 \"$1\" 2>/dev/null && _BIONIC_PIN_MADE=1"; next } { print }' "$SEAM" > "$T67_MUT_MK"
expect_eq "7.80 the no-refusal mutant parses" "0" "$(bash -n "$T67_MUT_MK" >/dev/null 2>&1; echo $?)"
t67_mk "$T67_MUT_MK" "$T67_DIR/mk/mut-root" '*'
expect_ne "7.80b under the mutant the root that cannot be made is still refused (not vacuous)" "0" "$PIN_RC"
expect_contains "7.80c …but by the entry read's wording, after the fact" "$T67_DIR/mk/mut-root does not exist" "$PIN_ERR"
expect_absent "7.80d …and not by name (the defect 7.78d guards)" "cannot make" "$PIN_ERR"
# the hand run: the chooser reads the entry through the same function, so a root that could not be made gets the path remedy, and the line carries the reason
mkdir -m 0700 "$T67_DIR/chooser"
STOP_PATH="$T67_STUB:$HAND_GIVEN_PATH" T67_MKDIR_FAIL='*' stop_run "$STOP_SUITE" "$T67_DIR/chooser"
expect_eq "7.81 a hand run whose root cannot be made exits 2" "2" "$STOP_RC"
expect_contains "7.81b …naming the reason, with the path remedy (nothing there to remove)" \
  "$(t57_line "$T67_DIR/chooser" "cannot make $T67_DIR/chooser/bionic-interpreter-pin.$STOP_UID" "$T57_FIX")" "$STOP_ERR"
expect_absent "7.81c …and runs no check" "check ran" "$STOP_LOG"
# A ROOT IS ABSOLUTE OR IT IS REFUSED (wave-28 T69; AC-10.6; pass 44 #1). The walk reads a relative root as a path
# from `.`: it judged the cwd and what lies below it and never the cwd's ancestors, while PATH carried the pin's
# ABSOLUTE physical path, which runs through every ancestor the walk skipped. T67's rows pinned the relative root
# as accepted (a relative root, CDPATH exported: built); they are reversed here. The root's refusal is the first
# thing the function does, before any walk: nothing is made, nothing is repaired with $PWD.
# The CDPATH rows come first, on T67's own plant: `cd` honours CDPATH for a path that starts with neither `/` nor
# `.`, goes to the directory CDPATH names and PRINTS it (pass 42 #2); a relative root is now refused before any cd.
T67_CD="$T67_DIR/cd"
mkdir -p "$T67_CD/cwd/tmp" "$T67_CD/elsewhere/tmp/r/pin"; chmod 0755 "$T67_CD" "$T67_CD/cwd" "$T67_CD/cwd/tmp" "$T67_CD/elsewhere"
chmod 0700 "$T67_CD/elsewhere/tmp/r" "$T67_CD/elsewhere/tmp/r/pin"; ln -s /bin/bash "$T67_CD/elsewhere/tmp/r/pin/bash"
# t67_cd <seam> <root> — pin <root> from a directory of this suite's own with CDPATH exported at another; leaves PIN_RC and T67_FIRST (PATH's first entry, a newline in it shown as ~)
t67_cd() {
  local out
  rm -rf "$T67_CD/cwd/tmp/r"
  out="$(cd "$T67_CD/cwd" && PATH="$HAND_GIVEN_PATH" CDPATH="$T67_CD/elsewhere" /bin/bash -c '. "$1" >/dev/null 2>&1 || exit 9
    bionic_interpreter_pin "$2" 2>/dev/null; echo "rc=$?"; printf "first=%s\n" "$(printf %s "${PATH%%:*}" | tr "\n" "~")"' t67-cd "$1" "$2" 2>/dev/null)"
  PIN_RC="$(printf '%s\n' "$out" | sed -n 's/^rc=//p')"
  T67_FIRST="$(printf '%s\n' "$out" | sed -n 's/^first=//p')"
}
t67_cd "$SEAM" tmp/r
expect_ne "7.82 a relative root with CDPATH exported at a directory holding the same relative path: refused" "0" "$PIN_RC"
expect_eq "7.82b …PATH's first entry is the one it was given (one line, no pin)" "$ALT_DIR" "$T67_FIRST"
expect_eq "7.82c …and nothing is made in the cwd" "absent" "$(there "$T67_CD/cwd/tmp/r")"
t67_cd "$SEAM" "$T67_CD/cwd/tmp/r"
expect_eq "7.83 the same root named absolutely, CDPATH still exported: built" "0" "$PIN_RC"
expect_eq "7.83b …PATH's first entry is one line, the physical directory the pin was built in" "$(phys "$T67_CD/cwd/tmp/r/pin")" "$T67_FIRST"
expect_eq "7.83c …and it holds bash -> /bin/bash" "/bin/bash" "$(readlink "$T67_CD/cwd/tmp/r/pin/bash" 2>/dev/null)"
# The relative root under a cwd whose holder is open: the reader's case. `gw` is group- and other-writable with no
# sticky bit, so the walk refuses anything below it named absolutely; named relatively from inside it, it was built.
T69_DIR="$T87_DIR/t69"; mkdir -p "$T69_DIR"; chmod 0755 "$T69_DIR"
T69_GW="$T69_DIR/gw"; mkdir -m 0777 "$T69_GW"; chmod 0777 "$T69_GW"; mkdir -m 0700 "$T69_GW/cwd" "$T69_GW/cwd/tmp"
# t69_rel <seam> <root> <cwd> — pin_call with <cwd> as the working directory
t69_rel() { local here="$PWD"; cd "$3" || return 1; pin_call "$1" "$2"; cd "$here" || return 1; }
t69_rel "$SEAM" "$T69_GW/cwd/tmp/abs" "$T69_GW/cwd"
expect_ne "7.84 the root named absolutely under the open holder: refused" "0" "$PIN_RC"
expect_contains "7.84b …naming the holder (the walk's answer, which the relative form never reached)" "$T69_GW is writable by group or others and has no sticky bit" "$PIN_ERR"
t69_rel "$SEAM" tmp/r "$T69_GW/cwd"
expect_ne "7.85 the same place named relatively from inside it: refused" "0" "$PIN_RC"
expect_contains "7.85b …naming the root as not an absolute path, by the seam's own line" \
  "cannot build the interpreter pin under tmp/r — tmp/r is not an absolute path, so nothing is pinned" "$PIN_ERR"
expect_eq "7.85c …nothing is made" "absent" "$(there "$T69_GW/cwd/tmp/r")"
expect_eq "7.85d …PATH is as given" "$HAND_GIVEN_PATH" "$PIN_PATH"
t69_rel "$SEAM" r "$T69_GW/cwd/tmp"
expect_contains "7.85e a bare name is refused the same way" "under r — r is not an absolute path, so nothing is pinned" "$PIN_ERR"
t69_rel "$SEAM" ./tmp/r "$T69_GW/cwd"
expect_contains "7.85f …and so is a root that begins with a dot" "under ./tmp/r — ./tmp/r is not an absolute path, so nothing is pinned" "$PIN_ERR"
expect_eq "7.85g …and nothing is made by either" "absent" "$(there "$T69_GW/cwd/tmp/r")"
mkdir -p "$T69_DIR/ok/cwd"; chmod 0755 "$T69_DIR/ok" "$T69_DIR/ok/cwd"
t69_rel "$SEAM" "$T69_DIR/ok/cwd/r" "$T69_DIR/ok/cwd"
expect_eq "7.85h control: an absolute root, the same call from a cwd of this suite's own: built" "0" "$PIN_RC"
# the mutant: the absolute test removed. The relative root builds through the open holder (the defect 7.85 guards).
T69_MUT_ABS="$TMPROOT/t69-mut-abs.sh"
T69_ABS_ARM=' /*) ;; *) why="$root is not an absolute path" ;;'
anchor "$SEAM" "$T69_ABS_ARM" 1
T69_ARM="$T69_ABS_ARM" awk '{ i = index($0, ENVIRON["T69_ARM"]); if (i) $0 = substr($0, 1, i - 1) substr($0, i + length(ENVIRON["T69_ARM"])); print }' "$SEAM" > "$T69_MUT_ABS"
expect_eq "7.86 the no-absolute-test mutant parses" "0" "$(bash -n "$T69_MUT_ABS" >/dev/null 2>&1; echo $?)"
t69_rel "$T69_MUT_ABS" "$T69_DIR/ok/cwd/mut" "$T69_DIR/ok/cwd"
expect_eq "7.86b …and builds an absolute root (not vacuous)" "0" "$PIN_RC"
t69_rel "$T69_MUT_ABS" tmp/r "$T69_GW/cwd"
expect_eq "7.86c under the mutant the relative root builds (the defect 7.85 guards)" "0" "$PIN_RC"
expect_eq "7.86d …through the open holder, and PATH carries the pin there" "$(phys "$T69_GW/cwd/tmp/r/pin"):$HAND_GIVEN_PATH" "$PIN_PATH"
# the hand run: a relative TMPDIR names a relative root. It is refused before anything is made, with the one remedy for every refusal that is the path's.
mkdir -p "$T69_DIR/hr/t"; chmod 0755 "$T69_DIR/hr"; chmod 0700 "$T69_DIR/hr/t"
T69_HR_ROOT="t/bionic-interpreter-pin.$STOP_UID"
T69_HERE="$PWD"; cd "$T69_DIR/hr" || exit 1
stop_run "$STOP_SUITE" t
cd "$T69_HERE" || exit 1
expect_eq "7.87 a hand run whose TMPDIR is a relative path to a closed directory: exits 2" "2" "$STOP_RC"
expect_contains "7.87b …naming the root as not an absolute path, with the remedy that says absolute" \
  "$(t57_line "t" "$T69_HR_ROOT is not an absolute path" "$T57_FIX")" "$STOP_ERR"
expect_contains "7.87c …the marker is unset (nothing was pinned)" "pinned=unset" "$STOP_LOG"
expect_absent "7.87d …and no check ran" "check ran" "$STOP_LOG"
expect_eq "7.87e …and nothing is made there" "absent" "$(there "$T69_DIR/hr/$T69_HR_ROOT")"
cd "$T69_DIR/hr" || exit 1
stop_run "$STOP_SUITE" .
cd "$T69_HERE" || exit 1
expect_contains "7.87f TMPDIR=. is refused the same way" \
  "$(t57_line "." "./bionic-interpreter-pin.$STOP_UID is not an absolute path" "$T57_FIX")" "$STOP_ERR"
# the lost race: a run of this user's made the root (or the pin) between the guard and our mkdir. What it made is in use, so the remedy is to run again, never to remove it.
T69_STUB="$TMPROOT/t69-stub"; mkdir -p "$T69_STUB"
cat > "$T69_STUB/mkdir" <<'STUB'
#!/bin/sh
for d; do :; done
case "$d" in $T69_RACE) PATH=/usr/bin:/bin mkdir "$@"; exit 1 ;; esac
PATH=/usr/bin:/bin exec mkdir "$@"
STUB
chmod +x "$T69_STUB/mkdir"
T69_RACE_REMEDY="run again"
# t69_race <dir> <glob> — a hand run whose mkdir of the paths <glob> matches is lost to a run of this user's
t69_race() { mkdir -m 0700 "$1"; STOP_PATH="$T69_STUB:$HAND_GIVEN_PATH" T69_RACE="$2" stop_run "$STOP_SUITE" "$1"; }
t69_race "$T69_DIR/race-root" '*/bionic-interpreter-pin.*[0-9]'
T69_RR="$T69_DIR/race-root/bionic-interpreter-pin.$STOP_UID"
expect_eq "7.88 a hand run that loses the race for the root: exits 2" "2" "$STOP_RC"
expect_eq "7.88b …the winner's root is there (the harness ran the race)" "present" "$(there "$T69_RR")"
expect_contains "7.88c …naming the reason, with the remedy run again" \
  "$(printf 'resolve-roots.sh: no interpreter pin at %s — cannot make %s; %s' "$T69_RR" "$T69_RR" "$T69_RACE_REMEDY")" "$STOP_ERR"
expect_absent "7.88d …and never offering to remove it" "remove" "$STOP_ERR"
t69_race "$T69_DIR/race-pin" '*/pin'
T69_RR="$T69_DIR/race-pin/bionic-interpreter-pin.$STOP_UID"
expect_eq "7.88e the same for the pin: exits 2, the winner's pin is there" "2:present" "$STOP_RC:$(there "$T69_RR/pin")"
expect_contains "7.88f …naming the pin, with the remedy run again" \
  "$(printf 'resolve-roots.sh: no interpreter pin at %s — cannot make %s/pin; %s' "$T69_RR" "$T69_RR" "$T69_RACE_REMEDY")" "$STOP_ERR"
expect_absent "7.88g …and never offering to remove it" "remove" "$STOP_ERR"
# the mutant: the race arm removed. The chooser offers to remove the root again (the defect 7.88 guards).
T69_MUT_RACE="$TMPROOT/t69-mut-race.sh"
T69_RACE_LINE='    race) echo "run again" ;;'
anchor "$SEAM" "$T69_RACE_LINE" 1
grep -vF "$T69_RACE_LINE" "$SEAM" > "$T69_MUT_RACE"
expect_eq "7.89 the no-race-arm mutant parses" "0" "$(bash -n "$T69_MUT_RACE" >/dev/null 2>&1; echo $?)"
mk_stop "$T69_MUT_RACE" "$TMPROOT/stop-mut-race.test.sh"
T69_MR="$T69_DIR/race-mut/bionic-interpreter-pin.$STOP_UID"
mkdir -m 0700 "$T69_DIR/race-mut"; STOP_PATH="$T69_STUB:$HAND_GIVEN_PATH" T69_RACE='*/bionic-interpreter-pin.*[0-9]' stop_run "$TMPROOT/stop-mut-race.test.sh" "$T69_DIR/race-mut"
expect_eq "7.89b under the mutant the lost race is still refused, the root is there (not vacuous)" "2:present" "$STOP_RC:$(there "$T69_MR")"
expect_contains "7.89c …and offers to remove the root (the defect 7.88d guards)" "remove $T69_MR or set TMPDIR" "$STOP_ERR"
# the seam's own repo cd follows an exported CDPATH when BASH_SOURCE is relative (a suite run `bash tests/x.test.sh` from the repo root): BIONIC_HOOKS_DIR came out as two lines, the second under the wrong tree (pass 44 #3)
mkdir -p "$T69_DIR/repo-other/tests/lib" "$T69_DIR/repo-tmp"; chmod 0755 "$T69_DIR/repo-other"; chmod 0700 "$T69_DIR/repo-tmp"
# t69_hooks <seam> <name> [cdpath] — a hand run from a repo root of its own, the shipped way, with CDPATH exported at a tree that holds tests/lib when asked; leaves T69_HOOKS (BIONIC_HOOKS_DIR as the suite saw it, a newline shown as ~)
t69_hooks() {
  local w="$T69_DIR/repo-$2" here="$PWD"
  mkdir -p "$w/tests/lib"; chmod 0755 "$w" "$w/tests" "$w/tests/lib"; cp "$1" "$w/tests/lib/resolve-roots.sh"
  cat > "$w/tests/x.test.sh" <<'SUITE'
#!/bin/bash
. "$(dirname "$0")/lib/resolve-roots.sh"
printf 'hooks=%s\n' "$(printf %s "$BIONIC_HOOKS_DIR" | tr '\n' '~')" >> "$STOP_OUT"
SUITE
  cd "$w" || return 1
  BIONIC_HOOKS_DIR="" CDPATH="${3:-}" stop_run tests/x.test.sh "$T69_DIR/repo-tmp"
  cd "$here" || return 1
  T69_HOOKS="$(printf '%s\n' "$STOP_LOG" | sed -n 's/^hooks=//p')"
}
t69_hooks "$SEAM" ctl
expect_eq "7.90 the repo cd with no CDPATH: BIONIC_HOOKS_DIR is one line, the physical hooks directory" "$(phys "$T69_DIR/repo-ctl")/hooks" "$T69_HOOKS"
t69_hooks "$SEAM" cd "$T69_DIR/repo-other"
expect_eq "7.90b …and with CDPATH exported at a tree that holds tests/lib: the same" "$(phys "$T69_DIR/repo-cd")/hooks" "$T69_HOOKS"
# the mutant: the repo cd's CDPATH unset removed (the defect 7.90b guards)
T69_MUT_REPO="$TMPROOT/t69-mut-repo.sh"
anchor "$SEAM" '_bionic_seam_repo="$(unset CDPATH; cd -- "$(dirname' 1
sed 's/_bionic_seam_repo="$(unset CDPATH; cd -- /_bionic_seam_repo="$(cd /' "$SEAM" > "$T69_MUT_REPO"
expect_eq "7.91 the repo-cd mutant parses" "0" "$(bash -n "$T69_MUT_REPO" >/dev/null 2>&1; echo $?)"
t69_hooks "$T69_MUT_REPO" mctl
expect_eq "7.91b …and gives one line where no CDPATH is exported (not vacuous)" "$(phys "$T69_DIR/repo-mctl")/hooks" "$T69_HOOKS"
t69_hooks "$T69_MUT_REPO" mcd "$T69_DIR/repo-other"
expect_contains "7.91c under the mutant, CDPATH exported, the value spans two lines (the defect 7.90b guards)" "~" "$T69_HOOKS"

# THE PIN'S cd IS PHYSICAL (wave-28 T73; AC-10.6; pass 48 #1). Bash's `cd` without -P removes `<component>/..` as TEXT
# before it calls chdir; the walk, mkdir, the hold and the judge hand `..` to the kernel, which resolves it through the
# link. For `<W>/mylink/../r` with mylink -> <W>/priv/sub the pin is judged and built under <W>/priv/r while a logical
# `cd` lands in <W>/r, a directory nobody judged. The decoy is planted at <W>/r/pin because bash falls back to the
# physical path when the textual one does not exist: without it the logical `cd` goes to the right place by luck.
T73_DIR="$T87_DIR/t73"; mkdir -p "$T73_DIR/priv/sub" "$T73_DIR/r/pin"; chmod 0755 "$T73_DIR"; chmod 0700 "$T73_DIR/priv" "$T73_DIR/priv/sub"
ln -s "$T73_DIR/priv/sub" "$T73_DIR/mylink"; : > "$T73_DIR/r/pin/bash"
pin_call "$SEAM" "$T73_DIR/mylink/../r"
expect_eq "7.92 an absolute root that passes a link and then .. : built" "0" "$PIN_RC"
expect_eq "7.92b …PATH's first entry is the pin the walk judged, under the link's target (physical)" \
  "$(phys "$T73_DIR/priv/r/pin"):$HAND_GIVEN_PATH" "$PIN_PATH"
expect_eq "7.92c …and that pin holds bash -> /bin/bash" "/bin/bash" "$(readlink "$T73_DIR/priv/r/pin/bash" 2>/dev/null)"
expect_eq "7.92d …the decoy the logical path names is untouched (a file, not the pin's link)" "regular" \
  "$([ -f "$T73_DIR/r/pin/bash" ] && [ ! -L "$T73_DIR/r/pin/bash" ] && echo regular)"
# the mutant: the pin's `cd` made logical again (the defect 7.92b guards)
T73_MUT_CD="$TMPROOT/t73-mut-cd.sh"
anchor "$SEAM" 'phys="$(cd -P -- "$dir"' 1
sed 's/phys="$(cd -P -- "$dir"/phys="$(cd -- "$dir"/' "$SEAM" > "$T73_MUT_CD"
expect_eq "7.93 the logical-cd mutant parses" "0" "$(bash -n "$T73_MUT_CD" >/dev/null 2>&1; echo $?)"
pin_call "$T73_MUT_CD" "$T73_DIR/plain"
expect_eq "7.93b …and pins a root with no link on it (not vacuous)" "$(phys "$T73_DIR/plain/pin"):$HAND_GIVEN_PATH" "$PIN_PATH"
pin_call "$T73_MUT_CD" "$T73_DIR/mylink/../r"
expect_eq "7.93c under the mutant PATH's first entry is the decoy nobody judged (the defect 7.92b guards)" \
  "$(phys "$T73_DIR/r/pin"):$HAND_GIVEN_PATH" "$PIN_PATH"
# A ROOT WITH A CONTROL CHARACTER IS REFUSED FIRST AND NEVER PRINTED RAW (T73; pass 48 #3). A newline in TMPDIR split
# the one refusal line into three. The check comes before the absolute test (a relative root with a newline is named
# for the character) and the line shows each control character as `?`.
T73_NL="$T73_DIR/nl"$'\n'"x"
pin_call "$SEAM" "$T73_NL"
expect_ne "7.94 a root with a newline in it: refused" "0" "$PIN_RC"
expect_eq "7.94b …by one line that names the root with the newline shown as ?" \
  "resolve-roots.sh: cannot build the interpreter pin under $T73_DIR/nl?x — $T73_DIR/nl?x carries a control character, so nothing is pinned" "$PIN_ERR"
expect_eq "7.94c …PATH is as given, and nothing is made" "$HAND_GIVEN_PATH:absent" "$PIN_PATH:$(there "$T73_NL")"
pin_call "$SEAM" "$T73_DIR/t"$'\t'"x"
expect_contains "7.94d a tab is a control character too" "$T73_DIR/t?x carries a control character, so nothing is pinned" "$PIN_ERR"
pin_call "$SEAM" a$'\n'b
expect_contains "7.94e a relative root with a newline is named for the character, not for being relative (the first check)" \
  "a?b carries a control character, so nothing is pinned" "$PIN_ERR"
stop_run "$STOP_SUITE" "$T73_DIR/hr"$'\n'"x"
expect_eq "7.95 a hand run whose TMPDIR holds a newline: exits 2" "2" "$STOP_RC"
expect_eq "7.95b …with ONE line, the path remedy and the character shown as ?" \
  "$(t57_line "$T73_DIR/hr?x" "$T73_DIR/hr?x/bionic-interpreter-pin.$STOP_UID carries a control character" "$T57_FIX")" "$STOP_ERR"
expect_contains "7.95c …the marker is unset (nothing was pinned)" "pinned=unset" "$STOP_LOG"
expect_absent "7.95d …and no check ran" "check ran" "$STOP_LOG"
# THE REMEDY IS KEYED ON WHICH mkdir FAILED (T73; pass 48 #2, structure #2). A root of this user's that cannot take the
# pin (read-only, a full disk) failed the same way every time, and `run again` was the remedy; only a lost race
# (7.88) is cured by running again. The two are told apart where the mkdir fails: the path is there afterwards or not.
T73_RO="$T73_DIR/ro"; mkdir -p "$T73_RO"; chmod 0700 "$T73_RO"
T73_RO_ROOT="$T73_RO/bionic-interpreter-pin.$STOP_UID"; mkdir -m 0500 "$T73_RO_ROOT"
stop_run "$STOP_SUITE" "$T73_RO"
expect_eq "7.96 a hand run whose root is this user's and read-only: exits 2" "2" "$STOP_RC"
expect_eq "7.96b …naming the pin that cannot be made, with the remedy to remove the root" \
  "$(t57_line "$T73_RO" "cannot make $T73_RO_ROOT/pin" "remove $T73_RO_ROOT or set TMPDIR")" "$STOP_ERR"
expect_eq "7.96c …the root is still there (the harness ran the failure) and no check ran" "present:" "$(there "$T73_RO_ROOT"):$(printf %s "$STOP_LOG" | grep 'check ran')"
chmod 0700 "$T73_RO_ROOT"
T73_SP="$T73_DIR/sp"; mkdir -p "$T73_SP"; chmod 0700 "$T73_SP"; mkdir -m 0700 "$T73_SP/bionic-interpreter-pin.$STOP_UID"
: > "$T67_MKDIR_LOG"
STOP_PATH="$T67_STUB:$HAND_GIVEN_PATH" T67_MKDIR_FAIL='*/pin' stop_run "$STOP_SUITE" "$T73_SP"
expect_eq "7.97 a pin whose mkdir fails and leaves nothing, in a root of this user's: exits 2, the root is there" "2:present" "$STOP_RC:$(there "$T73_SP/bionic-interpreter-pin.$STOP_UID")"
expect_eq "7.97b …naming the pin, with the remedy to remove the root" \
  "$(t57_line "$T73_SP" "cannot make $T73_SP/bionic-interpreter-pin.$STOP_UID/pin" "remove $T73_SP/bionic-interpreter-pin.$STOP_UID or set TMPDIR")" "$STOP_ERR"
expect_contains "7.97c …and the stub is what refused it (the harness ran the failure)" "$T73_SP/bionic-interpreter-pin.$STOP_UID/pin" "$(cat "$T67_MKDIR_LOG")"
# the same failure when this call made the root: it is taken down again, so there is nothing to remove
T73_SF="$T73_DIR/sf"; mkdir -p "$T73_SF"; chmod 0700 "$T73_SF"
STOP_PATH="$T67_STUB:$HAND_GIVEN_PATH" T67_MKDIR_FAIL='*/pin' stop_run "$STOP_SUITE" "$T73_SF"
expect_eq "7.98 the pin's mkdir fails in a root this call made: exits 2, the root is taken down again" "2:absent" "$STOP_RC:$(there "$T73_SF/bionic-interpreter-pin.$STOP_UID")"
expect_eq "7.98b …and the remedy is the path's (nothing there to remove)" \
  "$(t57_line "$T73_SF" "cannot make $T73_SF/bionic-interpreter-pin.$STOP_UID/pin" "$T57_FIX")" "$STOP_ERR"
# the mutant: a root taken down again no longer changes the class. The remedy offers to remove what is not there (the defect 7.98b guards).
T73_MUT_ENT="$TMPROOT/t73-mut-entry.sh"
anchor "$SEAM" 'rmdir "$root" 2>/dev/null && _BIONIC_PIN_CLASS=entry' 1
sed 's/rmdir "$root" 2>\/dev\/null && _BIONIC_PIN_CLASS=entry/rmdir "$root" 2>\/dev\/null/' "$SEAM" > "$T73_MUT_ENT"
expect_eq "7.99 the taken-down-root mutant parses" "0" "$(bash -n "$T73_MUT_ENT" >/dev/null 2>&1; echo $?)"
mk_stop "$T73_MUT_ENT" "$TMPROOT/stop-mut-ent.test.sh"
T73_SM="$T73_DIR/sm"; mkdir -p "$T73_SM"; chmod 0700 "$T73_SM"
STOP_PATH="$T67_STUB:$HAND_GIVEN_PATH" T67_MKDIR_FAIL='*/pin' stop_run "$TMPROOT/stop-mut-ent.test.sh" "$T73_SM"
expect_eq "7.99b under the mutant the pin is still refused and the root taken down (not vacuous)" "2:absent" "$STOP_RC:$(there "$T73_SM/bionic-interpreter-pin.$STOP_UID")"
expect_contains "7.99c …but it offers to remove the root that is not there (the defect 7.98b guards)" "remove $T73_SM/bionic-interpreter-pin.$STOP_UID or set TMPDIR" "$STOP_ERR"

# The rights that grant rights, on macOS: writesecurity and chown let their holder grant itself the rest.
if [ "$T57_ACL" = 1 ]; then
  T59_MUT_WS="$TMPROOT/t59-mut-ws.sh"; T59_MUT_CH="$TMPROOT/t59-mut-chown.sh"
  anchor "$SEAM" ' writesecurity chown; do' 1
  sed 's/ writesecurity chown; do/ chown; do/' "$SEAM" > "$T59_MUT_WS"
  sed 's/ writesecurity chown; do/ writesecurity; do/' "$SEAM" > "$T59_MUT_CH"
  expect_eq "7.54 the two rights mutants parse" "0" "$(bash -n "$T59_MUT_WS" >/dev/null 2>&1 && bash -n "$T59_MUT_CH" >/dev/null 2>&1; echo $?)"
  for t59_right in writesecurity chown; do
    T59_RD="$T87_DIR/t59-right-$t59_right"; mkdir -p "$T59_RD"; chmod 0700 "$T59_RD"
    chmod +a "everyone allow $t59_right" "$T59_RD"
    expect_eq "7.55 [$t59_right] the ACL extractor reads the entry" "1" "$(ls -lde "$T59_RD" | grep -c "group:everyone allow $t59_right")"
    stop_run "$STOP_SUITE" "$T59_RD"
    expect_eq "7.55b [$t59_right] a 0700 temp directory whose ACL lets everyone have it: the hand run exits 2" "2" "$STOP_RC"
    expect_contains "7.55c [$t59_right] …naming the entry" \
      "$(t57_line "$T59_RD" "$T59_RD carries an ACL letting group:everyone $t59_right" "$T57_FIX")" "$STOP_ERR"
    expect_eq "7.55d [$t59_right] …and builds nothing there" "absent" "$(there "$T59_RD/bionic-interpreter-pin.$STOP_UID")"
    case "$t59_right" in writesecurity) t59_mut="$T59_MUT_WS" t59_ctl="$T59_MUT_CH" ;; *) t59_mut="$T59_MUT_CH" t59_ctl="$T59_MUT_WS" ;; esac
    pin_call "$t59_mut" "$T59_RD/mut-root"
    expect_eq "7.55e [$t59_right] with that right dropped from the list the entry is accepted (the defect 7.55b guards)" "0" "$PIN_RC"
    pin_call "$t59_ctl" "$T59_RD/ctl-root"
    expect_ne "7.55f [$t59_right] …and the other mutant still refuses it (not vacuous)" "0" "$PIN_RC"
    chmod -N "$T59_RD" 2>/dev/null
  done
else
  skip "7.54 the rights that grant rights (macOS: writesecurity and chown on a 0700 directory)" \
    "chmod +a is not available on this host"
fi

# THE MUTANTS. (1) The hand path's refusal turned back into `|| :`: the refused run goes on and
# runs its check. (2) The parent check removed: the open parent is accepted. Each mutant is proved
# to run before its claim is read.
T36_MUT1="$TMPROOT/t36-mut-runon.sh"
anchor "$SEAM" 'if ! bionic_interpreter_pin "$_bionic_pin_root" 2>/dev/null; then' 1
sed 's|if ! bionic_interpreter_pin "$_bionic_pin_root" 2>/dev/null; then|if ! { bionic_interpreter_pin "$_bionic_pin_root" \|\| :; }; then|' \
  "$SEAM" > "$T36_MUT1"
expect_eq "7.29 the run-on mutant parses" "0" "$(bash -n "$T36_MUT1" >/dev/null 2>&1; echo $?)"
mk_stop "$T36_MUT1" "$TMPROOT/stop-mut1.test.sh"
stop_run "$TMPROOT/stop-mut1.test.sh" "$T36_OK"
expect_eq "7.29b …and runs a hand suite whose pin is fine (not vacuous)" "0" "$STOP_RC"
stop_run "$TMPROOT/stop-mut1.test.sh" "$T36_LINK"
expect_contains "7.29c under the run-on mutant a refused pin runs its check (the defect 7.24c guards)" \
  "check ran" "$STOP_LOG"
T36_MUT2="$TMPROOT/t36-mut-parent.sh"
anchor "$SEAM" '[ -n "$why" ] || why="$(_bionic_pin_parent "$root")"' 1
grep -vF '[ -n "$why" ] || why="$(_bionic_pin_parent "$root")"' "$SEAM" > "$T36_MUT2"
expect_eq "7.30 the parent mutant parses" "0" "$(bash -n "$T36_MUT2" >/dev/null 2>&1; echo $?)"
R="$T87_DIR/t36-mut-sticky-root"; pin_call "$T36_MUT2" "$R"
expect_eq "7.30b …and builds a pin in a plain directory (not vacuous)" "0" "$PIN_RC"
R="$T36_OPEN/mut-root"; pin_call "$T36_MUT2" "$R"
expect_eq "7.30c under the parent mutant the open parent is accepted (the defect 7.28 guards)" "0" "$PIN_RC"
echo ""

echo "interpreter-pin: ${SKIPPED} skipped (see SKIP: rows above)"
finish
