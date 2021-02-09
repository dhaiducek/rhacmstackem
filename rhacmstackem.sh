#! /bin/bash

set -e

# Clone requisite repos and store paths
echo "$(date) ##### Cloning Lifeguard, Deploy, Pipeline, and StartRHACM repos"
git clone https://github.com/dhaiducek/startrhacm.git
git clone https://github.com/open-cluster-management/lifeguard.git
git clone "https://${GIT_USER}:${GIT_TOKEN}@github.com/open-cluster-management/pipeline.git"
git clone https://github.com/open-cluster-management/deploy.git

export LIFEGUARD_PATH=$(pwd)/lifeguard
export RHACM_PIPELINE_PATH=$(pwd)/pipeline
export RHACM_DEPLOY_PATH=$(pwd)/deploy

# Check for Quay token for Deploy
echo "$(date) ##### Checking for Quay token"
if [[ -z "${QUAY_TOKEN_DECODED}" ]]; then
  echo "ERROR: QUAY_TOKEN not provided"
  exit 1
else
  # Re-encode Quay token for Deploy
  export QUAY_TOKEN=$(printf "${QUAY_TOKEN_DECODED}" | base64)
  echo "QUAY_TOKEN: ${QUAY_TOKEN}"
fi

# ClusterClaim exports
export CLUSTERPOOL_TARGET_NAMESPACE=${CLUSTERPOOL_TARGET_NAMESPACE:-"ERROR: Please specify CLUSTERPOOL_TARGET_NAMESPACE in environment variables"}
export CLUSTERPOOL_NAME=${CLUSTERPOOL_NAME:-"ERROR: Please specify CLUSTERPOOL_NAME in environment variables"}
export CLUSTERPOOL_RESIZE=${CLUSTERPOOL_RESIZE:-"true"}
export CLUSTERPOOL_MAX_CLUSTERS=${CLUSTERPOOL_MAX_CLUSTERS:-"5"}
export CLUSTERCLAIM_NAME="rhacmstackem-${CLUSTERPOOL_NAME}"
export CLUSTERCLAIM_GROUP_NAME=${CLUSTERCLAIM_GROUP_NAME:-"ERROR: Please specify CLUSTERCLAIM_GROUP_NAME in environment variables"}
export CLUSTERCLAIM_LIFETIME=${CLUSTERCLAIM_LIFETIME:-"10h"}
export AUTH_REDIRECT_PATHS=${AUTH_REDIRECT_PATHS:-()}

# Run StartRHACM to claim cluster and deploy RHACM
echo "$(date) ##### Running StartRHACM"
export DISABLE_CLUSTER_CHECK="true"
./startrhacm/startrhacm.sh

# Set up RBAC users
if [[ "${RBAC_SETUP:-"true"}" == "true" ]]; then
  echo "$(date) ##### Setting up RBAC users"
  export RBAC_PASS=$(date | md5sum)
  export KUBECONFIG=${LIFEGUARD_PATH}/clusterclaims/*/kubeconfig
  touch ./rbac/htpasswd
  for access in cluster ns; do
    for role in cluster-admin admin edit view group; do
      htpasswd -b ./rbac/htpasswd e2e-${role}-${access} ${RBAC_PASS}
    done
  done
  oc create secret generic e2e-users --from-file=htpasswd=./rbac/htpasswd -n openshift-config || true
  rm ./rbac/htpasswd
  if [[ -z "$(oc -n openshift-config get oauth cluster -o jsonpath='{.spec.identityProviders}')" ]]; then
    oc patch -n openshift-config oauth cluster --type json --patch '[{"op":"add","path":"/spec/identityProviders","value":[]}]'
  fi
  if [ ! $(oc -n openshift-config get oauth cluster -o jsonpath='{.spec.identityProviders[*].name}' | grep -o 'grc-e2e-htpasswd') ]; then
    oc patch -n openshift-config oauth cluster --type json --patch "$(cat ./rbac/e2e-rbac-auth.json)"
  fi
  oc apply --validate=false -k ./rbac
fi

# Send cluster information to Slack
if [[ -n "${SLACK_URL}" ]]; then
  echo "$(date) ##### Sending credentials to Slack"
  export KUBECONFIG=${LIFEGUARD_PATH}/clusterclaims/*/kubeconfig
  SNAPSHOT=$(oc get pod -l app=acm-custom-registry -o jsonpath='{.items[].spec.containers[0].image}' | grep -o "[0-9]\+\..*SNAPSHOT.*$")
  RHACM_URL=$(oc get routes multicloud-console -o jsonpath='{.status.ingress[0].host}')
  jq -r 'to_entries[] | "*\(.key)*: \(.value)"' ${LIFEGUARD_PATH}/clusterclaims/*/*.creds.json \
  | awk 'BEGIN{printf "{\"text\":\"*Snapshot*:'${SNAPSHOT}'\\n*RBAC Password*:'${RBAC_PASS}'\\n"};{printf "%s\\n", $0};END{printf "*RHACM URL*:'${RHACM_URL}'\\n\"}"}' \
  | curl -X POST -H 'Content-type: application/json' --data @- ${SLACK_URL}
fi
