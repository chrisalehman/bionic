#!/bin/bash
# payload/scripts/lib/write-gate.sh — THE WORDS OF THE WRITE HOOK'S REFUSALS.
#
# hooks/canonical-sdlc-governing-skill.sh reads its payload, finds the facts of the artifact being
# written and calls this file when one of them breaks the contract; every sentence a person or an
# agent reads from one of its refusals is spelled here, so a test calls a function and compares text.
#
#   write_gate_say <key> <basename> <path> [<fact>...]
#       Sets WG_FACT, WG_FIX and WG_DETAIL for the refusal <key> names. <basename> and <path> are the
#       artifact's file name and the path being written; the facts after them are the values the
#       sentences quote, in the order the key's branch below reads them. rc 0; rc 2 and the three
#       globals empty for a key that is none of these.
#   write_gate_refuse <key> <basename> <path> [<fact>...]
#       write_gate_say, then `refuse exit2 write` with what it set: the caller exits 2 with the
#       one-line verdict and the detail. It does not return.
#
# Sourced, never executed; it prints nothing and runs nothing at source time. It needs `refuse`
# (lib/refuse.sh) for write_gate_refuse and lib/run.sh for write_gate_header_fault.

write_gate_say() {
  local key="${1:-}" BASENAME="${2-}" FILE_PATH="${3-}"
  WG_FACT=""; WG_FIX=""; WG_DETAIL=""
  [ "$#" -ge 3 ] || return 2
  shift 3
  case "$key" in
    memory)  # <tool> <path> <projects>
      WG_FACT="this writes the memory store"; WG_FIX="use record/<wave>/assumptions.md"
      WG_DETAIL="This $1 writes $2, inside the auto-memory store ($3/*/memory).
An engaged run keeps what it learns where the run can see it: a judgment call goes in
record/<wave>/assumptions.md, and a correction that should outlive the run goes to the user
as a rule proposal (record/<wave>/user-rules-proposed.md), for the rules file that owns it.
Nothing that gates or reviews this run reads the store. Reading it stays open." ;;
    misplaced)  # <docs root> <subdir> <project root>
      WG_FACT="this artifact is outside the docs root"; WG_FIX="write it under the docs root"
      WG_DETAIL="canonical-sdlc artifact '$BASENAME' is misplaced.
Path: $FILE_PATH
It declares canonical-sdlc frontmatter but does not live under this project's docs root.
Docs root: $1
Fix: write it under $1/$2/ instead.
     (the docs root is <project>/.bionic/docs by default; override with 'docs-root:' in $3/.bionic/config.yaml)" ;;
    unpinned)  # <target .bionic> <pinned .bionic>
      WG_FACT="this write targets an unpinned .bionic root"; WG_FIX="write under the pinned root"
      WG_DETAIL="artifact write targets '$1', not this project's pinned .bionic root.
Path: $FILE_PATH
Pinned root: $2
Fix: write under $2 instead — the .bionic tree is pinned to the main repository root at Step 0 and is never re-derived from a worktree or subdirectory copy." ;;
    no-content)
      WG_FACT="this artifact has no content to validate"; WG_FIX="create it with Write"
      WG_DETAIL="canonical-sdlc artifact '$BASENAME' has no content to validate.
Path: $FILE_PATH
Fix: use Write to create the artifact with governing-skill frontmatter." ;;
    no-frontmatter)  # <supported version>
      WG_FACT="this artifact has no frontmatter block"; WG_FIX="prepend a frontmatter block"
      WG_DETAIL="canonical-sdlc artifact '$BASENAME' is missing a YAML frontmatter block.
Path: $FILE_PATH
Fix: prepend:
  ---
  governing-skill: <skill-id for the step that produced this artifact>
  sdlc-step: <step number>
  epic: epic-NN-<slug>
  wave: wave-NN-<slug>   # omit for epic-level and continuation
  canonical_sdlc_version: $1
  intent: <build|bugfix|refactor|tune|spike|incident-response>
  rigor: <single|double>
  scale: <task|wave|epic>
  ---" ;;
    no-temp-file)
      WG_FACT="this artifact could not be read"; WG_FIX="retry the write"
      WG_DETAIL="canonical-sdlc artifact '$BASENAME': no temporary file could be made to read it through the plan parser.
