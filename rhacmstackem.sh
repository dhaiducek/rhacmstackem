#! /bin/bash

set -e

ERROR_CODE=0

# Clone requisite repos and store paths
echo "$(date) ##### Cloning Lifeguard, Deploy, Pipeline, and StartRHACM repos"
git clone https://github.com/dhaiducek/startrhacm.git
git clone https://github.com/stolostron/lifeguard.git
git clone "https://${GIT_USER}:${GIT_TOKEN}@github.com/stolostron/pipeline.git"
git clone https://github.com/stolostron/deploy.git

export LIFEGUARD_PATH=/lifeguard
export RHACM_PIPELINE_PATH=/pipeline
export RHACM_DEPLOY_PATH=/deploy

# Check for Quay token for Deploy
echo "$(date) ##### Checking for Quay token"
if [[ -z "${QUAY_TOKEN}" ]]; then
  echo "ERROR: QUAY_TOKEN not provided"
  exit 1
else
  # Re-encode Quay token for Deploy
  export QUAY_TOKEN=$(echo -n "${QUAY_TOKEN}" | base64 -w 0)
fi

# ClusterClaim exports
export CLUSTERPOOL_TARGET_NAMESPACE=${CLUSTERPOOL_TARGET_NAMESPACE:-"ERROR: Please specify CLUSTERPOOL_TARGET_NAMESPACE in environment variables"}
export CLUSTERPOOL_NAME=${CLUSTERPOOL_NAME:-"ERROR: Please specify CLUSTERPOOL_NAME in environment variables"}
export CLUSTERPOOL_MIN_SIZE=${CLUSTERPOOL_MIN_SIZE:-"1"}
export CLUSTERCLAIM_NAME=${CLUSTERCLAIM_NAME:-"rhacmstackem-${CLUSTERPOOL_NAME}"}
export CLUSTERCLAIM_GROUP_NAME=${CLUSTERCLAIM_GROUP_NAME:-"ERROR: Please specify CLUSTERCLAIM_GROUP_NAME in environment variables"}
export CLUSTERCLAIM_LIFETIME=${CLUSTERCLAIM_LIFETIME:-"12h"}
export AUTH_REDIRECT_PATHS="${AUTH_REDIRECT_PATHS:-""}"
export INSTALL_ICSP=${INSTALL_ICSP:-"false"}

# Check for existing claims of the same name
echo "$(date) ##### Checking for existing claims named ${CLUSTERCLAIM_NAME}"
if (oc get -n ${CLUSTERPOOL_TARGET_NAMESPACE} clusterclaim.hive ${CLUSTERCLAIM_NAME} &>/dev/null); then
  echo "* Existing claim found"
  case "${CLAIM_REUSE:-"delete"}" in
    delete)
      CLUSTERDEPLOYMENT=$(oc get -n ${CLUSTERPOOL_TARGET_NAMESPACE} clusterclaim.hive ${CLUSTERCLAIM_NAME}  -o jsonpath='{.spec.namespace}')
      oc delete -n ${CLUSTERPOOL_TARGET_NAMESPACE} clusterclaim.hive ${CLUSTERCLAIM_NAME}
      echo "* Waiting up to 5 minutes for Hive to process ClusterDeployment for deletion"
      READY="false"
      ATTEMPTS=0
      MAX_ATTEMPTS=10
      INTERVAL=30
      while (oc get -n ${CLUSTERDEPLOYMENT} clusterdeployment.hive ${CLUSTERDEPLOYMENT}) && (( ATTEMPTS != MAX_ATTEMPTS )); do
        echo "* Waiting another ${INTERVAL}s for cluster deployment cleanup (Retry $((++ATTEMPTS))/${MAX_ATTEMPTS})"
        sleep ${INTERVAL}
      done
      if (oc get -n ${CLUSTERDEPLOYMENT} clusterdeployment.hive ${CLUSTERDEPLOYMENT} &>/dev/null); then
        echo "* Manually deleting ClusterDeployment ${CLUSTERDEPLOYMENT}"
        oc delete -n ${CLUSTERDEPLOYMENT} clusterdeployment.hive ${CLUSTERDEPLOYMENT}
      fi
      ;;
    update)
      echo "* Reusing existing claim"
      ;;
    *)
      echo "^^^^^ Unrecognized value found in CLAIM_REUSE: '${CLAIM_REUSE}'"
      exit 1
      ;;
  esac
