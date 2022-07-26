#!/usr/bin/env bash
# Copyright 2020 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.



export CYAN='\033[1;36m'
export GREEN='\033[1;32m'
export NC='\033[0m' # No Color
function echo_cyan() { echo -e "${CYAN}$@${NC}"; }
function echo_green() { echo -e "${GREEN}$@${NC}"; }

# Set WORKDIR var is not set
export WORKDIR=${WORKDIR:-$HOME/anthos-multicloud}
echo -e "WORKDIR set to $WORKDIR"

source ${WORKDIR}/vars.sh

if [[ ! $USER_SETUP_RUN ]]; then
  gsutil cp -r gs://$GOOGLE_PROJECT/kubeconfig ${WORKDIR}/.
  gsutil cp -r gs://$GOOGLE_PROJECT/gitlab ${WORKDIR}/.
  gsutil cp -r gs://$GOOGLE_PROJECT/ssh-keys ${WORKDIR}/.
  gsutil cp -r gs://$GOOGLE_PROJECT/cloudopsgsa ${WORKDIR}/.
  touch ${WORKDIR}/kubeconfig/workshop-config

  echo -e "export EKS_PROD_1=eks-prod-us-west2ab-1" >> ${WORKDIR}/vars.sh
  echo -e "export EKS_PROD_2=eks-prod-us-west2ab-2" >> ${WORKDIR}/vars.sh
  echo -e "export EKS_STAGE_1=eks-stage-us-east1ab-1" >> ${WORKDIR}/vars.sh
  echo -e "export GKE_PROD_1=gke-prod-us-west2a-1" >> ${WORKDIR}/vars.sh
  echo -e "export GKE_PROD_2=gke-prod-us-west2b-2" >> ${WORKDIR}/vars.sh
  echo -e "export GKE_STAGE_1=gke-stage-us-east4b-1" >> ${WORKDIR}/vars.sh
  echo -e "export GKE_DEV_1=gke-dev-us-west1a-1" >> ${WORKDIR}/vars.sh
  echo -e "export GKE_DEV_2=gke-dev-us-west1b-2" >> ${WORKDIR}/vars.sh
  echo -e "export GKE_GITLAB=gitlab" >> ${WORKDIR}/vars.sh
  echo -e "export KUBECONFIG=${WORKDIR}/kubeconfig/workshop-config" >> ${WORKDIR}/vars.sh
  source ${WORKDIR}/vars.sh

  KUBECONFIG=${WORKDIR}/kubeconfig/kubeconfig_$EKS_PROD_1:${WORKDIR}/kubeconfig/kubeconfig_$EKS_PROD_2:${WORKDIR}/kubeconfig/kubeconfig_$EKS_STAGE_1 kubectl config view --merge --flatten > ${WORKDIR}/kubeconfig/workshop-config

  gcloud container clusters get-credentials $GKE_PROD_1 --zone us-west2-a --project ${GOOGLE_PROJECT}
  gcloud container clusters get-credentials $GKE_PROD_2 --zone us-west2-b --project ${GOOGLE_PROJECT}
  gcloud container clusters get-credentials $GKE_STAGE_1 --zone us-east4-b --project ${GOOGLE_PROJECT}
  gcloud container clusters get-credentials $GKE_DEV_1 --zone us-west1-a --project ${GOOGLE_PROJECT}
  gcloud container clusters get-credentials $GKE_DEV_2 --zone us-west1-b --project ${GOOGLE_PROJECT}
  gcloud container clusters get-credentials gitlab --region us-central1 --project ${GOOGLE_PROJECT}

  kubectl ctx $EKS_PROD_1=eks_$EKS_PROD_1
  kubectl ctx $EKS_PROD_2=eks_$EKS_PROD_2
  kubectl ctx $EKS_STAGE_1=eks_$EKS_STAGE_1
  kubectl ctx $GKE_PROD_1=gke_${GOOGLE_PROJECT}_us-west2-a_$GKE_PROD_1
  kubectl ctx $GKE_PROD_2=gke_${GOOGLE_PROJECT}_us-west2-b_$GKE_PROD_2
  kubectl ctx $GKE_STAGE_1=gke_${GOOGLE_PROJECT}_us-east4-b_$GKE_STAGE_1
  kubectl ctx $GKE_DEV_1=gke_${GOOGLE_PROJECT}_us-west1-a_$GKE_DEV_1
  kubectl ctx $GKE_DEV_2=gke_${GOOGLE_PROJECT}_us-west1-b_$GKE_DEV_2
  kubectl ctx $GKE_GITLAB=gke_${GOOGLE_PROJECT}_us-central1_$GKE_GITLAB
  echo -e "export USER_SETUP_RUN=true" >> ${WORKDIR}/vars.sh

  mkdir -p  ${WORKDIR}/tmp
  cat << EOF > ${WORKDIR}/tmp/config-management-patch.yaml
spec:
  patches:
  - apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: git-importer
      namespace: config-management-system
    spec:
      template:
        spec:
          containers:
          - name: importer
            resources:
              limits:
                memory: "500Mi"
EOF

  kubectl --context ${GKE_PROD_1} patch configmanagement config-management \
    --type merge \
    --patch "$(cat ${WORKDIR}/tmp/config-management-patch.yaml)"
else
  export KUBECONFIG=${WORKDIR}/kubeconfig/workshop-config
fi

echo -e "\n"
echo_cyan "*** $EKS_PROD_1 Token ***\n"
cat ${WORKDIR}/kubeconfig/$EKS_PROD_1-ksa-token.txt && echo -e "\n"
echo_cyan "*** $EKS_PROD_2 Token ***\n"
cat ${WORKDIR}/kubeconfig/$EKS_PROD_2-ksa-token.txt && echo -e "\n"
echo_cyan "*** $EKS_STAGE_1 Token ***\n"
cat ${WORKDIR}/kubeconfig/$EKS_STAGE_1-ksa-token.txt && echo -e "\n"

echo_cyan "*** Gitlab Hostname and root password ***\n"
echo -n "http://"
cat $WORKDIR/gitlab/gitlab_creds.txt && echo -e "\n"

chmod 0600 ${WORKDIR}/ssh-keys/ssh-key-private
eval `ssh-agent` && ssh-add ${WORKDIR}/ssh-keys/ssh-key-private
