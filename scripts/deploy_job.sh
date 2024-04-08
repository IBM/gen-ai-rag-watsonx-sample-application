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

echo "Deploying your code as Code Engine job...."
setup-cd-auto-managed-env-configmap "$(get_env app-name)"
setup-cd-auto-managed-env-secret "$(get_env app-name)"
if ! deploy-code-engine-job "$(get_env app-name)" "${IMAGE}" "${REGISTRY_SECRET_NAME}"; then
  echo "Failure in code engine job deployment. Exiting 1"
  exit 1
fi

# Bind services, if any
if ! bind-services-to-code-engine-job "$(get_env app-name)"; then
  echo "Failure in services binding to code engine job. Exiting 1"
  exit 1
fi

echo "Checking if job is ready..."
# TODO
