#!/bin/bash
# Tests for the claude() line bionic's setup writes into the shell rc (wave-36 T1, spec D7, ADR-055;
# AC-1.1). §PROXY.
#
# THE FACT UNDER TEST. A session started inside a bionic checkout runs the checkout: the rc line adds
# `--plugin-dir <root>/payload` when the cwd is inside a git checkout whose payload/.claude-plugin/
# plugin.json names bionic, from any directory of it, and adds nothing anywhere else. It keeps
# `--allow-dangerously-skip-permissions`, and calls the binary through `command claude`.
#
# DRIVEN, NOT READ. The line is written by setup.sh itself into a sandbox HOME, then an interactive
# zsh and an interactive bash read that rc and type `claude`; a stub `claude` on PATH records the
# argv it was handed, one argument per line. A stub `git` logs each call, so the cost is pinned too:
# a shell starting reads the function and runs nothing, a `claude` call runs git once.
#
# Usage: bash tests/setup.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"

PAYLOAD="${BIONIC_SCRIPTS_DIR}/payload"
SETUP_SH="${PAYLOAD}/scripts/setup.sh"
DETECT_SH="${PAYLOAD}/scripts/lib/detect.sh"
ENV_SH="${PAYLOAD}/scripts/lib/env.sh"
[ -f "$SETUP_SH" ] || { echo "setup: no setup.sh at $SETUP_SH — suite refuses to run"; exit 1; }
command -v zsh >/dev/null 2>&1 || { echo "setup: zsh absent — suite cannot run"; exit 1; }
REAL_GIT="$(command -v git)" || { echo "setup: git absent — suite cannot run"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd -P)"

# The stubs: `claude` records its argv; `git` logs its call and runs the real one.
STUB="$TMP/stub"; mkdir -p "$STUB"
ARGV="$TMP/argv"; GITLOG="$TMP/git.log"
printf '#!/bin/sh\n: > "%s"\nfor a in "$@"; do printf "%%s\\n" "$a" >> "%s"; done\n' "$ARGV" "$ARGV" > "$STUB/claude"
printf '#!/bin/sh\necho "git $*" >> "%s"\nexec "%s" "$@"\n' "$GITLOG" "$REAL_GIT" > "$STUB/git"
chmod +x "$STUB/claude" "$STUB/git"

# A bionic checkout, with a deep directory in it; a checkout of something else; a repo with no payload.
CO="$TMP/bionic-co"; mkdir -p "$CO/payload/.claude-plugin" "$CO/deep/er"
printf '{\n  "name": "bionic",\n  "version": "9.9.9"\n}\n' > "$CO/payload/.claude-plugin/plugin.json"
OTHER="$TMP/other-co"; mkdir -p "$OTHER/payload/.claude-plugin"
printf '{"name":"not-bionic","author":{"name":"x"}}\n' > "$OTHER/payload/.claude-plugin/plugin.json"
BARE="$TMP/bare-repo"; mkdir -p "$BARE/src"
OUTSIDE="$TMP/outside"; mkdir -p "$OUTSIDE"
for r in "$CO" "$OTHER" "$BARE"; do
  "$REAL_GIT" -C "$r" init -q && : > "$r/.keep" && "$REAL_GIT" -C "$r" add -A \
    && "$REAL_GIT" -C "$r" -c user.email=t@t -c user.name=t commit -qm fixture
done

setup_run() {  # <sandbox> <shell path>
  printf 'y\n' | HOME="$1" ZDOTDIR="$1" SHELL="$2" PATH="$STUB:$PATH" BIONIC_CLAUDE_HOME="$1/.claude" \
    bash "$SETUP_SH" --only claude-proxy 2>&1
}
# type_claude <sandbox> <zsh|bash> <dir> [args...] — an interactive shell of that kind reads the
# sandbox's rc, cds to <dir>, and types `claude <args>`. The argv file is what the binary was handed.
type_claude() {
  local sb="$1" sh="$2" dir="$3"; shift 3
  rm -f "$ARGV"
  case "$sh" in
    zsh)  HOME="$sb" ZDOTDIR="$sb" PATH="$STUB:$PATH" zsh -ic 'cd "$1" && shift && claude "$@"' _ "$dir" "$@" >/dev/null 2>&1 ;;
    bash) HOME="$sb" PATH="$STUB:$PATH" bash --rcfile "$sb/.bashrc" -ic 'cd "$1" && shift && claude "$@"' _ "$dir" "$@" >/dev/null 2>&1 ;;
  esac
  cat "$ARGV" 2>/dev/null
}

