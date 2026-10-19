# tests/rc-item.prelude.sh — THE HALF OF THE RC-ITEM SUITE EVERY PART SHARES (wave-39 T38; D1, D13, REQ-3 AC-3.3).
#
# Sourced by tests/rc-item-1.test.sh and tests/rc-item-2.test.sh, after tests/lib/resolve-roots.sh and
# tests/lib/assert.sh. It is not a suite: the runner launches `*.test.sh` only. It sits beside the parts rather
# than under tests/lib/ so the reads index follows it from each part's `source` line, one hop (lib/anchors.sh, the
# prelude hop), and an edit to it is answered with these two suites, not the full run.
#
# WHY TWO PARTS. One rc-item.test.sh promised 505 s on the gate on its last solo run and more under load, near
# the suite bar (lib/line.sh LINE_SUITE_BAR, ten minutes of promise; D1), so it is cut at a section boundary
# into two suites of about equal cost, every section kept whole and in its order. Part 1 is the sections through
# "wave-27 T66" (18 sections); part 2 is the four sections that follow it, "wave-27 T75" through "wave-27 T78".
#
# WHAT IT HOLDS. The fixture the old suite kept above its first section (the literals under test, the claude and
# git stubs, the planted rcs, the extractors and the drivers), and each helper or constant a section in part 1
# defined that a section in part 2 calls. A hoisted block, at the foot of this file, is marked with the section it
# came from, and that section keeps a one-line pointer where it stood.
#
# WHAT IT NEVER HOLDS. A fixture one section builds and a later one reads. The one thing here that looks like
# one, the standalone copy of remove.sh, is a single cp of the payload that no section changes.
#
# THE OLD SUITE'S HEADER follows, unchanged: it is the contract of both parts.
#
# THE RC ITEM — epic-18 wave-03 task 4/7 (spec §R6, AC-5, AC-6, AC-7).
#
# WHAT THIS SUITE OWNS. The `claude()` shell proxy as a SETUP-MANAGED ITEM: the
# marker-delimited block bionic owns in the user's shell rc, the roster and the
# write/read/delete in payload/scripts/lib/env.sh, the consented step in
# setup.sh that offers it, the row doctor.sh renders for it, and the strip
# remove.sh performs through both of its doors.
#
# WHY A SHELL FUNCTION AND NOT A LINE SOMEONE PASTES. The launch flag has to
# reach the `claude` a person types, and the only place that can happen is
# their shell rc — no settings.json key is equivalent, because the CLI decides
# bypass availability from argv (epic-19 W1, record/epic-19/w1/s1-f2-probe.md).
# A line written there by hand is footprint doctor cannot report
# and remove cannot strip; inside bionic's markers it is an item with an owner —
# offered once with a why, reported present or absent, and taken back out on
# request. That is the whole reason this file exists (Chris 2026-08-23: "It may
# only be made if it is permanently added").
#
# EVERY NEGATIVE HERE HAS A POSITIVE BESIDE IT, ON THE SAME EXTRACTOR AND THE
# SAME FIXTURE (.claude/rules/test-harness.md,
# "Anti-vacuity"). `rc_block_lines` is asserted non-empty after
# a consented setup before it is asserted empty before one; the `type claude`
# readback is asserted to name a shell function after setup before it is
# asserted not to before setup. An extractor that returned the empty string for
# every input would fail the positive arm and take its negative twin with it.
#
# NO awk EQUALITY ON THE MARKER GLYPHS. The markers are box-drawing dashes, and
# an `awk '$0 == marker'` comparison on them is locale-dependent — it has
# silently matched nothing before. Every comparison below is bash's own `[ = ]`
# or a `case` pattern, in-process.
#
# ASSERTION-HELPER RACE. No `printf | grep -q` anywhere: containment is bash
# `case`, and the only reads of a file are bash `read` loops.
#
# HERMETIC. Every arm builds its own $HOME under $TMP, plants its own .zshrc,
# and points the payload at it with HOME/ZDOTDIR/SHELL/BIONIC_CLAUDE_HOME. The
# real ~/.zshrc is never read and never written. `claude` is a stub on a
# prepended PATH so no arm asks the live CLI anything.

REPO="${BIONIC_SCRIPTS_DIR}"
ENV_SH="${REPO}/payload/scripts/lib/env.sh"
DETECT_SH="${REPO}/payload/scripts/lib/detect.sh"
SETUP_SH="${REPO}/payload/scripts/setup.sh"
DOCTOR_SH="${REPO}/payload/scripts/doctor.sh"
REMOVE_SH="${REPO}/payload/scripts/remove.sh"

