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
# hooks.json), agents/, and the bionic-authored skills. `scripts/` joins in a later wave.
#
# EXCALIDRAW-DIAGRAM JOINED AT EPIC-18 T3 (AC-6), and it is the first PAYLOAD-NATIVE SKILL:
# the payload owns the directory outright, with no repo-root twin. W1 held it out because it
# is a vendored fork carrying a uv project, and a `uv sync` in that project writes a 134 MB
# `.venv` beside it — which through a link would have arrived here as the payload's own size.
# That risk did not move with the directory, it changed OWNER: the venv now belongs in the
# INSTALLED plugin's copy (`${CLAUDE_PLUGIN_ROOT}/skills/excalidraw-diagram/references`),
# armed on consent the first time a render needs it, and §E's `.venv` name check plus the
# size ceiling are what fail loudly if one is ever synced into this repo instead.
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

# The size ceiling the installed tree must respect. S4 measured 153 MB with no boundary; the
# first wall was 5 MB, chosen when the payload still carried 2.5 MB of diagram PNGs and the
# hook test suites. Both are gone (epic-17 W4: S9 moved hooks/*.test.sh under tests/, S8
# retired the PNG + .excalidraw pair for composed SVG), and the tree now measures 976 KB —
# so a 5 MB wall had stopped discriminating: the payload could quintuple without tripping it.
#
# RE-FIT ONCE, to 1.5 MB (spec AC-9's ratified ceiling, so the wall and the criterion are one
# number rather than two constants free to disagree). That left ~57% headroom over the 976 KB
# measured then; epic-18 T3 moved the excalidraw skill in and the tree now measures 1328 KB,
# so the headroom is ~16% — still loose enough that ordinary doc and script growth never trips
# it, and the ceiling stays where AC-9 ratified it rather than moving to fit the payload; tight enough
# that every failure mode this arm exists for still breaks it on contact: the retired PNG pair
# alone was 2.5 MB, `tests/` is over 1 MB, and the excalidraw venv is 134 MB. The comparison is
# `-le`, so the ceiling is inclusive, matching the "≤ 1.5M" the criterion states.
MAX_PAYLOAD_KB=1536

# Ratified payload skills, in the two shapes single ownership permits: LINKED, where the
# repo root owns the directory and payload/skills/ points at it, and NATIVE, where the
# payload owns it outright and no repo-root twin exists. §D asserts the roster is exactly
# their union, and each shape carries its own guards.
LINKED_SKILLS="browser-verify canonical-sdlc map-instrument-narrow"
NATIVE_SKILLS="excalidraw-diagram"

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
#   ccstatusline/ the ccstatusline widget-layout settings.json (W4 S11, spec AC-11 — moved
#                 from a repo-root ccstatusline/ dir that had no other consumer)
#   integrity/    the checksum manifest of the rendered agent files (W4 S5, spec AC-4).
#                 Payload-native although its SUBJECT is repo-owned: the manifest is a fact
#                 about what THIS payload ships, so it belongs beside the shipment. §H is
#                 the arm that keeps it honest.
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

# AMENDED epic-18 T3. A payload-native SKILL is the same carve-out one level down —
# `payload/skills/<name>/` rather than `payload/<name>/` — so it gets its own list and the
# same guard pair below, with the twin check pointed at `skills/<name>` because that is
# where a second owner for a skill would appear. It is a second list rather than a second
# spelling inside the first because the exclusion path and the twin path both differ, and
# folding them would mean a conditional in three places instead of a name in one.
PAYLOAD_NATIVE_DIRS="scripts permissions commands ccstatusline integrity"
PAYLOAD_NATIVE_SKILL_DIRS="$NATIVE_SKILLS"

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
  for native in $PAYLOAD_NATIVE_SKILL_DIRS; do
    FIND_EXCLUSIONS+=(! -path "${PAYLOAD}/skills/${native}/*")
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

  # The same pair for a payload-native SKILL, one level down.
  for native in $PAYLOAD_NATIVE_SKILL_DIRS; do
    if [ -d "${PAYLOAD}/skills/${native}" ]; then
      NATIVE_LINKS="$(find "${PAYLOAD}/skills/${native}" -type l 2>/dev/null | sed "s|${REPO}/||" | sort)"
      if [ -z "$NATIVE_LINKS" ]; then
        ok "payload/skills/${native}/ contains no symlinks (the payload owns these files outright)"
      else
        no "payload/skills/${native}/ contains no symlinks (found: $(echo "$NATIVE_LINKS" | tr '\n' ' '))"
      fi
    fi
    if [ -e "${BIONIC_SKILLS_DIR}/${native}" ]; then
      no "no repo-root skills/${native}/ twin beside payload/skills/${native}/ (found ${BIONIC_SKILLS_DIR}/${native})"
    else
      ok "no repo-root skills/${native}/ twin beside payload/skills/${native}/"
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
echo "=== D — exactly the ratified skills, linked ones linked and native ones owned ==="
# ============================================================

