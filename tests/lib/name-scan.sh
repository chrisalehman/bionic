#!/bin/bash
set +x +v
# tests/lib/name-scan.sh <list path> — this project's release-time name scan (wave-27 D13, as
# amended at A-orch-81).
#
# <list path> is a private list, one entry per line, kept OUTSIDE every git checkout (a list in
# a checkout would itself ship). Blank lines and lines starting with `#` are skipped but still
# counted, so an entry is named by its line number in the list. Each line is read as the scan
# will use it: a leading byte-order mark is removed, every white space character perl's \s
# knows (a space, a tab, a carriage return, a Unicode space) is stripped at both ends, and a
# line empty after that is skipped (counted, not an entry). Entries are fixed strings, matched
# case-insensitively: both sides are decoded as UTF-8 (a malformed byte becomes U+FFFD) and Unicode case-folded, whatever the
# caller's locale. The one exception is an entry's own white space (A-orch-91, A-orch-106,
# A-orch-115): between two of its words lies a GAP, and a gap matches when it is EITHER
# horizontal white space on one line (spaces, tabs, the Unicode spaces) OR a side, exactly ONE
# line break (LF, CR LF, CR, VT, FF, NEL, LS or PS), a side. A side is any mix of horizontal
# white space, at most 24 symbols (a character that is neither a letter, a digit nor white space:
# quotes, a backslash, `+`, `#`, `/`, `*`, `>`, `-`, `;`, brackets and the rest) and at most
# three markup tags (`<`, at most 200 characters with no `<`, `>` or line break, `>`), read ANY
# way that fits: a `<` may be a symbol or open a tag. The gap is exactly what lies between the
# two words, so a word's own symbols (`(word`, `c++`) belong to the word and never count against
# a side. So a name of two words is found where prose, a comment, a commit body, a string
# continued on the next line, a quoted patch line or markup wraps between them. White space is
# never optional (the words run together are another entry), a blank line between the words is
# no wrap, and symbols between two words on ONE line are no match. The scan runs in the
# checkout it is started from.
#
# WHAT IT READS is what a push of <base>..<head> would publish, never the working files:
#   - every blob in the tree at the head, as bytes (a binary file, a file marked `-diff` or
#     `binary`, and a symlink, whose blob is its target text), and every path name there;
#   - every object the range introduces: each blob (a file added and deleted inside the range
#     among them) and each path name a commit adds, changes or deletes;
#   - each commit in the range: its message, and its author's and committer's name and email;
#   - every tag that points at a commit in the range or at the head: its name, and for an
#     annotated tag its message and its tagger, and those of every tag object a nested tag
#     passes through on its way to the commit.
# Objects are read as a push sends them: GIT_NO_REPLACE_OBJECTS is set, so a commit or a blob
# "fixed" locally by `git replace` is read as the original.
# BIONIC_CHECK_BASE and BIONIC_CHECK_HEAD pick the range; the head defaults to HEAD and the
# base to the newest tag reachable from the head that does not point at the head itself, so a
# release already tagged is scanned as <previous tag>..<head> (no such tag: the whole history).
# NOTHING IS SKIPPED: an object the scan cannot read refuses the run (exit 2).
#
# ONE PASS. Everything above is read once, by one matcher (MATCHER, a program for the perl the
# PATH names, which the power check proves able: macOS awk ends a string at a NUL byte and stops
# on a malformed UTF-8 one, and BSD grep misses a folded match after a NUL). A record is tested
# against every entry at once, by a pattern that admits every gap the rule admits and a few it
# does not; only a record that passes is searched entry by entry, in the same folded text, and
# there each place is held to the rule exactly before it is a hit. tests/name-scan.test.sh
# holds the scan to a reference matcher written from the rule alone, over 5,000 generated cases.
#
# WHAT IS STILL MISSED: text not in UTF-8, in file contents as in messages (a UTF-16 file, a
# Latin-1 non-ASCII name, a commit with another `encoding`), compressed or otherwise encoded
# text, an NFD form of an NFC entry, `mergetag` and `gpgsig` headers, notes and branch names,
# and a name broken deliberately (inside a word, by a zero-width character). At a wrap: a blank
# line or any two breaks (a paragraph, a git subject and its body, LF then CR), a hyphen
# breaking a word, a side that no reading fits into 24 symbols and three tags, a tag of more
# than 200 characters or one that spans a line break, a letter or a digit outside a tag (`rem`,
# a JSON `\n` escape, `&nbsp;`), and symbols with no line break (`mxv9, plover` on one line).
#
# A CLEAN RESULT MUST HAVE POWER. Before the real scan, the same function runs over a
# throwaway repository built with git's plumbing, which holds every entry at every site the
# scan reads: a text blob (in upper case), a binary blob, a symlink target and a path name at
# the head, and five text blobs holding each entry wrapped, one per branch of the construction
# (each run of white space inside it a tab, CR LF and blanks; symbols around a line break; a
# tag on each side of one; a break then a `<` that is a symbol, a `>` later on the line; four
# tags of symbols alone, read as three tags and three symbols); a path and a blob (in lower
# case) that exist only
# inside the range; a commit message; an author name, an author email, a committer name and a
# committer email; a tag name and a tag message. An entry not found at any of them refuses the
# run (exit 2). An entry git cannot hold at a site is not planted there: one with a byte no ref
# name may hold (a space, `~^:?*[\`, a control byte, `..`, `@{`, `//`, `/.`, `./`, `.lock/`)
# at the tag name, and one holding `<` or `>` at the four people sites; such a site cannot
# publish that entry either.
#
# NO ENTRY IS EVER PRINTED OR WRITTEN, and none is a word of any command line or a variable
# of any child's environment: entries reach the matcher and git by file descriptor or stdin,
# written by the builtin printf. A hit is `HIT entry=<line number> at <where>`, and <where> is
# numbers and object ids alone, never text from the repository:
#   blob <sha12> line <n>     <n> is the count of newlines before the match plus one (the line
#                             the match starts on), in a binary blob as in a text one
#   path #<n>                 the path's 1-based position in `git ls-tree -r --name-only` order
#                             at the head
#   path in commit <sha12>    a path only the range holds, at the first commit that names it
#   commit <sha12> message | author | committer
#   tag <sha12>               the tag object, or the commit a lightweight tag names
# Records are split on NUL or by length, never on a byte a path or a message can hold. The
# first command turns tracing off; BASH_ENV and ENV are unset so nothing this starts reads
# them, every git trace variable is unset as a second line of defence, and so are the perl
# variables that would load a debugger or a module into the matcher. The throwaway
# lives in a temp directory removed on exit; HUP, INT and TERM end the run once the command then
# running has finished, so no child writes into the tree after it is removed, and the removal
# ignores the three, so a signal to the whole process group cannot stop it half done. Exit 0 clean (an empty list prints `entries=0`),
# 1 a hit, 2 a refusal.
#
# bash 3.2 (ADR-001) and the perl macOS ships. Not part of the shipped plugin.
unset BASH_ENV ENV
set -u -o pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_CEILING_DIRECTORIES GIT_DISCOVERY_ACROSS_FILESYSTEM \
  GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_NAMESPACE
