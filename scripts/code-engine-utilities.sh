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

if [ "$PIPELINE_DEBUG" = "1" ]; then
  pwd
  env
  trap env EXIT
  set -x +e

  export IBMCLOUD_TRACE=true
fi

# shellcheck disable=SC1090,SC1091
source "${ONE_PIPELINE_PATH}/tools/retry"

ibmcloud_login() {
  local -r ibmcloud_api=$(get_env ibmcloud-api "https://cloud.ibm.com")

  ibmcloud config --check-version false
  # Use `code-engine-ibmcloud-api-key` if present, if not, fall back to `ibmcloud-api-key`
  local SECRET_PATH="/config/ibmcloud-api-key"
  if [[ -s "/config/code-engine-ibmcloud-api-key" ]]; then
    SECRET_PATH="/config/code-engine-ibmcloud-api-key"
  fi

  retry 5 3 ibmcloud login -a "$ibmcloud_api" --apikey @"$SECRET_PATH" --no-region
  exit_code=$?
  if [ $exit_code -ne 0 ]; then
    echo "Could not log in to IBM Cloud."
    exit $exit_code
  fi
}

refresh_ibmcloud_session() {
  local login_temp_file="/tmp/ibmcloud-login-cache"
  if [[ ! -f "$login_temp_file" ]]; then
    ibmcloud_login
    touch "$login_temp_file"
  elif [[ -n "$(find "$login_temp_file" -mmin +15)" ]]; then
    ibmcloud_login
    touch "$login_temp_file"
  fi
}

initialize-code-engine-project-context() {
  refresh_ibmcloud_session || return

  # create the project and make it current
  IBMCLOUD_CE_REGION="$(get_env code-engine-region | awk -F ":" '{print $NF}')"
  if [ -z "$IBMCLOUD_CE_REGION" ]; then
    # default to toolchain region
    IBMCLOUD_CE_REGION=$(jq -r '.region_id' /toolchain/toolchain.json | awk -F: '{print $3}')
  fi

  IBMCLOUD_CE_RG="$(get_env code-engine-resource-group)"
  if [ -z "$IBMCLOUD_CE_RG" ]; then
    # default to toolchain resource group
    IBMCLOUD_CE_RG="$(jq -r '.container.guid' /toolchain/toolchain.json)"
  fi
  ibmcloud target -r "$IBMCLOUD_CE_REGION" -g "$IBMCLOUD_CE_RG"

  # Make sure that the latest version of Code Engine CLI is installed
  if ! ibmcloud plugin show code-engine > /dev/null 2>&1; then
    echo "Installing code-engine plugin"
    ibmcloud plugin install code-engine
  else
    echo "Updating code-engine plugin"
    ibmcloud plugin update code-engine --force
  fi

  echo "Check Code Engine project availability"
  if ibmcloud ce proj get -n "$(get_env code-engine-project)" > /dev/null 2>&1; then
    echo -e "Code Engine project $(get_env code-engine-project) found."
  else
    echo -e "No Code Engine project with the name $(get_env code-engine-project) found. Creating new project..."
    ibmcloud ce proj create -n "$(get_env code-engine-project)"
    echo -e "Code Engine project $(get_env code-engine-project) created."
  fi

  echo "Loading Kube config..."
  if ! ibmcloud ce proj select -n "$(get_env code-engine-project)" -k; then
    echo "Code Engine project $(get_env code-engine-project) can not be selected"
    return 1
  fi

  # Add service binding resource group to the project if specified
  IBMCLOUD_CE_BINDING_RG=$(get_env code-engine-binding-resource-group "")
  if [ -n "$IBMCLOUD_CE_BINDING_RG" ]; then
    echo "Updating Code Engine project to bind to resource group $IBMCLOUD_CE_BINDING_RG..."
    ibmcloud ce project update --binding-resource-group "$IBMCLOUD_CE_BINDING_RG"
  fi

}

