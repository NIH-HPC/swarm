#!/bin/bash

# Love colors a lot
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

mandir=/usr/local/share/man/man1
htmldir=/usr/local/www/hpcweb/htdocs/apps
bindir=/usr/local/bin
sbindir=/usr/local/sbin

# Help message
function printHelp {
  echo "
usage: $0 [ -h ] [ -f file ] [ -d ]

  Update swarm files if needed.  The paths affected are:

    $mandir/swarm.1
    $bindir/swarm
    $sbindir/swarm_cleanup.pl
    $htmldir/swarm.html

  If -f is given, only that file will be updated.

  Last updated 3/1/16, David Hoover
"
  exit
}

# Options
while getopts "f:h" flag
do
  if [ "$flag" == "h" ]; then
    printHelp
  fi
  if [ "$flag" == "f" ]; then
    file=$OPTARG
  fi
done

# Must be root to update things
[[ "$(whoami)" != 'root' ]] && { printRed "You must be root!"; exit 1; }

# Simple function for updating, args = dir file mode
function update_file {
  if diff $2 $1/$2 >& /dev/null ; then
    printBlue "$2 and $1/$2 are the same"
  else
    printYellow "rsync $2 $1/$2"
    rsync $2 $1/$2 || { printRed "FAIL!" ; exit 1; }
    chmod $3 $1/$2
    printGreen "$(ls -l $1/$2)"
  fi
}

if [[ -n $file ]]; then

  [[ -e $file ]] || { printRed "Can't find file $file!"; exit 1; }

  case $file in
    swarm.1)
      update_file $mandir swarm.1 0644
    ;;
    swarm.html)
      update_file $htmldir swarm.html 0644
    ;;
    swarm)
      update_file $bindir swarm 0755
    ;;
    swarm_cleanup.pl)
      update_file $sbindir swarm_cleanup.pl 0750
    ;;
  esac
else
  update_file $mandir swarm.1 0644
  update_file $htmldir swarm.html 0644
  update_file $bindir swarm 0755
  update_file $sbindir swarm_cleanup.pl 0750
fi