# second line of defence: no entry is in any argv, but a trace file the caller's environment names
# would still record what git does see (a ref name the power check plants, for one)
for v in $(compgen -e); do case "$v" in GIT_TRACE*) unset "$v" ;; esac; done
# a caller's perl debugger or module path would run inside the matcher, which holds every entry
unset PERL5OPT PERL5LIB PERLLIB PERL5DB PERLDB_OPTS
# read what a push sends: a push never sends a local `git replace` of an object
export GIT_NO_REPLACE_OBJECTS=1
export LC_ALL=C

# stop is the status a caught HUP, INT or TERM leaves; the run ends at the next checkpoint, after
# the command running then (and every child it started) has finished
stop=""
checkpoint() { [ -z "$stop" ] || exit "$stop"; }
refuse() { checkpoint; echo "name-scan: $*" >&2; exit 2; }

# ---- the matcher ------------------------------------------------------------------------------
#
# perl -e "$MATCHER" <list fd> <head paths> <range log> <tags> <object count>, objects on stdin
# from `git cat-file --batch`. The list fd holds `<line number>\0<entry>\0` pairs. Prints one
# HIT line per entry per place; exit 0 none, 1 found, 2 something could not be read whole.
MATCHER='
use strict; use feature "fc"; use Encode ();
$SIG{__WARN__} = sub { print STDERR "name-scan: the matcher warned\n" };
$SIG{__DIE__} = sub { return if $^S; print STDERR "name-scan: the matcher failed\n"; exit 2 };
sub bail { print STDERR "name-scan: $_[0]\n"; exit 2 }
sub slurp {
  open(my $h, "<:raw", $_[0]) or bail("cannot read $_[1]");
  local $/; my $d = <$h>; close($h) or bail("cannot read $_[1]");
  defined $d ? $d : "";
}
sub fold { fc(Encode::decode("UTF-8", $_[0])) }
my ($listf, $pathsf, $logf, $tagsf, $want) = @ARGV;
my @kv = split /\0/, slurp($listf, "the list");
# an entry is its words, each literal. Between two of them lies a GAP, matched by THE RULE (plan
# T65): EITHER horizontal white space on one line, OR a side, exactly one line break (anything \R
# takes as one: LF, CR LF, CR, VT, FF, NEL, LS, PS), a side. A side is items: horizontal white
# space (free), at most 24 symbols (a character that is neither a letter, a digit nor white space)
# and at most three tags (`<`, at most 200 characters with no `<`, `>` or line break, `>`), read
# ANY way that fits: a `<` may be a symbol or open a tag. The gap is exactly the text between the
# two words as matched, so the symbols of a word belong to it and never count against a side.
#
# side_ok <side>: does some reading fit? Each `<` that opens a tag (its next `>` comes first, within
# 200 characters, on its line) is that tag or two or more symbols; a tag holding a letter or a digit
# can only be a tag; of the rest, those with the most symbols are read as tags while the side has
# tags to spare, and every other character must be white space or a symbol.
sub side_ok {
  my ($s) = @_;
  my ($syms, $need, @w) = (0, 0);
  pos($s) = 0;
  while (pos($s) < length $s) {
    next if $s =~ /\G\h+/gc;
    if ($s =~ /\G(<[^<>\v]{0,200}>)/gc) {
      my $t = $1;
      if ($t =~ /[\p{L}\p{Nd}]/) { $need++ } else { push @w, scalar(() = $t =~ /[^\p{L}\p{Nd}\s]/g) }
      next;
    }
    next if $s =~ /\G[^\p{L}\p{Nd}\s]/gc && ++$syms;
    return 0;
  }
  return 0 if $need > 3;
  @w = sort { $b <=> $a } @w;
  splice(@w, 0, 3 - $need);
  $syms += $_ for @w;
  return $syms <= 24;
}
# gap_ok <gap> (a copy: $^N is reset by the first match in here)
sub gap_ok {
  my ($g) = @_;
  return 1 if $g !~ /\v/;
  my ($l, $r) = $g =~ /^(\V*)\R(\V*)\z/ or return 0;
  return side_ok($l) && side_ok($r);
}
# $gap finds where a gap can END, never more than the bounds of the rule allow: read with every tag
# it can hold, a side is at most 27 items (a tag read as symbols is two or more of them), so the
# side before the break is walked once, tag first, and kept; the side after it may end after any
# of its first 27 items, or inside a tag it opens (`mxv9` break `<plover x>`: that `<` is a
# symbol). It is a superset of the rule; side_ok then decides, once the next word has matched.
my $tag = qr{<[^<>\v]{0,200}+>};
my $sym = qr{[^\p{L}\p{Nd}\s]};
my $item = qr{(?:$tag|$sym)};
my $inside = qr{(?:<(?:\h++|[^\p{L}\p{Nd}\s<>]){0,47}?)?};
my $before = qr{(?:\h*+$item){0,27}+\h*+};
my $after = qr{(?:\h*+(?>$item)){0,27}?\h*+$inside};
my $wrap = qr{$before\R$after};
my $gap = qr{(?:\h++|$wrap)};
# three patterns per entry. @fs, the superset, finds where a match may start, from the same
# string as the batch pattern; @fl, white space on one line only, is exact and runs no code; @fe
# is exact, checking each gap after its next word. The batch pattern is the superset of every
# entry at once, written with $gap ONCE as the named
# group `ws`: written into each gap, 500 entries made a pattern of 580 KB that the engine could no
# longer search by its first words (13 s on 2 MB of text, against 0.01). Only an anchored pattern
# runs the check: a code block in a pattern that also searches costs at every place it tries.
my (@num, @fp, @fs, @fl, @fe);
while (@kv) {
  push @num, shift @kv;
  my @w = split /\s+/, fold(shift @kv);
  push @fp, join "(?&ws)", map { quotemeta } @w;
  my ($l, $e) = (qr/\Q$w[0]\E/) x 2;
  for my $x (@w[1 .. $#w]) {
    $l = qr/$l\h++\Q$x\E/;
    $e = qr/$e($gap)\Q$x\E(?(?{ gap_ok($^N) })|(*FAIL))/;
  }
  push @fs, qr/\G(.*?)(?=$fp[-1])(?(DEFINE)(?<ws>$gap))/s; push @fl, qr/\G($l)/; push @fe, qr/\G($e)/;
}
my $any = join "|", @fp;
$any = qr/(?:$any)(?(DEFINE)(?<ws>$gap))/;
my ($hits, %seen) = (0);
sub hit { return if $seen{"$_[0] $_[1]"}++; print "HIT entry=$_[0] at $_[1]\n"; $hits++ }
# look <bytes> <where> <lines>: all entries at once first; the entry and line only after a find.
# Each place the superset finds is tried by the exact patterns, anchored; a place they refuse is
# stepped over by one character. A line is counted on from the previous place, over the text
# between, never from an offset: an offset into decoded text is found by walking from its start,
# which made many matches in one blob cost their square.
sub look {
  my ($t, $where, $lines) = (fold($_[0]), $_[1], $_[2]);
  return unless $t =~ $any;
  for my $i (0 .. $#fe) {
    my $line = 1;
    pos($t) = undef;
    while ($t =~ /$fs[$i]/gc) {
      $line += ($1 =~ tr/\n//);
      if ($t =~ /$fl[$i]/gc || $t =~ /$fe[$i]/gc) {
        hit($num[$i], $lines ? "$where line $line" : $where);
        last unless $lines;
        $line += ($1 =~ tr/\n//);
      } else {
        $t =~ /\G(.)/gcs;
        $line++ if $1 eq "\n";
      }
    }
  }
}
# split an object at its first blank line: header, body
sub parts { my $k = index($_[0], "\n\n"); $k < 0 ? ($_[0], "") : (substr($_[0], 0, $k), substr($_[0], $k + 2)) }

my %path;
my $n = 0;
for my $p (split /\0/, slurp($pathsf, "the path list")) {
  $n++; $path{$p} = 1;
  look($p, "path #$n", 0);
}

my @t = split /\0/, slurp($logf, "the range path list");
my ($c, $i) = ("", 0);
while ($i < @t) {
  my $tok = $t[$i++];
  $tok =~ s/^\n//;
  if ($tok =~ /^[0-9a-f]{40}(?:[0-9a-f]{24})?$/) { $c = substr($tok, 0, 12); next }
  bail("the range path list cannot be parsed")
    unless $c ne "" && $i < @t && $tok =~ /^:[0-7]+ [0-7]+ [0-9a-f]+ [0-9a-f]+ [ADMTUX]$/;
  my $p = $t[$i++];
  next if $path{$p}++;
  look($p, "path in commit $c", 0);
}

for my $l (split /\n/, slurp($tagsf, "the tag list")) {
  my ($sha, $type, $ref) = split / /, $l, 3;
  bail("the tag list cannot be parsed") unless defined $ref && $ref =~ s{^refs/tags/}{};
  my $s = substr($sha, 0, 12);
  look($ref, "tag $s", 0);
}

binmode STDIN;
my $got = 0;
while (defined(my $h = <STDIN>)) {
  chomp $h;
  if ($h !~ /^([0-9a-f]{40}(?:[0-9a-f]{24})?) (blob|commit|tag|tree) ([0-9]+)$/) {
    bail($h =~ /^([0-9a-f]{12})[0-9a-f]{28}(?:[0-9a-f]{24})? missing$/ ? "object $1 cannot be read" : "an object cannot be read");
  }
  my ($sha, $type, $size) = (substr($1, 0, 12), $2, $3);
  my $d = "";
  my $r = $size ? read(STDIN, $d, $size) : 0;
  bail("object $sha cannot be read whole") unless defined $r && $r == $size;
  my $nl = "";
  bail("object $sha cannot be read whole") unless read(STDIN, $nl, 1) == 1 && $nl eq "\n";
  $got++;
  if ($type eq "blob") { look($d, "blob $sha", 1); }
  elsif ($type eq "commit") {
    my ($hd, $msg) = parts($d);
    look($msg, "commit $sha message", 0);
    for my $l (split /\n/, $hd) {
      next unless $l =~ /^(author|committer) (.*)$/;
      my ($who, $v) = ($1, $2);
      if ($v =~ /^(.*) <([^<>]*)> [0-9]+ [-+][0-9]{4}$/) {
        my ($name, $mail) = ($1, $2);
        look($name, "commit $sha $who", 0);
        look($mail, "commit $sha $who", 0);
      } else { look($v, "commit $sha $who", 0) }
    }
  }
  elsif ($type eq "tag") {
    my ($hd, $msg) = parts($d);
    look($msg, "tag $sha", 0);
    for my $l (split /\n/, $hd) {
      if ($l =~ /^tag (.*)$/) { my $v = $1; look($v, "tag $sha", 0) }
      elsif ($l =~ /^tagger (.*)$/) {
        my $v = $1;
        if ($v =~ /^(.*) <([^<>]*)> [0-9]+ [-+][0-9]{4}$/) { my ($tn, $tm) = ($1, $2); look($tn, "tag $sha", 0); look($tm, "tag $sha", 0) }
        else { look($v, "tag $sha", 0) }
      }
    }
  }
}
bail("read $got of $want objects") unless $got == $want;
exit($hits ? 1 : 0);
'

# entries_stream — `<line number>\0<entry>\0` for every entry, by the builtin printf
entries_stream() {
  local i=0
  while [ "$i" -lt "${#ENTRIES[@]}" ]; do printf '%s\0%s\0' "${NUMS[$i]}" "${ENTRIES[$i]}"; i=$((i + 1)); done
}

# ---- the one scan: everything a push of <base>..<head> publishes, in one matcher pass --------
#
# scan_repo <repo> <base sha or ""> <head sha> <work dir> — prints the HIT lines; exit 0 none,
# 1 found, 2 a refusal (the matcher says what it could not read). The work dir holds only what
# git printed (ids, paths, ref names), never an entry.
scan_repo() {
  local repo="$1" base="$2" head="$3" w="$4" n
  mkdir -p "$w" || return 2
  git -C "$repo" ls-tree -r -z --name-only "$head" 2>/dev/null > "$w/paths" || return 2
  # every path a range commit adds, changes or deletes, oldest commit first, merges against
  # each parent; `-z --raw` gives `<sha>\0` then `:<modes ids status>\0<path>\0` pairs
  git -C "$repo" -c log.showSignature=false log -z --raw --no-abbrev --no-color --format=%H \
    --diff-merges=separate --root --no-renames --reverse "$head" ${base:+"^$base"} -- 2>/dev/null > "$w/log" || return 2
  git -C "$repo" rev-list "$head" ${base:+"^$base"} 2>/dev/null > "$w/range" || return 2
  { cat "$w/range" && printf '%s\n' "$head"; } > "$w/commits" || return 2
  # every tag that points at a commit in the range or at the head: `<sha> <type> <ref>`; a ref
  # name holds no space or newline (git check-ref-format)
  git -C "$repo" for-each-ref --format='%(objecttype) %(objectname) %(refname) %(*objectname)' refs/tags \
    2>/dev/null > "$w/refs" || return 2
  awk 'FILENAME == ARGV[1] { c[$1] = 1; next }
       { p = ($1 == "tag") ? $4 : $2; if (p in c) print $2, $1, $3 }' "$w/commits" "$w/refs" > "$w/tags" || return 2
  # the objects: every blob at the head, every commit and blob the range introduces (the type
  # filter drops every commit but the tip, so the commits come from the range list), every tag
  # object in the tag list and every tag object a nested one names on its way to the commit
  # (rev-list lists each tag of the chain; every commit it reaches is the head's, so `--not`
  # the head leaves the tags alone)
  { git -C "$repo" ls-tree -r --format='%(objectmode) %(objecttype) %(objectname)' "$head" 2>/dev/null \
      | awk '$2 == "blob" { print $3 }' &&
    git -C "$repo" rev-list --objects --no-object-names --filter=object:type=blob "$head" ${base:+"^$base"} 2>/dev/null &&
    cat "$w/range" &&
    { awk '$2 == "tag" { print $1 }' "$w/tags" && printf -- '--not\n%s\n' "$head"; } \
      | git -C "$repo" rev-list --objects --no-object-names --stdin 2>/dev/null; } \
    | sort -u > "$w/objects" || return 2
  n="$(wc -l < "$w/objects" | tr -d ' ')"
  git -C "$repo" cat-file --batch --buffer < "$w/objects" 2>/dev/null \
    | perl -e "$MATCHER" <(entries_stream) "$w/paths" "$w/log" "$w/tags" "$n"
  set -- "${PIPESTATUS[@]}"
  [ "$1" -eq 0 ] || return 2
  return "$2"
}

# ---- the throwaway: every entry at every site, built with git's plumbing ---------------------

# pg <args> — git on the throwaway, with no hook to run
pg() { git -C "$PW" -c core.hooksPath=/dev/null "$@" 2>/dev/null; }
# pg_commit <tree> <parent or ""> <author name> <author email> <committer name> <committer email>
# <message> — writes a commit object from stdin (builtin printf); prints its id
pg_commit() {
  { printf 'tree %s\n' "$1"; [ -z "$2" ] || printf 'parent %s\n' "$2"
    printf 'author %s <%s> 0 +0000\ncommitter %s <%s> 0 +0000\n\n%s\n' "$3" "$4" "$5" "$6" "$7"
  } | pg hash-object -t commit -w --stdin
}
# ref_ok <entry> — can a tag name hold this entry? (git check-ref-format, inside `tn<n>-...-tn`)
ref_ok() {
  case "$1" in
    *[[:cntrl:]' ~^:?*[\']*|*..*|*'@{'*|*//*|*/.*|*./*|*.lock/*) return 1 ;;
  esac
  return 0
}
# ident_ok <entry> — can a name or an email hold it? (git refuses `<` and `>` there)
ident_ok() { case "$1" in *[\<\>]*) return 1 ;; esac; return 0; }

# wrapped_entries <title> <break> [<after>] — <title> and each entry on its own line, every run of
# blanks inside it made <break> and <after> after it: a scan that lost the branch of the
# construction <break> needs would miss it (the builtin printf; no entry is a word of any command)
wrapped_entries() {
  local i=0 e sp=' ' br="$2"
  printf '%s\n' "$1"
  while [ "$i" -lt "${#ENTRIES[@]}" ]; do
    e="${ENTRIES[$i]//$'\t'/$sp}"
    while :; do case "$e" in *"$sp$sp"*) e="${e//$sp$sp/$sp}" ;; *) break ;; esac; done
    printf '%s%s\n' "${e//$sp/$br}" "${3:-}"; i=$((i + 1))
  done
}

prove_power() {
  local w="$1" i e n tab empty b_text b_wrap b_wsym b_wtag b_wang b_wsta b_bin b_link b_gone tree0 tree1 c0 c1 c2 c3 c4 c5
  local t26='<------------------------>'
  local tg people msg miss rc
  PW="$w/power.git"
  mkdir -p "$w" && git init -q --bare --template= "$PW" >/dev/null 2>&1 \
    || refuse "cannot build the power check under ${TMPDIR:-/tmp}"
  # the blobs: text in upper case, binary, a symlink target, and (range only) lower case
  empty="$(pg hash-object -w --stdin < /dev/null)" &&
  b_text="$( { printf 'power text\n'; printf '%s\n' "${ENTRIES[@]}" | tr '[:lower:]' '[:upper:]'; } \
    | pg hash-object -w --stdin)" &&
  # one wrapped plant per branch of the construction: white space only, symbols, tags
  b_wrap="$(wrapped_entries 'power wrap' $'\t\r\n  ' | pg hash-object -w --stdin)" &&
  b_wsym="$(wrapped_entries 'power wrap symbols' $' " \\\n +# "' | pg hash-object -w --stdin)" &&
  b_wtag="$(wrapped_entries 'power wrap tags' $'</t>\n<t x="1">' | pg hash-object -w --stdin)" &&
  # a `<` after the break that is a symbol, though a `>` closes a tag from it later on the line
  b_wang="$(wrapped_entries 'power wrap angle' $'\n<' ' z>' | pg hash-object -w --stdin)" &&
  # four tags of symbols alone before the break: the three with the most symbols are the tags
  b_wsta="$(wrapped_entries 'power wrap symbol tags' "<->$t26$t26$t26"$'\n' | pg hash-object -w --stdin)" &&
  b_bin="$( { printf 'power\0binary\0'; printf '%s\0' "${ENTRIES[@]}"; } | pg hash-object -w --stdin)" &&
  b_link="$(printf '../%s\n' "${ENTRIES[@]}" | pg hash-object -w --stdin)" &&
  b_gone="$( { printf 'power gone\n'; printf '%s\n' "${ENTRIES[@]}" | tr '[:upper:]' '[:lower:]'; } \
    | pg hash-object -w --stdin)" || refuse "cannot build the power check"
  # the base tree holds the head's plants, so only the head's tree reaches them: a path per entry
  { printf '100644 %s\t%s\0' "$b_text" power/text.txt
    printf '100644 %s\t%s\0' "$b_wrap" power/wrap.txt
    printf '100644 %s\t%s\0' "$b_wsym" power/wrap-symbols.txt
    printf '100644 %s\t%s\0' "$b_wtag" power/wrap-tags.txt
    printf '100644 %s\t%s\0' "$b_wang" power/wrap-angle.txt
    printf '100644 %s\t%s\0' "$b_wsta" power/wrap-symbol-tags.txt
    printf '100644 %s\t%s\0' "$b_bin" power/data.bin
    printf '120000 %s\t%s\0' "$b_link" power/link
    i=0
    while [ "$i" -lt "${#ENTRIES[@]}" ]; do
      printf '100644 %s\t%s\0' "$empty" "pn${NUMS[$i]}-${ENTRIES[$i]}-pn"; i=$((i + 1))
    done
  } | GIT_INDEX_FILE="$w/index" pg update-index -z --index-info >/dev/null 2>&1 &&
  tree0="$(GIT_INDEX_FILE="$w/index" pg write-tree)" || refuse "cannot build the power check"
  # the range's first commit adds a blob and a path per entry that the next one removes
  { printf '100644 %s\t%s\0' "$b_gone" power/gone.txt
    i=0
    while [ "$i" -lt "${#ENTRIES[@]}" ]; do
      printf '100644 %s\t%s\0' "$empty" "rg${NUMS[$i]}-${ENTRIES[$i]}-rg"; i=$((i + 1))
    done
  } | GIT_INDEX_FILE="$w/index" pg update-index -z --index-info >/dev/null 2>&1 &&
  tree1="$(GIT_INDEX_FILE="$w/index" pg write-tree)" || refuse "cannot build the power check"
  people="power"; i=0
  while [ "$i" -lt "${#ENTRIES[@]}" ]; do
    ident_ok "${ENTRIES[$i]}" && people="$people|${ENTRIES[$i]}"; i=$((i + 1))
  done
  people="$people|power"
  msg="$(printf 'power message\n\n'; printf '%s\n' "${ENTRIES[@]}")"
  c0="$(pg_commit "$tree0" "" power power@example.invalid power power@example.invalid "power base")" &&
  c1="$(pg_commit "$tree1" "$c0" power power@example.invalid power power@example.invalid "$msg")" &&
  c2="$(pg_commit "$tree0" "$c1" "$people" power@example.invalid power power@example.invalid "power")" &&
  c3="$(pg_commit "$tree0" "$c2" power "$people" power power@example.invalid "power")" &&
  c4="$(pg_commit "$tree0" "$c3" power power@example.invalid "$people" power@example.invalid "power")" &&
  c5="$(pg_commit "$tree0" "$c4" power power@example.invalid power "$people" "power")" &&
  tg="$( { printf 'object %s\ntype commit\ntag power-tag\ntagger power <power@example.invalid> 0 +0000\n\npower tag\n' "$c1"
           printf '%s\n' "${ENTRIES[@]}"; } | pg hash-object -t tag -w --stdin)" \
    || refuse "cannot build the power check"
  # a tag named after each entry on a commit inside the range (not the head), and the annotated tag
  { printf 'create refs/tags/power-tag\0%s\0' "$tg"
    i=0
    while [ "$i" -lt "${#ENTRIES[@]}" ]; do
      ref_ok "${ENTRIES[$i]}" && printf 'create refs/tags/tn%s-%s-tn\0%s\0' "${NUMS[$i]}" "${ENTRIES[$i]}" "$c3"
      i=$((i + 1))
    done
  } | pg update-ref -z --stdin >/dev/null 2>&1 || refuse "cannot build the power check: git refused a tag name"

  # the same scan, over the range c0..c5
  scan_repo "$PW" "$c0" "$c5" "$w/run" > "$w/found"; rc=$?
  [ "$rc" -le 1 ] || refuse "the power check cannot read its own throwaway; the scan has no power"

  # what it must have found: `entry=<n> at <where>` and the site's name, numbers and ids only
  i=0
  while [ "$i" -lt "${#ENTRIES[@]}" ]; do
    e="${ENTRIES[$i]}"; n="${NUMS[$i]}"
    printf 'entry=%s at blob %.12s\ttext blob\n' "$n" "$b_text"
    printf 'entry=%s at blob %.12s\twrapped text\n' "$n" "$b_wrap"
    printf 'entry=%s at blob %.12s\tsymbol-wrapped text\n' "$n" "$b_wsym"
    printf 'entry=%s at blob %.12s\ttag-wrapped text\n' "$n" "$b_wtag"
    printf 'entry=%s at blob %.12s\tangle-wrapped text\n' "$n" "$b_wang"
    printf 'entry=%s at blob %.12s\tsymbol-tag-wrapped text\n' "$n" "$b_wsta"
    printf 'entry=%s at blob %.12s\tbinary blob\n' "$n" "$b_bin"
    printf 'entry=%s at blob %.12s\tsymlink target\n' "$n" "$b_link"
    printf 'entry=%s at path #\tpath name\n' "$n"
    printf 'entry=%s at path in commit %.12s\trange-only path\n' "$n" "$c1"
    printf 'entry=%s at blob %.12s\trange-only blob\n' "$n" "$b_gone"
    printf 'entry=%s at commit %.12s message\tmessage\n' "$n" "$c1"
    if ident_ok "$e"; then
      printf 'entry=%s at commit %.12s author\tauthor name\n' "$n" "$c2"
      printf 'entry=%s at commit %.12s author\tauthor email\n' "$n" "$c3"
      printf 'entry=%s at commit %.12s committer\tcommitter name\n' "$n" "$c4"
      printf 'entry=%s at commit %.12s committer\tcommitter email\n' "$n" "$c5"
    fi
    ref_ok "$e" && printf 'entry=%s at tag %.12s\ttag name\n' "$n" "$c3"
    printf 'entry=%s at tag %.12s\ttag message\n' "$n" "$tg"
    i=$((i + 1))
  done > "$w/expected"
  sed -e 's/^HIT //' -e 's/ line [0-9]*$//' -e 's/ #[0-9]*$/ #/' "$w/found" > "$w/found-sites" \
    || refuse "cannot check the power check"
  miss="$(awk -F'\t' 'FILENAME == ARGV[1] { f[$0] = 1; next } !($1 in f) { print $1 "\t" $2; exit }' \
    "$w/found-sites" "$w/expected")" || refuse "cannot check the power check"
  [ -z "$miss" ] && return 0
  n="${miss#entry=}"; n="${n%% *}"; tab=$'\t'
  refuse "the entry on line $n of the list is not found at its ${miss##*$tab} in the throwaway; the scan has no power"
}