Path: $FILE_PATH" ;;
    no-governing)
      WG_FACT="this artifact declares no governing skill"; WG_FIX="add a 'governing-skill:' line"
      WG_DETAIL="canonical-sdlc artifact '$BASENAME' is missing a 'governing-skill:' frontmatter field.
Path: $FILE_PATH
Fix: add a non-empty 'governing-skill: <skill-id>' line to the frontmatter block." ;;
    bad-version)  # <declared version> <supported version>
      WG_FACT="this artifact declares an unsupported version"; WG_FIX="set the supported version"
      WG_DETAIL="canonical-sdlc artifact '$BASENAME' declares canonical_sdlc_version: '$1'.
Path: $FILE_PATH
Fix: set 'canonical_sdlc_version: $2' — the only supported version." ;;
    mode)
      _write_gate_frame "this artifact declares mode:" "declare intent:, rigor: and scale:" \
        "artifacts declare intent:/rigor:/scale:, never mode:" ;;
    no-intent)
      _write_gate_frame "this artifact declares no intent:" "add an intent: line" \
        "requires intent: (build|bugfix|refactor|tune|spike|incident-response)" ;;
    no-rigor)  # <rigor set>
      _write_gate_frame "this artifact declares no rigor:" "add a rigor: line" \
        "requires rigor: single or double:$1" ;;
    no-scale)
      _write_gate_frame "this artifact declares no scale:" "add a scale: line" \
        "requires scale: (task|wave|epic)" ;;
    bad-intent)  # <intent>
      _write_gate_frame "that intent is not one of the six" "pick an allowed intent" \
        "invalid intent: '$1' — allowed: build|bugfix|refactor|tune|spike|incident-response" ;;
    bad-rigor)  # <rigor> <rigor set>
      _write_gate_frame "that rigor is not single or double" "pick an allowed rigor" \
        "invalid rigor: '$1' — allowed: single or double:$2" ;;
    bad-scale)  # <scale>
      _write_gate_frame "that scale is not task, wave or epic" "pick an allowed scale" \
        "invalid scale: '$1' — allowed: task|wave|epic" ;;
    bad-cadence)  # <review-cadence>
      _write_gate_frame "that review-cadence is not once" "use once" \
        "invalid review-cadence: '$1' — allowed: once" ;;
    policy-empty)  # <fix-policy vocabulary, space-joined>
      _write_gate_frame "this fix-policy names no rating" "${1// /,}" \
        "invalid fix-policy: '' — it names no rating; allowed, comma-joined: $1" ;;
    policy-word)  # <fix-policy> <the word that is no rating> <vocabulary>
      _write_gate_frame "a fix-policy word is no rating" "${3// /,}" \
        "invalid fix-policy: '$1' — '$2' is no rating; allowed, comma-joined: $3" ;;
    bad-cap)  # <fix-cap>
      _write_gate_frame "that fix-cap is no count" "a whole number, or a percent" \
        "invalid fix-cap: '$1' — allowed: a whole number (2) or a percent of the plan's ## Tasks rows (10%)" ;;
    bad-walk)  # <walk>
      _write_gate_frame "that walk is not required or exempt" "use required or exempt" \
        "invalid walk: '$1' — allowed: required|exempt" ;;
    alias-project)  # <the alias map's sentence> <project root>
      _write_gate_frame "$1" "rename the key" \
        "$2/.bionic/config.yaml still carries the old key; its value is not read" ;;
    alias-epic)  # <the alias map's sentence> <docs root> <epic>
      _write_gate_frame "$1" "rename the key" \
        "the frontmatter of $2/plans/$3/epic.plan.md still carries the old key; its value is not read" ;;
    lease)  # <cwd> <worktree> <main checkout>
      WG_FACT="this plan is written from a worktree"; WG_FIX="write it from the main checkout"
      WG_DETAIL="canonical-sdlc plan '$BASENAME' is being written from inside a linked worktree.

    cwd:           $1
    worktree:      $2
    main checkout: $3

The plan is the run's own artifact and it lives in the main checkout: written here
it lands on the tree's branch, where every hook that reads the active run cannot
see it until the lease ends.

Fix: write the plan from $3. A dispatched agent working in its own tree
may write there — this refusal is the main thread's alone." ;;
    missing-flags)  # <missing flags> <opt-in flags> <discriminator flags>
      WG_FACT="this plan is missing frontmatter flags"; WG_FIX="run Step 0 to set them"
      WG_DETAIL="canonical-sdlc plan '$BASENAME' is missing required frontmatter flags: $1
