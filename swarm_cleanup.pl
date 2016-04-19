#!/usr/local/bin/perl

use lib "/usr/local/slurm/lib/site_perl/5.12.1/x86_64-linux-thread-multi";
use lib "/usr/local/slurm/lib/perl5/site_perl/5.18.2/x86_64-linux-thread-multi-ld";
use Storable;
use File::Basename;
use File::Path;
use Getopt::Long;
Getopt::Long::Configure("bundling");
use Slurm;
use FileHandle;
use POSIX qw(strftime);
use Date::Parse qw(str2time);
use strict;
$|=1;  # turns off output buffering

my $PAR;

$PAR->{minage} = 5; # files must be at least this many days old before doing anything
$PAR->{logfile} = "/usr/local/logs/swarm_cleanup.log";
$PAR->{store} = "/usr/local/logs/swarm.store";
$PAR->{orphan_min_age} = 60; # orphandirectories will only be evaluated if they are at least 60 days old
$PAR->{description} = <<EOF;

swarm_cleanup.pl -- remove old swarm temp files and directories

Actions are logged to $PAR->{logfile} 

options:

  -u,--user     run for a single user
  -j,--jobid    run for a single job
  --dev         remove devel directories
  --orphan      remove obsolete and orphaned directories
  --fail        remove submission failures
  --age         restrict deletion to directories at least
                this many days old (default = $PAR->{minage} days)

  -v,--verbose  be very chatty
  -q,--quiet    just show summary
  -s,--silent   report nothing
  --debug       run in debug mode
  -h,--help     print this message

  --orphan_min_age
                minimal days old a directory without a symlink needs to be
                in order to be deleted (default = $PAR->{orphan_min_age} days)

Last modification date Apr 19, 2016 (David Hoover)

EOF


my %OPT;  # options
set_options();

# Pull jobs from slurm cache via perl API
my $JOBS;

printSwarmUsage() unless($OPT{silent});

getCurrentJobs();

if    ($OPT{"clean-dev"})      { clean_devdirs(); }
elsif ($OPT{"clean-orphans"})  { clean_orphandirs(); }
elsif ($OPT{"clean-failures"}) { clean_failures(); }
else                           { clean_jobdirs(); }

unless ($OPT{silent}) {
  print "="x70,"\n";
  printf "Swarm directories scanned: %d\n",$PAR->{scanned_count};
  printf "Swarm directories deleted: %d\n",$PAR->{deleted_count};
  print "="x70,"\n";
}
# In order to see the effect of cleanup, we need to wait at least
# 60 seconds for the quota to refresh
sleep(70) unless ($OPT{debug});
printSwarmUsage() unless($OPT{silent});

