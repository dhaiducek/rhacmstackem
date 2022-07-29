FROM registry.access.redhat.com/ubi8/ubi-minimal:latest

# Add RHACMStackEm script and YAML resources
ADD rhacmstackem.sh .
ADD resources/ resources/

# Install microdnf packages: tar/gzip, curl, git, jq, htpasswd
RUN microdnf update -y && microdnf install -y tar gzip curl git jq httpd-tools
# Install yq
RUN curl -sLO https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64.tar.gz -o yq_linux_amd64.tar.gz && \
    tar xzf yq_linux_amd64.tar.gz && chmod +x yq_linux_amd64 && mv yq_linux_amd64 /usr/local/bin/yq && rm yq_linux_amd64.tar.gz
# Install oc/kubectl
RUN curl -sLO https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/openshift-client-linux.tar.gz -o openshift-client-linux.tar.gz && \
    tar xzf openshift-client-linux.tar.gz && chmod +x oc && mv oc /usr/local/bin/oc && \
    chmod +x kubectl && mv kubectl /usr/local/bin/kubectl && rm openshift-client-linux.tar.gz
CMD ["/bin/bash", "-c", "./rhacmstackem.sh"]
