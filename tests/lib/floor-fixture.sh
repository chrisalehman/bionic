# tests/lib/floor-fixture.sh — THE ONE FLOOR-LOG FIXTURE (wave-37 T4; D7, REQ-6 AC-6.1; ADR-057).
#
#     . "$(dirname "$0")/lib/resolve-roots.sh"      # first, so BIONIC_SCRIPTS_DIR is set
#     . "$(dirname "$0")/lib/floor-fixture.sh"
#
# WHAT IT REPLACES. A floor proof cites a run the machine recorded: `proof-add floor` accepts a log only when an
# `ev=run` line of the plan's landing record matches it on head, exit and hash (lib/proof.sh `_proof_floor_match`).
# About 36 fixtures across five suites hand-wrote a floor log (`printf 'head=%s dirty=0\n…rc=0\n'`) and nothing else,
# the very shape the reader now refuses. Each fixture that is to be ACCEPTED writes its log here, and the log's run
# line with it, so a run line and its log cannot drift apart in a fixture. A fixture that tests a refusal of the
# floor's grammar (no header, a dirty tree, no rc line) is refused before any run line is read and stays as written.
#
# floor_fixture [--pre <lines>] <plan> <log> <head> <dirty> <rc> -> writes <log> in the floor's one grammar: <lines>
# (a runner's preamble, e.g. tests/run.sh's `rung=`/`env:`) if given, then `head=<head> dirty=<dirty>`, then stdin as
# the body, then `rc=<rc>`. Then it appends the run line THROUGH THE PRODUCT'S WRITER, lib/line.sh `line_event <plan>
# run`, to <plan>'s landing record: `log=` the log's real path under the docs root, its head, dirty count, exit and
# sha256 (lib/detect.sh `_detect_sha256`, the product's hash), and `at=` from the writer. rc 1 when either write fails.
floor_fixture() {
  local pre="" plan log head dirty rc
  if [ "${1:-}" = --pre ]; then pre="$2"; shift 2; fi
  plan="$1" log="$2" head="$3" dirty="$4" rc="$5"
  mkdir -p "${log%/*}" || return 1
  { [ -z "$pre" ] || printf '%s\n' "$pre"
    printf 'head=%s dirty=%s\n' "$head" "$dirty"
    cat
    printf 'rc=%s\n' "$rc"; } > "$log" || return 1
  bash -c '
    . "$1/payload/scripts/lib/line.sh" >/dev/null 2>&1 && . "$1/payload/scripts/lib/detect.sh" >/dev/null 2>&1 || exit 1
    rec="$(line_record "$2")" || exit 1
    docs="${rec%/record/*}"
    real="$(cd "${3%/*}" && pwd -P)/${3##*/}" || exit 1
    sha="$(_detect_sha256 "$real")" || exit 1
    line_event "$2" run "log=${real#"$docs"/}" "head=$4" "dirty=$5" "rc=$6" "sha256=$sha"' \
    _ "$BIONIC_SCRIPTS_DIR" "$plan" "$log" "$head" "$dirty" "$rc"
}
