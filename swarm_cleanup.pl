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
  "clean-dev" => \$OPT{"clean-dev"}, # only clean dev directories
  "clean-orphans" => \$OPT{"clean-orphans"}, # only clean orphan directories
  "d" => \$OPT{debug}, # debug mode
  "debug" => \$OPT{debug}, # debug mode
  "h" => sub { print $description; exit; },
  "help" => sub { print $description; exit; },
  "v" => \$OPT{verbose},
  "verbose" => \$OPT{verbose},
);

$OPT{verbose} = 1 if $OPT{debug};

my $jobs = getJobs();

if ($OPT{"clean-dev"}) {
  clean_devdirs();
}
elsif ($OPT{"clean-orphans"}) {
  clean_orphandirs();
}
else {
  clean_jobdirs();
}

#  else {
##    print "unknown\n";
##    print "  $y->{$id}\n";
#
## Is the directory empty?
#
#    if ((-d $y->{$id}) && (emptydir($y->{$id})) && (older_than_three_days($y->{$id}))) {
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
sub emptydir {
  my $dirname = shift;
  if (opendir(my $dh, $dirname)) {
    return scalar(grep { $_ ne "." && $_ ne ".." } readdir($dh)) == 0;
  }
  else {
    warn "Can't open directory: $dirname";
  }
}
#==============================================================================
sub getJobLinks
{
# Find symlinks pointing to tmp directories
  print "Getting symlinks for real jobs\n" if $OPT{verbose};
  my $cmd;
  if ($OPT{user}) {
    $cmd = "find /spin1/swarm/$OPT{user}/ -mindepth 1 -maxdepth 1 -type l 2>/dev/null";
  }
  else {
    $cmd = "find /spin1/swarm/ -mindepth 2 -maxdepth 2 -type l 2>/dev/null";
  }
  chomp(my $ret = `$cmd`);
  my $s;
  foreach my $link (split /\n/,$ret) {
    my $id = basename($link);
    if ($id=~/^\d+$/) { $s->{$id} = $link; } # only keep numerical symlinks
  }
  return $s;
}
#==============================================================================
sub getDevDirectories
{
# Find dev directories
  print "Getting dev directories\n" if $OPT{verbose};
  my $cmd;
  if ($OPT{user}) {
    $cmd = "find /spin1/swarm/$OPT{user}/ -mindepth 1 -maxdepth 1 -type d -name '^dev' 2>/dev/null";
  }
  else {
    $cmd = "find /spin1/swarm/ -mindepth 2 -maxdepth 2 -type d -name '^dev' 2>/dev/null";
  }
  chomp(my $ret = `$cmd`);
  my $s;
  foreach my $dir (split /\n/,$ret) {
    my $name = basename($dir);
    $s->{$name} = $dir;
  }
  return $s;
}
#==============================================================================
sub getOrphanDirectories
{
# Find tmp directories without any symlinks
  print "Getting orphan directories without symlink (this will take some time)\n" if $OPT{verbose};
  my $cmd;
  if ($OPT{user}) {
    $cmd = "find /spin1/swarm/$OPT{user}/ -mindepth 1 -maxdepth 1 -type d 2>/dev/null";
  }
  else {
    $cmd = "find /spin1/swarm/ -mindepth 2 -maxdepth 2 -type d 2>/dev/null";
  }
  chomp(my $ret = `$cmd`);
  my $s;
  DIR: foreach my $dir (split /\n/,$ret) {
    my $name = basename($dir);
    next DIR if ($name=~/^dev/);
    next DIR if ($name=~/^tmp/);
# Now turn around and find if there are any symlinks pointing to that file
    if ($OPT{user}) {
      $cmd = "find /spin1/swarm/$OPT{user}/ -mindepth 1 -maxdepth 1 -lname $dir 2>/dev/null";
    }
    else {
      $cmd = "find /spin1/swarm/ -mindepth 2 -maxdepth 2 -lname $dir 2>/dev/null";
    } 
    chomp(my $ret2 = `$cmd`);
    if (!$ret2) {
      $s->{$name} = $dir;
    }
  }
  return $s;
}
#==============================================================================
#sub getSingleoutFiles
#{
#  print "Getting singleout file info\n" if $OPT{verbose};
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
  print "Getting jobs\n" if $OPT{verbose};
  my $slurm = Slurm::new();
  my $jobs = $slurm->load_jobs();
  print "Getting job states\n" if $OPT{verbose};
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
sub clean_jobdirs
{
  my $joblink = getJobLinks();
  print "Walking through directories\n" if $OPT{verbose};
# Walk through all directories and determine if it and the associated batch file be removed
  DIR: foreach my $id (sort keys %{$joblink}) {
  
# Don't even bother unless the link is at least one day old 
    next DIR if ((time()-(stat($joblink->{$id}))[9]) < (86400*1));
    my $delete;
  
    my $user = basename(dirname($joblink->{$id}));
    printf "%-12s\t%d\t",$user,$id if $OPT{verbose};
  
# Real job id
    if (job_ended($id)) {
      $delete = 1;
    }
  
    print "DELETE!" if ($delete && $OPT{verbose});
    print "\n" if $OPT{verbose}; 
  }
}
#==============================================================================
sub clean_devdirs
{
  my $dev = getDevDirectories();
}
#==============================================================================
sub clean_orphandirs
{
  my $tmpdir = getOrphanDirectories();
  print "Walking through directories\n" if $OPT{verbose};
# Walk through all directories and determine if it and the associated batch file be removed
  DIR: foreach my $dir (sort keys %{$tmpdir}) {
 
# Don't even bother unless the directory is at least one day old 
    next DIR if ((time()-(stat($tmpdir->{$dir}))[9]) < (86400*1));
    my $delete;
  
    my $user = basename(dirname($tmpdir->{$dir}));
    printf "%-14s\t%-8s\t",$user,$dir if $OPT{verbose};

# Real job id?
    if ($dir =~ /^\d+$/) {
      if (job_ended($dir)) {
        $delete = 1;
      }
      else { print " --> ?" if $OPT{verbose}; }
    }

# Can't figure it out
    else {

# Is directory empty?
      if (emptydir($tmpdir->{$dir})) {
        print " --> EMPTY" if $OPT{verbose};
# Delete the empty directory if it is more than 1 day old
        if ((time()-(stat($tmpdir->{$dir}))[9]) > (86400*1)) {
          $delete = 1;
        }
      }
      else {
# Look in swarm log to see if it is on the verge of running
        chomp(my $stupid = `grep $dir /usr/local/logs/sbatch.log`);
        if ($stupid=~/ SUBM\[ERROR\]: $user /) {
          print " --> SUBM[ERROR]" if $OPT{verbose};
          $delete = 1 ;
        }
        elsif ($stupid=~/ SUBM\[(\d+)\]: $user /) {
          if (job_ended($1)) {
            $delete = 1;
          }
        }
        elsif ($stupid) {
          print " --> $stupid" if $OPT{verbose};
        }
        elsif ((time()-(stat($tmpdir->{$dir}))[9]) > (86400*3)) {
          print " --> DEVEL? $tmpdir->{$dir}" if $OPT{verbose};
          $delete = 1;
        }
        else {
          print " --> ? $tmpdir->{$dir}" if $OPT{verbose};
        }
      }
    }

    print "DELETE!" if ($delete && $OPT{verbose});
    print "\n" if $OPT{verbose}; 

# Really delete it
    if (($delete) && (!$OPT{debug})) {
      print "  deleting $tmpdir->{$dir} ...\n";
      system("rm -rf $tmpdir->{$dir}");
      if (-f "$tmpdir->{$dir}.batch") {
        print "  deleting $tmpdir->{$dir}.batch ...\n";
        system("rm -f $tmpdir->{$dir}.batch");
      }
    }
  }
}
#==============================================================================
sub job_ended
{
# Determine if a job has ended
  my $jobid = shift;
  my @z;
  if (not defined $jobs->{$jobid}) { # unknown to perl api
    my $x = getStatesForJob($jobid); 
    @z = (sort keys %{$x->{$jobid}});
  }
  else {
    @z = (sort keys %{$jobs->{$jobid}});
  }

  my $job_ended;
 
  if (@z) { # job states can be known
    my $list = join ",",@z;
    $list =~s/\s+//g;
    printf "%-30s\t",$list if ($OPT{verbose});

# if the job state is NOT an active state, then the Job is inactive -- we can delete it
    $job_ended = 1;
    foreach my $st ("CONFIGURING","COMPLETING","PENDING","RUNNING","RESIZING","SUSPENDED") {
      undef $job_ended if (grep /$st/,@z);
    }
  }
  else {
    printf "%-30s\t","" if $OPT{verbose};
  }
  return $job_ended;
}
#==============================================================================