# expect_same_bytes and expect_diff_bytes: defined in each part, above the source of this file (the framework
# derives a suite's helper calls from the suite's own text, before this file is sourced).

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

command -v zsh >/dev/null 2>&1 || { echo "${0##*/}: zsh is required — the readback arm runs the rc"; exit 1; }
command -v jq  >/dev/null 2>&1 || { echo "${0##*/}: jq is required"; exit 1; }

# ---------------------------------------------------------------------------
# The literals under test
#
# SPELLED HERE, AND PINNED TO THE PAYLOAD BELOW. The suite has to look for the
# markers to find the block, so it carries them; the pins that follow are what
# make that carriage a pin and not a second source of truth — env.sh's constants
# must equal these, and remove.sh's standalone copies must equal env.sh's.
# ---------------------------------------------------------------------------
RC_START_LIT='# ─── bionic:rc:start ───'
RC_END_LIT='# ─── bionic:rc:end ───'
# The function, six lines (wave-36 T1): it launches the checkout it is typed in. Built line by
# line, so `PROXY_LINE` is the function's text with no trailing newline, as one `printf '%s\n'`
# argument writes it. `PROXY_CALL` is its one line that names the call, for a count.
PROXY_LINE="$(printf '%s\n' 'claude() {' \
  '  local r; r="$(git rev-parse --show-toplevel 2>/dev/null)" || r=""' \
  "  if [ -n \"\$r\" ] && grep -Eqs '\"name\" *: *\"bionic\"' \"\$r/payload/.claude-plugin/plugin.json\"" \
  '  then set -- --plugin-dir "$r/payload" "$@"; fi' \
  '  command claude --allow-dangerously-skip-permissions "$@"' \
  '}')"
PROXY_CALL='  command claude --allow-dangerously-skip-permissions "$@"'
PROXY_N="$(printf '%s\n' "$PROXY_LINE" | wc -l | tr -d ' ')"   # the function's line count
# The function line bionic wrote from 40be1c30 through 1.18.0 (wave-36 T1 put the checkout's
# `--plugin-dir` in front): alone, the pre-T75 body; under the unalias line, the 1.18.0 body.
# Both are `rc_earlier` bodies, so a block holding either is stale, never changed.
PROXY_LINE_118='claude() { command claude --allow-dangerously-skip-permissions "$@"; }'
# The block's first line clears an alias named `claude`, which would otherwise expand
# into the function's definition line (wave-27 T75, A-orch-185). The body is both.
PROXY_UNALIAS='unalias claude 2>/dev/null || true'
PROXY_BODY="$(printf '%s\n%s' "$PROXY_UNALIAS" "$PROXY_LINE")"
DOCTOR_ROW_LABEL='claude() shell proxy'

# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

mkdir -p "$TMP/bin"
cat > "$TMP/bin/claude" <<'STUB'
#!/bin/bash
case "$*" in
  "plugin list --json") echo '[]' ;;
  *) exit 0 ;;
esac
STUB
chmod +x "$TMP/bin/claude"

# NO NETWORK (wave-33 T31). Every yes-answered `setup --all` door clones humanizer, a
# `github-skill` row (`git clone --depth 1 https://github.com/<slug>.git <dest>`), and the
# system git sits on every arm's PATH. A `git` stub beside the claude one serves any clone of a
# github.com URL from a local repository built once here, holding the SKILL.md the probe reads,
# and passes every other git call to the real git, named by its absolute path.
REAL_GIT="$(command -v git)"
[ -x "$REAL_GIT" ] || { echo "${0##*/}: git is required"; exit 1; }
FIXTURE_SKILL="$TMP/fixture-skill"
mkdir -p "$FIXTURE_SKILL"
printf -- '---\nname: fixture-skill\ndescription: a local stand-in for a cloned skill\n---\n' > "$FIXTURE_SKILL/SKILL.md"
"$REAL_GIT" -C "$FIXTURE_SKILL" init -q \
  && "$REAL_GIT" -C "$FIXTURE_SKILL" add SKILL.md \
  && "$REAL_GIT" -C "$FIXTURE_SKILL" -c user.name=fixture -c user.email=fixture@invalid commit -q -m fixture \
  || { echo "${0##*/}: the local skill fixture could not be built — suite refuses to run"; exit 1; }
cat > "$TMP/bin/git" <<STUB
#!/bin/bash
if [ "\${1:-}" = clone ]; then
  args=()
  for a in "\$@"; do
    case "\$a" in https://github.com/*|git@github.com:*) a="file://$FIXTURE_SKILL" ;; esac
    args+=("\$a")
  done
  exec "$REAL_GIT" "\${args[@]}"
