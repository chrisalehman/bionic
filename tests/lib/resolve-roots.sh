# tests/lib/resolve-roots.sh — STUB (epic-17 wave-02 S1, RED step).
#
# The naive resolution the seam is meant to replace: caller-pwd derived, not
# env-overridable. Present so tests/seam-resolution.test.sh fails on the
# PROPERTIES under test (override binding, location independence) rather than on
# a missing source. Replaced by the real helper at GREEN.

BIONIC_HOOKS_DIR="$(pwd)/hooks"
BIONIC_SKILLS_DIR="$(pwd)/skills"
BIONIC_SCRIPTS_DIR="$(pwd)"
export BIONIC_HOOKS_DIR BIONIC_SKILLS_DIR BIONIC_SCRIPTS_DIR