if [ ! -d "${PAYLOAD}/skills" ]; then
  no "payload/skills/ exists"
else
  ok "payload/skills/ exists"

  ACTUAL="$(cd "${PAYLOAD}/skills" && ls -1 2>/dev/null | sort | tr '\n' ' ' | sed 's/ $//')"
  EXPECTED="$(echo "$LINKED_SKILLS $NATIVE_SKILLS" | tr ' ' '\n' | grep -v '^$' | sort | tr '\n' ' ' | sed 's/ $//')"
  if [ "$ACTUAL" = "$EXPECTED" ]; then
    ok "payload/skills/ is exactly the ratified set: $EXPECTED"
  else
    no "payload/skills/ is exactly the ratified set (expected='$EXPECTED' actual='$ACTUAL')"
  fi

  for s in $LINKED_SKILLS; do
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

  # THE NATIVE HALF (epic-18 T3, AC-6). A directory, not a link — the payload IS the owner,
  # which is what makes the skill arrive on a plugin-installed machine at all. The link check
  # above would pass on a native skill by failing it, so the shape is asserted directly here:
  # a real directory whose SKILL.md is a real file, with §C's guard pair standing behind it.
  for s in $NATIVE_SKILLS; do
    if [ -L "${PAYLOAD}/skills/${s}" ]; then
      no "payload/skills/${s} is a real directory, not a symlink (the payload owns it)"
    elif [ -d "${PAYLOAD}/skills/${s}" ]; then
      ok "payload/skills/${s} is a real directory, not a symlink (the payload owns it)"
    else
      no "payload/skills/${s} is a real directory, not a symlink (nothing at that path)"
    fi
    if [ -f "${PAYLOAD}/skills/${s}/SKILL.md" ] && [ ! -L "${PAYLOAD}/skills/${s}/SKILL.md" ]; then
      ok "payload/skills/${s}/SKILL.md is a real file the payload ships"
    else
      no "payload/skills/${s}/SKILL.md is a real file the payload ships"
    fi
  done
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
             design node_modules .venv .DS_Store \
             agents-src; do
    HITS="$(find -L "$PAYLOAD" -name "$bad" 2>/dev/null | head -5)"
    if [ -z "$HITS" ]; then
      ok "payload tree contains no '$bad'"
    else
      no "payload tree contains no '$bad' (found: $(echo "$HITS" | tr '\n' ' '))"
    fi
  done

  # Dereferenced size — what the installer will actually copy.
  PAYLOAD_KB="$(du -skL "$PAYLOAD" 2>/dev/null | awk '{print $1}')"
  if [ -n "$PAYLOAD_KB" ] && [ "$PAYLOAD_KB" -le "$MAX_PAYLOAD_KB" ]; then
    ok "dereferenced payload is within ${MAX_PAYLOAD_KB} KB (measured ${PAYLOAD_KB} KB)"
  else
    no "dereferenced payload is within ${MAX_PAYLOAD_KB} KB (measured ${PAYLOAD_KB:-unknown} KB)"
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
echo "=== G — the agent RENDER PIPELINE stays repo-side: finals ship, sources never do ==="
# ============================================================
#
# epic-17 W4 S2 / spec AC-2. agents/ is rendered from agents-src/ (blocks + templates +
# render.sh). The rendered finals are product — they ARE the agent role files the plugin
# installs. Everything upstream of them is build-time apparatus: shipping it would put a
# second, editable copy of every shared block on the user's machine, and the render script
# would happily overwrite their installed agents from it.
#
# The `agents-src` entry in §E's bad-name list catches the directory arriving whole. This
# section is the finer sieve: the ARTIFACT KINDS, wherever they land. `find -L` is
# mandatory here for the reason §E's preamble gives — payload/ is a symlink tree and a bare
# recursive grep reports zero for anything below one.

if [ -d "$PAYLOAD" ]; then
  # Templates and the render script, by shape rather than by parent directory.
  TMPL_HITS="$(find -L "$PAYLOAD" -name '*.tmpl' 2>/dev/null | head -5)"
  if [ -z "$TMPL_HITS" ]; then
    ok "payload tree ships no role-file templates (*.tmpl)"
  else
    no "payload tree ships no role-file templates (found: $(echo "$TMPL_HITS" | tr '\n' ' '))"
  fi

  RENDER_HITS="$(find -L "$PAYLOAD" -name 'render.sh' 2>/dev/null | head -5)"
  if [ -z "$RENDER_HITS" ]; then
    ok "payload tree ships no render.sh"
  else
    no "payload tree ships no render.sh (found: $(echo "$RENDER_HITS" | tr '\n' ' '))"
  fi

  # The block sources by content signature: a block file is what carries the shared duty
  # text without the role frontmatter around it. Name-matching alone would miss a rename,
  # so this asks whether any file under the payload is a naked block.
  BLOCK_HITS=""
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    head -1 "$f" 2>/dev/null | grep -q '^---$' && continue
    grep -qF "carries the command that proves it and that command's output" "$f" 2>/dev/null \
      && BLOCK_HITS="${BLOCK_HITS}${f} "
  done <<EOF
