#!/bin/bash

# number of expected arg to the script
# {1} schema name
# {2} mysql user
# {3} mysql user password
# {4} testfolder
EXPECTED_ARGS=4
E_BADARGS=65

# path to mysql cli client
MYSQL="$(which mysqlslap)";

# script execute directory
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ITER=100
CONCUR=10

# test for expected args
if [ $# -ne $EXPECTED_ARGS ]
then
  echo "Usage: $0 dbname dbuser dbpass tests";
  exit $E_BADARGS;
fi

array=(after before during equals finished finishedby includes meets meetsby overlappedby overlaps startedby starts intersects)
for i in "${array[@]}"
do
	echo "Execute $i Basic";
  $MYSQL --user=${2} --password=${3} -v --create-schema=${1} --query=${DIR}'/../src/tests/'${4}'/'$i'_basic.mysql' --iterations=$ITER --concurrency=$CONCUR;
  
	echo "Execute $i Tree";
	$MYSQL --user=${2} --password=${3} -v --create-schema=${1} --query=${DIR}'/../src/tests/'${4}'/'$i'_tree.mysql' --iterations=$ITER --concurrency=$CONCUR;
done 

