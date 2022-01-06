#!/bin/bash
# This is the swarm script we want to test

swarm=$1

[[ -z $swarm ]] && { echo "What swarm script do you want to test?" ; exit 1; }
[[ $swarm == "-h" ]] && { echo "This script runs swarm tests which are expected to succeed"; exit; }
[[ ! -x $swarm ]] && { echo "$swarm is not executable" ; exit 1; }

function printRed {
    echo -e "\x01\033[31m\x02${1}\x01\033[0m\x02"
}
function printGreen {
    echo -e "\x01\033[32m\x02${1}\x01\033[0m\x02"
}
function printYellow {
    echo -e "\x01\033[33m\x02${1}\x01\033[0m\x02"
}
function printBlue {
    echo -e "\x01\033[34m\x02${1}\x01\033[0m\x02"
}

# This is the function we will use to run the tests
function __test_swarm {
  printYellow $1
  ec=0
# $1 = test script
  ret=$(bash $1 2>&1) || ec=1
  if [[ $ec == 1 ]] ; then
    printRed "└── $ret"
  else
     printGreen "└── OK: $ret"
  fi
}

# These are the test cases (i.e. set of options) we want to test



cat <<testcases > testcases.list
-g 8
-t 4
-p 2
-b 2
--usecsh
--module python
--module trimmomatic/0.35
--no-comment
--comment-char 5
--debug
--devel
--verbose 4
--silent
--job-name BOGUS
--dependency 12345678987654321
--time 1
--time 1:00
--time 1:00:00
--time 10:00:00
--time --devel
--license matlab
--partition nimh
--qos bogus
--qos norm
--sbatch '--mail-type=FAIL --export=var=100,nctype=12 --workdir=~/test'
-g 16 --time 02:00:00
-g 12 --time 3-12:00:00
-g 30 --partition=ccr -J SensSpec
-g 120 -t 32 --time=10-00:00:00 --sbatch '--mail-type=END'
--gres=lscratch:20 --job-name=pph_swarm -g 1 --logdir Sample_CCSK002tumor_T_C2D7YACXX_output_raw_snps_indels_filtered_modified.vcf.pph2_logdir.46150 -p 2 --partition ccr
--license=matlab-stat -g 16 --time 02:00:00
--partition=ccr --job-name CNV_pile --sbatch='--time=24:00:00 --mail-type=TIME_LIMIT_90,FAIL'
--license=matlab-stat -g 16 --time 02:00:00
--license=matlab-stat -g 8 --time 00:15:00 --dependency=afterany:10561509
--partition ccr --time 12:00:00 --logdir ~/pipeline_files/January_07_2016_04-26-30PM/ --dependency afterok:10559728 -g 4 -t 1
--partition ccr --time 24:00:00 --logdir ~/pipeline_files/January_07_2016_04-26-30PM/ --dependency afterok:10559739,afterok:10559740,afterok:10559741 -g 24 -t 4
--partition=ccr --job-name CNV_fmtD --dependency afterany:10560028
--partition=ccr --job-name CNV_pile --sbatch='--time=24:00:00 --mail-type=TIME_LIMIT_90,FAIL'
--sbatch '--gres=lscratch:1 --partition norm'
--sbatch '--gres=lscratch:200 --qos ccrprio' --job-name sprswarm -t 16 -g 60 --module Anaconda/2.1.0_py27 --partition ccr
--sbatch '--partition=norm --cpus-per-task=24 --mem=24g'
--sbatch '--partition=norm --mem=24g'
--sbatch '--qos ccrprio' --dependency=afterany:10556734 --gres=lscratch:400 --job-name frm_random -t auto -g 58 --module Anaconda/2.1.0_py27 --partition ccr --time 2:00:00
--time 12:00:00 --partition ccr --logdir ~/pipeline_files/January_07_2016_04-26-30PM/ --dependency afterok:10559731 -g 32 -t 16
--time 14:00:00 --module TORTOISE --sbatch '--cpus-per-task=32 --mem=40g'
--verbose=1 -t 8 -g 10 --time=18:00:00
-b 10 --dependency=afterany:10558355 --time 0:10:00 --module IDL --sbatch '--export=IDL_CPU_TPOOL_NTHREADS=2'
-g 10 -t 12 --partition=ccr --time=99:00:00 --module htseq
-g 10 -t 12 --time=99:00:00 --module htseq
-g 4 --time 00:10:00 --partition quick --module R
-g 5 -t 8 --partition=ccr --time=99:00:00 --module htseq
-g 64 -t 16 --module samtools,seqtk,kraken --time 10:00:00
-g 72 --module cufflinks --qos nimh
-g 8 --module python --partition quick
-g 8 --partition=ccr --time=56:00:00
-g 8 --time 00:15:00 --dependency=afterany:10558281
-g 8 --time 2-00:00:00
-g 8 -t 1 --partition quick --module fastqc
-g 8 -t 1 --time 18:00:00 --logdir ~/temp/analysis_results/netMHC/1_4_15_working_folder/ --partition ccr
-g 8 -t 10 --partition=ccr --time=56:00:00
-t 20 -g 8 --module afni --usecsh
-t 5 -g 8 --module fastxtoolkit
-t 8 -g 200 --gres=lscratch:200 --module samtools/1.2 --time=6 --sbatch '--partition=quick --mail-type=BEGIN,END'
-t auto -g 6
-g 4 --sbatch '--qos=ccrsprio' -t 8
--dependency afterany:10605277
-g 10 -t 4 --partition=ccr --time=30:00:00
-g 12 --time 3-00:00:00
-g 12 --time 3-12:00:00
-g 16 --time 02:00:00
-g 16 --time 48:00:00 -t 4 --sbatch '--exclusive'
-g 32 --logdir swarm_out
-g 36 --module blast
-g 6 --time 18:00:00
-g 8 --time 00:15:00 --dependency=afterany:10603994
-g 8 --time 24:00:00 -t 4 --sbatch '--exclusive'
-g 8 --time=6:00:00
--module R
-p 2 --partition=quick
--partition=norm
--sbatch '--export spydaemon=spydaemon' --job-name cmm_0105 --time 5-00:00:00 --partition ccr
--sbatch '--gres=lscratch:1 --partition quick'
--sbatch '--partition=ccr --time=24:00:00 --job-name CNV_plup --mail-type=TIME_LIMIT_90,FAIL'
--sbatch '--partition=ccr --time=8:00:00 --job-name CNV_fmtD --mail-type=TIME_LIMIT_90,FAIL --dependency afterany:10611929'
-t 10 -g 5 --time=24:00:00
-t 4 -g 2 --module samtools/1.2,bedtools --sbatch '--mail-type=BEGIN,END' --job-name=bam2bedgraph
-t 4 -g 2 --module samtools/1.2,bedtools --sbatch '--partition=quick --mail-type=BEGIN,END' --job-name=bam2bedgraph
-t auto -g 6 --partition nimh --time 1-00:00:00
-t auto --time 12:00:00 --module R
--time=00:01:00 --partition=quick --sbatch '--mail-type=TIME_LIMIT_90,FAIL' -g 1
--time 10:00:00
--time=5-00:00:00
--time 14:00:00 --module TORTOISE --sbatch '--cpus-per-task=32 --mem=35g'
--verbose=1 -g 15 --time=72:00:00
--verbose=1 --partition=quick -g 10 --time=120
--verbose=1 --partition=norm,largemem -g 10 --time=36:00:00
--verbose=1 --partition=norm,ccr,quick -g 10 --time=2:00:00
--verbose=1 --partition=norm,ccr,quick -g 10 --time=2:00:00
--partition norm --logdir Align_FASTQs --sbatch "--nodes=4 --ntasks=8 --ntasks-per-node=2 --cpus-per-task=16 --exclusive" 
--verbose=1 --maxrunning 3 --time=10:00:00
-g 2000 --partition largemem
-g 0.2 --partition quick
--merge-output --logdir bogus
testcases

# Walk through each test case
while read line ; do

# Create a new test script for each test case, making ABSOLUTELY CERTAIN we are using --devel and --logfile
  ((n++))
  cat <<eof > t$(printf %03d $n).sh
#!/bin/bash
a=2 ; while [ \$a -gt 0 ]; do echo 1 ; ((a--)); done > \$0.\$\$
$swarm \$0.\$\$ --devel -v 2 \\
  $line
ec=\$?
rm \$0.\$\$
exit \$ec
eof
#$swarm -f \$0.\$\$ --devel -v 2 --logfile swarm_on_slurm.log \\

# Run the test case
  __test_swarm t$(printf %03d $n).sh

# Throw away the test case script
  rm t$(printf %03d $n).sh
done < testcases.list

# Throw away the list
rm testcases.list


