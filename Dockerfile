FROM registry.access.redhat.com/ubi8/ubi-minimal:latest

# Add RHACMStackEm script and RBAC resources
ADD rhacmstackem.sh .
ADD rbac/ rbac/

# Install microdnf packages: tar/gzip, curl, git, jq, htpasswd
RUN microdnf update -y && microdnf install -y tar gzip curl git jq wget httpd-tools
# Install oc/kubectl
RUN curl -sLO https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/openshift-client-linux.tar.gz -o openshift-client-linux.tar.gz && \
    tar xzf openshift-client-linux.tar.gz && chmod +x oc && mv oc /usr/local/bin/oc && \
    chmod +x kubectl && mv kubectl /usr/local/bin/kubectl && rm openshift-client-linux.tar.gz
CMD ["/bin/bash", "-c", "./rhacmstackem.sh"]
