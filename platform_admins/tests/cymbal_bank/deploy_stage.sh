#!/usr/bin/env bash

# Copyright 2021 Google LLC
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

# Export a SCRIPT_DIR var and make all links relative to SCRIPT_DIR
export SCRIPT_DIR=$(dirname $(readlink -f $0 2>/dev/null) 2>/dev/null || echo "${PWD}/$(dirname $0)")

# Source required include files
source ${SCRIPT_DIR}/../include/display.sh
source ${SCRIPT_DIR}/../include/kubernetes.sh

# Define vars
export STAGE="stage"
export APP_NS="cymbal-bank-${STAGE}"

export EKS1=${EKS_STAGE_1}
export GKE1=${GKE_STAGE_1}

export GSA="cloud-ops@${GOOGLE_PROJECT}.iam.gserviceaccount.com"
export KSA="default"

## Stage 1: Preparation
ASM_REV_LABEL=$(kubectl --context ${GKE1} get deploy -n istio-system -l app=istiod -o jsonpath={.items[*].metadata.labels.'istio\.io\/rev'})

sed -e "s/ASM_REV_LABEL/${ASM_REV_LABEL}/" ${SCRIPT_DIR}/yaml/templates/namespace-patch.yaml >${SCRIPT_DIR}/yaml/overlays/${STAGE}/eks/namespace-patch.yaml
sed -e "s/ASM_REV_LABEL/${ASM_REV_LABEL}/" ${SCRIPT_DIR}/yaml/templates/namespace-patch.yaml >${SCRIPT_DIR}/yaml/overlays/${STAGE}/gke/namespace-patch.yaml

# Create Cloud-Ops GSA secret YAML
kubectl create secret generic cloud-ops-sa --from-file=application_default_credentials.json=${WORKDIR}/cloudopsgsa/cloud_ops_sa_key.json --dry-run=client -oyaml >${SCRIPT_DIR}/yaml/overlays/${STAGE}/eks/cloud-ops-sa-secret.yaml

# Workload Identity for Cloud-Ops GSA/KSA Mapping
sed -e "s/GSA/${GSA}/" ${SCRIPT_DIR}/yaml/templates/default-ksa-patch.yaml >${SCRIPT_DIR}/yaml/overlays/${STAGE}/gke/default-ksa-patch.yaml

gcloud iam service-accounts add-iam-policy-binding $GSA \
    --role roles/iam.workloadIdentityUser \
    --member "serviceAccount:${GOOGLE_PROJECT}.svc.id.goog[${APP_NS}/${KSA}]"

## Stage 2: Deploy
echo -e "\n"
echo_cyan "*** Deploying Cymbal Bank app to ${EKS1} cluster... ***\n"
kubectl --context=${EKS1} apply --kustomize ${SCRIPT_DIR}/yaml/overlays/${STAGE}/eks

echo -e "\n"
echo_cyan "*** Deploying Cymbal Bank app to ${GKE1} cluster... ***\n"
kubectl --context=${GKE1} apply --kustomize ${SCRIPT_DIR}/yaml/overlays/${STAGE}/gke
kubectl --context=${GKE1} --namespace ${APP_NS} delete statefulset/accounts-db
kubectl --context=${GKE1} --namespace ${APP_NS} delete statefulset/ledger-db

## Stage 3: Validation
echo -e "\n"
echo_cyan "*** Verifying all Deployments are Ready in all clusters... ***\n"
is_deployment_ready ${EKS1} ${APP_NS} balancereader
is_deployment_ready ${EKS1} ${APP_NS} contacts
is_deployment_ready ${EKS1} ${APP_NS} frontend
is_deployment_ready ${EKS1} ${APP_NS} ledgerwriter
is_deployment_ready ${EKS1} ${APP_NS} loadgenerator
is_deployment_ready ${EKS1} ${APP_NS} transactionhistory
is_deployment_ready ${EKS1} ${APP_NS} userservice

is_deployment_ready ${GKE1} ${APP_NS} balancereader
is_deployment_ready ${GKE1} ${APP_NS} contacts
is_deployment_ready ${GKE1} ${APP_NS} frontend
is_deployment_ready ${GKE1} ${APP_NS} ledgerwriter
is_deployment_ready ${GKE1} ${APP_NS} loadgenerator
is_deployment_ready ${GKE1} ${APP_NS} transactionhistory
is_deployment_ready ${GKE1} ${APP_NS} userservice

echo -e "\n"
echo_cyan "*** Access Cymbal Bank app in namespace ${APP_NS} by navigating to the following address: ***\n"
echo -n "http://"
kubectl --context=${GKE1} -n istio-system get svc istio-ingressgateway -o jsonpath={.status.loadBalancer.ingress[].ip}
echo -e "\n"
