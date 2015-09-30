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

  -u,--user    run for a single user
  --dev       remove devel directories
  --orphans   remove obsolete and orphaned directories
  --fail     remove submission failures

  -l,--log     log actions to this file
  -v,--verbose  be chatty
  --debug     run in debug mode (prevents -o option)
  -h,--help     print this message

Last modification date Sep 30, 2015 (David Hoover)

EOF

$|=1;  # turns off output buffering

my $PAR;
my %OPT;  # options
GetOptions(
  "u=s" => \$OPT{user}, # restrict to this user
  "user=s" => \$OPT{user}, # restrict to this user
  "l=s" => \$OPT{log}, # log actions
  "log=s" => \$OPT{log}, # log actions
  "dev" => \$OPT{"clean-dev"}, # only clean dev directories
  "orphan" => \$OPT{"clean-orphans"}, # only clean orphan directories
  "fail" => \$OPT{"clean-failures"}, # only clean orphan directories
  "debug" => \$OPT{debug}, # debug mode
  "h" => sub { print $description; exit; },
  "help" => sub { print $description; exit; },
  "v" => \$OPT{verbose},
  "verbose" => \$OPT{verbose},
);

$OPT{verbose} = 1 if $OPT{debug};

my $jobs = getCurrentJobs();

if ($OPT{"clean-dev"}) {
  clean_devdirs();
}
elsif ($OPT{"clean-orphans"}) {
  clean_orphandirs();
}
elsif ($OPT{"clean-failures"}) {
  clean_failures();
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
sub getFailLinks
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
    if ($id=~/_FAIL$/) { $s->{$id} = $link; }
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
    $cmd = "find /spin1/swarm/$OPT{user}/ -mindepth 1 -maxdepth 1 -type d -name 'dev*' 2>/dev/null";
  }
  else {
    $cmd = "find /spin1/swarm/ -mindepth 2 -maxdepth 2 -type d -name 'dev*' 2>/dev/null";
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
sub getCurrentJobs
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
  
  return $hr;
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
    my $age = ((time()-(stat($joblink->{$id}))[9])/86400);
    my $user = basename(dirname($joblink->{$id}));
   # my $s = get_state($id);

# Because we already know the job id, and by definition if the job is not available via the
# Slurm Perl API then the job is completed, all we have to check is whether the job is
# defined in the jobarray.
    #if ($s->{ended} == -1) {
    #  print_action({user=>$user,dir=>$id,path=>$joblink->{$id},delete=>0,link=>1,age=>$age});
    #}
    #elsif ($s->{ended} == 1) {
    if (not defined $jobs->{$id}) { # unknown to perl api, assumed completed
      #print_action({state=>$s->{state},ended=>$s->{ended},user=>$user,dir=>$id,path=>$joblink->{$id},delete=>1,link=>1,age=>$age});
      print_action({ended=>1,user=>$user,dir=>$id,path=>$joblink->{$id},delete=>1,link=>1,age=>$age});
    }
   # elsif ($s->{ended} == 0) {
    else {
      my $state = join ',',(sort keys %{$jobs->{$id}});
      #print_action({state=>$s->{state},ended=>$s->{ended},user=>$user,dir=>$id,path=>$joblink->{$id},delete=>0,link=>1,age=>$age});
      print_action({state=>$state,ended=>0,user=>$user,dir=>$id,path=>$joblink->{$id},delete=>0,link=>1,age=>$age});
    }
  }
}
#==============================================================================
sub clean_failures
{
  my $fail = getFailLinks();
  print "Walking through directories\n" if $OPT{verbose};
# Walk through all directories and determine if it and the associated batch file be removed
  DIR: foreach my $id (sort keys %{$fail}) {
  
# Don't even bother unless the link is at least one day old 
    my $age = ((time()-(stat($fail->{$id}))[9])/86400);
    my $user = basename(dirname($fail->{$id}));
    print_action({user=>$user,dir=>$id,path=>$fail->{$id},delete=>1,link=>1,age=>$age});
  }
}
#==============================================================================
sub clean_devdirs
{
  my $dev = getDevDirectories();
  print "Walking through directories\n" if $OPT{verbose};
# Walk through all directories and determine if it and the associated batch file be removed
  DIR: foreach my $id (sort keys %{$dev}) {
  
# Don't even bother unless the link is at least one day old 
    my $age = ((time()-(stat($dev->{$id}))[9])/86400);
    my $user = basename(dirname($dev->{$id}));
    print_action({user=>$user,dir=>$id,path=>$dev->{$id},delete=>1,link=>0,age=>$age});
  }
}
#==============================================================================
sub clean_orphandirs
{
  my $tmpdir = getOrphanDirectories();
  print "Walking through directories\n" if $OPT{verbose};
# Walk through all directories and determine if it and the associated batch file be removed
  DIR: foreach my $dir (sort keys %{$tmpdir}) {
 
# Don't even bother unless the directory is at least one day old 
    my $age = ((time()-(stat($tmpdir->{$dir}))[9])/86400);
    my $delete;
  
    my $user = basename(dirname($tmpdir->{$dir}));

# Real job id?
    if ($dir =~ /^\d+$/) {
      my $s = get_state($dir);
      if ($s->{ended} == -1) {
        print_action({user=>$user,dir=>$dir,path=>$tmpdir->{$dir},delete=>0,link=>0,age=>$age});
      }
      elsif ($s->{ended} == 1) {
        print_action({state=>$s->{state},ended=>$s->{ended},user=>$user,dir=>$dir,path=>$tmpdir->{$dir},delete=>1,link=>0,age=>$age});
      }
      elsif ($s->{ended} == 0) {
        print_action({state=>$s->{state},ended=>$s->{ended},user=>$user,dir=>$dir,path=>$tmpdir->{$dir},delete=>0,link=>0,age=>$age});
      } 
    }

# Can't figure it out
    else {

# Is directory empty?
      if (emptydir($tmpdir->{$dir})) {
        print_action({user=>$user,dir=>$dir,path=>$tmpdir->{$dir},delete=>1,link=>0,age=>$age,empty=>1});
      }
      else {
# Look in swarm log to see if it is on the verge of running
        chomp(my $stupid = `grep $dir /usr/local/logs/sbatch.log`);
        if ($stupid=~/ SUBM\[ERROR\]: $user /) {
          print_action({state=>'SUBM[ERROR]',ended=>1,user=>$user,dir=>$dir,path=>$tmpdir->{$dir},delete=>1,link=>0,age=>$age});
        } 
        elsif ($stupid=~/ SUBM\[(\d+)\]: $user /) {
          my $s = get_state($1);
          if ($s->{ended} == -1) {
            print_action({user=>$user,dir=>$dir,path=>$tmpdir->{$dir},delete=>0,link=>0});
          }
          elsif ($s->{ended} == 1) {
            print_action({state=>$s->{state},ended=>$s->{ended},user=>$user,dir=>$dir,path=>$tmpdir->{$dir},delete=>1,link=>0,age=>$age});
          }
          elsif ($s->{ended} == 0) {
            print_action({state=>$s->{state},ended=>$s->{ended},user=>$user,dir=>$dir,path=>$tmpdir->{$dir},delete=>0,link=>0,age=>$age});
          }
        }
        elsif ($stupid) {
          print_action({state=>$stupid,ended=>0,user=>$user,dir=>$dir,path=>$tmpdir->{$dir},delete=>0,link=>0,age=>$age});
        }
        else {
          print_action({user=>$user,dir=>$dir,path=>$tmpdir->{$dir},delete=>0,link=>0,age=>$age});
        } 
      }
    }
  }
}

