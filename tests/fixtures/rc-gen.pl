#!/usr/bin/perl
# tests/fixtures/rc-gen.pl <seed> <case dir> — the generated rc files bionic's retired lines are
# held to by behaviour (wave-27 T75). One file per case in <case dir> (`<id>.rc`), and one line per
# case in `<case dir>/index`: `<id> <family> <shell>`, where <family> names the doors the case goes
# through (`alias`, `env` or `both`) and <shell> is the shell that reads it (`bash` for a .bashrc,
# `zsh` for a .zshrc). The same seed writes the same bytes, and the same set of cases: the seed
# picks only the order the index lists them in, so a sample read off the top is fixed by the seed.
#
# The shapes are review pass 54's 422 (its generator was not shipped; they are ported here):
# bionic's exact line, the template line, the retired alias block, the retired environment block
# and a bare environment line, each in 65 places among 43 constructs (as the only command, and
# among the user's own where that makes sense); 28 forms of the line itself; the file forms (CR LF,
# no final newline, a 200,000-character line, a non-UTF-8 byte, an rc that does not parse, the line
# alone, an empty file); two and three of bionic's lines; and 32 block shapes (a user line between
# the markers, a changed value, markers that do not pair, two blocks, both blocks, nested,
# interleaved). EVERY LINE THAT IS NOT BIONIC'S IS THE SUITE'S OWN, HARMLESS AND OBSERVABLE: it
# sets a variable of its own (`export V<n>=<n>`) or appends its own tag to `$HOME/log`
# (`echo t<n> >> "$HOME/log"`), so executing the rc before and after a door shows any difference
# a door made to what the user's lines do. Nothing here names a real path outside $HOME.
use strict;
use warnings;

my ($seed, $dir) = @ARGV;
die "usage: rc-gen.pl <seed> <case dir>\n" unless defined $dir;
-d $dir or mkdir $dir or die "rc-gen.pl: cannot make $dir: $!\n";

my $A1 = "alias claude='claude --dangerously-skip-permissions'";
my $A2 = "alias claude='/opt/homebrew/bin/claude --dangerously-skip-permissions'";
my ($AS, $AE) = ("# \x{2500}\x{2500}\x{2500} bionic:start \x{2500}\x{2500}\x{2500}", "# \x{2500}\x{2500}\x{2500} bionic:end \x{2500}\x{2500}\x{2500}");
my ($ES, $EE) = ("# \x{2500}\x{2500}\x{2500} bionic:env:start \x{2500}\x{2500}\x{2500}", "# \x{2500}\x{2500}\x{2500} bionic:env:end \x{2500}\x{2500}\x{2500}");
utf8::encode($_) for ($AS, $AE, $ES, $EE);
my $EL = 'export CLAUDE_CODE_ENABLE_TODO_TOOLS=1';
my @AB = ($AS, $A1, $AE);
my @EB = ($ES, $EL, $EE);

# The user's own observable lines, numbered per case.
my $u = 0;
sub v { $u++; return "export V$u=$u"; }
sub g { $u++; return "echo t$u >> \"\$HOME/log\""; }
sub ind { return map { "  $_" } @_; }

my @cases;   # [id, family, [shells], bytes]
sub add {
  my ($id, $fam, $lines, %o) = @_;
  my $sep = $o{crlf} ? "\r\n" : "\n";
  my $raw = defined $o{raw} ? $o{raw} : join($sep, @$lines) . ($o{nofinal} ? '' : $sep);
  push @cases, [$id, $fam, $o{shells} || ['bash', 'zsh'], $raw];
}

# The constructs: name => sub (lines of bionic's, among the user's?) => lines.
sub wrap { my ($open, $close, $x, $sev, $noind) = @_;
  my @b = $noind ? @$x : ind(@$x);
  @b = ((($noind ? '' : '  ') . v()), @b, (($noind ? '' : '  ') . g())) if $sev;
  return (@$open, @b, @$close); }
