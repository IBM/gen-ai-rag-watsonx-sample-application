#!/usr/bin/env bash

# Copyright 2024 IBM Corp.
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# http://www.apache.org/licenses/LICENSE-2.0
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# shellcheck disable=SC1090,SC1091
source "${WORKSPACE}/$PIPELINE_CONFIG_REPO_PATH/scripts/code-engine-utilities.sh"

if ! initialize-code-engine-project-context; then
  echo "Code Engine project context initialization failed. Exiting 1"
  exit 1
fi

# Configure the secret for registry credentials
IBMCLOUD_TOOLCHAIN_ID="$(jq -r .toolchain_guid /toolchain/toolchain.json)"
REGISTRY_URL=$(echo "${IMAGE}" | awk -F/ '{print $1}')
export REGISTRY_SECRET_NAME="ibmcloud-toolchain-${IBMCLOUD_TOOLCHAIN_ID}-${REGISTRY_URL}"

if ibmcloud ce registry get --name "${REGISTRY_SECRET_NAME}" > /dev/null 2>&1; then
  echo "${REGISTRY_SECRET_NAME} Secret to push and pull the image already exists."
else
  echo "Secret to push and pull the image does not exists, Creating it......."
  if [ -f /config/api-key ]; then
    ICR_API_KEY="$(cat /config/api-key)" # pragma: allowlist secret
  else
    ICR_API_KEY="$(get_env ibmcloud-api-key)" # pragma: allowlist secret
  fi
  ibmcloud ce registry create --name "${REGISTRY_SECRET_NAME}" --email a@b.com  --password="$ICR_API_KEY" --server "$(echo "$IMAGE" |  awk -F/ '{print $1}')" --username iamapikey
fi

# Configure configmap
echo "Creating configmap for properties"

if ibmcloud ce configmap get -n app.properties; then
  echo "Configmap app.properties already exists, updating..."
  ibmcloud ce configmap update --name app.properties --from-env-file app.properties
else
  echo "Creating configmap app.properties"
  ibmcloud ce configmap create --name app.properties --from-env-file app.properties
fi

# Configure specific properties - app flavor, watsonx integration ID
WA_SERVICE_INSTANCE_ID=$(get_env WA_SERVICE_INSTANCE_ID "")
WA_REGION=$(get_env WA_REGION "")

# api call to get integration ID?
WA_INTEGRATION_ID=$(get_env WA_INTEGRATION_ID "")
APP_FLAVOR=$(get_env app-flavor "")

ibmcloud ce configmap update --name app.properties --from-literal "WA_SERVICE_INSTANCE_ID=$WA_SERVICE_INSTANCE_ID" --from-literal "WA_REGION=$WA_REGION" --from-literal "WA_INTEGRATION_ID=$WA_INTEGRATION_ID" --from-literal "APP_FLAVOR=$APP_FLAVOR"
