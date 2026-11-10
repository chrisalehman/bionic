#!/bin/bash
# tests/one-reader.test.sh — payload/scripts/one-reader-check.sh, the count of what the one-reader rule
# names over a checkout: parsers of a plan or a log outside the reader, plan writers, event types with
# two writers, refusal words in hook files and pasted loader copies. It reports and exits 0.
#
#   §PARSERS      an awk over a plan planted under payload/scripts/lib/ is named and the count rises by one;
#                 the same awk inside the reader's own file is admitted.
#   §PLANWRITERS  a planted append to a plan is named and the count rises by one.
#   §WRITERS      two functions appending one event type are listed as a pair; so is `published` today.
#   §REFUSALS     refusal words planted in a registered hook file are listed and counted.
#   §REPORT       the check exits 0 with findings and ends on the five count lines, in their order.
#
# FIXTURE FIDELITY. Every run reads a scratch copy of this checkout's hooks/ and payload/scripts/;
# the plants are real files in that copy.

set -uo pipefail
. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"
CHECK="${BIONIC_SCRIPTS_DIR}/payload/scripts/one-reader-check.sh"
S="$(mktemp -d)"; trap 'rm -rf "$S"' EXIT; mkdir -p "$S/payload"
cp -R "${BIONIC_SCRIPTS_DIR}/hooks" "$S/hooks"; cp -R "${BIONIC_SCRIPTS_DIR}/payload/scripts" "$S/payload/scripts"
run() { bash "$CHECK" "$S"; }
count() { printf '%s\n' "$1" | sed -n "s/^$2=//p"; }
BEFORE="$(run)"
L="$S/payload/scripts/lib"
cat > "$L/planted-parse.sh" <<'EOF'
planted_rows() { awk -F'|' '$2 ~ /^ T[0-9]+ $/ { print $2 }' "$plan"; }
EOF
cat > "$L/planted-write.sh" <<'EOF'
planted_line() { printf -- '- %s: landed\n' "$1" >> "$plan"; }
EOF
cat > "$L/planted-writers.sh" <<'EOF'
planted_born_a() { log_append born row=T1; }
planted_born_b() { log_append born row=T2; }
EOF
printf '%s\n' "planted_reader_rows() { awk -F'|' '\$2 ~ /T/' \"\$plan\"; }" >> "$L/reader.sh"
printf '%s\n' 'deny "planted refusal words"' >> "$S/hooks/engage.sh"
AFTER="$(run)"; RC=$?

section "PARSERS"
expect_contains "a real parser is named at this head" "$(printf 'parser\tpayload/scripts/card.sh\t')" "$BEFORE"
expect_contains "the planted awk over a plan is named" "$(printf 'parser\tpayload/scripts/lib/planted-parse.sh\t')" "$AFTER"
expect_eq "the parser count rises by one" "$(( $(count "$BEFORE" parsers) + 1 ))" "$(count "$AFTER" parsers)"
expect_absent "the reader's own file is admitted, its planted awk too" "lib/reader.sh" "$AFTER"

section "PLANWRITERS"
expect_contains "the planted plan write is named" "$(printf 'plan-writer\tpayload/scripts/lib/planted-write.sh\t')" "$AFTER"
expect_absent "a plan write is not a parse" "$(printf 'parser\tpayload/scripts/lib/planted-write.sh')" "$AFTER"
expect_eq "the plan-writer count rises by one" "$(( $(count "$BEFORE" plan_writers) + 1 ))" "$(count "$AFTER" plan_writers)"

section "WRITERS"
expect_contains "two functions appending one type are a pair" \
  "$(printf 'shared\tborn\tpayload/scripts/lib/planted-writers.sh:planted_born_a payload/scripts/lib/planted-writers.sh:planted_born_b')" "$AFTER"
PUB="$(printf '%s\n' "$BEFORE" | awk -F'\t' '$1 == "shared" && $2 == "published" { print $3 }')"
expect_contains "published: the queue landing's writer" "payload/scripts/lib/line.sh:line_publish" "$PUB"
expect_contains "published: the hand landing's writer" "hooks/poker/line.sh:poker_verb_row_landed" "$PUB"
expect_eq "the shared-type count rises by one" "$(( $(count "$BEFORE" shared_types) + 1 ))" "$(count "$AFTER" shared_types)"

section "REFUSALS"
expect_contains "a real refusal site in a hook file is listed" "$(printf 'refusal\thooks/dispatch-preflight.sh:')" "$BEFORE"
expect_regex "the planted refusal words are listed" "^refusal	hooks/engage\.sh:[0-9]+	deny$" "$AFTER"
expect_eq "the refusal count rises by one" "$(( $(count "$BEFORE" hook_refusals) + 1 ))" "$(count "$AFTER" hook_refusals)"

section "REPORT"
expect_status "the check exits 0 with findings" 0 "$RC"
expect_eq "it ends on the five count lines, in order" "parsers plan_writers shared_types hook_refusals loader_copies" \
  "$(printf '%s\n' "$AFTER" | tail -5 | sed -n 's/^\([a-z_]*\)=[0-9][0-9]*$/\1/p' | tr '\n' ' ' | sed 's/ $//')"
expect_contains "a pasted loader copy is listed" "$(printf 'loader\thooks/bash-walls.sh\t')" "$AFTER"
expect_absent "the loader's own library is not a copy" "$(printf 'loader\tpayload/scripts/lib/loader.sh')" "$AFTER"
bash "$CHECK" "$S/no-such" >/dev/null 2>&1; expect_status "a root that is not a checkout exits 2" 2 "$?"

finish
