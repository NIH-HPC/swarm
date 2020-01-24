#!/usr/local/bin/perl

use strict;
use Bit::Vector;
use Config::IniFiles;
use Memory::Usage;
use Data::Dumper;
use Date::Parse qw(str2time);
use HPCNIH::Util::PrintColors;
use HPCNIH::Util::TimeTools;
use HPCNIH::Util::EmailTools;
use POSIX qw(setsid strftime ceil);
use DBI;
use FileHandle;
use FindBin;
use File::Spec;
use WWW::Curl::Easy;
use URI::Escape;
use JSON;
use Statistics::Basic qw(:all);
use HPCNIH::Staff::MySQL::Catalog;

use strict;

my %OPT;
my %PAR;
my %ERR;

$PAR{delete_index} = "/usr/local/logs/swarm_cleanup.idx"; # index of deleted swarm directories
$PAR{logfile} = "/usr/local/logs/swarm_cleanup.log"; # logfile
$PAR{CONFIG} = Config::IniFiles->new( -file => "/usr/local/etc/my.cnf" );
$PAR{slurm_cnf_group} = "dashboardSlurm"; # the group name for the slurm connection in /usr/local/etc/my.cnf, probably slave
$PAR{'delete-age'} = 7; # how many days past finishing should we delete the directory?

getOptions();

eval {
# Catch signals
  local $SIG{ALRM} = sub { die " TIMEOUT: $OPT{timeout} seconds elapsed" };
  local $SIG{INT} = sub { die " INT: don't interrupt me!" };
  local $SIG{KILL} = sub { die " KILL: arrggg!" };

# Set the alarm to go off -- do nothing if $OPT{timeout} is undefined
  alarm $OPT{timeout};

#--------------------------------------------------------------------------------------------------
# Stuff that needs a timeout goes here
#--------------------------------------------------------------------------------------------------

  $PAR{message} = printSwarmUsage();

  run_cleanup();

  $PAR{message} .= "======================================================================\n";
  $PAR{message} .= sprintf "Swarm directories scanned: %d\n",$PAR{tally}{active}{found}+$PAR{tally}{inactive}{found}+$PAR{tally}{unknown}{found};
  $PAR{message} .= sprintf "Swarm directories deleted: %d\n",$PAR{tally}{inactive}{deleted}+$PAR{tally}{unknown}{deleted};
  $PAR{message} .= "======================================================================\n";

  print_tally();

  unless ($OPT{'dry-run'}) {
    while ((time()-$PAR{NOW}) <= 360) {
      sleep 10;
    }
    $PAR{message} .= printSwarmUsage();
  }

  if ($OPT{emailTo}) {
    sendEmail(subject=>"swarm_cleanup.log",message=>$PAR{message},emailTo=>$OPT{emailTo},Bcc=>$OPT{Bcc},debug=>$OPT{'dry-run'},provenance=>1);
  }
  else {
    print $PAR{message};
  }

#--------------------------------------------------------------------------------------------------
# Done
#--------------------------------------------------------------------------------------------------

  alarm 0;
  1;  # default return value from eval
};

