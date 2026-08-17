#!/bin/bash
# profile.sh — the permission profile pipeline (epic-17 wave-03, spec AC-6).
#
# WHAT THIS FILE OWNS. Everything that happens to bionic's shipped permission
# profile between the payload and a machine: rendering the template against a
# concrete plugin root, applying the result into the user settings layer,
# diffing what is applied against what ships, stripping it back out, and
# reporting the resulting state as one fact line. The template itself
# (`permissions/profile.template.json`) is the SSoT for the rules; nothing here
# authors a rule.
#
# WHY RENDERING AT ALL. The design's first choice was identity — ship rules
# carrying the literal `${CLAUDE_PLUGIN_ROOT}` text and let them match verbatim.
# Measurement refuted it: permission rules take literal paths and globs only, so
# a rule containing the variable text matches nothing a machine ever executes
# (record/epic-17-w3/probe-identity-match.md, ratified as D2-final). The concrete
# path is what the permission gate sees, so the concrete path is what gets
# written — which is also why the block goes stale on every plugin update, since
# the CLI's install path carries a version segment. doctor names that; setup is
# idempotent and cheap, and re-running it is the fix.
#
# THE MARKER BLOCK. The rules bionic owns are bracketed inside
# `permissions.allow` by two sentinel entries:
#
#     Bash(: bionic-profile-begin version=<v>)
#     ... bionic's rules ...
#     Bash(: bionic-profile-end)
#
# Settings files are strict JSON and cannot carry comments, and a foreign
# top-level key would be a key the CLI never reads. Sentinels shaped as rules
# solve both: they are valid rule syntax, they are EXACT-match (no `:*` suffix)
# so nothing can be appended to them, and the command they name is `:` — bash's
# no-op builtin. They authorize nothing. The begin sentinel carries the version,
# which is what lets a machine still holding an old block report the number it
# actually has rather than the number the payload currently ships.
#
# THE OUTPUT CONTRACT. detect.sh's conventions, so a caller parses these the
# same way it parses machine facts — one line, fixed shape, exit 0:
#
#   profile: applied=<yes|no> version=<v|none> stale=<yes|no|unknown> accretion=<n|unknown>
#   profile:diff verdict=<identical|stale|absent>
#   profile:diff accretion=<n|unknown>
#
# `unknown` appears where honesty requires it, exactly as it does in detect.sh:
# a machine without `jq` — itself a row in the dependency table — cannot have
# its settings parsed, and a confident `stale=no` there would report a stale
# machine as current. Presence and version survive that loss (they are read
# textually); comparison and counting do not.
#
# CONSENT IS THE CALLER'S. `profile_apply` is the only function that writes, and
# it refuses unless handed the consent token. It does not prompt: setup owns the
# conversation with the user, and a library that could ask would be a second
# place consent is decided. Passing the token is an assertion that the answer
# was obtained.
#
# ROOTS ARE OVERRIDABLE, read at CALL time:
#
#   BIONIC_PLUGIN_ROOT       the RENDER TARGET — where the plugin is installed
#   BIONIC_PROFILE_TEMPLATE  the template to read (default: beside this library)
#   BIONIC_SETTINGS_FILE     user settings.json
#   BIONIC_CLAUDE_HOME       the CLI's config dir
#
# The template and the render target are resolved separately on purpose. The
# template belongs to the tree this file lives in; the render target is wherever
# the machine put the plugin. In production they are the same directory, and the
# hermetic suite is the case where they are not.
#
# No `dirname`/`basename` calls anywhere below, same reason detect.sh gives: a
# library that cannot be SOURCED without coreutils dies on the half-uninstalled
# machine it exists to diagnose.
#
# Sourced, never executed:  . "${CLAUDE_PLUGIN_ROOT}/scripts/lib/profile.sh"

