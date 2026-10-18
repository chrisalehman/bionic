#!/bin/bash
# tests/reads-hash.test.sh — payload/scripts/lib/anchors.sh `reads_set` and `reads_hash`, the proof fact's key
# (wave-39 T1; D5, D8, A-orch-3; REQ-1 AC-1.3; ADR-061).
#
# WHAT THIS SUITE OWNS. A verdict is keyed by what its suite read. `reads_set <root> <at> <suite>` prints the
# suite's read set at a commit: what `reads_index` derives for it, closed over the scripts in it (what each
# names, its BIONIC_LIB_WANT list, so a library loaded by a library is read), plus the suite file and its
# prelude. `reads_hash <root> <at> <suite>` is sha256 over the set's sorted `<path> <blob>` lines; a suite whose
# closure holds a load whose file name is computed (`. "$d/$name"`) is keyed by the whole tree,
# `tree:<tree id>`, so it is reused only on an identical tree.
#
#   §TREE     a suite loading a computed file name: `tree:<tree id>`, and two differing trees give two keys
#             (AC-1.3); a literal suite's key is a sha256 and survives a change outside its read set
#   §CLOSURE  a hook's WANT library loading another library by a variable: the second library is read, and a
#             change to it changes the key; `reads_index` itself is unchanged
#   §KEY      the key is sha256 over the sorted `<path> <blob>` lines, the suite file and its prelude among them
#   §AT       the commit is read, never the working tree
#   §LIVE     this repository at HEAD: the closure reaches payload/scripts/lib/line.sh from
#             tests/session-poker.test.sh, which runs hooks/session-poker.sh, and keys it by content
#
# FIXTURE FIDELITY: the tree under $F is SYNTHESIZED; nothing in it is run, the set is read from text.
# ANTI-VACUITY: every absence sits beside a positive read off the same set of the same fixture.
#
# Usage: bash tests/run.sh --only reads-hash.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"

REPO="${BIONIC_SCRIPTS_DIR}"
ANCHORS="$REPO/payload/scripts/lib/anchors.sh"

SB="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/reads-hash-test.XXXXXX")" && pwd)"
trap 'rm -rf "$SB"' EXIT
F="$SB/tree"

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0

rh_set() { ( . "$ANCHORS" && reads_set "$@" ) 2>/dev/null; }      # <root> <at> <suite>
rh_hash() { ( . "$ANCHORS" && reads_hash "$@" ) 2>/dev/null; }    # <root> <at> <suite>
rh_index() { ( . "$ANCHORS" && reads_index "$@" ) 2>/dev/null; }  # <root> <at>
rh_commit() { git -C "$F" add -A && git -C "$F" commit -qm "$1" && git -C "$F" rev-parse HEAD; }   # <message> -> the commit
rh_sha() { if command -v shasum >/dev/null 2>&1; then shasum -a 256; else sha256sum; fi | awk '{ print $1 }'; }

# ------------------------------------------------------------
setup_section "plant the fixture tree and commit it"
# ------------------------------------------------------------
mkdir -p "$F/payload/scripts/lib" "$F/hooks" "$F/tests"
git -C "$F" init -q && git -C "$F" config user.email t@t && git -C "$F" config user.name t && git -C "$F" config commit.gpgsign false
# a.sh loads b.sh by a variable, the way lib/worktree.sh loads lib/line.sh: a library loaded by a library.
cat > "$F/payload/scripts/lib/a.sh" <<'PLANT'
lib="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/b.sh"
[ -r "$lib" ] && . "$lib"
PLANT
printf 'echo b\n' > "$F/payload/scripts/lib/b.sh"
printf 'echo c, read by no suite\n' > "$F/payload/scripts/lib/c.sh"
cat > "$F/hooks/h.sh" <<'PLANT'
#!/bin/bash
BIONIC_LIB_WANT="a.sh"
. "$BIONIC_LIB/a.sh"
PLANT
cat > "$F/tests/s-hook.test.sh" <<'PLANT'
#!/bin/bash
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
bash "$ROOT/hooks/h.sh"
PLANT
# A file name built at run time: no text names what it loads.
cat > "$F/tests/s-var.test.sh" <<'PLANT'
#!/bin/bash
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
name="$(ls "$ROOT/payload/scripts/lib" | head -1)"
. "$ROOT/payload/scripts/lib/$name"
PLANT
# A loop over literal names is resolved: each name is spelled.
cat > "$F/tests/s-loop.test.sh" <<'PLANT'
#!/bin/bash
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
for f in b.sh; do . "$ROOT/payload/scripts/lib/$f"; done
PLANT
# A suite that never names its prelude still reads it (D8).
printf '#!/bin/bash\necho pre\n' > "$F/tests/s-pre.test.sh"
printf 'echo prelude\n' > "$F/tests/s-pre.prelude.sh"
C1="$(rh_commit one)"
expect_nonempty "(fixture) the first commit" "$C1"

