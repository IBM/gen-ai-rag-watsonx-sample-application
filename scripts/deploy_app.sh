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

echo "Deploying your code as Code Engine application...."
setup-cd-auto-managed-env-configmap "$(get_env app-name)"
setup-cd-auto-managed-env-secret "$(get_env app-name)"
if ! deploy-code-engine-application "$(get_env app-name)" "${IMAGE}" "${REGISTRY_SECRET_NAME}"; then
  echo "Failure in code engine application deployment. Exiting 1"
  exit 1
fi

# Bind services, if any
if ! bind-services-to-code-engine-application "$(get_env app-name)"; then
  echo "Failure in services binding to code engine application. Exiting 1"
  exit 1
fi

echo "Checking if application is ready..."
KUBE_SERVICE_NAME=$(get_env app-name)
DEPLOYMENT_TIMEOUT=$(get_env app-deployment-timeout "300")
echo "Timeout for the application deployment is ${DEPLOYMENT_TIMEOUT} seconds"
ITERATION=0
while [[ "${ITERATION}" -le "${DEPLOYMENT_TIMEOUT}" ]]; do
    sleep 1
    SVC_STATUS_READY=$(kubectl get "ksvc/${KUBE_SERVICE_NAME}" -o json | jq '.status?.conditions[]?.status?|select(. == "True")')
    SVC_STATUS_NOT_READY=$(kubectl get "ksvc/${KUBE_SERVICE_NAME}" -o json | jq '.status?.conditions[]?.status?|select(. == "False")')
    SVC_STATUS_UNKNOWN=$(kubectl get "ksvc/${KUBE_SERVICE_NAME}" -o json | jq '.status?.conditions[]?.status?|select(. == "Unknown")')
    # shellcheck disable=SC2166
    if [ \( -n "$SVC_STATUS_NOT_READY" \) -o \( -n "$SVC_STATUS_UNKNOWN" \) ]; then
        echo "Application not ready, retrying"
    elif [ -n "$SVC_STATUS_READY" ]; then
        echo "Application is ready"
        ibmcloud ce app get --name "$(get_env app-name)"
        break
    else
        echo "Application status unknown, retrying"
    fi
    ITERATION="${ITERATION}"+1
done
# shellcheck disable=SC2166
if [ \( -n "$SVC_STATUS_NOT_READY" \) -o \( -n "$SVC_STATUS_UNKNOWN" \) ]; then
    echo ""
    echo "Gathering details to help troubleshooting the problem ..."

    echo ""
    echo "Application details:"
    ibmcloud ce app get --name "$(get_env app-name)" --output yaml

    echo ""
    echo "Application events:"
    ibmcloud ce app events --app "$(get_env app-name)"

    echo ""
    echo "Application logs:"
    ibmcloud ce app logs --app "$(get_env app-name)" --all

    echo ""
    echo "========================================================="
    echo "DEPLOYMENT FAILED"
    echo "========================================================="
    echo "Application is not ready after waiting maximum time"
    echo ""
    echo "Please review the app details, events and logs printed above and check whether the output contains information which relates to the problem."
    echo "Also, please see our troubleshooting guide https://cloud.ibm.com/docs/codeengine?topic=codeengine-ts-app-neverready and check for common issues."
    echo ""

    exit 1
fi
# Determine app url for polling from knative service
TEMP_URL=$(kubectl get "ksvc/${KUBE_SERVICE_NAME}" -o json | jq '.status.url')
echo "Application status URL: $TEMP_URL"
TEMP_URL=${TEMP_URL%\"} # remove end quote
TEMP_URL=${TEMP_URL#\"} # remove beginning quote
APPLICATION_URL=$TEMP_URL
if [ -z "$APPLICATION_URL" ]; then
    echo "Deploy failed, no URL found for application"
    exit 1
fi
echo "Application is available"
echo -e "View the application at: $APPLICATION_URL"
# Record task results
set_env app-url "$APPLICATION_URL"