# Really delete it
#    if (($delete) && (!$OPT{debug})) {
#      print "  deleting $tmpdir->{$dir} ...\n";
#      system("rm -rf $tmpdir->{$dir}");
#      if (-f "$tmpdir->{$dir}.batch") {
#        print "  deleting $tmpdir->{$dir}.batch ...\n";
#        system("rm -f $tmpdir->{$dir}.batch");
#      }
#    }
#==============================================================================
sub get_state
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
  my $hr;
  $hr->{ended} = -1; # unknown
  if (@z) { # job states can be known
    my $list = join ",",@z;
    $list =~s/\s+//g;
    $hr->{state} = $list;

# if the job state is NOT an active state, then the Job is inactive -- we can delete it
    $hr->{ended} = 1;
    foreach my $st ("CONFIGURING","COMPLETING","PENDING","RUNNING","RESIZING","SUSPENDED") {
      if (grep /$st/,@z) {
        $hr->{ended} = 0;
        return $hr;
      }
    }
  }
  return $hr;
}
#==============================================================================
sub print_action
{
  my $hr = shift;


# Has the job ended?
  my $end;
  if (defined $hr->{ended}) {
    if ($hr->{ended} == 0) { $end = "Q/R"; }
    else { $end = "END"; }
  }
  else { $end = "UNK"; }

# What type is the file?
  my $type;
  if (defined $hr->{link}) {
    if ($hr->{link} == 1) { $type = "LNK"; }
    else { $type = "DIR"; }
  }
  else { $type = "UNK"; }

# Can the directory/link etc. be deleted?
  my $action;
  if (defined $hr->{delete}) {
    if ($hr->{delete} == 1) { $action = "DELETE"; }
    else { $action = "KEEP"; }
  }
  else { $action = "UNK"; }

  unless ($PAR->{header}) {
    printf("%-16s %-10s  %-3s  %-3s  %-3s : %-6s  %s\n",
      "user",
      "basename",
      "STA",
      "AGE", 
      "TYP",
      "ACTION",
      "EXTRA",
    );
    print "="x70,"\n";
    $PAR->{header} = 1;
  }
      
  printf("%-16s %-10s  %-3s  %.1f  %-3s : %-6s  %s\n",
    $hr->{user},
    $hr->{dir},
    $end,
    $hr->{age},
    $type,
    $action,
    $hr->{state},
  );
}
#==============================================================================