else
  echo "* No existing claim found"
fi

# Run StartRHACM to claim cluster and deploy RHACM
echo "$(date) ##### Running StartRHACM"
export DISABLE_CLUSTER_CHECK="true"
./startrhacm/startrhacm.sh || ERROR_CODE=1

# Point to claimed cluster and set up RBAC users
if [[ "${RBAC_SETUP:-"true"}" == "true" ]]; then
  RBAC_IDP_NAME=${RBAC_IDP_NAME:-"e2e-htpasswd"}
  echo "$(date) ##### Setting up RBAC users"
  export RBAC_PASS=$(head /dev/urandom | tr -dc 'A-Za-z0-9' | head -c $((32 + RANDOM % 8)))
  export KUBECONFIG=${LIFEGUARD_PATH}/clusterclaims/${CLUSTERCLAIM_NAME}/kubeconfig
  RBAC_DIR="./resources/rbac"
  HTPASSWD_FILE="${RBAC_DIR}/htpasswd"
  touch "${HTPASSWD_FILE}"
  for access in cluster ns; do
    for role in cluster-admin admin edit view group; do
      htpasswd -b "${HTPASSWD_FILE}" e2e-${role}-${access} ${RBAC_PASS}
    done
  done
  oc create secret generic e2e-users --from-file=htpasswd="${HTPASSWD_FILE}" -n openshift-config || true
  rm "${HTPASSWD_FILE}"
  if [[ -z "$(oc -n openshift-config get oauth cluster -o jsonpath='{.spec.identityProviders}')" ]]; then
    oc patch -n openshift-config oauth cluster --type json --patch '[{"op":"add","path":"/spec/identityProviders","value":[]}]'
  fi
  if [ ! $(oc -n openshift-config get oauth cluster -o jsonpath='{.spec.identityProviders[*].name}' | grep -o "${RBAC_IDP_NAME}") ]; then
    oc patch -n openshift-config oauth cluster --type json --patch '[{"op":"add","path":"/spec/identityProviders/-","value":{"name":"'${RBAC_IDP_NAME}'","mappingMethod":"claim","type":"HTPasswd","htpasswd":{"fileData":{"name":"e2e-users"}}}}]'
  fi
  oc apply --validate=false -k "${RBAC_DIR}"
  export RBAC_INFO="*RBAC Users*: e2e-<cluster-admin/admin/edit/view>-<cluster/ns>\\\n*RBAC Password*: ${RBAC_PASS}\\\n"
fi

if [[ -n "${CONSOLE_BANNER_TEXT}" ]]; then
  export KUBECONFIG=${LIFEGUARD_PATH}/clusterclaims/${CLUSTERCLAIM_NAME}/kubeconfig
  oc apply -f ./resources/consolenotification.yaml
  if [[ "${CONSOLE_BANNER_TEXT}" != "default" ]]; then
    oc patch consolenotification.console.openshift.io/rhacmstackem --type json --patch '[{"op":"remove", "path":"/spec/link"},{"op":"replace", "path":"/spec/text", "value":"'${CONSOLE_BANNER_TEXT}'"}]'
  fi
  if [[ -n "${CONSOLE_BANNER_COLOR}" ]]; then
    oc patch consolenotification.console.openshift.io/rhacmstackem --type json --patch '[{"op":"replace", "path":"/spec/color", "value":"'${CONSOLE_BANNER_COLOR}'"}]'
  fi
  if [[ -n "${CONSOLE_BANNER_BGCOLOR}" ]]; then
    oc patch consolenotification.console.openshift.io/rhacmstackem --type json --patch '[{"op":"replace", "path":"/spec/backgroundColor", "value":"'${CONSOLE_BANNER_BGCOLOR}'"}]'
  fi
fi

