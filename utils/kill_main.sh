#!/bin/bash
echo
echo "###########################################################################"
echo This script is used to terminate the main frontend service
echo "###########################################################################"

# Example command to ge the pid
# ps -ef | grep main.js | grep -v grep | awk '{print $2}'

SVC=main.js
SVC_PID=`ps -ef | grep $SVC | grep -v grep | awk '{print $2}'`
if [[ "" !=  "$SVC_PID" ]]; then
  echo "killing $SVC $SVC_PID"
  kill -9 $SVC_PID
fi

