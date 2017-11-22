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

## Clean up

Because the space in /spin1/swarm is limited, old directories need to be removed.  We want to keep the directories and files around for a while to use in investigations, but not forever.  The leftovers are cleaned up daily by /usr/local/sbin/swarm_manager in a root cron job on biowulf.  At the moment, subdirectories and their accompanying symlinks are deleted when either the full swarm ended 5 days prior, or if not run the modification time exceeds 5 days.

When run in --dry-run mode, swarm_manager prints out a summary of the known swarms, with a list of swarms and their corresponding status:

```
$ swarm_manager --dry-run  --human
Running in dry-run mode
R/P=3123,F=18136,U=5260
...
6WKbhKwgdE	53685609	F	2017-11-12T07:18:59	2017-11-12T09:28:59	2017-11-18T06:30:01	mmouse
MX6u9pc6qA	53719443	F	2017-11-12T17:45:46	2017-11-12T17:46:08	2017-11-18T06:30:01	mmouse
7Vs9wt_bj7	      -1	U	2017-11-22T02:57:31	                 -1	                 -1	jeb
wM4wmAGBf2	53685210	F	2017-11-12T07:14:45	2017-11-12T08:30:37	2017-11-18T06:30:01	mmouse
sYczw00gOi	54462141	R/P	2017-11-22T00:22:02	                 -1	                 -1	dduck
yJdZ0Teclu	      -1	U	2017-11-11T15:44:40	                 -1	2017-11-17T06:30:02	mmouse
CkHn5oWBWZ	54462144	R/P	2017-11-22T00:22:09	                 -1	                 -1	dduck
4YWcIPcqp9	54461506	F	2017-11-21T23:56:10	2017-11-21T23:56:13	                 -1	dduck
NcvQIL0TNN	53764812	F	2017-11-13T08:33:59	2017-11-15T18:48:45	2017-11-21T06:30:01	ggoofy
z8OVfg_Az_	54303744	F	2017-11-20T11:51:34	2017-11-20T11:51:36	                 -1	dduck2
...
```
**Columns**
* 1: unique tag that identifies the swarm
* 2: the slurm jobid for the jobarray -- unsubmitted swarms are set to -1
* 3: the metastate; R/P = running or pending, F = finished, U = unsubmitted
* 4: submit/create time -- this is always set
* 5: end time -- running/pending/unsubmitted swarms are set to -1
* 6: delete time -- undeleted swarms are set to -1
* 7: user

Routine daily cleaning is done by including the --routine option.  Running in --dry-run mode shows what directories will get removed:

```
$ ./swarm_manager --dry-run  --human --routine
Running in dry-run mode
...
2017-11-22T09:37:02	rm -rf /spin1/swarm/dduck/bKuRukIcN0 /spin1/swarm/dduck/54095527
2017-11-22T09:37:02	rm -rf /spin1/swarm/ggoofy/mgeLmPLATB /spin1/swarm/ggoofy/54095086
2017-11-22T09:37:02	rm -rf /spin1/swarm/mmouse/qdcR8dNqZZ /spin1/swarm/mmouse/54096680
...
/swarm usage:   2.03 GB ( 4.1%),  240274 files ( 6.9%)
======================================================================
Swarm directories scanned: 26524
Swarm directories deleted: 3
======================================================================
/swarm usage:   2.03 GB ( 4.1%),  240274 files ( 6.9%)
```
## Index File

An index file /usr/local/logs/swarm_tempdir.idx is updated when a swarm is created.  This file contains the creation timestamp, user, unique tag, number of commands, and P value (either 1 or 2):

```
1509019983,mmouse,e4gLIFwqhq,1,1
1509020005,mmouse,aFwi3QYiQ0,13,1
1509020213,dduck2,jqcJTSiIBH,3,1
1509020215,dduck,qqBMb2SLzl,1,1
1509020225,ggoofy,64PZ3h80nB,1000,1
```

## Logging

* swarm logs to /usr/local/logs/swarm.log
* swarm_manager logs to /usr/local/logs/swarm_cleanup.log

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
