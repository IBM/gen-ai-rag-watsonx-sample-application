#!/usr/bin/env bash

# function to update properties
setProperty(){
  awk -v pat="^$1=" -v value="$1=$2" '{ if ($0 ~ pat) print value; else print $0; }' $3 > $3.tmp
  mv $3.tmp $3
}

source "${ONE_PIPELINE_PATH}"/tools/get_repo_params

# create namespace using oc
oc new-project ${IBMCLOUD_IKS_CLUSTER_NAMESPACE} || oc project ${IBMCLOUD_IKS_CLUSTER_NAMESPACE}

# update app.properties to use correct WatsonX Assistant values
WA_SERVICE_INSTANCE_ID=$(get_env watsonx_assistant_id "")
WA_REGION=$(get_env watsonx_assistant_region "us-south")
WA_INTEGRATION_ID=$(get_env watsonx_assistant_integration_id "")
APP_FLAVOR=$(get_env app-flavor "")

source="$WORKSPACE/$(load_repo app-repo path)/$(get_env source "")"
build_context="$(realpath -m "$source")"

setProperty "WA_SERVICE_INSTANCE_ID" "$WA_SERVICE_INSTANCE_ID" "$build_context/app.properties"
setProperty "WA_REGION" "$WA_REGION" "$build_context/app.properties"
setProperty "WA_INTEGRATION_ID" "$WA_INTEGRATION_ID" "$build_context/app.properties"
setProperty "APP_FLAVOR" "$APP_FLAVOR" "$build_context/app.properties"

# create configmap from app.properties
#todo: prefix this
oc create configmap gen-ai-rag-sample-app-configmap --from-env-file=$build_context/app.properties -o yaml --dry-run=client | oc apply -f -

echo "Updating the namespace in the deployment file ${DEPLOYMENT_FILE}"
NAMESPACE_DOC_INDEX=$(yq read --doc "*" --tojson "${DEPLOYMENT_FILE}" | jq -r 'to_entries | .[] | select(.value.kind | ascii_downcase=="namespace") | .key')
yq w -d "${NAMESPACE_DOC_INDEX}" "${DEPLOYMENT_FILE}" metadata.name "${IBMCLOUD_IKS_CLUSTER_NAMESPACE}" > "${TEMP_DEPLOYMENT_FILE}"
mv "${TEMP_DEPLOYMENT_FILE}" "${DEPLOYMENT_FILE}"
yq write --inplace "$DEPLOYMENT_FILE" --doc "*" "metadata.namespace" "${IBMCLOUD_IKS_CLUSTER_NAMESPACE}"

echo "Updating Image Pull Secrets Name in the deployment file ${DEPLOYMENT_FILE}"
SECRET_DOC_INDEX=$(yq read --doc "*" --tojson "$DEPLOYMENT_FILE" | jq -r 'to_entries | .[] | select((.value.kind | ascii_downcase=="secret") and (.value.type | ascii_downcase=="kubernetes.io/dockerconfigjson")) | .key')
yq write --doc "${SECRET_DOC_INDEX}" "${DEPLOYMENT_FILE}" "metadata.name" "${IMAGE_PULL_SECRET_NAME}" > "${TEMP_DEPLOYMENT_FILE}"
mv "${TEMP_DEPLOYMENT_FILE}" "${DEPLOYMENT_FILE}"

SERVICE_ACCOUNT_DOC_INDEX=$(yq read --doc "*" --tojson "$DEPLOYMENT_FILE" | jq -r 'to_entries | .[] | select(.value.kind | ascii_downcase=="serviceaccount") | .key')
yq write --doc "${SERVICE_ACCOUNT_DOC_INDEX}" "${DEPLOYMENT_FILE}" "imagePullSecrets[0].name" "${IMAGE_PULL_SECRET_NAME}" > "${TEMP_DEPLOYMENT_FILE}"
mv "${TEMP_DEPLOYMENT_FILE}" "${DEPLOYMENT_FILE}"


echo "Updating Image Pull Secrets in the deployment file ${DEPLOYMENT_FILE}"
REGISTRY_AUTH=""
if [[ -n "$BREAK_GLASS" ]]; then
  REGISTRY_AUTH=$(jq .parameters.docker_config_json /config/artifactory)
