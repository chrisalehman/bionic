#!/bin/bash
# PAYLOAD BOUNDARY — the hermetic half of epic-17 wave-01 slice S6.
#
# Governing evidence: .bionic/docs/record/epic-17-w1/s4-report.md finding F4 — "there is no
# payload boundary, the whole working tree ships": a directory-source install of this repo
# copied 1467 files / 153 MB, including `.bionic/` (machine-local operational records — a
# privacy leak in a public artifact), the 134 MB excalidraw venv, `tests/`, and
# `claude-bootstrap.sh`.
#
# WHY A `payload/` SUBTREE AND NOT AN EXCLUDE LIST. Measured against the 2.1.233 CLI
# (see s6-report.md "Probe results"):
#   (a) a marketplace entry's `source` MAY point at a subdirectory — `./payload` — and the
#       installer then copies ONLY that subtree;
#   (b) plugin.json component-path fields MAY NOT reach outside the plugin root — the
#       validator rejects `../hooks` as `Path contains ".." which could be a path traversal
#       attempt`, and the install fails outright;
#   (c) symlinks inside the payload ARE dereferenced-and-copied at install time, so the
#       payload can be a thin set of links onto the repo's single owners;
#   (d) no ignore/exclude mechanism exists at all — no `.claudeignore`, no `files` field.
#
# (b) is why the payload is a directory of SYMLINKS rather than a directory of path
# redirections, and (c) is why that works. The repo keeps ONE copy of every payload file —
# `hooks/`, `agents/`, `skills/<name>/` stay exactly where tests/run.sh exercises them, and
# `payload/` never holds a second copy that could drift. This suite is the wall that keeps
# it that way: a real file appearing under payload/ (other than the manifest) is a
# second-owner defect and fails here.
#
# RATIFIED PAYLOAD (epic-17 W1): .claude-plugin/plugin.json, LICENSE, hooks/ (scripts +
# hooks.json), agents/, and the bionic-authored skills EXCLUDING excalidraw-diagram, which
# is a vendored fork of coleam00/excalidraw-diagram-skill (repo-inventory.md §3) and carries
# a uv project + .venv. `scripts/` joins in a later wave.
#
# TRAVERSAL TRAP — `grep -r`/`-R` over payload/ is a FALSE-NEGATIVE ABSENCE MACHINE. payload/
# is a tree of top-level symlinks (see §C above); `grep -r`/`-R` does not descend a symlinked
# directory, so `grep -Rl '<pattern>' payload/` silently reports zero hits even when the
# pattern is present throughout the dereferenced tree (review-6axis.md F3: measured 0 vs the
# true 28 for `.bionic/` alone). Any absence claim about payload/ content — here or in a
# future audit — must use `find -L payload ...` (as this suite does throughout) or
# `/usr/bin/grep` with explicit dereference, never a bare recursive grep.
#
# Usage: bash tests/plugin-payload.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"

REPO="${BIONIC_SCRIPTS_DIR}"
PAYLOAD="${REPO}/payload"
MARKETPLACE_JSON="${REPO}/.claude-plugin/marketplace.json"

# The size ceiling the installed tree must respect. S4 measured 153 MB with no boundary;
# the ratified payload materialises to single-digit MB. 5 MB is a wall with real headroom
# over today's measurement, not a fitted constant — it is small enough that re-admitting
# `tests/`, `.bionic/` or the excalidraw venv breaks it immediately.
MAX_PAYLOAD_KB=5120

# Ratified payload skills, and the one bionic-authored skill deliberately held back.
RATIFIED_SKILLS="browser-verify canonical-sdlc map-instrument-narrow"
EXCLUDED_SKILL="excalidraw-diagram"

PASS=0
FAIL=0

ok() { echo "PASS: $1"; PASS=$((PASS + 1)); }
no() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

check() { if [ "$1" = 0 ]; then ok "$2"; else no "$2"; fi; }

# ============================================================
echo ""
echo "=== A — the marketplace entry points at the payload subtree, not the repo root ==="
# ============================================================
#
# This is the whole mechanism in one field. With `source: "./"` the installer copies the
# working tree; with `source: "./payload"` it copies the payload subtree and nothing else.

if [ ! -f "$MARKETPLACE_JSON" ]; then
  no "marketplace.json exists"
else
  SRC="$(python3 -c "
import json
d = json.load(open('$MARKETPLACE_JSON'))
for p in d.get('plugins', []):
    if p.get('name') == 'bionic':
        s = p.get('source', '')
        print(s if isinstance(s, str) else s.get('source', ''))
        break
" 2>/dev/null)"
  if [ "$SRC" = "./payload" ]; then
    ok "marketplace.json bionic entry sources ./payload"
  else
    no "marketplace.json bionic entry sources ./payload (actual='$SRC')"
  fi
fi

# ============================================================
echo ""
echo "=== B — single owner: the plugin manifest lives in the payload, and only there ==="
# ============================================================
#
# The plugin root is the directory containing .claude-plugin/plugin.json. If one also sits
# at the repo root, the repo root is itself installable as a plugin and the boundary is
# bypassable by anyone who points --plugin-dir or a source at it. Exactly one must exist.

