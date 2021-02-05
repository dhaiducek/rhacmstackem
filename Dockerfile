FROM alpine

ADD rhacmstackem.sh .

# Install git
RUN apk add git
# Install curl
RUN apk add curl
# Install jq
RUN JQ_LATEST=$(curl -s https://api.github.com/repos/stedolan/jq/releases/latest | \
    grep browser_download_url | grep linux64 | cut -d '"' -f 4 ); \
    curl -s -o jq ${JQ_LATEST}; chmod +x jq; mv jq /usr/bin
# Install oc
RUN curl -s https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/openshift-client-linux.tar.gz -o openshift-client-linux.tar.gz; \
    tar xf openshift-client-linux.tar.gz; mv oc /usr/bin; mv kubectl /usr/bin