else
  # Use the API key used for the image build as IAM API key to create the image pull secret, if corresponding parameter has been set.
  # See build_setup.sh for the container registry credentials/login
  CR_IAM_API_KEY="$(cat /config/api-key)" # pragma: allowlist secret
  REGISTRY_AUTH=$(echo "{\"auths\":{\"${REGISTRY_URL}\":{\"auth\":\"$(echo -n iamapikey:"${CR_IAM_API_KEY}" | base64 -w 0)\",\"username\":\"iamapikey\",\"email\":\"iamapikey\",\"password\":\"${CR_IAM_API_KEY}\"}}}" | base64 -w 0)
fi
yq write --doc "${SECRET_DOC_INDEX}" "${DEPLOYMENT_FILE}" "data[.dockerconfigjson]" "${REGISTRY_AUTH}" > "${TEMP_DEPLOYMENT_FILE}"
mv "${TEMP_DEPLOYMENT_FILE}" "${DEPLOYMENT_FILE}"

# For polyglot practice
source $WORKSPACE/$PIPELINE_CONFIG_REPO_PATH/.env.deploy.sh

echo "Cluster IP Service should be unique accross all the namespace, updating Cluster IP service name with namespace..."
CIP_DOC_INDEX=$(yq read --doc "*" --tojson "$DEPLOYMENT_FILE" | jq -r 'to_entries | .[] | select(.value.spec.type=="ClusterIP" ) | .key')
CIP_SERVICE_NAME=$(yq r --doc "$CIP_DOC_INDEX" "$DEPLOYMENT_FILE" metadata.name)
CIP_SERVICE_NAME="${CIP_SERVICE_NAME}"-"${IBMCLOUD_IKS_CLUSTER_NAMESPACE}"
yq write --doc "${CIP_DOC_INDEX}" "${DEPLOYMENT_FILE}" "metadata.name" "${CIP_SERVICE_NAME}" > "${TEMP_DEPLOYMENT_FILE}"
mv "${TEMP_DEPLOYMENT_FILE}" "${DEPLOYMENT_FILE}"
if [ "${CLUSTER_TYPE}" == "OPENSHIFT" ]; then
  ROUTE_DOC_INDEX=$(yq read --doc "*" --tojson "$DEPLOYMENT_FILE" | jq -r 'to_entries | .[] | select(.value.kind | ascii_downcase=="route") | .key')
  yq write --doc "${ROUTE_DOC_INDEX}" "${DEPLOYMENT_FILE}" "spec.to.name" "${CIP_SERVICE_NAME}" > "${TEMP_DEPLOYMENT_FILE}"
  mv "${TEMP_DEPLOYMENT_FILE}" "${DEPLOYMENT_FILE}"
fi

INGRESS_DOC_INDEX=$(yq read --doc "*" --tojson "$DEPLOYMENT_FILE" | jq -r 'to_entries | .[] | select(.value.kind | ascii_downcase=="ingress") | .key')
if [ -n "${INGRESS_DOC_INDEX}" ]; then
  echo "Updating Cluster IP service name in the ingress in ${DEPLOYMENT_FILE}"
  yq write --doc "${INGRESS_DOC_INDEX}" "${DEPLOYMENT_FILE}" "spec.rules[0].http.paths[*].backend.service.name" "${CIP_SERVICE_NAME}" > "${TEMP_DEPLOYMENT_FILE}"
  mv "${TEMP_DEPLOYMENT_FILE}" "${DEPLOYMENT_FILE}"
fi

