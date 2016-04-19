#!/usr/local/bin/perl
use Storable;
use Date::Parse qw(str2time);
use FileHandle;
use Fcntl ':flock';
use strict;

my $store = '/usr/local/logs/swarm.store';
my $sbatch_log_dir="/usr/local/logs/sbatch_log_archives/";

my $HR = retreive_old_data();
my @l = (keys %{$HR->{logfile}});
if (parse_logfiles($sbatch_log_dir)) {
  add_new_data_to_store();
}
print_short_summary();
#print_summary();

#==================================================================================================
sub retreive_old_data
{
  open(FH, ">$store.lck")           or die "can't create lock $store.lck $!";
  flock(FH, 2)                        or die "can't flock $store.lck $!";
  my $hr = retrieve($store) if (-f $store);
  close(FH)                           or die "can't remove lock $store.lck $!";
  unlink "$store.lck";
  return $hr;
}
#==================================================================================================
sub add_new_data_to_store
{
  open(FH, ">$store.lck")           or die "can't create lock $store.lck $!";
  flock(FH, 2)                        or die "can't flock $store.lck $!";
  unlink $store if (-f $store);
  store($HR,$store);
  close(FH)                           or die "can't remove lock $store.lck $!";
  unlink "$store.lck";
}
#==================================================================================================
sub parse_logfiles
{
  my ($sbatch_log_dir) = @_;
  opendir DIR, $sbatch_log_dir;
  my @files = grep /^sbatch.log-201\d+$/, readdir DIR;
  @files = sort @files;
  closedir DIR;

  my $count=0;
  LOGFILE: foreach my $f (@files) {
    $count++;
    if (defined $HR->{logfile}->{$f}) {
    #  print "logfile $f already parsed\n";
      next LOGFILE;
    }
#    last if ($count > 4);
    if (open FILE, "<$sbatch_log_dir/$f") {
      print "parsing $f\n";
      LINE: foreach my $line (<FILE>) {
        next LINE unless ($line=~/ \/spin1\/swarm\//);
        if ($line =~ /^(\d{4})(\d{2})(\d{2}) (\d\d:\d\d:\d\d) \w+ SUBM\[(\w+)\]: (\w+) .*?\/spin1\/swarm\/(\w+)\/(\w+)\/swarm.batch$/) {
          add_to_hashref($f,"${1}-${2}-${3} ${4}",$6,$7,$8,$5); 
        }
      }
      close FILE;
      $HR->{logfile}->{$f} = 1;
    }
  }
  return $count;
}
#==================================================================================================
sub add_to_hashref
{
  my ($logfile,$date,$user,$user2,$tag,$jobid) = @_;
  return unless ($user eq $user2); # ?
  if (not defined $HR->{swarm}->{$user}->{$date}->{$tag}) {
    my $time = str2time($date);
    $HR->{swarm}->{$user}->{$date}->{$tag} = {(
      time => $time,
      jobid => $jobid,
      logfile => $logfile,
    )};
  }
}
#==================================================================================================
sub print_short_summary
{
  my @files = (keys %{$HR->{logfile}});
  print "LOGFILES: ".scalar(@files)."\n";;

  my $count=0;
  foreach my $user (sort keys %{$HR->{swarm}}) {
    foreach my $date (sort keys %{$HR->{swarm}->{$user}}) {
      foreach my $tag (sort keys %{$HR->{swarm}->{$user}->{$date}}) { 
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
  foreach my $file (sort keys %{$HR->{logfile}}) {
    print "  $file\n";
  }

  print "JOBS:\n";
  foreach my $user (sort keys %{$HR->{swarm}}) {
    foreach my $date (sort keys %{$HR->{swarm}->{$user}}) {
      foreach my $tag (sort keys %{$HR->{swarm}->{$user}->{$date}}) { 
        printf ("%s  %-20s  %-20s %-10s %-10s\n",
          $tag,
          $date,
          $user,
          $HR->{swarm}->{$user}->{$date}->{$tag}->{logfile},
          $HR->{swarm}->{$user}->{$date}->{$tag}->{jobid},
        );
      }
    }
  }
}
#==================================================================================================


#20160403 12:16:03 biowulf SUBM[16684093]: buhuleod /spin1/users/buhuleod/proj1 sbatch --array=0-0 --job-name=swarm --output=/data/buhuleod/proj1/swarm_%A_%a.o --error=/data/buhuleod/proj1/swarm_%A_%a.e --cpus-per-task=2 --mem=10240 --partition=b1 --time=5-00:00:00 /spin1/swarm/buhuleod/tmpysxQQ5Fz/swarm.batch


#use Data::Dumper;

## Hash of arrays
#$HoA = {(
#  flintstones => [ "fred","barney" ],
#  jetsons => [ "george","jane","elroy" ],
#  simpsons => [ "homer","marge","bart"],
#)};
##print Dumper($HoA);
#store $HoA, 'HoA.store';
#
## hash of hashes
#$HoH = {(
#  flintstones => {
#    lead => "fred",
#    pal  => "barney",
#  },
#  jetsons => {
#    lead => "george",
#    wife => "jane",
#    "his boy" => "elroy",
#  },
#  simpsons => {
#    lead => "homer",
#    wife => "marge",
#    kid => "bart",
#  },
#)};
##print Dumper($HoH);
#store $HoH, 'HoH.store';
#
## array of hashes
#$AoH = [
#    {
#       husband  => "barney",
#       wife     => "betty",
#       son      => "bamm bamm",
#    },
#    {
#       husband => "george",
#       wife    => "jane",
#       son     => "elroy",
#    },
#
#    {
#       husband => "homer",
#       wife    => "marge",
#       son     => "bart",
#    },
#  ];
##print Dumper($AoH);
#store $AoH, 'AoH.store';
#
#
###$hr = retrieve('HoA.store');