# ---- main ------------------------------------------------------------------------------------

LIST="${1:-}"
[ -n "$LIST" ] || refuse "usage: name-scan.sh <list path> (a list kept outside every git checkout)"
[ -f "$LIST" ] && [ -r "$LIST" ] || refuse "the list is missing or unreadable"
LISTDIR="$(cd "$(dirname "$LIST")" 2>/dev/null && pwd -P)" || refuse "the list's directory cannot be read"
if git -C "$LISTDIR" rev-parse --show-toplevel >/dev/null 2>&1 || git -C "$LISTDIR" rev-parse --git-dir >/dev/null 2>&1; then
  refuse "the list is inside a git checkout; keep it outside every checkout"
fi

# every character the matcher's \s knows, as UTF-8 bytes (LC_ALL=C here): a list line is trimmed
# of each at both ends, so no entry begins with an empty word (one that did was missed at the
# start of a text, and cost the square of a blank run's length)
SPACES=(' ' $'\t' $'\r' $'\v' $'\f' $'\302\205' $'\302\240' $'\341\232\200' $'\342\200\200'
  $'\342\200\201' $'\342\200\202' $'\342\200\203' $'\342\200\204' $'\342\200\205' $'\342\200\206'
  $'\342\200\207' $'\342\200\210' $'\342\200\211' $'\342\200\212' $'\342\200\250' $'\342\200\251'
  $'\342\200\257' $'\342\201\237' $'\343\200\200')
