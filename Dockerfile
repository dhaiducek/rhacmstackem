FROM alpine:latest

ADD rhacmstackem.sh .
ADD rbac/ rbac/

# Install APK packages: bash, git, curl, jq, htpasswd
RUN apk update && apk add bash git curl jq apache2-utils
# Install kubectl
RUN curl -sLO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" -o kubectl && \
    mv kubectl /usr/bin/kubectl && chmod +x /usr/bin/kubectl
# Install oc
RUN curl -sLO https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/openshift-client-linux.tar.gz -o openshift-client-linux.tar.gz && \
    tar xzf openshift-client-linux.tar.gz && mv oc /usr/bin/oc && chmod +x /usr/bin/oc && rm openshift-client-linux.tar.gz
# Use musl instead of glibc for oc and run with bash shell
RUN echo 'alias oc="/lib/ld-musl-x86_64.so.1 --library-path /lib /usr/bin/oc $@"' >> /root/.bashrc
CMD [ "bash" ]
