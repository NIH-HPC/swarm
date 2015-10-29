Swarm is a script designed to simplify submitting a group of commands to the Biowulf cluster. 

How swarm works

The swarm script accepts a number of input parameters along with a file containing a list of commands that otherwise would be run on the command line.  swarm parses the commands from this file and writes them to a series of command scripts.  Then a single batch script is written to execute these command scripts in a slurm job array, using the user's inputs to guide how slurm allocates resources.

Behind the scenes

swarm writes everything in /spin1/swarm, under a user-specific directory:

/spin1/swarm/user/
├── 4506756 -> /spin1/swarm/user/tmpYMaPNXtq
└── tmpYMaPNXtq
    ├── cmd.0
    ├── cmd.1
    ├── cmd.2
    ├── cmd.3
    └── swarm.batch

swarm (running as the user) first creates a subdirectory within the user's directory with a completely random name beginning with 'tmp'.  The command scripts are named 'cmd.#', with # being the index of the job array.  The batch script is simply named 'swarm.batch'.  All of these are written into the temporary subdirectory.

When a swarm job is successfully submitted to slurm, a jobid is obtained, and a symlink is created that points to the temporary directory.  This allows for simple identification of swarm array jobs running on the cluster.

If a submission fails, then the symlink created will instead have the string '_FAIL' tagged onto the end:

/spin1/swarm/user/
├── tmpyeTeQTAV
│   ├── cmd.000
│   ├── cmd.001
│   ├── cmd.002
│   ├── cmd.003
│   └── swarm.batch
└── tmpyeTeQTAV_FAIL -> /spin1/swarm/user/tmpyeTeQTAV

When a user runs swarm in development mode (--devel), a subdirectory is created and filled, but the job is not submitted.  These subdirectories are identified with the prefix 'dev':

/spin1/swarm/user
└── dev3Pr6KE9F
    ├── cmd.0
    ├── cmd.1
    ├── cmd.2
    ├── cmd.3
    └── swarm.batch

Clean up

Because the space in /spin1/swarm is limited, old directories need to be removed.  We want to keep the directories and files around for a while to use in investigations, but not forever.  The leftovers are cleaned up daily by /usr/local/sbin/swarm_cleanup.pl in a root cron job on biowulf.  At the moment, subdirectories and their accompanying symlinks are deleted under these circumstances:

-- If there is a proper jobid symlink (meaning that the job was successfully submitted), the directory and symlink are removed one week after the entire swarm job array has ended
-- If the job submission failed (_FAIL) or if the swarm was created in development mode (dev), then the subdirectory and symlink are removed when the modification time of the directory exceeds one week.


