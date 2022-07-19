# cd ${WORKDIR}/anthos-multicloud-workshop/platform_admins/tests/ops
# source cgw-enable.sh ${GOOGLE_PROJECT} ${GCLOUD_USER} cicd-sa@${GOOGLE_PROJECT}.iam.gserviceaccount.com

source ${WORKDIR}/anthos-multicloud-workshop/user_setup.sh

# [PROJECT_ID] is the project's unique identifier.
# [USER_ACCOUNT] is an email address, either USER_EMAIL_ADDRESS or GCPSA_EMAIL_ADDRESS
# [USER_EMAIL_ADDRESS] is the Google Cloud account used to interact with clusters via the CGW API.
# [GCPSA_EMAIL_ADDRESS] is the identity used for interacting with the CGW API and cluster.

export PROJECT_ID=${1}

# MEMBER should be of the form `user|serviceAccount:$USER_ACCOUNT`, for example:
# MEMBER=user:foo@example.com
# MEMBER=serviceAccount:test@example-project.iam.gserviceaccount.com

export USER_ACCOUNT=${2}
export SERVICE_ACCOUNT=${3}
export MEMBER=serviceAccount:${SERVICE_ACCOUNT}

# check that repos exist
git ls-remote --exit-code -h git@gitlab.endpoints.${PROJECT_ID}.cloud.goog:platform-admins/shared-cd
if [ ! $? -eq 0 ]; then
  echo "Missing shared-cd repo"
  return
fi

git ls-remote --exit-code -h git@gitlab.endpoints.${PROJECT_ID}.cloud.goog:platform-admins/config
if [ ! $? -eq 0 ]; then
  echo "Missing config repo"
  return
fi

# gcloud projects add-iam-policy-binding ${PROJECT_ID} \
#     --member ${MEMBER} \
#     --role roles/gkehub.gatewayAdmin
# gcloud projects add-iam-policy-binding ${PROJECT_ID} \
#     --member ${MEMBER} \
#     --role roles/gkehub.viewer

envsubst < "cgw-clusterrole-impersonate.yaml_tmpl" > cgw-clusterrole-impersonate.yaml
envsubst < "cgw-clusterrole-userbinding.yaml_tmpl" > cgw-clusterrole-userbinding.yaml

# clone the repo
cd ${WORKDIR}/anthos-multicloud-workshop/platform-admins/tests/ops
# init git
git config --global user.email "${GCLOUD_USER}"
git config --global user.name "Cloud Shell"
if [ ! -d ${HOME}/.ssh ]; then
  mkdir ${HOME}/.ssh
  chmod 700 ${HOME}/.ssh
fi
# pre-grab gitlab public key
ssh-keyscan -t ecdsa-sha2-nistp256 -H gitlab.endpoints.${GOOGLE_PROJECT}.cloud.goog >> ~/.ssh/known_hosts
git clone git@gitlab.endpoints.${GOOGLE_PROJECT}.cloud.goog:platform-admins/config.git

if [ ! -d "config/cluster" ]; then
  echo "config repo is not properly initialized"
  echo "Deleting locally cloned config"
  rm -rf config
  return
fi

cp cgw-clusterrole-impersonate.yaml config/cluster
cp cgw-clusterrole-userbinding.yaml config/cluster

pushd config

git add cluster
git commit -m 'add clusterroles'
git push origin main

popd

# allow user id to create service account tokens
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member=user:${USER_ACCOUNT} \
    --role=roles/iam.serviceAccountTokenCreator

# get the current policy
gcloud iam service-accounts get-iam-policy ${SERVICE_ACCOUNT} \
   --format=json > policy_base.json

# add to the policy - for the cicd-sa serviceaccount to be impersonated by user
cat policy_base.json | jq --arg service_account ${USER_ACCOUNT} '. |= {"bindings": [{"role": "roles/iam.serviceAccountUser","members": ["user:" + $service_account]}]} + .' > policy.json

# apply policy
gcloud iam service-accounts set-iam-policy ${SERVICE_ACCOUNT} \
    policy.json

# user command
# gcloud config set auth/impersonate_service_account cicd-sa@${GOOGLE_PROJECT}.iam.gserviceaccount.com
# gcloud beta container hub memberships get-credentials eks-prod-us-west2ab-1
# unset impersonation
# gcloud config unset auth/impersonate_service_account