SB_Z="$TMP/sb-zsh"; mkdir -p "$SB_Z/.claude"
SB_B="$TMP/sb-bash"; mkdir -p "$SB_B/.claude"
setup_run "$SB_Z" /bin/zsh >/dev/null
setup_run "$SB_B" /bin/bash >/dev/null

section "PROXY — the line setup writes"
expect_contains "P1 setup wrote bionic's block into .zshrc" "bionic:rc:start" "$(cat "$SB_Z/.zshrc" 2>/dev/null)"
expect_contains "P2 …and into .bashrc for bash" "bionic:rc:start" "$(cat "$SB_B/.bashrc" 2>/dev/null)"
expect_contains "P3 …calling the binary, never the function" "command claude --allow-dangerously-skip-permissions" "$(cat "$SB_Z/.zshrc")"

for SH in zsh bash; do
  SB="$SB_Z"; [ "$SH" = bash ] && SB="$SB_B"
  section "PROXY — $SH: inside a bionic checkout, the checkout's payload"
  expect_eq "P4 $SH at the checkout's top: bypass kept, --plugin-dir <root>/payload, then the args" \
    "$(printf '%s\n' --allow-dangerously-skip-permissions --plugin-dir "$CO/payload" one)" \
    "$(type_claude "$SB" "$SH" "$CO" one)"
  expect_eq "P5 $SH two directories down: the same root" \
    "$(printf '%s\n' --allow-dangerously-skip-permissions --plugin-dir "$CO/payload" one)" \
    "$(type_claude "$SB" "$SH" "$CO/deep/er" one)"
  expect_eq "P6 $SH an argument with a space survives whole" \
    "$(printf '%s\n' --allow-dangerously-skip-permissions --plugin-dir "$CO/payload" 'a b' c)" \
    "$(type_claude "$SB" "$SH" "$CO" 'a b' c)"

  section "PROXY — $SH: anywhere else, nothing added"
  expect_eq "P7 $SH outside any checkout: bypass and the args, no flag" \
    "$(printf '%s\n' --allow-dangerously-skip-permissions one)" "$(type_claude "$SB" "$SH" "$OUTSIDE" one)"
  expect_eq "P8 $SH a checkout whose payload names another plugin: no flag" \
    "$(printf '%s\n' --allow-dangerously-skip-permissions one)" "$(type_claude "$SB" "$SH" "$OTHER" one)"
  expect_eq "P9 $SH a repository with no payload: no flag" \
    "$(printf '%s\n' --allow-dangerously-skip-permissions one)" "$(type_claude "$SB" "$SH" "$BARE/src" one)"
done

section "PROXY — cheap: a shell start runs nothing, a call runs git once"
rm -f "$GITLOG"
HOME="$SB_Z" ZDOTDIR="$SB_Z" PATH="$STUB:$PATH" zsh -ic 'true' >/dev/null 2>&1
G_START="$(grep -c . "$GITLOG" 2>/dev/null)"; G_START="${G_START:-0}"
type_claude "$SB_Z" zsh "$CO/deep/er" x >/dev/null
G_CALL="$(grep -c . "$GITLOG" 2>/dev/null)"; G_CALL="${G_CALL:-0}"
expect_eq "P10 a claude call runs git exactly once (the extractor reads the log)" "1" "$((G_CALL - G_START))"
expect_eq "P11 …and a shell starting runs it never (positive: P10)" "0" "$G_START"

section "PROXY — the line setup wrote before this one is stale, and setup rewrites it"
SB_OLD="$TMP/sb-old"; mkdir -p "$SB_OLD/.claude"
{ printf '%s\n' '# ─── bionic:rc:start ───' 'unalias claude 2>/dev/null || true' \
    'claude() { command claude --allow-dangerously-skip-permissions "$@"; }' '# ─── bionic:rc:end ───'; } > "$SB_OLD/.zshrc"
detect_proxy() { HOME="$1" SHELL=/bin/zsh BIONIC_CLAUDE_HOME="$1/.claude" bash -c '. "$1"; detect_rc_claude_proxy' _ "$DETECT_SH" 2>/dev/null; }
expect_eq "P12 doctor's reader calls the 1.18.0 line stale" "env:rc-claude-proxy present=stale" "$(detect_proxy "$SB_OLD")"
setup_run "$SB_OLD" /bin/zsh >/dev/null
expect_eq "P13 setup's yes rewrites it, and the reader calls it written" "env:rc-claude-proxy present=yes" "$(detect_proxy "$SB_OLD")"
expect_eq "P14 …and the rewritten block launches the checkout" \
  "$(printf '%s\n' --allow-dangerously-skip-permissions --plugin-dir "$CO/payload" one)" "$(type_claude "$SB_OLD" zsh "$CO" one)"

finish