# Check if the cluster is paid IKS cluster. If yes then update the cluster domain name in place for the host name.
CLUSTER_INGRESS_SUBDOMAIN=$(ibmcloud ks cluster get --cluster "${IBMCLOUD_IKS_CLUSTER_NAME}" --json | jq -r '.ingressHostname // .ingress.hostname' | cut -d, -f1)
INGRESS_DOC_INDEX=$(yq read --doc "*" --tojson "$DEPLOYMENT_FILE" | jq -r 'to_entries | .[] | select(.value.kind | ascii_downcase=="ingress") | .key')
if [ -n "${CLUSTER_INGRESS_SUBDOMAIN}" ] && [ "${KEEP_INGRESS_CUSTOM_DOMAIN}" != true ]; then
  if [ -z "${INGRESS_DOC_INDEX}" ]; then
    echo "No Kubernetes Ingress definition found in $DEPLOYMENT_FILE."
  else
    # Update ingress with cluster domain/secret information
    # Look for ingress rule whith host contains the token "cluster-ingress-subdomain"
    INGRESS_RULES_INDEX=$(yq r --doc "${INGRESS_DOC_INDEX}" --tojson "${DEPLOYMENT_FILE}" | jq '.spec.rules | to_entries | .[] | select( .value.host | contains("cluster-ingress-subdomain")) | .key')
    if [ -n "${INGRESS_RULES_INDEX}" ]; then
      INGRESS_RULE_HOST=$(yq r --doc "${INGRESS_DOC_INDEX}" "${DEPLOYMENT_FILE}" spec.rules["${INGRESS_RULES_INDEX}"].host)
      DOMAIN_ADDRESS="${IBMCLOUD_IKS_CLUSTER_NAMESPACE}"."${CLUSTER_INGRESS_SUBDOMAIN}"
      # IKS provides a valid TLS certificate for *.Cluster-ingress-sub-domian
      # Update the host with format {App-Name}-{Cluster-Namespace}.{Cluster-ingress-subdomain}
      # Example :- https://hello-app-prod.gen2phm-b-57a8db4f565402d4797cc1d3399c50e2-0000.eu-de.containers.appdomain.cloud/
      # hello-app is from INGRESS_RULES_INDEX
      # prod is cluster namespace
      yq w --inplace --doc "${INGRESS_DOC_INDEX}" "${DEPLOYMENT_FILE}" spec.rules["${INGRESS_RULES_INDEX}"].host "${INGRESS_RULE_HOST/.cluster-ingress-subdomain/-$DOMAIN_ADDRESS}"
    fi
  fi
fi

CLUSTER_INGRESS_SECRET=$(ibmcloud ks cluster get --cluster "${IBMCLOUD_IKS_CLUSTER_NAME}" --json | jq -r '.ingressSecretName // .ingress.secretName' | cut -d, -f1 )
if [ "${CLUSTER_TYPE}" == "OPENSHIFT" ]; then
  ROUTE_DOC_INDEX=$(yq read --doc "*" --tojson "$DEPLOYMENT_FILE" | jq -r 'to_entries | .[] | select(.value.kind | ascii_downcase=="route") | .key')
  if [ -n "$ROUTE_DOC_INDEX" ]; then
    route_spec_tls="$(yq read --doc "${ROUTE_DOC_INDEX}" "${DEPLOYMENT_FILE}" spec.tls)"
    if [ -z "$route_spec_tls" ] || [ "$route_spec_tls" == "null" ]; then
      echo "Setting spec.tls in Route"
      yq w --inplace --doc "${ROUTE_DOC_INDEX}" "${DEPLOYMENT_FILE}" spec.tls.termination "edge"
    fi
  fi
fi

# Portieris is not compatible with image name containing both tag and sha. Removing the tag
IMAGE="${IMAGE#*"@"}"
sed -i "s~^\([[:blank:]]*\)image:.*$~\1image: ${IMAGE}~" "${DEPLOYMENT_FILE}"

DEPLOYMENT_DOC_INDEX=$(yq read --doc "*" --tojson "$DEPLOYMENT_FILE" | jq -r 'to_entries | .[] | select(.value.kind | ascii_downcase=="deployment") | .key')
SERVICE_DOC_INDEX=$(yq read --doc "*" --tojson "$DEPLOYMENT_FILE" | jq -r 'to_entries | .[] | select(.value.spec.type=="NodePort" ) | .key')

deployment_name=$(yq r -d "${DEPLOYMENT_DOC_INDEX}" "${DEPLOYMENT_FILE}" metadata.name)

kubectl apply --namespace "$IBMCLOUD_IKS_CLUSTER_NAMESPACE" -f "${DEPLOYMENT_FILE}"
if kubectl rollout status --namespace "$IBMCLOUD_IKS_CLUSTER_NAMESPACE" "deployment/$deployment_name"; then
  status=success
else
  status=failure
fi

kubectl get events --sort-by=.metadata.creationTimestamp -n "$IBMCLOUD_IKS_CLUSTER_NAMESPACE"

if [ "$status" = failure ]; then
  echo "Deployment failed"
  if [[ -z "$BREAK_GLASS" ]]; then
    ibmcloud cr quota
  fi
  exit 1
