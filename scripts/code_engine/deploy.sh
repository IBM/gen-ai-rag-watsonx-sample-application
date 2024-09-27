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
source "${ONE_PIPELINE_PATH}"/tools/get_repo_params

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

# if in CD pipeline, add the app-url to the inventory entry.
if [[ "$(get_env pipeline_namespace)" == *"cd"* ]]; then
    INVENTORY_PATH="$(get_env inventory-path)"
    DEPLOYMENT_DELTA_PATH="$(get_env deployment-delta-path)"
    jq '.' "$DEPLOYMENT_DELTA_PATH"
    for INVENTORY_ENTRY in $(jq -r '.[]' $DEPLOYMENT_DELTA_PATH); do
        PROVENANCE=$(jq -r '.provenance' ${INVENTORY_PATH}/${INVENTORY_ENTRY})
        APP_NAME=$(jq -r '.name' ${INVENTORY_PATH}/${INVENTORY_ENTRY})

        APP_ARTIFACTS=$(jq --null-input -c \
            --arg name "${APP_NAME}" \
            --arg tags "$(jq -r '.app_artifacts.tags' ${INVENTORY_PATH}/${INVENTORY_ENTRY})" \
            --arg ce_type "$(jq -r '.app_artifacts.code_engine_deployment_type' ${INVENTORY_PATH}/${INVENTORY_ENTRY})" \
            --arg dev_app_url "$(jq -r '.app_artifacts.dev_app_url' ${INVENTORY_PATH}/${INVENTORY_ENTRY})" \
            --arg prod_app_url "${APPLICATION_URL}" \
            '.name=$name | .tags=$tags | .code_engine_deployment_type=$ce_type | .dev_app_url=$dev_app_url | .prod_app_url=$prod_app_url ')

        INVENTORY_TOKEN_PATH="./inventory-token"
        read -r INVENTORY_REPO_NAME INVENTORY_REPO_OWNER INVENTORY_SCM_TYPE INVENTORY_API_URL < <(get_repo_params "$(get_env INVENTORY_URL)" "$INVENTORY_TOKEN_PATH")

        params=(
            --repository-url="$(jq -r '.repository_url' ${INVENTORY_PATH}/${INVENTORY_ENTRY})"
            --commit-sha="$(jq -r '.commit_sha' ${INVENTORY_PATH}/${INVENTORY_ENTRY})"
            --version="$(jq -r '.version' ${INVENTORY_PATH}/${INVENTORY_ENTRY})"
            --build-number="$(jq -r '.build_number' ${INVENTORY_PATH}/${INVENTORY_ENTRY})"
            --pipeline-run-id="$(jq -r '.pipeline_run_id' ${INVENTORY_PATH}/${INVENTORY_ENTRY})"
            --org="$INVENTORY_REPO_OWNER"
            --repo="$INVENTORY_REPO_NAME"
            --git-provider="$INVENTORY_SCM_TYPE"
            --git-token-path="$INVENTORY_TOKEN_PATH"
            --git-api-url="$INVENTORY_API_URL"
        )

        cocoa inventory add \
            --artifact="${PROVENANCE}" \
            --name="${APP_NAME}" \
            --app-artifacts="${APP_ARTIFACTS}" \
            --signature="$(jq -r '.signature' ${INVENTORY_PATH}/${INVENTORY_ENTRY})" \
            --provenance="${PROVENANCE}" \
            --sha256="$(jq -r '.sha256' ${INVENTORY_PATH}/${INVENTORY_ENTRY})" \
            --type="$(jq -r '.type' ${INVENTORY_PATH}/${INVENTORY_ENTRY})" \
            --environment="$(get_env target-environment)" \
            "${params[@]}"
    done
fi
