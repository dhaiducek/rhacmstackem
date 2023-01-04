# RHACMStackEm

Image to provision an OCP cluster from a ClusterPool with the latest RHACM deployed using [StartRHACM](https://github.com/dhaiducek/startrhacm)

Image URL: `quay.io/dhaiduce/rhacmstackem`

## CronJob Deployment

1. Pre-deployment setup
  - Set up a ServiceAccount in your ClusterPool namespace (see the [Lifeguard Service Account docs](https://github.com/stolostron/lifeguard/blob/main/docs/creating_and_using_service_accounts_for_CI.md#creating-a-service-account-and-configuring-roles))
  - Use Quay to create a secret on the ClusterPool cluster with access to https://quay.io/organization/stolostron
    - Navigate to your Account Settings: `https://quay.io/user/<username>?tab=settings`
    - Click "Generate Encrypted Password"
    - With "Kubernetes Secret" selected on the left, follow Step 1 and Step 2 to create the secret on the cluster (you can modify `metadata.name` as you wish)
  - Use GitHub to set up a [Personal Access Token](https://github.com/settings/tokens) with access to the private [Pipeline](https://github.com/stolostron/pipeline/) repo
  - (Optional) Create a new private Slack channel in your workspace. In the channel, click the `i` in the upper right to view the channel's details. Click the "More" button and select "Add apps". Add "ClusterPool Bot". The bot can use either of two methods:
    - Incoming Webhook
      - This URL is the `SLACK_URL` to post to your channel and does not require a token or channel ID, but will not post a scheduled message when the claim will expire
    - Slack API
      - Using the Oauth token (`SLACK_TOKEN`) and Channel ID (`SLACK_CHANNEL_ID`) to post to your desired channel, this will use the Slack API to post both the credentials and schedule a message to post 20 minutes before the claim is going to expire (Note: You can find the Channel ID by right clicking on the channel, select "copy link", and use the last portion of the Channel link for the ID)
2. Export environment variables:
  ```bash
  # REQUIRED EXPORTS
  export SERVICE_ACCOUNT_NAME="" # Service Account with permissions to perform actions on the cluster
  export CLUSTERPOOL_TARGET_NAMESPACE="" # Namespace on ClusterPool cluster
  export CLUSTERPOOL_NAME="" # Name of ClusterPool to use (you'll probably want to use a name without a version for maintainability)
  export CLUSTERCLAIM_GROUP_NAME="" # Name of RBAC group to give additional permissions
  export QUAY_SECRET_NAME="" # Name of the Quay secret on the ClusterPool cluster to deploy RHACM from step 1
  export GIT_USER="" # Git username with permissions for Pipeline
  export GIT_TOKEN="" # Git token with permissions for Pipeline

  # OPTIONAL EXPORTS
  export SLACK_URL="" # Slack URL to post cluster information to a channel using the Incoming Webhook (no token or channel ID needed)
  export SLACK_TOKEN="" # Slack token to post cluster information and a scheduled expiration message to a channel using the Slack API (requires channel ID)
  export SLACK_CHANNEL_ID="" # Slack Channel ID to post cluster information and a scheduled expiration message to a channel using the Slack API (requires token)
  export CLUSTERPOOL_MIN_SIZE="" # Minimum size of ClusterPool to scale to before creating claim (default: "1")
  export CLUSTERPOOL_POST_DEPLOY_SIZE="" # Set the size of the ClusterPool post-deployment
  export CLUSTERCLAIM_NAME="" # Name to use for ClusterClaim (default: "rhacmstackem-${CLUSTERPOOL_NAME}")
  export CLUSTERCLAIM_LIFETIME="" # Lifetime of claimed cluster (default: "12h")
  export RBAC_SETUP="" # Whether to set up RBAC users on the cluster (default: "true")
  export RBAC_IDP_NAME="" # Custom name for identity provider (default: "e2e-htpasswd")
  export INSTALL_ICSP="" # Whether to install ImageContentSourcePolicy to access downstream repos (default: "false")
  export CLAIM_REUSE="" # Controls initial cleanup behavior (default: "delete"): "delete" - Delete existing claims prior to a deploy; "update" - Reuse existing claim; Any other non-empty value will exit the script and not attempt to deploy
  export CONSOLE_BANNER_TEXT="" # Text to put in a banner at the top of the OpenShift console (Use "default" to advertise for RHACMStackEm, leave empty to skip the banner)
  export CONSOLE_BANNER_COLOR="#fff" # Color of the text in the banner
  export CONSOLE_BANNER_BGCOLOR="#316DC1" # Color of the banner
  ```
  **NOTE**: Additional exports to further configure the deployment can be found in the [`StartRHACM` configuration](https://github.com/dhaiducek/startrhacm/blob/main/utils/config.sh.template)
3. Change to the `deployment/` directory and run the `rhacmstackem_deployment.yaml.sh` script to create the necessary YAML files:
  ```bash
  cd deployment/
  ./rhacmstackem_deployment.yaml.sh
  ```
4. Make sure you're pointing to your ClusterPool cluster and run `oc apply -f .` to deploy the files.

## About RBAC users

By default, RBAC users are instantiated on the cluster with a random password posted to Slack (This can be disabled by adding `RBAC_SETUP="false"` to the deployment). With this, the namespaces `e2e-rbac-test-1` and `e2e-rbac-test-2` are also created for the namespaced users to access.

| USER | ACCESS | ROLE |
| --- | --- | --- |
| e2e-cluster-admin-cluster | Cluster | cluster-admin |
| e2e-admin-cluster | Cluster | admin |
| e2e-edit-cluster | Cluster | edit |
| e2e-view-cluster | Cluster | view |
| e2e-group-cluster | Cluster | view |
| e2e-cluster-admin-ns | Namespace | cluster-admin for `e2e-rbac-test-1` |
| e2e-admin-ns | Namespace | admin for `e2e-rbac-test-1`</br>view for `e2e-rbac-test-2` |
| e2e-edit-ns | Namespace | edit for `e2e-rbac-test-1` |
| e2e-view-ns | Namespace | view for `e2e-rbac-test-1` |
| e2e-group-ns | Namespace | view for `e2e-rbac-test-1` |
