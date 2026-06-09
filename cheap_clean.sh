#!/bin/bash

# You must be root
[[ $(/usr/bin/whoami) == "root" ]] || { echo "You must be root"; exit 1; }

user=$1
[[ -z $user ]] && { echo "What user?"; exit 1; }

# Does the user have a swarm directory?

[[ -d /spin1/swarm/$user ]] || { echo "No swarm dir /swarm/$user"; exit 1; }
echo

# Does the user have any active jobs?
sjobs -u $user
echo

mfd=0
dashboard_cli jobs --is-active --user $user || ((mfd++))

# What is the most recent file in their swarm directory?
find /spin1/swarm/$user -type f -printf '%p\t%TF\n' | sort -k2 | tail -n 1
echo

# Determine timestamps
now=$(date  +%s)
latest=$(find /spin1/swarm/$user -type f -printf '%Ts\n' | sort -nk1 | tail -n 1)
diff=$(( (now-latest)/86400 ))

echo "directory is $diff days old"
echo

if [[ $diff -gt 30 ]]; then ((mfd++)) ; fi

if [[ -z $mfd ]] || [[ $mfd -lt 2 ]]; then
  echo -n "delete /spin1/swarm/$user y/[n] "
  read foo
  if [ "$foo" == 'y' ] ; then rm -rf /spin1/swarm/$user; fi
else
  echo automatically deleting /spin1/swarm/$user
  rm -rf /spin1/swarm/$user
fi

echo