[ -f "${PAYLOAD}/.claude-plugin/plugin.json" ]
check $? "payload/.claude-plugin/plugin.json exists"

if [ -e "${REPO}/.claude-plugin/plugin.json" ]; then
  no "no second plugin.json at the repo root (found ${REPO}/.claude-plugin/plugin.json)"
else
  ok "no second plugin.json at the repo root"
fi

# ============================================================
echo ""
echo "=== C — one owner per file: link to the repo's owner, or BE the owner ==="
# ============================================================
#
# The invariant this section defends is SINGLE OWNERSHIP, not symlink-ness. A second copy
# of something the repo already owns drifts, so anything the repo owns — hooks/, agents/,
# skills/, LICENSE — appears here only as a link back to that owner.
#
# THE PAYLOAD-NATIVE DIRECTORIES are the other way to satisfy the same invariant: the
# payload IS the owner. These files have no repo-root twin to drift from — the whole point
# of the wave-03 command surface is that installation logic lives in the payload and nowhere
# else (wave-03 spec §Design, component boundaries), and claude-bootstrap.sh, the last
# root-level installer, retires at W5.
#
#   scripts/      the four commands and the libraries behind them (W3 S1)
#   permissions/  the permission-profile template (W3 S5, spec AC-6)
#   commands/     the shipped slash-command files (W3 S9)
#
# Carving them out of the link check is not a hole in the invariant: each is closed by the
# SAME pair of guards — no symlinks inside it, so it cannot point at a second owner, and no
# repo-root twin beside it, so ownership cannot become ambiguous later. That pair is written
# once below and applied to the list, and the list is what the `find` exclusions are built
# from, so a fourth payload-native directory is one entry here rather than a paste plus an
# exclusion someone forgets.
#
# AMENDED epic-17 W3 S1. Before that, the check read "everything except the plugin manifest
# must be a symlink", which was true only because every payload file then had a repo-root
# owner.

PAYLOAD_NATIVE_DIRS="scripts permissions commands"

if [ ! -d "$PAYLOAD" ]; then
  no "payload/ exists"
else
  ok "payload/ exists"

  # The exclusions and the guards below are built from ONE list, so they cannot fall out of
  # step with each other.
  FIND_EXCLUSIONS=(! -path "${PAYLOAD}/.claude-plugin/*")
  for native in $PAYLOAD_NATIVE_DIRS; do
    FIND_EXCLUSIONS+=(! -path "${PAYLOAD}/${native}/*")
  done

  STRAY="$(find "$PAYLOAD" -type f "${FIND_EXCLUSIONS[@]}" 2>/dev/null | sed "s|${REPO}/||" | sort)"
  if [ -z "$STRAY" ]; then
    ok "payload/ holds no copy of anything the repo owns (outside .claude-plugin/ and the payload-native dirs)"
  else
    no "payload/ holds no copy of anything the repo owns (found: $(echo "$STRAY" | tr '\n' ' '))"
  fi

  # The carve-out's two guards, once, for every payload-native directory.
  #
  # First: it must own its files outright — a symlink in there would point at a second owner
  # and reopen exactly the drift this section exists to prevent. Second: no root-level twin;
  # if one ever appears, ownership is ambiguous again and the carve-out is no longer safe.
  for native in $PAYLOAD_NATIVE_DIRS; do
    if [ -d "${PAYLOAD}/${native}" ]; then
      NATIVE_LINKS="$(find "${PAYLOAD}/${native}" -type l 2>/dev/null | sed "s|${REPO}/||" | sort)"
      if [ -z "$NATIVE_LINKS" ]; then
        ok "payload/${native}/ contains no symlinks (the payload owns these files outright)"
      else
        no "payload/${native}/ contains no symlinks (found: $(echo "$NATIVE_LINKS" | tr '\n' ' '))"
      fi
    fi
    if [ -e "${REPO}/${native}" ]; then
      no "no repo-root ${native}/ twin beside payload/${native}/ (found ${REPO}/${native})"
    else
      ok "no repo-root ${native}/ twin beside payload/${native}/"
    fi
  done

  # Each link must resolve, and must resolve to the repo's single owner.
  for pair in "hooks:hooks" "agents:agents"; do
    link="${pair%%:*}"; target="${pair##*:}"
    if [ ! -L "${PAYLOAD}/${link}" ]; then
      no "payload/${link} is a symlink"
    elif [ "$(cd "$(dirname "${PAYLOAD}/${link}")" && cd "$(readlink "${PAYLOAD}/${link}")" && pwd)" = "${REPO}/${target}" ]; then
      ok "payload/${link} -> ${target}/ (repo single owner)"
    else
      no "payload/${link} -> ${target}/ (resolved elsewhere: $(readlink "${PAYLOAD}/${link}"))"
    fi
  done

  if [ -L "${PAYLOAD}/LICENSE" ] && [ "$(cd "$PAYLOAD" && cd "$(dirname "$(readlink LICENSE)")" && pwd)/$(basename "$(readlink "${PAYLOAD}/LICENSE")")" = "${REPO}/LICENSE" ]; then
    ok "payload/LICENSE -> LICENSE (repo single owner)"
  else
    no "payload/LICENSE -> LICENSE (repo single owner)"
  fi