# ------------------------------------------------------------
section "§TREE: a suite loading a computed file name is keyed by the whole tree; two trees, two keys (AC-1.3)"
# ------------------------------------------------------------
T1="$(git -C "$F" rev-parse "$C1^{tree}")"
K1="$(rh_hash "$F" "$C1" tests/s-var.test.sh)"
expect_eq "TREE: s-var, which loads \"\$ROOT/…/\$name\", is keyed tree:<the commit's tree>" "tree:$T1" "$K1"
expect_contains "TREE: …and reads_set says why, naming the load" "tree " "$(rh_set "$F" "$C1" tests/s-var.test.sh)"
printf 'echo c, changed\n' > "$F/payload/scripts/lib/c.sh"
C2="$(rh_commit two)"
K2="$(rh_hash "$F" "$C2" tests/s-var.test.sh)"
expect_eq "TREE: at a second commit it is keyed by that tree" "tree:$(git -C "$F" rev-parse "$C2^{tree}")" "$K2"
expect_ne "TREE: …so two trees that differ give two keys: no reuse across them" "$K1" "$K2"
H1="$(rh_hash "$F" "$C1" tests/s-hook.test.sh)"
expect_regex "TREE: a suite whose loads all resolve is keyed by a sha256 of its reads, not the tree" '^[0-9a-f]{64}$' "$H1"
expect_eq "TREE: …which a change outside its read set (c.sh) leaves alone" "$H1" "$(rh_hash "$F" "$C2" tests/s-hook.test.sh)"
expect_regex "TREE: a loop over spelled names (for f in b.sh) resolves: a sha256" '^[0-9a-f]{64}$' "$(rh_hash "$F" "$C1" tests/s-loop.test.sh)"
expect_contains "TREE: …and reads what it names" "payload/scripts/lib/b.sh" "$(rh_set "$F" "$C1" tests/s-loop.test.sh)"
expect_eq "TREE: a suite the commit lacks is keyed by the tree" "tree:$T1" "$(rh_hash "$F" "$C1" tests/nope.test.sh)"

# ------------------------------------------------------------
section "§CLOSURE: the read set closes over a library loaded by a library (A-orch-3)"
# ------------------------------------------------------------
expect_eq "CLOSURE: s-hook reads the hook, its WANT library a.sh, the library a.sh loads (b.sh) and itself" \
  "$(printf '%s\n' hooks/h.sh payload/scripts/lib/a.sh payload/scripts/lib/b.sh tests/s-hook.test.sh)" \
  "$(rh_set "$F" "$C1" tests/s-hook.test.sh)"
printf 'echo b, changed\n' > "$F/payload/scripts/lib/b.sh"
C3="$(rh_commit three)"
expect_ne "CLOSURE: a change to b.sh changes s-hook's key" "$H1" "$(rh_hash "$F" "$C3" tests/s-hook.test.sh)"
IX="$(rh_index "$F" "$C1")"
expect_contains "CLOSURE: reads_index itself still names s-hook for a.sh (rule 2)" "$(printf 'payload/scripts/lib/a.sh\ttests/s-hook.test.sh')" "$IX"
expect_no_match "CLOSURE: …and is unchanged by the closure: nothing names s-hook for b.sh there" "payload/scripts/lib/b\\.sh.*s-hook" "$IX"

# ------------------------------------------------------------
section "§KEY: sha256 over the sorted <path> <blob> lines, the suite file and its prelude among them (D8)"
# ------------------------------------------------------------
PS="$(rh_set "$F" "$C1" tests/s-pre.test.sh)"
expect_eq "KEY: s-pre's set is the suite and its prelude, which it never names" \
  "$(printf '%s\n' tests/s-pre.prelude.sh tests/s-pre.test.sh)" "$PS"
WANT="$(git -C "$F" ls-tree -r "$C1" -- hooks/h.sh payload/scripts/lib/a.sh payload/scripts/lib/b.sh tests/s-hook.test.sh \
  | awk -F'\t' '{ split($1, m, " "); print $2 " " m[3] }' | LC_ALL=C sort | rh_sha)"
expect_eq "KEY: s-hook's key is sha256 of its four sorted '<path> <blob>' lines" "$WANT" "$H1"

# ------------------------------------------------------------
section "§AT: the commit is read, never the working tree"
# ------------------------------------------------------------
K3="$(rh_hash "$F" "$C3" tests/s-hook.test.sh)"
expect_regex "(at) s-hook's key at the third commit" '^[0-9a-f]{64}$' "$K3"
printf 'echo b, uncommitted\n' > "$F/payload/scripts/lib/b.sh"
expect_contains "(at) …the edit is there to be read: the working tree differs from the commit" "payload/scripts/lib/b.sh" "$(git -C "$F" status --porcelain)"
expect_eq "AT: an uncommitted edit to b.sh leaves the key at the commit as it was" "$K3" "$(rh_hash "$F" "$C3" tests/s-hook.test.sh)"

# ------------------------------------------------------------
section "§LIVE: this repository at HEAD — the closure reaches lib/line.sh from a suite that runs hooks/session-poker.sh"
# ------------------------------------------------------------
LH="$(git -C "$REPO" rev-parse --verify -q HEAD)"
expect_nonempty "(live) the repository under test has a HEAD" "$LH"
LS="$(rh_set "$REPO" "$LH" tests/session-poker.test.sh)"
expect_contains "LIVE: session-poker.test.sh reads hooks/session-poker.sh" "hooks/session-poker.sh" "$LS"
expect_contains "LIVE: …and, through the closure, payload/scripts/lib/line.sh" "payload/scripts/lib/line.sh" "$LS"
expect_regex "LIVE: …and its key is a sha256 of its reads, not the tree" '^[0-9a-f]{64}$' "$(rh_hash "$REPO" "$LH" tests/session-poker.test.sh)"

finish