fi

export APPURL
if [ "${CLUSTER_TYPE}" == "OPENSHIFT" ]; then
  ROUTE_DOC_INDEX=$(yq read --doc "*" --tojson "$DEPLOYMENT_FILE" | jq -r 'to_entries | .[] | select(.value.kind | ascii_downcase=="route") | .key')
  if [ -n "$ROUTE_DOC_INDEX" ]; then
    route_name=$(yq r --doc "$ROUTE_DOC_INDEX" "$DEPLOYMENT_FILE" metadata.name)
    route_json_file=$(mktemp)
    kubectl get route --namespace "$IBMCLOUD_IKS_CLUSTER_NAMESPACE" "${route_name}" -o json > $route_json_file
    route_host="$(jq -r '.spec.host//empty' "$route_json_file")"
    route_path="$(jq -r '.spec.path//empty' "$route_json_file")"
    # Remove the last / from selected_route_path if any
    route_path="${route_path%/}"
    if jq -e '.spec.tls' "$route_json_file" > /dev/null 2>&1; then
      route_protocol="https"
    else
      route_protocol="http"
    fi
    APPURL="${route_protocol}://${route_host}${route_path}"
  fi
else
  sleep 10
  if [ -n "${CLUSTER_INGRESS_SUBDOMAIN}" ] && [ "${KEEP_INGRESS_CUSTOM_DOMAIN}" != true ]; then
    if [ -z "$INGRESS_DOC_INDEX" ]; then
      echo "No Kubernetes Ingress definition found in $DEPLOYMENT_FILE."
    else
      service_name=$(yq r --doc "$INGRESS_DOC_INDEX" "$DEPLOYMENT_FILE" metadata.name)
      # shellcheck disable=SC2034
      for ITER in {1..30}
      do
        INGRESS_JSON=$(kubectl get ingress --namespace "${IBMCLOUD_IKS_CLUSTER_NAMESPACE}" "${service_name}" -o json)
        # Expose app using ingress host and path for the service
        APP_HOST=$(echo "$INGRESS_JSON" | jq -r --arg service_name "${CIP_SERVICE_NAME}" '.spec.rules[] | first(select(.http.paths[].backend.serviceName==$service_name or .http.paths[].backend.service.name==$service_name)) | .host' | head -n1)
        APP_PATH=$(echo "$INGRESS_JSON" | jq -r --arg service_name "${CIP_SERVICE_NAME}" '.spec.rules[].http.paths[] | first(select(.backend.serviceName==$service_name or .backend.service.name==$service_name)) | .path' | head -n1)
        # Remove any group in the path in case of regex in ingress path definition
        # https://kubernetes.github.io/ingress-nginx/user-guide/ingress-path-matching/
        # shellcheck disable=SC2001
        APP_PATH=$(echo "$APP_PATH" | sed "s/([^)]*)//g")
        # Remove the last / from APP_PATH if any
        APP_PATH="${APP_PATH%/}"
        if [ -n  "${APP_HOST}"  ]; then
          APPURL="https://${APP_HOST}""${APP_PATH}"
          break
        fi
        sleep 2
      done
    fi
  fi

  # If unable to find the APP_URL and Ingress sub domain is not available.
  if [ -z  "${APPURL}"  ] || [[  "${APPURL}" = "null"  ]]; then
    service_name=$(yq r -d "${SERVICE_DOC_INDEX}" "${DEPLOYMENT_FILE}" metadata.name)
    IP_ADDRESS=$(kubectl get nodes -o json | jq -r '[.items[] | .status.addresses[] | select(.type == "ExternalIP") | .address] | .[0]')
    PORT=$(kubectl get service -n "$IBMCLOUD_IKS_CLUSTER_NAMESPACE" "$service_name" -o json | jq -r '.spec.ports[0].nodePort')
    APPURL="http://${IP_ADDRESS}:${PORT}"
  fi
fi

if [ -z  "${APPURL}"  ] || [[  "${APPURL}" = "null"  ]] || [[  "${APPURL}" = ":"  ]]; then
    echo "Unable to get Application URL....."
    exit 1
fi

echo "Application URL: ${APPURL}"
echo -n "${APPURL}" >../app-url
set_env app-url "${APPURL}"

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
