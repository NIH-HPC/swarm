#!/usr/local/bin/perl
use Storable;
use Date::Parse qw(str2time);
use FileHandle;
use Fcntl ':flock';
use strict;

my $PAR;

$PAR->{store} = '/usr/local/logs/swarm.store';
$PAR->{sbatch_log_dir}="/usr/local/logs/sbatch_log_archives/";
$PAR->{sbatch_log} = "/usr/local/logs/sbatch.log";

my %OPT;
getOptions();

retreive_old_data();
my @l = (keys %{$PAR->{data}->{logfile}});
parse_logfiles($PAR->{sbatch_log_dir});
add_new_data_to_store() unless $OPT{debug};
if ($OPT{verbose}) {
  print_summary();
}
else {
  print_short_summary();
}

#==================================================================================================
sub retreive_old_data
{
  open(FH, ">$PAR->{store}.lck")           or die "can't create lock $PAR->{store}.lck $!";
  flock(FH, 2)                        or die "can't flock $PAR->{store}.lck $!";
  $PAR->{data} = retrieve($PAR->{store}) if (-f $PAR->{store});
  close(FH)                           or die "can't remove lock $PAR->{store}.lck $!";
  unlink "$PAR->{store}.lck";
  return;
}
#==================================================================================================
sub add_new_data_to_store
{
  open(FH, ">$PAR->{store}.lck")           or die "can't create lock $PAR->{store}.lck $!";
  flock(FH, 2)                        or die "can't flock $PAR->{store}.lck $!";
  unlink $PAR->{store} if (-f $PAR->{store});
  store($PAR->{data},$PAR->{store});
  close(FH)                           or die "can't remove lock $PAR->{store}.lck $!";
  unlink "$PAR->{store}.lck";
  chmod 0640,$PAR->{store};
}
#==================================================================================================
sub parse_logfiles
{
# Find the archived sbatch log files
  opendir DIR, $PAR->{sbatch_log_dir};
  my @files = grep /^sbatch.log-201\d+$/, readdir DIR;
  @files = sort @files;
  closedir DIR;

# Walk through the log files
  LOGFILE: foreach my $f (@files) {
# Skip it if it has already been parsed
    if (defined $PAR->{data}->{logfile}->{$f}) {
      print "logfile $f already parsed\n" if $OPT{verbose};
      next LOGFILE;
    }
# Parse the file
    $PAR->{data}->{logfile}->{$f} = parse_log_file("$PAR->{sbatch_log_dir}/$f");
  }

# And of course parse the current sbatch.log file
  print "parsing regular log\n" if $OPT{verbose};
  parse_log_file($PAR->{sbatch_log});

  return;
}
#==================================================================================================
sub parse_log_file
{
  my $f = shift;
  if (open FILE, "<$f") {
    print "parsing $f\n";
    LINE: foreach my $line (<FILE>) {
      next LINE unless ($line=~/ \/spin1\/swarm\//);
      if ($line =~ /^(\d{4})(\d{2})(\d{2}) (\d\d:\d\d:\d\d) \w+ SUBM\[(\w+)\]: (\w+) .*?\/spin1\/swarm\/(\w+)\/(\w+)\/swarm.batch$/) {
        my $date = "${1}-${2}-${3}";
        my $time = ${4};
        add_to_hashref($f,"$date $time",$6,$7,$8,$5); 
        if (!$PAR->{dates_found}{$date}) {
          print "$date\n" if $OPT{verbose};
        }
        $PAR->{dates_found}{$date} = 1;
      }
    }
    close FILE;
    return 1;
  }
}
#==================================================================================================
sub add_to_hashref
{
  my ($logfile,$date,$user,$user2,$tag,$jobid) = @_;
  return unless ($user eq $user2); # ?
  if (not defined $PAR->{data}->{swarm}->{$user}->{$date}->{$tag}) {
    my $time = str2time($date);
    $PAR->{data}->{swarm}->{$user}->{$date}->{$tag} = {(
      time => $time,
      jobid => $jobid,
      logfile => $logfile,
    )};
  }
}
#==================================================================================================
sub print_short_summary
{
  my @files = (keys %{$PAR->{data}->{logfile}});
  print "LOGFILES: ".scalar(@files)."\n";;

  my $count=0;
  foreach my $user (sort keys %{$PAR->{data}->{swarm}}) {
    foreach my $date (sort keys %{$PAR->{data}->{swarm}->{$user}}) {
      foreach my $tag (sort keys %{$PAR->{data}->{swarm}->{$user}->{$date}}) { 
        $count++; 
      }
    }
  }
  print "SWARMS: $count\n";
}
#==================================================================================================
sub print_summary
{
  print "LOGFILES CHECKED:\n";
  foreach my $file (sort keys %{$PAR->{data}->{logfile}}) {
    print "  $file\n";
  }

  print "JOBS:\n";
  foreach my $user (sort keys %{$PAR->{data}->{swarm}}) {
    foreach my $date (sort keys %{$PAR->{data}->{swarm}->{$user}}) {
      foreach my $tag (sort keys %{$PAR->{data}->{swarm}->{$user}->{$date}}) { 
        printf ("%s  %-20s  %-20s %-10s %-10s\n",
          $tag,
          $date,
          $user,
          $PAR->{data}->{swarm}->{$user}->{$date}->{$tag}->{logfile},
          $PAR->{data}->{swarm}->{$user}->{$date}->{$tag}->{jobid},
        );
      }
    }
  }
}
#==================================================================================================
sub getOptions
{ 
  use Getopt::Long qw(:config no_ignore_case);
  Getopt::Long::Configure("bundling"); # allows option bundling
  GetOptions(
    'help' => \$OPT{help},
    'h' => \$OPT{help},
    'debug' => \$OPT{debug},
    'd' => \$OPT{debug},
    'verbose' => \$OPT{verbose},
    'v' => \$OPT{verbose},
  ) || printOptions();

  printOptions() if $OPT{help};

  print STDERR "Running in debug mode\n" if $OPT{debug};
}
#==================================================================================================
sub printOptions
{
  my $msg = shift;
  warn "\n$msg\n" if $msg;

  print STDERR <<EOF;

Usage: $0 [ options ]

Options:

  -h, --help     print options list
  -d, --debug    run in debug mode 
  -v, --verbose  be chatty

Description:

  Parse sbatch log files and incorporate the results into a store file for
  swarm_cleonup.pl.

    $PAR->{store}

  Last modification date: Jun 10, 2016

EOF
  
  exit;
}
#=================================================================================================
