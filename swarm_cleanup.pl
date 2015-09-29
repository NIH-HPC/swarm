#!/usr/bin/perl

use lib "/usr/local/slurm/lib/site_perl/5.12.1/x86_64-linux-thread-multi";
use lib "/usr/local/slurm/lib/perl5/site_perl/5.18.2/x86_64-linux-thread-multi-ld";
use File::Basename;
use Getopt::Long;
Getopt::Long::Configure("bundling");
use Slurm;

use strict;

my $description = <<EOF;

swarm_cleanup.pl -- remove old swarm temp files and directories

options:

  -l     log actions to this file
  -h     print this message
  -d     run in debug mode (prevents -o option)

Last modification date Sep 28, 2015 (David Hoover)

EOF

$|=1;  # turns off output buffering

my %OPT;  # options
GetOptions(
  "u=s" => \$OPT{user}, # restrict to this user
  "l=s" => \$OPT{log}, # log actions
  "log=s" => \$OPT{log}, # log actions
  "d" => \$OPT{debug}, # debug mode
  "debug" => \$OPT{debug}, # debug mode
  "h" => sub { print $description; exit; },
  "help" => sub { print $description; exit; },
  "v=i" => \$OPT{verbose},
  "verbose=i" => \$OPT{verbose},
);

# Permanently debug state until we know this will work correctly
$OPT{debug} = 1;

# Get states for all jobs known to sacct
my $x = getJobs();

# Get all directories in /spin1/swarm
my $y = getDirectories();

print "Walking through directories\n" if $OPT{debug};
# Walk through all directories and determine if it and the associated batch file be removed
foreach my $id (sort keys %{$y}) {

  my $delete;

  my $user = basename(dirname($y->{$id}));
  print "$user/$id: " if $OPT{debug};

  if ($id >  100000000000) { # fake job id
# is the symlink older than a week?
    if (older_than_one_week($y->{$id})) {
      print " --> ONE WEEK" if $OPT{debug};
      $delete = 1;
    }
    else {
      print " --> TOO EARLY" if $OPT{debug};
    }
  }
  else {

# Real job id
    if (not defined $x->{$id}) { # unknown to perl api
      $x = getStatesForJob($id); 
    }

    my @z = sort keys %{$x->{$id}};

    if (@z) { # job states known
      print " --> @z" if ($OPT{debug});

# If the job state is NOT an active state, then the Job is inactive -- we can delete it
      $delete = 1;
      foreach my $st ("CONFIGURING","COMPLETING","PENDING","RUNNING","RESIZING","SUSPENDED") {
        undef $delete if (grep /$st/,@z);
      }
    }
    else {
      print " --> ?" if $OPT{debug};
    }
  }

  print " DELETE!" if ($delete && $OPT{debug});
  print "\n" if $OPT{debug}; 
}
#  else {
##    print "unknown\n";
##    print "  $y->{$id}\n";
#
## Is the directory empty?
#
#    if ((-d $y->{$id}) && (is_folder_empty($y->{$id})) && (older_than_three_days($y->{$id}))) {
#      print " --> EMPTY" if $OPT{debug};
#      $delete = 1;
#    }
#
#  }
#
#  if ($delete) {
#    print " --> DELETE\n" if $OPT{debug};
#    my $cmd = "test -d $y->{$id} && rm -rf $y->{$id} ; test -f $y->{$id}.batch && rm -f $y->{$id}.batch";
#    if ($OPT{debug}) {
#      print "$cmd\n" if ($OPT{verbose} > 1);
#    }
#    else {
#      system($cmd);
#      system("echo \$\(date \+\"%F %T\"\)  $user/$id >> $OPT{log}") if $OPT{log};
#    }
#  }
#  else {
#    print "\n" if $OPT{debug};
#  }
#}

