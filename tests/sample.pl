#!/usr/local/bin/perl
if ($ARGV[0]) {
  print <<EOF;

sample.pl: extract sample swarm commands from swarm log

Last Modification: Jan 8, 2016 (David Hoover)

EOF
  exit;
}


foreach my $x (split /\n/,`tail -100 /usr/local/logs/swarm.log | tr ";" "\n" | grep "^ command=" | sed -e 's# command=/usr/local/bin/swarm ##g'`) {
  chomp $x;
  if ($x=~/^(.*)\s+\-f\s+\S+\s+(.*)$/) {
    print "$1 $2\n";
  }
  elsif ($x=~/^(.*)\s+\-\-file\s+\S+\s+(.*)$/) {
    print "$1 $2\n";
  }
  elsif ($x=~/^\-f\s+\S+\s+(.*)$/) {
    print "$1\n";
  }
  elsif ($x=~/^\-\-file\s+\S+\s+(.*)$/) {
    print "$1\n";
  }
  elsif ($x=~/^(.*)\s+\-f\s+\S+$/) {
    print "$1\n";
  }
  elsif ($x=~/^(.*)\s+\-\-file\s+\S+$/) {
    print "$1\n";
  }
}
