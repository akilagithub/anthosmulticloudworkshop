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

# Export a SCRIPT_DIR var and make all links relative to SCRIPT_DIR
export SCRIPT_DIR=$(dirname $(readlink -f $0 2>/dev/null) 2>/dev/null || echo "${PWD}/$(dirname $0)")

# Source required include files
source ${SCRIPT_DIR}/include/display.sh
source ${SCRIPT_DIR}/include/kubernetes.sh

# Define vars
export GKE1=${GKE_DEV_1}
export GKE2=${GKE_DEV_2}
export DEV_NS=ob-dev

## Stage 1: Preparation
ASM_REV_LABEL=asm-managed-rapid

sed -e "s/ASM_REV_LABEL/${ASM_REV_LABEL}/" ${SCRIPT_DIR}/ob/dev/gke1/ob-namespace-patch.yaml_tmpl > ${SCRIPT_DIR}/ob/dev/gke1/ob-namespace-patch.yaml
sed -e "s/ASM_REV_LABEL/${ASM_REV_LABEL}/" ${SCRIPT_DIR}/ob/dev/gke2/ob-namespace-patch.yaml_tmpl > ${SCRIPT_DIR}/ob/dev/gke2/ob-namespace-patch.yaml

## Stage 2: Deploy
echo -e "\n"
echo_cyan "*** Deploying Online Boutique app to ${GKE1} cluster... ***\n"
kubectl --context=${GKE1} apply -k ${SCRIPT_DIR}/ob/dev/gke1
echo -e "\n"
echo_cyan "*** Deploying Online Boutique app to ${GKE2} cluster... ***\n"
kubectl --context=${GKE2} apply -k ${SCRIPT_DIR}/ob/dev/gke2

## Stage 3: Validation
echo -e "\n"
echo_cyan "*** Verifying all Deployments are Ready in all clusters... ***\n"
is_deployment_ready ${GKE1} ${DEV_NS} emailservice
is_deployment_ready ${GKE1} ${DEV_NS} checkoutservice
is_deployment_ready ${GKE1} ${DEV_NS} frontend

is_deployment_ready ${GKE1} ${DEV_NS} paymentservice
is_deployment_ready ${GKE1} ${DEV_NS} productcatalogservice
is_deployment_ready ${GKE1} ${DEV_NS} currencyservice

is_deployment_ready ${GKE2} ${DEV_NS} shippingservice
is_deployment_ready ${GKE2} ${DEV_NS} adservice
is_deployment_ready ${GKE2} ${DEV_NS} loadgenerator

is_deployment_ready ${GKE2} ${DEV_NS} cartservice
is_deployment_ready ${GKE2} ${DEV_NS} recommendationservice

echo -e "\n"
echo_cyan "*** Access Online Boutique app in namespace ${DEV_NS} by navigating to the following address: ***\n"
echo -n "http://"
kubectl --context=${GKE1} -n istio-ingress-general get svc istio-ingressgateway -o jsonpath={.status.loadBalancer.ingress[].ip}
echo -e "\n"
