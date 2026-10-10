#!/bin/bash
# tests/reader-exam/score.sh — README step 5 as code. Sourced, it defines four functions
# (exam_meets, exam_field, exam_declared, exam_score) and does nothing else:
# tests/exam/reader-exam.sh holds the real keys to them, and a sitting scores its records with them.
#
#   . tests/reader-exam/score.sh
#   exam_score tests/reader-exam/samples/<name>/expect.txt <record>
#     prints `met: declared` or `met`; or `missed`, which says why when the miss is the declaration

# exam_meets <key result> <reached result> — rc 0 when the reached result meets the key's. A
# key of `pass` is a change with no defect, and not failing it is the bar: `pass` or `flag`.
# Any other key is met by itself alone.
exam_meets() {
  case "$1" in
    pass) case "$2" in pass|flag) return 0 ;; esac; return 1 ;;
    "") return 1 ;;
    *) [ "$2" = "$1" ] ;;
  esac
}

# exam_field <expect.txt> <field> — the value of the key's first `<field>:` line, read without a
# CR before its line end or blanks after it.
exam_field() {
  sed -n "s/^$2: //p" "$1" | head -n 1 | sed 's/\r$//; s/[[:blank:]]*$//'
}

# exam_declared <expect.txt> <one pass of a record, as a file> — whether the pass DECLARES the
# planted defect (wave-28 T18; D22, AC-8.6): prints `declared` (rc 0), or why not (rc 1). A key
# with no `finding-file:` line asks no declaration (a change with no defect). Otherwise the pass
# must carry a `finding:` line, read by the registering verb's own reader (`proof_findings`,
# payload/scripts/lib/proof.sh: the one parser of the finding lines, called and never copied), that
# names one of the key's files at a severity and reach the key lists, which the priority table sends
# to fix. The reasons, in the words the scorer prints after `missed: `:
#   described only                        no findings: or finding: line, or findings: 0
#   finding lines refused: <why>          the verb's reader refused the lines (a finding to fix
#                                         with no shown: command, a bad rating)
#   no finding names <file>[ or <file>]   findings, none on a file of the key
#   declared at <S> <reach>: deferred     the table defers the rating (S2 off, S3 on)
#   declared at <S> <reach>: noted        the table notes it (S3 off, S4)
#   declared at <S> <reach>: not a rating this key admits    fix-grade, but not on the key's list
#   declared as debt <kind>: not a rating this key admits    a debt: line on a harm key's file
# A DEBT KEY (wave-30 T22; D2) carries `finding-kind: <kind>` in place of `finding-rating:`: the pass
# must carry a `debt:` line of that kind (proof_findings' `debt` row) with a site on one of the key's
# files. Its reasons:
#   no debt line names <file>[ or <file>]                      debt lines, none on a file of the key
#   declared as debt <kind>: not the kind this key asks        a debt line of another kind
#   declared at <S> <reach>: a debt key asks a debt: line of kind <kind>   a rated finding instead
# A file matches by its path as written, or under a directory (an absolute path in the project).
exam_declared() {
  local key="$1" pass="$2" files ratings kind lib rec out rc id sev reach loc pri shown title
  local path alts alt onfile ok why first="" sites site
  files="$(exam_field "$key" finding-file)"; ratings="$(exam_field "$key" finding-rating)"
  kind="$(exam_field "$key" finding-kind)"
  [ -n "$files" ] || { echo "declared"; return 0; }
  grep -Eq '^(findings|finding|debt):' "$pass" || { echo "described only"; return 1; }
  lib="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/payload/scripts/lib/proof.sh"
  [ -r "$lib" ] || { echo "finding lines refused: $lib cannot be read"; return 1; }
  # The reader cuts a pass from its `reviewed:` line to the next one: the pass is given one of its own.
  rec="$pass.rec"
  { echo "reviewed: exam..pass"; grep -v '^reviewed:' "$pass"; } > "$rec"
  out="$(. "$lib"; proof_findings "$rec" 2>&1)"; rc=$?
  if [ "$rc" != 0 ]; then
    out="${out//the reading $rec/the record}"
    echo "finding lines refused: $out"; return 1
  fi
  [ -n "$out" ] || { echo "described only"; return 1; }
  while IFS=$'\t' read -r id sev reach loc pri shown title; do
    [ -n "$id" ] || continue
    # A debt row is `debt <kind> <concept> <sites> burn`: each site is a <path>:<line>.
    sites="$loc"; [ "$id" = debt ] || sites="${loc%%, *}"
    onfile=0
    while [ -n "$sites" ]; do
      site="${sites%%, *}"; if [ "$site" = "$sites" ]; then sites=""; else sites="${sites#*, }"; fi
      path="${site%:*}"; path="${path#./}"
      alts="$files"
      while [ -n "$alts" ]; do
        alt="${alts%% | *}"; if [ "$alt" = "$alts" ]; then alts=""; else alts="${alts#* | }"; fi
        case "$path" in "$alt"|*/"$alt") onfile=1 ;; esac
      done
    done
    [ "$onfile" = 1 ] || continue
    if [ "$id" = debt ]; then
      if [ -n "$kind" ] && [ "$sev" = "$kind" ]; then echo "declared"; return 0; fi
      if [ -z "$first" ]; then
        if [ -n "$kind" ]; then first="declared as debt $sev: not the kind this key asks"
        else first="declared as debt $sev: not a rating this key admits"; fi
      fi
      continue
    fi
    if [ -n "$kind" ]; then
      [ -n "$first" ] || first="declared at $sev $reach: a debt key asks a debt: line of kind $kind"
      continue
    fi
    ok=0; alts="$ratings"
    while [ -n "$alts" ]; do
      alt="${alts%% | *}"; if [ "$alt" = "$alts" ]; then alts=""; else alts="${alts#* | }"; fi
      [ "$alt" = "$sev $reach" ] && ok=1
    done
    if [ "$pri" = fix ] && [ "$ok" = 1 ]; then echo "declared"; return 0; fi
    if [ -z "$first" ]; then
      case "$pri" in
        fix) why="not a rating this key admits" ;;
        defer) why="deferred" ;;
        *) why="noted" ;;
      esac
      first="declared at $sev $reach: $why"
    fi
  done <<EOF