deploy-code-engine-application() {
  refresh_ibmcloud_session || return

  local application=$1
  local image=$2
  local image_pull_secret=$3

  # scope/prefix for env property for given environment properties
  local prefix="${application}_"

  env_from_configmap_params="$(get_env "${prefix}env-from-configmaps" "$(get_env env-from-configmaps "")")"
  if [ -n "$env_from_configmap_params" ]; then
    # replace ; by appropriate parameter
    env_from_configmap_params="--env-from-configmap ${env_from_configmap_params//;/ --env-from-configmap\ }"
  fi

  if [ -n "$(get_env cd-auto-managed-env-configmap "")" ]; then
    env_from_configmap_params="--env-from-configmap $(get_env cd-auto-managed-env-configmap) $env_from_configmap_params"
  fi

  env_from_secret_params="$(get_env "${prefix}env-from-secrets" "$(get_env env-from-secrets "")")"
  if [ -n "$env_from_secret_params" ]; then
    # replace ; by appropriate parameter
    env_from_secret_params="--env-from-secret ${env_from_secret_params//;/ --env-from-secret\ }"
  fi

  if [ -n "$(get_env cd-auto-managed-env-secret "")" ]; then
    env_from_secret_params="--env-from-secret $(get_env cd-auto-managed-env-secret) $env_from_secret_params"
  fi

  json_file=$(mktemp)
  if ibmcloud ce app get -n "${application}" --output json > $json_file 2>&1; then
    echo "Code Engine app with name ${application} found, updating it"
    operation="update"
    if [ "$(get_env remove-unspecified-references-to-configuration-resources "false")" == "true" ]; then
      # ensure synchronization of references to configmaps or secrets for the given application
      json_spec=$(jq -c '.spec.template.spec.containers[0]' $json_file)
      env_from_configmap_rm_params=$(compute-env-configuration-resources-references-remove-parameters configmap "$json_spec" "$env_from_configmap_params")
      env_from_secret_rm_params=$(compute-env-configuration-resources-references-remove-parameters secret "$json_spec" "$env_from_secret_params")
      env_rm_params=$(compute-individual-configuration-resource-remove-parameters "$json_spec" "$env_from_configmap_params" "$env_from_secret_params")
    fi
  else
    echo "Code Engine app with name ${application} not found, creating it"
    operation="create"
  fi

  local cpu
  cpu="$(get_env "${prefix}cpu" "$(get_env cpu "0.25")")"
  local memory
  memory="$(get_env "${prefix}memory" "$(get_env memory "0.5G")")"
  local ephemeral_storage
  ephemeral_storage="$(get_env "${prefix}ephemeral-storage" "$(get_env ephemeral-storage "0.4G")")"
  local min
  min="$(get_env "${prefix}app-min-scale" "$(get_env app-min-scale "0")")"
  local max
  max="$(get_env "${prefix}app-max-scale" "$(get_env app-max-scale "1")")"
  local scale_down_delay
  scale_down_delay="$(get_env "${prefix}app-scale_down_delay" "$(get_env app-scale_down_delay "3600")")"
  local concurrency
  concurrency="$(get_env "${prefix}app-concurrency" "$(get_env app-concurrency "100")")"
  local visibility
  visibility="$(get_env "${prefix}app-visibility" "$(get_env app-visibility "public")")"
  local port
  port="$(get_env "${prefix}app-port" "$(get_env app-port "8080")")"

  echo "   image: $image"
  echo "   registry-secret: $image_pull_secret"
  echo "   env-from-configmap: $env_from_configmap_params"
  echo "   env-from-secret: $env_from_secret_params"
  if [ -n "$env_from_configmap_rm_params" ]; then
    echo "   env-from-configmap-rm parameters: $env_from_configmap_rm_params"
  fi
  if [ -n "$env_from_secret_rm_params" ]; then
    echo "   env-from-secret-rm parameters: $env_from_secret_rm_params"
  fi
  if [ -n "$env_rm_params" ]; then
    echo "   env-rm parameters: $env_rm_params"
  fi
  echo "   cpu: $cpu"
  echo "   memory: $memory"
  echo "   ephemeral-storage: $ephemeral_storage"
  echo "   min: $min"
  echo "   max: $max"
  echo "   concurrency: $concurrency"
  echo "   visibility: $visibility"
  echo "   port: $port"

  # shellcheck disable=SC2086
  if ! ibmcloud ce app $operation -n "${application}" \
      --image "${image}" \
      --registry-secret "${image_pull_secret}" \
      $env_from_configmap_params \
      $env_from_secret_params \
      $env_from_configmap_rm_params \
      $env_from_secret_rm_params \
      $env_rm_params \
      --cpu "$cpu" \
      --memory "$memory" \
      --ephemeral-storage "$ephemeral_storage" \
      --min "$min" \
      --max "$max" \
      --scale-down-delay "$scale_down_delay" \
      --concurrency "$concurrency" \
      --visibility "$visibility" \
      --port "$port" \
      --wait=false; then
    echo "ibmcloud ce app $operation failed."
    return 1
  fi
}

