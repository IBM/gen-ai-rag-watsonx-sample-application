#!/bin/bash
echo
echo "###########################################################################"
echo This script is used for starting the main frontend service
echo "###########################################################################"

#Set home directory
if [[ $INSTALLATION_TYPE == "DOCKER" ]]
then
  echo "INSTALLATION_TYPE is DOCKER."
  APPLICATION_HOME=$APPLICATION_HOME_DOCKER

elif [[ $INSTALLATION_TYPE == "LOCAL" ]]
then
  echo "INSTALLATION_TYPE is LOCAL."
  APPLICATION_HOME=$APPLICATION_HOME_LOCAL

else
  echo "INSTALLATION_TYPE not set. Exiting."
  exit
fi

echo "APPLICATION_HOME:" $APPLICATION_HOME

echo "Starting $APPLICATION_HOME/main.js..."
cd $APPLICATION_HOME
nohup node main.js &>$APPLICATION_HOME/logs/main_nohup.out &

#cat $APPLICATION_HOME/logs/main_nohup.out
echo 
echo "To tail the log run the following command:"
echo 
echo "tail -10f $APPLICATION_HOME/logs/main_nohup.out"
echo 

