FROM alpine

ADD rhacmstackem.sh .
ADD rbac/ .

# Install APK packages: bash, git, curl, jq, htpasswd
RUN apk add bash git curl jq apache2-utils
# Install oc
RUN curl -s https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/openshift-client-linux.tar.gz -o openshift-client-linux.tar.gz; \
    tar xf openshift-client-linux.tar.gz; mv oc /usr/bin; mv kubectl /usr/bin
