#!/usr/bin/perl
# tests/fixtures/name-scan-gen.pl <seed> <case dir> <list> <manifest> — the generated corpus the
# name scan is held to (wave-27 T65): one file per case in <case dir> (`c00000.txt` on), the list
# of made-up entries the cases wrap in <list>, and `<case> <class>` per case in <manifest>. The
# same seed writes the same bytes. Every string is made up.
#
# The corpus is review pass 44's: the grid (0 to 26 symbols by 0 to 4 tags by three white-space
# modes by before, after or both sides of the break, over every single break the rule names),
# random sides from the whole tag pool over the eight entry kinds below, symbol runs that end in
# `<` near the bound, a word's own leading symbols near the bound, and the shapes that are never a
# match (two breaks, the words run together, symbols on one line). Whether a case is a match is
# not decided here: the oracle decides, and the scan must agree.
use strict;
use warnings;

my ($seed, $dir, $listf, $manf) = @ARGV;
die "usage: name-scan-gen.pl <seed> <case dir> <list> <manifest>\n" unless defined $manf;
srand($seed);

# the entries, one per kind: two words; three words; a word beginning with `(`; a word ending
# with `)`; a word that looks like a tag; non-ASCII with a case change; regex metacharacters; a
# word made only of symbols
my @ENTRIES = (
  ["mxv9", "plover"],
  ["zqtri", "wenlo", "daspy"],
  ["kreph", "(vandu"],
  ["glomp)", "trisk"],
  ["snarf", "<ix>"],
  ["\x{c6}rvik", "br\x{f6}nd"],
  ["zq.v+", "(1)"],
  ["zqplu", "++"],
);
my @SYMS = split //, q{"'\\+#/*>-;,()[]{}|`=:.};
my @PLAIN_TAGS = ('<t>', '</text>', '<text x="58" y="182" fill="#3a424c">', '<br/>');
# the plain tags, then: a `>` inside an attribute, a 200- and a 201-character body, the
# symbol-only shapes, `<--` with no `>`, and a bare `<`
my @TAGS = (@PLAIN_TAGS, '<a t="x>y">', '<' . ('a' x 200) . '>', '<' . ('a' x 201) . '>',
  '<->', '<!---->', '<--', '<');
my @WS = (" ", "\t", "\x{a0}", "  ");
# every single line break the rule names
my @BREAKS = ("\n", "\r\n", "\r", "\x0B", "\x0C", "\x{85}", "\x{2028}", "\x{2029}");
# never a match: two breaks
my @TWO = ("\n\n", "\r\n\r\n", "\n \n", "\r\r\n", "\n\r", "\x{2028}\n", "\x0C\x0C");

sub pick { $_[int(rand(@_))] }
sub shuffle { my @a = @_; for (my $i = @a - 1; $i > 0; $i--) { my $j = int(rand($i + 1)); @a[$i, $j] = @a[$j, $i] } @a }

# side <symbols> <tags> <mode> <tag pool> — that many of each, in a random order
sub side {
  my ($ns, $nt, $mode, $pool) = @_;
  my @items = shuffle((map { pick(@SYMS) } 1 .. $ns), (map { pick(@$pool) } 1 .. $nt));
  return join("", map { pick(@WS) . $_ } @items) . pick("", " ") if $mode eq "ws_each";
  return join("", map { $_ . (rand() < 0.4 ? pick(@WS) : "") } @items) if $mode eq "ws_rand";
  return join("", @items);
}
sub rand_side { my ($pool, $ms, $mt) = @_; side(int(rand($ms + 1)), int(rand($mt + 1)), pick("plain", "ws_each", "ws_rand"), $pool) }

my @cases;
# add <entry index> <gaps> <class> — the entry with these gaps, in a line of text, after 0 to 2
# lines (so the line a match starts on varies), in its own case or in upper case
sub add {
  my ($e, $gaps, $class) = @_;
  my @w = @{$ENTRIES[$e]};
  @w = map { uc } @w if rand() < 0.3;
  my $body = $w[0];
  $body .= $gaps->[$_ - 1] . $w[$_] for 1 .. $#w;
  my $text = ("a line before\n" x int(rand(3))) . "pre " . $body . " post\n";
  push @cases, [$text, $class];
}