#==============================================================================
sub set_options
{
  GetOptions(
    "u=s" => \$OPT{user}, # restrict to this user
    "user=s" => \$OPT{user}, # restrict to this user
    "j=s" => \$OPT{jobid}, # restrict to this jobid
    "jobid=s" => \$OPT{jobid}, # restrict to this jobid
    "dev" => \$OPT{"clean-dev"}, # only clean dev directories
    "orphan" => \$OPT{"clean-orphans"}, # only clean orphan directories
    "orphan_min_age" => \$OPT{orphan_min_age}, # minimal age of orphans to delete 
    "fail" => \$OPT{"clean-failures"}, # only clean orphan directories
    "debug" => \$OPT{debug}, # debug mode
    "h" => sub { print $PAR->{description}; exit; },
    "help" => sub { print $PAR->{description}; exit; },
    "v" => \$OPT{verbose},
    "verbose" => \$OPT{verbose},
    "age=i" => \$OPT{age},
    "s" => \$OPT{silent},
    "silent" => \$OPT{silent},
    "q" => \$OPT{quiet},
    "quiet" => \$OPT{quiet},
  ) || die($PAR->{description});

# Change minimum age  
  $PAR->{minage} = $OPT{age} if (defined $OPT{age});

  $PAR->{orphan_min_age} = $OPT{orphan_min_age} if (defined $OPT{orphan_min_age});

# Change verbosity
  if ($OPT{debug}) {
    if (!$OPT{silent} && !$OPT{quiet}) {
      $OPT{verbose} = 1;
    }
  }
  
# Translate user to uid
  $OPT{uid} = (getpwnam($OPT{user}))[2] if $OPT{user};
 
# Must be root 
  die("You must be root!\n") if ($<);

}
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
  my ($ex1,$depth);
  $depth = 2;
  if ($OPT{user}) {
    $ex1 = "$OPT{user}/";
    $depth = 1;
  }
  $cmd = "/bin/find /spin1/swarm/$ex1 -mindepth $depth -maxdepth $depth -type l 2>/dev/null";
  chomp(my $ret = `$cmd`);
  my $s;
  LINK: foreach my $link (split /\n/,$ret) {
    my $jobid = basename($link);
    next LINK if ($OPT{jobid} && ($jobid ne $OPT{jobid}));
    if ($jobid=~/^\d+$/) { $s->{$jobid} = $link; } # only keep numerical symlinks
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
    $cmd = "/bin/find /spin1/swarm/$OPT{user}/ -mindepth 1 -maxdepth 1 -type l 2>/dev/null";
  }
  else {
    $cmd = "/bin/find /spin1/swarm/ -mindepth 2 -maxdepth 2 -type l 2>/dev/null";
  }
  chomp(my $ret = `$cmd`);
  my $s;
  foreach my $link (split /\n/,$ret) {
    my $jobid = basename($link);
    if ($jobid=~/_FAIL$/) { $s->{$jobid} = $link; }
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
    $cmd = "/bin/find /spin1/swarm/$OPT{user}/ -mindepth 1 -maxdepth 1 -type d -name 'dev*' 2>/dev/null";
  }
  else {
    $cmd = "/bin/find /spin1/swarm/ -mindepth 2 -maxdepth 2 -type d -name 'dev*' 2>/dev/null";
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
# Find tmp directories without any symlinks, restricting the search to those directories 60 days or older
  print "Getting orphan directories without symlink (this will take some time)\n" if $OPT{verbose};
  my $cmd;
  if ($OPT{user}) {
    $cmd = "/bin/find /spin1/swarm/$OPT{user}/ -mindepth 1 -maxdepth 1 -type d -mtime +$PAR->{orphan_min_age} 2>/dev/null";
  }
  else {
    $cmd = "/bin/find /spin1/swarm/ -mindepth 2 -maxdepth 2 -type d -mtime +$PAR->{orphan_min_age} 2>/dev/null";
  }
print "$cmd\n" if $OPT{verbose};
  chomp(my $ret = `$cmd`);
  my $s;
  DIR: foreach my $dir (split /\n/,$ret) {
    my $name = basename($dir);
    next DIR if ($name=~/^dev/);
#    next DIR if ($name=~/^tmp/);
# Now turn around and find if there are any symlinks pointing to that file
    if ($OPT{user}) {
      $cmd = "/bin/find /spin1/swarm/$OPT{user}/ -mindepth 1 -maxdepth 1 -lname $dir -mtime +$PAR->{orphan_min_age} 2>/dev/null";
    }
    else {
      $cmd = "/bin/find /spin1/swarm/ -mindepth 2 -maxdepth 2 -lname $dir -mtime +$PAR->{orphan_min_age} 2>/dev/null";
    } 
print "$cmd\n" if $OPT{verbose};
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
  my $j = $slurm->load_jobs();
  print "Getting job states and ages since ending\n" if $OPT{verbose};
  JOB: foreach my $ref (@{$j->{job_array}}) {
    next JOB if ((defined $OPT{user}) && ($ref->{user_id} != $OPT{uid}));
    next JOB if ((defined $OPT{jobid}) && ($ref->{array_job_id} != $OPT{jobid}));
    next JOB unless ($ref->{array_job_id}); # only keep job arrays
# Accumulate the states
    my $state = $slurm->job_state_string($ref->{job_state});
    $JOBS->{$ref->{array_job_id}}{states}{$state} = 1;
    if (($ref->{end_time} > 0) && ($ref->{job_state} > 1)) {
# Find minimal value of days_since_ending
      $JOBS->{$ref->{array_job_id}}{days_since_ending}=minValue(((time()-$ref->{end_time})/86400),$JOBS->{$ref->{array_job_id}}{days_since_ending});
    }
  } 
  return;  
}
#==============================================================================
sub getStatesForJob
{
  my ($jobid) = shift;
  my $cmd = "/usr/local/slurm/bin/sacct -j $jobid --format=JobID,State,End --noheader --parsable2";
  $cmd .= " -u $OPT{user}" if $OPT{user};
  chomp(my $ret = `$cmd`);
  if ($OPT{verbose} && $OPT{jobid}) {
    print "cmd = $cmd\n";
    print "$ret\n";
  }
  my $hr;
  foreach my $line (split /\n/,$ret) {
    if ($line=~/^(\d+)_[^\|]+\|(\w+).*?\|(\S+)$/) {
      my ($jobid,$state) = ($1,$2);
      my $end = str2time($3);
# Accumulate the states
      if ($OPT{verbose} && $OPT{jobid}) {
         print "state = $state\n";
      }
      $hr->{$jobid}{states}{$state} = 1;
# Find minimal value of days_since_ending
      $JOBS->{$jobid}{days_since_ending}=minValue(((time()-$end)/86400),$JOBS->{$jobid}{days_since_ending});
    }
# Swarm of a single job
    elsif ($line=~/^(\d+)\|(\w+).*?\|(\S+)$/) {
      my ($jobid,$state) = ($1,$2);
      my $end = str2time($3);
# Accumulate the states
      if ($OPT{verbose} && $OPT{jobid}) {
         print "state = $state\n";
      }
      $hr->{$jobid}{states}{$state} = 1;
# Find minimal value of days_since_ending
      $JOBS->{$jobid}{days_since_ending}=minValue(((time()-$end)/86400),$JOBS->{$jobid}{days_since_ending});
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
  DIR: foreach my $jobid (sort keys %{$joblink}) {
  
# Don't even bother unless the link is at least one day old 
    my $age = ((time()-(stat($joblink->{$jobid}))[9])/86400);
    my $user = basename(dirname($joblink->{$jobid}));

# Because we already know the job id, and by definition if the job is not available via the
# Slurm Perl API then the job is completed, all we have to check is whether the job is
# defined in the jobarray.
    #if ($s->{ended} == -1) {
    #  print_action({user=>$user,dir=>$jobid,path=>$joblink->{$jobid},delete=>0,link=>1,age=>$age});
    #}
    #elsif ($s->{ended} == 1) {
    if (not defined $JOBS->{$jobid}) { # unknown to perl api, assumed completed
      my $s = get_state($jobid,$age); # Perl API may fail, and sacct may give nonsense
      if ($s->{ended} == 1) {
# override the $age if the days_since_ending is known
        my $dse = $JOBS->{$jobid}{days_since_ending} if (defined $JOBS->{$jobid}{days_since_ending});
        print_action({state=>$s->{state},ended=>$s->{ended},user=>$user,dir=>$jobid,path=>$joblink->{$jobid},delete=>1,link=>1,age=>$age,dse=>$dse});
      }
      elsif ($s->{ended} == 0) {
        print_action({state=>$s->{state},ended=>$s->{ended},user=>$user,dir=>$jobid,path=>$joblink->{$jobid},delete=>0,link=>1,age=>$age});
      } 
      else {
        print_action({ended=>$s->{ended},user=>$user,dir=>$jobid,path=>$joblink->{$jobid},delete=>0,link=>1,age=>$age});
      }
    }
    else {
      my $state = join ',',(sort keys %{$JOBS->{$jobid}{states}});
      my $dse = $JOBS->{$jobid}{days_since_ending} if (defined $JOBS->{$jobid}{days_since_ending});
#+------------------------------------------------------------------------------
#| STUPID STUPID STUPID
#| 
#|   Not all subjobs in a job array appear in Slurm Perl API, so the 
#|   days_since_ending value and states are incorrect.  ALL jobs must be
#|   pulled from sacct.  Yuck.
#+------------------------------------------------------------------------------
      print_action({state=>$state,ended=>0,user=>$user,dir=>$jobid,path=>$joblink->{$jobid},delete=>0,link=>1,age=>$age,dse=>$dse});
    }
  }
}
#==============================================================================
sub clean_failures
{
  my $fail = getFailLinks();
  print "Walking through directories\n" if $OPT{verbose};
# Walk through all directories and determine if it and the associated batch file be removed
  DIR: foreach my $jobid (sort keys %{$fail}) {
  
# Don't even bother unless the link is at least one day old 
    my $age = ((time()-(stat($fail->{$jobid}))[9])/86400);
    my $user = basename(dirname($fail->{$jobid}));
    print_action({user=>$user,dir=>$jobid,path=>$fail->{$jobid},delete=>1,link=>1,age=>$age});
  }
}
#==============================================================================
sub clean_devdirs
{
  my $dev = getDevDirectories();
  print "Walking through directories\n" if $OPT{verbose};
# Walk through all directories and determine if it and the associated batch file be removed
  DIR: foreach my $jobid (sort keys %{$dev}) {
  
# Don't even bother unless the link is at least one day old 
    my $age = ((time()-(stat($dev->{$jobid}))[9])/86400);
    my $user = basename(dirname($dev->{$jobid}));
    print_action({user=>$user,dir=>$jobid,path=>$dev->{$jobid},delete=>1,link=>0,age=>$age});
  }
}
#==============================================================================
sub findJobidsFromStore
{
  my $HR = retreive_old_data();
  my $old;
  foreach my $user (sort keys %{$HR->{swarm}}) {
    foreach my $date (sort keys %{$HR->{swarm}->{$user}}) {
      foreach my $tag (sort keys %{$HR->{swarm}->{$user}->{$date}}) { 
        $old->{$tag}->{user}=$user;
        $old->{$tag}->{jobid}=$HR->{swarm}->{$user}->{$date}->{$tag}->{jobid};
      }
    }
  }
  return $old;
}
#==================================================================================================
sub retreive_old_data
{
  open(FH, ">$PAR->{store}.lck")           or die "can't create lock $PAR->{store}.lck $!";
  flock(FH, 2)                        or die "can't flock $PAR->{store}.lck $!";
  my $hr = retrieve($PAR->{store}) if (-f $PAR->{store});
  close(FH)                           or die "can't remove lock $PAR->{store}.lck $!";
  unlink "$PAR->{store}.lck";
  return $hr;
}
#==================================================================================================
sub clean_orphandirs
{
  my $tmpdir = getOrphanDirectories();
  my $taghash = findJobidsFromStore();
  print "Walking through directories\n" if $OPT{verbose};
# Walk through all directories and determine if it and the associated batch file be removed
  DIR: foreach my $dir (sort keys %{$tmpdir}) {
 
# Don't even bother unless the directory is at least one day old 
    my $age = ((time()-(stat($tmpdir->{$dir}))[9])/86400);
    my $delete;
  
    my $user = basename(dirname($tmpdir->{$dir}));

# Real job id?
    if ($dir =~ /^\d+$/) {
      my $s = get_state($dir,$age);
      if ($s->{ended} == 1) {
        print_action({state=>$s->{state},ended=>$s->{ended},user=>$user,dir=>$dir,path=>$tmpdir->{$dir},delete=>1,link=>0,age=>$age});
      }
      elsif ($s->{ended} == 0) {
        print_action({state=>$s->{state},ended=>$s->{ended},user=>$user,dir=>$dir,path=>$tmpdir->{$dir},delete=>0,link=>0,age=>$age});
      } 
      else {
        print_action({user=>$user,dir=>$dir,path=>$tmpdir->{$dir},delete=>0,link=>0,age=>$age});
      }
    }

# Can't figure it out
    else {

# Is directory empty?
      if (emptydir($tmpdir->{$dir})) {
        print_action({user=>$user,dir=>$dir,path=>$tmpdir->{$dir},delete=>1,link=>0,age=>$age,empty=>1});
      }
      else {
# The directory tag is known from the sbatch logfiles
        if ($taghash->{$dir}->{user} && ($taghash->{$dir}->{user} eq $user)) {
          if ($taghash->{$dir}->{jobid} eq 'ERROR') {
            print_action({state=>'SUBM[ERROR]',ended=>1,user=>$user,dir=>$dir,path=>$tmpdir->{$dir},delete=>1,link=>0,age=>$age});
          }
          elsif ($taghash->{$dir}->{jobid} =~ /^(\d+)$/) {
            my $s = get_state($1,$age);
            if ($s->{ended} == 1) {
              print_action({state=>$s->{state},ended=>$s->{ended},user=>$user,dir=>$dir,path=>$tmpdir->{$dir},delete=>1,link=>0,age=>$age});
            }
            elsif ($s->{ended} == 0) {
              print_action({state=>$s->{state},ended=>$s->{ended},user=>$user,dir=>$dir,path=>$tmpdir->{$dir},delete=>0,link=>0,age=>$age});
            }
            else {
              print_action({user=>$user,dir=>$dir,path=>$tmpdir->{$dir},delete=>0,link=>0});
            }
          }
        }
# The directory is just too old, come on now
        elsif ($age > $PAR->{orphan_min_age}) {
          print_action({state=>'TOO OLD',user=>$user,dir=>$dir,path=>$tmpdir->{$dir},delete=>1,link=>0,age=>$age});
        }
        else {
          print_action({user=>$user,dir=>$dir,path=>$tmpdir->{$dir},delete=>0,link=>0,age=>$age});
        } 
      }
    }
  }
}
#==============================================================================
sub get_state
{
# Determine if a job has ended
  my ($jobid,$age) = @_;

  my $hr;
  $hr->{ended} = -1; # unknown
  return $hr if ($age < $PAR->{minage}); # don't bother unless dir is old enough

  my @z;
  if (not defined $JOBS->{$jobid}) { # unknown to perl api
    my $x = getStatesForJob($jobid); 
    @z = (sort keys %{$x->{$jobid}{states}});
  }
  else {
    @z = (sort keys %{$JOBS->{$jobid}{states}});
  }
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
  $PAR->{scanned_count}++;

# Has the job ended?
  my $end;
  if (defined $hr->{ended}) {
    if ($hr->{ended} == 0) { $end = "Q/R"; }
    elsif ($hr->{ended} == 1) { $end = "END"; }
    elsif ($hr->{ended} == -1) { $end = "SKP"; }
    else { $end = "UNK"; }
  }
  else { 
    #if ($OPT{"clean-dev"} || $OPT{"clean-failures"}) {
    if ($OPT{"clean-dev"}) {
      $end = "DEV"; 
    }
    elsif ($OPT{"clean-failures"}) {
      $end = "FAIL";
    }
    else {
      $end = "UNK"; 
    }
  }

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
    if ($hr->{delete} == 1) { 
# Do not delete a job whose directory is less than 7 days old and whose most recent subjob ended less than 7 days ago
      if ($hr->{age} > $PAR->{minage}) {
        if (not defined $hr->{dse}) {
          $action = "DELETE";
        }
        elsif ($hr->{dse} > $PAR->{minage}) {
          $action = "DELETE";
        }
        else { $action = "KEEP"; }
      }
      else { $action = "KEEP"; }
    }
    else { $action = "KEEP"; }
  }
  else {
    $action = "UNK";
  }

  if ((!$OPT{silent}) && (!$OPT{quiet})){
    unless ($PAR->{header}) {
      printf("%-16s  %-16s  %-4s  %-4s  %-3s  %-3s : %-6s  %s\n",
        "user",
        "basename",
        "STA",
        "AGE", 
        "DSE", 
        "TYP",
        "ACTION",
        "EXTRA",
      );
      print "="x80,"\n";
      $PAR->{header} = 1;
    }

    if ((not defined $hr->{dse}) || ($end eq 'SKP')) {
      $hr->{dse} = '---';
    }
    else {
      $hr->{dse} = sprintf("%3.1f",$hr->{dse});
    }
  
    my $line = sprintf("%-16s  %-16s  %-4s  %4.1f  %3s  %-3s : %-6s  %s\n",
      $hr->{user},
      $hr->{dir},
      $end,
      $hr->{age},
      $hr->{dse},
      $type,
      $action,
      $hr->{state},
    );
  
      print $line;
  }

# Now really delete stuff
  if ($action eq 'DELETE') {
    if ($OPT{"clean-dev"} || $OPT{"clean-failures"} || $OPT{"clean-orphans"}) {
      if (-d $hr->{path}) {
        $PAR->{deleted_count}++;
        print "  rm -rf $hr->{path}\n" if ($OPT{verbose});
        if (!$OPT{debug}) {
          if (rmtree($hr->{path})) { appendToFile($PAR->{logfile},(strftime("%F %T",(localtime(time))[0 .. 5]))." ".$hr->{path}."\n"); }
        }
      }
    }
    else {
      if (-l $hr->{path}) {
        my $real_dir = readlink($hr->{path});
        if (-d $real_dir) {
          print "  rm -f $hr->{path}\n" if $OPT{verbose};
          print "  rm -rf $real_dir\n" if $OPT{verbose};
          $PAR->{deleted_count}++;
          if (!$OPT{debug}) {
            if (rmtree($hr->{path})) { appendToFile($PAR->{logfile},(strftime("%F %T",(localtime(time))[0 .. 5]))." ".$hr->{path}."\n"); }
            if (rmtree($real_dir)) { appendToFile($PAR->{logfile},(strftime("%F %T",(localtime(time))[0 .. 5]))." ".$real_dir."\n"); }
          }
        }
      }
    }
  }
}
#==============================================================================
sub appendToFile
# Open file with append, write contents, flush and close.  'nuff said.
{
  my ($file,$contents) = @_;
  my $fh = FileHandle->new($file,">>");
  print $fh $contents;
  $fh->flush;
  $fh->close;
}
#==============================================================================
sub maxValue
{
  my ($a,$b) = @_;
  if ((defined $a) && (defined $b)) {
    if ($a < $b) { return $b; }
    else { return $a; }
  }
  elsif ((defined $b) && (not defined $a)) { return $b; }
  elsif ((defined $a) && (not defined $b)) { return $a; }
}
#==============================================================================
sub minValue
{
  my ($a,$b) = @_;
  if ((defined $a) && (defined $b)) {
    if ($a > $b) { return $b; }
    else { return $a; }
  }
  elsif ((defined $b) && (not defined $a)) { return $b; }
  elsif ((defined $a) && (not defined $b)) { return $a; }
}
#==============================================================================
sub printSwarmUsage
{
  use DBI;
  my $dbh = DBI->connect("DBI:mysql:;mysql_read_default_group=helixmon;mysql_read_default_file=/usr/local/etc/my.cnf;mysql_connect_timeout=10",undef,undef,{RaiseError=>0});
  my $sql = "SELECT * FROM quota_spin1 WHERE volume = 'swarm'";
  my $sth = $dbh->prepare($sql);
  $sth->execute;
  my $l = $sth->fetchrow_hashref();
  my $string = sprintf("/swarm usage: %6.2f GB (%4.1f%%), %7d files (%4.1f%%)\n",
      ( $l->{Dusage}/1024/1024 ),
      ( ($l->{Dusage}/$l->{Dquota})*100 ),
      ( $l->{Fusage} ),
      ( ($l->{Fusage}/$l->{Fquota})*100 ),
  );
  $sth->finish;
  $dbh->disconnect();
  print $string;
}
#============================================================================================================================
