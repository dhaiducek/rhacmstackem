#! /bin/bash

set -e

# Creates a RHACMStackEm CronJob to deploy a 12 hour cluster at 6:15 AM EST (11 AM UTC) Monday - Friday

echo "Using exports (if there's no output, please set these variables and try again):"
echo "* SERVICE_ACCOUNT_NAME: ${SERVICE_ACCOUNT_NAME}"
echo "* CLUSTERPOOL_TARGET_NAMESPACE: ${CLUSTERPOOL_TARGET_NAMESPACE}"
echo "* CLUSTERPOOL_NAME: ${CLUSTERPOOL_NAME}"
echo "* CLUSTERCLAIM_GROUP_NAME: ${CLUSTERCLAIM_GROUP_NAME}"
echo "* QUAY_SECRET_NAME: ${QUAY_SECRET_NAME}"
echo "* GIT_USER: $(if [[ -n "${GIT_USER}" ]]; then echo "REDACTED"; fi)"
echo "* GIT_TOKEN: $(if [[ -n "${GIT_TOKEN}" ]]; then echo "REDACTED"; fi)"
echo "* SLACK_URL (optional): $(if [[ -n "${SLACK_URL}" ]]; then echo "REDACTED"; fi)"
echo "* SLACK_TOKEN (optional): $(if [[ -n "${SLACK_TOKEN}" ]]; then echo "REDACTED"; fi)"
echo "* SLACK_CHANNEL_ID (optional): $(if [[ -n "${SLACK_CHANNEL_ID}" ]]; then echo "REDACTED"; fi)"

cat >rhacmstackem-github-secret.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: rhacmstackem-github-secret
data:
  user: $(printf "${GIT_USER}" | base64)
  token: $(printf "${GIT_TOKEN}" | base64)
EOF

if [[ -n "${SLACK_URL}" ]] || ( [[ -n "${SLACK_TOKEN}" ]] && [[ -n "${SLACK_CHANNEL_ID}" ]] ); then
cat >rhacmstackem-slack-secret.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: rhacmstackem-slack-secret
data:
$(test -n "${SLACK_URL}" && printf "  url: $(printf "${SLACK_URL}" | base64)\n")
$(test -n "${SLACK_TOKEN}" && printf "  token: $(printf "${SLACK_TOKEN}" | base64)\n")
$(test -n "${SLACK_CHANNEL_ID}" && printf "  channel_id: $(printf "${SLACK_CHANNEL_ID}" | base64)\n")
EOF
else
  printf "\n* Slack credentials not provided--skipping creation of Slack secret YAML\n"
fi

cat >rhacmstackem-cronjob.yaml <<EOF
apiVersion: batch/v1beta1
kind: CronJob
metadata:
  name: rhacmstackem-cronjob
spec:
#            ┌───────────── minute (0 - 59)
#            │  ┌───────────── hour (0 - 23) (Time in UTC)
#            │  │  ┌───────────── day of the month (1 - 31)
#            │  │  │ ┌───────────── month (1 - 12)
#            │  │  │ │ ┌───────────── day of the week (0 - 6) (Sunday to Saturday)
#            │  │  │ │ │
  schedule: "15 11 * * 1-5"
  jobTemplate:
    spec:
      backoffLimit: 1
      template:
        spec:
          serviceAccountName: ${SERVICE_ACCOUNT_NAME}
          restartPolicy: Never
          containers:
          - name: rhacmstackem
            image: quay.io/dhaiduce/rhacmstackem
            env:
            - name: GIT_USER
              valueFrom:
                secretKeyRef:
                  name: rhacmstackem-github-secret
                  key: user
            - name: GIT_TOKEN
              valueFrom:
                secretKeyRef:
                  name: rhacmstackem-github-secret
                  key: token
            - name: QUAY_TOKEN
              valueFrom:
                secretKeyRef:
                  name: ${QUAY_SECRET_NAME}
                  key: .dockerconfigjson
            - name: SLACK_URL
              valueFrom:
                secretKeyRef:
                  name: rhacmstackem-slack-secret
                  key: url
                  optional: true
            - name: SLACK_TOKEN
              valueFrom:
                secretKeyRef:
                  name: rhacmstackem-slack-secret
                  key: token
                  optional: true
            - name: SLACK_CHANNEL_ID
              valueFrom:
                secretKeyRef:
                  name: rhacmstackem-slack-secret
                  key: channel_id
                  optional: true
            - name: CLUSTERPOOL_TARGET_NAMESPACE
              value: "${CLUSTERPOOL_TARGET_NAMESPACE}"
            - name: CLUSTERPOOL_NAME
              value: "${CLUSTERPOOL_NAME}"
            - name: CLUSTERPOOL_MIN_SIZE
              value: "${CLUSTERPOOL_MIN_SIZE:-1}"
            - name: CLUSTERCLAIM_GROUP_NAME
              value: "${CLUSTERCLAIM_GROUP_NAME}"
            - name: CLUSTERCLAIM_NAME
              value: "${CLUSTERCLAIM_NAME}"
            - name: CLUSTERCLAIM_LIFETIME
              value: "${CLUSTERCLAIM_LIFETIME:-12h}"
            - name: INSTALL_ICSP
              value: "${INSTALL_ICSP:-false}"
            - name: CLAIM_REUSE
              value: "${CLAIM_REUSE}" 
EOF

echo ""
echo "CronJob YAML created! "
echo "* To apply to the ClusterPool cluster:"
echo "oc apply -n ${CLUSTERPOOL_TARGET_NAMESPACE} -f ."