ENTRIES=(); NUMS=()
n=0
while IFS= read -r line || [ -n "$line" ]; do
  n=$((n + 1))
  line="${line#$'\357\273\277'}"
  while :; do
    was="$line"
    for s in "${SPACES[@]}"; do line="${line#"$s"}"; line="${line%"$s"}"; done
    [ "$line" = "$was" ] && break
  done
  case "$line" in ''|'#'*) continue ;; esac
  ENTRIES[${#ENTRIES[@]}]="$line"
  NUMS[${#NUMS[@]}]="$n"
done < "$LIST"
if [ "${#ENTRIES[@]}" -eq 0 ]; then echo "entries=0"; exit 0; fi

# the scan decides the locale: a UTF-8 one for itself, so the power check's upper-case plant
# changes the case of a non-ASCII letter too and the plant proves the matcher folds it. The
# matcher folds without a locale, so a machine with none is scanned all the same; there the
# upper-case plant proves the fold of ASCII letters only.
utf8=""
for l in C.UTF-8 en_US.UTF-8 $(locale -a 2>/dev/null | grep -i -E 'utf-?8$'); do
  [ "$(LC_ALL="$l" locale charmap 2>/dev/null)" = UTF-8 ] && { utf8="$l"; break; }
done
if [ -n "$utf8" ]; then
  export LC_ALL="$utf8"
fi

REPO="$(git rev-parse --show-toplevel 2>/dev/null)" || refuse "not run inside a git checkout"
HEAD_SHA="$(git -C "$REPO" rev-parse --verify -q "${BIONIC_CHECK_HEAD:-HEAD}^{commit}")" \
  || refuse "the head does not resolve to a commit"
if [ -n "${BIONIC_CHECK_BASE:-}" ]; then
  BASE_SHA="$(git -C "$REPO" rev-parse --verify -q "${BIONIC_CHECK_BASE}^{commit}")" \
    || refuse "the base does not resolve to a commit"
else
  # the newest tag below the head: a tag that points at the head itself is the release being cut
  EXCL=()
  for t in $(git -C "$REPO" tag --points-at "$HEAD_SHA" 2>/dev/null); do EXCL[${#EXCL[@]}]="--exclude=$t"; done
  BASE_TAG="$(git -C "$REPO" describe --tags --abbrev=0 ${EXCL[@]+"${EXCL[@]}"} "$HEAD_SHA" 2>/dev/null)" || BASE_TAG=""
  BASE_SHA=""
  [ -z "$BASE_TAG" ] || BASE_SHA="$(git -C "$REPO" rev-parse --verify -q "refs/tags/$BASE_TAG^{commit}")"
fi

# a signal never ends the run while a child can still write into the temp tree: an exit straight
# from the signal let the EXIT trap remove the tree while a `git hash-object -w` inside a command
# substitution was still running, and git made the object's directories again (T61: 5 runs in 50
# left one). The traps only record the signal; the run ends at a checkpoint. A signal sent to the
# whole process group (a Ctrl-C, a hangup) reaches every child too: the removal and `mktemp` run
# with the three ignored, which a child inherits, so neither is killed with the tree half made or
# half removed (T65: one run in fifty left a tree, and its paths name the entries).
TMP_SCAN=""
trap 'trap "" HUP INT TERM; [ -z "$TMP_SCAN" ] || rm -rf "$TMP_SCAN"' EXIT
trap 'stop=129' HUP; trap 'stop=130' INT; trap 'stop=143' TERM
TMP_SCAN="$(trap '' HUP INT TERM; mktemp -d "${TMPDIR:-/tmp}/name-scan.XXXXXX")" || refuse "cannot make a temp directory"
checkpoint

prove_power "$TMP_SCAN/power"
checkpoint

scan_repo "$REPO" "$BASE_SHA" "$HEAD_SHA" "$TMP_SCAN/scan" > "$TMP_SCAN/hits"; rc=$?
checkpoint
[ "$rc" -le 1 ] || refuse "the scan could not read everything the push would publish"
cat "$TMP_SCAN/hits"
hits="$(grep -c '^HIT ' "$TMP_SCAN/hits")"
echo "entries=${#ENTRIES[@]} hits=$hits objects=$(wc -l < "$TMP_SCAN/scan/objects" | tr -d ' ') head=$(printf '%.12s' "$HEAD_SHA") base=${BASE_SHA:-none}"
[ "$hits" -eq 0 ]