Path: $FILE_PATH
Fix: run Step 0 (Configure) to set these explicitly. See SKILL.md §Step 0.
Required opt-in flags:        $2
Required discriminator flags: $3
Required:                     model_plan" ;;
    no-matrix)  # <sdlc-step>
      WG_FACT="this plan has no Verification Matrix"; WG_FIX="add the Verification Matrix"
      WG_DETAIL="canonical-sdlc plan '$BASENAME' (sdlc-step $1) is missing a '## Verification Matrix' section.
Path: $FILE_PATH
Fix: derive the matrix at Step 0 (see SKILL.md §Step 0 'the Verification Matrix') and lock it at Step 3 approval." ;;
    bring-forward)  # <supported version> <the bring-forward summary>
      WG_FACT="this plan's body is not at contract version $1"; WG_FIX="bring the plan forward"
      WG_DETAIL="canonical-sdlc plan '$BASENAME' declares canonical_sdlc_version: $1 and its body does not match it:
$2
Path: $FILE_PATH
Fix: repair every line above in one pass — each is a separate arm that would otherwise refuse the next commit in turn." ;;
    tasks-invalid)  # <sdlc-step> <the violations>
      WG_FACT="this plan's Tasks table is invalid"; WG_FIX="fix the row the detail names"
      WG_DETAIL="canonical-sdlc plan '$BASENAME' (sdlc-step $1) has a '## Tasks' table that breaks the Task invariants:
$2
Path: $FILE_PATH
Fix: repair each row named above; the columns are id | step | kind | task | agent | deps | size | serves | Files | worktree | base | status. A reads column is optional and may sit anywhere in the header." ;;
    version-15)  # <the parts version 15 has no place for>
      WG_FACT="this plan holds what version 15 does not"; WG_FIX="remove each part named"
      WG_DETAIL="canonical-sdlc plan '$BASENAME' declares canonical_sdlc_version: 15, and version 15 has no place for:
$1
Path: $FILE_PATH
Fix: remove each part named; the run's state is the log's, and the reader answers it." ;;
    design)  # <scale> <what went wrong>
      # ONE ROW FOR FOUR ARMS: all four say the same thing to the reader — this spec names no design
      # anywhere — and differ only in WHICH route was tried, which is what `detail` carries.
      WG_FACT="this spec names no '## Design' anywhere"; WG_FIX="add a '## Design' section"
      WG_DETAIL="canonical-sdlc spec '$BASENAME' (scale: $1): $2
Path: $FILE_PATH
A wave- or epic-scale spec must satisfy one of three:
  (a) a flush-left '## Design' section in this spec;
  (b) frontmatter 'design: <path>' naming a file that carries a flush-left '## Design';
  (c) frontmatter 'design-waived: <user> <date> <reason>' — a user-only move." ;;
    adrs-climb)  # <sdlc-step> <adrs: entry>
      WG_FACT="the adrs: path climbs out with '..'"; WG_FIX="name it under the docs root"
      WG_DETAIL="canonical-sdlc spec '$BASENAME' (sdlc-step $1): adrs: '$2' climbs out with a '..' component and is refused.
Path: $FILE_PATH" ;;
    adrs-missing)  # <sdlc-step> <adrs: entry> <resolved path>
      WG_FACT="the adrs: path names no file"; WG_FIX="draft the ADR at that path"
      WG_DETAIL="canonical-sdlc spec '$BASENAME' (sdlc-step $1): adrs: '$2' names no file (resolved to $3).
Path: $FILE_PATH
Fix: draft the ADR at that path, or correct the adrs: pointer." ;;
    goal-empty)  # <scale>
      WG_FACT="this artifact's Goal section is empty"; WG_FIX="write a paragraph under '## Goal'"
      WG_DETAIL="canonical-sdlc artifact '$BASENAME' (scale: $1): the 'Goal' section is empty.
Path: $FILE_PATH
Fix: write one concise paragraph describing the goal under '## Goal'." ;;
    goal-first)  # <scale>
      WG_FACT="the first section is not '## Goal'"; WG_FIX="open with a '## Goal' section"
      WG_DETAIL="canonical-sdlc artifact '$BASENAME' (scale: $1): the first section after the title is not '## Goal'.