_profile_self_dir() {
  local self="${BASH_SOURCE[0]}"
  case "$self" in */*) echo "${self%/*}" ;; *) echo "." ;; esac
}

# The render target: where this machine keeps the plugin.
_profile_plugin_root() {
  if [ -n "${BIONIC_PLUGIN_ROOT:-}" ]; then echo "$BIONIC_PLUGIN_ROOT"; return; fi
  if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then echo "$CLAUDE_PLUGIN_ROOT"; return; fi
  # lib -> scripts -> payload root
  ( cd "$(_profile_self_dir)/../.." && pwd -P )
}

# The template: part of the tree this file ships in, never of the render target.
_profile_template_path() {
  if [ -n "${BIONIC_PROFILE_TEMPLATE:-}" ]; then echo "$BIONIC_PROFILE_TEMPLATE"; return; fi
  echo "$( cd "$(_profile_self_dir)/../.." && pwd -P )/permissions/profile.template.json"
}

_profile_settings_file() {
  echo "${BIONIC_SETTINGS_FILE:-${BIONIC_CLAUDE_HOME:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}}/settings.json}"
}

_profile_have_jq() { command -v jq >/dev/null 2>&1; }

# Whole-file read with no fork and no trailing-byte surprises: `read -d ''`
# consumes to EOF and keeps the final newline if there is one, which is what
# makes a byte-exact round trip possible.
#
# It assigns into a caller-named variable rather than echoing, and that is the
# whole point: `$(...)` strips trailing newlines, so a slurp that printed its
# result would destroy the very byte the round trip turns on.
_profile_slurp_into() {  # <varname> <file>
  local __profile_var="$1" __profile_file="$2" __profile_text
  [ -f "$__profile_file" ] || return 1
  IFS= read -r -d '' __profile_text < "$__profile_file" || true
  printf -v "$__profile_var" '%s' "$__profile_text"
}

_profile_ends_with_newline() {  # <file>
  local text
  _profile_slurp_into text "${1:-}" || return 1
  case "$text" in *$'\n') return 0 ;; *) return 1 ;; esac
}

# ─── The marker block ────────────────────────────────────────────────────────
#
# One definition of the sentinels, used by every function below and by the jq
# programs. Changing either string is a format change: it orphans every block
# already applied on a machine, which is why they are constants and not
# assembled from parts.

BIONIC_PROFILE_BEGIN_PREFIX='Bash(: bionic-profile-begin version='
BIONIC_PROFILE_END='Bash(: bionic-profile-end)'
BIONIC_PROFILE_CONSENT='--consented'

# Removes the marker block, inclusive, and collapses the containers it created.
# The collapse is what makes a machine that had no `permissions` key at all come
# back byte-exact: apply created `.permissions.allow`, so strip must unmake it.
# (The one case this cannot distinguish is a file that already carried an EMPTY
# allow array before bionic ever ran; such a file comes back semantically
# identical with the empty container removed.)
_PROFILE_STRIP_JQ='
  if (.permissions | type) != "object" then .
  elif (.permissions.allow | type) != "array" then .
  else
    .permissions.allow as $a
    | ($a | map(type == "string" and startswith("'"${BIONIC_PROFILE_BEGIN_PREFIX}"'")) | index(true)) as $b
    | ($a | map(. == "'"${BIONIC_PROFILE_END}"'") | index(true)) as $e
    | if $b == null or $e == null or $e < $b then .
      else .permissions.allow = ($a[0:$b] + $a[$e+1:]) end
  end
  | if (.permissions | type) == "object"
       and (.permissions.allow | type) == "array"
       and (.permissions.allow | length) == 0
    then del(.permissions.allow) else . end
  | if (.permissions | type) == "object" and (.permissions | length) == 0
    then del(.permissions) else . end
'

# The applied block itself, as a JSON array, or `null` when none is applied.
_PROFILE_BLOCK_JQ='
  if (.permissions | type) != "object" then null
  elif (.permissions.allow | type) != "array" then null
  else
    .permissions.allow as $a
    | ($a | map(type == "string" and startswith("'"${BIONIC_PROFILE_BEGIN_PREFIX}"'")) | index(true)) as $b
    | ($a | map(. == "'"${BIONIC_PROFILE_END}"'") | index(true)) as $e
    | if $b == null or $e == null or $e < $b then null else $a[$b:$e+1] end
  end
'

# ─── Render ──────────────────────────────────────────────────────────────────
#
# Pure text substitution, deliberately: no JSON round trip, so the output is the
# template byte for byte with one token replaced and nothing else touched. It
# needs no `jq`, which matters because rendering is the half of the pipeline a
# broken machine can still do.

render_profile() {  # <template-path> <plugin-root>
  local template="${1:-}" root="${2:-}" text
  if [ -z "$template" ] || [ ! -f "$template" ]; then
    echo "profile.sh: no such profile template: ${template}" >&2; return 1
  fi
  if [ -z "$root" ]; then
    echo "profile.sh: render_profile needs a plugin root" >&2; return 1
  fi
  # A relative root would produce rules resolved against whatever directory the
  # session happens to be in — a rule that means something different per repo.
  case "$root" in
    /*) ;;
    *) echo "profile.sh: plugin root must be an absolute path: ${root}" >&2; return 1 ;;
  esac
  root="${root%/}"
  _profile_slurp_into text "$template" || return 1
  printf '%s' "${text//__BIONIC_PLUGIN_ROOT__/$root}"
}

# ─── Apply ───────────────────────────────────────────────────────────────────

profile_apply() {  # <rendered-file> <consent-token>
  local rendered="${1:-}" consent="${2:-}" settings text block stripped merged nl=0

  # The gate, first and unconditionally. Everything below this line mutates.
  if [ "$consent" != "$BIONIC_PROFILE_CONSENT" ]; then
    echo "profile.sh: profile_apply requires explicit consent — pass ${BIONIC_PROFILE_CONSENT} once the user has agreed." >&2
    return 1
  fi
  if [ -z "$rendered" ] || [ ! -f "$rendered" ]; then
    echo "profile.sh: no such rendered profile: ${rendered}" >&2; return 1
  fi
  if ! _profile_have_jq; then
    echo "profile.sh: jq is required to edit a settings file safely — refusing to write." >&2; return 1
  fi

  _profile_slurp_into text "$rendered" || return 1
  # An unrendered profile would install rules that match nothing at all — a
  # profile that appears applied and grants nothing is worse than none.
  case "$text" in
    *__BIONIC_PLUGIN_ROOT__*)
      echo "profile.sh: refusing to apply an unrendered profile — run render_profile first." >&2
      return 1 ;;
  esac

  block="$(jq -c '.permissions.allow // []' "$rendered" 2>/dev/null)" || {
    echo "profile.sh: rendered profile is not valid JSON: ${rendered}" >&2; return 1; }
  if ! jq -e --arg b "$BIONIC_PROFILE_BEGIN_PREFIX" --arg e "$BIONIC_PROFILE_END" '
        (.permissions.allow // []) as $a
        | ($a | length) >= 2
          and ($a[0] | type == "string" and startswith($b))
          and ($a[-1] == $e)' "$rendered" >/dev/null 2>&1; then
    echo "profile.sh: rendered profile is not marker-bracketed — refusing to apply." >&2; return 1
  fi

  settings="$(_profile_settings_file)"
  if [ ! -f "$settings" ]; then
    case "$settings" in */*) mkdir -p "${settings%/*}" || return 1 ;; esac
    printf '%s' '{}' > "$settings" || return 1
  else
    _profile_ends_with_newline "$settings" && nl=1
  fi

  # Strip first, then append. That is what makes a second apply idempotent and a
  # re-render after a plugin update REPLACE the block rather than stack a second
  # one beside it.
  stripped="$(jq "$_PROFILE_STRIP_JQ" "$settings" 2>/dev/null)" || {
    echo "profile.sh: ${settings} is not valid JSON — refusing to write." >&2; return 1; }
  merged="$(printf '%s' "$stripped" | jq --argjson block "$block" '
      .permissions = ((.permissions // {}) | .allow = ((.allow // []) + $block))' 2>/dev/null)" || {
    echo "profile.sh: could not merge the profile into ${settings}." >&2; return 1; }

  _profile_write "$settings" "$merged" "$nl"
}