my %CTX = (
  top        => sub { my ($x, $s) = @_; $s ? (v(), @$x, g()) : @$x },
  if         => sub { wrap(['if [ -z "$NOPE" ]; then'], ['fi'], @_) },
  elif       => sub { wrap(['if [ -n "$NOPE" ]; then', '  :', 'elif [ -z "$NOPE" ]; then'], ['fi'], @_) },
  else       => sub { wrap(['if [ -n "$NOPE" ]; then', '  :', 'else'], ['fi'], @_) },
  for        => sub { wrap(['for i in 1; do'], ['done'], @_) },
  while      => sub { wrap(['while [ -z "$W1" ]; do', '  W1=1'], ['done'], @_) },
  until      => sub { wrap(['until [ -n "$W2" ]; do', '  W2=1'], ['done'], @_) },
  case       => sub { wrap(['case x in', '  x)'], ['    ;;', 'esac'], @_) },
  fn1        => sub { my @l = wrap(['myf() {'], ['}'], @_); (@l, 'myf') },
  fn2        => sub { my @l = wrap(['function myf {'], ['}'], @_); (@l, 'myf') },
  fn3        => sub { my @l = wrap(['function myf() {'], ['}'], @_); (@l, 'myf') },
  subsh      => sub { wrap(['('], [')'], @_) },
  brace      => sub { wrap(['{'], ['}'], @_) },
  cmdsub     => sub { my @l = wrap(['OUT=$('], [')'], @_); (@l, 'echo "o:$OUT" >> "$HOME/log"') },
  bquote     => sub { my @l = wrap(['OUT=`'], ['`'], @_); (@l, 'echo "o:$OUT" >> "$HOME/log"') },
  hd         => sub { wrap(['cat >> "$HOME/log" <<EOF'], ['EOF'], @_, 1) },
  hdq        => sub { wrap(["cat >> \"\$HOME/log\" <<'EOF'"], ['EOF'], @_, 1) },
  hdtab      => sub { my ($x, $s) = @_; my @b = (($s ? (v()) : ()), @$x, ($s ? (g()) : ()));
                      ('cat >> "$HOME/log" <<-EOF', (map { "\t$_" } @b), "\tEOF") },
  hdcmdsub   => sub { my @l = wrap(["OUT=\$(cat <<'EOF'"], ['EOF', ')'], @_, 1); (@l, 'echo "o:$OUT" >> "$HOME/log"') },
  hstr       => sub { wrap(['cat >> "$HOME/log" <<< "'], ['"'], @_, 1) },
  sq         => sub { my @l = wrap(["NOTE='"], ["'"], @_, 1); (@l, 'echo "n:$NOTE" >> "$HOME/log"') },
  dq         => sub { my @l = wrap(['NOTE="'], ['"'], @_, 1); (@l, 'echo "n:$NOTE" >> "$HOME/log"') },
  eval       => sub { wrap(["eval '"], ["'"], @_, 1) },
  bslash     => sub { ('echo one \\', @{$_[0]}, g()) },
  andand     => sub { ('[ -f "$HOME/.work" ] &&', @{$_[0]}, v()) },
  oror       => sub { ('[ -f "$HOME" ] ||', @{$_[0]}, v()) },
  pipe       => sub { ('echo x |', @{$_[0]}, v()) },
  pipeamp    => sub { ('echo x |&', @{$_[0]}, v()) },
  andcomment => sub { ('[ -f "$HOME/.work" ] && # only at work', @{$_[0]}, v()) },
  pipecomment=> sub { ('echo x | # filter', @{$_[0]}, v()) },
  andblank   => sub { ('[ -f "$HOME/.work" ] &&', '', '# note', @{$_[0]}, v()) },
  bscomment  => sub { ('# a comment that ends in a backslash \\', @{$_[0]}, v()) },
  bsthencomment => sub { ('echo one \\', '# a comment line between', @{$_[0]}, v()) },
  dbracket   => sub { ('[[ -n "$HOME" &&', @{$_[0]}, ']] && ' . v()) },
  afterexit  => sub { (v(), 'return 0 2>/dev/null || exit 0', @{$_[0]}) },
  beforeexit => sub { (@{$_[0]}, 'return 0 2>/dev/null || exit 0', v()) },
  zshfn      => sub { ('myf()', @{$_[0]}, v(), 'myf 2>/dev/null') },
  zshrepeat  => sub { ('repeat 2', @{$_[0]}, g()) },
  zshforshort=> sub { ('for i (a b)', @{$_[0]}, g()) },
  bang       => sub { ('!', @{$_[0]}, v()) },
  bangtrue   => sub { ('! true', @{$_[0]}) },
  banglast   => sub { (v(), @{$_[0]}, '! true') },
  bangthenours => sub { (v(), '! true', @{$_[0]}) },
  time       => sub { ('time', @{$_[0]}, v()) },
  arith      => sub { ('(( V0 = 1 +', @{$_[0]}, '))') },
);
my %ONLY = map { $_ => 1 } qw(top bslash andand oror pipe pipeamp andcomment pipecomment andblank bscomment
  bsthencomment dbracket afterexit beforeexit zshfn zshrepeat zshforshort bang bangtrue banglast bangthenours time arith);