deploy-code-engine-job() {
  refresh_ibmcloud_session || return

  local job=$1
  local image=$2
  local image_pull_secret=$3

  # scope/prefix for env property for given environment properties
  local prefix="${job}_"

  env_from_configmap_params="$(get_env "${prefix}env-from-configmaps" "$(get_env env-from-configmaps "")")"
  if [ -n "$env_from_configmap_params" ]; then
    # replace ; by appropriate parameter
    env_from_configmap_params="--env-from-configmap ${env_from_configmap_params//;/ --env-from-configmap\ }"
  fi

  if [ -n "$(get_env cd-auto-managed-env-configmap "")" ]; then
    env_from_configmap_params="--env-from-configmap $(get_env cd-auto-managed-env-configmap) $env_from_configmap_params"
  fi

  env_from_secret_params="$(get_env "${prefix}env-from-secrets" "$(get_env env-from-secrets "")")"
  if [ -n "$env_from_secret_params" ]; then
    # replace ; by appropriate parameter
    env_from_secret_params="--env-from-secret ${env_from_secret_params//;/ --env-from-secret\ }"
  fi

  if [ -n "$(get_env cd-auto-managed-env-secret "")" ]; then
    env_from_secret_params="--env-from-secret $(get_env cd-auto-managed-env-secret) $env_from_secret_params"
  fi

  json_file=$(mktemp)
  if ibmcloud ce job get --name "${job}" --output json > $json_file 2>&1; then
    echo "Code Engine job with name ${job} found, updating it"
    operation="update"
    if [ "$(get_env remove-unspecified-references-to-configuration-resources "false")" == "true" ]; then
      # ensure synchronization of references to configmaps or secrets for the given job
      json_spec=$(jq -c '.spec.template.containers[0]' $json_file)
      env_from_configmap_rm_params=$(compute-env-configuration-resources-references-remove-parameters configmap "$json_spec" "$env_from_configmap_params")
      env_from_secret_rm_params=$(compute-env-configuration-resources-references-remove-parameters secret "$json_spec" "$env_from_secret_params")
      env_rm_params=$(compute-individual-configuration-resource-remove-parameters "$json_spec" "$env_from_configmap_params" "$env_from_secret_params")
    fi
  else
    echo "Code Engine job with name ${job} not found, creating it"
    operation="create"
  fi

  local cpu
  cpu="$(get_env "${prefix}cpu" "$(get_env cpu "0.25")")"
  local memory
  memory="$(get_env "${prefix}memory" "$(get_env memory "0.5G")")"
  local ephemeral_storage
  ephemeral_storage="$(get_env "${prefix}ephemeral-storage" "$(get_env ephemeral-storage "0.4G")")"
  local retrylimit
  retrylimit="$(get_env "${prefix}job-retrylimit" "$(get_env job-retrylimit "3")")"
  local maxexecutiontime
  maxexecutiontime="$(get_env "${prefix}job-maxexecutiontime" "$(get_env job-maxexecutiontime "7200")")"
  local instances
  instances="$(get_env "${prefix}job-instances" "$(get_env job-instances "1")")"

  echo "   image: $image"
  echo "   registry-secret: $image_pull_secret"
  echo "   env-from-configmap: $env_from_configmap_params"
  echo "   env-from-secret: $env_from_secret_params"
  if [ -n "$env_from_configmap_rm_params" ]; then
    echo "   env-from-configmap-rm parameters: $env_from_configmap_rm_params"
  fi
  if [ -n "$env_from_secret_rm_params" ]; then
    echo "   env-from-secret-rm parameters: $env_from_secret_rm_params"
  fi
  if [ -n "$env_rm_params" ]; then
    echo "   env-rm parameters: $env_rm_params"
  fi
  echo "   cpu: $cpu"
  echo "   memory: $memory"
  echo "   ephemeral-storage: $ephemeral_storage"
  echo "   instances: $instances"
  echo "   retrylimit: $retrylimit"
  echo "   maxexecutiontime: $maxexecutiontime"

  # shellcheck disable=SC2086
  if ! ibmcloud ce job $operation -n "${job}" \
      --image "${image}" \
      --registry-secret "${image_pull_secret}" \
      $env_from_configmap_params \
      $env_from_secret_params \
      $env_from_configmap_rm_params \
      $env_from_secret_rm_params \
      $env_rm_params \
      --cpu "$cpu" \
      --memory "$memory" \
      --ephemeral-storage "$ephemeral_storage" \
      --instances "$instances" \
      --retrylimit "$retrylimit" \
      --maxexecutiontime "$maxexecutiontime"; then
    echo "ibmcloud ce job $operation failed."
    return 1
  fi
}