# Atomic write that preserves the file's trailing-newline shape. The CLI writes
# canonical JSON with NO trailing newline; a hand-edited file may have one.
# Reproducing whichever was there is half of what makes the round trip byte-exact.
_profile_write() {  # <file> <content> <trailing-newline 0|1>
  local file="$1" content="$2" nl="$3" tmp="${1}.bionic.tmp"
  if [ "$nl" = "1" ]; then printf '%s\n' "$content" > "$tmp"; else printf '%s' "$content" > "$tmp"; fi
  mv "$tmp" "$file"
}

# ─── Strip ───────────────────────────────────────────────────────────────────
#
# No consent gate here, by design: strip only ever removes what bionic itself
# put there, and remove.sh's own per-item consent is the conversation. A strip
# on a machine that never applied must be a genuine no-op — not a rewrite that
# happens to produce the same JSON — so it returns before touching the file.

profile_strip() {
  local settings text stripped nl=0
  settings="$(_profile_settings_file)"
  [ -f "$settings" ] || return 0

  _profile_slurp_into text "$settings" || return 0
  case "$text" in
    *"$BIONIC_PROFILE_BEGIN_PREFIX"*) ;;
    *) return 0 ;;
  esac
  case "$text" in *$'\n') nl=1 ;; esac

  if ! _profile_have_jq; then
    echo "profile.sh: jq is required to edit a settings file safely — the profile block is still applied." >&2
    return 1
  fi
  stripped="$(jq "$_PROFILE_STRIP_JQ" "$settings" 2>/dev/null)" || {
    echo "profile.sh: ${settings} is not valid JSON — refusing to write." >&2; return 1; }

  _profile_write "$settings" "$stripped" "$nl"
}

