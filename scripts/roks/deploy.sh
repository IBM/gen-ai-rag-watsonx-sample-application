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

setProperty "WA_SERVICE_INSTANCE_ID" "$WA_SERVICE_INSTANCE_ID" "$WORKSPACE/$PIPELINE_CONFIG_REPO_PATH/app.properties"
setProperty "WA_REGION" "$WA_REGION" "$WORKSPACE/$PIPELINE_CONFIG_REPO_PATH/app.properties"
setProperty "WA_INTEGRATION_ID" "$WA_INTEGRATION_ID" "$WORKSPACE/$PIPELINE_CONFIG_REPO_PATH/app.properties"
setProperty "APP_FLAVOR" "$APP_FLAVOR" "$WORKSPACE/$PIPELINE_CONFIG_REPO_PATH/app.properties"

# create configmap from app.properties
#todo: prefix this
oc create configmap gen-ai-rag-sample-app-configmap --from-env-file=$WORKSPACE/$PIPELINE_CONFIG_REPO_PATH/app.properties -o yaml --dry-run=client | oc apply -f -

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

echo "Updating public route in the deployment file ${DEPLOYMENT_FILE}"
PUBLIC_ROUTE_DOC_INDEX=$(yq read --doc "*" --tojson "$DEPLOYMENT_FILE" | jq -r 'to_entries | .[] | select(.value.spec.host | tostring | ascii_downcase=="gen-ai-rag-sample-app-tls-dev.subdomain") | .key')
PUBLIC_INGRESS_SUBDOMAIN=$(get_env cluster_public_ingress_subdomain "")
# There may be some conditions when the pipeline env var is not set for ingress subdomain
# This may happen in the first CI run
# Try to get the domain from the ingress controller, assuming it's named <prefix>-ingress-public
if [[ -z "$PUBLIC_INGRESS_SUBDOMAIN" ]]; then
  PUBLIC_INGRESS_SUBDOMAIN=$(kubectl get ingresscontrollers -n openshift-ingress-operator -o=custom-columns='DOMAIN:.spec.domain,NAME:.metadata.name' --no-headers | grep ingress-public | cut -d ' ' -f1)
fi

if [[ "$(get_env pipeline_namespace)" == *"cd"* ]]; then
  ROUTE_ENVIRONMENT="prod"
else
  ROUTE_ENVIRONMENT="dev"
fi

yq write --doc "${PUBLIC_ROUTE_DOC_INDEX}" "${DEPLOYMENT_FILE}" "spec.host" "gen-ai-rag-sample-app-tls-${ROUTE_ENVIRONMENT}.${PUBLIC_INGRESS_SUBDOMAIN}" > "${TEMP_DEPLOYMENT_FILE}"
mv "${TEMP_DEPLOYMENT_FILE}" "${DEPLOYMENT_FILE}"

# For polyglot practice
source $WORKSPACE/$PIPELINE_CONFIG_REPO_PATH/.env.deploy.sh

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

export APPURL="https://gen-ai-rag-sample-app-tls-${ROUTE_ENVIRONMENT}.${PUBLIC_INGRESS_SUBDOMAIN}"

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