# Send cluster information to Slack
if [[ -n "${SLACK_URL}" ]] || ( [[ -n "${SLACK_TOKEN}" ]] && [[ -n "${SLACK_CHANNEL_ID}" ]] ); then
  echo "$(date) ##### Posting information to Slack"
  # Point to claimed cluster and retrieve cluster information
  export KUBECONFIG=${LIFEGUARD_PATH}/clusterclaims/${CLUSTERCLAIM_NAME}/kubeconfig
  # Set greeting based on error code from StartRHACM
  if [[ -z "ERROR_CODE" ]]; then
    GREETING=":red_circle: RHACM deployment failed. The \`${CLUSTERCLAIM_NAME}\` cluster for $(date "+%A, %B %d, %Y") may need to be debugged before use."
  else
    GREETING=":mostly_sunny: Good Morning! Here's your \`${CLUSTERCLAIM_NAME}\` cluster for $(date "+%A, %B %d, %Y")"
  fi
  SNAPSHOT=$(oc get catalogsource acm-custom-registry -n openshift-marketplace -o jsonpath='{.spec.image}' | grep -o "[0-9]\+\..*SNAPSHOT.*$")
  RHACM_URL=$(oc get routes console -n openshift-console -o jsonpath='{.status.ingress[0].host}' || echo "(No RHACM route found.)")
  if [[ "${RHACM_URL}" != "(No RHACM route found.)" ]]; then
    RHACM_URL="https://${RHACM_URL}/multicloud/home/welcome"
  fi
  # Get expiration time from the ClusterClaim
  unset KUBECONFIG
  CLAIM_CREATION=$(oc get clusterclaim.hive ${CLUSTERCLAIM_NAME} -n ${CLUSTERPOOL_TARGET_NAMESPACE} -o jsonpath={.metadata.creationTimestamp})
  LIFETIME_DIFF="+$(oc get clusterclaim.hive ${CLUSTERCLAIM_NAME} -n ${CLUSTERPOOL_TARGET_NAMESPACE} -o jsonpath={.spec.lifetime} | sed 's/h/hour/' | sed 's/m/min/' | sed 's/s/sec/')"
  CLAIM_EXPIRATION=$(date -d "${CLAIM_CREATION}${LIFETIME_DIFF}-20min" +%s)
  LIFETIME="${CLUSTERCLAIM_LIFETIME} from $(date -d "${CLAIM_CREATION}" "+%I:%M %p %Z")"
  CREDENTIAL_DATA=$(jq -r 'to_entries[] | "*\(.key)*: \(.value)"' ${LIFEGUARD_PATH}/clusterclaims/*/*.creds.json \
    | awk -v GREETING="${GREETING}" -v LIFETIME="${LIFETIME}" -v SNAPSHOT="${SNAPSHOT}" -v RBAC_INFO="${RBAC_INFO}" -v RHACM_URL="${RHACM_URL}" \
    'BEGIN{printf "{\"text\":\""GREETING"\\n*Lifetime*: "LIFETIME"\\n*Snapshot*: "SNAPSHOT"\\n"RBAC_INFO};{printf "%s\\n", $0};END{printf "*RHACM URL*: "RHACM_URL"\\n\"}"}')
  # Prefer using token and Slack API for both credentials and scheduled expiration post (Fall back to Incoming Webhook to post credentials to Slack (no expiration post))
  if [[ -n "${SLACK_TOKEN}" ]] && [[ -n "${SLACK_CHANNEL_ID}" ]]; then
    # Post credentials to Slack using the Slack API
    echo "* Sending credentials to Slack via token"
    curl -X POST -H 'Content-type: application/json' -H "Authorization: Bearer ${SLACK_TOKEN}" --data "${CREDENTIAL_DATA}" ${SLACK_URL}
    # Schedule a Slack message 20 minutes before the cluster expiration time
    EXPIRATION_DATA="{\"channel\": \"${SLACK_CHANNEL_ID}\",\"text\": \"*EXPIRATION ALERT*\\nToday's cluster will expire in about 20 minutes. Please update the lifetime of the \`${CLUSTERCLAIM_NAME}\` ClusterClaim if you need it longer.\\n Have a great day! :slightly_smiling_face:\", \"post_at\": ${CLAIM_EXPIRATION}}"
    # Schedule a Slack message 20 minutes before the cluster expiration time
    echo "* Scheduling expiration post to Slack via token"
    curl -X POST -H 'Content-type: application/json' -H "Authorization: Bearer ${SLACK_TOKEN}" --data "${EXPIRATION_DATA}" https://slack.com/api/chat.scheduleMessage | jq '{OK: .ok, POST_AT: .post_at, ERRORS: .error,  MESSAGES: .response_metadata.messages}'
  elif [[ -n "${SLACK_URL}" ]]; then
    # Post credentials to Slack using the Incoming Webhook (no expiration post)
    echo "* Sending credentials to Slack via incoming webhook"
    curl -X POST -H 'Content-type: application/json' --data "${CREDENTIAL_DATA}" ${SLACK_URL}
  fi
fi

exit ${ERROR_CODE}
