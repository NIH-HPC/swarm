#!/bin/bash
# This is the swarm script we want to test

swarm=$1

[[ -z $swarm ]] && { echo "What swarm script do you want to test?" ; exit 1; }
[[ $swarm == "-h" ]] && { echo "This script runs swarm tests which are expected to fail"; exit; }
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
-t 4 -p 2
-g 25 -job-name FirstBP --logdir /home/giustefo/ATACseq/Mouse_73//firstbp/
--time=10-00:00:00 -b 4
--time=8:00:00 -b 4 --partition norm,quick
-t auto -g 6 -partition nimh
-t 4 -g 2 --module samtools/1.2,bedtools --sbatch '--partition=ibqdr --mail-type=BEGIN,END' --job-name=bam2bedgraph
-c 4
--partition stupid
-t 20 -g 8 -module afni --usecsh --partition nimh
-g 72 --module cufflinks -q nimh
--verbose=1 --partition=ccr,niddk,quick -g 10 --time=36:00:00
--verbose=1 --partition=norm,b1,niddk,ccr,quick -g 10 --time=36:00:00
-p2 --sbatch --cpus-per-task=20
--sbatch --output=my_output.log
testcases

# Walk through each test case
while read line ; do

# Create a new test script for each test case
  ((n++))
  cat <<eof > t$(printf %03d $n).sh
#!/bin/bash
a=2 ; while [ \$a -gt 0 ]; do echo 1 ; ((a--)); done > \$0.\$\$
$swarm -f \$0.\$\$ --devel -v 2 \\
  $line
ec=\$?
rm \$0.\$\$
exit \$ec
eof

# Run the test case
  __test_swarm t$(printf %03d $n).sh

# Throw away the test case script
  rm t$(printf %03d $n).sh
done < testcases.list

# Throw away the list
rm testcases.list


