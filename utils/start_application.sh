#!/bin/bash
echo
echo "###########################################################################"
echo This  script starts the main frontend service
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

#####################

echo "Starting Generative AI RAG watsonx Sample Application frontend service."

cd $APPLICATION_HOME
./utils/apply_configurations_from_envars.sh
./utils/start_main.sh

#echo "to check logs:"
#echo "tail -f logs/main_nohup.out"

if [[ $INSTALLATION_TYPE == "DOCKER" ]]
then
  echo "INSTALLATION_TYPE is DOCKER. Keeping application running."
  tail -f logs/main_nohup.out
fi


