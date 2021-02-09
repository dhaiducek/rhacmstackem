#! /bin/bash

set -e

# Creates a RHACMStackEm CronJob to deploy a 10 hour cluster at 6:15 AM EST (11 AM UTC) Monday - Friday

echo "Using exports (if there's no output, please set these variables and try again):"
echo "* SERVICE_ACCOUNT_NAME: ${SERVICE_ACCOUNT_NAME}"
echo "* CLUSTERPOOL_TARGET_NAMESPACE: ${CLUSTERPOOL_TARGET_NAMESPACE}"
echo "* CLUSTERPOOL_NAME: ${CLUSTERPOOL_NAME}"
echo "* CLUSTERCLAIM_GROUP_NAME: ${CLUSTERCLAIM_GROUP_NAME}"
echo "* QUAY_SECRET_NAME: ${QUAY_SECRET_NAME}"
echo "* GIT_USER: $(if [[ -n "${GIT_USER}" ]]; then echo "REDACTED"; fi)"
echo "* GIT_TOKEN: $(if [[ -n "${GIT_TOKEN}" ]]; then echo "REDACTED"; fi)"
echo "* SLACK_URL (optional): $(if [[ -n "${SLACK_URL}" ]]; then echo "REDACTED"; fi)"

cat >rhacmstackem-github-secret.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: rhacmstackem-github-secret
data:
  user: $(printf "${GIT_USER}" | base64)
  token: $(printf "${GIT_TOKEN}" | base64)
EOF

cat >rhacmstackem-slack-secret.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: rhacmstackem-slack-secret
data:
  url: $(printf "${SLACK_URL}" | base64)
EOF

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
      template:
        spec:
          serviceAccountName: ${SERVICE_ACCOUNT_NAME}
          restartPolicy: OnFailure
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
            - name: CLUSTERPOOL_TARGET_NAMESPACE
              value: "${CLUSTERPOOL_TARGET_NAMESPACE}"
            - name: CLUSTERPOOL_NAME
              value: "${CLUSTERPOOL_NAME}"
            - name: CLUSTERPOOL_RESIZE
              value: "${CLUSTERPOOL_RESIZE:-"true"}"
            - name: CLUSTERPOOL_MAX_CLUSTERS
              value: "${CLUSTERPOOL_MAX_CLUSTERS:-"5"}"
            - name: CLUSTERCLAIM_GROUP_NAME
              value: "${CLUSTERCLAIM_GROUP_NAME}"
            - name: CLUSTERCLAIM_LIFETIME
              value: "${CLUSTERCLAIM_LIFETIME:-"10h"}"
            - name: AUTH_REDIRECT_PATHS
              value: "${AUTH_REDIRECT_PATHS}"
EOF

echo ""
echo "CronJob YAML created! "
echo "* To apply to the ClusterPool cluster:"
echo "oc apply -n ${CLUSTERPOOL_TARGET_NAMESPACE} -f ."
