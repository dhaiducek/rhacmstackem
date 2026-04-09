#!/bin/bash

set -euo pipefail

: "${CLUSTERCLAIM_NAME?:CLUSTERCLAIM_NAME must be set}"
: "${CLUSTERPOOL_TARGET_NAMESPACE?:CLUSTERPOOL_TARGET_NAMESPACE must be set}"
: "${CLUSTERCLAIM_LIFETIME?:CLUSTERCLAIM_LIFETIME must be set}"
: "${CLUSTER_KUBECONFIG_FILE?:CLUSTER_KUBECONFIG_FILE must be set}"

# Fetch ClusterDeployment and Hosted Zone name from ClusterPool host
oc project

clusterdeployment=$(oc get clusterclaims.hive.openshift.io "${CLUSTERCLAIM_NAME}" -n "${CLUSTERPOOL_TARGET_NAMESPACE}" -o jsonpath='{.spec.namespace}')
hosted_zone_name=$(oc get -n "${clusterdeployment}" clusterdeployments.hive.openshift.io "${clusterdeployment}" -o jsonpath='{.spec.baseDomain}')
certificate_name="apps-domain-tls-cert-${clusterdeployment}"
certificate_duration="${CLUSTERCLAIM_LIFETIME:-168h0m0s}" 

echo "* ClusterDeployment name: ${clusterdeployment}"
echo "* Hosted zone name: ${hosted_zone_name}"

if [[ -z "${clusterdeployment}" || -z "${hosted_zone_name}" ]]; then
  echo "ERROR: Could not determine clusterdeployment namespace or baseDomain from ClusterClaim ${CLUSTERCLAIM_NAME}"
  exit 1
fi

echo "* Cleaning up existing certificates..."
oc delete certificates.cert-manager.io -n "${CLUSTERPOOL_TARGET_NAMESPACE}" -l "cluster=${CLUSTERCLAIM_NAME}"

cat <<EOF | oc apply -f -
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: ${certificate_name}
  namespace: ${CLUSTERPOOL_TARGET_NAMESPACE}
  labels:
    use-dns01-solver: "true"
    cluster: ${CLUSTERCLAIM_NAME}
spec:
  secretName: ${certificate_name}-secret
  subject:
    organizations:
    - Open Cluster Management
  usages:
    - server auth
    - client auth
  dnsNames:
    - apps.${clusterdeployment}.${hosted_zone_name}
    - "*.apps.${clusterdeployment}.${hosted_zone_name}"
  duration: ${certificate_duration}
  privateKey:
    algorithm: "RSA"
    size: 2048
  issuerRef:
    name: public-cluster-issuer
    kind: Issuer
EOF

echo "* Waiting for certificate to be ready on collective..."
oc wait --for=condition=Ready "certificates.cert-manager.io/${certificate_name}" -n "${CLUSTERPOOL_TARGET_NAMESPACE}" --timeout=900s

# Get the certificate secret name from the certificate status
echo "* Getting certificate secret name from certificate status..."
cert_secret_name=$(oc get certificates.cert-manager.io "${certificate_name}" -n "${CLUSTERPOOL_TARGET_NAMESPACE}" -o jsonpath='{.spec.secretName}')

# Extract the certificate secret from collective
echo "* Extracting certificate secret from collective..."
cert_secret_yaml=$(oc get secret "${cert_secret_name}" -n "${CLUSTERPOOL_TARGET_NAMESPACE}" -o yaml | 
  yq '.metadata |= del(.creationTimestamp, .namespace, .ownerReferences, .resourceVersion, .uid)')

# Switch to claimed cluster
echo "* Switching to claimed cluster to apply certificate..."
export KUBECONFIG="${CLUSTER_KUBECONFIG_FILE}"
oc project

echo "* Copying certificate secret to openshift-ingress namespace on claimed cluster..."
echo "${cert_secret_yaml}" | oc apply -n openshift-ingress -f -

echo "* Patching the certificate into the IngressController on claimed cluster..."
oc patch ingresscontrollers.operator.openshift.io default \
  --type=merge -p \
  "{\"spec\":{\"defaultCertificate\": {\"name\": \"${cert_secret_name}\"}}}" \
  -n openshift-ingress-operator

echo "* Successfully created certificate on collective and applied to claimed cluster."
