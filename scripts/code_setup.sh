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

# shellcheck source=/dev/null
source "${ONE_PIPELINE_PATH}"/tools/get_repo_params

APP_TOKEN_PATH="./app-token"
read -r APP_REPO_NAME APP_REPO_OWNER APP_SCM_TYPE APP_API_URL < <(get_repo_params "$(load_repo app-repo url)" "$APP_TOKEN_PATH")

if [[ $APP_SCM_TYPE == "gitlab" ]]; then
  # shellcheck disable=SC2086
  curl --location --request PUT "${APP_API_URL}/projects/$(echo ${APP_REPO_OWNER}/${APP_REPO_NAME} | jq -rR @uri)" \
    --header "PRIVATE-TOKEN: $(cat $APP_TOKEN_PATH)" \
    --header 'Content-Type: application/json' \
    --data-raw '{
    "only_allow_merge_if_pipeline_succeeds": true
    }'
else
  # If PR, then target branch of the PR is the branch to protect
  branch=$(get_env base-branch "")
  if [ -z "$branch" ]; then
    branch="$(cat /config/git-branch)"
  fi
  curl -H "Authorization: Bearer $(cat "${APP_TOKEN_PATH}")" "${APP_API_URL}/repos/${APP_REPO_OWNER}/${APP_REPO_NAME}/branches/$branch/protection" \
    -XPUT -d '{"required_pull_request_reviews":{"dismiss_stale_reviews":true},"required_status_checks":{"strict":true,"contexts":["tekton/code-branch-protection","tekton/code-unit-tests","tekton/code-cis-check","tekton/code-vulnerability-scan","tekton/code-detect-secrets"]},"enforce_admins":null,"restrictions":null}'
fi