fi

# ============================================================
echo ""
echo "=== D — exactly the ratified skills, and excalidraw-diagram is NOT among them ==="
# ============================================================

if [ ! -d "${PAYLOAD}/skills" ]; then
  no "payload/skills/ exists"
else
  ok "payload/skills/ exists"

  ACTUAL="$(cd "${PAYLOAD}/skills" && ls -1 2>/dev/null | sort | tr '\n' ' ' | sed 's/ $//')"
  EXPECTED="$(echo "$RATIFIED_SKILLS" | tr ' ' '\n' | sort | tr '\n' ' ' | sed 's/ $//')"
  if [ "$ACTUAL" = "$EXPECTED" ]; then
    ok "payload/skills/ is exactly the ratified set: $EXPECTED"
  else
    no "payload/skills/ is exactly the ratified set (expected='$EXPECTED' actual='$ACTUAL')"
  fi

  for s in $RATIFIED_SKILLS; do
    if [ ! -L "${PAYLOAD}/skills/${s}" ]; then
      no "payload/skills/${s} is a symlink"
    elif [ "$(cd "${PAYLOAD}/skills" && cd "$(readlink "$s")" && pwd)" = "${BIONIC_SKILLS_DIR}/${s}" ]; then
      ok "payload/skills/${s} -> skills/${s}/ (repo single owner)"
    else
      no "payload/skills/${s} -> skills/${s}/ (resolved elsewhere: $(readlink "${PAYLOAD}/skills/${s}"))"
    fi
    [ -f "${PAYLOAD}/skills/${s}/SKILL.md" ]
    check $? "payload/skills/${s}/SKILL.md is reachable through the link"
  done

  if [ -e "${PAYLOAD}/skills/${EXCLUDED_SKILL}" ]; then
    no "${EXCLUDED_SKILL} is held out of the payload (vendored fork + uv .venv)"
  else
    ok "${EXCLUDED_SKILL} is held out of the payload (vendored fork + uv .venv)"
  fi

  # The holdout is a payload decision, not a deletion: the skill still lives in the repo.
  [ -f "${BIONIC_SKILLS_DIR}/${EXCLUDED_SKILL}/SKILL.md" ]
  check $? "${EXCLUDED_SKILL} still exists in the repo (held out, not removed)"
fi

# ============================================================
echo ""
echo "=== E — nothing outside the boundary is reachable through the payload ==="
# ============================================================
#
# The hermetic mirror of the install-time assertion in
# .bionic/tests/epic17-payload-boundary.sh. `find -L` walks the dereferenced tree, which is
# exactly the shape the installer copies.

if [ -d "$PAYLOAD" ]; then
  for bad in .bionic .claude .git tests claude-bootstrap.sh claude-reset.sh \
             ccstatusline design architecture.png node_modules .venv .DS_Store; do
    HITS="$(find -L "$PAYLOAD" -name "$bad" 2>/dev/null | head -5)"
    if [ -z "$HITS" ]; then
      ok "payload tree contains no '$bad'"
    else
      no "payload tree contains no '$bad' (found: $(echo "$HITS" | tr '\n' ' '))"
    fi
  done

  # Dereferenced size — what the installer will actually copy.
  PAYLOAD_KB="$(du -skL "$PAYLOAD" 2>/dev/null | awk '{print $1}')"
  if [ -n "$PAYLOAD_KB" ] && [ "$PAYLOAD_KB" -lt "$MAX_PAYLOAD_KB" ]; then
    ok "dereferenced payload is under ${MAX_PAYLOAD_KB} KB (measured ${PAYLOAD_KB} KB)"
  else
    no "dereferenced payload is under ${MAX_PAYLOAD_KB} KB (measured ${PAYLOAD_KB:-unknown} KB)"
  fi
fi

# ============================================================
echo ""
echo "=== F — the payload is committed, so a clone reproduces it ==="
# ============================================================
#
# The links are the mechanism. If git does not carry them, a fresh clone installs an empty
# plugin — and .gitignore in this repo excludes several paths by decision, so this is not a
# theoretical worry.

if git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1; then
  TRACKED="$(git -C "$REPO" ls-files payload | wc -l | tr -d ' ')"
  if [ "$TRACKED" -ge 7 ]; then
    ok "payload/ is tracked by git ($TRACKED entries)"
  else
    no "payload/ is tracked by git (only $TRACKED entries tracked)"
  fi

  IGNORED="$(git -C "$REPO" check-ignore payload 2>/dev/null)"
  if [ -z "$IGNORED" ]; then
    ok "payload/ is not gitignored"
  else
    no "payload/ is not gitignored (matched: $IGNORED)"
  fi
else
  echo "SKIP: git checks (not a git checkout)"
fi

# ============================================================
echo ""
echo "========================================"
echo "Results: $PASS passed, $FAIL failed"
echo "========================================"

[ "$FAIL" -gt 0 ] && exit 1
exit 0
