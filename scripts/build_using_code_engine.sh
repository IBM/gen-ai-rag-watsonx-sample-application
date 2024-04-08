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
REGISTRY_SECRET_NAME="ibmcloud-toolchain-${IBMCLOUD_TOOLCHAIN_ID}-${REGISTRY_URL}"

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

#
# Check whether the repository defined a .ceignore to set optimize the build
# See https://cloud.ibm.com/docs/codeengine?topic=codeengine-plan-build#build-plan-repo
cd "$WORKSPACE/$(load_repo app-repo path)/$(get_env source "")"
if [ ! -f ".ceignore" ]; then
  echo "File .ceignore does not exist. Using '.dockerignore' or '.gitignore' instead"

  # Given the order of copy statements, .dockerignore will be used to define the .ceignore if present
  [ -f .gitignore ] && cp .gitignore .ceignore
  [ -f .dockerignore ] && cp .dockerignore .ceignore
fi
if [ -f ".ceignore" ]; then
  echo "Following file patterns aren't considered as part of the build:"
  cat .ceignore
fi

#
# Helper function which is used in case the Code Engine build fails.
print_mustgather () {

  echo ""
  echo "Gathering details to help troubleshooting the problem ..."

  echo ""
  echo "Build run details:"
  ibmcloud ce buildrun get --name "$1"

  echo ""
  echo "Build run events:"
  ibmcloud ce buildrun events --name "$1"

  echo ""
  echo "Build run logs:"
  ibmcloud ce buildrun logs --name "$1"

  echo ""
  echo "========================================================="
  echo "BUILD FAILED"
  echo "========================================================="
  echo ""
  echo "Please review the build details, events and logs printed above and check whether the output contains information which relates to the problem."
  echo "Also, please see our troubleshooting guide https://cloud.ibm.com/docs/codeengine?topic=codeengine-ts-build-bldpush-stepfail and check for common issues."
  echo ""
}

build_strategy="$(get_env code-engine-build-strategy "dockerfile")"
build_size="$(get_env code-engine-build-size "large")"
build_timeout="$(get_env code-engine-build-timeout "1200")"
wait_timeout="$(get_env code-engine-wait-timeout "1300")"
source="$WORKSPACE/$(load_repo app-repo path)/$(get_env source "")"
context_dir="$(get_env context-dir ".")"
dockerfile="$(get_env dockerfile "Dockerfile")"

# Printing build configuration, prior submitting it
echo "Using Code Engine to build the container image '$IMAGE'."
echo "   strategy: $build_strategy"
echo "   source: $source"
echo "   registry-secret: $REGISTRY_SECRET_NAME"
echo "   context-dir: $context_dir"
echo "   dockerfile: $dockerfile"
echo "   size: $build_size"
echo "   build timeout: $build_timeout"
echo "   wait timeout: $wait_timeout"

BUILD_RUN_NAME="toolchain-run-${PIPELINE_RUN_ID}"
ibmcloud ce buildrun submit --name "${BUILD_RUN_NAME}" \
  --strategy "$build_strategy" \
  --image "$IMAGE" \
  --registry-secret "${REGISTRY_SECRET_NAME}" \
  --source "$source" \
  --context-dir "$context_dir" \
  --dockerfile "$dockerfile" \
  --size "$build_size" \
  --timeout "$build_timeout" \
  --wait --wait-timeout "$wait_timeout" \
  || (print_mustgather "${BUILD_RUN_NAME}" && exit 1)

# Print the build run logs
ibmcloud ce buildrun logs --buildrun "${BUILD_RUN_NAME}"

# Use the icr cli command to retrieve the DIGEST it would prevent to pull back the built image
digest=$(mktemp)
cr_region=$(cat /config/registry-region)
ibmcloud login --apikey @/config/api-key
ibmcloud cr region-set "${cr_region##ibm:yp:}"
ibmcloud cr image-digests --restrict "$ICR_REGISTRY_NAMESPACE/$IMAGE_NAME" --json > "$digest"
# parse the json to find the id
DIGEST=$(jq -r \
  --arg repo "$ICR_REGISTRY_DOMAIN/$ICR_REGISTRY_NAMESPACE/$IMAGE_NAME" \
  --arg tag "$IMAGE_TAG" '.[] | select(.repoTags[$repo][$tag].issueCount >= 0) | .id' "$digest")

echo "Found digest $DIGEST for $ICR_REGISTRY_DOMAIN/$ICR_REGISTRY_NAMESPACE/$IMAGE_NAME:$IMAGE_TAG"

#
# Save the artifact to the pipeline,
# so it can be scanned and signed later
#
save_artifact app-image \
    type=image \
    "name=${IMAGE}" \
    "digest=${DIGEST}" \
    "tags=${IMAGE_TAG}"

#
# Make sure you connect the built artifact to the repo and commit
# it was built from. The source repo asset format is:
#   <repo_URL>.git#<commit_SHA>
#
# In this example we have a repo saved as `app-repo`,
# and we've used the latest cloned state to build the image.
#
url="$(load_repo app-repo url)"
sha="$(load_repo app-repo commit)"

save_artifact app-image \
"source=${url}.git#${sha}"

# optional tags
set +e
TAG="$(cat /config/custom-image-tag)"
set -e
if [[ "${TAG}" ]]; then
    #see build_setup script
    IFS=',' read -ra tags <<< "${TAG}"
    for i in "${!tags[@]}"
    do
        TEMP_TAG=${tags[i]}
        # shellcheck disable=SC2001
        TEMP_TAG=$(echo "$TEMP_TAG" | sed -e 's/^[[:space:]]*//')
        echo "adding tag $i $TEMP_TAG"
        ADDITIONAL_IMAGE_TAG="$ICR_REGISTRY_DOMAIN/$ICR_REGISTRY_NAMESPACE/$IMAGE_NAME:$TEMP_TAG"
        docker tag "$IMAGE" "$ADDITIONAL_IMAGE_TAG"
        docker push "$ADDITIONAL_IMAGE_TAG"

        # save tags to pipelinectl
        image_tags="$(load_artifact app-image tags)"
        save_artifact app-image "tags=${image_tags},${TEMP_TAG}"
    done
fi