# These end with bionic's line or block: nothing of the user's follows it.
my %LAST = map { $_ => 1 } qw(banglast bangthenours afterexit);
for my $c (sort keys %CTX) {
  for my $sev (0, 1) {
    next if $sev && $ONLY{$c} && $c ne 'top';
    my $tag = $sev ? 'sev' : 'only';
    my %X = (a => [$A1], t => [$A2], ab => \@AB, eb => \@EB, el => [$EL]);
    for my $k (qw(a t ab eb el)) {
      $u = 0;
      my $fam = ($k eq 'eb' || $k eq 'el') ? 'env' : 'alias';
      add("$k-$c-$tag", $fam, ['# my rc', $CTX{$c}->($X{$k}, $sev), ($LAST{$c} ? () : v())]);
    }
  }
}

# The line itself, at top level, in each form.
my %FORMS = (
  indent => "\t  $A1", trail => "$A1  \t", comment => "$A1 # a note", shared => "$A1; export V9=9",
  dq => 'alias claude="claude --dangerously-skip-permissions"',
  pipe => "alias claude='/usr/bin/tee|/opt/homebrew/bin/claude --dangerously-skip-permissions'",
  amp => "alias claude='/x&/claude --dangerously-skip-permissions'", lt => "alias claude='/x</claude --dangerously-skip-permissions'",
  paren => "alias claude='/x(1)/claude --dangerously-skip-permissions'", space => "alias claude='/my dir/claude --dangerously-skip-permissions'",
  glob => "alias claude='/opt/*/claude --dangerously-skip-permissions'", hash => "alias claude='/a#b/claude --dangerously-skip-permissions'",
  bsl => "alias claude='/a\\b/claude --dangerously-skip-permissions'", brace => "alias claude='/a{b,c}/claude --dangerously-skip-permissions'",
  bang => "alias claude='/a!b/claude --dangerously-skip-permissions'", caret => "alias claude='/a^b/claude --dangerously-skip-permissions'",
  q => "alias claude='/a?b/claude --dangerously-skip-permissions'", utf8 => "alias claude='/Users/jos\xc3\xa9/bin/claude --dangerously-skip-permissions'",
  latin1 => "alias claude='/Users/jos\xe9/bin/claude --dangerously-skip-permissions'", nbsp => "alias claude='/a\xc2\xa0b/claude --dangerously-skip-permissions'",
  tilde => "alias claude='/~x/claude --dangerously-skip-permissions'", empty => "alias claude=' --dangerously-skip-permissions'",
  rel => "alias claude='bin/claude --dangerously-skip-permissions'", claude2 => "alias claude='/x/claude2 --dangerously-skip-permissions'",
  aliasg => "alias -g claude='claude --dangerously-skip-permissions'", export => "export alias claude='claude --dangerously-skip-permissions'",
  allow => "alias claude='claude --allow-dangerously-skip-permissions'", crmid => "$A1\r ",
);
for my $k (sort keys %FORMS) { $u = 0; add("f-$k", 'alias', [v(), $FORMS{$k}, g()]); }

# The file forms.
$u = 0; add('x-crlf', 'alias', [v(), $A1, g()], crlf => 1);
$u = 0; add('x-crlf-if', 'alias', ['if [ -z "$NOPE" ]; then', $A1, 'fi', v()], crlf => 1);
$u = 0; add('x-nofinal', 'alias', [v(), $A1], nofinal => 1);
$u = 0; add('x-nofinal-mid', 'alias', [v(), $A1, g()], nofinal => 1);
$u = 0; add('x-long', 'alias', ['export V1=' . ('y' x 200000), $A1, g()]);
$u = 0; add('x-long-ours', 'alias', ["alias claude='/" . ('a/' x 100000) . "claude --dangerously-skip-permissions'", v()]);
$u = 0; add('x-nonutf8', 'alias', ["export V1='\xff\xfe\x80'", $A1, "export V2='\xc3('"]);
$u = 0; add('x-noparse', 'alias', ['if true; then', $A1, v()]);
$u = 0; add('x-only', 'alias', [$A1]);
$u = 0; add('x-only-nofinal', 'alias', [$A1], nofinal => 1);
$u = 0; add('x-empty', 'alias', [], raw => '');
$u = 0; add('x-two', 'alias', [v(), $A1, g(), $A1]);
$u = 0; add('x-three', 'alias', [$A1, v(), $A1, 'if true; then', "  $A1", '  ' . g(), 'fi', $A1]);
$u = 0; add('x-two-if', 'alias', ['if true; then', "  $A1", "  $A1", 'fi', v()]);
$u = 0; add('x-two-adj', 'alias', [v(), $A1, $A1]);
$u = 0; add('x-top-between', 'alias', [v(), $A1, g()]);

