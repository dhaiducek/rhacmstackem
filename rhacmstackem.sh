#! /bin/bash

# Clone requisite repos and store paths
echo "$(date) ##### Cloning Lifeguard, Deploy, Pipeline, and StartRHACM repos"
git clone https://github.com/dhaiducek/startrhacm.git
git clone https://github.com/open-cluster-management/lifeguard.git
git clone https://${GIT_USER}:${GIT_TOKEN}@github.com/open-cluster-management/pipeline.git
git clone https://github.com/open-cluster-management/deploy.git

export LIFEGUARD_PATH=$(pwd)/lifeguard
export RHACM_PIPELINE_PATH=$(pwd)/pipeline
export RHACM_DEPLOY_PATH=$(pwd)/deploy

# Login to ClusterPool cluster
echo "$(date) ##### Logging in to ClusterPool cluster"
oc login --token="${CLUSTERPOOL_HOST_TOKEN}" --server="${CLUSTERPOOL_HOST_API}" --insecure-skip-tls-verify=true

# Setup Quay token for Deploy
echo "$(date) ##### Setting up deploy Quay token"
cat >${RHACM_DEPLOY_PATH}/prereqs/pull-secret.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: multiclusterhub-operator-pull-secret
data:
  .dockerconfigjson: ${QUAY_PULL_SECRET}
type: kubernetes.io/dockerconfigjson
EOF

# ClusterClaim exports
export CLUSTERPOOL_TARGET_NAMESPACE=${CLUSTERPOOL_TARGET_NAMESPACE:-"ERROR: Please specify CLUSTERPOOL_TARGET_NAMESPACE in environment variables"}
export CLUSTERPOOL_NAME=${CLUSTERPOOL_NAME:-"ERROR: Please specify CLUSTERPOOL_NAME in environment variables"}
export CLUSTERPOOL_RESIZE=${CLUSTERPOOL_RESIZE:-"true"}
export CLUSTERPOOL_MAX_CLUSTERS=${CLUSTERPOOL_MAX_CLUSTERS:-"5"}
export CLUSTERCLAIM_NAME="autoclaim-${CLUSTERPOOL_NAME}"
export CLUSTERCLAIM_GROUP_NAME=${CLUSTERCLAIM_GROUP_NAME:-""}
export CLUSTERCLAIM_LIFETIME=${CLUSTERCLAIM_LIFETIME:-"10h"}
export AUTH_REDIRECT_PATHS=${AUTH_REDIRECT_PATHS:-()}

# Run StartRHACM to claim cluster and deploy RHACM
echo "$(date) ##### Running StartRHACM"
./startrhacm/startrhacm.sh
echo "$(date) ##### Sending credentials to Slack"
export KUBECONFIG=${LIFEGUARD_PATH}/clusterclaims/*/kubeconfig
SNAPSHOT=$(oc get pod -l app=acm-custom-registry -o jsonpath='{.items[].spec.containers[0].image}' | grep -o "[0-9]\+\..*SNAPSHOT.*$")
RHACM_URL=$(oc get routes multicloud-console -o jsonpath='{.status.ingress[0].host}')
jq -r 'to_entries[] | "*\(.key)*: \(.value)"' ${LIFEGUARD_PATH}/clusterclaims/*/*.creds.json \
| awk 'BEGIN{printf "{\"text\":\"*Snapshot*:'${SNAPSHOT}'\\n"};{printf "%s\\n", $0};END{printf "*RHACM URL*:'${RHACM_URL}'\\n\"}"}' \
| curl -X POST -H 'Content-type: application/json' --data @- ${SLACK_URL}
