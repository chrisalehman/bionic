#!/bin/bash
# payload/scripts/lib/bounds.sh — THE RULE FOR AN INNER BOUND. IT DEFINES NO CONSTANT.
# (epic-23 wave-14-tune-181, REQ-7; design ledger D2 for the invariant below.)
#
# WHAT IS LEFT HERE. This file owned the two derivation bounds, the dispatch wall's and the
# landing sweep's. Both went with the file-to-suite map (wave-31 T2 the wall's, T23 the
# sweep's; REQ-4 AC-4.2): a brief names its suites, so neither waits on a derivation. What
# stays is the rule the hooks' own deadlines still follow, kept where they cite it
# (hooks/dispatch-preflight.sh `DP_DEADLINE_S`, hooks/stop-guard.sh `SG_DEADLINE_S`). Each
# deadline is defined in its own hook, beside the code it bounds.
#
# ── THE RULE ─────────────────────────────────────────────────────────────────
#
# AN INNER BOUND SITS STRICTLY UNDER ITS HOOK'S REGISTRATION, MARGIN NAMED.
#
# The registration is hooks/hooks.json's, and the margin is what the hook has left
# for everything it does that is not waiting.
#
# WHY STRICTLY UNDER, AND NOT AT. A bound at or above its registration can never
# fire: the CLI kills the hook at the registration, and a killed hook exits 124 —
# not the exit 2 a refusal spells — so the refusal that was in flight silently
# becomes a PASS. That is the one thing a gate must never do, and it is exactly
# what a bound above its registration guarantees.
#
# AND NO SUITE THAT DRIVES A GATE DIRECTLY CAN SEE IT. A suite has no CLI timeout,
# so the number can be wrong while every arm that drives the refusal stays green.
# The pair is pinned where the two files meet, both sides read rather than
# transcribed: tests/cross-gate-agreement.test.sh §L.4c.
#
# NO SHELL OPTIONS ARE SET HERE, AND NOTHING IS DEFINED. A caller that still sources
# this file gets nothing from it; the source is harmless and goes with its caller.
#
# [WALL: tests/cross-gate-agreement.test.sh §L.4c]