Path: $FILE_PATH
Fix: open with a '## Goal' section — one concise paragraph — immediately after the title." ;;
    theme)  # <the theme fault: kind TAB what> <scale>
      local what="${1#*	}"
      case "${1%%	*}" in
        flat)  WG_FACT="$what is under '## Requirements', no theme" ;;
        none)  WG_FACT="$what is under no ## section" ;;
        count) WG_FACT="$what theme sections, not 3 to 6" ;;
        *)     [ "${#what}" -le 24 ] || what="${what:0:23}…"
               WG_FACT="'$what' opens on no sentence" ;;
      esac
      WG_FIX="theme rule: 3-6 ## themes"
      WG_DETAIL="canonical-sdlc requirements '$BASENAME' (scale: $2): $WG_FACT.
Path: $FILE_PATH
Fix: group the REQs under three to six '## <theme>' sections, each opening on one sentence that says what the run is for in that respect, the '### REQ-' headings under them." ;;
    *) return 2 ;;
  esac
}

# write_gate_header_fault <mode> <intent> <rigor> <scale> <walk> <has cadence 0|1> <cadence> <has policy> <policy> <has cap> <cap>
#     THE DECISION behind the header refusals, in the order the hook has always asked: a declared
#     `mode:`; the triple missing, then the triple outside its sets; a present review-cadence:,
#     fix-policy: or fix-cap: outside its vocabulary (lib/run.sh's, judged only when the key is
#     there); a walk: that is neither word. rc 0 with WG_FAULT holding the refusal key and its facts,
#     for `write_gate_refuse "${WG_FAULT[@]}"`'s arguments after the artifact; rc 1 and WG_FAULT
#     empty when the header holds none. Needs lib/run.sh.
write_gate_header_fault() {
  local mode="$1" intent="$2" rigor="$3" scale="$4" walk="$5" cad="$7" pol="$9" cap="${11}" set bad
  WG_FAULT=()
  [ -z "$mode" ] || { WG_FAULT=(mode); return 0; }
  [ -n "$intent" ] || { WG_FAULT=(no-intent); return 0; }
  set="$(printf '\n  %s' "$(rigor_print single)" "$(rigor_print double)")"
  [ -n "$rigor" ] || { WG_FAULT=(no-rigor "$set"); return 0; }
  [ -n "$scale" ] || { WG_FAULT=(no-scale); return 0; }
  case "$intent" in
    build|bugfix|refactor|tune|spike|incident-response) ;;
    *) WG_FAULT=(bad-intent "$intent"); return 0 ;;
  esac
  rigor_level "$rigor" >/dev/null || { WG_FAULT=(bad-rigor "$rigor" "$set"); return 0; }
  case "$scale" in
    task|wave|epic) ;;
    *) WG_FAULT=(bad-scale "$scale"); return 0 ;;
  esac
  if [ "$6" = 1 ]; then
    review_cadence_level "$cad" >/dev/null || { WG_FAULT=(bad-cadence "$cad"); return 0; }
  fi
  if [ "$8" = 1 ]; then
    if bad=$(fix_policy_bad "$pol"); then :
    elif [ -z "${pol//[[:space:]]/}" ]; then WG_FAULT=(policy-empty "$FIX_POLICY_VOCAB"); return 0
    else WG_FAULT=(policy-word "$pol" "$bad" "$FIX_POLICY_VOCAB"); return 0
    fi
  fi
  if [ "${10}" = 1 ]; then
    { [ -n "$cap" ] && fix_cap_render "$cap" "$rigor" 0 >/dev/null; } || { WG_FAULT=(bad-cap "$cap"); return 0; }
  fi
  case "$walk" in
    ''|required|exempt) ;;
    *) WG_FAULT=(bad-walk "$walk"); return 0 ;;
  esac
  return 1
}

# _write_gate_frame <fact> <fix> <what went wrong> — THE FRAME KEEPS ITS PARAMETER AND LOSES ITS
# VOICE: the ruled fact and fix render as the one user line; the artifact
# name, its path and the sentence become `detail`.
_write_gate_frame() {
  WG_FACT="$1"; WG_FIX="$2"
  WG_DETAIL="canonical-sdlc artifact '$BASENAME': $3
Path: $FILE_PATH"
}

write_gate_refuse() {
  write_gate_say "$@" || return 2
  refuse exit2 write "$WG_FACT" "$WG_FIX" "$WG_DETAIL"
}
