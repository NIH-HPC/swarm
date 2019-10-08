# Swarm

Swarm is a script designed to simplify submitting a group of commands to the Biowulf cluster. 

## How swarm works

The swarm script accepts a number of input parameters along with a file containing a list of commands that otherwise would be run on the command line.  swarm parses the commands from this file and writes them to a series of command scripts.  Then a single batch script is written to execute these command scripts in a slurm job array, using the user's inputs to guide how slurm allocates resources.

### Bundling versus folding

Bundling a swarm means running two or more commands per subjob serially, uniformly.  For example, if there are 1000 commands in a swarm, and the bundle factor is 5, then each subjob will run 5 commands serially, resulting in 200 subjobs in the job array.

Folding a swarm means running commands serially in a subjob only if the number of subjobs exceed the maximum array size (maxarraysize = 1000).  This is a new concept.  Previously, if a swarm exceeded the maxarraysize, then either the swarm would fail, or the swarm would be autobundled until it fit within the maxarraysize number of subjobs.  Thus, if a swarm had 1001 commands, it would be autobundled with a bundle factor of 2 into 500 subjobs, with 2 commands serially each.  With folding, this would still result in 1000 subjobs, but one subjob would have 2 serial commands, while the rest have 1.

Folding was implemented June 21, 2016.

## Behind the scenes

swarm writes everything in /spin1/swarm, under a user-specific directory:

```
/spin1/swarm/user/
├── 4506756 -> /spin1/swarm/user/YMaPNXtqEF
└── YMaPNXtqEF
    ├── cmd.0
    ├── cmd.1
    ├── cmd.2
    ├── cmd.3
    └── swarm.batch
```

swarm (running as the user) first creates a subdirectory within the user's directory with a completely random name.  The command scripts are named 'cmd.#', with # being the index of the job array.  The batch script is simply named 'swarm.batch'.  All of these are written into the temporary subdirectory.

### Details about the batch script

The batch script 'swarm.batch' hard-codes the path to the temporary subdirectory as the location of the command scripts.  This allows the swarm to be rerun, albeit with the same sbatch options.

The module function is initialized and modules are loaded in the batch script.  This limits the number of times 'module load' is called to once per swarm, but it also means that the user could overrule the environment within the swarm commands.

### What happens after submission

When a swarm job is successfully submitted to slurm, a jobid is obtained, and a symlink is created that points to the temporary directory.  This allows for simple identification of swarm array jobs running on the cluster.

If a submission fails, then no symlink will be created.

When a user runs swarm in development mode (--devel), no temporary directory or files are created. 

## Testing

Swarm has several options for testing things.

**--devel:** This option prevents swarm from creating command or batch scripts, prevents it from actually submitting to sbatch, and prevents it from logging to the standard logfile.  It also increases the verbosity level of swarm.

**--verbose:** This option makes swarm more chatty, and accepts an integer from between 0 (silent) and 4.  Running a swarm with many commands at level 4 will give a lot of output, so beware.

**--debug:** This option is similar to --devel, except that the scripts are actually created.  The temporary directory for the swarm.batch and command scripts begins with 'dev', rather than 'tmp' like normal.

**--no-run:** A hidden alacarte option, prevents swarm from actually submitting to sbatch.

**--no-log:** A hidden alacarte option, prevents swarm from logging.

**--logfile:** A hidden alacarte option, redirects the logfile from the standard logfile to one of your choice.

**--no-scripts:** Don't create command and batch scripts.

In the tests subdirectory, there are two scripts that can be run to test the current build of swarm.  **test.sh** runs a series of swarm commands that are expected to succeed, and **fail.sh** runs a series of swarm commands that are expected to fail.  They are run in **--devel** mode, so nothing is ever submitted to the cluster nor logged.

The script **sample.pl** extracts the last 100 or so lines from the swarm logfile and generates possible options for testing swarm.  The **--sbatch** option is screwed up because it doesn't contain any quotes, so you will need to add those back in to construct proper swarm commands.

## Logging

* swarm logs to /usr/local/logs/swarm.log
* swarm_cleanup.pl logs to /usr/local/logs/swarm_cleanup.log

## Index File

An index file /usr/local/logs/swarm_tempdir.idx is updated when a swarm is created.  This file contains the creation timestamp, user, unique tag, number of commands, and P value (either 1 or 2):

```
1509019983,mmouse,e4gLIFwqhq,1,1
1509020005,mmouse,aFwi3QYiQ0,13,1
1509020213,dduck2,jqcJTSiIBH,3,1
1509020215,dduck,qqBMb2SLzl,1,1
1509020225,ggoofy,64PZ3h80nB,1000,1
```

## Clean up

Because the space in /spin1/swarm is limited, old directories need to be removed.  We want to keep the directories and files around for a while to use in investigations, but not forever.  The leftovers are cleaned up daily by /usr/local/sbin/swarm_cleanup.pl in a root cron job on biowulf.  At the moment, subdirectories and their accompanying symlinks are deleted when either the full swarm ended 5 days prior, or if not run the modification time exceeds 5 days.

Under normal use, swarm_cleanup.pl first identifies all jobarrays from the biowulf_job_table of the slurmacct database (using the replicate slave).  Then it parses the swarm_tempdir.idx, recent swarm.log and sbatch.log files and determines the status and age of all created swarms.  Swarms that are either inactive (they finished in slurm) or are unknown (never submitted to slurm) and are 5 days old are deleted from /spin1/swarm.

```
swarm_cleanup.pl --delete-age 5
```

When a swarm tempdir directory is deleted, it is recorded in /usr/local/logs/swarm_cleanup.idx as a comma-delimited list:

```
1569079783,0,1570533216,user1,ztTSHJ6gJ9,0
1570022156,1570022418,1570533216,user2,zuNcmPhc1r,37909839
```

The fields are:

* time created
* time finished (zero if not known)
* time deleted
* user
* tempdir
* jobid (zero if not known)

If --email is given, then an email is sent to the users listed in the option that looks like this:

```
$ swarm_cleanup.pl --delete-age 5 --email userA,userB,userC
...
/swarm usage:  11.15 GB (22.3%), 2268917 files (32.4%)
======================================================================
Swarm directories scanned: 8222
Swarm directories deleted: 2407
======================================================================
/swarm usage:   7.56 GB (15.1%), 1373878 files (19.6%)
```

When run in --dry-run mode, swarm_cleanup.pl generates a unique swarm_cleanup.idx file in the current working directory.

A final tally is written to swarm_cleanup.log:

```
2019-10-08T07:13:36     f: a=85 i=5726 u=2411 d: i=796 u=1611 rss=195264 (813 seconds)
```

The format of the log is as follows

```
  f -- found
  d -- deleted

    a:     active (pending or running)
    i:     inactive (finished)
    u:     unknown (swarm not submitted to slurm)
    rss:   current memory usage
```

Thus, the above line from the logfile indicates that the script found 85 pending or running swarms, 5726 inactive swarms, and 2411 unknown swarms.  Of the inactive swarms, 796 were deleted because they ended 5 or more days ago.  Of the unknown swarms, 1611 were deleted because they were created 5 or more days ago.  The entire cleanup process took about 15 minutes are required about 191 MB of RAM.