fi
exec "$REAL_GIT" "\$@"
STUB
chmod +x "$TMP/bin/git"

# The rc every arm starts from: three lines that are not bionic's, and which
# every assertion below requires to come back byte-identical.
plant_rc() {  # <file>
  cat > "$1" <<'RC'
# a line that was here before bionic
export EDITOR=vim
alias ll='ls -la'
RC
}

# THE STALE-BLOCK FIXTURE. bionic's markers around an OLDER payload's proxy
# text, with non-bionic lines above AND below the block. Every install already
# on disk takes this shape the day `rc_default claude-proxy`'s text changes. The
# line is one bionic really wrote (env.sh `rc_earlier`): since wave-27 T77 a block
# holding a line bionic never wrote is the user's, changed, and left as it is.
STALE_LINE='claude() { command claude --dangerously-skip-permissions "$@"; }'
plant_stale_rc() {  # <file>
  {
    printf '%s\n' '# a line that was here before bionic'
    printf '%s\n' 'export EDITOR=vim'
    printf '%s\n' "$RC_START_LIT"
    printf '%s\n' "$STALE_LINE"
    printf '%s\n' "$RC_END_LIT"
    printf '%s\n' "alias ll='ls -la'"
    printf '%s\n' 'export PAGER=less'
  } > "$1"
}

# FRESH MEANS FRESH, AND A COUNTER COULD NOT DELIVER IT. Every call site is
# `SB="$(new_sandbox)"`, which runs this function in a COMMAND SUBSTITUTION —
# its own subshell — so a `SANDBOX_N=$((SANDBOX_N + 1))` here incremented a
# variable that died with the subshell and every sandbox in the suite was the
# same directory, re-planted in place. Arms that write and read in immediate
# succession never noticed; an arm that needs two fixtures alive AT ONCE (the
# agreement section below holds three) got one directory wearing three names.
# `mktemp -d` keeps no state to lose (epic-19 W1 S9).
new_sandbox() {  # -> prints a fresh $HOME with a planted .zshrc
  local sb
  sb="$(mktemp -d "$TMP/home-XXXXXX")"
  mkdir -p "$sb/.claude"
  plant_rc "$sb/.zshrc"
  printf '%s' "$sb"
}

new_stale_sandbox() {  # -> a fresh $HOME whose .zshrc already holds a stale block
  local sb
  sb="$(new_sandbox)"
  plant_stale_rc "$sb/.zshrc"
  printf '%s' "$sb"
}

# ---------------------------------------------------------------------------
# Extractors — every assertion below reads through one of these
# ---------------------------------------------------------------------------

# The lines BETWEEN bionic's markers, in order. Not "does the file contain the
# proxy line": a proxy line outside the markers is a line bionic does not own
# and this extractor must not see it.
rc_block_lines() {  # <file>
  local file="$1" line inside=0 out=""
  [ -f "$file" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$line" = "$RC_START_LIT" ]; then inside=1; continue; fi
    if [ "$line" = "$RC_END_LIT" ];   then inside=0; continue; fi
    [ "$inside" = "1" ] && out="${out}${line}"$'\n'
  done < "$file"
  printf '%s' "$out"
}

# Every line NOT between bionic's markers, in order, the markers themselves
# excluded. The other half of `rc_block_lines`: what the user's rc held before
# bionic ever touched it, and must still hold afterwards whatever bionic did to
# its own block.
rc_nonblock_lines() {  # <file>
  local file="$1" line inside=0 out=""
  [ -f "$file" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$line" = "$RC_START_LIT" ]; then inside=1; continue; fi
    if [ "$line" = "$RC_END_LIT" ];   then inside=0; continue; fi
    [ "$inside" = "0" ] && out="${out}${line}"$'\n'
  done < "$file"
  printf '%s' "$out"
}

# Does the SHELL agree the file is a shell script -- `ok`, or the parser's own
# complaint. An rc that no longer parses is the failure mode that locks a user
# out of their own login shell, and no assertion about bytes or blocks sees it.
zsh_syntax_rc() {  # <file>
  local out
  if out="$(zsh -n "$1" 2>&1)"; then printf 'ok'; else printf '%s' "${out:-nonzero}"; fi
}

# How many times a whole line equals <literal>. The idempotence arm reads this.
count_lines_equal() {  # <file> <literal>
  local file="$1" want="$2" line n=0
  [ -f "$file" ] || { printf '0'; return 0; }
  while IFS= read -r line || [ -n "$line" ]; do
    [ "$line" = "$want" ] && n=$((n + 1))
  done < "$file"
  printf '%s' "$n"
}

# A single-quoted shell constant's contents, read out of a script. Pure bash —
# the values are box-drawing glyphs and this must not go through awk or sed.
const_from() {  # <file> <name>
  local file="$1" name="$2" line v
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      "${name}='"*)
        v="${line#${name}=\'}"; v="${v%\'}"
        printf '%s' "$v"; return 0 ;;
    esac
  done < "$file"
  return 1
}

# The one line of a report that names the proxy row.
report_row() {  # <report text> <label>
  local line
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in *"$2"*) printf '%s' "$line"; return 0 ;; esac
  done <<< "$1"
  return 0
}