# The block shapes.
my %BLK;
$u = 0; $BLK{'ab-top'}        = ['alias', [v(), '', @AB]];
$u = 0; $BLK{'ab-top-after'}  = ['alias', [v(), '', @AB, g()]];
$u = 0; $BLK{'ab-nofinal'}    = ['alias', [v(), '', @AB, g()], 1];
$u = 0; $BLK{'ab-nofinal-end'}= ['alias', [v(), '', @AB], 1];
$u = 0; $BLK{'ab-noblank'}    = ['alias', [v(), @AB, g()]];
$u = 0; $BLK{'ab-twoblank'}   = ['alias', [v(), '', '', @AB]];
$u = 0; $BLK{'ab-userline'}   = ['alias', [v(), '', $AS, $A1, 'export T=x', $AE, g()]];
$u = 0; $BLK{'ab-useronly'}   = ['alias', [v(), '', $AS, v(), $AE]];
$u = 0; $BLK{'ab-empty'}      = ['alias', [v(), $AS, $AE]];
$u = 0; $BLK{'ab-nostart'}    = ['alias', [v(), $A1, $AE]];
$u = 0; $BLK{'ab-noend'}      = ['alias', [v(), $AS, $A1, g()]];
$u = 0; $BLK{'ab-swapped'}    = ['alias', [v(), $AE, $A1, $AS]];
$u = 0; $BLK{'ab-two'}        = ['alias', [v(), @AB, @AB]];
$u = 0; $BLK{'ab-crlf'}       = ['alias', [v(), @AB], 0, 1];
$u = 0; $BLK{'ab-and-bare'}   = ['alias', [v(), @AB, $A1]];
$u = 0; $BLK{'ab-in-if'}      = ['alias', ['if true; then', @AB, 'fi', v()]];
$u = 0; $BLK{'ab-indented'}   = ['alias', [v(), "  $AS", $A1, "  $AE"]];
$u = 0; $BLK{'eb-top'}        = ['env', [v(), '', @EB]];
$u = 0; $BLK{'eb-top-after'}  = ['env', [v(), '', @EB, g()]];
$u = 0; $BLK{'eb-nofinal'}    = ['env', [v(), '', @EB, g()], 1];
$u = 0; $BLK{'eb-userline'}   = ['env', [v(), $ES, $EL, 'export T=x', $EE, g()]];
$u = 0; $BLK{'eb-nostart'}    = ['env', [v(), $EL, $EE]];
$u = 0; $BLK{'eb-noend'}      = ['env', [v(), $ES, $EL]];
$u = 0; $BLK{'eb-swapped'}    = ['env', [v(), $EE, $EL, $ES]];
$u = 0; $BLK{'eb-and-bare'}   = ['env', [v(), @EB, $EL]];
$u = 0; $BLK{'eb-ten'}        = ['env', [v(), $ES, 'export CLAUDE_CODE_ENABLE_TODO_TOOLS=10', $EE, 'echo "e:$CLAUDE_CODE_ENABLE_TODO_TOOLS" >> "$HOME/log"']];
$u = 0; $BLK{'both'}          = ['both', [v(), '', @AB, '', @EB]];
$u = 0; $BLK{'both-nested'}   = ['both', ['if true; then', @AB, @EB, 'fi', v()]];
$u = 0; $BLK{'both-interleaved'} = ['both', [$AS, $ES, $A1, $AE, $EL, $EE, v()]];
$u = 0; $BLK{'both-bare'}     = ['both', [$A1, $EL, v()]];
$u = 0; $BLK{'env-shared'}    = ['env', ["$EL; export V1=1"]];
$u = 0; $BLK{'env-comment'}   = ['env', ["# $EL", v()]];
for my $k (sort keys %BLK) {
  my ($fam, $lines, $nofinal, $crlf) = @{$BLK{$k}};
  add("k-$k", $fam, $lines, nofinal => $nofinal, crlf => $crlf);
}

