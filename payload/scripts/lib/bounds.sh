#!/bin/bash
# payload/scripts/lib/bounds.sh — THE DERIVATION BOUND, DEFINED ONCE.
# (epic-23 wave-14-tune-181, REQ-7; spec Design §1 "Derivation" and §3 ownership
# row "derivation bound"; design ledger D4, and D1/D2 for the invariant below.)
#
# WHAT IT OWNS. How long the landing sweep waits for the impacted-suite derivation
# (whatever `impact-command:` names) before it stops waiting:
#
#   payload/scripts/lib/stop.sh           once per sweep, spent across its rows
#                                         -> LG_IMPACT_BOUND_S
#
# The dispatch wall's own bound went with its derivation (wave-31 T2, REQ-4 AC-4.2):
# a brief names its suites, so the wall waits on nothing.
#
# WHY IT IS ITS OWN FILE. The sweep and the dispatch wall each carried their own `6`,
# in two files, under two headers that each explained the number and neither of
# which mentioned the other (R2 Q8 found the twin). Two copies of a constant do not
# disagree loudly; a shared library is the smallest thing that cannot drift.
#
# ── THE RULE THAT GOVERNS THE NUMBER ─────────────────────────────────────────
#
# AN INNER BOUND SITS STRICTLY UNDER ITS HOOK'S REGISTRATION, MARGIN NAMED.
#
#   LG_IMPACT_BOUND_S =  6   under hooks/stop.sh's  "timeout": 10       margin 4
#
# The registration is hooks/hooks.json's, and the margin is what the hook has left
# for everything it does that is not waiting.
#
# WHY STRICTLY UNDER, AND NOT AT. A bound at or above its registration can never
# fire: the CLI kills the hook at the registration, and a killed hook exits 124 —
# not the exit 2 a refusal spells — so the refusal that was in flight silently
# becomes a PASS. That is the one thing the gate must never do, and it is exactly
# what a bound above its registration guarantees.
#
# AND NO SUITE THAT DRIVES A GATE DIRECTLY CAN SEE IT. A suite has no CLI
# timeout, so the number can be wrong while every arm that drives the refusal
# stays green — which is what happened: a 20 s bound sat under a 10 s
# registration for the whole of wave-14 (A-T6.5, confirmed by four reviewers).
# The pair is therefore pinned where the two files meet, both sides read rather
# than transcribed: tests/cross-gate-agreement.test.sh §L.4c, and
# tests/stop.test.sh 6e/6f against hooks.json too.
#
# ── IT IS A HANG GUARD, NOT A COST BUDGET ────────────────────────────────────
#
# What is left for a bound to do is the thing no cache can fix — a configured
# impact command that never returns. The wait has to end on OUR terms, before the
# CLI ends it on its own.
#
# THIS ONE IS NOT A CHOICE ABOUT SLOWNESS. It is a ceiling its host imposes. The
# landing sweep runs inside hooks/stop.sh, which hooks/hooks.json registers at
# `"timeout": 10` on both Stop and SubagentStop — and that registration bounds four
# verdicts, of which the sweep is one. Six seconds is the sweep's whole derivation
# budget spent strictly inside it, with four seconds left for the rest of the
# turn-end work. tests/landing-gate.test.sh §16i drives it live.
#
# LG_IMPACT_BOUND_S moves only if hooks.json's registration for hooks/stop.sh
# moves, and never above it.
#
# WHAT WOULD BE WRONG. Lowering it because a derivation felt slow is treating it as
# a budget again. Raising it past the point where a stuck hook reads as a hung
# session is the opposite error. Raising it to meet its registration — the shape
# wave-14 T9 shipped and §16i caught — buys nothing and costs the refusal.
#
# NO SHELL OPTIONS ARE SET HERE. This file is sourced into a caller's shell and
# defines one constant; `set -u`, `set -o pipefail` and traps belong to whoever
# sourced it.
#
# [WALL: tests/stop.test.sh]
# [WALL: tests/cross-gate-agreement.test.sh §L.4c]

LG_IMPACT_BOUND_S=6