# Take action if either an error is given or the timeout was reached
if ( $@ ) {
  print STDERR $@;
  if ($OPT{emailTo}) {
    sendEmail(subject=>"ERROR: $0",message=>$@,emailTo=>"hooverdm",debug=>$OPT{'dry-run'},provenance=>1);
  }
  exit 1;
}
#==================================================================================================
sub run_cleanup
{
  $PAR{NOW} = time();

  $PAR{delete_cutoff} = $PAR{NOW} - (86400*$PAR{"delete-age"});

  $PAR{delete_index} = "swarm_cleanup.idx.dry-run.$PAR{NOW}" if ($OPT{'dry-run'});

# Get arrays
  get_arrays();
  foreach my $j (sort keys %{$PAR{arrays}}) {
    my $x = $PAR{arrays}->{$j};
    if ((not defined $PAR{min_submit_time}) || ($x->{create_time} < $PAR{min_submit_time})) {
      $PAR{min_submit_time} = $x->{create_time};
    }
  }
  $PAR{max_days_ago} = ceil(($PAR{NOW} - $PAR{min_submit_time})/86400);

# Find swarms from various logs
  parse_swarm_index();
  parse_swarm_logs();
  parse_sbatch_logs();
  read_delete_index();

  open DELETED, ">>$PAR{delete_index}";
  foreach my $t (sort keys %{$PAR{swarms}}) {
    next if ($PAR{deleted}->{$t});
    if ($PAR{swarms}->{$t}{jobid}) {                                  # jobid is known
      my $j = $PAR{swarms}->{$t}{jobid};
      if ($PAR{arrays}->{$j}) {                                       # array for jobid is known
# array is active
        if ($PAR{arrays}->{$j}{active}) {
          if ((-d "/spin1/swarm/$PAR{swarms}->{$t}{user}/$t") && (-d "/spin1/swarm/$PAR{swarms}->{$t}{user}/$PAR{swarms}->{$t}{jobid}")) {
            print "$t $j ACTIVE   $PAR{swarms}->{$t}{user}\n" if ($OPT{verbose} > 2);
            $PAR{tally}{active}{found}++;
          }
          else {
            $PAR{tally}{active}{notfound}++;
          }
        }
# array is inactive
        else {
          print "$t $j INACTIVE $PAR{swarms}->{$t}{user}\n" if ($OPT{verbose} > 2);
          if ((-d "/spin1/swarm/$PAR{swarms}->{$t}{user}/$t") && (-d "/spin1/swarm/$PAR{swarms}->{$t}{user}/$PAR{swarms}->{$t}{jobid}")) {
            if ($PAR{swarms}->{$t}{finish_time} < $PAR{delete_cutoff}) {
              system("rm -rf /spin1/swarm/$PAR{swarms}->{$t}{user}/$t") unless ($OPT{'dry-run'});
              system("rm -rf /spin1/swarm/$PAR{swarms}->{$t}{user}/$PAR{swarms}->{$t}{jobid}") unless ($OPT{'dry-run'});
              $PAR{tally}{inactive}{deleted}++;
              $PAR{tally}{inactive}{found}++;
              if (($OPT{'dry-run'}) || ((!-d "/spin1/swarm/$PAR{swarms}->{$t}{user}/$t") && (!-d "/spin1/swarm/$PAR{swarms}->{$t}{user}/$PAR{swarms}->{$t}{jobid}"))) {
                print DELETED "$PAR{swarms}->{$t}{create_time},$PAR{swarms}->{$t}{finish_time},".time().",$PAR{swarms}->{$t}{user},$t,$PAR{swarms}->{$t}{jobid}\n";
              }
            }
            else {
              $PAR{tally}{inactive}{found}++;
            }
          }
          else {
            $PAR{tally}{inactive}{notfound}++;
          }
        }
      }
# array is missing from jobs table (this can happen if a swarm is read from logfiles before it appears in the slurmacct database)
      else {
        print "$t $j MISSING  $PAR{swarms}->{$t}{user}\n" if ($OPT{verbose} > 2);
        $PAR{tally}{missing}++;
      }
    }
# array was never run, no jobid
    else {
      print "$t    UNKNOWN  $PAR{swarms}->{$t}{user}\n" if ($OPT{verbose} > 2);
      if (-d "/spin1/swarm/$PAR{swarms}->{$t}{user}/$t") {
        if ($PAR{swarms}->{$t}{create_time} < $PAR{delete_cutoff}) {
          $PAR{tally}{unknown}{deleted}++;
          $PAR{tally}{unknown}{found}++;
          system("rm -rf /spin1/swarm/$PAR{swarms}->{$t}{user}/$t") unless ($OPT{'dry-run'});
          if (($OPT{'dry-run'}) || (!-d "/spin1/swarm/$PAR{swarms}->{$t}{user}/$t")) {
            print DELETED "$PAR{swarms}->{$t}{create_time},0,".time().",$PAR{swarms}->{$t}{user},$t,0\n";
          }
        }
        else {
          $PAR{tally}{unknown}{found}++;
        }
      }
      else {
        $PAR{tally}{unknown}{notfound}++;
      }
    } 
  }
  close DELETED;
}
#==================================================================================================
sub read_delete_index
{
  return unless (-r $PAR{delete_index});
  open FILE, "<$PAR{delete_index}";
  while (<FILE>) {

# 12345678,cifellojp,YdK7sdy4ud,35641331
    chomp;
    my ($c,$f,$d,$u,$t,$j) = split /,/,$_;
    next unless $c;
    next unless $u;
    next unless $t;
    $PAR{deleted}->{$t}{create_time}=$c;
    $PAR{deleted}->{$t}{user}=$u;
    $PAR{deleted}->{$t}{tempname}=$t;
    $PAR{deleted}->{$t}{finish_time}=$f if ($f > 0);
    $PAR{deleted}->{$t}{jobid}=$j if ($j > 0);
  }
  close FILE;
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
    'verbose=i' => \$OPT{verbose},
    'v=i' => \$OPT{verbose},
    'delete-age=i' => \$OPT{"delete-age"},
    'u=s' => \$OPT{user},
    'user=s' => \$OPT{user},
    'email=s'=> \$OPT{emailTo},
    'bcc=s' => \$OPT{Bcc},
    'timeout=i' => \$OPT{timeout},
    'dry-run' => \$OPT{'dry-run'},
  ) || printOptions();

  printOptions() if $OPT{help};

  print STDERR "Running in debug mode\n" if $OPT{debug};
  $OPT{verbose} = 2 if ($OPT{debug} && not defined $OPT{verbose});

  $PAR{'delete-age'} = $OPT{'delete-age'} if ($OPT{'delete-age'});
}
#==================================================================================================
sub printOptions
{
  my $msg = shift;
  warn "\n$msg\n" if $msg;

  print STDERR <<EOF;

Usage: $0 [ options ]

  Delete old swarms from /spin1/swarm

Options:

  -h, --help           print options list
  -d, --dry-run        don't actually delete things, run in --dry-run mode
  -v, --verbose        increase verbosity level (0,1,2,3)

  --delete-age         number of days before deleting swarm (default = $PAR{'delete-age'})

  -u, --user           only for this user

  --email
  --bcc

  --timeout           

Description:

  Delete old swarms from /spin1/swarm 

Logfile key:

  Tally:

  f -- found
  d -- deleted

    a:     active (pending or running)
    i:     inactive (finished)
    u:     unknown (swarm not submitted to slurm)
    rss:   current memory usage

Last modification date: 08 Oct 2019 (David Hoover)

    sprintf("f: a=%d i=%d u=%d d: i=%d u=%d rss=%d (%d seconds)", 
EOF
  
  exit;
}
#==================================================================================================
sub parse_swarm_index
{
  my $f = "/usr/local/logs/swarm_tempdir.idx";
  if (open INDEXFILE, "<$f") {
    print "reading $f\n" if ($OPT{verbose} > 2);
    while (<INDEXFILE>) {
      chomp(my $line = $_);
      LINE: while ($line=~/(\d{10}),([^,]+),(\w{10}),(\d+),([12])/g) { # Hiccups in the write performance of /spin1
        my ($time,$user,$t) = ($1,$2,$3);
        next LINE if ($time < $PAR{min_submit_time});
        next LINE if (($OPT{user}) && ($user ne $OPT{user}));
        $PAR{swarms}->{$t}{tempname}=$t;
        $PAR{swarms}->{$t}{create_time}=$time;
        $PAR{swarms}->{$t}{user}=$user;
      }
    }
    close INDEXFILE;
  }
}
#==================================================================================================
sub parse_swarm_logs
{
  my @files;
  chomp(my $x = `/bin/find /usr/local/logs/swarm_log_archives -type f -mtime -$PAR{max_days_ago}`);
  @files = split /\n/,$x;
  @files = sort @files; 
  push @files,"/usr/local/logs/swarm.log";
  LOG: foreach my $f (@files) {
    if (open LOGFILE, "<$f") {
      print "reading $f\n" if ($OPT{verbose} > 2);
      LINE: while (<LOGFILE>) {
        my $line = $_;
        if ($line=~/^date=([^;]+);\s.+jobid=([^;]+);\suser=([^;]+);\s.+njobs=([^;]+);\stempname=([^;]+);/) {
          my ($time,$jobid,$user,$num,$t) = (str2time($1),$2,$3,$4,$5);
          next LINE if ($time < $PAR{min_submit_time});
          next LINE if (($OPT{user}) && ($user ne $OPT{user}));
          $PAR{swarms}->{$t}{tempname}=$t;
          $PAR{swarms}->{$t}{create_time}=$time;
          $PAR{swarms}->{$t}{user}=$user;
          $PAR{swarms}->{$t}{jobid}=$jobid;
          if (defined $PAR{arrays}->{$jobid}) {
            $PAR{swarms}->{$t}{active}=$PAR{arrays}->{$jobid}{active};
            $PAR{swarms}->{$t}{finish_time}=$PAR{arrays}->{$jobid}{finish_time};
          }
        }
      }
      close LOGFILE;
    }
  }
}
#=================================================================================================
sub parse_sbatch_logs
{
  my @files;
  chomp(my $x = `/bin/find /usr/local/logs/sbatch_log_archives -type f -mtime -$PAR{max_days_ago}`);
  @files = split /\n/,$x;
  @files = sort @files;
  push @files,"/usr/local/logs/sbatch.log";
  LOG: foreach my $f (@files) {
    if (open LOGFILE, "<$f") {
      print "reading $f\n" if ($OPT{verbose} > 2);
      LINE: while (<LOGFILE>) {
        my $line = $_;

#20180220 13:43:23 cn3167 SUBM[61905830]: clarkmg /data/clarkmg/ica_dualreg sbatch --array=0-0 --output=/data/clarkmg/ica_dualreg/model1_48_dualreg_split_output0016/scripts+logs/drD_%A_%a.o --error=/data/clarkmg/ica_dualreg/model1_48_dualreg_split_output0016/scripts+logs/drD_%A_%a.e --cpus-per-task=1 --dependency=afterany:61905773 --job-name=drD --mem=4096 --partition=norm --time=02:00:00 /spin1/swarm/clarkmg/mThglAnXQp/swarm.batch

        if ($line=~/^(\d{4})(\d{2})(\d{2}) (\d\d:\d\d:\d\d)\s\w+\sSUBM\[(\d+)\]:\s(\w+)\s+.+array=0-(\d+)\s.+\/spin1\/swarm\/\w+\/(\w+)\/swarm\.batch/) {
          my ($time,$jobid,$user,$num,$t) = (str2time("$1-$2-$3T$4"),$5,$6,$7,$8);

# Only find jobs created since min_submit_time -- this takes a few seconds
          next LINE if ($time <= $PAR{min_submit_time});
          next LINE if (($OPT{user}) && ($user ne $OPT{user}));
          $PAR{swarms}->{$t}{tempname}=$t;
          $PAR{swarms}->{$t}{create_time}=$time;
          $PAR{swarms}->{$t}{user}=$user;
          $PAR{swarms}->{$t}{jobid}=$jobid;
          if (defined $PAR{arrays}->{$jobid}) {
            $PAR{swarms}->{$t}{active}=$PAR{arrays}->{$jobid}{active};
            $PAR{swarms}->{$t}{finish_time}=$PAR{arrays}->{$jobid}{finish_time};
          }
        }
      }
      close LOGFILE;
    }
  }
}
#=================================================================================================
sub get_arrays
{
  try_connecting($PAR{slurm_cnf_group});
  my $userfilter = "AND `user` = '$OPT{user}'" if ($OPT{user});
  my $sql = "SELECT q4.id_array_job AS jobid, `user`, q4.time_submit AS create_time, q5.time_finish AS finish_time, q7.num AS num, q4.active AS active FROM (SELECT id_array_job,id_user,time_submit,active,`user` FROM (SELECT id_array_job,id_user,time_submit,IF(tactive > 0,1,0) AS active,`user` FROM (SELECT id_array_job,id_user,time_submit,SUM(active) AS tactive,`user` FROM (SELECT id_array_job,id_user,time_submit,IF(state > 1,0,1) AS active,`user` FROM biowulf_job_table JOIN biowulf_assoc_table ON biowulf_job_table.id_assoc = biowulf_assoc_table.id_assoc WHERE id_array_job > 0 $userfilter) AS q1 GROUP BY id_array_job) AS q2) AS q3) AS q4 INNER JOIN (SELECT id_array_job,MAX(time_end) AS time_finish FROM biowulf_job_table GROUP BY id_array_job) AS q5 ON q4.id_array_job = q5.id_array_job INNER JOIN (SELECT id_array_job,IF(s1=0,c1,c1+s1-1) AS num FROM ( SELECT id_array_job,COUNT(id_array_job) AS c1, SUM(array_task_pending) AS s1 FROM biowulf_job_table GROUP BY id_array_job) AS q6) AS q7 ON q4.id_array_job = q7.id_array_job";

  print "$sql\n" if ($OPT{verbose} > 2);
  my $sth = $PAR{$PAR{slurm_cnf_group}}->prepare($sql);
  $sth->execute();
  LINE: while (my $x = $sth->fetchrow_hashref) {
    next LINE if (($OPT{user}) && ($x->{user} ne $OPT{user}));
    $PAR{arrays}->{$x->{jobid}}{create_time} = $x->{create_time};
    $PAR{arrays}->{$x->{jobid}}{finish_time} = $x->{finish_time};
    $PAR{arrays}->{$x->{jobid}}{active} = $x->{active};
    $PAR{arrays}->{$x->{jobid}}{user} = $x->{user};
    $PAR{arrays}->{$x->{jobid}}{num} = $x->{num};
  }
  $sth->finish();
  $PAR{$PAR{slurm_cnf_group}}->disconnect();
}
#=================================================================================================
sub try_connecting
{
  my $dbh_tag = shift;
  my $try=10; 
  while ($try) {
    $PAR{$dbh_tag} = DBI->connect("DBI:mysql:;mysql_read_default_group=$dbh_tag;mysql_read_default_file=/usr/local/etc/my.cnf;mysql_connect_timeout=10",undef,undef,{RaiseError=>0,PrintError=>0,AutoCommit=>0});
    last if $PAR{$dbh_tag};
    print_to_logfile("Can't connect to mysql ($dbh_tag) -- $try more tries");
    sleep 60;
    $try--;
  }

# This is necessary to ensure each query is done fresh and new
  if ($PAR{$dbh_tag}) {
    my $result1 = $PAR{$dbh_tag}->do("SET TRANSACTION ISOLATION LEVEL READ COMMITTED");
    my $result2 = $PAR{$dbh_tag}->do("SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED");
    my @row_ary = $PAR{$dbh_tag}->selectrow_array("SELECT * FROM information_schema.session_variables WHERE variable_name LIKE 'tx_%'");
    print_to_logfile("$dbh_tag: @row_ary") if ($OPT{debug});
  }
  else {
    print_to_logfile("Giving up");
    exit 1;
  }
}
#=================================================================================================#
sub printSwarmUsage
{
  my $cat = HPCNIH::Staff::MySQL::Catalog->new(catalog=>"quota_spin1");
  my $x = $cat->get_current(entity=>"/spin1/swarm");
  my $y = $x->{'/spin1/swarm'};
  my $string = sprintf("/swarm usage: %6.2f GB (%4.1f%%), %7d files (%4.1f%%)\n",
      ( $y->{dusage}/1024/1024 ),
      ( ($y->{dusage}/$y->{dquota})*100 ),
      ( $y->{fusage} ),
      ( ($y->{fusage}/$y->{fquota})*100 ),
  );
  return $string;
}
#=================================================================================================
sub print_tally
{
  print_to_logfile(
    sprintf("f: a=%d i=%d u=%d d: i=%d u=%d rss=%d (%d seconds)", 

      $PAR{tally}{active}{found},
      $PAR{tally}{inactive}{found},
      $PAR{tally}{unknown}{found},
      $PAR{tally}{inactive}{deleted},
      $PAR{tally}{unknown}{deleted},
      _report_rss(),
      (time() - $PAR{NOW}),
    )
  );
  undef $PAR{tally};
}
#==================================================================================================
sub _report_rss
{
  my $mu = Memory::Usage->new();
  $mu->record('after');
  my $z = ${${$mu->state()}[0]}[3];
  undef $mu;
  return $z;
}
#==================================================================================================
sub print_to_logfile
{
  my $message = shift;
  if ($OPT{debug}) {
    my $date = strftime("%FT%T", (localtime(time))[0 .. 5]);
    print "$date\t$message\n";
  }
  else {
    my $LOGFILE = FileHandle->new($PAR{logfile},">>");
    my $date = strftime("%FT%T", (localtime(time))[0 .. 5]);
    print $LOGFILE "$date\t$message\n";
    $LOGFILE->flush;
    undef $LOGFILE;
  }
}
#==================================================================================================
