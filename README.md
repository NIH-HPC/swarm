# Swarm

Swarm is a script designed to simplify submitting a group of commands to the Biowulf cluster. 

## How swarm works

The swarm script accepts a number of input parameters along with a file containing a list of commands that otherwise would be run on the command line.  swarm parses the commands from this file and writes them to a series of command scripts.  Then a single batch script is written to execute these command scripts in a slurm job array, using the user's inputs to guide how slurm allocates resources.

## Behind the scenes

swarm writes everything in /spin1/swarm, under a user-specific directory:

```
/spin1/swarm/user/
├── 4506756 -> /spin1/swarm/user/tmpYMaPNXtq
└── tmpYMaPNXtq
    ├── cmd.0
    ├── cmd.1
    ├── cmd.2
    ├── cmd.3
    └── swarm.batch
```

swarm (running as the user) first creates a subdirectory within the user's directory with a completely random name beginning with 'tmp'.  The command scripts are named 'cmd.#', with # being the index of the job array.  The batch script is simply named 'swarm.batch'.  All of these are written into the temporary subdirectory.

When a swarm job is successfully submitted to slurm, a jobid is obtained, and a symlink is created that points to the temporary directory.  This allows for simple identification of swarm array jobs running on the cluster.

If a submission fails, then the symlink created will instead have the string '_FAIL' tagged onto the end:

```
/spin1/swarm/user/
├── tmpyeTeQTAV
│   ├── cmd.000
│   ├── cmd.001
│   ├── cmd.002
│   ├── cmd.003
│   └── swarm.batch
└── tmpyeTeQTAV_FAIL -> /spin1/swarm/user/tmpyeTeQTAV
```

When a user runs swarm in development mode (--devel), a subdirectory is created and filled, but the job is not submitted.  These subdirectories are identified with the prefix 'dev':

```
/spin1/swarm/user
└── dev3Pr6KE9F
    ├── cmd.0
    ├── cmd.1
    ├── cmd.2
    ├── cmd.3
    └── swarm.batch
```

## Clean up

Because the space in /spin1/swarm is limited, old directories need to be removed.  We want to keep the directories and files around for a while to use in investigations, but not forever.  The leftovers are cleaned up daily by /usr/local/sbin/swarm_cleanup.pl in a root cron job on biowulf.  At the moment, subdirectories and their accompanying symlinks are deleted under these circumstances:

* Proper jobid symlink (tmpXXXXXXXX, meaning that the job was successfully submitted)
  * the directory and symlink are removed **one week after the entire swarm job array has ended**
* Job submission failed (tmpXXXXXXXX_FAIL)
  * the subdirectory and symlink are removed when the **modification time of the directory exceeds one week**
* Development mode (devXXXXXXXX)
  * the subdirectory and symlink are removed when the **modification time of the directory exceeds one week**

When run in --debug mode, swarm_cleanup.pl prints out a very nice description of what it might do:

```
$ swarm_cleanup.pl --debug
Getting jobs
Getting job states and ages since ending
Getting symlinks for real jobs
Walking through directories
user              basename          STA   AGE   DSE  TYP : ACTION  EXTRA
================================================================================
chenp4            4073854           Q/R   14.9  ---  LNK : KEEP    states
ebrittain         4400424           END   10.0  0.2  LNK : KEEP    FAILED
sudregp           4467927           END    8.9  8.9  LNK : DELETE  COMPLETED,FAILED
  rm -f /spin1/swarm/sudregp/4467927
  rm -rf /spin1/swarm/sudregp/tmpXhlnoNq0
sudregp           4467928           SKP    6.9  ---  LNK : KEEP
bartesaghia       4501010           END    9.2  9.2  LNK : DELETE  COMPLETED
  rm -f /spin1/swarm/bartesaghia/4501010
  rm -rf /spin1/swarm/bartesaghia/tmpdR_NPaOk
bartesaghia       4501011           END    9.1  9.1  LNK : DELETE  COMPLETED
  rm -f /spin1/swarm/bartesaghia/4501011
  rm -rf /spin1/swarm/bartesaghia/tmpOePKGVUa
```

Each subdirectory is given as a single line.  The user and basename (jobid for successful submissions) start each line.  The other fields are:

**STA:** state of the job
* Q/R: queued or running
* END: the job has ended
* SKP: sacct was skipped, so no information is known about the job
* DEV: developemnt run
* FAIL: submission failed
* UNK: unknown state

**AGE:** modification time of the subdirectory

**DSE:** days since ending, only known for ended jobs

**TYP:** type of basename, either symlink (LNK) or directory (DIR)

**ACTION:** what action is taken, either (DELETE) or (KEEP)

**EXTRA:** extra information, such as the unique list of states of all the subjobs within the swarm

## Logging

swarm logs to /usr/local/logs/swarm_on_slurm.log

swarm_cleanup.pl logs to /usr/local/logs/swarm_cleanup.log

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
