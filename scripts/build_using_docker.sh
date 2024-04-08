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

set -euo pipefail

source="$WORKSPACE/$(load_repo app-repo path)/$(get_env source "")"
context_dir="$(get_env context-dir ".")"
dockerfile="$(get_env dockerfile "Dockerfile")"
build_context="$(realpath -m "$source/$context_dir")"
dockerfile_path="$(realpath -m "$build_context/$dockerfile")"

echo "Using Docker CLI to build the container image '$IMAGE'."
echo "   source: $source"
echo "   context-dir: $context_dir"
echo "   dockerfile: $dockerfile"
echo "   docker build context: $build_context"
echo "   dockerfile path: $dockerfile_path"

docker build -t "${IMAGE}" -f "$dockerfile_path" "$build_context"
docker push "${IMAGE}"

DIGEST="$(docker inspect --format='{{index .RepoDigests 0}}' "${IMAGE}" | awk -F@ '{print $2}')"

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
