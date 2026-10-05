#!/usr/bin/perl
# tests/fixtures/name-scan-oracle.pl <list> <case dir> — the reference matcher for the name scan
# (wave-27 T65), written from THE RULE in the plan's `### T65` and from nothing in
# tests/lib/name-scan.sh. Slow on purpose: it walks the text and, at every place the next word
# could start, tries every reading of the gap.
#
# <list> holds one entry per line, named by its line number. Every file in <case dir> is a text.
# For each text and each entry the rule finds, one line: `<file> entry=<n> line=<l>`, where <l> is
# the line the leftmost match starts on (the newlines before it, plus one). Nothing else is printed.
#
# THE RULE, as this file reads it. An entry is its words (split at white space). The text holds
# the entry where each word occurs literally, in order, and between two consecutive words lies a
# GAP. A gap matches when it is EITHER one or more horizontal white-space characters, OR it splits
# as `side` `break` `side`: `break` is exactly one line break (LF, CR LF, CR, VT, FF, NEL, LS,
# PS), and each side is a sequence of ITEMS, each one of: a horizontal white-space character
# (free); a SYMBOL, one character that is neither a letter, a digit nor white space (at most 24
# per side); a TAG, `<` then at most 200 characters none of which is `<`, `>` or a line break,
# then `>` (at most three per side). The reading is existential: the gap matches when ANY reading
# of it fits the bounds. A word's own symbols are the word's: the gap is exactly the text between
# the end of one word and the start of the next.
#
# What this file takes from the scan, and nothing else: the fold (perl's fc after decoding the
# bytes as UTF-8, a malformed byte becoming U+FFFD), and what a letter (\p{L}), a digit (\p{Nd}),
# white space (\s) and horizontal white space (\h) are. Those are definitions the rule names and
# the scan states; an oracle that folded differently would test the fold, not the wrap.
use strict;
use warnings;
use feature "fc";
use Encode ();

my ($listf, $dir) = @ARGV;
die "usage: name-scan-oracle.pl <list> <case dir>\n" unless defined $dir && -d $dir;

sub fold { fc(Encode::decode("UTF-8", $_[0])) }

sub slurp {
  my ($f) = @_;
  open(my $h, "<:raw", $f) or die "cannot read $f\n";
  local $/;
  my $d = <$h>;
  close $h;
  return defined $d ? $d : "";
}

# the line breaks the rule names, each one break
my %BREAK = map { $_ => 1 } ("\n", "\r\n", "\r", "\x0B", "\x0C", "\x{85}", "\x{2028}", "\x{2029}");

sub is_h { $_[0] =~ /\h/ }
sub is_symbol { $_[0] !~ /\p{L}/ && $_[0] !~ /\p{Nd}/ && $_[0] !~ /\s/ }
# a character a tag's body may not hold: `<`, `>`, or one that is a line break on its own
sub not_in_tag { $_[0] eq "<" || $_[0] eq ">" || $BREAK{$_[0]} }

# side_ok <side> — can the side be read as items with at most 24 symbols and 3 tags?
sub side_ok {
  my ($s) = @_;
  my %memo;
  return reads($s, 0, 0, 0, \%memo);
}

# reads <side> <at> <symbols so far> <tags so far> — does some reading of the rest fit?
sub reads {
  my ($s, $i, $syms, $tags, $memo) = @_;
  return 0 if $syms > 24 || $tags > 3;
  return 1 if $i == length $s;
  my $key = "$i $syms $tags";
  return $memo->{$key} if exists $memo->{$key};
  my $c = substr($s, $i, 1);
  my $ok = 0;
  # the character is horizontal white space: free
  $ok = 1 if is_h($c) && reads($s, $i + 1, $syms, $tags, $memo);
  # the character is a symbol
  $ok = 1 if !$ok && is_symbol($c) && reads($s, $i + 1, $syms + 1, $tags, $memo);
  # the character opens a tag: try every place its `>` could be
  if (!$ok && $c eq "<") {
    for my $j ($i + 1 .. length($s) - 1) {
      last if $j - $i - 1 > 200;
      my $d = substr($s, $j, 1);
      if ($d eq ">" && reads($s, $j + 1, $syms, $tags + 1, $memo)) { $ok = 1; last }
      # a body never holds this character, so no later `>` can close this tag
      last if not_in_tag($d);
    }
  }
  return $memo->{$key} = $ok;
}

# gap_ok <gap> — does the gap match, under any reading?
sub gap_ok {
  my ($g) = @_;
  return 0 if $g eq "";
  my $all_h = 1;
  for my $c (split //, $g) { $all_h = 0 unless is_h($c) }
  return 1 if $all_h;
  # side, break, side: every place the break could be, as one character or as CR LF
  for my $i (0 .. length($g) - 1) {
    for my $len (1, 2) {
      next if $i + $len > length $g;
      next unless $BREAK{substr($g, $i, $len)};
      return 1 if side_ok(substr($g, 0, $i)) && side_ok(substr($g, $i + $len));
    }
  }
  return 0;
}

# from <text> <at> <word index> <words> — do the words from this one on start at <at>?
sub from {
  my ($t, $at, $k, $w) = @_;
  return 0 unless substr($t, $at, length $w->[$k]) eq $w->[$k];
  return 1 if $k == $#$w;
  my $end = $at + length $w->[$k];
  # every place the next word occurs after this one: the gap is what lies between
  my $q = index($t, $w->[$k + 1], $end + 1);
  while ($q >= 0) {
    return 1 if gap_ok(substr($t, $end, $q - $end)) && from($t, $q, $k + 1, $w);
    $q = index($t, $w->[$k + 1], $q + 1);
  }
  return 0;
}

# first <text> <words> — where the leftmost match starts, or -1
sub first {
  my ($t, $w) = @_;
  my $p = index($t, $w->[0]);
  while ($p >= 0) {
    return $p if from($t, $p, 0, $w);
    $p = index($t, $w->[0], $p + 1);
  }
  return -1;
}

my (@num, @words);
my $n = 0;
for my $line (split /\n/, slurp($listf)) {
  $n++;
  next if $line eq "";
  push @num, $n;
  push @words, [split /\s+/, fold($line)];
}

opendir(my $dh, $dir) or die "cannot read $dir\n";
for my $f (sort grep { !/^\./ } readdir $dh) {
  my $t = fold(slurp("$dir/$f"));
  for my $i (0 .. $#num) {
    my $p = first($t, $words[$i]);
    next if $p < 0;
    my $line = 1 + (substr($t, 0, $p) =~ tr/\n//);
    print "$f entry=$num[$i] line=$line\n";
  }
}