$(find -L "$PAYLOAD" -type f -name '*.md' 2>/dev/null)
EOF
  if [ -z "$BLOCK_HITS" ]; then
    ok "payload tree ships no naked block source (shared duty text outside a role file)"
  else
    no "payload tree ships no naked block source (found: $BLOCK_HITS)"
  fi

  # The positive half — the wall must not be satisfiable by shipping nothing. The rendered
  # finals ARE product and have to be reachable through the payload, generated header and
  # all, or the plugin installs an agent-less harness.
  RENDERED_OK=1
  for r in auditor critic implementor researcher senior-implementor test-runner; do
    if [ ! -f "${PAYLOAD}/agents/${r}.md" ]; then
      RENDERED_OK=0; break
    fi
    grep -qF "GENERATED FILE — DO NOT EDIT" "${PAYLOAD}/agents/${r}.md" 2>/dev/null || RENDERED_OK=0
  done
  if [ "$RENDERED_OK" = 1 ]; then
    ok "all six RENDERED finals are reachable through payload/agents/ and carry their generated header"
  else
    no "all six RENDERED finals are reachable through payload/agents/ and carry their generated header"
  fi
fi

# ============================================================
echo ""
echo "=== H — the rendered-agent checksum manifest SHIPS, and agrees with what ships beside it ==="
# ============================================================
#
# Spec AC-4. /bionic:doctor's integrity line is only as true as this file: a manifest that
# did not reach the user's machine makes the line permanently `unknown`, and a manifest that
# shipped STALE makes it permanently `modified` — a false accusation against a user who
# edited nothing. Both failures are silent on the user's side, which is why they are
# measured here, on the payload as committed.
#
# The digests are recomputed from the files THROUGH THE PAYLOAD LINK — the same dereferenced
# path the installer copies — rather than from agents/ directly, so this arm measures the
# shipment and not the repo.

MANIFEST="${PAYLOAD}/integrity/agents.sha256"

if [ ! -f "$MANIFEST" ]; then
  no "payload/integrity/agents.sha256 ships (the manifest doctor reads)"
else
  ok "payload/integrity/agents.sha256 ships (the manifest doctor reads)"

  # A real file, not a link: the payload owns this one outright (§C's carve-out), and a
  # symlink here would put its owner outside the boundary the installer copies.
  if [ -L "$MANIFEST" ]; then
    no "the manifest is a real file, not a symlink out of the payload"
  else
    ok "the manifest is a real file, not a symlink out of the payload"
  fi

  # Exactly the six rendered finals, addressed plugin-root-relative. A path that did not
  # start `agents/` would resolve nowhere on the installed machine.
  MANIFEST_PATHS="$(grep -v '^#' "$MANIFEST" | grep -v '^[[:space:]]*$' | awk '{print $2}' | sort | tr '\n' ' ' | sed 's/ $//')"
  EXPECT_PATHS="$(for r in auditor critic implementor researcher senior-implementor test-runner; do
                    echo "agents/${r}.md"; done | sort | tr '\n' ' ' | sed 's/ $//')"
  if [ "$MANIFEST_PATHS" = "$EXPECT_PATHS" ]; then
    ok "the manifest covers exactly the six rendered finals, plugin-root-relative"
  else
    no "the manifest covers exactly the six rendered finals, plugin-root-relative (got '$MANIFEST_PATHS')"
  fi

  # Freshness. Every digest is recomputed and compared; a stale row is named.
  STALE_ROWS=""
  while IFS= read -r row; do
    case "$row" in ''|'#'*) continue ;; esac
    want="$(echo "$row" | awk '{print $1}')"
    rel="$(echo "$row" | awk '{print $2}')"
    if [ ! -f "${PAYLOAD}/${rel}" ]; then
      STALE_ROWS="${STALE_ROWS}${rel}(missing) "
      continue
    fi
    got="$(shasum -a 256 "${PAYLOAD}/${rel}" | awk '{print $1}')"
    [ "$got" = "$want" ] || STALE_ROWS="${STALE_ROWS}${rel} "
  done < "$MANIFEST"
  if [ -z "$STALE_ROWS" ]; then
    ok "every manifest digest matches the file that ships beside it"
  else
    no "every manifest digest matches the file that ships beside it (stale: $STALE_ROWS) — re-run bash agents-src/render.sh"
  fi

  # The manifest is an OUTPUT of the render pipeline, and the pipeline is repo-side. This is
  # the one place that pairing is visible from the payload: the file names its writer, so a
  # user who finds a mismatch is told what regenerates it rather than left to guess.
  if grep -qF "agents-src/render.sh" "$MANIFEST"; then
    ok "the manifest names the script that regenerates it"
  else
    no "the manifest names the script that regenerates it"
  fi
fi

# ============================================================
echo ""
echo "========================================"
echo "Results: $PASS passed, $FAIL failed"
echo "========================================"

[ "$FAIL" -gt 0 ] && exit 1
exit 0