# What the SHELL says the name resolves to, from that HOME's own rc. This is the
# arm no file assertion can stand in for: a block written into a file the shell
# never reads is a block that changed nothing.
type_claude() {  # <sandbox>
  HOME="$1" ZDOTDIR="$1" SHELL=/bin/zsh PATH="$TMP/bin:$PATH" \
    zsh -ic 'type claude' 2>&1
}

# ---------------------------------------------------------------------------
# Drivers
# ---------------------------------------------------------------------------

setup_run() {  # <sandbox> <answer>
  local sb="$1" answer="$2"
  printf '%s\n' "$answer" | HOME="$sb" ZDOTDIR="$sb" SHELL=/bin/zsh \
    PATH="$TMP/bin:$PATH" BIONIC_CLAUDE_HOME="$sb/.claude" \
    bash "$SETUP_SH" --only claude-proxy 2>&1
}

doctor_run() {  # <sandbox>
  HOME="$1" ZDOTDIR="$1" SHELL=/bin/zsh \
    PATH="$TMP/bin:$PATH" BIONIC_CLAUDE_HOME="$1/.claude" \
    BIONIC_DOCTOR_PROBE_SECONDS=15 \
    bash "$DOCTOR_SH" </dev/null 2>&1
}

remove_run() {  # <sandbox> <answer> [script]
  local sb="$1" answer="$2" script="${3:-$REMOVE_SH}"
  printf '%s\n' "$answer" | HOME="$sb" ZDOTDIR="$sb" SHELL=/bin/zsh \
    PATH="$TMP/bin:$PATH" BIONIC_CLAUDE_HOME="$sb/.claude" \
    bash "$script" --only claude-proxy 2>&1
}

# One env.sh call in a fresh bash, against a fixture HOME.
env_run() {  # <sandbox> <shell-path> -- <function> [args...]
  local sb="$1" shell_path="$2"; shift 2
  [ "${1:-}" = "--" ] && shift
  HOME="$sb" SHELL="$shell_path" PATH="$TMP/bin:$PATH" \
    BIONIC_CLAUDE_HOME="$sb/.claude" \
    bash -c '
      set -uo pipefail
      . "$1" || exit 90
      shift
      "$@"
    ' _ "$ENV_SH" "$@"
}

# The same, for a snippet that has to READ a variable env.sh defines rather than
# call a function it defines.
env_eval() {  # <sandbox> <shell-path> <snippet>
  HOME="$1" SHELL="$2" PATH="$TMP/bin:$PATH" BIONIC_CLAUDE_HOME="$1/.claude" \
    bash -c '
      set -uo pipefail
      . "$1" || exit 90
      eval "$2"
    ' _ "$ENV_SH" "$3"
}


# ---------------------------------------------------------------------------
# From §detect:
# ---------------------------------------------------------------------------
detect_run() {  # <sandbox>
  HOME="$1" SHELL=/bin/zsh PATH="$TMP/bin:$PATH" BIONIC_CLAUDE_HOME="$1/.claude" \
    bash -c '. "$1" && detect_rc_claude_proxy' _ "$DETECT_SH" 2>&1
}

# ---------------------------------------------------------------------------
# From §remove: the standalone door:
# ---------------------------------------------------------------------------
mkdir -p "$TMP/standalone"
cp "$REMOVE_SH" "$TMP/standalone/remove.sh"

# ---------------------------------------------------------------------------
# From §T40:
# ---------------------------------------------------------------------------
t40_env() {  # <sandbox> <snippet> — env.sh sourced against the sandbox, then <snippet>
  HOME="$1" ZDOTDIR="$1" SHELL=/bin/zsh PATH="$TMP/bin:$PATH" \
    CLAUDE_CONFIG_DIR="$1/.claude" BIONIC_CLAUDE_HOME="$1/.claude" \
    bash -c '. "$1" || exit 90; eval "$2"' _ "$ENV_SH" "$2" 2>&1
}