bind-services-to-code-engine-application() {
  local application=$1
  bind-services-to-code-engine_ "app" "$application"
}

bind-services-to-code-engine-job() {
  local job=$1
  bind-services-to-code-engine_ "job" "$job"
}

bind-services-to-code-engine_() {
  refresh_ibmcloud_session || return

  local kind=$1
  local ce_element=$2

  # scope/prefix for env property for given environment properties
  local prefix="${ce_element}_"

  # if there is some existing bindings, first remove them all
  # shellcheck disable=SC2086
  ibmcloud ce $kind unbind -n "$ce_element" --all --quiet

  sb_property_file="$CONFIG_DIR/${prefix}service-bindings"
  if [ ! -f "$sb_property_file" ]; then
    sb_property_file="$CONFIG_DIR/service-bindings"
    if [ ! -f "$sb_property_file" ]; then
      sb_property_file=""
    fi
  fi
  if [ -n "$sb_property_file" ]; then
    echo "bind services to code-engine $kind $ce_element"
    # ensure well-formatted json
    if ! jq '.' "$sb_property_file"; then
      echo "Invalid JSON in $sb_property_file"
      return 1
    fi
    # shellcheck disable=SC2162
    while read; do
      NAME=$(echo "$REPLY" | jq -r 'if type=="string" then . else (to_entries[] | .key) end')
      PREFIX=$(echo "$REPLY" | jq -r 'if type=="string" then empty else (to_entries[] | .value) end')
      if [ -n "$PREFIX" ]; then
        prefix_arg="-p $PREFIX"
      else
        prefix_arg=""
      fi
      echo "Binding $NAME to $kind $ce_element  with prefix '$PREFIX'"
      # shellcheck disable=SC2086
      if ! ibmcloud ce $kind bind -n "$ce_element" --si "$NAME" $prefix_arg -w=false; then
        echo "Fail to bind $NAME to $kind $ce_element with prefix '$PREFIX'"
        return 1
      fi
    done < <(jq -c '.[]' "$sb_property_file" )
  fi
}

setup-cd-auto-managed-env-configmap() {
  local scope=$1
  # filter the pipeline/trigger non-secured properties with ${scope}CE_ENV prefix and create the configmap
  # if there is some properties, create/update the configmap for this given scope
  # and set it as set_env cd-auto-managed-env-configmap
  setup-cd-auto-managed-env-component_ "configmap" "$scope"
}

setup-cd-auto-managed-env-secret() {
  local scope=$1
  # filter the pipeline/trigger secured properties with ${scope}CE_ENV prefix and create the configmap
  # if there is some properties, create/update the secret for this given scope
  # and set it as set_env cd-auto-managed-env-secret
  setup-cd-auto-managed-env-component_ "secret" "$scope"
}