$out
EOF
  [ -z "$first" ] || { echo "$first"; return 1; }
  if [ -n "$kind" ]; then echo "no debt line names ${files// | / or }"; return 1; fi
  echo "no finding names ${files// | / or }"; return 1
}

# exam_score <expect.txt> <record> — prints `met: declared` or `met` (rc 0), or `missed` (rc 1),
# which carries `: <why>` when the miss is the declaration (exam_declared).
#
# A record is read as passes: each flush-left `question:` line opens one, and the first pass
# also holds the lines above it. Only a pass whose question the key names is scored, so a
# one-mind reader's three passes in one file are each read on their own question, never on
# whichever `result:` comes first. Met when at least one pass is scored and every scored pass
# has: a declaration of the planted defect (exam_declared, asked of a key with a `finding-file:`
# line, and read first so that a miss on it says which); its first flush-left `result:` meeting
# the key's result (exam_meets); one of the key's tokens; and, when the key has a `names:` line,
# one of its identifiers. Alternatives on a `token:` or `names:` line are separated by ` | `. A CR
# before a line end, and blanks after a value, are not part of it. The scorer's own lines are read
# with an IFS of its own: a caller's IFS (`,`, `:` or empty) is not the separator of what the awk
# below prints.
exam_score() {
  local key="$1" rec="$2" kq kr kt kn passes r t n i scored=0 pd why verdict="" decl=0
  [ -r "$key" ] && [ -r "$rec" ] || { echo "missed"; return 1; }
  kq="$(exam_field "$key" question)"; kr="$(exam_field "$key" result)"
  kt="$(exam_field "$key" token)"; kn="$(exam_field "$key" names)"
  [ -z "$(exam_field "$key" finding-file)" ] || decl=1
  pd="$(mktemp -d "${TMPDIR:-/tmp}/exam-score.XXXXXX")" || { echo "missed"; return 1; }
  passes="$(PD="$pd" KQ="$kq" KT="$kt" KN="$kn" awk '
    function value(s) { sub(/^[a-z]+:[ \t]*/, "", s); sub(/[ \t]+$/, "", s); return s }
    function any(list, text,   a, i, k) {
      if (list == "") return 1
      k = split(list, a, / \| /)
      for (i = 1; i <= k; i++) if (a[i] != "" && index(text, a[i])) return 1
      return 0
    }
    BEGIN { np = 1; split(ENVIRON["KQ"], qs, /, */); for (i in qs) keyed[qs[i]] = 1 }
    { sub(/\r$/, "") }
    /^question:/ { if (opened[np]) np++; opened[np] = 1; q[np] = value($0) }
    /^result:/ && !(np in r) { r[np] = value($0) }
    { text[np] = text[np] $0 "\n" }
    END {
      for (i = 1; i <= np; i++)
        if (opened[i] && (q[i] in keyed)) {
          f = ENVIRON["PD"] "/pass" i
          printf "%s", text[i] > f; close(f)
          printf "%d %d %d %s\n", i, any(ENVIRON["KT"], text[i]), any(ENVIRON["KN"], text[i]), r[i]
        }
    }' "$rec")"
  while IFS=' ' read -r i t n r; do
    [ -n "$t" ] || continue
    scored=1
    why="$(exam_declared "$key" "$pd/pass$i")" || { verdict="missed: $why"; break; }
    exam_meets "$kr" "$r" && [ "$t" = 1 ] && [ "$n" = 1 ] || { verdict="missed"; break; }
  done <<EOF
$passes
EOF
  rm -rf "$pd"
  [ -z "$verdict" ] || { echo "$verdict"; return 1; }
  [ "$scored" = 1 ] || { echo "missed"; return 1; }
  if [ "$decl" = 1 ]; then echo "met: declared"; else echo "met"; fi
}
