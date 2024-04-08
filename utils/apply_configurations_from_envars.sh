#!/bin/bash

########################################## 
# This scripts gets environment variables values  
# from the app.properties ConfigMap in Code Engine 
########################################## 

##################### 

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

####################
#Set the location of files to be configured.
WA_PUBLIC_WEBPAGE_INDEX_FILE=$APPLICATION_HOME/public/index.html
WA_PUBLIC_WEBPAGE_INDEX_TEMPLATE_FILE=$APPLICATION_HOME/public/index.html.template

##########################
#Reset any older configurations if any to default files and configurations.
echo "Reseting/removing prior configurations if any..."
cp $WA_PUBLIC_WEBPAGE_INDEX_TEMPLATE_FILE $WA_PUBLIC_WEBPAGE_INDEX_FILE

##########################
#Update configurations in relevant files
echo "Updating configuration and integration files with values from .env or environment variables..."
#Update the watsonx Assistant chat UI configurations in the live public index.html file

sed -i "s/<wa_integration_id>/$WA_INTEGRATION_ID/g" $WA_PUBLIC_WEBPAGE_INDEX_FILE
sed -i "s/<wa_region>/$WA_REGION/g" $WA_PUBLIC_WEBPAGE_INDEX_FILE
sed -i "s/<wa_service_instance_id>/$WA_SERVICE_INSTANCE_ID/g" $WA_PUBLIC_WEBPAGE_INDEX_FILE

echo "Done."

##################### 