# 1. the grid
for my $ns (0 .. 26) {
  for my $nt (0 .. 4) {
    for my $mode ("plain", "ws_each", "ws_rand") {
      for my $where ("before", "after", "both") {
        my $a = side($ns, $nt, $mode, \@PLAIN_TAGS);
        my $b = $where eq "both" ? side($ns, $nt, $mode, \@PLAIN_TAGS) : pick("", " ", "# ");
        my $br = pick(@BREAKS);
        add(0, [$where eq "after" ? $b . $br . $a : $a . $br . $b], "grid");
      }
    }
  }
}
# 2. random sides from the whole tag pool, every entry; the three-word entry at gap 1, 2 or both
for my $spec ([0, 1000], [1, 900], [2, 500], [3, 500], [4, 500], [5, 300], [6, 300], [7, 300]) {
  my ($e, $count) = @$spec;
  for (1 .. $count) {
    my $g = rand_side(\@TAGS, 26, 4) . pick(@BREAKS) . rand_side(\@TAGS, 26, 4);
    if ($e == 1) {
      my $which = pick("g1", "g2", "both");
      my $g2 = rand_side(\@TAGS, 26, 4) . pick(@BREAKS) . rand_side(\@TAGS, 26, 4);
      add($e, $which eq "g1" ? [$g, " "] : $which eq "g2" ? [" ", $g] : [$g, $g2], "rand-$which");
    } else {
      add($e, [$g], "rand");
    }
  }
}
# 3. a symbol run that ends in `<`, before a tag or the break, near the bound
for (1 .. 400) {
  my $pre = join("", map { pick(@SYMS) } 1 .. 20 + int(rand(6))) . "<";
  my $post = pick("", "<t>", "t>", "<<t>", "-");
  my $br = pick(@BREAKS);
  add(pick(0, 2, 4), [pick($pre . $post . $br, $br . $pre . $post, $pre . $br . $post)], "lt-end");
}
# 4. the next word's own symbols near the bound: `(vandu`, `(1)`, `++` after 20 to 26 symbols,
# and a word of symbols alone followed by symbols on its line
for (1 .. 200) {
  my $e = pick(2, 6, 7);
  my $run = join("", map { pick("-", "#", "*", "|") } 1 .. 20 + int(rand(7)));
  my $br = pick(@BREAKS);
  add($e, [pick($br . $run, $run . $br, $br . " " . $run)], "own-symbols");
}
# 5. never a match: two breaks, the words run together, symbols on one line
for (1 .. 300) {
  my $e = pick(0, 2, 3, 6);
  my $shape = pick("two", "together", "oneline");
  my $g = $shape eq "two" ? rand_side(\@PLAIN_TAGS, 4, 1) . pick(@TWO) . rand_side(\@PLAIN_TAGS, 4, 1)
    : $shape eq "together" ? ""
    : pick(",", " , ", " - ", " # ", "<t>", " <-> ", ";") ;
  add($e, [$g], "not-$shape");
}
# 6. one line, white space alone
for (1 .. 200) {
  add(pick(0, 2, 3, 6), [pick(" ", "\t", "\x{a0}", "  ", "\x{2003}", " \x{3000} ")], "oneline");
}

open(my $lh, ">:encoding(UTF-8)", $listf) or die "cannot write $listf\n";
print $lh join(" ", @$_), "\n" for @ENTRIES;
close $lh or die "cannot write $listf\n";
mkdir $dir unless -d $dir;
open(my $mh, ">", $manf) or die "cannot write $manf\n";
for my $i (0 .. $#cases) {
  my $name = sprintf("c%05d", $i);
  open(my $ch, ">:raw:encoding(UTF-8)", "$dir/$name.txt") or die "cannot write $dir/$name.txt\n";
  print $ch $cases[$i][0];
  close $ch or die "cannot write $dir/$name.txt\n";
  print $mh "$name $cases[$i][1]\n";
}
close $mh or die "cannot write $manf\n";
print scalar(@cases), " cases\n";