# ---------------------------------------------------------------------------
# From §T46:
# ---------------------------------------------------------------------------
ALIAS_START="$(const_from "$REMOVE_SH" RM_ALIAS_START)"; ALIAS_END="$(const_from "$REMOVE_SH" RM_ALIAS_END)"
ENVB_START="$(const_from "$REMOVE_SH" RM_ENV_START)";    ENVB_END="$(const_from "$REMOVE_SH" RM_ENV_END)"

# ---------------------------------------------------------------------------
# From §T51:
# ---------------------------------------------------------------------------
T51_PATH="$TMP/bin:/usr/bin:/bin"
command -v jq >/dev/null 2>&1 && T51_PATH="${T51_PATH}:$(dirname "$(command -v jq)")"

# ---------------------------------------------------------------------------
# From §T51:
# ---------------------------------------------------------------------------
# A PAGE ITEM OF ITS OWN (wave-27 T82). Each `--all` sandbox here carries the pre-plugin
# skill copy `legacy-skill-copy` offers, so the page prints and the items run under its
# consent as these rows mean them. The page used to be filled by the claude stub, whose exit 0
# made every MCP tool row read present; tool rows are never on the page now.
t51_page_item() { mkdir -p "$1/.claude/skills/canonical-sdlc"; printf -- '---\nname: canonical-sdlc\n---\n' > "$1/.claude/skills/canonical-sdlc/SKILL.md"; }

# ---------------------------------------------------------------------------
# From §T55:
# ---------------------------------------------------------------------------
T55_EXACT="alias claude='claude --dangerously-skip-permissions'"

# ---------------------------------------------------------------------------
# From §T55:
# ---------------------------------------------------------------------------
fn_text() {  # <file> <name> — the function's lines, `name() {` through the first `}` alone
  local line inside=0 defs=0 text=""
  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$inside" = "0" ]; then case "$line" in "$2() {"*) inside=1; defs=$((defs + 1)) ;; *) continue ;; esac; fi
    [ "$defs" = "1" ] && text="${text}${line}"$'\n'
    [ "$line" = "}" ] && inside=0
  done < "$1"
  if [ "$defs" -gt 1 ]; then printf 'fn_text: %s is defined %s times in %s\n' "$2" "$defs" "$1"; return 0; fi
  printf '%s' "$text"
  return 0
}

# ---------------------------------------------------------------------------
# From §T66:
# ---------------------------------------------------------------------------
T66_ALIAS="$T55_EXACT"
T66_TODO='export CLAUDE_CODE_ENABLE_TODO_TOOLS=1'
T66_SHELL=/bin/bash
T66_PATH="$T51_PATH"
t66_env() {  # <sandbox> <command...> — t51_env with this section's SHELL and PATH
  local sb="$1"; shift
  mkdir -p "$sb/.tmp"
  env -i HOME="$sb" ZDOTDIR="$sb" CLAUDE_CONFIG_DIR="$sb/.claude" BIONIC_CLAUDE_HOME="$sb/.claude" \
    SHELL="$T66_SHELL" PATH="$T66_PATH" TMPDIR="$sb/.tmp" TERM=dumb BIONIC_DOCTOR_PROBE_SECONDS=15 "$@"
}
t66_rc() { case "$T66_SHELL" in */zsh) printf '%s' "$1/.zshrc" ;; *) printf '%s' "$1/.bashrc" ;; esac; }

# ---------------------------------------------------------------------------
# From §T66:
# ---------------------------------------------------------------------------
t66_door() {  # <sandbox> <door> <answer> [item]
  local item="${4:-legacy-alias}"
  case "$2" in
    setup-only)    printf '%s\n' "$3" | t66_env "$1" bash "$SETUP_SH" --only "$item" 2>&1 ;;
    setup-all)     printf '%s\n' "$3" | t66_env "$1" bash "$SETUP_SH" --all 2>&1 ;;
    rm-payload)    printf '%s\n' "$3" | t66_env "$1" bash "$REMOVE_SH" --only "$item" 2>&1 ;;
    rm-standalone) printf '%s\n' "$3" | t66_env "$1" bash "$TMP/standalone/remove.sh" --only "$item" 2>&1 ;;
    rm-all)        printf '%s\n' "$3" | t66_env "$1" bash "$REMOVE_SH" --all 2>&1 ;;
    doctor)        t66_env "$1" bash "$DOCTOR_SH" </dev/null 2>&1 ;;
  esac
}

# ---------------------------------------------------------------------------
# From §T66:
# ---------------------------------------------------------------------------
t66_pageblock() { printf '%s\n' "$RC_START_LIT" "$PROXY_UNALIAS" "$PROXY_LINE" "$RC_END_LIT"; }