# WHAT EACH DOOR MUST LEAVE, written beside each rc (A-orch-162): the markers are the
# whole rule. A line outside a marker pair is never taken out. A block goes as one unit
# only when its markers pair up once (as markers.sh `markers_check` reads them), what
# sits between them is the one body bionic wrote, and the rc's own shell says, with `-n`
# on a copy, that the rc parsed before and still parses without it ("parses": nothing on
# stderr and exit 0, or for zsh 0 or 1). Setup keeps the blank line above a block it
# strips; remove drops one (remove.sh `_rm_strip_walk`, documented there). `<id>.<shell>.<kind>`:
# `setup` (the alias block), `rmalias`, `rmenv`, and `rmall` (the alias item, then the
# environment item). The index carries, per rc and shell, the numbers of bionic's exact
# bare alias lines (outside the alias markers; blanks at either end and one trailing CR
# aside, as detect.sh `bionic_rc_line_bare` reads them) in the rc setup leaves and in the
# rc remove's alias item leaves, which every alias door must name, or `-`.
my %BODY = ($AS => $A1, $ES => $EL);
my %END = ($AS => $AE, $ES => $EE);
my $tmpd = "$dir/.t"; mkdir $tmpd;
my %pcache;
sub parses {  # <shell> <bytes>
  my ($sh, $raw) = @_;
  my $k = "$sh\0$raw"; return $pcache{$k} if exists $pcache{$k};
  open(my $f, '>:raw', "$tmpd/p") or die; print $f $raw; close $f;
  my $cmd = $sh eq 'zsh' ? "/bin/zsh -f -n" : "/bin/bash -n";
  my $err = `BASH_ENV= ENV= $cmd '$tmpd/p' 2>&1 >/dev/null </dev/null`; my $rc = $? >> 8;
  my $ok = ($err eq '' && ($rc == 0 || ($sh eq 'zsh' && $rc == 1))) ? 1 : 0;
  return $pcache{$k} = $ok;
}
sub strip_block {  # <units ref> <shell> <start marker> <drop the blank above?> — the units after the item
  my ($u, $sh, $s, $blank) = @_; my $e = $END{$s};
  my @t = map { my $x = $_; $x =~ s/\n\z//; $x } @$u;
  my ($first, $last, $bad) = (-1, -1, 0);
  for my $i (0 .. $#t) {
    if ($t[$i] eq $s) { if ($first >= 0) { $bad = 1 } else { $first = $i } }
    elsif ($t[$i] eq $e) { if ($first < 0 || $last >= 0) { $bad = 1 } else { $last = $i } }
  }
  return $u if $bad || $first < 0 || $last < 0;
  return $u unless $last == $first + 2 && $t[$first + 1] eq $BODY{$s};
  my @after = (@$u[0 .. $first - 1], @$u[$last + 1 .. $#$u]);
  return $u unless parses($sh, join('', @$u)) && parses($sh, join('', @after));
  my $top = $first;
  $top-- if $blank && $first > 0 && $u->[$first - 1] eq "\n";
  return [@$u[0 .. $top - 1], @$u[$last + 1 .. $#$u]];
}
sub bare {  # <raw> — bionic's exact bare alias lines, by number
  my @t = split /\n/, $_[0], -1; pop @t if @t && $t[-1] eq '';
  my ($in, @n) = (0);
  for my $i (0 .. $#t) {
    my $l = $t[$i];
    if ($l eq $AS) { $in = 1; next } if ($l eq $AE) { $in = 0; next } next if $in;
    (my $c = $l) =~ s/\A[ \t]+//; $c =~ s/[ \t]+\z//; $c =~ s/\r\z//; $c =~ s/[ \t]+\z//;
    push @n, $i + 1 if $c eq $A1 || $c eq $A2;
  }
  return @n ? join(',', @n) : '-';
}

# The order: a seeded shuffle, so the top of the index is a fixed sample of the whole.
srand($seed);
my @order = map { $_->[0] } sort { $a->[1] <=> $b->[1] } map { [$_, rand()] } 0 .. $#cases;
open(my $idx, '>', "$dir/index") or die "rc-gen.pl: $dir/index: $!\n";
for my $i (@order) {
  my ($id, $fam, $shells, $raw) = @{$cases[$i]};
  open(my $f, '>:raw', "$dir/$id.rc") or die "rc-gen.pl: $dir/$id.rc: $!\n";
  print $f $raw; close $f;
  my @u = $raw =~ /([^\n]*\n|[^\n]+\z)/g;
  for my $sh (@$shells) {
    my %exp = (setup => strip_block(\@u, $sh, $AS, 0), rmalias => strip_block(\@u, $sh, $AS, 1),
               rmenv => strip_block(\@u, $sh, $ES, 1));
    $exp{rmall} = strip_block($exp{rmalias}, $sh, $ES, 1);
    for my $k (keys %exp) {
      open(my $o, '>:raw', "$dir/$id.$sh.$k") or die; print $o join('', @{$exp{$k}}); close $o;
    }
    print $idx "$id $fam $sh ", bare(join('', @{$exp{setup}})), " ", bare(join('', @{$exp{rmalias}})), "\n";
  }
}
close $idx;
unlink "$tmpd/p"; rmdir $tmpd;