setup-cd-auto-managed-env-component_() {
  local kind=$1
  local scope=$2
  local prefix
  if [ -n "$scope" ]; then
    prefix="${scope}_"
  else
    prefix=""
  fi

  if [ "$kind" == "secret" ]; then
    properties_files_path="/config/secure-properties"
  else
    properties_files_path="/config/environment-properties"
  fi

  props=$(mktemp)
  # shellcheck disable=SC2086,SC2012
  if [ "$(ls -1 ${properties_files_path}/CE_ENV_* 2>/dev/null | wc -l)" != "0" ]; then
    # shellcheck disable=SC2086,SC2012
    for prop in "${properties_files_path}/CE_ENV_"*; do
      # shellcheck disable=SC2295
      echo "${prop##${properties_files_path}/CE_ENV_}=$(cat $prop)" >> $props
    done
  fi
  # shellcheck disable=SC2086,SC2012
  if [ "$(ls -1 ${properties_files_path}/${prefix}CE_ENV_* 2>/dev/null | wc -l)" != "0" ]; then
    # shellcheck disable=SC2086,SC2012
    for prop in "${properties_files_path}/${prefix}CE_ENV_"*; do
      # shellcheck disable=SC2295
      echo "${prop##${properties_files_path}/${prefix}CE_ENV_}=$(cat $prop)" >> $props
    done
  fi

  configuration_resource_name="cd-auto-$scope-${PIPELINE_ID}-$kind"

  if [ -s "$props" ]; then
    # shellcheck disable=SC2086
    if ibmcloud ce $kind get --name "$configuration_resource_name" > /dev/null 2>&1; then
      # configmap get does not fail if non existing - use the json output to ensure existing or not
      if [[ "$kind" == "configmap" && -z "$(ibmcloud ce $kind get --name "$configuration_resource_name" --output json | jq -r '.metadata.name//empty')" ]]; then
        echo "$kind $configuration_resource_name does not exist. Creating it"
        operation="create"
      else
        echo "$kind $configuration_resource_name already exists. Updating it"
        operation="update"
      fi
    else
      echo "$kind $configuration_resource_name does not exist. Creating it"
      operation="create"
    fi
    # shellcheck disable=SC2086
    ibmcloud ce $kind $operation --name "$configuration_resource_name" --from-env-file "$props"
    set_env "cd-auto-managed-env-$kind" "$configuration_resource_name"
  else
    set_env "cd-auto-managed-env-$kind" ""
  fi
}

# function to return codeengine update parameters for configuration resources to remove
compute-env-configuration-resources-references-remove-parameters() {
  # configmap or secret
  local kind=$1
  local entity_json_spec=$2
  local params_for_env_from_configuration_resources=$3
  if [ "$kind" == "configmap" ]; then
      kindOfRef="configMapRef"
      command="--env-from-configmap-rm"
  else
      kindOfRef="secretRef"
      command="--env-from-secret-rm"
  fi
  rm_command_parameters=""
  current_references=$(echo $entity_json_spec | jq -r --arg kindOfRef "$kindOfRef" '.envFrom[] | select(.[$kindOfRef]) | if has("prefix") then .prefix + "=" + .[$kindOfRef].name else .[$kindOfRef].name end')
  while read -r a_reference; do
    # check if current reference is still present in the params_for_env_from_configuration_resources
    if [[ "$params_for_env_from_configuration_resources" != *"$a_reference"* ]]; then
      # current reference is not required anymore
      if [[ $a_reference == *"="* ]]; then
        # use only the configmap or secret name
        rm_command_parameter=" $command $(echo $a_reference | awk -F= '{print $2}')"
      else
        rm_command_parameter=" $command $a_reference"
      fi
      rm_command_parameters="$rm_command_parameters $rm_command_parameter"
    fi
  done <<< "$current_references"
  echo $rm_command_parameters
}

# function to return codeengine update parameters for individual configuration resource to remove
compute-individual-configuration-resource-remove-parameters() {
  local entity_json_spec=$1
  local params_for_env_from_configmap=$2
  local params_for_env_from_secret=$3

  rm_command_parameters=""
  current_individual_env_references=$(echo $entity_json_spec | jq -r '.env[] | select(has("valueFrom")) | (.valueFrom.configMapKeyRef//.valueFrom.secretKeyRef).key as $key | (.valueFrom.configMapKeyRef//.valueFrom.secretKeyRef).name as $resource_name | if .name == $key then $resource_name + ":" + $key else $resource_name + ":" + .name + "=" + $key end')
  while read -r an_individual_env_reference; do
    # check if current individual env reference is still present in the params_for_env_from_configmap or params_for_env_from_secret
    if [[ "$params_for_env_from_configmap" != *"$an_individual_env_reference"* ]] && [[ "$params_for_env_from_secret" != *"$an_individual_env_reference"* ]]; then
      # individual env rm command expect the environment variable name as argument
      rm_command_parameters="$rm_command_parameters --env-rm $(echo "$an_individual_env_reference" | awk -F: '{print $2}' | awk -F= '{print $1}')"
    fi
  done <<< "$current_individual_env_references"
  echo $rm_command_parameters
}