# ─── Diff ────────────────────────────────────────────────────────────────────
#
# The sensor. Re-render, compare, count what is outside. `identical` and
# `absent` are the two clean states; everything else is `stale`, which covers
# both the post-update path change and a hand-edited rule inside the block.
# Accretion is defined uniformly as "allow entries outside the marker block", so
# on a machine with no block applied it is simply the machine's own rule count.

profile_diff() {  # <template-path> <plugin-root>
  local template="${1:-}" root="${2:-}" settings rendered block total blen verdict accretion text=""

  settings="$(_profile_settings_file)"

  if [ ! -f "$settings" ]; then
    echo "profile:diff verdict=absent"
    echo "profile:diff accretion=0"
    return 0
  fi

  if ! _profile_have_jq; then
    _profile_slurp_into text "$settings" || text=""
    case "$text" in
      *"$BIONIC_PROFILE_BEGIN_PREFIX"*) verdict=unknown ;;
      *) verdict=absent ;;
    esac
    echo "profile:diff verdict=${verdict}"
    echo "profile:diff accretion=unknown"
    return 0
  fi

  block="$(jq -c "$_PROFILE_BLOCK_JQ" "$settings" 2>/dev/null)" || block=null
  [ -n "$block" ] || block=null
  total="$(jq '[.permissions.allow[]?] | length' "$settings" 2>/dev/null)"
  case "$total" in ''|*[!0-9]*) total=0 ;; esac

  if [ "$block" = "null" ]; then
    verdict=absent
    blen=0
  else
    blen="$(printf '%s' "$block" | jq 'length' 2>/dev/null)"
    case "$blen" in ''|*[!0-9]*) blen=0 ;; esac
    rendered="$(render_profile "$template" "$root")" || {
      echo "profile:diff verdict=unknown"
      echo "profile:diff accretion=unknown"
      return 0
    }
    if [ "$(printf '%s' "$rendered" | jq -c '.permissions.allow // []' 2>/dev/null)" = "$block" ]; then
      verdict=identical
    else
      verdict=stale
    fi
  fi

  accretion=$((total - blen))
  [ "$accretion" -ge 0 ] || accretion=0

  echo "profile:diff verdict=${verdict}"
  echo "profile:diff accretion=${accretion}"
  return 0
}

# ─── The fact line ───────────────────────────────────────────────────────────
#
# detect.sh's `detect_half_uninstalled` asks whether bionic is still registered
# with the CLI and whether anything is left behind, over the three facts
# detect.sh owns (the legacy rc block, stale managed-hook entries, the
# todo-tools export). The permission marker block is the fourth piece of
# footprint and it is this library's fact, which is why this function wears
# detect.sh's name and line shape: a caller joining the disjunction reads
# `applied=` exactly as it reads `present=`.
#
# Presence and version are read TEXTUALLY, so they survive a machine with no
# `jq` — the state where the question matters most.

detect_profile_state() {
  local settings text applied=no version=none stale=no accretion=unknown line verdict

  settings="$(_profile_settings_file)"
  if [ -f "$settings" ]; then
    _profile_slurp_into text "$settings" || text=""
    case "$text" in
      *"$BIONIC_PROFILE_BEGIN_PREFIX"*)
        applied=yes
        line="$(grep -F "$BIONIC_PROFILE_BEGIN_PREFIX" "$settings" 2>/dev/null | head -1)"
        version="${line#*version=}"
        version="${version%%)*}"
        [ -n "$version" ] || version=none
        ;;
    esac
  fi

  while IFS= read -r line; do
    case "$line" in
      "profile:diff verdict="*)   verdict="${line#profile:diff verdict=}" ;;
      "profile:diff accretion="*) accretion="${line#profile:diff accretion=}" ;;
    esac
  done < <(profile_diff "$(_profile_template_path)" "$(_profile_plugin_root)")

  case "${verdict:-absent}" in
    stale)   stale=yes ;;
    unknown) stale=unknown ;;
    *)       stale=no ;;
  esac

  echo "profile: applied=${applied} version=${version} stale=${stale} accretion=${accretion}"
  return 0
}
