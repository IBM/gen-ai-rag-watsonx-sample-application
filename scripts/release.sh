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

#
# prepare data for the release step. Here we upload all the metadata to the Inventory Repo.
# If you want to add any information or artifact to the inventory repo then use the "cocoa inventory add command"
#

# shellcheck source=/dev/null
. "${ONE_PIPELINE_PATH}/tools/get_repo_params"

APP_REPO="$(load_repo app-repo url)"

COMMIT_SHA="$(load_repo app-repo commit)"

INVENTORY_TOKEN_PATH="./inventory-token"
read -r INVENTORY_REPO_NAME INVENTORY_REPO_OWNER INVENTORY_SCM_TYPE INVENTORY_API_URL < <(get_repo_params "$(get_env INVENTORY_URL)" "$INVENTORY_TOKEN_PATH")
#
# collect common parameters into an array
#
params=(
    --repository-url="${APP_REPO}"
    --commit-sha="${COMMIT_SHA}"
    --version="${COMMIT_SHA}"
    --build-number="${BUILD_NUMBER}"
    --pipeline-run-id="${PIPELINE_RUN_ID}"
    --org="$INVENTORY_REPO_OWNER"
    --repo="$INVENTORY_REPO_NAME"
    --git-provider="$INVENTORY_SCM_TYPE"
    --git-token-path="$INVENTORY_TOKEN_PATH"
    --git-api-url="$INVENTORY_API_URL"
)

#
# add all built images as build artifacts to the inventory
#
while read -r artifact; do
    image="$(load_artifact "${artifact}" name)"
    signature="$(load_artifact "${artifact}" signature)"
    digest="$(load_artifact "${artifact}" digest)"
    tags="$(load_artifact "${artifact}" tags)"

    APP_NAME="$(get_env app-name)"
    APP_ARTIFACTS=$(jq --null-input -c --arg name "${APP_NAME}" --arg tags "${tags}" \
      --arg ce_type "$(get_env code-engine-deployment-type "application")" \
      --arg dev_app_url "$(get_env app-url "")" \
      '.name=$name | .tags=$tags | .code_engine_deployment_type=$ce_type | .dev_app_url=$dev_app_url ')

    # Only keep image name (without namespace part and no tag or sha) for inventory name
    # Image name is remaining part after the repository and namespace and can contains /
    #image_name=$(echo "$image" |  awk -F/ '{a=match($0, $3); print substr($0,a)}' | awk -F@  '{print $1}' | awk -F: '{print $1}')

    cocoa inventory add \
        --artifact="${image}@${digest}" \
        --name="$APP_NAME" \
        --app-artifacts="${APP_ARTIFACTS}" \
        --signature="${signature}" \
        --provenance="${image}@${digest}" \
        --sha256="${digest}" \
        --type="image" \
        "${params[@]}"
done < <(list_artifacts)