#print "Looking for singleout files\n" if $OPT{debug};
#my $z = getSingleoutFiles();
#foreach my $id (sort keys %{$z}) {
#  foreach my $file (@{$z->{$id}}) {
#
#    my $delete;
#
#    my $user = basename(dirname($z->{$id}));
#    print "$user/$id: " if $OPT{debug};
#
#    print "$file: " if $OPT{debug};
#    if (not defined $x->{$id}) {
#      $x->{$id} = getStatesForJob($id); 
#    }
#    print " --> $x->{$id}" if $OPT{debug};
#
## If the job state is NOT an active state, then the Job is inactive -- we can delete it
#    if ($x->{$id}!~/CONFIGURING|COMPLETING|PENDING|RUNNING|RESIZING|SUSPENDED/) {
#
#      if (older_than_three_days($file)) {
#        $delete = 1;
#      }
#    }
#
#    if ($delete) {
#      print " --> DELETE\n" if $OPT{debug};
#      my $cmd = "rm -f $file";
#      if ($OPT{debug}) {
#        print "$cmd\n" if ($OPT{verbose} > 1);
#      }
#      else {
#        system($cmd);
#      }
#    }
#    else {
#      print "\n" if $OPT{debug};
#    }
#  }
#}


#==============================================================================
#sub older_than_one_month
#{
#  my $dirname = shift;
#  my $mtime = (stat($dirname))[9];
#  print " --> $mtime" if $OPT{debug};
#  return 1 if ((time()-$mtime) > (86400*31));
#}
#==============================================================================
sub older_than_one_week
{
  my $dirname = shift;
  my $mtime = (stat($dirname))[9];
  return 1 if ((time()-$mtime) > (86400*7));
}
#==============================================================================
#sub older_than_three_days
#{
#  my $dirname = shift;
#  my $mtime = (stat($dirname))[9];
#  return 1 if ((time()-$mtime) > (86400*3));
#}
#==============================================================================
#sub is_folder_empty {
#  my $dirname = shift;
#  if (opendir(my $dh, $dirname)) {
#    return scalar(grep { $_ ne "." && $_ ne ".." } readdir($dh)) == 0;
#  }
#  else {
#    warn "Can't open directory: $dirname";
#  }
#}
##==============================================================================
sub getDirectories
{
  print "Getting directory info\n" if $OPT{debug};
  my $cmd;
  if ($OPT{user}) {
    $cmd = 'find /spin1/swarm/'.$OPT{user}.' -mindepth 1 -maxdepth 1 \( -type l -o -type d \) 2>/dev/null';
  }
  else {
    $cmd = 'find /spin1/swarm -mindepth 2 -maxdepth 2 \( -type l -o -type d \) 2>/dev/null';
  }
  chomp(my $ret = `$cmd`);
  my $s;
  foreach my $line (split /\n/,$ret) {
    my $id = basename($line);

# only keep numerical symlinks
    if ($id=~/^\d+$/) {
      $s->{$id} = $line;
    }
  }
  return $s;
}
#==============================================================================
#sub getSingleoutFiles
#{
#  print "Getting singleout file info\n" if $OPT{debug};
#  my $cmd;
#  if ($OPT{user}) {
#    $cmd = "find /spin1/swarm/$OPT{user} -mindepth 1 -maxdepth 1 -type f -name '*.o' -o -name '*.e' 2>/dev/null";
#  }
#  else {
#    $cmd = "find /spin1/swarm -mindepth 2 -maxdepth 2 -type f -name '*.o' -o -name '*.e' 2>/dev/null";
#  }
#  chomp(my $ret = `$cmd`);
#  my $s;
#  foreach my $file (split /\n/,$ret) {
#    if ($file =~ /\/(\d+)_[\d_]+\.[eo]$/) {
#      push @{$s->{$1}},$file;
#    }
#  }
#  return $s;
#}
#==============================================================================
sub getJobs
{
  my $slurm = Slurm::new();
  my $jobs = $slurm->load_jobs();
  print "Getting job states\n" if $OPT{debug};
  my $hr;
  JOB: foreach my $ref (@{$jobs->{job_array}}) {
    next JOB if ((defined $OPT{user}) && ($ref->{"user"} ne $OPT{user}));
    next JOB unless ($ref->{"array_job_id"}); # only keep job arrays
    my $state = $slurm->job_state_string($ref->{"job_state"});
    $hr->{$ref->{"array_job_id"}}{$state} = 1;
  } 

  return $hr
}
#==============================================================================
sub getStatesForJob
{
  my $id = shift;
  my $cmd = "sacct -j $id --format=JobID,State --noheader";
  $cmd .= " -u $OPT{user}" if $OPT{user};
  chomp(my $ret = `$cmd`);
  my $hr;
  foreach my $line (split /\n/,$ret) {
    if ($line=~/^(\d+)\S*\s*(.*)$/) {
      $hr->{$1}{$2}=1;
    }
  }
 
  return $hr;
}
#==============================================================================
